// web/zigc/client.js — the page's side of the in-browser Zig compiler (web/zigc/worker.js).
//
//   import { getCompiler, CompileError } from './web/zigc/client.js';
//   const zc = getCompiler({ onProgress: (p) => ... });        // one per page
//   const r = await zc.compile('My_Theme', source, { onPhase, onLog, signal, timeoutMs });
//   // r: { ok, gate1, build, wasm, crash, ms, info } (zigc.js compileTheme), or a CompileError
//
// Every outcome is bounded and the compiler never stays broken:
//   - loading: each download is tried 3 times (worker.js); the whole load fails after 45 s with
//     no progress, and the next compile starts a fresh load;
//   - compiling: `timeoutMs` (60 s), then the Worker is terminated and the error carries Zig's
//     output so far;
//   - a Worker that crashes, posts an unreadable message or traps inside zig.wasm is terminated;
//     the next compile gets a fresh one. A crash with a /cache restored from IndexedDB is
//     retried once with that cache dropped, in case the cache caused it;
//   - `signal` (an AbortSignal) cancels: the Worker is terminated at once.
// The compiler loads only when first asked for, so pages that never compile download nothing.

export class CompileError extends Error {
  /// kind: 'load' | 'timeout' | 'cancelled' | 'worker'. log: Zig's output so far.
  constructor(kind, message, extra = {}) { super(message); this.kind = kind; Object.assign(this, extra); }
}

const LOAD_STALL_MS = 45000;
let compiler = null;

export function getCompiler({ base = new URL('./build/', import.meta.url), onProgress } = {}) {
  if (compiler) { if (onProgress) compiler.listeners.add(onProgress); return compiler; }
  const listeners = new Set(onProgress ? [onProgress] : []);
  let w = null;          // the current Worker, or null
  let ready = null;      // its init promise
  let info = null;       // its init info
  let current = null;    // the compile in flight: { id, res, rej, onPhase, onLog, log }
  let nextId = 1;
  let dropCacheNext = false;
  let generation = 0;    // bumped by kill(), so a dead Worker's late messages are ignored
  const stats = { workersStarted: 0, workersKilled: 0, lastKill: null };

  function kill(why) {
    generation++;
    if (w) { w.terminate(); stats.workersKilled++; stats.lastKill = why; }
    w = null; ready = null; info = null;
  }

  function start() {
    const gen = ++generation;
    stats.workersStarted++;
    w = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
    let readyRes, readyRej;
    ready = new Promise((res, rej) => { readyRes = res; readyRej = rej; });
    let stall = null;
    const armStall = () => { clearTimeout(stall); stall = setTimeout(() => fail(new CompileError('load', `the compiler did not load: no progress for ${LOAD_STALL_MS / 1000} s`)), LOAD_STALL_MS); };
    const fail = (err) => {
      clearTimeout(stall);
      if (gen !== generation) return;
      const c = current; current = null;
      kill(err.message);
      readyRej(err);
      if (c) c.rej(err.kind ? err : new CompileError('worker', err.message, { log: c.log }));
    };
    w.onmessage = (e) => {
      if (gen !== generation) return;
      const m = e.data;
      if (m.type === 'progress') { armStall(); for (const f of listeners) f(m); }
      else if (m.type === 'ready') { clearTimeout(stall); info = m.info; readyRes(m.info); }
      else if (m.type === 'error' && m.stage === 'load') fail(new CompileError('load', `the compiler did not load: ${m.error}`));
      else if (!current || m.id !== current.id) { /* a message for a compile that was given up */ }
      else if (m.type === 'phase') current.onPhase?.(m.phase);
      else if (m.type === 'log') { current.log += m.text; current.onLog?.(m.text); }
      else if (m.type === 'result') { const c = current; current = null; c.res(m.result); }
      else if (m.type === 'error') fail(new CompileError('worker', `the compiler failed: ${m.error}`));
    };
    w.onerror = (e) => { e.preventDefault?.(); fail(new CompileError('worker', `the compiler's Worker stopped: ${e.message || 'no message (out of memory?)'}`)); };
    w.onmessageerror = () => fail(new CompileError('worker', 'the compiler sent a message the page could not read'));
    armStall();
    w.postMessage({ type: 'init', base: String(base), dropCache: dropCacheNext });
    dropCacheNext = false;
    ready.catch(() => {});
    return ready;
  }

  /// One run in the current Worker (started if needed), bounded and cancellable.
  async function once(name, source, { onPhase, onLog, signal, timeoutMs }) {
    if (signal?.aborted) throw new CompileError('cancelled', 'cancelled');
    const abortP = new Promise((_, rej) => signal?.addEventListener('abort', () => rej(new CompileError('cancelled', 'cancelled')), { once: true }));
    abortP.catch(() => {});
    try {
      await Promise.race([ready || start(), abortP]);
    } catch (e) {
      if (e.kind === 'cancelled') kill('cancelled while loading');
      throw e;
    }
    const loadedInfo = info;
    const id = nextId++;
    const t0 = performance.now();
    const run = new Promise((res, rej) => {
      current = { id, res, rej, onPhase, onLog, log: '' };
      w.postMessage({ type: 'compile', id, name, source });
    });
    let timer;
    const timeout = new Promise((_, rej) => { timer = setTimeout(() => rej(new CompileError('timeout', `the compiler did not finish in ${Math.round(timeoutMs / 1000)} s`)), timeoutMs); });
    try {
      const r = await Promise.race([run, timeout, abortP]);
      r.info = loadedInfo;
      r.wallMs = performance.now() - t0;
      if (r.recycle) kill(r.crash ? `crash: ${r.crash.kind}` : 'memory');
      return r;
    } catch (e) {
      const mine = current && current.id === id;
      const log = mine ? current.log : (e.log || '');
      if (mine) { current = null; kill(e.kind || 'error'); }
      if (e instanceof CompileError) { e.log = log; e.info = loadedInfo; e.wallMs = performance.now() - t0; }
      throw e;
    } finally { clearTimeout(timer); }
  }

  compiler = {
    listeners,
    stats,
    /// Start loading now (a drag over the page, the editor's focus): errors wait for compile().
    warm() { if (!ready) start(); },
    async compile(name, source, { onPhase, onLog, signal, timeoutMs = 60000 } = {}) {
      const r = await once(name, source, { onPhase, onLog, signal, timeoutMs });
      if (r.crash && r.info?.restoredCacheFiles > 0) {
        // The cache this Worker restored may be what broke: once, try again without it.
        dropCacheNext = true;
        const again = await once(name, source, { onPhase, onLog, signal, timeoutMs });
        again.retriedWithoutCache = { first: r.crash };
        return again;
      }
      return r;
    },
    /// Forget the persisted /cache (the next Worker starts clean).
    dropCache() { dropCacheNext = true; kill('cache dropped'); },
    reset(why = 'reset') { if (current) { current.rej(new CompileError('cancelled', why)); current = null; } kill(why); },
  };
  return compiler;
}

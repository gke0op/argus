// web/zigc/client.js — the page's side of the in-browser Zig compiler (web/zigc/worker.js).
//
//   import { getCompiler } from './web/zigc/client.js';
//   const zc = getCompiler({ onProgress: (p) => ... });   // starts loading at once, once per page
//   const info = await zc.ready;                            // sizes, cache state, load time
//   const r = await zc.compile('My_Theme', source, (phase) => ...);
//   // r: { ok, gate1: { ok, log, ms }, build: { ok, log, ms } | null, wasm, ms }
//
// The Worker loads zig.wasm (Zig 0.17.0) and the std sources only when first asked for, so pages
// that never compile never download them.

let compiler = null;

export function getCompiler({ base = new URL('./build/', import.meta.url), onProgress } = {}) {
  if (compiler) { if (onProgress) compiler.listeners.add(onProgress); return compiler; }
  const w = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
  const listeners = new Set(onProgress ? [onProgress] : []);
  const pending = new Map();
  let nextId = 1;
  let readyRes, readyRej;
  const ready = new Promise((res, rej) => { readyRes = res; readyRej = rej; });
  w.onmessage = (e) => {
    const m = e.data;
    if (m.type === 'progress') for (const f of listeners) f(m);
    else if (m.type === 'ready') readyRes(m.info);
    else if (m.type === 'phase') pending.get(m.id)?.onPhase?.(m.phase);
    else if (m.type === 'result') { pending.get(m.id)?.res(m.result); pending.delete(m.id); }
    else if (m.type === 'error') {
      if (m.id !== undefined && pending.has(m.id)) { pending.get(m.id).rej(new Error(m.error)); pending.delete(m.id); }
      else readyRej(new Error(m.error));
    }
  };
  w.onerror = (e) => { const err = new Error(e.message || 'compiler worker failed'); readyRej(err); for (const p of pending.values()) p.rej(err); pending.clear(); };
  w.postMessage({ type: 'init', base: String(base) });
  compiler = {
    ready,
    listeners,
    compile(name, source, onPhase) {
      return ready.then(() => new Promise((res, rej) => {
        const id = nextId++;
        pending.set(id, { res, rej, onPhase });
        w.postMessage({ type: 'compile', id, name, source });
      }));
    },
  };
  return compiler;
}

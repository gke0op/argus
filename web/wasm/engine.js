// web/wasm/engine.js — start an Argus theme's wasm module on a pool of Workers.
//
// Threaded (the page is cross-origin isolated, so SharedArrayBuffer exists): NAME.mt.wasm on one
// shared WebAssembly.Memory; a leader Worker owns the theme and, for a CPU kernel theme, helper
// Workers (one per remaining core) run the kernel's rows. Otherwise NAME.st.wasm in one Worker,
// with its own memory; frames come back as copies.
// Used by host.js (live canvas) and gates.js (the harness gates), in browsers and in Node.

const MEM_PAGES = 64;          // matches --initial-memory=4194304 (Makefile web-wasm)
const MEM_MAX_PAGES = 16384;   // matches --max-memory=1073741824
const HELPER_STACK = 1 << 20;

export function canThread() {
  return typeof SharedArrayBuffer !== 'undefined' && (typeof crossOriginIsolated === 'undefined' || crossOriginIsolated);
}

export function hardwareThreads() {
  if (typeof navigator !== 'undefined' && navigator.hardwareConcurrency) return navigator.hardwareConcurrency;
  return 4;
}

async function defaultWorker(url) {
  if (typeof Worker !== 'undefined') {
    const w = new Worker(url, { type: 'module' });
    return {
      post: (m, t) => w.postMessage(m, t),
      on: (f) => { w.onmessage = (e) => f(e.data); w.onerror = (e) => f({ type: 'error', error: e.message }); },
      terminate: () => w.terminate(),
    };
  }
  const { Worker: NodeWorker } = await import('node:worker_threads');
  const w = new NodeWorker(url);
  return {
    post: (m, t) => w.postMessage(m, t),
    on: (f) => { w.on('message', f); w.on('error', (e) => f({ type: 'error', error: String(e && e.stack || e) })); },
    terminate: () => w.terminate(),
  };
}

class Channel {
  constructor(w) {
    this.w = w;
    this.next = 1;
    this.pending = new Map();
    this.listeners = [];
    this.loaded = new Promise((res) => { this._loaded = res; });
    w.on((m) => {
      if (m.type === 'loaded') return this._loaded();
      if (m.id !== undefined && this.pending.has(m.id)) {
        const p = this.pending.get(m.id);
        this.pending.delete(m.id);
        return m.ok ? p.res(m.result) : p.rej(new Error(m.error));
      }
      if (m.type === 'error') {
        for (const p of this.pending.values()) p.rej(new Error(m.error));
        this.pending.clear();
      }
      for (const f of this.listeners) f(m);
    });
  }
  call(type, args = {}, transfer = []) {
    const id = this.next++;
    return new Promise((res, rej) => {
      this.pending.set(id, { res, rej });
      this.w.post({ ...args, type, id }, transfer);
    });
  }
}

/// Fetch and compile NAME.{mt,st}.wasm from `base`. Returns { module, threaded, bytes }.
export async function loadModule(base, name, { threads = 'auto' } = {}) {
  const wantThreads = threads !== 1 && canThread();
  const variant = wantThreads ? 'mt' : 'st';
  const url = new URL(`${name}.${variant}.wasm`, base);
  let bytes;
  if (url.protocol === 'file:') {
    const fs = await import('node:fs');
    bytes = fs.readFileSync(url);
  } else {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
    bytes = new Uint8Array(await r.arrayBuffer());
  }
  const module = await WebAssembly.compile(bytes);
  return { module, threaded: wantThreads, bytes: bytes.byteLength, variant };
}

/// Compile a module from bytes the caller has (an uploaded NAME.mt.wasm or NAME.st.wasm). The
/// threaded build imports a shared memory; it runs threaded only on an isolated page.
export async function moduleFromBytes(bytes) {
  const module = await WebAssembly.compile(bytes);
  // Both builds import env.memory; only the threaded one needs it shared. Try a plain memory.
  const env = (memory) => ({ env: { memory, web_phase() {}, web_now_us: () => 0 } });
  let threaded = false;
  try {
    await WebAssembly.instantiate(module, env(new WebAssembly.Memory({ initial: MEM_PAGES, maximum: MEM_MAX_PAGES })));
  } catch (plainErr) {
    if (!canThread()) throw new Error(`cannot link this module single-threaded (${plainErr.message}); if it is NAME.mt.wasm, upload NAME.st.wasm: this page is not cross-origin isolated`);
    await WebAssembly.instantiate(module, env(new WebAssembly.Memory({ initial: MEM_PAGES, maximum: MEM_MAX_PAGES, shared: true })));
    threaded = true;
  }
  return { module, threaded, bytes: bytes.byteLength, variant: threaded ? 'mt' : 'st' };
}

/// Start an engine: { info, leader (Channel), threads, memory, onPhase(f), terminate() }.
/// `threads`: 'auto' (every core) or a number of Workers in all (1 = no helpers).
export async function startEngine({ module, threaded, threads = 'auto', makeWorker = defaultWorker, workerUrl = new URL('./worker.js', import.meta.url) }) {
  // Threaded: one shared memory, created here and handed to every Worker. Single-threaded: a
  // plain memory cannot be posted, so the leader creates its own (and frames come back as copies).
  const memory = threaded ? new WebAssembly.Memory({ initial: MEM_PAGES, maximum: MEM_MAX_PAGES, shared: true }) : null;
  const workers = [];
  const leader = new Channel(await makeWorker(workerUrl));
  workers.push(leader.w);
  await leader.loaded;
  const info = await leader.call('init', { module, memory, pages: [MEM_PAGES, MEM_MAX_PAGES], role: 'leader' });

  let helpers = 0;
  if (threaded && info.kernelPool) {
    const total = threads === 'auto' ? hardwareThreads() : Math.max(1, threads | 0);
    helpers = Math.max(0, total - 1);
  }
  if (helpers > 0) {
    const stacks = await leader.call('stacks', { n: helpers, stackSize: HELPER_STACK });
    await Promise.all(stacks.map(async ({ stackTop, tls }) => {
      const ch = new Channel(await makeWorker(workerUrl));
      workers.push(ch.w);
      await ch.loaded;
      await new Promise((res, rej) => {
        ch.listeners.push((m) => { if (m.type === 'ready') res(); if (m.type === 'error') rej(new Error(m.error)); });
        ch.w.post({ type: 'init', module, memory, role: 'helper', stackTop, tls });
      });
    }));
  }
  return {
    info,
    leader,
    memory,
    threaded,
    threads: 1 + helpers,
    onPhase(f) { leader.listeners.push((m) => { if (m.type === 'phase') f(m.phase); }); },
    terminate() { for (const w of workers) w.terminate(); },
  };
}

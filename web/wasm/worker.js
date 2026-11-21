// web/wasm/worker.js — one Worker of an Argus wasm engine (engine.js starts them).
//
// leader: the module's first instance. It owns the theme: step, draw, the gate run. When the
//         theme is a CPU kernel (themes/cpu) its draw hands rows to the helpers.
// helper: another instance on the same shared memory, on its own stack. It sleeps on the kernel's
//         epoch word and runs argus_kernel_help (the kernel's own Job.run) each time it moves.
// Runs in browsers (module Worker) and in Node (worker_threads), for the tests.

const isNode = typeof self === 'undefined' && typeof process !== 'undefined';
let post;
let onMessage;
if (isNode) {
  const { parentPort } = await import('node:worker_threads');
  post = (m, t) => parentPort.postMessage(m, t);
  onMessage = (f) => parentPort.on('message', f);
} else {
  post = (m, t) => self.postMessage(m, t);
  onMessage = (f) => { self.onmessage = (e) => f(e.data); };
}

let x = null; // exports
let memory = null;
let threaded = false;

function instantiate(module, mem) {
  memory = mem;
  const env = {
    memory: mem,
    web_now_us: () => performance.now() * 1000,
    web_phase: (p) => post({ type: 'phase', phase: p }),
  };
  return new WebAssembly.Instance(module, { env }).exports;
}

const u32 = (ptr, n) => new Uint32Array(memory.buffer, ptr, n);
const f64 = (ptr, n) => new Float64Array(memory.buffer, ptr, n);

const REPORT_FIELDS = ['status', 'stateful', 'width', 'height', 'padded_stride', 'n_frames', 'watchdog_ok',
  'allocs_init', 'bytes_live', 'allocs_after', 'nan_detected', 'canary_corrupted', 'distinct_pixels',
  'bad_alpha_pixels', 'animated_pixels', 'alloc_ok', 'pixels_ok', 'motion_ok', 'budget_ok', 'pass', 'final_ptr'];

function readReport(ptr) {
  const u = u32(ptr, 22);
  const r = {};
  REPORT_FIELDS.forEach((k, i) => { r[k] = u[i]; });
  const f = f64(ptr + 88, 2);
  r.avg_us = f[0];
  r.worst_us = f[1];
  return r;
}

// In a single-threaded engine the memory is not shared: hand the page a copy of the pixels.
function pixelsOut(ptr, n) {
  if (threaded) return null;
  return new Uint8ClampedArray(memory.buffer, ptr, n * 4).slice();
}

const handlers = {
  init({ module, memory: mem, pages, role, stackTop, tls }) {
    x = instantiate(module, mem || new WebAssembly.Memory({ initial: pages[0], maximum: pages[1] }));
    threaded = x.web_threaded() === 1;
    if (role === 'helper') {
      x.web_thread_init(stackTop, tls);
      post({ type: 'ready' });
      helperLoop();
      return null;
    }
    return {
      abi: x.web_abi(), lanes: x.web_lanes(), threaded,
      tlsSize: x.web_tls_size(), tlsAlign: x.web_tls_align(),
      kernelPool: typeof x.argus_kernel_help === 'function',
    };
  },
  stacks({ n, stackSize }) {
    const out = [];
    const tlsSize = x.web_tls_size();
    for (let i = 0; i < n; i++) {
      const base = x.web_alloc(stackSize);
      if (!base) throw new Error('out of memory for helper stacks');
      const tls = tlsSize ? x.web_alloc(tlsSize + x.web_tls_align()) : 0;
      const tlsAligned = tls ? Math.ceil(tls / x.web_tls_align()) * x.web_tls_align() : 0;
      out.push({ stackTop: base + stackSize, tls: tlsAligned });
    }
    return out;
  },
  liveInit({ w, h, scale }) {
    const ptr = x.web_live_init(w, h, scale);
    return { ptr, w, h };
  },
  frame({ dt, w, h, ptr }) {
    const t0 = performance.now();
    x.web_live_frame(dt);
    const cpuMs = performance.now() - t0;
    const pixels = pixelsOut(ptr, w * h);
    return { result: { cpuMs, nan: x.web_live_has_nan(), pagesGrown: x.web_pages_grown(), pixels }, transfer: pixels ? [pixels.buffer] : [] };
  },
  gates({ w, h, frames }) {
    const r = readReport(x.web_gates_run(w, h, frames));
    const pixels = r.status === 0 ? pixelsOut(r.final_ptr, w * h) : null;
    return { result: { report: r, pixels }, transfer: pixels ? [pixels.buffer] : [] };
  },
  render({ w, h, frames }) {
    const ptr = x.web_render_frames(w, h, frames);
    const pixels = ptr ? pixelsOut(ptr, w * h) : null;
    return { result: { ptr, pixels }, transfer: pixels ? [pixels.buffer] : [] };
  },
  liveDeinit() {
    x.web_live_deinit();
    return {};
  },
};

function helperLoop() {
  const i32 = new Int32Array(memory.buffer);
  const idx = x.argus_kernel_epoch() >> 2;
  let seen = Atomics.load(i32, idx);
  for (;;) {
    Atomics.wait(i32, idx, seen);
    seen = Atomics.load(i32, idx);
    x.argus_kernel_help();
  }
}

onMessage((m) => {
  const h = handlers[m.type];
  try {
    const out = h(m);
    if (out === null) return;
    if (out && out.result !== undefined) post({ id: m.id, ok: true, result: out.result }, out.transfer);
    else post({ id: m.id, ok: true, result: out });
  } catch (e) {
    post({ id: m.id, ok: false, error: String(e && e.stack || e) });
  }
});
post({ type: 'loaded' });

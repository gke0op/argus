// web/wasm/gates.js — the harness's 8 gates on a wasm theme, in the page (or in Node).
//
// Gate 1 (compile) is the build's: `make web-wasm-all` records whether the theme compiled
// (build/NAME.compile.txt, manifest.json), and here the module must also compile and link in
// this browser. Gates 2-8 run src/harness_gates.zig inside the theme's own module
// (runtime.zig web_gates_run): the same watchdog, frames, buffers and checks as `make harness`,
// so the verdict is the native harness's by construction. What only a host can do is done here:
// a time limit, as Argus.app's verifier has (space_config.zig verify_timeout_ms, 10 s), so a
// theme that hangs is stopped and failed instead of hanging the page.

import { loadModule, startEngine } from './engine.js';

export const GATES = [
  { id: 1, name: 'Compilation', key: 'compile' },
  { id: 2, name: 'Single-alloc arena', key: 'alloc' },
  { id: 3, name: 'Watchdog 320x200', key: 'watchdog' },
  { id: 4, name: 'Stride canary', key: 'stride' },
  { id: 5, name: 'Pixel & alpha integrity', key: 'pixels' },
  { id: 6, name: 'Temporal motion', key: 'motion' },
  { id: 7, name: 'Numerical stability', key: 'nan' },
  { id: 8, name: 'Frame budget', key: 'budget' },
];

const PHASES = { 1: 'watchdog', 2: 'init', 3: 'frames', 4: 'inspect', 5: 'done' };

async function readText(url) {
  try {
    if (url.protocol === 'file:') return (await import('node:fs')).readFileSync(url, 'utf8');
    const r = await fetch(url);
    return r.ok ? await r.text() : null;
  } catch { return null; }
}

/// Run the gates on build NAME. opts: base (build dir URL), threads, width/height/frames (the
/// harness's 1920x1200, 120), limitMs: { watchdog, init, frames } time limits per phase.
/// Returns { name, gates: [{id, name, pass, detail}], pass, report (runtime's numbers), text
/// (the harness's report layout), pixels (the final frame, RGBA) or null, timedOut }.
export async function runGates(name, opts = {}) {
  const base = opts.base || new URL('./build/', import.meta.url);
  const width = opts.width ?? 1920, height = opts.height ?? 1200, frames = opts.frames ?? 120;
  // The watchdog gets Argus.app's 10 s (its verifier runs that probe). The harness itself has no
  // limit; the page needs one, so init and the frames get room even for a slow machine.
  const limit = { start: 15000, watchdog: 10000, init: 120000, frames: 30000 + frames * 2000, inspect: 30000, ...(opts.limitMs || {}) };
  const out = { name, width, height, frames, gates: [], pass: false, report: null, text: '', pixels: null, timedOut: null, threads: 0, variant: '' };
  const gate = (id, pass, detail) => out.gates.push({ ...GATES[id - 1], pass, detail });

  // Gate 1: the build's compile, then this browser's.
  // opts.module: a module the caller compiled (an uploaded .wasm, see moduleFromBytes); Gate 1 is
  // then the uploader's build, and this browser's compile and link.
  const compileLog = opts.module ? null : await readText(new URL(`${name}.compile.txt`, base));
  let m;
  try {
    m = opts.module ?? await loadModule(base, name, { threads: opts.threads ?? 'auto' });
  } catch (e) {
    const log = (compileLog || '').trim();
    gate(1, false, log ? `zig build-exe failed:\n${log}` : `no module: ${e.message}`);
    for (let i = 2; i <= 8; i++) gate(i, null, 'not run');
    out.text = reportText(out);
    return out;
  }
  out.variant = m.variant;
  out.wasmKB = m.bytes / 1024;
  // opts.gate1: the caller's own Gate 1 line (the bench page's in-browser compile).
  gate(1, true, opts.gate1 ?? (opts.module
    ? `uploaded ${m.variant}.wasm (${(m.bytes / 1024).toFixed(1)} KB): built outside this page, compiled and linked here`
    : `zig build-exe -target wasm32-freestanding -O ReleaseFast (${m.variant}, ${(m.bytes / 1024).toFixed(1)} KB), compiled and linked here`));

  // opts.signal (an AbortSignal) cancels: the Workers are terminated and out.cancelled is set.
  const cancelled = opts.signal ? new Promise((resolve) => {
    if (opts.signal.aborted) resolve({ cancelled: true });
    opts.signal.addEventListener('abort', () => resolve({ cancelled: true }), { once: true });
  }) : new Promise(() => {});
  const notRun = (from, why = 'not run') => { for (let i = from; i <= 8; i++) gate(i, null, why); };
  // Starting the Workers is bounded too (limit.start): a browser that cannot start them fails here.
  const starting = startEngine({ module: m.module, threaded: m.threaded, threads: opts.threads ?? 'auto' });
  let startTimer;
  const st = await Promise.race([
    starting.then((engine) => ({ engine }), (error) => ({ error })),
    new Promise((resolve) => { startTimer = setTimeout(() => resolve({ timeout: true }), limit.start ?? 15000); }),
    cancelled,
  ]);
  clearTimeout(startTimer);
  if (!st.engine) {
    starting.then((e) => e.terminate(), () => {});
    if (st.cancelled) { out.cancelled = true; notRun(2, 'cancelled'); out.text = reportText(out); return out; }
    gate(2, null, 'not run');
    gate(3, false, st.timeout ? `the module did not start in a Worker within ${((limit.start ?? 15000) / 1000).toFixed(0)} s` : `the module did not start in a Worker: ${String(st.error && st.error.message || st.error).split('\n')[0]}`);
    notRun(4);
    out.text = reportText(out);
    return out;
  }
  const engine = st.engine;
  out.threads = engine.threads;
  let phase = 'watchdog';
  let timer = null;
  const timeout = new Promise((resolve) => {
    const arm = () => {
      clearTimeout(timer);
      timer = setTimeout(() => resolve({ timeout: phase }), limit[phase] ?? 10000);
    };
    engine.onPhase((p) => { phase = PHASES[p] || phase; if (opts.onPhase) opts.onPhase(phase); arm(); });
    arm();
  });
  const t0 = performance.now();
  // A theme that traps (a Zig panic, out of memory, a stack overflow) rejects the call.
  const res = await Promise.race([engine.leader.call('gates', { w: width, h: height, frames }).catch((e) => ({ crash: String(e && e.message || e) })), timeout, cancelled]);
  clearTimeout(timer);
  out.wallMs = performance.now() - t0;

  if (res.cancelled) {
    engine.terminate();
    out.cancelled = true;
    notRun(2, 'cancelled');
    out.text = reportText(out);
    return out;
  }
  if (res.crash) {
    engine.terminate();
    const msg = res.crash.split('\n')[0].replace(/^(Error: )+/, '');
    out.crashed = { phase, message: msg };
    // As for a hang (below): the watchdog or init is Gate 3's, the frame loop Gate 8's.
    if (phase === 'watchdog' || phase === 'init') {
      gate(2, null, 'not run');
      gate(3, false, `crashed in the ${phase === 'watchdog' ? '320x200 probe' : 'main init'}: ${msg}`);
      notRun(4);
    } else {
      for (let i = 2; i <= 7; i++) gate(i, null, 'not run');
      gate(8, false, `crashed in the frame loop: ${msg}`);
    }
    out.gates.sort((a, b) => a.id - b.id);
    out.text = reportText(out);
    return out;
  }

  if (res.timeout) {
    engine.terminate();
    out.timedOut = res.timeout;
    const secs = (limit[res.timeout] / 1000).toFixed(0);
    if (res.timeout === 'watchdog' || res.timeout === 'init') {
      gate(2, null, 'not run');
      gate(3, false, `hung: stopped after ${secs} s in the ${res.timeout === 'watchdog' ? '320x200 probe' : 'main init'}`);
      for (let i = 4; i <= 8; i++) gate(i, null, 'not run');
    } else {
      for (let i = 2; i <= 7; i++) gate(i, null, 'not run');
      gate(8, false, `hung: stopped after ${secs} s in the frame loop`);
    }
    out.gates.sort((a, b) => a.id - b.id);
    out.text = reportText(out);
    return out;
  }

  const r = res.report;
  out.report = r;
  if (r.status !== 0) {
    const why = { 1: 'exports neither the stateful nor the stateless ABI', 2: 'argus_theme_init returned null at 1920x1200', 3: 'out of memory' }[r.status];
    gate(2, null, 'not run');
    gate(3, null, 'not run');
    for (let i = 4; i <= 8; i++) gate(i, null, 'not run');
    out.gates[1] = { ...GATES[1], pass: false, detail: why };
    engine.terminate();
    out.text = reportText(out);
    return out;
  }
  out.pixels = res.pixels || new Uint8Array(engine.memory.buffer, r.final_ptr, width * height * 4).slice();
  engine.terminate();

  gate(2, !!r.alloc_ok, `allocs at init ${r.allocs_init} (${r.bytes_live} bytes), after init ${r.allocs_after}`);
  gate(3, !!r.watchdog_ok, r.watchdog_ok ? 'init + step + draw at 320x200 (stride 328), padding intact' : 'failed at 320x200');
  gate(4, !r.canary_corrupted, r.canary_corrupted ? 'wrote into stride padding' : `0 out-of-bounds canary writes (stride ${r.padded_stride})`);
  gate(5, !!r.pixels_ok, `${r.distinct_pixels} / ${width * height} non-bg pixels, alpha=0 count ${r.bad_alpha_pixels}`);
  gate(6, !!r.motion_ok, `${r.animated_pixels} / ${width * height} visibly animated pixels (min 2000)`);
  gate(7, !r.nan_detected, r.nan_detected ? 'NaN/Inf detected' : 'clean');
  gate(8, !!r.budget_ok, `avg ${r.avg_us.toFixed(1)} us (${(1e6 / Math.max(0.1, r.avg_us)).toFixed(1)} FPS), worst ${r.worst_us.toFixed(1)} us, budget 16667.0 us, ${engine.threads} thread${engine.threads > 1 ? 's' : ''}`);
  out.pass = !!r.pass;
  out.text = reportText(out);
  return out;
}

/// The native harness's report layout (src/theme_harness.zig), for side-by-side reading.
export function reportText(o) {
  const r = o.report;
  const L = [];
  L.push('========================================================================');
  L.push(' ARGUS HEADLESS THEME HARNESS (Zig 0.17.0, wasm32) // VERIFICATION REPORT');
  L.push('------------------------------------------------------------------------');
  L.push(` Theme             : ${o.name} (${r ? (r.stateful ? 'Stateful SDK Contract' : 'Stateless C-ABI') : '-'}; ${o.variant || '-'}, ${o.threads || 0} thread${o.threads === 1 ? '' : 's'})`);
  if (!r) {
    for (const x of o.gates) L.push(` Gate ${x.id} ${x.name.padEnd(22)}: ${x.pass === null ? 'not run' : x.pass ? 'PASS' : 'FAIL'}${x.detail ? ' (' + x.detail.split('\n')[0] + ')' : ''}`);
    L.push(' Verdict           : FAIL');
    L.push('========================================================================');
    return L.join('\n');
  }
  L.push(` Resolution        : ${r.width}x${r.height} (tested stride=${r.padded_stride}, stride=${r.width}, and 320x200 watchdog)`);
  L.push(` Frames Rendered   : ${r.n_frames} (fixed dt = 0.008000)`);
  L.push(` Avg Frame Time    : ${r.avg_us.toFixed(1)} us (${(1e6 / Math.max(0.1, r.avg_us)).toFixed(1)} FPS) | Budget: 16667.0 us`);
  L.push(` Worst Frame Time  : ${r.worst_us.toFixed(1)} us`);
  L.push(` Allocs at Init    : ${r.allocs_init} (${r.bytes_live} bytes)`);
  L.push(` Allocs after Init : ${r.allocs_after}`);
  L.push(` Watchdog 320x200  : ${r.watchdog_ok ? 'PASS' : 'FAIL (crashed or failed at 320x200)'}`);
  L.push(` Stride Guard      : ${r.canary_corrupted ? 'FAIL (wrote into stride padding!)' : 'CLEAN (0 out-of-bounds canary writes)'}`);
  L.push(` NaN / Inf Check   : ${r.nan_detected ? 'FAIL (NaN/Inf detected!)' : 'CLEAN'}`);
  L.push(` Pixel Variance    : ${r.distinct_pixels} / ${r.width * r.height} non-bg pixels (alpha=0 count: ${r.bad_alpha_pixels})`);
  L.push(` Temporal Motion   : ${r.animated_pixels} / ${r.width * r.height} visibly animated pixels (min required: 2000)`);
  L.push(` Verdict           : ${r.pass ? 'PASS' : 'FAIL'}`);
  L.push('========================================================================');
  return L.join('\n');
}

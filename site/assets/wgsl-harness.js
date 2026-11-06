// site/assets/wgsl-harness.js: the Metal theme harness (src/theme_harness.zig metalHarness),
// run on a WGSL theme in this browser's WebGPU.
//
// Same procedure and checks as `make harness THEME=themes/X.metal`:
//   compile (the WGSL prelude + the theme), then a 320x200 watchdog instance (seed 1, 3 frames);
//   120 frames at 1920x1200 into an rgba32float texture, dt = 1/30 s with a step every frame,
//   seed 0x5EED, the date pinned to 2026-10-20T12:00:00Z, synthetic stats;
//   NaN/Inf over the first and last frame; distinct pixels (> 100) and visibly animated pixels
//   (>= 2000, |dR|+|dG|+|dB| >= 4) on the 8-bit packing of those frames;
//   the average GPU time per frame against the 8,333 us budget of a 120 Hz frame.
// The Metal harness has no alpha gate (the app presents opaque layers); the alpha range is
// reported here but not gated. What only a page can add: a time limit, and GPU device loss.

import { create, getDevice, HARNESS_SEED, HARNESS_DATE } from '../web/host/argus_gpu.js';
import { j2000, parseIsoUtc } from '../web/host/frame.js';

export const BUDGET_US = 8333.0;
export const GATES = [
  { id: 1, name: 'Compilation', line: 'WGSL compiles with the prelude' },
  { id: 2, name: 'Watchdog 320x200', line: 'Watchdog 320x200' },
  { id: 3, name: 'Numerical stability', line: 'NaN / Inf Check' },
  { id: 4, name: 'Pixel variance', line: 'Pixel Variance (> 100 non-bg pixels)' },
  { id: 5, name: 'Temporal motion', line: 'Temporal Motion (>= 2000)' },
  { id: 6, name: 'GPU frame budget', line: 'Avg GPU Frame < 8333 us' },
];

// The harness's packFloat: round(clamp(x, 0, 1) * 255) per channel (Zig @round: halves away from 0).
const pack8 = (x) => Math.round(Math.min(Math.max(x, 0), 1) * 255);

function withTimeout(p, ms, what) {
  let t;
  return Promise.race([p, new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`timeout: ${what} took over ${(ms / 1000).toFixed(0)} s`)), ms); })]).finally(() => clearTimeout(t));
}

/// Run the harness on WGSL `source`. opts: name, frames (120), width/height (1920x1200),
/// onPhase(text). Resolves to { name, gates, pass, text (the report), last (RGBA8 of the final
/// frame), width, height, gpu: { avgUs, worstUs, n, source } }.
export async function runWgslHarness(source, opts = {}) {
  const name = (opts.name || 'Submission').replace(/[^A-Za-z0-9_]/g, '_');
  const frames = Math.max(2, opts.frames ?? 120);
  const width = opts.width ?? 1920, height = opts.height ?? 1200;
  const phase = (s) => opts.onPhase?.(s);
  const out = { name, width, height, frames, gates: [], pass: false, text: '', last: null, gpu: null, dir: null };
  const gate = (id, pass, detail) => { out.gates[id - 1] = { ...GATES[id - 1], pass, detail }; };
  const label = `${name}.wgsl`;

  let device;
  try { device = await getDevice(); } catch (e) {
    gate(1, false, String(e.message ?? e));
    for (let i = 2; i <= 6; i++) gate(i, null, 'not run');
    out.text = failText(`WEBGPU UNAVAILABLE: ${e.message ?? e}`);
    return out;
  }
  let lost = null;
  device.lost.then((info) => { lost = `GPU device lost (${info.reason || 'unknown'}): ${info.message}`; });
  const common = { theme: name, source, seed: HARNESS_SEED, date: HARNESS_DATE, stats: 'synthetic', device };

  // ---- compile -------------------------------------------------------------------------------
  phase('compiling');
  let e;
  const tc = performance.now();
  try {
    e = await withTimeout(create(null, { ...common, offscreen: { width, height, format: 'rgba32float' } }), 60000, 'compile');
  } catch (err) {
    const msg = String(err.message ?? err);
    gate(1, false, msg);
    for (let i = 2; i <= 6; i++) gate(i, null, 'not run');
    out.text = `METAL COMPILE FAILED (here: WGSL, WebGPU): ${label}\n${msg}\nVerdict           : FAIL\n`;
    return out;
  }
  const compileMs = performance.now() - tc;
  gate(1, true, `${label}: prelude + theme, ${source.split('\n').length} lines, pipelines built in ${compileMs.toFixed(0)} ms`);
  out.dir = e.info.directives;
  out.info = e.info;

  try {
    // ---- watchdog: a 320x200 instance must compile and run too ------------------------------
    phase('watchdog 320x200');
    let wdOk = false, wdWhy = '';
    try {
      device.pushErrorScope('validation');
      const wd = await withTimeout(create(null, { ...common, seed: 1, offscreen: { width: 320, height: 200, format: 'rgba32float' } }), 30000, 'watchdog compile');
      for (let i = 0; i < 3; i++) wd.harnessFrame();
      await withTimeout(device.queue.onSubmittedWorkDone(), 10000, 'the 320x200 watchdog');
      const verr = await device.popErrorScope();
      wd.destroy();
      wdOk = !verr && !lost;
      if (verr) wdWhy = verr.message; else if (lost) wdWhy = lost;
    } catch (err) {
      wdWhy = String(err.message ?? err);
      try { await device.popErrorScope(); } catch { /* scope already gone with the device */ }
    }
    gate(2, wdOk, wdOk ? 'compiled and ran 3 frames at 320x200 (seed 1)' : `failed at 320x200: ${wdWhy}`);

    // ---- the run: `frames` frames at width x height -----------------------------------------
    phase(`rendering ${frames} frames at ${width}x${height}`);
    const hasTs = device.features.has('timestamp-query');
    const wall = [];
    let first = null;
    const tRun = performance.now();
    const limitMs = 30000 + frames * 2000;
    device.pushErrorScope('validation');
    for (let i = 0; i < frames; i++) {
      const t = performance.now();
      e.harnessFrame();
      if (i === 0) first = await withTimeout(e.readback(), 20000, 'frame 1');
      else await withTimeout(device.queue.onSubmittedWorkDone(), 20000, `frame ${i + 1}`);
      if (i > 0) wall.push((performance.now() - t) * 1000);
      if (lost) throw new Error(lost);
      if (performance.now() - tRun > limitMs) throw new Error(`timeout: ${frames} frames took over ${(limitMs / 1000).toFixed(0)} s`);
      if (i % 20 === 19) phase(`rendering frame ${i + 1} / ${frames}`);
    }
    const last = await withTimeout(e.readback(), 20000, 'the last frame');
    const verr = await device.popErrorScope();
    if (verr) throw new Error(`WebGPU validation error: ${verr.message}`);
    // Let the last timestamp read-backs land.
    for (let i = 0; i < 20 && e.gpuSamples().length < Math.min(frames, 4); i++) await device.queue.onSubmittedWorkDone();

    // ---- checks, as the harness --------------------------------------------------------------
    phase('checking');
    let nan = false;
    for (const buf of [first, last]) { for (let i = 0; i < buf.length; i++) if (!Number.isFinite(buf[i])) { nan = true; break; } }
    const n = width * height;
    const L = new Uint8ClampedArray(n * 4);
    let distinct = 0, animated = 0, aMin = Infinity, aMax = -Infinity;
    const bg = [pack8(last[0]), pack8(last[1]), pack8(last[2])];
    for (let p = 0, i = 0; p < n; p++, i += 4) {
      const r = pack8(last[i]), g = pack8(last[i + 1]), b = pack8(last[i + 2]);
      L[i] = r; L[i + 1] = g; L[i + 2] = b; L[i + 3] = 255;
      if (r !== bg[0] || g !== bg[1] || b !== bg[2]) distinct++;
      const d = Math.abs(r - pack8(first[i])) + Math.abs(g - pack8(first[i + 1])) + Math.abs(b - pack8(first[i + 2]));
      if (d >= 4) animated++;
      const a = last[i + 3];
      if (a < aMin) aMin = a;
      if (a > aMax) aMax = a;
    }
    out.last = L;

    const samples = hasTs ? e.gpuSamples().slice(-frames).map((ms) => ms * 1000) : wall;
    const avg = samples.length ? samples.reduce((s, x) => s + x, 0) / samples.length : NaN;
    const worst = samples.length ? Math.max(...samples) : NaN;
    out.gpu = { avgUs: avg, worstUs: worst, n: samples.length, source: hasTs ? 'timestamp-query' : 'wall' };

    const budgetOk = Number.isFinite(avg) && avg < BUDGET_US;
    gate(3, !nan, nan ? 'NaN/Inf in the output' : 'clean on the first and last frame');
    gate(4, distinct > 100, `${distinct} / ${n} non-bg pixels`);
    gate(5, animated >= 2000, `${animated} / ${n} visibly animated pixels (min 2000)`);
    gate(6, budgetOk, `avg ${avg.toFixed(1)} us, worst ${worst.toFixed(1)} us over ${samples.length} frames (${hasTs ? 'GPU timestamps' : 'no timestamp-query: wall time from submit to done'}), budget ${BUDGET_US.toFixed(1)} us`);
    out.pass = wdOk && !nan && distinct > 100 && animated >= 2000 && budgetOk;

    // ---- the report, in the Metal harness's layout ------------------------------------------
    const d = out.dir;
    const unix = parseIsoUtc(HARNESS_DATE);
    const jd = j2000(unix, 0);
    const stateful = d.stateW > 0;
    const hasStep = /\bfn\s+argus_step\s*\(/.test(source);
    const R = [];
    R.push('========================================================================');
    R.push(' ARGUS HEADLESS THEME HARNESS (GPU / WebGPU) // VERIFICATION REPORT');
    R.push('------------------------------------------------------------------------');
    R.push(` Theme             : ${label} (WGSL, ${stateful ? 'state texture' : 'stateless'}${hasStep ? ', argus_step' : ''})`);
    R.push(` State             : ${d.stateW}x${d.stateH} ${d.stateF32 ? 'float32' : 'float16'}, ${hasStep ? d.steps : 0} step(s) per frame`);
    R.push(` Resolution        : ${width}x${height} (and 320x200 watchdog)`);
    R.push(` Frames Rendered   : ${frames} (dt = 1/30 s)`);
    R.push(` Date (UTC)        : ${HARNESS_DATE} at frame 0 (J2000 day ${jd.days} + ${jd.frac.toFixed(6)}), offset 0 (--date)`);
    R.push(` Avg GPU Frame     : ${avg.toFixed(1)} us | Budget: ${BUDGET_US.toFixed(1)} us${hasTs ? '' : ' (wall time: no timestamp-query here)'}`);
    R.push(` Worst GPU Frame   : ${worst.toFixed(1)} us`);
    R.push(` Watchdog 320x200  : ${wdOk ? 'PASS' : 'FAIL (failed to compile or run at 320x200)'}`);
    R.push(` NaN / Inf Check   : ${nan ? 'FAIL (NaN/Inf in the output!)' : 'CLEAN'}`);
    R.push(` Pixel Variance    : ${distinct} / ${n} non-bg pixels`);
    R.push(` Temporal Motion   : ${animated} / ${n} visibly animated pixels (min required: 2000)`);
    if (d.stats) R.push(' Stats (buffer 1)  : synthetic (fixed values, a new seq every 30 frames; --stats live reads this Mac)');
    R.push(` Alpha (page only) : ${aMin.toFixed(3)}..${aMax.toFixed(3)} (not a gate: the app and this canvas present opaque)`);
    R.push(` GPU               : ${e.info.adapter || 'unknown adapter'}${hasTs ? ', timestamp-query' : ''}`);
    R.push(` Verdict           : ${out.pass ? 'PASS' : 'FAIL'}`);
    R.push('========================================================================');
    out.text = R.join('\n');
  } catch (err) {
    const msg = String(err.message ?? err);
    for (let i = 2; i <= 6; i++) if (!out.gates[i - 1]) gate(i, null, 'not run');
    out.runError = msg;
    out.pass = false;
    out.text = failText(`METAL RUN FAILED (here: WGSL, WebGPU): ${label}: ${msg}`);
  } finally {
    e.destroy();
  }
  return out;
}

const failText = (line) => `${line}\nVerdict           : FAIL\n`;

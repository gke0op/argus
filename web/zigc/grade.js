// web/zigc/grade.js — the one grading pipeline: the bench page, the home page's hero and CI
// (grade.mjs) all run this, in a browser or in Node, so they reach the same result by construction.
//
//   const p = await prepare(compiler, name, source, { signal, timeoutMs, onPhase });
//   p.stop: null (ready) | 'crash' (zig.wasm did not finish) | 'gate1' (Zig's errors) |
//           'build' (Gate 1 passes, the wasm backend cannot build it) | 'module' (it did not load)
//   p.module, p.moduleSha256, p.ms320, p.maxPixels, p.deferred (the gates would take > 90 s here)
//   then, unless deferred: web/wasm/gates.js runGates(name, { module: p.module, ... })
//
// `compiler` is client.js's (a Worker, in the page) or any object with the same compile(); it
// throws client.js's CompileError (time-out, load, Worker, cancel). onPhase(key, p) is told
// 'sema', 'build' (the compiler's), then 'module' and 'probe', with the result so far.

const engine = () => import('../wasm/engine.js');

/// Run the gates without asking when their 120 frames at 1920x1200 take less than this here.
export const GATE_BUDGET_S = 90;

/// The pixels this build can draw in about `ms` per frame, from its 320x200 time (at most 1920x1200).
export const pixelsFor = (ms320, ms = 25) => (ms320 > 0 ? Math.max(320 * 200, Math.min(1920 * 1200, Math.round((320 * 200 * ms) / ms320))) : undefined);

/// The gates' 120 frames (and the watchdog) at 1920x1200, in seconds, from the 320x200 time.
export const projectedGatesS = (ms320) => (ms320 > 0 ? (ms320 * ((1920 * 1200) / (320 * 200)) * 121) / 1000 : 0);

export async function sha256Hex(bytes) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/// One 320x200 step + draw (after a first one) of `m` (engine.js moduleFromBytes) in a Worker:
/// CPU ms, undefined after 10 s (or on `signal`), null if it failed. Its Workers always end.
export async function speedProbe(m, signal) {
  const { startEngine } = await engine();
  let eng = null, stop = false;
  const work = (async () => {
    eng = await startEngine({ module: m.module, threaded: false, threads: 1 });
    if (stop) return undefined;
    const { ptr } = await eng.leader.call('liveInit', { w: 320, h: 200, scale: 2 });
    if (!ptr) return null;
    await eng.leader.call('frame', { dt: 0.008, w: 320, h: 200, ptr });
    return (await eng.leader.call('frame', { dt: 0.008, w: 320, h: 200, ptr })).cpuMs;
  })().catch(() => null);
  let t;
  const r = await Promise.race([work, new Promise((res) => { t = setTimeout(() => res(undefined), 10000); signal?.addEventListener('abort', () => res(undefined), { once: true }); })]);
  clearTimeout(t);
  stop = true;
  eng?.terminate();
  work.then(() => eng?.terminate());
  return r;
}

/// Compile `source` as `name`, then (if it built) load the module, take its SHA-256 and time a
/// 320x200 frame. See the top of this file.
export async function prepare(compiler, name, source, { signal, timeoutMs = 60000, onPhase, probe = true } = {}) {
  const c = await compiler.compile(name, source, { signal, timeoutMs, onPhase: (k) => onPhase?.(k, null) });
  const p = { stop: null, c, info: c.info || {}, error: null, module: null, moduleSha256: null, ms320: null, maxPixels: undefined, projectedS: 0, deferred: false };
  if (c.crash) return { ...p, stop: 'crash' };
  if (!c.gate1.ok) return { ...p, stop: 'gate1' };
  if (!c.ok) return { ...p, stop: 'build' };
  p.moduleSha256 = await sha256Hex(c.wasm);
  onPhase?.('module', p);
  const { moduleFromBytes } = await engine();
  let t;
  try {
    p.module = await Promise.race([moduleFromBytes(c.wasm), new Promise((_, rej) => { t = setTimeout(() => rej(new Error('compiling the module in this browser did not finish in 30.0 s')), 30000); })]);
  } catch (e) { return { ...p, stop: 'module', error: e }; } finally { clearTimeout(t); }
  if (!probe || signal?.aborted) return p;
  onPhase?.('probe', p);
  p.ms320 = await speedProbe(p.module, signal);
  p.maxPixels = pixelsFor(p.ms320);
  p.projectedS = projectedGatesS(p.ms320);
  p.deferred = p.projectedS > GATE_BUDGET_S;
  return p;
}

/// What CI records and the live board compares (site/assets/live.js): the outcome, the module's
/// SHA-256 and gates 1-8 under the ruler. `res`: runGates' result, or null (not run).
export function record(name, p, res) {
  const gates = [null, null, null, null, null, null, null, null];
  const rec = { name, ruler: p.info.ruler || null, outcome: '', moduleSha256: p.moduleSha256, gates, gate8Ms: null, ms320: p.ms320 ?? null, note: '' };
  const c = p.c;
  if (p.stop === 'crash') return { ...rec, outcome: 'compiler-crash', note: `${c.crash.kind} in ${c.crash.phase}: ${c.crash.panic || c.crash.message}` };
  if (p.stop === 'gate1') { gates[0] = false; return { ...rec, outcome: 'compile-error', note: c.gate1.log.split('\n').find((l) => /: error: /.test(l)) || c.gate1.log.split('\n')[0] }; }
  gates[0] = true;
  if (p.stop === 'build') return { ...rec, outcome: 'not-graded', note: c.build.log.split('\n').find((l) => / error: /.test(l)) || c.build.log.split('\n')[0] };
  if (p.stop === 'module') return { ...rec, outcome: 'module-error', note: String(p.error?.message ?? p.error) };
  if (p.deferred) return { ...rec, outcome: 'deferred', note: `gates would take about ${Math.ceil(p.projectedS / 60)} min in this build` };
  if (!res) return rec;
  res.gates.forEach((g, i) => { gates[i] = g.pass; });
  return { ...rec, outcome: 'verdict', gate8Ms: res.report ? res.report.avg_us / 1000 : null, note: res.crashed ? `crashed in ${res.crashed.phase}: ${res.crashed.message}` : res.timedOut ? `hung in ${res.timedOut}` : '' };
}

// Checks that web/cygnus/cygnus.wasm hands the GPU the same bytes as the app's native build
// (web/cygnus/verify/dump_native.zig): Static, the disk table, the turbulence noise, the trace
// params and the per-frame tables after SKIP steps of 0.008 * 30 / FPS.
//   node web/cygnus/verify/compare_tables.mjs NATIVE_DIR SKIP FPS W H [INIT_W INIT_H]
import { readFileSync } from 'node:fs';
const [dir, skip, fps, w, h, iw = '16', ih = '10'] = process.argv.slice(2);
const wasm = await WebAssembly.instantiate(readFileSync(new URL('../cygnus.wasm', import.meta.url)), {});
const x = wasm.instance.exports;
let t0 = performance.now();
if (!x.cyg_init(+iw, +ih)) throw new Error('init failed');
const tInit = performance.now() - t0;
const dt = 0.008 * 30 / +fps;
t0 = performance.now();
for (let i = 0; i < +skip; i++) x.cyg_step(dt);
const tStep = (performance.now() - t0) / Math.max(1, +skip);
const bytes = (p, n) => new Uint8Array(x.memory.buffer, p, n);
const got = {
  'static.bin': bytes(x.cyg_static_ptr(), x.cyg_static_len()),
  'ttab.bin': bytes(x.cyg_ttab_ptr(), x.cyg_ttab_len()),
  'noise.bin': bytes(x.cyg_noise_ptr(), x.cyg_noise_len()),
  'frame.bin': bytes(x.cyg_frame(), x.cyg_frame_len()),
  'params.bin': bytes(x.cyg_trace_params(+w, +h, -1), x.cyg_trace_params_len()),
};
let bad = 0;
for (const [name, b] of Object.entries(got)) {
  const ref = readFileSync(`${dir}/${name}`);
  let diff = 0, first = -1;
  for (let i = 0; i < Math.max(ref.length, b.length); i++) if (ref[i] !== b[i]) { diff++; if (first < 0) first = i; }
  console.log(`${name.padEnd(11)} ${String(b.length).padStart(8)} B  ${diff === 0 && ref.length === b.length ? 'identical' : `${diff} bytes differ (first at ${first}), native ${ref.length} B`}`);
  if (diff) bad++;
}
console.log(`t_m ${x.cyg_time_m()}  init ${tInit.toFixed(0)} ms  step ${(tStep * 1000).toFixed(1)} us  wasm memory ${(x.memory.buffer.byteLength / 1048576).toFixed(1)} MB`);
process.exit(bad ? 1 : 0);

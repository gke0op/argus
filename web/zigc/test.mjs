// web/zigc/test.mjs — compile and grade themes with zig.wasm in Node, as the bench page does.
//
//   node web/zigc/test.mjs [--zig zig.wasm] [--lib DIR | --bundle zig-lib.bin] [--only NAME] [--no-gates]
//
// --no-gates: compile only, and print each module's SHA-256 (to compare two libs' output).
// Tutorial_Tides (a @Vector kernel theme) is ~150x slower in this build than with LLVM, so its
// 120 gate frames at 1920x1200 would take ~26 min: it is compiled and run for 3 frames at
// 320x200 here (the page does the same check before it grades).
//
// Every tests/fixtures/Gate*.zig, the BENCHMARK.md skeleton, themes/cpu/Tutorial_Tides.zig and
// the u32/usize trap, one after another in one MemFS (so the second compile onward reuses the
// cache, as a second compile in the page does). Each must give its expected verdict: the
// fixture's own gate fails, the rest pass. Gate 8 is reported but not checked (it times this
// machine's run of self-hosted-backend code). Exit 1 on any unexpected verdict.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MemFS } from './wasi.js';
import { SUPPORT, compileTheme, parseDiagnostics } from './zigc.js';
import { mountBundle } from './stdlib.js';
import { createHash } from 'node:crypto';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const zigPath = opt('--zig', '') || `${process.env.HOME}/zig-src/wasm-out/bin/zig.wasm`;
const libDir = opt('--lib', `${process.env.HOME}/zig-src/zig-0.17.0/lib`);
const only = opt('--only', null);
const bundlePath = opt('--bundle', null);
const noGates = argv.includes('--no-gates');

const { runGates } = await import('../wasm/gates.js');
const { moduleFromBytes } = await import('../wasm/engine.js');

const fs = new MemFS();
if (bundlePath) mountBundle(fs, fs.lib, new Uint8Array(readFileSync(bundlePath)));
else (function mount(dir, node, rel = '') {
  for (const name of readdirSync(join(dir, rel))) {
    const r = rel ? `${rel}/${name}` : name;
    const st = statSync(join(dir, r));
    if (st.isDirectory()) mount(dir, node, r); else fs.lazyFile(node, r, st.size, () => new Uint8Array(readFileSync(join(dir, r))));
  }
})(libDir, fs.lib);
for (const [v, repo] of SUPPORT) fs.writeFile(fs.cwd, v, readFileSync(join(ROOT, repo)));

const md = readFileSync(join(ROOT, 'BENCHMARK.md'), 'utf8');
const skeleton = md.split('### Minimal Working Skeleton')[1].split('```zig\n')[1].split('\n```')[0] + '\n';
const trap = readFileSync(join(ROOT, 'tests/fixtures/Gate0_Control.zig'), 'utf8')
  .replace('st.* = .{ .w = w, .h = h, .t = 0, .centre = 0.2 };', 'st.* = .{ .w = w, .h = h, .t = 0, .centre = 0.2 };\n    const n_px: usize = @as(usize, w) * h;\n    const n32: u32 = n_px;\n    _ = n32;');

const cases = [
  ['Bench_Skeleton', skeleton, 0],
  ...readdirSync(join(ROOT, 'tests/fixtures')).filter((f) => /^Gate\d/.test(f)).sort().map((f) => [f.replace('.zig', ''), readFileSync(join(ROOT, 'tests/fixtures', f), 'utf8'), Number(f[4])]),
  ['Trap_U32_Usize', trap, 1],
  ['Tutorial_Tides', readFileSync(join(ROOT, 'themes/cpu/Tutorial_Tides.zig'), 'utf8'), 0],
].filter(([n]) => !only || n === only);

const zig = await WebAssembly.compile(readFileSync(zigPath));
let bad = 0;
for (const [name, src, expect] of cases) {
  const t0 = performance.now();
  const c = compileTheme(zig, fs, name, src);
  const tc = performance.now() - t0;
  let failed = [];
  let line = '';
  if (!c.ok) {
    failed = [1];
    const d = parseDiagnostics((c.gate1.ok ? c.build : c.gate1).log).find((x) => x.kind === 'error');
    line = d ? `${d.file}:${d.line}:${d.col}: ${d.msg}` : (c.gate1.ok ? c.build : c.gate1).log.split('\n')[0];
  } else if (noGates) {
    line = `${(c.wasm.length / 1024).toFixed(0)} KB sha256 ${createHash('sha256').update(c.wasm).digest('hex')}`;
    failed = null;
  } else if (name === 'Tutorial_Tides') {
    const mem = new WebAssembly.Memory({ initial: 64, maximum: 16384 });
    const e = new WebAssembly.Instance(new WebAssembly.Module(c.wasm), { env: { memory: mem, web_phase() {}, web_now_us: () => performance.now() * 1000 } }).exports;
    const ptr = e.web_live_init(320, 200, 2);
    const t1 = performance.now();
    for (let i = 0; i < 3; i++) e.web_live_frame(0.008);
    const px = new Uint32Array(mem.buffer, ptr, 320 * 200);
    const distinct = new Set(px).size;
    failed = ptr && distinct > 100 && !e.web_live_has_nan() ? [] : [3];
    line = `${(c.wasm.length / 1024).toFixed(0)} KB, live 320x200: ${((performance.now() - t1) / 3).toFixed(0)} ms/frame, ${distinct} distinct colours (gates not run: ~150x slower than LLVM)`;
  } else {
    const m = await moduleFromBytes(c.wasm);
    const r = await runGates(name, { module: m, threads: 1 });
    failed = r.gates.filter((g) => g.pass === false).map((g) => g.id);
    line = `${(c.wasm.length / 1024).toFixed(0)} KB, avg ${r.report?.avg_us?.toFixed(0)} us/frame`;
  }
  if (failed === null) { console.log(`     ${name.padEnd(16)} sema ${c.gate1.ms.toFixed(0)} ms, build ${c.build.ms.toFixed(0)} ms | ${line}`); continue; }
  // Gate 8 is the browser build's own timing: reported, not checked, unless it is the fixture's gate.
  const verdict = failed.filter((g) => g !== 8 || expect === 8);
  const ok = expect === 0 ? verdict.length === 0 : verdict.includes(expect) && verdict.every((g) => g === expect || (expect === 4 && g === 3));
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'BAD '} ${name.padEnd(16)} expect ${expect ? `FAIL ${expect}` : 'PASS'} got ${failed.length ? `FAIL ${failed.join(',')}` : 'PASS'} | sema ${c.gate1.ms.toFixed(0)} ms${c.build ? `, build ${c.build.ms.toFixed(0)} ms` : ''} (${tc.toFixed(0)} ms) | ${line}`);
}
let cacheBytes = 0;
for (const [, n] of fs.walk(fs.cache)) cacheBytes += n.size;
console.log(`cache: ${(cacheBytes / 1048576).toFixed(1)} MB; std files read: ${fs.lazyLoads} (${(fs.lazyBytes / 1048576).toFixed(1)} MB)`);
process.exit(bad ? 1 : 0);

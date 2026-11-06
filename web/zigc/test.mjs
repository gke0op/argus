// web/zigc/test.mjs — compile and grade themes with zig.wasm in Node, as the bench page does.
//
//   node web/zigc/test.mjs [--zig zig.wasm] [--lib DIR | --bundle zig-lib.bin] [--only NAME] [--no-gates] [--pathological] [--extra FILE,...]
//
// Every tests/fixtures/Gate*.zig, the BENCHMARK.md skeleton, themes/cpu/Tutorial_Tides.zig and
// the u32/usize trap, one after another in one MemFS (so the second compile onward reuses the
// cache, as a second compile in the page does). Each must give its expected verdict: the
// fixture's own gate fails, the rest pass. Gate 8 is reported but not checked (it times this
// machine's run of self-hosted-backend code). Exit 1 on any unexpected outcome.
//
// --pathological: also web/zigc/cases.js (endless comptime recursion, a huge comptime table,
// deep nesting, endless loops in init and step, an allocation storm, 500 KB of source, binary
// garbage). Each must end in its expected outcome within its time limit, and after each the
// skeleton must compile and pass. After a compiler crash the test starts a fresh MemFS, as the
// page starts a fresh Worker.
// --extra FILE[,FILE...]: also these themes, kept outside the repo (a model's answer someone
// hit trouble with, say). Each must pass gates 1-7, and the skeleton must pass after it.
// --no-gates: compile only, and print each module's SHA-256 (to compare two libs' output).
// Tutorial_Tides (a @Vector kernel theme) is ~150x slower in this build than with LLVM, so its
// 120 gate frames at 1920x1200 would take ~26 min: it is compiled and run for 3 frames at
// 320x200 here (the page decides the same from a timed frame before it grades).
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MemFS } from './wasi.js';
import { SUPPORT, compileTheme, parseDiagnostics } from './zigc.js';
import { mountBundle } from './stdlib.js';
import { pathologicalCases } from './cases.js';
import { createHash } from 'node:crypto';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const zigPath = opt('--zig', '') || `${process.env.HOME}/zig-src/wasm-out/bin/zig.wasm`;
const libDir = opt('--lib', `${process.env.HOME}/zig-src/zig-0.17.0/lib`);
const only = opt('--only', null);
const bundlePath = opt('--bundle', null);
const noGates = argv.includes('--no-gates');
const withPathological = argv.includes('--pathological');
const extras = (opt('--extra', '') || '').split(',').filter(Boolean);

const { runGates } = await import('../wasm/gates.js');
const { moduleFromBytes } = await import('../wasm/engine.js');

const bundle = bundlePath ? new Uint8Array(readFileSync(bundlePath)) : null;
function freshFs() {
  const f = new MemFS();
  if (bundle) mountBundle(f, f.lib, bundle);
  else (function mount(dir, node, rel = '') {
    for (const name of readdirSync(join(dir, rel))) {
      const r = rel ? `${rel}/${name}` : name;
      const st = statSync(join(dir, r));
      if (st.isDirectory()) mount(dir, node, r); else f.lazyFile(node, r, st.size, () => new Uint8Array(readFileSync(join(dir, r))));
    }
  })(libDir, f.lib);
  for (const [v, repo] of SUPPORT) f.writeFile(f.cwd, v, readFileSync(join(ROOT, repo)));
  return f;
}
let fs = freshFs();

const md = readFileSync(join(ROOT, 'BENCHMARK.md'), 'utf8');
const skeleton = md.split('### Minimal Working Skeleton')[1].split('```zig\n')[1].split('\n```')[0] + '\n';
const trap = readFileSync(join(ROOT, 'tests/fixtures/Gate0_Control.zig'), 'utf8')
  .replace('st.* = .{ .w = w, .h = h, .t = 0, .centre = 0.2 };', 'st.* = .{ .w = w, .h = h, .t = 0, .centre = 0.2 };\n    const n_px: usize = @as(usize, w) * h;\n    const n32: u32 = n_px;\n    _ = n32;');

const gate0 = readFileSync(join(ROOT, 'tests/fixtures/Gate0_Control.zig'), 'utf8');
const expectOf = (g) => (g ? { gate: g } : { pass: true });
const cases = [
  ['Bench_Skeleton', skeleton, expectOf(0)],
  ...readdirSync(join(ROOT, 'tests/fixtures')).filter((f) => /^Gate\d/.test(f)).sort().map((f) => [f.replace('.zig', ''), readFileSync(join(ROOT, 'tests/fixtures', f), 'utf8'), expectOf(Number(f[4]))]),
  ['Trap_U32_Usize', trap, expectOf(1)],
  ['Tutorial_Tides', readFileSync(join(ROOT, 'themes/cpu/Tutorial_Tides.zig'), 'utf8'), expectOf(0)],
  ...(withPathological ? pathologicalCases(gate0).filter((c) => !c[4]?.browserOnly).map(([n, src, e, limitS]) => [n, src, e, limitS, true]) : []),
  ...extras.map((f) => [f.replace(/^.*\//, '').replace(/\.zig$/, '').replace(/[^A-Za-z0-9_]/g, '_'), readFileSync(f, 'utf8'), { pass: true }, 120, true]),
].filter(([n]) => !only || n === only);

const zig = await WebAssembly.compile(readFileSync(zigPath));

/// Compile and grade one source. Returns { outcome, failed (gate ids), line, c }.
async function grade(name, src) {
  const c = compileTheme(zig, fs, name, src);
  if (c.crash) {
    fs = freshFs(); // the page drops a crashed Worker, its MemFS with it
    return { outcome: 'compiler-crash', failed: [], line: `${c.crash.kind} in ${c.crash.phase}: ${c.crash.panic || c.crash.message}`, c };
  }
  if (!c.ok) {
    const log = (c.gate1.ok ? c.build : c.gate1).log;
    const d = parseDiagnostics(log).find((x) => x.kind === 'error');
    return { outcome: c.gate1.ok ? 'not-graded' : 'verdict', failed: [1], line: d ? `${d.file}:${d.line}:${d.col}: ${d.msg}` : log.split('\n')[0], c };
  }
  if (noGates) return { outcome: 'compiled', failed: null, line: `${(c.wasm.length / 1024).toFixed(0)} KB sha256 ${createHash('sha256').update(c.wasm).digest('hex')}`, c };
  if (name === 'Tutorial_Tides') {
    const mem = new WebAssembly.Memory({ initial: 64, maximum: 16384 });
    const e = new WebAssembly.Instance(new WebAssembly.Module(c.wasm), { env: { memory: mem, web_phase() {}, web_now_us: () => performance.now() * 1000 } }).exports;
    const ptr = e.web_live_init(320, 200, 2);
    const t1 = performance.now();
    for (let i = 0; i < 3; i++) e.web_live_frame(0.008);
    const distinct = new Set(new Uint32Array(mem.buffer, ptr, 320 * 200)).size;
    return { outcome: 'verdict', failed: ptr && distinct > 100 && !e.web_live_has_nan() ? [] : [3], line: `${(c.wasm.length / 1024).toFixed(0)} KB, live 320x200: ${((performance.now() - t1) / 3).toFixed(0)} ms/frame, ${distinct} distinct colours (gates not run: ~150x slower than LLVM)`, c };
  }
  const m = await moduleFromBytes(c.wasm);
  const r = await runGates(name, { module: m, threads: 1 });
  const how = r.crashed ? `, crashed in ${r.crashed.phase}: ${r.crashed.message.slice(0, 80)}` : r.timedOut ? `, hung in ${r.timedOut}` : '';
  return { outcome: 'verdict', failed: r.gates.filter((g) => g.pass === false).map((g) => g.id), line: `${(c.wasm.length / 1024).toFixed(0)} KB, avg ${r.report?.avg_us?.toFixed(0) ?? '-'} us/frame${how}`, c };
}

function judge(expect, g) {
  if (expect.kind) return expect.kind.includes(g.outcome);
  if (g.outcome !== 'verdict') return false;
  // Gate 8 is the browser build's own timing: reported, not checked, unless it is the case's gate.
  const verdict = g.failed.filter((x) => x !== 8 || expect.gate === 8);
  if (expect.pass) return verdict.length === 0;
  return verdict.includes(expect.gate) && verdict.every((x) => x === expect.gate || (expect.gate === 4 && x === 3));
}
const show = (e) => (e.kind ? e.kind.join('|') : e.pass ? 'PASS' : `FAIL ${e.gate}`);

let bad = 0;
for (const [name, src, expect, limitS, pathological] of cases) {
  const t0 = performance.now();
  const g = await grade(name, src);
  const tc = (performance.now() - t0) / 1000;
  if (g.failed === null) { console.log(`     ${name.padEnd(22)} sema ${g.c.gate1.ms.toFixed(0)} ms, build ${g.c.build.ms.toFixed(0)} ms | ${g.line}`); continue; }
  const got = g.outcome === 'verdict' ? (g.failed.length ? `FAIL ${g.failed.join(',')}` : 'PASS') : g.outcome;
  const inTime = !limitS || tc <= limitS;
  const ok = judge(expect, g) && inTime;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'BAD '} ${name.padEnd(22)} expect ${show(expect)} got ${got} | ${tc.toFixed(1)} s${limitS ? ` (limit ${limitS} s)` : ''}, sema ${(g.c.gate1.ms ?? 0).toFixed(0)} ms${g.c.build ? `, build ${g.c.build.ms.toFixed(0)} ms` : ''}${g.c.memBytes ? `, zig.wasm ${(g.c.memBytes / 1048576).toFixed(0)} MB` : ''} | ${g.line.slice(0, 160)}`);
  if (pathological) {
    // The next ordinary compile must work.
    const after = await grade('Bench_Skeleton', skeleton);
    const fine = judge({ pass: true }, after);
    if (!fine) bad++;
    console.log(`${fine ? 'ok  ' : 'BAD '}   then Bench_Skeleton    ${after.outcome === 'verdict' && !after.failed.filter((x) => x !== 8).length ? 'PASS' : after.outcome + ' ' + after.failed.join(',')} | ${after.line.slice(0, 80)}`);
  }
}
let cacheBytes = 0;
for (const [, n] of fs.walk(fs.cache)) cacheBytes += n.size;
console.log(`cache: ${(cacheBytes / 1048576).toFixed(1)} MB; std files read: ${fs.lazyLoads} (${(fs.lazyBytes / 1048576).toFixed(1)} MB)`);
process.exit(bad ? 1 : 0);

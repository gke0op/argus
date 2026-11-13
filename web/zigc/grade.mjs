#!/usr/bin/env node
// web/zigc/grade.mjs — grade themes as the bench page does, in Node: the reference grade.
//
//   node web/zigc/grade.mjs [--site https://gke0op.github.io/argus/ | --build web/zigc/build/] [--out DIR] FILE.zig...
//
// The ruler (zig.wasm, the std bundle, the support sources: build/manifest.json `ruler`) comes
// from the live site or a local build, checked against the manifest's SHA-256s. Each file is
// compiled and graded exactly as the page does it: the same two compiler runs (zigc.js), the
// same module, the same gates (web/wasm/gates.js), the same 320x200 speed probe first (gates
// deferred when they would take over 90 s). So a visitor's "Re-grade in my browser" under the
// same ruler must give the same module SHA-256 and the same gates 1-7. Gate 8 is recorded but
// is this machine's time, not a verdict.
//
// Writes OUT/NAME.browser.json per file ({ name, ruler, outcome, moduleSha256, gates, ... }) and
// prints one line each. Every file runs in its own process with a 180 s limit, so a theme that
// hangs the compiler or the probe cannot stop the rest. Exit 0 unless the ruler cannot load.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import { spawnSync } from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const VALUED = new Set(['--site', '--build', '--out']);
const files = [];
for (let i = 0; i < argv.length && argv[0] !== '--one'; i++) { if (VALUED.has(argv[i])) i++; else files.push(argv[i]); }
const sha256 = (b) => createHash('sha256').update(b).digest('hex');
export const GATE_BUDGET_S = 90; // as site/assets/bench.js
const PER_FILE_S = 180;

/// The ruler from a site URL or a build folder: { manifest, zig (bytes), lib (bytes), support }.
async function loadRuler(source) {
  const isUrl = /^https?:/.test(source);
  const base = isUrl ? new URL('web/zigc/build/', source.endsWith('/') ? source : `${source}/`) : null;
  const get = async (rel) => {
    if (!isUrl) return new Uint8Array(readFileSync(join(source, rel)));
    const r = await fetch(new URL(rel, base), { cache: 'no-store' });
    if (!r.ok) throw new Error(`${new URL(rel, base)}: HTTP ${r.status}`);
    return new Uint8Array(await r.arrayBuffer());
  };
  const manifest = JSON.parse(new TextDecoder().decode(await get('manifest.json')));
  const zigGz = await get(manifest.zig.file), libGz = await get(manifest.lib.file);
  if (sha256(zigGz) !== manifest.zig.sha256) throw new Error('zig.wasm.gz does not match the manifest');
  if (sha256(libGz) !== manifest.lib.sha256) throw new Error('zig-lib.bin.gz does not match the manifest');
  const support = [];
  for (const [virt, rel] of manifest.support) support.push([virt, await get(rel)]);
  return { manifest, zig: gunzipSync(zigGz), lib: gunzipSync(libGz), support };
}

/// The name the page gives a file (web/zigc/zigc.js themeName), so both compile the same module.
async function nameOf(file) { const { themeName } = await import('./zigc.js'); return themeName(basename(file)); }

/// Grade one file in this process. Returns the record.
async function gradeOne(rulerSource, file) {
  const { MemFS } = await import('./wasi.js');
  const { SUPPORT, compileTheme, parseDiagnostics } = await import('./zigc.js');
  const { mountBundle } = await import('./stdlib.js');
  const { runGates } = await import('../wasm/gates.js');
  const { moduleFromBytes } = await import('../wasm/engine.js');
  void SUPPORT;
  const ruler = await loadRuler(rulerSource);
  const fs = new MemFS();
  mountBundle(fs, fs.lib, ruler.lib);
  for (const [virt, bytes] of ruler.support) fs.writeFile(fs.cwd, virt, bytes, 1n);
  const zig = await WebAssembly.compile(ruler.zig);
  const name = await nameOf(file);
  const source = readFileSync(file, 'utf8');
  const rec = { name, file: basename(file), sourceSha256: sha256(Buffer.from(source, 'utf8')), ruler: ruler.manifest.ruler || null, zigVersion: ruler.manifest.zigVersion, outcome: null, moduleSha256: null, gates: [null, null, null, null, null, null, null, null], gate8Ms: null, ms320: null, note: '' };
  const c = compileTheme(zig, fs, name, source);
  if (c.crash) { rec.outcome = 'compiler-crash'; rec.note = `${c.crash.kind} in ${c.crash.phase}: ${c.crash.panic || c.crash.message}`; return rec; }
  if (!c.gate1.ok) {
    rec.outcome = 'compile-error'; rec.gates[0] = false;
    const d = parseDiagnostics(c.gate1.log).find((x) => x.kind === 'error');
    rec.note = d ? `${d.file}:${d.line}:${d.col}: ${d.msg}` : c.gate1.log.split('\n')[0];
    return rec;
  }
  rec.gates[0] = true;
  if (!c.ok) { rec.outcome = 'not-graded'; rec.note = c.build.log.split('\n').find((l) => / error: /.test(l)) || c.build.log.split('\n')[0]; return rec; }
  rec.moduleSha256 = sha256(c.wasm);
  // The page's speed probe (site/assets/bench.js speedProbe): one 320x200 step + draw after a
  // first one, in a Worker, given 10 s; undefined (no answer) goes on to the gates' watchdog.
  const { startEngine } = await import('../wasm/engine.js');
  const module = await moduleFromBytes(c.wasm);
  let eng = null;
  const work = (async () => {
    eng = await startEngine({ module: module.module, threaded: false, threads: 1 });
    const { ptr } = await eng.leader.call('liveInit', { w: 320, h: 200, scale: 2 });
    if (!ptr) return null;
    await eng.leader.call('frame', { dt: 0.008, w: 320, h: 200, ptr });
    return (await eng.leader.call('frame', { dt: 0.008, w: 320, h: 200, ptr })).cpuMs;
  })().catch(() => null);
  let probeTimer;
  const ms320 = await Promise.race([work, new Promise((res) => { probeTimer = setTimeout(() => res(undefined), 10000); })]);
  clearTimeout(probeTimer);
  eng?.terminate();
  work.then(() => eng?.terminate());
  rec.ms320 = ms320 ?? null;
  const projected = ms320 > 0 ? ms320 * ((1920 * 1200) / (320 * 200)) * 121 / 1000 : 0;
  if (projected > GATE_BUDGET_S) { rec.outcome = 'deferred'; rec.note = `gates would take about ${Math.ceil(projected / 60)} min in this build`; return rec; }
  const r = await runGates(name, { module, threads: 1, gate1: 'compiled in the browser build' });
  rec.outcome = 'verdict';
  rec.gates = r.gates.map((g) => g.pass);
  rec.gate8Ms = r.report ? r.report.avg_us / 1000 : null;
  rec.note = r.crashed ? `crashed in ${r.crashed.phase}: ${r.crashed.message}` : r.timedOut ? `hung in ${r.timedOut}` : '';
  return rec;
}

if (argv[0] === '--one') {
  // Child: grade one file, print its record as the last line.
  const rec = await gradeOne(argv[1], argv[2]);
  process.stdout.write(`${JSON.stringify(rec)}\n`);
  process.exit(0);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const source = opt('--build', null) || opt('--site', 'https://gke0op.github.io/argus/');
  const out = opt('--out', '.');
  mkdirSync(out, { recursive: true });
  // Load the ruler once here, so a bad ruler fails the run before any theme.
  const ruler = await loadRuler(source);
  console.log(`ruler ${ruler.manifest.ruler} (Zig ${ruler.manifest.zigVersion}) from ${source}`);
  for (const f of files) {
    const t0 = performance.now();
    const p = spawnSync(process.execPath, [fileURLToPath(import.meta.url), '--one', source, f], { encoding: 'utf8', timeout: PER_FILE_S * 1000, maxBuffer: 16 << 20 });
    let rec;
    try { rec = JSON.parse(p.stdout.trim().split('\n').pop()); } catch {
      rec = { name: await nameOf(f), file: basename(f), ruler: ruler.manifest.ruler, outcome: p.signal ? 'timeout' : 'error', moduleSha256: null, gates: [null, null, null, null, null, null, null, null], note: p.signal ? `stopped after ${PER_FILE_S} s` : (p.stderr || '').split('\n').filter(Boolean).slice(-1)[0] || 'no output' };
    }
    rec.secs = Number(((performance.now() - t0) / 1000).toFixed(1));
    writeFileSync(join(out, `${rec.name}.browser.json`), `${JSON.stringify(rec, null, 2)}\n`);
    const g = rec.gates.map((v, i) => (v === true ? '' : v === false ? `${i + 1}✗ ` : '')).join('').trim();
    console.log(`${rec.name}: ${rec.outcome}${g ? ` (fails ${g})` : ''} · module ${rec.moduleSha256 ? rec.moduleSha256.slice(0, 16) : '-'} · ${rec.secs} s${rec.note ? ` · ${rec.note}` : ''}`);
  }
}

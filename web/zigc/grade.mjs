#!/usr/bin/env node
// web/zigc/grade.mjs — grade themes as the bench page does, in Node: the reference grade.
//
//   node web/zigc/grade.mjs [--site https://gke0op.github.io/argus/ | --build web/zigc/build/] [--out DIR] FILE.zig...
//
// The ruler (zig.wasm, the std bundle, the support sources: build/manifest.json `ruler`) comes
// from the live site or a local build, checked against the manifest's SHA-256s. Each file is
// graded by the page's own pipeline (grade.js prepare: the compile, the module, the 320x200 probe
// and the deferral; then web/wasm/gates.js), so a visitor's "Re-grade here" under the same
// ruler must give the same module SHA-256 and the same gates 1-7. Gate 8 is recorded but is this
// machine's time, not a verdict.
//
// Writes OUT/NAME.browser.json per file ({ name, ruler, outcome, moduleSha256, gates, ... }) and
// prints one line each. Every file runs in its own process with a 180 s limit, so a theme that
// hangs the compiler or the probe cannot stop the rest. Exit 0 unless the ruler cannot load.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, basename, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import { spawnSync } from 'node:child_process';

const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const VALUED = new Set(['--site', '--build', '--out']);
const files = [];
for (let i = 0; i < argv.length && argv[0] !== '--one'; i++) { if (VALUED.has(argv[i])) i++; else files.push(argv[i]); }
const sha256 = (b) => createHash('sha256').update(b).digest('hex');
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

/// Grade one file in this process, with the page's pipeline (grade.js). Returns the record.
async function gradeOne(rulerSource, file) {
  const { MemFS } = await import('./wasi.js');
  const { compileTheme } = await import('./zigc.js');
  const { mountBundle } = await import('./stdlib.js');
  const { prepare, record } = await import('./grade.js');
  const { runGates } = await import('../wasm/gates.js');
  const ruler = await loadRuler(rulerSource);
  const fs = new MemFS();
  mountBundle(fs, fs.lib, ruler.lib);
  for (const [virt, bytes] of ruler.support) fs.writeFile(fs.cwd, virt, bytes, 1n);
  const zig = await WebAssembly.compile(ruler.zig);
  // client.js's compile(), in this process: the per-file process limit stands in for its time-out.
  const compiler = { compile: async (n, src) => ({ ...compileTheme(zig, fs, n, src), info: { ruler: ruler.manifest.ruler || null } }) };
  const name = await nameOf(file);
  const source = readFileSync(file, 'utf8');
  const p = await prepare(compiler, name, source);
  const res = p.stop || p.deferred ? null : await runGates(name, { module: p.module, threads: 1, gate1: 'compiled in the browser build' });
  return { ...record(name, p, res), file: basename(file), sourceSha256: sha256(Buffer.from(source, 'utf8')), zigVersion: ruler.manifest.zigVersion };
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

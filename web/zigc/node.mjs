// web/zigc/node.mjs — run zig.wasm in Node through web/zigc/wasi.js (not node:wasi).
//
//   node web/zigc/node.mjs --zig PATH/zig.wasm --lib PATH/lib [--cwd DIR] [--log-lib FILE] -- <zig args>
//
// The cwd DIR (default: the current directory) is copied into the in-memory '.', the lib
// directory is mounted lazily at /lib, /cache starts empty (or --cache DIR, which is read
// before and written back after). Outputs written under '.' are copied back to DIR.
// --log-lib FILE writes the lib files the run read, one per line (to trim the std bundle).
import { readFileSync, writeFileSync, readdirSync, statSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { MemFS, runWasi } from './wasi.js';

const argv = process.argv.slice(2);
const sep = argv.indexOf('--');
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 && (sep < 0 || i < sep) ? argv[i + 1] : d; };
const zigArgs = sep >= 0 ? argv.slice(sep + 1) : [];
const zigPath = opt('--zig', `${process.env.HOME}/zig-src/wasm-out/bin/zig.wasm`);
const libDir = opt('--lib', `${process.env.HOME}/zig-src/zig-0.17.0/lib`);
const cwdDir = opt('--cwd', process.cwd());
const cacheDir = opt('--cache', null);
const logLib = opt('--log-lib', null);
const repeat = Number(opt('--repeat', '1'));

const fs = new MemFS();
function mountLazy(dir, node, rel = '') {
  for (const name of readdirSync(join(dir, rel))) {
    const r = rel ? `${rel}/${name}` : name;
    const st = statSync(join(dir, r));
    if (st.isDirectory()) { fs.mkdirp(node, r); mountLazy(dir, node, r); } else fs.lazyFile(node, r, st.size, () => new Uint8Array(readFileSync(join(dir, r))));
  }
}
function copyIn(dir, node, rel = '') {
  for (const name of readdirSync(join(dir, rel))) {
    const r = rel ? `${rel}/${name}` : name;
    if (name === '.zig-cache' || name === 'node_modules' || name === '.git') continue;
    const st = statSync(join(dir, r));
    if (st.isDirectory()) { fs.mkdirp(node, r); copyIn(dir, node, r); } else fs.writeFile(node, r, new Uint8Array(readFileSync(join(dir, r))), BigInt(Math.round(st.mtimeMs * 1e6)));
  }
}
const t0 = performance.now();
mountLazy(libDir, fs.lib);
copyIn(cwdDir, fs.cwd);
if (cacheDir && existsSync(cacheDir)) copyIn(cacheDir, fs.cache);
const before = new Map([...fs.walk(fs.cwd)].map(([r, n]) => [r, `${n.ino}:${n.mtime}:${n.size}`]));
const read = new Set();
fs.onLoad = (p) => read.add(p.replace(/^\/lib\//, ''));
const tMount = performance.now() - t0;
const module = await WebAssembly.compile(readFileSync(zigPath));
const tCompile = performance.now() - t0 - tMount;

let res;
for (let i = 0; i < repeat; i++) {
  res = runWasi(module, { args: ['zig', ...zigArgs], fs, onStderr: (b) => process.stderr.write(b), trace: process.env.ZIGC_TRACE ? (n, a, r, p) => process.stderr.write(`${n}(${a.join(',')}) ${p} -> ${r}\n`) : null });
  process.stderr.write(`[zigc] run ${i + 1}: exit ${res.code} in ${res.ms.toFixed(0)} ms (std files read so far: ${read.size}, ${(fs.lazyBytes / 1024).toFixed(0)} KB)\n`);
}
process.stdout.write(res.stdout);

process.stderr.write(`[zigc] mount ${tMount.toFixed(0)} ms, WebAssembly.compile ${tCompile.toFixed(0)} ms\n`);

for (const [r, n] of fs.walk(fs.cwd)) {
  if (before.get(r) === `${n.ino}:${n.mtime}:${n.size}`) continue;
  mkdirSync(dirname(join(cwdDir, r)), { recursive: true });
  writeFileSync(join(cwdDir, r), n.data.subarray(0, n.size));
}
if (cacheDir) for (const [r, n] of fs.walk(fs.cache)) { fs.ensure(n); mkdirSync(dirname(join(cacheDir, r)), { recursive: true }); writeFileSync(join(cacheDir, r), n.data.subarray(0, n.size)); }
if (logLib) writeFileSync(logLib, [...read].sort().join('\n') + '\n');
process.exitCode = res.code;

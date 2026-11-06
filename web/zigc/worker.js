// web/zigc/worker.js — the Zig 0.17.0 compiler (zig.wasm) in a Worker, for web/zigc/client.js.
//
// Messages in:  { type: 'init', base }                 load the compiler, the lib and /cache
//               { type: 'compile', id, name, source }  compile a theme (zigc.js compileTheme)
// Messages out: { type: 'progress', phase, loaded, total, cached }   while loading
//               { type: 'ready', info }  |  { type: 'error', error }
//               { type: 'phase', id, phase }  |  { type: 'result', id, result }  (wasm transferred)
//
// Downloads (build/manifest.json): zig.wasm.gz and zig-lib.bin.gz, checked against the
// manifest's SHA-256 and kept in the Cache API under their hash, so a second visit downloads
// nothing. Zig's /cache (the ZIR of every lib file, ~43 MB) is kept in IndexedDB, keyed by the
// compiler's and the lib's hashes, so a second visit also skips AstGen.

import { MemFS } from './wasi.js';
import { compileTheme } from './zigc.js';
import { mountBundle, packTree, unpackTree } from './stdlib.js';

const CACHE_NAME = 'argus-zigc-v1';
const IDB_NAME = 'argus-zigc';
const IDB_MAX_BYTES = 128 << 20;
let zig = null, fs = null, manifest = null, base = null, idbKey = '';

const post = (m, t) => self.postMessage(m, t || []);
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');

async function gunzip(bytes) {
  const s = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(s).arrayBuffer());
}

/// The .gz at `entry.file`, from the Cache API if its hash is there, else downloaded (with
/// progress) and checked. Returns the decompressed bytes.
async function fetchAsset(entry, label) {
  const url = new URL(`${entry.file}?sha256=${entry.sha256}`, base).href;
  let cache = null;
  try { cache = await caches.open(CACHE_NAME); } catch { /* no Cache API (http, private mode) */ }
  let gz = null, cached = false;
  const hit = cache && await cache.match(url);
  if (hit) { gz = new Uint8Array(await hit.arrayBuffer()); cached = true; }
  if (gz && hex(await crypto.subtle.digest('SHA-256', gz)) !== entry.sha256) gz = null;
  if (!gz) {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`${entry.file}: HTTP ${r.status}`);
    const total = entry.gzBytes;
    const parts = []; let loaded = 0;
    const reader = r.body.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      parts.push(value); loaded += value.length;
      post({ type: 'progress', phase: label, loaded, total, cached: false });
    }
    gz = new Uint8Array(loaded);
    let o = 0; for (const p of parts) { gz.set(p, o); o += p.length; }
    const sha = hex(await crypto.subtle.digest('SHA-256', gz));
    if (sha !== entry.sha256) throw new Error(`${entry.file}: SHA-256 ${sha} does not match the manifest's ${entry.sha256}`);
    if (cache) {
      // Drop older versions of this file, then keep this one.
      for (const k of await cache.keys()) if (k.url.split('?')[0] === url.split('?')[0] && k.url !== url) await cache.delete(k);
      await cache.put(url, new Response(gz, { headers: { 'content-type': 'application/gzip' } }));
    }
  }
  post({ type: 'progress', phase: label, loaded: entry.gzBytes, total: entry.gzBytes, cached });
  return { bytes: await gunzip(gz), cached };
}

function idb() {
  return new Promise((res, rej) => {
    const q = indexedDB.open(IDB_NAME, 1);
    q.onupgradeneeded = () => q.result.createObjectStore('cache');
    q.onsuccess = () => res(q.result);
    q.onerror = () => rej(q.error);
  });
}
async function idbGet(key) {
  try {
    const db = await idb();
    return await new Promise((res) => { const q = db.transaction('cache').objectStore('cache').get(key); q.onsuccess = () => res(q.result || null); q.onerror = () => res(null); });
  } catch { return null; }
}
async function idbPut(key, value) {
  try {
    const db = await idb();
    await new Promise((res) => {
      const t = db.transaction('cache', 'readwrite');
      const st = t.objectStore('cache');
      st.clear(); // one entry: the current compiler's
      st.put(value, key);
      t.oncomplete = res; t.onerror = res; t.onabort = res;
    });
  } catch { /* storage refused: next visit runs AstGen again */ }
}

let saveTimer = null, cacheDirty = false;
function saveCacheSoon() {
  cacheDirty = true;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    if (!cacheDirty) return;
    cacheDirty = false;
    const p = packTree(fs, fs.cache);
    if (p.bytes <= IDB_MAX_BYTES) await idbPut(idbKey, p.buffer);
  }, 300);
}

async function init(msg) {
  base = new URL(msg.base);
  const t0 = performance.now();
  const r = await fetch(new URL('manifest.json', base), { cache: 'no-cache' });
  if (!r.ok) throw new Error(`build/manifest.json: HTTP ${r.status} (is the compiler built? make web-zigc)`);
  manifest = await r.json();
  idbKey = `${manifest.zig.sha256}:${manifest.lib.sha256}`;
  const [z, l, support, saved] = await Promise.all([
    fetchAsset(manifest.zig, 'compiler'),
    fetchAsset(manifest.lib, 'std'),
    Promise.all(manifest.support.map(async ([virt, file]) => {
      const s = await fetch(new URL(file, base));
      if (!s.ok) throw new Error(`${file}: HTTP ${s.status}`);
      return [virt, new Uint8Array(await s.arrayBuffer())];
    })),
    idbGet(idbKey),
  ]);
  const tDownload = performance.now() - t0;
  post({ type: 'progress', phase: 'starting', loaded: 0, total: 0, cached: z.cached && l.cached });
  zig = await WebAssembly.compile(z.bytes);
  const tCompile = performance.now() - t0 - tDownload;
  fs = new MemFS();
  const libFiles = mountBundle(fs, fs.lib, l.bytes);
  for (const [virt, bytes] of support) fs.writeFile(fs.cwd, virt, bytes, 1n);
  const restored = saved ? unpackTree(fs, fs.cache, saved) : 0;
  return {
    zigVersion: manifest.zigVersion, libFiles, restoredCacheFiles: restored,
    cachedDownloads: z.cached && l.cached, downloadBytes: (z.cached ? 0 : manifest.zig.gzBytes) + (l.cached ? 0 : manifest.lib.gzBytes),
    gzBytes: manifest.zig.gzBytes + manifest.lib.gzBytes, loadMs: performance.now() - t0, downloadMs: tDownload, wasmCompileMs: tCompile,
  };
}

self.onmessage = async (e) => {
  const m = e.data;
  try {
    if (m.type === 'init') post({ type: 'ready', info: await init(m) });
    else if (m.type === 'compile') {
      const t0 = performance.now();
      const res = compileTheme(zig, fs, m.name, m.source, { onPhase: (phase) => post({ type: 'phase', id: m.id, phase }) });
      res.ms = performance.now() - t0;
      post({ type: 'result', id: m.id, result: res }, res.wasm ? [res.wasm.buffer] : []);
      saveCacheSoon();
    }
  } catch (err) {
    post({ type: 'error', id: m.id, error: String(err && err.message || err) });
  }
};

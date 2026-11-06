// web/zigc/worker.js — the Zig 0.17.0 compiler (zig.wasm) in a Worker, for web/zigc/client.js.
//
// Messages in:  { type: 'init', base, dropCache }      load the compiler, the lib and /cache
//               { type: 'compile', id, name, source }  compile a theme (zigc.js compileTheme)
// Messages out: { type: 'progress', phase, loaded, total, cached, attempt }   while loading
//               { type: 'ready', info }  |  { type: 'error', error, stage }
//               { type: 'phase', id, phase }  |  { type: 'log', id, text }   (Zig's stderr, live)
//               { type: 'result', id, result }   (result.wasm transferred)
//
// Downloads (build/manifest.json): zig.wasm.gz and zig-lib.bin.gz, each tried 3 times, checked
// against the manifest's SHA-256 and kept in the Cache API under that hash. Zig's /cache (the ZIR
// of every lib file, ~43 MB) is kept in IndexedDB with its own SHA-256; a record that does not
// verify or unpack is deleted and the compile starts from an empty cache. /cache is saved only
// after runs in which zig.wasm exited normally, never after a crash.
//
// This Worker is disposable: client.js terminates it after a crash, a time-out, a cancel or a
// run that grew zig.wasm's memory past RECYCLE_BYTES, and starts a fresh one for the next try.

import { MemFS } from './wasi.js';
import { compileTheme } from './zigc.js';
import { mountBundle, packTree, unpackTree } from './stdlib.js';

const CACHE_NAME = 'argus-zigc-v1';
const IDB_NAME = 'argus-zigc';
const IDB_FORMAT = 2;
const IDB_MAX_BYTES = 128 << 20;
const RECYCLE_BYTES = 1536 << 20;
let zig = null, fs = null, manifest = null, base = null, idbKey = '';

const post = (m, t) => self.postMessage(m, t || []);
const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
const sha256 = async (bytes) => hex(await crypto.subtle.digest('SHA-256', bytes));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function gunzip(bytes) {
  const s = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(s).arrayBuffer());
}

/// Fetch `url` with up to 3 attempts (0.5 s, then 2 s apart). Each attempt must keep receiving
/// bytes: 20 s without any is a failed attempt.
async function fetchRetry(url, label, onBytes) {
  let last;
  for (let attempt = 1; attempt <= 3; attempt++) {
    const ac = new AbortController();
    let stall = setTimeout(() => ac.abort(), 20000);
    const alive = () => { clearTimeout(stall); stall = setTimeout(() => ac.abort(), 20000); };
    try {
      const r = await fetch(url, { signal: ac.signal });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const parts = []; let loaded = 0;
      const reader = r.body.getReader();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        alive();
        parts.push(value); loaded += value.length;
        onBytes?.(loaded, attempt);
      }
      clearTimeout(stall);
      const out = new Uint8Array(loaded);
      let o = 0; for (const p of parts) { out.set(p, o); o += p.length; }
      return out;
    } catch (e) {
      clearTimeout(stall);
      last = ac.signal.aborted ? new Error('no data for 20 s') : e;
      if (attempt < 3) { post({ type: 'progress', phase: label, loaded: 0, total: 0, cached: false, attempt: attempt + 1, retry: String(last.message || last) }); await sleep(attempt === 1 ? 500 : 2000); }
    }
  }
  throw new Error(`${label}: ${new URL(url).pathname.split('/').pop()} did not download after 3 tries (${last && last.message || last})`);
}

/// The .gz at `entry.file`, from the Cache API if its hash is there, else downloaded and checked.
async function fetchAsset(entry, label) {
  const url = new URL(`${entry.file}?sha256=${entry.sha256}`, base).href;
  let cache = null;
  try { cache = await caches.open(CACHE_NAME); } catch { cache = null; } // no Cache API here (http, private mode): download
  let gz = null, cached = false;
  const hit = cache && await cache.match(url).catch(() => null);
  if (hit) { gz = new Uint8Array(await hit.arrayBuffer()); cached = true; }
  if (gz && await sha256(gz) !== entry.sha256) { gz = null; cached = false; await cache.delete(url).catch(() => {}); }
  if (!gz) {
    gz = await fetchRetry(url, label, (loaded, attempt) => post({ type: 'progress', phase: label, loaded, total: entry.gzBytes, cached: false, attempt }));
    const sha = await sha256(gz);
    if (sha !== entry.sha256) throw new Error(`${entry.file}: SHA-256 ${sha} does not match the manifest's ${entry.sha256}`);
    if (cache) {
      try {
        for (const k of await cache.keys()) if (k.url.split('?')[0] === url.split('?')[0] && k.url !== url) await cache.delete(k);
        await cache.put(url, new Response(gz, { headers: { 'content-type': 'application/gzip' } }));
      } catch { /* quota: the next visit downloads again */ }
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
    q.onblocked = () => rej(new Error('IndexedDB blocked'));
  });
}
function idbOp(mode, f) {
  return idb().then((db) => new Promise((res, rej) => {
    const t = db.transaction('cache', mode);
    const out = f(t.objectStore('cache'));
    t.oncomplete = () => { db.close(); res(out && out.result); };
    t.onerror = t.onabort = () => { db.close(); rej(t.error || new Error('IndexedDB transaction failed')); };
  }));
}

let saveTimer = null, cacheDirty = false;
function saveCacheSoon() {
  cacheDirty = true;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    if (!cacheDirty) return;
    cacheDirty = false;
    const p = packTree(fs, fs.cache);
    if (p.bytes > IDB_MAX_BYTES) return;
    const record = { format: IDB_FORMAT, sha256: await sha256(p.buffer), bytes: p.bytes, buf: p.buffer };
    // One entry, the current compiler's, written in one transaction (all or nothing).
    await idbOp('readwrite', (st) => { st.clear(); st.put(record, idbKey); }).catch(() => {}); // storage refused: the next visit runs AstGen again
  }, 300);
}

/// Restore /cache from IndexedDB. Returns { files, dropped } (dropped: why a record was deleted).
async function restoreCache(dropFirst) {
  if (dropFirst) { await idbOp('readwrite', (st) => st.clear()).catch(() => {}); return { files: 0, dropped: 'asked to start clean' }; }
  let rec = null;
  try { rec = await idbOp('readonly', (st) => st.get(idbKey)); } catch (e) { return { files: 0, dropped: null, unavailable: String(e.message || e) }; }
  if (!rec) return { files: 0, dropped: null };
  let why = null;
  if (rec.format !== IDB_FORMAT || !(rec.buf instanceof ArrayBuffer) || rec.buf.byteLength !== rec.bytes) why = 'wrong format or size';
  else if (await sha256(rec.buf) !== rec.sha256) why = 'checksum mismatch';
  else {
    try { return { files: unpackTree(fs, fs.cache, rec.buf), dropped: null }; } catch (e) { why = `unreadable (${e.message})`; }
  }
  await idbOp('readwrite', (st) => st.clear()).catch(() => {});
  return { files: 0, dropped: why };
}

async function init(msg) {
  base = new URL(msg.base);
  const t0 = performance.now();
  let r;
  try { r = await fetch(new URL('manifest.json', base), { cache: 'no-cache' }); } catch (e) { throw new Error(`build/manifest.json: ${e.message || e}`); }
  if (!r.ok) throw new Error(`build/manifest.json: HTTP ${r.status} (is the compiler built? make web-zigc)`);
  manifest = await r.json();
  idbKey = `${manifest.zig.sha256}:${manifest.lib.sha256}`;
  const [z, l, support] = await Promise.all([
    fetchAsset(manifest.zig, 'compiler'),
    fetchAsset(manifest.lib, 'std'),
    Promise.all(manifest.support.map(async ([virt, file]) => [virt, await fetchRetry(new URL(file, base).href, 'support')])),
  ]);
  const tDownload = performance.now() - t0;
  post({ type: 'progress', phase: 'starting', loaded: 0, total: 0, cached: z.cached && l.cached });
  zig = await WebAssembly.compile(z.bytes);
  const tCompile = performance.now() - t0 - tDownload;
  fs = new MemFS();
  const libFiles = mountBundle(fs, fs.lib, l.bytes);
  for (const [virt, bytes] of support) fs.writeFile(fs.cwd, virt, bytes, 1n);
  const cache = await restoreCache(!!msg.dropCache);
  return {
    zigVersion: manifest.zigVersion, libFiles, restoredCacheFiles: cache.files, cacheDropped: cache.dropped, cacheUnavailable: cache.unavailable || null,
    cachedDownloads: z.cached && l.cached, downloadBytes: (z.cached ? 0 : manifest.zig.gzBytes) + (l.cached ? 0 : manifest.lib.gzBytes),
    gzBytes: manifest.zig.gzBytes + manifest.lib.gzBytes, loadMs: performance.now() - t0, downloadMs: tDownload, wasmCompileMs: tCompile,
  };
}

const dec = new TextDecoder();
self.onmessage = async (e) => {
  const m = e.data;
  if (m.type === 'init') {
    try { post({ type: 'ready', info: await init(m) }); } catch (err) { post({ type: 'error', stage: 'load', error: String(err && err.message || err) }); }
    return;
  }
  if (m.type === 'compile') {
    try {
      const t0 = performance.now();
      const res = compileTheme(zig, fs, m.name, m.source, {
        onPhase: (phase) => post({ type: 'phase', id: m.id, phase }),
        onLog: (bytes) => post({ type: 'log', id: m.id, text: dec.decode(bytes) }),
      });
      res.ms = performance.now() - t0;
      res.recycle = !!res.crash || res.memBytes > RECYCLE_BYTES;
      post({ type: 'result', id: m.id, result: res }, res.wasm ? [res.wasm.buffer] : []);
      if (!res.crash) saveCacheSoon();
    } catch (err) {
      post({ type: 'error', id: m.id, stage: 'compile', error: String(err && err.stack || err) });
    }
  }
};

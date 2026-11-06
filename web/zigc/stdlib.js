// web/zigc/stdlib.js — mount a zig-lib bundle (web/zigc/bundle.zig) on a MemFS, and pack /cache.
//
// The bundle's files become lazy MemFS files whose bytes are views into the one buffer: nothing
// is copied until Zig writes to one (it never writes to /lib).

const dec = new TextDecoder();

/// Mount `bytes` (an uncompressed ZIGLIB1 bundle) at `dir`. Returns the file count.
export function mountBundle(fs, dir, bytes) {
  const magic = dec.decode(bytes.subarray(0, 8));
  if (magic !== 'ZIGLIB1\n') throw new Error('not a zig-lib bundle (bad magic)');
  const indexLen = new DataView(bytes.buffer, bytes.byteOffset + 8, 4).getUint32(0, true);
  const index = dec.decode(bytes.subarray(12, 12 + indexLen));
  let off = 12 + indexLen;
  let n = 0;
  for (const line of index.split('\n')) {
    if (!line) continue;
    const tab = line.lastIndexOf('\t');
    const path = line.slice(0, tab);
    const size = Number(line.slice(tab + 1));
    const view = bytes.subarray(off, off + size);
    fs.lazyFile(dir, path, size, () => view);
    off += size;
    n++;
  }
  if (off !== bytes.length) throw new Error(`zig-lib bundle: ${bytes.length - off} trailing bytes`);
  return n;
}

/// Pack every file under `dir` as one buffer: "ZCACHE1\n", then per file u32 path length,
/// path, u64 mtime, u32 size, bytes. For IndexedDB, which stores one ArrayBuffer quickly.
export function packTree(fs, dir) {
  const enc = new TextEncoder();
  const items = [];
  let total = 8;
  for (const [rel, n] of fs.walk(dir)) {
    fs.ensure(n);
    const p = enc.encode(rel);
    items.push([p, n]);
    total += 4 + p.length + 8 + 4 + n.size;
  }
  const out = new Uint8Array(total);
  const v = new DataView(out.buffer);
  out.set(enc.encode('ZCACHE1\n'), 0);
  let o = 8;
  for (const [p, n] of items) {
    v.setUint32(o, p.length, true); o += 4;
    out.set(p, o); o += p.length;
    v.setBigUint64(o, n.mtime, true); o += 8;
    v.setUint32(o, n.size, true); o += 4;
    out.set(n.data.subarray(0, n.size), o); o += n.size;
  }
  return { buffer: out.buffer, files: items.length, bytes: total };
}

/// The inverse of packTree. Returns the file count (0 if `buf` is not a pack).
export function unpackTree(fs, dir, buf) {
  const b = new Uint8Array(buf);
  if (b.length < 8 || dec.decode(b.subarray(0, 8)) !== 'ZCACHE1\n') return 0;
  const v = new DataView(buf);
  let o = 8, n = 0;
  while (o < b.length) {
    const pl = v.getUint32(o, true); o += 4;
    const path = dec.decode(b.subarray(o, o + pl)); o += pl;
    const mtime = v.getBigUint64(o, true); o += 8;
    const size = v.getUint32(o, true); o += 4;
    fs.writeFile(dir, path, b.slice(o, o + size), mtime); o += size;
    n++;
  }
  return n;
}

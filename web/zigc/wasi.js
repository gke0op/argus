// web/zigc/wasi.js — a WASI preview1 host for zig.wasm, with an in-memory filesystem.
//
// No dependencies; runs in a browser Worker and in Node. Every descriptor has every right (Node's
// built-in WASI denies zig.wasm's opens on a rights mismatch, so it cannot be used). Zig finds
// its lib directory and global cache through preopens named /lib and /cache, and the cwd
// through '.' (src/main.zig, wasi_preopens).
//
//   import { MemFS, runWasi } from './wasi.js';
//   const fs = new MemFS();
//   fs.writeFile(fs.cwd, 'theme/My_Theme.zig', bytes);
//   const { code, stdout, stderr } = runWasi(module, { args: ['zig', 'build-exe', ...], fs });
//
// Files can be lazy: a node with `load()` and no `data` reads its bytes on first open (the std
// sources, from a bundle or a disk).

export const ERRNO = { SUCCESS: 0, ACCES: 2, BADF: 8, EXIST: 20, INVAL: 28, IO: 29, ISDIR: 31, NAMETOOLONG: 37, NOENT: 44, NOSYS: 52, NOTDIR: 54, NOTEMPTY: 55, NOTSUP: 58, SPIPE: 70 };
const E = ERRNO;
const FT = { UNKNOWN: 0, CHAR: 2, DIR: 3, FILE: 4 };
const OFLAGS = { CREAT: 1, DIRECTORY: 2, EXCL: 4, TRUNC: 8 };
const FDFLAGS_APPEND = 1;
const ALL_RIGHTS = 0x1fffffffn;

// Stable inode numbers (FNV-1a of the path, 52 bits): Zig's cache manifests record inode, size
// and mtime, so a /cache restored on a later visit must see the same numbers for the same files.
function inoOf(path) {
  let h = 0xcbf29ce484222325n;
  for (let i = 0; i < path.length; i++) { h ^= BigInt(path.charCodeAt(i)); h = (h * 0x100000001b3n) & 0xffffffffffffffffn; }
  return h & 0xfffffffffffffn;
}

const enc = new TextEncoder();
const dec = new TextDecoder();
const nowNs = () => BigInt(Math.round((typeof performance !== 'undefined' ? performance.timeOrigin + performance.now() : Date.now()) * 1e6));

export class MemFS {
  constructor() {
    this.root = this.mkdirNode(null, '');
    this.cwd = this.mkdirp(this.root, 'cwd');
    this.lib = this.mkdirp(this.root, 'lib');
    this.cache = this.mkdirp(this.root, 'cache');
    this.opens = 0; this.lazyLoads = 0; this.lazyBytes = 0;
    this.onLoad = null; // (path) => void, for a log of the std files a compile reads
  }
  mkdirNode(parent, name) {
    const path = parent ? `${parent.path}/${name}` : '';
    return { type: 'dir', name, parent, path, ino: inoOf(path || '/'), mtime: 1n, children: new Map() };
  }
  fileNode(parent, name, data, mtime = nowNs()) {
    const path = `${parent.path}/${name}`;
    return { type: 'file', name, parent, path, ino: inoOf(path), mtime, data, size: data ? data.length : 0, load: null };
  }
  mkdirp(dir, rel) {
    for (const part of rel.split('/')) {
      if (!part || part === '.') continue;
      let n = dir.children.get(part);
      if (!n) { n = this.mkdirNode(dir, part); dir.children.set(part, n); }
      dir = n;
    }
    return dir;
  }
  /// Write (replace) a file under `dir` at relative path `rel`, creating directories.
  writeFile(dir, rel, data, mtime) {
    const parts = rel.split('/');
    const name = parts.pop();
    const d = this.mkdirp(dir, parts.join('/'));
    const bytes = typeof data === 'string' ? enc.encode(data) : data;
    const n = this.fileNode(d, name, bytes, mtime ?? nowNs());
    d.children.set(name, n);
    return n;
  }
  /// A file whose bytes come from `load()` on first open; `size` must be its exact length.
  lazyFile(dir, rel, size, load, mtime = 1n) {
    const parts = rel.split('/');
    const name = parts.pop();
    const d = this.mkdirp(dir, parts.join('/'));
    const n = this.fileNode(d, name, null, mtime);
    n.size = size; n.load = load;
    d.children.set(name, n);
    return n;
  }
  readFile(dir, rel) {
    const r = this.resolve(dir, rel);
    if (r.err || r.node.type !== 'file') return null;
    this.ensure(r.node);
    return r.node.data.subarray(0, r.node.size);
  }
  ensure(node) {
    if (node.data === null && node.load) {
      const b = node.load();
      node.data = b; node.size = b.length; node.load = null;
      this.lazyLoads++; this.lazyBytes += b.length;
      if (this.onLoad) this.onLoad(node.path);
    }
    if (node.data === null) node.data = new Uint8Array(0);
  }
  /// Resolve `rel` under `dir`. Returns { node } or { err, parent, name } (parent set when only
  /// the last component is missing, for creating it).
  resolve(dir, rel) {
    const parts = rel.split('/').filter((p) => p && p !== '.');
    let n = dir;
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (n.type !== 'dir') return { err: E.NOTDIR };
      if (p === '..') { n = n.parent ?? n; continue; }
      const c = n.children.get(p);
      if (!c) return i === parts.length - 1 ? { err: E.NOENT, parent: n, name: p } : { err: E.NOENT };
      n = c;
    }
    return { node: n };
  }
  /// Every file under `dir` as [relativePath, node] (for persisting the cache).
  *walk(dir, prefix = '') {
    for (const [name, c] of dir.children) {
      const rel = prefix ? `${prefix}/${name}` : name;
      if (c.type === 'dir') yield* this.walk(c, rel);
      else yield [rel, c];
    }
  }
}

class ProcExit extends Error { constructor(code) { super(`exit ${code}`); this.code = code; } }

/// Run a WASI command module to completion. opts: { args, env, fs (MemFS), preopens (name ->
/// dir node; default '.', '/lib', '/cache' of fs), onStdout/onStderr (Uint8Array) }.
/// Returns { code, stdout, stderr, ms }.
export function runWasi(module, opts) {
  const fs = opts.fs;
  const args = (opts.args || []).map((a) => enc.encode(a + '\0'));
  const env = Object.entries(opts.env || {}).map(([k, v]) => enc.encode(`${k}=${v}\0`));
  const out = { stdout: [], stderr: [] };
  const preopens = opts.preopens || [['.', fs.cwd], ['/lib', fs.lib], ['/cache', fs.cache]];

  // fd table: 0-2 stdio, then the preopens.
  const fds = new Map();
  fds.set(0, { kind: 'stdin' });
  fds.set(1, { kind: 'out', sink: 'stdout' });
  fds.set(2, { kind: 'out', sink: 'stderr' });
  preopens.forEach(([name, node], i) => fds.set(3 + i, { kind: 'node', node, pos: 0, preopen: name, append: false }));
  let nextFd = 3 + preopens.length;
  const freeFds = [];

  let memory = null;
  const u8 = () => new Uint8Array(memory.buffer);
  const dv = () => new DataView(memory.buffer);
  const str = (ptr, len) => dec.decode(u8().subarray(ptr, ptr + len));
  const node = (fd) => { const f = fds.get(fd); return f && f.kind === 'node' ? f : null; };

  function writeStat(ptr, n) {
    const v = dv();
    v.setBigUint64(ptr, 1n, true);
    v.setBigUint64(ptr + 8, n.ino, true);
    v.setUint8(ptr + 16, n.type === 'dir' ? FT.DIR : FT.FILE);
    for (let i = 17; i < 24; i++) v.setUint8(ptr + i, 0);
    v.setBigUint64(ptr + 24, 1n, true);
    v.setBigUint64(ptr + 32, BigInt(n.type === 'dir' ? 0 : n.size), true);
    v.setBigUint64(ptr + 40, n.mtime, true);
    v.setBigUint64(ptr + 48, n.mtime, true);
    v.setBigUint64(ptr + 56, n.mtime, true);
  }
  function grow(n, need) {
    fs.ensure(n);
    if (n.data.length >= need) return;
    const b = new Uint8Array(Math.max(need, n.data.length * 2, 4096));
    b.set(n.data.subarray(0, n.size));
    n.data = b;
  }
  function iovs(ptr, len) {
    const v = dv(); const r = [];
    for (let i = 0; i < len; i++) r.push([v.getUint32(ptr + i * 8, true), v.getUint32(ptr + i * 8 + 4, true)]);
    return r;
  }
  function readAt(n, list, pos) {
    fs.ensure(n);
    let total = 0; const m = u8();
    for (const [p, l] of list) {
      const k = Math.max(0, Math.min(l, n.size - pos));
      m.set(n.data.subarray(pos, pos + k), p);
      pos += k; total += k;
      if (k < l) break;
    }
    return total;
  }
  function writeAt(n, list, pos) {
    let total = 0;
    for (const [, l] of list) total += l;
    grow(n, pos + total);
    const m = u8();
    for (const [p, l] of list) { n.data.set(m.subarray(p, p + l), pos); pos += l; }
    if (pos > n.size) n.size = pos;
    n.mtime = nowNs();
    return total;
  }

  const w = {
    args_sizes_get(argc, bufsz) { const v = dv(); v.setUint32(argc, args.length, true); v.setUint32(bufsz, args.reduce((a, b) => a + b.length, 0), true); return 0; },
    args_get(argv, buf) { const v = dv(); const m = u8(); args.forEach((a, i) => { v.setUint32(argv + i * 4, buf, true); m.set(a, buf); buf += a.length; }); return 0; },
    environ_sizes_get(c, sz) { const v = dv(); v.setUint32(c, env.length, true); v.setUint32(sz, env.reduce((a, b) => a + b.length, 0), true); return 0; },
    environ_get(ep, buf) { const v = dv(); const m = u8(); env.forEach((a, i) => { v.setUint32(ep + i * 4, buf, true); m.set(a, buf); buf += a.length; }); return 0; },
    fd_prestat_get(fd, ptr) {
      const f = node(fd);
      if (!f || !f.preopen) return E.BADF;
      const v = dv(); v.setUint8(ptr, 0); v.setUint32(ptr + 4, enc.encode(f.preopen).length, true); return 0;
    },
    fd_prestat_dir_name(fd, ptr, len) {
      const f = node(fd);
      if (!f || !f.preopen) return E.BADF;
      u8().set(enc.encode(f.preopen).subarray(0, len), ptr); return 0;
    },
    proc_exit(code) { throw new ProcExit(code); },
    random_get(ptr, len) {
      const m = u8();
      for (let o = 0; o < len; o += 65536) crypto.getRandomValues(m.subarray(ptr + o, ptr + Math.min(len, o + 65536)));
      return 0;
    },
    clock_time_get(id, _prec, ptr) {
      const t = id === 0 ? nowNs() : BigInt(Math.round(performance.now() * 1e6));
      dv().setBigUint64(ptr, t, true); return 0;
    },
    clock_res_get(_id, ptr) { dv().setBigUint64(ptr, 1000n, true); return 0; },
    poll_oneoff(inp, outp, nsubs, nevents) {
      // Only clock subscriptions occur (sleeps); they complete at once.
      const v = dv();
      for (let i = 0; i < nsubs; i++) {
        const s = inp + i * 48, o = outp + i * 32;
        v.setBigUint64(o, v.getBigUint64(s, true), true);
        v.setUint16(o + 8, 0, true);
        v.setUint8(o + 10, v.getUint8(s + 8));
        for (let k = 11; k < 32; k++) v.setUint8(o + k, 0);
      }
      v.setUint32(nevents, nsubs, true); return 0;
    },
    fd_fdstat_get(fd, ptr) {
      const f = fds.get(fd);
      if (!f) return E.BADF;
      const v = dv();
      v.setUint8(ptr, f.kind === 'node' ? (f.node.type === 'dir' ? FT.DIR : FT.FILE) : FT.CHAR);
      v.setUint16(ptr + 2, f.append ? FDFLAGS_APPEND : 0, true);
      v.setBigUint64(ptr + 8, ALL_RIGHTS, true);
      v.setBigUint64(ptr + 16, ALL_RIGHTS, true);
      return 0;
    },
    fd_filestat_get(fd, ptr) {
      const f = fds.get(fd);
      if (!f) return E.BADF;
      if (f.kind !== 'node') { const v = dv(); for (let i = 0; i < 64; i += 8) v.setBigUint64(ptr + i, 0n, true); v.setUint8(ptr + 16, FT.CHAR); return 0; }
      writeStat(ptr, f.node); return 0;
    },
    fd_filestat_set_size(fd, size) {
      const f = node(fd);
      if (!f || f.node.type !== 'file') return E.BADF;
      const s = Number(size); grow(f.node, s);
      if (s > f.node.size) f.node.data.fill(0, f.node.size, s);
      f.node.size = s; f.node.mtime = nowNs(); return 0;
    },
    fd_filestat_set_times(fd, atim, mtim, flags) {
      const f = node(fd);
      if (!f) return E.BADF;
      if (flags & 4) f.node.mtime = mtim; else if (flags & 8) f.node.mtime = nowNs();
      return 0;
    },
    fd_sync() { return 0; },
    fd_seek(fd, off, whence, ptr) {
      const f = fds.get(fd);
      if (!f) return E.BADF;
      if (f.kind !== 'node') return E.SPIPE;
      const base = whence === 0 ? 0 : whence === 1 ? f.pos : f.node.size;
      const p = base + Number(off);
      if (p < 0) return E.INVAL;
      f.pos = p; dv().setBigUint64(ptr, BigInt(p), true); return 0;
    },
    fd_read(fd, iov, n, ptr) {
      const f = fds.get(fd);
      if (!f) return E.BADF;
      if (f.kind === 'stdin') { dv().setUint32(ptr, 0, true); return 0; }
      if (f.kind !== 'node' || f.node.type !== 'file') return f.kind === 'node' ? E.ISDIR : E.BADF;
      const k = readAt(f.node, iovs(iov, n), f.pos); f.pos += k; dv().setUint32(ptr, k, true); return 0;
    },
    fd_pread(fd, iov, n, off, ptr) {
      const f = node(fd);
      if (!f) return E.BADF;
      if (f.node.type !== 'file') return E.ISDIR;
      dv().setUint32(ptr, readAt(f.node, iovs(iov, n), Number(off)), true); return 0;
    },
    fd_write(fd, iov, n, ptr) {
      const f = fds.get(fd);
      if (!f) return E.BADF;
      const list = iovs(iov, n);
      if (f.kind === 'out') {
        let total = 0; const m = u8();
        for (const [p, l] of list) {
          const chunk = m.slice(p, p + l); total += l;
          out[f.sink].push(chunk);
          const cb = f.sink === 'stdout' ? opts.onStdout : opts.onStderr;
          if (cb) cb(chunk);
        }
        dv().setUint32(ptr, total, true); return 0;
      }
      if (f.kind !== 'node' || f.node.type !== 'file') return E.BADF;
      if (f.append) f.pos = f.node.size;
      const k = writeAt(f.node, list, f.pos); f.pos += k; dv().setUint32(ptr, k, true); return 0;
    },
    fd_pwrite(fd, iov, n, off, ptr) {
      const f = node(fd);
      if (!f || f.node.type !== 'file') return E.BADF;
      dv().setUint32(ptr, writeAt(f.node, iovs(iov, n), Number(off)), true); return 0;
    },
    fd_close(fd) {
      if (!fds.has(fd)) return E.BADF;
      if (fd > 2 + preopens.length) { fds.delete(fd); freeFds.push(fd); }
      return 0;
    },
    fd_readdir(fd, buf, len, cookie, ptr) {
      const f = node(fd);
      if (!f || f.node.type !== 'dir') return E.NOTDIR;
      const names = [...f.node.children.keys()];
      const v = dv(); const m = u8();
      let used = 0;
      for (let i = Number(cookie); i < names.length && used < len; i++) {
        const c = f.node.children.get(names[i]);
        const nb = enc.encode(names[i]);
        const ent = new Uint8Array(24 + nb.length);
        const ev = new DataView(ent.buffer);
        ev.setBigUint64(0, BigInt(i + 1), true);
        ev.setBigUint64(8, c.ino, true);
        ev.setUint32(16, nb.length, true);
        ev.setUint8(20, c.type === 'dir' ? FT.DIR : FT.FILE);
        ent.set(nb, 24);
        const k = Math.min(ent.length, len - used);
        m.set(ent.subarray(0, k), buf + used);
        used += k;
      }
      v.setUint32(ptr, used, true); return 0;
    },
    path_open(dirfd, _dirflags, pp, pl, oflags, _rb, _ri, fdflags, ptr) {
      const d = node(dirfd);
      if (!d) return E.BADF;
      if (d.node.type !== 'dir') return E.NOTDIR;
      const path = str(pp, pl);
      fs.opens++;
      let r = fs.resolve(d.node, path);
      let n = r.node;
      if (r.err) {
        if (r.err !== E.NOENT || !(oflags & OFLAGS.CREAT) || !r.parent) return r.err;
        n = fs.fileNode(r.parent, r.name, new Uint8Array(0));
        r.parent.children.set(r.name, n);
      } else {
        if ((oflags & OFLAGS.CREAT) && (oflags & OFLAGS.EXCL)) return E.EXIST;
        if ((oflags & OFLAGS.DIRECTORY) && n.type !== 'dir') return E.NOTDIR;
        if ((oflags & OFLAGS.TRUNC) && n.type === 'file') { n.data = new Uint8Array(0); n.size = 0; n.load = null; n.mtime = nowNs(); }
      }
      const fd = freeFds.length ? freeFds.pop() : nextFd++;
      fds.set(fd, { kind: 'node', node: n, pos: 0, append: !!(fdflags & FDFLAGS_APPEND), preopen: null });
      dv().setUint32(ptr, fd, true); return 0;
    },
    path_filestat_get(dirfd, _flags, pp, pl, ptr) {
      const d = node(dirfd);
      if (!d) return E.BADF;
      const r = fs.resolve(d.node, str(pp, pl));
      if (r.err) return r.err;
      writeStat(ptr, r.node); return 0;
    },
    path_create_directory(dirfd, pp, pl) {
      const d = node(dirfd);
      if (!d) return E.BADF;
      const r = fs.resolve(d.node, str(pp, pl));
      if (r.node) return E.EXIST;
      if (!r.parent) return r.err;
      r.parent.children.set(r.name, fs.mkdirNode(r.parent, r.name)); return 0;
    },
    path_unlink_file(dirfd, pp, pl) {
      const d = node(dirfd);
      if (!d) return E.BADF;
      const r = fs.resolve(d.node, str(pp, pl));
      if (r.err) return r.err;
      if (r.node.type === 'dir') return E.ISDIR;
      r.node.parent.children.delete(r.node.name); return 0;
    },
    path_remove_directory(dirfd, pp, pl) {
      const d = node(dirfd);
      if (!d) return E.BADF;
      const r = fs.resolve(d.node, str(pp, pl));
      if (r.err) return r.err;
      if (r.node.type !== 'dir') return E.NOTDIR;
      if (r.node.children.size) return E.NOTEMPTY;
      r.node.parent.children.delete(r.node.name); return 0;
    },
    path_rename(fd1, p1, l1, fd2, p2, l2) {
      const a = node(fd1), b = node(fd2);
      if (!a || !b) return E.BADF;
      const src = fs.resolve(a.node, str(p1, l1));
      if (src.err) return src.err;
      const dst = fs.resolve(b.node, str(p2, l2));
      let parent, name;
      if (dst.node) {
        if (dst.node === src.node) return 0;
        if (dst.node.type === 'dir' && (src.node.type !== 'dir' || dst.node.children.size)) return src.node.type === 'dir' ? E.NOTEMPTY : E.ISDIR;
        parent = dst.node.parent; name = dst.node.name;
      } else if (dst.parent) { parent = dst.parent; name = dst.name; } else return dst.err;
      src.node.parent.children.delete(src.node.name);
      src.node.parent = parent; src.node.name = name;
      parent.children.set(name, src.node); return 0;
    },
    path_readlink() { return E.INVAL; },
    path_symlink() { return E.NOTSUP; },
    path_link() { return E.NOTSUP; },
  };

  const imports = { wasi_snapshot_preview1: {} };
  for (const imp of WebAssembly.Module.imports(module)) {
    if (imp.module !== 'wasi_snapshot_preview1') continue;
    const f = w[imp.name] ?? (() => E.NOSYS);
    imports.wasi_snapshot_preview1[imp.name] = opts.trace ? (...a) => {
      let r;
      try { r = f(...a); } finally { opts.trace(imp.name, a, r, imp.name.startsWith('path_') ? str(a[2], a[3]) : ''); }
      return r;
    } : f;
  }
  const t0 = performance.now();
  const inst = new WebAssembly.Instance(module, imports);
  memory = inst.exports.memory;
  let code = 0;
  try { inst.exports._start(); } catch (e) {
    if (e instanceof ProcExit) code = e.code;
    else throw e;
  }
  const join = (chunks) => { let n = 0; for (const c of chunks) n += c.length; const b = new Uint8Array(n); let o = 0; for (const c of chunks) { b.set(c, o); o += c.length; } return dec.decode(b); };
  return { code, stdout: join(out.stdout), stderr: join(out.stderr), ms: performance.now() - t0 };
}

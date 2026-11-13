// site/assets/sources.js: a theme from anywhere (a share link, a dropped or pasted file) to a
// theme that engines.js mount() runs. Used by the home page and the bench.
//
// Share links carry the source in the URL fragment, which never reaches the server:
//   #zig=<raw deflate, base64url>&name=<Name>     a Zig theme (tools/share.zig, make share)
//   #wgsl=<raw deflate, base64url>&name=<Name>    a WGSL theme (web/README.md's contract)
// The same fragment works on the home page (the theme fills the hero) and on the bench (graded).

const WEB = new URL('../web/', import.meta.url);

/// A chat answer pasted whole: its largest fenced code block, else the text as it is.
export function unfence(s) {
  const blocks = [...s.matchAll(/```[^\n]*\n([\s\S]*?)```/g)].map((m) => m[1]);
  return blocks.length ? blocks.sort((a, b) => b.length - a.length)[0] : s;
}

/// A theme name both pages accept: letters, digits and _, starting with a letter or _.
export function themeName(fileName) {
  const n = String(fileName || '').replace(/^.*[\\/]/, '').replace(/\.(zig|wgsl|metal)$/i, '').replace(/[^A-Za-z0-9_]/g, '_');
  return /^[A-Za-z_]/.test(n) ? n : `T_${n || 'Theme'}`;
}

/// 'zig' | 'wgsl' | 'metal' | null, from the file name, else from the text.
export function kindOf(fileName, text = '') {
  const m = /\.(zig|wgsl|metal)$/i.exec(fileName || '');
  if (m) return m[1].toLowerCase();
  if (/@compute\b|textureStore\s*\(|\bvec[234]f\b/.test(text)) return 'wgsl';
  if (/\bkernel\s+void\b|\[\[\s*thread_position_in_grid\s*\]\]/.test(text)) return 'metal';
  if (/@import\s*\(|\bpub\s+fn\b|\bconst\s+std\b/.test(text)) return 'zig';
  return null;
}

const b64urlToBytes = (b) => {
  const s = atob(b.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (b.length % 4)) % 4));
  return Uint8Array.from(s, (c) => c.charCodeAt(0));
};
const bytesToB64url = (u8) => {
  let s = '';
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const viaStream = (bytes, stream) => new Response(new Blob([bytes]).stream().pipeThrough(stream));

/// The fragment for a theme: `zig=...&name=...` (no leading #).
export async function shareFragment(kind, name, src) {
  const packed = new Uint8Array(await viaStream(src, new CompressionStream('deflate-raw')).arrayBuffer());
  return `${kind}=${bytesToB64url(packed)}&name=${encodeURIComponent(name)}`;
}

/// A share link on `page` ('' = the home page, 'bench/' = the bench), from any page of the site.
export async function shareLink(kind, name, src, page = '') {
  return `${new URL(`../${page}`, import.meta.url).href}#${await shareFragment(kind, name, src)}`;
}

/// The theme in a location.hash, or null: { kind, name, source: Promise<string> }.
export function readShare(hash) {
  const p = new URLSearchParams(String(hash || '').replace(/^#/, ''));
  const kind = p.has('zig') ? 'zig' : p.has('wgsl') ? 'wgsl' : null;
  if (!kind) return null;
  const name = themeName(p.get('name') || 'Model_Theme');
  const source = viaStream(b64urlToBytes(p.get(kind)), new DecompressionStream('deflate-raw')).text();
  return { kind, name, source };
}

let compilerPromise = null;
/// The in-page Zig compiler (web/zigc/client.js), loaded on first use.
export function zigCompiler(onProgress) {
  compilerPromise ??= import(new URL('zigc/client.js', WEB)).then((m) => m.getCompiler({ onProgress }));
  return compilerPromise;
}

/// One frame of `m` (engine.js moduleFromBytes) at 320x200 on one thread: CPU ms, or undefined after 10 s.
export async function speedProbe(m, signal) {
  const { startEngine } = await import(new URL('wasm/engine.js', WEB));
  let eng = null, stop = false;
  const work = (async () => {
    eng = await startEngine({ module: m.module, threaded: false, threads: 1 });
    if (stop) return undefined;
    const { ptr } = await eng.leader.call('liveInit', { w: 320, h: 200, scale: 2 });
    if (!ptr) return null;
    await eng.leader.call('frame', { dt: 0.008, w: 320, h: 200, ptr });
    return (await eng.leader.call('frame', { dt: 0.008, w: 320, h: 200, ptr })).cpuMs;
  })().catch(() => null);
  let t;
  const r = await Promise.race([work, new Promise((res) => { t = setTimeout(() => res(undefined), 10000); signal?.addEventListener('abort', () => res(undefined), { once: true }); })]);
  clearTimeout(t);
  stop = true;
  eng?.terminate();
  work.then(() => eng?.terminate());
  return r;
}

/// The pixels this build can draw in about `ms` per frame, from its 320x200 time (at most 1920x1200).
export const pixelsFor = (ms320, ms = 25) => (ms320 > 0 ? Math.max(320 * 200, Math.min(1920 * 1200, Math.round((320 * 200 * ms) / ms320))) : undefined);

export class SourceError extends Error {
  constructor(message, log = '') { super(message); this.log = log; }
}

/// Zig source -> { theme, opts } for mount(): compiled in this page by Zig 0.17.0 (wasm backend,
/// no SIMD, one thread) and sized so a frame takes ~25 ms. Throws SourceError with the log.
export async function zigToLive(name, src, { onPhase, onProgress, signal } = {}) {
  onPhase?.('loading the compiler');
  const zc = await zigCompiler(onProgress);
  const c = await zc.compile(name, src, {
    signal,
    timeoutMs: 120000,
    onPhase: (p) => onPhase?.(p === 'sema' ? 'compiling: type-checking' : 'compiling: building the module'),
  });
  if (c.crash) throw new SourceError(`the compiler stopped (${c.crash.kind})`, c.crash.stderr || '');
  if (!c.gate1.ok) throw new SourceError('it does not compile (Zig 0.17.0’s errors below)', c.gate1.log);
  if (!c.ok) throw new SourceError('this page’s compiler (Zig’s wasm backend, no LLVM) could not build it; the native harness can', c.build.log);
  onPhase?.('starting it');
  const { moduleFromBytes } = await import(new URL('wasm/engine.js', WEB));
  const module = await moduleFromBytes(c.wasm);
  const maxPixels = pixelsFor(await speedProbe(module, signal));
  return {
    theme: { id: `yours:${name}`, label: name, kind: 'wasm', build: name, line: 'compiled in this page by Zig 0.17.0 as WebAssembly (one thread, no SIMD).', yours: true },
    opts: { module, maxPixels, label: 'wasm (Zig compiled in this page)' },
  };
}

/// WGSL source -> a theme for mount() (WebGPU compiles it).
export const wgslToLive = (name, src) => ({ id: `yours:${name}`, label: name, kind: 'wgsl-source', source: src, line: 'WGSL compiled by this browser’s WebGPU.', yours: true });

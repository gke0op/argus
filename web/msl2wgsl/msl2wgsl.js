// web/msl2wgsl/msl2wgsl.js: Metal to WGSL in the page, by tools/msl2wgsl.zig built to wasm
// (tools/msl2wgsl_wasm.zig, `make web-msl2wgsl`). The same translator the site's build and the
// Bench workflow run, so a .metal dropped or linked here becomes the WGSL they would make.
//
//   const r = await translate(source, 'themes/My_Theme.metal');
//   r.ok ? r.wgsl : `${r.line}:${r.col}: ${r.message}`
//
// Works in a browser and in Node 22 (pass the module's bytes as `bytes` there).

let instance = null;

async function load(bytes) {
  if (instance) return instance;
  const src = bytes ?? (await (await fetch(new URL('msl2wgsl.wasm', import.meta.url))).arrayBuffer());
  ({ instance } = await WebAssembly.instantiate(src, {}));
  return instance;
}

/// { ok: true, wgsl } or { ok: false, line, col, message }.
export async function translate(source, label = 'theme.metal', { bytes } = {}) {
  const x = (await load(bytes)).exports;
  const enc = new TextEncoder();
  const put = (s) => {
    const b = enc.encode(s);
    const p = x.alloc(Math.max(1, b.length));
    if (!p) throw new Error('msl2wgsl: out of memory');
    new Uint8Array(x.memory.buffer, p, b.length).set(b);
    return [p, b.length];
  };
  try {
    const [sp, sl] = put(source);
    const [lp, ll] = put(label);
    const status = x.translate(sp, sl, lp, ll);
    const text = new TextDecoder().decode(new Uint8Array(x.memory.buffer, x.result_ptr(), x.result_len()));
    if (status === 1) return { ok: true, wgsl: text };
    if (status === 2) throw new Error('msl2wgsl: out of memory');
    const m = /^(\d+):(\d+): ([\s\S]*)$/.exec(text);
    return m ? { ok: false, line: +m[1], col: +m[2], message: m[3] } : { ok: false, line: 0, col: 0, message: text };
  } finally {
    x.reset();
  }
}

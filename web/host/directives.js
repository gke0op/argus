// web/host/directives.js — `// @argus ...` directives, parsed exactly as src/gpu/metal_theme.zig
// (parseDirectives) does for Metal themes, so a WGSL port keeps its Metal header unchanged.
//
//   // @argus state WxH [float32]      persistent state texture (rgba16float, or rgba32float)
//   // @argus steps N                  argus_step runs N times per 30 Hz tick (1..64)
//   // @argus data Name.bin WxH [rgba8|rgba16f]   raw texels next to the theme, for argus_init
//   // @argus stats                    the theme reads the ArgusStats buffer

export const MAX_STATE_SIDE = 4096;
export const MAX_STEPS = 64;
export const MAX_DATA_NAME = 64;

const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

// Zig's std.fmt.parseInt(u32, s, 10) for the plain decimal forms themes use; null when invalid.
function parseU32(s) {
  if (!/^\+?\d+$/.test(s)) return null;
  const v = Number(s);
  return v > 0xffffffff ? null : v;
}

function parseSize(tok) {
  const x = tok.indexOf('x');
  if (x < 0) return null;
  const w = parseU32(tok.slice(0, x));
  const h = parseU32(tok.slice(x + 1));
  if (w === null || h === null) return null;
  return [clamp(w, 1, MAX_STATE_SIDE), clamp(h, 1, MAX_STATE_SIDE)];
}

export function parseDirectives(src) {
  const d = {
    stateW: 0, stateH: 0, stateF32: false, steps: 1,
    dataName: null, dataW: 0, dataH: 0, dataF16: false,
    stats: false,
  };
  for (const line of src.split('\n')) {
    const at = line.indexOf('@argus');
    if (at < 0) continue;
    const it = line.slice(at + '@argus'.length).split(/[ \t\r]+/).filter((t) => t.length > 0);
    const key = it[0];
    if (key === undefined) continue;
    if (key === 'state') {
      if (it[1] === undefined) continue;
      const sz = parseSize(it[1]);
      if (!sz) continue;
      [d.stateW, d.stateH] = sz;
      if (it[2] !== undefined) d.stateF32 = it[2] === 'float32';
    } else if (key === 'steps') {
      if (it[1] === undefined) continue;
      const n = parseU32(it[1]);
      if (n === null) continue;
      d.steps = clamp(n, 1, MAX_STEPS);
    } else if (key === 'data') {
      const name = it[1];
      if (name === undefined || name.length === 0 || name.length > MAX_DATA_NAME || name[0] === '.' ||
          /[/\\]/.test(name)) continue;
      if (it[2] === undefined) continue;
      const sz = parseSize(it[2]);
      if (!sz) continue;
      const fmt = it[3] ?? 'rgba8';
      if (fmt !== 'rgba8' && fmt !== 'rgba16f') continue;
      d.dataName = name;
      [d.dataW, d.dataH] = sz;
      d.dataF16 = fmt === 'rgba16f';
    } else if (key === 'stats') {
      d.stats = true;
    }
  }
  return d;
}

export function dataBytes(d) {
  return d.dataW * d.dataH * (d.dataF16 ? 8 : 4);
}

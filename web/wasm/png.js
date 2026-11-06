// web/wasm/png.js — decode the harness's PNGs exactly (8-bit RGB or RGBA, non-interlaced),
// so the page compares raw pixel values instead of letting colour management touch them.
// Uses DecompressionStream('deflate') (browsers, Node 18+).

export async function decodePNG(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
  const sig = [137, 80, 78, 71, 13, 10, 26, 10];
  for (let i = 0; i < 8; i++) if (u8[i] !== sig[i]) throw new Error('not a PNG');
  let w = 0, h = 0, depth = 0, ctype = 0, interlace = 0;
  const idat = [];
  for (let p = 8; p < u8.length;) {
    const len = dv.getUint32(p);
    const type = String.fromCharCode(u8[p + 4], u8[p + 5], u8[p + 6], u8[p + 7]);
    const data = u8.subarray(p + 8, p + 8 + len);
    if (type === 'IHDR') {
      w = dv.getUint32(p + 8); h = dv.getUint32(p + 12);
      depth = u8[p + 16]; ctype = u8[p + 17]; interlace = u8[p + 20];
    } else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    p += 12 + len;
  }
  if (depth !== 8 || (ctype !== 2 && ctype !== 6) || interlace !== 0) {
    throw new Error(`unsupported PNG: depth ${depth} colour type ${ctype} interlace ${interlace}`);
  }
  const ch = ctype === 6 ? 4 : 3;
  const z = new Blob(idat).stream().pipeThrough(new DecompressionStream('deflate'));
  const raw = new Uint8Array(await new Response(z).arrayBuffer());
  const rowLen = w * ch;
  const out = new Uint8Array(w * h * 4);
  let prev = new Uint8Array(rowLen), cur = new Uint8Array(rowLen);
  for (let y = 0; y < h; y++) {
    const base = y * (rowLen + 1);
    const f = raw[base];
    for (let i = 0; i < rowLen; i++) {
      const x = raw[base + 1 + i];
      const a = i >= ch ? cur[i - ch] : 0, b = prev[i], c = i >= ch ? prev[i - ch] : 0;
      let v;
      switch (f) {
        case 0: v = x; break;
        case 1: v = x + a; break;
        case 2: v = x + b; break;
        case 3: v = x + ((a + b) >> 1); break;
        case 4: {
          const pp = a + b - c, pa = Math.abs(pp - a), pb = Math.abs(pp - b), pc = Math.abs(pp - c);
          v = x + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
          break;
        }
        default: throw new Error('bad PNG filter ' + f);
      }
      cur[i] = v & 255;
    }
    for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 4;
      out[o] = cur[x * ch]; out[o + 1] = cur[x * ch + 1]; out[o + 2] = cur[x * ch + 2];
      out[o + 3] = ch === 4 ? cur[x * ch + 3] : 255;
    }
    [prev, cur] = [cur, prev];
  }
  return { width: w, height: h, rgba: out };
}

/// Compare two RGBA byte arrays on R, G, B: equal pixels, max channel difference, a histogram
/// of the per-pixel max difference (0, 1, 2, 3+).
export function comparePixels(a, b) {
  if (a.length !== b.length) throw new Error(`size mismatch ${a.length} vs ${b.length}`);
  let equal = 0, maxDiff = 0;
  const hist = [0, 0, 0, 0];
  for (let i = 0; i < a.length; i += 4) {
    const d = Math.max(Math.abs(a[i] - b[i]), Math.abs(a[i + 1] - b[i + 1]), Math.abs(a[i + 2] - b[i + 2]));
    if (d === 0) equal++;
    if (d > maxDiff) maxDiff = d;
    hist[Math.min(d, 3)]++;
  }
  return { pixels: a.length / 4, equal, maxDiff, hist };
}

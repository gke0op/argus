# Cygnus A on WebGPU

Argus's flagship theme in the browser: the Kerr black hole and its disk, traced per pixel on
the GPU, built like the app's GPU path (`src/gpu/bh_gpu.zig`, `src/gpu/presenter.zig`).

| file | what it is |
|---|---|
| `cygnus.wgsl` | `src/gpu/opus_black_hole.metal` ported to WGSL, kernel for kernel: `bh_meter`, `bh_trace`, `bh_footprint`, `bh_shade` (+ `bh_shade_canvas`, `fs_shade`), `bh_probe` |
| `cygnus_wasm.zig` → `cygnus.wasm` | the real theme (`themes/Cygnus_A.zig`) and `src/gpu/bh_tables.zig` compiled to wasm32-freestanding (79 KB): tables, trace geometry and every frame's `step()` state |
| `cygnus.js` | the engine module: `create(canvas, opts)` |
| `index.html` | dev page (`h` toggles the HUD) |
| `verify/` | checks against the app: tables, same-frame pixels, Bardeen contour, timings |
| `build.sh` | rebuilds `cygnus.wasm` (run from the repo root) |

## Interface

```js
import { create } from './cygnus.js';
const e = await create(canvas, opts);
e.frame(timeSec, dtSec);  // step() in wasm, then one shade pass into the canvas
e.resize(w, h);           // sets the canvas size; re-traces progressively, as the app does
e.stats();                // { gpuMs, cpuMs, wasmKB, wasmFileKB, traceMs, traceGpuMs, rowsDone, height, exposure, ... }
e.destroy();
```

`opts`: `device` (share one), `hdr` + `headroom` (rgba16float canvas, extended tone mapping;
headroom 1 is the app's SDR curve), `incl` (degrees; the theme's is 88), `tileMs` (GPU time per
trace tile, default 12), `onTraceDone(stats)`.

Time runs as in the app's pacer (`src/desktop/frame_rate.zig`): `step(0.008)` per 1/30 s,
at most one tick per frame, so `step(min(dt, 1/30) * 0.24)`.

## How it runs

1. **Once:** `cyg_init` builds the theme's tables in wasm (the app's own Zig); they go to the GPU
   as the presenter uploads them.
2. **On create and every resize:** `bh_meter` traces a 192-wide grid; the theme's own
   `exposureFrom` (wasm) turns it into the exposure. Then `bh_trace` runs in row tiles (whole
   8-row workgroups, at most two in flight, each tile's height steered to ~12 ms of GPU), so the
   image fills top-down while frames keep presenting (rows not traced yet are black), then
   `bh_footprint`. The trace keeps 13 bytes per pixel (+2 while tracing), as the app.
3. **Every frame:** `step()` in wasm, the 1320-byte `Frame` uploaded, one compute shade into an
   offscreen texture copied to the canvas. (Storage writes straight into the canvas texture,
   and the same shade as a fragment shader, both measured slower: `opts.direct`, `opts.fragment`.)

## Port notes

The Metal kernels already run in f32 (Apple GPUs have no f64), so the numerics carry over
unchanged. WGSL lacks some things the Metal source uses:

- no 8/16-bit types: `Rec` is `rec_a = rbin | phi << 16`, `rec_b = meta | lmu << 16 | ftr << 24`;
  `bfrac` (4 px per word) and `tq` (2 px per word) are written with `atomicOr`;
- no 64-bit integers: the sky's splitmix64 runs on `(lo, hi)` u32 pairs (Cygnus A's sky is
  black, `SKY_VISIBLE = 0`, so this path is ported but not exercised by its frames);
- WGSL `round()` rounds halves to even, Metal's away from zero: `roundAway()`;
- no `isfinite()`: the exponent bits are tested;
- `Frame` is a uniform read by word offset (uniform arrays need a 16-byte stride).

The wasm build turned up one portability bug in the theme: the turbulence lattice hash mixed
`usize` indices into a u64 seed, which overflowed on 32-bit targets. Fixed in
`tools/quasar_template.zig` and `themes/Cygnus_A.zig` with `@as(u64, ...)`; native bytes are
unchanged.

## Verification (Apple M3, Chromium 152 in Claude's browser pane, 2026-11-06)

Run `zig run web/cygnus/verify/serve.zig -- . 8735` from the repo root and open
`/web/cygnus/verify/?size=1920x1080&skip=300&fps=60&contour=1&frames=600`.

**Tables** (`verify/dump_native.zig` + `verify/compare_tables.mjs`, after 300 steps of 0.004):
`Static`, the turbulence noise (4 MB) and `TraceParams` are byte-identical to the native build.
The disk table differs in 2 of 16384 floats by 1 ulp (relative 6.7e-8 and 6.1e-8: macOS libm vs
Zig's own f64 math in the theme's init). `Frame` is identical except `width`/`height`, the theme's
own canvas size (16x10 here), which no kernel reads.

**Exposure:** the WGSL meter gives 10.7955 at 960x540 and 1920x1080, the same as the app's Metal
meter.

**Same frame as the app** (1920x1080, 88°, a = 0.9, t = 12 M, i.e. `--skip 300 --fps 60`, SDR
sRGB 8-bit): 99.9961% of pixels identical (2,073,519 of 2,073,600); 79 pixels differ by 1
level, 2 by 2 levels, none by more; scattered single pixels at rounding boundaries. Mean
|difference| 1.67e-5 levels per channel. The reference is `src/offline_render_bh.zig` with one
line changed so that, like the live app's presenter, it traces with the metered exposure
(`verify/out/applive_*`). The renderer as committed traces with `TraceParams.exposure = 1` and
sets the metered exposure only for the shade; matched to that (`&texpo=1`, 960x540), 99.9961%
are identical and 20 pixels differ by 1 level.

**Shadow edge vs Bardeen's critical curve** (`gpu_bench`'s sweep on the WGSL `bh_probe`: 766
points, 32 bisections): max 1.79e-5 M (off-axis 1.79e-5, polar band 7.62e-6), rms 3.70e-6 M,
0 bracket failures. These are the same figures `gpu_bench` reports for the Metal kernel, and
within the ledger's bounds (max 1e-2, rms 1e-3, off-axis max and rms 1e-4, 0 brackets).

**Timing** (WebGPU timestamp queries, mean of the last 120 frames; Metal from
`gpu_bench` on the same machine within minutes; the machine was shared with other work, and
runs during heavy contention, which slowed native and web alike by 5-10x, are left out):

| | WebGPU | Metal (`gpu_bench`) |
|---|---|---|
| trace 1920x1080 | 0.91 s GPU (0.95 s wall incl. meter) | 1.81 s |
| trace 3024x1964 | 2.53 s GPU (2.60 s wall) | 3.86 s |
| shade 1920x1080 | 0.81-1.02 ms/frame | 0.56 ms (unpaced) |
| shade 3024x1964 | 1.47 ms/frame | 1.59 ms (unpaced), 2.68 ms paced at 30 FPS |

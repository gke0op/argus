# Argus in the browser

`web/` runs Argus themes live in a browser. This part is the **WebGPU runtime for Metal themes**:
each `themes/<Name>.metal` has a one-to-one WGSL translation in `web/themes/<Name>.wgsl`, run by
`web/host/argus_gpu.js` with the same frame semantics as the Mac app (`src/gpu/metal_theme.zig`).
No video stand-ins and no reduced versions: the kernels run in full at the canvas's device-pixel
size, on every display frame.

| Path | What it is |
|---|---|
| `web/index.html` | Dev page: theme picker, frame-ms readout (the real site comes later) |
| `web/prelude.wgsl` | The WGSL twin of `src/gpu/argus_prelude.metal` |
| `web/themes/*.wgsl` | Theme translations; `.bin` data files sit next to them (byte-identical copies of `themes/*.bin`) |
| `web/host/argus_gpu.js` | The engine: compile, directives, state, data, stats, present, timing |
| `web/host/frame.js` | `ArgusFrame`: the 4 h-wrapped f64 clock, the 30 Hz tick, the J2000 date fields |
| `web/host/stats.js` | `ArgusStats`: the harness's synthetic feed, and what a browser can read live |
| `web/host/directives.js` | `// @argus` parsing, as `parseDirectives` in `metal_theme.zig` |
| `web/host/verify.html`, `web/host/tools/verify.mjs` | The Metal harness's check in the browser, and a headless driver that compares against the harness PNG |

Serve `web/` over `http://localhost` (WebGPU needs a secure context; `file://` won't do), e.g.
`python3 -m http.server -d web 8000`, then open `http://localhost:8000/`.

## The engine interface

Every web engine (this one; the Cygnus A engine in `web/cygnus/`; the wasm host in `web/wasm/`)
exports the same function, so a page can drive any of them the same way:

```js
import { create, runLoop } from './host/argus_gpu.js';

const engine = await create(canvas, { theme: 'Night_Tide' });
// engine.name                    'Night_Tide'
// engine.frame(timeSec, dtSec)   draw one display frame; dtSec = time since the previous frame
// engine.resize(w, h)            output size in device pixels (followed automatically by default)
// engine.stats()                 { gpuMs?, cpuMs?, wasmKB? } (this engine: gpuMs, cpuMs; medians of the last 240 frames)
// engine.destroy()
const stop = runLoop(engine);   // requestAnimationFrame at the display's refresh rate
```

`create(canvas, opts)` options for this engine:

| Option | Default | Meaning |
|---|---|---|
| `theme` | — | A name in `web/themes/` (`'Night_Tide'`) or a URL to a `.wgsl` file |
| `source`, `dataBase` | — | WGSL source given directly (a benchmark's model output), and where its `.bin` lives |
| `seed` | random per load | `f.seed` (the harness uses `0x5EED`) |
| `date` | `'system'` | Or `'YYYY-MM-DDTHH:MM:SSZ'`: pinned, advancing with the theme's clock, as the harness's `--date` |
| `utcOffset` | `0` | `f.utc_offset_s` with a pinned date (the system date uses the browser's time zone) |
| `stats` | `'browser'` | For `@argus stats` themes: `'browser'` (live where a browser can tell, see below) or `'synthetic'` (the harness feed) |
| `pixelRatio` | `devicePixelRatio` | Canvas pixels per CSS pixel |
| `autoResize` | `true` | Follow the canvas's displayed size (`ResizeObserver`, device-pixel box) |
| `offscreen` | — | `{ width, height, format }`: render into a texture instead of a canvas (the verify page; `engine.readback()`) |
| `device` | shared | A `GPUDevice` to use |

Errors are thrown with the theme's own line numbers (`Night_Tide.wgsl:212:9: error: ...`), so a
benchmark can hand them back to the model that wrote the theme.

### Frame semantics (as `metal_theme.zig`)

- **Clock.** `f.time` is an f64 clock of the summed f32 frame intervals, wrapped every 4 h
  (`ARGUS_TIME_PERIOD`) and narrowed to f32. The first frame sees `f.time = 0`.
- **Ticks and steps.** `argus_step` runs on a 30 Hz logic tick at any refresh rate (`steps`
  times per tick, ping-ponging two state textures); frames between ticks only draw. The first
  frame is a whole tick, and a stall moves time by at most one tick, as in the app's pacer.
  `f.frame` is the tick count; `f.dt` is 1/30 s in `argus_init`/`argus_step` and the frame
  interval in `argus_draw`.
- **State.** `@argus state WxH [float32]`: two `rgba16float` (or `rgba32float`) textures,
  initialised once by `argus_init` (or cleared to zero without one).
- **Data.** `@argus data Name.bin WxH rgba8|rgba16f`: fetched next to the theme, must be exactly
  `W*H*4` (or `*8`) bytes, given to `argus_init` as `argus_data`.
- **Date.** `days_j2000`, `day_frac`, `utc_offset_s` from the system clock each frame
  (`performance.timeOrigin + performance.now()`, the browser's time zone), split exactly as the
  app splits it (integer days, f64 fraction narrowed to f32, kept below 1).
- **Present.** The draw kernel writes straight into the canvas's texture (`bgra8unorm` with the
  `bgra8unorm-storage` feature, else `rgba8unorm`), opaque.
- **Timing.** With `timestamp-query`, `stats().gpuMs` is the GPU time of the whole frame
  (init, steps and draw), read back asynchronously so it never stalls the frame.

### Stats in a browser

A web page can't read the machine the way Argus does. `stats: 'browser'` fills what a browser can
honestly tell and keeps the rest on the harness's synthetic feed; `engine.statsSources()` says
which is which, and `index.html` shows it:

| Field | Source |
|---|---|
| `seq`, `sample_dt` | live: a new sample about once a second |
| `cpu_count` | live: `navigator.hardwareConcurrency` (P/E split unknown: 0; per-core loads synthetic) |
| `thermal` | live where available: the Compute Pressure API's CPU pressure state (Chromium) |
| `battery_*`, `on_ac` | live where available: the Battery Status API (Chromium) |
| `gpu_busy` | live: this page's own GPU time / frame interval |
| `uptime_s` | live: the page's uptime, not the machine's |
| everything else (per-core load, memory size and use, network, disk, processes) | synthetic (`navigator.deviceMemory` is capped at 8 GB, so it isn't used) |

## Writing or translating a theme in WGSL

`web/prelude.wgsl` is prepended to the theme. It declares `f` (the `ArgusFrame` uniform), `s`
(`ArgusStats`), the state/data textures, Metal-like samplers, and the helpers (`argus_uv`,
`argus_uv01`, `argus_hash`, `argus_rand`, `argus_noise`, `argus_fbm`, `argus_palette`,
`argus_srgb`, `argus_aces`, `argus_days_j2000`, `argus_utc_seconds`, `argus_sample`,
`argus_proc_char`). Entry points are compute shaders named as in Metal:

```wgsl
@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    textureStore(argus_out, gid, vec4f(colour, 1.0));
}
```

| Metal | WGSL |
|---|---|
| `constant ArgusFrame& f [[buffer(0)]]` | the module-scope `f` |
| `constant ArgusStats& s [[buffer(1)]]` (with `@argus stats`) | the module-scope `s`; `s.procs[i].name[j]` is `argus_proc_char(i, j)` |
| `out.write(c, gid)` in `argus_draw` | `textureStore(argus_out, gid, c)` |
| `state.write(v, gid)` in `argus_init`; `next.write(v, gid)` in `argus_step` | `textureStore(argus_state_out, gid, v)` |
| `prev.read(p)` in `argus_step`; `state.read(p)` in `argus_draw` | `textureLoad(argus_state, p, 0)` |
| `data.read(p)` / `.sample` in `argus_init` | `textureLoad(argus_data, p, 0)` / `textureSampleLevel(argus_data, ...)` |
| `tex.get_width()` | `textureDimensions(tex).x` |
| `constexpr sampler(filter::linear[, address::clamp_to_edge])` | `argus_linear_clamp` |
| `... address::repeat` | `argus_linear_repeat` |
| `... s_address::repeat, t_address::clamp_to_edge` | `argus_linear_repeat_s` (and `_t` for the reverse) |
| `constexpr sampler()` (nearest) | `argus_nearest_clamp` |
| `tex.sample(smp, uv)` | `argus_sample(tex, smp, uv)` (= `textureSampleLevel(..., 0.0)`; compute has no derivatives) |
| `coord::pixel` samplers | divide the coordinate by `vec2f(textureDimensions(tex))` |
| `threadgroup T x[N]`, `atomic_uint` | `var<workgroup> x: array<T, N>`, `atomic<u32>`; `workgroupBarrier()` |
| `thread_position_in_threadgroup`, `threads_per_threadgroup` | `@builtin(local_invocation_id)`, the declared `@workgroup_size` |

Language traps when translating from Metal:

- No implicit conversions: `i32`, `u32` and `f32` mix only through `f32(...)`, `u32(...)`, and
  scalars don't silently become vectors in constructors or assignments (`vec3f(x)`; but
  `vec3f + f32` arithmetic is fine). `u32(i32)` keeps the bits, as Metal's `uint(int)`.
- `a ? b : c` becomes `select(c, b, a)`, which evaluates both sides: keep real branches where a
  side indexes out of range or costs a lot.
- No swizzle assignment (`v.xy = ...`): assign components or rebuild the vector.
- Parameters are immutable (copy to a `var`); `x++` is a statement, never an expression.
- `round()` differs: Metal rounds halves away from zero, WGSL to even (`rint` matches WGSL's).
  Translate Metal's `round(x)` as `select(floor(x + 0.5), ceil(x - 0.5), x < 0.0)`-style code.
- `pow(x, y)` with a negative `x` is undefined in WGSL (NaN on some backends); Metal folds
  `pow(x, 2.0f)` into `x * x`, so write the product.
- `fmod(x, y)` is `x % y` for floats (both truncate); `rsqrt` is `inverseSqrt`; `atan2`, `fract`,
  `mix`, `clamp`, `saturate`, `smoothstep`, `step`, `fma` keep their meaning. There is no `isnan`.
- Matrices are column-major in both: `float2x2(a, b, c, d)` is `mat2x2f(a, b, c, d)`.
- `as_type<uint>(x)` is `bitcast<u32>(x)`; Metal's `half` is translated to `f32`.
- `workgroupBarrier()` must be in uniform control flow: don't `return` early before it (compute an
  `inside` flag instead).
- Some identifiers are reserved in WGSL (`smooth`, `sample`, `filter`, `target`, `common`,
  `module`, `static`, ...): rename them.
- Keep the theme's header and its `// @argus` lines verbatim, so the directives and the honest
  account of what is measured and what is modelled carry over.

## Verify a theme like the harness

```sh
make harness THEME=themes/Night_Tide.metal FRAMES=120 OUT=/tmp/ref/Night_Tide.png      # Metal (macOS)
node web/host/tools/verify.mjs --theme Night_Tide --ref /tmp/ref/Night_Tide.png --out /tmp/verify
```

`verify.mjs` (Node 22+, no dependencies) serves `web/`, opens `web/host/verify.html` in headless
Chrome with WebGPU, renders the harness's frames (1920x1200, dt = 1/30 s with a step every frame,
seed `0x5EED`, the date pinned to 2026-10-20T12:00:00Z), and reports:

- the harness gates on the first and last frame: NaN/Inf, distinct pixels, animated pixels
  (at least 2,000), and the alpha range;
- GPU time per frame from timestamp queries (60 frames, one at a time like the harness);
- the difference from the Metal PNG of the same frame (mean and max per channel in 0..255, PSNR,
  the share of pixels within 0, 1, 2, 4, 8... levels), with `<Theme>_web.png` and
  `<Theme>_diff.png` (the difference x 8) written to `--out`.

## Verified on this branch

Chrome 157, Apple M3 (MacBook Pro 14", ProMotion), 2026-11-06. **Match:** the last of 120
harness frames (1920x1200, dt = 1/30 s, seed `0x5EED`, date 2026-10-20T12:00:00Z) against the
Metal harness PNG of the same frame; differences in 0..255 levels per channel; distinct and
animated pixels are the harness's own gates (Metal's count in brackets where it differs).
**GPU ms:** web median from timestamp queries and Metal's Avg GPU Frame, measured back to back
per theme at 1920x1200. **Live:** `index.html` full screen in Chrome (3024x1786 device pixels,
below the notch), 240 frames at 120 Hz; a late frame took over 1.5x the median interval.

| Theme | Max diff | Pixels exact | Distinct | Animated | GPU web / Metal (ms) | Live GPU ms | Late frames |
|---|---|---|---|---|---|---|---|
| Tutorial_Tides | 1 | 99.9997% | 2,297,890 | 1,545,270 | 1.55 / 1.09 | 3.13 | 0/240 |
| Tutorial_Reef | 1 | 100% | 2,254,731 | 965,553 | 1.82 / 1.95 | 1.44 | 0/240 |
| Night_Tide | 3 | 99.9854% | 2,291,509 (2,291,508) | 268,083 (268,084) | 2.84 / 2.60 | 6.59 | 11/240 |
| Roulette_Chrome | 1 | 99.9988% | 2,277,228 | 262,092 | 1.73 / 2.02 | 6.69 | 12/240 |
| Ebru_Studio | 1 | 99.9942% | 2,298,489 | 1,279,707 (1,279,708) | 1.12 / 1.24 | 3.20 | 0/240 |
| Orion_Nebula | 1 | 99.9965% | 2,303,800 | 1,017,011 (1,017,002) | 2.24 / 2.21 | 5.64 | 0/240 |
| Lizard_Island | 3 | 99.9969% | 2,303,895 | 1,822,561 (1,822,562) | 3.37 / 3.11 | 7.87 | 49/240 |
| Aventurine_Horoscope | 2 | 99.9993% | 2,282,194 | 94,860 | 1.52 / 1.56 | 3.05 | 0/240 |
| Phosphor_Terminal | 1 | 99.9993% | 2,288,135 | 75,742 (75,741) | 1.60 / 1.24 | 3.61 | 0/240 |

Every theme passes the gates (no NaN/Inf, opaque, animated). Every pixel of every theme is
within 1 level except a handful in Night_Tide, Lizard_Island and Aventurine_Horoscope (at most
3 levels): rounding flips where WGSL's transcendentals differ by an ulp from Metal's fast-math
ones. At frame 2 Night_Tide has 7 isolated pixels up to 45 levels (reflected star points
behind finite-difference normals); they do not persist. Lizard_Island, Roulette_Chrome and
Night_Tide come close to the 8.33 ms budget of a 120 Hz frame at 5.4 million pixels and drop
some frames there; their simulations stay on the 30 Hz tick, so motion is unaffected.

## Browser notes

Tested here: Chrome 157 on macOS (Apple M3), headed and headless. The Safari and Firefox lines
come from the vendors' release notes, not from runs on this branch.

- **Chrome / Edge (113+) on macOS, Windows, ChromeOS; Android 121+:** supported. Chrome rounds
  timestamp queries to 100 µs unless `--enable-webgpu-developer-features` is set, so `gpuMs` is
  coarse in a normal profile. `bgra8unorm-storage` is present on Apple GPUs, so the draw writes
  the canvas in its preferred format.
- **Safari (26+ on macOS / iOS), untested here:** WebGPU is on by default. If `timestamp-query`
  is missing, `stats().gpuMs` is undefined and the page shows CPU-side ms only; without
  `bgra8unorm-storage` the canvas is configured as `rgba8unorm`.
- **Firefox, untested here:** WebGPU ships on Windows; on macOS it was behind a flag when this
  was written.
- Themes with `@argus state ... float32` that sample their state with a linear filter need the
  `float32-filterable` feature (Apple GPUs have it); without it the engine binds the state as
  unfilterable and such a theme fails to build with a clear error.
- The workgroup storage and invocation limits are requested at the adapter's maximum, so tiled
  themes can keep their Metal tile sizes where the GPU allows.

# Argus in the browser

`web/` runs Argus themes live in a browser. This part is the **WebGPU runtime for Metal themes**:
each `themes/<Name>.metal` has a one-to-one WGSL translation, hand-written in
`web/themes/<Name>.wgsl` or, without one, made automatically by `tools/msl2wgsl.zig` (below), run
by `web/host/argus_gpu.js` with the same frame semantics as the Mac app (`src/gpu/metal_theme.zig`).
No video stand-ins and no reduced versions: the kernels run in full at the canvas's device-pixel
size, on every display frame.

| Path | What it is |
|---|---|
| `web/index.html` | Dev page: theme picker, frame-ms readout (the real site comes later) |
| `web/prelude.wgsl` | The WGSL twin of `src/gpu/argus_prelude.metal` |
| `web/themes/*.wgsl` | Theme translations; `.bin` data files sit next to them (byte-identical copies of `themes/*.bin`) |
| `web/host/argus_gpu.js` | The engine: compile, directives, state, data, stats, present, timing |
| `web/host/frame.js` | `ArgusFrame`: the 4 h-wrapped f64 clock, the 30 Hz tick, the J2000 date fields |
| `web/host/stats.js` | `ArgusStats`: the harness's synthetic feed; `ArgusVitals`: what a browser page really knows about itself |
| `web/host/directives.js` | `// @argus` parsing, as `parseDirectives` in `metal_theme.zig` |
| `web/host/verify.html`, `web/host/tools/verify.mjs` | The Metal harness's check in the browser, and a driver that compares against the harness PNG (headless Chrome, or any browser with `--browser`) |
| `web/host/compile.html` | Builds every theme in this browser and checks a few frames for NaN (the portability check) |

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
// engine.stats()                 { gpuMs?, cpuMs?, wasmKB? } (this engine: gpuMs, drawMs, cpuMs; medians of the last 240 frames)
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
| `stats` | `'browser'` | For `@argus stats` themes: `'browser'` (only real readings, see below) or `'synthetic'` (the harness feed) |
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
  (init, steps and draw) and `stats().drawMs` that of `argus_draw` alone (the frame is encoded as
  two compute passes, each with its own pair of timestamps), read back asynchronously so it never
  stalls the frame.

### Stats in a browser

A web page can't read the machine's CPU load, memory size or use, disks, network traffic,
processes or thermal state, so a browser page gets none of them and nothing synthetic stands in
for them. With `stats: 'browser'` (the default), an `@argus stats` theme gets:

- `s` (`ArgusStats`) with only the fields that have a real source filled, every other field 0;
- `argus_vitals` (`ArgusVitals`, web only, binding 10) with `mode = 1`, the page's own vitals,
  and a `has` bit for each optional reading this browser offers. A reading without its bit is
  absent, not zero, and a theme must not show it as a reading. `mode = 0` (the verify page, the
  harness feed) means `s` is a machine's stats.

`engine.statsSources()` names the source of each reading, and `index.html` lists them. These are
all the readings a browser page gets; nothing else is real:

| Reading | Field | Source | Where it exists |
|---|---|---|---|
| Sample count, interval | `s.seq`, `s.sample_dt` | the page samples once a second | everywhere |
| Frame interval (mean, worst) | `frame_ms`, `frame_worst_ms` | `requestAnimationFrame` intervals of this page | everywhere |
| GPU time per frame, and `argus_draw`'s | `gpu_ms`, `draw_ms`; `s.gpu_busy` = `gpu_ms / frame_ms` | WebGPU timestamp queries around this page's two passes | with `timestamp-query` (Chrome, Safari 26 here) |
| JavaScript time per frame | `js_ms` | `performance.now()` around encoding and submitting the frame | everywhere (Safari's clock has 1 ms steps, so it reads 0 or 1 ms there) |
| Logical processors | `threads`, `s.cpu_count` (no per-core loads: `s.cpu_core` stays 0) | `navigator.hardwareConcurrency` | Chrome, Safari |
| Device memory | `device_mem_gb` | `navigator.deviceMemory`: rounded down to a power of two and capped (8 in Chrome), so the machine has *at least* that; Phosphor shows "8+ GB" | Chromium |
| JS heap used, allocated, limit | `heap_*_mb` | `performance.memory` (this page's heap, in coarse buckets) | Chromium |
| Battery | `s.battery_*`, `s.on_ac` | Battery Status API | Chromium |
| Network type, downlink, RTT, save-data | `net_*` | Network Information API: the browser's estimates, not this page's traffic | Chromium |
| CPU pressure | `pressure` | Compute Pressure API (a coarse state, not a load) | Chromium, where enabled |
| Canvas size, pixel ratio, GPU adapter | `canvas_w`, `canvas_h`, `dpr`, `adapter` | the canvas, `devicePixelRatio`, `GPUAdapterInfo` vendor and architecture | everywhere |
| Uptime | `s.uptime_s` | this tab's uptime (`performance.now()`), not the machine's | everywhere |
| Date and time | `f.days_j2000`, `f.day_frac`, `f.utc_offset_s` | the system clock and time zone | everywhere |

Phosphor_Terminal shows exactly these in a browser page as a browser-vitals screen on the same
tube: frame rate and frame time, GPU and draw ms, JS ms, the thread count as empty blocks ("per-thread
load is not visible to a web page"), device memory, the JS heap, battery, network estimates, CPU
pressure, the canvas, the GPU adapter, the tab's uptime and the date; a reading this browser lacks
says N/A. With the harness feed (the verify page) it shows the Mac screen, so it still compares
against the Metal PNG.

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
- **Portability:** no nested `const` arrays (`const T = array<array<f32, 15>, 13>(...)`).
  Chrome accepts them; Safari 26.6 rejects them ("cannot use override value in constant
  expression", pointing at the inner array's length). Flatten the table to one dimension and
  index it as `T[r * 15 + c]`. Run `tools/verify.mjs --browser Safari --page compile` after
  translating.
- Some identifiers are reserved in WGSL (`smooth`, `sample`, `filter`, `target`, `common`,
  `module`, `static`, ...): rename them.
- Keep the theme's header and its `// @argus` lines verbatim, so the directives and the honest
  account of what is measured and what is modelled carry over.

## Automatic translation (`tools/msl2wgsl.zig`)

A Metal theme needs no hand-written port: `tools/msl2wgsl.zig` translates it into the WGSL above.
The site's build (`site/build.sh`) translates every tracked `themes/*.metal` without a
`web/themes/<Name>.wgsl` into the published `web/themes/` (with its `@argus data` file) and lists
it in the home page's picker; the Bench workflow does the same for a pull request's theme and
links the translation; `make test` translates every tracked theme. A hand-written port, when there
is one, wins (the nine shipped themes keep theirs).

```sh
make wgsl THEME=themes/Night_Tide.metal                     # -> web/.auto/Night_Tide.wgsl (gitignored)
node web/host/tools/verify.mjs --theme ../.auto/Night_Tide.wgsl --ref /tmp/ref/Night_Tide.png --out /tmp/verify
zig run tools/msl2wgsl.zig -- --check themes/*.metal          # translate, report, write nothing
```

(`.bin` data files go next to the translation: `cp themes/X.bin web/.auto/`.)

It is a compiler, not a text rewrite: the theme is preprocessed (`#define`, also function-like),
parsed into a syntax tree of the C++ subset themes use, and every expression is typed, so each
rule in the table and the traps above is applied where it belongs:

- Metal's implicit conversions become explicit (`f32(i)`, `vec3f(x)`, `u32(n)` for a shift
  amount, `x != 0` for an int condition), with C++'s usual arithmetic conversions deciding the
  type; literals take the type they are used as (`2.0f`, `2u`).
- Overloads are resolved per call; templates and functions taking textures, samplers, lambdas
  or pointers are instantiated per distinct argument (two textures: two WGSL functions).
  Texture, sampler, `ArgusFrame` and `ArgusStats` parameters disappear: their uses name the
  prelude's bindings.
- `thread T&` is `ptr<function, T>` (a by-value parameter that is assigned gets a `var` copy;
  an argument that is not a whole variable is copied in and back); `thread char*` into a local
  array is the array's pointer plus an offset; `constant char` strings live in one constant pool
  (`M2W_STR`); `s.procs[i].name` is `argus_proc_char`.
- A lambda becomes a function; what it captures becomes parameters, pointers for what it
  writes. Passed to a template, it is threaded through the instance.
- `a ? b : c` is `select(c, b, a)` when both sides are cheap and free of side effects, else an
  `if`; `x++`, assignments and impure ternaries inside expressions become statements before the
  statement, in order (also inside `&&`, `||` and loop conditions); swizzle assignment is done
  per component; `switch` fall-through is unrolled; two-dimensional `constant` arrays are
  flattened (the Safari rule); `round`, `pow(x, 2)`, `fmod`, `isfinite`/`isnan`/`isinf`,
  `sincos`, `log10` keep Metal's meaning; `[[threads_per_threadgroup]]` is the declared
  `@workgroup_size` (16 x 16 for kernels with threadgroup memory, else 8 x 8).
- `half` is f32, as in the hand ports; an explicit conversion to a half type (`half2(v)`) still
  rounds to half precision (`quantizeToF16`), which Ebru_Studio relies on.

The output keeps the theme's header and its `// @argus` lines, and names the Metal line of every
function. A theme outside the subset is not translated: the tool exits 1 with
`themes/X.metal:line:col: error: <the construct>` and writes nothing, so no page runs a guess.
Not supported, each with its own message: SIMD-group functions and attributes (`simd_ballot`,
`[[thread_index_in_simdgroup]]`: WGSL subgroups are an extension the host does not enable),
textures other than `texture2d<float>`, mip levels, recursion, `#if` with an expression,
pointers that are reassigned, structs with member functions, lambdas capturing by name, a lambda
calling another lambda that captures.

### Measured (2026-11-14, Chrome 157 headless, Apple M3)

The harness's check (`verify.mjs`: frame 120 of 1920x1200, seed `0x5EED`, the pinned date)
against the Metal harness PNG of the same frame, levels 0..255 per channel. Distinct and animated
pixels are the harness gates; every row passes them (no NaN/Inf, opaque, animated).

**The nine shipped themes**, translated from `themes/*.metal` (their hand ports' max diff, from
the table below, in the last column):

| Theme | Max diff | Pixels exact | Within 2 | Distinct | Animated | Hand port |
|---|---|---|---|---|---|---|
| Tutorial_Tides | 1 | 99.9997% | 100% | 2,297,890 | 1,545,270 | 1 |
| Tutorial_Reef | 1 | 100% | 100% | 2,254,731 | 965,553 | 1 |
| Night_Tide | 3 | 99.9854% | 100% | 2,291,509 | 268,083 | 3 |
| Roulette_Chrome | 1 | 99.9988% | 100% | 2,277,228 | 262,092 | 1 |
| Ebru_Studio | 1 | 99.9942% | 100% | 2,298,489 | 1,279,707 | 1 |
| Orion_Nebula | 1 | 99.9938% | 100% | 2,303,800 | 1,017,014 | 1 |
| Lizard_Island | 1 | 99.9983% | 100% | 2,303,895 | 1,822,561 | 3 |
| Aventurine_Horoscope | 2 | 99.9993% | 100% | 2,282,194 | 94,860 | 2 |
| Phosphor_Terminal | 1 | 99.9993% | 100% | 2,288,135 | 75,742 | 1 |

**Held out:** nine Metal themes from the git history (earlier and retired themes) the translator
was not developed on, translated by the version that passed the nine above before their sources
were opened. Six translated and five of those match within 3 levels on the first try:

| Theme | First try | Max diff | Pixels exact | Within 4 |
|---|---|---|---|---|
| Test_PR_Tides | translated | 1 | 99.9997% | 100% |
| Opus_Ebru_Studio | translated | 1 | 99.9942% | 100% |
| Opus_Night_Tide | translated | 3 | 99.9854% | 100% |
| Opus_Orion_Nebula | translated | 1 | 99.9938% | 100% |
| Opus_Orion_Flight | translated | 1 | 99.9941% | 100% |
| Gemini_Wormhole | translated | 125 | 99.9694% | 99.9995% (all but 12 pixels) |
| Gemini_Aquarium | stopped (parse error in its `simd_ballot` helper) | now: `sincos` added; stops at `[[thread_index_in_simdgroup]]` | | |
| Coral_Reef, Opus_Coral_Reef | stopped (parse error in its `simd_ballot` helper) | now: stops at `[[thread_index_in_simdgroup]]` | | |

Gemini_Wormhole's 12 pixels are isolated fireflies in its lensing ring (one is pure white in the
Metal frame among neighbours both renders agree on): a geodesic integration and a hashed star
field there turn a last-bit difference into a whole pixel, as Lizard_Island's spots do in Safari.
Three of the held-out themes are earlier versions of shipped ones and Opus_Coral_Reef is
Coral_Reef under its first name, so the independent part is five: Gemini_Wormhole,
Gemini_Aquarium, Opus_Orion_Flight, Coral_Reef and Test_PR_Tides (a renamed tutorial).

GPU time is not claimed: back-to-back pairs on a busy machine put the translations within the
run-to-run noise of the hand ports (Tutorial_Reef 2.33 / 2.69 ms translated, 2.10 / 2.27 ms by
hand). Not yet checked in Safari.

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

Other browsers, without a driver: `--browser Safari` opens the same page with `open -a Safari`, and
the page POSTs its result back to the driver's server. `--page compile` builds every theme there
instead (`web/host/compile.html`); `--shot Phosphor_Terminal` also runs that theme live with the
browser's own stats and saves the frame. A Chromium-based browser can also run the default
headless path with `CHROME=<path to its binary>`.

```sh
node web/host/tools/verify.mjs --browser Safari --theme Night_Tide --ref /tmp/ref/Night_Tide.png --out /tmp/verify
node web/host/tools/verify.mjs --browser Safari --page compile --out /tmp/verify
```

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

### Re-checked in Chrome and Safari (2026-11-06, after the portability fix)

The same check, frame 120 against the Metal PNG, in Chrome 157 (headless) and Safari 26.6
(`--browser Safari`), on the same Apple M3. Chrome's results are identical to the table above.
Safari's are below. GPU ms come from one run each on a busy machine: Orion_Nebula measured
2.55 ms and 3.82 ms in two Safari runs.

| Theme | Chrome max diff | Safari max diff | Safari pixels exact | Safari pixels within 3 | Safari GPU ms |
|---|---|---|---|---|---|
| Tutorial_Tides | 1 | 1 | 99.9998% | all | 1.26 |
| Tutorial_Reef | 1 | 1 | 100% | all | 1.49 |
| Night_Tide | 3 | 3 | 99.9855% | all | 3.02 |
| Roulette_Chrome | 1 | 1 | 99.9992% | all | 1.84 |
| Ebru_Studio | 1 | 6 | 99.7558% | all but 10 | 1.40 |
| Orion_Nebula | 1 | 1 | 99.9945% | all | 3.82 |
| Lizard_Island | 3 | 91 | 99.9851% | all but 17 | 3.79 |
| Aventurine_Horoscope | 2 | 2 | 99.9993% | all | 1.79 |
| Phosphor_Terminal | 1 | 1 | 99.9993% | all | 1.33 |

Every theme passes the harness gates in Safari, with the same distinct and animated counts as in
Chrome (within 3 pixels; Ebru_Studio's animated count within 72 of 1.28 million).

The two outliers have different causes:
- **Lizard_Island:** 17 isolated pixels out of 2.3 million sit on the hard edges of the potato
  cod's spots (`du*du + ds*ds < r*r`). There, a last-bit difference in Safari's compiled maths
  flips a whole pixel. They differ from Chrome already at frame 2, so they come from the draw,
  not from the simulation.
- **Ebru_Studio:** at frame 2 it matches Chrome exactly; by frame 120 its paint simulation has
  drifted by up to 6 levels on 10 pixels.

Chrome's compiler happens to agree with Metal's bit for bit at those spots and Safari's doesn't.
Matching them would mean changing the theme itself, for example anti-aliasing the spots, which
would change the Metal look too.

## Browser notes

Tested here: Chrome 157 (headed and headless) and Safari 26.6 (through `--browser Safari`) on
macOS 26.6, Apple M3. Not tested: Chrome Canary, Firefox (neither is installed on this machine),
non-Apple GPUs. The Firefox line comes from Mozilla's release notes.

- **Chrome / Edge (113+) on macOS, Windows, ChromeOS; Android 121+:** supported. Chrome rounds
  timestamp queries to 100 µs unless `--enable-webgpu-developer-features` is set, so `gpuMs` is
  coarse in a normal profile. `bgra8unorm-storage` is present on Apple GPUs, so the draw writes
  the canvas in its preferred format.
- **Safari 26.6 on macOS, tested:** all 9 themes build and pass. It has `timestamp-query`,
  `bgra8unorm-storage` and `float32-filterable`. It rejects nested `const` arrays, which Chrome
  accepts (see the portability trap above). It has no `deviceMemory`, `performance.memory`, Battery,
  Network Information or Compute Pressure APIs, so Phosphor's browser screen shows N/A there.
  It pauses `requestAnimationFrame`, and slows timers to about 1 Hz, in a tab that isn't on
  screen.
- **Firefox, untested here:** WebGPU ships on Windows; on macOS it was behind a flag when this
  was written.
- Themes with `@argus state ... float32` that sample their state with a linear filter need the
  `float32-filterable` feature (Apple GPUs have it); without it the engine binds the state as
  unfilterable and such a theme fails to build with a clear error.
- The workgroup storage and invocation limits are requested at the adapter's maximum, so tiled
  themes can keep their Metal tile sizes where the GPU allows.

---
name: argus-metal-theme
description: Write Argus desktop wallpapers as Metal GPU kernels (themes/*.metal) - the native, fastest way to make an Argus theme. Covers the kernel contract, the built-in prelude, persistent GPU state for simulations, the GPU harness, and how to teach it. Use for any new Argus wallpaper, animation or simulation, or when someone wants to learn Metal shaders through Argus.
---

# Argus Metal Themes (`argus-metal-theme`)

An Argus theme can be **one `.metal` file**. Argus compiles it when it lands on a Space and
runs it on the GPU every frame, straight into the Space window's layer: no CPU pixel loop,
no image copies. A full 1920x1200 frame typically costs **0.5–2 ms of GPU time and ~0 CPU**,
where the same effect in a CPU theme costs 1–13 ms of a CPU core per frame.

Use this skill for every new theme. Reach for a Zig theme (`argus-theme` skill,
`themes/argus_theme_sdk.zig`) only when the work is small, sequential, branchy state that
the GPU can't help with (e.g. Echo's 120-neuron reservoir with online learning).

## 1. The contract

A theme is a Metal source file in `themes/`, named `<Author>_<Name>.metal`, with:

```cpp
kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;   // ALWAYS: the grid overhangs the edges
    const float2 uv = argus_uv(gid, f);                   // centred, y up, short side -1..1
    float3 col = 0.5f + 0.5f * cos(f.time + uv.xyx + float3(0, 2, 4));
    out.write(float4(saturate(col), 1.0f), gid);          // display values 0..1, alpha ignored
}
```

The GPU runs `argus_draw` once per pixel, all pixels in parallel. A kernel only answers
*"what colour is this one pixel?"*. It never loops over the screen.

**Rules**
- Bounds-check `gid` first in every kernel.
- Write display-encoded colour in 0..1 (what you'd put in a PNG). Lighting in linear light? Finish with `argus_srgb(...)`, plus `argus_aces(...)` for HDR.
- Time comes only from `f.time` / `f.dt` (seconds). There's no clock, randomness only via `argus_rand`/`argus_hash` + `f.seed`, and no I/O.
- Never produce NaN/Inf: guard `/`, `sqrt`, `log`, `pow` (negative bases), `normalize(0)`.
- Budget: the harness fails above **8.3 ms GPU per frame**. Aim for under 2 ms; the app runs at 30 FPS and shares the GPU with WindowServer.
- Don't write outside `out` (no device buffers yet) and don't assume a size: the harness also runs the theme at 320x200.

## 2. What Argus gives you (the prelude)

`src/gpu/argus_prelude.metal` is prepended to every theme (`metal_stdlib` and `using namespace metal` included):

| Name | What it is |
|---|---|
| `ArgusFrame f` | `time`, `dt` (s), `frame`, `width`, `height`, `state_width`, `state_height`, `seed` |
| `argus_uv(gid, f)` | pixel → centred coords, y up, short side spans -1..1 |
| `argus_uv01(gid, w, h)` | pixel → 0..1, y down (texture coordinates) |
| `argus_hash(uint)`, `argus_rand(uint2 cell, uint seed)` | integer hash, uniform 0..1 per cell |
| `argus_noise(float2)`, `argus_fbm(float2, octaves)` | smooth value noise (-1..1), fractal noise |
| `argus_palette(t, a, b, c, d)` | cosine palette `a + b·cos(2π(c·t + d))` |
| `argus_srgb(float3)`, `argus_aces(float3)` | linear → display, filmic tone map |

Compile errors report your own file's line numbers.

## 3. Themes that remember: GPU state

For simulations (reaction-diffusion, cellular automata, fluids, particles on a grid, trails),
add a **state texture** that persists between frames:

```cpp
// @argus state 960x600          <- state size (default: screen size). Add `float32` for full precision.
// @argus steps 8                <- argus_step runs this many times per frame (default 1, max 64)

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]], uint2 gid [[thread_position_in_grid]]);
kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read>  prev  [[texture(0)]],
                       texture2d<float, access::write> next  [[texture(1)]], uint2 gid [[thread_position_in_grid]]);
kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out   [[texture(0)]],
                       texture2d<float>                state [[texture(1)]], uint2 gid [[thread_position_in_grid]]);
```

- Each state texel is a `float4` (RGBA16F by default): pack up to 4 values per cell.
- **Ping-pong.** `argus_step` reads `prev` and writes `next`, then Argus swaps them. Never read and write the same texture: neighbours update simultaneously.
- `argus_init` runs once per load. Without one, the state starts at zero.
- Kernels over the state use `f.state_width/height` for bounds, not `f.width/height`.
- In `argus_draw`, sample the state with a linear sampler to upscale smoothly: `constexpr sampler s(filter::linear, address::repeat); state.sample(s, argus_uv01(gid, f.width, f.height))`.
- Wrap-around grids (torus) avoid edge artefacts. Anything that varies with position must then be periodic too (use `sin/cos(2π·uv)`), or you get a seam.
- A lower-resolution state (e.g. half the screen) is cheaper and usually looks better upscaled.

## 4. Workflow

1. **Start from a tutorial.** `themes/Tutorial_Tides.metal` is stateless: gradient → coordinates → domain warp → noise rays → palette, plus a reflected sea. `themes/Tutorial_Reef.metal` is stateful: Gray-Scott reaction-diffusion, init/step/draw and ping-pong. Copy one to `themes/<Author>_<Name>.metal`.
2. **Verify headlessly**:
   ```bash
   make harness THEME=themes/<Author>_<Name>.metal FRAMES=300 OUT=/tmp/<name>.png
   ```
   It compiles with the prelude and runs 300 frames at 1920x1200 plus a 320x200 watchdog run, then times 120 more as the app draws them (`Profile (BGRA8)`: init/step vs draw). It gates on: compile, NaN/Inf (in a float32 render), pixel variance > 100, ≥ 2,000 animated pixels between first and last frame, and average GPU time < 8.3 ms. It writes the last frame as a PNG. **Open the PNG and look at it**: passing gates don't mean it looks good. Render later frames (`FRAMES=900`) for simulations that take time to develop.
3. **Run it live.** Drag the `.metal` file onto a Space in the Argus menu-bar panel (or choose it with the file picker). Save edits and Argus hot-reloads within a second. If the new code doesn't compile, the old version keeps running and the error is printed on Argus's stderr (`./Argus.app/Contents/MacOS/Argus --perf-log` in a terminal shows it).
4. `make test` must stay green when engine code changes.

## 5. Performance: what the GPU actually does (measured)

Measured on an M3 at 1920x1200 with `make gpu-probes` (`tools/gpu_probes/`: tiny kernels that
each isolate one cost) and by taking the four ported themes apart. Rerun the probes on
another chip before trusting exact numbers; the ratios are what matter. How the hardware
works underneath (SIMD groups, Dynamic Caching, clocks, compression, TBDR, pacing) is in
[apple_gpu.md](apple_gpu.md).

**Judge budgets on the paced number.** At Argus's 30 FPS the GPU stays at a low clock, so
a frame costs 1.4–2.3x what it costs back-to-back. The harness prints both: `Profile
(BGRA8)` (back-to-back, good for A/B comparisons) and `Paced 30 FPS` (the live cost). For
A/B tests, warm the GPU first (the harness does): the first measurements on a cold GPU
run slow and fake big differences.

**Read the harness profile first.** The report's `Profile (BGRA8)` line times frames the way
the app draws them (into the BGRA8 drawable) and splits each into `init/step` and `draw`. To
find where a draw's time goes, switch parts off one at a time and compare. Two traps:
- The compiler deletes code whose result is unused. If you skip a stage with `continue`,
  still feed its result into the output (e.g. `col.x += z * 1e-9f`), or you'll measure nothing.
- Dead code is free: corals left in the kernel but never executed cost 0.02 ms. Only
  what runs costs, so kernel size is not a reason to split a theme.

**How the hardware runs your kernel.** Argus dispatches 32x32 threadgroups. The GPU executes
them in **SIMD groups of 32 threads = 32 neighbouring pixels of one row**, which run in lock-step.

| Measured back-to-back (one op per pixel, full screen) | Cost |
|---|---|
| writing the frame (BGRA8) | ~0.1–0.2 ms floor |
| `fma` | ~3.5 µs |
| `exp` | ~3 µs |
| `sqrt` + divide, `pow` | ~8 µs |
| `sin` (= `fast::sin`, Metal's default) | ~15 µs; `precise::sin` ~37 µs |
| integer `/` and `%` by a power of two | free (shift, mask) |
| integer `/` and `%` by a constant like 2049 | ~15 µs |
| integer `/` and `%` by a runtime value | ~58 µs |
| `half` instead of `float` maths | same speed (no ALU gain on M3) |

**Rules that follow, biggest first:**
1. **Neighbouring pixels must read neighbouring texels.** 32 coherent texture reads per
   pixel cost 0.45 ms; the same 32 reads at random addresses in an 8 MB texture cost
   **33 ms (74x)**. `sample` is ~1.5x a `read`. All 32 lanes reading the *same* texel (a
   shared table row) is the cheapest read there is.
2. **Branch per row or per tile, not per pixel.** A branch that differs between
   neighbouring pixels runs both sides (2.0x). The same branch differing per row or per
   32x32 tile costs nothing. Loops: a per-pixel random trip count costs like the max of the
   32 lanes (2.1x the mean); a count that varies smoothly across the screen costs 1.26x.
3. **Make per-tile lists 32 px wide (or a multiple).** Then a SIMD group never straddles two
   tiles and walks one list. Coral Reef's 30 px tiles → 32 px: −0.2 ms.
4. **Cull cooperatively.** Instead of every pixel testing every candidate, let the lanes of a
   SIMD group split the candidates, test them against the group's pixel span
   (`simd_min/simd_max` of the pixel coords), combine with `simd_ballot`/`simd_or`, and visit
   only the hits (`ctz` over the mask, `simd_shuffle` to broadcast data). Don't assume all 32
   lanes are active (earlier `continue`s, right screen edge): split work by rank among
   `simd_ballot(true)` and fall back when lanes aren't on the same item
   (`simd_all(id == simd_broadcast_first(id))`). Examples: `Gemini_Aquarium.metal` (whole
   draw 9.9 → 1.7 ms), `Opus_Coral_Reef.metal` corals. For bigger lists, cull per threadgroup
   into `threadgroup` arrays with an atomic append and a `threadgroup_barrier` (no early
   `return` before the barrier): `Lizard_Island.metal`.
5. **Use power-of-two strides for packed tables** (`uint2(n & 2047, row + (n >> 11))`, not
   `n % 2049`): −0.1 ms on Coral Reef.
6. **Local arrays indexed at run time can end up in memory.** A 96-element array indexed by
   a computed value: 200 ms vs 6 ms for 32 elements. Small arrays often stay in registers
   (Coral Reef's `ids[16]` made no difference): measure before rewriting.
7. **Copy baked state once.** A full-grid `argus_step` that returns at once costs ~0.05 ms
   at 2048x2048, but copying 2048x2048 RGBA16F costs ~0.77 ms per frame. Bake in `argus_init`
   and copy into the other ping-pong texture only on the first frames (`if (f.frame < 3u)`).

**Things that did not help** (so don't spend time on them): cheaper arithmetic inside a loop
that isn't arithmetic-bound; batching texture reads by hand (the compiler already overlaps
them); `[[max_total_threads_per_threadgroup(N)]]` or other threadgroup shapes; `half` for speed.

Raymarching, fractals and fbm with 4–6 octaves all fit the budget at 1920x1200. For
simulations, shrink the state (`@argus state`) before you cut steps.

## 6. Teaching it

When someone wants to *learn*, build up in small runnable steps, each one a harness run plus a PNG they can see:
1. a flat colour, then a gradient from `argus_uv01`;
2. shapes from distance (`length(uv) < r`, `smoothstep` for soft edges);
3. motion with `f.time`;
4. texture with `argus_noise` / `argus_fbm`, then domain warping (noise feeding noise);
5. colour with `argus_palette`;
6. memory: a state texture with init/step/draw (Game of Life → reaction-diffusion).

Explain the one mental shift up front: you write the rule for one pixel, and the GPU applies it to all 2.3 million pixels at once.

## 7. Where things live

| File | Role |
|---|---|
| `src/gpu/argus_prelude.metal` | the prelude (helpers, `ArgusFrame`) |
| `src/gpu/metal_theme.zig` | compiles themes, directives, state ping-pong, encodes frames |
| `src/gpu/presenter.zig` | CAMetalLayer per Space window; Zig + Metal hybrids (Opus_Quasar) |
| `src/theme_harness.zig` | `make harness`; `.metal` files take the GPU path |
| `themes/Tutorial_*.metal` | the two tutorials |
| `tools/gpu_probes/` | `make gpu-probes`: one-cost-each probe kernels behind section 5 |
| `src/gpu_arch_probe.zig` | `make gpu-arch`: engine-level probes (clocks, write path, threadgroups, CPU, memory) |
| `apple_gpu.md` | the Apple GPU as Argus drives it: measured + sourced |

Zig + Metal hybrids (a Zig theme whose per-pixel draw runs as a Metal kernel over its
CPU-built tables) exist as a prototype for `Opus_Quasar` only (`src/gpu/bh_*.zig`,
`make gpu-bench`). They aren't a general SDK feature yet.

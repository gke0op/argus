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
   It compiles with the prelude and runs 300 frames at 1920x1200 plus a 320x200 watchdog run. It gates on: compile, NaN/Inf (in a float32 render), pixel variance > 100, ≥ 2,000 animated pixels between first and last frame, and average GPU time < 8.3 ms. It writes the last frame as a PNG. **Open the PNG and look at it**: passing gates don't mean it looks good. Render later frames (`FRAMES=900`) for simulations that take time to develop.
3. **Run it live.** Drag the `.metal` file onto a Space in the Argus menu-bar panel (or choose it with the file picker). Save edits and Argus hot-reloads within a second. If the new code doesn't compile, the old version keeps running and the error is printed on Argus's stderr (`./Argus.app/Contents/MacOS/Argus --perf-log` in a terminal shows it).
4. `make test` must stay green when engine code changes.

## 5. Performance habits on the GPU

- Per-pixel `sin`, `exp`, `pow` are cheap on the GPU (unlike the CPU). Loops are fine when every pixel runs a similar count. Big per-pixel branches that differ between neighbours cost more.
- Raymarching, fractals and fbm with 4–6 octaves all fit in the budget at 1920x1200. Check `Avg GPU Frame` in the harness report.
- Prefer `half` for colour maths only if profiling says so. `float` is the safe default.
- Simulations: shrink the state (`@argus state`) before you cut steps.

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
| `src/gpu/presenter.zig` | CAMetalLayer per Space window; Zig + Metal hybrids (Opus_Black_Hole) |
| `src/theme_harness.zig` | `make harness`; `.metal` files take the GPU path |
| `themes/Tutorial_*.metal` | the two tutorials |

Zig + Metal hybrids (a Zig theme whose per-pixel draw runs as a Metal kernel over its
CPU-built tables) exist as a prototype for `Opus_Black_Hole` only (`src/gpu/bh_*.zig`,
`make gpu-bench`). They aren't a general SDK feature yet.

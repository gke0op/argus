---
name: argus-metal-theme
description: Write Argus desktop wallpapers as Metal GPU kernels (themes/*.metal) - the native, fastest way to make an Argus theme. Covers the quality bar and render-critique loop that separate a shippable theme from a passable one, the kernel contract, the prelude, persistent GPU state for simulations, the harness and contact sheet, claim checks, performance, and teaching. Use for any new Argus wallpaper, animation or simulation, or when someone wants to learn Metal shaders through Argus.
---

# Argus Metal Themes (`argus-metal-theme`)

An Argus theme can be **one `.metal` file**. Argus compiles it when it lands on a Space and
runs it on the GPU every frame, straight into the Space window's layer. A full 1920x1200
frame typically costs **0.5–3 ms of GPU time and ~0 CPU**. Reach for a Zig theme
(`argus-theme` skill) only for small, sequential, branchy state the GPU can't help with
(e.g. a 120-neuron reservoir with online learning).

## 0. The bar, and when you are done

**The harness proves a theme runs. It does not prove the theme is good.** Six agent-made
themes passed every gate in October 2026, and the owner called them "at best sub par". Before
writing code, read [`../THEME_CRAFT.md`](../THEME_CRAFT.md). It covers what the shipped
themes have in common, the 10-step workflow (brief → research → look targets → art direction
→ smallest version → render loop → claim checks → owner → independent review → header), the
A1–A10 critique checklist, what went wrong in the factory batch, and worked examples from
Night Tide, Orion Nebula, Cygnus A and Ebru Studio.

A theme is **done** when every one of these is true:

- [ ] **Subject and research.** A specific subject, a notes file with *how it looks* and *why*,
      sources tagged `[cited]`/`[snippet]`/`[data]`.
- [ ] **Look targets.** 5–10 checkable statements, each verified on the final sheet.
- [ ] **Contact sheet.** `tools/theme_sheet.sh` was run and every image opened: four moments
      (0.1 s to 90 s), three or more seeds, the 1:1 crop. No moment or seed is broken.
- [ ] **Critique.** A written A1–A10 critique of the final sheet, with nothing left you would
      point at as wrong.
- [ ] **Motion.** Rates designed in human time (§4); flicker measured, and you know what causes
      it; still alive at 90 s, and at an hour for simulations (§5, burn-in).
- [ ] **Claims.** Every number in the header is cited or checked (§5, claim checks); every thing
      the header names is visible; known defects are fixed, not just disclosed.
- [ ] **Review.** An independent reviewer (fresh agent or the owner) saw the sheet and the
      header, and its findings are resolved. If the owner hasn't seen it, the hand-off says so.
- [ ] **Header and cost.** Honest header (template in THEME_CRAFT.md); harness PASS, with paced
      cost from a quiet machine, or as a ratio to a control theme measured alongside (§6).
- [ ] **Field notes.** An entry in [`../FIELD_NOTES.md`](../FIELD_NOTES.md).

## 1. The contract

A theme is a Metal source file in `themes/`, named `<Name>.metal` (the subject, not the model),
with:

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

The GPU runs `argus_draw` once per pixel, all pixels in parallel. You write the rule for one
pixel; it never loops over the screen.

**Rules**
- Bounds-check `gid` first in every kernel.
- **Colour space: pick one and stay in it.** `out` takes display-encoded values (what you'd put
  in a PNG). If you light in linear light and end with `argus_srgb(...)` (plus `argus_aces(...)`
  for HDR), then **every constant in the kernel is linear**: a display-space 0.3 typed into it
  comes out as 0.58. Gamma-encoding a display-space ramp a second time gives a white frame.
- Time comes only from `f.time` / `f.dt` (seconds). There's no clock, randomness comes only from
  `argus_rand`/`argus_hash` with `f.seed`, and there's no I/O.
- **`f.time` wraps to 0 every `ARGUS_TIME_PERIOD` (14,400 s = 4 h)**, so it stays precise to
  ~1 ms on a Space that runs for weeks (Argus keeps the real clock in f64). Make long cycles
  divide the period: any whole number of minutes that divides 240 (1–6, 8, 10, 12, 15, 16, 20,
  30, 60 …) runs on seamlessly; Orion's 8- and 16-minute orbit does. Anything else jumps once
  every 4 hours. Simulations in a state texture don't care.
- Never produce NaN/Inf: guard `/`, `sqrt`, `log`, `pow` (negative bases), `normalize(0)`.
- Budget: the harness fails above **8.3 ms GPU per frame**. Aim for ≤ 3 ms back-to-back and
  ≤ 5 ms paced; the app runs at 30 FPS and shares the GPU with WindowServer.
- Don't write outside `out`, and don't assume a size: the harness also runs at 320x200.

## 2. The prelude

`src/gpu/argus_prelude.metal` is prepended to every theme (`metal_stdlib` and
`using namespace metal` included). Compile errors report your own file's line numbers.

| Name | What it is |
|---|---|
| `ArgusFrame f` | `time` (s, wraps every 4 h), `dt` (s), `frame`, `width`, `height`, `state_width`, `state_height`, `seed` |
| `ARGUS_TIME_PERIOD` | 14400.0f: where `f.time` wraps; fit long cycles to it |
| `float2 argus_uv(uint2 gid, constant ArgusFrame& f)` | pixel → centred coords, y up, short side spans -1..1 |
| `float2 argus_uv01(uint2 gid, uint w, uint h)` | pixel → 0..1, y down (texture coordinates) |
| `uint argus_hash(uint x)` | integer hash (lowbias32); chain it for several inputs, `argus_hash(a ^ argus_hash(b))` |
| `float argus_rand(uint2 cell, uint seed)` | uniform 0..1 per integer cell and seed: placement, sizes, per-object variation |
| `float argus_noise(float2 p)` | smooth value noise, about -1..1, one feature per unit of `p` |
| `float argus_fbm(float2 p, int octaves)` | fractal `argus_noise`, each octave twice as fine and half as strong |
| `float3 argus_palette(t, a, b, c, d)` | cosine palette `a + b·cos(2π(c·t + d))`: fine for sketches, but take shipped colours from the subject |
| `float3 argus_srgb(float3 lin)` | linear → display (clamps to 0..1 first) |
| `float3 argus_aces(float3 x)` | filmic tone map for HDR linear values; follow with `argus_srgb` |

**Seeds.** The app gives each Space its own `f.seed` (from the Space and the theme path); the
harness pins `0x5EED` unless you pass `SEED=`. `argus_noise` and `argus_fbm` **ignore the
seed** (they hash with seed 0), so their pattern is identical on every Space. To vary them,
offset the input: `p + 100.0f * float2(argus_rand(uint2(1, 2), f.seed), argus_rand(uint2(3, 4), f.seed))`.
If anything in your composition is seeded, check several seeds (§5).

## 3. Themes that remember: GPU state

For simulations (reaction-diffusion, cellular automata, fluids, lattice Boltzmann, trails), add
a **state texture** that persists between frames:

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

- **A texel is 4 channels, always.** RGBA16F by default; `float32` makes it RGBA32F, which gives
  more precision but not more channels. With more than 4 values per cell, pack several texels
  per cell; read §6 rule 1 before choosing the layout.
- **float16 drops small increments.** Half-float's ulp near 1.0 is ≈ 1e-3. A per-step increment
  below that at your working magnitude (2e-5 of condensation, say) rounds to zero, so slow
  accumulations stall silently, with no NaN and no failing gate. Use `float32` then.
  Memory: 960x600 float32 is 9.2 MB, doubled by the ping-pong.
- **Ping-pong.** `argus_step` reads `prev` and writes `next`, then Argus swaps them. Never read
  and write the same texture.
- **Static content: bake it once.** A theme with `argus_init` and no `argus_step` runs init once
  and then only draws, so an expensive static backdrop (a skyline, a terrain, a star field)
  costs nothing per frame (Orion does this). Add `@argus state WxH` to size the bake.
- `argus_init` runs once per load; without it the state starts at zero. Kernels over the state
  bound by `f.state_width/height`, not `f.width/height`.
- In `argus_draw`, sample with a linear sampler to upscale smoothly:
  `constexpr sampler s(filter::linear, address::repeat); state.sample(s, argus_uv01(gid, f.width, f.height))`.
- Wrap-around grids avoid edge artefacts, but then anything that varies with position must be
  periodic too, or you get a seam. Night Tide does this for an endless beach: noise on a lattice
  that wraps, and sines with whole cycles per map width.
- A lower-resolution state (half the screen) is cheaper and usually looks better upscaled.
- **Start a simulation where it would be after developing**, if reaching that takes longer than
  a viewer waits, and say so in the header. Seed the state you'd actually see: a developed
  convection profile has a step at *each* plate, not one in the middle.
- **Shipping data.** A theme can't read files, and its source is capped at 128 KB. For measured
  data, put a raw texel file next to the theme and declare it:
  `// @argus data Name.bin 512x512 rgba8` (or `rgba16f`): W x H texels, row-major, no header.
  `argus_init` gets it as a third argument, `texture2d<float, access::read> data [[texture(1)]]`.
  A missing or wrong-sized file fails the load. Example: `themes/Orion_Nebula.metal` (built by
  `tools/orion_bake/bake.py`, checked by `verify_earth_view.py`).

## 4. Design rates in human time

A wallpaper is watched for minutes and runs for days. Decide every rate in seconds first
("a drop takes 1–2 min from visible to running; a streak crosses the pane in ~20 s; a wave
reaches the shore in ~12 s"), then convert: steps per second = 30 × `steps`, so a per-step
constant is the per-second rate divided by that. A factory rain-on-glass theme's first rates
were 60–100× too fast: the pane beaded into a web within 4 s, and every gate passed. To catch it, compare
frames 150 and 2700 on the sheet. If 5 s already shows the end state, everything is too fast.
Say in the header what is time-lapsed and by how much (Cygnus A: one inner orbit in ~3 s on
screen, ~4 days in reality).

## 5. The harness, the render loop, claim checks

```bash
make harness THEME=themes/<Name>.metal FRAMES=300 OUT=/tmp/<name>.png [SEED=7]
tools/theme_sheet.sh themes/<Name>.metal          # the contact sheet: run it every round
```

- **The harness** compiles with the prelude, runs `FRAMES` frames at 1920x1200 plus a 320x200
  watchdog, then times 120 more as the app draws them. It gates on compile, NaN/Inf, pixel
  variance > 100, ≥ 2,000 animated pixels between the first and last frame, and average GPU
  time < 8.3 ms. It writes the last frame as a PNG.
- **The sheet** renders four moments (`MOMENTS`, default frames 2/150/900/2700), three seeds
  (`SEEDS`), a 1:1 crop (`CROP=WxH+X+Y`, default the centre; aim it at the detail you are
  judging), and a flicker count, then tiles them into `sheet.png`. Open all of it each round
  and critique against THEME_CRAFT.md. **Flicker** counts pixels jumping >16% between two
  consecutive frames. That includes legitimate motion (a bright car moving a few pixels), so
  know what yours is made of: crop or mask by band before calling it shimmer. One reef theme's
  shimmer fix took seabed flicker from 1.60% to 0.64%.
- **In a git worktree** there's no `./.toolchain/zig`, and the `zig` on PATH may be the wrong
  version (`std.process has no member Init` means it isn't 0.17). Pass
  `ZIG=<main checkout>/.toolchain/zig`, or export it, for both `make` and the sheet.
- **Burn-in.** For a simulation that takes a long time to develop, copy the theme to a temp
  file, raise `// @argus steps` (up to 64) and lower `FRAMES`: you get the same number of steps
  in ~30× less wall clock. To check the hour mark at `steps 1`: 108,000 steps ≈ `steps 64` ×
  `FRAMES=1700`. Only the state advances this way; `f.time` still counts frames.
- **Look at layers alone.** Copy the theme and `sed` a layer off (for example
  `s/const float h0 = s0.r;/const float h0 = 0.0f;/` to drop the glass), or zero one constant,
  to see what's underneath. One author's background city went from invisible to designed in
  two renders this way.
- **Claim checks.** Put physics checks in `themes/<Name>_claims.zig`, a `zig test` file that
  imports `argus_theme_sdk.zig` and records each check with `sdk.ledger(.{ .id, .claim,
  .reference, .conditions, .quantity, .measured, .lo, .hi, .source })` (`themes/Cygnus_A.zig`
  shows the pattern). A verify script works too, if it recomputes the header's numbers or
  measures a render (`tools/orion_bake/verify_earth_view.py`, or one kept beside your notes
  when the repo is off limits). A value plan is checkable as well: "the sand is the darkest
  thing" is a median over a mask. Re-derive the reference independently, then audit your *own
  discretisation* against it: lattice weights, boundary rules, units. A lattice Boltzmann
  convection theme's check found its D2Q5 weights gave Pr = 2 where the header said 1. Nothing in the harness would
  have noticed.
- **Run it live.** Drag the `.metal` file onto a Space in the Argus menu-bar panel. Saved edits
  hot-reload within a second. A compile error keeps the old version running and prints to
  stderr (`./Argus.app/Contents/MacOS/Argus --perf-log`).
- `make test` must stay green when engine code changes.

## 6. Performance: what the GPU actually does (measured)

Measured on an M3 at 1920x1200 with `make gpu-probes` (`tools/gpu_probes/`) and by taking
themes apart. The ratios matter more than the exact numbers. The hardware underneath is in
[apple_gpu.md](apple_gpu.md).

**Trust timings only from a quiet machine.** At 30 FPS the GPU stays at a low clock, so a frame
costs 1.4–2.3x its back-to-back time: judge budgets on `Paced 30 FPS`, and use `Profile (BGRA8)`
(back-to-back, split into `init/step` and `draw`) for A/B tests. The harness warms the GPU, but
it can't quiet it. **The live app with several Spaces, another agent's harness, or a build in a
sibling worktree makes A/B timings fiction**: the same unmodified build measured 1.6 → 4.4 ms
and 3.7 → 10.8 ms paced. Stop them first. If you can't (a sub-agent can't stop the owner's app),
run a control theme (`Night_Tide.metal`) in the same window and report your cost as a ratio to
it, together with the control's quiet-machine number (~2.9 ms back-to-back).

**Bisecting a draw.** Switch parts off one at a time and compare. The compiler deletes code
whose result is unused, so feed a skipped stage into the output (`col.x += z * 1e-9f`). Dead code
is free: only what runs costs. If removing work makes the frame *slower*, the machine is noisy
(above). It isn't your code.

**How the hardware runs your kernel.** Argus dispatches 32x32 threadgroups, executed as **SIMD
groups of 32 neighbouring pixels of one row** in lock-step.

| Measured back-to-back (one op per pixel, full screen) | Cost |
|---|---|
| writing the frame (BGRA8) | ~0.1–0.2 ms floor |
| `fma` / `exp` | ~3.5 µs / ~3 µs |
| `sqrt` + divide, `pow` | ~8 µs |
| `sin` (= `fast::sin`, Metal's default) | ~15 µs; `precise::sin` ~37 µs |
| integer `/` `%` by a power of two / a constant like 2049 / a runtime value | free / ~15 µs / ~58 µs |
| `half` instead of `float` maths | same speed (no ALU gain on M3) |
| a whole state step: 960x600 float32, ~11 neighbour reads + 3 noises, 3 steps | 0.66–0.81 ms |

**Rules, biggest first:**
1. **Neighbouring pixels must read neighbouring texels, at stride 1.** 32 coherent reads per pixel
   cost 0.45 ms; the same reads at random addresses in an 8 MB texture cost **33 ms (74x)**.
   *Strided* is the third case, and the default as soon as you pack several texels per cell:
   anything `argus_draw` samples must sit at stride 1 in its own region, or the cache line and
   the sampler waste most of each fetch. A lattice Boltzmann draw went 6967 → 713 µs by moving its
   four drawn fields into a leading stride-1 strip (`TW = 5*NX`, fields at `0..NX`, populations
   at `NX + 4i + s`, sampled at `u = x * NX / TW` with `clamp_to_edge`), which also made the
   bilinear and the wrap free. `sample` costs ~1.5x a `read`; all 32 lanes reading the *same*
   texel is the cheapest read there is.
2. **Branch per row or per tile, not per pixel.** A branch that differs between neighbours runs
   both sides (2.0x); the same branch differing per row or per 32x32 tile is free. A per-pixel
   random loop count costs the max of 32 lanes (2.1x the mean); a smoothly varying one, 1.26x.
3. **Make per-tile lists 32 px wide** (or a multiple), so a SIMD group never straddles two tiles.
   On a reef theme, 30 px → 32 px tiles saved 0.2 ms.
4. **Cull cooperatively.** Let the lanes of a SIMD group split the candidates, test them against
   the group's pixel span (`simd_min/simd_max`), combine with `simd_ballot`/`simd_or`, and visit
   only the hits (`ctz`, `simd_shuffle`). Don't assume all 32 lanes are active. This took an
   aquarium theme's whole draw from 9.9 to 1.7 ms. For bigger lists, cull per threadgroup into
   `threadgroup` arrays with an atomic append and a `threadgroup_barrier` (no early `return`
   before it): `themes/Orion_Nebula.metal` does this for its stars.
5. **Power-of-two strides for packed tables** (`uint2(n & 2047, row + (n >> 11))`, not `n % 2049`).
6. **Local arrays indexed at run time can spill to memory** (96 elements: 200 ms against 6 ms for
   32). Small ones usually stay in registers. Measure before rewriting.
7. **Copy baked state once.** Bake in `argus_init` and copy into the other ping-pong texture only
   on the first frames (`if (f.frame < 3u)`); copying 2048x2048 RGBA16F every frame costs ~0.77 ms.

**Optimise without changing the picture.** No upscaling, reprojection or jittered approximations
the eye can catch. Prove an optimisation by diffing renders at several moments before and
after: Night Tide's 4.9 → 2.9 ms pass changed the image by a mean of 0.1–0.16/255.

**Things that did not help:** cheaper arithmetic in a loop that isn't arithmetic-bound; batching
texture reads by hand; `[[max_total_threads_per_threadgroup(N)]]` or other threadgroup shapes;
`half` for speed. Raymarching, fractals and 4–6-octave fbm all fit the budget. For simulations,
shrink the state before you cut steps.

## 7. Teaching it

When someone wants to *learn*, build up in small runnable steps, each one a harness run plus a
PNG they can see: a flat colour, then a gradient from `argus_uv01`; shapes from distance
(`smoothstep` for soft edges); motion with `f.time`; `argus_noise`/`argus_fbm`, then domain
warping; colour; memory (a state texture: Game of Life → reaction-diffusion). Explain the one
mental shift up front: you write the rule for one pixel, and the GPU applies it to all 2.3
million at once. Then put a reference photo next to their render. That habit is worth teaching
too.

## 8. Where things live

| File | Role |
|---|---|
| `../THEME_CRAFT.md` | the quality bar, workflow, critique checklist, worked examples, header template |
| `src/gpu/argus_prelude.metal` | the prelude (helpers, `ArgusFrame`) |
| `src/gpu/metal_theme.zig` | compiles themes, directives, state ping-pong, encodes frames |
| `src/gpu/presenter.zig` | CAMetalLayer per Space window; Zig + Metal hybrids (Cygnus A) |
| `src/theme_harness.zig` | `make harness` (`SEED=` for Metal); `.metal` files take the GPU path |
| `tools/theme_sheet.sh` | the contact sheet: moments, seeds, 1:1 crop, flicker |
| `themes/argus_theme_sdk.zig` | `sdk.ledger` for claim checks (Zig themes and `<Name>_claims.zig` tests) |
| `themes/Tutorial_*.metal` | Tides (stateless) and Reef (stateful): skeletons to copy, not a quality bar |
| `tools/gpu_probes/`, `src/gpu_arch_probe.zig` | `make gpu-probes`, `make gpu-arch`: the measurements behind §6 |
| `apple_gpu.md` | the Apple GPU as Argus drives it: measured and sourced |

Zig + Metal hybrids (a Zig theme whose per-pixel draw runs as a Metal kernel over its CPU-built
tables) exist as a prototype for the Kerr-disk themes only (`src/gpu/bh_*.zig`,
`make gpu-bench`). They aren't a general SDK feature yet.

## When you are done: leave field notes

Append an entry to [`../FIELD_NOTES.md`](../FIELD_NOTES.md): what helped, what was wrong or
missing, what cost you time. Report how it *looks* (your critique, the owner's verdict), not only
the harness numbers.

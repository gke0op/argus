ARGUS-BENCH, agentic mode. Track B (PDE field dynamics): a live Gray–Scott reaction–diffusion simulation. The theme passed on its first harness run and finished in the Gold tier (about 1.6 ms a frame).

**Final theme file:** `<clone>/themes/Opus55_Field.zig` (untracked, not committed)

**Final scorecard** (`make harness THEME=themes/Opus55_Field.zig FRAMES=120`):
```
Avg Frame Time    : 1632.0 us (612.7 FPS)   [same build, other runs: 1592–1726 us]
Worst Frame Time  : ~2100–2400 us
Allocs at Init    : 1 (6014672 bytes)
Allocs after Init : 0
Watchdog 320x200  : PASS
Stride Guard      : CLEAN (0 out-of-bounds canary writes)
NaN / Inf Check   : CLEAN
Pixel Variance    : 2303797 / 2304000 (alpha=0 count: 0)
Temporal Motion   : 2010346 / 2304000 (min 2000)
Verdict           : PASS
```
Tier: Gold (under 2,000 µs), on this shared Mac under `nice -n 10`.

**Harness runs to first PASS:**
- **Run 1:** the unchanged §3 skeleton, saved as `themes/Opus55_Field.zig`. It passed (1498.5 µs), so the toolchain works.
- **Run 2:** the first Gray–Scott version. It passed (2300 µs, Silver). Two cast errors were fixed before that run; neither took a harness run.
- **About 18 runs in total.** The rest were tuning the look, long runs, timing experiments and a final check. Two of them stopped at compile errors during the speed work: a runtime index into a vector, and a variable name shadowed in an outer scope.

**PNG:** `/tmp/Opus55r3_GrayScott.png` (final frame, 120 frames). Other runs share `/tmp` and also write files named `/tmp/Opus55_*`, so I gave the final frame a unique name.

**What it simulates:**
- **Equations:** du/dt = Du∇²u − uv² + F(1−u) and dv/dt = Dv∇²v + uv² − (F+k)v, with Du=0.2097 and Dv=0.105.
- **Method:** explicit Euler with a 5-point Laplacian on a periodic grid of 481×301 cells, one cell per 4×4 pixels, about 900 iterations per simulated second.
- **Parameter map:**
  - F varies smoothly between 0.024 and 0.050.
  - k is set a controlled distance either side of the line k = √F/2 − F, which is where Gray–Scott patterns form.
  - The map repeats seamlessly across the screen edges, so the wrap-around shows no seam.
  - k drifts very slowly (about a 4-minute cycle).
  - On screen you get labyrinths, hexagonal hole lattices, dividing spots and slowly moving target-wave patches.
- **Warm-up:** 3,000 iterations run in `init()`, so the first frame already shows a grown pattern.
- **Look:** the v field is drawn as a glossy raised surface lit from the upper left (navy ground, teal, ivory-gold ridges) with a soft vignette.

**Speed:**
- **Simulation:** 8-wide SIMD, about 0.45 ms a frame.
- **Shading:** once per cell in `step()`, also 8-wide, which cut it from about 0.9 ms to about 0.25 ms.
- **Drawing:** a bilinear upsample in two passes that writes 32 pixels at a time, about 0.9 ms. There is no trigonometry or exponential per pixel.

**Checks and caveats:**
- **Steady-state motion:** to check motion after warm-up settles, I ran a temporary copy with 40,000 warm-up iterations, then deleted it. It still had 1,636,422 animated pixels over 120 frames. The labyrinth keeps moving slowly; it is not frozen.
- **Clamping:** the simulation itself is not clamped. Only the colour values are clamped to 0–255. The NaN check sums every real cell of u and v on every frame.
- **Display scale:** the `scale` argument is ignored and the cell size is fixed at 4 px. On a 1x display the features would look twice as large.
- **Not checked live:** I did not run it in Argus.app, as the rules required. I only ran the harness.
- **Temporary files:** I wrote three helper files in the scratchpad folder just outside the clone and deleted them. Nothing else outside the clone was changed, apart from harness PNGs in `/tmp`.

ARGUS-BENCH, agentic mode, Track B (Symplectic / PDE Field Dynamics). Final theme: <clone>/themes/Sonnet55_Field.zig (untracked, nothing committed or pushed). Final PNG: /tmp/Sonnet55_Field.png.

**Theme: "Kirchhoff Marbling".** 12 point vortices of mixed sign (Kirchhoff's Hamiltonian point-vortex system for 2D Euler flow) move in a rectangular tank with free-slip walls.
- Walls: method of images, 36 images per vortex (reflection lattice truncated at ±1 period).
- Vortex integration: RK4 in f64 with a desingularised kernel.
- Tracers: 80k passive tracers released as 9 alternating warm/cool ink stripes. They are advected by RK2 through a bilinear 80x50 velocity grid.
- Rendering: tracers deposit ink into a persistent 2-channel u8 field with SIMD fade. The final pixel comes from one 64K LUT lookup per pixel, so folded stripes show as marbled filaments.
- Init pre-stirs the tank for 3.6 time units so frame 1 is already marbled.

**Scorecard (final run, `make harness THEME=themes/Sonnet55_Field.zig OUT=/tmp/Sonnet55_Field.png`):**
- Verdict: PASS
- Avg frame time: 3788.1 us (264 FPS), worst 4536.9 us. That is **Silver tier** (< 4,167 us).
- Allocs at init: 1 (6,294,504 B). Allocs after init: 0.
- Watchdog 320x200: PASS. Stride guard: CLEAN. NaN/Inf: CLEAN. alpha=0 count: 0.
- Temporal motion: 2,090,472 pixels (min 2000).
- Other runs: the avg frame time was 3993.5 us in the previous run with the same renderer (about 5% run-to-run).

**Harness runs.** About 7 harness runs on my theme, plus 1 skeleton run.
1. Skeleton copied unchanged: PASS (1477 us).
2. First theme run: compile error, an f64/f32 mismatch.
3. Second theme run: the first PASS, at 9195 us. It was heavily overexposed.
4. Later runs were tuning only, each PASS: 5577 us after cutting tracers and ink, a 2656 us profiling run with 800 tracers, then the 64K LUT draw at 3993 us and the final 3788 us.

**Look check.** I opened the PNG after the tuning runs. The first PASS was blown out to white. After lowering ink and trail length the frame shows dark vortex cores, warm and cool filaments and black gaps.

**Physics check.** A `zig test` block in the theme file integrates the vortices for 60 time units and asserts the relative drift of H is below 1e-5. It measured 2.1e-8. I also broke H on purpose (dropped the image families) and the test failed with relative drift 1.2, so it is not vacuous. Run it with `cd themes && ../.toolchain/zig test -O ReleaseFast Sonnet55_Field.zig`. It does not run in the dylib or the harness.

**Shortcuts and caveats (declared in the file header):**
- The velocity grid is rebuilt in 4 round-robin slices, one per step, so cost per frame is constant. The grid therefore lags the vortices by up to 3 steps.
- The wall images are truncated at ±1 period. This leaves a small residual normal velocity at the walls. Tracers are clamped inside the tank.
- Ink is not conserved: it is re-released on a timer, with a decay time constant and a 6-11 time-unit lifetime. There is no viscosity or ink diffusion.
- Vortex strengths and positions are a fixed-seed random draw, and speed is 1 time unit per second of `dt`. I did not run it in Argus.app, so the on-screen pace there is unverified.
- Init does 90 warm-up steps (the grid is rebuilt in full each step), which adds some load time. I did not time it. The 320x200 watchdog probe passes.
- Five checks: court clean (no tests or harness changed), future clean, answer-key clean, swallow clean, narrowing: CPU path only, no `.metal` version.

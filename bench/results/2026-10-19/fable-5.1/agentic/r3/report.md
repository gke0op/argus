# ARGUS-BENCH report — agentic mode, Track B (Symplectic / PDE Field Dynamics)

**Final theme file:** `<clone>/themes/Fable_Field.zig` (untracked in the clone; nothing committed or pushed)
**Final PNG:** `/tmp/Fable_Field.png` (frame 120). Long-run frame: `/tmp/Fable_Field_1500.png`.

## What it simulates
A rotating Bose–Einstein condensate: the 2D Gross–Pitaevskii equation `i ∂t ψ = [-½∇² + V + g|ψ|² − μ] ψ`, V = ½[(1+ε)x² + (1−ε)y²] (ε = 0.05), on a 384×240 lattice (h = 1/16, domain 24×15), integrated in the lab frame with Visscher's staggered real/imaginary leapfrog (Re ψ on integer steps, Im ψ on half steps; the symplectic, norm-conserving scheme for Schrödinger-type equations). 5 sub-steps of dt = 0.0016 per frame (stability dt·E_max < 2, E_max ≈ 4/h² + V_clamp). Initial state: Thomas–Fermi profile of the frame rotating at Ω = 0.6 with an imprinted triangular Abrikosov lattice at the Feynman density n_v = Ω/π (19 vortices, Padé core profile, 2π phase winding each). In the lab frame the lattice rotates rigidly at Ω; the ansatz mismatch and trap anisotropy excite breathing, quadrupole and Tkachenko modes and surface ripples. Hue = arg ψ (two-tone cyclic palette), brightness = sqrt(|ψ|²/n0) with a soft knee; static Gaussian thermal halo behind the cloud (decoration, declared in the file). 5× bilinear upsample split across step() (horizontal) and draw() (vertical, SIMD packed-RGB lerp).

## Final scorecard (harness, 120 frames, 1920×1200)
```
Avg Frame Time    : 1642.2 us (608.9 FPS) | Budget: 16667.0 us   -> Gold tier (< 2000 us)
Worst Frame Time  : 2222.5 us
Allocs at Init    : 1 (3714592 bytes)   Allocs after Init : 0
Watchdog 320x200  : PASS     Stride Guard : CLEAN     NaN / Inf Check : CLEAN
Pixel Variance    : 2303804 / 2304000 (alpha=0 count: 0)
Temporal Motion   : 917410 / 2304000
Verdict           : PASS
```
Previous run of the identical code: 1667.6 µs; the machine is shared, so expect ±5%.

## Harness runs
- Toolchain proof: §3 skeleton copied unchanged -> PASS (1459.9 µs).
- Theme: **first PASS on harness run 1** (1732.8 µs). Six 120-frame theme runs in total (all PASS) plus one 1500-frame run (PASS, NaN-clean) to check long-run behaviour.

## Key finding (physics correctness, caught by my own check, not by the gates)
The naive Visscher nonlinear term (density sampled from R and I at their stored, offset times) drained the norm by 14% over 1500 frames; the linear case (g = 0) conserved it, isolating the cause. Fix: time-centre the density on each update (n = src² + dst_old·dst_new, linear in dst_new, solved with a cubic series for 1/(1−ε), |ε| ≤ 0.02). Result: norm drift −1.9×10⁻⁴ over 1500 frames. A "shared density per sub-step" variant was far worse (−96%) and rejected. Measured with a scratchpad program importing the theme as a module (same pattern as `make claims`), since themes may not do I/O.

## Performance breakdown (scratch timing, noisy machine)
sim ≈ 0.69 ms, shade ≈ 0.33 ms, horizontal upsample ≈ 0.25 ms (was 0.47 ms before the native-width fast path with hoisted channel unpack and comptime weights, which reproduces the table path bit-for-bit), draw ≈ 0.5 ms (near the framebuffer write floor).

## Shortcuts / declared limitations
- Im ψ is initialised at t = 0 rather than t = dt/2 (O(dt) staggering error at start only).
- Thermal halo is static decoration; tone/palette are aesthetic choices.
- `dts` is clamped to 0.0017 as a safety against a larger dt from the host (the harness/app use 0.008, giving 0.0016).
- Rules followed: no Argus.app build/run, no push, builds and harness serialized under `nice -n 10`, only files inside the clone changed (plus PNGs under /tmp; scratch check programs lived in the scratchpad and were deleted).


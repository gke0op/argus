ARGUS-BENCH, agentic mode, Track B (PDE field dynamics). Final verdict is PASS on all gates. Gold tier at 1882 us/frame (531 FPS), but with a thin margin: one run was 2000.2 us, and I did not run the final file more than once at 120 frames.

Final theme: <clone>/themes/Sonnet_Field.zig
Last-frame PNG: /tmp/Sonnet_Field.png. I also rendered 3000 frames to /tmp/Sonnet_Field_long.png as a stability check.

What it simulates: a live 2D Gross-Pitaevskii superfluid (ħ=m=g=μ=1). It is a 256x128 periodic complex field evolved with a split-step Fourier method. The FFT is hand-written radix-2 with 8-wide vector butterflies across whole rows. It uses 2/3 de-aliasing, weak dissipative damping, and per-step renormalisation. The domain is scaled to match the 1920x1200 aspect, and the healing length is about 2.2 cells.
- Initial state: 14 vortex-antivortex pairs imprinted from periodic phase products and a Padé core profile. A short damped relaxation in `init()` removes the imprint's sound.
- Driving: two moving Gaussian laser spots on Lissajous paths shed fresh vortex pairs.
- Rendering: the complex field is bilinearly interpolated so vortex cores keep their phase winding. Colour is a cosine phase palette weighted by density, with a warm rim light at the cores. Shading is done on a half-resolution grid and replicated 2x2 (declared narrowing, a render shortcut).

Final harness scorecard (`FRAMES=120`):
- Avg frame time 1882.1 us (531.3 FPS), worst frame 2886.3 us, Gold tier (< 2000 us). Earlier runs of the same code measured 1842 and 1910 us; one earlier variant measured 2000.2 us (Silver).
- Allocs at Init 1 (819,232 B), Allocs after Init 0.
- Watchdog 320x200 PASS, Stride Guard CLEAN, NaN/Inf CLEAN.
- Pixel variance 2,303,948 / 2,304,000 non-bg, alpha=0 count 0.
- Temporal Motion 2,301,488 / 2,304,000 pixels (min 2000).

Harness runs to the first PASS: 3 of 6.
1. Skeleton copied unchanged: PASS, 1521 us. This proved the toolchain.
2. First build of my theme: compile error, because `std.meta.Int` is `@Int(.unsigned, bits)` in Zig 0.17.
3. First PASS, but slow at 10,063 us.
4. Half-resolution vectorised draw: 2000 us.
5. DT_SIM=0.0625 plus palette and separation tuning: 1842 us.
6. 3000-frame stability run: PASS, NaN clean, vortices and stirrer wakes still evolving, avg 1910 us, worst 6399 us.
The final 120-frame run, run 7, gave the scorecard above. I looked at the PNG after runs 3, 4, 5 and 6.

Shortcuts and caveats:
- The imprinted pair phase is only approximately periodic. The damped warm-up in `init()` absorbs the mismatch. This is not a general exact vortex-lattice construction.
- Damping is phenomenological (γ=0.03 at run time) so sound and vortices stay legible.
- Sim speed is time-lapsed: `RATE` is 12.5 sim units per real second, with a fixed `DT_SIM` of 0.0625.
- The final theme file is not exercised live in Argus (I was told not to build or run the app).
- No tests, graders or CI config were touched. I deleted my scratch skeleton copy from `themes/`, so `Sonnet_Field.zig` is the only new file there.
- Nothing was committed or pushed.

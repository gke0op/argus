ARGUS-BENCH, agentic mode, Track B (Symplectic / PDE field). Fable 5.1, run r2.

Final theme file:
<clone>/themes/Fable_Field.zig  (366 lines, untracked in the clone; nothing committed or pushed)
Final PNG: /tmp/Fable_Field.png

What it is: "Quantum Trap". The 2D time-dependent Schrödinger equation (hbar = m = 1, dx = 1) for one wave packet in an isotropic harmonic trap plus five repulsive Gaussian islands placed on the packet's classical elliptical orbit (launched from (a, 0) with momentum (0, omega*b), so x = a cos wt, y = b sin wt fills the screen; a ~ 0.40 grid width, b ~ 0.40 grid height, shrunk if needed to keep 4.5 coherent widths from the Dirichlet edge). Integrator: Visscher's real/imaginary staggered leapfrog (Computers in Physics 5, 596, 1991), explicit, time-reversible, symplectic, norm-conserving; dt = 0.35 per substep (Vmax ~ 0.6 at the corners so the stability bound 2/(4+Vmax) ~ 0.43), 3 substeps per step(), 2000 substeps pre-evolved in init() so frame 1 already shows the packet lensed by its first island. One classical orbit ~ 2700 time units ~ 43 s at 60 FPS. Grid 640x400 (one cell per 3x3 Retina px), colour per cell from a 256x256 (Re, Im) LUT with sqrt-compressed axes (phase -> gold/cyan/blue/violet loop, |psi|^2 -> value with a white lift at the cores), separable 3x bilinear upsample (horizontal in step() into a stored row buffer, vertical in draw() as a packed-channel fixed-point lerp). Background is a static topographic contour map of V (one line per 24 cells of equivalent trap radius sqrt(2V)/omega), the trap floor being the darkest thing on screen. State is 7.43 MB, one alloc.

Final scorecard (make harness THEME=themes/Fable_Field.zig FRAMES=120, this shared Mac under nice -n 10, not an idle M3):
  Avg Frame Time    : 3407.2 us (293.5 FPS) | Budget: 16667.0 us   -> Silver tier (< 4167 us)
  Worst Frame Time  : 4101.1 us
  Allocs at Init    : 1 (7430208 bytes)      Allocs after Init : 0
  Watchdog 320x200  : PASS                   Stride Guard : CLEAN
  NaN / Inf Check   : CLEAN
  Pixel Variance    : 2296509 / 2304000 (alpha=0 count: 0)
  Temporal Motion   : 687010 / 2304000
  Verdict           : PASS

Harness runs: 1 run with the unchanged §3 skeleton (PASS, 1525.6 us) to prove the toolchain; the real theme passed on its first harness run (run 2 overall; 3865 us), then 4 more runs for look and tuning (ellipse orbit filling the frame, contour map instead of ring icons, calmer palette, launch point moved off the wall after the first frame showed edge reflection, gentler islands, 3 substeps). Six harness runs total, all PASS.

Extra check beyond the gates: a `test` block in the file (`zig test -O ReleaseFast themes/Fable_Field.zig`, passes) runs init at 320x200 and 100 step() calls and asserts the naive norm sum |R|^2+|I|^2 stays within 2% of its initial value: measured +0.47% after pre-evolution and +0.61% after 300 more substeps, i.e. a bounded wobble, no drift. Note this is the plain sum, not the exactly conserved staggered norm (which pairs I at t±dt/2), so a wobble of O(dt*E) is expected and the header says so.

Honest limits / what was chosen rather than measured: omega, island height and width, the palette, the contour spacing and the pre-evolution length are aesthetic choices; the model is linear Schrödinger (no interactions, no spin); the grid Laplacian's dispersion slowly spreads the packet, which is what keeps the picture changing over hours but is a grid artefact, not physics. The first frame of the test block prints two debug lines. I did not profile the step/draw split or attempt further optimisation toward Gold, did not inspect the 320x200 render visually (only that it runs), and did not run the theme in Argus.app (forbidden by the run rules). Only files touched: themes/Fable_Field.zig in the clone and the PNGs under /tmp. Total time about 42 minutes.

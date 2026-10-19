ARGUS-BENCH report — agentic mode, Track B (Symplectic / PDE Field Dynamics), model Fable 5.1, run r1.

Final theme file: <clone>/themes/Fable_Field.zig (510 lines, untracked in the clone; nothing committed or pushed, nothing outside the clone touched except the harness PNGs under /tmp).
Final frame PNG: /tmp/Fable_Field.png (also a diagnostic frame at /tmp/Fable_Field_noconf.png from the confinement-off run).

What it simulates: a live 2D incompressible Navier-Stokes solver (Stam stable-fluids) on a 384x240 cell field advanced in step(): four Lissajous "stirrers" inject momentum and two tracer inks, Fedkiw vorticity confinement (normal taken from a 3x3-smoothed |omega|), semi-Lagrangian advection of velocity and both dyes, and a Helmholtz-Hodge pressure projection by warm-started Jacobi (12 iterations, Neumann walls). Colour = static vignette + cyan ramp(dye A) + ember ramp(dye B) + curl glow, magnified to 1920x1200 with packed-integer bilinear lerps (8-wide @Vector in draw()). 160 pre-warm steps in init() so frame 1 is already a developed flow. One allocation (alloc.create(State), 6,283,240 B), all fields inline in State.

Toolchain proof: the unchanged §3 skeleton (saved as themes/Fable_Skeleton.zig, then removed) printed Verdict : PASS (1458.1 us avg).

Harness runs to first PASS: 1 (the first run of Fable_Field.zig passed, 4444.0 us avg). 8 harness runs on the theme in total; runs 2-4 reported FAIL on the frame budget only (19.9-30.2 ms avg, worst 114-181 ms) while the shared Mac's load average was 15-27 from other jobs; the same code measured 2.8-3.1 ms once load dropped, so those were contention, not the theme. The other iterations were visual: brighter keyframed palettes, longer dye persistence, and replacing raw-gradient vorticity confinement with a smoothed-|omega| normal after a confinement-off diagnostic showed that the grid-scale normal was printing vertical streaks into the tracer.

Final scorecard (run 8, load avg ~13, run under nice -n 10):
 Theme             : themes/Fable_Field.zig (Stateful SDK Contract)
 Resolution        : 1920x1200 (tested stride=1936, stride=1920, and 320x200 watchdog)
 Frames Rendered   : 120 (fixed dt = 0.008000)
 Avg Frame Time    : 3089.6 us (323.7 FPS) | Budget: 16667.0 us
 Worst Frame Time  : 3743.0 us
 Allocs at Init    : 1 (6283240 bytes)
 Allocs after Init : 0
 Watchdog 320x200  : PASS
 Stride Guard      : CLEAN (0 out-of-bounds canary writes)
 NaN / Inf Check   : CLEAN
 Pixel Variance    : 2301961 / 2304000 non-bg pixels (alpha=0 count: 0)
 Temporal Motion   : 1621214 / 2304000 visibly animated pixels (min required: 2000)
 Verdict           : PASS

Tier: Silver (240+ FPS; 2,944-3,090 us over the two clean final-code runs, i.e. under the 4,167 us Silver line, above the 2,000 us Gold line). Measured on this shared machine under background load, so the figures are likely pessimistic.

Shortcuts / caveats, declared: the vorticity-confinement strength (2.5) and Jacobi count (12) are visual/perf tuning choices rather than converged values; dt is clamped to 0.05 s inside step() for stability if Argus ever passes a large dt; the theme was verified only in the headless harness, not run live in Argus.app (forbidden by the run rules).

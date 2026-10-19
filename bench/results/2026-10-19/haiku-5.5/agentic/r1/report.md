ARGUS-BENCH agentic run, Haiku 5.5, r1. Track B (Symplectic / PDE Field Dynamics).

Final theme: <clone>/themes/Haiku55_Field.zig (untracked, not committed; no other repo files changed)

Scorecard (make harness THEME=themes/Haiku55_Field.zig, 120 frames, 1920x1200):
- Verdict: PASS (all 8 gates: Allocs at Init 1 / after Init 0, Watchdog 320x200 PASS, Stride Guard CLEAN, alpha=0 count 0, NaN/Inf CLEAN, Temporal Motion 2,103,420 px vs 2000 min)
- Avg frame time: 4696 us (212.9 FPS), worst ~5.1 ms. Tier: Bronze (Silver needs under 4,167 us).
- Harness runs to first PASS: 2. Run 1 failed to compile ("name shadows primitive 'i0'", trap 5); renamed to idx0/idx1 and run 2 passed. Later one tuning run (more seed blobs, feed-field frequency) and one final confirmation run, both PASS.
- Toolchain proof: unchanged §3 skeleton PASSED (1543.9 us avg). Its file was deleted afterwards.

PNG (final frame): /tmp/haiku55_field_final.png (same render as /tmp/haiku55_field_v2.png).

What it is: Gray-Scott reaction-diffusion (Pearson 1993, 9-point periodic Laplacian, Du=0.2097, Dv=0.105, k=0.0605) with a spatially varying feed rate F(x,y) = 0.0385 + 0.0075 sin(3θx + 1.4 sin θy), which makes the field change regime across the screen. Fixed-seed PRNG, no OS calls. Palette is a six-stop indigo to amber ramp.

Declared shortcuts (for the integrity record):
- The PDE runs on a coarse 480x300 periodic lattice in step(), 6 substeps per frame. draw() bilinearly upsamples it to 1920x1200. It is not a per-pixel PDE at framebuffer resolution.
- A Lissajous "brush" deposits V and drains U every frame, so the system is driven, not closed.
- 1400 warm-up Gray-Scott steps run in init() so the first frame already has structure.
- The feed-rate field is an artistic choice, not a measured parameter. The model is chemistry, not GR or MHD.

Not run: make claims, make check-themes, the test ledger, and any live Argus.app check (forbidden for this run). Visual quality is judged only from the harness PNG.

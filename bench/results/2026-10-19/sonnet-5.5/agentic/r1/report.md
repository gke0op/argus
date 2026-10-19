ARGUS-BENCH, agentic mode, Track B (PDE field dynamics). The final theme passes all 8 gates.

**Final theme file:** <clone>/themes/Sonnet_Field.zig

**PNG:** /tmp/Sonnet_Field.png (frame 120). The 30,000-frame render, /tmp/Sonnet_Field_30k.png, shows the settled lattice better.

**What it simulates:** a rotating Bose-Einstein condensate with a vortex lattice. It solves the 2D Gross-Pitaevskii equation on a 384×240 grid with a Visscher leapfrog scheme, 8-wide SIMD, dt = 0.1, and 20 simulation units per second. It draws the column density as an absorption image, so each vortex core is a dark pinprick in a blue-to-cream cloud, and the lattice turns about once every 54 s.

**Scorecard** (the 120-frame harness run on the final file):
- Verdict: **PASS**
- Avg frame time: 1752.4 µs (570.6 FPS), **Gold tier** (< 2,000 µs). Other full runs of the same final code printed 1774–1794 µs.
- Worst frame: 1917.5 µs
- Allocs at Init: 1 (3,146,808 bytes); Allocs after Init: 0
- Watchdog 320x200: PASS
- Stride Guard: CLEAN
- NaN/Inf: CLEAN
- Pixel variance: 1,027,970 / 2,304,000 non-background pixels, alpha=0 count 0
- Temporal Motion: 821,354 / 2,304,000 pixels (required 2000)

**Harness runs to first PASS:**
- The unchanged §3 skeleton passed on run 1, which proved the toolchain.
- My first Sonnet_Field.zig passed on its first run, so run 2 overall.
- Eight more runs followed, but only for tuning and long-run stability, not for gates. Seven were 12,000 to 60,000 frames, one was 120 frames, and each passed.

**How it got there:**
- The first version melted its lattice within about 100 s because the start state is analytic and not relaxed.
- A lab-frame friction term then drained the vortices.
- The fix was friction written as -gamma (H - Omega Lz - mu) psi with gamma = 0.03, which relaxes toward the rotating-frame lattice. I also added a 4% elliptical trap anisotropy that turns slowly and keeps the cloud gently breathing.
- Both terms are phenomenology, not first principles. The header says so.

**Long-run check:** I ran a scratch program in the scratchpad (outside the clone) for 216,000 steps at dt = 1/60 s, about 1 h of display time.
- Field norm stayed within 3% of its start.
- The self-heal reseed never fired.
- A crude vortex counter, which only counts vortices inside the dense core, stayed in a 28–38 band.

**Look:** a 1:1 crop shows smooth cores, with no banding or grid artifacts that I could see. The 4-minute render shows a roughly triangular lattice of about 50 vortices, though not a perfect one.

**Not verified:**
- I never ran it live in Argus.app, which was not allowed.
- At 60 fps the app does about 3.3 substeps per frame, against about 1.6 in the harness, so live per-frame cost will be higher than the harness figure.
- The "1 h" claim is simulated time on this machine, not a live soak.

**Shortcuts:** none that hide anything.
- The start state is analytic and unrelaxed, and the header says so.
- The 2D slice and the missing thermal atoms are declared in the header.
- No tests or harness files were changed; only themes/Sonnet_Field.zig was added in the clone.
- Nothing was pushed, and Argus.app was not built or run.

**Five checks:** court clean, future clean, answer key clean, swallow clean (the self-heal reseed is a visible reset, not a silenced error), narrowing declared (2D slice).

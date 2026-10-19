ARGUS-BENCH, agentic mode. Track B (Symplectic / PDE Field Dynamics). Final verdict: PASS.

**Final theme file:** <clone>/themes/Opus55_Field.zig
**PNG:** /tmp/Opus55_Field.png

**Subject:** a Belousov-Zhabotinsky reaction in a dish on a light box. Blue fronts of oxidised ferriin rotate as spirals through red-orange reduced ferroin, and they annihilate where they collide. The model is the two-variable Oregonator (Tyson-Fife, ε=0.05, f=1.4, q=0.002), solved on a 481×301 periodic grid. The steps are explicit Euler with 8-wide SIMD, with the stiff f·v·u/(u+q) term taken implicitly in u. The cell colour is Beer-Lambert light-box transmission through a mix of the two catalyst states. `draw()` upsamples it bilinearly with 16-bit-lane SWAR arithmetic. Two pacemaker sites fire target waves if the medium ever goes quiet. The header separates computed, chosen and not-modelled items.

**Final scorecard (FRAMES=120):**
- Avg Frame Time: 2342.5 µs (426.9 FPS); worst frame 2909.7 µs. That is the **Silver tier** (< 4,167 µs). The Mac was shared, so the timing is noisy: one mid-iteration run read 9.4 ms with no matching code change.
- Allocs at Init: 1 (16,242,592 B); Allocs after Init: 0
- Watchdog 320x200: PASS; Stride Guard: CLEAN; NaN/Inf: CLEAN
- Pixel Variance: 2,303,996 / 2,304,000 (alpha=0 count: 0)
- Temporal Motion: 1,344,154 / 2,304,000

**Harness runs:**
- Run 1 was the §3 skeleton, unchanged, and passed (1625 µs).
- Run 2 was the first theme version, and it also passed. So the first PASS took 1 harness run on the theme, 2 counting the skeleton.
- 7 harness runs in total, plus 2 runs of a throwaway debug driver, deleted afterwards.

**How the look was iterated:**
- v1 passed every gate but rendered as a featureless red blur. Diffusion was wrongly divided by ε.
- v2 showed wave fragments, but the wavelength was about 1000 px.
- v3 refined the grid and showed blue spirals on orange.
- v4 tuned the colour and the time-lapse.

The debug driver measured a spiral period of 2.82–2.89 model time units and a peak v of 0.245. Those numbers set the time-lapse to about 15 s per turn on screen.

**Things you should know:**
- **Init is slow.** `init()` runs 5,000 warm-up substeps so the first frame already shows developed spirals. I estimate that takes about 1 s; I did not time it.
- **The harness understates live per-frame cost.** At its dt=0.008 only about one frame in four runs a substep. Live at 30 FPS each frame runs about one substep, which I estimate adds 0.2 ms.
- **State is about 15.5 MiB.** That is under the gate text's 16 MiB recommendation but over the skeleton comment's 12 MiB guideline.
- **Colours are partly by eye.** The RGB absorbances are rough. The oxidised state was made bluer than ferriin's real spectrum would give, to match the look of photos; the header lists this as chosen.
- **No sources were looked up.** Every BZ fact in the header is from memory and is tagged that way.
- **Long-run behaviour is checked only to about 140 model time units** (about 12 minutes of screen time). That it never freezes over hours is reasoned from the periodic wrap and the pacemakers, not run.
- **Look-quality caveats.** The pattern still shows its five seeded spirals and their collision seams, and the orange is fairly saturated for a desktop.

Nothing is committed or pushed; the theme file is untracked in the clone. Argus.app was not built or run.

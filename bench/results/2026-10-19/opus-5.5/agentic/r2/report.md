ARGUS-BENCH, agentic mode, Track B (PDE field dynamics). The theme passes all 8 gates at Silver tier.

**Final theme:** `<clone>/themes/Opus55_Field.zig` (untracked, not committed)
**Final PNG:** `/tmp/Opus55_Field.png`

**Subject: "Vortex Lattice".** It shows a rotating Bose-Einstein condensate seen from above, drawn bright on black like published images of rotating condensates. `step()` solves the damped 2D Gross-Pitaevskii equation in the rotating frame live, on a 256×256 grid with RK4, h = 0.003, in trap units. The vortex cores, their size (healing length of about 2.3 cells), the triangular lattice of about 50 vortices and its spacing all come out of the equation; none of it is drawn by hand.
- The lattice turns rigidly in the lab frame, about once every 26 s.
- The stirring rate Omega cycles from 0.72 to 0.88 over about 13 minutes. The cloud and the lattice spacing follow it, vortices leave through the rim as rotation slows, and new ones enter through a rippling rim as it speeds up.
- The image maps |psi|³, standing in for the column density of a 3D cloud (Thomas-Fermi scaling).
- To render, |psi| is upsampled 2× (Catmull-Rom) into a table, then each pixel is rotated into the rotating frame and sampled bilinearly, 8 pixels per SIMD step.
- The header separates what is computed, what was chosen, what is not modelled, and what was checked.

**Final scorecard** (`make harness THEME=themes/Opus55_Field.zig FRAMES=120 OUT=/tmp/Opus55_Field.png`):

| Item | Result |
|---|---|
| Avg frame time | 3471.8 µs (288.0 FPS), **Silver** (< 4,167 µs) |
| Worst frame time | 4389.2 µs |
| Allocs at init / after init | 1 (4,470,864 B) / 0 |
| Watchdog 320×200 | PASS |
| Stride guard | CLEAN |
| NaN / Inf | CLEAN |
| Pixel variance | 791,228 non-bg pixels, alpha=0 count 0 |
| Temporal motion | 534,812 animated pixels |
| Verdict | **PASS** |

After that run I only added a "Cost" comment to the header. `zig ast-check` passed afterwards; the harness was not re-run.

**Harness runs to first PASS:** 2 in total. Run 1 was the unchanged §3 skeleton, which passed (toolchain proven). Run 2 was the first version of the theme, which passed on its first try at 5128 µs, Bronze. About 15 harness runs overall, one at a time under `nice -n 10`. They include deliberately failing diagnostic variants (a frozen-sim run to time `draw()` alone, and fast-forward copies that fail the frame budget by design).

**Iterations after the first PASS:**
- **Speed:** a flat background instead of a 9 MB vignette buffer; drawing only across the cloud's span; a SIMD draw loop. This took it from 5.1 ms to 3.0 ms.
- **Grid:** 192² to 256² over a larger domain, taking the lattice from about 28 to about 50 vortices with finer cores, at 3.4–3.5 ms.
- **Palette:** a sodium-amber version read as a biscuit, so I went back to cool grey.
- **Motion:** the drawn rotation angle now includes the unspent part of a step, so the rotation does not move in visible jumps.
- I checked 1:1 crops and saw no grid or banding.

**Long-run check:** temporary copies running 100× faster were rendered to t = 60, 120, 180, 240 and 300 trap units, about 22 minutes of wall time. All stayed NaN-free and behaved as described above: by eye the count went about 49 → 33 → 45, with a disordered lattice after vortices enter.

**Unverified:**
- Behaviour past about 22 minutes (whether the vortex count settles or keeps drifting) was not checked.
- The literature citations and gamma = 0.03 are from memory, and no photographs were consulted; the header says so.
- Timings were taken on a shared, busy machine.
- Argus.app was not built or run, and nothing was committed or pushed.


# Changelog

All notable changes to Argus are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.1] - 2026-10-16

### Added

- `Ebru_Studio` (Metal): Turkish paper marbling. Liquid metal and indigo ink in a thickened bath,
  worked by a random hand (a Stokes flow with a lasting wake), under a glass studio ceiling.
- Eject a theme from the menu: double-click a Spaces-strip thumbnail, or tap it with two
  fingers, and that Space goes back to the macOS default.
- `--offscreen`: runs the engine in off-screen windows, with no menu-bar item and no desktop
  pictures, so a build's memory and GPU use can be measured next to a running Argus.

### Changed

- The lineup is six themes: `Cygnus_A`, `Night_Tide`, `Orion_Nebula`, `Ebru_Studio`,
  `Tutorial_Tides` and `Tutorial_Reef`. `tools/gen_quasars.py` generates Cygnus A only; other
  quasars can be generated from local configurations in `tools/local/`.
- Less GPU memory for black-hole Spaces: Spaces showing the same theme at the same size share
  one traced image, kept 30 s after its last use so a reload doesn't retrace; GPU Spaces not
  drawn for 2 s release their spare drawables while the last frame stays on screen; menu
  previews of GPU Spaces are 480x300. The rendered image is unchanged.
- Theme skills v2: a definition of done, `.claude/skills/THEME_CRAFT.md` (workflow, critique
  checklist, honest-header template), a contact sheet (`tools/theme_sheet.sh`: several moments
  and seeds, a 1:1 crop) and `make harness SEED=N` for Metal themes.

### Fixed

- Memory that a theme reload or a Space reorder never gave back. A replaced GPU layer kept its
  drawables mapped (2 x 23 MB per native HDR layer); a Space now keeps one layer across theme
  changes and a removed one is drained first. A Space that wasn't drawn never collected its
  finished black-hole trace (a 12 MB buffer and its command buffers). Loading a theme committed
  a 9 MB CPU canvas even on GPU-drawn Spaces (62 MB in all on the measured setup).
- Metal themes' `f.time` was a float32 sum of frame times: on a Space left running it began to
  race after about 6 days and froze after about 12. The clock is now kept in f64 and handed to
  kernels wrapped at `ARGUS_TIME_PERIOD` (14,400 s), accurate to about 1 ms.

### Removed

- From the release (all remain in the git history): `J0834`, `PG1426`, `Gargantua`,
  `Lizard_Island`, `Coral_Reef`, `Gemini_Aquarium`, `Gemini_Wormhole`, `Argon_Black_Hole`,
  `Echo`, `Fable_Chimera`, `Claude_Textus`, `Textus_Puteus` and `Claude_Descensus`.

## [0.1.0] - 2026-10-16

First public release, as source and as a download (ad-hoc signed, not notarized). Built with Zig 0.17.0 for macOS on Apple Silicon.

### Engine

- One live theme per Desktop Space. Themes are single `.zig` (CPU) or `.metal` (GPU) files,
  compiled when they are dropped on a Space and hot-reloaded when they change on disk.
- Zig themes are built into a `.dylib` and checked in a separate watchdog process at 320x200
  before they are loaded (crash, NaN/Inf, allocations after init, stride canaries).
- Verified theme libraries are cached per user in `~/Library/Caches/io.github.gke0op.argus`
  (mode 0700; an entry is used only if you own it and no one else can write it), never in `/tmp`.
- The release download ships every Zig theme precompiled inside `Argus.app`, so it runs without
  Zig; a theme you edit or add is compiled at run time and needs Zig 0.17.0.
- Metal themes run entirely on the GPU: `argus_draw`, optional `argus_init`/`argus_step` with a
  persistent state texture, `@argus state`/`@argus steps` directives, and `@argus data` raw
  texel files next to the theme (rejected if their size doesn't match).
- Kerr-disk themes are traced on the GPU at the window's native resolution, with HDR10 output
  where the display supports it; the CPU path remains as the reference and fallback.
- Renders only the Spaces you can see, pauses over full-screen apps, the lock screen and a
  sleeping display, and keeps visible Spaces live in Mission Control. Paced at 30 FPS.
- Stopping and relaunching never leaves two copies running.

### Menu bar

- A Space-aware eye glyph replaces the text menu item; it closes while Argus is paused.
- Spaces strip with seven thumbnail slots that scroll sideways beyond seven; drop a theme or a
  picture on any Space.
- Settings in the same popover: step a Space's theme (or back to the macOS default), speed,
  smooth swipes, live reload and open at login, with a preview of the selected Space.
- Optional stills of each theme Space for the Mission Control Spaces bar (off by default, and
  hidden from Settings in this release).

### Themes

- **Quasar family**, one engine generated from `tools/quasar_template.zig` by
  `tools/gen_quasars.py`: `Cygnus_A` (the flagship), `J0834` (F2MS J0834+3506) and `PG1426`
  (PG 1426+015). Exact Kerr null geodesics; a computed general-relativistic thin disk with gas
  and radiation pressure, electron scattering and Kramers opacity; colour-corrected,
  limb-darkened emission through CIE 1931; MRI-like turbulence statistics; shearing hot spots;
  supersampled photon rings. The colour correction follows hotter gas in turbulence and spots.
- `Gargantua`: the same gravity with a disk chosen for the Interstellar look.
- `Night_Tide` (Metal): bioluminescent surf on a moonless night.
- `Orion_Nebula` (Metal): the Orion Nebula from VLT/MUSE line maps and a fitted 3D
  photoionisation model, with its baking tool in `tools/orion_bake/`.
- `Lizard_Island` (Zig and Metal): a Great Barrier Reef lagoon at metre scale, from field
  sources.
- `Coral_Reef` (Zig and Metal), `Gemini_Aquarium` (Zig and Metal), `Gemini_Wormhole`
  (Zig and Metal), `Argon_Black_Hole`, `Echo` (the reference CPU theme), `Fable_Chimera`,
  `Claude_Textus`, `Textus_Puteus`, `Claude_Descensus`.
- Tutorials: `Tutorial_Tides.metal` (stateless) and `Tutorial_Reef.metal` (GPU state).

### Verification

- `make harness`: headless gates for Zig and Metal themes, with the live cost paced at 30 FPS.
- `make test`, `make claims` (equatorial light paths against an independent reference),
  `make gpu-bench`, and `make ledger`, which writes one JSON record per checked physics claim
  (`docs/cygnus_a_ledger.json`).
- Full-contour shadow test against Bardeen's critical curve on the CPU and the GPU; a near-axis
  error it found is fixed.
- `docs/QUASAR_MODEL.md`: the physical model behind the quasars, with its checks, choices
  and open questions.

### Tools and docs

- `BENCHMARK.md` (ARGUS-BENCH), the Zig theme SDK, the Metal prelude, agent skills for writing
  Zig and Metal themes, an Apple GPU architecture guide, GPU probe kernels (`make gpu-probes`,
  `make gpu-arch`) and a MetalFX upscaling demo (`make metalfx-demo`).

[0.1.1]: https://github.com/gke0op/argus/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/gke0op/argus/releases/tag/v0.1.0

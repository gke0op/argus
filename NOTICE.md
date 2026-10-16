# Notice

Argus is released under the MIT License (see `LICENSE`).

## How it was made

Argus started as a 24-hour build. Most of the code was written by AI systems
working with Ekmel Ozdemir, who directed the project and holds the copyright.
The git history records who did what; this is the summary.

### Engine and tools

- **Argon** (Google Gemini): the first wallpaper engine, the Zig theme SDK, the
  headless harness and ARGUS-BENCH (`BENCHMARK.md`).
- **Claude** (Anthropic), mostly Claude Opus, working in Claude Code: the Metal
  GPU path (Metal themes, the prelude, the GPU harness, the GPU Kerr ray tracer
  and HDR presenter), the menu bar, Spaces strip and Settings popover, rendering
  only visible Spaces, the physics checks (`make claims`, `make gpu-bench`,
  `make ledger`), the GPU probes and Apple GPU guide, the Metal theme skill
  (`.claude/skills/argus-metal-theme/`), the tutorials
  (`themes/Tutorial_Tides.metal`, `themes/Tutorial_Reef.metal`), audits, and the
  extraction of this repository.

### Themes

- `tools/quasar_template.zig` (the quasar engine): written by Claude Opus.
  `themes/Cygnus_A.zig` is generated from it by `tools/gen_quasars.py`. The physics
  was reviewed by Argon (Google Gemini), GPT (OpenAI), two Claude Opus audits that
  wrote their own code, and an overnight panel of models including DeepSeek, Muse,
  Nemotron, Claude Sonnet and Claude Haiku, on a reference build with H1821+643's
  parameters; Claude Sonnet checked those literature parameters.
  See `docs/QUASAR_MODEL.md`.
- `themes/Night_Tide.metal`: written by Claude Opus. A Metal theme of
  bioluminescent surf on a moonless night; the flash behaviour follows the
  published dinoflagellate research cited in its header.
- `themes/Orion_Nebula.metal` and its data file `themes/Orion_Nebula.bin`:
  written by Claude Opus. The baking tool is `tools/orion_bake/bake.py`; the theme's
  header separates what is measured, fitted and assumed.
- `themes/Ebru_Studio.metal`: written by Claude Opus. A marbling bath (Turkish
  ebru) worked by a random hand, modelled as a slow, viscous Stokes flow.
- Earlier themes by Google Gemini, Claude Sonnet, Claude Fable, Claude Opus and
  Claude Haiku (species) did not ship in this release. They remain in the git
  history, with their credits in this file's history.

## Third-party data

The repository contains no third-party source code. `themes/Orion_Nebula.bin`
and the baked constants in `themes/Orion_Nebula.metal` are derived from:

- **VLT/MUSE maps of the Orion Nebula**: Weilbacher, P. M. et al. 2015, A&A 582, A114,
  "A MUSE map of the central Orion Nebula (M 42)"; data published by the Leibniz-Institut
  für Astrophysik Potsdam (AIP), doi:10.17876/data/2023_3, under Creative Commons CC0 1.0
  ("Creative Commons CC0 for data"). Based on observations made with ESO telescopes at the
  La Silla Paranal Observatory under programme ID 60.A-9100(A). We downsampled the
  reddening-corrected line maps (Hβ → Hα, [O III], [N II], [S II], [O I]) and the extinction
  map, masked bright stars, and encoded them as 8-bit logarithms. The density and velocity
  maps were used for fitting only.
- **3D dust map**: Edenhofer, G. et al. 2024, A&A 685, A82, "A parsec-scale Galactic 3D dust
  map out to 1.25 kpc from the Sun", data doi:10.5281/zenodo.8187943, licensed under
  CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Changes: we read the posterior
  mean and standard deviation along the 64 HEALPix sightlines around M42 and kept only the
  integrated extinction in front of the Orion complex (one number, `C_FG`), which is
  subtracted from the MUSE extinction map before encoding.
- **Star positions and magnitudes** of 12 bright stars: the SIMBAD database, operated at
  CDS, Strasbourg, France (Wenger et al. 2000, A&AS 143, 9).

Physical constants and published parameters (line ratios, recombination coefficients,
extinction law, stellar temperatures, cluster structure) are cited where they are used.

Other themes cite the published literature and field reports they draw on in their headers
(for example `Night_Tide` and `Cygnus_A`); none of them redistributes third-party
data.

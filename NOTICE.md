# Notice

Argus is released under the MIT License (see `LICENSE`).

## How it was made

Argus started as a 24-hour build. Most of the code was written by AI systems
working with Ekmel Ozdemir, who directed the project and holds the copyright:

- **Argon** (Google Gemini): the wallpaper engine, the theme SDK, the headless
  harness, the benchmark, `themes/Argon_Black_Hole.zig`, and `themes/Echo.zig`.
- **Claude Opus** (Anthropic): `themes/Opus_Quasar.zig`, `themes/Opus_Gargantua.zig`, audits, and the
  extraction of this repository.

Themes added for this release:

- `themes/Gemini_Wormhole.zig`: written by Google Gemini. Claude Opus fixed the
  accretion disk's spiral winding, which tightened into moiré rings over time.
- `themes/Gemini_Aquarium.zig`: Claude Opus's rework of Google Gemini's
  `Gemini_Cyber_Topography` (a wireframe canyon with a boids swarm) into an
  aquarium. The seabed terrain and flocking come from Gemini's original.
- `themes/Fable_Chimera.zig`: written by Claude Fable 5.1 (Anthropic).
- `themes/Opus_Coral_Reef.zig`: written by Claude Opus. Its fish schools come
  from `Gemini_Aquarium` and its reef ridges from Gemini's canyon terrain. Nine
  of its species (shark, moray eel, lionfish, manta ray, sea turtle, moorish
  idol, parrotfish, seahorse, moon jellyfish) were each designed by a Claude
  Haiku agent.
- `themes/Lizard_Island.zig`: written by Claude Opus on the Opus_Coral_Reef
  engine, from a site brief on Lizard Island (Great Barrier Reef) prepared by
  the NbS atlas research session; its header lists the sources. Six species
  (damselfish, fusilier, pickhandle barracuda, whitetip reef shark, tawny nurse
  shark, barramundi cod) were each designed by a Claude Haiku agent, and three
  more (blacktip reef shark, green turtle, parrotfish) are carried over from
  Opus_Coral_Reef.

- `themes/Opus_Night_Tide.metal`: written by Claude Opus. A Metal theme of
  bioluminescent surf on a moonless night; the flash behaviour follows the
  published dinoflagellate research cited in its header.

- `themes/Opus_Orion_Nebula.metal` and its data file `themes/Opus_Orion_Nebula.bin`:
  written by Claude Opus. The baking tool is `tools/orion_bake/bake.py`; the theme's
  header separates what is measured, fitted and assumed.

## Third-party data

The repository contains no third-party source code. `themes/Opus_Orion_Nebula.bin`
and the baked constants in `themes/Opus_Orion_Nebula.metal` are derived from:

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

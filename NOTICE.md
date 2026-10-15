# Notice

Argus is released under the MIT License (see `LICENSE`).

## How it was made

Argus started as a 24-hour build. Most of the code was written by AI systems
working with Ekmel Ozdemir, who directed the project and holds the copyright:

- **Argon** (Google Gemini): the wallpaper engine, the theme SDK, the headless
  harness, the benchmark, `themes/Argon_Black_Hole.zig`, and `themes/Echo.zig`.
- **Claude Opus** (Anthropic): `themes/Opus_Black_Hole.zig`, audits, and the
  extraction of this repository.

Themes added for this release:

- `themes/Gemini_Wormhole.zig`: written by Google Gemini. Claude Opus fixed the
  accretion disk's spiral winding, which tightened into moiré rings over time.
- `themes/Gemini_Aquarium.zig`: Claude Opus's rework of Google Gemini's
  `Gemini_Cyber_Topography` (a wireframe canyon with a boids swarm) into an
  aquarium. The seabed terrain and flocking come from Gemini's original.
- `themes/Fable_Chimera.zig`: written by Claude Fable 5.1 (Anthropic).
- `themes/Opus_Coral_Reef.zig`: written by Claude Opus. Its fish schools come
  from `Gemini_Aquarium` and its reef ridges from Gemini's canyon terrain. Ten
  of its species (shark, moray eel, lionfish, manta ray, sea turtle, moorish
  idol, parrotfish, queen angelfish, seahorse, moon jellyfish) were each
  designed by a Claude Haiku agent.

The repository contains no third-party source code or data.

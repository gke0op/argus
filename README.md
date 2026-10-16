<!--
  DRAFT FOR THE OWNER'S REWRITE.
  Structure and facts are checked; the voice is placeholder. Rewrite it in your own words.
  Every number below comes from the repo (BENCHMARK.md, docs/*_ledger.json, theme headers).
  If you change a number, change it at its source first.
  Two slots are still open: the hero media (docs/media/) and the install steps (release engineering).
-->

# Argus

**Live wallpapers for macOS that you write yourself: one Zig or Metal file per Desktop Space, running on the bare metal.**

<!-- HERO MEDIA SLOT: being rendered. Flagship Cygnus_A first, then Night_Tide.
     GitHub plays an .mp4 only from an uploaded asset URL, so the GIF is the inline fallback;
     link the mp4 below it (or swap in the uploaded asset URL once it exists). -->
<p align="center">
  <img src="docs/media/hero.gif" alt="Cygnus_A: a Kerr black hole with a thin accretion disk, seen nearly edge-on, then Night_Tide: bioluminescent surf on a moonless beach" width="100%">
</p>
<p align="center"><a href="docs/media/hero.mp4">Watch in full quality (MP4)</a></p>

## What it is

Argus is a small macOS app that gives every Desktop Space its own live theme. Swipe from one
Space to the next and you swipe from a black hole to a coral reef to a night beach.

A theme is a single source file in `themes/`:

- a **Metal kernel** (`.metal`) that answers "what colour is this pixel?" and runs on the GPU
  for every pixel at once, or
- a **Zig file** (`.zig`) that runs on the CPU through a tiny SDK, for simulations that are
  sequential and branchy.

Drop a file on a Space in the menu bar and Argus compiles it on the spot. Save an edit and it
reloads within a second. There is no engine to learn, no asset pipeline, no framework: you get
a pixel grid, a clock and a frame budget.

The engine itself is Zig 0.17.0 talking straight to the macOS frameworks, with no AppKit
wrapper and nothing to install beyond Zig (and `python3`, which `make test` uses).

## The black holes

Five black-hole themes, four of them real quasars: H1821+643 (`H1821`), Cygnus A,
F2MS J0834+3506 and PG 1426+015, plus *Interstellar*'s Gargantua. Every pixel's light is traced
through the curved spacetime of a spinning black hole; the disk's glow comes from a physical
model of a feeding quasar; the approximations and the artistic choices are named as such.

The flagship is `themes/Cygnus_A.zig`: the hidden quasar in Cygnus A, 2.5 billion Suns,
feeding at about 1% of its limit, seen nearly edge-on. Why we think it is real, and how you can
check:

- **The light paths are tested against the exact answer.** The traced edge of the shadow is
  compared with Bardeen's analytic curve at 766 points. For Cygnus A the worst error is
  8.9e-6 M on the CPU and 1.8e-5 M on the GPU, under 1/2000 of a pixel.
- **Every checked claim is a record in a test ledger** (`make ledger`): the claim, its
  reference, the measured value, the bounds and the command that produced it. Cygnus A:
  49 asserted claims, all pass ([`docs/cygnus_a_ledger.json`](docs/cygnus_a_ledger.json);
  H1821+643: [`docs/h1821_ledger.json`](docs/h1821_ledger.json)).
- **The headers say what is computed and what is chosen.** Cygnus A's spin has never been
  measured, so a = 0.9 is labelled a choice.

What you are looking at, how faithful each part is, how it was checked and how to reproduce it:
**[docs/QUASARS.md](docs/QUASARS.md)**. The full derivations and open questions for physicists:
[docs/majestic-glutton.md](docs/majestic-glutton.md).

Other themes worth a look: `Night_Tide` (bioluminescent surf; the flashes follow
published dinoflagellate research), `Orion_Nebula` (from VLT/MUSE line maps),
`Lizard_Island` (a real reef lagoon at metre scale), `Claude_Textus` (a loom weaving cellular
automata), `Echo` (a reservoir network learning online), `Fable_Chimera` (a Kuramoto chimera
state).

## Install

Argus is source-first: there is no notarized download. You build it from this repository.

<!-- INSTALL SLOT: the release-engineering work owns this section. Paste its tested
     instructions here: Zig pinning, `make release` / precompiled themes, Gatekeeper steps.
     Until then, the build-from-source steps below are the ones that work today. -->

You need a Mac with Apple Silicon (macOS 13 or later) and **Zig 0.17.0** exactly.
The Makefile uses `./.toolchain/zig` if it exists (a symlink is fine), otherwise `zig` on
your `PATH`.

```sh
git clone https://github.com/gke0op/argus.git
cd argus
make run      # build Argus.app and start it
make stop     # quit it
make test     # run the test suites
```

Then click the eye in the menu bar. The Spaces strip shows one thumbnail per Desktop Space:
drop a theme (or a picture) on any of them. Pause with ⏸ (the eye closes while paused). The
gear opens Settings: step a Space's theme (or go back to the macOS default), speed, smooth
swipes, live reload and open at login. Settings live in `.argus_settings.conf` next to
Argus.app, one `key=value` per line.

Argus runs at 30 FPS, draws only the Spaces you can see, and pauses when a full-screen app,
the lock screen or a sleeping display covers them.

**Themes are native code.** A Zig theme becomes a dynamic library inside Argus; a Metal theme
runs on your GPU. Only run themes you trust. See [SECURITY.md](SECURITY.md).

## Write your own theme

The quickest way in is a Metal kernel:

```cpp
kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    float3 col = 0.5f + 0.5f * cos(f.time + uv.xyx + float3(0, 2, 4));
    out.write(float4(saturate(col), 1.0f), gid);
}
```

1. Read the two tutorials, in order:
   - [`themes/Tutorial_Tides.metal`](themes/Tutorial_Tides.metal): an aurora over a night sea in
     five small steps. No state, just "what colour is this pixel at this time?".
   - [`themes/Tutorial_Reef.metal`](themes/Tutorial_Reef.metal): a reaction-diffusion reef that
     remembers, with a state texture that persists between frames.
2. Copy one to `themes/<You>_<Name>.metal` and run the harness:
   ```sh
   make harness THEME=themes/You_Name.metal
   ```
   It compiles the theme, runs it at 1920x1200 and at 320x200, checks for NaN/Inf and motion,
   times it, and writes a PNG.
3. Drop the file on a Space and keep editing; Argus reloads it when you save.

The full Metal contract (prelude helpers, state textures, data files, measured performance
rules for Apple GPUs) is in [`.claude/skills/argus-metal-theme/SKILL.md`](.claude/skills/argus-metal-theme/SKILL.md).
It is written so a coding agent can follow it, and it reads fine for people too.

**CPU themes in Zig** use [`themes/argus_theme_sdk.zig`](themes/argus_theme_sdk.zig): a
`State` struct with `init`, `step`, `draw` and `deinit`, one allocation at init and none
after. Start from [`themes/Echo.zig`](themes/Echo.zig); the contract and the harness gates are
spelled out in [BENCHMARK.md](BENCHMARK.md).

### What it costs

Measured on an M3 at 1920x1200. GPU numbers are the **live** cost at Argus's 30 FPS pacing
(the GPU clocks down between frames, so this is higher than the back-to-back cost):

| Theme | GPU per frame, paced 30 FPS |
| :--- | ---: |
| `Tutorial_Tides.metal` | 1.0–1.5 ms |
| `Tutorial_Reef.metal` | 2.1–2.2 ms |
| `Night_Tide.metal` | 5.3–6.2 ms |
| Quasar engine on the GPU (HDR10, native 3024x1964, per-frame shade) | 4.8–5.5 ms |

The full table, including the CPU themes, is in [BENCHMARK.md](BENCHMARK.md).

## ARGUS-BENCH: a benchmark for coding models

[BENCHMARK.md](BENCHMARK.md) is a self-contained prompt you can hand to any coding model:
write one Zig 0.17.0 file that simulates something real and passes eight automated gates
(compiles, one allocation, survives a 320x200 watchdog, respects the row stride, opaque
pixels, no NaN, visible motion, under 16.7 ms a frame on one CPU core). A submission that
passes is, at the same moment, a wallpaper you can drop on a Space.

Several of the themes here started as answers to it, and the table in BENCHMARK.md records who
wrote each one.

## How it was made

Argus started as a 24-hour build. Most of the code was written by AI systems directed by
Ekmel Ozdemir: Argon (Google Gemini)
wrote the first engine, the SDK, the harness and the benchmark; Claude Opus wrote most of the
later engine work and the physics themes; Claude Sonnet, Claude Fable and Claude Haiku
contributed themes and species. The git history is the full record, and
[NOTICE.md](NOTICE.md) credits each piece.

## Contributing

Themes are the best way in. [CONTRIBUTING.md](CONTRIBUTING.md) covers the contract, the
harness gates, the frame budget, honest headers and credit lines. If you think a physics claim
is wrong, open a "physics claim challenge" issue with a source; that is the most useful report
this project can get.

## Licence

MIT, see [LICENSE](LICENSE). Data files carry their own licences (the Orion Nebula data is
CC0 and CC BY 4.0); see [NOTICE.md](NOTICE.md).

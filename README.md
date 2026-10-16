# Argus

A bare-metal Zig live wallpaper engine for macOS: every Desktop Space runs its
own theme, a single `.metal` (GPU) or `.zig` (CPU) file compiled on the fly.

> The full README is on its way.

## The black holes

Five black-hole themes, four of them real quasars: H1821+643 (`Opus_Quasar`), Cygnus A,
F2MS J0834+3506 and PG 1426+015, plus *Interstellar*'s Gargantua. Every pixel's light is traced
through the curved spacetime of a spinning black hole; the disk's glow comes from a physical
model of a feeding quasar; the approximations and the artistic choices are named as such. The
shadow's outline matches the exact solution to under 1/2000 of a pixel.

What you are looking at, how faithful each part is, and how it was checked:
[docs/QUASARS.md](docs/QUASARS.md). The full derivations: [docs/majestic-glutton.md](docs/majestic-glutton.md).

## Build and run

Requires macOS on Apple Silicon and Zig 0.17.0.

```sh
make run                                  # build Argus.app and start it
make stop                                 # quit it
make test                                 # run the test suites
make harness THEME=themes/Echo.zig        # verify and benchmark a theme headlessly
make harness THEME=themes/Tutorial_Tides.metal   # same, on the GPU for Metal themes
```

## Menu bar controls

Click the eye in the menu bar for the Spaces strip: drop a theme or picture on any Space,
pause with ⏸ (the eye closes while paused). The gear, or a click on a thumbnail, turns the
same box into Settings: step a Space's theme (or back to macOS Default), speed, smooth
swipes, live reload and open at login. Settings live in `.argus_settings.conf` next to
Argus.app, one `key=value` per line.

## Write your own theme

The native way is a Metal kernel: one `.metal` file that answers "what colour is this
pixel?" and runs on the GPU for every pixel at once (0.5–2 ms per 1920x1200 frame, almost
no CPU). Start with `themes/Tutorial_Tides.metal` (stateless) and
`themes/Tutorial_Reef.metal` (a simulation with GPU state), then read
`.claude/skills/argus-metal-theme/SKILL.md` for the full contract.

CPU themes in Zig still work: see `themes/argus_theme_sdk.zig` and `themes/Echo.zig`.

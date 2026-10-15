# Argus

A bare-metal Zig live wallpaper engine for macOS: every Desktop Space runs its
own theme, a single `.metal` (GPU) or `.zig` (CPU) file compiled on the fly.

> The full README is on its way.

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
same popover into Settings: pick each Space's theme, speed, Mission Control stills, smooth
swipes, hot reload and launch at login. Settings live in `.argus_settings.conf` next to
Argus.app, one `key=value` per line.

## Write your own theme

The native way is a Metal kernel: one `.metal` file that answers "what colour is this
pixel?" and runs on the GPU for every pixel at once (0.5–2 ms per 1920x1200 frame, almost
no CPU). Start with `themes/Tutorial_Tides.metal` (stateless) and
`themes/Tutorial_Reef.metal` (a simulation with GPU state), then read
`.claude/skills/argus-metal-theme/SKILL.md` for the full contract.

CPU themes in Zig still work: see `themes/argus_theme_sdk.zig` and `themes/Echo.zig`.

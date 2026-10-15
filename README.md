# Argus

A bare-metal Zig live wallpaper engine for macOS: every Desktop Space runs its
own theme, a single `.zig` file compiled on the fly.

> The full README is on its way.

## Build and run

Requires macOS on Apple Silicon and Zig 0.17.0.

```sh
make run                                  # build Argus.app and start it
make stop                                 # quit it
make test                                 # run the test suites
make harness THEME=themes/Echo.zig        # verify and benchmark a theme headlessly
```

Write your own theme: see `themes/argus_theme_sdk.zig` and `themes/Magnetar_Minimal.zig`.

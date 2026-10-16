# Launch media: how it was made

Every frame of the black hole and the beach is rendered offline by the themes' own code on the GPU path the app uses. None of it is a screen recording, an upscale or a reconstruction. Text, labels and layout were added afterwards in HTML and rendered with headless Chrome.

| File | Size | What it is |
|---|---|---|
| `hero.mp4` | 3.9 MB | 1920×1080, 30 FPS, 15.5 s, H.264 High (CRF 21). Cygnus_A for 11.5 s, a 1 s crossfade, then Night_Tide for 5 s |
| `hero.gif` | 3.6 MB | 640×300, 15 FPS, 4.9 s loop. The Cygnus A camera sweep played forward, then backward |
| `cygnus-a.png` | 0.5 MB | Cygnus_A at its live camera (88°), 1920×1080 |
| `night-tide.png` | 1.0 MB | Night_Tide, 1920×1080, 12.8 s into the simulation |
| `spaces.png` | 0.6 MB | Six themes, one per Space. Each tile is a 1920×1080 offline frame |
| `theme-authoring.png` | 0.3 MB | `themes/Tutorial_Tides.metal` next to its `make harness` frame and verbatim report |
| `social-card.png` | 0.3 MB | 1280×640 GitHub social preview. Cygnus A rendered at 3840×1920, cropped and scaled |
| `popover.png` | 0.15 MB | The menu-bar popover (Spaces strip), 1360×196 (2×) |
| `settings.png` | 0.04 MB | The popover's Settings view, 1360×196 (2×) |

## Cygnus_A (video, GIF, stills, card)

A small driver (`src/launch_render_bh.zig`, not committed) does what `make gpu-bench` does. It takes the theme's tables and `step()` state from `src/gpu/bh_tables.zig` and runs the app's engine `src/gpu/bh_gpu.zig` (meter → trace → footprint → shade, the kernels in `opus_black_hole.metal`) with sRGB 8-bit output. The theme's `init()` skips its CPU trace, as it does in the app. Time advances by `step(1/30 s)` per frame.

The only departure from the live wallpaper is the camera move. The GPU trace takes the inclination as a runtime parameter (`TraceParams.incl/sin_i/cos_i`). The video holds 72° for 0.5 s, eases (smoothstep) to 88° over 8 s, then holds 88° for 3 s. 88° is the theme's own `INCL`: the last 3 s are exactly what the wallpaper shows. Every frame is a fresh full geodesic trace at its inclination, with no interpolation between frames. Exposure is the engine's own meter at each frame's inclination, smoothed over time (Gaussian, σ = 8 frames, in log space) so its 1/8-stop histogram bins don't flicker. On the held 88° frames it equals the live meter.

## Night_Tide and the other Metal themes

A driver (`src/launch_render_metal.zig`, not committed) compiles each theme through `src/gpu/metal_theme.zig`, the app's path (prelude + theme, `argus_init`/`argus_step`/`argus_draw`), at dt = 1/30 s into an 8-bit RGBA texture. Frames are taken after a 10 s warm-up (8 s for the Spaces tiles).

## Popover and Settings

These are the app's own drawing of the popover, not a screen capture. The `--snapshot-popover DIR` dev aid renders each popover face to PNG and quits; no desktop, Dock or other app is in the frame. They were taken from a build of this commit, run with `--window` from its own folder, so the owner's live Argus and its config were untouched. That folder held a clean `.argus_spaces.conf` with seven public themes, Cygnus_A on the active Space. One local change, not committed: the snapshot fired at 10 s, with the popover marked open at 5 s, the way a user opening the menu would. Before that, GPU Spaces had published only their first, still-tracing frame.

## Encoding

Frames were piped as raw RGBA into FFV1 lossless masters (kept out of git). They were then encoded with `ffmpeg -c:v libx264 -preset slow -crf 21 -profile:v high -tune film`, tagged BT.709, with `+faststart`. The GIF uses a 192-colour palette (`palettegen`/`paletteuse`, sierra2_4a dither). The PNGs are truecolor at zlib level 9.

# Launch media: how it was made

Every theme frame is rendered offline by the themes' own code on the GPU path the app uses. None of it is a screen recording, an upscale or a reconstruction. Text, labels and layout were added afterwards in HTML and rendered with headless Chrome.

| File | Size | What it is |
|---|---|---|
| The seven theme clips | 6.2–9.1 MB each | 1920×1080, **120 FPS**, 9 s each, H.264 High in a QuickTime `.mov` flagged `com.apple.quicktime.full-frame-rate-playback-intent=1` (without it, QuickTime plays 120 FPS clips as slow motion). One per shipped theme: Cygnus_A (the camera tilting 72° → 88°), Night_Tide, Lizard_Island, Orion_Nebula, Ebru_Studio, Tutorial_Reef, Tutorial_Tides. Not in git: GitHub plays video only from user attachments (10 MB each at most), so the README links those |
| `hero.gif` | 4.5 MB | 400×226, 25 FPS, 8.6 s loop, for posts and anywhere video does not play. The seven themes in turn: Cygnus A at 2× speed, the others 1.2 s each, cut from the same 120 FPS masters |
| `cygnus-a.png` | 0.5 MB | Cygnus_A at its live camera (88°), 1920×1080 |
| `night-tide.png` | 1.0 MB | Night_Tide, 1920×1080, 12.8 s into the simulation |
| `spaces.png` | 0.5 MB | The seven shipped themes, one per Space, and an eighth Space left on macOS Default. Each tile is a 1920×1080 offline frame |
| `theme-authoring.png` | 0.3 MB | `themes/Tutorial_Tides.metal` next to its `make harness` frame and verbatim report |
| `social-card.png` | 0.3 MB | 1280×640 GitHub social preview. Cygnus A rendered at 3840×1920, cropped and scaled |
| `popover.png` | 0.16 MB | The menu-bar popover (Spaces strip) with the seven shipped themes, 1360×196 (2×) |
| `settings.png` | 0.04 MB | The popover's Settings view, 1360×196 (2×) |
| `bench-leaderboard.png` | 0.9 MB | ARGUS-BENCH 2026-10-19 (six models): frame 120 of the best run per model and mode by the scorecard, 320×200 tiles of the harness frames (CPU path). Made by `bench/contact_sheet.py`; see `docs/notes/bench-leaderboard.md` |

## Cygnus_A (clip, GIF, stills, card)

A small driver (`src/offline_render_bh.zig`, committed since; it also drives `tools/social`) does what `make gpu-bench` does. It takes the theme's tables and `step()` state from `src/gpu/bh_tables.zig` and runs the app's engine `src/gpu/bh_gpu.zig` (meter → trace → footprint → shade, the kernels in `opus_black_hole.metal`) with sRGB 8-bit output. The theme's `init()` skips its CPU trace, as it does in the app. Time advances as the app's frame pacer (`src/desktop/frame_rate.zig`) advances it: `step(0.008)` per 30 Hz logic tick, spread over the frames, so `step(0.002)` per frame at 120 FPS. A held inclination is traced once and shaded every frame, as in the app. **The earlier hero (30 FPS, October 16) ran Cygnus A's turbulence too fast:** its driver stepped the theme 1/30 s per frame instead of 0.008 per tick, about 4.2× the wallpaper's speed. This render steps it exactly as the app does. It also includes the shear-aware turbulence filter that keeps the disk from shimmering at 120 FPS.

The only departure from the live wallpaper is the camera move. The GPU trace takes the inclination as a runtime parameter (`TraceParams.incl/sin_i/cos_i`). The clip holds 72° for 0.25 s, eases (smoothstep) to 88° over 4.5 s, then holds 88°. 88° is the theme's own `INCL`: the last 3 s are exactly what the wallpaper shows. Every frame is a fresh full geodesic trace at its inclination, with no interpolation between frames. Exposure is the engine's own meter at each frame's inclination, smoothed over time (Gaussian, σ = 32 frames at 120 FPS, in log space) so its 1/8-stop histogram bins don't flicker. On the held 88° frames it equals the live meter.

## Night_Tide and the other Metal themes

A driver (`src/offline_render_metal.zig`, committed since; it also drives `tools/social`) compiles each theme through `src/gpu/metal_theme.zig`, the app's path (prelude + theme, `argus_init`/`argus_step`/`argus_draw`), into an 8-bit RGBA texture, paced like the app at 120 FPS: `f.time` advances 1/120 s every frame and `argus_step` runs only on the 30 Hz logic ticks with dt = 1/30 s (`Theme.encodeTimes`). So all motion at 120 FPS is the theme's own, never interpolated, and simulations run at their real speed. Warm-ups before the shot: 11 s for Night_Tide (to catch a breaking wave), 40 s for Ebru_Studio (so the marbling has developed), 8 s for the rest.

`f.frame` is the 30 Hz tick index in both kernels, as in the app since the frame-tick fix (`metal_theme.FrameCounter`): it moves only on frames that step, and draws in between reuse it. So Lizard_Island's reef build, Tutorial_Reef's seeding and Night_Tide's sparkle grain run exactly as they do at 30 FPS.

## Popover and Settings

These are the app's own drawing of the popover, not a screen capture. The `--snapshot-popover DIR` dev aid renders each popover face to PNG and quits; no desktop, Dock or other app is in the frame. They were taken from a build of this commit, run with `--offscreen` from its own folder (windows far off-screen, no menu-bar item), so the owner's live Argus and its config were untouched. That folder held a clean `.argus_spaces.conf` with the seven shipped themes on seven Spaces, Cygnus_A on the active one. Two local changes for the run, not committed: the snapshot fired at 15 s, with the popover marked open at 5 s, the way a user opening the menu would; and the active Space counted as on screen, which off-screen windows otherwise never are. The themes that need simulation time (Lizard_Island builds its reef, Tutorial_Reef grows) sat on the active Space's warm neighbours.

## Encoding

Frames were piped as raw RGBA into FFV1 lossless masters (kept out of git). They were converted to YUV with the BT.709 matrix (the earlier encodes used ffmpeg's default BT.601 matrix under a BT.709 tag, a slight colour shift) and encoded with two-pass `libx264 -preset slow -profile:v high` to fit under GitHub's 10 MB inline-video limit, and remuxed into `.mov` with the playback-intent flag, tagged BT.709, with `+faststart`. The GIF uses a 192-colour palette (`palettegen`/`paletteuse`, sierra2_4a dither). The PNGs are truecolor at zlib level 9.

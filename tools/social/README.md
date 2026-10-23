# Social videos

Vertical (9:16) clips of Argus themes for TikTok, Reels and Shorts. They use the "POV: my Mac wallpaper" framing: a Mac screen in the middle of the frame, with a hook above it and a caption below.

```
make social ZIG=path/to/zig-0.17.0 \
  THEMES=Cygnus_A,Night_Tide,Roulette_Chrome,Phosphor_Terminal \
  HOOK="wdym my wallpaper has general relativity|POV: every desktop on your Mac is a different universe" \
  NAME="pov-general-relativity|pov-different-universe"
```

Each hook variant (separated by `|`) gets its own video. Every variant uses the same theme renders, so an extra variant costs only its encode. The run takes about 30 s on an M3. Output goes to `~/Desktop/argus-clips/social/` (set `SOCIAL_OUT=` to change it):

| File | What it is |
|---|---|
| `NAME.mp4` | 1080×1920, 60 FPS, H.264 High@4.2, CRF 16 (VBV cap 24 Mb/s), BT.709 tagged, `+faststart`. It has a silent 48 kHz stereo AAC track (the sound slot) and one chapter per theme plus one for the end card |
| `NAME_1s.png`, `_4s.png`, `_10s.png` | Stills for review, decoded from the MP4 |
| `NAME.beats.json` | The swipe beats for the sound pass: start, peak velocity and settle time of each Space swipe, and when the end card fades in |
| `NAME.labels.txt` | The same beats as an Audacity label track (File → Import → Labels) |

Other options (run `python3 tools/social/social.py --help` for the full list):

- `SOUND=track.m4a` lays audio under the video instead of silence. It is padded or cut to the video's length.
- `SEG=` sets the seconds per theme (default 3). The end card always takes the last second.
- `CLOCK=2026-10-23T21:41:00` sets the menu-bar clock.
- `--guides` also writes a still with the platforms' UI zones washed red.
- `--keep-work` keeps the intermediates.

## Timeline (4 themes, the defaults)

| Time | What happens |
|---|---|
| 0–3 s | Theme 1 |
| 3, 6, 9 s | A Space swipe to the next theme. The new Space slides in from the right with an 18 px dark gap, on a critically damped spring from rest: 99 % of the way at 0.5 s, landing at 0.6 s. The eye glyph's iris moves to the new Space's arc halfway through, and the caption crossfades |
| 10.75–11 s | Fade to the end card: the eye glyph, the Argus wordmark, "free & open source · macOS" and the repo URL |
| 11–12 s | End card |

## Where the pixels come from

- **Themes.** Each theme is rendered offline by its own code on the app's GPU path, at 1920×1080, and then scaled to the 976×549 display with Lanczos. Nothing is screen-recorded.
  - Metal themes use `src/offline_render_metal.zig`: `metal_theme`, paced like the app at 60 FPS, with `argus_step` on the 30 Hz ticks only.
  - Kerr-disk themes (Cygnus_A) use `src/offline_render_bh.zig`: the `bh_gpu` engine at the theme's own inclination, traced once and shaded every frame.
  - These are the drivers behind the launch media (`docs/media/README.md`).
  - Each theme first runs through its warm-up (`themes.json`): the time the app would already have been running.
  - Theme clocks (Phosphor_Terminal's date line) are pinned to the menu-bar clock, so the video always renders the same.
  - Phosphor_Terminal shows `argus_stats.synthetic`, never this Mac's readings. In the app it shows live readings.
  - CPU-only Zig themes have no offline video renderer yet, and the tool refuses them.
- **The Mac.** The Mac is drawn here, not captured:
  - a lid with a glass bezel, a notch and a camera, and the base's front lip;
  - a menu bar with Finder's menus, the Argus eye glyph and the clock. The eye glyph is drawn by the app's own rasteriser (`src/desktop/status_glyph.zig`, through `eye_glyph.zig`), with one arc per theme. Type is SF, at about 1.5× the true menu-bar size so it reads on a phone. There is no Apple logo, because Apple's trademark rules don't allow it in promotion;
  - no desktop icons, windows or file names.
- **Type.** Helvetica Bold, white on black, as on the social card (`docs/media/social-card.png`). The second lines are grey-blue, as on the card. The hook is set as large as fits in three lines.

## Safe zones

Text stays below y = 210, left of x = 924 and above y = 1536 (the bottom 20 %). This keeps it clear of the platforms' top tabs, the right-hand buttons, and the caption and music strip. The tool refuses a hook or caption that doesn't fit. The screen's right edge does run under the right-hand buttons.

## Approximations (chosen, not measured)

- The swipe's curve, its 0.6 s length and the gap between Spaces are close to macOS's, but they were not measured against a recording.
- The menu bar stays still while the Spaces slide under it, with a light dark tint and no blur.

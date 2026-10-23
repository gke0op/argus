# Social videos

Vertical (9:16) clips of Argus themes on a Mac screen, for TikTok, Reels and Shorts. They use the "POV: my Mac wallpaper" framing.

```
# pov: several themes, one per Space, with Space swipes between them
make social ZIG=path/to/zig-0.17.0 THEMES=Cygnus_A,Night_Tide,Roulette_Chrome,Phosphor_Terminal \
  HOOK="POV: every desktop on your Mac is a different universe" NAME=pov-different-universe

# zoom: one theme, the camera pushes in from the whole MacBook until the theme fills the frame
make social ZIG=path/to/zig-0.17.0 FORMAT=zoom THEMES=Cygnus_A \
  HOOK="wdym my wallpaper has general relativity" NAME=pov-general-relativity
```

To render several hook variants in one run, separate them with `|` in `HOOK` and `NAME`. Every variant uses the same theme render. A pov run takes about 25 s on an M3; a zoom run takes about 70 s.

Output goes to `~/Desktop/argus-clips/social/` (set `SOCIAL_OUT=` to change it):

| File | What it is |
|---|---|
| `NAME.mp4` | 1080×1920, 60 FPS, 12 s by default. H.264 High@4.2, CRF 16 (VBV cap 24 Mb/s), tagged BT.709, `+faststart`. It has a silent 48 kHz stereo AAC track (the sound slot) and chapters |
| `NAME_1s.png`, `_6s.png`, `_11s.png` | Stills for review, decoded from the MP4 |
| `NAME.beats.json` | The beats for the sound pass. pov: the start, peak velocity and settle time of each Space swipe. zoom: when the hook fades and when the zoom runs. Both: when the end card fades in |
| `NAME.labels.txt` | The same beats as an Audacity label track |

Other options (run `python3 tools/social/social.py --help` for the full list):

- `SOUND=track.m4a` lays audio under the video instead of silence.
- `SEG=` sets seconds per theme in pov.
- `CLOCK=2026-10-23T21:41:00` sets the menu-bar clock.
- `--zoom-start`, `--zoom-end` and `--fill` set the zoom's timing and how much of the display's height the final frame shows.
- `--guides` also writes a still with the platforms' UI zones washed red.
- `--keep-work` keeps the intermediates.

## Timelines (defaults)

**pov** (4 themes):

| Time | What happens |
|---|---|
| 0–3 s | Theme 1 |
| 3, 6, 9 s | A Space swipe to the next theme. The new Space slides in from the right with an 18 px gap, on a critically damped spring: 99 % of the way at 0.5 s, landing at 0.6 s. The eye glyph's iris moves to the new Space halfway through, and the caption crossfades |
| 10.75–11 s | Fade to the end card |
| 11–12 s | End card |

**zoom**:

| Time | What happens |
|---|---|
| 0–1.6 s | The whole MacBook with the hook above it |
| 1.6–2.2 s | The hook fades out as the zoom begins |
| 1.8–9 s | The camera pushes in (smootherstep, constant speed in log scale) on the theme's focus point (`themes.json`; for Cygnus_A, the shadow's centre) until the frame's height is 92 % of the display's. No caption |
| 9–10.75 s | Hold at full zoom |
| 10.75–11 s | Fade to the end card |
| 11–12 s | End card |

The zoom renders the theme once, at the size full zoom needs. For Cygnus_A that is 3216×2089, or 1.001 theme pixels per output pixel at the end, and every frame is cut from it. The Mac is drawn at the same scale. So no frame is ever upscaled, and the tool refuses a setup that would need it. The theme render streams straight into the encoder, with no intermediate files.

## The Mac (`DEVICES` in social.py)

The model is the **14-inch MacBook Pro (M3, Mac15,3)**, the machine Argus is developed on.

**Measured on it with AppKit and CoreGraphics:**
- 1512×982 pt at 2× (3024×1964 px), so the display is 16:10.4.
- The menu bar is 33 pt.
- `NSScreen.bezelPath`, the display's own visible outline. It gives the rounded top corners, about 37 pt along each edge as continuous curves, and the square bottom corners. It also gives the notch, 185.3×32.0 pt with rounded lower corners. The model draws this path as-is.

**From Apple's published figures:**
- 254 ppi, which gives a 302.4×196.4 mm active area.
- The body is 312.6×221.2×15.5 mm. So the side bezel is 5.1 mm.

**Assumed (no published figure):**
- The top bezel equals the side bezel.
- The lid spans the body's depth, so the bottom bezel (the chin and hinge) is 19.7 mm.
- The base's front face is 10.5 mm.
- The lid's corner is concentric with the display's (12.5 mm).
- A 0.9 mm aluminium edge shows around the glass.

Every theme renders at the display's aspect (1920×1247 for pov), so nothing is letterboxed. The menu bar shows Finder's menus, the Argus eye glyph and the clock:
- The eye glyph is drawn by the app's own rasteriser (`src/desktop/status_glyph.zig`, via `eye_glyph.zig`).
- The type and the glyph are 1.4× their true size, so they read on a phone.
- There is no Apple logo and no "MacBook Pro" chin label, because Apple's trademark rules don't allow them in promotion.
- There are no desktop icons, windows or file names.

The model is a front view with no perspective.

## Where the theme pixels come from

Each theme is rendered offline by its own code on the app's GPU path: `src/offline_render_metal.zig` for Metal themes, and `src/offline_render_bh.zig` for Kerr-disk themes such as Cygnus_A. These are the launch-media drivers (`docs/media/README.md`). Frames are paced as the app paces them at 60 FPS, after each theme's warm-up in `themes.json`. Nothing is screen-recorded.

Theme clocks are pinned to the menu-bar clock. Phosphor_Terminal shows `argus_stats.synthetic` (public process names), never this Mac's readings. CPU-only Zig themes have no offline video renderer yet, and the tool refuses them.

## Type and safe zones

Helvetica Bold, white on black, as on the social card. The grey-blue second lines are as on the card too. The hook is set as large as fits in three lines.

Text stays below y = 210, left of x = 924 and above y = 1536 (the bottom 20 %). The tool refuses a hook or caption that doesn't fit. The screen's right edge does run under the right-hand buttons.

## Approximations (chosen, not measured)

- The swipe's curve, its length and the gap between Spaces are close to macOS's, but they were not measured against a recording.
- The menu bar stays still while the Spaces slide under it, with a light dark tint and no blur.

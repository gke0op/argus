# Social videos

Vertical (9:16) clips of Argus themes on a Mac screen, for TikTok, Reels and Shorts. They use the "POV: my Mac wallpaper" framing.

```
# pov: several themes, one per Space, with Space swipes between them
make social ZIG=path/to/zig-0.17.0 THEMES=Cygnus_A,Night_Tide,Roulette_Chrome,Phosphor_Terminal \
  HOOK="POV: every desktop on your Mac is a different universe" NAME=pov-different-universe

# orbit: a Kerr-disk theme on the MacBook, the Mac fades, then a probe tours the black hole
make social ZIG=path/to/zig-0.17.0 FORMAT=orbit THEMES=Cygnus_A \
  HOOK="wdym my wallpaper has general relativity" NAME=pov-general-relativity STILLS=1,2.6,9.55,16.9,18.6,19.5

# the same path as a labelled 8-still strip, for approval before the full render
ZIG=path/to/zig-0.17.0 python3 -I tools/social/social.py --format orbit --themes Cygnus_A --hook x --name tour --strip 8
```

To render several hook variants in one run, separate them with `|` in `HOOK` and `NAME`. Every variant uses the same theme render. A pov run takes about 25 s on an M3. An orbit run takes about 15–20 min, because every frame of the camera move is a fresh trace.

Output goes to `~/Desktop/argus-clips/social/` (set `SOCIAL_OUT=` to change it):

| File | What it is |
|---|---|
| `NAME.mp4` | 1080×1920, 60 FPS, 12 s by default (orbit: 20 s). H.264 High@4.2, CRF 16 (VBV cap 24 Mb/s), tagged BT.709, `+faststart`. It has a silent 48 kHz stereo AAC track (the sound slot) and chapters |
| `NAME_1s.png`, `_6s.png`, `_11s.png` | Stills for review, decoded from the MP4 (default times; `STILLS=` sets others) |
| `NAME.beats.json` | The beats for the sound pass. pov: the start, peak velocity and settle time of each Space swipe. orbit: the Mac's fade, the tour, its pass over the top, the dip and the moment it crosses the disk's plane. Both: when the end card fades in |
| `NAME.labels.txt` | The same beats as an Audacity label track |

Other options (run `python3 tools/social/social.py --help` for the full list):

- `SOUND=track.m4a` lays audio under the video instead of silence.
- `SEG=` sets seconds per theme in pov.
- `CLOCK=2026-10-23T21:41:00` sets the menu-bar clock.
- `--mac-fade`, `--move-start`/`--move-end`, `--theta-min`, `--az-end`, `--roll-end-extra`, `--span-top`/`--span-end` and `--dip-to`/`--dip-start`/`--dip-end` set the orbit's timing and path.
- `--strip N` renders only N labelled stills along the path.
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

**orbit** (Cygnus_A, 20 s): a probe tours the black hole.

| Time | What happens |
|---|---|
| 0–2 s | The hook, and Cygnus A on the MacBook's screen, exactly as the wallpaper shows it |
| 2–3.2 s | The Mac and the hook fade out. Only the black hole is left, and its disk now runs past where the screen's edges were |
| 2.2–16.9 s | **The tour.** At a constant distance (r = 1000 M) the probe rises from the theme's 88° over the top of the hole to 20° from the pole, at 9.55 s. That is the near face-on "eye": the shadow inside a round glowing disk, with the lens set so the glow fits the frame's width. It comes back down to 88° on the far side, 180° of azimuth around. The roll turns 270° in all: the 180° that flying over the top turns the view (the far side arrives upside down, with the lensed arc and the bright, approaching side swapped), plus 90° so the disk ends along the frame's long side. The lens eases 1.0× (the screen's view) → 1.13× (over the top) → 1.8× (edge-on, the disk along the full height). Smootherstep throughout, and no words |
| 16.6–18.6 s | **The dip.** Still edge-on and still vertical, the probe drops through the disk's plane to 96°, just below it. At 90° the infinitely thin disk vanishes and leaves the bare lensed ring; below the plane the disk reopens from underneath |
| 18.75–19 s | Fade to the end card |
| 19–20 s | End card |

The whole video is **one render** of the theme, at 1080×1920 and 60 FPS:
- **Seamless handoff.** During the opening, the screen shows exactly its part of that render. The camera then is the wallpaper's own: the theme's inclination, no roll, and the theme's frame height (2 HALF_H) across the display's height, centred on the screen. So the first frame of the move is the on-screen view by construction.
- **A real camera move.** The camera moves in the simulation through `src/offline_render_bh.zig --camera`, one "polar span roll azimuth" line per frame. Roll and azimuth are the engine's `TraceParams.roll`/`phi0`, compiled in only for the offline renderer (`BH_CAMERA_MOVES`). Every frame is traced afresh, natively at 1080×1920. Nothing is cropped or upscaled.
- **Physically consistent.** The hole, its spin, the disk and its turbulence are the theme's own; only the camera moves.
- **Exposure.** It holds the wallpaper's own metered value (9.90) for the whole tour (`--hold-exposure`), like a camera keeping its setting. The theme's meter rule would raise exposure face-on to 11.8 and wash the disk out to white.

**Why 20° and not over the pole.** Rays from a camera near the spin axis have tiny angular momentum, and the integrator resolves their turn near the axis in tiny steps. Measured per 1080×1920 frame:
- 0.6–0.7 s at 60–20°;
- 26 s at 15°;
- 67 s at 10°;
- 4 min at 2°;
- no finish at 0.5°.

The pole itself (θ = 0) is singular in the ray setup. A tour 20° from the pole costs nothing extra and looks the same to the eye.

"From below" needs a crossing of the disk's plane, because a path over the top stays above the disk the whole way. That is the dip.

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

In pov, every theme renders at the display's aspect (1920×1247), so nothing is letterboxed. The menu bar shows Finder's menus, the Argus eye glyph and the clock:
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

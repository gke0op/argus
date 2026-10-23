#!/usr/bin/env python3
"""
tools/social/social.py -- vertical social videos of Argus themes ("POV: my Mac wallpaper").

Each theme is rendered offline by its own code on the app's GPU path (src/offline_render_metal.zig
for Metal themes, src/offline_render_bh.zig for Kerr-disk Zig themes such as Cygnus_A), paced as
the app paces it at the output frame rate, at the Mac's own display aspect. Nothing is
screen-recorded. The Mac around it is drawn here from a measured model (DEVICES): the lid, bezels
and base to the chassis dimensions, the display's outline (rounded top corners, the notch) as
macOS itself reports it, and a minimal menu bar (Finder's menus, the Argus eye glyph drawn by the
app's own rasteriser, the clock). Above the screen a hook, below it a caption, then an end card.

Formats:
  pov   several themes, one per Space, with macOS Space swipes between them and a caption each.
  orbit one Kerr-disk theme (Cygnus_A): the theme on the MacBook's screen, the Mac fades away, then
        the camera moves around the black hole in the theme's own simulation (inclination and
        image-plane scale; same hole, spin and disk), every frame traced natively at 1080x1920.

Output: H.264 1080x1920 60 FPS MP4 with a silent stereo track (the sound slot) or --sound,
chapters, a beats sidecar (JSON and an Audacity label track) and stills.

  python3 -I tools/social/social.py --themes Cygnus_A,Night_Tide,Roulette_Chrome,Phosphor_Terminal \
      --hook "POV: every desktop on your Mac is a different universe"
  python3 -I tools/social/social.py --format orbit --themes Cygnus_A \
      --hook "wdym my wallpaper has general relativity"

The themes are rendered once per run and shared by every --hook; intermediates go to a work
folder next to the output and are deleted at the end (--keep-work keeps them). See README.md.
"""
import argparse, datetime, json, math, os, re, shutil, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "social")
FFMPEG = shutil.which("ffmpeg") or "ffmpeg"

HELVETICA = "/System/Library/Fonts/Helvetica.ttc"  # index 0 Regular, 1 Bold
SF = "/System/Library/Fonts/SFNS.ttf"              # the menu bar's font (variable)

WHITE = (255, 255, 255)
GREY = (154, 163, 181)  # the social card's tagline grey-blue
GLASS = (8, 8, 9)
EDGE_RGB = (84, 86, 91)

# ---------------------------------------------------------------------------- the Mac
#
# 14-inch MacBook Pro (M3, Mac15,3), the machine Argus is developed on. Measured on it
# (AppKit/CoreGraphics, 2026-10-23): 1512 x 982 pt at 2x = 3024 x 1964 px; the menu bar 33 pt
# (frame top minus visibleFrame top); NSScreen.bezelPath, the display's visible outline, below
# (its 25 elements, y up as AppKit gives it). Apple's published figures: 254 ppi (-> a 302.4 x
# 196.4 mm active area), body 312.6 x 221.2 x 15.5 mm. Derived: side bezel (312.6 - 302.4) / 2 =
# 5.1 mm. Assumed (no published figure): top bezel = side bezel; the lid spans the body's depth,
# so the bottom bezel (chin and hinge) is 221.2 - 196.4 - 5.1 = 19.7 mm; the base's front face
# 10.5 mm of the 15.5 mm closed height; the lid's corner concentric with the display's (12.5 mm);
# a 0.9 mm aluminium edge seen around the glass. No "MacBook Pro" chin label, no Apple logo.
MBP14_BEZEL_PATH = [  # ("M"|"L", (x, y)) or ("C", c1, c2, end), AppKit points, y up
    ("M", (0.076, 944.871)),
    ("C", (0.076, 947.816), (0.0, 958.928), (0.646, 964.331)),
    ("C", (1.321, 969.957), (2.964, 973.459), (5.753, 976.248)),
    ("C", (8.542, 979.037), (12.044, 980.681), (17.669, 981.354)),
    ("C", (23.072, 982.0), (34.186, 981.924), (37.129, 981.924)),
    ("L", (657.700, 981.924)),
    ("C", (662.995, 981.924), (664.523, 980.396), (664.523, 975.101)),
    ("L", (664.523, 964.336)),
    ("C", (664.523, 959.771), (664.323, 956.123), (667.546, 952.900)),
    ("C", (670.769, 949.677), (674.417, 949.879), (678.982, 949.879)),
    ("L", (835.330, 949.879)),
    ("C", (839.896, 949.879), (843.544, 949.677), (846.766, 952.900)),
    ("C", (849.989, 956.123), (849.787, 959.771), (849.787, 964.336)),
    ("L", (849.787, 975.101)),
    ("C", (849.787, 980.396), (851.316, 981.924), (856.612, 981.924)),
    ("L", (1477.181, 981.924)),
    ("C", (1480.126, 981.924), (1491.238, 982.0), (1496.641, 981.354)),
    ("C", (1502.269, 980.681), (1505.770, 979.037), (1508.559, 976.248)),
    ("C", (1511.348, 973.459), (1512.991, 969.957), (1513.664, 964.331)),
    ("C", (1514.312, 958.928), (1514.234, 947.816), (1514.234, 944.871)),
    ("L", (1514.234, -1.478)),
    ("L", (0.076, -1.478)),
]

DEVICES = {
    "mbp14": dict(
        label="14-inch MacBook Pro (M3)",
        pt=(1512, 982), menubar_pt=33, bezel_path=MBP14_BEZEL_PATH,
        active_mm=(302.4, 196.4), body_w_mm=312.6,
        bezel_mm=dict(side=5.1, top=5.1, bottom=19.7), base_mm=10.5, lid_r_mm=12.5, edge_mm=0.9,
        base_r_mm=3.0, scoop_mm=(45.0, 2.0),
    ),
}

# The canvas and its safe zones (TikTok / Reels / Shorts UI): text stays left of SAFE_RIGHT, below
# SAFE_TOP and above SAFE_BOTTOM (the bottom 20 %). The screen itself may sit under the right-hand
# buttons. The display is DW px wide; everything else on the Mac follows from the device's mm.
CANVAS = dict(W=1080, H=1920, DW=984, DY=600, MARGIN=44, SAFE_TOP=210, SAFE_RIGHT=924, SAFE_BOTTOM=1536,
              HOOK_GAP=56, CAP_GAP=46)
MENU_TYPE = 1.4      # menu-bar type and glyph at 1.4x their true size, to read on a phone

SPRING_W = 13.3      # critically damped spring, 1/s: 99 % of the way at 0.5 s
GAP_PX = 18          # dark gap between two Spaces while they slide


def die(msg):
    sys.exit(f"social: {msg}")


def run(cmd, **kw):
    r = subprocess.run(cmd, **kw)
    if r.returncode != 0:
        die(f"command failed ({r.returncode}): {' '.join(cmd[:6])} ...")
    return r


def zig_path():
    tc = os.path.join(ROOT, ".toolchain", "zig")
    z = os.environ.get("ZIG") or (tc if os.access(tc, os.X_OK) else shutil.which("zig"))
    if not z:
        die("no zig: set ZIG to a Zig 0.17.0 binary (`make zig` installs one)")
    v = subprocess.run([z, "version"], capture_output=True, text=True).stdout.strip()
    if not v.startswith("0.17"):
        die(f"{z} is Zig {v}; the renderers need 0.17.0 (set ZIG=...)")
    return z


def font(path, size, index=0, variation=None):
    f = ImageFont.truetype(path, size, index=index)
    if variation:
        f.set_variation_by_name(variation)
    return f


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def smootherstep(x):
    t = min(max(x, 0.0), 1.0)
    return t * t * t * (t * (6 * t - 15) + 10)


def spring(t, dur):
    """Space-swipe position 0..1: a critically damped spring from rest, normalised to land at dur."""
    if t <= 0:
        return 0.0
    if t >= dur:
        return 1.0
    g = lambda s: 1 - (1 + SPRING_W * s) * math.exp(-SPRING_W * s)
    return g(t) / g(dur)


# ---------------------------------------------------------------------------- geometry

def geometry(dev, dy=None):
    """Canvas-pixel geometry of the Mac: the display rect (integer unless dy is given), the lid,
    the base."""
    C = CANVAS
    pw, ph = dev["pt"]
    DW = C["DW"]
    DH = round(DW * ph / pw)
    mm = DW / dev["active_mm"][0]  # px per mm
    lid_w = dev["body_w_mm"] * mm
    dx = round((C["W"] - DW) / 2)
    dy = C["DY"] if dy is None else dy
    b = dev["bezel_mm"]
    lx0 = dx + DW / 2 - lid_w / 2
    g = dict(DW=DW, DH=DH, dx=dx, dy=dy, mm=mm, ptx=DW / pw, pty=DH / ph,
             lid=(lx0, dy - b["top"] * mm, lx0 + lid_w, dy + DH + b["bottom"] * mm),
             lid_r=dev["lid_r_mm"] * mm, edge=dev["edge_mm"] * mm)
    g["base"] = (g["lid"][0], g["lid"][3], g["lid"][2], g["lid"][3] + dev["base_mm"] * mm)
    return g


def bezel_polygon(dev, g, steps=32):
    """The display's visible outline (bezelPath) in canvas px, y down, flattened to a polygon. The
    path spans 0.08..1514.23 x -1.48..982 pt; it is fitted to the display rect."""
    pts = []
    path = dev["bezel_path"]
    xs = [p[0] for el in path for p in el[1:]]
    ys = [p[1] for el in path for p in el[1:]]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    to = lambda p: (g["dx"] + (p[0] - x0) / (x1 - x0) * g["DW"], g["dy"] + (y1 - p[1]) / (y1 - y0) * g["DH"])
    cur = None
    for el in path:
        if el[0] in ("M", "L"):
            cur = el[1]
            pts.append(to(cur))
        else:
            c1, c2, e = el[1], el[2], el[3]
            for k in range(1, steps + 1):
                t = k / steps
                u = 1 - t
                p = tuple(u ** 3 * cur[i] + 3 * u * u * t * c1[i] + 3 * u * t * t * c2[i] + t ** 3 * e[i] for i in range(2))
                pts.append(to(p))
            cur = e
    return pts


class Raster:
    """Draws shapes given in canvas px into a region of the canvas at K pixels per canvas px,
    anti-aliased by drawing masks at ss x and downsampling."""

    def __init__(self, region, K, ss):
        self.ox, self.oy, ox1, oy1 = region
        self.K, self.ss = K, ss
        self.size = (int(math.ceil((ox1 - self.ox) * K)), int(math.ceil((oy1 - self.oy) * K)))
        self.img = Image.new("RGBA", self.size, (0, 0, 0, 0))

    def p(self, x, y, s=None):
        s = self.ss if s is None else s
        return ((x - self.ox) * self.K * s, (y - self.oy) * self.K * s)

    def mask(self, draw_fn):
        w, h = self.size
        m = Image.new("L", (w * self.ss, h * self.ss), 0)
        draw_fn(ImageDraw.Draw(m))
        return m.resize(self.size, Image.BOX) if self.ss > 1 else m

    def rrect(self, box, r, corners=(True, True, True, True)):
        x0, y0 = self.p(box[0], box[1])
        x1, y1 = self.p(box[2], box[3])
        return self.mask(lambda d: d.rounded_rectangle([x0, y0, x1, y1], radius=r * self.K * self.ss, fill=255, corners=corners))

    def poly(self, pts):
        return self.mask(lambda d: d.polygon([self.p(x, y) for x, y in pts], fill=255))

    def fill(self, rgb, mask):
        self.img.paste(Image.new("RGBA", self.size, rgb + (255,)), (0, 0), mask)


def draw_device(dev, g, region, K, ss):
    """The Mac as an RGBA layer of `region` at K px per canvas px: the lid's aluminium edge, the
    glass (with the display's outline cut out: rounded top corners and the notch stay glass), the
    hinge line and the base's front face with its opening scoop."""
    R = Raster(region, K, ss)
    lx0, ly0, lx1, ly1 = g["lid"]
    e, mm = g["edge"], g["mm"]
    hole = R.poly(bezel_polygon(dev, g))
    keep = 1 - np.asarray(hole, np.float32) / 255
    cut = lambda m: Image.fromarray((np.asarray(m, np.float32) * keep + 0.5).astype(np.uint8), "L")
    R.fill(EDGE_RGB, cut(R.rrect(g["lid"], g["lid_r"], corners=(True, True, False, False))))
    R.fill(GLASS, cut(R.rrect((lx0 + e, ly0 + e, lx1 - e, ly1), g["lid_r"] - e, corners=(True, True, False, False))))
    # The base's front face: a silver gradient, rounded below.
    bx0, by0, bx1, by1 = g["base"]
    face = R.rrect((bx0, by0 - 20, bx1, by1), dev["base_r_mm"] * mm)
    top_px, bot_px = R.p(0, by0, 1)[1], R.p(0, by1, 1)[1]
    ys = np.arange(R.size[1], dtype=np.float32)[:, None]
    t = np.clip((ys - top_px) / max(bot_px - top_px, 1), 0, 1)
    grad = np.zeros((R.size[1], R.size[0], 4), np.uint8)
    for i, (c0, c1) in enumerate(zip((214, 215, 218), (118, 120, 125))):
        grad[..., i] = (c0 + (c1 - c0) * t).astype(np.uint8)
    grad[..., 3] = 255
    clip = R.mask(lambda d: d.rectangle([*R.p(bx0 - 1, by0), *R.p(bx1 + 1, by1 + 1)], fill=255))
    m = Image.fromarray(np.minimum(np.asarray(face), np.asarray(clip)), "L")
    R.img.paste(Image.fromarray(grad, "RGBA"), (0, 0), m)
    R.fill((24, 24, 26), R.mask(lambda d: d.rectangle([*R.p(lx0 + e, by0), *R.p(lx1 - e, by0 + 0.6 * mm)], fill=255)))
    sw, sh = dev["scoop_mm"][0] * mm, dev["scoop_mm"][1] * mm
    cx = (bx0 + bx1) / 2
    scoop = R.mask(lambda d: d.ellipse([*R.p(cx - sw / 2, by0 - sh), *R.p(cx + sw / 2, by0 + sh)], fill=255))
    R.fill((70, 72, 76), Image.fromarray(np.minimum(np.asarray(scoop), np.asarray(clip)), "L"))
    return R.img


def eye_glyph(zig, px, n, cur, work):
    out = os.path.join(work, f"eye_{px}_{n}_{cur}.pgm")
    if not os.path.exists(out):
        with open(out, "wb") as fh:
            run([zig, "run", "-O", "ReleaseFast", "--dep", "status_glyph", "-Mroot=tools/social/eye_glyph.zig",
                 "-Mstatus_glyph=src/desktop/status_glyph.zig", "--", str(px), str(n), str(cur)], cwd=ROOT, stdout=fh)
    return Image.open(out)


def menu_bar(dev, g, K, zig, n, cur, clock_text, work):
    """The menu bar as an RGBA layer of the display (DW x DH at K): a light dark tint, Finder's
    menus left of the notch, the eye glyph (iris on Space cur of n) and the clock at the right."""
    W, H = int(round(g["DW"] * K)), int(round(g["DH"] * K))
    mb = dev["menubar_pt"] * g["pty"] * K
    pt = g["ptx"] * K
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    tint = Image.new("RGBA", (W, int(math.ceil(mb))), (0, 0, 0, 46))
    im.paste(tint, (0, 0))
    size = 13 * pt * MENU_TYPE
    bold = font(SF, round(size), variation="Bold")
    reg = font(SF, round(size), variation="Medium")
    d = ImageDraw.Draw(im)
    cy = mb / 2
    x = 20 * pt
    d.text((x, cy), "Finder", font=bold, fill=(255, 255, 255, 245), anchor="lm")
    x += bold.getlength("Finder") + 16 * pt * MENU_TYPE
    for m in ["File", "Edit", "View", "Go", "Window", "Help"]:
        d.text((x, cy), m, font=reg, fill=(255, 255, 255, 240), anchor="lm")
        x += reg.getlength(m) + 14 * pt * MENU_TYPE
    notch_x0 = 664.5 * pt  # from the bezel path
    if x > notch_x0:
        die("menu bar: the menus run under the notch")
    cx = W - 12 * pt - reg.getlength(clock_text)
    d.text((cx, cy), clock_text, font=reg, fill=(255, 255, 255, 245), anchor="lm")
    gp = min(96, round(16 * pt * MENU_TYPE))
    gl = eye_glyph(zig, gp, n, cur, work)
    im.paste(Image.new("RGBA", gl.size, (255, 255, 255, 255)), (int(round(cx - 14 * pt * MENU_TYPE - gp)), int(round(cy - gp / 2))), gl)
    return im


# ---------------------------------------------------------------------------- type

def wrap(text, fnt, max_w):
    lines = []
    for para in text.split("\n"):
        cur = ""
        for word in para.split():
            trial = (cur + " " + word).strip()
            if fnt.getlength(trial) <= max_w or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = word
        lines.append(cur)
    return lines


def caption_layer(cfg, h):
    """A caption (name, then one line in grey) as float RGB of a full-width strip on black."""
    C = CANVAS
    im = Image.new("RGB", (C["W"], h), (0, 0, 0))
    d = ImageDraw.Draw(im)
    x = C["MARGIN"]
    fmax = C["SAFE_RIGHT"] - x
    fn = font(HELVETICA, 46, 1)
    fl = font(HELVETICA, 34, 0)
    name, line = cfg["name"], cfg.get("line", "")
    if fn.getlength(name) > fmax or (line and fl.getlength(line) > fmax):
        die(f"caption too wide for the safe zone: {name!r} / {line!r}")
    d.text((x, 0), name, font=fn, fill=WHITE, anchor="lt")
    if line:
        d.text((x, 62), line, font=fl, fill=GREY, anchor="lt")
    return np.asarray(im, np.float32)


def hook_layer(text, lid_top):
    """The hook: Helvetica Bold, white, left-aligned, as large as fits in three lines inside the
    safe zone, its block ending HOOK_GAP above the lid. Returns an RGBA canvas layer."""
    C = CANVAS
    x = C["MARGIN"]
    max_w = C["SAFE_RIGHT"] - x
    for size in range(96, 40, -2):
        f = font(HELVETICA, size, 1)
        lines = wrap(text, f, max_w)
        if len(lines) <= 3 and all(f.getlength(s) <= max_w for s in lines):
            break
    else:
        die(f"hook too long for three lines: {text!r}")
    lead = round(size * 1.08)
    top = int(lid_top - C["HOOK_GAP"]) - (lead * (len(lines) - 1) + size)
    if top < C["SAFE_TOP"]:
        die(f"hook too tall for the safe zone: {text!r}")
    im = Image.new("RGBA", (C["W"], C["H"]), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, s in enumerate(lines):
        d.text((x, top + i * lead), s, font=f, fill=WHITE + (255,), anchor="lt")
    print(f"  hook {size} px in {len(lines)} lines", flush=True)
    return im


def end_card(zig, n, work, line1, line2):
    """The end card: the eye glyph, the Argus wordmark, line1, and the URL in grey."""
    C = CANVAS
    im = Image.new("RGB", (C["W"], C["H"]), (0, 0, 0))
    d = ImageDraw.Draw(im)
    x = C["MARGIN"] + 20
    g = eye_glyph(zig, 96, n, 0, work)
    y = 640
    im.paste(Image.new("RGB", g.size, WHITE), (x - 6, y), g)
    y += 96 + 40
    d.text((x - 6, y), "Argus", font=font(HELVETICA, 168, 1), fill=WHITE, anchor="lt")
    y += 168 + 46
    f1 = font(HELVETICA, 50, 1)
    d.text((x, y), line1, font=f1, fill=WHITE, anchor="lt")
    y += 50 + 26
    f2 = font(HELVETICA, 42, 0)
    d.text((x, y), line2, font=f2, fill=GREY, anchor="lt")
    if x + max(f1.getlength(line1), f2.getlength(line2)) > C["SAFE_RIGHT"] or y + 42 > C["SAFE_BOTTOM"]:
        die("end card outside the safe zone")
    return np.asarray(im, np.float32)


def guides(img):
    """Red wash over the platforms' UI zones, for checking a still."""
    C = CANVAS
    a = np.asarray(img, np.float32).copy()
    red = np.array([255, 0, 0], np.float32)
    for x0, y0, x1, y1 in [(0, 0, C["W"], C["SAFE_TOP"]), (C["SAFE_RIGHT"], C["SAFE_TOP"], C["W"], C["SAFE_BOTTOM"]),
                           (0, C["SAFE_BOTTOM"], C["W"], C["H"])]:
        a[y0:y1, x0:x1] = a[y0:y1, x0:x1] * 0.65 + red * 0.35
    return Image.fromarray(a.astype(np.uint8))


# ---------------------------------------------------------------------------- theme renders

def theme_kind(theme):
    m = os.path.join(ROOT, "themes", theme + ".metal")
    z = os.path.join(ROOT, "themes", theme + ".zig")
    if os.path.exists(m):
        return "metal", m
    if os.path.exists(z):
        with open(z) as fh:
            head = fh.read(4096)
        if "@argus-engine: kerr-disk" in head:
            return "kerr", z
        die(f"{theme}: CPU Zig themes have no offline video renderer yet (Metal and Kerr-disk themes do)")
    die(f"{theme}: no themes/{theme}.metal or themes/{theme}.zig")


def renderer_cmd(zig, theme, cfg, size, frames, fps, wall):
    """The command that writes `frames` raw RGBA frames of `theme` at `size` after its warm-up.
    `wall` is the local time its first shown frame should carry (theme clocks)."""
    kind, path = theme_kind(theme)
    skip = int(round(cfg["warmup"] * fps))
    rel = os.path.relpath(path, ROOT)
    sz = f"{size[0]}x{size[1]}"
    if kind == "metal":
        start = wall - datetime.timedelta(seconds=skip / fps)
        return [zig, "run", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", "src/offline_render_metal.zig", "--",
                rel, "--size", sz, "--fps", str(fps), "--skip", str(skip), "--frames", str(frames),
                "--date", start.strftime("%Y-%m-%dT%H:%M:%SZ"), "--utc-offset", "0", "--seed", str(cfg.get("seed", "0x5EED"))]
    return [zig, "run", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", "--dep", "theme",
            "-Mroot=src/offline_render_bh.zig", "-O", "ReleaseFast", f"-Mtheme={rel}", "--",
            "--size", sz, "--fps", str(fps), "--skip", str(skip), "--frames", str(frames)]


def render_segment(cmd, size, fps, frames, out_path, log_path, dw, dh):
    """Runs a renderer and scales its frames to the display size into a lossless FFV1 file."""
    ff = [FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{size[0]}x{size[1]}", "-r", str(fps), "-i", "-",
          "-vf", f"scale={dw}:{dh}:flags=lanczos+accurate_rnd+full_chroma_int,format=gbrp", "-c:v", "ffv1", "-level", "3", out_path]
    with open(log_path, "ab") as log:
        p1 = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=log)
        p2 = subprocess.Popen(ff, stdin=p1.stdout)
        p1.stdout.close()
        r2 = p2.wait()
        r1 = p1.wait()
    if r1 != 0 or r2 != 0:
        die(f"render failed (renderer {r1}, ffmpeg {r2}); see {log_path}")
    got = int(subprocess.run([shutil.which("ffprobe") or "ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0",
                              "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", out_path],
                             capture_output=True, text=True).stdout.strip() or 0)
    if got != frames:
        die(f"{out_path}: expected {frames} frames, the render has {got}")


class Segment:
    """Reads one theme render's frames in order, as RGB arrays at the display size."""

    def __init__(self, path, dw, dh):
        self.path, self.dw, self.dh, self.p = path, dw, dh, None

    def read(self):
        if self.p is None:
            self.p = subprocess.Popen([FFMPEG, "-v", "error", "-i", self.path, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                                      stdout=subprocess.PIPE)
        n = self.dw * self.dh * 3
        b = self.p.stdout.read(n)
        if len(b) != n:
            die(f"{self.path}: ran out of frames")
        return np.frombuffer(b, np.uint8).reshape(self.dh, self.dw, 3)

    def close(self):
        if self.p:
            self.p.stdout.close()
            self.p.wait()
            self.p = None


# ---------------------------------------------------------------------------- output

def open_encoder(out_mp4, fps, F, sound, chapters, crf, work):
    meta = os.path.join(work, "chapters.txt")
    with open(meta, "w") as fh:
        fh.write(";FFMETADATA1\ntitle=Argus\n")
        for i, (f0, title) in enumerate(chapters):
            f1 = chapters[i + 1][0] if i + 1 < len(chapters) else F
            fh.write(f"[CHAPTER]\nTIMEBASE=1/{fps}\nSTART={f0}\nEND={f1}\ntitle={title}\n")
    audio = (["-i", sound] if sound else ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"])
    C = CANVAS
    return subprocess.Popen(
        [FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{C['W']}x{C['H']}", "-r", str(fps), "-i", "-",
         *audio, "-i", meta, "-map", "0:v", "-map", "1:a", "-map_metadata", "2", "-map_chapters", "2",
         "-vf", "scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,"
                "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv",
         "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level", "4.2", "-crf", str(crf),
         "-maxrate", "24M", "-bufsize", "48M", "-g", str(fps), "-bf", "2",
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-af", "apad", "-t", f"{F / fps:.6f}",
         "-movflags", "+faststart", out_mp4], stdin=subprocess.PIPE)


def finish(a, name, out_mp4, fps, F, hook, themes, beats, labels):
    with open(os.path.join(a.out, name + ".beats.json"), "w") as fh:
        json.dump(dict(video=name + ".mp4", format=a.format, fps=fps, duration=F / fps, hook=hook, themes=themes,
                       sound=os.path.basename(a.sound) if a.sound else "silent (slot)", beats=beats), fh, indent=2)
    with open(os.path.join(a.out, name + ".labels.txt"), "w") as fh:  # Audacity label track
        for t0, t1, text in labels:
            fh.write(f"{t0:.4f}\t{t1:.4f}\t{text}\n")
    stills = [float(x) for x in a.stills.split(",") if x.strip()]
    for s in stills:
        png = os.path.join(a.out, f"{name}_{s:g}s.png")
        run([FFMPEG, "-v", "error", "-y", "-i", out_mp4, "-vf", f"select=eq(n\\,{round(s * fps)})", "-frames:v", "1", png])
    if a.guides and stills:
        guides(Image.open(os.path.join(a.out, f"{name}_{stills[0]:g}s.png")).convert("RGB")).save(
            os.path.join(a.out, f"{name}_safezones.png"))
    print(f"wrote {out_mp4}", flush=True)


def slug(text):
    words = re.sub(r"[^a-z0-9 ]+", "", text.lower()).split()
    return "-".join(words[:7]) or "video"


# ---------------------------------------------------------------------------- pov: Space swipes

def make_pov(a, zig, dev, themes, cfgs, hooks, names, clock, clock_text, work):
    fps, n = a.fps, len(themes)
    total = n * a.seg
    end_at = total - a.end
    if total > 60:
        die("platforms cap these at 60 s")
    if a.swipe >= a.seg or end_at <= (n - 1) * a.seg + a.swipe:
        die("timeline: each theme needs its slot to outlast the swipe and the end card")
    F = round(total * fps)
    start_f = [round(k * a.seg * fps) for k in range(n)]
    swipe_f = round(a.swipe * fps)
    fade_f0, end_f = round((end_at - 0.25) * fps), round(end_at * fps)
    vis = [(start_f[k], (start_f[k + 1] + swipe_f) if k + 1 < n else end_f) for k in range(n)]  # [first, last)

    g = geometry(dev)
    DW, DH, dx, dy = g["DW"], g["DH"], g["dx"], g["dy"]
    pw, ph = dev["pt"]
    size = (1920, round(1920 * ph / pw))  # the theme at the Mac's aspect, scaled to the display

    log = os.path.join(work, "render.log")
    segs = []
    for k, (t, c) in enumerate(zip(themes, cfgs)):
        frames = vis[k][1] - vis[k][0]
        p = os.path.join(work, f"seg{k}_{t}.mkv")
        print(f"render {t}: {frames} frames at {size[0]}x{size[1]}, {fps} FPS, after {c['warmup']} s warm-up", flush=True)
        cmd = renderer_cmd(zig, t, c, size, frames, fps, clock + datetime.timedelta(seconds=vis[k][0] / fps))
        render_segment(cmd, size, fps, frames, p, log, DW, DH)
        segs.append(p)

    C = CANVAS
    device = draw_device(dev, g, (0, 0, C["W"], C["H"]), 1, 4)
    # Over the display: the menu bar (per active Space) under the glass's corners and notch.
    dcrop = device.crop((dx, dy, dx + DW, dy + DH))
    overlays = []
    for cur in range(n):
        ov = Image.alpha_composite(menu_bar(dev, g, 1, zig, n, cur, clock_text, work), dcrop)
        arr = np.asarray(ov, np.float32)
        al = arr[..., 3:4] / 255.0
        rows = int(np.nonzero(al.max(axis=(1, 2)) > 0)[0].max()) + 1
        overlays.append((rows, arr[:rows, :, :3] * al[:rows], al[:rows]))
    cap_y0 = int(math.ceil(g["base"][3])) + C["CAP_GAP"]
    cap_h = 120
    if cap_y0 + cap_h > C["SAFE_BOTTOM"]:
        die("caption below the safe zone")
    caps = [caption_layer(c, cap_h) for c in cfgs]
    endcard = end_card(zig, n, work, a.end_line1, a.end_line2)

    beats = []
    labels = []
    for k in range(1, n):
        s = start_f[k] / fps
        beats.append(dict(kind="swipe", from_theme=themes[k - 1], to_theme=themes[k], start=round(s, 4),
                          peak_velocity=round(s + 1 / SPRING_W, 4), settled=round(s + a.swipe, 4)))
        labels.append((s, s + a.swipe, f"swipe {themes[k - 1]} -> {themes[k]}"))
    beats.append(dict(kind="end_card", start=round(fade_f0 / fps, 4), full=round(end_at, 4)))
    labels.append((fade_f0 / fps, end_at, "end card"))
    chapters = [(start_f[k], cfgs[k]["name"]) for k in range(n)] + [(fade_f0, "End card")]

    for hi, hook in enumerate(hooks):
        name = names[hi] if names else f"pov-{slug(hook)}"
        print(f"compose {name}", flush=True)
        base = Image.new("RGBA", (C["W"], C["H"]), (0, 0, 0, 255))
        base = Image.alpha_composite(base, hook_layer(hook, g["lid"][1]))
        base = Image.alpha_composite(base, device)
        static = np.asarray(base.convert("RGB"), np.uint8)
        out_mp4 = os.path.join(a.out, name + ".mp4")
        enc = open_encoder(out_mp4, fps, F, a.sound, chapters, a.crf, work)
        readers = [Segment(p, DW, DH) for p in segs]
        try:
            for i in range(F):
                frame = static.copy()
                if i < end_f:
                    live = [k for k in range(n) if vis[k][0] <= i < vis[k][1]]
                    imgs = {k: readers[k].read() for k in live}
                    for k in range(n):
                        if readers[k].p and i >= vis[k][1] - 1:
                            readers[k].close()
                    k = max(live)
                    if len(live) == 2:  # a swipe from k-1 to k
                        p = spring((i - start_f[k]) / fps, a.swipe)
                        off = int(round(p * (DW + GAP_PX)))
                        disp = np.zeros((DH, DW, 3), np.uint8)
                        if off < DW:
                            disp[:, : DW - off] = imgs[k - 1][:, off:]
                        x1 = DW + GAP_PX - off
                        if x1 < DW:
                            disp[:, max(x1, 0):] = imgs[k][:, max(-x1, 0): DW - x1]
                        cur = k if p >= 0.5 else k - 1
                        t_in = (i - start_f[k]) / fps
                        wcap = {k - 1: 1 - smoothstep(0.0, 0.15, t_in), k: smoothstep(0.12, 0.35, t_in)}
                    else:
                        disp = imgs[k].copy()
                        cur, wcap = k, {k: 1.0}
                    rows, pm, al = overlays[cur]
                    disp[:rows] = np.clip(disp[:rows].astype(np.float32) * (1 - al) + pm + 0.5, 0, 255).astype(np.uint8)
                    frame[dy: dy + DH, dx: dx + DW] = disp
                    strip = sum(w * caps[kk] for kk, w in wcap.items() if w > 0)
                    if not np.isscalar(strip):
                        frame[cap_y0: cap_y0 + cap_h] = np.clip(strip + 0.5, 0, 255).astype(np.uint8)
                if i >= fade_f0:
                    e = smoothstep(fade_f0, end_f, i)
                    frame = np.clip(frame.astype(np.float32) * (1 - e) + endcard * e + 0.5, 0, 255).astype(np.uint8)
                enc.stdin.write(frame.tobytes())
        finally:
            for r in readers:
                r.close()
            enc.stdin.close()
        if enc.wait() != 0:
            die(f"{name}: encode failed")
        finish(a, name, out_mp4, fps, F, hook, themes, beats, labels)


# ---------------------------------------------------------------------------- orbit: the camera moves in the simulation

def tour_pose(a, u, span0, incl0):
    """The camera at tour progress u (0..1): (polar angle deg, span, roll deg, azimuth deg).
    The probe keeps its distance (r = 1000 M) and flies over the top of the black hole: its polar
    angle goes incl0 -> theta_min -> incl0 (sin^2 bump, lingering over the top) while its azimuth
    sweeps 0 -> az_end, so it ends on the far side. It never crosses the spin axis: near the pole
    the tracer's near-axis geodesics get very slow (0.7 s a 1080x1920 frame at 20 deg, 26 s at
    15 deg, minutes below 5 deg, and no finish at 0.5 deg). Roll: 90 deg spread over the tour, so the
    disk ends along the frame's long side, plus 180 deg while it passes over the top, as a camera
    flying over the pole turns relative to the spin axis (the far side is seen upside down, its
    rotation reversed). The span (lens) eases span0 -> span_top (the near face-on ring sized to
    the frame's width) -> span_end (the edge-on disk along the frame's height)."""
    bump = math.sin(math.pi * u) ** 2
    theta = a.theta_min + (incl0 - a.theta_min) * (1 - bump)
    roll = a.roll_end_extra * u + 180.0 * smootherstep((u - 0.25) / 0.5)
    if u < 0.5:
        lo, hi, w = span0, a.span_top, smootherstep(u / 0.5)
    else:
        lo, hi, w = a.span_top, a.span_end, smootherstep((u - 0.5) / 0.5)
    span = math.exp(math.log(lo) + (math.log(hi) - math.log(lo)) * w)
    return theta, span, roll, a.az_end * u


def orbit_camera(a, fps, n_frames, span0, incl0):
    """Per-frame camera: the wallpaper's own view (incl0, span0, no roll, azimuth 0) until
    move_start, then the tour (tour_pose) eased in and out (smootherstep) to move_end, then held."""
    return [tour_pose(a, smootherstep((i / fps - a.move_start) / (a.move_end - a.move_start)), span0, incl0)
            for i in range(n_frames)]


def orbit_strip(a, cmd, camf, span0, incl0, theme):
    """Renders a.strip stills evenly along the tour (move_start to move_end, eased as in the video)
    and tiles them, labelled with time and camera, into <out>/<name>-strip.png."""
    n = a.strip
    times = [a.move_start + (a.move_end - a.move_start) * k / (n - 1) for k in range(n)]
    poses = [tour_pose(a, smootherstep(k / (n - 1)), span0, incl0) for k in range(n)]
    with open(camf, "w") as fh:
        fh.writelines(f"{t:.6f} {s:.4f} {r:.6f} {z:.6f}\n" for t, s, r, z in poses)
    C = CANVAS
    print(f"strip: {n} stills of {theme}", flush=True)
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True)
    nbytes = C["W"] * C["H"] * 4
    if r.returncode != 0 or len(r.stdout) != n * nbytes:
        die(f"strip render failed: {r.stderr.decode()[-400:]}")
    tw, th = 270, 480
    sheet = Image.new("RGB", (n * (tw + 8) + 8, th + 96), (0, 0, 0))
    d = ImageDraw.Draw(sheet)
    f1, f2 = font(HELVETICA, 17, 1), font(HELVETICA, 14, 0)
    for k, (t, (pol, sp, rl, az)) in enumerate(zip(times, poses)):
        im = Image.frombuffer("RGBA", (C["W"], C["H"]), r.stdout[k * nbytes:(k + 1) * nbytes], "raw", "RGBA", 0, 1).convert("RGB")
        x = 8 + k * (tw + 8)
        sheet.paste(im.resize((tw, th), Image.LANCZOS), (x, 8))
        d.text((x, th + 16), f"{t:.1f} s", font=f1, fill=WHITE)
        d.text((x, th + 40), f"polar {pol:.1f}  az {az:.0f}", font=f2, fill=GREY)
        d.text((x, th + 60), f"roll {rl:.0f}  lens {sp / span0:.2f}x", font=f2, fill=GREY)
    name = (a.name[0] if a.name else "orbit") + "-strip.png"
    sheet.save(os.path.join(a.out, name))
    print(f"wrote {os.path.join(a.out, name)}", flush=True)


def make_orbit(a, zig, dev, themes, cfgs, hooks, names, clock, clock_text, work):
    """One Kerr-disk theme: the hook and the theme on the Mac's screen, the Mac fades away, then the
    camera moves around the black hole in the theme's own simulation, traced natively at 1080x1920.
    The whole video is one render: during the opening the screen shows exactly its part of that
    render (the camera then is the wallpaper's own: the theme's inclination, the theme's frame
    height across the display's height, centred on the screen), so the handoff is seamless."""
    if len(themes) != 1:
        die("orbit takes one theme")
    theme, cfg = themes[0], cfgs[0]
    kind, path = theme_kind(theme)
    if kind != "kerr":
        die("orbit needs a Kerr-disk theme: the camera moves in its simulation")
    with open(path) as fh:
        m = re.search(r"pub const INCL: f64 = ([0-9.]+) \* math\.pi / 180\.0;", fh.read())
    if not m:
        die(f"{theme}: no INCL in degrees found")
    incl0 = float(m.group(1))
    fps = a.fps
    total = a.duration
    end_at = total - a.end
    f0, f1 = a.mac_fade
    if not (0 < f0 < f1 and a.move_start >= f0 and a.move_start < a.move_end <= end_at) or total > 60:
        die("timeline: need 0 < Mac fade start < fade end, the move to start after the fade starts and end by the end card")
    F = round(total * fps)
    fade_f0, end_f = round((end_at - 0.25) * fps), round(end_at * fps)

    C = CANVAS
    pw, ph = dev["pt"]
    DH0 = round(C["DW"] * ph / pw)
    g = geometry(dev, dy=C["H"] / 2 - DH0 / 2)  # the screen centred on the render's centre (the hole)
    DW, DH, dx, dy = g["DW"], g["DH"], g["dx"], g["dy"]
    if dx + DW / 2 != C["W"] / 2:
        die("orbit: the display must be centred")
    cam = orbit_camera(a, fps, end_f, DH, incl0)
    camf = os.path.join(work, "camera.txt")
    with open(camf, "w") as fh:
        fh.writelines(f"{i:.6f} {s:.4f} {r:.6f} {z:.6f}\n" for i, s, r, z in cam)
    moving = sum(1 for k in range(1, end_f) if cam[k] != cam[k - 1])
    print(f"render {theme}: {end_f} frames at {C['W']}x{C['H']}, {fps} FPS, after {cfg['warmup']} s warm-up; "
          f"tour: polar angle {incl0:g} -> {a.theta_min:g} -> {incl0:g} deg, azimuth 0 -> {a.az_end:g} deg, "
          f"roll 0 -> {cam[-1][2]:g} deg, span {DH} -> {a.span_top:g} -> {a.span_end:g}; {moving + 1} traces", flush=True)
    skip = int(round(cfg["warmup"] * fps))
    cmd = [zig, "run", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", "--dep", "theme",
           "-Mroot=src/offline_render_bh.zig", "-O", "ReleaseFast", f"-Mtheme={os.path.relpath(path, ROOT)}", "--",
           "--size", f"{C['W']}x{C['H']}", "--fps", str(fps), "--skip", str(skip), "--camera", camf,
           "--meter-size", f"{pw * 2}x{ph * 2}", "--sigma", "0", "--hold-exposure"]
    if a.strip:
        return orbit_strip(a, cmd, camf, DH, incl0, theme)

    # The Mac (device + menu bar), and where its screen lets the render through.
    device = draw_device(dev, g, (0, 0, C["W"], C["H"]), 1, 4)
    mbar = menu_bar(dev, g, 1, zig, a.spaces, 0, clock_text, work)
    layer = Image.new("RGBA", device.size, (0, 0, 0, 0))
    layer.paste(mbar, (int(round(dx)), int(round(dy))))
    device = Image.alpha_composite(layer, device)
    R = Raster((0, 0, C["W"], C["H"]), 1, 4)
    inside = np.asarray(R.poly(bezel_polygon(dev, g)), np.float32)[..., None] / 255
    dev_a = np.asarray(device, np.float32)[..., 3:4] / 255
    dev_pm = np.asarray(device, np.float32)[..., :3] * dev_a
    endcard = end_card(zig, a.spaces, work, a.end_line1, a.end_line2)

    beats = [dict(kind="mac_fade", start=f0, end=f1),
             dict(kind="camera_tour", start=a.move_start, end=a.move_end, polar=[incl0, a.theta_min, incl0],
                  azimuth=[0, a.az_end], roll=[0, round(cam[-1][2], 3)], span=[DH, a.span_top, a.span_end],
                  over_the_top=round(a.move_start + (a.move_end - a.move_start) / 2, 4)),
             dict(kind="end_card", start=round(fade_f0 / fps, 4), full=round(end_at, 4))]
    labels = [(f0, f1, "Mac fades"), (a.move_start, a.move_end, f"tour over the top ({a.theta_min:g} deg from the pole)"),
              (fade_f0 / fps, end_at, "end card")]
    chapters = [(0, f"{cfg['name']} on the Mac"), (round(f0 * fps), f"{cfg['name']}"), (fade_f0, "End card")]

    outs = []
    for hi, hook in enumerate(hooks):
        name = names[hi] if names else f"orbit-{slug(hook)}"
        print(f"compose {name}", flush=True)
        hl = np.asarray(hook_layer(hook, g["lid"][1]), np.float32)
        ha = hl[..., 3:4] / 255
        hw = os.path.join(work, f"h{hi}")
        os.makedirs(hw)
        out_mp4 = os.path.join(a.out, name + ".mp4")
        outs.append((name, out_mp4, hl[..., :3] * ha, ha, open_encoder(out_mp4, fps, F, a.sound, chapters, a.crf, hw)))

    nbytes = C["W"] * C["H"] * 4
    with open(os.path.join(work, "render.log"), "ab") as log:
        r = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=log, bufsize=nbytes)
        try:
            for i in range(F):
                t = i / fps
                mac = 1 - smoothstep(f0, f1, t)  # how much of the Mac (and the hook) is left
                if i < end_f:
                    b = r.stdout.read(nbytes)
                    if len(b) != nbytes:
                        die(f"{theme}: the renderer stopped at frame {i}; see {os.path.join(work, 'render.log')}")
                    th = np.frombuffer(b, np.uint8).reshape(C["H"], C["W"], 4)[..., :3]
                    if mac > 0:
                        base = th.astype(np.float32) * (inside + (1 - inside) * (1 - mac))
                        base = base * (1 - dev_a * mac) + dev_pm * mac
                    else:
                        base = None
                for name, out_mp4, hpm, ha, enc in outs:
                    if i < end_f:
                        if base is None:
                            frame = th.astype(np.float32) if i >= fade_f0 else th
                        else:
                            frame = base * (1 - ha * mac) + hpm * mac
                    else:
                        frame = 0.0
                    if i >= fade_f0:
                        e = smoothstep(fade_f0, end_f, i)
                        frame = frame * (1 - e) + endcard * e
                    if frame is not th:
                        frame = np.clip(frame + 0.5, 0, 255).astype(np.uint8)
                    enc.stdin.write(np.ascontiguousarray(frame).tobytes())
        finally:
            r.stdout.close()
            rc = r.wait()
            for *_, enc in outs:
                enc.stdin.close()
    if rc != 0:
        die(f"{theme}: renderer exited {rc}")
    for (name, out_mp4, *_, enc), hook in zip(outs, hooks):
        if enc.wait() != 0:
            die(f"{name}: encode failed")
        finish(a, name, out_mp4, fps, F, hook, themes, beats, labels)


# ---------------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--format", default="pov", choices=["pov", "orbit"])
    ap.add_argument("--device", default="mbp14", choices=sorted(DEVICES))
    ap.add_argument("--themes", required=True, help="comma-separated theme names (themes/<name>.metal or .zig)")
    ap.add_argument("--hook", action="append", required=True, help="hook text above the screen; variants: repeat it or separate them with |; \\n breaks a line")
    ap.add_argument("--name", action="append", help="output name per hook, same forms as --hook (default: <format>-<slug of the hook>)")
    ap.add_argument("--seg", type=float, default=3.0, help="pov: seconds per theme; the swipes start at seg, 2 seg, ...")
    ap.add_argument("--swipe", type=float, default=0.6, help="pov: Space-swipe duration, s")
    ap.add_argument("--duration", type=float, default=18.0, help="orbit: length of the video, s")
    ap.add_argument("--mac-fade", type=float, nargs=2, default=[2.0, 3.2], metavar=("START", "END"), help="orbit: the Mac and the hook fade out, s")
    ap.add_argument("--move-start", type=float, default=2.2, help="orbit: the camera starts moving, s")
    ap.add_argument("--move-end", type=float, default=16.9, help="orbit: the camera arrives, s")
    ap.add_argument("--theta-min", type=float, default=20, help="orbit: the tour's closest approach to the pole, degrees (keep >= 20: near the axis the tracer slows from ~1 s a frame to 26 s at 15 deg, minutes below 5)")
    ap.add_argument("--az-end", type=float, default=180, help="orbit: how far the probe travels around the spin axis, degrees")
    ap.add_argument("--roll-end-extra", type=float, default=90, help="orbit: roll spread over the tour on top of the 180 deg over the top (90: the disk ends along the long side)")
    ap.add_argument("--span-top", type=float, default=720, help="orbit: lens over the top: output pixels per theme frame height (the screen's view is the display's height, 639)")
    ap.add_argument("--span-end", type=float, default=1150, help="orbit: lens at the end, edge-on again")
    ap.add_argument("--strip", type=int, default=0, help="orbit: render only N stills along the tour into NAME-strip.png, for approval")
    ap.add_argument("--spaces", type=int, default=4, help="orbit: Spaces shown in the eye glyph")
    ap.add_argument("--end", type=float, default=1.0, help="seconds of end card at the end")
    ap.add_argument("--fps", type=int, default=60, choices=[30, 60])
    ap.add_argument("--clock", default="2026-10-23T21:41:00", help="local time on the menu bar (and on theme clocks), ISO")
    ap.add_argument("--end-line1", default="free & open source · macOS")
    ap.add_argument("--end-line2", default="github.com/gke0op/argus")
    ap.add_argument("--sound", help="audio file to lay under the video (default: a silent track, the slot)")
    ap.add_argument("--stills", default="1,6,11", help="seconds to export as PNG stills")
    ap.add_argument("--guides", action="store_true", help="also write a still with the UI safe zones washed red")
    ap.add_argument("--crf", type=int, default=16)
    ap.add_argument("--out", default=os.path.expanduser("~/Desktop/argus-clips/social"))
    ap.add_argument("--keep-work", action="store_true")
    a = ap.parse_args()

    zig = zig_path()
    themes = [t.strip() for t in a.themes.split(",") if t.strip()]
    if not themes:
        die("no themes")
    hooks = [h.strip().replace("\\n", "\n") for v in a.hook for h in v.split("|") if h.strip()]
    names = [x.strip() for v in (a.name or []) for x in v.split("|") if x.strip()]
    if len(names) not in (0, len(hooks)):
        die("give one --name per --hook, or none")
    with open(os.path.join(HERE, "themes.json")) as fh:
        table = json.load(fh)
    cfgs = []
    for t in themes:
        c = dict(name=t.replace("_", " "), line="", warmup=8)
        c.update(table.get(t, {}))
        cfgs.append(c)
        theme_kind(t)  # fail early on a theme with no renderer
    clock = datetime.datetime.fromisoformat(a.clock)
    clock_text = clock.strftime("%a %b %-d  %-I:%M %p")
    dev = DEVICES[a.device]

    os.makedirs(a.out, exist_ok=True)
    work = os.path.join(a.out, f".work-{os.getpid()}")
    os.makedirs(work)
    try:
        (make_orbit if a.format == "orbit" else make_pov)(a, zig, dev, themes, cfgs, hooks, names, clock, clock_text, work)
    finally:
        if not a.keep_work:
            shutil.rmtree(work)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
tools/social/social.py -- vertical social videos of Argus themes ("POV: my Mac wallpaper").

Each theme is rendered offline by its own code on the app's GPU path (src/offline_render_metal.zig
for Metal themes, src/offline_render_bh.zig for Kerr-disk Zig themes such as Cygnus_A), paced as
the app paces it at the output frame rate. Nothing is screen-recorded. The Mac around it is drawn
here: a MacBook-style lid and base, a minimal menu bar (Finder's menus, the Argus eye glyph drawn
by the app's own rasteriser, the clock), Space swipes between the themes, a hook above the screen,
a caption below it, and an end card. Output: H.264 1080x1920 60 FPS MP4 with a silent stereo
track (the sound slot) or --sound, chapters at the swipes, a beats sidecar (JSON and an Audacity
label track) and stills.

  python3 -I tools/social/social.py --themes Cygnus_A,Night_Tide,Roulette_Chrome,Phosphor_Terminal \
      --hook "wdym my wallpaper has general relativity" --hook "POV: every desktop ..."

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

# Layout of the "pov" format (framing B): a 16:9 Mac screen in the middle of a 9:16 canvas.
# Safe zones (TikTok / Reels / Shorts UI): text stays left of SAFE_RIGHT, below SAFE_TOP and
# above SAFE_BOTTOM (the bottom 20 %). The screen itself may sit under the right-hand buttons.
POV = dict(
    W=1080, H=1920,
    DW=976, DH=549,               # the display, 16:9
    BEZEL=(14, 14, 14, 20),       # left, top, right, bottom glass around the display
    EDGE=3,                       # the lid's aluminium edge
    LID_Y=670, LID_R=24, DISP_R=10,
    BASE_H=16, BASE_OVER=24,      # the base's front lip: height, overhang past the lid
    MB_H=26, NOTCH_W=124, NOTCH_R=9,
    MARGIN=44,                    # text column, aligned with the lid
    SAFE_TOP=210, SAFE_RIGHT=924, SAFE_BOTTOM=1536,
    HOOK_GAP=56,                  # hook baseline block ends this far above the lid
    CAP_GAP=50,                   # caption starts this far below the base
)

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
    z = os.environ.get("ZIG") or (os.path.join(ROOT, ".toolchain", "zig") if os.access(os.path.join(ROOT, ".toolchain", "zig"), os.X_OK) else shutil.which("zig"))
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


def spring(t, dur):
    """Space-swipe position 0..1: a critically damped spring from rest, normalised to land at dur."""
    if t <= 0:
        return 0.0
    if t >= dur:
        return 1.0
    g = lambda s: 1 - (1 + SPRING_W * s) * math.exp(-SPRING_W * s)
    return g(t) / g(dur)


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


def render_segment(zig, theme, cfg, frames, fps, wall, out_path, log_path, dw, dh):
    """Renders `frames` frames of `theme` at 1920x1080 after its warm-up, scaled to the display
    size into a lossless FFV1 file. `wall` is the local time the first shown frame should carry."""
    kind, path = theme_kind(theme)
    skip = int(round(cfg["warmup"] * fps))
    rel = os.path.relpath(path, ROOT)
    if kind == "metal":
        start = wall - datetime.timedelta(seconds=skip / fps)
        cmd = [zig, "run", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", "src/offline_render_metal.zig", "--",
               rel, "--size", "1920x1080", "--fps", str(fps), "--skip", str(skip), "--frames", str(frames),
               "--date", start.strftime("%Y-%m-%dT%H:%M:%SZ"), "--utc-offset", "0", "--seed", str(cfg.get("seed", "0x5EED"))]
    else:
        cmd = [zig, "run", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", "--dep", "theme",
               "-Mroot=src/offline_render_bh.zig", "-O", "ReleaseFast", f"-Mtheme={rel}", "--",
               "--size", "1920x1080", "--fps", str(fps), "--skip", str(skip), "--frames", str(frames)]
    ff = [FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "1920x1080", "-r", str(fps), "-i", "-",
          "-vf", f"scale={dw}:{dh}:flags=lanczos+accurate_rnd+full_chroma_int,format=gbrp", "-c:v", "ffv1", "-level", "3", out_path]
    with open(log_path, "ab") as log:
        p1 = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=log)
        p2 = subprocess.Popen(ff, stdin=p1.stdout)
        p1.stdout.close()
        r2 = p2.wait()
        r1 = p1.wait()
    if r1 != 0 or r2 != 0:
        die(f"{theme}: render failed (renderer {r1}, ffmpeg {r2}); see {log_path}")
    got = int(subprocess.run([shutil.which("ffprobe") or "ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0",
                              "-show_entries", "stream=nb_read_packets", "-of", "csv=p=0", out_path],
                             capture_output=True, text=True).stdout.strip() or 0)
    if got != frames:
        die(f"{theme}: expected {frames} frames, the render has {got}")


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


# ---------------------------------------------------------------------------- drawing

def eye_glyph(zig, px, n, cur, work):
    out = os.path.join(work, f"eye_{px}_{n}_{cur}.pgm")
    if not os.path.exists(out):
        with open(out, "wb") as fh:
            run([zig, "run", "-O", "ReleaseFast", "--dep", "status_glyph", "-Mroot=tools/social/eye_glyph.zig",
                 "-Mstatus_glyph=src/desktop/status_glyph.zig", "--", str(px), str(n), str(cur)], cwd=ROOT, stdout=fh)
    return Image.open(out)


def rrect_mask(size, box, r, ss=4, corners=(True, True, True, True)):
    """Anti-aliased rounded-rectangle mask (L) of `size`, drawn at ss x and downsampled."""
    w, h = size
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle([c * ss for c in box], radius=r * ss, fill=255, corners=corners)
    return m.resize((w, h), Image.LANCZOS)


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


def draw_device(L):
    """The MacBook lid (glass bezel, aluminium edge) and the base's front lip, as an RGBA layer
    of the whole canvas; the display area is left transparent."""
    W, H = L["W"], L["H"]
    bl, bt, br, bb = L["BEZEL"]
    e = L["EDGE"]
    lid_w = L["DW"] + bl + br + 2 * e
    lid_h = L["DH"] + bt + bb + 2 * e
    x0 = (W - lid_w) // 2
    y0 = L["LID_Y"]
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # Aluminium edge, then the glass inside it.
    edge = Image.new("RGBA", (W, H), (84, 86, 91, 255))
    layer.paste(edge, (0, 0), rrect_mask((W, H), (x0, y0, x0 + lid_w, y0 + lid_h), L["LID_R"]))
    glass = Image.new("RGBA", (W, H), (8, 8, 9, 255))
    layer.paste(glass, (0, 0), rrect_mask((W, H), (x0 + e, y0 + e, x0 + lid_w - e, y0 + lid_h - e), L["LID_R"] - e))
    # Base lip: wider than the lid, a silver gradient, rounded below, with the opening scoop.
    by0 = y0 + lid_h
    bx0, bx1 = x0 - L["BASE_OVER"], x0 + lid_w + L["BASE_OVER"]
    bh = L["BASE_H"]
    grad = np.zeros((bh, bx1 - bx0, 4), np.uint8)
    for yy in range(bh):
        t = yy / max(bh - 1, 1)
        c = (1 - t) * np.array([214, 215, 218]) + t * np.array([118, 120, 125])
        grad[yy, :, :3] = c.astype(np.uint8)
        grad[yy, :, 3] = 255
    gimg = Image.fromarray(grad, "RGBA")
    gmask = rrect_mask((bx1 - bx0, bh), (0, -bh, bx1 - bx0, bh), 9)
    layer.paste(gimg, (bx0, by0), gmask)
    hinge = Image.new("RGBA", (lid_w - 2 * L["LID_R"], 2), (24, 24, 26, 255))
    layer.paste(hinge, (x0 + L["LID_R"], by0))
    scoop_w = 150
    sc = Image.new("RGBA", (scoop_w, 7), (70, 72, 76, 255))
    sm = Image.new("L", (scoop_w * 4, 28), 0)
    ImageDraw.Draw(sm).ellipse([0, -28, scoop_w * 4, 28], fill=255)
    layer.paste(sc, ((W - scoop_w) // 2, by0), sm.resize((scoop_w, 7), Image.LANCZOS))
    dx, dy = x0 + e + bl, y0 + e + bt
    clear = Image.new("RGBA", (L["DW"], L["DH"]), (0, 0, 0, 0))
    layer.paste(clear, (dx, dy))
    return layer, (dx, dy), by0 + bh


def menu_overlays(L, zig, n, clock_text, work):
    """Premultiplied RGBA overlays for the top MB_H rows of the display, one per active Space:
    the translucent bar, Finder's menus, the eye glyph (iris on that Space), the clock, the notch
    and the display's rounded top corners."""
    DW, MB = L["DW"], L["MB_H"]
    ss = 4
    out = []
    bold = font(SF, 14, variation="Bold")
    reg = font(SF, 14, variation="Medium")
    menus = ["File", "Edit", "View", "Go", "Window", "Help"]
    for cur in range(n):
        im = Image.new("RGBA", (DW, MB), (0, 0, 0, 0))
        # The bar: a light dark tint so white type reads on any wallpaper.
        tint = np.zeros((MB, DW, 4), np.uint8)
        tint[..., 3] = 46
        im = Image.alpha_composite(im, Image.fromarray(tint, "RGBA"))
        d = ImageDraw.Draw(im)
        cy = MB / 2
        x = 18
        d.text((x, cy), "Finder", font=bold, fill=(255, 255, 255, 245), anchor="lm")
        x += bold.getlength("Finder") + 22
        for m in menus:
            d.text((x, cy), m, font=reg, fill=(255, 255, 255, 240), anchor="lm")
            x += reg.getlength(m) + 20
        notch_x0 = (DW - L["NOTCH_W"]) // 2
        if x > notch_x0:
            die("menu bar: the menus run under the notch")
        cw = reg.getlength(clock_text)
        cx = DW - 16 - cw
        d.text((cx, cy), clock_text, font=reg, fill=(255, 255, 255, 245), anchor="lm")
        g = eye_glyph(zig, 18, n, cur, work)
        white = Image.new("RGBA", g.size, (255, 255, 255, 255))
        gx = int(round(cx - 20 - g.size[0]))
        im.paste(white, (gx, int(round(cy - g.size[1] / 2))), g)
        # Notch (with a camera), in the bezel's black, square at the top, rounded below.
        nm = rrect_mask((DW, MB), (notch_x0, -20, notch_x0 + L["NOTCH_W"], MB), L["NOTCH_R"])
        im.paste(Image.new("RGBA", (DW, MB), (8, 8, 9, 255)), (0, 0), nm)
        cam = Image.new("L", (40, 40), 0)
        ImageDraw.Draw(cam).ellipse([8, 8, 32, 32], fill=255)
        im.paste(Image.new("RGBA", (10, 10), (26, 28, 34, 255)), (DW // 2 - 5, MB // 2 - 5), cam.resize((10, 10), Image.LANCZOS))
        # Rounded top corners of the panel.
        corner = rrect_mask((DW, MB), (0, 0, DW, MB + 40), L["DISP_R"])
        inv = Image.eval(corner, lambda v: 255 - v)
        im.paste(Image.new("RGBA", (DW, MB), (8, 8, 9, 255)), (0, 0), inv)
        a = np.asarray(im, np.float32)
        alpha = a[..., 3:4] / 255.0
        out.append((a[..., :3] * alpha, alpha))
    return out


def caption_layer(L, cfg, h):
    """A caption (name, then one line in grey) as premultiplied float RGB of a full-width strip."""
    im = Image.new("RGB", (L["W"], h), (0, 0, 0))
    d = ImageDraw.Draw(im)
    x = L["MARGIN"]
    fmax = L["SAFE_RIGHT"] - x
    fn = font(HELVETICA, 46, 1)
    fl = font(HELVETICA, 34, 0)
    name, line = cfg["name"], cfg.get("line", "")
    if fn.getlength(name) > fmax or (line and fl.getlength(line) > fmax):
        die(f"caption too wide for the safe zone: {name!r} / {line!r}")
    d.text((x, 0), name, font=fn, fill=WHITE, anchor="lt")
    if line:
        d.text((x, 62), line, font=fl, fill=GREY, anchor="lt")
    return np.asarray(im, np.float32)


def hook_layer(L, text):
    """The hook: Helvetica Bold, white, left-aligned, as large as fits in three lines inside the
    safe zone, its block ending HOOK_GAP above the lid. Returns an RGBA image and the top y."""
    x = L["MARGIN"]
    max_w = L["SAFE_RIGHT"] - x
    for size in range(96, 40, -2):
        f = font(HELVETICA, size, 1)
        lines = wrap(text, f, max_w)
        if len(lines) <= 3 and all(f.getlength(s) <= max_w for s in lines):
            break
    else:
        die(f"hook too long for three lines: {text!r}")
    lead = round(size * 1.08)
    block_h = lead * (len(lines) - 1) + size
    bottom = L["LID_Y"] - L["HOOK_GAP"]
    top = bottom - block_h
    if top < L["SAFE_TOP"]:
        die(f"hook too tall for the safe zone: {text!r}")
    im = Image.new("RGBA", (L["W"], L["H"]), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, s in enumerate(lines):
        d.text((x, top + i * lead), s, font=f, fill=WHITE + (255,), anchor="lt")
    return im, size, lines


def end_card(L, zig, n, work, line1, line2):
    """The end card: the eye glyph, the Argus wordmark, line1, and the URL in grey."""
    im = Image.new("RGB", (L["W"], L["H"]), (0, 0, 0))
    d = ImageDraw.Draw(im)
    x = L["MARGIN"] + 20
    g = eye_glyph(zig, 96, n, 0, work)
    y = 640
    im.paste(Image.new("RGB", g.size, WHITE), (x - 6, y), g)
    y += 96 + 40
    fw = font(HELVETICA, 168, 1)
    d.text((x - 6, y), "Argus", font=fw, fill=WHITE, anchor="lt")
    y += 168 + 46
    f1 = font(HELVETICA, 50, 1)
    d.text((x, y), line1, font=f1, fill=WHITE, anchor="lt")
    y += 50 + 26
    f2 = font(HELVETICA, 42, 0)
    d.text((x, y), line2, font=f2, fill=GREY, anchor="lt")
    if x + max(f1.getlength(line1), f2.getlength(line2)) > L["SAFE_RIGHT"] or y + 42 > L["SAFE_BOTTOM"]:
        die("end card outside the safe zone")
    return np.asarray(im, np.uint8)


def guides(img, L):
    """Red wash over the platforms' UI zones, for checking a still."""
    a = np.asarray(img, np.float32).copy()
    red = np.array([255, 0, 0], np.float32)
    zones = [(0, 0, L["W"], L["SAFE_TOP"]), (L["SAFE_RIGHT"], L["SAFE_TOP"], L["W"], L["SAFE_BOTTOM"]),
             (0, L["SAFE_BOTTOM"], L["W"], L["H"])]
    for x0, y0, x1, y1 in zones:
        a[y0:y1, x0:x1] = a[y0:y1, x0:x1] * 0.65 + red * 0.35
    return Image.fromarray(a.astype(np.uint8))


# ---------------------------------------------------------------------------- the video

def slug(text):
    words = re.sub(r"[^a-z0-9 ]+", "", text.lower()).split()
    return "-".join(words[:7]) or "video"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--format", default="pov", choices=["pov"])
    ap.add_argument("--themes", required=True, help="comma-separated theme names (themes/<name>.metal or .zig)")
    ap.add_argument("--hook", action="append", required=True, help="hook text above the screen; variants: repeat it or separate them with |; \\n breaks a line")
    ap.add_argument("--name", action="append", help="output name per hook, same forms as --hook (default: pov-<slug of the hook>)")
    ap.add_argument("--seg", type=float, default=3.0, help="seconds per theme; the swipes start at seg, 2 seg, ...")
    ap.add_argument("--end", type=float, default=1.0, help="seconds of end card, taken from the last theme's slot")
    ap.add_argument("--swipe", type=float, default=0.6, help="Space-swipe duration, s")
    ap.add_argument("--fps", type=int, default=60, choices=[30, 60])
    ap.add_argument("--clock", default="2026-10-23T21:41:00", help="local time on the menu bar (and on theme clocks), ISO")
    ap.add_argument("--end-line1", default="free & open source · macOS")
    ap.add_argument("--end-line2", default="github.com/gke0op/argus")
    ap.add_argument("--sound", help="audio file to lay under the video (default: a silent track, the slot)")
    ap.add_argument("--stills", default="1,4,10", help="seconds to export as PNG stills")
    ap.add_argument("--guides", action="store_true", help="also write a still with the UI safe zones washed red")
    ap.add_argument("--crf", type=int, default=16)
    ap.add_argument("--out", default=os.path.expanduser("~/Desktop/argus-clips/social"))
    ap.add_argument("--keep-work", action="store_true")
    a = ap.parse_args()

    L = POV
    zig = zig_path()
    themes = [t.strip() for t in a.themes.split(",") if t.strip()]
    if len(themes) < 1:
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
    clock = datetime.datetime.fromisoformat(a.clock)
    clock_text = clock.strftime("%a %b %-d  %-I:%M %p")

    os.makedirs(a.out, exist_ok=True)
    work = os.path.join(a.out, f".work-{os.getpid()}")
    os.makedirs(work)
    log = os.path.join(work, "render.log")
    try:
        # 1. The themes, once for all hooks.
        segs = []
        for k, (t, c) in enumerate(zip(themes, cfgs)):
            frames = vis[k][1] - vis[k][0]
            p = os.path.join(work, f"seg{k}_{t}.mkv")
            print(f"render {t}: {frames} frames at {fps} FPS after {c['warmup']} s warm-up", flush=True)
            render_segment(zig, t, c, frames, fps, clock + datetime.timedelta(seconds=vis[k][0] / fps), p, log, L["DW"], L["DH"])
            segs.append(p)

        # 2. Everything that does not move.
        device, (dx, dy), base_bottom = draw_device(L)
        bars = menu_overlays(L, zig, n, clock_text, work)
        cap_y0 = base_bottom + L["CAP_GAP"]
        cap_h = 120
        if cap_y0 + cap_h > L["SAFE_BOTTOM"]:
            die("caption below the safe zone")
        caps = [caption_layer(L, c, cap_h) for c in cfgs]
        endcard = end_card(L, zig, n, work, a.end_line1, a.end_line2).astype(np.float32)
        DW, DH, MB = L["DW"], L["DH"], L["MB_H"]

        # Swipe beats, for the sound pass.
        beats = []
        for k in range(1, n):
            s = start_f[k] / fps
            beats.append(dict(kind="swipe", from_theme=themes[k - 1], to_theme=themes[k], start=round(s, 4),
                              peak_velocity=round(s + 1 / SPRING_W, 4), settled=round(s + a.swipe, 4)))
        beats.append(dict(kind="end_card", start=round(fade_f0 / fps, 4), full=round(end_at, 4)))

        for hi, hook in enumerate(hooks):
            name = names[hi] if names else f"{a.format}-{slug(hook)}"
            base = Image.new("RGBA", (L["W"], L["H"]), (0, 0, 0, 255))
            hl, hsize, hlines = hook_layer(L, hook)
            base = Image.alpha_composite(base, hl)
            base = Image.alpha_composite(base, device)
            static = np.asarray(base.convert("RGB"), np.uint8)
            out_mp4 = os.path.join(a.out, name + ".mp4")
            print(f"compose {name}: hook {hsize} px in {len(hlines)} lines", flush=True)

            meta = os.path.join(work, "chapters.txt")
            with open(meta, "w") as fh:
                fh.write(";FFMETADATA1\ntitle=Argus\n")
                marks = [(start_f[k], cfgs[k]["name"]) for k in range(n)] + [(fade_f0, "End card")]
                for i, (f0, title) in enumerate(marks):
                    f1 = marks[i + 1][0] if i + 1 < len(marks) else F
                    fh.write(f"[CHAPTER]\nTIMEBASE=1/{fps}\nSTART={f0}\nEND={f1}\ntitle={title}\n")
            audio = (["-i", a.sound] if a.sound else ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"])
            enc = subprocess.Popen(
                [FFMPEG, "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{L['W']}x{L['H']}", "-r", str(fps), "-i", "-",
                 *audio, "-i", meta, "-map", "0:v", "-map", "1:a", "-map_metadata", "2", "-map_chapters", "2",
                 "-vf", "scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,"
                 "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv",
                 "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level", "4.2", "-crf", str(a.crf),
                 "-maxrate", "24M", "-bufsize", "48M", "-g", str(fps), "-bf", "2",
                 "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv",
                 "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-af", "apad", "-t", f"{F / fps:.6f}",
                 "-movflags", "+faststart", out_mp4], stdin=subprocess.PIPE)
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
                        pm, al = bars[cur]
                        top = disp[:MB].astype(np.float32) * (1 - al) + pm
                        disp[:MB] = np.clip(top + 0.5, 0, 255).astype(np.uint8)
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

            with open(os.path.join(a.out, name + ".beats.json"), "w") as fh:
                json.dump(dict(video=name + ".mp4", fps=fps, duration=F / fps, hook=hook, themes=themes,
                               sound=os.path.basename(a.sound) if a.sound else "silent (slot)", beats=beats), fh, indent=2)
            with open(os.path.join(a.out, name + ".labels.txt"), "w") as fh:  # Audacity label track
                for b in beats:
                    if b["kind"] == "swipe":
                        fh.write(f"{b['start']:.4f}\t{b['settled']:.4f}\tswipe {b['from_theme']} -> {b['to_theme']}\n")
                    else:
                        fh.write(f"{b['start']:.4f}\t{b['full']:.4f}\tend card\n")
            for s in [float(x) for x in a.stills.split(",") if x.strip()]:
                png = os.path.join(a.out, f"{name}_{s:g}s.png")
                run([FFMPEG, "-v", "error", "-y", "-i", out_mp4, "-vf", f"select=eq(n\\,{round(s * fps)})", "-frames:v", "1", png])
            if a.guides:
                g = os.path.join(a.out, f"{name}_safezones.png")
                src = os.path.join(a.out, f"{name}_{float(a.stills.split(',')[0]):g}s.png")
                guides(Image.open(src).convert("RGB"), L).save(g)
            print(f"wrote {out_mp4}", flush=True)
    finally:
        if not a.keep_work:
            shutil.rmtree(work)


if __name__ == "__main__":
    main()

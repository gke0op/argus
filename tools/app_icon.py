#!/usr/bin/env python3
"""Builds Argus.app's icon (Argus.app/Contents/Resources/Argus.icns) from the Cygnus A still.

    python3 -I tools/app_icon.py [docs/media/cygnus-a.png] [out.icns]

The quasar seen nearly edge-on reads as an eye: the disk is the lid line, the shadow the pupil.
A square crop around the shadow goes into the macOS app-icon shape (an 824 px rounded square
on a 1024 px canvas, with Apple's drop shadow), then into every size of an
.iconset, and iconutil packs the .icns. Needs Pillow and macOS's iconutil.
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs/media/cygnus-a.png")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "Argus.app/Contents/Resources/Argus.icns")

CANVAS = 1024
BODY = 824  # Apple's macOS icon grid: the shape is 824 px on a 1024 px canvas
CENTER = (985, 540)  # the shadow's centre in the 1920x1080 still
CROP = 1000  # px of the still across the icon body
SS = 4  # supersampling for the mask edge


def squircle(size: int) -> Image.Image:
    """Alpha mask of the macOS icon shape: a rounded square, corner radius 185/824 of its side."""
    big = size * SS
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=big * 185 // 824, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def build() -> Image.Image:
    still = Image.open(SRC).convert("RGB")
    cx, cy = CENTER
    h = CROP // 2
    art = still.crop((cx - h, cy - h, cx + h, cy + h)).resize((BODY, BODY), Image.LANCZOS)

    mask = squircle(BODY)
    # A faint rim so the black icon doesn't vanish on a dark Dock.
    rim = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(5)))
    rim = rim.point(lambda v: v * 0.22)
    art = Image.composite(Image.new("RGB", art.size, (190, 200, 230)), art, rim)

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    off = (CANVAS - BODY) // 2
    # Apple's template shadow: black at ~30%, blurred, a little below the shape.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (BODY, BODY), (0, 0, 0, 80)), (off, off + 12), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    icon.alpha_composite(shadow)
    body = art.convert("RGBA")
    body.putalpha(mask)
    icon.alpha_composite(body, (off, off))
    return icon


def main() -> None:
    icon = build()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "Argus.iconset")
        os.mkdir(iconset)
        for pt in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = pt * scale
                name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
                icon.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT], check=True)
    if os.environ.get("ARGUS_ICON_PNG"):  # a 1024 px preview, wherever you point it
        icon.save(os.environ["ARGUS_ICON_PNG"])
    print(f"app_icon: wrote {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()

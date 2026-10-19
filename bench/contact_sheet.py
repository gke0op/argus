#!/usr/bin/env python3
"""Contact sheet of the best run per model and mode (needs Pillow).

Usage: python3 bench/contact_sheet.py bench/results/<date> docs/media/bench-leaderboard.png

"Best" is decided by the scorecard alone, not by eye: a passing run first, then the highest gate
score, then the lowest median frame time. Each tile is that run's last harness frame (frame 120).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from leaderboard import MODES, NAMES, ORDER  # noqa: E402

TW, TH, LABEL, PAD = 320, 200, 26, 6


def best(base, model, mode):
    d = os.path.join(base, model, mode)
    cands = []
    for run in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        p = os.path.join(d, run, "score.json")
        if os.path.exists(p) and os.path.exists(os.path.join(d, run, "frame.png")):
            s = json.load(open(p))
            key = (s["verdict"] != "PASS", -s["gate_score"], s.get("avg_us_median") or 1e9)
            cands.append((key, run, s))
    return min(cands) if cands else None


def main():
    base, out = sys.argv[1], sys.argv[2]
    font = ImageFont.load_default(size=13)
    W = PAD + len(ORDER) * (TW + PAD)
    H = PAD + len(MODES) * (TH + LABEL + PAD)
    sheet = Image.new("RGB", (W, H), (12, 12, 16))
    dr = ImageDraw.Draw(sheet)
    for row, mode in enumerate(MODES):
        for col, model in enumerate(ORDER):
            x, y = PAD + col * (TW + PAD), PAD + row * (TH + LABEL + PAD)
            b = best(base, model, mode)
            if not b:
                dr.text((x + 8, y + TH // 2), "%s %s: no frame" % (NAMES[model], mode), fill=(200, 200, 200), font=font)
                continue
            _, run, s = b
            img = Image.open(os.path.join(base, model, mode, run, "frame.png")).convert("RGB").resize((TW, TH), Image.LANCZOS)
            sheet.paste(img, (x, y))
            ms = "%.2f ms" % (s["avg_us_median"] / 1000) if s.get("avg_us_median") else "-"
            label = "%s · %s · %s · %s · %s" % (NAMES[model].replace("Claude ", "").replace(" (Argon)", ""), mode, run, s["verdict"], ms)
            dr.text((x + 2, y + TH + 6), label, fill=(225, 225, 230), font=font)
    sheet.save(out, optimize=True)  # full colour: a 256-colour palette bands the smooth gradients
    print(out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main()

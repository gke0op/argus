#!/usr/bin/env python3
"""
tools/orion_bake/verify_earth_view.py -- checks that Opus_Orion_Nebula, seen from Earth (the
orbit frozen at zero), shows exactly the measured line maps it ships.

    python3 -I tools/orion_bake/verify_earth_view.py <render.png> [--diff out.png]

<render.png> is a harness frame of a copy of the theme with ORBIT_YAW and ORBIT_PITCH set to 0.
This script rebuilds the same image independently from themes/Opus_Orion_Nebula.bin and the
baked constants (numpy, bilinear sampling, the same colour pipeline) and compares the two away
from stars. Needs numpy and Pillow.
"""
import math, os, re, sys
import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = open(os.path.join(ROOT, "themes", "Opus_Orion_Nebula.metal")).read()

def const(name):
    m = re.search(rf"constant\s+\w+\s+{name}\s*=\s*([^;]+);", SRC)
    return m.group(1)

def num(name): return float(re.sub(r"[fu]", "", const(name)).strip())

def f2(name):
    v = re.findall(r"[-0-9.e]+", const(name)); return float(v[-2]), float(v[-1])

def lines(name):
    body = re.search(rf"constant Line {name}\[\d+\] = \{{(.*?)\}};", SRC, re.S).group(1)
    out = []
    for m in re.finditer(r"\{float3\(([^)]*)\),\s*([-0-9.e]+)f,\s*([-0-9.e]+)f\}", body):
        out.append((np.array([float(x.strip().rstrip("f")) for x in m.group(1).split(",")]), float(m.group(2)), float(m.group(3))))
    return out

W = int(re.search(r"DATA_W = (\d+)u", SRC).group(1)); H = int(re.search(r"DATA_H = (\d+)u", SRC).group(1))
LR = [tuple(float(v) for v in p) for p in re.findall(r"float2\(([-0-9.]+)f, ([-0-9.]+)f\)", re.search(r"LOG_RANGE\[6\] = \{(.*?)\};", SRC, re.S).group(1))]
TEXEL = num("TEXEL_PC"); EXPO = num("EXPOSURE"); STRETCH = num("STRETCH"); C_FG = num("C_FG")
cx, cy = (float(v) for v in re.findall(r"[-0-9.]+(?=f)", const("STAR_C_TEX"))[-2:])
VIEW_W = num("VIEW_W_PC"); VX, VY = (float(v) for v in re.findall(r"[-0-9.]+(?=f)", const("VIEW_C"))[-2:])

raw = np.fromfile(os.path.join(ROOT, "themes", "Opus_Orion_Nebula.bin"), np.uint8).reshape(2 * H, W, 4) / 255.0
A, B = raw[:H][::-1], raw[H:][::-1]          # row 0 = south from here on
dec = lambda e, k: 10 ** (LR[k][0] + e * (LR[k][1] - LR[k][0]))
ha, o3, n2, s2 = dec(A[..., 0], 0), dec(A[..., 1], 1), dec(A[..., 2], 2), dec(A[..., 3], 3)
o1 = dec(B[..., 0], 4); cveil = B[..., 1] * 1.6; rsii = 0.4 + 1.1 * B[..., 3]
c = cveil + C_FG

def group(L, r=None):
    s = 0
    for xyz, ratio, k in L:
        rr = r if ratio < 0 else ratio
        s = s + xyz[None, None, :] * np.asarray(rr)[..., None] * np.exp(-2.3025851 * c * k)[..., None]
    return s

xyz = (ha[..., None] * group(lines("L_BALMER")) + o3[..., None] * group(lines("L_OIII"))
       + n2[..., None] * group(lines("L_NII")) + s2[..., None] * group(lines("L_SII"), rsii)
       + o1[..., None] * group(lines("L_OI")))
M = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
lin = xyz @ M.T * EXPO          # per texel, before display; sampled bilinearly like the GPU does

ref_img = np.array(Image.open(sys.argv[1]).convert("RGB")).astype(np.float64) / 255.0
h, w = ref_img.shape[:2]
scale = min(VIEW_W / w, num("VIEW_H_PC") / h)
gx, gy = np.meshgrid(np.arange(w) + 0.5 - w / 2, -(np.arange(h) + 0.5 - h / 2))
col = cx + (VX + gx * scale) / TEXEL; row = cy + (VY + gy * scale) / TEXEL

def bilinear(img, x, y):
    x0 = np.clip(np.floor(x).astype(int), 0, img.shape[1] - 2); y0 = np.clip(np.floor(y).astype(int), 0, img.shape[0] - 2)
    fx = np.clip(x - x0, 0, 1)[..., None]; fy = np.clip(y - y0, 0, 1)[..., None]
    return ((img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx) * (1 - fy) + (img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx) * fy)

# The GPU samples each quantity and combines them per pixel; colours are linear in the line
# brightnesses but not in c, so sample the inputs, not the colour.
def samp(a): return bilinear(a[..., None] if a.ndim == 2 else a, col, row)[..., 0] if a.ndim == 2 else bilinear(a, col, row)
C = samp(c)
def groupS(L, r=None):
    s = 0
    for xyzL, ratio, k in L:
        rr = r if ratio < 0 else ratio
        s = s + xyzL[None, None, :] * np.asarray(rr)[..., None] * np.exp(-2.3025851 * C * k)[..., None]
    return s
XYZ = (samp(ha)[..., None] * groupS(lines("L_BALMER")) + samp(o3)[..., None] * groupS(lines("L_OIII"))
       + samp(n2)[..., None] * groupS(lines("L_NII")) + samp(s2)[..., None] * groupS(lines("L_SII"), samp(rsii))
       + samp(o1)[..., None] * groupS(lines("L_OI")))
rgb = XYZ @ M.T * EXPO
Y = np.maximum(rgb @ np.array([0.2126, 0.7152, 0.0722]), 0)
m = rgb.min(-1)
e = (Y - m) / np.maximum(Y, 1e-12)
ec = 0.5 + 0.25 * np.tanh((e - 0.5) / 0.25)
f = np.where(e <= 0.5, 1.0, ec / np.maximum(e, 1e-12))
rgb = np.maximum(Y[..., None] + (rgb - Y[..., None]) * f[..., None], 0)
L = rgb @ np.array([0.2126, 0.7152, 0.0722])
k = np.arcsinh(L / STRETCH) / (math.asinh(1 / STRETCH) * np.maximum(L, 1e-12))
rgb = rgb * k[..., None]
mx = rgb.max(-1)
over = mx > 1
rgb[over] = rgb[over] / mx[over, None] * (1 / mx[over, None]) + (1 - 1 / mx[over, None])
rgb = np.clip(rgb, 0, 1)
srgb = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.power(rgb, 1 / 2.4) - 0.055)

d = (ref_img - srgb) * 255
# stars are drawn on top of the nebula: leave out the pixels around each baked star
body = re.search(r"constant float4 STARS\[N_STARS\] = \{(.*?)\};", SRC, re.S).group(1)
pos = [(float(a), float(b)) for a, b in re.findall(r"float4\(([-0-9.]+)f, ([-0-9.]+)f,", body)]
mask = np.ones((h, w), bool)
yy, xx = np.mgrid[0:h, 0:w]
for i, (sx, sy) in enumerate(pos):
    px, py = w / 2 + (sx - VX) / scale, h / 2 - (sy - VY) / scale
    r = 46 if i < 12 else 9
    if -r < px < w + r and -r < py < h + r:
        x0, x1, y0, y1 = max(int(px - r), 0), min(int(px + r) + 1, w), max(int(py - r), 0), min(int(py + r) + 1, h)
        mask[y0:y1, x0:x1] &= (xx[y0:y1, x0:x1] - px) ** 2 + (yy[y0:y1, x0:x1] - py) ** 2 > r * r
print(f"pixels compared: {mask.mean() * 100:.1f}% (the rest are near stars)")
print(f"display difference (0-255): median {np.median(np.abs(d[mask])):.2f}, 99th pct {np.percentile(np.abs(d[mask]), 99):.2f}, mean {d[mask].mean(0).round(2)}")
if "--diff" in sys.argv:
    out = sys.argv[sys.argv.index("--diff") + 1]
    Image.fromarray(np.clip(128 + d * 8, 0, 255).astype(np.uint8)).save(out)

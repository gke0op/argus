#!/usr/bin/env python3
"""
tools/orion_bake/bake.py -- builds the data behind themes/Opus_Orion_Nebula.metal.

    python3 -I tools/orion_bake/bake.py --cache <dir> [--report <dir>]

Needs numpy and scipy. Downloads (once, into --cache):
  * VLT/MUSE maps of the Orion Nebula, Weilbacher et al. 2015, A&A 582, A114,
    doi:10.17876/data/2023_3 (AIP; DataCite rights: "Creative Commons CC0 for data").
  * 4 x 516 x 64 floats of the Edenhofer et al. 2024 3D dust map (A&A 685, A82;
    doi:10.5281/zenodo.8187943, CC BY 4.0): the 64 HEALPix pixels (nside 256, NEST)
    around M42, read with HTTP range requests from mean_and_std_healpix.fits.

Writes:
  * themes/Opus_Orion_Nebula.bin: the measured maps, downsampled and encoded (see FORMAT).
  * the block between "BEGIN BAKED" and "END BAKED" in themes/Opus_Orion_Nebula.metal:
    the fitted front surface, the flow profile, line colours, extinction ratios.
  * --report: residual maps (PNG) and report.md with every fit number.

Nothing here comes from GPL code; the photoionisation and flow models are written from the
equations in the papers cited next to them.
"""
import argparse, hashlib, json, math, os, re, struct, subprocess, sys, zlib
import numpy as np
from scipy import ndimage as nd, optimize as op

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
THEME = os.path.join(ROOT, "themes", "Opus_Orion_Nebula.metal")
DATA = os.path.join(ROOT, "themes", "Opus_Orion_Nebula.bin")

# ---------------------------------------------------------------------------------------------
# Sources and constants (each with where it comes from)
# ---------------------------------------------------------------------------------------------
MUSE = "https://s3.data.aip.de:9000/data.aip.de/musesc/orion/orion_m42/"
MUSE_FILES = {  # all reddening-corrected by Weilbacher+2015 (Cardelli 1989 as refined for Orion by
    # Blagrave+2007, R_V = 5.5, intrinsic Halpha/Hbeta = 2.89) except where noted
    "hb": "emhbeta_fluxcorr", "oiii": "emoiii5007_fluxcorr", "nii": "emnii6584_fluxcorr",
    "sii": "emsii6731_fluxcorr", "oi": "emoi6300_fluxcorr_cor", "c": "c_Halpha_Hbeta",
    "ne": "den_sii_median33", "ne_cl": "den_cliii_median55", "v_ha": "emhalpha_velos", "v_nii": "emnii6584_velos",
    "v_sii": "emsii6731_velos",
}
EDEN = "https://zenodo.org/records/8187943/files/mean_and_std_healpix.fits?download=1"

DIST_PC = 400.0            # ONC: 388 +- 5 (Kounkel+2017), 414 +- 7 (Menten+2007); chosen 400
SPAXEL_AS = 0.2            # MUSE mosaic sampling (FITS CD matrix)
VIEW_GUESS = (-0.035, -0.045)   # view centre in the theme (pc west, north of theta1 Ori C): star box
F = 3                      # downsampling of the shipped maps: 0.6" texels
HA_HB = 2.89               # Weilbacher+2015's intrinsic ratio (Case B, 9000 K): keeps their dereddening
T4 = 0.9                   # Te ~ 9000 K (Weilbacher+2015 [N II] map; O'Dell & Harris 2010)
ALPHA_B = 2.54e-13 * T4 ** (-0.8163 - 0.0208 * math.log(T4))   # Draine 2011 eq. 14.6
EPS_HB = 1.37e-25          # 4 pi j_Hb / (ne np), erg cm^3 s^-1, Storey & Hummer 1995 between 7500 and 10^4 K
CS_KMS = 11.0              # isothermal sound speed of H+ and He+ at 9000 K: sqrt(kT / 0.64 m_H)
Q_C = 1.7e49               # theta1 Ori C ionising photons s^-1 (O'Dell+2009's Cloudy model; Henney+2005: 1.8e49)
Q_2A = 1.0e48              # theta2 Ori A (O9V, Simon-Diaz+2006): order of magnitude, assumed
PCCM = 3.0857e18
OMEGA = (SPAXEL_AS * math.pi / 180 / 3600) ** 2   # sr per spaxel; maps are erg/s/cm^2 per spaxel (x1e-20)

# Bright stars in the field (SIMBAD; positions and V are facts). Used to mask the line-map
# artefacts that stars leave (Weilbacher+2015 did not mask them before fitting) and drawn.
# (name, RA deg, Dec deg, V, Teff K, Teff source)
STARS = [
    ("theta1 Ori C", 83.8186095697, -5.3897005033, 5.13, 39000, "Simon-Diaz+2006"),
    ("theta2 Ori B", 83.86000314065, -5.41688715766, 6.38, 26000, "Pecaut & Mamajek B1V (B0.7V)"),
    ("theta2 Ori A", 83.84542183261, -5.41606462003, 6.39, 35000, "Simon-Diaz+2006"),
    ("theta1 Ori D", 83.82190603333, -5.38793631614, 6.70, 32000, "Simon-Diaz+2006"),
    ("theta1 Ori A", 83.81593917292, -5.3873151943, 6.73, 30000, "Simon-Diaz+2006"),
    ("theta1 Ori B", 83.81722494169, -5.38521790118, 7.96, 26000, "Pecaut & Mamajek B1V"),
    ("V1073 Ori", 83.86843799716, -5.43898634702, 9.52, 10000, "Pecaut & Mamajek B9.5V (approx.)"),
    ("V1230 Ori", 83.83633509381, -5.36231815052, 9.74, 25000, "B1 (approx.)"),
    ("theta1 Ori F", 83.81969609357, -5.39033271044, 10.12, 12000, "B8 (approx.)"),
    ("KS Ori", 83.75053967604, -5.42117272852, 10.19, 9700, "A0V (approx.)"),
    ("MR Ori", 83.82074294729, -5.36259369654, 10.58, 8800, "A2V (approx.)"),
    ("LL Ori", 83.77348403271, -5.422088978, 11.52, 5000, "K1.8 (approx.)"),
]
CRVAL = (83.780566, -5.396172); CRPIX = (1606.5, 724.5); CDELT = 5.55555555555556e-05  # FITS header

# Line data. Air wavelengths: NIST ASD. Theoretical doublet ratios: Storey & Zeippen 2000.
# Balmer ratios: Storey & Hummer 1995 Case B, 10^4 K, ne = 10^3. Extinction relative to Hbeta,
# k = A_lambda / A_Hbeta = 1 + f_lambda: Blagrave+2007 Table 2 where listed, otherwise the
# Cardelli 1989 optical law at R_V = 5.5 (which Blagrave+2007 leave unchanged for x < 2.3).
LINES = {   # group -> [(lambda nm, ratio to the group's mapped line)]
    "balmer": [(656.2819, 1.0), (486.1333, 1 / HA_HB), (434.0471, 0.4686 / HA_HB), (410.17415, 0.2592 / HA_HB)],
    "oiii": [(500.6843, 1.0), (495.8911, 1 / 2.98)],
    "nii": [(658.345, 1.0), (654.805, 1 / 3.05)],
    "sii": [(673.0815, 1.0), (671.644, None)],            # 6716 from the measured density (Sanders+2016)
    "oi": [(630.0304, 1.0), (636.3776, 1 / 2.997)],
}
K_BLAGRAVE = {656.2819: 0.780, 658.345: 0.778, 500.6843: 0.978, 434.0471: 1.086, 410.17415: 1.117, 486.1333: 1.0}

# ---------------------------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------------------------
def log(*a):
    print(*a, flush=True)

def curl(args):
    import time
    for attempt in range(6):   # Zenodo rate-limits (retry-after: 59 s) and drops TLS now and then
        r = subprocess.run(["curl", "-sL", "--retry", "5", "-m", "900"] + args, capture_output=True)
        if r.returncode == 0 and r.stdout: return r.stdout
        time.sleep(60)
    raise SystemExit("curl failed: " + " ".join(args))

def read_fits(path):
    raw = open(path, "rb").read()
    hdr, off = {}, 0
    while True:
        card = raw[off:off + 80].decode("ascii", "replace"); off += 80
        if card.startswith("END"): break
        if "=" in card[:10]: hdr[card[:8].strip()] = card[10:].split("/")[0].strip().strip("'").strip()
    off = (off + 2879) // 2880 * 2880
    nx, ny = int(hdr["NAXIS1"]), int(hdr["NAXIS2"])
    dt = {-64: ">f8", -32: ">f4"}[int(hdr["BITPIX"])]
    return np.frombuffer(raw, dt, nx * ny, off).reshape(ny, nx).astype(np.float64)

def png(path, img):
    img = np.clip(np.nan_to_num(img) * 255 + 0.5, 0, 255).astype(np.uint8)
    if img.ndim == 2: img = np.stack([img] * 3, -1)
    img = img[::-1]  # north up
    h, w = img.shape[:2]
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))
    def ch(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + ch(b"IDAT", zlib.compress(raw, 6)) + ch(b"IEND", b""))

def sky_to_pix(ra, dec):  # 0-based MUSE pixel (col, row); TAN projection is linear to < 0.01 px here
    return (CRPIX[0] - 1 + (ra - CRVAL[0]) * math.cos(math.radians(CRVAL[1])) / -CDELT,
            CRPIX[1] - 1 + (dec - CRVAL[1]) / CDELT)

def wyman_cmf(l):  # CIE 1931 2-degree observer, multi-lobe fit (Wyman, Sloan & Shirley 2013)
    def lobe(mu, s1, s2):
        t = (l - mu) / (s1 if l < mu else s2); return math.exp(-0.5 * t * t)
    return np.array([1.056 * lobe(599.8, 37.9, 31.0) + 0.362 * lobe(442.0, 16.0, 26.7) - 0.065 * lobe(501.1, 20.4, 26.2),
                     0.821 * lobe(568.8, 46.9, 40.5) + 0.286 * lobe(530.9, 16.3, 31.1),
                     1.217 * lobe(437.0, 11.8, 36.0) + 0.681 * lobe(459.0, 26.0, 13.8)])

def ccm89(lam_nm, rv=5.5):  # Cardelli, Clayton & Mathis 1989, A_lambda / A_V (optical, 1.1 <= x <= 3.3)
    x = 1000.0 / lam_nm; y = x - 1.82
    a = 1 + 0.17699 * y - 0.50447 * y**2 - 0.02427 * y**3 + 0.72085 * y**4 + 0.01979 * y**5 - 0.77530 * y**6 + 0.32999 * y**7
    b = 1.41338 * y + 2.28305 * y**2 + 1.07233 * y**3 - 5.38434 * y**4 - 0.62251 * y**5 + 5.30260 * y**6 - 2.09002 * y**7
    if x > 2.3:  # Blagrave+2007 footnote 3 for 2.3 < x < 3.3
        a = 1.192528 + 0.27592 * (x - 2.3) - 0.15733 * (x - 2.3) ** 2; b = 0.0
    return a + b / rv

def k_line(lam):
    k = ccm89(lam) / ccm89(486.1333)
    return K_BLAGRAVE.get(lam, k), k

# ---------------------------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------------------------
def fetch_muse(cache):
    os.makedirs(cache, exist_ok=True)
    out = {}
    for key, name in MUSE_FILES.items():
        p = os.path.join(cache, name + ".fits")
        want = 1766 * 1476 * (4 if name.startswith("den_") else 8)
        if not os.path.exists(p) or os.path.getsize(p) < want:
            log("download", name)
            for _ in range(6):
                subprocess.run(["curl", "-sL", "-C", "-", "--retry", "5", "-o", p, MUSE + name + ".fits"])
                if os.path.getsize(p) >= want: break
        out[key] = read_fits(p)
    return out

def nest_pix(nside, l, b):  # HEALPix ang2pix, NEST scheme (Gorski et al. 2005)
    def spread(v):
        r = 0
        for i in range(16): r |= ((v >> i) & 1) << (2 * i)
        return r
    theta = math.radians(90 - b); phi = math.radians(l) % (2 * math.pi)
    z = math.cos(theta); za = abs(z); tt = (phi / (math.pi / 2)) % 4
    if za <= 2 / 3:
        t1 = nside * (0.5 + tt); t2 = nside * z * 0.75
        jp, jm = int(t1 - t2), int(t1 + t2); ifp, ifm = jp // nside, jm // nside
        face = (ifp | 4) if ifp == ifm else (ifp if ifp < ifm else ifm + 8)
        ix, iy = jm & (nside - 1), nside - (jp & (nside - 1)) - 1
    else:
        ntt = min(3, int(tt)); tp = tt - ntt; tmp = nside * math.sqrt(3 * (1 - za))
        jp, jm = min(int(tp * tmp), nside - 1), min(int((1 - tp) * tmp), nside - 1)
        if z >= 0: face, ix, iy = ntt, nside - jm - 1, nside - jp - 1
        else: face, ix, iy = ntt + 8, jp, jm
    return face * nside * nside + spread(ix) + (spread(iy) << 1)

def galactic(ra, dec):  # ICRS -> Galactic (Hipparcos rotation matrix)
    R = np.array([[-0.0548755604162154, -0.8734370902348850, -0.4838350155487132],
                  [0.4941094278755837, -0.4448296299600112, 0.7469822444972189],
                  [-0.8676661490190047, -0.1980763734312015, 0.4559837761750669]])
    a, d = math.radians(ra), math.radians(dec)
    g = R @ np.array([math.cos(d) * math.cos(a), math.cos(d) * math.sin(a), math.sin(d)])
    return math.degrees(math.atan2(g[1], g[0])) % 360, math.degrees(math.asin(g[2]))

def fetch_edenhofer(cache):
    """Streams the first ROWS distance shells (69 -> ~520 pc) of the mean and std cubes and keeps
    the 64 nested pixels around M42. The file is pixel-fastest (786432 x 516 float32 per cube),
    and Zenodo answers each range request after ~40-90 s, so one long range per cube (~1.2 GB)
    is far faster than a request per shell."""
    p = os.path.join(cache, "edenhofer2024_m42_block64.npz")
    l, b = galactic(*STARS[0][1:3])
    pix = nest_pix(256, l, b); p0 = pix // 64 * 64
    NP, N, ROWS = 786432, 64, 380
    if not os.path.exists(p):
        def stream(base):
            import time
            out = np.zeros((ROWS, N), np.float32)
            r, drops = 0, 0
            while r < ROWS:   # resumable: a dropped connection restarts at the shell it reached
                proc = subprocess.Popen(["curl", "-sL", "--retry", "5", "-r", f"{base + r * NP * 4}-{base + ROWS * NP * 4 - 1}", EDEN],
                                        stdout=subprocess.PIPE)
                while r < ROWS:
                    buf = b""
                    while len(buf) < NP * 4:
                        chunk = proc.stdout.read(NP * 4 - len(buf))
                        if not chunk: break
                        buf += chunk
                    if len(buf) < NP * 4: break
                    out[r] = np.frombuffer(buf[p0 * 4:p0 * 4 + N * 4], ">f4"); r += 1
                proc.kill(); proc.wait()
                if r < ROWS:
                    drops += 1
                    if drops > 10: raise SystemExit(f"Edenhofer stream keeps dropping (at shell {r})")
                    log(f"  Edenhofer stream dropped at shell {r}; resuming in 60 s"); time.sleep(60)
            return out
        rad = curl(["-r", f"{3246405120}-{3246405120 + 516 * 4 - 1}", EDEN])   # offsets from the FITS headers
        radius = np.frombuffer(rad[:516 * 4], ">f4").astype(np.float32)[:ROWS]
        np.savez(p, mean=stream(5760), std=stream(1623202560 + 2880), radius=radius)
    d = dict(np.load(p))
    d["index"] = pix - p0
    return d

# ---------------------------------------------------------------------------------------------
# Cleaning
# ---------------------------------------------------------------------------------------------
def masked_fill(a, bad, sig=6):
    a = a.copy(); good = ~bad & np.isfinite(a); a[~good] = 0; w = good.astype(float)
    for s in (sig, sig * 3, sig * 9, sig * 27):
        num, den = nd.gaussian_filter(a * w, s), nd.gaussian_filter(w, s)
        sel = (~good) & (den > 0.05)
        a[sel] = (num / np.maximum(den, 1e-12))[sel]; w = np.where(sel, 1.0, w); good |= sel
    return a

def destripe(a, rep=None, name=""):
    """MUSE's IFU slicers leave stripes a few pixels wide along whole exposures, in both axes
    (the mosaic alternated position angle by 90 deg; Weilbacher+2015 Sect. 4). In log space,
    take a high-pass across the stripes (31 px) and its running median along them (301 px,
    about one exposure): what survives is the stripe pattern, not nebular structure."""
    la = np.log(a)
    out = []
    for axis in (1, 0):
        hp = la - nd.uniform_filter1d(la, 31, axis=axis)
        st = nd.median_filter(hp, size=(301, 1) if axis == 1 else (1, 301))
        la = la - st
        out.append(float(st[50:-50, 50:-50].std()))
    if rep is not None: rep.append((name, out))
    return np.exp(la)

def clean(m, stripes=None):
    ny, nx = m["hb"].shape
    yy, xx = np.mgrid[0:ny, 0:nx]
    stars = np.zeros((ny, nx), bool)
    for _, ra, dec, V, _, _ in STARS:
        if V > 11.6: continue
        x, y = sky_to_pix(ra, dec); r = np.clip(16 - 1.4 * (V - 5), 5, 16)
        stars |= (xx - x) ** 2 + (yy - y) ** 2 < r * r
    edge = np.zeros((ny, nx), bool); edge[:8] = edge[-8:] = True; edge[:, :10] = edge[:, -10:] = True
    out = {}
    for k in ("hb", "oiii", "nii", "sii", "oi"):
        a = m[k]; out[k] = destripe(masked_fill(a, stars | ~np.isfinite(a) | (a <= 0)), stripes, k)
    out["c"] = nd.gaussian_filter(masked_fill(m["c"], stars | edge | ~np.isfinite(m["c"]) | (m["c"] <= 0)), 8)
    out["ne"] = nd.gaussian_filter(masked_fill(m["ne"], stars | edge | (m["ne"] < 50) | ~np.isfinite(m["ne"])), 4)
    bad_cl = stars | edge | (m["ne_cl"] < 100) | ~np.isfinite(m["ne_cl"])
    out["ne_cl"] = nd.gaussian_filter(masked_fill(m["ne_cl"], bad_cl), 4); out["ne_cl_ok"] = ~bad_cl
    for k in ("v_ha", "v_nii", "v_sii"):
        out[k] = masked_fill(m[k], stars | edge | ~np.isfinite(m[k]) | (m[k] == 0))
    out["stars"] = stars
    return out

def down(a, f):
    ny, nx = a.shape; a = a[:ny // f * f, :nx // f * f]
    return a.reshape(ny // f, f, nx // f, f).mean((1, 3))

# ---------------------------------------------------------------------------------------------
# The ionisation front: a uniform bicubic B-spline surface z(x, y), fitted so that
# photoionisation balance reproduces the large-scale Halpha emission measure.
# ---------------------------------------------------------------------------------------------
KX, KY = 15, 13        # control points (12 x 10 spans over the field)

def bspline_basis(n, k):
    """n samples across k control points (k - 3 spans): value, d/du rows (n x k)."""
    u = (np.arange(n) + 0.5) / n * (k - 3)
    i = np.minimum(np.floor(u).astype(int), k - 4); t = u - i
    B = np.zeros((n, k)); D = np.zeros((n, k))
    w = [(1 - t) ** 3 / 6, (3 * t**3 - 6 * t**2 + 4) / 6, (-3 * t**3 + 3 * t**2 + 3 * t + 1) / 6, t**3 / 6]
    dw = [-(1 - t) ** 2 / 2, (9 * t**2 - 12 * t) / 6, (-9 * t**2 + 6 * t + 3) / 6, t**2 / 2]
    for j in range(4):
        B[np.arange(n), i + j] = w[j]; D[np.arange(n), i + j] = dw[j]
    return B, D, (k - 3) / n

def front_model(P, geo):
    By, Dy, sy = geo["by"]; Bx, Dx, sx = geo["bx"]
    z = By @ P @ Bx.T
    dzx = By @ P @ Dx.T * (sx / geo["sp"]); dzy = Dy @ P @ Bx.T * (sy / geo["sp"])
    n = np.stack([-dzx, -dzy, np.ones_like(z)]); n /= np.linalg.norm(n, axis=0)
    phi = 0
    for q, sx_, sy_ in geo["src"]:
        r = np.stack([sx_ - geo["X"], sy_ - geo["Y"], -z]); d = np.linalg.norm(r, axis=0)
        phi = phi + q * np.maximum((n * r).sum(0) / d, 0.02) / (4 * math.pi * (d * PCCM) ** 2)
    # alpha_B EM_perp = Phi_n and EM_obs = EM_perp / n_z  (a thin layer seen at an angle)
    return np.log(phi / (ALPHA_B * np.maximum(n[2], 0.12))), z, n

def fit_front(EM, sp, cx, cy, ax, ay, lam=0.3):
    G = 2   # fit on 2x2 block means; sample i then sits at texel G i + (G - 1) / 2, i.e. at the
    #         same fraction (i + 0.5) / n of the field that bspline_basis assumes
    lEM = down(nd.gaussian_filter(np.log(EM), 8 / (SPAXEL_AS * F), mode="nearest"), G)
    ny, nx = lEM.shape
    X, Y = np.meshgrid((np.arange(nx) * G + (G - 1) / 2 - cx) * sp, (np.arange(ny) * G + (G - 1) / 2 - cy) * sp)
    geo = {"by": bspline_basis(ny, KY), "bx": bspline_basis(nx, KX), "sp": sp * G, "X": X, "Y": Y,
           "src": [(Q_C, 0.0, 0.0), (Q_2A, (ax - cx) * sp, (ay - cy) * sp)]}
    def res(p):
        lp, _, _ = front_model(p.reshape(KY, KX), geo)
        P = p.reshape(KY, KX)
        reg = np.concatenate([(P[2:] - 2 * P[1:-1] + P[:-2]).ravel(), (P[:, 2:] - 2 * P[:, 1:-1] + P[:, :-2]).ravel()])
        return np.concatenate([(lp - lEM).ravel() / math.sqrt(lEM.size), lam * reg])
    p0 = np.full(KY * KX, -0.2)
    sol = op.least_squares(res, p0, bounds=(-2.5, -0.02), x_scale=0.05, max_nfev=600)
    P = sol.x.reshape(KY, KX)
    lp, z, n = front_model(P, geo)
    return P, {"resid": lp - lEM, "z": z, "n": n, "X": X, "Y": Y, "G": G, "nfev": sol.nfev}

# ---------------------------------------------------------------------------------------------
# The photoevaporation flow off the front: isothermal, divergent, sonic at the front
# (Henney, Arthur & Garcia-Diaz 2005, ApJ 627, 813): n M R^2 = const, M^2/2 + ln n = const.
# ---------------------------------------------------------------------------------------------
def flow_profile(umax=3.0, n=4001):
    u = np.linspace(0, umax, n)
    M = np.array([1.0] + [op.brentq(lambda m: 0.5 * (1 - m * m) + math.log(m) + 2 * math.log(1 + t), 1 + 1e-12, 60)
                          for t in u[1:]])
    dens = 1 / ((1 + u) ** 2 * M)
    w = dens ** 2
    cdf = np.concatenate([[0], np.cumsum(0.5 * (w[1:] + w[:-1]) * np.diff(u))])
    g = cdf[-1]
    return u, M, dens, cdf / g, w / g, g

# ---------------------------------------------------------------------------------------------
def main():
    global F
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", required=True)
    ap.add_argument("--report", default=None)
    ap.add_argument("--downsample", type=int, default=F, help="MUSE spaxels per shipped texel (default 3: 0.6\")")
    a = ap.parse_args()
    F = a.downsample
    rep = a.report; lines = []
    def R(s=""): lines.append(s); log(s)
    if rep: os.makedirs(rep, exist_ok=True)

    raw = fetch_muse(a.cache)
    ed = fetch_edenhofer(a.cache)
    stripes = []
    c = clean(raw, stripes)

    # --- maps on the shipped grid -----------------------------------------------------------
    to_sb = 1e-20 / OMEGA   # per-spaxel flux (1e-20 erg/s/cm^2) -> erg/s/cm^2/sr
    ha = down(c["hb"], F) * HA_HB * to_sb
    oiii, nii, sii, oi = (down(c[k], F) * to_sb for k in ("oiii", "nii", "sii", "oi"))
    cmap, ne = down(c["c"], F), down(c["ne"], F)
    NY, NX = ha.shape
    sp = SPAXEL_AS * F * DIST_PC * math.pi / 180 / 3600          # pc per texel
    tex = lambda col, row: ((col + 0.5) / F - 0.5, (row + 0.5) / F - 0.5)
    cx, cy = tex(*sky_to_pix(*STARS[0][1:3])); ax, ay = tex(*sky_to_pix(*STARS[2][1:3]))
    R(f"# Opus_Orion_Nebula bake report\n\nGrid {NX} x {NY} texels of {SPAXEL_AS * F:.1f}\" = {sp * 1000:.2f} mpc at {DIST_PC:.0f} pc; field {NX * sp:.3f} x {NY * sp:.3f} pc.")

    R("Destriping (rms of the removed pattern, vertical / horizontal): " + ", ".join(f"{n} {v[0] * 100:.1f}% / {v[1] * 100:.1f}%" for n, v in stripes))

    # --- extinction: Edenhofer foreground vs the Veil ------------------------------------------
    r_pc = ed["radius"].astype(float); dr = np.gradient(r_pc); i0 = int(ed["index"])
    cum = np.cumsum(ed["mean"][:, i0] * dr); cstd = np.sqrt(np.cumsum((ed["std"][:, i0] * dr) ** 2))
    E_ZGR = lambda D: float(np.interp(D, r_pc, cum))
    # E of Zhang, Green & Rix 2023 matches SFD's E(B-V) (their Fig. 20: median residual ~0 to 0.5 mag)
    # and their curve matches CCM R_V = 3.1, so A_V ~ 3.1 E for the diffuse ISM in front of Orion
    # (to ~14%: SFD's own scale, Schlafly & Finkbeiner 2011). R_V = 5.5 is only the nebula's own dust.
    D_FG = 360.0   # foreground ends before the Orion A cloud (Grossschedl+2018: head at ~393 pc)
    Av_fg = 3.1 * E_ZGR(D_FG)
    c_fg = Av_fg * ccm89(486.1333, 3.1) / 2.5
    R(f"\n## Extinction\nEdenhofer+2024 toward theta1 Ori C (nside 256 NEST pixel {715136 + int(ed['index'])}): E_ZGR(<{D_FG:.0f} pc) = {E_ZGR(D_FG):.3f}, "
      f"E(<400) = {E_ZGR(400):.3f}, E(<450) = {E_ZGR(450):.3f}, E(<{r_pc[-1]:.0f}) = {cum[-1]:.3f} (+- {cstd[-1]:.3f}).")
    R(f"Foreground ISM A_V ~ {Av_fg:.2f} mag -> c(Hb)_fg = {c_fg:.3f}; MUSE total c(Hb): median {np.median(cmap):.3f} "
      f"(range {cmap.min():.2f}-{cmap.max():.2f}). The rest is put in the Veil.")
    # Where is the Orion cloud itself along this sightline? (an independent check on the distance)
    lo_, hi_ = E_ZGR(380), E_ZGR(470)
    wall = [float(np.interp(lo_ + f * (hi_ - lo_), cum, r_pc)) for f in (0.1, 0.5, 0.9)]
    block = np.cumsum(ed["mean"].astype(float) * dr[:, None], 0)[np.searchsorted(r_pc, D_FG)]
    R(f"Check: the dust wall of the Orion cloud on this sightline lies at {wall[1]:.0f} pc (10-90% of its extinction "
      f"between {wall[0]:.0f} and {wall[2]:.0f} pc): the molecular cloud behind the nebula, just beyond the stars' "
      f"388-414 pc parallax distances. The foreground E(<{D_FG:.0f} pc) is uniform over the 64 sightlines "
      f"({block.min():.3f}-{block.max():.3f}), so treating it as one screen is safe. Veil share of the median reddening: "
      f"{(1 - c_fg / np.median(cmap)) * 100:.0f}%.")
    c_veil = np.maximum(cmap - c_fg, 0.0)
    cq = np.round(np.clip(c_veil / 1.6, 0, 1) * 255) / 255 * 1.6
    R(f"Veil c(Hb): {(cmap < c_fg).mean() * 100:.2f}% of texels would be negative (clipped to 0); encoded error rms {np.std(cq - c_veil):.4f} "
      f"(max {np.abs(cq - c_veil).max():.4f}), i.e. < {np.abs(cq - c_veil).max() * 100 * math.log(10):.1f}% in Hbeta transmission.")
    for lam in sorted({l for g in LINES.values() for l, _ in g}):
        kb, kc = k_line(lam)
        R(f"  k({lam:.2f} nm) = A/A_Hb: used {kb:.3f}  (CCM89 R_V=5.5: {kc:.3f})")

    # --- the front ------------------------------------------------------------------------------
    EM = 4 * math.pi * ha / (HA_HB * EPS_HB)                          # cm^-5
    P, fr = fit_front(EM, sp, cx, cy, ax, ay)
    z = fr["z"]; nrm = fr["n"]
    rr = np.stack([-fr["X"], -fr["Y"], -z]); rr /= np.linalg.norm(rr, axis=0); lit = (nrm * rr).sum(0)
    resid = fr["resid"] / math.log(10)
    R(f"\n## Ionisation front (fitted)\nB-spline {KX} x {KY} control points, {fr['nfev']} evaluations. log EM residual "
      f"(8\" smoothing): rms {resid.std():.3f} dex, 5-95% {np.percentile(resid, 5):.3f} .. {np.percentile(resid, 95):.3f} dex.")
    zc = float(np.interp(0, fr["Y"][:, 0], z[:, np.argmin(abs(fr['X'][0]))]))
    R(f"Front below theta1 Ori C: {-zc:.3f} pc (published: ~0.2 pc at 440 pc, Wen & O'Dell 1995 / O'Dell+2009 -> "
      f"~0.18 pc at {DIST_PC:.0f} pc). Front depth range {-z.max():.3f} .. {-z.min():.3f} pc. Median tilt from the line of "
      f"sight {np.degrees(np.arccos(np.median(nrm[2]))):.1f} deg. Faces away from the stars (unlit): {(lit < 0).mean() * 100:.1f}% of the field.")

    # front on the full grid (for R0 and checks)
    By, Dy, syy = bspline_basis(NY, KY); Bx, Dx, sxx = bspline_basis(NX, KX)
    zf = By @ P @ Bx.T
    nz = 1 / np.sqrt(1 + (By @ P @ Dx.T * sxx / sp) ** 2 + (Dy @ P @ Bx.T * syy / sp) ** 2)

    # --- the flow -------------------------------------------------------------------------------
    u, M, dens, cdf, pdf, g = flow_profile()
    vH = CS_KMS * np.trapezoid(pdf * M, u)
    R(f"\n## Photoevaporation flow (Henney+2005 form; assumed isothermal, sonic at the front)\n"
      f"int (n/n0)^2 dh = g R0 with g = {g:.4f}; half of Halpha within h = {np.interp(0.5, cdf, u):.3f} R0, 90% within {np.interp(0.9, cdf, u):.3f} R0 (table cut at 3 R0).")
    vel = {k: down(c[k], F) for k in ("v_ha", "v_nii", "v_sii")}
    e = 6; core = np.s_[e:-e, e:-e]
    bright = ha[core] > np.percentile(ha[core], 60)
    dN = np.median((vel["v_nii"] - vel["v_ha"])[core][bright]); dS = np.median((vel["v_sii"] - vel["v_nii"])[core][bright])
    nzc = float(np.median(nz[core][bright]))
    pred = (vH - CS_KMS) * nzc
    R(f"Measured centroids (brightest 40%): [N II]-Halpha = {dN:+.2f} km/s, [S II]-[N II] = {dS:+.2f} km/s.")
    R(f"Prediction if [N II] comes from the front itself: (<v>_Ha {vH:.2f} - c_s {CS_KMS:.1f}) x n_z {nzc:.2f} = {pred:+.2f} km/s "
      f"(measured {dN:+.2f}): the flow model passes. [S II] lies {dS:.2f} km/s further toward the cloud's velocity: it is "
      f"emitted partly inside the accelerating ionisation front, below the sonic point.")
    lam_lim = None
    for lamN in np.geomspace(1e-4, 0.3, 200):
        v = CS_KMS * np.trapezoid(pdf * np.exp(-u / lamN) * M, u) / np.trapezoid(pdf * np.exp(-u / lamN), u)
        if (vH - v) * nzc < dN - 1.0: lam_lim = lamN; break
    R(f"An N+ zone thicker than {lam_lim:.4f} R0 would lower the offset by > 1 km/s: [N II], [S II] and [O I] are drawn as a sheet on the front.")
    pix_pred = (vH - CS_KMS) * nz
    vres = (vel["v_nii"] - vel["v_ha"]) - pix_pred
    R(f"Per-texel [N II]-Halpha residual (measured - predicted): median {np.median(vres[core]):+.2f}, rms {vres[core].std():.2f} km/s.")

    # R0 from the emission measure and the [S II] density, with one clumping factor fitted to the
    # geometric curvature of the fitted front.
    EMperp = EM * nz
    R0raw = EMperp / (g * ne ** 2) / PCCM                              # pc
    zxx = By @ P @ (bspline_second(NX, KX)).T * (sxx / sp) ** 2
    zyy = bspline_second(NY, KY) @ P @ Bx.T * (syy / sp) ** 2
    kappa = 0.5 * (zxx + zyy) * nz ** 3                                 # mean curvature (small-slope form)
    concave = kappa[core] > 1e-3
    Rgeom = np.median(1 / kappa[core][concave])
    phi = Rgeom / np.median(R0raw[core])
    R0 = np.clip(phi * R0raw, 0.005, 1.5)
    # An independent check: [Cl III] traces denser gas nearer the front than [S II] does.
    ncl = down(c["ne_cl"], F); okcl = down(c["ne_cl_ok"].astype(float), F) > 0.9
    sel = np.zeros_like(okcl); sel[core] = True
    sel &= okcl & (ha > np.percentile(ha[core], 50))
    phi_cl = float(np.median(((ne / ncl) ** 2)[sel]))
    R(f"\nR0 from EM_perp / (g n_e^2) with n_e from [S II]: median {np.median(R0raw[core]):.3f} pc. Mean curvature radius of the "
      f"fitted front where concave ({concave.mean() * 100:.0f}% of the field): median {Rgeom:.3f} pc.")
    R(f"Fitted clumping factor phi = {phi:.3f} (R0 = phi R0_raw; equivalently the flow's front density is n_[S II] / sqrt(phi) "
      f"= {1 / math.sqrt(phi):.2f} n_[S II]). R0 used: median {np.median(R0):.3f} pc, 5-95% {np.percentile(R0, 5):.3f} .. {np.percentile(R0, 95):.3f}.")
    R(f"Check: using the [Cl III] density instead (bright half of the field, {sel.sum()} texels with good [Cl III]): n_[Cl III] / n_[S II] = "
      f"{np.median((ncl / ne)[sel]):.2f} (16-84% {np.percentile((ncl / ne)[sel], 16):.2f}-{np.percentile((ncl / ne)[sel], 84):.2f}), i.e. phi = {phi_cl:.3f}. "
      f"The two independent estimates of the layer thickness differ by {phi_cl / phi:.2f}x: R0 is known to within that factor.")

    # --- Check: the Bright Bar is a nearly edge-on piece of front, so across it the ions are laid
    #     out on the sky by height. Full-resolution maps, rotated so the [S II] ridge is level.
    best = None
    for ang in np.arange(-36.0, -20.0, 0.5):
        prof = nd.rotate(np.log(c["sii"]), -ang, reshape=False, order=1, mode="nearest")[:, 500:1300].mean(1)
        sharp = nd.gaussian_filter1d(prof, 2).max() - np.median(prof)
        if best is None or sharp > best[0]: best = (sharp, ang)
    ang = best[1]
    rot = {k: nd.rotate(c[k], -ang, reshape=False, order=1, mode="nearest")[:, 400:1200].mean(1) for k in ("hb", "oiii", "nii", "sii", "oi")}
    y0 = int(np.argmax(nd.gaussian_filter1d(rot["sii"], 3)[200:1300]) + 200)
    mpc = SPAXEL_AS * DIST_PC * math.pi / 180 / 3600 * 1000
    offs = {k: (int(np.argmax(nd.gaussian_filter1d(v[y0 - 120:y0 + 121], 2))) - 120) * mpc for k, v in rot.items()}
    R("\nCheck, the Bright Bar seen edge-on (PA of the ridge in the pixel frame {:.1f} deg; + = toward the Trapezium): peaks of "
      .format(ang) + ", ".join(f"{k} {v:+.0f}" for k, v in sorted(offs.items(), key=lambda t: t[1])) + " mpc. "
      f"The ions are layered as the model has them (O0 -> S+/N+ -> H+/O++), across {max(offs.values()) - min(offs.values()):.0f} mpc. "
      f"The model draws the low ions as a sheet at the base of the flow; at the orbit's widest yaw (4.3 deg) that "
      f"misplaces them by at most {(max(offs.values()) - min(offs.values())) * math.tan(math.radians(4.3)):.0f} mpc "
      f"({(max(offs.values()) - min(offs.values())) * math.tan(math.radians(4.3)) / (sp * 1000):.1f} texels).")

    # --- [S II] doublet from density (Sanders+2016 eq. 6, 10^4 K) -------------------------------
    r_sii = 0.4315 * (2107 + ne) / (627.1 + ne)

    # --- encode ---------------------------------------------------------------------------------
    def lohi(x): return float(np.log10(np.percentile(x, 0.01))), float(np.log10(np.percentile(x, 99.995)))
    def enc_log(x, lo, hi): return np.clip(np.round((np.log10(x) - lo) / (hi - lo) * 255), 0, 255).astype(np.uint8)
    def enc_lin(x, lo, hi): return np.clip(np.round((x - lo) / (hi - lo) * 255), 0, 255).astype(np.uint8)
    rng = {k: lohi(v) for k, v in (("ha", ha), ("oiii", oiii), ("nii", nii), ("sii", sii), ("oi", oi))}
    rng["R0"] = (math.log10(0.005), math.log10(1.5))
    blockA = np.stack([enc_log(ha, *rng["ha"]), enc_log(oiii, *rng["oiii"]), enc_log(nii, *rng["nii"]), enc_log(sii, *rng["sii"])], -1)
    blockB = np.stack([enc_log(oi, *rng["oi"]), enc_lin(c_veil, 0, 1.6), enc_log(R0, *rng["R0"]), enc_lin(r_sii, 0.4, 1.5)], -1)
    # FORMAT: rows 0..NY-1 = block A, NY..2NY-1 = block B; within each block row 0 is the NORTH edge.
    img = np.concatenate([blockA[::-1], blockB[::-1]], 0)
    open(DATA, "wb").write(np.ascontiguousarray(img).tobytes())
    R(f"\n## Shipped data\n{os.path.relpath(DATA, ROOT)}: {NX} x {2 * NY} RGBA8 ({os.path.getsize(DATA) / 1e6:.2f} MB), sha256 "
      f"{hashlib.sha256(open(DATA, 'rb').read()).hexdigest()[:16]}...")
    for k, v, (lo, hi) in (("ha", ha, rng["ha"]), ("oiii", oiii, rng["oiii"]), ("nii", nii, rng["nii"]), ("sii", sii, rng["sii"]), ("oi", oi, rng["oi"])):
        dec = 10 ** (enc_log(v, lo, hi) / 255 * (hi - lo) + lo)
        q = np.log10(dec / v)
        R(f"  {k:5s}: log10 range {lo:.2f} .. {hi:.2f} (step {(hi - lo) / 255 * 100 * math.log(10):.1f}%), encoding error rms {q.std():.4f} dex")

    # --- colours ---------------------------------------------------------------------------------
    M_XYZ_RGB = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    grp_xyz = {}
    for gname, ls in LINES.items():
        grp_xyz[gname] = [(lam, (rat if rat is not None else -1.0), wyman_cmf(lam), k_line(lam)[0]) for lam, rat in ls]

    # --- report images --------------------------------------------------------------------------
    if rep:
        png(os.path.join(rep, "front_resid.png"), 0.5 + resid / 0.6)
        png(os.path.join(rep, "front_depth.png"), (z - z.min()) / (z.max() - z.min()))
        png(os.path.join(rep, "vel_resid_nii_ha.png"), 0.5 + vres / 12)
        png(os.path.join(rep, "R0.png"), (np.log10(R0) + 2.3) / 2.5)
        png(os.path.join(rep, "c_veil.png"), c_veil / 1.4)
        open(os.path.join(rep, "report.md"), "w").write("\n".join(lines) + "\n")

    # --- stars ---------------------------------------------------------------------------------
    lam = np.arange(360.0, 831.0, 1.0)
    cmf = np.array([wyman_cmf(l) for l in lam])                      # (n, 3)
    def planck(T):                                                    # B_lambda, nm
        x = 1.4387769e7 / (lam * T)
        return 1 / (lam ** 5 * np.expm1(np.minimum(x, 700)))
    def xyz_from_V(V, T):    # F_lambda(550 nm) = 3.63e-9 10^(-0.4 V) erg/s/cm^2/A (Bessell 1998)
        b = planck(T); b *= 3.63e-8 * 10 ** (-0.4 * V) / np.interp(550.0, lam, b)
        return (b[:, None] * cmf).sum(0)                              # erg/s/cm^2 x CMF
    def xyz_from_L(Lsun, T):
        Fbol = Lsun * 3.828e33 / (4 * math.pi * (DIST_PC * PCCM) ** 2)
        b = planck(T); b *= Fbol / (b.sum())
        return (b[:, None] * cmf).sum(0)
    stars = []
    for name, ra, dec, V, T, _ in STARS:
        col, row = sky_to_pix(ra, dec); tx, ty = tex(col, row)
        stars.append(((tx - cx) * sp, (ty - cy) * sp, 0.0, xyz_from_V(V, T), name))
    # The cluster's fainter members: statistical (see the theme header). Fixed seed.
    rng_ = np.random.default_rng(135)
    rgrid = np.linspace(0, 4.0, 4001); rc = 0.2
    dens3 = (1 + (rgrid / rc) ** 2) ** -1.1                           # Da Rio+2014: r^-2.2 outside a 0.2 pc core
    cdf3 = np.cumsum(dens3 * rgrid ** 2); cdf3 /= cdf3[-1]
    Nbig = 400000
    rr3 = np.interp(rng_.random(Nbig), cdf3, rgrid)
    mu = rng_.uniform(-1, 1, Nbig); ph = rng_.uniform(0, 2 * math.pi, Nbig); st_ = np.sqrt(1 - mu * mu)
    q = math.sqrt(0.7)                                                 # ellipticity 0.3, long axis N-S (assumed)
    P3 = np.stack([rr3 * st_ * np.cos(ph) * q, rr3 * st_ * np.sin(ph) / q, rr3 * mu * q], 1)
    frac2 = (np.hypot(P3[:, 0], P3[:, 1]) < 2.0).mean()
    Ntot = 4323 / frac2                                                # N(<2 pc) = 4323 (Da Rio+2014, all sources)
    box = (np.abs(P3[:, 0] - VIEW_GUESS[0]) < 0.36) & (np.abs(P3[:, 1] - VIEW_GUESS[1]) < 0.26) & (np.abs(P3[:, 2]) < 0.8)
    nbox = int(round(Ntot * box.mean())); idx = np.flatnonzero(box)[:nbox]
    # Kroupa 2001 masses, 0.08-3 Msun (brighter stars in this field are the real ones above)
    def kroupa(n):
        m = np.empty(0)
        while m.size < n:
            x = np.exp(rng_.uniform(math.log(0.08), math.log(3.0), 4 * n))
            w = np.where(x < 0.5, (x / 0.5) ** -1.3, (x / 0.5) ** -2.3) * x   # dN/dlnM
            m = np.concatenate([m, x[rng_.random(x.size) < w / w.max()]])
        return m[:n]
    mass = kroupa(idx.size)
    Lsun = 1.6 * mass ** 1.5                                           # ~1 Myr pre-main sequence (rough, assumed)
    Teff = np.interp(mass, [0.08, 0.1, 0.3, 0.5, 1.0, 2.0, 3.0], [2700, 2900, 3400, 3700, 4300, 5000, 7000])
    for (x, y, zz), Ls, T in zip(P3[idx], Lsun, Teff):
        stars.append((x, y, zz, xyz_from_L(Ls, T), "cluster"))
    R(f"\n## Stars\n{len(STARS)} real (SIMBAD) + {idx.size} statistical cluster members in the box (ONC model normalised to N(<2 pc) = 4323).")
    if len(stars) > 1024: raise SystemExit("too many stars for one threadgroup pass")

    # --- exposure: the nebula as seen from Earth -------------------------------------------------
    def line_y(S, lam_nm, k): return S * wyman_cmf(lam_nm)[1] * 10 ** (-cmap * k)
    Ylum = (line_y(ha, 656.2819, 0.780) + line_y(ha / HA_HB, 486.1333, 1.0) + line_y(oiii, 500.6843, 0.978)
            + line_y(oiii / 2.98, 495.8911, 0.978) + line_y(nii, 658.345, 0.778) + line_y(sii * (1 + r_sii), 673.0815, k_line(673.0815)[0])
            + line_y(oi, 630.0304, k_line(630.0304)[0]))
    exposure = 1.0 / np.percentile(Ylum, 99.95)                       # white point: the brightest 0.05%
    stretch = 2.5 * np.median(Ylum) * exposure                         # asinh knee
    sho = [np.percentile(v * 10 ** (-cmap * k), 99.7) for v, k in ((sii * (1 + r_sii), k_line(673.0815)[0]), (ha, 0.780), (oiii, 0.978))]
    R(f"Exposure: Earth-view luminance Y p50 {np.median(Ylum):.3g}, p99.7 {np.percentile(Ylum, 99.7):.3g} erg/s/cm2/sr (x CMF) -> EXPOSURE {exposure:.4g}, STRETCH {stretch:.4g}")

    # --- the Metal constants block -------------------------------------------------------------
    out = []
    W = out.append
    W("// BEGIN BAKED (tools/orion_bake/bake.py writes this block; do not edit by hand)")
    W(f"constant uint DATA_W = {NX}u, DATA_H = {NY}u;          // one block; the file holds two")
    W(f"constant float TEXEL_PC = {sp:.7f}f;                     // texel size at {DIST_PC:.0f} pc")
    W(f"constant float DIST_PC = {DIST_PC:.1f}f;")
    W(f"constant float EXPOSURE = {exposure:.6g}f;                   // chosen: Earth-view p99.95 luminance = white")
    W(f"constant float STRETCH = {stretch:.6g}f;                     // chosen: asinh knee at 2.5 x the median luminance")
    W(f"constant float3 SHO_NORM = float3({sho[0]:.6g}f, {sho[1]:.6g}f, {sho[2]:.6g}f);   // Hubble palette channel scales")
    W("constant float3 STAR_K = float3(" + ", ".join(f"{k_line(l)[1]:.4f}f" for l in (600.0, 555.0, 450.0)) + ");   // A/A_Hb for star light in X, Y, Z")
    W(f"constant float2 STAR_C_TEX = float2({cx:.3f}f, {cy:.3f}f);   // theta1 Ori C, texels from the west-south corner")
    W(f"constant float FLOW_G = {g:.6f}f;")
    W(f"constant float FRONT_ZMIN = {zf.min():.4f}f, FRONT_ZMAX = {zf.max():.4f}f;   // pc, over the field")
    W("constant float2 LOG_RANGE[6] = {  // log10 of erg/s/cm^2/sr: Halpha, [O III], [N II], [S II] 6731, [O I] 6300, R0 (pc)")
    W("    " + ", ".join(f"float2({rng[k][0]:.5f}f, {rng[k][1]:.5f}f)" for k in ("ha", "oiii", "nii", "sii", "oi", "R0")) + "};")
    W(f"constant float C_FG = {c_fg:.4f}f;              // c(Hb) of the diffuse ISM in front (Edenhofer+2024)")
    W(f"constant float FRONT_P[{KY}][{KX}] = {{          // B-spline control points: front depth z (pc, toward us = +)")
    for row in P: W("    {" + ", ".join(f"{v:.5f}f" for v in row) + "},")
    W("};")
    NT = 64
    uu = np.linspace(0, 3.0, NT)
    W(f"constant float FLOW_CDF[{NT}] = {{   // share of a flow line's emission below h = 3 R0 i / {NT - 1}")
    W("    " + ", ".join(f"{v:.6f}f" for v in np.interp(uu, u, cdf)) + "};")
    W(f"constant float FLOW_PDF[{NT}] = {{   // d CDF / d(h/R0)")
    W("    " + ", ".join(f"{v:.6f}f" for v in np.interp(uu, u, pdf)) + "};")
    W("struct Line { float3 xyz; float ratio; float k; };  // CIE XYZ per unit energy, ratio to the mapped line, A/A_Hb")
    for gname, ls in grp_xyz.items():
        W(f"constant Line L_{gname.upper()}[{len(ls)}] = {{")
        for lam, rat, xyz, k in ls:
            W(f"    {{float3({xyz[0]:.5f}f, {xyz[1]:.5f}f, {xyz[2]:.5f}f), {rat:.5f}f, {k:.4f}f}},   // {lam:.3f} nm")
        W("};")
    W(f"constant float A_V_PER_A_HB = {1 / ccm89(486.1333):.4f}f;   // CCM89 R_V = 5.5")
    W(f"constant uint N_STARS = {len(stars)}u;")
    W("constant float4 STARS[N_STARS] = {   // x, y, z (pc from theta1 Ori C: west, north, toward us); first 12 real")
    for i in range(0, len(stars), 4):
        W("    " + " ".join(f"float4({x:.4f}f, {y:.4f}f, {zz:.4f}f, 0),{'  // ' + nm if nm != 'cluster' else ''}" for x, y, zz, _, nm in stars[i:i + 4]))
    W("};")
    W("constant float4 STAR_XYZ[N_STARS] = {   // CIE XYZ flux, erg/s/cm2 x CMF, before extinction")
    for i in range(0, len(stars), 4):
        W("    " + " ".join(f"float4({v[0]:.4e}f, {v[1]:.4e}f, {v[2]:.4e}f, 0)," for _, _, _, v, _ in stars[i:i + 4]))
    W("};")
    W("// END BAKED")
    src = open(THEME).read()
    new = re.sub(r"// BEGIN BAKED.*?// END BAKED", "\n".join(out), src, flags=re.S)
    new = re.sub(r"// @argus state \d+x\d+", f"// @argus state {NX}x{3 * NY + 1}", new)
    new = re.sub(r"// @argus data (\S+) \d+x\d+", lambda m: f"// @argus data {m.group(1)} {NX}x{2 * NY}", new)
    open(THEME, "w").write(new)
    log("wrote", THEME, "and", DATA)

def bspline_second(n, k):
    u = (np.arange(n) + 0.5) / n * (k - 3)
    i = np.minimum(np.floor(u).astype(int), k - 4); t = u - i
    S = np.zeros((n, k))
    ddw = [(1 - t), (3 * t - 2), (-3 * t + 1), t]
    for j in range(4): S[np.arange(n), i + j] = ddw[j]
    return S

if __name__ == "__main__":
    main()

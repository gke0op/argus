#!/usr/bin/env python3
"""Generate the quasar family from themes/Majestic_Glutton.zig.

Majestic_Glutton.zig (the owner's artwork, modelled on H1821+643) is the one source of the engine.
Each real quasar is the same
file with its own object paragraph, spin, mass and Eddington ratio, test bounds and ledger ids.
Edit the source, then run `make quasars`; `make test` runs `--check` and fails on a stale file.

    python3 tools/gen_quasars.py          # write every generated theme
    python3 tools/gen_quasars.py --check  # exit 1 if any generated theme differs
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The source theme's name (file stem). Renaming it (e.g. to "Quasar") also needs a `git mv` of the
# file and the same rename inside it: its header title, LEDGER_PREFIX and claim ids (lower case).
SOURCE_NAME = "Majestic_Glutton"
SRC = os.path.join(ROOT, "themes", SOURCE_NAME + ".zig")
SOURCE_ID = SOURCE_NAME.lower() + "."  # its ledger id prefix
SOURCE_TITLE = SOURCE_NAME.replace("_", " ").upper()  # its header title

# Each entry: the object's paragraph (replaces Majestic Glutton's), the parameters, and the bounds of
# its own disk claims. `edd` is the snapshot's ISCO inflow (Mdot_Edd units); the snapshot
# radiates ~0.54 of a steady disk at that inflow, so edd ~ lambda / 0.54 (tuned so the test's
# absolute L/L_Edd lands on lambda).
QUASARS = [
    {
        "file": "Cygnus_A.zig",
        "title": "CYGNUS A",
        "slug": "cygnus_a",
        # Computed by this theme's disk solution; its "computed disk" test checks them (HEADER).
        "computed": {"pt_25": 0.87, "pt_5": 0.51, "lum": 0.55, "l_edd": 0.0125, "t_peak": 37_700.0, "r_peak": 3.41, "h_over_r": 0.004},
        "spin": "0.9",
        "spin_note": "Spin a = 0.9 M (unmeasured for Cygnus A: a choice), inclination 88 deg (nearly edge-on).",
        "mass": "2.5e9",
        "mass_note": "a 2.5e9 Msun hole (Tadhunter et al. 2003)",
        "edd": "0.023",
        "lam": 0.012,
        "lam_ref": "lambda ~ 0.012: L_bol 1e12 Lsun (Privon et al. 2012) / L_Edd at 2.5e9 Msun",
        "t_lo": 30_000.0,
        "t_hi": 45_000.0,
        "para": """\
// Modelled on Cygnus A (3C 405), the archetypal powerful radio galaxy and a hidden quasar: its
// dusty torus blocks our direct view of the nucleus, which is why it is classed a radio galaxy,
// and its jets and radio lobes lie far outside this view. Its black hole, 2.5 +- 0.7e9 Msun, is
// weighed by the gas dynamics of its near-nuclear regions (Tadhunter et al. 2003, MNRAS 342,
// 861); its hidden quasar's bolometric luminosity, ~1e12 Lsun from the torus-reprocessed
// infrared (Privon et al. 2012, ApJ 747, 46), puts it at lambda ~ 0.012 of Eddington: a thin disk
// near the low end of the radiatively efficient range. Its spin is unmeasured (the torus hides
// the inner disk's X-ray reflection): a = 0.9 here is a choice. This camera sits at 88 deg.
""",
    },
    {
        "file": "J0834.zig",
        "title": "J0834",
        "slug": "j0834",
        # Computed by this theme's disk solution; its "computed disk" test checks them (HEADER).
        "computed": {"pt_25": 0.82, "pt_5": 0.47, "lum": 0.57, "l_edd": 0.040, "t_peak": 64_600.0, "r_peak": 1.96, "h_over_r": 0.021},
        "spin": "0.99",
        "spin_note": "Spin a = 0.99 M (Piotrovich et al. 2024's models), inclination 88 deg (nearly edge-on).",
        "mass": "3.2e9",
        "mass_note": "a 3.2e9 Msun hole (Piotrovich et al. 2024, Table 1)",
        "edd": "0.067",
        "lam": 0.040,
        "lam_ref": "lambda = 0.040 (log -1.402; Piotrovich, Buliga & Natsvlishvili 2024, Table 1)",
        "t_lo": 55_000.0,
        "t_hi": 75_000.0,
        "para": """\
// Modelled on F2MS J0834+3506 (z ~ 0.47), a dust-reddened "red quasar" from the FIRST-2MASS
// survey, thought to be young and emerging from its dust. Its literature mass, 3.2e9 Msun
// (log 9.502), and Eddington ratio, 0.040 (log -1.402), are as compiled by Piotrovich, Buliga &
// Natsvlishvili (2024, Astron. Nachr., arXiv:2410.04851, Table 1): a thin disk. Their
// radiative-efficiency models give a near-extreme spin, a = 0.990-0.998 across three models
// (each assuming a thin disk), with inclinations of 50-70 deg found by stepping from 45 deg, not
// measured. a = 0.99 here follows those models; this camera sits at 88 deg (a choice).
""",
    },
    {
        "file": "PG1426.zig",
        "title": "PG 1426",
        "slug": "pg1426",
        # Computed by this theme's disk solution; its "computed disk" test checks them (HEADER).
        "computed": {"pt_25": 0.87, "pt_5": 0.51, "lum": 0.55, "l_edd": 0.0244, "t_peak": 56_000.0, "r_peak": 3.41, "h_over_r": 0.008},
        "spin": "0.9",
        "spin_note": "Spin a = 0.9 M (inside PG 1426+015's a* >~ 0.7), inclination 88 deg (nearly edge-on).",
        "mass": "1.0e9",
        "mass_note": "a 1.0e9 Msun hole (reverberation mapped)",
        "edd": "0.045",
        "lam": 0.024,
        "lam_ref": "lambda ~ 0.024 from its SED (Vasudevan & Fabian 2009, as compiled)",
        "t_lo": 45_000.0,
        "t_hi": 65_000.0,
        "para": """\
// Modelled on PG 1426+015 (z ~ 0.09), a "bare" quasar with an unobscured view of its nucleus and
// the most massive reverberation-mapped black hole: log M = 9.01 (+0.11 / -0.16) (Walton et al.
// 2025, arXiv:2509.13411). Its X-ray reflection gives a* >~ 0.7 (Walton et al. 2025,
// preliminary: it assumes reflection dominates the soft excess); a = 0.9 here, inside that
// range. Its Eddington ratio, ~0.024 from its SED (Vasudevan & Fabian 2009, as compiled; not
// re-checked here), makes it a thin disk. This camera sits at 88 deg (a choice).
""",
    },
]

PARA_START = "// Majestic Glutton is an artwork:"
PARA_END = "// Audited independently"


def rep(s, a, b, count=1):
    n = s.count(a)
    if n != count:
        raise SystemExit(f"gen_quasars: expected {count} of {a[:70]!r} in {SOURCE_NAME}.zig, found {n}")
    return s.replace(a, b)


def isco(a):
    z1 = 1 + (1 - a * a) ** (1 / 3) * ((1 + a) ** (1 / 3) + (1 - a) ** (1 / 3))
    z2 = math.sqrt(3 * a * a + z1 * z1)
    return 3 + z2 - math.sqrt((3 - z1) * (3 + z1 + 2 * z2))


def colour_factor(t):
    return 1.0 if t <= 3.0e4 else (t / 3.0e4) ** 0.82 if t < 1.0e5 else (72.0 / (t * 8.617333e-8)) ** (1 / 9)


def mfmt(x):
    """A radius in M as the header quotes it."""
    return f"{x:.0f}" if x >= 10 else f"{x:.1f}"


def computed_text(s, q):
    """Replace every value the source header quotes from H1821+643's solution with this object's."""
    c = q["computed"]
    a = float(q["spin"])
    m = float(q["mass"])
    ri = isco(a)
    f_peak = colour_factor(c["t_peak"])
    t_m = 4.925491e-6 * m  # seconds per M
    p_isco = 2 * math.pi * (ri ** 1.5 + a)  # prograde orbit period, M
    p_6 = 2 * math.pi * (6 ** 1.5 + a)
    tk = f"{round(c['t_peak'], -3):,.0f}"
    s = rep(s, "flux reverses (5 ISCO radii, 19 M), so the flux drops below Page-Thorne (0.89 at 9 M, 0.55\n//    at 19 M). Its recipe (ring and snapshot) scales with the ISCO (3.75 M at this spin); the",
            f"flux reverses (5 ISCO radii, {mfmt(5 * ri)} M), so the flux drops below Page-Thorne ({c['pt_25']:.2f} at {mfmt(2.5 * ri)} M, {c['pt_5']:.2f}\n//    at {mfmt(5 * ri)} M). Its recipe (ring and snapshot) scales with the ISCO ({ri:.2f} M at this spin); the")
    s = rep(s, "Scaled to a 4e9 solar-mass hole whose\n//    ISCO accretion rate is 36% of Eddington's (alpha = 0.1); the snapshot shines at 0.54 of\n//    that (its inflow stops at 5 ISCO radii), i.e. ~0.2 L_Edd as measured. Peak ~50,000 K at\n//    5.7 M (radiation-pressure supported, H/r ~ 0.05 there), blue-white, as real\n//    thin disks around such holes are.",
            f"Scaled to a {q['mass']} solar-mass hole whose\n//    ISCO accretion rate is {round(float(q['edd']) * 100, 1)}% of Eddington's (alpha = 0.1); the snapshot shines at {c['lum']:.2f} of\n//    that (its inflow stops at 5 ISCO radii), i.e. ~{c['l_edd']:g} L_Edd, the object's. Peak ~{tk} K at\n//    {c['r_peak']:.1f} M (H/r ~ {c['h_over_r']:g} there: thin), as real\n//    thin disks around such holes are.")
    s = rep(s, "~1.5 at this disk's 50,000 K peak", f"~{f_peak:.1f} at this disk's {tk} K peak")
    s = rep(s, "one ISCO orbit takes ~5 s on screen, one at r = 6 M ~10 s (in reality ~11\n//    and ~22 days for this 4e9 solar-mass hole).",
            f"one ISCO orbit takes ~{p_isco / 10:.0f} s on screen, one at r = 6 M ~{p_6 / 10:.0f} s (in reality ~{p_isco * t_m / 86400:.0f}\n//    and ~{p_6 * t_m / 86400:.0f} days for this {q['mass']} solar-mass hole).")
    fainter = 1e12 * (c["t_peak"] / 49935.0) ** 4
    s = rep(s, "but next to a 50,000 K disk they are ~1e12 times fainter,",
            f"but next to a {tk} K disk they are ~{fainter:.0e} times fainter,".replace("e+", "e"))
    s = rep(s, "// The sky is black: next to a 50,000 K disk everything else (the host galaxy's stars, the cluster's\n// galaxies) is ~1e12 times fainter,",
            f"// The sky is black: next to a {tk} K disk everything else (the host galaxy's stars, its\n// neighbours) is ~{fainter:.0e} times fainter,".replace("e+", "e"))
    hdr_old = s[s.index("pub const HEADER = struct {"):s.index("};", s.index("pub const HEADER = struct {")) + 2]
    hdr_new = ("pub const HEADER = struct {\n"
               f"    pub const r_isco: f64 = {ri:.2f}; // M\n"
               f"    pub const pt_25: f64 = {c['pt_25']}; // F / F_PT at 2.5 ISCO radii\n"
               f"    pub const pt_5: f64 = {c['pt_5']}; // F / F_PT at 5 ISCO radii\n"
               f"    pub const lum: f64 = {c['lum']}; // snapshot L / steady Page-Thorne L at the same inflow\n"
               f"    pub const l_edd: f64 = {c['l_edd']}; // L / L_Edd\n"
               f"    pub const t_peak: f64 = {c['t_peak']:.1f}; // K\n"
               f"    pub const r_peak: f64 = {c['r_peak']}; // M\n"
               f"    pub const h_over_r: f64 = {c['h_over_r']}; // at the peak\n"
               f"    pub const f_peak: f64 = {f_peak:.2f}; // colour correction at the peak\n"
               "};")
    return s.replace(hdr_old, hdr_new)


def generate(src, q):
    i = src.index(PARA_START)
    j = src.index(PARA_END)
    s = src[:i] + q["para"] + src[j:]
    s = rep(s, f"// {SOURCE_TITLE} // themes/{SOURCE_NAME}.zig",
            f"// {q['title']} // themes/{q['file']}\n"
            f"// GENERATED from themes/{SOURCE_NAME}.zig by tools/gen_quasars.py: edit the source, then\n"
            "// `make quasars`. Same engine; this object's paragraph, spin, mass and Eddington ratio.")
    s = rep(s, "//  * Spin a = 0.62 M (H1821+643's measured value, above), inclination 88 deg (nearly edge-on).",
            f"//  * {q['spin_note']}")
    s = rep(s, "mass 4e9 Msun, ISCO accretion rate 36% of Eddington",
            f"mass {q['mass']} Msun, ISCO accretion rate {round(float(q['edd']) * 100, 1)}% of Eddington")
    s = rep(s, "at the centre of the giant galaxy hosting\n//    H1821+643 inside its cluster, the sky holds the host's stars and the cluster's galaxies,",
            "in the heart of its host galaxy, the sky holds\n//    the host's stars and its neighbours' galaxies,")
    s = rep(s, "pub const SPIN: f64 = 0.62; // H1821+643's measured spin (Sisk-Reynes et al. 2022; see header)",
            f"pub const SPIN: f64 = {q['spin']}; // see header")
    s = rep(s, "pub const BH_MASS_SUN: f64 = 4.0e9; // a quasar-class supermassive hole",
            f"pub const BH_MASS_SUN: f64 = {q['mass']}; // {q['mass_note']}")
    s = rep(s, "pub const EDD_RATIO: f64 = 0.36;", f"pub const EDD_RATIO: f64 = {q['edd']};")
    s = rep(s, '"a = 0.62, 4e9 Msun, alpha = 0.1, ISCO inflow 0.36 Mdot_Edd,',
            f'"a = {q["spin"]}, {q["mass"]} Msun, alpha = 0.1, ISCO inflow {q["edd"]} Mdot_Edd,')
    s = rep(s, '"H1821+643: L ~ 0.2 L_Edd at 4e9 Msun (Fukuchi, Ichikawa et al. 2022)", cond, "T_peak (K)", d.t_peak, 40_000.0, 60_000.0);',
            f'"{q["lam_ref"]}", cond, "T_peak (K)", d.t_peak, {q["t_lo"]:.1f}, {q["t_hi"]:.1f});')
    s = rep(s, '"The snapshot shines at H1821+643\'s measured Eddington ratio", "lambda_Edd = 0.18 (full SED; Fukuchi, Ichikawa et al. 2022)", cond, "L / L_Edd: cgs flux integrated over both faces (flat area)", d.l_edd_abs, 0.17, 0.23);',
            f'"The snapshot shines at the object\'s Eddington ratio", "{q["lam_ref"]}", cond, "L / L_Edd: cgs flux integrated over both faces (flat area)", d.l_edd_abs, {q["lam"] * 0.85:.4f}, {q["lam"] * 1.15:.4f});')
    s = s.replace(f'"zig test themes/{SOURCE_NAME}.zig"', f'"zig test themes/{q["file"]}"')
    s = s.replace('"' + SOURCE_ID, f'"{q["slug"]}.')
    s = s.replace("a = 0.62", f"a = {q['spin']}")
    return computed_text(s, q)


def main():
    check = "--check" in sys.argv
    src = open(SRC).read()
    stale = []
    for q in QUASARS:
        out = generate(src, q)
        path = os.path.join(ROOT, "themes", q["file"])
        cur = open(path).read() if os.path.exists(path) else None
        if cur == out:
            continue
        if check:
            stale.append(q["file"])
        else:
            open(path, "w").write(out)
            print(f"gen_quasars: wrote themes/{q['file']}")
    if stale:
        print("gen_quasars: stale (run `make quasars`): " + ", ".join(stale), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

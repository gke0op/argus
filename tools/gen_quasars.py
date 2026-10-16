#!/usr/bin/env python3
"""Generate the quasar family from tools/quasar_template.zig.

The template is the one source of the engine, with {{TOKENS}} where each quasar differs: its
paragraph, spin, mass, Eddington ratio, the computed values its header quotes, test bounds and
ledger ids. Edit the template, then run `make quasars`; `make test` runs `--check` and fails on
a stale theme.

Local, unpublished quasars: any tools/local/*.json holding an entry with the same keys as
QUASARS below is generated too (into themes/, untracked). Keep such files out of the repository
with .git/info/exclude (not .gitignore, which is published).

    python3 tools/gen_quasars.py          # write every generated theme
    python3 tools/gen_quasars.py --check  # exit 1 if any generated theme differs
"""
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "tools", "quasar_template.zig")
LOCAL_DIR = os.path.join(ROOT, "tools", "local")

# Each entry: the object's paragraph, the parameters, and the bounds of its own disk claims.
# `edd` is the snapshot's ISCO inflow (Mdot_Edd units); the snapshot radiates ~0.55 of a steady
# disk at that inflow, so edd ~ lambda / 0.55 (tuned so the test's absolute L/L_Edd lands on
# lambda). `computed` holds the values its header quotes; its "computed disk" test checks them.
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


def isco(a):
    z1 = 1 + (1 - a * a) ** (1 / 3) * ((1 + a) ** (1 / 3) + (1 - a) ** (1 / 3))
    z2 = math.sqrt(3 * a * a + z1 * z1)
    return 3 + z2 - math.sqrt((3 - z1) * (3 + z1 + 2 * z2))


def colour_factor(t):
    return 1.0 if t <= 3.0e4 else (t / 3.0e4) ** 0.82 if t < 1.0e5 else (72.0 / (t * 8.617333e-8)) ** (1 / 9)


def mfmt(x):
    """A radius in M as the header quotes it."""
    return f"{x:.0f}" if x >= 10 else f"{x:.1f}"


def fields(q):
    """Every {{TOKEN}} of the template, for quasar q."""
    c = q["computed"]
    a = float(q["spin"])
    m = float(q["mass"])
    ri = isco(a)
    t_m = 4.925491e-6 * m  # seconds per M
    p_isco = 2 * math.pi * (ri ** 1.5 + a)  # prograde orbit period, M
    p_6 = 2 * math.pi * (6 ** 1.5 + a)
    f_peak = colour_factor(c["t_peak"])
    return {
        "TITLE_BLOCK": f"// {q['title']} // themes/{q['file']}\n"
                       "// GENERATED from tools/quasar_template.zig by tools/gen_quasars.py: edit the template, then\n"
                       "// `make quasars`. Same engine; this object's paragraph, spin, mass and Eddington ratio.",
        "OBJECT_PARAGRAPH": q["para"],
        "SPIN_NOTE": q["spin_note"],
        "SPIN": q["spin"],
        "MASS": q["mass"],
        "MASS_NOTE": q["mass_note"],
        "EDD": q["edd"],
        "EDD_PCT": f"{round(float(q['edd']) * 100, 1)}",
        "LAM_REF": q["lam_ref"],
        "T_LO": f"{q['t_lo']:.1f}",
        "T_HI": f"{q['t_hi']:.1f}",
        "LAM_LO": f"{q['lam'] * 0.85:.4f}",
        "LAM_HI": f"{q['lam'] * 1.15:.4f}",
        "FILE": q["file"],
        "ID": q["slug"],
        "R_ISCO": f"{ri:.2f}",
        "R_SNAP": mfmt(5 * ri),
        "R_25": mfmt(2.5 * ri),
        "PT_25": f"{c['pt_25']}",
        "PT_5": f"{c['pt_5']}",
        "LUM": f"{c['lum']}",
        "L_EDD": f"{c['l_edd']:g}",
        "T_PEAK": f"{c['t_peak']:.1f}",
        "T_PEAK_K": f"{round(c['t_peak'], -3):,.0f}",
        "R_PEAK": f"{c['r_peak']:.1f}",
        "R_PEAK_EXACT": f"{c['r_peak']}",
        "H_OVER_R": f"{c['h_over_r']:g}",
        "F_PEAK": f"{f_peak:.2f}",
        "F_PEAK_1": f"{f_peak:.1f}",
        "P_ISCO_S": f"{p_isco / 10:.0f}",
        "P_6_S": f"{p_6 / 10:.0f}",
        "P_ISCO_D": f"{p_isco * t_m / 86400:.0f}",
        "P_6_D": f"{p_6 * t_m / 86400:.0f}",
        "FAINTER": f"{1e12 * (c['t_peak'] / 49935.0) ** 4:.0e}".replace("e+", "e"),
    }


def generate(template, q):
    f = fields(q)
    used = set(re.findall(r"\{\{([A-Z_0-9]+)\}\}", template))
    missing = used - f.keys()
    if missing:
        raise SystemExit(f"gen_quasars: no value for {sorted(missing)} ({q['file']})")
    return re.sub(r"\{\{([A-Z_0-9]+)\}\}", lambda m: f[m.group(1)], template)


def local_quasars():
    if not os.path.isdir(LOCAL_DIR):
        return []
    out = []
    for name in sorted(os.listdir(LOCAL_DIR)):
        if name.endswith(".json"):
            with open(os.path.join(LOCAL_DIR, name)) as fh:
                out.append(json.load(fh))
    return out


def main():
    check = "--check" in sys.argv
    template = open(TEMPLATE).read()
    stale = []
    for q in QUASARS + local_quasars():
        out = generate(template, q)
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

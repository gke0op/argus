#!/usr/bin/env python3
"""Generate the quasar family from themes/Opus_Quasar.zig.

Opus_Quasar.zig (H1821+643) is the one source of the engine. Each other quasar is the same
file with its own object paragraph, spin, mass and Eddington ratio, test bounds and ledger ids.
Edit the source, then run `make quasars`; `make test` runs `--check` and fails on a stale file.

    python3 tools/gen_quasars.py          # write every generated theme
    python3 tools/gen_quasars.py --check  # exit 1 if any generated theme differs
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "themes", "Opus_Quasar.zig")

# Each entry: the object's paragraph (replaces H1821+643's), the parameters, and the bounds of
# its own disk claims. `edd` is the snapshot's ISCO inflow (Mdot_Edd units); the snapshot
# radiates ~0.54 of a steady disk at that inflow, so edd ~ lambda / 0.54 (tuned so the test's
# absolute L/L_Edd lands on lambda).
QUASARS = [
    {
        "file": "Opus_Cygnus_A.zig",
        "title": "OPUS CYGNUS A",
        "slug": "cygnus_a",
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
        "file": "Opus_J0834.zig",
        "title": "OPUS J0834",
        "slug": "j0834",
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
        "file": "Opus_PG1426.zig",
        "title": "OPUS PG 1426",
        "slug": "pg1426",
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

PARA_START = "// Modelled on H1821+643,"
PARA_END = "// Audited independently"


def rep(s, a, b, count=1):
    n = s.count(a)
    if n != count:
        raise SystemExit(f"gen_quasars: expected {count} of {a[:70]!r} in Opus_Quasar.zig, found {n}")
    return s.replace(a, b)


def generate(src, q):
    i = src.index(PARA_START)
    j = src.index(PARA_END)
    s = src[:i] + q["para"] + src[j:]
    s = rep(s, "// OPUS QUASAR // themes/Opus_Quasar.zig",
            f"// {q['title']} // themes/{q['file']}\n"
            "// GENERATED from themes/Opus_Quasar.zig by tools/gen_quasars.py: edit the source, then\n"
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
    s = s.replace('"zig test themes/Opus_Quasar.zig"', f'"zig test themes/{q["file"]}"')
    s = s.replace('"opus_quasar.', f'"opus_{q["slug"]}.')
    s = s.replace("a = 0.62", f"a = {q['spin']}")
    return s


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

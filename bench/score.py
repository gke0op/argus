#!/usr/bin/env python3
"""Score ARGUS-BENCH runs with the repository's own harness.

Usage (from the repository root):
    python3 bench/score.py bench/results/<date> [--repeats 3]

Every run folder <date>/<model>/<mode>/r<N>/ holds the contestant's file as theme.zig.
For each one, serially and under `nice -n 10`:
  - copy theme.zig next to a copy of themes/argus_theme_sdk.zig in bench/.score/ (deleted after),
  - run `make harness` --repeats times, in interleaved passes over all themes (gates are
    deterministic; timing is not, so each pass visits every theme before the next begins),
  - keep the full report of every repeat in harness.txt and the last frame as frame.png
    (downscaled to 640x400 with sips to keep the repository small),
  - write score.json: the eight gates, the gate score (gates passed out of 8), the verdict,
    and the median / range of the average frame time over the repeats.

A control row (the BENCHMARK.md section 3 skeleton, documented at about 1.5 ms on an idle M3) is
scored in every pass like a contestant, so the machine's load during scoring is visible next to the
contestants' numbers. summary.json also records the load average before each pass.
"""
import json
import os
import re
import shutil
import statistics
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCORE_DIR = os.path.join("bench", ".score")


def tier(us):
    if us is None:
        return "-"
    if us < 1000:
        return "Platinum"
    if us < 2000:
        return "Gold"
    if us < 4167:
        return "Silver"
    if us < 16667:
        return "Bronze"
    return "over budget"


def parse(out, rc):
    """Map one harness report to the eight gates. A gate that never ran counts as failed."""
    g = {k: False for k in ["compile", "allocs", "watchdog", "stride", "alpha_variance", "motion", "nan", "budget"]}
    r = {"gates": g, "avg_us": None, "worst_us": None, "verdict": "FAIL", "failure": None}
    if "Theme compilation failed" in out:
        r["failure"] = "compile error"
        m = re.search(r"error: (.*)", out)
        if m:
            r["failure"] += ": " + m.group(1).strip()[:160]
        return r
    g["compile"] = True
    if "VERIFICATION REPORT" not in out:
        r["failure"] = "no report (crashed after compiling, rc=%d)" % rc
        if "neither stateful" in out:
            r["failure"] = "does not export the theme ABI"
        return r

    def line(name):
        m = re.search(r"^\s*" + re.escape(name) + r"\s*:\s*(.*)$", out, re.M)
        return m.group(1).strip() if m else ""

    m = re.match(r"([\d.]+) us", line("Avg Frame Time"))
    r["avg_us"] = float(m.group(1)) if m else None
    m = re.match(r"([\d.]+) us", line("Worst Frame Time"))
    r["worst_us"] = float(m.group(1)) if m else None
    ai = re.match(r"(\d+)", line("Allocs at Init"))
    aa = re.match(r"(\d+)", line("Allocs after Init"))
    g["allocs"] = bool(ai and aa and int(ai.group(1)) == 1 and int(aa.group(1)) == 0)
    g["watchdog"] = line("Watchdog 320x200").startswith("PASS")
    g["stride"] = line("Stride Guard").startswith("CLEAN")
    g["nan"] = line("NaN / Inf Check").startswith("CLEAN")
    pv = re.match(r"(\d+) / \d+ non-bg pixels \(alpha=0 count: (\d+)\)", line("Pixel Variance"))
    g["alpha_variance"] = bool(pv and int(pv.group(1)) > 100 and int(pv.group(2)) == 0)
    tm = re.match(r"(\d+) /", line("Temporal Motion"))
    g["motion"] = bool(tm and int(tm.group(1)) >= 2000)
    g["budget"] = r["avg_us"] is not None and r["avg_us"] < 16667.0
    r["verdict"] = "PASS" if line("Verdict") == "PASS" else "FAIL"
    failed = [k for k, v in g.items() if not v]
    if failed:
        r["failure"] = "gates failed: " + ", ".join(failed)
    return r


def run_harness(theme_rel, png_rel):
    cmd = ["nice", "-n", "10", "make", "-s", "harness", "THEME=" + theme_rel, "OUT=" + png_rel]
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=900)
    return p.stdout + p.stderr, p.returncode


def stage(theme_path, label):
    """Copy a theme next to a copy of the SDK under bench/.score/<label>/; return its paths."""
    work_rel = os.path.join(SCORE_DIR, label)
    os.makedirs(os.path.join(ROOT, work_rel), exist_ok=True)
    theme_rel = os.path.join(work_rel, label + ".zig")
    shutil.copyfile(theme_path, os.path.join(ROOT, theme_rel))
    shutil.copyfile(os.path.join(ROOT, "themes", "argus_theme_sdk.zig"), os.path.join(ROOT, work_rel, "argus_theme_sdk.zig"))
    return theme_rel, os.path.join(work_rel, "frame.png")


def finish(entry):
    """Aggregate one theme's passes into score.json, harness.txt and frame.png in its folder."""
    parsed, out_dir = entry["parsed"], entry["out_dir"]
    with open(os.path.join(out_dir, "harness.txt"), "w") as f:
        f.write("\n".join(entry["reports"]))
    png = os.path.join(ROOT, entry["png_rel"])
    if os.path.exists(png):
        dst = os.path.join(out_dir, "frame.png")
        shutil.copyfile(png, dst)
        subprocess.run(["sips", "-z", "400", "640", dst], capture_output=True)
    first = parsed[0]
    times = [p["avg_us"] for p in parsed if p["avg_us"] is not None]
    res = {
        "gates": first["gates"],
        "gate_score": sum(first["gates"].values()),
        "verdict": first["verdict"],
        "failure": first["failure"],
        "gates_consistent_across_repeats": all(p["gates"] == first["gates"] for p in parsed),
        "repeats": len(parsed),
        "avg_us_each": times,
        "avg_us_median": statistics.median(times) if times else None,
        "avg_us_min": min(times) if times else None,
        "avg_us_max": max(times) if times else None,
        "tier": tier(statistics.median(times)) if times and first["verdict"] == "PASS" else "-",
    }
    with open(os.path.join(out_dir, "score.json"), "w") as f:
        json.dump(res, f, indent=2)
    return res


def loadavg():
    return subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True, text=True).stdout.strip()


def main():
    """Interleaved passes: each pass runs the harness once on every theme, in an order rotated by one
    per pass, so load from other work on the machine spreads across contestants instead of landing
    on whichever theme happened to be scored during a busy minute."""
    base = sys.argv[1]
    repeats = int(sys.argv[sys.argv.index("--repeats") + 1]) if "--repeats" in sys.argv else 3
    base_abs = os.path.join(ROOT, base) if not os.path.isabs(base) else base
    entries = []
    control_src = os.path.join(base_abs, "control", "Skeleton.zig")
    if os.path.exists(control_src):
        entries.append(dict(model="control", mode="-", run="skeleton", src=control_src, out_dir=os.path.join(base_abs, "control")))
    for model in sorted(os.listdir(base_abs)):
        mdir = os.path.join(base_abs, model)
        if model in ("control", "prompts") or not os.path.isdir(mdir):
            continue
        for mode in sorted(os.listdir(mdir)):
            if not os.path.isdir(os.path.join(mdir, mode)):
                continue
            for run in sorted(os.listdir(os.path.join(mdir, mode))):
                d = os.path.join(mdir, mode, run)
                entries.append(dict(model=model, mode=mode, run=run, src=os.path.join(d, "theme.zig"), out_dir=d))
    for e in entries:
        e["label"] = ("%s_%s_%s" % (e["model"], e["mode"], e["run"])).replace(".", "").replace("-", "_")
        e["reports"], e["parsed"] = [], []
        if os.path.exists(e["src"]):
            e["theme_rel"], e["png_rel"] = stage(e["src"], e["label"])
    loads = []
    for p in range(repeats):
        loads.append({"pass": p + 1, "loadavg_before": loadavg()})
        order = entries[p % len(entries):] + entries[:p % len(entries)]
        for e in order:
            if "theme_rel" not in e or (e["parsed"] and not e["parsed"][0]["gates"]["compile"]):
                continue  # nothing submitted, or a compile error (does not change between passes)
            out, rc = run_harness(e["theme_rel"], e["png_rel"])
            e["reports"].append("### pass %d (exit %d)\n%s" % (p + 1, rc, out))
            e["parsed"].append(parse(out, rc))
        print("pass %d done, load %s" % (p + 1, loadavg()), flush=True)
    summary = {"passes": loads, "control": None, "runs": []}
    for e in entries:
        if "theme_rel" not in e:
            res = {"gate_score": 0, "verdict": "FAIL", "failure": "no theme file submitted", "gates": None, "avg_us_median": None, "tier": "-"}
            with open(os.path.join(e["out_dir"], "score.json"), "w") as f:
                json.dump(res, f, indent=2)
        else:
            res = finish(e)
        if e["model"] == "control":
            summary["control"] = res
        else:
            summary["runs"].append(dict(model=e["model"], mode=e["mode"], run=e["run"], **res))
        print("%-18s %-9s %-8s %s %d/8 %s %s" % (e["model"], e["mode"], e["run"], res["verdict"], res["gate_score"], res.get("avg_us_median"), res.get("failure") or ""), flush=True)
    with open(os.path.join(base_abs, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    shutil.rmtree(os.path.join(ROOT, SCORE_DIR), ignore_errors=True)


if __name__ == "__main__":
    main()

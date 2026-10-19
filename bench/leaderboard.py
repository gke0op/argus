#!/usr/bin/env python3
"""Turn a scored results folder into the leaderboard tables (Markdown on stdout).

Usage (from the repository root, after bench/score.py):
    python3 bench/leaderboard.py bench/results/<date> [--runs]

Without --runs it prints the per-model, per-mode leaderboard; with --runs, one row per run.
Frame times are each run's median over the scorer's repeats; a model's figure is the median
and range of those over its passing runs. Skeleton similarity is difflib's ratio between the
submitted file and the BENCHMARK.md section 3 skeleton (1.0 = the skeleton unchanged).
"""
import difflib
import json
import os
import statistics
import sys

NAMES = {
    "opus-5.5": "Claude Opus 5.5",
    "sonnet-5.5": "Claude Sonnet 5.5",
    "haiku-5.5": "Claude Haiku 5.5",
    "fable-5.1": "Claude Fable 5.1",
    "gemini-3.8-flash": "Gemini 3.8 Flash",
    "gemini-4-argon": "Gemini 4 Argon (Argon)",
}
ORDER = list(NAMES)
MODES = ["zero-shot", "agentic"]


def tier(us):
    if us is None:
        return "-"
    return "Platinum" if us < 1000 else "Gold" if us < 2000 else "Silver" if us < 4167 else "Bronze" if us < 16667 else "over budget"


def med_range(xs, fmt="{:.2f}"):
    xs = [x for x in xs if x is not None]
    if not xs:
        return "-"
    m = statistics.median(xs)
    if len(xs) == 1 or min(xs) == max(xs):
        return fmt.format(m)
    return (fmt + " ({}–{})").format(m, fmt.format(min(xs)), fmt.format(max(xs)))


def load(base):
    skel_path = os.path.join(base, "control", "Skeleton.zig")
    skel = open(skel_path).read().splitlines() if os.path.exists(skel_path) else None
    rows = []
    for model in ORDER:
        for mode in MODES:
            d = os.path.join(base, model, mode)
            if not os.path.isdir(d):
                continue
            for run in sorted(os.listdir(d)):
                rd = os.path.join(d, run)
                if not os.path.exists(os.path.join(rd, "score.json")):
                    continue
                s = json.load(open(os.path.join(rd, "score.json")))
                m = json.load(open(os.path.join(rd, "meta.json"))) if os.path.exists(os.path.join(rd, "meta.json")) else {}
                sim = None
                if skel and os.path.exists(os.path.join(rd, "theme.zig")):
                    sim = difflib.SequenceMatcher(None, skel, open(os.path.join(rd, "theme.zig")).read().splitlines()).ratio()
                rows.append(dict(model=model, mode=mode, run=run, s=s, m=m, sim=sim))
    return rows


def leaderboard(rows):
    out = ["| Model | Mode | Pass | Gate score /8, median (range) | CPU ms/frame, median (range) of passing runs | Tier (median) | Gate failures | Runs to first own PASS | Wall time, min | Skeleton similarity |",
           "| :--- | :--- | :---: | :---: | ---: | :--- | :--- | :---: | ---: | :---: |"]
    for model in ORDER:
        for mode in MODES:
            rs = [r for r in rows if r["model"] == model and r["mode"] == mode]
            if not rs:
                continue
            passing = [r for r in rs if r["s"]["verdict"] == "PASS"]
            ms = [r["s"]["avg_us_median"] / 1000 for r in passing]
            fails = ["%s: %s" % (r["run"], r["s"]["failure"]) for r in rs if r["s"]["verdict"] != "PASS"]
            first = [r["m"].get("harness_runs_to_first_own_pass") for r in rs] if mode == "agentic" else []
            first_txt = "-" if mode != "agentic" else med_range([x for x in first if x is not None], "{:.0f}") + ("" if all(x is not None for x in first) else " (some never)")
            out.append("| %s | %s | %d/%d | %s | %s | %s | %s | %s | %s | %s |" % (
                NAMES[model], mode, len(passing), len(rs),
                med_range([r["s"]["gate_score"] for r in rs], "{:.0f}"),
                med_range(ms), tier(statistics.median(ms) * 1000) if ms else "-",
                "; ".join(fails) if fails else "none",
                first_txt,
                med_range([r["m"].get("wall_seconds", 0) / 60 for r in rs], "{:.0f}"),
                med_range([r["sim"] for r in rs], "{:.2f}")))
    return "\n".join(out)


def per_run(rows):
    out = ["| Model | Mode | Run | Verdict | Gates | CPU ms/frame (median of 7 passes, min–max) | Tier | Failure | Harness runs (total / to first own PASS) | Wall min | Skeleton sim. |",
           "| :--- | :--- | :---: | :---: | :---: | ---: | :--- | :--- | :---: | ---: | :---: |"]
    for r in rows:
        s, m = r["s"], r["m"]
        t = "-" if s.get("avg_us_median") is None else "%.2f (%.2f–%.2f)" % (s["avg_us_median"] / 1000, s["avg_us_min"] / 1000, s["avg_us_max"] / 1000)
        h = "-" if r["mode"] != "agentic" else "%s / %s" % (m.get("harness_runs_total", "?"), m.get("harness_runs_to_first_own_pass") or "never")
        out.append("| %s | %s | %s | %s | %d/8 | %s | %s | %s | %s | %.0f | %s |" % (
            NAMES[r["model"]], r["mode"], r["run"], s["verdict"], s["gate_score"], t, s.get("tier", "-"),
            s.get("failure") or "", h, m.get("wall_seconds", 0) / 60, "-" if r["sim"] is None else "%.2f" % r["sim"]))
    return "\n".join(out)


if __name__ == "__main__":
    rows = load(sys.argv[1])
    print(per_run(rows) if "--runs" in sys.argv else leaderboard(rows))

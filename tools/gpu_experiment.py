#!/usr/bin/env python3
"""
tools/gpu_experiment.py -- marginal GPU cost of one Argus configuration, measured off-screen.

For each case it launches this checkout's Argus.app with --offscreen (Space windows far
off-screen; never touches a running Argus), waits for it to settle, then measures over a
window:
  * Argus's own GPU time per second            (IOAccelerator AppUsage, per process)
  * whole-GPU power and P-state mix             (IOReport, see tools/gpu_meter.py)
and the same over an idle baseline (all Spaces "macOS Default"), alternating, so the
marginal power of the case is (case - baseline). The instance is stopped by its own PID.

  nice -n 10 python3 tools/gpu_experiment.py <rounds> <case-json> [<case-json> ...]
  case: {"name": "...", "theme": "Night_Tide.metal", "spaces": 1, "args": ["--bench-space","0"], "env": {...}}
"""
import json, os, signal, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import gpu_meter as gm

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SETTLE, WINDOW = 22.0, 20.0

def write_conf(theme, spaces):
    if isinstance(theme, list):  # a whole layout: one theme (or None) per Space
        with open(os.path.join(ROOT, ".argus_spaces.conf"), "w") as f:
            for i, t in enumerate(theme):
                f.write(f"{i}\tcustom_shader\t{t}\tthemes/{t}\n" if t else f"{i}\tpassthrough\tmacOS Default\t\n")
        try: os.remove(os.path.join(ROOT, ".argus_settings.conf"))
        except FileNotFoundError: pass
        return
    with open(os.path.join(ROOT, ".argus_spaces.conf"), "w") as f:
        for i in range(7):
            if theme and i < spaces: f.write(f"{i}\tcustom_shader\t{theme}\tthemes/{theme}\n")
            else: f.write(f"{i}\tpassthrough\tmacOS Default\t\n")
    try: os.remove(os.path.join(ROOT, ".argus_settings.conf"))
    except FileNotFoundError: pass

def measure(pid, secs):
    sub, subbed = gm.subscribe()
    s0 = gm.ior.IOReportCreateSamples(sub, subbed, None)
    a, _ = gm.ioreg_snapshot(); t0 = time.time()
    time.sleep(secs)
    b, _ = gm.ioreg_snapshot(); s1 = gm.ior.IOReportCreateSamples(sub, subbed, None)
    dt = time.time() - t0
    d = gm.read_delta(gm.ior.IOReportCreateSamplesDelta(s0, s1, None), dt)
    tot = sum(d["pstates"].values()) or 1
    act = {k: v for k, v in d["pstates"].items() if k != "OFF"}
    acts = sum(act.values()) or 1
    mine = sum(b[k] - a.get(k, 0) for k in b if k[0] == str(pid)) / dt / 1e9 * 100
    others = {k[1]: round((b[k] - a.get(k, 0)) / dt / 1e9 * 100, 1) for k in b if k[0] != str(pid) and (b[k] - a.get(k, 0)) / dt / 1e9 * 100 > 1}
    return {"argus_gpu_pct": round(mine, 1), "gpu_w": round(d["gpu_mj"] / 1000 / dt, 3),
            "gpu_active_pct": round(100 * acts / tot, 1), "p1_of_active_pct": round(100 * act.get("P1", 0) / acts, 1),
            "others": others}

def run(case):
    write_conf(case.get("theme"), case.get("spaces", 1))
    env = dict(os.environ); env.update(case.get("env", {}))
    args = ["./Argus.app/Contents/MacOS/Argus", "--offscreen", "--frames", str(int((SETTLE + WINDOW + 8) * 30))] + case.get("args", [])
    log = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"argus_exp_{os.getpid()}.log")
    p = subprocess.Popen(args + ["--perf-log"], cwd=ROOT, env=env, stdout=subprocess.DEVNULL, stderr=open(log, "w"))
    try:
        time.sleep(SETTLE)
        m = measure(p.pid, WINDOW)
    finally:
        try: os.kill(p.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        p.wait(timeout=20)
    # In-app GPU ms per frame of Space 0 over the measurement window (perf log, last 20 lines).
    import re
    lines = [l for l in open(log, errors="replace") if l.startswith("[perf]")][-int(WINDOW):]
    sp = case.get("frame_space", 0)
    ms = [float(x) for l in lines for x in re.findall(r" s%d=([0-9.]+)x" % sp, l)]
    m["frame_gpu_ms"] = round(sorted(ms)[len(ms) // 2], 2) if ms else None
    return m

def main():
    rounds = int(sys.argv[1]); cases = [json.loads(c) for c in sys.argv[2:]]
    base = {"name": "baseline (no theme)", "theme": None, "args": ["--bench-space", "0"]}
    for r in range(rounds):
        for c in cases:
            b = run(base); print(json.dumps({"round": r, **base, **b}), flush=True)
            m = run(c)
            m["marginal_w"] = round(m["gpu_w"] - b["gpu_w"], 3)
            print(json.dumps({"round": r, **c, **m}), flush=True)

if __name__ == "__main__":
    main()

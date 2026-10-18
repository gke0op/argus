#!/usr/bin/env python3
"""
tools/gpu_meter.py -- what the Apple GPU is doing, without sudo.

Over a window of N seconds it reports, from three independent sources:
  * IOReport "Energy Model"           GPU energy -> average GPU power (W)        [IOReport]
  * IOReport "GPU Stats"/GPUPH        time per GPU performance state (P-states),
                                      so you can see whether the GPU sits at a low
                                      clock while it is "busy"                  [IOReport]
  * IOAccelerator AppUsage per client accumulated GPU time per process, as %
                                      of wall time (what Activity Monitor's %GPU
                                      shows)                                    [ioreg]
  * IOAccelerator PerformanceStatistics "Device Utilization %" sampled each
                                      second (what menu-bar GPU meters show)    [ioreg]

  python3 tools/gpu_meter.py 20 [pid ...]        # 20 s window; named pids get their own column
  python3 tools/gpu_meter.py --series 180 2 Argus WindowServer Finder   # one JSON row per 2 s

IOReport is the private framework powermetrics and macmon read; its symbols live in
the dyld shared cache (/usr/lib/libIOReport.dylib), so ctypes can load it.
"""
import ctypes as C, ctypes.util, re, subprocess, sys, time, json

cf = C.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
ior = C.CDLL("/usr/lib/libIOReport.dylib")
V = C.c_void_p
cf.CFStringCreateWithCString.restype = V; cf.CFStringCreateWithCString.argtypes = [V, C.c_char_p, C.c_uint32]
cf.CFStringGetCString.restype = C.c_bool; cf.CFStringGetCString.argtypes = [V, C.c_char_p, C.c_long, C.c_uint32]
cf.CFDictionaryGetValue.restype = V; cf.CFDictionaryGetValue.argtypes = [V, V]
cf.CFArrayGetCount.restype = C.c_long; cf.CFArrayGetCount.argtypes = [V]
cf.CFArrayGetValueAtIndex.restype = V; cf.CFArrayGetValueAtIndex.argtypes = [V, C.c_long]
cf.CFRelease.argtypes = [V]
for name, res, args in [
    ("IOReportCopyChannelsInGroup", V, [V, V, C.c_uint64, C.c_uint64, C.c_uint64]),
    ("IOReportMergeChannels", None, [V, V, V]),
    ("IOReportCreateSubscription", V, [V, V, C.POINTER(V), C.c_uint64, V]),
    ("IOReportCreateSamples", V, [V, V, V]),
    ("IOReportCreateSamplesDelta", V, [V, V, V]),
    ("IOReportChannelGetGroup", V, [V]),
    ("IOReportChannelGetSubGroup", V, [V]),
    ("IOReportChannelGetChannelName", V, [V]),
    ("IOReportChannelGetUnitLabel", V, [V]),
    ("IOReportSimpleGetIntegerValue", C.c_int64, [V, C.c_int32]),
    ("IOReportStateGetCount", C.c_int32, [V]),
    ("IOReportStateGetNameForIndex", V, [V, C.c_int32]),
    ("IOReportStateGetResidency", C.c_int64, [V, C.c_int32]),
]:
    f = getattr(ior, name); f.restype = res; f.argtypes = args

UTF8 = 0x08000100
def cfs(s): return cf.CFStringCreateWithCString(None, s.encode(), UTF8)
def pys(r):
    if not r: return ""
    b = C.create_string_buffer(256)
    return b.value.decode() if cf.CFStringGetCString(r, b, 256, UTF8) else ""

def subscribe():
    chans = ior.IOReportCopyChannelsInGroup(cfs("Energy Model"), None, 0, 0, 0)
    gpu = ior.IOReportCopyChannelsInGroup(cfs("GPU Stats"), cfs("GPU Performance States"), 0, 0, 0)
    ior.IOReportMergeChannels(chans, gpu, None)
    subbed = V()
    sub = ior.IOReportCreateSubscription(None, chans, C.byref(subbed), 0, None)
    return sub, subbed

def read_delta(d, secs):
    out = {"gpu_mj": 0.0, "pstates": {}}
    arr = cf.CFDictionaryGetValue(d, cfs("IOReportChannels"))
    for i in range(cf.CFArrayGetCount(arr)):
        ch = cf.CFArrayGetValueAtIndex(arr, i)
        grp, name = pys(ior.IOReportChannelGetGroup(ch)), pys(ior.IOReportChannelGetChannelName(ch))
        if grp == "Energy Model" and name.startswith("GPU"):
            unit = pys(ior.IOReportChannelGetUnitLabel(ch)).strip()
            v = ior.IOReportSimpleGetIntegerValue(ch, 0)
            scale = {"mJ": 1.0, "uJ": 1e-3, "nJ": 1e-6}.get(unit, 1.0)
            out["gpu_mj"] += v * scale
        elif grp == "GPU Stats" and name == "GPUPH":
            for k in range(ior.IOReportStateGetCount(ch)):
                st = pys(ior.IOReportStateGetNameForIndex(ch, k))
                out["pstates"][st] = out["pstates"].get(st, 0) + ior.IOReportStateGetResidency(ch, k)
    return out

def ioreg_snapshot():
    txt = subprocess.run(["ioreg", "-l", "-w0"], capture_output=True).stdout.decode("utf-8", "replace")
    per, usage, creator = {}, 0, None
    def flush():
        if creator and usage: per[creator] = per.get(creator, 0) + usage
    util = None
    for l in txt.split("\n"):
        if "+-o " in l:
            flush(); usage, creator = 0, None; continue
        m = re.search(r'"IOUserClientCreator" = "pid (\d+), ([^"]*)"', l)
        if m: creator = (m.group(1), m.group(2))
        m = re.search(r'"AppUsage" = \((.*)\)', l)
        if m: usage += sum(int(x) for x in re.findall(r'"accumulatedGPUTime"=(\d+)', m.group(1)))
        m = re.search(r'"Device Utilization %"=(\d+)', l)
        if m and util is None: util = int(m.group(1))
    flush()
    return per, util

def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 10
    pids = sys.argv[2:]
    sub, subbed = subscribe()
    s0 = ior.IOReportCreateSamples(sub, subbed, None)
    a, _ = ioreg_snapshot()
    t0 = time.time(); utils = []
    while time.time() - t0 < secs:
        time.sleep(1.0)
        utils.append(ioreg_snapshot()[1] or 0)
    b, _ = ioreg_snapshot()
    s1 = ior.IOReportCreateSamples(sub, subbed, None)
    dt = time.time() - t0
    d = read_delta(ior.IOReportCreateSamplesDelta(s0, s1, None), dt)
    total_res = sum(d["pstates"].values()) or 1
    active = {k: v for k, v in d["pstates"].items() if k not in ("OFF", "IDLE", "DOWN")}
    act_res = sum(active.values())
    procs = sorted(((b[k] - a.get(k, 0)) / dt / 1e9 * 100, k) for k in b)
    res = {
        "window_s": round(dt, 1),
        "gpu_power_w": round(d["gpu_mj"] / 1000.0 / dt, 3),
        "gpu_active_residency_pct": round(100.0 * act_res / total_res, 1),
        "pstate_share_of_active_pct": {k: round(100.0 * v / max(act_res, 1), 1) for k, v in active.items() if v},
        "device_utilization_pct_mean": round(sum(utils) / max(len(utils), 1), 1),
        "per_process_gpu_pct": {f"{k[1]}[{k[0]}]": round(v, 1) for v, k in procs[::-1][:8] if v > 0.05},
    }
    for p in pids:
        res[f"pid {p}"] = round(sum(b[k] - a.get(k, 0) for k in b if k[0] == p) / dt / 1e9 * 100, 1)
    print(json.dumps(res))

if __name__ == "__main__" and sys.argv[1:2] != ["--series"]:
    main()

def series(secs, step, names):
    """Time series of per-process GPU % (by process name), device utilization, GPU power, P1 share."""
    sub, subbed = subscribe()
    prev_s = ior.IOReportCreateSamples(sub, subbed, None)
    prev, _ = ioreg_snapshot(); tprev = time.time(); t0 = tprev
    while time.time() - t0 < secs:
        time.sleep(step)
        cur, util = ioreg_snapshot(); s = ior.IOReportCreateSamples(sub, subbed, None); t = time.time()
        dt = t - tprev
        d = read_delta(ior.IOReportCreateSamplesDelta(prev_s, s, None), dt)
        tot = sum(d["pstates"].values()) or 1
        act = {k: v for k, v in d["pstates"].items() if k not in ("OFF",)}
        row = {"t": round(t - t0, 1), "util": util, "W": round(d["gpu_mj"] / 1000 / dt, 3),
               "active": round(100 * sum(act.values()) / tot, 1),
               "P1_of_active": round(100 * act.get("P1", 0) / max(sum(act.values()), 1), 1)}
        for n in names:
            row[n] = round(sum(cur[k] - prev.get(k, 0) for k in cur if k[1] == n) / dt / 1e9 * 100, 1)
        print(json.dumps(row), flush=True)
        prev, prev_s, tprev = cur, s, t

if __name__ == "__main__" and sys.argv[1:2] == ["--series"]:
    # python3 tools/gpu_meter.py --series 180 2 Argus WindowServer Finder
    series(float(sys.argv[2]), float(sys.argv[3]), sys.argv[4:])

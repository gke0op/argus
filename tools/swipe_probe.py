#!/usr/bin/env python3
"""
tools/swipe_probe.py -- when does a Space's window count as on screen during a swipe?

Read-only: watches another process's windows (the running Argus). At ~60 Hz it logs
  * which of that process's windows are in CGWindowListCreate(kCGWindowListOptionOnScreenOnly)
  * the active Space (SkyLight CGSGetActiveSpace)
so a swipe shows when the arriving Space's window enters the on-screen list compared with when
the active Space changes. One line per change, with milliseconds since start.

  python3 tools/swipe_probe.py <argus-pid> [seconds]
"""
import ctypes as C, sys, time

cf = C.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
cg = C.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
sl = C.CDLL("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
V = C.c_void_p
cf.CFArrayGetCount.restype = C.c_long; cf.CFArrayGetCount.argtypes = [V]
cf.CFArrayGetValueAtIndex.restype = V; cf.CFArrayGetValueAtIndex.argtypes = [V, C.c_long]
cf.CFDictionaryGetValue.restype = V; cf.CFDictionaryGetValue.argtypes = [V, V]
cf.CFNumberGetValue.restype = C.c_bool; cf.CFNumberGetValue.argtypes = [V, C.c_int, V]
cf.CFRelease.argtypes = [V]
cf.CFStringCreateWithCString.restype = V; cf.CFStringCreateWithCString.argtypes = [V, C.c_char_p, C.c_uint32]
cg.CGWindowListCreate.restype = V; cg.CGWindowListCreate.argtypes = [C.c_uint32, C.c_uint32]
cg.CGWindowListCopyWindowInfo.restype = V; cg.CGWindowListCopyWindowInfo.argtypes = [C.c_uint32, C.c_uint32]
sl.CGSMainConnectionID.restype = C.c_int
sl.CGSGetActiveSpace.restype = C.c_uint64; sl.CGSGetActiveSpace.argtypes = [C.c_int]

def cfs(s): return cf.CFStringCreateWithCString(None, s.encode(), 0x08000100)
K_PID, K_NUM, K_LAYER = cfs("kCGWindowOwnerPID"), cfs("kCGWindowNumber"), cfs("kCGWindowLayer")

def num(d, k):
    v = cf.CFDictionaryGetValue(d, k)
    out = C.c_int64(0)
    if v: cf.CFNumberGetValue(v, 4, C.byref(out))
    return out.value

def windows_of(pid):
    arr = cg.CGWindowListCopyWindowInfo(0, 0)  # all windows
    ids = []
    for i in range(cf.CFArrayGetCount(arr)):
        d = cf.CFArrayGetValueAtIndex(arr, i)
        if num(d, K_PID) == pid and num(d, K_LAYER) < 0:  # desktop-level windows only
            ids.append(num(d, K_NUM))
    cf.CFRelease(arr)
    return set(ids)

def onscreen():
    arr = cg.CGWindowListCreate(1, 0)  # kCGWindowListOptionOnScreenOnly
    s = {cf.CFArrayGetValueAtIndex(arr, i) or 0 for i in range(cf.CFArrayGetCount(arr))}
    cf.CFRelease(arr)
    return s

def main():
    pid = int(sys.argv[1]); secs = float(sys.argv[2]) if len(sys.argv) > 2 else 60
    conn = sl.CGSMainConnectionID()
    mine = windows_of(pid)
    print(f"watching {len(mine)} desktop-level windows of pid {pid}", flush=True)
    t0 = time.time(); last = None
    while time.time() - t0 < secs:
        on = sorted(w for w in mine if w in onscreen())
        sp = sl.CGSGetActiveSpace(conn)
        state = (tuple(on), sp)
        if state != last:
            print(f"{(time.time() - t0) * 1000:8.0f} ms  active_space={sp}  argus_windows_on_screen={list(on)}", flush=True)
            last = state
        time.sleep(1 / 60)

if __name__ == "__main__":
    main()

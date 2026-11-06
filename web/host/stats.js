// web/host/stats.js — ArgusStats for `// @argus stats` themes.
//
// `synthetic(seq)` is src/gpu/argus_stats.zig's harness feed, ported in f32 arithmetic, so the
// verify page shows the same readings as the Metal harness PNG. `BrowserStats` is what a web page
// can honestly read about the machine; every other field stays synthetic, and `sources` says
// which is which so a page can label them (web/README.md lists them).

export const STATS_BYTES = 428;
const MAX_CORES = 32;
const TOP = 5;

const f = Math.fround;
const sin32 = (x) => f(Math.sin(f(x)));
const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

// `cores`: how many per-core loads to fill (10 in the harness; the browser's core count live).
export function synthetic(seq, cores = 10) {
  const t = f(seq);
  const s = {
    seq: seq >>> 0,
    sample_dt: 1.0,
    uptime_s: 3 * 86400 + 4 * 3600 + seq,
    thermal: seq % 120 >= 100 ? 1 : 0,
    cpu_total: 0, cpu_count: Math.min(cores, MAX_CORES), cpu_p_cores: 6, cpu_e_cores: 4,
    cpu_core: new Array(MAX_CORES).fill(0),
    mem_total_gb: 16.0,
    mem_used_gb: f(f(10.5 + f(1.2 * sin32(t * f(0.05)))) + f(0.15 * sin32(t * f(0.9)))),
    mem_compressed_gb: f(1.4 + f(0.3 * sin32(f(t * f(0.04)) + 1.0))),
    mem_wired_gb: f(2.6 + f(0.1 * sin32(t * f(0.07)))),
    swap_used_gb: f(0.75 + f(0.25 * sin32(t * f(0.02)))),
    mem_pressure: seq % 90 >= 70 ? 1 : 0,
    gpu_busy: clamp(f(f(0.24 + f(0.16 * sin32(t * f(0.31)))) + f(0.06 * sin32(t * f(1.7)))), 0, 1),
    battery_present: 1,
    battery_charge: f(0.86 - f(0.0015 * f(seq % 400))),
    battery_charging: 0, on_ac: 0, battery_minutes: 0,
    net_rx_bps: f(f(180e3 * f(1.0 + sin32(t * f(0.45)))) + f(2.4e6 * Math.max(0, f(sin32(t * f(0.21)) - f(0.6))))),
    net_tx_bps: f(40e3 * f(1.0 + sin32(f(t * f(0.37)) + 2.0))),
    disk_free_gb: f(182.5 - f(0.01 * t)),
    disk_total_gb: f(494.4),
    proc_count: TOP,
    procs: [],
  };
  s.battery_minutes = f(s.battery_charge * 420.0);
  let sum = 0;
  for (let c = 0; c < s.cpu_count; c++) {
    const fc = f(c);
    const busy = c < s.cpu_e_cores ? f(0.35) : f(0.12);
    const v = f(f(busy + f(0.25 * sin32(f(t * f(0.3 + f(0.07 * fc))) + f(fc * f(1.3))))) + f(0.1 * sin32(f(t * f(1.1)) + fc)));
    s.cpu_core[c] = clamp(v, f(0.02), f(0.98));
    sum = f(sum + s.cpu_core[c]);
  }
  s.cpu_total = f(sum / s.cpu_count);

  const names = ['Safari', 'Xcode', 'Argus', 'Music', 'Terminal', 'Finder'];
  const base = [0.06, 0.04, 0.01, 0.015, 0.008, 0.004].map(f);
  const mem = [1.8, 2.4, 0.09, 0.35, 0.06, 0.12].map(f);
  const all = names.map((name, i) => {
    const fi = f(i);
    return { name, cpu: Math.max(0, f(base[i] * f(1.0 + f(0.8 * sin32(f(t * f(0.23 + f(0.05 * fi))) + fi))))), mem_gb: mem[i] };
  });
  all.sort((a, b) => b.cpu - a.cpu); // stable, as Zig's std.mem.sort
  s.procs = all.slice(0, TOP);
  return s;
}

// The 428 bytes the GPU sees (the prelude's ArgusStats).
export function pack(s, view) {
  const u = (o, v) => view.setUint32(o, v >>> 0, true);
  const fl = (o, v) => view.setFloat32(o, v, true);
  u(0, s.seq); fl(4, s.sample_dt); u(8, s.uptime_s); u(12, s.thermal);
  fl(16, s.cpu_total); u(20, s.cpu_count); u(24, s.cpu_p_cores); u(28, s.cpu_e_cores);
  for (let i = 0; i < MAX_CORES; i++) fl(32 + 4 * i, s.cpu_core[i] ?? 0);
  fl(160, s.mem_total_gb); fl(164, s.mem_used_gb); fl(168, s.mem_compressed_gb);
  fl(172, s.mem_wired_gb); fl(176, s.swap_used_gb); u(180, s.mem_pressure);
  fl(184, s.gpu_busy);
  u(188, s.battery_present); fl(192, s.battery_charge); u(196, s.battery_charging);
  u(200, s.on_ac); fl(204, s.battery_minutes);
  fl(208, s.net_rx_bps); fl(212, s.net_tx_bps);
  fl(216, s.disk_free_gb); fl(220, s.disk_total_gb);
  u(224, s.proc_count);
  for (let p = 0; p < TOP; p++) {
    const o = 228 + 40 * p;
    const pr = s.procs[p];
    for (let j = 0; j < 32; j++) {
      let c = 0;
      if (pr && j < Math.min(pr.name.length, 31)) {
        c = pr.name.charCodeAt(j);
        if (c < 0x20 || c >= 0x7f) c = 0x3f; // '?', as Proc.setName
      }
      view.setUint8(o + j, c);
    }
    fl(o + 32, pr ? pr.cpu : 0);
    fl(o + 36, pr ? pr.mem_gb : 0);
  }
}

// What the browser can tell about the machine. Fields not listed in `sources` as 'live' keep the
// synthetic values. Sampled about once a second, like the app.
export class BrowserStats {
  constructor() {
    this.seq = 0;
    this.lastSample = -Infinity;
    this.pressure = null;     // Compute Pressure API state, Chromium only
    this.battery = null;      // Battery Status API, Chromium only
    this.gpuMs = null;        // set by the host: this page's own GPU time per frame
    this.frameMs = null;
    this.sources = {};
    this.current = synthetic(0);
    this.current.seq = 0;
    if (typeof PressureObserver !== 'undefined') {
      try {
        const map = { nominal: 0, fair: 1, serious: 2, critical: 3 };
        this.observer = new PressureObserver((recs) => { this.pressure = map[recs[recs.length - 1].state] ?? null; });
        this.observer.observe('cpu', { sampleInterval: 1000 }).catch(() => { this.observer = null; });
      } catch { this.observer = null; }
    }
    if (navigator.getBattery) navigator.getBattery().then((b) => { this.battery = b; }, () => {});
  }

  // Returns the stats to bind now; a new sample (seq + 1) about once a second.
  sample(nowMs) {
    if (nowMs - this.lastSample < 1000) return this.current;
    const dt = this.lastSample === -Infinity ? 1 : (nowMs - this.lastSample) / 1000;
    this.lastSample = nowMs;
    this.seq += 1;
    const cores = navigator.hardwareConcurrency ? Math.min(navigator.hardwareConcurrency, MAX_CORES) : 10;
    const s = synthetic(this.seq, cores);
    const src = {};
    for (const k of Object.keys(s)) src[k] = 'synthetic';
    s.seq = this.seq; src.seq = 'live';
    s.sample_dt = Math.fround(dt); src.sample_dt = 'live';
    if (navigator.hardwareConcurrency) {
      // The count is live; the per-core loads stay synthetic (the same formula, one per core).
      s.cpu_p_cores = 0; s.cpu_e_cores = 0; // the browser doesn't say
      src.cpu_count = 'live (navigator.hardwareConcurrency)';
      src.cpu_p_cores = src.cpu_e_cores = 'unknown in a browser (0)';
    }
    // navigator.deviceMemory is rounded and capped (8 in Chrome), so it would misreport most Macs:
    // mem_total_gb stays synthetic.
    if (this.pressure !== null) { s.thermal = this.pressure; src.thermal = 'live (Compute Pressure API: CPU pressure state)'; }
    if (this.battery) {
      const b = this.battery;
      s.battery_present = 1; s.battery_charge = b.level; s.battery_charging = b.charging ? 1 : 0;
      s.on_ac = b.charging || (b.level === 1 && b.chargingTime === 0) ? 1 : 0;
      const t = b.charging ? b.chargingTime : b.dischargingTime;
      s.battery_minutes = Number.isFinite(t) ? (b.charging && b.level === 1 ? 0 : t / 60) : -1;
      for (const k of ['battery_present', 'battery_charge', 'battery_charging', 'on_ac', 'battery_minutes']) src[k] = 'live (Battery Status API)';
    }
    if (this.gpuMs !== null && this.frameMs) {
      s.gpu_busy = Math.min(this.gpuMs / this.frameMs, 1);
      src.gpu_busy = "live (this page's own GPU time / frame interval)";
    }
    s.uptime_s = Math.floor(performance.now() / 1000);
    src.uptime_s = 'live (page uptime, not machine uptime)';
    this.current = s;
    this.sources = src;
    return s;
  }

  destroy() { try { this.observer?.disconnect(); } catch { /* already gone */ } }
}

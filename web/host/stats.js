// web/host/stats.js — ArgusStats for `// @argus stats` themes.
//
// `synthetic(seq)` is src/gpu/argus_stats.zig's harness feed, ported in f32 arithmetic, so the
// verify page shows the same readings as the Metal harness PNG. `BrowserVitals` is what a browser
// page gets instead: only readings with a real source, nothing synthetic (see below).

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

// ---- a browser page ----------------------------------------------------------------------------
// A web page can't read the machine's CPU load, memory, disks, network traffic or processes. So a
// browser page gets no synthetic stand-ins: ArgusStats carries only the fields with a real source,
// the rest stay 0, and ArgusVitals (web only, mode 1) carries the page's own vitals. `sources`
// names the source of every reading, or says it isn't available; web/README.md has the table.
export const VITALS_BYTES = 208;
export const HAS = { gpuTime: 1, threads: 2, deviceMem: 4, heap: 8, battery: 16, network: 32, pressure: 64 };
const NET_TYPES = { 'slow-2g': 1, '2g': 2, '3g': 3, '4g': 4 };
const PRESSURE = { nominal: 1, fair: 2, serious: 3, critical: 4 };

export function emptyStats() {
  return {
    seq: 0, sample_dt: 0, uptime_s: 0, thermal: 0,
    cpu_total: 0, cpu_count: 0, cpu_p_cores: 0, cpu_e_cores: 0, cpu_core: new Array(MAX_CORES).fill(0),
    mem_total_gb: 0, mem_used_gb: 0, mem_compressed_gb: 0, mem_wired_gb: 0, swap_used_gb: 0, mem_pressure: 0,
    gpu_busy: 0, battery_present: 0, battery_charge: 0, battery_charging: 0, on_ac: 0, battery_minutes: 0,
    net_rx_bps: 0, net_tx_bps: 0, disk_free_gb: 0, disk_total_gb: 0, proc_count: 0, procs: [],
  };
}

export function emptyVitals(mode = 0) {
  return {
    mode, has: 0, frame_ms: 0, frame_worst_ms: 0, gpu_ms: 0, draw_ms: 0, js_ms: 0, threads: 0, device_mem_gb: 0,
    heap_used_mb: 0, heap_total_mb: 0, heap_limit_mb: 0, net_type: 0, net_downlink_mbps: 0, net_rtt_ms: 0,
    net_save_data: 0, pressure: 0, canvas_w: 0, canvas_h: 0, dpr: 0, adapter: '',
  };
}

// The 208 bytes of the prelude's ArgusVitals.
export function packVitals(v, view) {
  const u = (o, x) => view.setUint32(o, x >>> 0, true);
  const fl = (o, x) => view.setFloat32(o, x, true);
  u(0, v.mode); u(4, v.has); fl(8, v.frame_ms); fl(12, v.frame_worst_ms); fl(16, v.gpu_ms); fl(20, v.draw_ms);
  fl(24, v.js_ms); u(28, v.threads); fl(32, v.device_mem_gb); fl(36, v.heap_used_mb); fl(40, v.heap_total_mb);
  fl(44, v.heap_limit_mb); u(48, v.net_type); fl(52, v.net_downlink_mbps); fl(56, v.net_rtt_ms); u(60, v.net_save_data);
  u(64, v.pressure); u(68, v.canvas_w); u(72, v.canvas_h); fl(76, v.dpr);
  for (let j = 0; j < 32; j++) {
    let c = j < Math.min(v.adapter.length, 31) ? v.adapter.charCodeAt(j) : 0;
    if (c !== 0 && (c < 0x20 || c >= 0x7f)) c = 0x3f; // '?'
    u(80 + 4 * j, c);
  }
}

const median = (a) => { if (!a.length) return 0; const s = [...a].sort((x, y) => x - y); return s[s.length >> 1]; };
const MB = 1024 * 1024;

export class BrowserVitals {
  constructor(adapter = '') {
    this.seq = 0;
    this.lastSample = -Infinity;
    this.frames = [];          // display-frame intervals (ms) since the last sample
    this.gpu = [];             // GPU ms per frame (whole frame, argus_draw) since the last sample
    this.draw = [];
    this.js = [];
    this.pressure = null;      // Compute Pressure API state (Chromium)
    this.battery = null;       // Battery Status API (Chromium)
    this.adapter = adapter.toUpperCase().replace(/[^\x20-\x7e]/g, '?').split(/\s+/).filter((w, i, a) => w && a.indexOf(w) === i).join(' ').slice(0, 31);
    this.sources = {};
    this.stats = emptyStats();
    this.vitals = emptyVitals(1);
    if (typeof PressureObserver !== 'undefined') {
      try {
        this.observer = new PressureObserver((recs) => { this.pressure = PRESSURE[recs[recs.length - 1].state] ?? null; });
        this.observer.observe('cpu', { sampleInterval: 1000 }).catch(() => { this.observer = null; });
      } catch { this.observer = null; }
    }
    if (navigator.getBattery) navigator.getBattery().then((b) => { this.battery = b; }, () => {});
  }

  frame(intervalMs, jsMs) { this.frames.push(intervalMs); this.js.push(jsMs); }
  gpuTime(totalMs, drawMs) { this.gpu.push(totalMs); this.draw.push(drawMs); }

  // The stats and vitals to bind now; a new sample (seq + 1) about once a second.
  // The first one comes a second after the first frame, once there is something measured: until
  // then seq is 0 and the theme shows that it is waiting.
  sample(nowMs, canvasW, canvasH, dpr) {
    if (this.lastSample === -Infinity) { this.lastSample = nowMs; return this; }
    if (nowMs - this.lastSample < 1000) return this;
    const dt = (nowMs - this.lastSample) / 1000;
    this.lastSample = nowMs;
    this.seq += 1;
    const s = emptyStats();
    const v = emptyVitals(1);
    const src = {};
    const no = 'not available in this browser';

    s.seq = this.seq; s.sample_dt = Math.fround(dt);
    s.uptime_s = Math.floor(performance.now() / 1000);
    src.sample = 'live: a new sample about once a second';
    src.uptime = "live: this tab's uptime (performance.now), not the machine's";

    if (this.frames.length) {
      v.frame_ms = this.frames.reduce((a, b) => a + b, 0) / this.frames.length;
      v.frame_worst_ms = Math.max(...this.frames);
    }
    v.js_ms = median(this.js);
    src.frame = 'live: requestAnimationFrame intervals of this page';
    src.js = 'live: JavaScript time per frame of this page';
    if (this.gpu.length) {
      v.has |= HAS.gpuTime;
      v.gpu_ms = median(this.gpu); v.draw_ms = median(this.draw);
      s.gpu_busy = v.frame_ms > 0 ? Math.min(v.gpu_ms / v.frame_ms, 1) : 0;
      src.gpu = "live: this page's GPU time per frame (timestamp queries); gpu_busy = that / frame interval";
    } else src.gpu = `${no} (no timestamp-query)`;
    this.frames.length = 0; this.gpu.length = 0; this.draw.length = 0; this.js.length = 0;

    if (navigator.hardwareConcurrency) {
      v.has |= HAS.threads; v.threads = navigator.hardwareConcurrency;
      s.cpu_count = Math.min(v.threads, MAX_CORES); // per-core loads stay 0: not readable
      src.threads = 'live: navigator.hardwareConcurrency (logical processors; no loads)';
    } else src.threads = no;
    if (navigator.deviceMemory) {
      v.has |= HAS.deviceMem; v.device_mem_gb = navigator.deviceMemory;
      src.deviceMemory = 'live: navigator.deviceMemory (rounded down to a power of two, capped: 8 in Chrome)';
    } else src.deviceMemory = no;
    const pm = performance.memory;
    if (pm && pm.jsHeapSizeLimit) {
      v.has |= HAS.heap;
      v.heap_used_mb = pm.usedJSHeapSize / MB; v.heap_total_mb = pm.totalJSHeapSize / MB; v.heap_limit_mb = pm.jsHeapSizeLimit / MB;
      src.heap = 'live: performance.memory (this page\'s JS heap, coarse buckets)';
    } else src.heap = no;
    if (this.battery) {
      const b = this.battery;
      v.has |= HAS.battery;
      s.battery_present = 1; s.battery_charge = b.level; s.battery_charging = b.charging ? 1 : 0;
      s.on_ac = b.charging || (b.level === 1 && b.chargingTime === 0) ? 1 : 0;
      const t = b.charging ? b.chargingTime : b.dischargingTime;
      s.battery_minutes = Number.isFinite(t) ? (b.charging && b.level === 1 ? 0 : t / 60) : -1;
      src.battery = 'live: Battery Status API';
    } else src.battery = no;
    const c = navigator.connection;
    if (c && c.effectiveType) {
      v.has |= HAS.network;
      v.net_type = NET_TYPES[c.effectiveType] ?? 0; v.net_downlink_mbps = c.downlink ?? 0; v.net_rtt_ms = c.rtt ?? 0;
      v.net_save_data = c.saveData ? 1 : 0;
      src.network = 'live: Network Information API (effective type, downlink and RTT estimates)';
    } else src.network = no;
    if (this.pressure !== null) {
      v.has |= HAS.pressure; v.pressure = this.pressure;
      src.pressure = 'live: Compute Pressure API (CPU pressure state)';
    } else src.pressure = no;
    v.canvas_w = canvasW; v.canvas_h = canvasH; v.dpr = dpr; v.adapter = this.adapter;
    src.display = 'live: canvas size, devicePixelRatio, GPU adapter info';
    src.machine = 'not readable by a web page: CPU load, memory use, disks, network traffic, processes, thermal state';

    this.stats = s; this.vitals = v; this.sources = src;
    return this;
  }

  destroy() { try { this.observer?.disconnect(); } catch { /* already gone */ } }
}

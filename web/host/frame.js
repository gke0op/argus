// web/host/frame.js — the ArgusFrame a theme sees, kept exactly as src/gpu/metal_theme.zig keeps
// it: the f64 clock wrapped to 4 h, the 30 Hz tick counter, the J2000 date split, and the
// 44-byte layout.

export const TIME_PERIOD = 14400.0;
export const J2000_UNIX = 946728000;          // 2000-01-01T12:00:00Z
export const FRAME_BYTES = 44;                 // sizeof(ArgusFrame)
export const LOGIC_HZ = 30;
export const STEP_DT = Math.fround(1 / 30);    // the Metal harness's METAL_DT, as f32
const F32_BELOW_ONE = 1 - 2 ** -24;            // 1.0 - floatEps(f32) / 2

// Unix time (UTC, no leap seconds) -> whole days since J2000.0 and the fraction of that day,
// formed in f64 and narrowed to f32 (metal_theme.zig j2000).
export function j2000(unixS, nsec) {
  const s = unixS - J2000_UNIX;
  const days = Math.floor(s / 86400);
  const rem = s - days * 86400;
  const frac = Math.fround((rem + nsec * 1e-9) / 86400.0);
  return { days, frac: Math.min(frac, F32_BELOW_ONE) };
}

// `YYYY-MM-DDTHH:MM:SSZ` (UTC) -> Unix seconds (metal_theme.zig parseIsoUtc).
export function parseIsoUtc(str) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/.exec(str);
  if (!m) throw new Error(`date must be YYYY-MM-DDTHH:MM:SSZ, got ${str}`);
  const [y, mo, d, h, mi, se] = m.slice(1).map(Number);
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || se > 59) throw new Error(`date out of range: ${str}`);
  const yy = mo <= 2 ? y - 1 : y;
  const era = Math.floor(yy / 400);
  const yoe = yy - era * 400;
  const mp = (mo + 9) % 12;
  const doy = Math.floor((153 * mp + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  const days = era * 146097 + doe - 719468;
  return days * 86400 + h * 3600 + mi * 60 + se;
}

// The theme's mutable frame, its clock and its tick counter (metal_theme.zig Theme fields).
export class FrameState {
  constructor({ width, height, stateW, stateH, seed, wall }) {
    this.time = 0; this.dt = 0; this.frame = 0;
    this.width = width; this.height = height;
    this.stateW = stateW; this.stateH = stateH;
    this.seed = seed >>> 0;
    this.daysJ2000 = 0; this.dayFrac = 0; this.utcOffsetS = 0;
    this.clock = 0;              // f64 seconds since load; time is this, wrapped
    this.tickStarted = false;    // FrameCounter
    this.wall = wall;            // { kind: 'system' } | { kind: 'fixed', unixS, utcOffsetS }
  }

  // FrameCounter.forEncode
  forEncode(tick) {
    if (tick) {
      if (this.tickStarted) this.frame = (this.frame + 1) >>> 0; else this.tickStarted = true;
    }
    return this.frame;
  }

  // fillWall: the date fields from the system clock, or from the pinned start + the clock.
  fillWall() {
    if (this.wall.kind === 'fixed') {
      const whole = Math.floor(this.clock);
      const d = j2000(this.wall.unixS + whole, Math.trunc((this.clock - whole) * 1e9));
      this.daysJ2000 = d.days; this.dayFrac = d.frac; this.utcOffsetS = this.wall.utcOffsetS | 0;
    } else {
      const ms = performance.timeOrigin + performance.now();
      const sec = Math.floor(ms / 1000);
      const d = j2000(sec, Math.round((ms - sec * 1000) * 1e6));
      this.daysJ2000 = d.days; this.dayFrac = d.frac;
      this.utcOffsetS = -new Date(ms).getTimezoneOffset() * 60;
    }
  }

  // advanceClock: f64 accumulation of the f32 dt, wrapped, narrowed to f32.
  advanceClock(dt) {
    this.clock += Math.fround(dt);
    this.time = Math.fround(this.clock % TIME_PERIOD);
  }

  // The 44 bytes of ArgusFrame with f.dt = dt.
  pack(view, dt) {
    view.setFloat32(0, this.time, true);
    view.setFloat32(4, dt, true);
    view.setUint32(8, this.frame, true);
    view.setUint32(12, this.width, true);
    view.setUint32(16, this.height, true);
    view.setUint32(20, this.stateW, true);
    view.setUint32(24, this.stateH, true);
    view.setUint32(28, this.seed, true);
    view.setInt32(32, this.daysJ2000, true);
    view.setFloat32(36, this.dayFrac, true);
    view.setInt32(40, this.utcOffsetS, true);
  }
}

// The app's frame pacing (src/desktop/frame_rate.zig) on the browser's own vsync: every display
// frame draws and advances f.time by the real interval; argus_step runs on a 30 Hz logic tick
// whatever the refresh rate. The first frame is a whole tick (tick 0 lands on frame 0 at every
// rate), and a stall moves time by at most one tick, as in the app.
export class Pacer {
  constructor() { this.started = false; this.phase = 0; }

  // -> { clockDt, stepDt | null }
  advance(dtSec) {
    const tick = 1 / LOGIC_HZ;
    if (!this.started) {
      this.started = true;
      this.phase = 0;
      return { clockDt: Math.fround(tick), stepDt: STEP_DT };
    }
    const dt = Math.min(Math.max(Number.isFinite(dtSec) ? dtSec : 0, 0), tick);
    this.phase += dt;
    // Half a millisecond of slack absorbs vsync jitter (120 Hz frames of 8.2 / 8.5 ms).
    if (this.phase >= tick - 0.0005) {
      this.phase = Math.max(this.phase - tick, 0);
      return { clockDt: Math.fround(dt), stepDt: STEP_DT };
    }
    return { clockDt: Math.fround(dt), stepDt: null };
  }
}

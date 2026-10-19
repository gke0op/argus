// themes/Fable_MoonPool.zig — ARGUS-BENCH zero-shot submission (Track B: PDE field dynamics)
//
// A rain-fed pool at night, lit by one moon.
//
// Physics (step):
//   The damped 2-D wave equation  u_tt = c^2 (u_xx + u_yy) - gamma u_t  is integrated
//   with an explicit leapfrog scheme on a 1/4-resolution cell grid (Courant number
//   K = 0.40 <= 0.5, unconditionally bounded in 2-D). Forcing: Gaussian raindrops at
//   pseudo-random positions (deterministic LCG) and one slowly drifting oscillating
//   source whose wave train is Doppler-compressed ahead of it. Walls are Dirichlet
//   (u = 0), so rings reflect off the pool edge.
//
// Optics (also in step, per cell, so the 2.3 M-pixel pass stays trivial):
//   - refraction : the tiled floor is sampled with an offset along the surface slope
//   - caustics   : light focusing under a thin lens  ~  1 - k * laplacian(u)
//   - reflection : slope-dependent Fresnel-style blend towards a dark night sky
//   - glints     : Blinn-Phong lobe cos^128 against a fixed moon half-vector
//
// draw() only bilinearly upsamples the shaded cell grid 4x with packed integer
// arithmetic (one 2-channel lerp per pixel), indexed by y * stride + x, alpha 0xFF.
//
// Gates: exactly one allocation (alloc.create(State), ~2.5 MiB, every table lives in
// State), zero allocations afterwards, no OS calls, all sqrt/div arguments bounded,
// every slope/laplacian clamped before use, stride-aware row slices only.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

// ---------------------------------------------------------------- grid geometry
const CELL: usize = 4; // screen pixels per simulation cell
const GW: usize = MAX_W / CELL + 2; // 482: +1 edge column for bilinear, +1 guard
const GH: usize = MAX_H / CELL + 2; // 302
const GRID: usize = GW * GH;
const GW_I: isize = @intCast(GW);

// ---------------------------------------------------------------- floor texture
const TEX: usize = 256;
const TEX_MASK: usize = TEX - 1;
const TILE: usize = 16; // texels per mosaic tile (= 16 cells = 64 px on screen)

// ---------------------------------------------------------------- wave equation
const K: f32 = 0.40; // c^2 dt^2 / dx^2
const DAMP: f32 = 0.9965; // fraction of velocity kept per substep
const SUB_DT: f64 = 0.004; // seconds per substep (dt = 0.008 -> exactly 2 substeps)
const MAX_SUBSTEPS: u32 = 6;
const DROP_PERIOD: u32 = 12; // substeps between raindrops
const WARMUP_TICKS: u32 = 180; // pre-roll so frame 1 is already alive

// ---------------------------------------------------------------- optics
const SLOPE: f32 = 2.2; // height units -> surface slope
const REFRACT: f32 = 6.0; // texels of floor displacement per unit slope
const CAUSTIC: f32 = 5.0; // caustic gain on the laplacian
const GLINT: f32 = 0.9; // moon glint strength
// Blinn-Phong half vector for light L = (0.40, -0.45, 0.80) and a top-down viewer.
const H_X: f32 = 0.2106;
const H_Y: f32 = -0.2369;
const H_Z: f32 = 0.9484;
const SKY0_R: f32 = 6.0;
const SKY0_G: f32 = 10.0;
const SKY0_B: f32 = 22.0;
const SKY1_R: f32 = 52.0;
const SKY1_G: f32 = 78.0;
const SKY1_B: f32 = 130.0;

// ---------------------------------------------------------------- helpers
inline fn hash2(x: u32, y: u32) u32 {
    var h: u32 = (x *% 0x8DA6B343) ^ (y *% 0xD8163841);
    h ^= h >> 15;
    h *%= 0x2C1B3C6D;
    h ^= h >> 12;
    h *%= 0x297A2D39;
    h ^= h >> 15;
    return h;
}

inline fn toByte(v: f32) u8 {
    return @intFromFloat(math.clamp(v, 0.0, 255.0));
}

/// Lerp two packRGBA pixels (word 0xFF_BB_GG_RR) with t in [0..256].
/// R and B ride in one multiply, G in another; alpha is forced to 0xFF.
/// Per channel the sum is <= 255 * 256 < 65536, so channels never carry.
inline fn lerpPix(c0: u32, c1: u32, t: u32) u32 {
    const it: u32 = 256 - t;
    const rb0: u32 = c0 & 0x00FF00FF;
    const rb1: u32 = c1 & 0x00FF00FF;
    const g0: u32 = c0 & 0x0000FF00;
    const g1: u32 = c1 & 0x0000FF00;
    const rb: u32 = ((rb0 * it + rb1 * t) >> 8) & 0x00FF00FF;
    const g: u32 = ((g0 * it + g1 * t) >> 8) & 0x0000FF00;
    return 0xFF000000 | rb | g;
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    accum: f64,

    gw: usize, // active cells per row   (w / CELL + 2)
    gh: usize, // active cells per column (h / CELL + 2)
    cur: usize, // which of bufs holds u(t); the other holds u(t - dt)
    ticks: u32,
    rng: u64,

    // Everything lives inside State: one alloc.create(State) in init, nothing after.
    bufs: [2][GRID]f32,
    cgrid: [GRID]u32, // shaded cell colours, packRGBA
    floor_r: [TEX * TEX]f32,
    floor_g: [TEX * TEX]f32,
    floor_b: [TEX * TEX]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.accum = 0.0;
        self.gw = @min(GW, self.w / CELL + 2);
        self.gh = @min(GH, self.h / CELL + 2);
        self.cur = 0;
        self.ticks = 0;
        self.rng = 0x9E3779B97F4A7C15;
        self.bufs[0] = @splat(0.0);
        self.bufs[1] = @splat(0.0);
        self.cgrid = @splat(sdk.packRGBA(0, 0, 0));

        self.buildFloor();

        var i: u32 = 0;
        while (i < WARMUP_TICKS) : (i += 1) self.tick();
        self.shade();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        const d = math.clamp(dt, 0.0, 0.1);
        self.time_sec += d;
        self.accum += d;
        var n: u32 = 0;
        while (self.accum >= SUB_DT and n < MAX_SUBSTEPS) : (n += 1) {
            self.accum -= SUB_DT;
            self.tick();
        }
        if (self.accum > SUB_DT) self.accum = SUB_DT;
        self.shade();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const gw = self.gw;
        const nb = w / CELL; // full 4-pixel blocks per row
        const tail = w - nb * CELL;
        var vrow: [GW]u32 = undefined;

        var y: usize = 0;
        while (y < h) : (y += 1) {
            const cy = y / CELL;
            const ty: u32 = @intCast((y % CELL) * (256 / CELL));
            const row_a = cy * GW;
            const row_b = (cy + 1) * GW;

            // vertical lerp of the two bracketing cell rows
            if (ty == 0) {
                @memcpy(vrow[0..gw], self.cgrid[row_a .. row_a + gw]);
            } else {
                var gx: usize = 0;
                while (gx < gw) : (gx += 1) {
                    vrow[gx] = lerpPix(self.cgrid[row_a + gx], self.cgrid[row_b + gx], ty);
                }
            }

            // horizontal lerp, unrolled per 4-pixel block (Gate 4: y * stride + x)
            const dst = buf[y * stride .. y * stride + w];
            var bx: usize = 0;
            while (bx < nb) : (bx += 1) {
                const c0 = vrow[bx];
                const c1 = vrow[bx + 1];
                const o = bx * CELL;
                dst[o] = c0;
                dst[o + 1] = lerpPix(c0, c1, 64);
                dst[o + 2] = lerpPix(c0, c1, 128);
                dst[o + 3] = lerpPix(c0, c1, 192);
            }
            var k: usize = 0;
            while (k < tail) : (k += 1) {
                const tx: u32 = @intCast(k * (256 / CELL));
                dst[nb * CELL + k] = lerpPix(vrow[nb], vrow[nb + 1], tx);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        const u = &self.bufs[self.cur];
        const n = self.gh * GW;
        var acc: f32 = 0.0;
        var i: usize = 0;
        while (i < n) : (i += 1) acc += u[i];
        return math.isNan(acc) or math.isInf(acc);
    }

    // ------------------------------------------------------------ simulation

    fn randU32(self: *State) u32 {
        self.rng = self.rng *% 6364136223846793005 +% 1442695040888963407;
        return @as(u32, @truncate(self.rng >> 32));
    }

    /// One leapfrog substep of the damped wave equation on the interior cells.
    /// Reads u(t) from bufs[cur], overwrites u(t - dt) in the other buffer with u(t + dt).
    fn waveSubstep(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const cur = self.cur;
        const u = &self.bufs[cur];
        const p = &self.bufs[1 - cur];
        var gy: usize = 1;
        while (gy + 1 < gh) : (gy += 1) {
            const row = gy * GW;
            var gx: usize = 1;
            while (gx + 1 < gw) : (gx += 1) {
                const i = row + gx;
                const c = u[i];
                const lap = u[i - 1] + u[i + 1] + u[i - GW] + u[i + GW] - 4.0 * c;
                p[i] = c + (c - p[i]) * DAMP + K * lap;
            }
        }
        self.cur = 1 - cur;
    }

    /// Adds a Gaussian displacement (zero initial velocity) to both time levels.
    fn addDrop(self: *State, cx: isize, cy: isize, amp: f32, rad: isize) void {
        const gw_i: isize = @intCast(self.gw);
        const gh_i: isize = @intCast(self.gh);
        const fr: f32 = @floatFromInt(rad * rad);
        var dy: isize = -rad;
        while (dy <= rad) : (dy += 1) {
            const yy = cy + dy;
            if (yy < 1 or yy >= gh_i - 1) continue;
            var dx: isize = -rad;
            while (dx <= rad) : (dx += 1) {
                const xx = cx + dx;
                if (xx < 1 or xx >= gw_i - 1) continue;
                const fd: f32 = @floatFromInt(dx * dx + dy * dy);
                const g = amp * @exp(-2.5 * fd / fr);
                const i: usize = @intCast(yy * GW_I + xx);
                self.bufs[0][i] += g;
                self.bufs[1][i] += g;
            }
        }
    }

    fn spawnDrop(self: *State) void {
        if (self.gw < 10 or self.gh < 10) return;
        const span_x: u32 = @intCast(self.gw - 8);
        const span_y: u32 = @intCast(self.gh - 8);
        const rx: isize = @intCast(4 + self.randU32() % span_x);
        const ry: isize = @intCast(4 + self.randU32() % span_y);
        const ra = self.randU32() % 1000;
        const amp: f32 = 0.7 + 1.3 * @as(f32, @floatFromInt(ra)) * 0.001;
        self.addDrop(rx, ry, amp, 4);
    }

    fn tick(self: *State) void {
        self.ticks += 1;
        if (self.ticks % DROP_PERIOD == 0) self.spawnDrop();

        // A slowly drifting oscillating source on a Lissajous path (sub-sonic,
        // so its wave train is compressed ahead and stretched behind).
        const tf: f32 = @as(f32, @floatFromInt(self.ticks)) * 0.0025;
        const gwf: f32 = @floatFromInt(self.gw);
        const ghf: f32 = @floatFromInt(self.gh);
        const fx = 0.5 + 0.33 * @sin(tf * 0.9);
        const fy = 0.5 + 0.30 * @sin(tf * 1.3 + 1.7);
        const sx: isize = @intFromFloat(fx * gwf);
        const sy: isize = @intFromFloat(fy * ghf);
        const amp = 0.10 * @sin(@as(f32, @floatFromInt(self.ticks)) * 0.35);
        self.addDrop(sx, sy, amp, 2);

        self.waveSubstep();
    }

    // ------------------------------------------------------------ shading

    /// Shades every active cell from the current height field into cgrid.
    fn shade(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const u = &self.bufs[self.cur];
        const half_w: f32 = @as(f32, @floatFromInt(gw)) * 0.5;
        const half_h: f32 = @as(f32, @floatFromInt(gh)) * 0.5;
        const inv_hw: f32 = 1.0 / @max(half_w, 1.0);
        const inv_hh: f32 = 1.0 / @max(half_h, 1.0);

        var gy: usize = 0;
        while (gy < gh) : (gy += 1) {
            const ym = if (gy > 0) gy - 1 else gy;
            const yp = if (gy + 1 < gh) gy + 1 else gy;
            const row = gy * GW;
            const row_m = ym * GW;
            const row_p = yp * GW;
            const fyc: f32 = @floatFromInt(gy);
            const ddy = (fyc - half_h) * inv_hh;

            var gx: usize = 0;
            while (gx < gw) : (gx += 1) {
                const xm = if (gx > 0) gx - 1 else gx;
                const xp = if (gx + 1 < gw) gx + 1 else gx;
                const c = u[row + gx];
                const l = u[row + xm];
                const r = u[row + xp];
                const t = u[row_m + gx];
                const b = u[row_p + gx];

                // surface slope and curvature (all clamped: no NaN/Inf can escape)
                const sx = math.clamp((r - l) * (0.5 * SLOPE), -8.0, 8.0);
                const sy = math.clamp((b - t) * (0.5 * SLOPE), -8.0, 8.0);
                const lap = math.clamp(l + r + t + b - 4.0 * c, -4.0, 4.0);
                const inv_n = 1.0 / @sqrt(1.0 + sx * sx + sy * sy);
                const nx = -sx * inv_n;
                const ny = -sy * inv_n;
                const nz = inv_n;

                // refracted floor sample (offset is positive: +4096 keeps it >= 0)
                const fxc: f32 = @floatFromInt(gx);
                const tx_f = fxc + sx * REFRACT + 4096.0;
                const ty_f = fyc + sy * REFRACT + 4096.0;
                const ti: usize = @as(usize, @intFromFloat(tx_f)) & TEX_MASK;
                const tj: usize = @as(usize, @intFromFloat(ty_f)) & TEX_MASK;
                const tidx = tj * TEX + ti;

                // thin-lens caustic + radial depth vignette
                const caus = math.clamp(1.0 - lap * CAUSTIC, 0.2, 2.8);
                const ddx = (fxc - half_w) * inv_hw;
                const vig = 1.0 - 0.32 * @min(1.0, ddx * ddx + ddy * ddy);
                const fl = caus * vig;
                const flr_r = self.floor_r[tidx] * fl;
                const flr_g = self.floor_g[tidx] * fl;
                const flr_b = self.floor_b[tidx] * fl;

                // slope-dependent reflection of the night sky
                const fres = 0.06 + 0.70 * @min(1.0, (1.0 - nz) * 12.0);
                const up = math.clamp(0.5 - ny * 2.0, 0.0, 1.0);
                const sky_r = SKY0_R + (SKY1_R - SKY0_R) * up;
                const sky_g = SKY0_G + (SKY1_G - SKY0_G) * up;
                const sky_b = SKY0_B + (SKY1_B - SKY0_B) * up;

                // moon glint: cos^128 via seven squarings
                const spec0 = @max(0.0, nx * H_X + ny * H_Y + nz * H_Z);
                var s = spec0 * spec0; // ^2
                s *= s; // ^4
                s *= s; // ^8
                s *= s; // ^16
                s *= s; // ^32
                s *= s; // ^64
                s *= s; // ^128
                const glint = s * GLINT * 255.0;

                const keep = 1.0 - fres;
                const out_r = flr_r * keep + sky_r * fres + glint;
                const out_g = flr_g * keep + sky_g * fres + glint * 0.94;
                const out_b = flr_b * keep + sky_b * fres + glint * 0.80;
                self.cgrid[row + gx] = sdk.packRGBA(toByte(out_r), toByte(out_g), toByte(out_b));
            }
        }
    }

    /// Mosaic pool floor: 16x16-texel tiles with per-tile tone, a soft bevel,
    /// dark grout and a little texel noise. Built once in init.
    fn buildFloor(self: *State) void {
        var ty: usize = 0;
        while (ty < TEX) : (ty += 1) {
            var tx: usize = 0;
            while (tx < TEX) : (tx += 1) {
                const tile_x: u32 = @intCast(tx / TILE);
                const tile_y: u32 = @intCast(ty / TILE);
                const in_x = tx % TILE;
                const in_y = ty % TILE;
                const th = hash2(tile_x, tile_y);
                const v1: f32 = @as(f32, @floatFromInt(th & 0xFF)) * (1.0 / 255.0);
                const v2: f32 = @as(f32, @floatFromInt((th >> 8) & 0xFF)) * (1.0 / 255.0);
                const nh = hash2(@intCast(tx + 1000), @intCast(ty + 2000));
                const noise: f32 = (@as(f32, @floatFromInt(nh & 0xFF)) * (1.0 / 255.0) - 0.5) * 10.0;
                const e_x: usize = @min(in_x, TILE - 1 - in_x);
                const e_y: usize = @min(in_y, TILE - 1 - in_y);
                const e: usize = @min(e_x, e_y);

                const col: [3]f32 = if (e == 0) .{ 10.0, 26.0, 38.0 } else blk: {
                    const ef: f32 = @floatFromInt(@min(e, 3));
                    const bevel = 0.72 + 0.28 * ef * (1.0 / 3.0);
                    const r = (16.0 + 28.0 * v2 + noise) * bevel;
                    const g = (88.0 + 44.0 * v1 + noise) * bevel;
                    const b = (122.0 + 34.0 * (1.0 - v2) + noise) * bevel;
                    break :blk .{ r, g, b };
                };

                const idx = ty * TEX + tx;
                self.floor_r[idx] = math.clamp(col[0], 0.0, 255.0);
                self.floor_g[idx] = math.clamp(col[1], 0.0, 255.0);
                self.floor_b[idx] = math.clamp(col[2], 0.0, 255.0);
            }
        }
    }
};

comptime {
    sdk.exportTheme(State);
}

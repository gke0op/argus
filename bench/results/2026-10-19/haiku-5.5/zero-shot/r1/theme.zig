//! ARGUS-BENCH Track B: damped 2D wave field driven by three Lissajous emitters.
//! The PDE runs on a 320x200 grid (wave speed 60 cells/s, symplectic Euler with
//! reflecting edges, fixed 8 ms substeps, CFL 0.48 < 0.71). Each pixel reads its
//! grid cell through precomputed column/row maps, so draw() is table lookups and
//! saturating adds only: no transcendental functions per pixel.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

pub const GW: usize = 320;
pub const GH: usize = 200;
pub const GN: usize = GW * GH;
const GWF: f64 = @floatFromInt(GW);
const GHF: f64 = @floatFromInt(GH);

const SUB_DT: f64 = 0.008;
const MAX_SUBSTEPS: u32 = 4;
const WAVE_C: f32 = 60.0;
const WAVE_C2: f32 = WAVE_C * WAVE_C;
const DAMP: f32 = 0.22;
const FIELD_CLAMP: f32 = 4.0;
const VEL_CLAMP: f32 = 400.0;
const MAG_GAIN: f32 = 2.4;
const PALETTE_N: usize = 256;
const STAR_N: usize = 640;
const SOURCE_N: usize = 3;
const SRC_AMP: f64 = 3.0;
const SRC_OMEGA: f64 = 14.0;

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    acc: f64,

    // Wave field on the GW x GH grid: displacement p and velocity q.
    p: [GN]f32,
    q: [GN]f32,
    cell_color: [GN]u32,

    // Pixel -> grid mapping, filled once in init().
    col_map: [MAX_W]u32,
    row_base: [MAX_H]u32,
    row_bg: [MAX_H]u32,

    pal_pos: [PALETTE_N]u32,
    pal_neg: [PALETTE_N]u32,

    star_x: [STAR_N]u32,
    star_y: [STAR_N]u32,
    star_r: [STAR_N]u8,
    star_g: [STAR_N]u8,
    star_b: [STAR_N]u8,
    star_freq: [STAR_N]f32,
    star_phase: [STAR_N]f32,
    star_draw: [STAR_N]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @max(@as(usize, 1), @min(w, MAX_W));
        self.h = @max(@as(usize, 1), @min(h, MAX_H));
        self.scale = scale;
        self.time_sec = 0.0;
        self.acc = 0.0;

        @memset(self.p[0..], 0.0);
        @memset(self.q[0..], 0.0);
        @memset(self.cell_color[0..], sdk.packRGBA(0, 0, 0));

        // Crest (positive) and trough (negative) ramps, 256 entries each.
        for (0..PALETTE_N) |i| {
            const t: f64 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(PALETTE_N - 1));
            self.pal_pos[i] = ramp(t, .{ 6.0, 20.0, 44.0 }, .{ 70.0, 230.0, 230.0 }, .{ 255.0, 246.0, 214.0 });
            self.pal_neg[i] = ramp(t, .{ 6.0, 20.0, 44.0 }, .{ 70.0, 40.0, 160.0 }, .{ 210.0, 130.0, 255.0 });
        }

        for (0..self.w) |x| {
            self.col_map[x] = @as(u32, @intCast((x * GW) / self.w));
        }
        for (0..self.h) |y| {
            self.row_base[y] = @as(u32, @intCast((y * GH) / self.h)) * GW;
            const t256: u32 = @as(u32, @intCast((y * 256) / self.h));
            self.row_bg[y] = sdk.lerpRGB(sdk.packRGBA(3, 5, 16), sdk.packRGBA(14, 30, 58), t256);
        }

        // Static starfield, placed with a deterministic xorshift stream.
        var rng: u32 = 0x2545F491;
        for (0..STAR_N) |i| {
            rng = xorshift(rng);
            self.star_x[i] = rng % @as(u32, @intCast(self.w));
            rng = xorshift(rng);
            self.star_y[i] = rng % @as(u32, @intCast(self.h));
            rng = xorshift(rng);
            const bright: u32 = 150 + rng % 106;
            const bb: u32 = if (bright + 20 > 255) 255 else bright + 20;
            self.star_r[i] = @as(u8, @intCast(bright - 30));
            self.star_g[i] = @as(u8, @intCast(bright - 10));
            self.star_b[i] = @as(u8, @intCast(bb));
            rng = xorshift(rng);
            const fr: f32 = @floatFromInt(rng % 1000);
            self.star_freq[i] = 0.3 + 1.2 * fr / 1000.0;
            rng = xorshift(rng);
            const fp: f32 = @floatFromInt(rng % 1000);
            self.star_phase[i] = 6.2831853 * fp / 1000.0;
        }

        refreshColors(self);
        updateStars(self);
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        const safe_dt: f64 = if (math.isFinite(dt) and dt > 0.0) dt else 0.0;
        self.time_sec += safe_dt;
        self.acc += safe_dt;
        var n: u32 = 0;
        while (self.acc >= SUB_DT - 1.0e-9 and n < MAX_SUBSTEPS) : (n += 1) {
            self.acc -= SUB_DT;
            simulate(self, SUB_DT, self.time_sec);
        }
        if (self.acc > SUB_DT) self.acc = 0.0;
        refreshColors(self);
        updateStars(self);
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const cmap = self.col_map[0..w];
        for (0..h) |y| {
            const dst = buf[y * stride .. y * stride + w];
            const base: usize = @as(usize, self.row_base[y]);
            const bg = self.row_bg[y];
            for (dst, cmap) |*d, c| {
                const cell: usize = base + @as(usize, c);
                d.* = sdk.addRGB(bg, self.cell_color[cell]);
            }
        }
        for (0..STAR_N) |i| {
            const idx: usize = @as(usize, self.star_y[i]) * stride + @as(usize, self.star_x[i]);
            buf[idx] = self.star_draw[i];
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        var s: f32 = 0.0;
        for (self.p) |v| s += v;
        return math.isNan(s) or math.isInf(s);
    }
};

/// One wave update of size dt at simulation time t.
fn simulate(self: *State, dt: f64, t: f64) void {
    const dtf: f32 = @as(f32, @floatCast(dt));

    // Drivers: three Lissajous emitters, each a small disc of forcing.
    for (0..SOURCE_N) |k| {
        const kf: f64 = @as(f64, @floatFromInt(k));
        const tk: f64 = t + 1.7 * kf;
        const cx: f64 = 0.5 + 0.34 * @sin(0.21 * tk + 2.1 * kf);
        const cy: f64 = 0.5 + 0.30 * @sin(0.17 * tk + 1.3 * kf + 0.7);
        const drive: f32 = @as(f32, @floatCast(SRC_AMP * @sin(SRC_OMEGA * tk)));
        const cxi: isize = @as(isize, @intFromFloat(cx * GWF));
        const cyi: isize = @as(isize, @intFromFloat(cy * GHF));
        var dy: isize = -2;
        while (dy <= 2) : (dy += 1) {
            var dx: isize = -2;
            while (dx <= 2) : (dx += 1) {
                if (dx * dx + dy * dy > 4) continue;
                const xx: isize = cxi + dx;
                const yy: isize = cyi + dy;
                if (xx < 0 or yy < 0 or xx >= GW or yy >= GH) continue;
                const id: usize = @as(usize, @intCast(yy)) * GW + @as(usize, @intCast(xx));
                self.q[id] += drive * dtf;
            }
        }
    }

    // Velocity update from the reflecting-edge 5-point Laplacian of p.
    for (0..GH) |yy| {
        const up: usize = if (yy == 0) 0 else yy - 1;
        const dn: usize = if (yy + 1 >= GH) GH - 1 else yy + 1;
        const row = yy * GW;
        const row_up = up * GW;
        const row_dn = dn * GW;
        for (0..GW) |xx| {
            const lf: usize = if (xx == 0) 0 else xx - 1;
            const rt: usize = if (xx + 1 >= GW) GW - 1 else xx + 1;
            const i = row + xx;
            const c = self.p[i];
            const lap: f32 = self.p[row_up + xx] + self.p[row_dn + xx] + self.p[row + lf] + self.p[row + rt] - 4.0 * c;
            const qi = self.q[i];
            self.q[i] = clampf(qi + dtf * (WAVE_C2 * lap - DAMP * qi), VEL_CLAMP);
        }
    }

    // Displacement update.
    for (0..GN) |i| {
        self.p[i] = clampf(self.p[i] + dtf * self.q[i], FIELD_CLAMP);
    }
}

/// Maps each grid cell to a packed colour: crest or trough palette, by magnitude.
fn refreshColors(self: *State) void {
    for (0..GN) |i| {
        const v: f32 = self.p[i];
        const mag: f32 = @min(@as(f32, 1.0), @abs(v) * MAG_GAIN);
        const idx: usize = @as(usize, @intFromFloat(mag * 255.0));
        self.cell_color[i] = if (v >= 0.0) self.pal_pos[idx] else self.pal_neg[idx];
    }
}

/// Twinkles the starfield (640 sines per frame, nothing per pixel).
fn updateStars(self: *State) void {
    for (0..STAR_N) |i| {
        const ph: f64 = self.time_sec * @as(f64, self.star_freq[i]) + @as(f64, self.star_phase[i]);
        const s_f: f64 = 0.55 + 0.45 * @sin(ph);
        const s256: u32 = @as(u32, @intFromFloat(s_f * 256.0));
        self.star_draw[i] = sdk.packRGBA(
            scale8(self.star_r[i], s256),
            scale8(self.star_g[i], s256),
            scale8(self.star_b[i], s256),
        );
    }
}

fn ramp(t: f64, c0: [3]f64, c1: [3]f64, c2: [3]f64) u32 {
    const knee: f64 = 0.6;
    var out: [3]f64 = undefined;
    for (0..3) |k| {
        out[k] = if (t < knee)
            c0[k] + (c1[k] - c0[k]) * (t / knee)
        else
            c1[k] + (c2[k] - c1[k]) * ((t - knee) / (1.0 - knee));
    }
    return sdk.packRGBA(toByte(out[0]), toByte(out[1]), toByte(out[2]));
}

fn toByte(v: f64) u8 {
    const c: f64 = @max(0.0, @min(255.0, v));
    return @as(u8, @intFromFloat(c));
}

inline fn clampf(v: f32, lim: f32) f32 {
    return @max(-lim, @min(lim, v));
}

inline fn scale8(v: u8, s256: u32) u8 {
    const prod: u32 = @as(u32, v) * s256;
    return @as(u8, @intCast(prod >> 8));
}

inline fn xorshift(s: u32) u32 {
    var x = s;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

comptime {
    sdk.exportTheme(State);
}

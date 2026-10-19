// Opus55_Field — ARGUS-BENCH Track B (PDE field dynamics), agentic mode.
//
// The Gray–Scott reaction–diffusion system
//     du/dt = Du ∇²u − u v² + F (1 − u)
//     dv/dt = Dv ∇²v + u v² − (F + k) v
// integrated live (explicit Euler, 5-point Laplacian, periodic domain) on a
// 481×301 grid (one cell per 4×4 Retina pixels). The feed rate F and kill rate
// k vary smoothly across the screen and drift slowly in time, so the plate holds
// several of Pearson's regimes at once — chaotic fronts, labyrinths, dividing
// spots — and the borders between them keep moving. The v-field is rendered as
// a glossy relief: normals from its gradient, a key light, Blinn–Phong specular.
//
// Budget: the PDE runs in 8-wide SIMD; shading is done once per cell in step();
// draw() is a separable bilinear upsample of three colour planes, no
// transcendentals per pixel.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const CELL: usize = 4; // pixels per grid cell (each axis)
const GW_MAX: usize = MAX_W / CELL + 1; // 481 real columns
const GH_MAX: usize = MAX_H / CELL + 1; // 301 real rows
const P: usize = 496; // row pitch: ghost + 488 (61 chunks of 8) + ghost, padded to 8
const ROWS: usize = GH_MAX + 2;
const N: usize = P * ROWS;

const V8 = @Vector(8, f32);
const V4 = @Vector(4, f32);
const U4 = @Vector(4, u32);
const U8v = @Vector(8, u32);

// Diffusion coefficients in grid units with dt = 1 (Pearson 1993 ratio 2:1).
const DU: f32 = 0.2097;
const DV: f32 = 0.105;
// PDE iterations per simulated second (≈15 per 60 Hz frame).
const ITER_RATE: f64 = 900.0;
const MAX_ITERS_PER_STEP: u32 = 40;
// Iterations run inside init() so the first frame already shows a mature pattern.
const WARMUP_ITERS: u32 = 3000;

const PAL_N: usize = 256;
const PAL_MAXF: f32 = 255.0;
const INV_CELL: f32 = 0.25;

pub const State = struct {
    w: usize,
    h: usize,
    gw: usize,
    gh: usize,
    scale: f64,
    time_sec: f64,
    iter_acc: f64,
    total_iters: u64,
    field_sum: f64,
    cur: u1,

    u: [2][N]f32,
    v: [2][N]f32,
    feed: [N]f32,
    kill: [N]f32,
    vig: [N]f32,

    // Shaded colour planes (0..255), compact, row pitch P, real cells only.
    cr: [N]f32,
    cg: [N]f32,
    cb: [N]f32,

    pal: [PAL_N][3]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.gw = @min(GW_MAX, (self.w + CELL - 1) / CELL + 1);
        self.gh = @min(GH_MAX, (self.h + CELL - 1) / CELL + 1);
        self.scale = scale;
        self.time_sec = 0.0;
        self.iter_acc = 0.0;
        self.total_iters = 0;
        self.field_sum = 0.0;
        self.cur = 0;

        for (0..2) |b| {
            self.u[b] = @splat(1.0);
            self.v[b] = @splat(0.0);
        }
        self.cr = @splat(0.0);
        self.cg = @splat(0.0);
        self.cb = @splat(0.0);

        self.buildParamMap();
        self.buildPalette();
        self.seed(0x9E3779B97F4A7C15);

        var i: u32 = 0;
        while (i < WARMUP_ITERS) : (i += 1) self.iterate(0.0);
        self.shade();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    // ---------------------------------------------------------------- setup

    fn buildParamMap(self: *State) void {
        // F wanders over [0.018, 0.058] in large smooth basins; k sits a
        // controlled distance below/above the saddle-node line k_sn = √F/2 − F,
        // which is where Gray–Scott patterns live.
        const gwf: f32 = @floatFromInt(self.gw);
        const ghf: f32 = @floatFromInt(self.gh);
        for (0..P) |c| {
            for (0..ROWS) |r| {
                const idx = r * P + c;
                // Torus coordinates of real cell (c-1, r-1): the map uses whole
                // periods only, so the periodic domain has no parameter seam.
                const x: f32 = (@as(f32, @floatFromInt(c)) - 1.0) / gwf;
                const y: f32 = (@as(f32, @floatFromInt(r)) - 1.0) / ghf;
                const tau: f32 = 6.2831853;
                const a = 0.5 + 0.26 * @sin(tau * (x + y) + 1.3) + 0.24 * @cos(tau * (2.0 * x - y) - 0.4);
                const bq = @sin(tau * (y - x) + 2.1) * 0.6 + @sin(tau * (3.0 * x) + 0.7 * @sin(tau * y)) * 0.4;
                const f_rate: f32 = 0.024 + 0.026 * a;
                const k_sn = @sqrt(f_rate) * 0.5 - f_rate;
                // Low F leans chaotic (k below the line), high F leans to solitons.
                const delta: f32 = 0.0022 - 0.0050 * a + 0.0012 * bq; // k = k_sn - delta
                self.feed[idx] = f_rate;
                self.kill[idx] = k_sn - delta;
                // Soft elliptical vignette (a lamp over a dish).
                const dx = (x - 0.5) * 1.6;
                const dy = (y - 0.5) * 1.6;
                const d2 = dx * dx + dy * dy;
                self.vig[idx] = 1.0 - 0.45 * @min(@as(f32, 1.0), d2 * d2 * 0.6 + d2 * 0.25);
            }
        }
    }

    fn buildPalette(self: *State) void {
        const Stop = struct { t: f32, c: [3]f32 };
        const stops = [_]Stop{
            .{ .t = 0.00, .c = .{ 5, 10, 24 } },
            .{ .t = 0.10, .c = .{ 9, 34, 58 } },
            .{ .t = 0.30, .c = .{ 16, 98, 112 } },
            .{ .t = 0.52, .c = .{ 92, 178, 168 } },
            .{ .t = 0.72, .c = .{ 232, 220, 186 } },
            .{ .t = 0.88, .c = .{ 246, 184, 104 } },
            .{ .t = 1.00, .c = .{ 214, 104, 62 } },
        };
        for (0..PAL_N) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(PAL_N - 1));
            var s: usize = 0;
            while (s + 2 < stops.len and t > stops[s + 1].t) s += 1;
            const a = stops[s];
            const b = stops[s + 1];
            const f = math.clamp((t - a.t) / (b.t - a.t), 0.0, 1.0);
            const sm = f * f * (3.0 - 2.0 * f);
            for (0..3) |ch| self.pal[i][ch] = a.c[ch] + (b.c[ch] - a.c[ch]) * sm;
        }
    }

    fn seed(self: *State, s0: u64) void {
        var s = s0;
        const nseeds: usize = @max(@as(usize, 8), (self.gw * self.gh) / 220);
        for (0..nseeds) |_| {
            s ^= s << 13;
            s ^= s >> 7;
            s ^= s << 17;
            const cx: usize = @as(usize, @intCast(s % self.gw)) + 1;
            const cy: usize = @as(usize, @intCast((s >> 24) % self.gh)) + 1;
            const rad: usize = 1 + @as(usize, @intCast((s >> 48) % 3));
            var yy: usize = cy -| rad;
            while (yy <= @min(cy + rad, self.gh)) : (yy += 1) {
                var xx: usize = cx -| rad;
                while (xx <= @min(cx + rad, self.gw)) : (xx += 1) {
                    if (xx == 0 or yy == 0) continue;
                    self.u[0][yy * P + xx] = 0.50;
                    self.v[0][yy * P + xx] = 0.25;
                }
            }
        }
    }

    // ------------------------------------------------------------- dynamics

    inline fn fillGhosts(self: *State, b: usize) void {
        const gw = self.gw;
        const gh = self.gh;
        const u = &self.u[b];
        const v = &self.v[b];
        for (1..gh + 1) |r| {
            const o = r * P;
            u[o] = u[o + gw];
            v[o] = v[o + gw];
            u[o + gw + 1] = u[o + 1];
            v[o + gw + 1] = v[o + 1];
        }
        @memcpy(u[0..P], u[gh * P .. gh * P + P]);
        @memcpy(v[0..P], v[gh * P .. gh * P + P]);
        @memcpy(u[(gh + 1) * P .. (gh + 2) * P], u[P .. 2 * P]);
        @memcpy(v[(gh + 1) * P .. (gh + 2) * P], v[P .. 2 * P]);
    }

    fn iterate(self: *State, k_drift: f32) void {
        const src: usize = self.cur;
        const dst: usize = 1 - src;
        self.fillGhosts(src);
        const us = &self.u[src];
        const vs = &self.v[src];
        const ud = &self.u[dst];
        const vd = &self.v[dst];
        const du: V8 = @splat(DU);
        const dv: V8 = @splat(DV);
        const one: V8 = @splat(1.0);
        const four: V8 = @splat(4.0);
        const kd: V8 = @splat(k_drift);
        const gw = self.gw;
        for (1..self.gh + 1) |r| {
            var c: usize = 1;
            while (c < gw + 1) : (c += 8) {
                const i = r * P + c;
                const uc: V8 = us[i..][0..8].*;
                const vc: V8 = vs[i..][0..8].*;
                const lu = @as(V8, us[i - 1 ..][0..8].*) + @as(V8, us[i + 1 ..][0..8].*) +
                    @as(V8, us[i - P ..][0..8].*) + @as(V8, us[i + P ..][0..8].*) - four * uc;
                const lv = @as(V8, vs[i - 1 ..][0..8].*) + @as(V8, vs[i + 1 ..][0..8].*) +
                    @as(V8, vs[i - P ..][0..8].*) + @as(V8, vs[i + P ..][0..8].*) - four * vc;
                const f: V8 = self.feed[i..][0..8].*;
                const k: V8 = @as(V8, self.kill[i..][0..8].*) + kd;
                const uvv = uc * vc * vc;
                ud[i..][0..8].* = uc + du * lu - uvv + f * (one - uc);
                vd[i..][0..8].* = vc + dv * lv + uvv - (f + k) * vc;
            }
        }
        self.cur = @intCast(dst);
        self.total_iters += 1;
    }

    // ------------------------------------------------------------- shading

    fn shade(self: *State) void {
        const b: usize = self.cur;
        self.fillGhosts(b);
        const v = &self.v[b];
        const u = &self.u[b];
        // Key light from the upper left, viewer straight on (Blinn–Phong).
        const lx: f32 = -0.48;
        const ly: f32 = -0.56;
        const lz: f32 = 0.675;
        const hn = 1.0 / @sqrt(lx * lx + ly * ly + (lz + 1.0) * (lz + 1.0));
        const LX: V8 = @splat(lx);
        const LY: V8 = @splat(ly);
        const LZ: V8 = @splat(lz);
        const HX: V8 = @splat(lx * hn);
        const HY: V8 = @splat(ly * hn);
        const HZ: V8 = @splat((lz + 1.0) * hn);
        const relief: V8 = @splat(5.5);
        const zero: V8 = @splat(0.0);
        const one: V8 = @splat(1.0);
        const c255: V8 = @splat(255.0);
        var acc: V8 = @splat(0.0);
        var sum: f64 = 0.0;
        for (1..self.gh + 1) |r| {
            var c: usize = 1;
            while (c < self.gw + 1) : (c += 8) {
                const i = r * P + c;
                const val: V8 = v[i..][0..8].*;
                const uu: V8 = u[i..][0..8].*;
                // Only real cells enter the NaN/Inf guard sum.
                if (c + 8 <= self.gw + 1) {
                    acc += val + uu;
                } else {
                    const va: [8]f32 = val;
                    const ua: [8]f32 = uu;
                    var k: usize = 0;
                    while (c + k < self.gw + 1) : (k += 1) sum += va[k] + ua[k];
                }
                const gx = (@as(V8, v[i + 1 ..][0..8].*) - @as(V8, v[i - 1 ..][0..8].*)) * relief;
                const gy = (@as(V8, v[i + P ..][0..8].*) - @as(V8, v[i - P ..][0..8].*)) * relief;
                const inv = one / @sqrt(gx * gx + gy * gy + one);
                const nx = -gx * inv;
                const ny = -gy * inv;
                const ndl = @max(zero, nx * LX + ny * LY + inv * LZ);
                var ndh = @max(zero, nx * HX + ny * HY + inv * HZ);
                ndh *= ndh; // ^2
                ndh *= ndh; // ^4
                ndh *= ndh; // ^8
                ndh *= ndh; // ^16
                ndh *= ndh; // ^32
                const t = @min(one, @max(zero, val * @as(V8, @splat(2.6))));
                const ti: @Vector(8, u32) = @intFromFloat(t * @as(V8, @splat(PAL_MAXF)));
                var ar: V8 = undefined;
                var ag: V8 = undefined;
                var ab: V8 = undefined;
                inline for (0..8) |k| {
                    const p = self.pal[ti[k]];
                    ar[k] = p[0];
                    ag[k] = p[1];
                    ab[k] = p[2];
                }
                const gloss = @as(V8, @splat(0.25)) + @as(V8, @splat(0.75)) * t;
                const lit = @as(V8, @splat(0.30)) + @as(V8, @splat(0.85)) * ndl;
                const vg: V8 = self.vig[i..][0..8].*;
                const spec = @as(V8, @splat(210.0)) * ndh * gloss;
                const o = (r - 1) * P + (c - 1);
                self.cr[o..][0..8].* = @min(c255, @max(zero, (ar * lit + spec) * vg));
                self.cg[o..][0..8].* = @min(c255, @max(zero, (ag * lit + spec * @as(V8, @splat(0.97))) * vg));
                self.cb[o..][0..8].* = @min(c255, @max(zero, (ab * lit + spec * @as(V8, @splat(0.90))) * vg));
            }
        }
        sum += @reduce(.Add, acc);
        self.field_sum = sum;
    }

    pub fn step(self: *State, dt: f64) void {
        const dts = math.clamp(dt, 0.0, 0.25);
        self.time_sec += dts;
        self.iter_acc += dts * ITER_RATE;
        var n: u32 = @intFromFloat(@floor(self.iter_acc));
        self.iter_acc -= @floatFromInt(n);
        if (n > MAX_ITERS_PER_STEP) n = MAX_ITERS_PER_STEP;
        // Slow breathing of the kill rate (period ≈ 4 min) keeps borders moving.
        const drift: f32 = @floatCast(0.0009 * @sin(self.time_sec * (2.0 * math.pi / 240.0)));
        var i: u32 = 0;
        while (i < n) : (i += 1) self.iterate(drift);
        self.shade();
    }

    // --------------------------------------------------------------- draw

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const gw = self.gw;
        const full_cells = w / CELL;
        var tr: [P]f32 = undefined;
        var tg: [P]f32 = undefined;
        var tb: [P]f32 = undefined;
        const ramp: V4 = .{ 0.0, 0.25, 0.5, 0.75 };
        const alpha: U4 = @splat(0xFF000000);
        const alpha8: U8v = @splat(0xFF000000);
        const ramp8: V8 = .{ 0.0, 0.25, 0.5, 0.75, 0.0, 0.25, 0.5, 0.75 };
        for (0..self.h) |y| {
            const ry = y / CELL;
            const ty: f32 = @as(f32, @floatFromInt(y % CELL)) * INV_CELL;
            const a0 = ry * P;
            const a1 = (ry + 1) * P;
            const tyv: V8 = @splat(ty);
            var c: usize = 0;
            while (c < gw) : (c += 8) {
                const r0: V8 = self.cr[a0 + c ..][0..8].*;
                const r1: V8 = self.cr[a1 + c ..][0..8].*;
                const g0: V8 = self.cg[a0 + c ..][0..8].*;
                const g1: V8 = self.cg[a1 + c ..][0..8].*;
                const b0: V8 = self.cb[a0 + c ..][0..8].*;
                const b1: V8 = self.cb[a1 + c ..][0..8].*;
                tr[c..][0..8].* = r0 + (r1 - r0) * tyv;
                tg[c..][0..8].* = g0 + (g1 - g0) * tyv;
                tb[c..][0..8].* = b0 + (b1 - b0) * tyv;
            }
            const row = buf[y * stride .. y * stride + w];
            // 8 cells (32 pixels) per pass: one load of 8 cell values, spread to
            // 4 pixels each with shuffles, lerped across the cell with a ramp.
            var cx: usize = 0;
            while (cx + 8 <= full_cells) : (cx += 8) {
                const r0: V8 = tr[cx..][0..8].*;
                const g0: V8 = tg[cx..][0..8].*;
                const b0: V8 = tb[cx..][0..8].*;
                const rd = @as(V8, tr[cx + 1 ..][0..8].*) - r0;
                const gd = @as(V8, tg[cx + 1 ..][0..8].*) - g0;
                const bd = @as(V8, tb[cx + 1 ..][0..8].*) - b0;
                const out = row[cx * CELL ..][0..32];
                inline for (0..4) |q| {
                    const m: @Vector(8, i32) = .{ 2 * q, 2 * q, 2 * q, 2 * q, 2 * q + 1, 2 * q + 1, 2 * q + 1, 2 * q + 1 };
                    const rv = @shuffle(f32, r0, undefined, m) + @shuffle(f32, rd, undefined, m) * ramp8;
                    const gv = @shuffle(f32, g0, undefined, m) + @shuffle(f32, gd, undefined, m) * ramp8;
                    const bv = @shuffle(f32, b0, undefined, m) + @shuffle(f32, bd, undefined, m) * ramp8;
                    const ri: U8v = @intFromFloat(rv);
                    const gi: U8v = @intFromFloat(gv);
                    const bi: U8v = @intFromFloat(bv);
                    out[q * 8 ..][0..8].* = alpha8 | ri | (gi << @splat(8)) | (bi << @splat(16));
                }
            }
            while (cx < full_cells) : (cx += 1) {
                const rv = @as(V4, @splat(tr[cx])) + @as(V4, @splat(tr[cx + 1] - tr[cx])) * ramp;
                const gv = @as(V4, @splat(tg[cx])) + @as(V4, @splat(tg[cx + 1] - tg[cx])) * ramp;
                const bv = @as(V4, @splat(tb[cx])) + @as(V4, @splat(tb[cx + 1] - tb[cx])) * ramp;
                const ri: U4 = @intFromFloat(rv);
                const gi: U4 = @intFromFloat(gv);
                const bi: U4 = @intFromFloat(bv);
                row[cx * CELL ..][0..4].* = alpha | ri | (gi << @splat(8)) | (bi << @splat(16));
            }
            // Tail pixels when w is not a multiple of CELL.
            var x: usize = full_cells * CELL;
            while (x < w) : (x += 1) {
                const tc = x / CELL;
                row[x] = sdk.packRGBA(@intFromFloat(tr[tc]), @intFromFloat(tg[tc]), @intFromFloat(tb[tc]));
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec) or
            math.isNan(self.field_sum) or math.isInf(self.field_sum);
    }
};

comptime {
    sdk.exportTheme(State);
}

// @argus-theme: custom_shader
// ============================================================================
// Fable_Field — ARGUS-BENCH Track B (Symplectic / PDE Field Dynamics)
//
// A live 2D incompressible Navier–Stokes solver (Stam "stable fluids"):
//   * semi-Lagrangian advection of velocity and two passive tracer dyes,
//   * vorticity confinement (Fedkiw) to keep the filaments crisp,
//   * pressure projection by warm-started Jacobi iteration (div-free field),
//   * four Lissajous "stirrers" that inject momentum and ink.
// The 384x240 field is advanced in step() and bilinearly magnified to the
// 1920x1200 Retina framebuffer in draw() with packed-integer lerps.
//
// Single allocation (alloc.create(State)), no allocations afterwards, no I/O,
// every write goes through `y * stride + x`, every pixel carries 0xFF alpha.
// ============================================================================
const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const GW: usize = 384; // field width in cells  (1920 / 5)
const GH: usize = 240; // field height in cells (1200 / 5)
const N: usize = GW * GH;
const GWf: f32 = @floatFromInt(GW);
const GHf: f32 = @floatFromInt(GH);

const JACOBI_ITERS: usize = 12; // even: result lands back in `p`
const VEL_DAMP: f32 = 0.9975; // per-step velocity dissipation
const DYE_DECAY: f32 = 0.998; // per-step tracer fade
const CONFINE: f32 = 2.5; // vorticity confinement strength
const PREWARM_STEPS: usize = 160; // fill the screen before the first frame

const Stirrer = struct {
    rx: f32,
    ry: f32,
    wx: f32,
    wy: f32,
    ph: f32,
    ph2: f32,
    gain: f32,
    ink: u8, // 0 = dye A (cyan), 1 = dye B (ember)
};

const STIRRERS = [_]Stirrer{
    .{ .rx = 150.0, .ry = 88.0, .wx = 0.37, .wy = 0.53, .ph = 0.0, .ph2 = 1.1, .gain = 1.5, .ink = 0 },
    .{ .rx = 120.0, .ry = 95.0, .wx = 0.61, .wy = 0.29, .ph = 2.3, .ph2 = 0.4, .gain = 1.4, .ink = 1 },
    .{ .rx = 165.0, .ry = 70.0, .wx = 0.23, .wy = 0.71, .ph = 4.1, .ph2 = 2.9, .gain = 1.6, .ink = 0 },
    .{ .rx = 100.0, .ry = 100.0, .wx = 0.47, .wy = 0.41, .ph = 1.4, .ph2 = 4.4, .gain = 1.3, .ink = 1 },
};

const VL: usize = 8;
const V8 = @Vector(VL, u32);

/// Eight-wide version of lerpPix for the vertical magnification in draw().
inline fn lerpVec(c0: V8, c1: V8, t: u32) V8 {
    const tv: V8 = @splat(t);
    const iv: V8 = @splat(256 - t);
    const m_rb: V8 = @splat(0x00FF00FF);
    const m_g: V8 = @splat(0x0000FF00);
    const alpha: V8 = @splat(0xFF000000);
    const sh: V8 = @splat(8);
    const rb = (((c0 & m_rb) * iv + (c1 & m_rb) * tv) >> sh) & m_rb;
    const g = (((c0 & m_g) * iv + (c1 & m_g) * tv) >> sh) & m_g;
    return alpha | rb | g;
}

/// Two-channel-pair packed lerp: R and B in one lane, G in the other. `t` in [0..256].
inline fn lerpPix(c0: u32, c1: u32, t: u32) u32 {
    const inv: u32 = 256 - t;
    const rb0 = c0 & 0x00FF00FF;
    const rb1 = c1 & 0x00FF00FF;
    const g0 = c0 & 0x0000FF00;
    const g1 = c1 & 0x0000FF00;
    const rb = ((rb0 * inv + rb1 * t) >> 8) & 0x00FF00FF;
    const g = ((g0 * inv + g1 * t) >> 8) & 0x0000FF00;
    return 0xFF000000 | rb | g;
}

inline fn clampf(v: f32, lo: f32, hi: f32) f32 {
    return @min(hi, @max(lo, v));
}

inline fn toU8(v: f32) u8 {
    const c = clampf(v, 0.0, 255.0);
    return @intFromFloat(c);
}

/// Bilinear sample of a GWxGH field at (px, py); caller guarantees px in [0, GW-1), py in [0, GH-1).
inline fn sample(field: *const [N]f32, px: f32, py: f32) f32 {
    const x0: usize = @intFromFloat(px);
    const y0: usize = @intFromFloat(py);
    const tx = px - @as(f32, @floatFromInt(x0));
    const ty = py - @as(f32, @floatFromInt(y0));
    const i = y0 * GW + x0;
    const a = field[i] + (field[i + 1] - field[i]) * tx;
    const b = field[i + GW] + (field[i + GW + 1] - field[i + GW]) * tx;
    return a + (b - a) * ty;
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time: f32,
    rng: u64,

    // --- field state (all inline so alloc.create(State) is the only allocation) ---
    u: [N]f32,
    v: [N]f32,
    u2: [N]f32,
    v2: [N]f32,
    p: [N]f32,
    p2: [N]f32,
    div: [N]f32,
    curl: [N]f32,
    dye_a: [N]f32,
    dye_b: [N]f32,
    dye_t: [N]f32,

    // --- colour pipeline ---
    bg_cell: [N]u32, // static vignette under the ink
    ramp_a: [256]u32,
    ramp_b: [256]u32,
    glow: [64]u32,
    col_row: [GW]u32,
    wide: [GH][MAX_W]u32, // field rows magnified horizontally to screen width

    // --- magnification LUTs for the actual framebuffer size ---
    x_idx: [MAX_W]u16,
    x_t: [MAX_W]u16,
    y_idx: [MAX_H]u16,
    y_t: [MAX_H]u16,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @max(@as(usize, 1), @min(w, MAX_W));
        self.h = @max(@as(usize, 1), @min(h, MAX_H));
        self.scale = scale;
        self.time = 0.0;
        self.rng = 0x9E3779B97F4A7C15;

        self.u = @splat(0.0);
        self.v = @splat(0.0);
        self.u2 = @splat(0.0);
        self.v2 = @splat(0.0);
        self.p = @splat(0.0);
        self.p2 = @splat(0.0);
        self.div = @splat(0.0);
        self.curl = @splat(0.0);
        self.dye_a = @splat(0.0);
        self.dye_b = @splat(0.0);
        self.dye_t = @splat(0.0);
        self.col_row = @splat(0);
        for (&self.wide) |*row| row.* = @splat(sdk.packRGBA(0, 0, 0));

        for (0..GH) |y| {
            const fy = (@as(f32, @floatFromInt(y)) / GHf) * 2.0 - 1.0;
            for (0..GW) |x| {
                const fx = (@as(f32, @floatFromInt(x)) / GWf) * 2.0 - 1.0;
                const d = clampf(1.0 - 0.55 * (fx * fx * 0.8 + fy * fy), 0.0, 1.0);
                self.bg_cell[y * GW + x] = sdk.packRGBA(toU8(3.0 + 7.0 * d), toU8(4.0 + 9.0 * d), toU8(9.0 + 20.0 * d));
            }
        }
        self.buildPalette();
        self.buildLuts();
        self.seedField();

        // Pre-warm so the first frame is already a developed flow, not an empty tank.
        for (0..PREWARM_STEPS) |_| self.simStep(0.008);
        self.paintField();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn nextRand(self: *State) f32 {
        // xorshift64*
        var x = self.rng;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.rng = x;
        const r: u32 = @truncate((x *% 0x2545F4914F6CDD1D) >> 40);
        return @as(f32, @floatFromInt(r)) * (1.0 / 16777216.0);
    }

    fn buildPalette(self: *State) void {
        // Dye A: abyss -> deep teal -> cyan -> pale aqua.   Dye B: abyss -> wine -> ember -> gold.
        const keys_a = [_][3]f32{ .{ 0, 0, 0 }, .{ 5, 34, 62 }, .{ 16, 112, 150 }, .{ 80, 196, 220 }, .{ 200, 245, 255 } };
        const keys_b = [_][3]f32{ .{ 0, 0, 0 }, .{ 84, 14, 32 }, .{ 212, 72, 24 }, .{ 255, 156, 48 }, .{ 255, 232, 170 } };
        for (0..256) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 255.0;
            const s = math.pow(f32, t, 0.75) * 4.0; // lift the faint tails: thin filaments stay visible
            const k: usize = @min(@as(usize, 3), @as(usize, @intFromFloat(s)));
            const f = s - @as(f32, @floatFromInt(k));
            const a0 = keys_a[k];
            const a1 = keys_a[k + 1];
            const b0 = keys_b[k];
            const b1 = keys_b[k + 1];
            self.ramp_a[i] = sdk.packRGBA(toU8(a0[0] + (a1[0] - a0[0]) * f), toU8(a0[1] + (a1[1] - a0[1]) * f), toU8(a0[2] + (a1[2] - a0[2]) * f));
            self.ramp_b[i] = sdk.packRGBA(toU8(b0[0] + (b1[0] - b0[0]) * f), toU8(b0[1] + (b1[1] - b0[1]) * f), toU8(b0[2] + (b1[2] - b0[2]) * f));
        }
        for (0..64) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 63.0;
            const g = t * t;
            self.glow[i] = sdk.packRGBA(toU8(70.0 * g), toU8(90.0 * g), toU8(110.0 * g));
        }
    }

    fn buildLuts(self: *State) void {
        const wd: f64 = @floatFromInt(@max(@as(usize, 1), self.w - 1));
        const hd: f64 = @floatFromInt(@max(@as(usize, 1), self.h - 1));
        for (0..self.w) |x| {
            const fx = @as(f64, @floatFromInt(x)) * @as(f64, @floatFromInt(GW - 1)) / wd;
            var xi: usize = @intFromFloat(@floor(fx));
            var t: u32 = @intFromFloat(@floor((fx - @floor(fx)) * 256.0));
            if (xi >= GW - 1) {
                xi = GW - 2;
                t = 256;
            }
            self.x_idx[x] = @intCast(xi);
            self.x_t[x] = @intCast(t);
        }
        for (0..self.h) |y| {
            const fy = @as(f64, @floatFromInt(y)) * @as(f64, @floatFromInt(GH - 1)) / hd;
            var yi: usize = @intFromFloat(@floor(fy));
            var t: u32 = @intFromFloat(@floor((fy - @floor(fy)) * 256.0));
            if (yi >= GH - 1) {
                yi = GH - 2;
                t = 256;
            }
            self.y_idx[y] = @intCast(yi);
            self.y_t[y] = @intCast(t);
        }
    }

    /// A handful of Gaussian vortices and ink blobs so the field is never trivially still.
    fn seedField(self: *State) void {
        for (0..14) |k| {
            const cx = 20.0 + (GWf - 40.0) * self.nextRand();
            const cy = 20.0 + (GHf - 40.0) * self.nextRand();
            const r = 14.0 + 22.0 * self.nextRand();
            const sgn: f32 = if ((k & 1) == 0) 1.0 else -1.0;
            const str = sgn * (30.0 + 40.0 * self.nextRand());
            const ink_a = self.nextRand() > 0.5;
            for (1..GH - 1) |y| {
                const fy: f32 = @floatFromInt(y);
                for (1..GW - 1) |x| {
                    const fx: f32 = @floatFromInt(x);
                    const dx = fx - cx;
                    const dy = fy - cy;
                    const d2 = (dx * dx + dy * dy) / (r * r);
                    if (d2 > 9.0) continue;
                    const g = @exp(-d2);
                    const i = y * GW + x;
                    self.u[i] += -dy * str * g / r;
                    self.v[i] += dx * str * g / r;
                    if (ink_a) {
                        self.dye_a[i] = @min(1.0, self.dye_a[i] + 0.8 * g);
                    } else {
                        self.dye_b[i] = @min(1.0, self.dye_b[i] + 0.8 * g);
                    }
                }
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        const dts: f32 = clampf(@as(f32, @floatCast(dt)), 0.0, 0.05);
        self.simStep(dts);
        self.paintField();
    }

    fn simStep(self: *State, dt: f32) void {
        self.time += dt;
        self.stir(dt);
        self.confine(dt);
        self.advectVelocity(dt);
        self.project();
        self.advectDye(dt);
    }

    /// Lissajous stirrers blend the fluid toward their own velocity and drop ink.
    fn stir(self: *State, dt: f32) void {
        const t = self.time;
        const R: f32 = 11.0;
        for (STIRRERS) |s| {
            const ax = s.wx * t + s.ph;
            const ay = s.wy * t + s.ph2;
            const cx = GWf * 0.5 + s.rx * @cos(ax);
            const cy = GHf * 0.5 + s.ry * @sin(ay);
            const svx = -s.rx * s.wx * @sin(ax) * s.gain;
            const svy = s.ry * s.wy * @cos(ay) * s.gain;
            const x0: usize = @intFromFloat(clampf(@floor(cx - R), 1.0, GWf - 2.0));
            const x1: usize = @intFromFloat(clampf(@ceil(cx + R), 1.0, GWf - 2.0));
            const y0: usize = @intFromFloat(clampf(@floor(cy - R), 1.0, GHf - 2.0));
            const y1: usize = @intFromFloat(clampf(@ceil(cy + R), 1.0, GHf - 2.0));
            var y = y0;
            while (y <= y1) : (y += 1) {
                const fy: f32 = @floatFromInt(y);
                var x = x0;
                while (x <= x1) : (x += 1) {
                    const fx: f32 = @floatFromInt(x);
                    const dx = fx - cx;
                    const dy = fy - cy;
                    const d2 = (dx * dx + dy * dy) / (R * R);
                    if (d2 >= 1.0) continue;
                    const fall = (1.0 - d2) * (1.0 - d2);
                    const k = fall * 7.0 * dt;
                    const i = y * GW + x;
                    self.u[i] += (svx - self.u[i]) * k;
                    self.v[i] += (svy - self.v[i]) * k;
                    const ink = fall * 3.0 * dt;
                    if (s.ink == 0) {
                        self.dye_a[i] = @min(1.0, self.dye_a[i] + ink);
                    } else {
                        self.dye_b[i] = @min(1.0, self.dye_b[i] + ink);
                    }
                }
            }
        }
    }

    /// Vorticity confinement: F = eps * (N x omega), N = grad|omega| / |grad|omega||.
    /// The normal is taken from a 3x3-smoothed |omega| (scratch: `div`, rewritten by project()),
    /// otherwise the grid-scale noise of |omega| prints streaks into the tracer.
    fn confine(self: *State, dt: f32) void {
        for (1..GH - 1) |y| {
            const row = y * GW;
            for (1..GW - 1) |x| {
                const i = row + x;
                self.curl[i] = 0.5 * ((self.v[i + 1] - self.v[i - 1]) - (self.u[i + GW] - self.u[i - GW]));
            }
        }
        for (1..GH - 1) |y| {
            const row = y * GW;
            for (1..GW - 1) |x| {
                const i = row + x;
                const c = &self.curl;
                self.div[i] = (@abs(c[i - GW - 1]) + 2.0 * @abs(c[i - GW]) + @abs(c[i - GW + 1]) +
                    2.0 * @abs(c[i - 1]) + 4.0 * @abs(c[i]) + 2.0 * @abs(c[i + 1]) +
                    @abs(c[i + GW - 1]) + 2.0 * @abs(c[i + GW]) + @abs(c[i + GW + 1])) * (1.0 / 16.0);
            }
        }
        const eps = CONFINE * dt;
        for (2..GH - 2) |y| {
            const row = y * GW;
            for (2..GW - 2) |x| {
                const i = row + x;
                const gx = self.div[i + 1] - self.div[i - 1];
                const gy = self.div[i + GW] - self.div[i - GW];
                const len = @sqrt(@max(0.0, gx * gx + gy * gy)) + 1.0e-3;
                const c = self.curl[i] * eps / len;
                self.u[i] += gy * c;
                self.v[i] -= gx * c;
            }
        }
    }

    fn advectVelocity(self: *State, dt: f32) void {
        const xmax = GWf - 1.001;
        const ymax = GHf - 1.001;
        for (1..GH - 1) |y| {
            const fy: f32 = @floatFromInt(y);
            const row = y * GW;
            for (1..GW - 1) |x| {
                const fx: f32 = @floatFromInt(x);
                const i = row + x;
                const px = clampf(fx - self.u[i] * dt, 0.0, xmax);
                const py = clampf(fy - self.v[i] * dt, 0.0, ymax);
                self.u2[i] = sample(&self.u, px, py) * VEL_DAMP;
                self.v2[i] = sample(&self.v, px, py) * VEL_DAMP;
            }
        }
    }

    /// Helmholtz–Hodge projection: solve lap(p) = div(u2), then u = u2 - grad(p).
    fn project(self: *State) void {
        for (1..GH - 1) |y| {
            const row = y * GW;
            for (1..GW - 1) |x| {
                const i = row + x;
                self.div[i] = 0.5 * ((self.u2[i + 1] - self.u2[i - 1]) + (self.v2[i + GW] - self.v2[i - GW]));
            }
        }
        // Warm-started Jacobi, ping-pong p <-> p2 (even iteration count ends in p).
        var it: usize = 0;
        while (it < JACOBI_ITERS) : (it += 2) {
            jacobi(&self.p, &self.p2, &self.div);
            jacobi(&self.p2, &self.p, &self.div);
        }
        for (1..GH - 1) |y| {
            const row = y * GW;
            for (1..GW - 1) |x| {
                const i = row + x;
                self.u[i] = self.u2[i] - 0.5 * (self.p[i + 1] - self.p[i - 1]);
                self.v[i] = self.v2[i] - 0.5 * (self.p[i + GW] - self.p[i - GW]);
            }
        }
    }

    fn jacobi(src: *const [N]f32, dst: *[N]f32, div: *const [N]f32) void {
        for (1..GH - 1) |y| {
            const row = y * GW;
            for (1..GW - 1) |x| {
                const i = row + x;
                dst[i] = 0.25 * (src[i - 1] + src[i + 1] + src[i - GW] + src[i + GW] - div[i]);
            }
        }
        // Neumann walls: dp/dn = 0.
        for (1..GH - 1) |y| {
            dst[y * GW] = dst[y * GW + 1];
            dst[y * GW + GW - 1] = dst[y * GW + GW - 2];
        }
        for (0..GW) |x| {
            dst[x] = dst[GW + x];
            dst[(GH - 1) * GW + x] = dst[(GH - 2) * GW + x];
        }
    }

    fn advectDye(self: *State, dt: f32) void {
        self.advectScalar(&self.dye_a, dt);
        self.advectScalar(&self.dye_b, dt);
    }

    fn advectScalar(self: *State, field: *[N]f32, dt: f32) void {
        const xmax = GWf - 1.001;
        const ymax = GHf - 1.001;
        for (1..GH - 1) |y| {
            const fy: f32 = @floatFromInt(y);
            const row = y * GW;
            for (1..GW - 1) |x| {
                const fx: f32 = @floatFromInt(x);
                const i = row + x;
                const px = clampf(fx - self.u[i] * dt, 0.0, xmax);
                const py = clampf(fy - self.v[i] * dt, 0.0, ymax);
                self.dye_t[i] = sample(field, px, py) * DYE_DECAY;
            }
        }
        @memcpy(field[GW .. N - GW], self.dye_t[GW .. N - GW]);
    }

    /// Colour every field cell and magnify each row horizontally to the screen width.
    fn paintField(self: *State) void {
        const w = self.w;
        for (0..GH) |gy| {
            const row = gy * GW;
            for (0..GW) |gx| {
                const i = row + gx;
                const a = clampf(self.dye_a[i], 0.0, 1.0);
                const b = clampf(self.dye_b[i], 0.0, 1.0);
                const c = clampf(@abs(self.curl[i]) * 0.3, 0.0, 63.0);
                const ia: usize = @intFromFloat(a * 255.0);
                const ib: usize = @intFromFloat(b * 255.0);
                const ic: usize = @intFromFloat(c);
                const ink = sdk.addRGB(self.ramp_a[ia], self.ramp_b[ib]);
                self.col_row[gx] = sdk.addRGB(sdk.addRGB(self.bg_cell[i], ink), self.glow[ic]);
            }
            const dst = self.wide[gy][0..w];
            for (dst, self.x_idx[0..w], self.x_t[0..w]) |*d, xi, xt| {
                const c0 = self.col_row[xi];
                const c1 = self.col_row[@as(usize, xi) + 1];
                d.* = lerpPix(c0, c1, xt);
            }
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        if (stride < w) return;
        const h: usize = @min(self.h, buf.len / stride);
        for (0..h) |y| {
            const yi: usize = self.y_idx[y];
            const t: u32 = self.y_t[y];
            const dst = buf[y * stride .. y * stride + w];
            const r0 = self.wide[yi][0..w];
            const r1 = self.wide[yi + 1][0..w];
            if (t == 0) {
                @memcpy(dst, r0);
            } else if (t >= 256) {
                @memcpy(dst, r1);
            } else {
                var x: usize = 0;
                while (x + VL <= w) : (x += VL) {
                    const c0: V8 = r0[x..][0..VL].*;
                    const c1: V8 = r1[x..][0..VL].*;
                    dst[x..][0..VL].* = lerpVec(c0, c1, t);
                }
                while (x < w) : (x += 1) dst[x] = lerpPix(r0[x], r1[x], t);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (!math.isFinite(self.time)) return true;
        var k: usize = 0;
        while (k < N) : (k += 1543) {
            if (!math.isFinite(self.u[k]) or !math.isFinite(self.v[k]) or !math.isFinite(self.p[k]) or !math.isFinite(self.dye_a[k]) or !math.isFinite(self.dye_b[k])) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

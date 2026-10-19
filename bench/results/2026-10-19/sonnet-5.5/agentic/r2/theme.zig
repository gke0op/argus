//! Sonnet_Field -- a live 2D Gross-Pitaevskii superfluid (Track B).
//!
//!   i dpsi/dt = [ -1/2 laplacian + V(r,t) + |psi|^2 - 1 ] psi        (hbar = m = g = mu = 1)
//!
//! A 256x128 periodic complex field psi is evolved with a Strang-style split-step Fourier
//! method (potential/nonlinear phase kick in real space, free-particle propagator in k-space,
//! 2/3 de-aliasing, complex radix-2 FFTs with the butterflies vectorised across whole rows).
//! The domain is Lx x Ly = 256 dx x 128 dy with dy = 1.25 dx, so it maps 1:1 onto the 1920x1200
//! screen and the physics stays isotropic. Healing length xi = 0.71 -> 2.2 cells.
//!
//! The condensate starts as a gas of 14 vortex-antivortex pairs (phase imprinted from products
//! of (z - z_p) conj(z - z_n) over nine periodic images, Pade core profile) and is stirred by
//! two Gaussian laser spots on Lissajous paths that shed fresh vortex pairs. A weak
//! phenomenological damping (dissipative GP, gamma = 0.004) with global renormalisation lets
//! sound radiate away so the vortices stay legible.
//!
//! Rendering: psi is bilinearly interpolated to the screen (so a vortex core keeps its true
//! phase winding) and shaded with a cosine phase palette x density: colour = flow phase,
//! brightness = superfluid density, pinwheels = quantised vortices.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const NX: usize = 256;
const NY: usize = 128;
const N: usize = NX * NY;

const DX: f32 = 0.32;
const DY: f32 = 0.40;
const LX: f32 = DX * @as(f32, NX);
const LY: f32 = DY * @as(f32, NY);

const DT_SIM: f32 = 0.0625; // split-step time step (sim units)
const RATE: f64 = 12.5; // sim units per real second
const MAX_SUBSTEPS: u32 = 8;
const GAMMA: f32 = 0.03; // run-time dissipation
const GAMMA_WARM: f32 = 0.10; // relaxation of the imprinted state
const WARM_STEPS: usize = 40;

const V0: f32 = 4.0; // laser-spot height (mu = 1)
const SIGMA: f32 = 0.85; // laser-spot width
const N_PAIRS: usize = 14;

const V8 = @Vector(8, f32);

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    sim_t: f32,
    acc: f64,
    norm_scale: f32,
    norm_sum: f32,
    gamma: f32,
    spots_on: bool,

    re: [N]f32, // layout A: [y][x]
    im: [N]f32,
    tre: [N]f32, // layout B: [x][y]
    tim: [N]f32,
    kre: [N]f32, // propagator in layout B, includes 1/N and the 2/3 mask
    kim: [N]f32,

    twx_c: [NX / 2]f32,
    twx_s: [NX / 2]f32,
    twy_c: [NY / 2]f32,
    twy_s: [NY / 2]f32,

    // display tables
    xi: [MAX_W]u16,
    xf: [MAX_W]f32,
    yi: [MAX_H]u16,
    yf: [MAX_H]f32,
    vig_x: [MAX_W]f32,
    vig_y: [MAX_H]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(@max(w, 1), MAX_W);
        self.h = @min(@max(h, 1), MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.sim_t = 0.0;
        self.acc = 0.0;
        self.norm_scale = 1.0;
        self.norm_sum = @as(f32, N);
        self.gamma = GAMMA_WARM;
        self.spots_on = false;

        // twiddles
        for (0..NX / 2) |k| {
            const a = -2.0 * math.pi * @as(f64, @floatFromInt(k)) / @as(f64, NX);
            self.twx_c[k] = @floatCast(@cos(a));
            self.twx_s[k] = @floatCast(@sin(a));
        }
        for (0..NY / 2) |k| {
            const a = -2.0 * math.pi * @as(f64, @floatFromInt(k)) / @as(f64, NY);
            self.twy_c[k] = @floatCast(@cos(a));
            self.twy_s[k] = @floatCast(@sin(a));
        }

        self.buildPropagator();
        self.initVortexGas();
        // short strongly damped relaxation: radiates away the imprint's sound, keeps the vortices
        for (0..WARM_STEPS) |_| self.substep();
        self.gamma = GAMMA;
        self.buildPropagator();
        self.spots_on = true;
        self.sim_t = 0.0;

        // display tables (screen pixel -> periodic grid coordinate)
        const wf: f32 = @floatFromInt(self.w);
        const hf: f32 = @floatFromInt(self.h);
        for (0..self.w) |x| {
            const g = (@as(f32, @floatFromInt(x)) + 0.5) * @as(f32, NX) / wf - 0.5;
            const fl = @floor(g);
            const i: isize = @intFromFloat(fl);
            self.xi[x] = @intCast(@mod(i, @as(isize, NX)));
            self.xf[x] = g - fl;
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / wf * 2.0 - 1.0;
            self.vig_x[x] = 1.0 - 0.30 * u * u - 0.12 * u * u * u * u;
        }
        for (0..self.h) |y| {
            const g = (@as(f32, @floatFromInt(y)) + 0.5) * @as(f32, NY) / hf - 0.5;
            const fl = @floor(g);
            const i: isize = @intFromFloat(fl);
            self.yi[y] = @intCast(@mod(i, @as(isize, NY)));
            self.yf[y] = g - fl;
            const u = (@as(f32, @floatFromInt(y)) + 0.5) / hf * 2.0 - 1.0;
            self.vig_y[y] = 1.0 - 0.30 * u * u - 0.12 * u * u * u * u;
        }
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    /// Free-particle propagator exp(-(i + gamma) dt k^2 / 2), layout B index = kxi * NY + kyi,
    /// with the 2/3 de-aliasing mask and the 1/N of the inverse FFT folded in.
    fn buildPropagator(self: *State) void {
        const inv_n: f64 = 1.0 / @as(f64, N);
        const gam: f64 = self.gamma;
        for (0..NX) |ix| {
            const mx: isize = if (ix < NX / 2) @intCast(ix) else @as(isize, @intCast(ix)) - @as(isize, NX);
            const kx = 2.0 * math.pi * @as(f64, @floatFromInt(mx)) / @as(f64, LX);
            for (0..NY) |iy| {
                const my: isize = if (iy < NY / 2) @intCast(iy) else @as(isize, @intCast(iy)) - @as(isize, NY);
                const ky = 2.0 * math.pi * @as(f64, @floatFromInt(my)) / @as(f64, LY);
                const keep = @abs(mx) <= NX / 3 and @abs(my) <= NY / 3;
                const e = 0.5 * (kx * kx + ky * ky) * @as(f64, DT_SIM);
                const mag = @exp(-gam * e) * inv_n;
                const idx = ix * NY + iy;
                self.kre[idx] = if (keep) @floatCast(@cos(-e) * mag) else 0.0;
                self.kim[idx] = if (keep) @floatCast(@sin(-e) * mag) else 0.0;
            }
        }
    }

    // ------------------------------------------------------------------ initial state
    fn initVortexGas(self: *State) void {
        var pos: [N_PAIRS][4]f32 = undefined; // x1,y1 (+), x2,y2 (-)
        var rng: u32 = 0x2545F491;
        for (0..N_PAIRS) |p| {
            const cx = rnd(&rng) * LX;
            const cy = rnd(&rng) * LY;
            const d = 4.0 + rnd(&rng) * 3.4;
            const a = rnd(&rng) * 2.0 * math.pi;
            const ox = 0.5 * d * @cos(a);
            const oy = 0.5 * d * @sin(a);
            pos[p] = .{ cx + ox, cy + oy, cx - ox, cy - oy };
        }
        var sum: f32 = 0.0;
        for (0..NY) |y| {
            const py = (@as(f32, @floatFromInt(y)) + 0.5) * DY;
            for (0..NX) |x| {
                const px = (@as(f32, @floatFromInt(x)) + 0.5) * DX;
                var cr: f32 = 1.0;
                var ci: f32 = 0.0;
                var rho: f32 = 1.0;
                for (pos) |q| {
                    // density: nearest image of each core
                    rho *= core(px, py, q[0], q[1]) * core(px, py, q[2], q[3]);
                    // phase: pair phase summed over 3x3 periodic images
                    var iy: i32 = -1;
                    while (iy <= 1) : (iy += 1) {
                        var ix: i32 = -1;
                        while (ix <= 1) : (ix += 1) {
                            const sx = @as(f32, @floatFromInt(ix)) * LX;
                            const sy = @as(f32, @floatFromInt(iy)) * LY;
                            const ar = px - (q[0] + sx);
                            const ai = py - (q[1] + sy);
                            const br = px - (q[2] + sx);
                            const bi = py - (q[3] + sy);
                            // a * conj(b)
                            const zr = ar * br + ai * bi;
                            const zi = ai * br - ar * bi;
                            const m2 = zr * zr + zi * zi + 1e-12;
                            const inv = 1.0 / @sqrt(m2);
                            const nr = zr * inv;
                            const ni = zi * inv;
                            const tr = cr * nr - ci * ni;
                            ci = cr * ni + ci * nr;
                            cr = tr;
                        }
                    }
                    const cm = 1.0 / @sqrt(cr * cr + ci * ci + 1e-20);
                    cr *= cm;
                    ci *= cm;
                }
                const amp = @sqrt(rho);
                const idx = y * NX + x;
                self.re[idx] = amp * cr;
                self.im[idx] = amp * ci;
                sum += amp * amp;
            }
        }
        self.norm_sum = sum;
        self.norm_scale = @sqrt(@as(f32, N) / @max(sum, 1.0));
    }

    // ------------------------------------------------------------------ time stepping
    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        self.acc += dt * RATE;
        var n: u32 = 0;
        const dts: f64 = DT_SIM;
        while (self.acc >= dts and n < MAX_SUBSTEPS) : (n += 1) {
            self.substep();
            self.acc -= dts;
        }
        if (self.acc > dts) self.acc = 0.0;
    }

    fn substep(self: *State) void {
        self.potentialKick();
        // forward 2D FFT: along y (rows of A), transpose, along x
        fftRows(NY, NX, &self.re, &self.im, &self.twy_c, &self.twy_s, false);
        transpose(NY, NX, &self.re, &self.tre);
        transpose(NY, NX, &self.im, &self.tim);
        fftRows(NX, NY, &self.tre, &self.tim, &self.twx_c, &self.twx_s, false);
        // free propagation (includes 1/N and mask)
        {
            var i: usize = 0;
            while (i < N) : (i += 8) {
                const ar: V8 = self.tre[i..][0..8].*;
                const ai: V8 = self.tim[i..][0..8].*;
                const kr: V8 = self.kre[i..][0..8].*;
                const ki: V8 = self.kim[i..][0..8].*;
                self.tre[i..][0..8].* = ar * kr - ai * ki;
                self.tim[i..][0..8].* = ar * ki + ai * kr;
            }
        }
        fftRows(NX, NY, &self.tre, &self.tim, &self.twx_c, &self.twx_s, true);
        transpose(NX, NY, &self.tre, &self.re);
        transpose(NX, NY, &self.tim, &self.im);
        fftRows(NY, NX, &self.re, &self.im, &self.twy_c, &self.twy_s, true);
        self.sim_t += DT_SIM;
    }

    /// Real-space step: nonlinear + chemical-potential phase, weak damping, global
    /// renormalisation (using the norm measured at the end of the previous kick), then the
    /// moving laser spots.
    fn potentialKick(self: *State) void {
        const ns = self.norm_scale;
        const gdt: f32 = self.gamma * DT_SIM;
        var sum: V8 = @splat(0.0);
        const one: V8 = @splat(1.0);
        const dtv: V8 = @splat(DT_SIM);
        const nsv: V8 = @splat(ns);
        const gv: V8 = @splat(gdt);
        var i: usize = 0;
        while (i < N) : (i += 8) {
            var r: V8 = self.re[i..][0..8].*;
            var m: V8 = self.im[i..][0..8].*;
            r *= nsv;
            m *= nsv;
            const u = r * r + m * m - one; // g|psi|^2 - mu
            const th = u * dtv; // |th| <= ~0.3
            const t2 = th * th;
            // cos / sin Taylor (|th| < 0.5 here: error < 1e-9)
            const c = one - t2 * (@as(V8, @splat(0.5)) - t2 * (@as(V8, @splat(1.0 / 24.0)) - t2 * @as(V8, @splat(1.0 / 720.0))));
            const s = th * (one - t2 * (@as(V8, @splat(1.0 / 6.0)) - t2 * (@as(V8, @splat(1.0 / 120.0)) - t2 * @as(V8, @splat(1.0 / 5040.0)))));
            // psi * exp(-i th) = (r + i m)(c - i s)
            var nr = r * c + m * s;
            var ni = m * c - r * s;
            const damp = @max(one - gv * u, @as(V8, @splat(0.9)));
            nr *= damp;
            ni *= damp;
            self.re[i..][0..8].* = nr;
            self.im[i..][0..8].* = ni;
            sum += nr * nr + ni * ni;
        }
        self.norm_sum = @reduce(.Add, sum);
        // the spots act after this sum, so mass removed by them is restored by the renormalisation
        self.norm_scale = @sqrt(@as(f32, N) / @max(self.norm_sum, 1.0));
        if (self.spots_on) self.laserSpots();
    }

    fn spotPos(t: f32, k: usize) [2]f32 {
        const kf: f32 = @floatFromInt(k);
        const x = LX * (0.5 + 0.36 * @sin((0.021 + 0.004 * kf) * t + 0.3 + 2.1 * kf));
        const y = LY * (0.5 + 0.36 * @sin((0.033 - 0.006 * kf) * t + 1.1 + 1.7 * kf));
        return .{ x, y };
    }

    fn laserSpots(self: *State) void {
        const rx: isize = @intFromFloat(@ceil(4.0 * SIGMA / DX));
        const ry: isize = @intFromFloat(@ceil(4.0 * SIGMA / DY));
        for (0..2) |k| {
            const p = spotPos(self.sim_t, k);
            const gx: isize = @intFromFloat(@floor(p[0] / DX));
            const gy: isize = @intFromFloat(@floor(p[1] / DY));
            var oy: isize = -ry;
            while (oy <= ry) : (oy += 1) {
                const yy: usize = @intCast(@mod(gy + oy, @as(isize, NY)));
                const dyy = (@as(f32, @floatFromInt(gy + oy)) + 0.5) * DY - p[1];
                var ox: isize = -rx;
                while (ox <= rx) : (ox += 1) {
                    const xx: usize = @intCast(@mod(gx + ox, @as(isize, NX)));
                    const dxx = (@as(f32, @floatFromInt(gx + ox)) + 0.5) * DX - p[0];
                    const q = (dxx * dxx + dyy * dyy) / (2.0 * SIGMA * SIGMA);
                    const th = V0 * DT_SIM * @exp(-q);
                    const t2 = th * th;
                    const c = 1.0 - t2 * (0.5 - t2 * (1.0 / 24.0 - t2 * (1.0 / 720.0)));
                    const s = th * (1.0 - t2 * (1.0 / 6.0 - t2 * (1.0 / 120.0 - t2 * (1.0 / 5040.0))));
                    const idx = yy * NX + xx;
                    const r = self.re[idx];
                    const m = self.im[idx];
                    self.re[idx] = r * c + m * s;
                    self.im[idx] = m * c - r * s;
                }
            }
        }
    }

    // ------------------------------------------------------------------ drawing
    /// Shade on a half-resolution sample grid (every 2nd pixel and row; the field is smooth on
    /// that scale: cores are ~30 px wide) and replicate 2x2. Shading is 8 samples at a time.
    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const hw = (w + 1) / 2; // samples per row
        const pad = (hw + 7) / 8 * 8;
        var vr: [NX + 1]f32 = undefined;
        var vi: [NX + 1]f32 = undefined;
        var sr: [MAX_W / 2 + 8]f32 = undefined;
        var si: [MAX_W / 2 + 8]f32 = undefined;
        var vx: [MAX_W / 2 + 8]f32 = undefined;
        var row: [MAX_W / 2 + 8]u32 = undefined;
        @memset(sr[hw..pad], 0.0);
        @memset(si[hw..pad], 0.0);
        @memset(vx[hw..pad], 0.0);
        for (0..hw) |k| vx[k] = self.vig_x[@min(2 * k, w - 1)];

        var y: usize = 0;
        while (y < self.h) : (y += 2) {
            const r0 = @as(usize, self.yi[y]) * NX;
            const r1 = ((@as(usize, self.yi[y]) + 1) % NY) * NX;
            const f = self.yf[y];
            for (0..NX) |x| {
                vr[x] = self.re[r0 + x] + (self.re[r1 + x] - self.re[r0 + x]) * f;
                vi[x] = self.im[r0 + x] + (self.im[r1 + x] - self.im[r0 + x]) * f;
            }
            vr[NX] = vr[0];
            vi[NX] = vi[0];
            for (0..hw) |k| {
                const x = 2 * k;
                const a: usize = self.xi[x];
                const t = self.xf[x];
                sr[k] = vr[a] + (vr[a + 1] - vr[a]) * t;
                si[k] = vi[a] + (vi[a + 1] - vi[a]) * t;
            }
            const vy: V8 = @splat(self.vig_y[y] * 1.25);
            var k: usize = 0;
            while (k < pad) : (k += 8) {
                const r: V8 = sr[k..][0..8].*;
                const m: V8 = si[k..][0..8].*;
                const vg: V8 = vx[k..][0..8].* * vy;
                row[k..][0..8].* = shade(r, m, vg);
            }
            const dst0 = buf[y * stride .. y * stride + w];
            for (dst0, 0..) |*px, x| px.* = row[x >> 1];
            if (y + 1 < self.h) {
                @memcpy(buf[(y + 1) * stride .. (y + 1) * stride + w], dst0);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.norm_sum) or math.isInf(self.norm_sum) or math.isNan(self.time_sec) or math.isInf(self.time_sec) or
            math.isNan(self.re[N / 2 + 77]) or math.isNan(self.im[N / 3 + 5]);
    }
};

const U8 = @Vector(8, u32);

/// Colour of 8 samples: phase palette (cosine of the field's phase, weighted by |psi|) times a
/// density mask, a warm rim light where the density crosses ~1/2 (vortex cores, laser holes)
/// and a mild brightness response to sound-wave compression.
inline fn shade(r: V8, m: V8, vg: V8) U8 {
    const d = r * r + m * m;
    const one: V8 = @splat(1.0);
    const zero: V8 = @splat(0.0);
    const tt = @min(d * @as(V8, @splat(1.5)), one);
    const g = tt * tt * (@as(V8, @splat(3.0)) - @as(V8, @splat(2.0)) * tt);
    const lum = g * (@as(V8, @splat(0.92)) + @as(V8, @splat(1.1)) * (d - one)) * vg;
    const rim0 = @max(@as(V8, @splat(4.0)) * d * (one - d), zero);
    const rim = rim0 * rim0 * rim0 * vg * @as(V8, @splat(0.55));
    const cr = (@as(V8, @splat(PAL_B[0])) + r * @as(V8, @splat(PAL_C[0])) + m * @as(V8, @splat(PAL_S[0]))) * lum + rim * @as(V8, @splat(1.00));
    const cg = (@as(V8, @splat(PAL_B[1])) + r * @as(V8, @splat(PAL_C[1])) + m * @as(V8, @splat(PAL_S[1]))) * lum + rim * @as(V8, @splat(0.80));
    const cb = (@as(V8, @splat(PAL_B[2])) + r * @as(V8, @splat(PAL_C[2])) + m * @as(V8, @splat(PAL_S[2]))) * lum + rim * @as(V8, @splat(0.55));
    const k255: V8 = @splat(255.0);
    const half: V8 = @splat(0.5);
    const ir: U8 = @intFromFloat(@min(@max(cr, zero), one) * k255 + half);
    const ig: U8 = @intFromFloat(@min(@max(cg, zero), one) * k255 + half);
    const ib: U8 = @intFromFloat(@min(@max(cb, zero), one) * k255 + half);
    return ir | (ig << @as(@Vector(8, u5), @splat(8))) | (ib << @as(@Vector(8, u5), @splat(16))) | @as(U8, @splat(0xFF000000));
}

// cosine phase palette: channel_k = B_k + A_k cos(phi - phi_k); folded into (re, im) weights
const PAL_BASE = [3]f32{ 0.14, 0.20, 0.30 };
const PAL_AMP = [3]f32{ 0.28, 0.22, 0.26 };
const PAL_PH = [3]f32{ 0.30, 2.50, 4.40 };
const PAL_B = PAL_BASE;
const PAL_C = [3]f32{ PAL_AMP[0] * @cos(PAL_PH[0]), PAL_AMP[1] * @cos(PAL_PH[1]), PAL_AMP[2] * @cos(PAL_PH[2]) };
const PAL_S = [3]f32{ PAL_AMP[0] * @sin(PAL_PH[0]), PAL_AMP[1] * @sin(PAL_PH[1]), PAL_AMP[2] * @sin(PAL_PH[2]) };

inline fn q8(v: f32) u8 {
    const c = @min(@max(v, 0.0), 1.0);
    return @intFromFloat(c * 255.0 + 0.5);
}

fn rnd(s: *u32) f32 {
    s.* = s.* *% 1664525 +% 1013904223;
    return @as(f32, @floatFromInt(s.* >> 8)) / 16777216.0;
}

/// Pade vortex-core profile (Berloff), rho(r) = |psi|^2; nearest periodic image.
fn core(px: f32, py: f32, cx: f32, cy: f32) f32 {
    var dx = px - cx;
    var dy = py - cy;
    dx -= LX * @round(dx / LX);
    dy -= LY * @round(dy / LY);
    const r2 = 2.0 * (dx * dx + dy * dy); // Berloff units: r_B^2 = 2 r^2
    return r2 * (0.3437 + 0.0286 * r2) / (1.0 + 0.3333 * r2 + 0.0286 * r2 * r2);
}

// ---------------------------------------------------------------------- FFT / transpose

/// In-place complex FFT along the ROW index of an R x L row-major array (L contiguous):
/// each butterfly combines two whole rows, so the inner loop is a long vector loop.
fn fftRows(comptime R: usize, comptime L: usize, re: *[R * L]f32, im: *[R * L]f32, twc: *const [R / 2]f32, tws: *const [R / 2]f32, comptime inverse: bool) void {
    const bits = comptime math.log2_int(usize, R);
    const Bits = @Int(.unsigned, bits);
    // bit-reversal permutation of rows
    for (0..R) |a| {
        const b: usize = @bitReverse(@as(Bits, @intCast(a)));
        if (b > a) {
            for (0..L) |j| {
                const tr = re[a * L + j];
                re[a * L + j] = re[b * L + j];
                re[b * L + j] = tr;
                const ti = im[a * L + j];
                im[a * L + j] = im[b * L + j];
                im[b * L + j] = ti;
            }
        }
    }
    var len: usize = 2;
    while (len <= R) : (len *= 2) {
        const half = len / 2;
        const stp = R / len;
        var start: usize = 0;
        while (start < R) : (start += len) {
            for (0..half) |k| {
                const wr: V8 = @splat(twc[k * stp]);
                const wi: V8 = @splat(if (inverse) -tws[k * stp] else tws[k * stp]);
                const ra = (start + k) * L;
                const rb = (start + k + half) * L;
                var j: usize = 0;
                while (j < L) : (j += 8) {
                    const br: V8 = re[rb + j ..][0..8].*;
                    const bi: V8 = im[rb + j ..][0..8].*;
                    const ar: V8 = re[ra + j ..][0..8].*;
                    const ai: V8 = im[ra + j ..][0..8].*;
                    const tr = wr * br - wi * bi;
                    const ti = wr * bi + wi * br;
                    re[rb + j ..][0..8].* = ar - tr;
                    im[rb + j ..][0..8].* = ai - ti;
                    re[ra + j ..][0..8].* = ar + tr;
                    im[ra + j ..][0..8].* = ai + ti;
                }
            }
        }
    }
}

/// Blocked transpose of an R x C row-major array into a C x R one.
fn transpose(comptime R: usize, comptime C: usize, src: *const [N]f32, dst: *[N]f32) void {
    const B = 8;
    var by: usize = 0;
    while (by < R) : (by += B) {
        var bx: usize = 0;
        while (bx < C) : (bx += B) {
            for (by..by + B) |y| {
                for (bx..bx + B) |x| {
                    dst[x * R + y] = src[y * C + x];
                }
            }
        }
    }
}

comptime {
    sdk.exportTheme(State);
}

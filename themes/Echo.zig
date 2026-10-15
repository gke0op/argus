// @argus-theme: custom_shader
// ============================================================================
// ECHO // themes/Echo.zig
//
// A living echo-state reservoir. 120 leaky-tanh neurons with sparse random
// recurrent weights (spectral radius ~0.97, near the edge of chaos) listen to
// a slow two-tone signal. Neurons sit on a golden-angle spiral; warm = positive
// state, cool = negative. Each neuron's strongest live synapse is drawn.
// The readout learns live (recursive least squares) to predict the input
// DELAY ticks ahead. Each neuron is one orb driven by a single "life" level
// (its state, how fast it is moving, how much the readout is listening to it
// right now): size, glow and the white-hot centre all rise and fall together.
// Everything else is black.
//
// Contract: 1 allocation at init, 0 after; no clocks/I/O; draws via stride.
// Deterministic: fixed seed, own PRNG, no stdlib randomness.
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

const N: usize = 120;
const K: usize = 6;
const RHO: f32 = 0.97;
const LEAK: f32 = 0.18;
const GAIN: f32 = 1.8;
const DELAY: usize = 24; // forecast horizon in ticks (~0.8 s of signal time)
// lambda = 1: no forgetting. With lambda < 1, P winds up along the many weakly
// excited state directions and overflows after minutes; a wallpaper runs for days.
const P0: f64 = 100.0;
// One reservoir tick per step(); map Argus's fixed dt (0.008) onto 1/30 s of signal time.
const SIM_RATE: f64 = 1.0 / (30.0 * 0.008);
const GOLD: f32 = math.pi * (3.0 - 2.2360679775);
const PHI: f64 = 1.6180339887498949;

const WARM = [3]f32{ 255.0, 168.0, 82.0 };
const COOL = [3]f32{ 92.0, 162.0, 255.0 };
const NUCLEUS = [3]f32{ 255.0, 244.0, 228.0 };
// Forecast-error smoothing per tick (~3 s of signal time).
const ERR_EMA: f64 = 0.01;

const Rng = struct {
    s: u64,
    fn next(self: *Rng) u64 { // splitmix64
        self.s +%= 0x9E3779B97F4A7C15;
        var z = self.s;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return z ^ (z >> 31);
    }
    fn unit(self: *Rng) f32 {
        return @as(f32, @floatFromInt(self.next() >> 40)) / 16777216.0;
    }
    fn sym(self: *Rng) f32 {
        return self.unit() * 2.0 - 1.0;
    }
    fn below(self: *Rng, n: usize) usize {
        return @intCast(self.next() % @as(u64, n));
    }
    fn gauss(self: *Rng) f32 {
        const u_1 = @max(self.unit(), 1e-7);
        const u_2 = self.unit();
        return @sqrt(-2.0 * @log(u_1)) * @cos(2.0 * math.pi * u_2);
    }
};

fn tanh32(a: f32) f32 {
    const c = math.clamp(a, -15.0, 15.0);
    const e = @exp(2.0 * c);
    return (e - 1.0) / (e + 1.0);
}

fn sat(v: f32) u8 {
    if (!(v > 0.0)) return 0; // also catches NaN
    if (v >= 255.0) return 255;
    return @intFromFloat(v);
}

/// Float pixel coordinate -> i32, with NaN/huge values sent off-screen instead of panicking.
fn toI(v: f32) i32 {
    if (!(v > -1.0e6 and v < 1.0e6)) return -1;
    return @intFromFloat(@round(v));
}

fn addPx(buf: []u32, stride: usize, w: usize, h: usize, x: i32, y: i32, r: f32, g: f32, b: f32) void {
    if (x < 0 or y < 0) return;
    const ux: usize = @intCast(x);
    const uy: usize = @intCast(y);
    if (ux >= w or uy >= h) return;
    const idx = uy * stride + ux;
    if (idx >= buf.len) return;
    const p = buf[idx];
    const pr: f32 = @floatFromInt(p & 0xFF);
    const pg: f32 = @floatFromInt((p >> 8) & 0xFF);
    const pb: f32 = @floatFromInt((p >> 16) & 0xFF);
    buf[idx] = sdk.packRGBA(sat(pr + r), sat(pg + g), sat(pb + b));
}

fn addLine(buf: []u32, stride: usize, w: usize, h: usize, x0: f32, y0: f32, x1: f32, y1: f32, r: f32, g: f32, b: f32) void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len = @max(@abs(dx), @abs(dy));
    if (!(len < 1.0e5)) return;
    const n: usize = @as(usize, @intFromFloat(len)) + 1;
    const inv = 1.0 / @as(f32, @floatFromInt(n));
    for (0..n + 1) |k| {
        const tk = @as(f32, @floatFromInt(k)) * inv;
        addPx(buf, stride, w, h, toI(x0 + dx * tk), toI(y0 + dy * tk), r, g, b);
    }
}

fn addDot(buf: []u32, stride: usize, w: usize, h: usize, cx: f32, cy: f32, r_core: f32, r_halo: f32, core: [3]f32, halo: [3]f32) void {
    const ext = @ceil(r_halo) + 1.0;
    const x_lo = toI(cx - ext);
    const x_hi = toI(cx + ext);
    const y_lo = toI(cy - ext);
    const y_hi = toI(cy + ext);
    if (x_lo < -1 or y_lo < -1 and x_hi < 0) return;
    var y = y_lo;
    while (y <= y_hi) : (y += 1) {
        var x = x_lo;
        while (x <= x_hi) : (x += 1) {
            const fx = @as(f32, @floatFromInt(x)) - cx;
            const fy = @as(f32, @floatFromInt(y)) - cy;
            const d = @sqrt(fx * fx + fy * fy);
            if (d > r_halo) continue;
            if (d <= r_core + 0.5) {
                const f = math.clamp(r_core + 0.5 - d, 0.0, 1.0);
                addPx(buf, stride, w, h, x, y, core[0] * f, core[1] * f, core[2] * f);
            }
            if (r_halo > r_core) {
                const q = math.clamp(1.0 - (d - r_core) / (r_halo - r_core), 0.0, 1.0);
                const f = q * q;
                addPx(buf, stride, w, h, x, y, halo[0] * f, halo[1] * f, halo[2] * f);
            }
        }
    }
}

/// One orb: halo, body and a white-hot centre, all scaled by the same `life` in [0, 1].
fn addNeuron(buf: []u32, stride: usize, w: usize, h: usize, cx: f32, cy: f32, sc: f32, life: f32, col: [3]f32) void {
    const body = (2.0 + 4.0 * life) * sc;
    const halo = (4.0 + 12.0 * life) * sc;
    const k_body = 0.3 + 0.5 * life;
    const k_halo = 0.06 + 0.24 * life;
    const k_hot = 0.2 + 0.8 * life;
    const hot = [3]f32{ 0.4 * col[0] + 0.6 * NUCLEUS[0], 0.4 * col[1] + 0.6 * NUCLEUS[1], 0.4 * col[2] + 0.6 * NUCLEUS[2] };
    const ext = @ceil(halo) + 1.0;
    const x_lo = toI(cx - ext);
    const x_hi = toI(cx + ext);
    const y_lo = toI(cy - ext);
    const y_hi = toI(cy + ext);
    var y = y_lo;
    while (y <= y_hi) : (y += 1) {
        var x = x_lo;
        while (x <= x_hi) : (x += 1) {
            const fx = @as(f32, @floatFromInt(x)) - cx;
            const fy = @as(f32, @floatFromInt(y)) - cy;
            const d = @sqrt(fx * fx + fy * fy);
            if (d > halo) continue;
            const q = 1.0 - d / halo;
            var r = col[0] * k_halo * q * q;
            var g = col[1] * k_halo * q * q;
            var b = col[2] * k_halo * q * q;
            const edge = math.clamp(body + 0.5 - d, 0.0, 1.0);
            if (edge > 0.0) {
                // Centre blends from the body colour to white-hot, continuously, with no inner rim.
                const c = 1.0 - math.clamp(d / body, 0.0, 1.0);
                const m = k_hot * @sqrt(c);
                r += edge * ((1.0 - m) * col[0] * k_body + m * hot[0]);
                g += edge * ((1.0 - m) * col[1] * k_body + m * hot[1]);
                b += edge * ((1.0 - m) * col[2] * k_body + m * hot[2]);
            }
            addPx(buf, stride, w, h, x, y, r, g, b);
        }
    }
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    t: f64,
    x: [N]f32,
    dx: [N]f32, // last tick's change in state: how hard each neuron is firing
    src: [N][K]u8,
    wt: [N][K]f32,
    w_in: [N]f32,
    w_out: [N]f64,
    P: [N][N]f64,
    xh: [DELAY + 1][N]f32,
    xh_head: usize,
    steps: u64,
    err: f64, // smoothed squared forecast error

    /// Exactly one allocation; every table lives inline in State.
    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.* = .{
            .w = w,
            .h = h,
            .scale = scale,
            .t = 0.0,
            .x = @splat(0.0),
            .dx = @splat(0.0),
            .src = undefined,
            .wt = undefined,
            .w_in = undefined,
            .w_out = @splat(0.0),
            .P = undefined,
            .xh = @splat(@splat(0.0)),
            .xh_head = 0,
            .steps = 0,
            .err = 1.0,
        };
        var rng = Rng{ .s = 7 };
        const w_scale: f32 = RHO / (@sqrt(@as(f32, @floatFromInt(K))) * 0.5774);
        for (0..N) |i| {
            for (0..K) |k| {
                self.src[i][k] = @intCast(rng.below(N));
                self.wt[i][k] = rng.sym() * w_scale;
            }
        }
        for (0..N) |i| self.w_in[i] = rng.sym();
        self.resetReadout();
        return self;
    }

    fn resetReadout(self: *State) void {
        self.w_out = @splat(0.0);
        for (0..N) |i| {
            for (0..N) |j| self.P[i][j] = if (i == j) P0 else 0.0;
        }
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    /// One reservoir tick per call. Argus owns time; never read a clock here.
    pub fn step(self: *State, dt: f64) void {
        if (!(dt > 0.0 and dt < 1.0)) return;
        const tt = self.t;
        const u: f32 = @floatCast(0.6 * @sin(0.7 * tt) + 0.4 * @sin(0.7 * PHI * tt));
        var nx: [N]f32 = undefined;
        for (0..N) |i| {
            var a: f32 = GAIN * self.w_in[i] * u;
            for (0..K) |k| a += self.wt[i][k] * self.x[self.src[i][k]];
            nx[i] = (1.0 - LEAK) * self.x[i] + LEAK * tanh32(a);
        }
        for (0..N) |i| self.dx[i] = nx[i] - self.x[i];
        self.x = nx;

        // Remember x(t); the oldest slot holds x(t - DELAY).
        self.xh[self.xh_head] = self.x;
        const old = (self.xh_head + 1) % (DELAY + 1);
        self.xh_head = old;

        // RLS: learn w so that w . x(t - DELAY) ~ u(t). yhat is the a-priori
        // forecast, made from a state DELAY ticks old with weights fit only to the past.
        var yhat: f64 = 0.0;
        const ready = self.steps >= DELAY;
        if (ready) {
            const xd = &self.xh[old];
            var px: [N]f64 = undefined;
            var den: f64 = 1.0;
            for (0..N) |i| {
                var acc: f64 = 0.0;
                for (0..N) |j| acc += self.P[i][j] * xd[j];
                px[i] = acc;
                den += @as(f64, xd[i]) * acc;
                yhat += self.w_out[i] * xd[i];
            }
            const e = @as(f64, u) - yhat;
            self.err += ERR_EMA * (@min(e * e, 4.0) - self.err);
            if (den > 1.0e-12 and math.isFinite(den) and math.isFinite(yhat)) {
                const inv = 1.0 / den;
                for (0..N) |i| self.w_out[i] += px[i] * inv * e;
                for (0..N) |i| {
                    const ki = px[i] * inv;
                    for (0..N) |j| self.P[i][j] -= ki * px[j];
                }
            } else {
                self.resetReadout();
                self.err = 1.0;
            }
        }

        self.steps += 1;
        self.t += dt * SIM_RATE;
    }

    pub fn hasNaN(self: *const State) bool {
        if (!math.isFinite(self.t)) return true;
        for (self.x) |v| if (!math.isFinite(v)) return true;
        for (self.w_out) |v| if (!math.isFinite(v)) return true;
        if (!math.isFinite(self.err)) return true;
        for (self.dx) |v| if (!math.isFinite(v)) return true;
        return false;
    }

    /// Zero allocations. Every write goes through addPx, which indexes buf[y * stride + x].
    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        if (w == 0 or self.h == 0 or stride < w) return;
        const h: usize = @min(self.h, buf.len / stride);
        if (h == 0) return;

        // Every pixel that is not part of the network is off.
        const black = sdk.packRGBA(0, 0, 0);
        for (0..h) |yy| @memset(buf[yy * stride .. yy * stride + w], black);

        const hf: f32 = @floatFromInt(h);
        const wf: f32 = @floatFromInt(w);
        const sc: f32 = math.clamp(@as(f32, @floatCast(self.scale)), 1.0, 4.0);
        const cx = wf * 0.5;
        const cy = hf * 0.5;
        const R = @min(wf, hf) * 0.42;
        const rot: f32 = @floatCast(@mod(0.02 * self.t, 2.0 * math.pi));

        var px: [N]f32 = undefined;
        var py: [N]f32 = undefined;
        for (0..N) |i| {
            const fi: f32 = @floatFromInt(i);
            const r = R * @sqrt((fi + 0.5) / @as(f32, @floatFromInt(N)));
            const a = fi * GOLD + rot;
            px[i] = cx + r * @cos(a);
            py[i] = cy + r * @sin(a);
        }

        // Strongest live synapse into each neuron.
        for (0..N) |i| {
            var best: usize = 0;
            var best_s: f32 = -1.0;
            for (0..K) |k| {
                const s = @abs(self.wt[i][k] * self.x[self.src[i][k]]);
                if (s > best_s) {
                    best_s = s;
                    best = k;
                }
            }
            if (best_s <= 0.12) continue;
            const j: usize = self.src[i][best];
            const signed = self.wt[i][best] * self.x[j];
            const col = if (signed > 0.0) WARM else COOL;
            const inten = @min(@sqrt(best_s) * 0.6, 1.0) * 0.55;
            // Stop at the orbs' edges so synapses never cut across a neuron's body.
            const lx = px[i] - px[j];
            const ly = py[i] - py[j];
            const len = @sqrt(lx * lx + ly * ly);
            const gap = 7.0 * sc;
            if (len <= 2.0 * gap) continue;
            const ux = lx / len * gap;
            const uy = ly / len * gap;
            addLine(buf, stride, w, h, px[j] + ux, py[j] + uy, px[i] - ux, py[i] - uy, col[0] * inten, col[1] * inten, col[2] * inten);
        }

        // Live readout share of each neuron, and its firing rate, both normalized to the busiest.
        var c_max: f32 = 1.0e-9;
        var d_max: f32 = 1.0e-9;
        for (0..N) |i| {
            c_max = @max(c_max, @abs(@as(f32, @floatCast(self.w_out[i])) * self.x[i]));
            d_max = @max(d_max, @abs(self.dx[i]));
        }
        const conf: f32 = @floatCast(math.clamp(1.0 - @sqrt(self.err) / 0.5, 0.0, 1.0));

        // Neurons: one life level per neuron drives the whole orb.
        for (0..N) |i| {
            const v = self.x[i];
            const m = @sqrt(@min(@abs(v), 1.0));
            const fire = @sqrt(@abs(self.dx[i]) / d_max);
            const heard = @sqrt(@abs(@as(f32, @floatCast(self.w_out[i])) * v) / c_max) * (0.3 + 0.7 * conf);
            const life = math.clamp(0.45 * m + 0.3 * fire + 0.4 * heard, 0.0, 1.0);
            addNeuron(buf, stride, w, h, px[i], py[i], sc, life, if (v > 0.0) WARM else COOL);
        }
    }
};

comptime {
    sdk.exportTheme(State);
}

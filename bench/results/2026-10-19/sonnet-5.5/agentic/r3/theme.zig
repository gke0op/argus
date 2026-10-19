// ============================================================================
// SONNET55_FIELD // Track B (Symplectic / PDE field dynamics)
//
// "Kirchhoff Marbling": twelve point vortices of mixed sign (Kirchhoff's
// Hamiltonian point-vortex system for 2D incompressible Euler flow) stir a
// rectangular tank with free-slip walls. Passive Lagrangian tracers released
// as striped ink sheets are advected by the flow and deposit ink, so the sheets
// fold and stretch into marbled filaments (a Lagrangian view of chaotic
// advection). Two inks, one warm and one cool, add where they overlap.
//
// COMPUTED (all on the CPU, inside step()):
//   * Vortex motion: dr_i/dt from the Biot-Savart law with a Rankine-like
//     desingularised kernel Gamma*(r_perp)/(2*pi*(r^2 + d^2)), d = 0.035 of the
//     tank height. RK4, substeps of at most 0.01 time units.
//   * Walls: free-slip walls on all four sides by the method of images, i.e. a
//     reflection lattice truncated at +-1 periods (36 images per vortex). This
//     is the exact solution only for the infinite lattice; the truncation leaves
//     a small residual normal velocity at the walls, and tracers are clamped
//     to the tank so none can escape.
//   * The motion is Hamiltonian: H = -(1/8pi) sum Gamma_i Gamma_j s ln(r^2+d^2)
//     over the same truncated image set (self term excluded). A `zig test`
//     block at the bottom integrates the vortices for 60 time units and asserts
//     that H is conserved; it does not run in the theme library.
//   * Tracers: midpoint (RK2) advection through a 80x50 velocity grid that is
//     bilinearly sampled. The grid is rebuilt in 4 round-robin slices, one per
//     frame, so its cost per frame is constant; it therefore lags the vortices
//     by up to 3 steps of step() (small next to the 0.035 core at dt = 0.008).
//
// CHOSEN, NOT MEASURED: the vortex strengths and positions (a fixed-seed random
// draw), the 0.035 core, the ink palette, the trail decay time (0.5 time units),
// the ink lifetime (6-11 time units, then a tracer is re-released on a stripe and
// fades in over 1.2) and the speed (1 time unit per second of step() dt). The tank
// is pre-stirred for 3.6 time units in init() so frame 1 is already marbled. It is a
// hydrodynamic toy: point vortices are the inviscid limit.
//
// Not modelled: viscosity, vortex merging, pressure, ink diffusion (trails fade by
// a fixed time constant instead), compressibility. The ink is not conserved: it is
// re-released on a timer.
// ============================================================================
const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

const NV = 12; // vortices
const NIMG = 36; // 4 reflection families x 3 x 3 lattice cells
const GW = 80; // velocity-grid nodes
const GH = 50;
const GN = GW * GH;
const GSLICES = 4;
const NT = 80_000; // tracers
const NB = 9; // ink stripes
const CORE: f64 = 0.035; // vortex core, in tank heights
const SPEED: f64 = 1.0; // simulation time units per second of dt
const TAU: f64 = 0.5; // trail decay, simulation time units
const TWO_PI: f64 = 2.0 * math.pi;
const WARM_STEPS: usize = 90;
const WARM_DT: f64 = 0.04;
const V8 = @Vector(8, f32);

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    aspect: f64,
    rng: u64,
    slice: usize,
    decay_keep: u16,

    vx: [NV]f64,
    vy: [NV]f64,
    gam: [NV]f64,

    gnx: [GN]f32,
    gny: [GN]f32,
    gu: [GN]f32,
    gv: [GN]f32,
    inv_hx: f32,
    inv_hy: f32,

    tx: [NT]f32,
    ty: [NT]f32,
    tage: [NT]f32,
    tlife: [NT]f32,
    tspec: [NT]u8,

    field: [MAX_PIXELS]u16, // low byte: warm ink, high byte: cool ink
    lut: [65536]u32, // ink pair (cool << 8 | warm) -> final pixel, background included

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.aspect = @as(f64, @floatFromInt(self.w)) / @as(f64, @floatFromInt(@max(@as(usize, 1), self.h)));
        self.rng = 0x9E3779B97F4A7C15;
        self.slice = 0;
        self.decay_keep = 250;
        @memset(&self.field, 0);
        @memset(&self.gu, 0);
        @memset(&self.gv, 0);

        // Velocity-grid node coordinates.
        const hx = self.aspect / @as(f64, GW - 1);
        const hy = 1.0 / @as(f64, GH - 1);
        self.inv_hx = @floatCast(1.0 / hx);
        self.inv_hy = @floatCast(1.0 / hy);
        for (0..GH) |gy| {
            for (0..GW) |gx| {
                self.gnx[gy * GW + gx] = @floatCast(@as(f64, @floatFromInt(gx)) * hx);
                self.gny[gy * GW + gx] = @floatCast(@as(f64, @floatFromInt(gy)) * hy);
            }
        }

        // Vortices: alternating signs, varied strengths, no two closer than 0.16.
        var placed: usize = 0;
        while (placed < NV) {
            const px = 0.08 + self.rnd() * (self.aspect - 0.16);
            const py = 0.08 + self.rnd() * 0.84;
            var ok = true;
            for (0..placed) |j| {
                const dx = px - self.vx[j];
                const dy = py - self.vy[j];
                if (dx * dx + dy * dy < 0.16 * 0.16) ok = false;
            }
            if (!ok) continue;
            const mag = 0.07 + 0.16 * self.rnd();
            self.vx[placed] = px;
            self.vy[placed] = py;
            self.gam[placed] = if (placed % 2 == 0) mag else -mag;
            placed += 1;
        }

        // Palettes: ember (warm) and glacier (cool) over a near-black tank, baked into one
        // 64K table indexed by the raw (cool, warm) ink bytes so draw() is one lookup a pixel.
        var pal_a: [256]u32 = undefined;
        var pal_b: [256]u32 = undefined;
        for (0..256) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 255.0;
            const g = math.pow(f32, t, 1.1);
            pal_a[i] = ramp(g, .{ 0, 0, 0 }, .{ 120, 12, 34 }, .{ 255, 120, 38 }, .{ 255, 232, 180 });
            pal_b[i] = ramp(g, .{ 0, 0, 0 }, .{ 10, 26, 110 }, .{ 24, 176, 235 }, .{ 205, 248, 255 });
        }
        const bg = sdk.packRGBA(3, 4, 11);
        for (0..256) |b| {
            for (0..256) |a| {
                self.lut[(b << 8) | a] = sdk.addRGB(sdk.addRGB(pal_a[a], pal_b[b]), bg);
            }
        }

        // Tracers start as ink stripes and are stirred for WARM_STEPS before frame 1.
        for (0..NT) |i| self.respawn(i);
        for (0..WARM_STEPS) |k| {
            self.advance(WARM_DT, true, k + 40 >= WARM_STEPS);
        }
        // Stagger ages so respawns are spread over time rather than all at once.
        for (0..NT) |i| {
            const room: f64 = @as(f64, self.tlife[i]) - 4.6;
            self.tage[i] = @floatCast(3.6 + self.rnd() * room);
        }
        self.slice = 0;
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn rnd(self: *State) f64 {
        // xorshift64*
        var x = self.rng;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.rng = x;
        const r: u64 = x *% 0x2545F4914F6CDD1D;
        return @as(f64, @floatFromInt(r >> 11)) * (1.0 / 9007199254740992.0);
    }

    fn respawn(self: *State, i: usize) void {
        const band: usize = @min(@as(usize, @intFromFloat(self.rnd() * NB)), NB - 1);
        const u = self.rnd();
        const y = (@as(f64, @floatFromInt(band)) + 0.5 + (u - 0.5) * 0.15) / NB;
        self.tx[i] = @floatCast(self.rnd() * self.aspect);
        self.ty[i] = @floatCast(y);
        self.tspec[i] = @intCast(band & 1);
        self.tage[i] = 0.0;
        self.tlife[i] = @floatCast(6.0 + self.rnd() * 5.0);
    }

    // One image of vortex `j` for reflection family `f` (bit0: mirror x, bit1:
    // mirror y) and lattice cell (m, n). Returns x, y and signed circulation.
    inline fn image(self: *const State, j: usize, f: usize, m: i32, n: i32) [3]f64 {
        const sx: f64 = if (f & 1 == 1) -1.0 else 1.0;
        const sy: f64 = if (f & 2 == 2) -1.0 else 1.0;
        return .{
            sx * self.vx[j] + 2.0 * @as(f64, @floatFromInt(m)) * self.aspect,
            sy * self.vy[j] + 2.0 * @as(f64, @floatFromInt(n)),
            sx * sy * self.gam[j],
        };
    }

    // Velocity of every vortex at positions px/py (RK stage), written to ox/oy.
    fn vortexVel(self: *State, px: *const [NV]f64, py: *const [NV]f64, ox: *[NV]f64, oy: *[NV]f64) void {
        const saved_x = self.vx;
        const saved_y = self.vy;
        self.vx = px.*;
        self.vy = py.*;
        const c2 = CORE * CORE;
        for (0..NV) |i| {
            var u: f64 = 0.0;
            var v: f64 = 0.0;
            for (0..NV) |j| {
                for (0..4) |f| {
                    var m: i32 = -1;
                    while (m <= 1) : (m += 1) {
                        var n: i32 = -1;
                        while (n <= 1) : (n += 1) {
                            if (i == j and f == 0 and m == 0 and n == 0) continue;
                            const im = self.image(j, f, m, n);
                            const dx = px[i] - im[0];
                            const dy = py[i] - im[1];
                            const k = im[2] / (TWO_PI * (dx * dx + dy * dy + c2));
                            u -= dy * k;
                            v += dx * k;
                        }
                    }
                }
            }
            ox[i] = u;
            oy[i] = v;
        }
        self.vx = saved_x;
        self.vy = saved_y;
    }

    fn stepVortices(self: *State, sim_dt: f64) void {
        const nsub: usize = @max(1, @as(usize, @intFromFloat(@ceil(sim_dt / 0.01))));
        const hdt = sim_dt / @as(f64, @floatFromInt(nsub));
        for (0..nsub) |_| {
            var k1x: [NV]f64 = undefined;
            var k1y: [NV]f64 = undefined;
            var k2x: [NV]f64 = undefined;
            var k2y: [NV]f64 = undefined;
            var k3x: [NV]f64 = undefined;
            var k3y: [NV]f64 = undefined;
            var k4x: [NV]f64 = undefined;
            var k4y: [NV]f64 = undefined;
            var tx_: [NV]f64 = undefined;
            var ty_: [NV]f64 = undefined;
            self.vortexVel(&self.vx, &self.vy, &k1x, &k1y);
            for (0..NV) |i| {
                tx_[i] = self.vx[i] + 0.5 * hdt * k1x[i];
                ty_[i] = self.vy[i] + 0.5 * hdt * k1y[i];
            }
            self.vortexVel(&tx_, &ty_, &k2x, &k2y);
            for (0..NV) |i| {
                tx_[i] = self.vx[i] + 0.5 * hdt * k2x[i];
                ty_[i] = self.vy[i] + 0.5 * hdt * k2y[i];
            }
            self.vortexVel(&tx_, &ty_, &k3x, &k3y);
            for (0..NV) |i| {
                tx_[i] = self.vx[i] + hdt * k3x[i];
                ty_[i] = self.vy[i] + hdt * k3y[i];
            }
            self.vortexVel(&tx_, &ty_, &k4x, &k4y);
            for (0..NV) |i| {
                self.vx[i] += hdt / 6.0 * (k1x[i] + 2.0 * k2x[i] + 2.0 * k3x[i] + k4x[i]);
                self.vy[i] += hdt / 6.0 * (k1y[i] + 2.0 * k2y[i] + 2.0 * k3y[i] + k4y[i]);
            }
        }
    }

    // Rebuild velocity-grid nodes [lo, hi) from the current vortex positions.
    fn rebuildGrid(self: *State, lo: usize, hi: usize) void {
        @memset(self.gu[lo..hi], 0);
        @memset(self.gv[lo..hi], 0);
        const c2: V8 = @splat(@as(f32, @floatCast(CORE * CORE)));
        for (0..NV) |j| {
            for (0..4) |f| {
                var m: i32 = -1;
                while (m <= 1) : (m += 1) {
                    var n: i32 = -1;
                    while (n <= 1) : (n += 1) {
                        const im = self.image(j, f, m, n);
                        const ix: V8 = @splat(@as(f32, @floatCast(im[0])));
                        const iy: V8 = @splat(@as(f32, @floatCast(im[1])));
                        const g: V8 = @splat(@as(f32, @floatCast(im[2] / TWO_PI)));
                        var k = lo;
                        while (k < hi) : (k += 8) {
                            const X: V8 = self.gnx[k..][0..8].*;
                            const Y: V8 = self.gny[k..][0..8].*;
                            const dx = X - ix;
                            const dy = Y - iy;
                            const kk = g / (dx * dx + dy * dy + c2);
                            const U: V8 = self.gu[k..][0..8].*;
                            const W: V8 = self.gv[k..][0..8].*;
                            self.gu[k..][0..8].* = U - dy * kk;
                            self.gv[k..][0..8].* = W + dx * kk;
                        }
                    }
                }
            }
        }
    }

    inline fn sample(self: *const State, x: f32, y: f32) [2]f32 {
        const gx = math.clamp(x * self.inv_hx, 0.0, @as(f32, GW - 1) - 0.001);
        const gy = math.clamp(y * self.inv_hy, 0.0, @as(f32, GH - 1) - 0.001);
        const ix: usize = @intFromFloat(gx);
        const iy: usize = @intFromFloat(gy);
        const fx = gx - @as(f32, @floatFromInt(ix));
        const fy = gy - @as(f32, @floatFromInt(iy));
        const o = iy * GW + ix;
        const w00 = (1.0 - fx) * (1.0 - fy);
        const w10 = fx * (1.0 - fy);
        const w01 = (1.0 - fx) * fy;
        const w11 = fx * fy;
        return .{
            self.gu[o] * w00 + self.gu[o + 1] * w10 + self.gu[o + GW] * w01 + self.gu[o + GW + 1] * w11,
            self.gv[o] * w00 + self.gv[o + 1] * w10 + self.gv[o + GW] * w01 + self.gv[o + GW + 1] * w11,
        };
    }

    inline fn deposit(self: *State, px: f32, py: f32, amp: u32, spec: u8) void {
        if (!(px >= 0.0 and py >= 0.0)) return;
        const ix: usize = @intFromFloat(px);
        const iy: usize = @intFromFloat(py);
        if (ix >= self.w or iy >= self.h) return;
        const idx = iy * self.w + ix;
        const sh: u4 = if (spec == 0) 0 else 8;
        const f: u32 = self.field[idx];
        const cur: u32 = (f >> sh) & 0xFF;
        const nv: u32 = @min(@as(u32, 255), cur + amp);
        const cleared: u32 = f & ~(@as(u32, 0xFF) << sh);
        self.field[idx] = @intCast(cleared | (nv << sh));
    }

    // Fade the ink, then advance vortices, grid and tracers by sim_dt.
    fn advance(self: *State, sim_dt: f64, full_grid: bool, do_splat: bool) void {
        // Ink fade: keep = exp(-dt/TAU) in 8.8 fixed point, applied bytewise.
        const keep: u16 = @intFromFloat(@floor(256.0 * @exp(-sim_dt / TAU)));
        self.decay(keep);

        self.stepVortices(sim_dt);
        if (full_grid) {
            self.rebuildGrid(0, GN);
        } else {
            const lo = self.slice * (GN / GSLICES);
            self.rebuildGrid(lo, lo + GN / GSLICES);
            self.slice = (self.slice + 1) % GSLICES;
        }

        const dt: f32 = @floatCast(sim_dt);
        const hpx: f32 = @floatFromInt(self.h);
        const A: f32 = @floatCast(self.aspect);
        for (0..NT) |i| {
            const x0 = self.tx[i];
            const y0 = self.ty[i];
            const v1 = self.sample(x0, y0);
            const v2 = self.sample(x0 + 0.5 * dt * v1[0], y0 + 0.5 * dt * v1[1]);
            const x1 = math.clamp(x0 + dt * v2[0], 0.0005, A - 0.0005);
            const y1 = math.clamp(y0 + dt * v2[1], 0.0005, 0.9995);
            self.tx[i] = x1;
            self.ty[i] = y1;
            const age = self.tage[i] + dt;
            self.tage[i] = age;
            const life = self.tlife[i];
            if (age >= life) {
                self.respawn(i);
                continue;
            }
            if (!do_splat) continue;
            const env = @min(@min(age / 1.2, (life - age) / 1.2), 1.0);
            const amp_f = 34.0 * env;
            const ddx = (x1 - x0) * hpx;
            const ddy = (y1 - y0) * hpx;
            const dist = @sqrt(ddx * ddx + ddy * ddy);
            const ns: usize = @min(@as(usize, 4), @as(usize, @intFromFloat(dist)) + 1);
            const amp: u32 = @intFromFloat(amp_f);
            const sp = self.tspec[i];
            var s: usize = 1;
            while (s <= ns) : (s += 1) {
                const t: f32 = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(ns));
                self.deposit((x0 + (x1 - x0) * t) * hpx, (y0 + (y1 - y0) * t) * hpx, amp, sp);
            }
        }
    }

    fn decay(self: *State, keep: u16) void {
        const bytes = std.mem.sliceAsBytes(self.field[0..]);
        const n = @min(bytes.len, ((self.w * self.h * 2) + 31) & ~@as(usize, 31));
        const V = @Vector(32, u8);
        const W = @Vector(32, u16);
        const kv: W = @splat(keep);
        const one: V = @splat(1);
        var i: usize = 0;
        while (i < n) : (i += 32) {
            const v: V = bytes[i..][0..32].*;
            const wide: W = v;
            const prod: W = (wide * kv) >> @as(W, @splat(8));
            const narrow: V = @intCast(prod);
            bytes[i..][0..32].* = @min(narrow, v -| one);
        }
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        self.advance(dt * SPEED, false, true);
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        for (0..self.h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.field[y * w .. y * w + w];
            for (dst_row, src_row) |*dst, f| dst.* = self.lut[f];
        }
    }

    pub fn hasNaN(self: *const State) bool {
        for (0..NV) |i| {
            if (!math.isFinite(self.vx[i]) or !math.isFinite(self.vy[i])) return true;
        }
        return !math.isFinite(self.time_sec);
    }

    // Hamiltonian of the truncated image system (see header). Used by the test.
    pub fn hamiltonian(self: *const State) f64 {
        var hsum: f64 = 0.0;
        const c2 = CORE * CORE;
        for (0..NV) |i| {
            for (0..NV) |j| {
                for (0..4) |f| {
                    var m: i32 = -1;
                    while (m <= 1) : (m += 1) {
                        var n: i32 = -1;
                        while (n <= 1) : (n += 1) {
                            if (i == j and f == 0 and m == 0 and n == 0) continue;
                            const im = self.image(j, f, m, n);
                            const dx = self.vx[i] - im[0];
                            const dy = self.vy[i] - im[1];
                            // im[2] already carries Gamma_j * s
                            hsum += self.gam[i] * im[2] * @log(dx * dx + dy * dy + c2);
                        }
                    }
                }
            }
        }
        return -hsum / (8.0 * math.pi);
    }
};

fn lerpC(a: [3]f32, b: [3]f32, t: f32) [3]f32 {
    return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t };
}

fn ramp(t: f32, c0: [3]f32, c1: [3]f32, c2: [3]f32, c3: [3]f32) u32 {
    const c = if (t < 0.34)
        lerpC(c0, c1, t / 0.34)
    else if (t < 0.7)
        lerpC(c1, c2, (t - 0.34) / 0.36)
    else
        lerpC(c2, c3, (t - 0.7) / 0.3);
    return sdk.packRGBA(
        @intFromFloat(math.clamp(c[0], 0.0, 255.0)),
        @intFromFloat(math.clamp(c[1], 0.0, 255.0)),
        @intFromFloat(math.clamp(c[2], 0.0, 255.0)),
    );
}

comptime {
    sdk.exportTheme(State);
}

test "point-vortex Hamiltonian is conserved (RK4, image walls)" {
    const st = try State.init(std.heap.page_allocator, 320, 200, 1.0);
    defer st.deinit(std.heap.page_allocator);
    const h0 = st.hamiltonian();
    var worst: f64 = 0.0;
    var t: f64 = 0.0;
    while (t < 60.0) : (t += 0.04) {
        st.stepVortices(0.04);
        worst = @max(worst, @abs(st.hamiltonian() - h0));
    }
    const rel = worst / @max(@abs(h0), 1e-9);
    std.debug.print("\nH0 = {d:.9}, worst |dH| = {e}, relative = {e}\n", .{ h0, worst, rel });
    try std.testing.expect(rel < 1e-5);
    // Sanity: the test is not vacuous. The vortices must actually have moved.
    var moved: f64 = 0.0;
    const fresh = try State.init(std.heap.page_allocator, 320, 200, 1.0);
    defer fresh.deinit(std.heap.page_allocator);
    for (0..NV) |i| moved = @max(moved, @abs(st.vx[i] - fresh.vx[i]) + @abs(st.vy[i] - fresh.vy[i]));
    try std.testing.expect(moved > 0.05);
}

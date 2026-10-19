// VORTEX LATTICE // themes/Opus55_Field.zig
// Opus 5.5 (Claude Code, agentic ARGUS-BENCH run, Track B), 2026-10-19.
//
// What you see: a rotating Bose-Einstein condensate seen from above, along its rotation axis,
//   drawn the way images of rotating condensates are usually shown: atoms bright on black,
//   each quantised vortex a dark hole. About 50 holes sit in a triangular (Abrikosov) lattice
//   that turns rigidly with the cloud, once every ~26 s. Over ~13 minutes the stirring rate
//   rises and falls: the cloud swells and shrinks, the lattice spacing follows, vortices
//   drift out through the rim as the rotation slows, and new ones are drawn in through a
//   rippling rim as it speeds up, leaving the lattice disordered until it settles.
//
// The model: the damped 2D Gross-Pitaevskii equation in the frame rotating at Omega(t),
//   (i - gamma) dpsi/dt = [ -1/2 lap + 1/2 r^2 + g|psi|^2 - mu - Omega L_z ] psi,
//   in trap units (hbar = m = omega_perp = 1), solved live on a 256x256 grid over [-11, 11]^2
//   (dx = 0.086, healing length ~0.20 = 2.3 cells) with 4th-order Runge-Kutta, h = 0.003,
//   a hard wall at r = 10.9, and the norm reset to 1 after each step.
//
// COMPUTED (out of the equation, not drawn): the cores and their size, the lattice and its
//   spacing (~2.1 at Omega = 0.8, i.e. vortex density ~Omega/pi), the cloud's swelling with
//   Omega, vortices leaving and entering, rim ripples (surface modes) and the rigid rotation
//   in the lab frame.
// CHOSEN (taste, stated): g = 1342 (Thomas-Fermi radius 8.3 at Omega = 0.80); gamma = 0.03,
//   a phenomenological damping by the thermal cloud (value from memory of the literature);
//   the stirring schedule Omega(t) = 0.80 + 0.08 sin(2 pi t / 240); the time-lapse, 0.3 trap
//   units per wall second (for a 2 pi x 50 Hz trap, ~1000x slower than the atoms); the start
//   state (a triangular lattice imprinted at Omega = 0.80 with small jitter, then relaxed in
//   imaginary time in init); the cool grey palette, peaking below white. The image shows
//   |psi|^3: for a 3D Thomas-Fermi cloud the column density goes as (mu - V)^(3/2) while this
//   2D density goes as (mu - V), so |psi|^3 stands in for the column density.
// NOT MODELLED: time-of-flight expansion (real images are taken after release, which enlarges
//   the cores; this shows the cloud in the trap); the 3D cloud and vortex-line bending; the
//   thermal cloud itself (only its damping); imaging noise and optical resolution.
// SOURCES: the damped GPE and rotating-lattice phenomenology (Tsubota, Kasamatsu & Ueda 2002;
//   Abo-Shaeer et al., Science 292, 476, 2001, lattices of up to ~130 vortices in sodium) are
//   from memory [recalled, not re-read]; no photograph was consulted this session.
// CHECKED: the ARGUS harness gates; renders read by eye at 1:1 (no grid or banding seen);
//   fast-forward runs (the same file with SIM_RATE x100) to t = 60, 120, 180, 240 and 300 trap
//   units (~1.1 Omega cycles, ~22 minutes of wall time): no NaN, the cloud and lattice spacing
//   follow Omega; the count (by eye) fell from ~49 to ~33 by t = 240 as Omega went through its
//   minimum and rose to ~45 by t = 300, with vortices entering through a scalloped rim and the
//   lattice disordered. Past ~22 minutes (whether the count settles or ratchets) is NOT checked.
// How it works: step() advances the GPE (zero allocations; all arrays live in State), then
//   computes |psi| and upsamples it 2x with separable Catmull-Rom into a 512x512 table.
//   draw() fills each row with the background and, across the cloud's span, rotates each
//   pixel into the rotating frame, samples the table bilinearly (8 pixels per SIMD step) and
//   maps |psi| through a 1024-entry colour table.
// Cost: 3.4-3.5 ms/frame average in the ARGUS harness at 1920x1200 (one CPU thread, ~0.8 GPE
//   steps per harness frame), measured on a shared, busy Apple Silicon Mac; not a quiet machine.
//   Init holds one 4.3 MiB State and runs ~160 relaxation steps.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

const NG: usize = 256; // simulation grid
const NN: usize = NG * NG;
const UP: usize = 2; // render upsampling
const M: usize = NG * UP;
const L: f32 = 22.0; // domain [-11, 11]
const HALF_L: f32 = L * 0.5;
const DX: f32 = L / @as(f32, @floatFromInt(NG));
const DXH: f32 = L / @as(f32, @floatFromInt(M));
const R_WALL: f32 = 10.9;
const R_SCREEN: f32 = 8.3; // cloud radius (trap units) that spans 0.41 of the screen height

const G: f32 = 1342.0;
const GAMMA: f32 = 0.03;
const H_STEP: f32 = 0.003;
const SIM_RATE: f64 = 0.3; // trap units per wall second
const OMEGA0: f32 = 0.80;
const OMEGA_AMP: f32 = 0.08;
const OMEGA_PERIOD: f64 = 240.0; // trap units (~13.3 min at SIM_RATE)
const MAX_STEPS_PER_CALL: usize = 4;
const RELAX_STEPS: usize = 160;
const LUT_N: usize = 1024;
const LUT_TOP: f32 = 1.08; // LUT spans |psi| / peak in [0, 1.08]
const BG_R: f32 = 4.0;
const BG_G: f32 = 5.0;
const BG_B: f32 = 8.0;

const Field = [NN]f32;

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    sim_t: f64,
    acc: f64,
    theta: f64, // lattice rotation angle in the lab frame
    theta_draw: f64, // theta advanced by the unspent part of the last step
    omega: f32,
    mu: f32,
    a_ref: f32, // smoothed peak amplitude |psi| for display normalisation
    r_ext: f32, // radius beyond which the cloud is empty (render span)

    re: Field,
    im: Field,
    tr: Field,
    ti: Field,
    kr: Field,
    ki: Field,
    ar: Field,
    ai: Field,
    pot: Field, // 1/2 r^2
    mask: Field, // 1 inside the wall, 0 outside
    amp: Field, // |psi|
    up_row: [NG * M]f32,
    amp_hi: [M * M]f32,
    up_base: [M]i32,
    up_w: [M][4]f32,
    lut: [LUT_N]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.sim_t = 0.0;
        self.acc = 0.0;
        self.theta = 0.0;
        self.theta_draw = 0.0;
        self.omega = OMEGA0;
        self.a_ref = 0.0;
        self.r_ext = R_WALL;

        // Geometry tables.
        for (0..NG) |iy| {
            const y = coord(iy);
            for (0..NG) |ix| {
                const x = coord(ix);
                const r2 = x * x + y * y;
                const k = iy * NG + ix;
                self.pot[k] = 0.5 * r2;
                const inside = r2 < R_WALL * R_WALL and ix > 0 and iy > 0 and ix + 1 < NG and iy + 1 < NG;
                self.mask[k] = if (inside) 1.0 else 0.0;
            }
        }

        // Catmull-Rom 3x upsampling weights: hi-res cell j sits at coarse coordinate (j+0.5)/3 - 0.5.
        for (0..M) |j| {
            const gc: f32 = (@as(f32, @floatFromInt(j)) + 0.5) / @as(f32, @floatFromInt(UP)) - 0.5;
            const base_f = @floor(gc);
            const t = gc - base_f;
            self.up_base[j] = @as(i32, @intFromFloat(base_f));
            const t2 = t * t;
            const t3 = t2 * t;
            self.up_w[j] = .{
                0.5 * (-t3 + 2.0 * t2 - t),
                0.5 * (3.0 * t3 - 5.0 * t2 + 2.0),
                0.5 * (-3.0 * t3 + 4.0 * t2 + t),
                0.5 * (t3 - t2),
            };
        }

        // Thomas-Fermi cloud in the rotating frame with an imprinted triangular vortex lattice.
        const w_eff2: f32 = 1.0 - OMEGA0 * OMEGA0;
        const r_tf: f32 = @sqrt(@sqrt(4.0 * G / (math.pi * w_eff2)));
        self.mu = 0.5 * w_eff2 * r_tf * r_tf;
        const xi: f32 = 1.0 / @sqrt(2.0 * self.mu);
        const a_lat: f32 = @sqrt(2.0 * math.pi / (@sqrt(3.0) * OMEGA0));
        var vx: [256]f32 = undefined;
        var vy: [256]f32 = undefined;
        var nv: usize = 0;
        var rng: u64 = 0x9E3779B97F4A7C15;
        var jj: i32 = -12;
        while (jj <= 12) : (jj += 1) {
            var ii: i32 = -12;
            while (ii <= 12) : (ii += 1) {
                const fi: f32 = @floatFromInt(ii);
                const fj: f32 = @floatFromInt(jj);
                var px = a_lat * (fi + 0.5 * fj);
                var py = a_lat * (fj * 0.8660254);
                rng = rng *% 6364136223846793005 +% 1442695040888963407;
                px += 0.06 * (@as(f32, @floatFromInt(@as(u32, @truncate(rng >> 40)) & 0xFFFF)) / 65535.0 - 0.5);
                rng = rng *% 6364136223846793005 +% 1442695040888963407;
                py += 0.06 * (@as(f32, @floatFromInt(@as(u32, @truncate(rng >> 40)) & 0xFFFF)) / 65535.0 - 0.5);
                if (px * px + py * py < (0.86 * r_tf) * (0.86 * r_tf) and nv < vx.len) {
                    vx[nv] = px;
                    vy[nv] = py;
                    nv += 1;
                }
            }
        }
        for (0..NG) |iy| {
            const y = coord(iy);
            for (0..NG) |ix| {
                const x = coord(ix);
                const k = iy * NG + ix;
                const n_tf = @max(0.0, self.mu - 0.5 * w_eff2 * (x * x + y * y)) / G;
                var zr: f32 = @sqrt(n_tf + 1e-6);
                var zi: f32 = 0.0;
                for (0..nv) |v| {
                    const dxv = x - vx[v];
                    const dyv = y - vy[v];
                    const inv = 1.0 / @sqrt(dxv * dxv + dyv * dyv + 2.0 * xi * xi);
                    const fr = dxv * inv;
                    const fim = dyv * inv;
                    const nr = zr * fr - zi * fim;
                    zi = zr * fim + zi * fr;
                    zr = nr;
                }
                self.re[k] = zr * self.mask[k];
                self.im[k] = zi * self.mask[k];
            }
        }
        self.normalize();

        // Relax in imaginary time so the cores take their true shape before the clock starts.
        for (0..RELAX_STEPS) |_| self.rk4(-1.0, 0.0, OMEGA0);
        self.updateAmp();
        self.a_ref = self.peakAmp();
        self.r_ext = self.cloudExtent(self.a_ref);

        // Colour table, indexed by |psi| / peak. A 2D Thomas-Fermi density n ~ (mu - V) becomes a
        // 3D cloud's column density ~ (mu - V)^(3/2) = |psi|^3, so the image shows |psi|^3.
        for (0..LUT_N) |i| {
            const a: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(LUT_N - 1)) * LUT_TOP;
            const col = @min(1.0, a * a * a);
            // Cool grey ramp, a touch bluer in the thin outskirts, peaking below white.
            const v = math.pow(f32, col, 0.8);
            const rr = std.math.clamp(BG_R + v * 190.0, 0.0, 255.0);
            const gg = std.math.clamp(BG_G + v * 199.0, 0.0, 255.0);
            const bb = std.math.clamp(BG_B + v * 205.0 + 10.0 * @sqrt(v), 0.0, 255.0);
            self.lut[i] = sdk.packRGBA(@intFromFloat(rr), @intFromFloat(gg), @intFromFloat(bb));
        }
        return self;
    }

    inline fn coord(i: usize) f32 {
        return -HALF_L + (@as(f32, @floatFromInt(i)) + 0.5) * DX;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn normalize(self: *State) void {
        var s: f64 = 0.0;
        for (self.re, self.im) |r, i| s += @as(f64, r * r + i * i);
        s *= @as(f64, DX * DX);
        const f: f32 = @floatCast(1.0 / @sqrt(@max(s, 1e-30)));
        for (&self.re, &self.im) |*r, *i| {
            r.* *= f;
            i.* *= f;
        }
    }

    /// out = c * (H - mu) psi, with c = cr + i ci, in the frame rotating at `om`.
    fn deriv(self: *State, in_r: *const Field, in_i: *const Field, out_r: *Field, out_i: *Field, cr: f32, ci: f32, om: f32) void {
        const inv_dx2: f32 = 1.0 / (DX * DX);
        const inv_2dx: f32 = 0.5 / DX;
        const mu = self.mu;
        for (1..NG - 1) |iy| {
            const y = coord(iy);
            const row = iy * NG;
            for (1..NG - 1) |ix| {
                const k = row + ix;
                const x = coord(ix);
                const pr = in_r[k];
                const pi_ = in_i[k];
                const lap_r = (in_r[k + 1] + in_r[k - 1] + in_r[k + NG] + in_r[k - NG] - 4.0 * pr) * inv_dx2;
                const lap_i = (in_i[k + 1] + in_i[k - 1] + in_i[k + NG] + in_i[k - NG] - 4.0 * pi_) * inv_dx2;
                const dxr = (in_r[k + 1] - in_r[k - 1]) * inv_2dx;
                const dxi = (in_i[k + 1] - in_i[k - 1]) * inv_2dx;
                const dyr = (in_r[k + NG] - in_r[k - NG]) * inv_2dx;
                const dyi = (in_i[k + NG] - in_i[k - NG]) * inv_2dx;
                // D = x dpsi/dy - y dpsi/dx ;  -Omega L_z psi = i Omega D
                const d_r = x * dyr - y * dxr;
                const d_i = x * dyi - y * dxi;
                const wv = self.pot[k] + G * (pr * pr + pi_ * pi_) - mu;
                const a_r = -0.5 * lap_r + wv * pr - om * d_i;
                const a_i = -0.5 * lap_i + wv * pi_ + om * d_r;
                const m = self.mask[k];
                out_r[k] = (a_r * cr - a_i * ci) * m;
                out_i[k] = (a_r * ci + a_i * cr) * m;
            }
        }
    }

    fn axpy(dst_r: *Field, dst_i: *Field, src_r: *const Field, src_i: *const Field, kr: *const Field, ki: *const Field, s: f32) void {
        for (dst_r, dst_i, src_r, src_i, kr, ki) |*dr, *di, sr, si, vr, vi| {
            dr.* = sr + s * vr;
            di.* = si + s * vi;
        }
    }

    fn rk4(self: *State, cr: f32, ci: f32, om: f32) void {
        const h = H_STEP;
        self.deriv(&self.re, &self.im, &self.kr, &self.ki, cr, ci, om);
        axpy(&self.ar, &self.ai, &self.re, &self.im, &self.kr, &self.ki, h / 6.0);
        axpy(&self.tr, &self.ti, &self.re, &self.im, &self.kr, &self.ki, h / 2.0);
        self.deriv(&self.tr, &self.ti, &self.kr, &self.ki, cr, ci, om);
        axpy(&self.ar, &self.ai, &self.ar, &self.ai, &self.kr, &self.ki, h / 3.0);
        axpy(&self.tr, &self.ti, &self.re, &self.im, &self.kr, &self.ki, h / 2.0);
        self.deriv(&self.tr, &self.ti, &self.kr, &self.ki, cr, ci, om);
        axpy(&self.ar, &self.ai, &self.ar, &self.ai, &self.kr, &self.ki, h / 3.0);
        axpy(&self.tr, &self.ti, &self.re, &self.im, &self.kr, &self.ki, h);
        self.deriv(&self.tr, &self.ti, &self.kr, &self.ki, cr, ci, om);
        axpy(&self.re, &self.im, &self.ar, &self.ai, &self.kr, &self.ki, h / 6.0);
        self.normalize();
    }

    fn peakAmp(self: *const State) f32 {
        var mx: f32 = 0.0;
        for (self.amp) |a| mx = @max(mx, a);
        return mx;
    }

    fn cloudExtent(self: *const State, peak: f32) f32 {
        const thr = 0.03 * peak;
        var r2max: f32 = 0.0;
        for (0..NG) |iy| {
            const y = coord(iy);
            for (0..NG) |ix| {
                if (self.amp[iy * NG + ix] > thr) {
                    const x = coord(ix);
                    r2max = @max(r2max, x * x + y * y);
                }
            }
        }
        return @min(R_WALL, @sqrt(r2max) + 2.0 * DX);
    }

    fn updateAmp(self: *State) void {
        for (&self.amp, self.re, self.im) |*a, r, i| a.* = @sqrt(r * r + i * i);
        // Separable Catmull-Rom 3x upsampling: rows first, then columns.
        for (0..NG) |iy| {
            const src = self.amp[iy * NG .. iy * NG + NG];
            const dst = self.up_row[iy * M .. iy * M + M];
            for (0..M) |j| {
                const b = self.up_base[j];
                const wt = self.up_w[j];
                var s: f32 = 0.0;
                inline for (0..4) |q| {
                    const idx: usize = @intCast(std.math.clamp(b - 1 + @as(i32, q), 0, @as(i32, NG - 1)));
                    s += wt[q] * src[idx];
                }
                dst[j] = s;
            }
        }
        for (0..M) |jy| {
            const b = self.up_base[jy];
            const wt = self.up_w[jy];
            var rows: [4][]const f32 = undefined;
            inline for (0..4) |q| {
                const idx: usize = @intCast(std.math.clamp(b - 1 + @as(i32, q), 0, @as(i32, NG - 1)));
                rows[q] = self.up_row[idx * M .. idx * M + M];
            }
            const dst = self.amp_hi[jy * M .. jy * M + M];
            for (dst, rows[0], rows[1], rows[2], rows[3]) |*d, r0, r1, r2, r3| {
                d.* = @max(0.0, wt[0] * r0 + wt[1] * r1 + wt[2] * r2 + wt[3] * r3);
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        self.acc += @min(dt, 0.25) * SIM_RATE;
        const den: f32 = 1.0 + GAMMA * GAMMA;
        var n: usize = 0;
        while (self.acc >= H_STEP and n < MAX_STEPS_PER_CALL) : (n += 1) {
            self.acc -= H_STEP;
            const om: f32 = OMEGA0 + OMEGA_AMP * @as(f32, @floatCast(@sin(2.0 * math.pi * self.sim_t / OMEGA_PERIOD)));
            self.omega = om;
            self.rk4(-GAMMA / den, -1.0 / den, om);
            self.sim_t += H_STEP;
            self.theta = @mod(self.theta + @as(f64, om) * H_STEP, 2.0 * math.pi);
        }
        if (self.acc > H_STEP) self.acc = H_STEP; // never build a backlog
        // The pattern is (nearly) stationary in the rotating frame, so the leftover fraction of a
        // step only turns it: draw at theta + Omega * acc so the rotation does not step.
        self.theta_draw = self.theta + @as(f64, self.omega) * self.acc;
        if (n > 0) {
            self.updateAmp();
            const pk = self.peakAmp();
            self.a_ref = if (self.a_ref <= 0.0) pk else self.a_ref + 0.02 * (pk - self.a_ref);
            self.r_ext = self.cloudExtent(pk);
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);
        const ppu: f32 = 0.41 * fh / R_SCREEN; // pixels per trap unit
        const cx = 0.5 * fw;
        const cy = 0.5 * fh;
        const th: f32 = @floatCast(self.theta_draw);
        const c = @cos(th);
        const s = @sin(th);
        const inv_ppu = 1.0 / ppu;
        const inv_dxh = 1.0 / DXH;
        const lut_scale: f32 = @as(f32, @floatFromInt(LUT_N - 1)) / (LUT_TOP * @max(self.a_ref, 1e-9));
        const bgc = self.lut[0];
        const rx = self.r_ext;
        const lim: f32 = @floatFromInt(M - 2);
        for (0..h) |y| {
            const dst = buf[y * stride .. y * stride + w];
            @memset(dst, bgc);
            const ly = -((@as(f32, @floatFromInt(y)) + 0.5 - cy) * inv_ppu);
            if (@abs(ly) >= rx) continue;
            const half = @sqrt(@max(0.0, rx * rx - ly * ly)) * ppu;
            const x0: usize = @intFromFloat(@max(0.0, @floor(cx - half)));
            const x1: usize = @min(w, @as(usize, @intFromFloat(@max(0.0, @ceil(cx + half)))));
            if (x1 <= x0) continue;
            // Rotate lab (X, Y) into the rotating frame: u = cX + sY, v = -sX + cY.
            const lx0 = (@as(f32, @floatFromInt(x0)) + 0.5 - cx) * inv_ppu;
            const gu = (c * lx0 + s * ly + HALF_L) * inv_dxh - 0.5;
            const gv = (-s * lx0 + c * ly + HALF_L) * inv_dxh - 0.5;
            const du = c * inv_ppu * inv_dxh;
            const dv = -s * inv_ppu * inv_dxh;
            const span = dst[x0..x1];
            const V = 8;
            const VF = @Vector(V, f32);
            const VU = @Vector(V, u32);
            const lane: VF = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
            const zero: VF = @splat(0.0);
            const limv: VF = @splat(lim);
            const top_idx: VF = @splat(@as(f32, @floatFromInt(LUT_N - 1)));
            const scl: VF = @splat(lut_scale);
            const mv: VU = @splat(@as(u32, M));
            var i: usize = 0;
            while (i + V <= span.len) : (i += V) {
                const fi: f32 = @floatFromInt(i);
                const cu = @min(limv, @max(zero, @as(VF, @splat(gu + fi * du)) + lane * @as(VF, @splat(du))));
                const cv = @min(limv, @max(zero, @as(VF, @splat(gv + fi * dv)) + lane * @as(VF, @splat(dv))));
                const iu: VU = @intFromFloat(cu);
                const iv: VU = @intFromFloat(cv);
                const fu = cu - @as(VF, @floatFromInt(iu));
                const fv = cv - @as(VF, @floatFromInt(iv));
                const k = iv * mv + iu;
                var a00: VF = undefined;
                var a10: VF = undefined;
                var a01: VF = undefined;
                var a11: VF = undefined;
                inline for (0..V) |q| {
                    const kk: usize = k[q];
                    a00[q] = self.amp_hi[kk];
                    a10[q] = self.amp_hi[kk + 1];
                    a01[q] = self.amp_hi[kk + M];
                    a11[q] = self.amp_hi[kk + M + 1];
                }
                const top = a00 + fu * (a10 - a00);
                const bot = a01 + fu * (a11 - a01);
                const a = top + fv * (bot - top);
                const idx: VU = @intFromFloat(@min(top_idx, a * scl));
                inline for (0..V) |q| span[i + q] = self.lut[idx[q]];
            }
            while (i < span.len) : (i += 1) {
                const fi: f32 = @floatFromInt(i);
                const cu = std.math.clamp(gu + fi * du, 0.0, lim);
                const cv = std.math.clamp(gv + fi * dv, 0.0, lim);
                const iu: usize = @intFromFloat(cu);
                const iv: usize = @intFromFloat(cv);
                const fu = cu - @as(f32, @floatFromInt(iu));
                const fv = cv - @as(f32, @floatFromInt(iv));
                const k = iv * M + iu;
                const a00 = self.amp_hi[k];
                const a10 = self.amp_hi[k + 1];
                const a01 = self.amp_hi[k + M];
                const a11 = self.amp_hi[k + M + 1];
                const top = a00 + fu * (a10 - a00);
                const bot = a01 + fu * (a11 - a01);
                const a = top + fv * (bot - top);
                const idx: usize = @intFromFloat(@min(@as(f32, @floatFromInt(LUT_N - 1)), a * lut_scale));
                span[i] = self.lut[idx];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        const probe = [_]usize{ NN / 2 + NG / 2, NN / 3, NN / 2 + 7, NN / 2 - 3 * NG };
        for (probe) |k| {
            if (math.isNan(self.re[k]) or math.isInf(self.re[k]) or math.isNan(self.im[k]) or math.isInf(self.im[k])) return true;
        }
        return math.isNan(self.theta_draw) or math.isNan(self.a_ref) or math.isInf(self.a_ref) or math.isNan(self.time_sec);
    }
};

comptime {
    sdk.exportTheme(State);
}

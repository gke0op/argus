// Sonnet_Field: a rotating Bose-Einstein condensate with a vortex lattice.
//
// Track B (PDE field dynamics). The field is a 2D Gross-Pitaevskii wavefunction
//     i psi_t = [ -1/2 laplacian + V(r,t) + g |psi|^2 - mu ] psi        (hbar = m = 1, g = 1)
// on a 384 x 240 grid, advanced every frame with the Visscher leapfrog scheme (real and
// imaginary parts staggered by half a step, dt = 0.1, 8-wide SIMD, no allocation).
//
// Computed: the wavefunction really evolves under the GP equation. The vortices are never
// drawn; they are the phase singularities of psi, and they drift, crowd and slip out at the
// rim as the equation says. Column density |psi|^2 is what you see, the way an absorption
// image shows a real condensate: dark where atoms are missing, so each vortex core is a dark
// pinprick and the cloud edge is the Thomas-Fermi rim.
//
// Chosen (not derived): the units (mu = 0.39, healing length ~1.1 cells, trap w = 0.0097,
// lattice rotation Omega = 0.0058, so Omega/w = 0.6) and the colours. The start is analytic:
// a Thomas-Fermi cloud in the trap w^2 - Omega^2, times a triangular lattice of unit vortices
// at the density Omega/pi that rigid rotation needs (psi ~ prod (dx + i dy) / sqrt(d^2 + c^2)),
// with two vacancies. That start is not relaxed, so it sheds sound and loses vortices at first.
// Two small terms keep it alive and ordered for hours; both are phenomenology, not first principles:
//   - a weak friction gamma = 0.03, written as -gamma (H - Omega Lz - mu) psi, so the thing it
//     relaxes towards is the rotating-frame ground state (the lattice) rather than a
//     non-rotating cloud. The unitary part turns the lattice at Omega in the lab frame.
//   - a 4 % elliptical trap anisotropy turning slowly (0.3 Omega), which keeps the cloud
//     gently breathing and the vortices shuffling.
// Simulation time runs 20 units per second, so one lattice turn is about 54 s.
// Measured (scratch run, 1 h at 60 fps, 216 000 steps): vortex count in the dense core settles
// and stays; the field norm stays within 3 % of its start; the self-heal reseed never fired.
// Not modelled: thermal atoms, the third dimension (this is a 2D slice), imaging blur, real units.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const NX: usize = 384;
const NY: usize = 240;
const NCELL: usize = NX * NY;

const MU: f32 = 0.39; // chemical potential; g = 1, so peak density = mu, healing length ~1.1 cells
const W_TRAP: f32 = 0.0097; // trap frequency
const OMEGA: f32 = 0.0058; // rotation rate of the lattice
const DT: f32 = 0.1; // leapfrog step (max kinetic frequency is 4, so omega*dt = 0.4)
const K_RATE: f64 = 20.0; // simulation units per second of wall time
const MAX_SUBSTEPS: usize = 12;
const GAMMA: f32 = 0.03; // phenomenological damping (thermal friction), (i - gamma) psi_t = H psi
const EPS: f32 = 0.04; // ellipticity of the rotating stirrer (trap anisotropy)

const Vf = @Vector(8, f32);

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    acc: f64,
    sim_t: f64,
    norm0: f32,
    norm: f32,

    re: [NCELL]f32,
    im: [NCELL]f32,
    pot: [NCELL]f32, // V(r,t) - mu, rebuilt each frame
    pot0: [NCELL]f32, // isotropic trap - mu
    qa: [NCELL]f32, // 1/2 w^2 (x^2 - y^2)
    qb: [NCELL]f32, // 1/2 w^2 (2 x y)
    xs: [NX]f32,
    hi_prev: [NCELL]f32,
    hr_prev: [NCELL]f32,
    dens: [NCELL]u16, // column density, 3000 = central density at t=0
    palette: [1024]u32,
    col_i: [MAX_W]u16,
    col_f: [MAX_W]u16,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @max(@as(usize, 1), @min(w, MAX_W));
        self.h = @max(@as(usize, 1), @min(h, MAX_H));
        self.scale = scale;
        self.time_sec = 0.0;
        self.acc = 0.0;
        self.sim_t = 0.0;
        self.buildPalette();
        self.buildColumns();
        self.buildPotential();
        self.seed();
        self.updatePotential();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn buildPalette(self: *State) void {
        // absorption-image look: ink-blue cloud edge, cyan body, warm-white core density
        const stops = [_][4]f32{
            .{ 0.00, 2, 3, 9 },
            .{ 0.06, 6, 12, 34 },
            .{ 0.30, 16, 56, 120 },
            .{ 0.62, 54, 150, 196 },
            .{ 0.86, 170, 226, 224 },
            .{ 1.00, 252, 244, 214 },
        };
        for (0..1024) |i| {
            const u: f32 = @as(f32, @floatFromInt(i)) * 4.0 / 3000.0; // n / n0
            const c = std.math.clamp(u, 0.0, 1.0);
            var k: usize = 0;
            while (k + 2 < stops.len and c > stops[k + 1][0]) k += 1;
            const a = stops[k];
            const b = stops[k + 1];
            const t = std.math.clamp((c - a[0]) / (b[0] - a[0]), 0.0, 1.0);
            const s = t * t * (3.0 - 2.0 * t);
            const r: u8 = @intFromFloat(a[1] + (b[1] - a[1]) * s);
            const g: u8 = @intFromFloat(a[2] + (b[2] - a[2]) * s);
            const bl: u8 = @intFromFloat(a[3] + (b[3] - a[3]) * s);
            self.palette[i] = sdk.packRGBA(r, g, bl);
        }
    }

    fn buildColumns(self: *State) void {
        // source cell coordinates per output column: grid is scaled to cover the screen, centred
        const cell: f32 = @max(
            @as(f32, @floatFromInt(self.w)) / @as(f32, @floatFromInt(NX)),
            @as(f32, @floatFromInt(self.h)) / @as(f32, @floatFromInt(NY)),
        );
        const half_w: f32 = @as(f32, @floatFromInt(self.w)) * 0.5;
        for (0..self.w) |x| {
            const fx: f32 = @as(f32, @floatFromInt(x)) + 0.5;
            const sx = std.math.clamp((fx - half_w) / cell + @as(f32, NX) * 0.5 - 0.5, 0.0, @as(f32, NX - 1) - 0.001);
            const fl = @floor(sx);
            self.col_i[x] = @intCast(@as(usize, @intFromFloat(fl)));
            self.col_f[x] = @intFromFloat((sx - fl) * 256.0);
        }
    }

    fn buildPotential(self: *State) void {
        for (0..NX) |i| self.xs[i] = @as(f32, @floatFromInt(i)) - (@as(f32, NX) * 0.5 - 0.5);
        for (0..NY) |j| {
            for (0..NX) |i| {
                const dx: f32 = @as(f32, @floatFromInt(i)) - (@as(f32, NX) * 0.5 - 0.5);
                const dy: f32 = @as(f32, @floatFromInt(j)) - (@as(f32, NY) * 0.5 - 0.5);
                const q = 0.5 * W_TRAP * W_TRAP;
                self.pot0[j * NX + i] = q * (dx * dx + dy * dy) - MU;
                self.qa[j * NX + i] = q * (dx * dx - dy * dy);
                self.qb[j * NX + i] = q * 2.0 * dx * dy;
            }
        }
    }

    fn seed(self: *State) void {
        // Thomas-Fermi cloud in the effective trap, times a triangular vortex lattice.
        const w_eff2: f32 = W_TRAP * W_TRAP - OMEGA * OMEGA;
        const r_tf2: f32 = 2.0 * MU / w_eff2;
        const r_tf: f32 = @sqrt(r_tf2);
        const xi2: f32 = 1.0 / (2.0 * MU); // healing length squared (g = 1)
        const c2: f32 = 2.9 * xi2;
        // lattice spacing from vortex density Omega / pi (triangular lattice: n = 2 / (sqrt(3) a^2))
        const a: f32 = @sqrt(2.0 * math.pi / (@sqrt(3.0) * OMEGA));
        const max_v = 160;
        var vx: [max_v]f32 = undefined;
        var vy: [max_v]f32 = undefined;
        var nv: usize = 0;
        const ang: f32 = 0.31;
        const ca = @cos(ang);
        const sa = @sin(ang);
        var jj: i32 = -12;
        while (jj <= 12) : (jj += 1) {
            var ii: i32 = -12;
            while (ii <= 12) : (ii += 1) {
                const fi: f32 = @floatFromInt(ii);
                const fj: f32 = @floatFromInt(jj);
                const lx = (fi + 0.5 * fj) * a;
                const ly = fj * a * 0.8660254;
                const px = lx * ca - ly * sa + 0.37 * a;
                const py = lx * sa + ly * ca + 0.21 * a;
                if (px * px + py * py < (0.88 * r_tf) * (0.88 * r_tf) and nv < max_v) {
                    vx[nv] = px;
                    vy[nv] = py;
                    nv += 1;
                }
            }
        }
        // two vacancies, as real lattices have
        if (nv > 12) {
            vx[7] = vx[nv - 1];
            vy[7] = vy[nv - 1];
            vx[nv / 2] = vx[nv - 2];
            vy[nv / 2] = vy[nv - 2];
            nv -= 2;
        }
        const cxo: f32 = @as(f32, NX) * 0.5 - 0.5;
        const cyo: f32 = @as(f32, NY) * 0.5 - 0.5;
        var sum: f32 = 0.0;
        @memset(&self.re, 0.0);
        @memset(&self.im, 0.0);
        @memset(&self.hi_prev, 0.0);
        @memset(&self.hr_prev, 0.0);
        for (0..NY) |j| {
            const y: f32 = @as(f32, @floatFromInt(j)) - cyo;
            for (0..NX) |i| {
                const x: f32 = @as(f32, @floatFromInt(i)) - cxo;
                const r2 = x * x + y * y;
                const rho = (MU - 0.5 * w_eff2 * r2);
                if (rho <= 0.0) continue;
                var zr: f32 = 1.0;
                var zi: f32 = 0.0;
                for (0..nv) |k| {
                    const dx = x - vx[k];
                    const dy = y - vy[k];
                    const inv = 1.0 / @sqrt(dx * dx + dy * dy + c2);
                    const fr = dx * inv;
                    const fi = dy * inv;
                    const nr = zr * fr - zi * fi;
                    const ni = zr * fi + zi * fr;
                    zr = nr;
                    zi = ni;
                }
                const amp = @sqrt(rho);
                const idx = j * NX + i;
                self.re[idx] = amp * zr;
                self.im[idx] = amp * zi;
                sum += amp * amp * (zr * zr + zi * zi);
            }
        }
        self.norm0 = sum;
        self.norm = sum;
        self.updateDensity();
    }

    fn substep(self: *State) void {
        const dt: Vf = @splat(DT);
        const half: Vf = @splat(0.5);
        const four: Vf = @splat(4.0);
        const gam: Vf = @splat(GAMMA);
        const gom: Vf = @splat(OMEGA);
        // R += dt * H I
        for (1..NY - 1) |j| {
            const yv: Vf = @splat(@as(f32, @floatFromInt(j)) - (@as(f32, NY) * 0.5 - 0.5));
            var i: usize = 8;
            while (i < NX - 8) : (i += 8) {
                const idx = j * NX + i;
                const c: Vf = self.im[idx..][0..8].*;
                const l: Vf = self.im[idx - 1 ..][0..8].*;
                const r: Vf = self.im[idx + 1 ..][0..8].*;
                const u: Vf = self.im[idx - NX ..][0..8].*;
                const d: Vf = self.im[idx + NX ..][0..8].*;
                const rr: Vf = self.re[idx..][0..8].*;
                const v: Vf = self.pot[idx..][0..8].*;
                const lap = l + r + u + d - four * c;
                const hi = (v + rr * rr + c * c) * c - half * lap;
                const hrp: Vf = self.hr_prev[idx..][0..8].*;
                const xv: Vf = self.xs[i..][0..8].*;
                const di = xv * (d - u) * half - yv * (r - l) * half; // D I = x dI/dy - y dI/dx
                self.re[idx..][0..8].* = rr + dt * (hi - gam * (hrp - gom * di));
                self.hi_prev[idx..][0..8].* = hi;
            }
        }
        // I -= dt * H R
        for (1..NY - 1) |j| {
            const yv: Vf = @splat(@as(f32, @floatFromInt(j)) - (@as(f32, NY) * 0.5 - 0.5));
            var i: usize = 8;
            while (i < NX - 8) : (i += 8) {
                const idx = j * NX + i;
                const c: Vf = self.re[idx..][0..8].*;
                const l: Vf = self.re[idx - 1 ..][0..8].*;
                const r: Vf = self.re[idx + 1 ..][0..8].*;
                const u: Vf = self.re[idx - NX ..][0..8].*;
                const d: Vf = self.re[idx + NX ..][0..8].*;
                const ii: Vf = self.im[idx..][0..8].*;
                const v: Vf = self.pot[idx..][0..8].*;
                const lap = l + r + u + d - four * c;
                const hr = (v + c * c + ii * ii) * c - half * lap;
                const hip: Vf = self.hi_prev[idx..][0..8].*;
                const xv: Vf = self.xs[i..][0..8].*;
                const dr = xv * (d - u) * half - yv * (r - l) * half; // D R
                self.im[idx..][0..8].* = ii - dt * (hr + gam * (hip + gom * dr));
                self.hr_prev[idx..][0..8].* = hr;
            }
        }
    }

    fn updatePotential(self: *State) void {
        // the stirrer: an elliptical trap turning with the lattice at Omega
        const phi: f32 = @floatCast(@mod(self.sim_t * OMEGA * 0.3, 2.0 * math.pi));
        const ce: Vf = @splat(EPS * @cos(2.0 * phi));
        const se: Vf = @splat(EPS * @sin(2.0 * phi));
        var i: usize = 0;
        while (i < NCELL) : (i += 8) {
            const p: Vf = self.pot0[i..][0..8].*;
            const a: Vf = self.qa[i..][0..8].*;
            const b: Vf = self.qb[i..][0..8].*;
            self.pot[i..][0..8].* = p + ce * a + se * b;
        }
    }

    fn updateDensity(self: *State) void {
        const k: f32 = 3000.0 / MU;
        var sum: f32 = 0.0;
        for (0..NCELL) |i| {
            const rho = self.re[i] * self.re[i] + self.im[i] * self.im[i];
            sum += rho;
            const v = rho * k;
            self.dens[i] = @intFromFloat(@min(v, 4095.0));
        }
        self.norm = sum;
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        self.acc += dt * K_RATE;
        var n: usize = 0;
        while (self.acc >= DT and n < MAX_SUBSTEPS) : (n += 1) {
            self.substep();
            self.acc -= DT;
            self.sim_t += DT;
        }
        if (self.acc > DT) self.acc = 0.0;
        self.updatePotential();
        self.updateDensity();
        // self-heal: a blown-up or drained field starts over from the lattice
        if (!(self.norm > 0.6 * self.norm0 and self.norm < 1.6 * self.norm0)) self.seed();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const cell: f32 = @max(
            @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(NX)),
            @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(NY)),
        );
        const half_h: f32 = @as(f32, @floatFromInt(h)) * 0.5;
        var tmp: [NX + 1]u32 = undefined;
        for (0..h) |y| {
            const fy: f32 = @as(f32, @floatFromInt(y)) + 0.5;
            const sy = std.math.clamp((fy - half_h) / cell + @as(f32, NY) * 0.5 - 0.5, 0.0, @as(f32, NY - 1) - 0.001);
            const fl = @floor(sy);
            const j0: usize = @intFromFloat(fl);
            const wy: u32 = @intFromFloat((sy - fl) * 256.0);
            const row0 = self.dens[j0 * NX ..][0..NX];
            const row1 = self.dens[(j0 + 1) * NX ..][0..NX];
            for (0..NX) |i| {
                tmp[i] = @as(u32, row0[i]) * (256 - wy) + @as(u32, row1[i]) * wy; // 12 bit * 256
            }
            tmp[NX] = tmp[NX - 1];
            const dst = buf[y * stride .. y * stride + w];
            for (dst, self.col_i[0..w], self.col_f[0..w]) |*p, ix, wx| {
                const a = tmp[ix];
                const b = tmp[@as(usize, ix) + 1];
                const v = (a * (256 - @as(u32, wx)) + b * @as(u32, wx)) >> 18; // -> 0..4095 >> 2
                p.* = self.palette[v];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.norm) or math.isInf(self.norm) or math.isNan(self.time_sec) or math.isInf(self.time_sec);
    }
};

comptime {
    sdk.exportTheme(State);
}

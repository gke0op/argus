// ============================================================================
// Fable_Field.zig — "Quantum Trap"  (ARGUS-BENCH Track B: Symplectic / PDE field)
//
// A single quantum wave packet in a two-dimensional harmonic trap, scattered by five
// repulsive Gaussian islands sitting on its classical orbit. The field is the
// time-dependent Schrödinger equation (hbar = m = 1, grid spacing dx = 1):
//
//     i d(psi)/dt = H psi,    H = -(1/2) laplacian + V(x, y)
//     V = (1/2) omega^2 r^2 + sum_k A_k exp(-|r - r_k|^2 / (2 s_k^2))
//
// In an isotropic harmonic trap every classical orbit is an ellipse centred on the trap, so
// the packet is launched from (a, 0) with momentum (0, omega b): it follows x = a cos(wt),
// y = b sin(wt), an ellipse that fills the screen (a = 0.40 * grid width, b = 0.40 * grid
// height, leaving 4.4 packet widths to the Dirichlet edge). The five islands sit on that ellipse. A coherent state of width sqrt(1/(2 omega))
// would stay Gaussian forever in the pure trap; the islands scatter it, and the grid's
// Laplacian dispersion (1 - cos k vs k^2/2) slowly disperses it, so the field keeps changing.
//
// Integrator: Visscher's real/imaginary leapfrog (P. B. Visscher, Computers in Physics
// 5, 596, 1991). Re(psi) lives on integer time levels, Im(psi) on half-integer ones:
//     R^{n+1}   = R^n       + dt * H I^{n+1/2}
//     I^{n+3/2} = I^{n+1/2} - dt * H R^{n+1}
// This is a symplectic (explicit, time-reversible) scheme that conserves a discrete norm
// exactly; it is stable for dt < 2 / (4 + Vmax) with the 5-point Laplacian at dx = 1.
// Here dt = 0.35 per substep (Vmax ~ 0.6 at the corners, so the bound is 0.43), 3 substeps
// per step() call, and the field is pre-evolved 2000 substeps in init() so the first frame
// already shows the packet after its first pass through an island. One classical orbit takes
// 2 pi / omega ~ 2700 time units: about 43 s at 60 FPS.
//
// Computed:  the field itself (every frame), the norm sum |psi|^2 (a conservation check
//            exposed through hasNaN), the potential, the coherent-state width sqrt(1/(2 omega)).
// Chosen:    omega = p0 / a with p0 = 0.6 rad/cell (the packet's peak momentum, reached at
//            the ends of the minor axis); island height 0.22 and width 0.085 * grid height (gentle
//            lensing rather than hard scattering);
//            the palette (phase -> a gold/cyan/blue/violet loop, |psi|^2 -> value with a
//            white lift at the cores); the background contour map of V, one line per 24
//            cells of equivalent trap radius sqrt(2V)/omega.
// Not modelled: spin, interactions (this is linear Schrödinger, not Gross-Pitaevskii),
//            anything beyond the grid: the trap keeps the packet far from the edges, which
//            are Dirichlet (psi = 0).
//
// Rendering: grid 640x400 (one cell per 3x3 Retina pixels), colour per cell from a 256x256
// lookup over (Re, Im) with square-root-compressed axes, then a separable 3x bilinear
// upsample: horizontal in step() into `hrows`, vertical in draw() as a packed-channel lerp.
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const UP: usize = 3; // pixels per grid cell, both axes
pub const MAX_GW: usize = MAX_W / UP; // 640
pub const MAX_GH: usize = MAX_H / UP; // 400
pub const MAX_CELLS: usize = MAX_GW * MAX_GH;
pub const LUT_N: usize = 256;

const DT_SUB: f32 = 0.35; // substep (grid time units); stability needs < 2 / (4 + Vmax)
const SUBSTEPS_PER_STEP: usize = 3;
const PRE_EVOLVE_SUBSTEPS: usize = 2000;
const P0: f32 = 0.6; // packet momentum, rad/cell (wavelength ~10 cells = 31 px)
const N_ISLANDS: usize = 5;

pub const State = struct {
    w: usize,
    h: usize,
    gw: usize,
    gh: usize,
    scale: f64,
    time_sec: f64,
    norm: f64, // sum |psi|^2 over the grid, refreshed every step()
    norm0: f64, // the same sum right after init(): the conservation reference

    re: [MAX_CELLS]f32,
    im: [MAX_CELLS]f32,
    /// dt * (2 + V): the diagonal of dt * H with the 5-point Laplacian at dx = 1.
    diag: [MAX_CELLS]f32,
    /// Static per-cell background: a dark map of the potential.
    bg: [MAX_CELLS]u32,
    /// Colour for (Re, Im) after sqrt-compression of each axis onto 0..255.
    lut: [LUT_N * LUT_N]u32,
    /// Horizontally upsampled cell rows (3 * gw pixels each), built in step().
    hrows: [MAX_GH * MAX_W]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.gw = @min((self.w + UP - 1) / UP, MAX_GW);
        self.gh = @min((self.h + UP - 1) / UP, MAX_GH);
        self.scale = scale;
        self.time_sec = 0.0;
        self.norm = 0.0;
        self.norm0 = 0.0;

        const gw = self.gw;
        const gh = self.gh;
        const fgw: f32 = @floatFromInt(gw);
        const fgh: f32 = @floatFromInt(gh);
        const cx = 0.5 * fgw;
        const cy = 0.5 * fgh;
        // Semi-axes: 0.40 of the grid, shrunk if needed so the launch point keeps 4.5
        // coherent widths from the Dirichlet edge (matters at the 320x200 watchdog size).
        var orbit_a = 0.40 * fgw;
        for (0..4) |_| {
            const s_est = @sqrt(orbit_a / (2.0 * P0)); // sigma = sqrt(1/(2 omega)), omega = P0/a
            orbit_a = @min(orbit_a, @max(0.5 * fgw - 4.5 * s_est, 0.1 * fgw));
        }
        const orbit_b = @min(0.40 * fgh, orbit_a * fgh / fgw);
        const omega = P0 / @max(orbit_a, 1.0);
        const contour_spacing: f32 = 24.0; // cells of equivalent trap radius per line
        const sigma = @sqrt(1.0 / (2.0 * omega)); // coherent-state width in this trap
        const island_a: f32 = 0.22;
        const island_s = 0.085 * fgh;

        // Potential, its diagonal term, and the background map.
        for (0..gh) |y| {
            const fy: f32 = @floatFromInt(y);
            for (0..gw) |x| {
                const fx: f32 = @floatFromInt(x);
                const dx = fx - cx;
                const dy = fy - cy;
                var v: f32 = 0.5 * omega * omega * (dx * dx + dy * dy);
                for (0..N_ISLANDS) |k| {
                    const ang = 2.0 * math.pi * @as(f32, @floatFromInt(k)) / @as(f32, N_ISLANDS) + 0.9;
                    const ix = cx + orbit_a * @cos(ang);
                    const iy = cy + orbit_b * @sin(ang);
                    const ex = fx - ix;
                    const ey = fy - iy;
                    const d2 = (ex * ex + ey * ey) / (2.0 * island_s * island_s);
                    v += island_a * @exp(-d2);
                }
                const i = y * gw + x;
                self.diag[i] = DT_SUB * (2.0 + v);
                // Background: a topographic map of V. The trap floor is the darkest thing in
                // view; the only linework is one contour per `contour_spacing` cells of
                // equivalent trap radius r_eq = sqrt(2V)/omega, which bulges around islands.
                const r_eq = @sqrt(@max(0.0, 2.0 * v)) / omega;
                const frac = r_eq / contour_spacing - @floor(r_eq / contour_spacing);
                const dline = (frac - 0.5) * contour_spacing; // cells from the nearest line
                const line = @exp(-dline * dline / (2.0 * 0.6 * 0.6));
                const bowl = math.clamp(1.0 - @exp(-v * 1.5), 0.0, 1.0);
                const t256: u32 = @intFromFloat(bowl * 256.0);
                const base = sdk.lerpRGB(sdk.packRGBA(3, 4, 9), sdk.packRGBA(9, 13, 28), t256);
                const ink: u8 = @intFromFloat(math.clamp(line, 0.0, 1.0) * 14.0);
                self.bg[i] = sdk.addRGB(base, sdk.packRGBA(ink / 2, ink, ink + ink / 2));
            }
        }

        // The packet: a coherent-state Gaussian at the end of the major axis, moving
        // tangentially with momentum omega * b (the classical ellipse x = a cos, y = b sin).
        const x0 = cx + orbit_a;
        const y0 = cy;
        const p_launch = omega * orbit_b;
        var norm: f64 = 0.0;
        for (0..gh) |y| {
            const fy: f32 = @floatFromInt(y);
            for (0..gw) |x| {
                const fx: f32 = @floatFromInt(x);
                const i = y * gw + x;
                const dx = fx - x0;
                const dy = fy - y0;
                const env = @exp(-(dx * dx + dy * dy) / (4.0 * sigma * sigma));
                const ph = p_launch * dy; // momentum along +y
                const r = env * @cos(ph);
                // Im lives half a step later: rotate its phase by the local energy * dt/2.
                const e = 0.5 * p_launch * p_launch + 0.5 * omega * omega * (dx * dx + dy * dy);
                const im = env * @sin(ph - e * DT_SUB * 0.5);
                self.re[i] = r;
                self.im[i] = im;
                norm += @as(f64, r * r + im * im);
            }
        }
        // Dirichlet edges: zero and never updated.
        for (0..gw) |x| {
            self.re[x] = 0.0;
            self.im[x] = 0.0;
            self.re[(gh - 1) * gw + x] = 0.0;
            self.im[(gh - 1) * gw + x] = 0.0;
        }
        for (0..gh) |y| {
            self.re[y * gw] = 0.0;
            self.im[y * gw] = 0.0;
            self.re[y * gw + gw - 1] = 0.0;
            self.im[y * gw + gw - 1] = 0.0;
        }
        norm = 0.0;
        for (0..gw * gh) |i| norm += @as(f64, self.re[i] * self.re[i] + self.im[i] * self.im[i]);

        // Colour lookup over (Re, Im): hue from the phase, value from |psi|^2.
        for (0..LUT_N) |iy| {
            const vi = decompress(iy);
            for (0..LUT_N) |ix| {
                const vr = decompress(ix);
                const a2 = vr * vr + vi * vi;
                const lum = 1.0 - @exp(-14.0 * a2);
                const phi = math.atan2(vi, vr);
                // A gold / pale cyan / blue / violet loop: warm at phase 0, cold at pi.
                var cr = 0.55 + 0.45 * @cos(phi);
                var cg = 0.55 + 0.30 * @cos(phi - 1.2);
                var cb = 0.70 + 0.30 * @cos(phi - 3.0);
                const lift = lum * lum * lum * 0.40;
                cr = cr * lum + lift;
                cg = cg * lum + lift;
                cb = cb * lum + lift;
                self.lut[iy * LUT_N + ix] = sdk.packRGBA(toByte(cr), toByte(cg), toByte(cb));
            }
        }

        // Pre-evolve so the first frame already carries the scattered field.
        for (0..PRE_EVOLVE_SUBSTEPS) |_| self.substep();
        self.norm0 = norm;
        self.refreshColours();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    /// Axis decompression for the LUT: index 0..255 -> value in [-1, 1], with
    /// sign(u) * u^2 so small amplitudes get more bins.
    inline fn decompress(idx: usize) f32 {
        const u = (@as(f32, @floatFromInt(idx)) - 127.5) / 127.5;
        return if (u < 0.0) -(u * u) else u * u;
    }

    inline fn toByte(v: f32) u8 {
        return @intFromFloat(math.clamp(v, 0.0, 1.0) * 255.0);
    }

    /// One Visscher substep: R += dt H I, then I -= dt H R.
    fn substep(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        if (gw < 3 or gh < 3) return;
        const hd: f32 = 0.5 * DT_SUB; // dt * (1/2) in front of the neighbour sum
        // R^{n+1} = R^n + dt * (-(1/2) lap I + V I) = R + diag * I - hd * (neighbour sum)
        for (1..gh - 1) |y| {
            const row = y * gw;
            const im_c = self.im[row + 1 .. row + gw - 1];
            const im_l = self.im[row .. row + gw - 2];
            const im_r = self.im[row + 2 .. row + gw];
            const im_u = self.im[row - gw + 1 .. row - gw + gw - 1];
            const im_d = self.im[row + gw + 1 .. row + gw + gw - 1];
            const dg = self.diag[row + 1 .. row + gw - 1];
            const re_c = self.re[row + 1 .. row + gw - 1];
            for (re_c, im_c, im_l, im_r, im_u, im_d, dg) |*r, c, l, rr, u, d, g| {
                r.* += g * c - hd * (l + rr + u + d);
            }
        }
        for (1..gh - 1) |y| {
            const row = y * gw;
            const re_c = self.re[row + 1 .. row + gw - 1];
            const re_l = self.re[row .. row + gw - 2];
            const re_r = self.re[row + 2 .. row + gw];
            const re_u = self.re[row - gw + 1 .. row - gw + gw - 1];
            const re_d = self.re[row + gw + 1 .. row + gw + gw - 1];
            const dg = self.diag[row + 1 .. row + gw - 1];
            const im_c = self.im[row + 1 .. row + gw - 1];
            for (im_c, re_c, re_l, re_r, re_u, re_d, dg) |*i, c, l, rr, u, d, g| {
                i.* -= g * c - hd * (l + rr + u + d);
            }
        }
    }

    /// Packed-channel lerp of two packRGBA pixels, t in [0, 256]. R and B share one
    /// multiply, G the other; the alpha byte is forced to 0xFF.
    inline fn lerpPacked(a: u32, b: u32, t: u32) u32 {
        const inv: u32 = 256 - t;
        const rb = (((a & 0x00FF00FF) * inv + (b & 0x00FF00FF) * t) >> 8) & 0x00FF00FF;
        const g = ((((a >> 8) & 0xFF) * inv + ((b >> 8) & 0xFF) * t) >> 8) & 0xFF;
        return 0xFF000000 | rb | (g << 8);
    }

    inline fn lutIndex(v: f32) usize {
        // sqrt-compress |v| (clamped to 1) onto 0..255 around the centre.
        const c = math.clamp(v, -1.0, 1.0);
        const s = @sqrt(@abs(c));
        const u = if (c < 0.0) -s else s;
        const idx: i32 = @intFromFloat(127.5 + u * 127.0);
        return @intCast(math.clamp(idx, 0, @as(i32, LUT_N - 1)));
    }

    /// Cell colours and the horizontal 3x upsample into `hrows`; also the norm.
    fn refreshColours(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        var norm: f64 = 0.0;
        var cells: [MAX_GW]u32 = undefined;
        for (0..gh) |y| {
            const row = y * gw;
            var acc: f32 = 0.0;
            for (0..gw) |x| {
                const r = self.re[row + x];
                const i = self.im[row + x];
                acc += r * r + i * i;
                const col = self.lut[lutIndex(i) * LUT_N + lutIndex(r)];
                cells[x] = sdk.addRGB(self.bg[row + x], col);
            }
            norm += @as(f64, acc);
            const out = self.hrows[y * MAX_W .. y * MAX_W + gw * UP];
            for (0..gw) |x| {
                const c = cells[x];
                const l = cells[if (x > 0) x - 1 else 0];
                const rr = cells[if (x + 1 < gw) x + 1 else gw - 1];
                out[x * UP] = lerpPacked(c, l, 85);
                out[x * UP + 1] = c;
                out[x * UP + 2] = lerpPacked(c, rr, 85);
            }
        }
        self.norm = norm;
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        for (0..SUBSTEPS_PER_STEP) |_| self.substep();
        self.refreshColours();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const gh = self.gh;
        for (0..self.h) |y| {
            const cy = @min(y / UP, gh - 1);
            const k = y % UP;
            const dst = buf[y * stride .. y * stride + w];
            const cur = self.hrows[cy * MAX_W .. cy * MAX_W + w];
            if (k == 1) {
                @memcpy(dst, cur);
            } else {
                const oy = if (k == 0) (if (cy > 0) cy - 1 else 0) else @min(cy + 1, gh - 1);
                const oth = self.hrows[oy * MAX_W .. oy * MAX_W + w];
                for (dst, cur, oth) |*d, a, b| d.* = lerpPacked(a, b, 85);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec) or
            math.isNan(self.norm) or math.isInf(self.norm);
    }
};

comptime {
    sdk.exportTheme(State);
}

// `zig test -O ReleaseFast themes/Fable_Field.zig`: the naive norm sum |R|^2 + |I|^2 is not
// the exactly conserved staggered norm of the Visscher scheme (that one pairs I at t +- dt/2),
// so it is expected to wobble by O(dt * E); it must not drift. 2000 pre-evolution substeps
// plus 100 step() calls (300 substeps) at the watchdog size must stay within 2% of the
// initial sum, and nothing may go non-finite.
test "Visscher leapfrog keeps the norm" {
    const alloc = std.testing.allocator;
    const st = try State.init(alloc, 320, 200, 1.0);
    defer st.deinit(alloc);
    const n0 = st.norm0;
    try std.testing.expect(n0 > 0.0);
    std.debug.print("norm0 {d:.6} after pre-evolve {d:.6} (rel {e:.3})\n", .{ n0, st.norm, (st.norm - n0) / n0 });
    try std.testing.expect(@abs(st.norm - n0) / n0 < 0.02);
    for (0..100) |_| st.step(0.008);
    std.debug.print("after 300 more substeps {d:.6} (rel {e:.3})\n", .{ st.norm, (st.norm - n0) / n0 });
    try std.testing.expect(!st.hasNaN());
    try std.testing.expect(@abs(st.norm - n0) / n0 < 0.02);
}

// ============================================================================
// Fable_Field.zig — ARGUS-BENCH Track B (Symplectic / PDE Field Dynamics)
//
// A rotating Bose–Einstein condensate: the 2D Gross–Pitaevskii equation
//
//     i ∂t ψ = [ -½ ∇² + V(r) + g |ψ|² − μ ] ψ ,      V(r) = ½ r²   (ħ = m = ω = 1)
//
// integrated in the lab frame on a 384×240 lattice (h = 1/16) with Visscher's
// staggered leapfrog: Re ψ lives on integer steps, Im ψ on half steps,
//
//     R^{n+1}   = R^n       + dt · H[ I^{n+½} ]
//     I^{n+3/2} = I^{n+½}   − dt · H[ R^{n+1} ]
//
// which is the symplectic (time-reversible, discrete-norm-conserving) scheme for
// Schrödinger-type equations, stable for dt · E_max < 2 with E_max ≈ 4/h². The
// nonlinear term is time-centred on each update (see halfStep); with it the total
// norm Σ|ψ|²h² drifts by −1.9e-4 over 1500 frames (12 trap periods / 2π), against
// −14% for the naive sampling. The trap carries a 5% static anisotropy
// V = ½[(1+ε)x² + (1−ε)y²], which torques the lattice so the long-run motion
// (quadrupole wobble, lattice shear, surface ripples) never settles.
//
// The initial state is the Thomas–Fermi profile of the frame rotating at Ω with
// an imprinted triangular Abrikosov lattice (Feynman density n_v = Ω/π, so the
// spacing is b = sqrt(2π / (√3 Ω))), each core carrying a 2π phase winding and the
// Padé core profile f(ρ) = ρ / sqrt(ρ² + 2), ρ = r/ξ. Because that state is the
// rotating-frame ground state, in the lab frame it rotates rigidly at Ω while the
// small mismatch of the ansatz excites breathing and Tkachenko (lattice shear)
// modes that ripple through the cloud. Subtracting μ from the Hamiltonian is a
// gauge choice that removes the global e^{-iμt} strobe, so the hue (phase) field
// shows only the real motion.
//
// Rendering: hue = arg ψ (cyclic two-tone palette), brightness = sqrt(|ψ|² / n0)
// with a soft knee near zero; a static Gaussian "thermal halo" sits behind the
// condensate (decoration, not evolved). The 384×240 colour field is bilinearly
// upsampled 5× to the framebuffer: the horizontal half in step() (per cell row),
// the vertical half in draw() as one SIMD packed-RGB lerp per output pixel. All
// transcendental work is per lattice cell, none per framebuffer pixel.
//
// Measured (M-series Mac, shared, harness 120 frames): ~1.67 ms/frame, Gold tier;
// sim ≈ 0.69 ms, shade ≈ 0.33 ms, horizontal pass ≈ 0.25 ms, draw ≈ 0.5 ms.
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

// ---- lattice ---------------------------------------------------------------
const UP: usize = 5; // framebuffer pixels per lattice cell (at 1920x1200)
const CW: usize = MAX_W / UP; // 384
const CH: usize = MAX_H / UP; // 240
const N: usize = CW * CH;

// ---- physics (ħ = m = ω = 1) -----------------------------------------------
const H: f32 = 0.0625; // lattice spacing: domain 24 × 15
const KIN: f32 = -0.5 / (H * H); // coefficient of the 5-point Laplacian in -½∇²
const OMEGA: f32 = 0.6; // lattice rotation rate (in units of the trap frequency)
const R_TF: f32 = 6.5; // Thomas–Fermi radius of the rotating cloud
const MU: f32 = R_TF * R_TF * (1.0 - OMEGA * OMEGA) * 0.5; // rotating-frame chemical potential
const G: f32 = 1.0; // interaction strength (sets the scale of ψ only)
const N0: f32 = MU / G; // peak density
const XI: f32 = 1.0 / @sqrt(2.0 * MU); // healing length (vortex core size)
const EPS: f32 = 0.05; // static trap anisotropy: V = ½[(1+ε)x² + (1−ε)y²] (torques the lattice)
const V_CLAMP: f32 = 40.0; // trap clamp far outside the cloud (keeps E_max small)
const SUBSTEPS: usize = 5; // 0.008 / 5 = 0.0016 < 2 / (4/h² + V_CLAMP) = 0.0019
const DT_MAX: f32 = 0.0017; // safety clamp on the sub-step (Visscher stability)
const MAX_VORT: usize = 64;

// ---- SIMD ------------------------------------------------------------------
const VL: usize = 8;
const Vf = @Vector(VL, f32);
const Vu = @Vector(VL, u32);

pub const State = struct {
    w: usize,
    h: usize,
    time_sec: f64,
    norm: f32, // Σ |ψ|² h² each frame (NaN sentinel + diagnostic)

    re: [N]f32, // Re ψ at integer steps
    im: [N]f32, // Im ψ at half steps
    pot: [N]f32, // V(r) − μ, clamped
    cells: [N]u32, // shaded lattice (packed RGBA)
    bg: [N]u32, // static vignette behind the cloud
    hrows: [CH * MAX_W]u32, // horizontally upsampled rows (built in step)
    xcell0: [MAX_W]u32, // output column -> lattice column
    xcell1: [MAX_W]u32, // and its right neighbour (clamped)
    xfrac: [MAX_W]u32, // fixed-point 0..255 horizontal weight
    palette: [256]u32, // cyclic phase palette
    tone: [1024]u32, // density -> brightness (fixed-point 0..256)

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        _ = scale;
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.time_sec = 0.0;
        self.norm = 0.0;

        // Cyclic cosine palette for the phase.
        for (0..256) |k| {
            const t: f32 = @as(f32, @floatFromInt(k)) / 256.0;
            const two_pi: f32 = 6.28318548;
            const r = 0.60 + 0.40 * @cos(two_pi * (t + 0.00));
            const g = 0.55 + 0.42 * @cos(two_pi * (t + 0.12));
            const b = 0.60 + 0.40 * @cos(two_pi * (t + 0.28));
            self.palette[k] = sdk.packRGBA(toByte(r), toByte(g), toByte(b));
        }

        // Tone curve: brightness = (n / n0)^0.5 with a soft knee below 6% of the peak
        // density, so the vacuum's numerical noise floor stays dark and vortex cores
        // stay crisp. 1024-entry table.
        for (0..1024) |k| {
            const x: f32 = @as(f32, @floatFromInt(k)) / 1023.0;
            const kx = math.clamp(x / 0.06, 0.0, 1.0);
            const knee = kx * kx * (3.0 - 2.0 * kx);
            self.tone[k] = @intFromFloat(@sqrt(x) * knee * 256.0);
        }

        // Horizontal resampling tables for this display width.
        for (0..MAX_W) |x| {
            if (x < self.w) {
                const sx = (x * CW * 256) / self.w;
                const cx: u32 = @intCast(@min(sx >> 8, CW - 1));
                self.xcell0[x] = cx;
                self.xcell1[x] = @min(cx + 1, @as(u32, CW - 1));
                self.xfrac[x] = @intCast(sx & 255);
            } else {
                self.xcell0[x] = 0;
                self.xcell1[x] = 0;
                self.xfrac[x] = 0;
            }
        }

        // Vortex sites: triangular lattice at the Feynman density n_v = Ω/π.
        var sites: [MAX_VORT][2]f32 = undefined;
        var nsites: usize = 0;
        const b_lat: f32 = @sqrt(2.0 * math.pi / (1.7320508 * OMEGA));
        const tilt: f32 = 0.35;
        const ct = @cos(tilt);
        const st = @sin(tilt);
        var ii: i32 = -8;
        while (ii <= 8) : (ii += 1) {
            var jj: i32 = -8;
            while (jj <= 8) : (jj += 1) {
                const fi: f32 = @floatFromInt(ii);
                const fj: f32 = @floatFromInt(jj);
                const px = b_lat * (fi + 0.5 * fj);
                const py = b_lat * (0.8660254 * fj);
                const rx = ct * px - st * py;
                const ry = st * px + ct * py;
                if (rx * rx + ry * ry < (R_TF - 0.5) * (R_TF - 0.5) and nsites < MAX_VORT) {
                    sites[nsites] = .{ rx, ry };
                    nsites += 1;
                }
            }
        }

        // Fields: Thomas–Fermi profile of the rotating frame with the lattice imprinted.
        const inv_xi2: f32 = 1.0 / (XI * XI);
        const half_eff: f32 = 0.5 * (1.0 - OMEGA * OMEGA);
        for (0..CH) |cy| {
            const yc = (@as(f32, @floatFromInt(cy)) + 0.5 - @as(f32, CH) * 0.5) * H;
            for (0..CW) |cx| {
                const i = cy * CW + cx;
                const xc = (@as(f32, @floatFromInt(cx)) + 0.5 - @as(f32, CW) * 0.5) * H;
                const r2 = xc * xc + yc * yc;
                const vtrap = 0.5 * ((1.0 + EPS) * xc * xc + (1.0 - EPS) * yc * yc);
                self.pot[i] = @min(vtrap, V_CLAMP) - MU;

                const ntf = @max(0.0, MU - half_eff * r2) / G;
                var amp: f32 = @sqrt(ntf);
                var phase: f32 = 0.0;
                for (sites[0..nsites]) |s| {
                    const dx = xc - s[0];
                    const dy = yc - s[1];
                    const rho2 = (dx * dx + dy * dy) * inv_xi2;
                    amp *= @sqrt(rho2 / (rho2 + 2.0));
                    phase += math.atan2(dy, dx);
                }
                const edge = cx == 0 or cy == 0 or cx == CW - 1 or cy == CH - 1;
                self.re[i] = if (edge) 0.0 else amp * @cos(phase);
                self.im[i] = if (edge) 0.0 else amp * @sin(phase);

                // Static finite-temperature thermal halo (Gaussian, wider than the
                // condensate) over a deep-space vignette. Decoration only: it is not
                // evolved, the condensate is.
                const halo = @exp(-r2 / (2.0 * 7.5 * 7.5));
                const vig = @max(0.0, 1.0 - @sqrt(r2) / 15.0);
                const hr = 6.0 + 34.0 * halo + 4.0 * vig;
                const hg = 6.0 + 26.0 * halo + 5.0 * vig;
                const hb = 12.0 + 58.0 * halo + 10.0 * vig;
                self.bg[i] = sdk.packRGBA(toByte(hr / 255.0), toByte(hg / 255.0), toByte(hb / 255.0));
            }
        }

        self.shade();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const dts: f32 = @min(@as(f32, @floatCast(dt)) / @as(f32, SUBSTEPS), DT_MAX);
        for (0..SUBSTEPS) |_| {
            halfStep(&self.re, &self.im, &self.pot, dts); // R += dt H[I]
            halfStep(&self.im, &self.re, &self.pot, -dts); // I -= dt H[R]
        }
        self.shade();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        for (0..h) |y| {
            const sy = (y * CH * 256) / h;
            const cy: usize = @min(sy >> 8, CH - 1);
            const cy1: usize = @min(cy + 1, CH - 1);
            const fy: u32 = @intCast(sy & 255);
            const dst = buf[y * stride .. y * stride + w];
            const row_a = self.hrows[cy * MAX_W .. cy * MAX_W + w];
            if (fy == 0 or cy1 == cy) {
                @memcpy(dst, row_a);
            } else {
                const row_b = self.hrows[cy1 * MAX_W .. cy1 * MAX_W + w];
                lerpRow(dst, row_a, row_b, fy);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.norm) or math.isInf(self.norm) or
            math.isNan(self.time_sec) or math.isInf(self.time_sec);
    }

    /// Lattice -> colour, then the horizontal half of the bilinear upsample.
    fn shade(self: *State) void {
        const inv_n0: f32 = 1.0 / N0;
        var norm: f32 = 0.0;
        for (0..N) |i| {
            const r = self.re[i];
            const m = self.im[i];
            const n = r * r + m * m;
            norm += n;
            const ti: usize = @intFromFloat(@min(1.0, n * inv_n0) * 1023.0);
            const s256 = self.tone[ti];
            const hue = hueIndex(m, r);
            self.cells[i] = sdk.addRGB(self.bg[i], sdk.scaleRGB(self.palette[hue], s256));
        }
        self.norm = norm * (H * H);

        const w = self.w;
        for (0..CH) |cy| {
            const row = self.cells[cy * CW .. cy * CW + CW];
            const out = self.hrows[cy * MAX_W .. cy * MAX_W + w];
            if (w == MAX_W) {
                // Native width: cell c covers pixels 5c..5c+4 with weights 0, 51, 102, 153, 204
                // (the same values the table path computes for w = 1920).
                for (0..CW) |c| {
                    const a = row[c];
                    const b = row[@min(c + 1, CW - 1)];
                    const a_rb = a & 0x00FF00FF;
                    const a_g = a & 0x0000FF00;
                    const b_rb = b & 0x00FF00FF;
                    const b_g = b & 0x0000FF00;
                    const o = out[c * UP ..][0..UP];
                    o[0] = a;
                    inline for (1..UP) |k| {
                        const t: u32 = (k * 256) / UP;
                        const inv: u32 = 256 - t;
                        o[k] = (((a_rb * inv + b_rb * t) >> 8) & 0x00FF00FF) |
                            (((a_g * inv + b_g * t) >> 8) & 0x0000FF00) | 0xFF000000;
                    }
                }
            } else {
                for (out, self.xcell0[0..w], self.xcell1[0..w], self.xfrac[0..w]) |*o, c0, c1, f| {
                    o.* = lerpPacked(row[c0], row[c1], f);
                }
            }
        }
    }
};

/// One Visscher half-update: dst += sdt · H[src], H = KIN·∇²₅ + (V − μ + g n), with the
/// density time-centred on the update (n = src² + dst_old·dst_new). Sampling n with both
/// components at their stored times instead makes the two half-updates see different
/// Hamiltonians and drains the norm (measured: −14% over 1500 frames; this form: −2e-4).
/// Boundary cells (Dirichlet ψ = 0) are never touched.
fn halfStep(dst: *[N]f32, src: *const [N]f32, pot: *const [N]f32, sdt: f32) void {
    const kin: Vf = @splat(KIN);
    const g: Vf = @splat(G);
    const four: Vf = @splat(4.0);
    const one: Vf = @splat(1.0);
    const vdt: Vf = @splat(sdt);
    var y: usize = 1;
    while (y < CH - 1) : (y += 1) {
        const base = y * CW;
        var x: usize = 1;
        while (x + VL <= CW - 1) : (x += VL) {
            const i = base + x;
            const sc: Vf = src[i..][0..VL].*;
            const sl: Vf = src[i - 1 ..][0..VL].*;
            const sr: Vf = src[i + 1 ..][0..VL].*;
            const su: Vf = src[i - CW ..][0..VL].*;
            const sd: Vf = src[i + CW ..][0..VL].*;
            const dc: Vf = dst[i..][0..VL].*;
            const u: Vf = pot[i..][0..VL].*;
            // Nonlinear term centred on the update: n = src² + dst_old·dst_new, which is
            // linear in dst_new:  dst_new·(1 − dt·g·dst_old·src) = dst_old + dt·H₀[src].
            // |dt·g·dst_old·src| ≤ dt·g·n0 ≈ 0.02, so 1/(1−ε) is its cubic series.
            const hs = kin * (sl + sr + su + sd - four * sc) + (u + g * (sc * sc)) * sc;
            const eps = vdt * g * dc * sc;
            const inv = one + eps * (one + eps * (one + eps));
            dst[i..][0..VL].* = (dc + vdt * hs) * inv;
        }
        while (x < CW - 1) : (x += 1) {
            const i = base + x;
            const sc = src[i];
            const dc = dst[i];
            const lap = src[i - 1] + src[i + 1] + src[i - CW] + src[i + CW] - 4.0 * sc;
            const hs = KIN * lap + (pot[i] + G * (sc * sc)) * sc;
            const eps = sdt * G * dc * sc;
            dst[i] = (dc + sdt * hs) * (1.0 + eps * (1.0 + eps * (1.0 + eps)));
        }
    }
}

/// arg(x + iy) mapped to a 0..255 palette index (polynomial atan, |err| < 1e-4 rad).
inline fn hueIndex(y: f32, x: f32) u32 {
    const ax = @abs(x);
    const ay = @abs(y);
    const mx = @max(ax, ay);
    if (mx < 1e-30) return 0;
    const a = @min(ax, ay) / mx;
    const s = a * a;
    var r = a * (0.99997726 + s * (-0.33262347 + s * (0.19354346 + s * (-0.11643287 + s * (0.05265332 - s * 0.01172120)))));
    if (ay > ax) r = 1.57079637 - r;
    if (x < 0.0) r = 3.14159274 - r;
    if (y < 0.0) r = -r;
    const t = r * (256.0 / 6.28318548) + 256.0; // (128, 384]
    const idx: u32 = @intFromFloat(t);
    return idx & 255;
}

inline fn toByte(v: f32) u8 {
    const c = math.clamp(v, 0.0, 1.0) * 255.0 + 0.5;
    return @intFromFloat(c);
}

/// Packed-RGB lerp with t in 0..255 (R and B share one multiply, G the other).
inline fn lerpPacked(a: u32, b: u32, t: u32) u32 {
    const inv: u32 = 256 - t;
    const rb = (((a & 0x00FF00FF) * inv + (b & 0x00FF00FF) * t) >> 8) & 0x00FF00FF;
    const g = (((a & 0x0000FF00) * inv + (b & 0x0000FF00) * t) >> 8) & 0x0000FF00;
    return rb | g | 0xFF000000;
}

/// dst = lerp(a, b, t) over a whole row, 8 pixels at a time.
fn lerpRow(dst: []u32, a: []const u32, b: []const u32, t: u32) void {
    const inv: u32 = 256 - t;
    const vt: Vu = @splat(t);
    const vinv: Vu = @splat(inv);
    const mrb: Vu = @splat(0x00FF00FF);
    const mg: Vu = @splat(0x0000FF00);
    const alpha: Vu = @splat(0xFF000000);
    const sh: @Vector(VL, u5) = @splat(8);
    var x: usize = 0;
    while (x + VL <= dst.len) : (x += VL) {
        const va: Vu = a[x..][0..VL].*;
        const vb: Vu = b[x..][0..VL].*;
        const rb = (((va & mrb) * vinv + (vb & mrb) * vt) >> sh) & mrb;
        const g = (((va & mg) * vinv + (vb & mg) * vt) >> sh) & mg;
        dst[x..][0..VL].* = rb | g | alpha;
    }
    while (x < dst.len) : (x += 1) {
        dst[x] = lerpPacked(a[x], b[x], t);
    }
}

comptime {
    sdk.exportTheme(State);
}

// @argus-theme: custom_shader
// ============================================================================
// OPUS BLACK HOLE // themes/Opus_Black_Hole.zig
//
// A spinning (Kerr) black hole with a thin accretion disk, rendered from the
// physics rather than tuned by eye.
//
// What is computed, not chosen:
//  * Light paths: exact Kerr null geodesics (Carter constants, Hamiltonian form,
//    RK4) traced backward from a pinhole camera for every pixel. Spin, frame
//    dragging and the D-shaped shadow come out of the equations.
//  * Disk: geometrically thin, optically thick, inner edge at the ISCO (exact
//    Bardeen-Press-Teukolsky formula), emitted flux from the Page-Thorne
//    integral evaluated numerically from Kerr circular-orbit E(r), L(r), Omega(r).
//  * Color: each point radiates as a blackbody at T(r) ~ F^(1/4). The observed
//    spectrum is exactly a blackbody at g*T, with g the full Kerr redshift
//    (gravitational + Doppler), so color AND brightness come from Planck's law
//    integrated against CIE 1931 color matching functions. Beaming is not
//    switched off: the approaching side is much brighter, as it would be.
//  * Light travel time: each pixel's pattern phase includes the photon's
//    coordinate travel time, so lensed images lag the direct one.
//
// What is chosen (stated honestly):
//  * Spin a = 0.94 M, inclination 80 deg (steeply tilted).
//  * Outer disk: no wall. Viscous spreading (Lynden-Bell & Pringle 1974) rolls the
//    surface density off as Sigma ~ (R_C/r) exp(-r/R_C); optical depth follows it, so
//    past ~15 M the cool gas turns translucent and light from behind (sky, the lensed
//    far side) is traced through it: I = B(T)(1 - e^-tau) + I_behind e^-tau. Turbulence
//    modulates the column density, so the edge frays into drifting wisps.
//    The scale R_C and normalisation TAU0 are choices; the falloff law is not.
//  * Peak disk temperature 6,500 K: a heavy supermassive black hole with a low
//    accretion rate (T_peak ~ (Mdot / M^2)^(1/4)). Hotter disks look bluer-white;
//    most of a 5,000 K disk is honestly a warm off-white, not orange.
//  * Time-lapse: one inner-disk orbit takes ~10 s on screen (in reality hours).
//  * Turbulence: emissivity fluctuations advected at the true Keplerian rate
//    and refreshed every few inner orbits; the amplitude is a modelling choice.
//  * Hot spots: plasma clumps on exact Kerr orbits (like Sgr A* flares). Each one
//    shows up in every lensed image at once, with its own light-travel lag.
//    Their count, size and brightness are choices; their motion is not.
//  * Sky: a procedural Milky Way (band, dust lanes, bulge) and stars placed
//    behind the hole and seen through the geodesics, so it bends into arcs and
//    an Einstein ring. Its brightness is a composite-exposure choice.
//  * Camera exposure + Reinhard tone mapping; faint stars for context.
//  Not modelled: limb darkening, color correction of disk atmospheres,
//  returning radiation, disk thickness.
//
// Contract: 1 allocation (one slab) at init, 0 after; no clocks or I/O.
// The geodesic work happens once in init; draw() is table lookups.
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const SPIN: f64 = 0.94;
pub const INCL: f64 = 80.0 * math.pi / 180.0;
pub const R_OUT: f64 = 48.0; // geometry only: tau(48 M) ~ 2e-3, the gas has already faded out
pub const R_C: f64 = 5.0; // M: exponential roll-off scale of the outer disk
pub const TAU0: f64 = 220.0; // tau = 1 near r = 20 M; opaque (tau > 15) inside ~10 M
const TAU_NOISE: f32 = 1.2; // turbulence modulates the column: tau * exp(TAU_NOISE * n), |n| <= 1
const TAU_THICK: f64 = 5.0; // fully opaque above this (leaks < 0.7%)
const TAU_BEHIND: f64 = TAU_THICK * @exp(@as(f64, TAU_NOISE)); // above this even thinned gas is opaque
const TAU_MIN: f64 = 0.01; // thinner than this (max opacity 3%, emission nil) the gas is left out
const EMIT_FLOOR: f64 = 3e-4; // display-linear (~1/255): gas that can't reach this even stirred is baked
const SPOT_RMAX: f64 = 12.0; // M: hot spots orbit inside this (r_in * 5.35 + width); never baked there
const EXPO_R: f64 = 24.0; // exposure is metered on the bright inner disk only
const EMIT_N: usize = 1024; // 1 - exp(-e^x) table over x = ln(tau) in [EMIT_X0, EMIT_X1]
const EMIT_X0: f32 = -7.0;
const EMIT_X1: f32 = 4.0;
pub const T_PEAK: f64 = 6_500.0;
const OBS_R: f64 = 1000.0;
// Common light-travel time from the hole to the camera (radial tortoise coordinate,
// r + 2 ln(r/2 - 1) ~ r + 2 ln(r/2)). Only delays relative to it are observable; left in,
// Omega(r) * 1000 M would wind the disk pattern ~0.5 rad per pixel radially and the
// footprint filter would (rightly) erase all turbulence and hot spots.
const T_REF: f64 = OBS_R + 2.0 * @log(OBS_R / 2.0);
const HALF_H: f64 = 15.5; // half the screen height, in units of M
const TIME_LAPSE: f64 = 10.0; // M of coordinate time per unit of Argus dt
const LIFE_M: f64 = 60.0; // turbulence generation lifetime, in M
const TURB: f32 = 0.4;
const EXPO_TARGET: f64 = 7.0; // 99th-percentile disk luminance maps here before tone mapping
const STAR_GAIN: f64 = 0.8;
const STAR_CELL: f64 = 8.0e-3; // star grid spacing on the sky, radians (resolution-independent)
const STAR_FLUX: f64 = 60.0; // intrinsic star brightness; lensing then dims or brightens each one
const SKY_GAIN: f64 = 0.010; // diffuse Milky Way surface brightness (linear, pre-encode)
const GAL_TILT: f64 = 25.0 * math.pi / 180.0; // band's tilt on screen
const NSPOT: usize = 6;
const SPOT_LIFE: f64 = 90.0; // M of time each hot spot lives
const SPOT_SIZE: f64 = 1.1; // M
const SPOT_AMP: f32 = 6.0; // peak emissivity boost (hotter gas: T rises as boost^(1/4))
const HALF_PI: f64 = math.pi / 2.0;
const K_NEAR: f64 = 0.08; // tuned against the Bardeen test: ~1e-5 M shadow-edge error
const MAX_STEPS: u32 = 40_000;

// ============================================================================ Kerr physics (M = 1)

pub fn horizon(a: f64) f64 {
    return 1.0 + @sqrt(1.0 - a * a);
}

/// Prograde innermost stable circular orbit (Bardeen, Press & Teukolsky 1972).
pub fn isco(a: f64) f64 {
    const z1 = 1.0 + math.cbrt(1.0 - a * a) * (math.cbrt(1.0 + a) + math.cbrt(1.0 - a));
    const z2 = @sqrt(3.0 * a * a + z1 * z1);
    return 3.0 + z2 - @sqrt((3.0 - z1) * (3.0 + z1 + 2.0 * z2));
}

/// Circular photon orbit radius (prograde or retrograde).
pub fn photonOrbit(a: f64, prograde: bool) f64 {
    const x = if (prograde) -a else a;
    return 2.0 * (1.0 + @cos(2.0 / 3.0 * math.acos(x)));
}

pub const Orbit = struct { E: f64, L: f64, om: f64, ut: f64 };

/// Prograde equatorial circular orbit: specific energy, angular momentum,
/// angular velocity and u^t (Bardeen, Press & Teukolsky 1972).
pub fn orbit(a: f64, r: f64) Orbit {
    const sr = @sqrt(r);
    const r32 = r * sr;
    const den = @sqrt(r32) * @sqrt(r32 - 3.0 * sr + 2.0 * a);
    return .{
        .E = (r32 - 2.0 * sr + a) / den,
        .L = (r * r - 2.0 * a * sr + a * a) / den,
        .om = 1.0 / (r32 + a),
        .ut = (r32 + a) / den,
    };
}

pub const PT_N: usize = 4096;

/// Page-Thorne (1974) flux, up to a constant, on a log grid r_k = r_in (r_max/r_in)^(k/(N-1)):
///   F = -Omega' / (r (E - Omega L)^2) * Integral_{r_in}^{r} (E - Omega L) L' dr
/// evaluated numerically from the exact circular-orbit functions (no closed form needed).
pub fn pageThorne(a: f64, r_in: f64, r_max: f64, out: *[PT_N]f64) void {
    const dl = @log(r_max / r_in) / @as(f64, @floatFromInt(PT_N - 1));
    var integ: f64 = 0.0;
    var prev: f64 = 0.0;
    for (0..PT_N) |k| {
        const r = r_in * @exp(dl * @as(f64, @floatFromInt(k)));
        const e = 1e-6;
        const o = orbit(a, r);
        const op = orbit(a, r * (1.0 + e));
        const om = orbit(a, r * (1.0 - e));
        const dL = (op.L - om.L) / (2.0 * r * e);
        const dOm = (op.om - om.om) / (2.0 * r * e);
        const emo = o.E - o.om * o.L;
        const g = emo * dL * r; // integrand in d(ln r)
        if (k > 0) integ += 0.5 * (g + prev) * dl;
        prev = g;
        out[k] = if (k == 0) 0.0 else -dOm / (emo * emo) * integ / r;
    }
}

/// Optical depth of the disk at r: proportional to the viscously spread surface density.
pub fn opticalDepth(r: f64) f64 {
    return TAU0 * (R_C / r) * @exp(-r / R_C);
}

// ---------------------------------------------------------------- geodesics

const V6 = @Vector(6, f64); // r, theta, phi, t, p_r, p_theta

/// Hamilton's equations for Kerr null geodesics with E = 1, L = photon angular
/// momentum (real, forward-in-time photon). r/theta dynamics are invariant under
/// the backward-tracing flip (E,L,p) -> (-E,-L,-p); phi and t are negated so the
/// ray is followed backward along the real photon's path.
fn rhs(a: f64, L: f64, y: V6) V6 {
    const r = y[0];
    const s0 = @sin(y[1]);
    const c = @cos(y[1]);
    const s = if (@abs(s0) < 1e-9) (if (s0 < 0) @as(f64, -1e-9) else 1e-9) else s0;
    const s2 = s * s;
    const a2 = a * a;
    const r2 = r * r;
    const sig = r2 + a2 * c * c;
    const del = r2 - 2.0 * r + a2;
    const P = r2 + a2 - a * L;
    const isig = 1.0 / sig;
    const idel = 1.0 / del;
    const pr = y[4];
    const dBdr = (2.0 * r - 2.0) * pr * pr - (4.0 * r * P * del - P * P * (2.0 * r - 2.0)) * idel * idel;
    const dBdth = (-2.0 * L * L / (s2 * s) + 2.0 * a2 * s) * c;
    return .{
        del * pr * isig,
        y[5] * isig,
        -(a * P * idel + L / s2 - a) * isig,
        -((r2 + a2) * P * idel + a * (L - a * s2)) * isig,
        -0.5 * dBdr * isig,
        -0.5 * dBdth * isig,
    };
}

fn rk4(a: f64, L: f64, y: V6, h: f64) V6 {
    return rk4k(a, L, y, h, rhs(a, L, y));
}

fn rk4k(a: f64, L: f64, y: V6, h: f64, k1: V6) V6 {
    const hv: V6 = @splat(h);
    const half: V6 = @splat(0.5 * h);
    const k2 = rhs(a, L, y + k1 * half);
    const k3 = rhs(a, L, y + k2 * half);
    const k4 = rhs(a, L, y + k3 * hv);
    const sixth: V6 = @splat(1.0 / 6.0);
    return y + hv * sixth * (k1 + (k2 + k3) * @as(V6, @splat(2.0)) + k4);
}

/// Step size: geometric in r far away, proportional to distance from the horizon near it,
/// and capped so theta and phi each move < 0.08 rad per step (rays skimming the spin axis).
fn stepSize(g: *const Geo, y: V6, d: V6) f64 {
    const r = y[0];
    var h: f64 = if (r > 200.0) 0.25 * r else if (r > 60.0) 0.1 * r else K_NEAR * @min(r, 4.0 * (r - g.rh));
    if (r < 200.0) {
        h = @min(h, 0.08 / @max(@abs(d[1]), 1e-12));
        h = @min(h, 0.08 / @max(@abs(d[2]), 1e-12));
        // Near the spin axis theta turns on a scale ~ sin(theta): resolve that bend.
        h = @min(h, (0.05 * @abs(@sin(y[1])) + 2e-4) / @max(@abs(d[1]), 1e-12));
    }
    return @max(h, 1e-5);
}

/// Re-solve p_r from the null condition (keeping its sign). Far from the hole the
/// orbit-defining constant K ~ 27 is 1e-5 of the r^2-sized terms, so unconstrained
/// integration errors would silently move the photon onto a different orbit.
fn project(a: f64, L: f64, y: V6) V6 {
    const s = @sin(y[1]);
    const s2 = @max(s * s, 1e-18);
    const r = y[0];
    const del = r * r - 2.0 * r + a * a;
    const P = r * r + a * a - a * L;
    const X = P * P / del - y[5] * y[5] - (L - a * s2) * (L - a * s2) / s2;
    // Near a radial turning point (X -> 0) the raw Hamiltonian flow is smooth and accurate;
    // clamping there would stall the ray for a step. Only project where |p_r| is order unity.
    if (X < 0.05 * P * P / del) return y;
    const mag = @sqrt(X / del);
    var out = y;
    out[4] = if (y[4] < 0.0) -mag else mag;
    return out;
}

pub const Geo = struct {
    a: f64,
    incl: f64,
    sin_i: f64,
    cos_i: f64,
    rh: f64,
    r_in: f64,
    r_out: f64,

    pub fn init(a: f64, incl: f64, r_out: f64) Geo {
        return .{ .a = a, .incl = incl, .sin_i = @sin(incl), .cos_i = @cos(incl), .rh = horizon(a), .r_in = isco(a), .r_out = r_out };
    }
};

pub const Kind = enum(u8) { sky, disk, hole };

pub const Hit = struct {
    kind: Kind = .hole,
    n: u8 = 0,
    r: f64 = 0,
    ph: f64 = 0,
    t: f64 = 0,
    dir: [3]f64 = .{ 0, 0, 0 },
    steps: u32 = 0,
};

/// Initial state for the backward ray through screen point (alpha, beta), camera at
/// r = OBS_R, theta = incl, phi = 0. Up on screen = decreasing theta.
pub fn initialState(g: *const Geo, alpha: f64, beta: f64) struct { y: V6, L: f64 } {
    const a = g.a;
    const L = -alpha * g.sin_i;
    const r = OBS_R;
    const s2 = g.sin_i * g.sin_i;
    const del = r * r - 2.0 * r + a * a;
    const P = r * r + a * a - a * L;
    const f = (L - a * s2) * (L - a * s2) / s2;
    const pth = -beta;
    const X = P * P / del - pth * pth - f;
    const pr = -@sqrt(@max(X, 0.0) / del);
    return .{ .y = .{ r, g.incl, 0.0, 0.0, pr, pth }, .L = L };
}

pub const Ray = struct { y: V6, L: f64, n: u8 = 0, steps: u32 = 0 };

pub fn startRay(g: *const Geo, alpha: f64, beta: f64) Ray {
    const st = initialState(g, alpha, beta);
    return .{ .y = st.y, .L = st.L };
}

pub fn traceRay(g: *const Geo, alpha: f64, beta: f64, with_disk: bool) Hit {
    var ray = startRay(g, alpha, beta);
    return traceNext(g, &ray, with_disk);
}

/// Follow the ray to the next thing it meets. On a disk hit the state is left just past
/// the crossing, so calling again finds what lies behind translucent gas.
pub fn traceNext(g: *const Geo, ray: *Ray, with_disk: bool) Hit {
    var y = ray.y;
    const L = ray.L;
    var n = ray.n;
    var steps = ray.steps;
    while (steps < MAX_STEPS) : (steps += 1) {
        const r = y[0];
        if (r < g.rh + 0.02) return .{ .kind = .hole, .steps = steps };
        if (y[4] > 0.0 and r > 2.0e4) {
            const d = rhs(g.a, L, y);
            const s = @sin(y[1]);
            const c = @cos(y[1]);
            const sp = @sin(y[2]);
            const cp = @cos(y[2]);
            const vr = d[0];
            const vt = r * d[1];
            const vp = r * s * d[2];
            var v = [3]f64{
                vr * s * cp + vt * c * cp - vp * sp,
                vr * s * sp + vt * c * sp + vp * cp,
                vr * c - vt * s,
            };
            const nv = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
            for (&v) |*x| x.* /= nv;
            return .{ .kind = .sky, .dir = v, .steps = steps };
        }
        const k1 = rhs(g.a, L, y);
        const h = stepSize(g, y, k1);
        const prev = y;
        y = project(g.a, L, rk4k(g.a, L, y, h, k1));
        if (!std.math.isFinite(y[0]) or !std.math.isFinite(y[1])) return .{ .kind = .hole, .steps = steps };
        // Equator crossing via the sign of cos(theta): robust if theta wraps through a pole.
        const e0 = @cos(prev[1]);
        const e1 = @cos(y[1]);
        if ((e0 < 0.0) != (e1 < 0.0)) {
            n +|= 1;
            // Land exactly on the equator: secant iterations on a partial RK4 step from prev.
            var lo: f64 = 0.0;
            var hi: f64 = h;
            var flo = e0;
            var fhi = e1;
            var yc = y;
            for (0..4) |_| {
                const hm = lo + (hi - lo) * flo / (flo - fhi);
                yc = rk4k(g.a, L, prev, hm, k1);
                const fm = @cos(yc[1]);
                if ((fm < 0.0) == (flo < 0.0)) {
                    lo = hm;
                    flo = fm;
                } else {
                    hi = hm;
                    fhi = fm;
                }
                if (@abs(fm) < 1e-12) break;
            }
            const rc = yc[0];
            if (with_disk and rc >= g.r_in and rc <= g.r_out) {
                ray.* = .{ .y = y, .L = L, .n = n, .steps = steps + 1 };
                return .{ .kind = .disk, .n = n, .r = rc, .ph = yc[2], .t = yc[3], .steps = steps };
            }
        }
    }
    return .{ .kind = .hole, .steps = steps };
}

/// Kerr redshift g = E_obs / E_emit for a photon (E = 1, angular momentum L)
/// emitted by gas on a prograde circular orbit at r.
pub fn redshift(a: f64, r: f64, L: f64) f64 {
    const o = orbit(a, r);
    return 1.0 / (o.ut * (1.0 - o.om * L));
}

// ---------------------------------------------------------------- color science

pub const BB_N: usize = 1024;
pub const BB_TMIN: f64 = 300.0;
pub const BB_TMAX: f64 = 80_000.0;

fn lobe(l: f64, mu: f64, s1: f64, s2: f64) f64 {
    const t = (l - mu) / (if (l < mu) s1 else s2);
    return @exp(-0.5 * t * t);
}

/// CIE 1931 2-degree observer, multi-lobe Gaussian fit (Wyman, Sloan & Shirley 2013).
fn cmf(l: f64) [3]f64 {
    return .{
        1.056 * lobe(l, 599.8, 37.9, 31.0) + 0.362 * lobe(l, 442.0, 16.0, 26.7) - 0.065 * lobe(l, 501.1, 20.4, 26.2),
        0.821 * lobe(l, 568.8, 46.9, 40.5) + 0.286 * lobe(l, 530.9, 16.3, 31.1),
        1.217 * lobe(l, 437.0, 11.8, 36.0) + 0.681 * lobe(l, 459.0, 26.0, 13.8),
    };
}

/// Linear sRGB of a blackbody at T (arbitrary but consistent absolute scale).
pub fn blackbodyRGB(T: f64) [3]f64 {
    var xyz = [3]f64{ 0, 0, 0 };
    var l: f64 = 380.0;
    while (l <= 780.0) : (l += 5.0) {
        const lum = l * 1e-3; // micrometres
        const planck = 1.0 / (lum * lum * lum * lum * lum * std.math.expm1(14387.77 / (lum * T)));
        const c = cmf(l);
        for (0..3) |i| xyz[i] += planck * c[i];
    }
    return .{
        @max(0.0, 3.2406 * xyz[0] - 1.5372 * xyz[1] - 0.4986 * xyz[2]),
        @max(0.0, -0.9689 * xyz[0] + 1.8758 * xyz[1] + 0.0415 * xyz[2]),
        @max(0.0, 0.0557 * xyz[0] - 0.2040 * xyz[1] + 1.0570 * xyz[2]),
    };
}

fn luma(c: [3]f64) f64 {
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

fn srgbEncode(v: f64) f64 {
    return if (v <= 0.0031308) 12.92 * v else 1.055 * math.pow(f64, v, 1.0 / 2.4) - 0.055;
}

// ---------------------------------------------------------------- deterministic hashing

fn mix64(x0: u64) u64 {
    var z = x0 +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn unitf(h: u64) f64 {
    return @as(f64, @floatFromInt(h >> 11)) / 9007199254740992.0;
}

fn latticeVal(ix: i64, iy: i64, iz: i64, seed: u64) f64 {
    return unitf(mix64(seed ^ @as(u64, @bitCast(ix)) *% 0x9E3779B1 ^ @as(u64, @bitCast(iy)) *% 0x85EBCA77 ^ @as(u64, @bitCast(iz)) *% 0xC2B2AE3D));
}

/// Smooth 3D value noise in [0,1].
fn noise3(p: [3]f64, seed: u64) f64 {
    const f = [3]f64{ @floor(p[0]), @floor(p[1]), @floor(p[2]) };
    const i = [3]i64{ @intFromFloat(f[0]), @intFromFloat(f[1]), @intFromFloat(f[2]) };
    var u: [3]f64 = undefined;
    for (0..3) |k| {
        const t = p[k] - f[k];
        u[k] = t * t * (3.0 - 2.0 * t);
    }
    var acc: f64 = 0.0;
    for (0..8) |c| {
        const dx: i64 = @intCast(c & 1);
        const dy: i64 = @intCast((c >> 1) & 1);
        const dz: i64 = @intCast((c >> 2) & 1);
        const wx = if (dx == 1) u[0] else 1.0 - u[0];
        const wy = if (dy == 1) u[1] else 1.0 - u[1];
        const wz = if (dz == 1) u[2] else 1.0 - u[2];
        acc += wx * wy * wz * latticeVal(i[0] + dx, i[1] + dy, i[2] + dz, seed);
    }
    return acc;
}

fn dot3(a: [3]f64, b: [3]f64) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

// ============================================================================ theme state

const R_BINS: usize = 384;
const R_FRAC: u16 = 128; // rbin is stored in 1/128ths of a bin: magnified regions need sub-bin radius
const NP: usize = 1024;
const BLOCK: usize = 4;

const Rec = extern struct {
    rgb: [3]f16, // linear HDR disk radiance (pre-exposure)
    rbin: u16, // radial bin * R_FRAC (fixed point)
    phi: u16, // emission azimuth + Omega * travel time, Q16 of 2 pi
    cov: u8, // disk coverage 0..255
    fr: u8 = 0, // pixel footprint on the disk: radial extent in r-bins (saturating)
    tobs: f16 = 0, // observed blackbody temperature g*T, for re-coloring hotter gas
    fp: u8 = 0, // pixel footprint: azimuthal extent in units of 64/65536 turn (saturating)
    _pad: u8 = 0,
    tq: u16 = 0, // light-travel phase Omega*t in 1/1024 turn, mod 64 turns: kept apart so it can be unwrapped
};

const Sample = struct {
    disk: bool = false,
    tobs: f64 = 0,
    tq: u16 = 0,
    rgb: [3]f64 = .{ 0, 0, 0 }, // disk radiance, or sky linear color
    rbin: u16 = 0,
    phi: u16 = 0,
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    slab: []align(16) u8,
    recs: []Rec,
    bg: []u32,
    row_x0: []u16,
    row_x1: []u16,

    geo: Geo,
    mpp: f64,
    pix_ang: f64,
    lnr_in: f64,
    lnr_span: f64,
    exposure: f32,
    t_m: f64,
    rays_traced: u64,

    gw: [2]f32,
    gnorm: f32,
    gal_n: [3]f64, // galactic plane normal
    gal_c: [3]f64, // galactic center direction
    spot_rb: [NSPOT]f32,
    spot_wr: [NSPOT]f32, // radial half-width, r-bins
    spot_wp: [NSPOT]f32, // azimuthal half-width, Q16 units
    spot_q: [NSPOT]u16,
    spot_amp: [NSPOT]f32,
    spot_mask: [R_BINS]u8,
    gshift: [2][R_BINS]u16,
    grow: [2][R_BINS]u16,
    om_tab: [R_BINS]f64,
    tau_tab: [R_BINS]f32,
    lntau_tab: [R_BINS]f32,
    emit_tab: [EMIT_N + 1]f32,
    lin8: [256]f32, // sRGB byte -> linear
    ttab: [PT_N]f32,
    bb: [BB_N][3]f32,
    srgb: [4096]u8,
    noise: [R_BINS][NP]u8,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const n_px = w * h;
        const nbx = (w + BLOCK - 1) / BLOCK;
        // One slab: State | recs | bg | row ranges | two rows of corner hits (front + 2 behind).
        const off_recs = std.mem.alignForward(usize, @sizeOf(State), 16);
        const off_bg = std.mem.alignForward(usize, off_recs + n_px * @sizeOf(Rec), 16);
        const off_rows = std.mem.alignForward(usize, off_bg + n_px * 4, 16);
        const off_corn = std.mem.alignForward(usize, off_rows + h * 4, 16);
        const total = off_corn + 6 * (nbx + 1) * @sizeOf(Hit);
        const slab = try alloc.alignedAlloc(u8, .@"16", total);
        const self: *State = @ptrCast(@alignCast(slab.ptr));
        self.slab = slab;
        self.w = w;
        self.h = h;
        self.scale = scale;
        self.recs = @as([*]Rec, @ptrCast(@alignCast(slab.ptr + off_recs)))[0..n_px];
        self.bg = @as([*]u32, @ptrCast(@alignCast(slab.ptr + off_bg)))[0..n_px];
        const rows: [*]u16 = @ptrCast(@alignCast(slab.ptr + off_rows));
        self.row_x0 = rows[0..h];
        self.row_x1 = rows[h .. 2 * h];
        const corners = @as([*]Hit, @ptrCast(@alignCast(slab.ptr + off_corn)))[0 .. 6 * (nbx + 1)];

        self.geo = Geo.init(SPIN, INCL, R_OUT);
        self.mpp = if (h > 0) 2.0 * HALF_H / @as(f64, @floatFromInt(h)) else 1.0;
        self.pix_ang = self.mpp / OBS_R;
        self.lnr_in = @log(self.geo.r_in);
        self.lnr_span = @log(R_OUT / self.geo.r_in);
        self.t_m = 0.0;
        self.rays_traced = 0;
        self.exposure = 1.0;
        self.gw = .{ 0.5, 0.5 };
        self.gnorm = 1.0;
        self.buildTables();
        {
            // Place the Milky Way behind the hole, tilted on screen, bulge just off-center.
            const g = self.geo;
            const v = [3]f64{ -g.sin_i, 0.0, -g.cos_i }; // looking through the hole
            const ea = [3]f64{ 0.0, 1.0, 0.0 }; // screen right
            const eb = [3]f64{ -g.cos_i, 0.0, g.sin_i }; // screen up
            const ct = @cos(GAL_TILT);
            const st = @sin(GAL_TILT);
            self.gal_n = .{ ct * eb[0] - st * ea[0], ct * eb[1] - st * ea[1], ct * eb[2] - st * ea[2] };
            var c = [3]f64{ v[0] + 0.12 * (ct * ea[0] + st * eb[0]), v[1] + 0.12 * (ct * ea[1] + st * eb[1]), v[2] + 0.12 * (ct * ea[2] + st * eb[2]) };
            const nc = @sqrt(dot3(c, c));
            for (&c) |*x| x.* /= nc;
            self.gal_c = c;
        }
        self.spot_mask = @splat(0);
        if (n_px > 0) {
            self.meterExposure();
            self.render(corners);
        }
        self.step(1e-9);
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.free(self.slab);
    }

    fn buildTables(self: *State) void {
        // Temperature profile from Page-Thorne flux.
        var flux: [PT_N]f64 = undefined;
        pageThorne(self.geo.a, self.geo.r_in, R_OUT * 1.05, &flux);
        var fmax: f64 = 0.0;
        for (flux) |f| fmax = @max(fmax, f);
        for (0..PT_N) |k| self.ttab[k] = @floatCast(T_PEAK * @sqrt(@sqrt(@max(flux[k], 0.0) / fmax)));
        // Blackbody colors, normalised so a T_PEAK blackbody has luminance 1.
        const y0 = luma(blackbodyRGB(T_PEAK));
        for (0..BB_N) |k| {
            const T = BB_TMIN * @exp(@log(BB_TMAX / BB_TMIN) * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(BB_N - 1)));
            const c = blackbodyRGB(T);
            for (0..3) |i| self.bb[k][i] = @floatCast(c[i] / y0);
        }
        for (0..4096) |k| self.srgb[k] = @intFromFloat(@round(255.0 * srgbEncode(@as(f64, @floatFromInt(k)) / 4095.0)));
        for (0..R_BINS) |b| {
            const r = @exp(self.lnr_in + self.lnr_span * (@as(f64, @floatFromInt(b)) + 0.5) / @as(f64, @floatFromInt(R_BINS)));
            self.om_tab[b] = orbit(self.geo.a, r).om;
            self.tau_tab[b] = @floatCast(opticalDepth(r));
            self.lntau_tab[b] = @floatCast(@log(opticalDepth(r)));
        }
        for (0..EMIT_N + 1) |k| {
            const x = EMIT_X0 + (EMIT_X1 - EMIT_X0) * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(EMIT_N));
            self.emit_tab[k] = @floatCast(-std.math.expm1(-@exp(@as(f64, x))));
        }
        for (0..256) |k| {
            const v = @as(f64, @floatFromInt(k)) / 255.0;
            self.lin8[k] = @floatCast(if (v <= 0.04045) v / 12.92 else math.pow(f64, (v + 0.055) / 1.055, 2.4));
        }
        // Tileable turbulence: three octaves of smoothed value noise, periodic in r-bin and phi.
        for (0..R_BINS) |ri| {
            for (0..NP) |pi| {
                var v: f64 = 0.0;
                var amp: f64 = 1.0;
                var gr: usize = 24;
                var gp: usize = 96;
                for (0..2) |oct| {
                    const fr = @as(f64, @floatFromInt(ri)) * @as(f64, @floatFromInt(gr)) / @as(f64, @floatFromInt(R_BINS));
                    const fp = @as(f64, @floatFromInt(pi)) * @as(f64, @floatFromInt(gp)) / @as(f64, @floatFromInt(NP));
                    const ir: usize = @intFromFloat(@floor(fr));
                    const ip: usize = @intFromFloat(@floor(fp));
                    var ur = fr - @floor(fr);
                    var up = fp - @floor(fp);
                    ur = ur * ur * (3.0 - 2.0 * ur);
                    up = up * up * (3.0 - 2.0 * up);
                    const seed: u64 = 0xB1AC_401E + oct * 0x1000_0000;
                    const v00 = unitf(mix64(seed ^ (ir % gr) * 0x10001 ^ (ip % gp) << 20));
                    const v10 = unitf(mix64(seed ^ ((ir + 1) % gr) * 0x10001 ^ (ip % gp) << 20));
                    const v01 = unitf(mix64(seed ^ (ir % gr) * 0x10001 ^ ((ip + 1) % gp) << 20));
                    const v11 = unitf(mix64(seed ^ ((ir + 1) % gr) * 0x10001 ^ ((ip + 1) % gp) << 20));
                    const top = v00 + (v01 - v00) * up;
                    const bot = v10 + (v11 - v10) * up;
                    v += amp * (2.0 * (top + (bot - top) * ur) - 1.0);
                    amp *= 0.5;
                    gr *= 2;
                    gp *= 2;
                }
                self.noise[ri][pi] = @intFromFloat(math.clamp(128.0 + 70.0 * v, 0.0, 255.0));
            }
        }
    }

    fn temperature(self: *const State, r: f64) f64 {
        const x = @log(r / self.geo.r_in) / @log(R_OUT * 1.05 / self.geo.r_in) * @as(f64, @floatFromInt(PT_N - 1));
        if (!(x > 0.0)) return 0.0;
        const xi: usize = @intFromFloat(@min(@floor(x), @as(f64, @floatFromInt(PT_N - 2))));
        const f = x - @as(f64, @floatFromInt(xi));
        return @as(f64, self.ttab[xi]) * (1.0 - f) + @as(f64, self.ttab[xi + 1]) * f;
    }

    fn bbLookup(self: *const State, T: f64) [3]f64 {
        if (!(T > BB_TMIN)) return .{ 0, 0, 0 };
        const x = @log(T / BB_TMIN) / @log(BB_TMAX / BB_TMIN) * @as(f64, @floatFromInt(BB_N - 1));
        const xi: usize = @intFromFloat(@min(@floor(x), @as(f64, @floatFromInt(BB_N - 2))));
        const f = @min(x - @as(f64, @floatFromInt(xi)), 1.0);
        var c: [3]f64 = undefined;
        for (0..3) |i| c[i] = @as(f64, self.bb[xi][i]) * (1.0 - f) + @as(f64, self.bb[xi + 1][i]) * f;
        return c;
    }

    fn alphaBeta(self: *const State, x: f64, y: f64) [2]f64 {
        var alpha = (x - 0.5 * @as(f64, @floatFromInt(self.w))) * self.mpp;
        if (@abs(alpha) < 1e-6) alpha = 1e-6; // never aim a ray exactly through the spin axis
        return .{ alpha, (0.5 * @as(f64, @floatFromInt(self.h)) - y) * self.mpp };
    }

    fn trace(self: *State, x: f64, y: f64) Hit {
        const ab = self.alphaBeta(x, y);
        self.rays_traced += 1;
        return traceRay(&self.geo, ab[0], ab[1], true);
    }

    /// Front hit, then up to two more things seen through translucent gas (else .hole):
    /// e.g. near-side gas, the lensed far side's underside behind it, and the sky behind that.
    fn traceLayers(self: *State, x: f64, y: f64, tau_max: f64) [3]Hit {
        const ab = self.alphaBeta(x, y);
        self.rays_traced += 1;
        var ray = startRay(&self.geo, ab[0], ab[1]);
        var out = [3]Hit{ traceNext(&self.geo, &ray, true), .{}, .{} };
        for (1..3) |i| {
            const prev = out[i - 1];
            if (prev.kind != .disk or opticalDepth(prev.r) >= tau_max) break;
            out[i] = traceNext(&self.geo, &ray, true);
        }
        return out;
    }

    /// Display-linear light reaching the camera from behind translucent gas, in sky units
    /// (packBg multiplies by STAR_GAIN), composited front to back over the layers behind.
    /// Gas seen there is drawn static, at its own opacity.
    fn behind(self: *const State, x: f64, backs: [2]Hit, foot: f64) [3]f64 {
        var acc = [3]f64{ 0, 0, 0 };
        var tr: f64 = 1.0;
        for (backs) |b| {
            switch (b.kind) {
                .hole => break,
                .sky => {
                    const c = self.sky(b.dir, foot);
                    for (0..3) |i| acc[i] += tr * c[i];
                    break;
                },
                .disk => {
                    const tau = opticalDepth(b.r);
                    const s = self.shadeDisk(x, b.r, b.ph, b.t);
                    const k = @as(f64, self.exposure) * -std.math.expm1(-tau);
                    const c = [3]f64{ s.rgb[0] * k, s.rgb[1] * k, s.rgb[2] * k };
                    const tm = 1.0 / (1.0 + luma(c));
                    for (0..3) |i| acc[i] += tr * @min(c[i] * tm, 1.0) / STAR_GAIN;
                    tr *= @exp(-tau);
                },
            }
        }
        return acc;
    }

    /// Can the hits behind a block be interpolated? A lensed sky seen through gas may be, even
    /// where it curves; a disk must pass the strict test (phase/radius continuity).
    fn smoothBehind(self: *const State, cb: [4]Hit) bool {
        for (cb) |hb| if (hb.kind != cb[0].kind) return false;
        return cb[0].kind != .disk or self.uniform(cb);
    }

    /// Camera exposure, metered before rendering (translucent gas is composited with it):
    /// put the 99th-percentile luminance of the inner disk at EXPO_TARGET.
    fn meterExposure(self: *State) void {
        const gx: usize = 192;
        const gy: usize = @max(1, gx * self.h / @max(self.w, 1));
        var hist: [512]u32 = @splat(0);
        var count: u64 = 0;
        for (0..gy) |iy| {
            for (0..gx) |ix| {
                const x = (@as(f64, @floatFromInt(ix)) + 0.5) * @as(f64, @floatFromInt(self.w)) / @as(f64, @floatFromInt(gx));
                const y = (@as(f64, @floatFromInt(iy)) + 0.5) * @as(f64, @floatFromInt(self.h)) / @as(f64, @floatFromInt(gy));
                const hit = self.trace(x, y);
                if (hit.kind != .disk or hit.r > EXPO_R) continue;
                const yl = luma(self.shadeDisk(x, hit.r, hit.ph, hit.t).rgb);
                if (!(yl > 0.0)) continue;
                const bin: usize = @intFromFloat(math.clamp((@log2(yl) + 32.0) * 8.0, 0.0, 511.0));
                hist[bin] += 1;
                count += 1;
            }
        }
        if (count == 0) return;
        var acc: u64 = 0;
        const want = count - count / 100;
        for (hist, 0..) |c, b| {
            acc += c;
            if (acc >= want) {
                const yp = math.pow(f64, 2.0, @as(f64, @floatFromInt(b)) / 8.0 - 32.0);
                self.exposure = @floatCast(EXPO_TARGET / yp);
                break;
            }
        }
    }

    /// Point stars seen through the lens. `foot` is the sky angle one pixel covers here:
    /// demagnified sky (foot > pix_ang) shows fainter, denser stars; magnified sky stretches them.
    fn star(self: *const State, d: [3]f64, foot: f64) [3]f64 {
        const G = 1.0 / STAR_CELL;
        const cx = @floor(d[0] * G);
        const cy = @floor(d[1] * G);
        const cz = @floor(d[2] * G);
        const ix: i64 = @intFromFloat(cx);
        const iy: i64 = @intFromFloat(cy);
        const iz: i64 = @intFromFloat(cz);
        const hh = mix64(@as(u64, @bitCast(ix)) *% 0x9E37 ^ @as(u64, @bitCast(iy)) *% 0x85EB_CA6B ^ @as(u64, @bitCast(iz)) *% 0xC2B2_AE35);
        const lat = dot3(d, self.gal_n);
        const prob: u64 = 30 + @as(u64, @intFromFloat(45.0 * @exp(-(lat / 0.12) * (lat / 0.12))));
        if (hh % 100 >= prob) return .{ 0, 0, 0 };
        var p = [3]f64{
            (cx + 0.15 + 0.7 * unitf(mix64(hh ^ 1))) / G,
            (cy + 0.15 + 0.7 * unitf(mix64(hh ^ 2))) / G,
            (cz + 0.15 + 0.7 * unitf(mix64(hh ^ 3))) / G,
        };
        const np = @sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
        for (&p) |*v| v.* /= np;
        const dx = d[0] - p[0];
        const dy = d[1] - p[1];
        const dz = d[2] - p[2];
        const ang2 = dx * dx + dy * dy + dz * dz;
        const fp = @max(foot, self.pix_ang);
        const sig = 0.75 * fp;
        const u = unitf(mix64(hh ^ 4));
        const mu = (self.pix_ang / fp) * (self.pix_ang / fp);
        const bright = STAR_FLUX * (0.03 + 0.9 * u * u * u * u * u) * mu * @exp(-ang2 / (sig * sig));
        if (bright < 1e-4) return .{ 0, 0, 0 };
        const col = self.bbLookup(3500.0 + 9000.0 * unitf(mix64(hh ^ 5)));
        const yl = @max(luma(col), 1e-12);
        return .{ bright * col[0] / yl, bright * col[1] / yl, bright * col[2] / yl };
    }

    /// Diffuse Milky Way seen in direction d: a clumpy band, patchy dust lanes, a warm bulge.
    fn milkyWay(self: *const State, d: [3]f64) [3]f64 {
        const lat = dot3(d, self.gal_n);
        const band = @exp(-(lat / 0.07) * (lat / 0.07));
        const dc = [3]f64{ d[0] - self.gal_c[0], d[1] - self.gal_c[1], d[2] - self.gal_c[2] };
        const bulge = @exp(-dot3(dc, dc) / 0.004);
        if (band < 1e-3 and bulge < 1e-3) return .{ 0, 0, 0 };
        const s1 = [3]f64{ d[0] * 25.0, d[1] * 25.0, d[2] * 25.0 };
        const s2 = [3]f64{ d[0] * 80.0, d[1] * 80.0, d[2] * 80.0 };
        const s3 = [3]f64{ d[0] * 45.0, d[1] * 45.0, d[2] * 45.0 };
        const nz = 0.6 * noise3(s1, 11) + 0.4 * noise3(s2, 12);
        const clumpy = 0.1 + 1.2 * nz * nz;
        const lane = @exp(-(lat / 0.016) * (lat / 0.016));
        const dust = 1.0 - 0.75 * lane * math.clamp(1.6 * noise3(s3, 13) - 0.3, 0.0, 1.0);
        const warm = self.bbLookup(4300.0);
        const cool = self.bbLookup(6200.0);
        const yw = @max(luma(warm), 1e-12);
        const yc = @max(luma(cool), 1e-12);
        const ib = SKY_GAIN * band * clumpy * dust;
        const iu = SKY_GAIN * 2.5 * bulge * dust;
        return .{
            ib * cool[0] / yc + iu * warm[0] / yw,
            ib * cool[1] / yc + iu * warm[1] / yw,
            ib * cool[2] / yc + iu * warm[2] / yw,
        };
    }

    fn sky(self: *const State, d: [3]f64, foot: f64) [3]f64 {
        const a = self.star(d, foot);
        const b = self.milkyWay(d);
        return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
    }

    /// Could a star lie within `margin` of direction d? Stars sit >= 0.15 cell from their
    /// cell walls, so for margins below that, checking d's own cell is exact.
    fn starNear(self: *const State, d: [3]f64, margin: f64) bool {
        const G = 1.0 / STAR_CELL;
        if (margin * G > 0.14) return true;
        const cx = @floor(d[0] * G);
        const cy = @floor(d[1] * G);
        const cz = @floor(d[2] * G);
        const ix: i64 = @intFromFloat(cx);
        const iy: i64 = @intFromFloat(cy);
        const iz: i64 = @intFromFloat(cz);
        const hh = mix64(@as(u64, @bitCast(ix)) *% 0x9E37 ^ @as(u64, @bitCast(iy)) *% 0x85EB_CA6B ^ @as(u64, @bitCast(iz)) *% 0xC2B2_AE35);
        const lat = dot3(d, self.gal_n);
        const prob: u64 = 30 + @as(u64, @intFromFloat(45.0 * @exp(-(lat / 0.12) * (lat / 0.12))));
        if (hh % 100 >= prob) return false;
        var p = [3]f64{
            (cx + 0.15 + 0.7 * unitf(mix64(hh ^ 1))) / G,
            (cy + 0.15 + 0.7 * unitf(mix64(hh ^ 2))) / G,
            (cz + 0.15 + 0.7 * unitf(mix64(hh ^ 3))) / G,
        };
        const np = @sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
        var a2: f64 = 0.0;
        for (0..3) |i| {
            p[i] /= np;
            a2 += (d[i] - p[i]) * (d[i] - p[i]);
        }
        return a2 < margin * margin;
    }

    fn shadeDisk(self: *const State, x: f64, r: f64, ph: f64, t_hit: f64) Sample {
        const t = t_hit + T_REF; // backward-traced t is negative: this is minus the relative delay
        const alpha = (x - 0.5 * @as(f64, @floatFromInt(self.w))) * self.mpp;
        const L = -alpha * self.geo.sin_i;
        const o = orbit(self.geo.a, r);
        const g = 1.0 / (o.ut * (1.0 - o.om * L));
        const tobs = g * self.temperature(r);
        const c = self.bbLookup(tobs);
        const rb = math.clamp((@log(r) - self.lnr_in) / self.lnr_span * @as(f64, @floatFromInt(R_BINS)), 0.0, @as(f64, @floatFromInt(R_BINS - 1)));
        const phe = @mod(ph - o.om * t, 2.0 * math.pi);
        const tturns = @mod(o.om * t / (2.0 * math.pi) * 1024.0, 65536.0);
        return .{
            .disk = true,
            .tobs = tobs,
            .tq = @intFromFloat(@min(tturns, 65535.0)),
            .rgb = c,
            .rbin = @intFromFloat(@min(rb * @as(f64, R_FRAC), @as(f64, R_BINS * R_FRAC - 1))),
            .phi = @truncate(@as(u32, @intFromFloat(phe / (2.0 * math.pi) * 65536.0))),
        };
    }

    fn shadeHit(self: *const State, x: f64, hit: Hit, foot: f64) Sample {
        return switch (hit.kind) {
            .hole => .{},
            .sky => .{ .rgb = self.sky(hit.dir, foot) },
            .disk => self.shadeDisk(x, hit.r, hit.ph, hit.t),
        };
    }

    const Class = enum { uniform, sky_curved, same_kind, edge };

    fn classify(self: *const State, c: [4]Hit) struct { cls: Class, e2: f64 } {
        for (c) |h| if (h.kind != c[0].kind) return .{ .cls = .edge, .e2 = 0 };
        if (self.uniform(c)) return .{ .cls = .uniform, .e2 = 0 };
        if (c[0].kind == .sky) {
            var e2: f64 = 0.0;
            for (0..3) |i| {
                const d2 = c[0].dir[i] + c[3].dir[i] - c[1].dir[i] - c[2].dir[i];
                e2 += d2 * d2;
            }
            return .{ .cls = .sky_curved, .e2 = @sqrt(e2) };
        }
        return .{ .cls = .same_kind, .e2 = 0 };
    }

    fn uniform(self: *const State, c: [4]Hit) bool {
        const k = c[0].kind;
        for (c) |h| if (h.kind != k) return false;
        switch (k) {
            .hole => return true,
            .disk => {
                var rmin: f64 = c[0].r;
                var rmax: f64 = c[0].r;
                for (c) |h| {
                    if (h.n != c[0].n) return false;
                    rmin = @min(rmin, h.r);
                    rmax = @max(rmax, h.r);
                    if (@abs(wrapPi(h.ph - c[0].ph)) > 0.5) return false;
                }
                if (rmax / rmin > 1.6) return false;
                // Interpolation error is set by curvature: bound each field's second difference.
                const d2r = @log(c[0].r) + @log(c[3].r) - @log(c[1].r) - @log(c[2].r);
                const d2p = wrapPi(c[0].ph + c[3].ph - c[1].ph - c[2].ph);
                const d2t = c[0].t + c[3].t - c[1].t - c[2].t;
                return @abs(d2r) < 0.01 and @abs(d2p) < 0.01 and @abs(d2t) < 0.5;
            },
            .sky => {
                // Lensing may stretch the sky a lot but smoothly; what breaks bilinear
                // interpolation is curvature, measured by the block's second difference.
                const lim = 2.0 * self.pix_ang; // bilinear error ~ e2/4: under half a pixel
                var e2: f64 = 0.0;
                for (0..3) |i| {
                    const d2 = c[0].dir[i] + c[3].dir[i] - c[1].dir[i] - c[2].dir[i];
                    e2 += d2 * d2;
                }
                return e2 < lim * lim;
            },
        }
    }

    fn interpolate(c: [4]Hit, u: f64, v: f64) Hit {
        const w0 = (1 - u) * (1 - v);
        const w1 = u * (1 - v);
        const w2 = (1 - u) * v;
        const w3 = u * v;
        var out = c[0];
        switch (c[0].kind) {
            .hole => {},
            .disk => {
                out.r = @exp(w0 * @log(c[0].r) + w1 * @log(c[1].r) + w2 * @log(c[2].r) + w3 * @log(c[3].r));
                const b = c[0].ph;
                out.ph = b + w1 * wrapPi(c[1].ph - b) + w2 * wrapPi(c[2].ph - b) + w3 * wrapPi(c[3].ph - b);
                out.t = w0 * c[0].t + w1 * c[1].t + w2 * c[2].t + w3 * c[3].t;
            },
            .sky => {
                var d: [3]f64 = undefined;
                for (0..3) |i| d[i] = w0 * c[0].dir[i] + w1 * c[1].dir[i] + w2 * c[2].dir[i] + w3 * c[3].dir[i];
                const nd = @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
                for (0..3) |i| out.dir[i] = d[i] / nd;
            },
        }
        return out;
    }

    fn packBg(self: *const State, lin: [3]f64) u32 {
        var c: [3]u8 = undefined;
        for (0..3) |i| {
            const v = math.clamp(lin[i] * STAR_GAIN, 0.0, 1.0);
            c[i] = self.srgb[@intFromFloat(v * 4095.0)];
        }
        return sdk.packRGBA(c[0], c[1], c[2]);
    }

    /// The expensive part, once: trace the image block by block, refining where the picture changes.
    fn render(self: *State, corners: []Hit) void {
        const w = self.w;
        const h = self.h;
        const nbx = (w + BLOCK - 1) / BLOCK;
        const nby = (h + BLOCK - 1) / BLOCK;
        const ss: usize = 2; // 2x2 supersampling on true edges, at every resolution
        var top = corners[0 .. nbx + 1];
        var bot = corners[nbx + 1 .. 2 * (nbx + 1)];
        var topb = corners[2 * (nbx + 1) .. 3 * (nbx + 1)];
        var botb = corners[3 * (nbx + 1) .. 4 * (nbx + 1)];
        var topc = corners[4 * (nbx + 1) .. 5 * (nbx + 1)];
        var botc = corners[5 * (nbx + 1) .. 6 * (nbx + 1)];
        // Corners fetch what is behind gas a little denser than needed, so blocks straddling
        // the threshold still interpolate.
        const tau_corner = 2.0 * TAU_BEHIND;
        for (0..nbx + 1) |bx| {
            const p = self.traceLayers(@floatFromInt(bx * BLOCK), 0.0, tau_corner);
            top[bx] = p[0];
            topb[bx] = p[1];
            topc[bx] = p[2];
        }
        for (0..h) |y| {
            self.row_x0[y] = @intCast(@min(w, 0xFFFF));
            self.row_x1[y] = 0;
        }
        for (0..nby) |by| {
            const yb: f64 = @floatFromInt((by + 1) * BLOCK);
            for (0..nbx + 1) |bx| {
                const p = self.traceLayers(@floatFromInt(bx * BLOCK), yb, tau_corner);
                bot[bx] = p[0];
                botb[bx] = p[1];
                botc[bx] = p[2];
            }
            for (0..nbx) |bx| {
                const c = [4]Hit{ top[bx], top[bx + 1], bot[bx], bot[bx + 1] };
                const cb = [4]Hit{ topb[bx], topb[bx + 1], botb[bx], botb[bx + 1] };
                const cc = [4]Hit{ topc[bx], topc[bx + 1], botc[bx], botc[bx + 1] };
                const cl = self.classify(c);
                const back_smooth = self.smoothBehind(cb) and self.smoothBehind(cc);
                // Sky angle one pixel covers here, from any pair of adjacent sky corners.
                var foot = 8.0 * self.pix_ang; // typical value inside the Einstein ring, if unmeasurable
                {
                    var m: f64 = 0.0;
                    var got = false;
                    for ([_][2]usize{ .{ 0, 1 }, .{ 0, 2 }, .{ 1, 3 }, .{ 2, 3 } }) |pr| {
                        if (c[pr[0]].kind != .sky or c[pr[1]].kind != .sky) continue;
                        var q: f64 = 0.0;
                        for (0..3) |i| q += (c[pr[1]].dir[i] - c[pr[0]].dir[i]) * (c[pr[1]].dir[i] - c[pr[0]].dir[i]);
                        m = @max(m, @sqrt(q));
                        got = true;
                    }
                    if (got) foot = @max(m / @as(f64, @floatFromInt(BLOCK)), 0.25 * self.pix_ang);
                }
                const y_end = @min((by + 1) * BLOCK, h);
                const x_end = @min((bx + 1) * BLOCK, w);
                for (by * BLOCK..y_end) |py| {
                    for (bx * BLOCK..x_end) |px| {
                        var disk_rgb = [3]f64{ 0, 0, 0 };
                        var bg_rgb = [3]f64{ 0, 0, 0 };
                        var nd: usize = 0;
                        var first: Sample = .{};
                        const sub: usize = if (cl.cls == .edge) ss else 1; // supersample true edges only
                        const nsamp = sub * sub;
                        for (0..nsamp) |si| {
                            const sx: f64 = (@as(f64, @floatFromInt(si % sub)) + 0.5) / @as(f64, @floatFromInt(sub));
                            const sy: f64 = (@as(f64, @floatFromInt(si / sub)) + 0.5) / @as(f64, @floatFromInt(sub));
                            const fx = @as(f64, @floatFromInt(px)) + sx;
                            const fy = @as(f64, @floatFromInt(py)) + sy;
                            const u = (fx - @as(f64, @floatFromInt(bx * BLOCK))) / BLOCK;
                            const v = (fy - @as(f64, @floatFromInt(by * BLOCK))) / BLOCK;
                            var backs = [2]Hit{ .{}, .{} };
                            var have_back = false;
                            var hit = switch (cl.cls) {
                                .uniform => interpolate(c, u, v),
                                .sky_curved => blk: {
                                    // Interpolation is off by at most ~e2/4; if no star can be that
                                    // close, the pixel is provably empty sky and needs no ray.
                                    const guess = interpolate(c, u, v);
                                    const margin = 0.5 * cl.e2 + 4.0 * 0.75 * @max(foot, self.pix_ang);
                                    break :blk if (self.starNear(guess.dir, margin)) self.trace(fx, fy) else guess;
                                },
                                else => blk: {
                                    const p = self.traceLayers(fx, fy, TAU_BEHIND);
                                    backs = .{ p[1], p[2] };
                                    have_back = true;
                                    break :blk p[0];
                                },
                            };
                            const thin = hit.kind == .disk and opticalDepth(hit.r) < TAU_BEHIND;
                            if (thin and !have_back) {
                                if (back_smooth) {
                                    backs = .{ interpolate(cb, u, v), interpolate(cc, u, v) };
                                } else {
                                    const p = self.traceLayers(fx, fy, TAU_BEHIND);
                                    hit = p[0];
                                    backs = .{ p[1], p[2] };
                                }
                            }
                            if (hit.kind == .disk and hit.r > SPOT_RMAX) {
                                const tau = opticalDepth(hit.r);
                                const dim = luma(self.shadeDisk(fx, hit.r, hit.ph, hit.t).rgb) * self.exposure * 2.0 < EMIT_FLOOR;
                                if (tau * @exp(@as(f64, TAU_NOISE)) < TAU_MIN or dim) {
                                    // Gas too thin or too cool to show even when turbulence stirs it:
                                    // baked into the background at its mean opacity, not redrawn per frame.
                                    if (tau < TAU_BEHIND) {
                                        const bh = self.behind(fx, backs, foot);
                                        const tr = @exp(-tau);
                                        for (0..3) |i| bg_rgb[i] += tr * bh[i];
                                    }
                                    continue;
                                }
                            }
                            const s = self.shadeHit(fx, hit, foot);
                            if (s.disk) {
                                if (nd == 0) first = s;
                                nd += 1;
                                for (0..3) |i| disk_rgb[i] += s.rgb[i];
                                if (opticalDepth(hit.r) < TAU_BEHIND) {
                                    const bh = self.behind(fx, backs, foot);
                                    for (0..3) |i| bg_rgb[i] += bh[i];
                                }
                            } else {
                                for (0..3) |i| bg_rgb[i] += s.rgb[i];
                            }
                        }
                        const idx = py * w + px;
                        const fs: f64 = @floatFromInt(nsamp);
                        self.bg[idx] = self.packBg(.{ bg_rgb[0] / fs, bg_rgb[1] / fs, bg_rgb[2] / fs });
                        if (nd > 0) {
                            const fd: f64 = @floatFromInt(nd);
                            self.recs[idx] = .{
                                .rgb = .{ @floatCast(disk_rgb[0] / fd), @floatCast(disk_rgb[1] / fd), @floatCast(disk_rgb[2] / fd) },
                                .rbin = first.rbin,
                                .phi = first.phi,
                                .cov = @intCast(nd * 255 / nsamp),
                                .tobs = @floatCast(@min(first.tobs, 60000.0)),
                                .tq = first.tq,
                            };
                            self.row_x0[py] = @min(self.row_x0[py], @as(u16, @intCast(px)));
                            self.row_x1[py] = @max(self.row_x1[py], @as(u16, @intCast(px + 1)));
                        } else {
                            self.recs[idx] = .{ .rgb = .{ 0, 0, 0 }, .rbin = 0, .phi = 0, .cov = 0 };
                        }
                    }
                }
            }
            const tmp = top;
            top = bot;
            bot = tmp;
            const tmpb = topb;
            topb = botb;
            botb = tmpb;
            const tmpc = topc;
            topc = botc;
            botc = tmpc;
        }
        // Each disk pixel's footprint on the disk, from its neighbours: lensing can squeeze a
        // wide patch of disk into one pixel, and texture finer than that must be filtered.
        for (0..h) |py| {
            for (0..w) |px| {
                const i = py * w + px;
                if (self.recs[i].cov == 0) continue;
                var fr: u32 = 0;
                var fp: u32 = 0;
                const nb = [4][2]i64{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
                for (nb) |o| {
                    const nx = @as(i64, @intCast(px)) + o[0];
                    const ny = @as(i64, @intCast(py)) + o[1];
                    if (nx < 0 or ny < 0 or nx >= @as(i64, @intCast(w)) or ny >= @as(i64, @intCast(h))) continue;
                    const j = @as(usize, @intCast(ny)) * w + @as(usize, @intCast(nx));
                    if (self.recs[j].cov == 0) continue;
                    const dr = @divTrunc(@abs(@as(i32, self.recs[j].rbin) - @as(i32, self.recs[i].rbin)) + R_FRAC - 1, R_FRAC);
                    // Emission phase = geometric azimuth (safe to compare modulo a turn) minus the
                    // light-travel phase (compared unwrapped: delays can wind it by several turns).
                    const ri = self.recs[i];
                    const rj = self.recs[j];
                    const hit_i = ri.phi +% (ri.tq << 6);
                    const hit_j = rj.phi +% (rj.tq << 6);
                    const d_hit: i32 = @as(i16, @bitCast(hit_j -% hit_i));
                    const d_tq: i32 = @as(i16, @bitCast(rj.tq -% ri.tq));
                    const dp = @abs(d_hit - d_tq * 64);
                    fr = @max(fr, @as(u32, @intCast(dr)));
                    fp = @max(fp, @as(u32, @intCast(dp)));
                }
                self.recs[i].fr = @intCast(@min(fr, 255));
                self.recs[i].fp = @intCast(@min((fp + 63) / 64, 255));
            }
        }
    }

    // ---------------------------------------------------------------- per frame

    pub fn step(self: *State, dt: f64) void {
        if (!(dt > 0.0 and dt < 1.0)) return;
        self.t_m += dt * TIME_LAPSE;
        var wsq: f32 = 0.0;
        for (0..2) |gi| {
            const shifted = self.t_m + @as(f64, @floatFromInt(gi)) * 0.5 * LIFE_M;
            const gen = @floor(shifted / LIFE_M);
            const age = shifted - gen * LIFE_M;
            const wgt: f32 = @floatCast(1.0 - @abs(2.0 * age / LIFE_M - 1.0));
            self.gw[gi] = wgt;
            wsq += wgt * wgt;
            const hs = mix64(@as(u64, @intFromFloat(@max(gen, 0.0))) *% 2 + gi);
            const row_off: usize = @intCast(hs % R_BINS);
            const phase_off: u32 = @truncate(hs >> 32);
            for (0..R_BINS) |b| {
                const rot = @mod(self.om_tab[b] * age, 2.0 * math.pi) / (2.0 * math.pi) * 65536.0;
                self.gshift[gi][b] = @truncate(@as(u32, @intFromFloat(rot)) +% phase_off);
                self.grow[gi][b] = @intCast((b + row_off) % R_BINS);
            }
        }
        self.gnorm = 1.0 / @sqrt(@max(wsq, 1e-6));

        // Hot spots: born, orbit at their exact Kerr angular velocity, fade.
        @memset(&self.spot_mask, 0);
        const span_bins = self.lnr_span / @as(f64, @floatFromInt(R_BINS));
        for (0..NSPOT) |j| {
            const shifted = self.t_m + @as(f64, @floatFromInt(j)) * SPOT_LIFE / @as(f64, @floatFromInt(NSPOT));
            const gen = @floor(shifted / SPOT_LIFE);
            const age = shifted - gen * SPOT_LIFE;
            const env = @sin(math.pi * age / SPOT_LIFE);
            const hs = mix64(@as(u64, @intFromFloat(@max(gen, 0.0))) *% 16 + j + 0xA5A5);
            const u = unitf(hs);
            const r = self.geo.r_in * (1.15 + 4.2 * u * u);
            const om = orbit(self.geo.a, r).om;
            const ph = @mod(2.0 * math.pi * unitf(mix64(hs ^ 7)) + om * self.t_m, 2.0 * math.pi);
            const rb = (@log(r) - self.lnr_in) / span_bins;
            const wr = (SPOT_SIZE / r) / span_bins;
            const wp = (SPOT_SIZE / r) / (2.0 * math.pi) * 65536.0;
            self.spot_rb[j] = @floatCast(rb);
            self.spot_wr[j] = @floatCast(wr);
            self.spot_wp[j] = @floatCast(wp);
            self.spot_q[j] = @truncate(@as(u32, @intFromFloat(ph / (2.0 * math.pi) * 65536.0)));
            self.spot_amp[j] = @floatCast(@as(f64, SPOT_AMP) * env * env);
            const lo: i64 = @intFromFloat(@floor(rb - wr - 12.0)); // margin for wide pixel footprints
            const hi: i64 = @intFromFloat(@ceil(rb + wr + 12.0));
            var b = @max(lo, 0);
            while (b <= @min(hi, @as(i64, R_BINS - 1))) : (b += 1) self.spot_mask[@intCast(b)] |= @as(u8, 1) << @intCast(j);
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return !math.isFinite(self.t_m) or !math.isFinite(self.exposure);
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        if (w == 0 or self.h == 0 or stride < w) return;
        const h: usize = @min(self.h, buf.len / stride);
        const expo = self.exposure;
        const amp = TURB * self.gnorm / 128.0;
        const w0 = self.gw[0] * amp;
        const w1 = self.gw[1] * amp;

        const last_buf_idx = (h - 1) * stride + (w - 1);
        const last_bg_idx = (h - 1) * w + (w - 1);
        const need_bg_fill = (buf[0] != self.bg[0] or
            buf[w - 1] != self.bg[w - 1] or
            buf[last_buf_idx] != self.bg[last_bg_idx] or
            buf[(h - 1) * stride] != self.bg[(h - 1) * w]);

        if (need_bg_fill) {
            for (0..h) |y| {
                const row = buf[y * stride .. y * stride + w];
                @memcpy(row, self.bg[y * w .. y * w + w]);
            }
        }

        for (0..h) |y| {
            const x0 = self.row_x0[y];
            const x1 = self.row_x1[y];
            if (x0 >= x1) continue;
            const row = buf[y * stride .. y * stride + w];
            const bg_row = self.bg[y * w .. y * w + w];
            const rec_row = self.recs[y * w .. y * w + w];
            for (x0..x1) |x| {
                const rc = rec_row[x];
                if (rc.cov == 0) continue;
                const rb = rc.rbin / R_FRAC;
                const rbf = @as(f32, @floatFromInt(rc.rbin)) / @as(f32, @floatFromInt(R_FRAC));
                const pa = (rc.phi -% self.gshift[0][rb]) >> 6;
                const pb = (rc.phi -% self.gshift[1][rb]) >> 6;
                const na: f32 = @floatFromInt(@as(i32, self.noise[self.grow[0][rb]][pa]) - 128);
                const nb: f32 = @floatFromInt(@as(i32, self.noise[self.grow[1][rb]][pb]) - 128);
                const frf: f32 = @floatFromInt(rc.fr);
                const fpf: f32 = @as(f32, @floatFromInt(rc.fp)) * 64.0;
                // Turbulence cells are ~16 r-bins by ~683 Q16 units; unresolved texture averages out.
                const tex = 1.0 / (1.0 + (frf * frf) / 64.0 + (fpf * fpf) / 116_000.0);
                var k = @max(0.0, 1.0 + tex * (w0 * na + w1 * nb)) * expo;
                // Translucent outer gas: emitted fraction 1 - e^-tau, column density stirred by
                // the same turbulence (unresolved texture averages out, as above).
                const tau_b = self.tau_tab[rb];
                const thin = tau_b < TAU_BEHIND;
                var emit: f32 = 1.0;
                if (thin) {
                    const nt = math.clamp((self.gw[0] * na + self.gw[1] * nb) * self.gnorm / 128.0 * tex, -1.0, 1.0);
                    const xi = math.clamp((self.lntau_tab[rb] + TAU_NOISE * nt - EMIT_X0) * (@as(f32, EMIT_N) / (EMIT_X1 - EMIT_X0)), 0.0, @as(f32, EMIT_N) - 0.001);
                    const ii: usize = @intFromFloat(xi);
                    const fr_e = xi - @as(f32, @floatFromInt(ii));
                    emit = self.emit_tab[ii] + (self.emit_tab[ii + 1] - self.emit_tab[ii]) * fr_e;
                    k *= emit;
                }
                var spot_rgb: [3]f32 = undefined;
                var spot_scale: f32 = 0.0;
                const sm = self.spot_mask[rb];
                if (sm != 0) {
                    var boost: f32 = 0.0;
                    inline for (0..NSPOT) |j| {
                        if (sm & (@as(u8, 1) << j) != 0) {
                            // Spot seen through this pixel's footprint: widen the kernel, keep its energy.
                            const wr2 = self.spot_wr[j] * self.spot_wr[j] + frf * frf;
                            const wp2 = self.spot_wp[j] * self.spot_wp[j] + fpf * fpf;
                            const dr = rbf - self.spot_rb[j];
                            const dp: f32 = @floatFromInt(@as(i16, @bitCast(rc.phi -% self.spot_q[j])));
                            if (rc.fp == 255 or fpf > 2.0 * self.spot_wp[j] or frf > 2.0 * self.spot_wr[j]) {
                                // Unresolved here (pixel footprint wider than the spot): widening the
                                // kernel would smear it into long false arcs, so it is left out.
                                // Emission phase winds > 1/4 turn across this pixel (lensing time delays):
                                // the spot is unresolvable here. Its true contribution is a time average we
                                // don't integrate, so it is left out rather than drawn as a fake ring.
                            } else {
                                const q = dr * dr / wr2 + dp * dp / wp2;
                                if (q < 1.0) boost += self.spot_amp[j] * (1.0 - q) * (1.0 - q) * self.spot_wr[j] * self.spot_wp[j] / @sqrt(wr2 * wp2);
                            }
                        }
                    }
                    if (boost > 1e-3 and rc.tobs > 0) {
                        // Hotter gas is a hotter blackbody (T ~ emission^(1/4)): Planck gives its
                        // new color and brightness; ratio carries this pixel's coverage/normalisation.
                        const t0: f64 = @floatCast(@as(f32, rc.tobs));
                        const hot = self.bbLookup(t0 * @sqrt(@sqrt(1.0 + @as(f64, boost))));
                        const lum0 = luma(.{ rc.rgb[0], rc.rgb[1], rc.rgb[2] });
                        spot_scale = @floatCast(lum0 / @max(luma(self.bbLookup(t0)), 1e-12));
                        spot_rgb = .{ @floatCast(hot[0]), @floatCast(hot[1]), @floatCast(hot[2]) };
                    } else k *= 1.0 + boost;
                }
                var c = if (spot_scale > 0.0)
                    [3]f32{ spot_rgb[0] * spot_scale * k, spot_rgb[1] * spot_scale * k, spot_rgb[2] * spot_scale * k }
                else
                    [3]f32{ @as(f32, rc.rgb[0]) * k, @as(f32, rc.rgb[1]) * k, @as(f32, rc.rgb[2]) * k };
                const yl = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
                const tm = 1.0 / (1.0 + yl); // Reinhard on luminance, hue preserved
                const bgp = bg_row[x];
                if (thin) {
                    // I = cov * B(1 - e^-tau) + bg * (1 - cov (1 - e^-tau)); bg holds what lies behind.
                    var out: [3]u8 = undefined;
                    const cov: f32 = @as(f32, @floatFromInt(rc.cov)) / 255.0;
                    const tr = 1.0 - cov * emit;
                    for (0..3) |i| {
                        const bl = self.lin8[(bgp >> @intCast(8 * i)) & 0xFF];
                        const v = @min(cov * c[i] * tm + tr * bl, 1.0);
                        out[i] = self.srgb[@intFromFloat(v * 4095.0)];
                    }
                    row[x] = sdk.packRGBA(out[0], out[1], out[2]);
                } else if (rc.cov == 255) {
                    const r0 = self.srgb[@intFromFloat(@min(c[0] * tm, 1.0) * 4095.0)];
                    const g0 = self.srgb[@intFromFloat(@min(c[1] * tm, 1.0) * 4095.0)];
                    const b0 = self.srgb[@intFromFloat(@min(c[2] * tm, 1.0) * 4095.0)];
                    row[x] = sdk.packRGBA(r0, g0, b0);
                } else {
                    var out: [3]u8 = undefined;
                    const cov: f32 = @as(f32, @floatFromInt(rc.cov)) / 255.0;
                    for (0..3) |i| {
                        c[i] = @min(c[i] * tm, 1.0);
                        const dv: f32 = @floatFromInt(self.srgb[@intFromFloat(c[i] * 4095.0)]);
                        const bv: f32 = @floatFromInt((bgp >> @intCast(8 * i)) & 0xFF);
                        out[i] = @intFromFloat(@round(dv * cov + bv * (1.0 - cov)));
                    }
                    row[x] = sdk.packRGBA(out[0], out[1], out[2]);
                }
            }
        }
    }
};

fn wrapPi(x: f64) f64 {
    return x - 2.0 * math.pi * @round(x / (2.0 * math.pi));
}

comptime {
    sdk.exportTheme(State);
}

// ============================================================================ physics tests

const testing = std.testing;

test "ISCO: 6M without spin, -> 1M at extreme spin, and energy is minimal there" {
    try testing.expectApproxEqAbs(6.0, isco(0.0), 1e-12);
    try testing.expect(isco(0.999999) < 1.05);
    const a = SPIN;
    const r = isco(a);
    const e = 1e-5;
    const dE = (orbit(a, r * (1 + e)).E - orbit(a, r * (1 - e)).E) / (2 * r * e);
    try testing.expect(@abs(dE) < 1e-6);
    try testing.expect(orbit(a, r * 1.01).E > orbit(a, r).E);
}

test "photon orbits and Schwarzschild shadow radius sqrt(27)" {
    try testing.expectApproxEqAbs(3.0, photonOrbit(0.0, true), 1e-12);
    const g = Geo.init(0.0, INCL, R_OUT);
    var lo: f64 = 4.0;
    var hi: f64 = 7.0;
    for (0..40) |_| {
        const mid = 0.5 * (lo + hi);
        if (traceRay(&g, 0.0, mid, false).kind == .hole) lo = mid else hi = mid;
    }
    try testing.expectApproxEqAbs(@sqrt(27.0), 0.5 * (lo + hi), 2e-3);
}

/// Bardeen (1973) critical curve: the exact edge of the Kerr shadow.
fn bardeen(a: f64, incl: f64, r: f64) ?[2]f64 {
    const lam = -(r * r * (r - 3.0) + a * a * (r + 1.0)) / (a * (r - 1.0));
    const eta = r * r * r * (4.0 * a * a - r * (r - 3.0) * (r - 3.0)) / (a * a * (r - 1.0) * (r - 1.0));
    const ci = @cos(incl);
    const si = @sin(incl);
    const b2 = eta + a * a * ci * ci - lam * lam * ci * ci / (si * si);
    if (b2 < 0) return null;
    return .{ -lam / si, @sqrt(b2) };
}

test "Kerr shadow edge matches Bardeen's analytic critical curve" {
    const g = Geo.init(SPIN, INCL, R_OUT);
    const r1 = photonOrbit(SPIN, true);
    const r2 = photonOrbit(SPIN, false);
    var worst: f64 = 0.0;
    var checked: usize = 0;
    for (1..12) |k| {
        const r = r1 + (r2 - r1) * @as(f64, @floatFromInt(k)) / 12.0;
        const ab = bardeen(SPIN, INCL, r) orelse continue;
        if (ab[1] < 0.3) continue; // too close to the equator line to bisect cleanly
        var lo: f64 = 0.0;
        var hi: f64 = ab[1] + 3.0;
        if (traceRay(&g, ab[0], lo, false).kind != .hole) continue;
        for (0..40) |_| {
            const mid = 0.5 * (lo + hi);
            if (traceRay(&g, ab[0], mid, false).kind == .hole) lo = mid else hi = mid;
        }
        worst = @max(worst, @abs(0.5 * (lo + hi) - ab[1]));
        checked += 1;
    }
    std.debug.print("\n  Bardeen check: {d} points, worst |beta_traced - beta_exact| = {e:.2} M\n", .{ checked, worst });
    try testing.expect(checked >= 6);
    try testing.expect(worst < 0.01);
}

test "geodesic invariants: null condition and Carter constant are conserved" {
    const g = Geo.init(SPIN, INCL, R_OUT);
    const st = initialState(&g, -2.4, 3.9);
    var y = st.y;
    const L = st.L;
    const a = SPIN;
    const q0 = carter(a, L, y);
    var worst_h: f64 = 0.0;
    var worst_q: f64 = 0.0;
    for (0..4000) |_| {
        const r = y[0];
        if (r < g.rh + 0.05 or (y[4] > 0 and r > 200)) break;
        const k1 = rhs(a, L, y);
        y = project(a, L, rk4k(a, L, y, stepSize(&g, y, k1), k1)); // the production stepper
        worst_h = @max(worst_h, @abs(nullB(a, L, y)) / (y[0] * y[0]));
        worst_q = @max(worst_q, @abs(carter(a, L, y) - q0) / q0);
    }
    std.debug.print("\n  invariants: max |H|/r^2 = {e:.2}, max |dQ/Q| = {e:.2}\n", .{ worst_h, worst_q });
    try testing.expect(worst_h < 1e-4);
    try testing.expect(worst_q < 1e-4);
}

fn nullB(a: f64, L: f64, y: V6) f64 {
    const s = @sin(y[1]);
    const s2 = s * s;
    const r = y[0];
    const del = r * r - 2 * r + a * a;
    const P = r * r + a * a - a * L;
    return del * y[4] * y[4] + y[5] * y[5] - P * P / del + (L - a * s2) * (L - a * s2) / s2;
}

fn carter(a: f64, L: f64, y: V6) f64 {
    const c = @cos(y[1]);
    const s = @sin(y[1]);
    return y[5] * y[5] - a * a * c * c + L * L * c * c / (s * s);
}

test "Page-Thorne flux: zero at the ISCO, positive outside, Newtonian at large r" {
    var f: [PT_N]f64 = undefined;
    const r_in = isco(0.3);
    pageThorne(0.3, r_in, 1.0e5, &f);
    try testing.expectEqual(@as(f64, 0.0), f[0]);
    for (f[1..]) |v| try testing.expect(v > 0.0);
    // far out F -> C (1 - sqrt(r_*/r)) / r^3 ; F r^3 must flatten to a constant
    const dl = @log(1.0e5 / r_in) / @as(f64, PT_N - 1);
    const k1: usize = @intFromFloat(@log(2.0e4 / r_in) / dl);
    const k2: usize = PT_N - 1;
    const ra = r_in * @exp(dl * @as(f64, @floatFromInt(k1)));
    const rb = r_in * @exp(dl * @as(f64, @floatFromInt(k2)));
    const ratio = (f[k1] * ra * ra * ra) / (f[k2] * rb * rb * rb);
    try testing.expectApproxEqAbs(1.0, ratio, 0.02);
}

test "outer disk: opaque inside, translucent edge, gone before the geometry ends" {
    try testing.expect(opticalDepth(isco(SPIN)) > 50.0);
    try testing.expect(opticalDepth(10.0) > TAU_THICK);
    try testing.expect(opticalDepth(19.0) > 0.5 and opticalDepth(22.0) < 1.0);
    try testing.expect(opticalDepth(R_OUT) * @exp(@as(f64, TAU_NOISE)) < 0.01);
    var r: f64 = 3.0;
    while (r < R_OUT) : (r += 0.25) try testing.expect(opticalDepth(r + 0.25) < opticalDepth(r));
}

test "blackbody colours: 6500 K is near white, 3000 K is warm, 20000 K is blue" {
    const w = blackbodyRGB(6500.0);
    const mx = @max(w[0], @max(w[1], w[2]));
    const mn = @min(w[0], @min(w[1], w[2]));
    try testing.expect(mx / mn < 1.15);
    const c = blackbodyRGB(3000.0);
    try testing.expect(c[0] > c[1] and c[1] > c[2]);
    const hot = blackbodyRGB(20000.0);
    try testing.expect(hot[2] > hot[0]);
}

test "redshift: approaching side is the prograde-photon side, and the shadow is flattened there" {
    const a = SPIN;
    const r = 6.0;
    const g_left = redshift(a, r, 6.0 * @sin(INCL)); // alpha = -6
    const g_right = redshift(a, r, -6.0 * @sin(INCL)); // alpha = +6
    try testing.expect(g_left > 1.0 and g_right < 1.0);
    const flat = bardeen(a, INCL, photonOrbit(a, true) + 0.05);
    if (flat) |ab| try testing.expect(ab[0] < 0.0);
}

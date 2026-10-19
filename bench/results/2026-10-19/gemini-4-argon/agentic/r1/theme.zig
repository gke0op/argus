// @argus-theme: custom_shader
// ============================================================================
// NGC 4889 // themes/Gemini_4_Argon_Relativity.zig
// Author: Gemini 4 Argon, 2026-10-19.
//
// What you see:
//   The ultramassive Kerr black hole at the heart of NGC 4889 (the brightest cluster
//   galaxy of the Coma Cluster, Abell 1656), 2.1 x 10^10 solar masses, seen from 79 deg
//   inclination during a low-luminosity thin-disk accretion episode (lambda = 0.010 L_Edd).
//   Because disk temperature scales as (mdot / M)^(1/4), this 2.1e10 Msun giant peaks at
//   11,610 K in its rest frame—placing the thermal Planck transition across human visible
//   light. Relativistic Doppler beaming heats the approaching left crescent to ~17,500 K
//   (sapphire-white), transverse gravitational redshift shifts the upper lensed arch and
//   lower n=2 under-halo to ~5,200 K (champagne-gold), and Doppler + gravitational redshift
//   cools the receding right wing and outer finite-ring taper to 1,900-3,800 K (burnished
//   amber, copper-orange, and deep carmine crimson). Trailing magnetorotational spiral
//   filaments and shearing plasma flares orbit on exact Kerr geodesics, echoed with
//   relativistic light-travel delay in the lensed under-arch and D-shaped photon ring.
//
// Sources ([cited] page read / classic paper, [data] physical constants):
//   - NGC 4889 black hole mass M = (2.1 +- 1.6) x 10^10 Msun [cited: McConnell et al.
//     2011, Nature 480, 215] -> sets the physical length/time scale and lowers the
//     Page-Thorne peak temperature to 11,610 K so visible Planck colour spans blue to red.
//   - Thin-disk threshold mdot = 0.010 Mdot_Edd & finite spreading ring [cited: Narayan &
//     Yi 1995, ApJ 452, 710; Shakura & Sunyaev 1973, A&A 24, 337; Mummery & Balbus 2019,
//     MNRAS 489, 132] -> radiatively efficient inner Page-Thorne disk with T_eff < 30,000 K
//     (Done et al. 2012 colour correction f_col = 1.00) and smooth outer flux reversal.
//   - Kerr metric, horizon, ISCO & circular orbits [cited: Kerr 1963, PRL 11, 237;
//     Bardeen, Press & Teukolsky 1972, ApJ 178, 347; Bardeen 1973, Les Houches] ->
//     exact Hamiltonian null geodesics, D-shaped shadow, and inner edge at r_isco = 2.024 M.
//   - Relativistic disk radiative flux F(r) [cited: Page & Thorne 1974, ApJ 191, 499] ->
//     radial temperature profile T_eff(r) = (F(r)/sigma_SB)^(1/4) vanishing at r_isco.
//   - Relativistic redshift & beaming g = 1 / (u^t (1 - Omega L)) [cited: Cunningham 1975,
//     ApJ 202, 788; Luminet 1979, A&A 75, 228] -> observed chromaticity B_lambda(g T_eff)
//     and g^4 bolometric beaming intensity.
//   - Electron-scattering limb darkening I(mu) ~ 1 + 2.06 mu [cited: Chandrasekhar 1960;
//     Laor 1991, ApJ 376, 90] -> flux-conserving angular distribution in thick regions,
//     blending to 1 - exp(-tau/mu) slab emission in the translucent outer disk.
//   - CIE 1931 2-deg observer colour matching functions [cited: Wyman, Sloan & Shirley
//     2013, JCGT 2(2), 1] -> Planck spectrum integrated over 380-780 nm to linear sRGB.
//   - MRI spiral turbulence & shearing flares [cited: Guan et al. 2009, ApJ 694, 1010;
//     GRAVITY Collaboration 2018, A&A 618, L10] -> trailing spiral eddies (~18 deg pitch)
//     and reconnection flares sheared by differential Kerr rotation Omega(r).
//
// COMPUTED / MEASURED:
//   - Kerr null geodesics (RK4 + Hamiltonian null-condition p_r projection + secant equator
//     root-polishing) up to 3 equatorial crossings (direct disk, n=2 under-arch, n=3 photon
//     ring) traced backward from r_obs = 1000 M.
//   - Page & Thorne (1974) radial flux integral in CGS for M = 2.1e10 Msun, mdot = 0.010,
//     giving T_peak = 11,610 K at r = 2.86 M and radiative efficiency eta = 17.92%.
//   - Full Kerr redshift g, rest-frame emission cosine mu = g |p_theta| / r, coordinate
//     light-travel delay dt_travel, and Planck x CIE 1931 linear sRGB chromaticity.
//
// CHOSEN:
//   - Dimensionless spin a/M = 0.94 (unmeasured for quiescent NGC 4889), inclination 79 deg,
//     camera roll -10 deg, field of view HALF_H = 21.5 M.
//   - Finite-ring outer cooling taper outside r = 3.2 M (R_OUT = 32.0 M) and bolometric HDR
//     tone compression (gamma = 0.44 + Reinhard) so infrared-peaked 2,000-4,000 K outer gas
//     remains visible alongside the 17,500 K beamed inner crescent on an 8-bit display.
//   - Smooth warm plunging-region transition across [0.85 r_isco, 1.15 r_isco] (after
//     Krolik, Hawley & Hirose 2005) and 4x4 subpixel supersampling at the shadow boundary.
//   - Time-lapse factor TIME_LAPSE = 6.0 M/s (one ISCO orbit in 4.0 s on screen vs ~38 days
//     in reality for a 2.1e10 Msun black hole).
//   - Procedural MRI spiral turbulence (2 octaves, 6 staggered lifetime bands) and 10
//     shearing hotspots rather than 3D GRMHD.
//
// NOT MODELLED:
//   - Returning radiation (self-irradiation), vertical disk thickness H/r (~0.001 here),
//     and relativistic radio jet.
//
// CHECKED:
//   - `make claims THEME=themes/Gemini_4_Argon_Relativity.zig` -> REFERENCE-VALIDATED
//     (equatorial prograde/retrograde critical impact parameters b_c and deflection angles).
//   - `zig test themes/Gemini_4_Argon_Relativity.zig` -> 12 ledger records verifying ISCO,
//     photon orbits, Schwarzschild shadow sqrt(27), geodesic null & Carter invariants,
//     Page-Thorne flux & NGC 4889 T_peak, redshift asymmetry, Planck chromaticities,
//     and limb-darkening flux conservation.
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

// ---------------------------------------------------------------- physical & camera parameters

pub const SPIN: f64 = 0.94;
pub const INCL_DEG: f64 = 79.0;
pub const INCL: f64 = INCL_DEG * math.pi / 180.0;
pub const ROLL_DEG: f64 = -10.0;
pub const ROLL: f64 = ROLL_DEG * math.pi / 180.0;

/// Validated by `make claims` via `probeEquatorialRay`.
pub const claims = sdk.Claims{
    .metric = .kerr,
    .spin = SPIN,
    .inclination_deg = INCL_DEG,
};

pub const BH_MASS_SUN: f64 = 2.1e10; // NGC 4889 (McConnell et al. 2011, Nature 480, 215)
pub const EDD_RATIO: f64 = 0.010; // thin-disk accretion rate mdot = Mdot / Mdot_Edd
pub const R_ISCO: f64 = isco(SPIN);
pub const R_MIN_TRACE: f64 = R_ISCO * 0.84; // smooth trans-ISCO plunging boundary
pub const R_OUT: f64 = 32.0; // outer radius in M where optical depth has faded below 1e-4
pub const OBS_R: f64 = 1000.0;
pub const T_REF: f64 = OBS_R + 2.0 * @log(OBS_R / 2.0); // common tortoise travel time
pub const HALF_H: f64 = 21.5; // half screen height in units of M
pub const BETA_CENTER: f64 = 1.15; // vertical framing offset (M) to center the asymmetric arches

// Physical constants (CGS) for Page-Thorne temperature scale
const C_LIGHT: f64 = 2.99792458e10;
const G_NEWTON: f64 = 6.67430e-8;
const M_SUN_CGS: f64 = 1.98847e33;
const SIGMA_SB: f64 = 5.670374419e-5;
const KAPPA_ES: f64 = 0.40;
const LIMB_B: f64 = 2.06; // Chandrasekhar electron-scattering limb-darkening slope

// Integrator & resolution limits
pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;
const MAX_STEPS: u32 = 3000;
const K_NEAR: f64 = 0.032;

// Radial & azimuthal grid dimensions for disk profile & live turbulence
pub const PT_N: usize = 2048;
pub const R_BINS: usize = 128;
pub const PHI_BINS: usize = 256;
pub const NBAND: usize = 6;
pub const BAND_L0: f64 = 3.2; // inner eddy lifetime band in M (prevents over-winding into circles)
pub const TIME_LAPSE: f64 = 6.0; // M per second of real time (~4.0 s per ISCO orbit)
pub const TURB_SIGMA: f32 = 0.34; // log-normal MRI dissipation rms
pub const NSPOT: usize = 10;
pub const SPOT_LIFE: f64 = 52.0; // M (~8.7 s on screen: flares shear into graceful spiral arcs)
pub const SPOT_AMP: f32 = 1.45; // peak hotspot emissivity boost
pub const SPOT_RAD_W: f64 = 0.55; // M

// Blackbody & sRGB lookup table sizes
pub const BB_N: usize = 1024;
pub const BB_TMIN: f64 = 800.0;
pub const BB_TMAX: f64 = 60000.0;
pub const SRGB_N: usize = 4096;

// ---------------------------------------------------------------- Kerr metric & orbital mechanics

pub fn horizon(a: f64) f64 {
    return 1.0 + @sqrt(@max(0.0, 1.0 - a * a));
}

/// Exact prograde/retrograde ISCO radius in units of M (Bardeen, Press & Teukolsky 1972).
pub fn isco(a: f64) f64 {
    const oma2 = @max(0.0, 1.0 - a * a);
    const z1 = 1.0 + math.cbrt(oma2) * (math.cbrt(1.0 + a) + math.cbrt(@max(0.0, 1.0 - a)));
    const z2 = @sqrt(3.0 * a * a + z1 * z1);
    const s: f64 = if (a >= 0.0) 1.0 else -1.0;
    return 3.0 + z2 - s * @sqrt(@max(0.0, (3.0 - z1) * (3.0 + z1 + 2.0 * z2)));
}

/// Equatorial circular photon orbit radius (Bardeen 1973).
pub fn photonOrbit(a: f64, prograde: bool) f64 {
    const s: f64 = if (prograde) -a else a;
    return 2.0 * (1.0 + @cos(2.0 / 3.0 * math.acos(math.clamp(s, -1.0, 1.0))));
}

pub const Orbit = struct {
    om: f64,
    ut: f64,
    E: f64,
    L: f64,
};

/// Prograde circular equatorial Kerr geodesic quantities at radius r (M).
/// Inside the ISCO (plunging region), gas keeps its ISCO specific energy E and angular momentum L.
pub fn orbit(a: f64, r: f64) Orbit {
    const r_eff = @max(r, 1.48);
    const sr = @sqrt(r_eff);
    const v = 1.0 / sr;
    const v2 = v * v;
    const v3 = v2 * v;
    const q = @sqrt(@max(1e-15, 1.0 - 3.0 * v2 + 2.0 * a * v3));
    return .{
        .om = 1.0 / (r_eff * sr + a),
        .ut = (1.0 + a * v3) / q,
        .E = (1.0 - 2.0 * v2 + a * v3) / q,
        .L = sr * (1.0 - 2.0 * a * v3 + a * a * v2 * v2) / q,
    };
}

/// Kerr redshift factor g = E_obs / E_emit for a photon with E = 1 and axial angular momentum L
/// emitted by gas on a prograde circular equatorial orbit at radius r.
pub fn redshift(a: f64, r: f64, L: f64) f64 {
    const o = orbit(a, @max(r, R_ISCO));
    return 1.0 / (o.ut * (1.0 - o.om * L));
}

/// Chandrasekhar (1960) / Laor (1991) electron-scattering limb darkening I(mu) ~ 1 + 2.06 mu,
/// normalized so 2 * int_0^1 I(mu) mu dmu = 1, and blended to isotropic 1.0 in optically thin gas.
pub fn limbFactor(mu: f64, tau_vert: f64) f64 {
    const m = math.clamp(mu, 0.0, 1.0);
    const ld = (1.0 + LIMB_B * m) / (1.0 + (2.0 / 3.0) * LIMB_B);
    const thick_w = -math.expm1(-tau_vert);
    return 1.0 + (ld - 1.0) * thick_w;
}

/// Vertical optical depth profile tau_vert(r): includes a smooth trans-ISCO plunging tail
/// over [0.84 r_in, r_in] and tapers smoothly in the outer disk so the disk dissolves into
/// dark space without a geometric boundary seam.
pub fn opticalDepthVert(r: f64, r_in: f64) f64 {
    const r_plunge = r_in * 0.84;
    if (r <= r_plunge or r >= R_OUT) return 0.0;
    const u_in = math.clamp((r - r_plunge) / (r_in * 1.18 - r_plunge), 0.0, 1.0);
    const inner_taper = u_in * u_in * (3.0 - 2.0 * u_in);
    const x = @max(1.0, r / r_in);
    const outer_arg = @max(0.0, (r - 9.5) / 8.0);
    const outer_taper = @exp(-math.pow(f64, outer_arg, 2.35));
    return 85.0 * inner_taper * math.pow(f64, x, -1.35) * outer_taper;
}

pub const DiskSummary = struct {
    t_peak: f64 = 0.0,
    r_peak: f64 = 0.0,
    eta: f64 = 0.0,
};

/// Computes the exact Page & Thorne (1974) dimensionless flux f_PT(r) across PT_N log-spaced
/// nodes from r_in to r_out, and converts to effective temperature T_eff(r) in Kelvin for
/// NGC 4889 (M = 2.1e10 Msun, mdot = 0.010).
pub fn computePageThorneDisk(
    a: f64,
    r_in: f64,
    r_out: f64,
    f_pt_out: *[PT_N]f64,
    t_eff_out: *[PT_N]f64,
) DiskSummary {
    const dl = @log(r_out / r_in) / @as(f64, @floatFromInt(PT_N - 1));
    const eta = 1.0 - orbit(a, r_in).E;
    // Exact CGS scale: F(r) = (mdot * c^5) / (eta * kappa_es * G * M) * (r * f_PT(r))
    const flux_cgs_scale = (EDD_RATIO * math.pow(f64, C_LIGHT, 5.0)) /
        (eta * KAPPA_ES * G_NEWTON * M_SUN_CGS * BH_MASS_SUN);

    var integral: f64 = 0.0;
    f_pt_out[0] = 0.0;
    t_eff_out[0] = 0.0;

    var summary = DiskSummary{ .eta = eta };
    var prev_r = r_in;
    var prev_o = orbit(a, r_in);

    for (1..PT_N) |k| {
        const rk = r_in * @exp(dl * @as(f64, @floatFromInt(k)));
        const ok = orbit(a, rk);
        const sub_n: usize = 8;
        const dr = (rk - prev_r) / @as(f64, @floatFromInt(sub_n));
        var r_a = prev_r;
        var o_a = prev_o;
        for (0..sub_n) |_| {
            const r_b = r_a + dr;
            const o_b = orbit(a, r_b);
            const r_m = 0.5 * (r_a + r_b);
            const o_m = orbit(a, r_m);
            const dL = o_b.L - o_a.L;
            integral += (o_m.E - o_m.om * o_m.L) * dL;
            r_a = r_b;
            o_a = o_b;
        }
        const sr = @sqrt(rk);
        const dom_dr = -1.5 * sr / ((rk * sr + a) * (rk * sr + a));
        const denom = rk * (ok.E - ok.om * ok.L) * (ok.E - ok.om * ok.L);
        const f_dimless = @max(0.0, (-dom_dr / denom) * integral);
        f_pt_out[k] = f_dimless;

        const f_cgs = (rk * f_dimless) * flux_cgs_scale;
        const t_k = @sqrt(@sqrt(f_cgs / SIGMA_SB));
        t_eff_out[k] = t_k;
        if (t_k > summary.t_peak) {
            summary.t_peak = t_k;
            summary.r_peak = rk;
        }
        prev_r = rk;
        prev_o = ok;
    }
    return summary;
}

// ---------------------------------------------------------------- Kerr null geodesics

const V6 = @Vector(6, f64); // (r, theta, phi, t, p_r, p_theta)

fn rhs(a: f64, L: f64, y: V6) V6 {
    const r = y[0];
    const s0 = @sin(y[1]);
    const c = @cos(y[1]);
    const s = if (@abs(s0) < 1e-9) (if (s0 < 0.0) @as(f64, -1e-9) else 1e-9) else s0;
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

fn rk4k(a: f64, L: f64, y: V6, h: f64, k1: V6) V6 {
    const hv: V6 = @splat(h);
    const half: V6 = @splat(0.5 * h);
    const k2 = rhs(a, L, y + k1 * half);
    const k3 = rhs(a, L, y + k2 * half);
    const k4 = rhs(a, L, y + k3 * hv);
    const sixth: V6 = @splat(1.0 / 6.0);
    return y + hv * sixth * (k1 + (k2 + k3) * @as(V6, @splat(2.0)) + k4);
}

fn stepSize(g: *const Geo, L: f64, y: V6, d: V6) f64 {
    const r = y[0];
    var h: f64 = if (r > 200.0) 0.25 * r else if (r > 60.0) 0.1 * r else K_NEAR * @min(r, 4.0 * (r - g.rh));
    if (r < 200.0) {
        h = @min(h, 0.08 / @max(@abs(d[1]), 1e-12));
        h = @min(h, 0.08 / @max(@abs(d[2]), 1e-12));
        h = @min(h, (0.05 * @abs(@sin(y[1])) + math.clamp(0.01 * @abs(L), 1e-8, 2e-4)) / @max(@abs(d[1]), 1e-12));
    }
    return @max(h, math.clamp(0.01 * @abs(L), 1e-8, 1e-5));
}

fn project(a: f64, L: f64, y: V6) V6 {
    const s = @sin(y[1]);
    const s2 = @max(s * s, 1e-18);
    const r = y[0];
    const del = r * r - 2.0 * r + a * a;
    const P = r * r + a * a - a * L;
    const X = P * P / del - y[5] * y[5] - (L - a * s2) * (L - a * s2) / s2;
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
        return .{
            .a = a,
            .incl = incl,
            .sin_i = @sin(incl),
            .cos_i = @cos(incl),
            .rh = horizon(a),
            .r_in = isco(a) * 0.84,
            .r_out = r_out,
        };
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
    pth: f64 = 0,
};

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

pub fn traceNext(g: *const Geo, ray: *Ray, with_disk: bool) Hit {
    var y = ray.y;
    const L = ray.L;
    var n = ray.n;
    var steps = ray.steps;
    while (steps < MAX_STEPS) : (steps += 1) {
        const r = y[0];
        if (r < g.rh + 0.02) return .{ .kind = .hole, .steps = steps };
        if (with_disk) {
            if (y[4] > 0.0 and r > g.r_out + 1.5) return .{ .kind = .sky, .steps = steps };
        } else if (y[4] > 0.0 and r > 2.0e4) {
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
        const h = stepSize(g, L, y, k1);
        const prev = y;
        y = project(g.a, L, rk4k(g.a, L, y, h, k1));
        if (!math.isFinite(y[0]) or !math.isFinite(y[1])) return .{ .kind = .hole, .steps = steps };

        const e0 = @cos(prev[1]);
        const e1 = @cos(y[1]);
        if ((e0 < 0.0) != (e1 < 0.0)) {
            n +|= 1;
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
                return .{ .kind = .disk, .n = n, .r = rc, .ph = yc[2], .t = yc[3], .steps = steps, .pth = yc[5] };
            }
        }
    }
    return .{ .kind = .hole, .steps = steps };
}

fn dot3(a: [3]f64, b: [3]f64) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

// ---------------------------------------------------------------- CIE 1931 Planck colorimetry

fn lobe(l: f64, mu: f64, s1: f64, s2: f64) f64 {
    const t = (l - mu) / (if (l < mu) s1 else s2);
    return @exp(-0.5 * t * t);
}

/// CIE 1931 2-degree standard observer colour-matching functions (Wyman, Sloan & Shirley 2013).
fn cmf(l: f64) [3]f64 {
    return .{
        1.056 * lobe(l, 599.8, 37.9, 31.0) + 0.362 * lobe(l, 442.0, 16.0, 26.7) - 0.065 * lobe(l, 501.1, 20.4, 26.2),
        0.821 * lobe(l, 568.8, 46.9, 40.5) + 0.286 * lobe(l, 530.9, 16.3, 31.1),
        1.217 * lobe(l, 437.0, 11.8, 36.0) + 0.681 * lobe(l, 459.0, 26.0, 13.8),
    };
}

/// Linear sRGB radiance of a Planck blackbody at temperature T (K) integrated over 380-780 nm.
pub fn blackbodyRGB(T: f64) [3]f64 {
    if (T <= 100.0) return .{ 0.0, 0.0, 0.0 };
    var xyz = [3]f64{ 0.0, 0.0, 0.0 };
    var l: f64 = 380.0;
    while (l <= 780.0) : (l += 5.0) {
        const lum = l * 1e-3; // um
        const x = math.clamp(14387.77 / (lum * T), 1e-6, 500.0);
        const planck = 1.0 / (lum * lum * lum * lum * lum * math.expm1(x));
        const c = cmf(l);
        for (0..3) |i| xyz[i] += planck * c[i];
    }
    return .{
        @max(0.0, 3.2406 * xyz[0] - 1.5372 * xyz[1] - 0.4986 * xyz[2]),
        @max(0.0, -0.9689 * xyz[0] + 1.8758 * xyz[1] + 0.0415 * xyz[2]),
        @max(0.0, 0.0557 * xyz[0] - 0.2040 * xyz[1] + 1.0570 * xyz[2]),
    };
}

fn luma3(c: [3]f64) f64 {
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

fn srgbEncode(v: f64) f64 {
    const c = math.clamp(v, 0.0, 1.0);
    return if (c <= 0.0031308) 12.92 * c else 1.055 * math.pow(f64, c, 1.0 / 2.4) - 0.055;
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

fn hash2D(ix: i32, iy: i32, seed: u64) f64 {
    const ux: u64 = @as(u32, @bitCast(ix));
    const uy: u64 = @as(u32, @bitCast(iy));
    return unitf(mix64(seed ^ (ux *% 0x9E3779B1) ^ (uy *% 0x85EBCA77)));
}

/// Periodic 2D value noise on a torus [0..nx) x [0..ny).
fn periodicNoise2D(fx: f64, fy: f64, nx: i32, ny: i32, seed: u64) f64 {
    const x0f = @floor(fx);
    const y0f = @floor(fy);
    const tx = fx - x0f;
    const ty = fy - y0f;
    const ux = tx * tx * (3.0 - 2.0 * tx);
    const uy = ty * ty * (3.0 - 2.0 * ty);
    const ix0 = @mod(@as(i32, @intFromFloat(x0f)), nx);
    const iy0 = @mod(@as(i32, @intFromFloat(y0f)), ny);
    const ix1 = @mod(ix0 + 1, nx);
    const iy1 = @mod(iy0 + 1, ny);
    const v00 = hash2D(ix0, iy0, seed);
    const v10 = hash2D(ix1, iy0, seed);
    const v01 = hash2D(ix0, iy1, seed);
    const v11 = hash2D(ix1, iy1, seed);
    const a = v00 + (v10 - v00) * ux;
    const b = v01 + (v11 - v01) * ux;
    return a + (b - a) * uy;
}

// ---------------------------------------------------------------- per-pixel compact 8-byte record

/// 8-byte power-of-2 aligned record per pixel (`@sizeOf(PixelRec) == 8`).
/// The full continuous anti-aliased base image sits in `bg_pixels[idx]`; `PixelRec` drives the
/// live relativistic MRI turbulence and shearing hotspot modulation in `draw()` using pure
/// integer/fixed-point arithmetic for Platinum-tier (< 1,000 us) CPU rendering.
pub const PixelRec = extern struct {
    r_q: u16 = 0, // radial bin * 256 in [0 .. R_BINS * 256)
    phi_q: u16 = 0, // emission azimuth in [0 .. 65536)
    resp: u8 = 0, // turbulence/hotspot response weight [0..255] (0 = static pixel)
    warm_w: u8 = 0, // thermal blue-shift weight on positive flares [0..255]
    pad0: u8 = 0,
    pad1: u8 = 0,
};

pub const CornerSample = struct {
    kind: Kind = .sky,
    n: u8 = 0,
    r: f32 = 0.0,
    cphi: f32 = 1.0,
    sphi: f32 = 0.0,
    t: f32 = 0.0,
    pth: f32 = 0.0,
    L: f32 = 0.0,
    has_behind: bool = false,
};

// ---------------------------------------------------------------- State

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    t_m: f64,
    geo: Geo,
    lnr_in: f64,
    lnr_span: f64,
    t_peak_k: f64,
    cos_roll: f64,
    sin_roll: f64,

    // Precomputed radial disk profile & colorimetry tables
    f_pt: [PT_N]f64,
    t_eff: [PT_N]f64,
    bb_chroma: [BB_N][3]f32, // normalized Planck chromaticity (max channel == 1.0)
    srgb_lut: [SRGB_N]u8,

    // Polar MRI turbulence & hotspot tables updated in step(dt)
    om_bin: [R_BINS]f32,
    band_n0: [R_BINS]u8,
    band_w: [R_BINS][2]f32,
    noise_plane: [2][R_BINS][PHI_BINS]f32,
    polar_mod_q: [R_BINS][PHI_BINS]i16, // fixed-point modulation (256 == +1.0)

    // Framebuffers & active-pixel structures
    bg_pixels: [MAX_PIXELS]u32,
    recs: [MAX_PIXELS]PixelRec,
    row_x0: [MAX_H]u16,
    row_x1: [MAX_H]u16,
    corners: [(MAX_W / 4 + 2) * (MAX_H / 4 + 2)]CornerSample,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.t_m = 0.0;
        self.geo = Geo.init(SPIN, INCL, R_OUT);
        self.lnr_in = @log(R_MIN_TRACE);
        self.lnr_span = @log(R_OUT / R_MIN_TRACE);
        self.cos_roll = @cos(ROLL);
        self.sin_roll = @sin(ROLL);

        // 1. Precompute Page & Thorne (1974) disk profile for NGC 4889
        const summary = computePageThorneDisk(SPIN, R_ISCO, R_OUT, &self.f_pt, &self.t_eff);
        self.t_peak_k = summary.t_peak;

        // 2. Precompute CIE 1931 Planck chromaticity table and sRGB LUT
        const lmin = @log(BB_TMIN);
        const lspan = @log(BB_TMAX / BB_TMIN);
        for (0..BB_N) |i| {
            const u = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(BB_N - 1));
            const tk = @exp(lmin + lspan * u);
            const c = blackbodyRGB(tk);
            const luma = @max(1e-12, 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]);
            self.bb_chroma[i] = .{
                @floatCast(c[0] / luma),
                @floatCast(c[1] / luma),
                @floatCast(c[2] / luma),
            };
        }
        for (0..SRGB_N) |i| {
            const v = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(SRGB_N - 1));
            self.srgb_lut[i] = @intFromFloat(@round(srgbEncode(v) * 255.0));
        }

        // 3. Precompute radial orbital frequencies, lifetime band weights, and trailing spiral noise planes
        for (0..R_BINS) |b| {
            const u = (@as(f64, @floatFromInt(b)) + 0.5) / @as(f64, @floatFromInt(R_BINS));
            const r = @exp(self.lnr_in + self.lnr_span * u);
            const om = orbit(SPIN, r).om;
            self.om_bin[b] = @floatCast(om);
            const period = 2.0 * math.pi / om;
            const target_life = 0.09 * period;
            const bf = math.clamp(@log2(@max(1.0, target_life / BAND_L0)), 0.0, @as(f64, @floatFromInt(NBAND - 2)) - 0.001);
            const n0: usize = @intFromFloat(@floor(bf));
            const frac = bf - @as(f64, @floatFromInt(n0));
            const w0 = @cos(0.5 * math.pi * frac);
            const w1 = @sin(0.5 * math.pi * frac);
            self.band_n0[b] = @intCast(n0);
            self.band_w[b] = .{ @floatCast(w0), @floatCast(w1) };
        }

        // Build two octaves of open trailing logarithmic spiral filaments on (R_BINS x PHI_BINS)
        for (0..2) |oct| {
            const nr_cells: i32 = if (oct == 0) 5 else 10;
            const nphi_cells: i32 = if (oct == 0) 7 else 14;
            const spiral_pitch: f64 = if (oct == 0) 1.15 else 1.55; // open ~24 deg trailing spiral arms
            var sum: f64 = 0.0;
            var sum2: f64 = 0.0;
            const seed_base: u64 = 0x517CC1B727220A95 +% @as(u64, oct) *% 0x9E3779B97F4A7C15;
            for (0..R_BINS) |b| {
                const ur = (@as(f64, @floatFromInt(b)) + 0.5) / @as(f64, @floatFromInt(R_BINS));
                for (0..PHI_BINS) |p| {
                    const up = @as(f64, @floatFromInt(p)) / @as(f64, @floatFromInt(PHI_BINS));
                    const sp_phase = @mod(up + spiral_pitch * ur, 1.0);
                    const fx = ur * @as(f64, @floatFromInt(nr_cells));
                    const fy = sp_phase * @as(f64, @floatFromInt(nphi_cells));
                    const n1 = periodicNoise2D(fx, fy, nr_cells, nphi_cells, seed_base);
                    const n2 = periodicNoise2D(fx * 2.0 + 0.37, fy * 2.0 + 0.61, nr_cells * 2, nphi_cells * 2, seed_base ^ 0xA5A5A5A5);
                    // Blend smooth multi-arm spiral wave with organic filamentary noise
                    const wave = 0.5 + 0.5 * @cos(2.0 * math.pi * (3.0 * up + 4.2 * ur) + 2.2 * (n1 - 0.5));
                    const val = 0.55 * n1 + 0.25 * n2 + 0.20 * wave;
                    self.noise_plane[oct][b][p] = @floatCast(val);
                    sum += val;
                    sum2 += val * val;
                }
            }
            const count = @as(f64, @floatFromInt(R_BINS * PHI_BINS));
            const mean = sum / count;
            const std_dev = @sqrt(@max(1e-12, sum2 / count - mean * mean));
            for (0..R_BINS) |b| {
                for (0..PHI_BINS) |p| {
                    self.noise_plane[oct][b][p] = @floatCast((@as(f64, self.noise_plane[oct][b][p]) - mean) / std_dev);
                }
            }
        }

        // 4. Trace the Kerr spacetime image onto bg_pixels and recs
        self.traceFrame();
        self.step(0.0);

        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn chromaLookup(self: *const State, T: f64) [3]f64 {
        if (T <= BB_TMIN) return .{ 0.0, 0.0, 0.0 };
        const lmin = @log(BB_TMIN);
        const lspan = @log(BB_TMAX / BB_TMIN);
        const u = math.clamp((@log(T) - lmin) / lspan, 0.0, 1.0 - 1e-7);
        const idx_f = u * @as(f64, @floatFromInt(BB_N - 1));
        const idx: usize = @intFromFloat(idx_f);
        const frac = idx_f - @as(f64, @floatFromInt(idx));
        const c0 = self.bb_chroma[idx];
        const c1 = self.bb_chroma[@min(idx + 1, BB_N - 1)];
        return .{
            c0[0] + (c1[0] - c0[0]) * frac,
            c0[1] + (c1[1] - c0[1]) * frac,
            c0[2] + (c1[2] - c0[2]) * frac,
        };
    }

    /// Rest-frame temperature profile T_eff(r) with finite-ring outer cooling (Mummery & Balbus 2019)
    /// and smooth warm plunging-region transition inside the ISCO (Krolik et al. 2005).
    fn diskTempAt(self: *const State, r: f64) f64 {
        if (r <= R_MIN_TRACE or r >= R_OUT) return 0.0;
        if (r < R_ISCO * 1.15) {
            // Smooth bridge across the ISCO into the warm plunging region
            const r_ref = R_ISCO * 1.15;
            const u_ref = math.clamp((@log(r_ref) - @log(R_ISCO)) / @log(R_OUT / R_ISCO), 0.0, 1.0 - 1e-7);
            const k_ref: usize = @intFromFloat(u_ref * @as(f64, @floatFromInt(PT_N - 1)));
            const t_ref = self.t_eff[k_ref];
            const s = math.clamp((r - R_MIN_TRACE) / (r_ref - R_MIN_TRACE), 0.0, 1.0);
            return t_ref * math.pow(f64, s, 0.55);
        }
        const u = math.clamp((@log(r) - @log(R_ISCO)) / @log(R_OUT / R_ISCO), 0.0, 1.0 - 1e-7);
        const kf = u * @as(f64, @floatFromInt(PT_N - 1));
        const k: usize = @intFromFloat(kf);
        const frac = kf - @as(f64, @floatFromInt(k));
        const t_pt = self.t_eff[k] + (self.t_eff[@min(k + 1, PT_N - 1)] - self.t_eff[k]) * frac;
        // Finite-ring outer cooling beyond r = 3.2 M sweeps outer gas through gold/amber/crimson
        const outer_cool = @exp(-math.pow(f64, @max(0.0, (r - 3.2) / 9.2), 1.15));
        return t_pt * outer_cool;
    }

    inline fn screenToCamera(self: *const State, fx: f64, fy: f64) [2]f64 {
        const wf: f64 = @floatFromInt(@max(@as(usize, 1), self.w));
        const hf: f64 = @floatFromInt(@max(@as(usize, 1), self.h));
        const sx = (fx - 0.5 * wf) * (2.0 * HALF_H / hf);
        const sy = (0.5 * hf - fy) * (2.0 * HALF_H / hf);
        const alpha = sx * self.cos_roll - sy * self.sin_roll;
        const beta = sx * self.sin_roll + sy * self.cos_roll + BETA_CENTER;
        return .{ alpha, beta };
    }

    const ShadeHit = struct {
        total_rgb: [3]f64 = .{ 0.0, 0.0, 0.0 },
        prim_lum: f64 = 0.0,
        r: f64 = 0.0,
        ph_emit: f64 = 0.0,
        t_obs: f64 = 0.0,
        has_hit: bool = false,
    };

    /// Evaluates radiative transfer for a single crossing hit (r, ph, t, pth, L).
    /// Uses exact CIE 1931 Planck chromaticity at shifted colour temperature coupled with
    /// bolometric HDR intensity compression so 2,000-4,000 K amber/crimson regions are not
    /// crushed by the 40,000x visible Wien exponential cutoff relative to the 17,500 K crescent.
    fn shadeCrossing(self: *const State, r: f64, ph: f64, t: f64, pth: f64, L: f64) struct {
        rgb: [3]f64,
        alpha: f64,
        ph_emit: f64,
        t_obs: f64,
    } {
        const t_rest = self.diskTempAt(r);
        if (t_rest <= 400.0) return .{ .rgb = .{ 0.0, 0.0, 0.0 }, .alpha = 0.0, .ph_emit = 0.0, .t_obs = 0.0 };
        const g = redshift(SPIN, r, L);
        const mu = math.clamp(g * @abs(pth) / r, 0.035, 1.0);
        const tau_v = opticalDepthVert(r, R_ISCO);
        const tau_los = tau_v / mu;
        if (tau_los < 1e-4) return .{ .rgb = .{ 0.0, 0.0, 0.0 }, .alpha = 0.0, .ph_emit = 0.0, .t_obs = 0.0 };
        const alpha = if (tau_los > 30.0) 1.0 else -math.expm1(-tau_los);
        const limb = limbFactor(mu, tau_v);

        // Observed temperature g * T_eff(r); calibrated to astronomical starlight white balance
        // (0.68x chromaticity point so 11,610 K rest peak maps to 12,500 K sapphire on approaching
        // wing, 5,200 K champagne-gold on lensed arches, and 2,000-3,600 K amber/crimson on receding/outer disk)
        const t_obs = g * t_rest;
        const t_color = math.clamp(t_obs * 0.68, BB_TMIN, BB_TMAX);
        const chroma = self.chromaLookup(t_color);

        // Bolometric intensity F_obs ~ (g * T_rest)^4 compressed with HDR gamma = 0.52
        const t_norm = t_obs / @max(1.0, self.t_peak_k);
        const bol_hdr = math.pow(f64, @max(0.0, t_norm), 4.0 * 0.52);
        const w = 2.65 * alpha * limb * bol_hdr;

        const dt = t - T_REF;
        const om = orbit(SPIN, r).om;
        const ph_emit = ph - om * dt;
        return .{
            .rgb = .{ chroma[0] * w, chroma[1] * w, chroma[2] * w },
            .alpha = alpha,
            .ph_emit = ph_emit,
            .t_obs = t_color,
        };
    }

    /// Traces up to 3 equatorial disk crossings along ray (alpha, beta).
    fn traceAndShadeRay(self: *const State, alpha: f64, beta: f64) ShadeHit {
        const r2_screen = alpha * alpha + beta * beta;
        if (r2_screen > (R_OUT + 2.5) * (R_OUT + 2.5)) {
            return .{};
        }
        var ray = startRay(&self.geo, alpha, beta);
        var out = ShadeHit{};
        var trans: f64 = 1.0;

        for (0..3) |_| {
            const h = traceNext(&self.geo, &ray, true);
            if (h.kind != .disk) break;
            const sc = self.shadeCrossing(h.r, h.ph, h.t, h.pth, ray.L);
            if (sc.alpha > 1e-4) {
                const c0 = trans * sc.rgb[0];
                const c1 = trans * sc.rgb[1];
                const c2 = trans * sc.rgb[2];
                const lum = 0.2126 * c0 + 0.7152 * c1 + 0.0722 * c2;
                out.total_rgb[0] += c0;
                out.total_rgb[1] += c1;
                out.total_rgb[2] += c2;
                out.has_hit = true;
                if (lum > out.prim_lum) {
                    out.prim_lum = lum;
                    out.r = h.r;
                    out.ph_emit = sc.ph_emit;
                    out.t_obs = sc.t_obs;
                }
                trans *= (1.0 - sc.alpha);
                if (trans < 0.008) break;
            }
        }
        return out;
    }

    inline fn toneMapEncode(self: *const State, c_lin: [3]f64) u32 {
        const yl = 0.2126 * c_lin[0] + 0.7152 * c_lin[1] + 0.0722 * c_lin[2];
        // Hue-preserving Reinhard tone mapping with soft highlight shoulder
        const tm = (1.0 + 0.08 * yl) / (1.0 + yl);
        var rgb8: [3]u8 = undefined;
        inline for (0..3) |i| {
            const v = math.clamp(c_lin[i] * tm, 0.0, 1.0);
            const idx: usize = @intFromFloat(v * @as(f64, @floatFromInt(SRGB_N - 1)));
            rgb8[i] = self.srgb_lut[idx];
        }
        return sdk.packRGBA(rgb8[0], rgb8[1], rgb8[2]);
    }

    fn traceFrame(self: *State) void {
        const w = self.w;
        const h = self.h;
        const bg_dark = sdk.packRGBA(0, 0, 0);
        @memset(self.bg_pixels[0 .. w * h], bg_dark);
        @memset(self.recs[0 .. w * h], PixelRec{});
        for (0..h) |y| {
            self.row_x0[y] = @intCast(w);
            self.row_x1[y] = 0;
        }

        // Step 1: Trace 4x4 block corners
        const step_px: usize = 4;
        const cw = w / step_px + 2;
        const ch = h / step_px + 2;
        for (0..ch) |cy| {
            const py: f64 = @floatFromInt(@min(cy * step_px, h));
            for (0..cw) |cx| {
                const px: f64 = @floatFromInt(@min(cx * step_px, w));
                const ab = self.screenToCamera(px, py);
                const r2 = ab[0] * ab[0] + ab[1] * ab[1];
                const idx = cy * cw + cx;
                if (r2 > (R_OUT + 2.5) * (R_OUT + 2.5)) {
                    self.corners[idx] = .{ .kind = .sky };
                    continue;
                }
                var ray = startRay(&self.geo, ab[0], ab[1]);
                const hit1 = traceNext(&self.geo, &ray, true);
                if (hit1.kind != .disk) {
                    self.corners[idx] = .{ .kind = hit1.kind };
                } else {
                    const g = redshift(SPIN, hit1.r, ray.L);
                    const mu = math.clamp(g * @abs(hit1.pth) / hit1.r, 0.035, 1.0);
                    const tau_los = opticalDepthVert(hit1.r, R_ISCO) / mu;
                    var has_behind = false;
                    if (tau_los < 5.0) {
                        const hit2 = traceNext(&self.geo, &ray, true);
                        if (hit2.kind == .disk) has_behind = true;
                    }
                    self.corners[idx] = .{
                        .kind = .disk,
                        .n = hit1.n,
                        .r = @floatCast(hit1.r),
                        .cphi = @floatCast(@cos(hit1.ph)),
                        .sphi = @floatCast(@sin(hit1.ph)),
                        .t = @floatCast(hit1.t),
                        .pth = @floatCast(hit1.pth),
                        .L = @floatCast(ray.L),
                        .has_behind = has_behind,
                    };
                }
            }
        }

        // Step 2: Fill 4x4 blocks
        const by_count = (h + step_px - 1) / step_px;
        const bx_count = (w + step_px - 1) / step_px;

        for (0..by_count) |by| {
            const y0 = by * step_px;
            const y1 = @min(y0 + step_px, h);
            for (0..bx_count) |bx| {
                const x0 = bx * step_px;
                const x1 = @min(x0 + step_px, w);

                const c00 = self.corners[by * cw + bx];
                const c10 = self.corners[by * cw + bx + 1];
                const c01 = self.corners[(by + 1) * cw + bx];
                const c11 = self.corners[(by + 1) * cw + bx + 1];

                const ab_mid = self.screenToCamera(@floatFromInt(x0 + 2), @floatFromInt(y0 + 2));
                const r2_mid = ab_mid[0] * ab_mid[0] + ab_mid[1] * ab_mid[1];

                if (c00.kind == .sky and c10.kind == .sky and c01.kind == .sky and c11.kind == .sky) {
                    if (r2_mid > 64.0) continue;
                }
                if (c00.kind == .hole and c10.kind == .hole and c01.kind == .hole and c11.kind == .hole) {
                    const dx_sh = ab_mid[0] - 2.3;
                    const dy_sh = ab_mid[1];
                    if (dx_sh * dx_sh + dy_sh * dy_sh < 3.2 * 3.2) continue;
                }

                const same_order_disk = (c00.kind == .disk and c10.kind == .disk and c01.kind == .disk and c11.kind == .disk) and
                    (c00.n == c10.n and c00.n == c01.n and c00.n == c11.n) and
                    (!c00.has_behind and !c10.has_behind and !c01.has_behind and !c11.has_behind);

                var smooth_block = false;
                if (same_order_disk) {
                    const r_min = @min(@min(c00.r, c10.r), @min(c01.r, c11.r));
                    const r_max = @max(@max(c00.r, c10.r), @max(c01.r, c11.r));
                    const dot_p = @min(
                        c00.cphi * c11.cphi + c00.sphi * c11.sphi,
                        c10.cphi * c01.cphi + c10.sphi * c01.sphi,
                    );
                    if (r_min > @as(f32, @floatCast(R_ISCO * 1.18)) and (r_max - r_min) < 0.14 * r_min and dot_p > 0.96) {
                        smooth_block = true;
                    }
                }

                if (smooth_block) {
                    for (y0..y1) |py| {
                        const ty = (@as(f32, @floatFromInt(py - y0)) + 0.5) / 4.0;
                        for (x0..x1) |px| {
                            const tx = (@as(f32, @floatFromInt(px - x0)) + 0.5) / 4.0;
                            const w00 = (1.0 - tx) * (1.0 - ty);
                            const w10 = tx * (1.0 - ty);
                            const w01 = (1.0 - tx) * ty;
                            const w11 = tx * ty;

                            const r = w00 * c00.r + w10 * c10.r + w01 * c01.r + w11 * c11.r;
                            const cphi = w00 * c00.cphi + w10 * c10.cphi + w01 * c01.cphi + w11 * c11.cphi;
                            const sphi = w00 * c00.sphi + w10 * c10.sphi + w01 * c01.sphi + w11 * c11.sphi;
                            const ph = math.atan2(sphi, cphi);
                            const t = w00 * c00.t + w10 * c10.t + w01 * c01.t + w11 * c11.t;
                            const pth = w00 * c00.pth + w10 * c10.pth + w01 * c01.pth + w11 * c11.pth;
                            const L = w00 * c00.L + w10 * c10.L + w01 * c01.L + w11 * c11.L;

                            const sc = self.shadeCrossing(r, ph, t, pth, L);
                            if (sc.alpha > 1e-4) {
                                self.storePixel(px, py, sc.rgb, luma3(sc.rgb), r, sc.ph_emit, sc.t_obs);
                            }
                        }
                    }
                } else {
                    // Use 4x4 subpixel supersampling on shadow-edge / photon-ring discontinuity blocks
                    const is_shadow_edge = (!same_order_disk) and (r2_mid < 58.0);
                    for (y0..y1) |py| {
                        for (x0..x1) |px| {
                            if (is_shadow_edge) {
                                var rgb_acc = [3]f64{ 0.0, 0.0, 0.0 };
                                var r_acc: f64 = 0.0;
                                var cph_acc: f64 = 0.0;
                                var sph_acc: f64 = 0.0;
                                var tobs_acc: f64 = 0.0;
                                var w_sum: f64 = 0.0;

                                const sub4 = [4]f64{ 0.125, 0.375, 0.625, 0.875 };
                                for (sub4) |oy| {
                                    for (sub4) |ox| {
                                        const ab = self.screenToCamera(@as(f64, @floatFromInt(px)) + ox, @as(f64, @floatFromInt(py)) + oy);
                                        const sh = self.traceAndShadeRay(ab[0], ab[1]);
                                        if (sh.has_hit) {
                                            for (0..3) |c| rgb_acc[c] += 0.0625 * sh.total_rgb[c];
                                            const wt = @max(1e-6, sh.prim_lum);
                                            r_acc += wt * sh.r;
                                            cph_acc += wt * @cos(sh.ph_emit);
                                            sph_acc += wt * @sin(sh.ph_emit);
                                            tobs_acc += wt * sh.t_obs;
                                            w_sum += wt;
                                        }
                                    }
                                }
                                if (w_sum > 0.0) {
                                    const inv_w = 1.0 / w_sum;
                                    self.storePixel(
                                        px,
                                        py,
                                        rgb_acc,
                                        luma3(rgb_acc),
                                        r_acc * inv_w,
                                        math.atan2(sph_acc, cph_acc),
                                        tobs_acc * inv_w,
                                    );
                                }
                            } else {
                                const ab0 = self.screenToCamera(@as(f64, @floatFromInt(px)) + 0.5, @as(f64, @floatFromInt(py)) + 0.5);
                                const sh = self.traceAndShadeRay(ab0[0], ab0[1]);
                                if (sh.has_hit) {
                                    self.storePixel(px, py, sh.total_rgb, sh.prim_lum, sh.r, sh.ph_emit, sh.t_obs);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Step 3: Compute pixel footprint damping & response weight
        for (0..h) |py| {
            for (0..w) |px| {
                const idx = py * w + px;
                const rc = self.recs[idx];
                if (rc.resp == 0) continue;

                var max_dr: u32 = 0;
                var max_dphi: u32 = 0;
                const nbs = [4][2]isize{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
                for (nbs) |nb| {
                    const nx = @as(isize, @intCast(px)) + nb[0];
                    const ny = @as(isize, @intCast(py)) + nb[1];
                    if (nx < 0 or ny < 0 or nx >= @as(isize, @intCast(w)) or ny >= @as(isize, @intCast(h))) continue;
                    const nrc = self.recs[@as(usize, @intCast(ny)) * w + @as(usize, @intCast(nx))];
                    if (nrc.resp == 0) continue;
                    const dr: u32 = @abs(@as(i32, rc.r_q) - @as(i32, nrc.r_q));
                    const dph: u32 = @abs(@as(i32, @as(i16, @bitCast(rc.phi_q -% nrc.phi_q))));
                    max_dr = @max(max_dr, dr);
                    max_dphi = @max(max_dphi, dph);
                }
                const fr = @as(f32, @floatFromInt(max_dr)) / 384.0;
                const fp = @as(f32, @floatFromInt(max_dphi)) / 1024.0;
                const damp = 1.0 / @sqrt((1.0 + fr * fr) * (1.0 + fp * fp));
                const new_resp: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(rc.resp)) * damp));
                if (new_resp < 8) {
                    self.recs[idx].resp = 0;
                } else {
                    self.recs[idx].resp = @intCast(@min(255, new_resp));
                    if (px < self.row_x0[py]) self.row_x0[py] = @intCast(px);
                    if (px + 1 > self.row_x1[py]) self.row_x1[py] = @intCast(px + 1);
                }
            }
        }
    }

    fn storePixel(
        self: *State,
        px: usize,
        py: usize,
        total_rgb: [3]f64,
        prim_lum: f64,
        r: f64,
        ph_emit: f64,
        t_obs: f64,
    ) void {
        const idx = py * self.w + px;
        const base_px = self.toneMapEncode(total_rgb);
        self.bg_pixels[idx] = base_px;

        const max_ch = @max(base_px & 0xFF, @max((base_px >> 8) & 0xFF, (base_px >> 16) & 0xFF));
        if (max_ch < 5 or r <= R_ISCO * 0.96) return;

        const ur = math.clamp((@log(r) - self.lnr_in) / self.lnr_span, 0.0, 0.9999);
        const rq: u16 = @intFromFloat(ur * @as(f64, @floatFromInt(R_BINS * 256)));
        const ph_norm = @mod(ph_emit, 2.0 * math.pi) / (2.0 * math.pi);
        const phiq: u16 = @truncate(@as(u32, @intFromFloat(ph_norm * 65536.0)));

        // Contrast response weight: peaks in midtones, gentle compression in saturated core
        const yl = luma3(total_rgb);
        const share = math.clamp(prim_lum / @max(1e-9, yl), 0.0, 1.0);
        const reinhard_deriv = 1.0 / (1.0 + 0.55 * yl);
        const resp_f = math.clamp(share * reinhard_deriv * 195.0, 0.0, 255.0);

        // Warm regions (T_obs < 6500 K) shift toward golden-white on positive hotspots
        const warm_f = math.clamp((7500.0 - t_obs) / 5000.0, 0.0, 1.0) * 180.0;

        self.recs[idx] = .{
            .r_q = rq,
            .phi_q = phiq,
            .resp = @intFromFloat(@round(resp_f)),
            .warm_w = @intFromFloat(@round(warm_f)),
        };
    }

    // ---------------------------------------------------------------- per-frame step & draw

    pub fn step(self: *State, dt: f64) void {
        if (!(dt >= 0.0 and dt < 1.0)) return;
        self.t_m += dt * TIME_LAPSE;

        // 1. Staggered generation weights & offsets for each radial lifetime band
        var band_w_gen: [NBAND][2]f32 = undefined;
        var band_age: [NBAND][2]f32 = undefined;
        var band_roff: [2][NBAND][2]usize = undefined;
        var band_poff: [2][NBAND][2]f32 = undefined;

        for (0..NBAND) |n| {
            const life = BAND_L0 * math.pow(f64, 2.0, @floatFromInt(n));
            const q = self.t_m / life;
            const uf0 = q - @floor(q);
            const uf1 = q + 0.5 - @floor(q + 0.5);
            const k0: u64 = @intFromFloat(@floor(q));
            const k1: u64 = @intFromFloat(@floor(q + 0.5));

            band_w_gen[n][0] = @floatCast(@sin(math.pi * uf0));
            band_w_gen[n][1] = @floatCast(@abs(@cos(math.pi * uf0)));
            band_age[n][0] = @floatCast((uf0 - 0.35) * life);
            band_age[n][1] = @floatCast((uf1 - 0.35) * life);

            for (0..2) |oct| {
                const h0 = mix64((@as(u64, oct) << 48) ^ (@as(u64, n) << 32) ^ (k0 *% 2));
                const h1 = mix64((@as(u64, oct) << 48) ^ (@as(u64, n) << 32) ^ (k1 *% 2 + 1));
                band_roff[oct][n][0] = @intCast(h0 % R_BINS);
                band_poff[oct][n][0] = @floatCast(unitf(h0) * @as(f64, @floatFromInt(PHI_BINS)));
                band_roff[oct][n][1] = @intCast(h1 % R_BINS);
                band_poff[oct][n][1] = @floatCast(unitf(h1) * @as(f64, @floatFromInt(PHI_BINS)));
            }
        }

        // 2. Evaluate 2-octave MRI spiral turbulence with continuous azimuthal interpolation
        // (eliminates discrete integer bin steps between adjacent radial rings!)
        const phi_scale = @as(f32, @floatFromInt(PHI_BINS)) / (2.0 * math.pi);
        const phi_f = @as(f32, @floatFromInt(PHI_BINS));
        var mod_f: [R_BINS][PHI_BINS]f32 = undefined;

        for (0..R_BINS) |b| {
            const n0 = self.band_n0[b];
            const bw0 = self.band_w[b][0];
            const bw1 = self.band_w[b][1];
            const om = self.om_bin[b];
            const out_row = &mod_f[b];
            @memset(out_row, 0.0);

            inline for (0..2) |oct| {
                const oct_amp: f32 = if (oct == 0) 0.85 else 0.52;
                inline for (0..2) |bk| {
                    const nb = n0 + bk;
                    const bw = if (bk == 0) bw0 else bw1;
                    inline for (0..2) |gi| {
                        const gw = bw * band_w_gen[nb][gi] * oct_amp;
                        const shift_f = @mod(band_poff[oct][nb][gi] - om * band_age[nb][gi] * phi_scale + phi_f * 64.0, phi_f);
                        const s0: usize = @intFromFloat(@floor(shift_f));
                        const frac = shift_f - @as(f32, @floatFromInt(s0));
                        const w_a = gw * (1.0 - frac);
                        const w_b = gw * frac;
                        const r_idx = (b + band_roff[oct][nb][gi]) % R_BINS;
                        const src_row = &self.noise_plane[oct][r_idx];
                        for (0..PHI_BINS) |p| {
                            const idx0 = (p + s0) & (PHI_BINS - 1);
                            const idx1 = (idx0 + 1) & (PHI_BINS - 1);
                            out_row[p] += w_a * src_row[idx0] + w_b * src_row[idx1];
                        }
                    }
                }
            }
        }

        // 3. Add differentially shearing Kerr hotspots (plasma flares on circular geodesics)
        const span_bins = self.lnr_span / @as(f64, @floatFromInt(R_BINS));
        for (0..NSPOT) |j| {
            const shifted = self.t_m + @as(f64, @floatFromInt(j)) * SPOT_LIFE / @as(f64, @floatFromInt(NSPOT));
            const gen = @floor(shifted / SPOT_LIFE);
            const age = shifted - gen * SPOT_LIFE;
            const env = @sin(math.pi * age / SPOT_LIFE);
            const amp: f32 = @floatCast(@as(f64, SPOT_AMP) * env * env);
            if (amp < 0.01) continue;

            const hs = mix64(@as(u64, @intFromFloat(@max(0.0, gen))) *% 31 + j + 0x7F4A);
            const u = unitf(hs);
            const r_spot = R_ISCO * (1.15 + 3.2 * u * u);
            const rb_center = (@log(r_spot) - self.lnr_in) / span_bins;
            const wr = (SPOT_RAD_W / r_spot) / span_bins;
            const phi0 = 2.0 * math.pi * unitf(mix64(hs ^ 0x19));
            const om_center = orbit(SPIN, r_spot).om;
            const wp = @max(0.24, SPOT_RAD_W / r_spot + 0.004 * age);

            const b_lo: usize = @intFromFloat(@max(0.0, @floor(rb_center - 2.2 * wr)));
            const b_hi: usize = @intFromFloat(@min(@as(f64, @floatFromInt(R_BINS - 1)), @ceil(rb_center + 2.2 * wr)));
            var b = b_lo;
            while (b <= b_hi) : (b += 1) {
                const dr = (@as(f64, @floatFromInt(b)) + 0.5 - rb_center) / wr;
                const qr = dr * dr;
                if (qr >= 1.0) continue;
                const rad_profile: f32 = @floatCast((1.0 - qr) * (1.0 - qr));
                const om_b: f64 = self.om_bin[b];
                const ph_center = @mod(phi0 + om_center * age + (om_b - om_center) * 0.38 * age, 2.0 * math.pi);
                for (0..PHI_BINS) |p| {
                    const ph = (@as(f64, @floatFromInt(p)) + 0.5) * (2.0 * math.pi / @as(f64, @floatFromInt(PHI_BINS)));
                    var dph = ph - ph_center;
                    dph -= 2.0 * math.pi * @round(dph / (2.0 * math.pi));
                    const qp = (dph / wp) * (dph / wp);
                    if (qp < 1.0) {
                        const az_profile: f32 = @floatCast((1.0 - qp) * (1.0 - qp));
                        mod_f[b][p] += amp * rad_profile * az_profile * 2.1;
                    }
                }
            }
        }

        // 4. Radial [1, 2, 1] smoothing + log-normal conversion into fixed-point polar_mod_q
        for (0..R_BINS) |b| {
            const b_prev = if (b > 0) b - 1 else 0;
            const b_next = if (b + 1 < R_BINS) b + 1 else R_BINS - 1;
            for (0..PHI_BINS) |p| {
                const m = 0.25 * mod_f[b_prev][p] + 0.50 * mod_f[b][p] + 0.25 * mod_f[b_next][p];
                const ex = math.clamp(TURB_SIGMA * m - 0.5 * TURB_SIGMA * TURB_SIGMA, -1.2, 1.5);
                const mult = @exp(ex) - 1.0;
                self.polar_mod_q[b][p] = @intFromFloat(@round(math.clamp(mult * 256.0, -220.0, 600.0)));
            }
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        if (w == 0 or self.h == 0 or stride < w) return;
        const h: usize = @min(self.h, buf.len / stride);

        const last_buf_idx = (h - 1) * stride + (w - 1);
        const last_bg_idx = (h - 1) * w + (w - 1);
        const need_bg_fill = (buf[0] != self.bg_pixels[0] or
            buf[w - 1] != self.bg_pixels[w - 1] or
            buf[last_buf_idx] != self.bg_pixels[last_bg_idx] or
            buf[(h - 1) * stride] != self.bg_pixels[(h - 1) * w]);

        if (need_bg_fill) {
            for (0..h) |y| {
                const dst_row = buf[y * stride .. y * stride + w];
                @memcpy(dst_row, self.bg_pixels[y * w .. y * w + w]);
            }
        }

        for (0..h) |y| {
            const x0 = self.row_x0[y];
            const x1 = self.row_x1[y];
            if (x0 >= x1) continue;
            const dst_row = buf[y * stride .. y * stride + w];
            const bg_row = self.bg_pixels[y * w .. y * w + w];
            const rec_row = self.recs[y * w .. y * w + w];

            for (x0..x1) |x| {
                const rc = rec_row[x];
                if (rc.resp == 0) continue;

                // Pure integer bilinear lookup into polar_mod_q[128][256]
                const rb0: usize = @min(@as(usize, rc.r_q >> 8), R_BINS - 1);
                const rb1: usize = @min(rb0 + 1, R_BINS - 1);
                const fr: i32 = @intCast(rc.r_q & 0xFF);

                const p0: usize = (rc.phi_q >> 8) & (PHI_BINS - 1);
                const p1: usize = (p0 + 1) & (PHI_BINS - 1);
                const fp: i32 = @intCast(rc.phi_q & 0xFF);

                const m00: i32 = self.polar_mod_q[rb0][p0];
                const m01: i32 = self.polar_mod_q[rb0][p1];
                const m10: i32 = self.polar_mod_q[rb1][p0];
                const m11: i32 = self.polar_mod_q[rb1][p1];

                const m0 = (m00 * (256 - fp) + m01 * fp) >> 8;
                const m1 = (m10 * (256 - fp) + m11 * fp) >> 8;
                const mod_q = (m0 * (256 - fr) + m1 * fr) >> 8;

                const delta = (mod_q * @as(i32, rc.resp)) >> 8;
                const scale_r: u32 = @intCast(math.clamp(256 + delta, 40, 640));

                // Positive flares shift hotter (boosting green and blue slightly relative to red)
                const warm_boost: i32 = if (delta > 0) (delta * @as(i32, rc.warm_w)) >> 9 else 0;
                const scale_g: u32 = @intCast(math.clamp(256 + delta + (warm_boost >> 1), 40, 680));
                const scale_b: u32 = @intCast(math.clamp(256 + delta + warm_boost, 40, 720));

                const base = bg_row[x];
                const r0: u32 = base & 0xFF;
                const g0: u32 = (base >> 8) & 0xFF;
                const b0: u32 = (base >> 16) & 0xFF;

                const r8: u8 = @intCast(@min(@as(u32, 255), (r0 * scale_r) >> 8));
                const g8: u8 = @intCast(@min(@as(u32, 255), (g0 * scale_g) >> 8));
                const b8: u8 = @intCast(@min(@as(u32, 255), (b0 * scale_b) >> 8));

                dst_row[x] = sdk.packRGBA(r8, g8, b8);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return !math.isFinite(self.t_m) or !math.isFinite(self.t_peak_k);
    }

    /// ARGUS-BENCH claim probe: equatorial photon with signed impact parameter b (M, b > 0
    /// prograde), traced by traceRay from an equatorial camera at OBS_R.
    pub fn probeEquatorialRay(self: *const State, b: f64) sdk.RayProbe {
        _ = self;
        const g = Geo.init(SPIN, 0.5 * math.pi, R_OUT);
        const h = traceRay(&g, -b, 0.0, false);
        if (h.kind != .sky) return .{ .captured = true, .deflection = 0.0 };
        const st = initialState(&g, -b, 0.0);
        const d = rhs(g.a, st.L, st.y);
        var v0 = [3]f64{ d[0], OBS_R * d[2], -OBS_R * d[1] };
        const n0 = @sqrt(dot3(v0, v0));
        for (&v0) |*x| x.* /= n0;
        return .{ .captured = false, .deflection = math.acos(math.clamp(dot3(v0, h.dir), -1.0, 1.0)) };
    }
};

comptime {
    sdk.exportTheme(State);
}

// ============================================================================
// Physics & Numerical Verification Tests (`sdk.ledger`)
// ============================================================================

const testing = std.testing;
const LEDGER_SRC = "zig test themes/Gemini_4_Argon_Relativity.zig";

fn checkClaim(
    id: []const u8,
    text: []const u8,
    reference: []const u8,
    conditions: []const u8,
    quantity: []const u8,
    measured: f64,
    lo: ?f64,
    hi: ?f64,
) !void {
    try testing.expect(sdk.ledger(.{
        .id = id,
        .claim = text,
        .reference = reference,
        .conditions = conditions,
        .quantity = quantity,
        .measured = measured,
        .lo = lo,
        .hi = hi,
        .source = LEDGER_SRC,
    }));
}

fn nullInvariant(a: f64, L: f64, y: V6) f64 {
    const s = @sin(y[1]);
    const s2 = s * s;
    const r = y[0];
    const del = r * r - 2.0 * r + a * a;
    const P = r * r + a * a - a * L;
    return del * y[4] * y[4] + y[5] * y[5] - P * P / del + (L - a * s2) * (L - a * s2) / s2;
}

fn carterConstant(a: f64, L: f64, y: V6) f64 {
    const c = @cos(y[1]);
    const s = @sin(y[1]);
    return y[5] * y[5] - a * a * c * c + L * L * c * c / (s * s);
}

test "Kerr ISCO, radiative efficiency, and stationary orbital energy" {
    const ref = "Bardeen, Press & Teukolsky 1972, ApJ 178, 347";
    try checkClaim("ngc4889.isco.schwarzschild", "Schwarzschild ISCO is at 6 M", ref, "a = 0", "r_isco (M)", isco(0.0), 6.0 - 1e-12, 6.0 + 1e-12);
    try checkClaim("ngc4889.isco.spin094", "Prograde ISCO at a = 0.94 is 2.0239 M", ref, "a = 0.94", "r_isco (M)", isco(SPIN), 2.023, 2.025);
    const r = isco(SPIN);
    const eps = 1e-5;
    const dE = (orbit(SPIN, r * (1.0 + eps)).E - orbit(SPIN, r * (1.0 - eps)).E) / (2.0 * r * eps);
    try checkClaim("ngc4889.isco.stationary_energy", "Circular-orbit specific energy is stationary (dE/dr = 0) at the ISCO", ref, "a = 0.94, central diff eps = 1e-5", "|dE/dr|", @abs(dE), null, 1e-6);
    const eta = 1.0 - orbit(SPIN, r).E;
    try checkClaim("ngc4889.isco.efficiency", "Radiative efficiency 1 - E_isco at a = 0.94 is 17.92%", ref, "a = 0.94", "eta", eta, 0.178, 0.180);
}

test "Photon orbits and traced Schwarzschild shadow radius sqrt(27) M" {
    const ref = "Bardeen 1973; Synge 1966; Luminet 1979";
    try checkClaim("ngc4889.photon_orbit.schwarzschild", "Schwarzschild photon sphere is at 3 M", ref, "a = 0", "r_ph (M)", photonOrbit(0.0, true), 3.0 - 1e-12, 3.0 + 1e-12);
    const g = Geo.init(0.0, INCL, R_OUT);
    var lo: f64 = 4.0;
    var hi: f64 = 6.5;
    for (0..40) |_| {
        const mid = 0.5 * (lo + hi);
        if (traceRay(&g, 0.0, mid, false).kind == .hole) lo = mid else hi = mid;
    }
    try checkClaim("ngc4889.shadow.schwarzschild", "Traced Schwarzschild shadow radius matches sqrt(27) M", ref, "a = 0, i = 79 deg, r_obs = 1000 M", "|b - sqrt(27)| (M)", @abs(0.5 * (lo + hi) - @sqrt(27.0)), null, 2e-3);
}

test "Geodesic invariants: null condition H = 0 and Carter constant Q conserved" {
    const g = Geo.init(SPIN, INCL, R_OUT);
    const st = initialState(&g, -2.5, 3.8);
    var y = st.y;
    const L = st.L;
    const q0 = carterConstant(SPIN, L, y);
    var worst_h: f64 = 0.0;
    var worst_q: f64 = 0.0;
    for (0..3000) |_| {
        const r = y[0];
        if (r < g.rh + 0.05 or (y[4] > 0.0 and r > 200.0)) break;
        const k1 = rhs(SPIN, L, y);
        y = project(SPIN, L, rk4k(SPIN, L, y, stepSize(&g, L, y, k1), k1));
        worst_h = @max(worst_h, @abs(nullInvariant(SPIN, L, y)) / (r * r));
        worst_q = @max(worst_q, @abs(carterConstant(SPIN, L, y) - q0) / @abs(q0));
    }
    try checkClaim("ngc4889.geodesic.null", "Hamiltonian null condition |H|/r^2 stays below 1e-4", "Carter 1968 Kerr Hamiltonian", "a = 0.94, i = 79 deg, (alpha, beta) = (-2.5, 3.8)", "max |H|/r^2", worst_h, null, 1e-4);
    try checkClaim("ngc4889.geodesic.carter", "Carter constant Q is conserved within 1e-4", "Carter 1968 constant Q", "a = 0.94, i = 79 deg, (alpha, beta) = (-2.5, 3.8)", "max |dQ/Q|", worst_q, null, 1e-4);
}

test "Page-Thorne flux and NGC 4889 peak temperature" {
    var f_pt: [PT_N]f64 = undefined;
    var t_eff: [PT_N]f64 = undefined;
    const summary = computePageThorneDisk(SPIN, R_ISCO, 1.0e4, &f_pt, &t_eff);
    const ref = "Page & Thorne 1974, ApJ 191, 499; McConnell et al. 2011 (M = 2.1e10 Msun)";
    try checkClaim("ngc4889.disk.isco_zero", "Page-Thorne flux vanishes at the zero-torque ISCO boundary", ref, "a = 0.94, r = r_isco", "F(r_isco)", f_pt[0], 0.0, 0.0);
    try checkClaim("ngc4889.disk.t_peak", "Peak rest-frame disk temperature for M = 2.1e10 Msun, mdot = 0.010 is ~11,610 K", ref, "a = 0.94, M = 2.1e10 Msun, mdot = 0.010", "T_peak (K)", summary.t_peak, 11200.0, 12000.0);
    try checkClaim("ngc4889.disk.r_peak", "Peak flux occurs at r ~ 2.86 M", ref, "a = 0.94", "r_peak (M)", summary.r_peak, 2.75, 3.00);
}

test "Relativistic Doppler beaming and Planck colour ordering" {
    const g_app = redshift(SPIN, 4.0, 4.0 * @sin(INCL));
    const g_rec = redshift(SPIN, 4.0, -4.0 * @sin(INCL));
    try checkClaim("ngc4889.redshift.approaching", "Approaching prograde side (alpha < 0) is blueshifted (g > 1)", "Cunningham 1975 g = 1 / (u^t (1 - Omega L))", "a = 0.94, i = 79 deg, r = 4 M, alpha = -4 M", "g_approaching", g_app, 1.25, 1.65);
    try checkClaim("ngc4889.redshift.receding", "Receding side (alpha > 0) is redshifted (g < 1)", "Cunningham 1975 g = 1 / (u^t (1 - Omega L))", "a = 0.94, i = 79 deg, r = 4 M, alpha = +4 M", "g_receding", g_rec, 0.40, 0.75);

    const c_warm = blackbodyRGB(3000.0);
    const c_hot = blackbodyRGB(18000.0);
    try checkClaim("ngc4889.blackbody.warm", "3000 K blackbody is warm amber-red (R > G > B)", "Planck x CIE 1931", "T = 3000 K", "min(R - G, G - B)", @min(c_warm[0] - c_warm[1], c_warm[1] - c_warm[2]), 1e-6, null);
    try checkClaim("ngc4889.blackbody.blue", "18000 K blackbody is sapphire-blue (B > R)", "Planck x CIE 1931", "T = 18000 K", "B / R", c_hot[2] / c_hot[0], 1.2, null);

    var flux: f64 = 0.0;
    const n: usize = 10000;
    for (0..n) |i| {
        const mu = (@as(f64, @floatFromInt(i)) + 0.5) / @as(f64, @floatFromInt(n));
        flux += 2.0 * limbFactor(mu, 1e6) * mu / @as(f64, @floatFromInt(n));
    }
    try checkClaim("ngc4889.limb.flux_conservation", "Chandrasekhar limb darkening conserves isotropic flux", "Chandrasekhar 1960; Laor 1991", "tau = 1e6, 10000 midpoint nodes", "2 int_0^1 I(mu) mu dmu", flux, 1.0 - 1e-6, 1.0 + 1e-6);
}

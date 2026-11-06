// ============================================================================
// ARGUS WEB // web/cygnus/cygnus.wgsl
//
// src/gpu/opus_black_hole.metal ported to WGSL, kernel for kernel, line for line:
//
//   bh_meter      once  exposure: inner-disk luminance on a 192-wide grid
//   bh_trace      once  Kerr null geodesics, 2x2 samples per pixel (8x8 at edges and photon
//                       rings), in row tiles: per-pixel disk record + what lies behind gas
//   bh_footprint  once  each disk pixel's footprint on the disk (texture filtering)
//   bh_shade      every frame: turbulence, hot spots, translucency, tone map
//                 (compute into a texture, or fs_shade straight to the canvas)
//   bh_probe      kind of the first thing each (alpha, beta) ray meets (shadow-edge test)
//
// The Metal kernels already run in 32-bit floats (Apple GPUs have no f64), so the numerics
// carry over; what WGSL lacks is spelled out where it is used:
//   - no 8/16-bit types: the 6-byte record and the byte planes are packed into u32 words
//     (rec_a = rbin | phi << 16, rec_b = meta | lmu << 16 | ftr << 24; bfrac 4 and tq 2
//     pixels per word, written with atomicOr), 13 B/pixel + 2 B during the trace, as the app;
//   - no 64-bit integers: the sky's splitmix64 hash runs on (lo, hi) u32 pairs;
//   - round() is half-to-even in WGSL, half-away-from-zero in Metal: roundAway();
//   - no isfinite(): the exponent bits are tested.
// Struct layouts mirror src/gpu/bh_tables.zig (Static, Frame, TraceParams, View) byte for
// byte, so the theme's own wasm build fills them (web/cygnus/cygnus_wasm.zig).
// ============================================================================

const R_BINS: u32 = 384u;
const R_FRAC: u32 = 128u;
const NP: u32 = 1024u;
const NSPOT: u32 = 6u;
const EMIT_N: u32 = 1024u;
const EMIT_X0: f32 = -7.0;
const EMIT_X1: f32 = 4.0;
const NOISE_STD: f32 = 40.0;
const NR: u32 = 2048u;
const N_OCT: u32 = 2u;
const NBAND: u32 = 12u;
const OCT_NORM: f32 = 1.1467259;
const BB_N: u32 = 1024u;
const BB_TMIN: f32 = 300.0;
const BB_TMAX: f32 = 200000.0;
const PT_N: u32 = 4096u;

const OBS_R: f32 = 1000.0;
const T_REF: f32 = 1012.4292161968444;
const K_NEAR: f32 = 0.08;
const MAX_STEPS: u32 = 40000u;
const AXIS_FOLD_COS: f32 = 0.99500417;
const TAU_BEHIND: f32 = 40.0;
const TAU_MIN: f32 = 0.01;
const EMIT_FLOOR: f32 = 3e-4;
const EXPO_R: f32 = 24.0;
const STAR_GAIN: f32 = 0.8;
const STAR_CELL: f32 = 8.0e-3;
const STAR_FLUX: f32 = 60.0;
const SKY_GAIN: f32 = 0.010;
const TWO_PI: f32 = 6.283185307179586;
const PI: f32 = 3.141592653589793;

const KIND_SKY: u32 = 0u;
const KIND_DISK: u32 = 1u;
const KIND_HOLE: u32 = 2u;

const COV_MAX: u32 = 15u;
const FR_MAX: u32 = 31u;
const FP_MAX: u32 = 127u;
const REFINE: u32 = 8u;

const OUT_LINEAR: u32 = 0u;
const OUT_SRGB: u32 = 1u;
const OUT_PQ: u32 = 2u;
const OUT_EXT_SRGB: u32 = 3u; // web only: extended-range sRGB for an rgba16float canvas (toneMapping extended)
const PQ_REF_NITS: f32 = 100.0;

const LIMB_B: f32 = 2.06;
const MU_MIN: f32 = 0.0067;
const LMU_SCALE: f32 = 51.0;
const TURB_AA: f32 = 2.0;
const AA_R0: f32 = 6.0;
const AA_R1: f32 = 16.0;

/// The offline renderer's camera roll and azimuth (BH_CAMERA_MOVES in the Metal source).
override CAMERA_MOVES: bool = false;

struct TurbGen {
    w: f32,
    age_q: f32,
    rowoff: u32,
    phoff: u32,
}

// bh_tables.Frame (1320 B) is bound as a uniform of 83 vec4u (padded to 1328 B) and read by
// word offset: uniform arrays need a 16-byte stride, and TurbGen is exactly one vec4.
//   gen[j][n][g]  vec4 j * 24 + n * 2 + g   (w, age_q: f32; rowoff, phoff: u32)
//   spot_mask     words 192..287 (u8 x 384)   spot_rb 288   spot_wr 294   spot_wp 300
//   spot_amp 306  spot_q 312..314 (u16 x 6)   exposure 315  width 316  height 317
//   spot_age 318  spot_om 324
const FW_MASK: u32 = 192u;
const FW_RB: u32 = 288u;
const FW_WR: u32 = 294u;
const FW_WP: u32 = 300u;
const FW_AMP: u32 = 306u;
const FW_Q: u32 = 312u;
const FW_AGE: u32 = 318u;
const FW_OM: u32 = 324u;

// bh_tables.Static (35896 B). bb[k][c] = bb[k * 3 + c]; sband[j][b] = sband[j * R_BINS + b].
struct Static {
    lntau_tab: array<f32, 384>,
    lnem_tab: array<f32, 384>,
    emit_tab: array<f32, 1025>,
    lin8: array<f32, 256>,
    bb: array<f32, 3072>,
    sband: array<f32, 768>,
    om_row: array<f32, 2048>,
    cell_r0: f32,
    cell_p0: f32,
    turb_sigma: f32,
    rho_row: array<f32, 2>,
    rho_ph: array<f32, 2>,
    foot_cr: array<f32, 2>,
    foot_cp: array<f32, 2>,
    sky_gain: f32,
    fcol_follow: f32,
    srgb: array<u32, 1024>,
}

// bh_tables.TraceParams (128 B).
struct TraceParams {
    gal_n: vec4f,
    gal_c: vec4f,
    a: f32,
    sin_i: f32,
    cos_i: f32,
    incl: f32,
    rh: f32,
    r_in: f32,
    r_out: f32,
    lnr_in: f32,
    lnr_span: f32,
    lnt_span: f32,
    mpp: f32,
    pix_ang: f32,
    exposure: f32,
    width: u32,
    height: u32,
    row0: u32,
    grid_w: u32,
    grid_h: u32,
    spot_rmax: f32,
    roll: f32,
    phi0: f32,
    pad0: u32,
    pad1: u32,
    pad2: u32,
}

// bh_tables.View (32 B).
struct View {
    width: u32,
    height: u32,
    out_w: u32,
    out_h: u32,
    rows_done: u32,
    exposure: f32,
    headroom: f32,
    out_mode: u32,
}

// ---------------------------------------------------------------- bindings
// One module, several entry points: each pipeline binds only what its entry point uses
// (layout 'auto'), so the binding numbers below are shared but never all at once.

@group(0) @binding(0) var<uniform> P: TraceParams;
@group(0) @binding(1) var<storage, read> st: Static;
@group(0) @binding(2) var<storage, read> ttab: array<f32>;
// trace / footprint
@group(0) @binding(3) var<storage, read_write> rec_a: array<u32>;
@group(0) @binding(4) var<storage, read_write> bg_out: array<u32>;
@group(0) @binding(5) var<storage, read_write> tq_out: array<atomic<u32>>;
@group(0) @binding(6) var<storage, read_write> bfrac_out: array<atomic<u32>>;
@group(0) @binding(7) var<storage, read_write> rec_b: array<u32>;
// meter
@group(0) @binding(8) var<storage, read_write> lum: array<f32>;
// probe
@group(0) @binding(9) var<storage, read> probe_ab: array<vec2f>;
@group(0) @binding(10) var<storage, read_write> probe_kind: array<u32>;
// footprint reads the light-travel phase (written by bh_trace as atomics)
@group(0) @binding(11) var<storage, read> tq_in: array<u32>;
// shade
@group(1) @binding(0) var<storage, read> s_rec_a: array<u32>;
@group(1) @binding(1) var<storage, read> s_rec_b: array<u32>;
@group(1) @binding(2) var<storage, read> s_bg: array<u32>;
@group(1) @binding(3) var<storage, read> s_bfrac: array<u32>;
@group(1) @binding(4) var<storage, read> noise: array<u32>;
@group(1) @binding(5) var<uniform> frw: array<vec4u, 83>;
@group(1) @binding(6) var<uniform> v: View;
@group(1) @binding(7) var shade_out: texture_storage_2d<rgba8unorm, write>;
// The canvas's own texture, written by bh_shade_canvas every frame: rgba8unorm, or rgba16float for
// an HDR canvas (cygnus.js substitutes the format at the marker).
@group(2) @binding(0) var canvas_out: texture_storage_2d<rgba8unorm /*CANVAS_FORMAT*/, write>;

// ---------------------------------------------------------------- helpers

fn isFiniteF(x: f32) -> bool {
    return (bitcast<u32>(x) & 0x7f800000u) != 0x7f800000u;
}

// Metal's round(): halfway cases away from zero (WGSL's round() goes to even).
fn roundAway(x: f32) -> f32 {
    let t = trunc(x);
    if (abs(x - t) >= 0.5) {
        return t + sign(x);
    }
    return t;
}

fn copysignF(m: f32, s: f32) -> f32 {
    return bitcast<f32>((bitcast<u32>(m) & 0x7fffffffu) | (bitcast<u32>(s) & 0x80000000u));
}

// as_type<short>(ushort(x)): the low 16 bits, sign-extended.
fn s16(x: u32) -> i32 {
    return bitcast<i32>(x << 16u) >> 16u;
}

fn luma(c: vec3f) -> f32 {
    return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z;
}

fn bbAt(i: u32) -> vec3f {
    return vec3f(st.bb[i * 3u], st.bb[i * 3u + 1u], st.bb[i * 3u + 2u]);
}

fn bbLookup(T: f32) -> vec3f {
    if (!(T > BB_TMIN)) {
        return vec3f(0.0);
    }
    let x = log(T / BB_TMIN) / log(BB_TMAX / BB_TMIN) * f32(BB_N - 1u);
    let xi = u32(min(floor(x), f32(BB_N - 2u)));
    let f = min(x - f32(xi), 1.0);
    return bbAt(xi) * (1.0 - f) + bbAt(xi + 1u) * f;
}

fn fmodPos(x: f32, m: f32) -> f32 {
    return x - m * floor(x / m);
}

fn octAmp(j: u32) -> f32 {
    return select(0.5612310, 1.0, j == 0u);
}

// ---------------------------------------------------------------- shared-exponent colour

fn packRGB9E5(c_in: vec3f) -> u32 {
    let c = clamp(c_in, vec3f(0.0), vec3f(65408.0));
    let m = max(c.x, max(c.y, c.z));
    if (m < 1e-12) {
        return 0u;
    }
    var e = max(-16, i32(floor(log2(m)))) + 16;
    var denom = exp2(f32(e - 15 - 9));
    if (floor(m / denom + 0.5) >= 512.0) {
        denom *= 2.0;
        e += 1;
    }
    let q = vec3u(min(floor(c / denom + 0.5), vec3f(511.0)));
    return q.x | (q.y << 9u) | (q.z << 18u) | (u32(clamp(e, 0, 31)) << 27u);
}

fn unpackRGB9E5(x: u32) -> vec3f {
    let s = exp2(f32(i32(x >> 27u) - 15 - 9));
    return vec3f(f32(x & 511u), f32((x >> 9u) & 511u), f32((x >> 18u) & 511u)) * s;
}

// ---------------------------------------------------------------- Kerr geodesics (theme port)

struct V6 {
    p: vec3f, // r, theta, phi
    q: vec3f, // t, p_r, p_theta
}

fn v6add(x: V6, y: V6) -> V6 {
    return V6(x.p + y.p, x.q + y.q);
}
fn v6mul(x: V6, s: f32) -> V6 {
    return V6(x.p * s, x.q * s);
}

fn rhs(a: f32, L: f32, y: V6) -> V6 {
    let r = y.p.x;
    let s0 = sin(y.p.y);
    let c = cos(y.p.y);
    let s = select(s0, select(1e-9, -1e-9, s0 < 0.0), abs(s0) < 1e-9);
    let s2 = s * s;
    let a2 = a * a;
    let r2 = r * r;
    let sig = r2 + a2 * c * c;
    let del = r2 - 2.0 * r + a2;
    let Pp = r2 + a2 - a * L;
    let isig = 1.0 / sig;
    let idel = 1.0 / del;
    let pr = y.q.y;
    let dBdr = (2.0 * r - 2.0) * pr * pr - (4.0 * r * Pp * del - Pp * Pp * (2.0 * r - 2.0)) * idel * idel;
    let dBdth = (-2.0 * L * L / (s2 * s) + 2.0 * a2 * s) * c;
    return V6(
        vec3f(del * pr * isig, y.q.z * isig, -(a * Pp * idel + L / s2 - a) * isig),
        vec3f(-((r2 + a2) * Pp * idel + a * (L - a * s2)) * isig, -0.5 * dBdr * isig, -0.5 * dBdth * isig),
    );
}

fn rk4k(a: f32, L: f32, y: V6, h: f32, k1: V6) -> V6 {
    let k2 = rhs(a, L, v6add(y, v6mul(k1, 0.5 * h)));
    let k3 = rhs(a, L, v6add(y, v6mul(k2, 0.5 * h)));
    let k4 = rhs(a, L, v6add(y, v6mul(k3, h)));
    return v6add(y, v6mul(v6add(v6add(k1, v6mul(v6add(k2, k3), 2.0)), k4), h / 6.0));
}

fn stepSize(floor_th: f32, h_min: f32, y: V6, d: V6) -> f32 {
    let r = y.p.x;
    var h = select(select(K_NEAR * min(r, 4.0 * (r - P.rh)), 0.1 * r, r > 60.0), 0.25 * r, r > 200.0);
    if (r < 200.0) {
        h = min(h, 0.08 / max(abs(d.p.y), 1e-12));
        h = min(h, 0.08 / max(abs(d.p.z), 1e-12));
        h = min(h, (0.05 * abs(sin(y.p.y)) + floor_th) / max(abs(d.p.y), 1e-12));
    }
    return max(h, h_min);
}

fn project(a: f32, L: f32, y: V6) -> V6 {
    let s = sin(y.p.y);
    let s2 = max(s * s, 1e-18);
    let r = y.p.x;
    let del = r * r - 2.0 * r + a * a;
    let Pp = r * r + a * a - a * L;
    let X = Pp * Pp / del - y.q.z * y.q.z - (L - a * s2) * (L - a * s2) / s2;
    if (X < 0.05 * Pp * Pp / del) {
        return y;
    }
    let mag = sqrt(X / del);
    var o = y;
    o.q.y = select(mag, -mag, y.q.y < 0.0);
    return o;
}

struct Ray {
    y: V6,
    L: f32,
    n: u32,
    steps: u32,
    south: u32,
}

struct Hit {
    kind: u32,
    n: u32,
    r: f32,
    ph: f32,
    t: f32,
    dir: vec3f,
    pth: f32,
}

fn hitNone() -> Hit {
    return Hit(KIND_HOLE, 0u, 0.0, 0.0, 0.0, vec3f(0.0), 0.0);
}

fn startRay(alpha: f32, beta: f32) -> Ray {
    let a = P.a;
    let L = -alpha * P.sin_i;
    let r = OBS_R;
    let s2 = P.sin_i * P.sin_i;
    let del = r * r - 2.0 * r + a * a;
    let Pp = r * r + a * a - a * L;
    let f = (L - a * s2) * (L - a * s2) / s2;
    let pth = -beta;
    let X = Pp * Pp / del - pth * pth - f;
    let pr = -sqrt(max(X, 0.0) / del);
    let phi_obs = select(0.0, P.phi0, CAMERA_MOVES);
    return Ray(V6(vec3f(r, P.incl, phi_obs), vec3f(T_REF, pr, pth)), L, 0u, 0u, 0u);
}

fn traceNext(ray: ptr<function, Ray>, with_disk: bool) -> Hit {
    var y = (*ray).y;
    let L = (*ray).L;
    let a = P.a;
    var n = (*ray).n;
    var south = (*ray).south;
    let floor_th = clamp(0.01 * abs(L), 1e-8, 2e-4);
    let h_min = clamp(0.01 * abs(L), 1e-8, 1e-5);
    for (var steps = (*ray).steps; steps < MAX_STEPS; steps++) {
        let r = y.p.x;
        if (r < P.rh + 0.02) {
            return hitNone();
        }
        if (y.q.y > 0.0 && r > 2.0e4) {
            let d = rhs(a, L, y);
            let sg = select(1.0, -1.0, south != 0u);
            let s = sin(y.p.y);
            let c = sg * cos(y.p.y);
            let sp = sin(y.p.z);
            let cp = cos(y.p.z);
            let vr = d.p.x;
            let vt = sg * r * d.p.y;
            let vp = r * s * d.p.z;
            let vv = vec3f(vr * s * cp + vt * c * cp - vp * sp, vr * s * sp + vt * c * sp + vp * cp, vr * c - vt * s);
            return Hit(KIND_SKY, 0u, 0.0, 0.0, 0.0, normalize(vv), 0.0);
        }
        let k1 = rhs(a, L, y);
        let h = stepSize(floor_th, h_min, y, k1);
        let prev = y;
        y = project(a, L, rk4k(a, L, y, h, k1));
        if (!isFiniteF(y.p.x) || !isFiniteF(y.p.y)) {
            return hitNone();
        }
        let e0 = cos(prev.p.y);
        let e1 = cos(y.p.y);
        if ((e0 < 0.0) != (e1 < 0.0)) {
            n = min(n + 1u, 255u);
            var lo = 0.0;
            var hi = h;
            var flo = e0;
            var fhi = e1;
            var yc = y;
            for (var it = 0u; it < 4u; it++) {
                let hm = lo + (hi - lo) * flo / (flo - fhi);
                yc = rk4k(a, L, prev, hm, k1);
                let fm = cos(yc.p.y);
                if ((fm < 0.0) == (flo < 0.0)) {
                    lo = hm;
                    flo = fm;
                } else {
                    hi = hm;
                    fhi = fm;
                }
            }
            let rc = yc.p.x;
            if (with_disk && rc >= P.r_in && rc <= P.r_out) {
                (*ray).y = y;
                (*ray).n = n;
                (*ray).steps = steps + 1u;
                (*ray).south = south;
                return Hit(KIND_DISK, n, rc, yc.p.z, yc.q.x, vec3f(0.0), yc.q.z);
            }
        }
        if (e1 < -AXIS_FOLD_COS) {
            y = V6(vec3f(y.p.x, copysignF(PI, y.p.y) - y.p.y, y.p.z), vec3f(y.q.x, y.q.y, -y.q.z));
            south ^= 1u;
        }
    }
    return hitNone();
}

// ---------------------------------------------------------------- disk physics (theme port)

fn lnTab(base: u32, r: f32) -> f32 {
    let x = clamp(log(r / P.r_in) / P.lnt_span * f32(PT_N - 1u), 0.0, f32(PT_N - 1u) - 0.001);
    let xi = u32(x);
    let f = x - f32(xi);
    return ttab[base + xi] * (1.0 - f) + ttab[base + xi + 1u] * f;
}
fn tauExt(r: f32) -> f32 {
    return exp(lnTab(PT_N, r));
}
fn tauEm(r: f32) -> f32 {
    return exp(lnTab(2u * PT_N, r));
}
fn dilution(r: f32) -> f32 {
    return exp(lnTab(3u * PT_N, r));
}

fn limbFactor(lmu: f32, tau_ext: f32) -> f32 {
    let ld = (1.0 + LIMB_B * exp(-lmu)) / (2.0 * (0.5 + LIMB_B / 3.0));
    return 1.0 + (ld - 1.0) * (1.0 - exp(-tau_ext));
}

struct Orbit {
    om: f32,
    ut: f32,
}

fn orbitAt(a: f32, r: f32) -> Orbit {
    let sr = sqrt(r);
    let r32 = r * sr;
    let den = sqrt(r32) * sqrt(r32 - 3.0 * sr + 2.0 * a);
    return Orbit(1.0 / (r32 + a), (r32 + a) / den);
}

fn lnInvMu(alpha: f32, h: Hit) -> f32 {
    let o = orbitAt(P.a, h.r);
    let g = 1.0 / (o.ut * (1.0 - o.om * (-alpha * P.sin_i)));
    return -log(clamp(g * abs(h.pth) / h.r, MU_MIN, 1.0));
}

fn slantTau(alpha: f32, h: Hit) -> f32 {
    return tauExt(h.r) * exp(lnInvMu(alpha, h));
}

fn emitFrac(alpha: f32, h: Hit) -> f32 {
    let lmu = lnInvMu(alpha, h);
    let te = tauExt(h.r);
    return (1.0 - exp(-tauEm(h.r) * exp(lmu))) * limbFactor(lmu, te) * dilution(h.r);
}

fn colourFactor(T: f32) -> f32 {
    if (!(T > 3.0e4)) {
        return 1.0;
    }
    if (T < 1.0e5) {
        return pow(T / 3.0e4, 0.82);
    }
    return pow(72.0 / (T * 8.617333e-8), 1.0 / 9.0);
}

fn temperature(r: f32) -> f32 {
    let x = log(r / P.r_in) / P.lnt_span * f32(PT_N - 1u);
    if (!(x > 0.0)) {
        return 0.0;
    }
    let xi = u32(min(floor(x), f32(PT_N - 2u)));
    let f = x - f32(xi);
    return ttab[xi] * (1.0 - f) + ttab[xi + 1u] * f;
}

struct Sample {
    tobs: f32,
    tq: u32,
    rgb: vec3f,
    rbin: u32,
    phi: u32,
}

fn shadeDisk(alpha: f32, r: f32, ph: f32, t: f32) -> Sample {
    let L = -alpha * P.sin_i;
    let o = orbitAt(P.a, r);
    let g = 1.0 / (o.ut * (1.0 - o.om * L));
    let tobs = g * temperature(r);
    let rb = clamp((log(r) - P.lnr_in) / P.lnr_span * f32(R_BINS), 0.0, f32(R_BINS - 1u));
    let phe = fmodPos(ph - o.om * t, TWO_PI);
    let tturns = fmodPos(o.om * t / TWO_PI * 1024.0, 65536.0);
    return Sample(
        tobs,
        u32(min(tturns, 65535.0)),
        bbLookup(tobs),
        u32(min(rb * f32(R_FRAC), f32(R_BINS * R_FRAC - 1u))),
        u32(phe / TWO_PI * 65536.0) & 0xFFFFu,
    );
}

// ---------------------------------------------------------------- sky (theme port)
// 64-bit unsigned arithmetic on vec2u(lo, hi), for the splitmix64 hash.

fn mul32(a: u32, b: u32) -> vec2u { // full 64-bit product of two u32
    let a0 = a & 0xFFFFu;
    let a1 = a >> 16u;
    let b0 = b & 0xFFFFu;
    let b1 = b >> 16u;
    let p00 = a0 * b0;
    let p01 = a0 * b1;
    let p10 = a1 * b0;
    let p11 = a1 * b1;
    let mid = (p00 >> 16u) + (p01 & 0xFFFFu) + (p10 & 0xFFFFu);
    let lo = (p00 & 0xFFFFu) | (mid << 16u);
    let hi = p11 + (p01 >> 16u) + (p10 >> 16u) + (mid >> 16u);
    return vec2u(lo, hi);
}
fn mul64(a: vec2u, b: vec2u) -> vec2u {
    let p = mul32(a.x, b.x);
    return vec2u(p.x, p.y + a.x * b.y + a.y * b.x);
}
fn add64(a: vec2u, b: vec2u) -> vec2u {
    let lo = a.x + b.x;
    return vec2u(lo, a.y + b.y + select(0u, 1u, lo < a.x));
}
fn shr64(a: vec2u, s: u32) -> vec2u { // 0 < s < 32
    return vec2u((a.x >> s) | (a.y << (32u - s)), a.y >> s);
}
fn u64(x: u32) -> vec2u {
    return vec2u(x, 0u);
}
fn i64(x: i32) -> vec2u { // ulong(long(x)): sign-extended
    return vec2u(bitcast<u32>(x), select(0u, 0xFFFFFFFFu, x < 0));
}
fn mod100(a: vec2u) -> u32 { // (hi 2^32 + lo) mod 100; 2^32 mod 100 = 96
    return ((a.y % 100u) * 96u + a.x % 100u) % 100u;
}

fn mix64(x0: vec2u) -> vec2u {
    var z = add64(x0, vec2u(0x7F4A7C15u, 0x9E3779B9u));
    z = mul64(z ^ shr64(z, 30u), vec2u(0x1CE4E5B9u, 0xBF58476Du));
    z = mul64(z ^ shr64(z, 27u), vec2u(0x133111EBu, 0x94D049BBu));
    return z ^ shr64(z, 31u);
}

fn unitf(h: vec2u) -> f32 {
    return f32(h.y >> 8u) * (1.0 / 16777216.0);
}

fn latticeVal(ix: i32, iy: i32, iz: i32, seed: u32) -> f32 {
    return unitf(mix64(u64(seed) ^ mul64(i64(ix), u64(0x9E3779B1u)) ^ mul64(i64(iy), u64(0x85EBCA77u)) ^ mul64(i64(iz), u64(0xC2B2AE3Du))));
}

fn noise3(p: vec3f, seed: u32) -> f32 {
    let f = floor(p);
    let ix = i32(f.x);
    let iy = i32(f.y);
    let iz = i32(f.z);
    var u = p - f;
    u = u * u * (3.0 - 2.0 * u);
    var acc = 0.0;
    for (var c = 0u; c < 8u; c++) {
        let dx = i32(c & 1u);
        let dy = i32((c >> 1u) & 1u);
        let dz = i32((c >> 2u) & 1u);
        let wx = select(1.0 - u.x, u.x, dx == 1);
        let wy = select(1.0 - u.y, u.y, dy == 1);
        let wz = select(1.0 - u.z, u.z, dz == 1);
        acc += wx * wy * wz * latticeVal(ix + dx, iy + dy, iz + dz, seed);
    }
    return acc;
}

fn star(d: vec3f, foot: f32) -> vec3f {
    let G = 1.0 / STAR_CELL;
    let cc = floor(d * G);
    let ix = i32(cc.x);
    let iy = i32(cc.y);
    let iz = i32(cc.z);
    let hh = mix64(mul64(i64(ix), u64(0x9E37u)) ^ mul64(i64(iy), u64(0x85EBCA6Bu)) ^ mul64(i64(iz), u64(0xC2B2AE35u)));
    let lat = dot(d, P.gal_n.xyz);
    let prob = 30u + u32(45.0 * exp(-(lat / 0.12) * (lat / 0.12)));
    if (mod100(hh) >= prob) {
        return vec3f(0.0);
    }
    var p = vec3f(cc.x + 0.15 + 0.7 * unitf(mix64(hh ^ u64(1u))),
                  cc.y + 0.15 + 0.7 * unitf(mix64(hh ^ u64(2u))),
                  cc.z + 0.15 + 0.7 * unitf(mix64(hh ^ u64(3u)))) / G;
    p = normalize(p);
    let dd = d - p;
    let ang2 = dot(dd, dd);
    let fp = max(foot, P.pix_ang);
    let sig = 0.75 * fp;
    let u = unitf(mix64(hh ^ u64(4u)));
    let mu = (P.pix_ang / fp) * (P.pix_ang / fp);
    let bright = STAR_FLUX * (0.03 + 0.9 * u * u * u * u * u) * mu * exp(-ang2 / (sig * sig));
    if (bright < 1e-4) {
        return vec3f(0.0);
    }
    let col = bbLookup(3500.0 + 9000.0 * unitf(mix64(hh ^ u64(5u))));
    return bright * col / max(luma(col), 1e-12);
}

fn milkyWay(d: vec3f) -> vec3f {
    let lat = dot(d, P.gal_n.xyz);
    let band = exp(-(lat / 0.07) * (lat / 0.07));
    let dc = d - P.gal_c.xyz;
    let bulge = exp(-dot(dc, dc) / 0.004);
    if (band < 1e-3 && bulge < 1e-3) {
        return vec3f(0.0);
    }
    let nz = 0.6 * noise3(d * 25.0, 11u) + 0.4 * noise3(d * 80.0, 12u);
    let clumpy = 0.1 + 1.2 * nz * nz;
    let lane = exp(-(lat / 0.016) * (lat / 0.016));
    let dust = 1.0 - 0.75 * lane * clamp(1.6 * noise3(d * 45.0, 13u) - 0.3, 0.0, 1.0);
    let warm = bbLookup(4300.0);
    let cool = bbLookup(6200.0);
    let ib = SKY_GAIN * band * clumpy * dust;
    let iu = SKY_GAIN * 2.5 * bulge * dust;
    return ib * cool / max(luma(cool), 1e-12) + iu * warm / max(luma(warm), 1e-12);
}

fn sky(d: vec3f, foot: f32) -> vec3f {
    if (st.sky_gain <= 0.0) {
        return vec3f(0.0);
    }
    return (star(d, foot) + milkyWay(d)) * (STAR_GAIN * st.sky_gain);
}

// ---------------------------------------------------------------- trace kernels

fn behind(alpha: f32, b0: Hit, b1: Hit, foot: vec3f) -> vec3f {
    var acc = vec3f(0.0);
    var tr = 1.0;
    for (var i = 0u; i < 2u; i++) {
        var b = b1;
        if (i == 0u) {
            b = b0;
        }
        if (b.kind == KIND_HOLE) {
            break;
        }
        if (b.kind == KIND_SKY) {
            acc += tr * sky(b.dir, foot[i + 1u]);
            break;
        }
        let tau = slantTau(alpha, b);
        let s = shadeDisk(alpha, b.r, b.ph, b.t);
        acc += tr * s.rgb * (P.exposure * emitFrac(alpha, b));
        tr *= exp(-tau);
    }
    return acc;
}

fn imagePlane(fx: f32, fy: f32) -> vec2f {
    let u = (fx - 0.5 * f32(P.width)) * P.mpp;
    let w = (0.5 * f32(P.height) - fy) * P.mpp;
    if (CAMERA_MOVES && P.roll != 0.0) {
        let c = cos(P.roll);
        let s = sin(P.roll);
        return vec2f(c * u + s * w, c * w - s * u);
    }
    return vec2f(u, w);
}

fn alphaBeta(fx: f32, fy: f32) -> vec2f {
    var ab = imagePlane(fx, fy);
    if (abs(ab.x) < 1e-6) {
        ab.x = 1e-6;
    }
    return ab;
}

struct Px {
    bg: vec3f,
    cnt: array<u32, 3>,
    wcnt: array<f32, 3>,
    first: array<Sample, 3>,
    behind: array<vec3f, 3>,
    stat: array<vec3f, 3>,
    lmu: array<f32, 3>,
}

fn pxNew() -> Px {
    var px: Px;
    px.bg = vec3f(0.0);
    for (var o = 0u; o < 3u; o++) {
        px.cnt[o] = 0u;
        px.wcnt[o] = 0.0;
        px.first[o] = Sample(0.0, 0u, vec3f(0.0), 0u, 0u);
        px.lmu[o] = 0.0;
        px.behind[o] = vec3f(0.0);
        px.stat[o] = vec3f(0.0);
    }
    return px;
}

fn addSample(px: ptr<function, Px>, alpha: f32, h0_in: Hit, h1_in: Hit, h2_in: Hit, foot: vec3f) {
    var h0 = h0_in;
    var h1 = h1_in;
    var h2 = h2_in;
    var front_tr = 1.0;
    for (var layer = 0u; layer < 3u; layer++) {
        if (h0.kind == KIND_SKY) {
            (*px).bg += front_tr * sky(h0.dir, foot.x);
            return;
        }
        if (h0.kind != KIND_DISK) {
            return;
        }
        let lmu = lnInvMu(alpha, h0);
        let tau = tauExt(h0.r) * exp(lmu);
        let smp = shadeDisk(alpha, h0.r, h0.ph, h0.t);
        if (h0.r > P.spot_rmax) {
            let y0 = luma(smp.rgb);
            let peak_t = exp(2.6 * st.turb_sigma / 4.0);
            let boost = select(1.0, max(luma(bbLookup(smp.tobs * peak_t)) / y0, 1.0), y0 > 0.0);
            let ef = emitFrac(alpha, h0);
            let dim = y0 * ef * P.exposure * boost < EMIT_FLOOR;
            var promote = tau < TAU_MIN || dim;
            if (!promote && tau < TAU_BEHIND && h1.kind == KIND_DISK) {
                let sb = shadeDisk(alpha, h1.r, h1.ph, h1.t);
                if (y0 * ef < luma(sb.rgb) * emitFrac(alpha, h1) * exp(-tau)) {
                    (*px).bg += front_tr * smp.rgb * (P.exposure * ef);
                    promote = true;
                }
            }
            if (promote) {
                if (tau >= TAU_BEHIND) {
                    return;
                }
                front_tr *= exp(-tau);
                h0 = h1;
                h1 = h2;
                h2 = hitNone();
                continue;
            }
        }
        let o = min(h0.n, 3u) - 1u;
        if ((*px).cnt[o] == 0u) {
            (*px).first[o] = smp;
            (*px).lmu[o] = lmu;
        }
        (*px).cnt[o] += 1u;
        (*px).wcnt[o] += front_tr;
        let bh = behind(alpha, h1, h2, foot);
        (*px).behind[o] += front_tr * bh;
        (*px).stat[o] += front_tr * (smp.rgb * (P.exposure * emitFrac(alpha, h0)) + exp(-tau) * bh);
        return;
    }
}

@compute @workgroup_size(8, 8)
fn bh_meter(@builtin(global_invocation_id) gid: vec3u) {
    if (gid.x >= P.grid_w || gid.y >= P.grid_h) {
        return;
    }
    let fx = (f32(gid.x) + 0.5) * f32(P.width) / f32(P.grid_w);
    let fy = (f32(gid.y) + 0.5) * f32(P.height) / f32(P.grid_h);
    let ab = alphaBeta(fx, fy);
    var ray = startRay(ab.x, ab.y);
    let h = traceNext(&ray, true);
    var yl = 0.0;
    if (h.kind == KIND_DISK && h.r <= EXPO_R) {
        yl = luma(shadeDisk(ab.x, h.r, h.ph, h.t).rgb) * emitFrac(ab.x, h);
    }
    lum[gid.y * P.grid_w + gid.x] = yl;
}

// One sample of a 2x2 pixel: its front hit and up to two hits behind translucent gas.
struct Hits3 {
    h: array<Hit, 3>,
}

fn traceLayers(ab: vec2f) -> Hits3 {
    var out: Hits3;
    var ray = startRay(ab.x, ab.y);
    out.h[0] = traceNext(&ray, true);
    out.h[1] = hitNone();
    out.h[2] = hitNone();
    for (var i = 1u; i < 3u; i++) {
        let pv = out.h[i - 1u];
        if (pv.kind != KIND_DISK || slantTau(ab.x, pv) >= 2.0 * TAU_BEHIND) {
            break;
        }
        out.h[i] = traceNext(&ray, true);
    }
    return out;
}

@compute @workgroup_size(8, 8)
fn bh_trace(@builtin(global_invocation_id) gid: vec3u) {
    let x = gid.x;
    let y = gid.y + P.row0;
    if (x >= P.width || y >= P.height) {
        return;
    }

    var hits: array<Hits3, 4>;
    var alphas: array<f32, 4>;
    for (var s = 0u; s < 4u; s++) {
        let fx = f32(x) + (f32(s & 1u) + 0.5) * 0.5;
        let fy = f32(y) + (f32(s >> 1u) + 0.5) * 0.5;
        let ab = alphaBeta(fx, fy);
        alphas[s] = ab.x;
        hits[s] = traceLayers(ab);
    }

    var foot = vec3f(8.0 * P.pix_ang);
    var pairs = array<vec2u, 4>(vec2u(0u, 1u), vec2u(2u, 3u), vec2u(0u, 2u), vec2u(1u, 3u));
    for (var l = 0u; l < 3u; l++) {
        var m = 0.0;
        var got = false;
        for (var k = 0u; k < 4u; k++) {
            let h0 = hits[pairs[k].x].h[l];
            let h1 = hits[pairs[k].y].h[l];
            if (h0.kind != KIND_SKY || h1.kind != KIND_SKY) {
                continue;
            }
            m = max(m, length(h1.dir - h0.dir));
            got = true;
        }
        if (got) {
            foot[l] = max(m * 2.0, 0.25 * P.pix_ang);
        }
    }

    var refine = false;
    for (var l = 0u; l < 3u; l++) {
        for (var s = 1u; s < 4u; s++) {
            if (hits[s].h[l].kind != hits[0].h[l].kind || hits[s].h[l].n != hits[0].h[l].n) {
                refine = true;
            }
        }
        for (var s = 0u; s < 4u; s++) {
            if (hits[s].h[l].kind == KIND_DISK && hits[s].h[l].n >= select(3u, 2u, l == 0u)) {
                refine = true;
            }
        }
    }

    var px = pxNew();
    var N = 4u;
    if (!refine) {
        for (var s = 0u; s < 4u; s++) {
            addSample(&px, alphas[s], hits[s].h[0], hits[s].h[1], hits[s].h[2], foot);
        }
    } else {
        N = REFINE * REFINE;
        for (var row = 0u; row < REFINE; row++) {
            var hr: array<Hits3, REFINE>;
            var al: array<f32, REFINE>;
            var m = vec3f(0.0);
            var got = array<bool, 3>(false, false, false);
            for (var c = 0u; c < REFINE; c++) {
                let fx = f32(x) + (f32(c) + 0.5) / f32(REFINE);
                let fy = f32(y) + (f32(row) + 0.5) / f32(REFINE);
                let ab = alphaBeta(fx, fy);
                al[c] = ab.x;
                hr[c] = traceLayers(ab);
                if (c > 0u) {
                    for (var l = 0u; l < 3u; l++) {
                        if (hr[c].h[l].kind == KIND_SKY && hr[c - 1u].h[l].kind == KIND_SKY) {
                            m[l] = max(m[l], length(hr[c].h[l].dir - hr[c - 1u].h[l].dir));
                            got[l] = true;
                        }
                    }
                }
            }
            var rfoot = foot;
            for (var l = 0u; l < 3u; l++) {
                if (got[l]) {
                    rfoot[l] = max(m[l] * f32(REFINE), 0.25 * P.pix_ang);
                }
            }
            for (var c = 0u; c < REFINE; c++) {
                addSample(&px, al[c], hr[c].h[0], hr[c].h[1], hr[c].h[2], rfoot);
            }
        }
    }

    var p = -1;
    var covq = 0u;
    for (var o = 0; o < 3 && p < 0; o++) {
        let q = min((px.cnt[o] * COV_MAX + N / 2u) / N, COV_MAX);
        if (q > 0u) {
            p = o;
            covq = q;
        }
    }
    var beside = px.bg;
    for (var o = 0; o < 3; o++) {
        if (o != p) {
            beside += px.stat[o];
        }
    }
    var under = vec3f(0.0);
    var lmu_p = 0.0;
    if (p >= 0) {
        lmu_p = roundAway(clamp(px.lmu[p] * LMU_SCALE, 0.0, 255.0)) / LMU_SCALE;
        if (st.lntau_tab[px.first[p].rbin / R_FRAC] + lmu_p < log(TAU_BEHIND)) {
            under = px.behind[p];
        }
    }
    let bg_rgb = beside + under;
    let lt = luma(bg_rgb);
    let idx = y * P.width + x;
    bg_out[idx] = packRGB9E5(bg_rgb / f32(N));
    let bfrac = select(0u, u32(clamp(luma(under) / lt, 0.0, 1.0) * 255.0 + 0.5) & 0xFFu, lt > 1e-12);
    let lmuq = u32(lmu_p * LMU_SCALE + 0.5) & 0xFFu;
    var ftrq = 255u;
    var ra = 0u;
    var mt = 0u;
    var tqv = 0u;
    if (p >= 0) {
        if (px.cnt[p] > 0u) {
            ftrq = u32(clamp(px.wcnt[p] / f32(px.cnt[p]), 0.0, 1.0) * 255.0 + 0.5) & 0xFFu;
        }
        ra = (px.first[p].rbin & 0xFFFFu) | ((px.first[p].phi & 0xFFFFu) << 16u);
        mt = covq;
        tqv = px.first[p].tq & 0xFFFFu;
    }
    rec_a[idx] = ra;
    rec_b[idx] = mt | (lmuq << 16u) | (ftrq << 24u);
    if (bfrac != 0u) {
        atomicOr(&bfrac_out[idx >> 2u], bfrac << ((idx & 3u) * 8u));
    }
    if (tqv != 0u) {
        atomicOr(&tq_out[idx >> 1u], tqv << ((idx & 1u) * 16u));
    }
}

fn tqAt(i: u32) -> u32 {
    return (tq_in[i >> 1u] >> ((i & 1u) * 16u)) & 0xFFFFu;
}

// Each disk pixel's footprint on the disk, from its neighbours. Writes only the footprint bits
// of each record's meta (rec_b bits 4-15); neighbours read rbin, phi and the coverage, which no
// thread changes (as in the Metal kernel, a neighbour may read rec_b before or after its update:
// the coverage bits are the same either way).
@compute @workgroup_size(8, 8)
fn bh_footprint(@builtin(global_invocation_id) gid: vec3u) {
    if (gid.x >= P.width || gid.y >= P.height) {
        return;
    }
    let i = gid.y * P.width + gid.x;
    let rai = rec_a[i];
    let rbi = rec_b[i];
    let cov = rbi & COV_MAX;
    if (cov == 0u) {
        return;
    }
    let rbin_i = rai & 0xFFFFu;
    let phi_i = rai >> 16u;
    let tq_i = tqAt(i);
    var frr = 0u;
    var fp = 0u;
    var nb = array<vec2i, 4>(vec2i(1, 0), vec2i(-1, 0), vec2i(0, 1), vec2i(0, -1));
    for (var k = 0u; k < 4u; k++) {
        let q = vec2i(gid.xy) + nb[k];
        if (q.x < 0 || q.y < 0 || q.x >= i32(P.width) || q.y >= i32(P.height)) {
            continue;
        }
        let j = u32(q.y) * P.width + u32(q.x);
        if ((rec_b[j] & COV_MAX) == 0u) {
            continue;
        }
        let raj = rec_a[j];
        let tq_j = tqAt(j);
        let dr = (u32(abs(i32(raj & 0xFFFFu) - i32(rbin_i))) + R_FRAC / 4u - 1u) / (R_FRAC / 4u);
        let hit_i = (phi_i + ((tq_i << 6u) & 0xFFFFu)) & 0xFFFFu;
        let hit_j = ((raj >> 16u) + ((tq_j << 6u) & 0xFFFFu)) & 0xFFFFu;
        let d_hit = s16(hit_j - hit_i);
        let d_tq = s16(tq_j - tq_i);
        frr = max(frr, dr);
        fp = max(fp, u32(abs(d_hit - d_tq * 64)));
    }
    let frc = select(min(12u + (frr + 3u) / 4u, FR_MAX), frr, frr <= 16u);
    let mt = cov | (frc << 4u) | (min((fp + 63u) / 64u, FP_MAX) << 9u);
    rec_b[i] = (rbi & 0xFFFF0000u) | mt;
}

// ---------------------------------------------------------------- per-frame shading

fn oneMinusExpExp(x: f32) -> f32 {
    let xi = clamp((x - EMIT_X0) * (f32(EMIT_N) / (EMIT_X1 - EMIT_X0)), 0.0, f32(EMIT_N) - 0.001);
    let ii = u32(xi);
    return st.emit_tab[ii] + (st.emit_tab[ii + 1u] - st.emit_tab[ii]) * (xi - f32(ii));
}

fn frBins(code: u32) -> f32 {
    return select(f32(code) - 12.0, f32(code) * 0.25, code <= 16u);
}

fn vmix(a: f32, b: f32, t: f32, rho: f32) -> f32 {
    return ((1.0 - t) * a + t * b) * inverseSqrt((1.0 - t) * (1.0 - t) + t * t + 2.0 * t * (1.0 - t) * rho);
}

fn noiseByte(k: u32) -> f32 {
    return f32((noise[k >> 2u] >> ((k & 3u) * 8u)) & 0xFFu);
}

struct Oct {
    g: f32,
    v2: f32,
}

fn turbOctave(j: u32, phi: u32, r0: u32, tr: f32, sb: f32, rows_fp: f32, cells_per_q: f32, ep: f32) -> Oct {
    let plane = j * NR * NP;
    let n0 = min(u32(sb), NBAND - 2u);
    let beta = clamp(sb - f32(n0), 0.0, 1.0);
    let r1 = min(r0 + 1u, NR - 1u);
    let om0 = st.om_row[r0];
    let om1 = st.om_row[r1];
    let cp2 = st.foot_cp[j] * st.foot_cp[j];
    let base = 1.0 + ep * ep / cp2;
    let dom = abs(om1 - om0) * rows_fp * cells_per_q;
    var g = 0.0;
    var v2 = 0.0;
    for (var kk = 0u; kk < 2u; kk++) {
        let wb = select(sin(0.5 * PI * beta), cos(0.5 * PI * beta), kk == 0u);
        for (var gi = 0u; gi < 2u; gi++) {
            let tg = frw[j * 24u + (n0 + kk) * 2u + gi];
            let t = TurbGen(bitcast<f32>(tg.x), bitcast<f32>(tg.y), tg.z, tg.w);
            let smear = dom * t.age_q;
            let att = inverseSqrt(sqrt((base + smear * smear / cp2) / base));
            var vv: array<f32, 2>;
            for (var rr = 0u; rr < 2u; rr++) {
                let row = (select(r1, r0, rr == 0u) + t.rowoff) & (NR - 1u);
                let qf = f32((phi - t.phoff) & 0xFFFFu) - select(om1, om0, rr == 0u) * t.age_q;
                let pc = (qf - 65536.0 * floor(qf / 65536.0)) / 64.0;
                let p0 = min(u32(pc), NP - 1u);
                let p1 = (p0 + 1u) & (NP - 1u);
                vv[rr] = vmix(noiseByte(plane + row * NP + p0) - 128.0, noiseByte(plane + row * NP + p1) - 128.0, pc - f32(p0), st.rho_ph[j]);
            }
            g += wb * t.w * att * vmix(vv[0], vv[1], tr, st.rho_row[j]);
            v2 += (wb * t.w * att) * (wb * t.w * att);
        }
    }
    return Oct(g / NOISE_STD, v2);
}

fn fwU(w: u32) -> u32 {
    return frw[w >> 2u][w & 3u];
}
fn fwF(w: u32) -> f32 {
    return bitcast<f32>(fwU(w));
}

fn spotMask(rb: u32) -> u32 {
    return (fwU(FW_MASK + (rb >> 2u)) >> ((rb & 3u) * 8u)) & 0xFFu;
}

fn spotQ(j: u32) -> u32 {
    return (fwU(FW_Q + (j >> 1u)) >> ((j & 1u) * 16u)) & 0xFFFFu;
}

// Shade-pass reads of the trace (bound read-only in group 1). They need the trace's P too.
fn shadePre(x: u32, y: u32, exposure: f32) -> vec3f {
    let i = y * P.width + x;
    let bgv = unpackRGB9E5(s_bg[i]);
    let ra = s_rec_a[i];
    let rbw = s_rec_b[i];
    let ns = rbw & COV_MAX;
    if (ns == 0u) {
        return bgv;
    }
    let mt = rbw & 0xFFFFu;
    let fr_q = (mt >> 4u) & FR_MAX;
    let fp_q = (mt >> 9u) & FP_MAX;
    let rbin = ra & 0xFFFFu;
    let phi = ra >> 16u;

    let rb = rbin / R_FRAC;
    let rbf = f32(rbin) / f32(R_FRAC);
    let r = exp(P.lnr_in + P.lnr_span * rbf / f32(R_BINS));
    var L: f32;
    if (CAMERA_MOVES) {
        L = -imagePlane(f32(x) + 0.5, f32(y) + 0.5).x * P.sin_i;
    } else {
        L = -((f32(x) + 0.5 - 0.5 * f32(P.width)) * P.mpp) * P.sin_i;
    }
    let o = orbitAt(P.a, r);
    let tobs = temperature(r) / (o.ut * (1.0 - o.om * L));
    let frf = frBins(fr_q);
    let fpf = f32(fp_q) * 64.0;
    let prow = clamp(rbf * (f32(NR) / f32(R_BINS)) - 0.5, 0.0, f32(NR - 1u));
    let r0 = u32(prow);
    let trow = prow - f32(r0);
    let xb = clamp(rbf - 0.5, 0.0, f32(R_BINS - 1u) - 0.001);
    let b0 = u32(xb);
    let tb = xb - f32(b0);
    let w_aa = smoothstep(AA_R0 * P.r_in, AA_R1 * P.r_in, r);
    let aa = 1.0 + (TURB_AA - 1.0) * w_aa;
    var G = 0.0;
    var vr = 0.0;
    for (var j = 0u; j < N_OCT; j++) {
        let sc = f32(1u << j);
        let er = aa * frf * sc / st.cell_r0;
        let ep = fpf * sc / st.cell_p0;
        let a = octAmp(j) / OCT_NORM * inverseSqrt(sqrt((1.0 + er * er / (st.foot_cr[j] * st.foot_cr[j])) * (1.0 + ep * ep / (st.foot_cp[j] * st.foot_cp[j]))));
        if (a * st.turb_sigma < 0.002) {
            continue;
        }
        let sb = mix(st.sband[j * R_BINS + b0], st.sband[j * R_BINS + min(b0 + 1u, R_BINS - 1u)], tb);
        let oc = turbOctave(j, phi, r0, trow, sb, w_aa * aa * frf * (f32(NR) / f32(R_BINS)), sc / st.cell_p0, ep);
        G += a * oc.g;
        vr += a * a * oc.v2;
    }
    let eps = exp(st.turb_sigma * G - 0.5 * st.turb_sigma * st.turb_sigma * vr);
    let m1 = sqrt(sqrt(eps));
    let fol = st.fcol_follow > 0.0;
    let f0 = select(1.0, pow(max(dilution(r), 1e-30), -0.25), fol);
    let ts0 = temperature(r) / f0;
    let f1 = select(f0, colourFactor(ts0 * m1), fol);
    let tturb = tobs * m1 * f1 / f0;
    var k = exposure;

    let lmu_f = f32((rbw >> 16u) & 0xFFu) / LMU_SCALE;
    let lt_los = st.lntau_tab[rb] + lmu_f;
    let thin = lt_los < log(TAU_BEHIND);
    let emit = oneMinusExpExp(st.lnem_tab[rb] + lmu_f) * limbFactor(lmu_f, exp(st.lntau_tab[rb])) * dilution(r) *
        (f32(rbw >> 24u) / 255.0);
    let trans = 1.0 - oneMinusExpExp(lt_los);
    k *= emit * select(1.0, pow(f0 / f1, 4.0), fol);

    var spot_rgb = vec3f(0.0);
    var spot_scale = 0.0;
    let sm = spotMask(rb);
    if (sm != 0u) {
        var boost = 0.0;
        for (var j = 0u; j < NSPOT; j++) {
            if ((sm & (1u << j)) == 0u) {
                continue;
            }
            let r15 = r * sqrt(r) + P.a;
            let dom_dbin = 1.5 * sqrt(r) / (r15 * r15) * r * (P.lnr_span / f32(R_BINS));
            let smear = dom_dbin * fwF(FW_AGE + j) * (65536.0 / TWO_PI) * (frf + 0.5);
            let wr2 = fwF(FW_WR + j) * fwF(FW_WR + j) + frf * frf;
            let wp2 = fwF(FW_WP + j) * fwF(FW_WP + j) + fpf * fpf + smear * smear;
            let dr = rbf - fwF(FW_RB + j);
            let shear = (o.om - fwF(FW_OM + j)) * fwF(FW_AGE + j) * (65536.0 / TWO_PI);
            let dp0 = f32(s16(phi - spotQ(j))) - shear;
            let dp = dp0 - 65536.0 * roundAway(dp0 / 65536.0);
            if (fp_q == FP_MAX || fr_q == FR_MAX || fpf > 2.0 * fwF(FW_WP + j) || frf > 2.0 * fwF(FW_WR + j)) {
                continue;
            }
            let q = dr * dr / wr2 + dp * dp / wp2;
            if (q < 1.0) {
                boost += fwF(FW_AMP + j) * (1.0 - q) * (1.0 - q) * fwF(FW_WR + j) * fwF(FW_WP + j) / sqrt(wr2 * wp2);
            }
        }
        if (boost > 1e-3 && tobs > 0.0) {
            let m2 = sqrt(sqrt(1.0 + boost));
            let f2 = select(f1, colourFactor(ts0 * m1 * m2), fol);
            spot_rgb = bbLookup(tobs * m1 * m2 * f2 / f0) * select(1.0, pow(f1 / f2, 4.0), fol);
            spot_scale = 1.0;
        } else {
            k *= 1.0 + boost;
        }
    }

    let c = select(bbLookup(tturb), spot_rgb, spot_scale > 0.0) * k;
    let cov = f32(ns) / f32(COV_MAX);
    let f = f32((s_bfrac[i >> 2u] >> ((i & 3u) * 8u)) & 0xFFu) / 255.0;
    if (thin) {
        return cov * c + (1.0 - f * (1.0 - trans)) * bgv;
    }
    return cov * c + bgv;
}

fn srgbEncode(x: f32) -> f32 {
    return select(1.055 * pow(x, 1.0 / 2.4) - 0.055, 12.92 * x, x <= 0.0031308);
}

fn pqEncode(c: vec3f) -> vec3f {
    let c2020 = vec3f(dot(vec3f(0.6274040, 0.3292820, 0.0433136), c),
                      dot(vec3f(0.0690970, 0.9195400, 0.0113612), c),
                      dot(vec3f(0.0163916, 0.0880132, 0.8955950), c));
    let Lp = pow(clamp(c2020 * (PQ_REF_NITS / 10000.0), vec3f(0.0), vec3f(1.0)), vec3f(0.1593017578125));
    return pow((0.8359375 + 18.8515625 * Lp) / (1.0 + 18.6875 * Lp), vec3f(78.84375));
}

fn toneMap(c: vec3f, headroom: f32) -> vec3f {
    return c / (1.0 + luma(c) / headroom);
}

// bh_shade's body: output pixel -> traced pixel, shaded, tone mapped, encoded.
fn shadeOut(gx: u32, gy: u32) -> vec4f {
    let x = min(u32((f32(gx) + 0.5) * f32(v.width) / f32(v.out_w)), v.width - 1u);
    let y = min(u32((f32(gy) + 0.5) * f32(v.height) / f32(v.out_h)), v.height - 1u);
    var c = vec3f(0.0);
    if (y < v.rows_done) {
        c = toneMap(shadePre(x, y, v.exposure), max(v.headroom, 1.0));
    }
    c = max(c, vec3f(0.0));
    if (v.out_mode == OUT_SRGB) {
        c = vec3f(srgbEncode(min(c.x, 1.0)), srgbEncode(min(c.y, 1.0)), srgbEncode(min(c.z, 1.0)));
    } else if (v.out_mode == OUT_PQ) {
        c = pqEncode(c);
    } else if (v.out_mode == OUT_EXT_SRGB) {
        c = vec3f(srgbEncode(c.x), srgbEncode(c.y), srgbEncode(c.z));
    }
    return vec4f(c, 1.0);
}

@compute @workgroup_size(16, 8)
fn bh_shade(@builtin(global_invocation_id) gid: vec3u) {
    if (gid.x >= v.out_w || gid.y >= v.out_h) {
        return;
    }
    textureStore(shade_out, gid.xy, shadeOut(gid.x, gid.y));
}

// The same shade straight into the canvas texture (what frame() runs).
@compute @workgroup_size(16, 8)
fn bh_shade_canvas(@builtin(global_invocation_id) gid: vec3u) {
    if (gid.x >= v.out_w || gid.y >= v.out_h) {
        return;
    }
    textureStore(canvas_out, gid.xy, shadeOut(gid.x, gid.y));
}

// The same shade as a fragment shader (opts.fragment): measured 2.3x slower than the compute
// kernel at 3024x1964 in Chrome on an M3, kept for canvases without storage usage.
@vertex
fn vs_full(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
    let q = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
    return vec4f(q * 2.0 - 1.0, 0.0, 1.0);
}

@fragment
fn fs_shade(@builtin(position) pos: vec4f) -> @location(0) vec4f {
    return shadeOut(u32(pos.x), u32(pos.y));
}

@compute @workgroup_size(64)
fn bh_probe(@builtin(global_invocation_id) gid: vec3u) {
    if (gid.x >= arrayLength(&probe_kind)) {
        return;
    }
    var ray = startRay(probe_ab[gid.x].x, probe_ab[gid.x].y);
    probe_kind[gid.x] = traceNext(&ray, false).kind;
}

// Does nothing: a non-empty pass after the canvas copy carries the end timestamp of a frame
// (an empty pass's timestamps may be skipped).
@compute @workgroup_size(1)
fn bh_nop() {
}

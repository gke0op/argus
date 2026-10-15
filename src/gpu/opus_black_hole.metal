// ============================================================================
// ARGUS GPU // src/gpu/opus_black_hole.metal
//
// themes/Opus_Black_Hole.zig on the GPU, at the window's native resolution:
//
//   bh_meter      once  exposure: inner-disk luminance on a 192-wide grid
//   bh_trace      once  Kerr null geodesics, 2x2 samples per pixel, in row tiles:
//                       per-pixel disk record + what lies behind translucent gas
//   bh_footprint  once  each disk pixel's footprint on the disk (texture filtering)
//   bh_shade      every frame: turbulence, hot spots, translucency, HDR tone map
//
// The trace is the theme's own (`traceNext`, `traceLayers`, `render`, `behind`, the
// sky, `shadeDisk`) ported line by line in 32-bit floats; the per-frame tables come
// from the theme's step(). Apple GPUs have no f64: the camera is far (r = 1000 M), so
// the time coordinate starts at T_REF and only relative delays accumulate, and p_r is
// re-solved from the null condition every step (`project`), as on the CPU.
// Constants mirror the theme's private ones.
// ============================================================================

#include <metal_stdlib>
using namespace metal;

constant uint R_BINS = 384;
constant uint R_FRAC = 128;
constant uint NP = 1024;
constant uint NSPOT = 6;
constant uint EMIT_N = 1024;
constant float EMIT_X0 = -7.0f;
constant float EMIT_X1 = 4.0f;
constant float TURB = 0.4f;
constant float TAU_NOISE = 1.2f;
constant uint BB_N = 1024;
constant float BB_TMIN = 300.0f;
constant float BB_TMAX = 80000.0f;
constant uint PT_N = 4096;

constant float OBS_R = 1000.0f;
constant float T_REF = 1012.4292161968444f; // OBS_R + 2 ln(OBS_R / 2)
constant float K_NEAR = 0.08f;
constant uint MAX_STEPS = 40000;
constant float R_C = 5.0f;
constant float TAU0 = 220.0f;
// Gas denser than this is drawn opaque. The theme uses TAU_THICK * e^TAU_NOISE = 16.6, which
// hides a leak of e^-5 behind stirred gas: fine against the sky, but here light is composited
// before tone mapping and the inner disk behind can be ~50x display white, so a leak that size
// shows as sparkles along the threshold. At 40 the leak stays under ~3e-4 of display white.
constant float TAU_BEHIND = 40.0f;
constant float TAU_MIN = 0.01f;
constant float EMIT_FLOOR = 3e-4f;
constant float SPOT_RMAX = 12.0f;
constant float EXPO_R = 24.0f;
constant float STAR_GAIN = 0.8f;
constant float STAR_CELL = 8.0e-3f;
constant float STAR_FLUX = 60.0f;
constant float SKY_GAIN = 0.010f;
constant float TWO_PI = 6.283185307179586f;

constant uint KIND_SKY = 0;
constant uint KIND_DISK = 1;
constant uint KIND_HOLE = 2;

// One traced pixel in 6 bytes (the theme's Rec, minus what bh_shade can recompute):
//   rbin  radial bin in 1/R_FRAC bins (the radius, so the temperature and redshift follow)
//   phi   emission azimuth + Omega * travel time, Q16 of 2 pi
//   meta  coverage (0-15, /15) | radial footprint (r-bins, 5 bits) << 4 | azimuthal (64/65536 turn, 7 bits) << 9
// The light-travel phase (the theme's tq) is only needed for the footprint pass; it lives
// in a temporary buffer freed once the trace is done.
struct Rec {
    ushort rbin;
    ushort phi;
    ushort meta;
};
static_assert(sizeof(Rec) == 6, "Rec must stay 6 bytes");
constant uint COV_MAX = 15;
constant uint FR_MAX = 31;  // saturated: texture is filtered to ~6% and hot spots are unresolved
constant uint FP_MAX = 127; // saturated: the pixel spans too much azimuth to resolve a hot spot
constant uint REFINE = 8;   // photon-ring pixels: REFINE x REFINE samples instead of 2 x 2

// Per-frame tables written by the theme's step().
struct Frame {
    ushort gshift[2][R_BINS];
    ushort grow[2][R_BINS];
    uchar spot_mask[R_BINS];
    float spot_rb[NSPOT];
    float spot_wr[NSPOT];
    float spot_wp[NSPOT];
    float spot_amp[NSPOT];
    ushort spot_q[NSPOT];
    float gw[2];
    float gnorm;
    float exposure;
    float tau_behind;
    uint width;
    uint height;
    float spot_age[NSPOT]; // M since birth: the shear
    float spot_om[NSPOT];  // Omega at the birth radius
};

// Static tables built once by the theme's init().
struct Static {
    float tau_tab[R_BINS];
    float lntau_tab[R_BINS];
    float emit_tab[EMIT_N + 1];
    float lin8[256];
    float bb[BB_N][3];
    uchar srgb[4096];
};

// Mirrors bh_tables.TraceParams.
struct TraceParams {
    float4 gal_n;
    float4 gal_c;
    float a, sin_i, cos_i, incl, rh, r_in, r_out, lnr_in, lnr_span, lnt_span, mpp, pix_ang, exposure;
    uint width, height, row0, grid_w, grid_h, pad0, pad1;
};

// Mirrors bh_tables.View.
struct View {
    uint width, height, out_w, out_h, rows_done;
    float exposure, headroom;
    uint out_mode; // OUT_LINEAR, OUT_SRGB or OUT_PQ
};
constant uint OUT_LINEAR = 0; // extended-range linear sRGB (RGBA16F)
constant uint OUT_SRGB = 1;   // 8-bit sRGB (menu previews, SDR)
constant uint OUT_PQ = 2;     // HDR10: BT.2020 primaries, PQ, 10-bit
constant float PQ_REF_NITS = 100.0f; // display white (EDR 1.0) in PQ, as told to the layer

static float luma(float3 c) { return 0.2126f * c.x + 0.7152f * c.y + 0.0722f * c.z; }

static float3 bbLookup(constant Static& st, float T) {
    if (!(T > BB_TMIN)) return float3(0.0f);
    const float x = log(T / BB_TMIN) / log(BB_TMAX / BB_TMIN) * float(BB_N - 1);
    const uint xi = uint(min(floor(x), float(BB_N - 2)));
    const float f = min(x - float(xi), 1.0f);
    return float3(st.bb[xi][0], st.bb[xi][1], st.bb[xi][2]) * (1.0f - f) +
           float3(st.bb[xi + 1][0], st.bb[xi + 1][1], st.bb[xi + 1][2]) * f;
}

static float fmodPos(float x, float m) { return x - m * floor(x / m); }

// ---------------------------------------------------------------- shared-exponent colour

static uint packRGB9E5(float3 c) {
    c = clamp(c, 0.0f, 65408.0f);
    const float m = max(c.x, max(c.y, c.z));
    if (m < 1e-12f) return 0;
    int e = max(-16, int(floor(log2(m)))) + 16; // biased by 15, +1
    float denom = exp2(float(e - 15 - 9));
    if (floor(m / denom + 0.5f) >= 512.0f) {
        denom *= 2.0f;
        e += 1;
    }
    const uint3 q = uint3(min(floor(c / denom + 0.5f), 511.0f));
    return q.x | (q.y << 9) | (q.z << 18) | (uint(clamp(e, 0, 31)) << 27);
}

static float3 unpackRGB9E5(uint v) {
    const float s = exp2(float(int(v >> 27) - 15 - 9));
    return float3(float(v & 511u), float((v >> 9) & 511u), float((v >> 18) & 511u)) * s;
}

// ---------------------------------------------------------------- Kerr geodesics (theme port)

struct V6 {
    float3 p; // r, theta, phi
    float3 q; // t, p_r, p_theta
};

static V6 v6add(V6 x, V6 y) { return V6{x.p + y.p, x.q + y.q}; }
static V6 v6mul(V6 x, float s) { return V6{x.p * s, x.q * s}; }

static V6 rhs(float a, float L, V6 y) {
    const float r = y.p.x;
    const float s0 = sin(y.p.y);
    const float c = cos(y.p.y);
    const float s = fabs(s0) < 1e-9f ? (s0 < 0.0f ? -1e-9f : 1e-9f) : s0;
    const float s2 = s * s;
    const float a2 = a * a;
    const float r2 = r * r;
    const float sig = r2 + a2 * c * c;
    const float del = r2 - 2.0f * r + a2;
    const float P = r2 + a2 - a * L;
    const float isig = 1.0f / sig;
    const float idel = 1.0f / del;
    const float pr = y.q.y;
    const float dBdr = (2.0f * r - 2.0f) * pr * pr - (4.0f * r * P * del - P * P * (2.0f * r - 2.0f)) * idel * idel;
    const float dBdth = (-2.0f * L * L / (s2 * s) + 2.0f * a2 * s) * c;
    return V6{
        float3(del * pr * isig, y.q.z * isig, -(a * P * idel + L / s2 - a) * isig),
        float3(-((r2 + a2) * P * idel + a * (L - a * s2)) * isig, -0.5f * dBdr * isig, -0.5f * dBdth * isig),
    };
}

static V6 rk4k(float a, float L, V6 y, float h, V6 k1) {
    const V6 k2 = rhs(a, L, v6add(y, v6mul(k1, 0.5f * h)));
    const V6 k3 = rhs(a, L, v6add(y, v6mul(k2, 0.5f * h)));
    const V6 k4 = rhs(a, L, v6add(y, v6mul(k3, h)));
    return v6add(y, v6mul(v6add(v6add(k1, v6mul(v6add(k2, k3), 2.0f)), k4), h / 6.0f));
}

static float stepSize(constant TraceParams& P, V6 y, V6 d) {
    const float r = y.p.x;
    float h = r > 200.0f ? 0.25f * r : (r > 60.0f ? 0.1f * r : K_NEAR * min(r, 4.0f * (r - P.rh)));
    if (r < 200.0f) {
        h = min(h, 0.08f / max(fabs(d.p.y), 1e-12f));
        h = min(h, 0.08f / max(fabs(d.p.z), 1e-12f));
        h = min(h, (0.05f * fabs(sin(y.p.y)) + 2e-4f) / max(fabs(d.p.y), 1e-12f));
    }
    return max(h, 1e-5f);
}

static V6 project(float a, float L, V6 y) {
    const float s = sin(y.p.y);
    const float s2 = max(s * s, 1e-18f);
    const float r = y.p.x;
    const float del = r * r - 2.0f * r + a * a;
    const float P = r * r + a * a - a * L;
    const float X = P * P / del - y.q.z * y.q.z - (L - a * s2) * (L - a * s2) / s2;
    if (X < 0.05f * P * P / del) return y;
    const float mag = sqrt(X / del);
    V6 out = y;
    out.q.y = y.q.y < 0.0f ? -mag : mag;
    return out;
}

struct Ray {
    V6 y;
    float L;
    uint n;
    uint steps;
};

struct Hit {
    uint kind;
    uint n;
    float r, ph, t; // t: relative light-travel delay (the theme's t_hit + T_REF)
    float3 dir;
};

static Hit hitNone() { return Hit{KIND_HOLE, 0, 0.0f, 0.0f, 0.0f, float3(0.0f)}; }

static Ray startRay(constant TraceParams& P, float alpha, float beta) {
    const float a = P.a;
    const float L = -alpha * P.sin_i;
    const float r = OBS_R;
    const float s2 = P.sin_i * P.sin_i;
    const float del = r * r - 2.0f * r + a * a;
    const float Pp = r * r + a * a - a * L;
    const float f = (L - a * s2) * (L - a * s2) / s2;
    const float pth = -beta;
    const float X = Pp * Pp / del - pth * pth - f;
    const float pr = -sqrt(max(X, 0.0f) / del);
    return Ray{V6{float3(r, P.incl, 0.0f), float3(T_REF, pr, pth)}, L, 0, 0};
}

static Hit traceNext(constant TraceParams& P, thread Ray& ray, bool with_disk) {
    V6 y = ray.y;
    const float L = ray.L;
    const float a = P.a;
    uint n = ray.n;
    for (uint steps = ray.steps; steps < MAX_STEPS; steps++) {
        const float r = y.p.x;
        if (r < P.rh + 0.02f) return hitNone();
        if (y.q.y > 0.0f && r > 2.0e4f) {
            const V6 d = rhs(a, L, y);
            const float s = sin(y.p.y);
            const float c = cos(y.p.y);
            const float sp = sin(y.p.z);
            const float cp = cos(y.p.z);
            const float vr = d.p.x;
            const float vt = r * d.p.y;
            const float vp = r * s * d.p.z;
            const float3 v = float3(vr * s * cp + vt * c * cp - vp * sp,
                                    vr * s * sp + vt * c * sp + vp * cp,
                                    vr * c - vt * s);
            return Hit{KIND_SKY, 0, 0.0f, 0.0f, 0.0f, normalize(v)};
        }
        const V6 k1 = rhs(a, L, y);
        const float h = stepSize(P, y, k1);
        const V6 prev = y;
        y = project(a, L, rk4k(a, L, y, h, k1));
        if (!isfinite(y.p.x) || !isfinite(y.p.y)) return hitNone();
        // Equator crossing via the sign of cos(theta): robust if theta wraps through a pole.
        const float e0 = cos(prev.p.y);
        const float e1 = cos(y.p.y);
        if ((e0 < 0.0f) != (e1 < 0.0f)) {
            n = min(n + 1, 255u);
            float lo = 0.0f;
            float hi = h;
            float flo = e0;
            float fhi = e1;
            V6 yc = y;
            for (uint it = 0; it < 4; it++) {
                const float hm = lo + (hi - lo) * flo / (flo - fhi);
                yc = rk4k(a, L, prev, hm, k1);
                const float fm = cos(yc.p.y);
                if ((fm < 0.0f) == (flo < 0.0f)) {
                    lo = hm;
                    flo = fm;
                } else {
                    hi = hm;
                    fhi = fm;
                }
            }
            const float rc = yc.p.x;
            if (with_disk && rc >= P.r_in && rc <= P.r_out) {
                ray.y = y;
                ray.n = n;
                ray.steps = steps + 1;
                return Hit{KIND_DISK, n, rc, yc.p.z, yc.q.x, float3(0.0f)};
            }
        }
    }
    return hitNone();
}

// ---------------------------------------------------------------- disk physics (theme port)

static float opticalDepth(float r) { return TAU0 * (R_C / r) * exp(-r / R_C); }

struct Orbit {
    float om, ut;
};

static Orbit orbitAt(float a, float r) {
    const float sr = sqrt(r);
    const float r32 = r * sr;
    const float den = sqrt(r32) * sqrt(r32 - 3.0f * sr + 2.0f * a);
    return Orbit{1.0f / (r32 + a), (r32 + a) / den};
}

static float temperature(constant TraceParams& P, device const float* ttab, float r) {
    const float x = log(r / P.r_in) / P.lnt_span * float(PT_N - 1);
    if (!(x > 0.0f)) return 0.0f;
    const uint xi = uint(min(floor(x), float(PT_N - 2)));
    const float f = x - float(xi);
    return ttab[xi] * (1.0f - f) + ttab[xi + 1] * f;
}

struct Sample {
    float tobs;
    uint tq;
    float3 rgb;
    uint rbin;
    uint phi;
};

static Sample shadeDisk(constant TraceParams& P, constant Static& st, device const float* ttab, float alpha, float r, float ph, float t) {
    const float L = -alpha * P.sin_i;
    const Orbit o = orbitAt(P.a, r);
    const float g = 1.0f / (o.ut * (1.0f - o.om * L));
    const float tobs = g * temperature(P, ttab, r);
    const float rb = clamp((log(r) - P.lnr_in) / P.lnr_span * float(R_BINS), 0.0f, float(R_BINS - 1));
    const float phe = fmodPos(ph - o.om * t, TWO_PI);
    const float tturns = fmodPos(o.om * t / TWO_PI * 1024.0f, 65536.0f);
    return Sample{
        tobs,
        uint(min(tturns, 65535.0f)),
        bbLookup(st, tobs),
        uint(min(rb * float(R_FRAC), float(R_BINS * R_FRAC - 1))),
        uint(phe / TWO_PI * 65536.0f) & 0xFFFFu,
    };
}

// ---------------------------------------------------------------- sky (theme port)

static ulong mix64(ulong x0) {
    ulong z = x0 + 0x9E3779B97F4A7C15UL;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
    return z ^ (z >> 31);
}

static float unitf(ulong h) { return float(h >> 40) * (1.0f / 16777216.0f); }

static float latticeVal(long ix, long iy, long iz, ulong seed) {
    return unitf(mix64(seed ^ ulong(ix) * 0x9E3779B1UL ^ ulong(iy) * 0x85EBCA77UL ^ ulong(iz) * 0xC2B2AE3DUL));
}

static float noise3(float3 p, ulong seed) {
    const float3 f = floor(p);
    const long ix = long(f.x);
    const long iy = long(f.y);
    const long iz = long(f.z);
    float3 u = p - f;
    u = u * u * (3.0f - 2.0f * u);
    float acc = 0.0f;
    for (uint c = 0; c < 8; c++) {
        const long dx = long(c & 1u);
        const long dy = long((c >> 1) & 1u);
        const long dz = long((c >> 2) & 1u);
        const float wx = dx == 1 ? u.x : 1.0f - u.x;
        const float wy = dy == 1 ? u.y : 1.0f - u.y;
        const float wz = dz == 1 ? u.z : 1.0f - u.z;
        acc += wx * wy * wz * latticeVal(ix + dx, iy + dy, iz + dz, seed);
    }
    return acc;
}

static float3 star(constant TraceParams& P, constant Static& st, float3 d, float foot) {
    const float G = 1.0f / STAR_CELL;
    const float3 cc = floor(d * G);
    const long ix = long(cc.x);
    const long iy = long(cc.y);
    const long iz = long(cc.z);
    const ulong hh = mix64(ulong(ix) * 0x9E37UL ^ ulong(iy) * 0x85EBCA6BUL ^ ulong(iz) * 0xC2B2AE35UL);
    const float lat = dot(d, P.gal_n.xyz);
    const ulong prob = 30 + ulong(45.0f * exp(-(lat / 0.12f) * (lat / 0.12f)));
    if (hh % 100 >= prob) return float3(0.0f);
    float3 p = float3(cc.x + 0.15f + 0.7f * unitf(mix64(hh ^ 1)),
                      cc.y + 0.15f + 0.7f * unitf(mix64(hh ^ 2)),
                      cc.z + 0.15f + 0.7f * unitf(mix64(hh ^ 3))) / G;
    p = normalize(p);
    const float3 dd = d - p;
    const float ang2 = dot(dd, dd);
    const float fp = max(foot, P.pix_ang);
    const float sig = 0.75f * fp;
    const float u = unitf(mix64(hh ^ 4));
    const float mu = (P.pix_ang / fp) * (P.pix_ang / fp);
    const float bright = STAR_FLUX * (0.03f + 0.9f * u * u * u * u * u) * mu * exp(-ang2 / (sig * sig));
    if (bright < 1e-4f) return float3(0.0f);
    const float3 col = bbLookup(st, 3500.0f + 9000.0f * unitf(mix64(hh ^ 5)));
    return bright * col / max(luma(col), 1e-12f);
}

static float3 milkyWay(constant TraceParams& P, constant Static& st, float3 d) {
    const float lat = dot(d, P.gal_n.xyz);
    const float band = exp(-(lat / 0.07f) * (lat / 0.07f));
    const float3 dc = d - P.gal_c.xyz;
    const float bulge = exp(-dot(dc, dc) / 0.004f);
    if (band < 1e-3f && bulge < 1e-3f) return float3(0.0f);
    const float nz = 0.6f * noise3(d * 25.0f, 11) + 0.4f * noise3(d * 80.0f, 12);
    const float clumpy = 0.1f + 1.2f * nz * nz;
    const float lane = exp(-(lat / 0.016f) * (lat / 0.016f));
    const float dust = 1.0f - 0.75f * lane * clamp(1.6f * noise3(d * 45.0f, 13) - 0.3f, 0.0f, 1.0f);
    const float3 warm = bbLookup(st, 4300.0f);
    const float3 cool = bbLookup(st, 6200.0f);
    const float ib = SKY_GAIN * band * clumpy * dust;
    const float iu = SKY_GAIN * 2.5f * bulge * dust;
    return ib * cool / max(luma(cool), 1e-12f) + iu * warm / max(luma(warm), 1e-12f);
}

// Sky light in display-linear units (the theme's packBg gain applied).
static float3 sky(constant TraceParams& P, constant Static& st, float3 d, float foot) {
    return (star(P, st, d, foot) + milkyWay(P, st, d)) * STAR_GAIN;
}

// ---------------------------------------------------------------- trace kernels

// Light from behind translucent gas, pre-tone-map (exposed disk radiance; sky in display
// units), composited front to back. Gas seen there is static, at its own opacity.
// `foot` holds each layer's own sky footprint: lensed images behind the gas are squeezed
// differently from the one in front.
static float3 behind(constant TraceParams& P, constant Static& st, device const float* ttab, float alpha, Hit b0, Hit b1, float3 foot) {
    float3 acc = float3(0.0f);
    float tr = 1.0f;
    for (uint i = 0; i < 2; i++) {
        const Hit b = i == 0 ? b0 : b1;
        if (b.kind == KIND_HOLE) break;
        if (b.kind == KIND_SKY) {
            acc += tr * sky(P, st, b.dir, foot[i + 1]);
            break;
        }
        const float tau = opticalDepth(b.r);
        const Sample s = shadeDisk(P, st, ttab, alpha, b.r, b.ph, b.t);
        acc += tr * s.rgb * (P.exposure * (1.0f - exp(-tau)));
        tr *= exp(-tau);
    }
    return acc;
}

static float2 alphaBeta(constant TraceParams& P, float fx, float fy) {
    float alpha = (fx - 0.5f * float(P.width)) * P.mpp;
    if (fabs(alpha) < 1e-6f) alpha = 1e-6f; // never aim a ray exactly through the spin axis
    return float2(alpha, (0.5f * float(P.height) - fy) * P.mpp);
}

// One pixel's light, sorted by image order (disk crossings of the front hit: 1, 2, 3+).
struct Px {
    float3 bg;        // sky and baked gas
    uint cnt[3];      // animated-eligible disk samples per order
    Sample first[3];  // the first of each order: its record, if that order stays animated
    float3 behind[3]; // light behind those samples
    float3 stat[3];   // their mean emission plus what shows through: used if they stay static
};

static Px pxNew() {
    Px px;
    px.bg = float3(0.0f);
    for (uint o = 0; o < 3; o++) {
        px.cnt[o] = 0;
        px.first[o] = Sample{0.0f, 0, float3(0.0f), 0, 0};
        px.behind[o] = float3(0.0f);
        px.stat[o] = float3(0.0f);
    }
    return px;
}

static void addSample(thread Px& px, constant TraceParams& P, constant Static& st, device const float* ttab,
                      float alpha, Hit h0, Hit h1, Hit h2, float3 foot) {
    if (h0.kind == KIND_SKY) {
        px.bg += sky(P, st, h0.dir, foot.x);
        return;
    }
    if (h0.kind != KIND_DISK) return;
    const float tau = opticalDepth(h0.r);
    const Sample smp = shadeDisk(P, st, ttab, alpha, h0.r, h0.ph, h0.t);
    if (h0.r > SPOT_RMAX) {
        const bool dim = luma(smp.rgb) * P.exposure * 2.0f < EMIT_FLOOR;
        if (tau * exp(TAU_NOISE) < TAU_MIN || dim) {
            // Too thin or too cool to show even when stirred: baked at its mean opacity.
            if (tau < TAU_BEHIND) px.bg += exp(-tau) * behind(P, st, ttab, alpha, h1, h2, foot);
            return;
        }
    }
    const uint o = min(h0.n, 3u) - 1;
    if (px.cnt[o] == 0) px.first[o] = smp;
    px.cnt[o] += 1;
    const float3 bh = behind(P, st, ttab, alpha, h1, h2, foot);
    px.behind[o] += bh;
    px.stat[o] += smp.rgb * (P.exposure * (1.0f - exp(-tau))) + exp(-tau) * bh;
}

kernel void bh_meter(constant TraceParams& P [[buffer(0)]],
                     constant Static& st [[buffer(1)]],
                     device const float* ttab [[buffer(2)]],
                     device float* lum [[buffer(3)]],
                     uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= P.grid_w || gid.y >= P.grid_h) return;
    const float fx = (float(gid.x) + 0.5f) * float(P.width) / float(P.grid_w);
    const float fy = (float(gid.y) + 0.5f) * float(P.height) / float(P.grid_h);
    const float2 ab = alphaBeta(P, fx, fy);
    Ray ray = startRay(P, ab.x, ab.y);
    const Hit h = traceNext(P, ray, true);
    float y = 0.0f;
    if (h.kind == KIND_DISK && h.r <= EXPO_R) y = luma(shadeDisk(P, st, ttab, ab.x, h.r, h.ph, h.t).rgb);
    lum[gid.y * P.grid_w + gid.x] = y;
}

// One pixel of the theme's render(): 2x2 samples, each traced through up to two
// translucent layers, reduced to a disk record and a background.
kernel void bh_trace(constant TraceParams& P [[buffer(0)]],
                     constant Static& st [[buffer(1)]],
                     device const float* ttab [[buffer(2)]],
                     device Rec* recs [[buffer(3)]],
                     device uint* bg [[buffer(4)]],
                     device ushort* tq [[buffer(5)]],
                     uint2 gid [[thread_position_in_grid]]) {
    const uint x = gid.x;
    const uint y = gid.y + P.row0;
    if (x >= P.width || y >= P.height) return;

    Hit hits[4][3];
    float alphas[4];
    for (uint s = 0; s < 4; s++) {
        const float fx = float(x) + (float(s & 1u) + 0.5f) * 0.5f;
        const float fy = float(y) + (float(s >> 1) + 0.5f) * 0.5f;
        const float2 ab = alphaBeta(P, fx, fy);
        alphas[s] = ab.x;
        Ray ray = startRay(P, ab.x, ab.y);
        hits[s][0] = traceNext(P, ray, true);
        hits[s][1] = hitNone();
        hits[s][2] = hitNone();
        for (uint i = 1; i < 3; i++) {
            const Hit pv = hits[s][i - 1];
            // Fetch a little past the threshold: whether the pixel counts as translucent is
            // decided below from its record, exactly as bh_shade decides it.
            if (pv.kind != KIND_DISK || opticalDepth(pv.r) >= 2.0f * TAU_BEHIND) break;
            hits[s][i] = traceNext(P, ray, true);
        }
    }

    // Sky angle one pixel covers, per layer, from adjacent sky samples (half a pixel apart):
    // the sky seen directly, and the lensed skies seen through one or two layers of gas.
    float3 foot = float3(8.0f * P.pix_ang); // typical value inside the Einstein ring, if unmeasurable
    for (uint l = 0; l < 3; l++) {
        float m = 0.0f;
        bool got = false;
        const uint2 pairs[4] = {uint2(0, 1), uint2(2, 3), uint2(0, 2), uint2(1, 3)};
        for (uint k = 0; k < 4; k++) {
            const Hit h0 = hits[pairs[k].x][l];
            const Hit h1 = hits[pairs[k].y][l];
            if (h0.kind != KIND_SKY || h1.kind != KIND_SKY) continue;
            m = max(m, length(h1.dir - h0.dir));
            got = true;
        }
        if (got) foot[l] = max(m * 2.0f, 0.25f * P.pix_ang);
    }

    // A pixel whose samples disagree (an edge) or see light that crossed the disk plane more
    // than once (the photon rings) is traced again with REFINE x REFINE samples: the n = 2
    // ring is a fraction of a pixel wide, and 4 samples would alias it.
    bool refine = false;
    for (uint s = 1; s < 4; s++) {
        if (hits[s][0].kind != hits[0][0].kind || hits[s][0].n != hits[0][0].n) refine = true;
    }
    for (uint s = 0; s < 4; s++) {
        if (hits[s][0].kind == KIND_DISK && hits[s][0].n >= 2) refine = true;
    }

    Px px = pxNew();
    uint N = 4;
    if (!refine) {
        for (uint s = 0; s < 4; s++) addSample(px, P, st, ttab, alphas[s], hits[s][0], hits[s][1], hits[s][2], foot);
    } else {
        N = REFINE * REFINE;
        for (uint i = 0; i < N; i++) {
            const float fx = float(x) + (float(i % REFINE) + 0.5f) / float(REFINE);
            const float fy = float(y) + (float(i / REFINE) + 0.5f) / float(REFINE);
            const float2 ab = alphaBeta(P, fx, fy);
            Ray ray = startRay(P, ab.x, ab.y);
            Hit h[3] = {traceNext(P, ray, true), hitNone(), hitNone()};
            for (uint l = 1; l < 3; l++) {
                if (h[l - 1].kind != KIND_DISK || opticalDepth(h[l - 1].r) >= 2.0f * TAU_BEHIND) break;
                h[l] = traceNext(P, ray, true);
            }
            addSample(px, P, st, ttab, ab.x, h[0], h[1], h[2], foot);
        }
    }

    // The lowest-order disk image stays animated; higher orders go into bg as static light.
    int p = -1;
    for (int o = 2; o >= 0; o--) if (px.cnt[o] > 0) p = o;
    float3 bg_rgb = px.bg;
    uint covq = 0;
    if (p >= 0) {
        covq = min((px.cnt[p] * COV_MAX + N / 2) / N, COV_MAX);
        if (covq == 0) p = -1; // under 1/30 of the pixel: static like the rest
    }
    for (int o = 0; o < 3; o++) if (o != p) bg_rgb += px.stat[o];
    // bh_shade composites translucent pixels as cov*c + (1 - cov*emit)*bg and opaque ones as
    // cov*c + bg: the light behind the animated samples belongs in bg only in the first case.
    if (p >= 0 && st.tau_tab[px.first[p].rbin / R_FRAC] < TAU_BEHIND) bg_rgb += px.behind[p];
    const uint idx = y * P.width + x;
    bg[idx] = packRGB9E5(bg_rgb / float(N));
    recs[idx] = p >= 0 ? Rec{ushort(px.first[p].rbin), ushort(px.first[p].phi), ushort(covq)} : Rec{0, 0, 0};
    tq[idx] = p >= 0 ? ushort(px.first[p].tq) : ushort(0);
}

// Each disk pixel's footprint on the disk, from its neighbours (the theme's second pass).
// Writes only the footprint bits of each record's meta; neighbours read rbin, phi and the
// sample count, which no thread changes.
kernel void bh_footprint(constant TraceParams& P [[buffer(0)]],
                         device Rec* recs [[buffer(1)]],
                         device const ushort* tq [[buffer(2)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= P.width || gid.y >= P.height) return;
    const uint i = gid.y * P.width + gid.x;
    const Rec ri = recs[i];
    const uint cov = ri.meta & COV_MAX;
    if (cov == 0) return;
    const ushort tq_i = tq[i];
    uint fr = 0;
    uint fp = 0;
    const int2 nb[4] = {int2(1, 0), int2(-1, 0), int2(0, 1), int2(0, -1)};
    for (uint k = 0; k < 4; k++) {
        const int2 q = int2(gid) + nb[k];
        if (q.x < 0 || q.y < 0 || q.x >= int(P.width) || q.y >= int(P.height)) continue;
        const uint j = uint(q.y) * P.width + uint(q.x);
        const Rec rj = recs[j];
        if ((rj.meta & COV_MAX) == 0) continue;
        const ushort tq_j = tq[j];
        const uint dr = (uint(abs(int(rj.rbin) - int(ri.rbin))) + R_FRAC - 1) / R_FRAC;
        const ushort hit_i = ushort(ri.phi + ushort(tq_i << 6));
        const ushort hit_j = ushort(rj.phi + ushort(tq_j << 6));
        const int d_hit = int(as_type<short>(ushort(hit_j - hit_i)));
        const int d_tq = int(as_type<short>(ushort(tq_j - tq_i)));
        fr = max(fr, dr);
        fp = max(fp, uint(abs(d_hit - d_tq * 64)));
    }
    recs[i].meta = ushort(cov | (min(fr, FR_MAX) << 4) | (min((fp + 63) / 64, FP_MAX) << 9));
}

// ---------------------------------------------------------------- per-frame shading

// One pixel of the theme's draw(), composited before tone mapping (light adds in linear).
static float3 shadePre(uint x, uint y, constant TraceParams& P, device const float* ttab,
                       device const Rec* recs, device const uint* bg,
                       device const uchar* noise, constant Static& st, constant Frame& fr, float exposure) {
    const uint i = y * P.width + x;
    const float3 bgv = unpackRGB9E5(bg[i]);
    const Rec rc = recs[i];
    const uint ns = rc.meta & COV_MAX;
    if (ns == 0) return bgv;
    const uint fr_q = (rc.meta >> 4) & FR_MAX;
    const uint fp_q = (rc.meta >> 9) & FP_MAX;

    const float amp = TURB * fr.gnorm / 128.0f;
    const float w0 = fr.gw[0] * amp;
    const float w1 = fr.gw[1] * amp;
    const uint rb = rc.rbin / R_FRAC;
    const float rbf = float(rc.rbin) / float(R_FRAC);
    // Observed temperature, as the trace's shadeDisk had it: T(r) and the Kerr redshift for
    // this pixel's photon angular momentum.
    const float r = exp(P.lnr_in + P.lnr_span * rbf / float(R_BINS));
    const float L = -((float(x) + 0.5f - 0.5f * float(P.width)) * P.mpp) * P.sin_i;
    const Orbit o = orbitAt(P.a, r);
    const float tobs = temperature(P, ttab, r) / (o.ut * (1.0f - o.om * L));
    const float3 rgb = bbLookup(st, tobs);
    const uint pa = ushort(rc.phi - fr.gshift[0][rb]) >> 6;
    const uint pb = ushort(rc.phi - fr.gshift[1][rb]) >> 6;
    const float na = float(int(noise[fr.grow[0][rb] * NP + pa]) - 128);
    const float nb = float(int(noise[fr.grow[1][rb] * NP + pb]) - 128);
    const float frf = float(fr_q);
    const float fpf = float(fp_q) * 64.0f;
    const float tex = 1.0f / (1.0f + (frf * frf) / 64.0f + (fpf * fpf) / 116000.0f);
    float k = max(0.0f, 1.0f + tex * (w0 * na + w1 * nb)) * exposure;

    const float tau_b = st.tau_tab[rb];
    const bool thin = tau_b < TAU_BEHIND;
    float emit = 1.0f;
    if (thin) {
        const float nt = clamp((fr.gw[0] * na + fr.gw[1] * nb) * fr.gnorm / 128.0f * tex, -1.0f, 1.0f);
        const float xi = clamp((st.lntau_tab[rb] + TAU_NOISE * nt - EMIT_X0) * (float(EMIT_N) / (EMIT_X1 - EMIT_X0)), 0.0f, float(EMIT_N) - 0.001f);
        const uint ii = uint(xi);
        const float fr_e = xi - float(ii);
        emit = st.emit_tab[ii] + (st.emit_tab[ii + 1] - st.emit_tab[ii]) * fr_e;
        k *= emit;
    }

    float3 spot_rgb = float3(0.0f);
    float spot_scale = 0.0f;
    const uint sm = fr.spot_mask[rb];
    if (sm != 0) {
        float boost = 0.0f;
        for (uint j = 0; j < NSPOT; j++) {
            if ((sm & (1u << j)) == 0) continue;
            // A sheared spot's azimuth shifts with radius: across the pixel's radial footprint it
            // moves by |dOmega/dr| * age * dr. Widen the azimuthal kernel by that too, or a thin
            // sheared arc aliases into dots.
            const float r15 = r * sqrt(r) + P.a;
            const float dom_dbin = 1.5f * sqrt(r) / (r15 * r15) * r * (P.lnr_span / float(R_BINS));
            const float smear = dom_dbin * fr.spot_age[j] * (65536.0f / TWO_PI) * (frf + 0.5f);
            const float wr2 = fr.spot_wr[j] * fr.spot_wr[j] + frf * frf;
            const float wp2 = fr.spot_wp[j] * fr.spot_wp[j] + fpf * fpf + smear * smear;
            const float dr = rbf - fr.spot_rb[j];
            // Sheared: at this radius the clump has moved (Omega(r) - Omega_spot) * age further.
            const float shear = (o.om - fr.spot_om[j]) * fr.spot_age[j] * (65536.0f / TWO_PI);
            const float dp0 = float(as_type<short>(ushort(rc.phi - fr.spot_q[j]))) - shear;
            const float dp = dp0 - 65536.0f * round(dp0 / 65536.0f);
            if (fp_q == FP_MAX || fr_q == FR_MAX || fpf > 2.0f * fr.spot_wp[j] || frf > 2.0f * fr.spot_wr[j]) continue;
            const float q = dr * dr / wr2 + dp * dp / wp2;
            if (q < 1.0f) boost += fr.spot_amp[j] * (1.0f - q) * (1.0f - q) * fr.spot_wr[j] * fr.spot_wp[j] / sqrt(wr2 * wp2);
        }
        if (boost > 1e-3f && tobs > 0.0f) {
            spot_rgb = bbLookup(st, tobs * sqrt(sqrt(1.0f + boost)));
            spot_scale = 1.0f;
        } else {
            k *= 1.0f + boost;
        }
    }

    const float3 c = spot_scale > 0.0f ? spot_rgb * spot_scale * k : rgb * k;
    const float cov = float(ns) / float(COV_MAX);
    // bg holds the sky beside the disk samples and, under translucent gas, what lies behind it.
    return thin ? cov * c + (1.0f - cov * emit) * bgv : cov * c + bgv;
}

static float srgbEncode(float v) {
    return v <= 0.0031308f ? 12.92f * v : 1.055f * pow(v, 1.0f / 2.4f) - 0.055f;
}

// HDR10 encoding: linear sRGB (1.0 = display white) -> BT.2020 primaries -> PQ.
static float3 pqEncode(float3 c) {
    const float3 c2020 = float3(dot(float3(0.6274040f, 0.3292820f, 0.0433136f), c),
                                dot(float3(0.0690970f, 0.9195400f, 0.0113612f), c),
                                dot(float3(0.0163916f, 0.0880132f, 0.8955950f), c));
    const float3 Lp = pow(clamp(c2020 * (PQ_REF_NITS / 10000.0f), 0.0f, 1.0f), 0.1593017578125f);
    return pow((0.8359375f + 18.8515625f * Lp) / (1.0f + 18.6875f * Lp), 78.84375f);
}

// Reinhard on luminance, hue preserved, saturating at the display's headroom
// (headroom 1 = the theme's SDR curve, c / (1 + Y)).
static float3 toneMap(float3 c, float headroom) {
    return c / (1.0f + luma(c) / headroom);
}

kernel void bh_shade(device const Rec* recs [[buffer(0)]],
                     device const uint* bg [[buffer(1)]],
                     device const uchar* noise [[buffer(2)]],
                     constant Static& st [[buffer(3)]],
                     constant Frame& fr [[buffer(4)]],
                     constant View& v [[buffer(5)]],
                     constant TraceParams& P [[buffer(6)]],
                     device const float* ttab [[buffer(7)]],
                     texture2d<float, access::write> out [[texture(0)]],
                     uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= v.out_w || gid.y >= v.out_h) return;
    // Output pixel -> traced pixel (identical when the drawable is the traced size).
    const uint x = min(uint((float(gid.x) + 0.5f) * float(v.width) / float(v.out_w)), v.width - 1);
    const uint y = min(uint((float(gid.y) + 0.5f) * float(v.height) / float(v.out_h)), v.height - 1);
    float3 c = float3(0.0f);
    if (y < v.rows_done) c = toneMap(shadePre(x, y, P, ttab, recs, bg, noise, st, fr, v.exposure), max(v.headroom, 1.0f));
    c = max(c, 0.0f);
    if (v.out_mode == OUT_SRGB) c = float3(srgbEncode(min(c.x, 1.0f)), srgbEncode(min(c.y, 1.0f)), srgbEncode(min(c.z, 1.0f)));
    else if (v.out_mode == OUT_PQ) c = pqEncode(c);
    out.write(float4(c, 1.0f), gid);
}

// Probe for the shadow-edge test: kind of the first thing each (alpha, beta) ray meets
// (no disk), so the bisection runs on the GPU's own f32 geodesics.
kernel void bh_probe(constant TraceParams& P [[buffer(0)]],
                     device const float2* ab [[buffer(1)]],
                     device uint* kind [[buffer(2)]],
                     uint gid [[thread_position_in_grid]]) {
    Ray ray = startRay(P, ab[gid].x, ab[gid].y);
    kind[gid] = traceNext(P, ray, false).kind;
}


// ============================================================================
// ARGUS GPU PROTOTYPE // src/gpu/opus_black_hole.metal
//
// themes/Opus_Black_Hole.zig `State.draw` as a Metal compute kernel, one thread per pixel.
// The theme still runs on the CPU for init (ray tracing -> per-pixel records) and step
// (a few KB of per-frame tables); this kernel only replaces the per-pixel shading loop.
// It reads the theme's own tables, so a frame should match the CPU frame; f64 math in
// the hot-spot path runs in f32 here. Constants mirror the theme's private ones.
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

// Mirrors the theme's `extern struct Rec` (18 bytes, 2-byte aligned).
struct Rec {
    half r, g, b;
    ushort rbin;
    ushort phi;
    uchar cov;
    uchar fr;
    half tobs;
    uchar fp;
    uchar pad;
    ushort tq;
};
static_assert(sizeof(Rec) == 18, "Rec layout must match the theme");

// Per-frame tables written by the theme's step(), copied verbatim each frame.
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

static float3 bbLookup(constant Static& st, float T) {
    if (!(T > BB_TMIN)) return float3(0.0f);
    const float x = log(T / BB_TMIN) / log(BB_TMAX / BB_TMIN) * float(BB_N - 1);
    const uint xi = uint(min(floor(x), float(BB_N - 2)));
    const float f = min(x - float(xi), 1.0f);
    return float3(st.bb[xi][0], st.bb[xi][1], st.bb[xi][2]) * (1.0f - f) +
           float3(st.bb[xi + 1][0], st.bb[xi + 1][1], st.bb[xi + 1][2]) * f;
}

static float luma(float3 c) { return 0.2126f * c.x + 0.7152f * c.y + 0.0722f * c.z; }

// One pixel of State.draw, returning packRGBA (0xFFBBGGRR).
static uint shade(uint x, uint y,
                  device const Rec* recs, device const uint* bg,
                  device const ushort* row_x0, device const ushort* row_x1,
                  device const uchar* noise, constant Static& st, constant Frame& fr) {
    const uint w = fr.width;
    const uint i = y * w + x;
    const uint bgp = bg[i];
    if (x < row_x0[y] || x >= row_x1[y]) return bgp;
    const Rec rc = recs[i];
    if (rc.cov == 0) return bgp;

    const float amp = TURB * fr.gnorm / 128.0f;
    const float w0 = fr.gw[0] * amp;
    const float w1 = fr.gw[1] * amp;
    const uint rb = rc.rbin / R_FRAC;
    const float rbf = float(rc.rbin) / float(R_FRAC);
    const uint pa = ushort(rc.phi - fr.gshift[0][rb]) >> 6;
    const uint pb = ushort(rc.phi - fr.gshift[1][rb]) >> 6;
    const float na = float(int(noise[fr.grow[0][rb] * NP + pa]) - 128);
    const float nb = float(int(noise[fr.grow[1][rb] * NP + pb]) - 128);
    const float frf = float(rc.fr);
    const float fpf = float(rc.fp) * 64.0f;
    const float tex = 1.0f / (1.0f + (frf * frf) / 64.0f + (fpf * fpf) / 116000.0f);
    float k = max(0.0f, 1.0f + tex * (w0 * na + w1 * nb)) * fr.exposure;

    const float tau_b = st.tau_tab[rb];
    const bool thin = tau_b < fr.tau_behind;
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
            const float wr2 = fr.spot_wr[j] * fr.spot_wr[j] + frf * frf;
            const float wp2 = fr.spot_wp[j] * fr.spot_wp[j] + fpf * fpf;
            const float dr = rbf - fr.spot_rb[j];
            const float dp = float(as_type<short>(ushort(rc.phi - fr.spot_q[j])));
            if (rc.fp == 255 || fpf > 2.0f * fr.spot_wp[j] || frf > 2.0f * fr.spot_wr[j]) continue;
            const float q = dr * dr / wr2 + dp * dp / wp2;
            if (q < 1.0f) boost += fr.spot_amp[j] * (1.0f - q) * (1.0f - q) * fr.spot_wr[j] * fr.spot_wp[j] / sqrt(wr2 * wp2);
        }
        if (boost > 1e-3f && float(rc.tobs) > 0.0f) {
            const float t0 = float(rc.tobs);
            const float3 hot = bbLookup(st, t0 * sqrt(sqrt(1.0f + boost)));
            const float lum0 = luma(float3(float(rc.r), float(rc.g), float(rc.b)));
            spot_scale = lum0 / max(luma(bbLookup(st, t0)), 1e-12f);
            spot_rgb = hot;
        } else {
            k *= 1.0f + boost;
        }
    }

    float3 c = spot_scale > 0.0f ? spot_rgb * spot_scale * k : float3(float(rc.r), float(rc.g), float(rc.b)) * k;
    const float yl = 0.2126f * c.x + 0.7152f * c.y + 0.0722f * c.z;
    const float tm = 1.0f / (1.0f + yl);

    uint out[3];
    if (thin) {
        const float cov = float(rc.cov) / 255.0f;
        const float tr = 1.0f - cov * emit;
        for (uint ch = 0; ch < 3; ch++) {
            const float bl = st.lin8[(bgp >> (8 * ch)) & 0xFF];
            const float v = min(cov * c[ch] * tm + tr * bl, 1.0f);
            out[ch] = st.srgb[uint(v * 4095.0f)];
        }
    } else if (rc.cov == 255) {
        for (uint ch = 0; ch < 3; ch++) out[ch] = st.srgb[uint(min(c[ch] * tm, 1.0f) * 4095.0f)];
    } else {
        const float cov = float(rc.cov) / 255.0f;
        for (uint ch = 0; ch < 3; ch++) {
            const float cc = min(c[ch] * tm, 1.0f);
            const float dv = float(st.srgb[uint(cc * 4095.0f)]);
            const float bv = float((bgp >> (8 * ch)) & 0xFF);
            out[ch] = uint(round(dv * cov + bv * (1.0f - cov)));
        }
    }
    return 0xFF000000u | (out[2] << 16) | (out[1] << 8) | out[0];
}

// Into a packRGBA buffer (bench / CPU comparison).
kernel void bh_to_buffer(device const Rec* recs [[buffer(0)]],
                         device const uint* bg [[buffer(1)]],
                         device const ushort* row_x0 [[buffer(2)]],
                         device const ushort* row_x1 [[buffer(3)]],
                         device const uchar* noise [[buffer(4)]],
                         constant Static& st [[buffer(5)]],
                         constant Frame& fr [[buffer(6)]],
                         device uint* out [[buffer(7)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= fr.width || gid.y >= fr.height) return;
    out[gid.y * fr.width + gid.x] = shade(gid.x, gid.y, recs, bg, row_x0, row_x1, noise, st, fr);
}

// Straight into a CAMetalLayer drawable (BGRA8Unorm).
kernel void bh_to_texture(device const Rec* recs [[buffer(0)]],
                          device const uint* bg [[buffer(1)]],
                          device const ushort* row_x0 [[buffer(2)]],
                          device const ushort* row_x1 [[buffer(3)]],
                          device const uchar* noise [[buffer(4)]],
                          constant Static& st [[buffer(5)]],
                          constant Frame& fr [[buffer(6)]],
                          texture2d<float, access::write> out [[texture(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= fr.width || gid.y >= fr.height) return;
    const uint p = shade(gid.x, gid.y, recs, bg, row_x0, row_x1, noise, st, fr);
    out.write(float4(float(p & 0xFF), float((p >> 8) & 0xFF), float((p >> 16) & 0xFF), 255.0f) / 255.0f, gid);
}

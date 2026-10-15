// ============================================================================
// ARGUS METAL THEME PRELUDE // src/gpu/argus_prelude.metal
//
// Prepended to every themes/*.metal file before Argus compiles it, so themes can
// use these names without including anything. Compile errors still report the
// theme's own line numbers (a #line directive follows this prelude).
// ============================================================================

#include <metal_stdlib>
using namespace metal;

// Everything Argus tells a theme about the current frame (buffer 0 in every kernel).
struct ArgusFrame {
    float time;         // seconds of animation; advances 1/30 s per 30 FPS frame
    float dt;           // seconds since this Space's previous frame
    uint  frame;        // frames drawn since the theme was loaded
    uint  width;        // output size in pixels (1920 x 1200)
    uint  height;
    uint  state_width;  // state texture size (0 x 0 when the theme keeps no state)
    uint  state_height;
    uint  seed;         // random per load: vary it to vary the theme
};

// Pixel -> centred coordinates: (0,0) mid-screen, y up, the short side spans -1..1.
static inline float2 argus_uv(uint2 gid, constant ArgusFrame& f) {
    const float2 p = (float2(gid) + 0.5f) - 0.5f * float2(f.width, f.height);
    return float2(p.x, -p.y) / (0.5f * float(min(f.width, f.height)));
}

// Pixel -> 0..1 across a w x h grid, y down (texture coordinates).
static inline float2 argus_uv01(uint2 gid, uint w, uint h) {
    return (float2(gid) + 0.5f) / float2(w, h);
}

// Integer hash (lowbias32): a well-mixed uint from a uint.
static inline uint argus_hash(uint x) {
    x ^= x >> 16; x *= 0x7feb352dU;
    x ^= x >> 15; x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

// Uniform random 0..1 per integer cell (and per seed).
static inline float argus_rand(uint2 cell, uint seed) {
    return float(argus_hash(cell.x ^ argus_hash(cell.y ^ argus_hash(seed)))) * (1.0f / 4294967295.0f);
}

// Smooth value noise, about -1..1, one feature per unit of p.
static inline float argus_noise(float2 p) {
    const float2 i = floor(p);
    const float2 f = fract(p);
    const float2 u = f * f * (3.0f - 2.0f * f);
    const uint2 c = uint2(int2(i) + 32768);
    const float a = argus_rand(c, 0u);
    const float b = argus_rand(c + uint2(1, 0), 0u);
    const float d = argus_rand(c + uint2(0, 1), 0u);
    const float e = argus_rand(c + uint2(1, 1), 0u);
    return 2.0f * mix(mix(a, b, u.x), mix(d, e, u.x), u.y) - 1.0f;
}

// Fractal noise: `octaves` layers of argus_noise, each twice as fine and half as strong.
static inline float argus_fbm(float2 p, int octaves) {
    float sum = 0.0f, amp = 0.5f;
    for (int o = 0; o < octaves; o++) {
        sum += amp * argus_noise(p);
        p = float2x2(1.6f, 1.2f, -1.2f, 1.6f) * p;
        amp *= 0.5f;
    }
    return sum;
}

// Cosine palette (Inigo Quilez): a + b * cos(2 pi (c t + d)).
static inline float3 argus_palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.2831853f * (c * t + d));
}

// Linear light -> display value. Kernels write display values; use this if you light in linear.
static inline float3 argus_srgb(float3 lin) {
    lin = saturate(lin);
    return select(1.055f * pow(lin, float3(1.0f / 2.4f)) - 0.055f, lin * 12.92f, lin <= 0.0031308f);
}

// Filmic tone map (ACES fit) for HDR linear values; follow with argus_srgb.
static inline float3 argus_aces(float3 x) {
    return saturate((x * (2.51f * x + 0.03f)) / (x * (2.43f * x + 0.59f) + 0.14f));
}

// Used by Argus when a stateful theme has no argus_init: starts its state at zero.
kernel void argus_clear_state(texture2d<float, access::write> state [[texture(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= state.get_width() || gid.y >= state.get_height()) return;
    state.write(float4(0.0f), gid);
}

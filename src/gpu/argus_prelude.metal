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
    float time;         // seconds of animation, continuous at any frame rate (it advances by
                        // the real frame interval); wraps to 0 every ARGUS_TIME_PERIOD (4 h)
                        // so it stays precise on a Space that runs for weeks
    float dt;           // in argus_step: seconds since the previous step (1/30 s); in argus_draw:
                        // seconds since this Space's previous drawn frame
    uint  frame;        // the 30 Hz simulation tick since the theme was loaded: 0, 1, 2... at
                        // 30, 60 and 120 FPS alike (argus_step runs once per tick). Frames drawn
                        // between ticks at 60/120 FPS see the current tick's number again.
    uint  width;        // output size in pixels (1920 x 1200)
    uint  height;
    uint  state_width;  // state texture size (0 x 0 when the theme keeps no state)
    uint  state_height;
    uint  seed;         // random per load: vary it to vary the theme
};

// f.time wraps to 0 after this many seconds. A cycle whose period divides it (a whole number of
// minutes that divides 240: 1-6, 8, 10, 12, 15, 16, 20, 30, 60 ...) runs on seamlessly.
constant float ARGUS_TIME_PERIOD = 14400.0f;

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

// ---------------------------------------------------------------------------------------------
// Live system stats, for themes that ask with `// @argus stats` (and only them: without the
// directive nothing is sampled and buffer 1 is unbound). Every kernel may then take
//     constant ArgusStats& s [[buffer(1)]]
// Argus samples about once a second while the theme's Space is on screen; between samples the
// struct stays the same. `seq` goes up by one per sample, so a theme can push values into a
// history in its state texture exactly once each (keep the last seq it saw in a texel). The
// harness feeds fixed synthetic stats (a new seq every 30 frames), so renders never depend on
// the machine; `--stats live` there uses the real ones. Every field is 4 bytes.
constant uint ARGUS_STATS_MAX_CORES = 32;
constant uint ARGUS_STATS_TOP = 5;

struct ArgusProc {
    uchar name[32];       // process name: ASCII, NUL-padded, truncated to 31 characters
    float cpu;            // its share of the whole machine's CPU, 0..1 (x cpu_count = cores' worth)
    float mem_gb;         // memory footprint in GiB (Activity Monitor's Memory column)
};

struct ArgusStats {
    uint  seq;            // 0 until the first sample (about 1 s after the Space appears), then +1 each
    float sample_dt;      // seconds the loads and rates were measured over (about 1)
    uint  uptime_s;       // seconds since the Mac booted (sleep included)
    uint  thermal;        // 0 nominal, 1 fair, 2 serious, 3 critical (NSProcessInfo.thermalState)

    float cpu_total;      // busy fraction of all cores, 0..1
    uint  cpu_count;      // entries used in cpu_core (logical cores, at most 32)
    uint  cpu_p_cores;    // performance cores, efficiency cores (0 and 0 if the Mac doesn't say)
    uint  cpu_e_cores;
    float cpu_core[ARGUS_STATS_MAX_CORES]; // busy fraction per core, 0..1, in the kernel's order
                          // (Apple Silicon numbers the efficiency cores first)

    float mem_total_gb;   // installed memory, GiB (an "8 GB" Mac reads 8.0)
    float mem_used_gb;    // Activity Monitor's "Memory Used": app memory + wired + compressed
    float mem_compressed_gb; // held by the memory compressor
    float mem_wired_gb;   // wired (can't be paged out)
    float swap_used_gb;   // swap in use
    uint  mem_pressure;   // 0 normal, 1 warn, 2 critical (Activity Monitor's pressure colours)

    float gpu_busy;       // GPU utilisation 0..1 (IOAccelerator "Device Utilization %")

    uint  battery_present; // 1 on a MacBook, 0 on a desktop Mac (the battery fields are then 0)
    float battery_charge; // 0..1
    uint  battery_charging; // 1 while charging
    uint  on_ac;          // 1 on mains power (always 1 without a battery)
    float battery_minutes; // to full while charging, to empty on battery; 0 on mains when not
                          // charging (full, or held by Optimized Charging); -1 while macOS estimates

    float net_rx_bps;     // bytes per second received / sent, all active interfaces except
    float net_tx_bps;     // loopback and point-to-point tunnels (a VPN would count twice)

    float disk_free_gb;   // the startup volume, decimal GB as Finder shows them (free excludes
    float disk_total_gb;  // purgeable space, so it can read lower than Finder's "available")

    uint  proc_count;     // entries used in procs (at most 5)
    ArgusProc procs[ARGUS_STATS_TOP]; // the user's own processes using the most CPU, highest first
};

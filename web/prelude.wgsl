// ============================================================================
// ARGUS WGSL THEME PRELUDE // web/prelude.wgsl
//
// The browser twin of src/gpu/argus_prelude.metal. The WebGPU host (web/host/argus_gpu.js)
// prepends it to every web/themes/*.wgsl file before compiling, so themes use these names
// without importing anything. Compile errors are reported with the theme's own line numbers.
//
// The host replaces two tokens before compiling:
//   ARGUS_STATE_FORMAT  rgba16float, or rgba32float for `// @argus state WxH float32`
//   ARGUS_OUT_FORMAT    the output texture's format (the canvas: bgra8unorm or rgba8unorm;
//                       the verify page: rgba32float, as the Metal harness reads back)
//
// How a Metal theme maps onto WGSL (web/README.md has the whole contract):
//   kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]], out [[texture(0)]], ...)
//     -> @compute @workgroup_size(X, Y) fn argus_draw(@builtin(global_invocation_id) id: vec3u)
//        f is the module-scope uniform below; write pixels with textureStore(argus_out, gid, c)
//   argus_init(state [[texture(0)]], data [[texture(1)]])
//     -> textureStore(argus_state_out, gid, v); the data file is argus_data
//   argus_step(prev [[texture(0)]], next [[texture(1)]])
//     -> textureLoad(argus_state, gid, 0) reads prev; textureStore(argus_state_out, gid, v) writes next
//   argus_draw's state [[texture(1)]]
//     -> argus_state (the state after this frame's steps)
//   constant ArgusStats& s [[buffer(1)]]  -> the module-scope storage buffer s below
//   constexpr sampler ...                 -> one of the argus_* samplers below, sampled with
//                                            textureSampleLevel(t, smp, uv, 0.0) (compute has no
//                                            derivatives; Metal's sample() reads level 0 too)
// ============================================================================

// Everything Argus tells a theme about the current frame. Same fields, order and 44-byte layout
// as Metal's ArgusFrame (src/gpu/metal_theme.zig, `Frame`).
struct ArgusFrame {
    time: f32,          // seconds of animation, continuous at any frame rate (it advances by the
                        // real frame interval); wraps to 0 every ARGUS_TIME_PERIOD (4 h)
    dt: f32,            // in argus_step: seconds since the previous step (1/30 s); in argus_draw:
                        // seconds since the previous drawn frame
    frame: u32,         // the 30 Hz simulation tick since the theme was loaded: 0, 1, 2... at any
                        // display rate (argus_step runs once per tick). Frames drawn between ticks
                        // at 60/120 Hz see the current tick's number again.
    width: u32,         // output size in pixels
    height: u32,
    state_width: u32,   // state texture size (0 x 0 when the theme keeps no state)
    state_height: u32,
    seed: u32,          // random per load: vary it to vary the theme

    // The real date and time. Read from the system clock once per frame (Date.now()); the speed,
    // pausing and the f.time wrap don't touch it. UTC (Unix time, no leap seconds). The verify
    // page pins it like the Metal harness: 2026-10-20T12:00:00Z, offset 0, advancing 1/30 s
    // per frame.
    days_j2000: i32,    // whole days since J2000.0 (2000-01-01 12:00 UTC); negative before it
    day_frac: f32,      // fraction of that day elapsed, [0, 1), from the epoch's noon: 0.5 is 00:00 UTC
    utc_offset_s: i32,  // local time zone's offset from UTC in seconds, daylight saving included
}

// Live system stats, for themes that ask with `// @argus stats` (and only them). Same layout as
// Metal's ArgusStats (428 bytes, every field 4 bytes). A web page can't read the machine's CPU,
// memory, disks or processes, so in a browser page the host fills only the fields it really
// knows (seq, sample_dt, uptime_s = the tab's, cpu_count = navigator.hardwareConcurrency,
// gpu_busy = this page's GPU share, battery_* from the Battery Status API) and leaves the rest 0;
// argus_vitals.mode says which it is (web/README.md, "Stats in a browser"). The verify page
// feeds the harness's synthetic stats (a new seq every 30 ticks) with argus_vitals.mode = 0.
const ARGUS_STATS_MAX_CORES: u32 = 32u;
const ARGUS_STATS_TOP: u32 = 5u;

struct ArgusProc {
    name: array<u32, 8>,  // process name: 32 ASCII bytes, NUL-padded, packed little-endian 4 per u32
                          // (Metal's uchar name[32]); read byte j with argus_proc_char(i, j)
    cpu: f32,             // its share of the whole machine's CPU, 0..1
    mem_gb: f32,          // memory footprint in GiB
}

struct ArgusStats {
    seq: u32,             // 0 until the first sample, then +1 each
    sample_dt: f32,       // seconds the loads and rates were measured over (about 1)
    uptime_s: u32,        // seconds since boot
    thermal: u32,         // 0 nominal, 1 fair, 2 serious, 3 critical

    cpu_total: f32,       // busy fraction of all cores, 0..1
    cpu_count: u32,       // entries used in cpu_core (logical cores, at most 32)
    cpu_p_cores: u32,     // performance cores, efficiency cores (0 and 0 if unknown)
    cpu_e_cores: u32,
    cpu_core: array<f32, 32>, // busy fraction per core, 0..1

    mem_total_gb: f32,
    mem_used_gb: f32,
    mem_compressed_gb: f32,
    mem_wired_gb: f32,
    swap_used_gb: f32,
    mem_pressure: u32,    // 0 normal, 1 warn, 2 critical

    gpu_busy: f32,        // GPU utilisation 0..1

    battery_present: u32,
    battery_charge: f32,  // 0..1
    battery_charging: u32,
    on_ac: u32,
    battery_minutes: f32, // to full while charging, to empty on battery; -1 while estimating

    net_rx_bps: f32,      // bytes per second received / sent
    net_tx_bps: f32,

    disk_free_gb: f32,
    disk_total_gb: f32,

    proc_count: u32,      // entries used in procs (at most 5)
    procs: array<ArgusProc, 5>,
}

// Web only (no Metal twin): what a browser page can honestly tell about itself, for `@argus stats`
// themes. mode 0: s is a machine's stats (the harness feed; the Argus app); mode 1: a browser page,
// s holds only the real fields above and these are the page's own vitals. `has` says which of the
// optional readings exist in this browser (ARGUS_HAS_*); a missing one is 0 and must not be shown
// as a reading. 208 bytes.
const ARGUS_HAS_GPU_TIME: u32 = 1u;     // timestamp-query
const ARGUS_HAS_THREADS: u32 = 2u;      // navigator.hardwareConcurrency
const ARGUS_HAS_DEVICE_MEM: u32 = 4u;   // navigator.deviceMemory (Chromium)
const ARGUS_HAS_HEAP: u32 = 8u;         // performance.memory (Chromium)
const ARGUS_HAS_BATTERY: u32 = 16u;     // navigator.getBattery() (Chromium)
const ARGUS_HAS_NETWORK: u32 = 32u;     // navigator.connection (Chromium)
const ARGUS_HAS_PRESSURE: u32 = 64u;    // PressureObserver 'cpu' (Chromium)
struct ArgusVitals {
    mode: u32,              // 0 machine stats, 1 browser page
    has: u32,               // ARGUS_HAS_* bits
    frame_ms: f32,          // mean display-frame interval over the last sample (requestAnimationFrame)
    frame_worst_ms: f32,    // the longest frame interval in it
    gpu_ms: f32,            // this page's GPU time per frame (timestamp queries), median of the sample
    draw_ms: f32,           // of which argus_draw
    js_ms: f32,             // JavaScript time per frame (encoding and submitting it), median
    threads: u32,           // navigator.hardwareConcurrency: logical processors
    device_mem_gb: f32,     // navigator.deviceMemory: rounded down to a power of two, capped (8 in Chrome)
    heap_used_mb: f32,      // performance.memory, MB (2^20 bytes): used, allocated, limit (coarse buckets)
    heap_total_mb: f32,
    heap_limit_mb: f32,
    net_type: u32,          // navigator.connection.effectiveType: 1 slow-2g, 2 2g, 3 3g, 4 4g
    net_downlink_mbps: f32, // its downlink estimate (rounded to 25 kbit/s) and round-trip estimate
    net_rtt_ms: f32,        // (rounded to 25 ms); both are estimates, not measurements of this page
    net_save_data: u32,
    pressure: u32,          // PressureObserver CPU state: 1 nominal, 2 fair, 3 serious, 4 critical
    canvas_w: u32,          // the canvas in device pixels, and devicePixelRatio
    canvas_h: u32,
    dpr: f32,
    adapter: array<u32, 32>, // the GPU adapter's vendor and architecture (GPUAdapterInfo), one ASCII
                             // code per entry, 0-padded
}

// ---- Bindings (fixed; the host builds one layout per kernel kind) ---------------------------
@group(0) @binding(0) var<uniform> f: ArgusFrame;
@group(0) @binding(1) var<storage, read> s: ArgusStats;          // `@argus stats` themes only
@group(0) @binding(2) var argus_state: texture_2d<f32>;          // step: prev; draw: current state
@group(0) @binding(3) var argus_state_out: texture_storage_2d<ARGUS_STATE_FORMAT, write>; // init/step
@group(0) @binding(4) var argus_data: texture_2d<f32>;           // init: the `@argus data` file
// Metal's constexpr samplers. filter::linear unless named nearest; Metal's default address
// mode is clamp_to_edge. "repeat_s" repeats along x (s) and clamps along y (t).
@group(0) @binding(5) var argus_linear_clamp: sampler;
@group(0) @binding(6) var argus_linear_repeat: sampler;
@group(0) @binding(7) var argus_linear_repeat_s: sampler;
@group(0) @binding(8) var argus_linear_repeat_t: sampler;
@group(0) @binding(9) var argus_nearest_clamp: sampler;
@group(0) @binding(10) var<storage, read> argus_vitals: ArgusVitals; // `@argus stats` themes only (web)
@group(1) @binding(0) var argus_out: texture_storage_2d<ARGUS_OUT_FORMAT, write>; // draw only

// Days since J2000.0 as one float. LOSSY: a float near 9800 days resolves only ~84 s.
fn argus_days_j2000(fr: ArgusFrame) -> f32 {
    return f32(fr.days_j2000) + fr.day_frac;
}

// Seconds since 00:00 UTC today, 0..86400. Add f.utc_offset_s for local time.
fn argus_utc_seconds(fr: ArgusFrame) -> f32 {
    return fract(fr.day_frac + 0.5) * 86400.0;
}

// f.time wraps to 0 after this many seconds.
const ARGUS_TIME_PERIOD: f32 = 14400.0;

// Pixel -> centred coordinates: (0,0) mid-screen, y up, the short side spans -1..1.
fn argus_uv(gid: vec2u, fr: ArgusFrame) -> vec2f {
    let p = (vec2f(gid) + 0.5) - 0.5 * vec2f(f32(fr.width), f32(fr.height));
    return vec2f(p.x, -p.y) / (0.5 * f32(min(fr.width, fr.height)));
}

// Pixel -> 0..1 across a w x h grid, y down (texture coordinates).
fn argus_uv01(gid: vec2u, w: u32, h: u32) -> vec2f {
    return (vec2f(gid) + 0.5) / vec2f(f32(w), f32(h));
}

// Integer hash (lowbias32): a well-mixed u32 from a u32 (u32 arithmetic wraps, as in Metal).
fn argus_hash(x_in: u32) -> u32 {
    var x = x_in;
    x ^= x >> 16u; x *= 0x7feb352du;
    x ^= x >> 15u; x *= 0x846ca68bu;
    x ^= x >> 16u;
    return x;
}

// Uniform random 0..1 per integer cell (and per seed).
fn argus_rand(cell: vec2u, seed: u32) -> f32 {
    return f32(argus_hash(cell.x ^ argus_hash(cell.y ^ argus_hash(seed)))) * (1.0 / 4294967295.0);
}

// Smooth value noise, about -1..1, one feature per unit of p.
fn argus_noise(p: vec2f) -> f32 {
    let i = floor(p);
    let fr = fract(p);
    let u = fr * fr * (3.0 - 2.0 * fr);
    let c = vec2u(vec2i(i) + 32768);
    let a = argus_rand(c, 0u);
    let b = argus_rand(c + vec2u(1u, 0u), 0u);
    let d = argus_rand(c + vec2u(0u, 1u), 0u);
    let e = argus_rand(c + vec2u(1u, 1u), 0u);
    return 2.0 * mix(mix(a, b, u.x), mix(d, e, u.x), u.y) - 1.0;
}

// Fractal noise: `octaves` layers of argus_noise, each twice as fine and half as strong.
fn argus_fbm(p_in: vec2f, octaves: i32) -> f32 {
    var p = p_in;
    var sum = 0.0;
    var amp = 0.5;
    for (var o = 0; o < octaves; o++) {
        sum += amp * argus_noise(p);
        p = mat2x2f(1.6, 1.2, -1.2, 1.6) * p;
        amp *= 0.5;
    }
    return sum;
}

// Cosine palette (Inigo Quilez): a + b * cos(2 pi (c t + d)).
fn argus_palette(t: f32, a: vec3f, b: vec3f, c: vec3f, d: vec3f) -> vec3f {
    return a + b * cos(6.2831853 * (c * t + d));
}

// Linear light -> display value. Kernels write display values; use this if you light in linear.
fn argus_srgb(lin_in: vec3f) -> vec3f {
    let lin = saturate(lin_in);
    return select(1.055 * pow(lin, vec3f(1.0 / 2.4)) - 0.055, lin * 12.92, lin <= vec3f(0.0031308));
}

// Filmic tone map (ACES fit) for HDR linear values; follow with argus_srgb.
fn argus_aces(x: vec3f) -> vec3f {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

// Byte j (0..31) of process i's name, as Metal's s.procs[i].name[j].
fn argus_proc_char(i: u32, j: u32) -> u32 {
    return (s.procs[i].name[j >> 2u] >> (8u * (j & 3u))) & 0xffu;
}

// Metal's texture2d.sample(smp, uv) in a compute kernel: level 0.
fn argus_sample(t: texture_2d<f32>, smp: sampler, uv: vec2f) -> vec4f {
    return textureSampleLevel(t, smp, uv, 0.0);
}

// Used by the host when a stateful theme has no argus_init: starts its state at zero.
@compute @workgroup_size(8, 8)
fn argus_clear_state(@builtin(global_invocation_id) id: vec3u) {
    let d = textureDimensions(argus_state_out);
    if (id.x >= d.x || id.y >= d.y) { return; }
    textureStore(argus_state_out, id.xy, vec4f(0.0));
}

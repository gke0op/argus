// ============================================================================
// GEMINI AQUARIUM // themes/Gemini_Aquarium.metal
//
// A slow drift over a sandy seabed. Light comes down from the surface in
// moving shafts, kelp sways, bubbles rise, and four kinds of fish school
// across the view: neon tetras, clownfish, yellow tangs and a few big silver
// fish. Marine snow hangs in the water and the far reef fades into blue.
//
// Lineage: Google Gemini wrote Gemini_Cyber_Topography (ARGUS-BENCH Track C),
// a wireframe canyon flown over by a 3D boids swarm. Claude Opus turned it
// into the Zig aquarium (themes/Gemini_Aquarium.zig): the canyon became the
// reef and seabed, the drones became schooling fish, the sky became a water
// column. Claude Opus then ported it to this Metal-only GPU theme.
//
// How it's drawn:
//   - argus_step runs the same 168-fish boids simulation as the Zig theme (one
//     thread per fish, 17 school-mates each), then projects every fish into a
//     ready-to-draw record (head, tail, body depth, wag) in the state texture.
//   - argus_draw shades every pixel: water gradient + slanted god rays, the
//     seabed wireframe (contour ribs and depth filaments) found per pixel as
//     distances to the projected terrain curves, then kelp, marine snow,
//     bubbles and fish. Kelp, snow, bubbles and fish are culled cooperatively:
//     each SIMD group (a 32-pixel strip) splits the object list across its
//     lanes, votes on which objects touch its strip, and shades only those.
//   - Kelp, snow and bubbles are closed-form functions of time (world-z slots
//     and life cycles), so they need no state. Same terrain, camera and
//     palette numbers as the Zig original.
//
// State: 512x262 float32. Rows 0-3: fish position + size, velocity + wag phase,
// projected head/tail, (half depth px, z, kind, wag px). Rows 4-9: snow, bubble,
// kelp and fish-bounding-box screen records. Rows 10-111: the seabed grid sampled
// along its 46 ribs and 56 filaments (height, slope, light) for this frame.
// Rows 112-261: marine snow binned into 150 screen bands of up to 32 motes.
//
// @argus state 512x262 float32
// ============================================================================

constant float HORIZON   = 0.42f;   // horizon line as a fraction of height
constant float FOCAL     = 0.80f;   // focal length as a fraction of height
constant float CAM_SPEED = 0.6f;    // world units per second along +z
constant float CAM_Y     = 5.6f;
constant float SURFACE_Y = 15.0f;
constant float SCROLL_PERIOD = 6283.18530718f;   // every seabed z frequency is a multiple of 0.001
constant float Z_SPACING = 1.8f;
constant int   GRID_Z    = 46;
constant float TMIN = -0.55f, TMAX = 8.85f;      // terrain bounds, for culling
constant float TAU = 6.2831853f;

constant int   NUM_FISH  = 168;
// State rows (see the header).
constant uint ROW_SNOW = 4, ROW_BUB = 5, ROW_KELP = 6, ROW_FBOX = 9, ROW_RIB = 10, ROW_COL = 56,
              ROW_SBIN = 112, SNOW_BINS = 150, BIN_K = 32;
constant int   NUM_SNOW  = 420;
constant int   NUM_BUB   = 64;
constant int   KELP_SLOTS = 5497;                 // world-z kelp slots per scroll period
constant float KELP_S    = SCROLL_PERIOD / 5497.0f; // ~1.143: 56 stalks over 64 units of depth

// Species i % 8 -> kind. 0 neon tetra, 1 yellow tang, 2 clownfish, 3 silver.
constant int   KIND_OF_SLOT[8] = { 0, 0, 2, 1, 0, 2, 0, 3 };
constant float KIND_SIZE[4]  = { 0.34f, 0.70f, 0.50f, 1.10f };
constant float KIND_DEPTH[4] = { 0.15f, 0.30f, 0.21f, 0.15f };
constant float KIND_SPEED[4] = { 1.25f, 0.85f, 0.95f, 0.70f };
constant float3 KIND_BACK[4]  = { float3(38, 78, 150) / 255.0f, float3(245, 196, 30) / 255.0f,
                                  float3(236, 98, 16) / 255.0f, float3(70, 96, 122) / 255.0f };
constant float3 KIND_BELLY[4] = { float3(196, 210, 226) / 255.0f, float3(255, 232, 96) / 255.0f,
                                  float3(255, 150, 52) / 255.0f, float3(214, 224, 230) / 255.0f };

// ------------------------------------------------------------------ helpers --

static inline float rnd(thread uint& s) {
    s = argus_hash(s + 0x9E3779B9u);
    return float(s >> 8) * (1.0f / 16777216.0f);
}

static inline float pmod(float x, float m) { return x - m * floor(x / m); }

struct Cam {
    float sz;     // scroll along z, wrapped
    float cx;     // camera world x
    float cy;     // camera height
    float roll;
    float fh;     // focal length in pixels
    float2 c;     // vanishing point (pixels, y down)
};

static inline float camx_at(float sz) { return 4.2f * sin(sz * 0.045f) + 1.8f * cos(sz * 0.019f); }

static Cam camera(constant ArgusFrame& f) {
    Cam k;
    k.sz = pmod(CAM_SPEED * f.time, SCROLL_PERIOD);
    k.cx = camx_at(k.sz);
    k.cy = CAM_Y + 0.35f * sin(0.21f * f.time);
    k.roll = -0.02f * cos(k.sz * 0.045f);
    k.fh = FOCAL * float(f.height);
    k.c = float2(0.5f * float(f.width), HORIZON * float(f.height));
    return k;
}

// Dual numbers (value, derivative) so the terrain hands back its slope for line widths.
static inline float2 dsin(float2 a) { float c; const float s = sincos(a.x, c); return float2(s, c * a.y); }
static inline float2 dcos(float2 a) { float c; const float s = sincos(a.x, c); return float2(c, -s * a.y); }
static inline float2 dmul(float2 a, float2 b) { return float2(a.x * b.x, a.x * b.y + a.y * b.x); }

// Seabed height at world (wx, wz): a winding sandy channel between reef ridges
// (Gemini's canyon harmonics scaled to reef height). Pass derivative seeds in .y.
static float2 terrain_d(float2 wx, float2 wz) {
    const float2 center = 6.5f * dsin(0.045f * wz) + 3.0f * dcos(0.019f * wz);
    const float2 dx = wx - center;
    const float2 q = float2(1.0f, 0.0f) + 0.012f * dmul(dx, dx);
    const float2 env = float2(1.0f - 1.0f / q.x, q.y / (q.x * q.x));
    const float2 h1 = dmul(dsin(0.14f * wx + 0.09f * wz), dcos(0.08f * wx - 0.12f * wz));
    const float2 h2 = 0.52f * dsin(0.31f * wx - 0.23f * wz + 1.4f * h1);
    const float2 h3 = 0.25f * dcos(0.62f * wx + 0.48f * wz);
    float2 r = h1 + h2 + h3;
    r.x += 0.9f;
    const float2 reef = r.x > 0.0f ? 3.1f * r : float2(0.0f);
    const float2 dune = 0.45f * dmul(dsin(0.21f * wx + 0.13f * wz), dcos(0.07f * wx - 0.17f * wz));
    const float2 ripple = 0.07f * dsin(1.4f * wx + 0.9f * wz);
    return dmul(env, reef) + dune + ripple;
}

static inline float terrain(float wx, float wz) { return terrain_d(float2(wx, 0.0f), float2(wz, 0.0f)).x; }

// Water column: bright teal under the surface, blue haze at the horizon, deep below.
static float3 water(float ny) {
    const float3 top = float3(30, 104, 128) / 255.0f;
    const float3 hor = float3(10, 54, 84) / 255.0f;
    const float3 bot = float3(3, 18, 36) / 255.0f;
    if (ny < HORIZON) return mix(top, hor, pow(max(ny / HORIZON, 0.0f), 0.8f));
    return mix(hor, bot, pow(saturate((ny - HORIZON) / (1.0f - HORIZON)), 0.55f));
}

// ---------------------------------------------------------------- the fish --

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    const int i = int(gid.x);
    uint s = argus_hash(uint(i) * 0x2545F491u + 0x5EAF1002u);
    const int kind = KIND_OF_SLOT[i % 8];
    const float size = KIND_SIZE[kind] * (0.85f + 0.3f * rnd(s));
    const float x = (rnd(s) - 0.5f) * 24.0f;
    const float y = 3.0f + rnd(s) * 5.0f;
    const float z = 8.0f + rnd(s) * 22.0f;
    const float vx = (rnd(s) - 0.5f) * 2.0f;
    const float vz = (rnd(s) - 0.5f) * 0.5f;
    const float wag = rnd(s) * TAU;
    float4 v = float4(0.0f);
    if (gid.y == 0) v = float4(x, y, z, size);
    else if (gid.y == 1) v = float4(vx, 0.0f, vz, wag);
    state.write(v, gid);
}

// One thread per fish does the whole boids update and writes all four rows of its column.
static void step_fish(constant ArgusFrame& f, texture2d<float, access::read> prev,
                      texture2d<float, access::write> next, int i) {
    const int slot = i % 8;
    const int kind = KIND_OF_SLOT[slot];
    const float slot_f = float(slot), kf = float(kind);
    const float dt = clamp(f.dt, 0.0f, 0.05f);
    const float t = f.time;
    const Cam cam = camera(f);

    const float4 P = prev.read(uint2(i, 0));
    const float4 V = prev.read(uint2(i, 1));
    float3 p = P.xyz, v = V.xyz;
    const float size = P.w;
    float wag = V.w;

    // Each school chases a slowly wandering point in front of the camera.
    const float tz = 9.0f + 3.4f * slot_f + 5.0f * sin(0.053f * t + slot_f * 1.3f);
    const float tx = 0.55f * tz * sin(0.071f * t + slot_f * 1.9f) + 3.0f * sin(0.19f * t + kf * 0.7f);
    const float ty = 5.2f + 3.2f * sin(0.11f * t + slot_f * 2.3f);

    float3 sep = 0.0f, ali = 0.0f, coh = 0.0f;
    float n = 0.0f;
    const float sep_r2 = 2.2f * size * size;
    for (int k = 1; k < 18; k++) {
        const int j = (i + k * 8) % NUM_FISH;   // same slot -> same school
        const float3 op = prev.read(uint2(j, 0)).xyz;
        const float3 ov = prev.read(uint2(j, 1)).xyz;
        const float3 d = op - p;
        const float d2 = dot(d, d);
        if (d2 > 1e-4f && d2 < 16.0f) {
            if (d2 < sep_r2) sep -= d / d2;
            ali += ov;
            coh += op;
            n += 1.0f;
        }
    }
    if (n > 0.0f) {
        const float3 a = ali / n - v, c = coh / n - p;
        v += (a * float3(1.2f, 1.2f, 1.0f) + c * float3(0.5f, 0.5f, 0.3f) + sep * float3(1.6f, 1.6f, 1.2f)) * dt;
    }
    v.x += clamp(tx - p.x, -6.0f, 6.0f) * 0.30f * dt;
    v.y += clamp(ty - p.y, -4.0f, 4.0f) * 0.35f * dt;
    v.z += clamp(tz - p.z, -8.0f, 8.0f) * 0.12f * dt;
    v.y *= 1.0f - 0.6f * dt;   // fish swim level
    v.z *= 1.0f - 0.5f * dt;   // and mostly across the view, so we see them side-on

    const float ground = terrain(p.x + cam.cx, cam.sz + p.z) + 0.9f;
    if (p.y < ground) v.y += (ground - p.y) * 6.0f * dt;
    if (p.y > 11.0f) v.y -= (p.y - 11.0f) * 3.0f * dt;

    const float sp = length(v);
    const float lo = 0.9f * KIND_SPEED[kind], hi = 2.6f * KIND_SPEED[kind];
    const float cs = clamp(sp, lo, hi);
    if (sp > 1e-4f) v = v / sp * cs; else v = float3(lo, 0.0f, 0.0f);
    // Keep some forward way on, so nobody hangs head-up in the water.
    const float hs0 = length(v.xz);
    if (hs0 < 0.6f * lo) {
        if (hs0 > 1e-4f) { v.x *= 0.6f * lo / hs0; v.z *= 0.6f * lo / hs0; }
        else v.x = 0.6f * lo;
    }
    p += v * dt;
    p.z -= CAM_SPEED * dt;
    p = clamp(p, float3(-40.0f, -2.0f, 3.0f), float3(40.0f, SURFACE_Y, 45.0f));
    wag = pmod(wag + dt * (5.0f + 3.0f * cs / size), TAU);

    // Project into a ready-to-draw record (screen without roll; argus_draw un-rolls its pixels).
    float4 seg = float4(0.0f), body = float4(0.0f), box = float4(1e9f, 1e9f, -1e9f, -1e9f);
    const float hs = length(v.xz);
    const float pv = clamp(0.3f * v.y, -0.4f * hs, 0.4f * hs);
    const float3 dv = float3(v.x, pv, v.z);
    const float spo = length(dv);
    if (spo > 1e-4f) {
        const float3 d = dv / spo;
        const float half_len = 0.5f * size;
        const float ry = p.y - cam.cy;
        const float zh = p.z + d.z * half_len, zt = p.z - d.z * half_len;
        float2 hd = cam.c + float2(p.x + d.x * half_len, -(ry + d.y * half_len)) * (cam.fh / zh);
        float2 tl = cam.c + float2(p.x - d.x * half_len, -(ry - d.y * half_len)) * (cam.fh / zt);
        const float W = cam.fh * size * KIND_DEPTH[kind] / p.z;   // half body depth in px
        float2 ax = tl - hd;
        float L = length(ax);
        if (L < 1e-3f) { ax = float2(1.0f, 0.0f); L = 1.0f; } else ax /= L;
        // A fish seen nose-on still reads as a fish, not a dot.
        if (L < 2.2f * W) {
            const float2 m = 0.5f * (hd + tl);
            L = 2.2f * W;
            hd = m - ax * 0.5f * L;
            tl = m + ax * 0.5f * L;
        }
        const float pad = 1.2f * W + 2.0f;
        const float2 ext = abs(tl - hd) + 2.0f * pad;
        const float cap = 360.0f * float(f.height) / 1200.0f;
        if (W >= 0.5f && ext.x * ext.y <= cap * cap) {
            seg = float4(hd, tl);
            body = float4(W, p.z, float(kind), 0.11f * L * sin(wag));
            const float bpad = pad + abs(body.w);
            box = float4(min(hd, tl) - bpad, max(hd, tl) + bpad);
        }
    }
    next.write(float4(p, size), uint2(i, 0));
    next.write(float4(v, wag), uint2(i, 1));
    next.write(seg, uint2(i, 2));
    next.write(body, uint2(i, 3));
    next.write(box, uint2(i, ROW_FBOX));
}

// Fish outline: blunt nose, deepest at a third of the length, narrow tail root.
static inline float fish_prof(float u) {
    return u <= 0.78f ? 0.18f + 0.82f * sin(M_PI_F * pow(saturate(u / 0.78f), 0.62f)) : 0.18f;
}

// Shades one fish at pixel q. Returns colour in .rgb and coverage in .a (0 = miss).
static float4 shade_fish(float2 q, float4 seg, float4 body, float3 wcol) {
    const float W = body.x;
    const int kind = int(body.z + 0.5f);
    float2 ax = seg.zw - seg.xy;
    const float L = max(length(ax), 1e-3f);
    ax /= L;
    const float2 dd = q - seg.xy;
    const float u = dot(dd, ax) / L;
    if (u < -0.03f || u > 1.0f) return float4(0.0f);
    const float uc = saturate(u);
    const float v = (dd.x * -ax.y + dd.y * ax.x) - body.w * uc * uc;
    const float av = abs(v);
    float hw = W * fish_prof(uc);
    bool is_tail = false;
    if (u > 0.74f) {
        const float tf = (u - 0.74f) / 0.26f;
        const float tw = W * 1.05f * tf;
        const float notch = tf > 0.7f ? W * 0.5f * (tf - 0.7f) / 0.3f : 0.0f;   // forked tail
        if (tw > hw && av > notch) { hw = tw; is_tail = true; }
    }
    const float cov = saturate(hw - av + 0.5f);
    if (cov <= 0.0f) return float4(0.0f);

    const float belly = ax.x >= 0.0f ? 1.0f : -1.0f;   // belly points down the screen
    const float s = clamp(v * belly / max(hw, 0.5f), -1.0f, 1.0f);
    float3 col = mix(KIND_BACK[kind], KIND_BELLY[kind], 0.5f + 0.5f * s);
    if (kind == 0) {          // neon tetra: electric blue stripe, red rear belly
        if (!is_tail && abs(s + 0.05f) < 0.17f && u > 0.08f && u < 0.74f) col = float3(50, 200, 255) / 255.0f;
        else if (!is_tail && s > 0.2f && u > 0.42f && u < 0.76f) col = float3(225, 40, 52) / 255.0f;
    } else if (kind == 1) {   // yellow tang: pale spine at the tail root
        if (u > 0.70f && u < 0.76f) col = float3(255, 250, 235) / 255.0f;
    } else if (kind == 2) {   // clownfish: white bands with dark edges
        if ((u > 0.22f && u < 0.30f) || (u > 0.50f && u < 0.57f)) col = float3(248, 246, 240) / 255.0f;
        else if ((u > 0.205f && u < 0.315f) || (u > 0.485f && u < 0.585f) || (is_tail && u > 0.94f))
            col = float3(30, 18, 12) / 255.0f;
    } else {                  // silver: bright lateral line
        if (!is_tail && abs(s) < 0.07f) col = float3(235, 242, 248) / 255.0f;
    }
    const float eu = (u - 0.12f) * L;
    const float ev = v * belly + 0.22f * W;
    const float er = max(0.8f, 0.17f * W);
    if (eu * eu + ev * ev < er * er) col = float3(14, 14, 20) / 255.0f;
    const float fog = clamp(1.0f - exp(-0.045f * body.y), 0.0f, 0.9f);
    return float4(mix(col, wcol, fog), cov * (245.0f / 256.0f));
}

// ------------------------------------------------- per-frame object tables --
// argus_step also refreshes, every frame, the screen records of everything else, so
// argus_draw only reads them: marine snow, bubbles, kelp slots, and the seabed grid
// sampled finely along each rib and each depth filament.

constant float TABLE_N = 512.0f;
constant float COL_Z0 = 0.6f, COL_Z1 = 82.8f;   // depth range sampled along each filament

// The seabed grid's lighting at one point: (height, slope, light, unused).
static float4 grid_sample(float wx, float wz, float2 seed_d, float rz, float t) {
    const float2 T = terrain_d(float2(wx, seed_d.x), float2(wz, seed_d.y));
    const float caus = max(0.0f, sin(wx * 0.9f + 0.70f * t) * sin(wz * 0.8f - 0.50f * t + wx * 0.3f));
    const float fade = saturate(exp(-0.040f * rz) * smoothstep(0.6f, 3.5f, rz));
    return float4(T, fade * (0.55f + 0.9f * caus * caus), 0.0f);
}

kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    const uint x = gid.x, y = gid.y;
    const float t = f.time;
    const Cam cam = camera(f);
    const float xf = float(x) / (TABLE_N - 1.0f);

    if (y < ROW_SNOW) {                       // fish: thread (i, 0) writes rows 0..3
        if (y == 0 && int(x) < NUM_FISH) step_fish(f, prev, next, int(x));
        return;
    }
    float4 o = float4(0.0f);
    if (y == ROW_SNOW) {                      // 420 motes drifting toward the camera, sinking slowly
        if (int(x) < NUM_SNOW) {
            uint s = argus_hash(x * 0x85EBCA6Bu + 0x5A0Fu);
            const float x0 = (rnd(s) - 0.5f) * 50.0f;
            const float y0 = rnd(s) * SURFACE_Y;
            const float z0 = rnd(s) * 40.0f;
            const float ph = rnd(s) * TAU;
            const float z = 1.5f + pmod(z0 - CAM_SPEED * t, 40.0f);
            const float yy = -1.0f + pmod(y0 + 1.0f - 0.08f * t, SURFACE_Y + 1.0f);
            const float xx = x0 - 0.4f * cos(0.3f * t + ph);
            const float2 sp = cam.c + float2(xx, -(yy - cam.cy)) * (cam.fh / z);
            o = float4(sp, z < 6.0f ? 1.0f : 0.5f, (70.0f * exp(-0.05f * z) + 8.0f) / 255.0f);
        }
    } else if (y == ROW_BUB) {                // bubbles: rise from the seabed, drift closer, respawn
        if (int(x) < NUM_BUB) {
            uint s = argus_hash(x * 0x27D4EB2Fu + 0xB0B1u);
            const float vy = 1.2f + 1.2f * rnd(s);
            const float y0 = 0.3f + 2.5f * rnd(s);
            const float P = (SURFACE_Y - y0) / vy;
            const float tt = t + rnd(s) * P;
            const float ph = rnd(s) * TAU;
            const float cyc = floor(tt / P);
            const float tau = tt - cyc * P;
            uint s2 = argus_hash(s ^ argus_hash(uint(int(cyc)) + 0x51EDu));
            const float bx = (rnd(s2) - 0.5f) * 30.0f;
            const float z = 6.0f + 28.0f * rnd(s2) - CAM_SPEED * tau;
            const float r = 0.04f + 0.10f * rnd(s2);
            const float by = y0 + vy * tau;
            const float wob = 0.12f * sin(ph + 3.1f * tau);
            if (z >= 2.5f) {
                const float k = cam.fh / z;
                const float2 sp = cam.c + float2(bx + wob, -(by - cam.cy)) * k;
                o = float4(sp, k * r >= 0.6f ? k * r : 0.0f, clamp(exp(-0.04f * z), 0.2f, 1.0f));
            }
        }
    } else if (y == ROW_KELP) {               // kelp slot j: thread writes rows 6..8
        if (x < 58u) {
            const int m = int(floor((cam.sz + 2.0f) / KELP_S)) - 1 + int(x);
            uint s = argus_hash(uint((m % KELP_SLOTS + KELP_SLOTS) % KELP_SLOTS) * 0x9E3779B1u + 0x4E1Bu);
            const float zw = (float(m) + rnd(s)) * KELP_S;
            const float rz = zw - cam.sz;
            const float xw = camx_at(zw - 66.0f) + (rnd(s) - 0.5f) * 60.0f;
            const float hgt = 3.5f + 5.5f * rnd(s);
            const float ph = rnd(s) * TAU;
            float4 a = float4(0.0f), b = float4(0.0f), box = float4(1e9f, 1e9f, -1e9f, -1e9f);
            if (rz >= 2.0f && rz < 66.0f) {
                const float base = terrain(xw, zw) - 0.2f;
                const float xr = xw - cam.cx;
                const float kmin = cam.fh / (rz + 0.3f), kmax = cam.fh / max(rz - 0.3f, 1.0f);
                const float thick = clamp(cam.fh * 0.22f / rz, 1.0f, 16.0f);
                const float yb = base - cam.cy, yt = base + hgt - cam.cy;
                box = float4(cam.c.x + min((xr - 0.9f) * kmin, (xr - 0.9f) * kmax) - thick - 2.0f,
                             cam.c.y - max(yt * kmin, yt * kmax) - 2.0f,
                             cam.c.x + max((xr + 0.9f) * kmin, (xr + 0.9f) * kmax) + thick + 2.0f,
                             cam.c.y - min(yb * kmin, yb * kmax) + 2.0f);
                const float fade = saturate(exp(-0.045f * rz));
                a = float4(rz, xr, base, hgt);
                b = float4(ph, thick, fade, 1.0f);
            }
            next.write(a, uint2(x, ROW_KELP));
            next.write(b, uint2(x, ROW_KELP + 1));
            next.write(box, uint2(x, ROW_KELP + 2));
        }
        return;
    } else if (y < ROW_RIB) {
        return;                               // rows 7, 8: kelp threads; row 9: fish threads
    } else if (y < ROW_COL) {                 // rib `rev`: terrain along x at a fixed depth
        const float rz = float(y - ROW_RIB + 1) * Z_SPACING - pmod(cam.sz, Z_SPACING);
        const float wx = cam.cx + xf * 80.0f - 40.0f;
        o = grid_sample(wx, cam.sz + rz, float2(1.0f, 0.0f), rz, t);
    } else if (y < ROW_SBIN) {                // filament c: terrain along depth at a fixed x
        const float Xc = (float(2u * (y - ROW_COL)) / 111.0f - 0.5f) * 80.0f;
        const float rz = mix(COL_Z0, COL_Z1, xf);
        o = grid_sample(cam.cx + Xc, cam.sz + rz, float2(0.0f, 1.0f), rz, t);
    } else {
        // Snow bin b: the motes (from last frame's snow row) near screen band b, so a strip
        // of pixels reads one bin instead of all 420 motes. One thread fills the whole bin.
        if (x != 0u || y >= ROW_SBIN + SNOW_BINS) return;
        const float bh = float(f.height) / float(SNOW_BINS);
        const float ylo = float(y - ROW_SBIN) * bh - 4.0f, yhi = ylo + bh + 8.0f;
        const float wmax = float(f.width) + 2.0f;
        uint n = 0;
        for (int i = 0; i < NUM_SNOW && n < BIN_K; i++) {
            const float4 m = prev.read(uint2(i, ROW_SNOW));
            if (m.w > 0.0f && m.y >= ylo && m.y < yhi && m.x > -2.0f && m.x < wmax) next.write(m, uint2(n++, y));
        }
        for (; n < BIN_K; n++) next.write(float4(-1e4f, -1e4f, 0.0f, 0.0f), uint2(n, y));
        return;
    }
    next.write(o, gid);
}

// ------------------------------------------------------------- the seabed --

static inline float3 seabed_rgb(float4 g) {
    const float alt = saturate(g.x / 6.5f);
    float3 c;
    if (alt < 0.18f) c = float3(226, 190, 128);
    else if (alt < 0.6f) c = mix(float3(226, 190, 128), float3(70, 158, 172), (alt - 0.18f) / 0.42f);
    else c = mix(float3(70, 158, 172), float3(240, 106, 150), (alt - 0.6f) / 0.4f);
    return c * (g.z / 255.0f);
}

static inline uint ballot(bool b) { return uint(static_cast<simd_vote::vote_t>(simd_ballot(b))); }

// Additive wireframe at unrolled pixel q: contour ribs (constant depth) plus depth
// filaments (constant camera-relative x), each a 1 px anti-aliased line found as the
// distance to the projected terrain curve, read from the tables argus_step built.
// Culling is cooperative: each lane checks two ribs and two filaments against the
// SIMD group's strip (gmin..gmax), and the group then draws only the ones that cross it.
static float3 wireframe(float2 q, Cam cam, texture2d<float> st, float sh,
                        uint lane, float2 gmin, float2 gmax) {
    constexpr sampler lin(filter::linear, address::clamp_to_edge, coord::normalized);
    const float dxp = q.x - cam.c.x;
    const float zfrac = pmod(cam.sz, Z_SPACING);
    const float zfar = float(GRID_Z) * Z_SPACING - zfrac;
    const float znear = max(Z_SPACING - zfrac, 0.6f);
    const float tx = (TABLE_N - 1.0f) / TABLE_N, t0 = 0.5f / TABLE_N;
    auto rib = [&](int rev, float u) {
        return st.sample(lin, float2(t0 + saturate(u) * tx, (float(ROW_RIB + uint(rev)) + 0.5f) / sh));
    };
    auto fil = [&](int c, float rz) {
        const float u = (rz - COL_Z0) / (COL_Z1 - COL_Z0);
        return st.sample(lin, float2(t0 + saturate(u) * tx, (float(ROW_COL + uint(c)) + 0.5f) / sh));
    };
    float3 acc = 0.0f;

    // Ribs: the grid spans 80 world units of x around the camera.
    for (int pass = 0; pass < 2; pass++) {
        const int rev = int(lane) + 32 * pass;
        bool hit = false;
        if (rev < GRID_Z) {
            const float rz = float(rev + 1) * Z_SPACING - zfrac;
            const float k = cam.fh / rz;
            const float u0 = ((gmin.x - cam.c.x) / k + 40.0f) / 80.0f;
            const float u1 = ((gmax.x - cam.c.x) / k + 40.0f) / 80.0f;
            if (rz >= 0.6f && u1 >= 0.0f && u0 <= 1.0f) {
                const float4 g0 = rib(rev, u0), g1 = rib(rev, u1);
                const float y0 = cam.c.y - (g0.x - cam.cy) * k, y1 = cam.c.y - (g1.x - cam.cy) * k;
                const float span = (saturate(u1) - saturate(u0)) * 80.0f;     // world units across the strip
                const float m = 2.0f + span * k * (0.25f * abs(g0.y - g1.y) + 0.1f);
                hit = max(y0, y1) + m >= gmin.y && min(y0, y1) - m <= gmax.y;
            }
        }
        uint mask = ballot(hit);
        while (mask != 0u) {
            const uint l = ctz(mask);
            mask &= mask - 1u;
            const int r = int(l) + 32 * pass;
            const float rz = float(r + 1) * Z_SPACING - zfrac;
            const float k = cam.fh / rz;
            const float u = (dxp / k + 40.0f) / 80.0f;
            if (u < 0.0f || u > 1.0f) continue;
            const float4 g = rib(r, u);
            const float yr = cam.c.y - (g.x - cam.cy) * k;
            const float dist = abs(q.y - yr) * rsqrt(1.0f + g.y * g.y);
            if (dist < 1.0f) acc += (1.0f - dist) * seabed_rgb(g);
        }
    }

    // Filaments: every other grid column, from the nearest rib to the farthest.
    for (int pass = 0; pass < 2; pass++) {
        const int c = int(lane) + 32 * pass;
        bool hit = false;
        if (c < 56) {
            const float Xc = (float(2 * c) / 111.0f - 0.5f) * 80.0f;
            // Depth range this column covers across the strip's x range.
            const float d0 = (Xc > 0.0f ? gmax.x : gmin.x) - cam.c.x;   // farthest from centre -> nearest depth
            const float d1 = (Xc > 0.0f ? gmin.x : gmax.x) - cam.c.x;
            if (d0 * Xc > 0.0f) {
                const float za = max(Xc * cam.fh / d0, znear);
                const float zb = d1 * Xc > 0.0f ? min(Xc * cam.fh / d1, zfar) : zfar;
                if (za <= zb) {
                    if (zb - za > 6.0f) hit = true;   // near-vertical through this strip: just draw it
                    else {
                        const float zm = 0.5f * (za + zb);
                        const float ya = cam.c.y - (fil(c, za).x - cam.cy) * cam.fh / za;
                        const float yb = cam.c.y - (fil(c, zb).x - cam.cy) * cam.fh / zb;
                        const float ym = cam.c.y - (fil(c, zm).x - cam.cy) * cam.fh / zm;
                        const float lo = min(min(ya, yb), ym), hi = max(max(ya, yb), ym);
                        const float m = 2.0f + 0.5f * (hi - lo);
                        hit = hi + m >= gmin.y && lo - m <= gmax.y;
                    }
                }
            }
        }
        uint mask = ballot(hit);
        while (mask != 0u) {
            const uint l = ctz(mask);
            mask &= mask - 1u;
            const int cc = int(l) + 32 * pass;
            const float Xc = (float(2 * cc) / 111.0f - 0.5f) * 80.0f;
            if (dxp * Xc <= 0.0f) continue;
            const float rz = Xc * cam.fh / dxp;
            if (rz < znear || rz > zfar) continue;
            const float4 g = fil(cc, rz);
            const float yc = cam.c.y - (g.x - cam.cy) * cam.fh / rz;
            const float slope = (g.y * rz - (g.x - cam.cy)) / Xc;
            const float dist = abs(q.y - yc) * rsqrt(1.0f + slope * slope);
            if (dist < 1.0f) acc += (1.0f - dist) * (150.0f / 256.0f) * seabed_rgb(g);
        }
    }
    return acc;
}

// ------------------------------------------------------------------- draw --

static inline bool overlaps(float4 box, float2 gmin, float2 gmax) {
    return box.z >= gmin.x && box.x <= gmax.x && box.w >= gmin.y && box.y <= gmax.y;
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> state [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]],
                       uint lane [[thread_index_in_simdgroup]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float t = f.time;
    const Cam cam = camera(f);
    const float h = float(f.height);
    const float2 p = float2(gid) + 0.5f;

    // 1. Water column and god rays (screen space, like the Zig theme: the rays don't roll).
    const float ny = p.y / h;
    const float3 wcol = water(ny);
    float3 col = wcol;
    {
        const float gain = 150.0f * exp(-2.4f * ny) * (1.0f - smoothstep(0.55f, 0.95f, ny)) / 256.0f;
        if (gain > 0.0f) {
            const float u = (p.x + p.y * (26.0f / 64.0f)) * (1200.0f / h);
            const float b1 = 0.5f + 0.5f * sin(u * 0.0062f + 0.13f * t);
            const float b2 = 0.5f + 0.5f * sin(u * 0.0147f - 0.21f * t + 1.7f);
            const float b3 = 0.5f + 0.5f * sin(u * 0.0310f + 0.47f * t + 0.4f);
            float v = b1 * b2 * (0.55f + 0.45f * b3);
            v = min(v * v * 1.7f, 1.0f);
            col += v * gain * float3(110, 190, 200) / 256.0f;
        }
    }

    // Everything 3D lives in the camera's un-rolled frame: rotate this pixel back.
    float2 q;
    {
        const float cr = cos(cam.roll), sr = sin(cam.roll);
        const float uu = p.x - cam.c.x, vv = cam.c.y - p.y;
        q = cam.c + float2(uu * cr + vv * sr, uu * sr - vv * cr);
    }
    // This SIMD group's pixel bounds, for cooperative culling.
    const float2 gmin = float2(simd_min(q.x), simd_min(q.y));
    const float2 gmax = float2(simd_max(q.x), simd_max(q.y));

    // 2. Seabed wireframe.
    col += wireframe(q, cam, state, float(f.state_height), lane, gmin, gmax);

    // 3. Kelp, far to near (higher slot = farther).
    {
        const float pt = 0.8f * t;
        for (int c = 1; c >= 0; c--) {
            const uint j = lane + 32u * uint(c);
            const bool hit = j < 58u && overlaps(state.read(uint2(j, ROW_KELP + 2)), gmin, gmax);
            uint mask = ballot(hit);
            while (mask != 0u) {
                const uint l = 31u - clz(mask);
                mask &= ~(1u << l);
                const uint jj = l + 32u * uint(c);
                const float4 K = state.read(uint2(jj, ROW_KELP));       // (rz, x rel, base, height)
                const float4 K2 = state.read(uint2(jj, ROW_KELP + 1));  // (phase, thick, fade, valid)
                const float rz = K.x, k = cam.fh / rz;
                const float fy = ((cam.c.y - q.y) / k + cam.cy - K.z) / K.w;   // height fraction at this row
                if (fy < -0.05f || fy > 1.05f) continue;
                const float fc = saturate(fy);
                const float sway = fc * fc * 0.9f * sin(pt + K2.x - fc * 2.2f);
                const float xc = cam.c.x + (K.y + sway) * cam.fh / (rz + 0.3f * sway);
                const float hw = 0.5f * max(1.0f, K2.y * (1.0f - fc) + K2.y / 12.0f);   // taper to the tip
                float a = saturate(hw + 0.5f - abs(q.x - xc));
                const float px_h = K.w * k;
                a *= saturate(fy * px_h + 0.5f) * saturate((1.0f - fy) * px_h + 0.5f);
                const float fade = K2.z;
                const float3 kc = float3(10.0f + 42.0f * fade, 54.0f + 96.0f * fade, 84.0f - 14.0f * fade) / 255.0f;
                col = mix(col, kc, a * 0.88f);
            }
        }
    }

    // 4. Marine snow.
    {
        const float bh = h / float(SNOW_BINS);
        const uint bin = uint(clamp(floor(gmin.y / bh), 0.0f, float(SNOW_BINS - 1u)));
        const float4 m = state.read(uint2(lane % BIN_K, ROW_SBIN + bin));
        uint mask = ballot(overlaps(float4(m.xy - 2.0f, m.xy + 2.0f), gmin, gmax));
        while (mask != 0u) {
            const uint l = ctz(mask);
            mask &= mask - 1u;
            const float4 M = simd_shuffle(m, ushort(l));
            col += saturate(M.z + 0.5f - length(q - M.xy)) * M.w * float3(0.5f, 0.75f, 1.0f);
        }
    }

    // 5. Bubbles: a thin rim and a glint at the upper left.
    for (int c = 0; c < 2; c++) {
        const float4 b = state.read(uint2(lane + 32u * uint(c), ROW_BUB));   // (sx, sy, rpx, fade)
        const float e = b.z + 2.0f;
        uint mask = ballot(b.z > 0.0f && overlaps(float4(b.xy - e, b.xy + e), gmin, gmax));
        while (mask != 0u) {
            const uint l = ctz(mask);
            mask &= mask - 1u;
            const float4 B = simd_shuffle(b, ushort(l));
            col += saturate(1.0f - abs(length(q - B.xy) - B.z)) * B.w * float3(80, 130, 150) / 255.0f;
            col += saturate(1.0f - length(q - (B.xy - 0.4f * B.z))) * B.w * float3(150, 200, 210) / 255.0f;
        }
    }

    // 6. Fish, from the simulation's draw records: keep the nearest two at this pixel,
    //    composite the farther one first.
    {
        float4 c1 = float4(0.0f), c2 = float4(0.0f);
        float z1 = 1e9f, z2 = 1e9f;
        for (int c = 0; c < 6; c++) {
            const uint i = lane + 32u * uint(c);
            const bool hit = i < uint(NUM_FISH) && overlaps(state.read(uint2(i, ROW_FBOX)), gmin, gmax);
            uint mask = ballot(hit);
            while (mask != 0u) {
                const uint l = ctz(mask);
                mask &= mask - 1u;
                const uint fi = l + 32u * uint(c);
                const float4 S = state.read(uint2(fi, 2));
                const float4 Bd = state.read(uint2(fi, 3));
                const float4 fc = shade_fish(q, S, Bd, wcol);
                if (fc.a <= 0.0f) continue;
                if (Bd.y < z1) { c2 = c1; z2 = z1; c1 = fc; z1 = Bd.y; }
                else if (Bd.y < z2) { c2 = fc; z2 = Bd.y; }
            }
        }
        col = mix(col, c2.rgb, c2.a);
        col = mix(col, c1.rgb, c1.a);
    }

    out.write(float4(saturate(col), 1.0f), gid);
}

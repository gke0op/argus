// ============================================================================
// CORAL REEF // themes/Coral_Reef.metal
// Author: Claude Opus (Anthropic), 2026-10-15.
//
// A slow drift down a sandy channel through a shallow reef. Brain corals,
// barrel sponges and rock covered in coralline algae are a solid, lit
// heightfield. Staghorn corals branch out of it, sea fans and anemones sway,
// and twelve species live on it: schools of yellow tangs, clownfish, silver
// fish and moorish idols; blacktip reef sharks and manta rays cruising; moray
// eels, lionfish, parrotfish and seahorses close to the reef; sea turtles and
// moon jellyfish in open water. Light comes down in moving shafts, caustics
// ripple over the reef, and it fades into blue with distance.
//
// Lineage: ported by Claude Opus from themes/Coral_Reef.zig (same reef,
// palette, lighting, camera path and creature designs; nine species there were
// designed by Claude Haiku agents, the schooling and god rays come from
// Gemini_Aquarium, the rock ridges are Gemini's canyon harmonics).
//
// How it is drawn: one state texture (RGBA16F) holds it all. argus_init bakes
// the static part once (~0.1 s): the 128 x 128 unit reef tile at 16 texels per
// unit (2049^2 with a wrap row/column; lit colour in rgb, height in alpha, lit
// the way the Zig bake lights it), max-height grids of 4-unit blocks and 1-unit
// cells, and every staghorn and sea-fan branch segment with chunk boxes.
// argus_draw raymarches the heightfield per pixel instead of the Zig's
// voxel-space column fill: rays rising from the camera clear the reef at once,
// blocks and cells the ray passes over are skipped whole, then a short march
// and bisection find the hit; steep hits take the colour of the top they belong
// to, tinted toward the water, like the Zig's voxel walls. Corals, fish and
// bubbles are depth-tested against it per pixel. argus_step leaves the baked
// part alone (it is copied into both ping-pong textures on the first frames)
// and each frame rewrites a few small rows in parallel: the fish's screen
// geometry, every item's screen box, every coral segment projected to the
// screen, and a 64 x 40 grid of screen tiles listing the items touching each
// tile, so a pixel only shades a handful of candidates. Fish swim on smooth
// closed-form paths instead of stateful boids: each school circles the same
// wandering point the Zig boids chase, in loose formation; loners wander alone.
// The reef layout is fixed (as in the Zig), but its features sit on jittered
// grids, so it is the same kind of reef rather than the identical one.
//
// @argus state 2049x2127
// ============================================================================

#define SW 2049u
#define R_BLK 2049u      // 32 x 32 max heights of 4-unit blocks
#define R_CINFO 2050u
#define R_SEG 2051u
#define R_CHUNK 2074u    // static local box of every 4-segment chunk (6 rows)
#define R_FBLK 2080u     // 128 x 128 max heights of 1-unit cells (8 rows)
#define R_FISH 2088u
#define R_BOX 2089u      // per-item screen boxes for the next frame
#define R_BIN 2090u      // 64 x 40 tiles x 12 texels of item ids (15 rows)
#define R_SCHUNK 2105u   // this frame's screen box of every segment chunk (5 rows)
#define R_SSEG 2110u     // this frame's screen endpoints of every segment (17 rows)
#define NCH 23           // chunks per coral (4 segments each)
#define TILES_X 64u
#define TILES_Y 40u
#define BIN_TEX 12u
#define N_FISH 98
#define N_STAG 170
#define N_FAN 90
#define N_CORAL 370
#define N_SEGC 260
#define SEG_SLOTS 90
#define N_BUB 48
#define ID_CORAL 128
#define ID_BUB 512
// The four parts of a tile's list: fish, two halves of the corals, bubbles.
constant int  BIN_LO[4] = { 0, ID_CORAL, ID_CORAL + 185, ID_BUB };
constant int  BIN_HI[4] = { N_FISH, ID_CORAL + 185, ID_CORAL + N_CORAL, ID_BUB + N_BUB };
constant uint BIN_PART_TEX[4] = { 4u, 3u, 3u, 2u };

constant float PI_F = 3.14159265f;
constant float TAU = 6.2831853f;
constant float KW = 6.2831853f / 128.0f;      // base spatial frequency of the tile
constant float HORIZON = 0.40f;
constant float FOCAL = 0.80f;
constant float CAM_SPEED = 0.5f;
constant float CAM_Y = 6.2f;
constant float Z_NEAR = 0.8f;
constant float Z_FAR = 72.0f;
constant float FOG_K = 0.028f;
constant float SURFACE_Y = 14.0f;
constant float REEF_TOP = 5.7f;     // above every point of the baked reef (measured 5.44)

constant float3 WATER_HOR = float3(10.0f, 56.0f, 86.0f);

constant float3 BRAIN_COLS[5] = { float3(128, 170, 96), float3(200, 170, 112), float3(220, 130, 164), float3(156, 104, 186), float3(96, 168, 176) };
constant float3 SPONGE_COLS[4] = { float3(146, 72, 176), float3(232, 124, 52), float3(226, 196, 66), float3(196, 64, 92) };
constant float3 STAG_BASE[4] = { float3(214, 150, 96), float3(92, 140, 212), float3(212, 120, 172), float3(168, 190, 84) };
constant float3 STAG_TIP[4] = { float3(250, 224, 186), float3(186, 226, 255), float3(252, 204, 232), float3(232, 244, 156) };
constant float3 FAN_BASE[3] = { float3(150, 56, 172), float3(206, 58, 80), float3(228, 140, 58) };
constant float3 FAN_TIP[3] = { float3(206, 132, 230), float3(248, 132, 140), float3(252, 200, 120) };
constant float3 ANEM_BASE[3] = { float3(170, 224, 120), float3(236, 200, 140), float3(120, 200, 210) };
constant float3 ANEM_TIP[3] = { float3(240, 120, 200), float3(255, 236, 200), float3(200, 120, 240) };

// Species: yellow tang, clownfish, silver fish, blacktip shark, moray, lionfish,
// manta, parrotfish, seahorse, moon jelly, sea turtle, moorish idol.
constant int   SP_START[13] = { 0, 16, 40, 56, 59, 63, 68, 70, 76, 82, 88, 90, 98 };
constant float SP_LEN[12]   = { 0.70f, 0.50f, 1.10f, 2.2f, 1.8f, 0.6f, 1.8f, 0.8f, 0.4f, 0.7f, 1.3f, 0.5f };
constant float SP_HD[12]    = { 0.30f, 0.21f, 0.15f, 0.10f, 0.055f, 0.19f, 0.15f, 0.24f, 0.22f, 0.3f, 0.28f, 0.2f };
constant float SP_EXT[12]   = { 1.3f, 1.3f, 1.3f, 2.6f, 4.0f, 2.4f, 3.0f, 1.4f, 1.6f, 1.6f, 2.4f, 2.8f };
constant float SP_SPEED[12] = { 0.85f, 0.95f, 0.70f, 1.4f, 0.5f, 0.35f, 0.8f, 0.8f, 0.15f, 0.2f, 0.6f, 0.7f };
constant bool  SP_SCHOOL[12] = { true, true, true, false, false, false, false, false, false, false, false, true };
constant int   SP_HAB[12]   = { 1, 0, 1, 1, 0, 0, 2, 0, 0, 2, 1, 1 };
constant bool  SP_UPRIGHT[12] = { false, false, false, false, false, false, false, false, true, true, false, false };

// ------------------------------------------------------------------ helpers --

static inline float fm(float x, float y) { return x - y * floor(x / y); }   // floored mod
static inline float wrapD(float d) { return d - 128.0f * rint(d / 128.0f); }
static inline float3 mix3(float3 a, float3 b, float t) { return a + (b - a) * t; }
static inline float ss(float e0, float e1, float x) { float t = saturate((x - e0) / (e1 - e0)); return t * t * (3.0f - 2.0f * t); }

static inline uint hseed(uint a, uint b, uint c) { return argus_hash(a * 0x8DA6B343u ^ argus_hash(b * 0xD8163841u ^ argus_hash(c + 0x51ED27u))); }
static inline float rnd(thread uint& s) { s = argus_hash(s + 0x9E3779B9u); return float(s >> 8) * (1.0f / 16777216.0f); }
static inline float hash1(uint i) { return float(argus_hash(i * 747796405u + 2891336453u) >> 8) * (1.0f / 16777216.0f); }

// A float in an RGBA16F texture keeps 11 bits; split it into two halves for ~22.
static inline float2 split(float v) { float hi = float(half(v)); return float2(hi, v - hi); }
static inline float joinf(float2 p) { return p.x + p.y; }

// Linear tables use 2048 of the 2049 columns: a power-of-two stride turns the index
// split into a mask and a shift (dividing by 2049 is emulated: ~30x slower per read).
static inline uint2 linTex(uint n, uint row0) { return uint2(n & 2047u, row0 + (n >> 11)); }

// Centre of the sandy channel the camera follows, as a function of z.
static inline float channelX(float z) { return 64.0f + 14.0f * sin(KW * z) + 6.0f * sin(2.0f * KW * z + 1.0f); }
static inline float reefMask(float wx, float wz) { return ss(1.2f, 5.0f, fabs(wrapD(wx - channelX(wz)))); }

struct Cam { float scroll, cx, cy, focal, horizon, w, h; };
static Cam camera(constant ArgusFrame& f, float t) {
    Cam c;
    c.scroll = fm(CAM_SPEED * t, 128.0f);
    c.cx = channelX(c.scroll + 5.0f);
    c.cy = CAM_Y + 0.3f * sin(fm(0.19f * t, TAU));
    c.w = float(f.width);
    c.h = float(f.height);
    c.focal = FOCAL * c.h;
    c.horizon = HORIZON * c.h;
    return c;
}

// ------------------------------------------------------------ reef baking --

static float hash01(uint x, uint y, uint seed) {
    uint h = x * 0x8DA6B343u + y * 0xD8163841u + seed * 0xCB1AB31Fu;
    h ^= h >> 13; h *= 0x5BD1E995u; h ^= h >> 15;
    return float(h & 0xFFFFu) / 65535.0f;
}

// Periodic value noise on a cells x cells lattice over the tile.
static float vnoise(float wx, float wz, uint cells, uint seed) {
    const float s = float(cells) / 128.0f;
    const float u = fm(wx, 128.0f) * s, v = fm(wz, 128.0f) * s;
    const float fu = floor(u), fv = floor(v);
    const uint iu = uint(max(0.0f, fu)) % cells, iv = uint(max(0.0f, fv)) % cells;
    const uint ju = (iu + 1u) % cells, jv = (iv + 1u) % cells;
    const float tu = u - fu, tv = v - fv;
    const float su = tu * tu * (3.0f - 2.0f * tu), sv = tv * tv * (3.0f - 2.0f * tv);
    const float a = hash01(iu, iv, seed), b = hash01(ju, iv, seed), c = hash01(iu, jv, seed), d = hash01(ju, jv, seed);
    const float ab = a + (b - a) * su, cd = c + (d - c) * su;
    return ab + (cd - ab) * sv;
}

static float reefRaw(float wx, float wz) {
    const float h1 = sin(3.0f * KW * wx + 2.0f * KW * wz) * cos(2.0f * KW * wx - 3.0f * KW * wz);
    const float h2 = 0.52f * sin(6.0f * KW * wx - 5.0f * KW * wz + 1.4f * h1);
    const float h3 = 0.25f * cos(13.0f * KW * wx + 10.0f * KW * wz);
    return max(0.0f, 0.7f + h1 + h2 + h3) * 1.3f + 0.9f * vnoise(wx, wz, 64u, 1u) + 0.25f * vnoise(wx, wz, 256u, 2u);
}

static inline float rippleOf(float wx, float wz) { return sin(122.0f * KW * wx + 40.0f * KW * wz + 2.0f * sin(9.0f * KW * wz)); }

// Base seabed height (before brain corals, sponges and rubble).
static float baseH(float wx, float wz) {
    const float env = reefMask(wx, wz);
    return env * reefRaw(wx, wz) + 0.035f * rippleOf(wx, wz) * (1.0f - env);
}

static void baseHC(float wx, float wz, thread float& h, thread float3& c) {
    const float env = reefMask(wx, wz);
    const float reef = reefRaw(wx, wz);
    const float rip = rippleOf(wx, wz);
    h = env * reef + 0.035f * rip * (1.0f - env);
    const float n3 = 0.6f * vnoise(wx, wz, 192u, 3u) + 0.4f * vnoise(wx, wz, 512u, 6u);
    const float n4 = vnoise(wx, wz, 256u, 4u);
    float3 rc = mix3(float3(166, 136, 124), float3(206, 116, 136), 0.75f * ss(0.4f, 0.7f, n3));
    rc = mix3(rc, float3(120, 150, 84), 0.6f * ss(0.68f, 0.9f, n4));
    rc *= 0.86f + 0.26f * vnoise(wx, wz, 512u, 5u);
    const float3 sc = mix3(float3(236, 208, 150), float3(214, 184, 128), 0.5f + 0.5f * rip);
    c = mix3(sc, rc, ss(0.15f, 0.6f, env * min(1.0f, reef)));
}

// Features stamped onto the reef sit on jittered grids, one candidate per cell,
// so any texel only checks the 3 x 3 cells around it. Heights only ever rise.
constant float BRAIN_CELL = 128.0f / 35.0f;   // ~1100 brain corals on the reef
constant float SPONGE_CELL = 8.0f;            // ~230 barrel-sponge clusters
constant float RUBBLE_CELL = 128.0f / 71.0f;  // ~240 rubble pieces in the channel

static void stamps(float wx, float wz, thread float& h, thread float3& c) {
    // Brain corals: grooved domes.
    {
        const int ci = int(floor(wx / BRAIN_CELL)), cj = int(floor(wz / BRAIN_CELL));
        for (int dj = -1; dj <= 1; dj++) for (int di = -1; di <= 1; di++) {
            const int gi = ci + di, gj = cj + dj;
            uint s = hseed(uint((gi % 35 + 35) % 35), uint((gj % 35 + 35) % 35), 11u);
            const float cx = (float(gi) + rnd(s)) * BRAIN_CELL, cz = (float(gj) + rnd(s)) * BRAIN_CELL;
            const float r = 0.3f + 0.7f * rnd(s);
            const float lx = wx - cx, lz = wz - cz;
            const float d2 = (lx * lx + lz * lz) / (r * r);
            if (d2 >= 1.0f || reefMask(cx, cz) < 0.6f) continue;
            const float3 col = BRAIN_COLS[min(int(rnd(s) * 4.99f), 4)];
            const float hc = r * (0.45f + 0.25f * rnd(s));
            const float q = 6.5f + 2.0f * rnd(s);
            const float ph = rnd(s) * TAU;
            const float g = sin(q * (lx + 0.45f * sin(2.1f * lz + ph)) + 1.6f * sin(q * 0.55f * lz));
            const float groove = ss(0.55f, 0.85f, g);
            const float hh = baseH(cx, cz) + hc * sqrt(1.0f - d2) - 0.05f * groove;
            if (hh > h) { h = hh; c = col * (1.0f - 0.45f * groove); }
        }
    }
    // Barrel sponges: one to three tall tubes with a dark open top.
    {
        const int ci = int(floor(wx / SPONGE_CELL)), cj = int(floor(wz / SPONGE_CELL));
        for (int dj = -1; dj <= 1; dj++) for (int di = -1; di <= 1; di++) {
            const int gi = ci + di, gj = cj + dj;
            uint s = hseed(uint((gi % 16 + 16) % 16), uint((gj % 16 + 16) % 16), 22u);
            const float cx = (float(gi) + rnd(s)) * SPONGE_CELL, cz = (float(gj) + rnd(s)) * SPONGE_CELL;
            if (fabs(wx - cx) > 1.2f || fabs(wz - cz) > 1.2f || reefMask(cx, cz) < 0.6f) continue;
            const float3 col = SPONGE_COLS[min(int(rnd(s) * 3.99f), 3)];
            const int n = 1 + min(int(rnd(s) * 3.0f), 2);
            for (int k = 0; k < 3; k++) {
                const float tx = cx + (rnd(s) - 0.5f) * 1.2f, tz = cz + (rnd(s) - 0.5f) * 1.2f;
                const float r = 0.28f + 0.22f * rnd(s);
                const float tall = 0.7f + 1.4f * rnd(s);
                if (k >= n) continue;
                const float lx = wx - tx, lz = wz - tz;
                const float d2 = (lx * lx + lz * lz) / (r * r);
                if (d2 >= 1.0f) continue;
                const float base = baseH(tx, tz);
                float hh; float3 cc;
                if (d2 < 0.36f) { hh = base + tall * 0.55f; cc = col * 0.3f; }
                else { hh = base + tall; cc = col * (1.0f + 0.15f * ss(0.36f, 0.6f, d2)); }
                if (hh > h) { h = hh; c = cc; }
            }
        }
    }
    // Rubble and coral fragments on the sand.
    {
        const int ci = int(floor(wx / RUBBLE_CELL)), cj = int(floor(wz / RUBBLE_CELL));
        for (int dj = -1; dj <= 1; dj++) for (int di = -1; di <= 1; di++) {
            const int gi = ci + di, gj = cj + dj;
            uint s = hseed(uint((gi % 71 + 71) % 71), uint((gj % 71 + 71) % 71), 33u);
            const float cx = (float(gi) + rnd(s)) * RUBBLE_CELL, cz = (float(gj) + rnd(s)) * RUBBLE_CELL;
            const float r = 0.12f + 0.25f * rnd(s);
            const float lx = wx - cx, lz = wz - cz;
            const float d2 = (lx * lx + lz * lz) / (r * r);
            if (d2 >= 1.0f || reefMask(cx, cz) > 0.5f) continue;
            const float shade = 0.75f + 0.3f * rnd(s);
            const float3 col = BRAIN_COLS[min(int(rnd(s) * 4.99f), 4)] * shade;
            const float tall = r * (0.25f + 0.25f * rnd(s));
            const float hh = baseH(cx, cz) + tall * sqrt(1.0f - d2);
            if (hh > h) { h = hh; c = col; }
        }
    }
}

static float finalH(float wx, float wz) {
    float h = baseH(wx, wz);
    float3 c = float3(0.0f);
    stamps(wx, wz, h, c);
    return h;
}

// Upper bound of the reef over the box [x0, x1] x [z0, z1] (world units): the base
// sampled every 0.25 units plus a margin, and the peak of every stamp that reaches in.
static inline bool discHits(float cx, float cz, float r, float x0, float z0, float x1, float z1) {
    const float dx = cx - clamp(cx, x0, x1), dz = cz - clamp(cz, z0, z1);
    return dx * dx + dz * dz < r * r;
}
static float boxMax(float x0, float z0, float x1, float z1) {
    float m = -1.0e9f;
    const int nx = int(ceil((x1 - x0) / 0.25f)), nz = int(ceil((z1 - z0) / 0.25f));
    for (int j = 0; j <= nz; j++) for (int i = 0; i <= nx; i++) m = max(m, baseH(min(x0 + float(i) * 0.25f, x1), min(z0 + float(j) * 0.25f, z1)));
    m += 0.25f;
    for (int gj = int(floor((z0 - 1.0f) / BRAIN_CELL)); gj <= int(floor((z1 + 1.0f) / BRAIN_CELL)); gj++)
        for (int gi = int(floor((x0 - 1.0f) / BRAIN_CELL)); gi <= int(floor((x1 + 1.0f) / BRAIN_CELL)); gi++) {
            uint s = hseed(uint((gi % 35 + 35) % 35), uint((gj % 35 + 35) % 35), 11u);
            const float cx = (float(gi) + rnd(s)) * BRAIN_CELL, cz = (float(gj) + rnd(s)) * BRAIN_CELL;
            const float r = 0.3f + 0.7f * rnd(s);
            if (!discHits(cx, cz, r, x0, z0, x1, z1) || reefMask(cx, cz) < 0.6f) continue;
            rnd(s);
            const float hc = r * (0.45f + 0.25f * rnd(s));
            m = max(m, baseH(cx, cz) + hc + 0.02f);
        }
    for (int gj = int(floor((z0 - 1.5f) / SPONGE_CELL)); gj <= int(floor((z1 + 1.5f) / SPONGE_CELL)); gj++)
        for (int gi = int(floor((x0 - 1.5f) / SPONGE_CELL)); gi <= int(floor((x1 + 1.5f) / SPONGE_CELL)); gi++) {
            uint s = hseed(uint((gi % 16 + 16) % 16), uint((gj % 16 + 16) % 16), 22u);
            const float cx = (float(gi) + rnd(s)) * SPONGE_CELL, cz = (float(gj) + rnd(s)) * SPONGE_CELL;
            if (reefMask(cx, cz) < 0.6f) continue;
            rnd(s);
            const int n = 1 + min(int(rnd(s) * 3.0f), 2);
            for (int k = 0; k < 3; k++) {
                const float tx = cx + (rnd(s) - 0.5f) * 1.2f, tz = cz + (rnd(s) - 0.5f) * 1.2f;
                const float r = 0.28f + 0.22f * rnd(s);
                const float tall = 0.7f + 1.4f * rnd(s);
                if (k < n && discHits(tx, tz, r, x0, z0, x1, z1)) m = max(m, baseH(tx, tz) + tall + 0.02f);
            }
        }
    for (int gj = int(floor((z0 - 0.5f) / RUBBLE_CELL)); gj <= int(floor((z1 + 0.5f) / RUBBLE_CELL)); gj++)
        for (int gi = int(floor((x0 - 0.5f) / RUBBLE_CELL)); gi <= int(floor((x1 + 0.5f) / RUBBLE_CELL)); gi++) {
            uint s = hseed(uint((gi % 71 + 71) % 71), uint((gj % 71 + 71) % 71), 33u);
            const float cx = (float(gi) + rnd(s)) * RUBBLE_CELL, cz = (float(gj) + rnd(s)) * RUBBLE_CELL;
            const float r = 0.12f + 0.25f * rnd(s);
            if (!discHits(cx, cz, r, x0, z0, x1, z1) || reefMask(cx, cz) > 0.5f) continue;
            rnd(s); rnd(s);
            const float tall = r * (0.25f + 0.25f * rnd(s));
            m = max(m, baseH(cx, cz) + tall + 0.02f);
        }
    return m;
}

// ----------------------------------------------------------------- corals --
// Coral info, 3 texels each in row R_CINFO: (x hi/lo, z hi/lo), (y, kind*4+style,
// angle, size), (phase, segment count, horizontal radius, height). Staghorns and
// fans (the first 260) keep their branch segments in rows R_SEG.., 2 texels each:
// (a.xyz, thickness), (b.xyz, t along the branch).

struct Br { float3 p; float3 d; float len; float thick; int depth; };
struct B2 { float u, v, du, dv, len; int depth; };

// Segments are culled in chunks of 4: each chunk keeps its local bounding box
// (lo.xyz, max thickness), (hi.xyz) in rows R_CHUNK.., NCH chunks per coral.
struct ChunkAcc { float3 lo, hi; float tk; };
static void writeSeg(texture2d<float, access::write> st, int c, int k, float3 a, float3 b, float thick, float t, thread ChunkAcc& ch) {
    const uint n = uint(c * SEG_SLOTS + k) * 2u;
    st.write(float4(a, thick), linTex(n, R_SEG));
    st.write(float4(b, t), linTex(n + 1u, R_SEG));
    if ((k & 3) == 0) { ch.lo = float3(1e9f); ch.hi = float3(-1e9f); ch.tk = 0.0f; }
    ch.lo = min(ch.lo, min(a, b) - thick);
    ch.hi = max(ch.hi, max(a, b) + thick);
    ch.tk = max(ch.tk, thick);
}
static void flushChunk(texture2d<float, access::write> st, int c, int k, thread ChunkAcc& ch, bool last) {
    if ((k & 3) != 3 && !last) return;
    const uint n = uint(c * NCH + (k >> 2)) * 2u;
    st.write(float4(ch.lo, ch.tk), linTex(n, R_CHUNK));
    st.write(float4(ch.hi, 0.0f), linTex(n + 1u, R_CHUNK));
}

static void buildCoral(texture2d<float, access::write> st, int c) {
    uint s = hseed(uint(c), 77u, 5u);
    const int kind = c < N_STAG ? 1 : (c < N_STAG + N_FAN ? 2 : 3);
    float x = 64.0f, z = 64.0f;
    for (int tr = 0; tr < 96; tr++) {
        x = rnd(s) * 128.0f; z = rnd(s) * 128.0f;
        const float m = reefMask(x, z);
        if (kind == 3 && m > 0.85f) continue;
        if (kind != 3 && m < 0.65f) continue;
        break;
    }
    const float2 xs = split(x), zs = split(z);
    x = xs.x + float(half(xs.y));
    z = zs.x + float(half(zs.y));
    const float y = finalH(x - 1.0f / 32.0f, z - 1.0f / 32.0f) - 0.05f;
    const float angle = rnd(s) * PI_F;
    float size = 1.0f + 0.9f * rnd(s);
    const float phase = rnd(s) * TAU;
    int style = 0;
    int n = 0;
    ChunkAcc ch; ch.lo = float3(0.0f); ch.hi = float3(0.0f); ch.tk = 0.0f;
    float R = 0.0f, H = 0.0f;
    if (kind == 1) {
        style = min(int(rnd(s) * 3.99f), 3);
        Br stack[48];
        int sp = 0;
        const int trunks = 3 + min(int(rnd(s) * 3.0f), 2);
        for (int i = 0; i < trunks; i++) {
            const float a = rnd(s) * TAU, lean = 0.25f + 0.5f * rnd(s);
            stack[sp].p = float3(0.0f); stack[sp].d = normalize(float3(cos(a) * lean, 1.0f, sin(a) * lean));
            stack[sp].len = 0.36f * size; stack[sp].thick = 0.13f * size; stack[sp].depth = 0; sp++;
        }
        while (sp > 0 && n < 56) {
            sp--;
            const Br b = stack[sp];
            const float3 e = b.p + b.d * b.len;
            writeSeg(st, c, n, b.p, e, b.thick, float(b.depth) / 4.0f, ch);
            flushChunk(st, c, n, ch, false);
            n++;
            R = max(R, max(fabs(e.x), fabs(e.z)) + b.thick);
            H = max(H, e.y + b.thick);
            if (b.depth >= 4) continue;
            const int kids = rnd(s) < 0.55f ? 2 : 1;
            for (int k = 0; k < kids && sp < 48; k++) {
                const float a = rnd(s) * TAU, spread = 0.45f + 0.35f * rnd(s);
                const float3 nd = normalize(float3(b.d.x + cos(a) * spread, b.d.y + 0.25f, b.d.z + sin(a) * spread));
                stack[sp].p = e; stack[sp].d = nd; stack[sp].len = b.len * (0.78f + 0.1f * rnd(s));
                stack[sp].thick = b.thick * 0.82f; stack[sp].depth = b.depth + 1; sp++;
            }
        }
    } else if (kind == 2) {
        style = min(int(rnd(s) * 2.99f), 2);
        const float ca = cos(angle), sa = sin(angle);
        B2 stack[64];
        int sp = 1;
        stack[0].u = 0; stack[0].v = 0; stack[0].du = 0; stack[0].dv = 1; stack[0].len = 0.32f * size; stack[0].depth = 0;
        while (sp > 0 && n < SEG_SLOTS) {
            sp--;
            const B2 b = stack[sp];
            const float eu = b.u + b.du * b.len, ev = b.v + b.dv * b.len;
            const float thick = max(0.012f, 0.05f * size * (1.0f - 0.13f * float(b.depth)));
            writeSeg(st, c, n, float3(b.u * ca, b.v, b.u * sa), float3(eu * ca, ev, eu * sa), thick, float(b.depth) / 6.0f, ch);
            flushChunk(st, c, n, ch, false);
            n++;
            R = max(R, fabs(eu) + thick);
            H = max(H, ev + thick);
            if (b.depth >= 6) continue;
            const int kids = (b.depth < 2 || rnd(s) < 0.8f) ? 2 : 1;
            for (int k = 0; k < kids && sp < 64; k++) {
                const float side = k == 0 ? -1.0f : 1.0f;
                const float turn = side * (0.28f + 0.25f * rnd(s)) * (kids == 1 ? 0.3f : 1.0f);
                const float cs = cos(turn), sn = sin(turn);
                float du = b.du * cs - b.dv * sn;
                float dv = max(b.du * sn + b.dv * cs, 0.25f);
                const float l = sqrt(du * du + dv * dv);
                stack[sp].u = eu; stack[sp].v = ev; stack[sp].du = du / l; stack[sp].dv = dv / l;
                stack[sp].len = b.len * (0.8f + 0.1f * rnd(s)); stack[sp].depth = b.depth + 1; sp++;
            }
        }
        R += 0.25f;   // sway
    } else {
        style = min(int(rnd(s) * 2.99f), 2);
        size = 0.5f + 0.4f * rnd(s);
        R = size * 0.8f + 0.25f;
        H = size * 0.6f + 0.05f;
        n = 80;   // 20 tentacles x 4 segments, animated, projected by argus_step
    }
    if (kind != 3 && n > 0 && (n & 3) != 0) flushChunk(st, c, n - 1, ch, true);
    st.write(float4(xs.x, xs.y, zs.x, zs.y), uint2(uint(c) * 3u, R_CINFO));
    st.write(float4(y, float(kind * 4 + style), angle, size), uint2(uint(c) * 3u + 1u, R_CINFO));
    st.write(float4(phase, float(n), R, H), uint2(uint(c) * 3u + 2u, R_CINFO));
}

struct Coral { float x, z, y, angle, size, phase, R, H; int kind, style, nseg; };

template <typename T>
static Coral readCoral(T st, int c) {
    Coral o;
    const float4 a = st.read(uint2(uint(c) * 3u, R_CINFO));
    const float4 b = st.read(uint2(uint(c) * 3u + 1u, R_CINFO));
    const float4 d = st.read(uint2(uint(c) * 3u + 2u, R_CINFO));
    o.x = a.x + a.y; o.z = a.z + a.w; o.y = b.x;
    const int ks = int(b.y + 0.5f);
    o.kind = ks / 4; o.style = ks % 4;
    o.angle = b.z; o.size = b.w; o.phase = d.x; o.nseg = int(d.y + 0.5f); o.R = d.z; o.H = d.w;
    return o;
}

// Camera-relative placement and a conservative screen box. False when out of view.
static bool coralBox(Coral co, Cam c, thread float3& rel, thread float4& box) {
    const float rz = fm(co.z - c.scroll, 128.0f);
    if (rz < Z_NEAR + 0.3f || rz > Z_FAR) return false;
    const float rx = wrapD(co.x - c.cx);
    if (fabs(rx) > rz * 0.5f * c.w / c.focal + 2.5f) return false;
    const float ry = co.y - c.cy;
    rel = float3(rx, ry, rz);
    const float zn = max(rz - co.R, Z_NEAR), zf = rz + co.R;
    const float x0 = rx - co.R, x1 = rx + co.R, y0 = ry - 0.1f, y1 = ry + co.H;
    const float kn = c.focal / zn, kf = c.focal / zf;
    const float sx0 = min(x0 * kn, x0 * kf), sx1 = max(x1 * kn, x1 * kf);
    const float sy0 = min(y0 * kn, y0 * kf), sy1 = max(y1 * kn, y1 * kf);
    const float tkw = co.size * (co.kind == 1 ? 0.13f : (co.kind == 2 ? 0.05f : 0.085f));
    const float pad = 0.5f * tkw * kn + 1.5f;
    box = float4(0.5f * c.w + sx0 - pad, c.horizon - sy1 - pad, 0.5f * c.w + sx1 + pad, c.horizon - sy0 + pad);
    return true;
}

static inline float coralSway(Coral co, float t) { return co.kind == 2 ? 0.10f * sin(fm(0.55f * t, TAU) + co.phase) : 0.0f; }

// Conservative screen box of one chunk of a coral's segments (sway included).
template <typename T>
static float4 chunkScreen(T st, int k2, int ch, Coral co, float3 rel, Cam c, float sway) {
    const uint cn = uint(k2 * NCH + ch) * 2u;
    const float4 lo = st.read(linTex(cn, R_CHUNK)), hi = st.read(linTex(cn + 1u, R_CHUNK));
    // Sway moves a point by sway * y^2 along the fan's normal (nx, nz).
    const float ya = max(lo.y, 0.0f), yb = max(hi.y, 0.0f);
    const float2 sa = sway * ya * ya * float2(-sin(co.angle), cos(co.angle));
    const float2 sb = sway * yb * yb * float2(-sin(co.angle), cos(co.angle));
    const float x0 = rel.x + lo.x + min(sa.x, sb.x), x1 = rel.x + hi.x + max(sa.x, sb.x);
    const float y0 = rel.y + lo.y, y1 = rel.y + hi.y;
    const float zn = max(rel.z + lo.z + min(sa.y, sb.y), Z_NEAR), zf = max(rel.z + hi.z + max(sa.y, sb.y), Z_NEAR);
    const float kn = c.focal / zn, kf = c.focal / zf;
    const float pd = 0.5f * max(lo.w * kn, 1.0f) + 4.0f;
    return float4(0.5f * c.w + min(x0 * kn, x0 * kf) - pd, c.horizon - max(y1 * kn, y1 * kf) - pd,
                  0.5f * c.w + max(x1 * kn, x1 * kf) + pd, c.horizon - min(y0 * kn, y0 * kf) + pd);
}

// One point of an anemone: tentacle tt (0..19), joint kk (0..4), camera-relative.
static float3 anemPoint(Coral co, float3 rel, float t, int tt, int kk) {
    const float a = TAU * (float(tt) + 0.5f) / 20.0f;
    const float ph = fm(0.8f * t, TAU) + co.phase;
    const float surge = 0.12f * sin(fm(0.35f * t, TAU) + co.phase);
    const float kf = float(kk) * 0.25f;
    const float o = co.size * (0.25f + 0.55f * kf);
    const float up = co.size * (0.15f + 0.75f * kf - 0.35f * kf * kf);
    const float wav = kf * (0.10f * sin(ph + a * 2.0f - kf * 3.0f) + surge);
    return float3(rel.x + cos(a) * o + wav, rel.y + up, rel.z + sin(a) * o);
}
static inline float2 projectP(float3 p, Cam c) { return float2(0.5f * c.w + p.x * c.focal / p.z, c.horizon - p.y * c.focal / p.z); }

// Screen box of anemone chunk ch (tentacle ch).
static float4 anemChunk(Coral co, float3 rel, Cam c, float t, int ch) {
    float4 b = float4(1.0e4f, 1.0e4f, -1.0e4f, -1.0e4f);
    for (int tt = ch; tt < ch + 1; tt++)
        for (int kk = 0; kk < 5; kk++) {
            const float3 p = anemPoint(co, rel, t, tt, kk);
            if (p.z < Z_NEAR) continue;
            const float2 q = projectP(p, c);
            b = float4(min(b.xy, q), max(b.zw, q));
        }
    const float pd = 0.5f * max(0.085f * co.size * c.focal / rel.z, 1.0f) + 4.0f;
    return b + float4(-pd, -pd, pd, pd);
}

// ------------------------------------------------------------------- fish --

static int speciesOf(int i) {
    int s = 0;
    for (int k = 1; k < 12; k++) if (i >= SP_START[k]) s = k;
    return s;
}

static float habitatY(int h) { return h == 0 ? 2.6f : (h == 1 ? 5.8f : 9.0f); }

// Camera-relative position on the closed-form path. Each species school (or each
// loner) chases the same slowly wandering point the Zig boids chase, circling it
// at cruise speed; school members hold loose formation offsets that drift.
static float3 fishPath(int i, int si, float seed, float t) {
    const bool school = SP_SCHOOL[si];
    const float kf = float(si);
    const float key = school ? kf * 1.7f : kf * 1.7f + seed * 37.0f;
    const float slow = school ? 1.0f : 0.55f + 0.6f * seed;
    const float lane = fract(key * 0.618f);
    const float tz = 8.0f + 26.0f * lane + 4.0f * sin(0.053f * slow * t + key * 1.3f);
    const float tx = 0.55f * tz * sin(0.071f * slow * t + key * 1.9f) + 3.0f * sin(0.19f * slow * t + key * 0.7f);
    const float ty = habitatY(SP_HAB[si]) + 1.4f * sin(0.11f * slow * t + key * 2.3f);
    const float gs = school ? fract(key * 0.377f + 0.13f) : fract(seed * 7.31f + 0.4f);
    const float R = school ? 2.2f + 1.6f * SP_LEN[si] : 1.6f + 2.4f * gs;
    const float w = 1.25f * SP_SPEED[si] / R * (gs > 0.5f ? 1.0f : -1.0f);
    const float ph = w * t + gs * TAU;
    float3 p = float3(tx + R * cos(ph), ty + 0.35f * sin(0.5f * ph + gs * 3.0f), tz + 0.3f * R * sin(ph));
    if (school) {
        const uint hi = uint(i) * 3u + 101u;
        const float spread = 1.6f + 2.6f * SP_LEN[si];
        float3 o = float3(hash1(hi), hash1(hi + 1u), hash1(hi + 2u)) * 2.0f - 1.0f;
        o *= pow(max(hash1(hi + 7u), 1e-3f), 0.33f) / max(length(o), 0.05f);
        o += 0.35f * float3(sin(0.31f * t + seed * 40.0f), sin(0.23f * t + seed * 23.0f), sin(0.19f * t + seed * 17.0f));
        p += o * spread * float3(1.0f, 0.42f, 0.8f);
    }
    return float3(clamp(p.x, -40.0f, 40.0f), p.y, clamp(p.z, 3.0f, 45.0f));
}

struct FG { float hx, hy, tx, ty, W, z, wag; bool ok; };

static float hRead(texture2d<float, access::read> st, float wx, float wz) {
    const float u = min(fract(wx / 128.0f) * 2048.0f, 2047.99f), v = min(fract(wz / 128.0f) * 2048.0f, 2047.99f);
    const float fu = floor(u), fv = floor(v);
    const uint iu = uint(fu), iv = uint(fv);
    const float tu = u - fu, tv = v - fv;
    const float a = mix(st.read(uint2(iu, iv)).a, st.read(uint2(iu + 1u, iv)).a, tu);
    const float b = mix(st.read(uint2(iu, iv + 1u)).a, st.read(uint2(iu + 1u, iv + 1u)).a, tu);
    return mix(a, b, tv);
}

static FG fishGeom(int i, Cam c, float t, texture2d<float, access::read> st) {
    FG g; g.ok = false; g.hx = g.hy = g.tx = g.ty = g.W = g.z = g.wag = 0.0f;
    const int si = speciesOf(i);
    const float seed = hash1(uint(i) + 9000u);
    const float size = SP_LEN[si] * (0.85f + 0.3f * hash1(uint(i) + 19000u));
    float3 p = fishPath(i, si, seed, t);
    // Heading: path velocity relative to the drifting camera (fish keep pace with it).
    const float3 v = (fishPath(i, si, seed, t + 0.05f) - fishPath(i, si, seed, t - 0.05f)) * 10.0f;
    const float wx = p.x + c.cx, wz = c.scroll + p.z;
    float gr = hRead(st, wx, wz);
    gr = max(gr, max(hRead(st, wx + 0.45f, wz), hRead(st, wx - 0.45f, wz)));
    gr = max(gr, max(hRead(st, wx, wz + 0.45f), hRead(st, wx, wz - 0.45f)));
    float y = max(p.y, gr + 0.25f + size * SP_HD[si]);
    if (SP_HAB[si] == 0) y = max(y, gr + 0.6f + 0.8f * seed);
    y = clamp(y, -2.0f, SURFACE_Y);

    const float hs = sqrt(v.x * v.x + v.z * v.z);
    const float pv = clamp(0.3f * v.y, -0.4f * hs, 0.4f * hs);
    const float sp = sqrt(v.x * v.x + pv * pv + v.z * v.z);
    const float3 d = sp > 1e-4f ? float3(v.x, pv, v.z) / sp : float3(1.0f, 0.0f, 0.0f);
    const float hl = 0.5f * size, ry = y - c.cy;
    const float3 hp = float3(p.x, ry, p.z) + d * hl, tp = float3(p.x, ry, p.z) - d * hl;
    if (hp.z < Z_NEAR || tp.z < Z_NEAR) return g;
    float hx = 0.5f * c.w + hp.x * c.focal / hp.z, hy = c.horizon - hp.y * c.focal / hp.z;
    float tx = 0.5f * c.w + tp.x * c.focal / tp.z, ty = c.horizon - tp.y * c.focal / tp.z;
    const float W = c.focal * size * SP_HD[si] / p.z;
    if (W < 0.4f) return g;
    float ax = tx - hx, ay = ty - hy;
    float L = sqrt(ax * ax + ay * ay);
    if (SP_UPRIGHT[si]) {
        const float mx = 0.5f * (hx + tx), my = 0.5f * (hy + ty);
        L = W / SP_HD[si];
        hx = mx; tx = mx; hy = my - 0.5f * L; ty = my + 0.5f * L;
    } else {
        if (L < 1e-3f) { ax = 1.0f; ay = 0.0f; L = 1.0f; }
        ax /= L; ay /= L;
        const float ml = 2.2f * W;
        if (L < ml) {
            const float mx = 0.5f * (hx + tx), my = 0.5f * (hy + ty);
            L = ml;
            hx = mx - ax * 0.5f * L; hy = my - ay * 0.5f * L; tx = mx + ax * 0.5f * L; ty = my + ay * 0.5f * L;
        }
    }
    const float pad = SP_EXT[si] * W + 2.0f;
    const float bw = fabs(hx - tx) + 2.0f * pad, bh = fabs(hy - ty) + 2.0f * pad;
    if (bw * bh > 1100.0f * 1100.0f) return g;
    g.hx = hx; g.hy = hy; g.tx = tx; g.ty = ty; g.W = W; g.z = p.z;
    const float rate = 5.0f + 3.0f * 1.25f * SP_SPEED[si] / size;
    g.wag = fm(seed * TAU + rate * t, TAU);
    g.ok = true;
    return g;
}

static float4 fishBox(FG g, int si) {
    const float pad = SP_EXT[si] * g.W + 2.0f;
    return float4(min(g.hx, g.tx) - pad, min(g.hy, g.ty) - pad, max(g.hx, g.tx) + pad, max(g.hy, g.ty) + pad);
}

// --------------------------------------------------------------- bubbles --

struct Bub { float x, y, z, r, ph; };
static Bub bubbleAt(int b, float t) {
    Bub o;
    const uint bi = uint(b) * 5u + 50000u;
    const float y0 = 0.5f + 2.5f * hash1(bi), vy = 1.2f + 1.2f * hash1(bi + 1u);
    const float T = (SURFACE_Y - y0) / vy;
    const float cyc = t / T + hash1(bi + 2u);
    const float n = floor(cyc), tau = (cyc - n) * T;
    const uint ci = argus_hash(uint(b) * 7919u + uint(int(n) + 100000));
    const float h0 = hash1(ci), h1 = hash1(ci + 1u), h2 = hash1(ci + 2u), h3 = hash1(ci + 3u);
    o.ph = h3 * TAU + 3.1f * tau;
    o.x = (h0 - 0.5f) * 30.0f + 0.12f * sin(o.ph);
    o.y = y0 + vy * tau;
    o.z = 2.5f + 0.5f * T + h1 * 26.0f - 0.5f * tau;
    o.r = 0.04f + 0.08f * h2;
    return o;
}

// ---------------------------------------------------------------- species --
// u: along the body, 0 at the nose (top when upright) to 1 at the tail tip.
// s: across the body in units of W; s < 0 is the back, s > 0 the belly.
// Colours are 0..255, as in the Zig original.

static bool inTri(float px, float py, float ax, float ay, float bx, float by, float cx, float cy) {
    const float d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
    const float d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
    const float d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
    const bool neg = d1 < 0.0f || d2 < 0.0f || d3 < 0.0f;
    const bool pos = d1 > 0.0f || d2 > 0.0f || d3 > 0.0f;
    return !(neg && pos);
}

struct CHit { float k; bool tail; float edge; float sb; };
static bool classicBody(float u, float s, float t, thread CHit& o) {
    const float sb = s - 0.5f * sin(t) * u * u;
    const float a = fabs(sb);
    float hw = 0.0f;
    if (u >= 0.0f && u <= 1.0f) {
        const float uq = floor(u * 63.0f) / 63.0f;
        const float p = max(min(uq / 0.78f, 1.0f), 1e-5f);
        hw = uq <= 0.78f ? 0.18f + 0.82f * sin(PI_F * pow(p, 0.62f)) : 0.18f;
    }
    bool tail = false;
    if (u > 0.74f && u <= 1.0f) {
        const float tf = (u - 0.74f) / 0.26f;
        const float notch = tf > 0.7f ? 0.5f * (tf - 0.7f) / 0.3f : 0.0f;
        if (1.05f * tf > hw && a > notch) { hw = 1.05f * tf; tail = true; }
    }
    if (a > hw) return false;
    o.k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    o.tail = tail; o.edge = hw - a; o.sb = sb;
    return true;
}
static float3 classicFinish(float3 c, CHit h, float u) {
    if (h.edge < 0.07f) c *= 0.7f;
    const float eu = (u - 0.12f) / 0.06f, ev = (h.sb + 0.22f) / 0.17f;
    if (eu * eu + ev * ev < 1.0f) c = float3(14, 14, 20);
    return c;
}

static bool shadeTang(float u, float s, float t, thread float3& c) {
    CHit h; if (!classicBody(u, s, t, h)) return false;
    c = mix3(float3(245, 196, 30), float3(255, 232, 96), h.k);
    if (u > 0.70f && u < 0.76f) c = float3(255, 250, 235);
    c = classicFinish(c, h, u); return true;
}
static bool shadeClown(float u, float s, float t, thread float3& c) {
    CHit h; if (!classicBody(u, s, t, h)) return false;
    c = mix3(float3(236, 98, 16), float3(255, 150, 52), h.k);
    if ((u > 0.22f && u < 0.30f) || (u > 0.50f && u < 0.57f)) c = float3(248, 246, 240);
    else if ((u > 0.205f && u < 0.315f) || (u > 0.485f && u < 0.585f) || (h.tail && u > 0.94f)) c = float3(30, 18, 12);
    c = classicFinish(c, h, u); return true;
}
static bool shadeSilver(float u, float s, float t, thread float3& c) {
    CHit h; if (!classicBody(u, s, t, h)) return false;
    c = mix3(float3(70, 96, 122), float3(214, 224, 230), h.k);
    if (!h.tail && fabs(2.0f * h.k - 1.0f) < 0.07f) c = float3(235, 242, 248);
    c = classicFinish(c, h, u); return true;
}

static float3 sharkFin(float sb, bool tip) {
    if (tip) return float3(18, 18, 22);
    if (sb < 0.0f) return float3(78, 86, 92);
    return float3(210, 212, 210);
}
static bool shadeShark(float u, float s, float t, thread float3& c) {
    const float rear = saturate((u - 0.45f) / 0.55f);
    const float sb = s - 0.7f * sin(t) * rear * rear;
    const float a = fabs(sb);
    const float p = max(saturate(u / 0.8f), 1e-5f);
    const float hw = (u >= 0.0f && u <= 0.8f) ? 0.04f + 0.96f * sin(PI_F * pow(p, 0.8f)) : 0.0f;
    if (a <= hw) {
        const float k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
        const float m = saturate((k - 0.3f) / 0.4f);
        c = float3(86 + 160 * m, 92 + 154 * m, 92 + 146 * m);
        if (u > 0.15f && u < 0.27f && a < 0.4f && fm((u - 0.15f) / 0.024f, 1.0f) < 0.2f) c *= 0.72f;
        if (hw - a < 0.09f) c *= 0.55f;
        const float eu = (u - 0.10f) / 0.022f, ev = (sb + 0.20f) / 0.22f;
        if (eu * eu + ev * ev < 1.0f) c = float3(12, 12, 16);
        return true;
    }
    if (inTri(u, sb, 0.29f, -0.2f, 0.44f, -2.2f, 0.57f, -0.2f)) { c = sharkFin(sb, -sb > 1.85f); return true; }
    if (inTri(u, sb, 0.66f, -0.1f, 0.78f, -0.85f, 0.84f, -0.1f)) { c = sharkFin(sb, -sb > 0.7f); return true; }
    if (inTri(u, sb, 0.66f, 0.1f, 0.78f, 0.7f, 0.84f, 0.1f)) { c = sharkFin(sb, sb > 0.6f); return true; }
    if (inTri(u, sb, 0.16f, 0.2f, 0.44f, 1.9f, 0.34f, 0.2f)) { c = sharkFin(sb, sb > 1.5f && u > 0.36f); return true; }
    if (inTri(u, sb, 0.62f, -0.1f, 1.0f, -2.0f, 0.93f, -0.12f)) { c = sharkFin(sb, u > 0.93f && sb < -1.7f); return true; }
    if (inTri(u, sb, 0.62f, 0.1f, 0.97f, 0.85f, 0.93f, 0.12f)) { c = sharkFin(sb, u > 0.9f && sb > 0.6f); return true; }
    return false;
}

static bool shadeMoray(float u, float s, float t, float seed, thread float3& c) {
    const float amp = 0.35f + 0.6f * u;
    const float sb = s - amp * sin(15.7f * u - t);
    const float a = fabs(sb);
    float hw = 0.0f;
    if (u >= 0.0f && u <= 1.0f) {
        if (u < 0.35f) {
            const float nose = saturate(u / 0.12f);
            hw = (0.6f + 0.4f * sin(0.5f * PI_F * saturate(u / 0.35f))) * (0.45f + 0.55f * sqrt(nose));
        } else {
            hw = 1.0f - 0.92f * pow(max((u - 0.35f) / 0.65f, 1e-5f), 1.2f);
        }
    }
    if (hw <= 0.0f) return false;
    float fin = 0.0f;
    if (u >= 0.05f) fin = saturate((u - 0.05f) / 0.1f) * 0.34f * (1.0f - 0.85f * saturate((u - 0.05f) / 0.95f));
    const float reach = sb < 0.0f ? hw + fin : hw;
    if (a > reach) return false;
    const bool in_fin = sb < 0.0f && a > hw;
    const float k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    if (seed >= 0.5f) {
        c = in_fin ? float3(84, 60, 36) : float3(62 + 36 * k, 42 + 28 * k, 26 + 16 * k);
        const float row = floor(sb * 1.54f + 0.5f);
        const float off = fm(row, 2.0f) > 0.5f ? 0.5f : 0.0f;
        const float gu = fm(u * 28.0f + off, 1.0f) - 0.5f, gs = fm(sb * 1.54f + 0.5f, 1.0f) - 0.5f;
        if (gu * gu + gs * gs < 0.1f) c = float3(236, 214, 120);
    } else {
        c = in_fin ? float3(150, 162, 62) : float3(58 + 30 * k, 96 + 34 * k, 40 + 22 * k);
        const float net = sin(u * 70.0f + 2.0f * sin(sb * 4.0f)) * sin(sb * 5.0f - u * 40.0f);
        if (net > 0.55f) c = float3(200, 196, 80);
    }
    if (u < 0.13f && sb > 0.03f && sb < 0.03f + 0.36f * (1.0f - u / 0.13f)) { c = float3(240, 232, 196); return true; }
    const float eu = (u - 0.12f) / 0.018f, ev = (sb + 0.35f) / 0.33f;
    const float ed = eu * eu + ev * ev;
    if (ed < 1.0f) { c = ed < 0.35f ? float3(12, 12, 10) : float3(220, 190, 60); return true; }
    if (reach - a < 0.08f) c *= 0.65f;
    return true;
}

static bool shadeLion(float u, float s, float t, thread float3& c) {
    const float st = sin(t);
    const float sb = s - 0.12f * st * u * u;
    const float a = fabs(sb);
    const float p = saturate(u / 0.78f);
    const float hwb = u <= 0.78f ? 0.3f + 0.7f * sin(PI_F * sqrt(p)) : 0.0f;
    const float tq = (u - 0.86f) / 0.14f;
    const float hwt = 0.85f * sqrt(max(0.0f, 1.0f - tq * tq));
    const float hw = max(hwb, hwt);
    const bool tail = u > 0.7f && hwt > hwb;
    if (a <= hw) {
        if (u < 0.08f && sb > 0.1f + 2.0f * u) return false;
        const float k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
        c = float3(112 + 74 * k, 36 + 48 * k, 28 + 34 * k);
        if (tail) {
            c = float3(196, 64, 46);
            if (sin(u * 24.0f) * sin(sb * 20.0f) > 0.55f) c = float3(70, 22, 20);
            if (fm(sb * 2.5f, 1.0f) < 0.2f) c = float3(232, 214, 196);
        } else if (u > 0.1f && fm((u - 0.1f) * 5.5f, 1.0f) < 0.35f) {
            c = float3(242, 232, 214);
        }
        if (hw - a < 0.07f) c *= 0.7f;
        const float eu = (u - 0.15f) / 0.065f, ev = (sb + 0.2f) / 0.13f;
        const float er = eu * eu + ev * ev;
        if (er < 1.0f) c = er < 0.3f ? float3(14, 10, 12) : float3(240, 186, 70);
        return true;
    }
    if (sb > 0.0f) {
        const float x = u - 0.22f, y = (sb - 0.1f) * 0.19f;
        const float r2 = x * x + y * y;
        if (r2 > 0.2f) return false;
        const float r = sqrt(r2);
        const float ang = atan2(y, x);
        const float hwid = 0.62f + 0.12f * st;
        const float da = ang - 0.85f;
        if (fabs(da) >= hwid) return false;
        const float ray = (da + hwid) / (2.0f * hwid) * 10.0f;
        const float ri = min(floor(ray), 9.0f);
        const float fr = ray - ri;
        if (fr > 0.7f) return false;
        if (r > (0.4f + 0.02f * st) * (0.9f + 0.1f * fr)) return false;
        c = (int(ri) % 2 == 0) ? float3(206, 70, 52) : float3(242, 224, 204);
        return true;
    }
    const float above = -sb - hw;
    if (above > 1.3f) return false;
    if (above < 0.45f) {
        const float tc = min(fabs(u - 0.12f), fabs(u - 0.19f));
        if (u > 0.08f && u < 0.23f && tc < 0.02f * (1.0f - above / 0.45f)) { c = float3(232, 150, 120); return true; }
    }
    if (u > 0.2f && u < 0.72f) {
        const float env = sin(PI_F * (u - 0.2f) / 0.52f);
        const float lm = 1.25f * env;
        if (env > 0.05f && above < lm) {
            const float cell = (u - 0.2f) / 0.04f;
            const float f = cell - floor(cell) - 0.5f;
            const float wsp = 0.008f * (1.0f - above / lm) + 0.0015f;
            if (fabs(f * 0.04f) < wsp) {
                c = fm(above * 2.6f, 1.0f) < 0.5f ? float3(242, 226, 206) : float3(170, 44, 34);
                return true;
            }
        }
    }
    return false;
}

static bool shadeManta(float u, float s, float t, thread float3& c) {
    const float flap = sin(t);
    const float a = fabs(s);
    if (u > 0.5f) {
        if (u > 1.0f) return false;
        const float x = saturate((u - 0.5f) / 0.5f);
        if (a > 0.10f * (1.0f - x) + 0.03f) return false;
        c = float3(24, 24, 30); return true;
    }
    if (u < 0.0f) {
        const float fu = (u - 0.02f) / 0.06f, fa = (a - 1.15f) / 0.35f;
        if (fu * fu + fa * fa > 1.0f) return false;
        c = float3(30, 32, 38); return true;
    }
    const float ramp = saturate((a - 1.5f) / 1.3f);
    const float ua = u - 0.06f * flap * ramp * ramp;
    float h;
    if (ua < 0.32f) { const float x = saturate(ua / 0.32f); h = 0.6f + 2.2f * (2.0f * x - x * x); }
    else { const float y = max(saturate((ua - 0.32f) / 0.18f), 1e-5f); h = 2.8f - 2.7f * pow(y, 0.8f); }
    const float span = saturate(h / 2.8f);
    h *= 1.0f + 0.05f * flap * span * span;
    if (a > h) return false;
    const float rim = h - a;
    const float lift = 8.0f * span * span;
    c = float3(34 + lift, 36 + lift, 42 + lift);
    const float ac = 0.30f + 6.0f * (u - 0.06f);
    if (u > 0.06f && u < 0.26f && fabs(a - ac) < 0.10f) c = float3(200, 204, 208);
    if (rim < 0.10f) c = float3(74, 78, 86);
    if (rim < 0.05f) c = float3(14, 14, 18);
    return true;
}

static bool shadeParrot(float u, float s, float t, thread float3& c) {
    const float sb = s - 0.18f * sin(t) * u * u;
    const float a = fabs(sb);
    const float p = max(saturate(u / 0.8f), 1e-5f);
    const float hw = (u >= 0.0f && u <= 0.8f) ? 0.12f + 0.88f * sin(PI_F * pow(p, 0.7f)) : 0.0f;
    const float fh = (sb < 0.0f && u > 0.08f && u <= 0.8f) ? 0.27f * sqrt(max(0.0f, sin(PI_F * (u - 0.08f) / 0.72f))) : 0.0f;
    const float tf = saturate((u - 0.8f) / 0.2f);
    const float notch = 0.4f * tf * tf, th = 0.12f + 0.95f * tf;
    const bool tail = u > 0.8f && u <= 1.0f && a > notch && a <= th;
    const bool fin = !tail && fh > 0.0f && a > hw && a <= hw + fh;
    const bool body = u >= 0.0f && u <= 0.8f && a <= hw;
    if (!(tail || fin || body)) return false;
    const float k = 0.5f + 0.5f * clamp(sb / 0.9f, -1.0f, 1.0f);
    const float3 teal = float3(40 + 40 * k, 150 + 60 * k, 140 + 30 * k);
    c = teal;
    if (tail) {
        c = float3(62, 192, 166);
        if (a > th - 0.16f || a < notch + 0.07f) c = float3(250, 128, 64);
    } else if (fin) {
        c = float3(84, 212, 190);
        if (a > hw + 0.6f * fh) c = float3(250, 118, 104);
        if (fabs(sin(u * 150.0f)) < 0.15f) c = mix3(c, float3(40, 130, 130), 0.35f);
    } else {
        const float e = min(fabs(sin(140.0f * u + 12.0f * sb)), fabs(sin(40.0f * sb)));
        c = mix3(teal, float3(246, 124, 92), saturate(1.0f - e / 0.2f) * 0.7f);
        if (hw - a < 0.07f) c *= 0.6f;
        if (u > 0.2f && u < 0.44f && sb > -0.05f && sb < 0.5f) {
            const float ang = 0.35f * sin(t);
            const float du = u - 0.32f, ds = sb - 0.24f, cs = cos(ang), sn = sin(ang);
            const float pu = (du * cs + ds * sn) / 0.09f, ps = (-du * sn + ds * cs) / 0.25f;
            const float pr = pu * pu + ps * ps;
            if (pr < 1.0f) { c = mix3(c, float3(176, 242, 222), 0.6f); if (pr > 0.6f) c = float3(250, 130, 110); }
        }
        const float cu = (u - 0.19f) / 0.06f, cv = (sb - 0.3f) / 0.12f;
        if (cu * cu + cv * cv < 1.0f) c = mix3(c, float3(255, 102, 122), 0.85f);
        if (u < 0.08f && sb > -0.15f && sb < 0.4f) { c = float3(240, 238, 224); if (u > 0.035f && u < 0.045f) c = float3(190, 188, 178); }
        const float eu = (u - 0.14f) / 0.055f, ev = (sb + 0.2f) / 0.15f;
        const float d2 = eu * eu + ev * ev;
        if (d2 < 0.36f) c = float3(16, 16, 22); else if (d2 < 1.0f) c = float3(244, 206, 74);
    }
    return true;
}

static float3 horseTrunk(float y) {
    const float bulge = sin(PI_F * saturate((y - 1.5f) / 1.8f));
    const float taper = saturate((y - 2.6f) / 1.0f);
    return float3(0.12f * bulge, 0.15f + 0.62f * bulge - 0.09f * taper, 0.14f + 0.30f * bulge - 0.07f * taper);
}
static bool shadeSeahorse(float u, float s, float t, thread float3& c) {
    const float st = sin(t);
    const float y = u / 0.22f - 0.04f * st;
    const float sb = s - 0.07f * st * (y - 2.3f);
    const float ed = (sb - 0.24f) * (sb - 0.24f) + (y - 0.62f) * (y - 0.62f);
    if (ed < 0.01f) { c = float3(14, 12, 12); return true; }
    if (ed < 0.0225f) { c = float3(252, 248, 230); return true; }
    const float hq = (sb - 0.05f) / 0.5f, hr = (y - 0.68f) / 0.5f;
    const float hq2 = hq * hq + hr * hr;
    const bool c1 = sb * sb + (y - 0.2f) * (y - 0.2f) < 0.0169f;
    const float c2x = sb + 0.18f;
    const bool c2 = c2x * c2x + (y - 0.34f) * (y - 0.34f) < 0.0081f;
    const float vx = 0.95f, vy = 0.18f;
    const float hh = saturate(((sb - 0.35f) * vx + (y - 0.80f) * vy) / (vx * vx + vy * vy));
    const float px = sb - 0.35f - hh * vx, py = y - 0.80f - hh * vy;
    const float snout_r = 0.24f - 0.12f * hh, snout_d = sqrt(px * px + py * py);
    const bool in_snout = snout_d < snout_r;
    const float3 tr = horseTrunk(y);
    const bool in_trunk = y > 1.0f && y < 3.72f && sb <= tr.x + tr.y && sb >= tr.x - tr.z;
    bool curl = false;
    float curl_edge = 9.0f;
    if (y > 3.6f) {
        const float dx = sb - 0.06f, dy = y - 4.12f;
        const float rr = sqrt(dx * dx + dy * dy);
        float phi = atan2(dy, dx) + 0.5f * PI_F;
        if (phi < 0.0f) phi += TAU;
        const float phmax = 10.05f, g = 0.37f / 10.05f;
        for (int i = 0; i < 3; i++) {
            const float ph = phi + TAU * float(i);
            if (ph > phmax) break;
            const float rn = 0.42f - g * ph, wv = 0.11f - 0.07f * ph / phmax;
            const float ratio = fabs(rr - rn) / wv;
            if (ratio < 1.0f) { curl = true; curl_edge = min(curl_edge, (1.0f - ratio) * wv); }
        }
    }
    if (hq2 < 1.0f || c1 || c2 || in_snout || in_trunk || curl) {
        const float wdt = sb >= tr.x ? tr.y : tr.z;
        const float k = 0.5f + 0.5f * clamp((sb - tr.x) / max(wdt, 0.05f), -1.0f, 1.0f);
        c = float3(214 + 38 * k, 98 + 102 * k, 22 + 52 * k);
        if (in_trunk && y > 1.6f && y < 3.5f && fm(y - 1.6f, 0.34f) < 0.045f) c *= float3(0.7f, 0.6f, 0.6f);
        float edge = 9.0f;
        if (hq2 < 1.0f) edge = min(edge, (1.0f - hq2) * 0.5f);
        if (in_snout && hq2 >= 1.0f) edge = min(edge, snout_r - snout_d);
        if (in_trunk && y > 1.3f) edge = min(edge, min(tr.x + tr.y - sb, sb - (tr.x - tr.z)));
        if (curl) edge = min(edge, curl_edge);
        if (edge < 0.06f) c *= float3(0.55f, 0.5f, 0.45f);
        return true;
    }
    const float fy = (y - 2.25f) / 0.34f;
    if (fy * fy < 1.0f) {
        const float flen = 0.36f * (1.0f - fy * fy) * (0.85f + 0.25f * sin(3.0f * t));
        const float back = tr.x - tr.z;
        if (sb < back && sb > back - flen) { c = sin(-sb * 35.0f) > 0.7f ? float3(236, 190, 110) : float3(255, 240, 186); return true; }
    }
    return false;
}

static bool shadeJelly(float u, float s, float t, thread float3& c) {
    const float p = sin(t);
    const float a = fabs(s);
    const float bell_b = 0.34f - 0.03f * p, bw = 1.0f + 0.07f * p;
    if (u >= 0.2f && u <= 0.9f) {
        const float fu = (u - 0.2f) / 0.7f;
        const float aw = (0.03f + 0.035f * (1.0f - fu)) * (0.7f + 0.3f * fabs(sin(u * 32.0f)));
        for (int i = 0; i < 4; i++) {
            const float s0 = -0.30f + 0.2f * float(i);
            const float cs = s0 * (1.0f - 0.3f * u) + 0.14f * u * sin(t - 5.0f * u + 0.6f * float(i));
            const float d = fabs(s - cs);
            if (d < aw) { c = (aw - d < 0.015f) ? float3(244, 232, 248) : float3(214, 180, 226); return true; }
        }
    }
    if (u >= 0.0f && u <= bell_b) {
        const float v = u / bell_b, w = 1.0f - v;
        const float hw = bw * sqrt(max(0.0f, 1.0f - w * w));
        if (a <= hw) {
            const float dx = s * 0.3f, dy = u - 0.17f;
            const float r = sqrt(dx * dx + dy * dy), th = atan2(dy, dx);
            if (fabs(r - (0.10f + 0.035f * cos(4.0f * th))) < 0.011f) { c = float3(226, 140, 220); return true; }
            if (hw - a < 0.12f) { c = float3(226, 242, 248); return true; }
            const float g = (0.98f + 0.02f * cos(18.0f * th)) * (1.0f + 0.06f * (1.0f - v));
            c = float3(170, 206, 218) * g; return true;
        }
    }
    if (u > bell_b && u < bell_b + 0.14f && a < bw - 0.05f) {
        const float idx = floor(s * 13.0f);
        const float tl = 0.09f + 0.04f * fabs(sin(idx * 12.9898f + 0.3f));
        if (u < bell_b + tl) {
            const float sway = 0.04f * u * sin(t - 9.0f * u + idx);
            if (fabs(s - (idx + 0.5f) / 13.0f - sway) < 0.010f) { c = float3(176, 210, 224); return true; }
        }
    }
    return false;
}

static float3 turtleSkin(float x, float y, float3 base) {
    const float gx = x * 46.0f, gy = y * 46.0f;
    const float dx = gx - floor(gx) - 0.5f, dy = gy - floor(gy) - 0.5f;
    return dx * dx + dy * dy < 0.07f ? float3(176, 190, 160) : base;
}
static float flipperInside(float x, float y, float rx, float ry, float ang, float len, float w0, float w1) {
    const float dx = sin(ang), dy = cos(ang);
    const float px = x - rx, py = y - ry;
    const float al = px * dx + py * dy;
    if (al < -0.06f || al > len) return -1.0f;
    const float f = saturate(al / len), omf = 1.0f - f;
    const float hw = w1 + (w0 - w1) * omf * sqrt(1.0f - f * f + 0.02f);
    const float pe = px * dy - py * dx - 0.5f * al * al;
    return hw - fabs(pe);
}
static bool shadeTurtle(float u, float s, float t, thread float3& c) {
    const float x = u, y = s * 0.28f, sw = sin(t);
    const float ex = (x - 0.12f) / 0.022f, ey = (y + 0.035f) / 0.022f;
    const float e2 = ex * ex + ey * ey;
    if (e2 <= 1.0f) { c = e2 < 0.42f ? float3(14, 14, 18) : float3(214, 208, 170); return true; }
    const float fd = flipperInside(x, y, 0.27f, 0.06f, 0.45f + 0.35f * sw, 0.3f + 0.05f * sw, 0.12f, 0.03f);
    if (fd >= 0.0f) { c = fd < 0.012f ? float3(44, 56, 42) : turtleSkin(x, y, float3(118, 138, 110)); return true; }
    const float rd = flipperInside(x, y, 0.74f, 0.07f, 0.6f + 0.1f * sw, 0.17f, 0.05f, 0.02f);
    if (rd >= 0.0f) { c = rd < 0.01f ? float3(44, 56, 42) : turtleSkin(x, y, float3(112, 132, 104)); return true; }
    const float hcy = -0.02f + 0.006f * sw;
    const float hqx = (x - 0.09f) / 0.10f, hqy = (y - hcy) / 0.075f;
    const float hr2 = hqx * hqx + hqy * hqy;
    const float nqx = (x - 0.18f) / 0.075f, nqy = (y + 0.03f) / 0.065f;
    const float nr2 = nqx * nqx + nqy * nqy;
    if (hr2 <= 1.0f || nr2 <= 1.0f) {
        if (x < 0.03f && hr2 <= 1.0f) c = float3(72, 66, 46);
        else if (min(hr2, nr2) > 0.84f) c = float3(44, 56, 44);
        else c = turtleSkin(x, y, float3(110, 130, 102));
        return true;
    }
    const float qx = (x - 0.49f) / 0.33f;
    if (y <= 0.03f) {
        const float qy = (y - 0.03f) / 0.26f;
        const float r2 = qx * qx + qy * qy;
        if (r2 <= 1.0f) {
            if (r2 > 0.86f) { c = float3(36, 38, 20); return true; }
            const float gy = (y + 0.23f) * 12.0f, row = floor(gy);
            const float gx = (x - 0.49f) * 12.0f + (fm(row, 2.0f) == 0.0f ? 0.0f : 0.5f);
            const float cx = floor(gx), fx = gx - cx, fy = gy - row;
            if (min(fx, 1.0f - fx) < 0.08f || min(fy, 1.0f - fy) < 0.08f) { c = float3(54, 48, 26); return true; }
            const float h = saturate((-y - 0.02f) / 0.22f);
            const float alt = fm(cx + row, 2.0f) == 0.0f ? 0.94f : 1.0f;
            c = float3(98 + 30 * h, 102 + 26 * h, 50 + 18 * h) * alt; return true;
        }
    } else {
        const float qb = (y - 0.03f) / 0.09f;
        const float r2 = qx * qx + qb * qb;
        if (r2 <= 1.0f) {
            if (r2 > 0.86f) c = float3(40, 50, 38);
            else if (y < 0.055f) c = float3(224, 210, 152);
            else c = turtleSkin(x, y, float3(104, 124, 96));
            return true;
        }
    }
    if (x >= 0.80f && x <= 1.0f) {
        const float tf = (x - 0.80f) / 0.20f;
        const float hwt = 0.05f * pow(max(1.0f - tf, 1e-5f), 0.9f);
        const float ta = fabs(y);
        if (ta < hwt) { c = hwt - ta < 0.01f ? float3(40, 46, 34) : turtleSkin(x, y, float3(92, 110, 82)); return true; }
    }
    return false;
}

static float idolProfile(float u) {
    const float p = saturate((u - 0.18f) / 0.62f);
    const float front = sqrt(saturate(p / 0.22f));
    return 0.12f + 0.88f * front * (1.0f - p) * (1.0f - 0.3f * p);
}
static float3 idolColour(float u) {
    if (u < 0.40f) return float3(248, 244, 232);
    if (u < 0.49f) return float3(14, 12, 14);
    if (u < 0.72f) return float3(252, 204, 36);
    return float3(14, 12, 14);
}
static bool shadeIdol(float u, float s, float t, thread float3& c) {
    const float sb = s - 0.15f * sin(t) * u * u;
    const float a = fabs(sb);
    if (u > 0.50f && u <= 1.02f) {
        const float q = saturate((u - 0.50f) / 0.50f);
        const float centre = -(1.5f + sin(q * PI_F * 0.5f)) + 0.15f * q * sin(t - 1.2f * q);
        if (fabs(sb - centre) < 0.055f - 0.02f * q) { c = float3(250, 248, 240); return true; }
    }
    if (u >= 0.0f && u < 0.30f) {
        const float tube = 0.04f + 0.12f * saturate(u / 0.30f);
        const float off = sb + 0.10f;
        if (fabs(off) < tube) { c = (u > 0.07f && u < 0.12f && off < -0.3f * tube) ? float3(236, 116, 30) : float3(246, 240, 222); return true; }
    }
    if (u >= 0.18f && u <= 0.80f) {
        const float hw = idolProfile(u) * (sb < 0.0f ? 1.9f : 1.6f);
        if (a <= hw) {
            const float eu = (u - 0.45f) / 0.03f, ev = (sb + 0.45f) / 0.08f;
            const float e2 = eu * eu + ev * ev;
            if (e2 < 1.0f) { c = float3(8, 8, 10); return true; }
            if (e2 < 1.5f) { c = float3(70, 68, 74); return true; }
            c = idolColour(u);
            if (hw - a < 0.07f) c *= 0.6f;
            return true;
        }
    }
    if (sb < 0.0f && u >= 0.26f && u <= 0.78f) {
        const float hw = idolProfile(u) * 1.9f, fh = 0.9f * sin(PI_F * saturate((u - 0.26f) / 0.52f));
        if (a > hw && a <= hw + fh) { c = (a - hw > 0.7f * fh) ? float3(240, 236, 226) : float3(26, 20, 22); return true; }
    }
    if (sb > 0.0f && u >= 0.42f && u <= 0.82f) {
        const float hw = idolProfile(u) * 1.6f, fa = 0.5f * sin(PI_F * saturate((u - 0.42f) / 0.40f));
        if (a > hw && a <= hw + fa) { c = (a - hw > 0.65f * fa) ? float3(240, 236, 226) : float3(26, 20, 22); return true; }
    }
    if (u > 0.78f && u <= 1.0f) {
        const float tf = saturate((u - 0.80f) / 0.20f);
        const float ht = 1.15f * pow(max(tf, 1e-5f), 0.9f);
        const float ua = a / 1.15f;
        const float u_edge = 1.0f - 0.05f * ua * ua;
        if (a <= ht && u <= u_edge) {
            if ((ht > 0.25f && ht - a < 0.08f) || u > u_edge - 0.035f) c = float3(255, 210, 40);
            else if (u < 0.87f || u > 0.93f) c = float3(16, 14, 16);
            else c = float3(244, 242, 236);
            return true;
        }
    }
    return false;
}

static bool shadeSpecies(int si, float u, float s, float t, float seed, thread float3& c) {
    switch (si) {
        case 0: return shadeTang(u, s, t, c);
        case 1: return shadeClown(u, s, t, c);
        case 2: return shadeSilver(u, s, t, c);
        case 3: return shadeShark(u, s, t, c);
        case 4: return shadeMoray(u, s, t, seed, c);
        case 5: return shadeLion(u, s, t, c);
        case 6: return shadeManta(u, s, t, c);
        case 7: return shadeParrot(u, s, t, c);
        case 8: return shadeSeahorse(u, s, t, c);
        case 9: return shadeJelly(u, s, t, c);
        case 10: return shadeTurtle(u, s, t, c);
        default: return shadeIdol(u, s, t, c);
    }
}

// ------------------------------------------------------------------ init --

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    if (gid.y <= 2048u) {
        // Reef texel (column/row 2048 repeat 0 so bilinear taps wrap without masking).
        const float wx = (float(gid.x & 2047u) + 0.5f) / 16.0f, wz = (float(gid.y & 2047u) + 0.5f) / 16.0f;
        float h; float3 c;
        baseHC(wx, wz, h, c);
        stamps(wx, wz, h, c);
        // Light it, as the Zig bake does: Lambert from above, cavities darker,
        // reds absorbed with depth.
        const float e = 1.0f / 16.0f, q = 4.0f / 16.0f;
        const float gx = (finalH(wx + e, wz) - finalH(wx - e, wz)) * 8.0f;
        const float gz = (finalH(wx, wz + e) - finalH(wx, wz - e)) * 8.0f;
        const float lam = max(0.0f, (-gx * 0.30f + 0.88f + gz * 0.36f) / sqrt(gx * gx + gz * gz + 1.0f));
        const float around = 0.25f * (finalH(wx + q, wz) + finalH(wx - q, wz) + finalH(wx, wz + q) + finalH(wx, wz - q));
        const float cav = clamp(1.0f + 0.9f * (h - around), 0.55f, 1.15f);
        const float lit = (0.40f + 0.85f * lam) * cav * (0.92f + 0.05f * h);
        c = min(c * lit * float3(0.86f, 1.0f, 1.04f), float3(255.0f));
        state.write(float4(c / 255.0f, h), gid);
    } else if (gid.y == R_BLK) {
        if (gid.x < 1024u) {
            const float x0 = float(gid.x & 31u) * 4.0f, z0 = float(gid.x >> 5) * 4.0f;
            state.write(float4(boxMax(x0 - 0.2f, z0 - 0.2f, x0 + 4.2f, z0 + 4.2f), 0.0f, 0.0f, 0.0f), gid);
        }
    } else if (gid.y >= R_FBLK && gid.y < R_FBLK + 8u) {
        const uint n = (gid.y - R_FBLK) * 2048u + gid.x;
        if (gid.x < 2048u && n < 16384u) {
            const float x0 = float(n & 127u), z0 = float(n >> 7);
            state.write(float4(boxMax(x0 - 0.2f, z0 - 0.2f, x0 + 1.2f, z0 + 1.2f), 0.0f, 0.0f, 0.0f), gid);
        }
    } else if (gid.y == R_CINFO) {
        if (gid.x < uint(N_CORAL)) buildCoral(state, int(gid.x));
    } else if (gid.y >= R_FISH) {
        state.write(float4(0.0f), gid);
    }
}

// ------------------------------------------------------------------ step --

kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    if (gid.y < R_FISH) {
        // The baked part never changes: copy it into both ping-pong textures once.
        if (f.frame < 3u) next.write(prev.read(gid), gid);
        return;
    }
    const float t = f.time;
    const Cam c = camera(f, t);
    if (gid.y == R_FISH) {
        if (gid.x >= uint(N_FISH) * 4u) { next.write(float4(0.0f), gid); return; }
        const int i = int(gid.x >> 2);
        const FG g = fishGeom(i, c, t, prev);
        float4 o;
        switch (gid.x & 3u) {
            case 0u: o = float4(split(g.hx), split(g.hy)); break;
            case 1u: o = float4(split(g.tx), split(g.ty)); break;
            case 2u: o = float4(split(g.W), split(g.z)); break;
            default: o = float4(g.wag, g.ok ? 1.0f : 0.0f, 0.0f, 0.0f); break;
        }
        next.write(o, gid);
        return;
    }
    if (gid.y == R_BOX) {
        // Each item's screen box over this frame and the next one; the tile bins
        // read them a frame later, so they stay exact without a second pass.
        float4 b = float4(1.0e4f, 1.0e4f, -1.0e4f, -1.0e4f);
        const float t1 = t + max(f.dt, 0.0f);
        const Cam c1 = camera(f, t1);
        const int id = int(gid.x);
        if (id < N_FISH) {
            const int si = speciesOf(id);
            const FG g0 = fishGeom(id, c, t, prev), g1 = fishGeom(id, c1, t1, prev);
            if (g0.ok) b = fishBox(g0, si);
            if (g1.ok) { const float4 b1 = fishBox(g1, si); b = float4(min(b.xy, b1.xy), max(b.zw, b1.zw)); }
        } else if (id >= ID_CORAL && id < ID_CORAL + N_CORAL) {
            const Coral co = readCoral(prev, id - ID_CORAL);
            float3 rel; float4 b0;
            if (coralBox(co, c, rel, b0)) b = b0;
            if (coralBox(co, c1, rel, b0)) b = float4(min(b.xy, b0.xy), max(b.zw, b0.zw));
        } else if (id >= ID_BUB && id < ID_BUB + N_BUB) {
            for (int k = 0; k < 2; k++) {
                const float tk = k == 0 ? t : t1;
                const Cam ck = k == 0 ? c : c1;
                const Bub bb = bubbleAt(id - ID_BUB, tk);
                const float rpx = ck.focal * bb.r / bb.z;
                if (rpx < 0.6f) continue;
                const float2 sc = float2(0.5f * ck.w + bb.x * ck.focal / bb.z, ck.horizon - (bb.y - ck.cy) * ck.focal / bb.z);
                b = float4(min(b.xy, sc - rpx - 2.0f), max(b.zw, sc + rpx + 2.0f));
            }
        }
        next.write(b + float4(-4.0f, -4.0f, 4.0f, 4.0f), gid);
        return;
    }
    if (gid.y >= R_SCHUNK) {
        // Coral segments projected once per frame: chunk boxes, then each segment's
        // endpoints as offsets (+4, so >= 1) from its chunk box corner; the signs of three
        // of them carry the branch depth, which gives thickness and colour.
        const bool isSeg = gid.y >= R_SSEG;
        if (gid.x >= 2048u) return;
        const uint m = (gid.y - (isSeg ? R_SSEG : R_SCHUNK)) * 2048u + gid.x;
        const uint lim = isSeg ? uint(N_CORAL * SEG_SLOTS) : uint(N_CORAL * NCH);
        if (m >= lim) return;
        const float4 empty = isSeg ? float4(0.0f) : float4(1.0e4f, 1.0e4f, -1.0e4f, -1.0e4f);
        const int k2 = int(m / (isSeg ? uint(SEG_SLOTS) : uint(NCH)));
        const int sub = int(m % (isSeg ? uint(SEG_SLOTS) : uint(NCH)));
        const int ch = isSeg ? sub >> 2 : sub;
        const Coral co = readCoral(prev, k2);
        float3 rel; float4 cb;
        if (ch * 4 >= co.nseg || (isSeg && sub >= co.nseg) || !coralBox(co, c, rel, cb)) { next.write(empty, gid); return; }
        const float sway = coralSway(co, t);
        const float4 box = co.kind == 3 ? anemChunk(co, rel, c, t, ch) : chunkScreen(prev, k2, ch, co, rel, c, sway);
        if (!isSeg) { next.write(box, gid); return; }
        const float2 org = float2(float(half(box.x)), float(half(box.y)));
        if (co.kind == 3) {
            const int tt = sub >> 2, kk = sub & 3;
            const float3 p0 = anemPoint(co, rel, t, tt, kk), p1 = anemPoint(co, rel, t, tt, kk + 1);
            if (p0.z < Z_NEAR || p1.z < Z_NEAR) { next.write(empty, gid); return; }
            float4 e = max(float4(projectP(p0, c) - org, projectP(p1, c) - org) + 4.0f, 1.0f);
            const int d = kk + 1;
            if (d & 1) e.x = -e.x;
            if (d & 2) e.y = -e.y;
            if (d & 4) e.z = -e.z;
            next.write(e, gid);
            return;
        }
        const uint nn = uint(k2 * SEG_SLOTS + sub) * 2u;
        const float4 A = prev.read(linTex(nn, R_SEG)), B = prev.read(linTex(nn + 1u, R_SEG));
        const float nx = -sin(co.angle), nz = cos(co.angle);
        const float sa = sway * A.y * A.y, sb = sway * B.y * B.y;
        const float za = rel.z + A.z + sa * nz, zb = rel.z + B.z + sb * nz;
        if (za < Z_NEAR || zb < Z_NEAR) { next.write(empty, gid); return; }
        const float2 pa = float2(0.5f * c.w + (rel.x + A.x + sa * nx) * c.focal / za, c.horizon - (rel.y + A.y) * c.focal / za);
        const float2 pb = float2(0.5f * c.w + (rel.x + B.x + sb * nx) * c.focal / zb, c.horizon - (rel.y + B.y) * c.focal / zb);
        float4 e = max(float4(pa - org, pb - org) + 4.0f, 1.0f);
        const int d = int(B.w * (co.kind == 1 ? 4.0f : 6.0f) + 0.5f);
        if (d & 1) e.x = -e.x;
        if (d & 2) e.y = -e.y;
        if (d & 4) e.z = -e.z;
        next.write(e, gid);
        return;
    }
    // Tile bins: four threads per screen tile, each scanning one range of items
    // and writing its own part of the tile's 12-texel list of ids + 1 (0 ends a part).
    if (gid.x >= 2048u) return;
    const uint n = (gid.y - R_BIN) * 2048u + gid.x;
    const uint ti = n / BIN_TEX, part = n % BIN_TEX;
    if (ti >= TILES_X * TILES_Y || (part != 0u && part != 4u && part != 7u && part != 10u)) return;
    const int pi = part == 0u ? 0 : (part == 4u ? 1 : (part == 7u ? 2 : 3));
    const int i0 = BIN_LO[pi], i1 = BIN_HI[pi];
    const int cap = int(BIN_PART_TEX[pi]) * 4;
    const float tw = 32.0f * ceil(c.w / (32.0f * float(TILES_X))), th = ceil(c.h / float(TILES_Y));
    const float4 tile = float4(float(ti % TILES_X) * tw, float(ti / TILES_X) * th, float(ti % TILES_X + 1u) * tw, float(ti / TILES_X + 1u) * th);
    float ids[16];
    int cnt = 0;
    for (int i = 0; i < 16; i++) ids[i] = 0.0f;
    for (int id = i0; id < i1 && cnt < cap; id++) {
        const float4 b = prev.read(uint2(uint(id), R_BOX));
        if (b.z < tile.x || b.x > tile.z || b.w < tile.y || b.y > tile.w) continue;
        ids[cnt++] = float(id + 1);
    }
    for (uint k = 0; k < BIN_PART_TEX[pi]; k++) next.write(float4(ids[4 * k], ids[4 * k + 1], ids[4 * k + 2], ids[4 * k + 3]), linTex(n + k, R_BIN));
}

// ------------------------------------------------------------------ draw --

static float4 mapAt(texture2d<float> st, float wx, float wz) {
    constexpr sampler sp(coord::pixel, filter::linear, address::clamp_to_edge);
    const float u = min(fract(wx / 128.0f) * 2048.0f, 2047.99f), v = min(fract(wz / 128.0f) * 2048.0f, 2047.99f);
    return st.sample(sp, float2(u + 0.5f, v + 0.5f));
}
static inline float hAt(texture2d<float> st, float wx, float wz) { return mapAt(st, wx, wz).a; }

static inline float3 fogged(float3 c, float z) { return mix3(c, WATER_HOR, 1.0f - exp(-FOG_K * z)); }

static inline uint ballot(bool v) { return uint(static_cast<simd_vote::vote_t>(simd_ballot(v))); }

// Distance from p to segment ab, measured the way the Zig line rasteriser fills
// (a span across the major axis), compared against half the pixel thickness.
static inline bool onLine(float2 p, float2 a, float2 b, float tw) {
    const float2 d = b - a;
    const float l2 = dot(d, d);
    const float h = l2 > 1e-6f ? saturate(dot(p - a, d) / l2) : 0.0f;
    const float2 q = p - a - d * h;
    const float l = sqrt(max(l2, 1e-12f));
    const float axisf = l2 > 1e-6f ? max(fabs(d.x), fabs(d.y)) / l : 1.0f;
    return dot(q, q) < pow(max(0.5f * tw * axisf, 0.55f), 2.0f);
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> st [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]],
                       uint lane [[thread_index_in_simdgroup]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float t = f.time;
    const Cam c = camera(f, t);
    const float2 px = float2(gid) + 0.5f;
    const float ck = (px.x - 0.5f * c.w) / c.focal;
    const float dy = (c.horizon - px.y) / c.focal;

    // ---- the reef: march the heightfield, skipping blocks the ray clears ----
    float z = dy < 0.0f ? max(Z_NEAR, (c.cy - REEF_TOP) / (-dy)) : Z_FAR;   // rays rising from the camera clear the reef
    float zprev = z;
    bool hit = false;
    uint cbk = 0xFFFFFFFFu, cfk = 0xFFFFFFFFu;
    float bm = 0.0f, fmx = 0.0f;
    for (int i = 0; i < 200 && z < Z_FAR; i++) {
        const float wx = c.cx + ck * z, wz = c.scroll + z, y = c.cy + dy * z;
        const float bxf = floor(wx * 0.25f), bzf = floor(wz * 0.25f);
        const uint bk = uint(int(bxf) & 31) + 32u * uint(int(bzf) & 31);
        if (bk != cbk) { cbk = bk; bm = st.read(uint2(bk, R_BLK)).r; }
        if (y > bm) {
            float ze = (bzf + 1.0f) * 4.0f - c.scroll;
            if (ck > 1e-6f) ze = min(ze, ((bxf + 1.0f) * 4.0f - c.cx) / ck);
            else if (ck < -1e-6f) ze = min(ze, (bxf * 4.0f - c.cx) / ck);
            if (dy < 0.0f) ze = min(ze, (c.cy - bm) / (-dy));
            zprev = max(ze, z);
            z = zprev + 2e-3f;
            continue;
        }
        const float fxf = floor(wx), fzf = floor(wz);
        const uint fn = uint(int(fxf) & 127) + 128u * uint(int(fzf) & 127);
        if (fn != cfk) { cfk = fn; fmx = st.read(linTex(fn, R_FBLK)).r; }
        if (y > fmx) {
            float ze = (fzf + 1.0f) - c.scroll;
            if (ck > 1e-6f) ze = min(ze, ((fxf + 1.0f) - c.cx) / ck);
            else if (ck < -1e-6f) ze = min(ze, (fxf - c.cx) / ck);
            if (dy < 0.0f) ze = min(ze, (c.cy - fmx) / (-dy));
            zprev = max(ze, z);
            z = zprev + 2e-3f;
            continue;
        }
        const float h = hAt(st, wx, wz);
        if (y <= h) { hit = true; break; }
        zprev = z;
        z += clamp(0.8f * (y - h), z * 0.02f, max(0.3f, z * 0.025f));
    }
    float best = 1.0e9f;
    float3 col = float3(0.0f);
    if (hit) {
        float lo = zprev, hi = z;
        for (int k = 0; k < 5; k++) {
            const float m = 0.5f * (lo + hi);
            if (c.cy + dy * m <= hAt(st, c.cx + ck * m, c.scroll + m)) hi = m; else lo = m;
        }
        z = hi;
        const float wx = c.cx + ck * z, wz = c.scroll + z;
        const float e = 1.0f / 16.0f;
        float4 m = mapAt(st, wx, wz);
        const float hc = m.a;
        const float gx = (hAt(st, wx + e, wz) - hAt(st, wx - e, wz)) * 8.0f;
        const float gz = (hAt(st, wx, wz + e) - hAt(st, wx, wz - e)) * 8.0f;
        const float gl = sqrt(gx * gx + gz * gz);
        float wall = 0.0f;
        if (gl > 4.0f) {
            // A wall (sponge, coral head, ledge): take the colour of the top it
            // belongs to and tint it toward the water with depth below that top.
            const float2 up = float2(gx, gz) / gl * (1.6f / 16.0f);
            m = mapAt(st, wx + up.x, wz + up.y);
            wall = saturate((m.a - hc) / 0.9f - 0.15f) * (200.0f / 256.0f);
            wall = min(wall, 150.0f / 256.0f);
        }
        float3 rc = mix3(m.rgb * 255.0f, WATER_HOR, wall);
        if (z < 40.0f) {
            const float cz = sin(wz * 22.0f * KW - fm(0.5f * t, TAU));
            const float cs = max(0.0f, sin(wx * 26.0f * KW + fm(0.7f * t, TAU) + 0.6f * cz) * cz);
            rc = min(rc * ((220.0f + 120.0f * cs * cs * (1.0f - z / 40.0f)) / 256.0f), float3(255.0f));
        }
        col = fogged(rc, z);
        best = z;
    }

    // ---- corals, fish and bubbles listed for this pixel's tile ----
    // Tiles are a multiple of 32 px wide, so the 32 pixels of a SIMD group (one row of a
    // 32-wide threadgroup) share one tile and walk one list together.
    const float tw = 32.0f * ceil(c.w / (32.0f * float(TILES_X))), th = ceil(c.h / float(TILES_Y));
    const uint ti = min(uint(px.x / tw), TILES_X - 1u) + TILES_X * min(uint(px.y / th), TILES_Y - 1u);
    float3 add = float3(0.0f);
    for (uint kk = 0; kk < BIN_TEX; kk++) {
        const float4 e4 = st.read(linTex(ti * BIN_TEX + kk, R_BIN));
        if (e4.x < 0.5f) {   // this part is done: jump to the next one
            kk = kk < 4u ? 3u : (kk < 7u ? 6u : (kk < 10u ? 9u : 11u));
            continue;
        }
        for (int j = 0; j < 4; j++) {
            const int id = int(e4[j] + 0.5f) - 1;
            if (id < 0) break;
            if (id < ID_CORAL) {
                const uint b = uint(id) * 4u;
                const float4 f3 = st.read(uint2(b + 3u, R_FISH));
                if (f3.y < 0.5f) continue;
                const float4 f2 = st.read(uint2(b + 2u, R_FISH));
                const float fz = f2.z + f2.w;
                if (fz >= best) continue;
                const float4 f0 = st.read(uint2(b, R_FISH)), f1 = st.read(uint2(b + 1u, R_FISH));
                const float hx = f0.x + f0.y, hy = f0.z + f0.w, tx = f1.x + f1.y, ty = f1.z + f1.w, W = f2.x + f2.y;
                const int si = speciesOf(id);
                float ax = tx - hx, ay = ty - hy;
                const float L = max(sqrt(ax * ax + ay * ay), 1e-3f);
                ax /= L; ay /= L;
                const float belly = SP_UPRIGHT[si] ? 1.0f : (ax >= 0.0f ? 1.0f : -1.0f);
                const float ddx = px.x - hx, ddy = px.y - hy;
                const float u = (ddx * ax + ddy * ay) / L;
                const float s = (ddy * ax - ddx * ay) * belly / W;
                if (u < -0.05f || u > 1.05f || fabs(s) > SP_EXT[si]) continue;
                float3 fc;
                // Morays come in two morphs (spotted and green); alternate them.
                const float sd = si == 4 ? (((id - SP_START[4]) & 1) != 0 ? 0.75f : 0.25f) : hash1(uint(id) + 9000u);
                if (shadeSpecies(si, u, s, f3.x, sd, fc)) { col = fogged(fc, fz); best = fz; }
            } else if (id < ID_BUB) {
                const int k2 = id - ID_CORAL;
                const float4 pb4 = st.read(uint2(uint(id), R_BOX));
                if (px.x < pb4.x || px.x > pb4.z || px.y < pb4.y || px.y > pb4.w) continue;
                const Coral co = readCoral(st, k2);
                float3 rel; float4 bx;
                if (!coralBox(co, c, rel, bx)) continue;
                if (rel.z >= best) continue;
                if (px.x < bx.x || px.x > bx.z || px.y < bx.y || px.y > bx.w) continue;
                bool on = false;
                float tcol = 0.0f;
                const float kpx = c.focal / rel.z;
                const float tk0 = co.size * (co.kind == 1 ? 0.13f : (co.kind == 2 ? 0.05f : 0.085f));
                const float dsc = co.kind == 2 ? 6.0f : 4.0f;
                const int nch = (co.nseg + 3) >> 2;
                // Pixels of one SIMD group normally share a tile, so they walk the same coral.
                // Then the active lanes split its chunk boxes between them (one read each, all at
                // once, instead of up to 23 in a row per pixel) and keep the chunks that touch any
                // of their pixels; the pixels visit only those, in chunk order as before.
                uint cm = nch >= 32 ? 0xFFFFFFFFu : (1u << uint(nch)) - 1u;
                if (simd_all(k2 == simd_broadcast_first(k2))) {
                    const uint act = ballot(true);
                    const uint rank = popcount(act & ((1u << lane) - 1u)), nact = popcount(act);
                    const float2 glo = float2(simd_min(px.x), simd_min(px.y)), ghi = float2(simd_max(px.x), simd_max(px.y));
                    uint bits = 0u;
                    for (int ch = int(rank); ch < nch; ch += int(nact)) {
                        const float4 lb = st.read(linTex(uint(k2 * NCH + ch), R_SCHUNK));
                        if (!(glo.x > lb.z || ghi.x < lb.x || glo.y > lb.w || ghi.y < lb.y)) bits |= 1u << uint(ch);
                    }
                    cm = simd_or(bits);
                }
                while (cm != 0u && !on) {
                    const int ch = int(ctz(cm));
                    cm &= cm - 1u;
                    const float4 bx = st.read(linTex(uint(k2 * NCH + ch), R_SCHUNK));
                    if (px.x < bx.x || px.x > bx.z || px.y < bx.y || px.y > bx.w) continue;
                    const int se = min(co.nseg, ch * 4 + 4);
                    for (int sg = ch * 4; sg < se; sg++) {
                        const float4 e = st.read(linTex(uint(k2 * SEG_SLOTS + sg), R_SSEG));
                        if (e.x == 0.0f) continue;
                        const float d = float((e.x < 0.0f ? 1 : 0) | (e.y < 0.0f ? 2 : 0) | (e.z < 0.0f ? 4 : 0));
                        const float2 pa = bx.xy + fabs(e.xy) - 4.0f, pb = bx.xy + fabs(e.zw) - 4.0f;
                        const float thick = co.kind == 1 ? tk0 * exp2(d * -0.2863f)
                                          : (co.kind == 2 ? max(0.012f, tk0 * (1.0f - 0.13f * d)) : tk0 * (1.0f - 0.1f * d));
                        if (onLine(px, pa, pb, clamp(floor(thick * kpx), 1.0f, 40.0f))) { on = true; tcol = d / dsc; break; }
                    }
                }
                if (on) {
                    const float3 base = co.kind == 1 ? STAG_BASE[co.style] : (co.kind == 2 ? FAN_BASE[min(co.style, 2)] : ANEM_BASE[min(co.style, 2)]);
                    const float3 tip = co.kind == 1 ? STAG_TIP[co.style] : (co.kind == 2 ? FAN_TIP[min(co.style, 2)] : ANEM_TIP[min(co.style, 2)]);
                    col = fogged(mix3(base, tip, tcol * tcol), rel.z);
                    best = rel.z;
                }
            } else {
                const Bub bb = bubbleAt(id - ID_BUB, t);
                const float sx = 0.5f * c.w + bb.x * c.focal / bb.z, sy = c.horizon - (bb.y - c.cy) * c.focal / bb.z;
                const float rpx = c.focal * bb.r / bb.z;
                const float fade = clamp(exp(-0.04f * bb.z), 0.2f, 1.0f);
                const float d = length(px - float2(sx, sy));
                add += float3(80, 130, 150) * fade * saturate(1.0f - fabs(d - rpx));
                const float2 gp = floor(float2(sx, sy) - 0.4f * rpx);
                if (all(floor(px) == gp)) add += float3(150, 200, 210) * fade;
            }
        }
    }

    // ---- water fills what is left; god rays fall over everything ----
    const float ny = float(gid.y) / c.h;
    if (best > 1.0e8f) {
        const float3 top = float3(34, 112, 136), bot = float3(6, 26, 48);
        col = ny < HORIZON ? mix3(top, WATER_HOR, pow(max(ny / HORIZON, 1e-5f), 0.8f))
                           : mix3(WATER_HOR, bot, pow(max((ny - HORIZON) / (1.0f - HORIZON), 1e-5f), 0.7f));
    }
    {
        float gain = clamp(150.0f * exp(-2.2f * ny) * (1.0f - ss(0.6f, 1.0f, ny)), 0.0f, 256.0f);
        if (best < 1.0e8f) gain *= 0.5f;
        const float ru = float(gid.x) + floor(float(gid.y) * 26.0f / 64.0f);
        const float b1 = 0.5f + 0.5f * sin(ru * 0.0062f + fm(0.13f * t, TAU));
        const float b2 = 0.5f + 0.5f * sin(ru * 0.0147f - fm(0.21f * t, TAU) + 1.7f);
        const float b3 = 0.5f + 0.5f * sin(ru * 0.0310f + fm(0.47f * t, TAU) + 0.4f);
        float v = b1 * b2 * (0.55f + 0.45f * b3);
        v = min(v * v * 1.7f * 255.0f, 255.0f);
        const float a = v * gain / 256.0f;
        col += a * float3(110.0f, 190.0f, 200.0f) / 256.0f;
        col = min(col, float3(255.0f));
    }

    // ---- marine snow: four depth layers drifting toward the camera ----
    const float sdrift = 0.3f * sin(fm(0.3f * t, TAU));
    for (int L = 0; L < 4; L++) {
        const float cyc = (float(L) + 0.5f) / 4.0f - t * CAM_SPEED / 40.0f;
        const float fz = fract(cyc);
        const float mz = 1.5f + fz * 40.0f;
        const float kz = c.focal / mz;
        const float mx = (px.x - 0.5f * c.w) / kz - sdrift;
        const float my = c.cy + (c.horizon - px.y) / kz + 0.08f * t;
        const float2 ci = floor(float2(mx, my) * (1.0f / 2.75f));
        uint hsh = uint(int(ci.x) + 4096) * 73856093u ^ uint(int(ci.y) + 4096) * 19349663u ^ (uint(int(floor(cyc)) + 100000) * 4u + uint(L)) * 83492791u;
        hsh ^= hsh >> 15; hsh *= 0x2C1B3C6Du; hsh ^= hsh >> 12;
        const float ox = (ci.x + float(hsh & 0xFFFFu) * (1.0f / 65536.0f)) * 2.75f;
        const float oy = (ci.y + float(hsh >> 16) * (1.0f / 65536.0f)) * 2.75f;
        const float rad = mz < 6.0f ? 1.0f : 0.5f;
        if (fabs(mx - ox) * kz < rad && fabs(my - oy) * kz < rad) {
            const float lum = 60.0f * exp(-0.05f * mz) + 6.0f;
            add += float3(0.5f, 0.75f, 1.0f) * lum * ss(0.0f, 0.06f, fz) * ss(1.0f, 0.9f, fz);
        }
    }

    col = min(col + add, float3(255.0f));
    out.write(float4(col / 255.0f, 1.0f), gid);
}

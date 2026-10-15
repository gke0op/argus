// ============================================================================
// LIZARD ISLAND // themes/Lizard_Island.metal
// Metal port by Claude Opus (Anthropic), 2026-10-15, of themes/Lizard_Island.zig
// (Claude Opus; species by Claude Haiku agents). Same lagoon, same species,
// same light cycle, run entirely on the GPU.
//
// A diver's drift over the lagoon at Lizard Island, northern Great Barrier
// Reef, built from field sources rather than imagination. Real scale: one
// world unit is one metre.
//
// What the sources say, and how it shows here. [cited] = page read,
// [snippet] = search result only, [atlas] = NbS atlas rows (York 2020,
// Gomis 2025). Sources: PCRF Lizard Island reef report; ISRA factsheet
// (sharkrayareas.org); Australian Museum, Lizard Island Research Station;
// eAtlas media 3988 (TropWATER/JCU); Fishes of Australia 317.
//   - Fringing reef from the low-tide mark to about 8 m; coral bommies from
//     1 m to 8 m deep; a lagoon 2-15 m deep [cited: PCRF reef report, ISRA].
//     Here: a sandy lagoon floor with bommies up to ~6 m tall, and the
//     fringing reef rising toward the shore on the left.
//   - Live hard coral cover only 24-27% [cited: PCRF]. Most bommie surface is
//     rock, algal turf and coralline crust; live coral is patchy.
//   - Massive corals (Porites, Diploastrea, Montastrea) dominate, with small
//     patches of branching and table Acropora; sponges in barrel, encrusting
//     and vase forms [cited: PCRF].
//   - Seagrass: Halophila ovalis, Thalassia hemprichii, Halodule uninervis
//     [atlas]; patchy, sparse on reef tops, denser (>25%) in sheltered sand
//     [snippet]. Here: patchy meadows on the lagoon sand, never a lawn.
//   - Water "cloudy, not turbid", visibility 11-16 m [cited: PCRF]. Here the
//     fog closes in at about that range.
//   - Giant clams on coral heads, five species, crocus clam most abundant
//     [cited: PCRF]; anemones with eastern clown anemonefish [cited: PCRF,
//     Fishes of Australia].
//   - Damselfish and fusiliers "by far the most abundant fish"; ~300
//     pickhandle barracuda at one bommie; barramundi cod [cited: PCRF].
//   - Blacktip reef sharks along the shore, aggregating "especially at
//     sunset"; tawny nurse shark seen eating a giant clam [cited: ISRA];
//     whitetip reef sharks [snippet]; green turtles grazing Halodule [cited:
//     eAtlas]; parrotfish [snippet]. Here the light runs a slow day / sunset /
//     dusk / sunrise cycle (960 s), and the blacktips come in around sunset
//     and sunrise.
// Not modelled because not sourced: mangrove genera and layout (mangroves
// are present at Lizard), zone widths, most day/night habits.
//
// How the GPU version works
//   - argus_init bakes the 64 m reef tile (2048 x 2048 texels, 3 cm each) into
//     the state texture: rgb = albedo, a = height. Sand, ripples, the fringing
//     reef, seagrass blades, bommies (lumpy massive-coral heads), sponges and
//     rubble. Bommies, sponges and rubble sit on jittered grids so each texel
//     only looks at its neighbour cells (the Zig placed them by rejection).
//   - argus_step runs on the first three frames only: frame 0 lights the tile
//     (Lambert + cavity, reds absorbed), frame 1 adds a 2 m block max-height map
//     and the coral placements, frame 2 copies so both ping-pong textures hold
//     the same finished table. After that it returns at once.
//   - argus_draw marches each pixel's ray over the heightfield at the Zig's own
//     depth-slice spacing (2 m blocks whose max height the ray clears are
//     skipped), keeping the voxel look: walls take the colour at their top and
//     tint toward the water further down. Fish, corals, anemones, clams and
//     marine snow are culled per threadgroup tile into threadgroup lists, then
//     depth-tested per pixel. Fish swim on closed-form paths (schools orbit an
//     anchor bommie or anemone that is re-picked ahead every 40 s; loners
//     wander around a station that drifts with the diver).
//
// @argus state 2048x2082
// ============================================================================

constant float TWO_PI = 6.2831853f;
constant float TILE = 64.0f;
constant float KK = 6.2831853f / 64.0f;   // base spatial frequency
constant float TEX = 32.0f;                // texels per metre
constant int   MAP_N = 2048;
constant uint  ROWS = 2082;                // guard + 2048 rows + guard + 32 block rows
constant uint  BLK_ROW0 = 2050;            // block max map at (0..BLK_N-1, 2050..)
constant int   BLK_T = 64;                 // texels per skip block (2 m)
constant int   BLK_N = 2048 / BLK_T;
constant float BLK_M = float(BLK_T) / 32.0f; // metres per skip block
constant uint  CORAL_COL0 = 64;            // coral table at (64 + i, 2050..2051)

constant float HORIZON = 0.42f;
constant float FOCAL = 0.80f;
constant float CAM_SPEED = 0.35f;
constant float CAM_Y = 2.6f;
constant float Z_NEAR = 0.5f;
constant float Z_FAR = 26.0f;
constant float Z_GROW = 0.017f;
constant float FOG_K = 0.115f;
constant float SURFACE_Y = 9.0f;
constant float DAY_PERIOD = 960.0f;
constant float H_BOUND = 11.5f;            // nothing on the reef is taller

constant float3 WATER_HOR = float3(46.0f, 104.0f, 112.0f) / 255.0f;

constant float3 LIVE_COLS[6] = { float3(196, 164, 104), float3(214, 198, 158), float3(176, 150, 92),
                                 float3(128, 138, 88), float3(136, 124, 168), float3(190, 150, 120) };
constant float3 TURF = float3(104, 92, 60);
constant float3 ROCK = float3(150, 138, 120);
constant float3 CORALLINE = float3(196, 128, 138);
constant float3 SPONGE_COLS[4] = { float3(128, 76, 70), float3(150, 92, 150), float3(214, 132, 58), float3(176, 60, 70) };
constant float3 STAG_BASE[3] = { float3(168, 140, 96), float3(150, 132, 104), float3(120, 128, 150) };
constant float3 STAG_TIP[3] = { float3(214, 214, 230), float3(150, 180, 250), float3(220, 170, 220) };
constant float3 TABLE_COLS[3] = { float3(150, 140, 96), float3(128, 134, 110), float3(168, 150, 120) };
constant float3 ANEM_BASE[3] = { float3(196, 176, 120), float3(168, 190, 120), float3(210, 190, 150) };
constant float3 ANEM_TIP[3] = { float3(240, 230, 170), float3(200, 240, 170), float3(255, 214, 214) };
constant float3 ANEM_COLUMN[3] = { float3(200, 40, 70), float3(150, 50, 140), float3(220, 200, 170) };
constant float3 MANTLE_COLS[5] = { float3(30, 110, 220), float3(20, 170, 170), float3(120, 160, 60),
                                   float3(120, 70, 200), float3(110, 110, 60) };

// ------------------------------------------------------------------ species --
// 0 Damselfish, 1 Fusilier, 2 Pickhandle barracuda, 3 Eastern clownfish,
// 4 Parrotfish, 5 Barramundi cod, 6 Blacktip shark, 7 Whitetip shark,
// 8 Tawny nurse shark, 9 Green turtle. Numbers as in the Zig species structs.
constant int   N_SPECIES = 10;
constant int   NUM_FISH = 173;
constant int   SP_START[10]  = { 0, 60, 108, 148, 153, 159, 162, 166, 169, 171 };
constant float SP_LEN[10]    = { 0.08f, 0.30f, 0.9f, 0.08f, 0.45f, 0.55f, 1.5f, 1.5f, 2.6f, 1.0f };
constant float SP_HD[10]     = { 0.27f, 0.14f, 0.08f, 0.24f, 0.24f, 0.24f, 0.10f, 0.10f, 0.10f, 0.28f };
constant float SP_EXT[10]    = { 1.4f, 1.3f, 1.6f, 1.3f, 1.4f, 1.6f, 2.6f, 2.4f, 2.2f, 2.4f };
constant float SP_SPEED[10]  = { 1.2f, 1.5f, 0.5f, 0.9f, 0.8f, 0.4f, 0.6f, 0.35f, 0.2f, 0.35f };
constant int   SP_SCHOOL[10] = { 1, 1, 1, 1, 0, 0, 0, 0, 0, 0 };
constant int   SP_HAB[10]    = { 0, 1, 1, 0, 0, 0, 1, 0, 0, 0 };
constant int   SP_ANCHOR[10] = { 1, 0, 1, 2, 0, 0, 0, 0, 0, 0 };   // 1 bommie, 2 anemone
constant int   SP_DUSK[10]   = { 0, 0, 0, 0, 0, 0, 1, 0, 0, 0 };

// Corals: 90 staghorn, 36 table, 28 anemones, 180 giant clams.
constant int NUM_CORAL = 334;
constant int CORAL_TABLE0 = 90;
constant int CORAL_ANEM0 = 126;
constant int CORAL_CLAM0 = 154;
constant int NUM_SNOW = 900;

// ------------------------------------------------------------------ helpers --

static inline float sstep(float e0, float e1, float x) {   // works for e0 > e1 too
    const float t = saturate((x - e0) / (e1 - e0));
    return t * t * (3.0f - 2.0f * t);
}
static inline float wrapD(float d) { return d - TILE * rint(d / TILE); }
static inline float wrap64(float v) { return v - TILE * floor(v / TILE); }
static inline float channelX(float z) { return 34.0f + 5.0f * sin(KK * z) + 2.0f * sin(2.0f * KK * z + 1.0f); }
static inline float lagoonDx(float wx, float wz) { return wrapD(wx - channelX(wz)); }
static inline float fringeHeight(float dx) { return 5.0f * max(sstep(-7.0f, -20.0f, dx), sstep(27.0f, 31.5f, dx)); }
static inline float rnd(uint h, uint k) { return float(argus_hash(h + k * 0x9E3779B9u)) * (1.0f / 4294967296.0f); }
// (t * freq) mod 2 pi without ever forming a huge argument.
static inline float ph(float t, float fr) { const float P = TWO_PI / fr; return (t - P * floor(t / P)) * fr; }
static inline float scrollAt(float t) { const float P = TILE / CAM_SPEED; return (t - P * floor(t / P)) * CAM_SPEED; }
static inline float camxAt(float t) { return channelX(scrollAt(t) + 4.0f); }
static inline float habitatY(int hab) { return hab == 0 ? 1.0f : (hab == 1 ? 3.0f : 5.5f); }
static inline float3 fogged(float3 c255, float z) { return mix(c255 / 255.0f, WATER_HOR, 1.0f - exp(-FOG_K * z)); }

static inline float hash01(uint x, uint y, uint seed) {
    uint h = x * 0x8DA6B343u + y * 0xD8163841u + seed * 0xCB1AB31Fu;
    h ^= h >> 13; h *= 0x5BD1E995u; h ^= h >> 15;
    return float(h & 0xFFFFu) / 65535.0f;
}

/// Periodic value noise on a `cells` x `cells` lattice over the tile (as the Zig).
static float valueNoise(float wx, float wz, uint cells, uint seed) {
    const float s = float(cells) / TILE;
    const float u = wx * s, v = wz * s;
    const float fu = floor(u), fv = floor(v);
    const uint iu = uint(max(0.0f, fu)) % cells, iv = uint(max(0.0f, fv)) % cells;
    const uint ju = (iu + 1) % cells, jv = (iv + 1) % cells;
    const float tu = u - fu, tv = v - fv;
    const float su = tu * tu * (3.0f - 2.0f * tu), sv = tv * tv * (3.0f - 2.0f * tv);
    const float a = hash01(iu, iv, seed), b = hash01(ju, iv, seed);
    const float c = hash01(iu, jv, seed), d = hash01(ju, jv, seed);
    const float ab = a + (b - a) * su, cd = c + (d - c) * su;
    return ab + (cd - ab) * sv;
}

// ------------------------------------------------------------- the reef bake --

/// Reef rock colour (0..255): turf, rock, coralline crust, ~25% live massive coral.
static float3 reefSurface(float wx, float wz) {
    const float n_live = valueNoise(wx, wz, 160, 21);
    const float n_kind = valueNoise(wx, wz, 64, 22);
    const float n_crust = valueNoise(wx, wz, 256, 23);
    const float speck = 0.85f + 0.3f * valueNoise(wx, wz, 1024, 24);
    float3 c = mix(TURF, ROCK, sstep(0.3f, 0.7f, valueNoise(wx, wz, 128, 25)));
    c = mix(c, CORALLINE, 0.8f * sstep(0.62f, 0.8f, n_crust));
    const float live = sstep(0.58f, 0.62f, n_live);
    if (live > 0.0f) {
        const int k = int(clamp(n_kind * 5.99f, 0.0f, 5.0f));
        float3 lc = LIVE_COLS[k];
        if (k == 3 && sin(wx * 60.0f) * sin(wz * 60.0f) > 0.4f) lc *= 0.75f;   // polyp grid
        c = mix(c, lc, live);
    }
    if (valueNoise(wx, wz, 200, 26) > 0.86f) c = mix(c, SPONGE_COLS[2], 0.7f);   // encrusting sponge
    return c * speck;
}

/// Lagoon floor height without seagrass (used for feature bases).
static float groundBase(float wx, float wz) {
    const float dx = lagoonDx(wx, wz);
    const float rarg = 128.0f * KK * wx + 40.0f * KK * wz + 2.0f * sin(9.0f * KK * wz);
    const float undul = 0.35f * (valueNoise(wx, wz, 16, 11) - 0.5f);
    const float fringe = fringeHeight(dx);
    const float on_reef = sstep(0.3f, 1.2f, fringe);
    float h = undul + 0.025f * sin(rarg) * (1.0f - on_reef) + fringe;
    if (on_reef > 0.0f) h += on_reef * ((valueNoise(wx, wz, 256, 12) - 0.5f) * 0.5f + (valueNoise(wx, wz, 1024, 13) - 0.5f) * 0.12f);
    return h;
}

/// Pass 1 of the Zig bake for one texel: sand, fringing reef, patchy seagrass.
static void groundTexel(uint tu, uint tv, thread float& h, thread float3& c) {
    const float wx = (float(tu) + 0.5f) / TEX, wz = (float(tv) + 0.5f) / TEX;
    const float dx = lagoonDx(wx, wz);
    const float rarg = 128.0f * KK * wx + 40.0f * KK * wz + 2.0f * sin(9.0f * KK * wz);
    const float undul = 0.35f * (valueNoise(wx, wz, 16, 11) - 0.5f);
    const float fringe = fringeHeight(dx);
    const float on_reef = sstep(0.3f, 1.2f, fringe);
    float rough = 0.0f;
    if (on_reef > 0.0f) rough = (valueNoise(wx, wz, 256, 12) - 0.5f) * 0.5f + (valueNoise(wx, wz, 1024, 13) - 0.5f) * 0.12f;
    h = undul + 0.025f * sin(rarg) * (1.0f - on_reef) + fringe + rough * on_reef;
    c = mix(float3(228, 222, 200), float3(206, 196, 170), 0.5f + 0.5f * sin(rarg));   // pale carbonate sand
    if (on_reef > 0.0f) c = mix(c, reefSurface(wx, wz), on_reef);
    if (on_reef < 0.2f) {
        const float meadow = sstep(0.52f, 0.68f, valueNoise(wx, wz, 12, 14));
        const float cover = meadow * (0.15f + 0.3f * valueNoise(wx, wz, 96, 15));
        // Under the blades the meadow floor reads as a dim green mat (lower blades,
        // rhizomes, the shade of the canopy), not bright sand. Besides being how a
        // meadow looks, that keeps each 3 cm blade close in tone to what's behind
        // it, so the thousands of pixel-sized blades don't shimmer as the diver
        // drifts (bright sand between dark spikes did).
        const float mat = max(sstep(0.0f, 0.25f, cover), 0.6f * meadow);   // reaches the meadow's edges too
        const float3 floor_c = mix(mix(c, float3(176, 170, 140), 0.35f * meadow), float3(92, 116, 70), 0.75f * mat);
        // At the very edge of a meadow, where the mat is thinnest, blades thin out first.
        if (hash01(tu, tv, 16) < cover * sstep(0.15f, 0.5f, meadow)) {
            // One texel (3 cm) blade: Thalassia straps and shorter Halodule.
            h += 0.10f + 0.22f * hash01(tu, tv, 17);
            c = mix(float3(84, 132, 68), float3(116, 124, 72), hash01(tu, tv, 18));
        } else if (meadow > 0.0f) {
            c = floor_c;
        }
    }
}

// Bommies: one candidate per cell of a 14 x 14 grid (4.57 m), kept clear of the
// drift path and mostly off the fringing reef, as the Zig's rejection rules.
constant int   BC = 14;
constant float BCS = 64.0f / 14.0f;

struct Bommie { float x, z, r, tall; uint s; int lobes; bool ok; };

static Bommie bommieCell(int ci, int cj) {
    ci = ((ci % BC) + BC) % BC;
    cj = ((cj % BC) + BC) % BC;
    Bommie b;
    b.s = argus_hash(uint(ci * BC + cj) ^ 0xB0331E5Du);
    b.x = (float(ci) + 0.2f + 0.6f * rnd(b.s, 1)) * BCS;
    b.z = (float(cj) + 0.2f + 0.6f * rnd(b.s, 2)) * BCS;
    b.r = 0.9f + 2.0f * rnd(b.s, 3);
    b.ok = rnd(b.s, 0) < 0.9f;
    const float dx = lagoonDx(b.x, b.z);
    if (fabs(dx) < b.r + 2.2f) b.ok = false;                                  // keep the path clear
    if (fringeHeight(dx) > 2.0f && rnd(b.s, 4) < 0.7f) b.ok = false;
    b.tall = min(4.5f, b.r * (0.7f + 0.9f * rnd(b.s, 5)));
    b.lobes = 6 + int(rnd(b.s, 6) * 6.0f);
    return b;
}

/// Raises h to the tallest bommie lobe at (wx, wz); true if any lobe did.
static bool bommieMax(float wx, float wz, thread float& h) {
    const int icx = int(floor(wx / BCS)), icz = int(floor(wz / BCS));
    bool raised = false;
    for (int dj = -1; dj <= 1; dj++) {
        for (int di = -1; di <= 1; di++) {
            const Bommie b = bommieCell(icx + di, icz + dj);
            if (!b.ok) continue;
            const float ex = wrapD(wx - b.x), ez = wrapD(wz - b.z);
            const float reach = 1.45f * b.r + 0.05f;
            if (ex * ex + ez * ez > reach * reach) continue;
            const float base = groundBase(b.x, b.z);
            for (int l = 0; l < b.lobes; l++) {
                const uint ls = argus_hash(b.s ^ (uint(l) + 1u) * 0x85EBCA6Bu);
                const float a = rnd(ls, 0) * TWO_PI;
                const float off = l == 0 ? 0.0f : b.r * (0.3f + 0.55f * rnd(ls, 1));
                const float lr = l == 0 ? b.r * 0.8f : b.r * (0.3f + 0.3f * rnd(ls, 2));
                const float lx = wrapD(wx - (b.x + cos(a) * off));
                const float lz = wrapD(wz - (b.z + sin(a) * off));
                const float d2 = (lx * lx + lz * lz) / (lr * lr);
                if (d2 >= 1.0f) continue;
                const float lh = l == 0 ? b.tall : b.tall * (0.35f + 0.55f * rnd(ls, 3));
                const uint seed = uint(rnd(ls, 4) * 60000.0f);
                // Porites-style lumps: a dome with knobbly lobes on it.
                const float q = sqrt(max(0.0f, 1.0f - d2));
                const float dome = lh * q * (0.85f + 0.15f * q);
                const float knob = 0.40f * lr * (valueNoise(wx, wz, 128, seed) - 0.5f) + 0.12f * (valueNoise(wx, wz, 512, seed + 1) - 0.5f);
                const float hh = base + dome + knob;
                if (hh > h) { h = hh; raised = true; }
            }
        }
    }
    return raised;
}

static float heightNoSponge(float wx, float wz) {
    float h = groundBase(wx, wz);
    bommieMax(wrap64(wx), wrap64(wz), h);
    return h;
}

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    if (gid.y >= BLK_ROW0 || gid.x >= uint(MAP_N)) { state.write(float4(0.0f), gid); return; }
    // Row 0 and row 2049 are guard copies of data rows 2047 and 0 (seamless bilinear wrap).
    const uint tu = gid.x;
    const uint tv = (gid.y + uint(MAP_N) - 1u) % uint(MAP_N);
    const float wx = (float(tu) + 0.5f) / TEX, wz = (float(tv) + 0.5f) / TEX;

    float h; float3 c;
    groundTexel(tu, tv, h, c);
    if (bommieMax(wx, wz, h)) c = reefSurface(wx, wz);

    // Sponges: barrel and vase forms on bommies and the reef slope (13 x 13 grid).
    {
        const float cs = 64.0f / 13.0f;
        const int icx = int(floor(wx / cs)), icz = int(floor(wz / cs));
        for (int dj = -1; dj <= 1; dj++) for (int di = -1; di <= 1; di++) {
            const int ci = ((icx + di) % 13 + 13) % 13, cj = ((icz + dj) % 13 + 13) % 13;
            const uint s = argus_hash(uint(ci * 13 + cj) ^ 0x5B0A9E77u);
            const float cx = (float(ci) + 0.1f + 0.8f * rnd(s, 1)) * cs;
            const float cz = (float(cj) + 0.1f + 0.8f * rnd(s, 2)) * cs;
            const bool vase = rnd(s, 3) < 0.4f;
            const float r = vase ? 0.10f + 0.08f * rnd(s, 4) : 0.18f + 0.2f * rnd(s, 4);
            const float ex = wrapD(wx - cx), ez = wrapD(wz - cz);
            const float d2 = (ex * ex + ez * ez) / (r * r);
            if (d2 >= 1.0f) continue;
            if (fabs(lagoonDx(cx, cz)) < 2.5f) continue;
            const float base = heightNoSponge(cx, cz);
            if (base < 0.6f) continue;   // on rock, not on sand
            const float tall = vase ? 0.35f + 0.3f * rnd(s, 5) : r * (1.2f + 1.0f * rnd(s, 5));
            const float3 col = SPONGE_COLS[int(rnd(s, 6) * 3.99f)];
            const float hh = d2 < 0.40f ? base + tall * 0.5f : base + tall;
            if (hh > h) { h = hh; c = d2 < 0.40f ? col * 0.3f : col; }
        }
    }
    // Coral rubble on the lagoon sand (20 x 20 grid).
    {
        const float cs = 3.2f;
        const int icx = int(floor(wx / cs)), icz = int(floor(wz / cs));
        for (int dj = -1; dj <= 1; dj++) for (int di = -1; di <= 1; di++) {
            const int ci = ((icx + di) % 20 + 20) % 20, cj = ((icz + dj) % 20 + 20) % 20;
            const uint s = argus_hash(uint(ci * 20 + cj) ^ 0x7B1EB1E5u);
            if (rnd(s, 0) > 0.65f) continue;
            const float cx = (float(ci) + 0.05f + 0.9f * rnd(s, 1)) * cs;
            const float cz = (float(cj) + 0.05f + 0.9f * rnd(s, 2)) * cs;
            const float r = 0.06f + 0.14f * rnd(s, 3);
            const float ex = wrapD(wx - cx), ez = wrapD(wz - cz);
            const float d2 = (ex * ex + ez * ez) / (r * r);
            if (d2 >= 1.0f) continue;
            if (fabs(lagoonDx(cx, cz)) < 1.0f) continue;
            const float base = heightNoSponge(cx, cz);
            if (base > 0.4f) continue;
            const float tall = r * (0.3f + 0.3f * rnd(s, 4));
            const float hh = base + tall * sqrt(max(0.0f, 1.0f - d2));
            if (hh > h) { h = hh; c = float3(200, 190, 166) * (0.75f + 0.3f * rnd(s, 5)); }
        }
    }
    state.write(float4(saturate(c / 255.0f), h), gid);
}

// ------------------------------------------------- one-time lighting / tables --

static inline float hRead(texture2d<float, access::read> t, int iu, int iv) {
    return t.read(uint2(uint(iu & (MAP_N - 1)), uint(iv & (MAP_N - 1)) + 1u)).a;
}

static float hBilinear(texture2d<float, access::read> t, float x, float z) {
    const float u = x * TEX - 0.5f, v = z * TEX - 0.5f;
    const float fu = floor(u), fv = floor(v);
    const int iu = int(fu), iv = int(fv);
    const float tu = u - fu, tv = v - fv;
    const float a = mix(hRead(t, iu, iv), hRead(t, iu + 1, iv), tu);
    const float b = mix(hRead(t, iu, iv + 1), hRead(t, iu + 1, iv + 1), tu);
    return mix(a, b, tv);
}

// Coral placement: small patches of branching Acropora, table Acropora and
// anemones on bommie tops, giant clams set into coral heads (a few T. gigas on
// the sand beside them). kind: 1 staghorn, 3 anemone, 4 table, 5 clam.
static float4 coralPlace(int i, thread float4& extra) {
    const uint h = argus_hash(uint(i) * 0x632BE5ABu + 0xC0A1u);
    int kind = 1; float reach = 0.7f; float size = 0.35f + 0.25f * rnd(h, 10); int style = int(rnd(h, 11) * 2.99f);
    bool gigas = false;
    if (i >= CORAL_CLAM0) {
        kind = 5;
        const int ci = i - CORAL_CLAM0;
        if (ci % 45 == 0) { gigas = true; reach = 1.0f; style = 4; size = 0.45f + 0.15f * rnd(h, 10); }
        else { reach = 0.9f; style = int(rnd(h, 11) * 3.99f); size = rnd(h, 12) < 0.75f ? 0.07f + 0.05f * rnd(h, 10) : 0.14f + 0.10f * rnd(h, 10); }
    } else if (i >= CORAL_ANEM0) { kind = 3; reach = 0.85f; size = 0.22f + 0.15f * rnd(h, 10); }
    else if (i >= CORAL_TABLE0) { kind = 4; reach = 0.8f; size = 0.35f + 0.5f * rnd(h, 10); }
    Bommie b; b.ok = false;
    for (uint k = 0; k < 16 && !b.ok; k++) {
        const uint c = argus_hash(h + k * 0x2545F491u) % uint(BC * BC);
        b = bommieCell(int(c / uint(BC)), int(c % uint(BC)));
    }
    const float a = rnd(h, 13) * TWO_PI;
    const float d = b.r * reach * sqrt(rnd(h, 14));
    float x = b.x + cos(a) * d, z = b.z + sin(a) * d;
    if (gigas) x += 1.4f;
    extra = float4(rnd(h, 15) * TWO_PI, float(kind), float(style), b.ok ? 1.0f : 0.0f);
    return float4(wrap64(x), wrap64(z), 0.0f, size);
}

// ------------------------------------------------------------------- scene --

struct Scene {
    float t, w, h, focal, hor, scroll, camx, camy;
    float gold, dim;
};

static Scene makeScene(constant ArgusFrame& f) {
    Scene S;
    S.t = f.time;
    S.w = float(f.width);
    S.h = float(f.height);
    S.focal = FOCAL * S.h;
    S.hor = HORIZON * S.h;
    S.scroll = scrollAt(S.t);
    S.camx = channelX(S.scroll + 4.0f);
    S.camy = CAM_Y + 0.15f * sin(ph(S.t, 0.19f));
    // Day, sunset, dusk and sunrise over DAY_PERIOD seconds.
    const float pday = fract(S.t / DAY_PERIOD + 0.35f);
    auto bump = [](float x, float c, float w) { const float d = (x - c) / w; return max(0.0f, 1.0f - d * d); };
    S.gold = min(1.0f, bump(pday, 0.74f, 0.07f) + bump(pday, 0.95f, 0.06f));
    S.dim = bump(pday, 0.845f, 0.05f);
    return S;
}

constexpr sampler reefSampler(coord::normalized, s_address::repeat, t_address::clamp_to_edge, filter::linear);

/// Baked reef at world (x, z): rgb lit albedo, a height.
static inline float4 reefAt(texture2d<float> st, float x, float z) {
    const float zz = wrap64(z);
    return st.sample(reefSampler, float2(x * (1.0f / TILE), (zz * TEX + 1.0f) / float(ROWS)));
}

static inline bool project(Scene S, float rx, float ry, float rz, thread float2& p) {
    if (rz < Z_NEAR) return false;
    const float k = S.focal / rz;
    p = float2(0.5f * S.w + rx * k, S.hor - ry * k);
    return true;
}

static inline float segDist(float2 p, float2 a, float2 b) {
    const float2 ab = b - a, ap = p - a;
    const float t = saturate(dot(ap, ab) / max(dot(ab, ab), 1e-6f));
    return length(ap - ab * t);
}

/// The Zig's fillLine: an opaque line `thick` pixels wide.
static inline bool onLine(float2 p, float2 a, float2 b, float thick) {
    const float tw = floor(clamp(thick, 1.0f, 40.0f));
    return segDist(p, a, b) <= 0.5f * tw + 0.15f;
}

static inline uint stagSeed(uint i) { return argus_hash(i * 0x2C1B3C6Du + 0x57A6u); }

/// The Zig's growStaghorn: 3-5 trunks, each branching 1-2 ways down to depth 4,
/// at most 40 segments. Calls visit(base, tip, thickness, depth) per segment
/// until it returns true.
template <typename F>
static void stagGrow(uint seed, float size, thread F& visit) {
    uint st = seed;
    auto R = [&]() { st = argus_hash(st + 0x9E3779B9u); return float(st) * (1.0f / 4294967296.0f); };
    float3 sp[12], sd[12]; float sl[12], sth[12]; int sdep[12];
    int n = 0;
    const int trunks = 3 + int(R() * 3.0f);
    for (int i = 0; i < trunks; i++) {
        const float a = R() * TWO_PI, lean = 0.25f + 0.5f * R();
        sp[n] = float3(0.0f); sd[n] = normalize(float3(cos(a) * lean, 1.0f, sin(a) * lean));
        sl[n] = 0.36f * size; sth[n] = 0.13f * size; sdep[n] = 0; n++;
    }
    int segs = 0;
    while (n > 0 && segs < 40) {
        n--;
        const float3 p = sp[n], d = sd[n];
        const float len = sl[n], th = sth[n]; const int dep = sdep[n];
        const float3 e = p + d * len;
        segs++;
        if (visit(p, e, th, dep)) return;
        if (dep >= 4) continue;
        const int kids = R() < 0.55f ? 2 : 1;
        for (int j = 0; j < kids && n < 12; j++) {
            const float a = R() * TWO_PI, spread = 0.45f + 0.35f * R();
            sp[n] = e; sd[n] = normalize(float3(d.x + cos(a) * spread, d.y + 0.25f, d.z + sin(a) * spread));
            sl[n] = len * (0.78f + 0.1f * R()); sth[n] = th * 0.82f; sdep[n] = dep + 1; n++;
        }
    }
}

// --------------------------------------------------------------- creatures --
// Species shading, ported from the Zig species structs (colours 0..255).
//   u: along the body, 0 nose .. 1 tail tip; s: across, in units of W, s < 0 back;
//   t: tail-beat phase; seed: 0..1 per animal.

static inline bool inTri(float px, float py, float ax, float ay, float bx, float by, float cx, float cy) {
    const float d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
    const float d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
    const float d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
    const bool neg = d1 < 0.0f || d2 < 0.0f || d3 < 0.0f;
    const bool pos = d1 > 0.0f || d2 > 0.0f || d3 > 0.0f;
    return !(neg && pos);
}

static bool shadeClown(float u, float s, float t, thread float3& c) {
    const float sb = s - 0.5f * sin(t) * u * u;
    const float a = fabs(sb);
    float hw = 0.0f;
    if (u >= 0.0f && u <= 1.0f) {
        const float uq = floor(u * 63.0f) / 63.0f;
        const float p = min(uq / 0.78f, 1.0f);
        hw = uq <= 0.78f ? 0.18f + 0.82f * sin(M_PI_F * pow(max(p, 1e-6f), 0.62f)) : 0.18f;
    }
    bool tail = false;
    if (u > 0.74f && u <= 1.0f) {
        const float tf = (u - 0.74f) / 0.26f;
        const float notch = tf > 0.7f ? 0.5f * (tf - 0.7f) / 0.3f : 0.0f;
        if (1.05f * tf > hw && a > notch) { hw = 1.05f * tf; tail = true; }
    }
    if (a > hw) return false;
    const float k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    c = mix(float3(240, 104, 18), float3(255, 140, 40), k);
    const float2 bars[3] = { float2(0.17f, 0.27f), float2(0.44f, 0.56f), float2(0.74f, 0.80f) };
    for (int i = 0; i < 3; i++) {
        const float2 b = bars[i];
        if (u > b.x && u < b.y) c = float3(250, 248, 244);
        if ((u > b.x - 0.035f && u <= b.x) || (u >= b.y && u < b.y + 0.035f)) c = float3(26, 18, 14);
    }
    if (tail && u > 0.93f) c = float3(26, 18, 14);
    if (hw - a < 0.07f) c *= 0.7f;
    const float eu = (u - 0.12f) / 0.06f, ev = (sb + 0.22f) / 0.17f;
    if (eu * eu + ev * ev < 1.0f) c = float3(14, 14, 20);
    return true;
}

static inline float3 btFin(float sb, bool tip) {
    if (tip) return float3(18, 18, 22);
    return sb < 0.0f ? float3(78, 86, 92) : float3(210, 212, 210);
}

static bool shadeBlacktip(float u, float s, float t, thread float3& c) {
    const float rear = saturate((u - 0.45f) / 0.55f);
    const float sb = s - 0.7f * sin(t) * rear * rear;
    const float a = fabs(sb);
    const float p = saturate(u / 0.8f);
    const float hw = (u >= 0.0f && u <= 0.8f) ? 0.04f + 0.96f * sin(M_PI_F * pow(max(p, 1e-6f), 0.8f)) : 0.0f;
    if (a <= hw) {
        const float k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
        const float m = saturate((k - 0.3f) / 0.4f);
        c = float3(86 + 160 * m, 92 + 154 * m, 92 + 146 * m);
        if (u > 0.15f && u < 0.27f && a < 0.4f && fract((u - 0.15f) / 0.024f) < 0.2f) c *= 0.72f;
        if (hw - a < 0.09f) c *= 0.55f;
        const float eu = (u - 0.10f) / 0.022f, ev = (sb + 0.20f) / 0.22f;
        if (eu * eu + ev * ev < 1.0f) c = float3(12, 12, 16);
        return true;
    }
    if (inTri(u, sb, 0.29f, -0.2f, 0.44f, -2.2f, 0.57f, -0.2f)) { c = btFin(sb, -sb > 1.85f); return true; }
    if (inTri(u, sb, 0.66f, -0.1f, 0.78f, -0.85f, 0.84f, -0.1f)) { c = btFin(sb, -sb > 0.7f); return true; }
    if (inTri(u, sb, 0.66f, 0.1f, 0.78f, 0.7f, 0.84f, 0.1f)) { c = btFin(sb, sb > 0.6f); return true; }
    if (inTri(u, sb, 0.16f, 0.2f, 0.44f, 1.9f, 0.34f, 0.2f)) { c = btFin(sb, sb > 1.5f && u > 0.36f); return true; }
    if (inTri(u, sb, 0.62f, -0.1f, 1.0f, -2.0f, 0.93f, -0.12f)) { c = btFin(sb, u > 0.93f && sb < -1.7f); return true; }
    if (inTri(u, sb, 0.62f, 0.1f, 0.97f, 0.85f, 0.93f, 0.12f)) { c = btFin(sb, u > 0.9f && sb > 0.6f); return true; }
    return false;
}

static bool shadeParrot(float u, float s, float t, thread float3& c) {
    const float sb = s - 0.18f * sin(t) * u * u;
    const float a = fabs(sb);
    const float p = saturate(u / 0.8f);
    const float hw = (u >= 0.0f && u <= 0.8f) ? 0.12f + 0.88f * sin(M_PI_F * pow(max(p, 1e-6f), 0.7f)) : 0.0f;
    const float fh = (sb < 0.0f && u > 0.08f && u <= 0.8f) ? 0.27f * sqrt(max(0.0f, sin(M_PI_F * (u - 0.08f) / 0.72f))) : 0.0f;
    const float tf = saturate((u - 0.8f) / 0.2f);
    const float notch = 0.4f * tf * tf;
    const float th = 0.12f + 0.95f * tf;
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
        if (fabs(sin(u * 150.0f)) < 0.15f) c = mix(c, float3(40, 130, 130), 0.35f);
    } else {
        const float e = min(fabs(sin(140.0f * u + 12.0f * sb)), fabs(sin(40.0f * sb)));
        c = mix(teal, float3(246, 124, 92), saturate(1.0f - e / 0.2f) * 0.7f);
        if (hw - a < 0.07f) c *= 0.6f;
        if (u > 0.2f && u < 0.44f && sb > -0.05f && sb < 0.5f) {
            const float ang = 0.35f * sin(t);
            const float du = u - 0.32f, ds = sb - 0.24f;
            const float cs = cos(ang), sn = sin(ang);
            const float pu = (du * cs + ds * sn) / 0.09f, ps = (-du * sn + ds * cs) / 0.25f;
            const float pr = pu * pu + ps * ps;
            if (pr < 1.0f) { c = mix(c, float3(176, 242, 222), 0.6f); if (pr > 0.6f) c = float3(250, 130, 110); }
        }
        const float cu = (u - 0.19f) / 0.06f, cv = (sb - 0.3f) / 0.12f;
        if (cu * cu + cv * cv < 1.0f) c = mix(c, float3(255, 102, 122), 0.85f);
        if (u < 0.08f && sb > -0.15f && sb < 0.4f) {
            c = float3(240, 238, 224);
            if (u > 0.035f && u < 0.045f) c = float3(190, 188, 178);
        }
        const float eu = (u - 0.14f) / 0.055f, ev = (sb + 0.2f) / 0.15f;
        const float d2 = eu * eu + ev * ev;
        if (d2 < 0.36f) c = float3(16, 16, 22); else if (d2 < 1.0f) c = float3(244, 206, 74);
    }
    return true;
}

static inline float3 turtleSkin(float x, float y, float3 base) {
    const float dx = x * 46.0f - floor(x * 46.0f) - 0.5f, dy = y * 46.0f - floor(y * 46.0f) - 0.5f;
    return (dx * dx + dy * dy < 0.07f) ? float3(176, 190, 160) : base;
}

static inline float flipperInside(float x, float y, float rx, float ry, float ang, float len, float w0, float w1) {
    const float dx = sin(ang), dy = cos(ang);
    const float px = x - rx, py = y - ry;
    const float al = px * dx + py * dy;
    if (al < -0.06f || al > len) return -1.0f;
    const float f = saturate(al / len);
    const float hw = w1 + (w0 - w1) * (1.0f - f) * sqrt(max(0.0f, 1.0f - f * f + 0.02f));
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
            const float gy = (y + 0.23f) * 12.0f;
            const float row = floor(gy);
            const float odd = row - 2.0f * floor(row * 0.5f);
            const float gx = (x - 0.49f) * 12.0f + (odd == 0.0f ? 0.0f : 0.5f);
            const float cx = floor(gx);
            const float fx = gx - cx, fy = gy - row;
            if (min(fx, 1.0f - fx) < 0.08f || min(fy, 1.0f - fy) < 0.08f) { c = float3(54, 48, 26); return true; }
            const float hh = saturate((-y - 0.02f) / 0.22f);
            const float par = (cx + row) - 2.0f * floor((cx + row) * 0.5f);
            const float alt = par == 0.0f ? 0.94f : 1.0f;
            c = float3(98 + 30 * hh, 102 + 26 * hh, 50 + 18 * hh) * alt;
            return true;
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
        const float hwt = 0.05f * pow(max(1.0f - tf, 1e-6f), 0.9f);
        const float ta = fabs(y);
        if (ta < hwt) { c = (hwt - ta < 0.01f) ? float3(40, 46, 34) : turtleSkin(x, y, float3(92, 110, 82)); return true; }
    }
    return false;
}

static bool shadeDamsel(float u, float s, float t, float seed, thread float3& c) {
    const float sb = s - 0.22f * sin(t) * u * u;
    const float a = fabs(sb);
    const bool dorsal = sb < 0.0f;
    const bool humbug = seed >= 0.85f;
    const bool yellow = seed >= 0.6f && seed < 0.85f;
    float hw = 0.0f;
    if (u >= 0.0f && u <= 0.78f) {
        const float xs = u < 0.36f ? (0.36f - u) / 0.36f : (u - 0.36f) / 0.42f;
        hw = 0.2f + 0.8f * sqrt(max(0.0f, 1.0f - xs * xs));
    } else if (u > 0.78f && u <= 0.84f) hw = 0.2f;
    float tf = 0.0f; bool tail = false;
    if (u > 0.78f && u <= 1.0f) { tf = (u - 0.78f) / 0.22f; tail = a > 0.4f * tf * tf && a <= 0.8f * tf + 0.04f; }
    float fh = 0.0f; bool pelvic = false;
    if (dorsal) {
        if (u >= 0.08f && u <= 0.76f) {
            const float dt = (u - 0.08f) / 0.68f;
            const float ramp = saturate((u - 0.08f) / 0.05f) * saturate((0.76f - u) / 0.06f);
            fh = 0.34f * (1.0f - 0.4f * dt) * ramp * (0.9f + 0.1f * sin(u * 150.0f));
        }
    } else if (u >= 0.46f && u <= 0.76f) fh = 0.22f * sin(M_PI_F * (u - 0.46f) / 0.3f);
    else if (u >= 0.16f && u <= 0.28f) { fh = 0.16f * sin(M_PI_F * (u - 0.16f) / 0.12f); pelvic = true; }
    const bool in_body = a <= hw;
    const bool in_fin = !in_body && a <= hw + fh;
    if (!tail && !in_body && !in_fin) return false;
    float3 lo = float3(30, 106, 134), hi = float3(146, 224, 206), fin = float3(44, 130, 160);
    if (yellow) { lo = float3(232, 162, 18); hi = float3(255, 226, 70); fin = float3(250, 200, 40); }
    else if (humbug) { lo = float3(214, 214, 210); hi = float3(250, 250, 246); fin = float3(240, 240, 236); }
    const float k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    if (tail) {
        c = fin;
        if (0.8f * tf + 0.04f - a < 0.06f) c *= 0.45f;
    } else if (in_body) {
        c = mix(lo, hi, k);
        const bool bar = (u > 0.20f && u < 0.26f) || (u > 0.45f && u < 0.52f) || (u > 0.70f && u < 0.75f);
        if (humbug && bar) c = float3(22, 22, 28);
        if (!humbug && !yellow) { const float hl = 1.0f - min(1.0f, fabs(k - 0.3f) * 3.5f); c += float3(12, 26, 20) * hl; }
        if (hw - a < min(0.07f, 0.4f * hw)) c *= 0.72f;
        const float eu = (u - 0.13f) / 0.075f, ev = (sb + 0.16f) / 0.24f;
        const float r2 = eu * eu + ev * ev;
        if (r2 < 1.0f) c = r2 < 0.45f ? float3(12, 12, 18) : float3(176, 206, 206);
        if (u < 0.04f && fabs(sb - 0.06f) < 0.035f) c = float3(70, 36, 34);
    } else {
        c = (pelvic && humbug) ? float3(22, 22, 28) : fin;
        if (hw + fh - a < 0.05f) c *= 0.6f;
    }
    return true;
}

static bool shadeFusilier(float u, float s, float t, thread float3& c) {
    const float sb = s - 0.22f * sin(t) * u * u;
    const float a = fabs(sb);
    const float q = (u - 0.4f) / 0.4f;
    const float ell = sqrt(saturate(1.0f - q * q));
    float hw = 0.0f;
    if (u >= 0.0f && u <= 0.4f) hw = ell; else if (u > 0.4f && u <= 0.8f) hw = 0.12f + 0.88f * ell;
    bool tail = false;
    if (u > 0.8f && u <= 1.0f) {
        const float tf = (u - 0.8f) / 0.2f;
        const float outer = 0.14f + 0.72f * tf;
        const float notch = 0.36f * max(0.0f, tf - 0.2f) / 0.8f;
        if (outer > hw && a > notch) { hw = outer; tail = true; }
    }
    float dors = 0.0f;
    if (sb < 0.0f && u > 0.26f && u < 0.64f) dors = 0.24f * sin(M_PI_F * (u - 0.26f) / 0.38f);
    const float lim = hw + dors;
    if (a > lim) return false;
    const bool fin = dors > 0.0f && a > hw;
    const bool edge = lim - a < 0.07f;
    if (tail) c = float3(255, 204, 34);
    else if (fin) c = float3(255, 222, 80);
    else {
        const float k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
        const float yel_mask = saturate((u - 0.12f) / 0.1f);
        const float yw = max(yel_mask * saturate((0.42f - k) / 0.16f), saturate((u - 0.62f) / 0.12f) * saturate((0.70f - k) / 0.20f));
        const float sw = saturate((k - 0.68f) / 0.16f);
        const float bw = max(0.0f, 1.0f - yw - sw);
        c = float3(yw * 255 + bw * 22 + sw * 222, yw * 205 + bw * 112 + sw * 234, yw * 34 + bw * 235 + sw * 246);
    }
    if (edge) c *= 0.6f;
    if (u < 0.04f && sb < -0.1f && sb > -0.17f) c = float3(40, 22, 20);
    const float eu = (u - 0.13f) / 0.035f, ev = (sb + 0.25f) / 0.25f;
    const float r2 = eu * eu + ev * ev;
    if (r2 < 1.0f) c = r2 < 0.45f ? float3(12, 12, 18) : float3(240, 200, 110);
    return true;
}

static inline bool cudaFin(float u, float a, float hw, float uc, float wd, float fh) {
    const float d = fabs(u - uc);
    if (d >= wd) return false;
    return a <= hw + fh * (1.0f - d / wd);
}

static bool shadeBarracuda(float u, float s, float t, thread float3& c) {
    const float sb = s - 0.2f * sin(t) * u * u * u;
    const float a = fabs(sb);
    float hw = 0.0f; bool tail = false;
    if (u >= 0.0f && u < 0.42f) hw = 0.12f + 0.88f * sin(0.5f * M_PI_F * u / 0.42f);
    else if (u >= 0.42f && u <= 0.86f) { const float x = (u - 0.42f) / 0.44f; hw = 1.0f - 0.76f * x * x; }
    else if (u > 0.86f && u <= 1.0f) {
        const float tf = (u - 0.86f) / 0.14f;
        if (a < 0.45f * tf * tf) return false;
        hw = 0.24f + 0.72f * tf; tail = true;
    }
    if (a > hw) {
        if (sb >= 0.0f) return false;
        if (cudaFin(u, a, hw, 0.46f, 0.10f, 0.38f) || cudaFin(u, a, hw, 0.80f, 0.07f, 0.30f)) { c = float3(124, 128, 108); return true; }
        return false;
    }
    const float q = clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    const float k = 0.5f + 0.5f * q;
    c = mix(float3(44, 58, 72), float3(176, 186, 194), saturate(k * 1.6f));
    c = mix(c, float3(236, 239, 241), saturate((k - 0.7f) * 3.3f));
    if (tail) c = u > 0.96f ? float3(70, 60, 34) : float3(226, 196, 70);
    else if (k < 0.55f && u > 0.2f) {
        const float p = (u - 0.2f) * 27.0f + 0.6f * q;
        if (p - floor(p) < 0.42f) c = mix(c, float3(30, 36, 46), 0.85f * saturate((0.55f - k) * 3.0f));
    }
    if (u > 0.01f && u < 0.10f && sb > 0.05f && sb < 0.11f && fract(u * 60.0f) < 0.5f) c = float3(250, 250, 246);
    if (hw - a < 0.08f) c *= 0.72f;
    const float eu = (u - 0.14f) / 0.04f, ev = (sb + 0.2f) / 0.10f;
    const float r2 = eu * eu + ev * ev;
    if (r2 < 1.0f && r2 >= 0.35f) c = float3(214, 178, 78);
    if (r2 < 0.35f) c = float3(14, 14, 18);
    return true;
}

static inline bool inEll(float u, float s, float cu, float cs, float ru, float rs) {
    const float du = (u - cu) / ru, ds = (s - cs) / rs;
    return du * du + ds * ds < 1.0f;
}

static bool shadeWhitetip(float u, float s, float t, thread float3& c) {
    const float sb = s - 0.30f * sin(t - 3.0f * u) * u * u;
    const float a = fabs(sb);
    float hw = 0.0f;
    if (u >= 0.0f && u <= 0.92f) {
        if (u < 0.20f) { const float q = (0.20f - u) / 0.20f; hw = 0.9f * sqrt(max(0.0f, 1.0f - q * q)); }
        else if (u < 0.40f) hw = 0.9f;
        else if (u < 0.85f) hw = 0.42f + 0.48f * cos((u - 0.40f) / 0.45f * 0.5f * M_PI_F);
        else hw = 0.42f * (0.92f - u) / 0.07f;
    }
    const float kl = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    const float k = kl * kl * (3.0f - 2.0f * kl);
    if (inEll(u, sb, 0.07f, 0.60f, 0.06f, 0.16f)) { c = float3(118, 112, 110); return true; }
    if (inEll(u, sb, 0.12f, -0.22f, 0.035f, 0.09f)) { c = float3(14, 14, 20); return true; }
    c = float3(70 + 156 * k, 66 + 158 * k, 60 + 156 * k);
    if (a <= hw) {
        if (inEll(u, sb, 0.27f, 0.10f, 0.016f, 0.07f) || inEll(u, sb, 0.33f, -0.30f, 0.016f, 0.07f) ||
            inEll(u, sb, 0.62f, 0.25f, 0.016f, 0.07f) || inEll(u, sb, 0.70f, -0.20f, 0.016f, 0.07f)) c = float3(58, 54, 52);
        if (hw > 0.2f && hw - a < 0.06f) c *= 0.62f;
        return true;
    }
    float dh = 0.0f;
    if (u >= 0.40f && u <= 0.64f) dh = u <= 0.50f ? 1.9f * (u - 0.40f) / 0.10f : 1.9f * (0.64f - u) / 0.14f;
    bool fin = false, white = false;
    if (-sb > hw && -sb <= dh) { fin = true; if (-sb > 1.45f) white = true; }
    if (inTri(u, sb, 0.74f, -0.5f, 0.84f, -0.5f, 0.78f, -0.95f)) fin = true;
    if (inTri(u, sb, 0.16f, 0.75f, 0.42f, 0.85f, 0.30f, 1.60f)) fin = true;
    if (inTri(u, sb, 0.72f, 0.45f, 0.84f, 0.45f, 0.80f, 0.95f)) fin = true;
    if (inTri(u, sb, 0.78f, -0.35f, 0.98f, -1.25f, 0.92f, 0.0f)) { fin = true; if (-sb > 0.95f) white = true; }
    if (inTri(u, sb, 0.78f, 0.35f, 0.96f, 0.80f, 0.92f, 0.0f)) { fin = true; if (sb > 0.60f) white = true; }
    if (white) { c = float3(246, 246, 242); return true; }
    if (fin) { c *= 0.9f; return true; }
    return false;
}

static inline bool nurseFin(float u, float v, float lead0, float trail0, float tip, float h) {
    if (v < 0.35f || v > h) return false;
    const float f = (v - 0.35f) / (h - 0.35f);
    return u >= lead0 + (tip - lead0) * f && u <= trail0 + (tip - trail0) * f * f;
}

static bool shadeNurse(float u, float s, float t, thread float3& c) {
    const float sb = s - 0.25f * sin(t) * u * u;
    const float a = fabs(sb);
    const float v = -sb;
    float hw = 0.0f;
    if (u >= 0.0f && u <= 0.80f) {
        const float nose = sqrt(saturate(u / 0.16f));
        const float tp = saturate((u - 0.55f) / 0.25f);
        hw = (1.10f - 0.55f * tp * tp * (3.0f - 2.0f * tp)) * nose;
    } else if (u > 0.80f && u <= 0.97f) hw = 0.55f - 0.43f * saturate((u - 0.80f) / 0.17f);
    const bool body = a <= hw && hw > 0.0f;
    if (u >= -0.025f && u < 0.0f && sb > 0.12f && sb < 0.22f) { c = float3(200, 160, 118); return true; }
    bool upper = false;
    if (u >= 0.76f && u <= 1.0f && v >= 0.0f) {
        const float top = 1.45f * sqrt(saturate((u - 0.76f) / 0.24f));
        upper = v <= top && u <= 0.90f + 0.10f * saturate(v / 1.45f);
    }
    const bool lower = u >= 0.80f && u <= 0.95f && sb >= 0.0f && sb <= 0.30f * (1.0f - (u - 0.80f) / 0.15f);
    const bool fins = nurseFin(u, v, 0.36f, 0.58f, 0.62f, 1.95f) || nurseFin(u, v, 0.62f, 0.76f, 0.79f, 1.90f) ||
                      nurseFin(u, sb, 0.12f, 0.36f, 0.38f, 2.10f) || nurseFin(u, sb, 0.58f, 0.66f, 0.68f, 1.60f) || upper || lower;
    if (!body && !fins) return false;
    const float span = body ? max(hw, 0.05f) : 1.2f;
    const float k = 0.5f + 0.5f * clamp(sb / span, -1.0f, 1.0f);
    c = float3(150 + 76 * k, 102 + 98 * k, 56 + 100 * k);
    if (!body) c *= 0.9f;
    else {
        if (hw - a < 0.08f) c *= 0.7f;
        if (u >= 0.05f && u <= 0.09f && sb >= 0.40f && sb <= 0.46f) c = float3(70, 45, 30);
        const float gu = (u - 0.20f) / 0.032f;
        if (gu >= 0.0f && gu <= 4.5f && fract(gu) < 0.30f && sb > -0.22f && sb < 0.05f) c = float3(60, 40, 28);
        const float eu = (u - 0.11f) / 0.016f, ev = (sb + 0.30f) / 0.07f;
        if (eu * eu + ev * ev < 1.0f) c = float3(14, 12, 12);
    }
    return true;
}

static inline float codHash(float x, float y) { const float v = sin(x * 12.9898f + y * 78.233f) * 43758.5453f; return v - floor(v); }

static bool shadeCod(float u, float s, float t, float seed, thread float3& c) {
    const float sb = s - 0.25f * sin(t) * u * u;
    const float a = fabs(sb);
    float bh;
    if (u < 0.35f) { const float p = u / 0.35f; bh = 0.12f + 0.83f * sin(0.5f * M_PI_F * p) - 0.06f * sin(M_PI_F * p) * (1.0f - p); }
    else { const float q = saturate((u - 0.35f) / 0.45f); bh = 0.95f - 0.5f * q * sqrt(q); }
    const float bv = u < 0.4f ? 0.1f + 0.62f * sin(0.5f * M_PI_F * saturate(u / 0.4f)) : 0.72f - 0.3f * saturate((u - 0.4f) / 0.4f);
    const float fd = (u <= 0.3f || u >= 0.86f) ? 0.0f : 0.34f * sin(M_PI_F * (u - 0.3f) / 0.56f);
    const float fa = (u <= 0.45f || u >= 0.86f) ? 0.0f : 0.26f * sin(M_PI_F * (u - 0.45f) / 0.41f);
    const bool body = u >= 0.0f && u <= 0.8f && sb >= -bh && sb <= bv;
    const bool dorsal = fd > 0.0f && sb <= -bh + 0.02f && sb >= -(bh + fd);
    const bool anal = fa > 0.0f && sb >= bv - 0.02f && sb <= bv + fa;
    const float lat = 0.42f + 3.0f * (u - 0.8f);
    const float back_edge = 1.04f - 0.08f * a * a;
    const bool tail = u >= 0.75f && u <= back_edge && a <= lat;
    const float te = min(back_edge - u, lat - a);
    if (!body && !dorsal && !anal && !tail) return false;
    const float k = saturate((sb + bh) / (bh + bv + 0.001f));
    c = float3(168 + 70 * k, 184 + 52 * k, 166 + 56 * k);
    if (!body) c = c * 0.5f + float3(214, 232, 220) * 0.5f;
    if (u < 0.8f && ((dorsal && fabs(sb + bh) < 0.03f) || (anal && fabs(sb - bv) < 0.03f))) c *= 0.75f;
    {   // round black spots
        const float cu = u / 0.16f, cs = sb / 0.67f;
        const float iu = floor(cu), is = floor(cs);
        const float h1 = codHash(iu + 31.0f * seed, is);
        if (h1 >= 0.45f) {
            const float du = cu - iu - (0.35f + 0.3f * codHash(is + 7.1f, iu + 3.3f + 31.0f * seed));
            const float ds = cs - is - (0.35f + 0.3f * codHash(iu + 1.7f, is + 5.5f + 31.0f * seed));
            const float r = 0.16f + 0.06f * saturate((h1 - 0.45f) / 0.55f);
            if (du * du + ds * ds < r * r) c = float3(34, 30, 30);
        }
    }
    const bool outline = (tail && u > 0.79f) ? te < 0.05f : (u < 0.05f || min(sb + bh + fd, bv + fa - sb) < 0.08f);
    if (outline) c *= 0.6f;
    const float eu = (u - 0.14f) / 0.045f, ev = (sb + 0.2f) / 0.12f;
    const float ed = eu * eu + ev * ev;
    if (ed < 0.6f) c = float3(16, 16, 20); else if (ed < 1.0f) c = float3(222, 196, 110);
    return true;
}

static bool shadeSpecies(int kind, float u, float s, float t, float seed, thread float3& c) {
    switch (kind) {
        case 0: return shadeDamsel(u, s, t, seed, c);
        case 1: return shadeFusilier(u, s, t, c);
        case 2: return shadeBarracuda(u, s, t, c);
        case 3: return shadeClown(u, s, t, c);
        case 4: return shadeParrot(u, s, t, c);
        case 5: return shadeCod(u, s, t, seed, c);
        case 6: return shadeBlacktip(u, s, t, c);
        case 7: return shadeWhitetip(u, s, t, c);
        case 8: return shadeNurse(u, s, t, c);
        default: return shadeTurtle(u, s, t, c);
    }
}

// ------------------------------------------------------------------ motion --

/// Where species s's school gathers in epoch e (40 s each): world x, height,
/// depth ahead of the camera at the epoch's start. Bommie or anemone if the
/// species has one, else a random spot ahead.
static float4 anchorFor(int s, int e, float te, texture2d<float, access::read> st) {
    const float sc = scrollAt(te);
    const float cxe = channelX(sc + 4.0f);
    const uint h = argus_hash(as_type<uint>(e) * 0x9E3779B9u ^ (uint(s) + 1u) * 0x85EBCA6Bu);
    float4 a = float4(cxe + (rnd(h, 0) - 0.5f) * 12.0f, habitatY(SP_HAB[s]), 14.0f + 6.0f * rnd(h, 1), 0.0f);
    const float wz = sc + a.z;
    float best = 1e9f;
    if (SP_ANCHOR[s] == 1) {
        const int icx = int(floor(cxe / BCS)), icz = int(floor(wz / BCS));
        for (int dj = -2; dj <= 2; dj++) for (int di = -2; di <= 2; di++) {
            const Bommie b = bommieCell(icx + di, icz + dj);
            if (!b.ok) continue;
            const float dx = wrapD(b.x - cxe), dz = wrapD(b.z - wz);
            const float score = fabs(dz) + 0.5f * fabs(dx);
            if (fabs(dx) < 9.0f && fabs(dz) < 5.0f && score < best) {
                best = score;
                a.x = cxe + dx;
                a.z = max(8.0f, a.z + dz);
                a.y = hBilinear(st, b.x, b.z) + 0.4f + 2.0f * SP_LEN[s];
            }
        }
    } else if (SP_ANCHOR[s] == 2) {
        for (int i = CORAL_ANEM0; i < CORAL_CLAM0; i++) {
            const float4 d0 = st.read(uint2(CORAL_COL0 + uint(i), BLK_ROW0));
            const float dx = wrapD(d0.x - cxe), dz = wrapD(d0.y - wz);
            const float score = fabs(dz) + 0.5f * fabs(dx);
            if (fabs(dx) < 7.0f && fabs(dz) < 8.0f && score < best) {
                best = score;
                a.x = cxe + dx;
                a.z = max(6.0f, a.z + dz);
                a.y = d0.z + 0.25f;
            }
        }
    }
    return a;
}

/// Camera-relative position of fish i at time t (closed form).
static float3 fishRel(int s, float t, float tau, float4 an, float4 ao, float seed, uint fh, float L, float v) {
    const float camx = camxAt(t);
    if (SP_SCHOOL[s] != 0) {
        // Each fish circles the school's anchor on its own phase, plus a fixed
        // place in the cloud and a slow wobble (the Zig's boids, in closed form).
        const float R = 0.6f + 2.0f * L;
        const float3 orb = float3(R * sin(ph(t, 0.21f) + seed * 6.0f), 0.4f * sin(ph(t, 0.13f) + float(s)), R * cos(ph(t, 0.17f) + seed * 6.0f));
        float3 sp = (float3(rnd(fh, 3), rnd(fh, 4), rnd(fh, 5)) - 0.5f) * float3(1.4f * R, 0.6f * R + 0.3f, 1.4f * R);
        sp += 0.25f * R * float3(sin(ph(t, 0.37f + 0.2f * rnd(fh, 6)) + TWO_PI * rnd(fh, 7)),
                                  0.5f * sin(ph(t, 0.29f) + TWO_PI * rnd(fh, 8)),
                                  sin(ph(t, 0.31f + 0.2f * rnd(fh, 9)) + TWO_PI * rnd(fh, 10)));
        const float3 pn = float3(an.x - camx, an.y, an.z - CAM_SPEED * tau) + orb + sp;
        const float3 po = float3(ao.x - camx, ao.y, ao.z - CAM_SPEED * (tau + 40.0f)) + orb + sp;
        // After the anchor moves on, the school swims to the new one; fish the
        // camera has passed rejoin it out in the haze.
        const float D = length(float3(an.x - ao.x, an.y - ao.y, an.z - ao.z + CAM_SPEED * 40.0f));
        const float vmax = max(2.4f * v, 0.6f);
        const float lam = saturate((tau - 1.5f * seed) * vmax / max(D, 0.1f));
        float3 p = mix(po, pn, lam);
        if (lam < 1.0f && p.z < 0.7f) p = pn;
        return p;
    }
    // Loners wander around a station that drifts along with the diver.
    const float key = float(s) * 1.7f + seed * 37.0f;
    const float lane = fract(key * 0.618f);
    const float tz = 4.0f + 14.0f * lane + 3.0f * sin(ph(t, 0.03f) + key * 1.3f);
    const float tx = 0.45f * tz * sin(ph(t, 0.025f + 0.02f * seed) + key * 1.9f);
    const float ty = habitatY(SP_HAB[s]) + 0.5f * sin(ph(t, 0.07f) + key * 2.3f);
    // Around it, a wide loop swum faster than the diver drifts, so they pass
    // across the view (the Zig's steering overshoots its target the same way).
    const float rho = 0.8f + 1.0f * L;
    const float om = max(1.2f * v, 0.6f) / (1.6f * rho);
    const float a = (seed < 0.5f ? 1.0f : -1.0f) * ph(t, om) + seed * TWO_PI;
    return float3(tx + 2.2f * rho * sin(a), ty, tz + 0.8f * rho * cos(a));
}

// Per-frame animal and mote positions, computed once per frame in argus_step and
// stored (screen space, split into whole and fractional parts so RGBA16F keeps
// sub-pixel precision) in rows the reef does not use.
constant uint FISH_ROW = 2052;   // 2052..2055: fish i at column 32 + i
constant uint SNOW_ROW = 2056;   // mote i at column 32 + i
constant uint CORAL_ROW = 2057;  // 2057..2058: coral i this frame (screen circle, camera-relative place)

static inline float2 splitf(float v) { const float i = floor(v); return float2(i, v - i); }

static void fishStep(int i, Scene S, texture2d<float, access::read> prev, texture2d<float, access::write> next) {
    const uint col = CORAL_COL0 + uint(i);
    next.write(float4(0.0f), uint2(col, FISH_ROW + 3u));   // invalid until proven otherwise
    int s = 0;
    for (int k = 1; k < N_SPECIES; k++) if (i >= SP_START[k]) s = k;
    const uint fh = argus_hash(uint(i) * 0x27D4EB2Du ^ 0x51F1u);
    const float seed = rnd(fh, 0);
    const float L = SP_LEN[s];
    const float size = L * (0.85f + 0.3f * rnd(fh, 1));
    const float v = SP_SPEED[s] * L;
    const bool school = SP_SCHOOL[s] != 0;
    float4 an = float4(0.0f), ao = float4(0.0f);
    float tau = 0.0f;
    if (school) {
        // The school's anchor this epoch and the last (40 s epochs, per-species offset).
        const float hs = rnd(argus_hash(uint(s) + 0xA11u), 0);
        const float ts = S.t + 40.0f * hs;
        const float e = floor(ts / 40.0f);
        tau = ts - 40.0f * e;
        an = anchorFor(s, int(e), S.t - tau, prev);
        ao = anchorFor(s, int(e) - 1, S.t - tau - 40.0f, prev);
    }
    float3 p = fishRel(s, S.t, tau, an, ao, seed, fh, L, v);
    const float dts = (!school || tau > 0.2f) ? -0.1f : 0.1f;
    const float3 p2 = fishRel(s, S.t + dts, tau + dts, an, ao, seed, fh, L, v);
    float3 vel = (p2 - p) / dts;
    vel.z += CAM_SPEED;   // reef fish hold station in the world while the diver drifts on
    if (SP_DUSK[s] != 0) p.z = mix(42.0f, p.z, sstep(0.2f, 0.35f, max(S.gold, S.dim)));   // in the haze until the light changes
    if (SP_SCHOOL[s] == 0) p.z = max(p.z, 2.0f + 1.5f * L);   // loners keep a little distance
    if (p.z < Z_NEAR + 0.25f || p.z > Z_FAR) return;
    // Keep clear of the reef below.
    const float X = p.x + S.camx, Zw = S.scroll + p.z;
    float g = hBilinear(prev, X, Zw);
    g = max(g, max(hBilinear(prev, X + 0.6f, Zw), hBilinear(prev, X - 0.6f, Zw)));
    g = max(g, max(hBilinear(prev, X, Zw + 0.6f), hBilinear(prev, X, Zw - 0.6f)));
    if (SP_HAB[s] == 0) p.y = max(p.y, g + 0.3f + 0.5f * seed);
    p.y = min(max(p.y, g + 0.15f + size * SP_HD[s]), SURFACE_Y - 1.0f);
    // Body axis: fish pitch only a little even when climbing.
    const float hsp = length(vel.xz);
    const float pv = clamp(0.3f * vel.y, -0.4f * hsp, 0.4f * hsp);
    float3 dir = float3(vel.x, pv, vel.z);
    const float dl = length(dir);
    dir = dl > 1e-4f ? dir / dl : float3(1.0f, 0.0f, 0.0f);
    const float half_ = 0.5f * size;
    const float ry = p.y - S.camy;
    float2 hd, tl;
    if (!project(S, p.x + dir.x * half_, ry + dir.y * half_, p.z + dir.z * half_, hd)) return;
    if (!project(S, p.x - dir.x * half_, ry - dir.y * half_, p.z - dir.z * half_, tl)) return;
    const float W = S.focal * size * SP_HD[s] / p.z;
    if (W < 0.4f) return;
    float2 ax = tl - hd;
    float Lp = length(ax);
    if (Lp < 1e-3f) { ax = float2(1.0f, 0.0f); Lp = 1.0f; } else ax /= Lp;
    const float min_l = 2.2f * W;   // seen nose-on it still reads as an animal
    if (Lp < min_l) { const float2 m = 0.5f * (hd + tl); Lp = min_l; hd = m - ax * 0.5f * Lp; }
    hd = clamp(hd, -4000.0f, 6000.0f);
    const float wag = rnd(fh, 2) * TWO_PI + ph(S.t, 4.0f + 1.25f * SP_SPEED[s] * L / size);
    next.write(float4(splitf(hd.x), splitf(hd.y)), uint2(col, FISH_ROW));
    next.write(float4(ax, splitf(min(Lp, 4000.0f))), uint2(col, FISH_ROW + 1u));
    next.write(float4(min(W, 4000.0f), wag, p.z, 0.0f), uint2(col, FISH_ROW + 2u));
    next.write(float4(seed, float(s), 1.0f, 0.0f), uint2(col, FISH_ROW + 3u));
}

static void coralStep(int i, Scene S, texture2d<float, access::read> prev, texture2d<float, access::write> next) {
    const uint col = CORAL_COL0 + uint(i);
    next.write(float4(0.0f), uint2(col, CORAL_ROW));
    const float4 d1 = prev.read(uint2(col, BLK_ROW0 + 1u));
    if (d1.w < 0.5f) return;
    const float4 d0 = prev.read(uint2(col, BLK_ROW0));
    const float rz = wrap64(d0.y - S.scroll);
    if (rz < Z_NEAR + 0.3f || rz > Z_FAR) return;
    const float rx = wrapD(d0.x - S.camx);
    if (fabs(rx) > rz * 0.5f * S.w / S.focal + 1.5f) return;
    const float ry = d0.z - S.camy;
    const float size = d0.w;
    const int kind = int(d1.y + 0.5f);
    // A screen circle around everything the coral can draw.
    float cy = 0.0f, rad = 0.0f;
    if (kind == 1) { cy = 0.5f * size; rad = 1.35f * size; }                          // branches reach ~1.3 x size
    else if (kind == 3) { cy = 0.4f * size; rad = 0.95f * size + 0.25f; }             // tentacles + surge
    else if (kind == 4) { const float sh = 0.25f + 0.3f * size; cy = sh; rad = size + sh + 0.05f; }
    else { cy = 0.3f * size; rad = 1.05f * size; }
    float2 cc;
    if (!project(S, rx, ry + cy, rz, cc)) return;
    rad = rad * S.focal / rz + 3.0f;
    float4 rect = float4(cc - rad, cc + rad);
    if (kind == 1) {
        // Staghorn: the screen box of its actual branches.
        float4 r2 = float4(1e9f, 1e9f, -1e9f, -1e9f);
        bool ok = true;
        const float k = S.focal / rz;
        auto visit = [&](float3 p, float3 e, float th, int dep) {
            float2 a2, b2;
            if (!project(S, rx + p.x, ry + p.y, rz + p.z, a2) || !project(S, rx + e.x, ry + e.y, rz + e.z, b2)) { ok = false; return true; }
            const float pad = 0.5f * floor(clamp(th * k, 1.0f, 40.0f)) + 1.0f;
            r2.xy = min(r2.xy, min(a2, b2) - pad);
            r2.zw = max(r2.zw, max(a2, b2) + pad);
            return false;
        };
        stagGrow(stagSeed(uint(i)), size, visit);
        if (ok) rect = r2;
    }
    if (rect.z < 0.0f || rect.x > S.w || rect.w < 0.0f || rect.y > S.h) return;
    next.write(clamp(rect, -4000.0f, 6000.0f), uint2(col, CORAL_ROW));
    next.write(float4(rx, ry, rz, size), uint2(col, CORAL_ROW + 1u));
}

static void snowStep(int i, Scene S, texture2d<float, access::write> next) {
    // Marine snow: suspended sediment drifting past, falling slowly.
    const uint h = argus_hash(uint(i) * 0x9E3779B1u ^ 0x5A0Bu);
    const float z = 0.6f + 14.0f * fract(rnd(h, 2) - CAM_SPEED * S.t / 14.0f);
    const float y = -1.0f + (SURFACE_Y + 1.0f) * fract(rnd(h, 1) - 0.08f * S.t / (SURFACE_Y + 1.0f));
    const float x = (2.0f * rnd(h, 0) - 1.0f) * (0.6f * z + 1.0f) * 0.9f - 0.267f * cos(ph(S.t, 0.3f) + rnd(h, 3) * TWO_PI);
    float4 o = float4(0.0f);
    float2 q;
    if (project(S, x, y - S.camy, z, q) && q.x >= 1.0f && q.y >= 1.0f && q.x < S.w - 1.0f && q.y < S.h - 1.0f) {
        o = float4(floor(q), floor(64.0f * exp(-0.14f * z) + 4.0f), z < 6.0f ? 1.0f : 0.0f);
    }
    next.write(o, uint2(CORAL_COL0 + uint(i), SNOW_ROW));
}

kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    if (gid.x >= CORAL_COL0 && gid.y >= FISH_ROW && gid.y <= CORAL_ROW + 1u) {
        const int i = int(gid.x - CORAL_COL0);
        if (gid.y == FISH_ROW && i < NUM_FISH) fishStep(i, makeScene(f), prev, next);
        else if (gid.y == SNOW_ROW && i < NUM_SNOW) snowStep(i, makeScene(f), next);
        else if (gid.y == CORAL_ROW && i < NUM_CORAL) coralStep(i, makeScene(f), prev, next);
        return;
    }
    // The reef is static: build it over the first three frames, then leave it.
    if (f.frame > 2u) return;
    if (f.frame == 0u) {
        if (gid.y >= BLK_ROW0) { next.write(prev.read(gid), gid); return; }
        // Light it: Lambert from above, cavities darker, reds absorbed.
        const int iu = int(gid.x), iv = int((gid.y + uint(MAP_N) - 1u) % uint(MAP_N));
        const float hc = hRead(prev, iu, iv);
        const float gx = (hRead(prev, iu + 1, iv) - hRead(prev, iu - 1, iv)) * TEX * 0.5f;
        const float gz = (hRead(prev, iu, iv + 1) - hRead(prev, iu, iv - 1)) * TEX * 0.5f;
        const float inv = rsqrt(gx * gx + gz * gz + 1.0f);
        const float lam = max(0.0f, (-gx * 0.30f + 0.88f + gz * 0.36f) * inv);
        const float around = 0.25f * (hRead(prev, iu + 6, iv) + hRead(prev, iu - 6, iv) + hRead(prev, iu, iv + 6) + hRead(prev, iu, iv - 6));
        const float cavity = clamp(1.0f + 1.6f * (hc - around), 0.55f, 1.15f);
        float lit = (0.42f + 0.80f * lam) * cavity * (0.92f + 0.03f * hc);
        const float4 a = prev.read(gid);
        // Seagrass (green albedo): the blades are one-texel spikes, so their slopes
        // would light as hard bright and dark facets that shimmer as the diver
        // drifts. Light the meadow almost flat instead, as a soft canopy is.
        if (a.g > a.r + 0.02f && a.g > a.b * 1.4f) lit = mix(lit, 0.98f, 0.8f);
        next.write(float4(saturate(a.rgb * lit * float3(0.84f, 1.0f, 1.02f)), a.a), gid);
        return;
    }
    if (f.frame == 1u && gid.y >= BLK_ROW0) {
        if (gid.x < uint(BLK_N)) {
            // Tallest point in each block, one texel of margin for bilinear taps.
            const int bx = int(gid.x) * BLK_T, bz = int(gid.y - BLK_ROW0) * BLK_T;
            float m = -1.0e9f;
            for (int v = -1; v <= BLK_T; v++)
                for (int u = -1; u <= BLK_T; u++) m = max(m, hRead(prev, bx + u, bz + v));
            next.write(float4(m), gid);
            return;
        }
        const int i = int(gid.x - CORAL_COL0);
        if (i < NUM_CORAL && gid.y <= BLK_ROW0 + 1u) {
            float4 extra;
            float4 p = coralPlace(i, extra);
            p.z = hBilinear(prev, p.x, p.y) - 0.02f;
            next.write(gid.y == BLK_ROW0 ? p : extra, gid);
            return;
        }
    }
    next.write(prev.read(gid), gid);
}

// ------------------------------------------------------------- the drawing --

constant uint FCAP = 128;
constant uint CCAP = 64;
constant uint SCAP = 96;

/// Staghorn Acropora: regrows the Zig's random branching (<= 40 segments) and
/// tests the pixel against each segment's thick projected line.
static bool stagHit(float2 pp, Scene S, float rx, float ry, float rz, float size, uint seed, int style, thread float3& col) {
    const float k = S.focal / rz;
    int hit = -1;
    auto visit = [&](float3 p, float3 e, float th, int dep) {
        float2 a2, b2;
        if (project(S, rx + p.x, ry + p.y, rz + p.z, a2) && project(S, rx + e.x, ry + e.y, rz + e.z, b2) && onLine(pp, a2, b2, th * k)) {
            hit = dep;
            return true;
        }
        return false;
    };
    stagGrow(seed, size, visit);
    if (hit < 0) return false;
    const float t = float(hit) / 4.0f;
    col = fogged(mix(STAG_BASE[style], STAG_TIP[style], t * t), rz);
    return true;
}

static bool anemHit(float2 pp, Scene S, float rx, float ry, float rz, float size, float cph, int style, thread float3& col) {
    const float k = S.focal / rz;
    float2 b2, t2;
    if (project(S, rx, ry, rz, b2) && project(S, rx, ry + 0.2f * size, rz, t2) && onLine(pp, b2, t2, 0.45f * size * k)) {
        col = fogged(ANEM_COLUMN[style], rz);
        return true;
    }
    const float phs = ph(S.t, 0.8f) + cph;
    const float surge = 0.12f * sin(ph(S.t, 0.35f) + cph);
    const float thick = 0.085f * size * k;
    for (int ti = 0; ti < 22; ti++) {
        const float a = TWO_PI * (float(ti) + 0.5f) / 22.0f;
        const float ca = cos(a), sa = sin(a);
        float2 prev; bool have = false;
        for (int j = 0; j < 5; j++) {
            const float kf = float(j) / 4.0f;
            const float o = size * (0.25f + 0.55f * kf);
            const float up = size * (0.15f + 0.75f * kf - 0.35f * kf * kf);
            const float wav = kf * (0.10f * sin(phs + a * 2.0f - kf * 3.0f) + surge);
            float2 q;
            if (!project(S, rx + ca * o + wav, ry + up, rz + sa * o, q)) { have = false; continue; }
            if (have && onLine(pp, prev, q, thick * (1.0f - 0.4f * kf))) {
                col = fogged(mix(ANEM_BASE[style], ANEM_TIP[style], kf * kf), rz);
                return true;
            }
            prev = q; have = true;
        }
    }
    return false;
}

static bool tableHit(float2 pp, Scene S, float rx, float ry, float rz, float size, float cph, int style, thread float3& col) {
    const float stalk_h = 0.25f + 0.3f * size;
    float2 b2, p2;
    if (!project(S, rx, ry, rz, b2) || !project(S, rx, ry + stalk_h, rz, p2)) return false;
    const float k = S.focal / rz;
    const float3 c = TABLE_COLS[style];
    if (onLine(pp, b2, p2, 0.12f * k)) { col = fogged(c * 0.6f, rz); return true; }
    const float elev = clamp(-(ry + stalk_h) * rsqrt(rz * rz + (ry + stalk_h) * (ry + stalk_h)), -1.0f, 1.0f);
    const float ax = size * k, ay = ax * max(0.1f, fabs(elev));
    if (ax < 0.5f || ay < 0.3f) return false;
    // The plate's edge thickness first (it wins where they overlap, as in the Zig), then the plate.
    for (int pass = 0; pass < 2; pass++) {
        const float2 cc = pass == 0 ? p2 + float2(0.0f, 0.035f * k) : p2;
        const float nx = (pp.x - cc.x) / ax, ny = (pp.y - cc.y) / ay;
        const float r2 = nx * nx + ny * ny;
        if (r2 > 1.0f) continue;
        const bool above = pass == 1 && elev > 0.0f;
        const float3 base = pass == 0 ? c * 0.5f : c;
        const float rib = 0.9f + 0.1f * sin(atan2(ny, nx) * 26.0f + cph);
        const float rim = r2 > 0.82f ? 1.25f : 1.0f;
        const float lv = above ? rib * rim : 0.45f * rim;
        col = fogged(min(base * lv, 255.0f), rz);
        return true;
    }
    return false;
}

static bool clamHit(float2 pp, Scene S, float rx, float ry, float rz, float size, float cph, int style, thread float3& col) {
    float2 cc;
    if (!project(S, rx, ry + 0.3f * size, rz, cc)) return false;
    const float k = S.focal / rz;
    const float len = size * k;
    if (len < 1.0f) return false;
    const float elev = clamp(-ry * rsqrt(rz * rz + ry * ry), -1.0f, 1.0f);
    const float open = 0.65f + 0.35f * sin(ph(S.t, 0.09f) + cph);
    const float ax = len, ay = len * (0.25f + 0.35f * fabs(elev)) * (0.6f + 0.4f * open);
    if (ay < 0.3f) return false;
    const float nx = (pp.x - cc.x) / ax, ny = (pp.y - cc.y) / ay;
    const float r = sqrt(nx * nx + ny * ny);
    if (r > 1.0f) return false;
    const bool gigas = style == 4;
    const float phc = cph * 3.0f;
    const float wave = 0.06f * sin(atan2(ny, nx) * (gigas ? 7.0f : 11.0f) + phc);
    float3 c3;
    if (r > 0.84f + wave) c3 = gigas ? float3(196, 190, 170) : float3(120, 116, 100);   // fluted shell lip
    else if (fabs(ny) < 0.07f * open && fabs(nx) < 0.6f) c3 = float3(20, 24, 30);       // inhalant slit
    else {
        const float spot = sin(nx * 23.0f + phc) * sin(ny * 19.0f - phc);
        const float glow = spot > 0.55f ? 1.45f : 1.0f;
        const float edge = r > 0.7f ? 1.25f : 1.0f;
        c3 = min(MANTLE_COLS[style] * glow * edge, 255.0f);
    }
    col = fogged(c3, rz);
    return true;
}

/// The Zig's depth slices form one lattice for the whole frame: 12 mm steps
/// near the camera, then 1.7% of depth. A ray resuming after a skipped block
/// snaps back onto it, so neighbouring pixels sample the same depths.
constant float Z_LIN = 0.012f / 0.017f;
static inline float snapSlice(float z) {
    if (z <= Z_LIN) return Z_NEAR + 0.012f * ceil((z - Z_NEAR) / 0.012f);
    const float lg = log2(1.0f + Z_GROW);
    return Z_LIN * exp2(ceil(log2(z / Z_LIN) / lg) * lg);
}

/// Marches the pixel's ray over the baked heightfield at the Zig's slice spacing.
static bool marchReef(texture2d<float> st, Scene S, float rk, float ry, thread float& zhit, thread float3& col) {
    float zend = Z_FAR;
    if (ry > 1e-5f) zend = min(zend, (H_BOUND - S.camy) / ry);
    float z = Z_NEAR, zp = Z_NEAR;
    float4 sm = float4(0.0f);
    bool hit = false;
    int it = 0;
    while (z < zend && it < 480) {
        it++;
        const float X = S.camx + rk * z, Zw = S.scroll + z;
        const float bxf = floor(X / BLK_M), bzf = floor(Zw / BLK_M);
        float zx = 1e9f;
        if (rk > 1e-6f) zx = ((bxf + 1.0f) * BLK_M - S.camx) / rk;
        else if (rk < -1e-6f) zx = (bxf * BLK_M - S.camx) / rk;
        const float zexit = min(min(zx, (bzf + 1.0f) * BLK_M - S.scroll), zend);
        const float bm = st.read(uint2(uint(int(bxf) & (BLK_N - 1)), BLK_ROW0 + uint(int(bzf) & (BLK_N - 1)))).a;
        if (S.camy + ry * (ry < 0.0f ? zexit : z) > bm) {   // the ray clears this whole block
            zp = zexit;
            z = snapSlice(zexit + 1e-4f);
            continue;
        }
        while (z < zexit + 1e-4f && it < 480) {
            it++;
            sm = reefAt(st, S.camx + rk * z, S.scroll + z);
            if (S.camy + ry * z < sm.a) { hit = true; break; }
            zp = z;
            z = z < Z_LIN ? z + 0.012f : z * (1.0f + Z_GROW);
        }
        if (hit) break;
    }
    if (!hit) return false;
    const float d = sm.a - (S.camy + ry * z);   // how far below the column's top the ray hits
    if (d < 0.135f && zp < z) {
        // Ground seen at a slant: find the crossing between the last two samples.
        const float4 s0 = reefAt(st, S.camx + rk * zp, S.scroll + zp);
        const float f0 = S.camy + ry * zp - s0.a, f1 = S.camy + ry * z - sm.a;
        if (f0 > 0.0f) {
            const float zh = zp + (z - zp) * f0 / max(f0 - f1, 1e-6f);
            sm = reefAt(st, S.camx + rk * zh, S.scroll + zh);
            z = zh;
        }
    }
    float3 c = sm.rgb;
    // Caustics: a moving net of light from the surface, fading with depth.
    const float wx = S.camx + rk * z, wz = S.scroll + z;
    const float caus_z = sin(wz * 22.0f * KK - ph(S.t, 0.5f));
    const float caus = max(0.0f, sin(wx * 26.0f * KK + ph(S.t, 0.7f) + 0.6f * caus_z) * caus_z);
    c = min(c * ((220.0f + 120.0f * caus * caus * max(0.0f, 1.0f - z / 40.0f)) / 256.0f), 1.0f);
    c = mix(c, WATER_HOR, 1.0f - exp(-FOG_K * z));
    // A wall (bommie side, sponge, ledge) tints toward the water below its top.
    if (d >= 0.135f) c = mix(c, WATER_HOR, min(150.0f, 222.2f * (d - 0.135f)) / 256.0f);
    zhit = z;
    col = c;
    return true;
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> st [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]],
                       uint2 tpos [[thread_position_in_threadgroup]],
                       uint2 tsize [[threads_per_threadgroup]],
                       uint tidx [[thread_index_in_threadgroup]]) {
    threadgroup float4 fA[FCAP];
    threadgroup float4 fB[FCAP];
    threadgroup float2 fC[FCAP];
    threadgroup float4 cA[CCAP];
    threadgroup float4 cB[CCAP];
    threadgroup float4 cC[CCAP];
    threadgroup float  cZ[CCAP];
    threadgroup float4 sA[SCAP];
    threadgroup atomic_uint nF, nC, nS;

    const Scene S = makeScene(f);
    const uint nthreads = tsize.x * tsize.y;
    const float2 tlo = float2(gid - tpos);
    const float2 thi = tlo + float2(tsize);

    if (tidx == 0) {
        atomic_store_explicit(&nF, 0u, memory_order_relaxed);
        atomic_store_explicit(&nC, 0u, memory_order_relaxed);
        atomic_store_explicit(&nS, 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // ---- cull: each thread places a few animals, corals and motes, keeps those on this tile ----
    for (uint i = tidx; i < uint(NUM_FISH); i += nthreads) {
        const float4 t3 = st.read(uint2(CORAL_COL0 + i, FISH_ROW + 3u));
        if (t3.z < 0.5f) continue;
        const float4 t0 = st.read(uint2(CORAL_COL0 + i, FISH_ROW));
        const float4 t1 = st.read(uint2(CORAL_COL0 + i, FISH_ROW + 1u));
        const float4 t2 = st.read(uint2(CORAL_COL0 + i, FISH_ROW + 2u));
        const float2 hd = float2(t0.x + t0.y, t0.z + t0.w);
        const float Lp = t1.z + t1.w;
        const float2 tl = hd + t1.xy * Lp;
        const int kind = int(t3.y + 0.5f);
        const float pad = SP_EXT[kind] * t2.x + 2.0f;
        const float2 lo = min(hd, tl) - pad, hi = max(hd, tl) + pad;
        if ((hi.x - lo.x) * (hi.y - lo.y) > 1100.0f * 1100.0f) continue;
        if (hi.x < tlo.x || lo.x > thi.x || hi.y < tlo.y || lo.y > thi.y) continue;
        const uint slot = atomic_fetch_add_explicit(&nF, 1u, memory_order_relaxed);
        if (slot >= FCAP) continue;
        const float belly = t1.x >= 0.0f ? 1.0f : -1.0f;
        fA[slot] = float4(hd, t1.xy);
        fB[slot] = float4(1.0f / Lp, belly / max(t2.x, 1e-3f), t2.y, t2.z);
        fC[slot] = t3.xy;
    }
    for (uint i = tidx; i < uint(NUM_CORAL); i += nthreads) {
        const float4 cc = st.read(uint2(CORAL_COL0 + i, CORAL_ROW));   // screen rect
        if (cc.z <= cc.x) continue;
        if (cc.z < tlo.x || cc.x > thi.x || cc.w < tlo.y || cc.y > thi.y) continue;
        const uint slot = atomic_fetch_add_explicit(&nC, 1u, memory_order_relaxed);
        if (slot >= CCAP) continue;
        cA[slot] = st.read(uint2(CORAL_COL0 + i, CORAL_ROW + 1u));
        const float4 d1 = st.read(uint2(CORAL_COL0 + i, BLK_ROW0 + 1u));
        cB[slot] = float4(d1.x, d1.y, d1.z, float(i));
        const float4 ca = cA[slot];
        const int kind = int(d1.y + 0.5f);
        cC[slot] = cc;
        cZ[slot] = kind == 4 ? ca.z - 0.2f * ca.w : (kind == 5 ? ca.z - 0.05f : ca.z);
    }
    for (uint i = tidx; i < uint(NUM_SNOW); i += nthreads) {
        const float4 m = st.read(uint2(CORAL_COL0 + i, SNOW_ROW));
        if (m.z <= 0.0f) continue;
        if (m.x + 1.0f < tlo.x || m.x >= thi.x || m.y + 1.0f < tlo.y || m.y >= thi.y) continue;
        const uint slot = atomic_fetch_add_explicit(&nS, 1u, memory_order_relaxed);
        if (slot >= SCAP) continue;
        sA[slot] = m;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (gid.x >= f.width || gid.y >= f.height) return;

    // ---- this pixel ----
    const float2 pp = float2(gid) + 0.5f;
    const float rk = (pp.x - 0.5f * S.w) / S.focal;
    const float ry = (S.hor - pp.y) / S.focal;
    float bestZ = 1e9f;
    float3 col = float3(0.0f);
    bool drawn = marchReef(st, S, rk, ry, bestZ, col);

    const uint nc = min(atomic_load_explicit(&nC, memory_order_relaxed), CCAP);
    for (uint j = 0; j < nc; j++) {
        if (cZ[j] >= bestZ) continue;
        const float4 cc = cC[j];
        if (pp.x < cc.x || pp.x > cc.z || pp.y < cc.y || pp.y > cc.w) continue;
        const float4 a = cA[j], b = cB[j];
        const int kind = int(b.y + 0.5f), style = int(b.z + 0.5f);
        float3 c;
        bool h = false;
        if (kind == 1) h = stagHit(pp, S, a.x, a.y, a.z, a.w, stagSeed(uint(b.w)), style, c);
        else if (kind == 3) h = anemHit(pp, S, a.x, a.y, a.z, a.w, b.x, style, c);
        else if (kind == 4) h = tableHit(pp, S, a.x, a.y, a.z, a.w, b.x, style, c);
        else h = clamHit(pp, S, a.x, a.y, a.z, a.w, b.x, style, c);
        if (h) { bestZ = cZ[j]; col = c; drawn = true; }
    }
    const uint nf = min(atomic_load_explicit(&nF, memory_order_relaxed), FCAP);
    for (uint j = 0; j < nf; j++) {
        const float4 b = fB[j];
        if (b.w >= bestZ) continue;
        const float4 a = fA[j];
        const float2 c2 = fC[j];
        const int kind = int(c2.y + 0.5f);
        const float2 dp = pp - a.xy;
        const float u = (dp.x * a.z + dp.y * a.w) * b.x;
        const float s = (dp.y * a.z - dp.x * a.w) * b.y;
        if (u < -0.05f || u > 1.05f || fabs(s) > SP_EXT[kind]) continue;
        float3 c;
        if (shadeSpecies(kind, u, s, b.z, c2.x, c)) { bestZ = b.w; col = fogged(c, b.w); drawn = true; }
    }

    // ---- water, light shafts, the sun's colour ----
    const float ny = floor(pp.y) / S.h;
    const float3 top = float3(74, 138, 146) / 255.0f, bot = float3(18, 54, 62) / 255.0f;
    const float3 bg = ny < HORIZON ? mix(top, WATER_HOR, pow(max(ny / HORIZON, 1e-6f), 0.8f))
                                   : mix(WATER_HOR, bot, pow(max((ny - HORIZON) / (1.0f - HORIZON), 1e-6f), 0.7f));
    float gain = 110.0f * exp(-2.0f * ny) * (1.0f - sstep(0.6f, 1.0f, ny)) / 256.0f;
    if (drawn) gain *= 0.5f; else col = bg;
    const float sc = 1200.0f / S.h;   // ray pattern in 1200-line pixels
    const float ru = floor(pp.x * sc) + floor(floor(pp.y * sc) * 26.0f / 64.0f);
    const float b1 = 0.5f + 0.5f * sin(ru * 0.0062f + ph(S.t, 0.13f));
    const float b2 = 0.5f + 0.5f * sin(ru * 0.0147f - ph(S.t, 0.21f) + 1.7f);
    const float b3 = 0.5f + 0.5f * sin(ru * 0.0310f + ph(S.t, 0.47f) + 0.4f);
    float rv = b1 * b2 * (0.55f + 0.45f * b3);
    rv = min(1.0f, rv * rv * 1.7f);
    // Shaft colour: pale cyan at noon, warm gold at sunset and sunrise.
    const float3 ray_col = float3(110.0f + 140.0f * S.gold, 190.0f - 20.0f * S.gold, 200.0f - 110.0f * S.gold) / 256.0f;
    col += rv * gain * ray_col;
    // Under water the sunset is mostly a dimming; dusk sinks to a deep blue.
    const float3 tint = float3(1.0f - 0.18f * S.gold - 0.62f * S.dim, 1.0f - 0.20f * S.gold - 0.52f * S.dim, 1.0f - 0.10f * S.gold - 0.34f * S.dim);
    col = min(col * tint, 1.0f);

    // ---- marine snow drifts in front ----
    const uint ns = min(atomic_load_explicit(&nS, memory_order_relaxed), SCAP);
    const float2 pi = floor(pp);
    for (uint j = 0; j < ns; j++) {
        const float4 m = sA[j];
        const float2 d = pi - m.xy;
        const float ext = m.w > 0.5f ? 1.0f : 0.0f;
        if (d.x >= 0.0f && d.y >= 0.0f && d.x <= ext && d.y <= ext) {
            const float lum = m.z;
            col += float3(floor(lum * 0.5f), floor(lum * 0.75f), lum) / 255.0f;
        }
    }
    out.write(float4(saturate(col), 1.0f), gid);
}

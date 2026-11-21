// ============================================================================
// LIZARD ISLAND // themes/Lizard_Island.metal
// WGSL translation of themes/Lizard_Island.metal (web/themes/Lizard_Island.wgsl), one to one.
// Metal port by Claude Opus (Anthropic), 2026-10-15, of an earlier Zig version
// (Claude Opus; species by Claude Haiku agents). Same lagoon, same species,
// same light cycle, run entirely on the GPU.
//
// A diver's drift over the lagoon at Lizard Island, northern Great Barrier
// Reef, built from field sources rather than imagination. Real scale: one
// world unit is one metre.
//
// What the sources say, and how it shows here. [cited] = page read,
// [snippet] = search result only, [atlas] = habitat dataset rows (York 2020,
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
//     [snippet]. Lizard's lagoon meadows are dominated by Halophila; Halodule
//     and Thalassia were sampled only in the 0-3 m shallows [cited: York,
//     Macreadie & Rasheed 2018, Biol. Lett. 14:20180529]. Here: sparse
//     Halophila (paired oval leaves on short stalks) on the open lagoon sand,
//     and dense swaying strap meadows (Thalassia, Halodule) in sheltered patches
//     and the shallows by the fringing reef: the sheltered southern lagoon
//     meadow is 53.5% Thalassia, 29.3% Halodule [cited: Seagrass-Watch].
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
//     dusk / sunrise cycle (960 s); the blacktips come in around sunset and
//     sunrise and patrol the shallow edge of the fringing reef, toward the
//     shore; the turtles graze low over the seagrass meadows.
// Not modelled because not sourced: mangrove genera and layout (mangroves
// are present at Lizard), zone widths, most day/night habits.
//
// How the GPU version works
//   - argus_init bakes the 64 m reef tile (2048 x 2048 texels, 3 cm each) into
//     the state texture: rgb = albedo, a = height. Sand, ripples, the fringing
//     reef, the seagrass mat, bommies (lumpy massive-coral heads), sponges and
//     rubble. Bommies, sponges and rubble sit on jittered grids so each texel
//     only looks at its neighbour cells (the Zig placed them by rejection).
//   - argus_step runs on the first three frames only: frame 0 lights the tile
//     (Lambert + cavity, reds absorbed), frame 1 adds a 2 m block max-height map
//     and the coral placements, frame 2 copies so both ping-pong textures hold
//     the same finished table. After that it returns at once.
//   - argus_draw marches each pixel's ray over the heightfield at the Zig's own
//     depth-slice spacing (2 m blocks whose max height the ray clears are
//     skipped), then bisects to the true surface, so the coral heads' sides
//     take their own baked, lit colour. Fish, corals, anemones, clams and
//     marine snow are culled per threadgroup tile into threadgroup lists, then
//     depth-tested per pixel. Fish swim on closed-form paths (schools orbit an
//     anchor bommie or anemone that is re-picked ahead every 40 s; loners
//     wander around a station that drifts with the diver).
//
// @argus state 2048x2082
// ============================================================================

const TWO_PI: f32 = 6.2831853f;
const TILE: f32 = 64.0f;
const KK: f32 = 6.2831853f / 64.0f;   // base spatial frequency
const TEX: f32 = 32.0f;                // texels per metre
const MAP_N: i32 = 2048;
const ROWS: u32 = 2082u;               // guard + 2048 rows + guard + 32 block rows
const BLK_ROW0: u32 = 2050u;           // block max map at (0..BLK_N-1, 2050..)
const BLK_T: i32 = 64;                 // texels per skip block (2 m)
const BLK_N: i32 = 2048 / BLK_T;
const BLK_M: f32 = f32(BLK_T) / 32.0f; // metres per skip block
const CORAL_COL0: u32 = 64u;           // coral table at (64 + i, 2050..2051)

const HORIZON: f32 = 0.42f;
const FOCAL: f32 = 0.80f;
const CAM_SPEED: f32 = 0.35f;
const CAM_Y: f32 = 2.6f;
const Z_NEAR: f32 = 0.5f;
const Z_FAR: f32 = 26.0f;
const Z_GROW: f32 = 0.017f;
const FOG_K: f32 = 0.115f;
const SURFACE_Y: f32 = 9.0f;
const DAY_PERIOD: f32 = 960.0f;
const H_BOUND: f32 = 11.5f;            // nothing on the reef is taller

const M_PI_F: f32 = 3.14159265358979323846264338327950288f;   // Metal's M_PI_F

const WATER_HOR: vec3f = vec3f(46.0f, 104.0f, 112.0f) / 255.0f;

const LIVE_COLS = array<vec3f, 6>(vec3f(196, 164, 104), vec3f(214, 198, 158), vec3f(176, 150, 92),
                                  vec3f(128, 138, 88), vec3f(136, 124, 168), vec3f(190, 150, 120));
const TURF = vec3f(104, 92, 60);
const ROCK = vec3f(150, 138, 120);
const CORALLINE = vec3f(196, 128, 138);
const SPONGE_COLS = array<vec3f, 4>(vec3f(128, 76, 70), vec3f(150, 92, 150), vec3f(214, 132, 58), vec3f(176, 60, 70));
const STAG_BASE = array<vec3f, 3>(vec3f(168, 140, 96), vec3f(150, 132, 104), vec3f(120, 128, 150));
const STAG_TIP = array<vec3f, 3>(vec3f(214, 214, 230), vec3f(150, 180, 250), vec3f(220, 170, 220));
const TABLE_COLS = array<vec3f, 3>(vec3f(150, 140, 96), vec3f(128, 134, 110), vec3f(168, 150, 120));
const ANEM_BASE = array<vec3f, 3>(vec3f(196, 176, 120), vec3f(168, 190, 120), vec3f(210, 190, 150));
const ANEM_TIP = array<vec3f, 3>(vec3f(240, 230, 170), vec3f(200, 240, 170), vec3f(255, 214, 214));
const ANEM_COLUMN = array<vec3f, 3>(vec3f(200, 40, 70), vec3f(150, 50, 140), vec3f(220, 200, 170));
const MANTLE_COLS = array<vec3f, 5>(vec3f(30, 110, 220), vec3f(20, 170, 170), vec3f(120, 160, 60),
                                    vec3f(120, 70, 200), vec3f(110, 110, 60));

// ------------------------------------------------------------------ species --
// 0 Damselfish, 1 Fusilier, 2 Pickhandle barracuda, 3 Eastern clownfish,
// 4 Parrotfish, 5 Barramundi cod, 6 Blacktip shark, 7 Whitetip shark,
// 8 Tawny nurse shark, 9 Green turtle. Numbers as in the Zig species structs.
const N_SPECIES: i32 = 10;
const NUM_FISH: i32 = 173;
const SP_START  = array<i32, 10>(0, 60, 108, 148, 153, 159, 162, 166, 169, 171);
const SP_LEN    = array<f32, 10>(0.08f, 0.30f, 0.9f, 0.08f, 0.45f, 0.55f, 1.5f, 1.5f, 2.6f, 1.0f);
const SP_HD     = array<f32, 10>(0.27f, 0.14f, 0.08f, 0.24f, 0.24f, 0.24f, 0.10f, 0.10f, 0.10f, 0.28f);
const SP_EXT    = array<f32, 10>(1.4f, 1.3f, 1.6f, 1.3f, 1.4f, 1.6f, 2.6f, 2.4f, 2.2f, 2.4f);
const SP_SPEED  = array<f32, 10>(1.2f, 1.5f, 0.5f, 0.9f, 0.8f, 0.4f, 0.6f, 0.35f, 0.2f, 0.35f);
const SP_SCHOOL = array<i32, 10>(1, 1, 1, 1, 0, 0, 0, 0, 0, 1);   // turtles share a meadow (anchor 3)
const SP_HAB    = array<i32, 10>(0, 1, 1, 0, 0, 0, 0, 0, 0, 0);   // blacktips keep low over the reef edge
const SP_ANCHOR = array<i32, 10>(1, 0, 1, 2, 0, 0, 0, 0, 0, 3);   // 1 bommie, 2 anemone, 3 seagrass meadow
const SP_DUSK   = array<i32, 10>(0, 0, 0, 0, 0, 0, 1, 0, 0, 0);

// Corals: 90 staghorn, 36 table, 28 anemones, 180 giant clams.
const NUM_CORAL: i32 = 334;
const CORAL_TABLE0: i32 = 90;
const CORAL_ANEM0: i32 = 126;
const CORAL_CLAM0: i32 = 154;
const NUM_SNOW: i32 = 900;

// ------------------------------------------------------------------ helpers --

fn sstep(e0: f32, e1: f32, x: f32) -> f32 {   // works for e0 > e1 too
    let t = saturate((x - e0) / (e1 - e0));
    return t * t * (3.0f - 2.0f * t);
}
fn wrapD(d: f32) -> f32 { return d - TILE * round(d / TILE); }   // round: Metal's rint (half to even)
fn wrap64(v: f32) -> f32 { return v - TILE * floor(v / TILE); }
fn channelX(z: f32) -> f32 { return 34.0f + 5.0f * sin(KK * z) + 2.0f * sin(2.0f * KK * z + 1.0f); }
fn lagoonDx(wx: f32, wz: f32) -> f32 { return wrapD(wx - channelX(wz)); }
fn fringeHeight(dx: f32) -> f32 { return 5.0f * max(sstep(-7.0f, -20.0f, dx), sstep(27.0f, 31.5f, dx)); }
fn rnd(h: u32, k: u32) -> f32 { return f32(argus_hash(h + k * 0x9E3779B9u)) * (1.0f / 4294967296.0f); }
// (t * freq) mod 2 pi without ever forming a huge argument.
fn ph(t: f32, fr: f32) -> f32 { let P = TWO_PI / fr; return (t - P * floor(t / P)) * fr; }
fn scrollAt(t: f32) -> f32 { let P = TILE / CAM_SPEED; return (t - P * floor(t / P)) * CAM_SPEED; }
fn camxAt(t: f32) -> f32 { return channelX(scrollAt(t) + 4.0f); }
fn habitatY(hab: i32) -> f32 { return select(select(5.5f, 3.0f, hab == 1), 1.0f, hab == 0); }
fn fogged(c255: vec3f, z: f32) -> vec3f { return mix(c255 / 255.0f, WATER_HOR, 1.0f - exp(-FOG_K * z)); }

fn hash01(x: u32, y: u32, seed: u32) -> f32 {
    var h = x * 0x8DA6B343u + y * 0xD8163841u + seed * 0xCB1AB31Fu;
    h ^= h >> 13u; h *= 0x5BD1E995u; h ^= h >> 15u;
    return f32(h & 0xFFFFu) / 65535.0f;
}

/// Periodic value noise on a `cells` x `cells` lattice over the tile (as the Zig).
fn valueNoise(wx: f32, wz: f32, cells: u32, seed: u32) -> f32 {
    let s = f32(cells) / TILE;
    let u = wx * s; let v = wz * s;
    let fu = floor(u); let fv = floor(v);
    let iu = u32(max(0.0f, fu)) % cells; let iv = u32(max(0.0f, fv)) % cells;
    let ju = (iu + 1u) % cells; let jv = (iv + 1u) % cells;
    let tu = u - fu; let tv = v - fv;
    let su = tu * tu * (3.0f - 2.0f * tu); let sv = tv * tv * (3.0f - 2.0f * tv);
    let a = hash01(iu, iv, seed); let b = hash01(ju, iv, seed);
    let c = hash01(iu, jv, seed); let d = hash01(ju, jv, seed);
    let ab = a + (b - a) * su; let cd = c + (d - c) * su;
    return ab + (cd - ab) * sv;
}

// ------------------------------------------------------------- the reef bake --

/// Reef rock colour (0..255): turf, rock, coralline crust, ~25% live massive coral.
fn reefSurface(wx: f32, wz: f32) -> vec3f {
    let n_live = valueNoise(wx, wz, 160u, 21u);
    let n_kind = valueNoise(wx, wz, 64u, 22u);
    let n_crust = valueNoise(wx, wz, 256u, 23u);
    let speck = 0.85f + 0.3f * valueNoise(wx, wz, 1024u, 24u);
    var c = mix(TURF, ROCK, sstep(0.3f, 0.7f, valueNoise(wx, wz, 128u, 25u)));
    c = mix(c, CORALLINE, 0.8f * sstep(0.62f, 0.8f, n_crust));
    let live = sstep(0.58f, 0.62f, n_live);
    if (live > 0.0f) {
        let k = i32(clamp(n_kind * 5.99f, 0.0f, 5.0f));
        var lc = LIVE_COLS[k];
        if (k == 3 && sin(wx * 60.0f) * sin(wz * 60.0f) > 0.4f) { lc *= 0.75f; }   // polyp grid
        c = mix(c, lc, live);
    }
    if (valueNoise(wx, wz, 200u, 26u) > 0.86f) { c = mix(c, SPONGE_COLS[2], 0.7f); }   // encrusting sponge
    return c * speck;
}

/// Lagoon floor height without seagrass (used for feature bases).
fn groundBase(wx: f32, wz: f32) -> f32 {
    let dx = lagoonDx(wx, wz);
    let rarg = 128.0f * KK * wx + 40.0f * KK * wz + 2.0f * sin(9.0f * KK * wz);
    let undul = 0.35f * (valueNoise(wx, wz, 16u, 11u) - 0.5f);
    let fringe = fringeHeight(dx);
    let on_reef = sstep(0.3f, 1.2f, fringe);
    var h = undul + 0.025f * sin(rarg) * (1.0f - on_reef) + fringe;
    if (on_reef > 0.0f) { h += on_reef * ((valueNoise(wx, wz, 256u, 12u) - 0.5f) * 0.5f + (valueNoise(wx, wz, 1024u, 13u) - 0.5f) * 0.12f); }
    return h;
}

/// Pass 1 of the Zig bake for one texel: sand, fringing reef, patchy seagrass.
/// 0..1: how much a meadow here is strap-leaved Thalassia/Halodule rather than
/// Halophila. At Lizard the sheltered lagoon meadow is mostly Thalassia (53.5%)
/// and Halodule (29.3%), while Halophila dominates the more open, deeper sand
/// [cited: Seagrass-Watch]; here sheltered patches (about
/// half the meadows, ~10 m across) and the shallows by the fringing reef carry
/// straps, the rest Halophila.
fn strapness(wx: f32, wz: f32) -> f32 {
    let shallows = 1.0f - sstep(-5.5f, -3.5f, lagoonDx(wx, wz));
    return max(shallows, sstep(0.44f, 0.54f, valueNoise(wx, wz, 6u, 31u)));
}

fn groundTexel(tu: u32, tv: u32, h: ptr<function, f32>, c: ptr<function, vec3f>) {
    let wx = (f32(tu) + 0.5f) / TEX; let wz = (f32(tv) + 0.5f) / TEX;
    let dx = lagoonDx(wx, wz);
    let rarg = 128.0f * KK * wx + 40.0f * KK * wz + 2.0f * sin(9.0f * KK * wz);
    let undul = 0.35f * (valueNoise(wx, wz, 16u, 11u) - 0.5f);
    let fringe = fringeHeight(dx);
    let on_reef = sstep(0.3f, 1.2f, fringe);
    var rough = 0.0f;
    if (on_reef > 0.0f) { rough = (valueNoise(wx, wz, 256u, 12u) - 0.5f) * 0.5f + (valueNoise(wx, wz, 1024u, 13u) - 0.5f) * 0.12f; }
    *h = undul + 0.025f * sin(rarg) * (1.0f - on_reef) + fringe + rough * on_reef;
    *c = mix(vec3f(228, 222, 200), vec3f(206, 196, 170), 0.5f + 0.5f * sin(rarg));   // pale carbonate sand
    if (on_reef > 0.0f) { *c = mix(*c, reefSurface(wx, wz), on_reef); }
    if (on_reef < 0.2f) {
        let meadow = sstep(0.52f, 0.68f, valueNoise(wx, wz, 12u, 14u));
        let cover = meadow * (0.15f + 0.3f * valueNoise(wx, wz, 96u, 15u));
        // Under the blades the meadow floor reads as a dim green mat (lower blades,
        // rhizomes, the shade of the canopy), not bright sand. Besides being how a
        // meadow looks, that keeps each 3 cm blade close in tone to what's behind
        // it, so the thousands of pixel-sized blades don't shimmer as the diver
        // drifts (bright sand between dark spikes did).
        let mat = max(sstep(0.0f, 0.25f, cover), 0.6f * meadow);   // reaches the meadow's edges too
        // The blades themselves are drawn by the draw kernel (see seagrass()), as
        // fixed straps that sway; the bake only lays the mat, whose green also tells
        // the draw how dense the blades are.
        if (meadow > 0.0f) {
            // Halophila meadows in the lagoon are sparser and paler than the strap
            // meadows in the shallows by the fringing reef (see shallowStraps).
            let strap = strapness(wx, wz);
            // Strap meadows are dense lawns (Halodule ~6,900 shoots/m2 [atlas]);
            // Halophila a thin scatter (median ~0 g/m2 above ground [atlas]).
            let mat2 = mix(mat, max(mat, 0.85f * meadow), strap);
            *c = mix(mix(*c, vec3f(176, 170, 140), 0.35f * meadow), vec3f(92, 116, 70), mix(0.5f, 0.8f, strap) * mat2);
            *h += 0.02f * mat;
        }
    }
}

// Bommies: one candidate per cell of a 14 x 14 grid (4.57 m), kept clear of the
// drift path and mostly off the fringing reef, as the Zig's rejection rules.
const BC: i32 = 14;
const BCS: f32 = 64.0f / 14.0f;

struct Bommie { x: f32, z: f32, r: f32, tall: f32, s: u32, lobes: i32, ok: bool, }

fn bommieCell(ci_in: i32, cj_in: i32) -> Bommie {
    let ci = ((ci_in % BC) + BC) % BC;
    let cj = ((cj_in % BC) + BC) % BC;
    var b: Bommie;
    b.s = argus_hash(u32(ci * BC + cj) ^ 0xB0331E5Du);
    b.x = (f32(ci) + 0.2f + 0.6f * rnd(b.s, 1u)) * BCS;
    b.z = (f32(cj) + 0.2f + 0.6f * rnd(b.s, 2u)) * BCS;
    b.r = 0.9f + 2.0f * rnd(b.s, 3u);
    b.ok = rnd(b.s, 0u) < 0.9f;
    let dx = lagoonDx(b.x, b.z);
    if (abs(dx) < b.r + 2.2f) { b.ok = false; }                                  // keep the path clear
    if (fringeHeight(dx) > 2.0f && rnd(b.s, 4u) < 0.7f) { b.ok = false; }
    b.tall = min(4.5f, b.r * (0.7f + 0.9f * rnd(b.s, 5u)));
    b.lobes = 6 + i32(rnd(b.s, 6u) * 6.0f);
    return b;
}

/// Raises h to the tallest bommie lobe at (wx, wz); true if any lobe did.
fn bommieMax(wx: f32, wz: f32, h: ptr<function, f32>) -> bool {
    let icx = i32(floor(wx / BCS)); let icz = i32(floor(wz / BCS));
    var raised = false;
    for (var dj = -1; dj <= 1; dj++) {
        for (var di = -1; di <= 1; di++) {
            let b = bommieCell(icx + di, icz + dj);
            if (!b.ok) { continue; }
            let ex = wrapD(wx - b.x); let ez = wrapD(wz - b.z);
            let reach = 1.45f * b.r + 0.05f;
            if (ex * ex + ez * ez > reach * reach) { continue; }
            let base = groundBase(b.x, b.z);
            for (var l = 0; l < b.lobes; l++) {
                let ls = argus_hash(b.s ^ ((u32(l) + 1u) * 0x85EBCA6Bu));
                let a = rnd(ls, 0u) * TWO_PI;
                let off = select(b.r * (0.3f + 0.55f * rnd(ls, 1u)), 0.0f, l == 0);
                let lr = select(b.r * (0.3f + 0.3f * rnd(ls, 2u)), b.r * 0.8f, l == 0);
                let lx = wrapD(wx - (b.x + cos(a) * off));
                let lz = wrapD(wz - (b.z + sin(a) * off));
                let d2 = (lx * lx + lz * lz) / (lr * lr);
                if (d2 >= 1.0f) { continue; }
                let lh = select(b.tall * (0.35f + 0.55f * rnd(ls, 3u)), b.tall, l == 0);
                let seed = u32(rnd(ls, 4u) * 60000.0f);
                // Porites-style lumps: a dome with knobbly lobes on it.
                let q = sqrt(max(0.0f, 1.0f - d2));
                let dome = lh * q * (0.85f + 0.15f * q);
                let knob = 0.40f * lr * (valueNoise(wx, wz, 128u, seed) - 0.5f) + 0.12f * (valueNoise(wx, wz, 512u, seed + 1u) - 0.5f);
                let hh = base + dome + knob;
                if (hh > *h) { *h = hh; raised = true; }
            }
        }
    }
    return raised;
}

fn heightNoSponge(wx: f32, wz: f32) -> f32 {
    var h = groundBase(wx, wz);
    bommieMax(wrap64(wx), wrap64(wz), &h);
    return h;
}

@compute @workgroup_size(8, 8)
fn argus_init(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    if (gid.y >= BLK_ROW0 || gid.x >= u32(MAP_N)) { textureStore(argus_state_out, gid, vec4f(0.0f)); return; }
    // Row 0 and row 2049 are guard copies of data rows 2047 and 0 (seamless bilinear wrap).
    let tu = gid.x;
    let tv = (gid.y + u32(MAP_N) - 1u) % u32(MAP_N);
    let wx = (f32(tu) + 0.5f) / TEX; let wz = (f32(tv) + 0.5f) / TEX;

    var h: f32; var c: vec3f;
    groundTexel(tu, tv, &h, &c);
    if (bommieMax(wx, wz, &h)) { c = reefSurface(wx, wz); }

    // Sponges: barrel and vase forms on bommies and the reef slope (13 x 13 grid).
    {
        let cs = 64.0f / 13.0f;
        let icx = i32(floor(wx / cs)); let icz = i32(floor(wz / cs));
        for (var dj = -1; dj <= 1; dj++) { for (var di = -1; di <= 1; di++) {
            let ci = ((icx + di) % 13 + 13) % 13; let cj = ((icz + dj) % 13 + 13) % 13;
            let s = argus_hash(u32(ci * 13 + cj) ^ 0x5B0A9E77u);
            let cx = (f32(ci) + 0.1f + 0.8f * rnd(s, 1u)) * cs;
            let cz = (f32(cj) + 0.1f + 0.8f * rnd(s, 2u)) * cs;
            let vase = rnd(s, 3u) < 0.4f;
            let r = select(0.18f + 0.2f * rnd(s, 4u), 0.10f + 0.08f * rnd(s, 4u), vase);
            let ex = wrapD(wx - cx); let ez = wrapD(wz - cz);
            let d2 = (ex * ex + ez * ez) / (r * r);
            if (d2 >= 1.0f) { continue; }
            if (abs(lagoonDx(cx, cz)) < 2.5f) { continue; }
            let base = heightNoSponge(cx, cz);
            if (base < 0.6f) { continue; }   // on rock, not on sand
            let tall = select(r * (1.2f + 1.0f * rnd(s, 5u)), 0.35f + 0.3f * rnd(s, 5u), vase);
            let col = SPONGE_COLS[i32(rnd(s, 6u) * 3.99f)];
            let hh = select(base + tall, base + tall * 0.5f, d2 < 0.40f);
            if (hh > h) { h = hh; c = select(col, col * 0.3f, d2 < 0.40f); }
        } }
    }
    // Coral rubble on the lagoon sand (20 x 20 grid).
    {
        let cs = 3.2f;
        let icx = i32(floor(wx / cs)); let icz = i32(floor(wz / cs));
        for (var dj = -1; dj <= 1; dj++) { for (var di = -1; di <= 1; di++) {
            let ci = ((icx + di) % 20 + 20) % 20; let cj = ((icz + dj) % 20 + 20) % 20;
            let s = argus_hash(u32(ci * 20 + cj) ^ 0x7B1EB1E5u);
            if (rnd(s, 0u) > 0.65f) { continue; }
            let cx = (f32(ci) + 0.05f + 0.9f * rnd(s, 1u)) * cs;
            let cz = (f32(cj) + 0.05f + 0.9f * rnd(s, 2u)) * cs;
            let r = 0.06f + 0.14f * rnd(s, 3u);
            let ex = wrapD(wx - cx); let ez = wrapD(wz - cz);
            let d2 = (ex * ex + ez * ez) / (r * r);
            if (d2 >= 1.0f) { continue; }
            if (abs(lagoonDx(cx, cz)) < 1.0f) { continue; }
            let base = heightNoSponge(cx, cz);
            if (base > 0.4f) { continue; }
            let tall = r * (0.3f + 0.3f * rnd(s, 4u));
            let hh = base + tall * sqrt(max(0.0f, 1.0f - d2));
            if (hh > h) { h = hh; c = vec3f(200, 190, 166) * (0.75f + 0.3f * rnd(s, 5u)); }
        } }
    }
    textureStore(argus_state_out, gid, vec4f(saturate(c / 255.0f), h));
}

// ------------------------------------------------- one-time lighting / tables --

fn hRead(t: texture_2d<f32>, iu: i32, iv: i32) -> f32 {
    return textureLoad(t, vec2u(u32(iu & (MAP_N - 1)), u32(iv & (MAP_N - 1)) + 1u), 0).a;
}

fn hBilinear(t: texture_2d<f32>, x: f32, z: f32) -> f32 {
    let u = x * TEX - 0.5f; let v = z * TEX - 0.5f;
    let fu = floor(u); let fv = floor(v);
    let iu = i32(fu); let iv = i32(fv);
    let tu = u - fu; let tv = v - fv;
    let a = mix(hRead(t, iu, iv), hRead(t, iu + 1, iv), tu);
    let b = mix(hRead(t, iu, iv + 1), hRead(t, iu + 1, iv + 1), tu);
    return mix(a, b, tv);
}

// Coral placement: small patches of branching Acropora, table Acropora and
// anemones on bommie tops, giant clams set into coral heads (a few T. gigas on
// the sand beside them). kind: 1 staghorn, 3 anemone, 4 table, 5 clam.
fn coralPlace(i: i32, extra: ptr<function, vec4f>) -> vec4f {
    let h = argus_hash(u32(i) * 0x632BE5ABu + 0xC0A1u);
    var kind = 1; var reach = 0.7f; var size = 0.35f + 0.25f * rnd(h, 10u); var style = i32(rnd(h, 11u) * 2.99f);
    var gigas = false;
    if (i >= CORAL_CLAM0) {
        kind = 5;
        let ci = i - CORAL_CLAM0;
        if (ci % 45 == 0) { gigas = true; reach = 1.0f; style = 4; size = 0.45f + 0.15f * rnd(h, 10u); }
        else { reach = 0.9f; style = i32(rnd(h, 11u) * 3.99f); size = select(0.14f + 0.10f * rnd(h, 10u), 0.07f + 0.05f * rnd(h, 10u), rnd(h, 12u) < 0.75f); }
    } else if (i >= CORAL_ANEM0) { kind = 3; reach = 0.85f; size = 0.22f + 0.15f * rnd(h, 10u); }
    else if (i >= CORAL_TABLE0) { kind = 4; reach = 0.8f; size = 0.35f + 0.5f * rnd(h, 10u); }
    var b: Bommie; b.ok = false;
    for (var k = 0u; k < 16u && !b.ok; k++) {
        let c = argus_hash(h + k * 0x2545F491u) % u32(BC * BC);
        b = bommieCell(i32(c / u32(BC)), i32(c % u32(BC)));
    }
    let a = rnd(h, 13u) * TWO_PI;
    let d = b.r * reach * sqrt(rnd(h, 14u));
    var x = b.x + cos(a) * d; let z = b.z + sin(a) * d;
    if (gigas) { x += 1.4f; }
    *extra = vec4f(rnd(h, 15u) * TWO_PI, f32(kind), f32(style), select(0.0f, 1.0f, b.ok));
    return vec4f(wrap64(x), wrap64(z), 0.0f, size);
}

// ------------------------------------------------------------------- scene --

struct Scene {
    t: f32, w: f32, h: f32, focal: f32, hor: f32, scroll: f32, camx: f32, camy: f32,
    gold: f32, dim: f32,
}

// The Metal source's local lambda in makeScene.
fn bump(x: f32, c: f32, w: f32) -> f32 { let d = (x - c) / w; return max(0.0f, 1.0f - d * d); }

fn makeScene(fr: ArgusFrame) -> Scene {
    var S: Scene;
    S.t = fr.time;
    S.w = f32(fr.width);
    S.h = f32(fr.height);
    S.focal = FOCAL * S.h;
    S.hor = HORIZON * S.h;
    S.scroll = scrollAt(S.t);
    S.camx = channelX(S.scroll + 4.0f);
    S.camy = CAM_Y + 0.15f * sin(ph(S.t, 0.19f));
    // Day, sunset, dusk and sunrise over DAY_PERIOD seconds.
    let pday = fract(S.t / DAY_PERIOD + 0.35f);
    S.gold = min(1.0f, bump(pday, 0.74f, 0.07f) + bump(pday, 0.95f, 0.06f));
    S.dim = bump(pday, 0.845f, 0.05f);
    return S;
}

// reefSampler (Metal: s_address::repeat, t_address::clamp_to_edge, filter::linear) is
// the prelude's argus_linear_repeat_s.

/// Baked reef at world (x, z): rgb lit albedo, a height.
fn reefAt(st: texture_2d<f32>, x: f32, z: f32) -> vec4f {
    let zz = wrap64(z);
    return argus_sample(st, argus_linear_repeat_s, vec2f(x * (1.0f / TILE), (zz * TEX + 1.0f) / f32(ROWS)));
}

fn project(S: Scene, rx: f32, ry: f32, rz: f32, p: ptr<function, vec2f>) -> bool {
    if (rz < Z_NEAR) { return false; }
    let k = S.focal / rz;
    *p = vec2f(0.5f * S.w + rx * k, S.hor - ry * k);
    return true;
}

fn segDist(p: vec2f, a: vec2f, b: vec2f) -> f32 {
    let ab = b - a; let ap = p - a;
    let t = saturate(dot(ap, ab) / max(dot(ab, ab), 1e-6f));
    return length(ap - ab * t);
}

/// The Zig's fillLine: an opaque line `thick` pixels wide.
fn onLine(p: vec2f, a: vec2f, b: vec2f, thick: f32) -> bool {
    let tw = floor(clamp(thick, 1.0f, 40.0f));
    return segDist(p, a, b) <= 0.5f * tw + 0.15f;
}

fn stagSeed(i: u32) -> u32 { return argus_hash(i * 0x2C1B3C6Du + 0x57A6u); }

// WGSL has no lambdas or templates: the two visitors stagGrow is called with (the screen
// box in coralStep, the pixel test in stagHit) are this one struct, its captures, and
// stagVisit, which runs the one its `mode` names.
struct StagVisit {
    mode: i32,          // 0: coralStep's box, 1: stagHit's pixel test
    S: Scene,
    rx: f32, ry: f32, rz: f32, k: f32,
    pp: vec2f,          // stagHit
    r2: vec4f,          // coralStep
    ok: bool,           // coralStep
    hit: i32,           // stagHit
}

fn stagVisit(v: ptr<function, StagVisit>, p: vec3f, e: vec3f, th: f32, dep: i32) -> bool {
    let S = (*v).S;
    let rx = (*v).rx; let ry = (*v).ry; let rz = (*v).rz; let k = (*v).k;
    var a2: vec2f; var b2: vec2f;
    if ((*v).mode == 0) {
        if (!project(S, rx + p.x, ry + p.y, rz + p.z, &a2) || !project(S, rx + e.x, ry + e.y, rz + e.z, &b2)) { (*v).ok = false; return true; }
        let pad = 0.5f * floor(clamp(th * k, 1.0f, 40.0f)) + 1.0f;
        let r2 = (*v).r2;
        (*v).r2 = vec4f(min(r2.xy, min(a2, b2) - pad), max(r2.zw, max(a2, b2) + pad));
        return false;
    }
    if (project(S, rx + p.x, ry + p.y, rz + p.z, &a2) && project(S, rx + e.x, ry + e.y, rz + e.z, &b2) && onLine((*v).pp, a2, b2, th * k)) {
        (*v).hit = dep;
        return true;
    }
    return false;
}

// The Metal source's R lambda in stagGrow.
fn stagR(st: ptr<function, u32>) -> f32 { *st = argus_hash(*st + 0x9E3779B9u); return f32(*st) * (1.0f / 4294967296.0f); }

/// The Zig's growStaghorn: 3-5 trunks, each branching 1-2 ways down to depth 4,
/// at most 40 segments. Calls visit(base, tip, thickness, depth) per segment
/// until it returns true.
fn stagGrow(seed: u32, size: f32, visit: ptr<function, StagVisit>) {
    var st = seed;
    var sp: array<vec3f, 12>; var sd: array<vec3f, 12>; var sl: array<f32, 12>; var sth: array<f32, 12>; var sdep: array<i32, 12>;
    var n = 0;
    let trunks = 3 + i32(stagR(&st) * 3.0f);
    for (var i = 0; i < trunks; i++) {
        let a = stagR(&st) * TWO_PI; let lean = 0.25f + 0.5f * stagR(&st);
        sp[n] = vec3f(0.0f); sd[n] = normalize(vec3f(cos(a) * lean, 1.0f, sin(a) * lean));
        sl[n] = 0.36f * size; sth[n] = 0.13f * size; sdep[n] = 0; n++;
    }
    var segs = 0;
    while (n > 0 && segs < 40) {
        n--;
        let p = sp[n]; let d = sd[n];
        let len = sl[n]; let th = sth[n]; let dep = sdep[n];
        let e = p + d * len;
        segs++;
        if (stagVisit(visit, p, e, th, dep)) { return; }
        if (dep >= 4) { continue; }
        let kids = select(1, 2, stagR(&st) < 0.55f);
        for (var j = 0; j < kids && n < 12; j++) {
            let a = stagR(&st) * TWO_PI; let spread = 0.45f + 0.35f * stagR(&st);
            sp[n] = e; sd[n] = normalize(vec3f(d.x + cos(a) * spread, d.y + 0.25f, d.z + sin(a) * spread));
            sl[n] = len * (0.78f + 0.1f * stagR(&st)); sth[n] = th * 0.82f; sdep[n] = dep + 1; n++;
        }
    }
}

// --------------------------------------------------------------- creatures --
// Species shading, ported from the Zig species structs (colours 0..255).
//   u: along the body, 0 nose .. 1 tail tip; s: across, in units of W, s < 0 back;
//   t: tail-beat phase; seed: 0..1 per animal.

fn inTri(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) -> bool {
    let d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
    let d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
    let d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
    let neg = d1 < 0.0f || d2 < 0.0f || d3 < 0.0f;
    let pos = d1 > 0.0f || d2 > 0.0f || d3 > 0.0f;
    return !(neg && pos);
}

fn shadeClown(u: f32, s: f32, t: f32, c: ptr<function, vec3f>) -> bool {
    let sb = s - 0.5f * sin(t) * u * u;
    let a = abs(sb);
    var hw = 0.0f;
    if (u >= 0.0f && u <= 1.0f) {
        let uq = floor(u * 63.0f) / 63.0f;
        let p = min(uq / 0.78f, 1.0f);
        hw = select(0.18f, 0.18f + 0.82f * sin(M_PI_F * pow(max(p, 1e-6f), 0.62f)), uq <= 0.78f);
    }
    var tail = false;
    if (u > 0.74f && u <= 1.0f) {
        let tf = (u - 0.74f) / 0.26f;
        let notch = select(0.0f, 0.5f * (tf - 0.7f) / 0.3f, tf > 0.7f);
        if (1.05f * tf > hw && a > notch) { hw = 1.05f * tf; tail = true; }
    }
    if (a > hw) { return false; }
    let k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    *c = mix(vec3f(240, 104, 18), vec3f(255, 140, 40), k);
    var bars = array<vec2f, 3>(vec2f(0.17f, 0.27f), vec2f(0.44f, 0.56f), vec2f(0.74f, 0.80f));
    for (var i = 0; i < 3; i++) {
        let b = bars[i];
        if (u > b.x && u < b.y) { *c = vec3f(250, 248, 244); }
        if ((u > b.x - 0.035f && u <= b.x) || (u >= b.y && u < b.y + 0.035f)) { *c = vec3f(26, 18, 14); }
    }
    if (tail && u > 0.93f) { *c = vec3f(26, 18, 14); }
    if (hw - a < 0.07f) { *c *= 0.7f; }
    let eu = (u - 0.12f) / 0.06f; let ev = (sb + 0.22f) / 0.17f;
    if (eu * eu + ev * ev < 1.0f) { *c = vec3f(14, 14, 20); }
    return true;
}

fn btFin(sb: f32, tip: bool) -> vec3f {
    if (tip) { return vec3f(18, 18, 22); }
    return select(vec3f(210, 212, 210), vec3f(78, 86, 92), sb < 0.0f);
}

fn shadeBlacktip(u: f32, s: f32, t: f32, c: ptr<function, vec3f>) -> bool {
    let rear = saturate((u - 0.45f) / 0.55f);
    let sb = s - 0.7f * sin(t) * rear * rear;
    let a = abs(sb);
    let p = saturate(u / 0.8f);
    let hw = select(0.0f, 0.04f + 0.96f * sin(M_PI_F * pow(max(p, 1e-6f), 0.8f)), u >= 0.0f && u <= 0.8f);
    if (a <= hw) {
        let k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
        let m = saturate((k - 0.3f) / 0.4f);
        *c = vec3f(86.0f + 160.0f * m, 92.0f + 154.0f * m, 92.0f + 146.0f * m);
        if (u > 0.15f && u < 0.27f && a < 0.4f && fract((u - 0.15f) / 0.024f) < 0.2f) { *c *= 0.72f; }
        if (hw - a < 0.09f) { *c *= 0.55f; }
        let eu = (u - 0.10f) / 0.022f; let ev = (sb + 0.20f) / 0.22f;
        if (eu * eu + ev * ev < 1.0f) { *c = vec3f(12, 12, 16); }
        return true;
    }
    if (inTri(u, sb, 0.29f, -0.2f, 0.44f, -2.2f, 0.57f, -0.2f)) { *c = btFin(sb, -sb > 1.85f); return true; }
    if (inTri(u, sb, 0.66f, -0.1f, 0.78f, -0.85f, 0.84f, -0.1f)) { *c = btFin(sb, -sb > 0.7f); return true; }
    if (inTri(u, sb, 0.66f, 0.1f, 0.78f, 0.7f, 0.84f, 0.1f)) { *c = btFin(sb, sb > 0.6f); return true; }
    if (inTri(u, sb, 0.16f, 0.2f, 0.44f, 1.9f, 0.34f, 0.2f)) { *c = btFin(sb, sb > 1.5f && u > 0.36f); return true; }
    if (inTri(u, sb, 0.62f, -0.1f, 1.0f, -2.0f, 0.93f, -0.12f)) { *c = btFin(sb, u > 0.93f && sb < -1.7f); return true; }
    if (inTri(u, sb, 0.62f, 0.1f, 0.97f, 0.85f, 0.93f, 0.12f)) { *c = btFin(sb, u > 0.9f && sb > 0.6f); return true; }
    return false;
}

fn shadeParrot(u: f32, s: f32, t: f32, c: ptr<function, vec3f>) -> bool {
    let sb = s - 0.18f * sin(t) * u * u;
    let a = abs(sb);
    let p = saturate(u / 0.8f);
    let hw = select(0.0f, 0.12f + 0.88f * sin(M_PI_F * pow(max(p, 1e-6f), 0.7f)), u >= 0.0f && u <= 0.8f);
    let fh = select(0.0f, 0.27f * sqrt(max(0.0f, sin(M_PI_F * (u - 0.08f) / 0.72f))), sb < 0.0f && u > 0.08f && u <= 0.8f);
    let tf = saturate((u - 0.8f) / 0.2f);
    let notch = 0.4f * tf * tf;
    let th = 0.12f + 0.95f * tf;
    let tail = u > 0.8f && u <= 1.0f && a > notch && a <= th;
    let fin = !tail && fh > 0.0f && a > hw && a <= hw + fh;
    let body = u >= 0.0f && u <= 0.8f && a <= hw;
    if (!(tail || fin || body)) { return false; }
    let k = 0.5f + 0.5f * clamp(sb / 0.9f, -1.0f, 1.0f);
    let teal = vec3f(40.0f + 40.0f * k, 150.0f + 60.0f * k, 140.0f + 30.0f * k);
    *c = teal;
    if (tail) {
        *c = vec3f(62, 192, 166);
        if (a > th - 0.16f || a < notch + 0.07f) { *c = vec3f(250, 128, 64); }
    } else if (fin) {
        *c = vec3f(84, 212, 190);
        if (a > hw + 0.6f * fh) { *c = vec3f(250, 118, 104); }
        if (abs(sin(u * 150.0f)) < 0.15f) { *c = mix(*c, vec3f(40, 130, 130), 0.35f); }
    } else {
        let e = min(abs(sin(140.0f * u + 12.0f * sb)), abs(sin(40.0f * sb)));
        *c = mix(teal, vec3f(246, 124, 92), saturate(1.0f - e / 0.2f) * 0.7f);
        if (hw - a < 0.07f) { *c *= 0.6f; }
        if (u > 0.2f && u < 0.44f && sb > -0.05f && sb < 0.5f) {
            let ang = 0.35f * sin(t);
            let du = u - 0.32f; let ds = sb - 0.24f;
            let cs = cos(ang); let sn = sin(ang);
            let pu = (du * cs + ds * sn) / 0.09f; let ps = (-du * sn + ds * cs) / 0.25f;
            let pr = pu * pu + ps * ps;
            if (pr < 1.0f) { *c = mix(*c, vec3f(176, 242, 222), 0.6f); if (pr > 0.6f) { *c = vec3f(250, 130, 110); } }
        }
        let cu = (u - 0.19f) / 0.06f; let cv = (sb - 0.3f) / 0.12f;
        if (cu * cu + cv * cv < 1.0f) { *c = mix(*c, vec3f(255, 102, 122), 0.85f); }
        if (u < 0.08f && sb > -0.15f && sb < 0.4f) {
            *c = vec3f(240, 238, 224);
            if (u > 0.035f && u < 0.045f) { *c = vec3f(190, 188, 178); }
        }
        let eu = (u - 0.14f) / 0.055f; let ev = (sb + 0.2f) / 0.15f;
        let d2 = eu * eu + ev * ev;
        if (d2 < 0.36f) { *c = vec3f(16, 16, 22); } else if (d2 < 1.0f) { *c = vec3f(244, 206, 74); }
    }
    return true;
}

fn turtleSkin(x: f32, y: f32, base: vec3f) -> vec3f {
    let dx = x * 46.0f - floor(x * 46.0f) - 0.5f; let dy = y * 46.0f - floor(y * 46.0f) - 0.5f;
    return select(base, vec3f(176, 190, 160), dx * dx + dy * dy < 0.07f);
}

fn flipperInside(x: f32, y: f32, rx: f32, ry: f32, ang: f32, len: f32, w0: f32, w1: f32) -> f32 {
    let dx = sin(ang); let dy = cos(ang);
    let px = x - rx; let py = y - ry;
    let al = px * dx + py * dy;
    if (al < -0.06f || al > len) { return -1.0f; }
    let f = saturate(al / len);
    let hw = w1 + (w0 - w1) * (1.0f - f) * sqrt(max(0.0f, 1.0f - f * f + 0.02f));
    let pe = px * dy - py * dx - 0.5f * al * al;
    return hw - abs(pe);
}

fn shadeTurtle(u: f32, s: f32, t: f32, c: ptr<function, vec3f>) -> bool {
    let x = u; let y = s * 0.28f; let sw = sin(t);
    let ex = (x - 0.12f) / 0.022f; let ey = (y + 0.035f) / 0.022f;
    let e2 = ex * ex + ey * ey;
    if (e2 <= 1.0f) { *c = select(vec3f(214, 208, 170), vec3f(14, 14, 18), e2 < 0.42f); return true; }
    let fd = flipperInside(x, y, 0.27f, 0.06f, 0.45f + 0.35f * sw, 0.3f + 0.05f * sw, 0.12f, 0.03f);
    if (fd >= 0.0f) { *c = select(turtleSkin(x, y, vec3f(118, 138, 110)), vec3f(44, 56, 42), fd < 0.012f); return true; }
    let rd = flipperInside(x, y, 0.74f, 0.07f, 0.6f + 0.1f * sw, 0.17f, 0.05f, 0.02f);
    if (rd >= 0.0f) { *c = select(turtleSkin(x, y, vec3f(112, 132, 104)), vec3f(44, 56, 42), rd < 0.01f); return true; }
    let hcy = -0.02f + 0.006f * sw;
    let hqx = (x - 0.09f) / 0.10f; let hqy = (y - hcy) / 0.075f;
    let hr2 = hqx * hqx + hqy * hqy;
    let nqx = (x - 0.18f) / 0.075f; let nqy = (y + 0.03f) / 0.065f;
    let nr2 = nqx * nqx + nqy * nqy;
    if (hr2 <= 1.0f || nr2 <= 1.0f) {
        if (x < 0.03f && hr2 <= 1.0f) { *c = vec3f(72, 66, 46); }
        else if (min(hr2, nr2) > 0.84f) { *c = vec3f(44, 56, 44); }
        else { *c = turtleSkin(x, y, vec3f(110, 130, 102)); }
        return true;
    }
    let qx = (x - 0.49f) / 0.33f;
    if (y <= 0.03f) {
        let qy = (y - 0.03f) / 0.26f;
        let r2 = qx * qx + qy * qy;
        if (r2 <= 1.0f) {
            if (r2 > 0.86f) { *c = vec3f(36, 38, 20); return true; }
            let gy = (y + 0.23f) * 12.0f;
            let row = floor(gy);
            let odd = row - 2.0f * floor(row * 0.5f);
            let gx = (x - 0.49f) * 12.0f + select(0.5f, 0.0f, odd == 0.0f);
            let cx = floor(gx);
            let fx = gx - cx; let fy = gy - row;
            if (min(fx, 1.0f - fx) < 0.08f || min(fy, 1.0f - fy) < 0.08f) { *c = vec3f(54, 48, 26); return true; }
            let hh = saturate((-y - 0.02f) / 0.22f);
            let par = (cx + row) - 2.0f * floor((cx + row) * 0.5f);
            let alt = select(1.0f, 0.94f, par == 0.0f);
            *c = vec3f(98.0f + 30.0f * hh, 102.0f + 26.0f * hh, 50.0f + 18.0f * hh) * alt;
            return true;
        }
    } else {
        let qb = (y - 0.03f) / 0.09f;
        let r2 = qx * qx + qb * qb;
        if (r2 <= 1.0f) {
            if (r2 > 0.86f) { *c = vec3f(40, 50, 38); }
            else if (y < 0.055f) { *c = vec3f(224, 210, 152); }
            else { *c = turtleSkin(x, y, vec3f(104, 124, 96)); }
            return true;
        }
    }
    if (x >= 0.80f && x <= 1.0f) {
        let tf = (x - 0.80f) / 0.20f;
        let hwt = 0.05f * pow(max(1.0f - tf, 1e-6f), 0.9f);
        let ta = abs(y);
        if (ta < hwt) { *c = select(turtleSkin(x, y, vec3f(92, 110, 82)), vec3f(40, 46, 34), hwt - ta < 0.01f); return true; }
    }
    return false;
}

fn shadeDamsel(u: f32, s: f32, t: f32, seed: f32, c: ptr<function, vec3f>) -> bool {
    let sb = s - 0.22f * sin(t) * u * u;
    let a = abs(sb);
    let dorsal = sb < 0.0f;
    let humbug = seed >= 0.85f;
    let yellow = seed >= 0.6f && seed < 0.85f;
    var hw = 0.0f;
    if (u >= 0.0f && u <= 0.78f) {
        let xs = select((u - 0.36f) / 0.42f, (0.36f - u) / 0.36f, u < 0.36f);
        hw = 0.2f + 0.8f * sqrt(max(0.0f, 1.0f - xs * xs));
    } else if (u > 0.78f && u <= 0.84f) { hw = 0.2f; }
    var tf = 0.0f; var tail = false;
    if (u > 0.78f && u <= 1.0f) { tf = (u - 0.78f) / 0.22f; tail = a > 0.4f * tf * tf && a <= 0.8f * tf + 0.04f; }
    var fh = 0.0f; var pelvic = false;
    if (dorsal) {
        if (u >= 0.08f && u <= 0.76f) {
            let dt = (u - 0.08f) / 0.68f;
            let ramp = saturate((u - 0.08f) / 0.05f) * saturate((0.76f - u) / 0.06f);
            fh = 0.34f * (1.0f - 0.4f * dt) * ramp * (0.9f + 0.1f * sin(u * 150.0f));
        }
    } else if (u >= 0.46f && u <= 0.76f) { fh = 0.22f * sin(M_PI_F * (u - 0.46f) / 0.3f); }
    else if (u >= 0.16f && u <= 0.28f) { fh = 0.16f * sin(M_PI_F * (u - 0.16f) / 0.12f); pelvic = true; }
    let in_body = a <= hw;
    let in_fin = !in_body && a <= hw + fh;
    if (!tail && !in_body && !in_fin) { return false; }
    var lo = vec3f(30, 106, 134); var hi = vec3f(146, 224, 206); var fin = vec3f(44, 130, 160);
    if (yellow) { lo = vec3f(232, 162, 18); hi = vec3f(255, 226, 70); fin = vec3f(250, 200, 40); }
    else if (humbug) { lo = vec3f(214, 214, 210); hi = vec3f(250, 250, 246); fin = vec3f(240, 240, 236); }
    let k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    if (tail) {
        *c = fin;
        if (0.8f * tf + 0.04f - a < 0.06f) { *c *= 0.45f; }
    } else if (in_body) {
        *c = mix(lo, hi, k);
        let bar = (u > 0.20f && u < 0.26f) || (u > 0.45f && u < 0.52f) || (u > 0.70f && u < 0.75f);
        if (humbug && bar) { *c = vec3f(22, 22, 28); }
        if (!humbug && !yellow) { let hl = 1.0f - min(1.0f, abs(k - 0.3f) * 3.5f); *c += vec3f(12, 26, 20) * hl; }
        if (hw - a < min(0.07f, 0.4f * hw)) { *c *= 0.72f; }
        let eu = (u - 0.13f) / 0.075f; let ev = (sb + 0.16f) / 0.24f;
        let r2 = eu * eu + ev * ev;
        if (r2 < 1.0f) { *c = select(vec3f(176, 206, 206), vec3f(12, 12, 18), r2 < 0.45f); }
        if (u < 0.04f && abs(sb - 0.06f) < 0.035f) { *c = vec3f(70, 36, 34); }
    } else {
        *c = select(fin, vec3f(22, 22, 28), pelvic && humbug);
        if (hw + fh - a < 0.05f) { *c *= 0.6f; }
    }
    return true;
}

fn shadeFusilier(u: f32, s: f32, t: f32, c: ptr<function, vec3f>) -> bool {
    let sb = s - 0.22f * sin(t) * u * u;
    let a = abs(sb);
    let q = (u - 0.4f) / 0.4f;
    let ell = sqrt(saturate(1.0f - q * q));
    var hw = 0.0f;
    if (u >= 0.0f && u <= 0.4f) { hw = ell; } else if (u > 0.4f && u <= 0.8f) { hw = 0.12f + 0.88f * ell; }
    var tail = false;
    if (u > 0.8f && u <= 1.0f) {
        let tf = (u - 0.8f) / 0.2f;
        let outer = 0.14f + 0.72f * tf;
        let notch = 0.36f * max(0.0f, tf - 0.2f) / 0.8f;
        if (outer > hw && a > notch) { hw = outer; tail = true; }
    }
    var dors = 0.0f;
    if (sb < 0.0f && u > 0.26f && u < 0.64f) { dors = 0.24f * sin(M_PI_F * (u - 0.26f) / 0.38f); }
    let lim = hw + dors;
    if (a > lim) { return false; }
    let fin = dors > 0.0f && a > hw;
    let edge = lim - a < 0.07f;
    if (tail) { *c = vec3f(255, 204, 34); }
    else if (fin) { *c = vec3f(255, 222, 80); }
    else {
        let k = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
        let yel_mask = saturate((u - 0.12f) / 0.1f);
        let yw = max(yel_mask * saturate((0.42f - k) / 0.16f), saturate((u - 0.62f) / 0.12f) * saturate((0.70f - k) / 0.20f));
        let sw = saturate((k - 0.68f) / 0.16f);
        let bw = max(0.0f, 1.0f - yw - sw);
        *c = vec3f(yw * 255.0f + bw * 22.0f + sw * 222.0f, yw * 205.0f + bw * 112.0f + sw * 234.0f, yw * 34.0f + bw * 235.0f + sw * 246.0f);
    }
    if (edge) { *c *= 0.6f; }
    if (u < 0.04f && sb < -0.1f && sb > -0.17f) { *c = vec3f(40, 22, 20); }
    let eu = (u - 0.13f) / 0.035f; let ev = (sb + 0.25f) / 0.25f;
    let r2 = eu * eu + ev * ev;
    if (r2 < 1.0f) { *c = select(vec3f(240, 200, 110), vec3f(12, 12, 18), r2 < 0.45f); }
    return true;
}

fn cudaFin(u: f32, a: f32, hw: f32, uc: f32, wd: f32, fh: f32) -> bool {
    let d = abs(u - uc);
    if (d >= wd) { return false; }
    return a <= hw + fh * (1.0f - d / wd);
}

fn shadeBarracuda(u: f32, s: f32, t: f32, c: ptr<function, vec3f>) -> bool {
    let sb = s - 0.2f * sin(t) * u * u * u;
    let a = abs(sb);
    var hw = 0.0f; var tail = false;
    if (u >= 0.0f && u < 0.42f) { hw = 0.12f + 0.88f * sin(0.5f * M_PI_F * u / 0.42f); }
    else if (u >= 0.42f && u <= 0.86f) { let x = (u - 0.42f) / 0.44f; hw = 1.0f - 0.76f * x * x; }
    else if (u > 0.86f && u <= 1.0f) {
        let tf = (u - 0.86f) / 0.14f;
        if (a < 0.45f * tf * tf) { return false; }
        hw = 0.24f + 0.72f * tf; tail = true;
    }
    if (a > hw) {
        if (sb >= 0.0f) { return false; }
        if (cudaFin(u, a, hw, 0.46f, 0.10f, 0.38f) || cudaFin(u, a, hw, 0.80f, 0.07f, 0.30f)) { *c = vec3f(124, 128, 108); return true; }
        return false;
    }
    let q = clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    let k = 0.5f + 0.5f * q;
    *c = mix(vec3f(44, 58, 72), vec3f(176, 186, 194), saturate(k * 1.6f));
    *c = mix(*c, vec3f(236, 239, 241), saturate((k - 0.7f) * 3.3f));
    if (tail) { *c = select(vec3f(226, 196, 70), vec3f(70, 60, 34), u > 0.96f); }
    else if (k < 0.55f && u > 0.2f) {
        let p = (u - 0.2f) * 27.0f + 0.6f * q;
        if (p - floor(p) < 0.42f) { *c = mix(*c, vec3f(30, 36, 46), 0.85f * saturate((0.55f - k) * 3.0f)); }
    }
    if (u > 0.01f && u < 0.10f && sb > 0.05f && sb < 0.11f && fract(u * 60.0f) < 0.5f) { *c = vec3f(250, 250, 246); }
    if (hw - a < 0.08f) { *c *= 0.72f; }
    let eu = (u - 0.14f) / 0.04f; let ev = (sb + 0.2f) / 0.10f;
    let r2 = eu * eu + ev * ev;
    if (r2 < 1.0f && r2 >= 0.35f) { *c = vec3f(214, 178, 78); }
    if (r2 < 0.35f) { *c = vec3f(14, 14, 18); }
    return true;
}

fn inEll(u: f32, s: f32, cu: f32, cs: f32, ru: f32, rs: f32) -> bool {
    let du = (u - cu) / ru; let ds = (s - cs) / rs;
    return du * du + ds * ds < 1.0f;
}

fn shadeWhitetip(u: f32, s: f32, t: f32, c: ptr<function, vec3f>) -> bool {
    let sb = s - 0.30f * sin(t - 3.0f * u) * u * u;
    let a = abs(sb);
    var hw = 0.0f;
    if (u >= 0.0f && u <= 0.92f) {
        if (u < 0.20f) { let q = (0.20f - u) / 0.20f; hw = 0.9f * sqrt(max(0.0f, 1.0f - q * q)); }
        else if (u < 0.40f) { hw = 0.9f; }
        else if (u < 0.85f) { hw = 0.42f + 0.48f * cos((u - 0.40f) / 0.45f * 0.5f * M_PI_F); }
        else { hw = 0.42f * (0.92f - u) / 0.07f; }
    }
    let kl = 0.5f + 0.5f * clamp(sb / max(hw, 0.05f), -1.0f, 1.0f);
    let k = kl * kl * (3.0f - 2.0f * kl);
    if (inEll(u, sb, 0.07f, 0.60f, 0.06f, 0.16f)) { *c = vec3f(118, 112, 110); return true; }
    if (inEll(u, sb, 0.12f, -0.22f, 0.035f, 0.09f)) { *c = vec3f(14, 14, 20); return true; }
    *c = vec3f(70.0f + 156.0f * k, 66.0f + 158.0f * k, 60.0f + 156.0f * k);
    if (a <= hw) {
        if (inEll(u, sb, 0.27f, 0.10f, 0.016f, 0.07f) || inEll(u, sb, 0.33f, -0.30f, 0.016f, 0.07f) ||
            inEll(u, sb, 0.62f, 0.25f, 0.016f, 0.07f) || inEll(u, sb, 0.70f, -0.20f, 0.016f, 0.07f)) { *c = vec3f(58, 54, 52); }
        if (hw > 0.2f && hw - a < 0.06f) { *c *= 0.62f; }
        return true;
    }
    var dh = 0.0f;
    if (u >= 0.40f && u <= 0.64f) { dh = select(1.9f * (0.64f - u) / 0.14f, 1.9f * (u - 0.40f) / 0.10f, u <= 0.50f); }
    var fin = false; var white = false;
    if (-sb > hw && -sb <= dh) { fin = true; if (-sb > 1.45f) { white = true; } }
    if (inTri(u, sb, 0.74f, -0.5f, 0.84f, -0.5f, 0.78f, -0.95f)) { fin = true; }
    if (inTri(u, sb, 0.16f, 0.75f, 0.42f, 0.85f, 0.30f, 1.60f)) { fin = true; }
    if (inTri(u, sb, 0.72f, 0.45f, 0.84f, 0.45f, 0.80f, 0.95f)) { fin = true; }
    if (inTri(u, sb, 0.78f, -0.35f, 0.98f, -1.25f, 0.92f, 0.0f)) { fin = true; if (-sb > 0.95f) { white = true; } }
    if (inTri(u, sb, 0.78f, 0.35f, 0.96f, 0.80f, 0.92f, 0.0f)) { fin = true; if (sb > 0.60f) { white = true; } }
    if (white) { *c = vec3f(246, 246, 242); return true; }
    if (fin) { *c *= 0.9f; return true; }
    return false;
}

fn nurseFin(u: f32, v: f32, lead0: f32, trail0: f32, tip: f32, h: f32) -> bool {
    if (v < 0.35f || v > h) { return false; }
    let f = (v - 0.35f) / (h - 0.35f);
    return u >= lead0 + (tip - lead0) * f && u <= trail0 + (tip - trail0) * f * f;
}

fn shadeNurse(u: f32, s: f32, t: f32, c: ptr<function, vec3f>) -> bool {
    let sb = s - 0.25f * sin(t) * u * u;
    let a = abs(sb);
    let v = -sb;
    var hw = 0.0f;
    if (u >= 0.0f && u <= 0.80f) {
        let nose = sqrt(saturate(u / 0.16f));
        let tp = saturate((u - 0.55f) / 0.25f);
        hw = (1.10f - 0.55f * tp * tp * (3.0f - 2.0f * tp)) * nose;
    } else if (u > 0.80f && u <= 0.97f) { hw = 0.55f - 0.43f * saturate((u - 0.80f) / 0.17f); }
    let body = a <= hw && hw > 0.0f;
    if (u >= -0.025f && u < 0.0f && sb > 0.12f && sb < 0.22f) { *c = vec3f(200, 160, 118); return true; }
    var upper = false;
    if (u >= 0.76f && u <= 1.0f && v >= 0.0f) {
        let top = 1.45f * sqrt(saturate((u - 0.76f) / 0.24f));
        upper = v <= top && u <= 0.90f + 0.10f * saturate(v / 1.45f);
    }
    let lower = u >= 0.80f && u <= 0.95f && sb >= 0.0f && sb <= 0.30f * (1.0f - (u - 0.80f) / 0.15f);
    let fins = nurseFin(u, v, 0.36f, 0.58f, 0.62f, 1.95f) || nurseFin(u, v, 0.62f, 0.76f, 0.79f, 1.90f) ||
               nurseFin(u, sb, 0.12f, 0.36f, 0.38f, 2.10f) || nurseFin(u, sb, 0.58f, 0.66f, 0.68f, 1.60f) || upper || lower;
    if (!body && !fins) { return false; }
    let span = select(1.2f, max(hw, 0.05f), body);
    let k = 0.5f + 0.5f * clamp(sb / span, -1.0f, 1.0f);
    *c = vec3f(150.0f + 76.0f * k, 102.0f + 98.0f * k, 56.0f + 100.0f * k);
    if (!body) { *c *= 0.9f; }
    else {
        if (hw - a < 0.08f) { *c *= 0.7f; }
        if (u >= 0.05f && u <= 0.09f && sb >= 0.40f && sb <= 0.46f) { *c = vec3f(70, 45, 30); }
        let gu = (u - 0.20f) / 0.032f;
        if (gu >= 0.0f && gu <= 4.5f && fract(gu) < 0.30f && sb > -0.22f && sb < 0.05f) { *c = vec3f(60, 40, 28); }
        let eu = (u - 0.11f) / 0.016f; let ev = (sb + 0.30f) / 0.07f;
        if (eu * eu + ev * ev < 1.0f) { *c = vec3f(14, 12, 12); }
    }
    return true;
}

fn codHash(x: f32, y: f32) -> f32 { let v = sin(x * 12.9898f + y * 78.233f) * 43758.5453f; return v - floor(v); }

fn shadeCod(u: f32, s: f32, t: f32, seed: f32, c: ptr<function, vec3f>) -> bool {
    let sb = s - 0.25f * sin(t) * u * u;
    let a = abs(sb);
    var bh: f32;
    if (u < 0.35f) { let p = u / 0.35f; bh = 0.12f + 0.83f * sin(0.5f * M_PI_F * p) - 0.06f * sin(M_PI_F * p) * (1.0f - p); }
    else { let q = saturate((u - 0.35f) / 0.45f); bh = 0.95f - 0.5f * q * sqrt(q); }
    let bv = select(0.72f - 0.3f * saturate((u - 0.4f) / 0.4f), 0.1f + 0.62f * sin(0.5f * M_PI_F * saturate(u / 0.4f)), u < 0.4f);
    let fd = select(0.34f * sin(M_PI_F * (u - 0.3f) / 0.56f), 0.0f, u <= 0.3f || u >= 0.86f);
    let fa = select(0.26f * sin(M_PI_F * (u - 0.45f) / 0.41f), 0.0f, u <= 0.45f || u >= 0.86f);
    let body = u >= 0.0f && u <= 0.8f && sb >= -bh && sb <= bv;
    let dorsal = fd > 0.0f && sb <= -bh + 0.02f && sb >= -(bh + fd);
    let anal = fa > 0.0f && sb >= bv - 0.02f && sb <= bv + fa;
    let lat = 0.42f + 3.0f * (u - 0.8f);
    let back_edge = 1.04f - 0.08f * a * a;
    let tail = u >= 0.75f && u <= back_edge && a <= lat;
    let te = min(back_edge - u, lat - a);
    if (!body && !dorsal && !anal && !tail) { return false; }
    let k = saturate((sb + bh) / (bh + bv + 0.001f));
    *c = vec3f(168.0f + 70.0f * k, 184.0f + 52.0f * k, 166.0f + 56.0f * k);
    if (!body) { *c = *c * 0.5f + vec3f(214, 232, 220) * 0.5f; }
    if (u < 0.8f && ((dorsal && abs(sb + bh) < 0.03f) || (anal && abs(sb - bv) < 0.03f))) { *c *= 0.75f; }
    {   // round black spots
        let cu = u / 0.16f; let cs = sb / 0.67f;
        let iu = floor(cu); let is_ = floor(cs);
        let h1 = codHash(iu + 31.0f * seed, is_);
        if (h1 >= 0.45f) {
            let du = cu - iu - (0.35f + 0.3f * codHash(is_ + 7.1f, iu + 3.3f + 31.0f * seed));
            let ds = cs - is_ - (0.35f + 0.3f * codHash(iu + 1.7f, is_ + 5.5f + 31.0f * seed));
            let r = 0.16f + 0.06f * saturate((h1 - 0.45f) / 0.55f);
            if (du * du + ds * ds < r * r) { *c = vec3f(34, 30, 30); }
        }
    }
    let outline = select(u < 0.05f || min(sb + bh + fd, bv + fa - sb) < 0.08f, te < 0.05f, tail && u > 0.79f);
    if (outline) { *c *= 0.6f; }
    let eu = (u - 0.14f) / 0.045f; let ev = (sb + 0.2f) / 0.12f;
    let ed = eu * eu + ev * ev;
    if (ed < 0.6f) { *c = vec3f(16, 16, 20); } else if (ed < 1.0f) { *c = vec3f(222, 196, 110); }
    return true;
}

fn shadeSpecies(kind: i32, u: f32, s: f32, t: f32, seed: f32, c: ptr<function, vec3f>) -> bool {
    switch (kind) {
        case 0: { return shadeDamsel(u, s, t, seed, c); }
        case 1: { return shadeFusilier(u, s, t, c); }
        case 2: { return shadeBarracuda(u, s, t, c); }
        case 3: { return shadeClown(u, s, t, c); }
        case 4: { return shadeParrot(u, s, t, c); }
        case 5: { return shadeCod(u, s, t, seed, c); }
        case 6: { return shadeBlacktip(u, s, t, c); }
        case 7: { return shadeWhitetip(u, s, t, c); }
        case 8: { return shadeNurse(u, s, t, c); }
        default: { return shadeTurtle(u, s, t, c); }
    }
}

// ------------------------------------------------------------------ motion --

/// Where species s's school gathers in epoch e (40 s each): world x, height,
/// depth ahead of the camera at the epoch's start. Bommie or anemone if the
/// species has one, else a random spot ahead.
fn anchorFor(s: i32, e: i32, te: f32, st: texture_2d<f32>) -> vec4f {
    let sc = scrollAt(te);
    let cxe = channelX(sc + 4.0f);
    let h = argus_hash((bitcast<u32>(e) * 0x9E3779B9u) ^ ((u32(s) + 1u) * 0x85EBCA6Bu));
    var a = vec4f(cxe + (rnd(h, 0u) - 0.5f) * 12.0f, habitatY(SP_HAB[s]), 14.0f + 6.0f * rnd(h, 1u), 0.0f);
    let wz = sc + a.z;
    var best = 1e9f;
    if (SP_ANCHOR[s] == 1) {
        let icx = i32(floor(cxe / BCS)); let icz = i32(floor(wz / BCS));
        for (var dj = -2; dj <= 2; dj++) { for (var di = -2; di <= 2; di++) {
            let b = bommieCell(icx + di, icz + dj);
            if (!b.ok) { continue; }
            let dx = wrapD(b.x - cxe); let dz = wrapD(b.z - wz);
            let score = abs(dz) + 0.5f * abs(dx);
            if (abs(dx) < 9.0f && abs(dz) < 5.0f && score < best) {
                best = score;
                a.x = cxe + dx;
                a.z = max(8.0f, a.z + dz);
                a.y = hBilinear(st, b.x, b.z) + 0.4f + 2.0f * SP_LEN[s];
            }
        } }
    } else if (SP_ANCHOR[s] == 3) {
        // Green turtles graze seagrass at Lizard (eAtlas): find a meadow ahead
        // (the baked mat is green there) and keep low over it.
        for (var k = 0; k < 24; k++) {
            let cx = cxe + (rnd(h, 20u + u32(k)) - 0.5f) * 14.0f;
            let cz = a.z + (rnd(h, 50u + u32(k)) - 0.5f) * 10.0f;
            let zz = cz + sc;
            let m = textureLoad(st, vec2u(u32(i32(floor(wrap64(cx) * TEX)) & (MAP_N - 1)), u32(i32(floor(wrap64(zz) * TEX)) & (MAP_N - 1)) + 1u), 0);
            if (m.a < 0.6f && m.g - max(m.r, m.b * 1.2f) > 0.02f) {
                a.x = cx;
                a.z = max(6.0f, cz);
                a.y = hBilinear(st, cx, zz) + 0.45f;
                break;
            }
        }
    } else if (SP_ANCHOR[s] == 2) {
        for (var i = CORAL_ANEM0; i < CORAL_CLAM0; i++) {
            let d0 = textureLoad(st, vec2u(CORAL_COL0 + u32(i), BLK_ROW0), 0);
            let dx = wrapD(d0.x - cxe); let dz = wrapD(d0.y - wz);
            let score = abs(dz) + 0.5f * abs(dx);
            if (abs(dx) < 7.0f && abs(dz) < 8.0f && score < best) {
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
fn fishRel(s: i32, t: f32, tau: f32, an: vec4f, ao: vec4f, seed: f32, fh: u32, L: f32, v: f32) -> vec3f {
    let camx = camxAt(t);
    if (SP_SCHOOL[s] != 0) {
        // Each fish circles the school's anchor on its own phase, plus a fixed
        // place in the cloud and a slow wobble (the Zig's boids, in closed form).
        let graze = s == 9;   // turtles stay over their meadow, moving slowly side to side
        let R = select(0.6f + 2.0f * L, 2.2f, graze);
        var orb = vec3f(R * sin(ph(t, select(0.21f, 0.12f, graze)) + seed * 6.0f), select(0.4f * sin(ph(t, 0.13f) + f32(s)), 0.0f, graze),
                        R * cos(ph(t, select(0.17f, 0.12f, graze)) + seed * 6.0f));
        if (graze) { orb = vec3f(orb.x + select(1.4f, -1.4f, seed < 0.5f), orb.y, 0.3f * orb.z); }
        var sp = (vec3f(rnd(fh, 3u), rnd(fh, 4u), rnd(fh, 5u)) - 0.5f) * vec3f(1.4f * R, 0.6f * R + 0.3f, 1.4f * R);
        sp += 0.25f * R * vec3f(sin(ph(t, 0.37f + 0.2f * rnd(fh, 6u)) + TWO_PI * rnd(fh, 7u)),
                                0.5f * sin(ph(t, 0.29f) + TWO_PI * rnd(fh, 8u)),
                                sin(ph(t, 0.31f + 0.2f * rnd(fh, 9u)) + TWO_PI * rnd(fh, 10u)));
        let pn = vec3f(an.x - camx, an.y, an.z - CAM_SPEED * tau) + orb + sp;
        let po = vec3f(ao.x - camx, ao.y, ao.z - CAM_SPEED * (tau + 40.0f)) + orb + sp;
        // After the anchor moves on, the school swims to the new one; fish the
        // camera has passed rejoin it out in the haze.
        let D = length(vec3f(an.x - ao.x, an.y - ao.y, an.z - ao.z + CAM_SPEED * 40.0f));
        let vmax = max(2.4f * v, 0.6f);
        let lam = saturate((tau - 1.5f * seed) * vmax / max(D, 0.1f));
        var p = mix(po, pn, lam);
        if (lam < 1.0f && p.z < 0.7f) { p = pn; }
        return p;
    }
    if (s == 6) {
        // Blacktip reef sharks patrol the shallows along the shore (ISRA): here,
        // the shallow foot of the fringing reef, swimming up and down along it.
        let key = seed * 37.0f;
        let tz = 10.0f + 6.0f * fract(key * 0.618f) + 6.0f * sin(ph(t, 0.09f + 0.03f * seed) + key);
        let sc = scrollAt(t);
        let tx = (channelX(sc + tz) - camx) - 3.5f - 2.0f * seed + 0.6f * sin(ph(t, 0.23f) + key);
        return vec3f(tx, 0.6f, tz);
    }
    // Loners wander around a station that drifts along with the diver.
    let key = f32(s) * 1.7f + seed * 37.0f;
    let lane = fract(key * 0.618f);
    let tz = 4.0f + 14.0f * lane + 3.0f * sin(ph(t, 0.03f) + key * 1.3f);
    let tx = 0.45f * tz * sin(ph(t, 0.025f + 0.02f * seed) + key * 1.9f);
    let ty = habitatY(SP_HAB[s]) + 0.5f * sin(ph(t, 0.07f) + key * 2.3f);
    // Around it, a wide loop swum faster than the diver drifts, so they pass
    // across the view (the Zig's steering overshoots its target the same way).
    let rho = 0.8f + 1.0f * L;
    let om = max(1.2f * v, 0.6f) / (1.6f * rho);
    let a = select(-1.0f, 1.0f, seed < 0.5f) * ph(t, om) + seed * TWO_PI;
    return vec3f(tx + 2.2f * rho * sin(a), ty, tz + 0.8f * rho * cos(a));
}

// Per-frame animal and mote positions, computed once per frame in argus_step and
// stored (screen space, split into whole and fractional parts so RGBA16F keeps
// sub-pixel precision) in rows the reef does not use.
const FISH_ROW: u32 = 2052u;   // 2052..2055: fish i at column 32 + i
const SNOW_ROW: u32 = 2056u;   // mote i at column 32 + i
const CORAL_ROW: u32 = 2057u;  // 2057..2058: coral i this frame (screen circle, camera-relative place)
const FISH_RECT_ROW: u32 = 2059u;   // fish i's screen rect this frame (padded), for culling

fn splitf(v: f32) -> vec2f { let i = floor(v); return vec2f(i, v - i); }

// Metal's prev texture is the prev parameter (argus_state); its next texture is the
// prelude's argus_state_out.
fn fishStep(i: i32, S: Scene, prev: texture_2d<f32>) {
    let col = CORAL_COL0 + u32(i);
    textureStore(argus_state_out, vec2u(col, FISH_ROW + 3u), vec4f(0.0f));   // invalid until proven otherwise
    textureStore(argus_state_out, vec2u(col, FISH_RECT_ROW), vec4f(0.0f));
    var s = 0;
    for (var k = 1; k < N_SPECIES; k++) { if (i >= SP_START[k]) { s = k; } }
    let fh = argus_hash((u32(i) * 0x27D4EB2Du) ^ 0x51F1u);
    let seed = rnd(fh, 0u);
    let L = SP_LEN[s];
    let size = L * (0.85f + 0.3f * rnd(fh, 1u));
    let v = SP_SPEED[s] * L;
    let school = SP_SCHOOL[s] != 0;
    var an = vec4f(0.0f); var ao = vec4f(0.0f);
    var tau = 0.0f;
    if (school) {
        // The school's anchor this epoch and the last (40 s epochs, per-species offset).
        let hs = rnd(argus_hash(u32(s) + 0xA11u), 0u);
        let ts = S.t + 40.0f * hs;
        let e = floor(ts / 40.0f);
        tau = ts - 40.0f * e;
        an = anchorFor(s, i32(e), S.t - tau, prev);
        ao = anchorFor(s, i32(e) - 1, S.t - tau - 40.0f, prev);
    }
    var p = fishRel(s, S.t, tau, an, ao, seed, fh, L, v);
    let dts = select(0.1f, -0.1f, !school || tau > 0.2f);
    let p2 = fishRel(s, S.t + dts, tau + dts, an, ao, seed, fh, L, v);
    var vel = (p2 - p) / dts;
    vel.z += CAM_SPEED;   // reef fish hold station in the world while the diver drifts on
    if (SP_DUSK[s] != 0) { p.z = mix(42.0f, p.z, sstep(0.2f, 0.35f, max(S.gold, S.dim))); }   // in the haze until the light changes
    if (SP_SCHOOL[s] == 0) { p.z = max(p.z, 2.0f + 1.5f * L); }   // loners keep a little distance
    if (p.z < Z_NEAR + 0.25f || p.z > Z_FAR) { return; }
    // Keep clear of the reef below.
    let X = p.x + S.camx; let Zw = S.scroll + p.z;
    var g = hBilinear(prev, X, Zw);
    g = max(g, max(hBilinear(prev, X + 0.6f, Zw), hBilinear(prev, X - 0.6f, Zw)));
    g = max(g, max(hBilinear(prev, X, Zw + 0.6f), hBilinear(prev, X, Zw - 0.6f)));
    if (SP_HAB[s] == 0) { p.y = max(p.y, g + 0.3f + 0.5f * seed); }
    p.y = min(max(p.y, g + 0.15f + size * SP_HD[s]), SURFACE_Y - 1.0f);
    // Body axis: fish pitch only a little even when climbing.
    let hsp = length(vel.xz);
    let pv = clamp(0.3f * vel.y, -0.4f * hsp, 0.4f * hsp);
    var dir = vec3f(vel.x, pv, vel.z);
    let dl = length(dir);
    dir = select(vec3f(1.0f, 0.0f, 0.0f), dir / dl, dl > 1e-4f);
    let half_ = 0.5f * size;
    let ry = p.y - S.camy;
    var hd: vec2f; var tl: vec2f;
    if (!project(S, p.x + dir.x * half_, ry + dir.y * half_, p.z + dir.z * half_, &hd)) { return; }
    if (!project(S, p.x - dir.x * half_, ry - dir.y * half_, p.z - dir.z * half_, &tl)) { return; }
    let W = S.focal * size * SP_HD[s] / p.z;
    if (W < 0.4f) { return; }
    var ax = tl - hd;
    var Lp = length(ax);
    if (Lp < 1e-3f) { ax = vec2f(1.0f, 0.0f); Lp = 1.0f; } else { ax /= Lp; }
    let min_l = 2.2f * W;   // seen nose-on it still reads as an animal
    if (Lp < min_l) { let m = 0.5f * (hd + tl); Lp = min_l; hd = m - ax * 0.5f * Lp; }
    hd = clamp(hd, vec2f(-4000.0f), vec2f(6000.0f));
    let wag = rnd(fh, 2u) * TWO_PI + ph(S.t, 4.0f + 1.25f * SP_SPEED[s] * L / size);
    textureStore(argus_state_out, vec2u(col, FISH_ROW), vec4f(splitf(hd.x), splitf(hd.y)));
    textureStore(argus_state_out, vec2u(col, FISH_ROW + 1u), vec4f(ax, splitf(min(Lp, 4000.0f))));
    textureStore(argus_state_out, vec2u(col, FISH_ROW + 2u), vec4f(min(W, 4000.0f), wag, p.z, 0.0f));
    textureStore(argus_state_out, vec2u(col, FISH_ROW + 3u), vec4f(seed, f32(s), 1.0f, 0.0f));
    // The draw's culling rectangle, padded and rounded outward so the 16-bit
    // store can only make it bigger (the draw re-tests with the exact values).
    {
        let Lr = min(Lp, 4000.0f);
        let tlr = hd + ax * Lr;
        let pad = SP_EXT[s] * min(W, 4000.0f) + 2.0f;
        let lo = floor(min(hd, tlr) - pad) - 4.0f; let hi = ceil(max(hd, tlr) + pad) + 4.0f;
        textureStore(argus_state_out, vec2u(col, FISH_RECT_ROW), vec4f(clamp(lo, vec2f(-8000.0f), vec2f(8000.0f)), clamp(hi, vec2f(-8000.0f), vec2f(8000.0f))));
    }
}

fn coralStep(i: i32, S: Scene, prev: texture_2d<f32>) {
    let col = CORAL_COL0 + u32(i);
    textureStore(argus_state_out, vec2u(col, CORAL_ROW), vec4f(0.0f));
    let d1 = textureLoad(prev, vec2u(col, BLK_ROW0 + 1u), 0);
    if (d1.w < 0.5f) { return; }
    let d0 = textureLoad(prev, vec2u(col, BLK_ROW0), 0);
    let rz = wrap64(d0.y - S.scroll);
    if (rz < Z_NEAR + 0.3f || rz > Z_FAR) { return; }
    let rx = wrapD(d0.x - S.camx);
    if (abs(rx) > rz * 0.5f * S.w / S.focal + 1.5f) { return; }
    let ry = d0.z - S.camy;
    let size = d0.w;
    let kind = i32(d1.y + 0.5f);
    // A screen circle around everything the coral can draw.
    var cy = 0.0f; var rad = 0.0f;
    if (kind == 1) { cy = 0.5f * size; rad = 1.35f * size; }                          // branches reach ~1.3 x size
    else if (kind == 3) { cy = 0.4f * size; rad = 0.95f * size + 0.25f; }             // tentacles + surge
    else if (kind == 4) { let sh = 0.25f + 0.3f * size; cy = sh; rad = size + sh + 0.05f; }
    else { cy = 0.3f * size; rad = 1.05f * size; }
    var cc: vec2f;
    if (!project(S, rx, ry + cy, rz, &cc)) { return; }
    rad = rad * S.focal / rz + 3.0f;
    var rect = vec4f(cc - rad, cc + rad);
    if (kind == 1) {
        // Staghorn: the screen box of its actual branches.
        var visit: StagVisit;
        visit.mode = 0;
        visit.S = S; visit.rx = rx; visit.ry = ry; visit.rz = rz;
        visit.r2 = vec4f(1e9f, 1e9f, -1e9f, -1e9f);
        visit.ok = true;
        visit.k = S.focal / rz;
        stagGrow(stagSeed(u32(i)), size, &visit);
        if (visit.ok) { rect = visit.r2; }
    }
    if (rect.z < 0.0f || rect.x > S.w || rect.w < 0.0f || rect.y > S.h) { return; }
    textureStore(argus_state_out, vec2u(col, CORAL_ROW), clamp(rect, vec4f(-4000.0f), vec4f(6000.0f)));
    textureStore(argus_state_out, vec2u(col, CORAL_ROW + 1u), vec4f(rx, ry, rz, size));
}

fn snowStep(i: i32, S: Scene) {
    // Marine snow: suspended sediment drifting past, falling slowly.
    let h = argus_hash((u32(i) * 0x9E3779B1u) ^ 0x5A0Bu);
    let z = 0.6f + 14.0f * fract(rnd(h, 2u) - CAM_SPEED * S.t / 14.0f);
    let y = -1.0f + (SURFACE_Y + 1.0f) * fract(rnd(h, 1u) - 0.08f * S.t / (SURFACE_Y + 1.0f));
    let x = (2.0f * rnd(h, 0u) - 1.0f) * (0.6f * z + 1.0f) * 0.9f - 0.267f * cos(ph(S.t, 0.3f) + rnd(h, 3u) * TWO_PI);
    var o = vec4f(0.0f);
    var q: vec2f;
    if (project(S, x, y - S.camy, z, &q) && q.x >= 1.0f && q.y >= 1.0f && q.x < S.w - 1.0f && q.y < S.h - 1.0f) {
        o = vec4f(floor(q), floor(64.0f * exp(-0.14f * z) + 4.0f), select(0.0f, 1.0f, z < 6.0f));
    }
    textureStore(argus_state_out, vec2u(CORAL_COL0 + u32(i), SNOW_ROW), o);
}

@compute @workgroup_size(8, 8)
fn argus_step(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    if (gid.x >= CORAL_COL0 && gid.y >= FISH_ROW && gid.y <= CORAL_ROW + 1u) {
        let i = i32(gid.x - CORAL_COL0);
        if (gid.y == FISH_ROW && i < NUM_FISH) { fishStep(i, makeScene(f), argus_state); }
        else if (gid.y == SNOW_ROW && i < NUM_SNOW) { snowStep(i, makeScene(f)); }
        else if (gid.y == CORAL_ROW && i < NUM_CORAL) { coralStep(i, makeScene(f), argus_state); }
        return;
    }
    // The reef is static: build it over the first three frames, then leave it.
    if (f.frame > 2u) { return; }
    if (f.frame == 0u) {
        if (gid.y >= BLK_ROW0) { textureStore(argus_state_out, gid, textureLoad(argus_state, gid, 0)); return; }
        // Light it: Lambert from above, cavities darker, reds absorbed.
        let iu = i32(gid.x); let iv = i32((gid.y + u32(MAP_N) - 1u) % u32(MAP_N));
        let hc = hRead(argus_state, iu, iv);
        let gx = (hRead(argus_state, iu + 1, iv) - hRead(argus_state, iu - 1, iv)) * TEX * 0.5f;
        let gz = (hRead(argus_state, iu, iv + 1) - hRead(argus_state, iu, iv - 1)) * TEX * 0.5f;
        let inv = inverseSqrt(gx * gx + gz * gz + 1.0f);
        let lam = max(0.0f, (-gx * 0.30f + 0.88f + gz * 0.36f) * inv);
        let around = 0.25f * (hRead(argus_state, iu + 6, iv) + hRead(argus_state, iu - 6, iv) + hRead(argus_state, iu, iv + 6) + hRead(argus_state, iu, iv - 6));
        let cavity = clamp(1.0f + 1.6f * (hc - around), 0.55f, 1.15f);
        var lit = (0.42f + 0.80f * lam) * cavity * (0.92f + 0.03f * hc);
        let a = textureLoad(argus_state, gid, 0);
        // Seagrass (green albedo): the blades are one-texel spikes, so their slopes
        // would light as hard bright and dark facets that shimmer as the diver
        // drifts. Light the meadow almost flat instead, as a soft canopy is.
        if (a.g > a.r + 0.02f && a.g > a.b * 1.4f) { lit = mix(lit, 0.98f, 0.8f); }
        textureStore(argus_state_out, gid, vec4f(saturate(a.rgb * lit * vec3f(0.84f, 1.0f, 1.02f)), a.a));
        return;
    }
    if (f.frame == 1u && gid.y >= BLK_ROW0) {
        if (gid.x < u32(BLK_N)) {
            // Tallest point in each block, one texel of margin for bilinear taps.
            let bx = i32(gid.x) * BLK_T; let bz = i32(gid.y - BLK_ROW0) * BLK_T;
            var m = -1.0e9f;
            for (var v = -1; v <= BLK_T; v++) {
                for (var u = -1; u <= BLK_T; u++) { m = max(m, hRead(argus_state, bx + u, bz + v)); }
            }
            textureStore(argus_state_out, gid, vec4f(m));
            return;
        }
        let i = i32(gid.x - CORAL_COL0);
        if (i < NUM_CORAL && gid.y <= BLK_ROW0 + 1u) {
            var extra: vec4f;
            var p = coralPlace(i, &extra);
            p.z = hBilinear(argus_state, p.x, p.y) - 0.02f;
            textureStore(argus_state_out, gid, select(extra, p, gid.y == BLK_ROW0));
            return;
        }
    }
    textureStore(argus_state_out, gid, textureLoad(argus_state, gid, 0));
}

// ------------------------------------------------------------- the drawing --

const FCAP: u32 = 128u;
const CCAP: u32 = 64u;
const SCAP: u32 = 96u;

/// Staghorn Acropora: regrows the Zig's random branching (<= 40 segments) and
/// tests the pixel against each segment's thick projected line.
fn stagHit(pp: vec2f, S: Scene, rx: f32, ry: f32, rz: f32, size: f32, seed: u32, style: i32, col: ptr<function, vec3f>) -> bool {
    let k = S.focal / rz;
    var visit: StagVisit;
    visit.mode = 1;
    visit.S = S; visit.rx = rx; visit.ry = ry; visit.rz = rz; visit.k = k;
    visit.pp = pp;
    visit.hit = -1;
    stagGrow(seed, size, &visit);
    let hit = visit.hit;
    if (hit < 0) { return false; }
    let t = f32(hit) / 4.0f;
    *col = fogged(mix(STAG_BASE[style], STAG_TIP[style], t * t), rz);
    return true;
}

fn anemHit(pp: vec2f, S: Scene, rx: f32, ry: f32, rz: f32, size: f32, cph: f32, style: i32, col: ptr<function, vec3f>) -> bool {
    let k = S.focal / rz;
    var b2: vec2f; var t2: vec2f;
    if (project(S, rx, ry, rz, &b2) && project(S, rx, ry + 0.2f * size, rz, &t2) && onLine(pp, b2, t2, 0.45f * size * k)) {
        *col = fogged(ANEM_COLUMN[style], rz);
        return true;
    }
    let phs = ph(S.t, 0.8f) + cph;
    let surge = 0.12f * sin(ph(S.t, 0.35f) + cph);
    let thick = 0.085f * size * k;
    for (var ti = 0; ti < 22; ti++) {
        let a = TWO_PI * (f32(ti) + 0.5f) / 22.0f;
        let ca = cos(a); let sa = sin(a);
        var prev: vec2f; var have = false;
        for (var j = 0; j < 5; j++) {
            let kf = f32(j) / 4.0f;
            let o = size * (0.25f + 0.55f * kf);
            let up = size * (0.15f + 0.75f * kf - 0.35f * kf * kf);
            let wav = kf * (0.10f * sin(phs + a * 2.0f - kf * 3.0f) + surge);
            var q: vec2f;
            if (!project(S, rx + ca * o + wav, ry + up, rz + sa * o, &q)) { have = false; continue; }
            if (have && onLine(pp, prev, q, thick * (1.0f - 0.4f * kf))) {
                *col = fogged(mix(ANEM_BASE[style], ANEM_TIP[style], kf * kf), rz);
                return true;
            }
            prev = q; have = true;
        }
    }
    return false;
}

fn tableHit(pp: vec2f, S: Scene, rx: f32, ry: f32, rz: f32, size: f32, cph: f32, style: i32, col: ptr<function, vec3f>) -> bool {
    let stalk_h = 0.25f + 0.3f * size;
    var b2: vec2f; var p2: vec2f;
    if (!project(S, rx, ry, rz, &b2) || !project(S, rx, ry + stalk_h, rz, &p2)) { return false; }
    let k = S.focal / rz;
    let c = TABLE_COLS[style];
    if (onLine(pp, b2, p2, 0.12f * k)) { *col = fogged(c * 0.6f, rz); return true; }
    let elev = clamp(-(ry + stalk_h) * inverseSqrt(rz * rz + (ry + stalk_h) * (ry + stalk_h)), -1.0f, 1.0f);
    let ax = size * k; let ay = ax * max(0.1f, abs(elev));
    if (ax < 0.5f || ay < 0.3f) { return false; }
    // The plate's edge thickness first (it wins where they overlap, as in the Zig), then the plate.
    for (var pass_ = 0; pass_ < 2; pass_++) {   // `pass` is reserved in WGSL
        let cc = select(p2, p2 + vec2f(0.0f, 0.035f * k), pass_ == 0);
        let nx = (pp.x - cc.x) / ax; let ny = (pp.y - cc.y) / ay;
        let r2 = nx * nx + ny * ny;
        if (r2 > 1.0f) { continue; }
        let above = pass_ == 1 && elev > 0.0f;
        let base = select(c, c * 0.5f, pass_ == 0);
        let rib = 0.9f + 0.1f * sin(atan2(ny, nx) * 26.0f + cph);
        let rim = select(1.0f, 1.25f, r2 > 0.82f);
        let lv = select(0.45f * rim, rib * rim, above);
        *col = fogged(min(base * lv, vec3f(255.0f)), rz);
        return true;
    }
    return false;
}

fn clamHit(pp: vec2f, S: Scene, rx: f32, ry: f32, rz: f32, size: f32, cph: f32, style: i32, col: ptr<function, vec3f>) -> bool {
    var cc: vec2f;
    if (!project(S, rx, ry + 0.3f * size, rz, &cc)) { return false; }
    let k = S.focal / rz;
    let len = size * k;
    if (len < 1.0f) { return false; }
    let elev = clamp(-ry * inverseSqrt(rz * rz + ry * ry), -1.0f, 1.0f);
    let open = 0.65f + 0.35f * sin(ph(S.t, 0.09f) + cph);
    let ax = len; let ay = len * (0.25f + 0.35f * abs(elev)) * (0.6f + 0.4f * open);
    if (ay < 0.3f) { return false; }
    let nx = (pp.x - cc.x) / ax; let ny = (pp.y - cc.y) / ay;
    let r = sqrt(nx * nx + ny * ny);
    if (r > 1.0f) { return false; }
    let gigas = style == 4;
    let phc = cph * 3.0f;
    let wave = 0.06f * sin(atan2(ny, nx) * select(11.0f, 7.0f, gigas) + phc);
    var c3: vec3f;
    if (r > 0.84f + wave) { c3 = select(vec3f(120, 116, 100), vec3f(196, 190, 170), gigas); }   // fluted shell lip
    else if (abs(ny) < 0.07f * open && abs(nx) < 0.6f) { c3 = vec3f(20, 24, 30); }       // inhalant slit
    else {
        let spot = sin(nx * 23.0f + phc) * sin(ny * 19.0f - phc);
        let glow = select(1.0f, 1.45f, spot > 0.55f);
        let edge = select(1.0f, 1.25f, r > 0.7f);
        c3 = min(MANTLE_COLS[style] * glow * edge, vec3f(255.0f));
    }
    *col = fogged(c3, rz);
    return true;
}

/// The Zig's depth slices form one lattice for the whole frame: 12 mm steps
/// near the camera, then 1.7% of depth. A ray resuming after a skipped block
/// snaps back onto it, so neighbouring pixels sample the same depths.
const Z_LIN: f32 = 0.012f / 0.017f;
fn snapSlice(z: f32) -> f32 {
    if (z <= Z_LIN) { return Z_NEAR + 0.012f * ceil((z - Z_NEAR) / 0.012f); }
    let lg = log2(1.0f + Z_GROW);
    return Z_LIN * exp2(ceil(log2(z / Z_LIN) / lg) * lg);
}

// ---------------------------------------------------------------- seagrass --
// Thalassia / Halodule blades as real straps on a fixed 6 cm world grid: each
// has its own place, height (10-32 cm) and phase, leans with the surge running
// shoreward and wobbles a little. A pixel tests the blades that stand between the
// eye and the ground it sees; their edges are anti-aliased, so a blade too thin
// for a pixel fades rather than pops, and beyond ~9 m they fade into the mat.
const GRASS_CELL: f32 = 0.06f;
const GRASS_Z: f32 = 9.0f;
const GRASS_HMAX: f32 = 0.44f;   // tallest blade plus its lean

/// How dense the blades are at a lagoon point, read from the mat's green (0 off the meadows).
fn grassDensity(sm: vec4f) -> f32 {
    if (sm.a > 0.6f) { return 0.0f; }   // lagoon floor only: no blades on the bommies
    return saturate((sm.g - max(sm.r, sm.b * 1.2f)) * 14.0f);
}

/// The nearest blade in front of the ground hit at depth zhit, if any: its depth,
/// colour and coverage of this pixel.
fn seagrass(st: texture_2d<f32>, S: Scene, rk: f32, ry: f32, zhit: f32,
            zg: ptr<function, f32>, cg: ptr<function, vec3f>, cov: ptr<function, f32>) -> bool {
    if (ry >= -1e-4f || zhit > GRASS_Z) { return false; }
    let gh = S.camy + ry * zhit;           // height where the ray lands
    if (gh > 0.6f) { return false; }                   // it lands high on a rock: blades are below it
    // Blades stand on the sand at their own place, which is never above ~0.25 m;
    // where the ray lands on a rock's foot, the sand in front is lower than the hit.
    var z0 = max(Z_NEAR, zhit - (GRASS_HMAX + max(gh - 0.25f, 0.0f)) / -ry);
    // Most pixels see bare sand: skip them unless the ray's ground track meets a meadow.
    let zm = 0.5f * (z0 + zhit);
    if (grassDensity(reefAt(st, S.camx + rk * zhit, S.scroll + zhit)) <= 0.0f &&
        grassDensity(reefAt(st, S.camx + rk * zm, S.scroll + zm)) <= 0.0f &&
        grassDensity(reefAt(st, S.camx + rk * z0, S.scroll + z0)) <= 0.0f) { return false; }
    // Over Halophila only (no strap blade can stand anywhere along this stretch:
    // the meadow type changes over metres), the plants are under 9 cm, so the
    // rows the ray passes high above them needn't be visited at all.
    if (max(strapness(S.camx + rk * zhit, S.scroll + zhit), strapness(S.camx + rk * z0, S.scroll + z0)) < 0.2f) {
        z0 = max(z0, zhit - (0.09f + 0.10f + max(gh - 0.25f, 0.0f)) / -ry);
    }
    let px = 1.0f / S.focal;   // metres per pixel per metre of depth
    let t = S.t;
    let r0 = i32(floor((S.scroll + z0) / GRASS_CELL));
    let r1 = i32(floor((S.scroll + zhit) / GRASS_CELL));
    var found = false;
    for (var iz = r0; iz <= r1 && iz < r0 + 40; iz++) {
        let zr = (f32(iz) + 0.5f) * GRASS_CELL - S.scroll;   // this row's depth
        let xr = S.camx + rk * zr;
        let rs = reefAt(st, xr, S.scroll + zr);
        let dens = grassDensity(rs);
        if (dens <= 0.0f) { continue; }
        // Meadow type for this 6 cm row (it changes over metres, not centimetres),
        // and the tallest plant it can hold: skip rows the ray passes over.
        let sr = strapness(xr, S.scroll + zr);
        let hrow = select(0.07f + 0.02f, 0.36f + 0.08f, sr > 0.3f);
        if (S.camy + ry * zr - rs.a > hrow + 0.10f) { continue; }
        let ix0 = i32(floor(xr / GRASS_CELL));
        for (var ix = ix0 - 1; ix <= ix0 + 1; ix++) {
            let h = argus_hash((u32(ix + 1000000) * 0x9E3779B1u) ^ argus_hash(u32(iz + 1000000)));
            let q0 = f32(h & 0xFFu) / 255.0f; let q1 = f32((h >> 8u) & 0xFFu) / 255.0f;
            let q2 = f32((h >> 16u) & 0xFFu) / 255.0f; let q3 = f32(h >> 24u) / 255.0f;
            if (q0 > 0.8f * dens) { continue; }   // no blade in this cell
            let bx = (f32(ix) + 0.15f + 0.7f * q1) * GRASS_CELL;   // world x
            let bzw = (f32(iz) + 0.15f + 0.7f * q2) * GRASS_CELL;  // world z
            let bz = bzw - S.scroll;
            if (bz < Z_NEAR || bz > zhit + 0.05f) { continue; }
            // Strap-leaved Halodule/Thalassia only in the shallows at the foot of the
            // fringing reef; Halophila (a pair of small oval leaves on a short stalk)
            // everywhere else in the lagoon.
            let strap = sr > 0.5f + 0.3f * (q2 - 0.5f);
            let H = select(0.03f + 0.04f * q3, 0.12f + 0.24f * q3, strap);
            // Each blade is planted on the ground at its own spot, and only where
            // that spot is meadow (not rock): near a coral head the ray lands on the
            // rock, and planting blades there stretched them up its face.
            let at = reefAt(st, bx, bzw);
            if (grassDensity(at) <= 0.0f) { continue; }
            let gb = at.a - 0.01f;
            // The surge leans it shoreward and back; a faster wobble on top.
            let lscale = select(0.25f, 1.0f, strap);   // short Halophila barely leans
            let lean_z = lscale * (0.06f * sin(1.25f * t - 0.9f * bzw + 6.0f * q1) + 0.015f * sin(3.3f * t + 9.0f * q2));
            let lean_x = lscale * 0.035f * sin(0.9f * t + 0.7f * bx + 6.0f * q3);
            // Where the ray meets this blade: solve for the height up it (two passes).
            var z = bz; var u = 0.0f;
            for (var k = 0; k < 2; k++) {
                u = (S.camy + ry * z - gb) / H;
                let uc = saturate(u);
                z = bz + lean_z * uc * uc;
            }
            u = (S.camy + ry * z - gb) / H;
            if (u < 0.0f || u > 1.0f || z >= zhit || (found && z >= *zg)) { continue; }
            var dx = (S.camx + rk * z) - (bx + lean_x * u * u);
            var halfw = 0.0055f * (1.0f - 0.6f * u * u);
            if (!strap) {
                // A thin stalk, then two oval leaves splayed left and right.
                let leaf = sstep(0.35f, 0.55f, u);
                let lu = saturate((u - 0.4f) / 0.6f);
                let lw = 0.0055f * sqrt(max(0.0f, 1.0f - (2.0f * lu - 1.0f) * (2.0f * lu - 1.0f)));
                let off = 0.007f * leaf;
                let dl = min(abs(dx - off), abs(dx + off));
                if (leaf > 0.0f && lw > 0.0011f && dl < abs(dx)) { dx = dl; halfw = lw; } else { halfw = 0.0011f; }
            }
            let c = saturate((halfw - abs(dx)) / (z * px) + 0.5f) * (1.0f - sstep(GRASS_Z - 2.0f, GRASS_Z, z));
            if (c <= 0.02f) { continue; }
            found = true;
            *zg = z;
            *cov = c;
            let base_c = select(vec3f(86, 128, 70) / 255.0f, vec3f(64, 104, 56) / 255.0f, strap);
            let tip_c = select(mix(vec3f(122, 170, 96), vec3f(138, 160, 92), q2) / 255.0f,
                               mix(vec3f(112, 150, 82), vec3f(126, 128, 76), q2) / 255.0f, strap);
            *cg = mix(base_c, tip_c, u) * (0.85f + 0.3f * q0);
            *cg = mix(*cg, WATER_HOR, 1.0f - exp(-FOG_K * z));
        }
        if (found) { break; }   // rows run front to back: the first blade found is the nearest
    }
    return found;
}

/// Marches the pixel's ray over the baked heightfield at the Zig's slice spacing.
fn marchReef(st: texture_2d<f32>, S: Scene, rk: f32, ry: f32, zhit: ptr<function, f32>, col: ptr<function, vec3f>) -> bool {
    var zend = Z_FAR;
    if (ry > 1e-5f) { zend = min(zend, (H_BOUND - S.camy) / ry); }
    var z = Z_NEAR; var zp = Z_NEAR;
    var sm = vec4f(0.0f);
    var hit = false;
    var it = 0;
    while (z < zend && it < 480) {
        it++;
        let X = S.camx + rk * z; let Zw = S.scroll + z;
        let bxf = floor(X / BLK_M); let bzf = floor(Zw / BLK_M);
        var zx = 1e9f;
        if (rk > 1e-6f) { zx = ((bxf + 1.0f) * BLK_M - S.camx) / rk; }
        else if (rk < -1e-6f) { zx = (bxf * BLK_M - S.camx) / rk; }
        let zexit = min(min(zx, (bzf + 1.0f) * BLK_M - S.scroll), zend);
        let bm = textureLoad(st, vec2u(u32(i32(bxf) & (BLK_N - 1)), BLK_ROW0 + u32(i32(bzf) & (BLK_N - 1))), 0).a;
        if (S.camy + ry * select(z, zexit, ry < 0.0f) > bm) {   // the ray clears this whole block
            zp = zexit;
            z = snapSlice(zexit + 1e-4f);
            continue;
        }
        while (z < zexit + 1e-4f && it < 480) {
            it++;
            sm = reefAt(st, S.camx + rk * z, S.scroll + z);
            if (S.camy + ry * z < sm.a) { hit = true; break; }
            zp = z;
            z = select(z * (1.0f + Z_GROW), z + 0.012f, z < Z_LIN);
        }
        if (hit) { break; }
    }
    if (!hit) { return false; }
    // Find where the ray really meets the surface between the last two samples,
    // walls included: bisect on the height field. Its baked lighting already
    // shades the slopes, so the coral heads' sides keep their own colour instead
    // of a streak smeared down from the column top (which re-cut itself every
    // frame as the diver drifted, so the heads seemed to dance).
    if (zp < z) {
        var za = zp; var zb = z;
        for (var k = 0; k < 5; k++) {
            let zm = 0.5f * (za + zb);
            let s2 = reefAt(st, S.camx + rk * zm, S.scroll + zm);
            if (S.camy + ry * zm < s2.a) { zb = zm; sm = s2; } else { za = zm; }
        }
        z = zb;
    }
    var c = sm.rgb;
    // Caustics: a moving net of light from the surface, fading with depth.
    let wx = S.camx + rk * z; let wz = S.scroll + z;
    let caus_z = sin(wz * 22.0f * KK - ph(S.t, 0.5f));
    let caus = max(0.0f, sin(wx * 26.0f * KK + ph(S.t, 0.7f) + 0.6f * caus_z) * caus_z);
    c = min(c * ((220.0f + 120.0f * caus * caus * max(0.0f, 1.0f - z / 40.0f)) / 256.0f), vec3f(1.0f));
    c = mix(c, WATER_HOR, 1.0f - exp(-FOG_K * z));
    *zhit = z;
    *col = c;
    return true;
}

// The tiled draw. Metal runs it in threadgroups of threadExecutionWidth x
// (maxTotalThreads / width), 32 x 32 on Apple GPUs; here a workgroup is DRAW_TG x DRAW_TG
// (16 x 16 = 256 invocations, 9,996 bytes of workgroup memory: inside WebGPU's default
// limits). The tile only bounds the cull; each pixel re-tests every listed item exactly.
const DRAW_TG: u32 = 16u;
const DRAW_THREADS: u32 = DRAW_TG * DRAW_TG;

var<workgroup> fA: array<vec4f, FCAP>;
var<workgroup> fB: array<vec4f, FCAP>;
var<workgroup> fC: array<vec2f, FCAP>;
var<workgroup> cA: array<vec4f, CCAP>;
var<workgroup> cB: array<vec4f, CCAP>;
var<workgroup> cC: array<vec4f, CCAP>;
var<workgroup> cZ: array<f32, CCAP>;
var<workgroup> sA: array<vec4f, SCAP>;
var<workgroup> nF: atomic<u32>;
var<workgroup> nC: atomic<u32>;
var<workgroup> nS: atomic<u32>;

@compute @workgroup_size(DRAW_TG, DRAW_TG)
fn argus_draw(@builtin(global_invocation_id) id: vec3u,
              @builtin(local_invocation_id) tpos: vec3u,
              @builtin(local_invocation_index) tidx: u32) {
    let gid = id.xy;
    let S = makeScene(f);
    let nthreads = DRAW_THREADS;
    let tlo = vec2f(gid - tpos.xy);
    let thi = tlo + vec2f(f32(DRAW_TG), f32(DRAW_TG));

    if (tidx == 0u) {
        atomicStore(&nF, 0u);
        atomicStore(&nC, 0u);
        atomicStore(&nS, 0u);
    }
    workgroupBarrier();

    // ---- cull: each invocation places a few animals, corals and motes, keeps those on this tile ----
    for (var i = tidx; i < u32(NUM_FISH); i += nthreads) {
        let fr = textureLoad(argus_state, vec2u(CORAL_COL0 + i, FISH_RECT_ROW), 0);
        if (fr.z <= fr.x || fr.z < tlo.x || fr.x > thi.x || fr.w < tlo.y || fr.y > thi.y) { continue; }
        let t3 = textureLoad(argus_state, vec2u(CORAL_COL0 + i, FISH_ROW + 3u), 0);
        if (t3.z < 0.5f) { continue; }
        let t0 = textureLoad(argus_state, vec2u(CORAL_COL0 + i, FISH_ROW), 0);
        let t1 = textureLoad(argus_state, vec2u(CORAL_COL0 + i, FISH_ROW + 1u), 0);
        let t2 = textureLoad(argus_state, vec2u(CORAL_COL0 + i, FISH_ROW + 2u), 0);
        let hd = vec2f(t0.x + t0.y, t0.z + t0.w);
        let Lp = t1.z + t1.w;
        let tl = hd + t1.xy * Lp;
        let kind = i32(t3.y + 0.5f);
        let pad = SP_EXT[kind] * t2.x + 2.0f;
        let lo = min(hd, tl) - pad; let hi = max(hd, tl) + pad;
        if ((hi.x - lo.x) * (hi.y - lo.y) > 1100.0f * 1100.0f) { continue; }
        if (hi.x < tlo.x || lo.x > thi.x || hi.y < tlo.y || lo.y > thi.y) { continue; }
        let slot = atomicAdd(&nF, 1u);
        if (slot >= FCAP) { continue; }
        let belly = select(-1.0f, 1.0f, t1.x >= 0.0f);
        fA[slot] = vec4f(hd, t1.xy);
        fB[slot] = vec4f(1.0f / Lp, belly / max(t2.x, 1e-3f), t2.y, t2.z);
        fC[slot] = t3.xy;
    }
    for (var i = tidx; i < u32(NUM_CORAL); i += nthreads) {
        let cc = textureLoad(argus_state, vec2u(CORAL_COL0 + i, CORAL_ROW), 0);   // screen rect
        if (cc.z <= cc.x) { continue; }
        if (cc.z < tlo.x || cc.x > thi.x || cc.w < tlo.y || cc.y > thi.y) { continue; }
        let slot = atomicAdd(&nC, 1u);
        if (slot >= CCAP) { continue; }
        cA[slot] = textureLoad(argus_state, vec2u(CORAL_COL0 + i, CORAL_ROW + 1u), 0);
        let d1 = textureLoad(argus_state, vec2u(CORAL_COL0 + i, BLK_ROW0 + 1u), 0);
        cB[slot] = vec4f(d1.x, d1.y, d1.z, f32(i));
        let ca = cA[slot];
        let kind = i32(d1.y + 0.5f);
        cC[slot] = cc;
        cZ[slot] = select(select(ca.z, ca.z - 0.05f, kind == 5), ca.z - 0.2f * ca.w, kind == 4);
    }
    for (var i = tidx; i < u32(NUM_SNOW); i += nthreads) {
        let m = textureLoad(argus_state, vec2u(CORAL_COL0 + i, SNOW_ROW), 0);
        if (m.z <= 0.0f) { continue; }
        if (m.x + 1.0f < tlo.x || m.x >= thi.x || m.y + 1.0f < tlo.y || m.y >= thi.y) { continue; }
        let slot = atomicAdd(&nS, 1u);
        if (slot >= SCAP) { continue; }
        sA[slot] = m;
    }
    workgroupBarrier();
    if (gid.x >= f.width || gid.y >= f.height) { return; }

    // ---- this pixel ----
    let pp = vec2f(gid) + 0.5f;
    let rk = (pp.x - 0.5f * S.w) / S.focal;
    let ry = (S.hor - pp.y) / S.focal;
    var bestZ = 1e9f;
    var col = vec3f(0.0f);
    var drawn = marchReef(argus_state, S, rk, ry, &bestZ, &col);
    if (drawn) {
        var zg: f32; var cv: f32;
        var cgr: vec3f;
        if (seagrass(argus_state, S, rk, ry, bestZ, &zg, &cgr, &cv)) {
            col = mix(col, cgr, cv);
            if (cv > 0.5f) { bestZ = zg; }
        }
    }

    let nc = min(atomicLoad(&nC), CCAP);
    for (var j = 0u; j < nc; j++) {
        if (cZ[j] >= bestZ) { continue; }
        let cc = cC[j];
        if (pp.x < cc.x || pp.x > cc.z || pp.y < cc.y || pp.y > cc.w) { continue; }
        let a = cA[j]; let b = cB[j];
        let kind = i32(b.y + 0.5f); let style = i32(b.z + 0.5f);
        var c: vec3f;
        var h = false;
        if (kind == 1) { h = stagHit(pp, S, a.x, a.y, a.z, a.w, stagSeed(u32(b.w)), style, &c); }
        else if (kind == 3) { h = anemHit(pp, S, a.x, a.y, a.z, a.w, b.x, style, &c); }
        else if (kind == 4) { h = tableHit(pp, S, a.x, a.y, a.z, a.w, b.x, style, &c); }
        else { h = clamHit(pp, S, a.x, a.y, a.z, a.w, b.x, style, &c); }
        if (h) { bestZ = cZ[j]; col = c; drawn = true; }
    }
    let nf = min(atomicLoad(&nF), FCAP);
    for (var j = 0u; j < nf; j++) {
        let b = fB[j];
        if (b.w >= bestZ) { continue; }
        let a = fA[j];
        let c2 = fC[j];
        let kind = i32(c2.y + 0.5f);
        let dp = pp - a.xy;
        let u = (dp.x * a.z + dp.y * a.w) * b.x;
        let s = (dp.y * a.z - dp.x * a.w) * b.y;
        if (u < -0.05f || u > 1.05f || abs(s) > SP_EXT[kind]) { continue; }
        var c: vec3f;
        if (shadeSpecies(kind, u, s, b.z, c2.x, &c)) { bestZ = b.w; col = fogged(c, b.w); drawn = true; }
    }

    // ---- water, light shafts, the sun's colour ----
    let ny = floor(pp.y) / S.h;
    let top = vec3f(74, 138, 146) / 255.0f; let bot = vec3f(18, 54, 62) / 255.0f;
    let bg = select(mix(WATER_HOR, bot, pow(max((ny - HORIZON) / (1.0f - HORIZON), 1e-6f), 0.7f)),
                    mix(top, WATER_HOR, pow(max(ny / HORIZON, 1e-6f), 0.8f)), ny < HORIZON);
    var gain = 110.0f * exp(-2.0f * ny) * (1.0f - sstep(0.6f, 1.0f, ny)) / 256.0f;
    if (drawn) { gain *= 0.5f; } else { col = bg; }
    let sc = 1200.0f / S.h;   // ray pattern in 1200-line pixels
    let ru = floor(pp.x * sc) + floor(floor(pp.y * sc) * 26.0f / 64.0f);
    let b1 = 0.5f + 0.5f * sin(ru * 0.0062f + ph(S.t, 0.13f));
    let b2 = 0.5f + 0.5f * sin(ru * 0.0147f - ph(S.t, 0.21f) + 1.7f);
    let b3 = 0.5f + 0.5f * sin(ru * 0.0310f + ph(S.t, 0.47f) + 0.4f);
    var rv = b1 * b2 * (0.55f + 0.45f * b3);
    rv = min(1.0f, rv * rv * 1.7f);
    // Shaft colour: pale cyan at noon, warm gold at sunset and sunrise.
    let ray_col = vec3f(110.0f + 140.0f * S.gold, 190.0f - 20.0f * S.gold, 200.0f - 110.0f * S.gold) / 256.0f;
    col += rv * gain * ray_col;
    // Under water the sunset is mostly a dimming; dusk sinks to a deep blue.
    let tint = vec3f(1.0f - 0.18f * S.gold - 0.62f * S.dim, 1.0f - 0.20f * S.gold - 0.52f * S.dim, 1.0f - 0.10f * S.gold - 0.34f * S.dim);
    col = min(col * tint, vec3f(1.0f));

    // ---- marine snow drifts in front ----
    let ns = min(atomicLoad(&nS), SCAP);
    let pi = floor(pp);
    for (var j = 0u; j < ns; j++) {
        let m = sA[j];
        let d = pi - m.xy;
        let ext = select(0.0f, 1.0f, m.w > 0.5f);
        if (d.x >= 0.0f && d.y >= 0.0f && d.x <= ext && d.y <= ext) {
            let lum = m.z;
            col += vec3f(floor(lum * 0.5f), floor(lum * 0.75f), lum) / 255.0f;
        }
    }
    textureStore(argus_out, gid, vec4f(saturate(col), 1.0f));
}

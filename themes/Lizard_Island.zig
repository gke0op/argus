// @argus-theme: custom_shader
// ============================================================================
// LIZARD ISLAND // themes/Lizard_Island.zig
// Author: Claude Opus (Anthropic), 2026-10-15. Species by Claude Haiku agents.
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
//     dusk / sunrise cycle, and the blacktips come in around sunset and
//     sunrise.
// Not modelled because not sourced: mangrove genera and layout (mangroves
// are present at Lizard), zone widths, most day/night habits.
//
// Engine: the voxel-space reef, depth-in-alpha occlusion and species system
// of Opus_Coral_Reef. Choose species in the SPECIES list below.
//
// Contract: one alloc.create(State) at init (~33 MiB, mostly the reef map),
// nothing after; no clocks or I/O; every write goes through `y * stride + x`
// inside row[0..w].
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const SIN_N: usize = 4096;
const SIN_MASK: usize = SIN_N - 1;
const TWO_PI: f32 = 2.0 * math.pi;

// ------------------------------------------------------------------ reef map --
const TILE: f32 = 64.0; // metres per tile, both axes
const K: f32 = TWO_PI / TILE; // base spatial frequency; every periodic term is a multiple
const MAP_N: usize = 2048;
const MAP_MASK: u32 = MAP_N - 1;
const BLK_SHIFT: u5 = 6; // 64 x 64 texel blocks for the coarse max-height map
const BLK_N: usize = MAP_N >> BLK_SHIFT;
const BLK_MASK: u32 = BLK_N - 1;
const TEX: f32 = @as(f32, @floatFromInt(MAP_N)) / TILE; // texels per metre

// ------------------------------------------------------------------- camera --
const HORIZON: f32 = 0.42; // horizon line as a fraction of height
const FOCAL: f32 = 0.80; // focal length as a fraction of height
const CAM_SPEED: f32 = 0.35; // metres per second: a slow fin-kick drift
const CAM_Y: f32 = 2.6; // metres above the lagoon sand
const Z_NEAR: f32 = 0.5;
const Z_FAR: f32 = 26.0; // visibility is 11-16 m, so nothing past this shows
const Z_GROW: f32 = 0.017; // depth slice spacing as a fraction of depth
const MAX_SLICES: usize = 512;
const FOG_K: f32 = 0.115; // ~82% fogged at 15 m
const SURFACE_Y: f32 = 9.0; // the lagoon is about 10 m deep here
const DAY_PERIOD: f64 = 960.0; // seconds per day / sunset / dusk / sunrise cycle

// ------------------------------------------------------------------- things --
const NUM_BRANCH: usize = 90;
const NUM_TABLE: usize = 36;
const NUM_ANEM: usize = 28;
const NUM_CLAM: usize = 180;
const NUM_CORAL: usize = NUM_BRANCH + NUM_TABLE + NUM_ANEM + NUM_CLAM;
const STAG_SEGS: usize = 40;
const FAN_SEGS: usize = 0;
const NUM_FAN: usize = 0;
const MAX_SEGS: usize = NUM_BRANCH * STAG_SEGS;
const MAX_ITEMS: usize = NUM_FISH + NUM_CORAL;
const MAX_BOMMIES: usize = 96;
const ANEM_TENT: usize = 22;
const ANEM_PTS: usize = 5;
const NUM_SNOW: usize = 900;
const NUM_BUBBLES: usize = 0;
const PROF_N: usize = 64;

const RAY_SLANT_Q6: usize = 26; // god-ray slant: 26/64 px of x per px of y
const RAY_N: usize = MAX_W + (MAX_H * RAY_SLANT_Q6 >> 6) + 2;
const WATER_HOR = [3]f32{ 46, 104, 112 }; // cloudy green-blue lagoon water

// ------------------------------------------------------------------ species --
// Which animals live on the reef. Delete a line to remove a species, or move
// one to the front; each species struct (bottom of this file) sets its own
// count, size, speed and habitat.
const SPECIES = .{
    Damselfish,
    Fusilier,
    PickhandleBarracuda,
    EasternClownfish,
    Parrotfish,
    BarramundiCod,
    BlacktipShark,
    WhitetipShark,
    TawnyNurseShark,
    GreenTurtle,
};

const N_SPECIES: usize = SPECIES.len;

/// Per-species numbers the simulation needs at run time.
const SpeciesInfo = struct { start: u16, count: u16, length: f32, half_depth: f32, speed: f32, school: bool, habitat: u8, upright: bool, anchor: u8, dusk: bool };

const SPECIES_INFO: [N_SPECIES]SpeciesInfo = blk: {
    var out: [N_SPECIES]SpeciesInfo = undefined;
    var start: u16 = 0;
    for (0..N_SPECIES) |i| {
        const S = SPECIES[i];
        out[i] = .{
            .start = start,
            .count = S.count,
            .length = S.length,
            .half_depth = S.half_depth,
            .speed = S.speed,
            .school = S.school,
            .habitat = S.habitat,
            .upright = S.upright,
            // Optional: 1 = gathers at a bommie, 2 = lives in an anemone.
            .anchor = if (@hasDecl(S, "anchor")) S.anchor else 0,
            // Optional: only comes in around sunset and sunrise.
            .dusk = if (@hasDecl(S, "dusk")) S.dusk else false,
        };
        start += S.count;
    }
    break :blk out;
};

const NUM_FISH: usize = blk: {
    var n: usize = 0;
    for (0..N_SPECIES) |i| n += SPECIES[i].count;
    break :blk n;
};

// Live massive coral (Porites tan, cream and yellow-brown; Diploastrea
// green-brown; the odd blue-purple), dead rock and turf, coralline crust.
const LIVE_COLS = [6][3]f32{ .{ 196, 164, 104 }, .{ 214, 198, 158 }, .{ 176, 150, 92 }, .{ 128, 138, 88 }, .{ 136, 124, 168 }, .{ 190, 150, 120 } };
const TURF = [3]f32{ 104, 92, 60 };
const ROCK = [3]f32{ 150, 138, 120 };
const CORALLINE = [3]f32{ 196, 128, 138 };
const SPONGE_COLS = [4][3]f32{ .{ 128, 76, 70 }, .{ 150, 92, 150 }, .{ 214, 132, 58 }, .{ 176, 60, 70 } };
const STAG_BASE = [3][3]f32{ .{ 168, 140, 96 }, .{ 150, 132, 104 }, .{ 120, 128, 150 } };
const STAG_TIP = [3][3]f32{ .{ 214, 214, 230 }, .{ 150, 180, 250 }, .{ 220, 170, 220 } };
const TABLE_COLS = [3][3]f32{ .{ 150, 140, 96 }, .{ 128, 134, 110 }, .{ 168, 150, 120 } };
const ANEM_BASE = [3][3]f32{ .{ 196, 176, 120 }, .{ 168, 190, 120 }, .{ 210, 190, 150 } };
const ANEM_TIP = [3][3]f32{ .{ 240, 230, 170 }, .{ 200, 240, 170 }, .{ 255, 214, 214 } };
const ANEM_COLUMN = [3][3]f32{ .{ 200, 40, 70 }, .{ 150, 50, 140 }, .{ 220, 200, 170 } };
// Giant clam mantles: crocus blues and teals, gold-green, violet; gigas olive.
const MANTLE_COLS = [5][3]f32{ .{ 30, 110, 220 }, .{ 20, 170, 170 }, .{ 120, 160, 60 }, .{ 120, 70, 200 }, .{ 110, 110, 60 } };

pub const Bommie = struct { x: f32, z: f32, r: f32, top: f32 };

pub const Fish = struct {
    x: f32, // camera-relative x
    y: f32, // world y
    z: f32, // camera-relative depth
    vx: f32,
    vy: f32,
    vz: f32,
    size: f32,
    wag: f32,
    seed: f32, // 0..1, fixed: individual variation and solo wandering
    kind: u8, // index into SPECIES
};

pub const Coral = struct {
    x: f32, // world x in the tile
    z: f32, // world z in the tile
    y: f32, // seabed height at the base
    kind: u8, // 1 staghorn, 2 sea fan, 3 anemone
    style: u8, // palette index
    seg_start: u16,
    seg_count: u16,
    angle: f32, // fan plane orientation
    size: f32,
    phase: f32,
};

pub const Seg = struct {
    ax: f32,
    ay: f32,
    az: f32,
    bx: f32,
    by: f32,
    bz: f32,
    thick: f32, // world units
    t: f32, // 0 at the base, 1 at the tips (colour ramp)
};

pub const Item = struct {
    rz: f32, // depth
    rx: f32, // camera-relative x
    idx: u16,
    kind: u8, // 0 fish, otherwise the coral kind
};

pub const Mote = struct {
    x: f32,
    y: f32,
    z: f32,
    phase: f32,
};

pub const Bubble = struct {
    x: f32,
    y: f32,
    z: f32,
    r: f32,
    vy: f32,
    phase: f32,
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    scroll_z: f32,
    cam_x: f32,
    cam_y: f32,
    focal_px: f32,
    horizon_px: f32,
    h_max: f32, // tallest point on the reef, for skipping columns that cannot change
    blk_max: [BLK_N * BLK_N]f32, // tallest point in each block and its 8 neighbours

    sin_lut: [SIN_N]f32,
    prof: [PROF_N]f32,
    col_k: [MAX_W]f32, // screen column -> x slope (x - w/2) / focal

    row_bg: [MAX_H]u32,
    row_ray: [MAX_H]u32,
    rays: [RAY_N]u8,

    height: [MAP_N * MAP_N]f32,
    color: [MAP_N * MAP_N]u32, // lit albedo

    fish: [NUM_FISH]Fish,
    corals: [NUM_CORAL]Coral,
    segs: [MAX_SEGS]Seg,
    n_segs: usize,
    items: [MAX_ITEMS]Item,
    n_items: usize,

    snow: [NUM_SNOW]Mote,
    bubbles: [NUM_BUBBLES]Bubble,
    rng: u64,

    bommies: [MAX_BOMMIES]Bommie,
    n_bommies: usize,
    // Where each species' school is gathered: world x, depth ahead of the camera, height.
    anchor_x: [N_SPECIES]f32,
    anchor_z: [N_SPECIES]f32,
    anchor_y: [N_SPECIES]f32,
    // Light: 0 noon .. 1 full sunset/sunrise gold, and dusk dimming.
    gold: f32,
    dim: f32,
    tint: [3]u32, // q8 colour grade applied in the final pass

    // ------------------------------------------------------------- helpers --

    inline fn xorshift64(state: *u64) u64 {
        var x = state.*;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        state.* = x;
        return x;
    }

    inline fn rand01(state: *u64) f32 {
        return @as(f32, @floatFromInt(xorshift64(state) & 0xFFFFFF)) / @as(f32, 0x1000000);
    }

    inline fn fastSin(self: *const State, rad: f32) f32 {
        const norm = rad * (1.0 / TWO_PI);
        const f = (norm - @floor(norm)) * @as(f32, @floatFromInt(SIN_N));
        const idx: usize = @as(usize, @intFromFloat(@max(0.0, f))) & SIN_MASK;
        return self.sin_lut[idx];
    }

    inline fn fastCos(self: *const State, rad: f32) f32 {
        return self.fastSin(rad + 0.5 * math.pi);
    }

    /// (t * freq) mod 2*pi in f64, so phases stay exact after days of uptime.
    inline fn phase(self: *const State, freq: f64) f32 {
        return @floatCast(@mod(self.time_sec * freq, 2.0 * math.pi));
    }

    inline fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
        const t = math.clamp((x - e0) / (e1 - e0), 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    inline fn toU8(v: f32) u8 {
        return @intFromFloat(math.clamp(v, 0.0, 255.0));
    }

    inline fn pack3(c: [3]f32) u32 {
        return sdk.packRGBA(toU8(c[0]), toU8(c[1]), toU8(c[2]));
    }

    inline fn mix3(a: [3]f32, b: [3]f32, t: f32) [3]f32 {
        return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t };
    }

    /// Shortest signed distance on the wrapped tile.
    inline fn wrapD(d: f32) f32 {
        return d - TILE * @round(d / TILE);
    }

    inline fn texIdx(iu: i32, iv: i32) usize {
        const u: u32 = @as(u32, @bitCast(iu)) & MAP_MASK;
        const v: u32 = @as(u32, @bitCast(iv)) & MAP_MASK;
        return @as(usize, v) * MAP_N + u;
    }

    /// Centre of the sandy channel the camera follows, as a function of z.
    inline fn channelX(z: f32) f32 {
        return 34.0 + 5.0 * @sin(K * z) + 2.0 * @sin(2.0 * K * z + 1.0);
    }

    /// Bilinear seabed height at world (wx, wz).
    fn heightAt(self: *const State, wx: f32, wz: f32) f32 {
        const u = wx * TEX;
        const v = wz * TEX;
        const fu = @floor(u);
        const fv = @floor(v);
        const iu: i32 = @intFromFloat(math.clamp(fu, -1.0e6, 1.0e6));
        const iv: i32 = @intFromFloat(math.clamp(fv, -1.0e6, 1.0e6));
        const tu = u - fu;
        const tv = v - fv;
        const h00 = self.height[texIdx(iu, iv)];
        const h10 = self.height[texIdx(iu + 1, iv)];
        const h01 = self.height[texIdx(iu, iv + 1)];
        const h11 = self.height[texIdx(iu + 1, iv + 1)];
        const a = h00 + (h10 - h00) * tu;
        const b = h01 + (h11 - h01) * tu;
        return a + (b - a) * tv;
    }

    /// Camera-relative point -> screen. Returns false when behind the near plane.
    inline fn project(self: *const State, rx: f32, ry: f32, rz: f32, sx: *f32, sy: *f32) bool {
        if (rz < Z_NEAR) return false;
        const k = self.focal_px / rz;
        sx.* = 0.5 * @as(f32, @floatFromInt(self.w)) + rx * k;
        sy.* = self.horizon_px - ry * k;
        return true;
    }

    // ---------------------------------------------------------------- init --

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.scroll_z = 0.0;
        self.cam_x = channelX(0.0);
        self.cam_y = CAM_Y;
        self.rng = 0xC0_7A1_5EED_42_9E37;
        self.n_segs = 0;
        self.n_items = 0;
        self.n_bommies = 0;

        const hf: f32 = @floatFromInt(@max(self.h, 1));
        const wf: f32 = @floatFromInt(@max(self.w, 1));
        self.focal_px = FOCAL * hf;
        self.horizon_px = HORIZON * hf;

        for (0..SIN_N) |i| {
            const a = (@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(SIN_N))) * (2.0 * math.pi);
            self.sin_lut[i] = @floatCast(@sin(a));
        }
        for (0..PROF_N) |i| {
            const u: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(PROF_N - 1));
            const p = math.clamp(u / 0.78, 0.0, 1.0);
            self.prof[i] = if (u <= 0.78) 0.18 + 0.82 * @sin(math.pi * math.pow(f32, p, 0.62)) else 0.18;
        }
        for (0..MAX_W) |x| {
            self.col_k[x] = (@as(f32, @floatFromInt(x)) + 0.5 - 0.5 * wf) / self.focal_px;
        }

        // Water column.
        const top = [3]f32{ 74, 138, 146 };
        const bot = [3]f32{ 18, 54, 62 };
        for (0..self.h) |y| {
            const ny = @as(f32, @floatFromInt(y)) / hf;
            const c = if (ny < HORIZON)
                mix3(top, WATER_HOR, math.pow(f32, ny / HORIZON, 0.8))
            else
                mix3(WATER_HOR, bot, math.pow(f32, (ny - HORIZON) / (1.0 - HORIZON), 0.7));
            self.row_bg[y] = pack3(c);
            const g = 110.0 * @exp(-2.0 * ny) * (1.0 - smoothstep(0.6, 1.0, ny));
            self.row_ray[y] = @intFromFloat(math.clamp(g, 0.0, 256.0));
        }

        var rng = self.rng;
        self.bakeReef(&rng);
        self.buildCorals(&rng);

        for (0..N_SPECIES) |si| {
            const info = SPECIES_INFO[si];
            for (info.start..info.start + info.count) |i| {
                self.fish[i] = .{
                    .x = (rand01(&rng) - 0.5) * 12.0,
                    .y = habitatY(info.habitat) + (rand01(&rng) - 0.5) * 1.0,
                    .z = 3.0 + rand01(&rng) * 18.0,
                    .vx = (rand01(&rng) - 0.5) * 2.0,
                    .vy = 0.0,
                    .vz = (rand01(&rng) - 0.5) * 0.5,
                    .size = info.length * (0.85 + 0.3 * rand01(&rng)),
                    .wag = rand01(&rng) * TWO_PI,
                    .seed = rand01(&rng),
                    .kind = @intCast(si),
                };
            }
        }
        for (0..NUM_SNOW) |i| {
            self.snow[i] = .{
                .x = (rand01(&rng) - 0.5) * 14.0,
                .y = rand01(&rng) * SURFACE_Y,
                .z = 0.6 + rand01(&rng) * 14.0,
                .phase = rand01(&rng) * TWO_PI,
            };
        }
        for (0..NUM_BUBBLES) |i| {
            self.bubbles[i] = .{
                .x = (rand01(&rng) - 0.5) * 30.0,
                .y = rand01(&rng) * SURFACE_Y,
                .z = 4.0 + rand01(&rng) * 30.0,
                .r = 0.04 + 0.08 * rand01(&rng),
                .vy = 1.2 + 1.2 * rand01(&rng),
                .phase = rand01(&rng) * TWO_PI,
            };
        }
        self.rng = rng;
        for (0..N_SPECIES) |si| {
            self.anchor_x[si] = self.cam_x + (rand01(&self.rng) - 0.5) * 10.0;
            self.anchor_z[si] = 6.0 + 14.0 * rand01(&self.rng);
            self.anchor_y[si] = habitatY(SPECIES_INFO[si].habitat);
        }
        self.gold = 0;
        self.dim = 0;
        self.tint = .{ 256, 256, 256 };

        self.step(0.0);
        return self;
    }

    /// Periodic value noise on a `cells` x `cells` lattice over the tile.
    fn valueNoise(wx: f32, wz: f32, cells: u32, seed: u32) f32 {
        const s = @as(f32, @floatFromInt(cells)) / TILE;
        const u = wx * s;
        const v = wz * s;
        const fu = @floor(u);
        const fv = @floor(v);
        const iu: u32 = @as(u32, @intFromFloat(@max(0.0, fu))) % cells;
        const iv: u32 = @as(u32, @intFromFloat(@max(0.0, fv))) % cells;
        const ju = (iu + 1) % cells;
        const jv = (iv + 1) % cells;
        const tu = u - fu;
        const tv = v - fv;
        const su = tu * tu * (3.0 - 2.0 * tu);
        const sv = tv * tv * (3.0 - 2.0 * tv);
        const a = hash01(iu, iv, seed);
        const b = hash01(ju, iv, seed);
        const c = hash01(iu, jv, seed);
        const d = hash01(ju, jv, seed);
        const ab = a + (b - a) * su;
        const cd = c + (d - c) * su;
        return ab + (cd - ab) * sv;
    }

    inline fn hash01(x: u32, y: u32, seed: u32) f32 {
        var hsh: u32 = x *% 0x8DA6B343 +% y *% 0xD8163841 +% seed *% 0xCB1AB31F;
        hsh ^= hsh >> 13;
        hsh *%= 0x5BD1E995;
        hsh ^= hsh >> 15;
        return @as(f32, @floatFromInt(hsh & 0xFFFF)) / 65535.0;
    }

    /// Across-lagoon position relative to the drift path: negative toward the
    /// fringing reef and shore, positive toward open lagoon.
    inline fn lagoonDx(wx: f32, wz: f32) f32 {
        return wrapD(wx - channelX(wz));
    }

    /// Height of the fringing reef that rises toward the shore (left), in metres
    /// above the lagoon floor: reef flat ~5 m up, i.e. near low tide.
    fn fringeHeight(dx: f32) f32 {
        // The far edge of the tile (|dx| near 32) also counts as fringe, so the wrap is seamless.
        const left = smoothstep(-7.0, -20.0, dx);
        const wrap = smoothstep(27.0, 31.5, dx);
        return 5.0 * @max(left, wrap);
    }

    fn bakeReef(self: *State, rng: *u64) void {
        const sand = [3]f32{ 228, 222, 200 }; // pale carbonate sand
        const blade_young = [3]f32{ 74, 138, 64 };
        const blade_old = [3]f32{ 126, 122, 70 }; // epiphyte film on older blades

        // Pass 1: lagoon sand, the fringing reef slope, and patchy seagrass.
        for (0..MAP_N) |tv| {
            const wz = (@as(f32, @floatFromInt(tv)) + 0.5) / TEX;
            for (0..MAP_N) |tu| {
                const wx = (@as(f32, @floatFromInt(tu)) + 0.5) / TEX;
                const dx = lagoonDx(wx, wz);
                const ripple = 0.025 * @sin(128.0 * K * wx + 40.0 * K * wz + 2.0 * @sin(9.0 * K * wz));
                const undul = 0.35 * (valueNoise(wx, wz, 16, 11) - 0.5);
                const fringe = fringeHeight(dx);
                const rough = (valueNoise(wx, wz, 256, 12) - 0.5) * 0.5 + (valueNoise(wx, wz, 1024, 13) - 0.5) * 0.12;
                const on_reef = smoothstep(0.3, 1.2, fringe);
                var hgt = undul + ripple * (1.0 - on_reef) + fringe + rough * on_reef;
                var c = mix3(sand, .{ 206, 196, 170 }, 0.5 + 0.5 * @sin(128.0 * K * wx + 40.0 * K * wz + 2.0 * @sin(9.0 * K * wz)));
                if (on_reef > 0.0) c = mix3(c, reefSurface(wx, wz), on_reef);

                // Seagrass: meadows on lagoon sand away from the reef, patchy inside
                // (the sources: sparse on reef tops, >25% cover in sheltered sand).
                if (on_reef < 0.2) {
                    const meadow = smoothstep(0.52, 0.68, valueNoise(wx, wz, 12, 14));
                    const cover = meadow * (0.15 + 0.3 * valueNoise(wx, wz, 96, 15));
                    const r = hash01(@intCast(tu), @intCast(tv), 16);
                    if (r < cover) {
                        // One texel (3 cm) blade: Thalassia straps in shallower sand,
                        // shorter Halodule in between.
                        const tall = 0.10 + 0.22 * hash01(@intCast(tu), @intCast(tv), 17);
                        hgt += tall;
                        c = mix3(blade_young, blade_old, hash01(@intCast(tu), @intCast(tv), 18));
                    } else if (meadow > 0.0) {
                        c = mix3(c, .{ 176, 170, 140 }, 0.35 * meadow); // rhizome-darkened sand
                    }
                }
                const i = tv * MAP_N + tu;
                self.height[i] = hgt;
                self.color[i] = pack3(c);
            }
        }

        // Pass 2: bommies, clusters of lumpy massive-coral heads on the lagoon floor,
        // kept clear of the drift path. Their surface is mostly rock, turf and
        // coralline crust, with live coral on about a quarter of it.
        var tries: usize = 0;
        while (self.n_bommies < MAX_BOMMIES and tries < 20000) : (tries += 1) {
            const cx = rand01(rng) * TILE;
            const cz = rand01(rng) * TILE;
            const dx = lagoonDx(cx, cz);
            const r = 0.9 + 2.0 * rand01(rng);
            if (@abs(dx) < r + 2.2) continue; // keep the path clear
            if (fringeHeight(dx) > 2.0 and rand01(rng) < 0.7) continue;
            var clash = false;
            for (self.bommies[0..self.n_bommies]) |b| {
                const ddx = wrapD(b.x - cx);
                const ddz = wrapD(b.z - cz);
                if (ddx * ddx + ddz * ddz < (b.r + r + 1.0) * (b.r + r + 1.0)) clash = true;
            }
            if (clash) continue;
            const tall = @min(4.5, r * (0.7 + 0.9 * rand01(rng)));
            const base = self.heightAt(cx, cz);
            const lobes: usize = 6 + @as(usize, @intFromFloat(rand01(rng) * 6.0));
            var top: f32 = base;
            for (0..lobes) |li| {
                const a = rand01(rng) * TWO_PI;
                const off = if (li == 0) 0.0 else r * (0.3 + 0.55 * rand01(rng));
                const lx = cx + @cos(a) * off;
                const lz = cz + @sin(a) * off;
                const lr = if (li == 0) r * 0.8 else r * (0.3 + 0.3 * rand01(rng));
                const lh = if (li == 0) tall else tall * (0.35 + 0.55 * rand01(rng));
                const seed: u32 = @intFromFloat(rand01(rng) * 60000.0);
                top = @max(top, base + lh);
                self.stamp(lx, lz, lr, struct {
                    fn f(px: f32, pz: f32, d2: f32, ctx: anytype) ?struct { h: f32, c: [3]f32 } {
                        // Porites-style lumps: a dome with knobbly lobes on it.
                        const dome = ctx.lh * @sqrt(1.0 - d2) * (0.85 + 0.15 * @sqrt(1.0 - d2));
                        const wx = ctx.cx + px;
                        const wz = ctx.cz + pz;
                        const knob = 0.40 * ctx.lr * (valueNoise(wx, wz, 128, ctx.seed) - 0.5) + 0.12 * (valueNoise(wx, wz, 512, ctx.seed + 1) - 0.5);
                        return .{ .h = ctx.base + dome + knob, .c = reefSurface(wx, wz) };
                    }
                }.f, .{ .lh = lh, .lr = lr, .base = base, .cx = lx, .cz = lz, .seed = seed });
            }
            self.bommies[self.n_bommies] = .{ .x = cx, .z = cz, .r = r, .top = top };
            self.n_bommies += 1;
        }

        // Sponges: barrel and vase forms on the bommies and reef slope.
        var placed: usize = 0;
        tries = 0;
        while (placed < 90 and tries < 20000) : (tries += 1) {
            const cx = rand01(rng) * TILE;
            const cz = rand01(rng) * TILE;
            if (@abs(lagoonDx(cx, cz)) < 2.5) continue;
            const base = self.heightAt(cx, cz);
            if (base < 0.6) continue; // on rock, not on sand
            placed += 1;
            const col = SPONGE_COLS[@as(usize, @intFromFloat(rand01(rng) * 3.99))];
            const vase = rand01(rng) < 0.4;
            const r = if (vase) 0.10 + 0.08 * rand01(rng) else 0.18 + 0.2 * rand01(rng);
            const tall = if (vase) 0.35 + 0.3 * rand01(rng) else r * (1.2 + 1.0 * rand01(rng));
            self.stamp(cx, cz, r, struct {
                fn f(px: f32, pz: f32, d2: f32, ctx: anytype) ?struct { h: f32, c: [3]f32 } {
                    _ = px;
                    _ = pz;
                    if (d2 < 0.40) {
                        return .{ .h = ctx.base + ctx.tall * 0.5, .c = .{ ctx.col[0] * 0.3, ctx.col[1] * 0.3, ctx.col[2] * 0.3 } };
                    }
                    return .{ .h = ctx.base + ctx.tall, .c = ctx.col };
                }
            }.f, .{ .base = base, .tall = tall, .col = col });
        }

        // Coral rubble on the sand near the bommies.
        placed = 0;
        tries = 0;
        while (placed < 260 and tries < 20000) : (tries += 1) {
            const cx = rand01(rng) * TILE;
            const cz = rand01(rng) * TILE;
            if (@abs(lagoonDx(cx, cz)) < 1.0) continue;
            if (self.heightAt(cx, cz) > 0.4) continue;
            placed += 1;
            const r = 0.06 + 0.14 * rand01(rng);
            const shade = 0.75 + 0.3 * rand01(rng);
            const col = [3]f32{ 200 * shade, 190 * shade, 166 * shade };
            const base = self.heightAt(cx, cz);
            const tall = r * (0.3 + 0.3 * rand01(rng));
            self.stamp(cx, cz, r, struct {
                fn f(px: f32, pz: f32, d2: f32, ctx: anytype) ?struct { h: f32, c: [3]f32 } {
                    _ = px;
                    _ = pz;
                    return .{ .h = ctx.base + ctx.tall * @sqrt(1.0 - d2), .c = ctx.col };
                }
            }.f, .{ .base = base, .tall = tall, .col = col });
        }

        self.h_max = 0.0;
        for (&self.height) |*hv| self.h_max = @max(self.h_max, hv.*);
        var raw: [BLK_N * BLK_N]f32 = @splat(-1.0e9);
        for (0..MAP_N) |tv| {
            for (0..MAP_N) |tu| {
                const bi = (tv >> BLK_SHIFT) * BLK_N + (tu >> BLK_SHIFT);
                raw[bi] = @max(raw[bi], self.height[tv * MAP_N + tu]);
            }
        }
        // Dilate by one block so bilinear taps across a block edge stay covered.
        for (0..BLK_N) |bv| {
            for (0..BLK_N) |bu| {
                var m: f32 = -1.0e9;
                for (0..3) |dv| {
                    for (0..3) |du| {
                        const v = (bv + BLK_N + dv - 1) & BLK_MASK;
                        const u = (bu + BLK_N + du - 1) & BLK_MASK;
                        m = @max(m, raw[v * BLK_N + u]);
                    }
                }
                self.blk_max[bv * BLK_N + bu] = m;
            }
        }

        // Pass 3: light it. Lambert from above, cavities darker, reds absorbed.
        const lx: f32 = 0.30;
        const ly: f32 = 0.88;
        const lz: f32 = -0.36;
        for (0..MAP_N) |tv| {
            for (0..MAP_N) |tu| {
                const iu: i32 = @intCast(tu);
                const iv: i32 = @intCast(tv);
                const hc = self.height[texIdx(iu, iv)];
                const gx = (self.height[texIdx(iu + 1, iv)] - self.height[texIdx(iu - 1, iv)]) * TEX * 0.5;
                const gz = (self.height[texIdx(iu, iv + 1)] - self.height[texIdx(iu, iv - 1)]) * TEX * 0.5;
                const inv = 1.0 / @sqrt(gx * gx + gz * gz + 1.0);
                const lam = @max(0.0, (-gx * lx + ly - gz * lz) * inv);
                const around = 0.25 * (self.height[texIdx(iu + 6, iv)] + self.height[texIdx(iu - 6, iv)] +
                    self.height[texIdx(iu, iv + 6)] + self.height[texIdx(iu, iv - 6)]);
                const cavity = math.clamp(1.0 + 1.6 * (hc - around), 0.55, 1.15);
                const lit = (0.42 + 0.80 * lam) * cavity * (0.92 + 0.03 * hc);
                const c = self.color[tv * MAP_N + tu];
                const r = @as(f32, @floatFromInt(c & 0xFF)) * lit * 0.84;
                const g = @as(f32, @floatFromInt((c >> 8) & 0xFF)) * lit;
                const b = @as(f32, @floatFromInt((c >> 16) & 0xFF)) * lit * 1.02;
                self.color[tv * MAP_N + tu] = sdk.packRGBA(toU8(r), toU8(g), toU8(b));
            }
        }
    }

    /// Colour of reef rock at a point: mostly turf, rock and coralline crust,
    /// with live massive coral on roughly a quarter of the surface (24-27%
    /// live cover at Lizard, PCRF) and occasional encrusting sponge.
    fn reefSurface(wx: f32, wz: f32) [3]f32 {
        const n_live = valueNoise(wx, wz, 160, 21);
        const n_kind = valueNoise(wx, wz, 64, 22);
        const n_crust = valueNoise(wx, wz, 256, 23);
        const speck = 0.85 + 0.3 * valueNoise(wx, wz, 1024, 24);
        var c = mix3(TURF, ROCK, smoothstep(0.3, 0.7, valueNoise(wx, wz, 128, 25)));
        c = mix3(c, CORALLINE, 0.8 * smoothstep(0.62, 0.8, n_crust));
        const live = smoothstep(0.58, 0.62, n_live); // ~25% of the area
        if (live > 0.0) {
            const k: usize = @intFromFloat(math.clamp(n_kind * 5.99, 0.0, 5.0));
            var lc = LIVE_COLS[k];
            // Diploastrea / Montastrea: a fine grid of polyps.
            if (k == 3) {
                const pg = @sin(wx * 60.0) * @sin(wz * 60.0);
                if (pg > 0.4) lc = .{ lc[0] * 0.75, lc[1] * 0.75, lc[2] * 0.75 };
            }
            c = mix3(c, lc, live);
        }
        if (valueNoise(wx, wz, 200, 26) > 0.86) c = mix3(c, SPONGE_COLS[2], 0.7); // encrusting sponge
        return .{ c[0] * speck, c[1] * speck, c[2] * speck };
    }

    /// Writes a round feature of radius r at (cx, cz): `f` returns height and colour
    /// for each texel inside, or null to leave it. Heights only ever rise.
    fn stamp(self: *State, cx: f32, cz: f32, r: f32, comptime f: anytype, ctx: anytype) void {
        const r_tex: i32 = @intFromFloat(@ceil(r * TEX) + 1.0);
        const cu: i32 = @intFromFloat(@floor(cx * TEX));
        const cv: i32 = @intFromFloat(@floor(cz * TEX));
        var dv: i32 = -r_tex;
        while (dv <= r_tex) : (dv += 1) {
            var du: i32 = -r_tex;
            while (du <= r_tex) : (du += 1) {
                const wx = (@as(f32, @floatFromInt(cu + du)) + 0.5) / TEX;
                const wz = (@as(f32, @floatFromInt(cv + dv)) + 0.5) / TEX;
                const lx = (wx - cx) / r;
                const lz = (wz - cz) / r;
                const d2 = lx * lx + lz * lz;
                if (d2 >= 1.0) continue;
                if (f(lx * r, lz * r, d2, ctx)) |out| {
                    const i = texIdx(cu + du, cv + dv);
                    if (out.h > self.height[i]) {
                        self.height[i] = out.h;
                        self.color[i] = pack3(out.c);
                    }
                }
            }
        }
    }

    fn addSeg(self: *State, a: [3]f32, b: [3]f32, thick: f32, t: f32) void {
        if (self.n_segs >= MAX_SEGS) return;
        self.segs[self.n_segs] = .{ .ax = a[0], .ay = a[1], .az = a[2], .bx = b[0], .by = b[1], .bz = b[2], .thick = thick, .t = t };
        self.n_segs += 1;
    }

    const Branch = struct { p: [3]f32, d: [3]f32, len: f32, thick: f32, depth: u8 };

    /// A random point on a random bommie's upper surface.
    fn onBommie(self: *State, rng: *u64, reach: f32) [2]f32 {
        if (self.n_bommies == 0) return .{ rand01(rng) * TILE, rand01(rng) * TILE };
        const b = self.bommies[@min(self.n_bommies - 1, @as(usize, @intFromFloat(rand01(rng) * @as(f32, @floatFromInt(self.n_bommies)))))];
        const a = rand01(rng) * TWO_PI;
        const d = b.r * reach * @sqrt(rand01(rng));
        return .{ b.x + @cos(a) * d, b.z + @sin(a) * d };
    }

    fn buildCorals(self: *State, rng: *u64) void {
        var n: usize = 0;
        // Small patches of branching Acropora on bommie tops.
        for (0..NUM_BRANCH) |_| {
            const p = self.onBommie(rng, 0.7);
            var c = self.newCoral(rng, p, 1);
            c.style = @intFromFloat(rand01(rng) * 2.99);
            c.size = 0.35 + 0.25 * rand01(rng);
            c.seg_start = @intCast(self.n_segs);
            self.growStaghorn(rng, c.size);
            c.seg_count = @intCast(self.n_segs - c.seg_start);
            self.corals[n] = c;
            n += 1;
        }
        // Table Acropora: flat plates on a short stalk.
        for (0..NUM_TABLE) |_| {
            const p = self.onBommie(rng, 0.8);
            var c = self.newCoral(rng, p, 4);
            c.style = @intFromFloat(rand01(rng) * 2.99);
            c.size = 0.35 + 0.5 * rand01(rng); // plate radius, metres
            self.corals[n] = c;
            n += 1;
        }
        // Anemones (hosts for the clownfish) on bommie shoulders.
        for (0..NUM_ANEM) |_| {
            const p = self.onBommie(rng, 0.85);
            var c = self.newCoral(rng, p, 3);
            c.style = @intFromFloat(rand01(rng) * 2.99);
            c.size = 0.22 + 0.15 * rand01(rng);
            self.corals[n] = c;
            n += 1;
        }
        // Giant clams: crocus clams set into coral heads (most of them), a few
        // fluted and smooth giant clams, and the odd Tridacna gigas on the sand.
        for (0..NUM_CLAM) |ci| {
            var c: Coral = undefined;
            const pick = rand01(rng);
            if (ci % 45 == 0) {
                // T. gigas, about a metre long, resting on sand beside a bommie.
                var p = self.onBommie(rng, 1.0);
                p[0] += 1.4;
                c = self.newCoral(rng, p, 5);
                c.style = 4;
                c.size = 0.45 + 0.15 * rand01(rng);
            } else {
                const p = self.onBommie(rng, 0.9);
                c = self.newCoral(rng, p, 5);
                c.style = @intFromFloat(rand01(rng) * 3.99);
                c.size = if (pick < 0.75) 0.07 + 0.05 * rand01(rng) else 0.14 + 0.10 * rand01(rng);
            }
            self.corals[n] = c;
            n += 1;
        }
    }

    fn newCoral(self: *State, rng: *u64, p: [2]f32, kind: u8) Coral {
        const x = @mod(p[0], TILE);
        const z = @mod(p[1], TILE);
        return .{
            .x = x,
            .z = z,
            .y = self.heightAt(x, z) - 0.02,
            .kind = kind,
            .style = 0,
            .seg_start = 0,
            .seg_count = 0,
            .angle = rand01(rng) * math.pi,
            .size = 1.0,
            .phase = rand01(rng) * TWO_PI,
        };
    }

    fn normalize3(v: [3]f32) [3]f32 {
        const l = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (l < 1e-6) return .{ 0, 1, 0 };
        return .{ v[0] / l, v[1] / l, v[2] / l };
    }

    fn growStaghorn(self: *State, rng: *u64, size: f32) void {
        const limit = self.n_segs + STAG_SEGS;
        var stack: [64]Branch = undefined;
        var sp: usize = 0;
        const trunks: usize = 3 + @as(usize, @intFromFloat(rand01(rng) * 3.0));
        for (0..trunks) |_| {
            const a = rand01(rng) * TWO_PI;
            const lean = 0.25 + 0.5 * rand01(rng);
            stack[sp] = .{ .p = .{ 0, 0, 0 }, .d = normalize3(.{ @cos(a) * lean, 1.0, @sin(a) * lean }), .len = 0.36 * size, .thick = 0.13 * size, .depth = 0 };
            sp += 1;
        }
        while (sp > 0 and self.n_segs < limit) {
            sp -= 1;
            const b = stack[sp];
            const e = [3]f32{ b.p[0] + b.d[0] * b.len, b.p[1] + b.d[1] * b.len, b.p[2] + b.d[2] * b.len };
            self.addSeg(b.p, e, b.thick, @as(f32, @floatFromInt(b.depth)) / 4.0);
            if (b.depth >= 4) continue;
            const kids: usize = if (rand01(rng) < 0.55) 2 else 1;
            for (0..kids) |_| {
                if (sp >= stack.len) break;
                const a = rand01(rng) * TWO_PI;
                const spread = 0.45 + 0.35 * rand01(rng);
                const nd = normalize3(.{ b.d[0] + @cos(a) * spread, b.d[1] + 0.25, b.d[2] + @sin(a) * spread });
                stack[sp] = .{ .p = e, .d = nd, .len = b.len * (0.78 + 0.1 * rand01(rng)), .thick = b.thick * 0.82, .depth = b.depth + 1 };
                sp += 1;
            }
        }
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    // ---------------------------------------------------------------- step --

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const dt_f: f32 = @floatCast(math.clamp(dt, 0.0, 0.05));
        self.scroll_z = @mod(self.scroll_z + CAM_SPEED * dt_f, TILE);
        self.cam_x = channelX(self.scroll_z + 4.0);
        self.cam_y = CAM_Y + 0.15 * self.fastSin(self.phase(0.19));
        self.stepLight();
        self.stepAnchors(dt_f);

        self.stepRays();
        self.stepFish(dt_f);
        self.stepParticles(dt_f);
        self.buildItems();
    }

    /// Day, sunset, dusk and sunrise over DAY_PERIOD seconds. The sun's colour
    /// grades the whole frame; blacktip sharks come in around sunset and sunrise.
    fn stepLight(self: *State) void {
        const p: f32 = @floatCast(@mod(self.time_sec / DAY_PERIOD + 0.35, 1.0));
        const bump = struct {
            fn f(x: f32, c: f32, w: f32) f32 {
                const d = (x - c) / w;
                return @max(0.0, 1.0 - d * d);
            }
        }.f;
        self.gold = @min(1.0, bump(p, 0.74, 0.07) + bump(p, 0.95, 0.06));
        self.dim = bump(p, 0.845, 0.05);
        const g = self.gold;
        const d = self.dim;
        // Under water the sunset is mostly a dimming; only the light shafts warm up
        // (see the ray colour in draw). Dusk sinks to a deep blue.
        const r = 256.0 * (1.0 - 0.18 * g - 0.62 * d);
        const gg = 256.0 * (1.0 - 0.20 * g - 0.52 * d);
        const b = 256.0 * (1.0 - 0.10 * g - 0.34 * d);
        self.tint = .{ @intFromFloat(math.clamp(r, 0.0, 400.0)), @intFromFloat(math.clamp(gg, 0.0, 400.0)), @intFromFloat(math.clamp(b, 0.0, 400.0)) };
    }

    /// Where each school gathers. Anchors live in the world, so they slide
    /// toward the camera as it drifts; once passed, the school moves on to a
    /// bommie (or anemone) further ahead, out in the haze.
    fn stepAnchors(self: *State, dt_f: f32) void {
        for (0..N_SPECIES) |si| {
            self.anchor_z[si] -= CAM_SPEED * dt_f;
            if (self.anchor_z[si] > 3.0) continue;
            const info = SPECIES_INFO[si];
            const ahead = 14.0 + 8.0 * rand01(&self.rng);
            self.anchor_z[si] = ahead;
            self.anchor_x[si] = self.cam_x + (rand01(&self.rng) - 0.5) * 12.0;
            self.anchor_y[si] = habitatY(info.habitat);
            if (info.anchor == 0) continue;
            // Look for a bommie (or an anemone) at about that distance ahead.
            const wz = self.scroll_z + ahead;
            var best: f32 = 1e9;
            if (info.anchor == 1) {
                for (self.bommies[0..self.n_bommies]) |b| {
                    const dz = @abs(wrapD(b.z - wz));
                    const dx = @abs(wrapD(b.x - self.cam_x));
                    const score = dz + 0.5 * dx;
                    if (dx < 9.0 and score < best) {
                        best = score;
                        self.anchor_x[si] = self.cam_x + wrapD(b.x - self.cam_x);
                        self.anchor_z[si] = @max(6.0, ahead + wrapD(b.z - wz));
                        self.anchor_y[si] = b.top + 0.4 + 2.0 * info.length;
                    }
                }
            } else {
                for (self.corals) |c| {
                    if (c.kind != 3) continue;
                    const dz = @abs(wrapD(c.z - wz));
                    const dx = @abs(wrapD(c.x - self.cam_x));
                    const score = dz + 0.5 * dx;
                    if (dx < 7.0 and score < best) {
                        best = score;
                        self.anchor_x[si] = self.cam_x + wrapD(c.x - self.cam_x);
                        self.anchor_z[si] = @max(5.0, ahead + wrapD(c.z - wz));
                        self.anchor_y[si] = c.y + 0.25;
                    }
                }
            }
        }
    }

    fn stepRays(self: *State) void {
        const p1 = self.phase(0.13);
        const p2 = self.phase(0.21);
        const p3 = self.phase(0.47);
        for (0..RAY_N) |i| {
            const u: f32 = @floatFromInt(i);
            const b1 = 0.5 + 0.5 * self.fastSin(u * 0.0062 + p1);
            const b2 = 0.5 + 0.5 * self.fastSin(u * 0.0147 - p2 + 1.7);
            const b3 = 0.5 + 0.5 * self.fastSin(u * 0.0310 + p3 + 0.4);
            var v = b1 * b2 * (0.55 + 0.45 * b3);
            v = v * v * 1.7;
            self.rays[i] = toU8(v * 255.0);
        }
    }

    /// Typical swimming height for a habitat: 0 reef and sand, 1 mid-water, 2 high.
    fn habitatY(habitat: u8) f32 {
        return switch (habitat) {
            0 => 1.0,
            1 => 3.0,
            else => 5.5,
        };
    }

    fn stepFish(self: *State, dt_f: f32) void {
        const shark_hour = self.gold > 0.25 or self.dim > 0.25;
        for (0..NUM_FISH) |i| {
            var f = self.fish[i];
            const info = SPECIES_INFO[f.kind];
            const kf: f32 = @floatFromInt(f.kind);
            const v = info.speed * info.length; // cruise speed in m/s

            // Schools gather at their species' anchor; loners wander on their own.
            var tx: f32 = 0;
            var ty: f32 = 0;
            var tz: f32 = 0;
            if (info.school) {
                const ax = wrapD(self.anchor_x[f.kind] - self.cam_x);
                const orbit = 0.6 + 2.0 * info.length;
                tx = ax + orbit * self.fastSin(self.phase(0.21) + f.seed * 6.0);
                tz = self.anchor_z[f.kind] + orbit * self.fastCos(self.phase(0.17) + f.seed * 6.0);
                ty = self.anchor_y[f.kind] + 0.4 * self.fastSin(self.phase(0.13) + kf);
            } else {
                const key = kf * 1.7 + f.seed * 37.0;
                const lane = @mod(key * 0.618, 1.0);
                tz = 4.0 + 14.0 * lane + 3.0 * self.fastSin(self.phase(0.03) + key * 1.3);
                tx = 0.45 * tz * self.fastSin(self.phase(0.025 + 0.02 * f.seed) + key * 1.9);
                ty = habitatY(info.habitat) + 0.5 * self.fastSin(self.phase(0.07) + key * 2.3);
            }
            if (info.dusk and !shark_hour) tz = 40.0; // off in the haze until the light changes
            if (info.habitat == 0) {
                ty = @max(ty, self.heightAt(f.x + self.cam_x, self.scroll_z + f.z) + 0.3 + 0.5 * f.seed);
            }

            if (info.school and info.count > 1) {
                var sep = [3]f32{ 0, 0, 0 };
                var ali = [3]f32{ 0, 0, 0 };
                var coh = [3]f32{ 0, 0, 0 };
                var n: f32 = 0;
                const sep_r2 = 2.5 * f.size * f.size;
                const look2 = 25.0 * f.size * f.size + 0.5;
                const local = i - info.start;
                const neighbours = @min(info.count - 1, 14);
                for (1..neighbours + 1) |k| {
                    const j = info.start + (local + k) % info.count;
                    const o = self.fish[j];
                    const dx = o.x - f.x;
                    const dy = o.y - f.y;
                    const dz = o.z - f.z;
                    const d2 = dx * dx + dy * dy + dz * dz;
                    if (d2 > 1e-6 and d2 < look2) {
                        if (d2 < sep_r2) {
                            const inv = f.size * f.size / d2;
                            sep[0] -= dx * inv;
                            sep[1] -= dy * inv;
                            sep[2] -= dz * inv;
                        }
                        ali[0] += o.vx;
                        ali[1] += o.vy;
                        ali[2] += o.vz;
                        coh[0] += o.x;
                        coh[1] += o.y;
                        coh[2] += o.z;
                        n += 1;
                    }
                }
                if (n > 0) {
                    const inv_n = 1.0 / n;
                    f.vx += ((ali[0] * inv_n - f.vx) * 1.5 + (coh[0] * inv_n - f.x) * 0.6 + sep[0] * 3.0) * dt_f;
                    f.vy += ((ali[1] * inv_n - f.vy) * 1.5 + (coh[1] * inv_n - f.y) * 0.6 + sep[1] * 3.0) * dt_f;
                    f.vz += ((ali[2] * inv_n - f.vz) * 1.2 + (coh[2] * inv_n - f.z) * 0.4 + sep[2] * 2.5) * dt_f;
                }
            }
            // Steering toward the target, scaled to the animal's own speed.
            const pull = 0.35 + 1.2 * v;
            f.vx += math.clamp(tx - f.x, -4.0, 4.0) * 0.30 * pull * dt_f;
            f.vy += math.clamp(ty - f.y, -2.0, 2.0) * 0.45 * pull * dt_f;
            // The camera drifts on at CAM_SPEED; reef fish hold station in the world.
            f.vz += (math.clamp(tz - f.z, -6.0, 6.0) * 0.18 * pull + CAM_SPEED * 0.0) * dt_f;
            f.vy *= 1.0 - 0.8 * dt_f;
            f.vz *= 1.0 - 0.5 * dt_f;

            const ground = self.heightAt(f.x + self.cam_x, self.scroll_z + f.z) + 0.15 + f.size * info.half_depth;
            if (f.y < ground) f.vy += (ground - f.y) * 6.0 * dt_f;
            if (f.y > SURFACE_Y - 1.0) f.vy -= (f.y - SURFACE_Y + 1.0) * 3.0 * dt_f;

            const sp = @sqrt(f.vx * f.vx + f.vy * f.vy + f.vz * f.vz);
            const lo = 0.6 * v;
            const hi = 2.4 * v + @as(f32, if (info.dusk) 0.6 else 0.0);
            const cs = math.clamp(sp, lo, hi);
            if (sp > 1e-5) {
                f.vx = f.vx / sp * cs;
                f.vy = f.vy / sp * cs;
                f.vz = f.vz / sp * cs;
            } else {
                f.vx = lo;
            }
            if (!info.upright) {
                const hs = @sqrt(f.vx * f.vx + f.vz * f.vz);
                if (hs < 0.6 * lo) {
                    if (hs > 1e-5) {
                        f.vx *= 0.6 * lo / hs;
                        f.vz *= 0.6 * lo / hs;
                    } else {
                        f.vx = 0.6 * lo;
                    }
                }
            }

            f.x = math.clamp(f.x + f.vx * dt_f, -30.0, 30.0);
            f.y = math.clamp(f.y + f.vy * dt_f, -1.0, SURFACE_Y);
            f.z += (f.vz - CAM_SPEED) * dt_f;
            // Passed by the camera (or lost far ahead): rejoin ahead, out in the haze.
            if (f.z < 0.7 or f.z > 48.0) {
                if (info.school) {
                    f.x = wrapD(self.anchor_x[f.kind] - self.cam_x) + (rand01(&self.rng) - 0.5) * 2.0;
                    f.z = @max(self.anchor_z[f.kind], 12.0) + rand01(&self.rng) * 3.0;
                    f.y = self.anchor_y[f.kind] + (rand01(&self.rng) - 0.5) * 0.6;
                } else {
                    f.x = (rand01(&self.rng) - 0.5) * 16.0;
                    f.z = 17.0 + 6.0 * rand01(&self.rng);
                    f.y = habitatY(info.habitat) + rand01(&self.rng) * 0.5;
                }
            }
            f.wag = @mod(f.wag + dt_f * (4.0 + 5.0 * cs / @max(f.size, 0.05) * 0.25), TWO_PI);
            self.fish[i] = f;
        }
    }

    fn stepParticles(self: *State, dt_f: f32) void {
        for (&self.snow) |*m| {
            m.z -= CAM_SPEED * dt_f;
            m.y -= 0.08 * dt_f;
            m.x += 0.08 * self.fastSin(self.phase(0.3) + m.phase) * dt_f;
            if (@abs(m.x) > 0.6 * m.z + 1.0) m.x = -m.x * 0.9; // stay in view
            if (m.z < 0.6) m.z += 14.0;
            if (m.y < -1.0) m.y += SURFACE_Y + 1.0;
        }
        for (&self.bubbles) |*b| {
            b.y += b.vy * dt_f;
            b.z -= CAM_SPEED * dt_f;
            b.phase = @mod(b.phase + 3.1 * dt_f, TWO_PI);
            if (b.y > SURFACE_Y or b.z < 2.5) {
                b.z = 6.0 + rand01(&self.rng) * 28.0;
                b.x = (rand01(&self.rng) - 0.5) * 30.0;
                b.y = self.heightAt(b.x + self.cam_x, self.scroll_z + b.z);
                b.r = 0.04 + 0.08 * rand01(&self.rng);
            }
        }
    }

    /// Everything drawn between depth slices, sorted near to far.
    fn buildItems(self: *State) void {
        var n: usize = 0;
        for (0..NUM_FISH) |i| {
            if (self.fish[i].z > Z_FAR) continue;
            self.items[n] = .{ .rz = self.fish[i].z, .rx = self.fish[i].x, .idx = @intCast(i), .kind = 0 };
            n += 1;
        }
        const half_w = 0.5 * @as(f32, @floatFromInt(self.w));
        for (0..NUM_CORAL) |i| {
            const c = self.corals[i];
            const rz = @mod(c.z - self.scroll_z, TILE);
            if (rz < Z_NEAR + 0.3 or rz > Z_FAR) continue;
            const rx = wrapD(c.x - self.cam_x);
            if (@abs(rx) > rz * half_w / self.focal_px + 1.5) continue;
            self.items[n] = .{ .rz = rz, .rx = rx, .idx = @intCast(i), .kind = c.kind };
            n += 1;
        }
        self.n_items = n;
        var i: usize = 1;
        while (i < n) : (i += 1) {
            const cur = self.items[i];
            var j = i;
            while (j > 0 and self.items[j - 1].rz > cur.rz) : (j -= 1) {
                self.items[j] = self.items[j - 1];
            }
            self.items[j] = cur;
        }
    }

    // ---------------------------------------------------------------- draw --

    inline fn isEmpty(px: u32) bool {
        return (px >> 24) == 0;
    }

    inline fn addPixel(buf: []u32, idx: usize, col: u32) void {
        const dst = buf[idx];
        const r: u32 = @min(255, (dst & 0xFF) + (col & 0xFF));
        const g: u32 = @min(255, ((dst >> 8) & 0xFF) + ((col >> 8) & 0xFF));
        const b: u32 = @min(255, ((dst >> 16) & 0xFF) + ((col >> 16) & 0xFF));
        buf[idx] = 0xFF000000 | (b << 16) | (g << 8) | r;
    }

    /// Scales RGB by gain/256, allowing gains above 1 (saturating).
    inline fn brighten(c: u32, gain: u32) u32 {
        const r: u32 = @min(255, ((c & 0xFF) * gain) >> 8);
        const g: u32 = @min(255, (((c >> 8) & 0xFF) * gain) >> 8);
        const b: u32 = @min(255, (((c >> 16) & 0xFF) * gain) >> 8);
        return 0xFF000000 | (b << 16) | (g << 8) | r;
    }

    inline fn fogged(c: [3]f32, z: f32) u32 {
        const f = 1.0 - @exp(-FOG_K * z);
        return pack3(mix3(c, WATER_HOR, f)) | 0xFF000000;
    }

    /// Opaque thick line that writes only into empty pixels (front-to-back occlusion).
    fn fillLine(buf: []u32, stride: usize, w: i32, h: i32, x0f: f32, y0f: f32, x1f: f32, y1f: f32, thick: f32, col: u32, dq: u32) void {
        if ((x0f < -50 and x1f < -50) or (y0f < -50 and y1f < -50)) return;
        if ((x0f > @as(f32, @floatFromInt(w)) + 50 and x1f > @as(f32, @floatFromInt(w)) + 50)) return;
        if (y0f > @as(f32, @floatFromInt(h)) + 50 and y1f > @as(f32, @floatFromInt(h)) + 50) return;
        const dx = x1f - x0f;
        const dy = y1f - y0f;
        const len = @sqrt(dx * dx + dy * dy);
        if (len > 900) return;
        const steps: usize = @intFromFloat(@min(900.0, @ceil(len)) + 1.0);
        const tw: i32 = @intFromFloat(math.clamp(thick, 1.0, 40.0));
        const half = @divTrunc(tw, 2);
        const vertical = @abs(dy) >= @abs(dx);
        for (0..steps) |s| {
            const t: f32 = if (steps > 1) @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(steps - 1)) else 0.0;
            const cx: i32 = @intFromFloat(@floor(x0f + dx * t));
            const cy: i32 = @intFromFloat(@floor(y0f + dy * t));
            var o: i32 = -half;
            while (o < tw - half) : (o += 1) {
                const px = if (vertical) cx + o else cx;
                const py = if (vertical) cy else cy + o;
                if (px < 0 or py < 0 or px >= w or py >= h) continue;
                const idx = @as(usize, @intCast(py)) * stride + @as(usize, @intCast(px));
                depthWrite(buf, idx, col, dq);
            }
        }
    }

    /// Fills column x from `top` down to `yb` (exclusive). `col` carries depth in
    /// its alpha byte; `prev` is the colour the previous slice left at `yb`.
    /// A short span is ground seen at a slant: blend from `col` to `prev` so slices
    /// don't show as flat bands. A long span is a wall (sponge, coral head, ledge):
    /// the first 0.15 world units below the top are plain, then the tint toward
    /// water grows by 200/256 per world unit, capped at 150, so it reads as a solid side.
    inline fn fillSpan(buf: []u32, stride: usize, x: usize, top: i32, yb: i32, col: u32, prev: u32, water: u32, k: f32) void {
        const wall_px = @max(1.0, 0.9 * k);
        const a = col & 0xFF000000;
        const n = yb - top;
        var idx = @as(usize, @intCast(top)) * stride + x;
        if (@as(f32, @floatFromInt(n)) < 0.15 * wall_px) {
            const dt: u32 = @intCast(@divTrunc(256 * 256, @max(n, 1)));
            var t: u32 = 0;
            var y = top;
            while (y < yb) : (y += 1) {
                buf[idx] = (sdk.lerpRGB(col, prev, t >> 8) & 0x00FFFFFF) | a;
                t += dt;
                idx += stride;
            }
            return;
        }
        const plain_end: i32 = @min(yb, top + @as(i32, @intFromFloat(0.15 * wall_px)));
        var y = top;
        while (y < plain_end) : (y += 1) {
            buf[idx] = col;
            idx += stride;
        }
        const step_q8: u32 = @intFromFloat(@max(1.0, 200.0 * 256.0 / wall_px));
        var tint_q8: u32 = 0;
        while (y < yb) : (y += 1) {
            buf[idx] = (sdk.lerpRGB(col, water, @min(150, tint_q8 >> 8)) & 0x00FFFFFF) | a;
            tint_q8 += step_q8;
            idx += stride;
        }
    }

    /// Depth stored in a pixel's alpha byte while drawing: 255 is nearest, 1 farthest,
    /// 0 means nothing drawn yet. Log-spaced, about 1.8% of depth per step.
    inline fn depthQ(z: f32) u32 {
        const t = @log(@max(z, Z_NEAR) / Z_NEAR) * (254.0 / @log(Z_FAR / Z_NEAR));
        return 255 - @as(u32, @intFromFloat(math.clamp(t, 0.0, 254.0)));
    }

    /// Writes rgb at depth dq if nothing nearer is already there.
    inline fn depthWrite(buf: []u32, idx: usize, rgb: u32, dq: u32) void {
        if ((buf[idx] >> 24) < dq) buf[idx] = (rgb & 0x00FFFFFF) | (dq << 24);
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        if (self.w == 0 or self.h == 0 or stride < self.w) return;
        const w = self.w;
        const h = @min(self.h, buf.len / stride);
        const wi: i32 = @intCast(w);
        const hi: i32 = @intCast(h);

        // Alpha 0 marks "nothing drawn here yet"; otherwise alpha holds depth (see depthQ).
        for (0..h) |y| @memset(buf[y * stride .. y * stride + w], 0);

        // Depth slices, near to far, shared by every strip.
        const Slice = struct { z: f32, k: f32, fog256: u32, dq: u32, iv: i32, tv: f32, caus_z: f32, y_cap: f32, blk_row: usize };
        var slices: [MAX_SLICES]Slice = undefined;
        var n_slices: usize = 0;
        const pb = self.phase(0.5);
        var z: f32 = Z_NEAR;
        while (z < Z_FAR and n_slices < MAX_SLICES) : (z += @max(0.012, z * Z_GROW)) {
            const k = self.focal_px / z;
            // Nothing on the reef can rise above this line at this depth.
            const y_cap = self.horizon_px - (self.h_max - self.cam_y) * k;
            if (y_cap >= @as(f32, @floatFromInt(hi))) continue;
            const wz = self.scroll_z + z;
            const v = wz * TEX;
            const fv = @floor(v);
            const iv: i32 = @intFromFloat(fv);
            slices[n_slices] = .{
                .z = z,
                .k = k,
                .fog256 = @intFromFloat((1.0 - @exp(-FOG_K * z)) * 256.0),
                .dq = depthQ(z),
                .iv = iv,
                .tv = v - fv,
                .caus_z = self.fastSin(wz * 22.0 * K - pb),
                .y_cap = y_cap,
                .blk_row = @as(usize, (@as(u32, @bitCast(iv)) & MAP_MASK) >> BLK_SHIFT) * BLK_N,
            };
            n_slices += 1;
        }

        // The reef, front to back within each 16-pixel-wide strip, so a strip's
        // writes stay in L1 cache. Each column only ever fills upward.
        const pa = self.phase(0.7);
        const water = pack3(WATER_HOR);
        const STRIP: usize = 16;
        var x0: usize = 0;
        while (x0 < w) : (x0 += STRIP) {
            const x1 = @min(x0 + STRIP, w);
            var ybuf: [STRIP]i32 = @splat(hi);
            var pcol: [STRIP]u32 = undefined; // colour each column's last slice left at its ybuf
            for (slices[0..n_slices]) |sl| {
                var yb_strip: i32 = 0;
                for (0..x1 - x0) |j| yb_strip = @max(yb_strip, ybuf[j]);
                const ybs: f32 = @floatFromInt(yb_strip);
                if (ybs <= sl.y_cap) continue;
                // Far away a texel is narrower than a pixel, so neighbouring columns share a sample.
                const xs: usize = if (sl.z >= 30.0) 4 else if (sl.z >= 13.0) 2 else 1;
                var x = x0;
                while (x < x1) : (x += xs) {
                    const x_end = @min(x + xs, x1);
                    var yb_max: i32 = ybuf[x - x0];
                    for (x + 1..x_end) |xc| yb_max = @max(yb_max, ybuf[xc - x0]);
                    const ybf: f32 = @floatFromInt(yb_max);
                    if (ybf <= sl.y_cap) continue;
                    const wx = self.cam_x + self.col_k[x] * sl.z;
                    const u = wx * TEX;
                    const fu = @floor(u);
                    const iu: i32 = @intFromFloat(math.clamp(fu, -1.0e6, 1.0e6));
                    const bu: usize = (@as(u32, @bitCast(iu)) & MAP_MASK) >> BLK_SHIFT;
                    if (self.horizon_px - (self.blk_max[sl.blk_row + bu] - self.cam_y) * sl.k >= ybf) continue;
                    const tu = u - fu;
                    const k00 = texIdx(iu, sl.iv);
                    const k10 = texIdx(iu + 1, sl.iv);
                    const k01 = texIdx(iu, sl.iv + 1);
                    const k11 = texIdx(iu + 1, sl.iv + 1);
                    const ha = self.height[k00] + (self.height[k10] - self.height[k00]) * tu;
                    const hb = self.height[k01] + (self.height[k11] - self.height[k01]) * tu;
                    const hgt = ha + (hb - ha) * sl.tv;
                    const syf = self.horizon_px - (hgt - self.cam_y) * sl.k;
                    if (syf >= ybf) continue;
                    const top: i32 = @intFromFloat(@max(0.0, @ceil(syf)));
                    if (top >= yb_max) continue; // rose less than a pixel: nothing to fill

                    var col: u32 = undefined;
                    if (sl.z < 18.0) {
                        const t_u: u32 = @intFromFloat(tu * 256.0);
                        const t_v: u32 = @intFromFloat(sl.tv * 256.0);
                        const ca = sdk.lerpRGB(self.color[k00], self.color[k10], t_u);
                        const cb = sdk.lerpRGB(self.color[k01], self.color[k11], t_u);
                        col = sdk.lerpRGB(ca, cb, t_v);
                    } else {
                        col = self.color[if (tu < 0.5) (if (sl.tv < 0.5) k00 else k01) else (if (sl.tv < 0.5) k10 else k11)];
                    }
                    // Caustics: a moving net of light from the surface, fading with depth.
                    if (sl.z < 40.0) {
                        const c = self.fastSin(wx * 26.0 * K + pa + 0.6 * sl.caus_z) * sl.caus_z;
                        const caus = @max(0.0, c);
                        const gain: u32 = @intFromFloat(220.0 + 120.0 * caus * caus * (1.0 - sl.z / 40.0));
                        col = brighten(col, gain);
                    }
                    col = (sdk.lerpRGB(col, water, sl.fog256) & 0x00FFFFFF) | (sl.dq << 24);
                    for (x..x_end) |xc| {
                        const yb = ybuf[xc - x0];
                        if (top < yb) {
                            const prev = if (yb == hi) col else pcol[xc - x0];
                            fillSpan(buf, stride, xc, top, yb, col, prev, water, sl.k);
                            ybuf[xc - x0] = top;
                            pcol[xc - x0] = col;
                        }
                    }
                }
            }
        }

        // Corals and fish, depth-tested against the reef and each other.
        for (self.items[0..self.n_items]) |it| self.drawItem(buf, stride, wi, hi, it);

        // Water fills what is left; god rays fall over everything.
        for (0..h) |y| {
            const row = buf[y * stride .. y * stride + w];
            const base = self.row_bg[y];
            const gain = self.row_ray[y];
            const off = (y * RAY_SLANT_Q6) >> 6;
            const rays = self.rays[off .. off + w];
            // 8 pixels at a time: empty pixels take the water colour at full ray gain,
            // drawn pixels get half the gain.
            const V = @Vector(8, u32);
            const gain_v: V = @splat(gain);
            const half_v: V = @splat(gain >> 1);
            const base_v: V = @splat(base);
            const m8: V = @splat(0xFF);
            const c255: V = @splat(255);
            const zero: V = @splat(0);
            const alpha: V = @splat(0xFF000000);
            const tr: V = @splat(self.tint[0]);
            const tg: V = @splat(self.tint[1]);
            const tb: V = @splat(self.tint[2]);
            // Shaft colour: pale cyan at noon, warm gold at sunset and sunrise.
            const ray_r: u32 = @intFromFloat(110.0 + 140.0 * self.gold);
            const ray_g: u32 = @intFromFloat(190.0 - 20.0 * self.gold);
            const ray_b: u32 = @intFromFloat(200.0 - 110.0 * self.gold);
            var x: usize = 0;
            while (x + 8 <= w) : (x += 8) {
                var p: V = row[x..][0..8].*;
                const rv: V = @as(@Vector(8, u8), rays[x..][0..8].*);
                const empty = (p >> @as(V, @splat(24))) == zero;
                const g = @select(u32, empty, gain_v, half_v);
                p = @select(u32, empty, base_v, p);
                const a = (rv * g) >> @as(V, @splat(8));
                const r0 = (p & m8) + ((a * @as(V, @splat(ray_r))) >> @as(V, @splat(8)));
                const g0 = ((p >> @as(V, @splat(8))) & m8) + ((a * @as(V, @splat(ray_g))) >> @as(V, @splat(8)));
                const b0 = ((p >> @as(V, @splat(16))) & m8) + ((a * @as(V, @splat(ray_b))) >> @as(V, @splat(8)));
                // Sun colour: noon, sunset gold, dusk.
                const r: V = @min(c255, (r0 * tr) >> @as(V, @splat(8)));
                const gg: V = @min(c255, (g0 * tg) >> @as(V, @splat(8)));
                const bb: V = @min(c255, (b0 * tb) >> @as(V, @splat(8)));
                row[x..][0..8].* = alpha | (bb << @as(V, @splat(16))) | (gg << @as(V, @splat(8))) | r;
            }
            while (x < w) : (x += 1) {
                var p = row[x];
                var gn = gain;
                if (isEmpty(p)) {
                    p = base;
                } else {
                    gn >>= 1;
                }
                const a = (@as(u32, rays[x]) * gn) >> 8;
                const r: u32 = @min(255, (((p & 0xFF) + ((a * ray_r) >> 8)) * self.tint[0]) >> 8);
                const g: u32 = @min(255, ((((p >> 8) & 0xFF) + ((a * ray_g) >> 8)) * self.tint[1]) >> 8);
                const b: u32 = @min(255, ((((p >> 16) & 0xFF) + ((a * ray_b) >> 8)) * self.tint[2]) >> 8);
                row[x] = 0xFF000000 | (b << 16) | (g << 8) | r;
            }
        }

        // Marine snow and bubbles drift in front.
        const wf: f32 = @floatFromInt(w);
        const hf: f32 = @floatFromInt(h);
        for (self.snow) |m| {
            var sx: f32 = 0;
            var sy: f32 = 0;
            if (!self.project(m.x, m.y - self.cam_y, m.z, &sx, &sy)) continue;
            if (sx < 1 or sy < 1 or sx >= wf - 1 or sy >= hf - 1) continue;
            const lum: u8 = toU8(64.0 * @exp(-0.14 * m.z) + 4.0); // suspended sediment
            const c = sdk.packRGBA(lum >> 1, (lum * 3) >> 2, lum);
            const ux: usize = @intFromFloat(sx);
            const uy: usize = @intFromFloat(sy);
            addPixel(buf, uy * stride + ux, c);
            if (m.z < 6.0) {
                addPixel(buf, uy * stride + ux + 1, c);
                addPixel(buf, (uy + 1) * stride + ux, c);
                addPixel(buf, (uy + 1) * stride + ux + 1, c);
            }
        }
        for (self.bubbles) |b| self.drawBubble(buf, stride, wf, hf, b);
    }

    fn drawItem(self: *const State, buf: []u32, stride: usize, wi: i32, hi: i32, it: Item) void {
        if (it.kind == 0) {
            self.drawFish(buf, stride, wi, hi, self.fish[it.idx]);
            return;
        }
        const c = self.corals[it.idx];
        const ry = c.y - self.cam_y;
        switch (c.kind) {
            3 => return self.drawAnemone(buf, stride, wi, hi, c, it.rx, ry, it.rz),
            4 => return self.drawTable(buf, stride, wi, hi, c, it.rx, ry, it.rz),
            5 => return self.drawClam(buf, stride, wi, hi, c, it.rx, ry, it.rz),
            else => {},
        }
        const base = STAG_BASE[c.style];
        const tip = STAG_TIP[c.style];
        // Fans sway in the surge, bending more toward the top.
        const sway = if (c.kind == 2) 0.10 * self.fastSin(self.phase(0.55) + c.phase) else 0.0;
        const nx = -@sin(c.angle);
        const nz = @cos(c.angle);
        for (self.segs[c.seg_start .. c.seg_start + c.seg_count]) |s| {
            const sa = sway * s.ay * s.ay;
            const sb = sway * s.by * s.by;
            var x0: f32 = 0;
            var y0: f32 = 0;
            var x1: f32 = 0;
            var y1: f32 = 0;
            const za = it.rz + s.az + sa * nz;
            const zb = it.rz + s.bz + sb * nz;
            if (!self.project(it.rx + s.ax + sa * nx, ry + s.ay, za, &x0, &y0)) continue;
            if (!self.project(it.rx + s.bx + sb * nx, ry + s.by, zb, &x1, &y1)) continue;
            const thick = s.thick * self.focal_px / it.rz;
            const col = fogged(mix3(base, tip, s.t * s.t), it.rz);
            fillLine(buf, stride, wi, hi, x0, y0, x1, y1, thick, col, depthQ(it.rz));
        }
    }

    fn drawAnemone(self: *const State, buf: []u32, stride: usize, wi: i32, hi: i32, c: Coral, rx: f32, ry: f32, rz: f32) void {
        const base = ANEM_BASE[c.style];
        const tip = ANEM_TIP[c.style];
        const ph = self.phase(0.8) + c.phase;
        const surge = 0.12 * self.fastSin(self.phase(0.35) + c.phase);
        const thick = 0.085 * c.size * self.focal_px / rz;
        const dq = depthQ(rz);
        // The column (stalk) under the oral disc.
        var bx: f32 = 0;
        var by: f32 = 0;
        var tx: f32 = 0;
        var ty: f32 = 0;
        if (self.project(rx, ry, rz, &bx, &by) and self.project(rx, ry + 0.2 * c.size, rz, &tx, &ty)) {
            fillLine(buf, stride, wi, hi, bx, by, tx, ty, 0.45 * c.size * self.focal_px / rz, fogged(ANEM_COLUMN[c.style], rz), dq);
        }
        for (0..ANEM_TENT) |ti| {
            const a = TWO_PI * (@as(f32, @floatFromInt(ti)) + 0.5) / @as(f32, @floatFromInt(ANEM_TENT));
            const ca = @cos(a);
            const sa = @sin(a);
            var px: f32 = 0;
            var py: f32 = 0;
            var have = false;
            for (0..ANEM_PTS) |k| {
                const kf: f32 = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(ANEM_PTS - 1));
                const out = c.size * (0.25 + 0.55 * kf);
                const up = c.size * (0.15 + 0.75 * kf - 0.35 * kf * kf);
                const wav = kf * (0.10 * self.fastSin(ph + a * 2.0 - kf * 3.0) + surge);
                var sx: f32 = 0;
                var sy: f32 = 0;
                if (!self.project(rx + ca * out + wav, ry + up, rz + sa * out, &sx, &sy)) {
                    have = false;
                    continue;
                }
                if (have) {
                    const col = fogged(mix3(base, tip, kf * kf), rz);
                    fillLine(buf, stride, wi, hi, px, py, sx, sy, thick * (1.0 - 0.4 * kf), col, dq);
                }
                px = sx;
                py = sy;
                have = true;
            }
        }
    }

    /// Fills a screen ellipse centred at (cx, cy) with radii (ax, ay) pixels;
    /// `f(ctx, nx, ny)` gives the colour at normalised position (nx, ny) in the
    /// unit disc, or null to leave the pixel.
    fn fillEllipse(buf: []u32, stride: usize, wi: i32, hi: i32, cx: f32, cy: f32, ax: f32, ay: f32, dq: u32, ctx: anytype, comptime f: anytype) void {
        if (ax < 0.5 or ay < 0.3) return;
        const wf: f32 = @floatFromInt(wi);
        const hf: f32 = @floatFromInt(hi);
        const x0 = math.clamp(cx - ax - 1.0, 0.0, wf);
        const x1 = math.clamp(cx + ax + 1.0, 0.0, wf);
        const y0 = math.clamp(cy - ay - 1.0, 0.0, hf);
        const y1 = math.clamp(cy + ay + 1.0, 0.0, hf);
        if ((x1 - x0) * (y1 - y0) > 800.0 * 800.0) return;
        const inv_ax = 1.0 / ax;
        const inv_ay = 1.0 / ay;
        for (@as(usize, @intFromFloat(y0))..@as(usize, @intFromFloat(y1))) |py| {
            const ny = (@as(f32, @floatFromInt(py)) + 0.5 - cy) * inv_ay;
            for (@as(usize, @intFromFloat(x0))..@as(usize, @intFromFloat(x1))) |px| {
                const nx = (@as(f32, @floatFromInt(px)) + 0.5 - cx) * inv_ax;
                if (nx * nx + ny * ny > 1.0) continue;
                const idx = py * stride + px;
                if ((buf[idx] >> 24) >= dq) continue;
                if (f(ctx, nx, ny)) |c| buf[idx] = (c & 0x00FFFFFF) | (dq << 24);
            }
        }
    }

    /// Table Acropora: a flat plate on a short stalk, seen from above or below.
    fn drawTable(self: *const State, buf: []u32, stride: usize, wi: i32, hi: i32, c: Coral, rx: f32, ry: f32, rz: f32) void {
        const stalk_h = 0.25 + 0.3 * c.size;
        var bx: f32 = 0;
        var by: f32 = 0;
        var px: f32 = 0;
        var py: f32 = 0;
        if (!self.project(rx, ry, rz, &bx, &by)) return;
        if (!self.project(rx, ry + stalk_h, rz, &px, &py)) return;
        const dq = depthQ(rz - 0.2 * c.size);
        const k = self.focal_px / rz;
        const col = TABLE_COLS[c.style];
        fillLine(buf, stride, wi, hi, bx, by, px, py, 0.12 * k, fogged(.{ col[0] * 0.6, col[1] * 0.6, col[2] * 0.6 }, rz), dq);
        // How flat the plate looks depends on how far above or below it we are.
        const elev = math.clamp(-(ry + stalk_h) / @sqrt(rz * rz + (ry + stalk_h) * (ry + stalk_h)), -1.0, 1.0);
        const ax = c.size * k;
        const ay = ax * @max(0.1, @abs(elev));
        const from_above = elev > 0;
        const fog = 1.0 - @exp(-FOG_K * rz);
        const Ctx = struct { col: [3]f32, above: bool, fog: f32, ph: f32 };
        const shade = struct {
            fn f(cx: Ctx, nx: f32, ny: f32) ?u32 {
                const r2 = nx * nx + ny * ny;
                // Top: radial branchlets and paler growing rim; underside: dark.
                const ang = math.atan2(ny, nx);
                const rib = 0.9 + 0.1 * @sin(ang * 26.0 + cx.ph);
                const rim: f32 = if (r2 > 0.82) 1.25 else 1.0;
                const lv: f32 = if (cx.above) rib * rim else 0.45 * rim;
                const c3 = [3]f32{ cx.col[0] * lv, cx.col[1] * lv, cx.col[2] * lv };
                return pack3(mix3(c3, WATER_HOR, cx.fog));
            }
        }.f;
        // The plate's edge thickness, then the plate.
        fillEllipse(buf, stride, wi, hi, px, py + 0.035 * k, ax, ay, dq, Ctx{ .col = .{ col[0] * 0.5, col[1] * 0.5, col[2] * 0.5 }, .above = false, .fog = fog, .ph = c.phase }, shade);
        fillEllipse(buf, stride, wi, hi, px, py, ax, ay, dq, Ctx{ .col = col, .above = from_above, .fog = fog, .ph = c.phase }, shade);
    }

    /// Giant clam set into the reef: a wavy, iridescent mantle between the shell
    /// lips, with a dark inhalant slit, that slowly opens and closes.
    fn drawClam(self: *const State, buf: []u32, stride: usize, wi: i32, hi: i32, c: Coral, rx: f32, ry: f32, rz: f32) void {
        var cx: f32 = 0;
        var cy: f32 = 0;
        if (!self.project(rx, ry + 0.3 * c.size, rz, &cx, &cy)) return;
        const k = self.focal_px / rz;
        const len = c.size * k;
        if (len < 1.0) return;
        const elev = math.clamp(-(ry) / @sqrt(rz * rz + ry * ry), -1.0, 1.0);
        const open = 0.65 + 0.35 * self.fastSin(self.phase(0.09) + c.phase);
        const ax = len;
        const ay = len * (0.25 + 0.35 * @abs(elev)) * (0.6 + 0.4 * open);
        const dq = depthQ(rz - 0.05);
        const Ctx = struct { mantle: [3]f32, fog: f32, gigas: bool, ph: f32, open: f32 };
        const shade = struct {
            fn f(cx2: Ctx, nx: f32, ny: f32) ?u32 {
                // Fluted shell lip around the edge (wavy for the big clams).
                const ang = math.atan2(ny, nx);
                const r = @sqrt(nx * nx + ny * ny);
                const wave = 0.06 * @sin(ang * @as(f32, if (cx2.gigas) 7.0 else 11.0) + cx2.ph);
                var c3: [3]f32 = undefined;
                if (r > 0.84 + wave) {
                    c3 = if (cx2.gigas) .{ 196, 190, 170 } else .{ 120, 116, 100 };
                } else if (@abs(ny) < 0.07 * cx2.open and @abs(nx) < 0.6) {
                    c3 = .{ 20, 24, 30 }; // the slit between the mantle folds
                } else {
                    // Iridescent spots and streaks on the mantle.
                    const spot = @sin(nx * 23.0 + cx2.ph) * @sin(ny * 19.0 - cx2.ph);
                    const glow: f32 = if (spot > 0.55) 1.45 else 1.0;
                    const edge: f32 = if (r > 0.7) 1.25 else 1.0;
                    c3 = .{ @min(255.0, cx2.mantle[0] * glow * edge), @min(255.0, cx2.mantle[1] * glow * edge), @min(255.0, cx2.mantle[2] * glow * edge) };
                }
                return pack3(mix3(c3, WATER_HOR, cx2.fog));
            }
        }.f;
        fillEllipse(buf, stride, wi, hi, cx, cy, ax, ay, dq, Ctx{ .mantle = MANTLE_COLS[c.style], .fog = 1.0 - @exp(-FOG_K * rz), .gigas = c.style == 4, .ph = c.phase * 3.0, .open = open }, shade);
    }

    fn drawBubble(self: *const State, buf: []u32, stride: usize, wf: f32, hf: f32, b: Bubble) void {
        var sx: f32 = 0;
        var sy: f32 = 0;
        const wob = 0.12 * self.fastSin(b.phase);
        if (!self.project(b.x + wob, b.y - self.cam_y, b.z, &sx, &sy)) return;
        const rpx = self.focal_px * b.r / b.z;
        if (rpx < 0.6) return;
        if (sx < -rpx or sy < -rpx or sx > wf + rpx or sy > hf + rpx) return;
        const fade = math.clamp(@exp(-0.04 * b.z), 0.2, 1.0);
        const rim = sdk.packRGBA(toU8(80 * fade), toU8(130 * fade), toU8(150 * fade));
        const segs: usize = @intFromFloat(math.clamp(rpx * 6.0, 8.0, 96.0));
        for (0..segs) |k| {
            const a = TWO_PI * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(segs));
            const px = sx + rpx * self.fastCos(a);
            const py = sy + rpx * self.fastSin(a);
            if (px < 0 or py < 0 or px >= wf or py >= hf) continue;
            addPixel(buf, @as(usize, @intFromFloat(py)) * stride + @as(usize, @intFromFloat(px)), rim);
        }
        const gx = sx - 0.4 * rpx;
        const gy = sy - 0.4 * rpx;
        if (gx >= 0 and gy >= 0 and gx < wf and gy < hf) {
            addPixel(buf, @as(usize, @intFromFloat(gy)) * stride + @as(usize, @intFromFloat(gx)), sdk.packRGBA(toU8(150 * fade), toU8(200 * fade), toU8(210 * fade)));
        }
    }

    fn drawFish(self: *const State, buf: []u32, stride: usize, wi: i32, hi: i32, f: Fish) void {
        // Fish pitch only a little even when climbing, so flatten vy for the body axis.
        const hs = @sqrt(f.vx * f.vx + f.vz * f.vz);
        const pv = math.clamp(0.3 * f.vy, -0.4 * hs, 0.4 * hs);
        const sp_o = @sqrt(f.vx * f.vx + pv * pv + f.vz * f.vz);
        var dx: f32 = 1;
        var dy: f32 = 0;
        var dz: f32 = 0;
        if (sp_o > 1e-4) {
            dx = f.vx / sp_o;
            dy = pv / sp_o;
            dz = f.vz / sp_o;
        }
        const half = 0.5 * f.size;
        const ry = f.y - self.cam_y;
        var hx: f32 = 0;
        var hy: f32 = 0;
        var tx: f32 = 0;
        var ty: f32 = 0;
        if (!self.project(f.x + dx * half, ry + dy * half, f.z + dz * half, &hx, &hy)) return;
        if (!self.project(f.x - dx * half, ry - dy * half, f.z - dz * half, &tx, &ty)) return;
        const fog256: u32 = @intFromFloat((1.0 - @exp(-FOG_K * f.z)) * 256.0);
        const dq = depthQ(f.z);
        const w: usize = @intCast(wi);
        const h: usize = @intCast(hi);
        inline for (0..N_SPECIES) |si| {
            if (f.kind == si) {
                const S = SPECIES[si];
                const W = self.focal_px * f.size * S.half_depth / f.z;
                drawCreature(S, buf, stride, w, h, hx, hy, tx, ty, W, f.wag, f.seed, dq, fog256);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (!math.isFinite(self.time_sec) or !math.isFinite(self.scroll_z) or !math.isFinite(self.cam_x)) return true;
        for (self.fish) |f| {
            if (!math.isFinite(f.x) or !math.isFinite(f.y) or !math.isFinite(f.z)) return true;
        }
        return false;
    }
};

// --------------------------------------------------------------- creatures --

/// Draws one animal with depth test and fog. (hx, hy) and (tx, ty) are the
/// projected nose and tail tip in pixels; W is the half depth in pixels.
/// The species contract (see the species structs below):
///   u: along the body, 0 at the nose (top when upright) to 1 at the tail tip
///   s: across the body in units of W; s < 0 is the back, s > 0 the belly
///   t: animation phase in radians; seed: 0..1 per animal
fn drawCreature(comptime S: type, buf: []u32, stride: usize, w: usize, h: usize, hx_in: f32, hy_in: f32, tx_in: f32, ty_in: f32, W: f32, t: f32, seed: f32, dq: u32, fog256: u32) void {
    if (W < 0.4) return;
    var hx = hx_in;
    var hy = hy_in;
    var tx = tx_in;
    var ty = ty_in;
    var ax = tx - hx;
    var ay = ty - hy;
    var L = @sqrt(ax * ax + ay * ay);
    if (S.upright) {
        // Head on top, axis vertical, centred where the animal is.
        const mx = 0.5 * (hx + tx);
        const my = 0.5 * (hy + ty);
        L = W / S.half_depth;
        ax = 0;
        ay = 1;
        hx = mx;
        hy = my - 0.5 * L;
        tx = mx;
        ty = my + 0.5 * L;
    } else {
        if (L < 1e-3) {
            ax = 1;
            ay = 0;
            L = 1;
        }
        ax /= L;
        ay /= L;
        // Seen nose-on it still reads as an animal, not a dot.
        const min_l = 2.2 * W;
        if (L < min_l) {
            const mx = 0.5 * (hx + tx);
            const my = 0.5 * (hy + ty);
            L = min_l;
            hx = mx - ax * 0.5 * L;
            hy = my - ay * 0.5 * L;
            tx = mx + ax * 0.5 * L;
            ty = my + ay * 0.5 * L;
        }
    }
    const pad = S.extent * W + 2.0;
    const wf: f32 = @floatFromInt(w);
    const hf: f32 = @floatFromInt(h);
    const x_lo = math.clamp(@min(hx, tx) - pad, 0.0, wf);
    const x_hi = math.clamp(@max(hx, tx) + pad, 0.0, wf);
    const y_lo = math.clamp(@min(hy, ty) - pad, 0.0, hf);
    const y_hi = math.clamp(@max(hy, ty) + pad, 0.0, hf);
    if (x_hi - x_lo < 1 or y_hi - y_lo < 1) return;
    if ((x_hi - x_lo) * (y_hi - y_lo) > 1100.0 * 1100.0) return;

    const water = State.pack3(WATER_HOR);
    const belly: f32 = if (S.upright) 1.0 else if (ax >= 0) 1.0 else -1.0;
    const inv_L = 1.0 / L;
    const inv_W = 1.0 / W;
    const yi0: usize = @intFromFloat(y_lo);
    const yi1: usize = @intFromFloat(y_hi);
    // Along a row, u and s are linear in x: u = u0 + du*x, s = s0 + ds*x.
    // Clip each row to where both are in range, then step them incrementally.
    const du = ax * inv_L;
    const ds = -ay * inv_W * belly;
    for (yi0..yi1) |py| {
        const dy = @as(f32, @floatFromInt(py)) + 0.5 - hy;
        const u_c = dy * ay * inv_L - (hx - 0.5) * du; // u at pixel centre x = 0
        const s_c = dy * ax * inv_W * belly - (hx - 0.5) * ds;
        var lo = x_lo;
        var hi = x_hi;
        clipLinear(u_c, du, -0.05, 1.05, &lo, &hi);
        clipLinear(s_c, ds, -S.extent, S.extent, &lo, &hi);
        if (hi <= lo) continue;
        const xa: usize = @intFromFloat(@max(x_lo, @floor(lo)));
        const xb: usize = @intFromFloat(@min(x_hi, @ceil(hi)));
        var u = u_c + du * @as(f32, @floatFromInt(xa));
        var sv = s_c + ds * @as(f32, @floatFromInt(xa));
        for (xa..xb) |px| {
            defer {
                u += du;
                sv += ds;
            }
            const idx = py * stride + px;
            if ((buf[idx] >> 24) >= dq) continue; // something nearer is already here
            if (u < -0.05 or u > 1.05 or @abs(sv) > S.extent) continue;
            if (S.shade(u, sv, t, seed)) |c| {
                const rgb = sdk.lerpRGB(State.pack3(c), water, fog256);
                buf[idx] = (rgb & 0x00FFFFFF) | (dq << 24);
            }
        }
    }
}

/// Narrows [lo, hi] to the x where v0 + dv*x lies in [a, b].
inline fn clipLinear(v0: f32, dv: f32, a: f32, b: f32, lo: *f32, hi: *f32) void {
    if (@abs(dv) < 1e-9) {
        if (v0 < a or v0 > b) hi.* = lo.*;
        return;
    }
    const x1 = (a - v0) / dv;
    const x2 = (b - v0) / dv;
    lo.* = @max(lo.*, @min(x1, x2) - 1.0);
    hi.* = @min(hi.*, @max(x1, x2) + 1.0);
}

/// The classic reef-fish body shared by the four original species: blunt nose,
/// deepest a third of the way back, forked tail. Returns null outside it, else
/// the across-body position k (0 back .. 1 belly), whether the point is on the
/// tail, and how close it is to the edge (for an outline).
/// Half-width profile of the classic body along u (64 steps), built at compile time.
const CLASSIC_PROF: [64]f32 = blk: {
    @setEvalBranchQuota(20000);
    var out: [64]f32 = undefined;
    for (0..64) |i| {
        const u = @as(f32, @floatFromInt(i)) / 63.0;
        const p = @min(u / 0.78, 1.0);
        out[i] = if (u <= 0.78) 0.18 + 0.82 * @sin(math.pi * math.pow(f32, p, 0.62)) else 0.18;
    }
    break :blk out;
};

const ClassicHit = struct { k: f32, tail: bool, edge: f32, sb: f32 };
fn classicBody(u: f32, s: f32, t: f32) ?ClassicHit {
    const sb = s - 0.5 * @sin(t) * u * u;
    const a = @abs(sb);
    var hw: f32 = if (u >= 0.0 and u <= 1.0) CLASSIC_PROF[@as(usize, @intFromFloat(u * 63.0))] else 0.0;
    var tail = false;
    if (u > 0.74 and u <= 1.0) {
        const tf = (u - 0.74) / 0.26;
        const notch: f32 = if (tf > 0.7) 0.5 * (tf - 0.7) / 0.3 else 0.0;
        if (1.05 * tf > hw and a > notch) {
            hw = 1.05 * tf;
            tail = true;
        }
    }
    if (a > hw) return null;
    return .{ .k = 0.5 + 0.5 * math.clamp(sb / @max(hw, 0.05), -1.0, 1.0), .tail = tail, .edge = hw - a, .sb = sb };
}

fn classicFinish(c_in: [3]f32, hit: ClassicHit, u: f32, W_px_hint: f32) [3]f32 {
    _ = W_px_hint;
    var c = c_in;
    if (hit.edge < 0.07) c = .{ c[0] * 0.7, c[1] * 0.7, c[2] * 0.7 };
    const eu = (u - 0.12) / 0.06;
    const ev = (hit.sb + 0.22) / 0.17;
    if (eu * eu + ev * ev < 1.0) c = .{ 14, 14, 20 };
    return c;
}

const EasternClownfish = struct {
    pub const name = "Eastern clown anemonefish (Amphiprion percula)";
    pub const author = "Claude Opus";
    pub const length: f32 = 0.08;
    pub const half_depth: f32 = 0.24;
    pub const extent: f32 = 1.3;
    pub const upright = false;
    pub const speed: f32 = 0.9;
    pub const count: u8 = 5;
    pub const school = true;
    pub const habitat: u8 = 0;
    pub const anchor: u8 = 2; // lives in its host anemone
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        const hit = classicBody(u, s, t) orelse return null;
        var c = State.mix3(.{ 240, 104, 18 }, .{ 255, 140, 40 }, hit.k);
        // Three white bars (head, middle, tail root), each with a thick black edge.
        const bars = [3][2]f32{ .{ 0.17, 0.27 }, .{ 0.44, 0.56 }, .{ 0.74, 0.80 } };
        for (bars) |b| {
            if (u > b[0] and u < b[1]) c = .{ 250, 248, 244 };
            if ((u > b[0] - 0.035 and u <= b[0]) or (u >= b[1] and u < b[1] + 0.035)) c = .{ 26, 18, 14 };
        }
        if (hit.tail and u > 0.93) c = .{ 26, 18, 14 };
        return classicFinish(c, hit, u, 0);
    }
};

const BlacktipShark = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Blacktip reef shark";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip. For scale: a neon tetra
    /// is 0.34, a clownfish 0.5, a yellow tang 0.7, the big silver fish 1.1.
    pub const length: f32 = 1.5;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.10;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 2.6;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves (seahorse, jellyfish). false points the head where
    /// it swims and keeps the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed relative to a clownfish (1.0). Sharks ~1.4, lionfish ~0.4.
    pub const speed: f32 = 0.6;
    /// How many live in the reef (1..24).
    pub const count: u8 = 4;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = false;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 1;
    pub const dusk = true; // aggregations recorded especially at sunset (ISRA)

    /// Fin or tail colour: near-black tip, dark grey on the back, pale on the belly.
    fn finCol(sb: f32, tip: bool) [3]f32 {
        if (tip) return .{ 18, 18, 22 };
        if (sb < 0.0) return .{ 78, 86, 92 };
        return .{ 210, 212, 210 };
    }

    /// True if (px, py) lies inside the triangle a, b, c.
    fn inTri(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) bool {
        const d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
        const d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
        const d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
        const neg = d1 < 0.0 or d2 < 0.0 or d3 < 0.0;
        const pos = d1 > 0.0 or d2 > 0.0 or d3 > 0.0;
        return !(neg and pos);
    }

    /// Colour of the animal at one point, or null if the point is outside it.
    ///   u    : along the body, 0 at the nose (or the top when upright) to 1 at
    ///          the tail tip. Called for u in [-0.05, 1.05].
    ///   s    : across the body in units of W (= length * half_depth).
    ///          s < 0 is the back (dorsal side), s > 0 the belly. Called for
    ///          s in [-extent, extent].
    ///   t    : this animal's animation phase in radians. It advances about
    ///          6-10 rad per second; sin(t) is a good tail beat.
    ///   seed : 0..1, fixed per animal, for individual variation.
    /// Return RGB in 0..255 (unlit; the reef adds fog). It runs once per pixel
    /// the animal covers, so keep it cheap: a handful of sin/cos at most, no
    /// loops over more than ~8 items, no allocation, no panics (clamp before any
    /// @intFromFloat), no globals with state.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        // Sinuous sweep: the rear half swings from side to side.
        const rear = math.clamp((u - 0.45) / 0.55, 0.0, 1.0);
        const sb = s - 0.7 * @sin(t) * rear * rear;
        const a = @abs(sb);

        // Body: pointed snout, deepest near the first dorsal, slim tail root.
        const p = math.clamp(u / 0.8, 0.0, 1.0);
        const hw: f32 = if (u >= 0.0 and u <= 0.8) 0.04 + 0.96 * @sin(math.pi * math.pow(f32, p, 0.8)) else 0.0;
        if (a <= hw) {
            // Counter-shading: grey-bronze back, white belly.
            const k = 0.5 + 0.5 * math.clamp(sb / @max(hw, 0.05), -1.0, 1.0);
            const m = math.clamp((k - 0.3) / 0.4, 0.0, 1.0);
            var c = [3]f32{ 86 + 160 * m, 92 + 154 * m, 92 + 146 * m };
            // Five faint gill slits behind the head.
            if (u > 0.15 and u < 0.27 and a < 0.4 and @mod((u - 0.15) / 0.024, 1.0) < 0.2) {
                c = .{ c[0] * 0.72, c[1] * 0.72, c[2] * 0.72 };
            }
            // Dark outline band along the edge.
            if (hw - a < 0.09) c = .{ c[0] * 0.55, c[1] * 0.55, c[2] * 0.55 };
            // Small dark eye.
            const eu = (u - 0.10) / 0.022;
            const ev = (sb + 0.20) / 0.22;
            if (eu * eu + ev * ev < 1.0) return [3]f32{ 12, 12, 16 };
            return c;
        }

        // Fins and tail, each a triangle in (u, sb) space.
        // First dorsal (back), tall, black tip.
        // Bases sit well inside the body so every fin grows out of it.
        if (inTri(u, sb, 0.29, -0.2, 0.44, -2.2, 0.57, -0.2)) return finCol(sb, -sb > 1.85);
        // Second dorsal and anal fin near the tail.
        if (inTri(u, sb, 0.66, -0.1, 0.78, -0.85, 0.84, -0.1)) return finCol(sb, -sb > 0.7);
        if (inTri(u, sb, 0.66, 0.1, 0.78, 0.7, 0.84, 0.1)) return finCol(sb, sb > 0.6);
        // Pectoral (belly), swept back, black tip.
        if (inTri(u, sb, 0.16, 0.2, 0.44, 1.9, 0.34, 0.2)) return finCol(sb, sb > 1.5 and u > 0.36);
        // Heterocercal tail: long upper lobe, shorter lower lobe, black tips.
        // Both lobes start deep inside the tail root, so there is no gap.
        if (inTri(u, sb, 0.62, -0.1, 1.0, -2.0, 0.93, -0.12)) return finCol(sb, u > 0.93 and sb < -1.7);
        if (inTri(u, sb, 0.62, 0.1, 0.97, 0.85, 0.93, 0.12)) return finCol(sb, u > 0.9 and sb > 0.6);
        return null;
    }
};

const Parrotfish = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Stoplight Parrotfish";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip.
    pub const length: f32 = 0.45;
    /// Half the body depth (top-to-belly) as a fraction of length.
    pub const half_depth: f32 = 0.24;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    pub const extent: f32 = 1.4;
    /// Head forward along the swim direction, belly down.
    pub const upright: bool = false;
    /// Cruise speed relative to a clownfish (1.0).
    pub const speed: f32 = 0.8;
    /// How many live in the reef (1..24).
    pub const count: u8 = 6;
    /// Parrotfish here wander alone.
    pub const school: bool = false;
    /// Hugs the reef.
    pub const habitat: u8 = 0;

    /// Colour of the animal at one point, or null if the point is outside it.
    /// u: 0 at the beak tip, 1 at the tail tip. s: across the body in W units,
    /// negative on the back. t: animation phase (sin(t) drives the tail beat and
    /// the pectoral fin). seed: unused, every parrotfish looks the same.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        const Mix = struct {
            fn go(a: [3]f32, b: [3]f32, m: f32) [3]f32 {
                return .{ a[0] + (b[0] - a[0]) * m, a[1] + (b[1] - a[1]) * m, a[2] + (b[2] - a[2]) * m };
            }
        };
        // Bend: the tail swings, growing toward the tail tip.
        const sb = s - 0.18 * @sin(t) * u * u;
        const a = @abs(sb);
        // Body: blunt rounded head, deepest about a third in, slim peduncle at u = 0.8.
        const p = math.clamp(u / 0.8, 0.0, 1.0);
        const hw: f32 = if (u >= 0.0 and u <= 0.8) 0.12 + 0.88 * @sin(math.pi * math.pow(f32, p, 0.7)) else 0.0;
        // One long dorsal fin, from behind the head to the peduncle.
        const fh: f32 = if (sb < 0.0 and u > 0.08 and u <= 0.8) 0.27 * @sqrt(@max(0.0, @sin(math.pi * (u - 0.08) / 0.72))) else 0.0;
        // Crescent tail: lobes widen toward the tip, a notch bites into the middle.
        const tf: f32 = math.clamp((u - 0.8) / 0.2, 0.0, 1.0);
        const notch: f32 = 0.4 * tf * tf;
        const th: f32 = 0.12 + 0.95 * tf;
        const tail = u > 0.8 and u <= 1.0 and a > notch and a <= th;
        const fin = !tail and fh > 0.0 and a > hw and a <= hw + fh;
        const body = u >= 0.0 and u <= 0.8 and a <= hw;
        if (!(tail or fin or body)) return null;

        const k = 0.5 + 0.5 * math.clamp(sb / 0.9, -1.0, 1.0); // 0 back .. 1 belly
        const teal = [3]f32{ 40 + 40 * k, 150 + 60 * k, 140 + 30 * k };
        var c = teal;
        if (tail) {
            c = .{ 62, 192, 166 };
            if (a > th - 0.16 or a < notch + 0.07) c = .{ 250, 128, 64 };
        } else if (fin) {
            c = .{ 84, 212, 190 };
            if (a > hw + 0.6 * fh) c = .{ 250, 118, 104 };
            if (@abs(@sin(u * 150.0)) < 0.15) c = Mix.go(c, .{ 40, 130, 130 }, 0.35);
        } else {
            // Scales: a sheared grid whose edges are pink-orange.
            const gx = 140.0 * u + 12.0 * sb;
            const gy = 40.0 * sb;
            const e = @min(@abs(@sin(gx)), @abs(@sin(gy)));
            const m = math.clamp(1.0 - e / 0.2, 0.0, 1.0) * 0.7;
            c = Mix.go(teal, .{ 246, 124, 92 }, m);
            // Dark outline band along the edge.
            if (hw - a < 0.07) c = .{ c[0] * 0.6, c[1] * 0.6, c[2] * 0.6 };
            // Pectoral fin near the gill, flapping with sin(t).
            if (u > 0.2 and u < 0.44 and sb > -0.05 and sb < 0.5) {
                const ang = 0.35 * @sin(t);
                const du = u - 0.32;
                const ds = sb - 0.24;
                const cs = @cos(ang);
                const sn = @sin(ang);
                const pu = (du * cs + ds * sn) / 0.09;
                const ps = (-du * sn + ds * cs) / 0.25;
                const pr = pu * pu + ps * ps;
                if (pr < 1.0) {
                    c = Mix.go(c, .{ 176, 242, 222 }, 0.6);
                    if (pr > 0.6) c = .{ 250, 130, 110 };
                }
            }
            // Orange-pink cheek patch.
            const cu = (u - 0.19) / 0.06;
            const cv = (sb - 0.3) / 0.12;
            if (cu * cu + cv * cv < 1.0) c = Mix.go(c, .{ 255, 102, 122 }, 0.85);
            // Fused parrot beak with a pale teeth plate.
            if (u < 0.08 and sb > -0.15 and sb < 0.4) {
                c = .{ 240, 238, 224 };
                if (u > 0.035 and u < 0.045) c = .{ 190, 188, 178 };
            }
            // Eye: dark pupil in a gold ring.
            const eu = (u - 0.14) / 0.055;
            const ev = (sb + 0.2) / 0.15;
            const d2 = eu * eu + ev * ev;
            if (d2 < 0.36) {
                c = .{ 16, 16, 22 };
            } else if (d2 < 1.0) {
                c = .{ 244, 206, 74 };
            }
        }
        return c;
    }
};

const GreenTurtle = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Green sea turtle";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip.
    pub const length: f32 = 1.0;
    /// Half the body depth (top-to-belly) as a fraction of length.
    pub const half_depth: f32 = 0.28;
    /// The largest |s| the shape reaches (the front flipper sweeps to about 2).
    pub const extent: f32 = 2.4;
    /// Head points where the animal swims, belly down the screen.
    pub const upright: bool = false;
    /// Cruise speed relative to a clownfish.
    pub const speed: f32 = 0.35;
    /// How many live in the reef (1..24).
    pub const count: u8 = 2;
    /// Turtles wander alone.
    pub const school: bool = false;
    /// Mid-water.
    pub const habitat: u8 = 0;

    fn rgb(r: f32, g: f32, b: f32) [3]f32 {
        return .{ r, g, b };
    }

    /// Grey-green skin with a pale scale pattern (dots on a grid in length units).
    fn skin(x: f32, y: f32, r: f32, g: f32, b: f32) [3]f32 {
        const gx = x * 46.0;
        const gy = y * 46.0;
        const dx = gx - @floor(gx) - 0.5;
        const dy = gy - @floor(gy) - 0.5;
        if (dx * dx + dy * dy < 0.07) return rgb(176, 190, 160);
        return rgb(r, g, b);
    }

    /// Positive inside a tapered flipper rooted at (rx, ry), pointing along ang
    /// (0 = straight down the belly, positive = swept back toward the tail).
    /// Negative outside. Value is the distance to the edge, in length units.
    fn flipperInside(x: f32, y: f32, rx: f32, ry: f32, ang: f32, len: f32, w0: f32, w1: f32) f32 {
        const dx = @sin(ang);
        const dy = @cos(ang);
        const px = x - rx;
        const py = y - ry;
        const al = px * dx + py * dy;
        if (al < -0.06 or al > len) return -1.0;
        const f = math.clamp(al / len, 0.0, 1.0);
        const omf = 1.0 - f;
        const hw = w1 + (w0 - w1) * omf * @sqrt(1.0 - f * f + 0.02);
        const pe = px * dy - py * dx - 0.5 * al * al; // bow the leading edge back into a wing curve
        return hw - @abs(pe);
    }

    /// Colour of the animal at one point, or null if the point is outside it.
    ///   u    : along the body, 0 at the nose to 1 at the tail tip.
    ///   s    : across the body in units of W (= length * half_depth).
    ///          s < 0 is the back (carapace), s > 0 the belly.
    ///   t    : animation phase; sin(t) drives the flipper stroke.
    ///   seed : 0..1, per-animal variation (unused here).
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        // Work in length units: x along the body, y across (+ belly).
        const x = u;
        const y = s * half_depth;
        const sw = @sin(t);

        // Eye: dark with a pale ring, on the head.
        const ex = (x - 0.12) / 0.022;
        const ey = (y + 0.035) / 0.022;
        const e2 = ex * ex + ey * ey;
        if (e2 <= 1.0) {
            if (e2 < 0.42) return rgb(14, 14, 18);
            return rgb(214, 208, 170);
        }

        // Front flipper: long, sweeps in a slow wing stroke from the shoulder.
        const fd = flipperInside(x, y, 0.27, 0.06, 0.45 + 0.35 * sw, 0.3 + 0.05 * sw, 0.12, 0.03);
        if (fd >= 0.0) {
            if (fd < 0.012) return rgb(44, 56, 42);
            return skin(x, y, 118, 138, 110);
        }

        // Small rear flipper.
        const rd = flipperInside(x, y, 0.74, 0.07, 0.6 + 0.1 * sw, 0.17, 0.05, 0.02);
        if (rd >= 0.0) {
            if (rd < 0.01) return rgb(44, 56, 42);
            return skin(x, y, 112, 132, 104);
        }

        // Head and neck, with a small hooked beak at the front.
        const hcy = -0.02 + 0.006 * sw;
        const hqx = (x - 0.09) / 0.10;
        const hqy = (y - hcy) / 0.075;
        const hr2 = hqx * hqx + hqy * hqy;
        const nqx = (x - 0.18) / 0.075;
        const nqy = (y + 0.03) / 0.065;
        const nr2 = nqx * nqx + nqy * nqy;
        if (hr2 <= 1.0 or nr2 <= 1.0) {
            if (x < 0.03 and hr2 <= 1.0) return rgb(72, 66, 46);
            if (@min(hr2, nr2) > 0.84) return rgb(44, 56, 44);
            return skin(x, y, 110, 130, 102);
        }

        // Carapace (dome on the back) and plastron (pale line underneath).
        const qx = (x - 0.49) / 0.33;
        if (y <= 0.03) {
            const qy = (y - 0.03) / 0.26;
            const r2 = qx * qx + qy * qy;
            if (r2 <= 1.0) {
                if (r2 > 0.86) return rgb(36, 38, 20);
                // Scutes: staggered hexagon-ish plates with dark seams.
                const gy = (y + 0.23) * 12.0;
                const row = @floor(gy);
                const gx = (x - 0.49) * 12.0 + (if (@mod(row, 2.0) == 0.0) @as(f32, 0.0) else 0.5);
                const cx = @floor(gx);
                const fx = gx - cx;
                const fy = gy - row;
                if (@min(fx, 1.0 - fx) < 0.08 or @min(fy, 1.0 - fy) < 0.08) return rgb(54, 48, 26);
                const h = math.clamp((-y - 0.02) / 0.22, 0.0, 1.0); // dome highlight
                const alt: f32 = if (@mod(cx + row, 2.0) == 0.0) 0.94 else 1.0;
                return rgb((98 + 30 * h) * alt, (102 + 26 * h) * alt, (50 + 18 * h) * alt);
            }
        } else {
            const qb = (y - 0.03) / 0.09;
            const r2 = qx * qx + qb * qb;
            if (r2 <= 1.0) {
                if (r2 > 0.86) return rgb(40, 50, 38);
                if (y < 0.055) return rgb(224, 210, 152); // pale plastron line
                return skin(x, y, 104, 124, 96);
            }
        }

        // Tail: short and pointed, emerging from under the shell rim.
        if (x >= 0.80 and x <= 1.0) {
            const tf = (x - 0.80) / 0.20;
            const hwt = 0.05 * math.pow(f32, 1.0 - tf, 0.9);
            const ta = @abs(y);
            if (ta < hwt) {
                if (hwt - ta < 0.01) return rgb(40, 46, 34);
                return skin(x, y, 92, 110, 82);
            }
        }
        return null;
    }
};

const Damselfish = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Damselfish";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in METRES, nose to tail tip (real adult size).
    pub const length: f32 = 0.08;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.27;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 1.4;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves. false points the head where it swims and keeps
    /// the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed in body lengths per second (about 1 for most reef fish,
    /// 0.3 for slow hoverers, 0.6 for sharks).
    pub const speed: f32 = 1.2;
    /// How many live in the scene (1..80).
    pub const count: u8 = 60;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = true;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 0;
    pub const anchor: u8 = 1; // clouds over a coral head

    /// Colour of the animal at one point, or null if the point is outside it.
    ///   u    : along the body, 0 at the nose (or the top when upright) to 1 at
    ///          the tail tip. Called for u in [-0.05, 1.05].
    ///   s    : across the body in units of W (= length * half_depth).
    ///          s < 0 is the back (dorsal side), s > 0 the belly. Called for
    ///          s in [-extent, extent].
    ///   t    : this animal's animation phase in radians. It advances about
    ///          6-10 rad per second; sin(t) is a good tail beat.
    ///   seed : 0..1, fixed per animal, for individual variation.
    /// Return RGB in 0..255 (unlit; the reef adds fog). It runs once per pixel
    /// the animal covers, so keep it cheap: a handful of sin/cos at most, no
    /// math.pow, no loops over more than ~8 items, no allocation, no panics
    /// (clamp before any @intFromFloat), no globals with state.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        // Tail flick: the body bends, more toward the forked tail.
        const sb = s - 0.22 * @sin(t) * u * u;
        const a = @abs(sb);
        const dorsal = sb < 0.0;
        const humbug = seed >= 0.85;
        const yellow = seed >= 0.6 and seed < 0.85;

        // Deep oval body: blunt snout, deepest near u = 0.36, slim peduncle.
        var hw: f32 = 0.0;
        if (u >= 0.0 and u <= 0.78) {
            const xs: f32 = if (u < 0.36) (0.36 - u) / 0.36 else (u - 0.36) / 0.42;
            hw = 0.2 + 0.8 * @sqrt(@max(0.0, 1.0 - xs * xs));
        } else if (u > 0.78 and u <= 0.84) {
            hw = 0.2;
        }

        // Forked caudal fin: two lobes flare out with a central notch.
        var tf: f32 = 0.0;
        var tail = false;
        if (u > 0.78 and u <= 1.0) {
            tf = (u - 0.78) / 0.22;
            tail = a > 0.4 * tf * tf and a <= 0.8 * tf + 0.04;
        }

        // Dorsal fin (continuous, spiny front, softer back), anal fin, pelvics.
        var fh: f32 = 0.0;
        var pelvic = false;
        if (dorsal) {
            if (u >= 0.08 and u <= 0.76) {
                const dt = (u - 0.08) / 0.68;
                const ramp = math.clamp((u - 0.08) / 0.05, 0.0, 1.0) * math.clamp((0.76 - u) / 0.06, 0.0, 1.0);
                fh = 0.34 * (1.0 - 0.4 * dt) * ramp * (0.9 + 0.1 * @sin(u * 150.0));
            }
        } else if (u >= 0.46 and u <= 0.76) {
            fh = 0.22 * @sin(math.pi * (u - 0.46) / 0.3);
        } else if (u >= 0.16 and u <= 0.28) {
            fh = 0.16 * @sin(math.pi * (u - 0.16) / 0.12);
            pelvic = true;
        }

        const in_body = a <= hw;
        const in_fin = !in_body and a <= hw + fh;
        if (!tail and !in_body and !in_fin) return null;

        // Palette: blue-green chromis (default), lemon damsel, or humbug.
        var lo: [3]f32 = .{ 30, 106, 134 };
        var hi: [3]f32 = .{ 146, 224, 206 };
        var fin: [3]f32 = .{ 44, 130, 160 };
        if (yellow) {
            lo = .{ 232, 162, 18 };
            hi = .{ 255, 226, 70 };
            fin = .{ 250, 200, 40 };
        } else if (humbug) {
            lo = .{ 214, 214, 210 };
            hi = .{ 250, 250, 246 };
            fin = .{ 240, 240, 236 };
        }
        const k = 0.5 + 0.5 * math.clamp(sb / @max(hw, 0.05), -1.0, 1.0); // 0 back .. 1 belly

        var c: [3]f32 = undefined;
        if (tail) {
            c = fin;
            if (0.8 * tf + 0.04 - a < 0.06) {
                c[0] *= 0.45;
                c[1] *= 0.45;
                c[2] *= 0.45;
            }
        } else if (in_body) {
            c = .{ lo[0] + (hi[0] - lo[0]) * k, lo[1] + (hi[1] - lo[1]) * k, lo[2] + (hi[2] - lo[2]) * k };
            // Three bold black bars on the humbug.
            const bar = (u > 0.20 and u < 0.26) or (u > 0.45 and u < 0.52) or (u > 0.70 and u < 0.75);
            if (humbug and bar) c = .{ 22, 22, 28 };
            // Iridescent sheen on the blue-green chromis.
            if (!humbug and !yellow) {
                const hl = 1.0 - @min(1.0, @abs(k - 0.3) * 3.5);
                c[0] += 12.0 * hl;
                c[1] += 26.0 * hl;
                c[2] += 20.0 * hl;
            }
            // Dark outline band along the edge.
            if (hw - a < @min(0.07, 0.4 * hw)) {
                c[0] *= 0.72;
                c[1] *= 0.72;
                c[2] *= 0.72;
            }
            // Large eye with a pale iris and a black pupil.
            const eu = (u - 0.13) / 0.075;
            const ev = (sb + 0.16) / 0.24;
            const r2 = eu * eu + ev * ev;
            if (r2 < 1.0) {
                c = if (r2 < 0.45) [3]f32{ 12, 12, 18 } else [3]f32{ 176, 206, 206 };
            }
            // Small terminal mouth.
            if (u < 0.04 and @abs(sb - 0.06) < 0.035) c = .{ 70, 36, 34 };
        } else {
            c = if (pelvic and humbug) [3]f32{ 22, 22, 28 } else fin;
            if (hw + fh - a < 0.05) {
                c[0] *= 0.6;
                c[1] *= 0.6;
                c[2] *= 0.6;
            }
        }
        return c;
    }
};

const Fusilier = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Yellowback fusilier";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in METRES, nose to tail tip (real adult size).
    pub const length: f32 = 0.30;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.14;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 1.3;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves. false points the head where it swims and keeps
    /// the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed in body lengths per second (about 1 for most reef fish,
    /// 0.3 for slow hoverers, 0.6 for sharks).
    pub const speed: f32 = 1.5;
    /// How many live in the scene (1..80).
    pub const count: u8 = 48;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = true;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 1;

    /// Colour of the animal at one point, or null if the point is outside it.
    ///   u    : along the body, 0 at the nose (or the top when upright) to 1 at
    ///          the tail tip. Called for u in [-0.05, 1.05].
    ///   s    : across the body in units of W (= length * half_depth).
    ///          s < 0 is the back (dorsal side), s > 0 the belly. Called for
    ///          s in [-extent, extent].
    ///   t    : this animal's animation phase in radians. It advances about
    ///          6-10 rad per second; sin(t) is a good tail beat.
    ///   seed : 0..1, fixed per animal, for individual variation.
    /// Return RGB in 0..255 (unlit; the reef adds fog). It runs once per pixel
    /// the animal covers, so keep it cheap: a handful of sin/cos at most, no
    /// math.pow, no loops over more than ~8 items, no allocation, no panics
    /// (clamp before any @intFromFloat), no globals with state.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        // Tail beat: the rear of the body swings side to side.
        const sb = s - 0.22 * @sin(t) * u * u;
        const a = @abs(sb);
        // Fusiform body: rounded nose, deepest at about 40 %, slim tail root.
        const q = (u - 0.4) / 0.4;
        const ell = @sqrt(math.clamp(1.0 - q * q, 0.0, 1.0));
        var hw: f32 = 0.0;
        if (u >= 0.0 and u <= 0.4) {
            hw = ell;
        } else if (u > 0.4 and u <= 0.8) {
            hw = 0.12 + 0.88 * ell;
        }
        // Forked tail: lobes flare out from a slim root, notched in the middle.
        var tail = false;
        if (u > 0.8 and u <= 1.0) {
            const tf = (u - 0.8) / 0.2;
            const outer = 0.14 + 0.72 * tf;
            const notch = 0.36 * @max(0.0, tf - 0.2) / 0.8;
            if (outer > hw and a > notch) {
                hw = outer;
                tail = true;
            }
        }
        // Low dorsal fin on the back, growing out of the body with no gap.
        var dors: f32 = 0.0;
        if (sb < 0.0 and u > 0.26 and u < 0.64) {
            dors = 0.24 * @sin(math.pi * (u - 0.26) / 0.38);
        }
        const lim = hw + dors;
        if (a > lim) return null;
        const fin = dors > 0.0 and a > hw;
        const edge = lim - a < 0.07;

        var c: [3]f32 = undefined;
        if (tail) {
            c = .{ 255, 204, 34 };
        } else if (fin) {
            c = .{ 255, 222, 80 };
        } else {
            // 0 back .. 1 belly.
            const k = 0.5 + 0.5 * math.clamp(sb / @max(hw, 0.05), -1.0, 1.0);
            // Yellow back starts just behind the head and sweeps into the tail.
            const yel_mask = math.clamp((u - 0.12) / 0.1, 0.0, 1.0);
            const yw = @max(
                yel_mask * math.clamp((0.42 - k) / 0.16, 0.0, 1.0),
                math.clamp((u - 0.62) / 0.12, 0.0, 1.0) * math.clamp((0.70 - k) / 0.20, 0.0, 1.0),
            );
            const sw = math.clamp((k - 0.68) / 0.16, 0.0, 1.0);
            const bw = @max(0.0, 1.0 - yw - sw);
            c = .{
                yw * 255 + bw * 22 + sw * 222,
                yw * 205 + bw * 112 + sw * 234,
                yw * 34 + bw * 235 + sw * 246,
            };
        }
        if (edge) c = .{ c[0] * 0.6, c[1] * 0.6, c[2] * 0.6 }; // dark outline
        // Small upturned mouth at the front of the upper lip.
        if (u < 0.04 and sb < -0.1 and sb > -0.17) c = .{ 40, 22, 20 };
        // Medium eye: dark pupil in a gold iris.
        const eu = (u - 0.13) / 0.035;
        const ev = (sb + 0.25) / 0.25;
        const r2 = eu * eu + ev * ev;
        if (r2 < 1.0) c = if (r2 < 0.45) .{ 12, 12, 18 } else .{ 240, 200, 110 };
        return c;
    }
};

const PickhandleBarracuda = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Pickhandle barracuda (Sphyraena jello)";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in METRES, nose to tail tip (real adult size).
    pub const length: f32 = 0.9;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.08;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 1.6;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves. false points the head where it swims and keeps
    /// the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed in body lengths per second (about 1 for most reef fish,
    /// 0.3 for slow hoverers, 0.6 for sharks).
    pub const speed: f32 = 0.5;
    /// How many live in the scene (1..80).
    pub const count: u8 = 40;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = true;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 1;
    pub const anchor: u8 = 1; // ~300 recorded around one bommie (PCRF)

    /// Colour of the animal at one point, or null if the point is outside it.
    ///   u    : along the body, 0 at the nose (or the top when upright) to 1 at
    ///          the tail tip. Called for u in [-0.05, 1.05].
    ///   s    : across the body in units of W (= length * half_depth).
    ///          s < 0 is the back (dorsal side), s > 0 the belly. Called for
    ///          s in [-extent, extent].
    ///   t    : this animal's animation phase in radians. It advances about
    ///          6-10 rad per second; sin(t) is a good tail beat.
    ///   seed : 0..1, fixed per animal, for individual variation.
    /// Return RGB in 0..255 (unlit; the reef adds fog). It runs once per pixel
    /// the animal covers, so keep it cheap: a handful of sin/cos at most, no
    /// math.pow, no loops over more than ~8 items, no allocation, no panics
    /// (clamp before any @intFromFloat), no globals with state.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        // Stiff tail sweep: almost no bend in front, the tail swings at the end.
        const bend: f32 = 0.2 * @sin(t) * u * u * u;
        const sb = s - bend;
        const a = @abs(sb);
        // Body outline: pointed head, deepest near u = 0.42, slim peduncle.
        var hw: f32 = 0.0;
        var tail = false;
        if (u >= 0.0 and u < 0.42) {
            hw = 0.12 + 0.88 * @sin(0.5 * math.pi * u / 0.42);
        } else if (u >= 0.42 and u <= 0.86) {
            const x = (u - 0.42) / 0.44;
            hw = 1.0 - 0.76 * x * x;
        } else if (u > 0.86 and u <= 1.0) {
            // Forked tail: lobes flare out, a notch cuts the middle away.
            const tf = (u - 0.86) / 0.14;
            const gap = 0.45 * tf * tf;
            if (a < gap) return null;
            hw = 0.24 + 0.72 * tf;
            tail = true;
        }
        if (a > hw) {
            if (sb >= 0.0) return null;
            // Two small dorsal fins, grown from the back (no gap at the base).
            if (finHit(u, a, hw, 0.46, 0.10, 0.38) or finHit(u, a, hw, 0.80, 0.07, 0.30)) {
                return .{ 124, 128, 108 };
            }
            return null;
        }
        // Colour: dark blue-grey back, silver flank, white belly.
        const q = math.clamp(sb / @max(hw, 0.05), -1.0, 1.0);
        const k = 0.5 + 0.5 * q; // 0 back .. 1 belly
        var c = mix3(.{ 44, 58, 72 }, .{ 176, 186, 194 }, math.clamp(k * 1.6, 0.0, 1.0));
        c = mix3(c, .{ 236, 239, 241 }, math.clamp((k - 0.7) * 3.3, 0.0, 1.0));
        if (tail) {
            // Yellow-tinged caudal fin with a dark trailing edge.
            var tc = [3]f32{ 226, 196, 70 };
            if (u > 0.96) tc = .{ 70, 60, 34 };
            c = tc;
        } else if (k < 0.55 and u > 0.2) {
            // Oblique dark chevrons on the upper half, fading toward the belly.
            const p = (u - 0.2) * 27.0 + 0.6 * q;
            if (@mod(p, 1.0) < 0.42) {
                const fade = math.clamp((0.55 - k) * 3.0, 0.0, 1.0);
                c = mix3(c, .{ 30, 36, 46 }, 0.85 * fade);
            }
        }
        // Teeth line along the lower jaw.
        if (u > 0.01 and u < 0.10 and sb > 0.05 and sb < 0.11 and @mod(u * 60.0, 1.0) < 0.5) {
            c = .{ 250, 250, 246 };
        }
        // Dark outline band near the edge.
        if (hw - a < 0.08) c = .{ c[0] * 0.72, c[1] * 0.72, c[2] * 0.72 };
        // Large eye with a gold iris.
        const eu = (u - 0.14) / 0.04;
        const ev = (sb + 0.2) / 0.10;
        const r2 = eu * eu + ev * ev;
        if (r2 < 1.0 and r2 >= 0.35) c = .{ 214, 178, 78 };
        if (r2 < 0.35) c = .{ 14, 14, 18 };
        return c;
    }

    fn mix3(a: [3]f32, b: [3]f32, m: f32) [3]f32 {
        return .{ a[0] + (b[0] - a[0]) * m, a[1] + (b[1] - a[1]) * m, a[2] + (b[2] - a[2]) * m };
    }

    fn finHit(u: f32, a: f32, hw: f32, uc: f32, wd: f32, fh: f32) bool {
        const d = @abs(u - uc);
        if (d >= wd) return false;
        const tri = 1.0 - d / wd;
        return a <= hw + fh * tri;
    }
};

const WhitetipShark = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Whitetip reef shark";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in METRES, nose to tail tip (real adult size).
    pub const length: f32 = 1.5;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.10;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 2.4;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves. false points the head where it swims and keeps
    /// the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed in body lengths per second (about 1 for most reef fish,
    /// 0.3 for slow hoverers, 0.6 for sharks).
    pub const speed: f32 = 0.35;
    /// How many live in the scene (1..80).
    pub const count: u8 = 3;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = false;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 0;

    /// Colour of the animal at one point, or null if the point is outside it.
    ///   u    : along the body, 0 at the nose (or the top when upright) to 1 at
    ///          the tail tip. Called for u in [-0.05, 1.05].
    ///   s    : across the body in units of W (= length * half_depth).
    ///          s < 0 is the back (dorsal side), s > 0 the belly. Called for
    ///          s in [-extent, extent].
    ///   t    : this animal's animation phase in radians. It advances about
    ///          6-10 rad per second; sin(t) is a good tail beat.
    ///   seed : 0..1, fixed per animal, for individual variation.
    /// Return RGB in 0..255 (unlit; the reef adds fog). It runs once per pixel
    /// the animal covers, so keep it cheap: a handful of sin/cos at most, no
    /// math.pow, no loops over more than ~8 items, no allocation, no panics
    /// (clamp before any @intFromFloat), no globals with state.
    /// Body half-width (in W) at u: blunt rounded snout, full body at the
    /// pectorals, slim caudal peduncle, nothing past the tail root.
    fn bodyHalf(u: f32) f32 {
        if (u < 0.0 or u > 0.92) return 0.0;
        if (u < 0.20) {
            const q = (0.20 - u) / 0.20;
            return 0.9 * @sqrt(@max(0.0, 1.0 - q * q));
        }
        if (u < 0.40) return 0.9;
        if (u < 0.85) {
            const q = (u - 0.40) / 0.45;
            return 0.42 + 0.48 * @cos(q * 0.5 * math.pi);
        }
        return 0.42 * (0.92 - u) / 0.07;
    }

    /// Height of the first dorsal above the back at u (0 where there is none).
    fn dorsalH(u: f32) f32 {
        const f0: f32 = 0.40;
        const f1: f32 = 0.50;
        const f2: f32 = 0.64;
        if (u < f0 or u > f2) return 0.0;
        if (u <= f1) return 1.9 * (u - f0) / (f1 - f0);
        return 1.9 * (f2 - u) / (f2 - f1);
    }

    fn inEllipse(u: f32, s: f32, cu: f32, cs: f32, ru: f32, rs: f32) bool {
        const du = (u - cu) / ru;
        const ds = (s - cs) / rs;
        return du * du + ds * ds < 1.0;
    }

    fn inTri(u: f32, s: f32, ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) bool {
        const d1 = (u - bx) * (ay - by) - (ax - bx) * (s - by);
        const d2 = (u - cx) * (by - cy) - (bx - cx) * (s - cy);
        const d3 = (u - ax) * (cy - ay) - (cx - ax) * (s - ay);
        const neg = d1 < 0.0 or d2 < 0.0 or d3 < 0.0;
        const pos = d1 > 0.0 or d2 > 0.0 or d3 > 0.0;
        return !(neg and pos);
    }

    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        // Sinuous bend: a travelling wave, strongest toward the tail.
        const sb = s - 0.30 * @sin(t - 3.0 * u) * u * u;
        const a = @abs(sb);
        const hw = bodyHalf(u);
        // Back (k = 0) to belly (k = 1) shading, eased so the back stays grey-brown.
        const kl = 0.5 + 0.5 * math.clamp(sb / @max(hw, 0.05), -1.0, 1.0);
        const k = kl * kl * (3.0 - 2.0 * kl);
        // Snout: flared tube-like nasal flap under the nose.
        if (inEllipse(u, sb, 0.07, 0.60, 0.06, 0.16)) return [3]f32{ 118, 112, 110 };
        // Eye: small oval on the side of the head.
        if (inEllipse(u, sb, 0.12, -0.22, 0.035, 0.09)) return [3]f32{ 14, 14, 20 };
        var c = [3]f32{ 70 + 156 * k, 66 + 158 * k, 60 + 156 * k };
        if (a <= hw) {
            // A few scattered dark flank spots.
            if (inEllipse(u, sb, 0.27, 0.10, 0.016, 0.07) or
                inEllipse(u, sb, 0.33, -0.30, 0.016, 0.07) or
                inEllipse(u, sb, 0.62, 0.25, 0.016, 0.07) or
                inEllipse(u, sb, 0.70, -0.20, 0.016, 0.07))
            {
                c = .{ 58, 54, 52 };
            }
            // Dark outline band near the edge.
            if (hw > 0.2 and hw - a < 0.06) c = .{ c[0] * 0.62, c[1] * 0.62, c[2] * 0.62 };
            return c;
        }
        // Fins grow out of the body, so every fin overlaps the body edge.
        var fin = false;
        var white = false;
        // First dorsal, set well back; white tip at the apex.
        if (-sb > hw and -sb <= dorsalH(u)) {
            fin = true;
            if (-sb > 1.45) white = true;
        }
        // Second dorsal, small, near the tail root.
        if (inTri(u, sb, 0.74, -0.5, 0.84, -0.5, 0.78, -0.95)) fin = true;
        // Pectoral: broad and swept, below the body.
        if (inTri(u, sb, 0.16, 0.75, 0.42, 0.85, 0.30, 1.60)) fin = true;
        // Anal fin, small, under the tail root.
        if (inTri(u, sb, 0.72, 0.45, 0.84, 0.45, 0.80, 0.95)) fin = true;
        // Caudal fin: large upper lobe with white tip, smaller lower lobe with white tip.
        if (inTri(u, sb, 0.78, -0.35, 0.98, -1.25, 0.92, 0.0)) {
            fin = true;
            if (-sb > 0.95) white = true;
        }
        if (inTri(u, sb, 0.78, 0.35, 0.96, 0.80, 0.92, 0.0)) {
            fin = true;
            if (sb > 0.60) white = true;
        }
        if (white) return [3]f32{ 246, 246, 242 };
        if (fin) return [3]f32{ c[0] * 0.9, c[1] * 0.9, c[2] * 0.9 };
        return null;
    }
};

const TawnyNurseShark = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Tawny nurse shark";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in METRES, nose to tail tip (real adult size).
    pub const length: f32 = 2.6;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.10;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 2.2;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves. false points the head where it swims and keeps
    /// the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed in body lengths per second (about 1 for most reef fish,
    /// 0.3 for slow hoverers, 0.6 for sharks).
    pub const speed: f32 = 0.2;
    /// How many live in the scene (1..80).
    pub const count: u8 = 2;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = false;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 0;

    /// Falcate fin in (u, v) space: v is the height off the body in W units,
    /// lead0..trail0 is the base on the body, tip is the posterior point at
    /// height h. The leading edge runs straight to the tip; the trailing edge
    /// is concave (sickle-shaped).
    fn fin(u: f32, v: f32, lead0: f32, trail0: f32, tip: f32, h: f32) bool {
        if (v < 0.35 or v > h) return false;
        const f = (v - 0.35) / (h - 0.35);
        const lead = lead0 + (tip - lead0) * f;
        const trail = trail0 + (tip - trail0) * f * f;
        return u >= lead and u <= trail;
    }

    /// Upper caudal lobe: the long blade that carries the tail.
    fn upperTail(u: f32, v: f32) bool {
        if (u < 0.76 or u > 1.0 or v < 0.0) return false;
        const top = 1.45 * @sqrt(math.clamp((u - 0.76) / 0.24, 0.0, 1.0));
        const rear = 0.90 + 0.10 * math.clamp(v / 1.45, 0.0, 1.0);
        return v <= top and u <= rear;
    }

    /// Small lower caudal lobe.
    fn lowerTail(u: f32, sb: f32) bool {
        if (u < 0.80 or u > 0.95 or sb < 0.0) return false;
        return sb <= 0.30 * (1.0 - (u - 0.80) / 0.15);
    }

    /// Colour of the animal at one point, or null if the point is outside it.
    ///   u    : along the body, 0 at the nose (or the top when upright) to 1 at
    ///          the tail tip. Called for u in [-0.05, 1.05].
    ///   s    : across the body in units of W (= length * half_depth).
    ///          s < 0 is the back (dorsal side), s > 0 the belly. Called for
    ///          s in [-extent, extent].
    ///   t    : this animal's animation phase in radians. It advances about
    ///          6-10 rad per second; sin(t) is a good tail beat.
    ///   seed : 0..1, fixed per animal, for individual variation.
    /// Return RGB in 0..255 (unlit; the reef adds fog). It runs once per pixel
    /// the animal covers, so keep it cheap: a handful of sin/cos at most, no
    /// math.pow, no loops over more than ~8 items, no allocation, no panics
    /// (clamp before any @intFromFloat), no globals with state.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        // Slow sinuous swim: the tail sways, growing toward the tip.
        const sb = s - 0.25 * @sin(t) * u * u;
        const a = @abs(sb);
        const v = -sb; // back (dorsal side) is positive

        // Trunk: blunt rounded snout, thick body, tapering to a slim tail root.
        var hw: f32 = 0.0;
        if (u >= 0.0 and u <= 0.80) {
            const nose = @sqrt(math.clamp(u / 0.16, 0.0, 1.0));
            const tp = math.clamp((u - 0.55) / 0.25, 0.0, 1.0);
            const ts = tp * tp * (3.0 - 2.0 * tp);
            hw = (1.10 - 0.55 * ts) * nose;
        } else if (u > 0.80 and u <= 0.97) {
            hw = 0.55 - 0.43 * math.clamp((u - 0.80) / 0.17, 0.0, 1.0);
        }
        const body = a <= hw and hw > 0.0;

        // Nasal barbels: small tapered flaps just ahead of the mouth, belly side.
        if (u >= -0.025 and u < 0.0 and sb > 0.12 and sb < 0.22) {
            return [3]f32{ 200, 160, 118 };
        }

        // Fins: two falcate dorsals of similar size set far back, the large
        // sickle pectorals, small pelvics, and the caudal lobes.
        const fins = fin(u, v, 0.36, 0.58, 0.62, 1.95) or
            fin(u, v, 0.62, 0.76, 0.79, 1.90) or
            fin(u, sb, 0.12, 0.36, 0.38, 2.10) or
            fin(u, sb, 0.58, 0.66, 0.68, 1.60) or
            upperTail(u, v) or
            lowerTail(u, sb);

        if (!body and !fins) return null;

        const span: f32 = if (body) @max(hw, 0.05) else 1.2;
        const k = 0.5 + 0.5 * math.clamp(sb / span, -1.0, 1.0); // 0 back .. 1 belly
        // Uniform tawny dorsum, slightly paler sandy belly.
        var c = [3]f32{ 150 + 76 * k, 102 + 98 * k, 56 + 100 * k };
        if (!body) c = .{ c[0] * 0.9, c[1] * 0.9, c[2] * 0.9 };
        if (body) {
            if (hw - a < 0.08) c = .{ c[0] * 0.7, c[1] * 0.7, c[2] * 0.7 }; // outline
            // Mouth, gill slits and eye.
            if (u >= 0.05 and u <= 0.09 and sb >= 0.40 and sb <= 0.46) c = .{ 70, 45, 30 };
            const gu = (u - 0.20) / 0.032;
            if (gu >= 0.0 and gu <= 4.5 and @mod(gu, 1.0) < 0.30 and sb > -0.22 and sb < 0.05) c = .{ 60, 40, 28 };
            const eu = (u - 0.11) / 0.016;
            const ev = (sb + 0.30) / 0.07;
            if (eu * eu + ev * ev < 1.0) c = .{ 14, 12, 12 };
        }
        return c;
    }
};

const BarramundiCod = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Barramundi cod";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in METRES, nose to tail tip (real adult size).
    pub const length: f32 = 0.55;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.24;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 1.6;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves. false points the head where it swims and keeps
    /// the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed in body lengths per second (about 1 for most reef fish,
    /// 0.3 for slow hoverers, 0.6 for sharks).
    pub const speed: f32 = 0.4;
    /// How many live in the scene (1..80).
    pub const count: u8 = 3;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = false;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 0;

    /// Colour of the animal at one point, or null if the point is outside it.
    ///   u    : along the body, 0 at the nose (or the top when upright) to 1 at
    ///          the tail tip. Called for u in [-0.05, 1.05].
    ///   s    : across the body in units of W (= length * half_depth).
    ///          s < 0 is the back (dorsal side), s > 0 the belly. Called for
    ///          s in [-extent, extent].
    ///   t    : this animal's animation phase in radians. It advances about
    ///          6-10 rad per second; sin(t) is a good tail beat.
    ///   seed : 0..1, fixed per animal, for individual variation.
    /// Return RGB in 0..255 (unlit; the reef adds fog). It runs once per pixel
    /// the animal covers, so keep it cheap: a handful of sin/cos at most, no
    /// math.pow, no loops over more than ~8 items, no allocation, no panics
    /// (clamp before any @intFromFloat), no globals with state.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        // Bend: the tail sways, growing toward the tip.
        const sb = s - 0.25 * @sin(t) * u * u;
        const a = @abs(sb);
        const bh = backH(u);
        const bv = bellyH(u);
        const fd = dorsalH(u);
        const fa = analH(u);
        const body = u >= 0.0 and u <= 0.8 and sb >= -bh and sb <= bv;
        const dorsal = fd > 0.0 and sb <= -bh + 0.02 and sb >= -(bh + fd);
        const anal = fa > 0.0 and sb >= bv - 0.02 and sb <= bv + fa;
        // Caudal fin: a rounded fan. Edges flare out from the peduncle, and the
        // trailing margin is convex (tips at u ~ 0.96, centre at u ~ 1.04).
        const lat = 0.42 + 3.0 * (u - 0.8);
        const back_edge = 1.04 - 0.08 * a * a;
        const tail = u >= 0.75 and u <= back_edge and a <= lat;
        const te = @min(back_edge - u, lat - a);
        if (!body and !dorsal and !anal and !tail) return null;
        // Creamy belly, pale grey-green back.
        const k = math.clamp((sb + bh) / (bh + bv + 0.001), 0.0, 1.0);
        var c = [3]f32{ 168 + 70 * k, 184 + 52 * k, 166 + 56 * k };
        if (!body) c = .{ c[0] * 0.5 + 214 * 0.5, c[1] * 0.5 + 232 * 0.5, c[2] * 0.5 + 220 * 0.5 };
        // Soft fin bases: a faint dark seam where the dorsal and anal fins meet the body.
        if (u < 0.8 and ((dorsal and @abs(sb + bh) < 0.03) or (anal and @abs(sb - bv) < 0.03))) {
            c = .{ c[0] * 0.75, c[1] * 0.75, c[2] * 0.75 };
        }
        // Round black spots over head, body and fins.
        if (spotAt(u, sb, seed)) c = .{ 34, 30, 30 };
        // Dark outline band along the silhouette.
        const outline = if (tail and u > 0.79) te < 0.05 else (u < 0.05 or @min(sb + bh + fd, bv + fa - sb) < 0.08);
        if (outline) c = .{ c[0] * 0.6, c[1] * 0.6, c[2] * 0.6 };
        // Small eye, high on the head.
        const eu = (u - 0.14) / 0.045;
        const ev = (sb + 0.2) / 0.12;
        const ed = eu * eu + ev * ev;
        if (ed < 0.6) {
            c = .{ 16, 16, 20 };
        } else if (ed < 1.0) {
            c = .{ 222, 196, 110 };
        }
        return c;
    }

    /// Back (dorsal) half-height at u: small pointed head, a steep hump over
    /// the front third, then a long slope down to the tail root.
    fn backH(u: f32) f32 {
        if (u < 0.35) {
            const p = u / 0.35;
            return 0.12 + 0.83 * @sin(0.5 * math.pi * p) - 0.06 * @sin(math.pi * p) * (1.0 - p);
        }
        const q = math.clamp((u - 0.35) / 0.45, 0.0, 1.0);
        return 0.95 - 0.5 * q * @sqrt(q);
    }

    /// Belly half-height at u: flatter underside, narrow tail root.
    fn bellyH(u: f32) f32 {
        if (u < 0.4) return 0.1 + 0.62 * @sin(0.5 * math.pi * math.clamp(u / 0.4, 0.0, 1.0));
        const q = math.clamp((u - 0.4) / 0.4, 0.0, 1.0);
        return 0.72 - 0.3 * q;
    }

    /// Soft dorsal fin height above the back, from behind the hump to the peduncle.
    fn dorsalH(u: f32) f32 {
        if (u <= 0.3 or u >= 0.86) return 0.0;
        return 0.34 * @sin(math.pi * (u - 0.3) / 0.56);
    }

    /// Anal fin depth below the belly.
    fn analH(u: f32) f32 {
        if (u <= 0.45 or u >= 0.86) return 0.0;
        return 0.26 * @sin(math.pi * (u - 0.45) / 0.41);
    }

    /// Cheap hash in 0..1 for one grid cell.
    fn cellHash(x: f32, y: f32) f32 {
        const v = @sin(x * 12.9898 + y * 78.233) * 43758.5453;
        return v - @floor(v);
    }

    /// True where a round spot sits. The grid is 0.16 (u) by 0.67 (s), which
    /// is square in physical units, so spots come out round. About half the
    /// cells hold one, larger on some cells than others.
    fn spotAt(u: f32, s: f32, seed: f32) bool {
        const cu = u / 0.16;
        const cs = s / 0.67;
        const iu = @floor(cu);
        const is = @floor(cs);
        const h1 = cellHash(iu + 31.0 * seed, is);
        if (h1 < 0.45) return false;
        const du = cu - iu - (0.35 + 0.3 * cellHash(is + 7.1, iu + 3.3 + 31.0 * seed));
        const ds = cs - is - (0.35 + 0.3 * cellHash(iu + 1.7, is + 5.5 + 31.0 * seed));
        const r = 0.16 + 0.06 * math.clamp((h1 - 0.45) / 0.55, 0.0, 1.0);
        return du * du + ds * ds < r * r;
    }
};

// @@SPECIES_INSERT@@

comptime {
    sdk.exportTheme(State);
}

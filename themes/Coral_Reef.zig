// @argus-theme: custom_shader
// ============================================================================
// CORAL REEF // themes/Coral_Reef.zig
// Author: Claude Opus (Anthropic), 2026-10-15.
//
// A slow drift down a sandy channel through a shallow reef. Brain corals,
// barrel sponges and rock covered in coralline algae are a solid, lit
// heightfield. Staghorn corals branch out of it, sea fans and anemones sway,
// and twelve species live on it: schools of yellow tangs, clownfish, silver
// fish and moorish idols; blacktip reef sharks and manta rays cruising; moray
// eels, lionfish, parrotfish and seahorses close to the reef; sea turtles and
// moon jellyfish in open water. It is an imagined reef, not a real site (see
// Lizard_Island.zig for that).
// Light comes down in moving shafts and caustics ripple over the reef, which
// fades into blue with distance.
//
// Choosing species: edit the SPECIES list below. Each species is a small
// struct at the bottom of the file with its own count, size, speed, habitat
// and a shade(u, s, t, seed) function that paints one point of the animal.
//
// How it is drawn: the reef is a 128 x 128 unit tile baked once at init
// (height plus lit colour, 16 texels per unit) and rendered voxel-space style:
// depth slices are marched near to far in 16-pixel-wide strips, and each
// column only fills upward from what is already drawn. While drawing, a
// pixel's alpha byte holds its depth, so corals and fish are depth-tested
// against the reef and each other afterwards. Water and god rays fill
// whatever is left and restore alpha to opaque.
//
// Lineage: the schooling and god rays come from Gemini_Aquarium, Claude
// Opus's rework of Google Gemini's Gemini_Cyber_Topography; the reef's rock
// ridges are Gemini's canyon harmonics, made periodic so the tile wraps.
// Nine species were designed by Claude Haiku agents, one each (shark, moray,
// lionfish, manta, turtle, moorish idol, parrotfish, seahorse, moon jelly);
// each struct's `author` says so.
//
// Contract: one alloc.create(State) at init (~32.6 MiB, mostly the reef map),
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
const TILE: f32 = 128.0; // world units per tile, both axes
const K: f32 = TWO_PI / TILE; // base spatial frequency; every periodic term is a multiple
const MAP_N: usize = 2048;
const MAP_MASK: u32 = MAP_N - 1;
const BLK_SHIFT: u5 = 6; // 64 x 64 texel blocks for the coarse max-height map
const BLK_N: usize = MAP_N >> BLK_SHIFT;
const BLK_MASK: u32 = BLK_N - 1;
const TEX: f32 = @as(f32, @floatFromInt(MAP_N)) / TILE; // texels per world unit

// ------------------------------------------------------------------- camera --
const HORIZON: f32 = 0.40; // horizon line as a fraction of height
const FOCAL: f32 = 0.80; // focal length as a fraction of height
const CAM_SPEED: f32 = 0.5; // world units per second along +z
const CAM_Y: f32 = 6.2;
const Z_NEAR: f32 = 0.8;
const Z_FAR: f32 = 72.0;
const Z_GROW: f32 = 0.019;
const MAX_SLICES: usize = 512; // depth slice spacing as a fraction of depth
const FOG_K: f32 = 0.028;
const SURFACE_Y: f32 = 14.0;

// ------------------------------------------------------------------- things --
const NUM_STAG: usize = 170;
const NUM_FAN: usize = 90;
const NUM_ANEM: usize = 110;
const NUM_CORAL: usize = NUM_STAG + NUM_FAN + NUM_ANEM;
const STAG_SEGS: usize = 56;
const FAN_SEGS: usize = 90;
const MAX_SEGS: usize = NUM_STAG * STAG_SEGS + NUM_FAN * FAN_SEGS;
const MAX_ITEMS: usize = NUM_FISH + NUM_CORAL;
const ANEM_TENT: usize = 20;
const ANEM_PTS: usize = 5;
const NUM_SNOW: usize = 380;
const NUM_BUBBLES: usize = 48;
const PROF_N: usize = 64;

const RAY_SLANT_Q6: usize = 26; // god-ray slant: 26/64 px of x per px of y
const RAY_N: usize = MAX_W + (MAX_H * RAY_SLANT_Q6 >> 6) + 2;
const WATER_HOR = [3]f32{ 10, 56, 86 };

// ------------------------------------------------------------------ species --
// Which animals live on the reef. Delete a line to remove a species, or move
// one to the front; each species struct (bottom of this file) sets its own
// count, size, speed and habitat.
const SPECIES = .{
    YellowTang,
    Clownfish,
    SilverFish,
    BlacktipShark,
    MorayEel,
    Lionfish,
    MantaRay,
    Parrotfish,
    Seahorse,
    MoonJelly,
    SeaTurtle,
    MoorishIdol,
};

const N_SPECIES: usize = SPECIES.len;

/// Per-species numbers the simulation needs at run time.
const SpeciesInfo = struct { start: u16, count: u16, length: f32, half_depth: f32, speed: f32, school: bool, habitat: u8, upright: bool };

const SPECIES_INFO: [N_SPECIES]SpeciesInfo = blk: {
    var out: [N_SPECIES]SpeciesInfo = undefined;
    var start: u16 = 0;
    for (0..N_SPECIES) |i| {
        const S = SPECIES[i];
        out[i] = .{ .start = start, .count = S.count, .length = S.length, .half_depth = S.half_depth, .speed = S.speed, .school = S.school, .habitat = S.habitat, .upright = S.upright };
        start += S.count;
    }
    break :blk out;
};

const NUM_FISH: usize = blk: {
    var n: usize = 0;
    for (0..N_SPECIES) |i| n += SPECIES[i].count;
    break :blk n;
};

const BRAIN_COLS = [5][3]f32{ .{ 128, 170, 96 }, .{ 200, 170, 112 }, .{ 220, 130, 164 }, .{ 156, 104, 186 }, .{ 96, 168, 176 } };
const SPONGE_COLS = [4][3]f32{ .{ 146, 72, 176 }, .{ 232, 124, 52 }, .{ 226, 196, 66 }, .{ 196, 64, 92 } };
const STAG_BASE = [4][3]f32{ .{ 214, 150, 96 }, .{ 92, 140, 212 }, .{ 212, 120, 172 }, .{ 168, 190, 84 } };
const STAG_TIP = [4][3]f32{ .{ 250, 224, 186 }, .{ 186, 226, 255 }, .{ 252, 204, 232 }, .{ 232, 244, 156 } };
const FAN_BASE = [3][3]f32{ .{ 150, 56, 172 }, .{ 206, 58, 80 }, .{ 228, 140, 58 } };
const FAN_TIP = [3][3]f32{ .{ 206, 132, 230 }, .{ 248, 132, 140 }, .{ 252, 200, 120 } };
const ANEM_BASE = [3][3]f32{ .{ 170, 224, 120 }, .{ 236, 200, 140 }, .{ 120, 200, 210 } };
const ANEM_TIP = [3][3]f32{ .{ 240, 120, 200 }, .{ 255, 236, 200 }, .{ 200, 120, 240 } };

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
        return 64.0 + 14.0 * @sin(K * z) + 6.0 * @sin(2.0 * K * z + 1.0);
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
        const top = [3]f32{ 34, 112, 136 };
        const bot = [3]f32{ 6, 26, 48 };
        for (0..self.h) |y| {
            const ny = @as(f32, @floatFromInt(y)) / hf;
            const c = if (ny < HORIZON)
                mix3(top, WATER_HOR, math.pow(f32, ny / HORIZON, 0.8))
            else
                mix3(WATER_HOR, bot, math.pow(f32, (ny - HORIZON) / (1.0 - HORIZON), 0.7));
            self.row_bg[y] = pack3(c);
            const g = 150.0 * @exp(-2.2 * ny) * (1.0 - smoothstep(0.6, 1.0, ny));
            self.row_ray[y] = @intFromFloat(math.clamp(g, 0.0, 256.0));
        }

        var rng = self.rng;
        self.bakeReef(&rng);
        self.buildCorals(&rng);

        for (0..N_SPECIES) |si| {
            const info = SPECIES_INFO[si];
            for (info.start..info.start + info.count) |i| {
                self.fish[i] = .{
                    .x = (rand01(&rng) - 0.5) * 24.0,
                    .y = habitatY(info.habitat) + (rand01(&rng) - 0.5) * 2.0,
                    .z = 8.0 + rand01(&rng) * 22.0,
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
                .x = (rand01(&rng) - 0.5) * 50.0,
                .y = rand01(&rng) * SURFACE_Y,
                .z = 1.5 + rand01(&rng) * 40.0,
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

    /// How "reef" (vs channel sand) a point is, 0..1.
    fn reefMask(wx: f32, wz: f32) f32 {
        const dx = @abs(wrapD(wx - channelX(wz)));
        return smoothstep(1.2, 5.0, dx);
    }

    fn bakeReef(self: *State, rng: *u64) void {
        const sand = [3]f32{ 236, 208, 150 };
        const coralline = [3]f32{ 206, 116, 136 };
        const algae = [3]f32{ 120, 150, 84 };
        const rock = [3]f32{ 166, 136, 124 };

        // Pass 1: base heights and albedo. Colour is stored unlit for now.
        for (0..MAP_N) |tv| {
            const wz = (@as(f32, @floatFromInt(tv)) + 0.5) / TEX;
            for (0..MAP_N) |tu| {
                const wx = (@as(f32, @floatFromInt(tu)) + 0.5) / TEX;
                const env = reefMask(wx, wz);
                // Gemini's canyon ridge harmonics, snapped to multiples of K so the tile wraps.
                const h1 = @sin(3.0 * K * wx + 2.0 * K * wz) * @cos(2.0 * K * wx - 3.0 * K * wz);
                const h2 = 0.52 * @sin(6.0 * K * wx - 5.0 * K * wz + 1.4 * h1);
                const h3 = 0.25 * @cos(13.0 * K * wx + 10.0 * K * wz);
                const n1 = valueNoise(wx, wz, 64, 1);
                const n2 = valueNoise(wx, wz, 256, 2);
                const reef = @max(0.0, 0.7 + h1 + h2 + h3) * 1.3 + 0.9 * n1 + 0.25 * n2;
                const ripple = 0.035 * @sin(122.0 * K * wx + 40.0 * K * wz + 2.0 * @sin(9.0 * K * wz));
                const hgt = env * reef + ripple * (1.0 - env);

                const n3 = 0.6 * valueNoise(wx, wz, 192, 3) + 0.4 * valueNoise(wx, wz, 512, 6);
                const n4 = valueNoise(wx, wz, 256, 4);
                var rc = mix3(rock, coralline, 0.75 * smoothstep(0.4, 0.7, n3));
                rc = mix3(rc, algae, 0.6 * smoothstep(0.68, 0.9, n4));
                const speck = 0.86 + 0.26 * valueNoise(wx, wz, 512, 5);
                rc = .{ rc[0] * speck, rc[1] * speck, rc[2] * speck };
                const sc = mix3(sand, .{ 214, 184, 128 }, 0.5 + 0.5 * @sin(122.0 * K * wx + 40.0 * K * wz + 2.0 * @sin(9.0 * K * wz)));
                const c = mix3(sc, rc, smoothstep(0.15, 0.6, env * @min(1.0, reef)));
                const i = tv * MAP_N + tu;
                self.height[i] = hgt;
                self.color[i] = pack3(c);
            }
        }

        // Pass 2: brain corals (grooved domes) and barrel sponges, stamped onto the reef.
        var placed: usize = 0;
        var tries: usize = 0;
        while (placed < 1100 and tries < 20000) : (tries += 1) {
            const cx = rand01(rng) * TILE;
            const cz = rand01(rng) * TILE;
            if (reefMask(cx, cz) < 0.6) continue;
            placed += 1;
            const r = 0.3 + 0.7 * rand01(rng);
            const col = BRAIN_COLS[@as(usize, @intFromFloat(rand01(rng) * 4.99))];
            const hc = r * (0.45 + 0.25 * rand01(rng));
            const base = self.heightAt(cx, cz);
            const q = 6.5 + 2.0 * rand01(rng);
            const ph = rand01(rng) * TWO_PI;
            self.stamp(cx, cz, r, struct {
                fn f(lx: f32, lz: f32, d2: f32, ctx: anytype) ?struct { h: f32, c: [3]f32 } {
                    const dome = ctx.hc * @sqrt(1.0 - d2);
                    const g = @sin(ctx.q * (lx + 0.45 * @sin(2.1 * lz + ctx.ph)) + 1.6 * @sin(ctx.q * 0.55 * lz));
                    const groove = smoothstep(0.55, 0.85, g);
                    const shade = 1.0 - 0.45 * groove;
                    return .{ .h = ctx.base + dome - 0.05 * groove, .c = .{ ctx.col[0] * shade, ctx.col[1] * shade, ctx.col[2] * shade } };
                }
            }.f, .{ .hc = hc, .q = q, .ph = ph, .base = base, .col = col });
        }

        placed = 0;
        tries = 0;
        while (placed < 220 and tries < 20000) : (tries += 1) {
            const cx = rand01(rng) * TILE;
            const cz = rand01(rng) * TILE;
            if (reefMask(cx, cz) < 0.6) continue;
            placed += 1;
            const col = SPONGE_COLS[@as(usize, @intFromFloat(rand01(rng) * 3.99))];
            const n_tubes: usize = 1 + @as(usize, @intFromFloat(rand01(rng) * 3.0));
            for (0..n_tubes) |_| {
                const tx = cx + (rand01(rng) - 0.5) * 1.2;
                const tz = cz + (rand01(rng) - 0.5) * 1.2;
                const r = 0.28 + 0.22 * rand01(rng);
                const tall = 0.7 + 1.4 * rand01(rng);
                const base = self.heightAt(tx, tz);
                self.stamp(tx, tz, r, struct {
                    fn f(lx: f32, lz: f32, d2: f32, ctx: anytype) ?struct { h: f32, c: [3]f32 } {
                        _ = lx;
                        _ = lz;
                        if (d2 < 0.36) {
                            // The open top: a dark well.
                            return .{ .h = ctx.base + ctx.tall * 0.55, .c = .{ ctx.col[0] * 0.3, ctx.col[1] * 0.3, ctx.col[2] * 0.3 } };
                        }
                        const lip = 1.0 + 0.15 * smoothstep(0.36, 0.6, d2);
                        return .{ .h = ctx.base + ctx.tall, .c = .{ ctx.col[0] * lip, ctx.col[1] * lip, ctx.col[2] * lip } };
                    }
                }.f, .{ .base = base, .tall = tall, .col = col });
            }
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

        // Rubble and coral fragments scattered over the sand channel.
        placed = 0;
        tries = 0;
        while (placed < 240 and tries < 20000) : (tries += 1) {
            const cx = rand01(rng) * TILE;
            const cz = rand01(rng) * TILE;
            if (reefMask(cx, cz) > 0.5) continue;
            placed += 1;
            const r = 0.12 + 0.25 * rand01(rng);
            const shade = 0.75 + 0.3 * rand01(rng);
            const pick = BRAIN_COLS[@as(usize, @intFromFloat(rand01(rng) * 4.99))];
            const col = [3]f32{ pick[0] * shade, pick[1] * shade, pick[2] * shade };
            const base = self.heightAt(cx, cz);
            const tall = r * (0.25 + 0.25 * rand01(rng));
            self.stamp(cx, cz, r, struct {
                fn f(lx: f32, lz: f32, d2: f32, ctx: anytype) ?struct { h: f32, c: [3]f32 } {
                    _ = lx;
                    _ = lz;
                    return .{ .h = ctx.base + ctx.tall * @sqrt(1.0 - d2), .c = ctx.col };
                }
            }.f, .{ .base = base, .tall = tall, .col = col });
        }

        // Pass 3: light it. Lambert from above, cavities darker, reds absorbed with depth.
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
                const around = 0.25 * (self.height[texIdx(iu + 4, iv)] + self.height[texIdx(iu - 4, iv)] +
                    self.height[texIdx(iu, iv + 4)] + self.height[texIdx(iu, iv - 4)]);
                const cavity = math.clamp(1.0 + 0.9 * (hc - around), 0.55, 1.15);
                const lit = (0.40 + 0.85 * lam) * cavity * (0.92 + 0.05 * hc);
                const c = self.color[tv * MAP_N + tu];
                const r = @as(f32, @floatFromInt(c & 0xFF)) * lit * 0.86;
                const g = @as(f32, @floatFromInt((c >> 8) & 0xFF)) * lit;
                const b = @as(f32, @floatFromInt((c >> 16) & 0xFF)) * lit * 1.04;
                self.color[tv * MAP_N + tu] = sdk.packRGBA(toU8(r), toU8(g), toU8(b));
            }
        }
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

    fn buildCorals(self: *State, rng: *u64) void {
        var n: usize = 0;
        var tries: usize = 0;
        while (n < NUM_CORAL and tries < 20000) : (tries += 1) {
            const x = rand01(rng) * TILE;
            const z = rand01(rng) * TILE;
            const m = reefMask(x, z);
            const kind: u8 = if (n < NUM_STAG) 1 else if (n < NUM_STAG + NUM_FAN) 2 else 3;
            // Anemones like the reef's sandy edge, the rest want solid reef.
            if (kind == 3 and m > 0.85) continue;
            if (kind != 3 and m < 0.65) continue;
            var c = Coral{
                .x = x,
                .z = z,
                .y = self.heightAt(x, z) - 0.05,
                .kind = kind,
                .style = 0,
                .seg_start = @intCast(self.n_segs),
                .seg_count = 0,
                .angle = rand01(rng) * math.pi,
                .size = 1.0 + 0.9 * rand01(rng),
                .phase = rand01(rng) * TWO_PI,
            };
            switch (kind) {
                1 => {
                    c.style = @intFromFloat(rand01(rng) * 3.99);
                    self.growStaghorn(rng, c.size);
                },
                2 => {
                    c.style = @intFromFloat(rand01(rng) * 2.99);
                    self.growFan(rng, c.size, c.angle);
                },
                else => {
                    c.style = @intFromFloat(rand01(rng) * 2.99);
                    c.size = 0.5 + 0.4 * rand01(rng);
                },
            }
            c.seg_count = @intCast(self.n_segs - c.seg_start);
            self.corals[n] = c;
            n += 1;
        }
        // Should never trigger, but keep the array fully initialised.
        while (n < NUM_CORAL) : (n += 1) {
            self.corals[n] = .{ .x = 0, .z = 0, .y = -100, .kind = 3, .style = 0, .seg_start = 0, .seg_count = 0, .angle = 0, .size = 0, .phase = 0 };
        }
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

    fn growFan(self: *State, rng: *u64, size: f32, angle: f32) void {
        const limit = self.n_segs + FAN_SEGS;
        const ca = @cos(angle);
        const sa = @sin(angle);
        // Grown in the (u, v) plane, then turned to face `angle`.
        const B2 = struct { u: f32, v: f32, du: f32, dv: f32, len: f32, depth: u8 };
        var stack: [96]B2 = undefined;
        var sp: usize = 1;
        stack[0] = .{ .u = 0, .v = 0, .du = 0, .dv = 1, .len = 0.32 * size, .depth = 0 };
        while (sp > 0 and self.n_segs < limit) {
            sp -= 1;
            const b = stack[sp];
            const eu = b.u + b.du * b.len;
            const ev = b.v + b.dv * b.len;
            const thick = 0.05 * size * (1.0 - 0.13 * @as(f32, @floatFromInt(b.depth)));
            self.addSeg(.{ b.u * ca, b.v, b.u * sa }, .{ eu * ca, ev, eu * sa }, @max(0.012, thick), @as(f32, @floatFromInt(b.depth)) / 6.0);
            if (b.depth >= 6) continue;
            const kids: usize = if (b.depth < 2 or rand01(rng) < 0.8) 2 else 1;
            for (0..kids) |k| {
                if (sp >= stack.len) break;
                const side: f32 = if (k == 0) -1.0 else 1.0;
                const turn = side * (0.28 + 0.25 * rand01(rng)) * @as(f32, if (kids == 1) 0.3 else 1.0);
                const cs = @cos(turn);
                const sn = @sin(turn);
                var du = b.du * cs - b.dv * sn;
                var dv = b.du * sn + b.dv * cs;
                // Keep the fan growing up and out, not down.
                dv = @max(dv, 0.25);
                const l = @sqrt(du * du + dv * dv);
                du /= l;
                dv /= l;
                stack[sp] = .{ .u = eu, .v = ev, .du = du, .dv = dv, .len = b.len * (0.8 + 0.1 * rand01(rng)), .depth = b.depth + 1 };
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
        self.cam_x = channelX(self.scroll_z + 5.0);
        self.cam_y = CAM_Y + 0.3 * self.fastSin(self.phase(0.19));

        self.stepRays();
        self.stepFish(dt_f);
        self.stepParticles(dt_f);
        self.buildItems();
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
            0 => 2.6,
            1 => 5.8,
            else => 9.0,
        };
    }

    fn stepFish(self: *State, dt_f: f32) void {
        for (0..NUM_FISH) |i| {
            var f = self.fish[i];
            const info = SPECIES_INFO[f.kind];
            const kf: f32 = @floatFromInt(f.kind);

            // Schools chase one slowly wandering point per species; loners each get their own.
            const key: f32 = if (info.school) kf * 1.7 else kf * 1.7 + f.seed * 37.0;
            const slow: f64 = if (info.school) 1.0 else 0.55 + 0.6 * @as(f64, f.seed);
            const lane = @mod(key * 0.618, 1.0);
            const tz = 8.0 + 26.0 * lane + 4.0 * self.fastSin(self.phase(0.053 * slow) + key * 1.3);
            const tx = 0.55 * tz * self.fastSin(self.phase(0.071 * slow) + key * 1.9) + 3.0 * self.fastSin(self.phase(0.19 * slow) + key * 0.7);
            var ty = habitatY(info.habitat) + 1.4 * self.fastSin(self.phase(0.11 * slow) + key * 2.3);
            if (info.habitat == 0) {
                // Reef dwellers follow the reef: stay a little above whatever is below.
                ty = @max(ty, self.heightAt(f.x + self.cam_x, self.scroll_z + f.z) + 0.6 + 0.8 * f.seed);
            }

            if (info.school and info.count > 1) {
                var sep = [3]f32{ 0, 0, 0 };
                var ali = [3]f32{ 0, 0, 0 };
                var coh = [3]f32{ 0, 0, 0 };
                var n: f32 = 0;
                const sep_r2 = 2.2 * f.size * f.size;
                const local = i - info.start;
                const neighbours = @min(info.count - 1, 17);
                for (1..neighbours + 1) |k| {
                    const j = info.start + (local + k) % info.count;
                    const o = self.fish[j];
                    const dx = o.x - f.x;
                    const dy = o.y - f.y;
                    const dz = o.z - f.z;
                    const d2 = dx * dx + dy * dy + dz * dz;
                    if (d2 > 1e-4 and d2 < 16.0) {
                        if (d2 < sep_r2) {
                            const inv = 1.0 / d2;
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
                    f.vx += ((ali[0] * inv_n - f.vx) * 1.2 + (coh[0] * inv_n - f.x) * 0.5 + sep[0] * 1.6) * dt_f;
                    f.vy += ((ali[1] * inv_n - f.vy) * 1.2 + (coh[1] * inv_n - f.y) * 0.5 + sep[1] * 1.6) * dt_f;
                    f.vz += ((ali[2] * inv_n - f.vz) * 1.0 + (coh[2] * inv_n - f.z) * 0.3 + sep[2] * 1.2) * dt_f;
                }
            }
            f.vx += math.clamp(tx - f.x, -6.0, 6.0) * 0.30 * dt_f;
            f.vy += math.clamp(ty - f.y, -4.0, 4.0) * 0.35 * dt_f;
            f.vz += math.clamp(tz - f.z, -8.0, 8.0) * 0.12 * dt_f;
            f.vy *= 1.0 - 0.6 * dt_f;
            f.vz *= 1.0 - 0.5 * dt_f;

            const ground = self.heightAt(f.x + self.cam_x, self.scroll_z + f.z) + 0.25 + 0.5 * f.size * info.half_depth * 2.0;
            if (f.y < ground) f.vy += (ground - f.y) * 6.0 * dt_f;
            if (f.y > 11.0) f.vy -= (f.y - 11.0) * 3.0 * dt_f;

            const sp = @sqrt(f.vx * f.vx + f.vy * f.vy + f.vz * f.vz);
            const lo = 0.9 * info.speed;
            const hi = 2.6 * info.speed;
            const cs = math.clamp(sp, lo, hi);
            if (sp > 1e-4) {
                f.vx = f.vx / sp * cs;
                f.vy = f.vy / sp * cs;
                f.vz = f.vz / sp * cs;
            } else {
                f.vx = lo;
            }
            // Keep some forward way on, so nobody hangs head-up in the water.
            if (!info.upright) {
                const hs = @sqrt(f.vx * f.vx + f.vz * f.vz);
                if (hs < 0.6 * lo) {
                    if (hs > 1e-4) {
                        f.vx *= 0.6 * lo / hs;
                        f.vz *= 0.6 * lo / hs;
                    } else {
                        f.vx = 0.6 * lo;
                    }
                }
            }

            f.x = math.clamp(f.x + f.vx * dt_f, -40.0, 40.0);
            f.y = math.clamp(f.y + f.vy * dt_f, -2.0, SURFACE_Y);
            f.z = math.clamp(f.z + (f.vz - CAM_SPEED) * dt_f, 3.0, 45.0);
            f.wag = @mod(f.wag + dt_f * (5.0 + 3.0 * cs / f.size), TWO_PI);
            self.fish[i] = f;
        }
    }

    fn stepParticles(self: *State, dt_f: f32) void {
        for (&self.snow) |*m| {
            m.z -= CAM_SPEED * dt_f;
            m.y -= 0.08 * dt_f;
            m.x += 0.12 * self.fastSin(self.phase(0.3) + m.phase) * dt_f;
            if (m.z < 1.5) m.z += 40.0;
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
            self.items[n] = .{ .rz = self.fish[i].z, .rx = self.fish[i].x, .idx = @intCast(i), .kind = 0 };
            n += 1;
        }
        const half_w = 0.5 * @as(f32, @floatFromInt(self.w));
        for (0..NUM_CORAL) |i| {
            const c = self.corals[i];
            const rz = @mod(c.z - self.scroll_z, TILE);
            if (rz < Z_NEAR + 0.3 or rz > Z_FAR) continue;
            const rx = wrapD(c.x - self.cam_x);
            if (@abs(rx) > rz * half_w / self.focal_px + 2.5) continue;
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
            var x: usize = 0;
            while (x + 8 <= w) : (x += 8) {
                var p: V = row[x..][0..8].*;
                const rv: V = @as(@Vector(8, u8), rays[x..][0..8].*);
                const empty = (p >> @as(V, @splat(24))) == zero;
                const g = @select(u32, empty, gain_v, half_v);
                p = @select(u32, empty, base_v, p);
                const a = (rv * g) >> @as(V, @splat(8));
                const r: V = @min(c255, (p & m8) + ((a * @as(V, @splat(110))) >> @as(V, @splat(8))));
                const gg: V = @min(c255, ((p >> @as(V, @splat(8))) & m8) + ((a * @as(V, @splat(190))) >> @as(V, @splat(8))));
                const bb: V = @min(c255, ((p >> @as(V, @splat(16))) & m8) + ((a * @as(V, @splat(200))) >> @as(V, @splat(8))));
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
                const r: u32 = @min(255, (p & 0xFF) + ((a * 110) >> 8));
                const g: u32 = @min(255, ((p >> 8) & 0xFF) + ((a * 190) >> 8));
                const b: u32 = @min(255, ((p >> 16) & 0xFF) + ((a * 200) >> 8));
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
            const lum: u8 = toU8(60.0 * @exp(-0.05 * m.z) + 6.0);
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
        if (c.kind == 3) {
            self.drawAnemone(buf, stride, wi, hi, c, it.rx, ry, it.rz);
            return;
        }
        const base = if (c.kind == 1) STAG_BASE[c.style] else FAN_BASE[c.style];
        const tip = if (c.kind == 1) STAG_TIP[c.style] else FAN_TIP[c.style];
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
        // Back tentacles first is irrelevant here: writes are first-come, so draw the front half first.
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

const YellowTang = struct {
    pub const name = "Yellow tang";
    pub const author = "Claude Opus, from Gemini_Aquarium";
    pub const length: f32 = 0.70;
    pub const half_depth: f32 = 0.30;
    pub const extent: f32 = 1.3;
    pub const upright = false;
    pub const speed: f32 = 0.85;
    pub const count: u8 = 16;
    pub const school = true;
    pub const habitat: u8 = 1;
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        const hit = classicBody(u, s, t) orelse return null;
        var c = State.mix3(.{ 245, 196, 30 }, .{ 255, 232, 96 }, hit.k);
        if (u > 0.70 and u < 0.76) c = .{ 255, 250, 235 };
        return classicFinish(c, hit, u, 0);
    }
};

const Clownfish = struct {
    pub const name = "Clownfish";
    pub const author = "Claude Opus, from Gemini_Aquarium";
    pub const length: f32 = 0.50;
    pub const half_depth: f32 = 0.21;
    pub const extent: f32 = 1.3;
    pub const upright = false;
    pub const speed: f32 = 0.95;
    pub const count: u8 = 24;
    pub const school = true;
    pub const habitat: u8 = 0;
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        const hit = classicBody(u, s, t) orelse return null;
        var c = State.mix3(.{ 236, 98, 16 }, .{ 255, 150, 52 }, hit.k);
        if ((u > 0.22 and u < 0.30) or (u > 0.50 and u < 0.57)) {
            c = .{ 248, 246, 240 };
        } else if ((u > 0.205 and u < 0.315) or (u > 0.485 and u < 0.585) or (hit.tail and u > 0.94)) {
            c = .{ 30, 18, 12 };
        }
        return classicFinish(c, hit, u, 0);
    }
};

const SilverFish = struct {
    pub const name = "Silver fish";
    pub const author = "Claude Opus, from Gemini_Aquarium";
    pub const length: f32 = 1.10;
    pub const half_depth: f32 = 0.15;
    pub const extent: f32 = 1.3;
    pub const upright = false;
    pub const speed: f32 = 0.70;
    pub const count: u8 = 16;
    pub const school = true;
    pub const habitat: u8 = 1;
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        const hit = classicBody(u, s, t) orelse return null;
        var c = State.mix3(.{ 70, 96, 122 }, .{ 214, 224, 230 }, hit.k);
        if (!hit.tail and @abs(2.0 * hit.k - 1.0) < 0.07) c = .{ 235, 242, 248 };
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
    pub const length: f32 = 2.2;
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
    pub const speed: f32 = 1.4;
    /// How many live in the reef (1..24).
    pub const count: u8 = 3;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = false;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 1;

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

const MorayEel = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Moray eel";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip. For scale: a neon tetra
    /// is 0.34, a clownfish 0.5, a yellow tang 0.7, the big silver fish 1.1.
    pub const length: f32 = 1.8;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.055;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 4.0;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves (seahorse, jellyfish). false points the head where
    /// it swims and keeps the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed relative to a clownfish (1.0). Sharks ~1.4, lionfish ~0.4.
    pub const speed: f32 = 0.5;
    /// How many live in the reef (1..24).
    pub const count: u8 = 4;
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
    /// loops over more than ~8 items, no allocation, no panics (clamp before any
    /// @intFromFloat), no globals with state.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        // Travelling wave over the whole length: about 2.5 waves, growing
        // toward the tail. Positive t moves the wave toward the tail.
        const amp = 0.35 + 0.6 * u;
        const sb = s - amp * @sin(15.7 * u - t);
        const a = @abs(sb);

        // Body: blunt rounded head, thickest a third of the way along, then
        // tapering to a point at the tail tip.
        var hw: f32 = 0.0;
        if (u >= 0.0 and u <= 1.0) {
            if (u < 0.35) {
                const nose = math.clamp(u / 0.12, 0.0, 1.0);
                hw = (0.6 + 0.4 * @sin(0.5 * math.pi * math.clamp(u / 0.35, 0.0, 1.0))) * (0.45 + 0.55 * @sqrt(nose));
            } else {
                hw = 1.0 - 0.92 * math.pow(f32, (u - 0.35) / 0.65, 1.2);
            }
        }
        if (hw <= 0.0) return null;

        // Low continuous dorsal fin on the back, from behind the head into the tail.
        var fin: f32 = 0.0;
        if (u >= 0.05) {
            const ramp = math.clamp((u - 0.05) / 0.1, 0.0, 1.0);
            const fp = math.clamp((u - 0.05) / 0.95, 0.0, 1.0);
            fin = ramp * 0.34 * (1.0 - 0.85 * fp);
        }
        const reach = if (sb < 0.0) hw + fin else hw;
        if (a > reach) return null;

        const in_fin = sb < 0.0 and a > hw;
        const spotted = seed >= 0.5;
        const k = 0.5 + 0.5 * math.clamp(sb / @max(hw, 0.05), -1.0, 1.0); // 0 back .. 1 belly

        var c: [3]f32 = undefined;
        if (spotted) {
            // Dark brown body with pale yellow leopard spots on a staggered grid.
            c = if (in_fin) .{ 84, 60, 36 } else .{ 62 + 36 * k, 42 + 28 * k, 26 + 16 * k };
            const row = @floor(sb * 1.54 + 0.5);
            const off: f32 = if (@mod(row, 2.0) > 0.5) 0.5 else 0.0;
            const gu = @mod(u * 28.0 + off, 1.0) - 0.5;
            const gs = @mod(sb * 1.54 + 0.5, 1.0) - 0.5;
            if (gu * gu + gs * gs < 0.1) c = .{ 236, 214, 120 };
        } else {
            // Green moray: olive-green back, yellow-green belly, yellow mottling.
            c = if (in_fin) .{ 150, 162, 62 } else .{ 58 + 30 * k, 96 + 34 * k, 40 + 22 * k };
            const net = @sin(u * 70.0 + 2.0 * @sin(sb * 4.0)) * @sin(sb * 5.0 - u * 40.0);
            if (net > 0.55) c = .{ 200, 196, 80 };
        }

        // Open mouth at the blunt nose: pale inside, opening on the belly side.
        if (u < 0.13 and sb > 0.03 and sb < 0.03 + 0.36 * (1.0 - u / 0.13)) {
            return [3]f32{ 240, 232, 196 };
        }
        // Small eye near the top of the head: gold iris, dark pupil.
        const eu = (u - 0.12) / 0.018;
        const ev = (sb + 0.35) / 0.33;
        const ed = eu * eu + ev * ev;
        if (ed < 1.0) {
            return if (ed < 0.35) [3]f32{ 12, 12, 10 } else [3]f32{ 220, 190, 60 };
        }
        // Dark outline band near the edge.
        if (reach - a < 0.08) c = .{ c[0] * 0.65, c[1] * 0.65, c[2] * 0.65 };
        return c;
    }
};

const Lionfish = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Red lionfish";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip. For scale: a neon tetra
    /// is 0.34, a clownfish 0.5, a yellow tang 0.7, the big silver fish 1.1.
    pub const length: f32 = 0.6;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.19;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 2.4;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves (seahorse, jellyfish). false points the head where
    /// it swims and keeps the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed relative to a clownfish (1.0). Sharks ~1.4, lionfish ~0.4.
    pub const speed: f32 = 0.35;
    /// How many live in the reef (1..24).
    pub const count: u8 = 5;
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
    /// loops over more than ~8 items, no allocation, no panics (clamp before any
    /// @intFromFloat), no globals with state.
    pub fn shade(u: f32, s: f32, t: f32, seed: f32) ?[3]f32 {
        _ = seed;
        // Slow hover: the body barely bends.
        const st = @sin(t);
        const sb = s - 0.12 * st * u * u;
        const a = @abs(sb);
        // Big blunt head, deepest near the eye, narrowing to the stern.
        const p = math.clamp(u / 0.78, 0.0, 1.0);
        const hw_body: f32 = if (u <= 0.78) 0.3 + 0.7 * @sin(math.pi * @sqrt(p)) else 0.0;
        // Rounded fan tail at the back.
        const tq = (u - 0.86) / 0.14;
        const hw_tail: f32 = 0.85 * @sqrt(@max(0.0, 1.0 - tq * tq));
        const hw = @max(hw_body, hw_tail);
        const tail = u > 0.7 and hw_tail > hw_body;

        if (a <= hw) {
            // Downturned mouth: the lower front of the head is cut away.
            if (u < 0.08 and sb > 0.1 + 2.0 * u) return null;
            const k = 0.5 + 0.5 * math.clamp(sb / @max(hw, 0.05), -1.0, 1.0); // 0 back .. 1 belly
            var c = [3]f32{ 112 + 74 * k, 36 + 48 * k, 28 + 34 * k };
            if (tail) {
                c = .{ 196, 64, 46 };
                if (@sin(u * 24.0) * @sin(sb * 20.0) > 0.55) c = .{ 70, 22, 20 }; // spots
                if (@mod(sb * 2.5, 1.0) < 0.2) c = .{ 232, 214, 196 }; // rays
            } else if (u > 0.1 and @mod((u - 0.1) * 5.5, 1.0) < 0.35) {
                c = .{ 242, 232, 214 }; // cream bars
            }
            if (hw - a < 0.07) c = .{ c[0] * 0.7, c[1] * 0.7, c[2] * 0.7 }; // outline
            // Eye: gold ring, dark pupil.
            const eu = (u - 0.15) / 0.065;
            const ev = (sb + 0.2) / 0.13;
            const er = eu * eu + ev * ev;
            if (er < 1.0) c = if (er < 0.3) [3]f32{ 14, 10, 12 } else [3]f32{ 240, 186, 70 };
            return c;
        }
        if (sb > 0.0) {
            // Pectoral fan: striped rays with gaps, opening and closing slowly.
            const x = u - 0.22;
            const y = (sb - 0.1) * 0.19;
            const r2 = x * x + y * y;
            if (r2 > 0.2) return null; // beyond the fan
            const r = @sqrt(r2);
            const ang = math.atan2(y, x);
            const hwid: f32 = 0.62 + 0.12 * st;
            const da = ang - 0.85;
            if (@abs(da) >= hwid) return null;
            const frac = (da + hwid) / (2.0 * hwid);
            const ray = frac * 10.0;
            const ri = @min(@floor(ray), 9.0);
            const fr = ray - ri;
            if (fr > 0.7) return null; // gap between rays
            const rf: f32 = 0.4 + 0.02 * st;
            if (r > rf * (0.9 + 0.1 * fr)) return null; // scalloped edge
            const idx: u32 = @intFromFloat(ri);
            if (idx % 2 == 0) return [3]f32{ 206, 70, 52 };
            return [3]f32{ 242, 224, 204 };
        }
        // Back side, outside the body: fleshy tentacles and dorsal spines.
        const above = -sb - hw; // height above the back edge, in W units
        if (above > 1.3) return null;
        if (above < 0.45) {
            const tc = @min(@abs(u - 0.12), @abs(u - 0.19));
            if (u > 0.08 and u < 0.23 and tc < 0.02 * (1.0 - above / 0.45)) return [3]f32{ 232, 150, 120 };
        }
        if (u > 0.2 and u < 0.72) {
            // Separate spikes, one per cell along the back, with transparent gaps.
            const env = @sin(math.pi * (u - 0.2) / 0.52);
            const lm: f32 = 1.25 * env;
            if (env > 0.05 and above < lm) {
                const cell = (u - 0.2) / 0.04;
                const f = cell - @floor(cell) - 0.5;
                const wsp: f32 = 0.008 * (1.0 - above / lm) + 0.0015;
                if (@abs(f * 0.04) < wsp) {
                    if (@mod(above * 2.6, 1.0) < 0.5) return [3]f32{ 242, 226, 206 };
                    return [3]f32{ 170, 44, 34 };
                }
            }
        }
        return null;
    }
};

const MantaRay = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Manta ray";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip. For scale: a neon tetra
    /// is 0.34, a clownfish 0.5, a yellow tang 0.7, the big silver fish 1.1.
    pub const length: f32 = 1.8;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.15;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 3.0;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves (seahorse, jellyfish). false points the head where
    /// it swims and keeps the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed relative to a clownfish (1.0). Sharks ~1.4, lionfish ~0.4.
    pub const speed: f32 = 0.8;
    /// How many live in the reef (1..24).
    pub const count: u8 = 2;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = false;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 2;

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
        // Top view. The wings flap slowly: sin(t) swells the span and lifts or
        // drops the tips. Everything uses |s|, so the animal is mirror-symmetric.
        const flap = @sin(t);
        const a = @abs(s);
        // Tail: a thin whip from the tail root (u = 0.5) to the tip (u = 1).
        if (u > 0.5) {
            if (u > 1.0) return null;
            const x = math.clamp((u - 0.5) / 0.5, 0.0, 1.0);
            const tw = 0.10 * (1.0 - x) + 0.03;
            if (a > tw) return null;
            return .{ 24, 24, 30 };
        }
        // Cephalic fins: short paddles at the front corners of the head.
        if (u < 0.0) {
            const fu = (u - 0.02) / 0.06;
            const fa = (a - 1.15) / 0.35;
            if (fu * fu + fa * fa > 1.0) return null;
            return .{ 30, 32, 38 };
        }
        // Wing outline. The tips lift (flap > 0) or fall (flap < 0): the outer
        // trailing edge shifts back or forward.
        const ramp = math.clamp((a - 1.5) / 1.3, 0.0, 1.0);
        const ua = u - 0.06 * flap * ramp * ramp;
        var h: f32 = undefined;
        if (ua < 0.32) {
            const x = math.clamp(ua / 0.32, 0.0, 1.0);
            h = 0.6 + 2.2 * (2.0 * x - x * x); // rounded head, widest at u = 0.32
        } else {
            const y = math.clamp((ua - 0.32) / 0.18, 0.0, 1.0);
            h = 2.8 - 2.7 * math.pow(f32, y, 0.8); // pointed tips, sweep to the root
        }
        // Wingspan swells with the flap, most at the tips.
        const span = math.clamp(h / 2.8, 0.0, 1.0);
        h *= 1.0 + 0.05 * flap * span * span;
        if (a > h) return null;
        const rim = h - a;
        // Charcoal back, a touch lighter toward the tips.
        const lift = 8.0 * span * span;
        var c = [3]f32{ 34 + lift, 36 + lift, 42 + lift };
        // Pale grey-white shoulder chevron near the head.
        const ac = 0.30 + 6.0 * (u - 0.06);
        if (u > 0.06 and u < 0.26 and @abs(a - ac) < 0.10) c = .{ 200, 204, 208 };
        // Subtle lighter edge, then a dark outline band right at the rim.
        if (rim < 0.10) c = .{ 74, 78, 86 };
        if (rim < 0.05) c = .{ 14, 14, 18 };
        return c;
    }
};

const Parrotfish = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Stoplight Parrotfish";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip.
    pub const length: f32 = 0.8;
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

const Seahorse = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Seahorse (Hippocampus kuda)";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip.
    pub const length: f32 = 0.4;
    /// Half the body depth as a fraction of length; W = length * half_depth.
    pub const half_depth: f32 = 0.22;
    /// The largest |s| the shape reaches (snout, fin, lean included).
    pub const extent: f32 = 1.6;
    /// Upright: the head sits on top and the animal stands vertically.
    pub const upright: bool = true;
    /// Cruise speed relative to a clownfish (1.0).
    pub const speed: f32 = 0.15;
    /// How many live in the reef (1..24).
    pub const count: u8 = 6;
    /// Seahorses drift alone.
    pub const school: bool = false;
    /// Hugs the reef and sand.
    pub const habitat: u8 = 0;

    const Trunk = struct { c: f32, l: f32, r: f32 };
    const phmax: f32 = 10.05; // tail curl: 1.6 turns
    const g: f32 = 0.37 / phmax; // tail curl: radius lost per radian

    /// Trunk profile at height y: c shifts its centre, l is the half-width on
    /// the belly side (s > 0, screen-left) and r on the back side (s < 0).
    fn trunk(y: f32) Trunk {
        const bulge = @sin(math.pi * math.clamp((y - 1.5) / 1.8, 0.0, 1.0));
        const taper = math.clamp((y - 2.6) / 1.0, 0.0, 1.0);
        return .{
            .c = 0.12 * bulge,
            .l = 0.15 + 0.62 * bulge - 0.09 * taper,
            .r = 0.14 + 0.30 * bulge - 0.07 * taper,
        };
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
        const st = @sin(t);
        // y is the height in s units, so one unit is the same size across and
        // along the body. The whole animal bobs a little and leans with sin(t).
        const y = u / half_depth - 0.04 * st;
        const sb = s - 0.07 * st * (y - 2.3);

        // Eye: dark pupil with a pale ring.
        const ed = (sb - 0.24) * (sb - 0.24) + (y - 0.62) * (y - 0.62);
        if (ed < 0.1 * 0.1) return [3]f32{ 14, 12, 12 };
        if (ed < 0.15 * 0.15) return [3]f32{ 252, 248, 230 };

        // Head: a rounded skull with a two-knob coronet on top.
        const hq = (sb - 0.05) / 0.5;
        const hr = (y - 0.68) / 0.5;
        const hq2 = hq * hq + hr * hr;
        const c1 = sb * sb + (y - 0.2) * (y - 0.2) < 0.13 * 0.13;
        const c2x = sb + 0.18;
        const c2 = c2x * c2x + (y - 0.34) * (y - 0.34) < 0.09 * 0.09;
        const crown = c1 or c2;

        // Snout: a tapering tube reaching out to the screen-left.
        const vx: f32 = 0.95;
        const vy: f32 = 0.18;
        const hh = math.clamp(((sb - 0.35) * vx + (y - 0.80) * vy) / (vx * vx + vy * vy), 0.0, 1.0);
        const px = sb - 0.35 - hh * vx;
        const py = y - 0.80 - hh * vy;
        const snout_r = 0.24 - 0.12 * hh;
        const snout_d = @sqrt(px * px + py * py);
        const in_snout = snout_d < snout_r;

        // Trunk: neck, belly bulge and the tapering lower body with rings.
        const tr = trunk(y);
        const in_trunk = y > 1.0 and y < 3.72 and sb <= tr.c + tr.l and sb >= tr.c - tr.r;

        // Tail curl: an inward Archimedean spiral at the bottom.
        var curl = false;
        var curl_edge: f32 = 9.0;
        if (y > 3.6) {
            const dx = sb - 0.06;
            const dy = y - 4.12;
            const rr = @sqrt(dx * dx + dy * dy);
            var phi = math.atan2(dy, dx) + 0.5 * math.pi; // 0 at the top of the curl
            if (phi < 0.0) phi += 2.0 * math.pi;
            for (0..3) |i| {
                const ph = phi + 2.0 * math.pi * @as(f32, @floatFromInt(i));
                if (ph > phmax) break;
                const rn = 0.42 - g * ph;
                const wv = 0.11 - 0.07 * ph / phmax;
                const ratio = @abs(rr - rn) / wv;
                if (ratio < 1.0) {
                    curl = true;
                    curl_edge = @min(curl_edge, (1.0 - ratio) * wv);
                }
            }
        }

        const in_body = hq2 < 1.0 or crown or in_snout or in_trunk or curl;
        if (in_body) {
            // Yellow belly (s > 0) fading to orange back (s < 0).
            const wdt = if (sb >= tr.c) tr.l else tr.r;
            const k: f32 = 0.5 + 0.5 * math.clamp((sb - tr.c) / @max(wdt, 0.05), -1.0, 1.0);
            var c = [3]f32{ 214 + 38 * k, 98 + 102 * k, 22 + 52 * k };
            // Segment rings across the trunk.
            if (in_trunk and y > 1.6 and y < 3.5 and @mod(y - 1.6, 0.34) < 0.045) {
                c = .{ c[0] * 0.7, c[1] * 0.6, c[2] * 0.6 };
            }
            // Dark outline band near the edge.
            var edge: f32 = 9.0;
            if (hq2 < 1.0) edge = @min(edge, (1.0 - hq2) * 0.5);
            if (in_snout and hq2 >= 1.0) edge = @min(edge, snout_r - snout_d);
            if (in_trunk and y > 1.3) edge = @min(edge, @min(tr.c + tr.l - sb, sb - (tr.c - tr.r)));
            if (curl) edge = @min(edge, curl_edge);
            if (edge < 0.06) c = .{ c[0] * 0.55, c[1] * 0.5, c[2] * 0.45 };
            return c;
        }

        // Dorsal fin on the back, a pale fan that flutters fast.
        const fy = (y - 2.25) / 0.34;
        if (fy * fy < 1.0) {
            const s3 = @sin(3.0 * t);
            const flen = 0.36 * (1.0 - fy * fy) * (0.85 + 0.25 * s3);
            const back = tr.c - tr.r;
            if (sb < back and sb > back - flen) {
                const ray = @sin(-sb * 35.0) > 0.7;
                return if (ray) [3]f32{ 236, 190, 110 } else [3]f32{ 255, 240, 186 };
            }
        }
        return null;
    }
};

const MoonJelly = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Moon jellyfish";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip. For scale: a neon tetra
    /// is 0.34, a clownfish 0.5, a yellow tang 0.7, the big silver fish 1.1.
    pub const length: f32 = 0.7;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.3;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 1.6;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves (seahorse, jellyfish). false points the head where
    /// it swims and keeps the belly (s > 0) facing down the screen.
    pub const upright: bool = true;
    /// Cruise speed relative to a clownfish (1.0). Sharks ~1.4, lionfish ~0.4.
    pub const speed: f32 = 0.2;
    /// How many live in the reef (1..24).
    pub const count: u8 = 6;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = false;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 2;

    /// Lateral positions (in s units) of the four oral arms at their root.
    const arm_s = [4]f32{ -0.30, -0.10, 0.10, 0.30 };

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
        const p = @sin(t); // +1 = bell widens and flattens, -1 = narrows and lengthens
        const a = @abs(s);
        const bell_b: f32 = 0.34 - 0.03 * p; // bell rim (its bottom edge)
        const bw: f32 = 1.0 + 0.07 * p; // bell half-width in s units

        // Oral arms: four frilly arms trailing to about u = 0.9, swaying with u.
        if (u >= 0.2 and u <= 0.9) {
            const fu = (u - 0.2) / 0.7;
            const frill = 0.7 + 0.3 * @abs(@sin(u * 32.0));
            const aw = (0.03 + 0.035 * (1.0 - fu)) * frill;
            for (arm_s, 0..) |s0, i| {
                const fi: f32 = @floatFromInt(i);
                const cs = s0 * (1.0 - 0.3 * u) + 0.14 * u * @sin(t - 5.0 * u + 0.6 * fi);
                const d = @abs(s - cs);
                if (d < aw) {
                    if (aw - d < 0.015) return .{ 244, 232, 248 }; // frilly edge
                    return .{ 214, 180, 226 };
                }
            }
        }

        // Bell: dome in u = 0..bell_b, with clover gonads and faint radial ribs.
        if (u >= 0.0 and u <= bell_b) {
            const v = u / bell_b;
            const w = 1.0 - v;
            const hw = bw * @sqrt(@max(0.0, 1.0 - w * w));
            if (a <= hw) {
                // Physical coordinates in length units (x = s * half_depth).
                const dx = s * 0.3;
                const dy = u - 0.17;
                const r = @sqrt(dx * dx + dy * dy);
                const th = math.atan2(dy, dx);
                // Four-lobed clover ring: the gonads.
                const ring = 0.10 + 0.035 * @cos(4.0 * th);
                if (@abs(r - ring) < 0.011) return .{ 226, 140, 220 };
                if (hw - a < 0.12) return .{ 226, 242, 248 }; // brighter rim
                const g = (0.98 + 0.02 * @cos(18.0 * th)) * (1.0 + 0.06 * (1.0 - v));
                return .{ 170 * g, 206 * g, 218 * g };
            }
        }

        // Fine short tentacles hanging from the rim, one per cell of 1/13 s unit.
        if (u > bell_b and u < bell_b + 0.14 and a < bw - 0.05) {
            const cells = s * 13.0;
            const idx = @floor(cells);
            const tl = 0.09 + 0.04 * @abs(@sin(idx * 12.9898 + 0.3));
            if (u < bell_b + tl) {
                const sway = 0.04 * u * @sin(t - 9.0 * u + idx);
                const d = @abs(s - (idx + 0.5) / 13.0 - sway);
                if (d < 0.010) return .{ 176, 210, 224 };
            }
        }
        return null;
    }
};

const SeaTurtle = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Green sea turtle";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip.
    pub const length: f32 = 1.3;
    /// Half the body depth (top-to-belly) as a fraction of length.
    pub const half_depth: f32 = 0.28;
    /// The largest |s| the shape reaches (the front flipper sweeps to about 2).
    pub const extent: f32 = 2.4;
    /// Head points where the animal swims, belly down the screen.
    pub const upright: bool = false;
    /// Cruise speed relative to a clownfish.
    pub const speed: f32 = 0.6;
    /// How many live in the reef (1..24).
    pub const count: u8 = 2;
    /// Turtles wander alone.
    pub const school: bool = false;
    /// Mid-water.
    pub const habitat: u8 = 1;

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

const MoorishIdol = struct {
    /// Shown in credits. Keep it short.
    pub const name = "Moorish idol";
    /// Your animal, e.g. "Claude Haiku".
    pub const author = "Claude Haiku";

    // --- size and placement -------------------------------------------------
    /// Body length in world units, nose to tail tip. For scale: a neon tetra
    /// is 0.34, a clownfish 0.5, a yellow tang 0.7, the big silver fish 1.1.
    pub const length: f32 = 0.5;
    /// Half the body depth (top-to-belly) as a fraction of length. The
    /// renderer's W (one unit of `s` below) is length * half_depth.
    pub const half_depth: f32 = 0.2;
    /// The largest |s| your shape ever reaches, fins and body bends included.
    /// It sets the bounding box: anything beyond is clipped.
    pub const extent: f32 = 2.8;
    /// true draws the body axis vertical with the head (u = 0) on top, whatever
    /// way the animal moves (seahorse, jellyfish). false points the head where
    /// it swims and keeps the belly (s > 0) facing down the screen.
    pub const upright: bool = false;
    /// Cruise speed relative to a clownfish (1.0). Sharks ~1.4, lionfish ~0.4.
    pub const speed: f32 = 0.7;
    /// How many live in the reef (1..24).
    pub const count: u8 = 8;
    /// true: they stay together as a school. false: each wanders alone.
    pub const school: bool = true;
    /// Where they swim: 0 = hugging the reef and sand, 1 = mid-water,
    /// 2 = high in open water.
    pub const habitat: u8 = 1;

    /// Half-height of the disc at u, in units of W. Blunt front, tapering to
    /// the narrow tail root.
    fn bodyProfile(u: f32) f32 {
        const p = math.clamp((u - 0.18) / 0.62, 0.0, 1.0);
        const front = @sqrt(math.clamp(p / 0.22, 0.0, 1.0));
        return 0.12 + 0.88 * front * (1.0 - p) * (1.0 - 0.3 * p);
    }

    /// Fin height beyond the body edge, a smooth arch over u in [lo, hi].
    fn finHeight(u: f32, lo: f32, hi: f32, amp: f32) f32 {
        const q = math.clamp((u - lo) / (hi - lo), 0.0, 1.0);
        return amp * @sin(math.pi * q);
    }

    /// Body colour bands along u: white, black eye band, yellow, black band.
    fn bodyColour(u: f32) [3]f32 {
        if (u < 0.40) return .{ 248, 244, 232 };
        if (u < 0.49) return .{ 14, 12, 14 };
        if (u < 0.72) return .{ 252, 204, 36 };
        return .{ 14, 12, 14 };
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
        // Gentle tail swing: grows toward the tail tip.
        const sb = s - 0.15 * @sin(t) * u * u;
        const a = @abs(sb);

        // Dorsal filament: a thin white streamer from the top of the sail that
        // curls back over the tail and sways with sin(t).
        if (u > 0.50 and u <= 1.02) {
            const q = math.clamp((u - 0.50) / 0.50, 0.0, 1.0);
            const centre = -(1.5 + 1.0 * @sin(q * math.pi * 0.5)) + 0.15 * q * @sin(t - 1.2 * q);
            const th = 0.055 - 0.02 * q;
            if (@abs(sb - centre) < th) return .{ 250, 248, 240 };
        }

        // Long tubular snout with a small orange saddle.
        if (u >= 0.0 and u < 0.30) {
            const tube = 0.04 + 0.12 * math.clamp(u / 0.30, 0.0, 1.0);
            const off = sb + 0.10;
            if (@abs(off) < tube) {
                if (u > 0.07 and u < 0.12 and off < -0.3 * tube) return .{ 236, 116, 30 };
                return .{ 246, 240, 222 };
            }
        }

        // Tall disc body; the back side is taller than the belly.
        if (u >= 0.18 and u <= 0.80) {
            const k_top: f32 = if (sb < 0.0) 1.9 else 1.6;
            const hw = bodyProfile(u) * k_top;
            if (a <= hw) {
                // Eye: cream ring with a dark pupil, set in the black band.
                const eu = (u - 0.45) / 0.03;
                const ev = (sb + 0.45) / 0.08;
                const e2 = eu * eu + ev * ev;
                if (e2 < 1.0) return .{ 8, 8, 10 };
                if (e2 < 1.5) return .{ 70, 68, 74 };
                const c = bodyColour(u);
                if (hw - a < 0.07) return .{ c[0] * 0.6, c[1] * 0.6, c[2] * 0.6 };
                return c;
            }
        }

        // Dorsal sail: black with a white leading edge, rising off the back.
        if (sb < 0.0 and u >= 0.26 and u <= 0.78) {
            const hw = bodyProfile(u) * 1.9;
            const fh = finHeight(u, 0.26, 0.78, 0.9);
            if (a > hw and a <= hw + fh) {
                if (a - hw > 0.7 * fh) return .{ 240, 236, 226 };
                return .{ 26, 20, 22 };
            }
        }

        // Anal fin: the same arch, mirrored below the belly.
        if (sb > 0.0 and u >= 0.42 and u <= 0.82) {
            const hw = bodyProfile(u) * 1.6;
            const fa = finHeight(u, 0.42, 0.82, 0.5);
            if (a > hw and a <= hw + fa) {
                if (a - hw > 0.65 * fa) return .{ 240, 236, 226 };
                return .{ 26, 20, 22 };
            }
        }

        // Fan tail: black base, white band, black tip, yellow rim.
        if (u > 0.78 and u <= 1.0) {
            const tf = math.clamp((u - 0.80) / 0.20, 0.0, 1.0);
            const ht = 1.15 * math.pow(f32, tf, 0.9);
            const ua = a / 1.15;
            const u_edge = 1.0 - 0.05 * ua * ua;
            if (a <= ht and u <= u_edge) {
                if ((ht > 0.25 and ht - a < 0.08) or u > u_edge - 0.035) return .{ 255, 210, 40 };
                if (u < 0.87 or u > 0.93) return .{ 16, 14, 16 };
                return .{ 244, 242, 236 };
            }
        }
        return null;
    }
};

// @@SPECIES_INSERT@@

comptime {
    sdk.exportTheme(State);
}

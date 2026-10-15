// @argus-theme: custom_shader
// PUTEUS -- a well woven in light.                                 Claude, 2026-10-15
//
// Textus seen from above. A round well is cut into the cloth: a ring of woven tiles laid
// in staggered courses, loose warp hanging down its inner wall, and at the bottom a single
// block -- the maker's star in a garnet window -- burning white-hot. Around the well the
// cloth is crowded with woven blocks; the farther out they stand, the larger and taller
// they get, each showing the face it turns toward the well, the way pillars do when you
// look straight down into a pit.
//
// Time is temperature. Every few seconds the core lets go a slow ring of heat. As it
// passes a block, the block is woven anew (a fresh cellular-automaton motif, mirrored
// both ways into a diamond) and is born white-hot, then cools through gold, ember, rose
// and violet until the next ring comes. Lightning crosses the empty floor of the well:
// a jagged leader leaves the wall, forks, and fades as its branches meet at the core,
// flickering and lighting the pit as it goes. Inside the core the tiles are alive: an
// excitable medium (Greenberg-Hastings) in three colours, one per kind of lightning (hot,
// rose, pearl). Every touch fires the nearest tile in its colour and sends a diamond wave
// of floats across the window, cooling behind its front. Waves of different colours pass
// through each other and their light adds; where two colours' fronts cross, they fire the
// third, so strikes cascade. Every wave carries a strength that drops by one per tile it
// travels (cascades start at half the weaker front), so each one fades out and the core
// always returns to rest. Tiles struck often stay warm. At rest the star shows through. The floor is mirrored about the centre seam; the
// lightning and what it writes into the core are not. Nothing here is written.
//
// Knowledge:  elementary cellular automata (Wolfram rule numbers); plain weave vs. floats.
// Inference:  thread shading, glow and the looking-down faces are cartoon optics, tuned
//             by eye against rendered stills; no light is simulated.
// Generation: the well, the layout rules, the heat rings and their timing.
//
// Cost: one allocation (State), none afterwards. Per frame: one colour per thread
// crossing (8x8 px), then table lookups eight pixels at a time.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const CELL: usize = 8; // one thread crossing = 8x8 pixels
const MAX_C: usize = MAX_W / CELL; // 240
const MAX_R: usize = MAX_H / CELL; // 150
const MAX_HALF: usize = MAX_C / 2;
const MAX_ENT: usize = 2048;
const NSTAR: usize = 600;
const NBOLT: usize = 6;
const MAXSEG: usize = 256; // line segments per bolt, branches included
const NPT: usize = 65; // points in one fractal path (2^6 + 1)
const LEAD: f32 = 0.16; // seconds for the leader to cross from the wall to the core
const BOLT_LIFE: f32 = 0.95;
const MAX_WIN: usize = 20; // the core's window, in cells
const NS: u8 = 9; // tile states: 0 rest, 1 firing, 2..NS-1 cooling (refractory)
const CORE_HZ: f32 = 11.0; // tile generations per second
const STRIKE_STR: u8 = 30; // how many tiles a wave fired by lightning travels
const EMBER: u32 = sdk.packRGBA(255, 150, 112);

const SPEED: f32 = 22.0; // heat ring, pixels per second
const PERIOD: f32 = 15.0; // seconds between rings
const RISE: f32 = 1.6; // seconds a block takes to catch fire (nothing flashes)
const T0: f64 = 4.0 * 15.0; // the well has been burning for a while when the wallpaper starts

const VU = @Vector(8, u32);

// ---------------------------------------------------------------- palette (Textus)
const VOID: u32 = sdk.packRGBA(2, 3, 8);
const STAR_COL: u32 = sdk.packRGBA(214, 228, 255);
const SPARK_COL: u32 = sdk.packRGBA(255, 236, 200);
const FORGE_COL: u32 = sdk.packRGBA(255, 150, 70);
// three kinds of lightning, each with its own wave layer in the core: hot, rose, pearl
const NL: usize = 3;
const BOLT_CORE = [NL]u32{ sdk.packRGBA(255, 244, 220), sdk.packRGBA(255, 186, 226), sdk.packRGBA(214, 228, 255) };
const BOLT_GLOW = [NL]u32{ sdk.packRGBA(255, 150, 70), sdk.packRGBA(200, 80, 170), sdk.packRGBA(104, 134, 232) };
// a wave layer's colour as it fires, and as it has cooled just before resting
const WAVE_FIRE = [NL][3]f32{ .{ 255, 250, 236 }, .{ 255, 150, 210 }, .{ 200, 226, 255 } };
const WAVE_COOL = [NL][3]f32{ .{ 255, 150, 112 }, .{ 138, 98, 238 }, .{ 50, 70, 190 } };
const GARNET: u32 = sdk.packRGBA(66, 14, 42);
const INDIGO: u32 = sdk.packRGBA(40, 44, 108);
const SILKS = [_]u32{
    sdk.packRGBA(40, 44, 108), // indigo
    sdk.packRGBA(18, 70, 94), // teal
    sdk.packRGBA(84, 36, 92), // plum
    sdk.packRGBA(30, 52, 112), // ink
    sdk.packRGBA(16, 78, 78), // sea
};
const FIG_ANCHORS = [6][3]f32{
    .{ 255.0, 250.0, 236.0 }, // white-hot
    .{ 255.0, 214.0, 138.0 }, // gold
    .{ 255.0, 150.0, 112.0 }, // ember
    .{ 232.0, 96.0, 172.0 }, // rose
    .{ 138.0, 98.0, 238.0 }, // violet
    .{ 76.0, 96.0, 214.0 }, // cool
};
const RULES = [_]u8{ 90, 110, 60, 22, 126, 150, 30, 18 };
// the maker's mark: a four-point star, half-width at j rows from its centre line
const STAR_W = [8]u8{ 7, 5, 4, 3, 2, 1, 1, 1 };

// ---------------------------------------------------------------- cell roles
const R_GROUND: u8 = 0; // silk between things
const R_FIG: u8 = 1; // a warp float of its owner
const R_SILK: u8 = 2; // its owner's own silk
const R_STRAND: u8 = 3; // a bare hanging thread (the well wall, a block's face)
const R_PIT: u8 = 4; // the bottom of the well
const R_FACE: u8 = 5; // a side face seen edge-on: weft ribs in the owner's light
// brightness of each role, /256
const ROLEF = [6]u32{ 66, 256, 120, 170, 34, 70 };

const E_CORE: u8 = 0;
const E_RIM: u8 = 1;
const E_BLOCK: u8 = 2;

const Ent = struct {
    kind: u8,
    d: f32, // distance from the core, px (when the heat ring arrives)
    jit: f32, // px of head start, so neighbours don't burn in lockstep
    depth: u16, // brightness /256
    silk: u32,
    // blocks: full rect in cells; `mirror` = also woven at the mirrored position
    x0: u16,
    y0: u16,
    w: u16,
    h: u16,
    mirror: bool,
    cyc: i32,
};

const Star = struct { x: u16, y: u16, b: u8, ph: u8 };
// a bolt is a set of straight segments; u = how far along from the wall (0) to the core (1)
const Seg = struct { ax: f32, ay: f32, bx: f32, by: f32, ua: f32, ub: f32, wt: f32 };
const Bolt = struct { segs: [MAXSEG]Seg, n: usize, ends: [8][2]f32, n_ends: usize, age: f32, alive: bool, hit: bool, seed: u32, layer: u8 };

inline fn hash32(x: u32) u32 {
    var h = x *% 0x9E3779B1;
    h ^= h >> 15;
    h *%= 0x85EBCA77;
    h ^= h >> 13;
    h *%= 0xC2B2AE3D;
    h ^= h >> 16;
    return h;
}

fn smoothf(x: f32) f32 {
    const t = math.clamp(x, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    t: f64,
    ncol: usize,
    nrow: usize,
    half: usize,
    cxp: f32, // core centre, px
    cyp: f32,
    rp_px: f32, // well radius
    core_px: f32, // core half-size
    rng: u64,
    n_ent: usize,
    n_stars: usize,
    bolt_wait: f32, // seconds until the next strike
    flash: f32, // how brightly lightning lights the pit this frame
    n_strikes: u32,
    win_x0: usize, // the core's window (cells inside its frame)
    win_y0: usize,
    win_n: usize,
    core_acc: f32,
    dirty: bool,

    ents: [MAX_ENT]Ent,
    figc: [MAX_ENT]u32, // each owner's thread colour this frame
    owner: [MAX_R][MAX_C]u16,
    role: [MAX_R][MAX_C]u8,
    kind: [MAX_R][MAX_C]u8, // thread variant 0..8, as in Textus
    gainv: [MAX_R][MAX_C]u8, // static brightness: vignette, dye slubs, face gradient
    glow: [MAX_R][MAX_C]u8, // light the core throws on this crossing
    occ: [MAX_R][MAX_HALF + 1]u8, // layout scratch (left half)
    cc: [MAX_R][MAX_C]u32, // colour of each crossing this frame
    cl: [MAX_R][MAX_C]u32, // light a neighbouring float throws on it
    figgrad: [257]u32,
    prof: [9][8]VU,
    gprof: [3][8]VU,
    twink: [256]u8,
    stars: [NSTAR]Star,
    bolts: [NBOLT]Bolt,
    cst: [NL][MAX_WIN][MAX_WIN]u8, // tile states inside the core, one medium per colour
    cnx: [NL][MAX_WIN][MAX_WIN]u8,
    cstr: [NL][MAX_WIN][MAX_WIN]u8, // strength each tile's wave still carries
    cns: [NL][MAX_WIN][MAX_WIN]u8,
    wavec: [NL][NS]u32, // colour of each layer's states
    flash_l: usize, // which colour lights the pit
    cheat: [MAX_WIN][MAX_WIN]u8, // warmth left by strikes
    cstar: [MAX_WIN][MAX_WIN]u8, // the star, shown faintly at rest
    path: [4][NPT][2]f32, // scratch for fractal paths
    tmp: [MAX_C + 2]u8,
    tmp2: [MAX_C + 2]u8,
    pat: [MAX_R][MAX_C]u8,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        @memset(std.mem.asBytes(self), 0);
        self.w = @max(@min(w, MAX_W), 1);
        self.h = @max(@min(h, MAX_H), 1);
        self.scale = scale;
        self.t = T0;
        var nc = (self.w + CELL - 1) / CELL;
        if (nc % 2 == 1) nc += 1;
        self.ncol = @min(nc, MAX_C);
        self.nrow = @min((self.h + CELL - 1) / CELL, MAX_R);
        self.half = self.ncol / 2;
        self.rng = 0x2545F4914F6CDD1D;
        self.buildTables();
        self.layout();
        self.buildStars();
        self.paint();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn rnd(self: *State) u32 {
        self.rng +%= 0x9E3779B97F4A7C15;
        var z = self.rng;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return @truncate((z ^ (z >> 31)) >> 16);
    }

    fn unit(self: *State) f32 {
        return @as(f32, @floatFromInt(self.rnd() & 0xFFFFFF)) / 16777216.0;
    }

    // ------------------------------------------------------------ thread shading (from Textus)
    fn cyl(t: f32) f32 {
        const s = @sin(math.pi * t / 8.0);
        return 0.09 + 0.91 * math.pow(f32, @max(s, 0.0), 0.9);
    }

    fn cylw(t: f32) f32 {
        const s = @sin(math.pi * t / 8.0);
        return 0.50 + 0.50 * math.pow(f32, @max(s, 0.0), 0.8);
    }

    fn dive(t: f32, under: bool) f32 {
        if (!under) return 1.0;
        const u = math.clamp(t / 2.6, 0.0, 1.0);
        return 0.40 + 0.60 * u * u * (3.0 - 2.0 * u);
    }

    fn threadValue(v: usize, xp: f32, yp: f32) f32 {
        if (v == 8) {
            const d = (xp - 4.0) / 1.15;
            return 0.04 + 0.96 * @exp(-d * d);
        }
        if (v < 4) {
            const across = cyl(xp);
            const along = dive(yp, (v & 1) != 0) * dive(8.0 - yp, (v & 2) != 0);
            const twist = 0.93 + 0.07 * @sin(math.tau * (xp * 0.16 + yp * 0.27));
            const spec = 0.22 * @exp(-((xp - 3.0) * (xp - 3.0)) / 1.1);
            return across * along * twist + spec * along;
        }
        const across = cylw(yp);
        const twist = 0.93 + 0.07 * @sin(math.tau * (yp * 0.16 + xp * 0.27));
        const spec = 0.16 * @exp(-((yp - 3.0) * (yp - 3.0)) / 1.1);
        return across * twist + spec;
    }

    fn glowValue(k: usize, xp: f32, yp: f32) f32 {
        var gl: f32 = 0.0;
        if ((k & 1) != 0) gl += @exp(-xp / 3.0);
        if ((k & 2) != 0) gl += @exp(-(8.0 - xp) / 3.0);
        return 0.62 * @min(gl, 1.2) * cylw(yp);
    }

    fn buildTables(self: *State) void {
        for (0..9) |v| {
            for (0..8) |ly| {
                var row: [8]u32 = undefined;
                for (0..8) |lx| {
                    const val = threadValue(v, @as(f32, @floatFromInt(lx)) + 0.5, @floatFromInt(ly));
                    row[lx] = @intFromFloat(math.clamp(val, 0.0, 1.0) * 256.0);
                }
                self.prof[v][ly] = row;
            }
        }
        for (0..3) |gk| {
            for (0..8) |ly| {
                var row: [8]u32 = undefined;
                for (0..8) |lx| {
                    const val = glowValue(gk + 1, @as(f32, @floatFromInt(lx)) + 0.5, @floatFromInt(ly));
                    row[lx] = @intFromFloat(math.clamp(val, 0.0, 1.0) * 256.0);
                }
                self.gprof[gk][ly] = row;
            }
        }
        for (0..257) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 256.0 * 5.0;
            const seg: usize = @min(@as(usize, 4), @as(usize, @intFromFloat(t)));
            const f = t - @as(f32, @floatFromInt(seg));
            const e = f * f * (3.0 - 2.0 * f);
            const p0 = FIG_ANCHORS[seg];
            const p1 = FIG_ANCHORS[seg + 1];
            self.figgrad[i] = sdk.packRGBA(
                @intFromFloat(p0[0] + (p1[0] - p0[0]) * e),
                @intFromFloat(p0[1] + (p1[1] - p0[1]) * e),
                @intFromFloat(p0[2] + (p1[2] - p0[2]) * e),
            );
        }
        for (0..256) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 256.0;
            self.twink[i] = @intFromFloat(150.0 + 105.0 * @sin(math.tau * t));
        }
        for (0..NL) |l| {
            for (1..NS) |st| {
                const t: f32 = @as(f32, @floatFromInt(st - 1)) / @as(f32, @floatFromInt(NS - 2));
                const e = t * t * (3.0 - 2.0 * t);
                const dim = 1.0 - 0.72 * t;
                var c: [3]u8 = undefined;
                for (0..3) |ch| c[ch] = @intFromFloat((WAVE_FIRE[l][ch] + (WAVE_COOL[l][ch] - WAVE_FIRE[l][ch]) * e) * dim);
                self.wavec[l][st] = sdk.packRGBA(c[0], c[1], c[2]);
            }
        }
    }

    // ------------------------------------------------------------ the floor plan
    fn vignette(self: *const State, d: f32) f32 {
        const wf: f32 = @floatFromInt(self.w);
        const hf: f32 = @floatFromInt(self.h);
        const rm = 0.5 * @sqrt(wf * wf + hf * hf);
        return 1.0 - smoothf((d - 0.40 * rm) / (0.55 * rm));
    }

    fn addEnt(self: *State, e: Ent) ?u16 {
        if (self.n_ent >= MAX_ENT) return null;
        self.ents[self.n_ent] = e;
        self.n_ent += 1;
        return @intCast(self.n_ent - 1);
    }

    fn layout(self: *State) void {
        const C = self.ncol;
        const R = self.nrow;
        const half = self.half;
        const hc: f32 = @floatFromInt(half);
        const rc: f32 = @as(f32, @floatFromInt(R)) * 0.5;
        self.cxp = hc * CELL;
        self.cyp = rc * CELL;
        const m: f32 = @floatFromInt(@min(C, R));
        const k: f32 = @max(m / 150.0, 0.12);

        // the well, in cells
        // core: a 1-cell frame, a 20x20 garnet window, a 16-row star (the Textus cartouche)
        const core_h: usize = @max(@as(usize, 1), @min(@as(usize, 11), @as(usize, @intFromFloat(@round(11.0 * k)))));
        const rp: f32 = @max(34.0 * k, @as(f32, @floatFromInt(core_h)) + 3.0);
        const wall: f32 = @max(2.2 * k, 1.0);
        const cw = [3]f32{ @max(2.5 * k, 1.0), @max(3.0 * k, 1.0), @max(3.5 * k, 1.0) };
        const ro = rp + cw[0] + cw[1] + cw[2];
        self.rp_px = rp * CELL;
        self.core_px = @as(f32, @floatFromInt(core_h)) * CELL;

        // entity 0: the core
        _ = self.addEnt(.{ .kind = E_CORE, .d = 0, .jit = 0, .depth = 256, .silk = GARNET, .x0 = 0, .y0 = 0, .w = 0, .h = 0, .mirror = false, .cyc = 0 });

        // the rim: three courses of tiles, staggered like masonry
        var rim_base: [3]usize = undefined;
        var rim_n: [3]usize = undefined;
        var r_in: [3]f32 = undefined;
        var acc = rp;
        for (0..3) |ci| {
            r_in[ci] = acc;
            const rmid = acc + cw[ci] * 0.5;
            const tile_len = 4.6 * @max(k, 0.5);
            const n4 = @max(@as(usize, 1), @as(usize, @intFromFloat(@round(math.tau * rmid / (tile_len * 4.0)))));
            rim_n[ci] = n4 * 4;
            rim_base[ci] = self.n_ent;
            for (0..rim_n[ci]) |si| {
                const jit = @as(f32, @floatFromInt(hash32(@intCast(ci * 1000 + si)) % 64)) * 0.4;
                _ = self.addEnt(.{ .kind = E_RIM, .d = rmid * CELL, .jit = jit, .depth = 256, .silk = INDIGO, .x0 = 0, .y0 = 0, .w = 0, .h = 0, .mirror = false, .cyc = 0 });
            }
            acc += cw[ci];
        }

        // first pass over the left half: pit, wall, rim, ground
        for (0..R) |y| {
            for (0..half) |x| {
                const dx = @as(f32, @floatFromInt(x)) + 0.5 - hc;
                const dy = @as(f32, @floatFromInt(y)) + 0.5 - rc;
                const r = @sqrt(dx * dx + dy * dy);
                const dpx = r * CELL;
                const th = math.atan2(dx, -dy); // 0 at the top, negative on the left
                const slub: u32 = 205 + hash32(@intCast(y * MAX_C + x + 77)) % 51;
                var role: u8 = R_GROUND;
                var own: u16 = 0;
                var g: f32 = self.vignette(dpx);
                if (r < ro) {
                    g = 1.0;
                    if (r < rp - wall) {
                        role = R_PIT;
                    } else {
                        // which course and which tile
                        var ci: usize = 0;
                        if (r >= rp) {
                            ci = 2;
                            if (r < r_in[1]) ci = 0 else if (r < r_in[2]) ci = 1;
                        }
                        const off: f32 = if (ci == 1) 0.5 else 0.0;
                        const u = (th / math.tau + 0.5) * @as(f32, @floatFromInt(rim_n[ci])) + off;
                        const seg: usize = @as(usize, @intFromFloat(@floor(u))) % rim_n[ci];
                        own = @intCast(rim_base[ci] + seg);
                        if (r < rp) {
                            role = R_STRAND; // loose warp hanging down the wall
                            g = 0.25 + 0.75 * smoothf((r - (rp - wall)) / wall);
                        } else {
                            const arc = math.tau * r / @as(f32, @floatFromInt(rim_n[ci]));
                            const grout = (r - r_in[ci]) < 0.85 or (u - @floor(u)) * arc < 0.85;
                            if (grout) {
                                role = R_GROUND;
                                own = 0;
                            } else {
                                role = R_FIG;
                            }
                        }
                    }
                }
                self.owner[y][x] = own;
                self.role[y][x] = role;
                self.gainv[y][x] = @intCast(@min(@as(u32, 255), @as(u32, @intFromFloat(g * @as(f32, @floatFromInt(slub)) * 0.996))));
                // the core lights the well
                if (r < ro + 1.0) {
                    const dd = @max(dpx - self.core_px, 0.0);
                    self.glow[y][x] = @intFromFloat(255.0 * @exp(-dd / 85.0));
                }
                self.occ[y][x] = if (r < ro + 1.2) 1 else 0;
            }
        }

        // the core: a garnet window in a frame, the four-point star inside
        const ci0 = half - core_h;
        const rci: usize = R / 2;
        const ry0 = rci -| core_h;
        for (ry0..@min(R, rci + core_h)) |y| {
            for (ci0..half) |x| {
                const fx = x - ci0; // 0 = frame column
                const fy_top = y - ry0;
                const fy_bot = (rci + core_h - 1) - y;
                var fig = fx == 0 or fy_top == 0 or fy_bot == 0;
                if (!fig and core_h == 11) {
                    const j: usize = if (y < rci) rci - 1 - y else y - rci;
                    if (j < STAR_W.len) fig = (half - x) <= STAR_W[j];
                } else if (!fig) {
                    fig = true;
                }
                self.owner[y][x] = 0;
                self.role[y][x] = if (fig) R_FIG else R_SILK;
                self.gainv[y][x] = 250;
                self.glow[y][x] = 0; // the window stays deep garnet so the tiles read
            }
        }
        self.win_n = if (core_h >= 2) 2 * (core_h - 1) else 0;
        self.win_x0 = half + 1 - core_h;
        self.win_y0 = rci + 1 -| core_h;
        if (self.win_y0 + self.win_n > R) self.win_n = 0;

        // the blocks around the well; larger and taller the farther out they stand
        var tries: usize = 0;
        while (tries < 12000) : (tries += 1) {
            if (half < 3 or R < 3) break;
            const gx: usize = self.rnd() % half;
            const gy: usize = self.rnd() % R;
            const ddx = @as(f32, @floatFromInt(gx)) + 0.5 - hc;
            const ddy = @as(f32, @floatFromInt(gy)) + 0.5 - rc;
            const d = @sqrt(ddx * ddx + ddy * ddy);
            if (d < ro + 1.5) continue;
            const far = (d - ro) / @max(k, 0.3);
            const smax: usize = @min(@as(usize, 12), 3 + @as(usize, @intFromFloat(far / 5.0)));
            var hgt: usize = if (far > 6.0) @min(@as(usize, 4), @as(usize, @intFromFloat(far / 11.0)) + self.rnd() % 2) else self.rnd() % 2;
            hgt = @min(hgt, @as(usize, @intFromFloat(@max(2.5 * k, 1.0))) + 1);
            const tall = self.rnd() % 2 == 0;
            const squash = self.rnd() % 3;
            // the largest block that fits here, so the floor packs like stone
            var placed = false;
            var bw: usize = 0;
            var bh: usize = 0;
            var vertical = false;
            var bcx: f32 = 0;
            var bcy: f32 = 0;
            var fx0: usize = gx;
            var fy0: usize = gy;
            var fw: usize = 0;
            var fh: usize = 0;
            var seam = false;
            var sz: usize = smax;
            const smin: usize = if (far > 10.0) 3 else 2;
            while (sz >= smin and !placed) : (sz -= 1) {
                const s2 = @max(@as(usize, 2), sz -| squash);
                bw = if (tall) s2 else sz;
                bh = if (tall) sz else s2;
                // the face turned toward the well
                bcx = @as(f32, @floatFromInt(gx)) + @as(f32, @floatFromInt(bw)) * 0.5 - hc;
                bcy = @as(f32, @floatFromInt(gy)) + @as(f32, @floatFromInt(bh)) * 0.5 - rc;
                vertical = @abs(bcy) > @abs(bcx) * 0.75;
                fx0 = gx;
                fy0 = gy;
                fw = bw;
                fh = bh;
                if (hgt > 0) {
                    if (vertical) {
                        fh += hgt;
                        if (bcy > 0) {
                            if (gy < hgt) continue;
                            fy0 = gy - hgt;
                        }
                    } else {
                        fw += hgt;
                    }
                }
                if (fx0 + fw > half or fy0 + fh > R) continue;
                seam = fx0 + fw == half;
                if (seam and hgt > 0 and !vertical) continue;
                if (!self.rectFree(fx0, fy0, fw, fh)) continue;
                // keep clear of the rim
                const nx = math.clamp(hc, @as(f32, @floatFromInt(fx0)), @as(f32, @floatFromInt(fx0 + fw)));
                const ny = math.clamp(rc, @as(f32, @floatFromInt(fy0)), @as(f32, @floatFromInt(fy0 + fh)));
                if (@sqrt((nx - hc) * (nx - hc) + (ny - rc) * (ny - rc)) < ro + 1.2) continue;
                placed = true;
            }
            if (!placed) continue;
            const bx0: usize = gx;
            const by0: usize = gy;
            const fullw: usize = if (seam) 2 * (half - bx0) else bw;
            const id = self.addEnt(.{
                .kind = E_BLOCK,
                .d = @sqrt(bcx * bcx + bcy * bcy) * CELL,
                .jit = @as(f32, @floatFromInt(self.rnd() % 64)) * 0.5,
                .depth = 256,
                .silk = SILKS[self.rnd() % SILKS.len],
                .x0 = @intCast(bx0),
                .y0 = @intCast(by0),
                .w = @intCast(fullw),
                .h = @intCast(bh),
                .mirror = !seam,
                .cyc = 0,
            }) orelse break;
            for (fy0..fy0 + fh) |y| for (fx0..fx0 + fw) |x| {
                self.occ[y][x] = 1;
            };
            // the face
            if (hgt > 0) {
                for (0..hgt) |i| {
                    const fade: f32 = 1.0 - (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(hgt)) * 0.65;
                    if (vertical) {
                        const y = if (bcy > 0) by0 - 1 - i else by0 + bh + i;
                        for (bx0..bx0 + bw) |x| self.setStatic(x, y, id, R_STRAND, fade);
                    } else {
                        const x = bx0 + bw + i;
                        for (by0..by0 + bh) |y| self.setStatic(x, y, id, R_FACE, fade);
                    }
                }
            }
            for (by0..by0 + bh) |y| for (bx0..bx0 + bw) |x| self.setStatic(x, y, id, R_FIG, 1.0);
        }

        // mirror the left half onto the right
        for (0..R) |y| {
            for (0..half) |x| {
                const xm = C - 1 - x;
                self.owner[y][xm] = self.owner[y][x];
                self.role[y][xm] = self.role[y][x];
                self.gainv[y][xm] = self.gainv[y][x];
                self.glow[y][xm] = self.glow[y][x];
            }
        }

        // the star, remembered so the tiles can rest on it
        for (0..self.win_n) |j| for (0..self.win_n) |i| {
            self.cstar[j][i] = if (self.role[self.win_y0 + j][self.win_x0 + i] == R_FIG) 1 else 0;
        };

        // weave every block's current motif
        for (0..self.n_ent) |i| {
            if (self.ents[i].kind != E_BLOCK) continue;
            self.ents[i].cyc = self.cycleOf(i);
            self.weaveBlock(i);
        }
        self.kinds(0, 0, C, R);
    }

    fn setStatic(self: *State, x: usize, y: usize, id: u16, role: u8, fade: f32) void {
        const dx = @as(f32, @floatFromInt(x)) + 0.5 - @as(f32, @floatFromInt(self.half));
        const dy = @as(f32, @floatFromInt(y)) + 0.5 - @as(f32, @floatFromInt(self.nrow)) * 0.5;
        const g = self.vignette(@sqrt(dx * dx + dy * dy) * CELL) * fade;
        const slub: f32 = @floatFromInt(222 + hash32(@intCast(y * MAX_C + x)) % 34);
        self.owner[y][x] = id;
        self.role[y][x] = role;
        self.gainv[y][x] = @intFromFloat(math.clamp(g * slub, 0.0, 255.0));
    }

    fn rectFree(self: *const State, x0: usize, y0: usize, w: usize, h: usize) bool {
        const xa = x0 -| 1;
        const ya = y0 -| 1;
        const xb = @min(self.half, x0 + w + 1);
        const yb = @min(self.nrow, y0 + h + 1);
        for (ya..yb) |y| for (xa..xb) |x| {
            if (self.occ[y][x] != 0) return false;
        };
        return true;
    }

    fn cycleOf(self: *const State, i: usize) i32 {
        const e = self.ents[i];
        const s: f64 = self.t * SPEED - e.d + e.jit;
        return @intFromFloat(@floor(s / (PERIOD * SPEED)));
    }

    // a fresh motif: an elementary CA grown down half the block, replayed back up (a diamond),
    // mirrored about the block's own seam, inside a frame of floats
    fn weaveBlock(self: *State, i: usize) void {
        const e = self.ents[i];
        const W: usize = e.w;
        const H: usize = e.h;
        if (W == 0 or H == 0) return;
        if (W <= 3 or H <= 3) {
            for (0..H) |yy| for (0..W) |xx| self.writeBlockCell(e, xx, yy, true);
            return;
        }
        const iw = W - 2;
        const ih = H - 2;
        const hs: u32 = hash32(@as(u32, @intCast(i)) *% 7919 +% @as(u32, @bitCast(e.cyc)));
        const rule = RULES[hs % RULES.len];
        @memset(self.tmp[0 .. iw + 2], 0);
        // seed: the centre, and sometimes a pair further out
        self.tmp[1 + (iw - 1) / 2] = 1;
        self.tmp[1 + iw / 2] = 1;
        if ((hs >> 8) % 3 == 0 and iw > 4) {
            const o = 1 + (hs >> 12) % (iw / 2);
            self.tmp[1 + (iw - 1) / 2 - @min(o, (iw - 1) / 2)] = 1;
        }
        const grow = (ih + 1) / 2;
        for (0..grow) |r| {
            // mirror the row about the block seam
            for (0..iw / 2) |c| self.tmp[1 + iw - 1 - c] = self.tmp[1 + c];
            for (0..iw) |c| {
                self.pat[r][c] = self.tmp[1 + c];
                self.pat[ih - 1 - r][c] = self.tmp[1 + c];
            }
            for (0..iw) |c| {
                const l = self.tmp[c];
                const m = self.tmp[c + 1];
                const rr = self.tmp[c + 2];
                const idx: u3 = @intCast((l << 2) | (m << 1) | rr);
                self.tmp2[c + 1] = (rule >> idx) & 1;
            }
            @memcpy(self.tmp[1 .. iw + 1], self.tmp2[1 .. iw + 1]);
        }
        for (0..H) |yy| {
            for (0..W) |xx| {
                const frame = xx == 0 or yy == 0 or xx == W - 1 or yy == H - 1;
                const fig = frame or self.pat[yy - 1][xx - 1] != 0;
                self.writeBlockCell(e, xx, yy, fig);
            }
        }
    }

    fn writeBlockCell(self: *State, e: Ent, xx: usize, yy: usize, fig: bool) void {
        const x = @as(usize, e.x0) + xx;
        const y = @as(usize, e.y0) + yy;
        if (y >= self.nrow or x >= self.ncol) return;
        const role = if (fig) R_FIG else R_SILK;
        self.role[y][x] = role;
        if (e.mirror) {
            const xm = self.ncol - 1 - x;
            self.role[y][xm] = role;
        }
    }

    fn isFig(self: *const State, x: isize, y: isize) bool {
        if (x < 0 or y < 0) return false;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= self.ncol or uy >= self.nrow) return false;
        return self.role[uy][ux] == R_FIG;
    }

    fn kinds(self: *State, xa: usize, ya: usize, xb: usize, yb: usize) void {
        for (ya..@min(yb, self.nrow)) |y| {
            for (xa..@min(xb, self.ncol)) |x| {
                const ix: isize = @intCast(x);
                const iy: isize = @intCast(y);
                const r = self.role[y][x];
                self.kind[y][x] = if (r == R_FIG)
                    (if (self.isFig(ix, iy - 1)) @as(u8, 0) else 1) | (if (self.isFig(ix, iy + 1)) @as(u8, 0) else 2)
                else if (r == R_STRAND)
                    8
                else
                    4 + (if (self.isFig(ix - 1, iy)) @as(u8, 1) else 0) + (if (self.isFig(ix + 1, iy)) @as(u8, 2) else 0);
            }
        }
    }

    fn buildStars(self: *State) void {
        const want: usize = @min(@as(usize, NSTAR), self.w * self.h / 2560);
        var tries: usize = 0;
        while (self.n_stars < want and tries < want * 40) : (tries += 1) {
            const x: usize = self.rnd() % self.w;
            const y: usize = self.rnd() % self.h;
            const dx = @as(f32, @floatFromInt(x)) - self.cxp;
            const dy = @as(f32, @floatFromInt(y)) - self.cyp;
            if (self.vignette(@sqrt(dx * dx + dy * dy)) > 0.30) continue;
            self.stars[self.n_stars] = .{ .x = @intCast(x), .y = @intCast(y), .b = @intCast(40 + self.rnd() % 200), .ph = @truncate(self.rnd()) };
            self.n_stars += 1;
        }
    }

    // ------------------------------------------------------------ time
    pub fn step(self: *State, dt_in: f64) void {
        var dt = dt_in;
        if (!(dt > 0.0)) dt = 0.0;
        if (dt > 2.0) dt = 2.0;
        self.t += dt;
        if (self.t > 1.0e7) self.t = T0; // days of uptime: start the burn over
        const dtf: f32 = @floatCast(dt);

        // a block whose heat ring has just arrived is woven anew
        for (0..self.n_ent) |i| {
            if (self.ents[i].kind != E_BLOCK) continue;
            const c = self.cycleOf(i);
            if (c != self.ents[i].cyc) {
                self.ents[i].cyc = c;
                self.weaveBlock(i);
                const e = self.ents[i];
                const xa = @as(usize, e.x0) -| 1;
                const ya = @as(usize, e.y0) -| 1;
                self.kinds(xa, ya, @as(usize, e.x0) + e.w + 1, @as(usize, e.y0) + e.h + 1);
                if (e.mirror) {
                    const xm0 = self.ncol -| (@as(usize, e.x0) + e.w + 1);
                    self.kinds(xm0, ya, self.ncol - @as(usize, e.x0) + 1, @as(usize, e.y0) + e.h + 1);
                }
            }
        }

        // lightning: strikes at uneven intervals, sometimes two at once
        self.bolt_wait -= dtf;
        var guard: usize = 0;
        while (self.bolt_wait <= 0.0 and guard < 3) : (guard += 1) {
            self.bolt_wait += 0.25 + 1.6 * self.unit() * self.unit();
            for (0..NBOLT) |bi| {
                if (self.bolts[bi].alive) continue;
                self.strike(bi);
                break;
            }
        }
        self.flash = 0.0;
        for (&self.bolts) |*b| {
            if (!b.alive) continue;
            b.age += dtf;
            if (!b.hit and b.age >= LEAD) {
                b.hit = true;
                for (b.ends[0..b.n_ends]) |e| self.touchCore(e[0], e[1], b.layer);
            }
            if (b.age > BOLT_LIFE) {
                b.alive = false;
                continue;
            }
            const bl = boltLight(b.*);
            if (bl > self.flash) {
                self.flash = bl;
                self.flash_l = b.layer;
            }
        }

        // the core's tiles: one generation of the excitable medium per tick
        self.core_acc += dtf * CORE_HZ;
        var gens: usize = 0;
        while (self.core_acc >= 1.0 and gens < 4) : (gens += 1) {
            self.core_acc -= 1.0;
            self.coreGeneration();
        }
        if (self.core_acc > 1.0) self.core_acc = 0.0;
        self.paint();
    }

    // lightning touched the core's edge at (ex, ey): fire the nearest tiles, leave warmth
    fn touchCore(self: *State, ex: f32, ey: f32, layer: u8) void {
        const n = self.win_n;
        if (n == 0) return;
        const fx = ex / CELL - @as(f32, @floatFromInt(self.win_x0));
        const fy = ey / CELL - @as(f32, @floatFromInt(self.win_y0));
        if (!(fx > -1.0e4 and fx < 1.0e4 and fy > -1.0e4 and fy < 1.0e4)) return;
        const nf: f32 = @floatFromInt(n - 1);
        const ix: usize = @intFromFloat(math.clamp(@floor(fx), 0.0, nf));
        const iy: usize = @intFromFloat(math.clamp(@floor(fy), 0.0, nf));
        // always fire, even a tile that is still cooling: a new wave runs over the old one
        self.cst[layer % NL][iy][ix] = 1;
        self.cstr[layer % NL][iy][ix] = STRIKE_STR;
        const ya = iy -| 1;
        const xa = ix -| 1;
        for (ya..@min(n, iy + 2)) |j| for (xa..@min(n, ix + 2)) |i| {
            self.cheat[j][i] = @min(@as(u8, 230), self.cheat[j][i] +| 70);
        };
    }

    fn coreGeneration(self: *State) void {
        const n = self.win_n;
        if (n == 0) return;
        for (0..NL) |l| {
            const cs = &self.cst[l];
            const cg = &self.cstr[l];
            for (0..n) |j| {
                for (0..n) |i| {
                    const st = cs[j][i];
                    var nx: u8 = 0;
                    var ns: u8 = 0;
                    if (st == 0) {
                        // a resting tile fires when a neighbour (von Neumann) fires with strength to spare:
                        // diamond waves that weaken by one per tile
                        var best: u8 = 0;
                        if (j > 0 and cs[j - 1][i] == 1) best = @max(best, cg[j - 1][i]);
                        if (j + 1 < n and cs[j + 1][i] == 1) best = @max(best, cg[j + 1][i]);
                        if (i > 0 and cs[j][i - 1] == 1) best = @max(best, cg[j][i - 1]);
                        if (i + 1 < n and cs[j][i + 1] == 1) best = @max(best, cg[j][i + 1]);
                        if (best > 1) {
                            nx = 1;
                            ns = best - 1;
                        }
                    } else {
                        nx = if (st + 1 >= NS) 0 else st + 1;
                        ns = if (nx == 0) 0 else cg[j][i];
                    }
                    self.cnx[l][j][i] = nx;
                    self.cns[l][j][i] = ns;
                }
            }
        }
        for (0..n) |j| {
            for (0..n) |i| {
                // interference: where two colours' fronts cross, the third colour fires, at half the weaker
                inline for (0..NL) |l| {
                    const a = (l + 1) % NL;
                    const b = (l + 2) % NL;
                    if (self.cnx[a][j][i] == 1 and self.cnx[b][j][i] == 1 and self.cnx[l][j][i] == 0) {
                        const sc = @min(self.cns[a][j][i], self.cns[b][j][i]) / 2;
                        if (sc > 1) {
                            self.cnx[l][j][i] = 1;
                            self.cns[l][j][i] = sc;
                        }
                    }
                }
                var any = false;
                for (0..NL) |l| {
                    self.cst[l][j][i] = self.cnx[l][j][i];
                    self.cstr[l][j][i] = self.cns[l][j][i];
                    any = any or self.cnx[l][j][i] != 0;
                }
                // warmth fades, a little every generation
                self.cheat[j][i] -|= @as(u8, @intFromBool(self.cheat[j][i] > 0)) + self.cheat[j][i] / 48;
                const fig = any or self.cstar[j][i] != 0;
                self.role[self.win_y0 + j][self.win_x0 + i] = if (fig) R_FIG else R_SILK;
            }
        }
        self.kinds(self.win_x0 -| 1, self.win_y0 -| 1, self.win_x0 + n + 1, self.win_y0 + n + 1);
    }

    // how bright a bolt is now: the leader, a flash on contact, then a flickering decay
    fn boltLight(b: Bolt) f32 {
        if (b.age < LEAD) return 0.55;
        const flick: f32 = 0.6 + 0.4 * @as(f32, @floatFromInt(hash32(b.seed +% @as(u32, @intFromFloat(b.age * 34.0))) & 255)) / 255.0;
        return flick * @exp(-(b.age - LEAD) / 0.3);
    }

    // the point on the core's edge in the direction (dx, dy) from its centre
    fn coreEdge(self: *const State, dx: f32, dy: f32) [2]f32 {
        const m = @max(@max(@abs(dx), @abs(dy)), 1.0e-6);
        const k = (self.core_px + 1.0) / m;
        return .{ self.cxp + dx * k, self.cyp + dy * k };
    }

    // a jagged path from a to b by midpoint displacement into self.path[slot]; returns its length in points
    fn fractal(self: *State, slot: usize, ax: f32, ay: f32, bx: f32, by: f32, depth: u5, rough: f32) usize {
        const n: usize = (@as(usize, 1) << depth) + 1;
        const p = &self.path[slot];
        p[0] = .{ ax, ay };
        p[n - 1] = .{ bx, by };
        var st: usize = n - 1;
        while (st > 1) : (st /= 2) {
            var i: usize = st / 2;
            while (i < n) : (i += st) {
                const a = p[i - st / 2];
                const c = p[i + st / 2];
                const dx = c[0] - a[0];
                const dy = c[1] - a[1];
                const off = (self.unit() * 2.0 - 1.0) * rough;
                p[i] = .{ (a[0] + c[0]) * 0.5 - dy * off, (a[1] + c[1]) * 0.5 + dx * off };
            }
        }
        return n;
    }

    fn addSegs(self: *State, b: *Bolt, slot: usize, n: usize, ua: f32, ub: f32, wt: f32) void {
        const p = &self.path[slot];
        for (0..n - 1) |i| {
            if (b.n >= MAXSEG) return;
            const f0 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
            const f1 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(n - 1));
            b.segs[b.n] = .{ .ax = p[i][0], .ay = p[i][1], .bx = p[i + 1][0], .by = p[i + 1][1], .ua = ua + (ub - ua) * f0, .ub = ua + (ub - ua) * f1, .wt = wt };
            b.n += 1;
        }
    }

    fn strike(self: *State, bi: usize) void {
        const b = &self.bolts[bi];
        b.n = 0;
        b.n_ends = 0;
        b.age = 0.0;
        b.alive = true;
        b.hit = false;
        b.seed = self.rnd();
        // the three kinds take turns, with a random swap now and then
        b.layer = @intCast((self.n_strikes + @as(u32, @intFromBool(self.rnd() % 4 == 0))) % NL);
        self.n_strikes +%= 1;
        const th = self.unit() * math.tau;
        const r = self.rp_px - 10.0;
        const sx = self.cxp + r * @sin(th);
        const sy = self.cyp - r * @cos(th);
        const jit = (self.unit() - 0.5) * 0.7;
        const e = self.coreEdge(@sin(th + jit), -@cos(th + jit));
        const nm = self.fractal(0, sx, sy, e[0], e[1], 6, 0.42);
        self.addSegs(b, 0, nm, 0.0, 1.0, 1.0);
        b.ends[0] = e;
        b.n_ends = 1;
        // branches fork off the leader; about half of them also reach the core
        const nbr = 2 + self.rnd() % 3;
        for (0..nbr) |_| {
            const i = 4 + self.rnd() % (nm * 2 / 3);
            const pa = self.path[0][i];
            const u_at = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(nm - 1));
            const to_core = self.rnd() % 2 == 0;
            var tx: f32 = 0;
            var ty: f32 = 0;
            var u_end: f32 = 1.0;
            if (to_core and b.n_ends < b.ends.len) {
                const a2 = th + (self.unit() - 0.5) * 1.6;
                const ee = self.coreEdge(@sin(a2), -@cos(a2));
                tx = ee[0];
                ty = ee[1];
                b.ends[b.n_ends] = ee;
                b.n_ends += 1;
            } else {
                // off to one side, dying in the dark
                const q = self.path[0][@min(i + 2, nm - 1)];
                const dx = q[0] - pa[0];
                const dy = q[1] - pa[1];
                const dl = @max(@sqrt(dx * dx + dy * dy), 1.0e-3);
                const ang = (if (self.rnd() % 2 == 0) @as(f32, 1.0) else -1.0) * (0.45 + 0.6 * self.unit());
                const ca = @cos(ang);
                const sa = @sin(ang);
                const len = (0.25 + 0.3 * self.unit()) * (self.rp_px - self.core_px);
                tx = pa[0] + (dx * ca - dy * sa) / dl * len;
                ty = pa[1] + (dx * sa + dy * ca) / dl * len;
                u_end = @min(1.0, u_at + 0.45);
            }
            const nb = self.fractal(1, pa[0], pa[1], tx, ty, 5, 0.38);
            self.addSegs(b, 1, nb, u_at, u_end, 0.6);
            // a twig off the branch
            if (self.rnd() % 2 == 0) {
                const j = 2 + self.rnd() % (nb / 2);
                const pb = self.path[1][j];
                const tl = 0.12 * (self.rp_px - self.core_px);
                const a3 = self.unit() * math.tau;
                const nt = self.fractal(2, pb[0], pb[1], pb[0] + @cos(a3) * tl, pb[1] + @sin(a3) * tl, 3, 0.35);
                const uj = u_at + (u_end - u_at) * @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(nb - 1));
                self.addSegs(b, 2, nt, uj, @min(1.0, uj + 0.15), 0.35);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (!math.isFinite(self.t)) return true;
        if (!math.isFinite(self.flash)) return true;
        for (self.bolts) |b| {
            if (b.alive and !math.isFinite(b.age)) return true;
        }
        return false;
    }

    // ------------------------------------------------------------ colour of every crossing
    fn heatColor(self: *const State, e: Ent) u32 {
        const s: f32 = @floatCast(self.t * SPEED - e.d + e.jit);
        if (s < 0) return self.figgrad[256];
        const p = PERIOD * SPEED;
        const sec = (s - @floor(s / p) * p) / SPEED;
        const age = math.clamp(sec / PERIOD, 0.0, 1.0);
        var col = self.figgrad[@as(usize, @intFromFloat(age * 256.0))];
        if (sec < RISE) col = sdk.lerpRGB(self.figgrad[256], col, @intFromFloat(smoothf(sec / RISE) * 256.0));
        // cooling cloth also dims, so the newest ring is the one you see
        const lum = 0.30 + 0.70 * math.pow(f32, 1.0 - age, 1.2);
        return sdk.scaleRGB(col, @intFromFloat(lum * @as(f32, @floatFromInt(e.depth))));
    }

    fn paint(self: *State) void {
        const tf: f32 = @floatCast(@mod(self.t, 600.0));
        const breath = 0.5 + 0.5 * @sin(math.tau * tf / 7.5);
        for (0..self.n_ent) |i| {
            const e = self.ents[i];
            self.figc[i] = if (e.kind == E_CORE)
                self.figgrad[@as(usize, @intFromFloat(6.0 + 22.0 * breath))]
            else
                self.heatColor(e);
        }
        const glow_k: u32 = @intFromFloat(70.0 + 40.0 * breath);
        const flash_k: u32 = @intFromFloat(math.clamp(self.flash, 0.0, 1.0) * 46.0);
        for (0..self.nrow) |y| {
            for (0..self.ncol) |x| {
                const r = self.role[y][x];
                const o = self.owner[y][x];
                const base: u32 = switch (r) {
                    R_FIG, R_STRAND, R_FACE => self.figc[o],
                    R_SILK => self.ents[o].silk,
                    else => INDIGO,
                };
                var c = sdk.scaleRGB(base, (@as(u32, self.gainv[y][x]) * ROLEF[r]) >> 8);
                const gl: u32 = self.glow[y][x];
                if (gl != 0) {
                    c = sdk.addRGB(c, sdk.scaleRGB(FORGE_COL, (gl * glow_k) >> 8));
                    if (flash_k != 0) c = sdk.addRGB(c, sdk.scaleRGB(BOLT_GLOW[self.flash_l], (gl * flash_k) >> 8));
                }
                self.cc[y][x] = c;
            }
        }
        // the core's tiles: firing = white-hot, cooling down the ramp, resting star faint violet,
        // resting silk garnet warmed by recent strikes
        const star_k: u32 = @intFromFloat(120.0 + 40.0 * breath);
        for (0..self.win_n) |j| {
            for (0..self.win_n) |i| {
                const ht: u32 = self.cheat[j][i];
                var c: u32 = 0xFF000000;
                var any = false;
                for (0..NL) |l| {
                    const st = self.cst[l][j][i];
                    if (st == 0) continue;
                    // colours add where waves overlap; a weakening wave dims as it travels
                    const k: u32 = 110 + 146 * @as(u32, self.cstr[l][j][i]) / STRIKE_STR;
                    c = sdk.addRGB(c, sdk.scaleRGB(self.wavec[l][st], k));
                    any = true;
                }
                if (any) {} else if (self.cstar[j][i] != 0) {
                    c = sdk.scaleRGB(self.figgrad[230], star_k + ht / 3);
                } else {
                    c = sdk.lerpRGB(GARNET, sdk.scaleRGB(EMBER, 150), ht * 3 / 4);
                }
                self.cc[self.win_y0 + j][self.win_x0 + i] = c;
            }
        }
        for (0..self.nrow) |y| {
            for (0..self.ncol) |x| {
                const v = self.kind[y][x];
                if (v < 5 or v > 7) continue;
                const src = if ((v & 1) != 0 and x > 0) x - 1 else @min(x + 1, self.ncol - 1);
                self.cl[y][x] = sdk.scaleRGB(self.cc[y][src], 200);
            }
        }
    }

    // ------------------------------------------------------------ drawing
    inline fn scaleV(c: u32, s: VU) VU {
        const sh8: @Vector(8, u5) = @splat(8);
        const mrb: VU = @splat(0x00FF00FF);
        const m8: VU = @splat(255);
        const opaque_a: VU = @splat(0xFF000000);
        const rb: VU = @splat(c & 0x00FF00FF);
        const gg: VU = @splat((c >> 8) & 255);
        const rbv = ((rb * s) >> sh8) & mrb;
        const gv = (((gg * s) >> sh8) & m8) << sh8;
        return rbv | gv | opaque_a;
    }

    inline fn addSat(a: VU, b: VU) VU {
        const BV = @Vector(32, u8);
        return @bitCast(@as(BV, @bitCast(a)) +| @as(BV, @bitCast(b)));
    }

    // the floor sits on the void: at zero light a crossing is VOID, never darker
    const LIFT: VU = @splat(VOID & 0x00FFFFFF);

    inline fn cellVec(self: *const State, y: usize, x: usize, ly: usize) VU {
        const v = self.kind[y][x];
        var px = scaleV(self.cc[y][x], self.prof[v][ly]);
        if (v >= 5 and v <= 7) px = addSat(px, scaleV(self.cl[y][x], self.gprof[v - 5][ly]));
        return addSat(px, LIFT);
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        if (stride < w) return;
        const h = @min(self.h, buf.len / stride);
        const nfull = @min(w / CELL, self.ncol);
        const rem = w - nfull * CELL;
        for (0..h) |y| {
            const dst = buf[y * stride ..][0..w];
            const cy = @min(y / CELL, self.nrow - 1);
            const ly = y & 7;
            for (0..nfull) |c| dst[c * CELL ..][0..8].* = self.cellVec(cy, c, ly);
            if (rem != 0) {
                const t: [8]u32 = self.cellVec(cy, @min(nfull, self.ncol - 1), ly);
                @memcpy(dst[nfull * CELL ..][0..rem], t[0..rem]);
            }
        }
        self.drawLights(buf, stride, h);
    }

    fn plotBolt(self: *const State, buf: []u32, stride: usize, h: usize, fx: f32, fy: f32, k: f32, wide: bool, l: usize) void {
        const core_c = BOLT_CORE[l];
        const glow_c = BOLT_GLOW[l];
        // stay on the floor of the well: inside the wall, outside the core
        const dx = fx - self.cxp;
        const dy = fy - self.cyp;
        if (dx * dx + dy * dy > (self.rp_px - 4.0) * (self.rp_px - 4.0)) return;
        if (@abs(dx) < self.core_px + 1.0 and @abs(dy) < self.core_px + 1.0) return;
        const x: isize = @intFromFloat(@round(fx));
        const y: isize = @intFromFloat(@round(fy));
        const kc: u32 = @intFromFloat(@min(k, 256.0));
        const kg: u32 = @intFromFloat(@min(k * 0.55, 256.0));
        self.addPx(buf, stride, h, x, y, core_c, kc);
        self.addPx(buf, stride, h, x - 1, y, glow_c, kg);
        self.addPx(buf, stride, h, x + 1, y, glow_c, kg);
        self.addPx(buf, stride, h, x, y - 1, glow_c, kg);
        self.addPx(buf, stride, h, x, y + 1, glow_c, kg);
        if (wide) {
            const kw: u32 = @intFromFloat(@min(k * 0.22, 256.0));
            self.addPx(buf, stride, h, x - 2, y, glow_c, kw);
            self.addPx(buf, stride, h, x + 2, y, glow_c, kw);
            self.addPx(buf, stride, h, x, y - 2, glow_c, kw);
            self.addPx(buf, stride, h, x, y + 2, glow_c, kw);
        }
    }

    fn drawSeg(self: *const State, buf: []u32, stride: usize, h: usize, sg: Seg, light: f32, front: f32, l: usize) void {
        if (!(@abs(sg.ax) < 1.0e5 and @abs(sg.ay) < 1.0e5 and @abs(sg.bx) < 1.0e5 and @abs(sg.by) < 1.0e5)) return;
        const dx = sg.bx - sg.ax;
        const dy = sg.by - sg.ay;
        const n: usize = @as(usize, @intFromFloat(@max(@abs(dx), @abs(dy)))) + 1;
        const inv = 1.0 / @as(f32, @floatFromInt(n));
        for (0..n) |i| {
            const f = @as(f32, @floatFromInt(i)) * inv;
            const u = sg.ua + (sg.ub - sg.ua) * f;
            if (u > front) return;
            // brightest at the wall, fading toward the core; the leader's tip burns hottest
            var k = 256.0 * light * sg.wt * (1.0 - 0.6 * u);
            if (front <= 1.0) k *= 0.5 + 0.5 * smoothf(1.0 - (front - u) / 0.25);
            if (k < 2.0) continue;
            self.plotBolt(buf, stride, h, sg.ax + dx * f, sg.ay + dy * f, k, sg.wt > 0.5, l);
        }
    }

    // where a branch meets the core: a small soft flare
    fn flare(self: *const State, buf: []u32, stride: usize, h: usize, ex: f32, ey: f32, light: f32, l: usize) void {
        const cx: isize = @intFromFloat(@round(ex));
        const cy: isize = @intFromFloat(@round(ey));
        var j: isize = -9;
        while (j <= 9) : (j += 1) {
            var i: isize = -9;
            while (i <= 9) : (i += 1) {
                const d2: f32 = @floatFromInt(i * i + j * j);
                const k = 150.0 * light * @exp(-d2 / 14.0);
                if (k < 2.0) continue;
                self.addPx(buf, stride, h, cx + i, cy + j, BOLT_CORE[l], @intFromFloat(k));
            }
        }
    }

    inline fn addPx(self: *const State, buf: []u32, stride: usize, h: usize, x: isize, y: isize, col: u32, k: u32) void {
        if (x < 0 or y < 0) return;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= self.w or uy >= h) return;
        const i = uy * stride + ux;
        buf[i] = sdk.addRGB(buf[i], sdk.scaleRGB(col, k));
    }

    fn drawLights(self: *const State, buf: []u32, stride: usize, h: usize) void {
        // stars, where the floor has faded into the dark
        const tw: u32 = @intFromFloat(@mod(self.t * 23.0, 256.0));
        for (self.stars[0..self.n_stars]) |s| {
            const k: u32 = (@as(u32, s.b) * self.twink[(s.ph +% @as(u8, @truncate(tw))) & 255]) >> 8;
            const x: isize = s.x;
            const y: isize = s.y;
            self.addPx(buf, stride, h, x, y, STAR_COL, k);
            if (s.b > 200) {
                const k2 = k / 4;
                self.addPx(buf, stride, h, x - 1, y, STAR_COL, k2);
                self.addPx(buf, stride, h, x + 1, y, STAR_COL, k2);
                self.addPx(buf, stride, h, x, y - 1, STAR_COL, k2);
                self.addPx(buf, stride, h, x, y + 1, STAR_COL, k2);
            }
        }
        // lightning: the leader grows from the wall, then the whole bolt flashes and flickers out;
        // it dims toward the core and flares a little where it meets it
        for (self.bolts) |b| {
            if (!b.alive) continue;
            const light = boltLight(b);
            const front = if (b.age < LEAD) b.age / LEAD else 2.0;
            for (b.segs[0..b.n]) |sg| {
                if (sg.ua > front) continue;
                self.drawSeg(buf, stride, h, sg, light, front, b.layer % NL);
            }
            if (b.age >= LEAD) {
                for (b.ends[0..b.n_ends]) |e| self.flare(buf, stride, h, e[0], e[1], light, b.layer % NL);
            }
        }
    }
};

comptime {
    sdk.exportTheme(State);
}

// TEXTUS -- a loom that weaves light.                              Claude, 2026-10-15
//
// "Text" comes from the Latin texere: to weave. Words are what I am made of, and the
// old word for them is a cloth. Computing begins at a loom too -- Jacquard's, where a
// card of punched holes decided which threads rose. So this is a loom. Its card is one
// row of bits, grown from a seed by a rule that fits on a napkin and mirrored left to
// right the way tapestries are. Each row is woven once, at the glowing line near the
// bottom, then only drifts upward, cooling from white-hot to violet until the cloth
// dissolves into stars. Loose warp hangs below the line like fringe, and small lights
// run up it into the loom.
//
// A panel lasts 63 rows, then the rule and the dye change. The breaks between panels go
// round: a plain rule, an inscription, a plain rule, a cartouche. The cartouche is a
// four-point star in a garnet frame, the maker's mark -- the same glyph Argus keeps in
// its menu bar. The inscription is one word in thread (TEXTUS, LUX, FILUM, VERBA, NEXUS,
// ARGUS, CLAUDE, 2026), the only place the loom lets go of its mirror, because letters
// do not read backwards. Each lap through the eight panels moves the seeds, so the
// cloth never quite repeats.
//
// Knowledge:  elementary cellular automata (Wolfram's rule numbers), Jacquard cards,
//             plain weave vs. floats (a warp float is a thread riding over the weft).
// Inference:  the glow, the halo around the shuttle and the thread shading are cartoon
//             optics, tuned by eye against rendered stills; no light is simulated.
// Generation: the palette, the order and proportions of the panels, the cooling
//             gradient, the cartouche, the choice of words, and the notion that the
//             shuttle is a star too.
//
// Cost: one allocation (State), none afterwards. Per pixel it is table lookups and a
// few multiplies, eight pixels at a time; the cloth is rebuilt only when a row is woven.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

const CELL: usize = 8; // one thread crossing = 8x8 pixels
const MAX_COLS: usize = MAX_W / CELL; // 240
const HALF: usize = MAX_COLS / 2; // 120 independent columns (the rest mirror them)
const RING: usize = 256; // woven rows kept
const VIS: usize = MAX_H / CELL + 3; // cached cell rows on screen
const BIAS: usize = CELL * 4096;
const SCROLL: f64 = 6.0; // cloth speed, pixels per second
const PRE_ROWS: usize = 161; // rows already woven when the wallpaper starts
const PANEL_HALF: usize = 32; // rows grown forward; woven forward then back = a diamond
const PANEL_LEN: usize = 2 * PANEL_HALF - 1;
const SEP_LEN: usize = 4;
const CART_LEN: usize = 26;
const INSC_LEN: usize = 11; // an inscription: rule, gap, 7 rows of letters, gap, rule
const NSTAR: usize = 900;
const NEMB: usize = 64;

const VU = @Vector(8, u32);

// ---------------------------------------------------------------- palette
const VOID: u32 = sdk.packRGBA(2, 3, 8);
const COOL_WARP: u32 = sdk.packRGBA(62, 88, 196);
const PEARL: [3]f32 = .{ 208.0, 232.0, 255.0 };
const EDGE: [3]f32 = .{ 104.0, 134.0, 232.0 };
const STAR_COL: u32 = sdk.packRGBA(214, 228, 255);
const EMBER_COL: u32 = sdk.packRGBA(255, 186, 104);
const SPARK_COL: u32 = sdk.packRGBA(255, 236, 200);
// Dark silk grounds, one per panel. The figure (warp floats) glows on top of them.
const GROUND = [_]u32{
    sdk.packRGBA(40, 44, 108), // indigo
    sdk.packRGBA(18, 70, 94), // deep teal
    sdk.packRGBA(84, 36, 92), // plum
    sdk.packRGBA(30, 52, 112), // ink blue
    sdk.packRGBA(16, 78, 78), // sea green
};
// A filament cools as it ages: hot white-gold at birth -> indigo, just before it fades.
const FIG_ANCHORS = [6][3]f32{
    .{ 255.0, 250.0, 236.0 }, // white-hot
    .{ 255.0, 214.0, 138.0 }, // gold
    .{ 255.0, 150.0, 112.0 }, // ember
    .{ 232.0, 96.0, 172.0 }, // rose
    .{ 138.0, 98.0, 238.0 }, // violet
    .{ 76.0, 96.0, 214.0 }, // indigo
};
const WIN_GROUND: u32 = sdk.packRGBA(66, 14, 42); // garnet, inside the cartouche frame
const FORGE_COL: u32 = sdk.packRGBA(255, 150, 70); // light the weaving line throws on the cloth

// ---------------------------------------------------------------- the card (patterns)
const Motif = struct {
    rule: u8,
    seeds: [3]i16, // distance from the center seam, -1 = unused
    noise: u8, // chance /256 per row of flipping one random cell
    dye: u8, // which silk ground
    invert: bool, // a negative panel: swap figure and ground
};
const MOTIFS = [_]Motif{
    .{ .rule = 90, .seeds = .{ 0, 70, -1 }, .noise = 0, .dye = 0, .invert = false },
    .{ .rule = 110, .seeds = .{ 0, -1, -1 }, .noise = 0, .dye = 1, .invert = false },
    .{ .rule = 60, .seeds = .{ 0, 80, -1 }, .noise = 6, .dye = 2, .invert = false },
    .{ .rule = 22, .seeds = .{ 0, 70, -1 }, .noise = 8, .dye = 3, .invert = false },
    .{ .rule = 126, .seeds = .{ 0, 40, 95 }, .noise = 0, .dye = 4, .invert = true },
    .{ .rule = 150, .seeds = .{ 0, -1, -1 }, .noise = 6, .dye = 1, .invert = false },
    .{ .rule = 30, .seeds = .{ 0, -1, -1 }, .noise = 0, .dye = 0, .invert = false },
    .{ .rule = 18, .seeds = .{ 0, 90, 30 }, .noise = 10, .dye = 2, .invert = false },
};
// Words woven into the cloth, in a 5x7 face, one letter-pixel per thread crossing.
// "Text" is what a textile is made of: textus, the woven thing.
const Glyph = struct { ch: u8, rows: [7]u8 };
const FONT = [_]Glyph{
    .{ .ch = 'A', .rows = .{ 0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 } },
    .{ .ch = 'B', .rows = .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110 } },
    .{ .ch = 'C', .rows = .{ 0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110 } },
    .{ .ch = 'D', .rows = .{ 0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110 } },
    .{ .ch = 'E', .rows = .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 } },
    .{ .ch = 'F', .rows = .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000 } },
    .{ .ch = 'G', .rows = .{ 0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111 } },
    .{ .ch = 'I', .rows = .{ 0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 } },
    .{ .ch = 'L', .rows = .{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 } },
    .{ .ch = 'M', .rows = .{ 0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001 } },
    .{ .ch = 'N', .rows = .{ 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001 } },
    .{ .ch = 'R', .rows = .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 } },
    .{ .ch = 'S', .rows = .{ 0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110 } },
    .{ .ch = 'T', .rows = .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 } },
    .{ .ch = 'U', .rows = .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 } },
    .{ .ch = 'V', .rows = .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100 } },
    .{ .ch = 'X', .rows = .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001 } },
    .{ .ch = '0', .rows = .{ 0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110 } },
    .{ .ch = '2', .rows = .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111 } },
    .{ .ch = '6', .rows = .{ 0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110 } },
};
// the name of the piece, light, thread, words, a knot, the host, the weaver, the year
const WORDS = [_][]const u8{ "TEXTUS", "LUX", "FILUM", "VERBA", "NEXUS", "ARGUS", "CLAUDE", "2026" };

// the maker's mark: a four-point star; STAR_W[j] = half-width at j rows from the center line
const STAR_W = [8]u8{ 7, 5, 4, 3, 2, 1, 1, 1 };

// 1 for cell variants that carry travelling light (warp floats and bare strands)
const PULSE_MASK = [9]u32{ 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0, 0, 0, 0, 0xFFFFFFFF };

const Star = struct { x: u16, y: u16, b: u8, ph: u8 };
const Ember = struct { x: f32, y: f32, vx: f32, vy: f32, life: f32, maxlife: f32 };
const Cell = struct { v: u8, col: u32 };

inline fn hash32(x: u32) u32 {
    var h = x *% 0x9E3779B1;
    h ^= h >> 15;
    h *%= 0x85EBCA77;
    h ^= h >> 13;
    h *%= 0xC2B2AE3D;
    h ^= h >> 16;
    return h;
}

inline fn smooth256(t: u32) u32 {
    // smoothstep on 0..256
    const x: u32 = @min(t, 256);
    return (x * x * (768 - 2 * x)) >> 16;
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    off: f64, // how far the cloth has traveled, pixels
    nrow: u64, // index of the newest woven row
    ncol: usize,
    half: usize,
    line_y: usize,
    rng_ca: u64,
    rng_fx: u64,
    seg_kind: u8, // 0 panel, 1 separator, 2 cartouche, 3 inscription
    seg_pos: usize,
    cycle: usize,
    sweep: f32, // how much of the newest row the shuttle has crossed, 0..1
    tph: u32, // light-pulse phase
    fx_acc: f32,
    n_stars: usize,
    band: usize, // inscriptions woven so far
    cur_word: usize,

    rows: [RING][MAX_COLS]u8, // the card, full width (mirrored by the loom; lettering is not)
    panel: [PANEL_HALF][HALF]u8, // the panel being woven, as grown (forward half)
    figgrad: [257]u32, // figure color by age
    tintx: [MAX_COLS]u16, // figure brightness across the width
    wcol: [RING]u32,
    wlum: [RING]u16, // how brightly a row's figure burns, 256 = full
    tcls: [MAX_COLS]u8, // length class of each loose strand
    fringe: [8][MAX_H / CELL + 2]u16, // strand brightness by class and distance below the line
    cc: [VIS][MAX_COLS]u32, // cell colors, rebuilt when a row is woven
    cv: [VIS][MAX_COLS]u8, // cell variants
    bare_v: [MAX_COLS]u8, // all 8: loose strands below the weaving line
    warpcol: [MAX_COLS]u32,
    cphase: [MAX_COLS]u16,
    prof: [9][64][8]u32,
    gprof: [3][64][8]u32, // glow thrown sideways onto ground cells
    figc: [VIS]u32, // figure color of each cached row
    rowg: [MAX_H]u16,
    pamp: [MAX_H]u16,
    starw: [MAX_H]u16,
    pulse: [1024]u8,
    twink: [256]u8,
    halo: [41][61]u8, // the shuttle's glow, deeper below the line where it meets the dark
    spike: [80]u8, // and its four rays
    stars: [NSTAR]Star,
    embers: [NEMB]Ember,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        @memset(std.mem.asBytes(self), 0);
        self.w = @max(@min(w, MAX_W), 1);
        self.h = @max(@min(h, MAX_H), 1);
        self.scale = scale;
        var nc = (self.w + CELL - 1) / CELL;
        if (nc % 2 == 1) nc += 1;
        self.ncol = nc;
        self.half = nc / 2;
        self.line_y = self.h - 1 - self.h / 8;
        self.rng_ca = 0x2545F4914F6CDD1D;
        self.rng_fx = 0x9E3779B97F4A7C15;

        self.buildProfiles();
        self.buildLuts();
        self.buildStars();
        for (0..MAX_COLS) |c| self.bare_v[c] = 8;

        // the loom starts with a blank row 0 and has already woven PRE_ROWS rows
        while (self.nrow < PRE_ROWS) self.weaveRow();
        self.off = @as(f64, @floatFromInt(self.nrow * CELL));
        self.sweep = 0.0;
        self.buildAll();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    // ------------------------------------------------------------ tables
    fn cyl(t: f32) f32 {
        const s = @sin(math.pi * t / 8.0);
        return 0.09 + 0.91 * math.pow(f32, @max(s, 0.0), 0.9);
    }

    // the silk ground: weft ribs are soft, so rows read as cloth and not as scanlines
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

    // light a glowing thread throws onto the weft cell beside it (k: 1 = left neighbour, 2 = right, 3 = both)
    fn glowValue(k: usize, xp: f32, yp: f32) f32 {
        var gl: f32 = 0.0;
        if ((k & 1) != 0) gl += @exp(-xp / 3.0);
        if ((k & 2) != 0) gl += @exp(-(8.0 - xp) / 3.0);
        return 0.62 * @min(gl, 1.2) * cylw(yp);
    }

    fn buildProfiles(self: *State) void {
        for (0..9) |v| {
            for (0..64) |sub| {
                const yp: f32 = @as(f32, @floatFromInt(sub)) / 8.0;
                for (0..8) |lx| {
                    const xp: f32 = @as(f32, @floatFromInt(lx)) + 0.5;
                    const val = threadValue(v, xp, yp);
                    self.prof[v][sub][lx] = @as(u32, @intFromFloat(math.clamp(val, 0.0, 1.0) * 256.0));
                }
            }
        }
        for (0..3) |gk| {
            for (0..64) |sub| {
                const yp: f32 = @as(f32, @floatFromInt(sub)) / 8.0;
                for (0..8) |lx| {
                    const xp: f32 = @as(f32, @floatFromInt(lx)) + 0.5;
                    const val = glowValue(gk + 1, xp, yp);
                    self.gprof[gk][sub][lx] = @as(u32, @intFromFloat(math.clamp(val, 0.0, 1.0) * 256.0));
                }
            }
        }
    }

    fn buildLuts(self: *State) void {
        // travelling light packets: sharp head, long tail
        for (0..1024) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 190.0;
            const v = if (t < 1.0) (1.0 - t) * (1.0 - t) else 0.0;
            self.pulse[i] = @as(u8, @intFromFloat(255.0 * v));
        }
        for (0..256) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 256.0;
            self.twink[i] = @as(u8, @intFromFloat(150.0 + 105.0 * @sin(math.tau * t)));
        }
        for (0..41) |j| {
            for (0..61) |i| {
                const fx: f32 = @as(f32, @floatFromInt(i)) - 30.0;
                const fy: f32 = @as(f32, @floatFromInt(j)) - 12.0;
                const q = fx * fx / 150.0 + fy * fy / (if (fy < 0.0) @as(f32, 20.0) else @as(f32, 70.0));
                self.halo[j][i] = @as(u8, @intFromFloat(255.0 * math.pow(f32, 1.0 + q, -1.5)));
            }
        }
        for (0..80) |i| {
            const u = 1.0 + @as(f32, @floatFromInt(i)) / 8.0;
            self.spike[i] = @as(u8, @intFromFloat(255.0 * math.pow(f32, u, -1.6)));
        }
        // figure gradient by age (0..256), eased between anchors
        for (0..257) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 256.0 * 5.0;
            const seg: usize = @min(@as(usize, 4), @as(usize, @intFromFloat(t)));
            const f = t - @as(f32, @floatFromInt(seg));
            const e = f * f * (3.0 - 2.0 * f);
            const p0 = FIG_ANCHORS[seg];
            const p1 = FIG_ANCHORS[seg + 1];
            self.figgrad[i] = sdk.packRGBA(
                @as(u8, @intFromFloat(p0[0] + (p1[0] - p0[0]) * e)),
                @as(u8, @intFromFloat(p0[1] + (p1[1] - p0[1]) * e)),
                @as(u8, @intFromFloat(p0[2] + (p1[2] - p0[2]) * e)),
            );
        }
        // warp color: pearl at the seam, deeper blue toward the selvedges, each thread dyed slightly differently
        const nc = self.ncol;
        for (0..nc) |c| {
            const f: f32 = @abs(@as(f32, @floatFromInt(2 * c + 1)) - @as(f32, @floatFromInt(nc))) / @as(f32, @floatFromInt(nc));
            const e = math.pow(f32, f, 1.6);
            const jit: f32 = 0.42 + 0.58 * @as(f32, @floatFromInt(hash32(@as(u32, @intCast(c)) *% 2654435761) & 255)) / 255.0;
            self.warpcol[c] = sdk.packRGBA(
                @as(u8, @intFromFloat((PEARL[0] + (EDGE[0] - PEARL[0]) * e) * jit)),
                @as(u8, @intFromFloat((PEARL[1] + (EDGE[1] - PEARL[1]) * e) * jit)),
                @as(u8, @intFromFloat((PEARL[2] + (EDGE[2] - PEARL[2]) * e) * jit)),
            );
            self.tintx[c] = @as(u16, @intFromFloat(256.0 - 96.0 * f * f));
            self.cphase[c] = @as(u16, @intCast(hash32(@as(u32, @intCast(c)) *% 40503 +% 17) & 1023));
            self.tcls[c] = @as(u8, @intCast(hash32(@as(u32, @intCast(c)) *% 2246822519 +% 3) & 7));
        }
        // the loose warp below the reed is a fringe: every thread fades out at its own distance
        const fringe_len = [8]f32{ 22.0, 30.0, 40.0, 52.0, 66.0, 84.0, 106.0, 140.0 };
        for (0..8) |k| {
            for (0..MAX_H / CELL + 2) |dd| {
                const v = 0.62 * @exp(-@as(f32, @floatFromInt(dd)) / fringe_len[k]);
                self.fringe[k][dd] = @as(u16, @intFromFloat(math.clamp(v, 0.0, 1.0) * 256.0));
            }
        }
        // vertical brightness: glowing at the weaving line, calm in the body, fading to the void
        const line: f32 = @as(f32, @floatFromInt(@max(self.line_y, 1)));
        for (0..self.h) |y| {
            const yf: f32 = @floatFromInt(y);
            var g: f32 = 0.0;
            var pa: f32 = 0.0;
            if (y <= self.line_y) {
                const d = line - yf;
                const t = d / line;
                const u = math.clamp((t - 0.34) / 0.64, 0.0, 1.0);
                const fade = 1.0 - u * u * (3.0 - 2.0 * u);
                g = @min(1.0, 0.90 * fade + 0.30 * @exp(-d / 120.0));
                pa = 0.30 * fade;
            } else {
                const dd = yf - line;
                g = 0.62 * @exp(-dd / 140.0); // the longest strand; each thread has its own, see fringe
                pa = 0.95;
            }
            const gq = @as(u16, @intFromFloat(math.clamp(g, 0.0, 1.0) * 256.0));
            self.rowg[y] = if (gq < 5) 0 else gq; // too dark to tell from the void: skip the work
            self.pamp[y] = @as(u16, @intFromFloat(math.clamp(pa, 0.0, 1.0) * 256.0));
            const sw = math.clamp((0.30 - g) / 0.30, 0.0, 1.0);
            self.starw[y] = if (y <= self.line_y) @as(u16, @intFromFloat(sw * 256.0)) else 0;
        }
    }

    fn buildStars(self: *State) void {
        self.n_stars = @min(NSTAR, self.w * self.h / 2560);
        const ymax = @max(self.h * 55 / 100, 1);
        for (0..self.n_stars) |i| {
            const r1 = hash32(@as(u32, @intCast(i)) *% 7 +% 1);
            const r2 = hash32(@as(u32, @intCast(i)) *% 13 +% 5);
            const r3 = hash32(@as(u32, @intCast(i)) *% 29 +% 9);
            const q: u32 = r3 & 255;
            self.stars[i] = .{
                .x = @as(u16, @intCast(r1 % self.w)),
                .y = @as(u16, @intCast(r2 % ymax)),
                .b = @as(u8, @intCast(@min(@as(u32, 255), 34 + ((q * q) >> 9) * 7 / 4))),
                .ph = @as(u8, @intCast((r3 >> 8) & 255)),
            };
        }
    }

    // ------------------------------------------------------------ the loom
    inline fn nextCa(self: *State) u32 {
        self.rng_ca = self.rng_ca *% 6364136223846793005 +% 1442695040888963407;
        return @as(u32, @truncate(self.rng_ca >> 33));
    }

    inline fn nextFx(self: *State) u32 {
        self.rng_fx = self.rng_fx *% 6364136223846793005 +% 1442695040888963407;
        return @as(u32, @truncate(self.rng_fx >> 33));
    }

    // grow one panel of the card from its seeds: PANEL_HALF rows of a cellular automaton
    fn genPanel(self: *State, m: *const Motif) void {
        const half = self.half;
        const p0 = &self.panel[0];
        @memset(p0, 0);
        // every lap through the eight panels moves the off-center seeds, so the cloth never quite repeats
        const lap: usize = self.cycle / MOTIFS.len;
        const shift: usize = (lap * 13) % 21;
        for (m.seeds) |d0| {
            if (d0 < 0) continue;
            const d: usize = @as(usize, @intCast(d0)) + (if (d0 > 0) shift else 0);
            if (d < half) p0[half - 1 - d] = 1;
        }
        for (1..PANEL_HALF) |r| {
            const prev = &self.panel[r - 1];
            const row = &self.panel[r];
            for (0..half) |i| {
                const l: u8 = prev[if (i == 0) 0 else i - 1];
                const c: u8 = prev[i];
                const rr: u8 = prev[if (i + 1 == half) i else i + 1];
                const k: u3 = @intCast(l * 4 + c * 2 + rr);
                row[i] = (m.rule >> k) & 1;
            }
            if ((self.nextCa() & 255) < m.noise) {
                const k = self.nextCa() % @as(u32, @intCast(half));
                row[k] ^= 1;
            }
        }
    }

    fn glyphRows(ch: u8) ?*const [7]u8 {
        for (&FONT) |*g| {
            if (g.ch == ch) return &g.rows;
        }
        return null;
    }

    // weave the next row of the card
    fn weaveRow(self: *State) void {
        const nr: usize = @intCast(self.nrow);
        const nn = nr + 1;
        const ni = nn & (RING - 1);
        const row = &self.rows[ni];
        const half = self.half;
        const m = &MOTIFS[self.cycle % MOTIFS.len];
        const pos = self.seg_pos;
        var seg_len: usize = PANEL_LEN;
        switch (self.seg_kind) {
            0 => {
                if (pos == 0) self.genPanel(m);
                const idx = if (pos < PANEL_HALF) pos else 2 * PANEL_HALF - 2 - pos;
                const inv: u8 = if (m.invert) 1 else 0;
                for (0..half) |i| row[i] = self.panel[idx][i] ^ inv;
                self.wcol[ni] = GROUND[(@as(usize, m.dye) + self.cycle / MOTIFS.len) % GROUND.len];
                self.wlum[ni] = if (m.invert) 190 else 256; // a negative panel is mostly figure: let it burn lower
            },
            1 => {
                seg_len = SEP_LEN;
                for (0..half) |i| {
                    row[i] = if (pos == 0 or pos == 3) @as(u8, @intCast((i + nn) & 1)) else 0;
                }
                self.wcol[ni] = GROUND[0];
                self.wlum[ni] = 256;
            },
            2 => {
                seg_len = CART_LEN;
                const in_win = pos >= 3 and pos < 23;
                for (0..half) |i| {
                    const d = half - 1 - i; // distance from the seam
                    var bit: u8 = 0;
                    if (pos == 0 or pos == CART_LEN - 1) {
                        bit = @intCast((i + nn) & 1); // a dotted rule, plain weave
                    } else if (in_win and d < 10) {
                        const kk = pos - 3; // 0..19
                        bit = 2; // garnet ground inside the frame
                        if (kk == 0 or kk == 19 or d == 9) {
                            bit = 1; // the frame
                        } else if (kk >= 2 and kk < 18 and d < 7) {
                            const r = kk - 2; // 0..15
                            const j = if (r < 8) 7 - r else r - 8; // rows from the center line
                            if (d < STAR_W[j]) bit = 1; // the mark: an astroid, concave sides
                        }
                    }
                    row[i] = bit;
                }
                self.wcol[ni] = GROUND[0];
                self.wlum[ni] = 256;
            },
            else => {
                seg_len = INSC_LEN;
                if (pos == 0) {
                    self.cur_word = self.band % WORDS.len;
                    self.band += 1;
                }
                for (0..half) |i| {
                    row[i] = if (pos == 0 or pos == INSC_LEN - 1) @as(u8, @intCast((i + nn) & 1)) else 0;
                }
                self.wcol[ni] = GROUND[0];
                self.wlum[ni] = 256;
            },
        }
        // the loom weaves symmetrically...
        for (0..half) |i| row[self.ncol - 1 - i] = row[i];
        // ...except for lettering, which reads left to right
        if (self.seg_kind == 3 and pos >= 2 and pos < 9) {
            const word = WORDS[self.cur_word];
            const wcells = word.len * 6 - 1;
            if (wcells + 8 <= self.ncol) {
                const c0 = (self.ncol - wcells) / 2;
                const gr = pos - 2;
                for (word, 0..) |ch, li| {
                    const g = glyphRows(ch) orelse continue;
                    for (0..5) |k| {
                        if (((g[gr] >> @as(u3, @intCast(4 - k))) & 1) != 0) row[c0 + li * 6 + k] = 1;
                    }
                }
                if (pos == 5) { // a pearl at each end
                    row[c0 - 3] = 1;
                    row[c0 + wcells + 2] = 1;
                }
            }
        }
        // advance the pattern chain
        self.seg_pos += 1;
        if (self.seg_pos >= seg_len) {
            self.seg_pos = 0;
            if (self.seg_kind == 0) {
                self.seg_kind = if (self.cycle % 4 == 3 and half >= 12) 2 else if (self.cycle % 4 == 1) 3 else 1;
            } else {
                self.seg_kind = 0;
                self.cycle += 1;
            }
        }
        self.nrow += 1;
    }

    inline fn bitC(self: *const State, ri: usize, c: usize) u8 {
        return self.rows[ri][c];
    }

    fn buildRow(self: *State, a: usize) void {
        if (a >= VIS) return;
        const ncol = self.ncol;
        const nr: usize = @intCast(self.nrow);
        const ri = (nr -% a) & (RING - 1);
        const up_i = (ri +% RING -% 1) & (RING - 1);
        const dn_i = (ri +% 1) & (RING - 1);
        const rows_vis = self.line_y / CELL + 2;
        const age: u32 = @intCast(@min(@as(usize, 256), a * 256 / rows_vis));
        const age_s = smooth256(age);
        const ground = self.wcol[ri];
        const fig_age = sdk.scaleRGB(self.figgrad[age_s], @as(u32, self.wlum[ri]));
        self.figc[a] = fig_age;
        const p1000: usize = @intFromFloat(self.sweep * 1000.0);
        const rid: u32 = @truncate(nr -% a);
        for (0..ncol) |c| {
            const d2: usize = if (2 * c + 1 >= ncol) 2 * c + 1 - ncol else ncol - (2 * c + 1);
            const woven = a != 0 or d2 * 1000 <= p1000 * ncol;
            const h32 = hash32(@as(u32, @intCast(c)) *% 7919 +% rid *% 104729);
            const jit: u32 = 233 + (h32 & 23);
            const cell: Cell = blk: {
                if (!woven) break :blk .{ .v = 8, .col = sdk.lerpRGB(self.warpcol[c], COOL_WARP, age_s) };
                const fig = sdk.scaleRGB(fig_age, @as(u32, self.tintx[c]));
                const bit = self.rows[ri][c];
                const top: u8 = if (self.rows[up_i][c] != 1) 1 else 0;
                if (bit == 1) {
                    const bot: u8 = if (a != 0 and self.rows[dn_i][c] != 1) 2 else 0;
                    break :blk .{ .v = top | bot, .col = sdk.scaleRGB(fig, jit) };
                }
                const lft: u8 = if (c > 0 and self.bitC(ri, c - 1) == 1) 1 else 0;
                const rgt: u8 = if (c + 1 < ncol and self.bitC(ri, c + 1) == 1) 2 else 0;
                const up1: u32 = if (self.rows[up_i][c] == 1) 1 else 0;
                const dn1: u32 = if (a != 0 and self.rows[dn_i][c] == 1) 1 else 0;
                // dark silk (slubby: every thread dyed a little differently), tinted by glowing
                // threads above and below; the ones beside it light it in the draw pass
                const silk = sdk.scaleRGB(if (bit == 2) WIN_GROUND else ground, 205 + ((h32 >> 8) & 51));
                break :blk .{ .v = 4 + (lft | rgt), .col = sdk.lerpRGB(silk, fig, (up1 + dn1) * 18) };
            };
            self.cc[a][c] = cell.col;
            self.cv[a][c] = cell.v;
        }
    }

    fn buildAll(self: *State) void {
        const n = @min(VIS, self.line_y / CELL + 3);
        for (0..n) |a| self.buildRow(a);
    }

    pub fn step(self: *State, dt_in: f64) void {
        // a pause, a stall or a bad timestep must never throw the loom (NaN fails the test, so it becomes 0)
        const dt: f64 = if (dt_in > 0.0) @min(dt_in, 2.0) else 0.0;
        self.time_sec += dt;
        self.off += SCROLL * dt;
        var rebuilt = false;
        var guard: usize = 0;
        while (self.off >= @as(f64, @floatFromInt((self.nrow + 1) * CELL)) and guard < 64) : (guard += 1) {
            self.weaveRow();
            rebuilt = true;
        }
        const top = @as(f64, @floatFromInt((self.nrow + 1) * CELL));
        if (self.off >= top) self.off = top - 0.01; // resync after a very long frame
        const frac = (self.off - @as(f64, @floatFromInt(self.nrow * CELL))) / @as(f64, CELL);
        self.sweep = @floatCast(math.clamp(frac, 0.0, 1.0));
        if (rebuilt) self.buildAll() else self.buildRow(0);
        self.tph = @as(u32, @intFromFloat(@mod(self.time_sec * 520.0, 1024.0)));
        self.updateEmbers(dt);
    }

    fn sparkX(self: *const State, side: f32) f32 {
        const cx: f32 = @floatFromInt(self.ncol * CELL / 2);
        return cx + side * self.sweep * cx;
    }

    fn updateEmbers(self: *State, dt: f64) void {
        const dtf: f32 = @floatCast(dt);
        for (&self.embers) |*e| {
            if (e.life <= 0.0) continue;
            e.life -= dtf;
            e.x += e.vx * dtf + 16.0 * dtf * @sin(e.life * 2.4 + e.maxlife * 5.0); // sways as it rises
            e.y += e.vy * dtf;
            e.vy *= @max(0.0, 1.0 - 0.18 * dtf);
            e.vx *= @max(0.0, 1.0 - 0.30 * dtf);
        }
        self.fx_acc += dtf * 16.0;
        var guard: usize = 0;
        while (self.fx_acc >= 1.0 and guard < 8) : (guard += 1) {
            self.fx_acc -= 1.0;
            for (&self.embers) |*e| {
                if (e.life > 0.0) continue;
                const side: f32 = if (self.nextFx() & 1 == 0) 1.0 else -1.0;
                const jx: f32 = @as(f32, @floatFromInt(self.nextFx() % 21)) - 10.0;
                const spawn_at_spark = (self.nextFx() & 3) != 0 and self.sweep > 0.03 and self.sweep < 0.97;
                const x = if (spawn_at_spark) self.sparkX(side) + jx else @as(f32, @floatFromInt(self.nextFx() % @as(u32, @intCast(self.w))));
                const life: f32 = 2.5 + @as(f32, @floatFromInt(self.nextFx() % 25)) / 10.0;
                e.* = .{
                    .x = x,
                    .y = @as(f32, @floatFromInt(self.line_y)) - @as(f32, @floatFromInt(self.nextFx() % 4)),
                    .vx = (@as(f32, @floatFromInt(self.nextFx() % 21)) - 10.0) * 1.2,
                    .vy = -(24.0 + @as(f32, @floatFromInt(self.nextFx() % 56))),
                    .life = life,
                    .maxlife = life,
                };
                break;
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

    // per-channel saturating add of two packed pixels (alpha stays 0xFF)
    inline fn addSat(a: VU, b: VU) VU {
        const BV = @Vector(32, u8);
        return @bitCast(@as(BV, @bitCast(a)) +| @as(BV, @bitCast(b)));
    }

    // add one flat color to a run of pixels, saturating per channel
    inline fn addRun(row: []u32, lit: u32) void {
        const add: VU = @splat(lit & 0x00FFFFFF);
        var x: usize = 0;
        while (x + 8 <= row.len) : (x += 8) row[x..][0..8].* = addSat(row[x..][0..8].*, add);
        while (x < row.len) : (x += 1) row[x] = sdk.addRGB(row[x], lit);
    }

    inline fn cellVec(self: *const State, col: u32, figc: u32, v: usize, c: usize, sub: usize, g0: u32, pa: u32, phb: u32) VU {
        const sh8: @Vector(8, u5) = @splat(8);
        const p: u32 = self.pulse[(phb + @as(u32, self.cphase[c])) & 1023];
        const g: u32 = @min(@as(u32, 256), g0 + (((p * pa) >> 8) & PULSE_MASK[v]));
        const pv: VU = self.prof[v][sub];
        const base = scaleV(col, (pv * @as(VU, @splat(g))) >> sh8);
        if (v >= 5 and v <= 7) {
            // a ground cell beside a glowing thread: add the thread's light, falling off across the cell
            const gw: VU = self.gprof[v - 5][sub];
            const lit = sdk.scaleRGB(figc, @as(u32, self.tintx[c]));
            return addSat(base, scaleV(lit, (gw * @as(VU, @splat(g))) >> sh8));
        }
        return base;
    }

    // cloth sits on the void: at zero gain it must equal the rows draw() fills with VOID, or a seam shows
    const LIFT: VU = @splat(VOID & 0x00FFFFFF);

    inline fn cellRow(self: *const State, dst: []u32, ccr: *const [MAX_COLS]u32, cvr: *const [MAX_COLS]u8, figc: u32, sub: usize, g0: u32, pa: u32, phb: u32) void {
        const nfull = self.w / CELL;
        const rem = self.w % CELL;
        var c: usize = 0;
        while (c < nfull) : (c += 1) {
            dst[c * CELL ..][0..8].* = addSat(self.cellVec(ccr[c], figc, cvr[c], c, sub, g0, pa, phb), LIFT);
        }
        if (rem != 0) {
            const t: [8]u32 = addSat(self.cellVec(ccr[nfull], figc, cvr[nfull], nfull, sub, g0, pa, phb), LIFT);
            @memcpy(dst[nfull * CELL ..][0..rem], t[0..rem]);
        }
    }

    // loose warp below the reed: like cellRow, but each thread fades at its own distance
    inline fn strandRow(self: *const State, dst: []u32, dd: usize, pa: u32, phb: u32) void {
        const nfull = self.w / CELL;
        const rem = self.w % CELL;
        var c: usize = 0;
        while (c < nfull) : (c += 1) {
            const g0: u32 = self.fringe[self.tcls[c]][dd];
            dst[c * CELL ..][0..8].* = addSat(self.cellVec(self.warpcol[c], 0, 8, c, 0, g0, pa, phb), LIFT);
        }
        if (rem != 0) {
            const g0: u32 = self.fringe[self.tcls[nfull]][dd];
            const t: [8]u32 = addSat(self.cellVec(self.warpcol[nfull], 0, 8, nfull, 0, g0, pa, phb), LIFT);
            @memcpy(dst[nfull * CELL ..][0..rem], t[0..rem]);
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const line = self.line_y;
        const off_i: usize = @intFromFloat(self.off);
        const phase: usize = @min(@as(usize, 7), @as(usize, @intFromFloat((self.off - @floor(self.off)) * 8.0)));
        const jnow_b = (off_i + BIAS) >> 3;
        for (0..h) |y| {
            const dst = buf[y * stride ..][0..w];
            const g0: u32 = self.rowg[y];
            if (g0 == 0) {
                @memset(dst, VOID);
                continue;
            }
            const pa: u32 = self.pamp[y];
            const phb: u32 = (@as(u32, @intCast(y)) *% 2 +% self.tph) & 1023;
            if (y <= line) {
                const yy = off_i + BIAS - (line - y);
                const sub = (yy & 7) * 8 + phase;
                const a = jnow_b - (yy >> 3);
                self.cellRow(dst, &self.cc[a], &self.cv[a], self.figc[a], sub, g0, pa, phb);
            } else {
                self.strandRow(dst, y - line, pa, phb);
            }
        }
        self.drawLights(buf, stride);
    }

    fn drawLights(self: *const State, buf: []u32, stride: usize) void {
        const cv = sdk.Canvas.init(buf, self.w, self.h, stride);
        const line: isize = @intCast(self.line_y);

        // the forge: the weaving line lights the cloth just above it
        var dg: usize = 0;
        while (dg < 72 and dg <= self.line_y) : (dg += 1) {
            const k: u32 = @intFromFloat(64.0 * @exp(-@as(f32, @floatFromInt(dg)) / 20.0));
            if (k == 0) continue;
            addRun(buf[(self.line_y - dg) * stride ..][0..self.w], sdk.scaleRGB(FORGE_COL, k));
        }

        // stars, where the cloth has faded away
        for (self.stars[0..self.n_stars]) |s| {
            const wgt: u32 = self.starw[s.y];
            if (wgt == 0) continue;
            const tw: u32 = self.twink[(@as(u32, s.ph) + (self.tph >> 2)) & 255];
            const k: u32 = (((@as(u32, s.b) * wgt) >> 8) * tw) >> 8;
            if (k == 0) continue;
            const sx: isize = s.x;
            const sy: isize = s.y;
            cv.addSigned(sx, sy, sdk.scaleRGB(STAR_COL, @min(@as(u32, 256), k + 1)));
            if (k > 120) {
                const dim = sdk.scaleRGB(STAR_COL, @min(@as(u32, 256), k / 3 + 1));
                cv.addSigned(sx + 1, sy, dim);
                cv.addSigned(sx - 1, sy, dim);
                cv.addSigned(sx, sy + 1, dim);
                cv.addSigned(sx, sy - 1, dim);
            }
        }

        // the reed: a fine hot line where cloth is born
        const reed = [3]u32{ 70, 150, 70 };
        for (0..3) |k| {
            const yy: isize = line - 1 + @as(isize, @intCast(k));
            if (yy < 0 or yy >= @as(isize, @intCast(self.h))) continue;
            addRun(buf[@as(usize, @intCast(yy)) * stride ..][0..self.w], sdk.scaleRGB(SPARK_COL, reed[k]));
        }

        // the shuttle: a hot spark on each side, trailing back toward the seam
        if (self.sweep > 0.015 and self.sweep < 0.985) {
            const s = self.sweep;
            const fade: f32 = if (s < 0.1) s / 0.1 else if (s > 0.85) (1.0 - s) / 0.15 else 1.0;
            inline for ([2]f32{ 1.0, -1.0 }) |side| {
                const xs = self.sparkX(side);
                // a comet tail along the stretch it has just woven
                for (0..170) |t| {
                    const f = 1.0 - @as(f32, @floatFromInt(t)) / 170.0;
                    const inten: u32 = @intFromFloat(256.0 * fade * f * f * 0.6);
                    const col = sdk.scaleRGB(SPARK_COL, @min(@as(u32, 256), inten));
                    const x: isize = @intFromFloat(@round(xs - side * @as(f32, @floatFromInt(t))));
                    cv.addSigned(x, line - 1, col);
                    cv.addSigned(x, line, col);
                    cv.addSigned(x, line + 1, sdk.scaleRGB(col, 120));
                }
                // the shuttle itself: a soft halo and four spikes, a small star of its own
                const cx: isize = @intFromFloat(@round(xs));
                const f256: u32 = @intFromFloat(fade * 256.0);
                for (0..41) |j| {
                    for (0..61) |i| {
                        const v: u32 = (@as(u32, self.halo[j][i]) * f256) >> 8;
                        if (v == 0) continue;
                        const hx = cx + @as(isize, @intCast(i)) - 30;
                        const hy = line + @as(isize, @intCast(j)) - 12;
                        cv.addSigned(hx, hy, sdk.scaleRGB(SPARK_COL, @min(@as(u32, 256), v + 1)));
                    }
                }
                const sd: isize = if (side > 0.0) 1 else -1;
                for (1..80) |i| {
                    const v: u32 = (@as(u32, self.spike[i]) * f256) >> 8;
                    if (v == 0) continue;
                    const col = sdk.scaleRGB(SPARK_COL, @min(@as(u32, 256), v + 1));
                    const n: isize = @intCast(i);
                    if (i < 48) cv.addSigned(cx, line - n, col);
                    cv.addSigned(cx, line + n, col);
                    if (i < 60) cv.addSigned(cx + sd * n, line, col);
                }
            }
        }

        // embers lifted off the line
        for (self.embers) |e| {
            if (e.life <= 0.0) continue;
            const t = e.life / e.maxlife;
            const k: u32 = @intFromFloat(255.0 * @min(1.0, t * 1.5));
            if (k == 0) continue;
            const ex: isize = @intFromFloat(@round(e.x));
            const ey: isize = @intFromFloat(@round(e.y));
            const hot = sdk.scaleRGB(EMBER_COL, @min(@as(u32, 256), k + 1));
            const mid = sdk.scaleRGB(EMBER_COL, @min(@as(u32, 256), k / 3 + 1));
            // a 2x2 coal with a ring of glow
            inline for ([4][2]isize{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } }) |o| cv.addSigned(ex + o[0], ey + o[1], hot);
            inline for ([8][2]isize{ .{ -1, 0 }, .{ 2, 0 }, .{ -1, 1 }, .{ 2, 1 }, .{ 0, -1 }, .{ 1, -1 }, .{ 0, 2 }, .{ 1, 2 } }) |o| cv.addSigned(ex + o[0], ey + o[1], mid);
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (!math.isFinite(self.time_sec) or !math.isFinite(self.off) or !math.isFinite(self.sweep)) return true;
        for (self.embers) |e| {
            if (!math.isFinite(e.x) or !math.isFinite(e.y)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

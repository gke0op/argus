// Claude_Descensus.zig: an Argus theme. The Textus cloth with a procedurally generated descent laid over it.
//
// A stickman starts on a slab at the top of a 1920 x 1080 panel and drops through a field of shapes
// (slabs, capsules, domes, discs, hexagons, mounds, ramps, belts). He is on autopilot and the autopilot is a
// button-masher. Reaching the white-hot pad on the weaving line wins; sinking into the loose warp is a fall.
// Every seed's level has a guaranteed route (a guide that follows it wins 100% of the seeds measured), and a
// random walker still wins roughly four in ten. No words anywhere: the history strip is diamonds (won),
// triangles (fell) and rings (timed out).
//
// Layout: one level cell = one 8 px thread crossing. 240 x 135 cells = 1920 x 1080. The level's row 118 sits on
// the cloth's weaving line (y = 944 on a 1080 panel; shifted down with the line on taller panels).
// Panels smaller than 1920 x 1080 draw the cloth alone.
//
// Single file; the only import is the SDK. Zero allocations after init. The level generator, physics and the
// agent API (reset / step / observe) are in the `Descensus` namespace below and use only integers.
const std = @import("std");
const sdk = @import("argus_theme_sdk.zig");

// ======================================================================= Textus (unchanged except init is split into init + setup, and the inscription band can be woven without its word)
const Textus = struct {
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
// Cost: one allocation (Loom), none afterwards. Per pixel it is table lookups and a
// few multiplies, eight pixels at a time; the cloth is rebuilt only when a row is woven.

const math = std.math;

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

pub const Loom = struct {
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
    no_lettering: bool, // set by the host theme: weave the inscription band without its word, so the level laid over it is shapes only

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

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*Loom {
        const self = try alloc.create(Loom);
        self.setup(w, h, scale, false);
        return self;
    }

    /// everything init does after the allocation, so a host theme can embed a Loom by value
    pub fn setup(self: *Loom, w: usize, h: usize, scale: f64, no_lettering: bool) void {
        @memset(std.mem.asBytes(self), 0);
        self.no_lettering = no_lettering;
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
    }

    pub fn deinit(self: *Loom, alloc: std.mem.Allocator) void {
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

    fn buildProfiles(self: *Loom) void {
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

    fn buildLuts(self: *Loom) void {
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

    fn buildStars(self: *Loom) void {
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
    inline fn nextCa(self: *Loom) u32 {
        self.rng_ca = self.rng_ca *% 6364136223846793005 +% 1442695040888963407;
        return @as(u32, @truncate(self.rng_ca >> 33));
    }

    inline fn nextFx(self: *Loom) u32 {
        self.rng_fx = self.rng_fx *% 6364136223846793005 +% 1442695040888963407;
        return @as(u32, @truncate(self.rng_fx >> 33));
    }

    // grow one panel of the card from its seeds: PANEL_HALF rows of a cellular automaton
    fn genPanel(self: *Loom, m: *const Motif) void {
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
    fn weaveRow(self: *Loom) void {
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
        if (!self.no_lettering and self.seg_kind == 3 and pos >= 2 and pos < 9) {
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

    inline fn bitC(self: *const Loom, ri: usize, c: usize) u8 {
        return self.rows[ri][c];
    }

    fn buildRow(self: *Loom, a: usize) void {
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

    fn buildAll(self: *Loom) void {
        const n = @min(VIS, self.line_y / CELL + 3);
        for (0..n) |a| self.buildRow(a);
    }

    pub fn step(self: *Loom, dt_in: f64) void {
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

    fn sparkX(self: *const Loom, side: f32) f32 {
        const cx: f32 = @floatFromInt(self.ncol * CELL / 2);
        return cx + side * self.sweep * cx;
    }

    fn updateEmbers(self: *Loom, dt: f64) void {
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

    inline fn cellVec(self: *const Loom, col: u32, figc: u32, v: usize, c: usize, sub: usize, g0: u32, pa: u32, phb: u32) VU {
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

    inline fn cellRow(self: *const Loom, dst: []u32, ccr: *const [MAX_COLS]u32, cvr: *const [MAX_COLS]u8, figc: u32, sub: usize, g0: u32, pa: u32, phb: u32) void {
        const nfull = self.w / CELL;
        const rem = self.w % CELL;
        var c: usize = 0;
        while (c < nfull) : (c += 1) {
            dst[c * CELL ..][0..8].* = self.cellVec(ccr[c], figc, cvr[c], c, sub, g0, pa, phb);
        }
        if (rem != 0) {
            const t: [8]u32 = self.cellVec(ccr[nfull], figc, cvr[nfull], nfull, sub, g0, pa, phb);
            @memcpy(dst[nfull * CELL ..][0..rem], t[0..rem]);
        }
    }

    // loose warp below the reed: like cellRow, but each thread fades at its own distance
    inline fn strandRow(self: *const Loom, dst: []u32, dd: usize, pa: u32, phb: u32) void {
        const nfull = self.w / CELL;
        const rem = self.w % CELL;
        var c: usize = 0;
        while (c < nfull) : (c += 1) {
            const g0: u32 = self.fringe[self.tcls[c]][dd];
            dst[c * CELL ..][0..8].* = self.cellVec(self.warpcol[c], 0, 8, c, 0, g0, pa, phb);
        }
        if (rem != 0) {
            const g0: u32 = self.fringe[self.tcls[nfull]][dd];
            const t: [8]u32 = self.cellVec(self.warpcol[nfull], 0, 8, nfull, 0, g0, pa, phb);
            @memcpy(dst[nfull * CELL ..][0..rem], t[0..rem]);
        }
    }

    pub fn draw(self: *const Loom, buf: []u32, stride: usize) void {
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

    fn drawLights(self: *const Loom, buf: []u32, stride: usize) void {
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

    pub fn hasNaN(self: *const Loom) bool {
        if (!math.isFinite(self.time_sec) or !math.isFinite(self.off) or !math.isFinite(self.sweep)) return true;
        for (self.embers) |e| {
            if (!math.isFinite(e.x) or !math.isFinite(e.y)) return true;
        }
        return false;
    }
};



};

// ======================================================================= Descensus core: generator, physics, env, agents
pub const Descensus = struct {
// DESCENSUS core. A shapes-only, procedurally generated descent on a 240 x 135 grid of 8 px cells = 1920 x 1080.
// std-only, allocation-free, integer physics: the same seed and the same actions give the same run on every target.
// The thread starts on a slab at the top and drops tier to tier; touching the finish pad wins, sinking below the
// weaving line (into the loose warp) is a fall. The generator guarantees a route; it does not guarantee a safe one.

pub const W = 240; // cells across (1920 px)
pub const H = 135; // cells down (1080 px)
pub const CELL = 8; // px per cell
pub const LINE_ROW = 118; // the weaving line, row of y = 944 px; the fringe hangs below it
pub const PAD_TOP = 115; // top row of the finish pad (3 rows thick, resting on the weaving line)
pub const START_TOP = 9; // top row of the start slab
pub const MAX_SHAPES = 250;

pub const AIR: u8 = 0;
pub const SOLID: u8 = 1;
pub const BELT_L: u8 = 2; // a current that carries the thread left
pub const BELT_R: u8 = 3;
pub const GOAL: u8 = 4; // the finish pad

pub const Rng = struct {
    s: u64,
    pub fn next(self: *Rng) u64 {
        self.s +%= 0x9E3779B97F4A7C15;
        var z = self.s;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return z ^ (z >> 31);
    }
    pub fn below(self: *Rng, n: u32) u32 {
        return @intCast(((self.next() >> 32) * @as(u64, n)) >> 32);
    }
    pub fn range(self: *Rng, lo: i32, hi: i32) i32 { // inclusive both ends
        return lo + @as(i32, @intCast(self.below(@intCast(hi - lo + 1))));
    }
    pub fn pct(self: *Rng, p: u32) bool {
        return self.below(100) < p;
    }
};

/// Seeds that differ by one must not give streams that are shifted copies of each other, so every seed is hashed first.
pub fn mixSeed(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn isqrt(n: u32) u32 {
    var x = n;
    var r: u32 = 0;
    var b: u32 = 1 << 30;
    while (b > x) b >>= 2;
    while (b != 0) {
        if (x >= r + b) {
            x -= r + b;
            r = (r >> 1) + b;
        } else r >>= 1;
        b >>= 2;
    }
    return r;
}

fn iabs(x: i32) i32 {
    return if (x < 0) -x else x;
}

pub const Shape = struct { kind: u8, c0: i16, r0: i16, w: i16, h: i16 };
pub const Stop = struct { c0: i16, c1: i16, row: i16, side: i8 }; // a spine platform: flat top columns (inclusive), top row, and the edge the drop leaves by (-1 left, +1 right, 0 the pad)

pub const World = struct {
    cell: [H][W]u8,
    sid: [H][W]u8, // shape number + 1, 0 = none
    block: [H][W]u8, // generator scratch: 1 = nothing new may be placed here
    shapes: [MAX_SHAPES]Shape,
    nshapes: u32,
    seed: u64,
    tries: u32, // how many sub-seeds the generator needed
    start_c: i32, // column the thread stands on at the start
    pad_c0: i32, // finish pad columns, inclusive
    pad_c1: i32,
    nspine: u32,
    spine: [16]Stop, // the drops the generator promises (tests and oracle only; the wanderer never reads it)
};

pub inline fn at(w: *const World, c: i32, r: i32) u8 {
    if (c < 0 or c >= W) return SOLID; // the panel's sides are walls
    if (r < 0 or r >= H) return AIR; // open above, open below
    return w.cell[@intCast(r)][@intCast(c)];
}

// ---------------------------------------------------------------- shapes
// Every shape is rasterized into a small mask first, so it can be tested before it touches the world.
const MW = 96;
const MH = 20;
pub const Mask = struct {
    m: [MH][MW]u8,
    w: i32,
    h: i32,
};
pub const Kind = enum(u8) { slab, capsule, disc, hex, mound, wedge, dome, belt };

fn clearMask(mk: *Mask, w: i32, h: i32) void {
    mk.w = w;
    mk.h = h;
    var r: i32 = 0;
    while (r < h) : (r += 1) @memset(mk.m[@intCast(r)][0..@intCast(w)], 0);
}

fn span(mk: *Mask, r: i32, c0: i32, c1: i32) void { // fill [c0, c1) on row r
    var c = c0;
    while (c < c1) : (c += 1) mk.m[@intCast(r)][@intCast(c)] = SOLID;
}

fn beltTop(mk: *Mask, dir: i32) void { // the first solid cell of every column becomes a current
    var c: i32 = 0;
    while (c < mk.w) : (c += 1) {
        var r: i32 = 0;
        while (r < mk.h) : (r += 1) {
            const p = &mk.m[@intCast(r)][@intCast(c)];
            if (p.* != 0) {
                p.* = if (dir < 0) BELT_L else BELT_R;
                break;
            }
        }
    }
}

/// k = cells of run per step for hex / mound / wedge. dir = belt direction, or the rising side of a wedge.
pub fn build(mk: *Mask, kind: Kind, w: i32, h: i32, k: i32, dir: i32) void {
    var r: i32 = 0;
    switch (kind) {
        .slab, .belt => {
            clearMask(mk, w, h);
            while (r < h) : (r += 1) span(mk, r, 0, w);
            if (kind == .belt) beltTop(mk, dir);
        },
        .capsule => { // a stadium: flat top, rounded ends
            clearMask(mk, w, h);
            while (r < h) : (r += 1) {
                const dy2 = iabs(2 * r + 1 - h);
                const xh: i32 = @intCast(isqrt(@intCast(h * h - dy2 * dy2)));
                const inset = @divTrunc(h - xh + 1, 2);
                span(mk, r, inset, w - inset);
            }
        },
        .disc, .dome => { // an ellipse, or its upper half
            const vh = if (kind == .dome) 2 * h else h;
            clearMask(mk, w, h);
            while (r < h) : (r += 1) {
                const dy2 = iabs(2 * r + 1 - vh);
                const num: u32 = @intCast(vh * vh - dy2 * dy2);
                const rt: i32 = @intCast(isqrt(@as(u32, @intCast(w * w)) * num));
                const wr = @max(@divTrunc(rt, vh), 1);
                const c0 = @divTrunc(w - wr, 2);
                span(mk, r, c0, c0 + wr);
            }
        },
        .hex => { // flat top and bottom, widest through the middle
            clearMask(mk, w, h);
            const half = @divTrunc(h - 1, 2);
            while (r < h) : (r += 1) {
                const inset = (half - @min(r, h - 1 - r)) * k;
                span(mk, r, inset, w - inset);
            }
        },
        .mound => { // a stepped pyramid: narrow flat top, wide base
            clearMask(mk, w, h);
            while (r < h) : (r += 1) {
                const inset = (h - 1 - r) * k;
                span(mk, r, inset, w - inset);
            }
        },
        .wedge => { // a ramp of base height h, one cell higher every k columns, rising to the right when dir > 0
            const hh = h + @divTrunc(w - 1, k);
            clearMask(mk, w, hh);
            var c: i32 = 0;
            while (c < w) : (c += 1) {
                const i = if (dir > 0) c else w - 1 - c;
                r = hh - (h + @divTrunc(i, k));
                while (r < hh) : (r += 1) mk.m[@intCast(r)][@intCast(c)] = SOLID;
            }
        },
    }
}

/// first and last solid column of the top row
fn topSpan(mk: *const Mask, f: *i32, l: *i32) void {
    f.* = -1;
    l.* = -1;
    var c: i32 = 0;
    while (c < mk.w) : (c += 1) {
        if (mk.m[0][@intCast(c)] != 0) {
            if (f.* < 0) f.* = c;
            l.* = c;
        }
    }
}

// ---------------------------------------------------------------- placement
fn okAt(w: *const World, mk: *const Mask, c0: i32, r0: i32) bool {
    var r: i32 = 0;
    while (r < mk.h) : (r += 1) {
        var c: i32 = 0;
        while (c < mk.w) : (c += 1) {
            if (mk.m[@intCast(r)][@intCast(c)] == 0) continue;
            const x = c0 + c;
            const y = r0 + r;
            if (x < 2 or x > W - 3 or y < 2 or y > H - 1) return false;
            if (w.block[@intCast(y)][@intCast(x)] != 0) return false;
        }
    }
    return true;
}

fn dilate(w: *World, x: i32, y: i32) void { // 2 columns each side, 4 rows above and below: room to stand, to jump, to pass
    var yy = @max(y - 4, 0);
    while (yy <= @min(y + 4, H - 1)) : (yy += 1) {
        var xx = @max(x - 2, 0);
        while (xx <= @min(x + 2, W - 1)) : (xx += 1) w.block[@intCast(yy)][@intCast(xx)] = 1;
    }
}

fn reserve(w: *World, c0: i32, c1: i32, r0: i32, r1: i32) void { // keep a flight path clear
    var r = @max(r0, 0);
    while (r <= @min(r1, H - 1)) : (r += 1) {
        var c = @max(c0, 0);
        while (c <= @min(c1, W - 1)) : (c += 1) w.block[@intCast(r)][@intCast(c)] = 1;
    }
}

fn commit(w: *World, mk: *const Mask, c0: i32, r0: i32, kind: Kind) void {
    if (w.nshapes >= MAX_SHAPES) return;
    const id: u8 = @intCast(w.nshapes + 1);
    w.shapes[w.nshapes] = .{ .kind = @intFromEnum(kind), .c0 = @intCast(c0), .r0 = @intCast(r0), .w = @intCast(mk.w), .h = @intCast(mk.h) };
    w.nshapes += 1;
    var r: i32 = 0;
    while (r < mk.h) : (r += 1) {
        var c: i32 = 0;
        while (c < mk.w) : (c += 1) {
            const v = mk.m[@intCast(r)][@intCast(c)];
            const x = c0 + c;
            const y = r0 + r;
            if (v == 0 or x < 0 or x >= W or y < 0 or y >= H) continue;
            w.cell[@intCast(y)][@intCast(x)] = v;
            w.sid[@intCast(y)][@intCast(x)] = id;
            dilate(w, x, y);
        }
    }
}

// ---------------------------------------------------------------- the spine: a chain of drops that is always there
fn spineShape(rng: *Rng, mk: *Mask, toward: i32) Kind {
    switch (rng.below(5)) {
        0 => {
            build(mk, .slab, rng.range(18, 44), if (rng.pct(50)) 2 else 3, 0, 0);
            return .slab;
        },
        1 => {
            build(mk, .capsule, rng.range(20, 44), 3, 0, 0);
            return .capsule;
        },
        2 => {
            build(mk, .hex, rng.range(22, 44), 4, 2, 0);
            return .hex;
        },
        3 => {
            build(mk, .mound, rng.range(30, 44), 4, 2, 0);
            return .mound;
        },
        else => {
            build(mk, .belt, rng.range(20, 40), 3, 0, if (rng.pct(70)) toward else -toward);
            return .belt;
        },
    }
}

fn record(w: *World, mk: *const Mask, c0: i32, r0: i32) void {
    var f: i32 = 0;
    var l: i32 = 0;
    topSpan(mk, &f, &l);
    w.spine[w.nspine] = .{ .c0 = @intCast(c0 + f), .c1 = @intCast(c0 + l), .row = @intCast(r0), .side = 0 };
    w.nspine += 1;
}

fn buildSpine(w: *World, rng: *Rng, mk: *Mask) bool {
    var dys: [12]i32 = undefined;
    var n: i32 = 0;
    var guard: u32 = 0;
    while (true) { // a vertical plan: n drops that end exactly on the pad row, the last one the longest
        guard += 1;
        if (guard > 400) return false;
        n = rng.range(9, 11);
        var sum: i32 = 0;
        var i: i32 = 0;
        while (i < n - 1) : (i += 1) {
            dys[@intCast(i)] = rng.range(8, 12);
            sum += dys[@intCast(i)];
        }
        const last = (PAD_TOP - START_TOP) - sum;
        if (last >= 14 and last <= 18) {
            dys[@intCast(n - 1)] = last;
            break;
        }
    }
    const xp = rng.range(80, 160); // roughly where the pad will be: the chain leans toward it
    const sw = rng.range(26, 40);
    build(mk, if (rng.pct(50)) .slab else .capsule, sw, 3, 0, 0);
    const sc0 = rng.range(70, 170) - @divTrunc(sw, 2);
    if (!okAt(w, mk, sc0, START_TOP)) return false;
    commit(w, mk, sc0, START_TOP, .slab);
    record(w, mk, sc0, START_TOP);
    w.start_c = sc0 + @divTrunc(sw, 2);

    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const prev = w.spine[@intCast(i)];
        const mid = (@as(i32, prev.c0) + prev.c1) >> 1;
        const last = i == n - 1;
        var side: i32 = if (xp > mid) 1 else -1;
        if (i < n - 3 and rng.pct(45)) side = -side; // wander early, march home late
        const t2 = @as(i32, prev.row) + dys[@intCast(i)];
        var placed = false;
        var attempt: u32 = 0;
        while (attempt < 40 and !placed) : (attempt += 1) {
            const sd = if (attempt >= 20) -side else side;
            const e: i32 = if (sd > 0) prev.c1 else prev.c0;
            var kind: Kind = .slab;
            if (last) {
                build(mk, .slab, rng.range(34, 44), 3, 0, 0);
            } else {
                kind = spineShape(rng, mk, sd);
            }
            var f: i32 = 0;
            var l: i32 = 0;
            topSpan(mk, &f, &l);
            if (!last and l - f + 1 < 18) continue; // room to land after riding down a stepped side
            const c0 = if (sd > 0) e - 1 - f else e + 1 - l; // the new top reaches back under the edge by one cell
            if (!okAt(w, mk, c0, t2)) continue;
            if (last) { // the finish pad is a slab of GOAL
                var r: i32 = 0;
                while (r < mk.h) : (r += 1) {
                    var c: i32 = 0;
                    while (c < mk.w) : (c += 1) {
                        if (mk.m[@intCast(r)][@intCast(c)] != 0) mk.m[@intCast(r)][@intCast(c)] = GOAL;
                    }
                }
                w.pad_c0 = c0 + f;
                w.pad_c1 = c0 + l;
            }
            if (sd > 0) reserve(w, e + 1, e + 16, @as(i32, prev.row) - 4, t2 - 1) else reserve(w, e - 16, e - 1, @as(i32, prev.row) - 4, t2 - 1); // the flight path, and the shoulder a stepped side adds
            commit(w, mk, c0, t2, kind);
            record(w, mk, c0, t2);
            w.spine[@intCast(i)].side = @intCast(sd);
            placed = true;
        }
        if (!placed) return false;
    }
    return true;
}

// ---------------------------------------------------------------- funnel, decoys, generate
fn funnel(w: *World, rng: *Rng, mk: *Mask) void { // two ramps lead down into the pad, their surfaces a current toward it
    const k = rng.range(4, 6);
    const base = PAD_TOP + 3 - PAD_TOP; // the ramps start as tall as the pad is thick
    inline for ([2]i32{ -1, 1 }) |side| {
        const room = if (side < 0) w.pad_c0 - 3 else W - 3 - w.pad_c1;
        const len = @min(rng.range(16, 24), room);
        if (len >= 6) {
            build(mk, .wedge, len, base, k, side); // rises away from the pad
            beltTop(mk, -side);
            const c0 = if (side < 0) w.pad_c0 - len else w.pad_c1 + 1;
            commit(w, mk, c0, PAD_TOP + 3 - mk.h, .wedge);
        }
    }
}

fn decoys(w: *World, rng: *Rng, mk: *Mask, attempts: u32) void {
    const pc = (w.pad_c0 + w.pad_c1) >> 1;
    var i: u32 = 0;
    while (i < attempts and w.nshapes < MAX_SHAPES) : (i += 1) {
        const kd = rng.below(100);
        var kind: Kind = .slab;
        var ww: i32 = 0;
        var hh: i32 = 0;
        var kk: i32 = 2;
        if (kd < 18) {
            kind = .slab;
            ww = rng.range(6, 26);
            hh = rng.range(1, 2);
        } else if (kd < 33) {
            kind = .capsule;
            ww = rng.range(8, 24);
            hh = 3;
        } else if (kd < 47) {
            kind = .disc;
            hh = rng.range(4, 8);
            ww = hh + rng.range(0, 6);
        } else if (kd < 59) {
            kind = .hex;
            ww = rng.range(10, 22);
            hh = rng.range(3, 4);
        } else if (kd < 69) {
            kind = .mound;
            ww = rng.range(14, 26);
            hh = rng.range(3, 4);
        } else if (kd < 80) {
            kind = .wedge;
            ww = rng.range(8, 18);
            hh = rng.range(1, 2);
            kk = @max(1, @divTrunc(ww - 1, rng.range(2, 6)));
        } else if (kd < 91) {
            kind = .dome;
            ww = rng.range(10, 24);
            hh = rng.range(3, 6);
        } else {
            kind = .belt;
            ww = rng.range(10, 28);
            hh = 2;
        }
        const c0 = rng.range(2, W - 3 - ww);
        const r0 = rng.range(START_TOP + 3, PAD_TOP - 14);
        const toward: i32 = if (pc > c0 + (ww >> 1)) 1 else -1;
        const dir: i32 = if (kind == .wedge) (if (rng.pct(50)) 1 else -1) else if (rng.pct(70)) toward else -toward;
        build(mk, kind, ww, hh, kk, dir);
        if (okAt(w, mk, c0, r0)) commit(w, mk, c0, r0, kind);
    }
}

/// Build the whole level from a seed. Deterministic. Retries with sub-seeds in the rare case the spine does not fit.
pub fn generate(w: *World, seed: u64) void {
    var attempt: u32 = 0;
    while (attempt < 64) : (attempt += 1) {
        @memset(std.mem.asBytes(w), 0);
        w.seed = seed;
        w.tries = attempt + 1;
        var rng = Rng{ .s = mixSeed(seed ^ (@as(u64, attempt) *% 0xD1B54A32D192ED03)) };
        var mk: Mask = undefined;
        if (!buildSpine(w, &rng, &mk)) continue;
        funnel(w, &rng, &mk);
        decoys(w, &rng, &mk, DECOY_TRIES);
        return;
    }
}

pub var DECOY_TRIES: u32 = 1400; // how many extra shapes the generator tries to fit: density, not difficulty (a random walker wins 40.9% at 0 tries, 39.4% at 2800)

// ---------------------------------------------------------------- physics: integers, 120 ticks a second, 1/256 px
// Same feel as Textus Run (run 150 px/s, jump 410 px/s, gravity 1500 px/s^2), expressed per tick.
pub const SUBSHIFT = 11; // 2048 subunits = one cell = 8 px
pub const PW2: i32 = 896; // half body width, 3.5 px
pub const PH: i32 = 6144; // body height, 24 px
const RUN: i32 = 320;
const ACC: i32 = 27;
const ACC_AIR: i32 = 18;
const FRIC: i32 = 32;
const GRAV: i32 = 27;
const JUMP: i32 = 875;
const SHORT: i32 = 306; // letting go early caps the rise at this speed
const MAXFALL: i32 = 1195;
const GLIDE_GRAV: i32 = 10; // holding jump while falling: drift like a loose thread
const GLIDE_MAX: i32 = 320;
const COYOTE: i32 = 11;
const BUFFER: i32 = 12;
const BELT: i32 = 128; // a current moves the thread 60 px/s, slower than he can walk against it
pub const TICKS_PER_SEC = 120;
pub const MAXT: u32 = 100 * TICKS_PER_SEC;
pub const KILL_Y: i32 = (LINE_ROW + 3) << SUBSHIFT; // feet three rows under the weaving line: unravelled

pub const Body = struct {
    x: i32, // feet centre
    y: i32, // feet
    vx: i32,
    vy: i32,
    coy: i32,
    buf: i32,
    ground: bool,
    jh: bool,
    face: i32,
    ev: u8, // 1 = jumped, 2 = landed (this tick)
};

fn hits(w: *const World, x: i32, y: i32) bool {
    const c0 = (x - PW2) >> SUBSHIFT;
    const c1 = (x + PW2 - 1) >> SUBSHIFT;
    const r1 = (y - 1) >> SUBSHIFT;
    var r = (y - PH) >> SUBSHIFT;
    while (r <= r1) : (r += 1) {
        var c = c0;
        while (c <= c1) : (c += 1) if (at(w, c, r) != AIR) return true;
    }
    return false;
}

/// what the thread stands on: the kind of the cell under the feet (centre first, then either side)
pub fn support(w: *const World, p: *const Body) u8 {
    const r = p.y >> SUBSHIFT;
    var k = at(w, p.x >> SUBSHIFT, r);
    if (k == AIR) k = at(w, (p.x - PW2) >> SUBSHIFT, r);
    if (k == AIR) k = at(w, (p.x + PW2 - 1) >> SUBSHIFT, r);
    return k;
}

fn moveX(w: *const World, p: *Body, dx: i32, grounded: bool) void {
    p.x += dx;
    if (!hits(w, p.x, p.y)) return;
    const lift: i32 = if (grounded) 8 else 6; // px: a walker steps up one cell, a jumper clears a smaller lip
    var u: i32 = 1;
    while (u <= lift) : (u += 1) {
        if (!hits(w, p.x, p.y - u * 256)) {
            p.y -= u * 256;
            if (p.vy > 0) p.vy = 0;
            return;
        }
    }
    if (dx > 0) {
        p.x = (((p.x + PW2 - 1) >> SUBSHIFT) << SUBSHIFT) - PW2;
    } else {
        p.x = ((((p.x - PW2) >> SUBSHIFT) + 1) << SUBSHIFT) + PW2;
    }
    p.vx = 0;
}

fn moveY(w: *const World, p: *Body, dy: i32) void {
    p.y += dy;
    if (!hits(w, p.x, p.y)) return;
    if (dy > 0) {
        p.y = ((p.y - 1) >> SUBSHIFT) << SUBSHIFT;
        p.ground = true;
    } else {
        p.y = ((((p.y - PH) >> SUBSHIFT) + 1) << SUBSHIFT) + PH;
    }
    p.vy = 0;
}

/// Advance one tick. act bits: 1 = left, 2 = right, 4 = jump (held).
pub fn tick(w: *const World, p: *Body, act: u3) void {
    p.ev = 0;
    const dir: i32 = @as(i32, (act >> 1) & 1) - @as(i32, act & 1);
    const jump = (act & 4) != 0;
    const belt: i32 = if (p.ground) switch (support(w, p)) {
        BELT_L => -BELT,
        BELT_R => BELT,
        else => 0,
    } else 0;
    const acc: i32 = if (dir == 0) FRIC else if (p.ground) ACC else ACC_AIR;
    p.vx += std.math.clamp(dir * RUN - p.vx, -acc, acc);
    if (dir != 0) p.face = dir;
    if (jump and !p.jh) p.buf = BUFFER;
    p.jh = jump;
    p.buf -= 1;
    p.coy = if (p.ground) COYOTE else p.coy - 1;
    if (p.buf > 0 and p.coy > 0) {
        p.vy = -JUMP;
        p.buf = 0;
        p.coy = 0;
        p.ground = false;
        p.ev |= 1;
    }
    if (!jump and p.vy < -SHORT) p.vy = -SHORT; // let go early = short hop
    const glide = jump and p.vy > 0 and !p.ground;
    p.vy += if (glide) GLIDE_GRAV else GRAV;
    if (glide and p.vy > GLIDE_MAX) p.vy += @divTrunc(GLIDE_MAX - p.vy, 12);
    if (p.vy > MAXFALL) p.vy = MAXFALL;
    const was = p.ground;
    p.ground = false;
    moveX(w, p, p.vx, was);
    if (belt != 0) moveX(w, p, belt, was);
    moveY(w, p, p.vy);
    if (!p.ground and p.vy >= 0 and hits(w, p.x, p.y + 128)) p.ground = true;
    if (p.ground) {
        if (!was) p.ev |= 2;
        p.vy = @min(p.vy, 0);
    }
}

// ---------------------------------------------------------------- the environment: what an agent, or a learner, talks to
pub const Outcome = enum(u8) { running, won, fell, timeout };

pub const Env = struct {
    w: World,
    p: Body,
    t: u32,
    out: Outcome,
    reward: f32, // dense: depth gained this step / 100, +1 on the pad, -1 on a fall

    pub fn reset(self: *Env, seed: u64) void {
        generate(&self.w, seed);
        self.p = .{ .x = (self.w.start_c << SUBSHIFT) + 1024, .y = START_TOP << SUBSHIFT, .vx = 0, .vy = 0, .coy = 0, .buf = 0, .ground = true, .jh = false, .face = 1, .ev = 0 };
        self.t = 0;
        self.out = .running;
        self.reward = 0;
    }

    pub fn step(self: *Env, act: u3) void {
        if (self.out != .running) return;
        const y0 = self.p.y;
        tick(&self.w, &self.p, act);
        self.t += 1;
        self.reward = @as(f32, @floatFromInt(self.p.y - y0)) / (100.0 * 2048.0);
        if (self.p.ground and support(&self.w, &self.p) == GOAL) {
            self.out = .won;
            self.reward += 1.0;
        } else if (self.p.y > KILL_Y) {
            self.out = .fell;
            self.reward -= 1.0;
        } else if (self.t >= MAXT) {
            self.out = .timeout;
        }
    }

    /// repeat one action for up to n ticks, stopping when the run ends
    pub fn stepN(self: *Env, act: u3, n: u32) void {
        var i: u32 = 0;
        var acc: f32 = 0;
        while (i < n and self.out == .running) : (i += 1) {
            self.step(act);
            acc += self.reward;
        }
        self.reward = acc;
    }
};

// ---------------------------------------------------------------- agents
/// The wanderer: presses buttons at random and holds them for a random while. This is "bro does random stuff".
pub const Wander = struct {
    rng: Rng,
    act: u3,
    hold: i32,
    lo: i32, // hold range in ticks
    hi: i32,

    pub fn init(seed: u64, lo: i32, hi: i32) Wander {
        return .{ .rng = .{ .s = mixSeed(seed ^ 0xA5A5A5A55A5A5A5A) }, .act = 0, .hold = 0, .lo = lo, .hi = hi };
    }
    pub fn next(self: *Wander) u3 {
        if (self.hold <= 0) {
            var a: u3 = @intCast(self.rng.below(8));
            if (a & 3 == 3) a &= 4; // both ways at once is nothing
            self.act = a;
            self.hold = self.rng.range(self.lo, self.hi);
        }
        self.hold -= 1;
        return self.act;
    }
};

/// The guide: it knows the spine and walks it, leaving each platform by the edge the generator promised.
/// It proves a route exists; it is not how a learner is meant to see the world.
pub const Guide = struct {
    stuck: i32 = 0,
    hop: i32 = 0, // ticks left of a held jump

    pub fn next(self: *Guide, w: *const World, p: *const Body) u3 {
        const row = p.y >> SUBSHIFT;
        const col = p.x >> SUBSHIFT;
        var dir: i32 = p.face;
        if (p.ground) {
            var on = false;
            for (w.spine[0..w.nspine]) |s| {
                if (@as(i32, s.row) == row and col >= @as(i32, s.c0) - 1 and col <= @as(i32, s.c1) + 1) {
                    if (s.side != 0) dir = s.side;
                    on = true;
                    break;
                }
            }
            if (!on) { // off the spine: head for the next stop down
                for (w.spine[0..w.nspine]) |s| {
                    if (@as(i32, s.row) > row) {
                        const tx = std.math.clamp(col, @as(i32, s.c0) + 3, @as(i32, s.c1) - 3);
                        if (tx != col) dir = if (tx > col) 1 else -1;
                        break;
                    }
                }
            }
        }
        self.stuck = if (p.ground and p.vx == 0) self.stuck + 1 else 0;
        if (self.stuck > 20) self.hop = 44; // wedged against a lip: a full held jump
        const a: u3 = if (dir < 0) 1 else 2;
        if (self.hop > 0) {
            self.hop -= 1;
            return a | 4;
        }
        return a;
    }
};

/// FNV-1a over the cell grid: two worlds from the same seed must agree to the bit.
pub fn worldHash(w: *const World) u64 {
    var h: u64 = 0xCBF29CE484222325;
    for (w.cell) |row| {
        for (row) |v| {
            h ^= v;
            h *%= 0x100000001B3;
        }
    }
    return h;
}

// ---------------------------------------------------------------- what a learner sees
// 38 numbers, each about -1..1: no pixels, no spine, no pad map; only what a thread could feel around itself.
pub const OBS = 38;
const RAYS = blk: {
    var t: [16][2]f32 = undefined;
    for (0..16) |i| {
        const a = @as(f32, @floatFromInt(i)) * (std.math.pi / 8.0);
        t[i] = .{ @cos(a), @sin(a) };
    }
    break :blk t;
};

pub fn observe(e: *const Env, out: *[OBS]f32) void {
    const p = &e.p;
    const w = &e.w;
    const f = struct {
        fn n(v: i32, d: i32) f32 {
            return @as(f32, @floatFromInt(v)) / @as(f32, @floatFromInt(d));
        }
    }.n;
    const sup = if (p.ground) support(w, p) else AIR;
    const col = p.x >> SUBSHIFT;
    const row = p.y >> SUBSHIFT;
    out[0] = f(p.vx, RUN);
    out[1] = f(p.vy, MAXFALL);
    out[2] = if (p.ground) 1 else 0;
    out[3] = if (p.coy > 0) 1 else 0;
    out[4] = f(col, W) * 2 - 1;
    out[5] = f(row, H) * 2 - 1;
    out[6] = if (sup == BELT_L) 1 else 0;
    out[7] = if (sup == BELT_R) 1 else 0;
    out[8] = if (sup == GOAL) 1 else 0;
    out[9] = f(((w.pad_c0 + w.pad_c1) >> 1) - col, W);
    out[10] = f(PAD_TOP - row, H);
    const cx = @as(f32, @floatFromInt(p.x)) / 2048.0;
    const cy = @as(f32, @floatFromInt(p.y - PH / 2)) / 2048.0;
    for (RAYS, 0..) |d, i| { // sixteen whiskers, 24 cells long, 1 = nothing in reach
        var hit: f32 = 1.0;
        var s: i32 = 1;
        while (s <= 48) : (s += 1) {
            const k = @as(f32, @floatFromInt(s)) * 0.5;
            const gx: i32 = @intFromFloat(@floor(cx + d[0] * k));
            const gy: i32 = @intFromFloat(@floor(cy + d[1] * k));
            if (at(w, gx, gy) != AIR) {
                hit = k / 24.0;
                break;
            }
        }
        out[11 + i] = hit;
    }
    var j: usize = 0;
    var dx: i32 = -10;
    while (dx <= 10) : (dx += 2) { // eleven plumb lines: how far down until something, 1 = a hole to the bottom
        var r = row;
        while (r < row + 40 and at(w, col + dx, r) == AIR) : (r += 1) {}
        out[27 + j] = f(r - row, 40);
        j += 1;
    }
}

};

// ======================================================================= Descensus stage: tiles, thread, effects, run loop
const Draw = struct {
// DESCENSUS stage: draws the level over a Textus frame, runs the autopilot, keeps the show going.
// Everything is laid out on the 1920 x 1080 panel: one level cell = one 8 px thread crossing.
const D = Descensus;

const W = D.W;
const H = D.H;

// A filament cools as it ages: the same ramp the Textus cloth uses, here mapped to height, hot at the weaving line.
const ANCH = [6][3]f32{
    .{ 255.0, 250.0, 236.0 }, // white-hot
    .{ 255.0, 214.0, 138.0 }, // gold
    .{ 255.0, 150.0, 112.0 }, // ember
    .{ 232.0, 96.0, 172.0 }, // rose
    .{ 138.0, 98.0, 238.0 }, // violet
    .{ 96.0, 124.0, 236.0 }, // indigo, lifted a little so the top tiers read against the dark cloth
};
const PEARL: [3]f32 = .{ 236.0, 244.0, 255.0 };
const AMBER: [3]f32 = .{ 255.0, 176.0, 70.0 };

fn thermalAt(t: f32) [3]f32 { // t: 0 hottest .. 1 coolest
    const x = std.math.clamp(t, 0.0, 1.0) * 5.0;
    const i: usize = @min(@as(usize, @intFromFloat(x)), 4);
    const f = x - @as(f32, @floatFromInt(i));
    var o: [3]f32 = undefined;
    for (0..3) |k| o[k] = ANCH[i][k] + (ANCH[i + 1][k] - ANCH[i][k]) * f;
    return o;
}

fn pack3(c: [3]f32, k: f32) u32 {
    const r: u32 = @intFromFloat(std.math.clamp(c[0] * k, 0.0, 255.0));
    const g: u32 = @intFromFloat(std.math.clamp(c[1] * k, 0.0, 255.0));
    const b: u32 = @intFromFloat(std.math.clamp(c[2] * k, 0.0, 255.0));
    return sdk.packRGBA(@intCast(r), @intCast(g), @intCast(b));
}

/// One thread crossing: a lit cylinder, running across the cell one way or the other, darker where it dives under.
pub const Look = struct {
    tile: [H][4][64]u32, // per row: weave A, weave B, and both again with a lit lip along the top
    thermal: [H]u32, // the row's ramp colour, for effects

    pub fn build(self: *Look) void {
        for (0..H) |r| {
            const t = 1.0 - @min(1.0, @as(f32, @floatFromInt(r)) / 118.0);
            const base = thermalAt(t);
            self.thermal[r] = pack3(base, 1.0);
            for (0..4) |v| {
                const horiz = (v & 1) == 1;
                const lip = v >= 2;
                for (0..8) |y| {
                    for (0..8) |x| {
                        const a: f32 = @floatFromInt(if (horiz) y else x); // across the thread
                        const b: f32 = @floatFromInt(if (horiz) x else y); // along it
                        const cyl = @sqrt(@sin(std.math.pi * (a + 0.5) / 8.0));
                        const dive = @max(0.0, @abs(b - 3.5) - 2.2) / 1.3; // 0 in the middle, 1 at the ends
                        var lum = cyl * (1.0 - 0.42 * dive);
                        var mix: f32 = 0.0;
                        if (lip and y < 2) {
                            lum = 0.62 + 0.38 * lum;
                            mix = if (y == 0) 0.7 else 0.3;
                        }
                        const k = 0.2 + 0.8 * lum;
                        const spec = 0.20 * lum * lum;
                        var c: [3]f32 = undefined;
                        for (0..3) |i| c[i] = (base[i] * k + PEARL[i] * spec) * (1.0 - mix) + PEARL[i] * mix;
                        self.tile[r][v][y * 8 + x] = pack3(c, 1.0);
                    }
                }
            }
        }
    }
};

inline fn blit(buf: []u32, stride: usize, px: usize, py: usize, tile: *const [64]u32) void {
    inline for (0..8) |y| @memcpy(buf[(py + y) * stride + px ..][0..8], tile[y * 8 ..][0..8]);
}

inline fn addPx(buf: []u32, stride: usize, w: usize, h: usize, x: i32, y: i32, c: u32) void {
    if (x < 0 or y < 0 or x >= @as(i32, @intCast(w)) or y >= @as(i32, @intCast(h))) return;
    const i = @as(usize, @intCast(y)) * stride + @as(usize, @intCast(x));
    buf[i] = sdk.addRGB(buf[i], c);
}

/// The level, cell by cell. rows above `reveal` are woven in; oy puts level row 118 on the panel's weaving line.
pub fn drawLevel(look: *const Look, wd: *const D.World, buf: []u32, stride: usize, pw: usize, ph: usize, ox: i32, oy: i32, reveal: i32, clock: f32) void {
    const phase: i32 = @intFromFloat(clock * 64.0); // belts: chevrons slide, 64 px a second
    const pulse: u32 = @intFromFloat(34.0 + 30.0 * @sin(clock * 3.2)); // light added to the pad, 4..64
    var r: i32 = 0;
    while (r < @min(reveal, H)) : (r += 1) {
        const py = oy + r * 8;
        if (py < 0 or py + 8 > @as(i32, @intCast(ph))) continue;
        const row = &wd.cell[@intCast(r)];
        var c: i32 = 0;
        while (c < W) : (c += 1) {
            const k = row[@intCast(c)];
            if (k == D.AIR) continue;
            if (ox + c * 8 < 0 or ox + c * 8 + 8 > @as(i32, @intCast(pw))) continue;
            const exposed = r == 0 or wd.cell[@intCast(r - 1)][@intCast(c)] == D.AIR;
            const v: usize = @as(usize, @intCast((c + r) & 1)) + (if (exposed) @as(usize, 2) else 0);
            const px: usize = @intCast(ox + c * 8);
            const pyu: usize = @intCast(py);
            blit(buf, stride, px, pyu, &look.tile[@intCast(r)][v]);
            if (k == D.BELT_L or k == D.BELT_R) { // a current: amber, with chevrons running the way it carries
                const dir: i32 = if (k == D.BELT_R) 1 else -1;
                for (0..8) |y| {
                    const dv: i32 = @intCast(@abs(@as(i32, @intCast(y)) * 2 - 7));
                    for (0..8) |x| {
                        const u = (c * 8 + @as(i32, @intCast(x))) * dir - phase * dir * dir + dv;
                        const lit = @mod(u, 16) < 5;
                        const i = (pyu + y) * stride + px + x;
                        buf[i] = if (lit) sdk.lerpRGB(buf[i], pack3(AMBER, 1.0), 200) else sdk.lerpRGB(buf[i], pack3(AMBER, 0.55), 110);
                    }
                }
            } else if (k == D.GOAL) { // the finish pad breathes
                const lit = sdk.scaleRGB(sdk.packRGBA(255, 226, 160), pulse);
                for (0..8) |y| for (0..8) |x| {
                    const i = (pyu + y) * stride + px + x;
                    buf[i] = sdk.addRGB(buf[i], lit);
                };
                if (exposed) { // a column of light stands over the pad
                    for (1..28) |d| {
                        const g3 = sdk.scaleRGB(sdk.packRGBA(255, 214, 140), pulse * @as(u32, @intCast(28 - d)) * @as(u32, @intCast(28 - d)) / 1100);
                        for (0..8) |x| addPx(buf, stride, pw, ph, ox + c * 8 + @as(i32, @intCast(x)), py - @as(i32, @intCast(d)), g3);
                    }
                }
            }
            if (exposed) { // the lit lip throws a little light up onto the cloth
                const lipglow = sdk.scaleRGB(look.thermal[@intCast(r)], 54);
                inline for (.{ 1, 2, 3 }) |d| {
                    const g2 = sdk.scaleRGB(lipglow, 256 >> d);
                    for (0..8) |x| addPx(buf, stride, pw, ph, ox + c * 8 + @as(i32, @intCast(x)), py - d, g2);
                }
            }
        }
    }
}

// ---------------------------------------------------------------- the thread: a stickman made of light
inline fn fl(v: i32) f32 {
    return @floatFromInt(v);
}

fn plot2(buf: []u32, stride: usize, w: usize, h: usize, x: f32, y: f32, c: u32) void { // a 2 x 2 dot, opaque
    const xi: i32 = @intFromFloat(@floor(x));
    const yi: i32 = @intFromFloat(@floor(y));
    inline for (.{ 0, 1 }) |dy| inline for (.{ 0, 1 }) |dx| {
        const px = xi + dx;
        const py = yi + dy;
        if (px >= 0 and py >= 0 and px < @as(i32, @intCast(w)) and py < @as(i32, @intCast(h))) buf[@as(usize, @intCast(py)) * stride + @as(usize, @intCast(px))] = c;
    };
}

fn seg(buf: []u32, stride: usize, w: usize, h: usize, a: [2]f32, b: [2]f32, c: u32) void {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const n: usize = @intFromFloat(@max(@abs(dx), @abs(dy)) + 1.0);
    for (0..n + 1) |i| {
        const f = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        plot2(buf, stride, w, h, a[0] + dx * f - 0.5, a[1] + dy * f - 0.5, c);
    }
}

fn aseg(buf: []u32, stride: usize, w: usize, h: usize, a: [2]f32, b: [2]f32, c: u32) void { // the same, additive and one pixel wide
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const n: usize = @intFromFloat(@max(@abs(dx), @abs(dy)) + 1.0);
    for (0..n + 1) |i| {
        const f = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
        addPx(buf, stride, w, h, @intFromFloat(@floor(a[0] + dx * f)), @intFromFloat(@floor(a[1] + dy * f)), c);
    }
}

fn disc(buf: []u32, stride: usize, w: usize, h: usize, cx: f32, cy: f32, r: f32, c: u32, add: bool) void {
    const ri: i32 = @intFromFloat(@ceil(r));
    const x0: i32 = @intFromFloat(@floor(cx));
    const y0: i32 = @intFromFloat(@floor(cy));
    var y = y0 - ri;
    while (y <= y0 + ri) : (y += 1) {
        var x = x0 - ri;
        while (x <= x0 + ri) : (x += 1) {
            const ddx = fl(x) + 0.5 - cx;
            const ddy = fl(y) + 0.5 - cy;
            if (ddx * ddx + ddy * ddy > r * r) continue;
            if (add) {
                addPx(buf, stride, w, h, x, y, c);
            } else if (x >= 0 and y >= 0 and x < @as(i32, @intCast(w)) and y < @as(i32, @intCast(h))) {
                buf[@as(usize, @intCast(y)) * stride + @as(usize, @intCast(x))] = c;
            }
        }
    }
}

fn glow(buf: []u32, stride: usize, w: usize, h: usize, cx: f32, cy: f32, rad: f32, col: [3]f32) void {
    const ri: i32 = @intFromFloat(@ceil(rad));
    const x0: i32 = @intFromFloat(@floor(cx));
    const y0: i32 = @intFromFloat(@floor(cy));
    var y = y0 - ri;
    while (y <= y0 + ri) : (y += 1) {
        var x = x0 - ri;
        while (x <= x0 + ri) : (x += 1) {
            const ddx = fl(x) + 0.5 - cx;
            const ddy = fl(y) + 0.5 - cy;
            const d2 = ddx * ddx + ddy * ddy;
            if (d2 >= rad * rad) continue;
            const t = 1.0 - @sqrt(d2) / rad;
            addPx(buf, stride, w, h, x, y, pack3(col, t * t));
        }
    }
}

const Pose = struct { head: [2]f32, neck: [2]f32, hip: [2]f32, knee: [2][2]f32, foot: [2][2]f32, elbow: [2][2]f32, hand: [2][2]f32 };

/// joints in px relative to the feet, x already flipped to face the way he runs
fn pose(p: *const D.Body, gait: f32, clock: f32) Pose {
    const face: f32 = if (p.face < 0) -1.0 else 1.0;
    const spd = @min(1.0, @abs(fl(p.vx)) / 320.0);
    var o: Pose = undefined;
    var lean = face * 1.6 * spd;
    var bob: f32 = 0.35 * @sin(clock * 2.4) * (1.0 - spd);
    if (p.ground) {
        for (0..2) |i| {
            const th = gait + @as(f32, @floatFromInt(i)) * std.math.pi;
            const sw = @sin(th) * 7.0 * spd + (if (i == 0) @as(f32, -2.2) else 2.2) * (1.0 - spd);
            const lift = @max(0.0, @cos(th)) * 4.5 * spd;
            o.foot[i] = .{ face * sw, -lift };
            o.knee[i] = .{ face * (sw * 0.5 + 2.4 + 1.4 * lift / 4.5), -5.5 - lift * 0.5 };
            const ta = th + std.math.pi;
            o.hand[i] = .{ face * (@sin(ta) * 5.5 * spd + (if (i == 0) @as(f32, -3.5) else 3.5) * (1.0 - spd)), -19.0 + 7.5 - 1.2 * @cos(ta) * spd };
            o.elbow[i] = .{ o.hand[i][0] * 0.5 - face * 1.2, -15.0 };
        }
        bob += -@abs(@sin(gait)) * 1.2 * spd;
    } else if (p.vy < 0) { // rising: one knee up, arms thrown forward
        o.foot[0] = .{ face * 3.0, -4.0 };
        o.knee[0] = .{ face * 6.0, -8.5 };
        o.foot[1] = .{ -face * 2.5, -1.0 };
        o.knee[1] = .{ -face * 1.0, -5.5 };
        o.hand[0] = .{ face * 6.0, -22.0 };
        o.hand[1] = .{ -face * 3.0, -21.5 };
        o.elbow[0] = .{ face * 3.5, -19.0 };
        o.elbow[1] = .{ -face * 2.0, -18.0 };
        lean = face * 1.0;
    } else if (p.jh) { // gliding: arms out, a loose thread on the wind
        o.foot[0] = .{ face * 1.2, -0.5 };
        o.foot[1] = .{ -face * 1.2, -0.5 };
        o.knee[0] = .{ face * 1.0, -5.5 };
        o.knee[1] = .{ -face * 1.0, -5.5 };
        o.hand[0] = .{ 9.5, -20.5 };
        o.hand[1] = .{ -9.5, -20.5 };
        o.elbow[0] = .{ 5.0, -18.5 };
        o.elbow[1] = .{ -5.0, -18.5 };
    } else { // falling: arms up, legs hanging
        o.foot[0] = .{ 2.6, -0.5 };
        o.foot[1] = .{ -2.6, -0.5 };
        o.knee[0] = .{ 2.2, -5.5 };
        o.knee[1] = .{ -2.2, -5.5 };
        o.hand[0] = .{ 6.0, -25.0 };
        o.hand[1] = .{ -6.0, -25.0 };
        o.elbow[0] = .{ 4.0, -21.0 };
        o.elbow[1] = .{ -4.0, -21.0 };
    }
    o.hip = .{ 0.0, -11.0 + bob };
    o.neck = .{ lean, -19.0 + bob };
    o.head = .{ lean * 1.25, -22.0 + bob };
    return o;
}

// ---------------------------------------------------------------- sparks, dust, threads
const Part = struct { x: f32, y: f32, vx: f32, vy: f32, life: f32, max: f32, kind: u8, col: u32 };
const NPART = 192;
pub const GUIDE_EVERY: u32 = 0; // 0: always the wanderer. n: every n-th run is the guide's.

pub const Stage = struct {
    env: D.Env,
    look: Look,
    wander: D.Wander,
    guide: D.Guide,
    base: u64,
    run: u32,
    mode: u8, // 0 wander, 1 guide
    phase: u8, // 0 weaving in, 1 waiting, 2 running, 3 ending, 4 unweaving
    ptime: f32,
    reveal: f32,
    acc: f32,
    clock: f32,
    gait: f32,
    prev_vy: i32,
    trail: [48][2]f32,
    trail_n: u32,
    trail_tick: u32,
    parts: [NPART]Part,
    pnext: u32,
    hist: [20]u8, // oldest first: 1 won, 2 fell, 3 timed out
    flash_x: f32,
    flash_t: f32,
    vis_fall: f32, // px the thread has sunk into the fringe since the fall was decided (drawing only)

    pub fn init(self: *Stage, seed: u64) void {
        @memset(std.mem.asBytes(self), 0);
        self.look.build();
        self.base = seed;
        self.begin();
    }

    fn begin(self: *Stage) void {
        const s = D.mixSeed(self.base +% @as(u64, self.run) *% 0x9E3779B97F4A7C15);
        self.env.reset(s);
        self.wander = D.Wander.init(s, 12, 60);
        self.guide = .{};
        self.mode = if (GUIDE_EVERY != 0 and self.run % GUIDE_EVERY == GUIDE_EVERY - 1) 1 else 0;
        self.phase = 0;
        self.ptime = 0;
        self.reveal = 0;
        self.acc = 0;
        self.trail_n = 0;
        self.gait = 0;
        self.flash_t = 0;
        self.vis_fall = 0;
    }

    fn spawn(self: *Stage, x: f32, y: f32, vx: f32, vy: f32, life: f32, kind: u8, col: u32) void {
        self.parts[self.pnext % NPART] = .{ .x = x, .y = y, .vx = vx, .vy = vy, .life = life, .max = life, .kind = kind, .col = col };
        self.pnext +%= 1;
    }

    fn rnd(self: *Stage) f32 { // a cheap noise stream for effects, tied to the clock so it stays deterministic
        self.pnext +%= 0x9E37;
        const v = D.mixSeed(@as(u64, self.pnext) *% 0x2545F4914F6CDD1D +% self.run);
        return @as(f32, @floatFromInt(v >> 40)) / 16777216.0;
    }

    fn feetPx(self: *const Stage) [2]f32 {
        return .{ fl(self.env.p.x) / 256.0, fl(self.env.p.y) / 256.0 };
    }

    fn burst(self: *Stage, n: u32, kind: u8, col: u32, speed: f32, up: f32) void {
        const f = self.feetPx();
        for (0..n) |_| {
            const a = self.rnd() * 6.2832;
            const s = speed * (0.35 + 0.65 * self.rnd());
            self.spawn(f[0], f[1] - 10.0, @cos(a) * s, @sin(a) * s - up, 0.8 + 1.2 * self.rnd(), kind, col);
        }
    }

    pub fn step(self: *Stage, dt_raw: f32) void {
        const dt = std.math.clamp(dt_raw, 0.0, 0.1); // a sleeping panel must not fast-forward the thread
        self.clock += dt;
        if (self.flash_t > 0) self.flash_t -= dt;
        for (&self.parts) |*q| { // light and dust, 60 Hz-ish: scaled by dt so frame rate does not matter
            if (q.life <= 0) continue;
            q.life -= dt;
            q.x += q.vx * dt;
            q.y += q.vy * dt;
            if (q.kind == 0 or q.kind == 1) q.vy += 140.0 * dt; // dust and sparks fall
            if (q.kind == 2) q.vx *= 1.0 - 1.5 * dt; // threads drift down, slowly
        }
        switch (self.phase) {
            0 => {
                self.reveal += dt * (@as(f32, H) / 1.4);
                if (self.reveal >= H) {
                    self.reveal = H;
                    self.phase = 1;
                    self.ptime = 0;
                }
            },
            1 => {
                self.ptime += dt;
                if (self.ptime > 0.8) self.phase = 2;
            },
            2 => {
                self.acc += dt;
                var guard: u32 = 0;
                while (self.acc >= 1.0 / 120.0 and guard < 16 and self.env.out == .running) : (guard += 1) {
                    self.acc -= 1.0 / 120.0;
                    const act = if (self.mode == 1) self.guide.next(&self.env.w, &self.env.p) else self.wander.next();
                    self.prev_vy = self.env.p.vy;
                    self.env.step(act);
                    const p = &self.env.p;
                    if (p.ground) self.gait += @abs(fl(p.vx)) / 256.0 / 30.0 * 6.2832;
                    if (p.ev & 2 != 0 and self.prev_vy > 500) {
                        const f = self.feetPx();
                        const row: usize = @intCast(std.math.clamp(p.y >> D.SUBSHIFT, 0, H - 1));
                        for (0..4) |_| self.spawn(f[0], f[1] - 1.0, (self.rnd() - 0.5) * 70.0, -10.0 - 30.0 * self.rnd(), 0.35 + 0.3 * self.rnd(), 0, self.look.thermal[row]);
                    }
                    self.trail_tick += 1;
                    if (self.trail_tick % 4 == 0) {
                        const f = self.feetPx();
                        if (self.trail_n < 48) {
                            self.trail[self.trail_n] = .{ f[0], f[1] - 11.0 };
                            self.trail_n += 1;
                        } else {
                            std.mem.copyForwards([2]f32, self.trail[0..47], self.trail[1..48]);
                            self.trail[47] = .{ f[0], f[1] - 11.0 };
                        }
                    }
                }
                if (self.env.out != .running) {
                    self.phase = 3;
                    self.ptime = 0;
                    var i: usize = 0;
                    while (i < 19) : (i += 1) self.hist[i] = self.hist[i + 1];
                    self.hist[19] = switch (self.env.out) {
                        .won => 1,
                        .fell => 2,
                        else => 3,
                    };
                    if (self.env.out == .won) {
                        self.burst(60, 1, sdk.packRGBA(255, 214, 138), 210.0, 90.0);
                        self.burst(40, 1, sdk.packRGBA(255, 246, 226), 120.0, 140.0);
                    } else if (self.env.out == .fell) {
                        const f = self.feetPx();
                        self.flash_x = f[0];
                        self.flash_t = 1.6;
                        for (0..56) |_| { // the thread comes undone: loose warp, pearl and blue, drifting down through the fringe
                            const c = if (self.rnd() < 0.5) sdk.packRGBA(208, 232, 255) else sdk.packRGBA(120, 150, 255);
                            self.spawn(f[0] + (self.rnd() - 0.5) * 18.0, f[1] - 20.0 * self.rnd(), (self.rnd() - 0.5) * 10.0, 30.0 + 90.0 * self.rnd(), 1.1 + 1.6 * self.rnd(), 2, c);
                        }
                    }
                }
            },
            3 => {
                self.ptime += dt;
                if (self.env.out == .fell) self.vis_fall += 520.0 * dt;
                if (self.ptime > 3.4) {
                    self.phase = 4;
                    self.ptime = 0;
                }
            },
            else => {
                self.reveal -= dt * (@as(f32, H) / 0.9);
                if (self.reveal <= 0) {
                    self.run +%= 1;
                    self.begin();
                }
            },
        }
    }

    pub const draw = drawStage;
};

// ---------------------------------------------------------------- drawing the whole stage
fn pip(buf: []u32, stride: usize, w: usize, h: usize, cx: i32, cy: i32, kind: u8, k: u32) void { // a history mark: shapes, no words
    var dy: i32 = -6;
    while (dy <= 6) : (dy += 1) {
        var dx: i32 = -6;
        while (dx <= 6) : (dx += 1) {
            const ad = @as(i32, @intCast(@abs(dx))) + @as(i32, @intCast(@abs(dy)));
            const r2 = dx * dx + dy * dy;
            const on = switch (kind) {
                1 => ad <= 6, // a diamond: the thread reached the pad
                2 => dy >= -5 and dy <= 5 and @as(i32, @intCast(@abs(dx))) * 2 <= 5 - dy, // a triangle pointing down: it fell
                3 => r2 <= 36 and r2 >= 16, // a ring: it ran out of time
                else => dx == 0 and dy == 0,
            };
            if (!on) continue;
            const col = switch (kind) {
                1 => sdk.packRGBA(255, 214, 138),
                2 => sdk.packRGBA(232, 96, 172),
                3 => sdk.packRGBA(120, 140, 236),
                else => sdk.packRGBA(90, 100, 150),
            };
            const x = cx + dx;
            const y = cy + dy;
            if (x < 0 or y < 0 or x >= @as(i32, @intCast(w)) or y >= @as(i32, @intCast(h))) continue;
            buf[@as(usize, @intCast(y)) * stride + @as(usize, @intCast(x))] = sdk.scaleRGB(col, k);
        }
    }
}

pub fn drawStage(self: *const Stage, buf: []u32, stride: usize, w: usize, h: usize, oy: i32) void {
    const ox: i32 = @divTrunc(@as(i32, @intCast(w)) - W * 8, 2);
    drawLevel(&self.look, &self.env.w, buf, stride, w, h, ox, oy, @intFromFloat(self.reveal), self.clock);
    const line_y: i32 = oy + D.LINE_ROW * 8;
    const oxf: f32 = fl(ox);
    const oyf: f32 = fl(oy);

    if (self.reveal > 0 and self.reveal < H) { // the weft that is laying the level down
        const y: i32 = oy + @as(i32, @intFromFloat(self.reveal)) * 8;
        var x: i32 = ox;
        while (x < ox + W * 8) : (x += 1) {
            addPx(buf, stride, w, h, x, y, sdk.packRGBA(220, 226, 255));
            addPx(buf, stride, w, h, x, y - 1, sdk.packRGBA(120, 130, 200));
            addPx(buf, stride, w, h, x, y + 1, sdk.packRGBA(60, 66, 110));
        }
    }
    if (self.flash_t > 0) { // a thread has gone through the reed: the line flares where it went
        const a = std.math.clamp(self.flash_t / 1.6, 0.0, 1.0);
        var dx: i32 = -260;
        while (dx <= 260) : (dx += 1) {
            const f = (1.0 - @abs(fl(dx)) / 260.0) * a;
            const c = sdk.scaleRGB(sdk.packRGBA(255, 240, 214), @min(@as(u32, 256), @as(u32, @intFromFloat(f * f * 420.0))));
            const x: i32 = @as(i32, @intFromFloat(self.flash_x)) + ox + dx;
            addPx(buf, stride, w, h, x, line_y - 2, sdk.scaleRGB(c, 90));
            addPx(buf, stride, w, h, x, line_y - 1, c);
            addPx(buf, stride, w, h, x, line_y, c);
            addPx(buf, stride, w, h, x, line_y + 1, c);
            addPx(buf, stride, w, h, x, line_y + 2, sdk.scaleRGB(c, 120));
            addPx(buf, stride, w, h, x, line_y + 4, sdk.scaleRGB(c, 50));
        }
    }
    if (self.phase == 3 and self.env.out == .won) { // a column of light stands over the pad
        const wd = &self.env.w;
        const k = std.math.clamp(1.0 - self.ptime / 3.4, 0.0, 1.0);
        const x0: i32 = ox + wd.pad_c0 * 8;
        const x1: i32 = ox + (wd.pad_c1 + 1) * 8;
        var y: i32 = 0;
        while (y < 420) : (y += 1) {
            const fy = 1.0 - fl(y) / 420.0;
            const base: f32 = fy * fy * k * 74.0;
            var x = x0;
            while (x < x1) : (x += 1) {
                const edge = @min(1.0, fl(@min(x - x0, x1 - x)) / 40.0);
                addPx(buf, stride, w, h, x, oy + D.PAD_TOP * 8 - y, pack3(.{ 255.0, 226, 160 }, base * edge / 255.0));
            }
        }
    }
    if (self.phase >= 1 and self.phase <= 3 and !(self.env.out == .fell and self.ptime > 0.5)) {
        const n = self.trail_n;
        if (n > 1) { // the thread he leaves: gold where it is new, violet where it is old
            for (1..n) |i| {
                const age = @as(f32, @floatFromInt(n - 1 - i)) / 48.0;
                const col = sdk.lerpRGB(sdk.packRGBA(255, 210, 130), sdk.packRGBA(110, 80, 220), @intFromFloat(@min(1.0, age * 1.4) * 255.0));
                const c = sdk.scaleRGB(col, @intFromFloat((1.0 - age) * 150.0));
                aseg(buf, stride, w, h, .{ self.trail[i - 1][0] + oxf, self.trail[i - 1][1] + oyf }, .{ self.trail[i][0] + oxf, self.trail[i][1] + oyf }, c);
            }
        }
        const fp = self.feetPx();
        const fx = fp[0] + oxf;
        const fy = fp[1] + oyf + self.vis_fall;
        const fade: u32 = if (self.env.out == .fell) @intFromFloat(std.math.clamp(1.0 - self.ptime / 0.5, 0.0, 1.0) * 256.0) else 256;
        const q = pose(&self.env.p, self.gait, self.clock);
        const body = sdk.scaleRGB(sdk.packRGBA(236, 244, 255), fade);
        const warm = sdk.scaleRGB(sdk.packRGBA(255, 214, 150), fade);
        const P = struct {
            const SC: f32 = 1.75; // drawn 1.75x so he reads on a 1080 panel; the hitbox stays 24 px
            fn at(px: f32, py: f32, v: [2]f32) [2]f32 {
                return .{ px + v[0] * SC, py + v[1] * SC };
            }
        };
        glow(buf, stride, w, h, fx + q.hip[0] * P.SC, fy + q.hip[1] * P.SC, 22.0, .{ 70.0, 46.0, 18.0 }); // a small halo of light
        for (0..2) |i| {
            seg(buf, stride, w, h, P.at(fx, fy, q.hip), P.at(fx, fy, q.knee[i]), if (i == 0) body else sdk.scaleRGB(body, 200));
            seg(buf, stride, w, h, P.at(fx, fy, q.knee[i]), P.at(fx, fy, q.foot[i]), if (i == 0) body else sdk.scaleRGB(body, 200));
            seg(buf, stride, w, h, P.at(fx, fy, q.neck), P.at(fx, fy, q.elbow[i]), if (i == 0) body else sdk.scaleRGB(body, 200));
            seg(buf, stride, w, h, P.at(fx, fy, q.elbow[i]), P.at(fx, fy, q.hand[i]), if (i == 0) body else sdk.scaleRGB(body, 200));
        }
        seg(buf, stride, w, h, P.at(fx, fy, q.hip), P.at(fx, fy, q.neck), body);
        disc(buf, stride, w, h, fx + q.head[0] * P.SC, fy + q.head[1] * P.SC, 4.4, warm, false);
    }
    for (self.parts) |q| { // sparks, dust, falling threads
        if (q.life <= 0) continue;
        const a = std.math.clamp(q.life / q.max, 0.0, 1.0);
        const c = sdk.scaleRGB(q.col, @intFromFloat(a * a * 255.0));
        const x: i32 = @as(i32, @intFromFloat(@floor(q.x + oxf)));
        const y: i32 = @as(i32, @intFromFloat(@floor(q.y + oyf)));
        if (q.kind == 2) {
            for (0..8) |d| addPx(buf, stride, w, h, x, y - @as(i32, @intCast(d)), sdk.scaleRGB(c, 256 - @as(u32, @intCast(d)) * 30));
        } else if (q.kind == 1) {
            addPx(buf, stride, w, h, x, y, c);
            inline for (.{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |o| addPx(buf, stride, w, h, x + o[0], y + o[1], sdk.scaleRGB(c, 140));
        } else {
            addPx(buf, stride, w, h, x, y, c);
            addPx(buf, stride, w, h, x + 1, y, sdk.scaleRGB(c, 150));
            addPx(buf, stride, w, h, x, y + 1, sdk.scaleRGB(c, 150));
        }
    }
    for (self.hist, 0..) |k, i| pip(buf, stride, w, h, ox + 28 + @as(i32, @intCast(i)) * 20, oy + 28, k, if (i == 19) 256 else 190);
    if (self.phase >= 1 and self.phase <= 2) pip(buf, stride, w, h, ox + 28 + 20 * 20, oy + 28, 0, @intFromFloat(140.0 + 100.0 * @sin(self.clock * 5.0))); // the run in progress
}

};

// ======================================================================= the theme
/// Textus underneath, Descensus on top. One allocation: the host State holds both by value.
pub const State = struct {
    w: usize,
    h: usize,
    active: bool, // the level is authored for a 1920 x 1080 panel; on anything smaller the cloth runs alone
    oy: i32, // puts level row 118 on the cloth's weaving line
    tx: Textus.Loom,
    ds: Draw.Stage,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        @memset(std.mem.asBytes(self), 0);
        self.tx.setup(w, h, scale, w >= 1920 and h >= 1080); // the level is shapes only, so the cloth drops its lettering beneath it
        self.w = self.tx.w;
        self.h = self.tx.h;
        self.active = self.w >= 1920 and self.h >= 1080;
        self.oy = @as(i32, @intCast(self.tx.line_y)) - Descensus.LINE_ROW * Descensus.CELL;
        if (self.active) self.ds.init(0xD35C3115);
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt_in: f64) void {
        self.tx.step(dt_in);
        if (self.active) self.ds.step(@floatCast(dt_in));
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        self.tx.draw(buf, stride);
        if (self.active) self.ds.draw(buf, stride, self.w, self.h, self.oy);
    }

    pub fn hasNaN(self: *const State) bool {
        return self.tx.hasNaN() or !std.math.isFinite(self.ds.clock) or !std.math.isFinite(self.ds.reveal);
    }
};

comptime {
    sdk.exportTheme(State);
}

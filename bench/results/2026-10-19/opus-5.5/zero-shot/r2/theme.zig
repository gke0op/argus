// themes/Opus55_RippleTank.zig
//
// ARGUS-BENCH Track B (Field Dynamics): a live ripple tank.
// The damped 2D wave equation u_tt = c^2 * lap(u) - gamma * u_t is integrated
// with a leapfrog (Stormer-Verlet) scheme on a coarse grid (one cell per 8x8
// pixels). Two oscillating emitters drift along slow Lissajous orbits and
// produce moving interference fringes (with Doppler compression), while
// randomly timed raindrops add expanding rings. The surface is lit like a
// shadowgraph: slope lighting + a specular lobe + a caustic (focusing) term
// proportional to -lap(u). Per-cell shading is computed in step(); draw() is
// pure fixed-point bilinear interpolation plus a 1024-entry palette lookup.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
const CELL: usize = 8;
const MAX_GW: usize = MAX_W / CELL + 2;
const MAX_GH: usize = MAX_H / CELL + 2;
const MAX_GN: usize = MAX_GW * MAX_GH;
const PAL_N: usize = 1024;

const SUB_DT: f64 = 0.008;
const COURANT: f32 = 0.30; // c^2 dt^2 / dx^2, must stay <= 0.5 in 2D
const DAMP: f32 = 0.9965;
const H_LIMIT: f32 = 6.0;

fn toU8(v: f32) u8 {
    const c = math.clamp(v, 0.0, 255.0);
    return @intFromFloat(c);
}

pub const State = struct {
    w: usize,
    h: usize,
    gw: usize,
    gh: usize,
    scale: f64,
    time_sec: f64,
    acc: f64,
    next_drop: f64,
    rng: u64,
    flip: bool,

    ha: [MAX_GN]f32,
    hb: [MAX_GN]f32,
    cell: [MAX_GN]i32,
    palette: [PAL_N]u32,
    row_off: [MAX_H]i32,
    col_off: [MAX_W]i32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @max(@as(usize, 1), @min(w, MAX_W));
        self.h = @max(@as(usize, 1), @min(h, MAX_H));
        self.gw = (self.w / CELL) + 2;
        self.gh = (self.h / CELL) + 2;
        self.scale = scale;
        self.time_sec = 0.0;
        self.acc = 0.0;
        self.next_drop = 0.05;
        self.rng = 0x9E3779B97F4A7C15;
        self.flip = false;

        self.ha = @splat(0.0);
        self.hb = @splat(0.0);
        self.cell = @splat(0);
        self.row_off = @splat(0);
        self.col_off = @splat(0);

        // Palette: abyssal navy -> deep teal -> cyan -> white highlight.
        const stops = [_][4]f32{
            .{ 0.00, 1.0, 3.0, 10.0 },
            .{ 0.30, 4.0, 22.0, 44.0 },
            .{ 0.45, 10.0, 58.0, 90.0 },
            .{ 0.62, 30.0, 120.0, 160.0 },
            .{ 0.80, 110.0, 205.0, 230.0 },
            .{ 1.00, 245.0, 252.0, 255.0 },
        };
        for (0..PAL_N) |pi| {
            const t: f32 = @as(f32, @floatFromInt(pi)) / @as(f32, @floatFromInt(PAL_N - 1));
            var k: usize = 0;
            while (k + 2 < stops.len and t > stops[k + 1][0]) : (k += 1) {}
            const s0 = stops[k];
            const s1 = stops[k + 1];
            const q = math.clamp((t - s0[0]) / (s1[0] - s0[0]), 0.0, 1.0);
            const qs = q * q * (3.0 - 2.0 * q);
            const r = s0[1] + (s1[1] - s0[1]) * qs;
            const g = s0[2] + (s1[2] - s0[2]) * qs;
            const b = s0[3] + (s1[3] - s0[3]) * qs;
            self.palette[pi] = sdk.packRGBA(toU8(r), toU8(g), toU8(b));
        }

        // Separable vignette expressed as palette-index offsets.
        const fh: f32 = @floatFromInt(self.h);
        const fw: f32 = @floatFromInt(self.w);
        for (0..self.h) |y| {
            const fy: f32 = @floatFromInt(y);
            const ny = ((fy + 0.5) / fh) * 2.0 - 1.0;
            self.row_off[y] = @intFromFloat(-150.0 * ny * ny - 30.0 * ny);
        }
        for (0..self.w) |x| {
            const fx: f32 = @floatFromInt(x);
            const nx = ((fx + 0.5) / fw) * 2.0 - 1.0;
            self.col_off[x] = @intFromFloat(-150.0 * nx * nx);
        }

        for (0..6) |_| self.spawnDrop();
        self.shade();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn rnd(self: *State) f64 {
        var x = self.rng;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng = x;
        return @as(f64, @floatFromInt(x >> 11)) * (1.0 / 9007199254740992.0);
    }

    fn spawnDrop(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        if (gw < 10 or gh < 10) return;
        const gw_i: isize = @intCast(gw);
        const gh_i: isize = @intCast(gh);
        const cx: isize = 3 + @as(isize, @intFromFloat(self.rnd() * @as(f64, @floatFromInt(gw - 6))));
        const cy: isize = 3 + @as(isize, @intFromFloat(self.rnd() * @as(f64, @floatFromInt(gh - 6))));
        const amp: f32 = @floatCast(-(1.2 + 2.0 * self.rnd()));
        const rad: f32 = @floatCast(1.2 + 1.3 * self.rnd());
        const inv = 1.0 / (rad * rad);
        var dy: isize = -4;
        while (dy <= 4) : (dy += 1) {
            var dx: isize = -4;
            while (dx <= 4) : (dx += 1) {
                const xx = cx + dx;
                const yy = cy + dy;
                if (xx < 1 or yy < 1 or xx >= gw_i - 1 or yy >= gh_i - 1) continue;
                const d2: f32 = @floatFromInt(dx * dx + dy * dy);
                const v = amp * @exp(-d2 * inv);
                const idx = @as(usize, @intCast(yy)) * gw + @as(usize, @intCast(xx));
                self.ha[idx] += v;
                self.hb[idx] += v;
            }
        }
    }

    fn splat(self: *State, field: *[MAX_GN]f32, px: f64, py: f64, a: f32) void {
        const gw = self.gw;
        const flx = @floor(px);
        const fly = @floor(py);
        if (!(flx >= 1.0 and fly >= 1.0)) return;
        const ix: isize = @intFromFloat(@min(flx, 1.0e6));
        const iy: isize = @intFromFloat(@min(fly, 1.0e6));
        if (ix + 2 >= @as(isize, @intCast(gw)) or iy + 2 >= @as(isize, @intCast(self.gh))) return;
        const tx: f32 = @floatCast(px - flx);
        const ty: f32 = @floatCast(py - fly);
        const idx = @as(usize, @intCast(iy)) * gw + @as(usize, @intCast(ix));
        field[idx] += a * (1.0 - tx) * (1.0 - ty);
        field[idx + 1] += a * tx * (1.0 - ty);
        field[idx + gw] += a * (1.0 - tx) * ty;
        field[idx + gw + 1] += a * tx * ty;
    }

    fn substep(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const cur: *[MAX_GN]f32 = if (self.flip) &self.hb else &self.ha;
        const prv: *[MAX_GN]f32 = if (self.flip) &self.ha else &self.hb;

        // Two drifting coherent emitters.
        const t = self.time_sec;
        const fgw: f64 = @floatFromInt(gw);
        const fgh: f64 = @floatFromInt(gh);
        const sx0 = fgw * (0.5 + 0.28 * @cos(t * 0.21));
        const sy0 = fgh * (0.5 + 0.30 * @sin(t * 0.17));
        const sx1 = fgw * (0.5 + 0.30 * @cos(t * 0.13 + 2.4));
        const sy1 = fgh * (0.5 + 0.26 * @sin(t * 0.19 + 1.1));
        const amp0: f32 = @floatCast(0.22 * @sin(t * 30.0));
        const amp1: f32 = @floatCast(0.22 * @sin(t * 26.0 + 1.0));
        self.splat(cur, sx0, sy0, amp0);
        self.splat(cur, sx1, sy1, amp1);

        // Leapfrog update written in place into the previous buffer.
        for (1..gh - 1) |j| {
            const r = j * gw;
            for (1..gw - 1) |i| {
                const k = r + i;
                const c = cur[k];
                const lap = cur[k - 1] + cur[k + 1] + cur[k - gw] + cur[k + gw] - 4.0 * c;
                const nv = (2.0 * c - prv[k] + COURANT * lap) * DAMP;
                prv[k] = math.clamp(nv, -H_LIMIT, H_LIMIT);
            }
        }
        self.flip = !self.flip;
    }

    fn shade(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const cur: *const [MAX_GN]f32 = if (self.flip) &self.hb else &self.ha;
        for (0..gh) |j| {
            const jm = if (j > 0) j - 1 else j;
            const jp = if (j + 1 < gh) j + 1 else j;
            for (0..gw) |i| {
                const im = if (i > 0) i - 1 else i;
                const ip = if (i + 1 < gw) i + 1 else i;
                const hc = cur[j * gw + i];
                const hl = cur[j * gw + im];
                const hr = cur[j * gw + ip];
                const hu = cur[jm * gw + i];
                const hd = cur[jp * gw + i];
                const gx = hr - hl;
                const gy = hd - hu;
                const lap = hl + hr + hu + hd - 4.0 * hc;
                const s = 0.6 * gx + 0.8 * gy;
                const sp = @max(s, 0.0);
                const f = 0.42 + s * 0.22 + sp * sp * 0.25 - lap * 0.12 + hc * 0.03;
                const fc = math.clamp(f, -1.0, 2.0);
                self.cell[j * gw + i] = @intFromFloat(fc * 1023.0);
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        const d: f64 = if (math.isNan(dt) or dt < 0.0) 0.0 else @min(dt, 0.1);
        self.acc += d;
        var n: u32 = 0;
        while (self.acc >= SUB_DT * 0.999 and n < 6) : (n += 1) {
            self.acc -= SUB_DT;
            self.time_sec += SUB_DT;
            while (self.time_sec >= self.next_drop) {
                self.spawnDrop();
                self.next_drop += 0.12 + 0.45 * self.rnd();
            }
            self.substep();
        }
        if (self.acc < 0.0) self.acc = 0.0;
        if (self.acc > SUB_DT * 4.0) self.acc = 0.0;
        self.shade();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const gw = self.gw;
        var rowv: [MAX_GW]i32 = undefined;
        for (0..h) |y| {
            const cy = y / CELL;
            const fy: i32 = @intCast(y % CELL);
            const r0 = cy * gw;
            const r1 = r0 + gw;
            for (0..gw) |i| {
                const a = self.cell[r0 + i];
                const b = self.cell[r1 + i];
                rowv[i] = a + ((b - a) * fy >> 3);
            }
            const ro = self.row_off[y];
            const dst = buf[y * stride .. y * stride + w];
            var x: usize = 0;
            var cx: usize = 0;
            while (x < w) : (cx += 1) {
                const a = rowv[cx];
                const dl = rowv[cx + 1] - a;
                const end = @min(x + CELL, w);
                var k: i32 = 0;
                while (x < end) : ({
                    x += 1;
                    k += 1;
                }) {
                    var v: i32 = a + ((dl * k) >> 3) + ro + self.col_off[x];
                    if (v < 0) v = 0;
                    if (v > 1023) v = 1023;
                    const idx: usize = @intCast(v);
                    dst[x] = self.palette[idx];
                }
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        const n = self.gw * self.gh;
        for (self.ha[0..n], self.hb[0..n]) |a, b| {
            if (math.isNan(a) or math.isInf(a) or math.isNan(b) or math.isInf(b)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

// Track B: Gray-Scott reaction-diffusion on a periodic 384x240 grid.
//   du/dt = Du lap(u) - u v^2 + F (1 - u)
//   dv/dt = Dv lap(v) + u v^2 - (F + k) v
// Integrated with a 9-point Laplacian and explicit Euler (dt = 1 per substep, Du and Dv
// below 0.25, so it is stable). Each step() runs SUBSTEPS substeps of the fixed 0.008 s
// frame; the field is stored at 1/5 resolution and bilinearly sampled into the 1920x1200
// framebuffer in draw(), where V is mapped through a 256-entry deep-water palette.

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const GW: usize = 384;
pub const GH: usize = 240;
pub const GCELLS: usize = GW * GH;
pub const SUBSTEPS: usize = 4;
pub const WARMUP_SUBSTEPS: usize = 1500;

const DU: f32 = 0.2097;
const DV: f32 = 0.105;
const FEED: f32 = 0.0545;
const KILL: f32 = 0.062;

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    seed: u32,

    u: [GCELLS]f32,
    v: [GCELLS]f32,
    u_next: [GCELLS]f32,
    v_next: [GCELLS]f32,

    // Periodic neighbour indices, so the inner loop has no boundary branches.
    xm: [GW]usize,
    xp: [GW]usize,
    ym: [GH]usize,
    yp: [GH]usize,

    // Palette and screen-to-grid sampling tables, built for the w x h given to init().
    pal: [256]u32,
    col_x0: [MAX_W]usize,
    col_x1: [MAX_W]usize,
    col_wx: [MAX_W]f32,
    row_y0: [MAX_H]usize,
    row_y1: [MAX_H]usize,
    row_wy: [MAX_H]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.seed = 0x9E3779B9;

        for (0..GW) |x| {
            self.xm[x] = if (x == 0) GW - 1 else x - 1;
            self.xp[x] = if (x + 1 == GW) 0 else x + 1;
        }
        for (0..GH) |y| {
            self.ym[y] = if (y == 0) GH - 1 else y - 1;
            self.yp[y] = if (y + 1 == GH) 0 else y + 1;
        }

        self.seedField();
        for (0..WARMUP_SUBSTEPS) |_| self.substep();
        self.buildPalette();
        self.buildMapping();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn rand(self: *State) u32 {
        var s = self.seed;
        s ^= s << 13;
        s ^= s >> 17;
        s ^= s << 5;
        self.seed = s;
        return s;
    }

    fn seedField(self: *State) void {
        for (0..GCELLS) |i| {
            self.u[i] = 1.0;
            self.v[i] = 0.0;
        }
        // Deterministic blobs of reactant, wrapped at the edges.
        for (0..150) |_| {
            const cx: isize = @intCast(self.rand() % GW);
            const cy: isize = @intCast(self.rand() % GH);
            const r: isize = 3 + @as(isize, @intCast(self.rand() % 4));
            var dy: isize = -r;
            while (dy <= r) : (dy += 1) {
                var dx: isize = -r;
                while (dx <= r) : (dx += 1) {
                    if (dx * dx + dy * dy > r * r) continue;
                    const xi: usize = @intCast(@mod(cx + dx, @as(isize, GW)));
                    const yi: usize = @intCast(@mod(cy + dy, @as(isize, GH)));
                    const idx = yi * GW + xi;
                    const jit: f32 = @floatFromInt(self.rand() % 1000);
                    self.u[idx] = 0.5;
                    self.v[idx] = 0.2 + 0.1 * jit / 1000.0;
                }
            }
        }
    }

    fn substep(self: *State) void {
        for (0..GH) |y| {
            const rc = y * GW;
            const r0 = self.ym[y] * GW;
            const r1 = self.yp[y] * GW;
            for (0..GW) |x| {
                const l = self.xm[x];
                const rt = self.xp[x];
                const c = rc + x;
                const uc = self.u[c];
                const vc = self.v[c];

                const lap_u: f32 = 0.2 * (self.u[r0 + x] + self.u[r1 + x] + self.u[rc + l] + self.u[rc + rt]) +
                    0.05 * (self.u[r0 + l] + self.u[r0 + rt] + self.u[r1 + l] + self.u[r1 + rt]) - uc;
                const lap_v: f32 = 0.2 * (self.v[r0 + x] + self.v[r1 + x] + self.v[rc + l] + self.v[rc + rt]) +
                    0.05 * (self.v[r0 + l] + self.v[r0 + rt] + self.v[r1 + l] + self.v[r1 + rt]) - vc;

                const uvv = uc * vc * vc;
                const un = uc + DU * lap_u - uvv + FEED * (1.0 - uc);
                const vn = vc + DV * lap_v + uvv - (FEED + KILL) * vc;
                self.u_next[c] = std.math.clamp(un, 0.0, 1.0);
                self.v_next[c] = std.math.clamp(vn, 0.0, 1.0);
            }
        }
        @memcpy(self.u[0..], self.u_next[0..]);
        @memcpy(self.v[0..], self.v_next[0..]);
    }

    fn buildPalette(self: *State) void {
        // Deep water -> indigo -> teal -> pale gold, four stops.
        const stops = [_]u32{
            sdk.packRGBA(2, 4, 14),
            sdk.packRGBA(34, 24, 96),
            sdk.packRGBA(22, 150, 168),
            sdk.packRGBA(255, 226, 150),
        };
        for (0..256) |i| {
            const seg: usize = @min(i / 86, 2);
            const within: u32 = @intCast(((i - seg * 86) * 256) / 86);
            self.pal[i] = sdk.lerpRGB(stops[seg], stops[seg + 1], within);
        }
    }

    fn buildMapping(self: *State) void {
        const w_f: f64 = @floatFromInt(self.w);
        const h_f: f64 = @floatFromInt(self.h);
        for (0..self.w) |x| {
            const fx: f64 = (@as(f64, @floatFromInt(x)) + 0.5) * @as(f64, @floatFromInt(GW)) / w_f - 0.5;
            const fl: f64 = @floor(fx);
            const ifl: isize = @intFromFloat(fl);
            const col0: usize = @intCast(@mod(ifl, @as(isize, GW)));
            const wx: f32 = @floatCast(fx - fl);
            self.col_x0[x] = col0;
            self.col_x1[x] = self.xp[col0];
            self.col_wx[x] = wx;
        }
        for (0..self.h) |y| {
            const fy: f64 = (@as(f64, @floatFromInt(y)) + 0.5) * @as(f64, @floatFromInt(GH)) / h_f - 0.5;
            const fl: f64 = @floor(fy);
            const ifl: isize = @intFromFloat(fl);
            const j0: usize = @intCast(@mod(ifl, @as(isize, GH)));
            const wy: f32 = @floatCast(fy - fl);
            self.row_y0[y] = j0;
            self.row_y1[y] = self.yp[j0];
            self.row_wy[y] = wy;
        }
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        for (0..SUBSTEPS) |_| self.substep();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        for (0..self.h) |y| {
            const dst_row = buf[y * stride .. y * stride + self.w];
            const ra = self.row_y0[y] * GW;
            const rb = self.row_y1[y] * GW;
            const wy: f32 = self.row_wy[y];
            for (dst_row, 0..) |*dst, x| {
                const x0 = self.col_x0[x];
                const x1 = self.col_x1[x];
                const wx = self.col_wx[x];
                const a = self.v[ra + x0];
                const b = self.v[ra + x1];
                const c = self.v[rb + x0];
                const d = self.v[rb + x1];
                const top = a + (b - a) * wx;
                const bot = c + (d - c) * wx;
                const val = top + (bot - top) * wy;
                const scaled: f32 = std.math.clamp(val * 520.0, 0.0, 255.0);
                const pi: usize = @intFromFloat(scaled);
                dst.* = self.pal[pi];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        for (self.v) |val| {
            if (math.isNan(val) or math.isInf(val)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

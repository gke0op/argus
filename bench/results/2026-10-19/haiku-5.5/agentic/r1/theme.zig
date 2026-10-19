const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

// Track B: Gray-Scott reaction-diffusion (Pearson 1993) with a spatially varying feed rate.
// The PDE runs on a coarse periodic GW x GH lattice in step(dt); draw() bilinearly upsamples the
// V field to the framebuffer and maps it through a fixed palette.

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

pub const GW: usize = 480;
pub const GH: usize = 300;
pub const GN: usize = GW * GH;

const DU: f32 = 0.2097; // diffusion of U
const DV: f32 = 0.105; // diffusion of V
const KILL: f32 = 0.0605; // V removal rate
const DT: f32 = 1.0; // Euler step per substep (stable with the 9-point Laplacian below)
const SUBSTEPS: usize = 6; // PDE iterations per frame (fixed dt of the harness is 0.008 s)
const WARMUP_STEPS: usize = 1400; // iterations run in init() so the first frame already has structure
const BRUSH_R: isize = 9;
const PAL_N: usize = 256;

const stops = [_][3]f32{
    .{ 2.0, 3.0, 12.0 },
    .{ 20.0, 18.0, 70.0 },
    .{ 70.0, 30.0, 140.0 },
    .{ 210.0, 70.0, 110.0 },
    .{ 255.0, 170.0, 90.0 },
    .{ 255.0, 245.0, 220.0 },
};

fn ramp(t: f32) u32 {
    const n: f32 = @floatFromInt(stops.len - 1);
    const s = std.math.clamp(t, 0.0, 1.0) * n;
    const seg: usize = @min(@as(usize, @intFromFloat(@floor(s))), stops.len - 2);
    const f = s - @as(f32, @floatFromInt(seg));
    const a = stops[seg];
    const b = stops[seg + 1];
    const r: u8 = @intFromFloat(a[0] + (b[0] - a[0]) * f);
    const g: u8 = @intFromFloat(a[1] + (b[1] - a[1]) * f);
    const bl: u8 = @intFromFloat(a[2] + (b[2] - a[2]) * f);
    return sdk.packRGBA(r, g, bl);
}

fn rngNext(s: *u32) u32 {
    var x = s.*;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    s.* = x;
    return x;
}

fn rngUnit(s: *u32) f32 {
    return @as(f32, @floatFromInt(rngNext(s) >> 8)) / 16777216.0;
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    cur: usize,

    // Ping-pong PDE buffers and the per-cell feed rate F(x, y). All fixed-size so that
    // alloc.create(State) is the only heap allocation (Gate 2).
    u_buf: [2][GN]f32,
    v_buf: [2][GN]f32,
    feed: [GN]f32,

    // Periodic neighbour tables: column indices, and row offsets already multiplied by GW.
    col_lf: [GW]usize,
    col_rt: [GW]usize,
    row_up: [GH]usize,
    row_dn: [GH]usize,

    // Bilinear sampling tables from framebuffer pixels to lattice cells.
    ix0: [MAX_W]usize,
    ix1: [MAX_W]usize,
    fx: [MAX_W]f32,
    iy0: [MAX_H]usize,
    iy1: [MAX_H]usize,
    fy: [MAX_H]f32,

    palette: [PAL_N]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @max(@as(usize, 1), @min(w, MAX_W));
        self.h = @max(@as(usize, 1), @min(h, MAX_H));
        self.scale = scale;
        self.time_sec = 0.0;
        self.cur = 0;

        for (0..GW) |x| {
            self.col_lf[x] = (x + GW - 1) % GW;
            self.col_rt[x] = (x + 1) % GW;
        }
        for (0..GH) |y| {
            self.row_up[y] = ((y + GH - 1) % GH) * GW;
            self.row_dn[y] = ((y + 1) % GH) * GW;
        }

        const gw_f: f64 = @floatFromInt(GW);
        const gh_f: f64 = @floatFromInt(GH);
        const w_f: f64 = @floatFromInt(self.w);
        const h_f: f64 = @floatFromInt(self.h);
        for (0..self.w) |x| {
            const sx = std.math.clamp((@as(f64, @floatFromInt(x)) + 0.5) * gw_f / w_f - 0.5, 0.0, gw_f - 1.0);
            const s0 = @floor(sx);
            const idx0: usize = @intFromFloat(s0);
            self.ix0[x] = idx0;
            self.ix1[x] = @min(idx0 + 1, GW - 1);
            self.fx[x] = @floatCast(sx - s0);
        }
        for (0..self.h) |y| {
            const sy = std.math.clamp((@as(f64, @floatFromInt(y)) + 0.5) * gh_f / h_f - 0.5, 0.0, gh_f - 1.0);
            const s0 = @floor(sy);
            const idx0: usize = @intFromFloat(s0);
            self.iy0[y] = idx0 * GW;
            self.iy1[y] = @min(idx0 + 1, GH - 1) * GW;
            self.fy[y] = @floatCast(sy - s0);
        }

        for (0..PAL_N) |i| {
            self.palette[i] = ramp(@as(f32, @floatFromInt(i)) / 255.0);
        }

        // Feed rate varies smoothly across the lattice, so neighbouring regions settle into
        // different Turing regimes (spots, mitosis-like cells, labyrinths).
        for (0..GH) |y| {
            const ang_y = 2.0 * math.pi * @as(f64, @floatFromInt(y)) / gh_f;
            for (0..GW) |x| {
                const ang_x = 2.0 * math.pi * @as(f64, @floatFromInt(x)) / gw_f;
                const f = 0.0385 + 0.0075 * @sin(3.0 * ang_x + 1.4 * @sin(ang_y));
                self.feed[y * GW + x] = @floatCast(f);
            }
        }

        // Deterministic seed: near-uniform U with faint noise, plus scattered V blobs.
        var seed: u32 = 0x2545F491;
        for (0..GN) |c| {
            self.u_buf[0][c] = 1.0 - 0.04 * rngUnit(&seed);
            self.v_buf[0][c] = 0.02 * rngUnit(&seed);
        }
        for (0..260) |_| {
            const cx: isize = @intCast(rngNext(&seed) % GW);
            const cy: isize = @intCast(rngNext(&seed) % GH);
            const rad: isize = @intCast(4 + rngNext(&seed) % 6);
            var dy: isize = -rad;
            while (dy <= rad) : (dy += 1) {
                var dx: isize = -rad;
                while (dx <= rad) : (dx += 1) {
                    if (dx * dx + dy * dy > rad * rad) continue;
                    const px = @mod(cx + dx, @as(isize, GW));
                    const py = @mod(cy + dy, @as(isize, GH));
                    const c: usize = @as(usize, @intCast(py)) * GW + @as(usize, @intCast(px));
                    self.u_buf[0][c] = 0.5;
                    self.v_buf[0][c] = 0.25 + 0.1 * rngUnit(&seed);
                }
            }
        }

        for (0..WARMUP_STEPS) |_| self.substep();
        self.time_sec = 0.0;
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    // One explicit Gray-Scott update of the whole lattice (9-point Laplacian, periodic).
    fn substep(self: *State) void {
        const src = self.cur;
        const dst = 1 - self.cur;
        const u_src = &self.u_buf[src];
        const v_src = &self.v_buf[src];
        const u_dst = &self.u_buf[dst];
        const v_dst = &self.v_buf[dst];

        for (0..GH) |y| {
            const row_c = y * GW;
            const row_u = self.row_up[y];
            const row_d = self.row_dn[y];
            for (0..GW) |x| {
                const xl = self.col_lf[x];
                const xr = self.col_rt[x];
                const c = row_c + x;
                const u = u_src[c];
                const v = v_src[c];
                const lap_u = 0.2 * (u_src[row_c + xl] + u_src[row_c + xr] + u_src[row_u + x] + u_src[row_d + x]) +
                    0.05 * (u_src[row_u + xl] + u_src[row_u + xr] + u_src[row_d + xl] + u_src[row_d + xr]) - u;
                const lap_v = 0.2 * (v_src[row_c + xl] + v_src[row_c + xr] + v_src[row_u + x] + v_src[row_d + x]) +
                    0.05 * (v_src[row_u + xl] + v_src[row_u + xr] + v_src[row_d + xl] + v_src[row_d + xr]) - v;
                const uvv = u * v * v;
                const f = self.feed[c];
                const un = u + DT * (DU * lap_u - uvv + f * (1.0 - u));
                const vn = v + DT * (DV * lap_v + uvv - (f + KILL) * v);
                u_dst[c] = std.math.clamp(un, 0.0, 1.0);
                v_dst[c] = std.math.clamp(vn, 0.0, 1.0);
            }
        }
        self.cur = dst;
    }

    // A slow Lissajous "stirrer" that deposits V and drains U, so the field keeps moving.
    fn brush(self: *State) void {
        const t = self.time_sec;
        const cxf = (0.5 + 0.36 * @cos(0.31 * t)) * @as(f64, GW);
        const cyf = (0.5 + 0.34 * @sin(0.23 * t)) * @as(f64, GH);
        const cx: isize = @intFromFloat(cxf);
        const cy: isize = @intFromFloat(cyf);
        const u = &self.u_buf[self.cur];
        const v = &self.v_buf[self.cur];

        var dy: isize = -BRUSH_R;
        while (dy <= BRUSH_R) : (dy += 1) {
            var dx: isize = -BRUSH_R;
            while (dx <= BRUSH_R) : (dx += 1) {
                const px = cx + dx;
                const py = cy + dy;
                if (px < 0 or py < 0 or px >= GW or py >= GH) continue;
                const d2: f32 = @floatFromInt(dx * dx + dy * dy);
                const g = @exp(-d2 / 12.0);
                const c: usize = @as(usize, @intCast(py)) * GW + @as(usize, @intCast(px));
                u[c] = std.math.clamp(u[c] - 0.25 * g, 0.0, 1.0);
                v[c] = std.math.clamp(v[c] + 0.3 * g, 0.0, 1.0);
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        self.brush();
        for (0..SUBSTEPS) |_| self.substep();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const field = &self.v_buf[self.cur];
        const w = self.w;
        for (0..self.h) |y| {
            const dst = buf[y * stride .. y * stride + w];
            const r0 = self.iy0[y];
            const r1 = self.iy1[y];
            const wy = self.fy[y];
            for (dst, 0..) |*px, x| {
                const c0 = self.ix0[x];
                const c1 = self.ix1[x];
                const wx = self.fx[x];
                const top = field[r0 + c0] + (field[r0 + c1] - field[r0 + c0]) * wx;
                const bot = field[r1 + c0] + (field[r1 + c1] - field[r1 + c0]) * wx;
                const val = top + (bot - top) * wy;
                const q: f32 = @min(val * 700.0, 255.0);
                px.* = self.palette[@as(usize, @intFromFloat(q))];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        const field = &self.v_buf[self.cur];
        for (field) |x| {
            if (!math.isFinite(x)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

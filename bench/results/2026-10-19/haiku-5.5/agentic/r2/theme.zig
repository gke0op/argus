// Track B: Gray-Scott reaction-diffusion (two coupled PDEs for U and V),
// integrated on a 480x300 periodic-free grid (Dirichlet borders) with a
// 9-point isotropic Laplacian and explicit Euler. The feed rate F is slowly
// modulated so the pattern keeps morphing (spots split, worms grow, coral
// fronts). Each cell is shaded by the gradient of V and drawn up to 1920x1200
// by nearest-cell lookup; all per-pixel work is one table read.
const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

pub const GW: usize = 480;
pub const GH: usize = 300;
pub const GN: usize = GW * GH;

const SUBSTEPS: usize = 4;
const PRE_ROLL: usize = 500;
const SEEDS: usize = 120;
const DU: f32 = 0.2097;
const DV: f32 = 0.105;
const F_BASE: f32 = 0.0545;
const F_SWING: f32 = 0.0045;
const K_RATE: f32 = 0.062;

fn hash64(x: u64) u64 {
    var z: u64 = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn unit(seed: u64) f32 {
    const bits: u64 = hash64(seed) >> 40;
    return @as(f32, @floatFromInt(bits)) / 16777216.0;
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,

    // Double-buffered field: ua[cur] / va[cur] hold the current state.
    ua: [2][GN]f32,
    va: [2][GN]f32,
    cur: usize,

    cell_rgb: [GN]u32,
    palette: [256]u32,
    col_map: [MAX_W]u16,
    row_map: [MAX_H]u16,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @max(@as(usize, 1), @min(w, MAX_W));
        self.h = @max(@as(usize, 1), @min(h, MAX_H));
        self.scale = scale;
        self.time_sec = 0.0;
        self.cur = 0;

        for (0..MAX_W) |x| {
            const cx: usize = @min(GW - 1, (x * GW) / self.w);
            self.col_map[x] = @intCast(cx);
        }
        for (0..MAX_H) |y| {
            const cy: usize = @min(GH - 1, (y * GH) / self.h);
            self.row_map[y] = @intCast(cy);
        }

        // Palette: abyss -> teal -> amber -> ivory, indexed by V level.
        const c_abyss = sdk.packRGBA(2, 4, 16);
        const c_teal = sdk.packRGBA(14, 110, 124);
        const c_amber = sdk.packRGBA(236, 160, 56);
        const c_ivory = sdk.packRGBA(255, 244, 222);
        for (0..256) |i| {
            const t: u32 = @intCast(i);
            const col = if (t < 110)
                sdk.lerpRGB(c_abyss, c_teal, t * 256 / 110)
            else if (t < 190)
                sdk.lerpRGB(c_teal, c_amber, (t - 110) * 256 / 80)
            else
                sdk.lerpRGB(c_amber, c_ivory, (t - 190) * 256 / 66);
            self.palette[i] = col;
        }

        // Uniform U=1, V=0, then scatter deterministic V-blobs.
        @memset(&self.ua[0], 1.0);
        @memset(&self.va[0], 0.0);
        for (0..SEEDS) |s| {
            const cxf: f32 = unit(@as(u64, s) * 4 + 1) * @as(f32, GW - 20) + 10.0;
            const cyf: f32 = unit(@as(u64, s) * 4 + 2) * @as(f32, GH - 20) + 10.0;
            const rad: f32 = 2.0 + unit(@as(u64, s) * 4 + 3) * 4.0;
            const y0: usize = @intFromFloat(@max(@as(f32, 1.0), cyf - rad));
            const y1: usize = @intFromFloat(@min(@as(f32, GH - 2), cyf + rad));
            const x0: usize = @intFromFloat(@max(@as(f32, 1.0), cxf - rad));
            const x1: usize = @intFromFloat(@min(@as(f32, GW - 2), cxf + rad));
            for (y0..y1 + 1) |y| {
                for (x0..x1 + 1) |x| {
                    const dx: f32 = @as(f32, @floatFromInt(x)) - cxf;
                    const dy: f32 = @as(f32, @floatFromInt(y)) - cyf;
                    if (dx * dx + dy * dy <= rad * rad) {
                        self.ua[0][y * GW + x] = 0.5;
                        self.va[0][y * GW + x] = 0.25 + 0.2 * unit(@as(u64, y * GW + x) + 977);
                    }
                }
            }
        }

        for (0..PRE_ROLL) |_| reactStep(self, F_BASE, 1.0);
        renderCells(self);
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const feed: f32 = F_BASE + F_SWING * @as(f32, @floatCast(@sin(self.time_sec * 0.035)));
        for (0..SUBSTEPS) |_| reactStep(self, feed, 1.0);
        renderCells(self);
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        for (0..self.h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const grow: usize = @as(usize, self.row_map[y]) * GW;
            for (dst_row, 0..) |*dst, x| {
                const cell: usize = grow + @as(usize, self.col_map[x]);
                dst.* = self.cell_rgb[cell];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec);
    }
};

// One explicit Euler step of Gray-Scott with a 9-point Laplacian.
// Borders are held fixed (Dirichlet U=1, V=0 is preserved by copying).
fn reactStep(self: *State, feed: f32, dt: f32) void {
    const src = self.cur;
    const dst = 1 - src;
    const ua = &self.ua[src];
    const va = &self.va[src];
    const ub = &self.ua[dst];
    const vb = &self.va[dst];
    const kill_feed: f32 = feed + K_RATE;

    @memcpy(ub[0..GW], ua[0..GW]);
    @memcpy(vb[0..GW], va[0..GW]);
    @memcpy(ub[(GH - 1) * GW ..], ua[(GH - 1) * GW ..]);
    @memcpy(vb[(GH - 1) * GW ..], va[(GH - 1) * GW ..]);

    for (1..GH - 1) |y| {
        const row = y * GW;
        ub[row] = ua[row];
        vb[row] = va[row];
        ub[row + GW - 1] = ua[row + GW - 1];
        vb[row + GW - 1] = va[row + GW - 1];
        for (1..GW - 1) |x| {
            const c = row + x;
            const l = c - 1;
            const r = c + 1;
            const up = c - GW;
            const dn = c + GW;
            const uc = ua[c];
            const vc = va[c];
            const lap_u: f32 = 0.2 * (ua[l] + ua[r] + ua[up] + ua[dn]) +
                0.05 * (ua[up - 1] + ua[up + 1] + ua[dn - 1] + ua[dn + 1]) - uc;
            const lap_v: f32 = 0.2 * (va[l] + va[r] + va[up] + va[dn]) +
                0.05 * (va[up - 1] + va[up + 1] + va[dn - 1] + va[dn + 1]) - vc;
            const uvv: f32 = uc * vc * vc;
            const nu: f32 = uc + dt * (DU * lap_u - uvv + feed * (1.0 - uc));
            const nv: f32 = vc + dt * (DV * lap_v + uvv - kill_feed * vc);
            ub[c] = math.clamp(nu, 0.0, 1.0);
            vb[c] = math.clamp(nv, 0.0, 1.0);
        }
    }
    self.cur = dst;
}

// Colour every interior cell from V and a light-from-upper-left shading of its
// gradient. Shading is 0..1 so scaleRGB never saturates.
fn renderCells(self: *State) void {
    const va = &self.va[self.cur];
    for (0..GH) |y| {
        const row = y * GW;
        for (0..GW) |x| {
            const c = row + x;
            if (x == 0 or y == 0 or x == GW - 1 or y == GH - 1) {
                self.cell_rgb[c] = self.palette[0];
                continue;
            }
            const vc = va[c];
            const level: f32 = math.clamp(vc * 1.7, 0.0, 1.0) * 255.0;
            const idx: usize = @intFromFloat(level);
            const gx: f32 = va[c + 1] - va[c - 1];
            const gy: f32 = va[c + GW] - va[c - GW];
            const lum: f32 = -0.7 * gx - 0.7 * gy;
            const shade: f32 = math.clamp(0.62 + 2.4 * lum, 0.0, 1.0);
            const s256: u32 = @intFromFloat(shade * 256.0);
            self.cell_rgb[c] = sdk.scaleRGB(self.palette[idx], s256);
        }
    }
}

comptime {
    sdk.exportTheme(State);
}

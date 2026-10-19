//! Fable_Ripples — Track B (PDE field dynamics).
//!
//! Rain on a dark pool: a 2D damped wave equation (leapfrog, 5-point Laplacian)
//! integrated in `step()` on a coarse grid of 4x4-pixel cells, shaded per node
//! by height + slope (a cheap directional light), then bilinearly upsampled in
//! `draw()` with pure integer arithmetic — no transcendental calls per pixel.
//!
//! Single heap allocation (`alloc.create(State)`), ~2.3 MiB; no allocations
//! after init; stride-aware rows; every pixel written with 0xFF alpha.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

// One grid node every 4 pixels (CELL = 4). Grid has +2 nodes so that
// `gx + 1` / `gy + 1` are always valid for every pixel, at any resolution.
pub const CELL: usize = 4;
pub const MAX_GW: usize = MAX_W / CELL + 2; // 482
pub const MAX_GH: usize = MAX_H / CELL + 2; // 302
pub const MAX_NODES: usize = MAX_GW * MAX_GH;

const C2: f32 = 0.30; // c^2 dt^2 / dx^2 — below the 0.5 CFL limit of the 2D 5-point stencil
const DAMP: f32 = 0.996; // velocity damping per step
const DROP_EVERY: u32 = 6; // a new raindrop every 6 steps (48 ms)
const DROP_R: isize = 3; // raindrop footprint radius in cells
const DROP_AMP: f32 = 1.6;

/// Fixed-point bilinear channel lerp on packed 0xFF_BB_GG_RR pixels, t in [0..256].
/// R and B are mixed in one 32-bit word (their 16-bit products never overlap).
inline fn lerpPix(c0: u32, c1: u32, t: u32) u32 {
    const s: u32 = 256 - t;
    const rb0: u32 = c0 & 0x00FF00FF;
    const rb1: u32 = c1 & 0x00FF00FF;
    const g0: u32 = c0 & 0x0000FF00;
    const g1: u32 = c1 & 0x0000FF00;
    const rb: u32 = ((rb0 * s + rb1 * t) >> 8) & 0x00FF00FF;
    const g: u32 = ((g0 * s + g1 * t) >> 8) & 0x0000FF00;
    return 0xFF000000 | rb | g;
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,

    gw: usize,
    gh: usize,
    flip: bool, // which of ua/ub is the current field
    tick: u32,
    rng: u64,

    ua: [MAX_NODES]f32,
    ub: [MAX_NODES]f32,
    base: [MAX_NODES]u32, // static pool floor, per node
    node_color: [MAX_NODES]u32, // shaded water colour, per node, rebuilt each step
    pal: [256]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.gw = self.w / CELL + 2;
        self.gh = self.h / CELL + 2;
        self.flip = false;
        self.tick = 0;
        self.rng = 0x9E3779B97F4A7C15;
        self.ua = @splat(0.0);
        self.ub = @splat(0.0);
        self.base = @splat(sdk.packRGBA(0, 0, 0));
        self.node_color = @splat(sdk.packRGBA(0, 0, 0));

        // Height/slope palette: deep water -> mid blue -> bright crest.
        const deep = sdk.packRGBA(3, 10, 34);
        const mid = sdk.packRGBA(12, 64, 118);
        const crest = sdk.packRGBA(225, 246, 255);
        for (0..256) |i| {
            if (i < 128) {
                const t: u32 = @intCast(i * 2);
                self.pal[i] = sdk.lerpRGB(deep, mid, t);
            } else {
                const t: u32 = @intCast((i - 128) * 2);
                self.pal[i] = sdk.lerpRGB(mid, crest, t);
            }
        }

        // Static pool floor: soft sandy ridges, brighter toward the top (init only, so sin is fine).
        const gh_f: f32 = @floatFromInt(self.gh);
        for (0..self.gh) |gy| {
            const fy: f32 = @floatFromInt(gy);
            const depth = fy / gh_f; // 0 at top .. 1 at bottom
            const glow = 0.45 + 0.55 * (1.0 - depth);
            for (0..self.gw) |gx| {
                const fx: f32 = @floatFromInt(gx);
                const r1 = @sin(fx * 0.11 + @sin(fy * 0.07) * 2.5);
                const r2 = @sin(fy * 0.13 + @sin(fx * 0.05) * 2.0);
                const v = (0.5 + 0.25 * r1 + 0.25 * r2) * glow; // [0, 1]
                const rr: u8 = @intFromFloat(math.clamp(v * 22.0, 0.0, 255.0));
                const gg: u8 = @intFromFloat(math.clamp(v * 30.0, 0.0, 255.0));
                const bb: u8 = @intFromFloat(math.clamp(v * 38.0, 0.0, 255.0));
                self.base[gy * self.gw + gx] = sdk.packRGBA(rr, gg, bb);
            }
        }

        // Seed the pool with a handful of drops so frame 1 already has rings.
        for (0..14) |_| self.dropRandom();
        self.shade();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn nextRand(self: *State) u32 {
        self.rng = self.rng *% 6364136223846793005 +% 1442695040888963407;
        return @as(u32, @truncate(self.rng >> 33));
    }

    fn curField(self: *State) []f32 {
        if (self.flip) return self.ub[0..];
        return self.ua[0..];
    }

    /// Adds a Gaussian bump to the current field at a random interior node.
    fn dropRandom(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const span_x: u32 = @intCast(@max(gw - 2, 1));
        const span_y: u32 = @intCast(@max(gh - 2, 1));
        const rx = self.nextRand();
        const ry = self.nextRand();
        const ra = self.nextRand();
        const cx: isize = @intCast(1 + rx % span_x);
        const cy: isize = @intCast(1 + ry % span_y);
        const amp = DROP_AMP * (0.6 + 0.4 * @as(f32, @floatFromInt(ra % 256)) / 255.0);

        const cur = self.curField();
        const igw: isize = @intCast(gw);
        const igh: isize = @intCast(gh);
        var dy: isize = -DROP_R;
        while (dy <= DROP_R) : (dy += 1) {
            var dx: isize = -DROP_R;
            while (dx <= DROP_R) : (dx += 1) {
                const nx = cx + dx;
                const ny = cy + dy;
                if (nx < 1 or ny < 1 or nx >= igw - 1 or ny >= igh - 1) continue;
                const d2: f32 = @floatFromInt(dx * dx + dy * dy);
                const g = amp * @exp(-d2 * 0.35);
                const idx: usize = @intCast(ny * igw + nx);
                cur[idx] += g;
            }
        }
    }

    /// Height + slope -> palette index, added onto the static floor, per node.
    fn shade(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const cur: []const f32 = if (self.flip) self.ub[0..] else self.ua[0..];
        for (0..gh) |gy| {
            const row = gy * gw;
            for (0..gw) |gx| {
                const i = row + gx;
                const uc = cur[i];
                var sx: f32 = 0.0;
                if (gx > 0 and gx + 1 < gw) sx = cur[i + 1] - cur[i - 1];
                var sy: f32 = 0.0;
                if (gy > 0 and gy + 1 < gh) sy = cur[i + gw] - cur[i - gw];
                const v = 128.0 + uc * 70.0 + sx * 110.0 - sy * 70.0;
                const vc = math.clamp(v, 0.0, 255.0);
                const idx: usize = @intFromFloat(vc);
                self.node_color[i] = sdk.addRGB(self.base[i], self.pal[idx]);
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        self.tick +%= 1;
        if (self.tick % DROP_EVERY == 0) self.dropRandom();

        const gw = self.gw;
        const gh = self.gh;
        const cur: []const f32 = if (self.flip) self.ub[0..] else self.ua[0..];
        const prv: []f32 = if (self.flip) self.ua[0..] else self.ub[0..];

        // Leapfrog: u_next = u + damp*(u - u_prev) + c2 * lap(u), written over u_prev.
        // Border nodes stay at 0 (absorbing rim).
        for (1..gh - 1) |gy| {
            const row = gy * gw;
            for (1..gw - 1) |gx| {
                const i = row + gx;
                const uc = cur[i];
                const lap = cur[i - 1] + cur[i + 1] + cur[i - gw] + cur[i + gw] - 4.0 * uc;
                const vel = (uc - prv[i]) * DAMP;
                prv[i] = uc + vel + C2 * lap;
            }
        }
        self.flip = !self.flip;
        self.shade();
    }

    /// Horizontal bilinear pass for one grid row into a pixel row buffer.
    fn fillRow(self: *const State, row: *[MAX_W]u32, gy: usize) void {
        const gw = self.gw;
        const start = gy * gw;
        const nodes = self.node_color[start .. start + gw];
        for (0..self.w) |x| {
            const gx = x >> 2;
            const tx: u32 = @intCast((x & 3) << 6); // 0, 64, 128, 192
            row[x] = lerpPix(nodes[gx], nodes[gx + 1], tx);
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        var row_a: [MAX_W]u32 = undefined;
        var row_b: [MAX_W]u32 = undefined;
        var cached_gy: usize = MAX_GH; // sentinel: nothing cached yet

        for (0..h) |y| {
            const gy = y >> 2;
            const ty: u32 = @intCast((y & 3) << 6);
            if (gy != cached_gy) {
                self.fillRow(&row_a, gy);
                self.fillRow(&row_b, gy + 1);
                cached_gy = gy;
            }
            const dst = buf[y * stride .. y * stride + w];
            if (ty == 0) {
                @memcpy(dst, row_a[0..w]);
            } else {
                for (dst, row_a[0..w], row_b[0..w]) |*d, a, b| d.* = lerpPix(a, b, ty);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        const n = self.gw * self.gh;
        var i: usize = 0;
        while (i < n) : (i += 37) {
            const a = self.ua[i];
            const b = self.ub[i];
            if (math.isNan(a) or math.isInf(a) or math.isNan(b) or math.isInf(b)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

//! Claude Haiku 5.5 // Concentric Ripple Field (Zig 0.17.0)
//! A radial wave train leaving the screen centre. Distance to the centre is
//! precomputed once in init(). Each frame only a 2048-entry ring palette is
//! re-evaluated in step(), so draw() is table lookups plus saturating adds.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;
pub const RING_N: usize = 2048;

fn chan(v: f64) u8 {
    const c = math.clamp(v, 0.0, 255.0);
    return @intFromFloat(c);
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    cx: f64,
    cy: f64,

    // Gate 2: every table lives inside State (about 4.7 MiB total).
    row_base: [MAX_H]u32,
    ring_lut: [RING_N]u32,
    r_idx: [MAX_PIXELS]u16,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.cx = @as(f64, @floatFromInt(self.w)) * 0.5;
        self.cy = @as(f64, @floatFromInt(self.h)) * 0.5;
        self.ring_lut = @splat(sdk.packRGBA(0, 0, 0));

        // Night-blue vertical gradient, one colour per row.
        for (0..self.h) |y| {
            const t: u32 = @intCast((y * 256) / @max(@as(usize, 1), self.h));
            self.row_base[y] = sdk.lerpRGB(sdk.packRGBA(3, 5, 14), sdk.packRGBA(9, 18, 36), t);
        }

        // Radial bucket (whole pixels from centre) for every pixel, computed once.
        for (0..self.h) |y| {
            const dy: f64 = @as(f64, @floatFromInt(y)) - self.cy;
            for (0..self.w) |x| {
                const dx: f64 = @as(f64, @floatFromInt(x)) - self.cx;
                const r = @sqrt(dx * dx + dy * dy);
                const idx: usize = @min(RING_N - 1, @as(usize, @intFromFloat(r)));
                self.r_idx[y * self.w + x] = @intCast(idx);
            }
        }
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const t = self.time_sec;
        // Per-bucket work only (2048 entries): outward-travelling wave with a
        // 1/r falloff and a sharpened crest term.
        for (0..RING_N) |i| {
            const r: f64 = @floatFromInt(i);
            const wave = 0.5 + 0.5 * @sin(r * 0.11 - t * 2.4);
            const fall = 1.0 / (1.0 + (r * r) / (420.0 * 420.0));
            const amp = wave * fall;
            const crest = amp * amp;
            const rr = 10.0 * amp + 40.0 * crest;
            const gg = 60.0 * amp + 120.0 * crest;
            const bb = 110.0 * amp + 135.0 * crest;
            self.ring_lut[i] = sdk.packRGBA(chan(rr), chan(gg), chan(bb));
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        // Gate 3/4: index with y * stride + x and never write past column w.
        const w = self.w;
        for (0..self.h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const idx_row = self.r_idx[y * w .. y * w + w];
            const base = self.row_base[y];
            for (dst_row, idx_row) |*dst, ri| {
                dst.* = sdk.addRGB(base, self.ring_lut[ri]);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec);
    }
};

comptime {
    sdk.exportTheme(State);
}

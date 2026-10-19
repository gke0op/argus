const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

/// Maps a unit-range float to an 8-bit channel, clamped.
fn to8(v: f64) u8 {
    const c: f64 = math.clamp(v * 255.0, 0.0, 255.0);
    return @as(u8, @intFromFloat(c));
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    // 8-bit palette offset, advanced by time in step().
    offset: u8,

    // Static per-pixel radial + spiral index (0..255), indexed y * w + x. Built once in init().
    radial: [MAX_PIXELS]u8,
    // 256-entry palette, rebuilt in step() so the whole field shifts colour over time.
    palette: [256]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.offset = 0;
        self.palette = @splat(sdk.packRGBA(0, 0, 0));

        const cx: f64 = @as(f64, @floatFromInt(self.w)) * 0.5;
        const cy: f64 = @as(f64, @floatFromInt(self.h)) * 0.5;
        const span: f64 = @max(1.0, @sqrt(cx * cx + cy * cy));

        for (0..self.h) |y| {
            const fy: f64 = @as(f64, @floatFromInt(y)) - cy;
            for (0..self.w) |x| {
                const fx: f64 = @as(f64, @floatFromInt(x)) - cx;
                const r: f64 = @sqrt(fx * fx + fy * fy) / span;
                // turns in [0, 1]; 768 = 3 * 256 keeps the angular seam invisible.
                const turns: f64 = math.atan2(fy, fx) / (2.0 * math.pi) + 0.5;
                const v: f64 = r * 640.0 + turns * 768.0;
                const iv: u32 = @intFromFloat(@mod(v, 256.0));
                self.radial[y * self.w + x] = @truncate(iv);
            }
        }
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const tm: f64 = self.time_sec * 0.5;
        const k: f64 = 0.35 + 0.65 * (0.5 + 0.5 * @sin(self.time_sec * 0.7));
        for (0..256) |i| {
            const t: f64 = @as(f64, @floatFromInt(i)) * (2.0 * math.pi / 256.0);
            const r: f64 = 0.5 + 0.5 * @cos(t + tm);
            const g: f64 = 0.5 + 0.5 * @cos(2.0 * t + 2.1 - tm * 0.7);
            const b: f64 = 0.5 + 0.5 * @cos(t + 4.2 + tm * 0.4);
            self.palette[i] = sdk.packRGBA(to8(r * r * k), to8(g * g * k), to8(b * k));
        }
        const frac: f64 = @mod(self.time_sec * 60.0, 256.0);
        const whole: u32 = @intFromFloat(frac);
        self.offset = @truncate(whole);
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const off = self.offset;
        for (0..self.h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.radial[y * w .. y * w + w];
            for (dst_row, src_row) |*dst, idx| {
                dst.* = self.palette[idx +% off];
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

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,

    // IMPORTANT (Gate 2): Put all lookup tables, grids, and particle arrays directly
    // inside `State` as fixed-size arrays so `alloc.create(State)` is the ONLY heap
    // allocation (`Allocs at Init == 1`, `Allocs after Init == 0`).
    // Keep `@sizeOf(State) <= 12 * 1024 * 1024` (12 MiB).
    bg_lut: [MAX_PIXELS]u32,
    row_glow: [MAX_H]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.row_glow = @splat(sdk.packRGBA(0, 0, 0));

        // Precompute static geometry / LUTs once here in `init()`: a night-blue gradient.
        for (0..self.h) |y| {
            const t: u32 = @intCast((y * 256) / @max(@as(usize, 1), self.h));
            const row = sdk.lerpRGB(sdk.packRGBA(4, 6, 18), sdk.packRGBA(10, 24, 48), t);
            for (0..self.w) |x| {
                self.bg_lut[y * self.w + x] = row;
            }
        }
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        // Advance physics / ODE / PDE / phase state using fixed timestep `dt` (0.008 s).
        // Zero heap allocations allowed here. Per-row work (h sines), not per-pixel.
        self.time_sec += dt;
        for (0..self.h) |y| {
            const fy: f64 = @floatFromInt(y);
            const s = 0.5 + 0.5 * @sin(fy * 0.02 - self.time_sec * 3.0);
            const g: u8 = @intFromFloat(s * 40.0);
            const b: u8 = @intFromFloat(s * 90.0);
            self.row_glow[y] = sdk.packRGBA(0, g, b);
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        // IMPORTANT (Gate 3 & Gate 4):
        // 1. Always index row `y` via `y * stride + x` (NEVER `y * self.w + x` in `buf`).
        // 2. Write every pixel in `0..self.h` and `0..self.w` with `0xFF` alpha (`sdk.packRGBA`).
        // 3. Never write to columns `[self.w .. stride]`: those contain `0xDEADBEEF` canaries!
        const w = self.w;
        for (0..self.h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.bg_lut[y * w .. y * w + w];
            const glow = self.row_glow[y];
            for (dst_row, src_row) |*dst, src| dst.* = sdk.addRGB(src, glow);
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec);
    }
};

comptime {
    sdk.exportTheme(State);
}

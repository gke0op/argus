// ============================================================================
// ARGUS CPU KERNELS // themes/cpu/argus_kernel.zig
//
// Runs Metal-style Argus kernels on the CPU, so a ported Metal theme is an ordinary Zig
// theme: the harness, the Mac app and argus-linux load it unchanged. Pure Zig, no libc.
//
//   * Metal-flavoured math: F2/F3/F4 are @Vector types; floor, fract, mix, smoothstep,
//     saturate, length... behave as in the Metal Shading Language.
//   * The Argus prelude (src/gpu/argus_prelude.metal) ported 1:1: argus_uv, argus_hash,
//     argus_rand, argus_noise, argus_fbm, argus_palette, argus_srgb, argus_aces.
//   * exportKernelTheme(K): K.draw(f, gid) -> F4 runs once per pixel, spread over every core
//     in row bands; output is packed exactly as the GPU harness packs (round(c * 255)).
//
// Time: one SDK step of 0.008 is one 30 Hz Metal tick (f.time += 1/30 s, f.frame += 1), so
// the app's speed setting, which scales the step, scales f.time the same way.
// ============================================================================

const std = @import("std");

pub const F2 = @Vector(2, f32);
pub const F3 = @Vector(3, f32);
pub const F4 = @Vector(4, f32);

pub inline fn f2(x: f32, y: f32) F2 {
    return .{ x, y };
}
pub inline fn f3(x: f32, y: f32, z: f32) F3 {
    return .{ x, y, z };
}
pub inline fn s2(x: f32) F2 {
    return @splat(x);
}
pub inline fn s3(x: f32) F3 {
    return @splat(x);
}

pub inline fn fract(x: anytype) @TypeOf(x) {
    return x - @floor(x);
}
pub inline fn mix(a: anytype, b: @TypeOf(a), t: @TypeOf(a)) @TypeOf(a) {
    return a + (b - a) * t;
}
pub inline fn saturate(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    return @min(@max(x, splatLike(T, 0.0)), splatLike(T, 1.0));
}
pub inline fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
    const t = saturate((x - e0) / (e1 - e0));
    return t * t * (3.0 - 2.0 * t);
}
pub inline fn length(v: anytype) f32 {
    return @sqrt(@reduce(.Add, v * v));
}
inline fn splatLike(comptime T: type, x: f32) T {
    return if (@typeInfo(T) == .vector) @splat(x) else x;
}

// ---- The Argus prelude -------------------------------------------------------------------

pub const Frame = extern struct {
    time: f32,
    dt: f32,
    frame: u32,
    width: u32,
    height: u32,
    state_width: u32 = 0,
    state_height: u32 = 0,
    seed: u32,
    days_j2000: i32 = 0,
    day_frac: f32 = 0,
    utc_offset_s: i32 = 0,
};

pub inline fn argus_uv(gid: [2]u32, f: *const Frame) F2 {
    const p = f2(@floatFromInt(gid[0]), @floatFromInt(gid[1])) + s2(0.5) -
        s2(0.5) * f2(@floatFromInt(f.width), @floatFromInt(f.height));
    return f2(p[0], -p[1]) / s2(0.5 * @as(f32, @floatFromInt(@min(f.width, f.height))));
}

pub inline fn argus_hash(x0: u32) u32 {
    var x = x0;
    x ^= x >> 16;
    x *%= 0x7feb352d;
    x ^= x >> 15;
    x *%= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

pub inline fn argus_rand(cell: [2]u32, seed: u32) f32 {
    return @as(f32, @floatFromInt(argus_hash(cell[0] ^ argus_hash(cell[1] ^ argus_hash(seed))))) * (1.0 / 4294967295.0);
}

/// Metal's uint2(int2(v) + k): float -> int (toward zero) -> + k -> reinterpret as uint.
pub inline fn cellOf(v: F2, k: i32) [2]u32 {
    return .{
        @bitCast(@as(i32, @intFromFloat(v[0])) +% k),
        @bitCast(@as(i32, @intFromFloat(v[1])) +% k),
    };
}

pub inline fn argus_noise(p: F2) f32 {
    const i = @floor(p);
    const fr = p - i;
    const u = fr * fr * (s2(3.0) - s2(2.0) * fr);
    const c = cellOf(i, 32768);
    const a = argus_rand(c, 0);
    const b = argus_rand(.{ c[0] +% 1, c[1] }, 0);
    const d = argus_rand(.{ c[0], c[1] +% 1 }, 0);
    const e = argus_rand(.{ c[0] +% 1, c[1] +% 1 }, 0);
    return 2.0 * mix(mix(a, b, u[0]), mix(d, e, u[0]), u[1]) - 1.0;
}

pub inline fn argus_fbm(p0: F2, octaves: u32) f32 {
    var p = p0;
    var sum: f32 = 0.0;
    var amp: f32 = 0.5;
    for (0..octaves) |_| {
        sum += amp * argus_noise(p);
        p = f2(1.6 * p[0] - 1.2 * p[1], 1.2 * p[0] + 1.6 * p[1]); // float2x2(1.6, 1.2, -1.2, 1.6) * p
        amp *= 0.5;
    }
    return sum;
}

pub inline fn argus_palette(t: f32, a: F3, b: F3, c: F3, d: F3) F3 {
    return a + b * @cos(s3(6.2831853) * (c * s3(t) + d));
}

pub inline fn argus_srgb(lin0: F3) F3 {
    const lin = saturate(lin0);
    const hi = s3(1.055) * @exp2(@log2(lin) * s3(1.0 / 2.4)) - s3(0.055);
    return @select(f32, lin <= s3(0.0031308), lin * s3(12.92), hi);
}

pub inline fn argus_aces(x: F3) F3 {
    return saturate((x * (s3(2.51) * x + s3(0.03))) / (x * (s3(2.43) * x + s3(0.59)) + s3(0.14)));
}

// ---- Dispatch ----------------------------------------------------------------------------

const MAX_THREADS = 64;
const TICK_DT: f64 = 0.008; // the SDK step that equals one 30 Hz Metal tick

inline fn pack(c: F4) u32 {
    const q = @round(saturate(c) * @as(F4, @splat(255.0)));
    return 0xFF00_0000 | (@as(u32, @intFromFloat(q[2])) << 16) | (@as(u32, @intFromFloat(q[1])) << 8) | @as(u32, @intFromFloat(q[0]));
}

pub fn exportKernelTheme(comptime K: type) void {
    const Theme = struct {
        frame: Frame,
        clock: f64,
        threads: usize,

        var allocs_init: usize = 0;

        fn band(self: *const @This(), px: []u32, stride: usize, y0: usize, y1: usize) void {
            @setFloatMode(.optimized);
            for (y0..y1) |y| {
                const row = px[y * stride ..];
                for (0..self.frame.width) |x| row[x] = pack(K.draw(&self.frame, .{ @intCast(x), @intCast(y) }));
            }
        }

        fn init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque {
            _ = scale;
            const self = std.heap.page_allocator.create(@This()) catch return null;
            allocs_init = 1;
            self.* = .{
                .frame = .{ .time = 0, .dt = 1.0 / 30.0, .frame = 0, .width = w, .height = h, .seed = 0x5EED },
                .clock = 0,
                .threads = @min(MAX_THREADS, std.Thread.getCpuCount() catch 1),
            };
            return self;
        }

        fn deinit(raw: ?*anyopaque) callconv(.c) void {
            std.heap.page_allocator.destroy(@as(*@This(), @ptrCast(@alignCast(raw orelse return))));
        }

        fn step(raw: ?*anyopaque, dt: f64) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(raw orelse return));
            self.clock = @mod(self.clock + dt / TICK_DT / 30.0, 14400.0); // ARGUS_TIME_PERIOD
            self.frame.time = @floatCast(self.clock);
            self.frame.frame +%= 1;
        }

        fn draw(raw: ?*anyopaque, px: [*]u32, len: usize, stride: usize) callconv(.c) void {
            const self: *const @This() = @ptrCast(@alignCast(raw orelse return));
            const h: usize = self.frame.height;
            if (len < (h - 1) * stride + self.frame.width) return;
            const n = @min(self.threads, h);
            var pool: [MAX_THREADS]?std.Thread = @splat(null);
            for (1..n) |t| pool[t] = std.Thread.spawn(.{}, band, .{ self, px[0..len], stride, h * t / n, h * (t + 1) / n }) catch null;
            self.band(px[0..len], stride, 0, h / n);
            for (1..n) |t| {
                if (pool[t]) |th| th.join() else self.band(px[0..len], stride, h * t / n, h * (t + 1) / n);
            }
        }

        fn allocsInit() callconv(.c) usize {
            return allocs_init;
        }
        fn allocsAfter() callconv(.c) usize {
            return 0;
        }
        fn bytesLive() callconv(.c) usize {
            return @sizeOf(@This());
        }
        fn hasNaN(raw: ?*anyopaque) callconv(.c) bool {
            return raw == null;
        }
    };
    @export(&Theme.init, .{ .name = "argus_theme_init" });
    @export(&Theme.deinit, .{ .name = "argus_theme_deinit" });
    @export(&Theme.step, .{ .name = "argus_theme_step" });
    @export(&Theme.draw, .{ .name = "argus_theme_draw" });
    @export(&Theme.allocsInit, .{ .name = "argus_theme_allocs_init" });
    @export(&Theme.allocsAfter, .{ .name = "argus_theme_allocs_after_init" });
    @export(&Theme.bytesLive, .{ .name = "argus_theme_bytes_live" });
    @export(&Theme.hasNaN, .{ .name = "argus_theme_has_nan" });
}

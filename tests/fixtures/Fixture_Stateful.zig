// ============================================================================
// ARGUS TEST FIXTURE // tests/fixtures/Fixture_Stateful.zig
//
// Test-only theme (never shipped): the stateful C ABI that `argus_theme_sdk.zig`'s exportTheme
// produces (init/step/draw/deinit plus the allocation and NaN probes), written out by hand
// because a theme built from tests/ cannot import the SDK from themes/. A black sky with one lit
// disc at the centre whose brightness follows time; it allocates only in init.
// ============================================================================

const std = @import("std");

const State = struct { w: usize, h: usize, t: f64 };
var allocs: usize = 0;
var allocs_at_init: usize = 0;

export fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque {
    _ = scale;
    const st = std.heap.page_allocator.create(State) catch return null;
    allocs += 1;
    st.* = .{ .w = w, .h = h, .t = 0 };
    allocs_at_init = allocs;
    return st;
}

export fn argus_theme_deinit(state: ?*anyopaque) callconv(.c) void {
    const st: *State = @ptrCast(@alignCast(state orelse return));
    std.heap.page_allocator.destroy(st);
}

export fn argus_theme_step(state: ?*anyopaque, dt: f64) callconv(.c) void {
    const st: *State = @ptrCast(@alignCast(state orelse return));
    st.t += dt;
}

export fn argus_theme_draw(state: ?*anyopaque, pixels: [*]u32, buf_len: usize, stride: usize) callconv(.c) void {
    const st: *const State = @ptrCast(@alignCast(state orelse return));
    const cx: f64 = @as(f64, @floatFromInt(st.w)) * 0.5;
    const cy: f64 = @as(f64, @floatFromInt(st.h)) * 0.5;
    const r = @as(f64, @floatFromInt(@min(st.w, st.h))) * 0.125;
    const level: u32 = 160 + @as(u32, @intFromFloat(80.0 * (0.5 + 0.5 * @sin(st.t * 2.0))));
    for (0..st.h) |y| {
        for (0..st.w) |x| {
            const i = y * stride + x;
            if (i >= buf_len) return;
            const dx = @as(f64, @floatFromInt(x)) + 0.5 - cx;
            const dy = @as(f64, @floatFromInt(y)) + 0.5 - cy;
            const lit = dx * dx + dy * dy <= r * r;
            pixels[i] = if (lit) 0xFF00_0000 | (level << 16) | (level << 8) | level else 0xFF00_0000;
        }
    }
}

export fn argus_theme_allocs_init() callconv(.c) usize {
    return allocs_at_init;
}

export fn argus_theme_allocs_after_init() callconv(.c) usize {
    return allocs - allocs_at_init;
}

export fn argus_theme_bytes_live() callconv(.c) usize {
    return @sizeOf(State);
}

export fn argus_theme_has_nan(state: ?*anyopaque) callconv(.c) bool {
    const st: *const State = @ptrCast(@alignCast(state orelse return false));
    return std.math.isNan(st.t) or std.math.isInf(st.t);
}

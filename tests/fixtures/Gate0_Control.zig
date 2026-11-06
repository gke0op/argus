// ============================================================================
// ARGUS GATE FIXTURE // tests/fixtures/Gate0_Control.zig
//
// Test-only theme (never shipped) that passes all eight harness gates, so the native harness
// (make harness) and the browser harness (web/wasm) can be seen to give the same verdict.
// The theme: a night gradient with a band of light sweeping up and down, the stateful C ABI the
// SDK produces written out by hand (a theme built from tests/ cannot import themes/), one
// allocation in init and only exact arithmetic (no libm), so native and wasm agree bit for bit.
// The defect: none. This is the control the other Gate fixtures change in one place.
// ============================================================================

const std = @import("std");

const State = struct { w: usize, h: usize, t: f64, centre: f64 };
// Reset by every init, as the SDK's CountingAllocator is.
var allocs_init: usize = 0;
var allocs_after: usize = 0;

export fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque {
    _ = scale;
    allocs_init = 0;
    allocs_after = 0;
    const st = std.heap.page_allocator.create(State) catch return null;
    allocs_init += 1;
    st.* = .{ .w = w, .h = h, .t = 0, .centre = 0.2 };
    return st;
}

export fn argus_theme_deinit(state: ?*anyopaque) callconv(.c) void {
    const st: *State = @ptrCast(@alignCast(state orelse return));
    std.heap.page_allocator.destroy(st);
}

/// Triangle wave in [0, 1], period 1.
fn tri(x: f64) f64 {
    const f = x - @floor(x);
    return if (f < 0.5) 2.0 * f else 2.0 - 2.0 * f;
}

export fn argus_theme_step(state: ?*anyopaque, dt: f64) callconv(.c) void {
    const st: *State = @ptrCast(@alignCast(state orelse return));
    st.t += dt;
    st.centre = 0.2 + 0.6 * tri(st.t * 0.8);
}

inline fn pack(r: u32, g: u32, b: u32) u32 {
    return 0xFF00_0000 | (b << 16) | (g << 8) | r;
}

export fn argus_theme_draw(state: ?*anyopaque, pixels: [*]u32, buf_len: usize, stride: usize) callconv(.c) void {
    const st: *const State = @ptrCast(@alignCast(state orelse return));
    const hf: f64 = @floatFromInt(@max(st.h, 1));
    for (0..st.h) |y| {
        const row = y * stride;
        if (row + st.w > buf_len) return;
        const fy = @as(f64, @floatFromInt(y)) / hf;
        const d = @abs(fy - st.centre);
        const l = @max(0.0, 1.0 - d * 6.0); // the band's brightness on this row
        const r: u32 = @intFromFloat(4.0 + 20.0 * l + 6.0 * fy);
        const g: u32 = @intFromFloat(8.0 + 60.0 * l + 10.0 * fy);
        const b: u32 = @intFromFloat(24.0 + 150.0 * l + 30.0 * fy);
        for (0..st.w) |x| {
            pixels[row + x] = pack(r, g, b + @as(u32, @truncate(x & 3)));
        }
    }
}

export fn argus_theme_allocs_init() callconv(.c) usize {
    return allocs_init;
}

export fn argus_theme_allocs_after_init() callconv(.c) usize {
    return allocs_after;
}

export fn argus_theme_bytes_live() callconv(.c) usize {
    return @sizeOf(State);
}

export fn argus_theme_has_nan(state: ?*anyopaque) callconv(.c) bool {
    const st: *const State = @ptrCast(@alignCast(state orelse return false));
    return std.math.isNan(st.t) or std.math.isInf(st.t);
}

// ============================================================================
// ARGUS TEST FIXTURE // tests/fixtures/Fixture_Hang.zig
//
// Test-only theme (never shipped): a stateful theme whose step() never returns, the accident the
// watchdog's time limit exists for. It sub-steps its clock until it has covered `dt`, with a
// sub-step that is zero, so the loop never ends. init and draw are well behaved, so only the time
// limit can reject it.
// ============================================================================

const std = @import("std");

const State = struct { w: usize, h: usize, t: f64, substep: f64 };

export fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque {
    _ = scale;
    const st = std.heap.page_allocator.create(State) catch return null;
    st.* = .{ .w = w, .h = h, .t = 0, .substep = 0 }; // the bug: should be a fraction of the frame time
    return st;
}

export fn argus_theme_deinit(state: ?*anyopaque) callconv(.c) void {
    const st: *State = @ptrCast(@alignCast(state orelse return));
    std.heap.page_allocator.destroy(st);
}

export fn argus_theme_step(state: ?*anyopaque, dt: f64) callconv(.c) void {
    const st: *State = @ptrCast(@alignCast(state orelse return));
    var covered: f64 = 0;
    while (covered < dt) {
        covered += @as(*volatile f64, &st.substep).*; // volatile: the optimizer can't drop the loop
        std.atomic.spinLoopHint();
    }
    st.t += dt;
}

export fn argus_theme_draw(state: ?*anyopaque, pixels: [*]u32, buf_len: usize, stride: usize) callconv(.c) void {
    const st: *const State = @ptrCast(@alignCast(state orelse return));
    for (0..st.h) |y| {
        const row = y * stride;
        if (row + st.w > buf_len) return;
        @memset(pixels[row..][0..st.w], 0xFF00_0000);
    }
}

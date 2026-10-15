// ============================================================================
// ARGUS GPU PROTOTYPE // src/gpu/bh_export.zig
//
// Root of the GPU build of themes/Opus_Black_Hole.zig (`--gpu` only). Compiled as
//   zig build-lib --dep theme -Mroot=src/gpu/bh_export.zig -Mtheme=<theme path>
// it exports the theme's normal SDK symbols (from the theme's own `comptime` block)
// plus three accessors the Metal presenter uses to read the theme's tables.
// ============================================================================

const theme = @import("theme");
const bt = @import("bh_tables.zig");

comptime {
    _ = theme; // pulls in the theme's sdk.exportTheme(State)
}

fn state(raw: *anyopaque) *theme.State {
    return @ptrCast(@alignCast(raw));
}

export fn argus_gpu_bh_static(raw: *anyopaque, out: *bt.Static) callconv(.c) void {
    bt.fillStatic(state(raw), out);
}

export fn argus_gpu_bh_frame(raw: *anyopaque, out: *bt.Frame) callconv(.c) void {
    bt.fillFrame(state(raw), out);
}

/// Addresses and byte lengths of the kernel's buffers 0-4 (records, bg, row_x0, row_x1, noise).
export fn argus_gpu_bh_buffers(raw: *anyopaque, ptrs: *[5]usize, lens: *[5]usize) callconv(.c) void {
    const bufs = bt.pixelBuffers(state(raw));
    for (bufs, 0..) |b, i| {
        ptrs[i] = @intFromPtr(b.ptr);
        lens[i] = b.len;
    }
}

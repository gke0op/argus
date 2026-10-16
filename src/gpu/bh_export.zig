// ============================================================================
// ARGUS GPU // src/gpu/bh_export.zig
//
// Root of the GPU build of themes/H1821.zig (the default; `--cpu` turns it off).
// Compiled as
//   zig build-lib --dep theme -Mroot=src/gpu/bh_export.zig -Mtheme=<theme path>
// it exports the theme's normal SDK symbols (from the theme's own `comptime` block)
// plus the accessors the Metal presenter uses to read the theme's tables. The marker
// below tells the theme that the GPU traces the image, so its init() skips the CPU trace.
// ============================================================================

const theme = @import("theme");
const bt = @import("bh_tables.zig");

pub const argus_gpu_traces_kerr_disk = true;

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

/// Geometry for a w x h trace.
export fn argus_gpu_bh_trace_params(raw: *anyopaque, w: u32, h: u32, out: *bt.TraceParams) callconv(.c) void {
    bt.fillTrace(state(raw), w, h, out);
}

/// Address and byte length of the turbulence noise (0) and the temperature table (1).
export fn argus_gpu_bh_tables(raw: *anyopaque, ptrs: *[2]usize, lens: *[2]usize) callconv(.c) void {
    const st = state(raw);
    const t = [2][]const u8{ bt.noiseBytes(st), bt.ttabBytes(st) };
    for (t, 0..) |b, i| {
        ptrs[i] = @intFromPtr(b.ptr);
        lens[i] = b.len;
    }
}

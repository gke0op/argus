// ============================================================================
// ARGUS WEB // web/cygnus/cygnus_wasm.zig
//
// The browser's CPU side of Cygnus A: the real theme (themes/Cygnus_A.zig) compiled to
// wasm32-freestanding through the app's own GPU export root (src/gpu/bh_export.zig), so the
// tables (Static, the temperature/opacity table, the turbulence noise), the trace geometry and
// every frame's step() state are byte-for-byte what the Metal presenter uploads.
//
//   zig build-exe -target wasm32-freestanding -fno-entry -O ReleaseSmall --dep theme \
//     -Mroot=web/cygnus/cygnus_wasm.zig --dep bh_export ... (see web/cygnus/build.sh)
// ============================================================================

const std = @import("std");
const theme = @import("theme");
const bt = @import("bh_tables");

/// Marker the theme looks for on the root module: the GPU traces the image, so init() skips
/// the CPU trace and step() skips the CPU-only coarse turbulence (as in the app's GPU build).
pub const argus_gpu_traces_kerr_disk = true;

comptime {
    _ = theme; // the theme's own sdk.exportTheme(State)
}

var st_ptr: ?*theme.State = null;
var stat: bt.Static = undefined;
var frame: bt.Frame = undefined;
var params: bt.TraceParams = undefined;

/// Creates the theme state at `w` x `h` (the size only sets the theme's own framing, which
/// fillTrace rescales: see cyg_trace_params). Returns 0 on failure.
export fn cyg_init(w: u32, h: u32) u32 {
    if (st_ptr) |s| s.deinit(std.heap.wasm_allocator);
    st_ptr = theme.State.init(std.heap.wasm_allocator, w, h, 1.0) catch return 0;
    bt.fillStatic(st_ptr.?, &stat);
    return 1;
}

export fn cyg_step(dt: f64) void {
    if (st_ptr) |s| s.step(dt);
}

/// Simulation clock (M of coordinate time).
export fn cyg_time_m() f64 {
    return if (st_ptr) |s| s.t_m else 0;
}

export fn cyg_static_ptr() usize {
    return @intFromPtr(&stat);
}
export fn cyg_static_len() usize {
    return @sizeOf(bt.Static);
}

/// Fills the per-frame tables from the current step() state; returns their address.
export fn cyg_frame() usize {
    if (st_ptr) |s| bt.fillFrame(s, &frame);
    return @intFromPtr(&frame);
}
export fn cyg_frame_len() usize {
    return @sizeOf(bt.Frame);
}

/// Trace geometry for a w x h trace, optionally at another inclination (radians; < 0 = the theme's).
export fn cyg_trace_params(w: u32, h: u32, incl: f64) usize {
    if (st_ptr) |s| {
        bt.fillTrace(s, w, h, &params);
        if (incl >= 0) {
            params.incl = @floatCast(incl);
            params.sin_i = @floatCast(@sin(incl));
            params.cos_i = @floatCast(@cos(incl));
        }
    }
    return @intFromPtr(&params);
}
export fn cyg_trace_params_len() usize {
    return @sizeOf(bt.TraceParams);
}

export fn cyg_noise_ptr() usize {
    return if (st_ptr) |s| @intFromPtr(bt.noiseBytes(s).ptr) else 0;
}
export fn cyg_noise_len() usize {
    return if (st_ptr) |s| bt.noiseBytes(s).len else 0;
}
export fn cyg_ttab_ptr() usize {
    return if (st_ptr) |s| @intFromPtr(bt.ttabBytes(s).ptr) else 0;
}
export fn cyg_ttab_len() usize {
    return if (st_ptr) |s| bt.ttabBytes(s).len else 0;
}

/// Exposure from the meter kernel's luminances (the app's bt.exposureFrom): the JS side
/// writes `n` floats at cyg_scratch(n) and calls this.
var scratch: []f32 = &.{};
export fn cyg_scratch(n: usize) usize {
    if (scratch.len < n) {
        if (scratch.len > 0) std.heap.wasm_allocator.free(scratch);
        scratch = std.heap.wasm_allocator.alloc(f32, n) catch return 0;
    }
    return @intFromPtr(scratch.ptr);
}
export fn cyg_exposure_from(n: usize) f32 {
    return bt.exposureFrom(scratch[0..n], 7.0);
}

export fn cyg_incl() f64 {
    return theme.INCL;
}
export fn cyg_spin() f64 {
    return theme.SPIN;
}

// ---------------------------------------------------------------- shadow-edge test
// The theme's own contour (Bardeen 1973 critical curve, CONTOUR_PTS points) and statistics, so
// the browser bisects its WGSL probe kernel exactly as src/gpu_bench.zig bisects the Metal one.

var contour: [theme.CONTOUR_PTS][2]f64 = undefined;
var centre: [2]f64 = undefined;
var offsets: [theme.CONTOUR_PTS]f64 = undefined;
var stats_out: [8]f64 = undefined;

/// Fills the contour; returns its address (CONTOUR_PTS x [alpha, beta] f64).
export fn cyg_contour() usize {
    centre = theme.shadowContour(theme.SPIN, theme.INCL, &contour);
    return @intFromPtr(&contour);
}
export fn cyg_contour_n() usize {
    return theme.CONTOUR_PTS;
}
export fn cyg_contour_iters() usize {
    return theme.CONTOUR_ITERS;
}
export fn cyg_contour_centre() usize {
    return @intFromPtr(&centre);
}
/// Where the caller writes the signed edge offsets (M; NaN = bracket failure).
export fn cyg_contour_offsets() usize {
    return @intFromPtr(&offsets);
}
/// The theme's contourStats over those offsets: [max, max_at alpha, max_at beta, rms,
/// rms_off_axis, max_off_axis, max_polar, bracket failures].
export fn cyg_contour_stats() usize {
    const s = theme.contourStats(&contour, &offsets);
    stats_out = .{ s.max, s.max_at[0], s.max_at[1], s.rms, s.rms_off_axis, s.max_off_axis, s.max_polar, @floatFromInt(s.bad) };
    return @intFromPtr(&stats_out);
}

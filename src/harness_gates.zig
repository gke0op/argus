// ============================================================================
// ARGUS HARNESS GATES // src/harness_gates.zig
//
// The run behind the harness's verdict, as a library with no OS in it: the 320x200 watchdog,
// the padded-stride and tight frames, the allocation, NaN, pixel and motion checks and the frame
// timings. src/theme_harness.zig runs it on a theme it compiled and dlopen-ed; web/wasm/runtime.zig
// runs the same code on the same theme compiled to WebAssembly, so the browser's verdict is the
// harness's verdict by construction. (Gate 1, compilation, is the caller's: a theme that does not
// compile never gets here.)
// ============================================================================

const std = @import("std");

/// The SDK step per frame: one 30 Hz Argus tick.
pub const DT: f64 = 0.008;
/// Gate 8: average step + draw time per frame at 1920x1200.
pub const BUDGET_US: f64 = 16667.0;
pub const WD_W: usize = 320;
pub const WD_H: usize = 200;
/// The watchdog draws into a 320x200 frame with 8 columns of canary on every row.
pub const WD_PAD: usize = 8;
/// The main run's padded frames have 16 columns of canary on every row.
pub const PAD: usize = 16;
pub const CANARY: u32 = 0xDEADBEEF;
/// Gate 6: pixels whose |dR| + |dG| + |dB| >= 4 between frame 1 and the last frame.
pub const MOTION_MIN: usize = 2_000;
pub const MOTION_DIFF: i32 = 4;
/// Gate 5: more than this many pixels must differ from the top-left one.
pub const DISTINCT_MIN: usize = 100;

pub const FnInit = *const fn (w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque;
pub const FnDeinit = *const fn (state: ?*anyopaque) callconv(.c) void;
pub const FnStep = *const fn (state: ?*anyopaque, dt: f64) callconv(.c) void;
pub const FnDraw = *const fn (state: ?*anyopaque, pixels: [*]u32, buf_len: usize, stride: usize) callconv(.c) void;
pub const FnCount = *const fn () callconv(.c) usize;
pub const FnHasNaN = *const fn (state: ?*anyopaque) callconv(.c) bool;
pub const FnStateless = *const fn (pixels: [*]u32, w: u32, h: u32, phase: f64, step_count: u64) callconv(.c) void;

/// A theme's entry points; null where the theme does not export one.
pub const Abi = struct {
    init: ?FnInit = null,
    deinit: ?FnDeinit = null,
    step: ?FnStep = null,
    draw: ?FnDraw = null,
    allocs_init: ?FnCount = null,
    allocs_after: ?FnCount = null,
    bytes_live: ?FnCount = null,
    has_nan: ?FnHasNaN = null,
    stateless: ?FnStateless = null,

    pub fn isStateful(a: Abi) bool {
        return a.init != null and a.step != null and a.draw != null and a.deinit != null;
    }
};

/// Where the run is, for a host that must say which gate a theme hung in (the browser kills a
/// Worker that runs past its time limit; the app kills its verifier process the same way).
pub const Phase = enum(u32) { watchdog = 1, init = 2, frames = 3, inspect = 4, done = 5 };

pub const Hooks = struct {
    ctx: ?*anyopaque = null,
    /// A monotonic clock in nanoseconds.
    now_ns: *const fn (ctx: ?*anyopaque) u64,
    phase: ?*const fn (ctx: ?*anyopaque, p: Phase) void = null,

    fn enter(h: Hooks, p: Phase) void {
        if (h.phase) |f| f(h.ctx, p);
    }
};

pub const Options = struct {
    width: usize = 1920,
    height: usize = 1200,
    n_frames: usize = 120,
};

pub const Result = struct {
    stateful: bool,
    width: usize,
    height: usize,
    padded_stride: usize,
    n_frames: usize,
    watchdog_ok: bool,
    allocs_init: usize = 0,
    bytes_live: usize = 0,
    allocs_after: usize = 0,
    total_ns: u64 = 0,
    worst_ns: u64 = 0,
    nan_detected: bool = false,
    canary_corrupted: bool = false,
    distinct_pixels: usize = 0,
    bad_alpha_pixels: usize = 0,
    animated_pixels: usize = 0,

    pub fn avgUs(r: Result) f64 {
        return (@as(f64, @floatFromInt(r.total_ns)) / @as(f64, @floatFromInt(@max(@as(usize, 1), r.n_frames)))) / 1000.0;
    }
    pub fn worstUs(r: Result) f64 {
        return @as(f64, @floatFromInt(r.worst_ns)) / 1000.0;
    }
    pub fn allocOk(r: Result) bool {
        return if (r.stateful) (r.allocs_init == 1 and r.allocs_after == 0) else (r.allocs_after == 0);
    }
    pub fn motionOk(r: Result) bool {
        return if (r.n_frames > 1) (r.animated_pixels >= MOTION_MIN) else true;
    }
    pub fn pixelsOk(r: Result) bool {
        return r.distinct_pixels > DISTINCT_MIN and r.bad_alpha_pixels == 0;
    }
    pub fn budgetOk(r: Result) bool {
        return r.avgUs() < BUDGET_US;
    }
    pub fn pass(r: Result, enforce_budget: bool) bool {
        return r.watchdog_ok and r.allocOk() and !r.nan_detected and !r.canary_corrupted and r.pixelsOk() and r.motionOk() and (!enforce_budget or r.budgetOk());
    }
};

pub const Error = error{ NoThemeAbi, InitReturnedNull } || std.mem.Allocator.Error;

/// The harness run. `final` (width * height) receives the last frame, tightly packed, for the
/// caller's PNG or canvas. Buffers come from `alloc`, the host's allocator, never the theme's.
pub fn run(alloc: std.mem.Allocator, abi: Abi, opt: Options, hooks: Hooks, final: []u32) Error!Result {
    const stateful = abi.isStateful();
    if (!stateful and abi.stateless == null) return error.NoThemeAbi;
    const width = opt.width;
    const height = opt.height;
    const n_frames = opt.n_frames;
    const dt = DT;
    std.debug.assert(final.len == width * height);

    // 0. The 320x200 watchdog probe (parity with Argus.app `--verify-dylib`, space_config.zig).
    hooks.enter(.watchdog);
    var watchdog_ok = true;
    {
        const wd_stride: usize = WD_W + WD_PAD;
        const wd_buf = try alloc.alloc(u32, wd_stride * WD_H);
        defer alloc.free(wd_buf);
        @memset(wd_buf, CANARY);

        if (stateful) {
            if (abi.init.?(@intCast(WD_W), @intCast(WD_H), 2.0)) |wd_st| {
                defer abi.deinit.?(wd_st);
                abi.step.?(wd_st, dt);
                abi.draw.?(wd_st, wd_buf.ptr, wd_buf.len, wd_stride);
                if (abi.has_nan) |nan_f| {
                    if (nan_f(wd_st)) watchdog_ok = false;
                }
                if (!paddingIntact(wd_buf, WD_W, WD_H, wd_stride)) watchdog_ok = false;
            } else {
                watchdog_ok = false;
            }
        } else if (abi.stateless) |render_fn| {
            render_fn(wd_buf.ptr, @intCast(WD_W), @intCast(WD_H), 0.1, 1);
        }
    }

    // The padded frames (stride = width + 16, canaries in the padding) check `y * stride + x`.
    hooks.enter(.init);
    const padded_stride = width + PAD;
    const padded_buf = try alloc.alloc(u32, padded_stride * height);
    defer alloc.free(padded_buf);
    @memset(padded_buf, CANARY);

    const tight_buf = final;
    @memset(tight_buf, 0);

    const frame1_buf = try alloc.alloc(u32, width * height);
    defer alloc.free(frame1_buf);
    @memset(frame1_buf, 0);

    var state_ptr: ?*anyopaque = null;
    const scale: f64 = if (width >= 1920) 2.0 else 1.0;
    if (stateful) {
        state_ptr = abi.init.?(@intCast(width), @intCast(height), scale) orelse return error.InitReturnedNull;
    }
    defer if (stateful and state_ptr != null) abi.deinit.?(state_ptr);

    var r = Result{
        .stateful = stateful,
        .width = width,
        .height = height,
        .padded_stride = padded_stride,
        .n_frames = n_frames,
        .watchdog_ok = watchdog_ok,
        .allocs_init = if (abi.allocs_init) |f| f() else 0,
        .bytes_live = if (abi.bytes_live) |f| f() else 0,
    };

    hooks.enter(.frames);
    for (0..n_frames) |f| {
        const t0 = hooks.now_ns(hooks.ctx);
        if (stateful) {
            abi.step.?(state_ptr, dt);
            if (f == 0) {
                abi.draw.?(state_ptr, frame1_buf.ptr, frame1_buf.len, width);
            } else if (f + 1 < n_frames) {
                // Intermediate frames on padded_stride verify `y * stride + x` indexing.
                abi.draw.?(state_ptr, padded_buf.ptr, padded_buf.len, padded_stride);
            } else {
                // The final frame into tight_buf (stride == width).
                abi.draw.?(state_ptr, tight_buf.ptr, tight_buf.len, width);
            }
            if (abi.has_nan) |nan_fn| {
                if (nan_fn(state_ptr)) r.nan_detected = true;
            }
        } else {
            abi.stateless.?(tight_buf.ptr, @intCast(width), @intCast(height), @as(f64, @floatFromInt(f)) * dt, f);
            if (f == 0) @memcpy(frame1_buf, tight_buf);
        }
        const t1 = hooks.now_ns(hooks.ctx);
        const elapsed: u64 = t1 -| t0;
        r.total_ns += elapsed;
        if (elapsed > r.worst_ns) r.worst_ns = elapsed;
    }

    hooks.enter(.inspect);
    if (stateful and n_frames > 1) r.canary_corrupted = !paddingIntact(padded_buf, width, height, padded_stride);
    r.allocs_after = if (abi.allocs_after) |f| f() else 0;
    const s = frameStats(tight_buf, frame1_buf);
    r.distinct_pixels = s.distinct;
    r.bad_alpha_pixels = s.bad_alpha;
    r.animated_pixels = s.animated;
    hooks.enter(.done);
    return r;
}

/// True when every padding column [w, stride) of every row still holds the canary.
pub fn paddingIntact(buf: []const u32, w: usize, h: usize, stride: usize) bool {
    for (0..h) |y| {
        for (w..stride) |x| {
            if (buf[y * stride + x] != CANARY) return false;
        }
    }
    return true;
}

pub const FrameStats = struct { distinct: usize, bad_alpha: usize, animated: usize };

/// Gate 5 and 6 counts: pixels unlike the top-left one, pixels with alpha 0, and pixels that
/// moved visibly (|dR| + |dG| + |dB| >= 4) since frame 1.
pub fn frameStats(final: []const u32, first: []const u32) FrameStats {
    const bg_pixel = final[0];
    var s = FrameStats{ .distinct = 0, .bad_alpha = 0, .animated = 0 };
    for (final, 0..) |px, idx| {
        if (px != bg_pixel) s.distinct += 1;
        if ((px >> 24) == 0) s.bad_alpha += 1;
        const p0 = first[idx];
        if (px != p0) {
            const r1: i32 = @intCast(px & 0xFF);
            const g1: i32 = @intCast((px >> 8) & 0xFF);
            const b1: i32 = @intCast((px >> 16) & 0xFF);
            const r0: i32 = @intCast(p0 & 0xFF);
            const g0: i32 = @intCast((p0 >> 8) & 0xFF);
            const b0: i32 = @intCast((p0 >> 16) & 0xFF);
            const diff = @abs(r1 - r0) + @abs(g1 - g0) + @abs(b1 - b0);
            if (diff >= MOTION_DIFF) s.animated += 1;
        }
    }
    return s;
}

test "padding check finds one stray write" {
    var buf: [4 * 3]u32 = @splat(CANARY);
    for (0..3) |y| @memset(buf[y * 4 ..][0..3], 0xFF00_0000);
    try std.testing.expect(paddingIntact(&buf, 3, 3, 4));
    buf[2 * 4 + 3] = 0;
    try std.testing.expect(!paddingIntact(&buf, 3, 3, 4));
}

test "frame stats count distinct, transparent and moved pixels" {
    const first = [_]u32{ 0xFF00_0000, 0xFF00_0000, 0xFF00_0000, 0xFF00_0000 };
    const final = [_]u32{ 0xFF00_0000, 0xFF00_0003, 0x0000_0000, 0xFF01_0101 };
    const s = frameStats(&final, &first);
    try std.testing.expectEqual(@as(usize, 3), s.distinct);
    try std.testing.expectEqual(@as(usize, 1), s.bad_alpha);
    // 0x03: diff 3 (not visible); 0x00000000: diff 0; 0x010101: diff 3.
    try std.testing.expectEqual(@as(usize, 0), s.animated);
}

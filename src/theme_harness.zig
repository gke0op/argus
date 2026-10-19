// ============================================================================
// ARGUS HEADLESS THEME HARNESS // src/theme_harness.zig
//
// Single-command compiler, benchmark, memory-audit, stride-canary, NaN-check,
// and PNG-export harness for native Zig Argus themes, and (GPU mode) for Metal-only
// themes, which it compiles with the Argus prelude and renders headless on the GPU:
//
//   zig run -O ReleaseFast -lc src/theme_harness.zig -- themes/Cygnus_A.zig --frames 120 --out /tmp/cygnus.png
//   zig run -O ReleaseFast -lc src/theme_harness.zig -- themes/Tutorial_Tides.metal
// ============================================================================

const std = @import("std");
const mtl = @import("gpu/metal.zig");
const metal_theme = @import("gpu/metal_theme.zig");
const system_stats = @import("desktop/system_stats.zig");

/// GPU frame budget for Metal themes: 120 FPS worth, leaving the GPU nearly idle at 30 FPS.
const METAL_BUDGET_US: f64 = 8333.0;
const METAL_DT: f32 = 1.0 / 30.0;
/// `--fps N` (Metal, 30/60/120): pace the live-cost profile at the app's frame rate N, with
/// argus_step at 30 Hz and draw-only frames in between, as the app does (desktop/frame_rate.zig).
/// The budget verdict stays tied to the 30 FPS default.
var paced_fps: u32 = 30;
/// `--no-budget` (CI on shared runners): frame time is reported but not part of the verdict.
var enforce_budget = true;
/// `--seed N` (Metal): the f.seed a theme sees. The app derives one per Space; the harness pins
/// 0x5EED so renders are repeatable. Render a few seeds to check a seeded composition holds up.
var metal_seed: u32 = 0x5EED;
/// `--stats live` (`@argus stats` themes): read this Mac, a new sample every 30 frames, instead
/// of the fixed synthetic stats that keep renders the same on every machine.
var stats_live = false;
var live_sampler: system_stats.Sampler = .{};
var live_block: ?u32 = null;
var live_cost_ns: u64 = 0;
var live_samples: u32 = 0;

/// Before each encode of an `@argus stats` theme under `--stats live`: a fresh reading of the
/// Mac whenever the theme reaches a new 30-tick block (the synthetic feed's pace).
fn feedLiveStats(theme: *metal_theme.Theme) void {
    if (!stats_live or !theme.dir.stats) return;
    theme.stats_live = true;
    const block = theme.frame.frame / 30;
    if (live_block == block) return;
    live_block = block;
    const t0 = threadCpuNs();
    var st = theme.stats;
    if (!live_sampler.sample(&st)) _ = live_sampler.sample(&st); // the first one is a baseline
    live_cost_ns += threadCpuNs() - t0;
    live_samples += 1;
    st.seq = theme.stats.seq + 1;
    theme.stats = st;
}

fn threadCpuNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.THREAD_CPUTIME_ID, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}
/// `--date YYYY-MM-DDTHH:MM:SSZ` (Metal): the UTC instant f.days_j2000 / f.day_frac start at,
/// advancing with the frames' clock (1/30 s a frame). Pinned so renders don't depend on today;
/// f.utc_offset_s is 0.
var metal_date: i64 = 1_792_497_600;
var metal_date_str: []const u8 = "2026-10-20T12:00:00Z";

const MetalRun = struct { ok: bool, gpu_us_avg: f64 = 0, gpu_us_worst: f64 = 0, err: [*:0]const u8 = "" };

/// Renders `frames` frames of a compiled Metal theme into `out`; frame 0 lands in `first`, the last in `last`.
fn runMetal(theme: *metal_theme.Theme, out: mtl.Id, frames: usize, first: ?[]f32, last: ?[]f32) MetalRun {
    const w: usize = theme.frame.width;
    const h: usize = theme.frame.height;
    var total: f64 = 0;
    var worst: f64 = 0;
    for (0..frames) |f| {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const cb = mtl.msg(mtl.Id, theme.queue, "commandBuffer", .{});
        feedLiveStats(theme);
        theme.encode(cb, out, METAL_DT);
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        if (mtl.msg(usize, cb, "status", .{}) == 5) { // MTLCommandBufferStatusError
            return .{ .ok = false, .err = mtl.describe(mtl.msg(mtl.Id, cb, "error", .{})) };
        }
        const us = gpuUs(cb);
        if (f > 0) { // frame 0 includes one-time init and pipeline warm-up
            total += us;
            worst = @max(worst, us);
        }
        const dst = if (f == 0) first else if (f == frames - 1) last else null;
        if (dst) |d| mtl.msg(void, out, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", .{
            @as(*anyopaque, @ptrCast(d.ptr)), w * 16, mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = w, .h = h, .d = 1 }, @as(usize, 0),
        });
    }
    return .{ .ok = true, .gpu_us_avg = total / @as(f64, @floatFromInt(@max(1, frames - 1))), .gpu_us_worst = worst };
}

const Profile = struct { frame_us: f64 = 0, draw_us: f64 = 0, paced_us: f64 = 0, paced_ms_per_s: f64 = 0 };

fn gpuUs(cb: mtl.Id) f64 {
    return (mtl.msg(f64, cb, "GPUEndTime", .{}) - mtl.msg(f64, cb, "GPUStartTime", .{})) * 1e6;
}

/// Times `frames` more frames the way the app draws them: into a BGRA8 texture (the
/// drawable's format; the main run writes RGBA32F, 4x the bytes, for the NaN check).
/// Each frame is timed whole, then argus_draw alone on the same state, so the split is
/// init+step = frame - draw. Medians, so one stray hitch doesn't skew it.
fn profileMetal(theme: *metal_theme.Theme, frames: usize) Profile {
    const out = mtl.newTexture(theme.dev, mtl.PIXEL_BGRA8, theme.frame.width, theme.frame.height, mtl.STORAGE_PRIVATE);
    defer mtl.release(out);
    var whole: [256]f64 = undefined;
    var draw: [256]f64 = undefined;
    const n = @min(frames, whole.len);
    for (0..n) |f| {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const cb = mtl.msg(mtl.Id, theme.queue, "commandBuffer", .{});
        feedLiveStats(theme);
        theme.encode(cb, out, METAL_DT);
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        const cb2 = mtl.msg(mtl.Id, theme.queue, "commandBuffer", .{});
        theme.encodeDrawOnly(cb2, out);
        mtl.msg(void, cb2, "commit", .{});
        mtl.msg(void, cb2, "waitUntilCompleted", .{});
        whole[f] = gpuUs(cb);
        draw[f] = gpuUs(cb2);
    }
    std.mem.sort(f64, whole[0..n], {}, std.sort.asc(f64));
    std.mem.sort(f64, draw[0..n], {}, std.sort.asc(f64));

    // The app draws one frame every 33 ms, and the GPU doesn't raise its clock for such a
    // light periodic load: the same frame then takes ~1.9x as long as back-to-back (M3).
    // Time 45 frames paced like the app, so the report shows the live cost too.
    // At 60 / 120 FPS (`--fps`) the clock moves by the frame interval and argus_step runs on every
    // 2nd / 4th frame only, as in the app; the window stays 1.5 s.
    const ratio: usize = paced_fps / 30;
    const interval_ns: u64 = 1_000_000_000 / paced_fps;
    var paced_buf: [180]f64 = undefined;
    const paced = paced_buf[0 .. 45 * ratio];
    var gpu_total: f64 = 0;
    for (paced, 0..) |*v, f| {
        const t0 = nowNs();
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const cb = mtl.msg(mtl.Id, theme.queue, "commandBuffer", .{});
        feedLiveStats(theme);
        theme.encodeTimes(cb, out, 1.0 / @as(f32, @floatFromInt(paced_fps)), if (f % ratio == 0) METAL_DT else null);
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        v.* = gpuUs(cb);
        gpu_total += v.*;
        const spent = nowNs() - t0;
        if (spent < interval_ns) {
            const left = interval_ns - spent;
            const ts: std.c.timespec = .{ .sec = 0, .nsec = @intCast(left) };
            _ = std.c.nanosleep(&ts, null);
        }
    }
    std.mem.sort(f64, paced, {}, std.sort.asc(f64));
    const secs = @as(f64, @floatFromInt(paced.len)) / @as(f64, @floatFromInt(paced_fps));
    return .{ .frame_us = whole[n / 2], .draw_us = draw[n / 2], .paced_us = paced[paced.len / 2], .paced_ms_per_s = gpu_total / 1000.0 / secs };
}

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.UPTIME_RAW, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

fn packFloat(px: []const f32) u32 {
    var c: [3]u32 = undefined;
    for (0..3) |i| c[i] = @intFromFloat(@round(std.math.clamp(px[i], 0.0, 1.0) * 255.0));
    return (@as(u32, 255) << 24) | (c[2] << 16) | (c[1] << 8) | c[0];
}

fn metalHarness(io: std.Io, alloc: std.mem.Allocator, path: []const u8, n_frames: usize, width: usize, height: usize, out_png: []const u8) !void {
    var src_buf: [131072]u8 = undefined;
    const src = try std.Io.Dir.cwd().readFile(io, path, &src_buf);
    const label = std.Io.Dir.path.basename(path);
    const frames = @max(n_frames, 2);
    var err_buf: [4096]u8 = undefined;
    const data = metal_theme.loadData(io, alloc, path, src) catch |e| {
        std.debug.print("METAL DATA FILE FAILED: {s}: {s}\nVerdict           : FAIL\n", .{ path, @errorName(e) });
        std.process.exit(1);
    };
    defer if (data) |d| alloc.free(d);

    var theme = metal_theme.Theme.compile(src, label, data, @intCast(width), @intCast(height), metal_seed, &err_buf) catch {
        std.debug.print("METAL COMPILE FAILED: {s}\n{s}\nVerdict           : FAIL\n", .{ path, std.mem.sliceTo(&err_buf, 0) });
        std.process.exit(1);
    };
    defer theme.deinit();
    theme.wall = .{ .fixed = .{ .unix_s = metal_date } };

    // Watchdog: a small 320x200 instance must run too (no size assumptions in the kernels).
    var wd_ok = false;
    if (metal_theme.Theme.compile(src, label, data, 320, 200, 1, &err_buf)) |wd_theme| {
        var wd = wd_theme;
        defer wd.deinit();
        wd.wall = .{ .fixed = .{ .unix_s = metal_date } };
        const wd_out = mtl.newTexture(wd.dev, mtl.PIXEL_RGBA32F, 320, 200, mtl.STORAGE_SHARED);
        defer mtl.release(wd_out);
        wd_ok = runMetal(&wd, wd_out, 3, null, null).ok;
    } else |_| {}

    const out = mtl.newTexture(theme.dev, mtl.PIXEL_RGBA32F, width, height, mtl.STORAGE_SHARED);
    defer mtl.release(out);
    const first = try alloc.alloc(f32, width * height * 4);
    defer alloc.free(first);
    const last = try alloc.alloc(f32, width * height * 4);
    defer alloc.free(last);
    const run = runMetal(&theme, out, frames, first, last);
    if (!run.ok) {
        std.debug.print("METAL RUN FAILED: {s}: {s}\nVerdict           : FAIL\n", .{ path, run.err });
        std.process.exit(1);
    }

    const prof = profileMetal(&theme, 120);

    var nan_detected = false;
    for (first) |v| if (!std.math.isFinite(v)) {
        nan_detected = true;
        break;
    };
    for (last) |v| if (!std.math.isFinite(v)) {
        nan_detected = true;
        break;
    };

    const packed_px = try alloc.alloc(u32, width * height);
    defer alloc.free(packed_px);
    for (packed_px, 0..) |*p, i| p.* = packFloat(last[i * 4 .. i * 4 + 4]);
    const bg_pixel = packed_px[0];
    var distinct_pixels: usize = 0;
    var animated_pixels: usize = 0;
    for (packed_px, 0..) |px, i| {
        if (px != bg_pixel) distinct_pixels += 1;
        const p0 = packFloat(first[i * 4 .. i * 4 + 4]);
        var diff: i32 = 0;
        inline for (0..3) |ch| diff += @intCast(@abs(@as(i32, @intCast((px >> (8 * ch)) & 0xFF)) - @as(i32, @intCast((p0 >> (8 * ch)) & 0xFF))));
        if (diff >= 4) animated_pixels += 1;
    }
    try writePNG(packed_px, width, height, out_png);

    const motion_ok = animated_pixels >= 2_000;
    const pass = wd_ok and !nan_detected and distinct_pixels > 100 and motion_ok and (!enforce_budget or run.gpu_us_avg < METAL_BUDGET_US);
    const start = metal_theme.j2000(metal_date, 0);
    // The frame count and the date go in as one argument: the report is at std.fmt's 32-argument limit.
    var date_buf: [192]u8 = undefined;
    const frames_date = try std.fmt.bufPrint(&date_buf, " Frames Rendered   : {d} (dt = 1/30 s)\n Date (UTC)        : {s} at frame 0 (J2000 day {d} + {d:.6}), offset 0 (--date)", .{ frames, metal_date_str, start.days, start.frac });
    const st_desc = if (theme.stateful()) "state texture" else "stateless";
    var stats_buf: [160]u8 = undefined;
    const stats_line = if (!theme.dir.stats) "" else if (stats_live)
        try std.fmt.bufPrint(&stats_buf, " Stats (buffer 1)  : live, {d} samples of this Mac, {d:.0} us CPU each\n", .{ live_samples, @as(f64, @floatFromInt(live_cost_ns)) / 1000.0 / @as(f64, @floatFromInt(@max(1, live_samples))) })
    else
        " Stats (buffer 1)  : synthetic (fixed values, a new seq every 30 frames; --stats live reads this Mac)\n";
    var out_buf: [2048]u8 = undefined;
    const report = try std.fmt.bufPrint(&out_buf,
        \\========================================================================
        \\ ARGUS HEADLESS THEME HARNESS (GPU / Metal) // VERIFICATION REPORT
        \\------------------------------------------------------------------------
        \\ Theme             : {s} (Metal-only, {s}{s})
        \\ State             : {d}x{d} {s}, {d} step(s) per frame
        \\ Resolution        : {d}x{d} (and 320x200 watchdog)
        \\{s}
        \\ Avg GPU Frame     : {d:.1} us | Budget: {d:.1} us{s}
        \\ Worst GPU Frame   : {d:.1} us
        \\ Profile (BGRA8)   : {d:.1} us median frame = {d:.1} us init/step + {d:.1} us draw
        \\ Paced {d:>3} FPS     : {d:.1} us median frame, {d:.1} ms GPU per second (the live cost: the GPU clocks lower between frames)
        \\ Draw Threadgroup  : {d}x{d} (max {d}; a SIMD group is one 32-px row of it)
        \\ Watchdog 320x200  : {s}
        \\ NaN / Inf Check   : {s}
        \\ Pixel Variance    : {d} / {d} non-bg pixels
        \\ Temporal Motion   : {d} / {d} visibly animated pixels (min required: 2000)
        \\{s} Output PNG        : {s}
        \\ Verdict           : {s}
        \\========================================================================
        \\
    , .{
        path,                              st_desc,
        if (theme.step != null) ", argus_step" else "",
        theme.dir.state_w,                 theme.dir.state_h,
        if (theme.dir.state_f32) "float32" else "float16",
        if (theme.step != null) theme.dir.steps else 0,
        width,                             height,
        frames_date,
        run.gpu_us_avg,
        METAL_BUDGET_US,                   if (enforce_budget) "" else " (not enforced)",
        run.gpu_us_worst,
        prof.frame_us,                     @max(0.0, prof.frame_us - prof.draw_us),
        prof.draw_us,
        paced_fps,                         prof.paced_us,
        prof.paced_ms_per_s,
        theme.draw.group.w,                theme.draw.group.h,
        theme.draw.max_threads,
        if (wd_ok) "PASS" else "FAIL (failed to compile or run at 320x200)",
        if (nan_detected) "FAIL (NaN/Inf in the output!)" else "CLEAN",
        distinct_pixels,                   width * height,
        animated_pixels,                   width * height,
        stats_line,                        out_png,                           if (pass) "PASS" else "FAIL",
    });
    try std.Io.File.stdout().writeStreamingAll(io, report);
    if (!pass) std.process.exit(1);
}

const FnInit = *const fn (w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque;
const FnDeinit = *const fn (state: ?*anyopaque) callconv(.c) void;
const FnStep = *const fn (state: ?*anyopaque, dt: f64) callconv(.c) void;
const FnDraw = *const fn (state: ?*anyopaque, pixels: [*]u32, buf_len: usize, stride: usize) callconv(.c) void;
const FnCount = *const fn () callconv(.c) usize;
const FnHasNaN = *const fn (state: ?*anyopaque) callconv(.c) bool;
const FnStateless = *const fn (pixels: [*]u32, w: u32, h: u32, phase: f64, step_count: u64) callconv(.c) void;

pub fn writePNG(pixels: []const u32, width: usize, height: usize, out_path: []const u8) !void {
    const libcg = std.c.dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", .{ .LAZY = true }) orelse return error.CGLoadFailed;
    const libcf = std.c.dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", .{ .LAZY = true }) orelse return error.CFLoadFailed;
    const libiio = std.c.dlopen("/System/Library/Frameworks/ImageIO.framework/ImageIO", .{ .LAZY = true }) orelse return error.ImageIOLoadFailed;

    const CGColorSpaceCreateDeviceRGB: *const fn () callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGColorSpaceCreateDeviceRGB") orelse return error.Sym));
    const CGBitmapContextCreate: *const fn (?*anyopaque, usize, usize, usize, usize, ?*anyopaque, u32) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGBitmapContextCreate") orelse return error.Sym));
    const CGBitmapContextCreateImage: *const fn (?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGBitmapContextCreateImage") orelse return error.Sym));
    const CGContextRelease: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextRelease") orelse return error.Sym));
    const CGImageRelease: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGImageRelease") orelse return error.Sym));

    const CFURLCreateFromFileSystemRepresentation: *const fn (?*anyopaque, [*]const u8, isize, bool) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFURLCreateFromFileSystemRepresentation") orelse return error.Sym));
    const CFStringCreateWithCString: *const fn (?*anyopaque, [*:0]const u8, u32) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFStringCreateWithCString") orelse return error.Sym));
    const CFRelease: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFRelease") orelse return error.Sym));

    const CGImageDestinationCreateWithURL: *const fn (?*anyopaque, ?*anyopaque, usize, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libiio, "CGImageDestinationCreateWithURL") orelse return error.Sym));
    const CGImageDestinationAddImage: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libiio, "CGImageDestinationAddImage") orelse return error.Sym));
    const CGImageDestinationFinalize: *const fn (?*anyopaque) callconv(.c) bool = @ptrCast(@alignCast(std.c.dlsym(libiio, "CGImageDestinationFinalize") orelse return error.Sym));

    const cs = CGColorSpaceCreateDeviceRGB() orelse return error.ColorSpaceFailed;
    defer CFRelease(cs);

    const ctx = CGBitmapContextCreate(
        @ptrCast(@constCast(pixels.ptr)),
        width,
        height,
        8,
        width * 4,
        cs,
        1 | (4 << 12), // kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    ) orelse return error.ContextFailed;
    defer CGContextRelease(ctx);

    const cg_img = CGBitmapContextCreateImage(ctx) orelse return error.ImageFailed;
    defer CGImageRelease(cg_img);

    const url = CFURLCreateFromFileSystemRepresentation(null, out_path.ptr, @intCast(out_path.len), false) orelse return error.URLFailed;
    defer CFRelease(url);

    const uti_png = CFStringCreateWithCString(null, "public.png", 0x08000100) orelse return error.UTIFailed;
    defer CFRelease(uti_png);

    const dest = CGImageDestinationCreateWithURL(url, uti_png, 1, null) orelse return error.DestFailed;
    defer CFRelease(dest);

    CGImageDestinationAddImage(dest, cg_img, null);
    if (!CGImageDestinationFinalize(dest)) return error.PNGFinalizeFailed;
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var theme_path: ?[]const u8 = null;
    var n_frames: usize = 120;
    var out_png: []const u8 = "/tmp/argus_theme_out.png";
    var width: usize = 1920;
    var height: usize = 1200;
    const dt: f64 = 0.008;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--frames") and i + 1 < args.len) {
            i += 1;
            n_frames = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, a, "--out") and i + 1 < args.len) {
            i += 1;
            out_png = args[i];
        } else if (std.mem.eql(u8, a, "--width") and i + 1 < args.len) {
            i += 1;
            width = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, a, "--height") and i + 1 < args.len) {
            i += 1;
            height = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, a, "--seed") and i + 1 < args.len) {
            i += 1;
            metal_seed = try std.fmt.parseInt(u32, args[i], 0);
        } else if (std.mem.eql(u8, a, "--fps") and i + 1 < args.len) {
            i += 1;
            const f = try std.fmt.parseInt(u32, args[i], 10);
            if (f != 30 and f != 60 and f != 120) return error.FpsMustBe30Or60Or120;
            paced_fps = f;
        } else if (std.mem.eql(u8, a, "--stats") and i + 1 < args.len) {
            i += 1;
            if (std.mem.eql(u8, args[i], "live")) stats_live = true else if (!std.mem.eql(u8, args[i], "synthetic")) return error.StatsMustBeLiveOrSynthetic;
        } else if (std.mem.eql(u8, a, "--date") and i + 1 < args.len) {
            i += 1;
            metal_date = metal_theme.parseIsoUtc(args[i]) catch return error.DateMustBeYYYYMMDDTHHMMSSZ;
            metal_date_str = args[i];
        } else if (std.mem.eql(u8, a, "--no-budget")) {
            enforce_budget = false;
        } else if (std.mem.eql(u8, a, "--probe-metal")) {
            // CI: exit 0 when this machine has a Metal device for the GPU checks, 3 when not.
            mtl.load() catch std.process.exit(3);
            _ = mtl.device() catch std.process.exit(3);
            std.process.exit(0);
        } else if (!std.mem.startsWith(u8, a, "-")) {
            theme_path = a;
        }
    }

    const path = theme_path orelse {
        var ebuf: [256]u8 = undefined;
        const emsg = std.fmt.bufPrint(&ebuf, "Usage: ./.toolchain/zig run -O ReleaseFast -lc src/theme_harness.zig -- <theme.zig> [--frames N] [--out /tmp/out.png] [--seed N] [--fps N] [--date YYYY-MM-DDTHH:MM:SSZ]\n", .{}) catch "";
        try std.Io.File.stderr().writeStreamingAll(io, emsg);
        std.process.exit(1);
    };

    if (std.mem.endsWith(u8, path, ".metal")) return metalHarness(io, alloc, path, n_frames, width, height, out_png);

    var dylib_buf: [256]u8 = undefined;
    var emit_buf: [280]u8 = undefined;
    const now_ns = std.Io.Clock.real.now(io).nanoseconds;
    // The per-user temp folder (0700 on macOS), not /tmp: nobody else can swap the library
    // between the compile and the dlopen.
    const tmp_dir = std.mem.trimEnd(u8, init.environ_map.get("TMPDIR") orelse "/tmp", "/");
    const dylib_z = try std.fmt.bufPrintSentinel(&dylib_buf, "{s}/argus_harness_{d}.dylib", .{ tmp_dir, now_ns }, 0);
    const emit_arg = try std.fmt.bufPrint(&emit_buf, "-femit-bin={s}", .{dylib_z});

    // Resolve Zig 0.17+ toolchain portably across machines (.toolchain/zig -> $ZIG -> $HOME/zig-toolchains/zig-0.17.0/zig -> PATH zig)
    var home_zig_buf: [512]u8 = undefined;
    const zig_bin: []const u8 = blk: {
        if (std.Io.Dir.cwd().access(io, ".toolchain/zig", .{})) |_| {
            break :blk ".toolchain/zig";
        } else |_| {}
        if (init.environ_map.get("ZIG")) |env_zig| {
            if (env_zig.len > 0) break :blk env_zig;
        }
        if (init.environ_map.get("HOME")) |home| {
            if (std.fmt.bufPrint(&home_zig_buf, "{s}/zig-toolchains/zig-0.17.0/zig", .{home})) |cand| {
                if (std.Io.Dir.cwd().access(io, cand, .{})) |_| {
                    break :blk cand;
                } else |_| {}
            } else |_| {}
        }
        break :blk "zig";
    };

    // Compile the theme into an aarch64-macos shared library using Zig 0.17.0
    const res = try std.process.run(alloc, io, .{
        .argv = &[_][]const u8{
            zig_bin,
            "build-lib",
            path,
            "-dynamic",
            "-O",
            "ReleaseFast",
            "-target",
            "aarch64-macos",
            "-lc",
            emit_arg,
        },
    });
    defer alloc.free(res.stdout);
    defer alloc.free(res.stderr);

    switch (res.term) {
        .exited => |code| if (code != 0) {
            try std.Io.File.stderr().writeStreamingAll(io, "Theme compilation failed:\n");
            try std.Io.File.stderr().writeStreamingAll(io, res.stderr);
            std.process.exit(1);
        },
        else => std.process.exit(1),
    }
    defer std.Io.Dir.deleteFileAbsolute(io, dylib_z) catch {};

    const handle = std.c.dlopen(dylib_z.ptr, .{ .NOW = true }) orelse {
        try std.Io.File.stderr().writeStreamingAll(io, "dlopen failed on compiled theme .dylib\n");
        std.process.exit(1);
    };
    defer _ = std.c.dlclose(handle);

    const fn_init: ?FnInit = if (std.c.dlsym(handle, "argus_theme_init")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_deinit: ?FnDeinit = if (std.c.dlsym(handle, "argus_theme_deinit")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_step: ?FnStep = if (std.c.dlsym(handle, "argus_theme_step")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_draw: ?FnDraw = if (std.c.dlsym(handle, "argus_theme_draw")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_allocs_init: ?FnCount = if (std.c.dlsym(handle, "argus_theme_allocs_init")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_allocs_after: ?FnCount = if (std.c.dlsym(handle, "argus_theme_allocs_after_init")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_bytes_live: ?FnCount = if (std.c.dlsym(handle, "argus_theme_bytes_live")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_has_nan: ?FnHasNaN = if (std.c.dlsym(handle, "argus_theme_has_nan")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_stateless: ?FnStateless = if (std.c.dlsym(handle, "argus_render_theme")) |p| @ptrCast(@alignCast(p)) else null;

    const is_stateful = (fn_init != null and fn_step != null and fn_draw != null and fn_deinit != null);
    if (!is_stateful and fn_stateless == null) {
        try std.Io.File.stderr().writeStreamingAll(io, "Theme exports neither stateful (argus_theme_init/step/draw/deinit) nor stateless (argus_render_theme) ABI!\n");
        std.process.exit(1);
    }

    // 0. Run 320x200 Watchdog Probe (exact parity with Argus.app `--verify-dylib` in space_config.zig)
    var watchdog_ok = true;
    {
        const wd_w: usize = 320;
        const wd_h: usize = 200;
        const wd_stride: usize = wd_w + 8;
        const wd_canary: u32 = 0xDEADBEEF;
        const wd_buf = try alloc.alloc(u32, wd_stride * wd_h);
        defer alloc.free(wd_buf);
        @memset(wd_buf, wd_canary);

        if (is_stateful) {
            if (fn_init.?(@intCast(wd_w), @intCast(wd_h), 2.0)) |wd_st| {
                defer fn_deinit.?(wd_st);
                fn_step.?(wd_st, dt);
                fn_draw.?(wd_st, wd_buf.ptr, wd_buf.len, wd_stride);
                if (fn_has_nan) |nan_f| {
                    if (nan_f(wd_st)) watchdog_ok = false;
                }
                for (0..wd_h) |wy| {
                    for (wd_w..wd_stride) |wx| {
                        if (wd_buf[wy * wd_stride + wx] != wd_canary) {
                            watchdog_ok = false;
                            break;
                        }
                    }
                }
            } else {
                watchdog_ok = false;
            }
        } else if (fn_stateless) |render_fn| {
            render_fn(wd_buf.ptr, @intCast(wd_w), @intCast(wd_h), 0.1, 1);
        }
    }

    // Allocate padded buffer (stride = width + 16) filled with canary 0xDEAD_BEEF to verify stride discipline
    const pad: usize = 16;
    const padded_stride = width + pad;
    const canary: u32 = 0xDEADBEEF;
    const padded_buf = try alloc.alloc(u32, padded_stride * height);
    defer alloc.free(padded_buf);
    @memset(padded_buf, canary);

    const tight_buf = try alloc.alloc(u32, width * height);
    defer alloc.free(tight_buf);
    @memset(tight_buf, 0);

    const frame1_buf = try alloc.alloc(u32, width * height);
    defer alloc.free(frame1_buf);
    @memset(frame1_buf, 0);

    var state_ptr: ?*anyopaque = null;
    const scale: f64 = if (width >= 1920) 2.0 else 1.0;
    if (is_stateful) {
        state_ptr = fn_init.?(@intCast(width), @intCast(height), scale) orelse {
            try std.Io.File.stderr().writeStreamingAll(io, "argus_theme_init returned null!\n");
            std.process.exit(1);
        };
    }
    defer if (is_stateful and state_ptr != null) fn_deinit.?(state_ptr);

    const allocs_init: usize = if (fn_allocs_init) |f| f() else 0;
    const bytes_live: usize = if (fn_bytes_live) |f| f() else 0;

    var total_ns: u64 = 0;
    var worst_ns: u64 = 0;
    var nan_detected = false;
    var canary_corrupted = false;

    for (0..n_frames) |f| {
        const t0 = std.Io.Clock.awake.now(io);
        if (is_stateful) {
            fn_step.?(state_ptr, dt);
            if (f == 0) {
                fn_draw.?(state_ptr, frame1_buf.ptr, frame1_buf.len, width);
            } else if (f + 1 < n_frames) {
                // Run intermediate frames on padded_stride to verify `y * stride + x` indexing
                fn_draw.?(state_ptr, padded_buf.ptr, padded_buf.len, padded_stride);
            } else {
                // Final frame into tight_buf (stride == width) for PNG export
                fn_draw.?(state_ptr, tight_buf.ptr, tight_buf.len, width);
            }
            if (fn_has_nan) |nan_fn| {
                if (nan_fn(state_ptr)) nan_detected = true;
            }
        } else {
            fn_stateless.?(tight_buf.ptr, @intCast(width), @intCast(height), @as(f64, @floatFromInt(f)) * dt, f);
            if (f == 0) @memcpy(frame1_buf, tight_buf);
        }
        const elapsed: u64 = @intCast(@max(@as(i96, 0), t0.durationTo(std.Io.Clock.awake.now(io)).nanoseconds));
        total_ns += elapsed;
        if (elapsed > worst_ns) worst_ns = elapsed;
    }

    // Check padded_buf canary columns [width .. width + pad] on every row
    if (is_stateful and n_frames > 1) {
        outer: for (0..height) |y| {
            for (width..padded_stride) |x| {
                if (padded_buf[y * padded_stride + x] != canary) {
                    canary_corrupted = true;
                    break :outer;
                }
            }
        }
    }

    const allocs_after: usize = if (fn_allocs_after) |f| f() else 0;

    // Inspect final frame pixels for non-background variance, valid alpha (0xFF), and temporal motion vs Frame 1
    const bg_pixel = tight_buf[0];
    var distinct_pixels: usize = 0;
    var bad_alpha_pixels: usize = 0;
    var animated_pixels: usize = 0;
    for (tight_buf, 0..) |px, idx| {
        if (px != bg_pixel) distinct_pixels += 1;
        if ((px >> 24) == 0) bad_alpha_pixels += 1;
        const p0 = frame1_buf[idx];
        if (px != p0) {
            const r1: i32 = @intCast(px & 0xFF);
            const g1: i32 = @intCast((px >> 8) & 0xFF);
            const b1: i32 = @intCast((px >> 16) & 0xFF);
            const r0: i32 = @intCast(p0 & 0xFF);
            const g0: i32 = @intCast((p0 >> 8) & 0xFF);
            const b0: i32 = @intCast((p0 >> 16) & 0xFF);
            const diff = @abs(r1 - r0) + @abs(g1 - g0) + @abs(b1 - b0);
            if (diff >= 4) animated_pixels += 1;
        }
    }

    try writePNG(tight_buf, width, height, out_png);

    const avg_us = (@as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(@max(@as(usize, 1), n_frames)))) / 1000.0;
    const worst_us = @as(f64, @floatFromInt(worst_ns)) / 1000.0;

    const alloc_ok = if (is_stateful) (allocs_init == 1 and allocs_after == 0) else (allocs_after == 0);
    const motion_ok = if (n_frames > 1) (animated_pixels >= 2_000) else true;
    const pass = watchdog_ok and alloc_ok and !nan_detected and !canary_corrupted and distinct_pixels > 100 and bad_alpha_pixels == 0 and motion_ok and (!enforce_budget or avg_us < 16667.0);

    var out_buf: [2048]u8 = undefined;
    const report = try std.fmt.bufPrint(
        &out_buf,
        \\========================================================================
        \\ ARGUS HEADLESS THEME HARNESS (Zig 0.17.0) // VERIFICATION REPORT
        \\------------------------------------------------------------------------
        \\ Theme             : {s} ({s})
        \\ Resolution        : {d}x{d} (tested stride={d}, stride={d}, and 320x200 watchdog)
        \\ Frames Rendered   : {d} (fixed dt = {d:.6})
        \\ Avg Frame Time    : {d:.1} us ({d:.1} FPS) | Budget: 16667.0 us{s}
        \\ Worst Frame Time  : {d:.1} us
        \\ Allocs at Init    : {d} ({d} bytes)
        \\ Allocs after Init : {d}
        \\ Watchdog 320x200  : {s}
        \\ Stride Guard      : {s}
        \\ NaN / Inf Check   : {s}
        \\ Pixel Variance    : {d} / {d} non-bg pixels (alpha=0 count: {d})
        \\ Temporal Motion   : {d} / {d} visibly animated pixels (min required: 2000)
        \\ Output PNG        : {s}
        \\ Verdict           : {s}
        \\========================================================================
        \\
    ,
        .{
            path,
            if (is_stateful) "Stateful SDK Contract" else "Stateless C-ABI",
            width,
            height,
            padded_stride,
            width,
            n_frames,
            dt,
            avg_us,
            1_000_000.0 / @max(0.1, avg_us),
            if (enforce_budget) "" else " (not enforced)",
            worst_us,
            allocs_init,
            bytes_live,
            allocs_after,
            if (watchdog_ok) "PASS" else "FAIL (crashed or failed at 320x200)",
            if (canary_corrupted) "FAIL (wrote into stride padding!)" else "CLEAN (0 out-of-bounds canary writes)",
            if (nan_detected) "FAIL (NaN/Inf detected!)" else "CLEAN",
            distinct_pixels,
            width * height,
            bad_alpha_pixels,
            animated_pixels,
            width * height,
            out_png,
            if (pass) "PASS" else "FAIL",
        },
    );
    try std.Io.File.stdout().writeStreamingAll(io, report);

    if (!pass) std.process.exit(1);
}

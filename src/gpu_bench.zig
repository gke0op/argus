// ============================================================================
// ARGUS GPU // src/gpu_bench.zig
//
// Headless check of H1821's GPU path against the theme's own CPU path:
//   1. Shadow edge: the GPU's f32 geodesics bisected against Bardeen's analytic
//      critical curve. Themes exporting shadowContour (H1821) get the full-contour
//      sweep, GPU f32 and CPU f64 on the same samples, max and RMS each; others the
//      11-point check.
//   2. 1920x1200: CPU trace + draw() vs GPU meter + trace + shade, same step() state;
//      reports exposure, pixel agreement, and timings.
//   3. Native size (--native WxH, default 3024x1964): GPU trace and per-frame times.
// Frames go to /tmp/argus_bh_{cpu,gpu,native}.rgba (RGBA8) for a look.
// Checked claims print as `LEDGER {json}` lines (src/ledger.zig); `make ledger` collects them.
//
//   make gpu-bench [GPU_FRAMES=120]
// ============================================================================

const std = @import("std");
const theme = @import("theme");
// Ledger id prefix and camera inclination of the theme under test (generated quasars carry their own).
const ID = if (@hasDecl(theme, "LEDGER_PREFIX")) theme.LEDGER_PREFIX else "h1821.";
const INCL_DEG: f64 = if (@hasDecl(theme, "INCL")) theme.INCL * 180.0 / std.math.pi else 88.0;
const mtl = @import("gpu/metal.zig");
const bt = @import("gpu/bh_tables.zig");
const bg = @import("gpu/bh_gpu.zig");
const ledger = @import("ledger.zig");

const LEDGER_SRC = "make gpu-bench";

const W: usize = 1920;
const H: usize = 1200;

fn msSince(io: std.Io, t0: std.Io.Timestamp) f64 {
    const ns = t0.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    return @as(f64, @floatFromInt(@max(@as(i96, 0), ns))) / 1e6;
}

fn gpuMs(cb: mtl.Id) f64 {
    return (mtl.msg(f64, cb, "GPUEndTime", .{}) - mtl.msg(f64, cb, "GPUStartTime", .{})) * 1e3;
}

fn saveRgba(path: []const u8, px: []const u32) void {
    var buf: [256]u8 = undefined;
    const z = std.fmt.bufPrintSentinel(&buf, "{s}", .{path}, 0) catch return;
    const f = std.c.fopen(z, "wb") orelse return;
    defer _ = std.c.fclose(f);
    _ = std.c.fwrite(std.mem.sliceAsBytes(px).ptr, 4, px.len, f);
}

/// Traces at w x h and shades one sRGB frame into `out` (w*h RGBA8). Returns timings.
fn gpuFrame(st: *theme.State, w: u32, h: u32, frames: usize, out: []u32, io: std.Io) !struct { meter_ms: f64, trace_ms: f64, shade_ms: f64, hdr_ms: f64, paced_hdr_ms: f64, exposure: f32 } {
    var stat: bt.Static = undefined;
    bt.fillStatic(st, &stat);
    var params: bt.TraceParams = undefined;
    bt.fillTrace(st, w, h, &params);
    var e = try bg.Engine.init(&stat, params, bt.noiseBytes(st), bt.ttabBytes(st));
    defer e.deinit();

    var t0 = std.Io.Clock.awake.now(io);
    const expo = e.meter();
    const meter_ms = msSince(io, t0);
    t0 = std.Io.Clock.awake.now(io);
    e.startTrace(16);
    e.waitTrace();
    const trace_ms = msSince(io, t0);
    if (e.failed) return error.GpuTraceFailed;

    const dev = e.k.dev;
    const queue = mtl.msg(mtl.Id, dev, "newCommandQueue", .{});
    defer mtl.release(queue);
    const tex8 = mtl.newTexture(dev, mtl.PIXEL_RGBA8, w, h, mtl.STORAGE_SHARED);
    defer mtl.release(tex8);
    const tex10 = mtl.newTexture(dev, mtl.PIXEL_BGR10A2, w, h, mtl.STORAGE_PRIVATE);
    defer mtl.release(tex10);

    var frame: bt.Frame = undefined;
    var shade_ms: f64 = 0;
    var hdr_ms: f64 = 0;
    for (0..frames) |f| {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        if (f > 0) st.step(0.008);
        bt.fillFrame(st, &frame);
        const hdr = f % 2 == 1; // alternate the HDR (16-bit float) and sRGB paths
        const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
        e.encodeShade(cb, &frame, if (hdr) tex10 else tex8, w, h, if (hdr) 4.0 else 1.0, if (hdr) .pq else .srgb);
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        if (hdr) hdr_ms += gpuMs(cb) else shade_ms += gpuMs(cb);
    }
    // The live cost: HDR frames paced like the app (one every 33 ms). At this light periodic
    // load the GPU stays at a low clock, so frames take longer than back-to-back above.
    var paced: [45]f64 = undefined;
    for (&paced) |*v| {
        const t_start = std.Io.Clock.awake.now(io);
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        st.step(0.008);
        bt.fillFrame(st, &frame);
        const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
        e.encodeShade(cb, &frame, tex10, w, h, 4.0, .pq);
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        v.* = gpuMs(cb);
        const spent_ms = msSince(io, t_start);
        if (spent_ms < 33.333) {
            const ns: u64 = @intFromFloat((33.333 - spent_ms) * 1e6);
            const ts: std.c.timespec = .{ .sec = 0, .nsec = @intCast(ns) };
            _ = std.c.nanosleep(&ts, null);
        }
    }
    std.mem.sort(f64, &paced, {}, std.sort.asc(f64));

    // Final sRGB frame for comparison / viewing, at the last step state.
    {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
        e.encodeShade(cb, &frame, tex8, w, h, 1.0, .srgb);
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        mtl.msg(void, tex8, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", .{
            @as(*anyopaque, @ptrCast(out.ptr)), @as(usize, w) * 4, mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = w, .h = h, .d = 1 }, @as(usize, 0),
        });
    }
    const half: f64 = @floatFromInt(@max(frames / 2, 1));
    return .{ .meter_ms = meter_ms, .trace_ms = trace_ms, .shade_ms = shade_ms / half, .hdr_ms = hdr_ms / half, .paced_hdr_ms = paced[paced.len / 2], .exposure = expo };
}

/// Bardeen (1973) critical curve, as in the theme's test.
fn bardeen(a: f64, incl: f64, r: f64) ?[2]f64 {
    const lam = -(r * r * (r - 3.0) + a * a * (r + 1.0)) / (a * (r - 1.0));
    const eta = r * r * r * (4.0 * a * a - r * (r - 3.0) * (r - 3.0)) / (a * a * (r - 1.0) * (r - 1.0));
    const ci = @cos(incl);
    const si = @sin(incl);
    const b2 = eta + a * a * ci * ci - lam * lam * ci * ci / (si * si);
    if (b2 < 0) return null;
    return .{ -lam / si, @sqrt(b2) };
}

fn probeEngine(st: *theme.State) !bg.Engine {
    var stat: bt.Static = undefined;
    bt.fillStatic(st, &stat);
    var params: bt.TraceParams = undefined;
    bt.fillTrace(st, 64, 64, &params);
    return bg.Engine.init(&stat, params, bt.noiseBytes(st), bt.ttabBytes(st));
}

/// Full-contour sweep: the theme's Bardeen samples, each edge bisected along the ray from the
/// shadow centre on the GPU (f32, the engine's probe kernel) and on the CPU (f64, the theme's
/// traceRay). Prints max and RMS per path, and the GPU's ledger records (the theme's test
/// records the CPU's); true if the GPU's pass.
fn contourSweep(st: *theme.State) !bool {
    var e = try probeEngine(st);
    defer e.deinit();
    const N = theme.CONTOUR_PTS;
    var pts: [N][2]f64 = undefined;
    const c = theme.shadowContour(theme.SPIN, theme.INCL, &pts);
    var u: [N][2]f64 = undefined;
    var d: [N]f64 = undefined;
    var lo: [N]f64 = undefined;
    var hi: [N]f64 = undefined;
    for (pts, &u, &d, &lo, &hi) |p, *ui, *di, *l, *h| {
        di.* = @sqrt((p[0] - c[0]) * (p[0] - c[0]) + (p[1] - c[1]) * (p[1] - c[1]));
        ui.* = .{ (p[0] - c[0]) / di.*, (p[1] - c[1]) / di.* };
        l.* = 0.9 * di.*;
        h.* = 1.1 * di.*;
    }
    var ab: [N][2]f32 = undefined;
    var kinds: [N]u32 = undefined;
    var bad: [N]bool = @splat(false);
    for ([_]bool{ true, false }) |inner| { // brackets: inside at 0.9 d, outside at 1.1 d
        for (&ab, u, lo, hi) |*q, ui, l, h| {
            const t = if (inner) l else h;
            q.* = .{ @floatCast(c[0] + ui[0] * t), @floatCast(c[1] + ui[1] * t) };
        }
        e.probe(&ab, &kinds);
        for (kinds, &bad) |k, *b| if ((k == 2) != inner) {
            b.* = true;
        };
    }
    for (0..theme.CONTOUR_ITERS) |_| {
        for (&ab, u, lo, hi) |*q, ui, l, h| {
            const t = 0.5 * (l + h);
            q.* = .{ @floatCast(c[0] + ui[0] * t), @floatCast(c[1] + ui[1] * t) };
        }
        e.probe(&ab, &kinds);
        for (kinds, &lo, &hi) |k, *l, *h| {
            if (k == 2) l.* = 0.5 * (l.* + h.*) else h.* = 0.5 * (l.* + h.*);
        }
    }
    var off_gpu: [N]f64 = undefined;
    for (&off_gpu, lo, hi, d, bad) |*o, l, h, di, b| o.* = if (b) std.math.nan(f64) else 0.5 * (l + h) - di;
    var off_cpu: [N]f64 = undefined;
    try theme.traceContour(c, &pts, &off_cpu);

    var diff: f64 = 0;
    for (off_gpu, off_cpu) |g, cc| {
        if (!std.math.isNan(g) and !std.math.isNan(cc)) diff = @max(diff, @abs(g - cc));
    }
    var cond_buf: [2][512]u8 = undefined;
    var ok = true;
    for ([_][]const u8{ "gpu", "cpu" }, [_]*const [N]f64{ &off_gpu, &off_cpu }, &cond_buf) |path, off, *cb| {
        const s = theme.contourStats(&pts, off);
        std.debug.print(" shadow contour ({s} {s})      : {d} points, max {e:.2} M (off-axis {e:.2}, polar band {e:.2}), rms {e:.2} M (off-axis {e:.2}), {d} bracket failures\n", .{
            if (path[0] == 'g') "GPU" else "CPU", if (path[0] == 'g') "f32" else "f64", N, s.max, s.max_off_axis, s.max_polar, s.rms, s.rms_off_axis, s.bad,
        });
        if (path[0] == 'c') continue; // the theme's test records the CPU path (same samples)
        const cond = try std.fmt.bufPrint(cb, "a = {d}, i = {d} deg, r_obs = 1000 M; {d} points on the full critical curve (both halves, clustered toward the equatorial ends) + {d} in the polar band |alpha| < {d} M; {s}; {d} bisections along rays from the shadow centre", .{
            theme.SPIN, INCL_DEG, 2 * theme.CONTOUR_N - 2, 2 * theme.POLAR_N, theme.POLAR_BAND, "GPU f32 (bh_gpu probe kernel)", theme.CONTOUR_ITERS,
        });
        const text = "Traced shadow edge lies on the Kerr critical curve over the whole contour";
        const ref = "Bardeen 1973 analytic critical curve";
        var id_buf: [5][64]u8 = undefined;
        const recs = [_]struct { []const u8, []const u8, f64, ?f64 }{
            .{ "max", "max |radial offset| over all points (M); tolerance 1/4 pixel", s.max, 1e-2 },
            .{ "rms", "rms radial offset over the curve sweep (M)", s.rms, 1e-3 },
            .{ "max_off_axis", "max |radial offset| outside the polar band (M)", s.max_off_axis, 1e-4 },
            .{ "rms_off_axis", "rms radial offset over the curve sweep outside the polar band (M)", s.rms_off_axis, 1e-4 },
            .{ "brackets", "bracket failures (count)", @floatFromInt(s.bad), 0.0 },
        };
        for (recs, &id_buf) |r, *ib| {
            ok = ledger.emit(.{ .id = try std.fmt.bufPrint(ib, "{s}shadow.contour.{s}.{s}", .{ ID, path, r[0] }), .claim = text, .reference = ref, .conditions = cond, .quantity = r[1], .measured = r[2], .hi = r[3], .source = LEDGER_SRC }) and ok;
        }
        var polar_id: [64]u8 = undefined;
        _ = ledger.emit(.{ .id = try std.fmt.bufPrint(&polar_id, "{s}shadow.contour.{s}.max_polar", .{ ID, path }), .claim = "Shadow-edge error of rays passing over the spin axis (L ~ 0; reported)", .reference = ref, .conditions = cond, .quantity = "max |radial offset| in the polar band (M)", .measured = s.max_polar, .source = LEDGER_SRC });
    }
    std.debug.print(" shadow contour GPU vs CPU    : max |offset_GPU - offset_CPU| = {e:.2} M per sample\n", .{diff});
    _ = ledger.emit(.{ .id = ID ++ "shadow.contour.gpu_vs_cpu", .claim = "The GPU (f32) and CPU (f64) paths find the same shadow edge (reported)", .reference = "the CPU f64 path on the same samples", .conditions = "the samples of shadow.contour.gpu.* and .cpu.*", .quantity = "max |offset_GPU - offset_CPU| per sample (M)", .measured = diff, .source = LEDGER_SRC });
    return ok;
}

fn shadowEdge(st: *theme.State) !f64 {
    var e = try probeEngine(st);
    defer e.deinit();
    const a = theme.SPIN;
    const r1 = theme.photonOrbit(a, true);
    const r2 = theme.photonOrbit(a, false);
    var pts: [11][2]f64 = undefined;
    var lo: [11]f64 = undefined;
    var hi: [11]f64 = undefined;
    var n: usize = 0;
    for (1..12) |k| {
        const r = r1 + (r2 - r1) * @as(f64, @floatFromInt(k)) / 12.0;
        const ab = bardeen(a, theme.INCL, r) orelse continue;
        if (ab[1] < 0.3) continue;
        pts[n] = ab;
        lo[n] = 0.0;
        hi[n] = ab[1] + 3.0;
        n += 1;
    }
    var ab_buf: [11][2]f32 = undefined;
    var kinds: [11]u32 = undefined;
    for (0..40) |_| {
        for (0..n) |i| ab_buf[i] = .{ @floatCast(pts[i][0]), @floatCast(0.5 * (lo[i] + hi[i])) };
        e.probe(ab_buf[0..n], kinds[0..n]);
        for (0..n) |i| {
            if (kinds[i] == 2) lo[i] = 0.5 * (lo[i] + hi[i]) else hi[i] = 0.5 * (lo[i] + hi[i]);
        }
    }
    var worst: f64 = 0;
    for (0..n) |i| worst = @max(worst, @abs(0.5 * (lo[i] + hi[i]) - pts[i][1]));
    std.debug.print(" shadow edge (GPU f32)       : {d} points, worst |beta - Bardeen| = {e:.2} M\n", .{ n, worst });
    return worst;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = std.heap.page_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var frames: usize = 120;
    var nw: u32 = 3024;
    var nh: u32 = 1964;
    var i: usize = 1;
    while (i + 1 < args.len) : (i += 2) {
        if (std.mem.eql(u8, args[i], "--frames")) frames = try std.fmt.parseInt(usize, args[i + 1], 10);
        if (std.mem.eql(u8, args[i], "--native")) {
            const s = args[i + 1];
            const x = std.mem.indexOfScalar(u8, s, 'x') orelse return error.BadSize;
            nw = try std.fmt.parseInt(u32, s[0..x], 10);
            nh = try std.fmt.parseInt(u32, s[x + 1 ..], 10);
        }
    }

    std.debug.print("========================================================================\n ARGUS GPU // {s} GPU trace vs CPU\n------------------------------------------------------------------------\n", .{ID});
    var t0 = std.Io.Clock.awake.now(io);
    const st = try theme.State.init(alloc, W, H, 1.0);
    defer st.deinit(alloc);
    std.debug.print(" CPU init (trace) 1920x1200  : {d:.0} ms, exposure {d:.4}\n", .{ msSince(io, t0), st.exposure });

    const edge_ok = if (@hasDecl(theme, "shadowContour")) try contourSweep(st) else try shadowEdge(st) <= 0.01;

    // CPU frame at the bench's start state.
    const cpu = try alloc.alloc(u32, W * H);
    defer alloc.free(cpu);
    t0 = std.Io.Clock.awake.now(io);
    st.draw(cpu, W);
    const cpu_draw_ms = msSince(io, t0);

    // GPU at 1920x1200, single frame at the same state (frames = 1: no stepping).
    const gpu = try alloc.alloc(u32, W * H);
    defer alloc.free(gpu);
    const g1 = try gpuFrame(st, W, H, 1, gpu, io);
    var close: u64 = 0;
    var sum_abs: f64 = 0;
    for (cpu, gpu) |a, b| {
        var worst: i32 = 0;
        inline for (0..3) |ch| {
            const d: i32 = @as(i32, @intCast((a >> (8 * ch)) & 0xFF)) - @as(i32, @intCast((b >> (8 * ch)) & 0xFF));
            worst = @max(worst, @as(i32, @intCast(@abs(d))));
            sum_abs += @floatFromInt(@abs(d));
        }
        if (worst <= 8) close += 1;
    }
    saveRgba("/tmp/argus_bh_cpu.rgba", cpu);
    saveRgba("/tmp/argus_bh_gpu.rgba", gpu);
    std.debug.print(" exposure CPU / GPU          : {d:.4} / {d:.4}\n", .{ st.exposure, g1.exposure });
    const frame_cond = "1920x1200, same step() state, CPU draw() vs GPU meter + trace + shade (sRGB)";
    _ = ledger.emit(.{ .id = ID ++ "gpu.pixels_within_8", .claim = "The GPU frame reproduces the CPU reference frame (reported)", .reference = "the theme's CPU draw()", .conditions = frame_cond, .quantity = "% of pixels with every channel within 8 levels", .measured = @as(f64, @floatFromInt(close)) / @as(f64, W * H) * 100.0, .source = LEDGER_SRC });
    _ = ledger.emit(.{ .id = ID ++ "gpu.exposure_ratio", .claim = "The GPU meters the same exposure as the CPU (reported)", .reference = "the theme's CPU exposure meter", .conditions = frame_cond, .quantity = "exposure GPU / CPU", .measured = g1.exposure / st.exposure, .source = LEDGER_SRC });
    std.debug.print(" 1920x1200 GPU meter / trace : {d:.1} ms / {d:.1} ms   (CPU draw {d:.2} ms)\n", .{ g1.meter_ms, g1.trace_ms, cpu_draw_ms });
    std.debug.print(" CPU vs GPU pixels within 8  : {d:.3}%, mean |diff| {d:.3} levels/channel\n", .{
        @as(f64, @floatFromInt(close)) / @as(f64, W * H) * 100.0, sum_abs / @as(f64, W * H * 3),
    });

    // Native size: trace + per-frame shading.
    const nat = try alloc.alloc(u32, @as(usize, nw) * nh);
    defer alloc.free(nat);
    const g2 = try gpuFrame(st, nw, nh, frames, nat, io);
    saveRgba("/tmp/argus_bh_native.rgba", nat);
    std.debug.print(" {d}x{d} GPU meter / trace  : {d:.1} ms / {d:.1} ms (2x2 samples per pixel)\n", .{ nw, nh, g2.meter_ms, g2.trace_ms });
    std.debug.print(" {d}x{d} shade sRGB / HDR10 : {d:.3} / {d:.3} ms GPU per frame ({d} frames)\n", .{ nw, nh, g2.shade_ms, g2.hdr_ms, frames });
    std.debug.print(" {d}x{d} HDR10 paced 30 FPS : {d:.3} ms GPU per frame (the live cost: lower clock between frames)\n", .{ nw, nh, g2.paced_hdr_ms });
    std.debug.print(" traced image memory         : {d:.1} MB kept (+{d:.1} MB while tracing)\n========================================================================\n", .{
        @as(f64, @floatFromInt(@as(usize, nw) * nh * bt.BYTES_PER_PIXEL)) / 1e6,
        @as(f64, @floatFromInt(@as(usize, nw) * nh * bt.TEMP_BYTES_PER_PIXEL)) / 1e6,
    });
    if (!edge_ok) return error.ShadowEdge;
}

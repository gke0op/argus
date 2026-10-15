// ============================================================================
// ARGUS GPU PROTOTYPE // src/gpu_bench.zig
//
// Headless CPU-vs-GPU benchmark for themes/Opus_Black_Hole.zig at 1920x1200:
// each frame steps the theme once on the CPU, then draws it with the theme's own
// `draw()` and with the Metal kernel, timing both and diffing the two frames.
//
//   make gpu-bench [FRAMES=240]
// ============================================================================

const std = @import("std");
const theme = @import("theme");
const mtl = @import("gpu/metal.zig");
const bt = @import("gpu/bh_tables.zig");

const W: usize = 1920;
const H: usize = 1200;
const MSL = @embedFile("gpu/opus_black_hole.metal");

fn usSince(io: std.Io, t0: std.Io.Timestamp) f64 {
    const ns = t0.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    return @as(f64, @floatFromInt(@max(@as(i96, 0), ns))) / 1000.0;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = std.heap.page_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var frames: usize = 240;
    if (args.len > 2 and std.mem.eql(u8, args[1], "--frames")) frames = try std.fmt.parseInt(usize, args[2], 10);

    var t0 = std.Io.Clock.awake.now(io);
    const st = try theme.State.init(alloc, W, H, 1.0);
    defer st.deinit(alloc);
    const init_ms = usSince(io, t0) / 1000.0;

    t0 = std.Io.Clock.awake.now(io);
    const k = try mtl.Kernel.init(MSL, "bh_to_buffer");
    const pipe_ms = usSince(io, t0) / 1000.0;

    // Upload once: per-pixel records, background, row ranges, noise, static tables.
    t0 = std.Io.Clock.awake.now(io);
    const pix = bt.pixelBuffers(st);
    var bufs: [5]mtl.Id = undefined;
    for (pix, 0..) |bytes, i| bufs[i] = k.bufferCopy(bytes);
    const stat_buf = k.bufferNew(@sizeOf(bt.Static));
    bt.fillStatic(st, @ptrCast(@alignCast(mtl.contents(stat_buf))));
    const out_buf = k.bufferNew(W * H * 4);
    const upload_ms = usSince(io, t0) / 1000.0;
    var upload_bytes: usize = @sizeOf(bt.Static);
    for (pix) |b| upload_bytes += b.len;

    const cpu_buf = try alloc.alloc(u32, W * H);
    defer alloc.free(cpu_buf);
    @memset(cpu_buf, 0);
    const gpu_px: [*]const u32 = @ptrCast(@alignCast(mtl.contents(out_buf)));
    const group = k.groupSize();
    var frame: bt.Frame = undefined;

    var cpu_us: f64 = 0;
    var gpu_wall_us: f64 = 0;
    var gpu_exec_us: f64 = 0;
    var gpu_cpu_us: f64 = 0;
    var diff_px: u64 = 0;
    var diff_gt1: u64 = 0;
    var max_diff: u32 = 0;

    for (0..frames + 10) |f| {
        st.step(0.008);
        const timed = f >= 10; // first frames warm caches and the GPU clock

        t0 = std.Io.Clock.awake.now(io);
        st.draw(cpu_buf, W);
        const c_us = usSince(io, t0);

        const pool = mtl.poolPush();
        t0 = std.Io.Clock.awake.now(io);
        bt.fillFrame(st, &frame);
        const cb = mtl.msg(mtl.Id, k.queue, "commandBuffer", .{});
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        mtl.msg(void, enc, "setComputePipelineState:", .{k.pso});
        for (bufs, 0..) |b, i| mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ b, @as(usize, 0), i });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ stat_buf, @as(usize, 0), @as(usize, 5) });
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &frame), @as(usize, @sizeOf(bt.Frame)), @as(usize, 6) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ out_buf, @as(usize, 0), @as(usize, 7) });
        mtl.msg(void, enc, "dispatchThreads:threadsPerThreadgroup:", .{ mtl.MTLSize{ .w = W, .h = H, .d = 1 }, group });
        mtl.msg(void, enc, "endEncoding", .{});
        mtl.msg(void, cb, "commit", .{});
        const enc_us = usSince(io, t0);
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        const g_wall = usSince(io, t0);
        const g_exec = (mtl.msg(f64, cb, "GPUEndTime", .{}) - mtl.msg(f64, cb, "GPUStartTime", .{})) * 1e6;
        mtl.poolPop(pool);

        if (!timed) continue;
        cpu_us += c_us;
        gpu_wall_us += g_wall;
        gpu_exec_us += g_exec;
        gpu_cpu_us += enc_us;
        for (0..W * H) |i| {
            const a = cpu_buf[i];
            const b = gpu_px[i];
            if (a == b) continue;
            diff_px += 1;
            var worst: u32 = 0;
            inline for (0..3) |ch| {
                const ca: i32 = @intCast((a >> (8 * ch)) & 0xFF);
                const cg: i32 = @intCast((b >> (8 * ch)) & 0xFF);
                worst = @max(worst, @abs(ca - cg));
            }
            if (worst > 1) diff_gt1 += 1;
            max_diff = @max(max_diff, worst);
        }
    }

    const n: f64 = @floatFromInt(frames);
    const px_total: f64 = n * @as(f64, @floatFromInt(W * H));
    std.debug.print(
        \\========================================================================
        \\ ARGUS GPU PROTOTYPE // Opus_Black_Hole 1920x1200, {d} frames (M3)
        \\========================================================================
        \\ theme init (CPU ray trace)  : {d:.0} ms
        \\ Metal compile + pipeline    : {d:.1} ms
        \\ one-time upload             : {d:.1} ms ({d:.1} MB)
        \\ CPU draw()                  : {d:.3} ms/frame
        \\ GPU kernel (GPU time)       : {d:.3} ms/frame
        \\ GPU frame, wall (enc+wait)  : {d:.3} ms/frame
        \\ GPU frame, CPU side (encode): {d:.3} ms/frame
        \\ pixels differing CPU vs GPU : {d:.4}% (>1 level: {d:.4}%), max channel diff {d}
        \\========================================================================
        \\
    , .{
        frames,                              init_ms,                            pipe_ms,
        upload_ms,                           @as(f64, @floatFromInt(upload_bytes)) / 1e6,
        cpu_us / n / 1000.0,                 gpu_exec_us / n / 1000.0,
        gpu_wall_us / n / 1000.0,            gpu_cpu_us / n / 1000.0,
        @as(f64, @floatFromInt(diff_px)) / px_total * 100.0,
        @as(f64, @floatFromInt(diff_gt1)) / px_total * 100.0,
        max_diff,
    });
}

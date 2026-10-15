const std = @import("std");
const physics = @import("kronos/physics.zig");
const tui = @import("kronos/tui.zig");
const KronosEngine = physics.KronosEngine;
const FrameRenderer = tui.FrameRenderer;

pub const Mode = enum {
    live_tui,
    snapshot,
    bench,
};

var global_engine: KronosEngine = undefined;
var global_renderer: FrameRenderer = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const stdout = std.Io.File.stdout();

    var mode: Mode = .live_tui;
    var n_frames: usize = 600;
    var fps_sleep_ms: u64 = 16;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--snapshot")) {
            mode = .snapshot;
        } else if (std.mem.eql(u8, arg, "--bench")) {
            mode = .bench;
        } else if (std.mem.eql(u8, arg, "--live")) {
            mode = .live_tui;
        } else if (std.mem.eql(u8, arg, "--frames") and i + 1 < args.len) {
            i += 1;
            n_frames = std.fmt.parseInt(usize, args[i], 10) catch 600;
        } else if (std.mem.eql(u8, arg, "--sleep-ms") and i + 1 < args.len) {
            i += 1;
            fps_sleep_ms = std.fmt.parseInt(u64, args[i], 10) catch 16;
        }
    }

    global_engine = KronosEngine.init(.{});
    global_renderer = FrameRenderer.init();

    switch (mode) {
        .snapshot => {
            const t0 = std.Io.Clock.awake.now(io);
            const warmup_frames: usize = 120;
            for (0..warmup_frames) |_| {
                global_engine.stepFrame(0.012, 4);
            }
            const total_ns: u64 = @intCast(@max(@as(i96, 1), t0.durationTo(std.Io.Clock.awake.now(io)).nanoseconds));
            const avg_frame_ns = total_ns / warmup_frames;

            const frame_slice = global_renderer.renderFrame(&global_engine, avg_frame_ns, false);
            try stdout.writeStreamingAll(io, frame_slice);
        },
        .bench => {
            var eng_simd = KronosEngine.init(.{});
            var eng_scalar = KronosEngine.init(.{});
            eng_simd.depositChargeCIC();
            eng_scalar.depositChargeCIC();

            const n_iters: usize = 1000;
            const dt: f64 = 0.003;

            const t0_simd = std.Io.Clock.awake.now(io);
            for (0..n_iters) |_| eng_simd.stepFieldYoshida4(dt, true);
            const ns_simd: u64 = @intCast(@max(@as(i96, 1), t0_simd.durationTo(std.Io.Clock.awake.now(io)).nanoseconds));

            const t0_scalar = std.Io.Clock.awake.now(io);
            for (0..n_iters) |_| eng_scalar.stepFieldYoshida4(dt, false);
            const ns_scalar: u64 = @intCast(@max(@as(i96, 1), t0_scalar.durationTo(std.Io.Clock.awake.now(io)).nanoseconds));

            var max_diff: f64 = 0.0;
            for (0..physics.GRID_SIZE) |idx| {
                const d = @abs(eng_simd.phi[idx] - eng_scalar.phi[idx]);
                if (d > max_diff) max_diff = d;
            }

            const mcups_simd = (@as(f64, @floatFromInt(physics.GRID_SIZE * n_iters)) * 1000.0) /
                @as(f64, @floatFromInt(ns_simd));
            const mcups_scalar = (@as(f64, @floatFromInt(physics.GRID_SIZE * n_iters)) * 1000.0) /
                @as(f64, @floatFromInt(ns_scalar));

            var buf: [1024]u8 = undefined;
            const report = try std.fmt.bufPrint(
                &buf,
                "KRONOS-17 SIMD vs Scalar Parity Benchmark:\n" ++
                    "  SIMD Throughput   : {d:.1} MCUPS\n" ++
                    "  Scalar Throughput : {d:.1} MCUPS\n" ++
                    "  Max |phi_simd - phi_scalar| : {e:.4}\n",
                .{ mcups_simd, mcups_scalar, max_diff },
            );
            try stdout.writeStreamingAll(io, report);
        },
        .live_tui => {
            try stdout.writeStreamingAll(io, "\x1b[?25l\x1b[2J");
            defer stdout.writeStreamingAll(io, "\x1b[?25h\x1b[0m") catch {};

            for (0..n_frames) |f| {
                const t0 = std.Io.Clock.awake.now(io);
                global_engine.stepFrame(0.012, 4);
                const step_ns: u64 = @intCast(@max(@as(i96, 1), t0.durationTo(std.Io.Clock.awake.now(io)).nanoseconds));

                const frame_slice = global_renderer.renderFrame(&global_engine, step_ns, true);
                try stdout.writeStreamingAll(io, frame_slice);

                if (fps_sleep_ms > 0 and f + 1 < n_frames) {
                    const sleep_ns: i96 = @intCast(fps_sleep_ms * std.time.ns_per_ms);
                    (std.Io.Clock.Duration{ .raw = .{ .nanoseconds = sleep_ns }, .clock = .awake }).sleep(io) catch {};
                }
            }
        },
    }
}

test {
    _ = physics;
    _ = tui;
}

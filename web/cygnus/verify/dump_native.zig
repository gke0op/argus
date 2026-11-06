// ============================================================================
// ARGUS WEB // web/cygnus/verify/dump_native.zig
//
// Writes what the app's Metal presenter uploads for Cygnus A (native build, as
// src/offline_render_bh.zig sets it up: init(1920, 1200), --skip steps of 0.008 * 30 / fps),
// so web/cygnus/verify/compare_tables.mjs can check the wasm build gives the same bytes.
//
//   zig run --dep theme --dep bh_tables -Mroot=web/cygnus/verify/dump_native.zig \
//     -Mtheme=themes/Cygnus_A.zig -Mbh_tables=src/gpu/bh_tables.zig -- OUT_DIR SKIP FPS W H
// ============================================================================

const std = @import("std");
const theme = @import("theme");
const bt = @import("bh_tables");

pub const argus_gpu_traces_kerr_disk = true;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 6) return error.Usage;
    const dir = args[1];
    const skip = try std.fmt.parseInt(usize, args[2], 10);
    const fps = try std.fmt.parseFloat(f64, args[3]);
    const w = try std.fmt.parseInt(u32, args[4], 10);
    const h = try std.fmt.parseInt(u32, args[5], 10);

    const alloc = std.heap.page_allocator;
    const st = try theme.State.init(alloc, 1920, 1200, 1.0);
    defer st.deinit(alloc);
    const zig_dt: f64 = 0.008 * 30.0 / fps;
    for (0..skip) |_| st.step(zig_dt);

    var stat: bt.Static = undefined;
    bt.fillStatic(st, &stat);
    var frame: bt.Frame = undefined;
    bt.fillFrame(st, &frame);
    var params: bt.TraceParams = undefined;
    bt.fillTrace(st, w, h, &params);

    const cwd = std.Io.Dir.cwd();
    const a = init.arena.allocator();
    const files = [_]struct { name: []const u8, data: []const u8 }{
        .{ .name = "static.bin", .data = std.mem.asBytes(&stat) },
        .{ .name = "frame.bin", .data = std.mem.asBytes(&frame) },
        .{ .name = "params.bin", .data = std.mem.asBytes(&params) },
        .{ .name = "noise.bin", .data = bt.noiseBytes(st) },
        .{ .name = "ttab.bin", .data = bt.ttabBytes(st) },
    };
    for (files) |f| {
        const p = try std.fmt.allocPrint(a, "{s}/{s}", .{ dir, f.name });
        try cwd.writeFile(io, .{ .sub_path = p, .data = f.data });
    }
    std.debug.print("t_m {d} static {d} frame {d} params {d}\n", .{ st.t_m, @sizeOf(bt.Static), @sizeOf(bt.Frame), @sizeOf(bt.TraceParams) });
}

// ============================================================================
// ARGUS // src/offline_render_metal.zig  (media renderer; not part of the app)
//
// Renders frames of a Metal theme (themes/*.metal) offline through the app's own
// metal_theme path: prelude + theme compiled at the output size, argus_init/argus_step/
// argus_draw encoded per frame, paced like the app at --fps (f.time advances 1/fps a frame,
// argus_step only on the 30 Hz logic ticks with dt = 1/30 s), drawn into an 8-bit RGBA texture
// (the app draws into a BGRA8 drawable). Frames after --skip warm-up frames go to stdout as raw
// RGBA8. Used for docs/media (launch media) and tools/social.
//
// `@argus stats` themes get argus_stats.synthetic (a new sample every 30 ticks), never this
// Mac's readings. --date pins the wall clock (f.days_j2000 etc.) at the first warm-up frame, as the
// harness does, and --utc-offset sets the local zone in seconds; without --date it is the
// system clock, as in the app. --seed is the f.seed (default 0x5EED, the harness's).
//
//   zig run -O ReleaseFast -target aarch64-macos -lc src/offline_render_metal.zig -- \
//     themes/Night_Tide.metal --size 1920x1080 --fps 60 --skip 660 --frames 120 | ffmpeg ...
// ============================================================================

const std = @import("std");
const mtl = @import("gpu/metal.zig");
const metal_theme = @import("gpu/metal_theme.zig");

fn writeAll(bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = std.c.write(1, bytes[off..].ptr, bytes.len - off);
        if (n <= 0) std.process.exit(2);
        off += @intCast(n);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = std.heap.page_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.Usage;
    const path = args[1];
    var w: u32 = 1920;
    var h: u32 = 1080;
    var frames: usize = 1;
    var skip: usize = 0;
    var fps: u32 = 30;
    var seed: u32 = 0x5EED;
    var date: ?i64 = null;
    var utc_offset: i32 = 0;
    var i: usize = 2;
    while (i + 1 < args.len) : (i += 2) {
        const a = args[i];
        const v = args[i + 1];
        if (std.mem.eql(u8, a, "--size")) {
            const x = std.mem.indexOfScalar(u8, v, 'x') orelse return error.BadSize;
            w = try std.fmt.parseInt(u32, v[0..x], 10);
            h = try std.fmt.parseInt(u32, v[x + 1 ..], 10);
        } else if (std.mem.eql(u8, a, "--frames")) frames = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--skip")) skip = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--fps")) fps = try std.fmt.parseInt(u32, v, 10) else if (std.mem.eql(u8, a, "--seed")) seed = try std.fmt.parseInt(u32, v, 0) else if (std.mem.eql(u8, a, "--date")) date = metal_theme.parseIsoUtc(v) catch return error.DateMustBeYYYYMMDDTHHMMSSZ else if (std.mem.eql(u8, a, "--utc-offset")) utc_offset = try std.fmt.parseInt(i32, v, 10);
    }
    if (fps != 30 and fps != 60 and fps != 120) return error.FpsMustBe30Or60Or120;

    var src_buf: [131072]u8 = undefined;
    const src = try std.Io.Dir.cwd().readFile(io, path, &src_buf);
    const data = try metal_theme.loadData(io, alloc, path, src);
    var err_buf: [4096]u8 = undefined;
    var th = metal_theme.Theme.compile(src, std.Io.Dir.path.basename(path), data, w, h, seed, &err_buf) catch {
        std.debug.print("compile failed: {s}\n", .{std.mem.sliceTo(&err_buf, 0)});
        return error.MetalCompile;
    };
    defer th.deinit();
    if (date) |d| th.wall = .{ .fixed = .{ .unix_s = d, .utc_offset_s = utc_offset } };
    const out = mtl.newTexture(th.dev, mtl.PIXEL_RGBA8, w, h, mtl.STORAGE_SHARED);
    defer mtl.release(out);
    const px = try alloc.alloc(u32, @as(usize, w) * h);
    const units: u64 = 120 / fps; // frame_rate: time in 1/120 s units, a logic tick every 4
    var clock: u64 = 0;
    for (0..skip + frames) |f| {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const cb = mtl.msg(mtl.Id, th.queue, "commandBuffer", .{});
        // frame_rate.Pacer: the first frame is a whole logic tick at any rate, then a tick every
        // 4 units. f.frame is the tick index (metal_theme.FrameCounter, inside encodeTimes).
        const before = clock / 4;
        clock += if (f == 0) 4 else units;
        const logic = clock / 4 > before;
        th.encodeTimes(cb, out, 1.0 / @as(f32, @floatFromInt(fps)), if (logic) 1.0 / 30.0 else null);
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        if (mtl.msg(usize, cb, "status", .{}) == 5) return error.MetalRun;
        if (f < skip) continue;
        mtl.msg(void, out, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", .{
            @as(*anyopaque, @ptrCast(px.ptr)), @as(usize, w) * 4, mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = w, .h = h, .d = 1 }, @as(usize, 0),
        });
        writeAll(std.mem.sliceAsBytes(px));
    }
    std.debug.print("{s}: {d} frames after {d} warm-up\n", .{ path, frames, skip });
}

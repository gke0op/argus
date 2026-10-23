// ============================================================================
// ARGUS // src/offline_render_bh.zig  (media renderer; not part of the app)
//
// Renders frames of a Kerr-disk theme offline through the live GPU path: the theme's own
// tables and step() state (bh_tables), the app's engine (bh_gpu: meter -> trace ->
// footprint -> shade) and kernels (opus_black_hole.metal), sRGB 8-bit output (the
// menu-preview / SDR encoding). The only thing changed is the camera inclination, which the
// trace takes as a runtime parameter (TraceParams.incl/sin_i/cos_i): the shot sweeps it from
// --i0 to --i1 degrees over --sweep frames (smoothstep), after --pre frames held at inc0, then
// holds at inc1 (the theme's own INCL when --i1 is left out). Each frame is a fresh trace at that
// inclination; exposure is the engine's own meter per frame, smoothed over time (log space,
// gaussian sigma --sigma frames) so the 1/8-stop histogram bins don't flicker.
// Time advances like the app's frame pacer (src/desktop/frame_rate.zig): step(ZIG_TICK_DT = 0.008)
// per 30 Hz logic tick, spread evenly over the frames of --fps (0.002 per frame at 120 FPS).
// A held inclination is traced once and shaded every frame, as the app does.
// Raw RGBA8 frames go to stdout (pipe into ffmpeg -f rawvideo). Used for docs/media (launch
// media) and tools/social. Leave out --i0/--i1 for the live wallpaper's camera, held at INCL.
//
//   zig run -O ReleaseFast -target aarch64-macos -lc --dep theme -Mroot=src/offline_render_bh.zig \
//     -O ReleaseFast -Mtheme=themes/Cygnus_A.zig -- --size 1920x1080 --frames 300 \
//     --i0 40 --pre 15 --sweep 240 | ffmpeg -f rawvideo -pix_fmt rgba -s 1920x1080 -r 30 -i - ...
// ============================================================================

const std = @import("std");
const theme = @import("theme");
const mtl = @import("gpu/metal.zig");
const bt = @import("gpu/bh_tables.zig");
const bg = @import("gpu/bh_gpu.zig");

pub const argus_gpu_traces_kerr_disk = true; // the theme's init() skips its CPU trace, as in the app

fn writeAll(bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = std.c.write(1, bytes[off..].ptr, bytes.len - off);
        if (n <= 0) std.process.exit(2);
        off += @intCast(n);
    }
}

fn smoothstep(x: f64) f64 {
    const t = std.math.clamp(x, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

pub fn main(init: std.process.Init) !void {
    const alloc = std.heap.page_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var w: u32 = 1920;
    var h: u32 = 1080;
    var frames: usize = 1;
    var inc0: f64 = theme.INCL * 180.0 / std.math.pi;
    var inc1: f64 = inc0;
    var pre: usize = 0;
    var sweep: usize = 1;
    var sigma: f64 = 6.0;
    var skip: usize = 0; // frames of animation time to advance before the first output frame
    var fps: f64 = 30.0;
    var i: usize = 1;
    while (i + 1 < args.len) : (i += 2) {
        const a = args[i];
        const v = args[i + 1];
        if (std.mem.eql(u8, a, "--size")) {
            const x = std.mem.indexOfScalar(u8, v, 'x') orelse return error.BadSize;
            w = try std.fmt.parseInt(u32, v[0..x], 10);
            h = try std.fmt.parseInt(u32, v[x + 1 ..], 10);
        } else if (std.mem.eql(u8, a, "--frames")) frames = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--i0")) inc0 = try std.fmt.parseFloat(f64, v) else if (std.mem.eql(u8, a, "--i1")) inc1 = try std.fmt.parseFloat(f64, v) else if (std.mem.eql(u8, a, "--pre")) pre = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--sweep")) sweep = @max(1, try std.fmt.parseInt(usize, v, 10)) else if (std.mem.eql(u8, a, "--sigma")) sigma = try std.fmt.parseFloat(f64, v) else if (std.mem.eql(u8, a, "--skip")) skip = try std.fmt.parseInt(usize, v, 10) else if (std.mem.eql(u8, a, "--fps")) fps = try std.fmt.parseFloat(f64, v);
    }

    const st = try theme.State.init(alloc, 1920, 1200, 1.0);
    defer st.deinit(alloc);
    const zig_dt: f64 = 0.008 * 30.0 / fps; // frame_rate.zigStepDt for one frame at this rate
    for (0..skip) |_| st.step(zig_dt);
    var stat: bt.Static = undefined;
    bt.fillStatic(st, &stat);

    const incl = try alloc.alloc(f64, frames);
    for (incl, 0..) |*d, f| {
        const u = if (f < pre) 0.0 else @as(f64, @floatFromInt(f - pre)) / @as(f64, @floatFromInt(@max(sweep, 2) - 1));
        d.* = (inc0 + (inc1 - inc0) * smoothstep(u)) * std.math.pi / 180.0;
    }
    const paramsAt = struct {
        fn f(s: *theme.State, ww: u32, hh: u32, rad: f64) bt.TraceParams {
            var p: bt.TraceParams = undefined;
            bt.fillTrace(s, ww, hh, &p);
            p.incl = @floatCast(rad);
            p.sin_i = @floatCast(@sin(rad));
            p.cos_i = @floatCast(@cos(rad));
            return p;
        }
    }.f;

    // Pass 1: the engine's exposure meter at every frame's inclination, then smoothed. A held
    // inclination meters the same on every frame, so it is metered once.
    const lnx = try alloc.alloc(f64, frames);
    for (incl, lnx, 0..) |rad, *x, f| {
        if (f > 0 and rad == incl[f - 1]) {
            x.* = lnx[f - 1];
            continue;
        }
        var e = try bg.Engine.init(&stat, paramsAt(st, w, h, rad), bt.noiseBytes(st), bt.ttabBytes(st));
        defer e.deinit();
        x.* = @log(@as(f64, e.meter()));
    }
    const expo = try alloc.alloc(f32, frames);
    for (expo, 0..) |*o, f| {
        if (sigma <= 0) {
            o.* = @floatCast(@exp(lnx[f]));
            continue;
        }
        var acc: f64 = 0;
        var wsum: f64 = 0;
        const r: isize = @intFromFloat(@ceil(3 * sigma));
        var k: isize = -r;
        while (k <= r) : (k += 1) {
            const j: usize = @intCast(std.math.clamp(@as(isize, @intCast(f)) + k, 0, @as(isize, @intCast(frames - 1))));
            const wt = @exp(-0.5 * @as(f64, @floatFromInt(k * k)) / (sigma * sigma));
            acc += wt * lnx[j];
            wsum += wt;
        }
        o.* = @floatCast(@exp(acc / wsum));
    }

    // Pass 2: trace + shade each frame.
    const dev = try mtl.device();
    const queue = mtl.msg(mtl.Id, dev, "newCommandQueue", .{});
    defer mtl.release(queue);
    const tex8 = mtl.newTexture(dev, mtl.PIXEL_RGBA8, w, h, mtl.STORAGE_SHARED);
    defer mtl.release(tex8);
    const px = try alloc.alloc(u32, @as(usize, w) * h);
    var frame: bt.Frame = undefined;
    var eng: ?bg.Engine = null;
    defer if (eng) |*e| e.deinit();
    for (0..frames) |f| {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        if (eng == null or incl[f] != incl[f - 1]) {
            if (eng) |*old| old.deinit();
            eng = try bg.Engine.init(&stat, paramsAt(st, w, h, incl[f]), bt.noiseBytes(st), bt.ttabBytes(st));
            eng.?.startTrace(16);
            eng.?.waitTrace();
            if (eng.?.failed) return error.GpuTraceFailed;
        }
        const e = &eng.?;
        e.params.exposure = expo[f];
        if (f > 0) st.step(zig_dt);
        bt.fillFrame(st, &frame);
        const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
        e.encodeShade(cb, &frame, tex8, w, h, 1.0, .srgb);
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        mtl.msg(void, tex8, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", .{
            @as(*anyopaque, @ptrCast(px.ptr)), @as(usize, w) * 4, mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = w, .h = h, .d = 1 }, @as(usize, 0),
        });
        writeAll(std.mem.sliceAsBytes(px));
        std.debug.print("frame {d}/{d} incl {d:.2} deg exposure {d:.4} (raw {d:.4})\n", .{ f + 1, frames, incl[f] * 180.0 / std.math.pi, expo[f], @exp(lnx[f]) });
    }
}

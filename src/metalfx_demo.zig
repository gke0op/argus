// ============================================================================
// ARGUS GPU // src/metalfx_demo.zig
//
// Demo: does MetalFX upscaling pay off for Argus's Metal themes?
// Renders a theme natively at 1920x1200 and, at each --scale, renders it smaller
// and upscales it to 1920x1200 with MetalFX's spatial scaler (MTLFXSpatialScaler).
// Same seed and frame count everywhere, so every run shows the same moment.
// Prints the median GPU time per frame and writes one PNG per run.
//
//   make metalfx-demo THEME=themes/Night_Tide.metal
// ============================================================================

const std = @import("std");
const mtl = @import("gpu/metal.zig");
const metal_theme = @import("gpu/metal_theme.zig");
const harness = @import("theme_harness.zig");

const W: usize = 1920;
const H: usize = 1200;
const DT: f32 = 1.0 / 30.0;
const USAGE_READ: usize = 1;
const USAGE_WRITE: usize = 2;
const USAGE_RT: usize = 4;

fn texture(dev: mtl.Id, w: usize, h: usize, usage: usize) mtl.Id {
    const desc = mtl.msg(mtl.Id, mtl.cls("MTLTextureDescriptor"), "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", .{ mtl.PIXEL_BGRA8, w, h, false });
    mtl.msg(void, desc, "setUsage:", .{usage});
    mtl.msg(void, desc, "setStorageMode:", .{mtl.STORAGE_PRIVATE});
    return mtl.msg(mtl.Id, dev, "newTextureWithDescriptor:", .{desc});
}

fn gpuUs(cb: mtl.Id) f64 {
    return (mtl.msg(f64, cb, "GPUEndTime", .{}) - mtl.msg(f64, cb, "GPUStartTime", .{})) * 1e6;
}

const Result = struct { median_us: f64, draw_us: f64, scaler_us: f64 };

/// Renders `frames` frames at scale `s` (1 = native, no scaler) and saves the last as `png`.
fn run(io: std.Io, src: []const u8, label: []const u8, s: f64, frames: usize, png: []const u8) !Result {
    const lw: usize = @intFromFloat(@round(@as(f64, W) * s));
    const lh: usize = @intFromFloat(@round(@as(f64, H) * s));
    var err_buf: [4096]u8 = undefined;
    var theme = metal_theme.Theme.compile(src, label, null, @intCast(lw), @intCast(lh), 0x5EED, &err_buf) catch {
        std.debug.print("compile failed: {s}\n", .{std.mem.sliceTo(&err_buf, 0)});
        return error.Compile;
    };
    defer theme.deinit();
    const dev = theme.dev;
    const native = lw == W;

    var scaler: mtl.Id = null;
    var low: mtl.Id = null;
    var out: mtl.Id = null;
    if (native) {
        out = texture(dev, W, H, USAGE_READ | USAGE_WRITE);
    } else {
        const d = mtl.msg(mtl.Id, mtl.msg(mtl.Id, mtl.cls("MTLFXSpatialScalerDescriptor"), "alloc", .{}), "init", .{});
        mtl.msg(void, d, "setInputWidth:", .{lw});
        mtl.msg(void, d, "setInputHeight:", .{lh});
        mtl.msg(void, d, "setOutputWidth:", .{W});
        mtl.msg(void, d, "setOutputHeight:", .{H});
        mtl.msg(void, d, "setColorTextureFormat:", .{mtl.PIXEL_BGRA8});
        mtl.msg(void, d, "setOutputTextureFormat:", .{mtl.PIXEL_BGRA8});
        mtl.msg(void, d, "setColorProcessingMode:", .{@as(usize, 0)}); // perceptual: display-encoded input, like ours
        scaler = mtl.msg(mtl.Id, d, "newSpatialScalerWithDevice:", .{dev}) orelse return error.NoScaler;
        mtl.release(d);
        low = texture(dev, lw, lh, USAGE_READ | USAGE_WRITE | mtl.msg(usize, scaler, "colorTextureUsage", .{}));
        out = texture(dev, W, H, USAGE_READ | mtl.msg(usize, scaler, "outputTextureUsage", .{}));
        mtl.msg(void, scaler, "setColorTexture:", .{low});
        mtl.msg(void, scaler, "setOutputTexture:", .{out});
        mtl.msg(void, scaler, "setInputContentWidth:", .{lw});
        mtl.msg(void, scaler, "setInputContentHeight:", .{lh});
    }
    defer {
        mtl.release(out);
        mtl.release(low);
        mtl.release(scaler);
    }

    var times: [4096]f64 = undefined;
    var theme_only: [4096]f64 = undefined;
    const n = @min(frames, times.len);
    for (0..n) |f| {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const cb = mtl.msg(mtl.Id, theme.queue, "commandBuffer", .{});
        theme.encode(cb, if (native) out else low, DT);
        if (!native) mtl.msg(void, scaler, "encodeToCommandBuffer:", .{cb});
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        times[f] = gpuUs(cb);
        // argus_draw alone on the same state (no step, no scaler), to split the frame.
        const cb2 = mtl.msg(mtl.Id, theme.queue, "commandBuffer", .{});
        theme.encodeDrawOnly(cb2, if (native) out else low);
        mtl.msg(void, cb2, "commit", .{});
        mtl.msg(void, cb2, "waitUntilCompleted", .{});
        theme_only[f] = gpuUs(cb2);
    }
    // Median over the second half (after any one-time bake/warm-up).
    const tail = times[n / 2 .. n];
    std.mem.sort(f64, tail, {}, std.sort.asc(f64));

    // Read back: private -> shared copy, BGRA -> RGBA, PNG.
    const shared = blk: {
        const desc = mtl.msg(mtl.Id, mtl.cls("MTLTextureDescriptor"), "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", .{ mtl.PIXEL_BGRA8, W, H, false });
        mtl.msg(void, desc, "setStorageMode:", .{mtl.STORAGE_SHARED});
        break :blk mtl.msg(mtl.Id, dev, "newTextureWithDescriptor:", .{desc});
    };
    defer mtl.release(shared);
    {
        const cb = mtl.msg(mtl.Id, theme.queue, "commandBuffer", .{});
        const blit = mtl.msg(mtl.Id, cb, "blitCommandEncoder", .{});
        mtl.msg(void, blit, "copyFromTexture:toTexture:", .{ out, shared });
        mtl.msg(void, blit, "endEncoding", .{});
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
    }
    const px = try std.heap.page_allocator.alloc(u32, W * H);
    defer std.heap.page_allocator.free(px);
    mtl.msg(void, shared, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", .{
        @as(*anyopaque, @ptrCast(px.ptr)), W * 4, mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = W, .h = H, .d = 1 }, @as(usize, 0),
    });
    for (px) |*p| p.* = (p.* & 0xFF00FF00) | ((p.* >> 16) & 0xFF) | ((p.* & 0xFF) << 16);
    try harness.writePNG(px, W, H, png);
    _ = io;

    const half2 = theme_only[n / 2 .. n];
    std.mem.sort(f64, half2, {}, std.sort.asc(f64));
    // The scaler alone, on the last low-res frame.
    var sc: [64]f64 = undefined;
    for (&sc) |*v| {
        if (native) {
            v.* = 0;
            continue;
        }
        const cb = mtl.msg(mtl.Id, theme.queue, "commandBuffer", .{});
        mtl.msg(void, scaler, "encodeToCommandBuffer:", .{cb});
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        v.* = gpuUs(cb);
    }
    std.mem.sort(f64, &sc, {}, std.sort.asc(f64));
    return .{ .median_us = tail[tail.len / 2], .draw_us = half2[half2.len / 2], .scaler_us = sc[32] };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var path: []const u8 = "themes/Night_Tide.metal";
    var frames: usize = 300;
    var out_dir: []const u8 = "/tmp";
    var scales_arg: []const u8 = "1,0.75,0.667,0.5";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--frames") and i + 1 < args.len) {
            i += 1;
            frames = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, a, "--out-dir") and i + 1 < args.len) {
            i += 1;
            out_dir = args[i];
        } else if (std.mem.eql(u8, a, "--scales") and i + 1 < args.len) {
            i += 1;
            scales_arg = args[i];
        } else if (!std.mem.startsWith(u8, a, "-")) path = a;
    }
    try mtl.load();
    _ = std.c.dlopen("/System/Library/Frameworks/MetalFX.framework/MetalFX", .{ .LAZY = true }) orelse return error.MetalFXMissing;

    var src_buf: [262144]u8 = undefined;
    const src = try std.Io.Dir.cwd().readFile(io, path, &src_buf);
    const label = std.Io.Dir.path.basename(path);
    const stem = label[0 .. std.mem.lastIndexOfScalar(u8, label, '.') orelse label.len];

    std.debug.print("MetalFX demo: {s}, {d} frames, output {d}x{d} BGRA8 (median GPU ms per frame, 2nd half)\n", .{ label, frames, W, H });
    var it = std.mem.splitScalar(u8, scales_arg, ',');
    while (it.next()) |sa| {
        const s = try std.fmt.parseFloat(f64, sa);
        var pbuf: [512]u8 = undefined;
        const png = try std.fmt.bufPrintSentinel(&pbuf, "{s}/{s}_x{d:.3}.png", .{ out_dir, stem, s }, 0);
        const r = try run(io, src, label, s, frames, png);
        std.debug.print("  scale {d:.3} ({d}x{d}): frame {d:.2} ms = draw {d:.2} + MetalFX {d:.2} + step/other {d:.2}  -> {s}\n", .{
            s, @as(usize, @intFromFloat(@round(@as(f64, W) * s))), @as(usize, @intFromFloat(@round(@as(f64, H) * s))),
            r.median_us / 1000.0, r.draw_us / 1000.0, r.scaler_us / 1000.0, @max(0.0, r.median_us - r.draw_us - r.scaler_us) / 1000.0, png,
        });
    }
}

// ============================================================================
// ARGUS GPU // src/gpu/presenter.zig
//
// Presents GPU themes through a CAMetalLayer on their Space's window, shading straight
// into the drawable (no CGImage, no CPU pixel buffer):
//  - ThemePresenter: Metal-only themes (themes/*.metal, see metal_theme.zig).
//  - Presenter: Zig + Metal hybrids. The Zig theme steps on the CPU; the GPU traces the
//    image itself at the window's native pixel size and shades it every frame from the
//    theme's tables, into an extended-range (HDR) layer. Today: Opus_Quasar via
//    src/gpu/bh_export.zig and src/gpu/bh_gpu.zig.
// ============================================================================

const std = @import("std");
const mtl = @import("metal.zig");
const bt = @import("bh_tables.zig");
const metal_theme = @import("metal_theme.zig");
const bh_gpu = @import("bh_gpu.zig");

pub const CGRect = extern struct { x: f64, y: f64, w: f64, h: f64 };

/// HDR output for hybrid themes on displays with EDR headroom. `--sdr` turns it off.
pub var hdr_enabled = true;

/// A CAMetalLayer covering `host_layer` with a w x h drawable the kernels write directly:
/// BGRA8 in `color_space`, or with `hdr` HDR10 (10-bit PQ, BT.2020) as EDR content, at
/// 4 bytes per pixel like SDR. `drawables` caps the swap chain (2 or 3).
fn makeLayer(dev: mtl.Id, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize, hdr: bool, drawables: usize) mtl.Id {
    const ml = mtl.msg(mtl.Id, mtl.cls("CAMetalLayer"), "layer", .{}) orelse return null;
    _ = mtl.msg(mtl.Id, ml, "retain", .{});
    mtl.msg(void, ml, "setDevice:", .{dev});
    mtl.msg(void, ml, "setPixelFormat:", .{if (hdr) mtl.PIXEL_BGR10A2 else mtl.PIXEL_BGRA8});
    mtl.msg(void, ml, "setFramebufferOnly:", .{false});
    mtl.msg(void, ml, "setMaximumDrawableCount:", .{drawables});
    mtl.msg(void, ml, "setDrawableSize:", .{mtl.CGSize{ .width = @floatFromInt(w), .height = @floatFromInt(h) }});
    if (hdr) {
        mtl.msg(void, ml, "setWantsExtendedDynamicRangeContent:", .{true});
        if (colorSpaceNamed("kCGColorSpaceITUR_2100_PQ")) |cs| mtl.msg(void, ml, "setColorspace:", .{cs});
        // PQ is absolute luminance: tell the compositor that 100 nits is display white (EDR 1.0).
        const md = mtl.msg(mtl.Id, mtl.cls("CAEDRMetadata"), "HDR10MetadataWithMinLuminance:maxLuminance:opticalOutputScale:", .{ @as(f32, 0.005), @as(f32, 1600.0), @as(f32, 100.0) });
        if (md != null) mtl.msg(void, ml, "setEDRMetadata:", .{md});
    } else if (color_space != null) mtl.msg(void, ml, "setColorspace:", .{color_space});
    mtl.msg(void, ml, "setOpaque:", .{true});
    mtl.msg(void, ml, "setFrame:", .{mtl.msg(CGRect, host_layer, "bounds", .{})});
    mtl.msg(void, ml, "setAutoresizingMask:", .{@as(u32, 2 | 16)}); // width | height sizable
    mtl.msg(void, host_layer, "addSublayer:", .{ml});
    return ml;
}

/// Copies a w x h RGBA8 frame out of the GPU into `dst` (packRGBA layout), for menu previews.
/// `encode` writes the frame into the texture it's given. Blocks until the GPU is done (~1-2 ms).
fn snapshotInto(dev: mtl.Id, queue: mtl.Id, tex: *mtl.Id, w: usize, h: usize, dst: []u32, ctx: anytype, comptime encode: fn (@TypeOf(ctx), mtl.Id, mtl.Id) void) bool {
    if (dst.len < w * h) return false;
    if (tex.* == null) tex.* = mtl.newTexture(dev, mtl.PIXEL_RGBA8, w, h, mtl.STORAGE_SHARED);
    if (tex.* == null) return false;
    const pool = mtl.poolPush();
    defer mtl.poolPop(pool);
    const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
    encode(ctx, cb, tex.*);
    mtl.msg(void, cb, "commit", .{});
    mtl.msg(void, cb, "waitUntilCompleted", .{});
    mtl.msg(void, tex.*, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", .{
        @as(*anyopaque, @ptrCast(dst.ptr)), w * 4, mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = w, .h = h, .d = 1 }, @as(usize, 0),
    });
    return true;
}

fn detachLayer(layer: mtl.Id) void {
    if (layer == null) return;
    mtl.msg(void, layer, "removeFromSuperlayer", .{});
    mtl.release(layer);
}

/// A Metal-only theme on a Space window.
pub const ThemePresenter = struct {
    theme: metal_theme.Theme,
    layer: mtl.Id,
    gen: u32, // SpaceConfig.dylib_gen of the load this was built for
    snap_tex: mtl.Id = null,

    pub fn create(src: []const u8, label: []const u8, gen: u32, seed: u32, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize) ?ThemePresenter {
        var err_buf: [2048]u8 = undefined;
        var theme = metal_theme.Theme.compile(src, label, @intCast(w), @intCast(h), seed, &err_buf) catch {
            std.debug.print("argus: {s}: {s}\n", .{ label, std.mem.sliceTo(&err_buf, 0) });
            return null;
        };
        const layer = makeLayer(theme.dev, host_layer, color_space, w, h, false, 3) orelse {
            theme.deinit();
            return null;
        };
        return .{ .theme = theme, .layer = layer, .gen = gen };
    }

    pub fn render(self: *ThemePresenter, dt: f32) bool {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const drawable = mtl.msg(mtl.Id, self.layer, "nextDrawable", .{}) orelse return false;
        const cb = mtl.msg(mtl.Id, self.theme.queue, "commandBuffer", .{});
        self.theme.encode(cb, mtl.msg(mtl.Id, drawable, "texture", .{}), dt);
        mtl.msg(void, cb, "presentDrawable:", .{drawable});
        mtl.msg(void, cb, "commit", .{});
        return true;
    }

    /// Draws the current state once more into `dst` (packRGBA, w x h) for the menu preview.
    pub fn snapshot(self: *ThemePresenter, dst: []u32) bool {
        const encode = struct {
            fn f(t: *metal_theme.Theme, cb: mtl.Id, out: mtl.Id) void {
                t.encodeDrawOnly(cb, out);
            }
        }.f;
        return snapshotInto(self.theme.dev, self.theme.queue, &self.snap_tex, self.theme.frame.width, self.theme.frame.height, dst, &self.theme, encode);
    }

    pub fn destroy(self: *ThemePresenter) void {
        mtl.release(self.snap_tex);
        detachLayer(self.layer);
        self.theme.deinit();
        self.* = undefined;
    }
};
/// A named CoreGraphics colour space (e.g. kCGColorSpaceITUR_2100_PQ), created once.
var pq_space: ?*anyopaque = null;
fn colorSpaceNamed(comptime name: [*:0]const u8) ?*anyopaque {
    if (pq_space) |cs| return cs;
    const cg = std.c.dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", .{ .LAZY = true }) orelse return null;
    const sym: *const ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(cg, name) orelse return null));
    const create: *const fn (?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(cg, "CGColorSpaceCreateWithName") orelse return null));
    pq_space = create(sym.*);
    return pq_space;
}

/// The main screen's current EDR headroom (1 = SDR; rises with brightness on XDR panels).
fn edrHeadroom() f32 {
    const screen = mtl.msg(mtl.Id, mtl.cls("NSScreen"), "mainScreen", .{}) orelse return 1.0;
    const v = mtl.msg(f64, screen, "maximumExtendedDynamicRangeColorComponentValue", .{});
    return @floatCast(std.math.clamp(v, 1.0, 16.0));
}

/// The host layer's size in screen pixels (points x the main screen's backing scale).
fn nativeSize(host_layer: mtl.Id, fallback_w: usize, fallback_h: usize) [2]u32 {
    const b = mtl.msg(CGRect, host_layer, "bounds", .{});
    const screen = mtl.msg(mtl.Id, mtl.cls("NSScreen"), "mainScreen", .{});
    const scale: f64 = if (screen != null) mtl.msg(f64, screen, "backingScaleFactor", .{}) else 1.0;
    const w = @round(b.w * scale);
    const h = @round(b.h * scale);
    if (!(w >= 64 and h >= 64 and w <= 8192 and h <= 8192)) return .{ @intCast(fallback_w), @intCast(fallback_h) };
    return .{ @intFromFloat(w), @intFromFloat(h) };
}

const StaticFn = *const fn (*anyopaque, *bt.Static) callconv(.c) void;
const FrameFn = *const fn (*anyopaque, *bt.Frame) callconv(.c) void;
const TraceFn = *const fn (*anyopaque, u32, u32, *bt.TraceParams) callconv(.c) void;
const TablesFn = *const fn (*anyopaque, *[2]usize, *[2]usize) callconv(.c) void;

pub const Presenter = struct {
    handle: ?*anyopaque, // the theme dylib this presenter was built for
    state: *anyopaque,
    layer: mtl.Id, // CAMetalLayer, a sublayer of the Space window's host layer
    queue: mtl.Id,
    engine: bh_gpu.Engine,
    fill_frame: FrameFn,
    frame: bt.Frame = undefined,
    hdr: bool,
    preview_w: usize, // the app's menu-preview size (the CPU canvas size)
    preview_h: usize,

    /// Returns null when the dylib isn't a GPU build or Metal is unavailable.
    /// `w` x `h` is the app's canvas size, used for menu previews; the GPU traces at the
    /// window's native pixel size.
    pub fn create(handle: ?*anyopaque, state_ptr: ?*anyopaque, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize) ?Presenter {
        const h_lib = handle orelse return null;
        const st = state_ptr orelse return null;
        const fill_frame: FrameFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_frame") orelse return null));
        const fill_static: StaticFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_static") orelse return null));
        const fill_trace: TraceFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_trace_params") orelse return null));
        const tables: TablesFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_tables") orelse return null));
        mtl.load() catch return null; // nativeSize messages AppKit before the engine loads Metal

        const size = nativeSize(host_layer, w, h);
        var stat: bt.Static = undefined;
        fill_static(st, &stat);
        var params: bt.TraceParams = undefined;
        fill_trace(st, size[0], size[1], &params);
        var ptrs: [2]usize = undefined;
        var lens: [2]usize = undefined;
        tables(st, &ptrs, &lens);
        const noise = @as([*]const u8, @ptrFromInt(ptrs[0]))[0..lens[0]];
        const ttab = @as([*]const u8, @ptrFromInt(ptrs[1]))[0..lens[1]];

        var engine = bh_gpu.Engine.init(&stat, params, noise, ttab) catch return null;
        _ = engine.meter();
        engine.startTrace(16); // ~0.8 s of GPU work at 3024x1964, in ~120 short submissions
        const hdr = hdr_enabled;
        // Two drawables: the image changes slowly and Argus draws at <= 30 FPS, so a third
        // window-sized buffer would only cost memory.
        const layer = makeLayer(engine.k.dev, host_layer, color_space, size[0], size[1], hdr, 2) orelse {
            engine.deinit();
            return null;
        };
        return .{
            .handle = handle,
            .state = st,
            .layer = layer,
            .queue = mtl.msg(mtl.Id, engine.k.dev, "newCommandQueue", .{}),
            .engine = engine,
            .fill_frame = fill_frame,
            .hdr = hdr,
            .preview_w = w,
            .preview_h = h,
        };
    }

    /// Shades one frame from the theme's current step state and presents it. Rows the trace
    /// hasn't reached yet draw black. Never fails once created: with no free drawable the
    /// frame is skipped (the caller must not fall back to the theme's CPU draw).
    pub fn render(self: *Presenter) bool {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        _ = self.engine.poll();
        self.fill_frame(self.state, &self.frame);
        const drawable = mtl.msg(mtl.Id, self.layer, "nextDrawable", .{}) orelse return true;
        const cb = mtl.msg(mtl.Id, self.queue, "commandBuffer", .{});
        const p = self.engine.params;
        self.engine.encodeShade(cb, &self.frame, mtl.msg(mtl.Id, drawable, "texture", .{}), p.width, p.height, if (self.hdr) edrHeadroom() else 1.0, if (self.hdr) .pq else .srgb);
        mtl.msg(void, cb, "presentDrawable:", .{drawable});
        mtl.msg(void, cb, "commit", .{});
        return true;
    }

    /// The current frame, again, into `dst` (packRGBA at the app's canvas size, SDR) for the
    /// menu preview. The 9 MB texture lives only for the call: previews are occasional.
    pub fn snapshot(self: *Presenter, dst: []u32) bool {
        // The preview waits for the GPU; while the trace is running that means waiting behind
        // it on the main thread. The app retries a failed preview, so take it once the trace is done.
        if (!self.engine.poll()) return false;
        const encode = struct {
            fn f(pr: *Presenter, cb: mtl.Id, out: mtl.Id) void {
                pr.engine.encodeShade(cb, &pr.frame, out, pr.preview_w, pr.preview_h, 1.0, .srgb);
            }
        }.f;
        var tex: mtl.Id = null;
        defer mtl.release(tex);
        return snapshotInto(self.engine.k.dev, self.queue, &tex, self.preview_w, self.preview_h, dst, self, encode);
    }

    /// Detaches the layer and releases GPU objects. Call before the theme's state is freed.
    pub fn destroy(self: *Presenter) void {
        detachLayer(self.layer);
        mtl.release(self.queue);
        self.engine.deinit();
        self.* = undefined;
    }
};

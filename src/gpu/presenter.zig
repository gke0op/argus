// ============================================================================
// ARGUS GPU // src/gpu/presenter.zig
//
// Presents GPU themes through a CAMetalLayer on their Space's window, shading straight
// into the drawable (no CGImage, no CPU pixel buffer):
//  - ThemePresenter: Metal-only themes (themes/*.metal, see metal_theme.zig).
//  - Presenter: Zig + Metal hybrids. The Zig theme steps on the CPU; the GPU traces the
//    image itself at the window's native pixel size and shades it every frame from the
//    theme's tables, into an extended-range (HDR) layer. Today: the Kerr-disk quasars (Cygnus A) via
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

/// `--perf-log`: print layer and engine events (create, park, rehost, retire) to stderr.
pub var log_events = false;
const CB_COMPLETED: usize = 4; // MTLCommandBufferStatusCompleted
fn ev(comptime fmt: []const u8, args: anytype) void {
    if (log_events) std.debug.print("[gpu] " ++ fmt ++ "\n", args);
}

/// A CAMetalLayer covering `host_layer` with a w x h drawable the kernels write directly:
/// BGRA8 in `color_space`, or with `hdr` HDR10 (10-bit PQ, BT.2020) as EDR content, at
/// 4 bytes per pixel like SDR. `drawables` caps the swap chain (2 or 3).
/// `reuse` is a layer this Space already had: it is reconfigured and moved instead of
/// replaced, because a replaced layer's last drawable stays mapped (23 MB at native HDR).
fn makeLayer(dev: mtl.Id, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize, hdr: bool, drawables: usize, reuse: mtl.Id) mtl.Id {
    ev("layer {s} {d}x{d} hdr={}", .{ if (reuse != null) "reuse" else "new", w, h, hdr });
    const ml = reuse orelse blk: {
        const fresh = mtl.msg(mtl.Id, mtl.cls("CAMetalLayer"), "layer", .{}) orelse return null;
        _ = mtl.msg(mtl.Id, fresh, "retain", .{});
        break :blk fresh;
    };
    mtl.msg(void, ml, "setDevice:", .{dev});
    mtl.msg(void, ml, "setPixelFormat:", .{if (hdr) mtl.PIXEL_BGR10A2 else mtl.PIXEL_BGRA8});
    mtl.msg(void, ml, "setFramebufferOnly:", .{false});
    mtl.msg(void, ml, "setMaximumDrawableCount:", .{drawables});
    mtl.msg(void, ml, "setDrawableSize:", .{mtl.CGSize{ .width = @floatFromInt(w), .height = @floatFromInt(h) }});
    mtl.msg(void, ml, "setWantsExtendedDynamicRangeContent:", .{hdr});
    if (!hdr) mtl.msg(void, ml, "setEDRMetadata:", .{@as(mtl.Id, null)});
    if (hdr) {
        if (colorSpaceNamed("kCGColorSpaceITUR_2100_PQ")) |cs| mtl.msg(void, ml, "setColorspace:", .{cs});
        // PQ is absolute luminance: tell the compositor that 100 nits is display white (EDR 1.0).
        const md = mtl.msg(mtl.Id, mtl.cls("CAEDRMetadata"), "HDR10MetadataWithMinLuminance:maxLuminance:opticalOutputScale:", .{ @as(f32, 0.005), @as(f32, 1600.0), @as(f32, 100.0) });
        if (md != null) mtl.msg(void, ml, "setEDRMetadata:", .{md});
    } else if (color_space != null) mtl.msg(void, ml, "setColorspace:", .{color_space});
    mtl.msg(void, ml, "setOpaque:", .{true});
    mtl.msg(void, ml, "setAutoresizingMask:", .{@as(u32, 2 | 16)}); // width | height sizable
    moveLayer(ml, host_layer);
    return ml;
}

/// Puts `layer` on `host_layer` (no-op when it is already there), covering it.
fn moveLayer(layer: mtl.Id, host_layer: mtl.Id) void {
    if (mtl.msg(mtl.Id, layer, "superlayer", .{}) != host_layer) {
        ev("layer move", .{});
        mtl.msg(void, layer, "removeFromSuperlayer", .{});
        mtl.msg(void, host_layer, "addSublayer:", .{layer});
    }
    mtl.msg(void, layer, "setFrame:", .{mtl.msg(CGRect, host_layer, "bounds", .{})});
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

/// A layer that is going away for good (its Space changed to a non-GPU theme). Releasing a
/// CAMetalLayer leaves its swap chain mapped (measured: 2 x 23 MB per native HDR layer), so
/// it is shrunk and cycled through tiny frames first, and only taken out of the window a
/// second later, once the render server has let go of the old drawables.
const Retiring = struct { layer: mtl.Id, since: usize };
var retiring: [16]?Retiring = @splat(null);
var retire_queue: mtl.Id = null;
const RETIRE_TICKS: usize = 30;

fn retireLayer(layer: mtl.Id, tick: usize) void {
    if (layer == null) return;
    ev("layer retire t={d}", .{tick});
    shrinkDrawables(layer);
    if (retire_queue == null) retire_queue = mtl.msg(mtl.Id, mtl.device() catch null, "newCommandQueue", .{});
    if (retire_queue != null) {
        for (0..2) |_| {
            const pool = mtl.poolPush();
            defer mtl.poolPop(pool);
            const d = mtl.msg(mtl.Id, layer, "nextDrawable", .{}) orelse break;
            const cb = mtl.msg(mtl.Id, retire_queue, "commandBuffer", .{});
            mtl.msg(void, cb, "presentDrawable:", .{d});
            mtl.msg(void, cb, "commit", .{});
        }
    }
    for (&retiring) |*r| if (r.* == null) {
        r.* = .{ .layer = layer, .since = tick };
        return;
    };
    removeLayer(layer); // no slot: remove now
}

fn removeLayer(layer: mtl.Id) void {
    mtl.msg(void, layer, "removeFromSuperlayer", .{});
    mtl.release(layer);
}

/// Takes retired layers out of their windows once their drawables are gone.
pub fn reapLayers(tick: usize) void {
    for (&retiring) |*r| if (r.*) |x| if (tick -| x.since >= RETIRE_TICKS) {
        removeLayer(x.layer);
        r.* = null;
    };
}

/// Parks a hidden layer: shrinking the drawable size frees every drawable except the one on
/// screen, which keeps showing the last frame unchanged until the next render resizes it back.
fn shrinkDrawables(layer: mtl.Id) void {
    ev("layer park", .{});
    mtl.msg(void, layer, "setDrawableSize:", .{mtl.CGSize{ .width = 16, .height = 16 }});
}

fn setDrawables(layer: mtl.Id, w: usize, h: usize) void {
    ev("layer unpark", .{});
    mtl.msg(void, layer, "setDrawableSize:", .{mtl.CGSize{ .width = @floatFromInt(w), .height = @floatFromInt(h) }});
}

/// A Metal-only theme on a Space window.
pub const ThemePresenter = struct {
    theme: metal_theme.Theme,
    layer: mtl.Id,
    gen: u32, // SpaceConfig.dylib_gen of the load this was built for
    color_space: ?*anyopaque,
    parked: bool = false,

    /// `reuse`: the layer the Space's previous theme drew into (kept, see makeLayer), or null.
    pub fn create(src: []const u8, data: ?[]const u8, label: []const u8, gen: u32, seed: u32, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize, reuse: mtl.Id) ?ThemePresenter {
        var err_buf: [2048]u8 = undefined;
        var theme = metal_theme.Theme.compile(src, label, data, @intCast(w), @intCast(h), seed, &err_buf) catch {
            std.debug.print("argus: {s}: {s}\n", .{ label, std.mem.sliceTo(&err_buf, 0) });
            return null;
        };
        const layer = makeLayer(theme.dev, host_layer, color_space, w, h, false, 3, reuse) orelse {
            theme.deinit();
            return null;
        };
        return .{ .theme = theme, .layer = layer, .gen = gen, .color_space = color_space };
    }

    /// Frees the hidden layer's spare drawables (see shrinkDrawables).
    pub fn park(self: *ThemePresenter) void {
        if (self.parked) return;
        shrinkDrawables(self.layer);
        self.parked = true;
    }

    /// Moves the theme to another window layer (Spaces reordered) without recompiling it or
    /// losing its state.
    pub fn rehost(self: *ThemePresenter, host_layer: mtl.Id) bool {
        moveLayer(self.layer, host_layer);
        return true;
    }

    pub fn render(self: *ThemePresenter, dt: f32) bool {
        return self.renderTimes(dt, dt);
    }

    /// One frame: the clock advances `clock_dt`; `argus_step` runs with `step_dt`, or not at all
    /// when null (a draw-only frame between 30 Hz logic ticks, see desktop/frame_rate.zig).
    pub fn renderTimes(self: *ThemePresenter, clock_dt: f32, step_dt: ?f32) bool {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        if (self.parked) {
            setDrawables(self.layer, self.theme.frame.width, self.theme.frame.height);
            self.parked = false;
        }
        const drawable = mtl.msg(mtl.Id, self.layer, "nextDrawable", .{}) orelse return false;
        const cb = mtl.msg(mtl.Id, self.theme.queue, "commandBuffer", .{});
        self.theme.encodeTimes(cb, mtl.msg(mtl.Id, drawable, "texture", .{}), clock_dt, step_dt);
        mtl.msg(void, cb, "presentDrawable:", .{drawable});
        mtl.msg(void, cb, "commit", .{});
        return true;
    }

    /// Draws the current state once more into `dst` (packRGBA, w x h) for the menu preview.
    /// The kernel draws at the preview size directly; the texture lives only for the call.
    pub fn snapshot(self: *ThemePresenter, dst: []u32, w: usize, h: usize) bool {
        const encode = struct {
            fn f(t: *metal_theme.Theme, cb: mtl.Id, out: mtl.Id) void {
                t.encodeDrawOnly(cb, out);
            }
        }.f;
        const fw = self.theme.frame.width;
        const fh = self.theme.frame.height;
        self.theme.frame.width = @intCast(w);
        self.theme.frame.height = @intCast(h);
        defer {
            self.theme.frame.width = fw;
            self.theme.frame.height = fh;
        }
        var tex: mtl.Id = null;
        defer mtl.release(tex);
        return snapshotInto(self.theme.dev, self.theme.queue, &tex, w, h, dst, &self.theme, encode);
    }

    /// Frees the theme and hands back its layer for the Space's next GPU theme.
    pub fn release(self: *ThemePresenter) mtl.Id {
        const layer = self.layer;
        self.theme.deinit();
        self.* = undefined;
        return layer;
    }

    pub fn destroy(self: *ThemePresenter, tick: usize) void {
        retireLayer(self.release(), tick);
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

/// Traced images, shared by every Space showing the same theme at the same size (the trace
/// depends only on the theme source and the size). An image nobody uses is kept for
/// ENGINE_IDLE_TICKS so a theme reload or a Space reorder doesn't trace it again.
const EngineSlot = struct { key: u64, w: u32, h: u32, engine: bh_gpu.Engine, refs: u32, idle_since: usize };
var engines: [16]?EngineSlot = @splat(null);
const ENGINE_IDLE_TICKS: usize = 900; // 30 s at the app's 30 Hz tick

fn acquireEngine(key: u64, w: u32, h: u32) ?*bh_gpu.Engine {
    if (key == 0) return null;
    for (&engines) |*slot| if (slot.*) |*e| if (e.key == key and e.w == w and e.h == h and !e.engine.failed) {
        e.refs += 1;
        ev("engine shared {x} refs={d}", .{ key, e.refs });
        return &e.engine;
    };
    return null;
}

fn storeEngine(key: u64, w: u32, h: u32, engine: bh_gpu.Engine, tick: usize) ?*bh_gpu.Engine {
    reapEngines(tick, true);
    for (&engines) |*slot| if (slot.* == null) {
        ev("engine new {x} {d}x{d}", .{ key, w, h });
        slot.* = .{ .key = key, .w = w, .h = h, .engine = engine, .refs = 1, .idle_since = 0 };
        return &slot.*.?.engine;
    };
    return null;
}

fn releaseEngine(engine: *bh_gpu.Engine, tick: usize) void {
    for (&engines) |*slot| if (slot.*) |*e| if (&e.engine == engine) {
        e.refs -|= 1;
        if (e.refs == 0) e.idle_since = tick;
        return;
    };
}

/// Frees traced images nobody has used for ENGINE_IDLE_TICKS (all idle ones with `all`).
pub fn retire(layer: mtl.Id, tick: usize) void {
    retireLayer(layer, tick);
}

pub fn reapEngines(tick: usize, all: bool) void {
    for (&engines) |*slot| if (slot.*) |*e| if (e.refs == 0 and (all or tick -| e.idle_since >= ENGINE_IDLE_TICKS)) {
        e.engine.deinit();
        slot.* = null;
    };
}

/// Advances every running trace. A Space that isn't drawn never polled its engine, so its
/// finished trace kept the temporary light-travel buffer and ~120 tile command buffers alive.
pub fn pollEngines() void {
    for (&engines) |*slot| if (slot.*) |*e| {
        _ = e.engine.poll();
    };
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
    engine: *bh_gpu.Engine, // shared with other Spaces showing the same theme (see engines)
    fill_frame: FrameFn,
    frame: bt.Frame = undefined,
    hdr: bool,
    color_space: ?*anyopaque,
    parked: bool = false,
    /// The last frame's command buffer (retained) and the trace rows it showed: see render().
    last_cb: mtl.Id = null,
    shown_rows: u32 = 0,

    /// Returns null when the dylib isn't a GPU build or Metal is unavailable.
    /// `w` x `h` is the fallback size; the GPU traces at the window's native pixel size.
    /// `key` identifies the theme source (0 = don't share); `tick` is the app's frame counter.
    pub fn create(handle: ?*anyopaque, state_ptr: ?*anyopaque, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize, key: u64, tick: usize, reuse: mtl.Id) ?Presenter {
        const h_lib = handle orelse return null;
        const st = state_ptr orelse return null;
        const fill_frame: FrameFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_frame") orelse return null));
        const fill_static: StaticFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_static") orelse return null));
        const fill_trace: TraceFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_trace_params") orelse return null));
        const tables: TablesFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_tables") orelse return null));
        mtl.load() catch return null; // nativeSize messages AppKit before the engine loads Metal

        const size = nativeSize(host_layer, w, h);
        const engine = acquireEngine(key, size[0], size[1]) orelse blk: {
            var e = traceEngine(st, fill_static, fill_trace, tables, size) orelse return null;
            if (key == 0) {
                e.deinit(); // unshared engines aren't supported: every hybrid has a source key
                return null;
            }
            break :blk storeEngine(key, size[0], size[1], e, tick) orelse {
                e.deinit();
                return null;
            };
        };
        const hdr = hdr_enabled;
        // Two drawables: the image changes slowly and Argus draws at <= 30 FPS, so a third
        // window-sized buffer would only cost memory.
        const layer = makeLayer(engine.k.dev, host_layer, color_space, size[0], size[1], hdr, 2, reuse) orelse {
            releaseEngine(engine, tick);
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
            .color_space = color_space,
        };
    }

    /// A new traced image for this theme at `size` (meter, then the trace queued on the GPU).
    fn traceEngine(st: *anyopaque, fill_static: StaticFn, fill_trace: TraceFn, tables: TablesFn, size: [2]u32) ?bh_gpu.Engine {
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
        engine.startTrace(16); // seconds of GPU work at 3024x1964, in ~120 short submissions
        return engine;
    }

    /// Frees the hidden layer's spare drawable (see shrinkDrawables).
    pub fn park(self: *Presenter) void {
        if (self.parked) return;
        shrinkDrawables(self.layer);
        self.parked = true;
    }

    /// Moves to another window layer (Spaces reordered) keeping the traced image.
    pub fn rehost(self: *Presenter, host_layer: mtl.Id) bool {
        moveLayer(self.layer, host_layer);
        return true;
    }

    /// Shades one frame from the theme's current step state and presents it. Rows the trace
    /// hasn't reached yet draw black. Never fails once created: with no free drawable the
    /// frame is skipped (the caller must not fall back to the theme's CPU draw).
    pub fn render(self: *Presenter) bool {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        _ = self.engine.poll();
        // One frame on the GPU at a time. While the trace fills the GPU, a frame takes far longer
        // than 1/30 s, and frames queued behind it each hold a native-size drawable: ~40 of them
        // (900 MB at 3024x1964 HDR) piled up during Cygnus A's trace. While tracing, a new frame
        // is drawn only when more rows are done.
        if (self.last_cb) |cb| {
            if (mtl.msg(usize, cb, "status", .{}) < CB_COMPLETED) return true;
            mtl.release(cb);
            self.last_cb = null;
        }
        const rows = if (self.engine.done) self.engine.params.height else self.engine.rows_done;
        if (!self.engine.done and rows == self.shown_rows and !self.parked) return true;
        self.shown_rows = rows;
        if (self.parked) {
            setDrawables(self.layer, self.engine.params.width, self.engine.params.height);
            self.parked = false;
        }
        self.fill_frame(self.state, &self.frame);
        const drawable = mtl.msg(mtl.Id, self.layer, "nextDrawable", .{}) orelse return true;
        const cb = mtl.msg(mtl.Id, self.queue, "commandBuffer", .{});
        const p = self.engine.params;
        self.engine.encodeShade(cb, &self.frame, mtl.msg(mtl.Id, drawable, "texture", .{}), p.width, p.height, if (self.hdr) edrHeadroom() else 1.0, if (self.hdr) .pq else .srgb);
        mtl.msg(void, cb, "presentDrawable:", .{drawable});
        mtl.msg(void, cb, "commit", .{});
        self.last_cb = mtl.msg(mtl.Id, cb, "retain", .{});
        return true;
    }

    /// True while the traced image is still being built (rows not traced yet draw black).
    pub fn tracing(self: *const Presenter) bool {
        return !self.engine.done;
    }

    /// The current frame, again, into `dst` (packRGBA, w x h, SDR) for the menu preview.
    /// The texture lives only for the call: previews are occasional.
    pub fn snapshot(self: *Presenter, dst: []u32, w: usize, h: usize) bool {
        // The preview waits for the GPU; while the trace is running that means waiting behind
        // it on the main thread. The app retries a failed preview, so take it once the trace is done.
        if (!self.engine.poll()) return false;
        const Ctx = struct { pr: *Presenter, w: usize, h: usize };
        const encode = struct {
            fn f(c: *const Ctx, cb: mtl.Id, out: mtl.Id) void {
                c.pr.engine.encodeShade(cb, &c.pr.frame, out, c.w, c.h, 1.0, .srgb);
            }
        }.f;
        const ctx: Ctx = .{ .pr = self, .w = w, .h = h };
        var tex: mtl.Id = null;
        defer mtl.release(tex);
        return snapshotInto(self.engine.k.dev, self.queue, &tex, w, h, dst, &ctx, encode);
    }

    /// Detaches the layer and lets go of the traced image (kept a while for reuse). Call
    /// before the theme's state is freed.
    /// Lets go of the traced image and hands back the layer for the Space's next GPU theme.
    pub fn release(self: *Presenter, tick: usize) mtl.Id {
        const layer = self.layer;
        mtl.release(self.last_cb);
        mtl.release(self.queue);
        releaseEngine(self.engine, tick);
        self.* = undefined;
        return layer;
    }

    pub fn destroy(self: *Presenter, tick: usize) void {
        retireLayer(self.release(tick), tick);
    }
};

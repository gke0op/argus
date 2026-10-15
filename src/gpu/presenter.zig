// ============================================================================
// ARGUS GPU // src/gpu/presenter.zig
//
// Presents GPU themes through a CAMetalLayer on their Space's window, shading straight
// into the drawable (no CGImage, no CPU pixel buffer):
//  - ThemePresenter: Metal-only themes (themes/*.metal, see metal_theme.zig).
//  - Presenter: Zig + Metal hybrids. The Zig theme steps on the CPU and a Metal kernel
//    shades every pixel from its tables, bound zero-copy (Apple silicon shares memory
//    between CPU and GPU). Today: Opus_Black_Hole via src/gpu/bh_export.zig.
// ============================================================================

const std = @import("std");
const mtl = @import("metal.zig");
const bt = @import("bh_tables.zig");
const metal_theme = @import("metal_theme.zig");

pub const CGRect = extern struct { x: f64, y: f64, w: f64, h: f64 };

const MSL = @embedFile("opus_black_hole.metal");

/// A CAMetalLayer covering `host_layer` with a w x h BGRA8 drawable the kernels write directly.
fn makeLayer(dev: mtl.Id, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize) mtl.Id {
    const ml = mtl.msg(mtl.Id, mtl.cls("CAMetalLayer"), "layer", .{}) orelse return null;
    _ = mtl.msg(mtl.Id, ml, "retain", .{});
    mtl.msg(void, ml, "setDevice:", .{dev});
    mtl.msg(void, ml, "setPixelFormat:", .{mtl.PIXEL_BGRA8});
    mtl.msg(void, ml, "setFramebufferOnly:", .{false});
    mtl.msg(void, ml, "setDrawableSize:", .{mtl.CGSize{ .width = @floatFromInt(w), .height = @floatFromInt(h) }});
    if (color_space != null) mtl.msg(void, ml, "setColorspace:", .{color_space});
    mtl.msg(void, ml, "setOpaque:", .{true});
    mtl.msg(void, ml, "setFrame:", .{mtl.msg(CGRect, host_layer, "bounds", .{})});
    mtl.msg(void, ml, "setAutoresizingMask:", .{@as(u32, 2 | 16)}); // width | height sizable
    mtl.msg(void, host_layer, "addSublayer:", .{ml});
    return ml;
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

    pub fn create(src: []const u8, label: []const u8, gen: u32, seed: u32, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize) ?ThemePresenter {
        var err_buf: [2048]u8 = undefined;
        var theme = metal_theme.Theme.compile(src, label, @intCast(w), @intCast(h), seed, &err_buf) catch {
            std.debug.print("argus: {s}: {s}\n", .{ label, std.mem.sliceTo(&err_buf, 0) });
            return null;
        };
        const layer = makeLayer(theme.dev, host_layer, color_space, w, h) orelse {
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

    pub fn destroy(self: *ThemePresenter) void {
        detachLayer(self.layer);
        self.theme.deinit();
        self.* = undefined;
    }
};
const PAGE: usize = 16384;

const FillFrameFn = *const fn (*anyopaque, *bt.Frame) callconv(.c) void;
const FillStaticFn = *const fn (*anyopaque, *bt.Static) callconv(.c) void;
const BuffersFn = *const fn (*anyopaque, *[5]usize, *[5]usize) callconv(.c) void;

var kernel: ?mtl.Kernel = null;

pub const Presenter = struct {
    handle: ?*anyopaque, // the theme dylib this presenter was built for
    state: *anyopaque,
    layer: mtl.Id, // CAMetalLayer, a sublayer of the Space window's host layer
    data: [5]mtl.Id, // buffers 0-4 (one zero-copy buffer bound five times, or five copies)
    offs: [5]usize,
    stat: mtl.Id,
    fill_frame: FillFrameFn,
    frame: bt.Frame = undefined,

    /// Returns null when the dylib isn't a GPU build or Metal is unavailable.
    pub fn create(handle: ?*anyopaque, state_ptr: ?*anyopaque, host_layer: mtl.Id, color_space: ?*anyopaque, w: usize, h: usize) ?Presenter {
        const h_lib = handle orelse return null;
        const st = state_ptr orelse return null;
        const fill_frame: FillFrameFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_frame") orelse return null));
        const fill_static: FillStaticFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_static") orelse return null));
        const buffers: BuffersFn = @ptrCast(@alignCast(std.c.dlsym(h_lib, "argus_gpu_bh_buffers") orelse return null));
        if (kernel == null) kernel = mtl.Kernel.init(MSL, "bh_to_texture") catch return null;
        const k = &kernel.?;

        var ptrs: [5]usize = undefined;
        var lens: [5]usize = undefined;
        buffers(st, &ptrs, &lens);
        var p: Presenter = .{
            .handle = handle,
            .state = st,
            .layer = null,
            .data = @splat(null),
            .offs = @splat(0),
            .stat = k.bufferNew(@sizeOf(bt.Static)),
            .fill_frame = fill_frame,
        };
        fill_static(st, @ptrCast(@alignCast(mtl.contents(p.stat))));

        // All five live in the theme's single page-aligned slab: wrap its pages once, no copy.
        var lo: usize = std.math.maxInt(usize);
        var hi: usize = 0;
        for (ptrs, lens) |a, n| {
            lo = @min(lo, a);
            hi = @max(hi, a + n);
        }
        const base = lo & ~(PAGE - 1);
        const span = std.mem.alignForward(usize, hi - base, PAGE);
        const nocopy = mtl.msg(mtl.Id, k.device, "newBufferWithBytesNoCopy:length:options:deallocator:", .{
            @as(*anyopaque, @ptrFromInt(base)), span, mtl.STORAGE_SHARED, @as(?*anyopaque, null),
        });
        if (nocopy != null) {
            for (0..5) |i| {
                p.data[i] = nocopy;
                p.offs[i] = ptrs[i] - base;
            }
        } else {
            for (0..5) |i| p.data[i] = k.bufferCopy(@as([*]const u8, @ptrFromInt(ptrs[i]))[0..lens[i]]);
        }

        p.layer = makeLayer(k.device, host_layer, color_space, w, h) orelse return null;
        return p;
    }

    /// Shades one frame from the theme's current step state and presents it.
    pub fn render(self: *Presenter) bool {
        const k = &(kernel orelse return false);
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        self.fill_frame(self.state, &self.frame);
        const drawable = mtl.msg(mtl.Id, self.layer, "nextDrawable", .{}) orelse return false;
        const tex = mtl.msg(mtl.Id, drawable, "texture", .{});
        const cb = mtl.msg(mtl.Id, k.queue, "commandBuffer", .{});
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        mtl.msg(void, enc, "setComputePipelineState:", .{k.pso});
        for (self.data, self.offs, 0..) |b, o, i| mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ b, o, i });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.stat, @as(usize, 0), @as(usize, 5) });
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &self.frame), @as(usize, @sizeOf(bt.Frame)), @as(usize, 6) });
        mtl.msg(void, enc, "setTexture:atIndex:", .{ tex, @as(usize, 0) });
        mtl.msg(void, enc, "dispatchThreads:threadsPerThreadgroup:", .{
            mtl.MTLSize{ .w = self.frame.width, .h = self.frame.height, .d = 1 }, k.groupSize(),
        });
        mtl.msg(void, enc, "endEncoding", .{});
        mtl.msg(void, cb, "presentDrawable:", .{drawable});
        mtl.msg(void, cb, "commit", .{});
        return true;
    }

    /// Detaches the layer and releases GPU objects. Call before the theme's state is freed.
    pub fn destroy(self: *Presenter) void {
        detachLayer(self.layer);
        // The zero-copy buffer is bound up to five times but owned once.
        var seen: [5]mtl.Id = @splat(null);
        for (self.data, 0..) |b, i| {
            if (b == null or std.mem.indexOfScalar(mtl.Id, seen[0..i], b) != null) continue;
            seen[i] = b;
            mtl.release(b);
        }
        mtl.release(self.stat);
        self.* = undefined;
    }
};

// ============================================================================
// ARGUS GPU // src/gpu/bh_gpu.zig
//
// Opus_Quasar's GPU engine (kernels in opus_black_hole.metal), shared by the app's
// presenter and `make gpu-bench`:
//   init   upload the theme's tables, allocate the traced image (12 B/pixel, GPU-private,
//          plus 2 B/pixel freed when the trace is done)
//   meter  exposure from inner-disk luminance (blocks ~tens of ms)
//   trace  queue the geodesic trace in row tiles on its own command queue, then the
//          footprint pass; poll() advances `rows_done` as tiles finish, so frames keep
//          presenting (rows not traced yet draw black) and no GPU submission runs long
//   shade  encode one frame into a texture: HDR (linear, extended range) or sRGB 8-bit
// ============================================================================

const std = @import("std");
const mtl = @import("metal.zig");
const bt = @import("bh_tables.zig");

const MSL = @embedFile("opus_black_hole.metal");
const EXPO_TARGET: f64 = 7.0; // the theme's: 99th-percentile inner-disk luminance maps here
const BUF_PRIVATE: usize = 2 << 4; // MTLResourceStorageModePrivate
const MAX_TILES = 512;
const CB_COMPLETED: usize = 4;
const CB_ERROR: usize = 5;

const Pipe = struct {
    pso: mtl.Id,
    group: mtl.MTLSize,

    fn make(dev: mtl.Id, lib: mtl.Id, name: [*:0]const u8) !Pipe {
        const func = mtl.msg(mtl.Id, lib, "newFunctionWithName:", .{mtl.nsString(name)}) orelse return error.MetalNoEntry;
        defer mtl.release(func);
        var err: mtl.Id = null;
        const pso = mtl.msg(mtl.Id, dev, "newComputePipelineStateWithFunction:error:", .{ func, &err }) orelse {
            std.debug.print("argus: {s}: {s}\n", .{ name, mtl.describe(err) });
            return error.MetalPipeline;
        };
        const tw = mtl.msg(usize, pso, "threadExecutionWidth", .{});
        const tmax = mtl.msg(usize, pso, "maxTotalThreadsPerThreadgroup", .{});
        return .{ .pso = pso, .group = .{ .w = tw, .h = @max(1, tmax / tw), .d = 1 } };
    }

    fn dispatch(self: Pipe, enc: mtl.Id, w: usize, h: usize) void {
        mtl.msg(void, enc, "setComputePipelineState:", .{self.pso});
        mtl.msg(void, enc, "dispatchThreads:threadsPerThreadgroup:", .{ mtl.MTLSize{ .w = w, .h = h, .d = 1 }, self.group });
    }
};

/// Compiled once per process: every Opus Space shares the pipelines.
const Kernels = struct {
    dev: mtl.Id,
    meter: Pipe,
    trace: Pipe,
    footprint: Pipe,
    shade: Pipe,
    probe: Pipe,
};
var kernels: ?Kernels = null;

fn getKernels() !*const Kernels {
    if (kernels == null) {
        const dev = try mtl.device();
        var err: mtl.Id = null;
        const lib = mtl.msg(mtl.Id, dev, "newLibraryWithSource:options:error:", .{ mtl.nsString(MSL), @as(mtl.Id, null), &err }) orelse {
            std.debug.print("argus: opus_black_hole.metal: {s}\n", .{mtl.describe(err)});
            return error.MetalCompile;
        };
        defer mtl.release(lib);
        kernels = .{
            .dev = dev,
            .meter = try Pipe.make(dev, lib, "bh_meter"),
            .trace = try Pipe.make(dev, lib, "bh_trace"),
            .footprint = try Pipe.make(dev, lib, "bh_footprint"),
            .shade = try Pipe.make(dev, lib, "bh_shade"),
            .probe = try Pipe.make(dev, lib, "bh_probe"),
        };
    }
    return &kernels.?;
}

pub const Engine = struct {
    k: *const Kernels,
    trace_queue: mtl.Id,
    params: bt.TraceParams,
    stat: mtl.Id,
    ttab: mtl.Id,
    noise: mtl.Id,
    recs: mtl.Id,
    bg: mtl.Id,
    tq: mtl.Id, // light-travel phase: only until the footprint pass has run
    bfrac: mtl.Id, // share of bg behind the animated gas (dimmed by it every frame)
    lmu: mtl.Id, // ln(1/mu) of the animated gas: its line-of-sight slant
    tiles: [MAX_TILES]mtl.Id = @splat(null),
    tile_rows: u32 = 0,
    n_tiles: usize = 0,
    next_tile: usize = 0,
    rows_done: u32 = 0,
    footprint_cb: mtl.Id = null,
    done: bool = false,
    failed: bool = false,

    /// Uploads the theme's tables and allocates a `params.width` x `params.height` image.
    pub fn init(static: *const bt.Static, params: bt.TraceParams, noise: []const u8, ttab: []const u8) !Engine {
        const k = try getKernels();
        const dev = k.dev;
        const n: usize = @as(usize, params.width) * params.height;
        var e: Engine = .{
            .k = k,
            .trace_queue = mtl.msg(mtl.Id, dev, "newCommandQueue", .{}),
            .params = params,
            .stat = bufferCopy(dev, std.mem.asBytes(static)),
            .ttab = bufferCopy(dev, ttab),
            .noise = bufferCopy(dev, noise),
            .recs = mtl.msg(mtl.Id, dev, "newBufferWithLength:options:", .{ n * 6, BUF_PRIVATE }),
            .bg = mtl.msg(mtl.Id, dev, "newBufferWithLength:options:", .{ n * 4, BUF_PRIVATE }),
            .tq = mtl.msg(mtl.Id, dev, "newBufferWithLength:options:", .{ n * 2, BUF_PRIVATE }),
            .bfrac = mtl.msg(mtl.Id, dev, "newBufferWithLength:options:", .{ n, BUF_PRIVATE }),
            .lmu = mtl.msg(mtl.Id, dev, "newBufferWithLength:options:", .{ n, BUF_PRIVATE }),
        };
        if (e.trace_queue == null or e.stat == null or e.ttab == null or e.noise == null or e.recs == null or e.bg == null or e.tq == null or e.bfrac == null or e.lmu == null) {
            e.deinit();
            return error.MetalAlloc;
        }
        return e;
    }

    /// Exposure from the theme's metering rule, on the GPU's own trace. Blocks until done.
    pub fn meter(self: *Engine) f32 {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const n: usize = @as(usize, self.params.grid_w) * self.params.grid_h;
        const lum = mtl.msg(mtl.Id, self.k.dev, "newBufferWithLength:options:", .{ n * 4, mtl.STORAGE_SHARED }) orelse return 1.0;
        defer mtl.release(lum);
        const cb = mtl.msg(mtl.Id, self.trace_queue, "commandBuffer", .{});
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        self.bindTrace(enc);
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ lum, @as(usize, 0), @as(usize, 3) });
        self.k.meter.dispatch(enc, self.params.grid_w, self.params.grid_h);
        mtl.msg(void, enc, "endEncoding", .{});
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        const vals: [*]const f32 = @ptrCast(@alignCast(mtl.contents(lum)));
        self.params.exposure = bt.exposureFrom(vals[0..n], EXPO_TARGET);
        return self.params.exposure;
    }

    /// Queues the whole trace (row tiles, then the footprint pass) without waiting.
    pub fn startTrace(self: *Engine, rows_per_tile: u32) void {
        const h = self.params.height;
        self.tile_rows = @max(rows_per_tile, std.math.divCeil(u32, h, MAX_TILES) catch MAX_TILES);
        self.n_tiles = std.math.divCeil(u32, h, self.tile_rows) catch 0;
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        for (0..self.n_tiles) |t| {
            var p = self.params;
            p.row0 = @intCast(t * self.tile_rows);
            const rows = @min(self.tile_rows, h - p.row0);
            const cb = mtl.msg(mtl.Id, self.trace_queue, "commandBuffer", .{});
            _ = mtl.msg(mtl.Id, cb, "retain", .{});
            const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
            self.bindTrace(enc);
            mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &p), @as(usize, @sizeOf(bt.TraceParams)), @as(usize, 0) });
            mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.recs, @as(usize, 0), @as(usize, 3) });
            mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.bg, @as(usize, 0), @as(usize, 4) });
            mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.tq, @as(usize, 0), @as(usize, 5) });
            mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.bfrac, @as(usize, 0), @as(usize, 6) });
            mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.lmu, @as(usize, 0), @as(usize, 7) });
            self.k.trace.dispatch(enc, self.params.width, rows);
            mtl.msg(void, enc, "endEncoding", .{});
            mtl.msg(void, cb, "commit", .{});
            self.tiles[t] = cb;
        }
        const cb = mtl.msg(mtl.Id, self.trace_queue, "commandBuffer", .{});
        _ = mtl.msg(mtl.Id, cb, "retain", .{});
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &self.params), @as(usize, @sizeOf(bt.TraceParams)), @as(usize, 0) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.recs, @as(usize, 0), @as(usize, 1) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.tq, @as(usize, 0), @as(usize, 2) });
        self.k.footprint.dispatch(enc, self.params.width, self.params.height);
        mtl.msg(void, enc, "endEncoding", .{});
        mtl.msg(void, cb, "commit", .{});
        self.footprint_cb = cb;
    }

    /// Advances `rows_done` over finished tiles; true once the trace and footprints are done.
    pub fn poll(self: *Engine) bool {
        if (self.done) return true;
        while (self.next_tile < self.n_tiles) {
            const cb = self.tiles[self.next_tile];
            const status = mtl.msg(usize, cb, "status", .{});
            if (status == CB_ERROR) self.failed = true;
            if (status < CB_COMPLETED) return false;
            mtl.release(cb);
            self.tiles[self.next_tile] = null;
            self.next_tile += 1;
            self.rows_done = @intCast(@min(self.next_tile * self.tile_rows, self.params.height));
        }
        if (self.footprint_cb) |cb| {
            if (mtl.msg(usize, cb, "status", .{}) < CB_COMPLETED) return false;
            mtl.release(cb);
            self.footprint_cb = null;
        }
        mtl.release(self.tq); // the footprints are in the records now
        self.tq = null;
        self.done = true;
        return true;
    }

    /// Blocks until the trace has finished (bench and tests).
    pub fn waitTrace(self: *Engine) void {
        if (self.footprint_cb) |cb| mtl.msg(void, cb, "waitUntilCompleted", .{});
        _ = self.poll();
    }

    /// Encodes one frame into `tex` (out_w x out_h) in the given encoding.
    pub fn encodeShade(self: *const Engine, cb: mtl.Id, frame: *const bt.Frame, tex: mtl.Id, out_w: usize, out_h: usize, headroom: f32, mode: bt.OutMode) void {
        const view: bt.View = .{
            .width = self.params.width,
            .height = self.params.height,
            .out_w = @intCast(out_w),
            .out_h = @intCast(out_h),
            .rows_done = if (self.done) self.params.height else self.rows_done,
            .exposure = self.params.exposure,
            .headroom = headroom,
            .out_mode = mode,
        };
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.recs, @as(usize, 0), @as(usize, 0) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.bg, @as(usize, 0), @as(usize, 1) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.noise, @as(usize, 0), @as(usize, 2) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.stat, @as(usize, 0), @as(usize, 3) });
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, frame), @as(usize, @sizeOf(bt.Frame)), @as(usize, 4) });
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &view), @as(usize, @sizeOf(bt.View)), @as(usize, 5) });
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &self.params), @as(usize, @sizeOf(bt.TraceParams)), @as(usize, 6) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.ttab, @as(usize, 0), @as(usize, 7) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.bfrac, @as(usize, 0), @as(usize, 8) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.lmu, @as(usize, 0), @as(usize, 9) });
        mtl.msg(void, enc, "setTexture:atIndex:", .{ tex, @as(usize, 0) });
        self.k.shade.dispatch(enc, out_w, out_h);
        mtl.msg(void, enc, "endEncoding", .{});
    }

    /// Kinds (0 sky, 1 disk, 2 hole) of the first thing each (alpha, beta) ray meets,
    /// without the disk: the shadow-edge test's probe. Blocks.
    pub fn probe(self: *Engine, ab: []const [2]f32, kinds: []u32) void {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const in = bufferCopy(self.k.dev, std.mem.sliceAsBytes(ab));
        defer mtl.release(in);
        const out = mtl.msg(mtl.Id, self.k.dev, "newBufferWithLength:options:", .{ kinds.len * 4, mtl.STORAGE_SHARED });
        defer mtl.release(out);
        const cb = mtl.msg(mtl.Id, self.trace_queue, "commandBuffer", .{});
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &self.params), @as(usize, @sizeOf(bt.TraceParams)), @as(usize, 0) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ in, @as(usize, 0), @as(usize, 1) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ out, @as(usize, 0), @as(usize, 2) });
        mtl.msg(void, enc, "setComputePipelineState:", .{self.k.probe.pso});
        mtl.msg(void, enc, "dispatchThreads:threadsPerThreadgroup:", .{ mtl.MTLSize{ .w = ab.len, .h = 1, .d = 1 }, mtl.MTLSize{ .w = 32, .h = 1, .d = 1 } });
        mtl.msg(void, enc, "endEncoding", .{});
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        const got: [*]const u32 = @ptrCast(@alignCast(mtl.contents(out)));
        @memcpy(kinds, got[0..kinds.len]);
    }

    pub fn deinit(self: *Engine) void {
        for (self.tiles) |cb| mtl.release(cb);
        mtl.release(self.footprint_cb);
        for ([_]mtl.Id{ self.stat, self.ttab, self.noise, self.recs, self.bg, self.tq, self.bfrac, self.lmu, self.trace_queue }) |o| mtl.release(o);
        self.* = undefined;
    }

    fn bindTrace(self: *const Engine, enc: mtl.Id) void {
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &self.params), @as(usize, @sizeOf(bt.TraceParams)), @as(usize, 0) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.stat, @as(usize, 0), @as(usize, 1) });
        mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ self.ttab, @as(usize, 0), @as(usize, 2) });
    }
};

fn bufferCopy(dev: mtl.Id, bytes: []const u8) mtl.Id {
    return mtl.msg(mtl.Id, dev, "newBufferWithBytes:length:options:", .{ @as(*const anyopaque, bytes.ptr), bytes.len, mtl.STORAGE_SHARED });
}

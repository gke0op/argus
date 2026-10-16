// ============================================================================
// ARGUS GPU // src/gpu/metal_theme.zig
//
// Runtime for Metal-only themes (themes/*.metal). A theme is one Metal source file:
//
//   kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
//                          texture2d<float, access::write> out [[texture(0)]],
//                          uint2 gid [[thread_position_in_grid]])          required
//
// and, for themes that remember things between frames, a state texture:
//
//   kernel void argus_init(constant ArgusFrame&, texture2d<float, access::write> state [[texture(0)]], uint2)
//   kernel void argus_step(constant ArgusFrame&, texture2d<float, access::read> prev [[texture(0)]],
//                          texture2d<float, access::write> next [[texture(1)]], uint2)
//   argus_draw then also receives the current state as [[texture(1)]].
//
// Directives in comments:  // @argus state 480x300 [float32]    // @argus steps 4
//                          // @argus data Name.bin 512x512 rgba8|rgba16f
// `@argus data` ships a raw texel file next to the theme (W*H texels, row-major, no header;
// see loadData). argus_init then receives it read-only as [[texture(1)]], to bake from.
// The prelude (argus_prelude.metal) is prepended; see .claude/skills/argus-metal-theme.
// ============================================================================

const std = @import("std");
const mtl = @import("metal.zig");

pub const PRELUDE = @embedFile("argus_prelude.metal");

/// Mirrors `struct ArgusFrame` in the prelude.
pub const Frame = extern struct {
    time: f32 = 0,
    dt: f32 = 0,
    frame: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    state_width: u32 = 0,
    state_height: u32 = 0,
    seed: u32 = 0,
};

pub const Directives = struct {
    state_w: u32 = 0,
    state_h: u32 = 0,
    state_f32: bool = false,
    steps: u32 = 1,
    /// `@argus data`: a file next to the theme, uploaded to a texture for argus_init.
    data_name: [MAX_DATA_NAME]u8 = undefined,
    data_name_len: usize = 0,
    data_w: u32 = 0,
    data_h: u32 = 0,
    data_f16: bool = false,

    pub fn dataName(self: *const Directives) ?[]const u8 {
        return if (self.data_name_len == 0) null else self.data_name[0..self.data_name_len];
    }
    pub fn dataBytes(self: *const Directives) usize {
        return @as(usize, self.data_w) * self.data_h * @as(usize, if (self.data_f16) 8 else 4);
    }
};

pub const MAX_STATE_SIDE: u32 = 4096;
pub const MAX_STEPS: u32 = 64;
pub const MAX_DATA_NAME: usize = 64;

/// Reads `@argus state WxH [float32]` and `@argus steps N` from anywhere in the source.
pub fn parseDirectives(src: []const u8) Directives {
    var d: Directives = .{};
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        const at = std.mem.indexOf(u8, line, "@argus") orelse continue;
        var it = std.mem.tokenizeAny(u8, line[at + "@argus".len ..], " \t\r");
        const key = it.next() orelse continue;
        if (std.mem.eql(u8, key, "state")) {
            const size = it.next() orelse continue;
            const x = std.mem.indexOfScalar(u8, size, 'x') orelse continue;
            d.state_w = std.math.clamp(std.fmt.parseInt(u32, size[0..x], 10) catch continue, 1, MAX_STATE_SIDE);
            d.state_h = std.math.clamp(std.fmt.parseInt(u32, size[x + 1 ..], 10) catch continue, 1, MAX_STATE_SIDE);
            if (it.next()) |fmt| d.state_f32 = std.mem.eql(u8, fmt, "float32");
        } else if (std.mem.eql(u8, key, "steps")) {
            const n = it.next() orelse continue;
            d.steps = std.math.clamp(std.fmt.parseInt(u32, n, 10) catch continue, 1, MAX_STEPS);
        } else if (std.mem.eql(u8, key, "data")) {
            // A plain file name next to the theme: no directories, nothing hidden.
            const name = it.next() orelse continue;
            if (name.len == 0 or name.len > MAX_DATA_NAME or name[0] == '.' or
                std.mem.indexOfAny(u8, name, "/\\") != null) continue;
            const size = it.next() orelse continue;
            const x = std.mem.indexOfScalar(u8, size, 'x') orelse continue;
            const w = std.math.clamp(std.fmt.parseInt(u32, size[0..x], 10) catch continue, 1, MAX_STATE_SIDE);
            const h = std.math.clamp(std.fmt.parseInt(u32, size[x + 1 ..], 10) catch continue, 1, MAX_STATE_SIDE);
            const fmt = it.next() orelse "rgba8";
            if (!std.mem.eql(u8, fmt, "rgba8") and !std.mem.eql(u8, fmt, "rgba16f")) continue;
            @memcpy(d.data_name[0..name.len], name);
            d.data_name_len = name.len;
            d.data_w = w;
            d.data_h = h;
            d.data_f16 = std.mem.eql(u8, fmt, "rgba16f");
        }
    }
    return d;
}

/// Reads the theme's `@argus data` file (next to `theme_path`), or returns null when the
/// theme has none. The caller frees the bytes after `Theme.compile`, which copies them.
pub fn loadData(io: std.Io, alloc: std.mem.Allocator, theme_path: []const u8, src: []const u8) !?[]u8 {
    const d = parseDirectives(src);
    const name = d.dataName() orelse return null;
    const dir = std.Io.Dir.path.dirname(theme_path) orelse ".";
    const path = try std.Io.Dir.path.join(alloc, &.{ dir, name });
    defer alloc.free(path);
    const want = d.dataBytes();
    const buf = try alloc.alloc(u8, want);
    errdefer alloc.free(buf);
    const got = try std.Io.Dir.cwd().readFile(io, path, buf);
    if (got.len != want) return error.MetalDataSize;
    return buf;
}

pub const Pipe = struct {
    pso: mtl.Id,
    group: mtl.MTLSize,
    /// maxTotalThreadsPerThreadgroup (reported by the harness).
    max_threads: usize,

    fn make(dev: mtl.Id, lib: mtl.Id, name: [*:0]const u8, err_buf: []u8) !?Pipe {
        const func = mtl.msg(mtl.Id, lib, "newFunctionWithName:", .{mtl.nsString(name)}) orelse return null;
        defer mtl.release(func);
        var err: mtl.Id = null;
        const pso = mtl.msg(mtl.Id, dev, "newComputePipelineStateWithFunction:error:", .{ func, &err }) orelse {
            _ = std.fmt.bufPrint(err_buf, "{s}: {s}", .{ name, mtl.describe(err) }) catch {};
            return error.MetalPipeline;
        };
        const tw = mtl.msg(usize, pso, "threadExecutionWidth", .{});
        const tmax = mtl.msg(usize, pso, "maxTotalThreadsPerThreadgroup", .{});
        return .{ .pso = pso, .group = .{ .w = tw, .h = @max(1, tmax / tw), .d = 1 }, .max_threads = tmax };
    }

    fn dispatch(self: Pipe, enc: mtl.Id, w: usize, h: usize) void {
        mtl.msg(void, enc, "setComputePipelineState:", .{self.pso});
        mtl.msg(void, enc, "dispatchThreads:threadsPerThreadgroup:", .{ mtl.MTLSize{ .w = w, .h = h, .d = 1 }, self.group });
    }
};

pub const Theme = struct {
    dev: mtl.Id,
    queue: mtl.Id,
    draw: Pipe,
    init: ?Pipe,
    step: ?Pipe,
    clear: ?Pipe,
    dir: Directives,
    tex: [2]mtl.Id = .{ null, null },
    data_tex: mtl.Id = null,
    cur: usize = 0,
    needs_init: bool = true,
    frame: Frame = .{},

    /// Compiles prelude + `src` for an `out_w` x `out_h` output. On failure `err_buf`
    /// holds the Metal compiler's message (with the theme's own line numbers). `data` is the
    /// theme's `@argus data` file (loadData), or null when it has none.
    pub fn compile(src: []const u8, label: []const u8, data: ?[]const u8, out_w: u32, out_h: u32, seed: u32, err_buf: []u8) !Theme {
        @memset(err_buf, 0);
        const dev = try mtl.device();
        const alloc = std.heap.page_allocator;
        const full = try std.fmt.allocPrintSentinel(alloc, "{s}\n#line 1 \"{s}\"\n{s}\n", .{ PRELUDE, label, src }, 0);
        defer alloc.free(full);

        var err: mtl.Id = null;
        const lib = mtl.msg(mtl.Id, dev, "newLibraryWithSource:options:error:", .{ mtl.nsString(full.ptr), @as(mtl.Id, null), &err }) orelse {
            _ = std.fmt.bufPrint(err_buf, "{s}", .{mtl.describe(err)}) catch {};
            return error.MetalCompile;
        };
        defer mtl.release(lib);

        const draw = (try Pipe.make(dev, lib, "argus_draw", err_buf)) orelse {
            _ = std.fmt.bufPrint(err_buf, "no `kernel void argus_draw(...)` in {s}", .{label}) catch {};
            return error.MetalNoDraw;
        };
        const init = try Pipe.make(dev, lib, "argus_init", err_buf);
        const step = try Pipe.make(dev, lib, "argus_step", err_buf);
        var dir = parseDirectives(src);
        const has_state = init != null or step != null or dir.state_w != 0;
        if (has_state and dir.state_w == 0) {
            dir.state_w = out_w;
            dir.state_h = out_h;
        }
        var t: Theme = .{
            .dev = dev,
            .queue = mtl.msg(mtl.Id, dev, "newCommandQueue", .{}),
            .draw = draw,
            .init = init,
            .step = step,
            .clear = if (has_state) try Pipe.make(dev, lib, "argus_clear_state", err_buf) else null,
            .dir = dir,
            .frame = .{ .width = out_w, .height = out_h, .state_width = dir.state_w, .state_height = dir.state_h, .seed = seed },
        };
        if (has_state) {
            const fmt = if (dir.state_f32) mtl.PIXEL_RGBA32F else mtl.PIXEL_RGBA16F;
            for (&t.tex) |*tx| tx.* = mtl.newTexture(dev, fmt, dir.state_w, dir.state_h, mtl.STORAGE_PRIVATE);
            if (t.tex[0] == null or t.tex[1] == null) return error.MetalStateTexture;
        }
        if (dir.dataName()) |name| {
            const bytes = data orelse {
                _ = std.fmt.bufPrint(err_buf, "{s}: data file {s} ({d}x{d}) missing or the wrong size", .{ label, name, dir.data_w, dir.data_h }) catch {};
                return error.MetalData;
            };
            if (bytes.len != dir.dataBytes() or t.init == null) {
                _ = std.fmt.bufPrint(err_buf, "{s}: data file {s} needs {d} bytes and an argus_init", .{ label, name, dir.dataBytes() }) catch {};
                return error.MetalData;
            }
            const fmt = if (dir.data_f16) mtl.PIXEL_RGBA16F else mtl.PIXEL_RGBA8;
            t.data_tex = mtl.newTexture(dev, fmt, dir.data_w, dir.data_h, mtl.STORAGE_SHARED) orelse return error.MetalData;
            const row: usize = @as(usize, dir.data_w) * @as(usize, if (dir.data_f16) 8 else 4);
            const region = mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = dir.data_w, .h = dir.data_h, .d = 1 };
            mtl.msg(void, t.data_tex, "replaceRegion:mipmapLevel:withBytes:bytesPerRow:", .{ region, @as(usize, 0), @as(*const anyopaque, bytes.ptr), row });
        }
        return t;
    }

    pub fn stateful(self: *const Theme) bool {
        return self.tex[0] != null;
    }

    /// Encodes one frame into `cb`: init once, `steps` state updates, then the draw into `out`.
    pub fn encode(self: *Theme, cb: mtl.Id, out: mtl.Id, dt: f32) void {
        self.frame.dt = dt;
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        const fb: *const anyopaque = &self.frame;
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ fb, @as(usize, @sizeOf(Frame)), @as(usize, 0) });
        const sw: usize = self.dir.state_w;
        const sh: usize = self.dir.state_h;
        if (self.stateful()) {
            if (self.needs_init) {
                self.needs_init = false;
                const p = self.init orelse self.clear.?;
                mtl.msg(void, enc, "setTexture:atIndex:", .{ self.tex[self.cur], @as(usize, 0) });
                if (self.data_tex != null) mtl.msg(void, enc, "setTexture:atIndex:", .{ self.data_tex, @as(usize, 1) });
                p.dispatch(enc, sw, sh);
            }
            if (self.step) |p| {
                for (0..self.dir.steps) |_| {
                    mtl.msg(void, enc, "setTexture:atIndex:", .{ self.tex[self.cur], @as(usize, 0) });
                    mtl.msg(void, enc, "setTexture:atIndex:", .{ self.tex[self.cur ^ 1], @as(usize, 1) });
                    p.dispatch(enc, sw, sh);
                    self.cur ^= 1;
                }
            }
            mtl.msg(void, enc, "setTexture:atIndex:", .{ self.tex[self.cur], @as(usize, 1) });
        }
        mtl.msg(void, enc, "setTexture:atIndex:", .{ out, @as(usize, 0) });
        self.draw.dispatch(enc, self.frame.width, self.frame.height);
        mtl.msg(void, enc, "endEncoding", .{});
        self.frame.frame +%= 1;
        self.frame.time += dt;
    }

    /// Encodes only argus_draw for the current state, without advancing time or the state
    /// (used for menu previews).
    pub fn encodeDrawOnly(self: *Theme, cb: mtl.Id, out: mtl.Id) void {
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        const fb: *const anyopaque = &self.frame;
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ fb, @as(usize, @sizeOf(Frame)), @as(usize, 0) });
        if (self.stateful()) mtl.msg(void, enc, "setTexture:atIndex:", .{ self.tex[self.cur], @as(usize, 1) });
        mtl.msg(void, enc, "setTexture:atIndex:", .{ out, @as(usize, 0) });
        self.draw.dispatch(enc, self.frame.width, self.frame.height);
        mtl.msg(void, enc, "endEncoding", .{});
    }

    pub fn deinit(self: *Theme) void {
        for ([_]?Pipe{ self.draw, self.init, self.step, self.clear }) |p| if (p) |q| mtl.release(q.pso);
        for (self.tex) |t| mtl.release(t);
        mtl.release(self.data_tex);
        mtl.release(self.queue);
        self.* = undefined;
    }
};

test "directives" {
    const d = parseDirectives("// @argus state 480x300 float32\n// @argus steps 4\nkernel void argus_draw() {}");
    try std.testing.expectEqual(@as(u32, 480), d.state_w);
    try std.testing.expectEqual(@as(u32, 300), d.state_h);
    try std.testing.expect(d.state_f32);
    try std.testing.expectEqual(@as(u32, 4), d.steps);
    try std.testing.expectEqual(@as(u32, 0), parseDirectives("kernel void argus_draw() {}").state_w);
    try std.testing.expect(d.dataName() == null);

    const e = parseDirectives("// @argus data Nebula.bin 256x128 rgba16f\n");
    try std.testing.expectEqualStrings("Nebula.bin", e.dataName().?);
    try std.testing.expectEqual(@as(usize, 256 * 128 * 8), e.dataBytes());
    try std.testing.expect(parseDirectives("// @argus data ../x.bin 4x4\n").dataName() == null);
    try std.testing.expect(parseDirectives("// @argus data a/x.bin 4x4\n").dataName() == null);
    try std.testing.expect(parseDirectives("// @argus data x.bin 4x4 rgb9\n").dataName() == null);
}

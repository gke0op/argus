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
// `@argus stats` asks for the Mac's live vital signs: every kernel then receives
// `constant ArgusStats& s [[buffer(1)]]` (argus_stats.zig; sampled ~1/s by the app, synthetic
// in the harness). Without the directive nothing is sampled and buffer 1 is unbound.
// The prelude (argus_prelude.metal) is prepended; see .claude/skills/argus-metal-theme.
// ============================================================================

const std = @import("std");
const mtl = @import("metal.zig");
const argus_stats = @import("argus_stats.zig");

pub const PRELUDE = @embedFile("argus_prelude.metal");

/// `f.time` wraps after this many seconds (4 h; ARGUS_TIME_PERIOD in the prelude). The clock
/// itself is an f64; a float32 that kept growing would lose the frame step after days (dt
/// rounds to 2x at ~6 days and to 0 at ~12, so animation races and then freezes). Wrapped,
/// f.time stays within ~1 ms forever. A cycle of any whole number of minutes that divides 240
/// (1-6, 8, 10, 12, 15, 16, 20, 24, 30, 40, 48, 60 ...) stays seamless across a wrap.
pub const TIME_PERIOD: f64 = 14400.0;

/// Advances the f64 `clock` by `dt` and returns the float32 `f.time` the kernels see.
pub fn advanceClock(clock: *f64, dt: f32) f32 {
    clock.* += dt;
    return @floatCast(@mod(clock.*, TIME_PERIOD));
}

/// `f.frame`: the 30 Hz simulation tick index, the same at every frame rate. The first encode
/// is tick 0; each later encode that steps (a logic tick, see desktop/frame_rate.zig) moves to the
/// next tick, and draw-only encodes between ticks reuse the current number. Themes that build
/// state on frames 0, 1, 2 or pace events by `f.frame / N` therefore behave as at 30 FPS.
pub const FrameCounter = struct {
    current: u32 = 0,
    started: bool = false,

    /// The f.frame for this encode; `tick` is true when argus_step runs in it.
    pub fn forEncode(self: *FrameCounter, tick: bool) u32 {
        if (tick) {
            if (self.started) self.current +%= 1 else self.started = true;
        }
        return self.current;
    }
};

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
    /// `@argus stats`: bind ArgusStats as [[buffer(1)]].
    stats: bool = false,

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
        } else if (std.mem.eql(u8, key, "stats")) {
            d.stats = true;
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
    // The file must be exactly the declared size: a larger one would otherwise load its
    // first `want` bytes silently.
    const st = try std.Io.Dir.cwd().statFile(io, path, .{});
    if (st.size != want) return error.MetalDataSize;
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
    ticks: FrameCounter = .{},
    /// Seconds since load, in f64 (see TIME_PERIOD); frame.time is this, wrapped.
    clock: f64 = 0,
    /// `@argus stats` themes: what [[buffer(1)]] holds. With `stats_live` false (the harness,
    /// tests) every encode fills it with argus_stats.synthetic, one new sample per 30 ticks;
    /// the app sets it true and copies live samples in before each frame.
    stats: argus_stats.Stats = .{},
    stats_live: bool = false,

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
        self.encodeTimes(cb, out, dt, dt);
    }

    /// `encode` with the clock and the state steps decoupled: f.time advances by `clock_dt`
    /// (the frame interval) and `argus_step` runs with f.dt = `step_dt`, or is skipped when null.
    /// Steps happen at the fixed 30 Hz logic rate whatever the frame rate, so every simulation
    /// moves the same at 30, 60 and 120 FPS (desktop/frame_rate.zig). With equal dts this is
    /// exactly `encode`.
    pub fn encodeTimes(self: *Theme, cb: mtl.Id, out: mtl.Id, clock_dt: f32, step_dt: ?f32) void {
        self.frame.frame = self.ticks.forEncode(step_dt != null);
        self.frame.dt = step_dt orelse clock_dt;
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        const fb: *const anyopaque = &self.frame;
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ fb, @as(usize, @sizeOf(Frame)), @as(usize, 0) });
        if (self.dir.stats) {
            if (!self.stats_live) self.stats = argus_stats.synthetic(self.frame.frame / 30 + 1);
            self.bindStats(enc);
        }
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
            if (self.step) |p| if (step_dt != null) {
                for (0..self.dir.steps) |_| {
                    mtl.msg(void, enc, "setTexture:atIndex:", .{ self.tex[self.cur], @as(usize, 0) });
                    mtl.msg(void, enc, "setTexture:atIndex:", .{ self.tex[self.cur ^ 1], @as(usize, 1) });
                    p.dispatch(enc, sw, sh);
                    self.cur ^= 1;
                }
            };
            mtl.msg(void, enc, "setTexture:atIndex:", .{ self.tex[self.cur], @as(usize, 1) });
        }
        if (self.frame.dt != clock_dt) {
            // The draw sees the frame interval (the bytes were copied at setBytes time).
            self.frame.dt = clock_dt;
            mtl.msg(void, enc, "setBytes:length:atIndex:", .{ fb, @as(usize, @sizeOf(Frame)), @as(usize, 0) });
        }
        mtl.msg(void, enc, "setTexture:atIndex:", .{ out, @as(usize, 0) });
        self.draw.dispatch(enc, self.frame.width, self.frame.height);
        mtl.msg(void, enc, "endEncoding", .{});
        self.frame.time = advanceClock(&self.clock, clock_dt);
    }

    /// ArgusStats as [[buffer(1)]] for every dispatch in `enc` (428 bytes, copied now).
    fn bindStats(self: *const Theme, enc: mtl.Id) void {
        const sb: *const anyopaque = &self.stats;
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ sb, @as(usize, @sizeOf(argus_stats.Stats)), argus_stats.BUFFER_INDEX });
    }

    /// Encodes only argus_draw for the current state, without advancing time or the state
    /// (used for menu previews).
    pub fn encodeDrawOnly(self: *Theme, cb: mtl.Id, out: mtl.Id) void {
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        const fb: *const anyopaque = &self.frame;
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ fb, @as(usize, @sizeOf(Frame)), @as(usize, 0) });
        if (self.dir.stats) self.bindStats(enc);
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

test "f.time keeps the frame step for 30 days" {
    // 30 days of 30 FPS frames. A float32 accumulator stops advancing at ~12 days.
    const dt: f32 = 1.0 / 30.0;
    const frames: u64 = 30 * 86400 * 30;
    var clock: f64 = 0;
    var prev: f32 = 0;
    var wraps: u32 = 0;
    var worst: f64 = 0;
    var i: u64 = 0;
    while (i < frames) : (i += 1) {
        const t = advanceClock(&clock, dt);
        var step: f64 = @as(f64, t) - @as(f64, prev);
        if (step < 0) {
            step += TIME_PERIOD;
            wraps += 1;
        }
        worst = @max(worst, @abs(step - @as(f64, dt)));
        prev = t;
    }
    // Every step is dt to within the float32 resolution near the period (~1 ms), never 0 or 2 dt.
    try std.testing.expect(worst < 1.0e-3);
    try std.testing.expectEqual(@as(u32, 30 * 86400 / 14400), wraps);
    const elapsed: f64 = @as(f64, @floatFromInt(frames)) * @as(f64, dt);
    try std.testing.expectApproxEqAbs(elapsed, clock, 1.0e-3);
    try std.testing.expect(prev >= 0 and prev < TIME_PERIOD);
}

test "loadData: the file must be exactly the declared size" {
    const io = std.testing.io;
    const alloc = std.testing.allocator;
    const src = "// @argus data argus_test_data.bin 2x1 rgba8\n";
    const theme = "/tmp/argus_test_theme.metal";
    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = "/tmp/argus_test_data.bin", .data = "12345678" });
    const ok = (try loadData(io, alloc, theme, src)).?;
    defer alloc.free(ok);
    try std.testing.expectEqualStrings("12345678", ok);
    try cwd.writeFile(io, .{ .sub_path = "/tmp/argus_test_data.bin", .data = "123456789" });
    try std.testing.expectError(error.MetalDataSize, loadData(io, alloc, theme, src));
    try cwd.writeFile(io, .{ .sub_path = "/tmp/argus_test_data.bin", .data = "1234567" });
    try std.testing.expectError(error.MetalDataSize, loadData(io, alloc, theme, src));
    try std.testing.expect((try loadData(io, alloc, theme, "kernel void argus_draw() {}")) == null);
}

test "@argus stats: the directive, the synthetic feed, and the layout the GPU sees" {
    try std.testing.expect(parseDirectives("// @argus stats\nkernel void argus_draw() {}").stats);
    try std.testing.expect(!parseDirectives("// @argus state 4x4\nkernel void argus_draw() {}").stats);

    // Each texel of a 16x1 output is one field read back from the ArgusStats the kernel sees.
    const src =
        \\// @argus stats
        \\kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]], constant ArgusStats& s [[buffer(1)]],
        \\                       texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        \\    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
        \\    const float v[16] = { float(s.seq), s.sample_dt, float(s.thermal), s.cpu_total, s.cpu_core[0],
        \\        s.cpu_core[31], s.mem_total_gb, float(s.mem_pressure), s.gpu_busy, s.battery_minutes,
        \\        s.net_tx_bps, s.disk_total_gb, float(s.proc_count), float(s.procs[4].name[0]),
        \\        s.procs[4].mem_gb, float(sizeof(ArgusStats)) };
        \\    out.write(float4(v[gid.x]), gid);
        \\}
    ;
    var err_buf: [2048]u8 = undefined;
    var t = Theme.compile(src, "stats_layout.metal", null, 16, 1, 1, &err_buf) catch |e| {
        std.debug.print("{s}\n", .{std.mem.sliceTo(&err_buf, 0)});
        return e;
    };
    defer t.deinit();
    try std.testing.expect(t.dir.stats);
    const out = mtl.newTexture(t.dev, mtl.PIXEL_RGBA32F, 16, 1, mtl.STORAGE_SHARED);
    defer mtl.release(out);
    const readBack = struct {
        fn f(th: *Theme, o: mtl.Id) ![16]f32 {
            const cb = mtl.msg(mtl.Id, th.queue, "commandBuffer", .{});
            th.encode(cb, o, 1.0 / 30.0);
            mtl.msg(void, cb, "commit", .{});
            mtl.msg(void, cb, "waitUntilCompleted", .{});
            var px: [16 * 4]f32 = undefined;
            mtl.msg(void, o, "getBytes:bytesPerRow:fromRegion:mipmapLevel:", .{
                @as(*anyopaque, @ptrCast(&px)), @as(usize, 16 * 16), mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = 16, .h = 1, .d = 1 }, @as(usize, 0),
            });
            var r: [16]f32 = undefined;
            for (&r, 0..) |*x, i| x.* = px[i * 4];
            return r;
        }
    }.f;

    // Synthetic (the harness): seq 1 on tick 0, 2 from tick 30.
    try std.testing.expectEqual(@as(f32, 1), (try readBack(&t, out))[0]);
    for (0..30) |_| _ = try readBack(&t, out);
    try std.testing.expectEqual(@as(f32, 2), (try readBack(&t, out))[0]);

    // Live (the app): exactly what was copied in.
    var s: argus_stats.Stats = .{ .seq = 7, .sample_dt = 1.25, .thermal = 2, .cpu_total = 0.5, .mem_total_gb = 8, .mem_pressure = 1, .gpu_busy = 0.75, .battery_minutes = 95, .net_tx_bps = 4096, .disk_total_gb = 494.5, .proc_count = 5 };
    s.cpu_core[0] = 0.25;
    s.cpu_core[31] = 0.125;
    s.procs[4].setName("Zed");
    s.procs[4].mem_gb = 1.5;
    t.stats = s;
    t.stats_live = true;
    const want = [16]f32{ 7, 1.25, 2, 0.5, 0.25, 0.125, 8, 1, 0.75, 95, 4096, 494.5, 5, 'Z', 1.5, @sizeOf(argus_stats.Stats) };
    try std.testing.expectEqualSlices(f32, &want, &(try readBack(&t, out)));
}

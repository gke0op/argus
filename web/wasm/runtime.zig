// ============================================================================
// web/wasm/runtime.zig — the browser host for Argus Zig themes, compiled to WebAssembly
//
// The root of a theme's wasm module. The theme file is imported as module "theme" exactly as
// make linux and make claims import it, so its exports (argus_theme_*) are the same code the
// harness dlopen-s. This file adds what a browser needs and a theme must not provide:
//   - std.heap.page_allocator for threaded wasm (wasm_heap.zig, through root.os.heap),
//   - frame buffers and a live step/draw entry for the page,
//   - the harness gate run (src/harness_gates.zig) on this module, for an in-page verdict,
//   - thread bootstrap for the page's helper Workers (own stack, own TLS block).
// Built twice by `make web-wasm`: theme.mt.wasm (+simd128 +atomics, shared memory, Workers)
// and theme.st.wasm (+simd128, one thread) for pages without cross-origin isolation.
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");
const theme = @import("theme");
const gates = @import("harness_gates");
const wasm_heap = @import("wasm_heap.zig");

comptime {
    _ = theme;
}

/// std.heap.page_allocator, for this module (see wasm_heap.zig).
pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = wasm_heap.allocator;
    };
};

const threaded = !builtin.single_threaded;
const host = wasm_heap.allocator;

// ---- The theme ABI ------------------------------------------------------------------------
// Taken by name, as the harness takes it with dlsym. The required ones are plain externs; the
// optional ones are weak, so a theme that lacks one (a hand-written fixture) still links and
// the pointer is null, as dlsym's would be.

extern fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque;
extern fn argus_theme_deinit(state: ?*anyopaque) callconv(.c) void;
extern fn argus_theme_step(state: ?*anyopaque, dt: f64) callconv(.c) void;
extern fn argus_theme_draw(state: ?*anyopaque, pixels: [*]u32, buf_len: usize, stride: usize) callconv(.c) void;

fn weak(comptime T: type, comptime name: []const u8) ?T {
    return @extern(?T, .{ .name = name, .linkage = .weak });
}

/// Which entry points the theme exports, as a bit set the page reads (stateful = 1, ...).
const has = struct {
    // A theme exports argus_render_theme or the stateful set (or both, as the SDK does).
    // Which ones: from the theme's declarations when it has them (SDK: State; kernel: draw),
    // else from the weak symbols.
    const sdk = @hasDecl(theme, "State");
    const kernel = @hasDecl(theme, "draw");
};

fn abi() gates.Abi {
    if (comptime (has.sdk or has.kernel)) {
        return .{
            .init = argus_theme_init,
            .deinit = argus_theme_deinit,
            .step = argus_theme_step,
            .draw = argus_theme_draw,
            .allocs_init = @extern(gates.FnCount, .{ .name = "argus_theme_allocs_init" }),
            .allocs_after = @extern(gates.FnCount, .{ .name = "argus_theme_allocs_after_init" }),
            .bytes_live = @extern(gates.FnCount, .{ .name = "argus_theme_bytes_live" }),
            .has_nan = @extern(gates.FnHasNaN, .{ .name = "argus_theme_has_nan" }),
            .stateless = if (has.sdk) @extern(gates.FnStateless, .{ .name = "argus_render_theme" }) else null,
        };
    }
    return .{
        .init = weak(gates.FnInit, "argus_theme_init"),
        .deinit = weak(gates.FnDeinit, "argus_theme_deinit"),
        .step = weak(gates.FnStep, "argus_theme_step"),
        .draw = weak(gates.FnDraw, "argus_theme_draw"),
        .allocs_init = weak(gates.FnCount, "argus_theme_allocs_init"),
        .allocs_after = weak(gates.FnCount, "argus_theme_allocs_after_init"),
        .bytes_live = weak(gates.FnCount, "argus_theme_bytes_live"),
        .has_nan = weak(gates.FnHasNaN, "argus_theme_has_nan"),
        .stateless = weak(gates.FnStateless, "argus_render_theme"),
    };
}

// ---- Imports from the page ----------------------------------------------------------------

extern "env" fn web_now_us() f64;
extern "env" fn web_phase(p: u32) void;

// ---- Host memory --------------------------------------------------------------------------

export fn web_alloc(bytes: usize) usize {
    const m = host.alignedAlloc(u8, .fromByteUnits(16), bytes) catch return 0;
    return @intFromPtr(m.ptr);
}

export fn web_free(ptr: usize, bytes: usize) void {
    if (ptr == 0) return;
    const p: [*]align(16) u8 = @ptrFromInt(ptr);
    host.free(p[0..bytes]);
}

export fn web_pages_grown() usize {
    return wasm_heap.pages_grown;
}

/// 1 when built with threads (theme.mt.wasm), 0 for theme.st.wasm.
export fn web_threaded() u32 {
    return @intFromBool(threaded);
}

/// SIMD lanes per kernel call (themes/cpu/argus_kernel.zig N), 0 for non-kernel themes.
export fn web_lanes() u32 {
    if (!has.kernel) return 0;
    // draw(frame, gid): gid.x is one u32 per lane.
    const Gid = @typeInfo(@TypeOf(theme.draw)).@"fn".param_types[1].?;
    return @typeInfo(@FieldType(Gid, "x")).vector.len;
}

/// Bit set: 1 stateful ABI, 2 stateless ABI, 4 SDK theme, 8 CPU kernel theme.
export fn web_abi() u32 {
    const a = abi();
    var bits: u32 = 0;
    if (a.isStateful()) bits |= 1;
    if (a.stateless != null) bits |= 2;
    if (has.sdk) bits |= 4;
    if (has.kernel) bits |= 8;
    return bits;
}

// ---- Helper Workers -----------------------------------------------------------------------
// Each Worker instantiates this module on the same shared memory. Its globals start as the
// first instance's did, so before anything else it moves its stack pointer onto a stack of its
// own (the leader allocates it with web_alloc) and initialises a TLS block, as std.Thread's
// wasi_thread_start does for wasi threads.

export fn web_tls_size() usize {
    if (comptime !threaded) return 0;
    return asm volatile (
        \\ .globaltype __tls_size, i32, immutable
        \\ global.get __tls_size
        \\ local.set %[ret]
        : [ret] "=r" (-> usize),
    );
}

export fn web_tls_align() usize {
    if (comptime !threaded) return 1;
    return asm volatile (
        \\ .globaltype __tls_align, i32, immutable
        \\ global.get __tls_align
        \\ local.set %[ret]
        : [ret] "=r" (-> usize),
    );
}

extern fn __wasm_init_tls(memory: [*]u8) void;

/// Called first by a helper Worker: switch to `stack_top` and its own TLS block.
export fn web_thread_init(stack_top: usize, tls: usize) void {
    if (comptime !threaded) return;
    asm volatile (
        \\ .globaltype __stack_pointer, i32
        \\ local.get %[sp]
        \\ global.set __stack_pointer
        :
        : [sp] "r" (stack_top),
    );
    if (tls != 0) __wasm_init_tls(@ptrFromInt(tls));
}

// ---- Live rendering -----------------------------------------------------------------------

const Live = struct {
    state: ?*anyopaque = null,
    w: u32 = 0,
    h: u32 = 0,
    pixels: []u32 = &.{},
    phase: f64 = 0,
    steps: u64 = 0,
};
var live: Live = .{};

/// (Re)start the theme at w x h and give it a frame buffer. Returns the buffer's address, or
/// 0 if the theme refused that size.
export fn web_live_init(w: u32, h: u32, scale: f64) usize {
    web_live_deinit();
    const a = abi();
    const px = host.alloc(u32, @as(usize, w) * h) catch return 0;
    @memset(px, 0xFF00_0000);
    live = .{ .w = w, .h = h, .pixels = px };
    if (a.isStateful()) {
        live.state = a.init.?(w, h, scale) orelse {
            web_live_deinit();
            return 0;
        };
    }
    return @intFromPtr(px.ptr);
}

export fn web_live_deinit() void {
    if (live.state) |s| abi().deinit.?(s);
    if (live.pixels.len != 0) host.free(live.pixels);
    live = .{};
}

/// One display frame: advance by `sdk_dt` (0.008 per 30 Hz tick, so the page passes its real
/// frame interval x 0.24) and draw into the frame buffer.
export fn web_live_frame(sdk_dt: f64) void {
    const a = abi();
    if (live.pixels.len == 0) return;
    if (live.state) |s| {
        if (sdk_dt > 0) a.step.?(s, sdk_dt);
        a.draw.?(s, live.pixels.ptr, live.pixels.len, live.w);
    } else if (a.stateless) |render| {
        // argus_render_theme: phase 1/150 per 30 Hz tick (desktop/frame_rate.zig).
        live.phase += sdk_dt / gates.DT / 150.0;
        live.steps += 1;
        render(live.pixels.ptr, live.w, live.h, live.phase, live.steps);
    }
}

/// Step only (for a page that skips draws), and draw only.
export fn web_live_step(sdk_dt: f64) void {
    if (live.state) |s| abi().step.?(s, sdk_dt);
}

export fn web_live_draw() void {
    if (live.state) |s| abi().draw.?(s, live.pixels.ptr, live.pixels.len, live.w);
}

export fn web_live_has_nan() u32 {
    const s = live.state orelse return 0;
    const f = abi().has_nan orelse return 0;
    return @intFromBool(f(s));
}

// ---- The harness gates --------------------------------------------------------------------

/// The gate run's result, laid out for the page to read (web/wasm/gates.js).
pub const GateReport = extern struct {
    status: u32 = 0, // 0 ok, 1 no ABI, 2 init returned null, 3 out of memory
    stateful: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    padded_stride: u32 = 0,
    n_frames: u32 = 0,
    watchdog_ok: u32 = 0,
    allocs_init: u32 = 0,
    bytes_live: u32 = 0,
    allocs_after: u32 = 0,
    nan_detected: u32 = 0,
    canary_corrupted: u32 = 0,
    distinct_pixels: u32 = 0,
    bad_alpha_pixels: u32 = 0,
    animated_pixels: u32 = 0,
    alloc_ok: u32 = 0,
    pixels_ok: u32 = 0,
    motion_ok: u32 = 0,
    budget_ok: u32 = 0,
    pass: u32 = 0,
    final_ptr: u32 = 0,
    _pad: u32 = 0,
    avg_us: f64 = 0,
    worst_us: f64 = 0,
};
var report: GateReport = .{};
var final_buf: []u32 = &.{};

fn nowNs(_: ?*anyopaque) u64 {
    return @intFromFloat(@max(0.0, web_now_us() * 1000.0));
}
fn phase(_: ?*anyopaque, p: gates.Phase) void {
    web_phase(@backingInt(p));
}

/// Run the harness's gates (2-8) on this theme at width x height for n_frames, as
/// `make harness` does on the dylib. Returns the report's address.
export fn web_gates_run(width: u32, height: u32, n_frames: u32) *const GateReport {
    report = .{};
    if (final_buf.len != 0) host.free(final_buf);
    final_buf = host.alloc(u32, @as(usize, width) * height) catch {
        report.status = 3;
        return &report;
    };
    const r = gates.run(host, abi(), .{ .width = width, .height = height, .n_frames = n_frames }, .{ .now_ns = nowNs, .phase = phase }, final_buf) catch |e| {
        report.status = switch (e) {
            error.NoThemeAbi => 1,
            error.InitReturnedNull => 2,
            error.OutOfMemory => 3,
        };
        return &report;
    };
    report = .{
        .stateful = @intFromBool(r.stateful),
        .width = @intCast(r.width),
        .height = @intCast(r.height),
        .padded_stride = @intCast(r.padded_stride),
        .n_frames = @intCast(r.n_frames),
        .watchdog_ok = @intFromBool(r.watchdog_ok),
        .allocs_init = @intCast(r.allocs_init),
        .bytes_live = @intCast(r.bytes_live),
        .allocs_after = @intCast(r.allocs_after),
        .nan_detected = @intFromBool(r.nan_detected),
        .canary_corrupted = @intFromBool(r.canary_corrupted),
        .distinct_pixels = @intCast(r.distinct_pixels),
        .bad_alpha_pixels = @intCast(r.bad_alpha_pixels),
        .animated_pixels = @intCast(r.animated_pixels),
        .alloc_ok = @intFromBool(r.allocOk()),
        .pixels_ok = @intFromBool(r.pixelsOk()),
        .motion_ok = @intFromBool(r.motionOk()),
        .budget_ok = @intFromBool(r.budgetOk()),
        .pass = @intFromBool(r.pass(true)),
        .final_ptr = @intCast(@intFromPtr(final_buf.ptr)),
        .avg_us = r.avgUs(),
        .worst_us = r.worstUs(),
    };
    return &report;
}

/// Render `frames` frames headless (step 0.008 + draw, as the harness's main loop does) into a
/// tight w x h buffer and return its address: the page compares it with the native harness PNG.
export fn web_render_frames(w: u32, h: u32, frames: u32) usize {
    const a = abi();
    if (final_buf.len != 0) host.free(final_buf);
    final_buf = host.alloc(u32, @as(usize, w) * h) catch return 0;
    @memset(final_buf, 0);
    if (a.isStateful()) {
        const s = a.init.?(w, h, if (w >= 1920) 2.0 else 1.0) orelse return 0;
        defer a.deinit.?(s);
        for (0..frames) |_| {
            a.step.?(s, gates.DT);
            a.draw.?(s, final_buf.ptr, final_buf.len, w);
        }
    } else if (a.stateless) |render| {
        for (0..frames) |f| render(final_buf.ptr, w, h, @as(f64, @floatFromInt(f)) * gates.DT, f);
    }
    return @intFromPtr(final_buf.ptr);
}

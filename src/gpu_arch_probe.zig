// ============================================================================
// ARGUS GPU // src/gpu_arch_probe.zig
//
// Architecture probes: how Argus drives the Apple GPU, rather than what a theme
// computes. Each experiment isolates one structural choice of the engine:
//   clocks   - GPU time of the same frame back-to-back vs paced at 30 and 10 FPS
//   write    - writing a full frame from a compute kernel (what Argus does) vs a
//              fragment shader into a render target, and what reading it back costs
//   cpu      - CPU time to encode and commit one frame
//   memory   - state reads by texture format, texture vs buffer, threadgroup memory
//
//   make gpu-arch            (all)      make gpu-arch ARCH=clocks
// ============================================================================

const std = @import("std");
const mtl = @import("gpu/metal.zig");

const W: usize = 1920;
const H: usize = 1200;
const USAGE_READ: usize = 1;
const USAGE_WRITE: usize = 2;
const USAGE_RT: usize = 4;

const MSL =
    \\#include <metal_stdlib>
    \\using namespace metal;
    \\struct P { float time; uint w; uint h; uint iters; };
    \\
    \\static inline float hash21(float2 p) { p = fract(p * float2(123.34f, 456.21f)); p += dot(p, p + 45.32f); return fract(p.x * p.y); }
    \\static inline float vnoise(float2 p) {
    \\    float2 i = floor(p), f = fract(p), u = f * f * (3.0f - 2.0f * f);
    \\    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x), mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
    \\}
    \\// A Tides-like shade: domain-warped fbm plus a palette (~0.6 ms per 1920x1200 frame on an M3).
    \\static float4 shade(float2 px, constant P& p) {
    \\    float2 uv = (px - 0.5f * float2(p.w, p.h)) / float(p.h);
    \\    float2 q = uv * 3.0f;
    \\    float a = 0.0f, amp = 0.5f;
    \\    for (uint o = 0; o < p.iters; o++) { a += amp * vnoise(q + p.time * 0.1f + a); q = float2x2(1.6f, 1.2f, -1.2f, 1.6f) * q; amp *= 0.5f; }
    \\    float3 c = 0.5f + 0.5f * cos(6.2831f * (a + float3(0.0f, 0.33f, 0.67f)) + p.time * 0.2f);
    \\    return float4(c, 1.0f);
    \\}
    \\kernel void k_shade(constant P& p [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    \\    if (gid.x >= p.w || gid.y >= p.h) return;
    \\    out.write(shade(float2(gid) + 0.5f, p), gid);
    \\}
    \\struct VOut { float4 pos [[position]]; };
    \\vertex VOut v_full(uint vid [[vertex_id]]) {
    \\    float2 xy = float2((vid << 1) & 2, vid & 2);
    \\    VOut o; o.pos = float4(xy * 2.0f - 1.0f, 0.0f, 1.0f); return o;
    \\}
    \\fragment float4 f_shade(VOut in [[stage_in]], constant P& p [[buffer(0)]]) { return shade(in.pos.xy, p); }
    \\
    \\// memory: 9 neighbouring reads of a state per pixel (a 3x3 blur), from a texture or a buffer.
    \\kernel void k_read_tex(constant P& p [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], texture2d<float> st [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    \\    if (gid.x >= p.w || gid.y >= p.h) return;
    \\    float4 s = 0.0f;
    \\    for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++)
    \\        s += st.read(uint2(clamp(int2(gid) + int2(dx, dy), int2(0), int2(p.w - 1, p.h - 1))));
    \\    out.write(s / 9.0f, gid);
    \\}
    \\kernel void k_read_buf(constant P& p [[buffer(0)]], device const half4* st [[buffer(1)]], texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    \\    if (gid.x >= p.w || gid.y >= p.h) return;
    \\    float4 s = 0.0f;
    \\    for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
    \\        int2 c = clamp(int2(gid) + int2(dx, dy), int2(0), int2(p.w - 1, p.h - 1));
    \\        s += float4(st[c.y * int(p.w) + c.x]);
    \\    }
    \\    out.write(s / 9.0f, gid);
    \\}
    \\// memory: the same 3x3 blur, with each 32x32 threadgroup staging its 34x34 tile in threadgroup memory.
    \\kernel void k_read_tg(constant P& p [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], texture2d<float> st [[texture(1)]],
    \\                      uint2 gid [[thread_position_in_grid]], uint2 tpos [[thread_position_in_threadgroup]], uint2 tsz [[threads_per_threadgroup]]) {
    \\    threadgroup float4 tile[34 * 34];
    \\    const int2 org = int2(gid) - int2(tpos) - 1;
    \\    for (uint i = tpos.y * tsz.x + tpos.x; i < 34u * 34u; i += tsz.x * tsz.y) {
    \\        int2 c = clamp(org + int2(i % 34u, i / 34u), int2(0), int2(p.w - 1, p.h - 1));
    \\        tile[i] = st.read(uint2(c));
    \\    }
    \\    threadgroup_barrier(mem_flags::mem_threadgroup);
    \\    if (gid.x >= p.w || gid.y >= p.h) return;
    \\    float4 s = 0.0f;
    \\    for (int dy = 0; dy < 3; dy++) for (int dx = 0; dx < 3; dx++) s += tile[(tpos.y + dy) * 34 + tpos.x + dx];
    \\    out.write(s / 9.0f, gid);
    \\}
    \\// occupancy: a latency-bound chain of dependent texture reads, with N bytes of threadgroup memory reserved.
    \\#define OCC(NAME, BYTES) \
    \\kernel void NAME(constant P& p [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], texture2d<float> st [[texture(1)]], \
    \\                 uint2 gid [[thread_position_in_grid]], uint li [[thread_index_in_threadgroup]]) { \
    \\    threadgroup float pad[BYTES / 4]; pad[li % (BYTES / 4)] = float(li); threadgroup_barrier(mem_flags::mem_threadgroup); \
    \\    if (gid.x >= p.w || gid.y >= p.h) return; \
    \\    uint2 c = gid; float s = pad[(li + 1) % (BYTES / 4)] * 1e-9f; \
    \\    for (uint i = 0; i < 16; i++) { float4 v = st.read(c); s += v.x; c = uint2(uint(v.y * float(p.w - 1)), uint(v.z * float(p.h - 1))); } \
    \\    out.write(float4(s, 0, 0, 1), gid); \
    \\}
    \\OCC(k_occ_256, 256)
    \\OCC(k_occ_4k, 4096)
    \\OCC(k_occ_16k, 16384)
    \\OCC(k_occ_28k, 28672)
;

var queue: mtl.Id = null;
var dev: mtl.Id = null;
var lib: mtl.Id = null;

const P = extern struct { time: f32, w: u32, h: u32, iters: u32 };

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.UPTIME_RAW, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

fn sleepNs(ns: u64) void {
    const ts: std.c.timespec = .{ .sec = @intCast(ns / 1_000_000_000), .nsec = @intCast(ns % 1_000_000_000) };
    _ = std.c.nanosleep(&ts, null);
}

fn tex(format: usize, w: usize, h: usize, usage: usize, storage: usize) mtl.Id {
    const d = mtl.msg(mtl.Id, mtl.cls("MTLTextureDescriptor"), "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", .{ format, w, h, false });
    mtl.msg(void, d, "setUsage:", .{usage});
    mtl.msg(void, d, "setStorageMode:", .{storage});
    return mtl.msg(mtl.Id, dev, "newTextureWithDescriptor:", .{d});
}

fn pipe(name: [*:0]const u8) mtl.Id {
    const f = mtl.msg(mtl.Id, lib, "newFunctionWithName:", .{mtl.nsString(name)}) orelse @panic("no function");
    var err: mtl.Id = null;
    return mtl.msg(mtl.Id, dev, "newComputePipelineStateWithFunction:error:", .{ f, &err }) orelse @panic("pipeline");
}

fn gpuUs(cb: mtl.Id) f64 {
    return (mtl.msg(f64, cb, "GPUEndTime", .{}) - mtl.msg(f64, cb, "GPUStartTime", .{})) * 1e6;
}

fn median(xs: []f64) f64 {
    std.mem.sort(f64, xs, {}, std.sort.asc(f64));
    return xs[xs.len / 2];
}

/// Threadgroup shape for compute dispatches; the engine uses 32 x (max/32) = 32x32.
var group_w: usize = 32;
var group_h: usize = 32;

/// One compute dispatch over the frame.
fn dispatch(enc: mtl.Id, pso: mtl.Id, w: usize, h: usize) void {
    const tmax = mtl.msg(usize, pso, "maxTotalThreadsPerThreadgroup", .{});
    mtl.msg(void, enc, "setComputePipelineState:", .{pso});
    mtl.msg(void, enc, "dispatchThreads:threadsPerThreadgroup:", .{ mtl.MTLSize{ .w = w, .h = h, .d = 1 }, mtl.MTLSize{ .w = group_w, .h = @min(group_h, tmax / group_w), .d = 1 } });
}

fn probeGroups() void {
    std.debug.print("\n[groups] the same compute shade with different threadgroup shapes, median GPU us\n", .{});
    const out = tex(mtl.PIXEL_BGRA8, W, H, USAGE_READ | USAGE_WRITE, mtl.STORAGE_PRIVATE);
    defer mtl.release(out);
    const k = pipe("k_shade");
    const shapes = [_][2]usize{ .{ 32, 32 }, .{ 32, 16 }, .{ 32, 8 }, .{ 32, 4 }, .{ 32, 1 }, .{ 16, 16 }, .{ 8, 8 }, .{ 8, 4 }, .{ 4, 4 }, .{ 64, 4 }, .{ 256, 1 } };
    var fwd: [shapes.len]f64 = undefined;
    for (shapes, 0..) |sh, i| {
        group_w = sh[0];
        group_h = sh[1];
        fwd[i] = runCompute(.{ .pso = k, .out = out }, 120);
    }
    var i: usize = shapes.len;
    while (i > 0) {
        i -= 1;
        group_w = shapes[i][0];
        group_h = shapes[i][1];
        const back = runCompute(.{ .pso = k, .out = out }, 120);
        std.debug.print("  {d:>3}x{d:<3}: {d:6.0} / {d:6.0} (forward / reverse order)\n", .{ shapes[i][0], shapes[i][1], fwd[i], back });
    }
    group_w = 32;
    group_h = 32;
}

const Enc = struct { pso: mtl.Id, out: mtl.Id, st: mtl.Id = null, buf: mtl.Id = null };

/// Runs one compute frame and returns its GPU time in microseconds.
fn computeFrame(e: Enc, p: *P) f64 {
    const pool = mtl.poolPush();
    defer mtl.poolPop(pool);
    const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
    const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
    mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, p), @as(usize, @sizeOf(P)), @as(usize, 0) });
    mtl.msg(void, enc, "setTexture:atIndex:", .{ e.out, @as(usize, 0) });
    if (e.st != null) mtl.msg(void, enc, "setTexture:atIndex:", .{ e.st, @as(usize, 1) });
    if (e.buf != null) mtl.msg(void, enc, "setBuffer:offset:atIndex:", .{ e.buf, @as(usize, 0), @as(usize, 1) });
    dispatch(enc, e.pso, W, H);
    mtl.msg(void, enc, "endEncoding", .{});
    mtl.msg(void, cb, "commit", .{});
    mtl.msg(void, cb, "waitUntilCompleted", .{});
    p.time += 1.0 / 30.0;
    return gpuUs(cb);
}

/// ~0.5 s of back-to-back frames, so the GPU clock has ramped up before a measurement.
fn warm(e: Enc) void {
    var p: P = .{ .time = 0, .w = W, .h = H, .iters = 6 };
    const t0 = nowNs();
    while (nowNs() - t0 < 500_000_000) _ = computeFrame(e, &p);
}

fn runCompute(e: Enc, frames: usize) f64 {
    var p: P = .{ .time = 0, .w = W, .h = H, .iters = 6 };
    var t: [256]f64 = undefined;
    warm(e);
    for (t[0..frames]) |*v| v.* = computeFrame(e, &p);
    return median(t[0..frames]);
}

// ---------------------------------------------------------------------------- clocks
fn probeClocks() void {
    std.debug.print("\n[clocks] the same frame (Tides-like shade, 1920x1200) at different pacing; median GPU time\n", .{});
    const out = tex(mtl.PIXEL_BGRA8, W, H, USAGE_READ | USAGE_WRITE, mtl.STORAGE_PRIVATE);
    defer mtl.release(out);
    const e: Enc = .{ .pso = pipe("k_shade"), .out = out };
    const pacings = [_]struct { name: []const u8, gap_ns: u64, n: usize }{
        .{ .name = "back-to-back (benchmark/harness)", .gap_ns = 0, .n = 120 },
        .{ .name = "paced 30 FPS (visible Space)    ", .gap_ns = 33_333_333, .n = 90 },
        .{ .name = "paced 10 FPS (warm neighbour)   ", .gap_ns = 100_000_000, .n = 40 },
        .{ .name = "back-to-back again              ", .gap_ns = 0, .n = 120 },
    };
    for (pacings) |pc| {
        var p: P = .{ .time = 0, .w = W, .h = H, .iters = 6 };
        var t: [256]f64 = undefined;
        var wall: [256]f64 = undefined;
        for (0..pc.n) |i| {
            const t0 = nowNs();
            t[i] = computeFrame(e, &p);
            wall[i] = @as(f64, @floatFromInt(nowNs() - t0)) / 1000.0;
            if (pc.gap_ns > 0) sleepNs(pc.gap_ns -| (nowNs() - t0));
        }
        std.debug.print("  {s}: GPU {d:7.0} us   submit-to-done wall {d:7.0} us\n", .{ pc.name, median(t[0..pc.n]), median(wall[0..pc.n]) });
    }
}

// ---------------------------------------------------------------------------- write path
fn renderFrame(rps: mtl.Id, target: mtl.Id, p: *P) f64 {
    const pool = mtl.poolPush();
    defer mtl.poolPop(pool);
    const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
    const rpd = mtl.msg(mtl.Id, mtl.cls("MTLRenderPassDescriptor"), "renderPassDescriptor", .{});
    const ca = mtl.msg(mtl.Id, mtl.msg(mtl.Id, rpd, "colorAttachments", .{}), "objectAtIndexedSubscript:", .{@as(usize, 0)});
    mtl.msg(void, ca, "setTexture:", .{target});
    mtl.msg(void, ca, "setLoadAction:", .{@as(usize, 0)}); // dontCare: every pixel is written
    mtl.msg(void, ca, "setStoreAction:", .{@as(usize, 1)}); // store
    const enc = mtl.msg(mtl.Id, cb, "renderCommandEncoderWithDescriptor:", .{rpd});
    mtl.msg(void, enc, "setRenderPipelineState:", .{rps});
    mtl.msg(void, enc, "setFragmentBytes:length:atIndex:", .{ @as(*const anyopaque, p), @as(usize, @sizeOf(P)), @as(usize, 0) });
    mtl.msg(void, enc, "drawPrimitives:vertexStart:vertexCount:", .{ @as(usize, 3), @as(usize, 0), @as(usize, 3) });
    mtl.msg(void, enc, "endEncoding", .{});
    mtl.msg(void, cb, "commit", .{});
    mtl.msg(void, cb, "waitUntilCompleted", .{});
    p.time += 1.0 / 30.0;
    return gpuUs(cb);
}

/// GPU time to copy `src` into a same-format texture: a stand-in for the compositor reading the frame.
fn readBack(src: mtl.Id) f64 {
    const dst = tex(mtl.PIXEL_BGRA8, W, H, USAGE_READ, mtl.STORAGE_PRIVATE);
    defer mtl.release(dst);
    var t: [40]f64 = undefined;
    for (&t) |*v| {
        const pool = mtl.poolPush();
        defer mtl.poolPop(pool);
        const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
        const b = mtl.msg(mtl.Id, cb, "blitCommandEncoder", .{});
        mtl.msg(void, b, "copyFromTexture:toTexture:", .{ src, dst });
        mtl.msg(void, b, "endEncoding", .{});
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        v.* = gpuUs(cb);
    }
    return median(&t);
}

fn probeWrite() void {
    std.debug.print("\n[write] one full frame (Tides-like shade) into BGRA8 1920x1200, median GPU us; then a copy of it (as the compositor reads it)\n", .{});
    // Render pipeline: full-screen triangle, the same shade in the fragment stage.
    const rpd = mtl.msg(mtl.Id, mtl.msg(mtl.Id, mtl.cls("MTLRenderPipelineDescriptor"), "alloc", .{}), "init", .{});
    mtl.msg(void, rpd, "setVertexFunction:", .{mtl.msg(mtl.Id, lib, "newFunctionWithName:", .{mtl.nsString("v_full")})});
    mtl.msg(void, rpd, "setFragmentFunction:", .{mtl.msg(mtl.Id, lib, "newFunctionWithName:", .{mtl.nsString("f_shade")})});
    const ca = mtl.msg(mtl.Id, mtl.msg(mtl.Id, rpd, "colorAttachments", .{}), "objectAtIndexedSubscript:", .{@as(usize, 0)});
    mtl.msg(void, ca, "setPixelFormat:", .{mtl.PIXEL_BGRA8});
    var err: mtl.Id = null;
    const rps = mtl.msg(mtl.Id, dev, "newRenderPipelineStateWithDescriptor:error:", .{ rpd, &err }) orelse {
        std.debug.print("  render pipeline failed: {s}\n", .{mtl.describe(err)});
        return;
    };
    const k = pipe("k_shade");
    const cases = [_]struct { name: []const u8, usage: usize, render: bool }{
        .{ .name = "compute -> texture (ShaderWrite|Read), like Argus ", .usage = USAGE_READ | USAGE_WRITE, .render = false },
        .{ .name = "fragment -> render target (RenderTarget only)    ", .usage = USAGE_RT, .render = true },
        .{ .name = "fragment -> render target (RenderTarget|Read)    ", .usage = USAGE_RT | USAGE_READ, .render = true },
        .{ .name = "fragment -> RT that also allows ShaderWrite      ", .usage = USAGE_RT | USAGE_READ | USAGE_WRITE, .render = true },
        .{ .name = "compute -> texture again (order check)           ", .usage = USAGE_READ | USAGE_WRITE, .render = false },
    };
    for (cases) |c| {
        const out = tex(mtl.PIXEL_BGRA8, W, H, c.usage, mtl.STORAGE_PRIVATE);
        defer mtl.release(out);
        var p: P = .{ .time = 0, .w = W, .h = H, .iters = 6 };
        var t: [120]f64 = undefined;
        warm(.{ .pso = k, .out = out });
        for (0..60) |_| _ = if (c.render) renderFrame(rps, out, &p) else computeFrame(.{ .pso = k, .out = out }, &p);
        for (&t) |*v| v.* = if (c.render) renderFrame(rps, out, &p) else computeFrame(.{ .pso = k, .out = out }, &p);
        // Cheap fill (iters = 0) isolates the cost of writing the pixels.
        var p0: P = .{ .time = 0, .w = W, .h = H, .iters = 0 };
        var t0: [120]f64 = undefined;
        for (&t0) |*v| v.* = if (c.render) renderFrame(rps, out, &p0) else computeFrame(.{ .pso = k, .out = out }, &p0);
        const rb = if ((c.usage & USAGE_READ) != 0) readBack(out) else -1.0;
        std.debug.print("  {s}: shade {d:6.0}  fill-only {d:5.0}  copy-out {d:5.0}\n", .{ c.name, median(&t), median(&t0), rb });
    }
}

// ---------------------------------------------------------------------------- CPU
fn probeCpu() void {
    std.debug.print("\n[cpu] CPU time per frame on the submitting thread (median of 600), the engine's pattern: 1 command buffer, 1 compute encoder, setBytes + 2 textures + 1 dispatch\n", .{});
    const out = tex(mtl.PIXEL_BGRA8, W, H, USAGE_READ | USAGE_WRITE, mtl.STORAGE_PRIVATE);
    defer mtl.release(out);
    const k = pipe("k_shade");
    var p: P = .{ .time = 0, .w = W, .h = H, .iters = 0 };
    var enc_t: [600]f64 = undefined;
    var commit_t: [600]f64 = undefined;
    var pool_t: [600]f64 = undefined;
    for (0..600) |i| {
        const a = nowNs();
        const pool = mtl.poolPush();
        const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
        const enc = mtl.msg(mtl.Id, cb, "computeCommandEncoder", .{});
        mtl.msg(void, enc, "setBytes:length:atIndex:", .{ @as(*const anyopaque, &p), @as(usize, @sizeOf(P)), @as(usize, 0) });
        mtl.msg(void, enc, "setTexture:atIndex:", .{ out, @as(usize, 0) });
        mtl.msg(void, enc, "setTexture:atIndex:", .{ out, @as(usize, 1) });
        dispatch(enc, k, W, H);
        mtl.msg(void, enc, "endEncoding", .{});
        const b = nowNs();
        mtl.msg(void, cb, "commit", .{});
        const c = nowNs();
        mtl.msg(void, cb, "waitUntilCompleted", .{});
        const d = nowNs();
        mtl.poolPop(pool);
        const e = nowNs();
        enc_t[i] = @as(f64, @floatFromInt(b - a)) / 1000.0;
        commit_t[i] = @as(f64, @floatFromInt(c - b)) / 1000.0;
        pool_t[i] = @as(f64, @floatFromInt(e - d)) / 1000.0;
    }
    std.debug.print("  encode {d:.1} us   commit {d:.1} us   autorelease pop {d:.1} us\n", .{ median(&enc_t), median(&commit_t), median(&pool_t) });
}

// ---------------------------------------------------------------------------- memory
fn probeMemory() void {
    std.debug.print("\n[memory] 3x3 neighbourhood reads of a 1920x1200 state per pixel, median GPU us\n", .{});
    const out = tex(mtl.PIXEL_BGRA8, W, H, USAGE_READ | USAGE_WRITE, mtl.STORAGE_PRIVATE);
    defer mtl.release(out);
    const fmts = [_]struct { name: []const u8, f: usize }{
        .{ .name = "texture RGBA8   ", .f = mtl.PIXEL_RGBA8 },
        .{ .name = "texture RGBA16F ", .f = mtl.PIXEL_RGBA16F },
        .{ .name = "texture RGBA32F ", .f = mtl.PIXEL_RGBA32F },
    };
    const kt = pipe("k_read_tex");
    const ktg = pipe("k_read_tg");
    for (fmts) |fm| {
        const st = tex(fm.f, W, H, USAGE_READ | USAGE_WRITE, mtl.STORAGE_PRIVATE);
        defer mtl.release(st);
        std.debug.print("  {s}: direct {d:5.0}   staged in threadgroup memory {d:5.0}\n", .{ fm.name, runCompute(.{ .pso = kt, .out = out, .st = st }, 120), runCompute(.{ .pso = ktg, .out = out, .st = st }, 120) });
    }
    const buf = mtl.msg(mtl.Id, dev, "newBufferWithLength:options:", .{ W * H * 8, @as(usize, 2 << 4) }); // private storage
    defer mtl.release(buf);
    std.debug.print("  buffer half4    : direct {d:5.0}\n", .{runCompute(.{ .pso = pipe("k_read_buf"), .out = out, .buf = buf }, 120)});

    std.debug.print("\n[occupancy] 16 dependent random reads per pixel (latency-bound), with threadgroup memory reserved per 1024-thread group\n", .{});
    // A random-pointer state so every read depends on the previous one.
    const st = tex(mtl.PIXEL_RGBA16F, W, H, USAGE_READ | USAGE_WRITE, mtl.STORAGE_PRIVATE);
    defer mtl.release(st);
    {
        const n = W * H;
        const host = std.heap.page_allocator.alloc(u16, n * 4) catch return;
        defer std.heap.page_allocator.free(host);
        var rng = std.Random.DefaultPrng.init(7);
        const r = rng.random();
        for (0..n) |i| {
            host[i * 4 + 0] = @bitCast(@as(f16, 0.001));
            host[i * 4 + 1] = @bitCast(@as(f16, @floatCast(r.float(f32))));
            host[i * 4 + 2] = @bitCast(@as(f16, @floatCast(r.float(f32))));
            host[i * 4 + 3] = 0;
        }
        const staging = tex(mtl.PIXEL_RGBA16F, W, H, USAGE_READ, mtl.STORAGE_SHARED);
        defer mtl.release(staging);
        mtl.msg(void, staging, "replaceRegion:mipmapLevel:withBytes:bytesPerRow:", .{ mtl.MTLRegion{ .x = 0, .y = 0, .z = 0, .w = W, .h = H, .d = 1 }, @as(usize, 0), @as(*const anyopaque, host.ptr), W * 8 });
        const cb = mtl.msg(mtl.Id, queue, "commandBuffer", .{});
        const b = mtl.msg(mtl.Id, cb, "blitCommandEncoder", .{});
        mtl.msg(void, b, "copyFromTexture:toTexture:", .{ staging, st });
        mtl.msg(void, b, "endEncoding", .{});
        mtl.msg(void, cb, "commit", .{});
        mtl.msg(void, cb, "waitUntilCompleted", .{});
    }
    for ([_][*:0]const u8{ "k_occ_256", "k_occ_4k", "k_occ_16k", "k_occ_28k" }) |name| {
        const pso = pipe(name);
        std.debug.print("  {s:<10}: {d:6.0} us  (max threads/group {d})\n", .{ name, runCompute(.{ .pso = pso, .out = out, .st = st }, 60), mtl.msg(usize, pso, "maxTotalThreadsPerThreadgroup", .{}) });
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const which: []const u8 = if (args.len > 1) args[1] else "all";
    dev = try mtl.device();
    queue = mtl.msg(mtl.Id, dev, "newCommandQueue", .{});
    var err: mtl.Id = null;
    lib = mtl.msg(mtl.Id, dev, "newLibraryWithSource:options:error:", .{ mtl.nsString(MSL), @as(mtl.Id, null), &err }) orelse {
        std.debug.print("compile failed: {s}\n", .{mtl.describe(err)});
        return error.Compile;
    };
    const name = mtl.msg(mtl.Id, dev, "name", .{});
    std.debug.print("GPU architecture probes on {s}\n", .{mtl.msg(?[*:0]const u8, name, "UTF8String", .{}) orelse "?"});
    const all = std.mem.eql(u8, which, "all");
    if (all or std.mem.eql(u8, which, "clocks")) probeClocks();
    if (all or std.mem.eql(u8, which, "write")) probeWrite();
    if (all or std.mem.eql(u8, which, "groups")) probeGroups();
    if (all or std.mem.eql(u8, which, "cpu")) probeCpu();
    if (all or std.mem.eql(u8, which, "memory")) probeMemory();
}

// ============================================================================
// ARGUS CPU KERNELS // themes/cpu/argus_kernel.zig
//
// Runs Argus Metal kernels on the CPU the way a GPU runs them: SPMD. One call of a kernel
// shades N neighbouring pixels at once, one per SIMD lane (N = 16 with AVX-512, 8 with AVX2,
// 4 with SSE/NEON); rows are shared out to every core. A port is an ordinary Zig theme: the
// harness, the Mac app and argus-linux load it unchanged. Pure Zig 0.17, no libc.
//
// Porting a Metal kernel:
//   float        -> F (one value per lane)        f(0.5) splats a constant
//   float2/3     -> V2 / V3 (one F per component) v2(...), v3(...) for constants
//   if (c) a else b, early returns -> sel(c, a, b)  (every lane runs both sides, as on a GPU)
//   argus_noise(p) -> noise(p), argus_fbm -> fbm, argus_rand -> rand, argus_uv -> uv ...
// sin, cos, exp, exp2, log2 are SIMD polynomials (|error| < 2e-7 on sin, ~1e-7 rel. on exp2),
// in the spirit of Metal's fast math. They run in @setFloatMode(.optimized), except where fused
// or reordered math changed results (the sin/cos angle reduction, fbm: strict, so they are
// bit-exact on x86 and ARM alike). Zig does not carry a float mode into inlined callees, so a
// port's own hot functions may add that line too (~5% more on Tides, output unchanged to 1 level).
// Tests: `zig test themes/cpu/argus_kernel.zig`.
//
// Hosts: argus_theme_draw writes [R, G, B, A] bytes; argus_theme_draw_target writes any
// 32-bit RGB layout (Target), so a display's own memory can be the render target.
//
// Time: one SDK step of 0.008 is one 30 Hz Metal tick (f.time += 1/30 s, f.frame += 1), so
// the app's speed setting, which scales the step, scales f.time the same way.
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");

/// Lanes per call. Zig suggests 8 on many AVX-512 parts (it prefers 256-bit vectors); for this
/// ALU-bound work 16 lanes measured 1.5x faster on a Xeon (22.9 vs 34.2 ms, 1920x1200 Tides).
pub const N: comptime_int = if (builtin.cpu.arch == .x86_64 and std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f))
    16
else
    std.simd.suggestVectorLength(f32) orelse 4;
pub const F = @Vector(N, f32);
pub const U = @Vector(N, u32);
pub const I = @Vector(N, i32);
pub const M = @Vector(N, bool);

pub inline fn f(x: f32) F {
    return @splat(x);
}
pub inline fn u(x: u32) U {
    return @splat(x);
}
pub inline fn sel(m: M, a: F, b: F) F {
    return @select(f32, m, a, b);
}

// ---- float2 / float3 ---------------------------------------------------------------------

pub const V2 = struct {
    x: F,
    y: F,

    pub inline fn add(a: V2, b: V2) V2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub inline fn sub(a: V2, b: V2) V2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub inline fn scale(a: V2, s: F) V2 {
        return .{ .x = a.x * s, .y = a.y * s };
    }
    pub inline fn floor(a: V2) V2 {
        return .{ .x = @floor(a.x), .y = @floor(a.y) };
    }
    pub inline fn fract(a: V2) V2 {
        return .{ .x = a.x - @floor(a.x), .y = a.y - @floor(a.y) };
    }
    pub inline fn length(a: V2) F {
        return @sqrt(a.x * a.x + a.y * a.y);
    }
    pub inline fn select(m: M, a: V2, b: V2) V2 {
        return .{ .x = sel(m, a.x, b.x), .y = sel(m, a.y, b.y) };
    }
};

pub const V3 = struct {
    x: F,
    y: F,
    z: F,

    pub inline fn add(a: V3, b: V3) V3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub inline fn mul(a: V3, b: V3) V3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }
    pub inline fn scale(a: V3, s: F) V3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    pub inline fn mix(a: V3, b: V3, t: F) V3 {
        return .{ .x = k_mix(a.x, b.x, t), .y = k_mix(a.y, b.y, t), .z = k_mix(a.z, b.z, t) };
    }
    pub inline fn saturate(a: V3) V3 {
        return .{ .x = k_sat(a.x), .y = k_sat(a.y), .z = k_sat(a.z) };
    }
    pub inline fn select(m: M, a: V3, b: V3) V3 {
        return .{ .x = sel(m, a.x, b.x), .y = sel(m, a.y, b.y), .z = sel(m, a.z, b.z) };
    }
};

pub inline fn v2(x: f32, y: f32) V2 {
    return .{ .x = f(x), .y = f(y) };
}
pub inline fn v3(x: f32, y: f32, z: f32) V3 {
    return .{ .x = f(x), .y = f(y), .z = f(z) };
}

// ---- Scalar-per-lane math (Metal names) --------------------------------------------------

inline fn k_mix(a: F, b: F, t: F) F {
    return a + (b - a) * t;
}
inline fn k_sat(x: F) F {
    return @min(@max(x, f(0)), f(1));
}
pub const mix = k_mix;
pub const saturate = k_sat;

pub inline fn fract(x: F) F {
    return x - @floor(x);
}
pub inline fn smoothstep(e0: f32, e1: f32, x: F) F {
    const t = k_sat((x - f(e0)) * f(1.0 / (e1 - e0)));
    return t * t * (f(3) - f(2) * t);
}

/// x - 2 pi k, k = round(x / 2 pi): the two-constant (Cody-Waite) reduction to [-pi, pi]. Strict
/// float mode on purpose: optimized mode lets LLVM merge the two constants, and the error then
/// grows with |x| (measured: sin 2.1e-7 -> 2.7e-6 at |x| <= 100; f.time runs to 14400 s).
inline fn reduce(x: F) F {
    @setFloatMode(.strict);
    const k = @round(x * f(1.0 / (2.0 * std.math.pi)));
    return x - k * f(6.28125) - k * f(2.0 * std.math.pi - 6.28125);
}

/// sin of a reduced angle in [-pi, pi]: folded to [-pi/2, pi/2], odd degree 11.
inline fn sinReduced(r0: F) F {
    @setFloatMode(.optimized);
    var r = r0;
    const hi = f(std.math.pi / 2.0);
    r = sel(r > hi, f(std.math.pi) - r, sel(r < -hi, f(-std.math.pi) - r, r));
    const r2 = r * r;
    var p = f(-2.5052108e-8);
    p = p * r2 + f(2.7557319e-6);
    p = p * r2 + f(-1.9841270e-4);
    p = p * r2 + f(8.3333333e-3);
    p = p * r2 + f(-1.6666667e-1);
    return r + r * r2 * p;
}
pub inline fn sin(x: F) F {
    return sinReduced(reduce(x));
}
/// cos(x) = sin(x + pi/2), with pi/2 added after the reduction: added before, it rounds away
/// low bits of a large x (measured 3.4e-6 at |x| <= 100, now ~2e-7).
pub inline fn cos(x: F) F {
    const r = reduce(x) + f(std.math.pi / 2.0);
    return sinReduced(sel(r > f(std.math.pi), r - f(2.0 * std.math.pi), r));
}

/// 2^x: integer part into the exponent bits, fraction (in [-0.5, 0.5]) by a degree-6 polynomial.
pub inline fn exp2(x0: F) F {
    @setFloatMode(.optimized);
    const x = @min(@max(x0, f(-126)), f(127));
    const n = @round(x);
    const r = x - n;
    var p = f(1.5403530e-4);
    p = p * r + f(1.3333558e-3);
    p = p * r + f(9.6181291e-3);
    p = p * r + f(5.5504109e-2);
    p = p * r + f(2.4022651e-1);
    p = p * r + f(6.9314718e-1);
    p = p * r + f(1.0);
    const bits: U = @bitCast((@as(I, @intFromFloat(n)) + @as(I, @splat(127))) << @splat(23));
    return p * @as(F, @bitCast(bits));
}
pub inline fn exp(x: F) F {
    return exp2(x * f(std.math.log2e));
}
/// log2 for x > 0: exponent bits plus a polynomial in the mantissa mapped to [sqrt(1/2), sqrt(2)).
pub inline fn log2(x: F) F {
    @setFloatMode(.optimized);
    const bits: U = @bitCast(x);
    var e: F = @floatFromInt(@as(I, @bitCast((bits >> @splat(23)) & u(0xFF))) - @as(I, @splat(127)));
    var m: F = @bitCast((bits & u(0x007F_FFFF)) | u(0x3F80_0000)); // [1, 2)
    const big = m > f(std.math.sqrt2);
    m = sel(big, m * f(0.5), m);
    e = sel(big, e + f(1), e);
    const t = (m - f(1)) / (m + f(1)); // log(m) = 2 atanh(t)
    const t2 = t * t;
    const ln_m = f(2) * t * (f(1) + t2 * (f(1.0 / 3.0) + t2 * (f(1.0 / 5.0) + t2 * f(1.0 / 7.0))));
    return e + ln_m * f(std.math.log2e);
}

// ---- The Argus prelude (src/gpu/argus_prelude.metal), lane for lane ----------------------

pub const Frame = extern struct {
    time: f32,
    dt: f32,
    frame: u32,
    width: u32,
    height: u32,
    state_width: u32 = 0,
    state_height: u32 = 0,
    seed: u32,
    days_j2000: i32 = 0,
    day_frac: f32 = 0,
    utc_offset_s: i32 = 0,
};

/// thread_position_in_grid for N neighbouring pixels of one row.
pub const Gid = struct { x: U, y: U };
pub const Cell = struct { x: U, y: U };

/// argus_uv: (0,0) mid-screen, y up, the short side spans -1..1.
pub inline fn uv(gid: Gid, fr: *const Frame) V2 {
    const inv = f(1.0 / (0.5 * @as(f32, @floatFromInt(@min(fr.width, fr.height)))));
    const px: F = @as(F, @floatFromInt(gid.x)) + f(0.5 - 0.5 * @as(f32, @floatFromInt(fr.width)));
    const py: F = @as(F, @floatFromInt(gid.y)) + f(0.5 - 0.5 * @as(f32, @floatFromInt(fr.height)));
    return .{ .x = px * inv, .y = -py * inv };
}

pub inline fn hash(x0: U) U {
    var x = x0;
    x ^= x >> @splat(16);
    x *%= u(0x7feb352d);
    x ^= x >> @splat(15);
    x *%= u(0x846ca68b);
    x ^= x >> @splat(16);
    return x;
}

pub inline fn rand(c: Cell, seed: u32) F {
    return unit(hash(c.x ^ hash(c.y ^ u(argus_hash1(seed)))));
}
inline fn unit(h: U) F {
    return @as(F, @floatFromInt(h)) * f(1.0 / 4294967295.0);
}
fn argus_hash1(x0: u32) u32 {
    var x = x0;
    x ^= x >> 16;
    x *%= 0x7feb352d;
    x ^= x >> 15;
    x *%= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

/// Metal's uint2(int2(p) + k): toward zero to int, offset, reinterpret as uint.
pub inline fn cell(p: V2, k: i32) Cell {
    const ki: I = @splat(k);
    return .{
        .x = @bitCast(@as(I, @intFromFloat(p.x)) +% ki),
        .y = @bitCast(@as(I, @intFromFloat(p.y)) +% ki),
    };
}

pub inline fn noise(p: V2) F {
    @setFloatMode(.optimized);
    const i = p.floor();
    const fr = p.sub(i);
    const ux = fr.x * fr.x * (f(3) - f(2) * fr.x);
    const uy = fr.y * fr.y * (f(3) - f(2) * fr.y);
    const c = cell(i, 32768);
    const one = u(1);
    // rand(cell, 0) for the four corners, sharing each row's inner hash (bit-identical).
    const h0 = u(argus_hash1(0));
    const row0 = hash(c.y ^ h0);
    const row1 = hash((c.y +% one) ^ h0);
    const a = unit(hash(c.x ^ row0));
    const b = unit(hash((c.x +% one) ^ row0));
    const d = unit(hash(c.x ^ row1));
    const e = unit(hash((c.x +% one) ^ row1));
    return f(2) * k_mix(k_mix(a, b, ux), k_mix(d, e, ux), uy) - f(1);
}

pub inline fn fbm(p0: V2, comptime octaves: u32) F {
    // Strict: fusing the octave rotation into FMAs moved large coordinates enough to pick other
    // noise cells (1.1e-4 off the literal prelude at |p| ~ 500) and would differ between AVX and
    // NEON. Strict, fbm is bit-exact everywhere; noise() inside keeps its own (exact) mode.
    @setFloatMode(.strict);
    var p = p0;
    var sum = f(0);
    var amp: f32 = 0.5;
    inline for (0..octaves) |_| {
        sum += f(amp) * noise(p);
        // float2x2(1.6, 1.2, -1.2, 1.6) * p, through a temporary: `p = .{ .x = .., .y = ..p.x.. }`
        // would write p.x before .y reads it (result location aliasing).
        const rot = V2{ .x = f(1.6) * p.x - f(1.2) * p.y, .y = f(1.2) * p.x + f(1.6) * p.y };
        p = rot;
        amp *= 0.5;
    }
    return sum;
}

pub inline fn palette(t: F, a: V3, b: V3, c: V3, d: V3) V3 {
    @setFloatMode(.optimized);
    const tau = f(6.2831853);
    return .{
        .x = a.x + b.x * cos(tau * (c.x * t + d.x)),
        .y = a.y + b.y * cos(tau * (c.y * t + d.y)),
        .z = a.z + b.z * cos(tau * (c.z * t + d.z)),
    };
}

pub inline fn srgb(lin0: V3) V3 {
    const lin = lin0.saturate();
    const one = struct {
        inline fn ch(l: F) F {
            const hi = f(1.055) * exp2(log2(@max(l, f(1e-30))) * f(1.0 / 2.4)) - f(0.055);
            return sel(l <= f(0.0031308), l * f(12.92), hi);
        }
    };
    return .{ .x = one.ch(lin.x), .y = one.ch(lin.y), .z = one.ch(lin.z) };
}

pub inline fn aces(x: V3) V3 {
    const one = struct {
        inline fn ch(c: F) F {
            return k_sat((c * (f(2.51) * c + f(0.03))) / (c * (f(2.43) * c + f(0.59)) + f(0.14)));
        }
    };
    return .{ .x = one.ch(x.x), .y = one.ch(x.y), .z = one.ch(x.z) };
}

// ---- Dispatch ----------------------------------------------------------------------------

const MAX_THREADS = 64;
const ROWS_PER_GRAB = 4;
const TICK_DT: f64 = 0.008; // the SDK step that equals one 30 Hz Metal tick
const lane_ids: U = std.simd.iota(u32, N);

const Shift = @Vector(N, u5);

/// A pixel buffer in any 32-bit RGB layout: `shift` is each channel's bit offset (R, G, B).
/// argus_theme_draw is draw_target with {0, 8, 16} (Argus's [R, G, B, A] bytes); a host can
/// instead hand over its display memory in the display's own order (X11 BGRX: {16, 8, 0})
/// and skip the copy-and-reorder pass.
pub const Target = extern struct {
    px: [*]u32,
    len: usize,
    stride: usize, // in pixels
    shift: [3]u8,
};

/// round(saturate(c) * 255) per channel, as the GPU harness packs, at the target's bit offsets.
inline fn pack(c: V3, sr: Shift, sg: Shift, sb: Shift) U {
    const s = f(255);
    const r: U = @intFromFloat(@round(k_sat(c.x) * s));
    const g: U = @intFromFloat(@round(k_sat(c.y) * s));
    const b: U = @intFromFloat(@round(k_sat(c.z) * s));
    return u(0xFF00_0000) | (r << sr) | (g << sg) | (b << sb);
}

pub fn exportKernelTheme(comptime K: type) void {
    const Theme = struct {
        const Self = @This();
        frame: Frame,
        clock: f64,
        threads: usize,

        var allocs_init: usize = 0;

        const Job = struct {
            th: *const Self,
            px: []u32,
            stride: usize,
            shift: [3]u8,
            next_row: std.atomic.Value(u32) = .init(0),

            fn run(job: *Job) void {
                @setFloatMode(.optimized);
                const fr = &job.th.frame;
                const w: usize = fr.width;
                const sr: Shift = @splat(@intCast(job.shift[0]));
                const sg: Shift = @splat(@intCast(job.shift[1]));
                const sb: Shift = @splat(@intCast(job.shift[2]));
                while (true) {
                    const y0 = job.next_row.fetchAdd(ROWS_PER_GRAB, .monotonic);
                    if (y0 >= fr.height) return;
                    for (y0..@min(y0 + ROWS_PER_GRAB, fr.height)) |y| {
                        const row = job.px[y * job.stride ..][0..w];
                        var x: usize = 0;
                        while (x < w) : (x += N) {
                            const gid = Gid{ .x = u(@intCast(x)) + lane_ids, .y = u(@intCast(y)) };
                            const out: [N]u32 = pack(K.draw(fr, gid), sr, sg, sb);
                            const n = @min(N, w - x);
                            @memcpy(row[x..][0..n], out[0..n]);
                        }
                    }
                }
            }
        };

        fn init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque {
            _ = scale;
            const self = std.heap.page_allocator.create(Self) catch return null;
            allocs_init = 1;
            self.* = .{
                .frame = .{ .time = 0, .dt = 1.0 / 30.0, .frame = 0, .width = w, .height = h, .seed = 0x5EED },
                .clock = 0,
                .threads = @min(MAX_THREADS, std.Thread.getCpuCount() catch 1),
            };
            return self;
        }

        fn deinit(raw: ?*anyopaque) callconv(.c) void {
            std.heap.page_allocator.destroy(@as(*Self, @ptrCast(@alignCast(raw orelse return))));
        }

        fn step(raw: ?*anyopaque, dt: f64) callconv(.c) void {
            const self: *Self = @ptrCast(@alignCast(raw orelse return));
            self.clock = @mod(self.clock + dt / TICK_DT / 30.0, 14400.0); // ARGUS_TIME_PERIOD
            self.frame.time = @floatCast(self.clock);
            self.frame.frame +%= 1;
        }

        fn draw(raw: ?*anyopaque, px: [*]u32, len: usize, stride: usize) callconv(.c) void {
            drawTarget(raw, &.{ .px = px, .len = len, .stride = stride, .shift = .{ 0, 8, 16 } });
        }

        fn drawTarget(raw: ?*anyopaque, target: *const Target) callconv(.c) void {
            const self: *const Self = @ptrCast(@alignCast(raw orelse return));
            if (self.frame.height == 0 or target.len < (self.frame.height - 1) * target.stride + self.frame.width) return;
            for (target.shift) |s| if (s > 24) return;
            var job = Job{ .th = self, .px = target.px[0..target.len], .stride = target.stride, .shift = target.shift };
            var pool: [MAX_THREADS]?std.Thread = @splat(null);
            for (1..self.threads) |t| pool[t] = std.Thread.spawn(.{}, Job.run, .{&job}) catch null;
            job.run();
            for (pool[1..self.threads]) |th| if (th) |t| t.join();
        }

        fn allocsInit() callconv(.c) usize {
            return allocs_init;
        }
        fn allocsAfter() callconv(.c) usize {
            return 0;
        }
        fn bytesLive() callconv(.c) usize {
            return @sizeOf(Self);
        }
        fn hasNaN(raw: ?*anyopaque) callconv(.c) bool {
            return raw == null;
        }
    };
    @export(&Theme.init, .{ .name = "argus_theme_init" });
    @export(&Theme.deinit, .{ .name = "argus_theme_deinit" });
    @export(&Theme.step, .{ .name = "argus_theme_step" });
    @export(&Theme.draw, .{ .name = "argus_theme_draw" });
    @export(&Theme.drawTarget, .{ .name = "argus_theme_draw_target" });
    @export(&Theme.allocsInit, .{ .name = "argus_theme_allocs_init" });
    @export(&Theme.allocsAfter, .{ .name = "argus_theme_allocs_after_init" });
    @export(&Theme.bytesLive, .{ .name = "argus_theme_bytes_live" });
    @export(&Theme.hasNaN, .{ .name = "argus_theme_has_nan" });
}

// ---- Tests: `zig test themes/cpu/argus_kernel.zig` (make test also runs them as aarch64 under qemu)

/// The prelude transcribed literally, one scalar at a time: the reference the lanes must match bit
/// for bit (any lane-order or aliasing slip shows up as a mismatch).
const Ref = struct {
    fn rand(cx: u32, cy: u32, seed: u32) f32 {
        return @as(f32, @floatFromInt(argus_hash1(cx ^ argus_hash1(cy ^ argus_hash1(seed))))) * (1.0 / 4294967295.0);
    }
    fn noise(px: f32, py: f32) f32 {
        const ix = @floor(px);
        const iy = @floor(py);
        const fx = px - ix;
        const fy = py - iy;
        const ux = fx * fx * (3.0 - 2.0 * fx);
        const uy = fy * fy * (3.0 - 2.0 * fy);
        const cx: u32 = @bitCast(@as(i32, @intFromFloat(ix)) +% 32768);
        const cy: u32 = @bitCast(@as(i32, @intFromFloat(iy)) +% 32768);
        const a = Ref.rand(cx, cy, 0);
        const b = Ref.rand(cx +% 1, cy, 0);
        const d = Ref.rand(cx, cy +% 1, 0);
        const e = Ref.rand(cx +% 1, cy +% 1, 0);
        const top = a + (b - a) * ux;
        const bot = d + (e - d) * ux;
        return 2.0 * (top + (bot - top) * uy) - 1.0;
    }
    fn fbm(px0: f32, py0: f32, octaves: u32) f32 {
        var px = px0;
        var py = py0;
        var sum: f32 = 0;
        var amp: f32 = 0.5;
        for (0..octaves) |_| {
            sum += amp * Ref.noise(px, py);
            const nx = 1.6 * px - 1.2 * py;
            py = 1.2 * px + 1.6 * py;
            px = nx;
            amp *= 0.5;
        }
        return sum;
    }
};

fn lanesFrom(xs: [N]f32) F {
    return xs;
}

test "SIMD sin, cos, exp2, log2 stay within fast-math error of the scalar functions" {
    var prng = std.Random.DefaultPrng.init(1);
    const r = prng.random();
    var worst = [4]f32{ 0, 0, 0, 0 };
    for (0..4000) |_| {
        var xs: [N]f32 = undefined;
        for (&xs) |*x| x.* = (r.float(f32) - 0.5) * 200.0;
        const s: [N]f32 = sin(lanesFrom(xs));
        const c: [N]f32 = cos(lanesFrom(xs));
        var es: [N]f32 = undefined;
        for (&es, xs) |*e, x| e.* = x * 0.1; // 2^[-10, 10]
        const e2: [N]f32 = exp2(lanesFrom(es));
        var ls: [N]f32 = undefined;
        for (&ls, xs) |*l, x| l.* = @abs(x) * 10.0 + 1e-3;
        const l2: [N]f32 = log2(lanesFrom(ls));
        for (0..N) |i| {
            worst[0] = @max(worst[0], @abs(s[i] - @sin(xs[i])));
            worst[1] = @max(worst[1], @abs(c[i] - @cos(xs[i])));
            worst[2] = @max(worst[2], @abs(e2[i] - @exp2(es[i])) / @exp2(es[i]));
            worst[3] = @max(worst[3], @abs(l2[i] - @log2(ls[i])));
        }
    }
    // Measured in Debug and ReleaseFast alike: sin 2.1e-7, cos 2.7e-7, exp2 2.5e-7 (rel), log2 9.5e-7.
    try std.testing.expect(worst[0] < 4e-7); // absolute, |x| <= 100
    try std.testing.expect(worst[1] < 4e-7);
    try std.testing.expect(worst[2] < 4e-7); // relative
    try std.testing.expect(worst[3] < 2e-6);
}

// Bit-exact against the literal prelude in Debug and ReleaseFast, on x86 and ARM alike (noise is
// exact under optimized mode as measured; fbm is strict). A mismatch means a lane or aliasing bug.
test "rand, noise and fbm match the scalar prelude bit for bit in every lane" {
    var prng = std.Random.DefaultPrng.init(2);
    const r = prng.random();
    for (0..2000) |_| {
        var xs: [N]f32 = undefined;
        var ys: [N]f32 = undefined;
        for (&xs, &ys) |*x, *y| {
            x.* = (r.float(f32) - 0.5) * 500.0;
            y.* = (r.float(f32) - 0.5) * 500.0;
        }
        const p = V2{ .x = lanesFrom(xs), .y = lanesFrom(ys) };
        const n: [N]f32 = noise(p);
        const b: [N]f32 = fbm(p, 4);
        const c = cell(p.floor(), 4096);
        const rd: [N]f32 = rand(c, 7);
        const cx: [N]u32 = c.x;
        const cy: [N]u32 = c.y;
        for (0..N) |i| {
            try std.testing.expectEqual(Ref.noise(xs[i], ys[i]), n[i]);
            try std.testing.expectEqual(Ref.fbm(xs[i], ys[i], 4), b[i]);
            try std.testing.expectEqual(Ref.rand(cx[i], cy[i], 7), rd[i]);
        }
    }
}

test "pack honours the target's channel layout" {
    const c = V3{ .x = f(1.0), .y = f(0.5), .z = f(0.0) }; // r 255, g 128, b 0
    const rgba: [N]u32 = pack(c, @splat(0), @splat(8), @splat(16));
    const bgrx: [N]u32 = pack(c, @splat(16), @splat(8), @splat(0));
    try std.testing.expectEqual(@as(u32, 0xFF00_80FF), rgba[0]);
    try std.testing.expectEqual(@as(u32, 0xFFFF_8000), bgrx[N - 1]);
}

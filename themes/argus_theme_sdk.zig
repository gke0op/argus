// ============================================================================
// ARGUS THEME SDK // themes/argus_theme_sdk.zig
//
// Zero-AppKit Native Zig Theme Contract for Argus.app & Headless Harness.
//
// Usage in any theme file (e.g. `themes/Echo.zig`):
//
//   const std = @import("std");
//   const sdk = @import("argus_theme_sdk.zig");
//
//   pub const State = struct {
//       pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State { ... }
//       pub fn deinit(self: *State, alloc: std.mem.Allocator) void { ... }
//       pub fn step(self: *State, dt: f64) void { ... }
//       pub fn draw(self: *const State, buf: []u32, stride: usize) void { ... }
//       pub fn hasNaN(self: *const State) bool { ... } // optional
//   };
//   comptime { sdk.exportTheme(State); }
// ============================================================================

const std = @import("std");

/// Packs 8-bit unpremultiplied/opaque R, G, B into Argus's native pixel format:
/// Little-endian u32 word = 0xFF_BB_GG_RR -> memory bytes [R, G, B, 255].
/// Matches CoreGraphics `kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big`.
pub inline fn packRGBA(r: u8, g: u8, b: u8) u32 {
    return (@as(u32, 255) << 24) | (@as(u32, b) << 16) | (@as(u32, g) << 8) | @as(u32, r);
}

/// Packs 8-bit R, G, B, A with premultiplied alpha into Argus's native pixel format.
pub inline fn packPremulRGBA(r: u8, g: u8, b: u8, a: u8) u32 {
    const af: u32 = a;
    const rp: u8 = @intCast((@as(u32, r) * af + 127) / 255);
    const gp: u8 = @intCast((@as(u32, g) * af + 127) / 255);
    const bp: u8 = @intCast((@as(u32, b) * af + 127) / 255);
    return (af << 24) | (@as(u32, bp) << 16) | (@as(u32, gp) << 8) | @as(u32, rp);
}

/// Saturating additive blend of two `packRGBA` pixels (immune to Zig 0.17 `@min(255, x)` u8 peer-type narrowing).
pub inline fn addRGB(c1: u32, c2: u32) u32 {
    const r1: u8 = @truncate(c1);
    const g1: u8 = @truncate(c1 >> 8);
    const b1: u8 = @truncate(c1 >> 16);
    const r2: u8 = @truncate(c2);
    const g2: u8 = @truncate(c2 >> 8);
    const b2: u8 = @truncate(c2 >> 16);
    return packRGBA(r1 +| r2, g1 +| g2, b1 +| b2);
}

/// Scales an RGB pixel by an 8-bit fixed-point weight `scale_256` in `[0..256]`.
pub inline fn scaleRGB(c: u32, scale_256: u32) u32 {
    const s = @min(@as(u32, 256), scale_256);
    const r: u8 = @intCast(((c & 0xFF) * s) >> 8);
    const g: u8 = @intCast((((c >> 8) & 0xFF) * s) >> 8);
    const b: u8 = @intCast((((c >> 16) & 0xFF) * s) >> 8);
    return packRGBA(r, g, b);
}

/// Linearly interpolates between `c0` and `c1` using fixed-point `t_256` in `[0..256]`.
pub inline fn lerpRGB(c0: u32, c1: u32, t_256: u32) u32 {
    const t = @min(@as(u32, 256), t_256);
    const inv = 256 - t;
    const r: u8 = @intCast(((c0 & 0xFF) * inv + (c1 & 0xFF) * t) >> 8);
    const g: u8 = @intCast((((c0 >> 8) & 0xFF) * inv + ((c1 >> 8) & 0xFF) * t) >> 8);
    const b: u8 = @intCast((((c0 >> 16) & 0xFF) * inv + ((c1 >> 16) & 0xFF) * t) >> 8);
    return packRGBA(r, g, b);
}

/// Resolution-independent, stride-aware, bounds-checked canvas wrapper.
/// Prevents unsigned `usize` subtraction underflow when tested at 320x200 in `--verify-dylib`.
pub const Canvas = struct {
    buf: []u32,
    w: usize,
    h: usize,
    stride: usize,

    pub inline fn init(buf: []u32, w: usize, h: usize, stride: usize) Canvas {
        return .{ .buf = buf, .w = w, .h = h, .stride = stride };
    }

    pub inline fn clear(self: Canvas, color: u32) void {
        for (0..self.h) |y| {
            const row = y * self.stride;
            @memset(self.buf[row .. row + self.w], color);
        }
    }

    pub inline fn setSigned(self: Canvas, x: isize, y: isize, color: u32) void {
        if (x < 0 or y < 0) return;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= self.w or uy >= self.h) return;
        self.buf[uy * self.stride + ux] = color;
    }

    pub inline fn addSigned(self: Canvas, x: isize, y: isize, color: u32) void {
        if (x < 0 or y < 0) return;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= self.w or uy >= self.h) return;
        const idx = uy * self.stride + ux;
        self.buf[idx] = addRGB(self.buf[idx], color);
    }
};

/// CountingAllocator wraps page_allocator to track exact allocation counts and bytes
/// during `init` vs. `step`/`draw`. The headless harness asserts:
///   - `allocs_during_init == 1`
///   - `allocs_after_init == 0`
pub const CountingAllocator = struct {
    backing: std.mem.Allocator = std.heap.page_allocator,
    in_init: bool = false,
    allocs_during_init: usize = 0,
    allocs_after_init: usize = 0,
    bytes_live: usize = 0,

    const vtable = std.mem.Allocator.VTable{
        .alloc = allocFn,
        .resize = resizeFn,
        .remap = remapFn,
        .free = freeFn,
    };

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn allocFn(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.backing.rawAlloc(len, alignment, ret_addr) orelse return null;
        if (self.in_init) {
            self.allocs_during_init += 1;
        } else {
            self.allocs_after_init += 1;
        }
        self.bytes_live += len;
        return ptr;
    }

    fn resizeFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (self.backing.rawResize(buf, alignment, new_len, ret_addr)) {
            if (new_len > buf.len) {
                self.bytes_live += (new_len - buf.len);
            } else {
                self.bytes_live -|= (buf.len - new_len);
            }
            return true;
        }
        return false;
    }

    fn remapFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const p = self.backing.rawRemap(buf, alignment, new_len, ret_addr) orelse return null;
        if (!self.in_init) self.allocs_after_init += 1;
        if (new_len > buf.len) {
            self.bytes_live += (new_len - buf.len);
        } else {
            self.bytes_live -|= (buf.len - new_len);
        }
        return p;
    }

    fn freeFn(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.bytes_live -|= buf.len;
        self.backing.rawFree(buf, alignment, ret_addr);
    }
};

/// Generates the C-ABI `.dylib` entry points required by `Argus.app` and `theme_harness.zig`.
pub fn exportTheme(comptime State: type) void {
    const Wrapper = struct {
        var gpa = CountingAllocator{};
        var singleton_state: ?*State = null;
        var singleton_w: usize = 0;
        var singleton_h: usize = 0;
        var last_phase: f64 = 0.0;

        pub fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque {
            gpa.in_init = true;
            gpa.allocs_during_init = 0;
            gpa.allocs_after_init = 0;
            defer gpa.in_init = false;

            const st = State.init(gpa.allocator(), @as(usize, w), @as(usize, h), scale) catch return null;
            return @ptrCast(st);
        }

        pub fn argus_theme_deinit(raw: ?*anyopaque) callconv(.c) void {
            const ptr = raw orelse return;
            const st: *State = @ptrCast(@alignCast(ptr));
            st.deinit(gpa.allocator());
        }

        pub fn argus_theme_step(raw: ?*anyopaque, dt: f64) callconv(.c) void {
            const ptr = raw orelse return;
            const st: *State = @ptrCast(@alignCast(ptr));
            st.step(dt);
        }

        pub fn argus_theme_draw(raw: ?*anyopaque, pixels_ptr: [*]u32, buf_len: usize, stride: usize) callconv(.c) void {
            const ptr = raw orelse return;
            const st: *const State = @ptrCast(@alignCast(ptr));
            st.draw(pixels_ptr[0..buf_len], stride);
        }

        pub fn argus_theme_allocs_init() callconv(.c) usize {
            return gpa.allocs_during_init;
        }

        pub fn argus_theme_allocs_after_init() callconv(.c) usize {
            return gpa.allocs_after_init;
        }

        pub fn argus_theme_bytes_live() callconv(.c) usize {
            return gpa.bytes_live;
        }

        pub fn argus_theme_has_nan(raw: ?*anyopaque) callconv(.c) bool {
            const ptr = raw orelse return true;
            const st: *const State = @ptrCast(@alignCast(ptr));
            if (@hasDecl(State, "hasNaN")) {
                return st.hasNaN();
            }
            return false;
        }

        /// Compatibility entry point so `Argus.app` can also invoke the theme directly via `argus_render_theme`.
        pub fn argus_render_theme(pixels: [*]u32, width: u32, height: u32, phase: f64, step_count: u64) callconv(.c) void {
            _ = step_count;
            const w: usize = @intCast(width);
            const h: usize = @intCast(height);
            if (singleton_state == null or singleton_w != w or singleton_h != h) {
                if (singleton_state) |old| {
                    old.deinit(gpa.allocator());
                    singleton_state = null;
                }
                if (argus_theme_init(width, height, 1.0)) |raw| {
                    singleton_state = @ptrCast(@alignCast(raw));
                    singleton_w = w;
                    singleton_h = h;
                    last_phase = phase;
                } else return;
            }
            const st = singleton_state.?;
            // Fixed symplectic timestep dt = 0.008 owned by Argus
            st.step(0.008);
            last_phase = phase;
            st.draw(pixels[0 .. w * h], w);
        }
    };

    @export(&Wrapper.argus_theme_init, .{ .name = "argus_theme_init" });
    @export(&Wrapper.argus_theme_deinit, .{ .name = "argus_theme_deinit" });
    @export(&Wrapper.argus_theme_step, .{ .name = "argus_theme_step" });
    @export(&Wrapper.argus_theme_draw, .{ .name = "argus_theme_draw" });
    @export(&Wrapper.argus_theme_allocs_init, .{ .name = "argus_theme_allocs_init" });
    @export(&Wrapper.argus_theme_allocs_after_init, .{ .name = "argus_theme_allocs_after_init" });
    @export(&Wrapper.argus_theme_bytes_live, .{ .name = "argus_theme_bytes_live" });
    @export(&Wrapper.argus_theme_has_nan, .{ .name = "argus_theme_has_nan" });
    @export(&Wrapper.argus_render_theme, .{ .name = "argus_render_theme" });
}

// ---- ARGUS-BENCH claim validation (optional) ----
// A theme may declare `pub const claims: sdk.Claims` and, to be checked, expose
// `pub fn probeEquatorialRay(self: *const State, b: f64) sdk.RayProbe`, which must trace
// through the same light-path code its draw() uses. `make claims THEME=...` compares the
// probe against an independent reference. A declaration alone is never evidence.
pub const Metric = enum { none, schwarzschild, kerr };

pub const Claims = struct {
    metric: Metric = .none,
    /// Dimensionless spin a/M (Kerr only).
    spin: f64 = 0.0,
    inclination_deg: f64 = 90.0,
};

pub const RayProbe = struct {
    captured: bool,
    /// Total deflection angle in radians (escaping rays only; inf if unresolved).
    deflection: f64,
};

// ============================================================================
// ARGUS GPU PROTOTYPE // src/gpu/metal.zig
//
// Minimal Metal + CAMetalLayer glue over objc_msgSend (no headers, no Swift).
// ============================================================================

const std = @import("std");

pub const Id = ?*anyopaque;
pub const MTLSize = extern struct { w: usize, h: usize, d: usize };
pub const CGSize = extern struct { width: f64, height: f64 };

// Resolved at runtime with dlopen/dlsym, like the app does: no SDK needed to build.
var rt: struct {
    msgSend: *const anyopaque,
    getClass: *const fn ([*:0]const u8) callconv(.c) Id,
    selReg: *const fn ([*:0]const u8) callconv(.c) Id,
    poolPush: *const fn () callconv(.c) ?*anyopaque,
    poolPop: *const fn (?*anyopaque) callconv(.c) void,
    createDevice: *const fn () callconv(.c) Id,
} = undefined;
var loaded = false;

fn sym(comptime T: type, lib: *anyopaque, name: [*:0]const u8) !T {
    return @ptrCast(@alignCast(std.c.dlsym(lib, name) orelse return error.SymbolMissing));
}

/// Loads libobjc, Metal and QuartzCore. Idempotent.
pub fn load() !void {
    if (loaded) return;
    const objc = std.c.dlopen("/usr/lib/libobjc.A.dylib", .{ .LAZY = true }) orelse return error.ObjcLoadFailed;
    const metal = std.c.dlopen("/System/Library/Frameworks/Metal.framework/Metal", .{ .LAZY = true }) orelse return error.MetalLoadFailed;
    _ = std.c.dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", .{ .LAZY = true }) orelse return error.QuartzCoreLoadFailed;
    rt = .{
        .msgSend = try sym(*const anyopaque, objc, "objc_msgSend"),
        .getClass = try sym(*const fn ([*:0]const u8) callconv(.c) Id, objc, "objc_getClass"),
        .selReg = try sym(*const fn ([*:0]const u8) callconv(.c) Id, objc, "sel_registerName"),
        .poolPush = try sym(*const fn () callconv(.c) ?*anyopaque, objc, "objc_autoreleasePoolPush"),
        .poolPop = try sym(*const fn (?*anyopaque) callconv(.c) void, objc, "objc_autoreleasePoolPop"),
        .createDevice = try sym(*const fn () callconv(.c) Id, metal, "MTLCreateSystemDefaultDevice"),
    };
    loaded = true;
}

pub fn poolPush() ?*anyopaque {
    return rt.poolPush();
}

pub fn poolPop(pool: ?*anyopaque) void {
    rt.poolPop(pool);
}

pub fn cls(name: [*:0]const u8) Id {
    return rt.getClass(name);
}

pub fn sel(name: [*:0]const u8) Id {
    return rt.selReg(name);
}

/// objc_msgSend cast to `fn (id, SEL, args...) R` for the call site's argument types.
pub fn msg(comptime R: type, obj: Id, name: [*:0]const u8, args: anytype) R {
    const A = @TypeOf(args);
    const f = @typeInfo(A).@"struct".field_types;
    const s = sel(name);
    return switch (f.len) {
        0 => @as(*const fn (Id, Id) callconv(.c) R, @ptrCast(@alignCast(rt.msgSend)))(obj, s),
        1 => @as(*const fn (Id, Id, f[0]) callconv(.c) R, @ptrCast(@alignCast(rt.msgSend)))(obj, s, args[0]),
        2 => @as(*const fn (Id, Id, f[0], f[1]) callconv(.c) R, @ptrCast(@alignCast(rt.msgSend)))(obj, s, args[0], args[1]),
        3 => @as(*const fn (Id, Id, f[0], f[1], f[2]) callconv(.c) R, @ptrCast(@alignCast(rt.msgSend)))(obj, s, args[0], args[1], args[2]),
        4 => @as(*const fn (Id, Id, f[0], f[1], f[2], f[3]) callconv(.c) R, @ptrCast(@alignCast(rt.msgSend)))(obj, s, args[0], args[1], args[2], args[3]),
        else => @compileError("add an arity"),
    };
}

pub fn nsString(s: [*:0]const u8) Id {
    return msg(Id, cls("NSString"), "stringWithUTF8String:", .{s});
}

fn describe(err: Id) [*:0]const u8 {
    const d = msg(Id, err, "localizedDescription", .{});
    return msg(?[*:0]const u8, d, "UTF8String", .{}) orelse "?";
}

/// Shared-storage options: on Apple silicon CPU and GPU see the same memory.
pub const STORAGE_SHARED: usize = 0;
pub const PIXEL_BGRA8: usize = 80;

pub const Kernel = struct {
    device: Id,
    queue: Id,
    pso: Id,

    /// Compiles `src` at runtime and builds a compute pipeline for `entry`.
    pub fn init(src: [*:0]const u8, entry: [*:0]const u8) !Kernel {
        try load();
        const device = rt.createDevice() orelse return error.NoMetalDevice;
        var err: Id = null;
        const lib = msg(Id, device, "newLibraryWithSource:options:error:", .{ nsString(src), @as(Id, null), &err }) orelse {
            std.debug.print("metal compile failed: {s}\n", .{describe(err)});
            return error.MetalCompile;
        };
        const func = msg(Id, lib, "newFunctionWithName:", .{nsString(entry)}) orelse return error.MetalNoEntry;
        const pso = msg(Id, device, "newComputePipelineStateWithFunction:error:", .{ func, &err }) orelse {
            std.debug.print("metal pipeline failed: {s}\n", .{describe(err)});
            return error.MetalPipeline;
        };
        return .{ .device = device, .queue = msg(Id, device, "newCommandQueue", .{}), .pso = pso };
    }

    pub fn bufferCopy(self: *const Kernel, bytes: []const u8) Id {
        return msg(Id, self.device, "newBufferWithBytes:length:options:", .{ @as(*const anyopaque, bytes.ptr), bytes.len, STORAGE_SHARED });
    }

    pub fn bufferNew(self: *const Kernel, len: usize) Id {
        return msg(Id, self.device, "newBufferWithLength:options:", .{ len, STORAGE_SHARED });
    }

    /// Threadgroup shape for a 2D grid of one thread per pixel.
    pub fn groupSize(self: *const Kernel) MTLSize {
        const tw = msg(usize, self.pso, "threadExecutionWidth", .{});
        const tmax = msg(usize, self.pso, "maxTotalThreadsPerThreadgroup", .{});
        return .{ .w = tw, .h = @max(1, tmax / tw), .d = 1 };
    }
};

pub fn contents(buf: Id) [*]u8 {
    return msg([*]u8, buf, "contents", .{});
}

pub fn release(obj: Id) void {
    if (obj != null) msg(void, obj, "release", .{});
}

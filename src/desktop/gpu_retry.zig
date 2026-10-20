// ============================================================================
// ARGUS DESKTOP // src/desktop/gpu_retry.zig
//
// What a Space does when its GPU presenter (gpu/presenter.zig, Kerr-disk hybrids such as
// Cygnus A) is missing. A theme dylib that is not a GPU build draws on the CPU, for good. A GPU
// build whose presenter could not be made (Metal, the trace, a layer) retries every RETRY_TICKS
// and draws nothing meanwhile: its CPU fallback is the full-resolution image on the main thread,
// a whole core at 120 FPS. The old per-slot "tried this handle" mark also kept a Space on that
// fallback for good once its theme left the slot and came back (a Space reorder).
// ============================================================================

const std = @import("std");

pub const GpuRetry = struct {
    /// 5 s at the 30 Hz logic tick.
    pub const RETRY_TICKS: usize = 150;

    /// The dylib that has no GPU entry points: it draws on the CPU.
    cpu_handle: ?*anyopaque = null,
    /// The GPU build whose last create failed, and the tick at which to try it again.
    failed_handle: ?*anyopaque = null,
    retry_at: usize = 0,

    pub const Action = enum {
        /// Make the presenter now.
        create,
        /// Not a GPU build: the CPU path draws.
        cpu,
        /// A GPU build waiting to retry: draw nothing (the window keeps what it shows).
        wait,
    };

    pub fn next(self: *const GpuRetry, handle: ?*anyopaque, tick: usize) Action {
        if (handle == null or handle == self.cpu_handle) return .cpu;
        if (handle == self.failed_handle and tick < self.retry_at) return .wait;
        return .create;
    }

    pub fn notGpuBuild(self: *GpuRetry, handle: ?*anyopaque) void {
        self.cpu_handle = handle;
    }

    pub fn failed(self: *GpuRetry, handle: ?*anyopaque, tick: usize) void {
        self.failed_handle = handle;
        self.retry_at = tick + RETRY_TICKS;
    }

    pub fn created(self: *GpuRetry) void {
        self.failed_handle = null;
    }
};

/// One log line per failure kind per minute: a failure that repeats every 5 s stays readable.
pub fn LogLimiter(comptime Kind: type) type {
    return struct {
        pub const EVERY_TICKS: usize = 1800; // 60 s at 30 Hz
        last: [std.enums.values(Kind).len]?usize = @splat(null),

        /// True when `kind` should be logged at `tick` (and records it).
        pub fn due(self: *@This(), kind: Kind, tick: usize) bool {
            const i = @intFromEnum(kind);
            if (self.last[i]) |t| if (tick -| t < EVERY_TICKS) return false;
            self.last[i] = tick;
            return true;
        }
    };
}

// ============================================================================

fn h(n: usize) ?*anyopaque {
    return @ptrFromInt(n * 16);
}

test "gpu retry: a failed GPU build waits 5 s, then tries again; never the CPU path" {
    var r: GpuRetry = .{};
    const cygnus = h(1);
    try std.testing.expectEqual(GpuRetry.Action.create, r.next(cygnus, 100));
    r.failed(cygnus, 100);
    for (101..250) |t| try std.testing.expectEqual(GpuRetry.Action.wait, r.next(cygnus, t));
    try std.testing.expectEqual(GpuRetry.Action.create, r.next(cygnus, 250));
    r.created();
    try std.testing.expectEqual(GpuRetry.Action.create, r.next(cygnus, 251));
}

test "gpu retry: a theme leaving the slot and coming back is tried again (the reorder case)" {
    var r: GpuRetry = .{};
    const cygnus = h(1);
    // Created at this slot; a reorder moves another theme in (the presenter is dropped) and
    // later brings Cygnus A back. The old mark returned false here and drew on the CPU for good.
    try std.testing.expectEqual(GpuRetry.Action.create, r.next(cygnus, 10));
    r.created();
    try std.testing.expectEqual(GpuRetry.Action.cpu, r.next(null, 20));
    try std.testing.expectEqual(GpuRetry.Action.create, r.next(cygnus, 30_000));
}

test "gpu retry: a dylib with no GPU entry points draws on the CPU; another theme is unaffected" {
    var r: GpuRetry = .{};
    const cpu_build = h(2);
    const other = h(3);
    try std.testing.expectEqual(GpuRetry.Action.create, r.next(cpu_build, 0));
    r.notGpuBuild(cpu_build);
    try std.testing.expectEqual(GpuRetry.Action.cpu, r.next(cpu_build, 1));
    try std.testing.expectEqual(GpuRetry.Action.cpu, r.next(cpu_build, 1_000_000));
    try std.testing.expectEqual(GpuRetry.Action.create, r.next(other, 2));
    // A different failed theme does not hold up a new one.
    r.failed(other, 2);
    try std.testing.expectEqual(GpuRetry.Action.create, r.next(h(4), 3));
}

test "log limiter: once per kind per minute" {
    const Kind = enum { a, b };
    var l: LogLimiter(Kind) = .{};
    try std.testing.expect(l.due(.a, 0));
    try std.testing.expect(!l.due(.a, 150));
    try std.testing.expect(l.due(.b, 150));
    try std.testing.expect(!l.due(.a, 1799));
    try std.testing.expect(l.due(.a, 1800));
}

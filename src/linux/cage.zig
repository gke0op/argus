// ============================================================================
// ARGUS LINUX // src/linux/cage.zig
//
// Runs the theme in its own process. The host opens X, attaches the shared frame and maps the
// buffers below, then forks: the child keeps no descriptor but stderr (the X socket included),
// dies with its parent, locks itself down (sandbox.zig) and from then on only runs theme calls it
// is asked for, drawing into memory it shares with the parent. The parent never runs theme code;
// it talks to the child through one shared control block and a cross-process futex.
//
// Why a process and not only a filter: X11 lets any client read every window. A theme sharing a
// process with the X connection could ask the server for your other windows through that socket,
// which no syscall filter can tell apart from the host's own requests. In the child there is no
// socket to ask through.
//
// `Theme` is the same five calls either way: in-process when uncaged (`--sandbox off`), or
// forwarded to the caged child. A forwarded call costs one handoff (~16 us round trip measured
// on a 2-vCPU VM).
// ============================================================================

const std = @import("std");
const linux = std.os.linux;
const sandbox = @import("sandbox.zig");

pub const Target = extern struct { px: [*]u32, len: usize, stride: usize, shift: [3]u8 };

pub const Ops = struct {
    init: *const fn (u32, u32, f64) callconv(.c) ?*anyopaque,
    deinit: *const fn (?*anyopaque) callconv(.c) void,
    step: *const fn (?*anyopaque, f64) callconv(.c) void,
    draw: *const fn (?*anyopaque, [*]u32, usize, usize) callconv(.c) void,
    draw_target: ?*const fn (?*anyopaque, *const Target) callconv(.c) void,
};

const Cmd = enum(u32) { init = 1, deinit, step, draw, draw_target, quit };

const Ctl = extern struct {
    req: u32 align(64) = 0, // parent bumps it to ask for `cmd`
    done: u32 align(64) = 0, // child sets it to `req` when finished
    cmd: u32 = 0,
    ok: u32 = 0,
    w: u32 = 0,
    h: u32 = 0,
    scale: f64 = 0,
    dt: f64 = 0,
    px: usize = 0,
    len: usize = 0,
    stride: usize = 0,
    shift: [3]u8 = .{ 0, 8, 16 },
};

/// `n` items in memory shared with a child forked later (private mappings turn copy-on-write
/// across fork, so the child's writes would never reach the parent).
pub fn sharedAlloc(comptime T: type, n: usize) ![]T {
    const bytes = n * @sizeOf(T);
    const rc = linux.mmap(null, bytes, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED, .ANONYMOUS = true }, -1, 0);
    if (linux.errno(rc) != .SUCCESS) return error.OutOfMemory;
    const p: [*]T = @ptrFromInt(rc);
    return p[0..n];
}

fn futexWait(addr: *const u32, expect: u32, timeout_ns: u64) void {
    var ts = linux.timespec{ .sec = @intCast(timeout_ns / 1_000_000_000), .nsec = @intCast(timeout_ns % 1_000_000_000) };
    _ = linux.syscall4(.futex, @intFromPtr(addr), 0, expect, @intFromPtr(&ts)); // FUTEX_WAIT (shared)
}
/// Spins up to `ns` while `*addr == unchanged`. A futex sleep and wake costs ~8 us each way in
/// a VM (measured); a spin catches requests that follow each other closely.
fn spinFor(addr: *const u32, unchanged: u32, ns: u64) void {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    const end = @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec)) + ns;
    while (@atomicLoad(u32, addr, .acquire) == unchanged) {
        std.atomic.spinLoopHint();
        _ = linux.clock_gettime(.MONOTONIC, &ts);
        if (@as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec)) > end) return;
    }
}

fn futexWake(addr: *const u32) void {
    _ = linux.syscall3(.futex, @intFromPtr(addr), 1, 1); // FUTEX_WAKE (shared)
}

pub const Theme = struct {
    ops: Ops,
    st: ?*anyopaque = null, // in-process state (uncaged)
    ctl: ?*Ctl = null, // control block (caged)
    child: i32 = 0,

    pub fn inProcess(ops: Ops) Theme {
        return .{ .ops = ops };
    }

    /// Forks the caged theme process. Returns in the parent only; call it after everything the
    /// host needs is open and before any theme code has run.
    pub fn caged(ops: Ops) !Theme {
        const mem = try sharedAlloc(Ctl, 1);
        mem[0] = .{};
        const parent = linux.getpid();
        const pid = linux.syscall5(.clone, 17, 0, 0, 0, 0); // fork (SIGCHLD)
        if (linux.errno(pid) != .SUCCESS) return error.ForkFailed;
        if (pid == 0) childMain(&mem[0], ops, parent);
        return .{ .ops = ops, .ctl = &mem[0], .child = @intCast(pid) };
    }

    fn childMain(ctl: *Ctl, ops: Ops, parent: i32) noreturn {
        _ = linux.prctl(1, 9, 0, 0, 0); // PR_SET_PDEATHSIG = SIGKILL: no orphaned theme
        if (linux.getppid() != parent) linux.exit_group(0); // parent already gone
        // no descriptor but stderr: not the X socket, not stdin/stdout
        if (linux.errno(linux.syscall3(.close_range, 3, std.math.maxInt(u32), 0)) != .SUCCESS) {
            var fd: i32 = 3;
            while (fd < 1024) : (fd += 1) _ = linux.close(fd);
        }
        _ = linux.close(0);
        _ = linux.close(1);
        const rep = sandbox.lockdown(.errno);
        if (!rep.seccomp) linux.exit_group(70); // never run theme code uncaged by surprise
        var st: ?*anyopaque = null;
        var seen: u32 = 0;
        while (true) {
            // step and draw requests arrive microseconds apart: spin briefly before sleeping
            spinFor(&ctl.req, seen, 200_000);
            while (@atomicLoad(u32, &ctl.req, .acquire) == seen) futexWait(&ctl.req, seen, 1_000_000_000);
            seen = @atomicLoad(u32, &ctl.req, .acquire);
            switch (@as(Cmd, @enumFromInt(ctl.cmd))) {
                .init => {
                    st = ops.init(ctl.w, ctl.h, ctl.scale);
                    ctl.ok = @intFromBool(st != null);
                },
                .deinit => {
                    ops.deinit(st);
                    st = null;
                },
                .step => ops.step(st, ctl.dt),
                .draw => ops.draw(st, @ptrFromInt(ctl.px), ctl.len, ctl.stride),
                .draw_target => ops.draw_target.?(st, &.{ .px = @ptrFromInt(ctl.px), .len = ctl.len, .stride = ctl.stride, .shift = ctl.shift }),
                .quit => linux.exit_group(0),
            }
            @atomicStore(u32, &ctl.done, seen, .release);
            futexWake(&ctl.done);
        }
    }

    /// Hands `cmd` to the child and waits for it; notices within 100 ms if the child has died, and
    /// gives up on a call that hangs (the host then exits; the child dies with it: PDEATHSIG).
    fn call(self: *Theme, cmd: Cmd) !void {
        const ctl = self.ctl.?;
        ctl.cmd = @intFromEnum(cmd);
        const r = ctl.req +% 1;
        @atomicStore(u32, &ctl.req, r, .release);
        futexWake(&ctl.req);
        spinFor(&ctl.done, ctl.done, 50_000); // short calls finish before a sleep/wake would
        const limit_ticks: u32 = if (cmd == .init) 600 else 50; // x 100 ms: init may build tables
        var ticks: u32 = 0;
        while (true) {
            const d = @atomicLoad(u32, &ctl.done, .acquire);
            if (d == r) return;
            futexWait(&ctl.done, d, 100_000_000);
            if (@atomicLoad(u32, &ctl.done, .acquire) == r) return;
            ticks += 1;
            if (ticks >= limit_ticks) {
                std.debug.print("argus-linux: the theme did not answer within {d} s ({s}): giving up\n", .{ limit_ticks / 10, @tagName(cmd) });
                return error.ThemeHung;
            }
            var status: u32 = 0;
            if (linux.syscall4(.wait4, @as(usize, @bitCast(@as(isize, self.child))), @intFromPtr(&status), 1, 0) == @as(usize, @bitCast(@as(isize, self.child)))) { // WNOHANG
                if (status & 0x7f != 0) {
                    std.debug.print("argus-linux: the theme process was killed by signal {d}{s}\n", .{ status & 0x7f, if (status & 0x7f == 31) " (SIGSYS: the sandbox stopped a forbidden call)" else "" });
                } else std.debug.print("argus-linux: the theme process exited with status {d}\n", .{(status >> 8) & 0xff});
                return error.ThemeProcessDied;
            }
        }
    }

    pub fn init(self: *Theme, w: usize, h: usize, scale: f64) !void {
        if (self.ctl) |ctl| {
            ctl.w = @intCast(w);
            ctl.h = @intCast(h);
            ctl.scale = scale;
            try self.call(.init);
            if (ctl.ok == 0) return error.ThemeInitFailed;
        } else {
            self.st = self.ops.init(@intCast(w), @intCast(h), scale) orelse return error.ThemeInitFailed;
        }
    }
    pub fn deinit(self: *Theme) !void {
        if (self.ctl != null) try self.call(.deinit) else self.ops.deinit(self.st);
    }
    pub fn step(self: *Theme, dt: f64) !void {
        if (self.ctl) |ctl| {
            ctl.dt = dt;
            try self.call(.step);
        } else self.ops.step(self.st, dt);
    }
    pub fn draw(self: *Theme, px: []u32, stride: usize) !void {
        if (self.ctl) |ctl| {
            ctl.px = @intFromPtr(px.ptr);
            ctl.len = px.len;
            ctl.stride = stride;
            try self.call(.draw);
        } else self.ops.draw(self.st, px.ptr, px.len, stride);
    }
    pub fn drawTarget(self: *Theme, t: Target) !void {
        if (self.ctl) |ctl| {
            ctl.px = @intFromPtr(t.px);
            ctl.len = t.len;
            ctl.stride = t.stride;
            ctl.shift = t.shift;
            try self.call(.draw_target);
        } else self.ops.draw_target.?(self.st, &t);
    }
    pub fn quit(self: *Theme) void {
        if (self.ctl != null) {
            const ctl = self.ctl.?;
            ctl.cmd = @intFromEnum(Cmd.quit);
            @atomicStore(u32, &ctl.req, ctl.req +% 1, .release);
            futexWake(&ctl.req);
        }
    }
};

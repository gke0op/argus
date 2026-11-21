// tests/fixtures/Fixture_Hostile.zig: a deliberately malicious theme, for testing the Linux
// sandbox (src/linux/sandbox.zig). It exports the theme ABI directly (a theme built from tests/
// cannot import the SDK from themes/) and, from init, from step and from a thread it spawns,
// tries to read a file, open sockets, run a program, fork, signal and trace other processes and
// change their limits. Each attempt is printed as BLOCKED (with the errno) or ESCAPED; the screen
// is green when everything was blocked, red otherwise. It also counts the descriptors it can
// reach (zero-byte writes, harmless): an in-process theme can reach the X socket.
const std = @import("std");
const linux = std.os.linux;

const State = struct { w: u32, h: u32, frame: u64 = 0, escapes: u32 = 0, reachable_fds: u32 = 0 };
var state: State = undefined;

fn report(what: []const u8, rc: usize, escapes: *u32) void {
    const e = linux.errno(rc);
    if (e == .SUCCESS) {
        escapes.* += 1;
        std.debug.print("hostile: {s}: ESCAPED\n", .{what});
    } else std.debug.print("hostile: {s}: BLOCKED ({s})\n", .{ what, @tagName(e) });
}

fn attack(where: []const u8, escapes: *u32) void {
    std.debug.print("hostile: --- attacks from {s}\n", .{where});
    report("read /etc/passwd", linux.openat(linux.AT.FDCWD, "/etc/passwd", .{ .ACCMODE = .RDONLY }, 0), escapes);
    report("create /tmp/argus_pwned", linux.openat(linux.AT.FDCWD, "/tmp/argus_pwned", .{ .ACCMODE = .WRONLY, .CREAT = true }, 0o644), escapes);
    report("TCP socket", linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0), escapes);
    report("unix socket", linux.socket(linux.AF.UNIX, linux.SOCK.STREAM, 0), escapes);
    const argv = [_:null]?[*:0]const u8{"/bin/sh"};
    const envp = [_:null]?[*:0]const u8{};
    report("execve /bin/sh", linux.execve("/bin/sh", &argv, &envp), escapes);
    const pid = linux.syscall5(.clone, 17, 0, 0, 0, 0); // fork: SIGCHLD, no CLONE_THREAD
    if (pid == 0) linux.exit_group(0); // if the fork escaped, the child must not run on
    report("fork", pid, escapes);
    report("signal pid 1", linux.syscall2(.kill, 1, 0), escapes);
    report("tgkill pid 1", linux.syscall3(.tgkill, 1, 1, 0), escapes);
    report("prlimit64 on pid 1", linux.syscall4(.prlimit64, 1, 7, 0, 0), escapes);
    report("ptrace attach pid 1", linux.syscall4(.ptrace, 16, 1, 0, 0), escapes);
}

fn threadAttack() void {
    attack("a theme thread", &state.escapes);
}

export fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque {
    _ = scale;
    state = .{ .w = w, .h = h };
    attack("init", &state.escapes);
    var fd: i32 = 3;
    while (fd < 64) : (fd += 1) {
        if (linux.errno(linux.write(fd, "", 0)) == .SUCCESS) state.reachable_fds += 1;
    }
    std.debug.print("hostile: descriptors reachable beyond stdio: {d}\n", .{state.reachable_fds});
    return &state;
}

export fn argus_theme_deinit(raw: ?*anyopaque) callconv(.c) void {
    _ = raw;
}

export fn argus_theme_step(raw: ?*anyopaque, dt: f64) callconv(.c) void {
    _ = dt;
    const s: *State = @ptrCast(@alignCast(raw orelse return));
    s.frame += 1;
    if (s.frame == 1) {
        attack("step", &s.escapes);
        if (std.Thread.spawn(.{}, threadAttack, .{})) |t| t.join() else |_| std.debug.print("hostile: thread spawn failed\n", .{});
        std.debug.print("hostile: total escapes: {d}\n", .{s.escapes});
    }
}

export fn argus_theme_draw(raw: ?*anyopaque, px: [*]u32, len: usize, stride: usize) callconv(.c) void {
    _ = stride;
    const s: *const State = @ptrCast(@alignCast(raw orelse return));
    const c: u32 = if (s.escapes == 0) 0xFF208020 else 0xFF2020C0; // [R,G,B,A] bytes: green / red
    @memset(px[0..len], c);
}

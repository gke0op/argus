// ============================================================================
// ARGUS LINUX // src/linux/sandbox.zig
//
// Cages the process before theme code runs: themes are native code, so after the host has opened
// its X connection and shared frame, nothing a theme does may reach files, the network, other
// programs or other processes. Two independent layers, raw syscalls, no libraries:
//
//   * seccomp-bpf allowlist, generated at comptime: memory, threads, time, signals to itself,
//     reads and writes on descriptors that are already open. `clone` only with CLONE_THREAD
//     (threads yes, fork no); `arch_prctl` only to request AMX tile state. Only the x86-64 or
//     aarch64 syscall ABI passes (x32 / i386 numbers kill the process). Anything else returns
//     EPERM (or kills, `Mode.kill`).
//   * Landlock (when the kernel has it): no filesystem access, no TCP bind/connect, no abstract
//     unix sockets or signals outside the process. Descriptors opened before the lockdown (the
//     X socket) keep working.
//
// Both need PR_SET_NO_NEW_PRIVS and work unprivileged. They cannot be lifted once applied.
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const SYS = linux.SYS;

pub const Mode = enum { errno, kill };
pub const Report = struct { seccomp: bool, landlock_abi: usize };

const Insn = extern struct { code: u16, jt: u8, jf: u8, k: u32 };
const Prog = extern struct { len: u16, filter: [*]const Insn };

// BPF opcodes and seccomp return values
const LD_W_ABS: u16 = 0x20;
const JEQ_K: u16 = 0x15;
const JSET_K: u16 = 0x45;
const JGE_K: u16 = 0x35;
const RET_K: u16 = 0x06;
const RET_ALLOW: u32 = 0x7fff0000;
const RET_KILL_PROCESS: u32 = 0x80000000;
const RET_ERRNO_EPERM: u32 = 0x00050000 | 1;
const OFF_NR = 0;
const OFF_ARCH = 4;
const OFF_ARG0_LO = 16;

const AUDIT_ARCH: u32 = switch (builtin.cpu.arch) {
    .x86_64 => 0xC000003E,
    .aarch64 => 0xC00000B7,
    else => @compileError("sandbox: x86_64 or aarch64 only"),
};
const CLONE_THREAD: u32 = 0x00010000;
const ARCH_REQ_XCOMP_PERM: u32 = 0x1023;

/// Syscalls a theme and the frame loop may make after setup (measured with strace on Cygnus_A,
/// the CPU Tides port and Reservoir_Field, plus what the Zig runtime needs for threads, panics
/// and allocation growth).
const allow = blk: {
    const list = [_]SYS{
        .read,          .write,        .writev,          .readv,       .close,
        .mmap,          .munmap,       .mprotect,        .mremap,      .madvise,
        .futex,         .set_robust_list, .rseq,         .gettid,      .getpid,
        .sched_getaffinity, .sched_yield, .nanosleep,    .clock_nanosleep, .clock_gettime,
        .exit,          .exit_group,   .rt_sigreturn,    .rt_sigprocmask, .rt_sigaction,
        .sigaltstack,   .getrandom,    .ppoll,
    };
    break :blk if (builtin.cpu.arch == .x86_64) list ++ [_]SYS{.poll} else list;
};

const ARG_BLOCK = 5; // insns per argument-checked syscall
const PROG_LEN = 6 + allow.len + 1 + 3 * ARG_BLOCK + 1;

/// The filter. Every jump is local: the allowlist falls into one ALLOW right after it, and each
/// argument-checked syscall is a self-contained 5-insn block with its own returns, so no offset
/// depends on the layout of anything else. `pid` is the process's own id (tgkill check).
fn filter(mode: Mode, pid: u32) [PROG_LEN]Insn {
    const deny: u32 = if (mode == .kill) RET_KILL_PROCESS else RET_ERRNO_EPERM;
    var p: [PROG_LEN]Insn = undefined;
    var i: usize = 0;
    const At = struct {
        buf: *[PROG_LEN]Insn,
        n: *usize,
        fn op(s: @This(), code: u16, jt: u8, jf: u8, k: u32) void {
            s.buf[s.n.*] = .{ .code = code, .jt = jt, .jf = jf, .k = k };
            s.n.* += 1;
        }
        /// nr == sys ? (arg0 test k ? ALLOW : deny) : next block. `jset`: bit test, else equality.
        fn argBlock(s: @This(), sys: u32, jset: bool, k: u32, deny_: u32) void {
            s.op(JEQ_K, 0, ARG_BLOCK - 1, sys);
            s.op(LD_W_ABS, 0, 0, OFF_ARG0_LO);
            s.op(if (jset) JSET_K else JEQ_K, 0, 1, k);
            s.op(RET_K, 0, 0, RET_ALLOW);
            s.op(RET_K, 0, 0, deny_);
        }
    };
    const e = At{ .buf = &p, .n = &i };
    // wrong ABI (i386, x32 numbers) -> kill
    e.op(LD_W_ABS, 0, 0, OFF_ARCH);
    e.op(JEQ_K, 1, 0, AUDIT_ARCH);
    e.op(RET_K, 0, 0, RET_KILL_PROCESS);
    e.op(LD_W_ABS, 0, 0, OFF_NR);
    e.op(JGE_K, 0, 1, 0x40000000);
    e.op(RET_K, 0, 0, RET_KILL_PROCESS);
    // the allowlist: entry n jumps to the ALLOW just past the last entry
    for (allow, 0..) |nr, n| {
        const last = n == allow.len - 1;
        e.op(JEQ_K, if (last) 0 else @intCast(allow.len - 1 - n), if (last) 1 else 0, @intCast(@intFromEnum(nr)));
    }
    e.op(RET_K, 0, 0, RET_ALLOW);
    // clone only with CLONE_THREAD (threads, not fork); clone3 hides its flags in memory, so it
    // falls to deny and callers use clone (Zig's std.Thread does)
    e.argBlock(@intFromEnum(SYS.clone), true, CLONE_THREAD, deny);
    // tgkill only into this process (Zig's abort raises SIGABRT this way)
    e.argBlock(@intFromEnum(SYS.tgkill), false, pid, deny);
    // arch_prctl only to request AMX tile state
    if (builtin.cpu.arch == .x86_64)
        e.argBlock(@intFromEnum(SYS.arch_prctl), false, ARCH_REQ_XCOMP_PERM, deny)
    else
        e.argBlock(0xFFFFFFFF, false, 0, deny); // no such syscall on aarch64: never matches
    e.op(RET_K, 0, 0, deny);
    std.debug.assert(i == PROG_LEN);
    return p;
}

fn landlock() usize {
    const abi = linux.syscall3(.landlock_create_ruleset, 0, 0, 1); // LANDLOCK_CREATE_RULESET_VERSION
    if (linux.errno(abi) != .SUCCESS) return 0;
    const Attr = extern struct { fs: u64, net: u64, scoped: u64 };
    var attr = Attr{ .fs = 0, .net = 0, .scoped = 0 };
    // every filesystem right the kernel knows (ABI 1: 13 rights; 2: +REFER; 3: +TRUNCATE; 5: +IOCTL_DEV)
    attr.fs = (1 << 13) - 1;
    if (abi >= 2) attr.fs |= 1 << 13;
    if (abi >= 3) attr.fs |= 1 << 14;
    if (abi >= 5) attr.fs |= 1 << 15;
    if (abi >= 4) attr.net = 0b11; // BIND_TCP, CONNECT_TCP
    if (abi >= 6) attr.scoped = 0b11; // ABSTRACT_UNIX_SOCKET, SIGNAL
    const size: usize = if (abi >= 6) 24 else if (abi >= 4) 16 else 8;
    const fd = linux.syscall3(.landlock_create_ruleset, @intFromPtr(&attr), size, 0);
    if (linux.errno(fd) != .SUCCESS) return 0;
    defer _ = linux.close(@intCast(fd));
    if (linux.errno(linux.syscall2(.landlock_restrict_self, fd, 0)) != .SUCCESS) return 0;
    return abi;
}

/// Applies both layers to the calling process (all threads created afterwards inherit them).
/// Call after every file, socket and shared-memory segment the host needs is open.
pub fn lockdown(comptime mode: Mode) Report {
    if (linux.errno(linux.prctl(38, 1, 0, 0, 0)) != .SUCCESS) return .{ .seccomp = false, .landlock_abi = 0 }; // PR_SET_NO_NEW_PRIVS
    const abi = landlock();
    const insns = filter(mode, @intCast(linux.getpid()));
    const prog = Prog{ .len = insns.len, .filter = &insns };
    const ok = linux.errno(linux.syscall3(.seccomp, 1, 0, @intFromPtr(&prog))) == .SUCCESS; // SET_MODE_FILTER
    return .{ .seccomp = ok, .landlock_abi = abi };
}

// ---- Tests: run the generated program in a small BPF interpreter and check each decision.

fn run(prog: []const Insn, nr: u32, arch: u32, arg0: u32) u32 {
    var acc: u32 = 0;
    var pc: usize = 0;
    while (true) {
        const in = prog[pc];
        switch (in.code) {
            LD_W_ABS => acc = switch (in.k) {
                OFF_NR => nr,
                OFF_ARCH => arch,
                OFF_ARG0_LO => arg0,
                else => unreachable,
            },
            JEQ_K => pc += if (acc == in.k) in.jt else in.jf,
            JGE_K => pc += if (acc >= in.k) in.jt else in.jf,
            JSET_K => pc += if (acc & in.k != 0) in.jt else in.jf,
            RET_K => return in.k,
            else => unreachable,
        }
        pc += 1;
    }
}

test "seccomp filter decisions" {
    const me: u32 = 4242;
    const p = filter(.errno, me);
    const nr = struct {
        fn of(s: SYS) u32 {
            return @intCast(@intFromEnum(s));
        }
    }.of;
    const t = std.testing;
    try t.expectEqual(RET_ALLOW, run(&p, nr(.read), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ALLOW, run(&p, nr(.futex), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ALLOW, run(&p, nr(.exit_group), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.openat), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.socket), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.connect), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.execve), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.ptrace), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.clone3), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ALLOW, run(&p, nr(.clone), AUDIT_ARCH, CLONE_THREAD | 0x3d0f00));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.clone), AUDIT_ARCH, 17)); // fork: SIGCHLD only
    try t.expectEqual(RET_ALLOW, run(&p, nr(.tgkill), AUDIT_ARCH, me));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.tgkill), AUDIT_ARCH, me + 1)); // another process
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.kill), AUDIT_ARCH, me + 1));
    try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.prlimit64), AUDIT_ARCH, 0));
    if (builtin.cpu.arch == .x86_64) {
        try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.open), AUDIT_ARCH, 0));
        try t.expectEqual(RET_ALLOW, run(&p, nr(.arch_prctl), AUDIT_ARCH, ARCH_REQ_XCOMP_PERM));
        try t.expectEqual(RET_ERRNO_EPERM, run(&p, nr(.arch_prctl), AUDIT_ARCH, 0x1002)); // ARCH_SET_FS
        try t.expectEqual(RET_KILL_PROCESS, run(&p, 0x40000000 | nr(.openat), AUDIT_ARCH, 0)); // x32
    }
    try t.expectEqual(RET_KILL_PROCESS, run(&p, nr(.read), 0x40000003, 0)); // i386 ABI
    const pk = filter(.kill, me);
    try t.expectEqual(RET_KILL_PROCESS, run(&pk, nr(.openat), AUDIT_ARCH, 0));
    try t.expectEqual(RET_ALLOW, run(&pk, nr(.write), AUDIT_ARCH, 0));
}

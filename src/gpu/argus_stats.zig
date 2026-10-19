// ============================================================================
// ARGUS GPU // src/gpu/argus_stats.zig
//
// `ArgusStats`: the Mac's live vital signs, for Metal themes that ask with `// @argus stats`.
// Argus binds it as [[buffer(1)]] in argus_init, argus_step and argus_draw; the layout below
// mirrors `struct ArgusStats` in argus_prelude.metal (4-byte fields only, so C and Metal agree
// without padding). The app samples it about once a second (desktop/system_stats.zig); the
// harness feeds `synthetic`, so a render never depends on the machine.
// ============================================================================

const std = @import("std");

pub const MAX_CORES = 32;
pub const TOP_PROCS = 5;
pub const PROC_NAME_LEN = 32;
/// The kernel buffer index (buffer 0 is ArgusFrame).
pub const BUFFER_INDEX: usize = 1;

/// Mirrors `struct ArgusProc` in the prelude.
pub const Proc = extern struct {
    name: [PROC_NAME_LEN]u8 = @splat(0), // ASCII, NUL-padded, truncated to 31 characters
    cpu: f32 = 0, // share of the whole machine's CPU, 0-1 (x cpu_count = Activity Monitor's %CPU / 100)
    mem_gb: f32 = 0, // memory footprint, GiB (Activity Monitor's Memory column)

    pub fn setName(self: *Proc, s: []const u8) void {
        self.name = @splat(0);
        const n = @min(s.len, PROC_NAME_LEN - 1);
        for (s[0..n], 0..) |c, i| self.name[i] = if (c >= 0x20 and c < 0x7f) c else '?';
    }

    pub fn getName(self: *const Proc) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

/// Mirrors `struct ArgusStats` in the prelude (see there for the meaning of each field).
pub const Stats = extern struct {
    seq: u32 = 0,
    sample_dt: f32 = 0,
    uptime_s: u32 = 0,
    thermal: u32 = 0,

    cpu_total: f32 = 0,
    cpu_count: u32 = 0,
    cpu_p_cores: u32 = 0,
    cpu_e_cores: u32 = 0,
    cpu_core: [MAX_CORES]f32 = @splat(0),

    mem_total_gb: f32 = 0,
    mem_used_gb: f32 = 0,
    mem_compressed_gb: f32 = 0,
    mem_wired_gb: f32 = 0,
    swap_used_gb: f32 = 0,
    mem_pressure: u32 = 0,

    gpu_busy: f32 = 0,

    battery_present: u32 = 0,
    battery_charge: f32 = 0,
    battery_charging: u32 = 0,
    on_ac: u32 = 0,
    battery_minutes: f32 = 0,

    net_rx_bps: f32 = 0,
    net_tx_bps: f32 = 0,

    disk_free_gb: f32 = 0,
    disk_total_gb: f32 = 0,

    proc_count: u32 = 0,
    procs: [TOP_PROCS]Proc = @splat(.{}),
};

comptime {
    // The prelude's layout, field by field (a test also checks it on the GPU).
    std.debug.assert(@sizeOf(Proc) == 40);
    std.debug.assert(@offsetOf(Stats, "cpu_core") == 32);
    std.debug.assert(@offsetOf(Stats, "mem_total_gb") == 160);
    std.debug.assert(@offsetOf(Stats, "gpu_busy") == 184);
    std.debug.assert(@offsetOf(Stats, "net_rx_bps") == 208);
    std.debug.assert(@offsetOf(Stats, "proc_count") == 224);
    std.debug.assert(@offsetOf(Stats, "procs") == 228);
    std.debug.assert(@sizeOf(Stats) == 428);
}

/// Fixed, plausible stats for the harness: a function of `seq` only (1, 2, 3 ... one per
/// 30 frames), so every render of a theme is the same on every machine, while needles and
/// graphs still move. Values change slowly from one seq to the next, as a real Mac's do.
pub fn synthetic(seq: u32) Stats {
    const t: f32 = @floatFromInt(seq);
    var s: Stats = .{
        .seq = seq,
        .sample_dt = 1.0,
        .uptime_s = 3 * 86400 + 4 * 3600 + seq,
        .thermal = if (seq % 120 >= 100) 1 else 0,
        .cpu_count = 10,
        .cpu_p_cores = 6,
        .cpu_e_cores = 4,
        .mem_total_gb = 16.0,
        .mem_used_gb = 10.5 + 1.2 * @sin(t * 0.05) + 0.15 * @sin(t * 0.9),
        .mem_compressed_gb = 1.4 + 0.3 * @sin(t * 0.04 + 1.0),
        .mem_wired_gb = 2.6 + 0.1 * @sin(t * 0.07),
        .swap_used_gb = 0.75 + 0.25 * @sin(t * 0.02),
        .mem_pressure = if (seq % 90 >= 70) 1 else 0,
        .gpu_busy = std.math.clamp(0.24 + 0.16 * @sin(t * 0.31) + 0.06 * @sin(t * 1.7), 0.0, 1.0),
        .battery_present = 1,
        .battery_charge = 0.86 - 0.0015 * @as(f32, @floatFromInt(seq % 400)),
        .battery_charging = 0,
        .on_ac = 0,
        .net_rx_bps = 180e3 * (1.0 + @sin(t * 0.45)) + 2.4e6 * @max(0.0, @sin(t * 0.21) - 0.6),
        .net_tx_bps = 40e3 * (1.0 + @sin(t * 0.37 + 2.0)),
        .disk_free_gb = 182.5 - 0.01 * t,
        .disk_total_gb = 494.4,
    };
    s.battery_minutes = s.battery_charge * 420.0;
    var sum: f32 = 0;
    for (0..s.cpu_count) |c| {
        const fc: f32 = @floatFromInt(c);
        const busy: f32 = if (c < s.cpu_e_cores) 0.35 else 0.12; // efficiency cores are numbered first
        const v = busy + 0.25 * @sin(t * (0.3 + 0.07 * fc) + fc * 1.3) + 0.1 * @sin(t * 1.1 + fc);
        s.cpu_core[c] = std.math.clamp(v, 0.02, 0.98);
        sum += s.cpu_core[c];
    }
    s.cpu_total = sum / @as(f32, @floatFromInt(s.cpu_count));

    const names = [_][]const u8{ "Safari", "Xcode", "Argus", "Music", "Terminal", "Finder" };
    const base = [_]f32{ 0.06, 0.04, 0.01, 0.015, 0.008, 0.004 };
    const mem = [_]f32{ 1.8, 2.4, 0.09, 0.35, 0.06, 0.12 };
    var all: [names.len]Proc = undefined;
    for (&all, 0..) |*p, i| {
        const fi: f32 = @floatFromInt(i);
        p.* = .{ .cpu = @max(0.0, base[i] * (1.0 + 0.8 * @sin(t * (0.23 + 0.05 * fi) + fi))), .mem_gb = mem[i] };
        p.setName(names[i]);
    }
    std.mem.sort(Proc, &all, {}, struct {
        fn lt(_: void, a: Proc, b: Proc) bool {
            return a.cpu > b.cpu;
        }
    }.lt);
    s.proc_count = TOP_PROCS;
    @memcpy(&s.procs, all[0..TOP_PROCS]);
    return s;
}

test "synthetic stats are deterministic, plausible and move" {
    const a = synthetic(1);
    const b = synthetic(1);
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&a), std.mem.asBytes(&b));
    const c = synthetic(2);
    try std.testing.expect(a.cpu_total != c.cpu_total);
    for (1..400) |i| {
        const s = synthetic(@intCast(i));
        try std.testing.expect(s.cpu_total > 0 and s.cpu_total < 1);
        try std.testing.expect(s.gpu_busy >= 0 and s.gpu_busy <= 1);
        try std.testing.expect(s.mem_used_gb < s.mem_total_gb);
        try std.testing.expect(s.battery_charge > 0 and s.battery_charge <= 1);
        try std.testing.expect(s.net_rx_bps >= 0 and s.net_tx_bps >= 0);
        for (1..s.proc_count) |p| try std.testing.expect(s.procs[p - 1].cpu >= s.procs[p].cpu);
    }
}

test "process names are ASCII and truncated" {
    var p: Proc = .{};
    p.setName("com.apple.WebKit.WebContent.Helper (GPU)");
    try std.testing.expectEqual(@as(usize, 31), p.getName().len);
    try std.testing.expectEqual(@as(u8, 0), p.name[31]);
    p.setName("Caf\xc3\xa9");
    try std.testing.expectEqualStrings("Caf??", p.getName());
}

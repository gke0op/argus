// ============================================================================
// ARGUS DESKTOP // src/desktop/system_stats.zig
//
// The live system stats behind `// @argus stats` (gpu/argus_stats.zig has the struct).
//
//  - Sampler: one reading of the Mac from public, permission-free calls, turned into loads
//    and rates against the previous reading: host_processor_info (CPU ticks), host_statistics64
//    and sysctl (memory, swap, pressure, core counts, boot time), IOKit (IOAccelerator
//    "Device Utilization %", power sources), getifaddrs (interface byte counters), statfs (the
//    startup volume), libproc (the user's own processes) and NSProcessInfo.thermalState.
//    Nothing is written, nothing goes over the network, nothing asks for a permission.
//  - Feed: a utility-QoS thread that runs the Sampler about once a second while someone wants
//    it (Feed.want, called by a stats theme's every drawn frame) and sleeps on a condition
//    variable otherwise: themes that don't ask, or that are out of sight, cost nothing.
// ============================================================================

const std = @import("std");
const c = std.c;
const as = @import("../gpu/argus_stats.zig");

pub const Stats = as.Stats;

// ---------------------------------------------------------------------------------------------
// The maths, separate from the OS calls so it can be tested.

/// CPU ticks of one core, as host_processor_info reports them (user, system, idle, nice).
/// The counters are 32-bit and wrap (after ~500 days of one core at 100 Hz); differences are
/// taken modulo 2^32, so one wrap between two readings is harmless.
pub const Ticks = [4]u32;

/// Busy fraction (0-1) of a core between two readings: (user + system + nice) / all.
pub fn cpuLoad(prev: Ticks, cur: Ticks) f32 {
    const user = cur[0] -% prev[0];
    const sys = cur[1] -% prev[1];
    const idle = cur[2] -% prev[2];
    const nice = cur[3] -% prev[3];
    const busy = @as(u64, user) + sys + nice;
    const all = busy + idle;
    if (all == 0) return 0;
    return @floatCast(@as(f64, @floatFromInt(busy)) / @as(f64, @floatFromInt(all)));
}

/// Bytes per second from a 32-bit interface counter (if_data's ifi_ibytes / ifi_obytes wrap
/// at 4 GiB; a difference modulo 2^32 is right as long as less than 4 GiB moved in between).
pub fn byteRate(prev: u32, cur: u32, dt_s: f64) f64 {
    if (dt_s <= 0) return 0;
    return @as(f64, @floatFromInt(cur -% prev)) / dt_s;
}

/// A process's share of the whole machine (0-1) from its CPU time before and after, in ns.
pub fn procShare(prev_ns: u64, cur_ns: u64, dt_ns: u64, ncpu: u32) f32 {
    if (dt_ns == 0 or ncpu == 0 or cur_ns < prev_ns) return 0;
    const share = @as(f64, @floatFromInt(cur_ns - prev_ns)) / (@as(f64, @floatFromInt(dt_ns)) * @as(f64, @floatFromInt(ncpu)));
    return @floatCast(@min(share, 1.0));
}

/// kern.memorystatus_vm_pressure_level (1 normal, 2 warn, 4 critical) -> 0, 1, 2.
pub fn pressureLevel(raw: u32) u32 {
    return switch (raw) {
        4 => 2,
        2 => 1,
        else => 0,
    };
}

/// Inserts (share, value) into a list kept sorted by share, highest first, at most N long.
pub fn TopN(comptime N: usize, comptime T: type) type {
    return struct {
        items: [N]T = undefined,
        shares: [N]f32 = undefined,
        len: usize = 0,

        pub fn add(self: *@This(), share: f32, v: T) void {
            var i = self.len;
            if (i == N) {
                if (share <= self.shares[N - 1]) return;
                i = N - 1;
            } else self.len += 1;
            while (i > 0 and self.shares[i - 1] < share) : (i -= 1) {
                self.shares[i] = self.shares[i - 1];
                self.items[i] = self.items[i - 1];
            }
            self.shares[i] = share;
            self.items[i] = v;
        }
    };
}

// ---------------------------------------------------------------------------------------------
// Darwin calls not in std.c.

extern "c" fn host_processor_info(host: c.mach_port_t, flavor: c_int, out_count: *c_uint, out_info: *?[*]c_int, out_info_count: *c_uint) c.kern_return_t;
extern "c" fn host_statistics64(host: c.mach_port_t, flavor: c_int, info: *anyopaque, count: *c_uint) c.kern_return_t;
extern "c" fn proc_listpids(kind: u32, typeinfo: u32, buffer: ?*anyopaque, buffersize: c_int) c_int;
extern "c" fn proc_pid_rusage(pid: c_int, flavor: c_int, buffer: *anyopaque) c_int;
extern "c" fn proc_name(pid: c_int, buffer: [*]u8, buffersize: u32) c_int;
extern "c" fn getifaddrs(out: *?*IfAddrs) c_int;
extern "c" fn freeifaddrs(p: ?*IfAddrs) void;
extern "c" fn statfs(path: [*:0]const u8, buf: *anyopaque) c_int;
extern "c" fn pthread_set_qos_class_self_np(qos: c_uint, relpri: c_int) c_int;

const PROCESSOR_CPU_LOAD_INFO: c_int = 2;
const HOST_VM_INFO64: c_int = 4;
const PROC_UID_ONLY: u32 = 4;
const RUSAGE_INFO_V0: c_int = 0;
const AF_LINK: u8 = 18;
const IFF_UP: c_uint = 0x1;
const IFF_LOOPBACK: c_uint = 0x8;
const IFF_POINTOPOINT: c_uint = 0x10;
const IFF_RUNNING: c_uint = 0x40;
const QOS_CLASS_UTILITY: c_uint = 0x11;

/// struct ifaddrs (<ifaddrs.h>).
const IfAddrs = extern struct {
    next: ?*IfAddrs,
    name: [*:0]const u8,
    flags: c_uint,
    addr: ?*const extern struct { len: u8, family: u8 },
    netmask: ?*anyopaque,
    dstaddr: ?*anyopaque,
    data: ?*const IfData,
};

/// The start of struct if_data (<net/if_var.h>): byte counters at 40 and 44.
const IfData = extern struct {
    type: u8,
    _pad0: [39]u8,
    ibytes: u32,
    obytes: u32,
};

/// The start of struct vm_statistics64 (<mach/vm_statistics.h>), 62 natural_t's in all.
const VmStats = extern struct {
    free_count: u32,
    active_count: u32,
    inactive_count: u32,
    wire_count: u32,
    _a: [72]u8, // zero_fill .. purges (u64s)
    purgeable_count: u32, // @88
    speculative_count: u32,
    _b: [32]u8, // decompressions .. swapouts
    compressor_page_count: u32, // @128
    throttled_count: u32,
    external_page_count: u32,
    internal_page_count: u32, // @140
    _c: [104]u8,
};

/// struct rusage_info_v0 (<sys/resource.h>); times are in mach_absolute_time units.
const RusageV0 = extern struct {
    uuid: [16]u8,
    user_time: u64,
    system_time: u64,
    pkg_idle_wkups: u64,
    interrupt_wkups: u64,
    pageins: u64,
    wired_size: u64,
    resident_size: u64,
    phys_footprint: u64,
    proc_start_abstime: u64,
    proc_exit_abstime: u64,
};

comptime {
    std.debug.assert(@sizeOf(IfAddrs) == 56 and @offsetOf(IfAddrs, "data") == 48);
    std.debug.assert(@offsetOf(IfData, "ibytes") == 40);
    std.debug.assert(@sizeOf(VmStats) == 248 and @offsetOf(VmStats, "purgeable_count") == 88);
    std.debug.assert(@offsetOf(VmStats, "compressor_page_count") == 128 and @offsetOf(VmStats, "internal_page_count") == 140);
    std.debug.assert(@sizeOf(RusageV0) == 96 and @offsetOf(RusageV0, "phys_footprint") == 72);
}

fn sysctlInt(comptime T: type, name: [*:0]const u8) ?T {
    var v: T = 0;
    var len: usize = @sizeOf(T);
    if (c.sysctlbyname(name, &v, &len, null, 0) != 0) return null;
    return v;
}

const GIB: f64 = 1024.0 * 1024.0 * 1024.0;

// CoreFoundation / IOKit / objc, resolved with dlopen like the rest of the app.
const CF = struct {
    const Ref = ?*const anyopaque;
    StringCreate: *const fn (?*anyopaque, [*:0]const u8, u32) callconv(.c) Ref,
    DictGet: *const fn (Ref, Ref) callconv(.c) Ref,
    NumberGet: *const fn (Ref, isize, *anyopaque) callconv(.c) bool,
    BoolGet: *const fn (Ref) callconv(.c) bool,
    ArrayCount: *const fn (Ref) callconv(.c) isize,
    ArrayAt: *const fn (Ref, isize) callconv(.c) Ref,
    Equal: *const fn (Ref, Ref) callconv(.c) bool,
    Release: *const fn (Ref) callconv(.c) void,
    GetTypeID: *const fn (Ref) callconv(.c) usize,
    number_type: usize,
    bool_type: usize,
    // IOKit
    ServiceMatching: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque,
    GetMatchingService: *const fn (c.mach_port_t, ?*anyopaque) callconv(.c) u32,
    CreateProperty: *const fn (u32, Ref, ?*anyopaque, u32) callconv(.c) Ref,
    PSCopyInfo: *const fn () callconv(.c) Ref,
    PSCopyList: *const fn (Ref) callconv(.c) Ref,
    PSDescription: *const fn (Ref, Ref) callconv(.c) Ref,
    PSProviding: *const fn (Ref) callconv(.c) Ref,
    // objc
    msgSend: *const anyopaque,
    processInfo: ?*anyopaque,
    sel_thermal: ?*anyopaque,
    // keys
    k_perf: Ref,
    k_util: Ref,
    k_type: Ref,
    k_internal: Ref,
    k_cur: Ref,
    k_max: Ref,
    k_charging: Ref,
    k_empty: Ref,
    k_full: Ref,
    k_ac: Ref,

    fn load() ?CF {
        const cf = c.dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", .{ .LAZY = true }) orelse return null;
        const io = c.dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", .{ .LAZY = true }) orelse return null;
        const objc = c.dlopen("/usr/lib/libobjc.A.dylib", .{ .LAZY = true }) orelse return null;
        _ = c.dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", .{ .LAZY = true }) orelse return null;
        var r: CF = undefined;
        inline for (.{
            .{ "StringCreate", cf, "CFStringCreateWithCString" }, .{ "DictGet", cf, "CFDictionaryGetValue" },
            .{ "NumberGet", cf, "CFNumberGetValue" },              .{ "BoolGet", cf, "CFBooleanGetValue" },
            .{ "ArrayCount", cf, "CFArrayGetCount" },              .{ "ArrayAt", cf, "CFArrayGetValueAtIndex" },
            .{ "Equal", cf, "CFEqual" },                           .{ "Release", cf, "CFRelease" },
            .{ "GetTypeID", cf, "CFGetTypeID" },                   .{ "ServiceMatching", io, "IOServiceMatching" },
            .{ "GetMatchingService", io, "IOServiceGetMatchingService" },
            .{ "CreateProperty", io, "IORegistryEntryCreateCFProperty" },
            .{ "PSCopyInfo", io, "IOPSCopyPowerSourcesInfo" },     .{ "PSCopyList", io, "IOPSCopyPowerSourcesList" },
            .{ "PSDescription", io, "IOPSGetPowerSourceDescription" },
            .{ "PSProviding", io, "IOPSGetProvidingPowerSourceType" },
            .{ "msgSend", objc, "objc_msgSend" },
        }) |e| @field(r, e[0]) = @ptrCast(@alignCast(c.dlsym(e[1], e[2]) orelse return null));
        const num_tid: *const fn () callconv(.c) usize = @ptrCast(@alignCast(c.dlsym(cf, "CFNumberGetTypeID") orelse return null));
        const bool_tid: *const fn () callconv(.c) usize = @ptrCast(@alignCast(c.dlsym(cf, "CFBooleanGetTypeID") orelse return null));
        r.number_type = num_tid();
        r.bool_type = bool_tid();
        const get_class: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(c.dlsym(objc, "objc_getClass") orelse return null));
        const sel_reg: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(c.dlsym(objc, "sel_registerName") orelse return null));
        const send0: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(r.msgSend));
        r.processInfo = send0(get_class("NSProcessInfo"), sel_reg("processInfo"));
        r.sel_thermal = sel_reg("thermalState");
        inline for (.{
            .{ "k_perf", "PerformanceStatistics" }, .{ "k_util", "Device Utilization %" },
            .{ "k_type", "Type" },                  .{ "k_internal", "InternalBattery" },
            .{ "k_cur", "Current Capacity" },       .{ "k_max", "Max Capacity" },
            .{ "k_charging", "Is Charging" },       .{ "k_empty", "Time to Empty" },
            .{ "k_full", "Time to Full Charge" },   .{ "k_ac", "AC Power" },
        }) |k| @field(r, k[0]) = r.StringCreate(null, k[1], 0x08000100) orelse return null;
        return r;
    }

    fn int(self: *const CF, dict: Ref, key: Ref) ?i64 {
        const v = self.DictGet(dict, key) orelse return null;
        if (self.GetTypeID(v) != self.number_type) return null;
        var out: i64 = 0;
        return if (self.NumberGet(v, 4, &out)) out else null; // kCFNumberSInt64Type
    }

    fn boolean(self: *const CF, dict: Ref, key: Ref) bool {
        const v = self.DictGet(dict, key) orelse return false;
        return self.GetTypeID(v) == self.bool_type and self.BoolGet(v);
    }
};

// ---------------------------------------------------------------------------------------------

const MAX_TRACKED_CPUS = 128;
const MAX_PIDS = 4096;
const MAX_IFACES = 64;
/// A reading this long after the previous one (the feed slept, the Mac slept) starts over:
/// the rates would be averages over the gap, and a byte counter may have wrapped twice.
const MAX_GAP_NS: u64 = 4 * std.time.ns_per_s;

pub const Sampler = struct {
    cf: ?CF = null,
    loaded: bool = false,
    gpu_service: u32 = 0,
    timebase: c.mach_timebase_info_data = .{ .numer = 1, .denom = 1 },
    page_size: u64 = 16384,
    mem_total: u64 = 0,
    p_cores: u32 = 0,
    e_cores: u32 = 0,
    boot_s: i64 = 0,
    uid: u32 = 0,

    has_prev: bool = false,
    prev_abs: u64 = 0,
    ncpu: u32 = 0,
    prev_ticks: [MAX_TRACKED_CPUS]Ticks = undefined,
    prev_n_pids: usize = 0,
    prev_pids: [MAX_PIDS]i32 = undefined,
    prev_cpu: [MAX_PIDS]u64 = undefined, // mach units
    if_n: usize = 0,
    if_names: [MAX_IFACES][16]u8 = undefined,
    if_bytes: [MAX_IFACES][2]u32 = undefined,
    // Scratch for the current reading (kept here, not on the thread's stack).
    pids: [MAX_PIDS]i32 = undefined,
    cpu: [MAX_PIDS]u64 = undefined,

    fn init(self: *Sampler) void {
        self.loaded = true;
        self.cf = CF.load();
        _ = c.mach_timebase_info(&self.timebase);
        self.page_size = sysctlInt(u64, "hw.pagesize") orelse 16384;
        self.mem_total = sysctlInt(u64, "hw.memsize") orelse 0;
        if ((sysctlInt(u32, "hw.nperflevels") orelse 0) >= 2) {
            self.p_cores = sysctlInt(u32, "hw.perflevel0.logicalcpu") orelse 0;
            self.e_cores = sysctlInt(u32, "hw.perflevel1.logicalcpu") orelse 0;
        }
        var boot: c.timeval = undefined;
        var len: usize = @sizeOf(c.timeval);
        if (c.sysctlbyname("kern.boottime", &boot, &len, null, 0) == 0) self.boot_s = boot.sec;
        self.uid = c.getuid();
        if (self.cf) |*cf| {
            self.gpu_service = cf.GetMatchingService(0, cf.ServiceMatching("IOAccelerator"));
        }
    }

    /// Forgets the previous reading: the next `sample` only sets a new baseline.
    pub fn reset(self: *Sampler) void {
        self.has_prev = false;
    }

    fn absToNs(self: *const Sampler, abs: u64) u64 {
        return @intCast(@as(u128, abs) * self.timebase.numer / self.timebase.denom);
    }

    /// Reads the Mac into `out` (all but `seq`). Returns false when this reading is only a
    /// baseline (the first one, or the first after a long gap): loads and rates need two.
    pub fn sample(self: *Sampler, out: *Stats) bool {
        if (!self.loaded) self.init();
        const now_abs = c.mach_absolute_time();
        const dt_ns = if (self.has_prev) self.absToNs(now_abs -% self.prev_abs) else 0;
        const full = self.has_prev and dt_ns > 0 and dt_ns < MAX_GAP_NS;
        const dt_s = @as(f64, @floatFromInt(dt_ns)) / 1e9;
        out.* = .{ .seq = out.seq };
        out.sample_dt = @floatCast(dt_s);

        self.readCpu(out, full);
        self.readMemory(out);
        self.readPower(out);
        self.readNet(out, full, dt_s);
        self.readProcs(out, full, dt_ns);
        self.readMisc(out);

        self.prev_abs = now_abs;
        self.has_prev = true;
        return full;
    }

    fn readCpu(self: *Sampler, out: *Stats, full: bool) void {
        out.cpu_p_cores = self.p_cores;
        out.cpu_e_cores = self.e_cores;
        var n: c_uint = 0;
        var info: ?[*]c_int = null;
        var count: c_uint = 0;
        if (host_processor_info(c.mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) != 0) return;
        const p = info orelse return;
        defer _ = c.vm_deallocate(c.mach_task_self(), @intFromPtr(p), @as(usize, count) * @sizeOf(c_int));
        const ncpu: u32 = @min(n, MAX_TRACKED_CPUS);
        const same = full and ncpu == self.ncpu;
        var busy_sum: f64 = 0;
        for (0..ncpu) |i| {
            var t: Ticks = undefined;
            for (0..4) |k| t[k] = @bitCast(p[i * 4 + k]);
            if (same) {
                const load = cpuLoad(self.prev_ticks[i], t);
                busy_sum += load;
                if (i < as.MAX_CORES) out.cpu_core[i] = load;
            }
            self.prev_ticks[i] = t;
        }
        self.ncpu = ncpu;
        out.cpu_count = @min(ncpu, as.MAX_CORES);
        if (same and ncpu > 0) out.cpu_total = @floatCast(busy_sum / @as(f64, @floatFromInt(ncpu)));
    }

    fn readMemory(self: *Sampler, out: *Stats) void {
        out.mem_total_gb = @floatCast(@as(f64, @floatFromInt(self.mem_total)) / GIB);
        var vm: VmStats = undefined;
        var count: c_uint = @sizeOf(VmStats) / 4;
        if (host_statistics64(c.mach_host_self(), HOST_VM_INFO64, &vm, &count) == 0) {
            const pg: f64 = @floatFromInt(self.page_size);
            const app = @as(f64, @floatFromInt(vm.internal_page_count)) - @as(f64, @floatFromInt(vm.purgeable_count));
            const wired: f64 = @floatFromInt(vm.wire_count);
            const comp: f64 = @floatFromInt(vm.compressor_page_count);
            // Activity Monitor's "Memory Used": app memory + wired + compressed.
            out.mem_used_gb = @floatCast(@max(0.0, app + wired + comp) * pg / GIB);
            out.mem_wired_gb = @floatCast(wired * pg / GIB);
            out.mem_compressed_gb = @floatCast(comp * pg / GIB);
        }
        const Xsw = extern struct { total: u64, avail: u64, used: u64, pagesize: u32, encrypted: u32 };
        var xsw: Xsw = undefined;
        var len: usize = @sizeOf(Xsw);
        if (c.sysctlbyname("vm.swapusage", &xsw, &len, null, 0) == 0)
            out.swap_used_gb = @floatCast(@as(f64, @floatFromInt(xsw.used)) / GIB);
        out.mem_pressure = pressureLevel(sysctlInt(u32, "kern.memorystatus_vm_pressure_level") orelse 1);
    }

    fn readPower(self: *Sampler, out: *Stats) void {
        out.on_ac = 1;
        const cf = &(self.cf orelse return);
        if (self.gpu_service != 0) {
            if (cf.CreateProperty(self.gpu_service, cf.k_perf, null, 0)) |perf| {
                defer cf.Release(perf);
                if (cf.int(perf, cf.k_util)) |u| out.gpu_busy = @floatCast(std.math.clamp(@as(f64, @floatFromInt(u)) / 100.0, 0.0, 1.0));
            }
        }
        const blob = cf.PSCopyInfo() orelse return;
        defer cf.Release(blob);
        if (cf.PSProviding(blob)) |src| out.on_ac = @intFromBool(cf.Equal(src, cf.k_ac));
        const list = cf.PSCopyList(blob) orelse return;
        defer cf.Release(list);
        var i: isize = 0;
        while (i < cf.ArrayCount(list)) : (i += 1) {
            const d = cf.PSDescription(blob, cf.ArrayAt(list, i)) orelse continue;
            const ty = cf.DictGet(d, cf.k_type) orelse continue;
            if (!cf.Equal(ty, cf.k_internal)) continue;
            const cur = cf.int(d, cf.k_cur) orelse continue;
            const max = cf.int(d, cf.k_max) orelse 100;
            out.battery_present = 1;
            out.battery_charge = @floatCast(std.math.clamp(@as(f64, @floatFromInt(cur)) / @as(f64, @floatFromInt(@max(1, max))), 0.0, 1.0));
            out.battery_charging = @intFromBool(cf.boolean(d, cf.k_charging));
            // Minutes to full while charging, to empty on battery, 0 on mains when not charging
            // (full, or held below full by Optimized Charging); -1 while macOS estimates.
            const mins: i64 = if (out.battery_charging != 0) cf.int(d, cf.k_full) orelse -1 else if (out.on_ac == 0) cf.int(d, cf.k_empty) orelse -1 else 0;
            out.battery_minutes = @floatFromInt(if (mins < 0) -1 else mins);
            break;
        }
    }

    fn readNet(self: *Sampler, out: *Stats, full: bool, dt_s: f64) void {
        var head: ?*IfAddrs = null;
        if (getifaddrs(&head) != 0) return;
        defer freeifaddrs(head);
        var rx: f64 = 0;
        var tx: f64 = 0;
        var it = head;
        while (it) |ifa| : (it = ifa.next) {
            const addr = ifa.addr orelse continue;
            const data = ifa.data orelse continue;
            if (addr.family != AF_LINK) continue;
            // Up and running, not loopback, not a point-to-point tunnel (a VPN's utun carries
            // the same bytes as the interface under it).
            if (ifa.flags & (IFF_UP | IFF_RUNNING) != (IFF_UP | IFF_RUNNING) or ifa.flags & (IFF_LOOPBACK | IFF_POINTOPOINT) != 0) continue;
            const name = std.mem.sliceTo(ifa.name, 0);
            if (name.len > 15) continue;
            const slot = self.ifaceSlot(name) orelse continue;
            if (full and slot.known) {
                rx += byteRate(self.if_bytes[slot.i][0], data.ibytes, dt_s);
                tx += byteRate(self.if_bytes[slot.i][1], data.obytes, dt_s);
            }
            self.if_bytes[slot.i] = .{ data.ibytes, data.obytes };
        }
        out.net_rx_bps = @floatCast(rx);
        out.net_tx_bps = @floatCast(tx);
    }

    fn ifaceSlot(self: *Sampler, name: []const u8) ?struct { i: usize, known: bool } {
        for (0..self.if_n) |i| if (std.mem.eql(u8, std.mem.sliceTo(&self.if_names[i], 0), name)) return .{ .i = i, .known = true };
        if (self.if_n == MAX_IFACES) return null;
        const i = self.if_n;
        self.if_n += 1;
        self.if_names[i] = @splat(0);
        @memcpy(self.if_names[i][0..name.len], name);
        return .{ .i = i, .known = false };
    }

    fn readProcs(self: *Sampler, out: *Stats, full: bool, dt_ns: u64) void {
        // Only the user's own processes: libproc refuses other users' (root's included).
        const bytes = proc_listpids(PROC_UID_ONLY, self.uid, &self.pids, @sizeOf(@TypeOf(self.pids)));
        if (bytes <= 0) return;
        var n: usize = @intCast(@divTrunc(bytes, @sizeOf(i32)));
        n = @min(n, MAX_PIDS);
        std.mem.sort(i32, self.pids[0..n], {}, std.sort.asc(i32));
        const Entry = struct { pid: i32, mem: u64 };
        var top: TopN(as.TOP_PROCS, Entry) = .{};
        var kept: usize = 0;
        for (self.pids[0..n]) |pid| {
            if (pid <= 0) continue;
            var ri: RusageV0 = undefined;
            if (proc_pid_rusage(pid, RUSAGE_INFO_V0, &ri) != 0) continue;
            const cpu = ri.user_time +% ri.system_time;
            if (full) {
                // A process started since the last reading spent all its CPU time in between.
                const prev: ?u64 = if (std.sort.binarySearch(i32, self.prev_pids[0..self.prev_n_pids], pid, cmpPid)) |j| self.prev_cpu[j] else if (ri.proc_start_abstime > self.prev_abs) 0 else null;
                if (prev) |p| {
                    const share = procShare(self.absToNs(p), self.absToNs(cpu), dt_ns, self.ncpu);
                    if (share > 0) top.add(share, .{ .pid = pid, .mem = ri.phys_footprint });
                }
            }
            self.pids[kept] = pid;
            self.cpu[kept] = cpu;
            kept += 1;
        }
        @memcpy(self.prev_pids[0..kept], self.pids[0..kept]);
        @memcpy(self.prev_cpu[0..kept], self.cpu[0..kept]);
        self.prev_n_pids = kept;
        out.proc_count = @intCast(top.len);
        for (0..top.len) |i| {
            const p = &out.procs[i];
            p.cpu = top.shares[i];
            p.mem_gb = @floatCast(@as(f64, @floatFromInt(top.items[i].mem)) / GIB);
            var name: [64]u8 = undefined;
            const len = proc_name(top.items[i].pid, &name, name.len);
            p.setName(if (len > 0) name[0..@intCast(len)] else "?");
        }
    }

    fn cmpPid(key: i32, item: i32) std.math.Order {
        return std.math.order(key, item);
    }

    fn readMisc(self: *Sampler, out: *Stats) void {
        var buf: [2168]u8 align(8) = undefined; // struct statfs (64-bit inodes, the arm64 default)
        if (statfs("/", &buf) == 0) {
            const bsize: f64 = @floatFromInt(std.mem.readInt(u32, buf[0..4], .little));
            const blocks: f64 = @floatFromInt(std.mem.readInt(u64, buf[8..16], .little));
            const avail: f64 = @floatFromInt(std.mem.readInt(u64, buf[24..32], .little));
            out.disk_total_gb = @floatCast(blocks * bsize / 1e9);
            out.disk_free_gb = @floatCast(avail * bsize / 1e9);
        }
        var ts: c.timespec = undefined;
        if (self.boot_s > 0 and c.clock_gettime(.REALTIME, &ts) == 0)
            out.uptime_s = @intCast(std.math.clamp(ts.sec - self.boot_s, 0, std.math.maxInt(u32)));
        if (self.cf) |cf| if (cf.processInfo != null) {
            const send: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) isize = @ptrCast(@alignCast(cf.msgSend));
            out.thermal = @intCast(std.math.clamp(send(cf.processInfo, cf.sel_thermal), 0, 3));
        };
    }
};

// ---------------------------------------------------------------------------------------------

/// Samples on its own thread about once a second while wanted; see the header.
pub const Feed = struct {
    mutex: c.pthread_mutex_t = .{},
    cond: c.pthread_cond_t = .{},
    started: bool = false,
    idle: bool = false,
    want_abs: u64 = 0,
    latest: Stats = .{},
    seq: std.atomic.Value(u32) = .init(0),
    sampler: Sampler = .{},
    /// `--perf-log`: the sampling thread's own CPU time, per sample.
    cost_ns: u64 = 0,
    cost_samples: u32 = 0,

    pub const INTERVAL_NS: u64 = std.time.ns_per_s;
    /// With no want for this long (the stats theme's Space went out of sight), the thread sleeps.
    const IDLE_AFTER_NS: u64 = 2 * std.time.ns_per_s;

    /// Called on every frame a stats theme draws: keeps (or starts) the sampling going.
    pub fn want(self: *Feed) void {
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        self.want_abs = c.mach_absolute_time();
        if (!self.started) {
            self.started = true;
            const t = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, run, .{self}) catch {
                self.started = false;
                return;
            };
            t.detach();
        } else if (self.idle) _ = c.pthread_cond_signal(&self.cond);
    }

    /// Copies the latest sample into `dst` when it is newer than what `dst` holds.
    pub fn latestInto(self: *Feed, dst: *Stats) void {
        if (self.seq.load(.acquire) == dst.seq) return;
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        dst.* = self.latest;
    }

    /// Mean CPU time per sample (us) and the number of samples since the last call; resets.
    pub const Cost = struct { us: f64, samples: u32 };

    pub fn takeCost(self: *Feed) Cost {
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        const r: Cost = .{ .us = if (self.cost_samples > 0) @as(f64, @floatFromInt(self.cost_ns)) / 1000.0 / @as(f64, @floatFromInt(self.cost_samples)) else 0, .samples = self.cost_samples };
        self.cost_ns = 0;
        self.cost_samples = 0;
        return r;
    }

    fn sinceNs(self: *Feed, abs: u64) u64 {
        return self.sampler.absToNs(c.mach_absolute_time() -% abs);
    }

    fn run(self: *Feed) void {
        _ = pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
        var next: Stats = .{};
        _ = c.pthread_mutex_lock(&self.mutex);
        while (true) {
            if (self.sampler.loaded and self.sinceNs(self.want_abs) > IDLE_AFTER_NS) {
                self.idle = true;
                _ = c.pthread_cond_wait(&self.cond, &self.mutex);
                self.idle = false;
                self.sampler.reset(); // out of sight for a while: start the rates afresh
                continue;
            }
            _ = c.pthread_mutex_unlock(&self.mutex);
            const t0 = threadCpuNs();
            const full = self.sampler.sample(&next);
            const cost = threadCpuNs() -| t0;
            _ = c.pthread_mutex_lock(&self.mutex);
            self.cost_ns += cost;
            self.cost_samples += 1;
            if (full) {
                next.seq = self.latest.seq +% 1;
                if (next.seq == 0) next.seq = 1;
                self.latest = next;
                self.seq.store(next.seq, .release);
            }
            // Sleep a second (a want() only signals an idle thread, so this isn't cut short).
            var ts: c.timespec = undefined;
            _ = c.clock_gettime(.REALTIME, &ts);
            ts.sec += 1;
            _ = c.pthread_cond_timedwait(&self.cond, &self.mutex, &ts);
        }
    }
};

fn threadCpuNs() u64 {
    var ts: c.timespec = undefined;
    if (c.clock_gettime(.THREAD_CPUTIME_ID, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

/// The app's one feed, shared by every Space that shows a stats theme.
pub var feed: Feed = .{};

// ---------------------------------------------------------------------------------------------

test "cpu ticks to load" {
    try std.testing.expectEqual(@as(f32, 0), cpuLoad(.{ 10, 10, 10, 10 }, .{ 10, 10, 10, 10 }));
    // 30 user + 10 system + 0 nice busy, 60 idle: 40%.
    try std.testing.expectApproxEqAbs(@as(f32, 0.4), cpuLoad(.{ 100, 50, 1000, 7 }, .{ 130, 60, 1060, 7 }), 1e-6);
    try std.testing.expectEqual(@as(f32, 1), cpuLoad(.{ 0, 0, 5, 0 }, .{ 25, 0, 5, 25 }));
    try std.testing.expectEqual(@as(f32, 0), cpuLoad(.{ 0, 0, 5, 0 }, .{ 0, 0, 105, 0 }));
}

test "cpu ticks across a counter wrap" {
    const max = std.math.maxInt(u32);
    // user wraps from 2^32-10 to 20 (30 ticks), idle from 2^32-5 to 25 (30 ticks): 50%.
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), cpuLoad(.{ max - 9, 0, max - 4, 0 }, .{ 20, 0, 25, 0 }), 1e-6);
}

test "byte counters to rates, across a wrap" {
    try std.testing.expectEqual(@as(f64, 500), byteRate(1000, 2000, 2.0));
    try std.testing.expectEqual(@as(f64, 0), byteRate(1000, 1000, 1.0));
    try std.testing.expectEqual(@as(f64, 0), byteRate(1000, 2000, 0));
    // 4 GiB - 100 -> 900: 1000 bytes moved.
    try std.testing.expectEqual(@as(f64, 1000), byteRate(std.math.maxInt(u32) - 99, 900, 1.0));
}

test "process share and top list" {
    // 0.5 s of CPU in 1 s on 8 cores: 1/16 of the machine.
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 16.0), procShare(1_000_000_000, 1_500_000_000, 1_000_000_000, 8), 1e-6);
    try std.testing.expectEqual(@as(f32, 0), procShare(5, 4, 1000, 8)); // pid reused: no negative share
    try std.testing.expectEqual(@as(f32, 1), procShare(0, 100_000_000_000, 1_000_000_000, 8));
    var top: TopN(3, u8) = .{};
    for ([_]f32{ 0.1, 0.5, 0.05, 0.3, 0.7, 0.2 }, 0..) |s, i| top.add(s, @intCast(i));
    try std.testing.expectEqual(@as(usize, 3), top.len);
    try std.testing.expectEqualSlices(u8, &.{ 4, 1, 3 }, &top.items);
    try std.testing.expectEqualSlices(f32, &.{ 0.7, 0.5, 0.3 }, &top.shares);
}

test "memory pressure levels" {
    try std.testing.expectEqual(@as(u32, 0), pressureLevel(1));
    try std.testing.expectEqual(@as(u32, 1), pressureLevel(2));
    try std.testing.expectEqual(@as(u32, 2), pressureLevel(4));
    try std.testing.expectEqual(@as(u32, 0), pressureLevel(0));
}

test "a live sample reads plausible numbers" {
    var s: Sampler = .{};
    var st: Stats = .{};
    try std.testing.expect(!s.sample(&st)); // the first reading is a baseline
    try std.testing.expect(st.mem_total_gb > 1 and st.disk_total_gb > 1 and st.uptime_s > 0);
    const ts: c.timespec = .{ .sec = 0, .nsec = 200 * std.time.ns_per_ms };
    _ = c.nanosleep(&ts, null);
    try std.testing.expect(s.sample(&st));
    try std.testing.expect(st.cpu_count > 0 and st.cpu_count <= as.MAX_CORES);
    try std.testing.expect(st.cpu_total >= 0 and st.cpu_total <= 1);
    try std.testing.expect(st.mem_used_gb > 0 and st.mem_used_gb <= st.mem_total_gb * 1.01);
    try std.testing.expect(st.disk_free_gb <= st.disk_total_gb);
    try std.testing.expect(st.gpu_busy >= 0 and st.gpu_busy <= 1);
    try std.testing.expect(st.sample_dt > 0.1 and st.sample_dt < 1.0);
    try std.testing.expect(st.proc_count <= as.TOP_PROCS);
    for (st.procs[0..st.proc_count]) |p| try std.testing.expect(p.getName().len > 0 and p.cpu > 0 and p.cpu <= 1);
}

// ============================================================================
// ARGUS LINUX // src/argus_linux.zig
//
// A live wallpaper on Linux X11: a Zig theme, compiled in, drawn into a desktop-type window
// (under every normal window, on every workspace) at 30 FPS with the app's 0.008 step.
// Pure Zig 0.17 on raw syscalls: no libc, no X libraries.
//
//   make linux THEME=themes/Cygnus_A.zig && ./argus-linux [--fps 30] [--frames N] [--scale 1]
// ============================================================================

const std = @import("std");
const linux = std.os.linux;
const x11 = @import("linux/x11.zig");
const sandbox = @import("linux/sandbox.zig");
const theme = @import("theme"); // compiled in; exports argus_theme_*
comptime {
    _ = theme;
}

extern fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque;
extern fn argus_theme_deinit(st: ?*anyopaque) callconv(.c) void;

/// Direct path for CPU kernel themes (themes/cpu/argus_kernel.zig, recognised at compile time by
/// their `pub fn draw(frame, gid)`): draw straight into display memory in the display's channel
/// order. Null for SDK themes. (A weak symbol would do this at link time, but LLVM folds
/// `weak_sym != null` to true, so the choice is made here, where it is known for certain.)
const Target = extern struct { px: [*]u32, len: usize, stride: usize, shift: [3]u8 };
const DrawTarget = *const fn (?*anyopaque, *const Target) callconv(.c) void;
const draw_target: ?DrawTarget = if (@hasDecl(theme, "draw")) @extern(DrawTarget, .{ .name = "argus_theme_draw_target" }) else null;
extern fn argus_theme_step(st: ?*anyopaque, dt: f64) callconv(.c) void;
extern fn argus_theme_draw(st: ?*anyopaque, px: [*]u32, len: usize, stride: usize) callconv(.c) void;

const ZIG_TICK_DT: f64 = 0.008; // desktop/frame_rate.zig: one SDK step per frame

fn nowNs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

/// Nanoseconds since `mark`, moving `mark` to now.
fn lap(mark: *u64) u64 {
    const now = nowNs();
    defer mark.* = now;
    return now - mark.*;
}

fn sleepNs(ns: u64) void {
    var req = linux.timespec{ .sec = @intCast(ns / 1_000_000_000), .nsec = @intCast(ns % 1_000_000_000) };
    while (linux.errno(linux.nanosleep(&req, &req)) == .INTR) {}
}

fn readFile(path: []const u8, buf: []u8) ?[]u8 {
    var pz: [4096]u8 = undefined;
    if (path.len >= pz.len) return null;
    @memcpy(pz[0..path.len], path);
    pz[path.len] = 0;
    const rc = linux.open(@ptrCast(&pz), .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var n: usize = 0;
    while (n < buf.len) {
        const r = linux.read(fd, buf[n..].ptr, buf.len - n);
        if (linux.errno(r) != .SUCCESS or r == 0) break;
        n += r;
    }
    return buf[0..n];
}

fn initTheme(w: usize, h: usize, scale: f64) !?*anyopaque {
    const t0 = nowNs();
    const st = argus_theme_init(@intCast(w), @intCast(h), scale) orelse return error.ThemeInitFailed;
    std.debug.print("argus-linux: theme {d}x{d} ready in {d} ms\n", .{ w, h, (nowNs() - t0) / 1_000_000 });
    return st;
}

/// Source column and weight for each output column, 8.8 fixed point, centres aligned.
fn tap(o: usize, sn: usize, dn: usize) struct { lo: u32, hi: u32, w: u32 } {
    const fpos: i64 = @max(0, @as(i64, @intCast(((2 * o + 1) * sn * 256) / (2 * dn))) - 128);
    const lo: u32 = @intCast(@min(sn - 1, @as(usize, @intCast(fpos >> 8))));
    return .{ .lo = lo, .hi = @intCast(@min(sn - 1, lo + 1)), .w = @intCast(fpos & 255) };
}

var x_taps: [8192]struct { lo: u32, hi: u32, w: u32 } = undefined;

/// Bilinear upscale of a [R, G, B, A] frame (8.8 fixed point, pixel centres aligned), split
/// over the cores. Separable: each output row first blends its two source rows (sw pixels),
/// then expands that blended row horizontally (two taps per output pixel instead of four).
fn upscale(src: []const u32, sw: usize, sh: usize, dst: []u32, dw: usize, dh: usize, shift: [3]u5) void {
    if (sw > x_taps.len or dw > x_taps.len) return;
    for (0..dw) |x| {
        const t = tap(x, sw, dw);
        x_taps[x] = .{ .lo = t.lo, .hi = t.hi, .w = t.w };
    }
    const job = UpJob{ .src = src, .sw = sw, .sh = sh, .dst = dst, .dw = dw, .dh = dh, .shift = shift };
    const n = @min(8, std.Thread.getCpuCount() catch 1);
    var pool: [8]?std.Thread = @splat(null);
    for (1..n) |t| pool[t] = std.Thread.spawn(.{}, UpJob.rows, .{ &job, dh * t / n, dh * (t + 1) / n }) catch null;
    job.rows(0, dh / n);
    for (1..n) |t| if (pool[t]) |th| th.join() else job.rows(dh * t / n, dh * (t + 1) / n);
}

const UpJob = struct {
    src: []const u32,
    sw: usize,
    sh: usize,
    dst: []u32,
    dw: usize,
    dh: usize,
    shift: [3]u5, // output bit offset of R, G, B (src is always [R, G, B, A] bytes)

    fn rows(j: *const UpJob, y_begin: usize, y_end: usize) void {
        var mid: [8192][3]u32 = undefined; // the vertically blended source row, x256 per channel
        for (y_begin..y_end) |y| {
            const ty = tap(y, j.sh, j.dh);
            const r0 = j.src[ty.lo * j.sw ..][0..j.sw];
            const r1 = j.src[ty.hi * j.sw ..][0..j.sw];
            for (r0, r1, mid[0..j.sw]) |a, c, *m| {
                inline for (0..3) |ch| {
                    const s = 8 * ch;
                    m[ch] = ((a >> s) & 0xFF) * (256 - ty.w) + ((c >> s) & 0xFF) * ty.w;
                }
            }
            const out = j.dst[y * j.dw ..][0..j.dw];
            for (out, x_taps[0..j.dw]) |*o, t| {
                const l = mid[t.lo];
                const r = mid[t.hi];
                var px: u32 = 0xFF00_0000;
                inline for (0..3) |ch| px |= (((l[ch] * (256 - t.w) + r[ch] * t.w) >> 16) & 0xFF) << j.shift[ch];
                o.* = px;
            }
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var fps: u64 = 30;
    var frames: u64 = 0; // 0: run until killed
    var scale: f64 = 1.0;
    var div: usize = 0; // --render-scale: theme renders at 1/div size; 0 = auto (fit the budget)
    var sandboxed = true; // --sandbox off: run the theme uncaged
    var i: usize = 1;
    while (i + 1 < args.len) : (i += 2) {
        if (std.mem.eql(u8, args[i], "--fps")) fps = try std.fmt.parseInt(u64, args[i + 1], 10)
        else if (std.mem.eql(u8, args[i], "--frames")) frames = try std.fmt.parseInt(u64, args[i + 1], 10)
        else if (std.mem.eql(u8, args[i], "--scale")) scale = try std.fmt.parseFloat(f64, args[i + 1])
        else if (std.mem.eql(u8, args[i], "--render-scale")) div = try std.fmt.parseInt(usize, args[i + 1], 10)
        else if (std.mem.eql(u8, args[i], "--sandbox")) sandboxed = !std.mem.eql(u8, args[i + 1], "off")
        else return error.UnknownArgument;
    }

    // DISPLAY ":N" or ":N.S" (local socket only).
    const disp = init.environ_map.get("DISPLAY") orelse return error.NoDisplay;
    const colon = std.mem.indexOfScalar(u8, disp, ':') orelse return error.BadDisplay;
    const num_end = std.mem.indexOfScalarPos(u8, disp, colon + 1, '.') orelse disp.len;
    const display = try std.fmt.parseInt(u32, disp[colon + 1 .. num_end], 10);

    var xauth_buf: [16384]u8 = undefined;
    var path_buf: [4096]u8 = undefined;
    const xauth_path: ?[]const u8 = init.environ_map.get("XAUTHORITY") orelse if (init.environ_map.get("HOME")) |h|
        std.fmt.bufPrint(&path_buf, "{s}/.Xauthority", .{h}) catch null
    else
        null;
    const cookie = if (xauth_path) |p| (if (readFile(p, &xauth_buf)) |b| x11.findCookie(b, display) else null) else null;

    var c = try x11.Conn.open(display, cookie);
    const w: usize = c.width;
    const h: usize = c.height;

    const win = try c.createWindow();
    const wm_type = try c.internAtom("_NET_WM_WINDOW_TYPE");
    const wm_desktop_type = try c.internAtom("_NET_WM_WINDOW_TYPE_DESKTOP");
    const wm_desktop = try c.internAtom("_NET_WM_DESKTOP");
    try c.changeProperty32(win, wm_type, 4, &.{wm_desktop_type}); // ATOM
    try c.changeProperty32(win, wm_desktop, 6, &.{0xFFFF_FFFF}); // CARDINAL: every workspace
    try c.changePropertyString(win, 39, "Argus"); // WM_NAME
    try c.mapWindow(win);
    const gc = try c.createGC(win);

    var auto = div == 0;
    if (auto) div = 1;
    var rw = w / div;
    var rh = h / div;

    const alloc = std.heap.page_allocator;
    const px = try alloc.alloc(u32, w * h); // what the window shows
    const small = try alloc.alloc(u32, w * h); // the theme's render when div > 1
    const scratch = try alloc.alloc(u8, c.max_req_bytes);
    var shm = c.shmInit(w, h); // null: frames go through the socket (PutImage)
    std.debug.print("argus-linux: {d}x{d} depth {d}, {d} FPS, {s}\n", .{ w, h, c.depth, fps, if (shm != null) "MIT-SHM" else "PutImage" });

    // Everything the host needs is open: cage the process before any theme code runs.
    if (sandboxed) {
        const rep = sandbox.lockdown(.errno);
        std.debug.print("argus-linux: sandbox: seccomp {s}, landlock {s}\n", .{ if (rep.seccomp) "on" else "UNAVAILABLE", if (rep.landlock_abi > 0) "on" else "unavailable" });
        if (!rep.seccomp) return error.SandboxUnavailable; // never run a theme uncaged by surprise
    } else std.debug.print("argus-linux: sandbox OFF (--sandbox off): the theme runs with your full permissions\n", .{});
    var st = try initTheme(rw, rh, scale);

    const period = 1_000_000_000 / fps;
    var next = nowNs();
    var work_ns: u64 = 0;
    var probe_ns: u64 = 0;
    var probe: [8]u64 = @splat(0);
    var f: u64 = 0;
    var stage: [6]u64 = @splat(0); // step, draw, upscale, wait, fill, send
    const shift = [3]u5{ c.red_shift, c.green_shift, c.blue_shift };
    while (frames == 0 or f < frames) : (f += 1) {
        const t0 = nowNs();
        var mark = t0;
        argus_theme_step(st, ZIG_TICK_DT);
        stage[0] += lap(&mark);

        // The display's own memory (MIT-SHM), once the server is done reading the last frame.
        // shmWait also reports X errors (drainErrors would eat the completion event).
        const dst: ?[]u32 = if (shm) |*s| blk: {
            try c.shmWait(s);
            break :blk s.mem;
        } else null;
        stage[3] += lap(&mark);

        // Shortest route: a kernel theme draws, or the upscale writes, straight into display
        // memory in display order. SDK themes draw [R, G, B, A] into px and get reordered below.
        var direct = false;
        if (div == 1) {
            if (draw_target != null and dst != null) {
                draw_target.?(st, &.{ .px = dst.?.ptr, .len = dst.?.len, .stride = w, .shift = .{ shift[0], shift[1], shift[2] } });
                direct = true;
            } else {
                @memset(px, 0);
                argus_theme_draw(st, px.ptr, px.len, w);
            }
            stage[1] += lap(&mark);
        } else {
            if (draw_target == null) @memset(small[0 .. rw * rh], 0); // kernels write every pixel
            argus_theme_draw(st, small.ptr, rw * rh, rw);
            stage[1] += lap(&mark);
            if (dst) |d| {
                upscale(small[0 .. rw * rh], rw, rh, d, w, h, shift);
                direct = true;
            } else upscale(small[0 .. rw * rh], rw, rh, px, w, h, .{ 0, 8, 16 });
            stage[2] += lap(&mark);
        }

        if (shm) |*s| {
            if (!direct) c.shmFill(s, px);
            stage[4] += lap(&mark);
            try c.shmPut(s, win, gc);
        } else {
            try c.putFrame(win, gc, px, w, h, scratch);
            c.drainErrors();
        }
        stage[5] += lap(&mark);
        const dt_ns = mark - t0;
        work_ns += dt_ns;
        // Auto render scale: frames 2..9 measure the cost (frame 1 pays first-touch); if their
        // median (shared vCPUs spike) is over 85% of the budget, drop to the 1/div that fits ~70%
        // of it (cost ~ pixels ~ 1/div^2).
        if (auto and f >= 1 and f < 9) probe[f - 1] = dt_ns;
        if (auto and f == 8) {
            std.mem.sort(u64, &probe, {}, std.sort.asc(u64));
            probe_ns = 8 * ((probe[3] + probe[4]) / 2); // 8 x median, as the code below expects a sum
            auto = probe_ns / 8 > period * 85 / 100 and div < 4; // one verdict per scale
        }
        if (auto and f == 8) {
            const ratio = @as(f64, @floatFromInt(probe_ns / 8)) / (0.7 * @as(f64, @floatFromInt(period)));
            div = @min(4, @max(div + 1, @as(usize, @intFromFloat(@ceil(@as(f64, @floatFromInt(div)) * @sqrt(ratio))))));
            argus_theme_deinit(st);
            rw = w / div;
            rh = h / div;
            st = try initTheme(rw, rh, scale);
            std.debug.print("argus-linux: {d:.1} ms/frame over budget, rendering at 1/{d} ({d}x{d}) and upscaling\n", .{ @as(f64, @floatFromInt(probe_ns / 8)) / 1e6, div, rw, rh });
            work_ns = 0;
            stage = @splat(0);
            probe_ns = 0;
            f = 0; // stats restart at the new scale
            next = nowNs();
        }
        next += period;
        const now = nowNs();
        if (next > now) sleepNs(next - now) else next = now; // late: don't try to catch up
    }
    std.debug.print("argus-linux: {d} frames, avg work {d:.2} ms/frame ({d:.0}% of the {d} FPS budget)\n", .{
        f, @as(f64, @floatFromInt(work_ns)) / @as(f64, @floatFromInt(@max(f, 1))) / 1e6,
        100.0 * @as(f64, @floatFromInt(work_ns)) / @as(f64, @floatFromInt(@max(f, 1) * period)), fps,
    });
    const names = [_][]const u8{ "step", "draw", "upscale", "wait", "fill", "send" };
    std.debug.print("argus-linux: ms/frame", .{});
    for (names, stage) |n, s| std.debug.print("  {s} {d:.2}", .{ n, @as(f64, @floatFromInt(s)) / @as(f64, @floatFromInt(@max(f, 1))) / 1e6 });
    std.debug.print("\n", .{});
}

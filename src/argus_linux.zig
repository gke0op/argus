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
comptime {
    _ = @import("theme"); // exports argus_theme_* (sdk.exportTheme)
}

extern fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque;
extern fn argus_theme_deinit(st: ?*anyopaque) callconv(.c) void;
extern fn argus_theme_step(st: ?*anyopaque, dt: f64) callconv(.c) void;
extern fn argus_theme_draw(st: ?*anyopaque, px: [*]u32, len: usize, stride: usize) callconv(.c) void;

const ZIG_TICK_DT: f64 = 0.008; // desktop/frame_rate.zig: one SDK step per frame

fn nowNs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
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

/// Bilinear upscale of a [R, G, B, A] frame (8.8 fixed point, pixel centres aligned).
fn upscale(src: []const u32, sw: usize, sh: usize, dst: []u32, dw: usize, dh: usize) void {
    for (0..@min(dw, x_taps.len)) |x| {
        const t = tap(x, sw, dw);
        x_taps[x] = .{ .lo = t.lo, .hi = t.hi, .w = t.w };
    }
    for (0..dh) |y| {
        const ty = tap(y, sh, dh);
        const y0: usize = ty.lo;
        const y1: usize = ty.hi;
        const wy = ty.w;
        for (0..dw) |x| {
            const x0: usize = x_taps[x].lo;
            const x1: usize = x_taps[x].hi;
            const wx = x_taps[x].w;
            const a = src[y0 * sw + x0];
            const b = src[y0 * sw + x1];
            const cc = src[y1 * sw + x0];
            const d = src[y1 * sw + x1];
            var out: u32 = 0xFF00_0000;
            inline for (.{ 0, 8, 16 }) |sh_| {
                const top = ((a >> sh_) & 0xFF) * (256 - wx) + ((b >> sh_) & 0xFF) * wx;
                const bot = ((cc >> sh_) & 0xFF) * (256 - wx) + ((d >> sh_) & 0xFF) * wx;
                out |= (((top * (256 - wy) + bot * wy) >> 16) & 0xFF) << sh_;
            }
            dst[y * dw + x] = out;
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var fps: u64 = 30;
    var frames: u64 = 0; // 0: run until killed
    var scale: f64 = 1.0;
    var div: usize = 0; // --render-scale: theme renders at 1/div size; 0 = auto (fit the budget)
    var i: usize = 1;
    while (i + 1 < args.len) : (i += 2) {
        if (std.mem.eql(u8, args[i], "--fps")) fps = try std.fmt.parseInt(u64, args[i + 1], 10)
        else if (std.mem.eql(u8, args[i], "--frames")) frames = try std.fmt.parseInt(u64, args[i + 1], 10)
        else if (std.mem.eql(u8, args[i], "--scale")) scale = try std.fmt.parseFloat(f64, args[i + 1])
        else if (std.mem.eql(u8, args[i], "--render-scale")) div = try std.fmt.parseInt(usize, args[i + 1], 10)
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
    var st = try initTheme(rw, rh, scale);

    const alloc = std.heap.page_allocator;
    const px = try alloc.alloc(u32, w * h); // what the window shows
    const small = try alloc.alloc(u32, w * h); // the theme's render when div > 1
    const scratch = try alloc.alloc(u8, c.max_req_bytes);
    std.debug.print("argus-linux: {d}x{d} depth {d}, {d} FPS\n", .{ w, h, c.depth, fps });

    const period = 1_000_000_000 / fps;
    var next = nowNs();
    var work_ns: u64 = 0;
    var probe_ns: u64 = 0;
    var f: u64 = 0;
    while (frames == 0 or f < frames) : (f += 1) {
        const t0 = nowNs();
        argus_theme_step(st, ZIG_TICK_DT);
        if (div == 1) {
            @memset(px, 0);
            argus_theme_draw(st, px.ptr, px.len, w);
        } else {
            @memset(small[0 .. rw * rh], 0);
            argus_theme_draw(st, small.ptr, rw * rh, rw);
            upscale(small[0 .. rw * rh], rw, rh, px, w, h);
        }
        try c.putFrame(win, gc, px, w, h, scratch);
        c.drainErrors();
        const dt_ns = nowNs() - t0;
        work_ns += dt_ns;
        // Auto render scale: frames 2..9 measure the cost (frame 1 pays first-touch); over 85%
        // of the budget, drop to the 1/div that fits ~70% of it (cost ~ pixels ~ 1/div^2).
        if (auto and f >= 1 and f < 9) probe_ns += dt_ns;
        if (auto and f == 8) auto = probe_ns / 8 > period * 85 / 100 and div < 4; // one verdict per scale
        if (auto and f == 8) {
            const ratio = @as(f64, @floatFromInt(probe_ns / 8)) / (0.7 * @as(f64, @floatFromInt(period)));
            div = @min(4, @max(div + 1, @as(usize, @intFromFloat(@ceil(@as(f64, @floatFromInt(div)) * @sqrt(ratio))))));
            argus_theme_deinit(st);
            rw = w / div;
            rh = h / div;
            st = try initTheme(rw, rh, scale);
            std.debug.print("argus-linux: {d:.1} ms/frame over budget, rendering at 1/{d} ({d}x{d}) and upscaling\n", .{ @as(f64, @floatFromInt(probe_ns / 8)) / 1e6, div, rw, rh });
            work_ns = 0;
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
}

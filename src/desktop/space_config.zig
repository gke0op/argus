// ============================================================================
// ARGUS DESKTOP // src/desktop/space_config.zig
//
// Per-Space state machine, Native Retina (1920x1200 @2x) resolution constants,
// .zig -> .dylib hot-compiler, and out-of-process Watchdog verifier.
// ============================================================================

const std = @import("std");


// Native @2x Retina resolution for .dylib shaders & baked wallpapers (1920x1200)
pub const NATIVE_W: usize = 1920;
pub const NATIVE_H: usize = 1200;
pub const NATIVE_PIXELS: usize = NATIVE_W * NATIVE_H;
pub const NATIVE_SCALE: f64 = 2.0;

// @2x Retina Panorama Popover (680x98 logical points -> 1360x196 Retina pixels). The Settings
// view uses the same box (popover_layout.zig).
pub const POPOVER_W: usize = 680;
pub const POPOVER_H: usize = 98;
pub const POPOVER_SCALE: usize = 2;
pub const POPOVER_BMP_W: usize = POPOVER_W * POPOVER_SCALE;
pub const POPOVER_BMP_H: usize = POPOVER_H * POPOVER_SCALE;
pub const POPOVER_PIXELS: usize = POPOVER_BMP_W * POPOVER_BMP_H;

pub const SPACE_LIST_TOP: f64 = 34.0;
pub const SPACE_ROW_STEP: f64 = 81.5;

pub const MAX_SPACES: usize = 16;

pub const DEFAULT_STATE_PATH = ".argus_spaces.conf";
pub const ZIG_017_BIN = ".toolchain/zig";

pub var g_io: std.Io = undefined;

pub fn romanNumeral(n_1based: usize) []const u8 {
    const table = [_][]const u8{
        "I", "II", "III", "IV", "V", "VI", "VII", "VIII",
        "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI",
    };
    if (n_1based >= 1 and n_1based <= table.len) return table[n_1based - 1];
    return "I";
}

pub const CustomThemeRenderFn = *const fn (
    pixels: [*]u32,
    width: u32,
    height: u32,
    phase: f64,
    step_count: u64,
) callconv(.c) void;

pub const ThemeInitFn = *const fn (w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque;
pub const ThemeDeinitFn = *const fn (state: ?*anyopaque) callconv(.c) void;
pub const ThemeStepFn = *const fn (state: ?*anyopaque, dt: f64) callconv(.c) void;
pub const ThemeDrawFn = *const fn (state: ?*anyopaque, pixels: [*]u32, buf_len: usize, stride: usize) callconv(.c) void;
pub const ThemeAllocsAfterInitFn = *const fn () callconv(.c) usize;
pub const ThemeHasNaNFn = *const fn (state: ?*anyopaque) callconv(.c) bool;

pub const SpaceMode = enum(u8) {
    passthrough = 0, // Leaves standard macOS wallpaper untouched on this Space
    picture = 3, // Drag-and-dropped / picked Picture wallpaper on this Space
    custom_shader = 5, // Live hot-compiled .zig theme (.dylib via dlopen)

    pub fn label(self: SpaceMode) []const u8 {
        return switch (self) {
            .passthrough => "macOS Default",
            .picture => "Picture Wallpaper",
            .custom_shader => "Custom_Shader.zig",
        };
    }

    pub fn shortBadge(self: SpaceMode) []const u8 {
        return switch (self) {
            .passthrough => "Off",
            .picture => "Picture",
            .custom_shader => "Shader",
        };
    }

    pub fn modeName(self: SpaceMode) []const u8 {
        return switch (self) {
            .passthrough => "passthrough",
            .picture => "picture",
            .custom_shader => "custom_shader",
        };
    }

    pub fn fromModeName(s: []const u8) ?SpaceMode {
        if (std.mem.eql(u8, s, "passthrough")) return .passthrough;
        if (std.mem.eql(u8, s, "picture")) return .picture;
        if (std.mem.eql(u8, s, "custom_shader")) return .custom_shader;
        // Built-in modes from pre-SDK configs load as an untouched Space.
        if (std.mem.eql(u8, s, "magnetar_gr") or std.mem.eql(u8, s, "kronos_wave") or
            std.mem.eql(u8, s, "code_terminal")) return .passthrough;
        return null;
    }

    pub fn next(self: SpaceMode) SpaceMode {
        return switch (self) {
            .passthrough => .custom_shader,
            .custom_shader => .picture,
            .picture => .passthrough,
        };
    }
};

/// Runs inside the isolated `--verify-dylib` child process (or fallback in-process check)
/// to ensure a newly compiled `.dylib` does not panic, segfault, overrun row stride canaries,
/// produce NaN/Inf, or allocate after `init()`.
pub fn verifyDylibSafety(dylib_z: [:0]const u8) bool {
    const handle = std.c.dlopen(dylib_z.ptr, .{ .NOW = true }) orelse return false;
    defer _ = std.c.dlclose(handle);

    const fn_init: ?ThemeInitFn = if (std.c.dlsym(handle, "argus_theme_init")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_deinit: ?ThemeDeinitFn = if (std.c.dlsym(handle, "argus_theme_deinit")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_step: ?ThemeStepFn = if (std.c.dlsym(handle, "argus_theme_step")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_draw: ?ThemeDrawFn = if (std.c.dlsym(handle, "argus_theme_draw")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_allocs_after: ?ThemeAllocsAfterInitFn = if (std.c.dlsym(handle, "argus_theme_allocs_after_init")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_has_nan: ?ThemeHasNaNFn = if (std.c.dlsym(handle, "argus_theme_has_nan")) |p| @ptrCast(@alignCast(p)) else null;
    const fn_stateless: ?CustomThemeRenderFn = if (std.c.dlsym(handle, "argus_render_theme")) |p| @ptrCast(@alignCast(p)) else null;

    const is_stateful = (fn_init != null and fn_deinit != null and fn_step != null and fn_draw != null);
    if (!is_stateful and fn_stateless == null) return false;

    const alloc = std.heap.page_allocator;
    const test_w: usize = 320;
    const test_h: usize = 200;
    const pad: usize = 8;
    const stride: usize = test_w + pad;
    const canary: u32 = 0xDEAD_BEEF;

    const buf = alloc.alloc(u32, stride * test_h) catch return false;
    defer alloc.free(buf);
    @memset(buf, canary);

    if (is_stateful) {
        const st = fn_init.?(@intCast(test_w), @intCast(test_h), NATIVE_SCALE) orelse return false;
        defer fn_deinit.?(st);

        fn_step.?(st, 0.008);
        fn_draw.?(st, buf.ptr, buf.len, stride);

        if (fn_has_nan) |nan_f| {
            if (nan_f(st)) return false;
        }
        if (fn_allocs_after) |after_f| {
            if (after_f() != 0) return false;
        }
        for (0..test_h) |y| {
            for (test_w..stride) |x| {
                if (buf[y * stride + x] != canary) return false;
            }
        }
    } else if (fn_stateless) |render_fn| {
        render_fn(buf.ptr, @intCast(test_w), @intCast(test_h), 0.1, 1);
    }

    return true;
}

/// Zig + Metal hybrids: themes with a Metal port (src/gpu/) are built through their export
/// wrapper, so the GPU presenter can read their tables. On by default; `--cpu` turns it off.
pub var gpu_ports = true;

/// Set by the app: compiles a `.metal` theme source and reports whether it is loadable, so a
/// broken edit never replaces a working theme. Null (tests, harness) accepts any source.
pub var metal_validate: ?*const fn (src: []const u8, path: []const u8) bool = null;
// Themes built on the Kerr-disk engine (src/gpu/bh_*), drawn by its GPU path.
const GPU_PORT_THEMES = [_][]const u8{ "Majestic_Glutton.zig", "Gargantua.zig", "Cygnus_A.zig", "J0834.zig", "PG1426.zig" };

fn isGpuPortTheme(path: []const u8) bool {
    const base = std.Io.Dir.path.basename(path);
    for (GPU_PORT_THEMES) |t| if (std.mem.eql(u8, base, t)) return true;
    return false;
}
const GPU_PORT_ROOT = "-Mroot=src/gpu/bh_export.zig";

/// Themes that were renamed: a saved Space that names the old file loads the new one from the
/// same folder (and is saved under the new name).
const RENAMED_THEMES = [_][2][]const u8{
    .{ "Opus_Black_Hole.zig", "Majestic_Glutton.zig" }, // the owner's quasar artwork
    // Model names left the theme names (credits stay in NOTICE.md and the headers).
    .{ "Opus_Quasar.zig", "Majestic_Glutton.zig" },
    .{ "H1821.zig", "Majestic_Glutton.zig" }, // the real name stays with the real quasars
    .{ "Opus_Cygnus_A.zig", "Cygnus_A.zig" },
    .{ "Opus_J0834.zig", "J0834.zig" },
    .{ "Opus_PG1426.zig", "PG1426.zig" },
    .{ "Opus_Gargantua.zig", "Gargantua.zig" },
    .{ "Opus_Night_Tide.metal", "Night_Tide.metal" },
    .{ "Opus_Coral_Reef.metal", "Coral_Reef.metal" },
    .{ "Opus_Coral_Reef.zig", "Coral_Reef.zig" },
    .{ "Opus_Orion_Nebula.metal", "Orion_Nebula.metal" },
};

/// `path` with a renamed theme's old file name replaced by its new one; otherwise `path`.
pub fn renamedThemePath(path: []const u8, buf: []u8) []const u8 {
    const base = std.Io.Dir.path.basename(path);
    for (RENAMED_THEMES) |r| {
        if (!std.mem.eql(u8, base, r[0])) continue;
        const dir = path[0 .. path.len - base.len];
        if (dir.len + r[1].len > buf.len) return path;
        @memcpy(buf[0..dir.len], dir);
        @memcpy(buf[dir.len..][0..r[1].len], r[1]);
        return buf[0 .. dir.len + r[1].len];
    }
    return path;
}

test "renamed themes: saved Spaces naming an old theme file load the new one from the same folder" {
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings("/a/b/themes/Majestic_Glutton.zig", renamedThemePath("/a/b/themes/Opus_Black_Hole.zig", &buf));
    try std.testing.expectEqualStrings("themes/Majestic_Glutton.zig", renamedThemePath("themes/Opus_Black_Hole.zig", &buf));
    try std.testing.expectEqualStrings("/a/b/themes/Majestic_Glutton.zig", renamedThemePath("/a/b/themes/Opus_Quasar.zig", &buf));
    try std.testing.expectEqualStrings("/a/b/themes/Majestic_Glutton.zig", renamedThemePath("/a/b/themes/H1821.zig", &buf));
    try std.testing.expectEqualStrings("/a/b/themes/Cygnus_A.zig", renamedThemePath("/a/b/themes/Opus_Cygnus_A.zig", &buf));
    try std.testing.expectEqualStrings("/a/b/themes/Night_Tide.metal", renamedThemePath("/a/b/themes/Opus_Night_Tide.metal", &buf));
    try std.testing.expectEqualStrings("/a/b/themes/Orion_Nebula.metal", renamedThemePath("/a/b/themes/Opus_Orion_Nebula.metal", &buf));
    try std.testing.expectEqualStrings("themes/Echo.zig", renamedThemePath("themes/Echo.zig", &buf));
}

/// The app's bundle identifier (Argus.app/Contents/Info.plist): also the LaunchAgent label and
/// the name of the dylib cache folder.
pub const BUNDLE_ID = "io.github.gke0op.argus";

const S_IFMT: u16 = 0o170000;
const S_IFDIR: u16 = 0o040000;
const S_IFREG: u16 = 0o100000;

/// `path` itself (a symlink is not followed) is a `kind` (S_IFDIR/S_IFREG) owned by this user
/// with none of the `forbid` permission bits set.
fn ownedPrivately(path: [:0]const u8, kind: u16, forbid: u16) bool {
    var st: std.c.Stat = undefined;
    if (std.c.fstatat(std.c.AT.FDCWD, path.ptr, &st, std.c.AT.SYMLINK_NOFOLLOW) != 0) return false;
    return (st.mode & S_IFMT) == kind and st.uid == std.c.getuid() and (st.mode & forbid) == 0;
}

/// Per-user folder for compiled and cached theme dylibs: ~/Library/Caches/<bundle id>, mode 0700.
/// Never /tmp: anyone on the Mac can write there and cache names follow from public theme
/// source, so a planted dylib would be loaded into Argus. Null if it can't be made private.
pub fn dylibCacheDir(buf: *[512]u8) ?[:0]const u8 {
    const home = std.c.getenv("HOME") orelse return null;
    return cacheDirUnder(std.mem.span(home), buf);
}

fn cacheDirUnder(home: []const u8, buf: *[512]u8) ?[:0]const u8 {
    const dir = std.fmt.bufPrintSentinel(buf, "{s}/Library/Caches/" ++ BUNDLE_ID, .{home}, 0) catch return null;
    std.Io.Dir.cwd().createDirPath(g_io, dir[0 .. dir.len - BUNDLE_ID.len - 1]) catch {};
    _ = std.c.mkdir(dir.ptr, 0o700);
    if (ownedPrivately(dir, S_IFDIR, 0o077)) return dir;
    // Ours but open to others (an old build, a umask): close it. Anyone else's: refuse.
    if (!ownedPrivately(dir, S_IFDIR, 0) or std.c.chmod(dir.ptr, 0o700) != 0) return null;
    return if (ownedPrivately(dir, S_IFDIR, 0o077)) dir else null;
}

/// A cache entry is used only if it is a regular file owned by this user that nobody else can
/// write (the folder is private too; this also refuses a symlink or a copied-in foreign file).
fn cacheEntryUsable(path: [:0]const u8) bool {
    return ownedPrivately(path, S_IFREG, 0o022);
}

/// Unlike /tmp, ~/Library/Caches is never emptied for us, and live reload adds an entry per save:
/// at app start, drop entries unused for 30 days (a cache hit refreshes the date) and per-load
/// copies a crash left behind.
pub fn pruneDylibCache() void {
    var dir_buf: [512]u8 = undefined;
    const dir_path = dylibCacheDir(&dir_buf) orelse return;
    pruneDylibCacheIn(dir_path, std.Io.Clock.real.now(g_io).nanoseconds);
}

fn pruneDylibCacheIn(dir_path: []const u8, now_ns: i96) void {
    const max_age_ns: i96 = 30 * std.time.ns_per_day;
    var dir = std.Io.Dir.cwd().openDir(g_io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(g_io);
    var it = dir.iterate();
    while (it.next(g_io) catch null) |e| {
        if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".dylib")) continue;
        const stale = if (std.mem.startsWith(u8, e.name, "load_"))
            true // a live load deletes its copy right after dlopen
        else if (std.mem.startsWith(u8, e.name, "argus_theme_")) blk: {
            const st = dir.statFile(g_io, e.name, .{}) catch continue;
            break :blk now_ns - st.mtime.nanoseconds > max_age_ns;
        } else false;
        if (stale) dir.deleteFile(g_io, e.name) catch {};
    }
}

test "dylib cache: private per-user folder; entries must be ours and not writable by others" {
    g_io = std.testing.io;
    var home_buf: [128]u8 = undefined;
    const home = try std.fmt.bufPrint(&home_buf, "/tmp/argus_cache_test_{d}", .{std.c.getpid()});
    defer std.Io.Dir.cwd().deleteTree(g_io, home) catch {};
    var buf: [512]u8 = undefined;
    const dir = cacheDirUnder(home, &buf).?;
    try std.testing.expect(std.mem.endsWith(u8, dir, "/Library/Caches/" ++ BUNDLE_ID));
    try std.testing.expect(ownedPrivately(dir, S_IFDIR, 0o077));

    // Opened up to everyone: tightened back to 0700 on the next use.
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(dir.ptr, 0o777));
    try std.testing.expect(cacheDirUnder(home, &buf) != null);
    try std.testing.expect(ownedPrivately(dir, S_IFDIR, 0o077));

    var entry_buf: [600]u8 = undefined;
    const entry = try std.fmt.bufPrintSentinel(&entry_buf, "{s}/argus_theme_1.dylib", .{dir}, 0);
    try std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = entry, .data = "x" });
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(entry.ptr, 0o644));
    try std.testing.expect(cacheEntryUsable(entry));
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(entry.ptr, 0o666)); // writable by others
    try std.testing.expect(!cacheEntryUsable(entry));
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(entry.ptr, 0o664)); // by the group
    try std.testing.expect(!cacheEntryUsable(entry));

    // A symlink is refused even when it points at a good file.
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(entry.ptr, 0o644));
    var link_buf: [600]u8 = undefined;
    const link = try std.fmt.bufPrintSentinel(&link_buf, "{s}/argus_theme_2.dylib", .{dir}, 0);
    try std.Io.Dir.cwd().symLink(g_io, entry, link, .{});
    try std.testing.expect(!cacheEntryUsable(link));
    try std.testing.expect(!cacheEntryUsable("/tmp/argus_no_such_entry.dylib"));

    // Pruning: an entry 31 days old and a crashed run's load copy go, a fresh entry stays.
    var load_buf: [600]u8 = undefined;
    const load = try std.fmt.bufPrintSentinel(&load_buf, "{s}/load_1_sp0_g1.dylib", .{dir}, 0);
    try std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = load, .data = "x" });
    const day: i96 = std.time.ns_per_day;
    const now = std.Io.Clock.real.now(g_io).nanoseconds;
    pruneDylibCacheIn(dir, now);
    try std.testing.expect(cacheEntryUsable(entry));
    try std.testing.expect(!cacheEntryUsable(load));
    pruneDylibCacheIn(dir, now + 31 * day);
    try std.testing.expect(!cacheEntryUsable(entry));

    // A cache folder that is a symlink (say, to a shared folder) is refused.
    var home2_buf: [128]u8 = undefined;
    const home2 = try std.fmt.bufPrint(&home2_buf, "/tmp/argus_cache_test2_{d}", .{std.c.getpid()});
    defer std.Io.Dir.cwd().deleteTree(g_io, home2) catch {};
    var caches_buf: [256]u8 = undefined;
    const caches = try std.fmt.bufPrint(&caches_buf, "{s}/Library/Caches", .{home2});
    try std.Io.Dir.cwd().createDirPath(g_io, caches);
    var target_buf: [256]u8 = undefined;
    const target = try std.fmt.bufPrint(&target_buf, "{s}/shared", .{home2});
    try std.Io.Dir.cwd().createDirPath(g_io, target);
    var dlink_buf: [256]u8 = undefined;
    const dlink = try std.fmt.bufPrint(&dlink_buf, "{s}/" ++ BUNDLE_ID, .{caches});
    try std.Io.Dir.cwd().symLink(g_io, target, dlink, .{ .is_directory = true });
    try std.testing.expect(cacheDirUnder(home2, &buf) == null);
}

/// Precompiled themes that `make release` ships inside the app, relative to the app's folder
/// (the working directory). Named like the /tmp cache, by source hash.
pub const BUNDLED_THEMES_DIR = "Argus.app/Contents/Resources/prebuilt";

/// Why the last Zig theme compile could not run (the app turns it into a note).
pub const ZigStatus = enum { ok, missing, wrong_version };
pub var zig_status: ZigStatus = .ok;
/// `zig version` output when `zig_status` is `.wrong_version`.
pub var zig_found_buf: [32]u8 = undefined;
pub var zig_found_len: usize = 0;

/// Wyhash of a theme's whole source file (0 if unreadable or empty); the GPU build of a
/// Kerr-disk theme gets its own key.
pub fn themeSourceHash(path: []const u8, gpu_port: bool) u64 {
    var file = std.Io.Dir.cwd().openFile(g_io, path, .{}) catch return 0;
    defer file.close(g_io);
    var reader = file.reader(g_io, &.{});
    var hasher = std.hash.Wyhash.init(0xA460_5017);
    var chunk: [16384]u8 = undefined;
    var total: usize = 0;
    while (true) {
        const n = reader.interface.readSliceShort(&chunk) catch return 0;
        hasher.update(chunk[0..n]);
        total += n;
        if (n < chunk.len) break;
    }
    if (total == 0) return 0;
    var h = hasher.final();
    if (gpu_port) h ^= 0x6770_755F_706F_7274; // separate cache entry for the GPU build
    return h;
}

pub fn bundledThemePath(src_hash: u64, buf: []u8) ?[]const u8 {
    return std.fmt.bufPrint(buf, BUNDLED_THEMES_DIR ++ "/argus_theme_{x}.dylib", .{src_hash}) catch null;
}

/// The Zig to compile themes with: ./.toolchain/zig (`make zig`), else `zig` on PATH, else
/// Homebrew's (an app opened from Finder gets launchd's PATH, which has no Homebrew).
fn zigBin() []const u8 {
    if (std.Io.Dir.cwd().access(g_io, ZIG_017_BIN, .{})) |_| return ZIG_017_BIN else |_| {}
    if (onPath()) return "zig";
    for ([_][]const u8{ "/opt/homebrew/bin/zig", "/usr/local/bin/zig" }) |cand| {
        if (std.Io.Dir.cwd().access(g_io, cand, .{})) |_| return cand else |_| {}
    }
    return "zig";
}

fn onPath() bool {
    const path_env = std.mem.span(std.c.getenv("PATH") orelse return false);
    var it = std.mem.tokenizeScalar(u8, path_env, ':');
    var buf: [1024]u8 = undefined;
    while (it.next()) |dir| {
        const cand = std.fmt.bufPrint(&buf, "{s}/zig", .{dir}) catch continue;
        if (std.Io.Dir.cwd().access(g_io, cand, .{})) |_| return true else |_| {}
    }
    return false;
}

/// After a failed compile: is Zig missing, or the wrong version? (Sets `zig_status`.)
fn diagnoseZig(zig_bin: []const u8) void {
    const alloc = std.heap.page_allocator;
    const res = std.process.run(alloc, g_io, .{ .argv = &[_][]const u8{ zig_bin, "version" } }) catch {
        zig_status = .missing;
        return;
    };
    defer alloc.free(res.stdout);
    defer alloc.free(res.stderr);
    const v = std.mem.trim(u8, res.stdout, " \n\r\t");
    if (std.mem.startsWith(u8, v, "0.17.")) return;
    zig_status = .wrong_version;
    zig_found_len = @min(v.len, zig_found_buf.len);
    @memcpy(zig_found_buf[0..zig_found_len], v[0..zig_found_len]);
}

/// Compiles a `.zig` theme to a `.dylib` at `out_z` with install name `iname` (the Kerr-disk GPU
/// build when `gpu_port`). Sets `zig_status` when Zig itself is the problem.
pub fn buildThemeDylib(path: []const u8, out_z: [:0]const u8, iname: []const u8, gpu_port: bool) bool {
    zig_status = .ok;
    var emit_buf: [280]u8 = undefined;
    const emit_arg = std.fmt.bufPrint(&emit_buf, "-femit-bin={s}", .{out_z}) catch return false;
    var mtheme_buf: [530]u8 = undefined;
    const mtheme_arg = std.fmt.bufPrint(&mtheme_buf, "-Mtheme={s}", .{path}) catch return false;
    const zig_bin = zigBin();
    const cpu_argv = [_][]const u8{ zig_bin, "build-lib", path, "-dynamic", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", emit_arg, "-install_name", iname };
    const gpu_argv = [_][]const u8{ zig_bin, "build-lib", "-dynamic", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", emit_arg, "-install_name", iname, "--dep", "theme", GPU_PORT_ROOT, "-O", "ReleaseFast", mtheme_arg };
    const alloc = std.heap.page_allocator;
    const res = std.process.run(alloc, g_io, .{
        .argv = if (gpu_port) &gpu_argv else &cpu_argv,
    }) catch {
        zig_status = .missing;
        return false;
    };
    defer alloc.free(res.stdout);
    defer alloc.free(res.stderr);
    switch (res.term) {
        .exited => |code| if (code == 0) return true,
        else => {},
    }
    diagnoseZig(zig_bin);
    return false;
}

/// Watchdog isolation: if ./argus-desktop or Argus.app/Contents/MacOS/Argus exists, probe the
/// compiled .dylib in a child process BEFORE dlopen-ing it into Argus.app!
pub fn verifyInChild(dylib_z: [:0]const u8) bool {
    const watchdog_bin: ?[]const u8 = if (std.Io.Dir.cwd().access(g_io, "argus-desktop", .{})) |_|
        "./argus-desktop"
    else |_| if (std.Io.Dir.cwd().access(g_io, "Argus.app/Contents/MacOS/Argus", .{})) |_|
        "Argus.app/Contents/MacOS/Argus"
    else |_|
        null;
    const wbin = watchdog_bin orelse return verifyDylibSafety(dylib_z);
    const alloc = std.heap.page_allocator;
    const wres = std.process.run(alloc, g_io, .{
        .argv = &[_][]const u8{ wbin, "--verify-dylib", dylib_z },
    }) catch return false;
    defer alloc.free(wres.stdout);
    defer alloc.free(wres.stderr);
    return switch (wres.term) {
        .exited => |code| code == 0,
        else => false,
    };
}

/// `make release`: compiles `path` (and its Kerr-disk GPU build, if it has one) into `out_dir`
/// under the names the loader looks for, verifying each in a child process. Prints one line
/// per dylib; false on any failure.
pub fn precompileTheme(path: []const u8, out_dir: []const u8) bool {
    std.Io.Dir.cwd().createDirPath(g_io, out_dir) catch return false;
    const variants = [_]bool{ false, true };
    for (variants) |gpu_port| {
        if (gpu_port and !isGpuPortTheme(path)) continue;
        const h = themeSourceHash(path, gpu_port);
        if (h == 0) return false;
        var out_buf: [600]u8 = undefined;
        const out_z = std.fmt.bufPrintSentinel(&out_buf, "{s}/argus_theme_{x}.dylib", .{ out_dir, h }, 0) catch return false;
        var iname_buf: [128]u8 = undefined;
        const iname = std.fmt.bufPrint(&iname_buf, "@rpath/argus_theme_{x}.dylib", .{h}) catch return false;
        if (!buildThemeDylib(path, out_z, iname, gpu_port)) {
            std.debug.print("precompile: {s}{s}: build failed (zig: {s})\n", .{ path, if (gpu_port) " [gpu]" else "", @tagName(zig_status) });
            return false;
        }
        if (!verifyInChild(out_z)) {
            std.debug.print("precompile: {s}{s}: verify failed\n", .{ path, if (gpu_port) " [gpu]" else "" });
            return false;
        }
        std.debug.print("precompile: {s}{s} -> {s}\n", .{ path, if (gpu_port) " [gpu]" else "", std.Io.Dir.path.basename(out_z) });
    }
    return true;
}

test "theme source hash: streams the whole file, equal to one-shot Wyhash" {
    g_io = std.testing.io;
    var buf: [200000]u8 = undefined;
    for (&buf, 0..) |*b, i| b.* = @truncate(i *% 2654435761 >> 7);
    try std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = "/tmp/argus_hash_test.zig", .data = &buf });
    try std.testing.expectEqual(std.hash.Wyhash.hash(0xA460_5017, &buf), themeSourceHash("/tmp/argus_hash_test.zig", false));
    // Past the old 128 KiB read: an edit at the tail changes the key.
    buf[buf.len - 1] +%= 1;
    try std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = "/tmp/argus_hash_test2.zig", .data = &buf });
    try std.testing.expect(themeSourceHash("/tmp/argus_hash_test.zig", false) != themeSourceHash("/tmp/argus_hash_test2.zig", false));
    try std.testing.expect(themeSourceHash("/tmp/argus_hash_test.zig", false) != themeSourceHash("/tmp/argus_hash_test.zig", true));
    try std.testing.expectEqual(@as(u64, 0), themeSourceHash("/tmp/argus_no_such_theme.zig", false));
}

pub const SpaceConfig = struct {
    space_id: u64 = 0,
    index_1based: usize = 1,
    mode: SpaceMode = .passthrough,

    label_buf: [128]u8 = @splat(0),
    label_len: usize = 0,

    path_buf: [512]u8 = @splat(0),
    path_len: usize = 0,

    // Retained CGImageRef for Picture & bare-texture Panorama preview
    cg_image: ?*anyopaque = null,
    // Dedicated per-Space NSWindow & CALayer bound via SkyLight CGSMoveWindowsToManagedSpace
    desktop_win: ?*anyopaque = null,
    desktop_layer: ?*anyopaque = null,
    bound_space_id: u64 = 0,
    hidden_for_passthrough: bool = false,

    // Live hot-compiled .zig shader (.dylib handle + C-ABI render function pointers + file mtime)
    dylib_handle: ?*anyopaque = null,
    custom_render_fn: ?CustomThemeRenderFn = null,
    theme_state: ?*anyopaque = null,
    theme_deinit_fn: ?ThemeDeinitFn = null,
    theme_step_fn: ?ThemeStepFn = null,
    theme_draw_fn: ?ThemeDrawFn = null,
    theme_has_nan_fn: ?ThemeHasNaNFn = null,
    render_w: usize = NATIVE_W,
    render_h: usize = NATIVE_H,
    render_scale: f64 = NATIVE_SCALE,
    dylib_gen: u32 = 0,
    last_mtime: i96 = 0,
    /// A Metal-only theme (`.metal`): drawn entirely on the GPU by the app's presenter.
    metal_theme: bool = false,

    pub fn setLabel(self: *SpaceConfig, s: []const u8) void {
        const n = @min(self.label_buf.len, s.len);
        @memcpy(self.label_buf[0..n], s[0..n]);
        self.label_len = n;
    }

    pub fn getLabel(self: *const SpaceConfig) []const u8 {
        if (self.label_len > 0) return self.label_buf[0..self.label_len];
        return self.mode.label();
    }

    pub fn setPath(self: *SpaceConfig, s: []const u8) void {
        const n = @min(self.path_buf.len, s.len);
        @memcpy(self.path_buf[0..n], s[0..n]);
        self.path_len = n;
    }

    pub fn getPath(self: *const SpaceConfig) []const u8 {
        return self.path_buf[0..self.path_len];
    }

    pub fn unloadShader(self: *SpaceConfig) void {
        if (self.theme_state) |old_st| {
            if (self.theme_deinit_fn) |deinit_f| deinit_f(old_st);
            self.theme_state = null;
        }
        if (self.dylib_handle) |old_h| {
            _ = std.c.dlclose(old_h);
            self.dylib_handle = null;
        }
        self.theme_deinit_fn = null;
        self.theme_step_fn = null;
        self.theme_draw_fn = null;
        self.theme_has_nan_fn = null;
        self.custom_render_fn = null;
        self.metal_theme = false;
    }

    /// Loads a Metal-only theme: no dylib, the app compiles and runs it on the GPU.
    fn loadMetalTheme(self: *SpaceConfig, path: []const u8) bool {
        var buf: [131072]u8 = undefined;
        const src = std.Io.Dir.cwd().readFile(g_io, path, &buf) catch return false;
        if (std.mem.indexOf(u8, src, "argus_draw") == null) return false;
        if (metal_validate) |validate| {
            if (!validate(src, path)) return false;
        }
        if (std.Io.Dir.cwd().statFile(g_io, path, .{})) |st| {
            self.last_mtime = st.mtime.nanoseconds;
        } else |_| {}
        self.unloadShader();
        self.dylib_gen +%= 1;
        self.metal_theme = true;
        self.mode = .custom_shader;
        self.setPath(path);
        self.setLabel(std.Io.Dir.path.basename(path));
        return true;
    }

    /// Hot-compiles a standalone `.zig` file exporting either the stateful Argus Theme SDK
    /// (`argus_theme_init`/`step`/`draw`/`deinit`) or stateless `argus_render_theme` into a native
    /// `aarch64-macos` `.dylib` using Zig 0.17.0, verifies it in an isolated watchdog subprocess
    /// first, and then loads its symbols via `dlopen` / `dlsym` at native 1920x1200 Retina resolution.
    pub fn compileAndLoadShader(self: *SpaceConfig, space_idx: usize, path: []const u8) bool {
        if (std.mem.endsWith(u8, path, ".metal")) return self.loadMetalTheme(path);
        zig_status = .ok;
        if (std.Io.Dir.cwd().statFile(g_io, path, .{})) |st| {
            self.last_mtime = st.mtime.nanoseconds;
        } else |_| {}

        self.dylib_gen +%= 1;
        var dir_buf: [512]u8 = undefined;
        const cache_dir = dylibCacheDir(&dir_buf) orelse return false;
        var dylib_buf: [600]u8 = undefined;
        // PID in the path: the live app, tests and harness must never overwrite each other's loaded dylibs.
        const dylib_z = std.fmt.bufPrintSentinel(&dylib_buf, "{s}/load_{d}_sp{d}_g{d}.dylib", .{
            cache_dir,
            std.c.getpid(),
            space_idx,
            self.dylib_gen,
        }, 0) catch return false;
        // The loaded image stays mapped; the per-load copy is not needed after dlopen.
        defer _ = std.c.unlink(dylib_z.ptr);

        const gpu_port = gpu_ports and isGpuPortTheme(path);

        // Content-addressed verified .dylib cache: hash source content so unchanged shaders
        // across app restarts or multiple Spaces skip `zig build-lib` and `--verify-dylib`!
        const src_hash = themeSourceHash(path, gpu_port);
        var cache_buf: [600]u8 = undefined;
        const cache_path: ?[:0]const u8 = if (src_hash != 0)
            std.fmt.bufPrintSentinel(&cache_buf, "{s}/argus_theme_{x}.dylib", .{ cache_dir, src_hash }, 0) catch null
        else
            null;
        var bundled_buf: [256]u8 = undefined;
        const bundled_path: ?[]const u8 = if (src_hash != 0) bundledThemePath(src_hash, &bundled_buf) else null;

        // A theme shipped precompiled inside the app (`make release`, verified there) needs no
        // Zig on this Mac; then the verified cache from an earlier run (only if it is still ours
        // alone); then a fresh compile.
        var loaded_prebuilt = false;
        const usable_cache: ?[]const u8 = if (cache_path) |cp| (if (cacheEntryUsable(cp)) cp else null) else null;
        for ([_]?[]const u8{ bundled_path, usable_cache }, [_][]const u8{ "bundled", "cached" }) |maybe, how| {
            const src = maybe orelse continue;
            if (std.Io.Dir.cwd().copyFile(src, std.Io.Dir.cwd(), dylib_z, g_io, .{})) |_| {
                loaded_prebuilt = true;
                if (std.mem.eql(u8, how, "cached")) _ = std.c.utimes(cache_path.?.ptr, null); // in use: not pruned
                std.debug.print("argus: {s}: {s} dylib\n", .{ path, how });
                break;
            } else |_| {}
        }

        if (!loaded_prebuilt) {
            // dyld dedupes dlopen() by LC_ID_DYLIB install name, NOT by file path. The default install
            // name is the emit path, so two different themes built to the same /tmp path would make
            // dlopen() silently return the FIRST theme's image. Make it unique per source content.
            var iname_buf: [128]u8 = undefined;
            const iname = (if (src_hash != 0)
                std.fmt.bufPrint(&iname_buf, "@rpath/argus_theme_{x}.dylib", .{src_hash})
            else
                std.fmt.bufPrint(&iname_buf, "@rpath/argus_theme_p{d}_s{d}_g{d}.dylib", .{ std.c.getpid(), space_idx, self.dylib_gen })) catch return false;

            if (!buildThemeDylib(path, dylib_z, iname, gpu_port)) {
                std.debug.print("argus: {s}: compile failed (zig: {s})\n", .{ path, @tagName(zig_status) });
                return false;
            }
            if (!verifyInChild(dylib_z)) return false;
            std.debug.print("argus: {s}: compiled\n", .{path});

            // Cache the verified .dylib for instant multi-Space & cold-start reuse
            if (cache_path) |cp| {
                if (std.Io.Dir.cwd().copyFile(dylib_z, std.Io.Dir.cwd(), cp, g_io, .{})) |_| {
                    _ = std.c.chmod(cp.ptr, 0o700); // whatever the umask, usable next time
                } else |_| {}
            }
        }

        const handle = std.c.dlopen(dylib_z.ptr, .{ .NOW = true }) orelse return false;

        const fn_init: ?ThemeInitFn = if (std.c.dlsym(handle, "argus_theme_init")) |p| @ptrCast(@alignCast(p)) else null;
        const fn_deinit: ?ThemeDeinitFn = if (std.c.dlsym(handle, "argus_theme_deinit")) |p| @ptrCast(@alignCast(p)) else null;
        const fn_step: ?ThemeStepFn = if (std.c.dlsym(handle, "argus_theme_step")) |p| @ptrCast(@alignCast(p)) else null;
        const fn_draw: ?ThemeDrawFn = if (std.c.dlsym(handle, "argus_theme_draw")) |p| @ptrCast(@alignCast(p)) else null;
        const fn_has_nan: ?ThemeHasNaNFn = if (std.c.dlsym(handle, "argus_theme_has_nan")) |p| @ptrCast(@alignCast(p)) else null;
        const fn_stateless: ?CustomThemeRenderFn = if (std.c.dlsym(handle, "argus_render_theme")) |p| @ptrCast(@alignCast(p)) else null;

        const is_stateful = (fn_init != null and fn_deinit != null and fn_step != null and fn_draw != null);
        if (!is_stateful and fn_stateless == null) {
            _ = std.c.dlclose(handle);
            return false;
        }

        var new_state: ?*anyopaque = null;
        if (is_stateful) {
            new_state = fn_init.?(@intCast(NATIVE_W), @intCast(NATIVE_H), NATIVE_SCALE) orelse {
                _ = std.c.dlclose(handle);
                return false;
            };
        }

        // Clean up previous dylib state before swapping
        self.unloadShader();

        self.dylib_handle = handle;
        self.theme_state = new_state;
        self.theme_deinit_fn = fn_deinit;
        self.theme_step_fn = fn_step;
        self.theme_draw_fn = fn_draw;
        self.theme_has_nan_fn = fn_has_nan;
        self.custom_render_fn = fn_stateless;
        self.render_w = NATIVE_W;
        self.render_h = NATIVE_H;
        self.render_scale = NATIVE_SCALE;
        self.mode = .custom_shader;
        self.setPath(path);
        self.setLabel(std.Io.Dir.path.basename(path));
        return true;
    }
};

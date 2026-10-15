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

// @2x Retina Panorama Popover (680x98 logical points -> 1360x196 Retina pixels)
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
pub var metal_validate: ?*const fn (src: []const u8, label: []const u8) bool = null;
const GPU_PORT_THEME = "Opus_Black_Hole.zig";
const GPU_PORT_ROOT = "-Mroot=src/gpu/bh_export.zig";

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
            if (!validate(src, std.Io.Dir.path.basename(path))) return false;
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
        if (std.Io.Dir.cwd().statFile(g_io, path, .{})) |st| {
            self.last_mtime = st.mtime.nanoseconds;
        } else |_| {}

        self.dylib_gen +%= 1;
        var dylib_buf: [256]u8 = undefined;
        var emit_buf: [280]u8 = undefined;
        // PID in the path: the live app, tests and harness must never overwrite each other's loaded dylibs.
        const dylib_z = std.fmt.bufPrintSentinel(&dylib_buf, "/tmp/argus_shader_{d}_sp{d}_g{d}.dylib", .{
            std.c.getpid(),
            space_idx,
            self.dylib_gen,
        }, 0) catch return false;

        const gpu_port = gpu_ports and std.mem.eql(u8, std.Io.Dir.path.basename(path), GPU_PORT_THEME);

        // Content-addressed verified .dylib cache: hash source content so unchanged shaders
        // across app restarts or multiple Spaces skip `zig build-lib` and `--verify-dylib`!
        var src_hash: u64 = 0;
        var cache_buf: [256]u8 = undefined;
        var cache_path: ?[]const u8 = null;
        var hash_read_buf: [131072]u8 = undefined;
        if (std.Io.Dir.cwd().readFile(g_io, path, &hash_read_buf)) |src_bytes| {
            if (src_bytes.len > 0) {
                src_hash = std.hash.Wyhash.hash(0xA460_5017, src_bytes);
                if (gpu_port) src_hash ^= 0x6770_755F_706F_7274; // separate cache entry for the GPU build
                // v2: v1 cache entries carry path-derived install names that collide across themes.
                if (std.fmt.bufPrint(&cache_buf, "/tmp/argus_cache_v2_{x}.dylib", .{src_hash})) |cp| {
                    cache_path = cp;
                } else |_| {}
            }
        } else |_| {}

        var loaded_from_cache = false;
        if (cache_path) |cp| {
            if (std.Io.Dir.cwd().copyFile(cp, std.Io.Dir.cwd(), dylib_z, g_io, .{})) |_| {
                loaded_from_cache = true;
            } else |_| {}
        }

        if (!loaded_from_cache) {
            const emit_arg = std.fmt.bufPrint(&emit_buf, "-femit-bin={s}", .{dylib_z}) catch return false;
            // dyld dedupes dlopen() by LC_ID_DYLIB install name, NOT by file path. The default install
            // name is the emit path, so two different themes built to the same /tmp path would make
            // dlopen() silently return the FIRST theme's image. Make it unique per source content.
            var iname_buf: [128]u8 = undefined;
            const iname_arg = (if (src_hash != 0)
                std.fmt.bufPrint(&iname_buf, "@rpath/argus_theme_{x}.dylib", .{src_hash})
            else
                std.fmt.bufPrint(&iname_buf, "@rpath/argus_theme_p{d}_s{d}_g{d}.dylib", .{ std.c.getpid(), space_idx, self.dylib_gen })) catch return false;

            const zig_bin: []const u8 = if (std.Io.Dir.cwd().access(g_io, ZIG_017_BIN, .{})) |_|
                ZIG_017_BIN
            else |_|
                "zig";

            const alloc = std.heap.page_allocator;
            var mtheme_buf: [530]u8 = undefined;
            const mtheme_arg = std.fmt.bufPrint(&mtheme_buf, "-Mtheme={s}", .{path}) catch return false;
            const cpu_argv = [_][]const u8{ zig_bin, "build-lib", path, "-dynamic", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", emit_arg, "-install_name", iname_arg };
            const gpu_argv = [_][]const u8{ zig_bin, "build-lib", "-dynamic", "-O", "ReleaseFast", "-target", "aarch64-macos", "-lc", emit_arg, "-install_name", iname_arg, "--dep", "theme", GPU_PORT_ROOT, "-O", "ReleaseFast", mtheme_arg };
            const res = std.process.run(alloc, g_io, .{
                .argv = if (gpu_port) &gpu_argv else &cpu_argv,
            }) catch return false;
            defer alloc.free(res.stdout);
            defer alloc.free(res.stderr);

            switch (res.term) {
                .exited => |code| if (code != 0) return false,
                else => return false,
            }

            // Watchdog isolation: if ./argus-desktop or Argus.app/Contents/MacOS/Argus exists,
            // probe the compiled .dylib in a child process BEFORE dlopen-ing it into Argus.app!
            const watchdog_bin: ?[]const u8 = if (std.Io.Dir.cwd().access(g_io, "argus-desktop", .{})) |_|
                "./argus-desktop"
            else |_| if (std.Io.Dir.cwd().access(g_io, "Argus.app/Contents/MacOS/Argus", .{})) |_|
                "Argus.app/Contents/MacOS/Argus"
            else |_|
                null;

            if (watchdog_bin) |wbin| {
                const wres = std.process.run(alloc, g_io, .{
                    .argv = &[_][]const u8{ wbin, "--verify-dylib", dylib_z },
                }) catch return false;
                defer alloc.free(wres.stdout);
                defer alloc.free(wres.stderr);
                switch (wres.term) {
                    .exited => |code| if (code != 0) return false,
                    else => return false,
                }
            } else {
                if (!verifyDylibSafety(dylib_z)) return false;
            }

            // Cache the verified .dylib for instant multi-Space & cold-start reuse
            if (cache_path) |cp| {
                std.Io.Dir.cwd().copyFile(dylib_z, std.Io.Dir.cwd(), cp, g_io, .{}) catch {};
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

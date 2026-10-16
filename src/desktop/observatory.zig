// ============================================================================
// ARGUS DESKTOP // src/desktop/observatory.zig
//
// Per-Space state for the multi-Space wallpaper engine: isolated native 1920x1200
// (@2x Retina) theme buffers, Mission Control order reconciliation, and SDK theme dispatch.
// ============================================================================

const std = @import("std");
const sc = @import("space_config.zig");

pub const NATIVE_W = sc.NATIVE_W;
pub const NATIVE_H = sc.NATIVE_H;
pub const NATIVE_PIXELS = sc.NATIVE_PIXELS;
pub const POPOVER_PIXELS = sc.POPOVER_PIXELS;
pub const MAX_SPACES = sc.MAX_SPACES;
pub const PREVIEW_W: usize = 480;
pub const PREVIEW_H: usize = 300;
pub const SpaceConfig = sc.SpaceConfig;
pub const SpaceMode = sc.SpaceMode;

/// Zeroes `buf` by mapping fresh zero pages over its whole pages (memset only the partial
/// pages at the ends), so a reset buffer costs no memory until something draws into it.
/// A 9 MB memset per theme load committed every Space's canvas, even for GPU-drawn Spaces.
fn zeroRelease(buf: []u8) void {
    const page = std.heap.page_size_min;
    const base = @intFromPtr(buf.ptr);
    const start = std.mem.alignForward(usize, base, page);
    const end = std.mem.alignBackward(usize, base + buf.len, page);
    if (end <= start) return @memset(buf, 0);
    @memset(buf[0 .. start - base], 0);
    @memset(buf[end - base ..], 0);
    const got = std.c.mmap(@ptrFromInt(start), end - start, .{ .READ = true, .WRITE = true }, .{ .TYPE = .PRIVATE, .FIXED = true, .ANONYMOUS = true }, -1, 0);
    if (got == std.c.MAP_FAILED) @memset(buf[start - base .. end - base], 0);
}

pub const Observatory = struct {
    paused: bool = false,
    spin_mult: f64 = 1.0,
    phase_accum: f64 = 0.0,
    last_compute_us: f64 = 0.0,

    // Dynamically discovered macOS Desktop Spaces (never hardcoded!)
    spaces: [MAX_SPACES]SpaceConfig,
    n_spaces: usize = 1,
    active_space_idx: usize = 0,
    active_space_id: u64 = 0,
    drag_hover_idx: ?usize = null,
    dragged_theme_mode: ?SpaceMode = null,
    drag_mouse_x: f64 = 0.0,
    drag_mouse_y: f64 = 0.0,

    space_native_pixels: [MAX_SPACES][NATIVE_PIXELS]u32,
    /// Menu previews of GPU-drawn Spaces (PREVIEW_W x PREVIEW_H): the menu draws them ~200 px
    /// wide, so they don't need a 9 MB canvas each. Untouched until a GPU Space previews.
    preview_pixels: [MAX_SPACES][PREVIEW_W * PREVIEW_H]u32,
    popover_pixels: [POPOVER_PIXELS]u32,

    pub fn init(allocator: std.mem.Allocator) !*Observatory {
        const self = try allocator.create(Observatory);
        self.paused = false;
        self.spin_mult = 1.0;
        self.phase_accum = 0.0;
        self.last_compute_us = 0.0;
        self.n_spaces = 1;
        self.active_space_idx = 0;
        self.active_space_id = 0;
        self.drag_hover_idx = null;
        self.dragged_theme_mode = null;
        self.drag_mouse_x = 0.0;
        self.drag_mouse_y = 0.0;

        self.initSpacesDefault();
        @memset(&self.popover_pixels, 0x00000000);
        // space_native_pixels is deliberately NOT touched here: the app's page_allocator returns
        // zero-filled pages, and touching all MAX_SPACES buffers would commit ~74 MB for Spaces that
        // never animate. Every shader load resets its own buffer instead.
        return self;
    }

    /// Fills a Space's isolated buffer with an alpha-0 sentinel. SDK themes always write alpha 0xFF,
    /// so any theme that skips its background fill by probing pixels is forced to repaint after a
    /// shader (re)load, instead of inheriting stale pixels from the previous theme.
    pub fn resetSpaceNativeBuffer(self: *Observatory, space_idx: usize) void {
        if (space_idx >= MAX_SPACES) return;
        zeroRelease(std.mem.sliceAsBytes(&self.space_native_pixels[space_idx]));
    }

    /// Compile + load a `.zig` shader into a Space AND reset its isolated buffer on success.
    /// This is the only path the app should use to (re)load a shader.
    pub fn loadShaderIntoSpace(self: *Observatory, space_idx: usize, path: []const u8) bool {
        if (space_idx >= MAX_SPACES) return false;
        if (!self.spaces[space_idx].compileAndLoadShader(space_idx, path)) return false;
        self.resetSpaceNativeBuffer(space_idx);
        return true;
    }

    pub const SpaceOrderSyncResult = struct {
        order_changed: bool = false,
        moved_mask: u16 = 0,
    };

    /// Reconciles `self.spaces[0..n_spaces]` with the live left-to-right Mission Control order
    /// reported by SkyLight (`discovered_ids`), moving each `SpaceConfig` with its `space_id`
    /// so user-rearranged Spaces keep their assigned themes/windows and neighbor indices stay exact.
    pub fn syncSpaceOrderByIds(
        self: *Observatory,
        discovered_ids: []const u64,
        active_id: u64,
    ) SpaceOrderSyncResult {
        const count = @min(discovered_ids.len, MAX_SPACES);
        if (count == 0) return .{};

        const old_n = @min(self.n_spaces, MAX_SPACES);
        var same_order = (count == old_n);
        if (same_order) {
            for (0..count) |idx| {
                if (self.spaces[idx].space_id != discovered_ids[idx]) {
                    same_order = false;
                    break;
                }
            }
        }

        if (same_order) {
            self.active_space_id = active_id;
            for (0..count) |idx| {
                if (self.spaces[idx].space_id == active_id) {
                    self.active_space_idx = idx;
                    break;
                }
            }
            return .{ .order_changed = false, .moved_mask = 0 };
        }

        var claimed: [MAX_SPACES]bool = @splat(false);
        var new_spaces: [MAX_SPACES]SpaceConfig = undefined;
        var moved_mask: u16 = 0;

        for (0..count) |new_idx| {
            const sid = discovered_ids[new_idx];
            var found_old: ?usize = null;
            for (0..old_n) |old_idx| {
                if (!claimed[old_idx] and self.spaces[old_idx].space_id == sid) {
                    found_old = old_idx;
                    break;
                }
            }
            if (found_old) |old_idx| {
                claimed[old_idx] = true;
                new_spaces[new_idx] = self.spaces[old_idx];
                new_spaces[new_idx].index_1based = new_idx + 1;
                if (old_idx != new_idx) {
                    moved_mask |= (@as(u16, 1) << @intCast(new_idx));
                }
            } else {
                new_spaces[new_idx] = .{
                    .space_id = sid,
                    .index_1based = new_idx + 1,
                    .mode = .passthrough,
                };
                moved_mask |= (@as(u16, 1) << @intCast(new_idx));
            }
        }

        for (0..old_n) |old_idx| {
            if (!claimed[old_idx]) {
                self.spaces[old_idx].unloadShader();
            }
        }

        for (count..MAX_SPACES) |idx| {
            new_spaces[idx] = .{
                .space_id = 0,
                .index_1based = idx + 1,
                .mode = .passthrough,
            };
        }

        self.spaces = new_spaces;
        self.n_spaces = count;
        self.active_space_id = active_id;
        for (0..count) |idx| {
            if (self.spaces[idx].space_id == active_id) {
                self.active_space_idx = idx;
                break;
            }
        }

        // Any slot whose occupant changed must have its per-Space native buffer reset if it holds
        // a custom shader so probe-based background-skip heuristics never inherit stale pixels.
        for (0..count) |idx| {
            if ((moved_mask & (@as(u16, 1) << @intCast(idx))) != 0) {
                if (self.spaces[idx].mode == .custom_shader) {
                    self.resetSpaceNativeBuffer(idx);
                }
            }
        }

        return .{ .order_changed = true, .moved_mask = moved_mask };
    }

    pub fn deinit(self: *Observatory, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }

    /// Every Space starts untouched; the app loads its default theme on first launch.
    pub fn initSpacesDefault(self: *Observatory) void {
        for (0..MAX_SPACES) |i| {
            self.spaces[i] = .{
                .space_id = @intCast(i + 1),
                .index_1based = i + 1,
                .mode = .passthrough,
            };
        }
    }

    pub fn serializeStateConfig(self: *const Observatory, out_buf: []u8) []const u8 {
        var pos: usize = 0;
        for (0..self.n_spaces) |idx| {
            const sp = &self.spaces[idx];
            const written = std.fmt.bufPrint(out_buf[pos..], "{d}\t{s}\t{s}\t{s}\t{d}\n", .{
                idx,
                sp.mode.modeName(),
                sp.getLabel(),
                sp.getPath(),
                sp.space_id,
            }) catch break;
            pos += written.len;
        }
        return out_buf[0..pos];
    }

    /// Advances a Space's SDK theme one step without drawing (GPU-presented Spaces draw on the GPU).
    pub fn stepSpace(self: *Observatory, space_idx: usize) void {
        self.stepSpaceBy(space_idx, 0.008 * self.spin_mult);
    }

    /// Steps by `dt` simulated seconds (the app passes desktop/frame_rate.zig's per-frame step).
    pub fn stepSpaceBy(self: *Observatory, space_idx: usize, dt: f64) void {
        if (space_idx >= MAX_SPACES or self.paused) return;
        const sp = &self.spaces[space_idx];
        if (sp.theme_state != null and sp.theme_step_fn != null) sp.theme_step_fn.?(sp.theme_state, dt);
    }

    pub fn renderNativeShaderForSpaceIsolated(self: *Observatory, space_idx: usize, phase_cycles: f64) bool {
        return self.renderSpaceStepping(space_idx, phase_cycles, 0.008 * self.spin_mult);
    }

    /// Steps an SDK theme by `step_dt` and draws it into the Space's buffer.
    pub fn renderSpaceStepping(self: *Observatory, space_idx: usize, phase_cycles: f64, step_dt: f64) bool {
        if (space_idx >= MAX_SPACES) return false;
        const sp = &self.spaces[space_idx];
        if (sp.mode != .custom_shader) return false;
        const dst_buf = &self.space_native_pixels[space_idx];
        if (sp.theme_state != null and sp.theme_step_fn != null and sp.theme_draw_fn != null) {
            if (!self.paused) {
                sp.theme_step_fn.?(sp.theme_state, step_dt);
            }
            sp.theme_draw_fn.?(sp.theme_state, dst_buf, NATIVE_PIXELS, NATIVE_W);
            return true;
        }
        if (sp.custom_render_fn) |render_fn| {
            render_fn(dst_buf, @intCast(NATIVE_W), @intCast(NATIVE_H), phase_cycles, 0);
            return true;
        }
        return false;
    }
};

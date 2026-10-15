// ============================================================================
// ARGUS DESKTOP // src/desktop/popover_layout.zig
//
// Geometry and hit-testing for the menu bar popover's two faces, the Spaces strip and the
// Settings view, which share the same 680x98 box. All coordinates are popover points with the origin
// at the top-left. Drawing (desktop_wallpaper.zig) and clicks both read these, so they never drift.
// ============================================================================

const std = @import("std");
const sc = @import("space_config.zig");

pub const W: f64 = @floatFromInt(sc.POPOVER_W);
pub const SPACES_H: f64 = @floatFromInt(sc.POPOVER_H);

pub const Rect = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,

    pub fn contains(r: Rect, px: f64, py: f64) bool {
        return px >= r.x and px < r.x + r.w and py >= r.y and py < r.y + r.h;
    }
};

// ---- Spaces view -------------------------------------------------------------------------
pub const themes_icon = Rect{ .x = 10, .y = 4, .w = 54, .h = 30 };
pub const pause_btn = Rect{ .x = W - 60, .y = 4, .w = 24, .h = 30 };
pub const gear_btn = Rect{ .x = W - 36, .y = 4, .w = 30, .h = 30 };
/// The amber "Paused" chip left of the play button (only while paused); clicking it resumes.
pub const paused_chip = Rect{ .x = W - 132, .y = 8, .w = 64, .h = 20 };

pub const STRIP_PAD_X: f64 = 16.0;
pub const STRIP_GAP: f64 = 8.0;
pub const THUMB_Y: f64 = 34.0;
pub const THUMB_H: f64 = 50.0;

/// Thumbnail slot `idx` of `n` in the Spaces strip.
pub fn thumb(idx: usize, n_raw: usize) Rect {
    const n = @max(@as(usize, 1), @min(n_raw, sc.MAX_SPACES));
    const step = (W - STRIP_PAD_X * 2.0) / @as(f64, @floatFromInt(n));
    return .{
        .x = STRIP_PAD_X + @as(f64, @floatFromInt(idx)) * step + STRIP_GAP * 0.5,
        .y = THUMB_Y,
        .w = @max(28.0, step - STRIP_GAP),
        .h = THUMB_H,
    };
}

// ---- Settings view (same 680x98 box: header, then two rows of controls) ------------------
pub const back_btn = Rect{ .x = 10, .y = 4, .w = 86, .h = 30 };
pub const quit_btn = Rect{ .x = W - 64, .y = 4, .w = 64, .h = 30 };

pub const ROW_A_Y: f64 = 40.0; // top of the first control row
pub const ROW_B_Y: f64 = 66.0; // top of the second
pub const ROW_H: f64 = 22.0;

// Mini preview of the selected Space, the same size as a strip thumbnail: clicking it goes back.
pub const preview = Rect{ .x = 16, .y = ROW_A_Y - 2, .w = 80, .h = 50 };

// Left block: the selected Space's theme, and speed.
pub const LX: f64 = 108.0;
pub const space_btn = Rect{ .x = LX - 4, .y = ROW_A_Y, .w = 62, .h = ROW_H };
pub const stepper = Rect{ .x = LX + 62, .y = ROW_A_Y, .w = 172, .h = ROW_H };
pub const stepper_prev = Rect{ .x = stepper.x, .y = stepper.y, .w = 32, .h = stepper.h };
pub const stepper_next = Rect{ .x = stepper.x + stepper.w - 32, .y = stepper.y, .w = 32, .h = stepper.h };
pub const slider = Rect{ .x = LX + 62, .y = ROW_B_Y, .w = 140, .h = ROW_H };
pub const BLOCK_RULE_X: f64 = 352.0;

// Right block: a 2x2 grid of switches, each cell clickable as a whole.
pub const GX: f64 = 370.0;
pub const CELL_W: f64 = 148.0;

pub fn cell(col: usize, row_idx: usize) Rect {
    return .{
        .x = GX + @as(f64, @floatFromInt(col)) * CELL_W,
        .y = if (row_idx == 0) ROW_A_Y else ROW_B_Y,
        .w = CELL_W - 6.0,
        .h = ROW_H,
    };
}

/// Speed slider detents; 1x sits in the middle.
pub const SPEEDS = [_]f64{ 0.25, 0.5, 1.0, 1.5, 2.0 };

/// Index of the detent nearest to `speed`.
pub fn speedIndex(speed: f64) usize {
    var best: usize = 0;
    for (SPEEDS, 0..) |s, i| {
        if (@abs(s - speed) < @abs(SPEEDS[best] - speed)) best = i;
    }
    return best;
}

/// Track position (0..1) of a detent, and the detent under popover x.
pub fn detentT(i: usize) f64 {
    return @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(SPEEDS.len - 1));
}

pub fn detentAt(x: f64) usize {
    const t = std.math.clamp((x - slider.x) / slider.w, 0.0, 1.0);
    return @intFromFloat(@round(t * @as(f64, @floatFromInt(SPEEDS.len - 1))));
}

pub const Hit = union(enum) {
    // Spaces view
    open_themes,
    toggle_pause,
    open_settings,
    space_thumb: usize,
    // Settings view
    back,
    quit,
    next_space,
    prev_theme,
    next_theme,
    speed: usize,
    mc_stills,
    smooth_swipes,
    reload_on_edit,
    launch_at_login,
};

pub fn hitSpaces(x: f64, y: f64, n_spaces: usize, paused: bool) ?Hit {
    if (themes_icon.contains(x, y)) return .open_themes;
    if (pause_btn.contains(x, y)) return .toggle_pause;
    if (paused and paused_chip.contains(x, y)) return .toggle_pause;
    if (gear_btn.contains(x, y)) return .open_settings;
    const n = @max(@as(usize, 1), @min(n_spaces, sc.MAX_SPACES));
    for (0..n) |i| {
        const r = thumb(i, n);
        // Generous vertical band; the gaps between thumbnails belong to the nearer one.
        if (x >= r.x - STRIP_GAP * 0.5 and x < r.x + r.w + STRIP_GAP * 0.5 and y >= 30.0 and y <= 92.0) return .{ .space_thumb = i };
    }
    return null;
}

pub fn hitSettings(x: f64, y: f64) ?Hit {
    if (back_btn.contains(x, y) or preview.contains(x, y)) return .back;
    if (quit_btn.contains(x, y)) return .quit;
    if (space_btn.contains(x, y)) return .next_space;
    if (stepper_prev.contains(x, y)) return .prev_theme;
    if (stepper_next.contains(x, y)) return .next_theme;
    // The slider's knob overhangs its track; give it a few points of slack either side.
    if (x >= slider.x - 8 and x < slider.x + slider.w + 8 and y >= slider.y and y < slider.y + slider.h) return .{ .speed = detentAt(x) };
    if (cell(0, 0).contains(x, y)) return .mc_stills;
    if (cell(1, 0).contains(x, y)) return .smooth_swipes;
    if (cell(0, 1).contains(x, y)) return .reload_on_edit;
    if (cell(1, 1).contains(x, y)) return .launch_at_login;
    return null;
}

// ---- Theme list ---------------------------------------------------------------------------
pub const MAX_THEMES = 64;
pub const NAME_CAP = 64;

/// The theme files in themes/ (.zig and .metal, minus the SDK), sorted by name.
pub const ThemeList = struct {
    names: [MAX_THEMES][NAME_CAP]u8 = undefined,
    lens: [MAX_THEMES]u8 = @splat(0),
    n: usize = 0,

    pub fn name(self: *const ThemeList, i: usize) []const u8 {
        return self.names[i][0..self.lens[i]];
    }

    pub fn isThemeFile(file: []const u8) bool {
        if (std.mem.eql(u8, file, "argus_theme_sdk.zig")) return false;
        return std.mem.endsWith(u8, file, ".zig") or std.mem.endsWith(u8, file, ".metal");
    }

    /// Adds `file` in sorted position; ignores non-themes, overlong names and a full list.
    pub fn add(self: *ThemeList, file: []const u8) void {
        if (!isThemeFile(file) or file.len > NAME_CAP or self.n == MAX_THEMES) return;
        var at: usize = self.n;
        while (at > 0 and std.ascii.lessThanIgnoreCase(file, self.name(at - 1))) : (at -= 1) {
            self.names[at] = self.names[at - 1];
            self.lens[at] = self.lens[at - 1];
        }
        @memcpy(self.names[at][0..file.len], file);
        self.lens[at] = @intCast(file.len);
        self.n += 1;
    }

    pub fn indexOf(self: *const ThemeList, file: []const u8) ?usize {
        for (0..self.n) |i| {
            if (std.mem.eql(u8, self.name(i), file)) return i;
        }
        return null;
    }

    /// Re-reads themes/ (relative to the app's folder).
    pub fn scan(self: *ThemeList) void {
        self.n = 0;
        var dir = std.Io.Dir.cwd().openDir(sc.g_io, "themes", .{ .iterate = true }) catch return;
        defer dir.close(sc.g_io);
        var it = dir.iterate();
        while (it.next(sc.g_io) catch null) |e| {
            if (e.kind == .file) self.add(e.name);
        }
    }

    /// The stop `delta` steps from `current`, wrapping. Stops are the themes 0..n-1 plus
    /// "macOS Default" at n; from no current stop (a picture Space), the first or last.
    pub fn step(self: *const ThemeList, current: ?usize, delta: i32) usize {
        const stops: i64 = @intCast(self.n + 1);
        const from: i64 = if (current) |c| @intCast(c) else if (delta > 0) -1 else stops;
        return @intCast(@mod(from + delta, stops));
    }
};

test "popover layout: every control hits where it is drawn, inside the box" {
    for ([_]usize{ 1, 3, 8, 16 }) |n| {
        for (0..n) |i| {
            const t = thumb(i, n);
            try std.testing.expectEqual(Hit{ .space_thumb = i }, hitSpaces(t.x + t.w * 0.5, t.y + t.h * 0.5, n, false).?);
        }
    }
    try std.testing.expectEqual(Hit.open_settings, hitSpaces(W - 20, 18, 8, false).?);
    try std.testing.expectEqual(Hit.toggle_pause, hitSpaces(W - 48, 18, 8, false).?);
    try std.testing.expect(hitSpaces(W - 100, 18, 8, false) == null);
    try std.testing.expectEqual(Hit.toggle_pause, hitSpaces(W - 100, 18, 8, true).?);

    try std.testing.expectEqual(Hit.back, hitSettings(30, 18).?);
    try std.testing.expectEqual(Hit.back, hitSettings(preview.x + preview.w * 0.5, preview.y + preview.h * 0.5).?);
    try std.testing.expect(preview.x + preview.w < space_btn.x and preview.y + preview.h <= SPACES_H - 8);
    try std.testing.expectEqual(Hit.quit, hitSettings(W - 20, 18).?);
    try std.testing.expectEqual(Hit.next_space, hitSettings(LX + 10, ROW_A_Y + 10).?);
    try std.testing.expectEqual(Hit.prev_theme, hitSettings(stepper.x + 10, ROW_A_Y + 10).?);
    try std.testing.expectEqual(Hit.next_theme, hitSettings(stepper.x + stepper.w - 10, ROW_A_Y + 10).?);
    try std.testing.expect(hitSettings(stepper.x + stepper.w * 0.5, ROW_A_Y + 10) == null);
    try std.testing.expectEqual(Hit.mc_stills, hitSettings(GX + 10, ROW_A_Y + 10).?);
    try std.testing.expectEqual(Hit.smooth_swipes, hitSettings(GX + CELL_W + 10, ROW_A_Y + 10).?);
    try std.testing.expectEqual(Hit.reload_on_edit, hitSettings(GX + 10, ROW_B_Y + 10).?);
    try std.testing.expectEqual(Hit.launch_at_login, hitSettings(GX + CELL_W + 10, ROW_B_Y + 10).?);
    // Nothing leaves the original box or crosses the block divider.
    try std.testing.expect(ROW_B_Y + ROW_H <= SPACES_H - 6);
    try std.testing.expect(cell(1, 1).x + cell(1, 1).w <= W - 14);
    try std.testing.expect(stepper.x + stepper.w <= BLOCK_RULE_X - 10);
}

test "popover layout: speed detents" {
    try std.testing.expectEqual(@as(usize, 2), speedIndex(1.0));
    try std.testing.expectEqual(@as(usize, 0), speedIndex(0.1));
    try std.testing.expectEqual(@as(usize, 4), speedIndex(9.0));
    try std.testing.expectEqual(@as(usize, 0), detentAt(slider.x - 50));
    try std.testing.expectEqual(@as(usize, 2), detentAt(slider.x + slider.w * 0.5));
    try std.testing.expectEqual(@as(usize, 4), detentAt(slider.x + slider.w + 50));
    try std.testing.expectEqual(Hit{ .speed = 4 }, hitSettings(slider.x + slider.w - 1, slider.y + 10).?);
}

test "popover layout: theme list sorts, filters and steps" {
    var l: ThemeList = .{};
    for ([_][]const u8{ "Echo.zig", "argus_theme_sdk.zig", "Tutorial_Tides.metal", "README.md", "Argon_Black_Hole.zig" }) |f| l.add(f);
    try std.testing.expectEqual(@as(usize, 3), l.n);
    try std.testing.expectEqualStrings("Argon_Black_Hole.zig", l.name(0));
    try std.testing.expectEqualStrings("Tutorial_Tides.metal", l.name(2));
    try std.testing.expectEqual(@as(?usize, 1), l.indexOf("Echo.zig"));
    try std.testing.expectEqual(@as(usize, 3), l.step(2, 1)); // past the last theme: macOS Default
    try std.testing.expectEqual(@as(usize, 0), l.step(3, 1));
    try std.testing.expectEqual(@as(usize, 3), l.step(0, -1));
    try std.testing.expectEqual(@as(usize, 0), l.step(null, 1));
    try std.testing.expectEqual(@as(usize, 3), l.step(null, -1));
}

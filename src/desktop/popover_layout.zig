// ============================================================================
// ARGUS DESKTOP // src/desktop/popover_layout.zig
//
// Geometry and hit-testing for the menu bar popover's two faces: the Spaces strip (680x98) and
// the Settings view (680x318) it grows into. All coordinates are popover points with the origin
// at the top-left. Drawing (desktop_wallpaper.zig) and clicks both read these, so they never drift.
// ============================================================================

const std = @import("std");
const sc = @import("space_config.zig");

pub const W: f64 = @floatFromInt(sc.POPOVER_W);
pub const SPACES_H: f64 = @floatFromInt(sc.POPOVER_H);
pub const SETTINGS_H: f64 = @floatFromInt(sc.SETTINGS_H);

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

// ---- Settings view -----------------------------------------------------------------------
pub const back_btn = Rect{ .x = 10, .y = 4, .w = 86, .h = 30 };
pub const quit_btn = Rect{ .x = W - 64, .y = 4, .w = 64, .h = 30 };
pub const HEADER_RULE_Y: f64 = 34.0;

// Left column: the selected Space.
pub const LX: f64 = 20.0;
pub const LW: f64 = 300.0;
pub const NUMERALS_Y: f64 = 62.0;
pub const NUMERAL_H: f64 = 20.0;
pub const preview = Rect{ .x = LX, .y = 94, .w = 152, .h = 95 };
pub const stepper = Rect{ .x = LX + 166, .y = 112, .w = LW - 166, .h = 26 };
pub const stepper_prev = Rect{ .x = stepper.x, .y = stepper.y, .w = 34, .h = stepper.h };
pub const stepper_next = Rect{ .x = stepper.x + stepper.w - 34, .y = stepper.y, .w = 34, .h = stepper.h };
pub const choose_btn = Rect{ .x = LX, .y = 204, .w = 92, .h = 22 };
pub const default_btn = Rect{ .x = LX + 100, .y = 204, .w = 100, .h = 22 };
pub const reveal_btn = Rect{ .x = LX + 208, .y = 204, .w = 92, .h = 22 };
pub const COLUMN_RULE_X: f64 = 340.0;

/// Numeral pill for Space `idx` of `n`; pills shrink so up to 16 Spaces fit the column.
pub fn numeral(idx: usize, n_raw: usize) Rect {
    const n = @max(@as(usize, 1), @min(n_raw, sc.MAX_SPACES));
    const step = @min(36.0, LW / @as(f64, @floatFromInt(n)));
    return .{ .x = LX + @as(f64, @floatFromInt(idx)) * step, .y = NUMERALS_Y, .w = step - 4.0, .h = NUMERAL_H };
}

// Right column: global controls. Each toggle row is clickable across its full width.
pub const RX: f64 = 360.0;
pub const RW: f64 = W - RX - 20.0;
pub const ROW_ANIMATE_Y: f64 = 62.0;
pub const SPEED_Y: f64 = 92.0;
pub const slider = Rect{ .x = RX + 54, .y = 84, .w = RW - 94, .h = 30 };
pub const ROW_STILLS_Y: f64 = 148.0;
pub const ROW_SWIPES_Y: f64 = 174.0;
pub const ROW_RELOAD_Y: f64 = 200.0;
pub const ROW_LOGIN_Y: f64 = 244.0;

pub fn row(top_y: f64) Rect {
    return .{ .x = RX - 6, .y = top_y - 4, .w = RW + 12, .h = 25 };
}

pub const FOOTER_RULE_Y: f64 = 270.0;
pub const open_themes_btn = Rect{ .x = 14, .y = 276, .w = 170, .h = 26 };

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
    select_space: usize,
    prev_theme,
    next_theme,
    choose_file,
    reset_default,
    reveal,
    animate,
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

pub fn hitSettings(x: f64, y: f64, n_spaces: usize) ?Hit {
    if (back_btn.contains(x, y)) return .back;
    if (quit_btn.contains(x, y)) return .quit;
    const n = @max(@as(usize, 1), @min(n_spaces, sc.MAX_SPACES));
    for (0..n) |i| {
        if (numeral(i, n).contains(x, y)) return .{ .select_space = i };
    }
    if (stepper_prev.contains(x, y)) return .prev_theme;
    if (stepper_next.contains(x, y)) return .next_theme;
    if (choose_btn.contains(x, y)) return .choose_file;
    if (default_btn.contains(x, y)) return .reset_default;
    if (reveal_btn.contains(x, y)) return .reveal;
    if (slider.contains(x, y)) return .{ .speed = detentAt(x) };
    if (row(ROW_ANIMATE_Y).contains(x, y)) return .animate;
    if (row(ROW_STILLS_Y).contains(x, y)) return .mc_stills;
    if (row(ROW_SWIPES_Y).contains(x, y)) return .smooth_swipes;
    if (row(ROW_RELOAD_Y).contains(x, y)) return .reload_on_edit;
    if (row(ROW_LOGIN_Y).contains(x, y)) return .launch_at_login;
    if (open_themes_btn.contains(x, y)) return .open_themes;
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

    /// The theme `delta` steps from `current` (wrapping); from no current theme, the first or last.
    pub fn step(self: *const ThemeList, current: ?usize, delta: i32) ?usize {
        if (self.n == 0) return null;
        const n: i64 = @intCast(self.n);
        const from: i64 = if (current) |c| @intCast(c) else if (delta > 0) -1 else n;
        return @intCast(@mod(from + delta, n));
    }
};

test "popover layout: thumbnails, numerals and rows hit where they are drawn" {
    for ([_]usize{ 1, 3, 8, 16 }) |n| {
        for (0..n) |i| {
            const t = thumb(i, n);
            try std.testing.expectEqual(Hit{ .space_thumb = i }, hitSpaces(t.x + t.w * 0.5, t.y + t.h * 0.5, n, false).?);
            const r = numeral(i, n);
            try std.testing.expectEqual(Hit{ .select_space = i }, hitSettings(r.x + r.w * 0.5, r.y + r.h * 0.5, n).?);
            try std.testing.expect(r.x + r.w <= LX + LW);
        }
    }
    try std.testing.expectEqual(Hit.open_settings, hitSpaces(W - 20, 18, 8, false).?);
    try std.testing.expectEqual(Hit.toggle_pause, hitSpaces(W - 48, 18, 8, false).?);
    try std.testing.expect(hitSpaces(W - 100, 18, 8, false) == null);
    try std.testing.expectEqual(Hit.toggle_pause, hitSpaces(W - 100, 18, 8, true).?);
    try std.testing.expectEqual(Hit.mc_stills, hitSettings(RX + 20, ROW_STILLS_Y + 8, 8).?);
    try std.testing.expectEqual(Hit.launch_at_login, hitSettings(RX + RW - 10, ROW_LOGIN_Y + 8, 8).?);
    try std.testing.expectEqual(Hit.back, hitSettings(30, 18, 8).?);
    try std.testing.expectEqual(Hit.quit, hitSettings(W - 20, 18, 8).?);
    try std.testing.expect(open_themes_btn.y + open_themes_btn.h <= SETTINGS_H);
}

test "popover layout: speed detents" {
    try std.testing.expectEqual(@as(usize, 2), speedIndex(1.0));
    try std.testing.expectEqual(@as(usize, 0), speedIndex(0.1));
    try std.testing.expectEqual(@as(usize, 4), speedIndex(9.0));
    try std.testing.expectEqual(@as(usize, 0), detentAt(slider.x - 50));
    try std.testing.expectEqual(@as(usize, 2), detentAt(slider.x + slider.w * 0.5));
    try std.testing.expectEqual(@as(usize, 4), detentAt(slider.x + slider.w + 50));
    try std.testing.expectEqual(Hit{ .speed = 4 }, hitSettings(slider.x + slider.w - 1, slider.y + 10, 8).?);
}

test "popover layout: theme list sorts, filters and steps" {
    var l: ThemeList = .{};
    for ([_][]const u8{ "Echo.zig", "argus_theme_sdk.zig", "Tutorial_Tides.metal", "README.md", "Argon_Black_Hole.zig" }) |f| l.add(f);
    try std.testing.expectEqual(@as(usize, 3), l.n);
    try std.testing.expectEqualStrings("Argon_Black_Hole.zig", l.name(0));
    try std.testing.expectEqualStrings("Tutorial_Tides.metal", l.name(2));
    try std.testing.expectEqual(@as(?usize, 1), l.indexOf("Echo.zig"));
    try std.testing.expectEqual(@as(?usize, 0), l.step(2, 1));
    try std.testing.expectEqual(@as(?usize, 2), l.step(0, -1));
    try std.testing.expectEqual(@as(?usize, 0), l.step(null, 1));
    try std.testing.expectEqual(@as(?usize, 2), l.step(null, -1));
}

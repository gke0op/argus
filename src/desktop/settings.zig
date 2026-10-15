// ============================================================================
// ARGUS DESKTOP // src/desktop/settings.zig
//
// App-wide settings in `.argus_settings.conf`, next to `.argus_spaces.conf`: one `key=value` per
// line, `#` starts a comment. `set` rewrites only its own line and keeps every other line as is,
// so features can add keys without knowing about each other.
//
// Keys:
//   mission_control_stills=0|1   Spaces-bar stills (desktop/desktop_picture.zig). Default 0.
// ============================================================================

const std = @import("std");
const sc = @import("space_config.zig");

pub const PATH = ".argus_settings.conf";
const MAX_BYTES = 8192;

/// Value of `key` in `text`, or null. Surrounding spaces are trimmed.
pub fn lookup(text: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        if (std.mem.eql(u8, std.mem.trim(u8, line[0..eq], " \t"), key)) return std.mem.trim(u8, line[eq + 1 ..], " \t");
    }
    return null;
}

/// `text` with `key` set to `value` (replacing its line, or appended), written into `out`.
pub fn update(text: []const u8, key: []const u8, value: []const u8, out: []u8) ?[]const u8 {
    var pos: usize = 0;
    var replaced = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        const is_key = line[0] != '#' and if (std.mem.indexOfScalar(u8, line, '=')) |eq|
            std.mem.eql(u8, std.mem.trim(u8, line[0..eq], " \t"), key)
        else
            false;
        const w = if (is_key)
            std.fmt.bufPrint(out[pos..], "{s}={s}\n", .{ key, value }) catch return null
        else
            std.fmt.bufPrint(out[pos..], "{s}\n", .{line}) catch return null;
        if (is_key) replaced = true;
        pos += w.len;
    }
    if (!replaced) pos += (std.fmt.bufPrint(out[pos..], "{s}={s}\n", .{ key, value }) catch return null).len;
    return out[0..pos];
}

pub fn getBool(key: []const u8, default: bool) bool {
    var buf: [MAX_BYTES]u8 = undefined;
    const text = std.Io.Dir.cwd().readFile(sc.g_io, PATH, &buf) catch return default;
    const v = lookup(text, key) orelse return default;
    if (std.mem.eql(u8, v, "1") or std.ascii.eqlIgnoreCase(v, "true")) return true;
    if (std.mem.eql(u8, v, "0") or std.ascii.eqlIgnoreCase(v, "false")) return false;
    return default;
}

pub fn setBool(key: []const u8, on: bool) void {
    var buf: [MAX_BYTES]u8 = undefined;
    const text = std.Io.Dir.cwd().readFile(sc.g_io, PATH, &buf) catch "";
    var out: [MAX_BYTES + 128]u8 = undefined;
    const data = update(text, key, if (on) "1" else "0", &out) orelse return;
    std.Io.Dir.cwd().writeFile(sc.g_io, .{ .sub_path = PATH, .data = data }) catch {};
}

test "settings: lookup ignores comments and other keys; update keeps them" {
    const text = "# Argus settings\nfoo = bar\nmission_control_stills=0\n";
    try std.testing.expectEqualStrings("0", lookup(text, "mission_control_stills").?);
    try std.testing.expectEqualStrings("bar", lookup(text, "foo").?);
    try std.testing.expect(lookup(text, "missing") == null);

    var out: [256]u8 = undefined;
    const t2 = update(text, "mission_control_stills", "1", &out).?;
    try std.testing.expectEqualStrings("# Argus settings\nfoo = bar\nmission_control_stills=1\n", t2);
    var out2: [256]u8 = undefined;
    const t3 = update("", "mission_control_stills", "1", &out2).?;
    try std.testing.expectEqualStrings("mission_control_stills=1\n", t3);
}

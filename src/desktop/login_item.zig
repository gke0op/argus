// ============================================================================
// ARGUS DESKTOP // src/desktop/login_item.zig
//
// Launch at login: a per-user LaunchAgent (~/Library/LaunchAgents/io.github.gke0op.argus.plist) that
// opens Argus.app at login. Plain file, no ServiceManagement registration: `launch_at_login` in
// .argus_settings.conf is the switch, and the plist simply follows it.
// ============================================================================

const std = @import("std");
const sc = @import("space_config.zig");

/// Matches CFBundleIdentifier in Argus.app/Contents/Info.plist.
pub const LABEL = "io.github.gke0op.argus";
/// Labels of earlier builds: their LaunchAgents are removed on start (`removeLegacy`), and the
/// app writes the current one if "Open at login" is on.
const LEGACY_LABELS = [_][]const u8{"io.egregore.argus"};

/// The LaunchAgent plist that opens the app bundle at `app_path` at login.
pub fn plist(app_path: []const u8, out: []u8) ?[]const u8 {
    // Refuse paths that would need XML escaping rather than write a broken plist.
    if (std.mem.indexOfAny(u8, app_path, "&<>") != null) return null;
    return std.fmt.bufPrint(out,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\    <key>Label</key>
        \\    <string>{s}</string>
        \\    <key>ProgramArguments</key>
        \\    <array>
        \\        <string>/usr/bin/open</string>
        \\        <string>{s}</string>
        \\    </array>
        \\    <key>RunAtLoad</key>
        \\    <true/>
        \\</dict>
        \\</plist>
        \\
    , .{ LABEL, app_path }) catch null;
}

fn agentPath(out: []u8) ?[]const u8 {
    return agentPathFor(LABEL, out);
}

fn agentPathFor(label: []const u8, out: []u8) ?[]const u8 {
    const home = std.c.getenv("HOME") orelse return null;
    return std.fmt.bufPrint(out, "{s}/Library/LaunchAgents/{s}.plist", .{ std.mem.span(home), label }) catch null;
}

/// One-time migration: deletes LaunchAgents left under an old label. Returns how many it removed.
pub fn removeLegacy() usize {
    var removed: usize = 0;
    for (LEGACY_LABELS) |label| {
        var path_buf: [1024]u8 = undefined;
        const path = agentPathFor(label, &path_buf) orelse continue;
        std.Io.Dir.cwd().deleteFile(sc.g_io, path) catch continue;
        removed += 1;
    }
    return removed;
}

/// Installs (or refreshes, if Argus.app moved) or removes the LaunchAgent. `app_path` is the
/// absolute path of Argus.app. Returns false when the file could not be written or removed.
pub fn apply(on: bool, app_path: []const u8) bool {
    var path_buf: [1024]u8 = undefined;
    const path = agentPath(&path_buf) orelse return false;
    const cwd = std.Io.Dir.cwd();
    if (!on) {
        cwd.deleteFile(sc.g_io, path) catch |e| return e == error.FileNotFound;
        return true;
    }
    var body_buf: [2048]u8 = undefined;
    const body = plist(app_path, &body_buf) orelse return false;
    var old_buf: [2048]u8 = undefined;
    if (cwd.readFile(sc.g_io, path, &old_buf)) |old| {
        if (std.mem.eql(u8, old, body)) return true;
    } else |_| {}
    if (std.Io.Dir.path.dirname(path)) |dir| cwd.createDirPath(sc.g_io, dir) catch return false;
    cwd.writeFile(sc.g_io, .{ .sub_path = path, .data = body }) catch return false;
    return true;
}

test "login item: plist opens the app bundle at login" {
    var buf: [2048]u8 = undefined;
    const p = plist("/Users/me/Desktop/argus/Argus.app", &buf).?;
    try std.testing.expect(std.mem.indexOf(u8, p, "<string>io.github.gke0op.argus</string>") != null);
    try std.testing.expect(std.mem.indexOf(u8, p, "<string>/usr/bin/open</string>\n        <string>/Users/me/Desktop/argus/Argus.app</string>") != null);
    try std.testing.expect(std.mem.indexOf(u8, p, "<key>RunAtLoad</key>\n    <true/>") != null);
}

test "login item: label matches the bundle identifier in Info.plist" {
    sc.g_io = std.testing.io;
    var buf: [4096]u8 = undefined;
    const info = try std.Io.Dir.cwd().readFile(sc.g_io, "Argus.app/Contents/Info.plist", &buf);
    try std.testing.expect(std.mem.indexOf(u8, info, "<string>" ++ LABEL ++ "</string>") != null);
}

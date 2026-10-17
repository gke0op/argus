// ============================================================================
// ARGUS DESKTOP // src/desktop/reopen.zig
//
// The way back to Argus when its eye is out of reach. On a MacBook with a notch, a crowded menu
// bar hides the status items that don't fit, and the eye can be one of them: then a paused Argus
// can't be unpaused and Settings can't be opened. So opening Argus.app again (a double-click in
// Finder, `open Argus.app`, Spotlight) never starts a second copy. The running copy shows its
// popover, under the eye if the eye is on screen and centred under the menu bar if not, and
// resumes if it was paused.
//
// Two routes reach the running copy:
//   - LaunchServices sends it a reopen event when the same Argus.app is opened again;
//     AppKit hands that to the delegate's applicationShouldHandleReopen:hasVisibleWindows:.
//   - A second copy that starts anyway (`open -n`, another Argus.app folder, the binary run
//     directly) finds the running one, posts REVEAL_NOTE with that copy's pid, and exits
//     before it creates a window or a status item.
// ============================================================================

const std = @import("std");

/// Distributed notification a second copy posts; its object is the target copy's pid as text.
pub const REVEAL_NOTE = "io.github.gke0op.argus.reveal";

/// NSApplicationActivationPolicyAccessory: the menu-bar Argus (`--window` is regular, 0;
/// `--offscreen` is prohibited, 2). Only menu-bar copies count as "Argus is already running",
/// so a measurement instance never stops the real app from starting, or the other way round.
pub const POLICY_MENU_BAR: isize = 1;

/// A running app with Argus's bundle identifier, as NSRunningApplication describes it.
pub const Peer = struct {
    pid: i32,
    policy: isize,
    terminated: bool,
};

/// The menu-bar Argus a new menu-bar copy should hand over to, if there is one.
pub fn runningCopy(peers: []const Peer, self_pid: i32) ?i32 {
    for (peers) |p| {
        if (p.pid == self_pid or p.pid <= 0 or p.terminated) continue;
        if (p.policy == POLICY_MENU_BAR) return p.pid;
    }
    return null;
}

/// Whether a REVEAL_NOTE whose object reads `object` is meant for the copy with pid `self_pid`.
pub fn noteIsForUs(object: ?[]const u8, self_pid: i32) bool {
    const s = object orelse return false;
    const pid = std.fmt.parseInt(i32, s, 10) catch return false;
    return pid == self_pid;
}

pub const Box = struct { x: f64, y: f64, w: f64, h: f64 };

/// Whether the eye can be seen: its window is on a screen, inside it, and touches the top edge
/// (bottom-left origin, as AppKit reports it). An item hidden behind the notch has no screen and
/// sits below the display (y = -thickness); one hidden with setVisible: has a zero-height frame.
pub fn eyeOnScreen(eye: Box, has_screen: bool, screen: Box) bool {
    if (!has_screen or eye.w <= 0 or eye.h <= 0) return false;
    const top = screen.y + screen.h;
    return eye.x >= screen.x and eye.x + eye.w <= screen.x + screen.w and
        eye.y >= screen.y and eye.y + eye.h <= top and eye.y + eye.h >= top - 2.0;
}

/// Left edge of the popover: centred under the eye when it is on screen, otherwise centred
/// under the menu bar, and always 12 pt clear of the screen's sides.
pub fn popoverX(eye_mid_x: ?f64, screen_w: f64, pop_w: f64) f64 {
    const mid = eye_mid_x orelse screen_w * 0.5;
    return std.math.clamp(mid - pop_w * 0.5, 12.0, @max(12.0, screen_w - pop_w - 12.0));
}

test "reopen: a new menu-bar copy hands over to the running menu-bar Argus" {
    const peers = [_]Peer{
        .{ .pid = 500, .policy = 1, .terminated = false }, // this copy
        .{ .pid = 400, .policy = 2, .terminated = false }, // an --offscreen measurement
        .{ .pid = 300, .policy = 1, .terminated = true }, // killed a moment ago
        .{ .pid = 200, .policy = 1, .terminated = false }, // the running Argus
    };
    try std.testing.expectEqual(@as(?i32, 200), runningCopy(&peers, 500));
    try std.testing.expectEqual(@as(?i32, null), runningCopy(peers[0..3], 500));
    try std.testing.expectEqual(@as(?i32, null), runningCopy(&.{}, 500));
}

test "reopen: the reveal note only wakes the copy it names" {
    try std.testing.expect(noteIsForUs("4242", 4242));
    try std.testing.expect(!noteIsForUs("4243", 4242));
    try std.testing.expect(!noteIsForUs("", 4242));
    try std.testing.expect(!noteIsForUs("argus", 4242));
    try std.testing.expect(!noteIsForUs(null, 4242));
}

test "reopen: an eye behind the notch counts as hidden" {
    const screen = Box{ .x = 0, .y = 0, .w = 1512, .h = 982 };
    // Measured on macOS 26 (14-inch MacBook Pro, crowded menu bar): a visible item, then hidden.
    try std.testing.expect(eyeOnScreen(.{ .x = 1232, .y = 949, .w = 29, .h = 33 }, true, screen));
    try std.testing.expect(!eyeOnScreen(.{ .x = 0, .y = -33, .w = 29, .h = 33 }, false, screen));
    try std.testing.expect(!eyeOnScreen(.{ .x = 0, .y = -33, .w = 29, .h = 33 }, true, screen));
    try std.testing.expect(!eyeOnScreen(.{ .x = 1232, .y = 949, .w = 0, .h = 33 }, true, screen));
    // An --offscreen copy's item (setVisible: false), as Argus measured it on the same Mac.
    try std.testing.expect(!eyeOnScreen(.{ .x = 0, .y = 0, .w = 34, .h = 0 }, true, screen));
    try std.testing.expect(!eyeOnScreen(.{ .x = 600, .y = 400, .w = 29, .h = 33 }, true, screen));
}

test "reopen: popover sits under the eye, or centred when the eye is hidden" {
    // The 680 x 98 pt popover on a 1512 pt wide screen; x = 416 is what the window server reported.
    try std.testing.expectEqual(@as(f64, 416.0), popoverX(null, 1512, 680));
    try std.testing.expectEqual(@as(f64, 560.0), popoverX(900, 1512, 680));
    try std.testing.expectEqual(@as(f64, 820.0), popoverX(1246.5, 1512, 680));
    try std.testing.expectEqual(@as(f64, 12.0), popoverX(20, 1512, 680));
}

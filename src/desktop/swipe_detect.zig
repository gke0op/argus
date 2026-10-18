// ============================================================================
// ARGUS DESKTOP // src/desktop/swipe_detect.zig
//
// Tells a Space switch in progress from the window server's on-screen window list.
//
// As a swipe (or Mission Control) starts, the window server puts the Space windows of that
// display into the on-screen list, 0.4-1.5 s before the active Space changes; occlusionState
// reports the arriving window visible only at the end. So a neighbour of the active Space whose
// window has *just* come on screen means a switch is under way, and it should draw from that
// moment.
//
// Only fresh arrivals count. Some windows sit in the list for good: with several displays (or
// "Displays have separate Spaces"), each other display's current Space is always on screen. Taken
// at face value they would read as a switch that never ends and keep both neighbours drawing at
// 30 FPS. A window that has been on screen for FRESH_TICKS is steady and is ignored.
// ============================================================================

const std = @import("std");

pub const MAX_SPACES = 16;

pub const SwipeDetector = struct {
    /// A window on screen for this long (2 s at the 30 Hz logic tick) is steady, not arriving.
    pub const FRESH_TICKS: u64 = 60;

    /// Logic tick at which each Space's window entered the on-screen list; null while it is off.
    since: [MAX_SPACES]?u64 = @splat(null),

    /// Records the windows on screen at `tick` (`on_screen`: one bit per Space) and returns the
    /// Spaces among `candidates` (the active Space's neighbours) that should draw as if visible:
    /// both of them when either came on screen within FRESH_TICKS, else none. A swipe's
    /// direction isn't known until it ends, so both possible arrivals draw.
    pub fn update(self: *SwipeDetector, on_screen: u16, candidates: u16, tick: u64) u16 {
        var fresh = false;
        for (0..MAX_SPACES) |i| {
            const bit = @as(u16, 1) << @intCast(i);
            if (on_screen & bit == 0) {
                self.since[i] = null;
                continue;
            }
            const t0 = self.since[i] orelse blk: {
                self.since[i] = tick;
                break :blk tick;
            };
            if (candidates & bit != 0 and tick -| t0 < FRESH_TICKS) fresh = true;
        }
        return if (fresh) candidates else 0;
    }
};

// ============================================================================
// Tests: the window lists Argus sees in each situation
// ============================================================================

const ACTIVE: u16 = 1 << 3; // main display's active Space
const NEIGHBOURS: u16 = (1 << 2) | (1 << 4);

test "swipe: neighbours draw from the moment the Space windows come on screen" {
    var d: SwipeDetector = .{};
    var t: u64 = 0;
    while (t < 90) : (t += 1) try std.testing.expectEqual(@as(u16, 0), d.update(ACTIVE, NEIGHBOURS, t));
    // The swipe starts: every Space window of this display enters the list.
    try std.testing.expectEqual(NEIGHBOURS, d.update(0x7f, NEIGHBOURS, 90));
    try std.testing.expectEqual(NEIGHBOURS, d.update(0x7f, NEIGHBOURS, 120));
    // It ends: only the new active Space (4) is on screen; its neighbours are 3 and 5.
    try std.testing.expectEqual(@as(u16, 0), d.update(1 << 4, (1 << 3) | (1 << 5), 125));
}

test "second display: its current Space, always on screen, does not keep a switch going" {
    var d: SwipeDetector = .{};
    const other_display: u16 = 1 << 4; // a neighbour by index, but the other display's current Space
    var drew: u64 = 0;
    var t: u64 = 0;
    while (t < 30 * 60) : (t += 1) { // a minute
        if (d.update(ACTIVE | other_display, NEIGHBOURS, t) != 0) drew += 1;
    }
    // Only the first 2 s after it appeared (Argus starting up), then never.
    try std.testing.expectEqual(SwipeDetector.FRESH_TICKS, drew);
    // A real swipe on the main display still shows: the other neighbour (2) arrives fresh.
    try std.testing.expectEqual(NEIGHBOURS, d.update(ACTIVE | other_display | (1 << 2), NEIGHBOURS, t));
}

test "second display: a swipe there does not draw the main display's neighbours" {
    var d: SwipeDetector = .{};
    // Spaces 0-6 on the main display, 7-9 on the second; 8 is the second display's current Space.
    var t: u64 = 0;
    while (t < 90) : (t += 1) _ = d.update(ACTIVE | (1 << 8), NEIGHBOURS, t);
    // Swipe on the second display: its Space windows (7-9) come on screen, the main ones don't.
    try std.testing.expectEqual(@as(u16, 0), d.update(ACTIVE | (0b111 << 7), NEIGHBOURS, 90));
}

test "Mission Control held open: neighbours draw for at most 2 s" {
    var d: SwipeDetector = .{};
    var drew: u64 = 0;
    var t: u64 = 0;
    while (t < 30 * 10) : (t += 1) { // open for 10 s
        if (d.update(0x7f, NEIGHBOURS, t) != 0) drew += 1;
    }
    try std.testing.expectEqual(SwipeDetector.FRESH_TICKS, drew);
}

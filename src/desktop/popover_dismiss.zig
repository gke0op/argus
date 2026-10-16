// ============================================================================
// ARGUS DESKTOP // src/desktop/popover_dismiss.zig
//
// When a click outside closes the menu bar popover. Normally: a left click outside closes it on
// release (unless the press became a drag, so dragging a theme in from anywhere keeps it open),
// a right click outside closes it at once, and switching apps closes it.
//
// Drop mode: the popover's themes button opened Finder so the user can drag a theme onto a
// Space. Picking a file there takes clicks, so for a while clicks in Finder (and drags) leave the
// popover open, and the header says "Drag a theme onto a Space". Drop mode ends on a drop, Esc,
// the eye, a click outside both the popover and Finder, or DROP_TIMEOUT_S without a Finder click
// or drag.
// ============================================================================

const std = @import("std");

pub const DROP_TIMEOUT_S: f64 = 30.0;

/// Where a click landed.
pub const Where = enum { popover, finder, elsewhere };

pub const Dismiss = struct {
    drop_mode: bool = false,
    deadline: f64 = 0,
    press: ?Where = null,
    dragged: bool = false,

    pub fn enterDropMode(self: *Dismiss, now: f64) void {
        self.drop_mode = true;
        self.deadline = now + DROP_TIMEOUT_S;
    }

    fn keepAlive(self: *Dismiss, now: f64) void {
        if (self.drop_mode) self.deadline = now + DROP_TIMEOUT_S;
    }

    pub fn leftDown(self: *Dismiss, where: Where, now: f64) void {
        self.press = where;
        self.dragged = false;
        if (where == .finder) self.keepAlive(now);
    }

    pub fn leftDragged(self: *Dismiss, now: f64) void {
        self.dragged = true;
        self.keepAlive(now);
    }

    /// The release of a press; `released_in_popover` is where the mouse is now. True: close.
    pub fn leftUp(self: *Dismiss, released_in_popover: bool) bool {
        const p = self.press orelse return false;
        self.press = null;
        if (p == .popover or self.dragged or released_in_popover) return false;
        if (self.drop_mode and p == .finder) return false;
        self.drop_mode = false;
        return true;
    }

    /// A right click (or two-finger tap) at `where`. True: close.
    pub fn rightDown(self: *Dismiss, where: Where, now: f64) bool {
        if (where == .popover) return false;
        if (self.drop_mode and where == .finder) {
            self.keepAlive(now);
            return false;
        }
        self.drop_mode = false;
        return true;
    }

    /// Argus stopped being the active app. Opening Finder for a drop does exactly that, so drop
    /// mode ignores it; otherwise close unless a click is in progress (settled on its release).
    pub fn resignActive(self: *const Dismiss, button_down: bool, mouse_in_popover: bool) bool {
        if (self.drop_mode) return false;
        return !button_down and !mouse_in_popover;
    }

    /// A drag is over the popover.
    pub fn dragOver(self: *Dismiss, now: f64) void {
        self.keepAlive(now);
    }

    /// A file was dropped onto a Space: drop mode is done.
    pub fn dropped(self: *Dismiss) void {
        self.drop_mode = false;
    }

    /// Called every tick. True when drop mode just timed out (the hint should go).
    pub fn tick(self: *Dismiss, now: f64) bool {
        if (!self.drop_mode or now < self.deadline) return false;
        self.drop_mode = false;
        return true;
    }

    /// The popover closed (any way): start clean next time.
    pub fn closed(self: *Dismiss) void {
        self.* = .{};
    }
};

test "dismiss: normal mode closes on a click outside, never on a drag or inside" {
    var d: Dismiss = .{};
    d.leftDown(.elsewhere, 0);
    try std.testing.expect(d.leftUp(false));
    d.leftDown(.finder, 0); // Finder is "outside" when not in drop mode
    try std.testing.expect(d.leftUp(false));
    d.leftDown(.finder, 0);
    d.leftDragged(0);
    try std.testing.expect(!d.leftUp(false)); // a drag that starts in Finder is never cut off
    d.leftDown(.popover, 0);
    try std.testing.expect(!d.leftUp(false));
    try std.testing.expect(!d.leftUp(false)); // a release without a press
    try std.testing.expect(d.rightDown(.finder, 0));
    try std.testing.expect(!d.rightDown(.popover, 0));
    try std.testing.expect(d.resignActive(false, false));
    try std.testing.expect(!d.resignActive(true, false));
}

test "dismiss: drop mode keeps Finder clicks, ends on a click elsewhere, a drop or a timeout" {
    var d: Dismiss = .{};
    d.enterDropMode(100);
    try std.testing.expect(!d.resignActive(false, false)); // Finder came forward
    d.leftDown(.finder, 101);
    try std.testing.expect(!d.leftUp(false)); // picking a file
    try std.testing.expect(!d.rightDown(.finder, 102));
    try std.testing.expect(d.drop_mode);

    // Each Finder click restarts the 30 s timeout.
    d.leftDown(.finder, 125);
    _ = d.leftUp(false);
    try std.testing.expect(!d.tick(150));
    try std.testing.expect(d.tick(155.5));
    try std.testing.expect(!d.drop_mode);
    d.leftDown(.finder, 156); // back to normal: a Finder click closes
    try std.testing.expect(d.leftUp(false));

    // A click outside both the popover and Finder closes and ends drop mode.
    d.closed();
    d.enterDropMode(0);
    d.leftDown(.elsewhere, 1);
    try std.testing.expect(d.leftUp(false));
    try std.testing.expect(!d.drop_mode);

    // A drop ends it without closing; drags over the popover keep it alive meanwhile.
    d.enterDropMode(0);
    d.dragOver(29);
    try std.testing.expect(!d.tick(40));
    d.dropped();
    try std.testing.expect(!d.drop_mode);
    try std.testing.expect(!d.tick(1000));

    // Closing (Esc, the eye) resets everything.
    d.enterDropMode(0);
    d.leftDown(.finder, 1);
    d.closed();
    try std.testing.expect(!d.drop_mode and d.press == null);
}

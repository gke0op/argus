// ============================================================================
// ARGUS DESKTOP // src/desktop/frame_rate.zig
//
// Frame rate (30 / 60 / 120 FPS, `fps` in .argus_settings.conf) without changing how fast any
// theme moves. Two clocks:
//   - The logic tick stays at 30 Hz whatever the rate: housekeeping (Space sync, hot reload,
//     neighbour warm-up, popover refresh) and simulation steps (Metal `argus_step`, which many
//     themes advance by a fixed amount per step) run on it exactly as before.
//   - Display frames come from the display's vsync at the chosen rate. Visible Spaces draw on
//     every one, with time advanced by the real frame interval, so continuous motion is smoother
//     while the simulated time per wall second stays the same at every rate.
// Time is kept in integer units of 1/120 s, so at 30 FPS every step and clock advance is
// bit-identical to the old fixed-tick code.
// ============================================================================

const std = @import("std");

pub const RATES = [_]u32{ 30, 60, 120 };
pub const DEFAULT_FPS: u32 = 30;
pub const LOGIC_HZ: u32 = 30;
/// Time unit: 1/120 s, so every rate's frame is a whole number of units.
pub const UNITS_PER_S: u64 = 120;
const UNITS_PER_TICK: u64 = UNITS_PER_S / LOGIC_HZ; // 4

/// Simulated seconds an SDK (Zig) theme steps per logic tick (`argus_theme_step(dt)`).
pub const ZIG_TICK_DT: f64 = 0.008;
/// Phase a stateless (`argus_render_theme`) theme advances per logic tick.
pub const PHASE_PER_TICK: f64 = 1.0 / 150.0;

/// The nearest offered rate at or below `want` that the display can show.
pub fn clampToDisplay(want: u32, display_max_fps: u32) u32 {
    var best: u32 = RATES[0];
    for (RATES) |r| {
        if (r <= want and r <= @max(display_max_fps, RATES[0])) best = r;
    }
    return best;
}

/// How many of RATES this display offers (30 always; 60 and 120 when it can refresh that fast).
pub fn offeredCount(display_max_fps: u32) usize {
    var n: usize = 0;
    for (RATES) |r| {
        if (r == RATES[0] or r <= display_max_fps) n += 1;
    }
    return n;
}

fn unitsPerFrame(hz: u32) u64 {
    return UNITS_PER_S / hz;
}

/// What a display frame is: how far time moved (in units) and whether it is also a logic tick.
pub const Advance = struct { units: u64, logic: bool };

/// How far to move a Space's time when it draws now. `zig_dt` is the SDK step, `clock_dt` the
/// Metal clock advance (f.time), `step_dt` the Metal `argus_step` dt, or null when no logic tick
/// has passed since the Space last stepped (draw-only frame).
pub const SpaceTimes = struct { zig_dt: f64, clock_dt: f32, step_dt: ?f32 };

pub const Pacer = struct {
    hz: u32 = DEFAULT_FPS,
    /// Wall clock (s) that display frame 0 of the current rate was due at; null until the first frame.
    t0: ?f64 = null,
    last_frame: u64 = 0,
    /// Units since start, advanced only by display frames.
    clock: u64 = 0,
    /// Logic ticks since start.
    ticks: u64 = 0,
    // Per Space: clock at its last draw and logic tick at its last step.
    drawn_at: [16]u64 = @splat(0),
    stepped_at: [16]u64 = @splat(0),
    drawn_once: [16]bool = @splat(false),

    pub fn setRate(self: *Pacer, hz: u32) void {
        if (hz == self.hz) return;
        self.hz = hz;
        self.t0 = null; // restart the frame count at the new rate from the next callback
    }

    /// A vsync callback at wall time `now` (s). Null when no new frame at our rate is due yet
    /// (the display runs faster than the chosen rate); otherwise how far time moved.
    pub fn advance(self: *Pacer, now: f64) ?Advance {
        const hz_f: f64 = @floatFromInt(self.hz);
        const t0 = self.t0 orelse {
            self.t0 = now;
            self.last_frame = 0;
            // The very first frame is a whole logic tick at any rate, so tick 0 (the first
            // argus_step, f.frame 0) lands on the same frame at 30, 60 and 120 FPS.
            if (self.clock == 0) return self.step((UNITS_PER_TICK + unitsPerFrame(self.hz) - 1) / unitsPerFrame(self.hz));
            return self.step(1);
        };
        const f = @round((now - t0) * hz_f);
        if (f <= @as(f64, @floatFromInt(self.last_frame))) return null;
        const frame: u64 = @intFromFloat(f);
        const n = frame - self.last_frame;
        self.last_frame = frame;
        return self.step(n);
    }

    /// Moves the clock by `frames` frames at the current rate (more than 1 when frames were dropped).
    pub fn step(self: *Pacer, frames: u64) Advance {
        const before = self.clock / UNITS_PER_TICK;
        // Dropped frames count, up to one logic tick: a longer stall (sleep, a busy main thread)
        // moves time by 1/30 s, as a late tick of the old 30 Hz timer did.
        const units = @min(frames * unitsPerFrame(self.hz), UNITS_PER_TICK);
        self.clock += units;
        const logic = self.clock / UNITS_PER_TICK > before;
        if (logic) self.ticks += 1;
        return .{ .units = units, .logic = logic };
    }

    /// A hidden Space coming back into view: its next draw moves time by one frame and one
    /// step, as if its clock had paused while nobody could see it. Without this the first visible
    /// frame jumps by the whole hidden gap (up to 0.5 s of motion), which warm neighbours only
    /// hid by drawing invisible frames every 3 ticks.
    pub fn resumeSpace(self: *Pacer, idx: usize) void {
        if (!self.drawn_once[idx]) return;
        self.drawn_at[idx] = self.clock -| unitsPerFrame(self.hz);
        self.stepped_at[idx] = self.ticks -| 1;
    }

    /// Times for Space `idx` drawing now at speed `spin`. Records the draw (and the step, if due).
    pub fn spaceTimes(self: *Pacer, idx: usize, spin: f64) SpaceTimes {
        const first = !self.drawn_once[idx];
        // Never zero: a Space drawn twice in one frame still moves one frame, as before.
        const du = if (first) unitsPerFrame(self.hz) else @max(self.clock - self.drawn_at[idx], unitsPerFrame(self.hz));
        const dticks = if (first) 1 else self.ticks - self.stepped_at[idx];
        self.drawn_at[idx] = self.clock;
        self.drawn_once[idx] = true;
        var t: SpaceTimes = .{
            .zig_dt = zigStepDt(du, spin),
            .clock_dt = clockDt(du, self.hz, spin),
            .step_dt = null,
        };
        if (dticks > 0) {
            self.stepped_at[idx] = self.ticks;
            t.step_dt = clockDt(dticks * UNITS_PER_TICK, LOGIC_HZ, spin);
        }
        return t;
    }

    /// Stateless themes' phase per display frame of `units`.
    pub fn phaseStep(units: u64, spin: f64) f64 {
        return PHASE_PER_TICK * spin * (@as(f64, @floatFromInt(@min(units, UNITS_PER_TICK))) / @as(f64, @floatFromInt(UNITS_PER_TICK)));
    }

    pub fn forget(self: *Pacer, idx: usize) void {
        self.drawn_once[idx] = false;
    }
};

/// SDK step for a draw `du` units after the last: ZIG_TICK_DT per logic tick, capped at one
/// tick (a warm neighbour drawn every 3rd tick steps one tick's worth, as it always has).
pub fn zigStepDt(du: u64, spin: f64) f64 {
    const ticks = @as(f64, @floatFromInt(@min(du, UNITS_PER_TICK))) / @as(f64, @floatFromInt(UNITS_PER_TICK));
    return ZIG_TICK_DT * spin * ticks;
}

/// Metal clock advance for `du` units at rate `hz`: real time, at least one frame, at most 0.5 s.
pub fn clockDt(du: u64, hz: u32, spin: f64) f32 {
    const secs = @as(f32, @floatFromInt(du)) / @as(f32, @floatFromInt(UNITS_PER_S));
    return std.math.clamp(secs, 1.0 / @as(f32, @floatFromInt(hz)), 0.5) * @as(f32, @floatCast(spin));
}

// ============================================================================
// Tests
// ============================================================================

const Totals = struct { zig: f64 = 0, clock: f64 = 0, steps: u32 = 0, step_time: f64 = 0, phase: f64 = 0, logic: u32 = 0 };

/// One second of perfect vsync at `hz` on a Space that has been running for a second already:
/// the active Space draws every frame, a warm neighbour on every 3rd logic tick (as onTick does).
fn simulateSecond(hz: u32, spin: f64, neighbour: bool) Totals {
    var p: Pacer = .{};
    p.setRate(hz);
    var t: Totals = .{};
    const frames = 2 * hz;
    for (1..frames + 1) |f| {
        const adv = p.advance(@as(f64, @floatFromInt(f)) / @as(f64, @floatFromInt(hz))) orelse continue;
        if (f == hz + 1) t = .{}; // the first second warms up; measure the second one
        t.phase += Pacer.phaseStep(adv.units, spin);
        if (adv.logic) t.logic += 1;
        const draws = if (neighbour) adv.logic and (p.ticks % 3 == 0) else true;
        if (!draws) continue;
        const st = p.spaceTimes(0, spin);
        t.zig += st.zig_dt;
        t.clock += st.clock_dt;
        if (st.step_dt) |d| {
            t.steps += 1;
            t.step_time += d;
        }
    }
    return t;
}

test "frame rate: 1 s of wall time advances every time path equally at 30, 60 and 120 FPS" {
    for ([_]f64{ 1.0, 0.25, 2.0 }) |spin| {
        for ([_]bool{ false, true }) |neighbour| {
            const ref = simulateSecond(30, spin, neighbour);
            for ([_]u32{ 60, 120 }) |hz| {
                const t = simulateSecond(hz, spin, neighbour);
                try std.testing.expectEqual(ref.logic, t.logic);
                try std.testing.expectEqual(ref.steps, t.steps);
                try std.testing.expectApproxEqAbs(ref.zig, t.zig, 1e-12);
                try std.testing.expectApproxEqAbs(ref.clock, t.clock, 1e-5);
                try std.testing.expectApproxEqAbs(ref.step_time, t.step_time, 1e-5);
                try std.testing.expectApproxEqAbs(ref.phase, t.phase, 1e-12);
            }
        }
    }
    // The active Space at 30 FPS: 30 logic ticks, 30 steps of 1/30 s, Zig 30 x 0.008, clock 1 s.
    const a = simulateSecond(30, 1.0, false);
    try std.testing.expectEqual(@as(u32, 30), a.logic);
    try std.testing.expectEqual(@as(u32, 30), a.steps);
    try std.testing.expectApproxEqAbs(@as(f64, 0.24), a.zig, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), a.clock, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f64, 30.0 / 150.0), a.phase, 1e-12);
}

test "frame rate: at 30 FPS the clocks are bit-identical to the old per-tick code" {
    var p: Pacer = .{};
    for (1..200) |f| {
        const adv = p.advance(@as(f64, @floatFromInt(f)) / 30.0).?;
        try std.testing.expect(adv.logic);
        const st = p.spaceTimes(3, 1.5);
        // Old code: dt = clamp(ticks / 30, 1/30, 0.5) * spin with ticks = 1; step 0.008 * spin.
        const old_dt = std.math.clamp(@as(f32, 1.0) / 30.0, 1.0 / 30.0, 0.5) * @as(f32, 1.5);
        try std.testing.expectEqual(old_dt, st.clock_dt);
        try std.testing.expectEqual(old_dt, st.step_dt.?);
        try std.testing.expectEqual(@as(f64, 0.008) * 1.5, st.zig_dt);
    }
}

test "frame rate: a Space resuming after being hidden moves one frame, not the hidden gap" {
    var p: Pacer = .{};
    for (1..31) |f| _ = p.advance(@as(f64, @floatFromInt(f)) / 30.0).?;
    _ = p.spaceTimes(2, 1.0); // drawn at t = 1 s
    for (31..91) |f| _ = p.advance(@as(f64, @floatFromInt(f)) / 30.0).?; // hidden for 2 s
    const jumped = p.spaceTimes(2, 1.0);
    try std.testing.expectEqual(@as(f32, 0.5), jumped.clock_dt); // the old behaviour: a 0.5 s jump

    _ = p.spaceTimes(5, 1.0);
    for (91..151) |f| _ = p.advance(@as(f64, @floatFromInt(f)) / 30.0).?;
    p.resumeSpace(5);
    const resumed = p.spaceTimes(5, 1.0);
    try std.testing.expectEqual(@as(f32, 1.0) / 30.0, resumed.clock_dt);
    try std.testing.expectEqual(@as(f32, 1.0) / 30.0, resumed.step_dt.?);
    try std.testing.expectEqual(@as(f64, 0.008), resumed.zig_dt);
}

test "frame rate: faster vsync than the chosen rate skips callbacks; dropped frames count once" {
    var p: Pacer = .{};
    p.setRate(60);
    _ = p.advance(10.0).?;
    try std.testing.expect(p.advance(10.0 + 1.0 / 120.0 - 0.001) == null); // a 120 Hz vsync in between
    const late = p.advance(10.0 + 2.0 / 60.0).?; // one frame dropped
    try std.testing.expectEqual(@as(u64, 2 * 2), late.units);
    const stall = p.advance(30.0).?; // the Mac slept: one logic tick's worth
    try std.testing.expectEqual(UNITS_PER_TICK, stall.units);
}

test "frame rate: offered rates follow the display" {
    try std.testing.expectEqual(@as(usize, 2), offeredCount(60));
    try std.testing.expectEqual(@as(usize, 3), offeredCount(120));
    try std.testing.expectEqual(@as(u32, 60), clampToDisplay(120, 60));
    try std.testing.expectEqual(@as(u32, 120), clampToDisplay(120, 120));
    try std.testing.expectEqual(@as(u32, 30), clampToDisplay(45, 120));
    try std.testing.expectEqual(@as(u32, 30), clampToDisplay(30, 0));
}

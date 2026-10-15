//! Menu bar glyph: a ring split into one arc per Space, with an iris that sits on
//! the current Space's arc. Rasterised in pure Zig into an alpha mask (used as an
//! AppKit template image, so macOS tints it for light/dark/highlighted menu bars).
//!
//! Geometry is authored in a 24x24 unit box, Space 1 at 12 o'clock, clockwise.

const std = @import("std");
const math = std.math;

pub const MAX_PX: usize = 96;

const BOX: f64 = 24.0;
const RING_R: f64 = 7.0; // ring radius
const STROKE: f64 = 1.4; // ring stroke width
const GAP: f64 = 0.9; // visible gap between neighbouring arcs
const EYE_SCALE: f64 = 1.3; // iris diameter = 1.3x its own arc
const EYE_MIN: f64 = 4.2; // iris diameter clamp (many Spaces)
const EYE_MAX: f64 = 7.2; // iris diameter clamp (few Spaces)
const PUPIL_FRAC: f64 = 0.42; // pupil radius as a fraction of iris radius
const EYE_CLEAR: f64 = 0.6; // breathing room between iris and neighbouring arcs
/// Furthest any ink reaches from the centre; scaled to fill the image edge to edge.
const EXTENT: f64 = RING_R + EYE_MAX * 0.5;

fn spaceAngle(k: usize, n: usize) f64 {
    return @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(n)) * 2.0 * math.pi - math.pi * 0.5;
}

/// Iris radius in unit-box units for `n` Spaces.
pub fn irisRadius(n_raw: usize) f64 {
    const n = @max(n_raw, 1);
    const step = 2.0 * math.pi / @as(f64, @floatFromInt(n));
    const seg_len = if (n > 1) step * RING_R - GAP else 2.0 * math.pi * RING_R;
    return math.clamp(EYE_SCALE * seg_len, EYE_MIN, EYE_MAX) * 0.5;
}

/// Wraps an angle difference into (-pi, pi].
fn wrap(d: f64) f64 {
    var x = @mod(d + math.pi, 2.0 * math.pi) - math.pi;
    if (x <= -math.pi) x += 2.0 * math.pi;
    return x;
}

/// Signed distance (unit-box units) from point (x, y) to the glyph ink; negative is inside.
fn glyphDistance(x: f64, y: f64, n_raw: usize, cur_raw: usize) f64 {
    const n = @max(n_raw, 1);
    const cur = @min(cur_raw, n - 1);
    const c = BOX * 0.5;
    const px = x - c;
    const py = y - c;
    const r = @sqrt(px * px + py * py);
    const theta = math.atan2(py, px);

    const ir = irisRadius(n);
    const eye_a = spaceAngle(cur, n);
    const ex = eye_a; // iris centre angle
    const ecx = RING_R * @cos(ex);
    const ecy = RING_R * @sin(ex);
    const de = @sqrt((px - ecx) * (px - ecx) + (py - ecy) * (py - ecy));
    // Iris disc with a pupil hole.
    var d = @max(de - ir, ir * PUPIL_FRAC - de);

    // The iris carves an angular window out of the ring.
    const clear = (ir + EYE_CLEAR + STROKE * 0.5) / RING_R;
    const half_gap = if (n > 1) (GAP + STROKE) * 0.5 / RING_R else 0.0;
    const step = 2.0 * math.pi / @as(f64, @floatFromInt(n));

    // Arc k covers [centre - step/2 + gap, centre + step/2 - gap], all relative to the eye.
    var k: usize = 0;
    while (k < n) : (k += 1) {
        if (k == cur and n > 1) continue;
        var lo: f64 = undefined;
        var hi: f64 = undefined;
        if (n == 1) {
            lo = clear;
            hi = 2.0 * math.pi - clear;
        } else {
            const mid = wrap(spaceAngle(k, n) - eye_a);
            lo = mid - step * 0.5 + half_gap;
            hi = mid + step * 0.5 - half_gap;
            // Clip against the iris window [-clear, clear].
            if (hi > -clear and lo < clear) {
                if (lo < -clear) {
                    d = @min(d, arcDistance(r, wrap(theta - eye_a), lo, -clear));
                }
                if (hi > clear) {
                    d = @min(d, arcDistance(r, wrap(theta - eye_a), clear, hi));
                }
                continue;
            }
        }
        var rel = wrap(theta - eye_a);
        if (n == 1 and rel < 0) rel += 2.0 * math.pi;
        d = @min(d, arcDistance(r, rel, lo, hi));
    }
    return d;
}

/// Distance to a round-capped arc of radius RING_R spanning relative angles [lo, hi].
fn arcDistance(r: f64, rel: f64, lo: f64, hi: f64) f64 {
    if (hi - lo < 0.02) return math.inf(f64);
    const mid = (lo + hi) * 0.5;
    const half = (hi - lo) * 0.5;
    // Measure the angle from the arc's midpoint so wraparound never splits it.
    const off = wrap(rel - mid);
    if (@abs(off) <= half) return @abs(r - RING_R) - STROKE * 0.5;
    // Outside the span: distance to the nearer round cap.
    const cap = if (off > 0) half else -half;
    const dx = r * @cos(off) - RING_R * @cos(cap);
    const dy = r * @sin(off) - RING_R * @sin(cap);
    return @sqrt(dx * dx + dy * dy) - STROKE * 0.5;
}

/// Rasterises the glyph into `alpha` (px * px, row 0 at the top) with 1-pixel anti-aliasing.
pub fn render(alpha: []u8, px: usize, n_spaces: usize, current: usize) void {
    std.debug.assert(px > 0 and px <= MAX_PX and alpha.len >= px * px);
    const px_f: f64 = @floatFromInt(px);
    // Fill the image: EXTENT maps to half the image minus a pixel of AA margin.
    const units_per_px = EXTENT / (px_f * 0.5 - 1.0);
    const c = BOX * 0.5;
    for (0..px) |row| {
        for (0..px) |col| {
            const ux = c + (@as(f64, @floatFromInt(col)) + 0.5 - px_f * 0.5) * units_per_px;
            const uy = c + (@as(f64, @floatFromInt(row)) + 0.5 - px_f * 0.5) * units_per_px;
            const d_px = glyphDistance(ux, uy, n_spaces, current) / units_per_px;
            const cov = math.clamp(0.5 - d_px, 0.0, 1.0);
            alpha[row * px + col] = @intFromFloat(@round(cov * 255.0));
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

fn at(alpha: []const u8, px: usize, x: f64, y: f64) u8 {
    // Unit-box coordinates -> nearest pixel.
    const px_f: f64 = @floatFromInt(px);
    const units_per_px = EXTENT / (px_f * 0.5 - 1.0);
    const col: usize = @intFromFloat(@floor((x - BOX * 0.5) / units_per_px + px_f * 0.5));
    const row: usize = @intFromFloat(@floor((y - BOX * 0.5) / units_per_px + px_f * 0.5));
    return alpha[row * px + col];
}

test "status glyph: iris sits on the current Space with a clear pupil" {
    const px = 64;
    var buf: [px * px]u8 = undefined;
    for ([_]usize{ 1, 2, 3, 5, 8, 12, 16 }) |n| {
        for (0..n) |cur| {
            render(&buf, px, n, cur);
            const a = spaceAngle(cur, n);
            const cx = BOX * 0.5 + RING_R * @cos(a);
            const cy = BOX * 0.5 + RING_R * @sin(a);
            const ir = irisRadius(n);
            // Pupil centre is a hole, iris body is ink.
            try std.testing.expect(at(&buf, px, cx, cy) < 40);
            try std.testing.expect(at(&buf, px, cx + ir * 0.72 * @cos(a), cy + ir * 0.72 * @sin(a)) > 200);
        }
    }
}

test "status glyph: one arc per Space, separated by gaps" {
    const px = 96;
    var buf: [px * px]u8 = undefined;
    const n = 8;
    render(&buf, px, n, 0);
    // Opposite the eye, every arc midpoint is ink and every boundary between arcs is a gap.
    for (2..7) |k| {
        const mid = spaceAngle(k, n);
        const edge = mid + math.pi / @as(f64, n);
        try std.testing.expect(at(&buf, px, BOX * 0.5 + RING_R * @cos(mid), BOX * 0.5 + RING_R * @sin(mid)) > 200);
        try std.testing.expect(at(&buf, px, BOX * 0.5 + RING_R * @cos(edge), BOX * 0.5 + RING_R * @sin(edge)) < 60);
    }
}

test "status glyph: iris scales with its arc and stays clamped" {
    try std.testing.expectApproxEqAbs(EYE_MAX * 0.5, irisRadius(1), 1e-9);
    try std.testing.expectApproxEqAbs(EYE_MAX * 0.5, irisRadius(3), 1e-9);
    try std.testing.expectApproxEqAbs(EYE_MIN * 0.5, irisRadius(16), 1e-9);
    try std.testing.expect(irisRadius(8) > irisRadius(12));
    // 0 Spaces / out-of-range index never crash.
    var buf: [24 * 24]u8 = undefined;
    render(&buf, 24, 0, 7);
    render(&buf, 24, 4, 99);
}

test "status glyph: ink stays inside the image edge" {
    const px = 36;
    var buf: [px * px]u8 = undefined;
    for (1..17) |n| {
        render(&buf, px, n, 0);
        for (0..px) |i| {
            try std.testing.expect(buf[i] < 128); // top row
            try std.testing.expect(buf[(px - 1) * px + i] < 128); // bottom row
        }
    }
}

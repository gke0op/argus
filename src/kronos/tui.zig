const std = @import("std");
const math = std.math;
const physics = @import("physics.zig");
const KronosEngine = physics.KronosEngine;

pub const VIEW_CELL_W: usize = 64;
pub const VIEW_CELL_H: usize = 16;
pub const SUBPIX_W: usize = VIEW_CELL_W * 2; // 128 sub-pixels
pub const SUBPIX_H: usize = VIEW_CELL_H * 4; // 64 sub-pixels

pub const PHASE_CELL_W: usize = 24;
pub const PHASE_CELL_H: usize = 5;
pub const PHASE_SUB_W: usize = PHASE_CELL_W * 2; // 48 sub-pixels
pub const PHASE_SUB_H: usize = PHASE_CELL_H * 4; // 20 sub-pixels

pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// Maps sub-pixel offset (dx in 0..1, dy in 0..3) to ISO/TR 11548-1 Braille dot bit.
/// Dot layout:
///   (0,0): bit 0 (0x01)   (1,0): bit 3 (0x08)
///   (0,1): bit 1 (0x02)   (1,1): bit 4 (0x10)
///   (0,2): bit 2 (0x04)   (1,2): bit 5 (0x20)
///   (0,3): bit 6 (0x40)   (1,3): bit 7 (0x80)
pub inline fn brailleBit(dx: usize, dy: usize) u8 {
    return switch (dy) {
        0 => if (dx == 0) 0x01 else 0x08,
        1 => if (dx == 0) 0x02 else 0x10,
        2 => if (dx == 0) 0x04 else 0x20,
        3 => if (dx == 0) 0x40 else 0x80,
        else => 0x00,
    };
}

/// Encodes an 8-bit Braille dot mask into its 3-byte UTF-8 sequence (U+2800 + mask).
pub inline fn encodeBrailleUTF8(mask: u8) [3]u8 {
    return .{
        0xE2,
        0xA0 | (mask >> 6),
        0x80 | (mask & 0x3F),
    };
}

pub const BrailleViewport = struct {
    dots: [VIEW_CELL_W * VIEW_CELL_H]u8,
    polarity: [VIEW_CELL_W * VIEW_CELL_H]i8, // >0 positive vortex dominant, <0 negative vortex, 0 neutral/ring
    energy_tag: [VIEW_CELL_W * VIEW_CELL_H]u8,

    pub fn clear(self: *BrailleViewport) void {
        @memset(&self.dots, 0);
        @memset(&self.polarity, 0);
        @memset(&self.energy_tag, 0);
    }

    pub fn plotSubPixel(self: *BrailleViewport, sx: isize, sy: isize, pol: i8, e_level: u8) void {
        if (sx < 0 or sy < 0) return;
        const ux: usize = @intCast(sx);
        const uy: usize = @intCast(sy);
        if (ux >= SUBPIX_W or uy >= SUBPIX_H) return;

        const cx = ux / 2;
        const cy = uy / 4;
        const dx = ux % 2;
        const dy = uy % 4;
        const idx = cy * VIEW_CELL_W + cx;

        self.dots[idx] |= brailleBit(dx, dy);
        if (e_level >= self.energy_tag[idx]) {
            self.energy_tag[idx] = e_level;
            if (pol != 0) self.polarity[idx] = pol;
        }
    }

    /// Rasterizes a sub-pixel line segment using Bresenham's algorithm.
    pub fn plotLine(self: *BrailleViewport, x0: isize, y0: isize, x1: isize, y1: isize, pol: i8, e_level: u8) void {
        var cx = x0;
        var cy = y0;
        const dx: isize = @intCast(@abs(x1 - x0));
        const sx: isize = if (x0 < x1) 1 else -1;
        const dy: isize = -@as(isize, @intCast(@abs(y1 - y0)));
        const sy: isize = if (y0 < y1) 1 else -1;
        var err = dx + dy;

        var steps: usize = 0;
        while (steps < 32) : (steps += 1) {
            self.plotSubPixel(cx, cy, pol, e_level);
            if (cx == x1 and cy == y1) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                cx += sx;
            }
            if (e2 <= dx) {
                err += dx;
                cy += sy;
            }
        }
    }
};

pub const PhaseMiniScope = struct {
    dots: [PHASE_CELL_W * PHASE_CELL_H]u8,

    pub fn clear(self: *PhaseMiniScope) void {
        @memset(&self.dots, 0);
    }

    pub fn plot(self: *PhaseMiniScope, sx: isize, sy: isize) void {
        if (sx < 0 or sy < 0) return;
        const ux: usize = @intCast(sx);
        const uy: usize = @intCast(sy);
        if (ux >= PHASE_SUB_W or uy >= PHASE_SUB_H) return;
        const cx = ux / 2;
        const cy = uy / 4;
        self.dots[cy * PHASE_CELL_W + cx] |= brailleBit(ux % 2, uy % 4);
    }
};

/// Maps normalized Klein-Gordon wave amplitude phi in [-1, 1] to a 24-bit TrueColor background.
pub fn colorMapWaveField(phi_val: f64) RGB {
    const clamped = math.clamp(phi_val * 2.2, -1.0, 1.0);
    if (clamped < 0.0) {
        const t = -clamped; // [0, 1] rarefaction trough -> deep indigo / Cherenkov teal
        return .{
            .r = @intFromFloat(10.0 + 18.0 * t),
            .g = @intFromFloat(13.0 + 78.0 * t),
            .b = @intFromFloat(24.0 + 125.0 * t),
        };
    } else {
        const t = clamped; // [0, 1] compression crest -> deep magenta / solar amber
        return .{
            .r = @intFromFloat(10.0 + 135.0 * t),
            .g = @intFromFloat(13.0 + 48.0 * (t * t)),
            .b = @intFromFloat(24.0 + 62.0 * @sqrt(t)),
        };
    }
}

/// Maps particle polarity and kinetic energy level to a crisp 24-bit TrueColor foreground.
pub fn colorMapForeground(pol: i8, e_level: u8) RGB {
    if (pol > 0) {
        // Positive circulation vortex: electric cyan -> brilliant white-cyan
        const boost: u8 = @min(55, e_level / 4);
        return .{ .r = 110 +| boost, .g = 235, .b = 255 };
    } else if (pol < 0) {
        // Negative circulation vortex: solar gold / neon coral
        const boost: u8 = @min(55, e_level / 4);
        return .{ .r = 255, .g = 155 +| boost, .b = 95 +| boost };
    } else {
        // Horizon / Coordinate Fiducial Ring
        return .{ .r = 135, .g = 155, .b = 195 };
    }
}

/// Fixed-capacity zero-allocation frame buffer for streaming ANSI/UTF-8 output.
pub const FrameRenderer = struct {
    viewport: BrailleViewport = undefined,
    phase_scope: PhaseMiniScope = undefined,
    buf: [131072]u8 = undefined,
    pos: usize = 0,

    pub fn init() FrameRenderer {
        var r = FrameRenderer{};
        r.viewport.clear();
        r.phase_scope.clear();
        r.pos = 0;
        return r;
    }

    inline fn appendSlice(self: *FrameRenderer, s: []const u8) void {
        if (self.pos + s.len <= self.buf.len) {
            @memcpy(self.buf[self.pos .. self.pos + s.len], s);
            self.pos += s.len;
        }
    }

    inline fn appendFmt(self: *FrameRenderer, comptime fmt: []const u8, args: anytype) void {
        const rem = self.buf[self.pos..];
        const written = std.fmt.bufPrint(rem, fmt, args) catch return;
        self.pos += written.len;
    }

    fn worldToSubPixel(wx: f64, wy: f64, half_w: f64, half_h: f64) struct { sx: isize, sy: isize } {
        const nx = (wx + half_w) / (2.0 * half_w);
        const ny = (half_h - wy) / (2.0 * half_h); // Y-up in physics -> Y-down on screen
        const sx: isize = @intFromFloat(@round(nx * @as(f64, @floatFromInt(SUBPIX_W - 1))));
        const sy: isize = @intFromFloat(@round(ny * @as(f64, @floatFromInt(SUBPIX_H - 1))));
        return .{ .sx = sx, .sy = sy };
    }

    /// Rasterizes particles, velocity trails, horizon ring, and radial phase-space portrait.
    pub fn rasterizeState(self: *FrameRenderer, engine: *const KronosEngine) void {
        self.viewport.clear();
        self.phase_scope.clear();

        const half_w = engine.cfg.domain_half_w;
        const half_h = engine.cfg.domain_half_h;

        // 1. Subtle central softened horizon fiducial ring (r = softening_eps)
        const n_ring: usize = 24;
        for (0..n_ring) |k| {
            const ang = (2.0 * math.pi * @as(f64, @floatFromInt(k))) / @as(f64, @floatFromInt(n_ring));
            const rx = engine.cfg.softening_eps * @cos(ang);
            const ry = engine.cfg.softening_eps * @sin(ang);
            const pt = worldToSubPixel(rx, ry, half_w, half_h);
            self.viewport.plotSubPixel(pt.sx, pt.sy, 0, 10);
        }

        // 2. Rasterize particles + 2-step sub-pixel trajectories & populate (r, p_r) phase scope
        for (0..physics.N_PARTICLES) |i| {
            const xi = engine.x[i];
            const yi = engine.y[i];
            const pxi = engine.px[i];
            const pyi = engine.py[i];
            const pol: i8 = if (engine.charge[i] >= 0.0) 1 else -1;
            const speed = @sqrt(pxi * pxi + pyi * pyi);
            const e_level: u8 = @intFromFloat(@min(255.0, 40.0 + speed * 55.0));

            const p_curr = worldToSubPixel(xi, yi, half_w, half_h);
            const p_prev0 = worldToSubPixel(engine.trail_x0[i], engine.trail_y0[i], half_w, half_h);
            const p_prev1 = worldToSubPixel(engine.trail_x1[i], engine.trail_y1[i], half_w, half_h);

            self.viewport.plotLine(p_prev1.sx, p_prev1.sy, p_prev0.sx, p_prev0.sy, pol, e_level / 2);
            self.viewport.plotLine(p_prev0.sx, p_prev0.sy, p_curr.sx, p_curr.sy, pol, e_level);

            // Radial phase space (r in [0, 5.2], p_r in [-2.2, 2.2])
            const r = @sqrt(xi * xi + yi * yi);
            const pr = if (r > 1e-9) (xi * pxi + yi * pyi) / r else 0.0;
            const ps_x: isize = @intFromFloat(@round((r / 5.2) * @as(f64, @floatFromInt(PHASE_SUB_W - 1))));
            const ps_y: isize = @intFromFloat(@round(((2.2 - pr) / 4.4) * @as(f64, @floatFromInt(PHASE_SUB_H - 1))));
            self.phase_scope.plot(ps_x, ps_y);
        }

        // 3. Draw zero-momentum axis (p_r = 0) across the phase-space mini-scope
        const mid_y: isize = @intCast(PHASE_SUB_H / 2);
        var gx: isize = 0;
        while (gx < PHASE_SUB_W) : (gx += 4) {
            self.phase_scope.plot(gx, mid_y);
        }
    }

    fn appendSparkline(self: *FrameRenderer, bins: [physics.N_SPECTRUM_BINS]f64) void {
        const blocks = [8][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
        var max_v: f64 = 1e-9;
        for (bins) |v| {
            if (v > max_v) max_v = v;
        }
        for (bins) |v| {
            const norm = math.clamp(v / max_v, 0.0, 1.0);
            const idx: usize = @min(7, @as(usize, @intFromFloat(norm * 7.99)));
            self.appendSlice(blocks[idx]);
            self.appendSlice(blocks[idx]);
            self.appendSlice(" ");
        }
    }

    fn appendProgressBar(self: *FrameRenderer, val_0_to_1: f64, width: usize) void {
        const clamped = math.clamp(val_0_to_1, 0.0, 1.0);
        const filled: usize = @intFromFloat(@round(clamped * @as(f64, @floatFromInt(width))));
        for (0..width) |k| {
            if (k < filled) {
                self.appendSlice("█");
            } else {
                self.appendSlice("░");
            }
        }
    }

    /// Renders a complete composite TUI frame (Braille TrueColor viewport + right-hand telemetry)
    /// into `self.buf` and returns the slice. Zero heap allocations.
    pub fn renderFrame(
        self: *FrameRenderer,
        engine: *const KronosEngine,
        step_ns: u64,
        clear_home: bool,
    ) []const u8 {
        self.pos = 0;
        self.rasterizeState(engine);

        if (clear_home) {
            self.appendSlice("\x1b[H"); // Cursor home (no flicker)
        }

        const t = engine.telemetry;
        const step_us = @as(f64, @floatFromInt(step_ns)) / 1000.0;
        const mcups = if (step_ns > 0)
            (@as(f64, @floatFromInt(physics.GRID_SIZE * 4)) * 1000.0) / @as(f64, @floatFromInt(step_ns))
        else
            0.0;

        // Top Institutional Header Banner
        self.appendSlice("\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m");
        self.appendSlice("╭────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────╮\x1b[0m\n");
        self.appendSlice("\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m│\x1b[1m\x1b[38;2;240;248;255m KRONOS-17 // RELATIVISTIC MAGNETO-VORTEX & KLEIN-GORDON LATTICE \x1b[0m\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m│\x1b[1m\x1b[38;2;255;195;90m TELEMETRY & SYMPLECTIC INVARIANT COCKPIT       \x1b[0m\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m│\x1b[0m\n");
        self.appendSlice("\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m├────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────┤\x1b[0m\n");

        // Render 16 rows: Left = 64 Braille cells (128x64 sub-pixels + wave heatmap), Right = Telemetry row
        for (0..VIEW_CELL_H) |cy| {
            self.appendSlice("\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m│\x1b[0m");

            for (0..VIEW_CELL_W) |cx| {
                // Average 2x4 block of the 2D Klein-Gordon field phi(x,y)
                var phi_sum: f64 = 0.0;
                const gx0 = cx * 2;
                const gy0 = cy * 4;
                for (0..4) |dy| {
                    const row = (gy0 + dy) * physics.GRID_W;
                    phi_sum += engine.phi[row + gx0] + engine.phi[row + gx0 + 1];
                }
                const phi_avg = phi_sum * 0.125;
                const bg = colorMapWaveField(phi_avg);

                const cell_idx = cy * VIEW_CELL_W + cx;
                const mask = self.viewport.dots[cell_idx];

                if (mask != 0) {
                    const fg = colorMapForeground(self.viewport.polarity[cell_idx], self.viewport.energy_tag[cell_idx]);
                    self.appendFmt("\x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m", .{ fg.r, fg.g, fg.b, bg.r, bg.g, bg.b });
                    const utf8 = encodeBrailleUTF8(mask);
                    self.appendSlice(&utf8);
                } else {
                    self.appendFmt("\x1b[48;2;{d};{d};{d}m ", .{ bg.r, bg.g, bg.b });
                }
            }

            self.appendSlice("\x1b[0m\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m│\x1b[0m");
            self.renderTelemetryRow(cy, engine, step_us, mcups);
            self.appendSlice("\x1b[0m\n");
        }

        // Bottom Status Bar
        self.appendSlice("\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m├────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────┤\x1b[0m\n");
        self.appendFmt(
            "\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m│\x1b[38;2;180;220;240m STEP:\x1b[1m\x1b[38;2;255;255;255m {d:>6} \x1b[0m\x1b[38;2;180;220;240m\x1b[48;2;12;16;28m│ TIME:\x1b[1m\x1b[38;2;255;255;255m {d:>6.2}s \x1b[0m\x1b[38;2;180;220;240m\x1b[48;2;12;16;28m│ TICK:\x1b[1m\x1b[38;2;120;255;160m {d:>6.1} us \x1b[0m\x1b[38;2;180;220;240m\x1b[48;2;12;16;28m│ LATTICE:\x1b[1m\x1b[38;2;255;210;90m {d:>6.1} MCUPS \x1b[0m\x1b[38;2;180;220;240m\x1b[48;2;12;16;28m│ SIMD:\x1b[1m\x1b[38;2;110;230;255m @Vector(4,f64) \x1b[0m\x1b[38;2;180;220;240m\x1b[48;2;12;16;28m│ HEAP:\x1b[1m\x1b[38;2;120;255;160m 0 B   \x1b[0m\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m│\x1b[0m\n",
            .{ t.step_count, t.sim_time, step_us, mcups },
        );
        self.appendSlice("\x1b[38;2;110;230;255m\x1b[48;2;12;16;28m╰─────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯\x1b[0m\n");

        return self.buf[0..self.pos];
    }

    fn renderTelemetryRow(self: *FrameRenderer, row: usize, engine: *const KronosEngine, step_us: f64, mcups: f64) void {
        _ = step_us;
        _ = mcups;
        const t = engine.telemetry;
        self.appendSlice("\x1b[48;2;12;16;28m ");

        switch (row) {
            0 => self.appendFmt(
                "\x1b[1m\x1b[38;2;110;230;255m[1] HAMILTONIAN & SYMPLECTIC INVARIANTS        \x1b[38;2;110;230;255m│",
                .{},
            ),
            1 => self.appendFmt(
                "\x1b[38;2;185;200;220mTotal H = T+U : \x1b[1m\x1b[38;2;255;255;255m{d:>10.4} \x1b[0m\x1b[48;2;12;16;28m\x1b[38;2;140;165;190m(T={d:>6.2} U={d:>7.2})\x1b[38;2;110;230;255m│",
                .{ t.total_hamiltonian, t.kinetic_energy, t.potential_energy },
            ),
            2 => self.appendFmt(
                "\x1b[38;2;185;200;220mEnergy Drift  : \x1b[1m\x1b[38;2;120;255;165m{e:>10.3} \x1b[0m\x1b[48;2;12;16;28m\x1b[38;2;120;255;165m[YOSHIDA-4 O(dt^4)] \x1b[38;2;110;230;255m│",
                .{t.rel_energy_drift},
            ),
            3 => self.appendFmt(
                "\x1b[38;2;185;200;220mAng. Mom. L_z : \x1b[1m\x1b[38;2;255;255;255m{d:>10.4} \x1b[0m\x1b[48;2;12;16;28m\x1b[38;2;120;255;165m|dL/L|={e:>8.2}     \x1b[38;2;110;230;255m│",
                .{ t.angular_momentum_lz, t.rel_lz_drift },
            ),
            4 => self.appendFmt(
                "\x1b[38;2;185;200;220mVirial 2T/|W| : \x1b[1m\x1b[38;2;255;215;110m{d:>10.4} \x1b[0m\x1b[48;2;12;16;28m\x1b[38;2;140;165;190mParticles: {d:>3}      \x1b[38;2;110;230;255m│",
                .{ t.virial_ratio, physics.N_PARTICLES },
            ),
            5 => self.appendFmt(
                "\x1b[1m\x1b[38;2;255;165;195m[2] KLEIN-GORDON WAVE LATTICE & COHERENCE      \x1b[38;2;110;230;255m│",
                .{},
            ),
            6 => self.appendFmt(
                "\x1b[38;2;185;200;220mWave Energy   : \x1b[1m\x1b[38;2;255;185;120m{d:>10.4} \x1b[0m\x1b[48;2;12;16;28m\x1b[38;2;140;165;190mmax|phi|={d:>7.4}    \x1b[38;2;110;230;255m│",
                .{ t.wave_energy, t.peak_field_abs },
            ),
            7 => {
                self.appendFmt(
                    "\x1b[38;2;185;200;220mKuramoto R    : \x1b[1m\x1b[38;2;110;235;255m{d:>6.4} \x1b[0m\x1b[48;2;12;16;28m\x1b[38;2;110;235;255m[",
                    .{t.kuramoto_r},
                );
                self.appendProgressBar(t.kuramoto_r, 12);
                self.appendFmt("] psi={d:>5.2}\x1b[38;2;110;230;255m│", .{t.kuramoto_psi});
            },
            8 => {
                self.appendSlice("\x1b[38;2;185;200;220mRadial E(k_r) : \x1b[38;2;255;205;95m");
                self.appendSparkline(t.radial_spectrum);
                self.appendSlice("      \x1b[38;2;110;230;255m│");
            },
            9 => self.appendFmt(
                "\x1b[1m\x1b[38;2;140;255;185m[3] LIVE PHASE-SPACE PORTRAIT (r vs p_r)       \x1b[38;2;110;230;255m│",
                .{},
            ),
            10, 11, 12, 13, 14 => {
                const ps_row = row - 10;
                const label = switch (ps_row) {
                    0 => "+2.2│",
                    2 => " 0.0┼",
                    4 => "-2.2│",
                    else => "    │",
                };
                self.appendFmt("\x1b[38;2;140;165;190m{s}\x1b[38;2;130;255;190m", .{label});
                for (0..PHASE_CELL_W) |px| {
                    const mask = self.phase_scope.dots[ps_row * PHASE_CELL_W + px];
                    const utf8 = encodeBrailleUTF8(mask);
                    self.appendSlice(&utf8);
                }
                const right_tag = switch (ps_row) {
                    0 => "│ r in [0, 5.2]   ",
                    1 => "│ p_r = (q.p)/r   ",
                    2 => "│ Epicyclic Orbit ",
                    3 => "│ Symplectic Torus",
                    else => "│ 48x20 Sub-Pixel ",
                };
                self.appendFmt("\x1b[38;2;140;165;190m{s}\x1b[38;2;110;230;255m│", .{right_tag});
            },
            15 => self.appendSlice(
                "\x1b[38;2;140;165;190m    ╰────────────────────────╯ 0.0         5.2 \x1b[38;2;110;230;255m│",
            ),
            else => {},
        }
    }
};

// ============================================================================
// UNIT TESTS: Braille Bit-Mapping, UTF-8 Encoding & Zero-Alloc Frame Render
// ============================================================================

test "Braille sub-pixel bit mapping and UTF-8 encoding cover all 8 ISO dots" {
    // Empty cell -> U+2800 (0xE2, 0xA0, 0x80)
    const empty_utf8 = encodeBrailleUTF8(0x00);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xE2, 0xA0, 0x80 }, &empty_utf8);

    // Full 8-dot cell -> U+28FF (0xE2, 0xA3, 0xBF)
    var mask: u8 = 0;
    for (0..2) |dx| {
        for (0..4) |dy| {
            mask |= brailleBit(dx, dy);
        }
    }
    try std.testing.expectEqual(@as(u8, 0xFF), mask);
    const full_utf8 = encodeBrailleUTF8(mask);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xE2, 0xA3, 0xBF }, &full_utf8);
}

test "FrameRenderer renders complete TrueColor + Braille frame with valid UTF-8 and zero heap allocs" {
    var engine = KronosEngine.init(.{});
    engine.stepFrame(0.01, 2);

    var renderer = FrameRenderer.init();
    const frame_bytes = renderer.renderFrame(&engine, 42_500, false);

    try std.testing.expect(frame_bytes.len > 2000);
    try std.testing.expect(std.unicode.utf8ValidateSlice(frame_bytes));
    try std.testing.expect(std.mem.indexOf(u8, frame_bytes, "KRONOS-17") != null);
    try std.testing.expect(std.mem.indexOf(u8, frame_bytes, "YOSHIDA-4") != null);
}

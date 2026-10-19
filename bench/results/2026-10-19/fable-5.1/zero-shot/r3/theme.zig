// themes/Fable_Field.zig — ARGUS-BENCH Track B (Symplectic / PDE Field Dynamics)
//
// A damped 2-D wave equation (u_tt = c^2 ∇²u − γ u_t) integrated with a
// position-Verlet (leapfrog) scheme on a fixed 480×300 cell lattice, driven by
// three oscillating point sources that sweep the basin on Lissajous paths
// (leaving Doppler wakes) plus deterministic LCG rain drops. Each cell is
// shaded from its height and surface gradient (directional lighting), mapped
// through a 1024-entry deep-water palette, and bilinearly upsampled to the
// framebuffer with precomputed integer column/row maps so draw() is pure
// table lookups and integer arithmetic. Zero per-pixel transcendentals.
//
// Gate notes:
//   * One heap allocation: alloc.create(State). Every array lives in State.
//   * All framebuffer writes go through y * stride + x; nothing touches [w..stride).
//   * Every pixel in 0..w × 0..h is written with sdk.packRGBA (alpha 0xFF).
//   * The lattice is resolution independent (watchdog 320x200 maps onto the same grid).
//   * CFL-stable (c² = 0.3 < 0.5), damped, bounded injection, clamped before casts.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

// Simulation lattice (comptime ints so they coerce wherever they are used).
const GW = 480;
const GH = 300;
const GN = GW * GH;
const GWF: f32 = 480.0;
const GHF: f32 = 300.0;

const PAL_N = 1024;
const PAL_MAX_F: f32 = 1023.0;

const KR = 6; // drop kernel radius (cells)
const KW = 2 * KR + 1; // kernel width
const KRF: f32 = 6.0;

const SUBSTEPS: usize = 3;
const SUB_F: f64 = 3.0;
const NSRC: usize = 3;

const C2: f32 = 0.30; // wave speed squared (cells² / substep²), CFL-safe
const DAMP: f32 = 0.994; // velocity retention per substep
const DROP_EVERY: u32 = 22; // substeps between rain drops

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    cur: usize,
    rng: u64,
    substep_count: u32,

    field: [2][GN]f32,
    shade: [GN]u16,
    kernel: [KW * KW]f32,
    palette: [PAL_N]u32,
    col_idx: [MAX_W]u16,
    col_frac: [MAX_W]u16,
    row_idx: [MAX_H]u16,
    row_frac: [MAX_H]u16,
    vig_col: [MAX_W]u16,
    vig_row: [MAX_H]u16,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.cur = 0;
        self.rng = 0x9E3779B97F4A7C15;
        self.substep_count = 0;

        @memset(&self.field[0], 0.0);
        @memset(&self.field[1], 0.0);
        @memset(&self.shade, 0);
        @memset(&self.kernel, 0.0);
        @memset(&self.palette, sdk.packRGBA(0, 0, 0));
        @memset(&self.col_idx, 0);
        @memset(&self.col_frac, 0);
        @memset(&self.row_idx, 0);
        @memset(&self.row_frac, 0);
        @memset(&self.vig_col, 256);
        @memset(&self.vig_row, 256);

        // Smooth radial drop kernel: (1 - r²)².
        for (0..KW) |ky| {
            for (0..KW) |kx| {
                const dx: f32 = @as(f32, @floatFromInt(kx)) - KRF;
                const dy: f32 = @as(f32, @floatFromInt(ky)) - KRF;
                const r2: f32 = (dx * dx + dy * dy) / (KRF * KRF);
                const kv: f32 = if (r2 < 1.0) (1.0 - r2) * (1.0 - r2) else 0.0;
                self.kernel[ky * KW + kx] = kv;
            }
        }

        // Deep-water palette, 1024 entries.
        for (0..PAL_N) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / PAL_MAX_F;
            self.palette[i] = paletteColor(t);
        }

        // Column / row maps: framebuffer pixel -> lattice cell index + 8-bit fraction.
        const wd: usize = if (self.w > 1) self.w - 1 else 1;
        for (0..self.w) |x| {
            const t: usize = (x * (GW - 1) * 256) / wd;
            var gi: usize = t >> 8;
            var fr: usize = t & 255;
            if (gi >= GW - 1) {
                gi = GW - 2;
                fr = 255;
            }
            self.col_idx[x] = @as(u16, @intCast(gi));
            self.col_frac[x] = @as(u16, @intCast(fr));

            const nx: f32 = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(wd)) * 2.0 - 1.0;
            const n2: f32 = nx * nx;
            const v: f32 = 1.0 - 0.22 * n2 * n2;
            self.vig_col[x] = @as(u16, @intFromFloat(math.clamp(v, 0.0, 1.0) * 256.0));
        }

        const hd: usize = if (self.h > 1) self.h - 1 else 1;
        for (0..self.h) |y| {
            const t: usize = (y * (GH - 1) * 256) / hd;
            var gi: usize = t >> 8;
            var fr: usize = t & 255;
            if (gi >= GH - 1) {
                gi = GH - 2;
                fr = 255;
            }
            self.row_idx[y] = @as(u16, @intCast(gi));
            self.row_frac[y] = @as(u16, @intCast(fr));

            const ny: f32 = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(hd)) * 2.0 - 1.0;
            const n2: f32 = ny * ny;
            const v: f32 = 1.0 - 0.22 * n2 * n2;
            self.vig_row[y] = @as(u16, @intFromFloat(math.clamp(v, 0.0, 1.0) * 256.0));
        }

        // Seed the basin so the very first frame already has structure.
        for (0..7) |_| {
            self.randomDrop(1.0);
        }
        self.computeShade();

        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        const t0: f64 = self.time_sec;
        self.time_sec += dt;

        for (0..SUBSTEPS) |k| {
            const frac: f64 = @as(f64, @floatFromInt(k + 1)) / SUB_F;
            const t: f32 = @as(f32, @floatCast(t0 + dt * frac));
            self.waveStep();
            self.inject(t);
            self.substep_count +%= 1;
            if (self.substep_count % DROP_EVERY == 0) {
                self.randomDrop(0.9);
            }
        }

        self.computeShade();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        var tmp: [GW]u32 = undefined;

        for (0..self.h) |y| {
            const gy: usize = self.row_idx[y];
            const fy: u32 = self.row_frac[y];
            const ify: u32 = 256 - fy;
            const r0: usize = gy * GW;
            const r1: usize = r0 + GW;

            // Vertical lerp of the shade lattice into one 480-wide scanline.
            for (0..GW) |gx| {
                const a: u32 = self.shade[r0 + gx];
                const b: u32 = self.shade[r1 + gx];
                tmp[gx] = (a * ify + b * fy) >> 8;
            }

            const vr: u32 = self.vig_row[y];
            const dst_row = buf[y * stride .. y * stride + w];
            for (dst_row, 0..) |*dst, x| {
                const ci: usize = self.col_idx[x];
                const fx: u32 = self.col_frac[x];
                const v: usize = (tmp[ci] * (256 - fx) + tmp[ci + 1] * fx) >> 8;
                const vc: u32 = self.vig_col[x];
                dst.* = sdk.scaleRGB(self.palette[v], (vr * vc) >> 8);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        const f = &self.field[self.cur];
        var i: usize = 0;
        while (i < GN) : (i += 37) {
            if (math.isNan(f[i]) or math.isInf(f[i])) return true;
        }
        return false;
    }

    // ---------------------------------------------------------------- internals

    /// One leapfrog substep of the damped wave equation. Border cells are never
    /// written and stay at 0 (reflecting rim, softened by the vignette).
    fn waveStep(self: *State) void {
        const src = &self.field[self.cur];
        const dst = &self.field[1 - self.cur]; // holds u_prev on entry, u_next on exit
        for (1..GH - 1) |y| {
            const row: usize = y * GW;
            for (1..GW - 1) |x| {
                const i: usize = row + x;
                const c: f32 = src[i];
                const lap: f32 = src[i - 1] + src[i + 1] + src[i - GW] + src[i + GW] - 4.0 * c;
                const vel: f32 = (c - dst[i]) * DAMP;
                dst[i] = c + vel + C2 * lap;
            }
        }
        self.cur = 1 - self.cur;
    }

    /// Three oscillating sources sweeping Lissajous paths across the basin.
    fn inject(self: *State, t: f32) void {
        const cur = &self.field[self.cur];
        for (0..NSRC) |k| {
            const kf: f32 = @as(f32, @floatFromInt(k));
            const px: f32 = 0.5 * GWF + 0.36 * GWF * @sin(t * (0.31 + 0.07 * kf) + kf * 2.1);
            const py: f32 = 0.5 * GHF + 0.36 * GHF * @sin(t * (0.47 + 0.05 * kf) + kf * 1.3 + 0.7);
            const amp: f32 = 0.22 * @sin(t * 9.0 + kf * 1.9);
            const ix: usize = @as(usize, @intFromFloat(math.clamp(px, 2.0, GWF - 3.0)));
            const iy: usize = @as(usize, @intFromFloat(math.clamp(py, 2.0, GHF - 3.0)));
            const i: usize = iy * GW + ix;
            cur[i] += amp;
            cur[i - 1] += amp * 0.5;
            cur[i + 1] += amp * 0.5;
            cur[i - GW] += amp * 0.5;
            cur[i + GW] += amp * 0.5;
        }
    }

    /// Deterministic LCG rain drop somewhere in the interior.
    fn randomDrop(self: *State, amp: f32) void {
        self.rng = self.rng *% 6364136223846793005 +% 1442695040888963407;
        const ra: u32 = @as(u32, @truncate(self.rng >> 32));
        self.rng = self.rng *% 6364136223846793005 +% 1442695040888963407;
        const rb: u32 = @as(u32, @truncate(self.rng >> 32));
        const gx: usize = KR + 1 + @as(usize, ra % (GW - 2 * KR - 2));
        const gy: usize = KR + 1 + @as(usize, rb % (GH - 2 * KR - 2));
        self.addDrop(gx, gy, amp);
    }

    /// Adds a smooth bump to both buffers (zero initial velocity -> expanding ring).
    fn addDrop(self: *State, gx: usize, gy: usize, amp: f32) void {
        const cur = &self.field[self.cur];
        const prev = &self.field[1 - self.cur];
        const x0: usize = gx - KR;
        const y0: usize = gy - KR;
        for (0..KW) |ky| {
            const yy: usize = y0 + ky;
            if (yy == 0 or yy >= GH - 1) continue;
            for (0..KW) |kx| {
                const xx: usize = x0 + kx;
                if (xx == 0 or xx >= GW - 1) continue;
                const kv: f32 = self.kernel[ky * KW + kx] * amp;
                cur[yy * GW + xx] += kv;
                prev[yy * GW + xx] += kv;
            }
        }
    }

    /// Height + directional-gradient lighting -> 10-bit palette index per cell.
    fn computeShade(self: *State) void {
        const f = &self.field[self.cur];
        for (0..GH) |y| {
            const ym: usize = if (y > 0) y - 1 else 0;
            const yp: usize = if (y + 1 < GH) y + 1 else GH - 1;
            const row: usize = y * GW;
            for (0..GW) |x| {
                const xm: usize = if (x > 0) x - 1 else 0;
                const xp: usize = if (x + 1 < GW) x + 1 else GW - 1;
                const c: f32 = f[row + x];
                const gx: f32 = f[row + xp] - f[row + xm];
                const gy: f32 = f[yp * GW + x] - f[ym * GW + x];
                const s: f32 = math.clamp(0.40 + 0.9 * c + 2.5 * gx - 1.5 * gy, 0.0, 1.0);
                self.shade[row + x] = @as(u16, @intFromFloat(s * PAL_MAX_F));
            }
        }
    }
};

fn toByte(v: f32) u8 {
    const c: f32 = math.clamp(v, 0.0, 255.0);
    return @as(u8, @intFromFloat(c));
}

fn mixColor(ca: [3]f32, cb: [3]f32, t: f32) u32 {
    const rr: f32 = ca[0] + (cb[0] - ca[0]) * t;
    const gg: f32 = ca[1] + (cb[1] - ca[1]) * t;
    const bb: f32 = ca[2] + (cb[2] - ca[2]) * t;
    return sdk.packRGBA(toByte(rr), toByte(gg), toByte(bb));
}

fn paletteColor(t: f32) u32 {
    const stops = [_][3]f32{
        .{ 3.0, 10.0, 32.0 },
        .{ 8.0, 52.0, 92.0 },
        .{ 16.0, 120.0, 140.0 },
        .{ 90.0, 200.0, 200.0 },
        .{ 240.0, 252.0, 255.0 },
    };
    const pos = [_]f32{ 0.0, 0.35, 0.60, 0.82, 1.0 };
    var i: usize = 0;
    while (i + 2 < pos.len and t > pos[i + 1]) : (i += 1) {}
    const span: f32 = pos[i + 1] - pos[i];
    const u: f32 = math.clamp((t - pos[i]) / span, 0.0, 1.0);
    return mixColor(stops[i], stops[i + 1], u);
}

comptime {
    sdk.exportTheme(State);
}

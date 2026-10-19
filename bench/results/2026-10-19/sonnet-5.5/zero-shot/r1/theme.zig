const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

// Sonnet_Field: a live 2D scalar wave equation ("ripple tank") with five moving,
// phase-locked point sources on Lissajous paths. The field is integrated on a
// coarse grid (one cell per 4x4 pixels) with a leapfrog scheme, absorbed by a
// sponge layer at the edges, then upsampled bilinearly and mapped through a
// two-sided palette LUT (positive crests cyan to white, troughs violet to gold).

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

const CELL: usize = 4;
const GW: usize = MAX_W / CELL + 2; // fixed row stride of the wave grid
const GH: usize = MAX_H / CELL + 2;
const GN: usize = GW * GH;
const NS: usize = 5; // number of sources
const SUB: usize = 4; // wave-equation substeps per step()
const K: f32 = 0.25; // (c*dt/dx)^2, stable for <= 0.5 in 2D
const SPONGE: usize = 16; // absorbing layer width in cells
const LUT_N: usize = 1024;
const TWO_PI: f64 = 2.0 * math.pi;
const SCALE: f32 = 1.6 * 512.0;

const SRC_PERIOD = [NS]f64{ 13.0, 15.5, 17.0, 11.5, 19.0 }; // substeps per cycle
const SRC_AX = [NS]f64{ 0.21, 0.17, 0.13, 0.25, 0.11 };
const SRC_AY = [NS]f64{ 0.15, 0.23, 0.19, 0.12, 0.27 };
const SRC_PX = [NS]f64{ 0.3, 1.7, 3.1, 4.4, 5.9 };
const SRC_PY = [NS]f64{ 1.1, 2.6, 0.4, 3.9, 5.2 };

fn edgeDamp(i: usize, n: usize) f32 {
    if (i >= n) return 0.0;
    const d: usize = @min(i, n - 1 - i);
    if (d >= SPONGE) return 0.9997;
    const q: f32 = @as(f32, @floatFromInt(SPONGE - d)) / @as(f32, @floatFromInt(SPONGE));
    return 0.9997 * (1.0 - 0.2 * q * q);
}

fn toQ(t: f32) u32 {
    const c = @min(@max(t, 0.0), 1.0);
    const q: u32 = @intFromFloat(c * 256.0);
    return q;
}

fn ramp(c0: u32, c1: u32, c2: u32, c3: u32, t: f32) u32 {
    const tt = @min(@max(t, 0.0), 1.0);
    if (tt < 0.4) return sdk.lerpRGB(c0, c1, toQ(tt / 0.4));
    if (tt < 0.75) return sdk.lerpRGB(c1, c2, toQ((tt - 0.4) / 0.35));
    return sdk.lerpRGB(c2, c3, toQ((tt - 0.75) / 0.25));
}

fn buildPalette(lut: *[LUT_N]u32) void {
    const navy = sdk.packRGBA(5, 9, 26);
    const teal = sdk.packRGBA(0, 110, 160);
    const cyan = sdk.packRGBA(110, 225, 255);
    const white = sdk.packRGBA(255, 255, 255);
    const purple = sdk.packRGBA(58, 14, 96);
    const crimson = sdk.packRGBA(205, 48, 92);
    const gold = sdk.packRGBA(255, 190, 80);
    for (0..LUT_N) |i| {
        const x: f32 = (@as(f32, @floatFromInt(i)) - 512.0) / 512.0;
        const s = @sqrt(@abs(x));
        if (x >= 0.0) {
            lut[i] = ramp(navy, teal, cyan, white, s);
        } else {
            lut[i] = ramp(navy, purple, crimson, gold, s);
        }
    }
}

pub const State = struct {
    w: usize,
    h: usize,
    gw: usize,
    gh: usize,
    scale: f64,
    time_sec: f64,
    ip: usize,
    ic: usize,
    inx: usize,
    phase: [NS]f64,
    damp_x: [GW]f32,
    damp_y: [GH]f32,
    lut: [LUT_N]u32,
    fld: [3][GN]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.gw = (self.w + CELL - 1) / CELL + 2;
        self.gh = (self.h + CELL - 1) / CELL + 2;
        self.scale = scale;
        self.time_sec = 0.0;
        self.ip = 0;
        self.ic = 1;
        self.inx = 2;
        self.phase = @splat(0.0);
        self.damp_x = @splat(0.0);
        self.damp_y = @splat(0.0);
        self.lut = @splat(sdk.packRGBA(0, 0, 0));
        for (&self.fld) |*f| {
            @memset(f, 0.0);
        }
        for (0..GW) |x| {
            self.damp_x[x] = edgeDamp(x, self.gw);
        }
        for (0..GH) |y| {
            self.damp_y[y] = edgeDamp(y, self.gh);
        }
        buildPalette(&self.lut);
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn substep(self: *State) void {
        const prev = &self.fld[self.ip];
        const cur = &self.fld[self.ic];
        const nxt = &self.fld[self.inx];
        const dxs = &self.damp_x;
        const gw = self.gw;
        const gh = self.gh;
        if (gh < 3 or gw < 3) return;
        for (1..gh - 1) |y| {
            const row = y * GW;
            const dy = self.damp_y[y];
            for (1..gw - 1) |x| {
                const i = row + x;
                const c = cur[i];
                const lap = cur[i - 1] + cur[i + 1] + cur[i - GW] + cur[i + GW] - 4.0 * c;
                nxt[i] = (2.0 * c - prev[i] + K * lap) * (dy * dxs[x]);
            }
        }
        const tmp = self.ip;
        self.ip = self.ic;
        self.ic = self.inx;
        self.inx = tmp;
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const t = self.time_sec;
        const fgw: f64 = @floatFromInt(self.gw);
        const fgh: f64 = @floatFromInt(self.gh);
        const hi_x: isize = @max(@as(isize, @intCast(self.gw)) - 4, 4);
        const hi_y: isize = @max(@as(isize, @intCast(self.gh)) - 4, 4);

        var cell: [NS]usize = undefined;
        for (0..NS) |s| {
            const fx = 0.5 + 0.34 * @sin(SRC_AX[s] * t + SRC_PX[s]);
            const fy = 0.5 + 0.34 * @sin(SRC_AY[s] * t + SRC_PY[s]);
            const xi: isize = @intFromFloat(fx * fgw);
            const yi: isize = @intFromFloat(fy * fgh);
            const xc: isize = math.clamp(xi, 3, hi_x);
            const yc: isize = math.clamp(yi, 3, hi_y);
            const ux: usize = @intCast(xc);
            const uy: usize = @intCast(yc);
            cell[s] = uy * GW + ux;
        }

        for (0..SUB) |_| {
            const cur = &self.fld[self.ic];
            for (0..NS) |s| {
                self.phase[s] += TWO_PI / SRC_PERIOD[s];
                if (self.phase[s] > TWO_PI) self.phase[s] -= TWO_PI;
                const v: f32 = @floatCast(@sin(self.phase[s]));
                const i = cell[s];
                cur[i] = v;
                cur[i - 1] = 0.6 * v;
                cur[i + 1] = 0.6 * v;
                cur[i - GW] = 0.6 * v;
                cur[i + GW] = 0.6 * v;
            }
            self.substep();
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const cur = &self.fld[self.ic];
        const lut = &self.lut;
        for (0..h) |y| {
            const cy = y >> 2;
            const wy: f32 = @as(f32, @floatFromInt(y & 3)) * 0.25;
            const base = cy * GW;
            const row = buf[y * stride .. y * stride + w];
            var cx: usize = 0;
            while (cx * CELL < w) : (cx += 1) {
                const a = cur[base + cx];
                const b = cur[base + cx + 1];
                const c = cur[base + GW + cx];
                const d = cur[base + GW + cx + 1];
                const l = a + (c - a) * wy;
                const r = b + (d - b) * wy;
                const dv = (r - l) * 0.25;
                var v = l;
                const x0 = cx * CELL;
                const rem = w - x0;
                const n: usize = if (rem < CELL) rem else CELL;
                for (0..n) |k| {
                    const tq = v * SCALE + 512.0;
                    const tc = @min(@max(tq, 0.0), 1023.0);
                    const idx: usize = @intFromFloat(tc);
                    row[x0 + k] = lut[idx];
                    v += dv;
                }
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        const cur = &self.fld[self.ic];
        var bad = false;
        for (cur) |v| {
            if (v != v or @abs(v) > 1.0e20) bad = true;
        }
        return bad;
    }
};

comptime {
    sdk.exportTheme(State);
}

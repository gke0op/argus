const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

// Ripple Tank: a live 2D scalar wave equation (u_tt = c^2 * laplacian(u)) on a
// 480x300 grid, driven by three orbiting point oscillators (moving sources, so
// the wavefronts show Doppler bunching), absorbed by a sponge layer at the
// edges, and rendered with bilinear upsampling + a height/slope shaded palette.

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const GW: usize = 480;
const GH: usize = 300;
const GN: usize = GW * GH;
const PAL_N: usize = 1024;

const NSRC: usize = 3;
const SUBSTEPS: usize = 3;
const C2: f32 = 0.40; // (c*dt/dx)^2, stable for 2D when <= 0.5
const OMEGA: f64 = 0.28; // radians per sub-step (about 14 cells per wavelength)
const DRIVE: f64 = 2.0;
const DAMP_BASE: f32 = 0.9997;
const SPONGE: f32 = 22.0;

const H_GAIN: f32 = 300.0;
const S_GAIN: f32 = 500.0;

const SRC_FX = [NSRC]f64{ 0.31, 0.23, 0.17 };
const SRC_FY = [NSRC]f64{ 0.27, 0.37, 0.21 };
const SRC_PX = [NSRC]f64{ 0.0, 2.1, 4.2 };
const SRC_PY = [NSRC]f64{ 1.0, 3.3, 5.1 };

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    phase: f64,
    cur: usize,

    // Two time levels of the wave field (current and previous).
    u: [2][GN]f32,

    damp_x: [GW]f32,
    damp_y: [GH]f32,

    pal: [PAL_N]u32,

    col_i: [MAX_W]u16,
    col_f: [MAX_W]f32,
    row_i: [MAX_H]u16,
    row_f: [MAX_H]f32,
    vig_x: [MAX_W]f32,
    vig_y: [MAX_H]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @max(@as(usize, 2), @min(w, MAX_W));
        self.h = @max(@as(usize, 2), @min(h, MAX_H));
        self.scale = scale;
        self.time_sec = 0.0;
        self.phase = 0.0;
        self.cur = 0;

        @memset(self.u[0][0..], 0.0);
        @memset(self.u[1][0..], 0.0);

        // Sponge damping tables.
        for (0..GW) |x| {
            const d: usize = @min(x, GW - 1 - x);
            const df: f32 = @floatFromInt(d);
            const q: f32 = @max(@as(f32, 0.0), SPONGE - df) / SPONGE;
            self.damp_x[x] = DAMP_BASE * (1.0 - 0.12 * q * q);
        }
        for (0..GH) |y| {
            const d: usize = @min(y, GH - 1 - y);
            const df: f32 = @floatFromInt(d);
            const q: f32 = @max(@as(f32, 0.0), SPONGE - df) / SPONGE;
            self.damp_y[y] = 1.0 - 0.12 * q * q;
        }

        // Palette: deep night blue -> teal -> cyan -> white crest.
        const stop_pos = [_]usize{ 0, 256, 512, 700, 880, 1023 };
        const stops = [_]u32{
            sdk.packRGBA(2, 4, 14),
            sdk.packRGBA(6, 28, 66),
            sdk.packRGBA(14, 68, 118),
            sdk.packRGBA(40, 150, 190),
            sdk.packRGBA(150, 222, 236),
            sdk.packRGBA(255, 255, 255),
        };
        var seg: usize = 0;
        for (0..PAL_N) |i| {
            while (seg + 2 < stop_pos.len and i >= stop_pos[seg + 1]) seg += 1;
            const p0: usize = stop_pos[seg];
            const p1: usize = stop_pos[seg + 1];
            const t: u32 = @intCast(((i - p0) * 256) / (p1 - p0));
            self.pal[i] = sdk.lerpRGB(stops[seg], stops[seg + 1], t);
        }

        // Pixel -> grid coordinate maps (bilinear), and vignette tables.
        const gxmax: f32 = @floatFromInt(GW - 1);
        const gymax: f32 = @floatFromInt(GH - 1);
        const wden: f32 = @floatFromInt(self.w - 1);
        const hden: f32 = @floatFromInt(self.h - 1);
        const wf: f32 = @floatFromInt(self.w);
        const hf: f32 = @floatFromInt(self.h);

        for (0..self.w) |x| {
            const xf: f32 = @floatFromInt(x);
            const gx: f32 = xf * gxmax / wden;
            const ii: usize = @min(@as(usize, @intFromFloat(@floor(gx))), GW - 2);
            const iif: f32 = @floatFromInt(ii);
            self.col_i[x] = @intCast(ii);
            self.col_f[x] = @min(@as(f32, 1.0), @max(@as(f32, 0.0), gx - iif));
            const nx: f32 = (xf + 0.5) / wf * 2.0 - 1.0;
            self.vig_x[x] = 110.0 * nx * nx;
        }
        for (0..self.h) |y| {
            const yf: f32 = @floatFromInt(y);
            const gy: f32 = yf * gymax / hden;
            const jj: usize = @min(@as(usize, @intFromFloat(@floor(gy))), GH - 2);
            const jjf: f32 = @floatFromInt(jj);
            self.row_i[y] = @intCast(jj);
            self.row_f[y] = @min(@as(f32, 1.0), @max(@as(f32, 0.0), gy - jjf));
            const ny: f32 = (yf + 0.5) / hf * 2.0 - 1.0;
            self.vig_y[y] = 110.0 * ny * ny;
        }
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn inject(self: *State) void {
        const t = self.time_sec;
        const cur: *[GN]f32 = &self.u[self.cur];
        const gwf: f64 = @floatFromInt(GW);
        const ghf: f64 = @floatFromInt(GH);
        for (0..NSRC) |k| {
            const kf: f64 = @floatFromInt(k);
            const sx: f64 = gwf * 0.5 + gwf * 0.30 * @sin(t * SRC_FX[k] + SRC_PX[k]);
            const sy: f64 = ghf * 0.5 + ghf * 0.28 * @sin(t * SRC_FY[k] + SRC_PY[k]);
            const bx: f64 = @floor(sx);
            const by: f64 = @floor(sy);
            const fx: f32 = @floatCast(sx - bx);
            const fy: f32 = @floatCast(sy - by);
            const ix: usize = @intFromFloat(bx);
            const iy: usize = @intFromFloat(by);
            const amp: f32 = @floatCast(DRIVE * @sin(self.phase + kf * 1.9));
            const o: usize = iy * GW + ix;
            cur[o] += amp * (1.0 - fx) * (1.0 - fy);
            cur[o + 1] += amp * fx * (1.0 - fy);
            cur[o + GW] += amp * (1.0 - fx) * fy;
            cur[o + GW + 1] += amp * fx * fy;
        }
    }

    fn waveStep(self: *State) void {
        const cur: *[GN]f32 = &self.u[self.cur];
        const prv: *[GN]f32 = &self.u[1 - self.cur];
        for (1..GH - 1) |y| {
            const o: usize = y * GW;
            const dyv: f32 = self.damp_y[y];
            for (1..GW - 1) |x| {
                const k: usize = o + x;
                const c: f32 = cur[k];
                const lap: f32 = cur[k - 1] + cur[k + 1] + cur[k - GW] + cur[k + GW] - 4.0 * c;
                const nv: f32 = 2.0 * c - prv[k] + C2 * lap;
                prv[k] = nv * dyv * self.damp_x[x];
            }
        }
        self.cur = 1 - self.cur;
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        for (0..SUBSTEPS) |_| {
            self.inject();
            self.waveStep();
            self.phase = @mod(self.phase + OMEGA, 2.0 * math.pi);
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        // Rows are addressed only through `y * stride`; columns >= w are never touched.
        const w = self.w;
        const g: *const [GN]f32 = &self.u[self.cur];
        var tmp: [GW]f32 = undefined;
        for (0..self.h) |y| {
            const r0: usize = self.row_i[y];
            const fy: f32 = self.row_f[y];
            const a_row = g[r0 * GW .. r0 * GW + GW];
            const b_row = g[(r0 + 1) * GW .. (r0 + 1) * GW + GW];
            for (0..GW) |i| {
                tmp[i] = a_row[i] + (b_row[i] - a_row[i]) * fy;
            }
            const vy: f32 = self.vig_y[y];
            const dst = buf[y * stride .. y * stride + w];
            for (dst, 0..) |*d, x| {
                const i: usize = self.col_i[x];
                const a: f32 = tmp[i];
                const b: f32 = tmp[i + 1];
                const slope: f32 = b - a;
                const hh: f32 = a + slope * self.col_f[x];
                const v: f32 = 512.0 + hh * H_GAIN + slope * S_GAIN - vy - self.vig_x[x];
                const c: f32 = @min(@max(v, 0.0), 1023.0);
                const idx: usize = @intFromFloat(c);
                d.* = self.pal[idx];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        var sum: f32 = 0.0;
        for (self.u[self.cur][0..]) |v| sum += v;
        return math.isNan(sum) or math.isInf(sum);
    }
};

comptime {
    sdk.exportTheme(State);
}

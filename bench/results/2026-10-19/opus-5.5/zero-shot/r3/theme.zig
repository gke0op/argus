// themes/Opus55_Field.zig
//
// Track B — Symplectic / PDE Field Dynamics: "Moonlit Rain Pond".
//
// A damped 2D scalar wave equation  u_tt = c^2 * Laplacian(u) - gamma * u_t
// is integrated on a coarse grid (one node per 6x6 screen pixels) with the
// explicit leapfrog (Verlet) scheme
//     u^{n+1} = C2 * (u_E + u_W + u_N + u_S) + (2 - 4*C2) * u^n - u^{n-1}
// with C2 = (c dt / dx)^2 = 0.4 (inside the 2D CFL limit of 0.5) and fixed
// (Dirichlet) shoreline boundaries. Raindrops are Gaussian depressions
// injected at rest; they ring out into dispersive capillary-like wavetrains
// that reflect off the banks and interfere. A slow two-component swell is
// superposed analytically, and the surface is lit by a low moon: the shading
// uses the surface slope (Lambert-like term plus a squared specular glint)
// weighted by a precomputed moon-glitter path.
//
// Render path (Pattern A): step() produces one f32 palette coordinate per
// grid node; draw() does a per-row vertical lerp over ~322 nodes and then a
// per-pixel horizontal lerp + 1024-entry palette lookup. No transcendentals
// in draw(). Single heap allocation (State, ~1.2 MiB), zero allocations after.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const CELL: usize = 6;
const GW_MAX: usize = MAX_W / CELL + 4;
const GH_MAX: usize = MAX_H / CELL + 4;
const GRID_MAX: usize = GW_MAX * GH_MAX;
const PAL_N: usize = 1024;

const SUB_DT: f64 = 1.0 / 90.0;
const MAX_SUBSTEPS: u32 = 6;
const C2: f32 = 0.4;
const SELF_W: f32 = 2.0 - 4.0 * C2;
const DAMP: f32 = 0.9965;

fn toU8(v: f32) u8 {
    const c: f32 = math.clamp(v, 0.0, 255.0);
    return @as(u8, @intFromFloat(c));
}

pub const State = struct {
    w: usize,
    h: usize,
    gw: usize,
    gh: usize,
    scale: f64,
    time_sec: f64,
    accum: f64,
    drop_timer: f64,
    rng: u64,
    cur_is_a: bool,

    field_a: [GRID_MAX]f32,
    field_b: [GRID_MAX]f32,
    shade: [GRID_MAX]f32,
    glow: [GRID_MAX]f32,
    palette: [PAL_N]u32,
    x_idx: [MAX_W]u16,
    x_frac: [MAX_W]f32,
    y_idx: [MAX_H]u16,
    y_frac: [MAX_H]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);

        const cw: usize = @min(w, MAX_W);
        const ch: usize = @min(h, MAX_H);
        self.w = @max(@as(usize, 1), cw);
        self.h = @max(@as(usize, 1), ch);

        const gw_raw: usize = @min(GW_MAX, self.w / CELL + 2);
        const gh_raw: usize = @min(GH_MAX, self.h / CELL + 2);
        self.gw = @max(@as(usize, 4), gw_raw);
        self.gh = @max(@as(usize, 4), gh_raw);

        self.scale = scale;
        self.time_sec = 0.0;
        self.accum = 0.0;
        self.drop_timer = 0.0;
        self.rng = 0x9E3779B97F4A7C15;
        self.cur_is_a = true;

        self.field_a = @splat(0.0);
        self.field_b = @splat(0.0);
        self.shade = @splat(0.0);
        self.glow = @splat(0.0);
        self.x_idx = @splat(0);
        self.x_frac = @splat(0.0);
        self.y_idx = @splat(0);
        self.y_frac = @splat(0.0);

        const cell_f: f32 = @floatFromInt(CELL);

        // Pixel -> grid mapping tables (horizontal).
        for (0..self.w) |x| {
            const gx: f32 = (@as(f32, @floatFromInt(x)) + 0.5) / cell_f;
            var ix: usize = @intFromFloat(@floor(gx));
            if (ix > self.gw - 2) ix = self.gw - 2;
            const fr: f32 = math.clamp(gx - @as(f32, @floatFromInt(ix)), 0.0, 1.0);
            self.x_idx[x] = @intCast(ix);
            self.x_frac[x] = fr;
        }
        // Pixel -> grid mapping tables (vertical).
        for (0..self.h) |y| {
            const gy: f32 = (@as(f32, @floatFromInt(y)) + 0.5) / cell_f;
            var iy: usize = @intFromFloat(@floor(gy));
            if (iy > self.gh - 2) iy = self.gh - 2;
            const fr: f32 = math.clamp(gy - @as(f32, @floatFromInt(iy)), 0.0, 1.0);
            self.y_idx[y] = @intCast(iy);
            self.y_frac[y] = fr;
        }

        // Palette: abyssal blue -> teal -> aqua -> moonlit silver.
        const stops = [_][4]f32{
            .{ 0.0, 1.0, 3.0, 10.0 },
            .{ 220.0, 4.0, 18.0, 40.0 },
            .{ 430.0, 10.0, 52.0, 82.0 },
            .{ 620.0, 24.0, 108.0, 132.0 },
            .{ 780.0, 70.0, 170.0, 190.0 },
            .{ 900.0, 170.0, 225.0, 235.0 },
            .{ 1023.0, 255.0, 252.0, 240.0 },
        };
        for (0..PAL_N) |i| {
            const t: f32 = @floatFromInt(i);
            var s: usize = 0;
            while (s + 2 < stops.len and t > stops[s + 1][0]) : (s += 1) {}
            const p0 = stops[s];
            const p1 = stops[s + 1];
            const f: f32 = math.clamp((t - p0[0]) / (p1[0] - p0[0]), 0.0, 1.0);
            const r: f32 = p0[1] + (p1[1] - p0[1]) * f;
            const g: f32 = p0[2] + (p1[2] - p0[2]) * f;
            const b: f32 = p0[3] + (p1[3] - p0[3]) * f;
            self.palette[i] = sdk.packRGBA(toU8(r), toU8(g), toU8(b));
        }

        // Moon-glitter path: a Gaussian column that widens toward the viewer.
        const gwf: f32 = @floatFromInt(self.gw);
        const ghm: f32 = @floatFromInt(self.gh - 1);
        for (0..self.gh) |gy| {
            const depth: f32 = @as(f32, @floatFromInt(gy)) / ghm;
            const sigma: f32 = gwf * (0.05 + 0.10 * depth);
            const inv2: f32 = 1.0 / (2.0 * sigma * sigma);
            const amp: f32 = 0.6 + 0.4 * depth;
            for (0..self.gw) |gx| {
                const dx: f32 = @as(f32, @floatFromInt(gx)) - gwf * 0.62;
                self.glow[gy * self.gw + gx] = amp * @exp(-dx * dx * inv2);
            }
        }

        // A few drops already falling so the very first frame has structure.
        self.spawnDrop();
        self.spawnDrop();
        self.spawnDrop();
        self.computeShade();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn rand01(self: *State) f64 {
        var x = self.rng;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng = x;
        const bits: u32 = @as(u32, @truncate(x >> 40));
        return @as(f64, @floatFromInt(bits)) / 16777216.0;
    }

    fn randF32(self: *State) f32 {
        return @as(f32, @floatCast(self.rand01()));
    }

    fn addBump(self: *State, cx: f32, cy: f32, radius: f32, amp: f32) void {
        const gwi: isize = @intCast(self.gw);
        const ghi: isize = @intCast(self.gh);
        const reach: isize = @intFromFloat(@ceil(radius * 3.0));
        const icx: isize = @intFromFloat(@floor(cx));
        const icy: isize = @intFromFloat(@floor(cy));
        const x_lo: isize = @max(1, icx - reach);
        const x_hi: isize = @min(gwi - 2, icx + reach);
        const y_lo: isize = @max(1, icy - reach);
        const y_hi: isize = @min(ghi - 2, icy + reach);
        const inv: f32 = 1.0 / @max(radius * radius, 0.01);
        var yy: isize = y_lo;
        while (yy <= y_hi) : (yy += 1) {
            const dy: f32 = @as(f32, @floatFromInt(yy)) - cy;
            var xx: isize = x_lo;
            while (xx <= x_hi) : (xx += 1) {
                const dx: f32 = @as(f32, @floatFromInt(xx)) - cx;
                const e: f32 = @exp(-(dx * dx + dy * dy) * inv);
                const idx: usize = @intCast(yy * gwi + xx);
                // Injected into both time levels: the drop starts at rest.
                self.field_a[idx] += amp * e;
                self.field_b[idx] += amp * e;
            }
        }
    }

    fn spawnDrop(self: *State) void {
        const gwf: f32 = @floatFromInt(self.gw);
        const ghf: f32 = @floatFromInt(self.gh);
        const cx: f32 = 2.0 + self.randF32() * @max(gwf - 4.0, 0.0);
        const cy: f32 = 2.0 + self.randF32() * @max(ghf - 4.0, 0.0);
        const radius: f32 = 1.6 + 1.8 * self.randF32();
        const amp: f32 = -(0.6 + 1.0 * self.randF32());
        self.addBump(cx, cy, radius, amp);
    }

    fn waveSubstep(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const cur: []const f32 = if (self.cur_is_a) self.field_a[0..] else self.field_b[0..];
        const nxt: []f32 = if (self.cur_is_a) self.field_b[0..] else self.field_a[0..];
        var y: usize = 1;
        while (y + 1 < gh) : (y += 1) {
            const row = y * gw;
            var x: usize = 1;
            while (x + 1 < gw) : (x += 1) {
                const i = row + x;
                const nsum: f32 = cur[i - 1] + cur[i + 1] + cur[i - gw] + cur[i + gw];
                const v: f32 = C2 * nsum + SELF_W * cur[i] - nxt[i];
                nxt[i] = v * DAMP;
            }
        }
        self.cur_is_a = !self.cur_is_a;
    }

    fn computeShade(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const hgt: []const f32 = if (self.cur_is_a) self.field_a[0..] else self.field_b[0..];

        // Analytic swell: slopes of two travelling plane-wave components,
        // separable into per-column and per-row 1D tables.
        var col_s: [GW_MAX]f32 = undefined;
        var row_s: [GH_MAX]f32 = undefined;
        const t: f32 = @floatCast(self.time_sec);
        for (0..gw) |x| {
            const fx: f32 = @floatFromInt(x);
            col_s[x] = 0.22 * @cos(fx * 0.11 - t * 1.3) + 0.12 * @cos(fx * 0.043 + t * 0.7);
        }
        for (0..gh) |y| {
            const fy: f32 = @floatFromInt(y);
            row_s[y] = 0.30 * @cos(fy * 0.16 - t * 1.7) + 0.10 * @cos(fy * 0.071 + t * 0.9);
        }

        const ghm: f32 = @floatFromInt(gh - 1);
        for (0..gh) |y| {
            const ym: usize = if (y > 0) y - 1 else y;
            const yp: usize = if (y + 1 < gh) y + 1 else y;
            const depth: f32 = @as(f32, @floatFromInt(y)) / ghm;
            const base: f32 = 430.0 - 170.0 * depth;
            for (0..gw) |x| {
                const xm: usize = if (x > 0) x - 1 else x;
                const xp: usize = if (x + 1 < gw) x + 1 else x;
                const i = y * gw + x;
                const sx: f32 = hgt[y * gw + xp] - hgt[y * gw + xm] + col_s[x];
                const sy: f32 = hgt[yp * gw + x] - hgt[ym * gw + x] + row_s[y];
                const lit: f32 = -0.62 * sx - 0.78 * sy;
                const sp: f32 = @max(lit - 0.25, 0.0);
                const gl: f32 = self.glow[i];
                const raw: f32 = base + 110.0 * gl + 240.0 * lit + 18.0 * hgt[i] +
                    500.0 * (0.3 + 1.7 * gl) * sp * sp;
                self.shade[i] = math.clamp(raw, 0.5, 1022.5);
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        var d: f64 = dt;
        if (!(d >= 0.0)) d = 0.0;
        if (d > 0.1) d = 0.1;

        self.time_sec += d;

        // Poisson-ish rain.
        self.drop_timer -= d;
        var guard: u32 = 0;
        while (self.drop_timer <= 0.0 and guard < 4) : (guard += 1) {
            self.spawnDrop();
            self.drop_timer += 0.06 + 0.16 * self.rand01();
        }
        if (self.drop_timer < 0.0) self.drop_timer = 0.05;

        // Fixed-rate leapfrog substeps.
        self.accum += d;
        var n: u32 = 0;
        while (self.accum >= SUB_DT and n < MAX_SUBSTEPS) : (n += 1) {
            self.accum -= SUB_DT;
            self.waveSubstep();
        }
        if (self.accum > SUB_DT) self.accum = 0.0;

        self.computeShade();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const gw = self.gw;
        var row_vals: [GW_MAX]f32 = undefined;
        for (0..h) |y| {
            const gy: usize = self.y_idx[y];
            const fy: f32 = self.y_frac[y];
            const r0 = self.shade[gy * gw .. gy * gw + gw];
            const r1 = self.shade[(gy + 1) * gw .. (gy + 1) * gw + gw];
            for (0..gw) |x| row_vals[x] = r0[x] + (r1[x] - r0[x]) * fy;

            const dst = buf[y * stride .. y * stride + w];
            for (dst, 0..) |*px, x| {
                const ix: usize = self.x_idx[x];
                const a: f32 = row_vals[ix];
                const v: f32 = a + (row_vals[ix + 1] - a) * self.x_frac[x];
                const pal_i: usize = @intFromFloat(math.clamp(v, 0.0, 1023.0));
                px.* = self.palette[pal_i];
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        const n = self.gw * self.gh;
        const cur: []const f32 = if (self.cur_is_a) self.field_a[0..n] else self.field_b[0..n];
        for (cur) |v| {
            if (math.isNan(v) or math.isInf(v)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

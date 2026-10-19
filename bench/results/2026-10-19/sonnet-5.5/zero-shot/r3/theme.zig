const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

// Ripple Tank: a 2D scalar wave equation (u_tt = c^2 * laplacian(u) - damping)
// integrated with a symplectic leapfrog scheme on a 960x600 grid (2 px per cell),
// driven by five wandering oscillating point sources. The height field is lit by
// its own gradient and mapped through a 1024-entry ocean palette.

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_GW: usize = MAX_W / 2;
pub const MAX_GH: usize = MAX_H / 2;
pub const MAX_GRID: usize = MAX_GW * MAX_GH;
const NUM_SOURCES: usize = 5;
const SUBSTEPS: usize = 3;

pub const State = struct {
    w: usize,
    h: usize,
    gw: usize,
    gh: usize,
    scale: f64,
    time_sec: f64,
    tick: f64,

    // All storage lives inside State: a single allocation.
    u: [MAX_GRID]f32,
    v: [MAX_GRID]f32,
    lut: [1024]u32,

    fn paletteColor(t: f32) u32 {
        const pos = [_]f32{ 0.0, 0.30, 0.50, 0.68, 0.85, 1.0 };
        const col = [_][3]f32{
            .{ 1.0, 3.0, 12.0 },
            .{ 4.0, 22.0, 60.0 },
            .{ 10.0, 70.0, 130.0 },
            .{ 30.0, 150.0, 190.0 },
            .{ 170.0, 230.0, 240.0 },
            .{ 255.0, 255.0, 255.0 },
        };
        var seg: usize = 0;
        while (seg < 4 and t > pos[seg + 1]) : (seg += 1) {}
        const f: f32 = math.clamp((t - pos[seg]) / (pos[seg + 1] - pos[seg]), 0.0, 1.0);
        const r = col[seg][0] + (col[seg + 1][0] - col[seg][0]) * f;
        const g = col[seg][1] + (col[seg + 1][1] - col[seg][1]) * f;
        const b = col[seg][2] + (col[seg + 1][2] - col[seg][2]) * f;
        const r8: u8 = @intFromFloat(@min(@max(r, 0.0), 255.0));
        const g8: u8 = @intFromFloat(@min(@max(g, 0.0), 255.0));
        const b8: u8 = @intFromFloat(@min(@max(b, 0.0), 255.0));
        return sdk.packRGBA(r8, g8, b8);
    }

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.gw = @max(@as(usize, 8), @min((self.w + 1) / 2, MAX_GW));
        self.gh = @max(@as(usize, 8), @min((self.h + 1) / 2, MAX_GH));
        self.scale = scale;
        self.time_sec = 0.0;
        self.tick = 0.0;
        @memset(&self.u, 0.0);
        @memset(&self.v, 0.0);
        for (0..1024) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 1023.0;
            self.lut[i] = paletteColor(t);
        }
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn inject(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const gwf: f64 = @floatFromInt(gw);
        const ghf: f64 = @floatFromInt(gh);
        const t = self.time_sec;
        for (0..NUM_SOURCES) |i| {
            const f: f64 = @floatFromInt(i);
            const px = 0.5 + 0.36 * @sin(0.37 * t * (1.0 + 0.23 * f) + 1.7 * f);
            const py = 0.5 + 0.34 * @sin(0.29 * t * (1.0 + 0.31 * f) + 2.3 * f + 0.8);
            const cxf = math.clamp(px * gwf, 3.0, gwf - 4.0);
            const cyf = math.clamp(py * ghf, 3.0, ghf - 4.0);
            const cx: usize = @intFromFloat(cxf);
            const cy: usize = @intFromFloat(cyf);
            const omega = 78.0 + 9.0 * f;
            const amp: f32 = @floatCast(0.30 * @sin(omega * self.tick));
            const base = cy * gw + cx;
            self.v[base] += amp;
            self.v[base - 1] += amp * 0.5;
            self.v[base + 1] += amp * 0.5;
            self.v[base - gw] += amp * 0.5;
            self.v[base + gw] += amp * 0.5;
        }
    }

    fn wave(self: *State) void {
        const gw = self.gw;
        const gh = self.gh;
        const k: f32 = 0.24;
        const damp: f32 = 0.9985;
        var y: usize = 1;
        while (y + 1 < gh) : (y += 1) {
            const base = y * gw;
            const up = self.u[base - gw .. base];
            const mid = self.u[base .. base + gw];
            const dn = self.u[base + gw .. base + 2 * gw];
            const vr = self.v[base .. base + gw];
            var x: usize = 1;
            while (x + 1 < gw) : (x += 1) {
                const lap = mid[x - 1] + mid[x + 1] + up[x] + dn[x] - 4.0 * mid[x];
                vr[x] = (vr[x] + k * lap) * damp;
            }
        }
        const n = gw * gh;
        for (self.u[0..n], self.v[0..n]) |*uu, vv| uu.* += vv;
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        for (0..SUBSTEPS) |_| {
            self.tick += dt / @as(f64, @floatFromInt(SUBSTEPS));
            self.inject();
            self.wave();
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const gw = self.gw;
        const gh = self.gh;
        var tmp: [MAX_GW]u32 = undefined;
        for (0..gh) |gy| {
            const ym = if (gy > 0) gy - 1 else gy;
            const yp = if (gy + 1 < gh) gy + 1 else gy;
            const rm = self.u[ym * gw .. ym * gw + gw];
            const r0 = self.u[gy * gw .. gy * gw + gw];
            const rp = self.u[yp * gw .. yp * gw + gw];
            for (0..gw) |gx| {
                const xl = if (gx > 0) gx - 1 else gx;
                const xr = if (gx + 1 < gw) gx + 1 else gx;
                const c = r0[gx];
                const dx = r0[xr] - r0[xl];
                const dy = rp[gx] - rm[gx];
                const a = 1.2 * c + 1.1 * (dx + dy);
                const s = a / (1.0 + @abs(a));
                const q = (0.5 + 0.5 * s) * 1023.0;
                const idx: usize = @intFromFloat(@min(@max(q, 0.0), 1023.0));
                tmp[gx] = self.lut[idx];
            }
            const y0 = 2 * gy;
            if (y0 >= h) break;
            const row0 = buf[y0 * stride .. y0 * stride + w];
            for (0..gw) |gx| {
                const p = 2 * gx;
                if (p >= w) break;
                const c0 = tmp[gx];
                row0[p] = c0;
                if (p + 1 < w) {
                    const nx = if (gx + 1 < gw) gx + 1 else gx;
                    row0[p + 1] = sdk.lerpRGB(c0, tmp[nx], 128);
                }
            }
            const y1 = y0 + 1;
            if (y1 < h) {
                const row1 = buf[y1 * stride .. y1 * stride + w];
                @memcpy(row1, row0);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        if (math.isNan(self.tick) or math.isInf(self.tick)) return true;
        const n = self.gw * self.gh;
        var i: usize = 0;
        while (i < n) : (i += 97) {
            if (math.isNan(self.u[i]) or math.isInf(self.u[i])) return true;
            if (math.isNan(self.v[i]) or math.isInf(self.v[i])) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

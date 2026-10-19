//! Opus55_RainPool.zig  --  ARGUS-BENCH Track B (Symplectic / PDE Field Dynamics)
//!
//! Rain falling on a sunlit swimming pool.
//!
//! Physics: the free surface height u(x, y, t) obeys the damped 2D wave equation
//!     u_tt = c^2 * lap(u) - gamma * u_t
//! integrated with the explicit leapfrog (Verlet) scheme on a 321x201 node grid
//! at a fixed 250 Hz substep (CFL number c^2 dt^2 / dx^2 = 0.08 < 0.5, unconditionally
//! stable). Raindrops are Gaussian depressions injected at rest at random places and
//! times (deterministic xorshift RNG), which split into outgoing ring pulses that
//! reflect from the pool walls (Dirichlet boundary).
//!
//! Optics: every frame the surface gradient gives
//!   * refraction  -- the tiled pool floor is sampled at an offset proportional to
//!                    the slope (Snell's law, small-angle), so grout lines wobble,
//!   * Lambert/specular shading from a low sun in the upper-left,
//!   * caustics    -- focusing under convex crests (negative Laplacian) adds light.
//!
//! Rendering: per-node fixed-point fields are built in step(); draw() interpolates them
//! bilinearly (vertical pass per row over 321 nodes, horizontal pass per cell span), so the
//! per-pixel inner loop is integer FMA plus two table lookups. No transcendental per pixel.
//!
//! Gates: one alloc (State, ~10.5 MiB), zero allocs per frame, y*stride+x indexing,
//! opaque alpha everywhere via sdk.packRGBA / sdk.addRGB, NaN-guarded state.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

// Simulation grid (cells) -- 6x6 px per cell at 1920x1200.
const GW: usize = 320;
const GH: usize = 200;
const NX: usize = GW + 1;
const NY: usize = GH + 1;
const NN: usize = NX * NY;

const SPEC_N: usize = 1024;

const SUB_DT: f64 = 0.004; // 250 Hz physics substep
const C2: f32 = 0.08; // (c dt / dx)^2, must stay < 0.5
const DAMP: f32 = 0.9986; // per-substep viscous damping

const SHADE_K: f32 = 420.0; // slope -> shade
const CAUSTIC_K: f32 = 650.0; // curvature -> caustic light
const REFR_PX: f32 = 40.0; // slope -> refraction offset (px at 1920 wide)

fn hash2(a: u32, b: u32) u32 {
    var hv: u32 = (a *% 0x8DA6B343) ^ (b *% 0xD8163841);
    hv ^= hv >> 13;
    hv *%= 0x85EBCA6B;
    hv ^= hv >> 16;
    return hv;
}

fn smoothstep(e0: f32, e1: f32, v: f32) f32 {
    const t: f32 = @max(0.0, @min(1.0, (v - e0) / (e1 - e0)));
    return t * t * (3.0 - 2.0 * t);
}

fn mix(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn clampF(v: f32, lo: f32, hi: f32) f32 {
    return @max(lo, @min(hi, v));
}

fn toU8(v: f32) u8 {
    const c: f32 = @max(0.0, @min(255.0, v + 0.5));
    return @intFromFloat(c);
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    acc: f64,
    drop_timer: f64,
    rng: u64,
    cur: usize,
    refr_k: f32,

    // Leapfrog height buffers: bufs[cur] = u(t), bufs[1-cur] = u(t - dt).
    bufs: [2][NN]f32,

    // Per-node fixed-point render fields.
    node_dx: [NN]i32, // refraction x offset, 1/16 px
    node_dy: [NN]i32, // refraction y offset, 1/16 px
    node_s: [NN]i32, // shade index 0..1023

    // Pixel -> grid mapping.
    col_fx: [MAX_W]u8,
    row_iy: [MAX_H]u16,
    row_fy: [MAX_H]u8,
    cell_x0: [GW + 1]u32,

    spec_lut: [SPEC_N]u32,
    bg_lut: [MAX_PIXELS]u32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.acc = 0.0;
        self.drop_timer = 0.0;
        self.rng = 0x9E3779B97F4A7C15;
        self.cur = 0;

        @memset(self.bufs[0][0..], 0.0);
        @memset(self.bufs[1][0..], 0.0);
        @memset(self.node_dx[0..], 0);
        @memset(self.node_dy[0..], 0);
        @memset(self.node_s[0..], 512);
        @memset(self.col_fx[0..], 0);
        @memset(self.row_iy[0..], 0);
        @memset(self.row_fy[0..], 0);

        const wd: usize = @max(@as(usize, 1), self.w);
        const hd: usize = @max(@as(usize, 1), self.h);
        const sfw: f32 = @as(f32, @floatFromInt(wd)) / 1920.0;
        self.refr_k = REFR_PX * sfw * 16.0;

        for (0..self.w) |x| {
            const pos: usize = (x * GW * 256) / wd;
            self.col_fx[x] = @intCast(pos & 255);
        }
        for (0..self.h) |y| {
            const pos: usize = (y * GH * 256) / hd;
            self.row_iy[y] = @intCast(pos >> 8);
            self.row_fy[y] = @intCast(pos & 255);
        }
        for (0..GW + 1) |g| {
            self.cell_x0[g] = @intCast((g * self.w + GW - 1) / GW);
        }

        self.buildSpec();
        self.buildFloor();

        // Pre-warm: let a second and a bit of rain fall so frame 1 is already alive.
        var k: usize = 0;
        while (k < 150) : (k += 1) self.step(0.008);

        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn nextRand(self: *State) u64 {
        var s = self.rng;
        s ^= s >> 12;
        s ^= s << 25;
        s ^= s >> 27;
        self.rng = s;
        return s *% 0x2545F4914F6CDD1D;
    }

    fn randF(self: *State) f32 {
        const r = self.nextRand();
        return @as(f32, @floatFromInt(r >> 40)) / 16777216.0;
    }

    fn buildSpec(self: *State) void {
        // Additive water light: dim teal tint at rest, white-cyan at glints/caustics.
        for (0..SPEC_N) |i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / 1023.0;
            const t2 = t * t;
            const t4 = t2 * t2;
            const t8 = t4 * t4;
            const r = 30.0 * t + 120.0 * t4 + 150.0 * t8;
            const g = 62.0 * t + 150.0 * t4 + 110.0 * t8;
            const b = 78.0 * t + 150.0 * t4 + 90.0 * t8;
            self.spec_lut[i] = sdk.packRGBA(toU8(r), toU8(g), toU8(b));
        }
    }

    fn buildFloor(self: *State) void {
        const w = self.w;
        const h = self.h;
        if (w == 0 or h == 0) return;
        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);
        const sfw: f32 = fw / 1920.0;
        const tile: f32 = @max(6.0, 120.0 * sfw);
        const grout: f32 = @max(0.6, 3.0 * sfw);
        const cyl: f32 = fh * 0.5;
        const lane_half: f32 = @max(1.5, tile * 0.22);

        for (0..h) |y| {
            const py: f32 = @as(f32, @floatFromInt(y)) + 0.5;
            const ty = py / tile;
            const tyf = @floor(ty);
            const fry = ty - tyf;
            const dyg = @min(fry, 1.0 - fry) * tile;
            const tyu: u32 = @intFromFloat(tyf);
            const ny = py / fh * 2.0 - 1.0;
            const ady = @abs(py - cyl);
            const lane_y = 1.0 - smoothstep(lane_half - 1.0, lane_half + 1.0, ady);
            const tbar_y = 1.0 - smoothstep(tile * 0.9, tile * 0.9 + 1.5, ady);

            for (0..w) |x| {
                const px: f32 = @as(f32, @floatFromInt(x)) + 0.5;
                const tx = px / tile;
                const txf = @floor(tx);
                const frx = tx - txf;
                const dxg = @min(frx, 1.0 - frx) * tile;
                const txu: u32 = @intFromFloat(txf);

                const d = @min(dxg, dyg);
                const inside = smoothstep(grout, grout + 1.2, d);
                const th = hash2(txu, tyu);
                const tvar = (@as(f32, @floatFromInt(th & 255)) / 255.0 - 0.5) * 0.14;
                const bevel = (1.0 - smoothstep(grout, grout + tile * 0.12, d)) * 0.08;

                var r: f32 = 0.05 * (1.0 + tvar) + bevel * 0.5;
                var g: f32 = 0.30 * (1.0 + tvar) + bevel;
                var b: f32 = 0.44 * (1.0 + tvar) + bevel;

                // Grout between tiles.
                r = mix(0.36, r, inside);
                g = mix(0.50, g, inside);
                b = mix(0.56, b, inside);

                // Navy lane line with T-bars near both walls.
                const lane_x = smoothstep(tile, tile + 1.5, px) * (1.0 - smoothstep(fw - tile - 1.5, fw - tile, px));
                const tl = @abs(px - tile * 1.25);
                const tr = @abs(px - (fw - tile * 1.25));
                const tbar_x = 1.0 - smoothstep(lane_half - 1.0, lane_half + 1.0, @min(tl, tr));
                const lane = @max(lane_y * lane_x, tbar_y * tbar_x) * 0.9;
                r = mix(r, 0.02, lane);
                g = mix(g, 0.07, lane);
                b = mix(b, 0.20, lane);

                // Fine grain.
                const gh = hash2(@as(u32, @intCast(x)) +% 7919, @as(u32, @intCast(y)) +% 104729);
                const grain = (@as(f32, @floatFromInt(gh & 1023)) / 1023.0 - 0.5) * 0.035;

                // Depth falloff, vignette, sun from the upper left.
                const nx = px / fw * 2.0 - 1.0;
                const vig = 1.0 - 0.28 * (nx * nx) - 0.36 * (ny * ny);
                const sun = 1.08 - 0.18 * (px / fw) - 0.22 * (py / fh);
                const kk = vig * sun * 255.0;

                self.bg_lut[y * w + x] = sdk.packRGBA(
                    toU8((r + grain) * kk),
                    toU8((g + grain) * kk),
                    toU8((b + grain) * kk),
                );
            }
        }
    }

    fn addDrop(self: *State, cx: f32, cy: f32, amp: f32, sigma: f32) void {
        const rad: i32 = @intFromFloat(@ceil(sigma * 3.0));
        const icx: i32 = @intFromFloat(@floor(cx));
        const icy: i32 = @intFromFloat(@floor(cy));
        const inv: f32 = 1.0 / (2.0 * sigma * sigma);
        var dy: i32 = -rad;
        while (dy <= rad) : (dy += 1) {
            const gy = icy + dy;
            if (gy < 1 or gy > @as(i32, NY - 2)) continue;
            var dx: i32 = -rad;
            while (dx <= rad) : (dx += 1) {
                const gx = icx + dx;
                if (gx < 1 or gx > @as(i32, NX - 2)) continue;
                const fx: f32 = @as(f32, @floatFromInt(gx)) - cx;
                const fy: f32 = @as(f32, @floatFromInt(gy)) - cy;
                const v: f32 = amp * @exp(-(fx * fx + fy * fy) * inv);
                const idx: usize = @as(usize, @intCast(gy)) * NX + @as(usize, @intCast(gx));
                // Added to both time levels: the drop starts at rest and splits into a ring.
                self.bufs[0][idx] += v;
                self.bufs[1][idx] += v;
            }
        }
    }

    fn spawnDrop(self: *State) void {
        const cx: f32 = 5.0 + self.randF() * @as(f32, @floatFromInt(NX - 11));
        const cy: f32 = 5.0 + self.randF() * @as(f32, @floatFromInt(NY - 11));
        const big = self.randF() < 0.12;
        const amp: f32 = (0.6 + 0.9 * self.randF()) * (if (big) @as(f32, 1.8) else @as(f32, 1.0));
        const sigma: f32 = if (big) 3.2 else 1.7 + 0.6 * self.randF();
        self.addDrop(cx, cy, -amp, sigma);
    }

    fn waveSubstep(self: *State) void {
        const src = &self.bufs[self.cur];
        const dst = &self.bufs[1 - self.cur];
        var y: usize = 1;
        while (y < NY - 1) : (y += 1) {
            const row = y * NX;
            var x: usize = 1;
            while (x < NX - 1) : (x += 1) {
                const i = row + x;
                const c = src[i];
                const lap = src[i - 1] + src[i + 1] + src[i - NX] + src[i + NX] - 4.0 * c;
                dst[i] = (2.0 * c - dst[i] + C2 * lap) * DAMP;
            }
        }
        self.cur = 1 - self.cur;
    }

    fn updateFields(self: *State) void {
        const u = &self.bufs[self.cur];
        const kr = self.refr_k;
        for (0..NY) |y| {
            const ym = if (y > 0) y - 1 else y;
            const yp = if (y + 1 < NY) y + 1 else y;
            for (0..NX) |x| {
                const xm = if (x > 0) x - 1 else x;
                const xp = if (x + 1 < NX) x + 1 else x;
                const i = y * NX + x;
                const c = u[i];
                const left = u[y * NX + xm];
                const right = u[y * NX + xp];
                const up = u[ym * NX + x];
                const down = u[yp * NX + x];
                const gx = right - left;
                const gy = down - up;
                const lap = left + right + up + down - 4.0 * c;
                const odx = clampF(gx * kr, -1024.0, 1024.0);
                const ody = clampF(gy * kr, -1024.0, 1024.0);
                const shade = clampF(512.0 + SHADE_K * (0.6 * gx + 0.8 * gy) - CAUSTIC_K * lap, 0.0, 1023.0);
                self.node_dx[i] = @intFromFloat(odx);
                self.node_dy[i] = @intFromFloat(ody);
                self.node_s[i] = @intFromFloat(shade);
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        var d: f64 = dt;
        if (!(d > 0.0)) d = 0.0; // also rejects NaN
        if (d > 0.1) d = 0.1;
        self.time_sec += d;
        self.acc += d;
        self.drop_timer -= d;

        var guard: u32 = 0;
        while (self.drop_timer <= 0.0 and guard < 8) : (guard += 1) {
            self.spawnDrop();
            self.drop_timer += 0.07 + 0.28 * @as(f64, self.randF());
        }
        if (self.drop_timer < 0.0) self.drop_timer = 0.05;

        var n: u32 = 0;
        while (self.acc >= SUB_DT - 1e-9 and n < 30) : (n += 1) {
            self.acc -= SUB_DT;
            self.waveSubstep();
        }
        if (self.acc > SUB_DT) self.acc = 0.0;

        self.updateFields();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        if (w == 0 or h == 0) return;

        var rdx: [NX]i32 = undefined;
        var rdy: [NX]i32 = undefined;
        var rs: [NX]i32 = undefined;
        const wm1: i32 = @intCast(w - 1);
        const hm1: i32 = @intCast(h - 1);

        for (0..h) |y| {
            // Vertical interpolation of the node fields for this pixel row.
            const iy: usize = self.row_iy[y];
            const fy: i32 = self.row_fy[y];
            const r0 = iy * NX;
            const r1 = r0 + NX;
            for (0..NX) |g| {
                const a = self.node_dx[r0 + g];
                rdx[g] = a + (((self.node_dx[r1 + g] - a) * fy) >> 8);
                const c = self.node_dy[r0 + g];
                rdy[g] = c + (((self.node_dy[r1 + g] - c) * fy) >> 8);
                const e = self.node_s[r0 + g];
                rs[g] = e + (((self.node_s[r1 + g] - e) * fy) >> 8);
            }

            const yi: i32 = @intCast(y);
            const dst = buf[y * stride .. y * stride + w];

            // Horizontal interpolation, one grid cell span at a time.
            for (0..GW) |g| {
                const x0: usize = self.cell_x0[g];
                const x1: usize = self.cell_x0[g + 1];
                const ax = rdx[g];
                const bx = rdx[g + 1] - ax;
                const ay = rdy[g];
                const by = rdy[g + 1] - ay;
                const s0 = rs[g];
                const bs = rs[g + 1] - s0;
                var x: usize = x0;
                while (x < x1) : (x += 1) {
                    const fx: i32 = self.col_fx[x];
                    const ox = ax + ((bx * fx) >> 8);
                    const oy = ay + ((by * fx) >> 8);
                    const sv = s0 + ((bs * fx) >> 8);
                    const xi: i32 = @intCast(x);
                    const sx: i32 = @max(@as(i32, 0), @min(wm1, xi + (ox >> 4)));
                    const sy: i32 = @max(@as(i32, 0), @min(hm1, yi + (oy >> 4)));
                    const si: i32 = @max(@as(i32, 0), @min(@as(i32, 1023), sv));
                    const bgc = self.bg_lut[@as(usize, @intCast(sy)) * w + @as(usize, @intCast(sx))];
                    dst[x] = sdk.addRGB(bgc, self.spec_lut[@as(usize, @intCast(si))]);
                }
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        const u = &self.bufs[self.cur];
        for (u) |v| {
            if (math.isNan(v) or math.isInf(v)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

// @argus-theme: custom_shader
// ============================================================================
// GEMINI AQUARIUM // themes/Gemini_Aquarium.zig
//
// A slow drift over a sandy seabed. Light comes down from the surface in
// moving shafts, kelp sways, bubbles rise, and four kinds of fish school
// across the view: neon tetras, clownfish, yellow tangs and a few big silver
// fish. Marine snow hangs in the water and the far reef fades into blue.
//
// Lineage: Google Gemini wrote Gemini_Cyber_Topography (ARGUS-BENCH Track C),
// a wireframe canyon flown over by a 3D boids swarm. Claude Opus turned it
// into this aquarium: the canyon became the reef and seabed (same perspective
// wireframe and terrain harmonics, now lit by moving caustics), the drones
// became schooling fish drawn as shaded, tail-wagging bodies, and the sky
// became a water column with god rays, kelp, bubbles and marine snow.
//
// Contract: one alloc.create(State) at init, nothing after; no clocks or I/O;
// every write goes through `y * stride + x` inside row[0..w].
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;

const SIN_N: usize = 4096;
const SIN_MASK: usize = SIN_N - 1;

const GRID_Z: usize = 46;
const GRID_X: usize = 112;
const Z_SPACING: f32 = 1.8;

const NUM_FISH: usize = 168; // multiple of 8: species is i % 8, so schools are strided
const NUM_KELP: usize = 56;
const KELP_SEG: usize = 12;
const NUM_SNOW: usize = 420;
const NUM_BUBBLES: usize = 64;
const PROF_N: usize = 64;

const HORIZON: f32 = 0.42; // horizon line as a fraction of height
const FOCAL: f32 = 0.80; // focal length as a fraction of height
const CAM_SPEED: f32 = 0.6; // world units per second along +z
const CAM_Y: f32 = 5.6;
const KELP_SPAN: f32 = 64.0; // kelp lives in camera-relative z in [2, 2 + KELP_SPAN)
const SURFACE_Y: f32 = 15.0;
const SCROLL_PERIOD: f32 = 2.0 * math.pi / 0.001;

const RAY_SLANT_Q6: usize = 26; // god-ray slant: 26/64 px of x per px of y
const RAY_N: usize = MAX_W + (MAX_H * RAY_SLANT_Q6 >> 6) + 2;

const TWO_PI: f32 = 2.0 * math.pi;

// Species i % 8 -> kind. 0 neon tetra, 1 yellow tang, 2 clownfish, 3 silver.
const KIND_OF_SLOT = [8]u8{ 0, 0, 2, 1, 0, 2, 0, 3 };
const KIND_SIZE = [4]f32{ 0.34, 0.70, 0.50, 1.10 };
const KIND_DEPTH = [4]f32{ 0.15, 0.30, 0.21, 0.15 }; // half body depth / length
const KIND_SPEED = [4]f32{ 1.25, 0.85, 0.95, 0.70 };
const KIND_BACK = [4][3]f32{ .{ 38, 78, 150 }, .{ 245, 196, 30 }, .{ 236, 98, 16 }, .{ 70, 96, 122 } };
const KIND_BELLY = [4][3]f32{ .{ 196, 210, 226 }, .{ 255, 232, 96 }, .{ 255, 150, 52 }, .{ 214, 224, 230 } };

pub const Fish = struct {
    x: f32, // camera-relative x
    y: f32, // world y
    z: f32, // camera-relative depth
    vx: f32,
    vy: f32,
    vz: f32,
    size: f32,
    wag: f32,
    kind: u8,
};

pub const Kelp = struct {
    x: f32, // world x
    z: f32, // camera-relative depth
    height: f32,
    phase: f32,
};

pub const Mote = struct {
    x: f32,
    y: f32,
    z: f32,
    phase: f32,
};

pub const Bubble = struct {
    x: f32,
    y: f32,
    z: f32,
    r: f32,
    vy: f32,
    phase: f32,
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    scroll_z: f32,

    // Camera, shared by step() and draw().
    cam_x: f32,
    cam_y: f32,
    cos_roll: f32,
    sin_roll: f32,

    sin_lut: [SIN_N]f32,
    prof: [PROF_N]f32, // fish half-width profile along the body, nose to tail root

    row_bg: [MAX_H]u32, // water colour per row
    row_ray: [MAX_H]u32, // god-ray gain per row, 0..256
    rays: [RAY_N]u8, // god-ray intensity along the slanted axis, rebuilt every step

    mesh_sx: [GRID_Z][GRID_X]i16,
    mesh_sy: [GRID_Z][GRID_X]i16,
    mesh_col: [GRID_Z][GRID_X]u32,

    fish: [NUM_FISH]Fish,
    order: [NUM_FISH]u16, // far-to-near draw order, kept sorted in step()

    kelp: [NUM_KELP]Kelp,
    kelp_sx: [NUM_KELP][KELP_SEG + 1]i16,
    kelp_sy: [NUM_KELP][KELP_SEG + 1]i16,
    kelp_col: [NUM_KELP]u32,
    kelp_thick: [NUM_KELP]u8,

    snow: [NUM_SNOW]Mote,
    bubbles: [NUM_BUBBLES]Bubble,
    rng: u64,

    // ------------------------------------------------------------- helpers --

    inline fn xorshift64(state: *u64) u64 {
        var x = state.*;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        state.* = x;
        return x;
    }

    inline fn rand01(state: *u64) f32 {
        return @as(f32, @floatFromInt(xorshift64(state) & 0xFFFFFF)) / @as(f32, 0x1000000);
    }

    inline fn fastSin(self: *const State, rad: f32) f32 {
        const norm = rad * (1.0 / TWO_PI);
        const f = (norm - @floor(norm)) * @as(f32, @floatFromInt(SIN_N));
        const idx: usize = @as(usize, @intFromFloat(@max(0.0, f))) & SIN_MASK;
        return self.sin_lut[idx];
    }

    inline fn fastCos(self: *const State, rad: f32) f32 {
        return self.fastSin(rad + 0.5 * math.pi);
    }

    /// (t * freq) mod 2*pi in f64, so phases stay exact after days of uptime.
    inline fn phase(self: *const State, freq: f64) f32 {
        return @floatCast(@mod(self.time_sec * freq, 2.0 * math.pi));
    }

    inline fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
        const t = math.clamp((x - e0) / (e1 - e0), 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    inline fn toU8(v: f32) u8 {
        return @intFromFloat(math.clamp(v, 0.0, 255.0));
    }

    inline fn toI16(v: f32) i16 {
        return @intFromFloat(math.clamp(v, -4096.0, 8192.0));
    }

    /// Seabed height at world (wx, wz): a winding sandy channel between reef ridges.
    /// The ridge harmonics are Gemini's canyon terrain, scaled down to reef height.
    inline fn terrain(self: *const State, wx: f32, wz: f32) f32 {
        const center = 6.5 * self.fastSin(wz * 0.045) + 3.0 * self.fastCos(wz * 0.019);
        const dx = wx - center;
        const env = 1.0 - 1.0 / (1.0 + 0.012 * dx * dx);
        const h1 = self.fastSin(wx * 0.14 + wz * 0.09) * self.fastCos(wx * 0.08 - wz * 0.12);
        const h2 = 0.52 * self.fastSin(wx * 0.31 - wz * 0.23 + 1.4 * h1);
        const h3 = 0.25 * self.fastCos(wx * 0.62 + wz * 0.48);
        const reef = @max(0.0, 0.9 + h1 + h2 + h3) * 3.1;
        const dune = 0.45 * self.fastSin(wx * 0.21 + wz * 0.13) * self.fastCos(wx * 0.07 - wz * 0.17);
        const ripple = 0.07 * self.fastSin(wx * 1.4 + wz * 0.9);
        return env * reef + dune + ripple;
    }

    /// Camera-relative point -> screen. Returns false when behind the near plane.
    inline fn project(self: *const State, rx: f32, ry: f32, rz: f32, sx: *f32, sy: *f32) bool {
        if (rz < 0.6) return false;
        const hf: f32 = @floatFromInt(self.h);
        const wf: f32 = @floatFromInt(self.w);
        const k = FOCAL * hf / rz;
        const xr = rx * self.cos_roll - ry * self.sin_roll;
        const yr = rx * self.sin_roll + ry * self.cos_roll;
        sx.* = 0.5 * wf + xr * k;
        sy.* = HORIZON * hf - yr * k;
        return true;
    }

    // ---------------------------------------------------------------- init --

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.scroll_z = 0.0;
        self.cam_x = 0.0;
        self.cam_y = CAM_Y;
        self.cos_roll = 1.0;
        self.sin_roll = 0.0;
        self.rng = 0x5EA_F100_2A17_9E37;

        for (0..SIN_N) |i| {
            const a = (@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(SIN_N))) * (2.0 * math.pi);
            self.sin_lut[i] = @floatCast(@sin(a));
        }

        // Fish outline: blunt nose, deepest at a third of the length, narrow tail root.
        for (0..PROF_N) |i| {
            const u: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(PROF_N - 1));
            const p = math.clamp(u / 0.78, 0.0, 1.0);
            self.prof[i] = if (u <= 0.78) 0.18 + 0.82 * @sin(math.pi * math.pow(f32, p, 0.62)) else 0.18;
        }

        // Water column: bright teal under the surface, blue haze at the horizon, deep below.
        const hf: f32 = @floatFromInt(@max(self.h, 1));
        const top = [3]f32{ 30, 104, 128 };
        const hor = [3]f32{ 10, 54, 84 };
        const bot = [3]f32{ 3, 18, 36 };
        for (0..self.h) |y| {
            const ny = @as(f32, @floatFromInt(y)) / hf;
            var c: [3]f32 = undefined;
            if (ny < HORIZON) {
                const t = math.pow(f32, ny / HORIZON, 0.8);
                for (0..3) |k| c[k] = top[k] + (hor[k] - top[k]) * t;
            } else {
                const t = math.pow(f32, (ny - HORIZON) / (1.0 - HORIZON), 0.55);
                for (0..3) |k| c[k] = hor[k] + (bot[k] - hor[k]) * t;
            }
            self.row_bg[y] = sdk.packRGBA(toU8(c[0]), toU8(c[1]), toU8(c[2]));
            const g = 150.0 * @exp(-2.4 * ny) * (1.0 - smoothstep(0.55, 0.95, ny));
            self.row_ray[y] = @intFromFloat(math.clamp(g, 0.0, 256.0));
        }

        var rng = self.rng;
        for (0..NUM_FISH) |i| {
            const kind = KIND_OF_SLOT[i % 8];
            const sz = KIND_SIZE[kind] * (0.85 + 0.3 * rand01(&rng));
            self.fish[i] = .{
                .x = (rand01(&rng) - 0.5) * 24.0,
                .y = 3.0 + rand01(&rng) * 5.0,
                .z = 8.0 + rand01(&rng) * 22.0,
                .vx = (rand01(&rng) - 0.5) * 2.0,
                .vy = 0.0,
                .vz = (rand01(&rng) - 0.5) * 0.5,
                .size = sz,
                .wag = rand01(&rng) * TWO_PI,
                .kind = kind,
            };
            self.order[i] = @intCast(i);
        }
        for (0..NUM_KELP) |i| {
            self.kelp[i] = .{
                .x = (rand01(&rng) - 0.5) * 60.0,
                .z = 2.0 + KELP_SPAN * (@as(f32, @floatFromInt(i)) + rand01(&rng)) / @as(f32, @floatFromInt(NUM_KELP)),
                .height = 3.5 + 5.5 * rand01(&rng),
                .phase = rand01(&rng) * TWO_PI,
            };
        }
        for (0..NUM_SNOW) |i| {
            self.snow[i] = .{
                .x = (rand01(&rng) - 0.5) * 50.0,
                .y = rand01(&rng) * SURFACE_Y,
                .z = 1.5 + rand01(&rng) * 40.0,
                .phase = rand01(&rng) * TWO_PI,
            };
        }
        for (0..NUM_BUBBLES) |i| {
            self.bubbles[i] = .{
                .x = (rand01(&rng) - 0.5) * 30.0,
                .y = rand01(&rng) * SURFACE_Y,
                .z = 4.0 + rand01(&rng) * 30.0,
                .r = 0.04 + 0.10 * rand01(&rng),
                .vy = 1.2 + 1.2 * rand01(&rng),
                .phase = rand01(&rng) * TWO_PI,
            };
        }
        self.rng = rng;

        self.step(0.0);
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    // ---------------------------------------------------------------- step --

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const dt_f: f32 = @floatCast(math.clamp(dt, 0.0, 0.05));
        // Every seabed frequency along z is a multiple of 0.001, so wrapping scroll_z at
        // 2*pi/0.001 is seamless and keeps f32 precise forever.
        self.scroll_z = @mod(self.scroll_z + CAM_SPEED * dt_f, SCROLL_PERIOD);

        const sz = self.scroll_z;
        self.cam_x = 4.2 * self.fastSin(sz * 0.045) + 1.8 * self.fastCos(sz * 0.019);
        self.cam_y = CAM_Y + 0.35 * self.fastSin(self.phase(0.21));
        const roll = -0.02 * self.fastCos(sz * 0.045);
        self.cos_roll = @cos(roll);
        self.sin_roll = @sin(roll);

        self.stepRays();
        self.stepSeabed();
        self.stepKelp(dt_f);
        self.stepFish(dt_f);
        self.stepParticles(dt_f);
    }

    fn stepRays(self: *State) void {
        const p1 = self.phase(0.13);
        const p2 = self.phase(0.21);
        const p3 = self.phase(0.47);
        for (0..RAY_N) |i| {
            const u: f32 = @floatFromInt(i);
            const b1 = 0.5 + 0.5 * self.fastSin(u * 0.0062 + p1);
            const b2 = 0.5 + 0.5 * self.fastSin(u * 0.0147 - p2 + 1.7);
            const b3 = 0.5 + 0.5 * self.fastSin(u * 0.0310 + p3 + 0.4);
            var v = b1 * b2 * (0.55 + 0.45 * b3);
            v = v * v * 1.7;
            self.rays[i] = toU8(v * 255.0);
        }
    }

    fn stepSeabed(self: *State) void {
        const z_frac = @mod(self.scroll_z, Z_SPACING);
        const base_z = self.scroll_z - z_frac;
        const pa = self.phase(0.70);
        const pb = self.phase(0.50);

        for (0..GRID_Z) |iz| {
            const rev: f32 = @floatFromInt(GRID_Z - 1 - iz);
            const rel_z = (rev + 1.0) * Z_SPACING - z_frac;
            const wz = base_z + (rev + 1.0) * Z_SPACING;
            const fade = math.clamp(@exp(-0.040 * rel_z) * smoothstep(0.6, 3.5, rel_z), 0.0, 1.0);

            for (0..GRID_X) |ix| {
                const nx = (@as(f32, @floatFromInt(ix)) / @as(f32, @floatFromInt(GRID_X - 1))) - 0.5;
                const wx = self.cam_x + nx * 80.0;
                const wy = self.terrain(wx, wz);

                var sx: f32 = 0;
                var sy: f32 = 0;
                _ = self.project(wx - self.cam_x, wy - self.cam_y, rel_z, &sx, &sy);
                self.mesh_sx[iz][ix] = toI16(sx);
                self.mesh_sy[iz][ix] = toI16(sy);

                // Sand in the channel, blue-green rock on the slopes, coral on the crests.
                const alt = math.clamp(wy / 6.5, 0.0, 1.0);
                var r: f32 = 0;
                var g: f32 = 0;
                var b: f32 = 0;
                if (alt < 0.18) {
                    r = 226;
                    g = 190;
                    b = 128;
                } else if (alt < 0.6) {
                    const t = (alt - 0.18) / 0.42;
                    r = 226 - 156 * t;
                    g = 190 - 32 * t;
                    b = 128 + 44 * t;
                } else {
                    const t = (alt - 0.6) / 0.4;
                    r = 70 + 170 * t;
                    g = 158 - 52 * t;
                    b = 172 - 22 * t;
                }
                // Moving caustic net from the surface.
                const c = self.fastSin(wx * 0.9 + pa) * self.fastSin(wz * 0.8 - pb + wx * 0.3);
                const caus = @max(0.0, c);
                const lit = fade * (0.55 + 0.9 * caus * caus);
                self.mesh_col[iz][ix] = sdk.packRGBA(toU8(r * lit), toU8(g * lit), toU8(b * lit));
            }
        }
    }

    fn stepKelp(self: *State, dt_f: f32) void {
        const pt = self.phase(0.8);
        for (0..NUM_KELP) |i| {
            const k = &self.kelp[i];
            k.z -= CAM_SPEED * dt_f;
            if (k.z < 2.0) {
                k.z += KELP_SPAN;
                k.x = self.cam_x + (rand01(&self.rng) - 0.5) * 60.0;
                k.height = 3.5 + 5.5 * rand01(&self.rng);
            }
            const wz = self.scroll_z + k.z;
            const base = self.terrain(k.x, wz) - 0.2;
            const fade = math.clamp(@exp(-0.045 * k.z), 0.0, 1.0);
            // Kelp green fading into the horizon water colour with distance.
            self.kelp_col[i] = sdk.packRGBA(toU8(10 + (52 - 10) * fade), toU8(54 + (150 - 54) * fade), toU8(84 + (70 - 84) * fade));
            self.kelp_thick[i] = @intFromFloat(math.clamp(FOCAL * @as(f32, @floatFromInt(self.h)) * 0.22 / k.z, 1.0, 16.0));
            for (0..KELP_SEG + 1) |s| {
                const f: f32 = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(KELP_SEG));
                const sway = f * f * 0.9 * self.fastSin(pt + k.phase - f * 2.2);
                const y = base + f * k.height;
                var sx: f32 = -10000;
                var sy: f32 = -10000;
                _ = self.project(k.x + sway - self.cam_x, y - self.cam_y, k.z + 0.3 * sway, &sx, &sy);
                self.kelp_sx[i][s] = toI16(sx);
                self.kelp_sy[i][s] = toI16(sy);
            }
        }
    }

    fn stepFish(self: *State, dt_f: f32) void {
        for (0..NUM_FISH) |i| {
            var f = self.fish[i];
            const kind = f.kind;
            const kf: f32 = @floatFromInt(kind);
            const slot_f: f32 = @floatFromInt(i % 8);

            // Each school chases a slowly wandering point in front of the camera.
            const tz = 9.0 + 3.4 * slot_f + 5.0 * self.fastSin(self.phase(0.053) + slot_f * 1.3);
            const tx = 0.55 * tz * self.fastSin(self.phase(0.071) + slot_f * 1.9) + 3.0 * self.fastSin(self.phase(0.19) + kf * 0.7);
            const ty = 5.2 + 3.2 * self.fastSin(self.phase(0.11) + slot_f * 2.3);

            var sep_x: f32 = 0;
            var sep_y: f32 = 0;
            var sep_z: f32 = 0;
            var ali_x: f32 = 0;
            var ali_y: f32 = 0;
            var ali_z: f32 = 0;
            var coh_x: f32 = 0;
            var coh_y: f32 = 0;
            var coh_z: f32 = 0;
            var n: f32 = 0;
            const sep_r2 = 2.2 * f.size * f.size;
            for (1..18) |k| {
                const j = (i + k * 8) % NUM_FISH; // same slot -> same school
                const o = self.fish[j];
                const dx = o.x - f.x;
                const dy = o.y - f.y;
                const dz = o.z - f.z;
                const d2 = dx * dx + dy * dy + dz * dz;
                if (d2 > 1e-4 and d2 < 16.0) {
                    if (d2 < sep_r2) {
                        const inv = 1.0 / d2;
                        sep_x -= dx * inv;
                        sep_y -= dy * inv;
                        sep_z -= dz * inv;
                    }
                    ali_x += o.vx;
                    ali_y += o.vy;
                    ali_z += o.vz;
                    coh_x += o.x;
                    coh_y += o.y;
                    coh_z += o.z;
                    n += 1;
                }
            }
            if (n > 0) {
                const inv_n = 1.0 / n;
                f.vx += ((ali_x * inv_n - f.vx) * 1.2 + (coh_x * inv_n - f.x) * 0.5 + sep_x * 1.6) * dt_f;
                f.vy += ((ali_y * inv_n - f.vy) * 1.2 + (coh_y * inv_n - f.y) * 0.5 + sep_y * 1.6) * dt_f;
                f.vz += ((ali_z * inv_n - f.vz) * 1.0 + (coh_z * inv_n - f.z) * 0.3 + sep_z * 1.2) * dt_f;
            }
            f.vx += math.clamp(tx - f.x, -6.0, 6.0) * 0.30 * dt_f;
            f.vy += math.clamp(ty - f.y, -4.0, 4.0) * 0.35 * dt_f;
            f.vz += math.clamp(tz - f.z, -8.0, 8.0) * 0.12 * dt_f;
            f.vy *= 1.0 - 0.6 * dt_f; // fish swim level
            f.vz *= 1.0 - 0.5 * dt_f; // and mostly across the view, so we see them side-on

            const ground = self.terrain(f.x + self.cam_x, self.scroll_z + f.z) + 0.9;
            if (f.y < ground) f.vy += (ground - f.y) * 6.0 * dt_f;
            if (f.y > 11.0) f.vy -= (f.y - 11.0) * 3.0 * dt_f;

            const sp = @sqrt(f.vx * f.vx + f.vy * f.vy + f.vz * f.vz);
            const lo = 0.9 * KIND_SPEED[kind];
            const hi = 2.6 * KIND_SPEED[kind];
            const cs = math.clamp(sp, lo, hi);
            if (sp > 1e-4) {
                f.vx = f.vx / sp * cs;
                f.vy = f.vy / sp * cs;
                f.vz = f.vz / sp * cs;
            } else {
                f.vx = lo;
            }

            // Keep some forward way on, so nobody hangs head-up in the water.
            const hs = @sqrt(f.vx * f.vx + f.vz * f.vz);
            if (hs < 0.6 * lo) {
                if (hs > 1e-4) {
                    f.vx *= 0.6 * lo / hs;
                    f.vz *= 0.6 * lo / hs;
                } else {
                    f.vx = 0.6 * lo;
                }
            }

            f.x += f.vx * dt_f;
            f.y += f.vy * dt_f;
            f.z += (f.vz - CAM_SPEED) * dt_f;
            f.x = math.clamp(f.x, -40.0, 40.0);
            f.y = math.clamp(f.y, -2.0, SURFACE_Y);
            f.z = math.clamp(f.z, 3.0, 45.0);
            f.wag = @mod(f.wag + dt_f * (5.0 + 3.0 * cs / f.size), TWO_PI);
            self.fish[i] = f;
        }

        // Far-to-near order. The list barely changes between frames, so insertion sort is ~O(n).
        var i: usize = 1;
        while (i < NUM_FISH) : (i += 1) {
            const cur = self.order[i];
            const zc = self.fish[cur].z;
            var j = i;
            while (j > 0 and self.fish[self.order[j - 1]].z < zc) : (j -= 1) {
                self.order[j] = self.order[j - 1];
            }
            self.order[j] = cur;
        }
    }

    fn stepParticles(self: *State, dt_f: f32) void {
        for (&self.snow) |*m| {
            m.z -= CAM_SPEED * dt_f;
            m.y -= 0.08 * dt_f;
            m.x += 0.12 * self.fastSin(self.phase(0.3) + m.phase) * dt_f;
            if (m.z < 1.5) m.z += 40.0;
            if (m.y < -1.0) m.y += SURFACE_Y + 1.0;
        }
        for (&self.bubbles) |*b| {
            b.y += b.vy * dt_f;
            b.z -= CAM_SPEED * dt_f;
            b.phase = @mod(b.phase + 3.1 * dt_f, TWO_PI);
            if (b.y > SURFACE_Y or b.z < 2.5) {
                b.z = 6.0 + rand01(&self.rng) * 28.0;
                b.x = (rand01(&self.rng) - 0.5) * 30.0;
                b.y = self.terrain(b.x + self.cam_x, self.scroll_z + b.z);
                b.r = 0.04 + 0.10 * rand01(&self.rng);
            }
        }
    }

    // ---------------------------------------------------------------- draw --

    inline fn addPixel(buf: []u32, idx: usize, col: u32) void {
        const dst = buf[idx];
        const r: u32 = @min(@as(u32, 255), (dst & 0xFF) + (col & 0xFF));
        const g: u32 = @min(@as(u32, 255), ((dst >> 8) & 0xFF) + ((col >> 8) & 0xFF));
        const b: u32 = @min(@as(u32, 255), ((dst >> 16) & 0xFF) + ((col >> 16) & 0xFF));
        buf[idx] = 0xFF000000 | (b << 16) | (g << 8) | r;
    }

    inline fn blendPixel(buf: []u32, idx: usize, col: u32, a256: u32) void {
        buf[idx] = sdk.lerpRGB(buf[idx], col, a256) | 0xFF000000;
    }

    /// Clipped Bresenham line. mode 0 adds `col`, mode 1 blends it at `a256`.
    fn line(buf: []u32, stride: usize, w: i32, h: i32, x0_in: i32, y0_in: i32, x1: i32, y1: i32, col: u32, mode: u1, a256: u32) void {
        if ((x0_in < 0 and x1 < 0) or (x0_in >= w and x1 >= w)) return;
        if ((y0_in < 0 and y1 < 0) or (y0_in >= h and y1 >= h)) return;
        const dxr = x1 - x0_in;
        const dyr = y1 - y0_in;
        if (dxr * dxr + dyr * dyr > 300 * 300) return;

        var x0 = x0_in;
        var y0 = y0_in;
        const dx: i32 = @intCast(@abs(dxr));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const dy: i32 = -@as(i32, @intCast(@abs(dyr)));
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;
        var steps: usize = 0;
        while (steps < 640) : (steps += 1) {
            if (x0 >= 0 and x0 < w and y0 >= 0 and y0 < h) {
                const idx = @as(usize, @intCast(y0)) * stride + @as(usize, @intCast(x0));
                if (mode == 0) addPixel(buf, idx, col) else blendPixel(buf, idx, col, a256);
            }
            if (x0 == x1 and y0 == y1) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                x0 += sx;
            }
            if (e2 <= dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        if (self.w == 0 or self.h == 0 or stride < self.w) return;
        const w = self.w;
        const h = @min(self.h, buf.len / stride);
        const wi: i32 = @intCast(w);
        const hi: i32 = @intCast(h);

        // 1. Water column and god rays.
        for (0..h) |y| {
            const row = buf[y * stride .. y * stride + w];
            const base = self.row_bg[y];
            const gain = self.row_ray[y];
            if (gain == 0) {
                @memset(row, base);
                continue;
            }
            const br = base & 0xFF;
            const bg = (base >> 8) & 0xFF;
            const bb = (base >> 16) & 0xFF;
            const off = (y * RAY_SLANT_Q6) >> 6;
            const rays = self.rays[off .. off + w];
            for (row, rays) |*px, v| {
                const a = (@as(u32, v) * gain) >> 8;
                const r: u32 = @min(255, br + ((a * 110) >> 8));
                const g: u32 = @min(255, bg + ((a * 190) >> 8));
                const b: u32 = @min(255, bb + ((a * 200) >> 8));
                px.* = 0xFF000000 | (b << 16) | (g << 8) | r;
            }
        }

        // 2. Seabed wireframe: contour ribs plus softer depth filaments.
        for (0..GRID_Z) |iz| {
            for (0..GRID_X - 1) |ix| {
                line(buf, stride, wi, hi, self.mesh_sx[iz][ix], self.mesh_sy[iz][ix], self.mesh_sx[iz][ix + 1], self.mesh_sy[iz][ix + 1], self.mesh_col[iz][ix], 0, 0);
            }
            if (iz + 1 < GRID_Z) {
                var ix: usize = 0;
                while (ix < GRID_X) : (ix += 2) {
                    const c = sdk.scaleRGB(self.mesh_col[iz][ix], 150);
                    line(buf, stride, wi, hi, self.mesh_sx[iz][ix], self.mesh_sy[iz][ix], self.mesh_sx[iz + 1][ix], self.mesh_sy[iz + 1][ix], c, 0, 0);
                }
            }
        }

        // 3. Kelp, far to near (kelp z is spread evenly, so draw the deepest first by wrap point).
        var far: usize = 0;
        for (0..NUM_KELP) |i| {
            if (self.kelp[i].z > self.kelp[far].z) far = i;
        }
        for (0..NUM_KELP) |n| {
            const i = (far + NUM_KELP - n) % NUM_KELP;
            self.drawKelp(buf, stride, wi, hi, i);
        }

        // 4. Marine snow.
        for (self.snow) |m| {
            var sx: f32 = 0;
            var sy: f32 = 0;
            if (!self.project(m.x - 0.0, m.y - self.cam_y, m.z, &sx, &sy)) continue;
            if (sx < 1 or sy < 1 or sx >= @as(f32, @floatFromInt(w - 1)) or sy >= @as(f32, @floatFromInt(h - 1))) continue;
            const lum: u8 = toU8(70.0 * @exp(-0.05 * m.z) + 8.0);
            const c = sdk.packRGBA(lum >> 1, (lum * 3) >> 2, lum);
            const ux: usize = @intFromFloat(sx);
            const uy: usize = @intFromFloat(sy);
            addPixel(buf, uy * stride + ux, c);
            if (m.z < 6.0) {
                addPixel(buf, uy * stride + ux + 1, c);
                addPixel(buf, (uy + 1) * stride + ux, c);
                addPixel(buf, (uy + 1) * stride + ux + 1, c);
            }
        }

        // 5. Bubbles.
        for (self.bubbles) |b| self.drawBubble(buf, stride, w, h, b);

        // 6. Fish, far to near.
        for (self.order) |idx| self.drawFish(buf, stride, w, h, self.fish[idx]);
    }

    fn drawKelp(self: *const State, buf: []u32, stride: usize, wi: i32, hi: i32, i: usize) void {
        const col = self.kelp_col[i];
        const thick: i32 = self.kelp_thick[i];
        for (0..KELP_SEG) |s| {
            const x0: i32 = self.kelp_sx[i][s];
            const y0: i32 = self.kelp_sy[i][s];
            const x1: i32 = self.kelp_sx[i][s + 1];
            const y1: i32 = self.kelp_sy[i][s + 1];
            // Taper toward the tip.
            const tw = @max(1, @divTrunc(thick * @as(i32, @intCast(KELP_SEG - s)) + @as(i32, @intCast(KELP_SEG)) - 1, @as(i32, @intCast(KELP_SEG))));
            var o: i32 = 0;
            while (o < tw) : (o += 1) {
                const dxo = o - @divTrunc(tw, 2);
                const a: u32 = if (o == 0 or o == tw - 1) 150 else 230;
                line(buf, stride, wi, hi, x0 + dxo, y0, x1 + dxo, y1, col, 1, a);
            }
        }
    }

    fn drawBubble(self: *const State, buf: []u32, stride: usize, w: usize, h: usize, b: Bubble) void {
        var sx: f32 = 0;
        var sy: f32 = 0;
        const wob = 0.12 * self.fastSin(b.phase);
        if (!self.project(b.x + wob, b.y - self.cam_y, b.z, &sx, &sy)) return;
        const rpx = FOCAL * @as(f32, @floatFromInt(self.h)) * b.r / b.z;
        if (rpx < 0.6) return;
        const wf: f32 = @floatFromInt(w);
        const hf: f32 = @floatFromInt(h);
        if (sx < -rpx or sy < -rpx or sx > wf + rpx or sy > hf + rpx) return;
        const fade = math.clamp(@exp(-0.04 * b.z), 0.2, 1.0);
        const rim = sdk.packRGBA(toU8(80 * fade), toU8(130 * fade), toU8(150 * fade));
        const segs: usize = @intFromFloat(math.clamp(rpx * 6.0, 8.0, 96.0));
        for (0..segs) |k| {
            const a = TWO_PI * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(segs));
            const px = sx + rpx * self.fastCos(a);
            const py = sy + rpx * self.fastSin(a);
            if (px < 0 or py < 0 or px >= wf or py >= hf) continue;
            addPixel(buf, @as(usize, @intFromFloat(py)) * stride + @as(usize, @intFromFloat(px)), rim);
        }
        // Specular glint, upper left.
        const gx = sx - 0.4 * rpx;
        const gy = sy - 0.4 * rpx;
        if (gx >= 0 and gy >= 0 and gx < wf and gy < hf) {
            addPixel(buf, @as(usize, @intFromFloat(gy)) * stride + @as(usize, @intFromFloat(gx)), sdk.packRGBA(toU8(150 * fade), toU8(200 * fade), toU8(210 * fade)));
        }
    }

    fn drawFish(self: *const State, buf: []u32, stride: usize, w: usize, h: usize, f: Fish) void {
        const sp = @sqrt(f.vx * f.vx + f.vy * f.vy + f.vz * f.vz);
        if (sp < 1e-4) return;
        // Fish pitch only a little even when climbing, so flatten vy for the body axis.
        const hs = @sqrt(f.vx * f.vx + f.vz * f.vz);
        const pv = math.clamp(0.3 * f.vy, -0.4 * hs, 0.4 * hs);
        const sp_o = @sqrt(f.vx * f.vx + pv * pv + f.vz * f.vz);
        if (sp_o < 1e-4) return;
        const dx = f.vx / sp_o;
        const dy = pv / sp_o;
        const dz = f.vz / sp_o;
        const half = 0.5 * f.size;
        const ry = f.y - self.cam_y;

        var hx: f32 = 0;
        var hy: f32 = 0;
        var tx: f32 = 0;
        var ty: f32 = 0;
        if (!self.project(f.x + dx * half, ry + dy * half, f.z + dz * half, &hx, &hy)) return;
        if (!self.project(f.x - dx * half, ry - dy * half, f.z - dz * half, &tx, &ty)) return;

        const hf: f32 = @floatFromInt(self.h);
        const W = FOCAL * hf * f.size * KIND_DEPTH[f.kind] / f.z; // half body depth in px
        if (W < 0.5) return;
        var ax = tx - hx;
        var ay = ty - hy;
        var L = @sqrt(ax * ax + ay * ay);
        if (L < 1e-3) {
            ax = 1;
            ay = 0;
            L = 1;
        }
        ax /= L;
        ay /= L;
        // A fish seen nose-on still reads as a fish, not a dot.
        if (L < 2.2 * W) {
            const mx = 0.5 * (hx + tx);
            const my = 0.5 * (hy + ty);
            L = 2.2 * W;
            hx = mx - ax * 0.5 * L;
            hy = my - ay * 0.5 * L;
            tx = mx + ax * 0.5 * L;
            ty = my + ay * 0.5 * L;
        }

        const pad = 1.2 * W + 2.0;
        const wf: f32 = @floatFromInt(w);
        const hfs: f32 = @floatFromInt(h);
        const x_lo = math.clamp(@min(hx, tx) - pad, 0.0, wf);
        const x_hi = math.clamp(@max(hx, tx) + pad, 0.0, wf);
        const y_lo = math.clamp(@min(hy, ty) - pad, 0.0, hfs);
        const y_hi = math.clamp(@max(hy, ty) + pad, 0.0, hfs);
        if (x_hi - x_lo < 1 or y_hi - y_lo < 1) return;
        if ((x_hi - x_lo) * (y_hi - y_lo) > 360.0 * 360.0) return;

        // Belly points down the screen.
        const belly: f32 = if (ax >= 0) 1.0 else -1.0; // n = (-ay, ax); n.y = ax
        const wag_amp = 0.11 * L * self.fastSin(f.wag);
        const fog = math.clamp(1.0 - @exp(-0.045 * f.z), 0.0, 0.9);
        const kind = f.kind;
        const back = KIND_BACK[kind];
        const bel = KIND_BELLY[kind];
        const inv_L = 1.0 / L;
        const eye_r2 = @max(0.8, 0.17 * W) * @max(0.8, 0.17 * W);

        const yi0: usize = @intFromFloat(y_lo);
        const yi1: usize = @intFromFloat(y_hi);
        const xi0: usize = @intFromFloat(x_lo);
        const xi1: usize = @intFromFloat(x_hi);
        for (yi0..yi1) |py| {
            const water = self.row_bg[py];
            const wr: f32 = @floatFromInt(water & 0xFF);
            const wg: f32 = @floatFromInt((water >> 8) & 0xFF);
            const wb: f32 = @floatFromInt((water >> 16) & 0xFF);
            const ddy = @as(f32, @floatFromInt(py)) + 0.5 - hy;
            for (xi0..xi1) |px| {
                const ddx = @as(f32, @floatFromInt(px)) + 0.5 - hx;
                const u = (ddx * ax + ddy * ay) * inv_L;
                if (u < -0.03 or u > 1.0) continue;
                const uc = math.clamp(u, 0.0, 1.0);
                const v = (ddx * -ay + ddy * ax) - wag_amp * uc * uc;
                const av = @abs(v);

                var hw = W * self.prof[@as(usize, @intFromFloat(uc * @as(f32, @floatFromInt(PROF_N - 1))))];
                var is_tail = false;
                if (u > 0.74) {
                    const tf = (u - 0.74) / 0.26;
                    const tw = W * 1.05 * tf;
                    // Forked tail: a notch opens at the trailing edge.
                    const notch = if (tf > 0.7) W * 0.5 * (tf - 0.7) / 0.3 else 0.0;
                    if (tw > hw and av > notch) {
                        hw = tw;
                        is_tail = true;
                    }
                }
                const cov = math.clamp(hw - av + 0.5, 0.0, 1.0);
                if (cov <= 0.0) continue;

                const s = math.clamp(v * belly / @max(hw, 0.5), -1.0, 1.0);
                const t = 0.5 + 0.5 * s;
                var r = back[0] + (bel[0] - back[0]) * t;
                var g = back[1] + (bel[1] - back[1]) * t;
                var b = back[2] + (bel[2] - back[2]) * t;

                switch (kind) {
                    0 => { // neon tetra: electric blue stripe, red rear belly
                        if (!is_tail and @abs(s + 0.05) < 0.17 and u > 0.08 and u < 0.74) {
                            r = 50;
                            g = 200;
                            b = 255;
                        } else if (!is_tail and s > 0.2 and u > 0.42 and u < 0.76) {
                            r = 225;
                            g = 40;
                            b = 52;
                        }
                    },
                    1 => { // yellow tang: pale spine at the tail root
                        if (u > 0.70 and u < 0.76) {
                            r = 255;
                            g = 250;
                            b = 235;
                        }
                    },
                    2 => { // clownfish: white bands with dark edges
                        if ((u > 0.22 and u < 0.30) or (u > 0.50 and u < 0.57)) {
                            r = 248;
                            g = 246;
                            b = 240;
                        } else if ((u > 0.205 and u < 0.315) or (u > 0.485 and u < 0.585) or (is_tail and u > 0.94)) {
                            r = 30;
                            g = 18;
                            b = 12;
                        }
                    },
                    else => { // silver: bright lateral line
                        if (!is_tail and @abs(s) < 0.07) {
                            r = 235;
                            g = 242;
                            b = 248;
                        }
                    },
                }

                // Eye.
                const eu = (u - 0.12) * L;
                const ev = v * belly + 0.22 * W;
                if (eu * eu + ev * ev < eye_r2) {
                    r = 14;
                    g = 14;
                    b = 20;
                }

                r += (wr - r) * fog;
                g += (wg - g) * fog;
                b += (wb - b) * fog;
                const a256: u32 = @intFromFloat(cov * 245.0);
                blendPixel(buf, py * stride + px, sdk.packRGBA(toU8(r), toU8(g), toU8(b)), a256);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (!math.isFinite(self.time_sec) or !math.isFinite(self.scroll_z)) return true;
        for (self.fish) |f| {
            if (!math.isFinite(f.x) or !math.isFinite(f.y) or !math.isFinite(f.z)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

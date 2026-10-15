// @argus-theme: custom_shader
// ============================================================================
// GEMINI WORMHOLE // themes/Gemini_Wormhole.zig
// Author: Google Gemini (ARGUS-BENCH Track A entry). Ported to Argus 135 by
// Claude Opus, which replaced the disk's ever-winding shear with a rigid
// pattern speed plus bounded shear and made all time phases wrap in f64.
//
// A stylised traversable wormhole. Nobody knows what lies inside one, so this
// theme imagines it: the physics is a starting point, the look is artistic.
//
// Inspired by, not solved from:
//   - Ellis-Bronnikov / Morris-Thorne geometry,
//     ds^2 = -dt^2 + dl^2 + (b_0^2 + l^2)(d\theta^2 + \sin^2\theta d\phi^2).
//     Rays are traced through the throat (velocity-Verlet, 96 steps) with the
//     Ellis bending term plus hand-tuned attraction terms (MASS_PARAM) so the
//     lensing reads like gravity; it is not an exact geodesic solve.
//     Rays that cross the throat show Universe B: its own sky and disk.
//   - The accretion disks' Doppler shift and redshift use tuned formulas, and
//     their colours are an artistic false-colour palette (amber/cyan in
//     Universe A, violet/turquoise in Universe B), not blackbody light.
//   - Spiral density waves, MHD-style ripples and drifting plasma knots that
//     fall through the throat animate the disks in step(dt).
//   - 1 allocation at init (~16 MiB) and 0 after.
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

// Active relativistic lensing bounding box (centered on screen, 1024x920 = 942,080 pixels).
// Outside this box, rays have negligible deflection and blend seamlessly into the static
// deep-field background LUT copied at memory-bandwidth speed via @memcpy.
pub const BOX_W: usize = 1024;
pub const BOX_H: usize = 920;
pub const BOX_PIXELS: usize = BOX_W * BOX_H;

pub const RAD_BINS: usize = 512;
pub const ANG_BINS: usize = 1024;
pub const COLOR_BINS: usize = 4096;
pub const NUM_PARTICLES: usize = 320;

/// Compact 4-byte precomputed geodesic lookup record per active bounding-box pixel.
/// Total LUT size: 1024 * 920 * 4 bytes = 3,768,320 bytes (~3.59 MiB).
pub const GeodesicPixel = extern struct {
    /// Packed integer storage:
    /// [0..8]   r1_idx   (9 bits: 0..511 radial bin for primary disk crossing)
    /// [9]      r1_side  (1 bit : 0 = Universe A, 1 = Universe B)
    /// [10..18] r2_idx   (9 bits: 0..511 radial bin for secondary caustic crossing)
    /// [19]     r2_side  (1 bit : 0 = Universe A, 1 = Universe B)
    /// [20..29] phi1_idx (10 bits: 0..1023 azimuthal angle bin for primary crossing)
    /// [30..31] flags    (2 bits : bit 0 = hit1, bit 1 = hit2)
    packed_coords: u32,

    /// Azimuthal angle bin for secondary crossing (0..1023 in low 10 bits)
    /// + 6 bits of background sky transmission factor (0..63).
    phi2_and_trans: u16,

    /// Primary relativistic Doppler shift factor g_1 (quantized 0..255 -> g in [0.25, 2.25])
    g1_quant: u8,

    /// Secondary / throat glow / Einstein ring intensity weight (0..255)
    ring_and_g2: u8,
};

pub const PlasmaKnot = struct {
    l_coord: f32, // Proper radial distance from throat (-4.5 .. +4.5)
    phi: f32, // Azimuthal angle (0 .. 2*pi)
    omega: f32, // Relativistic keplerian angular velocity
    temp: f32, // Normalized emission temperature (0.5 .. 1.8)
    size_inv: f32, // Inverse Gaussian spot width
};

pub const State = struct {
    w: usize,
    h: usize,
    box_x0: usize,
    box_y0: usize,
    scale: f64,
    time_sec: f64,

    // Full-screen precomputed static deep-space background (Universe A nebula & starfield)
    // 1920 * 1200 * 4 = 9,216,000 bytes (~8.79 MiB)
    bg_lut: [MAX_PIXELS]u32,

    // Active bounding-box precomputed geodesic LUT
    // 1024 * 920 * 4 = 3,768,320 bytes -> Wait: 9.21 + 3.76 = 12.98 MiB.
    // Let's keep total @sizeOf(State) strictly <= 11.5 MiB!
    // By storing active box at 880x760 (668,800 pixels * 4B = 2.55 MiB),
    // Total State size is ~11.4 MiB (< 12 MiB recommended limit).
    geodesic_lut: [ACT_PIXELS]GeodesicPixel,
    portal_bg_lut: [ACT_PIXELS]u32, // Lensed Universe B / Lensed Universe A background behind the disk!

    // Per-frame 1D separable turbulence & MHD wave tables updated in step(dt)
    rad_profile_a: [RAD_BINS]f32,
    rad_profile_b: [RAD_BINS]f32,
    spiral_sin_a: [RAD_BINS]f32,
    spiral_cos_a: [RAD_BINS]f32,
    spiral_sin_b: [RAD_BINS]f32,
    spiral_cos_b: [RAD_BINS]f32,

    ang_wave_m2: [ANG_BINS]f32,
    ang_wave_m3: [ANG_BINS]f32,
    ang_wave_m5: [ANG_BINS]f32,
    ang_cos: [ANG_BINS]f32,
    ang_sin: [ANG_BINS]f32,

    // High-dynamic-range Planckian relativistic color LUT (temperature x intensity -> packed RGBA)
    // 16 Doppler/temperature bands x 256 intensity levels = 4096 entries
    color_lut_a: [COLOR_BINS]u32,
    color_lut_b: [COLOR_BINS]u32,

    // Symplectic MHD plasma knots orbiting in both universes
    knots: [NUM_PARTICLES]PlasmaKnot,

    pub const ACT_W: usize = 864;
    pub const ACT_H: usize = 720;
    pub const ACT_PIXELS: usize = ACT_W * ACT_H;

    // Physical Wormhole Parameters (in units of throat radius b_0 = 1.0)
    const B0: f64 = 1.0;
    const MASS_PARAM: f64 = 0.42; // Effective gravitational mass parameter for outer disk orbits
    const CAM_L: f64 = 9.5; // Observer at l = +9.5 b_0 in Universe A
    const CAM_INCLINATION: f64 = 79.0 * (math.pi / 180.0); // 79 deg nearly edge-on view
    const CAM_TILT: f64 = -14.0 * (math.pi / 180.0); // Aesthetic cinematic roll angle
    const DISK_MAX_L: f64 = 4.2; // Outer accretion disk cutoff in l (fits cleanly inside active window)

    inline fn xorshift64(state: *u64) u64 {
        var x = state.*;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        state.* = x;
        return x;
    }

    inline fn randFloat(state: *u64) f64 {
        return @as(f64, @floatFromInt(xorshift64(state) & 0x1FFFFFFFFFFFFF)) / @as(f64, 0x20000000000000);
    }

    inline fn smoothstep(edge0: f64, edge1: f64, x: f64) f64 {
        const t = math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    /// Hash-based 3D value noise for procedural celestial skyboxes (Universe A & Universe B)
    fn hash3(ix: i32, iy: i32, iz: i32) f64 {
        const ux: u32 = @bitCast(ix);
        const uy: u32 = @bitCast(iy);
        const uz: u32 = @bitCast(iz);
        var n: u32 = ux *% 1597334677 +% uy *% 3812015801 +% uz *% 2912667907;
        n = (n ^ (n >> 13)) *% 1274126177;
        n = n ^ (n >> 16);
        return @as(f64, @floatFromInt(n & 0x00FFFFFF)) / @as(f64, 0x01000000);
    }

    fn noise3D(x: f64, y: f64, z: f64) f64 {
        const ix: i32 = @intFromFloat(@floor(x));
        const iy: i32 = @intFromFloat(@floor(y));
        const iz: i32 = @intFromFloat(@floor(z));
        const fx = x - @floor(x);
        const fy = y - @floor(y);
        const fz = z - @floor(z);
        const ux = fx * fx * (3.0 - 2.0 * fx);
        const uy = fy * fy * (3.0 - 2.0 * fy);
        const uz = fz * fz * (3.0 - 2.0 * fz);

        const n000 = hash3(ix, iy, iz);
        const n100 = hash3(ix + 1, iy, iz);
        const n010 = hash3(ix, iy + 1, iz);
        const n110 = hash3(ix + 1, iy + 1, iz);
        const n001 = hash3(ix, iy, iz + 1);
        const n101 = hash3(ix + 1, iy, iz + 1);
        const n011 = hash3(ix, iy + 1, iz + 1);
        const n111 = hash3(ix + 1, iy + 1, iz + 1);

        const nx00 = n000 + ux * (n100 - n000);
        const nx10 = n010 + ux * (n110 - n010);
        const nx01 = n001 + ux * (n101 - n001);
        const nx11 = n011 + ux * (n111 - n011);

        const nxy0 = nx00 + uy * (nx10 - nx00);
        const nxy1 = nx01 + uy * (nx11 - nx01);

        return nxy0 + uz * (nxy1 - nxy0);
    }

    /// Evaluates celestial sky color for unit direction vector `dir` in either
    /// Universe A (`is_universe_b == false`: deep sapphire-indigo cosmic web) or
    /// Universe B (`is_universe_b == true`: vibrant gold-magenta-cyan starburst nebula seen through the wormhole throat).
    fn sampleCelestialSky(dx: f64, dy: f64, dz: f64, is_universe_b: bool) [3]f64 {
        const f1 = noise3D(dx * 3.5 + 1.3, dy * 3.5 - 2.1, dz * 3.5 + 0.7);
        const f2 = noise3D(dx * 7.2 - 4.1, dy * 7.2 + 1.9, dz * 7.2 - 3.3);
        const f3 = noise3D(dx * 15.0 + 2.7, dy * 15.0 + 5.1, dz * 15.0 - 1.4);
        const fbm = 0.55 * f1 + 0.30 * f2 + 0.15 * f3;

        // High-frequency procedural starfield on spherical grid
        const star_cell = noise3D(dx * 95.0, dy * 95.0, dz * 95.0);
        const star_sharp = math.pow(f64, @max(0.0, (star_cell - 0.76) / 0.24), 5.0);
        const star_tint = noise3D(dx * 40.0 + 9.0, dy * 40.0, dz * 40.0);

        if (!is_universe_b) {
            // Universe A: Deep Obsidian-Sapphire Galactic Plane + Fine Pinpoint Stars
            const galactic_band = @exp(-10.0 * (dy + 0.25 * dx) * (dy + 0.25 * dx));
            const dust_lane = smoothstep(0.35, 0.70, fbm);
            var r = 0.015 + 0.045 * galactic_band * dust_lane + 0.02 * f1;
            var g = 0.024 + 0.075 * galactic_band * dust_lane + 0.035 * f2;
            var b = 0.052 + 0.145 * galactic_band * dust_lane + 0.065 * f1;

            // Add crisp stars
            r += star_sharp * (0.9 + 0.4 * star_tint);
            g += star_sharp * (0.92 + 0.1 * star_tint);
            b += star_sharp * (1.05 - 0.3 * star_tint);
            return .{ r, g, b };
        } else {
            // Universe B (seen *inside* the Einstein ring through the wormhole throat):
            // Luminous Teal-Magenta-Gold Quasar Starforming Nebula
            const nebula_core = smoothstep(0.28, 0.82, fbm);
            const filament = math.pow(f64, @max(0.0, 1.0 - @abs(2.0 * f2 - 1.0)), 3.0);
            var r = 0.06 + 0.42 * nebula_core * f1 + 0.35 * filament;
            var g = 0.05 + 0.28 * nebula_core * f2 + 0.55 * filament * f3;
            var b = 0.14 + 0.65 * nebula_core + 0.45 * filament;

            // Dense brilliant star cluster in Universe B
            const star_b = math.pow(f64, @max(0.0, (star_cell - 0.70) / 0.30), 4.0);
            r += star_b * (1.2 + 0.5 * star_tint);
            g += star_b * (1.1 + 0.2 * star_tint);
            b += star_b * (0.95 - 0.2 * star_tint);
            return .{ r, g, b };
        }
    }

    /// Builds the precomputed relativistic blackbody + Doppler shift color lookup tables.
    fn initColorLUTs(self: *State) void {
        for (0..16) |g_bin| {
            // Doppler factor g spans [0.45 .. 1.95]
            const g_factor = 0.45 + (@as(f64, @floatFromInt(g_bin)) / 15.0) * 1.50;
            for (0..256) |i_bin| {
                const intensity = (@as(f64, @floatFromInt(i_bin)) / 255.0);
                // Smooth incandescent emission curve (avoids squaring low intensities to black)
                const energy = intensity * (0.85 + 1.35 * intensity);

                // Universe A Accretion Disk Palette:
                // Redshifted side (low g) -> Deep crimson / burnt amber-gold
                // Unshifted (g ~ 1)       -> Brilliant golden-orange plasma
                // Blueshifted side (high g)-> Incandescent cyan-white / electric blue
                const temp_a = g_factor;
                const ra_lin = energy * math.pow(f64, @max(0.05, temp_a * 1.20), 0.65);
                const ga_lin = energy * math.pow(f64, @max(0.02, temp_a * 0.95 - 0.05), 1.05);
                const ba_lin = energy * math.pow(f64, @max(0.01, temp_a * 0.85 - 0.15), 1.45);

                // ACES-inspired filmic shoulder tone mapping
                const ra = ra_lin / (1.0 + 0.55 * ra_lin);
                const ga = ga_lin / (1.0 + 0.55 * ga_lin);
                const ba = ba_lin / (1.0 + 0.55 * ba_lin);

                const r8_a: u8 = @intFromFloat(math.clamp(@round(math.pow(f64, ra, 0.78) * 255.0), 0.0, 255.0));
                const g8_a: u8 = @intFromFloat(math.clamp(@round(math.pow(f64, ga, 0.78) * 255.0), 0.0, 255.0));
                const b8_a: u8 = @intFromFloat(math.clamp(@round(math.pow(f64, ba, 0.78) * 255.0), 0.0, 255.0));
                self.color_lut_a[g_bin * 256 + i_bin] = sdk.packRGBA(r8_a, g8_a, b8_a);

                // Universe B Accretion Disk Palette (seen through wormhole throat & secondary arch):
                // Exotic matter-coupled plasma -> Violet-magenta to electric turquoise-gold
                const rb_lin = energy * math.pow(f64, @max(0.04, temp_a * 0.98), 0.90);
                const gb_lin = energy * math.pow(f64, @max(0.04, temp_a * 1.08), 0.85);
                const bb_lin = energy * math.pow(f64, @max(0.08, temp_a * 1.30 + 0.10), 0.65);

                const rb = rb_lin / (1.0 + 0.55 * rb_lin);
                const gb = gb_lin / (1.0 + 0.55 * gb_lin);
                const bb = bb_lin / (1.0 + 0.55 * bb_lin);

                const r8_b: u8 = @intFromFloat(math.clamp(@round(math.pow(f64, rb, 0.78) * 255.0), 0.0, 255.0));
                const g8_b: u8 = @intFromFloat(math.clamp(@round(math.pow(f64, gb, 0.78) * 255.0), 0.0, 255.0));
                const b8_b: u8 = @intFromFloat(math.clamp(@round(math.pow(f64, bb, 0.78) * 255.0), 0.0, 255.0));
                self.color_lut_b[g_bin * 256 + i_bin] = sdk.packRGBA(r8_b, g8_b, b8_b);
            }
        }
    }

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;

        self.box_x0 = if (self.w > ACT_W) (self.w - ACT_W) / 2 else 0;
        self.box_y0 = if (self.h > ACT_H) (self.h - ACT_H) / 2 else 0;

        self.initColorLUTs();

        // Precompute azimuthal trig tables
        for (0..ANG_BINS) |i| {
            const phi = (@as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(ANG_BINS))) * (2.0 * math.pi);
            self.ang_cos[i] = @floatCast(@cos(phi));
            self.ang_sin[i] = @floatCast(@sin(phi));
        }

        // Camera orthonormal basis in Universe A spherical/Cartesian coordinates.
        // Accretion disk lies in the equatorial plane Z = 0.
        // Observer is at distance CAM_L, inclination CAM_INCLINATION from Z-axis, in the X-Z plane.
        const sin_inc = @sin(CAM_INCLINATION);
        const cos_inc = @cos(CAM_INCLINATION);
        const sin_tilt = @sin(CAM_TILT);
        const cos_tilt = @cos(CAM_TILT);

        // Radial unit vector pointing from origin toward observer:
        const cam_rx = sin_inc;
        const cam_ry = 0.0;
        const cam_rz = cos_inc;

        // Forward vector pointing from observer toward wormhole throat (-cam_r):
        const fwd_x = -cam_rx;
        const fwd_y = -cam_ry;
        const fwd_z = -cam_rz;

        // Unrotated camera screen Right (+Y) and Up (-cos_inc X + sin_inc Z):
        const right0_x = 0.0;
        const right0_y = 1.0;
        const right0_z = 0.0;

        const up0_x = -cos_inc;
        const up0_y = 0.0;
        const up0_z = sin_inc;

        // Apply aesthetic camera roll angle CAM_TILT:
        const right_x = cos_tilt * right0_x + sin_tilt * up0_x;
        const right_y = cos_tilt * right0_y + sin_tilt * up0_y;
        const right_z = cos_tilt * right0_z + sin_tilt * up0_z;

        const up_x = -sin_tilt * right0_x + cos_tilt * up0_x;
        const up_y = -sin_tilt * right0_y + cos_tilt * up0_y;
        const up_z = -sin_tilt * right0_z + cos_tilt * up0_z;

        const half_w = 0.5 * @as(f64, @floatFromInt(self.w));
        const half_h = 0.5 * @as(f64, @floatFromInt(self.h));
        const focal_len = 0.88 * @as(f64, @floatFromInt(self.h)); // Field of view

        const r_obs = @sqrt(B0 * B0 + CAM_L * CAM_L);

        // 1. Populate full-screen static background LUT (Universe A sky + outer disk dust glow)
        var rng: u64 = 0x9E37_79B9_7F4A_7C15;
        for (0..self.h) |y| {
            const sy = (half_h - @as(f64, @floatFromInt(y))) / focal_len;
            for (0..self.w) |x| {
                const sx = (@as(f64, @floatFromInt(x)) - half_w) / focal_len;
                const inv_norm = 1.0 / @sqrt(1.0 + sx * sx + sy * sy);
                const dx = (fwd_x + sx * right_x + sy * up_x) * inv_norm;
                const dy = (fwd_y + sx * right_y + sy * up_y) * inv_norm;
                const dz = (fwd_z + sx * right_z + sy * up_z) * inv_norm;

                const f1 = noise3D(dx * 3.5 + 1.3, dy * 3.5 - 2.1, dz * 3.5 + 0.7);
                const f2 = noise3D(dx * 7.2 - 4.1, dy * 7.2 + 1.9, dz * 7.2 - 3.3);
                const fbm = 0.65 * f1 + 0.35 * f2;
                const galactic_band = @exp(-10.0 * (dy + 0.25 * dx) * (dy + 0.25 * dx));
                const dust_lane = smoothstep(0.35, 0.70, fbm);

                const impact_b = r_obs * @sqrt(@max(0.0, 1.0 - (dx * fwd_x + dy * fwd_y + dz * fwd_z) * (dx * fwd_x + dy * fwd_y + dz * fwd_z)));
                const ambient_glow = 0.035 / (1.0 + 0.12 * impact_b * impact_b);

                const r_sky = 0.012 + 0.040 * galactic_band * dust_lane + 0.018 * f1 + ambient_glow * 0.55;
                const g_sky = 0.018 + 0.068 * galactic_band * dust_lane + 0.030 * f2 + ambient_glow * 0.65;
                const b_sky = 0.042 + 0.135 * galactic_band * dust_lane + 0.058 * f1 + ambient_glow * 1.10;

                const r8: u8 = @intFromFloat(math.clamp(@round(r_sky * 255.0), 0.0, 255.0));
                const g8: u8 = @intFromFloat(math.clamp(@round(g_sky * 255.0), 0.0, 255.0));
                const b8: u8 = @intFromFloat(math.clamp(@round(b_sky * 255.0), 0.0, 255.0));
                self.bg_lut[y * self.w + x] = sdk.packRGBA(r8, g8, b8);
            }
        }

        // Crisp 2D Gaussian point stars across the full screen (no 3D voxel blockiness!)
        for (0..3800) |_| {
            const rx: i32 = @intFromFloat(randFloat(&rng) * @as(f64, @floatFromInt(self.w - 4)) + 2.0);
            const ry: i32 = @intFromFloat(randFloat(&rng) * @as(f64, @floatFromInt(self.h - 4)) + 2.0);
            const u_b = randFloat(&rng);
            const lum = 0.18 + 0.82 * u_b * u_b;
            const tint = randFloat(&rng);
            const sr = lum * (0.82 + 0.35 * tint);
            const sg = lum * (0.88 + 0.12 * tint);
            const sb = lum * (1.12 - 0.28 * tint);

            var oy: i32 = -1;
            while (oy <= 1) : (oy += 1) {
                var ox: i32 = -1;
                while (ox <= 1) : (ox += 1) {
                    const px = rx + ox;
                    const py = ry + oy;
                    if (px >= 0 and px < @as(i32, @intCast(self.w)) and py >= 0 and py < @as(i32, @intCast(self.h))) {
                        const d2 = @as(f64, @floatFromInt(ox * ox + oy * oy));
                        const k_w = @exp(-1.15 * d2);
                        const idx = @as(usize, @intCast(py)) * self.w + @as(usize, @intCast(px));
                        const old = self.bg_lut[idx];
                        const or8: f64 = @floatFromInt(old & 0xFF);
                        const og8: f64 = @floatFromInt((old >> 8) & 0xFF);
                        const ob8: f64 = @floatFromInt((old >> 16) & 0xFF);
                        const nr8: u8 = @intFromFloat(math.clamp(or8 + sr * k_w * 230.0, 0.0, 255.0));
                        const ng8: u8 = @intFromFloat(math.clamp(og8 + sg * k_w * 230.0, 0.0, 255.0));
                        const nb8: u8 = @intFromFloat(math.clamp(ob8 + sb * k_w * 230.0, 0.0, 255.0));
                        self.bg_lut[idx] = sdk.packRGBA(nr8, ng8, nb8);
                    }
                }
            }
        }

        // 2. Precompute exact Ellis-Bronnikov / Generalized Morris-Thorne Wormhole Geodesics
        //    across the active 864x720 bounding box with attractive GR gravitational lensing!
        for (0..ACT_H) |by| {
            const y = self.box_y0 + by;
            const sy = (half_h - @as(f64, @floatFromInt(y))) / focal_len;
            const ny_box = (@as(f64, @floatFromInt(by)) - 0.5 * @as(f64, @floatFromInt(ACT_H))) / (0.5 * @as(f64, @floatFromInt(ACT_H)));

            for (0..ACT_W) |bx| {
                const x = self.box_x0 + bx;
                const sx = (@as(f64, @floatFromInt(x)) - half_w) / focal_len;
                const nx_box = (@as(f64, @floatFromInt(bx)) - 0.5 * @as(f64, @floatFromInt(ACT_W))) / (0.5 * @as(f64, @floatFromInt(ACT_W)));
                const box_rad = @sqrt(nx_box * nx_box + ny_box * ny_box);
                const edge_fade = 1.0 - smoothstep(0.75, 0.98, box_rad);

                const act_idx = by * ACT_W + bx;

                if (edge_fade <= 0.001) {
                    self.geodesic_lut[act_idx] = .{
                        .packed_coords = 0,
                        .phi2_and_trans = 63 << 10,
                        .g1_quant = 128,
                        .ring_and_g2 = 0,
                    };
                    self.portal_bg_lut[act_idx] = self.bg_lut[y * self.w + x];
                    continue;
                }

                // Initial photon direction in 3D Cartesian space:
                const inv_norm = 1.0 / @sqrt(1.0 + sx * sx + sy * sy);
                const dir_x = (fwd_x + sx * right_x + sy * up_x) * inv_norm;
                const dir_y = (fwd_y + sx * right_y + sy * up_y) * inv_norm;
                const dir_z = (fwd_z + sx * right_z + sy * up_z) * inv_norm;

                // Decompose ray direction into radial component (along cam_r) and tangential unit vector e_psi:
                const cos_alpha = math.clamp(-(dir_x * cam_rx + dir_y * cam_ry + dir_z * cam_rz), -1.0, 1.0);
                const sin_alpha = @sqrt(@max(0.0, 1.0 - cos_alpha * cos_alpha));

                var epsi_x: f64 = 0.0;
                var epsi_y: f64 = 1.0;
                var epsi_z: f64 = 0.0;
                if (sin_alpha > 1e-7) {
                    epsi_x = (dir_x + cos_alpha * cam_rx) / sin_alpha;
                    epsi_y = (dir_y + cos_alpha * cam_ry) / sin_alpha;
                    epsi_z = (dir_z + cos_alpha * cam_rz) / sin_alpha;
                }

                const b = r_obs * sin_alpha;
                const b2 = b * b;

                var l_cur: f64 = CAM_L;
                var vl_cur: f64 = -cos_alpha;
                var psi_cur: f64 = 0.0;
                var z_prev: f64 = cam_rz;

                var hit1: bool = false;
                var hit1_r_idx: u32 = 0;
                var hit1_side: u32 = 0;
                var hit1_phi_idx: u32 = 0;
                var hit1_g: f64 = 1.0;

                var hit2: bool = false;
                var hit2_r_idx: u32 = 0;
                var hit2_side: u32 = 0;
                var hit2_phi_idx: u32 = 0;
                var hit2_g: f64 = 1.0;

                var min_abs_l: f64 = @abs(l_cur);

                // Symplectic Velocity-Verlet geodesic integration (96 adaptive steps with ATTRACTIVE gravity!)
                for (0..96) |_| {
                    const r2_cur = B0 * B0 + l_cur * l_cur;
                    const dl_scale = @sqrt(r2_cur);
                    const dlam = 0.11 * dl_scale;

                    const l_prev = l_cur;
                    const psi_prev = psi_cur;

                    // Attractive General Relativistic effective potential for massive Morris-Thorne wormhole:
                    // Centrifugal: +l * b^2 / r^4 ; Relativistic GR attraction: -1.65 * M * l * b^2 / r^5 - 0.55 * M * l / r^3
                    const inv_r2 = 1.0 / r2_cur;
                    const inv_r = @sqrt(inv_r2);
                    const accel1 = l_cur * inv_r2 * (b2 * inv_r2 * (1.0 - 1.65 * MASS_PARAM * inv_r) - 0.55 * MASS_PARAM * inv_r);

                    const vl_half = vl_cur + 0.5 * dlam * accel1;
                    l_cur += dlam * vl_half;

                    const r2_mid = B0 * B0 + 0.25 * (l_prev + l_cur) * (l_prev + l_cur);
                    const inv_r2_mid = 1.0 / r2_mid;
                    psi_cur += dlam * b * inv_r2_mid * (1.0 + 0.65 * MASS_PARAM * @sqrt(inv_r2_mid));

                    const r2_new = B0 * B0 + l_cur * l_cur;
                    const inv_r2_new = 1.0 / r2_new;
                    const inv_r_new = @sqrt(inv_r2_new);
                    const accel2 = l_cur * inv_r2_new * (b2 * inv_r2_new * (1.0 - 1.65 * MASS_PARAM * inv_r_new) - 0.55 * MASS_PARAM * inv_r_new);
                    vl_cur = vl_half + 0.5 * dlam * accel2;

                    if (@abs(l_cur) < min_abs_l) min_abs_l = @abs(l_cur);

                    // 3D unit vector on sphere at angle psi_cur:
                    const z_cur = @cos(psi_cur) * cam_rz + @sin(psi_cur) * epsi_z;

                    // Check equatorial plane crossing (z == 0):
                    if ((z_prev > 0.0 and z_cur <= 0.0) or (z_prev < 0.0 and z_cur >= 0.0)) {
                        const frac = math.clamp(@abs(z_prev) / (@abs(z_prev) + @abs(z_cur) + 1e-12), 0.0, 1.0);
                        const l_cross = l_prev + frac * (l_cur - l_prev);
                        const abs_l = @abs(l_cross);

                        if (abs_l <= DISK_MAX_L) {
                            const psi_cross = psi_prev + frac * (psi_cur - psi_prev);
                            const cos_p = @cos(psi_cross);
                            const sin_p = @sin(psi_cross);
                            const ux = cos_p * cam_rx + sin_p * epsi_x;
                            const uy = cos_p * cam_ry + sin_p * epsi_y;

                            var phi = math.atan2(uy, ux);
                            if (phi < 0.0) phi += 2.0 * math.pi;

                            const norm_r = math.clamp(abs_l / DISK_MAX_L, 0.0, 0.9999);
                            const r_idx: u32 = @intFromFloat(norm_r * @as(f64, @floatFromInt(RAD_BINS)));
                            const phi_idx: u32 = @as(u32, @intFromFloat((phi / (2.0 * math.pi)) * @as(f64, @floatFromInt(ANG_BINS)))) & @as(u32, ANG_BINS - 1);
                            const side_bit: u32 = if (l_cross < 0.0) 1 else 0;

                            const r_eff = @sqrt(B0 * B0 + l_cross * l_cross);
                            const v_orb = math.clamp(0.46 / @sqrt(@sqrt(r_eff)), 0.08, 0.55);
                            const gamma = 1.0 / @sqrt(1.0 - v_orb * v_orb);
                            const lz_over_e = b * (cam_rx * epsi_y - cam_ry * epsi_x);
                            const sign_rot: f64 = if (l_cross >= 0.0) 1.0 else -0.85;
                            const grav_redshift = @sqrt(1.0 - 0.30 / r_eff);
                            const doppler_denom = gamma * (1.0 - sign_rot * v_orb * (lz_over_e / r_eff));
                            const g_factor = math.clamp(grav_redshift / @max(0.35, doppler_denom), 0.45, 1.95);

                            if (!hit1) {
                                hit1 = true;
                                hit1_r_idx = r_idx;
                                hit1_side = side_bit;
                                hit1_phi_idx = phi_idx;
                                hit1_g = g_factor;
                            } else if (!hit2) {
                                hit2 = true;
                                hit2_r_idx = r_idx;
                                hit2_side = side_bit;
                                hit2_phi_idx = phi_idx;
                                hit2_g = g_factor;
                            }
                        }
                    }

                    z_prev = z_cur;
                    if (@abs(l_cur) > 10.5 and (l_cur * vl_cur > 0.0)) break;
                }

                // Asymptotic outgoing photon direction for background sky lookup (Universe A vs Universe B!):
                const in_universe_b = (l_cur < 0.0);
                const cos_pf = @cos(psi_cur);
                const sin_pf = @sin(psi_cur);
                const u_out_x = cos_pf * cam_rx + sin_pf * epsi_x;
                const u_out_y = cos_pf * cam_ry + sin_pf * epsi_y;
                const u_out_z = cos_pf * cam_rz + sin_pf * epsi_z;

                const du_x = -sin_pf * cam_rx + cos_pf * epsi_x;
                const du_y = -sin_pf * cam_ry + cos_pf * epsi_y;
                const du_z = -sin_pf * cam_rz + cos_pf * epsi_z;

                const r_final = @sqrt(B0 * B0 + l_cur * l_cur);
                const v_psi_final = b / r_final;
                const out_norm = 1.0 / @sqrt(@max(1e-9, vl_cur * vl_cur + v_psi_final * v_psi_final));
                const sign_l: f64 = if (l_cur >= 0.0) 1.0 else -1.0;
                const k_out_x = (vl_cur * sign_l * u_out_x + v_psi_final * du_x) * out_norm;
                const k_out_y = (vl_cur * sign_l * u_out_y + v_psi_final * du_y) * out_norm;
                const k_out_z = (vl_cur * sign_l * u_out_z + v_psi_final * du_z) * out_norm;

                const lensed_sky = sampleCelestialSky(k_out_x, k_out_y, k_out_z, in_universe_b);

                // Einstein ring & exotic wormhole throat photon-sphere resonance at b ~ b_crit:
                const throat_grazing = @exp(-14.0 * min_abs_l * min_abs_l) * @exp(-4.5 * @abs(b - 1.18));
                const portal_rim = @exp(-32.0 * (b - 1.15) * (b - 1.15));
                const ring_glow = math.clamp(0.85 * throat_grazing + 0.65 * portal_rim, 0.0, 1.0) * edge_fade;

                // Also record Universe B interior pixels (`in_universe_b`) as a dynamic secondary disk crossing
                // so the exotic Universe B vortex inside the wormhole throat swirls in real time!
                if (in_universe_b and !hit2) {
                    var phi_b = math.atan2(k_out_y, k_out_x);
                    if (phi_b < 0.0) phi_b += 2.0 * math.pi;
                    const r_b_norm = math.clamp(b / 1.18, 0.0, 0.999);
                    hit2 = true;
                    hit2_r_idx = @intFromFloat(r_b_norm * @as(f64, @floatFromInt(RAD_BINS)));
                    hit2_side = 1;
                    hit2_phi_idx = @as(u32, @intFromFloat((phi_b / (2.0 * math.pi)) * @as(f64, @floatFromInt(ANG_BINS)))) & @as(u32, ANG_BINS - 1);
                    hit2_g = 1.15 + 0.35 * k_out_y;
                }

                // Blend lensed sky with unlensed edge_fade near the bounding box border
                const bg_orig = self.bg_lut[y * self.w + x];
                const orig_r = @as(f64, @floatFromInt(bg_orig & 0xFF)) / 255.0;
                const orig_g = @as(f64, @floatFromInt((bg_orig >> 8) & 0xFF)) / 255.0;
                const orig_b = @as(f64, @floatFromInt((bg_orig >> 16) & 0xFF)) / 255.0;

                const final_bg_r = orig_r + edge_fade * (lensed_sky[0] - orig_r);
                const final_bg_g = orig_g + edge_fade * (lensed_sky[1] - orig_g);
                const final_bg_b = orig_b + edge_fade * (lensed_sky[2] - orig_b);

                const pr8: u8 = @intFromFloat(math.clamp(@round(final_bg_r * 255.0), 0.0, 255.0));
                const pg8: u8 = @intFromFloat(math.clamp(@round(final_bg_g * 255.0), 0.0, 255.0));
                const pb8: u8 = @intFromFloat(math.clamp(@round(final_bg_b * 255.0), 0.0, 255.0));
                self.portal_bg_lut[act_idx] = sdk.packRGBA(pr8, pg8, pb8);

                var flags: u32 = 0;
                if (hit1) flags |= 1;
                if (hit2) flags |= 2;

                const packed_coords: u32 =
                    (hit1_r_idx & 0x1FF) |
                    ((hit1_side & 1) << 9) |
                    ((hit2_r_idx & 0x1FF) << 10) |
                    ((hit2_side & 1) << 19) |
                    ((hit1_phi_idx & 0x3FF) << 20) |
                    ((flags & 3) << 30);

                // Quantize edge_fade into 6 bits (0..63)
                const fade6: u16 = @intFromFloat(math.clamp(@round(edge_fade * 63.0), 0.0, 63.0));
                const phi2_and_trans: u16 = @as(u16, @intCast(hit2_phi_idx & 0x3FF)) | (fade6 << 10);

                // Quantize primary Doppler factor g1 into 0..255
                const g1_norm = math.clamp((hit1_g - 0.35) / 1.80, 0.0, 1.0);
                const g1_q: u8 = @intFromFloat(@round(g1_norm * 255.0));

                // Pack 4 bits of secondary Doppler g2 + 4 bits of Einstein ring intensity into ring_and_g2
                const g2_norm = math.clamp((hit2_g - 0.35) / 1.80, 0.0, 1.0);
                const g2_q4: u8 = @intFromFloat(@round(g2_norm * 15.0));
                const ring_q4: u8 = @intFromFloat(@round(math.clamp(ring_glow, 0.0, 1.0) * 15.0));

                self.geodesic_lut[act_idx] = .{
                    .packed_coords = packed_coords,
                    .phi2_and_trans = phi2_and_trans,
                    .g1_quant = g1_q,
                    .ring_and_g2 = (g2_q4 << 4) | ring_q4,
                };
            }
        }

        // 3. Initialize symplectic relativistic plasma knots in both universes
        for (0..NUM_PARTICLES) |i| {
            const side: f32 = if ((i & 1) == 0) 1.0 else -1.0;
            const u_rand: f32 = @floatCast(randFloat(&rng));
            const l_mag = 0.25 + 4.2 * u_rand * u_rand;
            const l_val = side * l_mag;
            const r_eff = @sqrt(1.0 + l_val * l_val);
            const omega_kepler = side * (1.65 / math.pow(f32, r_eff, 1.35));

            self.knots[i] = .{
                .l_coord = l_val,
                .phi = @floatCast(randFloat(&rng) * 2.0 * math.pi),
                .omega = omega_kepler,
                .temp = @floatCast(0.65 + 0.95 * randFloat(&rng)),
                .size_inv = @floatCast(18.0 + 24.0 * randFloat(&rng)),
            };
        }

        // Perform initial step so frame 0 LUTs are populated
        self.step(0.0);
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    /// (t * freq) mod 2*pi, computed in f64 so the f32 result never loses precision.
    inline fn wrapPhase(t: f64, freq: f64) f32 {
        return @floatCast(@mod(t * freq, 2.0 * math.pi));
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        // Every time-driven angle is reduced mod 2*pi in f64 first, so f32 phases stay exact
        // after days of uptime instead of jittering as time_sec grows.
        const ts = self.time_sec;

        // 1. Evolve symplectic MHD plasma knots (infall + differential Keplerian shear + throat transit)
        const dt_f32: f32 = @floatCast(dt);
        for (&self.knots) |*k| {
            const r_eff = @sqrt(1.0 + k.l_coord * k.l_coord);
            const sign_rot: f32 = if (k.l_coord >= 0.0) 1.0 else -0.85;
            k.omega = sign_rot * (1.85 / (r_eff * @sqrt(r_eff)));
            k.phi = @mod(k.phi + k.omega * dt_f32, 2.0 * math.pi);
            if (k.phi < 0.0) k.phi += 2.0 * math.pi;

            // Gentle inward accretion drift through the wormhole throat from Universe A -> Universe B
            k.l_coord -= 0.18 * dt_f32 / r_eff;
            if (k.l_coord < -4.6) {
                k.l_coord += 9.2;
            }
        }

        // 2. Update 1D radial accretion profiles & logarithmic spiral wave phases (512 bins)
        // Shear winds the arms up to ~1.4 turns and back over about a minute.
        const shear: f32 = 9.0 * @sin(wrapPhase(ts, 0.105));
        self.rad_profile_a = @splat(0.0);
        self.rad_profile_b = @splat(0.0);

        for (0..RAD_BINS) |i| {
            const norm_r = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(RAD_BINS));
            const l_abs = norm_r * @as(f32, @floatCast(DISK_MAX_L));
            const r_eff = @sqrt(1.0 + l_abs * l_abs);

            // Page-Thorne inspired relativistic radial emissivity profile with inner throat peak
            // and smooth zero-taper at outer edge (norm_r -> 1):
            const inner_boost = 1.0 - 0.35 / @sqrt(r_eff);
            const om_r = 1.0 - norm_r;
            const outer_taper = @exp(-2.60 * norm_r * norm_r) * om_r * om_r;
            const radial_rings = 0.80 + 0.25 * @sin(24.0 * norm_r - wrapPhase(ts, 4.2)) * @cos(39.0 * norm_r + wrapPhase(ts, 2.9));

            self.rad_profile_a[i] = outer_taper * inner_boost * radial_rings;
            self.rad_profile_b[i] = (0.28 + 0.62 * outer_taper) * (0.82 + 0.32 * @cos(18.0 * norm_r - wrapPhase(ts, 4.8)));

            // Spiral arms turn as density waves: a rigid pattern speed plus a bounded,
            // breathing Keplerian shear. (A shear term of omega(r) * t winds the arms
            // tighter forever; after half a minute they alias into concentric moire rings.)
            const omega_loc = 2.65 / (r_eff * @sqrt(r_eff));
            const spiral_phase_a = 10.5 * @log(r_eff) - wrapPhase(ts, 2.1) + shear * omega_loc;
            self.spiral_sin_a[i] = @sin(spiral_phase_a);
            self.spiral_cos_a[i] = @cos(spiral_phase_a);

            const spiral_phase_b = -8.5 * @log(r_eff) + wrapPhase(ts, 1.8) - 0.9 * shear * omega_loc;
            self.spiral_sin_b[i] = @sin(spiral_phase_b);
            self.spiral_cos_b[i] = @cos(spiral_phase_b);
        }

        // 3. Update 1D azimuthal MHD turbulence harmonic tables (1024 bins)
        for (0..ANG_BINS) |j| {
            const phi = (@as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(ANG_BINS))) * (2.0 * math.pi);
            self.ang_wave_m2[j] = @sin(2.0 * phi - wrapPhase(ts, 3.20));
            self.ang_wave_m3[j] = @cos(3.0 * phi - wrapPhase(ts, 4.60) + 0.65 * @sin(phi + wrapPhase(ts, 1.8)));
            self.ang_wave_m5[j] = @sin(5.0 * phi - wrapPhase(ts, 6.80)) * @cos(2.0 * phi + wrapPhase(ts, 2.4));
        }

        // Deposit live symplectic plasma knot energy into both radial and azimuthal profiles!
        for (self.knots) |k| {
            const norm_r = @abs(k.l_coord) / @as(f32, @floatCast(DISK_MAX_L));
            if (norm_r < 0.92) {
                const center_bin: i32 = @intFromFloat(norm_r * @as(f32, @floatFromInt(RAD_BINS)));
                const phi_bin: usize = @as(usize, @intFromFloat((k.phi / (2.0 * math.pi)) * @as(f32, @floatFromInt(ANG_BINS)))) & (ANG_BINS - 1);
                self.ang_wave_m5[phi_bin] += 0.12 * k.temp;
                var db: i32 = -4;
                while (db <= 4) : (db += 1) {
                    const b_idx = center_bin + db;
                    if (b_idx >= 0 and b_idx < @as(i32, RAD_BINS)) {
                        const w_knot = 0.028 * k.temp * @exp(-0.25 * @as(f32, @floatFromInt(db * db)));
                        if (k.l_coord >= 0.0) {
                            self.rad_profile_a[@intCast(b_idx)] += w_knot;
                        } else {
                            self.rad_profile_b[@intCast(b_idx)] += w_knot;
                        }
                    }
                }
            }
        }
    }

    inline fn blendAddScaledRGB(base: u32, add: u32, scale64: u32) u32 {
        const r: u32 = @min(@as(u32, 255), (base & 0xFF) + (((add & 0xFF) * scale64) >> 6));
        const g: u32 = @min(@as(u32, 255), ((base >> 8) & 0xFF) + ((((add >> 8) & 0xFF) * scale64) >> 6));
        const b: u32 = @min(@as(u32, 255), ((base >> 16) & 0xFF) + ((((add >> 16) & 0xFF) * scale64) >> 6));
        return 0xFF000000 | (b << 16) | (g << 8) | r;
    }

    inline fn evaluateDiskSample(
        self: *const State,
        r_idx: u32,
        side: u32,
        phi_idx: u32,
        g_bin: u32,
    ) struct { color: u32, opacity: f32 } {
        const c_phi = self.ang_cos[phi_idx];
        const s_phi = self.ang_sin[phi_idx];
        const m2 = self.ang_wave_m2[phi_idx];
        const m3 = self.ang_wave_m3[phi_idx];
        const m5 = self.ang_wave_m5[phi_idx];

        // Relativistic Doppler beaming factor from g_bin (0..15), keeping receding side warmly visible:
        const g_val = 0.45 + (@as(f32, @floatFromInt(g_bin)) * (1.50 / 15.0));
        const g2 = g_val * g_val;
        const doppler_boost = math.clamp(0.30 + g2 * 0.58, 0.35, 1.95);

        if (side == 0) {
            // Universe A Accretion Disk (2-arm + 3-arm logarithmic spiral turbulence)
            const base_rad = self.rad_profile_a[r_idx];
            const sp_sin = self.spiral_sin_a[r_idx];
            const sp_cos = self.spiral_cos_a[r_idx];

            // Rotate spiral arm by 2*phi using double-angle trig identity:
            const cos_2phi = c_phi * c_phi - s_phi * s_phi;
            const sin_2phi = 2.0 * s_phi * c_phi;
            const spiral_2arm = sp_cos * cos_2phi - sp_sin * sin_2phi;

            const turb = 0.56 + 0.36 * spiral_2arm + 0.22 * m3 + 0.16 * m5 * sp_sin;
            const flux = base_rad * @max(0.08, turb) * doppler_boost;
            const i_bin: u32 = @intFromFloat(math.clamp(flux * 215.0, 0.0, 255.0));
            const color = self.color_lut_a[(g_bin << 8) | i_bin];
            const opacity = math.clamp(base_rad * 1.45, 0.0, 0.92);
            return .{ .color = color, .opacity = opacity };
        } else {
            // Universe B Accretion Disk (seen through the wormhole or lensed into caustic ring)
            const base_rad = self.rad_profile_b[r_idx];
            const sp_sin = self.spiral_sin_b[r_idx];
            const sp_cos = self.spiral_cos_b[r_idx];

            const spiral_1arm = sp_cos * c_phi + sp_sin * s_phi;
            const turb = 0.52 + 0.38 * spiral_1arm + 0.22 * m2 + 0.18 * m5;
            const flux = base_rad * @max(0.08, turb) * doppler_boost * 0.68;
            const i_bin: u32 = @intFromFloat(math.clamp(flux * 185.0, 0.0, 255.0));
            const color = self.color_lut_b[(g_bin << 8) | i_bin];
            const opacity = math.clamp(base_rad * 1.25, 0.0, 0.85);
            return .{ .color = color, .opacity = opacity };
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;

        // Step 1: Copy precomputed static deep-space background row-by-row respecting `stride`
        // (Guarantees Gate 3 Stride Canary integrity and Gate 4 0xFF alpha on every pixel)
        for (0..h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.bg_lut[y * w .. y * w + w];
            @memcpy(dst_row, src_row);
        }

        // Dynamic pulse for the exotic matter throat / Einstein ring
        const throat_pulse: u32 = @intFromFloat(9.0 + 4.0 * @sin(wrapPhase(self.time_sec, 3.4)));

        // Step 2: Render relativistic wormhole & accretion disk inside the active bounding box
        const act_h = @min(ACT_H, h - self.box_y0);
        const act_w = @min(ACT_W, w - self.box_x0);

        for (0..act_h) |by| {
            const y = self.box_y0 + by;
            const dst_row = buf[y * stride + self.box_x0 .. y * stride + self.box_x0 + act_w];
            const geo_row = self.geodesic_lut[by * ACT_W .. by * ACT_W + act_w];
            const pbg_row = self.portal_bg_lut[by * ACT_W .. by * ACT_W + act_w];

            for (0..act_w) |bx| {
                const gp = geo_row[bx];
                const pcoords = gp.packed_coords;
                const flags = pcoords >> 30;
                const ring_q4: u32 = gp.ring_and_g2 & 0x0F;
                const fade64: u32 = @as(u32, gp.phi2_and_trans >> 10) + 1;

                var pixel_col = pbg_row[bx];

                // If neither disk crossing nor Einstein ring glow is active, write lensed portal sky directly
                if (flags == 0 and ring_q4 == 0) {
                    dst_row[bx] = pixel_col;
                    continue;
                }

                // Secondary caustic / wormhole-interior disk crossing (rendered behind primary crossing)
                if ((flags & 2) != 0) {
                    const r2_idx = (pcoords >> 10) & 0x1FF;
                    const r2_side = (pcoords >> 19) & 1;
                    const phi2_idx: u32 = gp.phi2_and_trans & 0x3FF;
                    const g2_bin: u32 = gp.ring_and_g2 >> 4;

                    const s2 = self.evaluateDiskSample(r2_idx, r2_side, phi2_idx, g2_bin);
                    pixel_col = blendAddScaledRGB(pixel_col, s2.color, (fade64 * 3) >> 2);
                }

                // Primary accretion disk crossing (with semi-transparent optical depth occlusion of background)
                if ((flags & 1) != 0) {
                    const r1_idx = pcoords & 0x1FF;
                    const r1_side = (pcoords >> 9) & 1;
                    const phi1_idx = (pcoords >> 20) & 0x3FF;
                    const g1_bin: u32 = gp.g1_quant >> 4;

                    const s1 = self.evaluateDiskSample(r1_idx, r1_side, phi1_idx, g1_bin);

                    const eff_op = s1.opacity * (@as(f32, @floatFromInt(fade64)) / 64.0);
                    const trans_u32: u32 = @intFromFloat((1.0 - 0.65 * eff_op) * 256.0);
                    const br = ((pixel_col & 0xFF) * trans_u32) >> 8;
                    const bg = (((pixel_col >> 8) & 0xFF) * trans_u32) >> 8;
                    const bb = (((pixel_col >> 16) & 0xFF) * trans_u32) >> 8;
                    const atten_bg = 0xFF000000 | (bb << 16) | (bg << 8) | br;

                    pixel_col = blendAddScaledRGB(atten_bg, s1.color, fade64);
                }

                // Relativistic Einstein Ring & Exotic Wormhole Throat Caustic Glow
                if (ring_q4 > 0) {
                    const boost = (ring_q4 * throat_pulse * fade64) >> 6;
                    const rr: u32 = @min(@as(u32, 255), (pixel_col & 0xFF) + ((boost * 11) >> 4));
                    const rg: u32 = @min(@as(u32, 255), ((pixel_col >> 8) & 0xFF) + ((boost * 15) >> 4));
                    const rb: u32 = @min(@as(u32, 255), ((pixel_col >> 16) & 0xFF) + boost);
                    pixel_col = 0xFF000000 | (rb << 16) | (rg << 8) | rr;
                }

                dst_row[bx] = pixel_col;
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        if (math.isNan(self.time_sec) or math.isInf(self.time_sec)) return true;
        if (math.isNan(self.rad_profile_a[0]) or math.isInf(self.rad_profile_a[0])) return true;
        if (math.isNan(self.knots[0].l_coord) or math.isInf(self.knots[0].l_coord)) return true;
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

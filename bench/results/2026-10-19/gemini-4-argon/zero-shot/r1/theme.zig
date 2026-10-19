const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

pub const LENS_MAX_W: usize = 1280;
pub const LENS_MAX_H: usize = 580;
pub const LENS_CAP: usize = LENS_MAX_W * LENS_MAX_H;

pub const R_BINS: usize = 64;
pub const PHI_BINS: usize = 256;
pub const POLAR_CAP: usize = R_BINS * PHI_BINS;

pub const SIN_LUT_SIZE: usize = 1024;
pub const SIN_LUT_MASK: usize = SIN_LUT_SIZE - 1;

pub const NUM_PARTICLES: usize = 320;

pub const Particle = struct {
    r_orb: f32,
    phi: f32,
    omega: f32,
    z_off: f32,
    temp: u8,
    kind: u8, // 0 = prograde disk hotspot, 1 = photon-sphere skimmer, 2 = northern jet knot, 3 = southern jet knot
    size: u8,
    pad: u8,
};

pub const State = struct {
    w: usize,
    h: usize,
    box_w: usize,
    box_h: usize,
    box_x0: usize,
    box_y0: usize,
    scale: f64,
    time_sec: f64,

    // Precomputed static deep-space & steady-state relativistic continuum background (8.79 MiB)
    bg_lut: [MAX_PIXELS]u32,

    // Precomputed Kerr geodesic inverse-lensing lookup table for active singularity box (2.83 MiB)
    // Bit layout per u32 word:
    //   bits [0..7]   : phi_bin (0..255, observer-frame azimuthal angle)
    //   bits [8..13]  : r_bin   (0..63, 0..47 = primary disk, 48..55 = secondary lensed arch, 56..63 = polar jet)
    //   bits [14..22] : weight  (0..256, relativistic Doppler beaming g^4 * radial envelope * vignette)
    //   bits [23..31] : ring_w  (0..256, critical photon-sphere Lyapunov ring & Einstein caustic weight)
    lens_map: [LENS_CAP]u32,

    // Dynamic L1-cached polar emission table updated every step(dt) (64 KiB)
    polar_lut: [POLAR_CAP]u32,

    // Dynamic critical photon-ring flare table updated every step(dt) (1 KiB)
    ring_lut: [PHI_BINS]u32,

    // Fast trigonometric lookup table
    sin_lut: [SIN_LUT_SIZE]f32,

    // Full-screen separable gravitational-wave & magnetospheric tide tables
    row_glow: [MAX_H]u32,
    col_wave: [MAX_W]u32,

    // Lagrangian relativistic geodesic plasmoids & Blandford-Znajek jet knots
    particles: [NUM_PARTICLES]Particle,

    inline fn fastSin(self: *const State, rad: f32) f32 {
        const scaled: f32 = rad * (1024.0 / (2.0 * math.pi));
        const fl: f32 = @floor(scaled);
        const idx_i: i32 = @intFromFloat(fl);
        const idx_u: u32 = @bitCast(idx_i);
        const idx: usize = @as(usize, idx_u) & SIN_LUT_MASK;
        return self.sin_lut[idx];
    }

    inline fn fastCos(self: *const State, rad: f32) f32 {
        return self.fastSin(rad + 0.5 * math.pi);
    }

    inline fn hashU32(seed: u32) u32 {
        var x: u32 = seed ^ 0x9E3779B9;
        x ^= x >> 16;
        x *%= 0x7FEB352D;
        x ^= x >> 15;
        x *%= 0x846CA68B;
        x ^= x >> 16;
        return x;
    }

    inline fn blackbodyDopplerRGB(temp_norm: f64, doppler_g: f64, intensity: f64) u32 {
        const lum: f64 = math.clamp(intensity, 0.0, 1.0);
        if (lum <= 0.0005) return sdk.packRGBA(0, 0, 0);

        // Shift effective temperature by relativistic Doppler factor g = D * sqrt(1 - r_s/r)
        const t_eff: f64 = math.clamp(temp_norm * math.pow(f64, doppler_g, 0.85), 0.0, 2.2);

        // Relativistic accretion spectrum: deep crimson-amber (receding) -> gold-white -> electric cyan-blue (approaching)
        const r_f: f64 = math.clamp(lum * (0.95 * math.pow(f64, math.clamp(t_eff * 1.15, 0.0, 1.0), 0.70) + 0.25 * @max(0.0, t_eff - 1.0)), 0.0, 1.0);
        const g_f: f64 = math.clamp(lum * (0.88 * math.pow(f64, math.clamp(t_eff * 0.92, 0.0, 1.2), 1.25) + 0.20 * @max(0.0, t_eff - 1.1)), 0.0, 1.0);
        const b_f: f64 = math.clamp(lum * (0.72 * math.pow(f64, math.clamp(t_eff * 0.78, 0.0, 1.4), 2.10) + 0.45 * @max(0.0, t_eff - 0.95)), 0.0, 1.0);

        const r_u8: u8 = @intFromFloat(@round(r_f * 255.0));
        const g_u8: u8 = @intFromFloat(@round(g_f * 255.0));
        const b_u8: u8 = @intFromFloat(@round(b_f * 255.0));
        return sdk.packRGBA(r_u8, g_u8, b_u8);
    }

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;

        self.box_w = @min(LENS_MAX_W, (self.w * 2) / 3);
        self.box_h = @min(LENS_MAX_H, (self.h * 29) / 60);
        self.box_x0 = (self.w - self.box_w) / 2;
        self.box_y0 = (self.h - self.box_h) / 2;

        self.bg_lut = @splat(sdk.packRGBA(2, 4, 10));
        self.lens_map = @splat(0);
        self.polar_lut = @splat(sdk.packRGBA(0, 0, 0));
        self.ring_lut = @splat(sdk.packRGBA(0, 0, 0));
        self.row_glow = @splat(sdk.packRGBA(0, 0, 0));
        self.col_wave = @splat(128);

        for (0..SIN_LUT_SIZE) |idx| {
            const angle: f64 = (@as(f64, @floatFromInt(idx)) / @as(f64, @floatFromInt(SIN_LUT_SIZE))) * (2.0 * math.pi);
            self.sin_lut[idx] = @floatCast(@sin(angle));
        }

        const fw: f64 = @floatFromInt(@max(@as(usize, 1), self.w));
        const fh: f64 = @floatFromInt(@max(@as(usize, 1), self.h));
        const cx: f64 = 0.5 * fw;
        const cy: f64 = 0.5 * fh;
        const r_sh: f64 = 0.092 * @min(fw, fh);

        // Camera roll angle psi = -12.6 deg (-0.22 rad) for cinematic relativistic disk tilt
        const cos_psi: f64 = @cos(-0.22);
        const sin_psi: f64 = @sin(-0.22);

        // 1. Precompute deep-space relativistic nebula & molecular dust lanes across full frame
        for (0..self.h) |y| {
            const fy: f64 = (@as(f64, @floatFromInt(y)) - cy) / fh;
            for (0..self.w) |x| {
                const fx: f64 = (@as(f64, @floatFromInt(x)) - cx) / fw;

                // Rotate into galactic / accretion equatorial frame
                const gx: f64 = fx * cos_psi - fy * sin_psi;
                const gy: f64 = -(fx * sin_psi + fy * cos_psi);
                const rad_sq: f64 = gx * gx + 2.2 * gy * gy;

                // Multi-scale cosmic dust & ionized O-III / H-alpha veil using fast LUT
                const n1: f64 = @as(f64, self.fastSin(@floatCast(gx * 5.5 + gy * 3.2))) *
                    @as(f64, self.fastCos(@floatCast(gy * 6.8 - gx * 2.4)));
                const n2: f64 = @as(f64, self.fastSin(@floatCast(gx * 13.0 - gy * 9.5 + 1.2 * n1)));
                const band: f64 = @exp(-14.0 * gy * gy) * (0.55 + 0.45 * n1);
                const halo: f64 = @exp(-3.5 * rad_sq);

                const base_r: f64 = 3.0 + 14.0 * band * (0.6 + 0.4 * n2) + 18.0 * halo;
                const base_g: f64 = 5.0 + 18.0 * band + 26.0 * halo * (0.7 + 0.3 * n1);
                const base_b: f64 = 13.0 + 34.0 * band + 48.0 * halo;

                const r8: u8 = @intFromFloat(math.clamp(@round(base_r), 0.0, 255.0));
                const g8: u8 = @intFromFloat(math.clamp(@round(base_g), 0.0, 255.0));
                const b8: u8 = @intFromFloat(math.clamp(@round(base_b), 0.0, 255.0));
                self.bg_lut[y * self.w + x] = sdk.packRGBA(r8, g8, b8);
            }
        }

        // 2. Render 1,600 background stars with Einstein gravitational-lensing tangential shear
        const bg_canvas = sdk.Canvas.init(&self.bg_lut, self.w, self.h, self.w);
        const num_stars: usize = 1600;
        for (0..num_stars) |s_idx| {
            const h0: u32 = hashU32(@as(u32, @intCast(s_idx)) *% 747796405 +% 2891336453);
            const h1: u32 = hashU32(h0 ^ 0xA53C9E47);
            const h2: u32 = hashU32(h1 ^ 0x5F356495);

            const sx_f: f64 = (@as(f64, @floatFromInt(h0 & 0xFFFF)) / 65535.0) * fw;
            const sy_f: f64 = (@as(f64, @floatFromInt(h1 & 0xFFFF)) / 65535.0) * fh;

            const dx_s: f64 = (sx_f - cx) / r_sh;
            const dy_s: f64 = (sy_f - cy) / r_sh;
            const b_star: f64 = @sqrt(@max(0.0, dx_s * dx_s + dy_s * dy_s));

            // Exclude stars inside the Einstein shadow capture zone; shear stars near Einstein ring b ~ 1.4..2.8
            if (b_star < 1.15) continue;

            const temp_pick: u32 = h2 & 0xFF;
            const star_bright: f64 = 0.25 + 0.75 * math.pow(f64, @as(f64, @floatFromInt((h2 >> 8) & 0xFF)) / 255.0, 2.4);

            var sr: u8 = 210;
            var sg: u8 = 225;
            var sb: u8 = 255;
            if (temp_pick < 55) {
                // Warm K/M giant star
                sr = @intFromFloat(@round(255.0 * star_bright));
                sg = @intFromFloat(@round(175.0 * star_bright));
                sb = @intFromFloat(@round(110.0 * star_bright));
            } else if (temp_pick < 150) {
                // Solar F/G star
                sr = @intFromFloat(@round(245.0 * star_bright));
                sg = @intFromFloat(@round(235.0 * star_bright));
                sb = @intFromFloat(@round(215.0 * star_bright));
            } else {
                // Hot O/B blue-white star
                sr = @intFromFloat(@round(175.0 * star_bright));
                sg = @intFromFloat(@round(215.0 * star_bright));
                sb = @intFromFloat(@round(255.0 * star_bright));
            }

            const star_col = sdk.packRGBA(sr, sg, sb);
            const ix: isize = @intFromFloat(@floor(sx_f));
            const iy: isize = @intFromFloat(@floor(sy_f));
            bg_canvas.addSigned(ix, iy, star_col);

            // Tangential Einstein-lensing arc stretch near the photon sphere (1.15 <= b_star < 2.8)
            if (b_star < 2.8) {
                const tx: f64 = -dy_s / @max(0.001, b_star);
                const ty: f64 = dx_s / @max(0.001, b_star);
                const arc_col = sdk.scaleRGB(star_col, 150);
                const ix_p: isize = @intFromFloat(@floor(sx_f + tx * 1.4));
                const iy_p: isize = @intFromFloat(@floor(sy_f + ty * 1.4));
                const ix_m: isize = @intFromFloat(@floor(sx_f - tx * 1.4));
                const iy_m: isize = @intFromFloat(@floor(sy_f - ty * 1.4));
                bg_canvas.addSigned(ix_p, iy_p, arc_col);
                bg_canvas.addSigned(ix_m, iy_m, arc_col);
            } else if ((h2 & 0x3F) == 0) {
                // Subtle Airy diffraction cross on brightest distant stars
                const halo_col = sdk.scaleRGB(star_col, 95);
                bg_canvas.addSigned(ix + 1, iy, halo_col);
                bg_canvas.addSigned(ix - 1, iy, halo_col);
                bg_canvas.addSigned(ix, iy + 1, halo_col);
                bg_canvas.addSigned(ix, iy - 1, halo_col);
            }
        }

        // 3. Solve exact relativistic Kerr null-geodesic lensing across the active region
        const bw = self.box_w;
        const bh = self.box_h;
        const bx0 = self.box_x0;
        const by0 = self.box_y0;
        const f_bw: f64 = @floatFromInt(@max(@as(usize, 1), bw));
        const f_bh: f64 = @floatFromInt(@max(@as(usize, 1), bh));

        for (0..bh) |ly| {
            const y = by0 + ly;
            const dy: f64 = (@as(f64, @floatFromInt(y)) - cy) / r_sh;
            // Normalized elliptical coordinate inside the active bounding box [-1..1] for seamless vignette
            const ny_box: f64 = (@as(f64, @floatFromInt(ly)) - 0.5 * f_bh) / (0.5 * f_bh);

            for (0..bw) |lx| {
                const x = bx0 + lx;
                const dx: f64 = (@as(f64, @floatFromInt(x)) - cx) / r_sh;
                const nx_box: f64 = (@as(f64, @floatFromInt(lx)) - 0.5 * f_bw) / (0.5 * f_bw);

                // Smooth elliptical window that reaches strictly 0.0 before the bounding box border
                const box_r2: f64 = nx_box * nx_box + ny_box * ny_box;
                if (box_r2 >= 0.98) continue;
                const vignette: f64 = math.pow(f64, math.clamp((0.98 - box_r2) / 0.32, 0.0, 1.0), 1.6);

                // Bardeen screen coordinates (alpha along disk major axis, beta along spin axis)
                const alpha: f64 = dx * cos_psi - dy * sin_psi;
                const beta: f64 = -(dx * sin_psi + dy * cos_psi);

                // Kerr spin a/M = 0.94 shifts shadow center by +0.15 and flattens prograde edge (alpha < 0)
                const alpha_c: f64 = alpha - 0.15;
                const prograde_flat: f64 = 1.0 + 0.09 * math.tanh(-1.65 * alpha_c);
                const b: f64 = @sqrt(@max(0.0, (alpha_c * prograde_flat) * (alpha_c * prograde_flat) + beta * beta));

                // Smoothly transition inclination foreshortening from cos(78 deg)=0.208 in front of the
                // black hole (beta < 0) to bent face-on arch (mu_eff ~ 0.85) behind the black hole (beta > 0)
                const beta_norm: f64 = beta / (b + 0.14);
                const pos_beta: f64 = 0.5 * (beta_norm + @sqrt(beta_norm * beta_norm + 0.015));
                const mu_eff: f64 = 0.208 + 0.74 * (pos_beta / (1.0 + 0.17 * b * b));

                const z_disk: f64 = beta / mu_eff;
                const x_disk: f64 = alpha;
                const r_disk: f64 = @sqrt(@max(0.0, x_disk * x_disk + z_disk * z_disk));

                // Determine whether the foreground disk bridge (beta < 0, r_disk >= r_ISCO) occludes the shadow
                const r_isco: f64 = 0.90;
                const r_out: f64 = 5.15;
                const front_bridge: f64 = math.clamp((-beta - 0.14) / 0.10, 0.0, 1.0) *
                    math.clamp((r_disk - r_isco) / 0.12, 0.0, 1.0);

                // Event horizon shadow capture for rays behind the front bridge with b < 0.99
                const shadow_mask: f64 = math.clamp((b - 0.975) / 0.045, 0.0, 1.0);
                const transmission: f64 = @max(front_bridge, shadow_mask);

                // Darken background starfield/nebula inside the black hole silhouette
                if (b < 1.04) {
                    const bg_keep: f64 = shadow_mask * (1.0 - 0.85 * front_bridge);
                    const keep_256: u32 = @intFromFloat(math.clamp(@round(bg_keep * 256.0), 0.0, 256.0));
                    const dark_void = sdk.packRGBA(1, 2, 5);
                    self.bg_lut[y * self.w + x] = sdk.lerpRGB(dark_void, self.bg_lut[y * self.w + x], keep_256);
                }

                // --- Component A: Primary Relativistic Accretion Disk (r_disk in [r_isco .. r_out]) ---
                var disk_env: f64 = 0.0;
                var doppler_g: f64 = 1.0;
                var phi_disk: f64 = 0.0;
                if (r_disk >= r_isco and r_disk <= r_out and transmission > 0.01) {
                    const inner_turn: f64 = math.clamp((r_disk - r_isco) / 0.24, 0.0, 1.0);
                    const outer_fade: f64 = math.pow(f64, math.clamp((r_out - r_disk) / (r_out - r_isco), 0.0, 1.0), 1.55);
                    // Novikov-Thorne radial emissivity profile peaking near 1.45 * r_isco
                    const nt_flux: f64 = inner_turn * inner_turn * outer_fade * @exp(-0.28 * (r_disk - r_isco));
                    disk_env = nt_flux * transmission;

                    // Relativistic Keplerian orbital speed & Doppler factor D = 1 / [gamma * (1 - v_los)]
                    const v_orb: f64 = 0.56 / @sqrt(@max(0.25, r_disk));
                    const sin_phi_los: f64 = -x_disk / @max(0.15, r_disk); // +1 on approaching left side (alpha < 0)
                    const v_los: f64 = v_orb * 0.978 * sin_phi_los;
                    const gamma_inv: f64 = @sqrt(@max(0.08, 1.0 - v_orb * v_orb));
                    const grav_red: f64 = @sqrt(@max(0.15, 1.0 - 0.52 / @max(0.60, r_disk)));
                    doppler_g = (grav_red * gamma_inv) / @max(0.22, 1.0 - v_los);

                    // Azimuthal angle in disk plane + logarithmic Kerr frame-dragging spiral twist
                    const raw_phi: f64 = math.atan2(z_disk, x_disk);
                    const twist: f64 = 2.15 * @log(@max(0.85, r_disk)) - 0.85 / @max(0.45, r_disk - 0.40);
                    phi_disk = raw_phi + twist;
                }

                // --- Component B: Secondary Gravitationally Lensed Image (n = 1 Lower Cradle Arch) ---
                var sec_env: f64 = 0.0;
                var phi_sec: f64 = 0.0;
                var doppler_sec: f64 = 1.0;
                if (b >= 0.97 and b <= 1.55 and beta < 0.25) {
                    const south_gate: f64 = math.clamp((0.22 - beta) / 0.35, 0.0, 1.0);
                    const arch_profile: f64 = @exp(-((b - 1.13) * (b - 1.13)) / (2.0 * 0.095 * 0.095));
                    // Attenuate secondary arch where the opaque front bridge crosses directly over it
                    sec_env = arch_profile * south_gate * (1.0 - 0.72 * front_bridge);

                    const v_sec: f64 = 0.48;
                    const sin_los_sec: f64 = -alpha_c / @max(0.25, b);
                    doppler_sec = 0.78 / @max(0.30, 1.0 - v_sec * sin_los_sec);
                    phi_sec = math.atan2(-beta, -alpha_c) + 1.65 / @max(0.18, b - 0.82);
                }

                // --- Component C: Critical Photon Ring (n >= 2 Lyapunov Curve at b = 1.005) ---
                const ring_narrow: f64 = @exp(-((b - 1.005) * (b - 1.005)) / (2.0 * 0.021 * 0.021));
                const ring_halo: f64 = 0.32 * @exp(-((b - 1.035) * (b - 1.035)) / (2.0 * 0.055 * 0.055));
                const ring_beam: f64 = 0.58 + 0.42 * math.tanh(-1.35 * alpha_c + 0.22);
                const ring_occlusion: f64 = 1.0 - 0.55 * front_bridge;
                const ring_total: f64 = (ring_narrow + ring_halo) * ring_beam * ring_occlusion * vignette;

                // --- Component D: Twin Relativistic Blandford-Znajek Helical Jets ---
                var jet_env: f64 = 0.0;
                var jet_phi: f64 = 0.0;
                var jet_z_norm: f64 = 0.0;
                const abs_beta: f64 = @abs(beta);
                if (abs_beta >= 0.72 and b >= 0.96) {
                    const z_j: f64 = abs_beta - 0.65;
                    const jet_half_w: f64 = 0.11 + 0.16 * math.pow(f64, z_j, 0.65);
                    const u_perp: f64 = alpha_c / @max(0.05, jet_half_w);
                    if (@abs(u_perp) < 1.85) {
                        // Limb-brightened magnetized paraboloidal sheath + central Poynting spine
                        const sheath: f64 = @exp(-((@abs(u_perp) - 0.68) * (@abs(u_perp) - 0.68)) / (2.0 * 0.28 * 0.28));
                        const spine: f64 = 0.65 * @exp(-(u_perp * u_perp) / (2.0 * 0.22 * 0.22));
                        const z_taper: f64 = math.clamp((abs_beta - 0.72) / 0.35, 0.0, 1.0) * @exp(-0.55 * z_j);
                        // Relativistic beaming favors the approaching northern jet slightly
                        const jet_beam: f64 = if (beta > 0.0) 1.18 else 0.82;
                        jet_env = (sheath + spine) * z_taper * jet_beam * (1.0 - 0.85 * disk_env);
                        jet_z_norm = math.clamp(z_j / 2.2, 0.0, 0.999);
                        jet_phi = u_perp * 1.6 + (if (beta > 0.0) @as(f64, 0.0) else math.pi) + 3.2 * z_j;
                    }
                }

                // Bake steady-state relativistic continuum emission directly into bg_lut (48% continuum base)
                const disk_beamed: f64 = disk_env * math.pow(f64, doppler_g, 2.6) * vignette;
                const sec_beamed: f64 = sec_env * math.pow(f64, doppler_sec, 2.2) * vignette;
                const jet_beamed: f64 = jet_env * vignette;

                if (disk_beamed > 0.002 or sec_beamed > 0.002 or ring_total > 0.002 or jet_beamed > 0.002) {
                    const temp_disk: f64 = math.pow(f64, math.clamp((r_out - r_disk) / (r_out - r_isco), 0.0, 1.0), 0.45);
                    const c_disk = blackbodyDopplerRGB(temp_disk, doppler_g, 0.48 * disk_beamed);
                    const c_sec = blackbodyDopplerRGB(0.82, doppler_sec, 0.46 * sec_beamed);
                    const c_ring = blackbodyDopplerRGB(1.08, 0.95 + 0.40 * ring_beam, 0.54 * ring_total);

                    // Synchrotron sapphire-violet-cyan color for relativistic polar jets
                    const jr: u8 = @intFromFloat(math.clamp(@round(jet_beamed * 75.0), 0.0, 255.0));
                    const jg: u8 = @intFromFloat(math.clamp(@round(jet_beamed * 145.0), 0.0, 255.0));
                    const jb: u8 = @intFromFloat(math.clamp(@round(jet_beamed * 250.0), 0.0, 255.0));
                    const c_jet = sdk.packRGBA(jr, jg, jb);

                    const combined_static = sdk.addRGB(sdk.addRGB(c_disk, c_sec), sdk.addRGB(c_ring, c_jet));
                    self.bg_lut[y * self.w + x] = sdk.addRGB(self.bg_lut[y * self.w + x], combined_static);
                }

                // Pack dominant dynamic zone into lens_map[ly * bw + lx] for fast L1-cached per-frame animation
                var r_bin: u32 = 0;
                var phi_angle: f64 = 0.0;
                var dyn_weight_f: f64 = 0.0;

                if (disk_beamed >= sec_beamed and disk_beamed >= jet_beamed and disk_beamed > 0.003) {
                    // Zone 0..47: Primary relativistic accretion disk
                    const r_norm: f64 = math.clamp((r_disk - r_isco) / (r_out - r_isco), 0.0, 0.999);
                    // Square-root mapping concentrates radial resolution near the inner ISCO & photon sphere
                    const r_sqrt: f64 = @sqrt(@max(0.0, r_norm));
                    r_bin = @intFromFloat(@floor(r_sqrt * 47.99));
                    phi_angle = phi_disk;
                    dyn_weight_f = math.clamp(disk_beamed * 1.35, 0.0, 1.0);
                } else if (sec_beamed >= jet_beamed and sec_beamed > 0.003) {
                    // Zone 48..55: Secondary gravitationally lensed arch (n = 1)
                    const s_norm: f64 = math.clamp((b - 0.97) / 0.58, 0.0, 0.999);
                    const s_bin: u32 = @intFromFloat(@floor(s_norm * 7.99));
                    r_bin = 48 + s_bin;
                    phi_angle = phi_sec;
                    dyn_weight_f = math.clamp(sec_beamed * 1.30, 0.0, 1.0);
                } else if (jet_beamed > 0.003) {
                    // Zone 56..63: Relativistic Blandford-Znajek helical polar jets
                    const j_bin: u32 = @intFromFloat(@floor(jet_z_norm * 7.99));
                    r_bin = 56 + j_bin;
                    phi_angle = jet_phi;
                    dyn_weight_f = math.clamp(jet_beamed * 1.40, 0.0, 1.0);
                } else if (ring_total > 0.004) {
                    phi_angle = math.atan2(beta, alpha_c);
                }

                const weight_u32: u32 = @intFromFloat(math.clamp(@round(dyn_weight_f * 256.0), 0.0, 256.0));
                const ring_u32: u32 = @intFromFloat(math.clamp(@round(math.clamp(ring_total * 1.25, 0.0, 1.0) * 256.0), 0.0, 256.0));

                if (weight_u32 > 0 or ring_u32 > 0) {
                    const phi_wrapped: f64 = phi_angle / (2.0 * math.pi);
                    const phi_frac: f64 = phi_wrapped - @floor(phi_wrapped);
                    const phi_bin: u32 = @as(u32, @intFromFloat(@floor(phi_frac * 256.0))) & 0xFF;

                    const packed_code: u32 = phi_bin |
                        ((r_bin & 0x3F) << 8) |
                        ((weight_u32 & 0x1FF) << 14) |
                        ((ring_u32 & 0x1FF) << 23);
                    self.lens_map[ly * bw + lx] = packed_code;
                }
            }
        }

        // 4. Initialize 320 Lagrangian relativistic plasmoids & polar jet knots
        for (0..NUM_PARTICLES) |p_idx| {
            const h_a: u32 = hashU32(@as(u32, @intCast(p_idx)) *% 1103515245 +% 12345);
            const h_b: u32 = hashU32(h_a ^ 0xC6BC2796);
            const u_r: f32 = @as(f32, @floatFromInt(h_a & 0xFFFF)) / 65535.0;
            const u_phi: f32 = (@as(f32, @floatFromInt((h_a >> 16) & 0xFFFF)) / 65535.0) * (2.0 * math.pi);

            const kind_sel: u32 = p_idx % 8;
            if (kind_sel < 5) {
                // Prograde Keplerian accretion disk hotspot
                const r_val: f32 = 0.96 + 3.85 * (u_r * u_r);
                const omega_val: f32 = 3.6 / (math.pow(f32, r_val, 1.5) + 0.94);
                self.particles[p_idx] = Particle{
                    .r_orb = r_val,
                    .phi = u_phi,
                    .omega = omega_val,
                    .z_off = (@as(f32, @floatFromInt(h_b & 0xFF)) / 255.0 - 0.5) * 0.08,
                    .temp = @intCast((h_b >> 8) & 0xFF),
                    .kind = 0,
                    .size = if ((h_b & 3) == 0) 2 else 1,
                    .pad = 0,
                };
            } else if (kind_sel == 5) {
                // Photon-sphere Lyapunov orbit skimmer (b ~ 1.01)
                self.particles[p_idx] = Particle{
                    .r_orb = 1.005 + 0.04 * u_r,
                    .phi = u_phi,
                    .omega = 3.2 + 0.8 * u_r,
                    .z_off = 0.0,
                    .temp = 240,
                    .kind = 1,
                    .size = 1,
                    .pad = 0,
                };
            } else {
                // Relativistic Blandford-Znajek jet knot (kind 2 = north, kind 3 = south)
                const is_north: u8 = if (kind_sel == 6) 2 else 3;
                self.particles[p_idx] = Particle{
                    .r_orb = 0.78 + 2.4 * u_r, // distance along jet axis
                    .phi = u_phi, // helical magnetic phase
                    .omega = 1.65 + 0.55 * u_r, // outward superluminal propagation speed
                    .z_off = (@as(f32, @floatFromInt(h_b & 0xFF)) / 255.0 - 0.5) * 0.14,
                    .temp = @intCast(180 + ((h_b >> 8) & 0x3F)),
                    .kind = is_north,
                    .size = if ((h_b & 3) == 0) 2 else 1,
                    .pad = 0,
                };
            }
        }

        // Populate initial tables so draw() is ready even before step()
        self.updateDynamicTables();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn updateDynamicTables(self: *State) void {
        const t: f32 = @floatCast(self.time_sec);
        const fh: f32 = @floatFromInt(@max(@as(usize, 1), self.h));
        const fw: f32 = @floatFromInt(@max(@as(usize, 1), self.w));

        // 1. Update full-screen separable gravitational-wave & magnetospheric veil tables
        // Attenuate near the equatorial shadow center (ny ~ 0) so the event horizon stays abyssal black
        for (0..self.h) |y| {
            const ny: f32 = (@as(f32, @floatFromInt(y)) - 0.5 * fh) / (0.5 * fh);
            const shadow_guard: f32 = math.clamp((@abs(ny) - 0.12) / 0.35, 0.0, 1.0);
            const w1: f32 = self.fastSin(ny * 7.5 - t * 3.4);
            const w2: f32 = self.fastCos(ny * 13.0 + t * 2.7);
            const wave: f32 = (0.5 + 0.5 * (0.65 * w1 + 0.35 * w2)) * (0.35 + 0.65 * shadow_guard);

            const r_g: u8 = @intFromFloat(@round(wave * 7.0));
            const g_g: u8 = @intFromFloat(@round(wave * 15.0));
            const b_g: u8 = @intFromFloat(@round(wave * 28.0));
            self.row_glow[y] = sdk.packRGBA(r_g, g_g, b_g);
        }

        for (0..self.w) |x| {
            const nx: f32 = (@as(f32, @floatFromInt(x)) - 0.5 * fw) / (0.5 * fw);
            const cw: f32 = 0.5 + 0.5 * self.fastSin(nx * 9.0 - t * 3.1);
            const c_scale: u32 = @intFromFloat(@round(140.0 + 115.0 * cw));
            self.col_wave[x] = c_scale;
        }

        // 2. Update L1-cached polar emission table polar_lut[64 * 256]
        // Zones 0..47: Primary relativistic accretion disk with differential Kerr rotation
        for (0..48) |r_bin| {
            const r_sqrt: f32 = @as(f32, @floatFromInt(r_bin)) / 47.0;
            const r_norm: f32 = r_sqrt * r_sqrt;
            const r_phys: f32 = 0.90 + r_norm * (5.15 - 0.90);

            // Relativistic Kerr orbital frequency Omega(r) = C / (r^(3/2) + a)
            const omega_r: f32 = 4.2 / (math.pow(f32, r_phys, 1.35) + 0.94);
            const rot_phase: f32 = omega_r * t;
            const radial_pulse: f32 = self.fastSin(r_sqrt * 16.0 - t * 3.6);
            const temp_base: f32 = math.pow(f32, 1.0 - 0.72 * r_sqrt, 0.55);

            const row_offset: usize = r_bin * PHI_BINS;
            for (0..PHI_BINS) |phi_bin| {
                const phi: f32 = (@as(f32, @floatFromInt(phi_bin)) / 256.0) * (2.0 * math.pi);
                const phi_rot: f32 = phi - rot_phase;

                // Multi-mode m=2, m=3, m=5 spiral density waves + MRI turbulence filaments
                const m2: f32 = self.fastSin(2.0 * phi_rot + r_sqrt * 7.5);
                const m3: f32 = self.fastCos(3.0 * phi_rot - r_sqrt * 11.0 + t * 1.4);
                const m5: f32 = self.fastSin(5.0 * phi_rot + r_sqrt * 18.0 - t * 2.2);
                const m8: f32 = self.fastCos(8.0 * phi_rot - r_sqrt * 25.0 + 0.8 * m2);

                const turb: f32 = 0.52 + 0.24 * m2 + 0.16 * m3 + 0.12 * m5 + 0.08 * m8 + 0.10 * radial_pulse;
                const intensity: f32 = math.clamp(turb, 0.08, 1.35);

                // Observer-frame Doppler shift: cos(phi - twist) distinguishes approaching vs receding limb
                const approx_cos: f32 = -self.fastCos(phi - 1.35 * r_sqrt);
                const doppler_mod: f32 = 1.0 + 0.38 * approx_cos + 0.12 * m3;
                const t_color: f32 = math.clamp(temp_base * doppler_mod, 0.15, 1.85);

                const r_f: f32 = math.clamp(intensity * (0.96 * math.clamp(t_color * 1.25, 0.0, 1.0) + 0.22 * @max(0.0, t_color - 1.0)), 0.0, 1.0);
                const g_f: f32 = math.clamp(intensity * (0.86 * math.clamp(t_color * 0.92, 0.0, 1.1) * math.clamp(t_color * 0.92, 0.0, 1.1) + 0.25 * @max(0.0, t_color - 1.05)), 0.0, 1.0);
                const b_f: f32 = math.clamp(intensity * (0.68 * math.pow(f32, math.clamp(t_color * 0.78, 0.0, 1.2), 2.1) + 0.48 * @max(0.0, t_color - 0.90)), 0.0, 1.0);

                const r8: u8 = @intFromFloat(@round(r_f * 255.0));
                const g8: u8 = @intFromFloat(@round(g_f * 255.0));
                const b8: u8 = @intFromFloat(@round(b_f * 255.0));
                self.polar_lut[row_offset + phi_bin] = sdk.packRGBA(r8, g8, b8);
            }
        }

        // Zones 48..55: Secondary gravitationally lensed arch (n = 1 caustics)
        for (48..56) |r_bin| {
            const s_norm: f32 = @as(f32, @floatFromInt(r_bin - 48)) / 7.0;
            const omega_s: f32 = 3.5 - 1.1 * s_norm;
            const row_offset: usize = r_bin * PHI_BINS;
            for (0..PHI_BINS) |phi_bin| {
                const phi: f32 = (@as(f32, @floatFromInt(phi_bin)) / 256.0) * (2.0 * math.pi);
                const w_a: f32 = self.fastSin(3.0 * (phi - omega_s * t) + s_norm * 9.0);
                const w_b: f32 = self.fastCos(5.0 * (phi + 0.7 * omega_s * t) - s_norm * 14.0);
                const lum: f32 = math.clamp(0.55 + 0.30 * w_a + 0.20 * w_b, 0.10, 1.0);

                const r8: u8 = @intFromFloat(@round(lum * 250.0));
                const g8: u8 = @intFromFloat(@round(lum * 195.0));
                const b8: u8 = @intFromFloat(@round(lum * 135.0));
                self.polar_lut[row_offset + phi_bin] = sdk.packRGBA(r8, g8, b8);
            }
        }

        // Zones 56..63: Relativistic Blandford-Znajek helical polar jets
        for (56..64) |r_bin| {
            const j_norm: f32 = @as(f32, @floatFromInt(r_bin - 56)) / 7.0;
            const row_offset: usize = r_bin * PHI_BINS;
            for (0..PHI_BINS) |phi_bin| {
                const phi: f32 = (@as(f32, @floatFromInt(phi_bin)) / 256.0) * (2.0 * math.pi);
                // Outward-propagating Alfvénic double helix + superluminal shock knots
                const helix1: f32 = self.fastSin(2.0 * phi - j_norm * 12.0 + t * 4.2);
                const helix2: f32 = self.fastCos(4.0 * phi + j_norm * 18.0 - t * 3.5);
                const knot: f32 = math.clamp(0.58 + 0.28 * helix1 + 0.22 * helix2, 0.08, 1.0);

                const r8: u8 = @intFromFloat(@round(knot * 115.0));
                const g8: u8 = @intFromFloat(@round(knot * 195.0));
                const b8: u8 = @intFromFloat(@round(knot * 255.0));
                self.polar_lut[row_offset + phi_bin] = sdk.packRGBA(r8, g8, b8);
            }
        }

        // 3. Update critical photon-ring Lyapunov flare LUT ring_lut[256]
        for (0..PHI_BINS) |phi_bin| {
            const phi: f32 = (@as(f32, @floatFromInt(phi_bin)) / 256.0) * (2.0 * math.pi);
            const f1: f32 = self.fastSin(2.0 * phi - t * 3.8);
            const f2: f32 = self.fastCos(3.0 * phi + t * 2.9);
            const f3: f32 = self.fastSin(7.0 * phi - t * 5.1);
            const ring_lum: f32 = math.clamp(0.62 + 0.22 * f1 + 0.16 * f2 + 0.12 * f3, 0.15, 1.0);

            const r8: u8 = @intFromFloat(@round(ring_lum * 255.0));
            const g8: u8 = @intFromFloat(@round(ring_lum * 232.0));
            const b8: u8 = @intFromFloat(@round(ring_lum * 195.0));
            self.ring_lut[phi_bin] = sdk.packRGBA(r8, g8, b8);
        }
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const dt_f: f32 = @floatCast(dt);

        // Advance Lagrangian relativistic geodesic particles & jet knots
        for (&self.particles) |*p| {
            if (p.kind <= 1) {
                p.phi += p.omega * dt_f;
                if (p.phi > 2.0 * math.pi) p.phi -= 2.0 * math.pi;
            } else {
                p.r_orb += p.omega * dt_f;
                p.phi += 2.8 * dt_f;
                if (p.phi > 2.0 * math.pi) p.phi -= 2.0 * math.pi;
                if (p.r_orb > 3.18) {
                    p.r_orb = 0.78 + @mod(p.r_orb - 0.78, 2.40);
                }
            }
        }

        self.updateDynamicTables();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;

        // Pass 1: Full-screen background starfield + nebula + separable magnetospheric wave shimmer
        for (0..h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.bg_lut[y * w .. y * w + w];
            const rg = self.row_glow[y];
            for (dst_row, src_row, 0..) |*dst, src, x| {
                const mod_glow = sdk.scaleRGB(rg, self.col_wave[x]);
                dst.* = sdk.addRGB(src, mod_glow);
            }
        }

        // Pass 2: Relativistic Kerr singularity, warped accretion disk, secondary arch, photon ring & polar jets
        const bw = self.box_w;
        const bh = self.box_h;
        const bx0 = self.box_x0;
        const by0 = self.box_y0;

        for (0..bh) |ly| {
            const y = by0 + ly;
            const dst_row = buf[y * stride + bx0 .. y * stride + bx0 + bw];
            const lens_row = self.lens_map[ly * bw .. ly * bw + bw];
            for (dst_row, lens_row) |*dst, code| {
                if (code != 0) {
                    const polar_idx: usize = @intCast(code & 0x3FFF);
                    const weight: u32 = (code >> 14) & 0x1FF;
                    const ring_w: u32 = code >> 23;
                    const phi_idx: usize = polar_idx & 0xFF;

                    const disk_col = sdk.scaleRGB(self.polar_lut[polar_idx], weight);
                    const ring_col = sdk.scaleRGB(self.ring_lut[phi_idx], ring_w);
                    dst.* = sdk.addRGB(dst.*, sdk.addRGB(disk_col, ring_col));
                }
            }
        }

        // Pass 3: Lagrangian relativistic plasmoids, photon-sphere skimmers & jet synchrotron knots
        const canvas = sdk.Canvas.init(buf, w, h, stride);
        const fw: f32 = @floatFromInt(@max(@as(usize, 1), w));
        const fh: f32 = @floatFromInt(@max(@as(usize, 1), h));
        const cx: f32 = 0.5 * fw;
        const cy: f32 = 0.5 * fh;
        const r_sh: f32 = 0.092 * @min(fw, fh);

        const cos_psi: f32 = @floatCast(@cos(-0.22));
        const sin_psi: f32 = @floatCast(@sin(-0.22));

        for (&self.particles) |*p| {
            var alpha: f32 = 0.0;
            var beta: f32 = 0.0;
            var p_col: u32 = sdk.packRGBA(0, 0, 0);

            if (p.kind == 0) {
                // Equatorial accretion disk plasmoid mapped through Kerr gravitational bending
                const x_d: f32 = p.r_orb * self.fastCos(p.phi);
                const z_d: f32 = p.r_orb * self.fastSin(p.phi);

                alpha = x_d;
                if (z_d >= 0.0) {
                    // Far side of disk arches above the northern hemisphere of the black hole shadow
                    const bend: f32 = 0.208 + 0.66 / (1.0 + 0.18 * p.r_orb * p.r_orb);
                    beta = z_d * bend + p.z_off;
                } else {
                    // Near side of disk crosses in front of the southern waist
                    beta = z_d * 0.208 + p.z_off;
                }

                const b_p: f32 = @sqrt(@max(0.0, (alpha - 0.15) * (alpha - 0.15) + beta * beta));
                if (z_d > 0.0 and b_p < 1.02) continue;

                // Relativistic Doppler beaming boosts approaching plasmoids (x_d < 0)
                const doppler: f32 = math.clamp(1.0 - 0.45 * (x_d / @max(0.5, p.r_orb)), 0.35, 1.65);
                if (x_d < 0.0) {
                    const cr: u8 = @intFromFloat(math.clamp(@round(135.0 * doppler), 0.0, 255.0));
                    const cg: u8 = @intFromFloat(math.clamp(@round(170.0 * doppler), 0.0, 255.0));
                    const cb: u8 = @intFromFloat(math.clamp(@round(210.0 * doppler), 0.0, 255.0));
                    p_col = sdk.packRGBA(cr, cg, cb);
                } else {
                    const cr: u8 = @intFromFloat(math.clamp(@round(190.0 * doppler), 0.0, 255.0));
                    const cg: u8 = @intFromFloat(math.clamp(@round(115.0 * doppler), 0.0, 255.0));
                    const cb: u8 = @intFromFloat(math.clamp(@round(65.0 * doppler), 0.0, 255.0));
                    p_col = sdk.packRGBA(cr, cg, cb);
                }
            } else if (p.kind == 1) {
                // Photon-sphere skimmer orbiting along the asymmetric critical curve
                alpha = 0.15 + p.r_orb * self.fastCos(p.phi);
                beta = p.r_orb * self.fastSin(p.phi);
                p_col = sdk.packRGBA(220, 195, 150);
            } else {
                // Helical Blandford-Znajek jet knot
                const sign_b: f32 = if (p.kind == 2) 1.0 else -1.0;
                const z_j: f32 = p.r_orb - 0.65;
                const jet_w: f32 = 0.09 + 0.13 * z_j;
                alpha = 0.15 + jet_w * self.fastCos(p.phi) + p.z_off;
                beta = sign_b * p.r_orb;
                const fade: f32 = math.clamp((3.2 - p.r_orb) / 2.2, 0.15, 1.0);
                const jr: u8 = @intFromFloat(@round(95.0 * fade));
                const jg: u8 = @intFromFloat(@round(175.0 * fade));
                const jb: u8 = @intFromFloat(@round(245.0 * fade));
                p_col = sdk.packRGBA(jr, jg, jb);
            }

            // Unrotate from Bardeen (alpha, beta) back to screen pixel coordinates (sx, sy)
            const sx: f32 = cx + (alpha * cos_psi - beta * sin_psi) * r_sh;
            const sy: f32 = cy - (alpha * sin_psi + beta * cos_psi) * r_sh;

            const ix: isize = @intFromFloat(@floor(sx));
            const iy: isize = @intFromFloat(@floor(sy));

            canvas.addSigned(ix, iy, p_col);
            const halo_col = sdk.scaleRGB(p_col, 110);
            canvas.addSigned(ix + 1, iy, halo_col);
            canvas.addSigned(ix - 1, iy, halo_col);
            canvas.addSigned(ix, iy + 1, halo_col);
            canvas.addSigned(ix, iy - 1, halo_col);

            if (p.size > 1) {
                const outer_col = sdk.scaleRGB(p_col, 55);
                canvas.addSigned(ix + 1, iy + 1, outer_col);
                canvas.addSigned(ix - 1, iy + 1, outer_col);
                canvas.addSigned(ix + 1, iy - 1, outer_col);
                canvas.addSigned(ix - 1, iy - 1, outer_col);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec) or
            math.isNan(self.scale) or math.isInf(self.scale);
    }
};

comptime {
    sdk.exportTheme(State);
}

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

pub const HALF_W: usize = 960;
pub const HALF_H: usize = 600;
pub const HALF_PIXELS: usize = HALF_W * HALF_H;

pub const NR: usize = 128;
pub const NPHI: usize = 128;
pub const POLAR_CELLS: usize = NR * NPHI;

pub const SIN_LUT_SIZE: usize = 4096;
pub const SIN_LUT_MASK: usize = SIN_LUT_SIZE - 1;

pub const NUM_PARTICLES: usize = 256;

pub const JetParticle = struct {
    z_pos: f32,
    radius_base: f32,
    phase: f32,
    omega: f32,
    speed: f32,
    temp_idx: u16,
    hemisphere: f32,
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    step_count: u32,
    energy_metric: f64,

    // Precomputed full-resolution static deep-space & gravitational-lensed starfield (8.79 MiB)
    bg_lut: [MAX_PIXELS]u32,

    // Half-resolution relativistic null-geodesic lookup tables (1.65 MiB total)
    // geodesic_lut packs (r_bin << 7) | phi_bin in 0..16383
    geodesic_lut: [HALF_PIXELS]u16,
    // beam_lut stores the relativistic Doppler beaming & gravitational redshift weight (0..255)
    beam_lut: [HALF_PIXELS]u8,

    // Live 2D polar Gross-Pitaevskii / relativistic MHD accretion disk PDE fields (256 KiB)
    psi_re: [POLAR_CELLS]f32,
    psi_im: [POLAR_CELLS]f32,
    scratch_re: [POLAR_CELLS]f32,
    scratch_im: [POLAR_CELLS]f32,
    omega_kepler: [NR]f32,
    polar_lut: [POLAR_CELLS]u32,

    // Fast 1D harmonic tables & blackbody/synchrotron palettes
    sin_lut: [SIN_LUT_SIZE]f32,
    palette_disk: [1024]u32,
    palette_jet: [1024]u32,
    col_dither: [MAX_W]u16,
    row_dither: [MAX_H]u16,

    // Relativistic Blandford-Znajek Poynting jet plasmoids
    particles: [NUM_PARTICLES]JetParticle,

    inline fn fastSin(self: *const State, angle_rad: f32) f32 {
        const scaled: f32 = angle_rad * (4096.0 / (2.0 * math.pi));
        const idx_i32: i32 = @intFromFloat(@floor(scaled));
        const idx_u32: u32 = @bitCast(idx_i32);
        const lut_idx: usize = @intCast(idx_u32 & @as(u32, SIN_LUT_MASK));
        return self.sin_lut[lut_idx];
    }

    inline fn fastCos(self: *const State, angle_rad: f32) f32 {
        return self.fastSin(angle_rad + 0.5 * math.pi);
    }

    inline fn hash2D(ix: u32, iy: u32) u32 {
        var h_val: u32 = ix *% 374761393 +% iy *% 668265263;
        h_val = (h_val ^ (h_val >> 13)) *% 1274126177;
        return h_val ^ (h_val >> 16);
    }

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.step_count = 0;
        self.energy_metric = 1.0;

        // 1. Build trigonometric LUT
        for (0..SIN_LUT_SIZE) |i| {
            const fi: f64 = @floatFromInt(i);
            const ang: f64 = fi * (2.0 * math.pi / @as(f64, @floatFromInt(SIN_LUT_SIZE)));
            self.sin_lut[i] = @floatCast(@sin(ang));
        }

        // 2. Build relativistic blackbody disk palette & synchrotron jet palette
        for (0..1024) |i| {
            const fi: f32 = @floatFromInt(i);
            const t: f32 = fi / 1023.0;
            const t2: f32 = t * t;
            const t3: f32 = t2 * t;

            // Blackbody accretion palette: deep crimson -> glowing amber -> Doppler blue-white
            const dr_f: f32 = math.clamp(255.0 * (1.65 * t - 0.65 * t3), 0.0, 255.0);
            const dg_f: f32 = math.clamp(255.0 * (1.25 * t2 + 0.15 * t), 0.0, 255.0);
            const db_f: f32 = math.clamp(255.0 * (0.20 * t + 0.85 * t3 * t), 0.0, 255.0);
            const dr: u8 = @intFromFloat(dr_f);
            const dg: u8 = @intFromFloat(dg_f);
            const db: u8 = @intFromFloat(db_f);
            self.palette_disk[i] = sdk.packRGBA(dr, dg, db);

            // Synchrotron Poynting jet palette: deep violet -> electric cyan -> Cherenkov white
            const jr_f: f32 = math.clamp(255.0 * (0.45 * t + 0.55 * t3), 0.0, 255.0);
            const jg_f: f32 = math.clamp(255.0 * (1.15 * t2), 0.0, 255.0);
            const jb_f: f32 = math.clamp(255.0 * (1.50 * t - 0.50 * t2), 0.0, 255.0);
            const jr: u8 = @intFromFloat(jr_f);
            const jg: u8 = @intFromFloat(jg_f);
            const jb: u8 = @intFromFloat(jb_f);
            self.palette_jet[i] = sdk.packRGBA(jr, jg, jb);
        }

        // 3. Initialize Keplerian relativistic angular velocity and initial complex superfluid state
        for (0..NR) |ir| {
            const fr: f32 = @floatFromInt(ir);
            const r_phys: f32 = 2.2 + fr * 0.28; // in units of GM/c^2 (Kerr ISCO ~ 2.0M)
            const r_pow: f32 = r_phys * @sqrt(@max(0.01, r_phys));
            self.omega_kepler[ir] = 18.0 / (r_pow + 0.94);

            const radial_env: f32 = @exp(-0.022 * @max(0.0, fr - 10.0)) * (1.0 - @exp(-0.18 * fr));
            for (0..NPHI) |iphi| {
                const fphi: f32 = @floatFromInt(iphi);
                const phi: f32 = fphi * (2.0 * math.pi / @as(f32, @floatFromInt(NPHI)));
                const spiral_phase: f32 = 2.0 * phi - 0.24 * fr;
                const m3_phase: f32 = 3.0 * phi + 0.15 * fr;
                const h_noise: u32 = hash2D(@intCast(ir), @intCast(iphi));
                const noise_f: f32 = @as(f32, @floatFromInt(h_noise & 1023)) * (1.0 / 1024.0) - 0.5;

                const amp: f32 = radial_env * (0.68 + 0.24 * @cos(spiral_phase) + 0.14 * @sin(m3_phase) + 0.12 * noise_f);
                const phase0: f32 = spiral_phase + 0.35 * @sin(m3_phase);
                const idx: usize = ir * NPHI + iphi;
                self.psi_re[idx] = amp * @cos(phase0);
                self.psi_im[idx] = amp * @sin(phase0);
                self.scratch_re[idx] = 0.0;
                self.scratch_im[idx] = 0.0;
                self.polar_lut[idx] = sdk.packRGBA(0, 0, 0);
            }
        }

        // 4. Initialize sub-block dither tables
        for (0..MAX_W) |x| {
            const ux: u32 = @intCast(x);
            self.col_dither[x] = @intCast(ux & 1);
        }
        for (0..MAX_H) |y| {
            const uy: u32 = @intCast(y);
            self.row_dither[y] = @intCast((uy & 1) << 1);
        }

        // 5. Initialize relativistic Blandford-Znajek jet plasmoid particles
        for (0..NUM_PARTICLES) |i| {
            const ui: u32 = @intCast(i);
            const h1: u32 = hash2D(ui, 0x9E3779B9);
            const h2: u32 = hash2D(ui, 0x85EBCA6B);
            const f1: f32 = @as(f32, @floatFromInt(h1 & 4095)) / 4096.0;
            const f2: f32 = @as(f32, @floatFromInt(h2 & 4095)) / 4096.0;
            const f3: f32 = @as(f32, @floatFromInt((h1 >> 12) & 4095)) / 4096.0;
            const hemi: f32 = if ((ui & 1) == 0) 1.0 else -1.0;

            self.particles[i] = JetParticle{
                .z_pos = f1,
                .radius_base = 0.015 + 0.055 * f2,
                .phase = f3 * 2.0 * math.pi,
                .omega = 4.5 + 5.0 * f2,
                .speed = 0.35 + 0.55 * f3,
                .temp_idx = @intCast(320 + (h2 & 703)),
                .hemisphere = hemi,
            };
        }

        // 6. Precompute full-screen static background & half-res Kerr null-geodesic tables
        self.bg_lut = @splat(sdk.packRGBA(3, 5, 12));
        self.geodesic_lut = @splat(0);
        self.beam_lut = @splat(0);

        const fw: f64 = @floatFromInt(@max(@as(usize, 1), self.w));
        const fh: f64 = @floatFromInt(@max(@as(usize, 1), self.h));
        const cx: f64 = 0.5 * fw;
        const cy: f64 = 0.5 * fh;
        const min_dim: f64 = @min(fw, fh);
        const inv_scale: f64 = 22.0 / @max(1.0, min_dim);

        // Camera inclination theta_0 = 74 deg (cos_i = 0.2756, sin_i = 0.9613)
        // Tilt angle in screen plane = -16 deg for dynamic asymmetric presentation
        const cos_tilt: f64 = 0.9612616959;
        const sin_tilt: f64 = -0.2756373558;
        const cos_inc: f64 = 0.2756373558;
        const sin_inc: f64 = 0.9612616959;
        const b_crit: f64 = 5.1961524227; // 3 * sqrt(3) M photon sphere critical impact parameter

        for (0..self.h) |y| {
            const fy: f64 = @floatFromInt(y);
            const dy_raw: f64 = (fy - cy) * inv_scale;

            for (0..self.w) |x| {
                const fx: f64 = @floatFromInt(x);
                const dx_raw: f64 = (fx - cx) * inv_scale;

                // Rotate into black hole equatorial screen frame (alpha, beta)
                const alpha: f64 = dx_raw * cos_tilt - dy_raw * sin_tilt;
                const beta: f64 = dx_raw * sin_tilt + dy_raw * cos_tilt;

                // Frame-dragging horizontal shift of the Kerr shadow (+0.38 M)
                const alpha_kerr: f64 = alpha - 0.38;
                const b_sq: f64 = alpha_kerr * alpha_kerr + beta * beta;
                const b_imp: f64 = @sqrt(@max(1.0e-6, b_sq));

                // Deep space background gradient + gravitational-lensed starfield
                const rad_norm: f64 = math.clamp(b_imp / 18.0, 0.0, 1.0);
                var bg_r: f64 = 4.0 + 10.0 * (1.0 - rad_norm);
                var bg_g: f64 = 6.0 + 14.0 * (1.0 - rad_norm);
                var bg_b: f64 = 15.0 + 28.0 * (1.0 - rad_norm);

                // Einstein gravitational deflection of background star coordinates outside shadow
                if (b_imp > b_crit * 0.92) {
                    const deflect: f64 = 1.0 - (b_crit * 0.82) / @max(b_crit * 0.85, b_imp);
                    const sx_f: f64 = (alpha * deflect + 40.0) * 18.0;
                    const sy_f: f64 = (beta * deflect + 40.0) * 18.0;
                    const cell_x: i32 = @intFromFloat(@floor(sx_f));
                    const cell_y: i32 = @intFromFloat(@floor(sy_f));
                    const frac_x: f64 = sx_f - @floor(sx_f) - 0.5;
                    const frac_y: f64 = sy_f - @floor(sy_f) - 0.5;
                    const star_h: u32 = hash2D(@bitCast(cell_x), @bitCast(cell_y));

                    if ((star_h & 127) == 0) {
                        const dist2: f64 = frac_x * frac_x + frac_y * frac_y;
                        const star_lum: f64 = @exp(-dist2 * 28.0) * @as(f64, @floatFromInt((star_h >> 8) & 255)) / 255.0;
                        bg_r += star_lum * 190.0;
                        bg_g += star_lum * 205.0;
                        bg_b += star_lum * 245.0;
                    }

                    // Photon-ring crisp razor-thin relativistic caustic at b == b_crit
                    const d_ring: f64 = (b_imp - b_crit) / 0.22;
                    const ring_glow: f64 = @exp(-0.5 * d_ring * d_ring);
                    const doppler_ring: f64 = 1.0 - 0.42 * (alpha_kerr / @max(1.0, b_imp));
                    const ring_int: f64 = ring_glow * doppler_ring;
                    bg_r += ring_int * 235.0;
                    bg_g += ring_int * 175.0;
                    bg_b += ring_int * 120.0;
                } else {
                    // Inside event horizon shadow: attenuate background to deep abyssal black
                    const shadow_fade: f64 = @exp(-math.pow(f64, (b_crit - b_imp) * 1.4, 2.0));
                    bg_r *= shadow_fade * 0.25;
                    bg_g *= shadow_fade * 0.25;
                    bg_b *= shadow_fade * 0.30;
                }

                const pr: u8 = @intFromFloat(math.clamp(bg_r, 0.0, 255.0));
                const pg: u8 = @intFromFloat(math.clamp(bg_g, 0.0, 255.0));
                const pb: u8 = @intFromFloat(math.clamp(bg_b, 0.0, 255.0));
                self.bg_lut[y * self.w + x] = sdk.packRGBA(pr, pg, pb);

                // Populate half-resolution geodesic LUT once per 2x2 block
                if ((x & 1) == 0 and (y & 1) == 0) {
                    const hx: usize = x >> 1;
                    const hy: usize = y >> 1;
                    if (hx < HALF_W and hy < HALF_H) {
                        // Primary inclined equatorial disk coordinate (with gravitational bending over the top/bottom)
                        const bend_lens: f64 = 1.0 + 2.65 / (1.0 + 0.09 * b_sq);
                        const y_eq: f64 = (beta / cos_inc) / bend_lens;
                        const x_eq: f64 = alpha;
                        const r_primary: f64 = @sqrt(x_eq * x_eq + y_eq * y_eq);

                        // Secondary lensed halo arch near the photon ring (b ~ b_crit)
                        const b_diff: f64 = @abs(b_imp - b_crit);
                        const r_halo: f64 = 2.4 + b_diff * 3.8;
                        const halo_weight: f64 = @exp(-b_diff * 1.35);

                        // Blend primary equatorial ray and secondary lensed arch
                        const use_halo: bool = (r_primary < 2.2 or (halo_weight > 0.32 and beta > -1.2));
                        const r_eff: f64 = if (use_halo) r_halo else r_primary;
                        const phi_raw: f64 = if (use_halo)
                            math.atan2(beta, alpha_kerr)
                        else
                            math.atan2(y_eq, x_eq);

                        const r_norm: f64 = math.clamp((r_eff - 2.2) / (0.28 * @as(f64, @floatFromInt(NR))), 0.0, 0.999);
                        const phi_norm: f64 = @mod(phi_raw + 2.0 * math.pi, 2.0 * math.pi) / (2.0 * math.pi);

                        const r_bin: u16 = @intFromFloat(r_norm * @as(f64, @floatFromInt(NR)));
                        const phi_bin: u16 = @intFromFloat(phi_norm * @as(f64, @floatFromInt(NPHI)));
                        const packed_geo: u16 = ((r_bin & 127) << 7) | (phi_bin & 127);

                        // Compute relativistic Doppler factor D = 1 / (gamma * (1 - beta_orb * sin_inc * cos_phi))
                        const v_orb: f64 = 1.0 / @sqrt(@max(1.8, r_eff));
                        const cos_phi_sky: f64 = -alpha / @max(0.5, b_imp);
                        const doppler: f64 = math.clamp(1.0 + 0.85 * v_orb * sin_inc * cos_phi_sky, 0.25, 2.25);
                        const doppler_boost: f64 = math.pow(f64, doppler, 2.4);

                        // Radial disk profile + shadow cutoff
                        var disk_vis: f64 = 0.0;
                        if (r_eff >= 2.15) {
                            const inner_taper: f64 = 1.0 - @exp(-0.9 * (r_eff - 2.15));
                            const outer_taper: f64 = 0.14 + 0.86 * @exp(-0.075 * @max(0.0, r_eff - 3.2));
                            disk_vis = inner_taper * outer_taper * doppler_boost;
                        }
                        // Suppress foreground inside inner shadow unless on the front crossing equatorial band
                        if (b_imp < b_crit * 0.86 and @abs(beta) > 1.35) {
                            disk_vis *= 0.08;
                        }

                        const beam_u8: u8 = @intFromFloat(math.clamp(disk_vis * 155.0, 12.0, 255.0));
                        self.geodesic_lut[hy * HALF_W + hx] = packed_geo;
                        self.beam_lut[hy * HALF_W + hx] = beam_u8;
                    }
                }
            }
        }

        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        const dt_clamped: f64 = math.clamp(dt, 0.0001, 0.05);
        self.time_sec += dt_clamped;
        self.step_count +%= 1;

        const dt_f: f32 = @floatCast(dt_clamped);
        const t_f: f32 = @floatCast(self.time_sec);

        // 1. Evolve 2D polar Gross-Pitaevskii / relativistic MHD turbulence PDE on (NR x NPHI)
        for (0..NR) |ir| {
            const ir_prev: usize = if (ir > 0) ir - 1 else 0;
            const ir_next: usize = if (ir + 1 < NR) ir + 1 else NR - 1;
            const omega: f32 = self.omega_kepler[ir];
            const fr: f32 = @floatFromInt(ir);
            const radial_target: f32 = @exp(-0.018 * @max(0.0, fr - 8.0)) * (1.0 - @exp(-0.22 * (fr + 1.0)));

            for (0..NPHI) |iphi| {
                const ip_prev: usize = (iphi + NPHI - 1) & (NPHI - 1);
                const ip_next: usize = (iphi + 1) & (NPHI - 1);
                const idx: usize = ir * NPHI + iphi;

                const re_c: f32 = self.psi_re[idx];
                const im_c: f32 = self.psi_im[idx];

                // Discrete polar Laplacian + azimuthal Upwind/Central Keplerian advection
                const lap_re: f32 = 0.25 * (self.psi_re[ir_prev * NPHI + iphi] +
                    self.psi_re[ir_next * NPHI + iphi] +
                    self.psi_re[ir * NPHI + ip_prev] +
                    self.psi_re[ir * NPHI + ip_next]) - re_c;
                const lap_im: f32 = 0.25 * (self.psi_im[ir_prev * NPHI + iphi] +
                    self.psi_im[ir_next * NPHI + iphi] +
                    self.psi_im[ir * NPHI + ip_prev] +
                    self.psi_im[ir * NPHI + ip_next]) - im_c;

                const dphi_re: f32 = 0.5 * (self.psi_re[ir * NPHI + ip_next] - self.psi_re[ir * NPHI + ip_prev]);
                const dphi_im: f32 = 0.5 * (self.psi_im[ir * NPHI + ip_next] - self.psi_im[ir * NPHI + ip_prev]);

                // Gross-Pitaevskii cubic nonlinearity + spiral MHD dynamo forcing
                const rho: f32 = re_c * re_c + im_c * im_c;
                const nonlin: f32 = 2.8 * (radial_target * radial_target - rho);

                const fphi: f32 = @floatFromInt(iphi);
                const spiral_arg: f32 = fphi * (4.0 * math.pi / @as(f32, @floatFromInt(NPHI))) - 0.26 * fr - t_f * 3.4;
                const force_re: f32 = 0.45 * radial_target * self.fastCos(spiral_arg);
                const force_im: f32 = 0.45 * radial_target * self.fastSin(spiral_arg);

                // Symplectic-like update with dispersive wave coupling (-i * lap) and Keplerian shear
                const next_re: f32 = re_c + dt_f * (-omega * dphi_re - 1.8 * lap_im + nonlin * re_c + 0.8 * lap_re + force_re);
                const next_im: f32 = im_c + dt_f * (-omega * dphi_im + 1.8 * lap_re + nonlin * im_c + 0.8 * lap_im + force_im);

                self.scratch_re[idx] = math.clamp(next_re, -2.5, 2.5);
                self.scratch_im[idx] = math.clamp(next_im, -2.5, 2.5);
            }
        }

        // 2. Commit PDE state and bake 16,384-entry polar color LUT for O(1) per-pixel lookup
        var total_energy: f64 = 0.0;
        for (0..NR) |ir| {
            const fr: f32 = @floatFromInt(ir);
            const omega: f32 = self.omega_kepler[ir];
            const rot_shift: f32 = t_f * omega * 2.2;

            for (0..NPHI) |iphi| {
                const idx: usize = ir * NPHI + iphi;
                const re_v: f32 = self.scratch_re[idx];
                const im_v: f32 = self.scratch_im[idx];
                self.psi_re[idx] = re_v;
                self.psi_im[idx] = im_v;

                const density: f32 = re_v * re_v + im_v * im_v;
                total_energy += @as(f64, density);

                const fphi: f32 = @floatFromInt(iphi);
                const wave_caustic: f32 = 0.5 + 0.5 * self.fastSin(fphi * 0.2454369 + rot_shift - fr * 0.31);
                const wave_fine: f32 = 0.5 + 0.5 * self.fastCos(fphi * 0.7363107 - rot_shift * 1.4 + fr * 0.52);

                const intensity: f32 = math.clamp(0.48 * density + 0.34 * wave_caustic + 0.22 * wave_fine * density, 0.0, 1.0);
                const pal_idx: usize = @intFromFloat(intensity * 1023.0);
                const base_col: u32 = self.palette_disk[pal_idx];

                // Add magnetic reconnection / synchrotron flare filaments near inner Kerr ergosphere
                if (ir < 28) {
                    const erg_w: u32 = @intFromFloat(math.clamp((28.0 - fr) * 6.5 * wave_fine, 0.0, 220.0));
                    const jet_col: u32 = sdk.scaleRGB(self.palette_jet[pal_idx], erg_w);
                    self.polar_lut[idx] = sdk.addRGB(base_col, jet_col);
                } else {
                    self.polar_lut[idx] = base_col;
                }
            }
        }
        self.energy_metric = total_energy;

        // 3. Advance sub-block phase dither and relativistic Blandford-Znajek jet plasmoids
        const phase_tick: u16 = @intCast(self.step_count & 127);
        for (0..self.w) |x| {
            const ux: u16 = @intCast(x & 3);
            self.col_dither[x] = (ux +% phase_tick) & 127;
        }

        for (0..NUM_PARTICLES) |i| {
            var p = &self.particles[i];
            p.z_pos += p.speed * dt_f;
            if (p.z_pos >= 1.0) {
                p.z_pos -= 1.0;
            }
            p.phase += p.omega * dt_f;
            if (p.phase > 200.0 * math.pi) {
                p.phase -= 200.0 * math.pi;
            }
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w: usize = self.w;
        const h: usize = self.h;

        // 1. Fast full-screen relativistic geodesic + MHD accretion caustic pass
        for (0..h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const bg_row = self.bg_lut[y * w .. y * w + w];
            const hy: usize = @min(y >> 1, HALF_H - 1);
            const geo_row = self.geodesic_lut[hy * HALF_W .. hy * HALF_W + HALF_W];
            const beam_row = self.beam_lut[hy * HALF_W .. hy * HALF_W + HALF_W];
            const r_dith: u16 = self.row_dither[y];

            for (0..w) |x| {
                const hx: usize = x >> 1;
                const packed_geo: u16 = geo_row[hx];
                const beam: u32 = beam_row[hx];
                const c_dith: u16 = self.col_dither[x];

                // Keep radial bin [13:7] intact while rotating/dithering azimuthal bin [6:0]
                const r_bits: u16 = packed_geo & 0x3F80;
                const phi_bits: u16 = (packed_geo +% c_dith +% r_dith) & 0x007F;
                const p_idx: usize = @intCast(r_bits | phi_bits);

                const dyn_col: u32 = sdk.scaleRGB(self.polar_lut[p_idx], beam);
                dst_row[x] = sdk.addRGB(bg_row[x], dyn_col);
            }
        }

        // 2. Render relativistic Blandford-Znajek helical Poynting jets via bounds-safe sdk.Canvas
        const canvas = sdk.Canvas.init(buf, w, h, stride);
        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);
        const cx: f32 = 0.5 * fw;
        const cy: f32 = 0.5 * fh;
        const min_dim: f32 = @min(fw, fh);

        // Jet axis aligned with spin axis (perpendicular to -16 deg tilted equatorial plane)
        const cos_tilt: f32 = 0.9612617;
        const sin_tilt: f32 = -0.2756374;

        for (0..NUM_PARTICLES) |i| {
            const p = self.particles[i];
            const z_dist: f32 = 0.04 + 0.46 * p.z_pos;
            const collim_r: f32 = p.radius_base * @sqrt(p.z_pos + 0.05);
            const helix_x: f32 = collim_r * self.fastCos(p.phase);
            const helix_y: f32 = p.hemisphere * z_dist;

            // Project from black hole spin frame to screen space
            const scr_dx: f32 = (helix_x * cos_tilt + helix_y * sin_tilt) * min_dim;
            const scr_dy: f32 = (-helix_x * sin_tilt + helix_y * cos_tilt) * min_dim;

            const px: isize = @intFromFloat(cx + scr_dx);
            const py: isize = @intFromFloat(cy + scr_dy);

            const env: f32 = (1.0 - p.z_pos) * @min(1.0, p.z_pos * 8.0);
            const weight: u32 = @intFromFloat(math.clamp(env * 240.0, 0.0, 255.0));
            const core_col: u32 = sdk.scaleRGB(self.palette_jet[p.temp_idx & 1023], weight);
            const halo_col: u32 = sdk.scaleRGB(core_col, 110);

            canvas.addSigned(px, py, core_col);
            canvas.addSigned(px - 1, py, halo_col);
            canvas.addSigned(px + 1, py, halo_col);
            canvas.addSigned(px, py - 1, halo_col);
            canvas.addSigned(px, py + 1, halo_col);
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec) or
            math.isNan(self.energy_metric) or math.isInf(self.energy_metric);
    }
};

comptime {
    sdk.exportTheme(State);
}

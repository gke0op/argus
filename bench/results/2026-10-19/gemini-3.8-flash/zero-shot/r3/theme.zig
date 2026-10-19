const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

pub const NUM_HOTSPOTS: usize = 32;
pub const NUM_STARS: usize = 128;
pub const NUM_JET_KNOTS: usize = 6;

pub const Hotspot = struct {
    r_norm: f32,
    phi: f32,
    omega: f32,
    size_px: f32,
    base_r: u8,
    base_g: u8,
    base_b: u8,
};

pub const Star = struct {
    base_x: f32,
    base_y: f32,
    brightness: f32,
    r: u8,
    g: u8,
    b: u8,
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,

    // Precomputed static general-relativistic background (Luminet-Page-Thorne metric)
    bg_lut: [MAX_PIXELS]u32,

    // Dynamic row spacetime ripples and jet shockwaves
    row_wave: [MAX_H]u32,

    // Orbiting relativistic plasma clumps
    hotspots: [NUM_HOTSPOTS]Hotspot,

    // Relativistic jet shock knots
    jet_knots_y: [NUM_JET_KNOTS]f32,
    jet_knots_speed: [NUM_JET_KNOTS]f32,

    // Gravitationally lensed background stars
    stars: [NUM_STARS]Star,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.row_wave = @splat(sdk.packRGBA(0, 0, 0));
        @memset(&self.bg_lut, sdk.packRGBA(0, 0, 0));

        const fw: f32 = @floatFromInt(self.w);
        const fh: f32 = @floatFromInt(self.h);
        const cx: f32 = fw * 0.5;
        const cy: f32 = fh * 0.52;
        const base_dim: f32 = @min(fw, fh);
        const rg: f32 = base_dim * 0.052; // Gravitational radius

        // 1. Initialize background stars with pseudo-random spectral classes
        var seed: u64 = 0x9E3779B97F4A7C15;
        for (&self.stars, 0..) |*star, i_idx| {
            seed = seed *% 6364136223846793005 +% 1442695040888963407;
            const rx = @as(f32, @floatFromInt(@as(u32, @truncate(seed >> 32)))) / 4294967296.0;
            seed = seed *% 6364136223846793005 +% 1442695040888963407;
            const ry = @as(f32, @floatFromInt(@as(u32, @truncate(seed >> 32)))) / 4294967296.0;
            seed = seed *% 6364136223846793005 +% 1442695040888963407;
            const r_col = @as(u32, @truncate(seed >> 32)) % 4;

            star.base_x = rx * fw;
            star.base_y = ry * fh;
            star.brightness = 0.45 + 0.55 * (@as(f32, @floatFromInt(i_idx % 7)) / 7.0);

            switch (r_col) {
                0 => { // O-type electric blue
                    star.r = 160;
                    star.g = 200;
                    star.b = 255;
                },
                1 => { // A-type pure white
                    star.r = 240;
                    star.g = 245;
                    star.b = 255;
                },
                2 => { // G-type solar gold
                    star.r = 255;
                    star.g = 225;
                    star.b = 150;
                },
                else => { // M-type crimson amber
                    star.r = 255;
                    star.g = 130;
                    star.b = 80;
                },
            }
        }

        // 2. Initialize orbiting relativistic plasma hotspots in accretion disk
        for (&self.hotspots, 0..) |*clump, k| {
            const fk: f32 = @floatFromInt(k);
            const frac = fk / @as(f32, @floatFromInt(NUM_HOTSPOTS));
            clump.r_norm = 2.4 + frac * 6.5;
            clump.phi = fk * (2.0 * math.pi / @as(f32, @floatFromInt(NUM_HOTSPOTS)));
            // Relativistic Keplerian angular frequency Omega = sqrt(M / r^3)
            clump.omega = 4.2 / @sqrt(clump.r_norm * clump.r_norm * clump.r_norm);
            clump.size_px = @max(3.0, (base_dim * 0.012) * (1.0 + 0.3 * (1.0 - frac)));

            if (frac < 0.35) {
                clump.base_r = 180;
                clump.base_g = 220;
                clump.base_b = 255;
            } else if (frac < 0.7) {
                clump.base_r = 255;
                clump.base_g = 210;
                clump.base_b = 130;
            } else {
                clump.base_r = 255;
                clump.base_g = 120;
                clump.base_b = 50;
            }
        }

        // 3. Initialize relativistic jet shock knots
        for (&self.jet_knots_y, 0..) |*ky, j| {
            const fj: f32 = @floatFromInt(j);
            ky.* = (fj / @as(f32, @floatFromInt(NUM_JET_KNOTS))) * fh;
            self.jet_knots_speed[j] = (base_dim * 0.25) * (0.8 + 0.1 * fj);
        }

        // 4. Precompute Luminet-Page-Thorne General-Relativistic Black Hole & Accretion Disk
        const cos_i: f32 = 0.26; // Inclination angle i ~ 75 degrees
        const sin_i: f32 = 0.965;
        const inv_rg: f32 = 1.0 / rg;

        for (0..self.h) |y| {
            const fy: f32 = @floatFromInt(y);
            const dy = fy - cy;
            const row_start = y * self.w;

            for (0..self.w) |x| {
                const fx: f32 = @floatFromInt(x);
                const dx = fx - cx;

                const dist_sq = dx * dx + dy * dy;
                const dist = @sqrt(dist_sq);
                const r_norm = dist * inv_rg;

                // Cosmic void background gradient: deep indigo with subtle purple vignette
                const void_vignette = @min(1.0, dist / (base_dim * 0.85));
                var r_accum: f32 = 3.0 + void_vignette * 4.0;
                var g_accum: f32 = 4.0 + void_vignette * 6.0;
                var b_accum: f32 = 12.0 + void_vignette * 16.0;

                // Gravitational accretion corona glow
                const corona = 18.0 / (1.0 + r_norm * r_norm * 0.18);
                r_accum += corona * 0.6;
                g_accum += corona * 0.8;
                b_accum += corona * 1.5;

                // Blandford-Znajek Relativistic Jets along the y-axis
                const abs_dy = @abs(dy);
                if (abs_dy > rg * 0.8) {
                    const jet_width = rg * 0.15 + abs_dy * 0.07;
                    const jet_dist_x = @abs(dx);
                    if (jet_dist_x < jet_width * 3.0) {
                        const jet_prof = @exp(-(jet_dist_x * jet_dist_x) / (jet_width * jet_width));
                        const jet_decay = 1.0 / (1.0 + (abs_dy / rg) * 0.15);
                        const jet_col = jet_prof * jet_decay * 55.0;
                        r_accum += jet_col * 0.4;
                        g_accum += jet_col * 0.7;
                        b_accum += jet_col * 1.6;
                    }
                }

                // Relativistic Accretion Disk Model:
                // Direct front disk and gravitationally lensed rear disk flange
                var disk_flux: f32 = 0.0;
                var disk_temp_t: f32 = 0.0;
                var doppler_boost: f32 = 1.0;

                const disk_r_front = @sqrt(dx * dx + (dy / cos_i) * (dy / cos_i)) * inv_rg;
                const dy_rear = (dy + rg * 1.3) / 0.52;
                const disk_r_rear = @sqrt(dx * dx + (dy_rear / cos_i) * (dy_rear / cos_i)) * inv_rg;

                // A. Direct front disk (dy > -rg * 0.6)
                if (disk_r_front >= 2.1 and disk_r_front <= 12.0 and dy > -rg * 0.6) {
                    const r = disk_r_front;
                    const q = 1.0 - @sqrt(2.1 / r);
                    const flux_local = (1.0 / (r * r)) * @sqrt(@max(0.0, q)) * 14.0;
                    if (flux_local > disk_flux) {
                        disk_flux = flux_local;
                        disk_temp_t = @min(1.0, 3.2 / r);

                        const beta = @sqrt(1.0 / r);
                        const cos_psi = -dx / (@sqrt(dx * dx + (dy / cos_i) * (dy / cos_i)) + 1e-4);
                        const beta_par = std.math.clamp(beta * cos_psi * sin_i, -0.85, 0.85);
                        const gamma = 1.0 / @sqrt(1.0 - beta_par * beta_par);
                        const doppler_delta = 1.0 / (gamma * (1.0 - beta_par));
                        const g_grav = @sqrt(@max(0.05, 1.0 - 2.0 / r));
                        const g_tot = doppler_delta * g_grav;
                        doppler_boost = g_tot * g_tot * g_tot;
                    }
                }

                // B. Lensed rear flange arched above event horizon
                if (disk_r_rear >= 2.1 and disk_r_rear <= 10.0 and dy < rg * 0.2) {
                    const r = disk_r_rear;
                    const q = 1.0 - @sqrt(2.1 / r);
                    const flux_local = (1.0 / (r * r)) * @sqrt(@max(0.0, q)) * 12.0;
                    if (flux_local > disk_flux) {
                        disk_flux = flux_local;
                        disk_temp_t = @min(1.0, 3.2 / r);

                        const beta = @sqrt(1.0 / r);
                        const cos_psi = -dx / (@sqrt(dx * dx + (dy_rear / cos_i) * (dy_rear / cos_i)) + 1e-4);
                        const beta_par = std.math.clamp(beta * cos_psi * sin_i, -0.85, 0.85);
                        const gamma = 1.0 / @sqrt(1.0 - beta_par * beta_par);
                        const doppler_delta = 1.0 / (gamma * (1.0 - beta_par));
                        const g_grav = @sqrt(@max(0.05, 1.0 - 2.0 / r));
                        const g_tot = doppler_delta * g_grav;
                        doppler_boost = g_tot * g_tot * g_tot;
                    }
                }

                // Combine thermal disk emission with relativistic Doppler boosting
                if (disk_flux > 0.001) {
                    const final_intensity = disk_flux * doppler_boost;
                    const dr = std.math.clamp(final_intensity * (120.0 + disk_temp_t * 135.0), 0.0, 255.0);
                    const dg = std.math.clamp(final_intensity * (80.0 + disk_temp_t * 160.0), 0.0, 255.0);
                    const db = std.math.clamp(final_intensity * (40.0 + disk_temp_t * 215.0), 0.0, 255.0);

                    r_accum += dr;
                    g_accum += dg;
                    b_accum += db;
                }

                // C. Black Hole Shadow and Razor-Sharp Photon Ring
                const spin_shift = 0.22 * rg;
                const shadow_dx = dx + spin_shift;
                const shadow_dist = @sqrt(shadow_dx * shadow_dx + dy * dy * 1.08) * inv_rg;
                const b_crit: f32 = 2.58;

                if (shadow_dist < b_crit) {
                    // Inside the shadow: photons are captured by the event horizon
                    const horizon_edge = std.math.clamp((shadow_dist - (b_crit - 0.25)) / 0.25, 0.0, 1.0);
                    r_accum *= horizon_edge;
                    g_accum *= horizon_edge;
                    b_accum *= horizon_edge;
                } else {
                    // Intense photon ring spike just outside shadow boundary
                    const ring_dist = shadow_dist - b_crit;
                    if (ring_dist < 0.35) {
                        const ring_prof = @exp(-(ring_dist * ring_dist) / (0.04 * 0.04));
                        const ring_boost = std.math.clamp(1.0 - (dx * inv_rg) * 0.35, 0.3, 2.2);
                        const ring_val = ring_prof * ring_boost * 210.0;
                        r_accum += ring_val * 0.85;
                        g_accum += ring_val * 0.95;
                        b_accum += ring_val * 1.1;
                    }
                }

                const final_r: u8 = @as(u8, @intFromFloat(std.math.clamp(r_accum, 0.0, 255.0)));
                const final_g: u8 = @as(u8, @intFromFloat(std.math.clamp(g_accum, 0.0, 255.0)));
                const final_b: u8 = @as(u8, @intFromFloat(std.math.clamp(b_accum, 0.0, 255.0)));

                self.bg_lut[row_start + x] = sdk.packRGBA(final_r, final_g, final_b);
            }
        }

        // 5. Splat gravitationally deflected background stars onto bg_lut
        for (self.stars) |star| {
            const sdx = star.base_x - cx;
            const sdy = star.base_y - cy;
            const s_dist = @sqrt(sdx * sdx + sdy * sdy);

            const theta_e = rg * 1.8;
            const def_factor = 1.0 + (theta_e * theta_e) / (s_dist * s_dist + rg * rg);
            const app_x = cx + sdx * def_factor;
            const app_y = cy + sdy * def_factor;

            const ix: isize = @as(isize, @intFromFloat(app_x));
            const iy: isize = @as(isize, @intFromFloat(app_y));

            var sy: isize = -1;
            while (sy <= 1) : (sy += 1) {
                const py = iy + sy;
                if (py >= 0 and py < @as(isize, @intCast(self.h))) {
                    const row_idx = @as(usize, @intCast(py)) * self.w;
                    var sx: isize = -1;
                    while (sx <= 1) : (sx += 1) {
                        const px = ix + sx;
                        if (px >= 0 and px < @as(isize, @intCast(self.w))) {
                            const col_idx = @as(usize, @intCast(px));
                            const weight: f32 = if (sx == 0 and sy == 0) 1.0 else 0.45;
                            const star_color = sdk.packRGBA(
                                @as(u8, @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(star.r)) * star.brightness * weight, 0.0, 255.0))),
                                @as(u8, @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(star.g)) * star.brightness * weight, 0.0, 255.0))),
                                @as(u8, @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(star.b)) * star.brightness * weight, 0.0, 255.0))),
                            );
                            self.bg_lut[row_idx + col_idx] = sdk.addRGB(self.bg_lut[row_idx + col_idx], star_color);
                        }
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
        self.time_sec += dt;
        const t_f: f32 = @as(f32, @floatCast(self.time_sec));

        // Spacetime gravitational quadrupole waves & jet pulses
        for (0..self.h) |y| {
            const fy: f32 = @floatFromInt(y);
            const s1 = @sin(fy * 0.012 - t_f * 4.2);
            const s2 = @sin(fy * 0.028 + t_f * 2.8);
            const wave = 0.5 + 0.3 * s1 + 0.2 * s2;

            const r: u8 = @as(u8, @intFromFloat(wave * 12.0));
            const g: u8 = @as(u8, @intFromFloat(wave * 22.0));
            const b: u8 = @as(u8, @intFromFloat(wave * 42.0));
            self.row_wave[y] = sdk.packRGBA(r, g, b);
        }

        // Advance orbiting accretion clumps
        const dt_f: f32 = @as(f32, @floatCast(dt));
        for (&self.hotspots) |*clump| {
            clump.phi += clump.omega * dt_f;
            if (clump.phi > 2.0 * math.pi) {
                clump.phi -= 2.0 * math.pi;
            }
        }

        // Advance relativistic jet shock knots
        const fh: f32 = @floatFromInt(self.h);
        for (&self.jet_knots_y, 0..) |*ky, j| {
            ky.* -= self.jet_knots_speed[j] * dt_f;
            if (ky.* < 0.0) {
                ky.* += fh;
            }
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;

        // 1. Copy precomputed background and blend with dynamic spacetime ripples
        for (0..h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.bg_lut[y * w .. y * w + w];
            const wave = self.row_wave[y];
            for (dst_row, src_row) |*dst, src| {
                dst.* = sdk.addRGB(src, wave);
            }
        }

        // 2. Render orbiting relativistic plasma hotspots with Doppler beaming
        const fw: f32 = @floatFromInt(w);
        const fh: f32 = @floatFromInt(h);
        const cx: f32 = fw * 0.5;
        const cy: f32 = fh * 0.52;
        const base_dim: f32 = @min(fw, fh);
        const rg: f32 = base_dim * 0.052;
        const cos_i: f32 = 0.26;
        const sin_i: f32 = 0.965;

        for (self.hotspots) |clump| {
            const r_px = clump.r_norm * rg;
            const cos_p = @cos(clump.phi);
            const sin_p = @sin(clump.phi);

            const local_x = r_px * cos_p;
            var local_y = r_px * sin_p * cos_i;

            // Gravitational lensing: arch rear hotspots over the shadow
            if (sin_p < 0.0) {
                const lens_arch = (rg * 1.3) * (1.0 - (local_x * local_x) / (r_px * r_px + 1e-4));
                local_y -= lens_arch;
            }

            const app_x = cx + local_x;
            const app_y = cy + local_y;

            // Relativistic Doppler factor
            const beta = @sqrt(1.0 / clump.r_norm);
            const beta_par = std.math.clamp(-beta * sin_p * sin_i, -0.85, 0.85);
            const gamma = 1.0 / @sqrt(1.0 - beta_par * beta_par);
            const doppler_delta = 1.0 / (gamma * (1.0 - beta_par));
            const g_grav = @sqrt(@max(0.05, 1.0 - 2.0 / clump.r_norm));
            const g_tot = doppler_delta * g_grav;
            const boost = g_tot * g_tot * g_tot;

            const boost_scale: f32 = std.math.clamp(boost, 0.1, 4.0);
            const cr: u8 = @as(u8, @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(clump.base_r)) * boost_scale, 0.0, 255.0)));
            const cg: u8 = @as(u8, @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(clump.base_g)) * boost_scale, 0.0, 255.0)));
            const cb: u8 = @as(u8, @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(clump.base_b)) * (boost_scale * 1.2), 0.0, 255.0)));
            const clump_color = sdk.packRGBA(cr, cg, cb);

            const hx: isize = @as(isize, @intFromFloat(app_x));
            const hy: isize = @as(isize, @intFromFloat(app_y));
            const rad: isize = @as(isize, @intFromFloat(clump.size_px));

            const y_start = @max(@as(isize, 0), hy - rad);
            const y_end = @min(@as(isize, @intCast(h)), hy + rad + 1);
            const x_start = @max(@as(isize, 0), hx - rad);
            const x_end = @min(@as(isize, @intCast(w)), hx + rad + 1);

            if (y_start < y_end and x_start < x_end) {
                var sy = y_start;
                while (sy < y_end) : (sy += 1) {
                    const uy: usize = @intCast(sy);
                    const row_offset = uy * stride;
                    const dy_px: f32 = @floatFromInt(sy - hy);

                    var sx = x_start;
                    while (sx < x_end) : (sx += 1) {
                        const ux: usize = @intCast(sx);
                        const dx_px: f32 = @floatFromInt(sx - hx);
                        const d_sq = dx_px * dx_px + dy_px * dy_px;
                        const r_sq: f32 = @max(1.0, clump.size_px * clump.size_px);

                        if (d_sq < r_sq) {
                            const falloff: u32 = @as(u32, @intFromFloat((1.0 - d_sq / r_sq) * 256.0));
                            const splat_col = sdk.scaleRGB(clump_color, falloff);
                            buf[row_offset + ux] = sdk.addRGB(buf[row_offset + ux], splat_col);
                        }
                    }
                }
            }
        }

        // 3. Relativistic jet shock knots along the vertical axis
        for (self.jet_knots_y) |knot_y| {
            const ky: isize = @as(isize, @intFromFloat(knot_y));
            const kx: isize = @as(isize, @intFromFloat(cx));
            const k_rad: isize = @as(isize, @intFromFloat(rg * 0.45));

            const y_start = @max(@as(isize, 0), ky - k_rad);
            const y_end = @min(@as(isize, @intCast(h)), ky + k_rad + 1);
            const x_start = @max(@as(isize, 0), kx - k_rad);
            const x_end = @min(@as(isize, @intCast(w)), kx + k_rad + 1);

            if (y_start < y_end and x_start < x_end) {
                var sy = y_start;
                while (sy < y_end) : (sy += 1) {
                    const uy: usize = @intCast(sy);
                    const row_offset = uy * stride;
                    const dy_px: f32 = @floatFromInt(sy - ky);

                    var sx = x_start;
                    while (sx < x_end) : (sx += 1) {
                        const ux: usize = @intCast(sx);
                        const dx_px: f32 = @floatFromInt(sx - kx);
                        const d_sq = dx_px * dx_px + dy_px * dy_px;
                        const r_sq: f32 = @max(1.0, @as(f32, @floatFromInt(k_rad * k_rad)));

                        if (d_sq < r_sq) {
                            const falloff: u32 = @as(u32, @intFromFloat((1.0 - d_sq / r_sq) * 180.0));
                            const knot_color = sdk.scaleRGB(sdk.packRGBA(70, 140, 255), falloff);
                            buf[row_offset + ux] = sdk.addRGB(buf[row_offset + ux], knot_color);
                        }
                    }
                }
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.time_sec) or math.isInf(self.time_sec);
    }
};

comptime {
    sdk.exportTheme(State);
}

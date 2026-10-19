const std = @import("std");
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

fn hash2d(x: u32, y: u32) u32 {
    var h: u32 = x *% 374761393 +% y *% 668265263;
    h = (h ^ (h >> 13)) *% 1274126177;
    return h ^ (h >> 16);
}

fn fastAtan2(y: f32, x: f32) f32 {
    const abs_x = @abs(x);
    const abs_y = @abs(y);
    if (abs_x < 1e-6 and abs_y < 1e-6) return 0.0;

    const min_v = @min(abs_x, abs_y);
    const max_v = @max(abs_x, abs_y);
    const z = min_v / @max(1e-6, max_v);

    var angle = z * (0.97239411 - 0.19194795 * z * z);
    if (abs_y > abs_x) {
        angle = (std.math.pi * 0.5) - angle;
    }
    if (x < 0.0) {
        angle = std.math.pi - angle;
    }
    if (y < 0.0) {
        angle = -angle;
    }
    return angle;
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,

    // Precomputed gravitational lensing background and sine lookup table
    // Total heap size remains strictly <= 12 MiB (approx 9.22 MiB)
    bg_lut: [MAX_PIXELS]u32,
    row_gw: [MAX_H]u32,
    sin_lut: [1024]f32,

    pub fn evalSin(self: *const State, angle: f32) f32 {
        const two_pi = std.math.pi * 2.0;
        const norm = @mod(angle, two_pi);
        const positive_norm = if (norm < 0.0) norm + two_pi else norm;
        const idx = @as(usize, @intFromFloat(positive_norm * (1024.0 / two_pi)));
        return self.sin_lut[idx & 1023];
    }

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;
        self.row_gw = @splat(sdk.packRGBA(0, 0, 0));

        // Precompute 1D sine lookup table
        for (0..1024) |i| {
            const fi = @as(f32, @floatFromInt(i));
            const angle = (fi / 1024.0) * (std.math.pi * 2.0);
            self.sin_lut[i] = @sin(angle);
        }

        const fw = @as(f32, @floatFromInt(self.w));
        const fh = @as(f32, @floatFromInt(self.h));
        const cx = fw * 0.5;
        const cy = fh * 0.5;
        const r_einstein = @min(cx, cy) * 0.45;
        const r_einstein2 = r_einstein * r_einstein;

        // Precompute General Relativistic gravitational lensing & celestial background
        for (0..self.h) |y| {
            const fy = @as(f32, @floatFromInt(y));
            const dy = fy - cy;
            const dy2 = dy * dy;

            for (0..self.w) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const dx = fx - cx;
                const r2 = dx * dx + dy2;
                const r = @sqrt(@max(0.0, r2));

                // Relativistic deflection angle: bends background light around black hole
                const deflect = r_einstein2 / (r2 + 400.0);
                const lensed_x = cx + dx * (1.0 - deflect);
                const lensed_y = cy + dy * (1.0 - deflect);

                // 1. Starfield generation via hash on deflected celestial coordinates
                const ux: u32 = @as(u32, @intFromFloat(@abs(lensed_x) * 1.5));
                const uy: u32 = @as(u32, @intFromFloat(@abs(lensed_y) * 1.5));
                const h_val = hash2d(ux, uy);

                var star_r: u32 = 0;
                var star_g: u32 = 0;
                var star_b: u32 = 0;

                if ((h_val & 0x0FFF) == 77) {
                    star_r = 230;
                    star_g = 240;
                    star_b = 255;
                } else if ((h_val & 0x07FF) == 42) {
                    star_r = 240;
                    star_g = 190;
                    star_b = 100;
                } else if ((h_val & 0x01FF) == 13) {
                    const dim: u32 = 60 + ((h_val >> 10) & 0x3F);
                    star_r = dim;
                    star_g = dim + 10;
                    star_b = dim + 25;
                }

                // 2. Interstellar cosmic gas clouds (nebula)
                const nx = lensed_x * 0.0035;
                const ny = lensed_y * 0.0035;
                const n1 = 0.5 + 0.5 * @sin(nx + ny * 0.7);
                const n2 = 0.5 + 0.5 * @cos(nx * 1.8 - ny * 1.2);
                const n3 = 0.5 + 0.5 * @sin((nx - ny) * 2.3);
                const neb_dense = n1 * 0.5 + n2 * 0.3 + n3 * 0.2;
                const neb_pow = neb_dense * neb_dense;

                const neb_r = @as(u32, @intFromFloat(neb_pow * 28.0));
                const neb_g = @as(u32, @intFromFloat(neb_pow * 18.0));
                const neb_b = @as(u32, @intFromFloat(neb_pow * 48.0));

                // 3. Collimated relativistic polar synchrotron jets along y-axis
                const jet_w = 12.0 + 0.07 * @abs(dy);
                const jet_dist = @abs(dx);
                const jet_falloff = @exp(-(jet_dist * jet_dist) / (2.0 * jet_w * jet_w));
                const jet_fade = 90.0 / @max(40.0, @abs(dy));
                const jet_val = jet_falloff * @min(2.5, jet_fade);

                const jet_r = @as(u32, @intFromFloat(std.math.clamp(jet_val * 45.0, 0.0, 255.0)));
                const jet_g = @as(u32, @intFromFloat(std.math.clamp(jet_val * 110.0, 0.0, 255.0)));
                const jet_b = @as(u32, @intFromFloat(std.math.clamp(jet_val * 220.0, 0.0, 255.0)));

                // 4. Lensed Einstein Ring photon halo
                const e_dist = @abs(r - r_einstein);
                const e_glow = @exp(-(e_dist * e_dist) / 120.0) * 35.0;
                const ein_r = @as(u32, @intFromFloat(e_glow * 0.8));
                const ein_g = @as(u32, @intFromFloat(e_glow * 0.95));
                const ein_b = @as(u32, @intFromFloat(e_glow * 1.2));

                const base_r: u32 = 4;
                const base_g: u32 = 6;
                const base_b: u32 = 14;

                const tot_r: u8 = @as(u8, @intCast(@min(@as(u32, 255), base_r + star_r + neb_r + jet_r + ein_r)));
                const tot_g: u8 = @as(u8, @intCast(@min(@as(u32, 255), base_g + star_g + neb_g + jet_g + ein_g)));
                const tot_b: u8 = @as(u8, @intCast(@min(@as(u32, 255), base_b + star_b + neb_b + jet_b + ein_b)));

                self.bg_lut[y * self.w + x] = sdk.packRGBA(tot_r, tot_g, tot_b);
            }
        }
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const t = self.time_sec;

        // Quadrupolar gravitational wave metric perturbation passing through observer plane
        for (0..self.h) |y| {
            const fy = @as(f64, @floatFromInt(y));
            const phase1 = fy * 0.018 - t * 4.2;
            const phase2 = fy * 0.027 + t * 2.8;
            const s1 = 0.5 + 0.5 * @sin(phase1);
            const s2 = 0.5 + 0.5 * @sin(phase2);
            const pulse = s1 * s2;

            const r_val: u8 = @as(u8, @intFromFloat(pulse * 14.0));
            const g_val: u8 = @as(u8, @intFromFloat(pulse * 26.0));
            const b_val: u8 = @as(u8, @intFromFloat(pulse * 52.0));
            self.row_gw[y] = sdk.packRGBA(r_val, g_val, b_val);
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;

        // 1. Render base gravitational-lensed background starfield with gravitational wave modulation
        for (0..h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.bg_lut[y * w .. y * w + w];
            const gw = self.row_gw[y];
            for (dst_row, src_row) |*dst, src| {
                dst.* = sdk.addRGB(src, gw);
            }
        }

        // 2. Render dynamic relativistic Kerr accretion disk with Doppler beaming
        const fw = @as(f32, @floatFromInt(w));
        const fh = @as(f32, @floatFromInt(h));
        const cx = fw * 0.5;
        const cy = fh * 0.5;

        // Dynamically scale accretion disk based on viewport resolution (supports 320x200 watchdog & 1920x1200)
        const r_out = @min(cx, cy) * 0.82;
        const r_out2 = r_out * r_out;
        const r_in = r_out * 0.24; // ISCO (Innermost Stable Circular Orbit)
        const r_shadow = r_out * 0.16; // Event horizon shadow
        const r_shadow2 = r_shadow * r_shadow;

        // Disk inclination: tilted towards observer (i ~ 68 degrees, cos(i) ~ 0.38)
        const cos_inc: f32 = 0.38;
        const inv_cos_inc: f32 = 1.0 / cos_inc;

        const y_radius = r_out * cos_inc;
        const y_start = @as(usize, @intFromFloat(@max(0.0, cy - y_radius - 2.0)));
        const y_end = @as(usize, @intFromFloat(@min(fh, cy + y_radius + 3.0)));

        const time_f = @as(f32, @floatCast(self.time_sec));

        for (y_start..y_end) |y| {
            const fy = @as(f32, @floatFromInt(y));
            const dy = (fy - cy) * inv_cos_inc;
            const dy2 = dy * dy;
            if (dy2 >= r_out2) continue;

            const dx_span = @sqrt(@max(0.0, r_out2 - dy2));
            const x_start = @as(usize, @intFromFloat(@max(0.0, cx - dx_span - 1.0)));
            const x_end = @as(usize, @intFromFloat(@min(fw, cx + dx_span + 2.0)));

            for (x_start..x_end) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const dx = fx - cx;
                const r2 = dx * dx + dy2;
                if (r2 >= r_out2) continue;

                const pixel_idx = y * stride + x;

                // Inside black hole event horizon shadow
                if (r2 <= r_shadow2) {
                    const r = @sqrt(@max(0.0, r2));
                    const shadow_edge = std.math.clamp((r_shadow - r) * 1.5, 0.0, 1.0);
                    if (shadow_edge >= 0.99) {
                        buf[pixel_idx] = sdk.packRGBA(0, 0, 0);
                        continue;
                    } else {
                        const bg_pixel = buf[pixel_idx];
                        const dim = @as(u32, @intFromFloat((1.0 - shadow_edge) * 256.0));
                        buf[pixel_idx] = sdk.scaleRGB(bg_pixel, dim);
                        continue;
                    }
                }

                const r = @sqrt(@max(1e-4, r2));
                const is_photon_ring = (r > r_shadow and r < r_shadow * 1.15);

                // Azimuthal angle phi on accretion disk plane
                const phi = fastAtan2(dy, dx);

                // Keplerian orbital frequency Omega(r) ~ omega_0 * (r_out / r)^1.5
                const r_ratio = r_out / r;
                const omega = 1.35 * r_ratio * @sqrt(r_ratio);

                // Multi-armed relativistic spiral density waves
                const log_r = @log(@max(1.0, r / r_in));
                const spiral_phase = phi - omega * time_f - 2.8 * log_r;

                const s1 = self.evalSin(spiral_phase * 2.0);
                const s2 = self.evalSin(spiral_phase * 3.0 + 1.2);
                const density = 0.5 + 0.3 * s1 + 0.2 * s2;

                // Relativistic Doppler Beaming
                // Approaching plasma on left (dx < 0), receding on right (dx > 0)
                const v_orbit = @min(0.65, 0.45 * @sqrt(r_in / r));
                const v_parallel = -v_orbit * (dx / r) * 0.92;
                const doppler = std.math.clamp(1.0 / @max(0.1, 1.0 - v_parallel), 0.35, 3.2);
                const beaming = doppler * doppler * @sqrt(doppler);

                // Radial Shakura-Sunyaev temperature profile
                const r_peak = r_in * 1.35;
                const temp_profile = if (r < r_in)
                    ((r - r_shadow) / @max(1e-4, r_in - r_shadow)) * 0.8
                else
                    @max(0.05, @min(1.0, r_peak / r)) * (1.0 - 0.7 * (r / r_out));

                const intensity = density * temp_profile * beaming;

                // Smooth boundary Hermite fade at outer disk radius (seamless blending)
                const fade = if (r > r_out * 0.82)
                    std.math.clamp((r_out - r) / (r_out * 0.18), 0.0, 1.0)
                else
                    1.0;
                const smooth_fade = fade * fade * (3.0 - 2.0 * fade);

                // Spectral color mapping: Doppler blue-shift vs red-shift
                var pr: f32 = 0.0;
                var pg: f32 = 0.0;
                var pb: f32 = 0.0;

                if (doppler > 1.3) {
                    // Blueshifted high-energy thermal emission (approaching side)
                    const boost = (doppler - 1.3) * 0.8;
                    pr = (180.0 + boost * 75.0) * intensity;
                    pg = (210.0 + boost * 45.0) * intensity;
                    pb = 255.0 * intensity;
                } else if (doppler > 0.8) {
                    // Moderate temperature golden synchrotron plasma
                    pr = 255.0 * intensity;
                    pg = (140.0 + doppler * 50.0) * intensity;
                    pb = (40.0 + doppler * 40.0) * intensity;
                } else {
                    // Redshifted and gravitationally dimmed emission (receding side)
                    pr = (160.0 * doppler) * intensity;
                    pg = (35.0 * doppler) * intensity;
                    pb = (15.0 * doppler) * intensity;
                }

                // Luminous photon ring contribution
                if (is_photon_ring) {
                    const p_dist = @abs(r - r_shadow * 1.08);
                    const p_intensity = @exp(-p_dist * p_dist * 0.4) * 220.0 * doppler;
                    pr += p_intensity;
                    pg += p_intensity * 0.9;
                    pb += p_intensity * 0.75;
                }

                pr *= smooth_fade;
                pg *= smooth_fade;
                pb *= smooth_fade;

                const r_u8 = @as(u8, @intFromFloat(std.math.clamp(pr, 0.0, 255.0)));
                const g_u8 = @as(u8, @intFromFloat(std.math.clamp(pg, 0.0, 255.0)));
                const b_u8 = @as(u8, @intFromFloat(std.math.clamp(pb, 0.0, 255.0)));

                const disk_pixel = sdk.packRGBA(r_u8, g_u8, b_u8);
                buf[pixel_idx] = sdk.addRGB(buf[pixel_idx], disk_pixel);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return std.math.isNan(self.time_sec) or std.math.isInf(self.time_sec);
    }
};

comptime {
    sdk.exportTheme(State);
}

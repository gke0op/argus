const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;
pub const DISK_W: usize = 800;
pub const DISK_H: usize = 440;
pub const DISK_CELLS: usize = DISK_W * DISK_H;

/// Physical Simulation & Visualization of a Supermassive Kerr Singularity (spin a/M = 0.94)
/// with a Relativistic Novikov-Thorne Accretion Disk, Asymmetric Frame-Dragging Shadow,
/// Dual Gravitational Lensing Arches, Doppler Beaming, and Ergosphere Polar Jets.
pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,

    // Precomputed full-resolution deep-space cosmic background (nebula + lensed starfield)
    bg_lut: [MAX_PIXELS]u32,

    // Precomputed relativistic geometry table for the active black hole accretion disk
    disk_cells: [DISK_CELLS]u32,

    // Fast 1D dynamic lookup tables evaluated in step()
    kepler_phase: [256]u16,
    turb_lut: [512]u8,
    jet_lut: [MAX_H]u32,
    jet_falloff: [32]u32,

    const Rng = struct {
        state: u64,
        inline fn next(self: *Rng) u64 {
            self.state +%= 0x9E3779B97F4A7C15;
            var z: u64 = self.state;
            z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
            z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
            return z ^ (z >> 31);
        }
    };

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        // Single heap allocation for the entire state (Gate 2: Allocs at Init == 1)
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;

        @memset(self.disk_cells[0..], 0);
        @memset(self.kepler_phase[0..], 0);
        @memset(self.turb_lut[0..], 0);
        @memset(self.jet_lut[0..], sdk.packRGBA(0, 0, 0));

        // Precompute transverse Gaussian falloff for polar relativistic jets
        for (0..32) |idx| {
            const fidx: f32 = @floatFromInt(idx);
            const falloff: f32 = @exp(-fidx * 0.38);
            const scale_val: u32 = @intFromFloat(std.math.clamp(falloff * 256.0, 0.0, 256.0));
            self.jet_falloff[idx] = scale_val;
        }

        const cx: f32 = @as(f32, @floatFromInt(self.w)) * 0.5;
        const cy: f32 = @as(f32, @floatFromInt(self.h)) * 0.5;

        // 1. Generate cosmic deep space background + nebula into bg_lut
        for (0..self.h) |y| {
            const fy: f32 = @floatFromInt(y);
            const dy: f32 = fy - cy;
            const row_offset = y * self.w;

            for (0..self.w) |x| {
                const fx: f32 = @floatFromInt(x);
                const dx: f32 = fx - cx;
                const dist: f32 = std.math.hypot(dx, dy);

                // Diffuse galactic core ambient glow
                const bulge: f32 = @exp(-dist / 550.0);
                const r_base: f32 = bulge * 15.0 + 3.0;
                const g_base: f32 = bulge * 12.0 + 4.0;
                const b_base: f32 = bulge * 26.0 + 10.0;

                // Cosmic dust nebula filaments via harmonic synthesis
                const u_coord: f32 = fx * 0.0035;
                const v_coord: f32 = fy * 0.0035;
                const s1: f32 = @sin(u_coord + @cos(v_coord * 1.4));
                const s2: f32 = @cos(v_coord * 1.2 - s1 * 0.75);
                const s3: f32 = @sin((u_coord + v_coord) * 2.1 + s2);
                const dust: f32 = @max(0.0, s1 * 0.5 + s2 * 0.35 + s3 * 0.15);

                const r_dust: f32 = dust * 18.0;
                const g_dust: f32 = dust * 10.0;
                const b_dust: f32 = dust * 32.0;

                const r_pix: u8 = @intFromFloat(std.math.clamp(r_base + r_dust, 0.0, 255.0));
                const g_pix: u8 = @intFromFloat(std.math.clamp(g_base + g_dust, 0.0, 255.0));
                const b_pix: u8 = @intFromFloat(std.math.clamp(b_base + b_dust, 0.0, 255.0));

                self.bg_lut[row_offset + x] = sdk.packRGBA(r_pix, g_pix, b_pix);
            }
        }

        // 2. Gravitationally lensed procedural starfield
        var rng = Rng{ .state = 0xA0761D6478BD642F };
        const num_stars: usize = 2200;
        const w_u64: u64 = @intCast(self.w);
        const h_u64: u64 = @intCast(self.h);

        for (0..num_stars) |_| {
            const raw_x = rng.next() % w_u64;
            const raw_y = rng.next() % h_u64;
            const fx: f32 = @floatFromInt(raw_x);
            const fy: f32 = @floatFromInt(raw_y);
            const dx: f32 = fx - cx;
            const dy: f32 = fy - cy;
            const dist: f32 = std.math.hypot(dx, dy);

            // Stars inside shadow boundary are swallowed by the event horizon
            if (dist < 45.0) continue;

            // Einstein deflection: pushes stars outward around singularity
            const deflection: f32 = 400.0 / @max(35.0, dist);
            const app_x = cx + dx * (1.0 + deflection / dist);
            const app_y = cy + dy * (1.0 + deflection / dist);

            if (app_x < 0.0 or app_x >= @as(f32, @floatFromInt(self.w)) or
                app_y < 0.0 or app_y >= @as(f32, @floatFromInt(self.h)))
            {
                continue;
            }

            const sx: usize = @intFromFloat(app_x);
            const sy: usize = @intFromFloat(app_y);

            // Spectral classification from pseudo-random bits
            const col_type = rng.next() % 5;
            const mag = rng.next() % 256;
            const bright: f32 = @as(f32, @floatFromInt(mag)) / 255.0;

            var r_star: u8 = 255;
            var g_star: u8 = 255;
            var b_star: u8 = 255;

            if (col_type == 0) {
                // Hot O/B-type blue hypergiant
                r_star = @intFromFloat(bright * 180.0);
                g_star = @intFromFloat(bright * 210.0);
                b_star = @intFromFloat(bright * 255.0);
            } else if (col_type == 1) {
                // A-type white star
                r_star = @intFromFloat(bright * 240.0);
                g_star = @intFromFloat(bright * 240.0);
                b_star = @intFromFloat(bright * 255.0);
            } else if (col_type == 2) {
                // Solar G-type analogue
                r_star = @intFromFloat(bright * 255.0);
                g_star = @intFromFloat(bright * 230.0);
                b_star = @intFromFloat(bright * 170.0);
            } else {
                // M-type orange-red dwarf
                r_star = @intFromFloat(bright * 255.0);
                g_star = @intFromFloat(bright * 130.0);
                b_star = @intFromFloat(bright * 60.0);
            }

            const star_pix = sdk.packRGBA(r_star, g_star, b_star);
            const p_idx = sy * self.w + sx;
            self.bg_lut[p_idx] = sdk.addRGB(self.bg_lut[p_idx], star_pix);

            // Diffraction cross spike for brilliant 1st magnitude guide stars
            if (mag > 240) {
                if (sx > 0) self.bg_lut[p_idx - 1] = sdk.addRGB(self.bg_lut[p_idx - 1], sdk.scaleRGB(star_pix, 120));
                if (sx + 1 < self.w) self.bg_lut[p_idx + 1] = sdk.addRGB(self.bg_lut[p_idx + 1], sdk.scaleRGB(star_pix, 120));
                if (sy > 0) self.bg_lut[p_idx - self.w] = sdk.addRGB(self.bg_lut[p_idx - self.w], sdk.scaleRGB(star_pix, 120));
                if (sy + 1 < self.h) self.bg_lut[p_idx + self.w] = sdk.addRGB(self.bg_lut[p_idx + self.w], sdk.scaleRGB(star_pix, 120));
            }
        }

        // 3. Precompute Kerr black hole relativistic geometry into disk_cells
        const active_w = @min(self.w, DISK_W);
        const active_h = @min(self.h, DISK_H);
        const acx: f32 = @as(f32, @floatFromInt(active_w)) * 0.5;
        const acy: f32 = @as(f32, @floatFromInt(active_h)) * 0.5;

        const r_shadow_base: f32 = @as(f32, @floatFromInt(active_w)) * 0.076;
        const r_in: f32 = r_shadow_base * 1.22;
        const r_out: f32 = @as(f32, @floatFromInt(active_w)) * 0.46;
        const cos_inc: f32 = 0.28; // ~74 degree disk inclination

        for (0..active_h) |by| {
            const fby: f32 = @floatFromInt(by);
            const dy: f32 = fby - acy;

            for (0..active_w) |bx| {
                const fbx: f32 = @floatFromInt(bx);
                const dx: f32 = fbx - acx;
                const r_scr: f32 = std.math.hypot(dx, dy);

                // Kerr spin frame-dragging shadow asymmetry (prograde side compressed)
                const kerr_shift: f32 = (dx / @max(1.0, r_shadow_base)) * 0.08;
                const r_shadow = r_shadow_base * (1.0 + kerr_shift);

                // Event horizon shadow check
                if (r_scr < r_shadow) {
                    var cell: u32 = 1; // is_active
                    cell |= 2; // is_shadow
                    self.disk_cells[by * DISK_W + bx] = cell;
                    continue;
                }

                // Photon sphere caustic ring check
                if (r_scr >= r_shadow and r_scr < r_shadow + 2.4) {
                    var cell: u32 = 1; // is_active
                    cell |= 4; // is_photon_ring
                    const ring_doppler: u8 = if (dx < 0.0) 230 else 70;
                    cell |= (@as(u32, ring_doppler) & 0xFF) << 20;
                    self.disk_cells[by * DISK_W + bx] = cell;
                    continue;
                }

                // Direct disk coordinates
                const y_eq = dy / cos_inc;
                const r_dir = std.math.hypot(dx, y_eq);
                const phi_dir = std.math.atan2(y_eq, dx);

                var in_disk = false;
                var r_disk: f32 = 0.0;
                var phi_disk: f32 = 0.0;

                // Test direct disk
                if (r_dir >= r_in and r_dir <= r_out) {
                    if (dy >= 0.0 or r_scr > r_shadow * 1.45) {
                        in_disk = true;
                        r_disk = r_dir;
                        phi_disk = phi_dir;
                    }
                }

                // Test lensed upper arch (rear disk bent over the black hole)
                if (!in_disk and dy < 0.0) {
                    const y_lens = -dy * 1.18;
                    const r_arch = std.math.hypot(dx * 0.82, (y_lens - r_shadow * 0.35) * 1.55);
                    if (r_arch >= r_in and r_arch <= r_out * 0.88) {
                        in_disk = true;
                        r_disk = r_arch;
                        phi_disk = std.math.atan2(y_lens, dx);
                    }
                }

                if (!in_disk) continue;

                // Normalized radius [0..255]
                const u_r: f32 = std.math.clamp((r_disk - r_in) / (r_out - r_in), 0.0, 1.0);
                const r_norm: u8 = @intFromFloat(u_r * 255.0);

                // Normalized azimuthal angle [0..511]
                const norm_phi: f32 = (phi_disk + std.math.pi) / (2.0 * std.math.pi);
                const phi_idx: u16 = @as(u16, @intCast(@as(u32, @intFromFloat(norm_phi * 512.0)) & 511));

                // Relativistic Doppler beaming
                const beta = 0.52 * @sqrt(r_in / @max(r_in * 0.5, r_disk));
                const sin_phi = @sin(phi_disk);
                const v_los = -beta * 0.96 * sin_phi;
                const gamma = 1.0 / @sqrt(@max(0.01, 1.0 - beta * beta));
                const delta = 1.0 / @max(0.1, gamma * (1.0 - v_los));

                const doppler_raw = std.math.clamp(delta * delta * 78.0, 15.0, 255.0);
                const doppler_base: u8 = @intFromFloat(doppler_raw);

                // Novikov-Thorne thermal profile
                const ratio = r_in / @max(r_in, r_disk);
                const sqrt_ratio = @sqrt(ratio);
                const t_prof = @sqrt(@max(0.0, ratio * sqrt_ratio)) * @sqrt(@sqrt(@max(0.0, 1.0 - sqrt_ratio)));
                const t_norm = std.math.clamp((t_prof / 0.44) * 15.0, 1.0, 15.0);
                const thermal_base: u8 = @intFromFloat(t_norm);

                var cell: u32 = 1; // is_active
                cell |= (@as(u32, r_norm) & 0xFF) << 3;
                cell |= (@as(u32, phi_idx) & 0x1FF) << 11;
                cell |= (@as(u32, doppler_base) & 0xFF) << 20;
                cell |= (@as(u32, thermal_base) & 0x0F) << 28;

                self.disk_cells[by * DISK_W + bx] = cell;
            }
        }

        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;

        // 1. Keplerian differential rotation phase per radius
        for (0..256) |r| {
            const fr: f64 = @floatFromInt(r);
            const r_scaled = 1.0 + fr / 28.0;
            const omega = 5.2 / (r_scaled * @sqrt(r_scaled));
            const phase_f = @mod(omega * self.time_sec, 2.0 * math.pi) / (2.0 * math.pi);
            const p_int: u32 = @intFromFloat(phase_f * 512.0);
            self.kepler_phase[r] = @as(u16, @intCast(p_int & 511));
        }

        // 2. Dynamic turbulent wave LUT (two-armed spiral + higher harmonic ripples)
        for (0..512) |i| {
            const fi: f64 = @floatFromInt(i);
            const theta = (fi / 512.0) * 2.0 * math.pi;
            const s1 = @sin(2.0 * theta);
            const s2 = 0.4 * @sin(4.0 * theta - self.time_sec * 3.6);
            const s3 = 0.2 * @cos(6.0 * theta + self.time_sec * 1.8);
            const wave = std.math.clamp(0.45 + 0.35 * s1 + s2 + s3, 0.05, 1.0);
            self.turb_lut[i] = @as(u8, @intFromFloat(wave * 255.0));
        }

        // 3. Ergosphere relativistic polar jet column
        const t = self.time_sec;
        for (0..self.h) |y| {
            const fy: f64 = @floatFromInt(y);
            const cy: f64 = @as(f64, @floatFromInt(self.h)) * 0.5;
            const dy = fy - cy;
            const dist_y = @abs(dy);

            if (dist_y > 45.0) {
                const p = dist_y * 0.038 - t * 6.5;
                const knot = 0.5 + 0.5 * @sin(p);
                const atten = @exp(-dist_y * 0.0028);
                const intensity = std.math.clamp(knot * atten * 190.0, 0.0, 255.0);

                const r_jet: u8 = @intFromFloat(intensity * 0.35);
                const g_jet: u8 = @intFromFloat(intensity * 0.68);
                const b_jet: u8 = @intFromFloat(intensity);
                self.jet_lut[y] = sdk.packRGBA(r_jet, g_jet, b_jet);
            } else {
                self.jet_lut[y] = sdk.packRGBA(0, 0, 0);
            }
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;

        // 1. Copy deep-space cosmic background
        for (0..h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row = self.bg_lut[y * w .. y * w + w];
            @memcpy(dst_row, src_row);
        }

        // 2. Collimated relativistic polar jets along x = xc
        const xc: usize = w / 2;
        const jet_half_w: usize = @max(@as(usize, 2), @min(@as(usize, 16), w / 120));
        const x_min = if (xc > jet_half_w) xc - jet_half_w else 0;
        const x_max = @min(w, xc + jet_half_w);

        for (0..h) |y| {
            const jet_color = self.jet_lut[y];
            if (jet_color == sdk.packRGBA(0, 0, 0)) continue;

            const dst_row = buf[y * stride .. y * stride + w];
            for (x_min..x_max) |x| {
                const dx_jet: usize = if (x >= xc) x - xc else xc - x;
                if (dx_jet >= 32) continue;
                const falloff = self.jet_falloff[dx_jet];
                const scaled_jet = sdk.scaleRGB(jet_color, falloff);
                dst_row[x] = sdk.addRGB(dst_row[x], scaled_jet);
            }
        }

        // 3. Render Kerr accretion disk and event horizon shadow
        const active_w = @min(w, DISK_W);
        const active_h = @min(h, DISK_H);
        const x_start = (w - active_w) / 2;
        const y_start = (h - active_h) / 2;

        for (0..active_h) |by| {
            const py = y_start + by;
            const dst_row = buf[py * stride .. py * stride + w];
            const cell_row = self.disk_cells[by * DISK_W .. by * DISK_W + active_w];

            for (0..active_w) |bx| {
                const cell = cell_row[bx];
                if (cell & 1 == 0) continue; // Inactive: preserve background

                const px = x_start + bx;

                // Event horizon shadow: absolute dark
                if (cell & 2 != 0) {
                    dst_row[px] = sdk.packRGBA(0, 0, 0);
                    continue;
                }

                // Photon sphere caustic ring
                if (cell & 4 != 0) {
                    const doppler = (cell >> 20) & 0xFF;
                    const r_p: u8 = @intCast(@min(@as(u32, 255), 180 + (doppler / 4)));
                    const g_p: u8 = @intCast(@min(@as(u32, 255), 200 + (doppler / 5)));
                    const b_p: u8 = 255;
                    dst_row[px] = sdk.packRGBA(r_p, g_p, b_p);
                    continue;
                }

                // Accretion disk emission
                const r_norm: usize = (cell >> 3) & 0xFF;
                const phi_idx: usize = (cell >> 11) & 0x1FF;
                const doppler_base: u32 = (cell >> 20) & 0xFF;
                const thermal_base: u32 = (cell >> 28) & 0x0F;

                // Keplerian orbital differential rotation
                const rot_phi: usize = (phi_idx + self.kepler_phase[r_norm]) & 0x1FF;
                const turb: u32 = self.turb_lut[rot_phi];

                // Modulate thermal emission with turbulence
                const intensity: u32 = (thermal_base * turb) / 16;

                // Relativistic Doppler boosting
                const flux: u32 = (intensity * doppler_base) / 80;

                // Spectral color grading:
                // Approaching flank (high Doppler): white-hot to brilliant cyan
                // Receding flank (low Doppler): ember orange to deep ruby
                const red_val: u32 = @min(@as(u32, 255), (flux * 260) / 256);
                const green_val: u32 = @min(@as(u32, 255), (flux * (68 + @as(u32, @intCast(r_norm)) / 2)) / 256);
                const blue_val: u32 = if (doppler_base > 100)
                    @min(@as(u32, 255), ((flux * (doppler_base - 100)) * 2) / 256)
                else
                    0;

                const pr: u8 = @intCast(red_val);
                const pg: u8 = @intCast(green_val);
                const pb: u8 = @intCast(blue_val);

                const disk_pixel = sdk.packRGBA(pr, pg, pb);
                dst_row[px] = sdk.addRGB(dst_row[px], disk_pixel);
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

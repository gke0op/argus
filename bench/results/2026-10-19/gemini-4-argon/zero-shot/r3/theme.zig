const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 1920;
pub const MAX_H: usize = 1200;
pub const MAX_PIXELS: usize = MAX_W * MAX_H;

pub const R_BINS: usize = 256;
pub const PHI_BINS: usize = 256;
pub const LUT_SIZE: usize = R_BINS * PHI_BINS;
pub const NUM_PLASMOIDS: usize = 72;

pub const Plasmoid = struct {
    r_norm: f32,
    phi: f32,
    omega: f32,
    temp: f32,
    size: i32,
    layer: u8, // 0 = equatorial disk, 1 = upper lensed arch, 2 = polar jet
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,

    // Precomputed full-resolution static cosmic background, lensed starfield & photon ring
    bg_lut: [MAX_PIXELS]u32,

    // Precomputed 16-bit relativistic coordinate key per pixel:
    // high byte = radial / topological shell (0 = pure bg, 1..168 = primary accretion disk,
    // 169..216 = secondary gravitationally lensed Einstein arch, 217..255 = Blandford-Znajek jet)
    // low byte  = local azimuthal phase angle phi in [0..255]
    pix_code: [MAX_PIXELS]u16,

    // Dynamic 256x256 relativistic emission lookup table updated every frame in step()
    color_lut: [LUT_SIZE]u32,

    // Precomputed radial physical profiles for fast step() evaluation
    r_omega: [R_BINS]f32,
    r_temp: [R_BINS]f32,
    r_spiral_k: [R_BINS]f32,
    r_envelope: [R_BINS]f32,

    // Precomputed angular harmonic tables
    cos_tab: [PHI_BINS]f32,
    sin_tab: [PHI_BINS]f32,

    // Relativistic orbiting hotspots / MHD plasmoids
    plasmoids: [NUM_PLASMOIDS]Plasmoid,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @min(w, MAX_W);
        self.h = @min(h, MAX_H);
        self.scale = scale;
        self.time_sec = 0.0;

        // 1. Initialize angular harmonic tables
        for (0..PHI_BINS) |p| {
            const fp: f32 = @floatFromInt(p);
            const ang: f32 = fp * (2.0 * math.pi / 256.0);
            self.cos_tab[p] = @cos(ang);
            self.sin_tab[p] = @sin(ang);
        }

        // 2. Initialize radial relativistic profiles across the 3 topological regions
        self.r_omega[0] = 0.0;
        self.r_temp[0] = 0.0;
        self.r_spiral_k[0] = 0.0;
        self.r_envelope[0] = 0.0;

        for (1..R_BINS) |r_idx| {
            if (r_idx <= 168) {
                // Region 1: Primary equatorial Kerr accretion disk (r from ISCO=1.0 to R_out=9.5)
                const u: f32 = @as(f32, @floatFromInt(r_idx - 1)) / 167.0;
                const r_phys: f32 = 1.0 + u * 8.5;
                // Relativistic Keplerian angular velocity Omega(r) = 1 / (r^1.5 + a)
                const r_pow: f32 = r_phys * @sqrt(@max(0.0, r_phys));
                self.r_omega[r_idx] = 6.8 / (r_pow + 0.94);
                // Novikov-Thorne temperature profile T(r)
                const isco_factor: f32 = @sqrt(@max(0.0, 1.0 - 0.88 / r_phys));
                self.r_temp[r_idx] = @min(1.0, 1.45 * isco_factor / @sqrt(@max(0.1, r_phys)));
                self.r_spiral_k[r_idx] = r_phys * 2.8;
                // Smooth inner ISCO turn-on and outer edge vignette (zero bounding-box seam)
                const inner_fade: f32 = math.clamp((u - 0.01) * 14.0, 0.0, 1.0);
                const outer_fade: f32 = math.clamp((1.0 - u) * 3.2, 0.0, 1.0);
                self.r_envelope[r_idx] = inner_fade * outer_fade * outer_fade * (1.0 / (1.0 + 0.35 * u * u));
            } else if (r_idx <= 216) {
                // Region 2: Secondary gravitationally lensed Einstein ring arch (over/under shadow)
                const u: f32 = @as(f32, @floatFromInt(r_idx - 169)) / 47.0;
                const r_phys: f32 = 1.0 + u * 5.5;
                const r_pow: f32 = r_phys * @sqrt(@max(0.0, r_phys));
                self.r_omega[r_idx] = 7.2 / (r_pow + 0.94);
                self.r_temp[r_idx] = @min(1.0, 1.15 / @sqrt(@max(0.2, r_phys)));
                self.r_spiral_k[r_idx] = r_phys * 3.4;
                const arch_bell: f32 = @sin(u * math.pi);
                self.r_envelope[r_idx] = arch_bell * arch_bell * 0.92;
            } else {
                // Region 3: Blandford-Znajek relativistic polar MHD jets
                const u: f32 = @as(f32, @floatFromInt(r_idx - 217)) / 38.0;
                self.r_omega[r_idx] = -5.4; // Outward superluminal helical propagation
                self.r_temp[r_idx] = math.clamp(1.0 - 0.45 * u, 0.2, 1.0);
                self.r_spiral_k[r_idx] = u * 12.0;
                const jet_fade: f32 = math.clamp(u * 6.0, 0.0, 1.0) * math.clamp((1.0 - u) * 2.5, 0.0, 1.0);
                self.r_envelope[r_idx] = jet_fade * 0.65;
            }
        }

        // 3. Initialize orbiting relativistic plasmoids
        var rng: u64 = 0xA482F97D7C73494B;
        for (0..NUM_PLASMOIDS) |i| {
            rng = rng *% 6364136223846793005 +% 1442695040888963407;
            const u01: f32 = @as(f32, @floatFromInt(@as(u32, @truncate(rng >> 40)))) / 16777216.0;
            rng = rng *% 6364136223846793005 +% 1442695040888963407;
            const u02: f32 = @as(f32, @floatFromInt(@as(u32, @truncate(rng >> 40)))) / 16777216.0;

            const layer: u8 = if (i < 48) 0 else if (i < 62) 1 else 2;
            const r_norm: f32 = 0.08 + 0.78 * u01;
            const r_phys: f32 = 1.0 + r_norm * 6.5;
            const omega: f32 = if (layer == 2) 3.8 + 1.5 * u01 else 5.2 / (r_phys * @sqrt(r_phys) + 0.94);

            self.plasmoids[i] = .{
                .r_norm = r_norm,
                .phi = u02 * (2.0 * math.pi),
                .omega = omega,
                .temp = 0.65 + 0.35 * (1.0 - r_norm),
                .size = if (self.w <= 400) 1 else @as(i32, @intCast(2 + (i % 3))),
                .layer = layer,
            };
        }

        // 4. Precompute full-screen relativistic ray-traced coordinates & cosmic background
        const fw: f64 = @floatFromInt(@max(@as(usize, 1), self.w));
        const fh: f64 = @floatFromInt(@max(@as(usize, 1), self.h));
        const aspect: f64 = fw / fh;

        // Disk orientation: tilted by 14 degrees counter-clockwise, viewed at inclination i = 76 deg
        const tilt_angle: f64 = -0.244346; // -14 deg
        const cos_tilt: f64 = @cos(tilt_angle);
        const sin_tilt: f64 = @sin(tilt_angle);
        const disk_sin_inc: f64 = 0.2419219; // cos(76 deg) foreshortening factor

        // Black hole shadow radius in normalized vertical screen units
        const r_shadow: f64 = 0.165;
        const r_isco: f64 = 0.172;
        const r_disk_max: f64 = 0.92;

        for (0..self.h) |y| {
            const fy: f64 = @floatFromInt(y);
            // Normalized screen coordinates: ny in [-1, 1], nx in [-aspect, aspect]
            const ny: f64 = (fy / fh) * 2.0 - 1.0;

            for (0..self.w) |x| {
                const fx: f64 = @floatFromInt(x);
                const nx: f64 = ((fx / fw) * 2.0 - 1.0) * aspect;

                // Rotate into black hole spin-axis frame (y' = spin axis, x' = equatorial major axis)
                // Kerr frame-dragging shifts the shadow center slightly right (+0.018)
                const rx: f64 = nx * cos_tilt - ny * sin_tilt;
                const ry: f64 = nx * sin_tilt + ny * cos_tilt;

                const sx: f64 = rx - 0.018;
                const b_impact: f64 = @sqrt(@max(1e-12, sx * sx + ry * ry));
                const b_raw: f64 = @sqrt(@max(1e-12, rx * rx + ry * ry));

                // --- A. Static Cosmic Background + Lensed Starfield + Photon Ring ---
                var bg_r: f64 = 3.0;
                var bg_g: f64 = 5.0;
                var bg_b: f64 = 13.0;

                if (b_impact > r_shadow * 0.96) {
                    // Gravitational deflection mapping for background nebula & stars
                    const einstein_r2: f64 = r_shadow * r_shadow * 1.15;
                    const lens_factor: f64 = 1.0 - einstein_r2 / @max(einstein_r2 * 0.92, b_impact * b_impact);
                    const lx: f64 = sx * lens_factor;
                    const ly: f64 = ry * lens_factor;

                    // Multi-octave galactic dust & ionized nebula filaments
                    const n1: f64 = @sin(lx * 3.1 + @cos(ly * 2.7) * 1.4);
                    const n2: f64 = @cos(lx * 6.3 - ly * 4.9 + n1 * 1.2);
                    const n3: f64 = @sin((lx * 0.85 + ly * 0.45) * 4.5 + n2 * 0.8);
                    const neb_band: f64 = @exp(-@min(12.0, (ry * 1.8 - 0.15 * n1) * (ry * 1.8 - 0.15 * n1) * 3.5));

                    const cyan_neb: f64 = @max(0.0, n2 * 0.5 + 0.5) * neb_band;
                    const mag_neb: f64 = @max(0.0, n3 * 0.5 + 0.5) * neb_band;

                    bg_r += 16.0 * mag_neb + 5.0 * cyan_neb;
                    bg_g += 18.0 * cyan_neb + 6.0 * mag_neb;
                    bg_b += 38.0 * cyan_neb + 22.0 * mag_neb;

                    // Procedural lensed starfield via spatial cell hashing in lensed coordinates
                    const star_scale: f64 = 38.0;
                    const gx_f: f64 = @floor((lx + 4.0) * star_scale);
                    const gy_f: f64 = @floor((ly + 4.0) * star_scale);
                    const cell_x: i32 = @intFromFloat(gx_f);
                    const cell_y: i32 = @intFromFloat(gy_f);
                    const frac_x: f64 = (lx + 4.0) * star_scale - gx_f;
                    const frac_y: f64 = (ly + 4.0) * star_scale - gy_f;

                    const ux: u32 = @bitCast(cell_x);
                    const uy: u32 = @bitCast(cell_y);
                    var h_val: u32 = (ux *% 0x9E3779B1) ^ (uy *% 0x85EBCA77) ^ 0xC2B2AE3D;
                    h_val ^= h_val >> 16;
                    h_val *%= 0x7FEB352D;
                    h_val ^= h_val >> 15;

                    if ((h_val & 0xFF) < 18) {
                        const sx_pos: f64 = 0.2 + 0.6 * (@as(f64, @floatFromInt((h_val >> 8) & 0xFF)) / 255.0);
                        const sy_pos: f64 = 0.2 + 0.6 * (@as(f64, @floatFromInt((h_val >> 16) & 0xFF)) / 255.0);
                        const dx: f64 = frac_x - sx_pos;
                        const dy: f64 = frac_y - sy_pos;
                        const d2: f64 = dx * dx + dy * dy;
                        // Gravitational magnification near Einstein ring
                        const mag_boost: f64 = 1.0 + 1.5 * @exp(-@min(10.0, (b_impact - r_shadow * 1.35) * (b_impact - r_shadow * 1.35) * 45.0));
                        const star_lum: f64 = @exp(-@min(14.0, d2 * 42.0)) * mag_boost * 185.0;
                        const star_type: u32 = (h_val >> 24) & 3;
                        if (star_type == 0) {
                            bg_r += star_lum * 0.75;
                            bg_g += star_lum * 0.88;
                            bg_b += star_lum * 1.15;
                        } else if (star_type == 1) {
                            bg_r += star_lum * 1.10;
                            bg_g += star_lum * 0.92;
                            bg_b += star_lum * 0.72;
                        } else {
                            bg_r += star_lum * 0.95;
                            bg_g += star_lum * 0.96;
                            bg_b += star_lum * 1.02;
                        }
                    }
                } else {
                    // Inside the event horizon shadow: deep obsidian abyss
                    bg_r = 1.0;
                    bg_g = 1.0;
                    bg_b = 3.0;
                }

                // Razor-sharp Kerr Photon Ring (n=1 & n=2 demagnified Lyapunov critical curve)
                const d_photon: f64 = @abs(b_impact - r_shadow);
                const doppler_ring: f64 = math.clamp(1.0 - 0.58 * (rx / @max(0.05, b_raw)), 0.28, 1.75);
                const photon_ring: f64 = @exp(-@min(16.0, (d_photon / 0.0065) * (d_photon / 0.0065))) * doppler_ring;
                const photon_halo: f64 = @exp(-@min(16.0, (d_photon / 0.024) * (d_photon / 0.024))) * doppler_ring * 0.42;
                const ring_tot: f64 = photon_ring + photon_halo;

                bg_r += ring_tot * 235.0;
                bg_g += ring_tot * 185.0;
                bg_b += ring_tot * 125.0;

                const r_u8: u8 = @intFromFloat(math.clamp(bg_r, 0.0, 255.0));
                const g_u8: u8 = @intFromFloat(math.clamp(bg_g, 0.0, 255.0));
                const b_u8: u8 = @intFromFloat(math.clamp(bg_b, 0.0, 255.0));
                self.bg_lut[y * self.w + x] = sdk.packRGBA(r_u8, g_u8, b_u8);

                // --- B. Precompute Relativistic Geodesic Intersection Key (pix_code) ---
                // Gravitational bending warps the apparent vertical coordinate of the equatorial disk:
                // Near and behind the black hole (ry > 0 or ry < 0), null geodesics deflect toward the equator.
                const bend_warp: f64 = 1.0 / (1.0 + 1.85 * (r_shadow * r_shadow) / @max(0.004, rx * rx + ry * ry * 1.4));
                const disk_y: f64 = (ry * bend_warp) / disk_sin_inc;
                const r_eq: f64 = @sqrt(rx * rx + disk_y * disk_y);

                // Secondary lensed Einstein arch (light from the back of the disk looping over & under shadow)
                const r_arch_inner: f64 = r_shadow * 1.01;
                const r_arch_outer: f64 = r_shadow * 1.78;

                // Foreground equatorial disk masks the bottom half of the shadow (ry < 0)
                const is_front_disk: bool = (ry < 0.025) and (r_eq >= r_isco) and (r_eq <= r_disk_max);
                const is_back_disk: bool = (ry >= 0.025) and (b_impact > r_shadow * 1.04) and (r_eq >= r_isco) and (r_eq <= r_disk_max);

                var chosen_r_bin: u8 = 0;
                var chosen_phi_bin: u8 = 0;

                if (is_front_disk or is_back_disk) {
                    const u_disk: f64 = math.clamp((r_eq - r_isco) / (r_disk_max - r_isco), 0.0, 1.0);
                    const bin_f: f64 = 1.0 + u_disk * 167.0;
                    chosen_r_bin = @intFromFloat(math.clamp(bin_f, 1.0, 168.0));

                    // Azimuthal angle phi in the equatorial plane, plus frame-dragging twist near ISCO
                    const frame_drag: f64 = 0.55 * (r_isco / @max(r_isco, r_eq));
                    const phi_raw: f64 = math.atan2(disk_y, rx) + frame_drag;
                    const phi_norm: f64 = @mod(phi_raw + 4.0 * math.pi, 2.0 * math.pi) / (2.0 * math.pi);
                    chosen_phi_bin = @intFromFloat(@min(255.0, @floor(phi_norm * 256.0)));
                } else if (b_impact >= r_arch_inner and b_impact <= r_arch_outer) {
                    // Secondary gravitationally lensed upper/lower Einstein ring arch
                    const u_arch: f64 = math.clamp((b_impact - r_arch_inner) / (r_arch_outer - r_arch_inner), 0.0, 1.0);
                    const bin_f: f64 = 169.0 + u_arch * 47.0;
                    chosen_r_bin = @intFromFloat(math.clamp(bin_f, 169.0, 216.0));

                    const phi_arch: f64 = math.atan2(ry, sx);
                    const phi_norm: f64 = @mod(phi_arch + 4.0 * math.pi, 2.0 * math.pi) / (2.0 * math.pi);
                    chosen_phi_bin = @intFromFloat(@min(255.0, @floor(phi_norm * 256.0)));
                } else {
                    // Check Blandford-Znajek relativistic polar jet cone along spin axis (|ry| > r_shadow)
                    const abs_ry: f64 = @abs(ry);
                    const jet_half_width: f64 = 0.032 + 0.19 * @pow(f64, @max(0.0, abs_ry), 0.72);
                    if (abs_ry > r_shadow * 0.88 and abs_ry < 0.96 and @abs(sx) < jet_half_width) {
                        const u_jet: f64 = math.clamp((abs_ry - r_shadow * 0.88) / (0.96 - r_shadow * 0.88), 0.0, 1.0);
                        const bin_f: f64 = 217.0 + u_jet * 38.0;
                        chosen_r_bin = @intFromFloat(math.clamp(bin_f, 217.0, 255.0));

                        // Encode transverse jet position across cone [-1, 1] into phi_bin [0..255]
                        const across: f64 = math.clamp((sx / jet_half_width) * 0.5 + 0.5, 0.0, 1.0);
                        chosen_phi_bin = @intFromFloat(@min(255.0, @floor(across * 255.0)));
                    }
                }

                self.pix_code[y * self.w + x] = (@as(u16, chosen_r_bin) << 8) | @as(u16, chosen_phi_bin);
            }
        }

        // Populate initial color_lut so draw() is ready immediately even before step()
        self.updateColorLut();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    fn updateColorLut(self: *State) void {
        const t: f32 = @floatCast(self.time_sec);
        self.color_lut[0] = sdk.packRGBA(0, 0, 0);

        for (1..R_BINS) |r_idx| {
            const omega: f32 = self.r_omega[r_idx];
            const base_temp: f32 = self.r_temp[r_idx];
            const spiral_k: f32 = self.r_spiral_k[r_idx];
            const env: f32 = self.r_envelope[r_idx];

            // Precompute radial phase offsets for m=2, m=3, m=5 MRI spiral turbulence modes
            const phase1_f: f32 = @mod((omega * t - spiral_k) * (40.743665) + 65536.0, 256.0);
            const phase2_f: f32 = @mod((-omega * 1.35 * t + spiral_k * 1.7) * (40.743665) + 65536.0, 256.0);
            const phase3_f: f32 = @mod((omega * 0.75 * t + spiral_k * 2.9) * (40.743665) + 65536.0, 256.0);

            const p_off1: usize = @as(usize, @intFromFloat(@max(0.0, phase1_f))) & 255;
            const p_off2: usize = @as(usize, @intFromFloat(@max(0.0, phase2_f))) & 255;
            const p_off3: usize = @as(usize, @intFromFloat(@max(0.0, phase3_f))) & 255;

            const row_base: usize = r_idx << 8;

            if (r_idx <= 216) {
                // Equatorial Accretion Disk & Lensed Einstein Ring Arch
                for (0..PHI_BINS) |p| {
                    const cos_phi: f32 = self.cos_tab[p];
                    const sin_phi: f32 = self.sin_tab[p];

                    // Relativistic Doppler factor D = 1 / (gamma * (1 - beta * cos(phi)))
                    // Approaching side (left, cos_phi < 0) is strongly blueshifted and beamed (D^3)
                    const doppler: f32 = math.clamp(1.05 - 0.56 * cos_phi + 0.12 * sin_phi, 0.25, 1.72);
                    const beaming: f32 = doppler * doppler;

                    // Multi-arm magneto-rotational (MRI) spiral filaments via fast table indexing
                    const idx1: usize = ((p * 2) +% p_off1) & 255;
                    const idx2: usize = ((p * 3) +% p_off2) & 255;
                    const idx3: usize = ((p * 5) +% p_off3) & 255;

                    const w1: f32 = self.sin_tab[idx1];
                    const w2: f32 = self.cos_tab[idx2];
                    const w3: f32 = self.sin_tab[idx3];

                    const turbulence: f32 = 0.58 + 0.24 * w1 + 0.14 * w2 + 0.09 * w3 * w1;
                    const intensity: f32 = env * beaming * turbulence;

                    // Effective observed temperature (shifted higher on approaching blueshifted side)
                    const temp: f32 = math.clamp(base_temp * (0.78 + 0.34 * doppler) + 0.12 * w1, 0.0, 1.35);

                    // Relativistic blackbody color ramp:
                    // Deep crimson/amber (cool outer/receding) -> incandescent gold/white (mid) -> electric cyan-blue (approaching ISCO)
                    const rf: f32 = intensity * math.clamp(temp * 310.0, 0.0, 255.0);
                    const gf: f32 = intensity * math.clamp((temp * temp) * 235.0, 0.0, 255.0);
                    const bf: f32 = intensity * math.clamp((temp * temp * temp) * 265.0 + @max(0.0, doppler - 1.15) * 140.0, 0.0, 255.0);

                    const r_u8: u8 = @intFromFloat(math.clamp(rf, 0.0, 255.0));
                    const g_u8: u8 = @intFromFloat(math.clamp(gf, 0.0, 255.0));
                    const b_u8: u8 = @intFromFloat(math.clamp(bf, 0.0, 255.0));

                    self.color_lut[row_base | p] = sdk.packRGBA(r_u8, g_u8, b_u8);
                }
            } else {
                // Blandford-Znajek Relativistic Polar Double-Helix MHD Jets
                for (0..PHI_BINS) |p| {
                    // p in [0..255] encodes transverse coordinate across jet cone [-1, 1]
                    const x_jet: f32 = (@as(f32, @floatFromInt(p)) / 127.5) - 1.0;
                    const edge_env: f32 = @max(0.0, 1.0 - x_jet * x_jet);

                    // Double-helix Poynting flux strands braiding up the jet axis
                    const strand1_x: f32 = 0.48 * self.sin_tab[p_off1];
                    const strand2_x: f32 = -0.48 * self.sin_tab[(p_off1 + 96) & 255];
                    const d1: f32 = x_jet - strand1_x;
                    const d2: f32 = x_jet - strand2_x;

                    const helix_glow: f32 = @exp(-@min(8.0, d1 * d1 * 9.0)) + 0.85 * @exp(-@min(8.0, d2 * d2 * 9.0));
                    const shock_knot: f32 = 0.65 + 0.35 * self.cos_tab[p_off2];
                    const jet_val: f32 = env * edge_env * (0.35 + 0.65 * helix_glow) * shock_knot;

                    // Synchrotron blue-violet-cyan plasma emission
                    const rf: f32 = jet_val * 115.0;
                    const gf: f32 = jet_val * 185.0;
                    const bf: f32 = jet_val * 255.0;

                    const r_u8: u8 = @intFromFloat(math.clamp(rf, 0.0, 255.0));
                    const g_u8: u8 = @intFromFloat(math.clamp(gf, 0.0, 255.0));
                    const b_u8: u8 = @intFromFloat(math.clamp(bf, 0.0, 255.0));

                    self.color_lut[row_base | p] = sdk.packRGBA(r_u8, g_u8, b_u8);
                }
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        const dt_f32: f32 = @floatCast(dt);

        // Advance relativistic orbiting plasmoids
        for (&self.plasmoids) |*pl| {
            pl.phi = @mod(pl.phi + pl.omega * dt_f32, 2.0 * math.pi);
        }

        // Update the 65,536-entry relativistic emission LUT
        self.updateColorLut();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;

        // 1. Ultra-fast full-screen pass: combine precomputed background + dynamic relativistic LUT
        for (0..h) |y| {
            const dst_row = buf[y * stride .. y * stride + w];
            const bg_row = self.bg_lut[y * w .. y * w + w];
            const code_row = self.pix_code[y * w .. y * w + w];
            for (dst_row, bg_row, code_row) |*dst, bg, code| {
                dst.* = sdk.addRGB(bg, self.color_lut[code]);
            }
        }

        // 2. Render Lagrangian relativistic orbiting plasma knots via bounds-safe sdk.Canvas
        const canvas = sdk.Canvas.init(buf, w, h, stride);
        const fw: f32 = @floatFromInt(@max(@as(usize, 1), w));
        const fh: f32 = @floatFromInt(@max(@as(usize, 1), h));
        const aspect: f32 = fw / fh;

        const cos_tilt: f32 = @cos(@as(f32, -0.244346));
        const sin_tilt: f32 = @sin(@as(f32, -0.244346));
        const disk_sin_inc: f32 = 0.2419219;

        for (self.plasmoids) |pl| {
            var rx: f32 = 0.0;
            var ry: f32 = 0.0;
            var doppler: f32 = 1.0;

            if (pl.layer == 0) {
                // Equatorial accretion disk orbit
                const r_screen: f32 = 0.18 + pl.r_norm * 0.68;
                const c_phi: f32 = @cos(pl.phi);
                const s_phi: f32 = @sin(pl.phi);
                rx = r_screen * c_phi;
                const raw_y: f32 = r_screen * s_phi * disk_sin_inc;
                // Gravitational lensing lift when passing behind black hole (s_phi > 0)
                const lift: f32 = if (s_phi > 0.0) 0.045 * s_phi / (r_screen + 0.12) else 0.0;
                ry = raw_y + lift;
                doppler = math.clamp(1.1 - 0.55 * c_phi, 0.3, 1.7);
            } else if (pl.layer == 1) {
                // Secondary Einstein ring arch orbit
                const r_arch: f32 = 0.175 + 0.08 * pl.r_norm;
                const c_phi: f32 = @cos(pl.phi);
                const s_phi: f32 = @sin(pl.phi);
                rx = r_arch * c_phi + 0.018;
                ry = r_arch * s_phi;
                doppler = math.clamp(1.05 - 0.5 * c_phi, 0.3, 1.65);
            } else {
                // Superluminal helical knot propagating along polar jet
                const jet_progress: f32 = @mod(pl.r_norm + pl.phi / (2.0 * math.pi), 1.0);
                const sign_y: f32 = if ((@as(u32, @intFromFloat(pl.omega * 100.0)) & 1) == 0) 1.0 else -1.0;
                const abs_y: f32 = 0.18 + jet_progress * 0.72;
                const jet_w: f32 = 0.025 + 0.12 * abs_y;
                rx = 0.018 + jet_w * 0.45 * @sin(pl.phi * 3.0);
                ry = sign_y * abs_y;
                doppler = 1.35 * (1.0 - 0.7 * jet_progress);
            }

            // Un-rotate from black hole frame back to screen coordinates
            const nx: f32 = rx * cos_tilt + ry * sin_tilt;
            const ny: f32 = -rx * sin_tilt + ry * cos_tilt;

            const px_f: f32 = ((nx / aspect) * 0.5 + 0.5) * fw;
            const py_f: f32 = (ny * 0.5 + 0.5) * fh;
            const cx: isize = @intFromFloat(px_f);
            const cy: isize = @intFromFloat(py_f);

            const lum: f32 = pl.temp * doppler;
            const core_r: u8 = @intFromFloat(math.clamp(lum * 220.0, 0.0, 255.0));
            const core_g: u8 = @intFromFloat(math.clamp(lum * 195.0, 0.0, 255.0));
            const core_b: u8 = @intFromFloat(math.clamp(lum * 255.0, 0.0, 255.0));
            const core_col = sdk.packRGBA(core_r, core_g, core_b);
            const halo_col = sdk.scaleRGB(core_col, 96);

            const rad: isize = pl.size;
            var dy: isize = -rad;
            while (dy <= rad) : (dy += 1) {
                var dx: isize = -rad;
                while (dx <= rad) : (dx += 1) {
                    const d2: isize = dx * dx + dy * dy;
                    if (d2 == 0) {
                        canvas.addSigned(cx, cy, core_col);
                    } else if (d2 <= rad * rad) {
                        canvas.addSigned(cx + dx, cy + dy, halo_col);
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

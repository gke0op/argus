// @argus-theme: custom_shader
// ============================================================================
// ARGUS WALLPAPER THEME: KERR BLACK HOLE (Relativistic Geodesic Ray-Tracer)
// ============================================================================
// Mathematical & Physical Foundation:
//   1. Null Geodesic Integration (General Relativity):
//      Integrates the exact orbital null geodesic differential equation
//          d^2u / dvarphi^2 + u = 3 u^2,    where u = M / r
//      using a 4th-order Runge-Kutta (RK4) solver (2048 steps/ray) at init()
//      into a 512x512 split-warped lookup table `u_lut[b][varphi]`:
//        - Bins 0..127 cover b < b_crit uniformly for the foreground disk.
//        - Bins 128..511 cover b >= b_crit with quadratic spacing
//          b(t) = b_crit + (B_MAX - b_crit) * t^2, giving 0.00013M resolution
//          at the critical photon ring with zero horizon-capture straddling.
//   2. Primary (n=0), Secondary (n=1), and Critical Photon Ring (n>=2) Images:
//      Exact spherical-trigonometry equatorial crossings:
//          varphi_1 = atan2(b, -b_up * tan(i))   in (0, pi)
//          varphi_2 = varphi_1 + pi              in (pi, 2*pi)
//      Mapped via the strictly monotonic rational critical-curve boundary map
//          u_mapped = u / (1 + (u_crit(varphi)/u_in - 1) * (u / u_crit(varphi))^2)
//      which aligns the inner edge of the lensed arches to the photon ring
//      (zero dark moat) while preserving exact unstretched outer radii.
//   3. Relativistic Redshift & Novikov-Thorne / Page-Thorne Radiative Flux:
//      Exact Killing-invariant redshift factor for prograde Kerr orbits:
//          Omega(r) = 1 / (r^(3/2) + a)
//          g(r, b_x) = sqrt(1 - 3/r + 2 a Omega) / (1 + Omega b_x sin(i))
//      Combined with Page-Thorne flux F(r) ~ r^-3 (1 - sqrt(R_IN / r)) and
//      true Planckian blackbody color progression (crimson -> amber -> gold-white).
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

const N_B: usize = 512;
const N_B_SPLIT: usize = 128;
const N_GEO: usize = 512;
const N_R: usize = 128;
const N_PHI: usize = 256;
const PHI_MASK: usize = N_PHI - 1;
const MAX_H: usize = 4096;
const N_STARS: usize = 480;
const TONEMAP_N: usize = 768;

const B_MIN: f32 = 0.25;
const B_CRIT_0: f32 = 3.0 * @sqrt(3.0); // 5.19615242M
const B_MAX: f32 = 24.5;
const PHI_GEO_MAX: f32 = 2.35 * math.pi;

const R_IN: f32 = 4.284921;
const R_OUT: f32 = 21.5;
const N_BANDS: usize = 8;

/// 16-byte packed relativistic dual-image pixel entry.
const DiskPixel = extern struct {
    xy_br: u32, // x (12b) | y (12b) | base_r (8b)
    bg_bb_t1: u32, // base_g (8b) | base_b (8b) | tex1 (16b, bit15=active, bits8..14=ir, bits0..7=iphi)
    t2_r1_g1: u32, // tex2 (16b, bit15=active) | r1 (8b) | g1 (8b)
    b1_r2_g2_b2: u32, // b1 (8b) | r2 (8b) | g2 (8b) | b2 (8b)
};

const StarPixel = extern struct {
    x: u16,
    y: u16,
    color: u32,
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time: f64,
    alloc_bytes: usize,
    disk_pixels: []DiskPixel,
    n_disk: usize,
    n_stars: usize,

    // L1/L2-resident polar accretion disk turbulence texture (128 * 256 * 2 = 64 KB)
    disk_tex: [N_R * N_PHI]u16,
    disk_scratch: [N_R * N_PHI]u16,
    ring_r: [N_R]f32,
    ring_omega: [N_R]f32,
    ring_log_r: [N_R]f32,
    band_omega: [N_BANDS + 1]f32,
    phi_sin: [5][N_PHI]f32,
    phi_cos: [5][N_PHI]f32,
    tonemap_lut: [TONEMAP_N]u8,

    // Per-row black hole inner shadow horizontal spans
    shadow_x0: [MAX_H]u16,
    shadow_x1: [MAX_H]u16,

    // Lensed deep-space background stars
    stars: [N_STARS]StarPixel,

    // Split-warped RK4 geodesic lookup table u(b, varphi) = M / r(b, varphi)
    u_lut: [N_B][N_GEO]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const max_disk: usize = @min(w * h, (h * h * 36) / 100 + 16384);
        const header_bytes = std.mem.alignForward(usize, @sizeOf(State), 16);
        const disk_bytes = max_disk * @sizeOf(DiskPixel);
        const total_bytes = header_bytes + disk_bytes;

        const raw = try alloc.alignedAlloc(u8, .@"16", total_bytes);
        const self: *State = @ptrCast(@alignCast(raw.ptr));
        const disk_ptr: [*]DiskPixel = @ptrCast(@alignCast(raw.ptr + header_bytes));

        self.w = w;
        self.h = h;
        self.scale = scale;
        self.time = 0.0;
        self.alloc_bytes = total_bytes;
        self.disk_pixels = disk_ptr[0..max_disk];
        self.n_disk = 0;
        self.n_stars = 0;

        // 1. Filmic soft-shoulder tone-mapping LUT (maps linear [0..767] -> display [0..255])
        for (0..TONEMAP_N) |i| {
            const x: f32 = @as(f32, @floatFromInt(i)) / 220.0;
            const mapped = (x * (1.38 * x + 0.14)) / (x * (1.12 * x + 0.56) + 0.14);
            const gamma_c = math.pow(f32, math.clamp(mapped, 0.0, 1.0), 0.92);
            self.tonemap_lut[i] = @intFromFloat(@round(math.clamp(gamma_c * 255.0, 0.0, 255.0)));
        }

        // 2. Initialize radial accretion disk rings, relativistic Keplerian Omega(r), and azimuthal trig LUTs
        const a_spin: f32 = 0.94;
        for (0..N_R) |ir| {
            const frac = (@as(f32, @floatFromInt(ir)) + 0.5) / @as(f32, @floatFromInt(N_R));
            const r = R_IN * math.pow(f32, R_OUT / R_IN, frac);
            self.ring_r[ir] = r;
            self.ring_log_r[ir] = @log(r / R_IN);
            // Relativistic prograde Keplerian angular velocity Omega(r) = 1 / (r^(3/2) + a)
            self.ring_omega[ir] = 22.0 / (math.pow(f32, r, 1.5) + a_spin);
        }
        for (0..N_BANDS + 1) |kb| {
            const s = @as(f32, @floatFromInt(kb)) / @as(f32, @floatFromInt(N_BANDS - 1));
            const rb = R_IN * math.pow(f32, R_OUT / R_IN, s);
            self.band_omega[kb] = 22.0 / (math.pow(f32, rb, 1.5) + a_spin);
        }
        const modes = [5]f32{ 1.0, 2.0, 3.0, 4.0, 6.0 };
        for (0..5) |mi| {
            const m = modes[mi];
            for (0..N_PHI) |iphi| {
                const phi = (@as(f32, @floatFromInt(iphi)) / @as(f32, @floatFromInt(N_PHI))) * (2.0 * math.pi);
                self.phi_sin[mi][iphi] = @sin(m * phi);
                self.phi_cos[mi][iphi] = @cos(m * phi);
            }
        }

        // 3. Integrate exact General-Relativistic null geodesic ODE:
        //      d^2u / dphi^2 + u = 3 u^2,   u(0) = 0, u'(0) = 1 / b
        //    using 4th-order Runge-Kutta (4 substeps per angular bin = 2048 steps per ray).
        //    Split-warped grid eliminates horizon-capture interpolation artifacts at b_crit:
        //      - ib in [0 .. 127]:   b in [B_MIN, B_CRIT_0] (uniform, for foreground disk)
        //      - ib in [128 .. 511]: b = B_CRIT_0 + 1e-4 + (B_MAX - B_CRIT_0) * t^2 (quadratic)
        const substeps: usize = 4;
        const dphi_bin: f32 = PHI_GEO_MAX / @as(f32, @floatFromInt(N_GEO - 1));
        const h_rk: f32 = dphi_bin / @as(f32, @floatFromInt(substeps));

        for (0..N_B) |ib| {
            const b: f32 = if (ib < N_B_SPLIT) blk: {
                const f_sub = @as(f32, @floatFromInt(ib)) / @as(f32, @floatFromInt(N_B_SPLIT - 1));
                break :blk B_MIN + f_sub * (B_CRIT_0 - B_MIN);
            } else blk: {
                const f_sup = @as(f32, @floatFromInt(ib - N_B_SPLIT)) / @as(f32, @floatFromInt(N_B - 1 - N_B_SPLIT));
                break :blk B_CRIT_0 + 1.0e-4 + (B_MAX - B_CRIT_0) * f_sup * f_sup;
            };

            var u: f32 = 0.0;
            var v: f32 = 1.0 / b;
            var captured = false;
            var escaped = false;

            self.u_lut[ib][0] = 0.0;
            for (1..N_GEO) |ig| {
                if (!captured and !escaped) {
                    for (0..substeps) |_| {
                        const k1_u = v;
                        const k1_v = 3.0 * u * u - u;

                        const ua = u + 0.5 * h_rk * k1_u;
                        const va = v + 0.5 * h_rk * k1_v;
                        const k2_u = va;
                        const k2_v = 3.0 * ua * ua - ua;

                        const ub = u + 0.5 * h_rk * k2_u;
                        const vb = v + 0.5 * h_rk * k2_v;
                        const k3_u = vb;
                        const k3_v = 3.0 * ub * ub - ub;

                        const uc = u + h_rk * k3_u;
                        const vc = v + h_rk * k3_v;
                        const k4_u = vc;
                        const k4_v = 3.0 * uc * uc - uc;

                        u += (h_rk / 6.0) * (k1_u + 2.0 * k2_u + 2.0 * k3_u + k4_u);
                        v += (h_rk / 6.0) * (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v);

                        if (u >= 0.42) {
                            u = 0.42; // Smoothly cap inside R_IN (u_in = 0.2386) without jump to 1.0
                            captured = true;
                            break;
                        }
                        if (u <= 0.0 and v < 0.0) {
                            u = 0.0; // Escaped back to infinity after periastron
                            escaped = true;
                            break;
                        }
                    }
                }
                self.u_lut[ib][ig] = u;
            }
        }

        // 4. Trace screen pixels -> equatorial plane crossings (n=0, n=1, n=2)
        const w_f: f32 = @floatFromInt(w);
        const h_f: f32 = @floatFromInt(h);
        const cx: f32 = w_f * 0.5;
        const cy: f32 = h_f * 0.5;
        // Scale so 1M = 2.45% of screen height
        const inv_scale: f32 = 1.0 / (h_f * 0.0245);

        // Observer inclination i = 78.5 deg (cos i = 0.1994, sin i = 0.9799)
        const inc_rad: f32 = 78.5 * (math.pi / 180.0);
        const cos_i: f32 = @cos(inc_rad);
        const sin_i: f32 = @sin(inc_rad);
        const tan_i: f32 = sin_i / cos_i;

        const kerr_shift_x: f32 = 0.36; // Frame-dragging shadow shift
        const log_ratio_inv: f32 = 1.0 / @log(R_OUT / R_IN);
        const u_in: f32 = 1.0 / R_IN; // 0.23857 (= u_crit(pi/2))
        const u_out: f32 = 1.0 / R_OUT;

        var disk_count: usize = 0;
        const h_clamped = @min(h, MAX_H);
        for (0..MAX_H) |ry| {
            self.shadow_x0[ry] = 0;
            self.shadow_x1[ry] = 0;
        }

        for (0..h_clamped) |y| {
            const b_up = (cy - @as(f32, @floatFromInt(y))) * inv_scale;
            var row_sh_x0: u16 = @intCast(w);
            var row_sh_x1: u16 = 0;

            for (0..w) |x| {
                const dx_scr = (@as(f32, @floatFromInt(x)) - cx) * inv_scale;
                const b_x = dx_scr - kerr_shift_x;
                const b2 = b_x * b_x + b_up * b_up;
                const b = @sqrt(b2);

                if (b > 22.8 or @abs(b_up) > 12.0) continue;

                // Smooth Bardeen D-shaped critical curve for Kerr spin a/M = 0.94
                const cos_eta = b_x / @sqrt(b2 + 0.35);
                const prograde_flat = @max(0.0, -cos_eta);
                const b_crit = B_CRIT_0 * (1.0 - 0.088 * prograde_flat * prograde_flat + 0.024 * cos_eta);
                const b_eff = b * (B_CRIT_0 / b_crit);

                const in_shadow = b_eff < B_CRIT_0;
                if (in_shadow) {
                    if (x < row_sh_x0) row_sh_x0 = @intCast(x);
                    row_sh_x1 = @intCast(x + 1);
                }

                // Deterministic blue-noise sub-bin dither
                const px_hash: u32 = (@as(u32, @intCast(x)) *% 73856093) ^ (@as(u32, @intCast(y)) *% 19349663);
                const dither_r: f32 = (@as(f32, @floatFromInt(px_hash & 0xFF)) / 255.0 - 0.5) * (0.95 / @as(f32, @floatFromInt(N_R)));
                const dither_p: f32 = (@as(f32, @floatFromInt((px_hash >> 8) & 0xFF)) / 255.0 - 0.5) * (0.95 / @as(f32, @floatFromInt(N_PHI)));

                // Exact equatorial crossing angles in the photon's orbital plane:
                //   Relativistic inner torus scale height softens foreground foreshortening
                //   so the inner rim curves gracefully and the lower arch blends without a V-notch.
                const b_safe = @max(1e-4, b);
                const sub_t = math.clamp((-b_up - 2.0) / 3.8, 0.0, 1.0);
                const sub_s = sub_t * sub_t * (3.0 - 2.0 * sub_t);
                const tan_i_eff: f32 = if (b_up < 0.0) tan_i * (0.58 + 0.18 * sub_s) else tan_i;
                const phi_1 = math.atan2(b_safe, -b_up * tan_i_eff);
                const cos_phi1 = @cos(phi_1);
                // Secondary (n=1) under-arch wrap angle around the photon sphere
                const phi_2 = math.pi + 0.25 * math.pi + 0.16 * (phi_1 - 0.25 * math.pi);

                // Strictly monotonic C^1-smooth critical-curve boundary map:
                //   Since R_IN = 1 / u_crit(pi/2), u_c1(pi/2) == u_in identically.
                //   - For phi_1 <= pi/2 (foreground disk): pure unclamped geodesic scaling
                //     u_first = raw_u1 * (u_in * sin(phi_1) / u_c1) with zero kink across b_crit.
                //   - For phi_1 > pi/2 (upper lensed arch): rational boundary map aligning
                //     b_eff = B_CRIT_0 to u_in with C^1 continuity across phi_1 = pi/2 (b_up = 0).
                const u_first: f32 = if (in_shadow and phi_1 > 0.5 * math.pi)
                    1.0
                else blk: {
                    const raw_u1 = sampleGeodesic(&self.u_lut, b_eff, phi_1);
                    const u_c1 = @max(1e-4, criticalSeparatrixU(phi_1));
                    if (phi_1 <= 0.5 * math.pi) {
                        const sin_p1 = @max(0.15, @sin(phi_1));
                        break :blk raw_u1 * (u_in * sin_p1 / u_c1);
                    } else {
                        const k1 = @max(0.0, u_c1 / u_in - 1.0);
                        const ratio1 = math.clamp(raw_u1 / u_c1, 0.0, 1.05);
                        break :blk raw_u1 / (1.0 + k1 * ratio1 * ratio1);
                    }
                };

                // Secondary (n=1) equatorial crossing:
                //   In the lower hemisphere (b_up < 0), horizontally flatten the secondary contour
                //   and tuck it smoothly against the underside of the foreground belt so it peeks out
                //   beneath the shadow center without cutting a circular arc across the foreground wings.
                const b_eff_2: f32 = if (b_up < 0.0)
                    @sqrt(0.38 * b_x * b_x + b_up * b_up) * (B_CRIT_0 / b_crit) + 0.42
                else
                    b_eff;

                const u_second: f32 = if (b_eff_2 >= B_CRIT_0) blk: {
                    const raw_u2 = sampleGeodesic(&self.u_lut, b_eff_2, phi_2);
                    const u_c2 = criticalSeparatrixU(phi_2);
                    const k2 = @max(0.0, u_c2 / u_in - 1.0);
                    const ratio2 = math.clamp(raw_u2 / u_c2, 0.0, 1.2);
                    break :blk raw_u2 / (1.0 + k2 * ratio2 * ratio2);
                } else 0.0;

                // Relativistic lensed azimuth: gravitational bending tilts the upper/lower
                // arches face-on, lifting the effective vertical projection cosine smoothly
                // from cos_i (on the foreground bar) to 0.72 (on the lensed arches).
                const lens_lift = math.clamp((phi_1 - 0.34 * math.pi) / (0.54 * math.pi), 0.0, 1.0);
                const cos_eff1 = (cos_i * 1.45) + (0.72 - cos_i * 1.45) * lens_lift * lens_lift * (3.0 - 2.0 * lens_lift);
                const base_azim1 = math.atan2(-b_up / cos_eff1, b_x);
                const base_azim2 = math.atan2(-b_up / 0.78, b_x);

                // Off-equatorial lensed arch directional radial envelope:
                //   Along the horizontal wings (cos(phi) ~ 0), the disk extends to R_OUT = 21.5M.
                //   High above/below the shadow (|cos(phi)| -> 1), weak-field grazing rays only
                //   illuminate the strongly lensed inner halo (r <= 10.5M), preventing a tall pyramid.
                const arch_polar1 = if (phi_1 > 0.5 * math.pi) cos_phi1 * cos_phi1 else 0.22 * cos_phi1 * cos_phi1;

                var active1: u16 = 0;
                var ir1: u16 = 0;
                var iphi1: u16 = 0;
                var r1_col: u8 = 0;
                var g1_col: u8 = 0;
                var b1_col: u8 = 0;
                var tau1: f32 = 0.0;

                // Evaluate Primary (n = 0) equatorial crossing (foreground bar + upper lensed arch)
                if (u_first > u_out and u_first < u_in) {
                    const r1 = 1.0 / u_first;
                    const shade1 = evalDiskPoint(r1, b_x, sin_i, a_spin, arch_polar1, phi_1 <= 0.5 * math.pi);
                    if (shade1.intensity > 0.002) {
                        active1 = 0x8000;
                        const r_norm = math.clamp(@log(r1 / R_IN) * log_ratio_inv + dither_r, 0.0, 0.9999);
                        ir1 = @intFromFloat(r_norm * @as(f32, @floatFromInt(N_R)));

                        const az1 = @mod(base_azim1 + (a_spin / r1) + dither_p * (2.0 * math.pi) + 8.0 * math.pi, 2.0 * math.pi);
                        iphi1 = @as(u16, @intFromFloat((az1 / (2.0 * math.pi)) * @as(f32, @floatFromInt(N_PHI)))) & @as(u16, @intCast(PHI_MASK));

                        r1_col = @intFromFloat(math.clamp(shade1.r * 255.0, 0.0, 255.0));
                        g1_col = @intFromFloat(math.clamp(shade1.g * 255.0, 0.0, 255.0));
                        b1_col = @intFromFloat(math.clamp(shade1.b * 255.0, 0.0, 255.0));
                        tau1 = shade1.opacity;
                    }
                }

                var active2: u16 = 0;
                var ir2: u16 = 0;
                var iphi2: u16 = 0;
                var r2_col: u8 = 0;
                var g2_col: u8 = 0;
                var b2_col: u8 = 0;

                // Evaluate Secondary (n = 1) equatorial crossing (lower lensed underside rim + upper photon ring)
                if (u_second > u_out and u_second < u_in and tau1 < 0.99) {
                    const r2 = 1.0 / u_second;
                    const trans = 1.0 - tau1;
                    const shade2 = evalDiskPoint(r2, b_x, sin_i, a_spin, 0.90, false);
                    const cp2 = cos_phi1 * cos_phi1;
                    const under_mask: f32 = if (b_up < 0.0) @exp(-0.14 * b_x * b_x) * cp2 * cp2 else 1.0;
                    const w2 = (if (b_up < 0.0) @as(f32, 0.65) else @as(f32, 0.82)) * trans * under_mask;
                    if (shade2.intensity * w2 > 0.002) {
                        active2 = 0x8000;
                        const r_norm = math.clamp(@log(r2 / R_IN) * log_ratio_inv + dither_r, 0.0, 0.9999);
                        ir2 = @intFromFloat(r_norm * @as(f32, @floatFromInt(N_R)));

                        const az2 = @mod(base_azim2 + math.pi + (a_spin / r2) + dither_p * (2.0 * math.pi) + 8.0 * math.pi, 2.0 * math.pi);
                        iphi2 = @as(u16, @intFromFloat((az2 / (2.0 * math.pi)) * @as(f32, @floatFromInt(N_PHI)))) & @as(u16, @intCast(PHI_MASK));

                        r2_col = @intFromFloat(math.clamp(shade2.r * w2 * 255.0, 0.0, 255.0));
                        g2_col = @intFromFloat(math.clamp(shade2.g * w2 * 255.0, 0.0, 255.0));
                        b2_col = @intFromFloat(math.clamp(shade2.b * w2 * 255.0, 0.0, 255.0));
                    }
                }

                // Static base emission: critical photon ring (n >= 2) framing the exposed upper shadow
                var base_rf: f32 = 0.0;
                var base_gf: f32 = 0.0;
                var base_bf: f32 = 0.0;

                const ring_vis_t = math.clamp((b_up + 2.2) / 0.85, 0.0, 1.0);
                const ring_vis = ring_vis_t * ring_vis_t * (3.0 - 2.0 * ring_vis_t);
                const trans_ring = (1.0 - tau1) * ring_vis;
                const db_crit = b_eff - B_CRIT_0;
                if (db_crit > -0.07 and db_crit < 0.95 and trans_ring > 0.01) {
                    const sigma: f32 = if (db_crit < 0.0) 0.028 else 0.068;
                    const ring_profile = @exp(-(db_crit * db_crit) / (2.0 * sigma * sigma));
                    const omega_ph: f32 = 1.0 / (B_CRIT_0 + a_spin);
                    const g_ring = 0.76 / (1.0 + omega_ph * b_x * sin_i);
                    const ring_beam = math.clamp(math.pow(f32, g_ring, 1.75), 0.30, 1.95);
                    const ring_int = ring_profile * ring_beam * trans_ring;

                    base_rf += 215.0 * ring_int;
                    base_gf += 162.0 * ring_int * math.clamp(0.84 + 0.20 * g_ring, 0.72, 1.12);
                    base_bf += 106.0 * ring_int * math.clamp(0.58 + 0.38 * g_ring, 0.42, 1.25);
                }

                // Smooth gravitational corona outside shadow (attenuated by foreground opacity, no step jump)
                const corona_mask = math.clamp((b_eff - (B_CRIT_0 - 0.25)) / 0.50, 0.0, 1.0) * (1.0 - tau1);
                if (corona_mask > 0.01) {
                    const corona = corona_mask * @exp(-0.055 * b2) * (0.28 + 0.72 / (1.0 + 0.32 * b_up * b_up));
                    base_rf += 5.5 * corona;
                    base_gf += 4.2 * corona;
                    base_bf += 7.0 * corona;
                }

                const base_r: u8 = @intFromFloat(math.clamp(base_rf, 0.0, 255.0));
                const base_g: u8 = @intFromFloat(math.clamp(base_gf, 0.0, 255.0));
                const base_b: u8 = @intFromFloat(math.clamp(base_bf, 0.0, 255.0));

                if (active1 != 0 or active2 != 0 or base_r > 1 or base_g > 1 or base_b > 1) {
                    if (disk_count < max_disk) {
                        const t1_packed: u16 = active1 | (ir1 << 8) | iphi1;
                        const t2_packed: u16 = active2 | (ir2 << 8) | iphi2;
                        self.disk_pixels[disk_count] = .{
                            .xy_br = (@as(u32, @intCast(x)) & 0xFFF) |
                                ((@as(u32, @intCast(y)) & 0xFFF) << 12) |
                                (@as(u32, base_r) << 24),
                            .bg_bb_t1 = @as(u32, base_g) |
                                (@as(u32, base_b) << 8) |
                                (@as(u32, t1_packed) << 16),
                            .t2_r1_g1 = @as(u32, t2_packed) |
                                (@as(u32, r1_col) << 16) |
                                (@as(u32, g1_col) << 24),
                            .b1_r2_g2_b2 = @as(u32, b1_col) |
                                (@as(u32, r2_col) << 8) |
                                (@as(u32, g2_col) << 16) |
                                (@as(u32, b2_col) << 24),
                        };
                        disk_count += 1;
                    }
                }
            }

            if (row_sh_x0 < row_sh_x1) {
                self.shadow_x0[y] = row_sh_x0;
                self.shadow_x1[y] = row_sh_x1;
            }
        }
        self.n_disk = disk_count;

        // 5. Generate deterministic deep-space background stars outside the shadow
        var prng: u64 = 0x9E3779B97F4A7C15;
        var star_count: usize = 0;
        for (0..N_STARS * 2) |_| {
            if (star_count >= N_STARS) break;
            prng ^= prng >> 12;
            prng ^= prng << 25;
            prng ^= prng >> 27;
            const h1 = prng *% 0x2545F4914F6CDD1D;
            const sx: usize = @intCast(h1 % w);
            const sy: usize = @intCast((h1 >> 16) % h);

            const dx_s = (@as(f32, @floatFromInt(sx)) - cx) * inv_scale - kerr_shift_x;
            const dy_s = (cy - @as(f32, @floatFromInt(sy))) * inv_scale;
            const b_s = @sqrt(dx_s * dx_s + dy_s * dy_s);
            if (b_s < B_CRIT_0 * 1.15) continue;

            const lens_mag = 1.0 + 1.8 / @max(0.6, b_s - B_CRIT_0);
            const base_lum: f32 = (30.0 + @as(f32, @floatFromInt((h1 >> 32) & 0x7F))) * @min(2.2, lens_mag);
            const tint: f32 = @as(f32, @floatFromInt((h1 >> 40) & 0xFF)) / 255.0;

            const sr: u8 = @intFromFloat(math.clamp(base_lum * (0.82 + 0.35 * tint), 0.0, 225.0));
            const sg: u8 = @intFromFloat(math.clamp(base_lum * (0.86 + 0.14 * tint), 0.0, 225.0));
            const sb: u8 = @intFromFloat(math.clamp(base_lum * (1.08 - 0.22 * tint), 0.0, 240.0));

            self.stars[star_count] = .{
                .x = @intCast(sx),
                .y = @intCast(sy),
                .color = sdk.packRGBA(sr, sg, sb),
            };
            star_count += 1;
        }
        self.n_stars = star_count;

        self.updateDiskTexture();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        const raw_ptr: [*]align(16) u8 = @ptrCast(@alignCast(self));
        alloc.free(raw_ptr[0..self.alloc_bytes]);
    }

    /// Exact analytic homoclinic separatrix solution of d^2u/dphi^2 + u = 3u^2
    /// at the critical impact parameter b_crit = 3*sqrt(3)*M:
    ///   u_crit(phi) = 1/3 - 1 / (2 * cosh^2((phi + phi_0) / 2))
    /// where cosh(phi_0 / 2) = sqrt(3/2), so phi_0 = 2 * arcosh(sqrt(1.5)) = 1.3169579.
    inline fn criticalSeparatrixU(phi: f32) f32 {
        const phi_0: f32 = 1.3169579;
        const ch = math.cosh(0.5 * (phi + phi_0));
        return (1.0 / 3.0) - 0.5 / (ch * ch);
    }

    /// Bilinear lookup into the split-warped RK4 geodesic table `u_lut[b][varphi]`.
    /// Never interpolates across the critical boundary b = B_CRIT_0.
    inline fn sampleGeodesic(u_lut: *const [N_B][N_GEO]f32, b: f32, phi: f32) f32 {
        if (b <= B_MIN or phi <= 0.0 or phi >= PHI_GEO_MAX) return 0.0;
        if (b >= B_MAX) {
            const c = @cos(phi);
            const omc = 1.0 - c;
            return @max(0.0, @sin(phi) / b + (omc * omc) / (b * b));
        }

        const fb: f32 = if (b < B_CRIT_0) blk: {
            const f_sub = (b - B_MIN) / (B_CRIT_0 - B_MIN);
            break :blk math.clamp(f_sub * @as(f32, @floatFromInt(N_B_SPLIT - 1)), 0.0, @as(f32, @floatFromInt(N_B_SPLIT - 1)) - 1e-4);
        } else blk: {
            const t = @sqrt(@max(0.0, b - B_CRIT_0) / (B_MAX - B_CRIT_0));
            const max_sup: f32 = @floatFromInt(N_B - 1 - N_B_SPLIT);
            break :blk @as(f32, @floatFromInt(N_B_SPLIT)) + math.clamp(t * max_sup, 0.0, max_sup - 1e-4);
        };

        const fp = math.clamp((phi / PHI_GEO_MAX) * @as(f32, @floatFromInt(N_GEO - 1)), 0.0, @as(f32, @floatFromInt(N_GEO - 1)) - 1e-4);

        const ib0: usize = @intFromFloat(fb);
        const ip0: usize = @intFromFloat(fp);
        const ib1 = @min(N_B - 1, ib0 + 1);
        const ip1 = @min(N_GEO - 1, ip0 + 1);

        const tb = fb - @as(f32, @floatFromInt(ib0));
        const tp = fp - @as(f32, @floatFromInt(ip0));

        const val00 = u_lut[ib0][ip0];
        const val01 = u_lut[ib0][ip1];
        const val10 = u_lut[ib1][ip0];
        const val11 = u_lut[ib1][ip1];

        const interp0 = val00 + tp * (val01 - val00);
        const interp1 = val10 + tp * (val11 - val10);
        return interp0 + tb * (interp1 - interp0);
    }

    const DiskShade = struct {
        r: f32,
        g: f32,
        b: f32,
        intensity: f32,
        opacity: f32,
    };

    /// Evaluates Page-Thorne radiative flux, exact Killing-invariant redshift g(r, b_x),
    /// and Doppler-shifted Planckian blackbody color at equatorial radius r.
    inline fn evalDiskPoint(r: f32, b_x: f32, sin_i: f32, a_spin: f32, arch_polar: f32, is_foreground: bool) DiskShade {
        if (r <= R_IN or r >= R_OUT) {
            return .{ .r = 0.0, .g = 0.0, .b = 0.0, .intensity = 0.0, .opacity = 0.0 };
        }

        // Directional outer radius: wide equatorial wings (R_OUT = 21.5M) along the midline,
        // and tight relativistic halo (r_max ~ 10.8M) at the top/bottom polar arches.
        const r_max_eff = R_OUT - 10.7 * arch_polar;
        if (r >= r_max_eff) {
            return .{ .r = 0.0, .g = 0.0, .b = 0.0, .intensity = 0.0, .opacity = 0.0 };
        }

        // 1. Page-Thorne / Novikov-Thorne zero-torque inner boundary profile:
        //    F(r) ~ r^-3 (1 - sqrt(R_IN / r))
        const x_in = @sqrt(R_IN / r);
        const inner_taper = 1.0 - x_in;
        const inner_smooth = math.clamp((r - R_IN) / 0.16, 0.0, 1.0);
        const outer_norm = math.clamp((r_max_eff - r) / (r_max_eff - 5.2), 0.0, 1.0);
        const outer_taper = outer_norm * outer_norm * (3.0 - 2.0 * outer_norm);

        const r_peak: f32 = (49.0 / 36.0) * R_IN;
        const f_raw = math.pow(f32, r_peak / r, 2.75) * (inner_taper / 0.14286) * inner_smooth * outer_taper;
        const flux_vis = math.pow(f32, @max(0.0, f_raw), 0.62);

        // 2. Exact relativistic Keplerian Omega(r) and Killing redshift factor g:
        //      Omega(r) = 1 / (r^(3/2) + a)
        //      g = sqrt(1 - 3/r + 2 a Omega) / (1 + Omega b_x sin(i))
        const omega = 1.0 / (math.pow(f32, r, 1.5) + a_spin);
        const lapse_sq = @max(0.20, 1.0 - 3.0 / r + 2.0 * a_spin * omega);
        const denom = @max(0.45, 1.0 + omega * b_x * sin_i);
        const g = @sqrt(lapse_sq) / denom;

        // Relativistic beaming g^2.05 with smooth C^infinity soft-shoulder compression into [0, 0.98]
        // so u8 channel packing never clips R at 255 while G and B keep rising (preserving R > G > B everywhere).
        const g_beam = math.clamp(math.pow(f32, g, 2.05), 0.20, 2.25);
        const raw_int = flux_vis * g_beam * 1.04;
        const intensity = raw_int / @sqrt(1.0 + 0.88 * raw_int * raw_int);

        // 3. True Planckian blackbody color progression (R > G > B strictly everywhere):
        //    Receding/outer -> deep crimson-umber; mid -> rich amber-gold;
        //    approaching inner crest -> warm incandescent solar white-gold (never cold grey!).
        const t_disk = math.pow(f32, @max(0.03, f_raw), 0.22);
        const t_obs = math.clamp(g * t_disk, 0.25, 1.55);

        const warm = math.clamp((t_obs - 0.25) / 0.68, 0.0, 1.0);
        const hot = math.clamp((t_obs - 0.85) / 0.70, 0.0, 1.0);

        const cr = 0.88 + 0.12 * warm;
        const cg = 0.18 + 0.52 * warm * (0.65 + 0.35 * warm) + 0.19 * hot;
        const cb = 0.03 + 0.24 * warm * warm + 0.42 * hot * (0.65 + 0.35 * hot);

        // Optically thick foreground disk body occludes background photon ring & lower arch
        // so the circular shadow boundary never cuts a seam across the foreground bar.
        const inner_opaq = math.clamp((r - R_IN) / 0.08, 0.0, 1.0);
        const opacity: f32 = if (is_foreground)
            math.clamp(inner_opaq * math.clamp(outer_norm * 3.4, 0.0, 1.0), 0.0, 0.998)
        else
            math.clamp(inner_opaq * outer_taper * 0.96, 0.0, 0.96);

        return .{
            .r = intensity * cr,
            .g = intensity * cg,
            .b = intensity * cb,
            .intensity = intensity,
            .opacity = opacity,
        };
    }

    /// Updates the [128][256] polar accretion disk turbulence texture in `step(dt)`.
    /// Uses multi-band partition-of-unity relativistic Keplerian shear so inner rings
    /// orbit ~8x faster than outer rings while maintaining organic spiral pitch forever
    /// (zero concentric m=0 bullseye rings and zero long-time Nyquist winding).
    fn updateDiskTexture(self: *State) void {
        const t: f32 = @floatCast(self.time);
        const breath = 0.75 * @sin(0.32 * t);

        for (0..N_R) |ir| {
            const log_r = self.ring_log_r[ir];
            const omega = self.ring_omega[ir];
            const s = (@as(f32, @floatFromInt(ir)) + 0.5) / @as(f32, @floatFromInt(N_R));
            const u_band = s * @as(f32, @floatFromInt(N_BANDS - 1));
            const k0: usize = @min(N_BANDS - 2, @as(usize, @intFromFloat(u_band)));
            const f_band = u_band - @as(f32, @floatFromInt(k0));
            const w = f_band * f_band * (3.0 - 2.0 * f_band);
            const norm = 1.0 / @sqrt((1.0 - w) * (1.0 - w) + w * w + 0.45 * (1.0 - w) * w);
            const w0 = (1.0 - w) * norm;
            const w1 = w * norm;

            const shear_live = (omega - 0.85) * breath;
            const om0 = self.band_omega[k0] * t + shear_live;
            const om1 = self.band_omega[k0 + 1] * t + shear_live;

            const spiral1 = 3.6 * log_r;
            const spiral2 = 6.4 * log_r;
            const spiral3 = 9.8 * log_r;

            // Angle-addition decomposition: hoists all 10 transcendental sin/cos evaluations
            // out of the 256-wide inner azimuthal loop into 1D ring coefficients (a_m, b_m)
            const th1_0 = spiral1 + 0.25 * t - 1.0 * om0;
            const th1_1 = spiral1 + 0.25 * t - 1.0 * om1;
            const a1 = 0.24 * (w0 * @cos(th1_0) + w1 * @cos(th1_1));
            const b1 = 0.24 * (w0 * @sin(th1_0) + w1 * @sin(th1_1));

            const th2_0 = spiral1 * 1.35 - 0.40 * t - 2.0 * om0;
            const th2_1 = spiral1 * 1.35 - 0.40 * t - 2.0 * om1;
            const a2 = 0.30 * (w0 * @cos(th2_0) + w1 * @cos(th2_1));
            const b2 = 0.30 * (w0 * @sin(th2_0) + w1 * @sin(th2_1));

            const th3_0 = spiral2 + 0.65 * t - 3.0 * om0;
            const th3_1 = spiral2 + 0.65 * t - 3.0 * om1;
            const a3 = -0.22 * (w0 * @sin(th3_0) + w1 * @sin(th3_1));
            const b3 = 0.22 * (w0 * @cos(th3_0) + w1 * @cos(th3_1));

            const th4_0 = -spiral2 * 0.85 - 0.80 * t - 4.0 * om0;
            const th4_1 = -spiral2 * 0.85 - 0.80 * t - 4.0 * om1;
            const a4 = 0.15 * (w0 * @cos(th4_0) + w1 * @cos(th4_1));
            const b4 = 0.15 * (w0 * @sin(th4_0) + w1 * @sin(th4_1));

            const th6_0 = spiral3 + 1.10 * t - 6.0 * om0;
            const th6_1 = spiral3 + 1.10 * t - 6.0 * om1;
            const a6 = -0.09 * (w0 * @sin(th6_0) + w1 * @sin(th6_1));
            const b6 = 0.09 * (w0 * @cos(th6_0) + w1 * @cos(th6_1));

            const row_offset = ir * N_PHI;
            for (0..N_PHI) |iphi| {
                const turb = a1 * self.phi_sin[0][iphi] + b1 * self.phi_cos[0][iphi] +
                    a2 * self.phi_sin[1][iphi] + b2 * self.phi_cos[1][iphi] +
                    a3 * self.phi_sin[2][iphi] + b3 * self.phi_cos[2][iphi] +
                    a4 * self.phi_sin[3][iphi] + b4 * self.phi_cos[3][iphi] +
                    a6 * self.phi_sin[4][iphi] + b6 * self.phi_cos[4][iphi];
                const fil = 1.00 + 0.26 * turb + 0.18 * @max(0.0, turb);
                self.disk_scratch[row_offset + iphi] = @intFromFloat(math.clamp(fil * 256.0, 64.0, 440.0));
            }
        }

        // Separable [1, 2, 1] radial + azimuthal filter
        for (0..N_R) |ir| {
            const ir_prev = if (ir > 0) ir - 1 else 0;
            const ir_next = if (ir + 1 < N_R) ir + 1 else N_R - 1;
            const row_prev = ir_prev * N_PHI;
            const row_curr = ir * N_PHI;
            const row_next = ir_next * N_PHI;

            for (0..N_PHI) |iphi| {
                const ip_prev = (iphi + N_PHI - 1) & PHI_MASK;
                const ip_next = (iphi + 1) & PHI_MASK;

                const c_rad: u32 = @as(u32, self.disk_scratch[row_prev + iphi]) +
                    (@as(u32, self.disk_scratch[row_curr + iphi]) << 1) +
                    @as(u32, self.disk_scratch[row_next + iphi]);
                const l_rad: u32 = @as(u32, self.disk_scratch[row_curr + ip_prev]);
                const r_rad: u32 = @as(u32, self.disk_scratch[row_curr + ip_next]);

                self.disk_tex[row_curr + iphi] = @intCast((c_rad + l_rad + r_rad) / 6);
            }
        }
    }

    pub fn step(self: *State, dt: f64) void {
        self.time = @mod(self.time + dt, 10000.0);
        self.updateDiskTexture();
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        if (self.w == 0 or self.h == 0 or stride < self.w) return;
        const h = @min(self.h, buf.len / stride);
        const w = self.w;

        // 1. Fill deep-space background + black hole shadow interior spans only when buffer is uninitialized
        const bg_space = sdk.packRGBA(3, 4, 9);
        const bg_shadow = sdk.packRGBA(1, 1, 2);
        const h_sh = @min(h, MAX_H);
        const sh_probe_y = (h / 2) -| (h / 16);
        const sh_probe_idx = sh_probe_y * stride + (w / 2);
        const last_idx = (h - 1) * stride + (w - 1);

        if (buf[0] != bg_space or buf[w - 1] != bg_space or buf[last_idx] != bg_space or buf[sh_probe_idx] != bg_shadow) {
            for (0..h) |y| {
                const row = buf[y * stride .. y * stride + w];
                @memset(row, bg_space);
                if (y < h_sh) {
                    const x0 = self.shadow_x0[y];
                    const x1 = @min(@as(u16, @intCast(w)), self.shadow_x1[y]);
                    if (x0 < x1) {
                        @memset(row[x0..x1], bg_shadow);
                    }
                }
            }
        }

        // 2. Render active relativistic accretion disk, lensed arches, and photon ring (write-only, zero buf reads)
        const tex = &self.disk_tex;
        const tmap = &self.tonemap_lut;

        for (self.disk_pixels[0..self.n_disk]) |px| {
            const w0 = px.xy_br;
            const w1 = px.bg_bb_t1;
            const w2 = px.t2_r1_g1;
            const w3 = px.b1_r2_g2_b2;

            const x: usize = w0 & 0xFFF;
            const y: usize = (w0 >> 12) & 0xFFF;
            var rf: u32 = w0 >> 24;
            var gf: u32 = w1 & 0xFF;
            var bf: u32 = (w1 >> 8) & 0xFF;

            const t1 = w1 >> 16;
            if ((t1 & 0x8000) != 0) {
                const m1: u32 = tex[t1 & 0x7FFF];
                rf += (m1 * ((w2 >> 16) & 0xFF)) >> 8;
                gf += (m1 * (w2 >> 24)) >> 8;
                bf += (m1 * (w3 & 0xFF)) >> 8;
            }

            const t2 = w2 & 0xFFFF;
            if ((t2 & 0x8000) != 0) {
                const m2: u32 = tex[t2 & 0x7FFF];
                rf += (m2 * ((w3 >> 8) & 0xFF)) >> 8;
                gf += (m2 * ((w3 >> 16) & 0xFF)) >> 8;
                bf += (m2 * (w3 >> 24)) >> 8;
            }

            const dst_idx = y * stride + x;
            const dr: u32 = tmap[@min(TONEMAP_N - 1, rf)];
            const dg: u32 = tmap[@min(TONEMAP_N - 1, gf)];
            const db: u32 = tmap[@min(TONEMAP_N - 1, bf)];

            const in_sh = (dr + dg + db < 36) and (x >= self.shadow_x0[y] and x < self.shadow_x1[y]);
            const bg_r: u32 = if (in_sh) 1 else 3;
            const bg_g: u32 = if (in_sh) 1 else 4;
            const bg_b: u32 = if (in_sh) 2 else 9;
            const r_out = @min(@as(u32, 255), bg_r + dr);
            const g_out = @min(@as(u32, 255), bg_g + dg);
            const b_out = @min(@as(u32, 255), bg_b + db);
            buf[dst_idx] = sdk.packRGBA(@intCast(r_out), @intCast(g_out), @intCast(b_out));
        }

        // 3. Render gravitationally lensed background stars where not occluded by opaque disk plasma
        for (self.stars[0..self.n_stars]) |st| {
            if (st.y < h and st.x < w) {
                const idx = @as(usize, st.y) * stride + @as(usize, st.x);
                const cur = buf[idx];
                if (cur == bg_space or cur == st.color) {
                    buf[idx] = st.color;
                } else {
                    const cr: u32 = @as(u8, @truncate(cur));
                    const cg: u32 = @as(u8, @truncate(cur >> 8));
                    const cb: u32 = @as(u8, @truncate(cur >> 16));
                    if (cr + cg + cb < 52) {
                        const sr: u32 = @as(u8, @truncate(st.color));
                        const sg: u32 = @as(u8, @truncate(st.color >> 8));
                        const sb: u32 = @as(u8, @truncate(st.color >> 16));
                        buf[idx] = sdk.packRGBA(
                            @intCast(@min(@as(u32, 255), sr + (cr -| 3))),
                            @intCast(@min(@as(u32, 255), sg + (cg -| 4))),
                            @intCast(@min(@as(u32, 255), sb + (cb -| 9))),
                        );
                    }
                }
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return !math.isFinite(self.time);
    }
};

comptime {
    sdk.exportTheme(State);
}

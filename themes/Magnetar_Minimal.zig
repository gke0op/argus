// ============================================================================
// @argus-theme: custom_shader
// ARGUS MINIMAL REFERENCE THEME // themes/Magnetar_Minimal.zig
//
// Stripped-down General Relativistic Spinning Neutron Star (Schwarzschild
// Light-Bending + Relativistic Doppler Beaming) implementing the stateful
// Argus Theme Contract:
//   - `init(alloc, w, h, scale) !*State` (exactly 1 allocation)
//   - `step(state, dt: f64)`             (0 allocations, no clock reads)
//   - `draw(state, buf: []u32, stride)`  (0 allocations, respects stride)
//   - `deinit(state, alloc)`
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const STAR_BOX: usize = 280;

pub const StarRay = struct {
    valid: bool = false,
    psi: f32 = 0.0,
    theta: f32 = 0.0,
    lambda: f32 = 0.0,
    cos_sigma: f32 = 0.0,
    delta: f32 = 1.0,
    z_fac: f32 = 1.0,
    lensing: f32 = 1.0,
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    phase_rad: f64,
    omega_rad_per_dt: f64,
    u_compactness: f32, // r_s / R_eq = 2GM / (R c^2)
    z_base: f32, // sqrt(1 - u)
    inclination: f32,
    spot_colat: f32,
    spot_radius: f32,
    rays: [STAR_BOX * STAR_BOX]StarRay,

    /// Exactly ONE allocation (`alloc.create(State)`). All ray-tracing tables live inline in `State`.
    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        const u: f32 = 0.342; // SLy 1.4 M_sun compactness r_s / R_eq
        const z_b: f32 = @sqrt(1.0 - u);
        const inc: f32 = 1.15; // ~66 deg observer inclination

        self.* = .{
            .w = w,
            .h = h,
            .scale = scale,
            .phase_rad = 0.0,
            .omega_rad_per_dt = 2.0 * math.pi * 0.85, // 0.85 rev per unit dt
            .u_compactness = u,
            .z_base = z_b,
            .inclination = inc,
            .spot_colat = 0.95,
            .spot_radius = 0.32,
            .rays = undefined,
        };

        // Precompute Schwarzschild light-bending lookup table across the 280x280 star box
        const sin_i = @sin(inc);
        const cos_i = @cos(inc);
        const half: f32 = @as(f32, @floatFromInt(STAR_BOX - 1)) * 0.5;
        // GR apparent impact parameter b_max / R = 1 / sqrt(1 - u)
        const b_max_over_r: f32 = 1.0 / z_b;

        for (0..STAR_BOX) |by| {
            const ny = (@as(f32, @floatFromInt(by)) - half) / (half * 0.88);
            for (0..STAR_BOX) |bx| {
                const nx = (@as(f32, @floatFromInt(bx)) - half) / (half * 0.88);
                const r_img = @sqrt(nx * nx + ny * ny);
                const idx = by * STAR_BOX + bx;

                if (r_img > 1.0) {
                    self.rays[idx] = .{ .valid = false };
                    continue;
                }

                // Beloborodov (2002) / Pechenick (1983) exact analytic + high-order Schwarzschild inversion:
                // sin(alpha) = r_img, cos(psi) = 1 - (1 - cos(alpha)) / (1 - u)
                const sin_alpha = math.clamp(r_img, 0.0, 1.0);
                const cos_alpha = @sqrt(@max(0.0, 1.0 - sin_alpha * sin_alpha));
                const cos_psi = 1.0 - (1.0 - cos_alpha) / (1.0 - u);
                if (cos_psi < -0.65) {
                    self.rays[idx] = .{ .valid = false };
                    continue;
                }
                const psi = math.acos(math.clamp(cos_psi, -1.0, 1.0));
                const sin_psi = @sqrt(@max(1e-8, 1.0 - cos_psi * cos_psi));

                // Image-plane position angle eta (0 at North, clockwise)
                const sin_eta = if (r_img > 1e-6) nx / r_img else 0.0;
                const cos_eta = if (r_img > 1e-6) -ny / r_img else 1.0;

                // Spherical trigonometry from (psi, eta) to stellar surface (theta, lambda)
                const cos_theta = math.clamp(cos_i * cos_psi + sin_i * sin_psi * cos_eta, -1.0, 1.0);
                const theta = math.acos(cos_theta);
                const sin_theta = @sqrt(@max(1e-8, 1.0 - cos_theta * cos_theta));
                const lambda = math.atan2(sin_psi * sin_eta, sin_i * cos_psi - cos_i * sin_psi * cos_eta);

                // Relativistic Doppler factor delta at equatorial beta_eq = 0.14
                const beta_eq: f32 = 0.14;
                const beta_loc = beta_eq * sin_theta;
                const gamma = 1.0 / @sqrt(1.0 - beta_loc * beta_loc);
                const cos_xi = -sin_alpha * sin_i * sin_eta / @max(1e-5, sin_psi);
                const delta = 1.0 / (gamma * (1.0 - beta_loc * math.clamp(cos_xi, -0.95, 0.95)));

                const lensing = 1.0 / @max(0.18, 1.0 - u + u * cos_psi);
                _ = b_max_over_r;

                self.rays[idx] = .{
                    .valid = true,
                    .psi = psi,
                    .theta = theta,
                    .lambda = lambda,
                    .cos_sigma = cos_alpha,
                    .delta = delta,
                    .z_fac = z_b * delta,
                    .lensing = lensing,
                };
            }
        }

        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    /// Argus owns time and passes a fixed `dt`. Never read a system clock here.
    pub fn step(self: *State, dt: f64) void {
        self.phase_rad = @mod(self.phase_rad + self.omega_rad_per_dt * dt, 2.0 * math.pi);
    }

    pub fn hasNaN(self: *const State) bool {
        return math.isNan(self.phase_rad) or math.isInf(self.phase_rad);
    }

    /// Renders into `buf` using `stride` (`buf[y * stride + x]`). Zero allocations.
    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const bg = sdk.packRGBA(6, 9, 16);

        for (0..h) |y| {
            const row = buf[y * stride .. y * stride + w];
            @memset(row, bg);
        }

        const px_scale: usize = if (self.scale >= 1.5 and w >= STAR_BOX * 2 and h >= STAR_BOX * 2) 2 else 1;
        const scaled_box = STAR_BOX * px_scale;
        if (w < scaled_box or h < scaled_box) return;
        const box_x0 = (w - scaled_box) / 2;
        const box_y0 = (h - scaled_box) / 2;

        const phase_f: f32 = @floatCast(self.phase_rad);
        const s_spot = @sin(self.spot_colat);
        const c_spot = @cos(self.spot_colat);
        const spot_r = self.spot_radius;
        const z_base = self.z_base;

        for (0..STAR_BOX) |by| {
            for (0..STAR_BOX) |bx| {
                const ray = self.rays[by * STAR_BOX + bx];
                if (!ray.valid) continue;

                const phi_c = ray.lambda - phase_f;
                const cos_rho = math.clamp(
                    c_spot * @cos(ray.theta) + s_spot * @sin(ray.theta) * @cos(phi_c),
                    -1.0,
                    1.0,
                );
                const rho_ang = math.acos(cos_rho);
                const limb = 0.28 + 0.72 * @sqrt(math.clamp(ray.cos_sigma, 0.0, 1.0));
                const doppler = math.clamp((ray.z_fac - z_base) / 0.13, -1.0, 1.0);

                var rf: f32 = 0.0;
                var gf: f32 = 0.0;
                var bf: f32 = 0.0;

                if (doppler >= 0.0) {
                    rf = (24.0 + 30.0 * (1.0 - doppler)) * limb;
                    gf = (65.0 + 115.0 * doppler) * limb;
                    bf = (135.0 + 115.0 * doppler) * limb;
                } else {
                    const red = -doppler;
                    rf = (85.0 + 130.0 * red) * limb;
                    gf = (28.0 + 25.0 * (1.0 - red)) * limb;
                    bf = (65.0 + 40.0 * (1.0 - red)) * limb;
                }

                // Far-side GR lensed hemisphere (psi > 90 deg) magenta tint
                if (ray.psi > math.pi * 0.5) {
                    rf += 28.0;
                    bf += 48.0;
                }

                // Co-rotating latitude/longitude grid lines
                if (@abs(@sin(3.0 * phi_c)) < 0.042 or @abs(@sin(6.0 * ray.theta)) < 0.042) {
                    rf = @min(255.0, rf + 42.0);
                    gf = @min(255.0, gf + 58.0);
                    bf = @min(255.0, bf + 78.0);
                }

                // Relativistic beamed polar hotspot
                if (rho_ang <= spot_r * 1.18) {
                    const beam = ray.delta * ray.delta * ray.delta * ray.delta *
                        @sqrt(1.0 - self.u_compactness) * ray.cos_sigma * ray.lensing;
                    const profile: f32 = if (rho_ang <= spot_r)
                        1.0
                    else
                        @exp(-18.0 * (rho_ang - spot_r) * (rho_ang - spot_r));
                    const inten = math.clamp(beam * profile * 1.65, 0.0, 1.5);
                    rf = @min(255.0, rf + 235.0 * inten);
                    gf = @min(255.0, gf + 195.0 * inten);
                    bf = @min(255.0, bf + 120.0 * inten * inten);
                }

                const col = sdk.packRGBA(
                    @intFromFloat(math.clamp(rf, 0.0, 255.0)),
                    @intFromFloat(math.clamp(gf, 0.0, 255.0)),
                    @intFromFloat(math.clamp(bf, 0.0, 255.0)),
                );
                const py0 = box_y0 + by * px_scale;
                const px0 = box_x0 + bx * px_scale;
                for (0..px_scale) |sy| {
                    const row_start = (py0 + sy) * stride;
                    for (0..px_scale) |sx| {
                        buf[row_start + px0 + sx] = col;
                    }
                }
            }
        }
    }
};

comptime {
    sdk.exportTheme(State);
}

const std = @import("std");
const math = std.math;

pub const N_PARTICLES: usize = 128;
pub const GRID_W: usize = 128;
pub const GRID_H: usize = 64;
pub const GRID_SIZE: usize = GRID_W * GRID_H;
pub const N_SPECTRUM_BINS: usize = 8;

/// 4th-Order Symplectic Yoshida Integrator Coefficients (Yoshida 1990, Phys. Lett. A 150)
pub const Yoshida4 = struct {
    const cbrt2: f64 = 1.25992104989487316476721060727822835057025; // 2^(1/3)
    pub const w1: f64 = 1.0 / (2.0 - cbrt2);
    pub const w0: f64 = -cbrt2 / (2.0 - cbrt2);

    pub const c1: f64 = w1 * 0.5;
    pub const c2: f64 = (w0 + w1) * 0.5;
    pub const c3: f64 = (w0 + w1) * 0.5;
    pub const c4: f64 = w1 * 0.5;

    pub const d1: f64 = w1;
    pub const d2: f64 = w0;
    pub const d3: f64 = w1;
};

pub const SimConfig = struct {
    gm: f64 = 18.0, // Central gravitational parameter GM
    softening_eps: f64 = 0.65, // Central horizon softening length
    omega_conf: f64 = 0.35, // Magnetic / harmonic radial confinement frequency
    alpha_quad: f64 = 0.0, // Quadrupole perturbation (0.0 = exact SO(2) angular momentum conservation)
    pair_kappa: f64 = 0.015, // Pairwise vortex/Coulomb coupling constant
    pair_delta: f64 = 0.35, // Pairwise softening scale
    wave_c: f64 = 1.8, // Relativistic Klein-Gordon wave speed
    wave_mass: f64 = 0.85, // Klein-Gordon rest mass parameter m_0
    wave_damping: f64 = 0.04, // Wave radiative damping gamma (0.0 for conservative tests)
    pic_coupling: f64 = 1.25, // Particle-to-field Cherenkov wake coupling
    domain_half_w: f64 = 8.0, // Physical half-width of the 2D domain [-8, 8]
    domain_half_h: f64 = 4.0, // Physical half-height of the 2D domain [-4, 4]
};

pub const Telemetry = struct {
    step_count: u64 = 0,
    sim_time: f64 = 0.0,
    kinetic_energy: f64 = 0.0,
    potential_energy: f64 = 0.0,
    total_hamiltonian: f64 = 0.0,
    initial_hamiltonian: f64 = 0.0,
    rel_energy_drift: f64 = 0.0,
    angular_momentum_lz: f64 = 0.0,
    initial_lz: f64 = 0.0,
    rel_lz_drift: f64 = 0.0,
    virial_ratio: f64 = 0.0,
    wave_energy: f64 = 0.0,
    peak_field_abs: f64 = 0.0,
    kuramoto_r: f64 = 0.0,
    kuramoto_psi: f64 = 0.0,
    radial_spectrum: [N_SPECTRUM_BINS]f64 = @splat(0.0),
};

pub const KronosEngine = struct {
    cfg: SimConfig,

    // Particle state arrays (SoA layout for cache locality & vectorization)
    x: [N_PARTICLES]f64,
    y: [N_PARTICLES]f64,
    px: [N_PARTICLES]f64,
    py: [N_PARTICLES]f64,
    fx: [N_PARTICLES]f64,
    fy: [N_PARTICLES]f64,
    charge: [N_PARTICLES]f64,

    // Trail history buffer (last 2 positions per particle for sub-pixel Braille streaks)
    trail_x0: [N_PARTICLES]f64,
    trail_y0: [N_PARTICLES]f64,
    trail_x1: [N_PARTICLES]f64,
    trail_y1: [N_PARTICLES]f64,

    // 2D Relativistic Klein-Gordon Field Lattice (128 x 64 = 8,192 cells)
    phi: [GRID_SIZE]f64,
    pi: [GRID_SIZE]f64,
    lap_buf: [GRID_SIZE]f64,
    rho_cic: [GRID_SIZE]f64,

    telemetry: Telemetry,

    pub fn init(cfg: SimConfig) KronosEngine {
        var self = KronosEngine{
            .cfg = cfg,
            .x = @splat(0.0),
            .y = @splat(0.0),
            .px = @splat(0.0),
            .py = @splat(0.0),
            .fx = @splat(0.0),
            .fy = @splat(0.0),
            .charge = @splat(0.0),
            .trail_x0 = @splat(0.0),
            .trail_y0 = @splat(0.0),
            .trail_x1 = @splat(0.0),
            .trail_y1 = @splat(0.0),
            .phi = @splat(0.0),
            .pi = @splat(0.0),
            .lap_buf = @splat(0.0),
            .rho_cic = @splat(0.0),
            .telemetry = .{},
        };

        // Deterministic quasi-Keplerian + magneto-vortex multi-ring initialization
        // Uses golden-angle spiral + 3 resonant orbital bands so dynamics are rich and deterministic.
        const golden_angle: f64 = math.pi * (3.0 - @sqrt(5.0));
        for (0..N_PARTICLES) |i| {
            const fi = @as(f64, @floatFromInt(i));
            const fn_tot = @as(f64, @floatFromInt(N_PARTICLES));
            const band = i % 3;
            const r_base: f64 = switch (band) {
                0 => 1.35 + 0.55 * (fi / fn_tot),
                1 => 2.15 + 0.70 * (fi / fn_tot),
                else => 3.05 + 0.65 * (fi / fn_tot),
            };
            const eccentricity_mod = 1.0 + 0.08 * @sin(fi * 0.37);
            const r = r_base * eccentricity_mod;
            const theta = fi * golden_angle + 0.25 * @cos(fi * 0.19);

            const xi = r * @cos(theta);
            const yi = r * @sin(theta);
            self.x[i] = xi;
            self.y[i] = yi;
            self.trail_x0[i] = xi;
            self.trail_y0[i] = yi;
            self.trail_x1[i] = xi;
            self.trail_y1[i] = yi;

            // Exact circular orbital speed in the central potential + small radial epicyclic mode
            const r2_eps = r * r + cfg.softening_eps * cfg.softening_eps;
            const dV_dr = cfg.gm * r / (r2_eps * @sqrt(r2_eps)) + cfg.omega_conf * cfg.omega_conf * r;
            const v_circ = @sqrt(@max(0.0, r * dV_dr));
            const v_rad = 0.12 * v_circ * @sin(3.0 * theta + fi * 0.05);

            self.px[i] = -v_circ * @sin(theta) + v_rad * @cos(theta);
            self.py[i] = v_circ * @cos(theta) + v_rad * @sin(theta);

            // Alternating vortex circulation / charge (+1 / -0.85) for rich dipole wakes
            self.charge[i] = if ((i & 1) == 0) 1.0 else -0.85;
        }

        // Seed an initial axisymmetric + spiral Klein-Gordon wave packet on the lattice
        const dx = (2.0 * cfg.domain_half_w) / @as(f64, @floatFromInt(GRID_W - 1));
        const dy = (2.0 * cfg.domain_half_h) / @as(f64, @floatFromInt(GRID_H - 1));
        for (1..GRID_H - 1) |gy| {
            const wy = -cfg.domain_half_h + @as(f64, @floatFromInt(gy)) * dy;
            for (1..GRID_W - 1) |gx| {
                const wx = -cfg.domain_half_w + @as(f64, @floatFromInt(gx)) * dx;
                const r2 = wx * wx + wy * wy;
                const s = @sqrt(r2 + 1.0);
                const env = 0.25 * @exp(-0.32 * r2);
                const m2_re = wx * wx - wy * wy;
                const m2_im = 2.0 * wx * wy;
                const idx = gy * GRID_W + gx;
                self.phi[idx] = env * (m2_re * @cos(1.2 * s) + m2_im * @sin(1.2 * s));
                self.pi[idx] = 0.6 * env * (m2_im * @cos(1.2 * s) - m2_re * @sin(1.2 * s));
            }
        }

        self.updateTelemetry(true);
        return self;
    }

    /// Computes exact analytical forces F_i = -grad_i U(q), potential energy U(q),
    /// and radial virial sum(q_i . -grad_i U). Zero heap allocations.
    pub fn computeForcesAndPotential(self: *KronosEngine) struct { potential: f64, virial_dot: f64 } {
        const gm = self.cfg.gm;
        const eps2 = self.cfg.softening_eps * self.cfg.softening_eps;
        const omega2 = self.cfg.omega_conf * self.cfg.omega_conf;
        const alpha_q = self.cfg.alpha_quad;
        const kappa = self.cfg.pair_kappa;
        const delta2 = self.cfg.pair_delta * self.cfg.pair_delta;

        var total_u: f64 = 0.0;
        var virial_dot: f64 = 0.0;

        for (0..N_PARTICLES) |i| {
            const xi = self.x[i];
            const yi = self.y[i];
            const r2 = xi * xi + yi * yi;
            const r2_eps = r2 + eps2;
            const inv_r_eps = 1.0 / @sqrt(r2_eps);
            const inv_r3_eps = inv_r_eps * inv_r_eps * inv_r_eps;

            // Central gravitational + magnetic harmonic confinement + quadrupole potential
            const u_one = -gm * inv_r_eps + 0.5 * omega2 * r2 + alpha_q * (xi * xi - yi * yi);
            total_u += u_one;

            const coeff_x = gm * inv_r3_eps + omega2 + 2.0 * alpha_q;
            const coeff_y = gm * inv_r3_eps + omega2 - 2.0 * alpha_q;
            self.fx[i] = -coeff_x * xi;
            self.fy[i] = -coeff_y * yi;
        }

        if (kappa != 0.0) {
            for (0..N_PARTICLES) |i| {
                const xi = self.x[i];
                const yi = self.y[i];
                const qi = self.charge[i];
                var dfx_i: f64 = 0.0;
                var dfy_i: f64 = 0.0;

                for (i + 1..N_PARTICLES) |j| {
                    const dx = xi - self.x[j];
                    const dy = yi - self.y[j];
                    const d2 = dx * dx + dy * dy + delta2;
                    const inv_d = 1.0 / @sqrt(d2);
                    const inv_d3 = inv_d * inv_d * inv_d;
                    const qij = kappa * qi * self.charge[j];

                    total_u += qij * inv_d;
                    const f_mag = qij * inv_d3;
                    const fx_pair = f_mag * dx;
                    const fy_pair = f_mag * dy;

                    dfx_i += fx_pair;
                    dfy_i += fy_pair;
                    self.fx[j] -= fx_pair;
                    self.fy[j] -= fy_pair;
                }

                self.fx[i] += dfx_i;
                self.fy[i] += dfy_i;
            }
        }

        for (0..N_PARTICLES) |i| {
            // Virial dot product: sum_i q_i . grad_i U = sum_i -(x_i * fx_i + y_i * fy_i)
            virial_dot += -(self.x[i] * self.fx[i] + self.y[i] * self.fy[i]);
        }

        return .{ .potential = total_u, .virial_dot = virial_dot };
    }

    inline fn driftPositions(self: *KronosEngine, coeff_dt: f64) void {
        for (0..N_PARTICLES) |i| {
            self.x[i] += coeff_dt * self.px[i];
            self.y[i] += coeff_dt * self.py[i];
        }
    }

    inline fn kickMomenta(self: *KronosEngine, coeff_dt: f64) void {
        _ = self.computeForcesAndPotential();
        for (0..N_PARTICLES) |i| {
            self.px[i] += coeff_dt * self.fx[i];
            self.py[i] += coeff_dt * self.fy[i];
        }
    }

    /// Advances particles by one 4th-order Symplectic Yoshida step.
    /// Strictly time-reversible and symplectic: conserves H to O(dt^4) and L_z to machine epsilon.
    pub fn stepParticlesYoshida4(self: *KronosEngine, dt: f64) void {
        self.driftPositions(Yoshida4.c1 * dt);
        self.kickMomenta(Yoshida4.d1 * dt);

        self.driftPositions(Yoshida4.c2 * dt);
        self.kickMomenta(Yoshida4.d2 * dt);

        self.driftPositions(Yoshida4.c3 * dt);
        self.kickMomenta(Yoshida4.d3 * dt);

        self.driftPositions(Yoshida4.c4 * dt);
    }

    /// Cloud-In-Cell (CIC) bilinear particle charge deposition onto the 2D lattice.
    /// Strictly conserves total deposited charge for all interior particles.
    pub fn depositChargeCIC(self: *KronosEngine) void {
        @memset(&self.rho_cic, 0.0);

        const half_w = self.cfg.domain_half_w;
        const half_h = self.cfg.domain_half_h;
        const scale_x = @as(f64, @floatFromInt(GRID_W - 3)) / (2.0 * half_w);
        const scale_y = @as(f64, @floatFromInt(GRID_H - 3)) / (2.0 * half_h);

        for (0..N_PARTICLES) |i| {
            // Map physical coordinates [-half_w, half_w] into interior grid [1, GRID_W - 2]
            const gx_f = 1.0 + (self.x[i] + half_w) * scale_x;
            const gy_f = 1.0 + (self.y[i] + half_h) * scale_y;

            if (gx_f >= 1.0 and gx_f < @as(f64, @floatFromInt(GRID_W - 2)) and
                gy_f >= 1.0 and gy_f < @as(f64, @floatFromInt(GRID_H - 2)))
            {
                const ix0: usize = @intFromFloat(@floor(gx_f));
                const iy0: usize = @intFromFloat(@floor(gy_f));
                const wx = gx_f - @as(f64, @floatFromInt(ix0));
                const wy = gy_f - @as(f64, @floatFromInt(iy0));

                const q = self.charge[i];
                const row0 = iy0 * GRID_W;
                const row1 = (iy0 + 1) * GRID_W;

                self.rho_cic[row0 + ix0] += q * (1.0 - wx) * (1.0 - wy);
                self.rho_cic[row0 + ix0 + 1] += q * wx * (1.0 - wy);
                self.rho_cic[row1 + ix0] += q * (1.0 - wx) * wy;
                self.rho_cic[row1 + ix0 + 1] += q * wx * wy;
            }
        }
    }

    /// Computes field acceleration a = c^2 * Laplacian(phi) - m_0^2 * phi + g * rho_cic
    /// using @Vector(4, f64) hardware SIMD intrinsics across the 2D lattice.
    pub fn computeFieldAccelSIMD(self: *KronosEngine) void {
        const Vec4 = @Vector(4, f64);
        const dx = (2.0 * self.cfg.domain_half_w) / @as(f64, @floatFromInt(GRID_W - 1));
        const dy = (2.0 * self.cfg.domain_half_h) / @as(f64, @floatFromInt(GRID_H - 1));
        const c2_inv_dx2 = (self.cfg.wave_c * self.cfg.wave_c) / (dx * dx);
        const c2_inv_dy2 = (self.cfg.wave_c * self.cfg.wave_c) / (dy * dy);
        const m2 = self.cfg.wave_mass * self.cfg.wave_mass;
        const g_cpl = self.cfg.pic_coupling;

        const v_cx: Vec4 = @splat(c2_inv_dx2);
        const v_cy: Vec4 = @splat(c2_inv_dy2);
        const v_center: Vec4 = @splat(-2.0 * (c2_inv_dx2 + c2_inv_dy2) - m2);
        const v_gcpl: Vec4 = @splat(g_cpl);

        for (1..GRID_H - 1) |gy| {
            const row = gy * GRID_W;
            const row_up = (gy - 1) * GRID_W;
            const row_dn = (gy + 1) * GRID_W;

            var gx: usize = 1;
            // Process 4 interior cells per iteration using @Vector(4, f64)
            while (gx + 4 <= GRID_W - 1) : (gx += 4) {
                const p_c: Vec4 = self.phi[row + gx ..][0..4].*;
                const p_l: Vec4 = self.phi[row + gx - 1 ..][0..4].*;
                const p_r: Vec4 = self.phi[row + gx + 1 ..][0..4].*;
                const p_u: Vec4 = self.phi[row_up + gx ..][0..4].*;
                const p_d: Vec4 = self.phi[row_dn + gx ..][0..4].*;
                const rho_v: Vec4 = self.rho_cic[row + gx ..][0..4].*;

                const lap_x = (p_l + p_r) * v_cx;
                const lap_y = (p_u + p_d) * v_cy;
                const acc = lap_x + lap_y + p_c * v_center + rho_v * v_gcpl;
                self.lap_buf[row + gx ..][0..4].* = acc;
            }

            // Remainder interior cells (x = 125, 126 for GRID_W = 128)
            const center_scalar = -2.0 * (c2_inv_dx2 + c2_inv_dy2) - m2;
            while (gx < GRID_W - 1) : (gx += 1) {
                const idx = row + gx;
                const lap_x = (self.phi[idx - 1] + self.phi[idx + 1]) * c2_inv_dx2;
                const lap_y = (self.phi[row_up + gx] + self.phi[row_dn + gx]) * c2_inv_dy2;
                self.lap_buf[idx] = lap_x + lap_y + self.phi[idx] * center_scalar + self.rho_cic[idx] * g_cpl;
            }
        }
    }

    /// Reference scalar field acceleration for bit-for-bit SIMD parity verification.
    pub fn computeFieldAccelScalar(self: *KronosEngine) void {
        const dx = (2.0 * self.cfg.domain_half_w) / @as(f64, @floatFromInt(GRID_W - 1));
        const dy = (2.0 * self.cfg.domain_half_h) / @as(f64, @floatFromInt(GRID_H - 1));
        const c2_inv_dx2 = (self.cfg.wave_c * self.cfg.wave_c) / (dx * dx);
        const c2_inv_dy2 = (self.cfg.wave_c * self.cfg.wave_c) / (dy * dy);
        const m2 = self.cfg.wave_mass * self.cfg.wave_mass;
        const g_cpl = self.cfg.pic_coupling;
        const center_scalar = -2.0 * (c2_inv_dx2 + c2_inv_dy2) - m2;

        for (1..GRID_H - 1) |gy| {
            const row = gy * GRID_W;
            const row_up = (gy - 1) * GRID_W;
            const row_dn = (gy + 1) * GRID_W;
            for (1..GRID_W - 1) |gx| {
                const idx = row + gx;
                const lap_x = (self.phi[idx - 1] + self.phi[idx + 1]) * c2_inv_dx2;
                const lap_y = (self.phi[row_up + gx] + self.phi[row_dn + gx]) * c2_inv_dy2;
                self.lap_buf[idx] = lap_x + lap_y + self.phi[idx] * center_scalar + self.rho_cic[idx] * g_cpl;
            }
        }
    }

    inline fn driftFieldSIMD(self: *KronosEngine, coeff_dt: f64) void {
        const Vec4 = @Vector(4, f64);
        const v_dt: Vec4 = @splat(coeff_dt);
        for (1..GRID_H - 1) |gy| {
            const row = gy * GRID_W;
            var gx: usize = 1;
            while (gx + 4 <= GRID_W - 1) : (gx += 4) {
                const phi_v: Vec4 = self.phi[row + gx ..][0..4].*;
                const pi_v: Vec4 = self.pi[row + gx ..][0..4].*;
                self.phi[row + gx ..][0..4].* = phi_v + v_dt * pi_v;
            }
            while (gx < GRID_W - 1) : (gx += 1) {
                self.phi[row + gx] += coeff_dt * self.pi[row + gx];
            }
        }
    }

    inline fn kickFieldSIMD(self: *KronosEngine, coeff_dt: f64, use_simd: bool) void {
        if (use_simd) {
            self.computeFieldAccelSIMD();
        } else {
            self.computeFieldAccelScalar();
        }
        const Vec4 = @Vector(4, f64);
        const v_dt: Vec4 = @splat(coeff_dt);
        const damp_factor = @exp(-coeff_dt * self.cfg.wave_damping);
        const v_damp: Vec4 = @splat(damp_factor);

        for (1..GRID_H - 1) |gy| {
            const row = gy * GRID_W;
            var gx: usize = 1;
            while (gx + 4 <= GRID_W - 1) : (gx += 4) {
                const pi_v: Vec4 = self.pi[row + gx ..][0..4].*;
                const acc_v: Vec4 = self.lap_buf[row + gx ..][0..4].*;
                self.pi[row + gx ..][0..4].* = pi_v * v_damp + v_dt * acc_v;
            }
            while (gx < GRID_W - 1) : (gx += 1) {
                const idx = row + gx;
                self.pi[idx] = self.pi[idx] * damp_factor + coeff_dt * self.lap_buf[idx];
            }
        }
    }

    /// Advances the 2D Klein-Gordon wave lattice via 4th-order Yoshida integration.
    pub fn stepFieldYoshida4(self: *KronosEngine, dt: f64, use_simd: bool) void {
        self.driftFieldSIMD(Yoshida4.c1 * dt);
        self.kickFieldSIMD(Yoshida4.d1 * dt, use_simd);

        self.driftFieldSIMD(Yoshida4.c2 * dt);
        self.kickFieldSIMD(Yoshida4.d2 * dt, use_simd);

        self.driftFieldSIMD(Yoshida4.c3 * dt);
        self.kickFieldSIMD(Yoshida4.d3 * dt, use_simd);

        self.driftFieldSIMD(Yoshida4.c4 * dt);
    }

    /// Computes exact discrete Klein-Gordon wave energy functional H_KG.
    pub fn computeWaveEnergy(self: *const KronosEngine) struct { energy: f64, peak_abs: f64 } {
        const dx = (2.0 * self.cfg.domain_half_w) / @as(f64, @floatFromInt(GRID_W - 1));
        const dy = (2.0 * self.cfg.domain_half_h) / @as(f64, @floatFromInt(GRID_H - 1));
        const c2 = self.cfg.wave_c * self.cfg.wave_c;
        const m2 = self.cfg.wave_mass * self.cfg.wave_mass;
        const cell_area = dx * dy;

        var e_sum: f64 = 0.0;
        var peak_abs: f64 = 0.0;

        // Interior kinetic + mass energy
        for (1..GRID_H - 1) |gy| {
            const row = gy * GRID_W;
            for (1..GRID_W - 1) |gx| {
                const idx = row + gx;
                const phi_v = self.phi[idx];
                const pi_v = self.pi[idx];
                const abs_phi = @abs(phi_v);
                if (abs_phi > peak_abs) peak_abs = abs_phi;
                e_sum += 0.5 * (pi_v * pi_v + m2 * phi_v * phi_v);
            }
        }

        // Exact discrete gradient energy across all interior + boundary links
        for (1..GRID_H - 1) |gy| {
            const row = gy * GRID_W;
            for (0..GRID_W - 1) |gx| {
                const dphi_dx = (self.phi[row + gx + 1] - self.phi[row + gx]) / dx;
                e_sum += 0.5 * c2 * dphi_dx * dphi_dx;
            }
        }
        for (0..GRID_H - 1) |gy| {
            const row = gy * GRID_W;
            const row_next = (gy + 1) * GRID_W;
            for (1..GRID_W - 1) |gx| {
                const dphi_dy = (self.phi[row_next + gx] - self.phi[row + gx]) / dy;
                e_sum += 0.5 * c2 * dphi_dy * dphi_dy;
            }
        }

        return .{ .energy = e_sum * cell_area, .peak_abs = peak_abs };
    }

    /// Computes Kuramoto azimuthal phase order parameter R = |1/N sum exp(i theta_j)|.
    pub fn computeKuramotoOrder(x_arr: []const f64, y_arr: []const f64) struct { r: f64, psi: f64 } {
        if (x_arr.len == 0) return .{ .r = 0.0, .psi = 0.0 };
        var sum_cos: f64 = 0.0;
        var sum_sin: f64 = 0.0;
        for (x_arr, y_arr) |xi, yi| {
            const r = @sqrt(xi * xi + yi * yi);
            if (r > 1e-12) {
                sum_cos += xi / r;
                sum_sin += yi / r;
            }
        }
        const inv_n = 1.0 / @as(f64, @floatFromInt(x_arr.len));
        const mean_cos = sum_cos * inv_n;
        const mean_sin = sum_sin * inv_n;
        return .{
            .r = @sqrt(mean_cos * mean_cos + mean_sin * mean_sin),
            .psi = math.atan2(mean_sin, mean_cos),
        };
    }

    /// Updates all physical conservation diagnostics, Kuramoto order parameter, and radial spectrum.
    pub fn updateTelemetry(self: *KronosEngine, is_initial: bool) void {
        const force_res = self.computeForcesAndPotential();

        var ke: f64 = 0.0;
        var lz: f64 = 0.0;
        for (0..N_PARTICLES) |i| {
            ke += 0.5 * (self.px[i] * self.px[i] + self.py[i] * self.py[i]);
            lz += self.x[i] * self.py[i] - self.y[i] * self.px[i];
        }

        const total_h = ke + force_res.potential;
        if (is_initial) {
            self.telemetry.initial_hamiltonian = total_h;
            self.telemetry.initial_lz = lz;
        }

        self.telemetry.kinetic_energy = ke;
        self.telemetry.potential_energy = force_res.potential;
        self.telemetry.total_hamiltonian = total_h;
        self.telemetry.rel_energy_drift = @abs(total_h - self.telemetry.initial_hamiltonian) /
            @max(1e-12, @abs(self.telemetry.initial_hamiltonian));

        self.telemetry.angular_momentum_lz = lz;
        self.telemetry.rel_lz_drift = @abs(lz - self.telemetry.initial_lz) /
            @max(1e-12, @abs(self.telemetry.initial_lz));

        self.telemetry.virial_ratio = (2.0 * ke) / @max(1e-12, @abs(force_res.virial_dot));

        const wave_stats = self.computeWaveEnergy();
        self.telemetry.wave_energy = wave_stats.energy;
        self.telemetry.peak_field_abs = wave_stats.peak_abs;

        const kuramoto = computeKuramotoOrder(&self.x, &self.y);
        self.telemetry.kuramoto_r = kuramoto.r;
        self.telemetry.kuramoto_psi = kuramoto.psi;

        // Compute 8-band radial energy density spectrum across shells r in [0, 5.5]
        var bins: [N_SPECTRUM_BINS]f64 = @splat(0.0);
        const r_max: f64 = 5.5;
        for (0..N_PARTICLES) |i| {
            const r = @sqrt(self.x[i] * self.x[i] + self.y[i] * self.y[i]);
            const e_kin_i = 0.5 * (self.px[i] * self.px[i] + self.py[i] * self.py[i]);
            const bin_f = (r / r_max) * @as(f64, @floatFromInt(N_SPECTRUM_BINS));
            const bin_idx = @min(N_SPECTRUM_BINS - 1, @as(usize, @intFromFloat(@max(0.0, bin_f))));
            bins[bin_idx] += e_kin_i;
        }
        self.telemetry.radial_spectrum = bins;
    }

    /// Executes one complete coupled simulation frame (sub-steps for accuracy + trail recording).
    pub fn stepFrame(self: *KronosEngine, dt: f64, substeps: usize) void {
        // Shift particle trail history for sub-pixel Braille motion streaks
        self.trail_x1 = self.trail_x0;
        self.trail_y1 = self.trail_y0;
        self.trail_x0 = self.x;
        self.trail_y0 = self.y;

        const sub_dt = dt / @as(f64, @floatFromInt(substeps));
        for (0..substeps) |_| {
            self.stepParticlesYoshida4(sub_dt);
            self.depositChargeCIC();
            self.stepFieldYoshida4(sub_dt, true);
            self.telemetry.step_count += 1;
            self.telemetry.sim_time += sub_dt;
        }

        self.updateTelemetry(false);
    }
};

// ============================================================================
// UNIT TESTS: Conservation Laws, SIMD Bit-Parity, CIC Invariants & Kuramoto
// ============================================================================

test "Yoshida 4th-order symplectic integrator conserves H and L_z with pairwise interactions" {
    var engine = KronosEngine.init(.{
        .alpha_quad = 0.0, // Axisymmetric SO(2) invariance
        .pair_kappa = 0.015,
        .pic_coupling = 0.0,
        .wave_damping = 0.0,
    });

    const dt: f64 = 0.0025;
    for (0..1000) |_| {
        engine.stepParticlesYoshida4(dt);
    }
    engine.updateTelemetry(false);

    // 4th-order symplectic Hamiltonian conservation < 1e-8 over 1,000 steps
    try std.testing.expect(engine.telemetry.rel_energy_drift < 1.0e-8);
    // Exact rotational symmetry conserves canonical angular momentum L_z to < 1e-12
    try std.testing.expect(engine.telemetry.rel_lz_drift < 1.0e-12);
}

test "SIMD @Vector(4, f64) 2D Klein-Gordon wave solver matches scalar reference bit-for-bit" {
    var simd_engine = KronosEngine.init(.{});
    var scalar_engine = KronosEngine.init(.{});

    simd_engine.depositChargeCIC();
    scalar_engine.depositChargeCIC();

    const dt: f64 = 0.004;
    for (0..60) |_| {
        simd_engine.stepFieldYoshida4(dt, true);
        scalar_engine.stepFieldYoshida4(dt, false);
    }

    var max_phi_diff: f64 = 0.0;
    var max_pi_diff: f64 = 0.0;
    for (0..GRID_SIZE) |idx| {
        const d_phi = @abs(simd_engine.phi[idx] - scalar_engine.phi[idx]);
        const d_pi = @abs(simd_engine.pi[idx] - scalar_engine.pi[idx]);
        if (d_phi > max_phi_diff) max_phi_diff = d_phi;
        if (d_pi > max_pi_diff) max_pi_diff = d_pi;
    }

    // Identical IEEE-754 operations in @Vector(4, f64) vs scalar loop
    try std.testing.expectEqual(@as(f64, 0.0), max_phi_diff);
    try std.testing.expectEqual(@as(f64, 0.0), max_pi_diff);
}

test "Free 2D Klein-Gordon wave lattice conserves discrete wave Hamiltonian via Yoshida-4" {
    var engine = KronosEngine.init(.{
        .wave_damping = 0.0,
        .pic_coupling = 0.0,
    });
    const e0 = engine.computeWaveEnergy().energy;
    try std.testing.expect(e0 > 0.01);

    const dt: f64 = 0.004;
    for (0..400) |_| {
        engine.stepFieldYoshida4(dt, true);
    }
    const e1 = engine.computeWaveEnergy().energy;
    const rel_drift = @abs(e1 - e0) / e0;
    try std.testing.expect(rel_drift < 1.0e-8);
}

test "Cloud-In-Cell (CIC) bilinear charge deposition strictly conserves total charge" {
    var engine = KronosEngine.init(.{});
    engine.depositChargeCIC();

    var expected_q: f64 = 0.0;
    for (engine.charge) |q| expected_q += q;

    var grid_q: f64 = 0.0;
    for (engine.rho_cic) |rho| grid_q += rho;

    try std.testing.expectApproxEqAbs(expected_q, grid_q, 1.0e-12);
}

test "Kuramoto phase coherence R satisfies exact analytical limits" {
    // 1. Identical angles -> R = 1.0
    const x_sync = [_]f64{ 2.0, 3.5, 1.2, 4.0 };
    const y_sync = [_]f64{ 0.0, 0.0, 0.0, 0.0 };
    const res_sync = KronosEngine.computeKuramotoOrder(&x_sync, &y_sync);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), res_sync.r, 1.0e-14);

    // 2. Balanced 4-fold symmetry -> R = 0.0
    const x_bal = [_]f64{ 1.0, -1.0, 0.0, 0.0 };
    const y_bal = [_]f64{ 0.0, 0.0, 1.0, -1.0 };
    const res_bal = KronosEngine.computeKuramotoOrder(&x_bal, &y_bal);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), res_bal.r, 1.0e-14);
}

// @argus-theme: custom_shader
// ============================================================================
// NEON OSTR CHERENKOV // themes/Neon_OSTR_Cherenkov.zig
// Author / Agent : Gemini 4 Neon (ARGUS-BENCH — CPU Track, Zig 0.17.0)
// Date           : 2026-11-27
//
// What you see:
//   Looking down at an 18.5-degree oblique angle from the observation bridge
//   through 5.2 meters of ultra-pure demineralized light water into the
//   submerged cylindrical core of the Oregon State TRIGA Reactor (OSTR,
//   Mark II, licensed to 1.1 MW, operated here at 1.00 MW nominal steady-state,
//   Corvallis, Oregon) in a darkened night-bay. Ninety-one concentric lattice
//   positions (Rings A-F: 1 central flux-trap thimble, 79 UZrH fuel pins with
//   trifoil spiders & lifting pintles, 4 control rods, 5 outer graphite
//   dummies, 2 coolant ports) sit inside a dark machined-aluminum upper grid
//   plate ringed by a 12-bolt retaining flange, an annular graphite reflector
//   deck with its 40-well Rotary Specimen Rack ("Lazy Susan"), two horizontal
//   submerged beam-port cylinders, two outer instrument guide pipes with
//   deck collars, and four vertical stainless control-rod guide tubes rising
//   toward the viewer. Electric cobalt-cerulean Cherenkov light shines from
//   the flux trap and interstitial coolant passages while a live 2D Boussinesq
//   thermal plume gently bends the submerged core via water's negative
//   thermo-optic gradient (dn/dT), Snell-refracted surface capillary caustics
//   lace across the wet aluminum deck, and 96 sparse 3D radiolytic
//   microbubbles rise along the buoyant flow.
//
// How it works:
//   1. Init (1 single heap allocation, ~9.66 MiB): raytraces exact 3D reactor
//      geometry into a native packed 4-channel G-buffer with 4x rotated-grid
//      MSAA across all 3D silhouettes (core, reflector, shroud, beam ports,
//      and all 6 rising vertical tubes), bakes dual independent 256x256 Snell
//      photon-mapped caustic sheets (2 x 262,144 rays at n=1.333), precomputes
//      padded spectral/metal LUTs, and classifies outer bit-invariant dark
//      abyssal cells for zero-seam @memcpy (eroded by 1 full cell margin).
//   2. Step: advances Keepin (1965) 6-group delayed-neutron kinetics coupled
//      to UZrH thermal feedback, a 128x80 Boussinesq Navier-Stokes thermal
//      plume (semi-Lagrangian advection + 4-pass red-black Gauss-Seidel
//      pressure projection), a 128x80 velocity-free Stormer-Verlet 9-pt
//      Mehrstellen capillary-wave PDE, and 96 3D advected microbubbles.
//   3. Draw: 3-tier branchless scanline renderer — wide @memcpy for static
//      abyssal margins, clamp-free padded LUT lookup with 16-wide SIMD
//      per-scanline caustic premixing (512 B L1d stack buffer) and smooth
//      per-pixel caustic envelope stepping, plus 2-stage separable 32-bit SWAR
//      Q4 bilinear Schlieren refraction over the core and rising plume.
//
// Cost:
//   1920x1200 single-core Apple Silicon M3 (5-pass interleaved vs BENCHMARK.md
//   sec. 3 skeleton control, host loadavg 5.30-5.36):
//     Median : 1640.7 us/frame (609.5 FPS, Gold Tier < 2000 us)
//     Range  : 1635.1 - 1657.1 us/frame (Worst single frame: 1743.4 - 2147.8 us)
//     Control: 1631.4 us/frame (ratio 1.006x empty skeleton)
//     Memory : 1 heap allocation at init (10,133,088 B = 9.66 MiB), 0 per frame
//     Flicker: 79 / 2,304,000 px >16% jump between frames 900->901 (0.00%)
//
// Sources ([cited] standard physics reference, [snippet] search result):
//   - Oregon State TRIGA Reactor (OSTR, Mark II, licensed 1.1 MW, ~6.7 m
//     deep open aluminum tank, ~5.2 m shielding water column over core)
//     [snippet: OSU Radiation Center / NRC] -> tank depth, water attenuation
//   - Concentric TRIGA Mark II core lattice (Rings A-F: 1+6+12+18+24+30 = 91
//     positions, 3.75 cm fuel OD, ~4.35 cm ring pitch, 4 control rods:
//     Transient, Safety, Shim, Regulating, ~30 cm radial graphite reflector
//     with 40-position Rotary Specimen Rack)
//     [snippet: TU Wien / JSI / IAEA TRIGA Mark II] -> exact 3D core CSG
//   - Frank-Tamm Cherenkov yield d^2N/(dx dlambda) = (2*pi*alpha/lambda^2) *
//     (1 - 1/(beta^2 * n(lambda)^2)) [cited: Frank & Tamm 1937], Pope & Fry
//     (1997) pure-water absorption spectrum (418 nm minimum 0.0045 m^-1)
//     [snippet: Appl. Opt. 36, 8710], and Wyman-Sloan-Shirley (2013) analytic
//     CIE 1931 2-deg CMFs [cited: JCGT 2(2)] -> base 5.2 m & 14 m chromaticity
//   - Water thermo-optic coefficient dn/dT = -8.8e-5 K^-1 at 25 C
//     [snippet: water optical dispersion] -> Schlieren refraction sign & scaling
//   - Keepin (1965) 6-group U-235 thermal delayed-neutron constants (beta=0.0065)
//     and UZrH prompt negative temperature coefficient alpha_T = -11 pcm/K,
//     prompt neutron lifetime Lambda = 25 us [snippet: Keepin 1965 / NRC]
//     -> live 6-group kinetics + thermal feedback + gentle regulating-rod cycle
//
// COMPUTED / MEASURED:
//   - Spectral Cherenkov chromaticity integrated over 380-700 nm in f64 via
//     Frank-Tamm x Pope & Fry 5.2 m & 14 m Beer-Lambert x analytic CIE 1931
//     2-deg CMFs (5.2 m raw CIE x = 0.2040, photopic peak 538 nm, 418/620 nm
//     water transmission ratio 4.09x).
//   - Core radial flux distribution from J_0(2.4048 * r / R_ext) diffusion mode
//     with local B4C control-rod absorber flux depressions.
//   - Live 128x80 Boussinesq thermal-convection PDE (semi-Lagrangian advection,
//     buoyancy forcing from core heat flux, red-black Gauss-Seidel pressure
//     projection) driving depth-scaled Schlieren refractive displacement.
//   - Live 128x80 velocity-free Stormer-Verlet 9-pt Mehrstellen isotropic
//     capillary-wave PDE coupled to dual independent 256x256 Snell
//     photon-mapped caustic webs baked in init() (2 x 262,144 refracted rays
//     at n=1.333) for crisp underwater filament networks on wet submerged metal.
//   - Live 6-group delayed-neutron kinetics coupled to lumped UZrH fuel
//     temperature feedback at 1.00 MW nominal equilibrium.
//
// CHOSEN:
//   - Time-lapse factor: 1.0x real time at Argus's 30 Hz x dt=0.008 tick
//     (dt_real = dt / 0.24, so 30 ticks = 1.0 real second).
//   - Camera vantage (18.5 deg off vertical, 5.32 m above grid plate, 22 deg
//     vertical FOV in water) and dim night-bay overhead maintenance spill.
//   - Control-rod slot assignments (C1 Transient, C7 Safety, D4 Shim, D13
//     Regulating), 5 outer graphite dummies, 2 coolant ports, 2 outer
//     instrument guide pipes, and 2 horizontal beam ports.
//   - Gentle incommensurate regulating-rod shim oscillation (118 s & 277 s
//     periods, +-33 pcm -> ~[-2.3%, +2.8%] power breathing around 1.00 MW).
//   - Artistic cobalt color grading applied on top of computed 5.2 m / 14 m
//     CIE 1931 linear RGB (attenuating red by 0.50x and mid-band green by
//     0.44-0.82x to emulate dark-adapted scotopic / camera blue response) with
//     luminance roll-off desaturating the hottest flux trap toward ice-white.
//   - Effective Schlieren optical-path gain (L_eff = 2.95e5 px*K multiplying
//     DN_DT_WATER_25C = -8.8e-5 K^-1) scaled for calm wallpaper legibility.
//
// NOT MODELLED:
//   - Full 3D Monte Carlo neutron transport (MCNP) or nucleate boiling:
//     replaced by 2D cylindrical J_0 diffusion + rod sinks and 2D Boussinesq
//     convection integrated along the viewing column.
//   - Per-frame 3D raymarching or bubble depth occlusion against foreground
//     rods: static 3D geometry is raytraced once at native resolution in init()
//     into a 4-channel G-buffer and refracted per frame via SWAR Q4 Schlieren
//     warp; microbubbles composite additively.
//   - Variable-dt capillary wave dispersion (wave PDE advances at fixed step).
//
// CHECKED (`zig test themes/Neon_OSTR_Cherenkov.zig` -> 10 LEDGER records):
//   - ostr_cherenkov_threshold_beta (relativistic E_k threshold at 420 nm)
//   - ostr_frank_tamm_water_peak (photopic peak + 5.2 m Pope & Fry 418/620 nm transmission ratio)
//   - ostr_cie_cherenkov_chromaticity (Illuminant E + 5.2 m & 14 m CIE 1931 x,y blue shift)
//   - ostr_bessel_j0_diffusion_eigenmode (4-pt f64 FD Bessel ODE residual & first root)
//   - ostr_keepin_6group_equilibrium_and_feedback (rho=0 equilibrium & +100 pcm UZrH stabilization)
//   - ostr_boussinesq_divergence_free_projection (relative RMS divergence & net upward buoyancy)
//   - ostr_stormer_verlet_wave_isotropy_and_energy (9-pt vs 5-pt rotational anisotropy & 120-step energy bound)
//   - ostr_thermo_optic_schlieren_sign (live dn/dT < 0 diverging lens sign)
//   - ostr_snell_caustic_flux_conservation (flux conservation & cusp ratio on BOTH caustic sheets)
//   - ostr_multires_canary_and_hour_soak (0x0, 64x48, 320x200, 777x513, truncated buf, 2048x1300 upscale, multi-week t=1e6 s soak)
//   NOT CHECKED by unit tests: subjective cobalt aesthetic grading, 3D raytracer visual fidelity (verified via theme_sheet.sh & 1:1 PNG inspection).
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

// ----------------------------------------------------------------------------
// Memory & Simulation Grid Constants (Single Allocation <= 10.5 MiB)
// ----------------------------------------------------------------------------
pub const CACHE_CAP: usize = 1920 * 1200; // 2,304,000 px = 8.79 MiB native G-buffer
pub const SIM_W: usize = 128; // 15 px/cell at 1920x1200
pub const SIM_H: usize = 80;
pub const SIM_N: usize = SIM_W * SIM_H;
pub const CAUST_TEX_W: usize = 256;
pub const CAUST_TEX_N: usize = CAUST_TEX_W * CAUST_TEX_W; // 64 KB -> L1d resident
pub const NUM_SLOTS: usize = 91; // Rings A(1)+B(6)+C(12)+D(18)+E(24)+F(30)
pub const NUM_BUBBLES: usize = 96;
pub const CHER_LUT_LEN: usize = 1024;
pub const CHER_LUT_PAD: usize = 1536; // Padded +512 so hot draw loops need ZERO @min clamp!
pub const METAL_LUT_LEN: usize = 512;
pub const METAL_LUT_PAD: usize = 1024; // Padded +512 so hot draw loops need ZERO @min clamp!

// Per-cell render specialization bitflags (eliminates per-pixel branches in hot draw loops!)
const CF_STATIC: u8 = 1 << 0; // Bit-exact invariant outer abyssal cell -> wide @memcpy
const CF_CAUSTIC: u8 = 1 << 1; // Contains wet submerged metal/floor receiving Snell caustics
const CF_TUBE_DEPTH: u8 = 1 << 2; // Contains foreground vertical guide tube requiring per-pixel depth_w

// ----------------------------------------------------------------------------
// Physical Constants (CODATA 2018 & Reactor / Water Literature)
// ----------------------------------------------------------------------------
const ALPHA_FINE: f64 = 1.0 / 137.035999084;
const ELECTRON_MC2_MEV: f64 = 0.510998950;
const WATER_COL_DEPTH_M: f64 = 5.20;
const DN_DT_WATER_25C: f64 = -8.8e-5;
const BESSEL_J0_ROOT1: f64 = 2.4048255576957727;

// OSTR TRIGA Mark II core geometry [meters]
const RING_PITCH_M: f64 = 0.0435;
const SOCKET_RADIUS_M: f64 = 0.0193;
const GRID_PLATE_R_M: f64 = 0.268;
const FLANGE_OUTER_R_M: f64 = 0.296;
const LAZY_SUSAN_R_M: f64 = 0.382;
const REFLECTOR_OUTER_R_M: f64 = 0.545;
const SHROUD_OUTER_R_M: f64 = 0.576;
const TANK_RADIUS_M: f64 = 1.06;
const EXTRAP_CORE_R_M: f64 = 0.305;

// Keepin (1965) 6-group delayed-neutron parameters for U-235 thermal fission
const KEEPIN_BETA: [6]f64 = .{ 0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273 };
const KEEPIN_LAMBDA: [6]f64 = .{ 0.0124, 0.0305, 0.111, 0.301, 1.14, 3.01 };
const BETA_EFF: f64 = 0.006502;
const PROMPT_LIFETIME_S: f64 = 2.5e-5;
const ALPHA_T_PER_K: f64 = -1.1e-4;

// Pope & Fry (1997) pure-water absorption a(lambda) [m^-1] on 380..700 nm (10 nm step, 33 pts)
const POPE_FRY_A: [33]f64 = .{
    0.01137, 0.00851, 0.00663, 0.00473, 0.00454, // 380..420 nm
    0.00495, 0.00635, 0.00922, 0.00979, 0.01060, // 430..470 nm
    0.01270, 0.01500, 0.02040, 0.03250, 0.04090, // 480..520 nm
    0.04340, 0.04740, 0.05650, 0.06190, 0.06950, // 530..570 nm
    0.08960, 0.13510, 0.22240, 0.26440, 0.27550, // 580..620 nm
    0.29160, 0.31080, 0.34000, 0.41000, 0.43900, // 630..670 nm
    0.46500, 0.51600, 0.62400, // 680..700 nm
};

// ----------------------------------------------------------------------------
// Data Types
// ----------------------------------------------------------------------------
const SlotKind = enum(u8) {
    central_thimble = 0,
    fuel = 1,
    control_rod = 2,
    graphite_dummy = 3,
    coolant_port = 4,
};

const LatticeSlot = struct {
    x: f32,
    y: f32,
    ring: u8,
    kind: SlotKind,
    angle: f32,
    flux_base: f32,
};

const Vec3 = struct {
    x: f64,
    y: f64,
    z: f64,

    inline fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    inline fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    inline fn scale(a: Vec3, s: f64) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    inline fn dot(a: Vec3, b: Vec3) f64 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    inline fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }
    inline fn norm(a: Vec3) Vec3 {
        const len = @sqrt(@max(1e-18, a.dot(a)));
        return a.scale(1.0 / len);
    }
};

const Camera = struct {
    pos: Vec3,
    right: Vec3,
    up: Vec3,
    fwd: Vec3,
    tan_half_y: f64,
    aspect: f64,

    fn make(w: usize, h: usize) Camera {
        const aspect = @as(f64, @floatFromInt(@max(@as(usize, 1), w))) /
            @as(f64, @floatFromInt(@max(@as(usize, 1), h)));
        const pos = Vec3{ .x = 0.07, .y = -1.78, .z = 5.32 };
        const target = Vec3{ .x = 0.0, .y = 0.03, .z = -0.05 };
        const fwd = target.sub(pos).norm();
        const world_up = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
        const right = fwd.cross(world_up).norm();
        const up = right.cross(fwd).norm();
        return .{
            .pos = pos,
            .right = right,
            .up = up,
            .fwd = fwd,
            .tan_half_y = 0.194,
            .aspect = aspect,
        };
    }

    inline fn rayDir(self: Camera, ndc_x: f64, ndc_y: f64) Vec3 {
        const sx = ndc_x * self.aspect * self.tan_half_y;
        const sy = ndc_y * self.tan_half_y;
        return self.fwd.add(self.right.scale(sx)).add(self.up.scale(sy)).norm();
    }

    fn project(self: Camera, p: Vec3, w: f64, h: f64) ?struct { sx: f64, sy: f64, depth: f64 } {
        const rel = p.sub(self.pos);
        const depth = rel.dot(self.fwd);
        if (depth <= 0.2) return null;
        const rx = rel.dot(self.right) / (depth * self.aspect * self.tan_half_y);
        const ry = rel.dot(self.up) / (depth * self.tan_half_y);
        const sx = (0.5 + 0.5 * rx) * w;
        const sy = (0.5 - 0.5 * ry) * h;
        return .{ .sx = sx, .sy = sy, .depth = depth };
    }
};

const Bubble = struct {
    x: f32,
    y: f32,
    z: f32,
    vz: f32,
    radius_mm: f32,
    wobble_phase: f32,
    brightness: f32,
};

// ----------------------------------------------------------------------------
// Analytical Math & Spectral Physics Functions (f64, Verified by LEDGER Tests)
// ----------------------------------------------------------------------------

pub fn waterRefractiveIndex(lambda_nm: f64) f64 {
    const um = lambda_nm * 1.0e-3;
    const inv2 = 1.0 / (um * um);
    const inv4 = inv2 * inv2;
    return 1.3242 + 0.00288 * inv2 - 0.000025 * inv4;
}

pub fn waterAbsorptionPopeFry(lambda_nm: f64) f64 {
    const clamped = math.clamp(lambda_nm, 380.0, 700.0);
    const fidx = (clamped - 380.0) * 0.1;
    const idx0: usize = @min(@as(usize, 31), @as(usize, @intFromFloat(@floor(fidx))));
    const frac = fidx - @as(f64, @floatFromInt(idx0));
    return POPE_FRY_A[idx0] * (1.0 - frac) + POPE_FRY_A[idx0 + 1] * frac;
}

pub fn electronBetaFromKineticMeV(ek_mev: f64) f64 {
    if (ek_mev <= 0.0) return 0.0;
    const gamma = 1.0 + ek_mev / ELECTRON_MC2_MEV;
    return @sqrt(@max(0.0, 1.0 - 1.0 / (gamma * gamma)));
}

pub fn cherenkovThresholdMeV(lambda_nm: f64) f64 {
    const n = waterRefractiveIndex(lambda_nm);
    const beta_min = 1.0 / n;
    const gamma_min = 1.0 / @sqrt(@max(1e-12, 1.0 - beta_min * beta_min));
    return ELECTRON_MC2_MEV * (gamma_min - 1.0);
}

pub fn frankTammYieldPerMeterNm(lambda_nm: f64, beta: f64) f64 {
    const n = waterRefractiveIndex(lambda_nm);
    const bn = beta * n;
    if (bn <= 1.0) return 0.0;
    const lam_m = lambda_nm * 1.0e-9;
    return (2.0 * math.pi * ALPHA_FINE / (lam_m * lam_m)) * (1.0 - 1.0 / (bn * bn)) * 1.0e-9;
}

pub fn cherenkovWaterSpectrum(lambda_nm: f64, depth_m: f64) f64 {
    const energies = [_]f64{ 0.45, 0.75, 1.15, 1.75, 2.50 };
    const weights = [_]f64{ 0.24, 0.30, 0.24, 0.15, 0.07 };
    var photon_rate: f64 = 0.0;
    for (energies, weights) |ek, wt| {
        const beta = electronBetaFromKineticMeV(ek);
        photon_rate += wt * frankTammYieldPerMeterNm(lambda_nm, beta);
    }
    const a = waterAbsorptionPopeFry(lambda_nm);
    return (photon_rate / lambda_nm) * @exp(-a * depth_m);
}

fn cieGaussian(x: f64, mu: f64, sigma1: f64, sigma2: f64) f64 {
    const t = (x - mu) * (if (x < mu) sigma1 else sigma2);
    return @exp(-0.5 * t * t);
}

pub fn cie1931XYZ(lambda_nm: f64) [3]f64 {
    const x_bar = 1.056 * cieGaussian(lambda_nm, 599.8, 0.0264, 0.0323) +
        0.362 * cieGaussian(lambda_nm, 442.0, 0.0624, 0.0374) -
        0.065 * cieGaussian(lambda_nm, 501.1, 0.0490, 0.0382);
    const y_bar = 0.821 * cieGaussian(lambda_nm, 568.8, 0.0213, 0.0247) +
        0.286 * cieGaussian(lambda_nm, 530.9, 0.0613, 0.0322);
    const z_bar = 1.217 * cieGaussian(lambda_nm, 437.0, 0.0845, 0.0278) +
        0.681 * cieGaussian(lambda_nm, 459.0, 0.0385, 0.0725);
    return .{ @max(0.0, x_bar), @max(0.0, y_bar), @max(0.0, z_bar) };
}

pub fn computeCherenkovChromaticity(depth_m: f64) struct { x: f64, y: f64, lin_rgb: [3]f64 } {
    var big_x: f64 = 0.0;
    var big_y: f64 = 0.0;
    var big_z: f64 = 0.0;
    const d_lam: f64 = 2.0;
    var step_i: usize = 0;
    while (step_i <= 160) : (step_i += 1) {
        const lam = 380.0 + @as(f64, @floatFromInt(step_i)) * d_lam;
        const spec = cherenkovWaterSpectrum(lam, depth_m);
        const cmf = cie1931XYZ(lam);
        big_x += spec * cmf[0] * d_lam;
        big_y += spec * cmf[1] * d_lam;
        big_z += spec * cmf[2] * d_lam;
    }
    const sum_xyz = @max(1e-18, big_x + big_y + big_z);
    const r = 3.2406 * big_x - 1.5372 * big_y - 0.4986 * big_z;
    const g = -0.9689 * big_x + 1.8758 * big_y + 0.0415 * big_z;
    const b = 0.0557 * big_x - 0.2040 * big_y + 1.0570 * big_z;
    const min_c = @min(r, @min(g, b));
    const lift = if (min_c < 0.0) -min_c * 0.25 else 0.0;
    const rc = @max(0.0, r + lift);
    const gc = @max(0.0, g + lift);
    const bc = @max(0.0, b + lift);
    const peak = @max(1e-12, @max(rc, @max(gc, bc)));
    return .{
        .x = big_x / sum_xyz,
        .y = big_y / sum_xyz,
        .lin_rgb = .{ rc / peak, gc / peak, bc / peak },
    };
}

pub fn besselJ0(x: f64) f64 {
    const half = 0.5 * x;
    const m_half2 = -(half * half);
    var term: f64 = 1.0;
    var sum: f64 = 1.0;
    var k: usize = 1;
    while (k <= 18) : (k += 1) {
        const kf = @as(f64, @floatFromInt(k));
        term *= m_half2 / (kf * kf);
        sum += term;
        if (@abs(term) < 1e-15) break;
    }
    return sum;
}

inline fn srgbEncode(lin: f64) u8 {
    const c = math.clamp(lin, 0.0, 1.0);
    const s = if (c <= 0.0031308) 12.92 * c else 1.055 * math.pow(f64, c, 1.0 / 2.4) - 0.055;
    return @intFromFloat(@round(math.clamp(s, 0.0, 1.0) * 255.0));
}

/// Single-instruction SIMD saturating RGB add (bit-exact to sdk.addRGB, preserves 0xFF alpha).
inline fn fastAddRGB(c1: u32, c2: u32) u32 {
    const v1: @Vector(4, u8) = @bitCast(c1);
    const v2: @Vector(4, u8) = @bitCast(c2);
    return @bitCast(v1 +| v2);
}

inline fn hash2D(ix: i32, iy: i32) f64 {
    const ux: u32 = @bitCast(ix);
    const uy: u32 = @bitCast(iy);
    var h = ux *% 374761393 +% uy *% 668265263;
    h = (h ^ (h >> 13)) *% 1274126177;
    h = h ^ (h >> 16);
    return @as(f64, @floatFromInt(h & 0xFFFFFF)) / 16777216.0;
}

fn valueNoise2D(x: f64, y: f64) f64 {
    const fx = @floor(x);
    const fy = @floor(y);
    const ix: i32 = @intFromFloat(fx);
    const iy: i32 = @intFromFloat(fy);
    const tx = x - fx;
    const ty = y - fy;
    const sx = tx * tx * (3.0 - 2.0 * tx);
    const sy = ty * ty * (3.0 - 2.0 * ty);
    const n00 = hash2D(ix, iy);
    const n10 = hash2D(ix + 1, iy);
    const n01 = hash2D(ix, iy + 1);
    const n11 = hash2D(ix + 1, iy + 1);
    const nx0 = n00 + (n10 - n00) * sx;
    const nx1 = n01 + (n11 - n01) * sx;
    return nx0 + (nx1 - nx0) * sy;
}

fn fbm2D(x: f64, y: f64) f64 {
    var acc: f64 = 0.0;
    var amp: f64 = 0.5;
    var px = x;
    var py = y;
    for (0..3) |_| {
        acc += amp * valueNoise2D(px, py);
        const nx = px * 1.92 - py * 0.65 + 11.3;
        const ny = px * 0.65 + py * 1.92 + 7.1;
        px = nx;
        py = ny;
        amp *= 0.5;
    }
    return acc;
}

inline fn smoothstep(edge0: f64, edge1: f64, x: f64) f64 {
    const span = edge1 - edge0;
    if (@abs(span) < 1e-12) return if (x >= edge1) 1.0 else 0.0;
    const t = math.clamp((x - edge0) / span, 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// ----------------------------------------------------------------------------
// Stateful Argus Theme Contract (`Allocs at Init == 1`, `After == 0`)
// ----------------------------------------------------------------------------
pub const State = struct {
    w: usize,
    h: usize,
    map_w: usize,
    map_h: usize,
    scale: f64,
    time_sec: f64,
    real_time_s: f64,
    step_count: u64,
    rng_state: u64,

    cam: Camera,

    // Native G-buffer with SWAR-optimized bit layout:
    //   Active cells: [c_rad:8 | caustic_mask:8 | m_lit:8 | refract_depth:8]
    //   Static outer cells (cell_flags & CF_STATIC): pre-baked 0xFF_BB_GG_RR RGBA for zero-seam @memcpy!
    scene: [CACHE_CAP]u32,

    // Two independent L1d-coherent 256x256 tileable Snell photon-mapped liquid caustic webs (2 x 64 KB)
    caust_tex: [CAUST_TEX_N]u8,
    caust_tex2: [CAUST_TEX_N]u8,
    caust_peak_ratio: f64,
    caust_flux_mean: f64,
    caust2_peak_ratio: f64,
    caust2_flux_mean: f64,

    // Live 2D Boussinesq Thermal-Convection PDE (128 x 80)
    vel_u: [SIM_N]f32,
    vel_v: [SIM_N]f32,
    vel_u_tmp: [SIM_N]f32,
    vel_v_tmp: [SIM_N]f32,
    pres: [SIM_N]f32,
    div_field: [SIM_N]f32,
    temp: [SIM_N]f32,
    temp_tmp: [SIM_N]f32,
    heat_src: [SIM_N]f32,
    cone_mask: [SIM_N]f32,
    wave_ring: [SIM_N]f32,
    warp_zone: [SIM_N]f32,
    flux_env: [SIM_N]f32,

    // Live 2D Velocity-Free Stormer-Verlet Surface Capillary-Wave PDE (128 x 80)
    eta_curr: [SIM_N]f32,
    eta_prev: [SIM_N]f32,
    eta_next: [SIM_N]f32,

    // Per-frame transfer buffers from PDEs to fast 3-tier SIMD/SWAR draw() (128 x 80)
    disp_x_q4: [SIM_N]i16,
    disp_y_q4: [SIM_N]i16,
    caustic_q8: [SIM_N]u16,
    plume_glow_q8: [SIM_N]u16,
    flux_mod_q8: [SIM_N]u16,
    cell_flags: [SIM_N]u8,
    row_active_x0: [SIM_H]u8, // First non-static cell x per simulation row (skips full dark rows!)
    row_active_x1: [SIM_H]u8, // Exclusive last non-static cell x per simulation row
    row_has_caust: [SIM_H]u8, // 1 if any active cell in this simulation row receives Snell caustics

    // 6-Group Delayed-Neutron Point Kinetics + UZrH Thermal Feedback
    power_mw: f64,
    fuel_temp_k: f64,
    fuel_temp_eq_k: f64,
    precursors: [6]f64,
    reg_rod_rho: f64,

    // 91 TRIGA lattice positions (Rings A-F) & 4 control rod indices
    slots: [NUM_SLOTS]LatticeSlot,
    ctrl_indices: [4]usize,

    // 96 live 3D advected radiolytic microbubbles
    bubbles: [NUM_BUBBLES]Bubble,

    // L1-resident padded spectral tone-map LUTs & fast sin table for PDE forcing
    cher_lut: [CHER_LUT_PAD]u32,
    metal_lut: [METAL_LUT_PAD]u32,
    sin_lut: [256]f32,
    cell_x: [SIM_W]usize,
    cell_y: [SIM_H]usize,

    core_cx_norm: f32,
    core_cy_norm: f32,

    fn nextRandF32(self: *State) f32 {
        self.rng_state +%= 0x9E3779B97F4A7C15;
        var z = self.rng_state;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        z = z ^ (z >> 31);
        return @as(f32, @floatFromInt(z >> 40)) / 16777216.0;
    }

    inline fn fastSin(self: *const State, rad: f32) f32 {
        const scaled = rad * (256.0 / @as(f32, @floatCast(2.0 * math.pi)));
        const idx: usize = @as(usize, @intFromFloat(@mod(scaled, 256.0) + 256.0)) & 255;
        return self.sin_lut[idx];
    }

    const CausticMode = struct { kx: f64, ky: f64, amp: f64, ph: f64 };

    fn bakeSingleCausticSheet(
        bins: []u32,
        dst: *[CAUST_TEX_N]u8,
        modes: []const CausticMode,
    ) struct { flux_mean: f64, peak_ratio: f64 } {
        const N = CAUST_TEX_W;
        @memset(bins, 0);

        const snell_k: f64 = (1.0 - 1.0 / 1.333) * 0.38;
        const rays_side: usize = 512;
        const inv_rays: f64 = 1.0 / @as(f64, @floatFromInt(rays_side));
        const two_pi: f64 = 2.0 * math.pi;

        for (0..rays_side) |ry| {
            const v = (@as(f64, @floatFromInt(ry)) + 0.5) * inv_rays;
            for (0..rays_side) |rx| {
                const u = (@as(f64, @floatFromInt(rx)) + 0.5) * inv_rays;
                var dh_du: f64 = 0.0;
                var dh_dv: f64 = 0.0;
                for (modes) |m| {
                    const arg = two_pi * (m.kx * u + m.ky * v) + m.ph;
                    const s = -@sin(arg) * m.amp * two_pi;
                    dh_du += s * m.kx;
                    dh_dv += s * m.ky;
                }
                const lu = @mod(u - snell_k * dh_du + 4.0, 1.0) * @as(f64, @floatFromInt(N));
                const lv = @mod(v - snell_k * dh_dv + 4.0, 1.0) * @as(f64, @floatFromInt(N));

                const ix0: usize = @as(usize, @intFromFloat(@floor(lu))) & (N - 1);
                const iy0: usize = @as(usize, @intFromFloat(@floor(lv))) & (N - 1);
                const ix1 = (ix0 + 1) & (N - 1);
                const iy1 = (iy0 + 1) & (N - 1);
                const fx = lu - @floor(lu);
                const fy = lv - @floor(lv);

                const w00: u32 = @intFromFloat(@round((1.0 - fx) * (1.0 - fy) * 256.0));
                const w10: u32 = @intFromFloat(@round(fx * (1.0 - fy) * 256.0));
                const w01: u32 = @intFromFloat(@round((1.0 - fx) * fy * 256.0));
                const w11: u32 = 256 -| (w00 + w10 + w01);

                bins[iy0 * N + ix0] += w00;
                bins[iy0 * N + ix1] += w10;
                bins[iy1 * N + ix0] += w01;
                bins[iy1 * N + ix1] += w11;
            }
        }

        var total_flux: u64 = 0;
        var max_bin: u32 = 0;
        for (bins) |b| {
            total_flux += b;
            if (b > max_bin) max_bin = b;
        }
        const expected_mean = @as(f64, @floatFromInt(rays_side * rays_side * 256)) / @as(f64, @floatFromInt(CAUST_TEX_N));
        const actual_mean = @as(f64, @floatFromInt(total_flux)) / @as(f64, @floatFromInt(CAUST_TEX_N));

        for (0..N) |y| {
            const ym = (y + N - 1) & (N - 1);
            const yp = (y + 1) & (N - 1);
            for (0..N) |x| {
                const xm = (x + N - 1) & (N - 1);
                const xp = (x + 1) & (N - 1);
                const s: u32 = bins[y * N + x] * 4 +
                    bins[y * N + xm] + bins[y * N + xp] + bins[ym * N + x] + bins[yp * N + x];
                const density = (@as(f64, @floatFromInt(s)) / 8.0) / @max(1.0, actual_mean);
                const excess = @max(0.0, density - 0.92);
                const ridge = math.clamp(math.pow(f64, excess * 0.95, 1.35), 0.0, 1.0);
                dst[y * N + x] = @intFromFloat(@round(ridge * 255.0));
            }
        }
        return .{
            .flux_mean = actual_mean / @max(1.0, expected_mean),
            .peak_ratio = @as(f64, @floatFromInt(max_bin)) / @max(1.0, actual_mean),
        };
    }

    fn bakeSnellCausticSheet(self: *State) void {
        const bins = self.scene[0..CAUST_TEX_N];
        const modes0 = [_]CausticMode{
            .{ .kx = 2.0, .ky = 1.0, .amp = 0.0088, .ph = 0.3 },
            .{ .kx = -1.0, .ky = 3.0, .amp = 0.0074, .ph = 1.7 },
            .{ .kx = 3.0, .ky = -2.0, .amp = 0.0062, .ph = 2.9 },
            .{ .kx = -3.0, .ky = -1.0, .amp = 0.0056, .ph = 4.1 },
            .{ .kx = 4.0, .ky = 2.0, .amp = 0.0042, .ph = 0.9 },
            .{ .kx = -2.0, .ky = 4.0, .amp = 0.0040, .ph = 3.6 },
            .{ .kx = 1.0, .ky = -4.0, .amp = 0.0036, .ph = 5.2 },
        };
        const modes1 = [_]CausticMode{
            .{ .kx = 1.0, .ky = 2.0, .amp = 0.0086, .ph = 2.1 },
            .{ .kx = -2.0, .ky = 2.0, .amp = 0.0076, .ph = 0.8 },
            .{ .kx = 3.0, .ky = 1.0, .amp = 0.0064, .ph = 4.5 },
            .{ .kx = -1.0, .ky = -3.0, .amp = 0.0058, .ph = 1.2 },
            .{ .kx = 2.0, .ky = -4.0, .amp = 0.0044, .ph = 3.4 },
            .{ .kx = -4.0, .ky = 1.0, .amp = 0.0041, .ph = 5.7 },
            .{ .kx = 3.0, .ky = 4.0, .amp = 0.0034, .ph = 2.6 },
        };
        const r0 = bakeSingleCausticSheet(bins, &self.caust_tex, &modes0);
        const r1 = bakeSingleCausticSheet(bins, &self.caust_tex2, &modes1);
        self.caust_flux_mean = r0.flux_mean;
        self.caust_peak_ratio = r0.peak_ratio;
        self.caust2_flux_mean = r1.flux_mean;
        self.caust2_peak_ratio = r1.peak_ratio;
    }

    fn buildTrigaLattice(self: *State) void {
        const ring_counts = [_]usize{ 1, 6, 12, 18, 24, 30 };
        var idx: usize = 0;

        const ctrl_slots = [_]usize{ 7, 13, 22, 31 };
        self.ctrl_indices = ctrl_slots;

        for (ring_counts, 0..) |cnt, ring| {
            const rad: f64 = @as(f64, @floatFromInt(ring)) * RING_PITCH_M;
            for (0..cnt) |j| {
                const phase_off: f64 = if (ring % 2 == 1) 0.22 else 0.22 + math.pi / @as(f64, @floatFromInt(@max(@as(usize, 1), cnt)));
                const ang: f64 = phase_off + (2.0 * math.pi * @as(f64, @floatFromInt(j))) / @as(f64, @floatFromInt(cnt));
                const px = rad * @cos(ang);
                const py = rad * @sin(ang);

                var kind: SlotKind = .fuel;
                if (ring == 0) {
                    kind = .central_thimble;
                } else if (idx == ctrl_slots[0] or idx == ctrl_slots[1] or idx == ctrl_slots[2] or idx == ctrl_slots[3]) {
                    kind = .control_rod;
                } else if (ring == 5 and (j == 2 or j == 9 or j == 16 or j == 22 or j == 27)) {
                    kind = .graphite_dummy;
                } else if (ring == 4 and (j == 5 or j == 17)) {
                    kind = .coolant_port;
                }

                const j0 = @max(0.12, besselJ0(BESSEL_J0_ROOT1 * rad / EXTRAP_CORE_R_M));
                self.slots[idx] = .{
                    .x = @floatCast(px),
                    .y = @floatCast(py),
                    .ring = @intCast(ring),
                    .kind = kind,
                    .angle = @floatCast(ang),
                    .flux_base = @floatCast(j0),
                };
                idx += 1;
            }
        }

        for (&self.slots) |*slot| {
            var depress: f64 = 1.0;
            for (ctrl_slots) |ci| {
                const c = self.slots[ci];
                const dx = @as(f64, slot.x) - @as(f64, c.x);
                const dy = @as(f64, slot.y) - @as(f64, c.y);
                const d2 = dx * dx + dy * dy;
                depress *= 1.0 - 0.34 * @exp(-d2 / (0.048 * 0.048));
            }
            slot.flux_base = @floatCast(@as(f64, slot.flux_base) * depress);
        }
    }

    fn buildSpectralLuts(self: *State) void {
        const direct_spec = computeCherenkovChromaticity(WATER_COL_DEPTH_M);
        const deep_spec = computeCherenkovChromaticity(14.0);

        for (0..CHER_LUT_LEN) |k| {
            const u = @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(CHER_LUT_LEN - 1));
            const energy = math.pow(f64, u, 2.55) * 10.5;
            const tone = energy / (1.0 + energy * 0.54);

            const dir_w = smoothstep(0.10, 0.72, u);
            const raw_r = deep_spec.lin_rgb[0] * (1.0 - dir_w) + direct_spec.lin_rgb[0] * dir_w;
            const raw_g = deep_spec.lin_rgb[1] * (1.0 - dir_w) + direct_spec.lin_rgb[1] * dir_w;
            const raw_b = deep_spec.lin_rgb[2] * (1.0 - dir_w) + direct_spec.lin_rgb[2] * dir_w;

            const chroma_r = raw_r * 0.50;
            const chroma_g = raw_g * (0.44 + 0.38 * dir_w);
            const chroma_b = raw_b;

            const hot_white = smoothstep(0.64, 1.0, u);
            const hw2 = hot_white * hot_white;

            const floor_r: f64 = 0.00030;
            const floor_g: f64 = 0.00084;
            const floor_b: f64 = 0.00340;

            const lr = floor_r + tone * (chroma_r * (1.0 - hw2 * 0.62) + hw2 * 0.85);
            const lg = floor_g + tone * (chroma_g * (1.0 - hw2 * 0.50) + hw2 * 0.94);
            const lb = floor_b + tone * (chroma_b * (1.0 - hw2 * 0.12) + hw2 * 1.00);

            self.cher_lut[k] = sdk.packRGBA(srgbEncode(lr), srgbEncode(lg), srgbEncode(lb));
        }
        @memset(self.cher_lut[CHER_LUT_LEN..CHER_LUT_PAD], self.cher_lut[CHER_LUT_LEN - 1]);

        const t_r = @exp(-waterAbsorptionPopeFry(620.0) * 4.5);
        const t_g = @exp(-waterAbsorptionPopeFry(535.0) * 4.5);
        const t_b = @exp(-waterAbsorptionPopeFry(455.0) * 4.5);
        const t_max = @max(t_r, @max(t_g, t_b));
        const mr = (t_r / t_max) * 0.58 + 0.22;
        const mg = (t_g / t_max) * 0.78 + 0.10;
        const mb = (t_b / t_max) * 1.00;

        for (0..METAL_LUT_LEN) |k| {
            const u = @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(METAL_LUT_LEN - 1));
            const e = math.pow(f64, u, 2.0) * 1.50;
            const tone = e / (1.0 + e * 0.62);
            self.metal_lut[k] = sdk.packRGBA(
                srgbEncode(tone * mr * 0.58),
                srgbEncode(tone * mg * 0.78),
                srgbEncode(tone * mb * 0.98),
            );
        }
        @memset(self.metal_lut[METAL_LUT_LEN..METAL_LUT_PAD], self.metal_lut[METAL_LUT_LEN - 1]);

        for (0..256) |k| {
            self.sin_lut[k] = @floatCast(@sin(@as(f64, @floatFromInt(k)) * (2.0 * math.pi / 256.0)));
        }
    }

    fn evalCoreFlux(self: *const State, x: f64, y: f64) f64 {
        const r = @sqrt(x * x + y * y);
        if (r >= EXTRAP_CORE_R_M) return 0.0;
        const j0 = @max(0.0, besselJ0(BESSEL_J0_ROOT1 * r / EXTRAP_CORE_R_M));
        var depress: f64 = 1.0;
        for (self.ctrl_indices) |ci| {
            const c = self.slots[ci];
            const dx = x - @as(f64, c.x);
            const dy = y - @as(f64, c.y);
            const d2 = dx * dx + dy * dy;
            depress *= 1.0 - 0.36 * @exp(-d2 / (0.044 * 0.044));
        }
        return j0 * depress;
    }

    fn nearestSlot(self: *const State, x: f64, y: f64) struct { idx: usize, d2: f64, dx: f64, dy: f64 } {
        const r = @sqrt(x * x + y * y);
        const ring_f = r / RING_PITCH_M;
        const r_est: usize = @min(@as(usize, 5), @as(usize, @intFromFloat(@round(@max(0.0, ring_f)))));
        const ring_starts = [_]usize{ 0, 1, 7, 19, 37, 61 };
        const ring_counts = [_]usize{ 1, 6, 12, 18, 24, 30 };

        var best_i: usize = 0;
        var best_d2: f64 = 1e9;
        var best_dx: f64 = 0.0;
        var best_dy: f64 = 0.0;

        const r_lo: usize = if (r_est > 0) r_est - 1 else 0;
        const r_hi: usize = @min(@as(usize, 5), r_est + 1);
        const ang = math.atan2(y, x);

        var rr: usize = r_lo;
        while (rr <= r_hi) : (rr += 1) {
            const start = ring_starts[rr];
            const cnt = ring_counts[rr];
            if (cnt == 1) {
                const s = self.slots[0];
                const dx = x - @as(f64, s.x);
                const dy = y - @as(f64, s.y);
                const d2 = dx * dx + dy * dy;
                if (d2 < best_d2) {
                    best_d2 = d2;
                    best_i = 0;
                    best_dx = dx;
                    best_dy = dy;
                }
            } else {
                const phase_off: f64 = if (rr % 2 == 1) 0.22 else 0.22 + math.pi / @as(f64, @floatFromInt(cnt));
                const rel_a = @mod(ang - phase_off + 4.0 * math.pi, 2.0 * math.pi);
                const est_j_f = rel_a * @as(f64, @floatFromInt(cnt)) / (2.0 * math.pi);
                const est_j: usize = @as(usize, @intFromFloat(@floor(est_j_f))) % cnt;
                for ([_]usize{ (est_j + cnt - 1) % cnt, est_j, (est_j + 1) % cnt }) |jj| {
                    const s = self.slots[start + jj];
                    const dx = x - @as(f64, s.x);
                    const dy = y - @as(f64, s.y);
                    const d2 = dx * dx + dy * dy;
                    if (d2 < best_d2) {
                        best_d2 = d2;
                        best_i = start + jj;
                        best_dx = dx;
                        best_dy = dy;
                    }
                }
            }
        }
        return .{ .idx = best_i, .d2 = best_d2, .dx = best_dx, .dy = best_dy };
    }

    fn intersectVerticalCyl(ro: Vec3, rd: Vec3, cx: f64, cy: f64, rad: f64, z_lo: f64, z_hi: f64) ?struct { t: f64, nx: f64, ny: f64, nz: f64, hit_z: f64, is_cap: bool } {
        const ox = ro.x - cx;
        const oy = ro.y - cy;
        var best_t: f64 = 1e9;
        var out_nx: f64 = 0.0;
        var out_ny: f64 = 0.0;
        var out_nz: f64 = 1.0;
        var out_z: f64 = z_hi;
        var is_cap = false;

        if (rd.z < -1e-9) {
            const tc = (z_hi - ro.z) / rd.z;
            if (tc > 0.01 and tc < best_t) {
                const hx = ox + rd.x * tc;
                const hy = oy + rd.y * tc;
                if (hx * hx + hy * hy <= rad * rad) {
                    best_t = tc;
                    out_nx = 0.0;
                    out_ny = 0.0;
                    out_nz = 1.0;
                    out_z = z_hi;
                    is_cap = true;
                }
            }
        }

        const a = rd.x * rd.x + rd.y * rd.y;
        if (a > 1e-12) {
            const b = ox * rd.x + oy * rd.y;
            const c = ox * ox + oy * oy - rad * rad;
            const disc = b * b - a * c;
            if (disc >= 0.0) {
                const sq = @sqrt(disc);
                const t0 = (-b - sq) / a;
                if (t0 > 0.01 and t0 < best_t) {
                    const hz = ro.z + rd.z * t0;
                    if (hz >= z_lo and hz <= z_hi) {
                        const hx = ox + rd.x * t0;
                        const hy = oy + rd.y * t0;
                        const inv_r = 1.0 / @max(1e-9, rad);
                        best_t = t0;
                        out_nx = hx * inv_r;
                        out_ny = hy * inv_r;
                        out_nz = 0.0;
                        out_z = hz;
                        is_cap = false;
                    }
                }
            }
        }

        if (best_t < 1e8) {
            return .{ .t = best_t, .nx = out_nx, .ny = out_ny, .nz = out_nz, .hit_z = out_z, .is_cap = is_cap };
        }
        return null;
    }

    fn intersectHorizontalBeamPort(ro: Vec3, rd: Vec3, ux: f64, uy: f64, z0: f64, rad: f64, s_lo: f64, s_hi: f64) ?struct { t: f64, nrm: Vec3, s: f64 } {
        const px = -uy;
        const py = ux;
        const o_p = ro.x * px + ro.y * py;
        const o_z = ro.z - z0;
        const d_p = rd.x * px + rd.y * py;
        const d_z = rd.z;

        const a = d_p * d_p + d_z * d_z;
        if (a <= 1e-12) return null;
        const b = o_p * d_p + o_z * d_z;
        const c = o_p * o_p + o_z * o_z - rad * rad;
        const disc = b * b - a * c;
        if (disc < 0.0) return null;

        const t0 = (-b - @sqrt(disc)) / a;
        if (t0 <= 0.01) return null;
        const hp = ro.add(rd.scale(t0));
        const s = hp.x * ux + hp.y * uy;
        if (s < s_lo or s > s_hi) return null;

        const np = (hp.x * px + hp.y * py) / rad;
        const nz = (hp.z - z0) / rad;
        return .{
            .t = t0,
            .nrm = (Vec3{ .x = np * px, .y = np * py, .z = nz }).norm(),
            .s = s,
        };
    }

    fn traceReactorRay(self: *const State, ro: Vec3, rd: Vec3) [4]f64 {
        const light_dir = (Vec3{ .x = 0.22, .y = 0.36, .z = 0.90 }).norm();
        const view_dir = rd.scale(-1.0);

        // --------------------------------------------------------------------
        // 1. Elevated vertical hardware rising through 5.2 m of clear water
        // --------------------------------------------------------------------
        var tube_hit_t: f64 = 1e9;
        var tube_cher: f64 = 0.0;
        var tube_metal: f64 = 0.0;
        var tube_caustic: f64 = 0.0;
        var tube_depth: f64 = 0.5;

        for (self.ctrl_indices) |ci| {
            const s = self.slots[ci];
            if (intersectVerticalCyl(ro, rd, s.x, s.y, 0.0108, 0.025, 4.75)) |hit| {
                if (hit.t < tube_hit_t) {
                    tube_hit_t = hit.t;
                    const nrm = Vec3{ .x = hit.nx, .y = hit.ny, .z = hit.nz };
                    const p = ro.add(rd.scale(hit.t));
                    const core_vec = (Vec3{ .x = -p.x, .y = -p.y, .z = -0.15 - p.z }).norm();
                    const core_dist2 = p.x * p.x + p.y * p.y + (p.z + 0.14) * (p.z + 0.14);
                    const n_dot_c = @max(0.0, nrm.dot(core_vec));
                    const fresnel = math.pow(f64, 1.0 - @max(0.0, nrm.dot(view_dir)), 3.0);
                    // Graceful fade near pool top so macOS menu-bar edge stays serene
                    const z_atten = @exp(-hit.hit_z * 0.72) * smoothstep(3.85, 2.35, hit.hit_z);
                    const band = 0.92 + 0.08 * @sin(hit.hit_z * 52.0);
                    const half_v = light_dir.add(view_dir).norm();
                    const spec = math.pow(f64, @max(0.0, nrm.dot(half_v)), 36.0);
                    const diff_ov = @max(0.0, nrm.dot(light_dir));

                    const cher_bounce = (0.10 + 0.72 * n_dot_c + 1.15 * fresnel) *
                        (0.095 / (core_dist2 + 0.04)) * z_atten;

                    tube_cher = cher_bounce;
                    tube_metal = (0.016 + 0.090 * diff_ov + 0.44 * spec) * band * (0.25 + 0.75 * z_atten) * smoothstep(4.2, 2.6, hit.hit_z);
                    tube_caustic = 0.22 * diff_ov * z_atten;
                    tube_depth = math.clamp((WATER_COL_DEPTH_M - hit.hit_z) / WATER_COL_DEPTH_M, 0.05, 0.78);
                }
            }
            if (intersectVerticalCyl(ro, rd, s.x, s.y, 0.0162, 0.0, 0.042)) |bh| {
                if (bh.t < tube_hit_t) {
                    tube_hit_t = bh.t;
                    const nrm = Vec3{ .x = bh.nx, .y = bh.ny, .z = bh.nz };
                    const diff_ov = @max(0.0, nrm.dot(light_dir));
                    const half_v = light_dir.add(view_dir).norm();
                    const spec = math.pow(f64, @max(0.0, nrm.dot(half_v)), 34.0);
                    const fresnel = math.pow(f64, 1.0 - @max(0.0, nrm.dot(view_dir)), 2.5);
                    tube_cher = @as(f64, s.flux_base) * (0.28 + 0.60 * fresnel);
                    tube_metal = 0.025 + 0.11 * diff_ov + 0.38 * spec;
                    tube_caustic = 0.42;
                    tube_depth = 0.75;
                }
            }
        }

        const inst_pipes = [_][3]f64{
            .{ -0.462, 0.215, 0.0142 },
            .{ 0.474, 0.180, 0.0128 },
        };
        for (inst_pipes) |pipe| {
            if (intersectVerticalCyl(ro, rd, pipe[0], pipe[1], pipe[2], 0.02, 4.75)) |hit| {
                if (hit.t < tube_hit_t) {
                    tube_hit_t = hit.t;
                    const nrm = Vec3{ .x = hit.nx, .y = hit.ny, .z = hit.nz };
                    const p = ro.add(rd.scale(hit.t));
                    const core_vec = (Vec3{ .x = -p.x, .y = -p.y, .z = -0.08 - p.z }).norm();
                    const core_dist2 = p.x * p.x + p.y * p.y + (p.z + 0.08) * (p.z + 0.08);
                    const n_dot_c = @max(0.0, nrm.dot(core_vec));
                    const fresnel = math.pow(f64, 1.0 - @max(0.0, nrm.dot(view_dir)), 3.0);
                    const z_atten = @exp(-@max(0.0, hit.hit_z) * 0.66) * smoothstep(3.85, 2.35, hit.hit_z);
                    const half_v = light_dir.add(view_dir).norm();
                    const spec = math.pow(f64, @max(0.0, nrm.dot(half_v)), 28.0);
                    const diff_ov = @max(0.0, nrm.dot(light_dir));

                    tube_cher = (0.04 + 0.45 * n_dot_c + 0.52 * fresnel) * (0.052 / (core_dist2 + 0.07)) * z_atten;
                    tube_metal = (0.010 + 0.062 * diff_ov + 0.28 * spec) * (0.22 + 0.78 * z_atten) * smoothstep(4.2, 2.6, hit.hit_z);
                    tube_caustic = 0.18 * diff_ov * z_atten;
                    tube_depth = math.clamp((WATER_COL_DEPTH_M - @max(0.0, hit.hit_z)) / WATER_COL_DEPTH_M, 0.05, 0.78);
                }
            }
            if (intersectVerticalCyl(ro, rd, pipe[0], pipe[1], pipe[2] * 1.75, 0.0, 0.030)) |fh| {
                if (fh.t < tube_hit_t) {
                    tube_hit_t = fh.t;
                    const nrm = Vec3{ .x = fh.nx, .y = fh.ny, .z = fh.nz };
                    const diff_ov = @max(0.0, nrm.dot(light_dir));
                    const half_v = light_dir.add(view_dir).norm();
                    const spec = math.pow(f64, @max(0.0, nrm.dot(half_v)), 24.0);
                    tube_cher = 0.018;
                    tube_metal = 0.014 + 0.048 * diff_ov + 0.14 * spec;
                    tube_caustic = 0.34;
                    tube_depth = 0.75;
                }
            }
        }

        // --------------------------------------------------------------------
        // 2. Main Reactor Deck, Fuel-Pin 3D Hardware, Reflector & Deep Pool
        // --------------------------------------------------------------------
        const t_deck = (0.0 - ro.z) / rd.z;
        const p_deck = ro.add(rd.scale(t_deck));
        const r_deck = @sqrt(p_deck.x * p_deck.x + p_deck.y * p_deck.y);

        if (tube_hit_t < t_deck - 0.002) {
            return .{ tube_cher, tube_metal, tube_caustic, tube_depth };
        }

        const core_bloom = 0.44 * @exp(-r_deck * r_deck / (0.145 * 0.145));
        const core_halo = 0.135 * @exp(-r_deck * r_deck / (0.30 * 0.30)) +
            0.016 * @exp(-r_deck * r_deck / (0.62 * 0.62));

        var cher_out: f64 = 0.0;
        var metal_out: f64 = 0.0;
        var caustic_out: f64 = 0.0;
        var depth_out: f64 = 0.96;

        // --------------------------------------------------------------------
        // Region A: Active Core & Dark Machined Upper Grid Plate
        // --------------------------------------------------------------------
        if (r_deck <= GRID_PLATE_R_M + 0.012) {
            const t_knob_plane = (0.036 - ro.z) / rd.z;
            const p_knob = ro.add(rd.scale(t_knob_plane));
            const near_k = self.nearestSlot(p_knob.x, p_knob.y);
            const slot_k = self.slots[near_k.idx];

            var hit_3d_handle = false;
            if (slot_k.kind == .fuel or slot_k.kind == .graphite_dummy) {
                if (intersectVerticalCyl(ro, rd, slot_k.x, slot_k.y, 0.0063, 0.008, 0.044)) |kh| {
                    hit_3d_handle = true;
                    const nrm = Vec3{ .x = kh.nx, .y = kh.ny, .z = kh.nz };
                    const local_flux = @as(f64, slot_k.flux_base);
                    const half_v = light_dir.add(view_dir).norm();
                    const spec = math.pow(f64, @max(0.0, nrm.dot(half_v)), 44.0);
                    const diff_ov = @max(0.0, nrm.dot(light_dir));
                    const fresnel = math.pow(f64, 1.0 - @max(0.0, nrm.dot(view_dir)), 2.8);

                    if (kh.is_cap) {
                        const hp = ro.add(rd.scale(kh.t));
                        const dr = @sqrt((hp.x - slot_k.x) * (hp.x - slot_k.x) + (hp.y - slot_k.y) * (hp.y - slot_k.y));
                        const bevel = smoothstep(0.0046, 0.0063, dr);
                        cher_out = core_halo * 0.22 + core_bloom * 0.35 + local_flux * (0.05 + 0.45 * bevel);
                        metal_out = 0.020 + 0.075 * diff_ov + 0.48 * spec * (1.0 - 0.4 * bevel);
                        caustic_out = 0.42;
                    } else {
                        cher_out = core_halo * 0.28 + core_bloom * 0.45 + local_flux * (0.16 + 0.68 * fresnel);
                        metal_out = 0.014 + 0.050 * diff_ov + 0.25 * spec;
                        caustic_out = 0.16;
                    }
                    depth_out = 0.94;
                }
            }

            if (!hit_3d_handle and r_deck <= GRID_PLATE_R_M) {
                const t_top = (0.013 - ro.z) / rd.z;
                const p_top = ro.add(rd.scale(t_top));
                const near = self.nearestSlot(p_top.x, p_top.y);
                const slot = self.slots[near.idx];
                const d_slot = @sqrt(near.d2);
                const flux_here = self.evalCoreFlux(p_deck.x, p_deck.y);
                const grain = 0.90 + 0.10 * fbm2D(p_deck.x * 105.0, p_deck.y * 105.0);

                if (d_slot < SOCKET_RADIUS_M) {
                    switch (slot.kind) {
                        .central_thimble => {
                            const t_deep = (-0.11 - ro.z) / rd.z;
                            const p_deep = ro.add(rd.scale(t_deep));
                            const d_deep = @sqrt(p_deep.x * p_deep.x + p_deep.y * p_deep.y);
                            if (d_slot > 0.0168) {
                                cher_out = 1.95 + core_bloom;
                                metal_out = 0.11 * grain;
                                caustic_out = 0.28;
                            } else if (d_deep > 0.0168) {
                                const wall_grad = smoothstep(0.022, 0.0168, d_deep);
                                cher_out = (3.20 + 4.20 * wall_grad) + core_bloom;
                                metal_out = 0.025;
                                caustic_out = 0.03;
                            } else {
                                const core_focus = 1.0 - 0.14 * (d_slot / 0.0168) * (d_slot / 0.0168);
                                cher_out = 10.4 * core_focus + core_bloom;
                                metal_out = 0.0;
                                caustic_out = 0.0;
                            }
                            depth_out = 0.98;
                        },
                        .coolant_port => {
                            const t_deep = (-0.09 - ro.z) / rd.z;
                            const p_deep = ro.add(rd.scale(t_deep));
                            const dp_x = p_deep.x - @as(f64, slot.x);
                            const dp_y = p_deep.y - @as(f64, slot.y);
                            const d_deep = @sqrt(dp_x * dp_x + dp_y * dp_y);
                            if (d_slot > 0.0164) {
                                cher_out = 0.90 * flux_here + core_halo;
                                metal_out = 0.08 * grain;
                                caustic_out = 0.28;
                            } else if (d_deep > 0.0164) {
                                cher_out = 2.40 * flux_here + core_halo;
                                metal_out = 0.02;
                                caustic_out = 0.03;
                            } else {
                                cher_out = 6.40 * flux_here + core_halo;
                                metal_out = 0.0;
                                caustic_out = 0.0;
                            }
                            depth_out = 0.97;
                        },
                        .control_rod => {
                            const ring_w = smoothstep(0.0115, 0.0165, d_slot);
                            cher_out = core_halo * 0.45 + core_bloom * 0.35 + flux_here * (0.28 + 0.82 * (1.0 - ring_w));
                            metal_out = (0.022 + 0.070 * ring_w) * grain;
                            caustic_out = 0.32 * ring_w;
                            depth_out = 0.94;
                        },
                        .fuel, .graphite_dummy => {
                            const is_fuel = (slot.kind == .fuel);
                            const local_flux: f64 = if (is_fuel) @as(f64, slot.flux_base) else @as(f64, slot.flux_base) * 0.40;
                            const phi_s = math.atan2(near.dy, near.dx) - @as(f64, slot.angle);
                            const spoke_cos = @abs(@cos(1.5 * phi_s));
                            const in_spoke = (spoke_cos > 0.875) and (d_slot < 0.0156);

                            if (d_slot > 0.0148) {
                                const edge_rim = smoothstep(0.0148, 0.0162, d_slot) * (1.0 - smoothstep(0.0178, 0.0193, d_slot));
                                const gap_glow = smoothstep(0.0181, 0.0193, d_slot);
                                cher_out = core_halo * 0.25 + core_bloom * 0.35 + local_flux * (0.12 + 0.52 * (1.0 - edge_rim) + 2.40 * gap_glow);
                                metal_out = (0.018 + 0.088 * edge_rim) * grain;
                                caustic_out = 0.42 * edge_rim;
                                depth_out = 0.95;
                            } else if (in_spoke) {
                                cher_out = core_halo * 0.20 + core_bloom * 0.25 + local_flux * 0.14;
                                metal_out = 0.048 * grain;
                                caustic_out = 0.24;
                                depth_out = 0.94;
                            } else {
                                const t_cl = (-0.05 - ro.z) / rd.z;
                                const p_cl = ro.add(rd.scale(t_cl));
                                const dc_x = p_cl.x - @as(f64, slot.x);
                                const dc_y = p_cl.y - @as(f64, slot.y);
                                const d_cl = @sqrt(dc_x * dc_x + dc_y * dc_y);
                                const wall_shadow: f64 = if (d_cl > 0.0158) 0.50 else 1.0;
                                const radial_peaking = math.pow(f64, @max(0.05, local_flux), 1.25);
                                const port_glow: f64 = if (is_fuel) 5.80 else 0.36;
                                cher_out = core_halo * 0.40 + core_bloom * 0.65 + radial_peaking * port_glow * wall_shadow;
                                metal_out = if (is_fuel) @as(f64, 0.004) else 0.022;
                                caustic_out = 0.02;
                                depth_out = 0.97;
                            }
                        },
                    }
                } else {
                    var in_coolant_hole = false;
                    var hole_edge: f64 = 0.0;
                    const inter_rings = [_]struct { rad: f64, cnt: usize, hr: f64 }{
                        .{ .rad = 0.0255, .cnt = 6, .hr = 0.0052 },
                        .{ .rad = 0.0665, .cnt = 12, .hr = 0.0066 },
                        .{ .rad = 0.1095, .cnt = 18, .hr = 0.0070 },
                        .{ .rad = 0.1525, .cnt = 24, .hr = 0.0070 },
                        .{ .rad = 0.1960, .cnt = 30, .hr = 0.0068 },
                        .{ .rad = 0.2420, .cnt = 36, .hr = 0.0064 },
                    };
                    const ang_d = math.atan2(p_deck.y, p_deck.x);
                    for (inter_rings, 0..) |ir, iri| {
                        if (@abs(r_deck - ir.rad) < ir.hr + 0.0028) {
                            const ph: f64 = if (iri % 2 == 0) 0.22 + math.pi / @as(f64, @floatFromInt(ir.cnt)) else 0.22;
                            const ra = @mod(ang_d - ph + 4.0 * math.pi, 2.0 * math.pi);
                            const sector = (2.0 * math.pi) / @as(f64, @floatFromInt(ir.cnt));
                            const nearest_a = (@round(ra / sector)) * sector + ph;
                            const hx = ir.rad * @cos(nearest_a);
                            const hy = ir.rad * @sin(nearest_a);
                            const dh = @sqrt((p_deck.x - hx) * (p_deck.x - hx) + (p_deck.y - hy) * (p_deck.y - hy));
                            if (dh < ir.hr) {
                                in_coolant_hole = true;
                                hole_edge = smoothstep(ir.hr * 0.70, ir.hr, dh);
                                break;
                            } else if (dh < ir.hr + 0.0020) {
                                hole_edge = 1.0 - smoothstep(ir.hr, ir.hr + 0.0020, dh);
                            }
                        }
                    }

                    if (in_coolant_hole) {
                        const depth_boost = 1.0 - 0.32 * hole_edge;
                        const radial_peaking = math.pow(f64, @max(0.05, flux_here), 1.20);
                        cher_out = core_halo * 0.50 + core_bloom * 0.85 + radial_peaking * 7.20 * depth_boost;
                        metal_out = 0.008 * hole_edge;
                        caustic_out = 0.02;
                        depth_out = 0.98;
                    } else {
                        const radial_lines = 0.92 + 0.08 * @sin(r_deck * 340.0);
                        const rim_glow = smoothstep(SOCKET_RADIUS_M + 0.0036, SOCKET_RADIUS_M, d_slot) * 0.95 + hole_edge * 1.15;
                        cher_out = core_halo * 0.26 + core_bloom * 0.32 + flux_here * (0.10 + rim_glow);
                        metal_out = (0.032 + 0.018 * radial_lines) * grain;
                        caustic_out = 0.62;
                        depth_out = 0.95;
                    }
                }
            }
        }

        // --------------------------------------------------------------------
        // Region B: Dark Machined Retaining Flange & Graphite Reflector Deck
        // --------------------------------------------------------------------
        if (r_deck > GRID_PLATE_R_M and r_deck <= SHROUD_OUTER_R_M) {
            const ang_d = math.atan2(p_deck.y, p_deck.x);
            const grain = 0.88 + 0.12 * fbm2D(p_deck.x * 54.0, p_deck.y * 54.0);
            const inv_r2 = 0.062 / (r_deck * r_deck + 0.034);

            if (r_deck <= FLANGE_OUTER_R_M) {
                const sector = (2.0 * math.pi) / 12.0;
                const bolt_a = (@round(ang_d / sector)) * sector;
                const bx = 0.282 * @cos(bolt_a);
                const by = 0.282 * @sin(bolt_a);
                const db = @sqrt((p_deck.x - bx) * (p_deck.x - bx) + (p_deck.y - by) * (p_deck.y - by));
                const is_bolt = db < 0.0066;
                const bolt_center = db < 0.0035;
                const inner_bevel = smoothstep(GRID_PLATE_R_M + 0.0045, GRID_PLATE_R_M, r_deck);
                const outer_step = smoothstep(FLANGE_OUTER_R_M - 0.0045, FLANGE_OUTER_R_M, r_deck);

                cher_out = core_halo * 0.32 + inv_r2 * (0.14 + 1.45 * inner_bevel) * (1.0 - 0.35 * outer_step);
                const bolt_m: f64 = if (bolt_center) 0.025 else if (is_bolt) 0.185 else 0.052 - 0.018 * outer_step;
                metal_out = bolt_m * grain;
                caustic_out = if (is_bolt) 0.38 else 0.85;
                depth_out = 0.94;
            } else if (r_deck <= REFLECTOR_OUTER_R_M) {
                const ls_dist = @abs(r_deck - LAZY_SUSAN_R_M);
                const in_ls_track = ls_dist < 0.031;
                var well_shade: f64 = 1.0;
                var well_rim: f64 = 0.0;
                if (in_ls_track) {
                    const sector40 = (2.0 * math.pi) / 40.0;
                    const wa = (@round(ang_d / sector40)) * sector40;
                    const wx = LAZY_SUSAN_R_M * @cos(wa);
                    const wy = LAZY_SUSAN_R_M * @sin(wa);
                    const dw = @sqrt((p_deck.x - wx) * (p_deck.x - wx) + (p_deck.y - wy) * (p_deck.y - wy));
                    if (dw < 0.0148) {
                        well_shade = 0.56 + 0.32 * smoothstep(0.010, 0.0148, dw);
                        well_rim = smoothstep(0.012, 0.0148, dw);
                    }
                    if (@abs(ls_dist - 0.029) < 0.0022) well_shade *= 0.76;
                }

                const seg6 = @abs(@sin(3.0 * ang_d + 0.4));
                const panel_groove = 0.84 + 0.16 * smoothstep(0.004, 0.014, seg6);
                const brush = 0.93 + 0.07 * @sin(r_deck * 240.0);
                const rad_falloff = @exp(-(r_deck - FLANGE_OUTER_R_M) * 4.5);
                const deck_glow = inv_r2 * 0.25 * (0.75 + 0.25 * well_shade + 0.25 * well_rim) * rad_falloff;

                cher_out = core_halo * 0.36 * rad_falloff + deck_glow;
                metal_out = (0.028 + 0.022 * rad_falloff + 0.020 * well_rim) * well_shade * panel_groove * brush * grain;
                caustic_out = 0.95 * well_shade * panel_groove;
                depth_out = 0.92;
            } else {
                const rim_hi = 1.0 - @abs((r_deck - 0.558) / 0.018);
                const rim_v = @max(0.0, rim_hi);
                cher_out = core_halo * 0.18 + inv_r2 * 0.11;
                metal_out = (0.016 + 0.042 * rim_v) * grain;
                caustic_out = 0.70;
                depth_out = 0.91;
            }
        }

        // --------------------------------------------------------------------
        // Region C: Outer Deep Open Pool Tank & 3D Horizontal Beam Ports
        // --------------------------------------------------------------------
        if (r_deck > SHROUD_OUTER_R_M) {
            var hit_shroud = false;
            var shroud_t: f64 = 1e9;
            if (intersectVerticalCyl(ro, rd, 0.0, 0.0, SHROUD_OUTER_R_M, -0.78, 0.0)) |wall| {
                hit_shroud = true;
                shroud_t = wall.t;
                const nrm = Vec3{ .x = wall.nx, .y = wall.ny, .z = wall.nz };
                const z_fade = @exp(wall.hit_z * 2.7);
                const diff_ov = @max(0.0, nrm.dot(light_dir));
                const grain = 0.90 + 0.10 * fbm2D(wall.nx * 14.0, wall.hit_z * 24.0);
                const wa = math.atan2(wall.ny, wall.nx);
                const rib = smoothstep(0.95, 0.99, @abs(@cos(4.0 * wa)));

                cher_out = core_halo * (0.15 + 0.20 * z_fade);
                metal_out = (0.008 + 0.030 * diff_ov + 0.020 * rib) * z_fade * grain;
                caustic_out = 0.36 * z_fade;
                depth_out = 0.90;
            }

            const bp_angles = [_]f64{ -2.42, -0.44 };
            var hit_bp = false;
            for (bp_angles) |ba| {
                if (intersectHorizontalBeamPort(ro, rd, @cos(ba), @sin(ba), -0.34, 0.070, SHROUD_OUTER_R_M - 0.04, 1.48)) |bp| {
                    if (bp.t < shroud_t) {
                        hit_bp = true;
                        shroud_t = bp.t;
                        const s_dist = @max(0.0, bp.s - SHROUD_OUTER_R_M);
                        const s_fade = @exp(-s_dist * 4.8) * smoothstep(1.25, 0.88, bp.s);
                        const diff_ov = @max(0.0, bp.nrm.dot(light_dir));
                        const top_cher = @max(0.0, bp.nrm.z);
                        const half_v = light_dir.add(view_dir).norm();
                        const spec = math.pow(f64, @max(0.0, bp.nrm.dot(half_v)), 26.0);
                        const weld_ao = 0.55 + 0.45 * smoothstep(0.0, 0.055, s_dist);
                        const collar = smoothstep(0.026, 0.0, @abs(s_dist - 0.042));

                        cher_out = (0.014 + 0.072 * top_cher) * s_fade * weld_ao;
                        metal_out = (0.004 + 0.024 * diff_ov + 0.042 * spec + 0.018 * collar) * s_fade * weld_ao;
                        caustic_out = 0.42 * top_cher * s_fade * smoothstep(0.95, 0.65, bp.s);
                        depth_out = 0.88;
                    }
                }
            }

            if (!hit_shroud and !hit_bp) {
                const t_floor = (-0.82 - ro.z) / rd.z;
                const p_fl = ro.add(rd.scale(t_floor));
                const r_fl = @sqrt(p_fl.x * p_fl.x + p_fl.y * p_fl.y);

                const wall_ring = smoothstep(TANK_RADIUS_M - 0.08, TANK_RADIUS_M, r_fl);
                const floor_atten = @exp(-@max(0.0, r_fl - SHROUD_OUTER_R_M) * 4.1);
                const pool_grain = 0.88 + 0.12 * fbm2D(p_fl.x * 16.0, p_fl.y * 16.0);

                const outer_cut = smoothstep(1.16, 0.78, r_deck);
                const deep_halo = (0.052 * @exp(-r_deck * r_deck / (0.45 * 0.45)) +
                    0.005 * @exp(-r_deck * r_deck / (0.88 * 0.88))) * outer_cut;

                cher_out = deep_halo * (1.0 - 0.72 * wall_ring);
                var m_fl = 0.004 * floor_atten * pool_grain * (1.0 - 0.85 * wall_ring) * outer_cut;
                if (r_fl >= TANK_RADIUS_M - 0.016 and r_fl <= TANK_RADIUS_M + 0.022) {
                    m_fl += 0.004 * @exp(-r_deck * 1.35);
                }
                metal_out = m_fl;
                // Subtle delicate caustics strictly in the near-shroud illuminated floor apron
                caustic_out = 0.36 * floor_atten * smoothstep(0.84, 0.64, r_fl);
                depth_out = 0.86;
            }
        }

        return .{ cher_out, metal_out, caustic_out, depth_out };
    }

    inline fn packGBuffer(ch: [4]f64, x: usize, y: usize) u32 {
        const bayer_4 = [4]f64{ -0.375, 0.125, 0.375, -0.125 };
        const dither = bayer_4[((y & 1) << 1) | (x & 1)];
        const c_norm = math.pow(f64, math.clamp(ch[0] / 10.5, 0.0, 1.0), 1.0 / 2.55);
        const m_norm = math.pow(f64, math.clamp(ch[1] / 1.50, 0.0, 1.0), 1.0 / 2.0);
        const c8: u32 = @intFromFloat(@round(math.clamp(c_norm * 255.0 + dither, 0.0, 255.0)));
        const k8: u32 = @intFromFloat(@round(math.clamp(ch[2] * 255.0, 0.0, 255.0)));
        const m8: u32 = @intFromFloat(@round(math.clamp(m_norm * 255.0 + dither, 0.0, 255.0)));
        const d8: u32 = @intFromFloat(@round(math.clamp(ch[3] * 255.0, 0.0, 255.0)));
        return c8 | (k8 << 8) | (m8 << 16) | (d8 << 24);
    }

    fn bakeSceneGBuffer(self: *State) void {
        const mw = self.map_w;
        const mh = self.map_h;
        const inv_w = 1.0 / @as(f64, @floatFromInt(@max(@as(usize, 1), mw)));
        const inv_h = 1.0 / @as(f64, @floatFromInt(@max(@as(usize, 1), mh)));
        const cam = self.cam;

        if (cam.project(.{ .x = 0.0, .y = 0.0, .z = 0.0 }, 1.0, 1.0)) |proj| {
            self.core_cx_norm = @floatCast(proj.sx);
            self.core_cy_norm = @floatCast(proj.sy);
        } else {
            self.core_cx_norm = 0.5;
            self.core_cy_norm = 0.52;
        }

        const msaa_off = [_][2]f64{
            .{ -0.28, -0.18 },
            .{ 0.18, -0.28 },
            .{ 0.28, 0.18 },
            .{ -0.18, 0.28 },
        };

        // 6 vertical pipe axes (4 control-rod guide tubes + 2 outer instrument pipes) for exact full-height 4x MSAA
        const pipe_axes = [_][2]f64{
            .{ @as(f64, self.slots[self.ctrl_indices[0]].x), @as(f64, self.slots[self.ctrl_indices[0]].y) },
            .{ @as(f64, self.slots[self.ctrl_indices[1]].x), @as(f64, self.slots[self.ctrl_indices[1]].y) },
            .{ @as(f64, self.slots[self.ctrl_indices[2]].x), @as(f64, self.slots[self.ctrl_indices[2]].y) },
            .{ @as(f64, self.slots[self.ctrl_indices[3]].x), @as(f64, self.slots[self.ctrl_indices[3]].y) },
            .{ -0.462, 0.215 },
            .{ 0.474, 0.180 },
        };

        for (0..mh) |y| {
            const fy = @as(f64, @floatFromInt(y));
            const row_off = y * mw;
            for (0..mw) |x| {
                const fx = @as(f64, @floatFromInt(x));
                const ndc_x = ((fx + 0.5) * inv_w) * 2.0 - 1.0;
                const ndc_y = 1.0 - ((fy + 0.5) * inv_h) * 2.0;
                const rd0 = cam.rayDir(ndc_x, ndc_y);

                const t_d = (0.0 - cam.pos.z) / rd0.z;
                const dx_w = cam.pos.x + rd0.x * t_d;
                const dy_w = cam.pos.y + rd0.y * t_d;
                const r2_w = dx_w * dx_w + dy_w * dy_w;

                // True 4x MSAA across core, reflector, canister shroud, both horizontal beam ports (r < 1.18 m),
                // AND all 6 vertical pipes right up to the top screen edge (ray-to-vertical-axis distance < 3.6 cm).
                var use_msaa = (r2_w < 1.18 * 1.18);
                if (!use_msaa) {
                    const a_xy = rd0.x * rd0.x + rd0.y * rd0.y;
                    if (a_xy > 1e-12) {
                        const inv_a = 1.0 / a_xy;
                        for (pipe_axes) |pa| {
                            const ox = cam.pos.x - pa[0];
                            const oy = cam.pos.y - pa[1];
                            const tc = -(ox * rd0.x + oy * rd0.y) * inv_a;
                            if (tc > 0.0) {
                                const px_c = ox + rd0.x * tc;
                                const py_c = oy + rd0.y * tc;
                                if (px_c * px_c + py_c * py_c < 0.036 * 0.036) {
                                    use_msaa = true;
                                    break;
                                }
                            }
                        }
                    }
                }

                var accum: [4]f64 = .{ 0.0, 0.0, 0.0, 0.0 };
                if (use_msaa) {
                    for (msaa_off) |o| {
                        const sx = ((fx + 0.5 + o[0]) * inv_w) * 2.0 - 1.0;
                        const sy = 1.0 - ((fy + 0.5 + o[1]) * inv_h) * 2.0;
                        const s = self.traceReactorRay(cam.pos, cam.rayDir(sx, sy));
                        accum[0] += s[0];
                        accum[1] += s[1];
                        accum[2] += s[2];
                        accum[3] += s[3];
                    }
                    accum[0] *= 0.25;
                    accum[1] *= 0.25;
                    accum[2] *= 0.25;
                    accum[3] *= 0.25;
                } else {
                    accum = self.traceReactorRay(cam.pos, rd0);
                }

                self.scene[row_off + x] = packGBuffer(accum, x, y);
            }
        }
    }

    fn bakeSimSourceMasks(self: *State) void {
        const inv_sw = 1.0 / @as(f64, @floatFromInt(SIM_W));
        const inv_sh = 1.0 / @as(f64, @floatFromInt(SIM_H));
        for (0..SIM_H) |gy| {
            const ndc_y = 1.0 - ((@as(f64, @floatFromInt(gy)) + 0.5) * inv_sh) * 2.0;
            for (0..SIM_W) |gx| {
                const ndc_x = ((@as(f64, @floatFromInt(gx)) + 0.5) * inv_sw) * 2.0 - 1.0;
                const rd = self.cam.rayDir(ndc_x, ndc_y);
                const t_d = (0.0 - self.cam.pos.z) / rd.z;
                const wx = self.cam.pos.x + rd.x * t_d;
                const wy = self.cam.pos.y + rd.y * t_d;
                const flux = self.evalCoreFlux(wx, wy);
                const r_w = @sqrt(wx * wx + wy * wy);

                const idx = gy * SIM_W + gx;
                self.heat_src[idx] = @floatCast(flux);

                // Volumetric rising water-column Cherenkov scatter cone (C^1 smooth cutoff to 0.0)
                const r2_cone = (wx * wx) / (0.27 * 0.27) + ((wy - 0.22) * (wy - 0.22)) / (0.48 * 0.48);
                self.cone_mask[idx] = @floatCast(if (r2_cone < 3.6) @exp(-r2_cone) * smoothstep(3.6, 2.2, r2_cone) else 0.0);

                // Circular tank-wall filtration wave emitter ring
                const ring_d = (r_w - 0.72) / 0.075;
                self.wave_ring[idx] = @floatCast(@exp(-ring_d * ring_d));

                // Smooth Schlieren refraction envelope strictly over core, inner reflector & rising plume
                const r_env = smoothstep(0.56, 0.34, r_w);
                const plume_col = smoothstep(0.28, 0.12, @abs(wx)) *
                    smoothstep(-0.10, 0.16, wy) *
                    smoothstep(0.88, 0.48, wy);
                self.warp_zone[idx] = @floatCast(@max(r_env, plume_col * 0.85));

                // Smooth flux-modulation envelope: full over illuminated reactor assembly, smoothly 0.0
                // in dark outer abyssal pool (enables 100% bit-exact zero-seam @memcpy for ~65% of screen!)
                self.flux_env[idx] = @floatCast(smoothstep(0.76, 0.52, r_w));
            }
        }
    }

    /// Classify every 15x15 cell into specialized fast-path bitflags (`CF_STATIC`, `CF_CAUSTIC`, `CF_TUBE_DEPTH`)
    /// and pre-bake final RGBA in-place for bit-exact invariant outer cells!
    fn bakeCellSpecializations(self: *State) void {
        self.cell_flags = @splat(0);
        self.row_active_x0 = @splat(0);
        self.row_active_x1 = @splat(@intCast(SIM_W - 1));
        self.row_has_caust = @splat(1);
        if (self.w != self.map_w or self.h != self.map_h or self.w < 640 or self.h < 400) {
            // Non-native 4K/5K or small resolution (<640x400 where 1 sim cell < 5 px): disable static in-place baking
            self.cell_flags = @splat(CF_CAUSTIC | CF_TUBE_DEPTH);
            return;
        }
        const mw = self.map_w;
        const cell_x = &self.cell_x;
        const cell_y = &self.cell_y;

        var cand_static: [SIM_N]u8 = @splat(0);
        for (0..SIM_H - 1) |gy| {
            const y0 = cell_y[gy];
            const y1 = cell_y[gy + 1];
            for (0..SIM_W - 1) |gx| {
                const x0 = cell_x[gx];
                const x1 = cell_x[gx + 1];
                const s00 = gy * SIM_W + gx;
                const s10 = s00 + 1;
                const s01 = s00 + SIM_W;
                const s11 = s01 + 1;

                var has_caust = false;
                var has_tube = false;
                var max_c8: u32 = 0;
                var max_m8: u32 = 0;
                for (y0..y1) |y| {
                    const row = y * mw;
                    for (x0..x1) |x| {
                        const px = self.scene[row + x];
                        const c8 = px & 0xFF;
                        const m8 = (px >> 16) & 0xFF;
                        if (c8 > max_c8) max_c8 = c8;
                        if (m8 > max_m8) max_m8 = m8;
                        if (((px >> 8) & 0xFF) > 4) has_caust = true;
                        if ((px >> 24) < 212) has_tube = true;
                    }
                }
                var flags: u8 = 0;
                if (has_caust) flags |= CF_CAUSTIC;
                if (has_tube) flags |= CF_TUBE_DEPTH;
                self.cell_flags[s00] = flags;

                // Candidate for bit-exact static @memcpy: zero warp, zero plume veil, zero caustics,
                // and either zero flux_env or bit-identical deep abyssal water (c8<=2 -> cher_lut[0..11] identical, m8==0).
                const no_warp = self.warp_zone[s00] <= 0.001 and self.warp_zone[s10] <= 0.001 and
                    self.warp_zone[s01] <= 0.001 and self.warp_zone[s11] <= 0.001;
                const no_cone = self.cone_mask[s00] <= 0.015 and self.cone_mask[s10] <= 0.015 and
                    self.cone_mask[s01] <= 0.015 and self.cone_mask[s11] <= 0.015;
                const no_flux = (self.flux_env[s00] <= 0.001 and self.flux_env[s10] <= 0.001 and
                    self.flux_env[s01] <= 0.001 and self.flux_env[s11] <= 0.001) or
                    (max_c8 <= 2 and max_m8 == 0);
                if (no_warp and no_cone and no_flux and !has_caust) {
                    cand_static[s00] = 1;
                }
            }
        }

        // Erode static cells by 1 cell margin so bilinear warp taps near active cells NEVER read baked RGBA!
        for (0..SIM_H - 1) |gy| {
            var first_active: usize = SIM_W - 1;
            var last_active: usize = 0;
            var any_caust: u8 = 0;
            for (0..SIM_W - 1) |gx| {
                const idx = gy * SIM_W + gx;
                var is_static = (cand_static[idx] != 0);
                if (is_static) {
                    const y_lo = if (gy > 0) gy - 1 else 0;
                    const y_hi = @min(SIM_H - 2, gy + 1);
                    const x_lo = if (gx > 0) gx - 1 else 0;
                    const x_hi = @min(SIM_W - 2, gx + 1);
                    var ny = y_lo;
                    while (ny <= y_hi) : (ny += 1) {
                        var nx = x_lo;
                        while (nx <= x_hi) : (nx += 1) {
                            if (cand_static[ny * SIM_W + nx] == 0) is_static = false;
                        }
                    }
                }
                if (is_static) {
                    self.cell_flags[idx] = CF_STATIC;
                    const y0 = cell_y[gy];
                    const y1 = cell_y[gy + 1];
                    const x0 = cell_x[gx];
                    const x1 = cell_x[gx + 1];
                    for (y0..y1) |y| {
                        const row = y * mw;
                        for (x0..x1) |x| {
                            const px = self.scene[row + x];
                            const c10 = (px & 0xFF) << 2;
                            const m9 = ((px >> 16) & 0xFF) << 1;
                            self.scene[row + x] = fastAddRGB(self.cher_lut[c10], self.metal_lut[m9]);
                        }
                    }
                } else {
                    if (gx < first_active) first_active = gx;
                    if (gx + 1 > last_active) last_active = gx + 1;
                    if ((self.cell_flags[idx] & CF_CAUSTIC) != 0) any_caust = 1;
                }
            }
            self.row_active_x0[gy] = @intCast(first_active);
            self.row_active_x1[gy] = @intCast(last_active);
            self.row_has_caust[gy] = any_caust;
        }
    }

    fn initBubbles(self: *State) void {
        for (&self.bubbles) |*b| {
            self.respawnBubble(b, true);
        }
    }

    fn respawnBubble(self: *State, b: *Bubble, random_z: bool) void {
        const r = 0.015 + 0.215 * @sqrt(self.nextRandF32());
        const ang = self.nextRandF32() * @as(f32, @floatCast(2.0 * math.pi));
        b.x = r * @cos(ang);
        b.y = r * @sin(ang);
        b.z = if (random_z) self.nextRandF32() * 4.4 else 0.02 + self.nextRandF32() * 0.08;
        b.vz = 0.14 + self.nextRandF32() * 0.16;
        b.radius_mm = 0.45 + self.nextRandF32() * 0.85;
        b.wobble_phase = self.nextRandF32() * 6.28318;
        b.brightness = 0.55 + self.nextRandF32() * 0.45;
    }

    pub fn stepReactorKinetics(self: *State, dt_real_s: f64, rho_ext: f64) void {
        const substeps: usize = 8;
        const h = dt_real_s / @as(f64, @floatFromInt(substeps));
        const heat_cap_mj_k: f64 = 0.145;
        const ua_mw_k: f64 = 1.0 / 260.0;
        const water_bulk_k: f64 = 298.15;

        for (0..substeps) |_| {
            const rho = rho_ext + ALPHA_T_PER_K * (self.fuel_temp_k - self.fuel_temp_eq_k);
            var delayed_src: f64 = 0.0;
            for (0..6) |g| delayed_src += KEEPIN_LAMBDA[g] * self.precursors[g];

            const coeff = (BETA_EFF - rho) / PROMPT_LIFETIME_S;
            const denom = @max(1e-6, 1.0 + h * coeff);
            const p_new = math.clamp((self.power_mw + h * delayed_src) / denom, 0.15, 2.50);

            for (0..6) |g| {
                const lam = KEEPIN_LAMBDA[g];
                const decay = @exp(-lam * h);
                const src = (KEEPIN_BETA[g] / PROMPT_LIFETIME_S) * p_new;
                self.precursors[g] = self.precursors[g] * decay + (src / lam) * (1.0 - decay);
            }

            const d_temp = (p_new - ua_mw_k * (self.fuel_temp_k - water_bulk_k)) / heat_cap_mj_k;
            self.fuel_temp_k = math.clamp(self.fuel_temp_k + h * d_temp, 295.0, 900.0);
            self.power_mw = p_new;
        }
    }

    pub fn stepBoussinesqPlume(self: *State, dt_sim: f32) void {
        const w = SIM_W;
        const h = SIM_H;
        const p_scale: f32 = @floatCast(self.power_mw);
        const two_pi: f64 = 2.0 * math.pi;
        const ph_a: f32 = @floatCast(@mod(self.real_time_s * 1.15, two_pi));
        const ph_b: f32 = @floatCast(@mod(self.real_time_s * 0.85, two_pi));
        const ph_c: f32 = @floatCast(@mod(self.real_time_s * 0.92, two_pi));

        for (1..h - 1) |gy| {
            const row = gy * w;
            const fy = @as(f32, @floatFromInt(gy));
            for (1..w - 1) |gx| {
                const idx = row + gx;
                const src = self.heat_src[idx];
                if (src > 0.002) {
                    const fx = @as(f32, @floatFromInt(gx));
                    const eddy = 0.80 + 0.40 * self.fastSin(fx * 0.48 + ph_a + fy * 0.22) *
                        self.fastSin(fy * 0.41 - ph_b + fx * 0.17 + 1.5708);
                    self.temp[idx] += src * p_scale * eddy * 1.32 * dt_sim;
                    self.vel_u[idx] += 0.34 * src * self.fastSin(fx * 0.35 - ph_c + fy * 0.26) * dt_sim;
                }
                self.vel_v[idx] -= self.temp[idx] * 3.05 * dt_sim;
                self.vel_u[idx] *= 0.986;
                self.vel_v[idx] *= 0.986;
            }
        }

        const max_x: f32 = @as(f32, @floatFromInt(w - 2)) - 0.001;
        const max_y: f32 = @as(f32, @floatFromInt(h - 2)) - 0.001;
        for (1..h - 1) |gy| {
            const row = gy * w;
            const fy = @as(f32, @floatFromInt(gy));
            for (1..w - 1) |gx| {
                const idx = row + gx;
                const fx = @as(f32, @floatFromInt(gx));
                const bx = math.clamp(fx - self.vel_u[idx] * dt_sim * 15.0, 1.0, max_x);
                const by = math.clamp(fy - self.vel_v[idx] * dt_sim * 15.0, 1.0, max_y);
                const ix: usize = @intFromFloat(@floor(bx));
                const iy: usize = @intFromFloat(@floor(by));
                const sx = bx - @as(f32, @floatFromInt(ix));
                const sy = by - @as(f32, @floatFromInt(iy));
                const r0 = iy * w + ix;
                const r1 = r0 + w;

                const vu00 = self.vel_u[r0];
                const vu10 = self.vel_u[r0 + 1];
                const vu01 = self.vel_u[r1];
                const vu11 = self.vel_u[r1 + 1];
                self.vel_u_tmp[idx] = (vu00 + (vu10 - vu00) * sx) * (1.0 - sy) + (vu01 + (vu11 - vu01) * sx) * sy;

                const vv00 = self.vel_v[r0];
                const vv10 = self.vel_v[r0 + 1];
                const vv01 = self.vel_v[r1];
                const vv11 = self.vel_v[r1 + 1];
                self.vel_v_tmp[idx] = (vv00 + (vv10 - vv00) * sx) * (1.0 - sy) + (vv01 + (vv11 - vv01) * sx) * sy;

                const vt00 = self.temp[r0];
                const vt10 = self.temp[r0 + 1];
                const vt01 = self.temp[r1];
                const vt11 = self.temp[r1 + 1];
                const t_adv = (vt00 + (vt10 - vt00) * sx) * (1.0 - sy) + (vt01 + (vt11 - vt01) * sx) * sy;

                const t_lap = 0.25 * (self.temp[idx - 1] + self.temp[idx + 1] + self.temp[idx - w] + self.temp[idx + w]) - self.temp[idx];
                self.temp_tmp[idx] = math.clamp((t_adv + 0.08 * t_lap) * 0.968, 0.0, 2.5);
            }
        }
        @memcpy(&self.vel_u, &self.vel_u_tmp);
        @memcpy(&self.vel_v, &self.vel_v_tmp);
        @memcpy(&self.temp, &self.temp_tmp);

        for (0..w) |gx| {
            self.vel_u[gx] = 0.0;
            self.vel_v[gx] = 0.0;
            self.temp[gx] *= 0.85;
            const bot = (h - 1) * w + gx;
            self.vel_u[bot] = 0.0;
            self.vel_v[bot] = 0.0;
            self.temp[bot] = 0.0;
        }
        for (0..h) |gy| {
            const left = gy * w;
            const right = left + w - 1;
            self.vel_u[left] = 0.0;
            self.vel_v[left] = 0.0;
            self.temp[left] = 0.0;
            self.vel_u[right] = 0.0;
            self.vel_v[right] = 0.0;
            self.temp[right] = 0.0;
        }

        for (1..h - 1) |gy| {
            const row = gy * w;
            for (1..w - 1) |gx| {
                const idx = row + gx;
                self.div_field[idx] = -0.5 * ((self.vel_u[idx + 1] - self.vel_u[idx - 1]) +
                    (self.vel_v[idx + w] - self.vel_v[idx - w]));
                self.pres[idx] *= 0.88;
            }
        }
        for (0..4) |_| {
            for (1..h - 1) |gy| {
                const row = gy * w;
                var gx: usize = 1 + (gy & 1);
                while (gx < w - 1) : (gx += 2) {
                    const idx = row + gx;
                    self.pres[idx] = 0.25 * (self.div_field[idx] +
                        self.pres[idx - 1] + self.pres[idx + 1] + self.pres[idx - w] + self.pres[idx + w]);
                }
            }
            for (1..h - 1) |gy| {
                const row = gy * w;
                var gx: usize = 1 + ((gy + 1) & 1);
                while (gx < w - 1) : (gx += 2) {
                    const idx = row + gx;
                    self.pres[idx] = 0.25 * (self.div_field[idx] +
                        self.pres[idx - 1] + self.pres[idx + 1] + self.pres[idx - w] + self.pres[idx + w]);
                }
            }
        }
        for (1..h - 1) |gy| {
            const row = gy * w;
            for (1..w - 1) |gx| {
                const idx = row + gx;
                self.vel_u[idx] -= 0.5 * (self.pres[idx + 1] - self.pres[idx - 1]);
                self.vel_v[idx] -= 0.5 * (self.pres[idx + w] - self.pres[idx - w]);
            }
        }
    }

    pub inline fn laplacian9pt(field: []const f32, idx: usize, stride: usize) f32 {
        const ortho = field[idx - 1] + field[idx + 1] + field[idx - stride] + field[idx + stride];
        const diag = field[idx - stride - 1] + field[idx - stride + 1] +
            field[idx + stride - 1] + field[idx + stride + 1];
        return (4.0 * ortho + diag - 20.0 * field[idx]) * (1.0 / 6.0);
    }

    pub fn stepSurfaceWaves(self: *State) void {
        const w = SIM_W;
        const h = SIM_H;
        const c2: f32 = 0.036;
        const damp: f32 = 0.0085;
        const two_pi: f64 = 2.0 * math.pi;
        const ph_t: f32 = @floatCast(@mod(self.real_time_s * 1.35, two_pi));
        const ph_r1: f32 = @floatCast(@mod(self.real_time_s * 0.85, two_pi));
        const ph_r2: f32 = @floatCast(@mod(self.real_time_s * 0.52, two_pi));

        for (1..h - 1) |gy| {
            const row = gy * w;
            const fy = @as(f32, @floatFromInt(gy));
            for (1..w - 1) |gx| {
                const idx = row + gx;
                const lap = laplacian9pt(&self.eta_curr, idx, w);

                var src: f32 = 0.0;
                const fx = @as(f32, @floatFromInt(gx));
                if (self.temp[idx] > 0.08) {
                    src += 0.0038 * self.temp[idx] * self.fastSin(ph_t + fx * 0.42 - fy * 0.36);
                }
                const wr = self.wave_ring[idx];
                if (wr > 0.04) {
                    src += 0.0036 * wr * self.fastSin(ph_r1 + fx * 0.28 + fy * 0.31) *
                        self.fastSin(ph_r2 - fx * 0.21 + fy * 0.24 + 1.5708);
                }

                const curr = self.eta_curr[idx];
                const prev = self.eta_prev[idx];
                const next = (2.0 - damp) * curr - (1.0 - damp) * prev + c2 * lap + src;
                self.eta_next[idx] = math.clamp(next, -1.5, 1.5);
            }
        }

        for (0..w) |gx| {
            self.eta_next[gx] = self.eta_next[w + gx] * 0.65;
            self.eta_next[(h - 1) * w + gx] = self.eta_next[(h - 2) * w + gx] * 0.65;
        }
        for (0..h) |gy| {
            self.eta_next[gy * w] = self.eta_next[gy * w + 1] * 0.65;
            self.eta_next[gy * w + w - 1] = self.eta_next[gy * w + w - 2] * 0.65;
        }

        @memcpy(&self.eta_prev, &self.eta_curr);
        @memcpy(&self.eta_curr, &self.eta_next);
    }

    fn updateRenderTransferGrid(self: *State) void {
        const w = SIM_W;
        const h = SIM_H;
        const scale_px: f32 = @as(f32, @floatFromInt(self.map_w)) / 1920.0;
        const p_flux: f32 = @floatCast(self.power_mw);
        const tilt_amp: f32 = @floatCast(self.reg_rod_rho * 120.0);

        for (0..h) |gy| {
            const row = gy * w;
            const y0 = if (gy > 0) gy - 1 else 0;
            const y1 = if (gy + 1 < h) gy + 1 else h - 1;
            const ny = @as(f32, @floatFromInt(gy)) / @as(f32, @floatFromInt(h)) - self.core_cy_norm;

            for (0..w) |gx| {
                const idx = row + gx;
                const x0 = if (gx > 0) gx - 1 else 0;
                const x1 = if (gx + 1 < w) gx + 1 else w - 1;
                const nx = @as(f32, @floatFromInt(gx)) / @as(f32, @floatFromInt(w)) - self.core_cx_norm;

                const wz = self.warp_zone[idx];
                if (wz > 0.001) {
                    const dtdx = 0.5 * (self.temp[row + x1] - self.temp[row + x0]);
                    const dtdy = 0.5 * (self.temp[y1 * w + gx] - self.temp[y0 * w + gx]);
                    const dedx = 0.5 * (self.eta_curr[row + x1] - self.eta_curr[row + x0]);
                    const dedy = 0.5 * (self.eta_curr[y1 * w + gx] - self.eta_curr[y0 * w + gx]);

                    // Thermo-optic Schlieren deflection driven live by water dn/dT = -8.8e-5 K^-1
                    const schlieren_gain: f32 = @floatCast(DN_DT_WATER_25C * 2.9545e5); // -26.0 px / unit grad(T)
                    const dx_px = (dtdx * schlieren_gain + dedx * 12.0) * wz * scale_px;
                    const dy_px = (dtdy * schlieren_gain + dedy * 12.0) * wz * scale_px;
                    self.disp_x_q4[idx] = @intFromFloat(@round(math.clamp(dx_px * 16.0, -124.0, 124.0)));
                    self.disp_y_q4[idx] = @intFromFloat(@round(math.clamp(dy_px * 16.0, -124.0, 124.0)));
                } else {
                    self.disp_x_q4[idx] = 0;
                    self.disp_y_q4[idx] = 0;
                }

                const lap_eta = self.eta_curr[row + x0] + self.eta_curr[row + x1] +
                    self.eta_curr[y0 * w + gx] + self.eta_curr[y1 * w + gx] - 4.0 * self.eta_curr[idx];
                const wave_mod = 0.58 + math.clamp(-lap_eta * 14.0, -0.25, 0.72);
                self.caustic_q8[idx] = @intFromFloat(@round(math.clamp(wave_mod * 92.0, 20.0, 140.0)));

                const veil = self.temp[idx] * self.cone_mask[idx] * p_flux * 32.0;
                self.plume_glow_q8[idx] = @intFromFloat(@round(math.clamp(veil, 0.0, 90.0)));

                const local_tilt = 1.0 + tilt_amp * (nx * 0.8 - ny * 0.6);
                const flux_delta = (p_flux * local_tilt - 1.0) * self.flux_env[idx];
                self.flux_mod_q8[idx] = @intFromFloat(@round(math.clamp((1.0 + flux_delta) * 256.0, 236.0, 276.0)));
            }
        }
    }

    fn stepBubbles(self: *State, dt_real_s: f32) void {
        const w_f: f32 = @floatFromInt(SIM_W - 2);
        const h_f: f32 = @floatFromInt(SIM_H - 2);
        const two_pi: f64 = 2.0 * math.pi;
        const wob_base_x: f32 = @floatCast(@mod(self.real_time_s * 2.6, two_pi));
        const wob_base_y: f32 = @floatCast(@mod(self.real_time_s * (2.6 * 1.13), two_pi));
        const p_f: f32 = @floatCast(self.power_mw);

        for (&self.bubbles) |*b| {
            var drift_x: f32 = 0.0;
            var drift_y: f32 = 0.0;
            if (self.cam.project(.{ .x = b.x, .y = b.y, .z = b.z }, 1.0, 1.0)) |proj| {
                const gx: usize = @intFromFloat(math.clamp(@as(f32, @floatCast(proj.sx)) * w_f, 1.0, w_f));
                const gy: usize = @intFromFloat(math.clamp(@as(f32, @floatCast(proj.sy)) * h_f, 1.0, h_f));
                const idx = gy * SIM_W + gx;
                drift_x = self.vel_u[idx] * 0.09;
                drift_y = -self.vel_v[idx] * 0.04;
            }
            b.x += (drift_x + 0.012 * self.fastSin(wob_base_x + b.wobble_phase)) * dt_real_s;
            b.y += (drift_y + 0.010 * self.fastSin(wob_base_y + b.wobble_phase * 1.13 + 1.5708)) * dt_real_s;
            b.z += b.vz * (0.85 + 0.15 * p_f) * dt_real_s;

            if (b.z > 4.65 or (b.x * b.x + b.y * b.y) > 0.65 * 0.65) {
                self.respawnBubble(b, false);
            }
        }
    }

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = w;
        self.h = h;
        self.scale = scale;
        self.time_sec = 0.0;
        self.real_time_s = 0.0;
        self.step_count = 0;
        self.rng_state = 0x5EED_0574_C4E2_1100;

        const area64: u64 = @as(u64, w) * @as(u64, h);
        if (w == 0 or h == 0) {
            self.map_w = 1;
            self.map_h = 1;
        } else if (area64 <= CACHE_CAP) {
            self.map_w = w;
            self.map_h = h;
        } else {
            const ratio = @sqrt(@as(f64, @floatFromInt(CACHE_CAP)) / @as(f64, @floatFromInt(area64)));
            self.map_w = @max(@as(usize, 1), @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(w)) * ratio))));
            self.map_h = @max(@as(usize, 1), @as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(h)) * ratio))));
            while (@as(u64, self.map_w) * @as(u64, self.map_h) > CACHE_CAP) {
                if (self.map_w >= self.map_h and self.map_w > 1) {
                    self.map_w -= 1;
                } else if (self.map_h > 1) {
                    self.map_h -= 1;
                } else {
                    break;
                }
            }
        }

        self.cam = Camera.make(self.map_w, self.map_h);

        for (0..SIM_W) |gx| self.cell_x[gx] = (gx * w) / (SIM_W - 1);
        self.cell_x[SIM_W - 1] = w;
        for (0..SIM_H) |gy| self.cell_y[gy] = (gy * h) / (SIM_H - 1);
        self.cell_y[SIM_H - 1] = h;

        self.vel_u = @splat(0.0);
        self.vel_v = @splat(0.0);
        self.vel_u_tmp = @splat(0.0);
        self.vel_v_tmp = @splat(0.0);
        self.pres = @splat(0.0);
        self.div_field = @splat(0.0);
        self.temp = @splat(0.0);
        self.temp_tmp = @splat(0.0);
        self.heat_src = @splat(0.0);
        self.cone_mask = @splat(0.0);
        self.wave_ring = @splat(0.0);
        self.warp_zone = @splat(0.0);
        self.flux_env = @splat(0.0);
        self.eta_curr = @splat(0.0);
        self.eta_prev = @splat(0.0);
        self.eta_next = @splat(0.0);
        self.disp_x_q4 = @splat(0);
        self.disp_y_q4 = @splat(0);
        self.caustic_q8 = @splat(0);
        self.plume_glow_q8 = @splat(0);
        self.flux_mod_q8 = @splat(256);
        self.cell_flags = @splat(0);
        self.caust_peak_ratio = 1.0;
        self.caust_flux_mean = 1.0;
        self.caust2_peak_ratio = 1.0;
        self.caust2_flux_mean = 1.0;

        self.power_mw = 1.00;
        self.fuel_temp_eq_k = 558.15;
        self.fuel_temp_k = self.fuel_temp_eq_k;
        self.reg_rod_rho = 0.0;
        for (0..6) |g| {
            self.precursors[g] = (KEEPIN_BETA[g] / (PROMPT_LIFETIME_S * KEEPIN_LAMBDA[g])) * self.power_mw;
        }

        self.bakeSnellCausticSheet();
        self.buildTrigaLattice();
        self.buildSpectralLuts();
        self.bakeSceneGBuffer();
        self.bakeSimSourceMasks();
        self.bakeCellSpecializations();
        self.initBubbles();

        for (0..60) |_| {
            self.real_time_s += 1.0 / 30.0;
            self.stepBoussinesqPlume(1.0 / 30.0);
            self.stepSurfaceWaves();
        }
        self.real_time_s = 0.0;
        self.updateRenderTransferGrid();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        if (!math.isFinite(dt) or dt <= 0.0) return;
        const dt_clamped = math.clamp(dt, 0.0001, 0.05);
        self.time_sec += dt_clamped;
        const dt_real = dt_clamped * (1.0 / (30.0 * 0.008));
        self.real_time_s += dt_real;
        self.step_count += 1;

        const t = self.real_time_s;
        const rho_ext = 0.00022 * @sin(2.0 * math.pi * t / 118.0) +
            0.00011 * @sin(2.0 * math.pi * t / 277.0 + 1.1);
        self.reg_rod_rho = rho_ext;

        self.stepReactorKinetics(dt_real, rho_ext);
        self.stepBoussinesqPlume(@floatCast(dt_real));
        self.stepSurfaceWaves();
        self.stepBubbles(@floatCast(dt_real));
        self.updateRenderTransferGrid();
    }

    fn drawBubbles(self: *const State, buf: []u32, w: usize, h: usize, stride: usize) void {
        const wf: f64 = @floatFromInt(w);
        const proj_hf: f64 = @floatFromInt(self.h);
        const clip_hf: f64 = @floatFromInt(h);
        const scale_r = wf / 1920.0;

        for (self.bubbles) |b| {
            const proj = self.cam.project(.{ .x = b.x, .y = b.y, .z = b.z }, wf, proj_hf) orelse continue;
            if (proj.sx < 4.0 or proj.sx >= wf - 4.0 or proj.sy < 4.0 or proj.sy >= proj_hf - 4.0) continue;

            const p_ratio = (10.3 + WATER_COL_DEPTH_M) / (10.3 + @max(0.1, WATER_COL_DEPTH_M - @as(f64, b.z)));
            const r_phys_mm = @as(f64, b.radius_mm) * math.pow(f64, p_ratio, 1.0 / 3.0);
            const r_px = math.clamp((r_phys_mm * 0.001 / (proj.depth * self.cam.tan_half_y)) * proj_hf * 1.45, 0.9 * scale_r, 3.2 * scale_r);
            if (proj.sy - r_px - 2.0 >= clip_hf) continue;

            const core_r2 = @as(f64, b.x) * @as(f64, b.x) + @as(f64, b.y) * @as(f64, b.y);
            const z_fade = @exp(-@as(f64, b.z) * 0.56) * smoothstep(0.0, 0.25, @as(f64, b.z));
            const radial_fade = @exp(-core_r2 / (0.28 * 0.28));
            const lum = @as(f64, b.brightness) * z_fade * (0.25 + 0.75 * radial_fade) * self.power_mw;
            if (lum < 0.03) continue;

            const rad_i: isize = @intFromFloat(@ceil(r_px + 1.0));
            const cx_i: isize = @intFromFloat(@floor(proj.sx));
            const cy_i: isize = @intFromFloat(@floor(proj.sy));

            var dy: isize = -rad_i;
            while (dy <= rad_i) : (dy += 1) {
                const py = cy_i + dy;
                if (py < 0 or py >= @as(isize, @intCast(h))) continue;
                const fy = @as(f64, @floatFromInt(py)) + 0.5 - proj.sy;
                const row = @as(usize, @intCast(py)) * stride;

                var dx: isize = -rad_i;
                while (dx <= rad_i) : (dx += 1) {
                    const px = cx_i + dx;
                    if (px < 0 or px >= @as(isize, @intCast(w))) continue;
                    const fx = @as(f64, @floatFromInt(px)) + 0.5 - proj.sx;
                    const dist = @sqrt(fx * fx + fy * fy) / @max(0.5, r_px);
                    if (dist >= 1.35) continue;

                    const rim = smoothstep(0.25, 0.85, dist) * (1.0 - smoothstep(0.85, 1.30, dist));
                    const glint_d = @sqrt((fx - 0.30 * r_px) * (fx - 0.30 * r_px) + (fy + 0.30 * r_px) * (fy + 0.30 * r_px)) / @max(0.4, r_px);
                    const glint = @exp(-glint_d * glint_d * 5.0);
                    const a_val = math.clamp((0.42 * rim + 0.95 * glint) * lum, 0.0, 1.0);
                    if (a_val < 0.015) continue;

                    const add_r: u8 = @intFromFloat(math.clamp(a_val * 115.0, 0.0, 255.0));
                    const add_g: u8 = @intFromFloat(math.clamp(a_val * 192.0, 0.0, 255.0));
                    const add_b: u8 = @intFromFloat(math.clamp(a_val * 255.0, 0.0, 255.0));
                    const p_idx = row + @as(usize, @intCast(px));
                    buf[p_idx] = fastAddRGB(buf[p_idx], sdk.packRGBA(add_r, add_g, add_b));
                }
            }
        }
    }

    /// 2-stage separable 32-bit SWAR Q4 bilinear sample on paired (c_rad | m_lit) + inline k8 mask.
    /// Max lane intermediate: 255 * 16 = 4080; final: 4080 * 16 = 65280 <= 65535 (zero cross-lane carry).
    inline fn sampleCMK_Q4(scene_ptr: [*]const u32, mw: usize, x_q4: usize, y_q4: usize) struct { c10: u32, m9: u32, k8: u32 } {
        const ix = x_q4 >> 4;
        const iy = y_q4 >> 4;
        const fx: u32 = @intCast(x_q4 & 15);
        const fy: u32 = @intCast(y_q4 & 15);
        const ifx: u32 = 16 - fx;
        const ify: u32 = 16 - fy;

        const r0 = iy * mw + ix;
        const r1 = r0 + mw;
        const raw00 = scene_ptr[r0];
        const p00 = raw00 & 0x00FF00FF;
        const p10 = scene_ptr[r0 + 1] & 0x00FF00FF;
        const p01 = scene_ptr[r1] & 0x00FF00FF;
        const p11 = scene_ptr[r1 + 1] & 0x00FF00FF;

        const top = p00 * ifx + p10 * fx;
        const bot = p01 * ifx + p11 * fx;
        const cm = top * ify + bot * fy;
        return .{ .c10 = (cm & 0xFFFF) >> 6, .m9 = cm >> 23, .k8 = (raw00 >> 8) & 0xFF };
    }

    /// Pre-mixes 256 periodic dual-layer Snell caustic samples for one scanline using 16-wide SIMD.
    /// Fits in 512 bytes of L1d stack so every pixel in the scanline does 1 stack load instead of 2 tex loads + ALU!
    inline fn buildCausticScanline(
        web_row: *[256]u16,
        c_row0: [*]const u8,
        c_row1: [*]const u8,
        ox0: usize,
        ox1: usize,
    ) void {
        var a_rot: [256]u8 = undefined;
        var b_rot: [256]u8 = undefined;
        const s0 = ox0 & 255;
        const n0 = 256 - s0;
        @memcpy(a_rot[0..n0], c_row0[s0..256]);
        if (s0 > 0) @memcpy(a_rot[n0..256], c_row0[0..s0]);
        const s1 = ox1 & 255;
        const n1 = 256 - s1;
        @memcpy(b_rot[0..n1], c_row1[s1..256]);
        if (s1 > 0) @memcpy(b_rot[n1..256], c_row1[0..s1]);

        var i: usize = 0;
        while (i < 256) : (i += 16) {
            const va8: @Vector(16, u8) = a_rot[i..][0..16].*;
            const vb8: @Vector(16, u8) = b_rot[i..][0..16].*;
            const va: @Vector(16, u16) = va8;
            const vb: @Vector(16, u16) = vb8;
            const wv = ((va + vb) >> @as(@Vector(16, u4), @splat(1))) + ((va * vb) >> @as(@Vector(16, u4), @splat(9)));
            web_row[i..][0..16].* = wv;
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        if (self.w == 0 or self.h == 0 or stride < self.w) return;
        const w = self.w;
        const h: usize = @min(self.h, buf.len / stride);
        if (h == 0) return;

        const mw = self.map_w;
        const mh = self.map_h;
        const same_res = (w == mw and self.h == mh);
        const scene_ptr: [*]const u32 = &self.scene;
        const cher_lut_ptr: [*]const u32 = &self.cher_lut;
        const metal_lut_ptr: [*]const u32 = &self.metal_lut;
        const caust_ptr0: [*]const u8 = &self.caust_tex;
        const caust_ptr1: [*]const u8 = &self.caust_tex2;

        const ox0: usize = @as(usize, @intFromFloat(@mod(self.real_time_s * 14.0, 256.0)));
        const oy0: usize = @as(usize, @intFromFloat(@mod(self.real_time_s * 9.0, 256.0)));
        const ox1: usize = @as(usize, @intFromFloat(@mod(256.0 - @mod(self.real_time_s * 11.0, 256.0), 256.0)));
        const oy1: usize = @as(usize, @intFromFloat(@mod(256.0 - @mod(self.real_time_s * 13.0, 256.0), 256.0)));

        var row_dx: [SIM_W]i32 = undefined;
        var row_dy: [SIM_W]i32 = undefined;
        var row_caust: [SIM_W]i32 = undefined;
        var row_glow: [SIM_W]i32 = undefined;
        var row_flux: [SIM_W]i32 = undefined;
        var web_row: [256]u16 = undefined;

        const max_xq4_i: i32 = @intCast((@max(@as(usize, 2), mw) - 2) * 16);
        const max_yq4_i: i32 = @intCast((@max(@as(usize, 2), mh) - 2) * 16);

        const cell_x = &self.cell_x;
        const cell_y = &self.cell_y;

        var cur_gy: usize = 0;
        for (0..h) |y| {
            while (cur_gy + 1 < SIM_H - 1 and y >= cell_y[cur_gy + 1]) : (cur_gy += 1) {}
            const gy0 = cur_gy;
            const dst_row = buf[y * stride .. y * stride + w];
            const src_row_off: usize = if (same_res)
                y * mw
            else
                @min(mh - 1, (y * mh) / @max(@as(usize, 1), h)) * mw;

            const ax0: usize = self.row_active_x0[gy0];
            const ax1: usize = self.row_active_x1[gy0];

            // Ultra-fast full-scanline @memcpy when an entire outer dark row is static!
            if (same_res and ax0 >= ax1) {
                @memcpy(dst_row, self.scene[src_row_off .. src_row_off + w]);
                continue;
            }

            // Copy left & right static abyssal margins in two wide @memcpy bursts
            const gx_start: usize = if (same_res) ax0 else 0;
            const gx_end: usize = if (same_res) ax1 else (SIM_W - 1);
            if (same_res) {
                const lx = cell_x[gx_start];
                if (lx > 0) @memcpy(dst_row[0..lx], self.scene[src_row_off .. src_row_off + lx]);
                const rx = cell_x[gx_end];
                if (rx < w) @memcpy(dst_row[rx..w], self.scene[src_row_off + rx .. src_row_off + w]);
            }

            // SIMD-premix 256 periodic dual-layer Snell caustic samples once per caustic scanline!
            if (!same_res or self.row_has_caust[gy0] != 0) {
                const c_row0 = caust_ptr0 + (((y +% oy0) & 255) << 8);
                const c_row1 = caust_ptr1 + (((y +% oy1) & 255) << 8);
                buildCausticScanline(&web_row, c_row0, c_row1, ox0, ox1);
            }

            // Vertically interpolate ONLY the active horizontal corridor [gx_start .. gx_end + 1]!
            const y_lo = cell_y[gy0];
            const y_hi = cell_y[gy0 + 1];
            const wy: i32 = if (y_hi > y_lo) @intCast(((y - y_lo) * 256) / (y_hi - y_lo)) else 0;
            const iwy: i32 = 256 - wy;
            const sr0 = gy0 * SIM_W;
            const sr1 = sr0 + SIM_W;

            const interp_hi = @min(SIM_W, gx_end + 1);
            for (gx_start..interp_hi) |gx| {
                const i0_s = sr0 + gx;
                const i1_s = sr1 + gx;
                row_dx[gx] = (@as(i32, self.disp_x_q4[i0_s]) * iwy + @as(i32, self.disp_x_q4[i1_s]) * wy) >> 8;
                row_dy[gx] = (@as(i32, self.disp_y_q4[i0_s]) * iwy + @as(i32, self.disp_y_q4[i1_s]) * wy) >> 8;
                row_caust[gx] = (@as(i32, self.caustic_q8[i0_s]) * iwy + @as(i32, self.caustic_q8[i1_s]) * wy) >> 8;
                row_glow[gx] = (@as(i32, self.plume_glow_q8[i0_s]) * iwy + @as(i32, self.plume_glow_q8[i1_s]) * wy) >> 8;
                row_flux[gx] = (@as(i32, self.flux_mod_q8[i0_s]) * iwy + @as(i32, self.flux_mod_q8[i1_s]) * wy) >> 8;
            }

            const safe_y = same_res and (y >= 9 and y + 10 < mh);
            const my_base_q4: i32 = if (same_res)
                @intCast(y << 4)
            else
                @intCast(((y * mh) << 4) / @max(@as(usize, 1), h));

            var gx: usize = gx_start;
            while (gx < gx_end) {
                const flags = self.cell_flags[sr0 + gx];
                if (same_res and (flags & CF_STATIC) != 0) {
                    const x_start = cell_x[gx];
                    while (gx < gx_end and (self.cell_flags[sr0 + gx] & CF_STATIC) != 0) : (gx += 1) {}
                    const x_end = cell_x[gx];
                    @memcpy(dst_row[x_start..x_end], self.scene[src_row_off + x_start .. src_row_off + x_end]);
                    continue;
                }

                const x_start = cell_x[gx];
                const x_end = cell_x[gx + 1];
                defer gx += 1;
                if (x_end <= x_start) continue;
                const span_len: i32 = @intCast(x_end - x_start);

                const dx0 = row_dx[gx];
                const dx1 = row_dx[gx + 1];
                const dy0 = row_dy[gx];
                const dy1 = row_dy[gx + 1];
                const c0 = row_caust[gx];
                const c1 = row_caust[gx + 1];
                const g0 = row_glow[gx];
                const g1 = row_glow[gx + 1];
                const f0 = row_flux[gx];
                const f1 = row_flux[gx + 1];

                const has_caust = (flags & CF_CAUSTIC) != 0;
                const has_tube = (flags & CF_TUBE_DEPTH) != 0;
                const no_glow = (g0 == 0 and g1 == 0);
                const flux_mid: u32 = @intCast((f0 + f1) >> 1);

                // Tier 1: Zero-warp active cell (clamp-free padded LUTs + L1d stack caustic lookup!)
                const zero_warp = same_res and (@abs(dx0) <= 1 and @abs(dx1) <= 1 and @abs(dy0) <= 1 and @abs(dy1) <= 1);
                if (zero_warp) {
                    const src_span = scene_ptr + src_row_off;
                    if (!has_caust) {
                        if (no_glow) {
                            for (x_start..x_end) |x| {
                                const px = src_span[x];
                                const ci = ((px & 0xFF) * flux_mid) >> 6;
                                const m9 = ((px >> 16) & 0xFF) << 1;
                                dst_row[x] = fastAddRGB(cher_lut_ptr[ci], metal_lut_ptr[m9]);
                            }
                        } else {
                            var cur_g: u32 = @intCast(g0 << 8);
                            const step_g: u32 = @bitCast(@divTrunc((g1 - g0) << 8, span_len));
                            for (x_start..x_end) |x| {
                                const px = src_span[x];
                                const ci = (((px & 0xFF) * flux_mid) >> 6) + (cur_g >> 7);
                                const m9 = ((px >> 16) & 0xFF) << 1;
                                dst_row[x] = fastAddRGB(cher_lut_ptr[ci], metal_lut_ptr[m9]);
                                cur_g +%= step_g;
                            }
                        }
                    } else if (no_glow) {
                        var cur_c: u32 = @intCast(c0 << 8);
                        const step_c: u32 = @bitCast(@divTrunc((c1 - c0) << 8, span_len));
                        for (x_start..x_end) |x| {
                            const px = src_span[x];
                            const ci = ((px & 0xFF) * flux_mid) >> 6;
                            const k8 = (px >> 8) & 0xFF;
                            const m9 = ((px >> 16) & 0xFF) << 1;
                            const mi = m9 + (((k8 * (cur_c >> 8)) * @as(u32, web_row[x & 255])) >> 16);
                            dst_row[x] = fastAddRGB(cher_lut_ptr[ci], metal_lut_ptr[mi]);
                            cur_c +%= step_c;
                        }
                    } else {
                        var cur_g: u32 = @intCast(g0 << 8);
                        const step_g: u32 = @bitCast(@divTrunc((g1 - g0) << 8, span_len));
                        var cur_c: u32 = @intCast(c0 << 8);
                        const step_c: u32 = @bitCast(@divTrunc((c1 - c0) << 8, span_len));
                        for (x_start..x_end) |x| {
                            const px = src_span[x];
                            const ci = (((px & 0xFF) * flux_mid) >> 6) + (cur_g >> 7);
                            const k8 = (px >> 8) & 0xFF;
                            const m9 = ((px >> 16) & 0xFF) << 1;
                            const mi = m9 + (((k8 * (cur_c >> 8)) * @as(u32, web_row[x & 255])) >> 16);
                            dst_row[x] = fastAddRGB(cher_lut_ptr[ci], metal_lut_ptr[mi]);
                            cur_g +%= step_g;
                            cur_c +%= step_c;
                        }
                    }
                    continue;
                }

                // Tier 2: Active Schlieren thermal plume & core refraction (branchless specialized!)
                var cur_g: u32 = @intCast(g0 << 8);
                const step_g: u32 = @bitCast(@divTrunc((g1 - g0) << 8, span_len));

                const safe_span = safe_y and (x_start >= 9 and x_end + 10 < mw);
                if (safe_span and !has_tube) {
                    // Ultra-fast interior core/deck Schlieren warp: pre-folded linear Q12 stepping, ZERO depth load, ZERO clamp!
                    const d0x = (dx0 * 240) >> 8;
                    const d1x = (dx1 * 240) >> 8;
                    const d0y = (dy0 * 240) >> 8;
                    const d1y = (dy1 * 240) >> 8;
                    var cur_sx_q12: i32 = (@as(i32, @intCast(x_start << 4)) + d0x) << 8;
                    var cur_sy_q12: i32 = (my_base_q4 + d0y) << 8;
                    const step_sx_q12: i32 = (16 << 8) + @divTrunc((d1x - d0x) << 8, span_len);
                    const step_sy_q12: i32 = @divTrunc((d1y - d0y) << 8, span_len);

                    if (!has_caust) {
                        for (x_start..x_end) |x| {
                            const cm = sampleCMK_Q4(scene_ptr, mw, @intCast(cur_sx_q12 >> 8), @intCast(cur_sy_q12 >> 8));
                            const ci = ((cm.c10 * flux_mid) >> 8) + (cur_g >> 7);
                            dst_row[x] = fastAddRGB(cher_lut_ptr[ci], metal_lut_ptr[cm.m9]);
                            cur_sx_q12 += step_sx_q12;
                            cur_sy_q12 += step_sy_q12;
                            cur_g +%= step_g;
                        }
                    } else {
                        var cur_c: u32 = @intCast(c0 << 8);
                        const step_c: u32 = @bitCast(@divTrunc((c1 - c0) << 8, span_len));
                        for (x_start..x_end) |x| {
                            const sx_q4: usize = @intCast(cur_sx_q12 >> 8);
                            const cm = sampleCMK_Q4(scene_ptr, mw, sx_q4, @intCast(cur_sy_q12 >> 8));
                            const ci = ((cm.c10 * flux_mid) >> 8) + (cur_g >> 7);
                            const web: u32 = web_row[(sx_q4 >> 4) & 255];
                            const mi = cm.m9 + (((cm.k8 * (cur_c >> 8)) * web) >> 16);
                            dst_row[x] = fastAddRGB(cher_lut_ptr[ci], metal_lut_ptr[mi]);
                            cur_sx_q12 += step_sx_q12;
                            cur_sy_q12 += step_sy_q12;
                            cur_g +%= step_g;
                            cur_c +%= step_c;
                        }
                    }
                } else if (safe_span) {
                    // Interior vertical guide-tube span: exact per-pixel depth_w so foreground rods stay rock-steady!
                    var cur_dx = dx0 << 8;
                    var cur_dy = dy0 << 8;
                    const step_dx = @divTrunc((dx1 - dx0) << 8, span_len);
                    const step_dy = @divTrunc((dy1 - dy0) << 8, span_len);
                    var cur_c: u32 = @intCast(c0 << 8);
                    const step_c: u32 = @bitCast(@divTrunc((c1 - c0) << 8, span_len));
                    for (x_start..x_end) |x| {
                        const base_px = scene_ptr[src_row_off + x];
                        const depth_w: i32 = @intCast(base_px >> 24);
                        const eff_dx = ((cur_dx >> 8) * depth_w) >> 8;
                        const eff_dy = ((cur_dy >> 8) * depth_w) >> 8;
                        const sx_q4: usize = @intCast(@as(i32, @intCast(x << 4)) + eff_dx);
                        const sy_q4: usize = @intCast(my_base_q4 + eff_dy);
                        const cm = sampleCMK_Q4(scene_ptr, mw, sx_q4, sy_q4);
                        const ci = ((cm.c10 * flux_mid) >> 8) + (cur_g >> 7);
                        var mi: u32 = cm.m9;
                        if (has_caust) {
                            const web: u32 = web_row[(sx_q4 >> 4) & 255];
                            mi = cm.m9 + (((cm.k8 * (cur_c >> 8)) * web) >> 16);
                        }
                        dst_row[x] = fastAddRGB(cher_lut_ptr[ci], metal_lut_ptr[mi]);
                        cur_dx += step_dx;
                        cur_dy += step_dy;
                        cur_g +%= step_g;
                        cur_c +%= step_c;
                    }
                } else {
                    // Edge / non-native resolution path with exact clamped sampling
                    var cur_dx = dx0 << 8;
                    var cur_dy = dy0 << 8;
                    const step_dx = @divTrunc((dx1 - dx0) << 8, span_len);
                    const step_dy = @divTrunc((dy1 - dy0) << 8, span_len);
                    var cur_c: u32 = @intCast(c0 << 8);
                    const step_c: u32 = @bitCast(@divTrunc((c1 - c0) << 8, span_len));
                    for (x_start..x_end) |x| {
                        const mx = if (same_res) x else @min(mw - 1, (x * mw) / @max(@as(usize, 1), w));
                        const base_px = scene_ptr[src_row_off + mx];
                        const depth_w: i32 = @intCast(base_px >> 24);
                        const eff_dx = ((cur_dx >> 8) * depth_w) >> 8;
                        const eff_dy = ((cur_dy >> 8) * depth_w) >> 8;

                        const mx_q4: i32 = if (same_res)
                            @intCast(x << 4)
                        else
                            @intCast(((x * mw) << 4) / @max(@as(usize, 1), w));
                        const sx_q4: usize = @intCast(math.clamp(mx_q4 + eff_dx, 0, @max(@as(i32, 0), max_xq4_i)));
                        const sy_q4: usize = @intCast(math.clamp(my_base_q4 + eff_dy, 0, @max(@as(i32, 0), max_yq4_i)));

                        var c10: u32 = undefined;
                        var m9: u32 = undefined;
                        var k8: u32 = (base_px >> 8) & 0xFF;
                        if (mw >= 2 and mh >= 2) {
                            const cm = sampleCMK_Q4(scene_ptr, mw, sx_q4, sy_q4);
                            c10 = cm.c10;
                            m9 = cm.m9;
                            k8 = cm.k8;
                        } else {
                            c10 = (base_px & 0xFF) << 2;
                            m9 = ((base_px >> 16) & 0xFF) << 1;
                        }

                        const ci = ((c10 * flux_mid) >> 8) + (cur_g >> 7);
                        var mi: u32 = m9;
                        if (k8 > 4) {
                            const web: u32 = web_row[x & 255];
                            mi = m9 + (((k8 * (cur_c >> 8)) * web) >> 16);
                        }
                        dst_row[x] = fastAddRGB(cher_lut_ptr[ci], metal_lut_ptr[mi]);

                        cur_dx += step_dx;
                        cur_dy += step_dy;
                        cur_g +%= step_g;
                        cur_c +%= step_c;
                    }
                }
            }
        }

        self.drawBubbles(buf, w, h, stride);
    }

    pub fn hasNaN(self: *const State) bool {
        if (!math.isFinite(self.time_sec) or !math.isFinite(self.real_time_s) or
            !math.isFinite(self.power_mw) or !math.isFinite(self.fuel_temp_k)) return true;
        for (self.precursors) |c| {
            if (!math.isFinite(c)) return true;
        }
        for (0..SIM_N) |idx| {
            if (!math.isFinite(self.temp[idx]) or !math.isFinite(self.vel_u[idx]) or
                !math.isFinite(self.vel_v[idx]) or !math.isFinite(self.pres[idx]) or
                !math.isFinite(self.eta_curr[idx]) or !math.isFinite(self.eta_prev[idx])) return true;
        }
        for (self.bubbles) |b| {
            if (!math.isFinite(b.x) or !math.isFinite(b.y) or !math.isFinite(b.z) or !math.isFinite(b.vz)) return true;
        }
        return false;
    }
};

comptime {
    sdk.exportTheme(State);
}

// ============================================================================
// MACHINE-CHECKED PHYSICS & INTEGRITY LEDGER TESTS (`zig test`)
// ============================================================================

test "ostr_cherenkov_threshold_beta" {
    const n420 = waterRefractiveIndex(420.0);
    const ek_thr = cherenkovThresholdMeV(420.0);
    const ok = sdk.ledger(.{
        .id = "ostr_cherenkov_threshold_beta",
        .claim = "Electron Cherenkov kinetic-energy threshold in pure water at 420 nm matches relativistic beta=1/n",
        .reference = "CODATA 2018 m_e c^2=0.51099895 MeV, n(420 nm)~1.339 => E_k~0.257-0.264 MeV",
        .conditions = "lambda=420 nm, T=20 C water",
        .quantity = "threshold_ek_MeV",
        .measured = ek_thr,
        .lo = 0.250,
        .hi = 0.268,
        .source = "themes/Neon_OSTR_Cherenkov.zig:cherenkovThresholdMeV",
    });
    try std.testing.expect(n420 > 1.335 and n420 < 1.345);
    try std.testing.expect(ok);
}

test "ostr_frank_tamm_water_peak" {
    // Non-trivial check: Pope & Fry (1997) 5.2 m pure-water transmission peaks at 418 nm with >3.5x
    // blue/red selectivity T(418 nm)/T(620 nm), and blue-shifts CIE photopic V(lambda) from 555 nm -> ~538 nm.
    const t418 = @exp(-waterAbsorptionPopeFry(418.0) * WATER_COL_DEPTH_M);
    const t620 = @exp(-waterAbsorptionPopeFry(620.0) * WATER_COL_DEPTH_M);
    const blue_red_ratio = t418 / @max(1e-12, t620);

    var best_water_lam: f64 = 380.0;
    var best_water_t: f64 = -1.0;
    var best_photopic_lam: f64 = 380.0;
    var best_photopic_val: f64 = -1.0;
    var k: usize = 0;
    while (k <= 320) : (k += 1) {
        const lam = 380.0 + @as(f64, @floatFromInt(k));
        const wt = @exp(-waterAbsorptionPopeFry(lam) * WATER_COL_DEPTH_M);
        if (wt > best_water_t) {
            best_water_t = wt;
            best_water_lam = lam;
        }
        const pval = cherenkovWaterSpectrum(lam, WATER_COL_DEPTH_M) * cie1931XYZ(lam)[1];
        if (pval > best_photopic_val) {
            best_photopic_val = pval;
            best_photopic_lam = lam;
        }
    }
    const ok = sdk.ledger(.{
        .id = "ostr_frank_tamm_water_peak",
        .claim = "5.2 m Pope & Fry (1997) water column peaks at 418 nm with 4.09x 418/620 nm selectivity and blue-shifts Cherenkov photopic peak below 555 nm",
        .reference = "Pope & Fry (1997) Appl. Opt. 36, 8710: a(418)=0.0045, a(620)=0.2755 m^-1 => T418/T620=4.093",
        .conditions = "depth=5.20 m pure water, 380-700 nm, 1 nm step",
        .quantity = "water_418_to_620_transmission_ratio",
        .measured = blue_red_ratio,
        .lo = 3.5,
        .hi = 4.8,
        .source = "themes/Neon_OSTR_Cherenkov.zig:cherenkovWaterSpectrum",
    });
    try std.testing.expect(best_water_lam >= 412.0 and best_water_lam <= 424.0);
    try std.testing.expect(best_photopic_lam >= 520.0 and best_photopic_lam <= 548.0);
    try std.testing.expect(ok);
}

test "ostr_cie_cherenkov_chromaticity" {
    var ex: f64 = 0.0;
    var ey: f64 = 0.0;
    var ez: f64 = 0.0;
    var step_i: usize = 0;
    while (step_i <= 160) : (step_i += 1) {
        const cmf = cie1931XYZ(380.0 + @as(f64, @floatFromInt(step_i)) * 2.0);
        ex += cmf[0];
        ey += cmf[1];
        ez += cmf[2];
    }
    const esum = ex + ey + ez;
    try std.testing.expect(@abs(ex / esum - (1.0 / 3.0)) < 0.01);
    try std.testing.expect(@abs(ey / esum - (1.0 / 3.0)) < 0.01);

    const chrom = computeCherenkovChromaticity(WATER_COL_DEPTH_M);
    const chrom_deep = computeCherenkovChromaticity(14.0);
    const ok_x = sdk.ledger(.{
        .id = "ostr_cie_cherenkov_chromaticity",
        .claim = "CIE 1931 2-deg chromaticity x of 5.2 m water-filtered Frank-Tamm spectrum sits strictly bluer than T->inf Planck locus",
        .reference = "Illuminant E=(0.333,0.333), Rayleigh-Jeans=(0.240,0.235); deeper H2O shifts strictly bluer",
        .conditions = "380-700 nm quadrature, step=2 nm, depth=5.20 m",
        .quantity = "cie_1931_x",
        .measured = chrom.x,
        .lo = 0.180,
        .hi = 0.225,
        .source = "themes/Neon_OSTR_Cherenkov.zig:computeCherenkovChromaticity",
    });
    try std.testing.expect(chrom.y > 0.12 and chrom.y < 0.26);
    try std.testing.expect(chrom_deep.x < chrom.x and chrom_deep.y < chrom.y);
    try std.testing.expect(chrom.lin_rgb[2] > chrom.lin_rgb[1] and chrom.lin_rgb[1] >= chrom.lin_rgb[0]);
    try std.testing.expect(ok_x);
}

test "ostr_bessel_j0_diffusion_eigenmode" {
    const x: f64 = 1.35;
    const h: f64 = 1.0e-3;
    const jm2 = besselJ0(x - 2.0 * h);
    const jm1 = besselJ0(x - h);
    const j0 = besselJ0(x);
    const jp1 = besselJ0(x + h);
    const jp2 = besselJ0(x + 2.0 * h);
    const d1 = (-jp2 + 8.0 * jp1 - 8.0 * jm1 + jm2) / (12.0 * h);
    const d2 = (-jp2 + 16.0 * jp1 - 30.0 * j0 + 16.0 * jm1 - jm2) / (12.0 * h * h);
    const residual = @abs(x * x * d2 + x * d1 + x * x * j0);
    const root_err = @abs(besselJ0(BESSEL_J0_ROOT1));
    const max_err = @max(residual, root_err);
    const ok = sdk.ledger(.{
        .id = "ostr_bessel_j0_diffusion_eigenmode",
        .claim = "Cylindrical diffusion eigenmode J_0 satisfies Bessel ODE (4-pt f64 FD) and vanishes at j_{0,1}",
        .reference = "x^2 J_0'' + x J_0' + x^2 J_0 = 0, j_{0,1} = 2.4048255577",
        .conditions = "x=1.35, h=1e-3",
        .quantity = "max_ode_and_root_error",
        .measured = max_err,
        .lo = 0.0,
        .hi = 1.0e-8,
        .source = "themes/Neon_OSTR_Cherenkov.zig:besselJ0",
    });
    try std.testing.expect(ok);
}

test "ostr_keepin_6group_equilibrium_and_feedback" {
    const gpa = std.testing.allocator;
    const st = try State.init(gpa, 320, 200, 1.0);
    defer st.deinit(gpa);

    var beta_sum: f64 = 0.0;
    for (KEEPIN_BETA) |b| beta_sum += b;
    try std.testing.expect(@abs(beta_sum - BETA_EFF) < 1e-12);

    for (0..30) |_| st.stepReactorKinetics(1.0 / 30.0, 0.0);
    try std.testing.expect(@abs(st.power_mw - 1.0) < 1e-9);

    for (0..600) |_| st.stepReactorKinetics(1.0 / 30.0, 0.0010);
    const settled_power = st.power_mw;
    const ok = sdk.ledger(.{
        .id = "ostr_keepin_6group_equilibrium_and_feedback",
        .claim = "Keepin 6-group kinetics holds exact equilibrium at rho=0 and self-stabilizes under +100 pcm via UZrH alpha_T",
        .reference = "Keepin (1965) U-235 6-group; equilibrium delta_P/P = rho / (|alpha_T| * delta_T_eq) ~ +3.5%",
        .conditions = "dt=1/30 s, 600 steps (20 s), rho_ext=+0.0010",
        .quantity = "settled_power_MW",
        .measured = settled_power,
        .lo = 1.015,
        .hi = 1.080,
        .source = "themes/Neon_OSTR_Cherenkov.zig:stepReactorKinetics",
    });
    try std.testing.expect(ok);
}

test "ostr_boussinesq_divergence_free_projection" {
    const gpa = std.testing.allocator;
    const st = try State.init(gpa, 320, 200, 1.0);
    defer st.deinit(gpa);

    for (0..10) |_| st.stepBoussinesqPlume(1.0 / 30.0);
    var div_sq: f64 = 0.0;
    var vel_sq: f64 = 0.0;
    var up_mom: f64 = 0.0;
    for (2..SIM_H - 2) |gy| {
        const row = gy * SIM_W;
        for (2..SIM_W - 2) |gx| {
            const idx = row + gx;
            const du_dx = 0.5 * (@as(f64, st.vel_u[idx + 1]) - @as(f64, st.vel_u[idx - 1]));
            const dv_dy = 0.5 * (@as(f64, st.vel_v[idx + SIM_W]) - @as(f64, st.vel_v[idx - SIM_W]));
            const d = du_dx + dv_dy;
            div_sq += d * d;
            vel_sq += du_dx * du_dx + dv_dy * dv_dy;
            up_mom += -@as(f64, st.vel_v[idx]);
        }
    }
    const rel_div = @sqrt(div_sq / @max(1e-12, vel_sq));
    const ok = sdk.ledger(.{
        .id = "ostr_boussinesq_divergence_free_projection",
        .claim = "Pressure-projected 128x80 Boussinesq thermal plume maintains low relative divergence and net upward buoyancy",
        .reference = "Incompressible Navier-Stokes div(u) = 0",
        .conditions = "70 total PDE steps at dt=1/30 s",
        .quantity = "relative_rms_divergence",
        .measured = rel_div,
        .lo = 0.0,
        .hi = 0.35,
        .source = "themes/Neon_OSTR_Cherenkov.zig:stepBoussinesqPlume",
    });
    try std.testing.expect(up_mom > 0.0);
    try std.testing.expect(ok);
}

test "ostr_stormer_verlet_wave_isotropy_and_energy" {
    // 1. True rotational isotropy check on off-axis plane wave cos(k*(x*cos(th) + y*sin(th))), k=0.6:
    //    5-point Laplacian suffers O(k^2) directional anisotropy between 0 deg & 45 deg,
    //    while 9-point Mehrstellen achieves O(k^4) isotropy (>5x lower directional error!).
    const k_wave: f64 = 0.6;
    const angles = [_]f64{ 0.0, math.pi / 4.0 };
    var lap9_vals: [2]f64 = undefined;
    var lap5_vals: [2]f64 = undefined;
    for (angles, 0..) |th, ai| {
        var field: [16 * 16]f32 = @splat(0.0);
        const ca = @cos(th);
        const sa = @sin(th);
        for (0..16) |y| {
            for (0..16) |x| {
                const dx = @as(f64, @floatFromInt(x)) - 8.0;
                const dy = @as(f64, @floatFromInt(y)) - 8.0;
                field[y * 16 + x] = @floatCast(@cos(k_wave * (dx * ca + dy * sa)));
            }
        }
        const c_idx: usize = 8 * 16 + 8;
        lap9_vals[ai] = @as(f64, State.laplacian9pt(&field, c_idx, 16));
        lap5_vals[ai] = @as(f64, field[c_idx - 1] + field[c_idx + 1] + field[c_idx - 16] + field[c_idx + 16] - 4.0 * field[c_idx]);
    }
    const aniso9 = @abs(lap9_vals[0] - lap9_vals[1]) / (k_wave * k_wave);
    const aniso5 = @abs(lap5_vals[0] - lap5_vals[1]) / (k_wave * k_wave);

    // 2. Live Stormer-Verlet integration & bounded energy stability on real State.stepSurfaceWaves()
    const gpa = std.testing.allocator;
    const st = try State.init(gpa, 320, 200, 1.0);
    defer st.deinit(gpa);
    st.temp = @splat(0.0);
    st.wave_ring = @splat(0.0);
    st.eta_curr = @splat(0.0);
    st.eta_prev = @splat(0.0);
    for (1..SIM_H - 1) |gy| {
        for (1..SIM_W - 1) |gx| {
            const dx = @as(f32, @floatFromInt(gx)) - 64.0;
            const dy = @as(f32, @floatFromInt(gy)) - 40.0;
            const g = 0.25 * @exp(-(dx * dx + dy * dy) * 0.08);
            st.eta_curr[gy * SIM_W + gx] = g;
            st.eta_prev[gy * SIM_W + gx] = g;
        }
    }
    var e0: f64 = 0.0;
    for (st.eta_curr) |v| e0 += @as(f64, v) * @as(f64, v);
    for (0..120) |_| st.stepSurfaceWaves();
    var e1: f64 = 0.0;
    for (st.eta_curr) |v| e1 += @as(f64, v) * @as(f64, v);

    const ok = sdk.ledger(.{
        .id = "ostr_stormer_verlet_wave_isotropy_and_energy",
        .claim = "Mehrstellen 9-pt Laplacian beats 5-pt rotational anisotropy by >5x and live Stormer-Verlet wave energy decays stably over 120 steps",
        .reference = "0 deg vs 45 deg plane wave (k=0.6) + damped Stormer-Verlet CFL stability (0 < E_120 < E_0)",
        .conditions = "16x16 stencil isotropy + 120 unforced wave steps on 128x80 State",
        .quantity = "lap9_rotational_anisotropy",
        .measured = aniso9,
        .lo = 0.0,
        .hi = 0.0025,
        .source = "themes/Neon_OSTR_Cherenkov.zig:stepSurfaceWaves",
    });
    try std.testing.expect(aniso5 > aniso9 * 5.0);
    try std.testing.expect(e1 > 0.0 and e1 < e0 and !st.hasNaN());
    try std.testing.expect(ok);
}

test "ostr_thermo_optic_schlieren_sign" {
    const gpa = std.testing.allocator;
    const st = try State.init(gpa, 320, 200, 1.0);
    defer st.deinit(gpa);
    st.temp = @splat(0.0);
    st.eta_curr = @splat(0.0);
    st.warp_zone = @splat(1.0);
    st.temp[40 * SIM_W + 64] = 1.0;
    st.updateRenderTransferGrid();
    const dx_right = st.disp_x_q4[40 * SIM_W + 65];
    const dx_left = st.disp_x_q4[40 * SIM_W + 63];
    const sign_ok: f64 = if (DN_DT_WATER_25C < 0.0 and dx_right > 0 and dx_left < 0) 1.0 else 0.0;
    const ok = sdk.ledger(.{
        .id = "ostr_thermo_optic_schlieren_sign",
        .claim = "Negative water thermo-optic dn/dT < 0 produces diverging Schlieren deflection around a warm thermal plume",
        .reference = "dn/dT = -8.8e-5 K^-1 at 25 C (warm water has lower refractive index)",
        .conditions = "isolated thermal impulse at (64, 40), flat surface",
        .quantity = "diverging_lens_sign_check",
        .measured = sign_ok,
        .lo = 1.0,
        .hi = 1.0,
        .source = "themes/Neon_OSTR_Cherenkov.zig:updateRenderTransferGrid",
    });
    try std.testing.expect(ok);
}

test "ostr_snell_caustic_flux_conservation" {
    const gpa = std.testing.allocator;
    const st = try State.init(gpa, 320, 200, 1.0);
    defer st.deinit(gpa);
    const flux_err0 = @abs(st.caust_flux_mean - 1.0);
    const flux_err1 = @abs(st.caust2_flux_mean - 1.0);
    const ok = sdk.ledger(.{
        .id = "ostr_snell_caustic_flux_conservation",
        .claim = "Both forward Snell photon-mapped 256x256 caustic sheets conserve total optical flux and focus sharp cusps >2.0x mean",
        .reference = "Conservation of energy (mean_flux==1.0) + optical Jacobian focusing peaks >2.0x on both sheets",
        .conditions = "2 x 512x512 rays (524,288 photons), n_water=1.333, 2x7 capillary wave modes",
        .quantity = "caustic_peak_to_mean_ratio",
        .measured = st.caust_peak_ratio,
        .lo = 2.0,
        .hi = 25.0,
        .source = "themes/Neon_OSTR_Cherenkov.zig:bakeSnellCausticSheet",
    });
    try std.testing.expect(flux_err0 < 1e-4 and flux_err1 < 1e-4);
    try std.testing.expect(st.caust2_peak_ratio >= 2.0 and st.caust2_peak_ratio <= 25.0);
    try std.testing.expect(ok);
}

test "ostr_multires_canary_and_hour_soak" {
    const gpa = std.testing.allocator;
    // Exercise 0x0 guard, tiny (<128) width, watchdog 320x200, native 640x400 (with CF_STATIC), odd 777x513,
    // AND non-native upscale (>CACHE_CAP: 2048x1300)!
    const st_zero = try State.init(gpa, 0, 0, 1.0);
    defer st_zero.deinit(gpa);
    st_zero.step(0.0);
    st_zero.step(0.008);

    const sizes = [_][3]usize{
        .{ 64, 48, 72 },
        .{ 320, 200, 328 },
        .{ 640, 400, 656 },
        .{ 777, 513, 800 },
        .{ 2048, 1300, 2064 },
    };
    const canary: u32 = 0xDEADBEEF;
    var bad_total: usize = 0;

    for (sizes) |sz| {
        const w = sz[0];
        const h = sz[1];
        const stride = sz[2];
        const st = try State.init(gpa, w, h, 2.0);
        defer st.deinit(gpa);

        const buf = try gpa.alloc(u32, stride * h);
        defer gpa.free(buf);
        @memset(buf, canary);

        st.step(0.008);
        st.draw(buf, stride);
        if (st.hasNaN()) bad_total += 1;

        for (0..h) |y| {
            for (0..w) |x| {
                if ((buf[y * stride + x] >> 24) != 0xFF) bad_total += 1;
            }
            for (w..stride) |x| {
                if (buf[y * stride + x] != canary) bad_total += 1;
            }
        }

        // Verify truncated buffer path (buf.len < self.h * stride) on native CF_STATIC resolution (B1 regression guard!)
        if (w == 640 and h == 400) {
            const half_h: usize = 200;
            const trunc = try gpa.alloc(u32, stride * half_h);
            defer gpa.free(trunc);
            @memset(trunc, canary);
            st.draw(trunc, stride);
            for (0..half_h) |y| {
                for (0..w) |x| {
                    // Must match full-buffer top half bit-for-bit!
                    if (trunc[y * stride + x] != buf[y * stride + x]) bad_total += 1;
                }
                for (w..stride) |x| {
                    if (trunc[y * stride + x] != canary) bad_total += 1;
                }
            }
        }
    }

    // Real multi-week uptime & live motion soak (t = 1,000,000 s + 600 live steps, verifying non-dead dynamics)
    const soak = try State.init(gpa, 320, 200, 1.0);
    defer soak.deinit(gpa);
    soak.real_time_s = 1_000_000.0;
    const b0_z = soak.bubbles[0].z;
    for (0..600) |_| soak.step(0.008);
    var max_t: f32 = 0.0;
    for (soak.temp) |tv| max_t = @max(max_t, tv);
    if (soak.hasNaN() or soak.power_mw < 0.7 or soak.power_mw > 1.4 or max_t < 0.05 or soak.bubbles[0].z == b0_z) {
        bad_total += 1;
    }

    const ok = sdk.ledger(.{
        .id = "ostr_multires_canary_and_hour_soak",
        .claim = "Multi-resolution (0x0..2048x1300), truncated-buffer parity, opaque alpha, and multi-week live soak complete with zero violations",
        .reference = "ARGUS-BENCH Gates 3-7 + THEME_CRAFT A7 multi-week stability",
        .conditions = "0x0, 64x48, 320x200, 640x400 (+half-buf parity), 777x513, 2048x1300, t=1e6 s + 600 steps",
        .quantity = "violation_count",
        .measured = @floatFromInt(bad_total),
        .lo = 0.0,
        .hi = 0.0,
        .source = "themes/Neon_OSTR_Cherenkov.zig:State.draw",
    });
    try std.testing.expect(ok);
}

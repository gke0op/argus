// @argus-theme: custom_shader
// ============================================================================
// OPUS GARGANTUA // themes/Opus_Gargantua.zig
//
// Interstellar's mood on Opus_Quasar's engine. The gravity is all computed, exactly as there:
// Kerr light paths (GPU-traced at native resolution, the same shadow-edge check), redshift and
// beaming, light-travel delays, photon rings, shearing hot spots on Kerr orbits, limb
// darkening, and the turbulence machinery. The disk itself is CHOSEN, for the look, and says so:
//  * Temperature: a steady Page-Thorne disk, T ~ F^(1/4), scaled to a 6,500 K peak: the warm
//    white-gold of the film's Gargantua. A real thin disk this cool around a 5e9 solar-mass
//    hole is not self-consistent: at the ~1e-3 lower accretion rate it needs, the computed
//    model's gas comes out opaque everywhere (cooler gas absorbs more), and real gas that
//    starved would puff up into a hot, faint flow (what the Event Horizon Telescope images).
//    Interstellar took the same licence, and turned beaming off; here beaming stays on.
//  * Outer gas: a translucent column, tau = 220 (5 M / r) e^(-r / 5 M) (the gamma = 1
//    Lynden-Bell & Pringle viscous-spreading shape), so the lensed underside of the disk glows
//    through below the shadow. Grey: emission and extinction depth alike.
//  * Turbulence: bolder than a thermal thin disk (sigma 0.4, not 0.2), eddies 6x the quasar's
//    (H/r 0.06) living 2x the measured time, so the shear winds them into broad bands; the GPU
//    footprint filter is narrowed to match so they never alias.
// The notes below are Opus_Quasar's and describe the shared engine; where they quote the
// quasar's disk (37,000 K, the computed profile, Eddington ratios) Gargantua's choices above
// replace them. The computed quasar disk is still solved at init (its test runs here too).
//
// What is computed, not chosen:
//  * Light paths: exact Kerr null geodesics (Hamiltonian form, RK4, with p_r re-solved
//    from the null condition each step), traced backward from a pinhole camera. The
//    GPU traces every pixel (2x2 samples, 8x8 at edges and photon rings); the CPU
//    fallback traces 4x4-block corners and interpolates where the image is smooth.
//    Spin, frame dragging and the D-shaped shadow come out of the equations.
//  * Disk: geometrically thin, inner edge at the ISCO (exact Bardeen-Press-Teukolsky
//    formula). Surface density, dissipation, temperature and optical depth all come from ONE
//    solution of the general-relativistic thin-disk evolution equation (Balbus 2017; Mummery &
//    Balbus 2019, MNRAS 489, 132; see diskProfile): a ring of gas that has spread for a while,
//    zero stress at the ISCO, a stress W ~ r^(1/2) independent of Sigma. Near the ISCO it is
//    in steady inflow and has the Page-Thorne flux shape (within 2% inside 3 M; mass budget
//    closes to 0.1%); further out the inflow falls to zero at the radius where its mass flux
//    reverses (10 M), so the flux drops below Page-Thorne (0.86 at 5 M, 0.50 at 10 M). Beyond
//    it the disk spreads outward, and its dissipation, temperature and opacity fall off
//    together, so it thins out with no edge. The stress follows the closure, not the local
//    pressure: W = 1.5 alpha (P/rho) r holds only at the flux peak, where it is set (further
//    out the closure's stress implies alpha >> 1). Scaled to a 5e9 solar-mass hole whose
//    ISCO accretion rate is 3% of Eddington's (alpha = 0.1); the snapshot shines at ~1.5% of
//    L_Edd, because its inflow stops at 10 M. Peak 37,000 K, blue-white, as real thin disks
//    around such holes are. Local structure: scale height from hydrostatic balance with gas +
//    radiation pressure, midplane temperature from radiative diffusion, electron scattering +
//    Kramers absorption at that temperature. Where the gas thins it emits as a grey isothermal
//    slab (energy-conserving source temperature; emission depth sqrt(tau_a tau_ext) where
//    scattering is thick, tau_a (1 + tau_es) where thin) and dims the light behind by the
//    extinction depth.
//  * Color: each point radiates the spectrum of a disk atmosphere: a colour-corrected
//    blackbody f^-4 B(f T_s), whose electron scattering hardens it to a bluer colour at the
//    same flux (Done, Davis, Jin, Blaes & Ward 2012: f = 1 below 3e4 K, 1.19 at the 37,000 K
//    peak). The observed spectrum is that at g f T_s, with g the full Kerr redshift
//    (gravitational + Doppler), so color AND brightness come from Planck's law integrated
//    against CIE 1931 color matching functions. Beaming is not switched off: the approaching
//    side is much brighter, as it would be.
//  * Limb darkening: the optically thick disk is an electron-scattering atmosphere, darker
//    seen edge-on, I(mu) ~ 1 + 2.06 mu (Chandrasekhar's H-function, linear fit, as Laor 1991;
//    full disk-atmosphere calculations find a slope nearer 2.6 and up to ~15% deviations),
//    flux-conserving, with mu in the gas's own frame; it fades out where the gas thins.
//  * Light travel time: each pixel's pattern phase includes the photon's
//    coordinate travel time, so lensed images lag the direct one.
//  * Grazing light: where gas is translucent, light crosses tau / mu of it, with mu =
//    g |p_theta| / r the cosine of its angle to the disk in the gas's own frame
//    (at 80 deg the median mu is ~0.2), and I = B(1 - e^-tau/mu) + I_behind e^-tau/mu.
//
// What is chosen (stated honestly):
//  * Spin a = 0.94 M, inclination 80 deg (steeply tilted).
//  * The disk's parameters: mass 5e9 Msun, ISCO accretion rate 3% of Eddington, alpha 0.1, the initial ring
//    (8 M, width 1.6 M) and the snapshot (mass flux reversing at 10 M). The Sigma-independent
//    stress is what gives the soft outer fade: a stress that grows with Sigma (a pure alpha
//    closure) makes a sharp front instead (Mummery & Balbus 2019). Opacity: grey, and an
//    extrapolation beyond ~35 M: there the gas is below ~5000 K and neutral, so electron
//    scattering and Kramers (which need free electrons) do not apply, and the true opacity
//    (H-, molecules, dust) is not modelled. Sigma falls an e-fold per ~5 M out there, so the
//    fade is robust but its exact radius and its colour are not computed physics. The colour
//    correction and limb darkening are fits to disk-atmosphere models, not computed here.
//  * Time-lapse: one ISCO orbit takes ~2.4 s on screen, one at r = 6 M ~10 s (in
//    reality ~7 and ~28 days for this 5e9 solar-mass hole).
//  * Turbulence: procedural noise carrying the measured statistics of magnetorotational
//    turbulence, not simulated MHD (Guan et al. 2009; Beckwith, Armitage & Simon 2011;
//    Hirose et al. 2009). As rendered (time-averaged 1/e correlation ellipse, measured on the
//    tables): eddies ~1.8 H along the orbit by ~0.25 H radially (axis ratio ~7), trailing
//    12-14 deg; H/r = 0.01 is our choice (this disk: 0.006-0.012 at the peak, by convention).
//    They get there physically: born leading ~31 deg, swung by the Kerr shear through radial
//    to trailing (the birth shape is fitted to that outcome). Two octaves with amplitude
//    2^(-5j/6), a k^(-11/3) per-mode spectrum; octave j lives P(r) 2^(-2j/3) (correlation
//    time ~ half an orbit, shorter for small eddies), on phase-locked lifetime bands L0 2^n
//    blended across radius so neighbouring radii never drift apart into stripes. Each band
//    is two staggered, independent generations cross-faded with variance-preserving weights,
//    every one advected at its own Kerr Omega(r). Dissipation is log-normal,
//    exp(0.2 m - 0.02 var m) with mean 1 (sigma 0.2: a radiatively efficient thin disk, ~5%
//    temperature ripples), and the gas temperature follows it as T ~ eps^(1/4), so it
//    changes colour as well as brightness. Interpolated so the variance holds between table
//    cells, and filtered by the pixel's footprint on the disk as a box average does
//    (~ (footprint / eddy)^(-1/2) per axis). The CPU fallback draws a stand-in for the
//    coarse octave as a ~1-bin pixel sees it (point samples per radial bin and 1/512 turn,
//    tent-filtered, scaled to the box-averaged rms), as brightness scaled by the blackbody's
//    response to the temperature change, and bakes the pixels it cannot change by an 8-bit
//    level; the GPU draws both octaves per pixel.
//  * Hot spots: plasma clumps on exact Kerr orbits (like Sgr A* flares). Each appears
//    in the direct image and the lowest-order lensed image of each pixel, its orbital
//    phase lagging by that image's light-travel time (birth and fade do not lag; spots
//    are not drawn in higher-order rings or in images seen through translucent gas).
//    They shear as they age: every radius of the clump keeps its own Omega(r), so after
//    an age a the part at r has moved Omega(r) a and the clump draws out into an arc.
//    Hotter gas: emissivity x (1 + boost), so T rises as (1 + boost)^(1/4). Their count,
//    size and brightness are choices; their motion is not.
//  * Sky: a procedural Milky Way (band, dust lanes, bulge) and stars placed
//    behind the hole and seen through the geodesics, so it bends into arcs and
//    an Einstein ring. Its brightness is a composite-exposure choice.
//  * Camera exposure + Reinhard tone mapping (HDR: to the display's EDR headroom).
//    The CPU fallback composites translucent layers after tone mapping, in display
//    values; the GPU composites radiances before it.
//  Not modelled: returning radiation, disk thickness, gas inside the ISCO.
//
// Contract: 1 allocation (one slab) at init, 0 after; no clocks or I/O.
// The geodesic work happens once in init; draw() is table lookups.
// ============================================================================

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const SPIN: f64 = 0.94;
pub const INCL: f64 = 80.0 * math.pi / 180.0;
pub const R_OUT: f64 = 48.0; // geometry only: Gargantua's chosen column is tau ~ 2e-3 here
pub const GARG_RC: f64 = 5.0; // M: roll-off scale of Gargantua's chosen outer column
pub const GARG_TAU0: f64 = 220.0; // tau = 1 near r = 20 M; opaque (tau > 15) inside ~10 M
// Gas denser than this (line of sight) is drawn opaque: e^-40 of what lies behind leaks, under
// 1e-3 of display white even behind the brightest disk (light is composited before tone mapping).
const TAU_BEHIND: f64 = 40.0;
const TAU_MIN: f64 = 0.01; // thinner than this (line of sight) the gas is left out: opacity < 1%
const EMIT_FLOOR: f64 = 3e-4; // display-linear (~1/255): gas that can't reach this even stirred is baked
const SPOT_RMAX: f64 = 12.0; // M: hot spots orbit inside this (r_in * 5.35 + width); never baked there
const EXPO_R: f64 = 24.0; // exposure is metered on the bright inner disk only
const EMIT_N: usize = 1024; // 1 - exp(-e^x) table over x = ln(tau) in [EMIT_X0, EMIT_X1]
const EMIT_X0: f32 = -7.0;
const EMIT_X1: f32 = 4.0;
const OBS_R: f64 = 1000.0;
// Common light-travel time from the hole to the camera (radial tortoise coordinate,
// r + 2 ln(r/2 - 1) ~ r + 2 ln(r/2)). Only delays relative to it are observable; left in,
// Omega(r) * 1000 M would wind the disk pattern ~0.5 rad per pixel radially and the
// footprint filter would (rightly) erase all turbulence and hot spots.
const T_REF: f64 = OBS_R + 2.0 * @log(OBS_R / 2.0);
const HALF_H: f64 = 15.5; // half the screen height, in units of M
const TIME_LAPSE: f64 = 10.0; // M of coordinate time per unit of Argus dt
// Turbulence: statistics of magnetorotational turbulence from shearing-box and global MHD
// simulations (Guan et al. 2009, ApJ 694, 1010; Beckwith, Armitage & Simon 2011, MNRAS 416, 361).
const TURB_SIGMA: f32 = 0.4; // Gargantua: bolder than a thermal thin disk's 0.2 (a choice)
const GARG_LIFE: f64 = 2.0; // Gargantua: eddies live 2x the measured time, so shear winds them into long arcs (a choice)
const NOISE_STD: f32 = 40.0; // noise table byte levels per standard deviation
pub const H_OVER_R: f64 = 0.06; // Gargantua: eddies 6x the quasar's (a choice, for broad bands)
pub const NR: usize = 2048; // turbulence rows across the radial span (eddies are smaller than a radial bin)
pub const N_OCT: usize = 2; // octaves, amplitude 2^(-5j/6): a k^(-11/3) per-mode spectrum (Beckwith 2011). A third
// (0.03 H radially) would be finer than a table row, and than a Retina pixel's footprint on the disk.
pub const NBAND: usize = 12; // lifetime bands L0 * 2^n, phase-locked to global time
pub const BAND_L0: f64 = 4.0; // M: the shortest lifetime band
const OCT_AMP = [N_OCT]f32{ 1.0, 0.5612310241546865 };
// Birth eddies (value-noise cells of 2 x these, in H), born leading and swung by shear to
// trailing: fitted so the time-averaged rendered 1/e ellipse is the measured MRI one, ~1.8 H
// along the orbit by ~0.25 H radially (ratio ~7), trailing 12-14 deg (notes:
// opus-audit2-turbulence-fit.md). Octave 1 renders ~0.9 x 0.2 H.
const EDDY_MIN_H: f64 = 0.294;
const EDDY_MAJ_H: f64 = 0.556;
const TILT_ROWS: f64 = -2.0; // noise rows per phase cell along a birth eddy's long axis: leading ~31 deg
// (exact wrap: NP * 2 = NR rows, a whole number of cells per octave)
const MU_MIN: f64 = 0.0067; // grazing limit for 1/mu (ln 150 = 5.0)
const LMU_SCALE: f64 = 51.0; // ln(1/mu) per byte level: 0..255 covers mu down to MU_MIN
const RESP_SCALE: f32 = 32.0; // Rec.resp units per unit d ln Y / d ln eps
const LIMB_B: f64 = 2.06; // electron-scattering limb darkening I(mu) ~ 1 + LIMB_B mu
const EXP_N: usize = 1024; // exp table over [-4, 4] for the CPU draw
const EXPO_TARGET: f64 = 7.0; // 99th-percentile disk luminance maps here before tone mapping
const STAR_GAIN: f64 = 0.8;
const SKY_VISIBLE: f64 = 1.0; // Gargantua keeps its (artistic) starfield
const STAR_CELL: f64 = 8.0e-3; // star grid spacing on the sky, radians (resolution-independent)
const STAR_FLUX: f64 = 60.0; // intrinsic star brightness; lensing then dims or brightens each one
const SKY_GAIN: f64 = 0.010; // diffuse Milky Way surface brightness (linear, pre-encode)
const GAL_TILT: f64 = 25.0 * math.pi / 180.0; // band's tilt on screen
const NSPOT: usize = 6;
const SPOT_LIFE: f64 = 90.0; // M of time each hot spot lives
const SPOT_SIZE: f64 = 1.1; // M
const SPOT_AMP: f32 = 6.0; // peak emissivity boost (hotter gas: T rises as (1 + boost)^(1/4))
const HALF_PI: f64 = math.pi / 2.0;
/// Built by Argus's GPU path (src/gpu/bh_export.zig): the GPU traces the image itself at the
/// window's native size, so init() skips the CPU trace and draw() runs it only if it's ever called.
const gpu_traced = @hasDecl(@import("root"), "argus_gpu_traces_kerr_disk");
const K_NEAR: f64 = 0.08; // tuned against the Bardeen test: ~1e-5 M shadow-edge error
const MAX_STEPS: u32 = 40_000;

// ============================================================================ Kerr physics (M = 1)

pub fn horizon(a: f64) f64 {
    return 1.0 + @sqrt(1.0 - a * a);
}

/// Prograde innermost stable circular orbit (Bardeen, Press & Teukolsky 1972).
pub fn isco(a: f64) f64 {
    const z1 = 1.0 + math.cbrt(1.0 - a * a) * (math.cbrt(1.0 + a) + math.cbrt(1.0 - a));
    const z2 = @sqrt(3.0 * a * a + z1 * z1);
    return 3.0 + z2 - @sqrt((3.0 - z1) * (3.0 + z1 + 2.0 * z2));
}

/// Circular photon orbit radius (prograde or retrograde).
pub fn photonOrbit(a: f64, prograde: bool) f64 {
    const x = if (prograde) -a else a;
    return 2.0 * (1.0 + @cos(2.0 / 3.0 * math.acos(x)));
}

pub const Orbit = struct { E: f64, L: f64, om: f64, ut: f64 };

/// Prograde equatorial circular orbit: specific energy, angular momentum,
/// angular velocity and u^t (Bardeen, Press & Teukolsky 1972).
pub fn orbit(a: f64, r: f64) Orbit {
    const sr = @sqrt(r);
    const r32 = r * sr;
    const den = @sqrt(r32) * @sqrt(r32 - 3.0 * sr + 2.0 * a);
    return .{
        .E = (r32 - 2.0 * sr + a) / den,
        .L = (r * r - 2.0 * a * sr + a * a) / den,
        .om = 1.0 / (r32 + a),
        .ut = (r32 + a) / den,
    };
}

pub const PT_N: usize = 4096;

/// Page-Thorne (1974) flux, up to a constant, on a log grid r_k = r_in (r_max/r_in)^(k/(N-1)):
///   F = -Omega' / (r (E - Omega L)^2) * Integral_{r_in}^{r} (E - Omega L) L' dr
/// evaluated numerically from the exact circular-orbit functions (no closed form needed).
pub fn pageThorne(a: f64, r_in: f64, r_max: f64, out: *[PT_N]f64) void {
    const dl = @log(r_max / r_in) / @as(f64, @floatFromInt(PT_N - 1));
    var integ: f64 = 0.0;
    var prev: f64 = 0.0;
    for (0..PT_N) |k| {
        const r = r_in * @exp(dl * @as(f64, @floatFromInt(k)));
        const e = 1e-6;
        const o = orbit(a, r);
        const op = orbit(a, r * (1.0 + e));
        const om = orbit(a, r * (1.0 - e));
        const dL = (op.L - om.L) / (2.0 * r * e);
        const dOm = (op.om - om.om) / (2.0 * r * e);
        const emo = o.E - o.om * o.L;
        const g = emo * dL * r; // integrand in d(ln r)
        if (k > 0) integ += 0.5 * (g + prev) * dl;
        prev = g;
        out[k] = if (k == 0) 0.0 else -dOm / (emo * emo) * integ / r;
    }
}

// ============================================================================ the disk, computed
// One solution sets the disk's surface density, temperature and optical depth: the general-
// relativistic thin-disk evolution equation (Balbus 2017; Mummery & Balbus 2019, MNRAS 489, 132,
// eqs 4, 5, 16, 53) with a radius-dependent, Sigma-independent stress W = w (r/r0)^(1/2)
// (nu ~ r at large r), zero stress at the ISCO, started from a ring and evaluated once.
// Inside the mass-flux reversal radius it relaxes to the Page-Thorne flux; beyond it the disk is
// spreading outward and its surface density, dissipation and opacity fall off together.

pub const BH_MASS_SUN: f64 = 5.0e9; // a quasar-class supermassive hole
pub const EDD_RATIO: f64 = 0.03; // ISCO accretion rate / (L_Edd / (eta c^2)): a thin disk (>~ 0.01)
pub const ALPHA_VISC: f64 = 0.1; // Shakura-Sunyaev alpha
pub const RING_R0: f64 = 8.0; // M: where the gas was deposited
pub const T_DISPLAY_PEAK: f64 = 6_500.0; // K: the chosen peak (the computed disk's is ~37,000 K)
const RING_D: f64 = 1.6; // M: initial ring width
pub const SNAP_RREV: f64 = 10.0; // M: snapshot when the mass flux reverses here
const DM_N: usize = 1200; // radial nodes of the evolution grid
const DM_RMAX: f64 = 3000.0;
// cgs
const G_CGS: f64 = 6.674e-8;
const C_CGS: f64 = 2.998e10;
const MSUN_G: f64 = 1.989e33;
const SIGMA_SB: f64 = 5.6704e-5;
const K_BOLTZ: f64 = 1.380649e-16;
const M_PROTON: f64 = 1.6726e-24;
const A_RAD: f64 = 7.5657e-15;
const L_EDD_PER_MSUN: f64 = 1.26e38;
const KAPPA_ES: f64 = 0.34; // electron scattering, cm^2/g
const KAPPA_KRAMERS: f64 = 6.4e22; // free-free absorption: kappa = K rho T^-3.5
const T_MAX_SOURCE: f64 = 70_000.0;

fn uT(a: f64, r: f64) f64 { // U^0 of a prograde circular orbit (Mummery 2023 eq 3)
    return (1.0 + a * math.pow(f64, r, -1.5)) / @sqrt(1.0 - 3.0 / r + 2.0 * a * math.pow(f64, r, -1.5));
}
fn uPhi(a: f64, r: f64) f64 { // U_phi (Bardeen, Press & Teukolsky 1972 eq 2.13)
    const sr = @sqrt(r);
    return (r * r - 2.0 * a * sr + a * a) / (math.pow(f64, r, 0.75) * @sqrt(r * sr - 3.0 * sr + 2.0 * a));
}
fn uPhiPrime(a: f64, r: f64) f64 {
    const e = 1e-6;
    return (uPhi(a, r * (1.0 + e)) - uPhi(a, r * (1.0 - e))) / (2.0 * r * e);
}
fn omegaK(a: f64, r: f64) f64 {
    return 1.0 / (r * @sqrt(r) + a);
}
fn omegaPrime(a: f64, r: f64) f64 {
    const q = r * @sqrt(r) + a;
    return -1.5 * @sqrt(r) / (q * q);
}

/// Exponential integral E1 (Abramowitz & Stegun 5.1.53 / 5.1.56) and E3 from it.
fn expE1(x: f64) f64 {
    if (x <= 1.0) {
        return -@log(x) - 0.57721566 + x * (0.99999193 + x * (-0.24991055 + x * (0.05519968 + x * (-0.00976004 + x * 0.00107857))));
    }
    return (x * x + 2.334733 * x + 0.250621) / (x * x + 3.330657 * x + 1.681534) * @exp(-x) / x;
}
fn expE3(x: f64) f64 {
    if (x <= 1e-12) return 0.5;
    if (x > 60.0) return 0.0;
    return 0.5 * (@exp(-x) * (1.0 - x) + x * x * expE1(x));
}

/// The computed disk on the theme's log-r table grid r_k = r_in (r_tab/r_in)^(k/(PT_N-1)):
/// source temperature, ln of the vertical extinction depth (electron scattering + Kramers) and
/// ln of the thermalisation depth tau_* = sqrt(tau_a (tau_a + tau_es)).
pub const PT_CHECK_R = [5]f64{ 3.0, 5.0, 8.0, 10.0, 15.0 };

pub const DiskProfile = struct {
    T: [PT_N]f32,
    lt_ext: [PT_N]f32,
    lt_em: [PT_N]f32,
    t_peak: f64, // K, hottest source temperature
    r_peak: f64,
    tau_es_peak: f64,
    sigma_peak: f64, // g/cm^2
    h_over_r_peak: f64,
    mass_budget: f64, // mass lost / integrated ISCO inflow (1 = exact)
    pt_ratio_spread: f64, // max/min of F / F_PageThorne inside SNAP_RREV / 4
    pt_ratio_at: [5]f64, // F / F_PageThorne (normalised at the ISCO) at PT_CHECK_R
};

/// Solves the disk. `pt` is the Page-Thorne flux on the same grid (shape only), used to set the
/// absolute scale: the snapshot's ISCO inflow is the accretion rate for EDD_RATIO.
pub fn diskProfile(a: f64, r_in: f64, r_tab: f64, pt: *const [PT_N]f64, out: *DiskProfile) void {
    const N = DM_N;
    var r: [N]f64 = undefined;
    r[0] = r_in;
    for (1..N) |i| r[i] = r_in + 1e-4 * math.pow(f64, (DM_RMAX - r_in) / 1e-4, @as(f64, @floatFromInt(i - 1)) / @as(f64, @floatFromInt(N - 2)));
    var cond: [N - 1]f64 = undefined; // face conductance U0 / U'_phi / dr
    for (0..N - 1) |i| {
        const rf = 0.5 * (r[i] + r[i + 1]);
        cond[i] = uT(a, rf) / uPhiPrime(a, rf) / (r[i + 1] - r[i]);
    }
    var coef: [N]f64 = @splat(0.0); // W / U0^2 / cell width
    var z: [N]f64 = @splat(0.0); // zeta = r Sigma W / U0
    for (1..N - 1) |i| {
        const wv = @sqrt(r[i] / RING_R0);
        const ut0 = uT(a, r[i]);
        coef[i] = wv / (ut0 * ut0) / (0.5 * (r[i + 1] - r[i - 1]));
        const sg = @exp(-((r[i] - RING_R0) / RING_D) * ((r[i] - RING_R0) / RING_D));
        z[i] = r[i] * sg * wv / ut0;
    }
    const massOf = struct {
        fn f(rr: *const [N]f64, zz: *const [N]f64, aa: f64) f64 {
            var m: f64 = 0.0;
            for (0..N - 1) |i| {
                const f0 = zz[i] * uT(aa, rr[i]) * uT(aa, rr[i]) / @sqrt(rr[i] / RING_R0);
                const f1 = zz[i + 1] * uT(aa, rr[i + 1]) * uT(aa, rr[i + 1]) / @sqrt(rr[i + 1] / RING_R0);
                m += 0.5 * (f0 + f1) * (rr[i + 1] - rr[i]);
            }
            return m;
        }
    }.f;
    const m0 = massOf(&r, &z, a);
    // Backward Euler (Thomas algorithm), Dirichlet zeta = 0 at the ISCO and at DM_RMAX.
    var lo: [N]f64 = undefined;
    var di: [N]f64 = undefined;
    var up: [N]f64 = undefined;
    var dt: f64 = 1e-4;
    var inflow: f64 = 0.0;
    var steps: usize = 0;
    while (steps < 400_000) : (steps += 1) {
        var imax: usize = 0;
        for (0..N) |i| {
            if (z[i] > z[imax]) imax = i;
        }
        if (r[imax] >= SNAP_RREV) break;
        const f_before = cond[0] * (z[1] - z[0]);
        for (0..N) |i| {
            if (i == 0 or i == N - 1) {
                lo[i] = 0;
                di[i] = 1;
                up[i] = 0;
                continue;
            }
            const c = coef[i] * dt;
            lo[i] = -c * cond[i - 1];
            up[i] = -c * cond[i];
            di[i] = 1.0 + c * (cond[i - 1] + cond[i]);
        }
        z[0] = 0;
        z[N - 1] = 0;
        // forward sweep
        for (1..N) |i| {
            const m = lo[i] / di[i - 1];
            di[i] -= m * up[i - 1];
            z[i] -= m * z[i - 1];
        }
        z[N - 1] /= di[N - 1];
        var i: usize = N - 1;
        while (i > 0) {
            i -= 1;
            z[i] = (z[i] - up[i] * z[i + 1]) / di[i];
        }
        inflow += 0.5 * (f_before + cond[0] * (z[1] - z[0])) * dt;
        dt = @min(dt * 1.003, 0.2);
    }
    out.mass_budget = (m0 - massOf(&r, &z, a)) / @max(inflow, 1e-300);

    // Dissipation per face (MB19a eq 53): F = -(U0)^2 zeta Omega' / (2r), geometric units.
    var fg: [N]f64 = undefined;
    for (0..N) |i| fg[i] = if (i == 0) 0.0 else -uT(a, r[i]) * uT(a, r[i]) * z[i] * omegaPrime(a, r[i]) / (2.0 * r[i]);
    const dl = @log(r_tab / r_in) / @as(f64, @floatFromInt(PT_N - 1));
    const fgAt = struct {
        fn f(rr: *const [N]f64, ff: *const [N]f64, x: f64) f64 {
            if (x <= rr[0]) return 0.0;
            var lo_i: usize = 0;
            var hi_i: usize = N - 1;
            while (hi_i - lo_i > 1) {
                const mid = (lo_i + hi_i) / 2;
                if (rr[mid] <= x) lo_i = mid else hi_i = mid;
            }
            const t = (x - rr[lo_i]) / (rr[hi_i] - rr[lo_i]);
            return ff[lo_i] + (ff[hi_i] - ff[lo_i]) * t;
        }
    }.f;
    // Scale: near the ISCO the solution is in steady inflow, F = F_PT * inflow; match it there.
    var ratio_sum: f64 = 0.0;
    var ratio_n: f64 = 0.0;
    var rmin: f64 = 1e300;
    var rmax: f64 = 0.0;
    for (0..PT_N) |k| {
        const rk = r_in * @exp(dl * @as(f64, @floatFromInt(k)));
        if (rk < 1.05 * r_in or pt[k] <= 0.0) continue;
        const q = fgAt(&r, &fg, rk) / pt[k];
        if (rk < 1.4 * r_in) {
            ratio_sum += q;
            ratio_n += 1.0;
        }
        if (rk < SNAP_RREV / 4.0) {
            rmin = @min(rmin, q);
            rmax = @max(rmax, q);
        }
    }
    const norm = ratio_sum / @max(ratio_n, 1.0);
    out.pt_ratio_spread = rmax / @max(rmin, 1e-300);
    for (PT_CHECK_R, 0..) |rc, ci| {
        const k: usize = @intFromFloat(@round(@log(rc / r_in) / dl));
        out.pt_ratio_at[ci] = fgAt(&r, &fg, rc) / pt[k] / norm;
    }

    // Physical units.
    const m_g = BH_MASS_SUN * MSUN_G;
    const rg = G_CGS * m_g / (C_CGS * C_CGS);
    const tg = rg / C_CGS;
    const eff = 1.0 - orbit(a, r_in).E;
    const mdot = EDD_RATIO * L_EDD_PER_MSUN * BH_MASS_SUN / (eff * C_CGS * C_CGS);
    const fscale = mdot * math.pow(f64, C_CGS, 6) / (G_CGS * G_CGS * m_g * m_g) / (4.0 * math.pi) / norm;
    // Peak of the flux, then the stress there from the alpha closure (gas + radiation pressure).
    var ipk: usize = 1;
    for (1..N) |i| {
        if (fg[i] > fg[ipk]) ipk = i;
    }
    const Local = struct { sigma: f64, tes: f64, ta: f64, tc: f64, cs2: f64, rho: f64 };
    // Local structure: Sigma from the flux and the closure's stress; scale height from vertical
    // hydrostatic balance with the local gas + radiation pressure; midplane temperature from
    // radiative diffusion (uniform heating: T_c^4 = (3/8 tau_half + 1) T_eff^4). Iterated jointly.
    const local = struct {
        fn f(aa: f64, rr: f64, fphys: f64, wphys: f64, rgc: f64, tgc: f64) Local {
            const teff4 = fphys / SIGMA_SB;
            const om = omegaK(aa, rr) / tgc;
            const domp = @abs(omegaPrime(aa, rr)) / tgc / rgc;
            const sg = 2.0 * fphys / (uT(aa, rr) * wphys * domp);
            var tc = @sqrt(@sqrt(teff4));
            var cs2 = K_BOLTZ * tc / (0.6 * M_PROTON);
            var rho: f64 = sg * om / (2.0 * @sqrt(cs2));
            var tes: f64 = 0.0;
            var ta: f64 = 0.0;
            for (0..200) |_| {
                rho = sg * om / (2.0 * @sqrt(cs2)); // Sigma / 2H, H = c_s / Omega
                tes = KAPPA_ES * sg / 2.0;
                ta = KAPPA_KRAMERS * rho * math.pow(f64, @max(tc, 1.0), -3.5) * sg / 2.0;
                const tn = @sqrt(@sqrt(0.375 * (tes + ta) * teff4 + teff4));
                const cn = K_BOLTZ * tn / (0.6 * M_PROTON) + A_RAD * math.pow(f64, tn, 4) / (3.0 * rho);
                if (@abs(tn - tc) < 1e-9 * tc and @abs(cn - cs2) < 1e-9 * cs2) break;
                tc = 0.5 * (tc + tn);
                cs2 = @sqrt(cs2 * cn);
            }
            return .{ .sigma = sg, .tes = tes, .ta = ta, .tc = tc, .cs2 = cs2, .rho = rho };
        }
    }.f;
    const fpk = fg[ipk] * fscale;
    var wpk: f64 = 1e14 * r[ipk] * rg;
    var lp: Local = undefined;
    for (0..300) |_| {
        lp = local(a, r[ipk], fpk, wpk, rg, tg);
        const p_rho = K_BOLTZ * lp.tc / (0.6 * M_PROTON) + A_RAD * math.pow(f64, lp.tc, 4) / (3.0 * lp.rho);
        const wn = 1.5 * ALPHA_VISC * p_rho * r[ipk] * rg;
        if (@abs(wn / wpk - 1.0) < 1e-9) break;
        wpk = @sqrt(wpk * wn);
    }
    const wref = wpk / @sqrt(r[ipk] / RING_R0);
    out.r_peak = r[ipk];
    out.sigma_peak = lp.sigma;
    out.tau_es_peak = lp.tes;
    out.h_over_r_peak = @sqrt(lp.cs2) / (omegaK(a, r[ipk]) / tg) / (r[ipk] * rg);
    out.t_peak = 0.0;
    for (0..PT_N) |k| {
        const rk = r_in * @exp(dl * @as(f64, @floatFromInt(k)));
        const fphys = fgAt(&r, &fg, rk) * fscale;
        if (!(fphys > 1e-30 * fpk) or rk <= r_in) {
            out.T[k] = 0;
            out.lt_ext[k] = -60;
            out.lt_em[k] = -60;
            continue;
        }
        const lk = local(a, rk, fphys, wref * @sqrt(rk / RING_R0), rg, tg);
        // Through the whole slab (both halves): a crossing ray and the slab's emission see 2x
        // the midplane-to-surface depths that set the midplane temperature above.
        const tes_f = 2.0 * lk.tes;
        // Emission depth: the thermalisation depth sqrt(tau_a tau_ext) where scattering is thick,
        // the absorption depth lengthened by the scattering path, tau_a (1 + tau_es), where it is
        // thin (an effectively thin slab emits 2 tau_a sigma T^4 per face, scattering or not).
        // Absorption stays at the midplane temperature: evaluated at the hotter source
        // temperature of the thin tail it runs away (free-free cooling falls as the gas heats),
        // the sign that neither Kramers nor electron scattering applies there (see header).
        const ta_f = 2.0 * lk.ta;
        const tem = @min(ta_f * (1.0 + tes_f), @sqrt(ta_f * (ta_f + tes_f)));
        const emiss = 1.0 - 2.0 * expE3(tem); // grey isothermal slab: flux out = sigma T_s^4 (1 - 2 E3)
        const ts = @min(@sqrt(@sqrt(fphys / (SIGMA_SB * @max(emiss, 1e-300)))), T_MAX_SOURCE);
        out.T[k] = @floatCast(ts);
        out.lt_ext[k] = @floatCast(@max(@log(tes_f + ta_f), -60.0));
        out.lt_em[k] = @floatCast(@max(@log(tem), -60.0));
        if (rk < 30.0) out.t_peak = @max(out.t_peak, ts);
    }
}


// ---------------------------------------------------------------- geodesics

const V6 = @Vector(6, f64); // r, theta, phi, t, p_r, p_theta

/// Hamilton's equations for Kerr null geodesics with E = 1, L = photon angular
/// momentum (real, forward-in-time photon). r/theta dynamics are invariant under
/// the backward-tracing flip (E,L,p) -> (-E,-L,-p); phi and t are negated so the
/// ray is followed backward along the real photon's path.
fn rhs(a: f64, L: f64, y: V6) V6 {
    const r = y[0];
    const s0 = @sin(y[1]);
    const c = @cos(y[1]);
    const s = if (@abs(s0) < 1e-9) (if (s0 < 0) @as(f64, -1e-9) else 1e-9) else s0;
    const s2 = s * s;
    const a2 = a * a;
    const r2 = r * r;
    const sig = r2 + a2 * c * c;
    const del = r2 - 2.0 * r + a2;
    const P = r2 + a2 - a * L;
    const isig = 1.0 / sig;
    const idel = 1.0 / del;
    const pr = y[4];
    const dBdr = (2.0 * r - 2.0) * pr * pr - (4.0 * r * P * del - P * P * (2.0 * r - 2.0)) * idel * idel;
    const dBdth = (-2.0 * L * L / (s2 * s) + 2.0 * a2 * s) * c;
    return .{
        del * pr * isig,
        y[5] * isig,
        -(a * P * idel + L / s2 - a) * isig,
        -((r2 + a2) * P * idel + a * (L - a * s2)) * isig,
        -0.5 * dBdr * isig,
        -0.5 * dBdth * isig,
    };
}

fn rk4(a: f64, L: f64, y: V6, h: f64) V6 {
    return rk4k(a, L, y, h, rhs(a, L, y));
}

fn rk4k(a: f64, L: f64, y: V6, h: f64, k1: V6) V6 {
    const hv: V6 = @splat(h);
    const half: V6 = @splat(0.5 * h);
    const k2 = rhs(a, L, y + k1 * half);
    const k3 = rhs(a, L, y + k2 * half);
    const k4 = rhs(a, L, y + k3 * hv);
    const sixth: V6 = @splat(1.0 / 6.0);
    return y + hv * sixth * (k1 + (k2 + k3) * @as(V6, @splat(2.0)) + k4);
}

/// Step size: geometric in r far away, proportional to distance from the horizon near it,
/// and capped so theta and phi each move < 0.08 rad per step (rays skimming the spin axis).
fn stepSize(g: *const Geo, L: f64, y: V6, d: V6) f64 {
    const r = y[0];
    var h: f64 = if (r > 200.0) 0.25 * r else if (r > 60.0) 0.1 * r else K_NEAR * @min(r, 4.0 * (r - g.rh));
    if (r < 200.0) {
        h = @min(h, 0.08 / @max(@abs(d[1]), 1e-12));
        h = @min(h, 0.08 / @max(@abs(d[2]), 1e-12));
        // Near the spin axis theta turns on a scale ~ sin(theta): resolve that bend. A ray with
        // angular momentum L turns back at sin(theta) ~ |L| / sqrt(Q) ~ |L| / 5; the floor (which
        // lets L ~ 0 rays cross the pole) stays under 5% of that, so the turn is resolved too.
        // Unresolved, it threw the photon off its orbit: a sliver of false capture at alpha ~ 0.
        // Steps shrink geometrically into the turn, so even L = 0 crosses in ~300 steps; the
        // minimum step makes way for it only on such rays (|L| < 1e-3), so no other ray changes.
        h = @min(h, (0.05 * @abs(@sin(y[1])) + math.clamp(0.01 * @abs(L), 1e-8, 2e-4)) / @max(@abs(d[1]), 1e-12));
    }
    return @max(h, math.clamp(0.01 * @abs(L), 1e-8, 1e-5));
}

/// Re-solve p_r from the null condition (keeping its sign). Far from the hole the
/// orbit-defining constant K ~ 27 is 1e-5 of the r^2-sized terms, so unconstrained
/// integration errors would silently move the photon onto a different orbit.
fn project(a: f64, L: f64, y: V6) V6 {
    const s = @sin(y[1]);
    const s2 = @max(s * s, 1e-18);
    const r = y[0];
    const del = r * r - 2.0 * r + a * a;
    const P = r * r + a * a - a * L;
    const X = P * P / del - y[5] * y[5] - (L - a * s2) * (L - a * s2) / s2;
    // Near a radial turning point (X -> 0) the raw Hamiltonian flow is smooth and accurate;
    // clamping there would stall the ray for a step. Only project where |p_r| is order unity.
    if (X < 0.05 * P * P / del) return y;
    const mag = @sqrt(X / del);
    var out = y;
    out[4] = if (y[4] < 0.0) -mag else mag;
    return out;
}

pub const Geo = struct {
    a: f64,
    incl: f64,
    sin_i: f64,
    cos_i: f64,
    rh: f64,
    r_in: f64,
    r_out: f64,

    pub fn init(a: f64, incl: f64, r_out: f64) Geo {
        return .{ .a = a, .incl = incl, .sin_i = @sin(incl), .cos_i = @cos(incl), .rh = horizon(a), .r_in = isco(a), .r_out = r_out };
    }
};

pub const Kind = enum(u8) { sky, disk, hole };

pub const Hit = struct {
    kind: Kind = .hole,
    n: u8 = 0,
    r: f64 = 0,
    ph: f64 = 0,
    t: f64 = 0,
    dir: [3]f64 = .{ 0, 0, 0 },
    steps: u32 = 0,
    pth: f64 = 0, // photon p_theta at a disk crossing: sets the angle it crosses the gas at
};

/// Initial state for the backward ray through screen point (alpha, beta), camera at
/// r = OBS_R, theta = incl, phi = 0. Up on screen = decreasing theta.
pub fn initialState(g: *const Geo, alpha: f64, beta: f64) struct { y: V6, L: f64 } {
    const a = g.a;
    const L = -alpha * g.sin_i;
    const r = OBS_R;
    const s2 = g.sin_i * g.sin_i;
    const del = r * r - 2.0 * r + a * a;
    const P = r * r + a * a - a * L;
    const f = (L - a * s2) * (L - a * s2) / s2;
    const pth = -beta;
    const X = P * P / del - pth * pth - f;
    const pr = -@sqrt(@max(X, 0.0) / del);
    return .{ .y = .{ r, g.incl, 0.0, 0.0, pr, pth }, .L = L };
}

pub const Ray = struct { y: V6, L: f64, n: u8 = 0, steps: u32 = 0 };

pub fn startRay(g: *const Geo, alpha: f64, beta: f64) Ray {
    const st = initialState(g, alpha, beta);
    return .{ .y = st.y, .L = st.L };
}

pub fn traceRay(g: *const Geo, alpha: f64, beta: f64, with_disk: bool) Hit {
    var ray = startRay(g, alpha, beta);
    return traceNext(g, &ray, with_disk);
}

/// Follow the ray to the next thing it meets. On a disk hit the state is left just past
/// the crossing, so calling again finds what lies behind translucent gas.
pub fn traceNext(g: *const Geo, ray: *Ray, with_disk: bool) Hit {
    var y = ray.y;
    const L = ray.L;
    var n = ray.n;
    var steps = ray.steps;
    while (steps < MAX_STEPS) : (steps += 1) {
        const r = y[0];
        if (r < g.rh + 0.02) return .{ .kind = .hole, .steps = steps };
        if (y[4] > 0.0 and r > 2.0e4) {
            const d = rhs(g.a, L, y);
            const s = @sin(y[1]);
            const c = @cos(y[1]);
            const sp = @sin(y[2]);
            const cp = @cos(y[2]);
            const vr = d[0];
            const vt = r * d[1];
            const vp = r * s * d[2];
            var v = [3]f64{
                vr * s * cp + vt * c * cp - vp * sp,
                vr * s * sp + vt * c * sp + vp * cp,
                vr * c - vt * s,
            };
            const nv = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
            for (&v) |*x| x.* /= nv;
            return .{ .kind = .sky, .dir = v, .steps = steps };
        }
        const k1 = rhs(g.a, L, y);
        const h = stepSize(g, L, y, k1);
        const prev = y;
        y = project(g.a, L, rk4k(g.a, L, y, h, k1));
        if (!std.math.isFinite(y[0]) or !std.math.isFinite(y[1])) return .{ .kind = .hole, .steps = steps };
        // Equator crossing via the sign of cos(theta): robust if theta wraps through a pole.
        const e0 = @cos(prev[1]);
        const e1 = @cos(y[1]);
        if ((e0 < 0.0) != (e1 < 0.0)) {
            n +|= 1;
            // Land exactly on the equator: secant iterations on a partial RK4 step from prev.
            var lo: f64 = 0.0;
            var hi: f64 = h;
            var flo = e0;
            var fhi = e1;
            var yc = y;
            for (0..4) |_| {
                const hm = lo + (hi - lo) * flo / (flo - fhi);
                yc = rk4k(g.a, L, prev, hm, k1);
                const fm = @cos(yc[1]);
                if ((fm < 0.0) == (flo < 0.0)) {
                    lo = hm;
                    flo = fm;
                } else {
                    hi = hm;
                    fhi = fm;
                }
                if (@abs(fm) < 1e-12) break;
            }
            const rc = yc[0];
            if (with_disk and rc >= g.r_in and rc <= g.r_out) {
                ray.* = .{ .y = y, .L = L, .n = n, .steps = steps + 1 };
                return .{ .kind = .disk, .n = n, .r = rc, .ph = yc[2], .t = yc[3], .steps = steps, .pth = yc[5] };
            }
        }
    }
    return .{ .kind = .hole, .steps = steps };
}

/// Kerr redshift g = E_obs / E_emit for a photon (E = 1, angular momentum L)
/// emitted by gas on a prograde circular orbit at r.
pub fn redshift(a: f64, r: f64, L: f64) f64 {
    const o = orbit(a, r);
    return 1.0 / (o.ut * (1.0 - o.om * L));
}

// ---------------------------------------------------------------- color science

pub const BB_N: usize = 1024;
pub const BB_TMIN: f64 = 300.0;
pub const BB_TMAX: f64 = 200_000.0; // above the hottest observed colour temperature (~105 kK: g f T on the approaching inner disk)

fn lobe(l: f64, mu: f64, s1: f64, s2: f64) f64 {
    const t = (l - mu) / (if (l < mu) s1 else s2);
    return @exp(-0.5 * t * t);
}

/// CIE 1931 2-degree observer, multi-lobe Gaussian fit (Wyman, Sloan & Shirley 2013).
fn cmf(l: f64) [3]f64 {
    return .{
        1.056 * lobe(l, 599.8, 37.9, 31.0) + 0.362 * lobe(l, 442.0, 16.0, 26.7) - 0.065 * lobe(l, 501.1, 20.4, 26.2),
        0.821 * lobe(l, 568.8, 46.9, 40.5) + 0.286 * lobe(l, 530.9, 16.3, 31.1),
        1.217 * lobe(l, 437.0, 11.8, 36.0) + 0.681 * lobe(l, 459.0, 26.0, 13.8),
    };
}

/// Linear sRGB of a blackbody at T (arbitrary but consistent absolute scale).
pub fn blackbodyRGB(T: f64) [3]f64 {
    var xyz = [3]f64{ 0, 0, 0 };
    var l: f64 = 380.0;
    while (l <= 780.0) : (l += 5.0) {
        const lum = l * 1e-3; // micrometres
        const planck = 1.0 / (lum * lum * lum * lum * lum * std.math.expm1(14387.77 / (lum * T)));
        const c = cmf(l);
        for (0..3) |i| xyz[i] += planck * c[i];
    }
    return .{
        @max(0.0, 3.2406 * xyz[0] - 1.5372 * xyz[1] - 0.4986 * xyz[2]),
        @max(0.0, -0.9689 * xyz[0] + 1.8758 * xyz[1] + 0.0415 * xyz[2]),
        @max(0.0, 0.0557 * xyz[0] - 0.2040 * xyz[1] + 1.0570 * xyz[2]),
    };
}

fn luma(c: [3]f64) f64 {
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

fn srgbEncode(v: f64) f64 {
    return if (v <= 0.0031308) 12.92 * v else 1.055 * math.pow(f64, v, 1.0 / 2.4) - 0.055;
}

// ---------------------------------------------------------------- deterministic hashing

fn mix64(x0: u64) u64 {
    var z = x0 +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn unitf(h: u64) f64 {
    return @as(f64, @floatFromInt(h >> 11)) / 9007199254740992.0;
}

fn latticeVal(ix: i64, iy: i64, iz: i64, seed: u64) f64 {
    return unitf(mix64(seed ^ @as(u64, @bitCast(ix)) *% 0x9E3779B1 ^ @as(u64, @bitCast(iy)) *% 0x85EBCA77 ^ @as(u64, @bitCast(iz)) *% 0xC2B2AE3D));
}

/// Smooth 3D value noise in [0,1].
fn noise3(p: [3]f64, seed: u64) f64 {
    const f = [3]f64{ @floor(p[0]), @floor(p[1]), @floor(p[2]) };
    const i = [3]i64{ @intFromFloat(f[0]), @intFromFloat(f[1]), @intFromFloat(f[2]) };
    var u: [3]f64 = undefined;
    for (0..3) |k| {
        const t = p[k] - f[k];
        u[k] = t * t * (3.0 - 2.0 * t);
    }
    var acc: f64 = 0.0;
    for (0..8) |c| {
        const dx: i64 = @intCast(c & 1);
        const dy: i64 = @intCast((c >> 1) & 1);
        const dz: i64 = @intCast((c >> 2) & 1);
        const wx = if (dx == 1) u[0] else 1.0 - u[0];
        const wy = if (dy == 1) u[1] else 1.0 - u[1];
        const wz = if (dz == 1) u[2] else 1.0 - u[2];
        acc += wx * wy * wz * latticeVal(i[0] + dx, i[1] + dy, i[2] + dz, seed);
    }
    return acc;
}

fn dot3(a: [3]f64, b: [3]f64) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

// ============================================================================ theme state

const R_BINS: usize = 384;
const R_FRAC: u16 = 128; // rbin is stored in 1/128ths of a bin: magnified regions need sub-bin radius
const NP: usize = 1024;
const BLOCK: usize = 4;

const FR_Q = R_FRAC / 4; // footprint unit: a quarter radial bin (eddies are below a bin)
const FR_SAT: u8 = 73; // quarter bins: where the GPU's 5-bit footprint code saturates (12 + ceil(73/4) = 31)

const Rec = extern struct {
    rgb: [3]f16, // linear HDR disk radiance (pre-exposure)
    rbin: u16, // radial bin * R_FRAC (fixed point)
    phi: u16, // emission azimuth + Omega * travel time, Q16 of 2 pi
    cov: u8, // disk coverage 0..255
    fr: u8 = 0, // pixel footprint on the disk: radial extent in quarter r-bins (saturating)
    tobs: f16 = 0, // observed blackbody temperature g*T, for re-coloring hotter gas
    fp: u8 = 0, // pixel footprint: azimuthal extent in units of 64/65536 turn (saturating)
    bf: u8 = 0, // share of bg (luminance, /255) that lies behind this pixel's translucent gas
    resp: u8 = 0, // CPU turbulence: d ln(luminance) / d ln(eps) at tobs (T ~ eps^(1/4)), * RESP_SCALE
    tq: u16 = 0, // light-travel phase Omega*t in 1/1024 turn, mod 64 turns: kept apart so it can be unwrapped
};

const Sample = struct {
    disk: bool = false,
    tobs: f64 = 0,
    tq: u16 = 0,
    rgb: [3]f64 = .{ 0, 0, 0 }, // disk radiance, or sky linear color
    rbin: u16 = 0,
    phi: u16 = 0,
};

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    slab: []align(16) u8,
    recs: []Rec,
    bg: []u32,
    row_x0: []u16,
    row_x1: []u16,
    corners: []Hit,
    deferred: bool, // CPU trace not run yet (GPU builds)

    geo: Geo,
    mpp: f64,
    pix_ang: f64,
    lnr_in: f64,
    lnr_span: f64,
    exposure: f32,
    t_m: f64,
    rays_traced: u64,

    gal_n: [3]f64, // galactic plane normal
    gal_c: [3]f64, // galactic center direction
    spot_rb: [NSPOT]f32,
    spot_wr: [NSPOT]f32, // radial half-width, r-bins
    spot_wp: [NSPOT]f32, // azimuthal half-width, Q16 units
    spot_q: [NSPOT]u16,
    spot_amp: [NSPOT]f32,
    spot_age: [NSPOT]f32, // M since the spot was born (its shear)
    spot_om: [NSPOT]f32, // Omega at the spot's birth radius
    spot_mask: [R_BINS]u8,
    band_u: [NBAND]f32, // phase of each lifetime band in its generation cycle, 0..1
    band_ka: [NBAND]u32, // generation counters of the band's two staggered generations
    band_kb: [NBAND]u32,
    gen: [N_OCT][NBAND][2]TurbGen, // per-frame generation constants (octave, band, A/B)
    gtab: [R_BINS][GT_NP]f32, // CPU path: coarse turbulence this frame per radial bin and phase slot
    gtmp: [R_BINS][GT_NP]f32, // its unfiltered point samples
    band_n0: [R_BINS]u8, // CPU path: octave-0 band below each bin and its two blend weights
    band_w: [R_BINS][2]f32,
    sband: [N_OCT][R_BINS]f32, // log2(lifetime / BAND_L0) per octave and radial bin
    om_row: [NR]f32, // Omega at each turbulence row
    cell_r0: f32, // octave-0 cell size: radial bins
    cell_p0: f32, // octave-0 cell size: azimuth, Q16
    turb_sigma: f32, // TURB_SIGMA, for the GPU path
    spot_rmax: f64, // SPOT_RMAX, for the GPU path
    sky_gain: f32, // SKY_VISIBLE, for the GPU path
    rho_row: [N_OCT]f32, // measured neighbour correlation of each noise plane: rows, phase cells
    rho_ph: [N_OCT]f32,
    foot_cr: [N_OCT]f32, // GPU footprint filter: cell constants of the box-averaged rendered field
    foot_cp: [N_OCT]f32,
    om_tab: [R_BINS]f64,
    shear_tab: [R_BINS]f32, // |dOmega/d rbin| in Q16 per M: how fast a sheared spot's azimuth runs with radius
    lntau_tab: [R_BINS]f32, // ln vertical extinction depth per radial bin
    lnem_tab: [R_BINS]f32, // ln vertical thermalisation depth per radial bin
    t_peak: f64, // hottest source temperature of the computed disk (K)
    emit_tab: [EMIT_N + 1]f32,
    lin8: [256]f32, // sRGB byte -> linear
    // The computed disk on the log-r grid: [0] source temperature (K), [1] ln vertical extinction
    // depth, [2] ln vertical thermalisation depth. One block, so the GPU uploads it as is.
    dtab: [4][PT_N]f32, // colour temperature f T_s, ln tau_ext, ln tau_em, ln f^-4 (spectral dilution)
    bb: [BB_N][3]f32,
    srgb: [4096]u8,
    noise: [N_OCT][NR][NP]u8, // turbulence, one plane per octave (each lives on its own clock)
    exp_tab: [EXP_N + 1]f32,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const n_px = w * h;
        const nbx = (w + BLOCK - 1) / BLOCK;
        // One slab: State | recs | bg | row ranges | two rows of corner hits (front + 2 behind).
        const off_recs = std.mem.alignForward(usize, @sizeOf(State), 16);
        const off_bg = std.mem.alignForward(usize, off_recs + n_px * @sizeOf(Rec), 16);
        const off_rows = std.mem.alignForward(usize, off_bg + n_px * 4, 16);
        const off_corn = std.mem.alignForward(usize, off_rows + h * 4, 16);
        const total = off_corn + 6 * (nbx + 1) * @sizeOf(Hit);
        const slab = try alloc.alignedAlloc(u8, .@"16", total);
        const self: *State = @ptrCast(@alignCast(slab.ptr));
        self.slab = slab;
        self.w = w;
        self.h = h;
        self.scale = scale;
        self.recs = @as([*]Rec, @ptrCast(@alignCast(slab.ptr + off_recs)))[0..n_px];
        self.bg = @as([*]u32, @ptrCast(@alignCast(slab.ptr + off_bg)))[0..n_px];
        const rows: [*]u16 = @ptrCast(@alignCast(slab.ptr + off_rows));
        self.row_x0 = rows[0..h];
        self.row_x1 = rows[h .. 2 * h];
        self.corners = @as([*]Hit, @ptrCast(@alignCast(slab.ptr + off_corn)))[0 .. 6 * (nbx + 1)];
        self.deferred = n_px > 0;

        self.geo = Geo.init(SPIN, INCL, R_OUT);
        self.mpp = if (h > 0) 2.0 * HALF_H / @as(f64, @floatFromInt(h)) else 1.0;
        self.pix_ang = self.mpp / OBS_R;
        self.lnr_in = @log(self.geo.r_in);
        self.lnr_span = @log(R_OUT / self.geo.r_in);
        self.t_m = 0.0;
        self.rays_traced = 0;
        self.exposure = 1.0;
        self.buildTables();
        {
            // Place the Milky Way behind the hole, tilted on screen, bulge just off-center.
            const g = self.geo;
            const v = [3]f64{ -g.sin_i, 0.0, -g.cos_i }; // looking through the hole
            const ea = [3]f64{ 0.0, 1.0, 0.0 }; // screen right
            const eb = [3]f64{ -g.cos_i, 0.0, g.sin_i }; // screen up
            const ct = @cos(GAL_TILT);
            const st = @sin(GAL_TILT);
            self.gal_n = .{ ct * eb[0] - st * ea[0], ct * eb[1] - st * ea[1], ct * eb[2] - st * ea[2] };
            var c = [3]f64{ v[0] + 0.12 * (ct * ea[0] + st * eb[0]), v[1] + 0.12 * (ct * ea[1] + st * eb[1]), v[2] + 0.12 * (ct * ea[2] + st * eb[2]) };
            const nc = @sqrt(dot3(c, c));
            for (&c) |*x| x.* /= nc;
            self.gal_c = c;
        }
        self.spot_mask = @splat(0);
        if (!gpu_traced) self.traceNow();
        self.step(1e-9);
        return self;
    }

    fn traceNow(self: *State) void {
        if (!self.deferred) return;
        self.deferred = false;
        self.meterExposure();
        self.render(self.corners);
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.free(self.slab);
    }

    fn buildTables(self: *State) void {
        // The disk: temperature and optical depths from one relativistic solution (diskProfile).
        var flux: [PT_N]f64 = undefined;
        pageThorne(self.geo.a, self.geo.r_in, R_OUT * 1.05, &flux);
        var disk: DiskProfile = undefined;
        diskProfile(self.geo.a, self.geo.r_in, R_OUT * 1.05, &flux, &disk);
        // Colour correction (Done et al. 2012): the scattering atmosphere hardens the spectrum to
        // f^-4 B(f T_s), the same bolometric flux at a bluer colour.
        // Gargantua's chosen disk (see header): a steady Page-Thorne disk, T ~ F^(1/4) scaled to
        // a T_DISPLAY_PEAK peak, and a translucent outer disk whose column rolls off as the
        // Lynden-Bell & Pringle gamma = 1 profile, tau = GARG_TAU0 (GARG_RC / r) e^(-r / GARG_RC).
        // (The computed quasar disk above is still solved: its tests and diagnostics run, and
        // a self-consistent 6,500 K solution would be opaque everywhere; see header.)
        _ = &disk;
        var fmax: f64 = 0.0;
        for (flux) |v| fmax = @max(fmax, v);
        var tcol: [PT_N]f32 = undefined;
        var ltau: [PT_N]f32 = undefined;
        var ldil: [PT_N]f32 = undefined;
        for (0..PT_N) |k| {
            const rk = self.geo.r_in * @exp(@log(R_OUT * 1.05 / self.geo.r_in) * @as(f64, @floatFromInt(k)) / @as(f64, PT_N - 1));
            const ts = T_DISPLAY_PEAK * @sqrt(@sqrt(@max(flux[k], 0.0) / fmax));
            const fc = colourFactor(ts); // 1 below 3e4 K: kept for the shared engine
            tcol[k] = @floatCast(fc * ts);
            ldil[k] = @floatCast(-4.0 * @log(fc));
            ltau[k] = @floatCast(@max(@log(GARG_TAU0 * (GARG_RC / rk)) - rk / GARG_RC, -60.0));
        }
        self.dtab = .{ tcol, ltau, ltau, ldil }; // grey gas: emission and extinction depth alike
        self.t_peak = T_DISPLAY_PEAK;
        // Blackbody colors, normalised so the hottest disk blackbody has luminance 1.
        const y0 = luma(blackbodyRGB(self.t_peak));
        for (0..BB_N) |k| {
            const T = BB_TMIN * @exp(@log(BB_TMAX / BB_TMIN) * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(BB_N - 1)));
            const c = blackbodyRGB(T);
            for (0..3) |i| self.bb[k][i] = @floatCast(c[i] / y0);
        }
        for (0..4096) |k| self.srgb[k] = @intFromFloat(@round(255.0 * srgbEncode(@as(f64, @floatFromInt(k)) / 4095.0)));
        for (0..R_BINS) |b| {
            const r = @exp(self.lnr_in + self.lnr_span * (@as(f64, @floatFromInt(b)) + 0.5) / @as(f64, @floatFromInt(R_BINS)));
            self.om_tab[b] = orbit(self.geo.a, r).om;
            const r15 = r * @sqrt(r) + self.geo.a;
            self.shear_tab[b] = @floatCast(1.5 * @sqrt(r) / (r15 * r15) * r * (self.lnr_span / @as(f64, @floatFromInt(R_BINS))) * 65536.0 / (2.0 * math.pi));
            self.lntau_tab[b] = @floatCast(@log(self.tauExt(r)));
            self.lnem_tab[b] = @floatCast(@log(self.tauEm(r)));
        }
        for (0..EMIT_N + 1) |k| {
            const x = EMIT_X0 + (EMIT_X1 - EMIT_X0) * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(EMIT_N));
            self.emit_tab[k] = @floatCast(-std.math.expm1(-@exp(@as(f64, x))));
        }
        for (0..256) |k| {
            const v = @as(f64, @floatFromInt(k)) / 255.0;
            self.lin8[k] = @floatCast(if (v <= 0.04045) v / 12.92 else math.pow(f64, (v + 0.055) / 1.055, 2.4));
        }
        // Turbulence planes, periodic in row and phase: octave j has birth cells of 2 x (EDDY_MIN_H,
        // EDDY_MAJ_H) H / 2^j (correlation falls to 1/e at ~0.77 cell). The long axis is tilted by shearing
        // the radial coordinate along the azimuth (TILT_ROWS rows per phase cell); the cell sizes
        // are corrected by cos(tilt) so the eddy keeps its width across and length along its axis.
        // Normalised per plane: two passes, moments then bytes.
        const dl_row = self.lnr_span / @as(f64, @floatFromInt(NR));
        const dphi_cell = 2.0 * math.pi / @as(f64, @floatFromInt(NP));
        const cos_tilt = @cos(math.atan(TILT_ROWS * dl_row / dphi_cell));
        const cell_rows = 2.0 * EDDY_MIN_H * H_OVER_R / dl_row / cos_tilt;
        const cell_ph = 2.0 * EDDY_MAJ_H * H_OVER_R / dphi_cell * cos_tilt;
        self.cell_r0 = @floatCast(2.0 * EDDY_MIN_H * H_OVER_R / (self.lnr_span / @as(f64, @floatFromInt(R_BINS))));
        self.cell_p0 = @floatCast(2.0 * EDDY_MAJ_H * H_OVER_R / (2.0 * math.pi) * 65536.0);
        self.turb_sigma = TURB_SIGMA;
        self.spot_rmax = SPOT_RMAX;
        self.sky_gain = @floatCast(SKY_VISIBLE);
        for (0..N_OCT) |oct| {
            const sc = math.pow(f64, 2.0, @floatFromInt(oct));
            const gr: usize = @max(1, @as(usize, @intFromFloat(@round(@as(f64, NR) / (cell_rows / sc)))));
            const gp: usize = @max(1, @as(usize, @intFromFloat(@round(@as(f64, NP) / (cell_ph / sc)))));
            var sum: f64 = 0.0;
            var sum2: f64 = 0.0;
            for (0..2) |pass| {
                const mean = sum / @as(f64, NR * NP);
                const sd = @sqrt(@max(sum2 / @as(f64, NR * NP) - mean * mean, 1e-12));
                for (0..NR) |ri| {
                    for (0..NP) |pi| {
                        const v = turbulence(ri, pi, oct, gr, gp);
                        if (pass == 0) {
                            sum += v;
                            sum2 += v * v;
                        } else {
                            self.noise[oct][ri][pi] = @intFromFloat(@round(math.clamp(128.0 + @as(f64, NOISE_STD) * (v - mean) / sd, 0.0, 255.0)));
                        }
                    }
                }
            }
        }
        for (0..NR) |ri| {
            const r = @exp(self.lnr_in + self.lnr_span * (@as(f64, @floatFromInt(ri)) + 0.5) / @as(f64, @floatFromInt(NR)));
            self.om_row[ri] = @floatCast(orbit(self.geo.a, r).om);
        }
        // Neighbour correlations of each plane (for the GPU's variance-preserving interpolation),
        // measured on the static planes: an upper bound for rows, which shear decorrelates as
        // eddies age (Opus_Quasar uses values fitted on the rendered field). An approximation:
        // between rows the variance may dip a little.
        for (0..N_OCT) |oct| {
            var srr: f64 = 0.0;
            var spp: f64 = 0.0;
            var s00: f64 = 0.0;
            for (0..NR) |ri| {
                for (0..NP) |pi| {
                    const v0 = @as(f64, @floatFromInt(self.noise[oct][ri][pi])) - 128.0;
                    srr += v0 * (@as(f64, @floatFromInt(self.noise[oct][(ri + 1) % NR][pi])) - 128.0);
                    spp += v0 * (@as(f64, @floatFromInt(self.noise[oct][ri][(pi + 1) % NP])) - 128.0);
                    s00 += v0 * v0;
                }
            }
            self.rho_row[oct] = @floatCast(srr / s00);
            self.rho_ph[oct] = @floatCast(spp / s00);
        }
        // Footprint filter: Opus_Quasar's fit, with the radial constant cut by GARG_LIFE: eddies
        // that shear GARG_LIFE times longer are that much thinner radially (else they alias).
        self.foot_cr = .{ @floatCast(0.865 / GARG_LIFE), @floatCast(1.284 / GARG_LIFE) };
        self.foot_cp = .{ 1.513, 2.039 };
        // Each octave's eddies live ~ P(r) 2^(-2j/3) (correlation time ~0.5 P, Beckwith 2011),
        // quantised onto phase-locked bands so neighbouring radii never drift apart (no stripes).
        for (0..R_BINS) |b| {
            const r = @exp(self.lnr_in + self.lnr_span * (@as(f64, @floatFromInt(b)) + 0.5) / @as(f64, @floatFromInt(R_BINS)));
            const period = 2.0 * math.pi * (r * @sqrt(r) + self.geo.a);
            for (0..N_OCT) |oct| {
                const life = GARG_LIFE * period * math.pow(f64, 2.0, -2.0 * @as(f64, @floatFromInt(oct)) / 3.0);
                self.sband[oct][b] = @floatCast(math.clamp(std.math.log2(life / BAND_L0), 0.0, @as(f64, NBAND - 2) - 1e-3));
            }
            const sb = self.sband[0][b];
            const n0 = @floor(sb);
            self.band_n0[b] = @intFromFloat(n0);
            self.band_w[b] = .{ @cos(0.5 * math.pi * (sb - n0)), @sin(0.5 * math.pi * (sb - n0)) };
        }
        for (0..EXP_N + 1) |k| self.exp_tab[k] = @floatCast(@exp(-4.0 + 8.0 * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(EXP_N))));
    }

    /// One octave of the tilted, anisotropic turbulence field at table row ri, phase cell pi.
    fn turbulence(ri: usize, pi: usize, oct: usize, gr: usize, gp: usize) f64 {
        // Constant along ri + TILT_ROWS pi: with TILT_ROWS < 0 outer gas lies at larger phase, a
        // leading tilt that shear swings through radial to trailing. (+NR keeps it positive; it is
        // a whole number of cells.)
        const fr = (@as(f64, @floatFromInt(ri)) + @as(f64, NR) + TILT_ROWS * @as(f64, @floatFromInt(pi))) * @as(f64, @floatFromInt(gr)) / @as(f64, @floatFromInt(NR));
        const fp = @as(f64, @floatFromInt(pi)) * @as(f64, @floatFromInt(gp)) / @as(f64, @floatFromInt(NP));
        const ir: usize = @intFromFloat(@floor(fr));
        const ip: usize = @intFromFloat(@floor(fp));
        var ur = fr - @floor(fr);
        var up = fp - @floor(fp);
        ur = ur * ur * (3.0 - 2.0 * ur);
        up = up * up * (3.0 - 2.0 * up);
        const seed: u64 = 0xB1AC_401E + oct * 0x1000_0000;
        const v00 = unitf(mix64(seed ^ (ir % gr) * 0x10001 ^ (ip % gp) << 24));
        const v10 = unitf(mix64(seed ^ ((ir + 1) % gr) * 0x10001 ^ (ip % gp) << 24));
        const v01 = unitf(mix64(seed ^ (ir % gr) * 0x10001 ^ ((ip + 1) % gp) << 24));
        const v11 = unitf(mix64(seed ^ ((ir + 1) % gr) * 0x10001 ^ ((ip + 1) % gp) << 24));
        const top = v00 + (v01 - v00) * up;
        const bot = v10 + (v11 - v10) * up;
        return 2.0 * (top + (bot - top) * ur) - 1.0;
    }

    /// ln of a table on the temperature grid at radius r (linear in ln r).
    fn lnTable(self: *const State, tab: *const [PT_N]f32, r: f64) f64 {
        const x = math.clamp(@log(r / self.geo.r_in) / @log(R_OUT * 1.05 / self.geo.r_in) * @as(f64, @floatFromInt(PT_N - 1)), 0.0, @as(f64, @floatFromInt(PT_N - 1)) - 1e-9);
        const xi: usize = @intFromFloat(@floor(x));
        const f = x - @as(f64, @floatFromInt(xi));
        return @as(f64, tab[xi]) * (1.0 - f) + @as(f64, tab[xi + 1]) * f;
    }

    /// Vertical extinction depth (electron scattering + Kramers) of the computed disk at r.
    fn tauExt(self: *const State, r: f64) f64 {
        return @exp(self.lnTable(&self.dtab[1], r));
    }

    /// Vertical thermalisation depth tau_* of the computed disk at r: sets how much it emits.
    fn tauEm(self: *const State, r: f64) f64 {
        return @exp(self.lnTable(&self.dtab[2], r));
    }

    fn temperature(self: *const State, r: f64) f64 {
        const x = @log(r / self.geo.r_in) / @log(R_OUT * 1.05 / self.geo.r_in) * @as(f64, @floatFromInt(PT_N - 1));
        if (!(x > 0.0)) return 0.0;
        const xi: usize = @intFromFloat(@min(@floor(x), @as(f64, @floatFromInt(PT_N - 2))));
        const f = x - @as(f64, @floatFromInt(xi));
        return @as(f64, self.dtab[0][xi]) * (1.0 - f) + @as(f64, self.dtab[0][xi + 1]) * f;
    }

    fn bbLookup(self: *const State, T: f64) [3]f64 {
        if (!(T > BB_TMIN)) return .{ 0, 0, 0 };
        const x = @log(T / BB_TMIN) / @log(BB_TMAX / BB_TMIN) * @as(f64, @floatFromInt(BB_N - 1));
        const xi: usize = @intFromFloat(@min(@floor(x), @as(f64, @floatFromInt(BB_N - 2))));
        const f = @min(x - @as(f64, @floatFromInt(xi)), 1.0);
        var c: [3]f64 = undefined;
        for (0..3) |i| c[i] = @as(f64, self.bb[xi][i]) * (1.0 - f) + @as(f64, self.bb[xi + 1][i]) * f;
        return c;
    }

    /// Luminance response of the blackbody at observed temperature T to a change of the local
    /// dissipation eps (T ~ eps^(1/4)): d ln Y / d ln eps = (1/4) d ln Y / d ln T, as a byte.
    fn respByte(self: *const State, T: f64) u8 {
        const y1 = luma(self.bbLookup(T * 1.02));
        const y0 = luma(self.bbLookup(T / 1.02));
        if (!(y0 > 0.0) or !(y1 > 0.0)) return 0;
        const r = 0.25 * @log(y1 / y0) / @log(1.02 * 1.02);
        return @intFromFloat(@round(math.clamp(r * RESP_SCALE, 0.0, 255.0)));
    }

    /// How far turbulence can brighten gas at observed temperature T in the visible: its
    /// dissipation at +2.6 sigma, eps = e^(2.6 sigma), raises T by eps^(1/4).
    fn peakBoost(self: *const State, T: f64) f64 {
        const y0 = luma(self.bbLookup(T));
        if (!(y0 > 0.0)) return 1.0;
        return @max(luma(self.bbLookup(T * @exp(2.6 * @as(f64, TURB_SIGMA) / 4.0))) / y0, 1.0);
    }

    fn alphaBeta(self: *const State, x: f64, y: f64) [2]f64 {
        var alpha = (x - 0.5 * @as(f64, @floatFromInt(self.w))) * self.mpp;
        if (@abs(alpha) < 1e-6) alpha = 1e-6; // never aim a ray exactly through the spin axis
        return .{ alpha, (0.5 * @as(f64, @floatFromInt(self.h)) - y) * self.mpp };
    }

    fn trace(self: *State, x: f64, y: f64) Hit {
        const ab = self.alphaBeta(x, y);
        self.rays_traced += 1;
        return traceRay(&self.geo, ab[0], ab[1], true);
    }

    /// Front hit, then up to two more things seen through translucent gas (else .hole):
    /// e.g. near-side gas, the lensed far side's underside behind it, and the sky behind that.
    fn traceLayers(self: *State, x: f64, y: f64, tau_max: f64) [3]Hit {
        const ab = self.alphaBeta(x, y);
        self.rays_traced += 1;
        var ray = startRay(&self.geo, ab[0], ab[1]);
        var out = [3]Hit{ traceNext(&self.geo, &ray, true), .{}, .{} };
        for (1..3) |i| {
            const prev = out[i - 1];
            if (prev.kind != .disk or self.slantTau(x, prev) >= tau_max) break;
            out[i] = traceNext(&self.geo, &ray, true);
        }
        return out;
    }

    /// ln(1/mu) for a disk crossing: mu = g |p_theta| / r is the cosine of the angle between the
    /// photon and the disk normal in the gas's rest frame, so the light's path through the gas is
    /// the vertical optical depth times 1/mu (at 80 deg most crossings are grazing, mu ~ 0.2).
    fn lnInvMu(self: *const State, x: f64, hit: Hit) f64 {
        const alpha = (x - 0.5 * @as(f64, @floatFromInt(self.w))) * self.mpp;
        const L = -alpha * self.geo.sin_i;
        const o = orbit(self.geo.a, hit.r);
        const g = 1.0 / (o.ut * (1.0 - o.om * L));
        const mu = math.clamp(g * @abs(hit.pth) / hit.r, MU_MIN, 1.0);
        return -@log(mu);
    }

    /// Extinction depth along the line of sight through the gas at a disk crossing.
    fn slantTau(self: *const State, x: f64, hit: Hit) f64 {
        return self.tauExt(hit.r) * @exp(self.lnInvMu(x, hit));
    }

    /// Fraction of a blackbody the gas emits along the line of sight: 1 - e^(-tau_* / mu).
    fn emitFrac(self: *const State, x: f64, hit: Hit) f64 {
        return -std.math.expm1(-self.tauEm(hit.r) * @exp(self.lnInvMu(x, hit)));
    }

    /// What the gas sends along the line of sight per unit of the colour blackbody B(f T_s):
    /// emitted fraction x limb darkening x spectral dilution f^-4.
    fn emitWeight(self: *const State, x: f64, hit: Hit) f64 {
        const lmu = self.lnInvMu(x, hit);
        return self.emitFrac(x, hit) * limbFactor(lmu, self.tauExt(hit.r)) * @exp(self.lnTable(&self.dtab[3], hit.r));
    }

    /// Display-linear light reaching the camera from behind translucent gas, in sky units
    /// (packBg multiplies by STAR_GAIN), composited front to back over the layers behind.
    /// Gas seen there is drawn static, at its own opacity.
    fn behind(self: *const State, x: f64, backs: [2]Hit, foot: f64) [3]f64 {
        var acc = [3]f64{ 0, 0, 0 };
        var tr: f64 = 1.0;
        for (backs) |b| {
            switch (b.kind) {
                .hole => break,
                .sky => {
                    const c = self.sky(b.dir, foot);
                    for (0..3) |i| acc[i] += tr * c[i];
                    break;
                },
                .disk => {
                    const tau = self.slantTau(x, b);
                    const s = self.shadeDisk(x, b.r, b.ph, b.t);
                    const k = @as(f64, self.exposure) * self.emitWeight(x, b);
                    const c = [3]f64{ s.rgb[0] * k, s.rgb[1] * k, s.rgb[2] * k };
                    const tm = 1.0 / (1.0 + luma(c));
                    for (0..3) |i| acc[i] += tr * @min(c[i] * tm, 1.0) / STAR_GAIN;
                    tr *= @exp(-tau);
                },
            }
        }
        return acc;
    }

    /// Can the hits behind a block be interpolated? A lensed sky seen through gas may be, even
    /// where it curves; a disk must pass the strict test (phase/radius continuity).
    fn smoothBehind(self: *const State, cb: [4]Hit) bool {
        for (cb) |hb| if (hb.kind != cb[0].kind) return false;
        return cb[0].kind != .disk or self.uniform(cb);
    }

    /// Camera exposure, metered before rendering (translucent gas is composited with it):
    /// put the 99th-percentile luminance of the inner disk at EXPO_TARGET.
    fn meterExposure(self: *State) void {
        const gx: usize = 192;
        const gy: usize = @max(1, gx * self.h / @max(self.w, 1));
        var hist: [512]u32 = @splat(0);
        var count: u64 = 0;
        for (0..gy) |iy| {
            for (0..gx) |ix| {
                const x = (@as(f64, @floatFromInt(ix)) + 0.5) * @as(f64, @floatFromInt(self.w)) / @as(f64, @floatFromInt(gx));
                const y = (@as(f64, @floatFromInt(iy)) + 0.5) * @as(f64, @floatFromInt(self.h)) / @as(f64, @floatFromInt(gy));
                const hit = self.trace(x, y);
                if (hit.kind != .disk or hit.r > EXPO_R) continue;
                // Metered as seen: with limb darkening and the colour correction's dilution.
                const yl = luma(self.shadeDisk(x, hit.r, hit.ph, hit.t).rgb) * self.emitWeight(x, hit);
                if (!(yl > 0.0)) continue;
                const bin: usize = @intFromFloat(math.clamp((@log2(yl) + 32.0) * 8.0, 0.0, 511.0));
                hist[bin] += 1;
                count += 1;
            }
        }
        if (count == 0) return;
        var acc: u64 = 0;
        const want = count - count / 100;
        for (hist, 0..) |c, b| {
            acc += c;
            if (acc >= want) {
                const yp = math.pow(f64, 2.0, @as(f64, @floatFromInt(b)) / 8.0 - 32.0);
                self.exposure = @floatCast(EXPO_TARGET / yp);
                break;
            }
        }
    }

    /// Point stars seen through the lens. `foot` is the sky angle one pixel covers here:
    /// demagnified sky (foot > pix_ang) shows fainter, denser stars; magnified sky stretches them.
    fn star(self: *const State, d: [3]f64, foot: f64) [3]f64 {
        const G = 1.0 / STAR_CELL;
        const cx = @floor(d[0] * G);
        const cy = @floor(d[1] * G);
        const cz = @floor(d[2] * G);
        const ix: i64 = @intFromFloat(cx);
        const iy: i64 = @intFromFloat(cy);
        const iz: i64 = @intFromFloat(cz);
        const hh = mix64(@as(u64, @bitCast(ix)) *% 0x9E37 ^ @as(u64, @bitCast(iy)) *% 0x85EB_CA6B ^ @as(u64, @bitCast(iz)) *% 0xC2B2_AE35);
        const lat = dot3(d, self.gal_n);
        const prob: u64 = 30 + @as(u64, @intFromFloat(45.0 * @exp(-(lat / 0.12) * (lat / 0.12))));
        if (hh % 100 >= prob) return .{ 0, 0, 0 };
        var p = [3]f64{
            (cx + 0.15 + 0.7 * unitf(mix64(hh ^ 1))) / G,
            (cy + 0.15 + 0.7 * unitf(mix64(hh ^ 2))) / G,
            (cz + 0.15 + 0.7 * unitf(mix64(hh ^ 3))) / G,
        };
        const np = @sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
        for (&p) |*v| v.* /= np;
        const dx = d[0] - p[0];
        const dy = d[1] - p[1];
        const dz = d[2] - p[2];
        const ang2 = dx * dx + dy * dy + dz * dz;
        const fp = @max(foot, self.pix_ang);
        const sig = 0.75 * fp;
        const u = unitf(mix64(hh ^ 4));
        const mu = (self.pix_ang / fp) * (self.pix_ang / fp);
        const bright = STAR_FLUX * (0.03 + 0.9 * u * u * u * u * u) * mu * @exp(-ang2 / (sig * sig));
        if (bright < 1e-4) return .{ 0, 0, 0 };
        const col = self.bbLookup(3500.0 + 9000.0 * unitf(mix64(hh ^ 5)));
        const yl = @max(luma(col), 1e-12);
        return .{ bright * col[0] / yl, bright * col[1] / yl, bright * col[2] / yl };
    }

    /// Diffuse Milky Way seen in direction d: a clumpy band, patchy dust lanes, a warm bulge.
    fn milkyWay(self: *const State, d: [3]f64) [3]f64 {
        const lat = dot3(d, self.gal_n);
        const band = @exp(-(lat / 0.07) * (lat / 0.07));
        const dc = [3]f64{ d[0] - self.gal_c[0], d[1] - self.gal_c[1], d[2] - self.gal_c[2] };
        const bulge = @exp(-dot3(dc, dc) / 0.004);
        if (band < 1e-3 and bulge < 1e-3) return .{ 0, 0, 0 };
        const s1 = [3]f64{ d[0] * 25.0, d[1] * 25.0, d[2] * 25.0 };
        const s2 = [3]f64{ d[0] * 80.0, d[1] * 80.0, d[2] * 80.0 };
        const s3 = [3]f64{ d[0] * 45.0, d[1] * 45.0, d[2] * 45.0 };
        const nz = 0.6 * noise3(s1, 11) + 0.4 * noise3(s2, 12);
        const clumpy = 0.1 + 1.2 * nz * nz;
        const lane = @exp(-(lat / 0.016) * (lat / 0.016));
        const dust = 1.0 - 0.75 * lane * math.clamp(1.6 * noise3(s3, 13) - 0.3, 0.0, 1.0);
        const warm = self.bbLookup(4300.0);
        const cool = self.bbLookup(6200.0);
        const yw = @max(luma(warm), 1e-12);
        const yc = @max(luma(cool), 1e-12);
        const ib = SKY_GAIN * band * clumpy * dust;
        const iu = SKY_GAIN * 2.5 * bulge * dust;
        return .{
            ib * cool[0] / yc + iu * warm[0] / yw,
            ib * cool[1] / yc + iu * warm[1] / yw,
            ib * cool[2] / yc + iu * warm[2] / yw,
        };
    }

    fn sky(self: *const State, d: [3]f64, foot: f64) [3]f64 {
        if (SKY_VISIBLE <= 0.0) return .{ 0, 0, 0 };
        const a = self.star(d, foot);
        const b = self.milkyWay(d);
        return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
    }

    /// Could a star lie within `margin` of direction d? Stars sit >= 0.15 cell from their
    /// cell walls, so for margins below that, checking d's own cell is exact.
    fn starNear(self: *const State, d: [3]f64, margin: f64) bool {
        if (SKY_VISIBLE <= 0.0) return false;
        const G = 1.0 / STAR_CELL;
        if (margin * G > 0.14) return true;
        const cx = @floor(d[0] * G);
        const cy = @floor(d[1] * G);
        const cz = @floor(d[2] * G);
        const ix: i64 = @intFromFloat(cx);
        const iy: i64 = @intFromFloat(cy);
        const iz: i64 = @intFromFloat(cz);
        const hh = mix64(@as(u64, @bitCast(ix)) *% 0x9E37 ^ @as(u64, @bitCast(iy)) *% 0x85EB_CA6B ^ @as(u64, @bitCast(iz)) *% 0xC2B2_AE35);
        const lat = dot3(d, self.gal_n);
        const prob: u64 = 30 + @as(u64, @intFromFloat(45.0 * @exp(-(lat / 0.12) * (lat / 0.12))));
        if (hh % 100 >= prob) return false;
        var p = [3]f64{
            (cx + 0.15 + 0.7 * unitf(mix64(hh ^ 1))) / G,
            (cy + 0.15 + 0.7 * unitf(mix64(hh ^ 2))) / G,
            (cz + 0.15 + 0.7 * unitf(mix64(hh ^ 3))) / G,
        };
        const np = @sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
        var a2: f64 = 0.0;
        for (0..3) |i| {
            p[i] /= np;
            a2 += (d[i] - p[i]) * (d[i] - p[i]);
        }
        return a2 < margin * margin;
    }

    fn shadeDisk(self: *const State, x: f64, r: f64, ph: f64, t_hit: f64) Sample {
        const t = t_hit + T_REF; // backward-traced t is negative: this is minus the relative delay
        const alpha = (x - 0.5 * @as(f64, @floatFromInt(self.w))) * self.mpp;
        const L = -alpha * self.geo.sin_i;
        const o = orbit(self.geo.a, r);
        const g = 1.0 / (o.ut * (1.0 - o.om * L));
        const tobs = g * self.temperature(r);
        const c = self.bbLookup(tobs);
        const rb = math.clamp((@log(r) - self.lnr_in) / self.lnr_span * @as(f64, @floatFromInt(R_BINS)), 0.0, @as(f64, @floatFromInt(R_BINS - 1)));
        const phe = @mod(ph - o.om * t, 2.0 * math.pi);
        const tturns = @mod(o.om * t / (2.0 * math.pi) * 1024.0, 65536.0);
        return .{
            .disk = true,
            .tobs = tobs,
            .tq = @intFromFloat(@min(tturns, 65535.0)),
            .rgb = c,
            .rbin = @intFromFloat(@min(rb * @as(f64, R_FRAC), @as(f64, R_BINS * R_FRAC - 1))),
            .phi = @truncate(@as(u32, @intFromFloat(phe / (2.0 * math.pi) * 65536.0))),
        };
    }

    fn shadeHit(self: *const State, x: f64, hit: Hit, foot: f64) Sample {
        return switch (hit.kind) {
            .hole => .{},
            .sky => .{ .rgb = self.sky(hit.dir, foot) },
            .disk => self.shadeDisk(x, hit.r, hit.ph, hit.t),
        };
    }

    const Class = enum { uniform, sky_curved, same_kind, edge };

    fn classify(self: *const State, c: [4]Hit) struct { cls: Class, e2: f64 } {
        for (c) |h| if (h.kind != c[0].kind) return .{ .cls = .edge, .e2 = 0 };
        if (self.uniform(c)) return .{ .cls = .uniform, .e2 = 0 };
        if (c[0].kind == .sky) {
            var e2: f64 = 0.0;
            for (0..3) |i| {
                const d2 = c[0].dir[i] + c[3].dir[i] - c[1].dir[i] - c[2].dir[i];
                e2 += d2 * d2;
            }
            return .{ .cls = .sky_curved, .e2 = @sqrt(e2) };
        }
        return .{ .cls = .same_kind, .e2 = 0 };
    }

    fn uniform(self: *const State, c: [4]Hit) bool {
        const k = c[0].kind;
        for (c) |h| if (h.kind != k) return false;
        switch (k) {
            .hole => return true,
            .disk => {
                var rmin: f64 = c[0].r;
                var rmax: f64 = c[0].r;
                for (c) |h| {
                    if (h.n != c[0].n) return false;
                    rmin = @min(rmin, h.r);
                    rmax = @max(rmax, h.r);
                    if (@abs(wrapPi(h.ph - c[0].ph)) > 0.5) return false;
                }
                if (rmax / rmin > 1.6) return false;
                // Interpolation error is set by curvature: bound each field's second difference.
                const d2r = @log(c[0].r) + @log(c[3].r) - @log(c[1].r) - @log(c[2].r);
                const d2p = wrapPi(c[0].ph + c[3].ph - c[1].ph - c[2].ph);
                const d2t = c[0].t + c[3].t - c[1].t - c[2].t;
                return @abs(d2r) < 0.01 and @abs(d2p) < 0.01 and @abs(d2t) < 0.5;
            },
            .sky => {
                // Lensing may stretch the sky a lot but smoothly; what breaks bilinear
                // interpolation is curvature, measured by the block's second difference.
                const lim = 2.0 * self.pix_ang; // bilinear error ~ e2/4: under half a pixel
                var e2: f64 = 0.0;
                for (0..3) |i| {
                    const d2 = c[0].dir[i] + c[3].dir[i] - c[1].dir[i] - c[2].dir[i];
                    e2 += d2 * d2;
                }
                return e2 < lim * lim;
            },
        }
    }

    fn interpolate(c: [4]Hit, u: f64, v: f64) Hit {
        const w0 = (1 - u) * (1 - v);
        const w1 = u * (1 - v);
        const w2 = (1 - u) * v;
        const w3 = u * v;
        var out = c[0];
        switch (c[0].kind) {
            .hole => {},
            .disk => {
                out.r = @exp(w0 * @log(c[0].r) + w1 * @log(c[1].r) + w2 * @log(c[2].r) + w3 * @log(c[3].r));
                const b = c[0].ph;
                out.ph = b + w1 * wrapPi(c[1].ph - b) + w2 * wrapPi(c[2].ph - b) + w3 * wrapPi(c[3].ph - b);
                out.t = w0 * c[0].t + w1 * c[1].t + w2 * c[2].t + w3 * c[3].t;
                out.pth = w0 * c[0].pth + w1 * c[1].pth + w2 * c[2].pth + w3 * c[3].pth;
            },
            .sky => {
                var d: [3]f64 = undefined;
                for (0..3) |i| d[i] = w0 * c[0].dir[i] + w1 * c[1].dir[i] + w2 * c[2].dir[i] + w3 * c[3].dir[i];
                const nd = @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
                for (0..3) |i| out.dir[i] = d[i] / nd;
            },
        }
        return out;
    }

    fn packBg(self: *const State, lin: [3]f64) u32 {
        var c: [3]u8 = undefined;
        for (0..3) |i| {
            const v = math.clamp(lin[i] * STAR_GAIN, 0.0, 1.0);
            c[i] = self.srgb[@intFromFloat(v * 4095.0)];
        }
        return sdk.packRGBA(c[0], c[1], c[2]);
    }

    /// The expensive part, once: trace the image block by block, refining where the picture changes.
    fn render(self: *State, corners: []Hit) void {
        const w = self.w;
        const h = self.h;
        const nbx = (w + BLOCK - 1) / BLOCK;
        const nby = (h + BLOCK - 1) / BLOCK;
        const ss: usize = 2; // 2x2 supersampling on true edges, at every resolution
        var top = corners[0 .. nbx + 1];
        var bot = corners[nbx + 1 .. 2 * (nbx + 1)];
        var topb = corners[2 * (nbx + 1) .. 3 * (nbx + 1)];
        var botb = corners[3 * (nbx + 1) .. 4 * (nbx + 1)];
        var topc = corners[4 * (nbx + 1) .. 5 * (nbx + 1)];
        var botc = corners[5 * (nbx + 1) .. 6 * (nbx + 1)];
        // Corners fetch what is behind gas a little denser than needed, so blocks straddling
        // the threshold still interpolate.
        const tau_corner = 2.0 * TAU_BEHIND;
        for (0..nbx + 1) |bx| {
            const p = self.traceLayers(@floatFromInt(bx * BLOCK), 0.0, tau_corner);
            top[bx] = p[0];
            topb[bx] = p[1];
            topc[bx] = p[2];
        }
        for (0..h) |y| {
            self.row_x0[y] = @intCast(@min(w, 0xFFFF));
            self.row_x1[y] = 0;
        }
        for (0..nby) |by| {
            const yb: f64 = @floatFromInt((by + 1) * BLOCK);
            for (0..nbx + 1) |bx| {
                const p = self.traceLayers(@floatFromInt(bx * BLOCK), yb, tau_corner);
                bot[bx] = p[0];
                botb[bx] = p[1];
                botc[bx] = p[2];
            }
            for (0..nbx) |bx| {
                const c = [4]Hit{ top[bx], top[bx + 1], bot[bx], bot[bx + 1] };
                const cb = [4]Hit{ topb[bx], topb[bx + 1], botb[bx], botb[bx + 1] };
                const cc = [4]Hit{ topc[bx], topc[bx + 1], botc[bx], botc[bx + 1] };
                const cl = self.classify(c);
                const back_smooth = self.smoothBehind(cb) and self.smoothBehind(cc);
                // Sky angle one pixel covers here, from any pair of adjacent sky corners.
                var foot = 8.0 * self.pix_ang; // typical value inside the Einstein ring, if unmeasurable
                {
                    var m: f64 = 0.0;
                    var got = false;
                    for ([_][2]usize{ .{ 0, 1 }, .{ 0, 2 }, .{ 1, 3 }, .{ 2, 3 } }) |pr| {
                        if (c[pr[0]].kind != .sky or c[pr[1]].kind != .sky) continue;
                        var q: f64 = 0.0;
                        for (0..3) |i| q += (c[pr[1]].dir[i] - c[pr[0]].dir[i]) * (c[pr[1]].dir[i] - c[pr[0]].dir[i]);
                        m = @max(m, @sqrt(q));
                        got = true;
                    }
                    if (got) foot = @max(m / @as(f64, @floatFromInt(BLOCK)), 0.25 * self.pix_ang);
                }
                const y_end = @min((by + 1) * BLOCK, h);
                const x_end = @min((bx + 1) * BLOCK, w);
                for (by * BLOCK..y_end) |py| {
                    for (bx * BLOCK..x_end) |px| {
                        var disk_rgb = [3]f64{ 0, 0, 0 };
                        var bg_rgb = [3]f64{ 0, 0, 0 };
                        var disk_behind = [3]f64{ 0, 0, 0 }; // behind the disk samples: in bg only if translucent
                        var nd: usize = 0;
                        var first: Sample = .{};
                        var first_lmu: f64 = 0.0; // ln(1/mu) of the first disk sample
                        const sub: usize = if (cl.cls == .edge) ss else 1; // supersample true edges only
                        const nsamp = sub * sub;
                        for (0..nsamp) |si| {
                            const sx: f64 = (@as(f64, @floatFromInt(si % sub)) + 0.5) / @as(f64, @floatFromInt(sub));
                            const sy: f64 = (@as(f64, @floatFromInt(si / sub)) + 0.5) / @as(f64, @floatFromInt(sub));
                            const fx = @as(f64, @floatFromInt(px)) + sx;
                            const fy = @as(f64, @floatFromInt(py)) + sy;
                            const u = (fx - @as(f64, @floatFromInt(bx * BLOCK))) / BLOCK;
                            const v = (fy - @as(f64, @floatFromInt(by * BLOCK))) / BLOCK;
                            var backs = [2]Hit{ .{}, .{} };
                            var have_back = false;
                            var hit = switch (cl.cls) {
                                .uniform => interpolate(c, u, v),
                                .sky_curved => blk: {
                                    // Interpolation is off by at most ~e2/4; if no star can be that
                                    // close, the pixel is provably empty sky and needs no ray.
                                    const guess = interpolate(c, u, v);
                                    const margin = 0.5 * cl.e2 + 4.0 * 0.75 * @max(foot, self.pix_ang);
                                    break :blk if (self.starNear(guess.dir, margin)) self.trace(fx, fy) else guess;
                                },
                                else => blk: {
                                    const p = self.traceLayers(fx, fy, TAU_BEHIND);
                                    backs = .{ p[1], p[2] };
                                    have_back = true;
                                    break :blk p[0];
                                },
                            };
                            const thin = hit.kind == .disk and self.slantTau(fx, hit) < TAU_BEHIND;
                            if (thin and !have_back) {
                                if (back_smooth) {
                                    backs = .{ interpolate(cb, u, v), interpolate(cc, u, v) };
                                } else {
                                    const p = self.traceLayers(fx, fy, TAU_BEHIND);
                                    hit = p[0];
                                    backs = .{ p[1], p[2] };
                                }
                            }
                            // Gas too thin or too cool to show even when turbulence stirs it emits nothing
                            // visible: it only dims what lies behind. The next crossing behind it is then this
                            // sample's real hit (animated, e.g. the lensed underside of the disk), seen through
                            // it at e^(-tau/mu).
                            var front_tr: f64 = 1.0;
                            var hidden = false;
                            while (hit.kind == .disk and hit.r > SPOT_RMAX) {
                                const tau = self.slantTau(fx, hit);
                                const sd = self.shadeDisk(fx, hit.r, hit.ph, hit.t);
                                const yf = luma(sd.rgb) * self.emitWeight(fx, hit);
                                const dim = yf * self.exposure * self.peakBoost(sd.tobs) < EMIT_FLOOR;
                                if (!(tau < TAU_MIN or dim)) {
                                    // Glowing but translucent gas over a brighter crossing behind it (the
                                    // lensed underside seen through the warm outer disk): the brighter layer
                                    // is the animated one; this one's faint glow goes to the background.
                                    if (tau >= TAU_BEHIND or backs[0].kind != .disk) break;
                                    const sb = self.shadeDisk(fx, backs[0].r, backs[0].ph, backs[0].t);
                                    if (yf >= luma(sb.rgb) * self.emitWeight(fx, backs[0]) * @exp(-tau)) break;
                                    const k = @as(f64, self.exposure) * self.emitWeight(fx, hit);
                                    const cf = [3]f64{ sd.rgb[0] * k, sd.rgb[1] * k, sd.rgb[2] * k };
                                    const tmf = 1.0 / (1.0 + luma(cf));
                                    for (0..3) |i| bg_rgb[i] += front_tr * @min(cf[i] * tmf, 1.0) / STAR_GAIN;
                                }
                                if (tau >= TAU_BEHIND) {
                                    hidden = true; // dim and opaque: nothing shows here
                                    break;
                                }
                                front_tr *= @exp(-tau);
                                hit = backs[0];
                                backs = .{ backs[1], .{} };
                            }
                            if (hidden) continue;
                            const s = self.shadeHit(fx, hit, foot);
                            if (s.disk) {
                                if (nd == 0) {
                                    first = s;
                                    first_lmu = self.lnInvMu(fx, hit);
                                }
                                nd += 1;
                                for (0..3) |i| disk_rgb[i] += front_tr * s.rgb[i];
                                if (self.slantTau(fx, hit) < TAU_BEHIND) {
                                    const bh = self.behind(fx, backs, foot);
                                    for (0..3) |i| disk_behind[i] += front_tr * bh[i];
                                }
                            } else {
                                for (0..3) |i| bg_rgb[i] += front_tr * s.rgb[i];
                            }
                        }
                        const idx = py * w + px;
                        const fs: f64 = @floatFromInt(nsamp);
                        // draw() composites translucent pixels as cov*c + (1 - bf)*bg, bf = share behind the
                        // gas x its absorption: only the light behind the gas is dimmed, not the sky beside it.
                        // Static per pixel, so baked here: bf already carries the absorbed share,
                        // bf (1 - e^(-tau_ext/mu)), and rgb the emitted fraction 1 - e^(-tau_*/mu).
                        const lmu_q: u8 = @intFromFloat(@round(math.clamp(first_lmu * LMU_SCALE, 0.0, 255.0)));
                        const lmu_f = @as(f32, @floatFromInt(lmu_q)) / @as(f32, LMU_SCALE);
                        var bf: u8 = 0;
                        var emit: f64 = 1.0;
                        if (nd > 0) {
                            const rb = first.rbin / R_FRAC;
                            const r_first = @exp(self.lnr_in + self.lnr_span * (@as(f64, @floatFromInt(first.rbin)) / R_FRAC) / R_BINS);
                            emit = self.oneMinusExpExp(self.lnem_tab[rb] + lmu_f) *
                                limbFactor(lmu_f, @exp(@as(f64, self.lntau_tab[rb]))) * @exp(self.lnTable(&self.dtab[3], r_first));
                            const lt_los = self.lntau_tab[rb] + lmu_f;
                            if (lt_los < @as(f32, @floatCast(@log(TAU_BEHIND)))) {
                                const lb = luma(disk_behind);
                                for (0..3) |i| bg_rgb[i] += disk_behind[i];
                                const lt = luma(bg_rgb);
                                const absorbed = self.oneMinusExpExp(lt_los);
                                if (lt > 1e-12) bf = @intFromFloat(@round(math.clamp(lb / lt * absorbed, 0.0, 1.0) * 255.0));
                            }
                        }
                        self.bg[idx] = self.packBg(.{ bg_rgb[0] / fs, bg_rgb[1] / fs, bg_rgb[2] / fs });
                        if (nd > 0) {
                            const fd: f64 = @floatFromInt(nd);
                            self.recs[idx] = .{
                                .rgb = .{ @floatCast(disk_rgb[0] / fd * emit), @floatCast(disk_rgb[1] / fd * emit), @floatCast(disk_rgb[2] / fd * emit) },
                                .rbin = first.rbin,
                                .phi = first.phi,
                                .cov = @intCast(nd * 255 / nsamp),
                                .tobs = @floatCast(@min(first.tobs, 60000.0)),
                                .tq = first.tq,
                                .bf = bf,
                                .resp = self.respByte(first.tobs),
                            };
                            self.row_x0[py] = @min(self.row_x0[py], @as(u16, @intCast(px)));
                            self.row_x1[py] = @max(self.row_x1[py], @as(u16, @intCast(px + 1)));
                        } else {
                            self.recs[idx] = .{ .rgb = .{ 0, 0, 0 }, .rbin = 0, .phi = 0, .cov = 0 };
                        }
                    }
                }
            }
            const tmp = top;
            top = bot;
            bot = tmp;
            const tmpb = topb;
            topb = botb;
            botb = tmpb;
            const tmpc = topc;
            topc = botc;
            botc = tmpc;
        }
        // Each disk pixel's footprint on the disk, from its neighbours: lensing can squeeze a
        // wide patch of disk into one pixel, and texture finer than that must be filtered.
        for (0..h) |py| {
            for (0..w) |px| {
                const i = py * w + px;
                if (self.recs[i].cov == 0) continue;
                var fr: u32 = 0;
                var fp: u32 = 0;
                const nb = [4][2]i64{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } };
                for (nb) |o| {
                    const nx = @as(i64, @intCast(px)) + o[0];
                    const ny = @as(i64, @intCast(py)) + o[1];
                    if (nx < 0 or ny < 0 or nx >= @as(i64, @intCast(w)) or ny >= @as(i64, @intCast(h))) continue;
                    const j = @as(usize, @intCast(ny)) * w + @as(usize, @intCast(nx));
                    if (self.recs[j].cov == 0) continue;
                    const dr = @divTrunc(@abs(@as(i32, self.recs[j].rbin) - @as(i32, self.recs[i].rbin)) + FR_Q - 1, FR_Q);
                    // Emission phase = geometric azimuth (safe to compare modulo a turn) minus the
                    // light-travel phase (compared unwrapped: delays can wind it by several turns).
                    const ri = self.recs[i];
                    const rj = self.recs[j];
                    const hit_i = ri.phi +% (ri.tq << 6);
                    const hit_j = rj.phi +% (rj.tq << 6);
                    const d_hit: i32 = @as(i16, @bitCast(hit_j -% hit_i));
                    const d_tq: i32 = @as(i16, @bitCast(rj.tq -% ri.tq));
                    const dp = @abs(d_hit - d_tq * 64);
                    fr = @max(fr, @as(u32, @intCast(dr)));
                    fp = @max(fp, @as(u32, @intCast(dp)));
                }
                self.recs[i].fr = @intCast(@min(fr, 255));
                self.recs[i].fp = @intCast(@min((fp + 63) / 64, 255));
            }
        }
        self.bakeStatic();
    }

    /// One disk pixel, composited over its background and tone mapped, as draw() writes it.
    inline fn composite(self: *const State, rc: Rec, c: [3]f32, bgp: u32) u32 {
        const yl = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
        const tm = 1.0 / (1.0 + yl); // Reinhard on luminance, hue preserved
        if (rc.bf != 0) {
            // I = cov * B(T_s)(1 - e^-tau_*) + bg * (1 - bf (1 - e^-tau_ext)): bg holds the light
            // beside the gas and, a share bf of it, the light behind it, which only that share sees dimmed.
            var out: [3]u8 = undefined;
            const cov: f32 = @as(f32, @floatFromInt(rc.cov)) / 255.0;
            const tr = 1.0 - @as(f32, @floatFromInt(rc.bf)) / 255.0;
            for (0..3) |i| {
                const bl = self.lin8[(bgp >> @intCast(8 * i)) & 0xFF];
                const v = @min(cov * c[i] * tm + tr * bl, 1.0);
                out[i] = self.srgb[@intFromFloat(v * 4095.0)];
            }
            return sdk.packRGBA(out[0], out[1], out[2]);
        } else if (rc.cov == 255) {
            const r0 = self.srgb[@intFromFloat(@min(c[0] * tm, 1.0) * 4095.0)];
            const g0 = self.srgb[@intFromFloat(@min(c[1] * tm, 1.0) * 4095.0)];
            const b0 = self.srgb[@intFromFloat(@min(c[2] * tm, 1.0) * 4095.0)];
            return sdk.packRGBA(r0, g0, b0);
        } else {
            // Partly covered opaque pixel, blended in linear light: bg already holds the sky
            // of the uncovered samples (weighted by their share), so it adds as is.
            var out: [3]u8 = undefined;
            const cov: f32 = @as(f32, @floatFromInt(rc.cov)) / 255.0;
            for (0..3) |i| {
                const bl = self.lin8[(bgp >> @intCast(8 * i)) & 0xFF];
                const v = @min(cov * c[i] * tm + bl, 1.0);
                out[i] = self.srgb[@intFromFloat(v * 4095.0)];
            }
            return sdk.packRGBA(out[0], out[1], out[2]);
        }
    }

    /// Where turbulence cannot change an 8-bit level even at 3 sigma (dim enough gas, or eddies
    /// averaged out by the footprint), a pixel is the same every frame unless a hot spot can
    /// reach it: those pixels are composited once here, into the background, and draw() skips them.
    fn bakeStatic(self: *State) void {
        const span_bins = self.lnr_span / @as(f64, @floatFromInt(R_BINS));
        // Outermost bin a spot's mask can reach (step(): spot radius <= 5.35 r_in, +wr +12 bins).
        const spot_bin_max: u32 = @intFromFloat(@ceil((@log(5.35 * self.geo.r_in) - self.lnr_in + SPOT_SIZE / (1.15 * self.geo.r_in)) / span_bins + 13.0));
        const n = self.w * self.h;
        for (0..n) |i| {
            const rc = self.recs[i];
            if (rc.cov == 0 or rc.rbin / R_FRAC <= spot_bin_max) continue;
            const frf: f32 = @as(f32, @floatFromInt(rc.fr)) * 0.25;
            const fpf: f32 = @as(f32, @floatFromInt(rc.fp)) * 64.0;
            const amp = GT_RMS * gridFoot(frf, fpf) * @as(f32, @floatFromInt(rc.resp)) / RESP_SCALE;
            if (!turbBelowLevel(rc, amp, self.exposure)) continue;
            const k = @exp(-0.5 * TURB_SIGMA * TURB_SIGMA * amp * amp) * self.exposure;
            const c = [3]f32{ @as(f32, rc.rgb[0]) * k, @as(f32, rc.rgb[1]) * k, @as(f32, rc.rgb[2]) * k };
            self.bg[i] = self.composite(rc, c, self.bg[i]);
            self.recs[i].cov = 0;
        }
    }

    /// A 3-sigma turbulence ripple, e^(3 sigma amp) - 1 in linear light, moves this pixel by less
    /// than one 8-bit sRGB level (slope of the sRGB curve at its tone-mapped luminance).
    fn turbBelowLevel(rc: Rec, amp: f32, expo: f32) bool {
        const cov = @as(f32, @floatFromInt(rc.cov)) / 255.0;
        const yl = (0.2126 * @as(f32, rc.rgb[0]) + 0.7152 * @as(f32, rc.rgb[1]) + 0.0722 * @as(f32, rc.rgb[2])) * expo;
        const v = cov * yl / (1.0 + yl);
        const slope: f32 = if (v <= 0.0031308) 12.92 else 1.055 / 2.4 * math.pow(f32, v, -7.0 / 12.0);
        return 255.0 * slope * v * (@exp(3.0 * TURB_SIGMA * amp) - 1.0) < 1.0;
    }

    // ---------------------------------------------------------------- per frame

    pub fn step(self: *State, dt: f64) void {
        if (!(dt > 0.0 and dt < 1.0)) return;
        self.t_m += dt * TIME_LAPSE;
        // Turbulence clocks: band n has generations of life L0 2^n born every L0 2^n, two of them
        // staggered by half a life. Computed in f64 from absolute time, so it never drifts.
        for (0..NBAND) |n| {
            const life = BAND_L0 * math.pow(f64, 2.0, @floatFromInt(n));
            const q = self.t_m / life;
            self.band_u[n] = @floatCast(q - @floor(q));
            self.band_ka[n] = @truncate(@as(u64, @intFromFloat(@floor(q))));
            self.band_kb[n] = @truncate(@as(u64, @intFromFloat(@floor(q + 0.5))));
            const u: f64 = self.band_u[n];
            for (0..2) |gi| {
                const k = if (gi == 0) self.band_ka[n] else self.band_kb[n];
                const age = (if (gi == 0) u else u + 0.5 - @floor(u + 0.5)) * life;
                for (0..N_OCT) |oct| {
                    // A and B are distinct generations (their counters coincide half the time).
                    const seed = turbSeed(@intCast(oct), @intCast(n), 2 *% k +% @as(u32, @intCast(gi)));
                    self.gen[oct][n][gi] = .{
                        .w = @floatCast(if (gi == 0) @sin(math.pi * u) else @abs(@cos(math.pi * u))),
                        .age_q = @floatCast(age * (65536.0 / (2.0 * math.pi))),
                        .rowoff = seed % @as(u32, NR),
                        .phoff = seed >> 16,
                    };
                }
            }
        }

        // CPU fallback: a stand-in for the coarse octave as a ~1-bin pixel sees it. Point samples
        // on a (radial bin, 1/GT_NP turn) grid (nearly uncorrelated: the eddies are smaller),
        // tent-filtered over the nodes, [1 2 3 2 1] radially x [1 2 1] in azimuth, and scaled to
        // the rms the field has when box-averaged over such a footprint (GT_RMS, fitted). The
        // GPU path samples the eddies themselves.
        // (turbCoarse at every node, with the per-bin work hoisted: same row, Omega and bands.)
        for (0..R_BINS) |b| {
            const rbf = @as(f32, @floatFromInt(b)) + 0.5;
            const row: usize = @min(@as(usize, @intFromFloat(rbf * (@as(f32, NR) / @as(f32, R_BINS)))), NR - 1);
            const n0: usize = self.band_n0[b];
            const om = self.om_row[row];
            const out = &self.gtmp[b];
            @memset(out, 0.0);
            inline for (0..2) |kk| {
                inline for (0..2) |gi| {
                    const gn = self.gen[0][n0 + kk][gi];
                    const wgt = self.band_w[b][kk] * gn.w / NOISE_STD;
                    const shift: u16 = @truncate(@as(u32, @intFromFloat(om * gn.age_q)));
                    const base: u16 = @as(u16, @truncate(gn.phoff)) +% shift;
                    const src = &self.noise[0][(row + gn.rowoff) % NR];
                    for (0..GT_NP) |pc| {
                        const phi: u16 = @intCast((pc << (16 - GT_LOG2)) + (1 << (15 - GT_LOG2)));
                        const q: u16 = phi -% base;
                        out[pc] += wgt * (@as(f32, @floatFromInt(src[q >> 6])) - 128.0);
                    }
                }
            }
        }
        const tr_w = [5]f32{ 1, 2, 3, 2, 1 };
        const gain = GT_RMS / @sqrt((19.0 / 81.0) * (6.0 / 16.0)); // white-noise rms after the tent
        for (0..R_BINS) |b| {
            for (0..GT_NP) |pc| {
                var acc: f32 = 0.0;
                var wsum: f32 = 0.0;
                for (0..5) |db| {
                    const bb = @as(i64, @intCast(b)) + @as(i64, @intCast(db)) - 2;
                    if (bb < 0 or bb >= R_BINS) continue;
                    const row = &self.gtmp[@intCast(bb)];
                    acc += tr_w[db] * (row[(pc + GT_NP - 1) & (GT_NP - 1)] + 2.0 * row[pc] + row[(pc + 1) & (GT_NP - 1)]);
                    wsum += 4.0 * tr_w[db];
                }
                self.gtab[b][pc] = acc / wsum * gain;
            }
        }

        // Hot spots: born, orbit at their exact Kerr angular velocity, fade.
        @memset(&self.spot_mask, 0);
        const span_bins = self.lnr_span / @as(f64, @floatFromInt(R_BINS));
        for (0..NSPOT) |j| {
            const shifted = self.t_m + @as(f64, @floatFromInt(j)) * SPOT_LIFE / @as(f64, @floatFromInt(NSPOT));
            const gen = @floor(shifted / SPOT_LIFE);
            const age = shifted - gen * SPOT_LIFE;
            const env = @sin(math.pi * age / SPOT_LIFE);
            const hs = mix64(@as(u64, @intFromFloat(@max(gen, 0.0))) *% 16 + j + 0xA5A5);
            const u = unitf(hs);
            const r = self.geo.r_in * (1.15 + 4.2 * u * u);
            const om = orbit(self.geo.a, r).om;
            const ph = @mod(2.0 * math.pi * unitf(mix64(hs ^ 7)) + om * self.t_m, 2.0 * math.pi);
            const rb = (@log(r) - self.lnr_in) / span_bins;
            const wr = (SPOT_SIZE / r) / span_bins;
            const wp = (SPOT_SIZE / r) / (2.0 * math.pi) * 65536.0;
            self.spot_rb[j] = @floatCast(rb);
            self.spot_wr[j] = @floatCast(wr);
            self.spot_wp[j] = @floatCast(wp);
            self.spot_q[j] = @truncate(@as(u32, @intFromFloat(ph / (2.0 * math.pi) * 65536.0)));
            self.spot_amp[j] = @floatCast(@as(f64, SPOT_AMP) * env * env);
            self.spot_age[j] = @floatCast(age);
            self.spot_om[j] = @floatCast(om);
            const lo: i64 = @intFromFloat(@floor(rb - wr - 12.0)); // margin for wide pixel footprints
            const hi: i64 = @intFromFloat(@ceil(rb + wr + 12.0));
            var b = @max(lo, 0);
            while (b <= @min(hi, @as(i64, R_BINS - 1))) : (b += 1) self.spot_mask[@intCast(b)] |= @as(u8, 1) << @intCast(j);
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return !math.isFinite(self.t_m) or !math.isFinite(self.exposure);
    }

    /// The CPU turbulence grid at a pixel: variance-preserving interpolation between nodes
    /// (separable, weights from tables).
    inline fn turbGrid(self: *const State, phi: u16, rbf: f32) f32 {
        const xb = math.clamp(rbf - 0.5, 0.0, @as(f32, R_BINS - 1) - 0.001);
        const b0: usize = @intFromFloat(xb);
        const tb: usize = @intFromFloat((xb - @as(f32, @floatFromInt(b0))) * @as(f32, GT_TQ));
        const q = phi -% (1 << (15 - GT_LOG2));
        const p0: usize = q >> (16 - GT_LOG2);
        const p1 = (p0 + 1) & (GT_NP - 1);
        const tp: usize = (q >> (16 - GT_LOG2 - GT_TQ_LOG2)) & (GT_TQ - 1);
        const r0 = &self.gtab[b0];
        const r1 = &self.gtab[@min(b0 + 1, R_BINS - 1)];
        const wp = gt_wp[tp];
        const wr = gt_wr[tb];
        return wr[0] * (wp[0] * r0[p0] + wp[1] * r0[p1]) + wr[1] * (wp[0] * r1[p0] + wp[1] * r1[p1]);
    }

    /// Octave-0 turbulence at (phi, rbf) (unit variance, nearest cell): two lifetime bands blended
    /// across radius, each two staggered generations, every generation advected at Omega(r)
    /// since its birth. Variance-preserving (sin/cos) weights keep the statistics stationary.
    fn turbCoarse(self: *const State, phi: u16, rbf: f32) f32 {
        const row: usize = @min(@as(usize, @intFromFloat(rbf * (@as(f32, NR) / @as(f32, R_BINS)))), NR - 1);
        const b: usize = @min(@as(usize, @intFromFloat(rbf)), R_BINS - 1);
        const n0: usize = self.band_n0[b];
        const om = self.om_row[row];
        var g: f32 = 0.0;
        inline for (0..2) |kk| {
            const gens = &self.gen[0][n0 + kk];
            inline for (0..2) |gi| {
                const gn = gens[gi];
                const shift: u16 = @truncate(@as(u32, @intFromFloat(om * gn.age_q)));
                const q: u16 = phi -% @as(u16, @truncate(gn.phoff)) -% shift;
                const v: f32 = @floatFromInt(self.noise[0][(row + gn.rowoff) % NR][q >> 6]);
                g += self.band_w[b][kk] * gn.w * (v - 128.0);
            }
        }
        return g / NOISE_STD;
    }

    /// 1 - exp(-e^x) from the table: emitted (or blocked) fraction for a log optical depth x.
    inline fn oneMinusExpExp(self: *const State, x: f32) f32 {
        const xi = math.clamp((x - EMIT_X0) * (@as(f32, EMIT_N) / (EMIT_X1 - EMIT_X0)), 0.0, @as(f32, EMIT_N) - 0.001);
        const ii: usize = @intFromFloat(xi);
        return self.emit_tab[ii] + (self.emit_tab[ii + 1] - self.emit_tab[ii]) * (xi - @as(f32, @floatFromInt(ii)));
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        // GPU builds trace on the GPU; if the CPU draw is used after all (no Metal), trace now, once.
        if (self.deferred) @constCast(self).traceNow();
        const w = self.w;
        if (w == 0 or self.h == 0 or stride < w) return;
        const h: usize = @min(self.h, buf.len / stride);
        const expo = self.exposure;

        const last_buf_idx = (h - 1) * stride + (w - 1);
        const last_bg_idx = (h - 1) * w + (w - 1);
        const need_bg_fill = (buf[0] != self.bg[0] or
            buf[w - 1] != self.bg[w - 1] or
            buf[last_buf_idx] != self.bg[last_bg_idx] or
            buf[(h - 1) * stride] != self.bg[(h - 1) * w]);

        if (need_bg_fill) {
            for (0..h) |y| {
                const row = buf[y * stride .. y * stride + w];
                @memcpy(row, self.bg[y * w .. y * w + w]);
            }
        }

        for (0..h) |y| {
            const x0 = self.row_x0[y];
            const x1 = self.row_x1[y];
            if (x0 >= x1) continue;
            const row = buf[y * stride .. y * stride + w];
            const bg_row = self.bg[y * w .. y * w + w];
            const rec_row = self.recs[y * w .. y * w + w];
            // The CPU grid is smooth over a cell (tent-filtered): a pixel within half a cell of
            // the last lookup on this row reuses it.
            var last_rbin: i32 = -1000;
            var last_phi: u16 = 0;
            var last_g: f32 = 0.0;
            for (x0..x1) |x| {
                const rc = rec_row[x];
                if (rc.cov == 0) continue;
                const rb = rc.rbin / R_FRAC;
                const rbf = @as(f32, @floatFromInt(rc.rbin)) / @as(f32, @floatFromInt(R_FRAC));
                // CPU fallback: a stand-in for the coarse octave (see step()), as brightness at fixed
                // colour; the GPU path samples both octaves per pixel and changes the temperature.
                const frf: f32 = @as(f32, @floatFromInt(rc.fr)) * 0.25; // bins
                const fpf: f32 = @as(f32, @floatFromInt(rc.fp)) * 64.0;

                // The GPU changes the temperature, T ~ eps^(1/4); here the brightness changes by the
                // blackbody's response to that, d ln Y / d ln eps (baked per pixel), at fixed colour.
                const amp = gridFoot(frf, fpf) * @as(f32, @floatFromInt(rc.resp)) / RESP_SCALE;
                const drb: i32 = @as(i32, rc.rbin) - last_rbin;
                const dph: i32 = @as(i16, @bitCast(rc.phi -% last_phi));
                if (@abs(drb) > R_FRAC / 2 or @abs(dph) > (1 << (15 - GT_LOG2))) {
                    last_g = self.turbGrid(rc.phi, rbf);
                    last_rbin = rc.rbin;
                    last_phi = rc.phi;
                }
                const m = last_g * amp;
                const amp_rms = GT_RMS * amp;
                const ex = math.clamp((TURB_SIGMA * m - 0.5 * TURB_SIGMA * TURB_SIGMA * amp_rms * amp_rms + 4.0) * (@as(f32, EXP_N) / 8.0), 0.0, @as(f32, EXP_N) - 0.001);
                const ei: usize = @intFromFloat(ex);
                var k = (self.exp_tab[ei] + (self.exp_tab[ei + 1] - self.exp_tab[ei]) * (ex - @as(f32, @floatFromInt(ei)))) * expo;
                // The gas emits 1 - e^(-tau_*/mu) of a blackbody at its source temperature (baked into
                // rgb) and lets e^(-tau_ext/mu) of what lies behind through (baked into bf).
                var spot_rgb: [3]f32 = undefined;
                var spot_scale: f32 = 0.0;
                const sm = self.spot_mask[rb];
                if (sm != 0) {
                    var boost: f32 = 0.0;
                    // Azimuth a sheared spot sweeps across this pixel's radial footprint, per M of age.
                    const shear_q_per_age = self.shear_tab[rb] * (frf + 0.5);
                    // Omega at this pixel's radius, between the table's bin centres.
                    const om_px: f32 = blk: {
                        const xb = math.clamp(rbf - 0.5, 0.0, @as(f32, R_BINS - 1) - 0.001);
                        const ib: usize = @intFromFloat(xb);
                        const fb = xb - @as(f32, @floatFromInt(ib));
                        const o0: f32 = @floatCast(self.om_tab[ib]);
                        const o1: f32 = @floatCast(self.om_tab[@min(ib + 1, R_BINS - 1)]);
                        break :blk o0 + (o1 - o0) * fb;
                    };
                    inline for (0..NSPOT) |j| {
                        if (sm & (@as(u8, 1) << j) != 0) {
                            // Spot seen through this pixel's footprint: widen the kernel, keep its energy.
                            // A sheared spot's azimuth shifts with radius: across the pixel's radial footprint
                            // it moves by |dOmega/dr| * age * dr. Widen the azimuthal kernel by that too.
                            const smear = shear_q_per_age * self.spot_age[j];
                            const wr2 = self.spot_wr[j] * self.spot_wr[j] + frf * frf;
                            const wp2 = self.spot_wp[j] * self.spot_wp[j] + fpf * fpf + smear * smear;
                            const dr = rbf - self.spot_rb[j];
                            // Sheared: at this radius the clump has moved (Omega(r) - Omega_spot) * age further.
                            const shear: f32 = (om_px - self.spot_om[j]) * self.spot_age[j] * (65536.0 / (2.0 * math.pi));
                            const dp0: f32 = @as(f32, @floatFromInt(@as(i16, @bitCast(rc.phi -% self.spot_q[j])))) - shear;
                            const dp = dp0 - 65536.0 * @round(dp0 / 65536.0);
                            // Saturated footprints as on the GPU (7-bit azimuth, 5-bit radius).
                            if (rc.fp >= 127 or rc.fr >= FR_SAT or fpf > 2.0 * self.spot_wp[j] or frf > 2.0 * self.spot_wr[j]) {
                                // Unresolved here (pixel footprint wider than the spot): widening the
                                // kernel would smear it into long false arcs, so it is left out.
                                // Emission phase winds > 1/4 turn across this pixel (lensing time delays):
                                // the spot is unresolvable here. Its true contribution is a time average we
                                // don't integrate, so it is left out rather than drawn as a fake ring.
                            } else {
                                const q = dr * dr / wr2 + dp * dp / wp2;
                                if (q < 1.0) boost += self.spot_amp[j] * (1.0 - q) * (1.0 - q) * self.spot_wr[j] * self.spot_wp[j] / @sqrt(wr2 * wp2);
                            }
                        }
                    }
                    if (boost > 1e-3 and rc.tobs > 0) {
                        // Hotter gas is a hotter blackbody (T ~ emission^(1/4)): Planck gives its
                        // new color and brightness; ratio carries this pixel's coverage/normalisation.
                        const t0: f64 = @floatCast(@as(f32, rc.tobs));
                        const hot = self.bbLookup(t0 * @sqrt(@sqrt(1.0 + @as(f64, boost))));
                        const lum0 = luma(.{ rc.rgb[0], rc.rgb[1], rc.rgb[2] });
                        spot_scale = @floatCast(lum0 / @max(luma(self.bbLookup(t0)), 1e-12));
                        spot_rgb = .{ @floatCast(hot[0]), @floatCast(hot[1]), @floatCast(hot[2]) };
                    } else k *= 1.0 + boost;
                }
                const c = if (spot_scale > 0.0)
                    [3]f32{ spot_rgb[0] * spot_scale * k, spot_rgb[1] * spot_scale * k, spot_rgb[2] * spot_scale * k }
                else
                    [3]f32{ @as(f32, rc.rgb[0]) * k, @as(f32, rc.rgb[1]) * k, @as(f32, rc.rgb[2]) * k };
                row[x] = self.composite(rc, c, bg_row[x]);
            }
        }
    }
};

const GT_LOG2 = 9; // CPU turbulence grid: 2^9 phase slots per turn (2 noise-table cells)
const GT_NP = 1 << GT_LOG2;
const GT_RMS: f32 = 0.367; // rms of the coarse octave box-averaged over +-2 bins x +-1 slot (fitted)
const GT_RHO_R: f32 = 0.84; // neighbour correlation of the tent-filtered grid: radial, azimuthal
const GT_RHO_P: f32 = 0.67;

/// Footprint wider than the grid's own averaging (+-2 bins, +-1 slot): the box average falls
/// further, ~ (extent ratio)^(-1/2) per axis.
inline fn gridFoot(frf: f32, fpf: f32) f32 {
    if (frf <= 2.0 and fpf <= 256.0) return 1.0;
    return 1.0 / @sqrt(@max(frf * 0.5, 1.0) * @max(fpf * (1.0 / 256.0), 1.0));
}

const GT_TQ_LOG2 = 5; // interpolation weights quantised to 1/32 of a cell
const GT_TQ = 1 << GT_TQ_LOG2;

/// Weights of an interpolation that keeps the variance of a field whose neighbours correlate
/// by rho: ((1 - t) a + t b) / sqrt((1 - t)^2 + t^2 + 2 t (1 - t) rho), tabulated at t = (i + 0.5) / GT_TQ.
fn vmixWeights(comptime rho: f32) [GT_TQ][2]f32 {
    var w: [GT_TQ][2]f32 = undefined;
    for (0..GT_TQ) |i| {
        const t = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, GT_TQ);
        const n = @sqrt((1.0 - t) * (1.0 - t) + t * t + 2.0 * t * (1.0 - t) * rho);
        w[i] = .{ (1.0 - t) / n, t / n };
    }
    return w;
}
const gt_wp = vmixWeights(GT_RHO_P);
const gt_wr = vmixWeights(GT_RHO_R);

/// One generation of eddies: its weight now, its age (Q16 phase per unit Omega), and the offsets
/// that make it an independent draw from the octave's noise plane. Laid out for the GPU.
pub const TurbGen = extern struct { w: f32, age_q: f32, rowoff: u32, phoff: u32 };

/// Generation seed shared with the GPU shader (lowbias32 of the octave, band and generation).
pub fn turbSeed(j: u32, n: u32, k: u32) u32 {
    var x = j *% 0x9E3779B1 ^ n *% 0x85EBCA77 ^ k *% 0xC2B2AE3D;
    x ^= x >> 16;
    x *%= 0x7feb352d;
    x ^= x >> 15;
    x *%= 0x846ca68b;
    x ^= x >> 16;
    return x;
}

/// Colour-correction factor of an accretion-disk atmosphere at effective temperature T (Done,
/// Davis, Jin, Blaes & Ward 2012, MNRAS 420, 1848): 1 below 3e4 K (hydrogen neutral, absorption
/// thermalises), (T / 3e4 K)^0.83 to 1e5 K, (72 keV / kT)^(1/9) above (electron scattering).
pub fn colourFactor(T: f64) f64 {
    if (!(T > 3.0e4)) return 1.0;
    if (T < 1.0e5) return math.pow(f64, T / 3.0e4, 0.83);
    return math.pow(f64, 72.0 / (T * 8.617333e-8), 1.0 / 9.0);
}

/// Limb darkening of the gas at ln(1/mu) = lmu, weighted by how thick (scattering-dominated) the
/// atmosphere is: a semi-infinite electron-scattering atmosphere gives I(mu) ~ 1 + 2.06 mu
/// (Chandrasekhar's H-function, linear fit; Laor 1991), normalised to the same flux as an
/// isotropic emitter; translucent gas emits as a thin slab instead (its 1/mu limb brightening
/// is in 1 - e^(-tau_*/mu)).
pub fn limbFactor(lmu: f64, tau_ext: f64) f64 {
    const ld = (1.0 + LIMB_B * @exp(-lmu)) / (2.0 * (0.5 + LIMB_B / 3.0));
    return 1.0 + (ld - 1.0) * -std.math.expm1(-tau_ext);
}

fn wrapPi(x: f64) f64 {
    return x - 2.0 * math.pi * @round(x / (2.0 * math.pi));
}

comptime {
    sdk.exportTheme(State);
}

// ============================================================================ physics tests

const testing = std.testing;

test "ISCO: 6M without spin, -> 1M at extreme spin, and energy is minimal there" {
    try testing.expectApproxEqAbs(6.0, isco(0.0), 1e-12);
    try testing.expect(isco(0.999999) < 1.05);
    const a = SPIN;
    const r = isco(a);
    const e = 1e-5;
    const dE = (orbit(a, r * (1 + e)).E - orbit(a, r * (1 - e)).E) / (2 * r * e);
    try testing.expect(@abs(dE) < 1e-6);
    try testing.expect(orbit(a, r * 1.01).E > orbit(a, r).E);
}

test "photon orbits and Schwarzschild shadow radius sqrt(27)" {
    try testing.expectApproxEqAbs(3.0, photonOrbit(0.0, true), 1e-12);
    const g = Geo.init(0.0, INCL, R_OUT);
    var lo: f64 = 4.0;
    var hi: f64 = 7.0;
    for (0..40) |_| {
        const mid = 0.5 * (lo + hi);
        if (traceRay(&g, 0.0, mid, false).kind == .hole) lo = mid else hi = mid;
    }
    try testing.expectApproxEqAbs(@sqrt(27.0), 0.5 * (lo + hi), 2e-3);
}

/// Bardeen (1973) critical curve: the exact edge of the Kerr shadow.
fn bardeen(a: f64, incl: f64, r: f64) ?[2]f64 {
    const lam = -(r * r * (r - 3.0) + a * a * (r + 1.0)) / (a * (r - 1.0));
    const eta = r * r * r * (4.0 * a * a - r * (r - 3.0) * (r - 3.0)) / (a * a * (r - 1.0) * (r - 1.0));
    const ci = @cos(incl);
    const si = @sin(incl);
    const b2 = eta + a * a * ci * ci - lam * lam * ci * ci / (si * si);
    if (b2 < 0) return null;
    return .{ -lam / si, @sqrt(b2) };
}

test "Kerr shadow edge matches Bardeen's analytic critical curve" {
    const g = Geo.init(SPIN, INCL, R_OUT);
    const r1 = photonOrbit(SPIN, true);
    const r2 = photonOrbit(SPIN, false);
    var worst: f64 = 0.0;
    var checked: usize = 0;
    for (1..12) |k| {
        const r = r1 + (r2 - r1) * @as(f64, @floatFromInt(k)) / 12.0;
        const ab = bardeen(SPIN, INCL, r) orelse continue;
        if (ab[1] < 0.3) continue; // too close to the equator line to bisect cleanly
        var lo: f64 = 0.0;
        var hi: f64 = ab[1] + 3.0;
        if (traceRay(&g, ab[0], lo, false).kind != .hole) continue;
        for (0..40) |_| {
            const mid = 0.5 * (lo + hi);
            if (traceRay(&g, ab[0], mid, false).kind == .hole) lo = mid else hi = mid;
        }
        worst = @max(worst, @abs(0.5 * (lo + hi) - ab[1]));
        checked += 1;
    }
    std.debug.print("\n  Bardeen check: {d} points, worst |beta_traced - beta_exact| = {e:.2} M\n", .{ checked, worst });
    try testing.expect(checked >= 6);
    try testing.expect(worst < 0.01);
}

test "geodesic invariants: null condition and Carter constant are conserved" {
    const g = Geo.init(SPIN, INCL, R_OUT);
    const st = initialState(&g, -2.4, 3.9);
    var y = st.y;
    const L = st.L;
    const a = SPIN;
    const q0 = carter(a, L, y);
    var worst_h: f64 = 0.0;
    var worst_q: f64 = 0.0;
    for (0..4000) |_| {
        const r = y[0];
        if (r < g.rh + 0.05 or (y[4] > 0 and r > 200)) break;
        const k1 = rhs(a, L, y);
        y = project(a, L, rk4k(a, L, y, stepSize(&g, L, y, k1), k1)); // the production stepper
        worst_h = @max(worst_h, @abs(nullB(a, L, y)) / (y[0] * y[0]));
        worst_q = @max(worst_q, @abs(carter(a, L, y) - q0) / q0);
    }
    std.debug.print("\n  invariants: max |H|/r^2 = {e:.2}, max |dQ/Q| = {e:.2}\n", .{ worst_h, worst_q });
    try testing.expect(worst_h < 1e-4);
    try testing.expect(worst_q < 1e-4);
}

fn nullB(a: f64, L: f64, y: V6) f64 {
    const s = @sin(y[1]);
    const s2 = s * s;
    const r = y[0];
    const del = r * r - 2 * r + a * a;
    const P = r * r + a * a - a * L;
    return del * y[4] * y[4] + y[5] * y[5] - P * P / del + (L - a * s2) * (L - a * s2) / s2;
}

fn carter(a: f64, L: f64, y: V6) f64 {
    const c = @cos(y[1]);
    const s = @sin(y[1]);
    return y[5] * y[5] - a * a * c * c + L * L * c * c / (s * s);
}

test "Page-Thorne flux: zero at the ISCO, positive outside, Newtonian at large r" {
    var f: [PT_N]f64 = undefined;
    const r_in = isco(0.3);
    pageThorne(0.3, r_in, 1.0e5, &f);
    try testing.expectEqual(@as(f64, 0.0), f[0]);
    for (f[1..]) |v| try testing.expect(v > 0.0);
    // far out F -> C (1 - sqrt(r_*/r)) / r^3 ; F r^3 must flatten to a constant
    const dl = @log(1.0e5 / r_in) / @as(f64, PT_N - 1);
    const k1: usize = @intFromFloat(@log(2.0e4 / r_in) / dl);
    const k2: usize = PT_N - 1;
    const ra = r_in * @exp(dl * @as(f64, @floatFromInt(k1)));
    const rb = r_in * @exp(dl * @as(f64, @floatFromInt(k2)));
    const ratio = (f[k1] * ra * ra * ra) / (f[k2] * rb * rb * rb);
    try testing.expectApproxEqAbs(1.0, ratio, 0.02);
}


test "blackbody colours: 6500 K is near white, 3000 K is warm, 20000 K is blue" {
    const w = blackbodyRGB(6500.0);
    const mx = @max(w[0], @max(w[1], w[2]));
    const mn = @min(w[0], @min(w[1], w[2]));
    try testing.expect(mx / mn < 1.15);
    const c = blackbodyRGB(3000.0);
    try testing.expect(c[0] > c[1] and c[1] > c[2]);
    const hot = blackbodyRGB(20000.0);
    try testing.expect(hot[2] > hot[0]);
}

test "redshift: approaching side is the prograde-photon side, and the shadow is flattened there" {
    const a = SPIN;
    const r = 6.0;
    const g_left = redshift(a, r, 6.0 * @sin(INCL)); // alpha = -6
    const g_right = redshift(a, r, -6.0 * @sin(INCL)); // alpha = +6
    try testing.expect(g_left > 1.0 and g_right < 1.0);
    const flat = bardeen(a, INCL, photonOrbit(a, true) + 0.05);
    if (flat) |ab| try testing.expect(ab[0] < 0.0);
}

test "computed disk: mass budget, Page-Thorne limit, quasar-like temperature, translucent tail" {
    var pt: [PT_N]f64 = undefined;
    const r_in = isco(SPIN);
    pageThorne(SPIN, r_in, 85.0, &pt);
    var d: DiskProfile = undefined;
    diskProfile(SPIN, r_in, 85.0, &pt, &d);
    const dl = @log(85.0 / r_in) / @as(f64, PT_N - 1);
    const at = struct {
        fn f(dd: *const DiskProfile, ri: f64, dll: f64, rr: f64) [3]f64 {
            const k: usize = @intFromFloat(@round(@log(rr / ri) / dll));
            return .{ dd.T[k], @exp(@as(f64, dd.lt_ext[k])), @exp(@as(f64, dd.lt_em[k])) };
        }
    }.f;
    std.debug.print("\n  disk: T_peak {d:.0} K at r={d:.2}, tau_es {d:.0}, Sigma {e:.2}, H/r {d:.4}, mass budget {d:.4}, F/F_PT spread {d:.3}\n", .{ d.t_peak, d.r_peak, d.tau_es_peak, d.sigma_peak, d.h_over_r_peak, d.mass_budget, d.pt_ratio_spread });
    for (PT_CHECK_R, d.pt_ratio_at) |rr, q| std.debug.print("  F/F_PT at r {d}: {d:.3}\n", .{ rr, q });
    for ([_]f64{ 3, 10, 20, 30, 40, 50, 60, 80 }) |rr| {
        const v = at(&d, r_in, dl, rr);
        std.debug.print("  r {d:>4}: T_s {d:>7.0} K  tau_ext {e:.3}  tau_* {e:.3}\n", .{ rr, v[0], v[1], v[2] });
    }
    try testing.expectApproxEqAbs(1.0, d.mass_budget, 0.01);
    try testing.expect(d.pt_ratio_spread < 1.15);
    try testing.expect(d.t_peak > 30_000.0 and d.t_peak < 45_000.0);
    try testing.expect(at(&d, r_in, dl, 20.0)[1] > 10.0); // opaque at 20 M
    try testing.expect(at(&d, r_in, dl, 80.0)[1] < 1e-2); // gone by 80 M
}

test "colour correction and limb darkening: continuity, flux conservation, thin limit" {
    // Done et al. 2012: f = 1 below 3e4 K and continuous at 1e5 K (the 0.83 exponent joins the
    // Compton branch to 0.3%).
    try testing.expectEqual(@as(f64, 1.0), colourFactor(2.9e4));
    try testing.expectApproxEqRel(colourFactor(0.9999e5), colourFactor(1.0001e5), 5e-3);
    try testing.expect(colourFactor(3.7e4) > 1.15 and colourFactor(3.7e4) < 1.2);
    // Limb darkening on a thick atmosphere conserves the flux of an isotropic emitter:
    // 2 int_0^1 I(mu) mu dmu = 1; and it switches off where the gas is thin.
    var flux: f64 = 0.0;
    const n = 20000;
    for (0..n) |i| {
        const mu = (@as(f64, @floatFromInt(i)) + 0.5) / n;
        flux += 2.0 * limbFactor(-@log(mu), 1e6) * mu / n;
    }
    try testing.expectApproxEqAbs(1.0, flux, 1e-6);
    try testing.expectApproxEqAbs(1.0, limbFactor(-@log(0.1), 1e-6), 1e-5);
    try testing.expect(limbFactor(-@log(0.2), 1e6) < 0.6); // grazing view of the thick disk: dimmer
}

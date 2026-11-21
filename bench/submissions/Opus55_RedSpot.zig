// Jupiter's Great Red Spot and its turbulent wake: a 60,000 km stretch of the southern cloud bands, seen from straight above, flowing as a forced quasi-geostrophic fluid.
// @argus-theme: custom_shader
//
// OPUS55_REDSPOT // bench/submissions/Opus55_RedSpot.zig
// Claude Opus 5.5, agentic ARGUS-BENCH run (Track B), 2026-11-21.
//
// What you see: a flat map of Jupiter from 6.7 S to 37.3 S, north up, west to the left, 60,000 km
//   across (about 52 degrees of longitude at 22 S). The Great Red Spot turns counterclockwise in
//   the bright South Tropical Zone, between the dark brown South Equatorial Belt to its north and
//   the greyer South Temperate Belt to its south, with a lighter collar and a pale hollow around a
//   deep red core. White convective plumes rise in the belt north-west of it and are torn into the
//   streaky wake; the belts curl into eddies. Nothing is painted: every streak is cloud brightness
//   and colour carried by the simulated wind.
//
// Sources ([cited] page read, [snippet] search result only):
//   - Spot at ~22 S, counterclockwise, ~4.5-day circulation (2008), edge winds ~432 km/h
//     (120 m/s), interior nearly stagnant, width 16,350 km (Juno, 2017) [cited:
//     en.wikipedia.org/wiki/Great_Red_Spot] -> a 16,000 x 11,000 km vortex at 22 S whose wind
//     peaks at the collar (~120 m/s, checked) over a quiet core.
//   - "A very strong westward jet lies to the north, a modest eastward jet to the south" [cited,
//     same page]; westward ~70 m/s at 17.5 S, eastward ~60 m/s at 24.5 S [snippet: EBSCO GRS
//     overview] -> those two jets in the wind profile; their shear has the spot's sign.
//   - The turbulent "GRS wake" of filamentary convection lies north-west of the spot [snippet:
//     arXiv 2410.02468 and 1701.00957; Voyager 1 shows turbulence to its west, cited page]
//     -> vigorous plumes are seeded only in the SEB, 3,000-20,000 km west of the spot.
//   - The jets extend ~3,000 km deep [snippet: Kaspi et al. 2018, Nature 555, 223] -> the deep
//     layer is taken to move with the cloud-level jets, so only perturbations feel the
//     deformation radius (the jets add no -U/Ld^2 PV gradient).
//   - Red = a chromophore absorbing blue and green light [snippet: arXiv 1706.02779], made by
//     sunlight on material held at the highest cloud tops [snippet: Scientific American] -> the
//     colour is a Beer-Lambert tint (blue absorbed most), produced only in air trapped inside an
//     anticyclone; trapped air is not reset to its band, so colour tracks residence time and the
//     core, trapped longest, is reddest.
//
// COMPUTED: the wind. A 256x160 equivalent-barotropic quasi-geostrophic model on Jupiter's own
//   Coriolis parameter f = 2*Omega*sin(lat) (Omega from the 9 h 55 m 30 s rotation), with the
//   zonal jets as background flow. Potential vorticity is advected semi-Lagrangian (RK2 departure
//   points, clamped Catmull-Rom) and inverted exactly every step (FFT in longitude, tridiagonal in
//   latitude). The spot's speed profile, its wobble and drift, the eddies the jets shed and the
//   wake's tearing are outputs. Cloud brightness and chromophore are two tracers advected on a
//   960x600 grid (62.5 km cells) by that wind.
// CHOSEN: the wind profile away from the two sourced jets (shape after published profiles, values
//   approximate, smoothed by a 1-degree Gaussian); deformation radius 2,000 km; the spot's
//   north-south size and its PV (12/day), set so the collar reaches ~120 m/s; a weak nudge toward
//   that vortex (5 days), anchored at 22 S, standing in for its real and debated energy supply
//   (without the anchor this profile lets it drift to 24.6 S in an hour); damping of perturbations
//   (60 days) and of their zonal mean (4 days), which keeps the jets; small random eddies stirred
//   into the belts; plume rate, size and life, and the faint ring of cleared air around each;
//   relaxation of brightness and colour to the band pattern (6 days); band brightness and colour
//   set by eye after Hubble OPAL true-colour images, not measured; a periodic channel of 52
//   degrees of longitude instead of the whole planet (what leaves on the right comes back on the
//   left); the camera follows the spot's longitude. Time-lapse: one wall second (30 Argus ticks)
//   is 0.06 Jovian day (1.44 h), about 5,200x.
// NOT MODELLED: moist convection itself (plumes are prescribed sources of white cloud plus a small
//   anticyclone); vertical structure beyond one deformation radius; the planet's curvature, limb
//   and lighting (the view is a flat true-colour map, no relief); Oval BA and the white ovals
//   further south; the spot's 90-day oscillation and its shrinking.
// CHECKED (`zig test -O ReleaseSafe -lc` on this file; LEDGER lines): collar wind 125 m/s after
//   two minutes (cited 120); latitude 22.2 S; after an hour of wall time (216 Jovian days) still
//   123 m/s at 22.5 S. The collar's circulation takes 7.1 days here, slower than the 4.5 days
//   measured in 2008: the modelled collar is broader, and the spot turns once in about two minutes
//   on screen. A size sweep (1x1 to 3024x1964, padded stride) draws every pixel opaque. Flicker:
//   the stored tracers are renewed every two seconds; the mean frame change at that boundary is
//   0.32 levels (0.05 mid-interval), at most an 8-level step (600 frames measured). The browser
//   build (wasm, one thread) passes gates 1-7 on the bench page in Chrome. Not checked: the
//   colours against calibrated spectra, the wind profile away from the two sourced jets.
// How it works: every 60 ticks (two wall seconds) an interval starts: one PV step and inversion
//   (~1.5 ms). The tracer advection and the next interval's departure field are spread over the
//   60 ticks. In
//   between, each tick shows the tracers sampled at x - phase*displacement (plume injection
//   shown in proportion), so motion is continuous while the stored tracers are resampled only
//   once per interval: little numerical diffusion. step() colours the 960x600 grid through a
//   256x128 table, only as finely as the screen shows it (every cell at 1920x1200, every third
//   at 320x200); draw() upscales it bilinearly, 64-bit lane-packed (a gather-free path at
//   exactly 2x). One allocation: the State, 24.7 MB. init() is kept to ~0.2 s on an M3,
//   because the 10 s watchdog probe repeats it and wasm in a browser is >10x slower: the wind
//   runs 3.8 days in 16 long steps; the clouds start from the bands displaced by each parcel's
//   PV anomaly (eta = q'/beta: PV is conserved, so it labels where a parcel came from), then
//   run 2.9 days in 6 long steps (semi-Lagrangian advection is stable at any step).
// Cost: 5.4-6.2 ms per frame in the harness on an M3 under load 3-6 from other work (the
//   section 3 skeleton read 1.58 ms alongside it), Bronze tier.

const std = @import("std");
const math = std.math;
const sdk = @import("argus_theme_sdk.zig");

pub const MAX_W: usize = 8192;
pub const MAX_H: usize = 8192;

// ---- geometry ----
const NX: usize = 256; // PV grid, longitude
const NY: usize = 160; // PV grid, latitude (row 0 = north)
const NC: usize = NX * NY;
const DXK: f32 = 234.375; // km per PV cell (60,000 km / 256)
const DW: usize = 960; // tracer grid
const DH: usize = 600;
const ND: usize = DW * DH;
const C_PER_D: f32 = @as(f32, @floatFromInt(NX)) / @as(f32, @floatFromInt(DW)); // 0.4
const KM_PER_DEG: f32 = 1221.7; // R = 70,000 km
const LAT_TOP: f32 = -22.0 + (@as(f32, @floatFromInt(NY)) * DXK * 0.5) / KM_PER_DEG; // -6.65

// ---- time ----
const TICKS: usize = 60; // ticks per interval = two wall seconds in Argus (30 Hz)
const T_DAY: f32 = 0.12; // Jovian days per interval (0.06 per wall second)
const TWO_OMEGA: f32 = 2.0 * (2.0 * math.pi / 35729.7) * 86400.0; // 1/day
const LD_KM: f32 = 2000.0;

// ---- forcing ----
const TAU_E: f32 = 60.0; // days, perturbation damping
const TAU_Z: f32 = 4.0; // days, zonal-mean perturbation damping
const TAU_G: f32 = 5.0; // days, GRS nudge
const TAU_DYE: f32 = 6.0; // days, tracer relaxation to band climatology
const TAU_RED: f32 = 3.0; // days, chromophore production inside anticyclones
const GRS_Q: f32 = 12.0; // 1/day, PV anomaly of the spot (tuned: collar ~120 m/s)
const GRS_A: f32 = 8000.0 / DXK; // semi-axes in PV cells
const GRS_B: f32 = 5500.0 / DXK;
const MAX_STORMS: usize = 64;

// ---- display ----
const CL_A: usize = 256; // colour table: brightness levels over [0, A_MAX]
const CL_C: usize = 128; // chromophore levels over [0, C_MAX]
const A_MAX: f32 = 1.1;
const C_MAX: f32 = 1.2;
const D_MAX: f32 = 30.0; // displacement clamp, tracer cells (the fastest wind moves ~25)
const PAD: usize = 34; // interior cells (>= PAD from an edge) need no wrap or clamp, even for Catmull-Rom

const Storm = struct {
    x: f32 = 0, // tracer cells
    y: f32 = 0,
    rad: f32 = 0,
    age: f32 = 0, // days
    life: f32 = 0,
    power: f32 = 0,
    vx: f32 = 0, // displacement over the current interval, tracer cells
    vy: f32 = 0,
    on: bool = false,
};

/// Plume strength this interval: switches on over a sixth of its life, fades over the last 40%.
fn plumeStrength(st: *const Storm) f32 {
    const life_t = st.age / st.life;
    return st.power * 0.84 * math.clamp(life_t * 6.0, 0.0, 1.0) * math.clamp((1.0 - life_t) * 2.5, 0.0, 1.0);
}

/// Convective plume: fresh white ammonia cloud with no chromophore at the head (flat-topped,
/// exp(-r^4): a crisp edge, not a soft ball) and a ring of subsiding air where deeper cloud shows.
fn inject(a: *f32, c: *f32, r2: f32, strength: f32, c_cl: f32) void {
    const g = @exp(-r2 * r2) * strength;
    a.* += (1.08 - a.*) * g;
    c.* -= c.* * g * 0.8;
    const rr = @sqrt(r2) - 1.6;
    const ring = @exp(-rr * rr / 0.30) * strength * 0.07;
    a.* += (0.0 - a.*) * ring;
    c.* += (c_cl - c.*) * ring;
}

/// Tracer row (fractional) of a latitude in degrees south.
fn dyeRowOfLat(lat_s: f32) f32 {
    return (lat_s + LAT_TOP) * KM_PER_DEG / (DXK * C_PER_D) - 0.5;
}

pub const State = struct {
    w: usize,
    h: usize,
    scale: f64,
    time_sec: f64,
    tk: usize,
    intervals: u64,
    rng: u64,
    bad: bool,

    // PV model
    q: [NC]f32, // perturbation PV, 1/day
    q2: [NC]f32,
    psi: [NC]f32, // perturbation streamfunction, km^2/day
    cu: [NC]f32, // total velocity, PV cells per interval (x east, y south)
    cv: [NC]f32,
    red: [NC]f32, // anticyclone mask for chromophore production
    fre: [NC]f32, // spectral scratch
    fim: [NC]f32,
    ubg: [NY]f32, // background zonal wind, km/day
    qbg: [NY]f32, // background PV, 1/day
    cosk: [NX / 2]f32,
    sink: [NX / 2]f32,
    lam: [NX]f32,
    gx: f32, // GRS centre, PV cells
    gy: f32, // the nudge is anchored at 22 S
    gy_obs: f32, // where the streamfunction minimum actually is

    // tracers: [front/back]
    ta: [2][ND]f32, // cloud brightness (0 deep, 1 fresh ammonia white)
    tc: [2][ND]f32, // chromophore
    front: usize,
    dx: [2][ND]f16, // departure displacement per interval, tracer cells
    dy: [2][ND]f16,
    dcur: usize,
    a_clim: [DH]f32,
    c_clim: [DH]f32,
    storms: [MAX_STORMS]Storm,

    // display
    col: [ND]u64, // lane-packed R<<32 | G<<16 | B
    trans: [256][3]f32,
    srgb: [1024]u8,
    clut: [CL_A * CL_C]u64,
    pa: [ND]f32, // displayed tracers under plumes (scratch)
    pc: [ND]f32,
    cam: f32, // left edge of the view, tracer cells
    view_sc: f32,
    view_oy: f32,
    colx0: [MAX_W]u16,
    colx1: [MAX_W]u16,
    colw: [MAX_W]u16,
    rowy0: [MAX_H]u16,
    rowy1: [MAX_H]u16,
    lod: usize, // shade every lod-th tracer cell: no finer than the screen shows
    roww: [MAX_H]u16,

    pub fn init(alloc: std.mem.Allocator, w: usize, h: usize, scale: f64) !*State {
        const self = try alloc.create(State);
        self.w = @max(@as(usize, 1), @min(w, MAX_W));
        self.h = @max(@as(usize, 1), @min(h, MAX_H));
        self.scale = scale;
        self.time_sec = 0;
        self.tk = 0;
        self.intervals = 0;
        self.rng = 0x9E3779B97F4A7C15;
        self.bad = false;
        self.front = 0;
        self.dcur = 0;
        self.storms = @splat(Storm{});
        self.q = @splat(0);
        self.q2 = @splat(0);
        self.psi = @splat(0);

        self.setupTables();
        // level of detail: the largest divisor of gcd(DW, DH) = 120 not above the tracer cells
        // per screen pixel (1 at 1920x1200 and above, 3 for the 320x200 watchdog)
        self.lod = @max(@as(usize, 1), @as(usize, @intFromFloat(@floor(@min(self.viewScale(), 120.0)))));
        while (120 % self.lod != 0) self.lod -= 1;
        @memset(&self.col, 0);
        self.setupBackground();
        self.gx = 0.62 * @as(f32, @floatFromInt(NX));
        self.gy = 0.5 * @as(f32, @floatFromInt(NY)) - 0.5;
        self.gy_obs = self.gy;
        // the spot itself
        for (0..NY) |j| for (0..NX) |i| {
            self.q[j * NX + i] = GRS_Q * self.grsShape(@floatFromInt(i), @floatFromInt(j));
        };
        self.invert();

        // Spin-up, kept cheap because the 10 s watchdog probe repeats init (and wasm in a browser
        // is over 10x slower than native): long steps are fine for semi-Lagrangian advection, and
        // in the zonal jets a straight-line departure is nearly exact. The wind first: 16 steps of
        // two intervals (3.8 Jovian days).
        for (0..16) |_| self.coarseStep(false, 2.0);
        // tracers start on the band climatology, the spot pre-reddened
        const back = 1 - self.front;
        // PV is materially conserved, so a parcel's PV anomaly says where it came from: linear
        // theory displaces it by eta = q'/beta (PV is higher to the north), clamped to 1,500 km
        const beta_km = TWO_OMEGA * @cos(22.0 * math.pi / 180.0) / (KM_PER_DEG * 180.0 / math.pi);
        for (0..DH) |j| for (0..DW) |i| {
            const c = j * DW + i;
            const fi: f32 = @floatFromInt(i);
            const fj: f32 = @floatFromInt(j);
            const qp = bilinC(&self.q, (fi + 0.5) * C_PER_D - 0.5, (fj + 0.5) * C_PER_D - 0.5);
            const eta_cells = math.clamp(qp / beta_km, -1500.0, 1500.0) / (DXK * C_PER_D);
            const j0: usize = @intFromFloat(math.clamp(@round(fj - eta_cells), 0.0, @as(f32, @floatFromInt(DH - 1))));
            const g = self.redAt(fi, fj);
            self.ta[back][c] = self.a_clim[j0] + (0.55 - self.a_clim[j0]) * g;
            self.tc[back][c] = self.c_clim[j0] + (1.0 - self.c_clim[j0]) * g;
            self.ta[self.front][c] = self.ta[back][c];
            self.tc[self.front][c] = self.tc[back][c];
        };
        // Then the clouds: 6 steps of four intervals (2.9 days), each after two wind steps.
        const spin: f32 = 4.0;
        self.departRows(0, DH, spin, false);
        for (0..6) |_| {
            self.front = 1 - self.front;
            self.dcur = 1 - self.dcur;
            self.advanceStorms();
            for (&self.storms) |*st| st.age += (spin - 1.0) * T_DAY; // plumes age at the real rate
            for (0..2) |_| self.coarseStep(true, 2.0);
            self.intervals += 4;
            self.dyeRows(0, DH, spin, false);
            self.departRows(0, DH, spin, false);
        }
        // the first live interval moves at the real rate
        self.departRows(0, DH, 1.0, false);
        self.cam = self.camTarget();
        self.tick();
        return self;
    }

    pub fn deinit(self: *State, alloc: std.mem.Allocator) void {
        alloc.destroy(self);
    }

    pub fn step(self: *State, dt: f64) void {
        self.time_sec += dt;
        self.tick();
    }

    // ------------------------------------------------------------------ setup

    fn setupTables(self: *State) void {
        for (0..NX / 2) |k| {
            const a = -2.0 * math.pi * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(NX));
            self.cosk[k] = @floatCast(@cos(a));
            self.sink[k] = @floatCast(@sin(a));
        }
        for (0..NX) |k| {
            const th = 2.0 * math.pi * @as(f64, @floatFromInt(k)) / @as(f64, @floatFromInt(NX));
            const dd: f64 = @as(f64, DXK);
            self.lam[k] = @floatCast((2.0 - 2.0 * @cos(th)) + dd * dd / (@as(f64, LD_KM) * @as(f64, LD_KM)));
        }
        // chromophore transmission: blue absorbed most (Beer-Lambert)
        for (0..256) |i| {
            const c: f32 = @as(f32, @floatFromInt(i)) / 255.0 * 1.2;
            self.trans[i] = .{ @exp(-0.40 * c), @exp(-1.75 * c), @exp(-3.2 * c) };
        }
        // linear [0, 1.25] -> sRGB
        for (0..1024) |i| {
            const l: f64 = @as(f64, @floatFromInt(i)) / 1023.0 * 1.25;
            const v: f64 = if (l <= 0.0031308) 12.92 * l else 1.055 * math.pow(f64, l, 1.0 / 2.4) - 0.055;
            self.srgb[i] = @intFromFloat(math.clamp(v, 0.0, 1.0) * 255.0 + 0.5);
        }
        // the colour model as a table: reflectance = (deep + (white - deep) * brightness) times
        // the chromophore's Beer-Lambert transmission (blue absorbed most), then sRGB
        const rd = [3]f32{ 0.19, 0.175, 0.165 };
        const rc = [3]f32{ 0.93, 0.90, 0.84 };
        const expo: f32 = 0.98;
        for (0..CL_A) |ia| {
            const a: f32 = @as(f32, @floatFromInt(ia)) / @as(f32, @floatFromInt(CL_A - 1)) * A_MAX;
            for (0..CL_C) |ic| {
                const ci: usize = ic * 255 / (CL_C - 1);
                const t = self.trans[ci];
                var lanes: u64 = 0;
                inline for (0..3) |ch| {
                    const refl = (rd[ch] + (rc[ch] - rd[ch]) * a) * t[ch] * expo;
                    const li: usize = @intFromFloat(math.clamp(refl * (1023.0 / 1.25), 0.0, 1023.0));
                    lanes |= @as(u64, self.srgb[li]) << @as(u6, @intCast(32 - 16 * ch));
                }
                self.clut[ia * CL_C + ic] = lanes;
            }
        }
        // band climatology on the tracer rows (latitude south, degrees)
        const bands = [_][3]f32{
            // lat S, brightness, chromophore
            .{ 5.0, 0.90, 0.07 }, // Equatorial Zone, south edge
            .{ 7.3, 0.86, 0.09 },
            .{ 8.8, 0.16, 0.50 }, // SEB north component
            .{ 11.5, 0.14, 0.52 },
            .{ 13.5, 0.34, 0.40 }, // SEB middle, a little lighter
            .{ 15.5, 0.14, 0.52 },
            .{ 18.3, 0.10, 0.58 }, // SEB south component, darkest
            .{ 19.8, 0.88, 0.035 }, // South Tropical Zone (the Red Spot Hollow)
            .{ 25.5, 0.90, 0.03 },
            .{ 27.0, 0.30, 0.24 }, // South Temperate Belt
            .{ 30.5, 0.28, 0.22 },
            .{ 32.0, 0.86, 0.04 }, // South Temperate Zone
            .{ 35.0, 0.84, 0.05 },
            .{ 36.5, 0.36, 0.20 }, // South South Temperate Belt
            .{ 39.0, 0.36, 0.20 },
        };
        for (0..DH) |j| {
            const lat = -self.latOfDyeRow(@floatFromInt(j));
            var k: usize = 0;
            while (k + 2 < bands.len and bands[k + 1][0] < lat) k += 1;
            const b0 = bands[k];
            const b1 = bands[k + 1];
            const t = math.clamp((lat - b0[0]) / (b1[0] - b0[0]), 0.0, 1.0);
            const s = t * t * (3.0 - 2.0 * t);
            self.a_clim[j] = b0[1] + (b1[1] - b0[1]) * s;
            self.c_clim[j] = b0[2] + (b1[2] - b0[2]) * s;
        }
    }

    fn latOfDyeRow(_: *const State, j: f32) f32 {
        const s_km = (j + 0.5) * (DXK * C_PER_D);
        return LAT_TOP - s_km / KM_PER_DEG;
    }

    fn setupBackground(self: *State) void {
        // zonal wind (m/s, + = eastward) at latitudes south (degrees)
        const kl = [_]f32{ 3.0, 6.5, 9.0, 12.0, 15.0, 17.5, 20.0, 22.0, 24.5, 27.0, 29.0, 31.5, 34.0, 36.5, 40.0 };
        const ku = [_]f32{ 90.0, 120.0, 60.0, 10.0, -35.0, -70.0, -35.0, 0.0, 60.0, 15.0, -20.0, 5.0, 30.0, -5.0, 20.0 };
        var raw: [NY]f32 = undefined;
        for (0..NY) |j| {
            const s_km = (@as(f32, @floatFromInt(j)) + 0.5) * DXK;
            const lat = -(LAT_TOP - s_km / KM_PER_DEG);
            var k: usize = 0;
            while (k + 2 < kl.len and kl[k + 1] < lat) k += 1;
            const t = math.clamp((lat - kl[k]) / (kl[k + 1] - kl[k]), 0.0, 1.0);
            raw[j] = (ku[k] + (ku[k + 1] - ku[k]) * t) * 86.4; // km/day
        }
        // 1-degree Gaussian smoothing (sigma ~ 5 rows), clamped ends
        const sig: f32 = KM_PER_DEG / DXK;
        for (0..NY) |j| {
            var acc: f32 = 0;
            var wsum: f32 = 0;
            var o: isize = -16;
            while (o <= 16) : (o += 1) {
                const jj: usize = @intCast(math.clamp(@as(isize, @intCast(j)) + o, 0, @as(isize, NY - 1)));
                const fo: f32 = @floatFromInt(o);
                const wgt = @exp(-0.5 * fo * fo / (sig * sig));
                acc += raw[jj] * wgt;
                wsum += wgt;
            }
            self.ubg[j] = acc / wsum;
        }
        // background PV: zeta + f with zeta = du/ds (s southward), f = 2 Omega sin(lat)
        for (0..NY) |j| {
            const jm = if (j == 0) 0 else j - 1;
            const jp = @min(j + 1, NY - 1);
            const ds: f32 = @as(f32, @floatFromInt(jp - jm)) * DXK;
            const zeta = (self.ubg[jp] - self.ubg[jm]) / ds;
            const s_km = (@as(f32, @floatFromInt(j)) + 0.5) * DXK;
            const lat = (LAT_TOP - s_km / KM_PER_DEG) * (math.pi / 180.0);
            self.qbg[j] = zeta + TWO_OMEGA * @sin(lat);
        }
    }

    fn grsShape(self: *const State, x: f32, y: f32) f32 {
        var ddx = x - self.gx;
        const n: f32 = @floatFromInt(NX);
        if (ddx > 0.5 * n) ddx -= n;
        if (ddx < -0.5 * n) ddx += n;
        const ex = ddx / GRS_A;
        const ey = (y - self.gy) / GRS_B;
        const r2 = ex * ex + ey * ey;
        const r8 = r2 * r2 * r2 * r2;
        return 1.0 / (1.0 + r8);
    }

    fn rnd(self: *State) f32 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 7;
        self.rng ^= self.rng << 17;
        return @as(f32, @floatFromInt(self.rng >> 40)) / 16777216.0;
    }

    // ------------------------------------------------------------------ PV model

    fn fft(re: *[NX]f32, im: *[NX]f32, cosk: *const [NX / 2]f32, sink: *const [NX / 2]f32, inverse: bool) void {
        // bit reversal
        var j: usize = 0;
        for (1..NX) |i| {
            var bit: usize = NX >> 1;
            while ((j & bit) != 0) : (bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) {
                std.mem.swap(f32, &re[i], &re[j]);
                std.mem.swap(f32, &im[i], &im[j]);
            }
        }
        var len: usize = 2;
        while (len <= NX) : (len <<= 1) {
            const half = len >> 1;
            const stride = NX / len;
            var s: usize = 0;
            while (s < NX) : (s += len) {
                for (0..half) |k| {
                    const wr = cosk[k * stride];
                    const wi = if (inverse) -sink[k * stride] else sink[k * stride];
                    const a = s + k;
                    const b = a + half;
                    const tr = re[b] * wr - im[b] * wi;
                    const ti = re[b] * wi + im[b] * wr;
                    re[b] = re[a] - tr;
                    im[b] = im[a] - ti;
                    re[a] += tr;
                    im[a] += ti;
                }
            }
        }
    }

    /// (lap - 1/Ld^2) psi = q, periodic in x, psi = 0 beyond the north and south rows.
    fn invert(self: *State) void {
        const d2 = DXK * DXK;
        for (0..NY) |j| {
            const re: *[NX]f32 = self.fre[j * NX ..][0..NX];
            const im: *[NX]f32 = self.fim[j * NX ..][0..NX];
            for (0..NX) |i| {
                re[i] = self.q[j * NX + i] * d2;
                im[i] = 0;
            }
            fft(re, im, &self.cosk, &self.sink, false);
        }
        // Thomas algorithm per wavenumber: psi[j-1] - (2 + lam) psi[j] + psi[j+1] = rhs[j]
        var cp: [NY]f32 = undefined;
        for (0..NX) |k| {
            const b = -(2.0 + self.lam[k]);
            cp[0] = 1.0 / b;
            self.fre[k] = self.fre[k] / b;
            self.fim[k] = self.fim[k] / b;
            for (1..NY) |j| {
                const m = 1.0 / (b - cp[j - 1]);
                cp[j] = m;
                self.fre[j * NX + k] = (self.fre[j * NX + k] - self.fre[(j - 1) * NX + k]) * m;
                self.fim[j * NX + k] = (self.fim[j * NX + k] - self.fim[(j - 1) * NX + k]) * m;
            }
            var j: usize = NY - 1;
            while (j > 0) {
                j -= 1;
                self.fre[j * NX + k] -= cp[j] * self.fre[(j + 1) * NX + k];
                self.fim[j * NX + k] -= cp[j] * self.fim[(j + 1) * NX + k];
            }
        }
        const inv_n: f32 = 1.0 / @as(f32, @floatFromInt(NX));
        for (0..NY) |j| {
            const re: *[NX]f32 = self.fre[j * NX ..][0..NX];
            const im: *[NX]f32 = self.fim[j * NX ..][0..NX];
            fft(re, im, &self.cosk, &self.sink, true);
            for (0..NX) |i| self.psi[j * NX + i] = re[i] * inv_n;
        }
        // velocities (km/day) -> PV cells per interval; u = +dpsi/ds, v_south = -dpsi/dx
        const k_cells = T_DAY / DXK;
        const inv2d = 1.0 / (2.0 * DXK);
        for (0..NY) |j| {
            for (0..NX) |i| {
                const ip = if (i + 1 == NX) 0 else i + 1;
                const im_ = if (i == 0) NX - 1 else i - 1;
                const pn: f32 = if (j == 0) 0 else self.psi[(j - 1) * NX + i];
                const ps: f32 = if (j + 1 == NY) 0 else self.psi[(j + 1) * NX + i];
                const u = (ps - pn) * inv2d + self.ubg[j];
                const v = -(self.psi[j * NX + ip] - self.psi[j * NX + im_]) * inv2d;
                self.cu[j * NX + i] = u * k_cells;
                self.cv[j * NX + i] = v * k_cells;
            }
        }
    }

    fn bilinC(f: *const [NC]f32, x: f32, y: f32) f32 {
        const n: f32 = @floatFromInt(NX);
        const xc = math.clamp(x, -n, 2.0 * n);
        const yc = math.clamp(y, 0.0, @as(f32, @floatFromInt(NY - 1)));
        const xf = @floor(xc);
        const yf = @floor(yc);
        const tx = xc - xf;
        const ty = yc - yf;
        const ix = wrapIdx(@intFromFloat(xf), NX);
        const ix1 = if (ix + 1 == NX) 0 else ix + 1;
        const iy: usize = @intFromFloat(yf);
        const iy1 = @min(iy + 1, NY - 1);
        const a = f[iy * NX + ix] + (f[iy * NX + ix1] - f[iy * NX + ix]) * tx;
        const b = f[iy1 * NX + ix] + (f[iy1 * NX + ix1] - f[iy1 * NX + ix]) * tx;
        return a + (b - a) * ty;
    }

    /// Total wind (PV cells per interval) at a PV-grid point, both components from one set of
    /// weights; away from the edges without wrap or clamp.
    fn windAt(self: *const State, x: f32, y: f32) [2]f32 {
        if (x >= 1.0 and x < @as(f32, @floatFromInt(NX - 2)) and y >= 0.0 and y < @as(f32, @floatFromInt(NY - 2))) {
            const xf = @floor(x);
            const yf = @floor(y);
            const tx = x - xf;
            const ty = y - yf;
            const p = @as(usize, @intFromFloat(yf)) * NX + @as(usize, @intFromFloat(xf));
            const ua = self.cu[p] + (self.cu[p + 1] - self.cu[p]) * tx;
            const ub = self.cu[p + NX] + (self.cu[p + NX + 1] - self.cu[p + NX]) * tx;
            const va = self.cv[p] + (self.cv[p + 1] - self.cv[p]) * tx;
            const vb = self.cv[p + NX] + (self.cv[p + NX + 1] - self.cv[p + NX]) * tx;
            return .{ ua + (ub - ua) * ty, va + (vb - va) * ty };
        }
        return .{ bilinC(&self.cu, x, y), bilinC(&self.cv, x, y) };
    }

    fn qbgAt(self: *const State, y: f32) f32 {
        const yc = math.clamp(y, 0.0, @as(f32, @floatFromInt(NY - 1)));
        const yf = @floor(yc);
        const iy: usize = @intFromFloat(yf);
        const iy1 = @min(iy + 1, NY - 1);
        return self.qbg[iy] + (self.qbg[iy1] - self.qbg[iy]) * (yc - yf);
    }

    /// One PV step over an interval: advect, force, invert, track the spot.
    fn coarseStep(self: *State, storms: bool, k: f32) void {
        const rate_e = k * T_DAY / TAU_E;
        const rate_z = k * T_DAY / TAU_Z;
        const rate_g = k * T_DAY / TAU_G;
        for (0..NY) |j| {
            const fy: f32 = @floatFromInt(j);
            for (0..NX) |i| {
                const fx: f32 = @floatFromInt(i);
                const c = j * NX + i;
                const mx = fx - 0.5 * k * self.cu[c];
                const my = fy - 0.5 * k * self.cv[c];
                const ux = bilinC(&self.cu, mx, my);
                const vy = bilinC(&self.cv, mx, my);
                const sx = fx - k * ux;
                const sy = fy - k * vy;
                var v = sampleCR(NX, NY, &self.q, sx, sy) + self.qbgAt(sy) - self.qbg[j];
                v -= v * rate_e;
                self.q2[c] = v;
            }
        }
        // zonal-mean damping keeps the jets; the nudge keeps the spot
        for (0..NY) |j| {
            var m: f32 = 0;
            for (0..NX) |i| m += self.q2[j * NX + i];
            m /= @as(f32, @floatFromInt(NX));
            const fy: f32 = @floatFromInt(j);
            for (0..NX) |i| {
                const c = j * NX + i;
                var v = self.q2[c] - m * rate_z;
                const g = self.grsShape(@floatFromInt(i), fy);
                if (g > 0.002) {
                    const reach = math.clamp(g * 4.0, 0.0, 1.0);
                    v += (GRS_Q * g - v) * rate_g * reach;
                }
                self.q[c] = v;
            }
        }
        const reps: usize = @intFromFloat(@max(1.0, @round(k * T_DAY / 0.06))); // rates are per 0.06 day
        for (0..reps) |_| {
            self.stir();
            if (storms) self.stormVortices();
        }
        self.invert();
        self.track();
        var sum: f32 = 0;
        for (self.q) |v| sum += v;
        if (!math.isFinite(sum)) self.bad = true;
        // anticyclone mask (chromophore production)
        for (0..NC) |c| {
            const t = math.clamp((self.q[c] - 0.38 * GRS_Q) / (0.20 * GRS_Q), 0.0, 1.0);
            self.red[c] = t * t * (3.0 - 2.0 * t);
        }
    }

    fn track(self: *State) void {
        // the spot is the streamfunction minimum near its last position
        var best: f32 = math.floatMax(f32);
        var bx: isize = 0;
        var by: isize = 0;
        const cx: isize = @intFromFloat(@round(self.gx));
        const cy: isize = @intFromFloat(@round(self.gy_obs));
        var oy: isize = -6;
        while (oy <= 6) : (oy += 1) {
            const y = math.clamp(cy + oy, 2, @as(isize, NY - 3));
            var ox: isize = -10;
            while (ox <= 10) : (ox += 1) {
                const x = wrapIdx(cx + ox, NX);
                const v = self.psi[@as(usize, @intCast(y)) * NX + x];
                if (v < best) {
                    best = v;
                    bx = cx + ox;
                    by = y;
                }
            }
        }
        // sub-cell refinement (parabola through neighbours)
        const yi: usize = @intCast(by);
        const xi = wrapIdx(bx, NX);
        const xl = self.psi[yi * NX + wrapIdx(bx - 1, NX)];
        const xr = self.psi[yi * NX + wrapIdx(bx + 1, NX)];
        const yu = self.psi[(yi - 1) * NX + xi];
        const yd = self.psi[(yi + 1) * NX + xi];
        const c0 = self.psi[yi * NX + xi];
        const denx = xl - 2.0 * c0 + xr;
        const deny = yu - 2.0 * c0 + yd;
        const offx: f32 = if (denx > 1e-6) math.clamp(0.5 * (xl - xr) / denx, -0.5, 0.5) else 0;
        const offy: f32 = if (deny > 1e-6) math.clamp(0.5 * (yu - yd) / deny, -0.5, 0.5) else 0;
        // follow it gently (the nudge must not chase eddies)
        var tx = @as(f32, @floatFromInt(bx)) + offx;
        const ty = @as(f32, @floatFromInt(by)) + offy;
        const n: f32 = @floatFromInt(NX);
        var d = tx - self.gx;
        if (d > 0.5 * n) d -= n;
        if (d < -0.5 * n) d += n;
        tx = self.gx + d * 0.25;
        if (tx < 0) tx += n;
        if (tx >= n) tx -= n;
        self.gx = tx;
        self.gy_obs = math.clamp(self.gy_obs + (ty - self.gy_obs) * 0.25, 0.3 * @as(f32, @floatFromInt(NY)), 0.7 * @as(f32, @floatFromInt(NY)));
    }

    /// A Gaussian PV blob (1/day) at PV-cell position (px, py), radius rc cells.
    fn addBlob(self: *State, px: f32, py: f32, rc: f32, amp: f32) void {
        const r_i: isize = @intFromFloat(@ceil(rc * 2.5));
        const cx: isize = @intFromFloat(@round(px));
        const cy: isize = @intFromFloat(@round(py));
        var oy: isize = -r_i;
        while (oy <= r_i) : (oy += 1) {
            const yy = cy + oy;
            if (yy < 0 or yy >= NY) continue;
            var ox: isize = -r_i;
            while (ox <= r_i) : (ox += 1) {
                const xx = cx + ox;
                const fdx = @as(f32, @floatFromInt(xx)) - px;
                const fdy = @as(f32, @floatFromInt(yy)) - py;
                const g = @exp(-(fdx * fdx + fdy * fdy) / (rc * rc));
                self.q[@as(usize, @intCast(yy)) * NX + wrapIdx(xx, NX)] += amp * g;
            }
        }
    }

    /// Small-scale stirring: convective eddies of both signs, mostly in the belts.
    fn stir(self: *State) void {
        for (0..3) |_| {
            const in_belt = self.rnd() < 0.75;
            const lat: f32 = if (in_belt)
                (if (self.rnd() < 0.6) 9.0 + 10.0 * self.rnd() else 26.5 + 4.0 * self.rnd())
            else
                7.0 + 30.0 * self.rnd();
            const py = dyeRowOfLat(lat) * C_PER_D;
            const px = self.rnd() * @as(f32, @floatFromInt(NX));
            const rc = (300.0 + 400.0 * self.rnd()) / DXK;
            const sgn: f32 = if (self.rnd() < 0.5) -1.0 else 1.0;
            self.addBlob(px, py, rc, sgn * (1.5 + 2.0 * self.rnd()));
        }
    }

    fn spawnStorm(self: *State, x: f32, lat: f32, rad_km: f32, life: f32, power: f32) void {
        for (&self.storms) |*s| {
            if (s.on) continue;
            s.* = .{
                .x = x,
                .y = dyeRowOfLat(lat),
                .rad = rad_km / (DXK * C_PER_D),
                .age = 0,
                .life = life,
                .power = power,
                .on = true,
            };
            // a small anticyclone at the plume top
            self.addBlob(s.x * C_PER_D, s.y * C_PER_D, s.rad * C_PER_D * 1.5, 2.0 * power);
            return;
        }
    }

    /// Convective plumes: vigorous ones in the SEB north-west of the spot (the wake), weaker ones
    /// anywhere along the SEB and STB.
    fn stormVortices(self: *State) void {
        const span = @as(f32, @floatFromInt(DW));
        if (self.rnd() < 0.35) {
            var x = self.gx / C_PER_D - (0.05 + 0.28 * self.rnd()) * span;
            if (x < 0) x += span;
            self.spawnStorm(x, 12.5 + 5.5 * self.rnd(), 350.0 + 350.0 * self.rnd(), 1.0 + 1.5 * self.rnd(), 1.0);
        }
        if (self.rnd() < 0.2) {
            const lat: f32 = if (self.rnd() < 0.65) 9.0 + 9.0 * self.rnd() else 27.0 + 3.5 * self.rnd();
            self.spawnStorm(self.rnd() * span, lat, 220.0 + 220.0 * self.rnd(), 0.6 + 0.9 * self.rnd(), 0.45);
        }
    }

    // ------------------------------------------------------------------ tracers

    fn redAt(self: *const State, i: f32, j: f32) f32 {
        return bilinC(&self.red, (i + 0.5) * C_PER_D - 0.5, (j + 0.5) * C_PER_D - 0.5);
    }

    /// Departure displacement for the next interval from the current wind (RK2), tracer rows [j0, j1).
    fn departRows(self: *State, j0: usize, j1: usize, mult: f32, fast: bool) void {
        const nxt = 1 - self.dcur;
        const k = mult / C_PER_D;
        for (j0..j1) |j| {
            const y = (@as(f32, @floatFromInt(j)) + 0.5) * C_PER_D - 0.5;
            for (0..DW) |i| {
                const x = (@as(f32, @floatFromInt(i)) + 0.5) * C_PER_D - 0.5;
                const va = self.windAt(x, y);
                const vb = if (fast) va else self.windAt(x - 0.5 * va[0], y - 0.5 * va[1]);
                const ub = vb[0];
                self.dx[nxt][j * DW + i] = @floatCast(math.clamp(ub * k, -D_MAX * mult, D_MAX * mult));
                self.dy[nxt][j * DW + i] = @floatCast(math.clamp(vb[1] * k, -D_MAX * mult, D_MAX * mult));
            }
        }
    }

    /// The next interval's tracers from the current ones, tracer rows [j0, j1).
    fn dyeRows(self: *State, j0: usize, j1: usize, mult: f32, fast: bool) void {
        const f = self.front;
        const b = 1 - f;
        const dc = self.dcur;
        const relax = mult * T_DAY / TAU_DYE;
        const redr = mult * T_DAY / TAU_RED;
        for (j0..j1) |j| {
            const fy: f32 = @floatFromInt(j);
            const a_cl = self.a_clim[j];
            const c_cl = self.c_clim[j];
            for (0..DW) |i| {
                const c = j * DW + i;
                const fx: f32 = @floatFromInt(i);
                const sx = fx - @as(f32, self.dx[dc][c]);
                const sy = fy - @as(f32, self.dy[dc][c]);
                const interior = mult <= 1.0 and j >= PAD and j + PAD < DH and i >= PAD and i + PAD < DW;
                var s = if (fast)
                    sampleBL2(DW, DH, &self.ta[f], &self.tc[f], sx, sy)
                else if (interior)
                    sampleCR2Interior(&self.ta[f], &self.tc[f], sx, sy)
                else
                    sampleCR2(DW, DH, &self.ta[f], &self.tc[f], sx, sy);
                // air trapped in an anticyclone keeps its own history (no band relaxation) and
                // reddens with time: colour tracks residence time, deepest in the core
                const g = self.redAt(fx, fy);
                const rl = relax * (1.0 - g);
                s[0] += (a_cl - s[0]) * rl;
                s[1] += (c_cl - s[1]) * rl;
                if (g > 0.0) {
                    s[1] += (1.15 - s[1]) * g * redr;
                    s[0] += (0.50 - s[0]) * g * redr;
                }
                self.ta[b][c] = s[0];
                self.tc[b][c] = s[1];
            }
            // convective plumes: fresh white ammonia cloud with no chromophore at the head, and a
            // ring of subsiding, cleared air around it where the deeper, darker cloud shows
            for (&self.storms) |*st| {
                if (!st.on) continue;
                const reach = st.rad * 2.6;
                const ddy = fy - st.y;
                if (@abs(ddy) > reach) continue;
                const strength = plumeStrength(st);
                if (strength <= 0) continue;
                const xa: isize = @intFromFloat(@floor(st.x - reach));
                const xb: isize = @intFromFloat(@ceil(st.x + reach));
                var xx = xa;
                while (xx <= xb) : (xx += 1) {
                    const ddx = @as(f32, @floatFromInt(xx)) - st.x;
                    const r2 = (ddx * ddx + ddy * ddy) / (st.rad * st.rad);
                    if (r2 > 6.76) continue;
                    const c = j * DW + wrapIdx(xx, DW);
                    inject(&self.ta[b][c], &self.tc[b][c], r2, strength, c_cl);
                }
            }
        }
    }

    /// The plume's footprint at display phase `phase`, centred where it is now. mode 0 stores
    /// the displayed tracers, 1 adds phase x the injection the next stored state will contain,
    /// 2 recolours. The boundary then lands on the same picture: no 1-second pulse.
    fn plumeDisplay(self: *State, st: *const Storm, phase: f32, mode: u8) void {
        const strength = plumeStrength(st) * phase;
        const cx = st.x - (1.0 - phase) * st.vx;
        const cy = st.y - (1.0 - phase) * st.vy;
        const reach = st.rad * 2.6;
        const ya: isize = @max(0, @as(isize, @intFromFloat(@floor(cy - reach))));
        const yb: isize = @min(@as(isize, DH - 1), @as(isize, @intFromFloat(@ceil(cy + reach))));
        const xa: isize = @intFromFloat(@floor(cx - reach));
        const xb: isize = @intFromFloat(@ceil(cx + reach));
        const ka: f32 = @as(f32, @floatFromInt(CL_A - 1)) / A_MAX;
        const kc: f32 = @as(f32, @floatFromInt(CL_C - 1)) / C_MAX;
        const lod: isize = @intCast(self.lod);
        var yy = @divFloor(ya + lod - 1, lod) * lod; // only the shaded cells: the lod lattice
        while (yy <= yb) : (yy += lod) {
            const j: usize = @intCast(yy);
            const fy: f32 = @floatFromInt(yy);
            var xx = @divFloor(xa, lod) * lod;
            while (xx <= xb) : (xx += lod) {
                const ddx = @as(f32, @floatFromInt(xx)) - cx;
                const ddy = fy - cy;
                const r2 = (ddx * ddx + ddy * ddy) / (st.rad * st.rad);
                if (r2 > 6.76) continue;
                const i = wrapIdx(xx, DW);
                const c = j * DW + i;
                switch (mode) {
                    0 => {
                        const s = sampleBL2(DW, DH, &self.ta[self.front], &self.tc[self.front], @as(f32, @floatFromInt(i)) - phase * @as(f32, self.dx[self.dcur][c]), fy - phase * @as(f32, self.dy[self.dcur][c]));
                        self.pa[c] = s[0];
                        self.pc[c] = s[1];
                    },
                    1 => inject(&self.pa[c], &self.pc[c], r2, strength, self.c_clim[j]),
                    else => {
                        const ia: usize = @intFromFloat(math.clamp(self.pa[c] * ka + 0.5, 0.0, @as(f32, @floatFromInt(CL_A - 1))));
                        const ic: usize = @intFromFloat(math.clamp(self.pc[c] * kc + 0.5, 0.0, @as(f32, @floatFromInt(CL_C - 1))));
                        self.col[c] = self.clut[ia * CL_C + ic];
                    },
                }
            }
        }
    }

    fn advanceStorms(self: *State) void {
        for (&self.storms) |*st| {
            if (!st.on) continue;
            st.age += T_DAY;
            if (st.age >= st.life) {
                st.on = false;
                continue;
            }
            const yi: usize = @intFromFloat(math.clamp(@round(st.y), 0.0, @as(f32, @floatFromInt(DH - 1))));
            const xi = wrapIdx(@intFromFloat(@round(st.x)), DW);
            st.vx = self.dx[self.dcur][yi * DW + xi];
            st.vy = self.dy[self.dcur][yi * DW + xi];
            st.x += st.vx;
            st.y += st.vy;
            const span: f32 = @floatFromInt(DW);
            if (st.x < 0) st.x += span;
            if (st.x >= span) st.x -= span;
            st.y = math.clamp(st.y, 0.0, @as(f32, @floatFromInt(DH - 1)));
        }
    }

    /// Start of an interval: the back tracers and departure field become current; PV steps.
    fn boundary(self: *State) void {
        self.front = 1 - self.front;
        self.dcur = 1 - self.dcur;
        self.advanceStorms();
        self.coarseStep(true, 1.0);
        self.intervals += 1;
    }

    fn tick(self: *State) void {
        if (self.tk == 0) self.boundary();
        const r0 = self.tk * DH / TICKS;
        const r1 = (self.tk + 1) * DH / TICKS;
        self.dyeRows(r0, r1, 1.0, false);
        self.departRows(r0, r1, 1.0, false);
        const phase = @as(f32, @floatFromInt(self.tk)) / @as(f32, @floatFromInt(TICKS));
        self.shade(phase);
        self.updateCamera();
        self.tk += 1;
        if (self.tk == TICKS) self.tk = 0;
    }

    // ------------------------------------------------------------------ display

    fn shade(self: *State, phase: f32) void {
        const ta = &self.ta[self.front];
        const tc = &self.tc[self.front];
        const ddx = &self.dx[self.dcur];
        const ddy = &self.dy[self.dcur];
        const ka: f32 = @as(f32, @floatFromInt(CL_A - 1)) / A_MAX;
        const kc: f32 = @as(f32, @floatFromInt(CL_C - 1)) / C_MAX;
        const top_a: f32 = @floatFromInt(CL_A - 1);
        const top_c: f32 = @floatFromInt(CL_C - 1);
        const lod = self.lod;
        var j: usize = 0;
        while (j < DH) : (j += lod) {
            const fy: f32 = @floatFromInt(j);
            const inner_row = j >= PAD and j + PAD < DH;
            var i: usize = 0;
            while (i < DW) : (i += lod) {
                const c = j * DW + i;
                const fx: f32 = @floatFromInt(i);
                const x = fx - phase * @as(f32, ddx[c]);
                const y = fy - phase * @as(f32, ddy[c]);
                var s: [2]f32 = undefined;
                if (inner_row and i >= PAD and i + PAD < DW) {
                    // |displacement| <= D_MAX < PAD: the 2x2 footprint is inside the grid
                    const xf = @floor(x);
                    const yf = @floor(y);
                    const tx = x - xf;
                    const ty = y - yf;
                    const ix: usize = @intFromFloat(xf);
                    const iy: usize = @intFromFloat(yf);
                    const p = iy * DW + ix;
                    const a0 = ta[p] + (ta[p + 1] - ta[p]) * tx;
                    const a1 = ta[p + DW] + (ta[p + DW + 1] - ta[p + DW]) * tx;
                    const b0 = tc[p] + (tc[p + 1] - tc[p]) * tx;
                    const b1 = tc[p + DW] + (tc[p + DW + 1] - tc[p + DW]) * tx;
                    s = .{ a0 + (a1 - a0) * ty, b0 + (b1 - b0) * ty };
                } else {
                    s = sampleBL2(DW, DH, ta, tc, x, y);
                }
                const ia: usize = @intFromFloat(math.clamp(s[0] * ka + 0.5, 0.0, top_a));
                const ic: usize = @intFromFloat(math.clamp(s[1] * kc + 0.5, 0.0, top_c));
                self.col[c] = self.clut[ia * CL_C + ic];
            }
        }
        if (phase > 0) {
            for (0..3) |mode| {
                for (&self.storms) |*st| {
                    if (st.on and plumeStrength(st) > 0) self.plumeDisplay(st, phase, @intCast(mode));
                }
            }
        }
    }

    fn camTarget(self: *const State) f32 {
        const view_w = @as(f32, @floatFromInt(self.w)) * self.viewScale();
        var t = self.gx / C_PER_D - 0.62 * view_w;
        const span: f32 = @floatFromInt(DW);
        while (t < 0) t += span;
        while (t >= span) t -= span;
        return t;
    }

    fn viewScale(self: *const State) f32 {
        const sx = @as(f32, @floatFromInt(DW)) / @as(f32, @floatFromInt(self.w));
        const sy = @as(f32, @floatFromInt(DH)) / @as(f32, @floatFromInt(self.h));
        return @min(sx, sy);
    }

    fn updateCamera(self: *State) void {
        const span: f32 = @floatFromInt(DW);
        var d = self.camTarget() - self.cam;
        if (d > 0.5 * span) d -= span;
        if (d < -0.5 * span) d += span;
        self.cam += d * 0.002;
        if (self.cam < 0) self.cam += span;
        if (self.cam >= span) self.cam -= span;
        const sc = self.viewScale();
        self.view_sc = sc;
        self.view_oy = (@as(f32, @floatFromInt(DH)) - @as(f32, @floatFromInt(self.h)) * sc) * 0.5;
        // sample the shaded cells: every lod-th column and row
        const lod = self.lod;
        const lf: f32 = @floatFromInt(lod);
        for (0..self.w) |x| {
            var sx = self.cam + (@as(f32, @floatFromInt(x)) + 0.5) * sc - 0.5;
            while (sx < 0) sx += span;
            while (sx >= span) sx -= span;
            const u = sx / lf;
            const fl = @floor(u);
            const ix: usize = @min(@as(usize, @intFromFloat(fl)) * lod, DW - lod);
            self.colx0[x] = @intCast(ix);
            self.colx1[x] = @intCast(if (ix + lod >= DW) 0 else ix + lod);
            self.colw[x] = @intFromFloat(math.clamp((u - fl) * 256.0, 0.0, 256.0));
        }
        for (0..self.h) |y| {
            const sy = math.clamp(self.view_oy + (@as(f32, @floatFromInt(y)) + 0.5) * sc - 0.5, 0.0, @as(f32, @floatFromInt(DH - lod)));
            const v = sy / lf;
            const fl = @floor(v);
            const j0: usize = @min(@as(usize, @intFromFloat(fl)) * lod, DH - lod);
            self.rowy0[y] = @intCast(j0);
            self.rowy1[y] = @intCast(@min(j0 + lod, DH - lod));
            self.roww[y] = @intFromFloat(math.clamp((v - fl) * 256.0, 0.0, 256.0));
        }
    }

    pub fn draw(self: *const State, buf: []u32, stride: usize) void {
        const w = self.w;
        const h = self.h;
        const mask: u64 = 0x00FF_00FF_00FF;
        var tmp: [DW]u64 = undefined;
        // exactly 2x (1920x1200 from 960x600): stream a row rotated to the camera, no gathers
        const two_x = self.lod == 1 and self.view_sc == 0.5 and w % 2 == 0 and w / 2 + 2 <= DW;
        var rot: [DW + 2]u64 = undefined;
        const base: usize = self.colx0[0];
        const w_even: u64 = self.colw[0];
        const w_odd: u64 = if (w > 1) self.colw[1] else 0;
        const odd_shift: usize = if (w > 1 and self.colx0[1] != self.colx0[0]) 1 else 0;
        for (0..h) |y| {
            if (y * stride + w > buf.len) return;
            const j0: usize = self.rowy0[y];
            const j1: usize = self.rowy1[y];
            const wy: u64 = self.roww[y];
            const r0 = self.col[j0 * DW ..][0..DW];
            const r1 = self.col[j1 * DW ..][0..DW];
            const dst = buf[y * stride ..][0..w];
            if (two_x) {
                const n = w / 2 + 2;
                for (0..n) |k| {
                    var s = base + k;
                    if (s >= DW) s -= DW;
                    rot[k] = ((r0[s] * (256 - wy) + r1[s] * wy) >> 8) & mask;
                }
                for (0..w / 2) |k| {
                    const ve = ((rot[k] * (256 - w_even) + rot[k + 1] * w_even) >> 8) & mask;
                    const vo = ((rot[k + odd_shift] * (256 - w_odd) + rot[k + odd_shift + 1] * w_odd) >> 8) & mask;
                    dst[2 * k] = packLanes(ve);
                    dst[2 * k + 1] = packLanes(vo);
                }
                continue;
            }
            for (&tmp, r0, r1) |*t, a, b| t.* = ((a * (256 - wy) + b * wy) >> 8) & mask;
            for (dst, 0..) |*d, x| {
                const wx: u64 = self.colw[x];
                const v = ((tmp[self.colx0[x]] * (256 - wx) + tmp[self.colx1[x]] * wx) >> 8) & mask;
                const r: u32 = @truncate(v >> 32);
                const g: u32 = @truncate(v >> 16);
                const bl: u32 = @truncate(v);
                d.* = 0xFF00_0000 | ((bl & 0xFF) << 16) | ((g & 0xFF) << 8) | (r & 0xFF);
            }
        }
    }

    pub fn hasNaN(self: *const State) bool {
        return self.bad or !math.isFinite(self.time_sec) or !math.isFinite(self.gx) or !math.isFinite(self.cam);
    }

    // ------------------------------------------------------------------ checks

    /// Collar speed (m/s, max over the ring 0.7-1.3 of the spot's size, relative to the spot) and
    /// circulation period (days) along the collar ellipse (1.0).
    pub fn grsStats(self: *const State) [2]f32 {
        const to_ms = DXK / T_DAY / 86.4; // PV cells per interval -> m/s
        var vmax: f32 = 0;
        for (0..NY) |j| for (0..NX) |i| {
            var ddx = @as(f32, @floatFromInt(i)) - self.gx;
            const n: f32 = @floatFromInt(NX);
            if (ddx > 0.5 * n) ddx -= n;
            if (ddx < -0.5 * n) ddx += n;
            const ex = ddx / GRS_A;
            const ey = (@as(f32, @floatFromInt(j)) - self.gy) / GRS_B;
            const r = @sqrt(ex * ex + ey * ey);
            if (r < 0.7 or r > 1.3) continue;
            const c = j * NX + i;
            const sp = @sqrt(self.cu[c] * self.cu[c] + self.cv[c] * self.cv[c]) * to_ms;
            vmax = @max(vmax, sp);
        };
        // circulation time around the collar ellipse
        var period: f32 = 0;
        const nseg: usize = 128;
        for (0..nseg) |k| {
            const th0 = 2.0 * math.pi * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(nseg));
            const th1 = 2.0 * math.pi * @as(f32, @floatFromInt(k + 1)) / @as(f32, @floatFromInt(nseg));
            const x0 = self.gx + 1.0 * GRS_A * @cos(th0);
            const y0 = self.gy + 1.0 * GRS_B * @sin(th0);
            const x1 = self.gx + 1.0 * GRS_A * @cos(th1);
            const y1 = self.gy + 1.0 * GRS_B * @sin(th1);
            const tx = x1 - x0;
            const ty = y1 - y0;
            const len = @sqrt(tx * tx + ty * ty);
            const u = bilinC(&self.cu, 0.5 * (x0 + x1), 0.5 * (y0 + y1));
            const v = bilinC(&self.cv, 0.5 * (x0 + x1), 0.5 * (y0 + y1));
            // screen y points south, so counterclockwise on screen is decreasing theta here
            const along = -(u * tx + v * ty) / @max(len, 1e-6);
            period += len / @max(along, 1e-3) * T_DAY;
        }
        return .{ vmax, period };
    }
};

/// R<<32 | G<<16 | B lanes -> Argus's 0xFF_BB_GG_RR word.
inline fn packLanes(v: u64) u32 {
    const r: u32 = @truncate((v >> 32) & 0xFF);
    const g: u32 = @truncate((v >> 16) & 0xFF);
    const b: u32 = @truncate(v & 0xFF);
    return 0xFF00_0000 | (b << 16) | (g << 8) | r;
}

/// Periodic index for i in [-n, 2n) (every caller clamps to that), without a division.
inline fn wrapIdx(i: isize, n: usize) usize {
    const ni: isize = @intCast(n);
    var k = i;
    if (k < 0) k += ni;
    if (k >= ni) k -= ni;
    return @intCast(math.clamp(k, 0, ni - 1));
}

inline fn crw(p0: f32, p1: f32, p2: f32, p3: f32, t: f32) f32 {
    const t2 = t * t;
    const t3 = t2 * t;
    return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3);
}

/// Catmull-Rom, periodic in x, clamped in y, limited to the central 2x2 range (no overshoot).
fn sampleCR(comptime W: usize, comptime H: usize, f: *const [W * H]f32, x: f32, y: f32) f32 {
    const wf: f32 = @floatFromInt(W);
    const xc = math.clamp(x, -wf, 2.0 * wf);
    const yc = math.clamp(y, 0.0, @as(f32, @floatFromInt(H - 1)));
    const xf = @floor(xc);
    const yf = @floor(yc);
    const tx = xc - xf;
    const ty = yc - yf;
    const ix: isize = @intFromFloat(xf);
    const iy: isize = @intFromFloat(yf);
    var xs: [4]usize = undefined;
    inline for (0..4) |k| xs[k] = wrapIdx(ix - 1 + @as(isize, k), W);
    var rows: [4]f32 = undefined;
    var lo: f32 = math.floatMax(f32);
    var hi: f32 = -math.floatMax(f32);
    inline for (0..4) |r| {
        const jj: usize = @intCast(math.clamp(iy - 1 + @as(isize, r), 0, @as(isize, H - 1)));
        const row = f[jj * W ..][0..W];
        rows[r] = crw(row[xs[0]], row[xs[1]], row[xs[2]], row[xs[3]], tx);
        if (r == 1 or r == 2) {
            lo = @min(lo, @min(row[xs[1]], row[xs[2]]));
            hi = @max(hi, @max(row[xs[1]], row[xs[2]]));
        }
    }
    return math.clamp(crw(rows[0], rows[1], rows[2], rows[3], ty), lo, hi);
}

/// The same for two fields sampled at one point.
fn sampleCR2(comptime W: usize, comptime H: usize, fa: *const [W * H]f32, fb: *const [W * H]f32, x: f32, y: f32) [2]f32 {
    const wf: f32 = @floatFromInt(W);
    const xc = math.clamp(x, -wf, 2.0 * wf);
    const yc = math.clamp(y, 0.0, @as(f32, @floatFromInt(H - 1)));
    const xf = @floor(xc);
    const yf = @floor(yc);
    const tx = xc - xf;
    const ty = yc - yf;
    const ix: isize = @intFromFloat(xf);
    const iy: isize = @intFromFloat(yf);
    var xs: [4]usize = undefined;
    inline for (0..4) |k| xs[k] = wrapIdx(ix - 1 + @as(isize, k), W);
    var out: [2]f32 = undefined;
    inline for (0..2) |q| {
        const f = if (q == 0) fa else fb;
        var rows: [4]f32 = undefined;
        var lo: f32 = math.floatMax(f32);
        var hi: f32 = -math.floatMax(f32);
        inline for (0..4) |r| {
            const jj: usize = @intCast(math.clamp(iy - 1 + @as(isize, r), 0, @as(isize, H - 1)));
            const row = f[jj * W ..][0..W];
            rows[r] = crw(row[xs[0]], row[xs[1]], row[xs[2]], row[xs[3]], tx);
            if (r == 1 or r == 2) {
                lo = @min(lo, @min(row[xs[1]], row[xs[2]]));
                hi = @max(hi, @max(row[xs[1]], row[xs[2]]));
            }
        }
        out[q] = math.clamp(crw(rows[0], rows[1], rows[2], rows[3], ty), lo, hi);
    }
    return out;
}

/// sampleCR2 on the tracer grid for a point whose 4x4 footprint is inside it (the caller checks:
/// |displacement| <= D_MAX and the cell is >= PAD from every edge): no wrap, no clamp.
fn sampleCR2Interior(fa: *const [ND]f32, fb: *const [ND]f32, x: f32, y: f32) [2]f32 {
    const xf = @floor(x);
    const yf = @floor(y);
    const tx = x - xf;
    const ty = y - yf;
    const ix: usize = @intFromFloat(xf);
    const iy: usize = @intFromFloat(yf);
    const p = (iy - 1) * DW + ix - 1;
    var out: [2]f32 = undefined;
    inline for (0..2) |q| {
        const f = if (q == 0) fa else fb;
        var rows: [4]f32 = undefined;
        inline for (0..4) |r| {
            const o = p + r * DW;
            rows[r] = crw(f[o], f[o + 1], f[o + 2], f[o + 3], tx);
        }
        const c0 = p + DW + 1;
        const lo = @min(@min(f[c0], f[c0 + 1]), @min(f[c0 + DW], f[c0 + DW + 1]));
        const hi = @max(@max(f[c0], f[c0 + 1]), @max(f[c0 + DW], f[c0 + DW + 1]));
        out[q] = math.clamp(crw(rows[0], rows[1], rows[2], rows[3], ty), lo, hi);
    }
    return out;
}

/// Bilinear, two fields, periodic in x, clamped in y.
inline fn sampleBL2(comptime W: usize, comptime H: usize, fa: *const [W * H]f32, fb: *const [W * H]f32, x: f32, y: f32) [2]f32 {
    const wf: f32 = @floatFromInt(W);
    const xc = math.clamp(x, -wf, 2.0 * wf);
    const yc = math.clamp(y, 0.0, @as(f32, @floatFromInt(H - 1)));
    const xf = @floor(xc);
    const yf = @floor(yc);
    const tx = xc - xf;
    const ty = yc - yf;
    const ix = wrapIdx(@intFromFloat(xf), W);
    const ix1 = if (ix + 1 == W) 0 else ix + 1;
    const iy: usize = @intFromFloat(yf);
    const iy1 = @min(iy + 1, H - 1);
    const a0 = fa[iy * W + ix] + (fa[iy * W + ix1] - fa[iy * W + ix]) * tx;
    const a1 = fa[iy1 * W + ix] + (fa[iy1 * W + ix1] - fa[iy1 * W + ix]) * tx;
    const b0 = fb[iy * W + ix] + (fb[iy * W + ix1] - fb[iy * W + ix]) * tx;
    const b1 = fb[iy1 * W + ix] + (fb[iy1 * W + ix1] - fb[iy1 * W + ix]) * tx;
    return .{ a0 + (a1 - a0) * ty, b0 + (b1 - b0) * ty };
}

comptime {
    sdk.exportTheme(State);
}

fn grsLatS(st: *const State) f32 {
    return -(LAT_TOP - (st.gy_obs + 0.5) * DXK / KM_PER_DEG);
}

test "the spot's collar speed and circulation period after two minutes" {
    const st = try State.init(std.testing.allocator, 320, 200, 1.0);
    defer st.deinit(std.testing.allocator);
    for (0..30 * 120) |_| st.step(0.008);
    const s = st.grsStats();
    try std.testing.expect(!st.hasNaN());
    try std.testing.expect(sdk.ledger(.{
        .id = "redspot.collar_speed",
        .claim = "the simulated spot's collar wind matches the observed edge winds",
        .reference = "edge winds peak near 432 km/h = 120 m/s (en.wikipedia.org/wiki/Great_Red_Spot)",
        .conditions = "after init spin-up and 120 wall seconds; max over 0.7-1.3 of the spot's ellipse",
        .quantity = "max wind speed, m/s",
        .measured = s[0],
        .lo = 100.0,
        .hi = 140.0,
        .source = "themes/Opus55_RedSpot.zig grsStats",
    }));
    try std.testing.expect(sdk.ledger(.{
        .id = "redspot.circulation_period",
        .claim = "the collar circulates in days, the same order as observed; slower than the 2008 value",
        .reference = "about 4.5 days as of 2008 (en.wikipedia.org/wiki/Great_Red_Spot)",
        .conditions = "line integral of ds / v_tangential around the spot's 16,000 x 11,000 km ellipse",
        .quantity = "circulation period, Jovian days",
        .measured = s[1],
        .lo = 3.0,
        .hi = 10.0,
        .source = "themes/Opus55_RedSpot.zig grsStats",
    }));
    try std.testing.expect(sdk.ledger(.{
        .id = "redspot.latitude",
        .claim = "the spot stays at ~22 S, held by the jets",
        .reference = "about 22 S, varying by about a degree (en.wikipedia.org/wiki/Great_Red_Spot)",
        .conditions = "after 120 wall seconds",
        .quantity = "latitude of the streamfunction minimum, degrees south",
        .measured = grsLatS(st),
        .lo = 20.0,
        .hi = 24.0,
        .source = "themes/Opus55_RedSpot.zig track",
    }));
}

test "the wind stays alive and bounded for an hour of wall time" {
    const st = try State.init(std.testing.allocator, 320, 200, 1.0);
    defer st.deinit(std.testing.allocator);
    // the PV model alone, one step per wall second (the tracers are bounded by relaxation)
    for (0..1800) |_| {
        st.advanceStorms();
        st.coarseStep(true, 1.0);
    }
    const s = st.grsStats();
    try std.testing.expect(!st.hasNaN());
    try std.testing.expect(sdk.ledger(.{
        .id = "redspot.one_hour",
        .claim = "after an hour on screen (216 Jovian days) the spot still spins at observed speeds",
        .reference = "edge winds ~120 m/s (en.wikipedia.org/wiki/Great_Red_Spot)",
        .conditions = "1800 PV steps of 0.12 day with storms",
        .quantity = "max collar wind speed, m/s",
        .measured = s[0],
        .lo = 90.0,
        .hi = 150.0,
        .source = "themes/Opus55_RedSpot.zig coarseStep",
    }));
    try std.testing.expect(sdk.ledger(.{
        .id = "redspot.one_hour_latitude",
        .claim = "after an hour the spot is still at ~22 S",
        .reference = "about 22 S (en.wikipedia.org/wiki/Great_Red_Spot)",
        .conditions = "1800 PV steps of 0.12 day with storms",
        .quantity = "latitude of the streamfunction minimum, degrees south",
        .measured = grsLatS(st),
        .lo = 20.0,
        .hi = 24.0,
        .source = "themes/Opus55_RedSpot.zig track",
    }));
}

test "no size assumptions: odd, small, wide, tall and Retina frames draw every pixel opaque" {
    const sizes = [_][2]usize{ .{ 1, 1 }, .{ 7, 3 }, .{ 320, 200 }, .{ 1440, 900 }, .{ 1921, 1080 }, .{ 900, 1600 }, .{ 3024, 1964 } };
    for (sizes) |sz| {
        const st = try State.init(std.testing.allocator, sz[0], sz[1], 2.0);
        defer st.deinit(std.testing.allocator);
        const stride = sz[0] + 5;
        const buf = try std.testing.allocator.alloc(u32, stride * sz[1]);
        defer std.testing.allocator.free(buf);
        @memset(buf, 0);
        for (0..40) |_| st.step(0.008);
        st.draw(buf, stride);
        for (0..sz[1]) |y| for (0..sz[0]) |x| {
            try std.testing.expect(buf[y * stride + x] >> 24 == 0xFF);
        };
        for (0..sz[1]) |y| for (sz[0]..stride) |x| {
            try std.testing.expect(buf[y * stride + x] == 0);
        };
    }
}

test "init alone (time it: the watchdog probe repeats it under a 10 s limit)" {
    const st = try State.init(std.testing.allocator, 320, 200, 1.0);
    defer st.deinit(std.testing.allocator);
    try std.testing.expect(!st.hasNaN());
}

// AVENTURINE HOROSCOPE // themes/Aventurine_Horoscope.metal
// Claude (Anthropic), 2026-10-19.
//
// What you see: the sky right now, read the way Western astrology reads it, made as one piece of
// jewellery. An astrology chart wheel (0 deg Aries at 9 o'clock, the signs counter-clockwise) in
// blue aventurine glass, with a ring of translucent enamel over guilloche, rose gold and a gem for
// each body, photographed straight on under a softbox. Each gem stands at its body's real place in
// the zodiac (a gold leader runs to the exact degree), with its glyph, its degree and sign (floored,
// as ephemerides print them), a garnet R-x while it is retrograde, and the next event within 7 days:
// "-> (sign) 5h" enters a sign, "SR 4d" / "SD 5d" stations retrograde / direct (hours under a day,
// else days). Enamel threads in the centre join bodies in a major aspect (garnet: square, opposition;
// sapphire: sextile, trine, which share a colour). The Moon in the middle is the real Moon at its real
// phase, its phase name and sign engraved beneath. It moves at the sky's pace: the Moon's gem
// ~0.5 deg an hour, the labels count down; the studio light drifts so the crystals in the glass glint.
// 30 s after it loads, and every 5 minutes after that, it looks ahead: the dial winds 30 days forward (14 s), holds 3 s and returns to
// now (5 s), marked "Preview" with the local date shown, so the coming weeks' retrograde loops,
// ingresses and lunar phases play out; event countdowns hide while it does.
// The astronomy is computed; the signs, aspects and their meanings are astrology's tradition, shown
// here as that tradition draws them and not claimed as physics.
//
// Sources ([cited] page read, [data] dataset, [looked at] image):
//   - JPL Solar System Dynamics, "Approximate Positions of the Planets" (E. M. Standish & J. G.
//     Williams), Table 1, valid 1800-2050 [cited, data]: Keplerian elements and rates for Mercury to
//     Neptune and the Earth-Moon barycentre; Pluto from the same table before JPL removed it (2015
//     copy) -> every planet's heliocentric position, by JPL's own recipe.
//   - J. Meeus, Astronomical Algorithms (2nd ed.), ch. 47 (all 60 + 60 terms of the ELP-2000/82
//     truncation), ch. 22 (nutation, 4 terms), ch. 48 (phase angle) [data: tables cross-checked
//     against the PyMeeus source] -> the Moon, nutation, the illuminated fraction.
//   - Tropical zodiac: 30 deg signs from the March equinox of date [cited by the research agent: Wikipedia "Zodiac"].
//   - Glyphs: Noto Sans Symbols, Noto Sans Symbols 2, Noto Sans, Noto Serif (SIL OFL 1.1; Copyright
//     2022 The Noto Project Authors) -> the atlas in Aventurine_Horoscope.bin; licence and credits in
//     Aventurine_Horoscope_OFL.txt. Uranus as the H monogram and Pluto as the bident, as astrologers
//     draw them; stations written SR / SD as in printed ephemerides [cited, via the research notes].
//   - The Moon's face: NASA Scientific Visualization Studio, CGI Moon Kit (svs.gsfc.nasa.gov/4720;
//     LRO LROC WAC colour mosaic; visualizer Ernie Wright) [data], 512x256 in the .bin.
//   - Look: Van Cleef & Arpels Midnight Planetarium (aventurine, gem planets, rose gold), the Prague
//     Orloj (gilt glyphs on blue), Jens Olsen's World Clock (guilloche) [looked at, Wikimedia Commons].
// COMPUTED (every tick, in argus_step; nothing tuned by eye):
//   - apparent geocentric ecliptic longitude and latitude of date of the Sun, Moon and Mercury to
//     Pluto, from the real UTC date (f.days_j2000 + f.day_frac) + TT-UTC 69.184 s: Kepler's equation,
//     light-time (2 iterations), Earth = barycentre - Moon/82.3, general precession in longitude (IAU
//     2006), nutation in longitude, annual aberration. Whole days go through exact 32-bit modular
//     arithmetic so float32 keeps the Moon to ~1";
//   - retrograde: the longitude falling over the surrounding 24 h; the flag flips when that rate
//     passes +-6e-5 deg/day (float32 noise stays below it) or when the latched station passes;
//   - the next ingress or station: 216 hourly samples (-24 h to +191 h); an ingress interpolated
//     linearly, a station as the zero of a least-squares line through the daily rate; the event is
//     latched as an absolute time and kept while fresh estimates agree within 3 h, so a slow
//     planet's countdown can't wander; a station's kind (SR / SD) follows the current retrograde state;
//   - major aspects 60/90/120/180 deg within orb; the Moon's elongation and illuminated fraction
//     (Meeus 48.3, with distances); the medallion lit at that phase angle on the Moon's east limb
//     while waxing and west limb while waning (the map turns half a revolution over the ~1.6 days
//     around full and new Moon, so it never flips), the map's near side facing us.
// CHOSEN (taste, not measured):
//   - the chart's layout: Aries at 9 o'clock with no Ascendant (the viewer's place is unknown);
//     gems spread to >= 14 deg apart when they crowd (a leader shows the true degree), eased 0.5 s;
//     orbs 6 deg with the Sun or Moon, else 4; no conjunction threads; events shown within 7 days
//     (hours below 23.5 h, rounded up; else whole days); the gem for each body (VCA's set where it has one: serpentine,
//     chloromelanite, red jasper, blue agate, sugilite; aquamarine, lapis, smoky quartz for the
//     outer three), a gold Sun, a mother-of-pearl Moon;
//   - the studio: a camera 4 dial radii above the centre (so each pixel sees the lights from its own
//     angle); a key softbox upper left (a bright core in a softer diffuser) drifting +-6 deg (periods
//     96, 240 and 150 s, so the 4 h clock wrap is seamless); a wide cool fill softbox right; a light
//     tent with seams, darker toward the horizon, and a dark lens port; four room lamps low on the
//     horizon at irregular azimuths, widths and strengths; every light an area, widened by the lobe
//     (never point-sampled); every colour, roughness and exposure;
//   - materials: Fresnel integrated over the GGX lobe (Karis 2014's analytic environment BRDF), so
//     edges never go "wet"; only metal is near-mirror. The bezel is one continuous polished bead whose
//     curvature widens its lobe and whose inner flank reflects the dial; the chapter ring is circular-
//     brushed (lobe stretched across the grooves: a radial bow-tie highlight); deep cobalt enamel (linear
//     ~0.01, 0.03, 0.22) with the guilloche showing through as brightness and a GGX-0.1 clear coat;
//     applied gold casts soft shadows; gems cast and contact shadows; the dial sits on dark velvet in
//     the key's pool of light, with pile, a nap faded below ~3 px, and the dial's cast shadow (approach
//     after Roulette_Chrome's: environment first, satin over gloss, contact shadows over texture);
//     copper crystals in cobalt glass;
//   - the look-ahead: at 30 s after load, then every 300 s, +30 days, 14 + 3 + 5 s, eased; the
//     previewed instant is computed exactly like now (the same kernels, the clock offset); the date
//     shown is local (f.utc_offset_s); events and their latches pause and resume on return;
//   - the medallion's orientation: the lit limb turned toward the Sun's gem; earthshine far brighter
//     than a camera exposed for the sunlit Moon would record, so the new Moon still reads as the Moon;
//     phase names: New, First Quarter, Full, Last Quarter within 7 deg of elongation (~13 h either
//     side of the exact moment), the waxing / waning crescent and gibbous between.
// NOT MODELLED:
//   - houses, the Ascendant and Midheaven, the lunar nodes, Chiron, void-of-course Moon, eclipses,
//     retrograde shadows; the Moon's libration and the true tilt of its axis on the sky (the lit limb
//     points at the Sun's true longitude, not at its gem when gems are spread);
//   - Jupiter's and Saturn's mutual perturbations beyond JPL's fitted elements (see CHECKED).
// CHECKED (scripts and tables in the session notes, horoscope-research.md):
//   - the model against JPL Horizons (apparent, ecliptic of date), 1990-2050 every 37 days: Sun <= 22",
//     Moon <= 13", Mercury <= 35", Venus <= 72", Mars <= 3.1', Jupiter <= 10.6', Saturn <= 10.4',
//     Uranus <= 2.0', Neptune <= 61", Pluto <= 61" (JPL's own limits for Table 1: 400"/600" for
//     Jupiter/Saturn);
//   - every 2026 ingress and station against Horizons, hourly: all found, none spurious; Sun ingresses
//     within 8 min, all 160 Moon ingresses within 0.2 min, Mercury's six stations within 3 min;
//   - an independent audit, daily against Horizons 2000-2050: Sun to Mars ingresses within 1.6 h and
//     every station within 4.2 h; Jupiter to Pluto ingresses can be off by a day or more (median 4.5 h
//     for Jupiter, 21 h for Saturn, worst Saturn 123 h in 2042-44), because JPL's table itself is off
//     by up to ~10' for Jupiter and Saturn (a slow planet near a sign's edge moves ~2' a day);
//   - the same audit confirmed the integer-day arithmetic, precession, nutation, aberration and
//     light-time signs, TT from day_frac, the phase angle (0.004 deg vs Horizons) and the waxing limb
//     (Crisium east); the latched countdown and the Rx flip were checked on the GPU with a test copy
//     whose clock runs 1 min per tick (Mercury's 2026-10-24 station latched at 07:09 vs 07:12; Pluto's
//     at 01:37 vs 01:36);
//   - through the look-ahead (harness, real clock): every countdown drops 39.9-40.1 s across a 40 s
//     span that contains a sweep, and again across the second one; kinds and Rx flags unchanged. This
//     test found that Metal's fast math reassociated (day + fraction) and lost ~15 s a tick near day
//     9800; the day difference is now taken in integers and a kept latch is copied, not re-encoded;
//   - sign, degree and retrograde for all 10 bodies at 5 dates (incl. Mercury 5 h after a station
//     and the Sun 37 min before an ingress): 50/50 signs, 50/50 flags;
//   - this kernel against the float64 model (state read back from harness renders) at 6 dates,
//     2001-2045: <= 4.7", event times within 0.07 h.
// How it works: argus_init copies the atlas (rows 0-575) and Moon map (576-831) into a 512x847
// float32 state (argus_step re-copies them on ticks 0-2) and computes the hourly samples (rows
// 836-845); argus_step
// recomputes the samples every tick and, from the previous tick's samples, each body's longitude,
// rate, display angle (row 832), event (833), the 45 aspect pairs (834), the Moon's phase (835) and
// the latched event times (846). The calendar date: H. Hinnant's days-to-civil algorithm.
// argus_draw is analytic: no march.
// Cost (harness, 1920x1200, on a busy machine, so as ratios to Night Tide measured alongside):
// 1.1-1.4 ms back-to-back (0.44-0.53x Night Tide; the step ~0.04-0.14 ms of it); paced 0.4-0.9x
// Night Tide (2.0-6.6 ms at load 2.5-5); PASS at 30, 60 and 120 FPS. No bake was needed: the draw is
// analytic and branches by ring.
// @argus state 512x847 float32
// @argus data Aventurine_Horoscope.bin 512x832 rgba8

// ============================================================================ ephemeris
constant float D2R = 0.01745329252f, R2D = 57.2957795131f, TAU = 6.28318530718f;
constant float TT_UTC_D = 69.184f / 86400.0f;      // TT - UTC: 32.184 s + 37 leap seconds (since 2017)
constant float AU_KM = 149597870.7f;
constant float C_AU_D = 173.1446327f;              // light: au per day
constant float KAPPA = 20.49552f / 3600.0f;        // constant of aberration, deg

// state rows
constant int ROW_BODY = 832, ROW_EVENT = 833, ROW_ASP = 834, ROW_MOON = 835, ROW_SAMP = 836, ROW_LATCH = 846;
constant int NSAMP = 216, SAMP0 = 24;              // hourly samples from -24 h to +191 h

// JPL "Approximate Positions of the Planets", Table 1 (1800-2050); Pluto: the same table before 2015.
// a, e, I, L, long. perihelion, long. node at J2000, and their rates per Julian century.
constant float EL0[9][6] = {
    {0.38709927f, 0.20563593f, 7.00497902f, 252.25032350f, 77.45779628f, 48.33076593f},  // Mercury
    {0.72333566f, 0.00677672f, 3.39467605f, 181.97909950f, 131.60246718f, 76.67984255f},  // Venus
    {1.00000261f, 0.01671123f, -0.00001531f, 100.46457166f, 102.93768193f, 0.00000000f},  // EMB
    {1.52371034f, 0.09339410f, 1.84969142f, -4.55343205f, -23.94362959f, 49.55953891f},  // Mars
    {5.20288700f, 0.04838624f, 1.30439695f, 34.39644051f, 14.72847983f, 100.47390909f},  // Jupiter
    {9.53667594f, 0.05386179f, 2.48599187f, 49.95424423f, 92.59887831f, 113.66242448f},  // Saturn
    {19.18916464f, 0.04725744f, 0.77263783f, 313.23810451f, 170.95427630f, 74.01692503f},  // Uranus
    {30.06992276f, 0.00859048f, 1.77004347f, -55.12002969f, 44.96476227f, 131.78422574f},  // Neptune
    {39.48211675f, 0.24882730f, 17.14001206f, 238.92903833f, 224.06891629f, 110.30393684f},  // Pluto
};
constant float ELR[9][6] = {
    {0.00000037f, 0.00001906f, -0.00594749f, 149472.67411175f, 0.16047689f, -0.12534081f},
    {0.00000390f, -0.00004107f, -0.00078890f, 58517.81538729f, 0.00268329f, -0.27769418f},
    {0.00000562f, -0.00004392f, -0.01294668f, 35999.37244981f, 0.32327364f, 0.00000000f},
    {0.00001847f, 0.00007882f, -0.00813131f, 19140.30268499f, 0.44441088f, -0.29257343f},
    {-0.00011607f, -0.00013253f, -0.00183714f, 3034.74612775f, 0.21252668f, 0.20469106f},
    {-0.00125060f, -0.00050991f, 0.00193609f, 1222.49362201f, -0.41897216f, -0.28867794f},
    {-0.00196176f, -0.00004397f, -0.00242939f, 428.48202785f, 0.40805281f, 0.04240589f},
    {0.00026291f, 0.00005105f, 0.00035372f, 218.45945325f, -0.32241464f, -0.00508664f},
    {-0.00031596f, 0.00005170f, 0.00004818f, 145.20780515f, -0.04062942f, -0.01183482f},
};
// L rate as whole turns per day x 2^32 (exact modular arithmetic on the day count)
constant uint ELR_LR[9] = {48823503u, 19114161u, 11758775u, 6251956u, 991264u, 399313u, 139959u, 71357u, 47430u};
// Meeus ch. 47: L', D, M, M', F, A1, A2, A3 at J2000 (deg) and rates (deg per century)
constant float MA0[8] = {218.3164477f, 297.8501921f, 357.5291092f, 134.9633964f, 93.2720950f, 119.7500000f, 53.0900000f, 313.4500000f};
constant float MAR[8] = {481267.88123421f, 445267.11140340f, 35999.05029090f, 477198.86750550f, 483202.01752330f, 131.84900000f, 479264.29000000f, 481266.48400000f};
constant uint MAR_R[8] = {157200533u, 145441302u, 11758669u, 155871437u, 157832296u, 43067u, 156546083u, 157200077u};
// Table 47.A: multiples of D, M, M', F; Sigma-l (1e-6 deg) and Sigma-r (1e-3 km)
constant char4 MLR_ARG[60] = {char4(0,0,1,0), char4(2,0,-1,0), char4(2,0,0,0), char4(0,0,2,0), char4(0,1,0,0), char4(0,0,0,2), char4(2,0,-2,0), char4(2,-1,-1,0), char4(2,0,1,0), char4(2,-1,0,0), char4(0,1,-1,0), char4(1,0,0,0), char4(0,1,1,0), char4(2,0,0,-2), char4(0,0,1,2), char4(0,0,1,-2), char4(4,0,-1,0), char4(0,0,3,0), char4(4,0,-2,0), char4(2,1,-1,0), char4(2,1,0,0), char4(1,0,-1,0), char4(1,1,0,0), char4(2,-1,1,0), char4(2,0,2,0), char4(4,0,0,0), char4(2,0,-3,0), char4(0,1,-2,0), char4(2,0,-1,2), char4(2,-1,-2,0), char4(1,0,1,0), char4(2,-2,0,0), char4(0,1,2,0), char4(0,2,0,0), char4(2,-2,-1,0), char4(2,0,1,-2), char4(2,0,0,2), char4(4,-1,-1,0), char4(0,0,2,2), char4(3,0,-1,0), char4(2,1,1,0), char4(4,-1,-2,0), char4(0,2,-1,0), char4(2,2,-1,0), char4(2,1,-2,0), char4(2,-1,0,-2), char4(4,0,1,0), char4(0,0,4,0), char4(4,-1,0,0), char4(1,0,-2,0), char4(2,1,0,-2), char4(0,0,2,-2), char4(1,1,1,0), char4(3,0,-2,0), char4(4,0,-3,0), char4(2,-1,2,0), char4(0,2,1,0), char4(1,1,-1,0), char4(2,0,3,0), char4(2,0,-1,-2)};
constant float2 MLR_C[60] = {float2(6288774.0f,-20905355.0f), float2(1274027.0f,-3699111.0f), float2(658314.0f,-2955968.0f), float2(213618.0f,-569925.0f), float2(-185116.0f,48888.0f), float2(-114332.0f,-3149.0f), float2(58793.0f,246158.0f), float2(57066.0f,-152138.0f), float2(53322.0f,-170733.0f), float2(45758.0f,-204586.0f), float2(-40923.0f,-129620.0f), float2(-34720.0f,108743.0f), float2(-30383.0f,104755.0f), float2(15327.0f,10321.0f), float2(-12528.0f,0.0f), float2(10980.0f,79661.0f), float2(10675.0f,-34782.0f), float2(10034.0f,-23210.0f), float2(8548.0f,-21636.0f), float2(-7888.0f,24208.0f), float2(-6766.0f,30824.0f), float2(-5163.0f,-8379.0f), float2(4987.0f,-16675.0f), float2(4036.0f,-12831.0f), float2(3994.0f,-10445.0f), float2(3861.0f,-11650.0f), float2(3665.0f,14403.0f), float2(-2689.0f,-7003.0f), float2(-2602.0f,0.0f), float2(2390.0f,10056.0f), float2(-2348.0f,6322.0f), float2(2236.0f,-9884.0f), float2(-2120.0f,5751.0f), float2(-2069.0f,0.0f), float2(2048.0f,-4950.0f), float2(-1773.0f,4130.0f), float2(-1595.0f,0.0f), float2(1215.0f,-3958.0f), float2(-1110.0f,0.0f), float2(-892.0f,3258.0f), float2(-810.0f,2616.0f), float2(759.0f,-1897.0f), float2(-713.0f,-2117.0f), float2(-700.0f,2354.0f), float2(691.0f,0.0f), float2(596.0f,0.0f), float2(549.0f,-1423.0f), float2(537.0f,-1117.0f), float2(520.0f,-1571.0f), float2(-487.0f,-1739.0f), float2(-399.0f,0.0f), float2(-381.0f,-4421.0f), float2(351.0f,0.0f), float2(-340.0f,0.0f), float2(330.0f,0.0f), float2(327.0f,0.0f), float2(-323.0f,1165.0f), float2(299.0f,0.0f), float2(294.0f,0.0f), float2(0.0f,8752.0f)};
// Table 47.B: multiples of D, M, M', F; Sigma-b (1e-6 deg)
constant char4 MB_ARG[60] = {char4(0,0,0,1), char4(0,0,1,1), char4(0,0,1,-1), char4(2,0,0,-1), char4(2,0,-1,1), char4(2,0,-1,-1), char4(2,0,0,1), char4(0,0,2,1), char4(2,0,1,-1), char4(0,0,2,-1), char4(2,-1,0,-1), char4(2,0,-2,-1), char4(2,0,1,1), char4(2,1,0,-1), char4(2,-1,-1,1), char4(2,-1,0,1), char4(2,-1,-1,-1), char4(0,1,-1,-1), char4(4,0,-1,-1), char4(0,1,0,1), char4(0,0,0,3), char4(0,1,-1,1), char4(1,0,0,1), char4(0,1,1,1), char4(0,1,1,-1), char4(0,1,0,-1), char4(1,0,0,-1), char4(0,0,3,1), char4(4,0,0,-1), char4(4,0,-1,1), char4(0,0,1,-3), char4(4,0,-2,1), char4(2,0,0,-3), char4(2,0,2,-1), char4(2,-1,1,-1), char4(2,0,-2,1), char4(0,0,3,-1), char4(2,0,2,1), char4(2,0,-3,-1), char4(2,1,-1,1), char4(2,1,0,1), char4(4,0,0,1), char4(2,-1,1,1), char4(2,-2,0,-1), char4(0,0,1,3), char4(2,1,1,-1), char4(1,1,0,-1), char4(1,1,0,1), char4(0,1,-2,-1), char4(2,1,-1,-1), char4(1,0,1,1), char4(2,-1,-2,-1), char4(0,1,2,1), char4(4,0,-2,-1), char4(4,-1,-1,-1), char4(1,0,1,-1), char4(4,0,1,-1), char4(1,0,-1,-1), char4(4,-1,0,-1), char4(2,-2,0,1)};
constant float MB_C[60] = {5128122.0f, 280602.0f, 277693.0f, 173237.0f, 55413.0f, 46271.0f, 32573.0f, 17198.0f, 9266.0f, 8822.0f, 8216.0f, 4324.0f, 4200.0f, -3359.0f, 2463.0f, 2211.0f, 2065.0f, -1870.0f, 1828.0f, -1794.0f, -1749.0f, -1565.0f, -1491.0f, -1475.0f, -1410.0f, -1344.0f, -1335.0f, 1107.0f, 1021.0f, 833.0f, 777.0f, 671.0f, 607.0f, 596.0f, 491.0f, -451.0f, 439.0f, 422.0f, 421.0f, -366.0f, -351.0f, 331.0f, 315.0f, 302.0f, -283.0f, -229.0f, 223.0f, 223.0f, -220.0f, -220.0f, -185.0f, 181.0f, -177.0f, 176.0f, 166.0f, -164.0f, 132.0f, -119.0f, 115.0f, 107.0f};
// 60 LR rows, 60 B rows


struct Tm { int n; float fr; };                    // TT days since J2000.0 = n + fr

static inline float wrap360(float a) { return a - 360.0f * floor(a * (1.0f / 360.0f)); }
static inline float wrap180(float a) { return wrap360(a + 180.0f) - 180.0f; }
static inline float sinr(float x) { return sin(x - TAU * rint(x * (1.0f / TAU))); }
static inline float cosr(float x) { return cos(x - TAU * rint(x * (1.0f / TAU))); }
// a0 + rate * (n + fr) / 36525 in degrees, mod 360. The whole days go through exact 32-bit modular
// arithmetic (R = turns per day x 2^32), so float32 keeps the Moon to ~1" for decades.
static inline float lin_angle(uint R, float a0, float rate_cy, Tm t) {
    const float whole = float(uint(t.n) * R) * (360.0f / 4294967296.0f);
    return wrap360(whole + a0 + rate_cy * (t.fr * (1.0f / 36525.0f)));
}
static inline float cent(Tm t) { return (float(t.n) + t.fr) * (1.0f / 36525.0f); }

// heliocentric J2000 ecliptic position (au) of element set i (JPL's Keplerian recipe)
static float3 helio(int i, Tm t) {
    const float T = cent(t);
    const float a = EL0[i][0] + ELR[i][0] * T, e = EL0[i][1] + ELR[i][1] * T;
    const float I = (EL0[i][2] + ELR[i][2] * T) * D2R;
    const float L = lin_angle(ELR_LR[i], EL0[i][3], ELR[i][3], t);
    const float wb = EL0[i][4] + ELR[i][4] * T, Om = (EL0[i][5] + ELR[i][5] * T) * D2R;
    const float w = wb * D2R - Om;
    const float M = (wrap360(L - wb + 180.0f) - 180.0f) * D2R;
    float E = M + e * sin(M);
    for (int k = 0; k < 6; k++) E -= (E - e * sin(E) - M) / (1.0f - e * cos(E));
    const float xp = a * (cos(E) - e), yp = a * sqrt(1.0f - e * e) * sin(E);
    const float cw = cos(w), sw = sin(w), cO = cos(Om), sO = sin(Om), cI = cos(I), sI = sin(I);
    return float3((cw * cO - sw * sO * cI) * xp + (-sw * cO - cw * sO * cI) * yp,
                  (cw * sO + sw * cO * cI) * xp + (-sw * sO + cw * cO * cI) * yp,
                  (sw * sI) * xp + (cw * sI) * yp);
}

// geocentric Moon, mean equinox of date (Meeus ch. 47, all 60 + 60 terms): lon, lat (deg), dist (km)
static float3 moon_meeus(Tm t) {
    const float T = cent(t);
    float A[8];
    for (int k = 0; k < 8; k++) A[k] = lin_angle(MAR_R[k], MA0[k], MAR[k], t);
    const float Lp = A[0] - 0.0015786f * T * T, D = A[1] - 0.0018819f * T * T, M = A[2] - 0.0001536f * T * T;
    const float Mp = A[3] + 0.0087414f * T * T, F = A[4] - 0.0036539f * T * T;
    const float E = 1.0f - 0.002516f * T - 0.0000074f * T * T;
    const float4 g = float4(D, M, Mp, F) * D2R;
    float sl = 0.0f, sr = 0.0f, sb = 0.0f;
    for (int i = 0; i < 60; i++) {
        const float4 m = float4(MLR_ARG[i]);
        const float x = dot(m, g);
        const float k = abs(m.y) == 1.0f ? E : (abs(m.y) == 2.0f ? E * E : 1.0f);
        sl += MLR_C[i].x * k * sinr(x);
        sr += MLR_C[i].y * k * cosr(x);
    }
    for (int i = 0; i < 60; i++) {
        const float4 m = float4(MB_ARG[i]);
        const float k = abs(m.y) == 1.0f ? E : (abs(m.y) == 2.0f ? E * E : 1.0f);
        sb += MB_C[i] * k * sinr(dot(m, g));
    }
    const float a1 = A[5] * D2R, a2 = A[6] * D2R, a3 = A[7] * D2R, lp = Lp * D2R, mp = Mp * D2R, f = F * D2R;
    sl += 3958.0f * sinr(a1) + 1962.0f * sinr(lp - f) + 318.0f * sinr(a2);
    sb += -2235.0f * sinr(lp) + 382.0f * sinr(a3) + 175.0f * sinr(a1 - f) + 175.0f * sinr(a1 + f)
          + 127.0f * sinr(lp - mp) - 115.0f * sinr(lp + mp);
    return float3(wrap360(Lp + sl * 1e-6f), sb * 1e-6f, 385000.56f + sr * 1e-3f);
}

static inline float3 lonlatr(float3 v) {
    return float3(wrap360(atan2(v.y, v.x) * R2D), atan2(v.z, length(v.xy)) * R2D, length(v));
}

// apparent geocentric ecliptic longitude and latitude of date (deg) and distance (au) of body b:
// 0 Sun, 1 Moon, 2 Mercury, 3 Venus, 4 Mars, 5 Jupiter, 6 Saturn, 7 Uranus, 8 Neptune, 9 Pluto
static float3 body_pos(int b, Tm t) {
    const float T = cent(t);
    const float3 mo = moon_meeus(t);
    const float Om = (125.04452f - 1934.136261f * T) * D2R, Ls = (280.4665f + 36000.7698f * T) * D2R;
    const float Lm = (218.3165f + 481267.8813f * T) * D2R;
    const float dpsi = (-17.20f * sinr(Om) - 1.32f * sinr(2.0f * Ls) - 0.23f * sinr(2.0f * Lm) + 0.21f * sinr(2.0f * Om)) / 3600.0f;
    if (b == 1) return float3(wrap360(mo.x + dpsi), mo.y, mo.z / AU_KM);
    const float pr = (5028.796195f * T + 1.1054348f * T * T) / 3600.0f;   // general precession in longitude
    const float ml = (mo.x - pr) * D2R, mb = mo.y * D2R;
    const float3 mv = float3(cos(mb) * cos(ml), cos(mb) * sin(ml), sin(mb)) * (mo.z / AU_KM / 82.3006f);
    const float3 earth = helio(2, t) - mv;                                  // Earth = EMB - Moon/(1+81.3)
    const float3 sv = lonlatr(-earth);
    const float sun = sv.x + pr + dpsi;
    if (b == 0) return float3(wrap360(sun - KAPPA / cos(sv.y * D2R)), sv.y, sv.z);
    const int i = b == 2 ? 0 : (b == 3 ? 1 : b - 1);
    float tau = 0.0f; float3 p = float3(0.0f);
    for (int k = 0; k < 2; k++) {
        p = lonlatr(helio(i, Tm{t.n, t.fr - tau}) - earth);
        tau = p.z / C_AU_D;
    }
    const float lon = p.x + pr + dpsi;
    return float3(wrap360(lon - KAPPA * cos((sun - lon) * D2R) / cos(p.y * D2R)), p.y, p.z);
}

// the look-ahead: PV_FIRST seconds after load and every PV_PERIOD after that, the dial winds PV_DAYS
// forward (14 s, eased), holds 3 s and returns to now (5 s). Returns (days ahead, the preview's
// weight 0..1). 300 s divides the 4 h wrap of f.time, so the rhythm runs on across it.
constant float PV_PERIOD = 300.0f, PV_FIRST = 30.0f, PV_DAYS = 30.0f;
static inline float2 preview(float t) {
    float u = fmod(t + PV_PERIOD - PV_FIRST, PV_PERIOD);
    if (u > PV_PERIOD - 1.0f) u -= PV_PERIOD;
    if (u < -1.0f || u > 23.0f) return float2(0.0f);
    const float k = u < 14.0f ? smoothstep(0.0f, 14.0f, u) : (u < 17.0f ? 1.0f : 1.0f - smoothstep(17.0f, 22.0f, u));
    return float2(PV_DAYS * k, smoothstep(-0.6f, 0.0f, u) * (1.0f - smoothstep(22.0f, 22.6f, u)));
}
static inline Tm now_tt(constant ArgusFrame& f) { return Tm{f.days_j2000, f.day_frac + TT_UTC_D + preview(f.time).x}; }

// ============================================================================ state kernels
// one thread per hourly sample of one body: rows ROW_SAMP + b, x = k, time now + (k - SAMP0) h
static inline void write_sample(constant ArgusFrame& f, texture2d<float, access::write> o, uint2 gid) {
    const int b = int(gid.y) - ROW_SAMP;
    const Tm t0 = now_tt(f);
    const float3 p = body_pos(b, Tm{t0.n, t0.fr + float(int(gid.x) - SAMP0) * (1.0f / 24.0f)});
    o.write(float4(p, 0.0f), gid);
}

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> state [[texture(0)]],
                       texture2d<float, access::read> data [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    if (gid.y < 832u) { state.write(data.read(gid), gid); return; }
    if (int(gid.y) >= ROW_SAMP && int(gid.y) < ROW_SAMP + 10 && int(gid.x) < NSAMP) { write_sample(f, state, gid); return; }
    state.write(float4(0.0f), gid);
}

static inline float samp(texture2d<float, access::read> s, int b, int k) { return s.read(uint2(k, ROW_SAMP + b)).x; }

kernel void argus_step(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    const int x = int(gid.x), y = int(gid.y);
    if (y < 832) { if (f.frame < 3u) next.write(prev.read(gid), gid); return; }
    if (y >= ROW_SAMP) { if (y < ROW_SAMP + 10 && x < NSAMP) write_sample(f, next, gid); return; }
    if (y == ROW_BODY && x < 10) {
        // longitude now, its rate over the surrounding day, and the display angle on the chart
        const float l0 = samp(prev, x, SAMP0);
        const float rate = wrap180(samp(prev, x, SAMP0 + 12) - samp(prev, x, SAMP0 - 12));
        // display angles: the true longitudes pushed apart to >= 14 deg, eased over ~1.5 s
        float d[10];
        for (int j = 0; j < 10; j++) d[j] = samp(prev, j, SAMP0);
        for (int it = 0; it < 12; it++)
            for (int i = 0; i < 10; i++) for (int j = i + 1; j < 10; j++) {
                const float s = wrap180(d[j] - d[i]);
                if (abs(s) < 14.0f) { const float pu = (14.0f - abs(s)) * 0.5f * (s >= 0.0f ? 1.0f : -1.0f); d[i] -= pu; d[j] += pu; }
            }
        // during the look-ahead the easing is fast, so the gems keep up (and slide past one another)
        const float4 old = prev.read(uint2(x, ROW_BODY));
        const float pw = preview(f.time).y;
        const float target = wrap360(d[x]);
        const float disp = f.frame < 3u ? target : wrap360(old.w + wrap180(target - old.w) * (1.0f - exp(-f.dt / (pw > 0.0f ? 0.05f : 0.5f))));
        next.write(float4(l0, prev.read(uint2(SAMP0, ROW_SAMP + x)).y, rate, disp), gid);
        return;
    }
    if (y == ROW_EVENT && x < 10) {
        // the next sign ingress or station within the horizon, latched as an absolute time (row
        // ROW_LATCH) so float noise in a slow planet's samples can't make the countdown wander
        const int b = x;
        if (preview(f.time).x > 0.0f && f.frame >= 3u) {
            // look-ahead: no events; Rx from the motion alone; the latch waits for the return to now
            const float rate = wrap180(samp(prev, b, SAMP0 + 12) - samp(prev, b, SAMP0 - 12));
            const float rx0 = prev.read(uint2(x, ROW_EVENT)).w;
            next.write(float4(0.0f, 0.0f, 0.0f, b < 2 ? 0.0f : (rate < -6e-5f ? 1.0f : (rate > 6e-5f ? 0.0f : rx0))), gid);
            next.write(prev.read(uint2(x, ROW_LATCH)), uint2(x, ROW_LATCH));
            return;
        }
        float l_prev = samp(prev, b, SAMP0);
        int s_prev = int(l_prev / 30.0f) % 12;
        float t_ing = 1e9f; int sign_to = 0;
        for (int k = SAMP0 + 1; k <= SAMP0 + 168; k++) {
            const float l = samp(prev, b, k);
            const int s = int(l / 30.0f) % 12;
            if (s != s_prev) {
                const float dl = wrap180(l - l_prev);
                const float edge = dl > 0.0f ? float(s) * 30.0f : float(s_prev) * 30.0f;
                t_ing = float(k - 1 - SAMP0) + clamp(wrap180(edge - l_prev) / dl, 0.0f, 1.0f);
                sign_to = s; break;
            }
            l_prev = l; s_prev = s;
        }
        float t_st = 1e9f; float st_kind = 0.0f;
        if (b >= 2) {
            float r_prev = wrap180(samp(prev, b, SAMP0 + 12) - samp(prev, b, SAMP0 - 12));
            for (int k = SAMP0 + 1; k + 12 < NSAMP; k++) {
                const float r = wrap180(samp(prev, b, k + 12) - samp(prev, b, k - 12));
                if ((r > 0.0f) != (r_prev > 0.0f)) {
                    // the zero of a least-squares line through the daily rate around the crossing
                    const int j0 = max(12, k - 8), j1 = min(NSAMP - 13, k + 8);
                    float sx = 0.0f, sy = 0.0f, sxx = 0.0f, sxy = 0.0f, nn = 0.0f;
                    for (int j = j0; j <= j1; j++) {
                        const float xx = float(j - k), yy = wrap180(samp(prev, b, j + 12) - samp(prev, b, j - 12));
                        sx += xx; sy += yy; sxx += xx * xx; sxy += xx * yy; nn += 1.0f;
                    }
                    const float slope = (nn * sxy - sx * sy) / max(nn * sxx - sx * sx, 1e-6f);
                    const float icpt = (sy - slope * sx) / nn;
                    const float z = abs(slope) > 1e-12f ? clamp(-icpt / slope, -2.0f, 1.0f) : -0.5f;   // near the crossing
                    t_st = float(k - SAMP0) + z;
                    st_kind = r_prev > 0.0f ? 2.0f : 3.0f; break;
                }
                r_prev = r;
            }
        }
        // retrograde now: the daily motion past +-6e-5 deg/day (float noise stays below), or the latched
        // station passing; a coming station's kind follows from it (direct now -> SR next), never from
        // the sign of a noisy crossing
        const Tm t0 = now_tt(f);
        const float4 L = prev.read(uint2(x, ROW_LATCH));
        // whole days in integers first: under fast math (L.x + L.y) would be rounded near day 9800 (~84 s)
        const int dn = int(L.x) - t0.n;
        const float hL = (float(dn) + (L.y - t0.fr)) * 24.0f;
        const bool fresh = f.frame < 3u || L.z == 0.0f;
        const float rate = wrap180(samp(prev, b, SAMP0 + 12) - samp(prev, b, SAMP0 - 12));
        float rx = f.frame < 3u ? (rate < 0.0f ? 1.0f : 0.0f) : prev.read(uint2(x, ROW_EVENT)).w;
        const bool passed = !fresh && L.z >= 2.0f && hL <= 0.0f;
        if (passed) rx = L.z == 2.0f ? 1.0f : 0.0f;
        else rx = rate < -6e-5f ? 1.0f : (rate > 6e-5f ? 0.0f : rx);
        if (b < 2) rx = 0.0f;
        st_kind = rx > 0.5f ? 3.0f : 2.0f;
        float4 ev = float4(0.0f);                                   // kind, hours, target sign, Rx flag
        if (t_ing < 168.0f && t_ing <= t_st) ev = float4(1.0f, t_ing, float(sign_to), 0.0f);
        else if (t_st < 168.0f) ev = float4(st_kind, t_st, 0.0f, 0.0f);
        // the latched event: keep it while the fresh estimate agrees within 3 h
        bool keep = false;
        if (!fresh && !passed) {
            if (L.z == ev.x && L.w == ev.z && abs(hL - ev.y) < 3.0f) { ev.y = hL; keep = true; }
            else if (ev.x == 0.0f && L.z >= 2.0f && hL > 0.0f && hL < 168.0f) ev = float4(L.z, hL, L.w, 0.0f);
        }
        ev.w = rx;
        next.write(ev, gid);
        const float tot = t0.fr + ev.y / 24.0f, ip = floor(tot);           // a kept latch is copied as is
        next.write(keep ? L : (ev.x > 0.0f ? float4(float(t0.n) + ip, tot - ip, ev.x, ev.z) : float4(0.0f)), uint2(x, ROW_LATCH));
        return;
    }
    if (y == ROW_LATCH) return;                                     // written by the ROW_EVENT threads
    if (y == ROW_ASP && x < 45) {
        // aspect pair x: the major aspects within orb (6 deg with the Sun or Moon, else 4); no conjunctions
        int i = 0, j = 1, p = 0;
        for (int a = 0; a < 10; a++) for (int c = a + 1; c < 10; c++) { if (p == x) { i = a; j = c; } p++; }
        const float li = samp(prev, i, SAMP0), lj = samp(prev, j, SAMP0);
        const float sep = abs(wrap180(li - lj));
        const float orb = (i < 2) ? 6.0f : 4.0f;
        float kind = -1.0f; float tight = 0.0f;
        const float A[4] = {60.0f, 90.0f, 120.0f, 180.0f};
        for (int k = 0; k < 4; k++) if (abs(sep - A[k]) < orb) { kind = float(k); tight = 1.0f - abs(sep - A[k]) / orb; }
        next.write(float4(li, lj, kind, tight), gid);
        return;
    }
    if (y == ROW_MOON && x == 0) {
        // the Moon's phase: elongation from the Sun and the illuminated fraction (Meeus ch. 48)
        const float4 s = prev.read(uint2(SAMP0, ROW_SAMP + 0)), m = prev.read(uint2(SAMP0, ROW_SAMP + 1));
        const float cpsi = cos(m.y * D2R) * cos((m.x - s.x) * D2R);
        const float psi = acos(clamp(cpsi, -1.0f, 1.0f));
        const float i = atan2(s.z * sin(psi), m.z - s.z * cos(psi));            // phase angle
        next.write(float4(wrap360(m.x - s.x), 0.5f * (1.0f + cos(i)), s.x, m.x), gid);
        return;
    }
    next.write(float4(0.0f), gid);
}

// ============================================================================ the dial
// Dial units: radius 1 = the bezel's outer edge. Chart convention: 0 Aries at 9 o'clock, longitude
// counter-clockwise. The camera looks straight down from CAM_D dial radii; z points at it.
constant float PI_F = 3.14159265f;
constant float DIAL_R = 0.805f, DIAL_Y = 0.025f;     // of the screen's half-height; centre raised a little
constant float CAM_D = 4.0f;
constant float R_OUT = 1.075f, R_Z1 = 0.898f, R_Z0 = 0.776f, R_D0 = 0.726f;
constant float R_GEM = 0.668f, R_LG = 0.600f, R_ASP = 0.325f;
constant float R_MED = 0.150f, R_MEDB = 0.172f;
constant int G_RX = 22, G_DIG = 23, G_DEG = 33, G_d = 34, G_h = 35, G_D = 36, G_ARROW = 37, G_S = 38, G_R = 39;
// advance widths in cells (text glyphs; symbols 0.78), from the atlas build
constant float ADV[72] = {0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.312f, 0.492f, 0.508f, 0.582f, 0.780f, 0.438f, 0.533f, 0.453f, 0.492f, 0.396f, 0.432f, 0.428f, 0.262f, 0.512f, 0.463f, 0.387f, 0.363f, 0.295f, 0.508f, 0.670f, 0.477f, 0.258f, 0.498f, 0.471f, 0.578f, 0.498f, 0.736f, 0.604f, 0.596f, 0.824f, 0.490f, 0.445f, 0.461f, 0.293f, 0.566f, 0.596f, 0.484f, 0.438f, 0.780f};
// the eight phase names, as atlas indices (-1 a space, -2 the end)
constant char PHASE[8][16] = {
    {60, 43, 52, -1, 59, 47, 47, 46, -2},                               // New Moon
    {62, 40, 53, 45, 46, 44, -1, 55, 48, 43, 49, 42, 43, 46, 50, -2},   // Waxing Crescent
    {56, 45, 48, 49, 50, -1, 61, 51, 40, 48, 50, 43, 48, -2},           // First Quarter
    {62, 40, 53, 45, 46, 44, -1, 57, 45, 41, 41, 47, 51, 49, -2},       // Waxing Gibbous
    {56, 51, 54, 54, -1, 59, 47, 47, 46, -2},                           // Full Moon
    {62, 40, 46, 45, 46, 44, -1, 57, 45, 41, 41, 47, 51, 49, -2},       // Waning Gibbous
    {58, 40, 49, 50, -1, 61, 51, 40, 48, 50, 43, 48, -2},               // Last Quarter
    {62, 40, 46, 45, 46, 44, -1, 55, 48, 43, 49, 42, 43, 46, 50, -2}};  // Waning Crescent
constant char PREVIEW_W[7] = {69, 48, 43, 65, 45, 43, 52};               // Preview
constant char MONTH[12][3] = {{66, 40, 46}, {56, 43, 41}, {59, 40, 48}, {67, 63, 48}, {59, 40, 64}, {66, 51, 46},
                              {66, 51, 54}, {67, 51, 44}, {38, 43, 63}, {68, 42, 50}, {60, 47, 65}, {36, 43, 42}};
// the local calendar date (proleptic Gregorian) of a day count from 1970-01-01 (H. Hinnant's algorithm)
static inline int2 month_day(int z) {
    z += 719468;
    const int era = (z >= 0 ? z : z - 146096) / 146097;
    const int doe = z - era * 146097;
    const int yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const int doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const int mp = (5 * doy + 2) / 153;
    return int2(mp < 10 ? mp + 3 : mp - 9, doy - (153 * mp + 2) / 5 + 1);
}

static inline float2 CP(float lam, float r) { const float a = (180.0f + lam) * D2R; return r * float2(cos(a), sin(a)); }
static inline float hash2(float2 c, float s) { return argus_rand(uint2(int2(c) + 50000), uint(s)); }
static inline float sat(float x) { return clamp(x, 0.0f, 1.0f); }

// --- glyph atlas (state rows 0-575, 8 x 9 cells of 64 px): signed distance in screen px, + outside
static inline float glyph_px(texture2d<float> st, int id, float2 q, float cell_px) {
    // q: glyph-local position in cells, (0,0) the cell's centre, y up
    if (abs(q.x) > 0.49f || abs(q.y) > 0.49f) return 99.0f;
    constexpr sampler s(filter::linear, address::clamp_to_edge, coord::pixel);
    const float2 tc = float2(float(id % 8) * 64.0f + (q.x + 0.5f) * 64.0f, float(id / 8) * 64.0f + (0.5f - q.y) * 64.0f);
    return (0.5f - st.sample(s, tc).r) * 12.0f * cell_px / 64.0f;
}
static inline float adv(int id) { return id < 0 ? 0.28f : ADV[id]; }
// a run of glyphs centred at c (dial units), cell size s, upright: the signed distance in px
static float text_px(texture2d<float> st, thread const int* ids, int n, float2 p, float2 c, float s, float ppu) {
    float w = 0.0f;
    for (int i = 0; i < n; i++) w += adv(ids[i]);
    const float2 q0 = (p - c) / s;
    if (abs(q0.y) > 0.5f || abs(q0.x) > 0.5f * w + 0.5f) return 99.0f;
    float x = -0.5f * w, d = 99.0f;
    for (int i = 0; i < n; i++) {
        const float a = adv(ids[i]);
        if (ids[i] >= 0) d = min(d, glyph_px(st, ids[i], q0 - float2(x + 0.5f * a, 0.0f), s * ppu));
        x += a;
    }
    return d;
}

// --- the studio: a light tent with a dark lens port overhead, a key softbox upper left (drifting), a
// wide fill softbox right, the tent's seams and a few lamps of the room low on the horizon (irregular,
// so reflections never repeat). Lights are areas, widened by the lobe (rough) and never point-sampled.
// V is this pixel's direction to the camera.
struct Studio { float3 sb; float3 sbx; float3 sby; float3 st; float3 stx; float3 sty; float3 V; };
static inline Studio studio(float t) {
    Studio S;
    const float az = (135.0f + 6.0f * sin(TAU * t / 96.0f) + 3.0f * sin(TAU * t / 240.0f + 1.0f)) * D2R;
    const float el = (52.0f + 3.0f * sin(TAU * t / 150.0f)) * D2R;
    S.sb = float3(cos(el) * cos(az), cos(el) * sin(az), sin(el));
    S.sbx = normalize(cross(float3(0, 0, 1), S.sb)); S.sby = cross(S.sb, S.sbx);
    S.st = normalize(float3(0.80f, -0.30f, 0.52f));
    S.stx = normalize(cross(float3(0, 0, 1), S.st)); S.sty = cross(S.st, S.stx);
    S.V = float3(0, 0, 1);
    return S;
}
static inline float rect_light(float3 d, float3 c, float3 ax, float3 ay, float hx, float hy, float soft) {
    const float k = dot(d, c);
    if (k <= 0.05f) return 0.0f;
    const float u = dot(d, ax) / k, v = dot(d, ay) / k;
    return (1.0f - smoothstep(hx - soft, hx + soft, abs(u))) * (1.0f - smoothstep(hy - soft, hy + soft, abs(v)));
}
constant float LAMP_AZ[4] = {0.40f, 1.25f, 2.90f, 5.00f}, LAMP_W[4] = {0.45f, 0.25f, 0.60f, 0.40f}, LAMP_S[4] = {1.0f, 0.55f, 0.8f, 0.7f};
static float3 env(float3 d, float rough, Studio S) {
    const float soft = 0.04f + rough * 0.9f;
    float3 c = float3(0.004f, 0.0035f, 0.005f) * (1.0f + 2.0f * sat(d.z + 0.3f));   // the dark velvet below
    if (d.z > -0.05f) {
        const float az = atan2(d.y, d.x), elv = asin(clamp(d.z, -1.0f, 1.0f));
        // the tent: brighter toward the key, its seams and folds a low-frequency unevenness
        const float port = smoothstep(0.90f - rough * 0.3f, 0.975f, d.z);
        const float fold = 0.78f + 0.22f * argus_noise(float2(az * 1.6f, elv * 2.2f));
        c = mix(float3(0.16f, 0.155f, 0.15f) * (0.45f + 0.75f * sat(dot(d, S.sb))) * fold, float3(0.010f), port) * (0.15f + 0.85f * smoothstep(0.15f, 0.75f, d.z));
        // key softbox (a bright core inside a softer diffuser) and a wide cool fill
        c += float3(1.0f, 0.95f, 0.88f) * (3.6f * rect_light(d, S.sb, S.sbx, S.sby, 0.22f, 0.15f, soft)
                                         + 1.6f * rect_light(d, S.sb, S.sbx, S.sby, 0.32f, 0.24f, soft + 0.06f)) * (1.0f - rough * 0.6f);
        c += float3(0.92f, 0.96f, 1.0f) * 0.75f * rect_light(d, S.st, S.stx, S.sty, 0.26f, 0.34f, soft + 0.05f) * (1.0f - rough * 0.5f);
        // lamps of the room, low on the horizon at irregular azimuths, widths and strengths
        for (int i = 0; i < 4; i++) {
            const float da = abs(fract((az - LAMP_AZ[i]) / TAU + 0.5f) - 0.5f) * TAU;
            const float w = LAMP_W[i] * 0.35f + rough * 0.8f;
            c += float3(1.0f, 0.78f, 0.52f) * LAMP_S[i] * 0.35f * exp(-(da * da) / (w * w)) * exp(-pow((elv - 0.16f) / (0.06f + rough * 0.6f), 2.0f));
        }
        c += float3(1.0f, 0.95f, 0.88f) * rough * 0.8f * pow(sat(dot(d, S.sb)), 4.0f);   // a satin lobe sees the box's glow
    }
    return c;
}
static inline float3 irr(float3 n, Studio S) {      // diffuse light on a matte surface
    return float3(0.16f) * (0.55f + 0.45f * n.z) + float3(1.0f, 0.95f, 0.88f) * 0.42f * sat(dot(n, S.sb)) + 0.06f * sat(dot(n, S.st));
}
static inline float3 schlick(float3 F0, float c) { return F0 + (1.0f - F0) * pow(1.0f - sat(c), 5.0f); }
// Fresnel integrated over a GGX lobe (Karis 2014's analytic environment BRDF): an edge seen edge-on
// reaches ~0.4 for a satin surface, not Schlick's 1, so nothing goes "wet"
static inline float3 env_brdf(float3 F0, float rough, float ndv) {
    const float4 rr = rough * float4(-1.0f, -0.0275f, -0.572f, 0.022f) + float4(1.0f, 0.0425f, 1.04f, -0.04f);
    const float a = min(rr.x * rr.x, exp2(-9.28f * sat(ndv))) * rr.x + rr.y;
    const float2 AB = float2(-1.04f, 1.04f) * a + rr.zw;
    return F0 * AB.x + AB.y;
}
static inline float3 refl(float3 n, Studio S) { return reflect(-S.V, n); }

constant float3 ROSE = float3(0.92f, 0.58f, 0.45f);
static inline float3 gold(float3 n, float rough, Studio S) {
    return env_brdf(ROSE, max(rough, 0.04f), dot(n, S.V)) * env(refl(n, S), rough, S);
}

// --- the Moon medallion: NASA's LROC colour map on a sphere lit at the real phase angle
static float3 moon_face(texture2d<float> st, float2 q, float elong, float illum, float2 sun_dir) {
    // lighting in the Sun's frame (+x toward the Sun gem); the map turns half a revolution, slowly,
    // around full and new Moon (elongation 170-190 and 350-10 deg), so the lit limb is the east limb
    // while waxing and the west while waning without a jump
    const float i = acos(clamp(2.0f * illum - 1.0f, -1.0f, 1.0f));         // phase angle
    const float ths = atan2(sun_dir.y, sun_dir.x);
    const float e2 = elong < 90.0f ? elong + 360.0f : elong;
    const float tht = ths + PI_F * (smoothstep(170.0f, 190.0f, e2) - smoothstep(350.0f, 370.0f, e2));
    const float2 qb = float2(cos(tht) * q.x + sin(tht) * q.y, -sin(tht) * q.x + cos(tht) * q.y);
    const float3 n = float3(qb, sqrt(max(1.0f - dot(qb, qb), 0.0f)));
    const float dt = ths - tht;
    const float3 s = float3(cos(dt) * sin(i), sin(dt) * sin(i), cos(i));     // the Sun, in the map's frame
    const float lon = atan2(n.x, n.z), lat = asin(clamp(n.y, -1.0f, 1.0f));
    constexpr sampler sm(filter::linear, address::clamp_to_edge, coord::pixel);
    const float2 tc = float2(256.0f + lon * (256.0f / PI_F), 576.0f + clamp((0.5f - lat / PI_F) * 256.0f, 0.5f, 255.5f));
    const float3 al = pow(st.sample(sm, tc).rgb, float3(2.2f));
    const float mu0 = dot(n, s), mu = n.z;
    const float ls = mu0 > 0.0f ? mu0 / (mu0 + mu + 1e-3f) * 2.0f : 0.0f;    // Lommel-Seeliger
    return al * (ls * 1.25f + float3(0.030f, 0.034f, 0.042f) * (1.0f - illum)); // + earthshine (exaggerated)
}

static inline float3 gem_albedo(int b, float2 q) {
    if (b == 2) return mix(float3(0.10f, 0.16f, 0.10f), float3(0.28f, 0.34f, 0.22f), smoothstep(-0.2f, 0.5f, argus_fbm(q * 3.0f + 3.0f, 4)));   // serpentine
    if (b == 3) return mix(float3(0.02f, 0.07f, 0.04f), float3(0.06f, 0.16f, 0.09f), smoothstep(-0.3f, 0.6f, argus_fbm(q * 2.0f + 9.0f, 3))); // chloromelanite
    if (b == 4) return mix(float3(0.30f, 0.025f, 0.012f), float3(0.45f, 0.08f, 0.03f), smoothstep(-0.4f, 0.6f, argus_fbm(q * 4.0f + 1.0f, 4))); // red jasper
    if (b == 5) return mix(float3(0.25f, 0.38f, 0.60f), float3(0.62f, 0.72f, 0.85f), 0.5f + 0.5f * sin(q.y * 11.0f + 2.0f * argus_noise(q * 2.0f))); // blue agate
    if (b == 6) return float3(0.20f, 0.06f, 0.30f) * (0.8f + 0.3f * argus_noise(q * 3.0f));                                          // sugilite
    if (b == 7) return float3(0.18f, 0.48f, 0.52f);                                                                                  // aquamarine
    if (b == 8) { const float py = step(0.985f, hash2(floor((q + 2.0f) * 14.0f), 3.0f));                                              // lapis, pyrite flecks
                  return mix(float3(0.02f, 0.05f, 0.30f), float3(0.9f, 0.7f, 0.3f), py); }
    if (b == 9) return float3(0.10f, 0.09f, 0.09f) * (0.85f + 0.3f * argus_noise(q * 4.0f));                                         // smoky quartz
    return float3(0.85f, 0.83f, 0.80f);                                                                                              // Moon: mother-of-pearl
}
static inline float gem_r(int b) { return b == 0 ? 0.040f : b == 1 ? 0.034f : (b == 5 || b == 6) ? 0.030f : 0.025f; }

// a cabochon: a low dome (flatter than a sphere, so the softbox shows as a broad window), lit from
// the box, with light carried through the stone to the side away from it
static float3 shade_gem(int b, float2 q, Studio S) {
    const float rr = dot(q, q);
    const float3 n = normalize(float3(q * 0.85f, sqrt(max(1.0f - rr, 0.0f)) + 0.15f));
    if (b == 0) {   // the Sun: a polished gold dome engraved with a sunburst
        const float a = atan2(q.y, q.x);
        const float3 nn = normalize(n + float3(-q.y, q.x, 0.0f) * 0.18f * cos(a * 24.0f) * sqrt(rr));
        return gold(nn, 0.22f, S) * float3(1.08f, 1.04f, 0.86f);
    }
    const float3 al = gem_albedo(b, q);
    const float F = schlick(float3(0.05f), dot(n, S.V)).x;
    float3 c = al * irr(n, S) * (1.0f - F) + F * env(refl(n, S), 0.06f, S);
    const float glow = sat(dot(-q, normalize(S.sb.xy))) * (1.0f - rr);      // transmitted light, opposite the box
    c += al * 0.55f * glow;
    if (b == 1) {   // nacre: a soft interference tint that follows the surface
        const float ph = n.z * 9.0f + argus_noise(q * 5.0f) * 2.0f;
        c *= 1.0f + 0.10f * float3(sin(ph), sin(ph + 2.1f), sin(ph + 4.2f));
    }
    return c;
}

static inline int digits(thread int* ids, int n, int v) {
    if (v >= 10) ids[n++] = G_DIG + (v / 10) % 10;
    ids[n++] = G_DIG + v % 10;
    return n;
}

// the label block of body b (glyph; degree, sign and Rx; the coming event): signed distances in px of
// (gold text, the Rx, the event line), so it can be drawn and also cast its shadow
static float3 label_d(texture2d<float> st, float2 p, int b, float lam_b, float disp, float4 ev, float pvw, float ppu) {
    const float2 lg = CP(disp, R_LG);
    const float cx = abs(cos((180.0f + disp) * D2R));            // 1 where the stack runs sideways
    const float sp = 0.056f + 0.058f * cx;
    float d = glyph_px(st, 12 + b, (p - lg) / 0.074f, 0.074f * ppu);
    int ids[8];
    int n = digits(ids, 0, int(fmod(lam_b, 30.0f)));
    ids[n++] = G_DEG; ids[n++] = int(lam_b / 30.0f) % 12;
    const bool rx = ev.w > 0.5f;
    const float s2 = 0.046f;
    float w = 0.0f;
    for (int i = 0; i < n; i++) w += adv(ids[i]);
    const float rxs = b == 2 ? 1.25f : 1.0f;                                // Mercury's Rx a little larger
    const float wt = w + (rx ? 0.15f + 0.78f * rxs : 0.0f);
    const float2 lc = CP(disp, R_LG - sp);
    d = min(d, text_px(st, ids, n, p, lc + float2((w - wt) * 0.5f * s2, 0.0f), s2, ppu));
    float dr = 99.0f;
    if (rx) dr = glyph_px(st, G_RX, (p - lc - float2((0.5f * wt - 0.39f * rxs) * s2, 0.0f)) / (s2 * rxs), s2 * rxs * ppu);
    float de = 99.0f;
    if (ev.x > 0.5f && pvw < 0.5f) {
        const float hrs = ev.y;
        int m = 0;
        if (ev.x == 1.0f) { ids[m++] = G_ARROW; ids[m++] = int(ev.z); }
        else { ids[m++] = G_S; ids[m++] = ev.x == 2.0f ? G_R : G_D; }
        ids[m++] = -1;
        const bool days = hrs >= 23.0f;
        m = digits(ids, m, days ? int(hrs / 24.0f + 0.5f) : max(1, int(ceil(hrs))));
        ids[m++] = days ? G_d : G_h;
        // toward the centre at the top and bottom, straight below the degree line at the sides
        const float2 ep = lc + mix(-CP(disp, 1.0f) * 0.052f, float2(0.0f, -0.046f), cx * cx);
        de = text_px(st, ids, m, p, ep, 0.036f, ppu);
    }
    return float3(d, dr, de);
}

static float3 dial(constant ArgusFrame& f, texture2d<float> st, float2 p, float ppu, Studio S) {
    const float r = length(p);
    const float aa = 1.0f / ppu;
    const float2 rad = r > 1e-5f ? p / r : float2(1, 0);
    const float lam = wrap360(atan2(p.y, p.x) * R2D - 180.0f);
    const float2 kd = normalize(S.sb.xy);                                         // toward the key light
    // ---- outside the dial: dark velvet in the key's pool of light, its pile and nap (faded to the mean
    // below ~3 px), the dial's soft cast shadow and contact darkening
    if (r > R_OUT + aa) {
        const float pool = 0.35f + 0.85f * exp(-dot(p - kd * 0.75f, p - kd * 0.75f) / 1.6f);
        const float pile = 0.82f + 0.18f * argus_noise(p * float2(2.6f, 3.4f) + 7.0f);   // brushed patches
        const float nap_fade = sat((ppu / 170.0f - 1.5f) / 2.0f);
        const float nap = (argus_noise(p * float2(170.0f, 120.0f)) * 0.6f + argus_noise(p * 60.0f + 3.0f) * 0.4f) * nap_fade;
        const float2 off = -kd * (0.075f / max(tan(asin(S.sb.z)), 0.3f));
        const float shd = smoothstep(R_OUT - 0.04f, R_OUT + 0.13f, length(p - off));
        const float ao = 0.50f + 0.50f * smoothstep(R_OUT, R_OUT + 0.06f, r);
        return float3(0.0085f, 0.0078f, 0.0140f) * irr(float3(0, 0, 1), S) * 2.0f * pool * pile * (1.0f + 0.10f * nap) * (0.40f + 0.60f * shd) * ao;
    }
    // ---- bezel: one continuous bead of polished rose gold, from the enamel up to its crest and down to
    // the cloth; its curvature widens the reflected lobe, and the inner flank reflects the dial itself
    if (r > R_Z1) {
        const float RBC = 0.975f;
        const float half_w = r < RBC ? RBC - R_Z1 : R_OUT - RBC;
        const float t = clamp((r - RBC) / half_w, -1.0f, 1.0f);
        const float ang = t * 1.25f;
        const float3 n = normalize(float3(rad * sin(ang), cos(ang)));
        const float rough = 0.035f + 1.0f * 1.25f / (half_w * ppu);
        const float3 R = refl(n, S);
        float3 e = env(R, rough, S);
        const float toward = sat(-dot(R.xy, rad) * 2.0f) * sat(1.0f - R.z * 1.4f);
        e = mix(e, float3(0.010f, 0.022f, 0.12f), toward);
        float3 c = env_brdf(ROSE, rough, dot(n, S.V)) * e;
        c *= 0.55f + 0.45f * smoothstep(0.0f, 0.010f, r - R_Z1);                // where it meets the enamel
        return mix(c, float3(0.003f), smoothstep(R_OUT - aa, R_OUT + aa, r));
    }
    // ---- zodiac ring: translucent night-blue enamel over a flinqué sunburst, gold signs, cloisonné
    if (r > R_Z0) {
        const int sg = int(lam / 30.0f) % 12;
        const float a = atan2(p.y, p.x);
        const float2 tang = float2(-rad.y, rad.x);
        const float ph = a * 880.0f;
        const float groove = 0.5f + 0.5f * cos(ph);                               // 1 in a groove
        const float3 ng = normalize(float3(tang * 0.13f * sin(ph) + rad * 0.05f * sin(r * 520.0f), 1.0f));
        // deep cobalt glass; the engraving shows through as brightness, darker where the glass is deeper
        const float lu = dot(env(refl(ng, S), 0.28f, S), float3(0.3f, 0.5f, 0.2f));
        float3 c = float3(0.010f, 0.030f, 0.22f) * (0.12f + 0.55f * lu) * (1.15f - 0.35f * groove);
        // the fired glass is gently domed across the ring: a clear coat (GGX ~0.1) catches the lights
        const float u = (r - 0.5f * (R_Z0 + R_Z1)) / (0.5f * (R_Z1 - R_Z0));
        const float3 ns = normalize(float3(rad * u * 0.22f, 1.0f));
        c += env_brdf(float3(0.04f), 0.10f, dot(ns, S.V)) * env(refl(ns, S), 0.10f, S);
        c *= 0.55f + 0.45f * smoothstep(0.0f, 0.016f, R_Z1 - r);                // the bezel's shadow on the glass
        // gold sign glyph, upright, applied in relief
        const float lm = float(sg) * 30.0f + 15.0f;
        const float2 gc = CP(lm, 0.5f * (R_Z0 + R_Z1));
        const float gs = 0.090f;
        const float d = glyph_px(st, sg, (p - gc) / gs, gs * ppu);
        const float dsh = glyph_px(st, sg, (p + kd * 0.0035f - gc) / gs, gs * ppu);   // applied: it casts a shadow
        c *= 1.0f - 0.55f * sat(1.0f - (dsh + 1.0f) / 4.0f);
        if (d < 1.5f) {
            const float dx = glyph_px(st, sg, (p + float2(aa, 0) - gc) / gs, gs * ppu) - d;
            const float dy = glyph_px(st, sg, (p + float2(0, aa) - gc) / gs, gs * ppu) - d;
            const float bev = sat(1.0f + d / 2.2f);
            const float3 n = normalize(float3(float2(dx, dy) * 0.9f * bev, 1.0f));
            c = mix(c, gold(n, 0.18f, S), sat(0.5f - d));
        }
        // cloisonné wires: sign boundaries and the ring's rims
        const float db = abs(fract(lam / 30.0f + 0.5f) - 0.5f) * 30.0f * D2R * r;
        const float w1 = 0.0035f;
        float wire = 1.0f - smoothstep(w1 - aa, w1 + aa, db);
        const float dr = min(abs(r - R_Z0), abs(r - R_Z1));
        wire = max(wire, 1.0f - smoothstep(w1 - aa, w1 + aa, dr));
        if (wire > 0.0f) {
            const float x = db < dr ? db / w1 * (fract(lam / 30.0f + 0.5f) > 0.5f ? 1.0f : -1.0f) : (r - (abs(r - R_Z0) < abs(r - R_Z1) ? R_Z0 : R_Z1)) / w1;
            const float2 dir = db < dr ? tang : rad;
            const float3 n = normalize(float3(dir * clamp(x, -0.9f, 0.9f), sqrt(1.0f - min(x * x, 0.81f))));
            c = mix(c, gold(n, 0.08f, S), wire);
        }
        return c;
    }
    // ---- chapter ring: polished rose gold with fine circular graining, engraved degrees filled black
    if (r > R_D0) {
        // circular brushing: grooves run round the ring, so the lobe is stretched across them (radially),
        // and the lights show as a soft radial "bow tie"
        float3 c = float3(0.0f);
        for (int k = -2; k <= 2; k++) c += gold(normalize(float3(rad * 0.16f * float(k), 1.0f)), 0.14f, S);
        c *= 0.2f;
        const float dd = abs(fract(lam + 0.5f) - 0.5f) * D2R * r;
        const float di = floor(lam + 0.5f);
        const float len = fmod(di, 30.0f) == 0.0f ? 1.0f : fmod(di, 10.0f) == 0.0f ? 0.62f : fmod(di, 5.0f) == 0.0f ? 0.44f : 0.24f;
        const float w = fmod(di, 30.0f) == 0.0f ? 0.0018f : 0.0009f;
        const float tick = (1.0f - smoothstep(w - 0.6f * aa, w + 0.6f * aa, dd)) * step(R_Z0 - len * (R_Z0 - R_D0), r);
        const float eng = max(tick, 1.0f - smoothstep(0.0012f - aa, 0.0012f + aa, abs(r - R_D0 - 0.0045f)));
        c = mix(c, float3(0.006f, 0.005f, 0.005f), eng * 0.95f);
        c *= 0.75f + 0.25f * smoothstep(R_D0, R_D0 + 0.006f, r);                   // the step down to the glass
        return c;
    }
    // ---- inside: blue aventurine glass (cobalt glass with copper crystals)
    const float4 mo = st.read(uint2(0, ROW_MOON));
    float3 c;
    {
        const float m = argus_fbm(p * 2.5f + 4.0f, 4);
        const float3 base = mix(float3(0.0013f, 0.0022f, 0.0105f), float3(0.0030f, 0.0050f, 0.020f), 0.5f + 0.5f * m);
        c = base * irr(float3(0, 0, 1), S) * 2.2f + schlick(float3(0.04f), S.V.z) * env(refl(float3(0, 0, 1), S), 0.02f, S);
        // crystals: tiny tilted mirrors in the glass; each lights only when it mirrors a light
        const float2 g = p * 300.0f;
        const float2 cell = floor(g);
        const float h0 = hash2(cell, 11.0f);
        if (h0 > 0.62f) {
            const float2 o = float2(hash2(cell, 12.0f), hash2(cell, 13.0f)) - 0.5f;
            const float2 fp = fract(g) - 0.5f - o * 0.6f;
            const float2 tilt = (float2(hash2(cell, 14.0f), hash2(cell, 15.0f)) - 0.5f) * 1.0f;
            const float3 nf = normalize(float3(tilt, 1.0f));
            const float3 tint = mix(float3(1.0f, 0.55f, 0.30f), float3(1.0f, 0.80f, 0.55f), hash2(cell, 16.0f));
            const float size = 0.10f + 0.22f * hash2(cell, 17.0f);
            const float cov = exp(-dot(fp, fp) / (size * size) * 2.0f) * size * size * 6.0f;
            const float k = pow(hash2(cell, 18.0f), 3.0f) * 1.6f + 0.05f;          // most crystals small, a few large
            c += tint * env(refl(nf, S), 0.0f, S) * cov * k;
        }
    }
    // ---- aspect threads and the aspect ring
    if (r < R_ASP + 0.01f) {
        if (r < R_ASP) for (int k = 0; k < 45; k++) {
            const float4 a = st.read(uint2(k, ROW_ASP));
            if (a.z < 0.0f) continue;
            const float2 p0 = CP(a.x, R_ASP), p1 = CP(a.y, R_ASP);
            const float2 ba = p1 - p0; const float hh = sat(dot(p - p0, ba) / dot(ba, ba));
            const float2 dv = p - p0 - ba * hh;
            const float d = length(dv);
            const float w = 0.0010f + 0.0010f * a.w;
            if (d < w + 0.003f) {
                const float3 en = (a.z == 1.0f || a.z == 3.0f) ? float3(0.24f, 0.012f, 0.016f) : float3(0.012f, 0.045f, 0.26f);
                const float fill = (1.0f - smoothstep(w - aa, w + aa, d)) * (0.55f + 0.45f * a.w);
                c = mix(c, en * (irr(float3(0, 0, 1), S) * 0.6f + 0.10f), fill);
                const float edge = (1.0f - smoothstep(0.0005f - aa, 0.0005f + aa, abs(d - w - 0.0006f))) * (0.5f + 0.5f * a.w);
                c = mix(c, gold(normalize(float3(-dv / max(d, 1e-5f) * 0.2f, 1.0f)), 0.25f, S), edge * 0.7f);
            }
        }
        const float x = (r - R_ASP) / 0.0028f;
        if (abs(x) < 1.0f) c = mix(c, gold(normalize(float3(rad * x * 0.9f, sqrt(1.0f - 0.81f * x * x))), 0.06f, S), 1.0f - smoothstep(0.8f, 1.0f, abs(x)));
    }
    // ---- the Moon medallion, its phase and sign engraved beneath
    if (r < R_MEDB + 0.012f) {
        if (r < R_MED) {
            const float3 m = moon_face(st, p / R_MED, mo.x, mo.y, normalize(CP(mo.z, 1.0f)));
            const float3 n = normalize(float3(p / R_MED * 0.55f, 1.0f));
            return m + 0.06f * pow(1.0f - dot(n, S.V), 4.0f) * float3(0.8f, 0.82f, 0.85f);
        }
        if (r < R_MEDB) {
            const float t = (r - 0.5f * (R_MED + R_MEDB)) / (0.5f * (R_MEDB - R_MED));
            return gold(normalize(float3(rad * t * 0.95f, sqrt(max(1.0f - 0.9f * t * t, 0.02f)))), 0.05f, S);
        }
        c *= 0.45f + 0.55f * smoothstep(R_MEDB, R_MEDB + 0.012f, length(p - float2(0.006f, -0.009f)));
    }
    const float2 pv = preview(f.time);
    if (abs(p.x) < 0.20f && p.y < -0.19f && p.y > -0.31f) {
        const float e = mo.x;
        const int ph = (e < 7.0f || e > 353.0f) ? 0 : abs(e - 90.0f) < 7.0f ? 2 : abs(e - 180.0f) < 7.0f ? 4 : abs(e - 270.0f) < 7.0f ? 6
                     : e < 90.0f ? 1 : e < 180.0f ? 3 : e < 270.0f ? 5 : 7;
        int ids[16];
        int n = 0;
        for (int i = 0; i < 16 && PHASE[ph][i] != -2; i++) ids[n++] = PHASE[ph][i];
        float d = text_px(st, ids, n, p, float2(0.0f, -0.215f), 0.036f, ppu);
        const float ml = mo.w;
        int m = 0;
        ids[m++] = 13; ids[m++] = -1;
        m = digits(ids, m, int(fmod(ml, 30.0f)));
        ids[m++] = G_DEG; ids[m++] = int(ml / 30.0f) % 12;
        d = min(d, text_px(st, ids, m, p, float2(0.0f, -0.268f), 0.040f, ppu));
        // during the look-ahead: "Preview" and the local date being shown, in place of the phase
        float dp = 99.0f;
        if (pv.y > 0.0f) {
            for (int i = 0; i < 7; i++) ids[i] = PREVIEW_W[i];
            dp = text_px(st, ids, 7, p, float2(0.0f, -0.215f), 0.040f, ppu);
            const float x = f.day_frac + 0.5f + pv.x + float(f.utc_offset_s) / 86400.0f;
            const int2 md = month_day(f.days_j2000 + int(floor(x)) + 10957);
            int k = 0;
            for (int i = 0; i < 3; i++) ids[k++] = MONTH[md.x - 1][i];
            ids[k++] = -1;
            k = digits(ids, k, md.y);
            dp = min(dp, text_px(st, ids, k, p, float2(0.0f, -0.268f), 0.044f, ppu));
        }
        const float cov = mix(sat(0.5f - d), sat(0.5f - dp), pv.y);
        if (cov > 0.0f) c = mix(c, gold(float3(0, 0, 1), 0.46f, S) * (1.0f + 0.25f * pv.y), cov);
    }
    // ---- bodies: degree marks on the aspect ring, leaders, gems, labels
    for (int b = 0; b < 10; b++) {
        const float4 bd = st.read(uint2(b, ROW_BODY));
        const float lam_b = bd.x, disp = bd.w;
        const float gr = gem_r(b);
        const float2 gc = CP(disp, R_GEM);
        // the true longitude: a gold dot on the aspect ring, a leader from the degree scale to the gem
        const float2 ad = CP(lam_b, R_ASP);
        if (length(p - ad) < 0.012f) c = mix(c, gold(normalize(float3((p - ad) / 0.0075f * 0.7f, 1.0f)), 0.08f, S), 1.0f - smoothstep(0.0062f - aa, 0.0062f + aa, length(p - ad)));
        {
            const float2 t0 = CP(lam_b, R_D0), t1 = gc + normalize(CP(lam_b, R_D0) - gc) * gr * 1.12f;
            const float2 ba = t1 - t0; const float hh = sat(dot(p - t0, ba) / dot(ba, ba));
            const float dl = length(p - t0 - ba * hh);
            if (dl < 0.004f) c = mix(c, gold(float3(0, 0, 1), 0.14f, S), 1.0f - smoothstep(0.0010f - aa, 0.0010f + aa, dl));
        }
        // soft contact shadow, the collet, the cabochon
        const float dg = length(p - gc);
        if (dg < gr * 1.6f + 0.02f) {
            c *= 1.0f - 0.60f * (1.0f - smoothstep(gr * 0.80f, gr * 1.55f, length(p - gc + kd * 0.010f)));   // cast
            c *= 1.0f - 0.35f * (1.0f - smoothstep(gr * 1.0f, gr * 1.25f, dg));                                // contact
            if (dg < gr * 1.10f) {
                if (dg > gr) {
                    const float t = (dg - gr * 1.05f) / (gr * 0.05f);
                    c = gold(normalize(float3((p - gc) / dg * t * 0.9f, sqrt(max(1.0f - 0.8f * t * t, 0.05f)))), 0.06f, S);
                } else c = shade_gem(b, (p - gc) / gr, S);
            }
            if (b == 6) {   // Saturn's ring: a fine gold wire, tilted, passing behind the stone at the top
                const float2 q = (p - gc) / gr;
                const float2 qq = float2(q.x * 0.94f + q.y * 0.34f, (-q.x * 0.34f + q.y * 0.94f) * 3.2f);
                const float wire = 1.0f - smoothstep(0.035f * 3.2f, (0.035f + aa / gr) * 3.2f, abs(length(qq) - 1.6f * 3.2f * 0.0f - 1.6f));
                if (wire > 0.0f && !(qq.y > 0.0f && dot(q, q) < 1.0f)) c = mix(c, gold(normalize(float3(0.0f, -0.3f * sign(qq.y), 1.0f)), 0.35f, S) * 0.8f, wire);
            }
        }
        // labels on the gem's line, toward the centre: glyph; degree, sign, Rx; the coming event
        const float2 lg = CP(disp, R_LG);
        if (length(p - lg) < 0.26f) {
            const float4 ev = st.read(uint2(b, ROW_EVENT));
            const float3 L = label_d(st, p, b, lam_b, disp, ev, pv.y, ppu);
            const float d = L.x, dr = L.y, de = L.z;
            // applied gold casts a soft shadow away from the key
            const float3 Ls = label_d(st, p + kd * 0.0032f, b, lam_b, disp, ev, pv.y, ppu);
            c *= 1.0f - 0.5f * sat(1.0f - (min(min(Ls.x, Ls.y), Ls.z) + 1.0f) / 4.0f);
            // gold in relief: a soft bevel from the distance field
            const float dm = min(d, de);
            const float bv = sat(1.0f + dm / 1.5f);
            if (dm < 1.5f) c = mix(c, gold(normalize(float3(-0.08f * bv, 0.08f * bv, 1.0f)), 0.42f, S) * (de < d ? 0.80f : 1.0f), sat(0.5f - dm));
            // garnet enamel Rx
            if (dr < 1.5f) c = mix(c, float3(0.35f, 0.03f, 0.03f) * (irr(float3(0, 0, 1), S) * 0.8f + 0.12f) + env_brdf(float3(0.04f), 0.15f, S.V.z) * env(refl(float3(0, 0, 1), S), 0.15f, S), sat(0.5f - dr));
        }
    }
    return c;
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> state [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const float2 uv = argus_uv(gid, f);
    const float ppu = 0.5f * float(min(f.width, f.height)) * DIAL_R;
    Studio S = studio(f.time);
    const float2 p = (uv - float2(0.0f, DIAL_Y)) / DIAL_R;
    S.V = normalize(float3(-p, CAM_D));
    const float3 c = dial(f, state, p, ppu, S);
    out.write(float4(argus_srgb(argus_aces(c * 1.6f)), 1.0f), gid);
}

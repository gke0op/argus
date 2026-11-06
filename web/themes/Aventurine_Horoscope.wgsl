// AVENTURINE HOROSCOPE // themes/Aventurine_Horoscope.metal
// web/themes/Aventurine_Horoscope.wgsl: the one-to-one WGSL translation of themes/Aventurine_Horoscope.metal.
// Claude (Anthropic), 2026-10-19.
//
// What you see: the sky right now, read the way Western astrology reads it, made as one piece of
// jewellery. An astrology chart wheel (0 deg Aries at 9 o'clock, the signs counter-clockwise) in
// blue aventurine glass, with a ring of translucent enamel over guilloche, rose gold and a gem for
// each body, photographed straight on under a softbox. Each gem stands at its body's real place in
// the zodiac (a gold stud in the aspect groove marks the exact degree), with its glyph, its degree and sign (floored,
// as ephemerides print them), a garnet R-x while it is retrograde, and the next event within 7 days:
// "-> (sign) 5h" enters a sign, "SR 4d" / "SD 5d" stations retrograde / direct (hours under a day,
// else days). Grooves etched in the glass join bodies in a major aspect (garnet: square, opposition;
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
//     gems spread to >= 14 deg apart when they crowd (the stud shows the true degree), eased 0.5 s;
//     orbs 6 deg with the Sun or Moon, else 4; no conjunction grooves; events shown within 7 days
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
//     no wires between the signs (the degree ring's full-width 30 deg ticks mark them); a flinque
//     sunburst of one ray per degree, faded as the pixel grows against it; no crystals within ~2-5 px
//     of a gold edge; copper crystals in cobalt glass; every fine line at least a pixel wide and box-filtered over the
//     pixel (energy kept, never dotted); aspects as V-grooves 4-6 px wide with frosted walls and an
//     enamel floor; the stones set flush (no gold rims), each with a faint ~3 px glow of its own colour; the degree ring's edges filtered over the pixel;
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
const D2R: f32 = 0.01745329252f; const R2D: f32 = 57.2957795131f; const TAU: f32 = 6.28318530718f;
const TT_UTC_D: f32 = 69.184f / 86400.0f;      // TT - UTC: 32.184 s + 37 leap seconds (since 2017)
const AU_KM: f32 = 149597870.7f;
const C_AU_D: f32 = 173.1446327f;              // light: au per day
const KAPPA: f32 = 20.49552f / 3600.0f;        // constant of aberration, deg

// state rows
const ROW_BODY: i32 = 832; const ROW_EVENT: i32 = 833; const ROW_ASP: i32 = 834; const ROW_MOON: i32 = 835; const ROW_SAMP: i32 = 836; const ROW_LATCH: i32 = 846;
const NSAMP: i32 = 216; const SAMP0: i32 = 24;              // hourly samples from -24 h to +191 h

// JPL "Approximate Positions of the Planets", Table 1 (1800-2050); Pluto: the same table before 2015.
// a, e, I, L, long. perihelion, long. node at J2000, and their rates per Julian century.
const EL0 = array<array<f32, 6>, 9>(
    array<f32, 6>(0.38709927f, 0.20563593f, 7.00497902f, 252.25032350f, 77.45779628f, 48.33076593f),  // Mercury
    array<f32, 6>(0.72333566f, 0.00677672f, 3.39467605f, 181.97909950f, 131.60246718f, 76.67984255f),  // Venus
    array<f32, 6>(1.00000261f, 0.01671123f, -0.00001531f, 100.46457166f, 102.93768193f, 0.00000000f),  // EMB
    array<f32, 6>(1.52371034f, 0.09339410f, 1.84969142f, -4.55343205f, -23.94362959f, 49.55953891f),  // Mars
    array<f32, 6>(5.20288700f, 0.04838624f, 1.30439695f, 34.39644051f, 14.72847983f, 100.47390909f),  // Jupiter
    array<f32, 6>(9.53667594f, 0.05386179f, 2.48599187f, 49.95424423f, 92.59887831f, 113.66242448f),  // Saturn
    array<f32, 6>(19.18916464f, 0.04725744f, 0.77263783f, 313.23810451f, 170.95427630f, 74.01692503f),  // Uranus
    array<f32, 6>(30.06992276f, 0.00859048f, 1.77004347f, -55.12002969f, 44.96476227f, 131.78422574f),  // Neptune
    array<f32, 6>(39.48211675f, 0.24882730f, 17.14001206f, 238.92903833f, 224.06891629f, 110.30393684f),  // Pluto
);
const ELR = array<array<f32, 6>, 9>(
    array<f32, 6>(0.00000037f, 0.00001906f, -0.00594749f, 149472.67411175f, 0.16047689f, -0.12534081f),
    array<f32, 6>(0.00000390f, -0.00004107f, -0.00078890f, 58517.81538729f, 0.00268329f, -0.27769418f),
    array<f32, 6>(0.00000562f, -0.00004392f, -0.01294668f, 35999.37244981f, 0.32327364f, 0.00000000f),
    array<f32, 6>(0.00001847f, 0.00007882f, -0.00813131f, 19140.30268499f, 0.44441088f, -0.29257343f),
    array<f32, 6>(-0.00011607f, -0.00013253f, -0.00183714f, 3034.74612775f, 0.21252668f, 0.20469106f),
    array<f32, 6>(-0.00125060f, -0.00050991f, 0.00193609f, 1222.49362201f, -0.41897216f, -0.28867794f),
    array<f32, 6>(-0.00196176f, -0.00004397f, -0.00242939f, 428.48202785f, 0.40805281f, 0.04240589f),
    array<f32, 6>(0.00026291f, 0.00005105f, 0.00035372f, 218.45945325f, -0.32241464f, -0.00508664f),
    array<f32, 6>(-0.00031596f, 0.00005170f, 0.00004818f, 145.20780515f, -0.04062942f, -0.01183482f),
);
// L rate as whole turns per day x 2^32 (exact modular arithmetic on the day count)
const ELR_LR = array<u32, 9>(48823503u, 19114161u, 11758775u, 6251956u, 991264u, 399313u, 139959u, 71357u, 47430u);
// Meeus ch. 47: L', D, M, M', F, A1, A2, A3 at J2000 (deg) and rates (deg per century)
const MA0 = array<f32, 8>(218.3164477f, 297.8501921f, 357.5291092f, 134.9633964f, 93.2720950f, 119.7500000f, 53.0900000f, 313.4500000f);
const MAR = array<f32, 8>(481267.88123421f, 445267.11140340f, 35999.05029090f, 477198.86750550f, 483202.01752330f, 131.84900000f, 479264.29000000f, 481266.48400000f);
const MAR_R = array<u32, 8>(157200533u, 145441302u, 11758669u, 155871437u, 157832296u, 43067u, 156546083u, 157200077u);
// Table 47.A: multiples of D, M, M', F; Sigma-l (1e-6 deg) and Sigma-r (1e-3 km)
const MLR_ARG = array<vec4i, 60>(vec4i(0,0,1,0), vec4i(2,0,-1,0), vec4i(2,0,0,0), vec4i(0,0,2,0), vec4i(0,1,0,0), vec4i(0,0,0,2), vec4i(2,0,-2,0), vec4i(2,-1,-1,0), vec4i(2,0,1,0), vec4i(2,-1,0,0), vec4i(0,1,-1,0), vec4i(1,0,0,0), vec4i(0,1,1,0), vec4i(2,0,0,-2), vec4i(0,0,1,2), vec4i(0,0,1,-2), vec4i(4,0,-1,0), vec4i(0,0,3,0), vec4i(4,0,-2,0), vec4i(2,1,-1,0), vec4i(2,1,0,0), vec4i(1,0,-1,0), vec4i(1,1,0,0), vec4i(2,-1,1,0), vec4i(2,0,2,0), vec4i(4,0,0,0), vec4i(2,0,-3,0), vec4i(0,1,-2,0), vec4i(2,0,-1,2), vec4i(2,-1,-2,0), vec4i(1,0,1,0), vec4i(2,-2,0,0), vec4i(0,1,2,0), vec4i(0,2,0,0), vec4i(2,-2,-1,0), vec4i(2,0,1,-2), vec4i(2,0,0,2), vec4i(4,-1,-1,0), vec4i(0,0,2,2), vec4i(3,0,-1,0), vec4i(2,1,1,0), vec4i(4,-1,-2,0), vec4i(0,2,-1,0), vec4i(2,2,-1,0), vec4i(2,1,-2,0), vec4i(2,-1,0,-2), vec4i(4,0,1,0), vec4i(0,0,4,0), vec4i(4,-1,0,0), vec4i(1,0,-2,0), vec4i(2,1,0,-2), vec4i(0,0,2,-2), vec4i(1,1,1,0), vec4i(3,0,-2,0), vec4i(4,0,-3,0), vec4i(2,-1,2,0), vec4i(0,2,1,0), vec4i(1,1,-1,0), vec4i(2,0,3,0), vec4i(2,0,-1,-2));
const MLR_C = array<vec2f, 60>(vec2f(6288774.0f,-20905355.0f), vec2f(1274027.0f,-3699111.0f), vec2f(658314.0f,-2955968.0f), vec2f(213618.0f,-569925.0f), vec2f(-185116.0f,48888.0f), vec2f(-114332.0f,-3149.0f), vec2f(58793.0f,246158.0f), vec2f(57066.0f,-152138.0f), vec2f(53322.0f,-170733.0f), vec2f(45758.0f,-204586.0f), vec2f(-40923.0f,-129620.0f), vec2f(-34720.0f,108743.0f), vec2f(-30383.0f,104755.0f), vec2f(15327.0f,10321.0f), vec2f(-12528.0f,0.0f), vec2f(10980.0f,79661.0f), vec2f(10675.0f,-34782.0f), vec2f(10034.0f,-23210.0f), vec2f(8548.0f,-21636.0f), vec2f(-7888.0f,24208.0f), vec2f(-6766.0f,30824.0f), vec2f(-5163.0f,-8379.0f), vec2f(4987.0f,-16675.0f), vec2f(4036.0f,-12831.0f), vec2f(3994.0f,-10445.0f), vec2f(3861.0f,-11650.0f), vec2f(3665.0f,14403.0f), vec2f(-2689.0f,-7003.0f), vec2f(-2602.0f,0.0f), vec2f(2390.0f,10056.0f), vec2f(-2348.0f,6322.0f), vec2f(2236.0f,-9884.0f), vec2f(-2120.0f,5751.0f), vec2f(-2069.0f,0.0f), vec2f(2048.0f,-4950.0f), vec2f(-1773.0f,4130.0f), vec2f(-1595.0f,0.0f), vec2f(1215.0f,-3958.0f), vec2f(-1110.0f,0.0f), vec2f(-892.0f,3258.0f), vec2f(-810.0f,2616.0f), vec2f(759.0f,-1897.0f), vec2f(-713.0f,-2117.0f), vec2f(-700.0f,2354.0f), vec2f(691.0f,0.0f), vec2f(596.0f,0.0f), vec2f(549.0f,-1423.0f), vec2f(537.0f,-1117.0f), vec2f(520.0f,-1571.0f), vec2f(-487.0f,-1739.0f), vec2f(-399.0f,0.0f), vec2f(-381.0f,-4421.0f), vec2f(351.0f,0.0f), vec2f(-340.0f,0.0f), vec2f(330.0f,0.0f), vec2f(327.0f,0.0f), vec2f(-323.0f,1165.0f), vec2f(299.0f,0.0f), vec2f(294.0f,0.0f), vec2f(0.0f,8752.0f));
// Table 47.B: multiples of D, M, M', F; Sigma-b (1e-6 deg)
const MB_ARG = array<vec4i, 60>(vec4i(0,0,0,1), vec4i(0,0,1,1), vec4i(0,0,1,-1), vec4i(2,0,0,-1), vec4i(2,0,-1,1), vec4i(2,0,-1,-1), vec4i(2,0,0,1), vec4i(0,0,2,1), vec4i(2,0,1,-1), vec4i(0,0,2,-1), vec4i(2,-1,0,-1), vec4i(2,0,-2,-1), vec4i(2,0,1,1), vec4i(2,1,0,-1), vec4i(2,-1,-1,1), vec4i(2,-1,0,1), vec4i(2,-1,-1,-1), vec4i(0,1,-1,-1), vec4i(4,0,-1,-1), vec4i(0,1,0,1), vec4i(0,0,0,3), vec4i(0,1,-1,1), vec4i(1,0,0,1), vec4i(0,1,1,1), vec4i(0,1,1,-1), vec4i(0,1,0,-1), vec4i(1,0,0,-1), vec4i(0,0,3,1), vec4i(4,0,0,-1), vec4i(4,0,-1,1), vec4i(0,0,1,-3), vec4i(4,0,-2,1), vec4i(2,0,0,-3), vec4i(2,0,2,-1), vec4i(2,-1,1,-1), vec4i(2,0,-2,1), vec4i(0,0,3,-1), vec4i(2,0,2,1), vec4i(2,0,-3,-1), vec4i(2,1,-1,1), vec4i(2,1,0,1), vec4i(4,0,0,1), vec4i(2,-1,1,1), vec4i(2,-2,0,-1), vec4i(0,0,1,3), vec4i(2,1,1,-1), vec4i(1,1,0,-1), vec4i(1,1,0,1), vec4i(0,1,-2,-1), vec4i(2,1,-1,-1), vec4i(1,0,1,1), vec4i(2,-1,-2,-1), vec4i(0,1,2,1), vec4i(4,0,-2,-1), vec4i(4,-1,-1,-1), vec4i(1,0,1,-1), vec4i(4,0,1,-1), vec4i(1,0,-1,-1), vec4i(4,-1,0,-1), vec4i(2,-2,0,1));
const MB_C = array<f32, 60>(5128122.0f, 280602.0f, 277693.0f, 173237.0f, 55413.0f, 46271.0f, 32573.0f, 17198.0f, 9266.0f, 8822.0f, 8216.0f, 4324.0f, 4200.0f, -3359.0f, 2463.0f, 2211.0f, 2065.0f, -1870.0f, 1828.0f, -1794.0f, -1749.0f, -1565.0f, -1491.0f, -1475.0f, -1410.0f, -1344.0f, -1335.0f, 1107.0f, 1021.0f, 833.0f, 777.0f, 671.0f, 607.0f, 596.0f, 491.0f, -451.0f, 439.0f, 422.0f, 421.0f, -366.0f, -351.0f, 331.0f, 315.0f, 302.0f, -283.0f, -229.0f, 223.0f, 223.0f, -220.0f, -220.0f, -185.0f, 181.0f, -177.0f, 176.0f, 166.0f, -164.0f, 132.0f, -119.0f, 115.0f, 107.0f);
// 60 LR rows, 60 B rows


struct Tm { n: i32, fr: f32 }                      // TT days since J2000.0 = n + fr

fn wrap360(a: f32) -> f32 { return a - 360.0f * floor(a * (1.0f / 360.0f)); }
fn wrap180(a: f32) -> f32 { return wrap360(a + 180.0f) - 180.0f; }
fn sinr(x: f32) -> f32 { return sin(x - TAU * round(x * (1.0f / TAU))); }   // Metal rint = WGSL round (half to even)
fn cosr(x: f32) -> f32 { return cos(x - TAU * round(x * (1.0f / TAU))); }
// a0 + rate * (n + fr) / 36525 in degrees, mod 360. The whole days go through exact 32-bit modular
// arithmetic (R = turns per day x 2^32), so float32 keeps the Moon to ~1" for decades.
fn lin_angle(R: u32, a0: f32, rate_cy: f32, t: Tm) -> f32 {
    let whole = f32(u32(t.n) * R) * (360.0f / 4294967296.0f);
    return wrap360(whole + a0 + rate_cy * (t.fr * (1.0f / 36525.0f)));
}
fn cent(t: Tm) -> f32 { return (f32(t.n) + t.fr) * (1.0f / 36525.0f); }

// heliocentric J2000 ecliptic position (au) of element set i (JPL's Keplerian recipe)
fn helio(i: i32, t: Tm) -> vec3f {
    let T = cent(t);
    let a = EL0[i][0] + ELR[i][0] * T; let e = EL0[i][1] + ELR[i][1] * T;
    let I = (EL0[i][2] + ELR[i][2] * T) * D2R;
    let L = lin_angle(ELR_LR[i], EL0[i][3], ELR[i][3], t);
    let wb = EL0[i][4] + ELR[i][4] * T; let Om = (EL0[i][5] + ELR[i][5] * T) * D2R;
    let w = wb * D2R - Om;
    let M = (wrap360(L - wb + 180.0f) - 180.0f) * D2R;
    var E = M + e * sin(M);
    for (var k = 0; k < 6; k++) { E -= (E - e * sin(E) - M) / (1.0f - e * cos(E)); }
    let xp = a * (cos(E) - e); let yp = a * sqrt(1.0f - e * e) * sin(E);
    let cw = cos(w); let sw = sin(w); let cO = cos(Om); let sO = sin(Om); let cI = cos(I); let sI = sin(I);
    return vec3f((cw * cO - sw * sO * cI) * xp + (-sw * cO - cw * sO * cI) * yp,
                 (cw * sO + sw * cO * cI) * xp + (-sw * sO + cw * cO * cI) * yp,
                 (sw * sI) * xp + (cw * sI) * yp);
}

// geocentric Moon, mean equinox of date (Meeus ch. 47, all 60 + 60 terms): lon, lat (deg), dist (km)
fn moon_meeus(t: Tm) -> vec3f {
    let T = cent(t);
    var A: array<f32, 8>;
    for (var k = 0; k < 8; k++) { A[k] = lin_angle(MAR_R[k], MA0[k], MAR[k], t); }
    let Lp = A[0] - 0.0015786f * T * T; let D = A[1] - 0.0018819f * T * T; let M = A[2] - 0.0001536f * T * T;
    let Mp = A[3] + 0.0087414f * T * T; let F = A[4] - 0.0036539f * T * T;
    let E = 1.0f - 0.002516f * T - 0.0000074f * T * T;
    let g = vec4f(D, M, Mp, F) * D2R;
    var sl = 0.0f; var sr = 0.0f; var sb = 0.0f;
    for (var i = 0; i < 60; i++) {
        let m = vec4f(MLR_ARG[i]);
        let x = dot(m, g);
        let k = select(select(1.0f, E * E, abs(m.y) == 2.0f), E, abs(m.y) == 1.0f);
        sl += MLR_C[i].x * k * sinr(x);
        sr += MLR_C[i].y * k * cosr(x);
    }
    for (var i = 0; i < 60; i++) {
        let m = vec4f(MB_ARG[i]);
        let k = select(select(1.0f, E * E, abs(m.y) == 2.0f), E, abs(m.y) == 1.0f);
        sb += MB_C[i] * k * sinr(dot(m, g));
    }
    let a1 = A[5] * D2R; let a2 = A[6] * D2R; let a3 = A[7] * D2R; let lp = Lp * D2R; let mp = Mp * D2R; let f = F * D2R;
    sl += 3958.0f * sinr(a1) + 1962.0f * sinr(lp - f) + 318.0f * sinr(a2);
    sb += -2235.0f * sinr(lp) + 382.0f * sinr(a3) + 175.0f * sinr(a1 - f) + 175.0f * sinr(a1 + f)
          + 127.0f * sinr(lp - mp) - 115.0f * sinr(lp + mp);
    return vec3f(wrap360(Lp + sl * 1e-6f), sb * 1e-6f, 385000.56f + sr * 1e-3f);
}

fn lonlatr(v: vec3f) -> vec3f {
    return vec3f(wrap360(atan2(v.y, v.x) * R2D), atan2(v.z, length(v.xy)) * R2D, length(v));
}

// apparent geocentric ecliptic longitude and latitude of date (deg) and distance (au) of body b:
// 0 Sun, 1 Moon, 2 Mercury, 3 Venus, 4 Mars, 5 Jupiter, 6 Saturn, 7 Uranus, 8 Neptune, 9 Pluto
fn body_pos(b: i32, t: Tm) -> vec3f {
    let T = cent(t);
    let mo = moon_meeus(t);
    let Om = (125.04452f - 1934.136261f * T) * D2R; let Ls = (280.4665f + 36000.7698f * T) * D2R;
    let Lm = (218.3165f + 481267.8813f * T) * D2R;
    let dpsi = (-17.20f * sinr(Om) - 1.32f * sinr(2.0f * Ls) - 0.23f * sinr(2.0f * Lm) + 0.21f * sinr(2.0f * Om)) / 3600.0f;
    if (b == 1) { return vec3f(wrap360(mo.x + dpsi), mo.y, mo.z / AU_KM); }
    let pr = (5028.796195f * T + 1.1054348f * T * T) / 3600.0f;   // general precession in longitude
    let ml = (mo.x - pr) * D2R; let mb = mo.y * D2R;
    let mv = vec3f(cos(mb) * cos(ml), cos(mb) * sin(ml), sin(mb)) * (mo.z / AU_KM / 82.3006f);
    let earth = helio(2, t) - mv;                                  // Earth = EMB - Moon/(1+81.3)
    let sv = lonlatr(-earth);
    let sun = sv.x + pr + dpsi;
    if (b == 0) { return vec3f(wrap360(sun - KAPPA / cos(sv.y * D2R)), sv.y, sv.z); }
    let i = select(select(b - 1, 1, b == 3), 0, b == 2);
    var tau = 0.0f; var p = vec3f(0.0f);
    for (var k = 0; k < 2; k++) {
        p = lonlatr(helio(i, Tm(t.n, t.fr - tau)) - earth);
        tau = p.z / C_AU_D;
    }
    let lon = p.x + pr + dpsi;
    return vec3f(wrap360(lon - KAPPA * cos((sun - lon) * D2R) / cos(p.y * D2R)), p.y, p.z);
}

// the look-ahead: PV_FIRST seconds after load and every PV_PERIOD after that, the dial winds PV_DAYS
// forward (14 s, eased), holds 3 s and returns to now (5 s). Returns (days ahead, the preview's
// weight 0..1). 300 s divides the 4 h wrap of f.time, so the rhythm runs on across it.
const PV_PERIOD: f32 = 300.0f; const PV_FIRST: f32 = 30.0f; const PV_DAYS: f32 = 30.0f;
fn preview(t: f32) -> vec2f {
    var u = (t + PV_PERIOD - PV_FIRST) % PV_PERIOD;
    if (u > PV_PERIOD - 1.0f) { u -= PV_PERIOD; }
    if (u < -1.0f || u > 23.0f) { return vec2f(0.0f); }
    let k = select(select(1.0f - smoothstep(17.0f, 22.0f, u), 1.0f, u < 17.0f), smoothstep(0.0f, 14.0f, u), u < 14.0f);
    return vec2f(PV_DAYS * k, smoothstep(-0.6f, 0.0f, u) * (1.0f - smoothstep(22.0f, 22.6f, u)));
}
fn now_tt(fr: ArgusFrame) -> Tm { return Tm(fr.days_j2000, fr.day_frac + TT_UTC_D + preview(fr.time).x); }

// ============================================================================ state kernels
// one thread per hourly sample of one body: rows ROW_SAMP + b, x = k, time now + (k - SAMP0) h
fn write_sample(gid: vec2u) {
    let b = i32(gid.y) - ROW_SAMP;
    let t0 = now_tt(f);
    let p = body_pos(b, Tm(t0.n, t0.fr + f32(i32(gid.x) - SAMP0) * (1.0f / 24.0f)));
    textureStore(argus_state_out, gid, vec4f(p, 0.0f));
}

@compute @workgroup_size(8, 8)
fn argus_init(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    if (gid.y < 832u) { textureStore(argus_state_out, gid, textureLoad(argus_data, gid, 0)); return; }
    if (i32(gid.y) >= ROW_SAMP && i32(gid.y) < ROW_SAMP + 10 && i32(gid.x) < NSAMP) { write_sample(gid); return; }
    textureStore(argus_state_out, gid, vec4f(0.0f));
}

fn samp(s: texture_2d<f32>, b: i32, k: i32) -> f32 { return textureLoad(s, vec2u(u32(k), u32(ROW_SAMP + b)), 0).x; }

@compute @workgroup_size(8, 8)
fn argus_step(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    let x = i32(gid.x); let y = i32(gid.y);
    if (y < 832) { if (f.frame < 3u) { textureStore(argus_state_out, gid, textureLoad(argus_state, gid, 0)); } return; }
    if (y >= ROW_SAMP) { if (y < ROW_SAMP + 10 && x < NSAMP) { write_sample(gid); } return; }
    if (y == ROW_BODY && x < 10) {
        // longitude now, its rate over the surrounding day, and the display angle on the chart
        let l0 = samp(argus_state, x, SAMP0);
        let rate = wrap180(samp(argus_state, x, SAMP0 + 12) - samp(argus_state, x, SAMP0 - 12));
        // display angles: the true longitudes pushed apart to >= 14 deg, eased over ~1.5 s
        var d: array<f32, 10>;
        for (var j = 0; j < 10; j++) { d[j] = samp(argus_state, j, SAMP0); }
        for (var it = 0; it < 12; it++) {
            for (var i = 0; i < 10; i++) { for (var j = i + 1; j < 10; j++) {
                let s = wrap180(d[j] - d[i]);
                if (abs(s) < 14.0f) { let pu = (14.0f - abs(s)) * 0.5f * select(-1.0f, 1.0f, s >= 0.0f); d[i] -= pu; d[j] += pu; }
            } }
        }
        // during the look-ahead the easing is fast, so the gems keep up (and slide past one another)
        let old = textureLoad(argus_state, vec2u(u32(x), u32(ROW_BODY)), 0);
        let pw = preview(f.time).y;
        let tgt = wrap360(d[x]);                                    // Metal: target (reserved in WGSL)
        let disp = select(wrap360(old.w + wrap180(tgt - old.w) * (1.0f - exp(-f.dt / select(0.5f, 0.05f, pw > 0.0f)))), tgt, f.frame < 3u);
        textureStore(argus_state_out, gid, vec4f(l0, textureLoad(argus_state, vec2u(u32(SAMP0), u32(ROW_SAMP + x)), 0).y, rate, disp));
        return;
    }
    if (y == ROW_EVENT && x < 10) {
        // the next sign ingress or station within the horizon, latched as an absolute time (row
        // ROW_LATCH) so float noise in a slow planet's samples can't make the countdown wander
        let b = x;
        if (preview(f.time).x > 0.0f && f.frame >= 3u) {
            // look-ahead: no events; Rx from the motion alone; the latch waits for the return to now
            let rate = wrap180(samp(argus_state, b, SAMP0 + 12) - samp(argus_state, b, SAMP0 - 12));
            let rx0 = textureLoad(argus_state, vec2u(u32(x), u32(ROW_EVENT)), 0).w;
            textureStore(argus_state_out, gid, vec4f(0.0f, 0.0f, 0.0f, select(select(select(rx0, 0.0f, rate > 6e-5f), 1.0f, rate < -6e-5f), 0.0f, b < 2)));
            textureStore(argus_state_out, vec2u(u32(x), u32(ROW_LATCH)), textureLoad(argus_state, vec2u(u32(x), u32(ROW_LATCH)), 0));
            return;
        }
        var l_prev = samp(argus_state, b, SAMP0);
        var s_prev = i32(l_prev / 30.0f) % 12;
        var t_ing = 1e9f; var sign_to = 0;
        for (var k = SAMP0 + 1; k <= SAMP0 + 168; k++) {
            let l = samp(argus_state, b, k);
            let s = i32(l / 30.0f) % 12;
            if (s != s_prev) {
                let dl = wrap180(l - l_prev);
                let edge = select(f32(s_prev) * 30.0f, f32(s) * 30.0f, dl > 0.0f);
                t_ing = f32(k - 1 - SAMP0) + clamp(wrap180(edge - l_prev) / dl, 0.0f, 1.0f);
                sign_to = s; break;
            }
            l_prev = l; s_prev = s;
        }
        var t_st = 1e9f; var st_kind = 0.0f;
        if (b >= 2) {
            var r_prev = wrap180(samp(argus_state, b, SAMP0 + 12) - samp(argus_state, b, SAMP0 - 12));
            for (var k = SAMP0 + 1; k + 12 < NSAMP; k++) {
                let r = wrap180(samp(argus_state, b, k + 12) - samp(argus_state, b, k - 12));
                if ((r > 0.0f) != (r_prev > 0.0f)) {
                    // the zero of a least-squares line through the daily rate around the crossing
                    let j0 = max(12, k - 8); let j1 = min(NSAMP - 13, k + 8);
                    var sx = 0.0f; var sy = 0.0f; var sxx = 0.0f; var sxy = 0.0f; var nn = 0.0f;
                    for (var j = j0; j <= j1; j++) {
                        let xx = f32(j - k); let yy = wrap180(samp(argus_state, b, j + 12) - samp(argus_state, b, j - 12));
                        sx += xx; sy += yy; sxx += xx * xx; sxy += xx * yy; nn += 1.0f;
                    }
                    let slope = (nn * sxy - sx * sy) / max(nn * sxx - sx * sx, 1e-6f);
                    let icpt = (sy - slope * sx) / nn;
                    let z = select(-0.5f, clamp(-icpt / slope, -2.0f, 1.0f), abs(slope) > 1e-12f);   // near the crossing
                    t_st = f32(k - SAMP0) + z;
                    st_kind = select(3.0f, 2.0f, r_prev > 0.0f); break;
                }
                r_prev = r;
            }
        }
        // retrograde now: the daily motion past +-6e-5 deg/day (float noise stays below), or the latched
        // station passing; a coming station's kind follows from it (direct now -> SR next), never from
        // the sign of a noisy crossing
        let t0 = now_tt(f);
        let L = textureLoad(argus_state, vec2u(u32(x), u32(ROW_LATCH)), 0);
        // whole days in integers first: under fast math (L.x + L.y) would be rounded near day 9800 (~84 s)
        let dn = i32(L.x) - t0.n;
        let hL = (f32(dn) + (L.y - t0.fr)) * 24.0f;
        let fresh = f.frame < 3u || L.z == 0.0f;
        let rate = wrap180(samp(argus_state, b, SAMP0 + 12) - samp(argus_state, b, SAMP0 - 12));
        var rx = select(textureLoad(argus_state, vec2u(u32(x), u32(ROW_EVENT)), 0).w, select(0.0f, 1.0f, rate < 0.0f), f.frame < 3u);
        let passed = !fresh && L.z >= 2.0f && hL <= 0.0f;
        if (passed) { rx = select(0.0f, 1.0f, L.z == 2.0f); }
        else { rx = select(select(rx, 0.0f, rate > 6e-5f), 1.0f, rate < -6e-5f); }
        if (b < 2) { rx = 0.0f; }
        st_kind = select(2.0f, 3.0f, rx > 0.5f);
        var ev = vec4f(0.0f);                                       // kind, hours, target sign, Rx flag
        if (t_ing < 168.0f && t_ing <= t_st) { ev = vec4f(1.0f, t_ing, f32(sign_to), 0.0f); }
        else if (t_st < 168.0f) { ev = vec4f(st_kind, t_st, 0.0f, 0.0f); }
        // the latched event: keep it while the fresh estimate agrees within 3 h
        var keep = false;
        if (!fresh && !passed) {
            if (L.z == ev.x && L.w == ev.z && abs(hL - ev.y) < 3.0f) { ev.y = hL; keep = true; }
            else if (ev.x == 0.0f && L.z >= 2.0f && hL > 0.0f && hL < 168.0f) { ev = vec4f(L.z, hL, L.w, 0.0f); }
        }
        ev.w = rx;
        textureStore(argus_state_out, gid, ev);
        let tot = t0.fr + ev.y / 24.0f; let ip = floor(tot);           // a kept latch is copied as is
        textureStore(argus_state_out, vec2u(u32(x), u32(ROW_LATCH)), select(select(vec4f(0.0f), vec4f(f32(t0.n) + ip, tot - ip, ev.x, ev.z), ev.x > 0.0f), L, keep));
        return;
    }
    if (y == ROW_LATCH) { return; }                                 // written by the ROW_EVENT threads
    if (y == ROW_ASP && x < 45) {
        // aspect pair x: the major aspects within orb (6 deg with the Sun or Moon, else 4); no conjunctions
        var i = 0; var j = 1; var p = 0;
        for (var a = 0; a < 10; a++) { for (var c = a + 1; c < 10; c++) { if (p == x) { i = a; j = c; } p++; } }
        let li = samp(argus_state, i, SAMP0); let lj = samp(argus_state, j, SAMP0);
        let sep = abs(wrap180(li - lj));
        let orb = select(4.0f, 6.0f, i < 2);
        var kind = -1.0f; var tight = 0.0f;
        let A = array<f32, 4>(60.0f, 90.0f, 120.0f, 180.0f);
        for (var k = 0; k < 4; k++) { if (abs(sep - A[k]) < orb) { kind = f32(k); tight = 1.0f - abs(sep - A[k]) / orb; } }
        textureStore(argus_state_out, gid, vec4f(li, lj, kind, tight));
        return;
    }
    if (y == ROW_MOON && x == 0) {
        // the Moon's phase: elongation from the Sun and the illuminated fraction (Meeus ch. 48)
        let s = textureLoad(argus_state, vec2u(u32(SAMP0), u32(ROW_SAMP + 0)), 0); let m = textureLoad(argus_state, vec2u(u32(SAMP0), u32(ROW_SAMP + 1)), 0);
        let cpsi = cos(m.y * D2R) * cos((m.x - s.x) * D2R);
        let psi = acos(clamp(cpsi, -1.0f, 1.0f));
        let i = atan2(s.z * sin(psi), m.z - s.z * cos(psi));            // phase angle
        textureStore(argus_state_out, gid, vec4f(wrap360(m.x - s.x), 0.5f * (1.0f + cos(i)), s.x, m.x));
        return;
    }
    textureStore(argus_state_out, gid, vec4f(0.0f));
}

// ============================================================================ the dial
// Dial units: radius 1 = the bezel's outer edge. Chart convention: 0 Aries at 9 o'clock, longitude
// counter-clockwise. The camera looks straight down from CAM_D dial radii; z points at it.
const PI_F: f32 = 3.14159265f;
const DIAL_R: f32 = 0.805f; const DIAL_Y: f32 = 0.025f;     // of the screen's half-height; centre raised a little
const CAM_D: f32 = 4.0f;
const R_OUT: f32 = 1.075f; const R_Z1: f32 = 0.898f; const R_Z0: f32 = 0.776f; const R_D0: f32 = 0.726f;
const R_GEM: f32 = 0.672f; const R_LG: f32 = 0.582f; const R_ASP: f32 = 0.325f;
const R_MED: f32 = 0.150f; const R_MEDB: f32 = 0.172f;
const G_RX: i32 = 22; const G_DIG: i32 = 23; const G_DEG: i32 = 33; const G_d: i32 = 34; const G_h: i32 = 35; const G_D: i32 = 36; const G_ARROW: i32 = 37; const G_S: i32 = 38; const G_R: i32 = 39;
// advance widths in cells (text glyphs; symbols 0.78), from the atlas build
const ADV = array<f32, 72>(0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.780f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.438f, 0.312f, 0.492f, 0.508f, 0.582f, 0.780f, 0.438f, 0.533f, 0.453f, 0.492f, 0.396f, 0.432f, 0.428f, 0.262f, 0.512f, 0.463f, 0.387f, 0.363f, 0.295f, 0.508f, 0.670f, 0.477f, 0.258f, 0.498f, 0.471f, 0.578f, 0.498f, 0.736f, 0.604f, 0.596f, 0.824f, 0.490f, 0.445f, 0.461f, 0.293f, 0.566f, 0.596f, 0.484f, 0.438f, 0.780f);
// the eight phase names, as atlas indices (-1 a space, -2 the end; Metal's unset tail is 0)
const PHASE = array<array<i32, 16>, 8>(
    array<i32, 16>(60, 43, 52, -1, 59, 47, 47, 46, -2, 0, 0, 0, 0, 0, 0, 0),                // New Moon
    array<i32, 16>(62, 40, 53, 45, 46, 44, -1, 55, 48, 43, 49, 42, 43, 46, 50, -2),         // Waxing Crescent
    array<i32, 16>(56, 45, 48, 49, 50, -1, 61, 51, 40, 48, 50, 43, 48, -2, 0, 0),           // First Quarter
    array<i32, 16>(62, 40, 53, 45, 46, 44, -1, 57, 45, 41, 41, 47, 51, 49, -2, 0),          // Waxing Gibbous
    array<i32, 16>(56, 51, 54, 54, -1, 59, 47, 47, 46, -2, 0, 0, 0, 0, 0, 0),               // Full Moon
    array<i32, 16>(62, 40, 46, 45, 46, 44, -1, 57, 45, 41, 41, 47, 51, 49, -2, 0),          // Waning Gibbous
    array<i32, 16>(58, 40, 49, 50, -1, 61, 51, 40, 48, 50, 43, 48, -2, 0, 0, 0),            // Last Quarter
    array<i32, 16>(62, 40, 46, 45, 46, 44, -1, 55, 48, 43, 49, 42, 43, 46, 50, -2));        // Waning Crescent
const PREVIEW_W = array<i32, 7>(69, 48, 43, 65, 45, 43, 52);                // Preview
const MONTH = array<array<i32, 3>, 12>(array<i32, 3>(66, 40, 46), array<i32, 3>(56, 43, 41), array<i32, 3>(59, 40, 48), array<i32, 3>(67, 63, 48), array<i32, 3>(59, 40, 64), array<i32, 3>(66, 51, 46),
                                       array<i32, 3>(66, 51, 54), array<i32, 3>(67, 51, 44), array<i32, 3>(38, 43, 63), array<i32, 3>(68, 42, 50), array<i32, 3>(60, 47, 65), array<i32, 3>(36, 43, 42));
// the local calendar date (proleptic Gregorian) of a day count from 1970-01-01 (H. Hinnant's algorithm)
fn month_day(z_in: i32) -> vec2i {
    var z = z_in;
    z += 719468;
    let era = select(z - 146096, z, z >= 0) / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    return vec2i(select(mp - 9, mp + 3, mp < 10), doy - (153 * mp + 2) / 5 + 1);
}

fn CP(lam: f32, r: f32) -> vec2f { let a = (180.0f + lam) * D2R; return r * vec2f(cos(a), sin(a)); }
fn hash2(c: vec2f, s: f32) -> f32 { return argus_rand(vec2u(vec2i(c) + 50000), u32(s)); }
fn sat(x: f32) -> f32 { return clamp(x, 0.0f, 1.0f); }

// --- glyph atlas (state rows 0-575, 8 x 9 cells of 64 px): signed distance in screen px, + outside
fn glyph_px(st: texture_2d<f32>, id: i32, q: vec2f, cell_px: f32) -> f32 {
    // q: glyph-local position in cells, (0,0) the cell's centre, y up
    if (abs(q.x) > 0.49f || abs(q.y) > 0.49f) { return 99.0f; }
    // Metal: constexpr sampler s(filter::linear, address::clamp_to_edge, coord::pixel)
    let tc = vec2f(f32(id % 8) * 64.0f + (q.x + 0.5f) * 64.0f, f32(id / 8) * 64.0f + (0.5f - q.y) * 64.0f);
    return (0.5f - argus_sample(st, argus_linear_clamp, tc / vec2f(textureDimensions(st))).r) * 12.0f * cell_px / 64.0f;
}
fn adv(id: i32) -> f32 { if (id < 0) { return 0.28f; } return ADV[id]; }
// a run of glyphs centred at c (dial units), cell size s, upright: the signed distance in px
fn text_px(st: texture_2d<f32>, ids: ptr<function, array<i32, 16>>, n: i32, p: vec2f, c: vec2f, s: f32, ppu: f32) -> f32 {
    var w = 0.0f;
    for (var i = 0; i < n; i++) { w += adv((*ids)[i]); }
    let q0 = (p - c) / s;
    if (abs(q0.y) > 0.5f || abs(q0.x) > 0.5f * w + 0.5f) { return 99.0f; }
    var x = -0.5f * w; var d = 99.0f;
    for (var i = 0; i < n; i++) {
        let a = adv((*ids)[i]);
        if ((*ids)[i] >= 0) { d = min(d, glyph_px(st, (*ids)[i], q0 - vec2f(x + 0.5f * a, 0.0f), s * ppu)); }
        x += a;
    }
    return d;
}

// --- the studio: a light tent with a dark lens port overhead, a key softbox upper left (drifting), a
// wide fill softbox right, the tent's seams and a few lamps of the room low on the horizon (irregular,
// so reflections never repeat). Lights are areas, widened by the lobe (rough) and never point-sampled.
// V is this pixel's direction to the camera.
struct Studio { sb: vec3f, sbx: vec3f, sby: vec3f, st: vec3f, stx: vec3f, sty: vec3f, V: vec3f }
fn studio(t: f32) -> Studio {
    var S: Studio;
    let az = (135.0f + 6.0f * sin(TAU * t / 96.0f) + 3.0f * sin(TAU * t / 240.0f + 1.0f)) * D2R;
    let el = (52.0f + 3.0f * sin(TAU * t / 150.0f)) * D2R;
    S.sb = vec3f(cos(el) * cos(az), cos(el) * sin(az), sin(el));
    S.sbx = normalize(cross(vec3f(0, 0, 1), S.sb)); S.sby = cross(S.sb, S.sbx);
    S.st = normalize(vec3f(0.80f, -0.30f, 0.52f));
    S.stx = normalize(cross(vec3f(0, 0, 1), S.st)); S.sty = cross(S.st, S.stx);
    S.V = vec3f(0, 0, 1);
    return S;
}
fn rect_light(d: vec3f, c: vec3f, ax: vec3f, ay: vec3f, hx: f32, hy: f32, soft: f32) -> f32 {
    let k = dot(d, c);
    if (k <= 0.05f) { return 0.0f; }
    let u = dot(d, ax) / k; let v = dot(d, ay) / k;
    return (1.0f - smoothstep(hx - soft, hx + soft, abs(u))) * (1.0f - smoothstep(hy - soft, hy + soft, abs(v)));
}
const LAMP_AZ = array<f32, 4>(0.40f, 1.25f, 2.90f, 5.00f); const LAMP_W = array<f32, 4>(0.45f, 0.25f, 0.60f, 0.40f); const LAMP_S = array<f32, 4>(1.0f, 0.55f, 0.8f, 0.7f);
fn env(d: vec3f, rough: f32, S: Studio) -> vec3f {
    let soft = 0.04f + rough * 0.9f;
    var c = vec3f(0.004f, 0.0035f, 0.005f) * (1.0f + 2.0f * sat(d.z + 0.3f));   // the dark velvet below
    if (d.z > -0.05f) {
        let az = atan2(d.y, d.x); let elv = asin(clamp(d.z, -1.0f, 1.0f));
        // the tent: brighter toward the key, its seams and folds a low-frequency unevenness
        let port = smoothstep(0.90f - rough * 0.3f, 0.975f, d.z);
        let fold = 0.78f + 0.22f * argus_noise(vec2f(az * 1.6f, elv * 2.2f));
        c = mix(vec3f(0.16f, 0.155f, 0.15f) * (0.45f + 0.75f * sat(dot(d, S.sb))) * fold, vec3f(0.010f), port) * (0.15f + 0.85f * smoothstep(0.15f, 0.75f, d.z));
        // key softbox (a bright core inside a softer diffuser) and a wide cool fill
        c += vec3f(1.0f, 0.95f, 0.88f) * (3.6f * rect_light(d, S.sb, S.sbx, S.sby, 0.22f, 0.15f, soft)
                                        + 1.6f * rect_light(d, S.sb, S.sbx, S.sby, 0.32f, 0.24f, soft + 0.06f)) * (1.0f - rough * 0.6f);
        c += vec3f(0.92f, 0.96f, 1.0f) * 0.75f * rect_light(d, S.st, S.stx, S.sty, 0.26f, 0.34f, soft + 0.05f) * (1.0f - rough * 0.5f);
        // lamps of the room, low on the horizon at irregular azimuths, widths and strengths
        for (var i = 0; i < 4; i++) {
            let da = abs(fract((az - LAMP_AZ[i]) / TAU + 0.5f) - 0.5f) * TAU;
            let w = LAMP_W[i] * 0.35f + rough * 0.8f;
            // Metal: pow((elv - 0.16f) / (0.06f + rough * 0.6f), 2.0f), which its compiler makes x * x; WGSL's pow
            // is undefined for a negative base (NaN on some backends), so the square is written out
            let ze = (elv - 0.16f) / (0.06f + rough * 0.6f);
            c += vec3f(1.0f, 0.78f, 0.52f) * LAMP_S[i] * 0.35f * exp(-(da * da) / (w * w)) * exp(-(ze * ze));
        }
        c += vec3f(1.0f, 0.95f, 0.88f) * rough * 0.8f * pow(sat(dot(d, S.sb)), 4.0f);   // a satin lobe sees the box's glow
    }
    return c;
}
fn irr(n: vec3f, S: Studio) -> vec3f {      // diffuse light on a matte surface
    return vec3f(0.16f) * (0.55f + 0.45f * n.z) + vec3f(1.0f, 0.95f, 0.88f) * 0.42f * sat(dot(n, S.sb)) + 0.06f * sat(dot(n, S.st));
}
fn schlick(F0: vec3f, c: f32) -> vec3f { return F0 + (1.0f - F0) * pow(1.0f - sat(c), 5.0f); }
// Fresnel integrated over a GGX lobe (Karis 2014's analytic environment BRDF): an edge seen edge-on
// reaches ~0.4 for a satin surface, not Schlick's 1, so nothing goes "wet"
fn env_brdf(F0: vec3f, rough: f32, ndv: f32) -> vec3f {
    let rr = rough * vec4f(-1.0f, -0.0275f, -0.572f, 0.022f) + vec4f(1.0f, 0.0425f, 1.04f, -0.04f);
    let a = min(rr.x * rr.x, exp2(-9.28f * sat(ndv))) * rr.x + rr.y;
    let AB = vec2f(-1.04f, 1.04f) * a + rr.zw;
    return F0 * AB.x + AB.y;
}
fn refl(n: vec3f, S: Studio) -> vec3f { return reflect(-S.V, n); }

const ROSE = vec3f(0.92f, 0.58f, 0.45f);
fn gold(n: vec3f, rough: f32, S: Studio) -> vec3f {
    return env_brdf(ROSE, max(rough, 0.04f), dot(n, S.V)) * env(refl(n, S), rough, S);
}

// --- the Moon medallion: NASA's LROC colour map on a sphere lit at the real phase angle
fn moon_face(st: texture_2d<f32>, q: vec2f, elong: f32, illum: f32, sun_dir: vec2f) -> vec3f {
    // lighting in the Sun's frame (+x toward the Sun gem); the map turns half a revolution, slowly,
    // around full and new Moon (elongation 170-190 and 350-10 deg), so the lit limb is the east limb
    // while waxing and the west while waning without a jump
    let i = acos(clamp(2.0f * illum - 1.0f, -1.0f, 1.0f));         // phase angle
    let ths = atan2(sun_dir.y, sun_dir.x);
    let e2 = select(elong, elong + 360.0f, elong < 90.0f);
    let tht = ths + PI_F * (smoothstep(170.0f, 190.0f, e2) - smoothstep(350.0f, 370.0f, e2));
    let qb = vec2f(cos(tht) * q.x + sin(tht) * q.y, -sin(tht) * q.x + cos(tht) * q.y);
    let n = vec3f(qb, sqrt(max(1.0f - dot(qb, qb), 0.0f)));
    let dt = ths - tht;
    let s = vec3f(cos(dt) * sin(i), sin(dt) * sin(i), cos(i));     // the Sun, in the map's frame
    let lon = atan2(n.x, n.z); let lat = asin(clamp(n.y, -1.0f, 1.0f));
    // Metal: constexpr sampler sm(filter::linear, address::clamp_to_edge, coord::pixel)
    let tc = vec2f(256.0f + lon * (256.0f / PI_F), 576.0f + clamp((0.5f - lat / PI_F) * 256.0f, 0.5f, 255.5f));
    let al = pow(argus_sample(st, argus_linear_clamp, tc / vec2f(textureDimensions(st))).rgb, vec3f(2.2f));
    let mu0 = dot(n, s); let mu = n.z;
    let ls = select(0.0f, mu0 / (mu0 + mu + 1e-3f) * 2.0f, mu0 > 0.0f);    // Lommel-Seeliger
    return al * (ls * 1.25f + vec3f(0.030f, 0.034f, 0.042f) * (1.0f - illum)); // + earthshine (exaggerated)
}

fn gem_albedo(b: i32, q: vec2f) -> vec3f {
    if (b == 2) { return mix(vec3f(0.10f, 0.16f, 0.10f), vec3f(0.28f, 0.34f, 0.22f), smoothstep(-0.2f, 0.5f, argus_fbm(q * 3.0f + 3.0f, 4))); }   // serpentine
    if (b == 3) { return mix(vec3f(0.02f, 0.07f, 0.04f), vec3f(0.06f, 0.16f, 0.09f), smoothstep(-0.3f, 0.6f, argus_fbm(q * 2.0f + 9.0f, 3))); } // chloromelanite
    if (b == 4) { return mix(vec3f(0.30f, 0.025f, 0.012f), vec3f(0.45f, 0.08f, 0.03f), smoothstep(-0.4f, 0.6f, argus_fbm(q * 4.0f + 1.0f, 4))); } // red jasper
    if (b == 5) { return mix(vec3f(0.25f, 0.38f, 0.60f), vec3f(0.62f, 0.72f, 0.85f), 0.5f + 0.5f * sin(q.y * 11.0f + 2.0f * argus_noise(q * 2.0f))); } // blue agate
    if (b == 6) { return vec3f(0.20f, 0.06f, 0.30f) * (0.8f + 0.3f * argus_noise(q * 3.0f)); }                                        // sugilite
    if (b == 7) { return vec3f(0.18f, 0.48f, 0.52f); }                                                                                // aquamarine
    if (b == 8) { let py = step(0.985f, hash2(floor((q + 2.0f) * 14.0f), 3.0f));                                                     // lapis, pyrite flecks
                  return mix(vec3f(0.02f, 0.05f, 0.30f), vec3f(0.9f, 0.7f, 0.3f), py); }
    if (b == 9) { return vec3f(0.10f, 0.09f, 0.09f) * (0.85f + 0.3f * argus_noise(q * 4.0f)); }                                       // smoky quartz
    return vec3f(0.85f, 0.83f, 0.80f);                                                                                                // Moon: mother-of-pearl
}
fn gem_r(b: i32) -> f32 { return select(select(select(0.025f, 0.030f, b == 5 || b == 6), 0.034f, b == 1), 0.040f, b == 0); }

// a cabochon: a low dome (flatter than a sphere, so the softbox shows as a broad window), lit from
// the box, with light carried through the stone to the side away from it
fn shade_gem(b: i32, q: vec2f, S: Studio) -> vec3f {
    let rr = dot(q, q);
    let n = normalize(vec3f(q * 0.85f, sqrt(max(1.0f - rr, 0.0f)) + 0.15f));
    if (b == 0) {   // the Sun: a polished gold dome engraved with a sunburst
        let a = atan2(q.y, q.x);
        let nn = normalize(n + vec3f(-q.y, q.x, 0.0f) * 0.18f * cos(a * 24.0f) * sqrt(rr));
        return gold(nn, 0.22f, S) * vec3f(1.08f, 1.04f, 0.86f);
    }
    let al = gem_albedo(b, q);
    let F = schlick(vec3f(0.05f), dot(n, S.V)).x;
    var c = al * irr(n, S) * (1.0f - F) + F * env(refl(n, S), 0.06f, S);
    let glow = sat(dot(-q, normalize(S.sb.xy))) * (1.0f - rr);      // transmitted light, opposite the box
    c += al * 0.55f * glow;
    if (b == 1) {   // nacre: a soft interference tint that follows the surface
        let ph = n.z * 9.0f + argus_noise(q * 5.0f) * 2.0f;
        c *= 1.0f + 0.10f * vec3f(sin(ph), sin(ph + 2.1f), sin(ph + 4.2f));
    }
    return c;
}

fn digits(ids: ptr<function, array<i32, 16>>, n_in: i32, v: i32) -> i32 {
    var n = n_in;
    if (v >= 10) { (*ids)[n] = G_DIG + (v / 10) % 10; n++; }
    (*ids)[n] = G_DIG + v % 10; n++;
    return n;
}

// the label block of body b (glyph; degree, sign and Rx; the coming event): signed distances in px of
// (gold text, the Rx, the event line), so it can be drawn and also cast its shadow
fn label_d(st: texture_2d<f32>, p: vec2f, b: i32, lam_b: f32, disp: f32, ev: vec4f, pvw: f32, ppu: f32) -> vec3f {
    let lg = CP(disp, R_LG);
    let cx = abs(cos((180.0f + disp) * D2R));            // 1 where the stack runs sideways
    let sp = 0.056f + 0.058f * cx;
    var d = glyph_px(st, 12 + b, (p - lg) / 0.074f, 0.074f * ppu);
    var ids: array<i32, 16>;                                    // Metal: int ids[8] (one array type for text_px)
    var n = digits(&ids, 0, i32(lam_b % 30.0f));
    ids[n] = G_DEG; n++; ids[n] = i32(lam_b / 30.0f) % 12; n++;
    let rx = ev.w > 0.5f;
    let s2 = 0.046f;
    var w = 0.0f;
    for (var i = 0; i < n; i++) { w += adv(ids[i]); }
    let rxs = select(1.0f, 1.25f, b == 2);                                  // Mercury's Rx a little larger
    let wt = w + select(0.0f, 0.15f + 0.78f * rxs, rx);
    let lc = CP(disp, R_LG - sp);
    d = min(d, text_px(st, &ids, n, p, lc + vec2f((w - wt) * 0.5f * s2, 0.0f), s2, ppu));
    var dr = 99.0f;
    if (rx) { dr = glyph_px(st, G_RX, (p - lc - vec2f((0.5f * wt - 0.39f * rxs) * s2, 0.0f)) / (s2 * rxs), s2 * rxs * ppu); }
    var de = 99.0f;
    if (ev.x > 0.5f && pvw < 0.5f) {
        let hrs = ev.y;
        var m = 0;
        if (ev.x == 1.0f) { ids[m] = G_ARROW; m++; ids[m] = i32(ev.z); m++; }
        else { ids[m] = G_S; m++; ids[m] = select(G_D, G_R, ev.x == 2.0f); m++; }
        ids[m] = -1; m++;
        let days = hrs >= 23.0f;
        m = digits(&ids, m, select(max(1, i32(ceil(hrs))), i32(hrs / 24.0f + 0.5f), days));
        ids[m] = select(G_h, G_d, days); m++;
        // toward the centre at the top and bottom, straight below the degree line at the sides
        let ep = lc + mix(-CP(disp, 1.0f) * 0.052f, vec2f(0.0f, -0.046f), cx * cx);
        de = text_px(st, &ids, m, p, ep, 0.036f, ppu);
    }
    return vec3f(d, dr, de);
}

// coverage of a line of half-width hw at distance d, box-filtered over the pixel (aa = one pixel in
// dial units); a line thinner than a pixel keeps its energy, spread over a pixel, instead of breaking
// into dots
fn line_cov(d: f32, hw: f32, aa: f32) -> f32 {
    let h = max(hw, 0.5f * aa);
    return sat((h - d) / aa + 0.5f) * (hw / h);
}
// a V-groove etched into the dial glass: ds the signed distance across it, hw its half-width, perp
// the direction across. The walls lean in (each catches the lights from its own side, frosted by the
// etching); the floor holds a little coloured enamel. Box-filtered at the rims; walls meet at the floor.
fn groove(base: vec3f, ds: f32, hw: f32, perp: vec2f, floor_col: vec3f, aa: f32, S: Studio) -> vec3f {
    let cov = sat((hw - abs(ds)) / aa + 0.5f);
    if (cov <= 0.0f) { return base; }
    let x = clamp(ds / hw, -1.0f, 1.0f);
    let nw = normalize(vec3f(-perp * select(1.0f, -1.0f, x < 0.0f) * 0.75f, 1.0f));
    let wall = vec3f(0.050f, 0.054f, 0.070f) * irr(nw, S) * 1.6f
             + env_brdf(vec3f(0.04f), 0.35f, dot(nw, S.V)) * env(refl(nw, S), 0.35f, S);
    let flo = floor_col * (irr(vec3f(0, 0, 1), S) * 0.7f + 0.10f);
    let f = smoothstep(0.55f, 0.20f, abs(x));                    // the floor's share
    return mix(base, mix(wall, flo, f) * (0.80f + 0.20f * (1.0f - abs(x))), cov);
}

// the degree ring: rose gold, circular-brushed (the lobe stretched across the grooves, radially, so the
// lights show as a soft radial "bow tie"), degrees engraved and filled black
fn chapter_ring(r: f32, lam: f32, rad: vec2f, aa: f32, S: Studio) -> vec3f {
    var c = vec3f(0.0f);
    for (var k = -2; k <= 2; k++) { c += gold(normalize(vec3f(rad * 0.16f * f32(k), 1.0f)), 0.14f, S); }
    c *= 0.2f;
    let dd = abs(fract(lam + 0.5f) - 0.5f) * D2R * r;
    let di = floor(lam + 0.5f);
    let len = select(select(select(0.24f, 0.44f, di % 5.0f == 0.0f), 0.62f, di % 10.0f == 0.0f), 1.0f, di % 30.0f == 0.0f);
    let w = select(select(0.0011f, 0.0013f, di % 5.0f == 0.0f), 0.0026f, di % 30.0f == 0.0f);
    let tick = line_cov(dd, w, aa) * sat((r - (R_Z0 - len * (R_Z0 - R_D0))) / aa + 0.5f);
    c = mix(c, vec3f(0.006f, 0.005f, 0.005f), tick * 0.95f);
    return c * (0.75f + 0.25f * smoothstep(R_D0, R_D0 + 0.006f, r));          // the step down to the glass
}
// the aventurine glass without its crystals (what meets the degree ring's inner edge)
fn glass_base(p: vec2f, S: Studio) -> vec3f {
    let m = argus_fbm(p * 2.5f + 4.0f, 4);
    let base = mix(vec3f(0.0013f, 0.0022f, 0.0105f), vec3f(0.0030f, 0.0050f, 0.020f), 0.5f + 0.5f * m);
    return base * irr(vec3f(0, 0, 1), S) * 2.2f + schlick(vec3f(0.04f), S.V.z) * env(refl(vec3f(0, 0, 1), S), 0.02f, S);
}

fn dial(st: texture_2d<f32>, p: vec2f, ppu: f32, S: Studio) -> vec3f {
    let r = length(p);
    let aa = 1.0f / ppu;
    let rad = select(vec2f(1, 0), p / r, r > 1e-5f);
    let lam = wrap360(atan2(p.y, p.x) * R2D - 180.0f);
    let kd = normalize(S.sb.xy);                                         // toward the key light
    // ---- outside the dial: dark velvet in the key's pool of light, its pile and nap (faded to the mean
    // below ~3 px), the dial's soft cast shadow and contact darkening
    if (r > R_OUT + aa) {
        let pool = 0.35f + 0.85f * exp(-dot(p - kd * 0.75f, p - kd * 0.75f) / 1.6f);
        let pile = 0.82f + 0.18f * argus_noise(p * vec2f(2.6f, 3.4f) + 7.0f);   // brushed patches
        let nap_fade = sat((ppu / 170.0f - 1.5f) / 2.0f);
        let nap = (argus_noise(p * vec2f(170.0f, 120.0f)) * 0.6f + argus_noise(p * 60.0f + 3.0f) * 0.4f) * nap_fade;
        let off = -kd * (0.075f / max(tan(asin(S.sb.z)), 0.3f));
        let shd = smoothstep(R_OUT - 0.04f, R_OUT + 0.13f, length(p - off));
        let ao = 0.50f + 0.50f * smoothstep(R_OUT, R_OUT + 0.06f, r);
        return vec3f(0.0085f, 0.0078f, 0.0140f) * irr(vec3f(0, 0, 1), S) * 2.0f * pool * pile * (1.0f + 0.10f * nap) * (0.40f + 0.60f * shd) * ao;
    }
    // ---- bezel: one continuous bead of polished rose gold, from the enamel up to its crest and down to
    // the cloth; its curvature widens the reflected lobe, and the inner flank reflects the dial itself
    if (r > R_Z1) {
        let RBC = 0.975f;
        let half_w = select(R_OUT - RBC, RBC - R_Z1, r < RBC);
        let t = clamp((r - RBC) / half_w, -1.0f, 1.0f);
        let ang = t * 1.25f;
        let n = normalize(vec3f(rad * sin(ang), cos(ang)));
        let rough = 0.035f + 1.0f * 1.25f / (half_w * ppu);
        let R = refl(n, S);
        var e = env(R, rough, S);
        let toward = sat(-dot(R.xy, rad) * 2.0f) * sat(1.0f - R.z * 1.4f);
        e = mix(e, vec3f(0.010f, 0.022f, 0.12f), toward);
        var c = env_brdf(ROSE, rough, dot(n, S.V)) * e;
        c *= 0.55f + 0.45f * smoothstep(0.0f, 0.010f, r - R_Z1);                // where it meets the enamel
        return mix(c, vec3f(0.003f), smoothstep(R_OUT - aa, R_OUT + aa, r));
    }
    // ---- zodiac ring: translucent cobalt enamel over a flinqué sunburst, gold signs
    if (r > R_Z0 - aa) {
        let sg = i32(lam / 30.0f) % 12;
        let a = atan2(p.y, p.x);
        let tang = vec2f(-rad.y, rad.x);
        // a flinqué sunburst, one ray per degree (~7 px apart at 1200 px), faded toward its mean as the
        // pixel grows against it, so it never beats against an edge or the pixel grid
        let ph = a * 360.0f;
        let gw = sat((r * D2R * ppu - 3.0f) / 4.0f);
        let groove = 0.5f + 0.5f * cos(ph) * gw;                          // 1 in a groove
        let ng = normalize(vec3f(tang * 0.13f * sin(ph) * gw + rad * 0.03f * sin(r * 160.0f), 1.0f));
        // deep cobalt glass; the engraving shows through as brightness, darker where the glass is deeper
        let lu = dot(env(refl(ng, S), 0.28f, S), vec3f(0.3f, 0.5f, 0.2f));
        var c = vec3f(0.010f, 0.030f, 0.22f) * (0.12f + 0.55f * lu) * (1.15f - 0.35f * groove);
        // the fired glass is gently domed across the ring: a clear coat (GGX ~0.1) catches the lights
        let u = (r - 0.5f * (R_Z0 + R_Z1)) / (0.5f * (R_Z1 - R_Z0));
        let ns = normalize(vec3f(rad * u * 0.22f, 1.0f));
        c += env_brdf(vec3f(0.04f), 0.10f, dot(ns, S.V)) * env(refl(ns, S), 0.10f, S);
        c *= 0.55f + 0.45f * smoothstep(0.0f, 0.016f, R_Z1 - r);                // the bezel's shadow on the glass
        // gold sign glyph, upright, applied in relief
        let lm = f32(sg) * 30.0f + 15.0f;
        let gc = CP(lm, 0.5f * (R_Z0 + R_Z1));
        let gs = 0.108f;
        let d = glyph_px(st, sg, (p - gc) / gs, gs * ppu);
        let dsh = glyph_px(st, sg, (p + kd * 0.0035f - gc) / gs, gs * ppu);   // applied: it casts a shadow
        c *= 1.0f - 0.55f * sat(1.0f - (dsh + 1.0f) / 4.0f);
        if (d < 1.5f) {
            let dx = glyph_px(st, sg, (p + vec2f(aa, 0) - gc) / gs, gs * ppu) - d;
            let dy = glyph_px(st, sg, (p + vec2f(0, aa) - gc) / gs, gs * ppu) - d;
            let bev = sat(1.0f + d / 2.2f);
            let n = normalize(vec3f(vec2f(dx, dy) * 0.9f * bev, 1.0f));
            c = mix(c, gold(n, 0.18f, S), sat(0.5f - d));
        }
        if (r < R_Z0 + aa) { c = mix(chapter_ring(r, lam, rad, aa, S), c, sat((r - R_Z0) / aa + 0.5f)); }
        return c;
    }
    // ---- the degree ring; both its edges filtered over the pixel (glass inside, enamel outside)
    if (r > R_D0 - aa) {
        var c = chapter_ring(r, lam, rad, aa, S);
        if (r < R_D0 + aa) { c = mix(glass_base(p, S), c, sat((r - R_D0) / aa + 0.5f)); }
        return c;
    }
    // ---- inside: blue aventurine glass (cobalt glass with copper crystals)
    let mo = textureLoad(st, vec2u(0u, u32(ROW_MOON)), 0);
    var c: vec3f;
    {
        let m = argus_fbm(p * 2.5f + 4.0f, 4);
        let base = mix(vec3f(0.0013f, 0.0022f, 0.0105f), vec3f(0.0030f, 0.0050f, 0.020f), 0.5f + 0.5f * m);
        c = base * irr(vec3f(0, 0, 1), S) * 2.2f + schlick(vec3f(0.04f), S.V.z) * env(refl(vec3f(0, 0, 1), S), 0.02f, S);
        // crystals: tiny tilted mirrors in the glass; each lights only when it mirrors a light
        let g = p * 300.0f;
        let cell = floor(g);
        let h0 = hash2(cell, 11.0f);
        if (h0 > 0.62f) {
            let o = vec2f(hash2(cell, 12.0f), hash2(cell, 13.0f)) - 0.5f;
            let fp = fract(g) - 0.5f - o * 0.6f;
            let tilt = (vec2f(hash2(cell, 14.0f), hash2(cell, 15.0f)) - 0.5f) * 1.0f;
            let nf = normalize(vec3f(tilt, 1.0f));
            let tint = mix(vec3f(1.0f, 0.55f, 0.30f), vec3f(1.0f, 0.80f, 0.55f), hash2(cell, 16.0f));
            let size = 0.10f + 0.22f * hash2(cell, 17.0f);
            let cov = exp(-dot(fp, fp) / (size * size) * 2.0f) * size * size * 6.0f;
            let k = pow(hash2(cell, 18.0f), 3.0f) * 1.6f + 0.05f;          // most crystals small, a few large
            // none right against a gold edge (a rim must stay a clean line, not a string of sparks)
            var keep = smoothstep(0.004f, 0.014f, R_D0 - r) * smoothstep(0.004f, 0.014f, r - R_MEDB)
                     * smoothstep(0.005f, 0.012f, abs(r - R_ASP));
            for (var b = 0; b < 10; b++) {
                let gr = gem_r(b);
                keep *= smoothstep(gr * 1.15f, gr * 1.7f, length(p - CP(textureLoad(st, vec2u(u32(b), u32(ROW_BODY)), 0).w, R_GEM)));
            }
            c += tint * env(refl(nf, S), 0.0f, S) * cov * k * keep;
        }
    }
    // ---- aspect threads and the aspect ring
    if (r < R_ASP + 0.01f) {
        if (r < R_ASP) {
            for (var k = 0; k < 45; k++) {
                let a = textureLoad(st, vec2u(u32(k), u32(ROW_ASP)), 0);
                if (a.z < 0.0f) { continue; }
                let p0 = CP(a.x, R_ASP); let p1 = CP(a.y, R_ASP);
                let ba = p1 - p0; let hh = sat(dot(p - p0, ba) / dot(ba, ba));
                let perp = normalize(vec2f(-ba.y, ba.x));
                let ds = dot(p - p0 - ba * hh, perp);
                let hw = 0.0038f + 0.0016f * a.w;                         // a tighter aspect, a wider cut
                if (abs(ds) < hw + 2.0f * aa && hh > 0.0f && hh < 1.0f) {
                    let en = select(vec3f(0.012f, 0.045f, 0.26f), vec3f(0.24f, 0.012f, 0.016f), a.z == 1.0f || a.z == 3.0f);
                    c = groove(c, ds, hw, perp, en, aa, S);
                }
            }
        }
        if (abs(r - R_ASP) < 0.006f + 2.0f * aa) { c = groove(c, r - R_ASP, 0.0040f, rad, vec3f(0.05f, 0.045f, 0.04f), aa, S); }
    }
    // ---- the Moon medallion, its phase and sign engraved beneath
    if (r < R_MEDB + 0.012f) {
        if (r < R_MEDB + aa) {
            // the medallion's bezel: one rounded bead (curvature widens its lobe); the Moon inside it,
            // its limb filtered over the pixel
            let t = clamp((r - 0.5f * (R_MED + R_MEDB)) / (0.5f * (R_MEDB - R_MED)), -1.0f, 1.0f);
            let rough = 0.06f + 1.2f / (0.5f * (R_MEDB - R_MED) * ppu);
            var g = gold(normalize(vec3f(rad * sin(t * 1.15f), cos(t * 1.15f))), rough, S);
            if (r < R_MED + aa) {
                let n = normalize(vec3f(p / R_MED * 0.55f, 1.0f));
                let m = moon_face(st, p / R_MED * min(1.0f, (R_MED - 0.5f * aa) / max(r, 1e-5f)), mo.x, mo.y, normalize(CP(mo.z, 1.0f)))
                      + 0.06f * pow(1.0f - dot(n, S.V), 4.0f) * vec3f(0.8f, 0.82f, 0.85f);
                g = mix(g, m, sat((R_MED - r) / aa + 0.5f));
            }
            return mix(c, g, sat((R_MEDB - r) / aa + 0.5f));
        }
        c *= 0.45f + 0.55f * smoothstep(R_MEDB, R_MEDB + 0.012f, length(p - vec2f(0.006f, -0.009f)));
    }
    let pv = preview(f.time);
    if (abs(p.x) < 0.20f && p.y < -0.19f && p.y > -0.31f) {
        let e = mo.x;
        var ph = 7;
        if (e < 7.0f || e > 353.0f) { ph = 0; } else if (abs(e - 90.0f) < 7.0f) { ph = 2; } else if (abs(e - 180.0f) < 7.0f) { ph = 4; } else if (abs(e - 270.0f) < 7.0f) { ph = 6; }
        else if (e < 90.0f) { ph = 1; } else if (e < 180.0f) { ph = 3; } else if (e < 270.0f) { ph = 5; }
        var ids: array<i32, 16>;
        var n = 0;
        for (var i = 0; i < 16 && PHASE[ph][i] != -2; i++) { ids[n] = PHASE[ph][i]; n++; }
        var d = text_px(st, &ids, n, p, vec2f(0.0f, -0.215f), 0.036f, ppu);
        let ml = mo.w;
        var m = 0;
        ids[m] = 13; m++; ids[m] = -1; m++;
        m = digits(&ids, m, i32(ml % 30.0f));
        ids[m] = G_DEG; m++; ids[m] = i32(ml / 30.0f) % 12; m++;
        d = min(d, text_px(st, &ids, m, p, vec2f(0.0f, -0.268f), 0.040f, ppu));
        // during the look-ahead: "Preview" and the local date being shown, in place of the phase
        var dp = 99.0f;
        if (pv.y > 0.0f) {
            for (var i = 0; i < 7; i++) { ids[i] = PREVIEW_W[i]; }
            dp = text_px(st, &ids, 7, p, vec2f(0.0f, -0.215f), 0.040f, ppu);
            let x = f.day_frac + 0.5f + pv.x + f32(f.utc_offset_s) / 86400.0f;
            let md = month_day(f.days_j2000 + i32(floor(x)) + 10957);
            var k = 0;
            for (var i = 0; i < 3; i++) { ids[k] = MONTH[md.x - 1][i]; k++; }
            ids[k] = -1; k++;
            k = digits(&ids, k, md.y);
            dp = min(dp, text_px(st, &ids, k, p, vec2f(0.0f, -0.268f), 0.044f, ppu));
        }
        let cov = mix(sat(0.5f - d), sat(0.5f - dp), pv.y);
        if (cov > 0.0f) { c = mix(c, gold(vec3f(0, 0, 1), 0.46f, S) * (1.0f + 0.25f * pv.y), cov); }
    }
    // ---- bodies: degree marks on the aspect ring, leaders, gems, labels
    for (var b = 0; b < 10; b++) {
        let bd = textureLoad(st, vec2u(u32(b), u32(ROW_BODY)), 0);
        let lam_b = bd.x; let disp = bd.w;
        let gr = gem_r(b);
        let gc = CP(disp, R_GEM);
        // the true longitude: a gold stud set in the aspect groove
        let ad = CP(lam_b, R_ASP);
        if (length(p - ad) < 0.012f) { c = mix(c, gold(normalize(vec3f((p - ad) / 0.0075f * 0.7f, 1.0f)), 0.08f, S), 1.0f - smoothstep(0.0062f - aa, 0.0062f + aa, length(p - ad))); }
        // soft cast and contact shadows, then the cabochon
        let dg = length(p - gc);
        if (dg < gr * 1.6f + 0.02f) {
            c *= 1.0f - 0.60f * (1.0f - smoothstep(gr * 0.80f, gr * 1.55f, length(p - gc + kd * 0.010f)));   // cast
            c *= 1.0f - 0.15f * (1.0f - smoothstep(gr * 1.0f, gr * 1.20f, dg));                                // contact
            // a faint glow of the stone's own colour, ~3 px, so each planet lifts off the dark glass
            if (dg > gr - aa) {
                var gc0 = vec3f(1.0f, 0.70f, 0.38f);
                if (b != 0) { gc0 = gem_albedo(b, vec2f(0.2f, 0.3f)); }
                let tone = normalize(gc0 + 0.05f) * 0.5f + 0.25f;
                c += tone * select(0.045f, 0.085f, b == 0) * exp(-max(dg - gr, 0.0f) * ppu / 2.6f);
            }
            // the stone alone, set flush (no rim), its edge filtered over the pixel
            if (dg < gr + aa) { c = mix(c, shade_gem(b, (p - gc) / gr * min(1.0f, (gr - 0.5f * aa) / max(dg, 1e-5f)), S), sat((gr - dg) / aa + 0.5f)); }
        }
        // labels on the gem's line, toward the centre: glyph; degree, sign, Rx; the coming event
        let lg = CP(disp, R_LG);
        if (length(p - lg) < 0.26f) {
            let ev = textureLoad(st, vec2u(u32(b), u32(ROW_EVENT)), 0);
            let L = label_d(st, p, b, lam_b, disp, ev, pv.y, ppu);
            let d = L.x; let dr = L.y; let de = L.z;
            // applied gold casts a soft shadow away from the key
            let Ls = label_d(st, p + kd * 0.0032f, b, lam_b, disp, ev, pv.y, ppu);
            c *= 1.0f - 0.5f * sat(1.0f - (min(min(Ls.x, Ls.y), Ls.z) + 1.0f) / 4.0f);
            // gold in relief: a soft bevel from the distance field
            let dm = min(d, de);
            let bv = sat(1.0f + dm / 1.5f);
            if (dm < 1.5f) { c = mix(c, gold(normalize(vec3f(-0.08f * bv, 0.08f * bv, 1.0f)), 0.42f, S) * select(1.0f, 0.80f, de < d), sat(0.5f - dm)); }
            // garnet enamel Rx
            if (dr < 1.5f) { c = mix(c, vec3f(0.35f, 0.03f, 0.03f) * (irr(vec3f(0, 0, 1), S) * 0.8f + 0.12f) + env_brdf(vec3f(0.04f), 0.15f, S.V.z) * env(refl(vec3f(0, 0, 1), S), 0.15f, S), sat(0.5f - dr)); }
        }
    }
    return c;
}

@compute @workgroup_size(16, 16)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let uv = argus_uv(gid, f);
    let ppu = 0.5f * f32(min(f.width, f.height)) * DIAL_R;
    var S = studio(f.time);
    let p = (uv - vec2f(0.0f, DIAL_Y)) / DIAL_R;
    S.V = normalize(vec3f(-p, CAM_D));
    let c = dial(argus_state, p, ppu, S);
    textureStore(argus_out, gid, vec4f(argus_srgb(argus_aces(c * 1.6f)), 1.0f));
}

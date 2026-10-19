// ROULETTE CHROME // themes/Roulette_Chrome.metal
// Claude (Anthropic), 2026-10-19.
//
// What you see: a modern European single-zero casino wheel from straight above, standing at the
// end of its table under the table's light box, in a lit casino hall. The croupier spins the
// rotor (brake, hold, two pushes, to 0.25-0.34 rev/s; the direction alternates from spin to spin)
// and throws the white ball on the black stone track against it. The ball rides the wall for
// 13-17 s (9-13 laps: the first 0.75-1.0 s, the last full one ~2.0-2.3 s, released at 2.51 s
// per revolution), falls down the veneer stator, strikes a chrome diamond in about half the
// spins, drops onto the turning rotor, runs along its rim, rattles across the frets and settles
// in a pocket. It rides there with the coasting rotor for 10 s; then a hand (not drawn) closes
// over it, lifts it out and later sets it back on the track for the next throw: one spin about
// every 31-37 s. Every pocket comes out of the dynamics; nothing is scripted. Only
// chrome is a mirror; the veneer, lacquer, stone and ball are satin.
//
// Sources ([cited] page read, [snippet] search result only, [looked at] photo):
//   - Small & Tse, Chaos 22 (2012), arXiv:1204.6412 [cited]: the ball rides the rim while
//     thetad^2 > (g/r) tan(alpha), leaves it at a fixed speed, crosses the stator, meets the
//     deflectors, then frets make the end chaotic; ball and wheel decelerations are close to
//     constant -> the rim phase, its near-constant loss, the release condition, the rotor's decay.
//     Their Fig. 4 (hand-timed, a casino-grade 32-inch European wheel) [cited, read from the
//     plot]: ball laps from ~0.9-1.0 s on the first timed laps to ~2.3-2.6 s on the last before it
//     leaves the rim, each ~5-15 % longer than the one before; the wheel at 2-4 s per turn while
//     spinning -> the push (0.25-0.34 rev/s: 2.9-4 s a turn, the slower part of their range, see
//     the shutter below), the release (2.51 s per revolution: inside their last-lap range) and the
//     rim loss. Not a fit to every number: the first lap here is 0.75-1.0 s from the throw (a
//     throw is faster than a lap timed once the ball runs: CHOSEN), and the last full lap
//     before the release ~2.0-2.3 s, a little shorter than their 2.3-2.6 s.
//   - A spin counts only with >= 4 ball revolutions (3 in some places) and the ball must run
//     opposite to the rotor: N.J.A.C. 13:69E, Singapore GRA rule sets [snippet] -> both enforced
//     (a throw that breaks them is a "no spin", thrown again). ~40-60 spins an hour on a live
//     single-zero table [snippet, weak sources]; most of that is payout and betting, which this
//     scene does not show, so the rest in the pocket is cut to 10 s (CHOSEN, owner's call).
//   - 8 deflectors alternating radial / tangential, US6047965 [cited] -> the 8 diamond studs.
//   - Wheel 80-83 cm across [cited]; ball 19-22 mm, non-metallic [cited] -> an 82 cm bowl, a
//     20 mm ball; PTFE or resin balls in modern casinos [cited, commercial]; PTFE index ~1.3-1.4
//     (arXiv:0910.1056, fits 1.25-1.56) [snippet] -> F0 0.03, a high-albedo diffuse ball.
//   - European order clockwise from 0, red set, numerals tops outward [cited, brief; Commons
//     Roulette_casino.JPG looked at] -> the ring.
//   - Chromium n ~3.11, k ~4.42 at 550 nm (US patent optical tables) [snippet] -> normal
//     reflectance ~0.65, neutral: chrome F0 0.60.
//   - Clear coats: IOR 1.50-1.56, US7248350 [snippet]; nitrocellulose 1.51, shellac 1.52
//     (woodweb, "Illusion of Depth in Transparent Coatings") [snippet] -> F0 0.04.
//   - Engineered-stone ball tracks: Cammegh "Garnite" (Mercury 360 page) [cited]; Huxley Saturn
//     "engineered stone solid surface" [cited] -> the black stone track.
//   - Wiesbaden casino photos -093/-094 (Commons) [looked at]: bold white numerals, a mirror
//     rotor rim, rounded chrome frets, felt-lined pockets (satin lacquer here, the owner's
//     choice), faceted diamonds, a satin white ball; Cammegh Mercury 360 [looked at]: 8
//     book-matched cone sectors, black upper track over veneer; Commons Roulette_casino_coupe.jpg
//     [looked at]: the steep track, the cross with ball ends, the ball-rest cup.
//   - Shading formulas (standard, from the papers; not re-read this round): GGX microfacets
//     (Walter et al. 2007); the split-sum environment BRDF and its analytic fit (Karis 2014,
//     "Physically Based Shading on Mobile"); the "Charlie" sheen distribution (Estevez & Kulla
//     2017, "Production Friendly Microfacet Sheen BRDF") with Neubelt & Pettineo's visibility.
// COMPUTED (from the model, not tuned by eye):
//   - where the ball leaves the wall: ROLL_K v^2/r = g tan(alpha), ROLL_K = 1 + I/mR^2 = 1.4 for
//     a rolling sphere (Small & Tse's eq. 1 is the point mass, ROLL_K = 1): 94.7 cm/s, 2.51 s per
//     revolution; alpha (18.7 deg) is the stator's slope at the ball's contact;
//   - the descent, strikes, bounces, rattle and pocket: a rigid sphere with spin on the exact
//     surfaces drawn (one SHARED GEOMETRY block for physics and draw), contacts against the
//     rotor's moving surface, 2400 Hz sub-steps;
//   - every reflection: rays into one world-fixed hall (light box, coffer, fixtures, walls, other
//     tables' lamps), into the wheel itself, the bowl's far side, or the cone and turret in the
//     way; box-filtered over the lobe and the normal's turn within the pixel. A satin lobe is
//     GGX's reflected FWHM, 2.57 alpha (alpha = roughness^2); its strength Fresnel over that lobe
//     (split-sum fit): F0 0.04 face-on, ~0.38 at grazing for roughness 0.3, no boosts;
//   - the ball's shadow: the share of the light box (17 deg off-axis) its silhouette hides, ~0.3
//     cm off per cm of height, plus its occlusion; its image in glossy surfaces; what hides it
//     (lip, handle); the lip's silhouette and the rotor-stator gap: exact pixel coverage (the
//     gap's dark slot lies under the ball, so it shows only where the ball leaves the pixel open);
//   - the bowl's shadow on the felt: the share of the light box the 11.5 cm bowl hides (the
//     highest elevation the apron and rim hide toward the box, against the box's elevation span):
//     a soft band away from the box, none toward it; the hall's ~40 % is occluded evenly round
//     the bowl's foot (CHOSEN falloff).
// CHOSEN (taste or calibration, not measured):
//   - time scale 1:1 (real seconds) except the betting interval: 10 s settled (a real table rests
//     ~40-60 s); the hand closes over the ball in
//     its pocket (0.15 s: the ball fades out there, as the fingers would hide it from above),
//     lifts and carries it off hidden, the rotor push (brake 0.8 s, hold 0.3 s, two 0.25 s
//     pushes) to 0.25-0.34 rev/s, the ball set back on the track (fading in over 0.12 s as the
//     fingers open) and thrown (0.08 s) at 1.05-1.45 rev/s against the rotor's present
//     direction; no ball is ever shown in the air over the wheel or the felt; frame 0 is 3 s
//     after a launch;
//   - the push's cap, 0.34 rev/s: at the app's default 30 FPS the 37 identical frets then move
//     at most 0.42 pocket a frame, under the wagon-wheel limit of 0.5 (see the shutter);
//   - rim loss, fitted to Small & Tse's lap times: MU_RIM 0.006 (rolling + skid on the stone) +
//     MU_WALL 0.004 (wall scrub) + air drag (computed K_AIR): ~35 cm/s^2 at the throw, ~7 at the
//     release; rolling resistance on veneer and rotor 0.016; restitution 0.40 (lacquer, stone,
//     wood) / 0.55 (chrome), none below 12 cm/s; friction 0.25 / 0.10 (chrome); rotor decay
//     0.006 rad/s^2 + 0.0025/s;
//   - the profile: a cubic stator steepened below r 32.5 (38 deg at the rotor, 35 at the
//     diamonds, 18.7 at the rim), an 8 deg overhung lip, the rotor 0.48 cm below the stator's
//     edge, a 20 deg number ring, a ~1 cm chrome rotor rim (shaded as a convex bead), a dished
//     pocket floor, frets 0.85 cm proud, diamonds 3.0 x 0.86 cm with a 4-facet cap to 0.8 cm, a
//     domed turret with a ball-rest cup, a cross of tapered rods with 2.4 cm ball finials;
//   - camera 270 cm up; the hall: ceiling paint 0.09, a dark coffer 4.3 m across, slot rows
//     beyond with hashed fixtures (a quarter off), walls 4.5 m away, 5 other tables' lamps; the
//     light box over the layout, 94 cm off the wheel's axis; every colour (mahogany, darker on the
//     bowl; red, black, green lacquer; white numerals; teal felt; a near-black stone, albedo
//     0.011), the veneer's chevron and chatoyance, the stone's grain (about +-5 %), the GGX
//     roughnesses (bowl 0.32, stator veneer 0.30, cone 0.28, number ring 0.32, pocket floors
//     0.40, stone 0.40, PTFE ball 0.22: the light box a soft patch in each, never a line), the
//     felt's nap, light pool and sheen (roughness 0.5, colour 5x the felt's), the numerals,
//     exposure; the ball lit on the scale of every surface (~60 % light box, near-Lambert; ~40 %
//     the rest of the ceiling); the diamonds' shading facets less sheared than their collision's;
//   - shutter: one fixed exposure of 1/120 s for everything that moves (rotor, numerals, frets,
//     arms, ball), the same at 30, 60 and 120 FPS: at 120 FPS the look the owner watched
//     (numerals readable mid-spin); a frame on a 30 Hz tick is pixel-identical at all three
//     rates (checked). The cost at lower rates is temporal: at 30 FPS the ball on its first laps
//     jumps ~11 cm (~120 px, 4-5 ball widths) a frame as a short capsule, a visible strobe (60
//     FPS: ~60 px). The rotor turns at most 0.42 pocket a frame at 30 FPS (the push's cap), so
//     frets and numerals step forward, never backward; near the limit the 37-fold fret pattern
//     may still read as flicker in peripheral vision (a risk, not judged by viewers). 1/240 s
//     (round 3): crisper, but no longer the 120 FPS look. Above 0.42 pocket a frame (never in
//     this cycle) the frets' periodic contrast fades to its mean (f.dt; deterministic).
// NOT MODELLED:
//   - the croupier's hand itself (where it would hide the ball from above, the ball fades);
//     no chips, no dolly, no table layout or rail: the wheel stands on plain felt;
//   - Magnus/air-spin coupling, track wear and imperfections, the ball's load on the rotor, wheel
//     tilt; the diamonds follow the slope by shearing, not by a true tilt;
//   - the ball's rolling (a plain ball shows none); GGX's long tails (the box lobe has none: the
//     satin highlights end a little sooner than a real glow); scratches, dust.
//   - Known limits: a diamond struck in 57 % of spins (no sourced rate); a ball reaching the
//     rotor runs along its outer edge for ~1.3 s on average (bench) before it runs in (a rolling
//     sphere on a counter-turning surface keeps its speed; a real ball skids and bounces more);
//     the hop shadow is soft and subtle, as an area light gives; the 30 FPS strobe (above). The
//     diamonds and frets do not glint from straight above: diamond facets lean 34-40 deg and the
//     up-facing strip of a fret's crown is under a pixel, while mirroring the light box takes a
//     face tilted ~9 deg toward it; they show as grey chrome (176-213 of 255; the turret 254),
//     not faked. The white ball sits in the tone curve's shoulder: its satin highlight lifts it
//     to 239 (numerals 232) and it falls ~15 levels toward the limb away from the box: a soft,
//     mostly white disc, not a glossy sphere.
// CHECKED:
//   - one robustness bench (scratch: the same physics, 256 wheels x 1 h of 30 Hz ticks, seed
//     7; rerun with the 10 s rest): 27,995 settled spins, 0 voided (no "no spin" either), 0 escapes; rim 13.3-16.8 s
//     (mean 15.2; 16 % 10-14 s, 84 % 14-18 s), 8.9-13.2 revolutions (47 % 8-11, 53 % 11-14);
//     first lap 0.75-1.03 s (mean 0.88, from the throw), release 2.51 s per revolution, each lap
//     2-17 % longer than the one before; stator 0.7-1.3 s (0.81); rotor 0.7-5.9 s (3.4);
//     launch to settled mean 19.5 s, max 23.3; settled always on a pocket floor (z 1.80-1.82,
//     never on a fret), the rotor then at 0.21-0.31 rev/s; worst overlap with any surface 0.07
//     cm; outcomes chi^2 18.9 on 2,048 results (df 36, 95 % line 51.0); slot changes after the
//     ball first enters the pocket ring: 0 in 1 %, 1-2 in 19 %, 3-5 in 52 %, 6+ in 28 % (mean
//     4.7); a diamond struck in 57 % of spins, always on the way down, at most 4 separate strikes
//     in a spin (counted after > 20 ms off every diamond; the raw sub-step count's 16 was one
//     contact flickering), longest diamond contact 31 ms (never sticks); highest flight 5.9 cm
//     above the stator after a strike, 7.3 cm above the rotor in the rattle; back onto the stator
//     in 2 spins of 27,995; 108.6 spins per wheel-hour; the ball always against the rotor (the
//     throw takes the rotor's sign after the push);
//   - a state trace (default seed, 4 spins): rotor 0.25-0.34 rev/s alternating, the ball
//     against it, 7.4-13.1 laps (the first spin starts mid-run), first laps 0.73-0.81 s, last full
//     laps 2.04-2.28 s, release 2.51 s; the hand: the ball fades in its pocket before it rises and
//     fades in on the track before the throw (frames 1819-1822, 1926-1929);
//   - harness PASS, NaN-clean; the contact sheet; 1:1 crops before and after the satin change;
//     the round-2 cone streak (a hall fixture mirrored in the clear coat) is a faint broad sheen;
//     the ball over the rotor-stator gap (frame 400) has no line through it; the shutter at
//     30/60/120 FPS (tick blend and f.dt forced in scratch copies, rotor at its cap, the hardest
//     throw) and a 30 FPS burst;
//   - not checked: the timings against a filmed spin (Small & Tse's hand timings only).
// How it works:
//   - argus_step: 10 threads; each recomputes the whole 30 Hz tick (80 sub-steps) from the
//     previous state and writes its own texel. Phases: 0 ball out (the hand's path), 1 rim
//     (pinned, rolling at both contacts), 2 stator and 3 rotor (free rigid sphere), 4 settled.
//     Safety: NaN, escape or a spin over 45 s voids it ("no spin"); never seen in the bench.
//   - State 480x1201 float32. Row 0: 0 (rotor angle, rate, phase, phase time), 1 (ball xyz,
//     opacity), 2 (velocity, rolling angle), 3 (winning slot, spins, direction, number), 4..7
//     private, 8..9 the previous tick (the draw blends ticks at 60/120 FPS, one tick late), 10
//     the bake's size. Rows 1..1200: a bake by argus_init, one float per pixel (see bake_px): the
//     felt's final colour, else the height the camera sees. 9.2 MB, x2 ping-pong.
//   - argus_draw: a pinhole camera over a height field of revolution (8 steps + 5 bisections, baked; a
//     pixel on the lip's silhouette shaded for both sides, blended by coverage); chrome and satin
//     dielectrics against env(); the felt diffuse + sheen in the bowl's shadow; analytic blur
//     over the shutter (pocket colours and five fret facets box-filtered in angle, numerals over
//     up to 10 positions, the ball as 4 capsules along its arc, shaded from its path's nearest
//     point). The source must stay under 128 KiB (the app and harness read 131,072 bytes).
// Cost: busy machine (an ML job), 3 alternated runs at frame 300: 1.81 ms back-to-back at
//   1920x1200 against Night Tide's 2.56-2.59 ms (0.71x); paced 3.3-4.7 ms against 4.5-4.9. The
//   bake took it from 2.95 ms (the felt was ~1.05 ms, the height search ~0.4); proven by diffing
//   8 moments x 3 seeds: max 1/255, mean <= 0.0002/255. The first frame takes longer once (init
//   pre-runs 3 s of the rim and bakes).
// @argus state 480x1201 float32
// @argus steps 1

// ==== SHARED GEOMETRY ====
// Units cm. World frame: wheel centre at the origin, z up, felt top at z = 0, x right, y up the
// screen, angles CCW-positive seen from above. Rotor-frame angle a = world angle - phi.
// The physics collides with exactly these surfaces; the draw should render exactly these.
constant float PI_F        = 3.14159265f;
constant float TAU_F       = 6.28318531f;
constant float G_ACC       = 981.0f;      // cm/s^2
constant float R_BALL      = 1.0f;        // 20 mm white resin ball
constant int   N_POCKETS   = 37;
constant float POCKET_DA   = 0.16981582f; // 2 pi / 37
constant float POCKET_A0   = 1.57079633f; // rotor-frame angle of the centre of slot 0 (the zero)
                                          // slot i is centred at POCKET_A0 - i*POCKET_DA (clockwise)
// Bowl and stator (static). The stator is a smooth cubic from the rotor edge to the wall,
// z = Z_STATOR_IN + x (STATOR_T_IN + x (STATOR_S2 + x STATOR_S3)), x = r - R_STATOR_IN, plus a
// steepening inside R_STEEP: + STEEP_C ((R_STEEP - R_STATOR_IN)^2 - (R_STEEP - r)^2) (C1 at
// R_STEEP; outside it the cubic is lifted by STEEP_DZ). 38 deg at the rotor edge, 35 deg at the
// diamonds, easing to 18.7 deg at the ball's rim contact. The orbit a ball needs (r^3 dz/dr)
// is larger everywhere inside the wall than the released ball has, so it falls across the
// diamond ring in about a revolution instead of spiralling at it.
constant float R_STATOR_IN = 28.0f;       // inner edge of the stator (next to the rotor rim)
constant float Z_STATOR_IN = 3.45f;      // 0.48 above the rotor rim: the rotor sits below the stator
constant float STATOR_T_IN = 0.60f;       // slope dz/dr at R_STATOR_IN (31.0 deg)
constant float STATOR_S2   = 0.0138204f;
constant float STATOR_S3   = -0.0017395f;
constant float R_STEEP     = 32.5f;       // the lower track is steepened inside this radius
constant float STEEP_C     = 0.02f;
constant float STEEP_DZ    = 0.405f;      // STEEP_C (R_STEEP - R_STATOR_IN)^2: the lift outside R_STEEP
constant float R_RIM_WALL  = 39.0f;       // foot of the back-track wall the ball rides against;
constant float WALL_LEAN   = 0.13963f;    //   the wall overhangs inward by 8 deg (a lip that keeps the
constant float R_WALL_TOP  = 38.7691f;    //   ball down): its top edge is at r = R_WALL_TOP
constant float Z_WALL_FOOT = 9.812f;      // stator_z(R_RIM_WALL)
constant float Z_RIM_TOP   = 11.455f;     // top of the wall / flat rim top r 39..41 (1.64 above its foot)
constant float R_RIM_OUT   = 41.0f;       // outer edge of the rim top (apron 41..45 falls to the felt)
constant float R_APRON_OUT = 45.0f;
constant float ALPHA_TRACK = 0.32605f;    // 18.68 deg: stator slope at the ball's rim contact (r 38.21)
constant float R_BALL_RIM  = 37.891f;       // ball centre radius while it rides the wall
constant float Z_BALL_RIM  = 10.518f;     // ball centre height while it rides the wall
// Diamonds (deflectors): 8 chrome studs on the stator, centred at r = R_DIAMOND, angles k*45 deg;
// even k radial (long axis along the radius), odd k tangential. A rhombic footprint
// (half-diagonals DIAMOND_HALF_LEN x DIAMOND_HALF_WID, 3 cm long, 3.5:1) with upright sides
// DIAMOND_HE tall, capped by a 4-facet pyramid whose apex stands DIAMOND_H above the local stator
// surface (it follows the slope); edges rounded with DIAMOND_ROUND. See diamond_sdf().
constant float R_DIAMOND        = 31.0f;
constant float DIAMOND_HALF_LEN = 1.5f;
constant float DIAMOND_HALF_WID = 0.43f;
constant float DIAMOND_H        = 0.8f;
constant float DIAMOND_HE       = 0.45f;
constant float DIAMOND_ROUND    = 0.10f;
constant float DIAMOND_KX = (DIAMOND_H - DIAMOND_HE) / DIAMOND_HALF_LEN;   // facet slopes
constant float DIAMOND_KY = (DIAMOND_H - DIAMOND_HE) / DIAMOND_HALF_WID;
// Rotor (wheelhead): axisymmetric profile in (r, z), turning with phi, plus 37 frets.
constant float R_TURRET    = 7.0f;        // the turret's collar meets the cone here (turret_z below)
constant float R_CONE_IN   = 7.0f;        // cone r 7..19.5, straight, z 5.4 -> 1.6
constant float Z_CONE_TOP  = 5.4f;
constant float R_POCKET_IN = 19.5f;       // pocket ring r 19.5..24
constant float Z_CONE_OUT  = 1.6f;
constant float R_DISH_C    = 21.9f;       // pocket floor: circular arc, lowest at r = R_DISH_C,
constant float Z_POCKET    = 0.8f;        //   z = Z_POCKET, radius R_DISH (centre at z 4.8)
constant float R_DISH      = 4.0f;
constant float R_NUM_IN    = 24.0f;       // pocket outer wall: vertical step at r = 24 from the
constant float Z_DISH_OUT  = 1.39557f;    //   floor (z 1.396) up to the number ring (z 1.50)
constant float Z_NUM_IN    = 1.50f;       // number ring r 24..27, straight, z 1.50 -> 2.592 (20.0 deg
constant float R_NUM_OUT   = 27.0f;       //   down into the pockets: g tan 20 deg = 357 cm/s^2 beats the
constant float Z_NUM_OUT   = 2.592f;      //   <= 320 a ball riding with the fastest rotor feels outward)
constant float R_ROTOR_OUT = 27.95f;      // chrome rotor rim r 27..27.95 (a polished band ~1 cm),
constant float Z_ROTOR_RIM = 2.97f;       //   z 2.592 -> 2.97 (21.7 deg), a 0.48 cm step under the stator
                                          //   edge (28, 3.45): a ball thrown out against it rarely climbs back
// Frets: thin chrome plates in the radial planes between pockets (rotor angle
// POCKET_A0 - (i + 0.5) POCKET_DA), from r 19.2 to 24, top Z_FRET_TOP, 2*FRET_HALF_W thick,
// the top edge rounded with radius FRET_HALF_W. Low profile: 0.85 cm above the pocket floor.
constant float R_FRET_IN   = 19.2f;
constant float R_FRET_OUT  = 24.0f;
constant float Z_FRET_TOP  = 1.65f;
constant float FRET_HALF_W = 0.15f;
// Turret (the chrome column on the rotor axis) and its 4-arm handle. One profile of revolution,
// drawn as is and collided as a 12-point polyline through it (sag < 0.03 cm, under a pixel):
// a rounded collar r 4.6..7 (z 5.4 -> 6.1), a flared column r 2.05..4.6, a domed boss r < 2.05
// (a sphere of radius 2.3, top z 11.86) with the ball-rest cup in its top (r < 0.6).
static inline float sq(float x) { return x * x; }
static inline float turret_z(float r) {
    if (r < 0.6f) return 11.55f + 0.25f * sq(r / 0.6f);
    if (r < 2.05f) return 9.556f + sqrt(max(5.29f - r * r, 0.0f));
    if (r < 4.6f) return 6.7f + 2.9f * sq(1.0f - (r - 2.05f) / 2.55f);
    return Z_CONE_TOP + 0.7f * sqrt(max(1.0f - sq((r - 4.6f) / 2.4f), 0.0f));
}
constant float TURRET_PR[12] = { 7.0f, 6.95f, 6.8f, 6.5f, 6.0f, 5.3f, 4.6f, 4.5999f, 3.8f, 3.0f, 2.0501f, 2.0499f };
// Handle (a "French cross"): 4 turned chrome rods at height ARM_Z from r ARM_R0 to ARM_R1,
// tapering from radius ARM_RA to ARM_RB, each ending in a ball finial (radius KNOB_R) at r
// KNOB_AT, at rotor angles ARM_A0 + k 90 deg. ARM_R is their mean radius (for the shadows).
constant float ARM_Z = 10.35f, ARM_RA = 0.75f, ARM_RB = 0.55f, ARM_R = 0.65f, ARM_R0 = 2.0f, ARM_R1 = 10.9f;
constant float KNOB_R = 1.2f, KNOB_AT = 11.7f;
constant float ARM_A0 = 0.785398f;
static inline float arm_radius(float t) { return mix(ARM_RA, ARM_RB, saturate(t)); }   // t 0..1 along the rod
// Wheel layout, clockwise from 0 seen from above.
constant uchar EU_SEQ[37] = { 0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
                              5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26 };
static inline bool is_red(int n) {
    // 1 3 5 7 9 12 14 16 18 19 21 23 25 27 30 32 34 36
    return n > 0 && ((((n <= 10) || (n >= 19 && n <= 28)) && (n & 1)) ||
                     (((n >= 11 && n <= 18) || (n >= 29)) && !(n & 1)));
}
// Stator surface height at radius r (R_STATOR_IN..R_RIM_WALL; the rim top above that).
static inline float stator_curve_z(float r) {   // the curve itself (no rim top)
    const float x = max(r - R_STATOR_IN, 0.0f), y = max(R_STEEP - r, 0.0f);
    return Z_STATOR_IN + x * (STATOR_T_IN + x * (STATOR_S2 + x * STATOR_S3)) + STEEP_DZ - STEEP_C * y * y;
}
static inline float stator_z(float r) {
    return r >= R_RIM_WALL ? Z_RIM_TOP : stator_curve_z(r);
}
static inline float stator_slope(float r) {        // dz/dr of the stator curve
    const float x = max(r - R_STATOR_IN, 0.0f);
    return STATOR_T_IN + x * (2.0f * STATOR_S2 + 3.0f * STATOR_S3 * x) + 2.0f * STEEP_C * max(R_STEEP - r, 0.0f);
}
static inline float stator_curv(float r) {         // d2z/dr2
    const float x = max(r - R_STATOR_IN, 0.0f);
    return 2.0f * STATOR_S2 + 6.0f * STATOR_S3 * x - (r < R_STEEP ? 2.0f * STEEP_C : 0.0f);
}
// Axisymmetric rotor profile (no frets), r in the rotor (any angle).
static inline float rotor_profile_z(float r) {
    if (r < R_TURRET)    return turret_z(r);
    if (r < R_POCKET_IN) return mix(Z_CONE_TOP, Z_CONE_OUT, (r - R_CONE_IN) / (R_POCKET_IN - R_CONE_IN));
    if (r < R_NUM_IN) { const float d = r - R_DISH_C; return Z_POCKET + R_DISH - sqrt(max(R_DISH * R_DISH - d * d, 0.0f)); }
    if (r < R_NUM_OUT)   return mix(Z_NUM_IN, Z_NUM_OUT, (r - R_NUM_IN) / (R_NUM_OUT - R_NUM_IN));
    if (r < R_ROTOR_OUT) return mix(Z_NUM_OUT, Z_ROTOR_RIM, (r - R_NUM_OUT) / (R_ROTOR_OUT - R_NUM_OUT));
    return Z_ROTOR_RIM;
}
// Continuous slot coordinate of a rotor-frame angle: slot centres at integers, frets at +-0.5.
static inline float slot_coord(float a_rotor) {
    float s = (POCKET_A0 - a_rotor) / POCKET_DA;
    return s - 37.0f * floor(s / 37.0f);               // 0..37
}
static inline int slot_at(float a_rotor) { return int(floor(slot_coord(a_rotor) + 0.5f)) % 37; }
// Perpendicular distance (cm) from (r, a_rotor) to the nearest fret plane.
static inline float fret_plane_dist(float r, float a_rotor) {
    const float s = slot_coord(a_rotor);
    const float off = (s + 0.5f - floor(s + 0.5f)) - 0.5f;          // -0.5..0.5 from slot centre
    return r * abs(sin((0.5f - abs(off)) * POCKET_DA));
}
// Rotor surface height at rotor-frame polar (r, a): profile, and the fret tops where they stand.
static inline float rotor_z(float r, float a_rotor) {
    const float z = rotor_profile_z(r);
    if (r > R_FRET_IN && r < R_FRET_OUT) {
        const float w = fret_plane_dist(r, a_rotor);
        if (w < FRET_HALF_W) {
            const float top = Z_FRET_TOP - FRET_HALF_W + sqrt(max(FRET_HALF_W * FRET_HALF_W - w * w, 0.0f));
            return max(z, top);
        }
    }
    return z;
}
// Signed distance (cm) from a point in a fret's own frame (u along the radius, w across the
// plate, z up) to that fret: a rounded box r R_FRET_IN..R_FRET_OUT, |w| < FRET_HALF_W, z < Z_FRET_TOP.
static inline float fret_sdf_local(float3 loc) {
    const float3 cen = float3(0.5f * (R_FRET_IN + R_FRET_OUT), 0.0f, 0.5f * Z_FRET_TOP);
    const float3 hal = float3(0.5f * (R_FRET_OUT - R_FRET_IN), FRET_HALF_W, 0.5f * Z_FRET_TOP) - FRET_HALF_W;
    const float3 q = abs(loc - cen) - hal;
    return length(max(q, 0.0f)) + min(max(q.x, max(q.y, q.z)), 0.0f) - FRET_HALF_W;
}
// Signed distance from a world point to the nearest fret, rotor at angle phi.
static inline float fret_sdf(float3 p, float phi) {
    const float sc = (POCKET_A0 - (atan2(p.y, p.x) - phi)) / POCKET_DA;
    const float j = floor(sc + 0.5f);
    float d = 1e3f;
    for (int side = 0; side < 2; side++) {
        const float fa = POCKET_A0 - (j + (side == 0 ? -0.5f : 0.5f)) * POCKET_DA + phi;
        const float2 eu = float2(cos(fa), sin(fa)), ew = float2(-eu.y, eu.x);
        d = min(d, fret_sdf_local(float3(dot(p.xy, eu), dot(p.xy, ew), p.z)));
    }
    return d;
}
static inline float sd_rhombus(float2 p, float2 b) {   // exact 2D rhombus, half-diagonals b (iq)
    p = abs(p);
    const float h = clamp(((b.x - 2.0f * p.x) * b.x - (b.y - 2.0f * p.y) * b.y) / dot(b, b), -1.0f, 1.0f);
    const float d = length(p - 0.5f * b * float2(1.0f - h, 1.0f + h));
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}
static inline float diamond_angle(int k) { return float(k) * 0.78539816f; }
// Signed distance (cm) from a world point to diamond k (negative inside).
static inline float diamond_sdf(float3 p, int k) {
    const float th = diamond_angle(k);
    const float2 er = float2(cos(th), sin(th));
    const float2 et = float2(-er.y, er.x);
    const float lr = dot(p.xy, er) - R_DIAMOND, lt = dot(p.xy, et);
    const float2 q = (k & 1) == 0 ? float2(lr, lt) : float2(lt, lr);
    const float hb = p.z - stator_z(length(p.xy));     // height above the local stator surface
    const float d2 = sd_rhombus(q, float2(DIAMOND_HALF_LEN, DIAMOND_HALF_WID));
    // the pyramid cap: the plane of the facet over q, as a distance
    const float df = (hb - DIAMOND_HE - (DIAMOND_H - DIAMOND_HE) * (1.0f - abs(q.x) / DIAMOND_HALF_LEN - abs(q.y) / DIAMOND_HALF_WID))
                   * rsqrt(1.0f + DIAMOND_KX * DIAMOND_KX + DIAMOND_KY * DIAMOND_KY);
    const float2 wv = float2(d2 + DIAMOND_ROUND, max(df, -hb - DIAMOND_H) + DIAMOND_ROUND);
    return min(max(wv.x, wv.y), 0.0f) + length(max(wv, 0.0f)) - DIAMOND_ROUND;
}
// ==== END SHARED GEOMETRY ====

// ---------------------------------------------------------------------------------------------
// Dynamics constants. [cited] page read, [snippet] search result only, chosen = picked by us.
constant float SUB_HZ       = 2400.0f;     // sub-step rate (chosen: no tunnelling, see header)
constant float K_AIR        = 1.05e-4f;    // 1/cm: rho Cd A / 2m, rho 1.2e-3 g/cm3, Cd 0.47, A pi cm2, m 8.4 g
constant float MU_ROLL      = 0.016f;      // rolling resistance of the free ball on veneer and the rotor
constant float MU_RIM       = 0.006f;      // ... on the polished stone track (the rim phase, and the free
                                           //   ball on the stone): with MU_WALL and air drag, fitted to
                                           //   Small & Tse's lap times (chosen, see the header)
constant float R_TRACK_IN   = 34.0f;       // the polished stone ball track: from here to the lip
constant float MIN_REVS     = 4.0f;        // a spin counts only with >= 4 ball revolutions [snippet]
constant float MU_WALL      = 0.004f;      // scrub loss at the wall contact (chosen: fitted, as MU_RIM)
constant float MU_SLIDE     = 0.25f;       // Coulomb friction resin on lacquer / wood (chosen)
constant float MU_CHROME    = 0.10f;       // ... on polished chrome: frets, diamonds (chosen)
constant float K_PIVOT      = 0.002f;      // pivot friction: spin about the normal decays in ~0.5 s
constant float E_SURF       = 0.40f;       // restitution on track / ring / floor / cone (chosen)
constant float E_CHROME     = 0.55f;       // restitution on frets, diamonds, rotor rim (chosen)
constant float V_REST       = 12.0f;       // below this normal speed a contact does not bounce
constant float ROLL_K       = 1.4f;        // 1 + I/(m R^2) for a solid sphere
constant float ROTOR_DECEL  = 0.006f;      // rad/s^2 bearing friction (chosen)
constant float ROTOR_DRAG   = 0.0025f;     // 1/s velocity-proportional drag (chosen)
constant float SETTLE_V     = 2.0f;        // cm/s relative to the rotor
constant float SETTLE_T     = 0.4f;        // s at rest in a pocket before the lock
// Spin cycle (s). Phase 0 timeline: the hand closes over the ball in its pocket (the hand is not
// drawn; from straight above its fingers would hide the ball, so the ball fades out there, in the
// pocket), lifts it and carries it off (hidden), the rotor push, the ball brought back (hidden),
// set on the track (it fades in as the fingers open) and thrown. No ball ever floats in the air.
constant float T_GRIP       = 0.15f;       // the hand closes over the ball in its pocket: it fades out
constant float T_LIFT       = 0.3f;        // lifted Z_HAND, decoupling from the rotor (hidden)
constant float T_CARRY      = 1.0f;        // ... carried out past the bowl (hidden)
constant float T_PUSH0      = 1.2f;        // the rotor push: brake, hold, two pushes (T_PUSH long)
constant float T_PUSH       = 1.85f;
constant float T_PLACE      = 3.1f;        // the hand brings the ball back ...
constant float T_LAUNCH     = 3.7f;        // ... sets it on the track and throws it
constant float T_LOWER      = 0.12f;       // the fingers open over the ball on the track: it fades in
constant float T_THROW      = 0.08f;
constant float Z_HAND       = 15.0f;       // the hand carries the ball above the turret (cm)
constant float T_SETTLED    = 10.0f;       // time the ball rides in its pocket (a ~34 s cycle)
constant float T_NOSPIN     = 45.0f;       // safety: a spin still running after this is voided
constant float T_INIT_AHEAD = 3.0f;        // first frame: 3 s after a launch

struct Sim {
    float phi, phid, phase, pt;   // t0
    float3 p;  float op;          // t1
    float3 v;  float roll;        // t2
    float win, spins, dir, num;   // t3
    float3 w;  float flags;       // t4: spin vector (rad/s); flags = touching a diamond (counts strikes)
    float th, thd, air, slow;     // t5: rim angle/speed, airborne time, settle timer
    float3 lk; float target;      // t6: lock (r, a_rotor, z); |phid| target of the push
    float ramp0, dh, tl, maxair;  // t7: phid at push start, diamond hits, time since launch, max air
};

static inline Sim sim_load(texture2d<float, access::read> t, uint row) {
    Sim s;
    const float4 a = t.read(uint2(0, row)), b = t.read(uint2(1, row)), c = t.read(uint2(2, row)), d = t.read(uint2(3, row));
    const float4 e = t.read(uint2(4, row)), g = t.read(uint2(5, row)), h = t.read(uint2(6, row)), k = t.read(uint2(7, row));
    s.phi = a.x; s.phid = a.y; s.phase = a.z; s.pt = a.w;
    s.p = b.xyz; s.op = b.w; s.v = c.xyz; s.roll = c.w;
    s.win = d.x; s.spins = d.y; s.dir = d.z; s.num = d.w;
    s.w = e.xyz; s.flags = e.w; s.th = g.x; s.thd = g.y; s.air = g.z; s.slow = g.w;
    s.lk = h.xyz; s.target = h.w; s.ramp0 = k.x; s.dh = k.y; s.tl = k.z; s.maxair = k.w;
    return s;
}
static inline float4 sim_texel(thread const Sim& s, uint i) {
    switch (i) {
        case 0: return float4(s.phi, s.phid, s.phase, s.pt);
        case 1: return float4(s.p, s.op);
        case 2: return float4(s.v, s.roll);
        case 3: return float4(s.win, s.spins, s.dir, s.num);
        case 4: return float4(s.w, s.flags);
        case 5: return float4(s.th, s.thd, s.air, s.slow);
        case 6: return float4(s.lk, s.target);
        default: return float4(s.ramp0, s.dh, s.tl, s.maxair);
    }
}

// Per-spin random numbers: spin index n, channel k.
static inline float spin_rand(uint seed, uint n, uint k) { return argus_rand(uint2(n, k), seed); }
static inline float spin_dir(uint seed, uint n) {       // rotor direction alternates spin to spin
    const float d0 = spin_rand(seed, 0u, 3u) < 0.5f ? 1.0f : -1.0f;
    return (n & 1u) ? -d0 : d0;
}
// The push: 0.25-0.34 rev/s (2.9-4 s a turn, inside Small & Tse's 2-4 s). Capped at 0.34 so that at
// the app's default 30 FPS the 37 frets move at most 0.42 pocket a frame: below the wagon-wheel
// limit (0.5), so neither the frets nor the numerals can seem to run backwards (see the draw).
static inline float spin_target(uint seed, uint n) { return TAU_F * (0.25f + 0.09f * spin_rand(seed, n, 2u)); }
static inline float wrap_pi(float a) { return a - TAU_F * floor((a + PI_F) / TAU_F); }

// Ball spin while it rolls against the wall: no slip at the wall and at the track contact.
static inline float3 rim_spin(float th, float thd) {
    const float v = thd * R_BALL_RIM;   // signed tangential speed
    const float sb = sin(ALPHA_TRACK), cb = cos(ALPHA_TRACK), sg = sin(WALL_LEAN), cg = cos(WALL_LEAN);
    const float det = cg * cb + sg * sb;
    const float2 er = float2(cos(th), sin(th));
    const float wz = -v * (cb + sg) / (R_BALL * det), wr = -v * (cg - sb) / (R_BALL * det);
    return float3(wr * er, wz);
}
static inline void place_on_rim(thread Sim& s) {
    s.p = float3(R_BALL_RIM * cos(s.th), R_BALL_RIM * sin(s.th), Z_BALL_RIM);
    s.v = float3(-sin(s.th), cos(s.th), 0.0f) * (s.thd * R_BALL_RIM);
    s.w = rim_spin(s.th, s.thd);
}
static inline void launch(thread Sim& s, uint seed) {
    const uint n = uint(s.spins + 0.5f);   // index of this spin
    const float speed = TAU_F * (1.05f + 0.40f * spin_rand(seed, n, 0u));    // rad/s: first lap 0.71-0.99 s
    s.th = -0.5f * PI_F + 0.5f * (spin_rand(seed, n, 1u) - 0.5f);           // croupier's side
    // the ball runs against the rotor as it turns now (the rule), whatever the push meant to do
    s.dir = abs(s.phid) > 0.05f ? sign(s.phid) : spin_dir(seed, n);
    s.thd = -s.dir * speed * 0.02f;   // against the rotor; the throw ramps it
    s.ramp0 = -s.dir * speed;
    s.phase = 1.0f; s.pt = 0.0f; s.tl = 0.0f; s.op = 1.0f;   // (air counts the rim's revolutions)
    s.win = -1.0f; s.num = -1.0f; s.air = 0.0f; s.slow = 0.0f; s.dh = 0.0f; s.maxair = 0.0f;
    s.spins = float(n + 1u);
    place_on_rim(s);
}

// One contact: push out, restitution, Coulomb friction on the slip, rolling and pivot loss.
// n points from the surface to the ball centre; u is the surface velocity at the contact.
static inline void resolve(thread Sim& s, float3 n, float pen, float3 u, float e, float mur = MU_ROLL, float piv = K_PIVOT, float mus = MU_SLIDE) {
    s.p += n * pen;
    const float vn = dot(s.v - u, n);
    if (vn >= 0.0f) return;
    const float ee = (-vn > V_REST) ? e : 0.0f;
    const float jn = -(1.0f + ee) * vn;   // normal impulse per unit mass
    s.v += jn * n;
    float3 slip = (s.v - u) + cross(s.w, -R_BALL * n);
    slip -= dot(slip, n) * n;
    const float sl = length(slip);
    if (sl > 1e-6f) {
        const float jt = min(mus * jn, sl / 3.5f);          // 3.5 = 1/m + R^2/I per unit mass
        const float3 sh = slip / sl;
        s.v -= jt * sh;
        s.w += (jt / (0.4f * R_BALL)) * cross(n, sh);
    }
    float3 vt = s.v - u; vt -= dot(vt, n) * n;
    const float vl = length(vt);
    if (vl > 1e-6f) {
        const float3 dv = -(min(mur * jn, vl) / vl) * vt;
        s.v += dv;
        s.w += cross(n, dv) / R_BALL;   // keeps the rolling relation
    }
    s.w -= n * (dot(s.w, n) * min(1.0f, piv * jn));
}

// Closest point on a 2D segment.
static inline float2 seg_closest(float2 p, float2 a, float2 b) {
    const float2 ab = b - a;
    return a + ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0f, 1.0f);
}
// Contact against a profile point q (r, z) in the axisymmetric frame. Returns penetration.
static inline bool profile_contact(thread Sim& s, float2 pr, float2 q, float2 er, float rotor_w, float e, float mur = MU_ROLL, float piv = K_PIVOT) {
    const float2 d = pr - q;
    const float dl = length(d);
    if (dl >= R_BALL || dl < 1e-6f) return false;
    const float2 n2 = d / dl;
    const float3 n = float3(n2.x * er, n2.y);
    const float3 c = float3(q.x * er, q.y);   // contact point, world
    const float3 u = float3(-c.y, c.x, 0.0f) * rotor_w;
    resolve(s, n, R_BALL - dl, u, e, mur, piv);
    return true;
}

// Events of one sub-step (the safety check reads nospin).
struct Ev { bool left_rim, entered_rotor, locked, nospin, escaped, wall; float pen_max; };
static inline Ev ev_none() { Ev e; e.left_rim = e.entered_rotor = e.locked = e.nospin = e.escaped = e.wall = false; e.pen_max = 0.0f; return e; }

// The free ball: phases 2 and 3.
static inline void free_substep(thread Sim& s, float h, thread Ev& ev) {
    s.v.z -= G_ACC * h;
    s.v -= (K_AIR * length(s.v) * h) * s.v;
    s.p += s.v * h;
    bool touch = false, floor_touch = false;
    const float dtouch_prev = s.flags;
    float dtouch = 0.0f;
    float r = length(s.p.xy);
    float2 er = r > 1e-4f ? s.p.xy / r : float2(1.0f, 0.0f);
    float2 pr = float2(r, s.p.z);

    // --- static stator curve (Newton on the closest point of the quadratic) ---
    if (r > R_STATOR_IN - 1.5f) {
        float x = clamp(r - R_STATOR_IN, 0.0f, R_RIM_WALL - R_STATOR_IN);
        for (int it = 0; it < 3; it++) {
            const float zx = stator_curve_z(x + R_STATOR_IN), sx = stator_slope(x + R_STATOR_IN), cx = stator_curv(x + R_STATOR_IN);
            const float g1 = (x + R_STATOR_IN - pr.x) + (zx - pr.y) * sx;
            const float g2 = 1.0f + sx * sx + (zx - pr.y) * cx;
            x = clamp(x - g1 / g2, 0.0f, R_RIM_WALL - R_STATOR_IN);
        }
        const float2 q = float2(R_STATOR_IN + x, stator_curve_z(R_STATOR_IN + x));
        if (profile_contact(s, pr, q, er, 0.0f, E_SURF, q.x >= R_TRACK_IN ? MU_RIM : MU_ROLL)) { touch = true; ev.pen_max = max(ev.pen_max, 0.0f); }
        // the back-track wall and the rim top
        r = length(s.p.xy); er = s.p.xy / max(r, 1e-4f); pr = float2(r, s.p.z);
        if (r > R_RIM_WALL - 1.5f) {
            if (profile_contact(s, pr, seg_closest(pr, float2(R_RIM_WALL, Z_WALL_FOOT), float2(R_WALL_TOP, Z_RIM_TOP)), er, 0.0f, E_SURF, MU_WALL, 0.0f)) { touch = true; ev.wall = true; }
            r = length(s.p.xy); er = s.p.xy / max(r, 1e-4f); pr = float2(r, s.p.z);
            if (profile_contact(s, pr, seg_closest(pr, float2(R_WALL_TOP, Z_RIM_TOP), float2(R_RIM_OUT, Z_RIM_TOP)), er, 0.0f, E_SURF)) touch = true;
        }
    }
    // --- diamonds (static) ---
    r = length(s.p.xy);
    if (abs(r - R_DIAMOND) < DIAMOND_HALF_LEN + R_BALL + 0.2f) {
        const float ang = atan2(s.p.y, s.p.x);
        const int k = int(floor(ang / 0.78539816f + 0.5f + 8.0f)) & 7;
        const float d = diamond_sdf(s.p, k);
        if (d < R_BALL) {
            const float ep = 0.004f;
            float3 n = float3(diamond_sdf(s.p + float3(ep, 0, 0), k) - diamond_sdf(s.p - float3(ep, 0, 0), k),
                              diamond_sdf(s.p + float3(0, ep, 0), k) - diamond_sdf(s.p - float3(0, ep, 0), k),
                              diamond_sdf(s.p + float3(0, 0, ep), k) - diamond_sdf(s.p - float3(0, 0, ep), k));
            n = normalize(n + float3(0, 0, 1e-7f));
            if (dtouch_prev < 0.5f) s.dh += 1.0f;                  // a new strike
            dtouch = 1.0f;
            resolve(s, n, R_BALL - d, float3(0.0f), E_CHROME, MU_ROLL, K_PIVOT, MU_CHROME);
            ev.pen_max = max(ev.pen_max, R_BALL - d);
            touch = true;
        }
    }
    // --- rotor profile (rotating; axisymmetric) ---
    r = length(s.p.xy); er = s.p.xy / max(r, 1e-4f); pr = float2(r, s.p.z);
    if (r < R_ROTOR_OUT + 1.2f) {
        const float wv = s.phid;
        // turret wall, cone
        if (r < R_TURRET + 1.2f) {   // the turret: its drawn profile
            float2 qa = float2(TURRET_PR[0], turret_z(TURRET_PR[0]));
            for (int i = 1; i < 12; i++) {
                const float2 qb = float2(TURRET_PR[i], turret_z(TURRET_PR[i]));
                pr = float2(length(s.p.xy), s.p.z);
                if (profile_contact(s, pr, seg_closest(pr, qa, qb), er, wv, E_CHROME)) touch = true;
                qa = qb;
            }
        }
        if (r < KNOB_AT + KNOB_R + R_BALL + 0.3f && s.p.z > ARM_Z - KNOB_R - R_BALL - 0.3f) {
            // the handle: the nearest arm (a capsule) and its knob, turning with the rotor
            const float qa = 1.5707963f;
            const float aq = atan2(s.p.y, s.p.x) - s.phi - ARM_A0;
            const float fa = ARM_A0 + qa * round(aq / qa) + s.phi;
            const float3 eu = float3(cos(fa), sin(fa), 0.0f);
            const float3 a0 = eu * ARM_R0 + float3(0, 0, ARM_Z), a1 = eu * ARM_R1 + float3(0, 0, ARM_Z);
            const float ta = saturate(dot(s.p - a0, a1 - a0) / dot(a1 - a0, a1 - a0));
            const float3 qs = a0 + (a1 - a0) * ta;
            const float3 kc = eu * KNOB_AT + float3(0, 0, ARM_Z);
            for (int part = 0; part < 2; part++) {
                const float3 c0 = part == 0 ? qs : kc;
                const float rad = part == 0 ? arm_radius(ta) : KNOB_R;
                const float3 d = s.p - c0;
                const float dl = length(d);
                if (dl < rad + R_BALL && dl > 1e-5f) {
                    const float3 n = d / dl, c = c0 + n * rad;
                    resolve(s, n, rad + R_BALL - dl, float3(-c.y, c.x, 0.0f) * wv, E_CHROME);
                    touch = true;
                }
            }
        }
        if (r < R_POCKET_IN + 1.2f) {
            pr = float2(length(s.p.xy), s.p.z);
            if (profile_contact(s, pr, seg_closest(pr, float2(R_CONE_IN, Z_CONE_TOP), float2(R_POCKET_IN, Z_CONE_OUT)), er, wv, E_SURF)) touch = true;
        }
        // pocket floor arc
        pr = float2(length(s.p.xy), s.p.z);
        if (pr.x > R_POCKET_IN - 1.2f && pr.x < R_NUM_IN + 1.2f) {
            const float2 cc = float2(R_DISH_C, Z_POCKET + R_DISH);
            const float2 d = pr - cc;
            const float dl = length(d);
            if (dl > 1e-4f) {
                const float2 q = cc + d * (R_DISH / dl);
                if (q.x >= R_POCKET_IN && q.x <= R_NUM_IN && q.y < cc.y && R_DISH - dl < R_BALL) {
                    const float2 n2 = -d / dl;
                    const float3 n = float3(n2.x * er, n2.y);
                    const float3 c = float3(q.x * er, q.y);
                    resolve(s, n, R_BALL - (R_DISH - dl), float3(-c.y, c.x, 0.0f) * wv, E_SURF);
                    touch = true; floor_touch = true;
                }
            }
        }
        // pocket step, number ring, rotor rim
        pr = float2(length(s.p.xy), s.p.z);
        if (pr.x > R_NUM_IN - 1.2f) {
            if (profile_contact(s, pr, seg_closest(pr, float2(R_NUM_IN, Z_DISH_OUT), float2(R_NUM_IN, Z_NUM_IN)), er, wv, E_SURF)) touch = true;
            pr = float2(length(s.p.xy), s.p.z);
            if (profile_contact(s, pr, seg_closest(pr, float2(R_NUM_IN, Z_NUM_IN), float2(R_NUM_OUT, Z_NUM_OUT)), er, wv, E_SURF)) touch = true;
            pr = float2(length(s.p.xy), s.p.z);
            if (profile_contact(s, pr, seg_closest(pr, float2(R_NUM_OUT, Z_NUM_OUT), float2(R_ROTOR_OUT, Z_ROTOR_RIM)), er, wv, E_CHROME)) touch = true;
        }
        // frets: the two that bound the ball's slot, as rounded boxes in the rotating frame
        r = length(s.p.xy);
        if (r > R_FRET_IN - 1.2f && r < R_FRET_OUT + 1.2f && s.p.z < Z_FRET_TOP + 1.2f) {
            const float a_rot = atan2(s.p.y, s.p.x) - s.phi;
            const float sc = (POCKET_A0 - a_rot) / POCKET_DA;
            const float j = floor(sc + 0.5f);
            for (int side = 0; side < 2; side++) {
                const float fa = POCKET_A0 - (j + (side == 0 ? -0.5f : 0.5f)) * POCKET_DA + s.phi;  // world angle
                const float2 eu = float2(cos(fa), sin(fa)), ew = float2(-eu.y, eu.x);
                const float3 loc = float3(dot(s.p.xy, eu), dot(s.p.xy, ew), s.p.z);
                const float3 cen = float3(0.5f * (R_FRET_IN + R_FRET_OUT), 0.0f, 0.5f * Z_FRET_TOP);
                const float3 hal = float3(0.5f * (R_FRET_OUT - R_FRET_IN), FRET_HALF_W, 0.5f * Z_FRET_TOP) - FRET_HALF_W;
                const float3 rel = loc - cen;
                const float3 q = abs(rel) - hal;
                const float3 qp = max(q, 0.0f);
                const float ql = length(qp);
                const float d = ql + min(max(q.x, max(q.y, q.z)), 0.0f) - FRET_HALF_W;
                if (d < R_BALL) {
                    float3 nl;
                    if (ql > 1e-6f) nl = qp / ql * sign(rel);
                    else nl = (q.y >= q.x && q.y >= q.z) ? float3(0, sign(rel.y), 0) : (q.z >= q.x ? float3(0, 0, sign(rel.z)) : float3(sign(rel.x), 0, 0));
                    const float3 n = float3(nl.x * eu + nl.y * ew, nl.z);
                    const float3 c = s.p - n * R_BALL;
                    resolve(s, n, R_BALL - d, float3(-c.y, c.x, 0.0f) * wv, E_CHROME, MU_ROLL, K_PIVOT, MU_CHROME);
                    ev.pen_max = max(ev.pen_max, R_BALL - d);
                    touch = true;
                }
            }
        }
    }

    // bookkeeping
    s.flags = dtouch;
    s.roll = fmod(s.roll + length(s.w) * h, TAU_F);
    s.air = touch ? 0.0f : s.air + h;
    s.maxair = max(s.maxair, s.air);
    r = length(s.p.xy);
    if (s.phase < 2.5f && r < R_STATOR_IN - 0.5f) { s.phase = 3.0f; s.pt = 0.0f; ev.entered_rotor = true; }
    if (s.phase > 2.5f) {
        const float3 u = float3(-s.p.y, s.p.x, 0.0f) * s.phid;
        const bool slow = floor_touch && length(s.v - u) < SETTLE_V && s.p.z < Z_POCKET + R_BALL + 0.4f
                       && r > R_POCKET_IN && r < R_NUM_IN;
        s.slow = slow ? s.slow + h : 0.0f;
        if (s.slow > SETTLE_T) {
            const float a_rot = wrap_pi(atan2(s.p.y, s.p.x) - s.phi);
            s.lk = float3(r, a_rot, s.p.z);
            s.phase = 4.0f; s.pt = 0.0f;
            s.win = float(slot_at(a_rot));
            s.num = float(EU_SEQ[slot_at(a_rot)]);
            ev.locked = true;
        }
    }
    if (r > R_RIM_OUT - 0.5f || s.p.z < 0.5f) { ev.escaped = true; ev.nospin = true; }
    if (s.tl > T_NOSPIN) ev.nospin = true;
}

static inline void void_spin(thread Sim& s) {             // croupier calls "no spin" (safety)
    const float r = length(s.p.xy);
    s.lk = float3(r, wrap_pi(atan2(s.p.y, s.p.x) - s.phi), s.p.z);
    s.phase = 0.0f; s.pt = 0.0f; s.win = -1.0f; s.num = -1.0f;
    s.th = atan2(s.p.y, s.p.x); s.thd = 0.0f;
}

// The ball leaves the wall. A spin counts only with >= MIN_REVS revolutions of the ball (N.J.A.C.
// 13:69E; Singapore GRA rules [snippet]): a ball that leaves sooner is a "no spin", picked up and
// thrown again (the launch range gives >= 8 revolutions: never seen in the bench).
static inline void leave_rim(thread Sim& s, thread Ev& ev) {
    place_on_rim(s);
    if (s.air < MIN_REVS) { ev.nospin = true; void_spin(s); return; }
    s.phase = 2.0f; s.pt = 0.0f; s.air = 0.0f; ev.left_rim = true;
}

// One sub-step of everything.
static inline void substep(thread Sim& s, float h, uint seed, thread Ev& ev) {
    // rotor
    const bool pushing = s.phase < 0.5f && s.pt >= T_PUSH0 && s.pt < T_PUSH0 + T_PUSH;
    if (pushing) {
        // like a hand: brake to a stop (gripping harder at the end), hold, then two short pushes
        const float tp = s.pt - T_PUSH0;
        const float tg = s.dir * s.target;
        if (tp < 0.8f)       s.phid = s.ramp0 * (1.0f - sq(tp / 0.8f));
        else if (tp < 1.1f)  s.phid = 0.0f;
        else if (tp < 1.35f) s.phid = tg * 0.6f * smoothstep(1.1f, 1.35f, tp);
        else if (tp < 1.6f)  s.phid = tg * 0.6f;
        else                 s.phid = tg * (0.6f + 0.4f * smoothstep(1.6f, 1.85f, tp));
    } else {
        const float dec = (ROTOR_DECEL * sign(s.phid) + ROTOR_DRAG * s.phid) * h;
        s.phid = abs(dec) >= abs(s.phid) ? 0.0f : s.phid - dec;
    }
    s.phi = wrap_pi(s.phi + s.phid * h);
    s.pt += h; s.tl += h;

    if (s.phase < 0.5f) {   // ---- phase 0: ball out
        const float t = s.pt;
        const float3 p_old = s.p;
        // the hand: th / thd hold the ball's world angle and the rotor rate when it was picked up
        const float a_l = s.th + s.thd * (T_GRIP + 0.5f * (T_LIFT - T_GRIP));   // where the lift leaves it
        const float3 L = float3(s.lk.x * cos(a_l), s.lk.x * sin(a_l), s.lk.z + Z_HAND);
        const float3 X = float3(clamp(L.x, -18.0f, 18.0f), -54.0f, Z_HAND);   // over the felt, croupier's side
        if (t < T_LIFT) {   // gripped in the pocket (fading out), then up
            const float tt = max(t - T_GRIP, 0.0f), u = tt / (T_LIFT - T_GRIP);
            const float a = s.th + s.thd * (min(t, T_GRIP) + tt - tt * tt / (2.0f * (T_LIFT - T_GRIP)));
            s.p = float3(s.lk.x * cos(a), s.lk.x * sin(a), s.lk.z + Z_HAND * (1.0f - sq(1.0f - u)));
            s.op = 1.0f - smoothstep(0.0f, T_GRIP, t);
        } else if (t < T_PLACE) {   // carried out and back, in the hand (hidden)
            s.p = mix(L, X, smoothstep(T_LIFT, T_CARRY, t));
            s.op = 0.0f;
        }
        if (t >= T_PUSH0 && t - h < T_PUSH0) {                 // the croupier's push starts
            const uint n = uint(s.spins + 0.5f);
            s.ramp0 = s.phid; s.dir = spin_dir(seed, n); s.target = spin_target(seed, n);
        }
        if (t >= T_PLACE) {   // carried in, lowered onto the track
            const uint n = uint(s.spins + 0.5f);
            const float th = -0.5f * PI_F + 0.5f * (spin_rand(seed, n, 1u) - 0.5f);
            const float3 T0 = float3(R_BALL_RIM * cos(th), R_BALL_RIM * sin(th), Z_BALL_RIM);
            const float3 X2 = float3(T0.x * 0.6f, -54.0f, Z_HAND);
            s.p = mix(X2, float3(T0.xy, Z_HAND), smoothstep(T_PLACE, T_LAUNCH - 3.0f * T_LOWER, t));
            s.p.z = mix(Z_HAND, T0.z, smoothstep(T_LAUNCH - 3.0f * T_LOWER, T_LAUNCH - T_LOWER, t));
            s.op = smoothstep(T_LAUNCH - T_LOWER, T_LAUNCH, t);   // set on the track, then the fingers open
        }
        s.v = (s.p - p_old) / h;
        if (t >= T_LAUNCH) launch(s, seed);
        return;
    }
    if (s.phase < 1.5f) {   // ---- phase 1: riding the wall
        // Pinned against the wall (Small & Tse phase i). Per unit mass: track normal force
        // N_t = g / cos(alpha); wall normal force N_w = ROLL_K v^2 / r - g tan(alpha), where
        // ROLL_K = 1 + I/(m R^2) = 1.4 adds the friction that turns a rolling ball's spin as it
        // circles (a point mass has ROLL_K = 1: Small & Tse eq. 1). With ROLL_K the hand-over to
        // the free rolling ball below is seamless: it leaves the wall at the speed where the free
        // model's wall force also vanishes.
        const float v = abs(s.thd) * R_BALL_RIM;
        const float n_track = G_ACC / cos(ALPHA_TRACK);
        const float n_wall = ROLL_K * v * v / R_BALL_RIM - G_ACC * tan(ALPHA_TRACK);
        if (s.pt < T_THROW) {   // still in the hand: the throw
            const float u = s.pt / T_THROW;
            s.thd = s.ramp0 * max(u * u * (3.0f - 2.0f * u), 0.02f);
            s.th = wrap_pi(s.th + s.thd * h);
            s.air += abs(s.thd) * h / TAU_F;
            place_on_rim(s);
            return;
        }
        if (n_wall <= 0.0f) { leave_rim(s, ev); return; }     // leaves the wall: free from here
        const float dec = MU_RIM * n_track + MU_WALL * n_wall + K_AIR * v * v;
        s.thd = sign(s.thd) * max(v - dec * h, 0.0f) / R_BALL_RIM;
        s.th = wrap_pi(s.th + s.thd * h);
        s.air += abs(s.thd) * h / TAU_F;
        place_on_rim(s);
        s.roll = fmod(s.roll + length(s.w) * h, TAU_F);
        return;
    }
    if (s.phase < 3.5f) {   // ---- phases 2, 3: free ball
        free_substep(s, h, ev);
        if (ev.nospin) void_spin(s);
        return;
    }
    // ---- phase 4: settled, riding with the rotor
    const float a = s.lk.y + s.phi;
    s.p = float3(s.lk.x * cos(a), s.lk.x * sin(a), s.lk.z);
    s.v = float3(-s.p.y, s.p.x, 0.0f) * s.phid;
    s.w = float3(0.0f, 0.0f, s.phid);
    if (s.pt >= T_SETTLED) { s.phase = 0.0f; s.pt = 0.0f; s.th = atan2(s.p.y, s.p.x); s.thd = s.phid; }
}

static inline bool sim_finite(thread const Sim& s) {
    return isfinite(s.phi) && isfinite(s.phid) && all(isfinite(s.p)) && all(isfinite(s.v)) && all(isfinite(s.w))
        && isfinite(s.pt) && isfinite(s.tl);
}

static inline Sim sim_start(uint seed) {
    Sim s;
    s.phi = TAU_F * spin_rand(seed, 0u, 5u) - PI_F;
    s.spins = 0.0f; s.dir = spin_dir(seed, 0u); s.target = spin_target(seed, 0u);
    s.phid = s.dir * s.target; s.ramp0 = s.phid;
    s.roll = 0.0f; s.flags = 0.0f; s.lk = float3(22.4f, 0.0f, 1.85f);
    launch(s, seed);
    Ev ev = ev_none();
    const float h = 1.0f / SUB_HZ;
    for (int i = 0; i < int(T_INIT_AHEAD * SUB_HZ); i++) substep(s, h, seed, ev);   // rim only: cheap
    return s;
}


// ===================================================================== the kernels: state ==
constant float BAKE_TAG = 7321.0f, Z_LIVE = 1e4f;
static float4 bake4(uint2 gid, constant ArgusFrame& f);
// State row 0: texels 0..7 are the simulation (above); 8 and 9 hold the previous tick's
// ball position + rotor angle and ball velocity + the f.time of the tick, so the draw can show
// smooth motion between 30 Hz ticks at 60/120 FPS (it shows the state one tick late, which at
// 30 FPS is exactly the previous tick; no extrapolation, so nothing overshoots).
kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    if (gid.y > 0u) { state.write(bake4(gid, f), gid); return; }
    if (gid.x == 10u) state.write(float4(float(f.width), float(f.height), BAKE_TAG, 0.0f), gid);
    if (gid.x > 9u) return;
    const Sim s = sim_start(f.seed);
    if (gid.x < 8u) state.write(sim_texel(s, gid.x), gid);
    else if (gid.x == 8u) state.write(float4(s.p, s.phi), gid);
    else if (gid.x == 9u) state.write(float4(s.v, f.time), gid);
}

kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    if (gid.y > 0u || gid.x > 9u) { if (f.frame < 3u) next.write(prev.read(gid), gid); return; }
    if (gid.x == 8u) { next.write(float4(prev.read(uint2(1, 0)).xyz, prev.read(uint2(0, 0)).x), gid); return; }
    if (gid.x == 9u) { next.write(float4(prev.read(uint2(2, 0)).xyz, f.time), gid); return; }
    if (gid.x > 9u) return;
    const uint seed = f.seed;
    Sim s = sim_load(prev, 0u);
    const float dt = clamp(f.dt, 0.0f, 0.1f);
    const int n = clamp(int(ceil(dt * SUB_HZ - 1e-3f)), 1, 240);
    const float h = dt / float(n);
    for (int i = 0; i < n && dt > 0.0f; i++) {
        Ev ev = ev_none();
        substep(s, h, seed, ev);
        if (!sim_finite(s)) { s = sim_start(seed ^ uint(s.spins) * 2654435761u); }
    }
    next.write(sim_texel(s, gid.x), gid);
}

// ---- look-only geometry: what the camera sees beyond the collision surfaces ----
// (the apron outside the rim, the rounded lip edge, the stone/lacquer split, the turret's shape)
constant float LIP_ROUND  = 0.3f;         // the lip's top edge is rounded
// The bowl outside the rotor as seen from above: felt, apron, rim top over the lip, stator.
static inline float bowl_z(float r) {
    if (r >= R_APRON_OUT) return 0.0f;
    if (r >= R_RIM_OUT) {   // apron: rounded shoulder to the felt
        const float u = (r - R_RIM_OUT) / (R_APRON_OUT - R_RIM_OUT);
        return Z_RIM_TOP * sqrt(max(1.0f - sq(sq(u)), 0.0f));
    }
    if (r >= R_WALL_TOP) {   // rim top, its lip edge rounded
        const float e = saturate((R_WALL_TOP + LIP_ROUND - r) / LIP_ROUND);
        return Z_RIM_TOP - LIP_ROUND * (1.0f - sqrt(max(1.0f - e * e, 0.0f)));
    }
    if (r >= R_STATOR_IN) return stator_z(r);
    return Z_ROTOR_RIM - 0.25f;   // the seam between stator and rotor (a shallow groove)
}

// ============================================================== the state ==
struct WheelState {
    float  rotor, rotor_vel;     // rotor angle (rad), rate (rad/s)
    float3 ball, ball_vel;       // ball centre (cm, world), velocity (cm/s)
    float  ball_roll, ball_alpha;   // rolling angle (not drawn: it aliases on the rim), opacity
    int    winner;               // pocket index (EU_SEQ order) or -1
};

// The state the draw sees, between two 30 Hz ticks (see the kernels above).
static WheelState wheel_state(texture2d<float> state, float time) {
    const float4 t0 = state.read(uint2(0, 0)), t1 = state.read(uint2(1, 0)), t2 = state.read(uint2(2, 0));
    const float4 t3 = state.read(uint2(3, 0)), t8 = state.read(uint2(8, 0)), t9 = state.read(uint2(9, 0));
    float tau = time - t9.w;
    if (tau < -1.0f) tau += ARGUS_TIME_PERIOD;                 // f.time wrapped between the two
    const float al = saturate(tau * 30.0f);
    WheelState S;
    S.rotor = wrap_pi(t8.w + wrap_pi(t0.x - t8.w) * al);
    S.rotor_vel = t0.y;
    // the ball, in polar coordinates about the axis (it circles: a straight blend would cut in)
    float3 p0 = t8.xyz;
    const float3 p1 = t1.xyz;
    if (distance(p0, p1) > 30.0f) p0 = p1;   // placed on the track, or a reset
    const float a0 = atan2(p0.y, p0.x), a = a0 + wrap_pi(atan2(p1.y, p1.x) - a0) * al;
    const float rr = mix(length(p0.xy), length(p1.xy), al);
    S.ball = float3(rr * cos(a), rr * sin(a), mix(p0.z, p1.z, al));
    S.ball_vel = mix(t9.xyz, t2.xyz, al);
    S.ball_roll = t2.w;
    S.ball_alpha = saturate(t1.w);
    S.winner = int(t3.x);
    return S;
}

// ============================================================== the look ==
// Camera: a pinhole straight above the wheel centre.
constant float H_EYE  = 270.0f;          // camera height above the felt (cm)
constant float FC     = 5.10f;           // focal length in argus_uv units: bowl ~87% of the height
// The hall: a casino ceiling 3 m above the felt, carrying rows of recessed warm-white linear
// slots. Over the table a light box (a lit panel with two slots); elsewhere the hall's own rows,
// dimmer and broken into fixtures. Around the table, D_ROOM away, the hall's walls, other tables
// and their lamps. All of it is fixed in the world: what turns moves under still highlights.
constant float HC      = 300.0f;
constant float PITCH   = 110.0f;         // slot spacing (across)
constant float SLOT_W  = 14.0f;          // slot width
constant float SEG_L   = 205.0f;         // the light box's slots: lit length
constant float HALL_L  = 90.0f;          // the hall's fixtures: lit length along a row ...
constant float ROW_P   = 240.0f;         // ... repeating every ROW_P
constant float2 CAN_C  = float2(-70.0f, 0.0f);     // the light box's centre (slot frame): over the
                                                   //   layout, 94 cm off the wheel's axis (17 deg)
constant float2 CAN_H  = float2(72.0f, 88.0f);     // its half extents: 2 slots, 1.8 m long
constant float3 CEIL_DARK = float3(0.090f, 0.083f, 0.075f);   // the ceiling between fixtures (mean)
constant float  SLOT_FAR = 0.30f;        // the hall's slots, relative to the table's light box
constant float  D_ROOM = 450.0f;         // horizontal distance to the walls and the other tables
constant float  R_COFFER = 215.0f;       // the dark coffer over the table: no hall fixtures within this
                                         //   radius of the wheel's axis (the light box hangs in it)
// The other tables' lamps, seen on the walls: 5 at fixed, uneven azimuths (rad from the -x axis,
// CCW), widths (rad) and strengths (relative to WARM)
constant float LAMP_AZ[5] = { 0.40f, 1.25f, 2.90f, 3.50f, 5.00f };
constant float LAMP_W[5]  = { 0.45f, 0.25f, 0.60f, 0.30f, 0.40f };
constant float LAMP_I[5]  = { 1.00f, 0.55f, 0.80f, 0.40f, 0.70f };
constant float2 CEIL_OFF = float2(23.0f, 7.9f);     // the grid's offset from the wheel axis
constant float  CEIL_ROT = 0.33f;        // the slots' angle to the screen's x axis (rad)
constant float3 BOX_W   = float3(-89.22f, -30.58f, 300.0f);   // the light box's centre, world (from the above)
constant float3 WARM    = float3(1.00f, 0.84f, 0.66f);  // ~3500 K
constant float3 SLOT_L  = WARM * 15.0f; // diffuser 0.55x, core 1.55x
constant float3 CEIL_L  = float3(0.20f, 0.185f, 0.165f);   // the light box's panel, lit by its slots
constant float3 WALL_L  = float3(0.24f, 0.19f, 0.15f);    // the hall's walls and tables, lit
constant float3 CHROME  = float3(0.60f, 0.60f, 0.61f);    // electroplated chromium, F0 ~0.6 neutral
// Materials (linear albedo).
constant float3 FELT    = float3(0.006f, 0.040f, 0.062f);
constant float3 RED_L   = float3(0.42f, 0.018f, 0.012f);
constant float3 BLK_L   = float3(0.008f, 0.008f, 0.009f);
constant float3 GRN_L   = float3(0.010f, 0.17f, 0.050f);
constant float3 CREAM   = float3(0.80f, 0.80f, 0.78f);   // the numerals' white
constant float3 WOOD_A  = float3(0.120f, 0.044f, 0.020f);  // mahogany veneer, light / dark figure
constant float3 WOOD_B  = float3(0.060f, 0.021f, 0.010f);
constant float  BOWL_DK = 0.45f;         // the bowl's rim and apron: the same veneer, stained darker
constant float  LIGHT_AZ = -2.811f;      // azimuth of the light box seen from the axis (BOX_W)
constant float3 STONE   = float3(0.010f, 0.010f, 0.012f);
constant float3 STONE_MEAN = float3(0.0110f, 0.0110f, 0.0125f);   // the track's albedo: near-black
constant float3 LACQ_BK = float3(0.006f, 0.006f, 0.007f);
constant float3 BALL_C  = float3(0.86f, 0.85f, 0.82f);   // PTFE: a high-albedo volume scatterer
constant float3 POCKET_MEAN = (18.0f * RED_L + 18.0f * BLK_L + GRN_L) / 37.0f;
// The camera's exposure time (s): the same at every frame rate (see shade_px).
constant float SHUTTER     = 1.0f / 120.0f;
// Satin finishes. Only chrome is a mirror; every dielectric is a GGX surface of perceptual roughness
// `rough` (alpha = rough^2), dielectric F0 0.04. env() integrates a box lobe; it takes the GGX
// reflected lobe's full width at half maximum: the half-vector's HWHM is 0.64 alpha (small alpha),
// the reflection turns twice as far, so 2.57 alpha (COMPUTED). The tails of GGX are left out (the
// box has none): the satin highlights come out a little more contained than a true GGX glow.
constant float F0_COAT     = 0.04f;      // clear coat, lacquer, stone resin: n ~1.5
constant float ROUGH_BOWL  = 0.32f;      // the bowl's rim and apron: satin lacquered veneer
constant float ROUGH_VEN   = 0.30f;      // the lower stator's veneer
constant float ROUGH_CONE  = 0.28f;      // the cone's veneer
constant float ROUGH_RING  = 0.32f;      // the number ring's lacquer
constant float ROUGH_POCK  = 0.40f;      // the pocket floors' lacquer
constant float ROUGH_STONE = 0.40f;      // the stone track: honed satin
constant float ROUGH_BALL  = 0.22f;      // the PTFE ball: satin
constant float F0_BALL     = 0.03f;      // PTFE, n ~1.35-1.4
constant float LOBE_CHROME = 0.006f;     // chrome: a mirror (its lobe in rad)
static inline float ggx_lobe(float rough) { return 2.57f * rough * rough; }
// The split-sum environment BRDF for a rough dielectric (Karis 2014, "Physically Based Shading on
// Mobile", the analytic fit): Fresnel integrated over the GGX lobe. At normal view it is F0; at
// grazing it reaches ~0.38 for roughness 0.3 instead of Schlick's 1.0, so a satin edge seen
// edge-on is not a wet mirror band.
static inline float env_brdf(float F0, float rough, float ndv) {
    const float4 rr = rough * float4(-1.0f, -0.0275f, -0.572f, 0.022f) + float4(1.0f, 0.0425f, 1.04f, -0.04f);
    const float a004 = min(rr.x * rr.x, exp2(-9.28f * ndv)) * rr.x + rr.y;
    const float2 AB = float2(-1.04f, 1.04f) * a004 + rr.zw;
    return F0 * AB.x + AB.y;
}

// Box-filtered coverage of a periodic train of lit intervals (width `on`, period `per`,
// centred at (n + 0.5) * per), averaged over [x - w/2, x + w/2]: exact for any w.
static inline float train_F(float x, float per, float on) {
    const float q = floor(x / per);
    return q * on + clamp(x - q * per - 0.5f * (per - on), 0.0f, on);
}
static inline float train_cov(float x, float w, float per, float on) {
    return (train_F(x + 0.5f * w, per, on) - train_F(x - 0.5f * w, per, on)) / w;
}
static inline float box_cov(float x, float w, float h) {     // [-h, h] over [x - w/2, x + w/2]
    return (clamp(x + 0.5f * w, -h, h) - clamp(x - 0.5f * w, -h, h)) / w;
}
static inline float2 ceil_coords(float2 c) {      // world xy on the ceiling -> slot frame
    const float cs = cos(CEIL_ROT), sn = sin(CEIL_ROT);
    c += CEIL_OFF;
    return float2(cs * c.x + sn * c.y, -sn * c.x + cs * c.y);
}
// Mean luminance of the lit ceiling (for diffuse light).
constant float3 CEIL_AVG = WARM * 15.0f * (0.55f * 14.0f + 0.45f * 14.0f) / 110.0f * (205.0f / 240.0f) + float3(0.20f, 0.185f, 0.165f);
constant float3 DL_UP = CEIL_AVG * 0.62f;           // diffuse light on a surface facing up

static inline float3 schlick3(float3 F0, float c) {
    const float m = pow(1.0f - saturate(c), 5.0f);
    return F0 + (1.0f - F0) * m;
}
static inline float schlick1(float F0, float c) {
    return F0 + (1.0f - F0) * pow(1.0f - saturate(c), 5.0f);
}
// Diffuse irradiance from the ceiling (radiance units: albedo * this = outgoing radiance).
static inline float3 diffuse_light(float3 n) {
    return DL_UP * pow(saturate(0.5f + 0.5f * n.z), 1.6f);
}
// The revolution profile the camera sees (frets and diamonds are added on top).
static inline float scene_rev(float r) {
    if (r >= R_ROTOR_OUT) return bowl_z(r);
    if (r < R_TURRET) return turret_z(r);
    return rotor_profile_z(r);   // frets are drawn on top
}

// The hall where a ray meets its walls (height hw above the felt): other tables' lit tops, people
// and machines, lit walls, and the long lamps over 7 other tables. Box-filtered over the lobe
// in height and azimuth, so a curved mirror sees soft bands, never dots.
static float3 room(float3 P, float3 R, float blur) {
    const float h = max(length(R.xy), 1e-3f);
    const float tz = R.z / h;
    const float hw = P.z + D_ROOM * tz;
    const float sec2 = 1.0f + tz * tz;
    const float wh = blur * D_ROOM * sec2 + 1.0f;               // the lobe's footprint in height (cm)
    const float waz = blur * sqrt(sec2) + 0.004f;               // ... and in azimuth (rad)
    const float az = atan2(R.y, R.x) + PI_F;   // 0..2 pi
    const float var = 0.22f * exp(-3.0f * blur) * sin(3.0f * az + 0.7f) * sin(5.0f * az + 1.3f);
    float3 c = WALL_L * (0.75f + var) * (0.45f + 0.55f * box_cov(hw - 235.0f, wh, 65.0f));
    c += float3(0.05f, 0.10f, 0.11f) * box_cov(hw - 10.0f, wh, 14.0f);          // other tables' felt
    const float band = box_cov(hw - 222.0f, wh, 22.0f);
    float lamp = 0.0f;
    if (band > 0.0f)
        for (int k = 0; k < 5; k++)
            lamp += LAMP_I[k] * box_cov(wrap_pi(az - LAMP_AZ[k]), waz, 0.5f * LAMP_W[k]);
    return c + WARM * (0.8f * lamp * band);
}
// The hall's fixtures along the slot rows: one per ROW_P cell with its own length (45-150 cm),
// offset and strength, a quarter off (unequal streaks, not an even dash). Box-filtered exactly
// over the footprint w (two cells cover it); from a quarter cell on it fades to its mean.
static inline float hall_fixtures(float2 C, float w) {
    const float xs = C.x - CAN_C.x + 0.5f * ROW_P;
    const int row = int(floor(C.y / PITCH));
    const float fade = smoothstep(0.25f * ROW_P, 0.6f * ROW_P, w);
    if (fade >= 1.0f) return 0.221f;
    const int n0 = int(floor((xs - 0.5f * w) / ROW_P));     // w < 0.6 ROW_P: two cells cover it
    float cov = 0.0f;
    for (int i = 0; i <= 1; i++) {
        const int n = n0 + i;
        const float h0 = argus_rand(uint2(uint(n), uint(row)), 71u), h1 = argus_rand(uint2(uint(n), uint(row)), 72u);
        const float on = h0 < 0.25f ? 0.0f : 0.45f + 0.55f * (h0 - 0.25f) / 0.75f;
        const float len = 45.0f + 105.0f * h1;
        const float cx = (float(n) + 0.5f) * ROW_P + (h1 - 0.5f) * (ROW_P - len - 10.0f);
        cov += on * box_cov(xs - cx, w, 0.5f * len);
    }
    return mix(cov, 0.221f, fade);       // the mean: 0.75 x 0.725 x 97.5 / 240
}
// The ceiling along R (R.z > 0): the light box, and the hall's dimmer rows of fixtures.
static float3 ceiling(float3 P, float3 R, float blur) {
    const float rz = max(R.z, 0.02f);
    const float dist = (HC - P.z) / rz;
    const float2 C = ceil_coords(P.xy + R.xy * dist);
    const float w = max(blur * dist / rz, 0.4f);
    const float2 Cc = C - CAN_C;
    const float canopy = box_cov(Cc.x, w, CAN_H.x) * box_cov(Cc.y, w, CAN_H.y);
    const float inner = box_cov(Cc.x, w, CAN_H.x - 12.0f) * box_cov(Cc.y, w, CAN_H.y - 12.0f);
    // a slot: a bright core in a softer diffuser, in a dark trim
    const float core = train_cov(C.y, w, PITCH, 0.45f * SLOT_W);
    const float diff = train_cov(C.y, w, PITCH, SLOT_W);
    const float trim = train_cov(C.y, w, PITCH, SLOT_W + 5.0f);
    const float rc = length(P.xy + R.xy * dist);                 // from the wheel's axis, on the ceiling
    const float hall = smoothstep(R_COFFER - 25.0f - w, R_COFFER + 25.0f + w, rc);
    const float seg = hall * (1.0f - canopy) > 0.0f ? hall_fixtures(C, w) * hall : 0.0f;
    // the ceiling's paint: a low-frequency unevenness of the light (faded over the footprint) and
    // the coffer's lighter trim ring
    const float3 box = CEIL_L * (1.0f - 0.8f * (trim - diff) * inner);
    float3 base = box;
    if (canopy < 1.0f) {
        const float3 paint = CEIL_DARK * (1.0f + 0.3f * argus_noise(C * 0.006f + 3.0f) / (1.0f + w / 120.0f))
                           + float3(0.10f, 0.09f, 0.08f) * box_cov(rc - R_COFFER, w, 6.0f);
        base = mix(paint, box, canopy);
    }
    return base + SLOT_L * (0.55f * diff + core) * (inner + SLOT_FAR * seg * (1.0f - canopy));
}
// What the wheel and the table look like along a downward ray (the wheel's own image in the
// chrome): the ray meets the profile (two fixed-point steps), and the ring colours there are
// box-filtered over the lobe's footprint; the pockets by the rotor's angle (and its sweep).
static inline float ring_w(float r, float f, float lo, float hi) {
    return (clamp(r + 0.5f * f, lo, hi) - clamp(r - 0.5f * f, lo, hi)) / f;
}
static float3 wheel_image(float3 P, float3 R, float blur, float rotor, float dphi) {
    const float dz = max(-R.z, 0.03f);
    // march to the first point under the profile (6 steps to the felt plane), then bisect
    const float tm = P.z / dz + 0.5f;
    float ta = 0.0f, tb = tm;
    for (int i = 1; i <= 6; i++) {
        const float ti = tm * float(i) / 6.0f;
        if (P.z - dz * ti <= scene_rev(length(P.xy + R.xy * ti))) { tb = ti; break; }
        ta = ti;
    }
    for (int j = 0; j < 4; j++) {
        const float tc = 0.5f * (ta + tb);
        if (P.z - dz * tc <= scene_rev(length(P.xy + R.xy * tc))) tb = tc; else ta = tc;
    }
    const float t = max(0.5f * (ta + tb), 0.3f);
    const float2 H = P.xy + R.xy * t;
    const float rh = length(H);
    const float f = blur * t / dz + 0.15f;                 // the lobe's footprint there (cm)
    float3 pc = POCKET_MEAN;
    if (rh > R_POCKET_IN - f && rh < R_NUM_OUT + f) {
        const float s = (POCKET_A0 - (atan2(H.y, H.x) - rotor)) / POCKET_DA + 0.5f;
        const float wq = f / max(rh * POCKET_DA, 0.5f) + dphi / POCKET_DA;
        if (wq < 0.95f) {
            const float k0f = floor(s - 0.5f * wq);
            const float wt1 = saturate((s + 0.5f * wq - (k0f + 1.0f)) / wq);
            const int n0 = int(EU_SEQ[((int(k0f) % 37) + 37) % 37]), n1 = int(EU_SEQ[((int(k0f) + 38) % 37 + 37) % 37]);
            const float3 c0 = n0 == 0 ? GRN_L : (is_red(n0) ? RED_L : BLK_L);
            const float3 c1 = n1 == 0 ? GRN_L : (is_red(n1) ? RED_L : BLK_L);
            pc = mix(mix(c0, c1, wt1), POCKET_MEAN, smoothstep(0.5f, 0.95f, wq));
        }
    }
    float3 c = float3(0.30f) * ring_w(rh, f, -50.0f, R_TURRET);
    c += (WOOD_A * DL_UP * 0.9f + 0.02f) * ring_w(rh, f, R_TURRET, R_POCKET_IN);
    c += pc * (0.30f * DL_UP) * ring_w(rh, f, R_POCKET_IN, R_NUM_IN);
    c += ((pc * 0.85f + CREAM * 0.15f) * DL_UP * 0.95f + 0.02f) * ring_w(rh, f, R_NUM_IN, R_NUM_OUT);
    c += float3(0.35f) * ring_w(rh, f, R_NUM_OUT, R_STATOR_IN + 0.3f);
    c += (LACQ_BK * DL_UP + 0.03f) * ring_w(rh, f, R_STATOR_IN + 0.3f, 34.0f);
    c += (STONE * DL_UP + 0.035f) * ring_w(rh, f, 34.0f, R_WALL_TOP);
    c += (BOWL_DK * WOOD_A * DL_UP + 0.04f) * ring_w(rh, f, R_WALL_TOP, R_APRON_OUT);
    c += FELT * DL_UP * ring_w(rh, f, R_APRON_OUT, 1e4f);
    return c;
}

// Inside the bowl, low reflected rays meet the bowl itself: the stator's inner edge and the
// bowl rim stand above the rotor. Returns the tangent of the elevation the bowl hides, along
// the horizontal direction of R from P (-1 when P is outside the bowl).
static inline float circle_exit(float2 p, float2 d, float rad) {   // distance along d to |p| = rad
    const float b = dot(p, d), c = dot(p, p) - rad * rad;
    return -b + sqrt(max(b * b - c, 0.0f));
}
static inline float bowl_horizon(float3 P, float3 R) {
    const float rp = length(P.xy);
    if (rp >= R_RIM_OUT) return -1.0f;
    const float h = length(R.xy);
    if (h < 1e-4f) return -1.0f;
    const float2 d = R.xy / h;
    float tn = (Z_RIM_TOP - P.z) / max(circle_exit(P.xy, d, R_RIM_OUT), 0.05f);
    if (rp < R_STATOR_IN)
        tn = max(tn, (stator_z(R_STATOR_IN + 0.01f) - P.z) / max(circle_exit(P.xy, d, R_STATOR_IN), 0.05f));
    return tn;
}

// On the rotor, rays that run inward low meet the cone and the turret before the hall: the
// pocket floors' dish looks across the cone (the number ring's reflections clear it). Returns the tangent of the
// elevation the rotor's own profile hides along R's horizontal direction (-1e3 when none): the
// profile sampled at 5 points toward the axis (its closest approach).
static inline float cone_horizon(float3 P, float3 R) {
    const float h = length(R.xy);
    if (h < 1e-4f) return -1e3f;
    const float2 d = R.xy / h;
    const float sc = -dot(P.xy, d);                  // distance to the closest approach to the axis
    if (sc <= 0.5f) return -1e3f;   // heading outward: nothing of the rotor rises there
    float tn = -1e3f;
    for (int i = 1; i <= 5; i++) {
        const float s = sc * float(i) / 5.0f;
        tn = max(tn, (rotor_profile_z(length(P.xy + d * s)) - P.z) / s);
    }
    return tn;
}
constant float3 CONE_SEEN = WOOD_A * DL_UP * 0.9f + 0.02f;   // the lit cone, as wheel_image shows it

// What the bowl's inside shows to a ray from P that its rim hides (P inside the bowl): where the
// ray meets the stator (a march and a bisection along it), the lit veneer, the polished stone (its
// gloss mirrors the hall) or the wall under the lip, box-filtered over the lobe's footprint there.
static float3 bowl_far(float3 P, float3 R, float bz) {
    const float h = max(length(R.xy), 1e-3f);
    const float2 d = R.xy / h;
    const float tz = R.z / h;
    const float rp = length(P.xy);
    const float sa = rp < R_STATOR_IN ? circle_exit(P.xy, d, R_STATOR_IN) : 0.0f;
    const float sb = circle_exit(P.xy, d, R_RIM_WALL);
    float a = sa, b = sb, rh = R_RIM_WALL;
    bool hit = false;
    for (int i = 1; i <= 4 && !hit; i++) {
        const float s = mix(sa, sb, 0.25f * float(i));
        if (P.z + tz * s <= stator_z(max(length(P.xy + d * s), R_STATOR_IN))) { b = s; hit = true; } else a = s;
    }
    float s = sb;
    if (hit) {
        for (int j = 0; j < 4; j++) {
            const float m = 0.5f * (a + b);
            if (P.z + tz * m <= stator_z(max(length(P.xy + d * m), R_STATOR_IN))) b = m; else a = m;
        }
        s = 0.5f * (a + b);
        rh = length(P.xy + d * s);
    }
    const float f = bz * s * sqrt(1.0f + tz * tz) / max(abs(tz) + 0.3f, 0.3f) + 0.2f;   // footprint (cm)
    const float3 veneer = BOWL_DK * WOOD_A * DL_UP * 0.85f + 0.025f;
    const float3 stone  = STONE * DL_UP + float3(0.075f, 0.068f, 0.060f);
    const float3 wall   = BOWL_DK * WOOD_A * DL_UP * 0.4f + 0.02f;
    return veneer * ring_w(rh, f, -1e3f, R_TRACK_IN) + stone * ring_w(rh, f, R_TRACK_IN, R_WALL_TOP - 0.2f)
         + wall * ring_w(rh, f, R_WALL_TOP - 0.2f, 1e3f);
}

// What a surface at P sees along R (unit); `blur` = angular spread (rad) of the lobe, turned
// into box footprints on the ceiling, the walls and the wheel: every light is integrated over it
// exactly, so nothing aliases however small or curved the mirror. rotor / dphi: the rotor's
// angle and its sweep over the shutter (for the wheel's own image).
static float3 env(float3 P, float3 R, float blur, float rotor, float dphi) {
    const float bz = min(blur, 0.8f);
    const float h = max(length(R.xy), 1e-3f);
    const float el = atan2(R.z, h);
    // the hall's walls, and the ceiling above their top edge
    const float el_c = atan2(HC - P.z, D_ROOM);
    const float cf = smoothstep(el_c - 0.02f - 0.5f * bz, el_c + 0.02f + 0.5f * bz, el);
    float3 Lc = cf < 1.0f ? room(P, R, bz) : float3(0.0f);
    if (cf > 0.0f) Lc = mix(Lc, ceiling(P, R, blur), cf);
    // below the horizon: the table, or (inside the bowl) the wheel itself
    const float lo = smoothstep(0.02f + bz, -0.02f - bz, R.z);
    if (lo > 0.0f) Lc = mix(Lc, wheel_image(P, R, max(bz, 0.01f), rotor, dphi), lo);
    // the bowl's own wall hides what lies below its rim: the far bowl (veneer, stone, wall)
    const float tn = bowl_horizon(P, R);
    if (tn > -0.5f) {
        const float vis = smoothstep(tn - 0.08f - 1.5f * bz, tn + 0.08f + 1.5f * bz, R.z / h);
        if (vis < 1.0f) Lc = mix(bowl_far(P, R, bz), Lc, vis);
    }
    // ... and on the rotor, the cone and the turret hide what lies beyond them
    const float rp2 = dot(P.xy, P.xy);
    if (rp2 < sq(R_NUM_IN) && rp2 > sq(R_POCKET_IN - 0.5f) && R.z < 0.6f * length(R.xy) + bz) {
        const float tc = cone_horizon(P, R);
        if (tc > -1e2f) {
            const float h = max(length(R.xy), 1e-3f);
            const float vis = smoothstep(tc - 0.08f - 1.5f * bz, tc + 0.08f + 1.5f * bz, R.z / h);
            if (vis < 1.0f) Lc = mix(CONE_SEEN, Lc, vis);
        }
    }
    return Lc;
}

// The ball's centre at time t (s) from now, along its path in polar coordinates about the axis.
static inline float3 ball_at(float3 B, float3 v, float t, bool polar, float rB, float thB, float vr, float om) {
    if (!polar) return B + v * t;
    const float rr = rB + vr * t, a = thB + om * t;
    return float3(rr * cos(a), rr * sin(a), B.z + v.z * t);
}
// The PTFE ball's diffuse light (DL_UP scale): ~60 % light box (near-Lambert, slight wrap), ~40 %
// sky, plus the bounce from what lies under it (a red pocket tints its underside pink).
static inline float3 ball_diffuse(float3 nb, float3 B, float3 under) {
    const float3 L = normalize(BOX_W - B);
    const float k = saturate((dot(nb, L) + 0.08f) / 1.08f) / 0.95f;    // 1 for a face turned up
    const float sky = pow(saturate(0.5f + 0.5f * nb.z), 1.6f);
    return BALL_C * ((0.6f * k + 0.4f * sky) * DL_UP + under * (0.5f - 0.5f * nb.z));
}

// ---- numerals: a condensed sans built from strokes and arcs (unit: digit height) ----
static inline float sd_seg(float2 p, float2 a, float2 b) {
    const float2 pa = p - a, ba = b - a;
    return length(pa - ba * saturate(dot(pa, ba) / dot(ba, ba)));
}
// arc of radius r about c from angle a0 CCW to a1 (degrees, a0 < a1, span < 360)
static inline float sd_arc(float2 p, float2 c, float r, float a0, float a1) {
    const float2 q = p - c;
    const float k = 0.0174533f;
    float ang = atan2(q.y, q.x) / k;
    float rel = ang - a0; rel -= 360.0f * floor(rel / 360.0f);
    if (rel <= a1 - a0) return abs(length(q) - r);
    const float2 e0 = c + r * float2(cos(a0 * k), sin(a0 * k));
    const float2 e1 = c + r * float2(cos(a1 * k), sin(a1 * k));
    return min(length(p - e0), length(p - e1));
}
static inline float sd_loop(float2 p, float y0, float y1, float r) {   // vertical stadium outline
    return abs(length(float2(p.x, p.y - clamp(p.y, y0, y1))) - r);
}
// A bold, regular-width grotesque (Helvetica-Bold-like proportions), built from one stroke
// width so every glyph has the same weight. Skeleton: half height GH, half width GW; bowls
// centred at YU (upper) / YL (lower); the 3, 5, 8 waists at Y3 / Y5 / Y8.
constant float GW = 0.22f, GH = 0.43f;
constant float YU = GH - GW, YL = -(GH - GW);
constant float R3 = 0.19f, Y3M = GH - 2.0f * R3, Y3 = Y3M - GW;     // 3: smaller upper bowl
constant float Y5 = YL + 0.14f;   // 5 and 6/9: the lower bowl's top centre
constant float R8 = 0.175f, Y8 = GH - 2.0f * R8 - GW;                // 8: upper loop, lower loop's top centre
static float sd_digit(int d, float2 p) {
    switch (d) {
    case 0: return sd_loop(p, YL, YU, GW);
    case 1: return min(sd_seg(p, float2(0.05f, -GH), float2(0.05f, GH)),
                       sd_seg(p, float2(0.05f, GH), float2(-0.15f, GH - 0.17f)));
    case 2: return min(min(sd_arc(p, float2(0.0f, YU), GW, -40.0f, 180.0f),
                           sd_seg(p, float2(GW * 0.766f, YU - GW * 0.643f), float2(-GW, -GH))),
                       sd_seg(p, float2(-GW, -GH), float2(GW + 0.01f, -GH)));
    case 3: return min(min(sd_arc(p, float2(0.0f, GH - R3), R3, -90.0f, 160.0f),
                           sd_arc(p, float2(0.0f, YL), GW, 200.0f, 360.0f)),
                       min(min(sd_seg(p, float2(GW, YL), float2(GW, Y3)),
                               sd_arc(p, float2(0.0f, Y3), GW, 0.0f, 90.0f)),
                           sd_seg(p, float2(0.0f, Y3M), float2(-0.07f, Y3M))));
    case 4: return min(min(sd_seg(p, float2(0.10f, -GH), float2(0.10f, GH)),
                           sd_seg(p, float2(0.10f, GH), float2(-GW, -0.13f))),
                       sd_seg(p, float2(-GW, -0.13f), float2(GW + 0.02f, -0.13f)));
    case 5: return min(min(sd_seg(p, float2(GW, GH), float2(-0.18f, GH)),
                           sd_seg(p, float2(-0.18f, GH), float2(-0.19f, Y5 + GW * 0.5f))),
                       min(min(sd_arc(p, float2(0.0f, Y5), GW, 0.0f, 150.0f),
                               sd_seg(p, float2(GW, Y5), float2(GW, YL))),
                           sd_arc(p, float2(0.0f, YL), GW, 200.0f, 360.0f)));
    case 6: return min(min(sd_loop(p, YL, Y5, GW),
                           sd_seg(p, float2(-GW, Y5), float2(-GW, YU))),
                       sd_arc(p, float2(0.0f, YU), GW, 25.0f, 180.0f));
    case 7: return min(sd_seg(p, float2(-GW, GH), float2(GW, GH)),
                       sd_seg(p, float2(GW, GH), float2(-0.05f, -GH)));
    case 8: return min(abs(length(p - float2(0.0f, GH - R8)) - R8), sd_loop(p, YL, Y8, GW));
    default: {
        const float2 q = -p;
        return min(min(sd_loop(q, YL, Y5, GW),
                       sd_seg(q, float2(-GW, Y5), float2(-GW, YU))),
                   sd_arc(q, float2(0.0f, YU), GW, 25.0f, 180.0f));
    }
    }
}
constant float DIGIT_H = 2.1f;           // cm (cap height ~2.2 cm with the stroke)
constant float DIGIT_SW = 0.085f;        // stroke half-width (digit heights): bold
constant float R_TEXT = 25.65f;
// Coverage of the numeral of pocket k at glyph-plane point (x tangential cm, y radial cm).
static float numeral_cov(int k, float2 q, float aa) {
    const int n = int(EU_SEQ[k]);
    const float2 p = q / DIGIT_H;
    float d;
    if (n < 10) d = sd_digit(n, p);
    else {
        const float sp = 0.36f;
        d = min(sd_digit(n / 10, p + float2(sp, 0.0f)), sd_digit(n % 10, p - float2(sp, 0.0f)));
    }
    return smoothstep(DIGIT_SW + aa, DIGIT_SW - aa, d);
}
static inline float3 pocket_colour(int k) {
    const int n = int(EU_SEQ[k]);
    return n == 0 ? GRN_L : (is_red(n) ? RED_L : BLK_L);
}
static inline int wrap37(int k) { return ((k % 37) + 37) % 37; }

// Periodic box-filter coverage of intervals [m - hw, m + hw] (integers m) over [x0, x1].
static inline float tick_F(float x, float hw) {
    const float y = x + hw;
    return floor(y) * 2.0f * hw + min(y - floor(y), 2.0f * hw);
}
static inline float tick_cov(float x, float w, float hw) {
    return (tick_F(x + 0.5f * w, hw) - tick_F(x - 0.5f * w, hw)) / w;
}

// Ambient occlusion of a sphere (Quilez), normal n at P.
static inline float sphere_ao(float3 P, float3 n, float3 c, float rad) {
    const float3 d = c - P;
    const float l = length(d);
    return 1.0f - saturate(dot(n, d / l) * sq(rad / l)) * 0.9f;
}

// The key light: the light box over the table's layout, seen from p.
static inline float3 box_dir(float3 p) { return normalize(BOX_W - p); }
// How much of the light box a sphere (centre c, radius rad) hides from point P: the sphere's
// silhouette projected from P onto the ceiling (as a square of equal area) overlapped with the
// box's lit rectangle. Exact enough for a soft shadow that separates from the ball with height:
// about 0.3 cm per cm of height, along the box's direction.
static inline float box_block(float3 P, float3 c, float rad) {
    const float hz = c.z - P.z;
    if (hz <= 0.05f) return 0.0f;
    const float k = (HC - P.z) / hz;
    const float2 X = ceil_coords(P.xy + (c.xy - P.xy) * k) - CAN_C;
    const float s = 0.886f * rad * k;   // half side: sqrt(pi)/2 of the radius
    const float2 hb = CAN_H - 12.0f;
    const float ox = max(min(X.x + s, hb.x) - max(X.x - s, -hb.x), 0.0f);
    const float oy = max(min(X.y + s, hb.y) - max(X.y - s, -hb.y), 0.0f);
    return ox * oy / (4.0f * hb.x * hb.y);
}

// The felt's sheen (radiance) seen along V at P: Charlie D (sheen roughness FELT_SHEEN_A) x the
// visibility 1 / (4 (NL + NV - NL NV)) x irradiance, for the light box (~60 % of the light on the
// table, as a single direction) and the hall's walls (radiance ~WALL_L over elevations 0..34 deg:
// irradiance pi L sin^2(34 deg)).
constant float  FELT_SHEEN_A = 0.5f;          // sheen roughness (chosen): D = 4 sin^2 / (2 pi), no pow
constant float3 FELT_SHEEN_C = FELT * 5.0f;          // the fibres' sheen colour (chosen)
static inline float charlie(float3 n, float3 L, float3 V) {
    const float3 H = normalize(L + V);
    const float c = saturate(dot(n, H));
    const float D = (2.0f + 1.0f / FELT_SHEEN_A) * (1.0f - c * c) * (0.5f / PI_F);   // sin^(1/a), a = 0.5
    const float nl = saturate(dot(n, L)), nv = saturate(dot(n, V));
    return D / (4.0f * (nl + nv - nl * nv) + 1e-4f);
}
static inline float3 felt_sheen(float3 P, float3 V) {
    const float3 n = float3(0.0f, 0.0f, 1.0f);
    const float3 Lb = box_dir(P);
    float3 s = charlie(n, Lb, V) * (0.6f * PI_F * DL_UP);
    const float2 vt = length(V.xy) > 1e-4f ? normalize(V.xy) : float2(1.0f, 0.0f);
    const float ce = 0.956f, se = 0.292f;                 // 17 deg elevation
    const float wall = 0.5f * (charlie(n, float3(vt * ce, se), V) + charlie(n, float3(-vt * ce, se), V));
    s += wall * (PI_F * 0.31f) * WALL_L * 0.75f;
    return FELT_SHEEN_C * s;
}

// The bowl's shadow on the felt: the share of the light box (its near-to-far elevations, +-80 cm)
// that the bowl (5 heights along the ray to the box) leaves visible from q: soft, directional.
static inline float bowl_box_vis(float2 q) {
    const float2 tb = BOX_W.xy - q;
    const float D = length(tb);
    const float2 d = tb / D;
    const float b = dot(q, d), c = dot(q, q) - R_APRON_OUT * R_APRON_OUT;
    if (b >= 0.0f || b * b - c <= 0.0f) return 1.0f;           // the ray to the box misses the bowl
    const float s0 = -b - sqrt(b * b - c);   // where it enters the bowl's footprint
    const float tlo = HC / (D + 80.0f), thi = HC / max(D - 80.0f, 25.0f);
    if (Z_RIM_TOP / max(s0, 1e-3f) <= tlo) return 1.0f;           // too far out to hide any of it
    const float c1 = dot(q, q) - R_RIM_OUT * R_RIM_OUT;
    const float s1 = b * b - c1 > 0.0f ? -b - sqrt(b * b - c1) + 0.3f : -b;   // the rim top, or the closest approach
    float tn = 0.0f;
    for (int i = 1; i <= 5; i++) {
        const float s = mix(s0, s1, 0.2f * float(i));
        tn = max(tn, bowl_z(length(q + d * s)) / max(s, 1e-3f));
    }
    return saturate((thi - tn) / (thi - tlo));
}

// The material of the revolution surface at radius r (frets, numerals and veneer included).
struct Mat {
    float3 alb;      // diffuse albedo (linear)
    float  f0;       // dielectric reflectance at normal incidence
    float  met;      // 0 dielectric .. 1 chrome
    float  gloss;    // reflection lobe (rad): ggx_lobe(rough) for dielectrics, LOBE_CHROME for chrome
    float  rough;    // GGX roughness of the dielectric part (for its Fresnel over the lobe)
    float  ao;
};
static Mat mat_at(float r, float2 Pxy, float ang_w, float a_rot, float pix, float dphi) {
    Mat m;
    m.alb = float3(0.0f); m.f0 = F0_COAT; m.met = 0.0f; m.gloss = LOBE_CHROME; m.rough = 0.3f; m.ao = 1.0f;
    if (r >= R_APRON_OUT) {
        // ------------------------------------------------------------ felt --
        const float2 q = Pxy;
        const float mott = argus_fbm(q * 0.09f, 2);
        const float fib = argus_noise(q * float2(2.2f, 7.5f)) * 0.5f + argus_noise(q * float2(6.0f, 3.1f) + 17.0f) * 0.5f;
        // the nap: fine fibres (faded to their mean below ~3 px, so they never shimmer) and a
        // faint brushed direction
        const float nap = argus_noise(q * float2(0.6f, 1.8f) + 31.0f);
        m.alb = FELT * (1.0f + 0.08f * mott + 0.10f * fib * saturate(0.35f / pix - 0.6f) + 0.015f * nap);
        // the table sits in a pool of light: the light box (off-axis, lower left) and the slots
        const float2 Cf = ceil_coords(q);
        const float yq = Cf.y / PITCH - 0.5f;
        const float d0 = (yq - round(yq)) * PITCH;
        const float2 db = q - BOX_W.xy;
        m.alb *= (0.45f + 0.55f * exp(-dot(db, db) / (2.0f * 95.0f * 95.0f)))
               * (0.92f + 0.08f * (sq(HC * HC / (HC * HC + d0 * d0)) + sq(HC * HC / (HC * HC + sq(PITCH - abs(d0))))) * 0.6f) * 1.25f;
        m.f0 = 0.0f;
        // the hall's light (~40 %) is hidden near the bowl's foot all round; the light box's (~60 %)
        // by the bowl's cast shadow, away from the box
        m.ao = (1.0f - 0.45f * exp(-(r - R_APRON_OUT) / 1.0f) - 0.15f * exp(-(r - R_APRON_OUT) / 5.0f))
             * (1.0f - 0.6f * (1.0f - bowl_box_vis(q)));
    } else if (r >= R_WALL_TOP) {
        // ----------------------------------- bowl rim and apron: dark veneer --
        const float g = argus_fbm(float2(ang_w * 60.0f, r * 0.35f), 3);
        const float fig = 0.5f + 0.5f * sin(ang_w * 140.0f + 6.0f * g + r * 0.2f);
        m.alb = BOWL_DK * mix(WOOD_B, WOOD_A, saturate(0.35f + 0.5f * fig * (0.6f + 0.4f * g)));
        m.rough = ROUGH_BOWL; m.gloss = ggx_lobe(ROUGH_BOWL);
    } else if (r >= R_TRACK_IN) {
        // ------------------- honed engineered stone ball track (mineral-filled resin) --
        // a dense, fine, low-contrast grain (about +-5 % around the mean), faded to its mean
        // below ~2 px; a honed-to-polished finish: a faint, broad sheen of the light box
        const float2 q = Pxy;
        const float k = saturate(0.12f / pix - 0.5f);
        const float sp = 0.6f * argus_noise(q * 11.0f) + 0.4f * argus_noise(q * 17.0f + 7.0f);
        const float3 grain = float3(0.14f, 0.14f, 0.13f) * sp * k;      // sp: std ~0.35
        m.alb = STONE_MEAN * (1.0f + grain + 0.03f * argus_noise(q * 2.3f + 2.0f));
        m.rough = ROUGH_STONE; m.gloss = ggx_lobe(ROUGH_STONE);
        m.ao *= 1.0f - 0.6f * exp(-(R_WALL_TOP - r) / 0.5f);           // under the lip
        m.ao *= mix(1.0f, 0.9f, smoothstep(R_TRACK_IN + 0.3f, R_TRACK_IN, r));
    } else if (r >= R_STATOR_IN) {
        // ------------------ lower stator: dark mahogany veneer under a clear coat --
        const float g = argus_fbm(float2(ang_w * 45.0f, r * 0.5f), 2);
        const float fig = 0.5f + 0.5f * sin(ang_w * 120.0f + 5.0f * g + r * 0.3f);
        m.alb = BOWL_DK * mix(WOOD_B, WOOD_A, saturate(0.4f + 0.45f * fig * (0.6f + 0.4f * g)));
        m.rough = ROUGH_VEN; m.gloss = ggx_lobe(ROUGH_VEN);
        m.ao *= 1.0f - 0.3f * smoothstep(1.5f * pix, 0.0f, abs(r - R_TRACK_IN));   // the groove's floor
        m.ao *= 1.0f - 0.3f * exp(-(r - R_STATOR_IN) / 0.2f);
    } else if (r >= R_ROTOR_OUT) {
        // --------------------------------------------- the seam to the rotor --
        m.alb = float3(0.002f); m.f0 = 0.02f; m.ao = 0.15f;
    } else if (r >= R_NUM_OUT) {
        m.alb = float3(0.0f); m.met = 1.0f;   // rotor rim: chrome
    } else if (r >= R_POCKET_IN) {
        // ---------------------- the rotor's numbered ring and pockets (blurred) --
        const float s = (POCKET_A0 - a_rot) / POCKET_DA + 0.5f;      // pocket k occupies [k, k+1)
        const float wpix = pix / (r * POCKET_DA);   // a pixel, in pocket units
        const float wmot = dphi / POCKET_DA;
        const float w = min(wpix + wmot, 0.95f);
        const float k0f = floor(s - 0.5f * w);
        const float wt1 = saturate((s + 0.5f * w - (k0f + 1.0f)) / w);
        const int k0 = wrap37(int(k0f)), k1 = wrap37(int(k0f) + 1);
        const float3 band = mix(pocket_colour(k0), pocket_colour(k1), wt1);
        if (r >= R_NUM_IN) {
            // number ring: lacquer + numerals, smeared over the shutter
            const int NS = clamp(int(ceil(wmot * r * POCKET_DA / (1.5f * pix))), 1, 10);
            const float stepu = wmot / float(NS);
            const float aa = max(pix, stepu * r * POCKET_DA) / DIGIT_H * 0.6f;
            float cov = 0.0f;
            for (int i = 0; i < NS; i++) {
                const float si = s + (float(i) + 0.5f) / float(NS) * wmot - 0.5f * wmot;
                const float kf = floor(si);
                const float x = (si - kf - 0.5f) * POCKET_DA * r;
                cov += numeral_cov(wrap37(int(kf)), float2(x, r - R_TEXT), aa);
            }
            cov /= float(NS);
            m.alb = mix(band, CREAM, cov);
            // satin lacquer; a chrome edging on the ring's inner lip (over the pockets' outer wall)
            m.met = smoothstep(R_NUM_IN + 0.3f + pix, R_NUM_IN + 0.3f - pix, r);
            m.rough = ROUGH_RING; m.gloss = mix(ggx_lobe(ROUGH_RING), LOBE_CHROME, m.met);
            m.ao *= 1.0f - 0.25f * exp(-(R_NUM_OUT - r) / 0.12f);
        } else {
            // pocket floor (satin lacquer) between the frets (drawn over it in the kernel)
            const float3 floor_c = band * float3(0.55f, 0.55f, 0.6f) + float3(0.004f);
            const float dfr = abs(s - round(s)) * POCKET_DA * r;          // cm to the nearest fret
            const float depth = Z_FRET_TOP - rotor_profile_z(r);
            const float aof = 0.35f + 0.65f * smoothstep(0.0f, 1.1f, dfr - FRET_HALF_W);
            m.ao *= mix(1.0f, mix(aof, 0.72f, saturate(wmot * 2.5f)), saturate(depth / 0.6f));
            // the outer wall (the step under the number ring) and the cone's foot
            m.ao *= 1.0f - 0.5f * exp(-(R_NUM_IN - r) / 0.45f) - 0.3f * exp(-(r - R_POCKET_IN) / 0.5f);
            m.ao *= 0.8f;
            m.alb = floor_c; m.rough = ROUGH_POCK; m.gloss = ggx_lobe(ROUGH_POCK);
        }
    } else if (r >= R_TURRET) {
        // --------------- the cone: book-matched mahogany veneer under a clear coat --
        // 8 sectors, each two leaves mirrored about its centre line, the grain in a 20 deg
        // chevron. Chatoyance: the figure's sheen follows the angle between the fibres and the
        // light box's azimuth, so it slides over the turning cone and the two leaves of a sector
        // light up in turn (smooth, slow). Grain and figure fade to their mean over the pixel and
        // the shutter sweep, so the turning veneer never crawls.
        const float sec = TAU_F / 8.0f;
        const float am = a_rot - sec * floor(a_rot / sec) - 0.5f * sec;   // -sec/2..sec/2
        const float u = r * cos(am), v = r * sin(am);   // along / across the leaf
        const float gq = abs(v) * 0.940f + u * 0.342f;   // across the grain (cm)
        const float gl = u * 0.940f - abs(v) * 0.342f;   // along it
        const float smear = dphi * r;
        const float gw = 1.0f / (1.0f + smear / 0.10f + pix / 0.12f);     // fine grain lines
        const float fw = 1.0f / (1.0f + smear / 1.0f + pix / 0.8f);       // the figure
        const float g = argus_fbm(float2(gq * 2.2f, gl * 0.18f), 2);
        const float grain = sin(gq * 14.0f + 6.0f * g);
        const float figure = argus_fbm(float2(gq * 0.8f + 3.0f, gl * 0.3f), 2);
        const float fa = ang_w - am - (v >= 0.0f ? 0.349f : -0.349f);    // fibre azimuth, world
        const float chat = cos(2.0f * (fa - LIGHT_AZ));
        m.alb = mix(WOOD_B, WOOD_A, saturate(0.55f + gw * 0.22f * grain + fw * 0.5f * figure));
        m.alb *= 1.0f + 0.22f * chat + 0.25f * chat * fw * figure;
        // seams between sectors
        const float seam = smoothstep(pix * 1.2f + smear, 0.0f, abs(abs(am) - 0.5f * sec) * r);
        m.alb *= 1.0f - 0.6f * seam;
        // satin clear coat; a chrome edging where the cone meets the pockets
        m.met = smoothstep(R_POCKET_IN - 0.4f - pix, R_POCKET_IN - 0.4f + pix, r);
        m.rough = ROUGH_CONE; m.gloss = mix(ggx_lobe(ROUGH_CONE), LOBE_CHROME, m.met);
        m.ao *= 1.0f - 0.3f * exp(-(r - R_TURRET) / 0.8f);
    } else {
        // ---------------------------------------------------------- turret --
        m.alb = float3(0.0f); m.met = 1.0f;
    }
    return m;
}
// Which ring a radius falls in: materials are averaged over a pixel where this changes.
static inline int ring_band(float r) {
    return int(r >= R_TURRET) + int(r >= R_POCKET_IN) + int(r >= R_NUM_IN) + int(r >= R_NUM_OUT)
         + int(r >= R_ROTOR_OUT) + int(r >= R_STATOR_IN) + int(r >= R_TRACK_IN) + int(r >= R_WALL_TOP)
         + int(r >= R_APRON_OUT);
}

// The rim's lip is a silhouette: inside its edge the camera sees the track (under the overhang),
// outside it the lip. A pixel straddling the edge is shaded for both sides (1: the track continued
// under the lip; 2: the lip continued inward), blended by the exact share of the pixel on each.
// The rotor-stator gap is a ~1.1 px ring over a dark slot: a pixel near it is shaded as one side
// (3: the rotor rim continued outward, 4: the stator continued inward, the nearer one) and covered
// by the slot by the exact share the ring takes: no stair-stepped seam.
constant float RHO_LIP = R_WALL_TOP / (H_EYE - (Z_RIM_TOP - LIP_ROUND));   // the edge's radius / FC
constant float RHO_GAP_IN  = R_ROTOR_OUT / (H_EYE - Z_ROTOR_RIM);         // the gap on screen / FC
constant float RHO_GAP_OUT = R_STATOR_IN / (H_EYE - Z_STATOR_IN);
constant float3 GAP_C = float3(0.0004f, 0.0003f, 0.0003f);                // the dark slot
// A side, as the radii it shows (sc: outside them the side's surface is continued) and its
// continuation: kc > 0 a flat top at kc (the lip, the rotor rim), else the stator's curve.
struct Side { float2 sc; float kc; };
static inline Side side_of(int side) {
    Side s;
    switch (side) {
        case 1:  s.sc = float2(0.0f, R_WALL_TOP - 1e-3f);    s.kc = 0.0f; break;
        case 2:  s.sc = float2(R_WALL_TOP, 1e4f);            s.kc = Z_RIM_TOP - LIP_ROUND; break;
        case 3:  s.sc = float2(0.0f, R_ROTOR_OUT - 1e-3f);   s.kc = Z_ROTOR_RIM; break;
        default: s.sc = float2(R_STATOR_IN + 1e-3f, 1e4f);   s.kc = 0.0f; break;
    }
    return s;
}
static inline float prof_side(float r, Side sd) {
    if (r < sd.sc.x || r > sd.sc.y) return sd.kc > 0.0f ? sd.kc : stator_curve_z(r);
    return scene_rev(r);
}
static inline float r_side(float r, Side sd) { return clamp(r, sd.sc.x, sd.sc.y); }   // the radius whose material it shows

// The height the camera sees along pixel radius rho (a march down the ray, then a bisection).
static float visible_z(float rho, Side side) {
    const float r0 = rho * H_EYE;
    float zhi, zlo;
    if (r0 < 8.0f)                      { zhi = 12.6f; zlo = Z_CONE_TOP - 0.4f; }
    else if (r0 < R_POCKET_IN + 0.8f)   { zhi = Z_CONE_TOP + 0.3f; zlo = Z_POCKET - 0.2f; }
    else if (r0 < R_STATOR_IN + 0.6f)   { zhi = stator_z(R_STATOR_IN + 0.6f) + 0.1f; zlo = Z_POCKET - 0.2f; }
    else if (r0 < R_WALL_TOP - 0.2f)    { zhi = stator_z(r0) + 0.1f; zlo = 0.8f; }
    else if (r0 < R_APRON_OUT + 1.0f)   { zhi = Z_RIM_TOP + 0.05f; zlo = 0.0f; }
    else                                { zhi = 0.0f; zlo = 0.0f; }
    float z = zlo;
    if (zhi > 0.0f) {
        const float dz = (zhi - zlo) / 8.0f;
        float a = zhi, b = zlo;
        bool hit = false;
        for (int i = 1; i <= 8 && !hit; i++) {
            const float zi = zhi - float(i) * dz;
            if (zi <= prof_side(rho * (H_EYE - zi), side)) { a = zi + dz; b = zi; hit = true; }
        }
        if (hit) {
            for (int j = 0; j < 5; j++) {
                const float m = 0.5f * (a + b);
                if (m <= prof_side(rho * (H_EYE - m), side)) b = m; else a = m;
            }
            z = 0.5f * (a + b);
        }
    }
    return z;
}
static float4 shade_px(float2 uv, int side_k, constant ArgusFrame& f, thread const WheelState& S, float zb) {   // .w: the ball's cover
    const Side side = side_of(side_k);
    const float3 dir = normalize(float3(uv, -FC));
    const float3 V = -dir;
    const float rho = length(uv) / FC;
    const float uvpix = 2.0f / float(f.height);            // one pixel in argus_uv units

    // ---------------------------------------------------- visible surface --
    const float z = zb < Z_LIVE ? zb : visible_z(rho, side);
    const float r = rho * (H_EYE - z);
    float3 P = float3(uv * (H_EYE - z) / FC, z);
    const float pix = uvpix * (H_EYE - z) / FC;            // cm per pixel at P
    const float2 rh = r > 1e-4f ? P.xy / r : float2(1.0f, 0.0f);
    const float2 th = float2(-rh.y, rh.x);                 // CCW tangent
    // normal of the revolution profile, filtered over a pixel
    const float e = max(pix, 0.03f);
    const float zp = prof_side(r + e, side), zm = prof_side(max(r - e, 0.0f), side), z0 = prof_side(r, side);
    const float dzdr = (zp - zm) / (2.0f * e);
    // how far the normal turns across the pixel (bounded, so edges cannot blow it up)
    // ... and around the axis (a small dome's normal swings round within a pixel near its top)
    const float dang = abs(atan((zp - z0) / e) - atan((z0 - zm) / e)) * (pix / e)
                     + abs(dzdr) * rsqrt(1.0f + dzdr * dzdr) * pix / max(r, 0.05f);
    float3 n = normalize(float3(-dzdr * rh, 1.0f));
    // the join between the stone track and the veneer: a shallow V groove (shading only) whose
    // walls catch the hall's light; its normal's turn across the pixel widens the lobe
    float xblur = 0.0f;
    {
        const float xg = (r - R_TRACK_IN) / 0.22f;
        if (abs(xg) < 1.0f) {
            n = normalize(n + float3(rh * tan(-0.45f * sin(PI_F * xg)), 0.0f) * n.z);
            xblur = 0.45f * PI_F * pix / 0.22f;
        }
    }
    // the chrome rotor rim is a convex bead (shading only; it collides as the straight segment):
    // its normal turns from 45 deg inward to 60 deg outward across its ~1 cm, so within ~10 px it
    // mirrors the number ring, the hall, the light box, the ceiling and the bowl beside it
    {
        const float xb = (r_side(r, side) - R_NUM_OUT) / (R_ROTOR_OUT - R_NUM_OUT);
        if (xb > 0.0f && xb < 1.0f) {
            const float tilt = mix(-0.785f, 1.047f, xb);
            n = float3(rh * sin(tilt), cos(tilt));
            xblur = 2.0f * 1.833f * pix / (R_ROTOR_OUT - R_NUM_OUT);   // the reflection's sweep over a pixel
        }
    }
    const float ang_w = atan2(P.y, P.x);
    const float a_rot = ang_w - S.rotor;   // rotor-frame angle
    // Shutter: one fixed exposure, SHUTTER, at every frame rate: rotor, numerals, frets, arms and
    // ball are blurred over the same time at 30, 60 and 120 FPS (it does not depend on f.dt).
    const float SHb = SHUTTER;
    const float dphi = abs(S.rotor_vel) * SHUTTER;          // rotor sweep during the shutter
    // Wagon-wheel safety net: from 0.42 pocket per displayed frame the frets' periodic contrast
    // fades to its mean. The push cap (0.34 rev/s) keeps it off at 30, 60 and 120 FPS.
    const float fdt = clamp(f.dt, 1.0f / 120.0f, 1.0f / 30.0f);
    const float nyq = smoothstep(0.5f, 0.42f, abs(S.rotor_vel) * fdt / POCKET_DA);

    // ---------------------------------------------------- material at P --
    Mat m = mat_at(r_side(r, side), P.xy, ang_w, a_rot, pix, dphi);
    if (ring_band(r_side(r - 0.5f * pix, side)) != ring_band(r_side(r + 0.5f * pix, side))) {
        // a ring edge crosses this pixel: average the material over its footprint
        const Mat ma = mat_at(r_side(r - 0.33f * pix, side), P.xy, ang_w, a_rot, pix, dphi);
        const Mat mb = mat_at(r_side(r + 0.33f * pix, side), P.xy, ang_w, a_rot, pix, dphi);
        m.alb = (ma.alb + m.alb + mb.alb) / 3.0f;
        m.f0 = (ma.f0 + m.f0 + mb.f0) / 3.0f;
        m.met = (ma.met + m.met + mb.met) / 3.0f;
        m.gloss = (ma.gloss + m.gloss + mb.gloss) / 3.0f;
        m.rough = (ma.rough + m.rough + mb.rough) / 3.0f;
        m.ao = (ma.ao + m.ao + mb.ao) / 3.0f;
    }
    float3 alb = m.alb;
    float f0 = m.f0, met = m.met, gloss = m.gloss, ao = m.ao;
    const float rough = m.rough;

    // ---------------------------------------------------- the frets --
    // The rounded top is a half cylinder: its normal tilts asin(x / FRET_HALF_W) at lateral offset
    // x. Five facets: the crown (|x| < 0.18, tilt < 10 deg: the light box), two inner shoulders
    // (0.18..0.7, 10-44 deg: the hall) and two outer shoulders (0.7..1, 44-90 deg: they face down
    // into the neighbouring pocket and mirror its floor). Each is box-filtered exactly over the
    // pixel and the shutter, and its periodic contrast fades by `nyq`.
    float fret_top = 0.0f, fret_ccw = 0.0f, fret_cw = 0.0f, fret_occw = 0.0f, fret_ocw = 0.0f;
    float3 fret_pa = POCKET_MEAN, fret_pb = POCKET_MEAN;      // the pockets the outer shoulders face
    const float rf = rho * (H_EYE - Z_FRET_TOP);
    if (rf > R_FRET_IN && rf < R_FRET_OUT + pix && z < Z_FRET_TOP + 0.05f) {
        const float s = (POCKET_A0 - a_rot) / POCKET_DA + 0.5f;      // frets at integer s
        const float hwf = FRET_HALF_W / (rf * POCKET_DA);
        const float wf = min(pix / (rf * POCKET_DA) + dphi / POCKET_DA, 0.95f);
        const float span = smoothstep(R_FRET_IN + 0.05f, R_FRET_IN + 0.2f, rf)
                         * smoothstep(R_FRET_OUT + 0.5f * pix, R_FRET_OUT - 0.5f * pix, rf);
        fret_top  = mix(0.36f * hwf, tick_cov(s, wf, 0.18f * hwf), nyq) * span;
        fret_ccw  = mix(0.52f * hwf, tick_cov(s + 0.44f * hwf, wf, 0.26f * hwf), nyq) * span;
        fret_cw   = mix(0.52f * hwf, tick_cov(s - 0.44f * hwf, wf, 0.26f * hwf), nyq) * span;
        fret_occw = mix(0.30f * hwf, tick_cov(s + 0.85f * hwf, wf, 0.15f * hwf), nyq) * span;
        fret_ocw  = mix(0.30f * hwf, tick_cov(s - 0.85f * hwf, wf, 0.15f * hwf), nyq) * span;
        const float j = round(s);
        fret_pa = mix(pocket_colour(wrap37(int(j) - 1)), POCKET_MEAN, smoothstep(0.3f, 0.9f, wf));
        fret_pb = mix(pocket_colour(wrap37(int(j))), POCKET_MEAN, smoothstep(0.3f, 0.9f, wf));
    }
    const float2 fret_zr = float2(Z_FRET_TOP - 0.05f, rf);

    // ---------------------------------------------------- diamonds (static) --
    // Rhombic chrome studs with a 4-facet pyramid cap, sheared to follow the stator's slope, the
    // edges rounded. Seen at their mean top height (parallax). Facet normals are blended across
    // the ridges over ~1.5 px and the rounded edge band is at least 2.5 px wide: no speckle.
    if (r > R_DIAMOND - 2.5f && r < R_DIAMOND + 2.5f) {
        const float zd = stator_z(R_DIAMOND) + 0.5f * (DIAMOND_H + DIAMOND_HE);
        const float2 Q = uv * (H_EYE - zd) / FC;
        const float sec = 0.785398f;
        const float j = round(atan2(Q.y, Q.x) / sec);
        const float ac = j * sec;
        const float2 cr = float2(cos(ac), sin(ac)), ct = float2(-cr.y, cr.x);
        const float2 dq = Q - R_DIAMOND * cr;
        const bool radial = (int(j) & 1) == 0;
        const float2 q = radial ? float2(dot(dq, cr), dot(dq, ct)) : float2(dot(dq, ct), dot(dq, cr));
        const float2 hb = float2(DIAMOND_HALF_LEN, DIAMOND_HALF_WID);
        const float d2 = sd_rhombus(q, hb);   // < 0 inside
        const float cov = smoothstep(0.5f * pix, -0.5f * pix, d2);
        // its foot darkens the stator around it
        ao *= 1.0f - 0.45f * (1.0f - cov) * exp(-max(d2, 0.0f) / 0.35f);
        if (cov > 0.0f) {
            // the outward direction of the nearest edge (gradient of the rhombus distance)
            const float ee = 0.02f;
            const float2 gq = float2(sd_rhombus(q + float2(ee, 0.0f), hb) - sd_rhombus(q - float2(ee, 0.0f), hb),
                                     sd_rhombus(q + float2(0.0f, ee), hb) - sd_rhombus(q - float2(0.0f, ee), hb));
            const float2 gl = gq / max(length(gq), 1e-5f);
            const float2 gw2 = radial ? (gl.x * cr + gl.y * ct) : (gl.x * ct + gl.y * cr);
            const float rr = length(Q);
            const float2 sl2 = -stator_slope(rr) * Q / max(rr, 1e-3f);          // the stator's tilt
            // the facet under the pixel (signs blended across the ridges)
            const float2 sgn = clamp(q / (0.75f * pix), -1.0f, 1.0f);
            const float2 fl = -sgn * float2(DIAMOND_KX, DIAMOND_KY);                // facet slopes, local
            const float2 lx = radial ? cr : ct, ly = radial ? ct : cr;
            // (shading: the cap's facets are taken a little less sheared than the collision cap;
            // from above they mirror the hall and the ceiling around the box, not the box itself)
            const float3 ntop = normalize(float3(0.35f * sl2 + 0.8f * (fl.x * lx + fl.y * ly), 1.0f));
            // across the rounded edge the normal turns from the facet's to horizontal
            const float band = max(DIAMOND_ROUND, 2.5f * pix);
            const float t = saturate((d2 + band) / band);
            const float turn = 1.5708f * t * t;
            const float3 nd = normalize(ntop * cos(turn) + float3(gw2, 0.0f) * sin(turn));
            n = normalize(mix(n, nd, cov));
            met = mix(met, 1.0f, cov);
            // the lobe covers how far the normal turns within the pixel (edge band, ridges)
            gloss = mix(gloss, 0.03f + 2.0f * 1.5708f * pix / band * t + 0.7f * (2.0f - abs(sgn.x) - abs(sgn.y)), cov);
            ao = mix(ao, 1.0f, cov);
            P.z = mix(P.z, zd, cov);
        }
    }

    // ---------------------------------------------------- shadows on P --
    float shadow = 1.0f;
    // ball: contact occlusion + soft shadows from the nearest panels
    const float3 B = S.ball;
    const float ba = S.ball_alpha;
    if (ba > 0.0f && length(P.xy - B.xy) < 12.0f) {
        const float3 vb = S.ball_vel * SHb;
        const float sl = length(vb);
        const float keep = 2.0f * R_BALL / (2.0f * R_BALL + sl);
        float3 Bc = B;
        if (sl > 1e-3f) { const float3 dv = vb / sl; Bc = B + dv * clamp(dot(P - B, dv), -0.5f * sl, 0.5f * sl); }
        const float occ = sphere_ao(P, n, Bc, R_BALL);
        // the box gives ~60 % of the light here; the rest (the hall) is occluded as ambient
        const float sh = (1.0f - 0.6f * box_block(P, Bc, R_BALL)) * mix(1.0f, occ, 0.5f);
        shadow *= mix(1.0f, sh, ba * mix(1.0f, keep, 0.5f));
    }
    // turret column and handle arms on the cone / pockets
    if (r < R_NUM_IN && r > 1.0f) {
        const float3 L0 = box_dir(float3(0.0f, 0.0f, 0.0f));
        // column: the axis, up to the hub
        {
            const float t1 = (10.0f - P.z) / L0.z;
            if (t1 > 0.0f) {
                const float2 a2 = P.xy, b2 = P.xy + L0.xy * t1;
                const float dcol = sd_seg(float2(0.0f), a2, b2);
                const float pen = 0.4f + 0.12f * t1 * 0.5f;
                shadow *= 1.0f - 0.45f * smoothstep(2.2f + pen, 2.2f - pen, dcol) * smoothstep(R_TURRET - 1.5f, R_TURRET + 0.5f, r);
            }
        }
        const float t2 = (ARM_Z - P.z) / L0.z;
        if (t2 > 0.0f) {
            const float2 Q = P.xy + L0.xy * t2;              // where the shadow ray meets the arms' plane
            const float rq = length(Q);
            const float aq = atan2(Q.y, Q.x) - S.rotor - ARM_A0;
            const float qa = 1.5707963f;
            const float rel = (aq - qa * round(aq / qa));    // angle to the nearest arm
            const float pen = 0.1f + t2 * 0.10f;
            const float halfw = (ARM_R + pen) / max(rq, 0.5f);
            const float wv = dphi;
            const float cov = saturate((min(rel + 0.5f * wv, halfw) - max(rel - 0.5f * wv, -halfw)) / max(wv, 1e-4f + 0.0f * halfw));
            const float c2 = wv > 2.0f * halfw ? cov : smoothstep(ARM_R + pen, ARM_R - pen, abs(rel) * rq);
            const float on = smoothstep(ARM_R0 - 0.5f, ARM_R0 + 0.5f, rq) * smoothstep(KNOB_AT + KNOB_R + pen, KNOB_AT + KNOB_R - pen, rq);
            shadow *= 1.0f - 0.5f * c2 * on;
        }
    }

    // ---------------------------------------------------- shade P --
    const float ndv = saturate(dot(n, V));
    float3 Rv = reflect(dir, n);
    const float pixang = uvpix / FC;   // a pixel's angular size
    const float blur = gloss + 4.0f * dang + xblur + pixang * (1.0f + (HC - P.z) / max(H_EYE - P.z, 1.0f));
    float3 envc = (f0 > 0.0f || met > 0.0f) ? env(P, Rv, blur, S.rotor, dphi) : float3(0.0f);   // the felt reflects nothing
    // the ball, mirrored in glossy surfaces
    // (filtered over the lobe: its footprint at the ball's distance against the ball's disc, so a
    // small or steep mirror shows a faint, steady image instead of a sparkle)
    if (ba > 0.0f) {
        const float3 oc = P - B;
        const float bq = dot(oc, Rv), cq = dot(oc, oc) - R_BALL * R_BALL;
        const float hq = bq * bq - cq;
        if (bq < 0.0f) {
            const float dp = sqrt(max(dot(oc, oc) - bq * bq, 0.0f));    // the ray's miss distance
            const float sw = 0.5f * blur * (-bq) + 1e-3f;                // the lobe's radius there
            const float wb = smoothstep(R_BALL + sw, max(R_BALL - sw, 0.0f), dp) * saturate(sq(R_BALL / max(sw, R_BALL)));
            if (wb > 0.0f) {
                const float3 nh = hq > 0.0f ? normalize(oc + Rv * (-bq - sqrt(hq)))   // where the ray meets it
                                            : normalize(oc - Rv * bq);                 // or its limb
                envc = mix(envc, ball_diffuse(nh, B, float3(0.0f)), ba * wb);
            }
        }
    }
    const float Fr = f0 > 0.0f ? env_brdf(f0, rough, ndv) : 0.0f;   // Fresnel over the satin lobe
    const float3 col_d = alb * diffuse_light(n) * ao * shadow * (1.0f - Fr) + Fr * envc * mix(1.0f, ao, 0.7f) * (0.4f + 0.6f * shadow);
    const float3 col_m = schlick3(CHROME, ndv) * envc * (0.35f + 0.65f * shadow) * mix(1.0f, ao, 0.6f);
    float3 col = mix(col_d, col_m, met);
    // the felt's cloth sheen (Charlie lobe, Estevez & Kulla 2017; see felt_sheen): faint from
    // straight above, a little stronger toward the screen's edges, as baize does.
    if (r >= R_APRON_OUT) col += felt_sheen(P, V) * ao * mix(0.4f, 1.0f, shadow);
    // the frets over the pocket floors: chrome facets, composited by their coverage
    const float fret_all = fret_top + fret_ccw + fret_cw + fret_occw + fret_ocw;
    if (fret_all > 0.0f) {
        const float3 Pf = float3(rh * fret_zr.y, fret_zr.x);
        const float lit = 0.35f + 0.65f * shadow;
        const float3 n_t = float3(0.0f, 0.0f, 1.0f);
        const float3 n_a = normalize(float3(th * 0.5f, 1.0f)), n_b = normalize(float3(-th * 0.5f, 1.0f));   // 27 deg
        const float3 ct = schlick3(CHROME, dot(n_t, V)) * env(Pf, reflect(dir, n_t), 0.35f, S.rotor, dphi);
        const float3 ca = schlick3(CHROME, saturate(dot(n_a, V))) * env(Pf, reflect(dir, n_a), 0.6f, S.rotor, dphi);
        const float3 cb = schlick3(CHROME, saturate(dot(n_b, V))) * env(Pf, reflect(dir, n_b), 0.6f, S.rotor, dphi);
        // the outer shoulders mirror the shaded pocket floor beside them (chrome at ~67 deg)
        const float3 fo = schlick3(CHROME, 0.39f) * (0.22f * DL_UP);
        col = col * (1.0f - fret_all) + lit * (fret_top * ct + fret_ccw * ca + fret_cw * cb
                                              + fo * (fret_occw * fret_pa + fret_ocw * fret_pb));
    }

    // ---------------------------------------------------- handle arms + knobs --
    float arm_cov = 0.0f;   // hides the ball when it is below them
    {
        const float zc = ARM_Z;
        const float2 Q = uv * (H_EYE - zc) / FC;
        const float rq = length(Q);
        if (rq < KNOB_AT + KNOB_R + 0.5f && rq > ARM_R0 - 0.2f) {
            const float aq = atan2(Q.y, Q.x) - S.rotor - ARM_A0;
            const float qa = 1.5707963f;
            const float rel = aq - qa * round(aq / qa);           // angle to the nearest arm's centre (at shutter mid)
            const float wv = dphi;
            const float pq = pix / max(rq, 0.5f);
            // rod
            const float arad = arm_radius((rq - ARM_R0) / (ARM_R1 - ARM_R0));
            const float hr = arad / rq;
            const float lo = max(rel - 0.5f * (wv + pq), -hr), hi = min(rel + 0.5f * (wv + pq), hr);
            float cov = saturate((hi - lo) / (wv + pq));
            cov *= smoothstep(ARM_R0 - pix, ARM_R0 + pix, rq) * smoothstep(ARM_R1 + pix, ARM_R1 - pix, rq);
            // knob
            const float dk = rq - KNOB_AT;
            const float hk = sqrt(max(KNOB_R * KNOB_R - dk * dk, 0.0f)) / rq;
            const float lok = max(rel - 0.5f * (wv + pq), -hk), hik = min(rel + 0.5f * (wv + pq), hk);
            const float covk = abs(dk) < KNOB_R + pix ? saturate((hik - lok) / (wv + pq)) * smoothstep(KNOB_R + pix, KNOB_R - pix, abs(dk)) : 0.0f;
            const float c = max(cov, covk);
            if (c > 0.0f) {
                // normal at the middle of the covered interval
                const float mid = 0.5f * (lo + hi);
                const bool kn = covk > cov;
                float3 na;
                const float2 qr = Q / rq, qt = float2(-qr.y, qr.x);
                if (kn) {
                    const float mk = 0.5f * (lok + hik);
                    const float2 o = float2(dk, mk * rq) / KNOB_R;
                    na = float3(qr * o.x + qt * o.y, sqrt(max(1.0f - dot(o, o), 0.02f)));
                } else {
                    const float o = clamp(mid * rq / arad, -1.0f, 1.0f);
                    na = float3(qt * o, sqrt(max(1.0f - o * o, 0.02f)));
                }
                na = normalize(na);
                const float3 Pa = float3(Q, zc + 0.3f);
                const float3 Ra = reflect(dir, na);
                const float3 ca = schlick3(CHROME, saturate(dot(na, V))) * env(Pa, Ra, 0.02f + 4.0f * pix / ((kn ? KNOB_R : arad) * max(na.z, 0.12f)), S.rotor, dphi);
                col = mix(col, ca, c);
                arm_cov = c;
            }
        }
    }

    // ---------------------------------------------------- the ball --
    // Swept over its shutter along its path in polar coordinates about the axis (the rim ball
    // circles: a straight streak would cut the chord), as 4 capsules, each a quarter of the
    // shutter time; the coverage is the share of the shutter the ball covers the pixel.
    float ball_cov = 0.0f;
    if (ba > 0.0f) {
        const float rB = length(B.xy);
        const float3 vB = S.ball_vel;
        const bool polar = rB > 3.0f;
        const float2 eB = B.xy / max(rB, 1e-3f);
        const float vr = dot(vB.xy, eB), om = (eB.x * vB.y - eB.y * vB.x) / max(rB, 1e-3f), thB = atan2(B.y, B.x);
        const float3 pA = ball_at(B, vB, -0.5f * SHb, polar, rB, thB, vr, om), pZ = ball_at(B, vB, 0.5f * SHb, polar, rB, thB, vr, om);
        const float2 cA = pA.xy * FC / (H_EYE - pA.z), cZ = pZ.xy * FC / (H_EYE - pZ.z);
        const float rb0 = R_BALL * FC / (H_EYE - B.z);
        // bound: the swept arc lies within its chord's circle widened by the arc's sag
        const float2 cM = B.xy * FC / (H_EYE - B.z);
        if (length(uv - cM) < rb0 + 0.5f * length(cZ - cA) + 0.3f * length(cZ - cA) + 2.0f * uvpix) {
            float covT = 0.0f, dBest = 1e9f;
            float2 ocBest = float2(0.0f);
            float3 Bbest = B;
            float rbBest = rb0;
            float3 pa = pA;
            float2 ca = cA;
            for (int i = 0; i < 4; i++) {
                const float3 pb = ball_at(B, vB, SHb * (0.25f * float(i + 1) - 0.5f), polar, rB, thB, vr, om);
                const float2 cb2 = pb.xy * FC / (H_EYE - pb.z);
                const float rb = R_BALL * FC / (H_EYE - 0.5f * (pa.z + pb.z));
                const float2 sw = cb2 - ca, mid = 0.5f * (ca + cb2);
                const float L = length(sw);
                const float2 ax = L > 1e-6f ? sw / L : float2(1.0f, 0.0f);
                const float2 o = uv - mid;
                const float u = dot(o, ax), wv = dot(o, float2(-ax.y, ax.x));
                const float Lp = max(L, uvpix);
                const float hh = sqrt(max(sq(rb + 0.5f * uvpix) - wv * wv, 0.0f));
                const float lo = max(u - hh, -0.5f * Lp), hi = min(u + hh, 0.5f * Lp);
                const float ci = saturate((hi - lo) / Lp) * smoothstep(rb + uvpix, rb, abs(wv));
                covT += 0.25f * ci;
                // the normal: from the nearest point of the centre's whole path (a still ball is a
                // sphere; a streak is round across and at its two ends)
                const float2 off = o - ax * clamp(u, -0.5f * L, 0.5f * L);
                const float dd = dot(off, off);
                if (dd < dBest) { dBest = dd; ocBest = off / rb; Bbest = 0.5f * (pa + pb); rbBest = rb; }
                pa = pb; ca = cb2;
            }
            if (covT > 0.0f) {
                // what lies under the ball, lit (its bounce light)
                const float3 ball_under = wheel_image(B, float3(0.0f, 0.0f, -1.0f), 0.3f, S.rotor, dphi);
                const float l2 = dot(ocBest, ocBest);
                const float3 nb = normalize(float3(ocBest, sqrt(max(1.0f - l2, 0.0f)) + 0.02f));
                const float3 Pb = Bbest + nb * R_BALL;
                const float ndvb = saturate(dot(nb, V));
                const float Fb = env_brdf(F0_BALL, ROUGH_BALL, ndvb);  // over its satin lobe
                const float3 Rb = reflect(dir, nb);
                // contact: the limb darkens toward the surface it rests on
                const float hgt = B.z - R_BALL - scene_rev(rB);
                const float aob = 1.0f - 0.6f * pow(1.0f - saturate(nb.z), 2.5f) * saturate(1.0f - hgt / 1.5f);
                const float3 dif = ball_diffuse(nb, Bbest, ball_under) * aob;
                // satin PTFE: a 0.12 rad lobe, so the light box is a small soft patch toward it
                const float3 spc = env(Pb, Rb, ggx_lobe(ROUGH_BALL) + 2.0f * pixang / max(rbBest, 1e-3f), S.rotor, dphi);
                const float3 cball = dif * (1.0f - Fb) + Fb * spc;
                // the overhanging lip (or anything else standing higher here) hides the ball
                const float vis = smoothstep(-0.06f, 0.06f, Pb.z - z) * (1.0f - arm_cov * step(Pb.z, ARM_Z));
                ball_cov = covT * ba * vis;
                col = mix(col, cball, ball_cov);
            }
        }
    }

    // ---------------------------------------------------- finish --
    col *= 1.0f - 0.10f * dot(uv, uv) * 0.25f;
    col *= 1.45f;   // exposure
    return float4(col, ball_cov);
}

// The static part of the picture, baked once by argus_init into rows 1.. of the state (one pixel
// per float, four per texel, at 1920x1200): the felt's final 8-bit colour packed as -(rgb + 1)
// (nothing on the felt moves), and on the wheel the height the camera sees (the surface search
// depends only on the pixel). Z_LIVE marks pixels shaded live (the lip and gap edges, where two
// sides blend). Another output size (the harness's watchdog, previews) draws everything live.
static float bake_px(uint2 px, constant ArgusFrame& f) {
    if (px.x >= f.width || px.y >= f.height) return Z_LIVE;
    const float2 uv = argus_uv(px, f);
    const float rho = length(uv) / FC;
    const float ppx = 0.5f * FC * float(f.height);
    const float dl = (rho - RHO_LIP) * ppx;
    if ((rho - RHO_GAP_IN) * ppx > -0.6f && (rho - RHO_GAP_OUT) * ppx < 0.6f) return Z_LIVE;
    if (dl < 0.5f && dl > -0.5f) return Z_LIVE;
    const Side side = side_of(dl < 0.5f ? 1 : 2);
    const float r0 = rho * H_EYE;
    if (r0 >= R_APRON_OUT + 1.0f) {
        WheelState S0;
        S0.rotor = 0.0f; S0.rotor_vel = 0.0f; S0.ball = float3(0.0f, 0.0f, -100.0f); S0.ball_vel = float3(0.0f);
        S0.ball_roll = 0.0f; S0.ball_alpha = 0.0f; S0.winner = -1;
        const float3 c = argus_srgb(argus_aces(shade_px(uv, 2, f, S0, 0.0f).rgb));
        const uint3 q = uint3(rint(saturate(c) * 255.0f));
        return -float((q.x << 16) | (q.y << 8) | q.z) - 1.0f;
    }
    return visible_z(rho, side);
}
static float4 bake4(uint2 gid, constant ArgusFrame& f) {
    const uint2 p = uint2(4u * gid.x, gid.y - 1u);
    return float4(bake_px(p, f), bake_px(p + uint2(1, 0), f), bake_px(p + uint2(2, 0), f), bake_px(p + uint2(3, 0), f));
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> state [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const WheelState S = wheel_state(state, f.time);
    const float2 uv = argus_uv(gid, f);
    const float rho = length(uv) / FC;
    const float ppx = 0.5f * FC * float(f.height);   // pixels per unit of rho
    const float dl = (rho - RHO_LIP) * ppx;   // pixels outside the lip's edge
    // the rotor-stator gap: the share of the pixel (radially) it covers
    const float gap = saturate((min(rho + 0.5f / ppx, RHO_GAP_OUT) - max(rho - 0.5f / ppx, RHO_GAP_IN)) * ppx);
    const bool near_gap = (rho - RHO_GAP_IN) * ppx > -0.6f && (rho - RHO_GAP_OUT) * ppx < 0.6f;
    // one call site (a loop of one or two), so the shading is compiled once
    const int k0 = near_gap ? (rho < 0.5f * (RHO_GAP_IN + RHO_GAP_OUT) ? 3 : 4) : (dl < 0.5f ? 1 : 2);
    const int k1 = near_gap ? k0 : (dl > -0.5f ? 2 : 1);
    float zb = Z_LIVE;
    const float4 bk = state.read(uint2(10, 0));
    if (bk.z == BAKE_TAG && uint(bk.x) == f.width && uint(bk.y) == f.height) {
        const float v = state.read(uint2(gid.x >> 2, gid.y + 1u))[gid.x & 3u];
        if (v < 0.0f) {   // the felt: its final colour, baked
            const uint q = uint(-v - 1.0f);
            out.write(float4(float(q >> 16), float((q >> 8) & 255u), float(q & 255u), 255.0f) / 255.0f, gid);
            return;
        }
        zb = v;
    }
    float4 col = float4(0.0f);
    for (int k = k0; k <= k1; k++)
        col += shade_px(uv, k, f, S, zb) * (k0 == k1 ? 1.0f : (k == 2 ? dl + 0.5f : 0.5f - dl));
    // the dark slot lies under the ball: only the part of the pixel the ball leaves open shows it
    if (near_gap) col.rgb = mix(col.rgb, GAP_C, gap * (1.0f - saturate(col.w)));
    out.write(float4(argus_srgb(argus_aces(col.rgb)), 1.0f), gid);
}

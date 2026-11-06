// ROULETTE CHROME // web/themes/Roulette_Chrome.wgsl
// Claude (Anthropic), 2026-10-19.
// The one-to-one WGSL translation of themes/Roulette_Chrome.metal (web/README.md).
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

// ---- translation notes (WGSL only) ----
// Metal's round() takes halfway cases away from zero; WGSL's round() takes them to even, so the
// theme's round() is round_m() below (exact C semantics). Metal's rint() is WGSL's round().
// Metal's isfinite() is isfinite_f() below (WGSL has none). The Sim field `target` is `tgt`
// and room()'s local `var` is `var_` (both reserved words in WGSL). Functions that take
// `thread Sim&` / `thread Ev&` take ptr<function, ...>; the frame is the module-scope `f`.
fn round_m(x: f32) -> f32 { let t = trunc(x); return select(t, t + sign(x), abs(x - t) >= 0.5f); }
fn isfinite_f(x: f32) -> bool { return (bitcast<u32>(x) & 0x7f800000u) != 0x7f800000u; }
fn isfinite3(v: vec3f) -> bool { return isfinite_f(v.x) && isfinite_f(v.y) && isfinite_f(v.z); }

// ==== SHARED GEOMETRY ====
// Units cm. World frame: wheel centre at the origin, z up, felt top at z = 0, x right, y up the
// screen, angles CCW-positive seen from above. Rotor-frame angle a = world angle - phi.
// The physics collides with exactly these surfaces; the draw should render exactly these.
const PI_F: f32        = 3.14159265f;
const TAU_F: f32       = 6.28318531f;
const G_ACC: f32       = 981.0f;      // cm/s^2
const R_BALL: f32      = 1.0f;        // 20 mm white resin ball
const N_POCKETS: i32   = 37;
const POCKET_DA: f32   = 0.16981582f; // 2 pi / 37
const POCKET_A0: f32   = 1.57079633f; // rotor-frame angle of the centre of slot 0 (the zero)
                                      // slot i is centred at POCKET_A0 - i*POCKET_DA (clockwise)
// Bowl and stator (static). The stator is a smooth cubic from the rotor edge to the wall,
// z = Z_STATOR_IN + x (STATOR_T_IN + x (STATOR_S2 + x STATOR_S3)), x = r - R_STATOR_IN, plus a
// steepening inside R_STEEP: + STEEP_C ((R_STEEP - R_STATOR_IN)^2 - (R_STEEP - r)^2) (C1 at
// R_STEEP; outside it the cubic is lifted by STEEP_DZ). 38 deg at the rotor edge, 35 deg at the
// diamonds, easing to 18.7 deg at the ball's rim contact. The orbit a ball needs (r^3 dz/dr)
// is larger everywhere inside the wall than the released ball has, so it falls across the
// diamond ring in about a revolution instead of spiralling at it.
const R_STATOR_IN: f32 = 28.0f;       // inner edge of the stator (next to the rotor rim)
const Z_STATOR_IN: f32 = 3.45f;      // 0.48 above the rotor rim: the rotor sits below the stator
const STATOR_T_IN: f32 = 0.60f;       // slope dz/dr at R_STATOR_IN (31.0 deg)
const STATOR_S2: f32   = 0.0138204f;
const STATOR_S3: f32   = -0.0017395f;
const R_STEEP: f32     = 32.5f;       // the lower track is steepened inside this radius
const STEEP_C: f32     = 0.02f;
const STEEP_DZ: f32    = 0.405f;      // STEEP_C (R_STEEP - R_STATOR_IN)^2: the lift outside R_STEEP
const R_RIM_WALL: f32  = 39.0f;       // foot of the back-track wall the ball rides against;
const WALL_LEAN: f32   = 0.13963f;    //   the wall overhangs inward by 8 deg (a lip that keeps the
const R_WALL_TOP: f32  = 38.7691f;    //   ball down): its top edge is at r = R_WALL_TOP
const Z_WALL_FOOT: f32 = 9.812f;      // stator_z(R_RIM_WALL)
const Z_RIM_TOP: f32   = 11.455f;     // top of the wall / flat rim top r 39..41 (1.64 above its foot)
const R_RIM_OUT: f32   = 41.0f;       // outer edge of the rim top (apron 41..45 falls to the felt)
const R_APRON_OUT: f32 = 45.0f;
const ALPHA_TRACK: f32 = 0.32605f;    // 18.68 deg: stator slope at the ball's rim contact (r 38.21)
const R_BALL_RIM: f32  = 37.891f;       // ball centre radius while it rides the wall
const Z_BALL_RIM: f32  = 10.518f;     // ball centre height while it rides the wall
// Diamonds (deflectors): 8 chrome studs on the stator, centred at r = R_DIAMOND, angles k*45 deg;
// even k radial (long axis along the radius), odd k tangential. A rhombic footprint
// (half-diagonals DIAMOND_HALF_LEN x DIAMOND_HALF_WID, 3 cm long, 3.5:1) with upright sides
// DIAMOND_HE tall, capped by a 4-facet pyramid whose apex stands DIAMOND_H above the local stator
// surface (it follows the slope); edges rounded with DIAMOND_ROUND. See diamond_sdf().
const R_DIAMOND: f32        = 31.0f;
const DIAMOND_HALF_LEN: f32 = 1.5f;
const DIAMOND_HALF_WID: f32 = 0.43f;
const DIAMOND_H: f32        = 0.8f;
const DIAMOND_HE: f32       = 0.45f;
const DIAMOND_ROUND: f32    = 0.10f;
const DIAMOND_KX: f32 = (DIAMOND_H - DIAMOND_HE) / DIAMOND_HALF_LEN;   // facet slopes
const DIAMOND_KY: f32 = (DIAMOND_H - DIAMOND_HE) / DIAMOND_HALF_WID;
// Rotor (wheelhead): axisymmetric profile in (r, z), turning with phi, plus 37 frets.
const R_TURRET: f32    = 7.0f;        // the turret's collar meets the cone here (turret_z below)
const R_CONE_IN: f32   = 7.0f;        // cone r 7..19.5, straight, z 5.4 -> 1.6
const Z_CONE_TOP: f32  = 5.4f;
const R_POCKET_IN: f32 = 19.5f;       // pocket ring r 19.5..24
const Z_CONE_OUT: f32  = 1.6f;
const R_DISH_C: f32    = 21.9f;       // pocket floor: circular arc, lowest at r = R_DISH_C,
const Z_POCKET: f32    = 0.8f;        //   z = Z_POCKET, radius R_DISH (centre at z 4.8)
const R_DISH: f32      = 4.0f;
const R_NUM_IN: f32    = 24.0f;       // pocket outer wall: vertical step at r = 24 from the
const Z_DISH_OUT: f32  = 1.39557f;    //   floor (z 1.396) up to the number ring (z 1.50)
const Z_NUM_IN: f32    = 1.50f;       // number ring r 24..27, straight, z 1.50 -> 2.592 (20.0 deg
const R_NUM_OUT: f32   = 27.0f;       //   down into the pockets: g tan 20 deg = 357 cm/s^2 beats the
const Z_NUM_OUT: f32   = 2.592f;      //   <= 320 a ball riding with the fastest rotor feels outward)
const R_ROTOR_OUT: f32 = 27.95f;      // chrome rotor rim r 27..27.95 (a polished band ~1 cm),
const Z_ROTOR_RIM: f32 = 2.97f;       //   z 2.592 -> 2.97 (21.7 deg), a 0.48 cm step under the stator
                                      //   edge (28, 3.45): a ball thrown out against it rarely climbs back
// Frets: thin chrome plates in the radial planes between pockets (rotor angle
// POCKET_A0 - (i + 0.5) POCKET_DA), from r 19.2 to 24, top Z_FRET_TOP, 2*FRET_HALF_W thick,
// the top edge rounded with radius FRET_HALF_W. Low profile: 0.85 cm above the pocket floor.
const R_FRET_IN: f32   = 19.2f;
const R_FRET_OUT: f32  = 24.0f;
const Z_FRET_TOP: f32  = 1.65f;
const FRET_HALF_W: f32 = 0.15f;
// Turret (the chrome column on the rotor axis) and its 4-arm handle. One profile of revolution,
// drawn as is and collided as a 12-point polyline through it (sag < 0.03 cm, under a pixel):
// a rounded collar r 4.6..7 (z 5.4 -> 6.1), a flared column r 2.05..4.6, a domed boss r < 2.05
// (a sphere of radius 2.3, top z 11.86) with the ball-rest cup in its top (r < 0.6).
fn sq(x: f32) -> f32 { return x * x; }
fn turret_z(r: f32) -> f32 {
    if (r < 0.6f) { return 11.55f + 0.25f * sq(r / 0.6f); }
    if (r < 2.05f) { return 9.556f + sqrt(max(5.29f - r * r, 0.0f)); }
    if (r < 4.6f) { return 6.7f + 2.9f * sq(1.0f - (r - 2.05f) / 2.55f); }
    return Z_CONE_TOP + 0.7f * sqrt(max(1.0f - sq((r - 4.6f) / 2.4f), 0.0f));
}
const TURRET_PR = array<f32, 12>(7.0f, 6.95f, 6.8f, 6.5f, 6.0f, 5.3f, 4.6f, 4.5999f, 3.8f, 3.0f, 2.0501f, 2.0499f);
// Handle (a "French cross"): 4 turned chrome rods at height ARM_Z from r ARM_R0 to ARM_R1,
// tapering from radius ARM_RA to ARM_RB, each ending in a ball finial (radius KNOB_R) at r
// KNOB_AT, at rotor angles ARM_A0 + k 90 deg. ARM_R is their mean radius (for the shadows).
const ARM_Z: f32 = 10.35f; const ARM_RA: f32 = 0.75f; const ARM_RB: f32 = 0.55f; const ARM_R: f32 = 0.65f; const ARM_R0: f32 = 2.0f; const ARM_R1: f32 = 10.9f;
const KNOB_R: f32 = 1.2f; const KNOB_AT: f32 = 11.7f;
const ARM_A0: f32 = 0.785398f;
fn arm_radius(t: f32) -> f32 { return mix(ARM_RA, ARM_RB, saturate(t)); }   // t 0..1 along the rod
// Wheel layout, clockwise from 0 seen from above.
const EU_SEQ = array<i32, 37>(0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
                              5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26);
fn is_red(n: i32) -> bool {
    // 1 3 5 7 9 12 14 16 18 19 21 23 25 27 30 32 34 36
    return n > 0 && ((((n <= 10) || (n >= 19 && n <= 28)) && ((n & 1) != 0)) ||
                     (((n >= 11 && n <= 18) || (n >= 29)) && !((n & 1) != 0)));
}
// Stator surface height at radius r (R_STATOR_IN..R_RIM_WALL; the rim top above that).
fn stator_curve_z(r: f32) -> f32 {   // the curve itself (no rim top)
    let x = max(r - R_STATOR_IN, 0.0f); let y = max(R_STEEP - r, 0.0f);
    return Z_STATOR_IN + x * (STATOR_T_IN + x * (STATOR_S2 + x * STATOR_S3)) + STEEP_DZ - STEEP_C * y * y;
}
fn stator_z(r: f32) -> f32 {
    return select(stator_curve_z(r), Z_RIM_TOP, r >= R_RIM_WALL);
}
fn stator_slope(r: f32) -> f32 {        // dz/dr of the stator curve
    let x = max(r - R_STATOR_IN, 0.0f);
    return STATOR_T_IN + x * (2.0f * STATOR_S2 + 3.0f * STATOR_S3 * x) + 2.0f * STEEP_C * max(R_STEEP - r, 0.0f);
}
fn stator_curv(r: f32) -> f32 {         // d2z/dr2
    let x = max(r - R_STATOR_IN, 0.0f);
    return 2.0f * STATOR_S2 + 6.0f * STATOR_S3 * x - select(0.0f, 2.0f * STEEP_C, r < R_STEEP);
}
// Axisymmetric rotor profile (no frets), r in the rotor (any angle).
fn rotor_profile_z(r: f32) -> f32 {
    if (r < R_TURRET)    { return turret_z(r); }
    if (r < R_POCKET_IN) { return mix(Z_CONE_TOP, Z_CONE_OUT, (r - R_CONE_IN) / (R_POCKET_IN - R_CONE_IN)); }
    if (r < R_NUM_IN) { let d = r - R_DISH_C; return Z_POCKET + R_DISH - sqrt(max(R_DISH * R_DISH - d * d, 0.0f)); }
    if (r < R_NUM_OUT)   { return mix(Z_NUM_IN, Z_NUM_OUT, (r - R_NUM_IN) / (R_NUM_OUT - R_NUM_IN)); }
    if (r < R_ROTOR_OUT) { return mix(Z_NUM_OUT, Z_ROTOR_RIM, (r - R_NUM_OUT) / (R_ROTOR_OUT - R_NUM_OUT)); }
    return Z_ROTOR_RIM;
}
// Continuous slot coordinate of a rotor-frame angle: slot centres at integers, frets at +-0.5.
fn slot_coord(a_rotor: f32) -> f32 {
    let s = (POCKET_A0 - a_rotor) / POCKET_DA;
    return s - 37.0f * floor(s / 37.0f);               // 0..37
}
fn slot_at(a_rotor: f32) -> i32 { return i32(floor(slot_coord(a_rotor) + 0.5f)) % 37; }
// Perpendicular distance (cm) from (r, a_rotor) to the nearest fret plane.
fn fret_plane_dist(r: f32, a_rotor: f32) -> f32 {
    let s = slot_coord(a_rotor);
    let off = (s + 0.5f - floor(s + 0.5f)) - 0.5f;          // -0.5..0.5 from slot centre
    return r * abs(sin((0.5f - abs(off)) * POCKET_DA));
}
// Rotor surface height at rotor-frame polar (r, a): profile, and the fret tops where they stand.
fn rotor_z(r: f32, a_rotor: f32) -> f32 {
    let z = rotor_profile_z(r);
    if (r > R_FRET_IN && r < R_FRET_OUT) {
        let w = fret_plane_dist(r, a_rotor);
        if (w < FRET_HALF_W) {
            let top = Z_FRET_TOP - FRET_HALF_W + sqrt(max(FRET_HALF_W * FRET_HALF_W - w * w, 0.0f));
            return max(z, top);
        }
    }
    return z;
}
// Signed distance (cm) from a point in a fret's own frame (u along the radius, w across the
// plate, z up) to that fret: a rounded box r R_FRET_IN..R_FRET_OUT, |w| < FRET_HALF_W, z < Z_FRET_TOP.
fn fret_sdf_local(loc: vec3f) -> f32 {
    let cen = vec3f(0.5f * (R_FRET_IN + R_FRET_OUT), 0.0f, 0.5f * Z_FRET_TOP);
    let hal = vec3f(0.5f * (R_FRET_OUT - R_FRET_IN), FRET_HALF_W, 0.5f * Z_FRET_TOP) - FRET_HALF_W;
    let q = abs(loc - cen) - hal;
    return length(max(q, vec3f(0.0f))) + min(max(q.x, max(q.y, q.z)), 0.0f) - FRET_HALF_W;
}
// Signed distance from a world point to the nearest fret, rotor at angle phi.
fn fret_sdf(p: vec3f, phi: f32) -> f32 {
    let sc = (POCKET_A0 - (atan2(p.y, p.x) - phi)) / POCKET_DA;
    let j = floor(sc + 0.5f);
    var d = 1e3f;
    for (var side = 0; side < 2; side++) {
        let fa = POCKET_A0 - (j + select(0.5f, -0.5f, side == 0)) * POCKET_DA + phi;
        let eu = vec2f(cos(fa), sin(fa)); let ew = vec2f(-eu.y, eu.x);
        d = min(d, fret_sdf_local(vec3f(dot(p.xy, eu), dot(p.xy, ew), p.z)));
    }
    return d;
}
fn sd_rhombus(p_in: vec2f, b: vec2f) -> f32 {   // exact 2D rhombus, half-diagonals b (iq)
    let p = abs(p_in);
    let h = clamp(((b.x - 2.0f * p.x) * b.x - (b.y - 2.0f * p.y) * b.y) / dot(b, b), -1.0f, 1.0f);
    let d = length(p - 0.5f * b * vec2f(1.0f - h, 1.0f + h));
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}
fn diamond_angle(k: i32) -> f32 { return f32(k) * 0.78539816f; }
// Signed distance (cm) from a world point to diamond k (negative inside).
fn diamond_sdf(p: vec3f, k: i32) -> f32 {
    let th = diamond_angle(k);
    let er = vec2f(cos(th), sin(th));
    let et = vec2f(-er.y, er.x);
    let lr = dot(p.xy, er) - R_DIAMOND; let lt = dot(p.xy, et);
    let q = select(vec2f(lt, lr), vec2f(lr, lt), (k & 1) == 0);
    let hb = p.z - stator_z(length(p.xy));     // height above the local stator surface
    let d2 = sd_rhombus(q, vec2f(DIAMOND_HALF_LEN, DIAMOND_HALF_WID));
    // the pyramid cap: the plane of the facet over q, as a distance
    let df = (hb - DIAMOND_HE - (DIAMOND_H - DIAMOND_HE) * (1.0f - abs(q.x) / DIAMOND_HALF_LEN - abs(q.y) / DIAMOND_HALF_WID))
                   * inverseSqrt(1.0f + DIAMOND_KX * DIAMOND_KX + DIAMOND_KY * DIAMOND_KY);
    let wv = vec2f(d2 + DIAMOND_ROUND, max(df, -hb - DIAMOND_H) + DIAMOND_ROUND);
    return min(max(wv.x, wv.y), 0.0f) + length(max(wv, vec2f(0.0f))) - DIAMOND_ROUND;
}
// ==== END SHARED GEOMETRY ====

// ---------------------------------------------------------------------------------------------
// Dynamics constants. [cited] page read, [snippet] search result only, chosen = picked by us.
const SUB_HZ: f32       = 2400.0f;     // sub-step rate (chosen: no tunnelling, see header)
const K_AIR: f32        = 1.05e-4f;    // 1/cm: rho Cd A / 2m, rho 1.2e-3 g/cm3, Cd 0.47, A pi cm2, m 8.4 g
const MU_ROLL: f32      = 0.016f;      // rolling resistance of the free ball on veneer and the rotor
const MU_RIM: f32       = 0.006f;      // ... on the polished stone track (the rim phase, and the free
                                       //   ball on the stone): with MU_WALL and air drag, fitted to
                                       //   Small & Tse's lap times (chosen, see the header)
const R_TRACK_IN: f32   = 34.0f;       // the polished stone ball track: from here to the lip
const MIN_REVS: f32     = 4.0f;        // a spin counts only with >= 4 ball revolutions [snippet]
const MU_WALL: f32      = 0.004f;      // scrub loss at the wall contact (chosen: fitted, as MU_RIM)
const MU_SLIDE: f32     = 0.25f;       // Coulomb friction resin on lacquer / wood (chosen)
const MU_CHROME: f32    = 0.10f;       // ... on polished chrome: frets, diamonds (chosen)
const K_PIVOT: f32      = 0.002f;      // pivot friction: spin about the normal decays in ~0.5 s
const E_SURF: f32       = 0.40f;       // restitution on track / ring / floor / cone (chosen)
const E_CHROME: f32     = 0.55f;       // restitution on frets, diamonds, rotor rim (chosen)
const V_REST: f32       = 12.0f;       // below this normal speed a contact does not bounce
const ROLL_K: f32       = 1.4f;        // 1 + I/(m R^2) for a solid sphere
const ROTOR_DECEL: f32  = 0.006f;      // rad/s^2 bearing friction (chosen)
const ROTOR_DRAG: f32   = 0.0025f;     // 1/s velocity-proportional drag (chosen)
const SETTLE_V: f32     = 2.0f;        // cm/s relative to the rotor
const SETTLE_T: f32     = 0.4f;        // s at rest in a pocket before the lock
// Spin cycle (s). Phase 0 timeline: the hand closes over the ball in its pocket (the hand is not
// drawn; from straight above its fingers would hide the ball, so the ball fades out there, in the
// pocket), lifts it and carries it off (hidden), the rotor push, the ball brought back (hidden),
// set on the track (it fades in as the fingers open) and thrown. No ball ever floats in the air.
const T_GRIP: f32       = 0.15f;       // the hand closes over the ball in its pocket: it fades out
const T_LIFT: f32       = 0.3f;        // lifted Z_HAND, decoupling from the rotor (hidden)
const T_CARRY: f32      = 1.0f;        // ... carried out past the bowl (hidden)
const T_PUSH0: f32      = 1.2f;        // the rotor push: brake, hold, two pushes (T_PUSH long)
const T_PUSH: f32       = 1.85f;
const T_PLACE: f32      = 3.1f;        // the hand brings the ball back ...
const T_LAUNCH: f32     = 3.7f;        // ... sets it on the track and throws it
const T_LOWER: f32      = 0.12f;       // the fingers open over the ball on the track: it fades in
const T_THROW: f32      = 0.08f;
const Z_HAND: f32       = 15.0f;       // the hand carries the ball above the turret (cm)
const T_SETTLED: f32    = 10.0f;       // time the ball rides in its pocket (a ~34 s cycle)
const T_NOSPIN: f32     = 45.0f;       // safety: a spin still running after this is voided
const T_INIT_AHEAD: f32 = 3.0f;        // first frame: 3 s after a launch

struct Sim {
    phi: f32, phid: f32, phase: f32, pt: f32,   // t0
    p: vec3f,  op: f32,           // t1
    v: vec3f,  roll: f32,         // t2
    win: f32, spins: f32, dir: f32, num: f32,   // t3
    w: vec3f,  flags: f32,        // t4: spin vector (rad/s); flags = touching a diamond (counts strikes)
    th: f32, thd: f32, air: f32, slow: f32,     // t5: rim angle/speed, airborne time, settle timer
    lk: vec3f, tgt: f32,          // t6: lock (r, a_rotor, z); |phid| target of the push
    ramp0: f32, dh: f32, tl: f32, maxair: f32,  // t7: phid at push start, diamond hits, time since launch, max air
}

fn sim_load(row: u32) -> Sim {
    var s: Sim;
    let a = textureLoad(argus_state, vec2u(0u, row), 0); let b = textureLoad(argus_state, vec2u(1u, row), 0); let c = textureLoad(argus_state, vec2u(2u, row), 0); let d = textureLoad(argus_state, vec2u(3u, row), 0);
    let e = textureLoad(argus_state, vec2u(4u, row), 0); let g = textureLoad(argus_state, vec2u(5u, row), 0); let h = textureLoad(argus_state, vec2u(6u, row), 0); let k = textureLoad(argus_state, vec2u(7u, row), 0);
    s.phi = a.x; s.phid = a.y; s.phase = a.z; s.pt = a.w;
    s.p = b.xyz; s.op = b.w; s.v = c.xyz; s.roll = c.w;
    s.win = d.x; s.spins = d.y; s.dir = d.z; s.num = d.w;
    s.w = e.xyz; s.flags = e.w; s.th = g.x; s.thd = g.y; s.air = g.z; s.slow = g.w;
    s.lk = h.xyz; s.tgt = h.w; s.ramp0 = k.x; s.dh = k.y; s.tl = k.z; s.maxair = k.w;
    return s;
}
fn sim_texel(s: Sim, i: u32) -> vec4f {
    switch (i) {
        case 0u: { return vec4f(s.phi, s.phid, s.phase, s.pt); }
        case 1u: { return vec4f(s.p, s.op); }
        case 2u: { return vec4f(s.v, s.roll); }
        case 3u: { return vec4f(s.win, s.spins, s.dir, s.num); }
        case 4u: { return vec4f(s.w, s.flags); }
        case 5u: { return vec4f(s.th, s.thd, s.air, s.slow); }
        case 6u: { return vec4f(s.lk, s.tgt); }
        default: { return vec4f(s.ramp0, s.dh, s.tl, s.maxair); }
    }
}

// Per-spin random numbers: spin index n, channel k.
fn spin_rand(seed: u32, n: u32, k: u32) -> f32 { return argus_rand(vec2u(n, k), seed); }
fn spin_dir(seed: u32, n: u32) -> f32 {       // rotor direction alternates spin to spin
    let d0 = select(-1.0f, 1.0f, spin_rand(seed, 0u, 3u) < 0.5f);
    return select(d0, -d0, (n & 1u) != 0u);
}
// The push: 0.25-0.34 rev/s (2.9-4 s a turn, inside Small & Tse's 2-4 s). Capped at 0.34 so that at
// the app's default 30 FPS the 37 frets move at most 0.42 pocket a frame: below the wagon-wheel
// limit (0.5), so neither the frets nor the numerals can seem to run backwards (see the draw).
fn spin_target(seed: u32, n: u32) -> f32 { return TAU_F * (0.25f + 0.09f * spin_rand(seed, n, 2u)); }
fn wrap_pi(a: f32) -> f32 { return a - TAU_F * floor((a + PI_F) / TAU_F); }

// Ball spin while it rolls against the wall: no slip at the wall and at the track contact.
fn rim_spin(th: f32, thd: f32) -> vec3f {
    let v = thd * R_BALL_RIM;   // signed tangential speed
    let sb = sin(ALPHA_TRACK); let cb = cos(ALPHA_TRACK); let sg = sin(WALL_LEAN); let cg = cos(WALL_LEAN);
    let det = cg * cb + sg * sb;
    let er = vec2f(cos(th), sin(th));
    let wz = -v * (cb + sg) / (R_BALL * det); let wr = -v * (cg - sb) / (R_BALL * det);
    return vec3f(wr * er, wz);
}
fn place_on_rim(s: ptr<function, Sim>) {
    s.p = vec3f(R_BALL_RIM * cos(s.th), R_BALL_RIM * sin(s.th), Z_BALL_RIM);
    s.v = vec3f(-sin(s.th), cos(s.th), 0.0f) * (s.thd * R_BALL_RIM);
    s.w = rim_spin(s.th, s.thd);
}
fn launch(s: ptr<function, Sim>, seed: u32) {
    let n = u32(s.spins + 0.5f);   // index of this spin
    let speed = TAU_F * (1.05f + 0.40f * spin_rand(seed, n, 0u));    // rad/s: first lap 0.71-0.99 s
    s.th = -0.5f * PI_F + 0.5f * (spin_rand(seed, n, 1u) - 0.5f);           // croupier's side
    // the ball runs against the rotor as it turns now (the rule), whatever the push meant to do
    s.dir = select(spin_dir(seed, n), sign(s.phid), abs(s.phid) > 0.05f);
    s.thd = -s.dir * speed * 0.02f;   // against the rotor; the throw ramps it
    s.ramp0 = -s.dir * speed;
    s.phase = 1.0f; s.pt = 0.0f; s.tl = 0.0f; s.op = 1.0f;   // (air counts the rim's revolutions)
    s.win = -1.0f; s.num = -1.0f; s.air = 0.0f; s.slow = 0.0f; s.dh = 0.0f; s.maxair = 0.0f;
    s.spins = f32(n + 1u);
    place_on_rim(s);
}

// One contact: push out, restitution, Coulomb friction on the slip, rolling and pivot loss.
// n points from the surface to the ball centre; u is the surface velocity at the contact.
// (Metal's defaults mur = MU_ROLL, piv = K_PIVOT, mus = MU_SLIDE are passed explicitly here.)
fn resolve(s: ptr<function, Sim>, n: vec3f, pen: f32, u: vec3f, e: f32, mur: f32, piv: f32, mus: f32) {
    s.p += n * pen;
    let vn = dot(s.v - u, n);
    if (vn >= 0.0f) { return; }
    let ee = select(0.0f, e, -vn > V_REST);
    let jn = -(1.0f + ee) * vn;   // normal impulse per unit mass
    s.v += jn * n;
    var slip = (s.v - u) + cross(s.w, -R_BALL * n);
    slip -= dot(slip, n) * n;
    let sl = length(slip);
    if (sl > 1e-6f) {
        let jt = min(mus * jn, sl / 3.5f);          // 3.5 = 1/m + R^2/I per unit mass
        let sh = slip / sl;
        s.v -= jt * sh;
        s.w += (jt / (0.4f * R_BALL)) * cross(n, sh);
    }
    var vt = s.v - u; vt -= dot(vt, n) * n;
    let vl = length(vt);
    if (vl > 1e-6f) {
        let dv = -(min(mur * jn, vl) / vl) * vt;
        s.v += dv;
        s.w += cross(n, dv) / R_BALL;   // keeps the rolling relation
    }
    s.w -= n * (dot(s.w, n) * min(1.0f, piv * jn));
}

// Closest point on a 2D segment.
fn seg_closest(p: vec2f, a: vec2f, b: vec2f) -> vec2f {
    let ab = b - a;
    return a + ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0f, 1.0f);
}
// Contact against a profile point q (r, z) in the axisymmetric frame. Returns penetration.
// (Metal's defaults mur = MU_ROLL, piv = K_PIVOT are passed explicitly here.)
fn profile_contact(s: ptr<function, Sim>, pr: vec2f, q: vec2f, er: vec2f, rotor_w: f32, e: f32, mur: f32, piv: f32) -> bool {
    let d = pr - q;
    let dl = length(d);
    if (dl >= R_BALL || dl < 1e-6f) { return false; }
    let n2 = d / dl;
    let n = vec3f(n2.x * er, n2.y);
    let c = vec3f(q.x * er, q.y);   // contact point, world
    let u = vec3f(-c.y, c.x, 0.0f) * rotor_w;
    resolve(s, n, R_BALL - dl, u, e, mur, piv, MU_SLIDE);
    return true;
}

// Events of one sub-step (the safety check reads nospin).
struct Ev { left_rim: bool, entered_rotor: bool, locked: bool, nospin: bool, escaped: bool, wall: bool, pen_max: f32, }
fn ev_none() -> Ev { var e: Ev; e.left_rim = false; e.entered_rotor = false; e.locked = false; e.nospin = false; e.escaped = false; e.wall = false; e.pen_max = 0.0f; return e; }

// The free ball: phases 2 and 3.
fn free_substep(s: ptr<function, Sim>, h: f32, ev: ptr<function, Ev>) {
    s.v.z -= G_ACC * h;
    s.v -= (K_AIR * length(s.v) * h) * s.v;
    s.p += s.v * h;
    var touch = false; var floor_touch = false;
    let dtouch_prev = s.flags;
    var dtouch = 0.0f;
    var r = length(s.p.xy);
    var er = select(vec2f(1.0f, 0.0f), s.p.xy / r, r > 1e-4f);
    var pr = vec2f(r, s.p.z);

    // --- static stator curve (Newton on the closest point of the quadratic) ---
    if (r > R_STATOR_IN - 1.5f) {
        var x = clamp(r - R_STATOR_IN, 0.0f, R_RIM_WALL - R_STATOR_IN);
        for (var it = 0; it < 3; it++) {
            let zx = stator_curve_z(x + R_STATOR_IN); let sx = stator_slope(x + R_STATOR_IN); let cx = stator_curv(x + R_STATOR_IN);
            let g1 = (x + R_STATOR_IN - pr.x) + (zx - pr.y) * sx;
            let g2 = 1.0f + sx * sx + (zx - pr.y) * cx;
            x = clamp(x - g1 / g2, 0.0f, R_RIM_WALL - R_STATOR_IN);
        }
        let q = vec2f(R_STATOR_IN + x, stator_curve_z(R_STATOR_IN + x));
        if (profile_contact(s, pr, q, er, 0.0f, E_SURF, select(MU_ROLL, MU_RIM, q.x >= R_TRACK_IN), K_PIVOT)) { touch = true; ev.pen_max = max(ev.pen_max, 0.0f); }
        // the back-track wall and the rim top
        r = length(s.p.xy); er = s.p.xy / max(r, 1e-4f); pr = vec2f(r, s.p.z);
        if (r > R_RIM_WALL - 1.5f) {
            if (profile_contact(s, pr, seg_closest(pr, vec2f(R_RIM_WALL, Z_WALL_FOOT), vec2f(R_WALL_TOP, Z_RIM_TOP)), er, 0.0f, E_SURF, MU_WALL, 0.0f)) { touch = true; ev.wall = true; }
            r = length(s.p.xy); er = s.p.xy / max(r, 1e-4f); pr = vec2f(r, s.p.z);
            if (profile_contact(s, pr, seg_closest(pr, vec2f(R_WALL_TOP, Z_RIM_TOP), vec2f(R_RIM_OUT, Z_RIM_TOP)), er, 0.0f, E_SURF, MU_ROLL, K_PIVOT)) { touch = true; }
        }
    }
    // --- diamonds (static) ---
    r = length(s.p.xy);
    if (abs(r - R_DIAMOND) < DIAMOND_HALF_LEN + R_BALL + 0.2f) {
        let ang = atan2(s.p.y, s.p.x);
        let k = i32(floor(ang / 0.78539816f + 0.5f + 8.0f)) & 7;
        let d = diamond_sdf(s.p, k);
        if (d < R_BALL) {
            let ep = 0.004f;
            var n = vec3f(diamond_sdf(s.p + vec3f(ep, 0.0f, 0.0f), k) - diamond_sdf(s.p - vec3f(ep, 0.0f, 0.0f), k),
                          diamond_sdf(s.p + vec3f(0.0f, ep, 0.0f), k) - diamond_sdf(s.p - vec3f(0.0f, ep, 0.0f), k),
                          diamond_sdf(s.p + vec3f(0.0f, 0.0f, ep), k) - diamond_sdf(s.p - vec3f(0.0f, 0.0f, ep), k));
            n = normalize(n + vec3f(0.0f, 0.0f, 1e-7f));
            if (dtouch_prev < 0.5f) { s.dh += 1.0f; }                  // a new strike
            dtouch = 1.0f;
            resolve(s, n, R_BALL - d, vec3f(0.0f), E_CHROME, MU_ROLL, K_PIVOT, MU_CHROME);
            ev.pen_max = max(ev.pen_max, R_BALL - d);
            touch = true;
        }
    }
    // --- rotor profile (rotating; axisymmetric) ---
    r = length(s.p.xy); er = s.p.xy / max(r, 1e-4f); pr = vec2f(r, s.p.z);
    if (r < R_ROTOR_OUT + 1.2f) {
        let wv = s.phid;
        // turret wall, cone
        if (r < R_TURRET + 1.2f) {   // the turret: its drawn profile
            var qa = vec2f(TURRET_PR[0], turret_z(TURRET_PR[0]));
            for (var i = 1; i < 12; i++) {
                let qb = vec2f(TURRET_PR[i], turret_z(TURRET_PR[i]));
                pr = vec2f(length(s.p.xy), s.p.z);
                if (profile_contact(s, pr, seg_closest(pr, qa, qb), er, wv, E_CHROME, MU_ROLL, K_PIVOT)) { touch = true; }
                qa = qb;
            }
        }
        if (r < KNOB_AT + KNOB_R + R_BALL + 0.3f && s.p.z > ARM_Z - KNOB_R - R_BALL - 0.3f) {
            // the handle: the nearest arm (a capsule) and its knob, turning with the rotor
            let qa = 1.5707963f;
            let aq = atan2(s.p.y, s.p.x) - s.phi - ARM_A0;
            let fa = ARM_A0 + qa * round_m(aq / qa) + s.phi;
            let eu = vec3f(cos(fa), sin(fa), 0.0f);
            let a0 = eu * ARM_R0 + vec3f(0.0f, 0.0f, ARM_Z); let a1 = eu * ARM_R1 + vec3f(0.0f, 0.0f, ARM_Z);
            let ta = saturate(dot(s.p - a0, a1 - a0) / dot(a1 - a0, a1 - a0));
            let qs = a0 + (a1 - a0) * ta;
            let kc = eu * KNOB_AT + vec3f(0.0f, 0.0f, ARM_Z);
            for (var part = 0; part < 2; part++) {
                let c0 = select(kc, qs, part == 0);
                let rad = select(KNOB_R, arm_radius(ta), part == 0);
                let d = s.p - c0;
                let dl = length(d);
                if (dl < rad + R_BALL && dl > 1e-5f) {
                    let n = d / dl; let c = c0 + n * rad;
                    resolve(s, n, rad + R_BALL - dl, vec3f(-c.y, c.x, 0.0f) * wv, E_CHROME, MU_ROLL, K_PIVOT, MU_SLIDE);
                    touch = true;
                }
            }
        }
        if (r < R_POCKET_IN + 1.2f) {
            pr = vec2f(length(s.p.xy), s.p.z);
            if (profile_contact(s, pr, seg_closest(pr, vec2f(R_CONE_IN, Z_CONE_TOP), vec2f(R_POCKET_IN, Z_CONE_OUT)), er, wv, E_SURF, MU_ROLL, K_PIVOT)) { touch = true; }
        }
        // pocket floor arc
        pr = vec2f(length(s.p.xy), s.p.z);
        if (pr.x > R_POCKET_IN - 1.2f && pr.x < R_NUM_IN + 1.2f) {
            let cc = vec2f(R_DISH_C, Z_POCKET + R_DISH);
            let d = pr - cc;
            let dl = length(d);
            if (dl > 1e-4f) {
                let q = cc + d * (R_DISH / dl);
                if (q.x >= R_POCKET_IN && q.x <= R_NUM_IN && q.y < cc.y && R_DISH - dl < R_BALL) {
                    let n2 = -d / dl;
                    let n = vec3f(n2.x * er, n2.y);
                    let c = vec3f(q.x * er, q.y);
                    resolve(s, n, R_BALL - (R_DISH - dl), vec3f(-c.y, c.x, 0.0f) * wv, E_SURF, MU_ROLL, K_PIVOT, MU_SLIDE);
                    touch = true; floor_touch = true;
                }
            }
        }
        // pocket step, number ring, rotor rim
        pr = vec2f(length(s.p.xy), s.p.z);
        if (pr.x > R_NUM_IN - 1.2f) {
            if (profile_contact(s, pr, seg_closest(pr, vec2f(R_NUM_IN, Z_DISH_OUT), vec2f(R_NUM_IN, Z_NUM_IN)), er, wv, E_SURF, MU_ROLL, K_PIVOT)) { touch = true; }
            pr = vec2f(length(s.p.xy), s.p.z);
            if (profile_contact(s, pr, seg_closest(pr, vec2f(R_NUM_IN, Z_NUM_IN), vec2f(R_NUM_OUT, Z_NUM_OUT)), er, wv, E_SURF, MU_ROLL, K_PIVOT)) { touch = true; }
            pr = vec2f(length(s.p.xy), s.p.z);
            if (profile_contact(s, pr, seg_closest(pr, vec2f(R_NUM_OUT, Z_NUM_OUT), vec2f(R_ROTOR_OUT, Z_ROTOR_RIM)), er, wv, E_CHROME, MU_ROLL, K_PIVOT)) { touch = true; }
        }
        // frets: the two that bound the ball's slot, as rounded boxes in the rotating frame
        r = length(s.p.xy);
        if (r > R_FRET_IN - 1.2f && r < R_FRET_OUT + 1.2f && s.p.z < Z_FRET_TOP + 1.2f) {
            let a_rot = atan2(s.p.y, s.p.x) - s.phi;
            let sc = (POCKET_A0 - a_rot) / POCKET_DA;
            let j = floor(sc + 0.5f);
            for (var side = 0; side < 2; side++) {
                let fa = POCKET_A0 - (j + select(0.5f, -0.5f, side == 0)) * POCKET_DA + s.phi;  // world angle
                let eu = vec2f(cos(fa), sin(fa)); let ew = vec2f(-eu.y, eu.x);
                let loc = vec3f(dot(s.p.xy, eu), dot(s.p.xy, ew), s.p.z);
                let cen = vec3f(0.5f * (R_FRET_IN + R_FRET_OUT), 0.0f, 0.5f * Z_FRET_TOP);
                let hal = vec3f(0.5f * (R_FRET_OUT - R_FRET_IN), FRET_HALF_W, 0.5f * Z_FRET_TOP) - FRET_HALF_W;
                let rel = loc - cen;
                let q = abs(rel) - hal;
                let qp = max(q, vec3f(0.0f));
                let ql = length(qp);
                let d = ql + min(max(q.x, max(q.y, q.z)), 0.0f) - FRET_HALF_W;
                if (d < R_BALL) {
                    var nl: vec3f;
                    if (ql > 1e-6f) { nl = qp / ql * sign(rel); }
                    else { nl = select(select(vec3f(sign(rel.x), 0.0f, 0.0f), vec3f(0.0f, 0.0f, sign(rel.z)), q.z >= q.x), vec3f(0.0f, sign(rel.y), 0.0f), q.y >= q.x && q.y >= q.z); }
                    let n = vec3f(nl.x * eu + nl.y * ew, nl.z);
                    let c = s.p - n * R_BALL;
                    resolve(s, n, R_BALL - d, vec3f(-c.y, c.x, 0.0f) * wv, E_CHROME, MU_ROLL, K_PIVOT, MU_CHROME);
                    ev.pen_max = max(ev.pen_max, R_BALL - d);
                    touch = true;
                }
            }
        }
    }

    // bookkeeping
    s.flags = dtouch;
    s.roll = (s.roll + length(s.w) * h) % TAU_F;
    s.air = select(s.air + h, 0.0f, touch);
    s.maxair = max(s.maxair, s.air);
    r = length(s.p.xy);
    if (s.phase < 2.5f && r < R_STATOR_IN - 0.5f) { s.phase = 3.0f; s.pt = 0.0f; ev.entered_rotor = true; }
    if (s.phase > 2.5f) {
        let u = vec3f(-s.p.y, s.p.x, 0.0f) * s.phid;
        let slow = floor_touch && length(s.v - u) < SETTLE_V && s.p.z < Z_POCKET + R_BALL + 0.4f
                       && r > R_POCKET_IN && r < R_NUM_IN;
        s.slow = select(0.0f, s.slow + h, slow);
        if (s.slow > SETTLE_T) {
            let a_rot = wrap_pi(atan2(s.p.y, s.p.x) - s.phi);
            s.lk = vec3f(r, a_rot, s.p.z);
            s.phase = 4.0f; s.pt = 0.0f;
            s.win = f32(slot_at(a_rot));
            s.num = f32(EU_SEQ[slot_at(a_rot)]);
            ev.locked = true;
        }
    }
    if (r > R_RIM_OUT - 0.5f || s.p.z < 0.5f) { ev.escaped = true; ev.nospin = true; }
    if (s.tl > T_NOSPIN) { ev.nospin = true; }
}

fn void_spin(s: ptr<function, Sim>) {             // croupier calls "no spin" (safety)
    let r = length(s.p.xy);
    s.lk = vec3f(r, wrap_pi(atan2(s.p.y, s.p.x) - s.phi), s.p.z);
    s.phase = 0.0f; s.pt = 0.0f; s.win = -1.0f; s.num = -1.0f;
    s.th = atan2(s.p.y, s.p.x); s.thd = 0.0f;
}

// The ball leaves the wall. A spin counts only with >= MIN_REVS revolutions of the ball (N.J.A.C.
// 13:69E; Singapore GRA rules [snippet]): a ball that leaves sooner is a "no spin", picked up and
// thrown again (the launch range gives >= 8 revolutions: never seen in the bench).
fn leave_rim(s: ptr<function, Sim>, ev: ptr<function, Ev>) {
    place_on_rim(s);
    if (s.air < MIN_REVS) { ev.nospin = true; void_spin(s); return; }
    s.phase = 2.0f; s.pt = 0.0f; s.air = 0.0f; ev.left_rim = true;
}

// One sub-step of everything.
fn substep(s: ptr<function, Sim>, h: f32, seed: u32, ev: ptr<function, Ev>) {
    // rotor
    let pushing = s.phase < 0.5f && s.pt >= T_PUSH0 && s.pt < T_PUSH0 + T_PUSH;
    if (pushing) {
        // like a hand: brake to a stop (gripping harder at the end), hold, then two short pushes
        let tp = s.pt - T_PUSH0;
        let tg = s.dir * s.tgt;
        if (tp < 0.8f)       { s.phid = s.ramp0 * (1.0f - sq(tp / 0.8f)); }
        else if (tp < 1.1f)  { s.phid = 0.0f; }
        else if (tp < 1.35f) { s.phid = tg * 0.6f * smoothstep(1.1f, 1.35f, tp); }
        else if (tp < 1.6f)  { s.phid = tg * 0.6f; }
        else                 { s.phid = tg * (0.6f + 0.4f * smoothstep(1.6f, 1.85f, tp)); }
    } else {
        let dec = (ROTOR_DECEL * sign(s.phid) + ROTOR_DRAG * s.phid) * h;
        s.phid = select(s.phid - dec, 0.0f, abs(dec) >= abs(s.phid));
    }
    s.phi = wrap_pi(s.phi + s.phid * h);
    s.pt += h; s.tl += h;

    if (s.phase < 0.5f) {   // ---- phase 0: ball out
        let t = s.pt;
        let p_old = s.p;
        // the hand: th / thd hold the ball's world angle and the rotor rate when it was picked up
        let a_l = s.th + s.thd * (T_GRIP + 0.5f * (T_LIFT - T_GRIP));   // where the lift leaves it
        let L = vec3f(s.lk.x * cos(a_l), s.lk.x * sin(a_l), s.lk.z + Z_HAND);
        let X = vec3f(clamp(L.x, -18.0f, 18.0f), -54.0f, Z_HAND);   // over the felt, croupier's side
        if (t < T_LIFT) {   // gripped in the pocket (fading out), then up
            let tt = max(t - T_GRIP, 0.0f); let u = tt / (T_LIFT - T_GRIP);
            let a = s.th + s.thd * (min(t, T_GRIP) + tt - tt * tt / (2.0f * (T_LIFT - T_GRIP)));
            s.p = vec3f(s.lk.x * cos(a), s.lk.x * sin(a), s.lk.z + Z_HAND * (1.0f - sq(1.0f - u)));
            s.op = 1.0f - smoothstep(0.0f, T_GRIP, t);
        } else if (t < T_PLACE) {   // carried out and back, in the hand (hidden)
            s.p = mix(L, X, smoothstep(T_LIFT, T_CARRY, t));
            s.op = 0.0f;
        }
        if (t >= T_PUSH0 && t - h < T_PUSH0) {                 // the croupier's push starts
            let n = u32(s.spins + 0.5f);
            s.ramp0 = s.phid; s.dir = spin_dir(seed, n); s.tgt = spin_target(seed, n);
        }
        if (t >= T_PLACE) {   // carried in, lowered onto the track
            let n = u32(s.spins + 0.5f);
            let th = -0.5f * PI_F + 0.5f * (spin_rand(seed, n, 1u) - 0.5f);
            let T0 = vec3f(R_BALL_RIM * cos(th), R_BALL_RIM * sin(th), Z_BALL_RIM);
            let X2 = vec3f(T0.x * 0.6f, -54.0f, Z_HAND);
            s.p = mix(X2, vec3f(T0.xy, Z_HAND), smoothstep(T_PLACE, T_LAUNCH - 3.0f * T_LOWER, t));
            s.p.z = mix(Z_HAND, T0.z, smoothstep(T_LAUNCH - 3.0f * T_LOWER, T_LAUNCH - T_LOWER, t));
            s.op = smoothstep(T_LAUNCH - T_LOWER, T_LAUNCH, t);   // set on the track, then the fingers open
        }
        s.v = (s.p - p_old) / h;
        if (t >= T_LAUNCH) { launch(s, seed); }
        return;
    }
    if (s.phase < 1.5f) {   // ---- phase 1: riding the wall
        // Pinned against the wall (Small & Tse phase i). Per unit mass: track normal force
        // N_t = g / cos(alpha); wall normal force N_w = ROLL_K v^2 / r - g tan(alpha), where
        // ROLL_K = 1 + I/(m R^2) = 1.4 adds the friction that turns a rolling ball's spin as it
        // circles (a point mass has ROLL_K = 1: Small & Tse eq. 1). With ROLL_K the hand-over to
        // the free rolling ball below is seamless: it leaves the wall at the speed where the free
        // model's wall force also vanishes.
        let v = abs(s.thd) * R_BALL_RIM;
        let n_track = G_ACC / cos(ALPHA_TRACK);
        let n_wall = ROLL_K * v * v / R_BALL_RIM - G_ACC * tan(ALPHA_TRACK);
        if (s.pt < T_THROW) {   // still in the hand: the throw
            let u = s.pt / T_THROW;
            s.thd = s.ramp0 * max(u * u * (3.0f - 2.0f * u), 0.02f);
            s.th = wrap_pi(s.th + s.thd * h);
            s.air += abs(s.thd) * h / TAU_F;
            place_on_rim(s);
            return;
        }
        if (n_wall <= 0.0f) { leave_rim(s, ev); return; }     // leaves the wall: free from here
        let dec = MU_RIM * n_track + MU_WALL * n_wall + K_AIR * v * v;
        s.thd = sign(s.thd) * max(v - dec * h, 0.0f) / R_BALL_RIM;
        s.th = wrap_pi(s.th + s.thd * h);
        s.air += abs(s.thd) * h / TAU_F;
        place_on_rim(s);
        s.roll = (s.roll + length(s.w) * h) % TAU_F;
        return;
    }
    if (s.phase < 3.5f) {   // ---- phases 2, 3: free ball
        free_substep(s, h, ev);
        if (ev.nospin) { void_spin(s); }
        return;
    }
    // ---- phase 4: settled, riding with the rotor
    let a = s.lk.y + s.phi;
    s.p = vec3f(s.lk.x * cos(a), s.lk.x * sin(a), s.lk.z);
    s.v = vec3f(-s.p.y, s.p.x, 0.0f) * s.phid;
    s.w = vec3f(0.0f, 0.0f, s.phid);
    if (s.pt >= T_SETTLED) { s.phase = 0.0f; s.pt = 0.0f; s.th = atan2(s.p.y, s.p.x); s.thd = s.phid; }
}

fn sim_finite(s: Sim) -> bool {
    return isfinite_f(s.phi) && isfinite_f(s.phid) && isfinite3(s.p) && isfinite3(s.v) && isfinite3(s.w)
        && isfinite_f(s.pt) && isfinite_f(s.tl);
}

fn sim_start(seed: u32) -> Sim {
    var s: Sim;
    s.phi = TAU_F * spin_rand(seed, 0u, 5u) - PI_F;
    s.spins = 0.0f; s.dir = spin_dir(seed, 0u); s.tgt = spin_target(seed, 0u);
    s.phid = s.dir * s.tgt; s.ramp0 = s.phid;
    s.roll = 0.0f; s.flags = 0.0f; s.lk = vec3f(22.4f, 0.0f, 1.85f);
    launch(&s, seed);
    var ev = ev_none();
    let h = 1.0f / SUB_HZ;
    for (var i = 0; i < i32(T_INIT_AHEAD * SUB_HZ); i++) { substep(&s, h, seed, &ev); }   // rim only: cheap
    return s;
}


// ===================================================================== the kernels: state ==
const BAKE_TAG: f32 = 7321.0f; const Z_LIVE: f32 = 1e4f;
// State row 0: texels 0..7 are the simulation (above); 8 and 9 hold the previous tick's
// ball position + rotor angle and ball velocity + the f.time of the tick, so the draw can show
// smooth motion between 30 Hz ticks at 60/120 FPS (it shows the state one tick late, which at
// 30 FPS is exactly the previous tick; no extrapolation, so nothing overshoots).
@compute @workgroup_size(8, 8)
fn argus_init(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    if (gid.y > 0u) { textureStore(argus_state_out, gid, bake4(gid)); return; }
    if (gid.x == 10u) { textureStore(argus_state_out, gid, vec4f(f32(f.width), f32(f.height), select(0.0f, BAKE_TAG, f.width <= 4u * f.state_width && f.height < f.state_height), 0.0f)); }
    if (gid.x > 9u) { return; }
    let s = sim_start(f.seed);
    if (gid.x < 8u) { textureStore(argus_state_out, gid, sim_texel(s, gid.x)); }
    else if (gid.x == 8u) { textureStore(argus_state_out, gid, vec4f(s.p, s.phi)); }
    else if (gid.x == 9u) { textureStore(argus_state_out, gid, vec4f(s.v, f.time)); }
}

@compute @workgroup_size(8, 8)
fn argus_step(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    if (gid.y > 0u || gid.x > 9u) { if (f.frame < 3u) { textureStore(argus_state_out, gid, textureLoad(argus_state, gid, 0)); } return; }
    if (gid.x == 8u) { textureStore(argus_state_out, gid, vec4f(textureLoad(argus_state, vec2u(1u, 0u), 0).xyz, textureLoad(argus_state, vec2u(0u, 0u), 0).x)); return; }
    if (gid.x == 9u) { textureStore(argus_state_out, gid, vec4f(textureLoad(argus_state, vec2u(2u, 0u), 0).xyz, f.time)); return; }
    if (gid.x > 9u) { return; }
    let seed = f.seed;
    var s = sim_load(0u);
    let dt = clamp(f.dt, 0.0f, 0.1f);
    let n = clamp(i32(ceil(dt * SUB_HZ - 1e-3f)), 1, 240);
    let h = dt / f32(n);
    for (var i = 0; i < n && dt > 0.0f; i++) {
        var ev = ev_none();
        substep(&s, h, seed, &ev);
        if (!sim_finite(s)) { s = sim_start(seed ^ (u32(s.spins) * 2654435761u)); }
    }
    textureStore(argus_state_out, gid, sim_texel(s, gid.x));
}

// ---- look-only geometry: what the camera sees beyond the collision surfaces ----
// (the apron outside the rim, the rounded lip edge, the stone/lacquer split, the turret's shape)
const LIP_ROUND: f32  = 0.3f;         // the lip's top edge is rounded
// The bowl outside the rotor as seen from above: felt, apron, rim top over the lip, stator.
fn bowl_z(r: f32) -> f32 {
    if (r >= R_APRON_OUT) { return 0.0f; }
    if (r >= R_RIM_OUT) {   // apron: rounded shoulder to the felt
        let u = (r - R_RIM_OUT) / (R_APRON_OUT - R_RIM_OUT);
        return Z_RIM_TOP * sqrt(max(1.0f - sq(sq(u)), 0.0f));
    }
    if (r >= R_WALL_TOP) {   // rim top, its lip edge rounded
        let e = saturate((R_WALL_TOP + LIP_ROUND - r) / LIP_ROUND);
        return Z_RIM_TOP - LIP_ROUND * (1.0f - sqrt(max(1.0f - e * e, 0.0f)));
    }
    if (r >= R_STATOR_IN) { return stator_z(r); }
    return Z_ROTOR_RIM - 0.25f;   // the seam between stator and rotor (a shallow groove)
}

// ============================================================== the state ==
struct WheelState {
    rotor: f32, rotor_vel: f32,          // rotor angle (rad), rate (rad/s)
    ball: vec3f, ball_vel: vec3f,        // ball centre (cm, world), velocity (cm/s)
    ball_roll: f32, ball_alpha: f32,     // rolling angle (not drawn: it aliases on the rim), opacity
    winner: i32,                         // pocket index (EU_SEQ order) or -1
}

// The state the draw sees, between two 30 Hz ticks (see the kernels above).
fn wheel_state(time: f32) -> WheelState {
    let t0 = textureLoad(argus_state, vec2u(0u, 0u), 0); let t1 = textureLoad(argus_state, vec2u(1u, 0u), 0); let t2 = textureLoad(argus_state, vec2u(2u, 0u), 0);
    let t3 = textureLoad(argus_state, vec2u(3u, 0u), 0); let t8 = textureLoad(argus_state, vec2u(8u, 0u), 0); let t9 = textureLoad(argus_state, vec2u(9u, 0u), 0);
    var tau = time - t9.w;
    if (tau < -1.0f) { tau += ARGUS_TIME_PERIOD; }                 // f.time wrapped between the two
    let al = saturate(tau * 30.0f);
    var S: WheelState;
    S.rotor = wrap_pi(t8.w + wrap_pi(t0.x - t8.w) * al);
    S.rotor_vel = t0.y;
    // the ball, in polar coordinates about the axis (it circles: a straight blend would cut in)
    var p0 = t8.xyz;
    let p1 = t1.xyz;
    if (distance(p0, p1) > 30.0f) { p0 = p1; }   // placed on the track, or a reset
    let a0 = atan2(p0.y, p0.x); let a = a0 + wrap_pi(atan2(p1.y, p1.x) - a0) * al;
    let rr = mix(length(p0.xy), length(p1.xy), al);
    S.ball = vec3f(rr * cos(a), rr * sin(a), mix(p0.z, p1.z, al));
    S.ball_vel = mix(t9.xyz, t2.xyz, al);
    S.ball_roll = t2.w;
    S.ball_alpha = saturate(t1.w);
    S.winner = i32(t3.x);
    return S;
}

// ============================================================== the look ==
// Camera: a pinhole straight above the wheel centre.
const H_EYE: f32  = 270.0f;          // camera height above the felt (cm)
const FC: f32     = 5.10f;           // focal length in argus_uv units: bowl ~87% of the height
// The hall: a casino ceiling 3 m above the felt, carrying rows of recessed warm-white linear
// slots. Over the table a light box (a lit panel with two slots); elsewhere the hall's own rows,
// dimmer and broken into fixtures. Around the table, D_ROOM away, the hall's walls, other tables
// and their lamps. All of it is fixed in the world: what turns moves under still highlights.
const HC: f32      = 300.0f;
const PITCH: f32   = 110.0f;         // slot spacing (across)
const SLOT_W: f32  = 14.0f;          // slot width
const SEG_L: f32   = 205.0f;         // the light box's slots: lit length
const HALL_L: f32  = 90.0f;          // the hall's fixtures: lit length along a row ...
const ROW_P: f32   = 240.0f;         // ... repeating every ROW_P
const CAN_C: vec2f  = vec2f(-70.0f, 0.0f);     // the light box's centre (slot frame): over the
                                               //   layout, 94 cm off the wheel's axis (17 deg)
const CAN_H: vec2f  = vec2f(72.0f, 88.0f);     // its half extents: 2 slots, 1.8 m long
const CEIL_DARK: vec3f = vec3f(0.090f, 0.083f, 0.075f);   // the ceiling between fixtures (mean)
const SLOT_FAR: f32 = 0.30f;        // the hall's slots, relative to the table's light box
const D_ROOM: f32 = 450.0f;         // horizontal distance to the walls and the other tables
const R_COFFER: f32 = 215.0f;       // the dark coffer over the table: no hall fixtures within this
                                    //   radius of the wheel's axis (the light box hangs in it)
// The other tables' lamps, seen on the walls: 5 at fixed, uneven azimuths (rad from the -x axis,
// CCW), widths (rad) and strengths (relative to WARM)
const LAMP_AZ = array<f32, 5>(0.40f, 1.25f, 2.90f, 3.50f, 5.00f);
const LAMP_W = array<f32, 5>(0.45f, 0.25f, 0.60f, 0.30f, 0.40f);
const LAMP_I = array<f32, 5>(1.00f, 0.55f, 0.80f, 0.40f, 0.70f);
const CEIL_OFF: vec2f = vec2f(23.0f, 7.9f);     // the grid's offset from the wheel axis
const CEIL_ROT: f32 = 0.33f;        // the slots' angle to the screen's x axis (rad)
const BOX_W: vec3f   = vec3f(-89.22f, -30.58f, 300.0f);   // the light box's centre, world (from the above)
const WARM: vec3f    = vec3f(1.00f, 0.84f, 0.66f);  // ~3500 K
const SLOT_L: vec3f  = WARM * 15.0f; // diffuser 0.55x, core 1.55x
const CEIL_L: vec3f  = vec3f(0.20f, 0.185f, 0.165f);   // the light box's panel, lit by its slots
const WALL_L: vec3f  = vec3f(0.24f, 0.19f, 0.15f);    // the hall's walls and tables, lit
const CHROME: vec3f  = vec3f(0.60f, 0.60f, 0.61f);    // electroplated chromium, F0 ~0.6 neutral
// Materials (linear albedo).
const FELT: vec3f    = vec3f(0.006f, 0.040f, 0.062f);
const RED_L: vec3f   = vec3f(0.42f, 0.018f, 0.012f);
const BLK_L: vec3f   = vec3f(0.008f, 0.008f, 0.009f);
const GRN_L: vec3f   = vec3f(0.010f, 0.17f, 0.050f);
const CREAM: vec3f   = vec3f(0.80f, 0.80f, 0.78f);   // the numerals' white
const WOOD_A: vec3f  = vec3f(0.120f, 0.044f, 0.020f);  // mahogany veneer, light / dark figure
const WOOD_B: vec3f  = vec3f(0.060f, 0.021f, 0.010f);
const BOWL_DK: f32 = 0.45f;         // the bowl's rim and apron: the same veneer, stained darker
const LIGHT_AZ: f32 = -2.811f;      // azimuth of the light box seen from the axis (BOX_W)
const STONE: vec3f   = vec3f(0.010f, 0.010f, 0.012f);
const STONE_MEAN: vec3f = vec3f(0.0110f, 0.0110f, 0.0125f);   // the track's albedo: near-black
const LACQ_BK: vec3f = vec3f(0.006f, 0.006f, 0.007f);
const BALL_C: vec3f  = vec3f(0.86f, 0.85f, 0.82f);   // PTFE: a high-albedo volume scatterer
const POCKET_MEAN: vec3f = (18.0f * RED_L + 18.0f * BLK_L + GRN_L) / 37.0f;
// The camera's exposure time (s): the same at every frame rate (see shade_px).
const SHUTTER: f32     = 1.0f / 120.0f;
// Satin finishes. Only chrome is a mirror; every dielectric is a GGX surface of perceptual roughness
// `rough` (alpha = rough^2), dielectric F0 0.04. env() integrates a box lobe; it takes the GGX
// reflected lobe's full width at half maximum: the half-vector's HWHM is 0.64 alpha (small alpha),
// the reflection turns twice as far, so 2.57 alpha (COMPUTED). The tails of GGX are left out (the
// box has none): the satin highlights come out a little more contained than a true GGX glow.
const F0_COAT: f32     = 0.04f;      // clear coat, lacquer, stone resin: n ~1.5
const ROUGH_BOWL: f32  = 0.32f;      // the bowl's rim and apron: satin lacquered veneer
const ROUGH_VEN: f32   = 0.30f;      // the lower stator's veneer
const ROUGH_CONE: f32  = 0.28f;      // the cone's veneer
const ROUGH_RING: f32  = 0.32f;      // the number ring's lacquer
const ROUGH_POCK: f32  = 0.40f;      // the pocket floors' lacquer
const ROUGH_STONE: f32 = 0.40f;      // the stone track: honed satin
const ROUGH_BALL: f32  = 0.22f;      // the PTFE ball: satin
const F0_BALL: f32     = 0.03f;      // PTFE, n ~1.35-1.4
const LOBE_CHROME: f32 = 0.006f;     // chrome: a mirror (its lobe in rad)
fn ggx_lobe(rough: f32) -> f32 { return 2.57f * rough * rough; }
// The split-sum environment BRDF for a rough dielectric (Karis 2014, "Physically Based Shading on
// Mobile", the analytic fit): Fresnel integrated over the GGX lobe. At normal view it is F0; at
// grazing it reaches ~0.38 for roughness 0.3 instead of Schlick's 1.0, so a satin edge seen
// edge-on is not a wet mirror band.
fn env_brdf(F0: f32, rough: f32, ndv: f32) -> f32 {
    let rr = rough * vec4f(-1.0f, -0.0275f, -0.572f, 0.022f) + vec4f(1.0f, 0.0425f, 1.04f, -0.04f);
    let a004 = min(rr.x * rr.x, exp2(-9.28f * ndv)) * rr.x + rr.y;
    let AB = vec2f(-1.04f, 1.04f) * a004 + rr.zw;
    return F0 * AB.x + AB.y;
}

// Box-filtered coverage of a periodic train of lit intervals (width `on`, period `per`,
// centred at (n + 0.5) * per), averaged over [x - w/2, x + w/2]: exact for any w.
fn train_F(x: f32, per: f32, on: f32) -> f32 {
    let q = floor(x / per);
    return q * on + clamp(x - q * per - 0.5f * (per - on), 0.0f, on);
}
fn train_cov(x: f32, w: f32, per: f32, on: f32) -> f32 {
    return (train_F(x + 0.5f * w, per, on) - train_F(x - 0.5f * w, per, on)) / w;
}
fn box_cov(x: f32, w: f32, h: f32) -> f32 {     // [-h, h] over [x - w/2, x + w/2]
    return (clamp(x + 0.5f * w, -h, h) - clamp(x - 0.5f * w, -h, h)) / w;
}
fn ceil_coords(c_in: vec2f) -> vec2f {      // world xy on the ceiling -> slot frame
    let cs = cos(CEIL_ROT); let sn = sin(CEIL_ROT);
    let c = c_in + CEIL_OFF;
    return vec2f(cs * c.x + sn * c.y, -sn * c.x + cs * c.y);
}
// Mean luminance of the lit ceiling (for diffuse light).
const CEIL_AVG: vec3f = WARM * 15.0f * (0.55f * 14.0f + 0.45f * 14.0f) / 110.0f * (205.0f / 240.0f) + vec3f(0.20f, 0.185f, 0.165f);
const DL_UP: vec3f = CEIL_AVG * 0.62f;           // diffuse light on a surface facing up

fn schlick3(F0: vec3f, c: f32) -> vec3f {
    let m = pow(1.0f - saturate(c), 5.0f);
    return F0 + (1.0f - F0) * m;
}
fn schlick1(F0: f32, c: f32) -> f32 {
    return F0 + (1.0f - F0) * pow(1.0f - saturate(c), 5.0f);
}
// Diffuse irradiance from the ceiling (radiance units: albedo * this = outgoing radiance).
fn diffuse_light(n: vec3f) -> vec3f {
    return DL_UP * pow(saturate(0.5f + 0.5f * n.z), 1.6f);
}
// The revolution profile the camera sees (frets and diamonds are added on top).
fn scene_rev(r: f32) -> f32 {
    if (r >= R_ROTOR_OUT) { return bowl_z(r); }
    if (r < R_TURRET) { return turret_z(r); }
    return rotor_profile_z(r);   // frets are drawn on top
}

// The hall where a ray meets its walls (height hw above the felt): other tables' lit tops, people
// and machines, lit walls, and the long lamps over 7 other tables. Box-filtered over the lobe
// in height and azimuth, so a curved mirror sees soft bands, never dots.
fn room(P: vec3f, R: vec3f, blur: f32) -> vec3f {
    let h = max(length(R.xy), 1e-3f);
    let tz = R.z / h;
    let hw = P.z + D_ROOM * tz;
    let sec2 = 1.0f + tz * tz;
    let wh = blur * D_ROOM * sec2 + 1.0f;               // the lobe's footprint in height (cm)
    let waz = blur * sqrt(sec2) + 0.004f;               // ... and in azimuth (rad)
    let az = atan2(R.y, R.x) + PI_F;   // 0..2 pi
    let var_ = 0.22f * exp(-3.0f * blur) * sin(3.0f * az + 0.7f) * sin(5.0f * az + 1.3f);
    var c = WALL_L * (0.75f + var_) * (0.45f + 0.55f * box_cov(hw - 235.0f, wh, 65.0f));
    c += vec3f(0.05f, 0.10f, 0.11f) * box_cov(hw - 10.0f, wh, 14.0f);          // other tables' felt
    let band = box_cov(hw - 222.0f, wh, 22.0f);
    var lamp = 0.0f;
    if (band > 0.0f) {
        for (var k = 0; k < 5; k++) {
            lamp += LAMP_I[k] * box_cov(wrap_pi(az - LAMP_AZ[k]), waz, 0.5f * LAMP_W[k]);
        }
    }
    return c + WARM * (0.8f * lamp * band);
}
// The hall's fixtures along the slot rows: one per ROW_P cell with its own length (45-150 cm),
// offset and strength, a quarter off (unequal streaks, not an even dash). Box-filtered exactly
// over the footprint w (two cells cover it); from a quarter cell on it fades to its mean.
fn hall_fixtures(C: vec2f, w: f32) -> f32 {
    let xs = C.x - CAN_C.x + 0.5f * ROW_P;
    let row = i32(floor(C.y / PITCH));
    let fade = smoothstep(0.25f * ROW_P, 0.6f * ROW_P, w);
    if (fade >= 1.0f) { return 0.221f; }
    let n0 = i32(floor((xs - 0.5f * w) / ROW_P));     // w < 0.6 ROW_P: two cells cover it
    var cov = 0.0f;
    for (var i = 0; i <= 1; i++) {
        let n = n0 + i;
        let h0 = argus_rand(vec2u(u32(n), u32(row)), 71u); let h1 = argus_rand(vec2u(u32(n), u32(row)), 72u);
        let on = select(0.45f + 0.55f * (h0 - 0.25f) / 0.75f, 0.0f, h0 < 0.25f);
        let len = 45.0f + 105.0f * h1;
        let cx = (f32(n) + 0.5f) * ROW_P + (h1 - 0.5f) * (ROW_P - len - 10.0f);
        cov += on * box_cov(xs - cx, w, 0.5f * len);
    }
    return mix(cov, 0.221f, fade);       // the mean: 0.75 x 0.725 x 97.5 / 240
}
// The ceiling along R (R.z > 0): the light box, and the hall's dimmer rows of fixtures.
fn ceiling(P: vec3f, R: vec3f, blur: f32) -> vec3f {
    let rz = max(R.z, 0.02f);
    let dist = (HC - P.z) / rz;
    let C = ceil_coords(P.xy + R.xy * dist);
    let w = max(blur * dist / rz, 0.4f);
    let Cc = C - CAN_C;
    let canopy = box_cov(Cc.x, w, CAN_H.x) * box_cov(Cc.y, w, CAN_H.y);
    let inner = box_cov(Cc.x, w, CAN_H.x - 12.0f) * box_cov(Cc.y, w, CAN_H.y - 12.0f);
    // a slot: a bright core in a softer diffuser, in a dark trim
    let core = train_cov(C.y, w, PITCH, 0.45f * SLOT_W);
    let diff = train_cov(C.y, w, PITCH, SLOT_W);
    let trim = train_cov(C.y, w, PITCH, SLOT_W + 5.0f);
    let rc = length(P.xy + R.xy * dist);                 // from the wheel's axis, on the ceiling
    let hall = smoothstep(R_COFFER - 25.0f - w, R_COFFER + 25.0f + w, rc);
    var seg = 0.0f;
    if (hall * (1.0f - canopy) > 0.0f) { seg = hall_fixtures(C, w) * hall; }
    // the ceiling's paint: a low-frequency unevenness of the light (faded over the footprint) and
    // the coffer's lighter trim ring
    let box = CEIL_L * (1.0f - 0.8f * (trim - diff) * inner);
    var base = box;
    if (canopy < 1.0f) {
        let paint = CEIL_DARK * (1.0f + 0.3f * argus_noise(C * 0.006f + 3.0f) / (1.0f + w / 120.0f))
                           + vec3f(0.10f, 0.09f, 0.08f) * box_cov(rc - R_COFFER, w, 6.0f);
        base = mix(paint, box, canopy);
    }
    return base + SLOT_L * (0.55f * diff + core) * (inner + SLOT_FAR * seg * (1.0f - canopy));
}
// What the wheel and the table look like along a downward ray (the wheel's own image in the
// chrome): the ray meets the profile (two fixed-point steps), and the ring colours there are
// box-filtered over the lobe's footprint; the pockets by the rotor's angle (and its sweep).
fn ring_w(r: f32, f: f32, lo: f32, hi: f32) -> f32 {
    return (clamp(r + 0.5f * f, lo, hi) - clamp(r - 0.5f * f, lo, hi)) / f;
}
fn wheel_image(P: vec3f, R: vec3f, blur: f32, rotor: f32, dphi: f32) -> vec3f {
    let dz = max(-R.z, 0.03f);
    // march to the first point under the profile (6 steps to the felt plane), then bisect
    let tm = P.z / dz + 0.5f;
    var ta = 0.0f; var tb = tm;
    for (var i = 1; i <= 6; i++) {
        let ti = tm * f32(i) / 6.0f;
        if (P.z - dz * ti <= scene_rev(length(P.xy + R.xy * ti))) { tb = ti; break; }
        ta = ti;
    }
    for (var j = 0; j < 4; j++) {
        let tc = 0.5f * (ta + tb);
        if (P.z - dz * tc <= scene_rev(length(P.xy + R.xy * tc))) { tb = tc; } else { ta = tc; }
    }
    let t = max(0.5f * (ta + tb), 0.3f);
    let H = P.xy + R.xy * t;
    let rh = length(H);
    let f = blur * t / dz + 0.15f;                 // the lobe's footprint there (cm)
    var pc = POCKET_MEAN;
    if (rh > R_POCKET_IN - f && rh < R_NUM_OUT + f) {
        let s = (POCKET_A0 - (atan2(H.y, H.x) - rotor)) / POCKET_DA + 0.5f;
        let wq = f / max(rh * POCKET_DA, 0.5f) + dphi / POCKET_DA;
        if (wq < 0.95f) {
            let k0f = floor(s - 0.5f * wq);
            let wt1 = saturate((s + 0.5f * wq - (k0f + 1.0f)) / wq);
            let n0 = i32(EU_SEQ[((i32(k0f) % 37) + 37) % 37]); let n1 = i32(EU_SEQ[((i32(k0f) + 38) % 37 + 37) % 37]);
            let c0 = select(select(BLK_L, RED_L, is_red(n0)), GRN_L, n0 == 0);
            let c1 = select(select(BLK_L, RED_L, is_red(n1)), GRN_L, n1 == 0);
            pc = mix(mix(c0, c1, wt1), POCKET_MEAN, smoothstep(0.5f, 0.95f, wq));
        }
    }
    var c = vec3f(0.30f) * ring_w(rh, f, -50.0f, R_TURRET);
    c += (WOOD_A * DL_UP * 0.9f + 0.02f) * ring_w(rh, f, R_TURRET, R_POCKET_IN);
    c += pc * (0.30f * DL_UP) * ring_w(rh, f, R_POCKET_IN, R_NUM_IN);
    c += ((pc * 0.85f + CREAM * 0.15f) * DL_UP * 0.95f + 0.02f) * ring_w(rh, f, R_NUM_IN, R_NUM_OUT);
    c += vec3f(0.35f) * ring_w(rh, f, R_NUM_OUT, R_STATOR_IN + 0.3f);
    c += (LACQ_BK * DL_UP + 0.03f) * ring_w(rh, f, R_STATOR_IN + 0.3f, 34.0f);
    c += (STONE * DL_UP + 0.035f) * ring_w(rh, f, 34.0f, R_WALL_TOP);
    c += (BOWL_DK * WOOD_A * DL_UP + 0.04f) * ring_w(rh, f, R_WALL_TOP, R_APRON_OUT);
    c += FELT * DL_UP * ring_w(rh, f, R_APRON_OUT, 1e4f);
    return c;
}

// Inside the bowl, low reflected rays meet the bowl itself: the stator's inner edge and the
// bowl rim stand above the rotor. Returns the tangent of the elevation the bowl hides, along
// the horizontal direction of R from P (-1 when P is outside the bowl).
fn circle_exit(p: vec2f, d: vec2f, rad: f32) -> f32 {   // distance along d to |p| = rad
    let b = dot(p, d); let c = dot(p, p) - rad * rad;
    return -b + sqrt(max(b * b - c, 0.0f));
}
fn bowl_horizon(P: vec3f, R: vec3f) -> f32 {
    let rp = length(P.xy);
    if (rp >= R_RIM_OUT) { return -1.0f; }
    let h = length(R.xy);
    if (h < 1e-4f) { return -1.0f; }
    let d = R.xy / h;
    var tn = (Z_RIM_TOP - P.z) / max(circle_exit(P.xy, d, R_RIM_OUT), 0.05f);
    if (rp < R_STATOR_IN) {
        tn = max(tn, (stator_z(R_STATOR_IN + 0.01f) - P.z) / max(circle_exit(P.xy, d, R_STATOR_IN), 0.05f));
    }
    return tn;
}

// On the rotor, rays that run inward low meet the cone and the turret before the hall: the
// pocket floors' dish looks across the cone (the number ring's reflections clear it). Returns the tangent of the
// elevation the rotor's own profile hides along R's horizontal direction (-1e3 when none): the
// profile sampled at 5 points toward the axis (its closest approach).
fn cone_horizon(P: vec3f, R: vec3f) -> f32 {
    let h = length(R.xy);
    if (h < 1e-4f) { return -1e3f; }
    let d = R.xy / h;
    let sc = -dot(P.xy, d);                  // distance to the closest approach to the axis
    if (sc <= 0.5f) { return -1e3f; }   // heading outward: nothing of the rotor rises there
    var tn = -1e3f;
    for (var i = 1; i <= 5; i++) {
        let s = sc * f32(i) / 5.0f;
        tn = max(tn, (rotor_profile_z(length(P.xy + d * s)) - P.z) / s);
    }
    return tn;
}
const CONE_SEEN: vec3f = WOOD_A * DL_UP * 0.9f + 0.02f;   // the lit cone, as wheel_image shows it

// What the bowl's inside shows to a ray from P that its rim hides (P inside the bowl): where the
// ray meets the stator (a march and a bisection along it), the lit veneer, the polished stone (its
// gloss mirrors the hall) or the wall under the lip, box-filtered over the lobe's footprint there.
fn bowl_far(P: vec3f, R: vec3f, bz: f32) -> vec3f {
    let h = max(length(R.xy), 1e-3f);
    let d = R.xy / h;
    let tz = R.z / h;
    let rp = length(P.xy);
    let sa = select(0.0f, circle_exit(P.xy, d, R_STATOR_IN), rp < R_STATOR_IN);
    let sb = circle_exit(P.xy, d, R_RIM_WALL);
    var a = sa; var b = sb; var rh = R_RIM_WALL;
    var hit = false;
    for (var i = 1; i <= 4 && !hit; i++) {
        let s = mix(sa, sb, 0.25f * f32(i));
        if (P.z + tz * s <= stator_z(max(length(P.xy + d * s), R_STATOR_IN))) { b = s; hit = true; } else { a = s; }
    }
    var s = sb;
    if (hit) {
        for (var j = 0; j < 4; j++) {
            let m = 0.5f * (a + b);
            if (P.z + tz * m <= stator_z(max(length(P.xy + d * m), R_STATOR_IN))) { b = m; } else { a = m; }
        }
        s = 0.5f * (a + b);
        rh = length(P.xy + d * s);
    }
    let f = bz * s * sqrt(1.0f + tz * tz) / max(abs(tz) + 0.3f, 0.3f) + 0.2f;   // footprint (cm)
    let veneer = BOWL_DK * WOOD_A * DL_UP * 0.85f + 0.025f;
    let stone  = STONE * DL_UP + vec3f(0.075f, 0.068f, 0.060f);
    let wall   = BOWL_DK * WOOD_A * DL_UP * 0.4f + 0.02f;
    return veneer * ring_w(rh, f, -1e3f, R_TRACK_IN) + stone * ring_w(rh, f, R_TRACK_IN, R_WALL_TOP - 0.2f)
         + wall * ring_w(rh, f, R_WALL_TOP - 0.2f, 1e3f);
}

// What a surface at P sees along R (unit); `blur` = angular spread (rad) of the lobe, turned
// into box footprints on the ceiling, the walls and the wheel: every light is integrated over it
// exactly, so nothing aliases however small or curved the mirror. rotor / dphi: the rotor's
// angle and its sweep over the shutter (for the wheel's own image).
fn env(P: vec3f, R: vec3f, blur: f32, rotor: f32, dphi: f32) -> vec3f {
    let bz = min(blur, 0.8f);
    let h = max(length(R.xy), 1e-3f);
    let el = atan2(R.z, h);
    // the hall's walls, and the ceiling above their top edge
    let el_c = atan2(HC - P.z, D_ROOM);
    let cf = smoothstep(el_c - 0.02f - 0.5f * bz, el_c + 0.02f + 0.5f * bz, el);
    var Lc = vec3f(0.0f);
    if (cf < 1.0f) { Lc = room(P, R, bz); }
    if (cf > 0.0f) { Lc = mix(Lc, ceiling(P, R, blur), cf); }
    // below the horizon: the table, or (inside the bowl) the wheel itself
    let lo = smoothstep(0.02f + bz, -0.02f - bz, R.z);
    if (lo > 0.0f) { Lc = mix(Lc, wheel_image(P, R, max(bz, 0.01f), rotor, dphi), lo); }
    // the bowl's own wall hides what lies below its rim: the far bowl (veneer, stone, wall)
    let tn = bowl_horizon(P, R);
    if (tn > -0.5f) {
        let vis = smoothstep(tn - 0.08f - 1.5f * bz, tn + 0.08f + 1.5f * bz, R.z / h);
        if (vis < 1.0f) { Lc = mix(bowl_far(P, R, bz), Lc, vis); }
    }
    // ... and on the rotor, the cone and the turret hide what lies beyond them
    let rp2 = dot(P.xy, P.xy);
    if (rp2 < sq(R_NUM_IN) && rp2 > sq(R_POCKET_IN - 0.5f) && R.z < 0.6f * length(R.xy) + bz) {
        let tc = cone_horizon(P, R);
        if (tc > -1e2f) {
            let h = max(length(R.xy), 1e-3f);
            let vis = smoothstep(tc - 0.08f - 1.5f * bz, tc + 0.08f + 1.5f * bz, R.z / h);
            if (vis < 1.0f) { Lc = mix(CONE_SEEN, Lc, vis); }
        }
    }
    return Lc;
}

// The ball's centre at time t (s) from now, along its path in polar coordinates about the axis.
fn ball_at(B: vec3f, v: vec3f, t: f32, polar: bool, rB: f32, thB: f32, vr: f32, om: f32) -> vec3f {
    if (!polar) { return B + v * t; }
    let rr = rB + vr * t; let a = thB + om * t;
    return vec3f(rr * cos(a), rr * sin(a), B.z + v.z * t);
}
// The PTFE ball's diffuse light (DL_UP scale): ~60 % light box (near-Lambert, slight wrap), ~40 %
// sky, plus the bounce from what lies under it (a red pocket tints its underside pink).
fn ball_diffuse(nb: vec3f, B: vec3f, under: vec3f) -> vec3f {
    let L = normalize(BOX_W - B);
    let k = saturate((dot(nb, L) + 0.08f) / 1.08f) / 0.95f;    // 1 for a face turned up
    let sky = pow(saturate(0.5f + 0.5f * nb.z), 1.6f);
    return BALL_C * ((0.6f * k + 0.4f * sky) * DL_UP + under * (0.5f - 0.5f * nb.z));
}

// ---- numerals: a condensed sans built from strokes and arcs (unit: digit height) ----
fn sd_seg(p: vec2f, a: vec2f, b: vec2f) -> f32 {
    let pa = p - a; let ba = b - a;
    return length(pa - ba * saturate(dot(pa, ba) / dot(ba, ba)));
}
// arc of radius r about c from angle a0 CCW to a1 (degrees, a0 < a1, span < 360)
fn sd_arc(p: vec2f, c: vec2f, r: f32, a0: f32, a1: f32) -> f32 {
    let q = p - c;
    let k = 0.0174533f;
    let ang = atan2(q.y, q.x) / k;
    var rel = ang - a0; rel -= 360.0f * floor(rel / 360.0f);
    if (rel <= a1 - a0) { return abs(length(q) - r); }
    let e0 = c + r * vec2f(cos(a0 * k), sin(a0 * k));
    let e1 = c + r * vec2f(cos(a1 * k), sin(a1 * k));
    return min(length(p - e0), length(p - e1));
}
fn sd_loop(p: vec2f, y0: f32, y1: f32, r: f32) -> f32 {   // vertical stadium outline
    return abs(length(vec2f(p.x, p.y - clamp(p.y, y0, y1))) - r);
}
// A bold, regular-width grotesque (Helvetica-Bold-like proportions), built from one stroke
// width so every glyph has the same weight. Skeleton: half height GH, half width GW; bowls
// centred at YU (upper) / YL (lower); the 3, 5, 8 waists at Y3 / Y5 / Y8.
const GW: f32 = 0.22f; const GH: f32 = 0.43f;
const YU: f32 = GH - GW; const YL: f32 = -(GH - GW);
const R3: f32 = 0.19f; const Y3M: f32 = GH - 2.0f * R3; const Y3: f32 = Y3M - GW;     // 3: smaller upper bowl
const Y5: f32 = YL + 0.14f;   // 5 and 6/9: the lower bowl's top centre
const R8: f32 = 0.175f; const Y8: f32 = GH - 2.0f * R8 - GW;                // 8: upper loop, lower loop's top centre
fn sd_digit(d: i32, p: vec2f) -> f32 {
    switch (d) {
    case 0: { return sd_loop(p, YL, YU, GW); }
    case 1: { return min(sd_seg(p, vec2f(0.05f, -GH), vec2f(0.05f, GH)),
                         sd_seg(p, vec2f(0.05f, GH), vec2f(-0.15f, GH - 0.17f))); }
    case 2: { return min(min(sd_arc(p, vec2f(0.0f, YU), GW, -40.0f, 180.0f),
                             sd_seg(p, vec2f(GW * 0.766f, YU - GW * 0.643f), vec2f(-GW, -GH))),
                         sd_seg(p, vec2f(-GW, -GH), vec2f(GW + 0.01f, -GH))); }
    case 3: { return min(min(sd_arc(p, vec2f(0.0f, GH - R3), R3, -90.0f, 160.0f),
                             sd_arc(p, vec2f(0.0f, YL), GW, 200.0f, 360.0f)),
                         min(min(sd_seg(p, vec2f(GW, YL), vec2f(GW, Y3)),
                                 sd_arc(p, vec2f(0.0f, Y3), GW, 0.0f, 90.0f)),
                             sd_seg(p, vec2f(0.0f, Y3M), vec2f(-0.07f, Y3M)))); }
    case 4: { return min(min(sd_seg(p, vec2f(0.10f, -GH), vec2f(0.10f, GH)),
                             sd_seg(p, vec2f(0.10f, GH), vec2f(-GW, -0.13f))),
                         sd_seg(p, vec2f(-GW, -0.13f), vec2f(GW + 0.02f, -0.13f))); }
    case 5: { return min(min(sd_seg(p, vec2f(GW, GH), vec2f(-0.18f, GH)),
                             sd_seg(p, vec2f(-0.18f, GH), vec2f(-0.19f, Y5 + GW * 0.5f))),
                         min(min(sd_arc(p, vec2f(0.0f, Y5), GW, 0.0f, 150.0f),
                                 sd_seg(p, vec2f(GW, Y5), vec2f(GW, YL))),
                             sd_arc(p, vec2f(0.0f, YL), GW, 200.0f, 360.0f))); }
    case 6: { return min(min(sd_loop(p, YL, Y5, GW),
                             sd_seg(p, vec2f(-GW, Y5), vec2f(-GW, YU))),
                         sd_arc(p, vec2f(0.0f, YU), GW, 25.0f, 180.0f)); }
    case 7: { return min(sd_seg(p, vec2f(-GW, GH), vec2f(GW, GH)),
                         sd_seg(p, vec2f(GW, GH), vec2f(-0.05f, -GH))); }
    case 8: { return min(abs(length(p - vec2f(0.0f, GH - R8)) - R8), sd_loop(p, YL, Y8, GW)); }
    default: {
        let q = -p;
        return min(min(sd_loop(q, YL, Y5, GW),
                       sd_seg(q, vec2f(-GW, Y5), vec2f(-GW, YU))),
                   sd_arc(q, vec2f(0.0f, YU), GW, 25.0f, 180.0f));
    }
    }
}
const DIGIT_H: f32 = 2.1f;           // cm (cap height ~2.2 cm with the stroke)
const DIGIT_SW: f32 = 0.085f;        // stroke half-width (digit heights): bold
const R_TEXT: f32 = 25.65f;
// Coverage of the numeral of pocket k at glyph-plane point (x tangential cm, y radial cm).
fn numeral_cov(k: i32, q: vec2f, aa: f32) -> f32 {
    let n = i32(EU_SEQ[k]);
    let p = q / DIGIT_H;
    var d: f32;
    if (n < 10) { d = sd_digit(n, p); }
    else {
        let sp = 0.36f;
        d = min(sd_digit(n / 10, p + vec2f(sp, 0.0f)), sd_digit(n % 10, p - vec2f(sp, 0.0f)));
    }
    return smoothstep(DIGIT_SW + aa, DIGIT_SW - aa, d);
}
fn pocket_colour(k: i32) -> vec3f {
    let n = i32(EU_SEQ[k]);
    return select(select(BLK_L, RED_L, is_red(n)), GRN_L, n == 0);
}
fn wrap37(k: i32) -> i32 { return ((k % 37) + 37) % 37; }

// Periodic box-filter coverage of intervals [m - hw, m + hw] (integers m) over [x0, x1].
fn tick_F(x: f32, hw: f32) -> f32 {
    let y = x + hw;
    return floor(y) * 2.0f * hw + min(y - floor(y), 2.0f * hw);
}
fn tick_cov(x: f32, w: f32, hw: f32) -> f32 {
    return (tick_F(x + 0.5f * w, hw) - tick_F(x - 0.5f * w, hw)) / w;
}

// Ambient occlusion of a sphere (Quilez), normal n at P.
fn sphere_ao(P: vec3f, n: vec3f, c: vec3f, rad: f32) -> f32 {
    let d = c - P;
    let l = length(d);
    return 1.0f - saturate(dot(n, d / l) * sq(rad / l)) * 0.9f;
}

// The key light: the light box over the table's layout, seen from p.
fn box_dir(p: vec3f) -> vec3f { return normalize(BOX_W - p); }
// How much of the light box a sphere (centre c, radius rad) hides from point P: the sphere's
// silhouette projected from P onto the ceiling (as a square of equal area) overlapped with the
// box's lit rectangle. Exact enough for a soft shadow that separates from the ball with height:
// about 0.3 cm per cm of height, along the box's direction.
fn box_block(P: vec3f, c: vec3f, rad: f32) -> f32 {
    let hz = c.z - P.z;
    if (hz <= 0.05f) { return 0.0f; }
    let k = (HC - P.z) / hz;
    let X = ceil_coords(P.xy + (c.xy - P.xy) * k) - CAN_C;
    let s = 0.886f * rad * k;   // half side: sqrt(pi)/2 of the radius
    let hb = CAN_H - 12.0f;
    let ox = max(min(X.x + s, hb.x) - max(X.x - s, -hb.x), 0.0f);
    let oy = max(min(X.y + s, hb.y) - max(X.y - s, -hb.y), 0.0f);
    return ox * oy / (4.0f * hb.x * hb.y);
}

// The felt's sheen (radiance) seen along V at P: Charlie D (sheen roughness FELT_SHEEN_A) x the
// visibility 1 / (4 (NL + NV - NL NV)) x irradiance, for the light box (~60 % of the light on the
// table, as a single direction) and the hall's walls (radiance ~WALL_L over elevations 0..34 deg:
// irradiance pi L sin^2(34 deg)).
const FELT_SHEEN_A: f32 = 0.5f;          // sheen roughness (chosen): D = 4 sin^2 / (2 pi), no pow
const FELT_SHEEN_C: vec3f = FELT * 5.0f;          // the fibres' sheen colour (chosen)
fn charlie(n: vec3f, L: vec3f, V: vec3f) -> f32 {
    let H = normalize(L + V);
    let c = saturate(dot(n, H));
    let D = (2.0f + 1.0f / FELT_SHEEN_A) * (1.0f - c * c) * (0.5f / PI_F);   // sin^(1/a), a = 0.5
    let nl = saturate(dot(n, L)); let nv = saturate(dot(n, V));
    return D / (4.0f * (nl + nv - nl * nv) + 1e-4f);
}
fn felt_sheen(P: vec3f, V: vec3f) -> vec3f {
    let n = vec3f(0.0f, 0.0f, 1.0f);
    let Lb = box_dir(P);
    var s = charlie(n, Lb, V) * (0.6f * PI_F * DL_UP);
    let vt = select(vec2f(1.0f, 0.0f), normalize(V.xy), length(V.xy) > 1e-4f);
    let ce = 0.956f; let se = 0.292f;                 // 17 deg elevation
    let wall = 0.5f * (charlie(n, vec3f(vt * ce, se), V) + charlie(n, vec3f(-vt * ce, se), V));
    s += wall * (PI_F * 0.31f) * WALL_L * 0.75f;
    return FELT_SHEEN_C * s;
}

// The bowl's shadow on the felt: the share of the light box (its near-to-far elevations, +-80 cm)
// that the bowl (5 heights along the ray to the box) leaves visible from q: soft, directional.
fn bowl_box_vis(q: vec2f) -> f32 {
    let tb = BOX_W.xy - q;
    let D = length(tb);
    let d = tb / D;
    let b = dot(q, d); let c = dot(q, q) - R_APRON_OUT * R_APRON_OUT;
    if (b >= 0.0f || b * b - c <= 0.0f) { return 1.0f; }           // the ray to the box misses the bowl
    let s0 = -b - sqrt(b * b - c);   // where it enters the bowl's footprint
    let tlo = HC / (D + 80.0f); let thi = HC / max(D - 80.0f, 25.0f);
    if (Z_RIM_TOP / max(s0, 1e-3f) <= tlo) { return 1.0f; }           // too far out to hide any of it
    let c1 = dot(q, q) - R_RIM_OUT * R_RIM_OUT;
    let s1 = select(-b, -b - sqrt(b * b - c1) + 0.3f, b * b - c1 > 0.0f);   // the rim top, or the closest approach
    var tn = 0.0f;
    for (var i = 1; i <= 5; i++) {
        let s = mix(s0, s1, 0.2f * f32(i));
        tn = max(tn, bowl_z(length(q + d * s)) / max(s, 1e-3f));
    }
    return saturate((thi - tn) / (thi - tlo));
}

// The material of the revolution surface at radius r (frets, numerals and veneer included).
struct Mat {
    alb: vec3f,      // diffuse albedo (linear)
    f0: f32,         // dielectric reflectance at normal incidence
    met: f32,        // 0 dielectric .. 1 chrome
    gloss: f32,      // reflection lobe (rad): ggx_lobe(rough) for dielectrics, LOBE_CHROME for chrome
    rough: f32,      // GGX roughness of the dielectric part (for its Fresnel over the lobe)
    ao: f32,
}
fn mat_at(r: f32, Pxy: vec2f, ang_w: f32, a_rot: f32, pix: f32, dphi: f32) -> Mat {
    var m: Mat;
    m.alb = vec3f(0.0f); m.f0 = F0_COAT; m.met = 0.0f; m.gloss = LOBE_CHROME; m.rough = 0.3f; m.ao = 1.0f;
    if (r >= R_APRON_OUT) {
        // ------------------------------------------------------------ felt --
        let q = Pxy;
        let mott = argus_fbm(q * 0.09f, 2);
        let fib = argus_noise(q * vec2f(2.2f, 7.5f)) * 0.5f + argus_noise(q * vec2f(6.0f, 3.1f) + 17.0f) * 0.5f;
        // the nap: fine fibres (faded to their mean below ~3 px, so they never shimmer) and a
        // faint brushed direction
        let nap = argus_noise(q * vec2f(0.6f, 1.8f) + 31.0f);
        m.alb = FELT * (1.0f + 0.08f * mott + 0.10f * fib * saturate(0.35f / pix - 0.6f) + 0.015f * nap);
        // the table sits in a pool of light: the light box (off-axis, lower left) and the slots
        let Cf = ceil_coords(q);
        let yq = Cf.y / PITCH - 0.5f;
        let d0 = (yq - round_m(yq)) * PITCH;
        let db = q - BOX_W.xy;
        m.alb *= (0.45f + 0.55f * exp(-dot(db, db) / (2.0f * 95.0f * 95.0f)))
               * (0.92f + 0.08f * (sq(HC * HC / (HC * HC + d0 * d0)) + sq(HC * HC / (HC * HC + sq(PITCH - abs(d0))))) * 0.6f) * 1.25f;
        m.f0 = 0.0f;
        // the hall's light (~40 %) is hidden near the bowl's foot all round; the light box's (~60 %)
        // by the bowl's cast shadow, away from the box
        m.ao = (1.0f - 0.45f * exp(-(r - R_APRON_OUT) / 1.0f) - 0.15f * exp(-(r - R_APRON_OUT) / 5.0f))
             * (1.0f - 0.6f * (1.0f - bowl_box_vis(q)));
    } else if (r >= R_WALL_TOP) {
        // ----------------------------------- bowl rim and apron: dark veneer --
        let g = argus_fbm(vec2f(ang_w * 60.0f, r * 0.35f), 3);
        let fig = 0.5f + 0.5f * sin(ang_w * 140.0f + 6.0f * g + r * 0.2f);
        m.alb = BOWL_DK * mix(WOOD_B, WOOD_A, saturate(0.35f + 0.5f * fig * (0.6f + 0.4f * g)));
        m.rough = ROUGH_BOWL; m.gloss = ggx_lobe(ROUGH_BOWL);
    } else if (r >= R_TRACK_IN) {
        // ------------------- honed engineered stone ball track (mineral-filled resin) --
        // a dense, fine, low-contrast grain (about +-5 % around the mean), faded to its mean
        // below ~2 px; a honed-to-polished finish: a faint, broad sheen of the light box
        let q = Pxy;
        let k = saturate(0.12f / pix - 0.5f);
        let sp = 0.6f * argus_noise(q * 11.0f) + 0.4f * argus_noise(q * 17.0f + 7.0f);
        let grain = vec3f(0.14f, 0.14f, 0.13f) * sp * k;      // sp: std ~0.35
        m.alb = STONE_MEAN * (1.0f + grain + 0.03f * argus_noise(q * 2.3f + 2.0f));
        m.rough = ROUGH_STONE; m.gloss = ggx_lobe(ROUGH_STONE);
        m.ao *= 1.0f - 0.6f * exp(-(R_WALL_TOP - r) / 0.5f);           // under the lip
        m.ao *= mix(1.0f, 0.9f, smoothstep(R_TRACK_IN + 0.3f, R_TRACK_IN, r));
    } else if (r >= R_STATOR_IN) {
        // ------------------ lower stator: dark mahogany veneer under a clear coat --
        let g = argus_fbm(vec2f(ang_w * 45.0f, r * 0.5f), 2);
        let fig = 0.5f + 0.5f * sin(ang_w * 120.0f + 5.0f * g + r * 0.3f);
        m.alb = BOWL_DK * mix(WOOD_B, WOOD_A, saturate(0.4f + 0.45f * fig * (0.6f + 0.4f * g)));
        m.rough = ROUGH_VEN; m.gloss = ggx_lobe(ROUGH_VEN);
        m.ao *= 1.0f - 0.3f * smoothstep(1.5f * pix, 0.0f, abs(r - R_TRACK_IN));   // the groove's floor
        m.ao *= 1.0f - 0.3f * exp(-(r - R_STATOR_IN) / 0.2f);
    } else if (r >= R_ROTOR_OUT) {
        // --------------------------------------------- the seam to the rotor --
        m.alb = vec3f(0.002f); m.f0 = 0.02f; m.ao = 0.15f;
    } else if (r >= R_NUM_OUT) {
        m.alb = vec3f(0.0f); m.met = 1.0f;   // rotor rim: chrome
    } else if (r >= R_POCKET_IN) {
        // ---------------------- the rotor's numbered ring and pockets (blurred) --
        let s = (POCKET_A0 - a_rot) / POCKET_DA + 0.5f;      // pocket k occupies [k, k+1)
        let wpix = pix / (r * POCKET_DA);   // a pixel, in pocket units
        let wmot = dphi / POCKET_DA;
        let w = min(wpix + wmot, 0.95f);
        let k0f = floor(s - 0.5f * w);
        let wt1 = saturate((s + 0.5f * w - (k0f + 1.0f)) / w);
        let k0 = wrap37(i32(k0f)); let k1 = wrap37(i32(k0f) + 1);
        let band = mix(pocket_colour(k0), pocket_colour(k1), wt1);
        if (r >= R_NUM_IN) {
            // number ring: lacquer + numerals, smeared over the shutter
            let NS = clamp(i32(ceil(wmot * r * POCKET_DA / (1.5f * pix))), 1, 10);
            let stepu = wmot / f32(NS);
            let aa = max(pix, stepu * r * POCKET_DA) / DIGIT_H * 0.6f;
            var cov = 0.0f;
            for (var i = 0; i < NS; i++) {
                let si = s + (f32(i) + 0.5f) / f32(NS) * wmot - 0.5f * wmot;
                let kf = floor(si);
                let x = (si - kf - 0.5f) * POCKET_DA * r;
                cov += numeral_cov(wrap37(i32(kf)), vec2f(x, r - R_TEXT), aa);
            }
            cov /= f32(NS);
            m.alb = mix(band, CREAM, cov);
            // satin lacquer; a chrome edging on the ring's inner lip (over the pockets' outer wall)
            m.met = smoothstep(R_NUM_IN + 0.3f + pix, R_NUM_IN + 0.3f - pix, r);
            m.rough = ROUGH_RING; m.gloss = mix(ggx_lobe(ROUGH_RING), LOBE_CHROME, m.met);
            m.ao *= 1.0f - 0.25f * exp(-(R_NUM_OUT - r) / 0.12f);
        } else {
            // pocket floor (satin lacquer) between the frets (drawn over it in the kernel)
            let floor_c = band * vec3f(0.55f, 0.55f, 0.6f) + vec3f(0.004f);
            let dfr = abs(s - round_m(s)) * POCKET_DA * r;          // cm to the nearest fret
            let depth = Z_FRET_TOP - rotor_profile_z(r);
            let aof = 0.35f + 0.65f * smoothstep(0.0f, 1.1f, dfr - FRET_HALF_W);
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
        let sec = TAU_F / 8.0f;
        let am = a_rot - sec * floor(a_rot / sec) - 0.5f * sec;   // -sec/2..sec/2
        let u = r * cos(am); let v = r * sin(am);   // along / across the leaf
        let gq = abs(v) * 0.940f + u * 0.342f;   // across the grain (cm)
        let gl = u * 0.940f - abs(v) * 0.342f;   // along it
        let smear = dphi * r;
        let gw = 1.0f / (1.0f + smear / 0.10f + pix / 0.12f);     // fine grain lines
        let fw = 1.0f / (1.0f + smear / 1.0f + pix / 0.8f);       // the figure
        let g = argus_fbm(vec2f(gq * 2.2f, gl * 0.18f), 2);
        let grain = sin(gq * 14.0f + 6.0f * g);
        let figure = argus_fbm(vec2f(gq * 0.8f + 3.0f, gl * 0.3f), 2);
        let fa = ang_w - am - select(-0.349f, 0.349f, v >= 0.0f);    // fibre azimuth, world
        let chat = cos(2.0f * (fa - LIGHT_AZ));
        m.alb = mix(WOOD_B, WOOD_A, saturate(0.55f + gw * 0.22f * grain + fw * 0.5f * figure));
        m.alb *= 1.0f + 0.22f * chat + 0.25f * chat * fw * figure;
        // seams between sectors
        let seam = smoothstep(pix * 1.2f + smear, 0.0f, abs(abs(am) - 0.5f * sec) * r);
        m.alb *= 1.0f - 0.6f * seam;
        // satin clear coat; a chrome edging where the cone meets the pockets
        m.met = smoothstep(R_POCKET_IN - 0.4f - pix, R_POCKET_IN - 0.4f + pix, r);
        m.rough = ROUGH_CONE; m.gloss = mix(ggx_lobe(ROUGH_CONE), LOBE_CHROME, m.met);
        m.ao *= 1.0f - 0.3f * exp(-(r - R_TURRET) / 0.8f);
    } else {
        // ---------------------------------------------------------- turret --
        m.alb = vec3f(0.0f); m.met = 1.0f;
    }
    return m;
}
// Which ring a radius falls in: materials are averaged over a pixel where this changes.
fn ring_band(r: f32) -> i32 {
    return i32(r >= R_TURRET) + i32(r >= R_POCKET_IN) + i32(r >= R_NUM_IN) + i32(r >= R_NUM_OUT)
         + i32(r >= R_ROTOR_OUT) + i32(r >= R_STATOR_IN) + i32(r >= R_TRACK_IN) + i32(r >= R_WALL_TOP)
         + i32(r >= R_APRON_OUT);
}

// The rim's lip is a silhouette: inside its edge the camera sees the track (under the overhang),
// outside it the lip. A pixel straddling the edge is shaded for both sides (1: the track continued
// under the lip; 2: the lip continued inward), blended by the exact share of the pixel on each.
// The rotor-stator gap is a ~1.1 px ring over a dark slot: a pixel near it is shaded as one side
// (3: the rotor rim continued outward, 4: the stator continued inward, the nearer one) and covered
// by the slot by the exact share the ring takes: no stair-stepped seam.
const RHO_LIP: f32 = R_WALL_TOP / (H_EYE - (Z_RIM_TOP - LIP_ROUND));   // the edge's radius / FC
const RHO_GAP_IN: f32  = R_ROTOR_OUT / (H_EYE - Z_ROTOR_RIM);         // the gap on screen / FC
const RHO_GAP_OUT: f32 = R_STATOR_IN / (H_EYE - Z_STATOR_IN);
const GAP_C: vec3f = vec3f(0.0004f, 0.0003f, 0.0003f);                // the dark slot
// A side, as the radii it shows (sc: outside them the side's surface is continued) and its
// continuation: kc > 0 a flat top at kc (the lip, the rotor rim), else the stator's curve.
struct Side { sc: vec2f, kc: f32, }
fn side_of(side: i32) -> Side {
    var s: Side;
    switch (side) {
        case 1:  { s.sc = vec2f(0.0f, R_WALL_TOP - 1e-3f);    s.kc = 0.0f; }
        case 2:  { s.sc = vec2f(R_WALL_TOP, 1e4f);            s.kc = Z_RIM_TOP - LIP_ROUND; }
        case 3:  { s.sc = vec2f(0.0f, R_ROTOR_OUT - 1e-3f);   s.kc = Z_ROTOR_RIM; }
        default: { s.sc = vec2f(R_STATOR_IN + 1e-3f, 1e4f);   s.kc = 0.0f; }
    }
    return s;
}
fn prof_side(r: f32, sd: Side) -> f32 {
    if (r < sd.sc.x || r > sd.sc.y) { return select(stator_curve_z(r), sd.kc, sd.kc > 0.0f); }
    return scene_rev(r);
}
fn r_side(r: f32, sd: Side) -> f32 { return clamp(r, sd.sc.x, sd.sc.y); }   // the radius whose material it shows

// The height the camera sees along pixel radius rho (a march down the ray, then a bisection).
fn visible_z(rho: f32, side: Side) -> f32 {
    let r0 = rho * H_EYE;
    var zhi: f32; var zlo: f32;
    if (r0 < 8.0f)                      { zhi = 12.6f; zlo = Z_CONE_TOP - 0.4f; }
    else if (r0 < R_POCKET_IN + 0.8f)   { zhi = Z_CONE_TOP + 0.3f; zlo = Z_POCKET - 0.2f; }
    else if (r0 < R_STATOR_IN + 0.6f)   { zhi = stator_z(R_STATOR_IN + 0.6f) + 0.1f; zlo = Z_POCKET - 0.2f; }
    else if (r0 < R_WALL_TOP - 0.2f)    { zhi = stator_z(r0) + 0.1f; zlo = 0.8f; }
    else if (r0 < R_APRON_OUT + 1.0f)   { zhi = Z_RIM_TOP + 0.05f; zlo = 0.0f; }
    else                                { zhi = 0.0f; zlo = 0.0f; }
    var z = zlo;
    if (zhi > 0.0f) {
        let dz = (zhi - zlo) / 8.0f;
        var a = zhi; var b = zlo;
        var hit = false;
        for (var i = 1; i <= 8 && !hit; i++) {
            let zi = zhi - f32(i) * dz;
            if (zi <= prof_side(rho * (H_EYE - zi), side)) { a = zi + dz; b = zi; hit = true; }
        }
        if (hit) {
            for (var j = 0; j < 5; j++) {
                let m = 0.5f * (a + b);
                if (m <= prof_side(rho * (H_EYE - m), side)) { b = m; } else { a = m; }
            }
            z = 0.5f * (a + b);
        }
    }
    return z;
}
fn shade_px(uv: vec2f, side_k: i32, S: WheelState, zb: f32) -> vec4f {   // .w: the ball's cover
    let side = side_of(side_k);
    let dir = normalize(vec3f(uv, -FC));
    let V = -dir;
    let rho = length(uv) / FC;
    let uvpix = 2.0f / f32(f.height);            // one pixel in argus_uv units

    // ---------------------------------------------------- visible surface --
    var z = zb;
    if (!(zb < Z_LIVE)) { z = visible_z(rho, side); }
    let r = rho * (H_EYE - z);
    var P = vec3f(uv * (H_EYE - z) / FC, z);
    let pix = uvpix * (H_EYE - z) / FC;            // cm per pixel at P
    let rh = select(vec2f(1.0f, 0.0f), P.xy / r, r > 1e-4f);
    let th = vec2f(-rh.y, rh.x);                 // CCW tangent
    // normal of the revolution profile, filtered over a pixel
    let e = max(pix, 0.03f);
    let zp = prof_side(r + e, side); let zm = prof_side(max(r - e, 0.0f), side); let z0 = prof_side(r, side);
    let dzdr = (zp - zm) / (2.0f * e);
    // how far the normal turns across the pixel (bounded, so edges cannot blow it up)
    // ... and around the axis (a small dome's normal swings round within a pixel near its top)
    let dang = abs(atan((zp - z0) / e) - atan((z0 - zm) / e)) * (pix / e)
                     + abs(dzdr) * inverseSqrt(1.0f + dzdr * dzdr) * pix / max(r, 0.05f);
    var n = normalize(vec3f(-dzdr * rh, 1.0f));
    // the join between the stone track and the veneer: a shallow V groove (shading only) whose
    // walls catch the hall's light; its normal's turn across the pixel widens the lobe
    var xblur = 0.0f;
    {
        let xg = (r - R_TRACK_IN) / 0.22f;
        if (abs(xg) < 1.0f) {
            n = normalize(n + vec3f(rh * tan(-0.45f * sin(PI_F * xg)), 0.0f) * n.z);
            xblur = 0.45f * PI_F * pix / 0.22f;
        }
    }
    // the chrome rotor rim is a convex bead (shading only; it collides as the straight segment):
    // its normal turns from 45 deg inward to 60 deg outward across its ~1 cm, so within ~10 px it
    // mirrors the number ring, the hall, the light box, the ceiling and the bowl beside it
    {
        let xb = (r_side(r, side) - R_NUM_OUT) / (R_ROTOR_OUT - R_NUM_OUT);
        if (xb > 0.0f && xb < 1.0f) {
            let tilt = mix(-0.785f, 1.047f, xb);
            n = vec3f(rh * sin(tilt), cos(tilt));
            xblur = 2.0f * 1.833f * pix / (R_ROTOR_OUT - R_NUM_OUT);   // the reflection's sweep over a pixel
        }
    }
    let ang_w = atan2(P.y, P.x);
    let a_rot = ang_w - S.rotor;   // rotor-frame angle
    // Shutter: one fixed exposure, SHUTTER, at every frame rate: rotor, numerals, frets, arms and
    // ball are blurred over the same time at 30, 60 and 120 FPS (it does not depend on f.dt).
    let SHb = SHUTTER;
    let dphi = abs(S.rotor_vel) * SHUTTER;          // rotor sweep during the shutter
    // Wagon-wheel safety net: from 0.42 pocket per displayed frame the frets' periodic contrast
    // fades to its mean. The push cap (0.34 rev/s) keeps it off at 30, 60 and 120 FPS.
    let fdt = clamp(f.dt, 1.0f / 120.0f, 1.0f / 30.0f);
    let nyq = smoothstep(0.5f, 0.42f, abs(S.rotor_vel) * fdt / POCKET_DA);

    // ---------------------------------------------------- material at P --
    var m = mat_at(r_side(r, side), P.xy, ang_w, a_rot, pix, dphi);
    if (ring_band(r_side(r - 0.5f * pix, side)) != ring_band(r_side(r + 0.5f * pix, side))) {
        // a ring edge crosses this pixel: average the material over its footprint
        let ma = mat_at(r_side(r - 0.33f * pix, side), P.xy, ang_w, a_rot, pix, dphi);
        let mb = mat_at(r_side(r + 0.33f * pix, side), P.xy, ang_w, a_rot, pix, dphi);
        m.alb = (ma.alb + m.alb + mb.alb) / 3.0f;
        m.f0 = (ma.f0 + m.f0 + mb.f0) / 3.0f;
        m.met = (ma.met + m.met + mb.met) / 3.0f;
        m.gloss = (ma.gloss + m.gloss + mb.gloss) / 3.0f;
        m.rough = (ma.rough + m.rough + mb.rough) / 3.0f;
        m.ao = (ma.ao + m.ao + mb.ao) / 3.0f;
    }
    var alb = m.alb;
    var f0 = m.f0; var met = m.met; var gloss = m.gloss; var ao = m.ao;
    let rough = m.rough;

    // ---------------------------------------------------- the frets --
    // The rounded top is a half cylinder: its normal tilts asin(x / FRET_HALF_W) at lateral offset
    // x. Five facets: the crown (|x| < 0.18, tilt < 10 deg: the light box), two inner shoulders
    // (0.18..0.7, 10-44 deg: the hall) and two outer shoulders (0.7..1, 44-90 deg: they face down
    // into the neighbouring pocket and mirror its floor). Each is box-filtered exactly over the
    // pixel and the shutter, and its periodic contrast fades by `nyq`.
    var fret_top = 0.0f; var fret_ccw = 0.0f; var fret_cw = 0.0f; var fret_occw = 0.0f; var fret_ocw = 0.0f;
    var fret_pa = POCKET_MEAN; var fret_pb = POCKET_MEAN;      // the pockets the outer shoulders face
    let rf = rho * (H_EYE - Z_FRET_TOP);
    if (rf > R_FRET_IN && rf < R_FRET_OUT + pix && z < Z_FRET_TOP + 0.05f) {
        let s = (POCKET_A0 - a_rot) / POCKET_DA + 0.5f;      // frets at integer s
        let hwf = FRET_HALF_W / (rf * POCKET_DA);
        let wf = min(pix / (rf * POCKET_DA) + dphi / POCKET_DA, 0.95f);
        let span = smoothstep(R_FRET_IN + 0.05f, R_FRET_IN + 0.2f, rf)
                         * smoothstep(R_FRET_OUT + 0.5f * pix, R_FRET_OUT - 0.5f * pix, rf);
        fret_top  = mix(0.36f * hwf, tick_cov(s, wf, 0.18f * hwf), nyq) * span;
        fret_ccw  = mix(0.52f * hwf, tick_cov(s + 0.44f * hwf, wf, 0.26f * hwf), nyq) * span;
        fret_cw   = mix(0.52f * hwf, tick_cov(s - 0.44f * hwf, wf, 0.26f * hwf), nyq) * span;
        fret_occw = mix(0.30f * hwf, tick_cov(s + 0.85f * hwf, wf, 0.15f * hwf), nyq) * span;
        fret_ocw  = mix(0.30f * hwf, tick_cov(s - 0.85f * hwf, wf, 0.15f * hwf), nyq) * span;
        let j = round_m(s);
        fret_pa = mix(pocket_colour(wrap37(i32(j) - 1)), POCKET_MEAN, smoothstep(0.3f, 0.9f, wf));
        fret_pb = mix(pocket_colour(wrap37(i32(j))), POCKET_MEAN, smoothstep(0.3f, 0.9f, wf));
    }
    let fret_zr = vec2f(Z_FRET_TOP - 0.05f, rf);

    // ---------------------------------------------------- diamonds (static) --
    // Rhombic chrome studs with a 4-facet pyramid cap, sheared to follow the stator's slope, the
    // edges rounded. Seen at their mean top height (parallax). Facet normals are blended across
    // the ridges over ~1.5 px and the rounded edge band is at least 2.5 px wide: no speckle.
    if (r > R_DIAMOND - 2.5f && r < R_DIAMOND + 2.5f) {
        let zd = stator_z(R_DIAMOND) + 0.5f * (DIAMOND_H + DIAMOND_HE);
        let Q = uv * (H_EYE - zd) / FC;
        let sec = 0.785398f;
        let j = round_m(atan2(Q.y, Q.x) / sec);
        let ac = j * sec;
        let cr = vec2f(cos(ac), sin(ac)); let ct = vec2f(-cr.y, cr.x);
        let dq = Q - R_DIAMOND * cr;
        let radial = (i32(j) & 1) == 0;
        let q = select(vec2f(dot(dq, ct), dot(dq, cr)), vec2f(dot(dq, cr), dot(dq, ct)), radial);
        let hb = vec2f(DIAMOND_HALF_LEN, DIAMOND_HALF_WID);
        let d2 = sd_rhombus(q, hb);   // < 0 inside
        let cov = smoothstep(0.5f * pix, -0.5f * pix, d2);
        // its foot darkens the stator around it
        ao *= 1.0f - 0.45f * (1.0f - cov) * exp(-max(d2, 0.0f) / 0.35f);
        if (cov > 0.0f) {
            // the outward direction of the nearest edge (gradient of the rhombus distance)
            let ee = 0.02f;
            let gq = vec2f(sd_rhombus(q + vec2f(ee, 0.0f), hb) - sd_rhombus(q - vec2f(ee, 0.0f), hb),
                           sd_rhombus(q + vec2f(0.0f, ee), hb) - sd_rhombus(q - vec2f(0.0f, ee), hb));
            let gl = gq / max(length(gq), 1e-5f);
            let gw2 = select(gl.x * ct + gl.y * cr, gl.x * cr + gl.y * ct, radial);
            let rr = length(Q);
            let sl2 = -stator_slope(rr) * Q / max(rr, 1e-3f);          // the stator's tilt
            // the facet under the pixel (signs blended across the ridges)
            let sgn = clamp(q / (0.75f * pix), vec2f(-1.0f), vec2f(1.0f));
            let fl = -sgn * vec2f(DIAMOND_KX, DIAMOND_KY);                // facet slopes, local
            let lx = select(ct, cr, radial); let ly = select(cr, ct, radial);
            // (shading: the cap's facets are taken a little less sheared than the collision cap;
            // from above they mirror the hall and the ceiling around the box, not the box itself)
            let ntop = normalize(vec3f(0.35f * sl2 + 0.8f * (fl.x * lx + fl.y * ly), 1.0f));
            // across the rounded edge the normal turns from the facet's to horizontal
            let band = max(DIAMOND_ROUND, 2.5f * pix);
            let t = saturate((d2 + band) / band);
            let turn = 1.5708f * t * t;
            let nd = normalize(ntop * cos(turn) + vec3f(gw2, 0.0f) * sin(turn));
            n = normalize(mix(n, nd, cov));
            met = mix(met, 1.0f, cov);
            // the lobe covers how far the normal turns within the pixel (edge band, ridges)
            gloss = mix(gloss, 0.03f + 2.0f * 1.5708f * pix / band * t + 0.7f * (2.0f - abs(sgn.x) - abs(sgn.y)), cov);
            ao = mix(ao, 1.0f, cov);
            P.z = mix(P.z, zd, cov);
        }
    }

    // ---------------------------------------------------- shadows on P --
    var shadow = 1.0f;
    // ball: contact occlusion + soft shadows from the nearest panels
    let B = S.ball;
    let ba = S.ball_alpha;
    if (ba > 0.0f && length(P.xy - B.xy) < 12.0f) {
        let vb = S.ball_vel * SHb;
        let sl = length(vb);
        let keep = 2.0f * R_BALL / (2.0f * R_BALL + sl);
        var Bc = B;
        if (sl > 1e-3f) { let dv = vb / sl; Bc = B + dv * clamp(dot(P - B, dv), -0.5f * sl, 0.5f * sl); }
        let occ = sphere_ao(P, n, Bc, R_BALL);
        // the box gives ~60 % of the light here; the rest (the hall) is occluded as ambient
        let sh = (1.0f - 0.6f * box_block(P, Bc, R_BALL)) * mix(1.0f, occ, 0.5f);
        shadow *= mix(1.0f, sh, ba * mix(1.0f, keep, 0.5f));
    }
    // turret column and handle arms on the cone / pockets
    if (r < R_NUM_IN && r > 1.0f) {
        let L0 = box_dir(vec3f(0.0f, 0.0f, 0.0f));
        // column: the axis, up to the hub
        {
            let t1 = (10.0f - P.z) / L0.z;
            if (t1 > 0.0f) {
                let a2 = P.xy; let b2 = P.xy + L0.xy * t1;
                let dcol = sd_seg(vec2f(0.0f), a2, b2);
                let pen = 0.4f + 0.12f * t1 * 0.5f;
                shadow *= 1.0f - 0.45f * smoothstep(2.2f + pen, 2.2f - pen, dcol) * smoothstep(R_TURRET - 1.5f, R_TURRET + 0.5f, r);
            }
        }
        let t2 = (ARM_Z - P.z) / L0.z;
        if (t2 > 0.0f) {
            let Q = P.xy + L0.xy * t2;              // where the shadow ray meets the arms' plane
            let rq = length(Q);
            let aq = atan2(Q.y, Q.x) - S.rotor - ARM_A0;
            let qa = 1.5707963f;
            let rel = (aq - qa * round_m(aq / qa));    // angle to the nearest arm
            let pen = 0.1f + t2 * 0.10f;
            let halfw = (ARM_R + pen) / max(rq, 0.5f);
            let wv = dphi;
            let cov = saturate((min(rel + 0.5f * wv, halfw) - max(rel - 0.5f * wv, -halfw)) / max(wv, 1e-4f + 0.0f * halfw));
            let c2 = select(smoothstep(ARM_R + pen, ARM_R - pen, abs(rel) * rq), cov, wv > 2.0f * halfw);
            let on = smoothstep(ARM_R0 - 0.5f, ARM_R0 + 0.5f, rq) * smoothstep(KNOB_AT + KNOB_R + pen, KNOB_AT + KNOB_R - pen, rq);
            shadow *= 1.0f - 0.5f * c2 * on;
        }
    }

    // ---------------------------------------------------- shade P --
    let ndv = saturate(dot(n, V));
    let Rv = reflect(dir, n);
    let pixang = uvpix / FC;   // a pixel's angular size
    let blur = gloss + 4.0f * dang + xblur + pixang * (1.0f + (HC - P.z) / max(H_EYE - P.z, 1.0f));
    var envc = vec3f(0.0f);   // the felt reflects nothing
    if (f0 > 0.0f || met > 0.0f) { envc = env(P, Rv, blur, S.rotor, dphi); }
    // the ball, mirrored in glossy surfaces
    // (filtered over the lobe: its footprint at the ball's distance against the ball's disc, so a
    // small or steep mirror shows a faint, steady image instead of a sparkle)
    if (ba > 0.0f) {
        let oc = P - B;
        let bq = dot(oc, Rv); let cq = dot(oc, oc) - R_BALL * R_BALL;
        let hq = bq * bq - cq;
        if (bq < 0.0f) {
            let dp = sqrt(max(dot(oc, oc) - bq * bq, 0.0f));    // the ray's miss distance
            let sw = 0.5f * blur * (-bq) + 1e-3f;                // the lobe's radius there
            let wb = smoothstep(R_BALL + sw, max(R_BALL - sw, 0.0f), dp) * saturate(sq(R_BALL / max(sw, R_BALL)));
            if (wb > 0.0f) {
                let nh = select(normalize(oc - Rv * bq),                    // or its limb
                                normalize(oc + Rv * (-bq - sqrt(hq))),      // where the ray meets it
                                hq > 0.0f);
                envc = mix(envc, ball_diffuse(nh, B, vec3f(0.0f)), ba * wb);
            }
        }
    }
    let Fr = select(0.0f, env_brdf(f0, rough, ndv), f0 > 0.0f);   // Fresnel over the satin lobe
    let col_d = alb * diffuse_light(n) * ao * shadow * (1.0f - Fr) + Fr * envc * mix(1.0f, ao, 0.7f) * (0.4f + 0.6f * shadow);
    let col_m = schlick3(CHROME, ndv) * envc * (0.35f + 0.65f * shadow) * mix(1.0f, ao, 0.6f);
    var col = mix(col_d, col_m, met);
    // the felt's cloth sheen (Charlie lobe, Estevez & Kulla 2017; see felt_sheen): faint from
    // straight above, a little stronger toward the screen's edges, as baize does.
    if (r >= R_APRON_OUT) { col += felt_sheen(P, V) * ao * mix(0.4f, 1.0f, shadow); }
    // the frets over the pocket floors: chrome facets, composited by their coverage
    let fret_all = fret_top + fret_ccw + fret_cw + fret_occw + fret_ocw;
    if (fret_all > 0.0f) {
        let Pf = vec3f(rh * fret_zr.y, fret_zr.x);
        let lit = 0.35f + 0.65f * shadow;
        let n_t = vec3f(0.0f, 0.0f, 1.0f);
        let n_a = normalize(vec3f(th * 0.5f, 1.0f)); let n_b = normalize(vec3f(-th * 0.5f, 1.0f));   // 27 deg
        let ct = schlick3(CHROME, dot(n_t, V)) * env(Pf, reflect(dir, n_t), 0.35f, S.rotor, dphi);
        let ca = schlick3(CHROME, saturate(dot(n_a, V))) * env(Pf, reflect(dir, n_a), 0.6f, S.rotor, dphi);
        let cb = schlick3(CHROME, saturate(dot(n_b, V))) * env(Pf, reflect(dir, n_b), 0.6f, S.rotor, dphi);
        // the outer shoulders mirror the shaded pocket floor beside them (chrome at ~67 deg)
        let fo = schlick3(CHROME, 0.39f) * (0.22f * DL_UP);
        col = col * (1.0f - fret_all) + lit * (fret_top * ct + fret_ccw * ca + fret_cw * cb
                                              + fo * (fret_occw * fret_pa + fret_ocw * fret_pb));
    }

    // ---------------------------------------------------- handle arms + knobs --
    var arm_cov = 0.0f;   // hides the ball when it is below them
    {
        let zc = ARM_Z;
        let Q = uv * (H_EYE - zc) / FC;
        let rq = length(Q);
        if (rq < KNOB_AT + KNOB_R + 0.5f && rq > ARM_R0 - 0.2f) {
            let aq = atan2(Q.y, Q.x) - S.rotor - ARM_A0;
            let qa = 1.5707963f;
            let rel = aq - qa * round_m(aq / qa);           // angle to the nearest arm's centre (at shutter mid)
            let wv = dphi;
            let pq = pix / max(rq, 0.5f);
            // rod
            let arad = arm_radius((rq - ARM_R0) / (ARM_R1 - ARM_R0));
            let hr = arad / rq;
            let lo = max(rel - 0.5f * (wv + pq), -hr); let hi = min(rel + 0.5f * (wv + pq), hr);
            var cov = saturate((hi - lo) / (wv + pq));
            cov *= smoothstep(ARM_R0 - pix, ARM_R0 + pix, rq) * smoothstep(ARM_R1 + pix, ARM_R1 - pix, rq);
            // knob
            let dk = rq - KNOB_AT;
            let hk = sqrt(max(KNOB_R * KNOB_R - dk * dk, 0.0f)) / rq;
            let lok = max(rel - 0.5f * (wv + pq), -hk); let hik = min(rel + 0.5f * (wv + pq), hk);
            let covk = select(0.0f, saturate((hik - lok) / (wv + pq)) * smoothstep(KNOB_R + pix, KNOB_R - pix, abs(dk)), abs(dk) < KNOB_R + pix);
            let c = max(cov, covk);
            if (c > 0.0f) {
                // normal at the middle of the covered interval
                let mid = 0.5f * (lo + hi);
                let kn = covk > cov;
                var na: vec3f;
                let qr = Q / rq; let qt = vec2f(-qr.y, qr.x);
                if (kn) {
                    let mk = 0.5f * (lok + hik);
                    let o = vec2f(dk, mk * rq) / KNOB_R;
                    na = vec3f(qr * o.x + qt * o.y, sqrt(max(1.0f - dot(o, o), 0.02f)));
                } else {
                    let o = clamp(mid * rq / arad, -1.0f, 1.0f);
                    na = vec3f(qt * o, sqrt(max(1.0f - o * o, 0.02f)));
                }
                na = normalize(na);
                let Pa = vec3f(Q, zc + 0.3f);
                let Ra = reflect(dir, na);
                let ca = schlick3(CHROME, saturate(dot(na, V))) * env(Pa, Ra, 0.02f + 4.0f * pix / (select(arad, KNOB_R, kn) * max(na.z, 0.12f)), S.rotor, dphi);
                col = mix(col, ca, c);
                arm_cov = c;
            }
        }
    }

    // ---------------------------------------------------- the ball --
    // Swept over its shutter along its path in polar coordinates about the axis (the rim ball
    // circles: a straight streak would cut the chord), as 4 capsules, each a quarter of the
    // shutter time; the coverage is the share of the shutter the ball covers the pixel.
    var ball_cov = 0.0f;
    if (ba > 0.0f) {
        let rB = length(B.xy);
        let vB = S.ball_vel;
        let polar = rB > 3.0f;
        let eB = B.xy / max(rB, 1e-3f);
        let vr = dot(vB.xy, eB); let om = (eB.x * vB.y - eB.y * vB.x) / max(rB, 1e-3f); let thB = atan2(B.y, B.x);
        let pA = ball_at(B, vB, -0.5f * SHb, polar, rB, thB, vr, om); let pZ = ball_at(B, vB, 0.5f * SHb, polar, rB, thB, vr, om);
        let cA = pA.xy * FC / (H_EYE - pA.z); let cZ = pZ.xy * FC / (H_EYE - pZ.z);
        let rb0 = R_BALL * FC / (H_EYE - B.z);
        // bound: the swept arc lies within its chord's circle widened by the arc's sag
        let cM = B.xy * FC / (H_EYE - B.z);
        if (length(uv - cM) < rb0 + 0.5f * length(cZ - cA) + 0.3f * length(cZ - cA) + 2.0f * uvpix) {
            var covT = 0.0f; var dBest = 1e9f;
            var ocBest = vec2f(0.0f);
            var Bbest = B;
            var rbBest = rb0;
            var pa = pA;
            var ca = cA;
            for (var i = 0; i < 4; i++) {
                let pb = ball_at(B, vB, SHb * (0.25f * f32(i + 1) - 0.5f), polar, rB, thB, vr, om);
                let cb2 = pb.xy * FC / (H_EYE - pb.z);
                let rb = R_BALL * FC / (H_EYE - 0.5f * (pa.z + pb.z));
                let sw = cb2 - ca; let mid = 0.5f * (ca + cb2);
                let L = length(sw);
                let ax = select(vec2f(1.0f, 0.0f), sw / L, L > 1e-6f);
                let o = uv - mid;
                let u = dot(o, ax); let wv = dot(o, vec2f(-ax.y, ax.x));
                let Lp = max(L, uvpix);
                let hh = sqrt(max(sq(rb + 0.5f * uvpix) - wv * wv, 0.0f));
                let lo = max(u - hh, -0.5f * Lp); let hi = min(u + hh, 0.5f * Lp);
                let ci = saturate((hi - lo) / Lp) * smoothstep(rb + uvpix, rb, abs(wv));
                covT += 0.25f * ci;
                // the normal: from the nearest point of the centre's whole path (a still ball is a
                // sphere; a streak is round across and at its two ends)
                let off = o - ax * clamp(u, -0.5f * L, 0.5f * L);
                let dd = dot(off, off);
                if (dd < dBest) { dBest = dd; ocBest = off / rb; Bbest = 0.5f * (pa + pb); rbBest = rb; }
                pa = pb; ca = cb2;
            }
            if (covT > 0.0f) {
                // what lies under the ball, lit (its bounce light)
                let ball_under = wheel_image(B, vec3f(0.0f, 0.0f, -1.0f), 0.3f, S.rotor, dphi);
                let l2 = dot(ocBest, ocBest);
                let nb = normalize(vec3f(ocBest, sqrt(max(1.0f - l2, 0.0f)) + 0.02f));
                let Pb = Bbest + nb * R_BALL;
                let ndvb = saturate(dot(nb, V));
                let Fb = env_brdf(F0_BALL, ROUGH_BALL, ndvb);  // over its satin lobe
                let Rb = reflect(dir, nb);
                // contact: the limb darkens toward the surface it rests on
                let hgt = B.z - R_BALL - scene_rev(rB);
                let aob = 1.0f - 0.6f * pow(1.0f - saturate(nb.z), 2.5f) * saturate(1.0f - hgt / 1.5f);
                let dif = ball_diffuse(nb, Bbest, ball_under) * aob;
                // satin PTFE: a 0.12 rad lobe, so the light box is a small soft patch toward it
                let spc = env(Pb, Rb, ggx_lobe(ROUGH_BALL) + 2.0f * pixang / max(rbBest, 1e-3f), S.rotor, dphi);
                let cball = dif * (1.0f - Fb) + Fb * spc;
                // the overhanging lip (or anything else standing higher here) hides the ball
                let vis = smoothstep(-0.06f, 0.06f, Pb.z - z) * (1.0f - arm_cov * step(Pb.z, ARM_Z));
                ball_cov = covT * ba * vis;
                col = mix(col, cball, ball_cov);
            }
        }
    }

    // ---------------------------------------------------- finish --
    col *= 1.0f - 0.10f * dot(uv, uv) * 0.25f;
    col *= 1.45f;   // exposure
    return vec4f(col, ball_cov);
}

// The static part of the picture, baked once by argus_init into rows 1.. of the state (one pixel
// per float, four per texel, at 1920x1200): the felt's final 8-bit colour packed as -(rgb + 1)
// (nothing on the felt moves), and on the wheel the height the camera sees (the surface search
// depends only on the pixel). Z_LIVE marks pixels shaded live (the lip and gap edges, where two
// sides blend). Another output size (the harness's watchdog, previews) draws everything live.
fn bake_px(px: vec2u) -> f32 {
    if (px.x >= f.width || px.y >= f.height) { return Z_LIVE; }
    let uv = argus_uv(px, f);
    let rho = length(uv) / FC;
    let ppx = 0.5f * FC * f32(f.height);
    let dl = (rho - RHO_LIP) * ppx;
    if ((rho - RHO_GAP_IN) * ppx > -0.6f && (rho - RHO_GAP_OUT) * ppx < 0.6f) { return Z_LIVE; }
    if (dl < 0.5f && dl > -0.5f) { return Z_LIVE; }
    let side = side_of(select(2, 1, dl < 0.5f));
    let r0 = rho * H_EYE;
    if (r0 >= R_APRON_OUT + 1.0f) {
        var S0: WheelState;
        S0.rotor = 0.0f; S0.rotor_vel = 0.0f; S0.ball = vec3f(0.0f, 0.0f, -100.0f); S0.ball_vel = vec3f(0.0f);
        S0.ball_roll = 0.0f; S0.ball_alpha = 0.0f; S0.winner = -1;
        let c = argus_srgb(argus_aces(shade_px(uv, 2, S0, 0.0f).rgb));
        let q = vec3u(round(saturate(c) * 255.0f));   // Metal's rint(): halfway cases to even
        return -f32((q.x << 16u) | (q.y << 8u) | q.z) - 1.0f;
    }
    return visible_z(rho, side);
}
fn bake4(gid: vec2u) -> vec4f {
    let p = vec2u(4u * gid.x, gid.y - 1u);
    return vec4f(bake_px(p), bake_px(p + vec2u(1u, 0u)), bake_px(p + vec2u(2u, 0u)), bake_px(p + vec2u(3u, 0u)));
}

@compute @workgroup_size(16, 16)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let S = wheel_state(f.time);
    let uv = argus_uv(gid, f);
    let rho = length(uv) / FC;
    let ppx = 0.5f * FC * f32(f.height);   // pixels per unit of rho
    let dl = (rho - RHO_LIP) * ppx;   // pixels outside the lip's edge
    // the rotor-stator gap: the share of the pixel (radially) it covers
    let gap = saturate((min(rho + 0.5f / ppx, RHO_GAP_OUT) - max(rho - 0.5f / ppx, RHO_GAP_IN)) * ppx);
    let near_gap = (rho - RHO_GAP_IN) * ppx > -0.6f && (rho - RHO_GAP_OUT) * ppx < 0.6f;
    // one call site (a loop of one or two), so the shading is compiled once
    let k0 = select(select(2, 1, dl < 0.5f), select(4, 3, rho < 0.5f * (RHO_GAP_IN + RHO_GAP_OUT)), near_gap);
    let k1 = select(select(1, 2, dl > -0.5f), k0, near_gap);
    var zb = Z_LIVE;
    let bk = textureLoad(argus_state, vec2u(10u, 0u), 0);
    if (bk.z == BAKE_TAG && u32(bk.x) == f.width && u32(bk.y) == f.height) {
        let v = textureLoad(argus_state, vec2u(gid.x >> 2u, gid.y + 1u), 0)[gid.x & 3u];
        if (v < 0.0f) {   // the felt: its final colour, baked
            let q = u32(-v - 1.0f);
            textureStore(argus_out, gid, vec4f(f32(q >> 16u), f32((q >> 8u) & 255u), f32(q & 255u), 255.0f) / 255.0f);
            return;
        }
        zb = v;
    }
    var col = vec4f(0.0f);
    for (var k = k0; k <= k1; k++) {
        col += shade_px(uv, k, S, zb) * select(select(0.5f - dl, dl + 0.5f, k == 2), 1.0f, k0 == k1);
    }
    // the dark slot lies under the ball: only the part of the pixel the ball leaves open shows it
    if (near_gap) { col = vec4f(mix(col.rgb, GAP_C, gap * (1.0f - saturate(col.w))), col.w); }
    textureStore(argus_out, gid, vec4f(argus_srgb(argus_aces(col.rgb)), 1.0f));
}

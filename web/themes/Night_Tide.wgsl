// ============================================================================
// NIGHT TIDE // themes/Night_Tide.metal
// The WGSL translation of themes/Night_Tide.metal (web/themes/Night_Tide.wgsl), one to one.
// Author: Claude Opus (Anthropic), 2026-10-15.
//
// A beach on a moonless night during a red tide. Swells roll in dark from the
// open sea, steepen over the sandbar and break; where the water tears, the
// dinoflagellates in it flash blue, so the light runs along the breaking lip,
// boils in the whitewater, rides the wash up the sand and drains away again.
// Overhead, stars and a faint Milky Way; the wet sand mirrors both.
//
// The light is a consequence of the water, as it is at sea:
//   - Cells (Lingulodinium polyedrum in California red tides) flash only above a
//     shear-stress threshold that ordinary ocean motion doesn't reach but
//     breaking waves do (Latz & Rohr 1999; Cussatlegras & Le Gal 2005). So here
//     the swells are dark and only breaking, churning and running water glows.
//   - Each flash is brief (reported ~0.1-0.5 s) and blue (~475 nm); the glow is
//     millions of them, so it is grainy and fades fast behind the foam.
//   - Cells that have flashed need time to recover, so water that just lit up
//     glows less the next time it is stirred.
//   - To the eye the glow is a soft grey-blue, whiter in the brightest foam;
//     long-exposure photos make it neon. This aims between the two.
//
// How it works: a 1024x384 state texture is a top-down map of the surf zone
// (128 m along the beach, 48 m out to sea). Every frame, argus_step evaluates how hard
// the water is being stirred at each cell (from an analytic model of shoaling
// swells, breakers, bores and swash) and updates that cell's light, its charge
// (ability to flash) and a softly spreading halo. argus_draw raymarches the
// sea and the beach from a viewer standing on the sand, looking along the
// shore, and lights them with that map.
//
// @argus state 1024x384
// @argus steps 1
// ============================================================================

const EYE_Y: f32 = 1.95;       // eye height above still water (about 1.5 m above the sand)
const CAM_Z: f32 = -1.5;       // standing on the beach, 6.5 m back from the waterline
const YAW: f32 = 0.85;         // looking along the beach, ~49 degrees to the right of straight out
const SHORE: f32 = 5.0;        // still-water line, metres in front of the eye
const BEACH_SLOPE: f32 = 0.07; // about 1:14
const T_WAVE: f32 = 8.0;       // seconds between waves
const MAP_X0: f32 = -24.0;     // the map spans 128 m along the beach and wraps (endless) ...
const MAP_W: f32 = 128.0;
const MAP_Z: f32 = 48.0;       // ... and z in [0, 48] m
const FOCAL: f32 = 1.45;
const HORIZON_UV: f32 = 0.28;  // where the horizon sits on screen (uv.y)

// ---------------------------------------------------------------- the waves --

struct Sea {
    h: f32,     // water surface above still water (m)
    stir: f32,  // how hard the water is being torn: drives the flashes
    foam: f32,  // whitewater cover, 0..1
    sheet: f32, // swash sheet depth on the sand (m)
}

// The beach is endless: everything baked into the surf map repeats exactly every
// MAP_W metres along the shore, and the map wraps, so a wave can peel down the
// beach as far as the eye sees instead of running into the map's edge. Noise
// along x uses this lattice that wraps after `cells` cells (cells = MAP_W x the
// frequency, a whole number), and sines along x use whole cycles per MAP_W.
fn noiseP(p: vec2f, cells: f32) -> f32 {
    let i = floor(p);
    let fr = p - i;
    let u = fr * fr * (3.0 - 2.0 * fr);
    let ix0 = i.x - cells * floor(i.x / cells);
    let ix1 = select(ix0 + 1.0, 0.0, ix0 + 1.0 >= cells);
    let y0 = u32(i32(i.y) + 32768); let y1 = y0 + 1u;
    let x0 = u32(ix0) + 32768u; let x1 = u32(ix1) + 32768u;
    let a = argus_rand(vec2u(x0, y0), 0u); let b = argus_rand(vec2u(x1, y0), 0u);
    let d = argus_rand(vec2u(x0, y1), 0u); let e = argus_rand(vec2u(x1, y1), 0u);
    return 2.0 * mix(mix(a, b, u.x), mix(d, e, u.x), u.y) - 1.0;
}
const KX: f32 = 6.2831853 / 128.0;   // one cycle per MAP_W along the beach

fn rand1(n: f32) -> f32 { return argus_rand(vec2u(u32(i32(n) + 100000), 17u), 5u); }

// Crest distance from the eye for a wave of this age (seconds): it slows as the
// water shoals, from 48 m out to the shore in about 12 s.
fn crestZ(age: f32) -> f32 { return -14.0 + 62.0 * exp(-0.1 * age); }
fn ageAt(z: f32) -> f32 { return log(62.0 / max(z + 14.0, 1e-3)) / 0.1; }

fn sea(x: f32, z: f32, t: f32) -> Sea {
    var s = Sea(0.0, 0.0, 0.0, 0.0);
    let n0 = floor(t / T_WAVE);
    for (var k = 0; k < 4; k++) {
        let n = n0 - f32(k);
        let r = rand1(n);
        let age = t - n * T_WAVE - 1.5 * r;
        if (age < 0.0) { continue; }
        // Cheap early out before the noise work: a cell this wave can't touch.
        // Its crest is within 2.3 m of crestZ(age) (the bend); nothing reaches
        // more than 6 m ahead of the crest or 30 m behind it, except the swash,
        // which lives within SHORE + 4 m and ends 8 s after the crest lands.
        {
            let zc0 = crestZ(age);
            let in_swash_zone = z < SHORE + 4.0 && age < ageAt(SHORE + 1.5 - 2.3) + 8.0;
            if (!in_swash_zone && (z < zc0 - 8.3 || z > zc0 + 32.3)) { continue; }
            if (age > ageAt(SHORE + 1.5 - 2.3) + 8.0 && z < SHORE + 4.0) { continue; }
        }
        // Wave size: mostly small to moderate, rising and falling in sets with lulls
        // between, and now and then (about one in twelve, at random) a big one.
        let sets = sin(n * 0.9) * sin(n * 0.37 + 1.0);           // -1..1, slow
        var amp = 0.45 + 0.30 * sets + 0.18 * (r - 0.5);
        amp = max(amp, 0.18);                                    // lulls dribble in
        let rogue = rand1(n * 7.0 + 3.0);
        if (rogue > 0.917) { amp = 1.35 + 0.9 * (rogue - 0.917) / 0.083; } // the big ones
        // Along the crest: two swell trains from slightly different directions
        // interfere, so the wave stands up into peaks where they agree and sags
        // where they don't. The pattern drifts from wave to wave; when a peak meets
        // a set wave or a big one, that part of the wave gets much bigger.
        let beat = 0.5 + 0.5 * cos(x * 2.0 * KX + n * 1.9 + 0.8 * sin(x * KX + n * 0.7));
        let along = 0.35 + 1.3 * beat * beat + 0.25 * noiseP(vec2f(x * 0.0625 + n * 0.4, 11.0), 8.0);
        amp = min(amp * along, 2.6);
        let bend = 1.4 * sin(KX * x + 2.1 * n) + 0.9 * noiseP(vec2f(x * 0.0703125, n * 3.1), 9.0);
        let zc = crestZ(age) + bend;
        // The sandbar: waves break where it's shallow, so the break peels along x.
        let zb = 17.0 + 4.0 * noiseP(vec2f(x * 0.046875 + n * 0.17, 3.0), 6.0) + 1.5 * amp;
        let d = z - zc; // > 0 behind the crest (seaward), < 0 in front
        if (zc > SHORE) {
            // Blend from swell to breaking bore across the break, so the wave
            // changes shape smoothly along the peeling line.
            let bw = smoothstep(zb + 1.2, zb - 1.8, zc);
            // An unbroken swell, growing as it shoals; steep face, long back.
            let grow = smoothstep(48.0, zb, zc);
            let a = amp * (0.25 + 0.6 * grow);
            s.h += (1.0 - bw) * a * select(exp(-(d * d) / 30.0), exp(-(d * d) / 2.2), d < 0.0);
            // At the break the lip pitches over and tears.
            let lip = smoothstep(3.0, 0.0, abs(zc - zb + 0.3));
            s.stir += amp * lip * 1.3 * exp(-(d + 0.4) * (d + 0.4) / 0.5);
            s.foam += lip * 0.4 * exp(-(d * d) / 0.4);
            // The breaking bore: a step of churned water running toward the beach.
            // Near the beach the bore hands over to the swash: fade it out over the
            // last 3 m, so no seam opens where one part of the crest has reached the
            // shoreline and the next hasn't.
            let landing = smoothstep(SHORE, SHORE + 3.0, zc);
            if (bw > 0.0 && landing > 0.0) {
                let strength = saturate((zc - SHORE) / max(zb - SHORE, 1.0));
                let hb = amp * 0.4 * (0.25 + 0.75 * strength);
                let front = smoothstep(-0.4, 0.15, d);
                let tail = exp(-max(d, 0.0) / (2.5 + 7.0 * (1.0 - strength)));
                s.h += bw * landing * hb * front * tail;
                let churn = 0.5 + 0.5 * noiseP(vec2f(x * 1.6015625 + n * 7.0, z * 1.2 - t * 2.2), 205.0);
                s.stir += bw * landing * amp * (0.4 + 0.6 * strength) * (1.2 * exp(-(d * d) / 0.35) + 0.75 * front * tail * churn);
                s.foam += bw * landing * front * tail * (0.55 + 0.45 * churn);
            }
        }
        // Swash: a thin sheet runs up the sand, stalls, and mostly sinks into it.
        // It parts first where the wave landed: that end drains back toward the
        // sea, the film left up the beach soaks in, and its edge creeps back only
        // a little. It starts while the bore is still landing (the
        // crest 1.5 m from the waterline) and ramps in, so the hand-over has no seam.
        let z0 = SHORE + 1.5;
        let tau = age - ageAt(z0 - bend);
        let ts = 8.0;
        if (tau < 0.0 || tau > ts) { continue; }
        let p = tau / ts;
        let ramp = smoothstep(0.0, 0.08, p);
        let run = 2.4 + 1.6 * amp; // from z0 up the sand
        let up = saturate(p / 0.3);
        // Its own momentum carries it up the slope, slowing like a thrown ball,
        // until it stops; then the edge slips back a little as it drains.
        let zs = z0 - run * (1.0 - (1.0 - up) * (1.0 - up)) + 0.08 * run * smoothstep(0.3, 1.0, p);
        let cover = smoothstep(zs - 0.15, zs + 0.6, z) * (1.0 - smoothstep(z0, z0 + 2.0, z));
        // Draining: the seaward end (where it landed) clears first, then the
        // stranded film up the beach soaks away.
        let toward_front = saturate((z0 - z) / max(z0 - zs, 0.1));
        let soak = smoothstep(0.30 + 0.25 * toward_front, 0.62 + 0.33 * toward_front, p);
        s.sheet = max(s.sheet, 0.06 * ramp * (1.0 - soak) * cover);
        let edge = exp(-((z - zs) * (z - zs)) / 0.15);
        s.stir += ramp * (amp * select(0.12, 1.8, p < 0.3) * edge + 0.45 * amp * (1.0 - up * 0.6) * (1.0 - soak) * cover);
        s.foam += ramp * (1.0 - soak) * 0.5 * cover;
    }
    // Small wind ripples everywhere.
    s.h += 0.025 * noiseP(vec2f(x * 0.8984375 + t * 0.3, z * 1.4 - t * 0.6), 115.0);
    s.foam = saturate(s.foam);
    return s;
}

// The beach: a 1:14 slope with beach cusps (the scalloped ridges a few metres
// apart that swash carves on real beaches) and a gently wandering waterline.
fn sandY(x: f32, z: f32) -> f32 {
    let near = smoothstep(SHORE + 4.0, SHORE - 3.0, z);
    let cusps = 0.07 * sin(x * 15.0 * KX) * near;
    let wander = 0.10 * noiseP(vec2f(x * 0.0625, 1.7), 8.0);
    // Landward the slope rolls over into a flat berm about 0.8 m up.
    let rise = BEACH_SLOPE * (SHORE - z);
    let berm = 0.8 - 0.8 * exp(-max(rise, 0.0) / 0.8);
    return select(rise, berm, rise > 0.0) + cusps + wander;
}

// ------------------------------------------------------------ the glow map --

fn mapUV(x: f32, z: f32) -> vec2f { return vec2f((x - MAP_X0) / MAP_W, z / MAP_Z); }
fn inMap(x: f32, z: f32) -> bool { return z > 0.1 && z < MAP_Z - 1.0; }   // endless along x

@compute @workgroup_size(8, 8)
fn argus_init(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    // x: light now; y: charge (ability to flash); z: soft halo; w: unused.
    textureStore(argus_state_out, gid, vec4f(0.0, 1.0, 0.0, 0.0)); // w (height) is filled by the first step
}

// The halo's neighbour read: wraps along x, clamps along y.
fn at(gid: vec2u, w: u32, h: u32, dx: i32, dy: i32) -> f32 {
    return textureLoad(argus_state, vec2u(u32((i32(gid.x) + dx + i32(w)) % i32(w)), u32(clamp(i32(gid.y) + dy, 0, i32(h) - 1))), 0).z;
}

@compute @workgroup_size(8, 8)
fn argus_step(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    let w = f.state_width; let h = f.state_height;
    if (gid.x >= w || gid.y >= h) { return; }
    let dt = clamp(f.dt, 0.0, 0.1);
    let uv = argus_uv01(gid, w, h);
    let x = MAP_X0 + uv.x * MAP_W;
    let z = uv.y * MAP_Z;

    let c = textureLoad(argus_state, gid, 0);
    var light = c.x; var charge = c.y;

    let s = sea(x, z, f.time);
    // Each map cell stands for a patch of water holding many cells. The share of
    // them pushed past their flash threshold grows with how hard the water is
    // torn; cells that flash spend their charge and recover over tens of seconds.
    // (The draw adds the grain: individual flashes are finer than this map.)
    let share = smoothstep(0.2, 1.6, s.stir);
    let flash = share * charge;
    light = max(light * exp(-dt / 0.2), 0.95 * flash); // flashes last a fraction of a second
    charge = saturate(charge - flash * dt * 1.6 + dt / 25.0);

    // The halo: light scattered in the water spreads a little and fades.
    let spread = 0.25 * (at(gid, w, h, 2, 0) + at(gid, w, h, -2, 0) + at(gid, w, h, 0, 2) + at(gid, w, h, 0, -2));
    let halo = (0.55 * c.z + 0.45 * spread) * exp(-dt / 0.35) + 0.06 * light;

    // w: the height of whatever is there (water, or sand when it's dry), for the draw.
    let sand = sandY(x, z);
    let surf = max(sand, select(sand + s.sheet, s.h, z >= SHORE));
    textureStore(argus_state_out, gid, vec4f(light, charge, min(halo, 2.0), surf));
}

// ------------------------------------------------------------------- the sky --

fn skyColour(dir: vec3f, t: f32, seed: u32, with_stars: bool) -> vec3f {
    let elev = max(dir.y, 0.0);
    // No moon, no towns: the sky is all but black, a touch lighter low down.
    var col = mix(vec3f(0.0030, 0.0038, 0.0060), vec3f(0.0004, 0.0006, 0.0012), saturate(elev * 3.0));
    // Spherical-ish coordinates for stars and the galaxy.
    let az = atan2(dir.x, dir.z);
    let sp = vec2f(az * 2.0, elev * 3.2);
    // The Milky Way: a soft tilted band with dark dust lanes.
    let band = sp.y - 0.55 - 0.35 * sp.x;
    let mw = exp(-band * band * 6.0);
    let dust = smoothstep(-0.1, 0.5, argus_fbm(sp * 3.0 + vec2f(4.0, 1.0), 5));
    col += mw * (0.003 + 0.009 * max(argus_fbm(sp * 9.0, 4), 0.0)) * (1.0 - 0.85 * dust) * vec3f(0.85, 0.88, 1.0);
    if (!with_stars) { return col + vec3f(0.0018, 0.0024, 0.0020) * exp(-elev * 25.0); }
    // Stars: denser in the band; each cell holds at most one.
    let g = sp * 160.0;
    let cell = floor(g);
    let r = argus_rand(vec2u(vec2i(cell) + 50000), seed);
    let dens = 0.978 - 0.02 * mw;
    if (r > dens) {
        let off = vec2f(argus_rand(vec2u(vec2i(cell) + 50000), seed + 9u), argus_rand(vec2u(vec2i(cell) + 50000), seed + 13u)) - 0.5;
        let dd = length(fract(g) - 0.5 - off * 0.6);
        let mag = (r - dens) / (1.0 - dens);
        // Scintillation: fast, irregular, and strongest near the horizon, where
        // the light crosses the most air.
        let depth_air = 0.25 + 0.6 * exp(-elev * 6.0);
        let flick = 0.5 + 0.5 * argus_noise(vec2f(t * 9.0 + r * 80.0, r * 13.0));
        let tw = 1.0 - depth_air * flick;
        col += mag * mag * tw * smoothstep(0.18, 0.0, dd) * mix(vec3f(1.0, 0.85, 0.7), vec3f(0.75, 0.85, 1.0), fract(r * 97.0)) * 2.2;
    }
    // A sparse layer of bright stars, each with a soft halo.
    let g2 = sp * 48.0;
    let cell2 = floor(g2);
    let r2 = argus_rand(vec2u(vec2i(cell2) + 90000), seed + 31u);
    if (r2 > 0.975) {
        let off = vec2f(argus_rand(vec2u(vec2i(cell2) + 90000), seed + 37u), argus_rand(vec2u(vec2i(cell2) + 90000), seed + 41u)) - 0.5;
        let dd = length(fract(g2) - 0.5 - off * 0.6);
        let mag = (r2 - 0.975) / 0.025;
        let depth_air = 0.2 + 0.6 * exp(-elev * 6.0);
        let flick = 0.5 + 0.5 * argus_noise(vec2f(t * 8.0 + r2 * 90.0, r2 * 17.0));
        let tw = 1.0 - depth_air * flick;
        let tint = mix(vec3f(1.0, 0.82, 0.62), vec3f(0.72, 0.84, 1.0), fract(r2 * 71.0));
        col += tw * (0.6 + 2.4 * mag * mag) * (smoothstep(0.06, 0.0, dd) + 0.06 * exp(-dd * dd * 60.0)) * tint;
    }
    // A faint airglow just above the horizon.
    col += vec3f(0.0018, 0.0024, 0.0020) * exp(-elev * 25.0);
    return col;
}

// ------------------------------------------------------------------ drawing --

fn glowColour(g: f32) -> vec3f {
    // Blue at low levels, whiter in the brightest foam (as the eye sees it).
    return g * vec3f(0.10, 0.50, 1.00) * 1.4 + g * g * vec3f(0.35, 0.45, 0.45);
}

// The surface height: from the map over the surf zone; dry sand landward of
// it; a calm far sea beyond it. (Metal: a lambda in argus_draw, sampling the state
// with filter::linear, s_address::repeat, t_address::clamp_to_edge.)
fn height(x: f32, z: f32, t: f32) -> f32 {
    if (inMap(x, z)) { return argus_sample(argus_state, argus_linear_repeat_s, mapUV(x, z)).w; }
    if (z < SHORE) { return sandY(x, z); }
    return 0.02 * argus_noise(vec2f(x * 0.5 + t * 0.2, z * 0.6 - t * 0.4));
}

@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let t = f.time;
    let uv = argus_uv(gid, f);
    // The camera stands on the beach and looks along it: rotate the view ray.
    let v = normalize(vec3f(uv.x, uv.y - HORIZON_UV, FOCAL));
    let cy = cos(YAW); let sy = sin(YAW);
    let dir = vec3f(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy);
    let eye = vec3f(0.0, EYE_Y, CAM_Z);

    var col: vec3f;
    if (dir.y >= -0.0005) {
        col = skyColour(dir, t, f.seed, true);
    } else {
        // March along the ray from where it is 2.4 m above still water (the biggest
        // waves' crests) to where it meets still water, then refine.
        let s_top = max(0.3, (EYE_Y - 2.4) / -dir.y);
        let s_flat = (EYE_Y + 0.05) / -dir.y;
        let s_end = min(s_flat + 1.0, 3000.0);
        let s_last = min(s_end, 160.0);
        var sa = s_top; var sb = s_end;
        var hit = false;
        if (s_top < s_last) {
            let steps = 24; // plus 6 refinement steps; finer showed no difference
            var prev_s = s_top;
            for (var i = 1; i <= steps; i++) {
                let ss = mix(s_top, s_last, f32(i) / f32(steps));
                let p = eye + dir * ss;
                if (p.y <= height(p.x, p.z, t)) {
                    sa = prev_s;
                    sb = ss;
                    hit = true;
                    break;
                }
                prev_s = ss;
            }
        }
        var dist = s_flat;
        if (hit) {
            for (var i = 0; i < 6; i++) {
                let sm = 0.5 * (sa + sb);
                let p = eye + dir * sm;
                if (p.y <= height(p.x, p.z, t)) { sb = sm; } else { sa = sm; }
            }
            dist = sb;
        }
        let hp = eye + dir * dist;
        let x = hp.x;
        let z = hp.z;
        let hgt = height(x, z, t);
        let sand = sandY(x, z);
        // Three materials: the sea (over sand that's always under water), the
        // swash (a thin sheet running over the beach), and the sand itself.
        let depth = hgt - sand;
        let sea = sand < -0.04 && depth > 0.004;
        let swash = !sea && depth > 0.003;
        let film = saturate(depth / 0.03);

        // Surface normal from the height field.
        let e = 0.08 + 0.006 * dist;
        let hx = height(x + e, z, t) - height(x - e, z, t);
        let hz = height(x, z + e, t) - height(x, z - e, t);
        let nrm = normalize(vec3f(-hx, 2.0 * e, -hz));

        var g = vec4f(0.0);
        if (inMap(x, z)) { g = argus_sample(argus_state, argus_linear_repeat_s, mapUV(x, z)); }
        // Fine sparkle: the glow is millions of tiny flashes, finer than the map.
        // Flashes last a fraction of a second, so the grain needn't stay put in the
        // world: it is drawn in 2x2-pixel cells on screen, renewed every 2 frames.
        let grain_cell = gid / 2u;
        // Most flashes are faint and a few are bright.
        let rr = argus_rand(grain_cell, f.seed + f.frame / 2u);
        let sparkle = 0.3 + 2.8 * rr * rr * rr;
        // Whitewater lights in streaks and patches that ride shoreward with it.
        // (Only worth computing where there is light to shape.)
        var foam_tex = 0.0;
        if (g.x + g.z > 1e-4) {
            let fp = vec2f(x * 0.55, (z + 2.2 * t) * 0.9);
            let streaks = argus_fbm(fp + 0.6 * vec2f(argus_noise(fp * 0.5 + 7.0), 0.0), 4);
            foam_tex = 0.25 + 0.95 * smoothstep(-0.35, 0.45, streaks);
        }
        let glow = (g.x * sparkle + 0.2 * g.z) * foam_tex;

        if (sea) {
            // A turbulent sea: the chop scatters the reflection into a dim, broken
            // sheen (no mirrored stars), and the water itself is dark and opaque.
            let cp = vec2f(x * 2.6 + t * 0.7, z * 3.4 - t * 1.1);
            let chop = 0.35 * vec3f(argus_noise(cp), 0.0, argus_noise(cp + 17.3));
            let rn = normalize(nrm + chop);
            let rr = reflect(dir, rn);
            let fres = 0.02 + 0.98 * pow(1.0 - saturate(-dot(dir, rn)), 5.0);
            col = skyColour(vec3f(rr.x, abs(rr.y), rr.z), t, f.seed, false) * fres * 0.45;
            col += vec3f(0.0010, 0.0018, 0.0030);
            // Shimmer: tiny wave facets tilted just right flash the faint light of the
            // sky low over the horizon back at the eye, and move with the chop.
            let gp = vec2f(x * 9.0 + t * 1.3, z * 11.0 - t * 1.9);
            let facet = argus_noise(gp) * argus_noise(gp * 1.7 + 23.0);
            let glint = smoothstep(0.30, 0.60, facet) * (0.4 + 0.6 * fres);
            col += glint * vec3f(0.020, 0.028, 0.040) * exp(-dist * 0.02);
            col += glowColour(glow);
        } else if (swash) {
            // The swash is a glassy sheet: smooth enough to mirror the sky and the
            // glowing surf beyond it, brightest at grazing angles - a sheen quite
            // unlike the dark chop of the sea. Thin at its edges, it lets the wet
            // sand show through.
            let cp = vec2f(x * 4.0 + t * 0.5, z * 4.0 - t * 0.8);
            let rn = normalize(nrm + 0.05 * vec3f(argus_noise(cp), 0.0, argus_noise(cp + 9.1)));
            let rr = reflect(dir, rn);
            let fres = (0.02 + 0.98 * pow(1.0 - saturate(-dot(dir, rn)), 5.0)) * smoothstep(0.0, 0.6, film);
            let mirror = skyColour(vec3f(rr.x, abs(rr.y), rr.z), t, f.seed, true) * 5.0;
            // The surf's light, seen in the sheet: look a few metres along the reflection.
            let rxz = rr.xz / max(length(rr.xz), 1e-3);
            let seen = argus_sample(argus_state, argus_linear_repeat_s, mapUV(x + rxz.x * 3.0, z + rxz.y * 3.0));
            let wet_sand = vec3f(0.0026, 0.0026, 0.0028) * (0.85 + 0.15 * argus_noise(vec2f(x * 40.0, z * 40.0)));
            col = mix(wet_sand, mirror + glowColour(seen.x * 0.6 + 0.4 * seen.z), fres);
            col += glowColour(glow) * 0.9;
        } else {
            // Sand: matte and very dark, a little darker still where it's wet; it
            // reflects nothing, so the water and its glow carry the picture.
            let wet = smoothstep(SHORE - 4.5, SHORE - 1.0, z);
            let grain = 0.80 + 0.20 * argus_noise(vec2f(x * 40.0, z * 40.0))
                              + 0.08 * argus_noise(vec2f(x * 7.0, z * 7.0));
            let lambert = 0.6 + 0.4 * saturate(nrm.y);
            // At night the sand is the darkest thing in view.
            col = mix(vec3f(0.0042, 0.0040, 0.0036), vec3f(0.0026, 0.0026, 0.0028), wet) * grain * lambert;
            col += glowColour(glow) * 0.8; // stranded water still glows as it soaks in
        }
        // Distance haze toward the horizon.
        let haze = 1.0 - exp(-dist * 0.015);
        col = mix(col, vec3f(0.0022, 0.0030, 0.0048), haze * 0.85);
    }
    col = argus_aces(col * 2.2);
    textureStore(argus_out, gid, vec4f(argus_srgb(col), 1.0));
}

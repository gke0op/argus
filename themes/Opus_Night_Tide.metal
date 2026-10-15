// ============================================================================
// OPUS NIGHT TIDE // themes/Opus_Night_Tide.metal
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
// How it works: a 1536x512 state texture is a top-down map of the surf zone
// (128 m along the beach, 48 m out to sea). Every frame, argus_step evaluates how hard
// the water is being stirred at each cell (from an analytic model of shoaling
// swells, breakers, bores and swash) and updates that cell's light, its charge
// (ability to flash) and a softly spreading halo. argus_draw raymarches the
// sea and the beach from a viewer standing on the sand, looking along the
// shore, and lights them with that map.
//
// @argus state 1536x512
// @argus steps 1
// ============================================================================

constant float EYE_Y = 1.95f;       // eye height above still water (about 1.5 m above the sand)
constant float CAM_Z = -1.5f;       // standing on the beach, 6.5 m back from the waterline
constant float YAW = 0.85f;         // looking along the beach, ~49 degrees to the right of straight out
constant float SHORE = 5.0f;        // still-water line, metres in front of the eye
constant float BEACH_SLOPE = 0.07f; // about 1:14
constant float T_WAVE = 8.0f;       // seconds between waves
constant float MAP_X0 = -24.0f;     // the map spans x in [-24, 104] m (we look along it) ...
constant float MAP_W = 128.0f;
constant float MAP_Z = 48.0f;       // ... and z in [0, 48] m
constant float FOCAL = 1.45f;
constant float HORIZON_UV = 0.28f;  // where the horizon sits on screen (uv.y)

// ---------------------------------------------------------------- the waves --

struct Sea {
    float h;     // water surface above still water (m)
    float stir;  // how hard the water is being torn: drives the flashes
    float foam;  // whitewater cover, 0..1
    float sheet; // swash sheet depth on the sand (m)
};

static float rand1(float n) { return argus_rand(uint2(uint(int(n) + 100000), 17u), 5u); }

// Crest distance from the eye for a wave of this age (seconds): it slows as the
// water shoals, from 48 m out to the shore in about 12 s.
static float crestZ(float age) { return -14.0f + 62.0f * exp(-0.1f * age); }
static float ageAt(float z) { return log(62.0f / max(z + 14.0f, 1e-3f)) / 0.1f; }

static Sea sea(float x, float z, float t) {
    Sea s = {0.0f, 0.0f, 0.0f, 0.0f};
    const float n0 = floor(t / T_WAVE);
    for (int k = 0; k < 4; k++) {
        const float n = n0 - float(k);
        const float r = rand1(n);
        const float age = t - n * T_WAVE - 1.5f * r;
        if (age < 0.0f) continue;
        // Wave size: mostly small to moderate, rising and falling in sets with lulls
        // between, and now and then (about one in twelve, at random) a big one.
        const float sets = sin(n * 0.9f) * sin(n * 0.37f + 1.0f);           // -1..1, slow
        float amp = 0.45f + 0.30f * sets + 0.18f * (r - 0.5f);
        amp = max(amp, 0.18f);                                              // lulls dribble in
        const float rogue = rand1(n * 7.0f + 3.0f);
        if (rogue > 0.917f) amp = 1.35f + 0.9f * (rogue - 0.917f) / 0.083f; // the big ones
        // Along the crest: two swell trains from slightly different directions
        // interfere, so the wave stands up into peaks where they agree and sags
        // where they don't. The pattern drifts from wave to wave; when a peak meets
        // a set wave or a big one, that part of the wave gets much bigger.
        const float beat = 0.5f + 0.5f * cos(x * 0.11f + n * 1.9f + 0.8f * sin(x * 0.031f + n * 0.7f));
        const float along = 0.35f + 1.3f * beat * beat + 0.25f * argus_noise(float2(x * 0.06f + n * 0.4f, 11.0f));
        amp = min(amp * along, 2.6f);
        const float bend = 1.4f * sin(0.06f * x + 2.1f * n) + 0.9f * argus_noise(float2(x * 0.07f, n * 3.1f));
        const float zc = crestZ(age) + bend;
        // The sandbar: waves break where it's shallow, so the break peels along x.
        const float zb = 17.0f + 4.0f * argus_noise(float2(x * 0.045f + n * 0.17f, 3.0f)) + 1.5f * amp;
        const float d = z - zc; // > 0 behind the crest (seaward), < 0 in front
        if (zc > SHORE) {
            // Blend from swell to breaking bore across the break, so the wave
            // changes shape smoothly along the peeling line.
            const float bw = smoothstep(zb + 1.2f, zb - 1.8f, zc);
            // An unbroken swell, growing as it shoals; steep face, long back.
            const float grow = smoothstep(48.0f, zb, zc);
            const float a = amp * (0.25f + 0.6f * grow);
            s.h += (1.0f - bw) * a * (d < 0.0f ? exp(-(d * d) / 2.2f) : exp(-(d * d) / 30.0f));
            // At the break the lip pitches over and tears.
            const float lip = smoothstep(3.0f, 0.0f, abs(zc - zb + 0.3f));
            s.stir += amp * lip * 1.3f * exp(-(d + 0.4f) * (d + 0.4f) / 0.5f);
            s.foam += lip * 0.4f * exp(-(d * d) / 0.4f);
            // The breaking bore: a step of churned water running toward the beach.
            // Near the beach the bore hands over to the swash: fade it out over the
            // last 3 m, so no seam opens where one part of the crest has reached the
            // shoreline and the next hasn't.
            const float landing = smoothstep(SHORE, SHORE + 3.0f, zc);
            if (bw > 0.0f && landing > 0.0f) {
                const float strength = saturate((zc - SHORE) / max(zb - SHORE, 1.0f));
                const float hb = amp * 0.4f * (0.25f + 0.75f * strength);
                const float front = smoothstep(-0.4f, 0.15f, d);
                const float tail = exp(-max(d, 0.0f) / (2.5f + 7.0f * (1.0f - strength)));
                s.h += bw * landing * hb * front * tail;
                const float churn = 0.5f + 0.5f * argus_noise(float2(x * 1.6f + n * 7.0f, z * 1.2f - t * 2.2f));
                s.stir += bw * landing * amp * (0.4f + 0.6f * strength) * (1.2f * exp(-(d * d) / 0.35f) + 0.75f * front * tail * churn);
                s.foam += bw * landing * front * tail * (0.55f + 0.45f * churn);
            }
        }
        // Swash: a thin sheet runs up the sand, stalls, and mostly sinks into it.
        // It parts first where the wave landed: that end drains back toward the
        // sea, the film left up the beach soaks in, and its edge creeps back only
        // a little. It starts while the bore is still landing (the
        // crest 1.5 m from the waterline) and ramps in, so the hand-over has no seam.
        const float z0 = SHORE + 1.5f;
        const float tau = age - ageAt(z0 - bend);
        const float ts = 8.0f;
        if (tau < 0.0f || tau > ts) continue;
        const float p = tau / ts;
        const float ramp = smoothstep(0.0f, 0.08f, p);
        const float run = 2.4f + 1.6f * amp; // from z0 up the sand
        const float up = saturate(p / 0.3f);
        // Its own momentum carries it up the slope, slowing like a thrown ball,
        // until it stops; then the edge slips back a little as it drains.
        const float zs = z0 - run * (1.0f - (1.0f - up) * (1.0f - up)) + 0.08f * run * smoothstep(0.3f, 1.0f, p);
        const float cover = smoothstep(zs - 0.15f, zs + 0.6f, z) * (1.0f - smoothstep(z0, z0 + 2.0f, z));
        // Draining: the seaward end (where it landed) clears first, then the
        // stranded film up the beach soaks away.
        const float toward_front = saturate((z0 - z) / max(z0 - zs, 0.1f));
        const float soak = smoothstep(0.30f + 0.25f * toward_front, 0.62f + 0.33f * toward_front, p);
        s.sheet = max(s.sheet, 0.06f * ramp * (1.0f - soak) * cover);
        const float edge = exp(-((z - zs) * (z - zs)) / 0.15f);
        s.stir += ramp * (amp * (p < 0.3f ? 1.8f : 0.12f) * edge + 0.45f * amp * (1.0f - up * 0.6f) * (1.0f - soak) * cover);
        s.foam += ramp * (1.0f - soak) * 0.5f * cover;
    }
    // Small wind ripples everywhere.
    s.h += 0.025f * argus_noise(float2(x * 0.9f + t * 0.3f, z * 1.4f - t * 0.6f));
    s.foam = saturate(s.foam);
    return s;
}

// The beach: a 1:14 slope with beach cusps (the scalloped ridges a few metres
// apart that swash carves on real beaches) and a gently wandering waterline.
static float sandY(float x, float z) {
    const float near = smoothstep(SHORE + 4.0f, SHORE - 3.0f, z);
    const float cusps = 0.07f * sin(x * 0.75f) * near;
    const float wander = 0.10f * argus_noise(float2(x * 0.06f, 1.7f));
    // Landward the slope rolls over into a flat berm about 0.8 m up.
    const float rise = BEACH_SLOPE * (SHORE - z);
    const float berm = 0.8f - 0.8f * exp(-max(rise, 0.0f) / 0.8f);
    return (rise > 0.0f ? berm : rise) + cusps + wander;
}

// ------------------------------------------------------------ the glow map --

static float2 mapUV(float x, float z) { return float2((x - MAP_X0) / MAP_W, z / MAP_Z); }
static bool inMap(float x, float z) { return x > MAP_X0 + 0.5f && x < MAP_X0 + MAP_W - 0.5f && z > 0.1f && z < MAP_Z - 1.0f; }

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    // x: light now; y: charge (ability to flash); z: soft halo; w: unused.
    state.write(float4(0.0f, 1.0f, 0.0f, 0.0f), gid); // w (height) is filled by the first step
}

kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    const uint w = f.state_width, h = f.state_height;
    if (gid.x >= w || gid.y >= h) return;
    const float dt = clamp(f.dt, 0.0f, 0.1f);
    const float2 uv = argus_uv01(gid, w, h);
    const float x = MAP_X0 + uv.x * MAP_W;
    const float z = uv.y * MAP_Z;

    float4 c = prev.read(gid);
    float light = c.x, charge = c.y;

    const Sea s = sea(x, z, f.time);
    // Each map cell stands for a patch of water holding many cells. The share of
    // them pushed past their flash threshold grows with how hard the water is
    // torn; cells that flash spend their charge and recover over tens of seconds.
    // (The draw adds the grain: individual flashes are finer than this map.)
    const float share = smoothstep(0.2f, 1.6f, s.stir);
    const float flash = share * charge;
    light = max(light * exp(-dt / 0.2f), 0.95f * flash); // flashes last a fraction of a second
    charge = saturate(charge - flash * dt * 1.6f + dt / 25.0f);

    // The halo: light scattered in the water spreads a little and fades.
    auto at = [&](int dx, int dy) {
        return prev.read(uint2(clamp(int(gid.x) + dx, 0, int(w) - 1), clamp(int(gid.y) + dy, 0, int(h) - 1))).z;
    };
    const float spread = 0.25f * (at(2, 0) + at(-2, 0) + at(0, 2) + at(0, -2));
    const float halo = (0.55f * c.z + 0.45f * spread) * exp(-dt / 0.35f) + 0.06f * light;

    // w: the height of whatever is there (water, or sand when it's dry), for the draw.
    const float sand = sandY(x, z);
    const float surf = max(sand, z >= SHORE ? s.h : sand + s.sheet);
    next.write(float4(light, charge, min(halo, 2.0f), surf), gid);
}

// ------------------------------------------------------------------- the sky --

static float3 skyColour(float3 dir, float t, uint seed, bool with_stars) {
    const float elev = max(dir.y, 0.0f);
    // No moon, no towns: the sky is all but black, a touch lighter low down.
    float3 col = mix(float3(0.0030f, 0.0038f, 0.0060f), float3(0.0004f, 0.0006f, 0.0012f), saturate(elev * 3.0f));
    // Spherical-ish coordinates for stars and the galaxy.
    const float az = atan2(dir.x, dir.z);
    const float2 sp = float2(az * 2.0f, elev * 3.2f);
    // The Milky Way: a soft tilted band with dark dust lanes.
    const float band = sp.y - 0.55f - 0.35f * sp.x;
    const float mw = exp(-band * band * 6.0f);
    const float dust = smoothstep(-0.1f, 0.5f, argus_fbm(sp * 3.0f + float2(4.0f, 1.0f), 5));
    col += mw * (0.003f + 0.009f * max(argus_fbm(sp * 9.0f, 4), 0.0f)) * (1.0f - 0.85f * dust) * float3(0.85f, 0.88f, 1.0f);
    if (!with_stars) return col + float3(0.0018f, 0.0024f, 0.0020f) * exp(-elev * 25.0f);
    // Stars: denser in the band; each cell holds at most one.
    const float2 g = sp * 160.0f;
    const float2 cell = floor(g);
    const float r = argus_rand(uint2(int2(cell) + 50000), seed);
    const float dens = 0.978f - 0.02f * mw;
    if (r > dens) {
        const float2 off = float2(argus_rand(uint2(int2(cell) + 50000), seed + 9u), argus_rand(uint2(int2(cell) + 50000), seed + 13u)) - 0.5f;
        const float dd = length(fract(g) - 0.5f - off * 0.6f);
        const float mag = (r - dens) / (1.0f - dens);
        // Scintillation: fast, irregular, and strongest near the horizon, where
        // the light crosses the most air.
        const float depth_air = 0.25f + 0.6f * exp(-elev * 6.0f);
        const float flick = 0.5f + 0.5f * argus_noise(float2(t * 9.0f + r * 80.0f, r * 13.0f));
        const float tw = 1.0f - depth_air * flick;
        col += mag * mag * tw * smoothstep(0.18f, 0.0f, dd) * mix(float3(1.0f, 0.85f, 0.7f), float3(0.75f, 0.85f, 1.0f), fract(r * 97.0f)) * 2.2f;
    }
    // A sparse layer of bright stars, each with a soft halo.
    const float2 g2 = sp * 48.0f;
    const float2 cell2 = floor(g2);
    const float r2 = argus_rand(uint2(int2(cell2) + 90000), seed + 31u);
    if (r2 > 0.975f) {
        const float2 off = float2(argus_rand(uint2(int2(cell2) + 90000), seed + 37u), argus_rand(uint2(int2(cell2) + 90000), seed + 41u)) - 0.5f;
        const float dd = length(fract(g2) - 0.5f - off * 0.6f);
        const float mag = (r2 - 0.975f) / 0.025f;
        const float depth_air = 0.2f + 0.6f * exp(-elev * 6.0f);
        const float flick = 0.5f + 0.5f * argus_noise(float2(t * 8.0f + r2 * 90.0f, r2 * 17.0f));
        const float tw = 1.0f - depth_air * flick;
        const float3 tint = mix(float3(1.0f, 0.82f, 0.62f), float3(0.72f, 0.84f, 1.0f), fract(r2 * 71.0f));
        col += tw * (0.6f + 2.4f * mag * mag) * (smoothstep(0.06f, 0.0f, dd) + 0.06f * exp(-dd * dd * 60.0f)) * tint;
    }
    // A faint airglow just above the horizon.
    col += float3(0.0018f, 0.0024f, 0.0020f) * exp(-elev * 25.0f);
    return col;
}

// ------------------------------------------------------------------ drawing --

static float3 glowColour(float g) {
    // Blue at low levels, whiter in the brightest foam (as the eye sees it).
    return g * float3(0.10f, 0.50f, 1.00f) * 1.4f + g * g * float3(0.35f, 0.45f, 0.45f);
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> state [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    const float t = f.time;
    const float2 uv = argus_uv(gid, f);
    // The camera stands on the beach and looks along it: rotate the view ray.
    const float3 v = normalize(float3(uv.x, uv.y - HORIZON_UV, FOCAL));
    const float cy = cos(YAW), sy = sin(YAW);
    const float3 dir = float3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy);
    const float3 eye = float3(0.0f, EYE_Y, CAM_Z);

    // The surface height: from the map over the surf zone; dry sand landward of
    // it; a calm far sea beyond it.
    auto height = [&](float x, float z) {
        if (inMap(x, z)) return state.sample(smp, mapUV(x, z)).w;
        if (z < SHORE) return sandY(x, z);
        return 0.02f * argus_noise(float2(x * 0.5f + t * 0.2f, z * 0.6f - t * 0.4f));
    };

    float3 col;
    if (dir.y >= -0.0005f) {
        col = skyColour(dir, t, f.seed, true);
    } else {
        // March along the ray from where it is 2.4 m above still water (the biggest
        // waves' crests) to where it meets still water, then refine.
        const float s_top = max(0.3f, (EYE_Y - 2.4f) / -dir.y);
        const float s_flat = (EYE_Y + 0.05f) / -dir.y;
        const float s_end = min(s_flat + 1.0f, 3000.0f);
        const float s_last = min(s_end, 160.0f);
        float sa = s_top, sb = s_end;
        bool hit = false;
        if (s_top < s_last) {
            const int steps = 48;
            float prev_s = s_top;
            for (int i = 1; i <= steps; i++) {
                const float ss = mix(s_top, s_last, float(i) / float(steps));
                const float3 p = eye + dir * ss;
                if (p.y <= height(p.x, p.z)) {
                    sa = prev_s;
                    sb = ss;
                    hit = true;
                    break;
                }
                prev_s = ss;
            }
        }
        float dist = s_flat;
        if (hit) {
            for (int i = 0; i < 6; i++) {
                const float sm = 0.5f * (sa + sb);
                const float3 p = eye + dir * sm;
                if (p.y <= height(p.x, p.z)) sb = sm; else sa = sm;
            }
            dist = sb;
        }
        const float3 hp = eye + dir * dist;
        const float x = hp.x;
        const float z = hp.z;
        const float hgt = height(x, z);
        const float sand = sandY(x, z);
        // Three materials: the sea (over sand that's always under water), the
        // swash (a thin sheet running over the beach), and the sand itself.
        const float depth = hgt - sand;
        const bool sea = sand < -0.04f && depth > 0.004f;
        const bool swash = !sea && depth > 0.003f;
        const float film = saturate(depth / 0.03f);

        // Surface normal from the height field.
        const float e = 0.08f + 0.006f * dist;
        const float hx = height(x + e, z) - height(x - e, z);
        const float hz = height(x, z + e) - height(x, z - e);
        const float3 nrm = normalize(float3(-hx, 2.0f * e, -hz));

        // Close to the eye a map texel covers many pixels: average a few taps so
        // the glow doesn't show the map's grid.
        float4 g = float4(0.0f);
        if (inMap(x, z)) {
            const float r = clamp(0.9f - dist * 0.08f, 0.0f, 0.8f) * 0.12f; // metres
            g = state.sample(smp, mapUV(x, z));
            if (r > 0.0f) {
                g = 0.4f * g + 0.15f * (state.sample(smp, mapUV(x + r, z)) + state.sample(smp, mapUV(x - r, z)) +
                                        state.sample(smp, mapUV(x, z + 1.5f * r)) + state.sample(smp, mapUV(x, z - 1.5f * r)));
            }
        }
        // Fine sparkle: the glow is millions of tiny flashes, finer than the map.
        // Flashes last a fraction of a second, so the grain needn't stay put in the
        // world: it is drawn in 2x2-pixel cells on screen, renewed every 2 frames.
        const uint2 grain_cell = gid / 2u;
        // Most flashes are faint and a few are bright.
        const float rr = argus_rand(grain_cell, f.seed + f.frame / 2u);
        const float sparkle = 0.3f + 2.8f * rr * rr * rr;
        // Whitewater lights in streaks and patches that ride shoreward with it.
        const float2 fp = float2(x * 0.55f, (z + 2.2f * t) * 0.9f);
        const float streaks = argus_fbm(fp + 0.6f * float2(argus_noise(fp * 0.5f + 7.0f), 0.0f), 4);
        const float foam_tex = 0.25f + 0.95f * smoothstep(-0.35f, 0.45f, streaks);
        // The map ends ~100 m down the beach: let the light fade out before it does.
        const float far_fade = smoothstep(MAP_X0 + MAP_W - 2.0f, MAP_X0 + MAP_W - 40.0f, x) * smoothstep(MAP_X0 + 1.0f, MAP_X0 + 10.0f, x);
        const float glow = (g.x * sparkle + 0.2f * g.z) * foam_tex * far_fade;

        if (sea) {
            // A turbulent sea: the chop scatters the reflection into a dim, broken
            // sheen (no mirrored stars), and the water itself is dark and opaque.
            const float2 cp = float2(x * 2.6f + t * 0.7f, z * 3.4f - t * 1.1f);
            const float3 chop = 0.35f * float3(argus_noise(cp), 0.0f, argus_noise(cp + 17.3f));
            const float3 rn = normalize(nrm + chop);
            const float3 rr = reflect(dir, rn);
            const float fres = 0.02f + 0.98f * pow(1.0f - saturate(-dot(dir, rn)), 5.0f);
            col = skyColour(float3(rr.x, abs(rr.y), rr.z), t, f.seed, false) * fres * 0.45f;
            col += float3(0.0010f, 0.0018f, 0.0030f);
            // Shimmer: tiny wave facets tilted just right flash the faint light of the
            // sky low over the horizon back at the eye, and move with the chop.
            const float2 gp = float2(x * 9.0f + t * 1.3f, z * 11.0f - t * 1.9f);
            const float facet = argus_noise(gp) * argus_noise(gp * 1.7f + 23.0f);
            const float glint = smoothstep(0.30f, 0.60f, facet) * (0.4f + 0.6f * fres);
            col += glint * float3(0.020f, 0.028f, 0.040f) * exp(-dist * 0.02f);
            col += glowColour(glow);
        } else if (swash) {
            // The swash is a glassy sheet: smooth enough to mirror the sky and the
            // glowing surf beyond it, brightest at grazing angles - a sheen quite
            // unlike the dark chop of the sea. Thin at its edges, it lets the wet
            // sand show through.
            const float2 cp = float2(x * 4.0f + t * 0.5f, z * 4.0f - t * 0.8f);
            const float3 rn = normalize(nrm + 0.05f * float3(argus_noise(cp), 0.0f, argus_noise(cp + 9.1f)));
            const float3 rr = reflect(dir, rn);
            const float fres = (0.02f + 0.98f * pow(1.0f - saturate(-dot(dir, rn)), 5.0f)) * smoothstep(0.0f, 0.6f, film);
            const float3 mirror = skyColour(float3(rr.x, abs(rr.y), rr.z), t, f.seed, true) * 5.0f;
            // The surf's light, seen in the sheet: look a few metres along the reflection.
            const float2 rxz = rr.xz / max(length(rr.xz), 1e-3f);
            const float4 seen = state.sample(smp, mapUV(x + rxz.x * 3.0f, z + rxz.y * 3.0f));
            const float3 wet_sand = float3(0.0026f, 0.0026f, 0.0028f) * (0.85f + 0.15f * argus_noise(float2(x * 40.0f, z * 40.0f)));
            col = mix(wet_sand, mirror + glowColour(seen.x * 0.6f + 0.4f * seen.z), fres);
            col += glowColour(glow) * 0.9f;
        } else {
            // Sand: matte and very dark, a little darker still where it's wet; it
            // reflects nothing, so the water and its glow carry the picture.
            const float wet = smoothstep(SHORE - 4.5f, SHORE - 1.0f, z);
            const float grain = 0.80f + 0.20f * argus_noise(float2(x * 40.0f, z * 40.0f))
                                      + 0.08f * argus_noise(float2(x * 7.0f, z * 7.0f));
            const float lambert = 0.6f + 0.4f * saturate(nrm.y);
            // At night the sand is the darkest thing in view.
            col = mix(float3(0.0042f, 0.0040f, 0.0036f), float3(0.0026f, 0.0026f, 0.0028f), wet) * grain * lambert;
            col += glowColour(glow) * 0.8f; // stranded water still glows as it soaks in
        }
        // Distance haze toward the horizon.
        const float haze = 1.0f - exp(-dist * 0.015f);
        col = mix(col, float3(0.0022f, 0.0030f, 0.0048f), haze * 0.85f);
    }
    col = argus_aces(col * 2.2f);
    out.write(float4(argus_srgb(col), 1.0f), gid);
}

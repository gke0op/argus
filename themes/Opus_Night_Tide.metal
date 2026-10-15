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
// How it works: a 1024x512 state texture is a top-down map of the surf zone
// (80 m across, 64 m out to sea). Every frame, argus_step evaluates how hard
// the water is being stirred at each cell (from an analytic model of shoaling
// swells, breakers, bores and swash) and updates that cell's light, its charge
// (ability to flash) and a softly spreading halo. argus_draw raymarches the
// sea and the beach from eye height and lights them with that map.
//
// @argus state 1024x512
// @argus steps 1
// ============================================================================

constant float EYE_Y = 1.5f;        // eye height above still water, metres
constant float SHORE = 5.0f;        // still-water line, metres in front of the eye
constant float BEACH_SLOPE = 0.07f; // about 1:14
constant float T_WAVE = 8.0f;       // seconds between waves
constant float MAP_X = 32.0f;       // the map spans x in [-32, 32] m ...
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
        // Sets: every few waves come bigger.
        const float amp = 0.55f + 0.35f * sin(n * 0.9f) * sin(n * 0.37f + 1.0f) + 0.25f * r;
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
        // Swash: a thin sheet runs up the sand fast and slides back slowly. It
        // starts while the bore is still landing (the crest 1.5 m from the
        // waterline) and ramps in, so the hand-over has no seam either.
        const float z0 = SHORE + 1.5f;
        const float tau = age - ageAt(z0 - bend);
        const float ts = 7.5f;
        if (tau < 0.0f || tau > ts) continue;
        const float p = tau / ts;
        const float ramp = smoothstep(0.0f, 0.1f, p);
        const float run = 3.5f + 2.5f * amp; // from z0 up the sand
        const float zs = p < 0.35f ? z0 - run * sin(p / 0.35f * 1.5708f)
                                   : z0 - run * cos((p - 0.35f) / 0.65f * 1.5708f);
        const float cover = smoothstep(zs - 0.15f, zs + 0.6f, z) * (1.0f - smoothstep(z0, z0 + 2.0f, z));
        s.sheet = max(s.sheet, 0.06f * (1.0f - 0.7f * p) * ramp * cover);
        const float edge = exp(-((z - zs) * (z - zs)) / 0.15f);
        s.stir += ramp * (amp * (p < 0.35f ? 1.8f : 0.35f) * edge + 0.45f * amp * (1.0f - p) * cover);
        s.foam += ramp * (1.0f - p) * 0.5f * cover;
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
    return BEACH_SLOPE * (SHORE - z) + cusps + wander;
}

// ------------------------------------------------------------ the glow map --

static float2 mapUV(float x, float z) { return float2((x + MAP_X) / (2.0f * MAP_X), z / MAP_Z); }

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
    const float x = uv.x * 2.0f * MAP_X - MAP_X;
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

static float3 skyColour(float3 dir, float t, uint seed) {
    const float elev = max(dir.y, 0.0f);
    float3 col = mix(float3(0.016f, 0.022f, 0.034f), float3(0.002f, 0.004f, 0.010f), saturate(elev * 3.0f));
    // Spherical-ish coordinates for stars and the galaxy.
    const float az = atan2(dir.x, dir.z);
    const float2 sp = float2(az * 2.0f, elev * 3.2f);
    // The Milky Way: a soft tilted band with dark dust lanes.
    const float band = sp.y - 0.55f - 0.35f * sp.x;
    const float mw = exp(-band * band * 6.0f);
    const float dust = smoothstep(-0.1f, 0.5f, argus_fbm(sp * 3.0f + float2(4.0f, 1.0f), 5));
    col += mw * (0.004f + 0.010f * max(argus_fbm(sp * 9.0f, 4), 0.0f)) * (1.0f - 0.85f * dust) * float3(0.85f, 0.88f, 1.0f);
    // Stars: denser in the band; each cell holds at most one.
    const float2 g = sp * 160.0f;
    const float2 cell = floor(g);
    const float r = argus_rand(uint2(int2(cell) + 50000), seed);
    const float dens = 0.985f - 0.02f * mw;
    if (r > dens) {
        const float2 off = float2(argus_rand(uint2(int2(cell) + 50000), seed + 9u), argus_rand(uint2(int2(cell) + 50000), seed + 13u)) - 0.5f;
        const float dd = length(fract(g) - 0.5f - off * 0.6f);
        const float mag = (r - dens) / (1.0f - dens);
        const float tw = 0.75f + 0.25f * sin(t * (1.5f + 3.0f * mag) + r * 50.0f);
        col += mag * mag * tw * smoothstep(0.22f, 0.0f, dd) * mix(float3(1.0f, 0.85f, 0.7f), float3(0.75f, 0.85f, 1.0f), fract(r * 97.0f)) * 0.9f;
    }
    // A faint airglow just above the horizon.
    col += float3(0.010f, 0.014f, 0.012f) * exp(-elev * 25.0f);
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
    const float3 dir = normalize(float3(uv.x, uv.y - HORIZON_UV, FOCAL));

    // The surface height: from the map near the beach, a calm far sea beyond it.
    auto height = [&](float x, float z) {
        if (z < MAP_Z - 1.0f) return state.sample(smp, mapUV(x, z)).w;
        return 0.02f * argus_noise(float2(x * 0.5f + t * 0.2f, z * 0.6f - t * 0.4f));
    };

    float3 col;
    if (dir.y >= -0.0005f) {
        col = skyColour(dir, t, f.seed);
    } else {
        // March the ray from where it is 1.2 m above still water to where it meets
        // still water, then refine: nothing on the beach is taller than that.
        const float slope = dir.y / dir.z; // < 0
        const float z_top = max(0.3f, (EYE_Y - 1.2f) / -slope);
        const float z_flat = (EYE_Y + 0.05f) / -slope;
        const float z_end = min(z_flat + 1.0f, 2000.0f);
        const float kx = dir.x / dir.z;
        float za = z_top, zb = z_end;
        bool hit = false;
        if (z_top < MAP_Z) {
            const float z_last = min(z_end, MAP_Z);
            const int steps = 40;
            float prev_z = z_top;
            for (int i = 1; i <= steps; i++) {
                const float zz = mix(z_top, z_last, float(i) / float(steps));
                if (EYE_Y + slope * zz <= height(kx * zz, zz)) {
                    za = prev_z;
                    zb = zz;
                    hit = true;
                    break;
                }
                prev_z = zz;
            }
        }
        float z = z_flat;
        if (hit) {
            for (int i = 0; i < 6; i++) {
                const float zm = 0.5f * (za + zb);
                if (EYE_Y + slope * zm <= height(kx * zm, zm)) zb = zm; else za = zm;
            }
            z = zb;
        }
        const float x = kx * z;
        const float hgt = height(x, z);
        const float sand = sandY(x, z);
        const bool water = z >= MAP_Z - 1.0f || hgt > sand + 0.004f;

        // Surface normal from the height field.
        const float e = 0.08f + 0.006f * z;
        const float hx = height(x + e, z) - height(x - e, z);
        const float hz = height(x, z + e) - height(x, z - e);
        const float3 nrm = normalize(float3(-hx, 2.0f * e, -hz));
        const float3 refl = reflect(dir, nrm);
        const float cosv = saturate(-dot(dir, nrm));

        // Close to the eye a map texel covers many pixels: average a few taps so
        // the glow doesn't show the map's grid.
        float4 g = float4(0.0f);
        if (z < MAP_Z) {
            const float r = clamp(0.9f - z * 0.08f, 0.0f, 0.8f) * 0.12f; // metres
            g = state.sample(smp, mapUV(x, z));
            if (r > 0.0f) {
                g = 0.4f * g + 0.15f * (state.sample(smp, mapUV(x + r, z)) + state.sample(smp, mapUV(x - r, z)) +
                                        state.sample(smp, mapUV(x, z + 1.5f * r)) + state.sample(smp, mapUV(x, z - 1.5f * r)));
            }
        }
        // Fine sparkle: the glow is millions of tiny flashes, finer than the map.
        // Each sparkle cell is about 3 pixels on screen at any distance: a pixel
        // covers z/F metres across and z^2/(eye*F) metres along the ground.
        const float fpx = 0.5f * float(min(f.width, f.height)) * FOCAL;
        const float2 cell = float2(3.0f * z / fpx, 3.0f * z * z / (max(EYE_Y - hgt, 0.3f) * fpx));
        const uint2 grain_cell = uint2(int2(floor(float2(x, z) / max(cell, float2(1e-3f)))) + 4000000);
        // Most flashes are faint and a few are bright.
        const float rr = argus_rand(grain_cell, f.seed + f.frame / 2u);
        const float sparkle = 0.3f + 2.8f * rr * rr * rr;
        // Whitewater lights in streaks and patches that ride shoreward with it.
        const float2 fp = float2(x * 0.55f, (z + 2.2f * t) * 0.9f);
        const float streaks = argus_fbm(fp + 0.6f * float2(argus_noise(fp * 0.5f + 7.0f), 0.0f), 4);
        const float foam_tex = 0.25f + 0.95f * smoothstep(-0.35f, 0.45f, streaks);
        const float glow = (g.x * sparkle + 0.2f * g.z) * foam_tex;

        if (water) {
            // Dark water mirroring the sky, and the light in it.
            const float fres = 0.02f + 0.98f * pow(1.0f - cosv, 5.0f);
            col = skyColour(float3(refl.x, abs(refl.y), refl.z), t, f.seed) * fres * 1.3f;
            col += float3(0.002f, 0.004f, 0.007f);
            col += glowColour(glow);
        } else {
            // Sand: dry and starlit near the eye, darker and glossy where it's wet.
            const float wet = smoothstep(SHORE - 6.5f, SHORE - 2.5f, z);
            const float grain = 0.85f + 0.15f * argus_noise(float2(x * 40.0f, z * 40.0f));
            col = mix(float3(0.026f, 0.023f, 0.019f), float3(0.008f, 0.008f, 0.009f), wet) * grain;
            // Wet sand mirrors the sky and the glow in the water beyond it.
            const float fres = 0.04f + 0.6f * pow(1.0f - cosv, 4.0f);
            col += wet * fres * skyColour(float3(refl.x, abs(refl.y), refl.z), t, f.seed);
            const float4 seaward = state.sample(smp, mapUV(x, z + 0.8f + 0.25f * (SHORE - z)));
            // Only the glossy patches (thin films of water) mirror it, and dimly.
            const float gloss = smoothstep(0.05f, 0.55f, argus_noise(float2(x * 0.9f, z * 1.8f)));
            col += wet * gloss * 0.06f * glowColour(seaward.x * 0.5f + 0.3f * seaward.z) + glowColour(glow) * 0.8f;
        }
        // Distance haze toward the horizon.
        const float haze = 1.0f - exp(-z * 0.015f);
        col = mix(col, float3(0.010f, 0.014f, 0.022f), haze * 0.85f);
    }
    col = argus_aces(col * 2.2f);
    out.write(float4(argus_srgb(col), 1.0f), gid);
}

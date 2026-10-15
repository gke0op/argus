// ============================================================================
// GEMINI WORMHOLE // themes/Gemini_Wormhole.metal
//
// A stylised traversable wormhole. Nobody knows what lies inside one, so this
// theme imagines it: the physics is a starting point, the look is artistic.
//
// Lineage: designed by Google Gemini (ARGUS-BENCH Track A, CPU Zig), tuned for
// Argus 135 by Claude Opus (rigid spiral pattern speed with bounded shear,
// wrapped time phases), then ported to a Metal-only GPU theme by Claude Opus.
// The Zig original (themes/Gemini_Wormhole.zig) stays the reference.
//
// Inspired by, not solved from, Ellis-Bronnikov / Morris-Thorne geometry,
//   ds^2 = -dt^2 + dl^2 + (b_0^2 + l^2)(d\theta^2 + \sin^2\theta d\phi^2).
// Rays through a centred 864x720 lensing box (reference pixels at 1920x1200,
// scaled with the screen height) are traced once, in argus_init: velocity-Verlet,
// 96 steps, the Ellis bending term plus hand-tuned attraction (MASS_PARAM).
// Rays that cross the throat end in Universe B, with its own sky and disk.
//
// How it's drawn:
//   - State (float32) = a per-pixel geodesic lookup table plus two small rows:
//       rows 0..719, x <  864 : (disk crossing 1 radius|side, phi, Doppler g, ring glow)
//       rows 0..719, x >= 864 : (crossing 2 radius|side, phi, Doppler g, lensed sky RGB8)
//       row 720               : 320 plasma knots (l, phi, temperature)
//       row 721               : per-frame knot deposits (radial rings A/B, m5 spokes)
//     argus_step only advances the knots and their deposits; the LUT rows are
//     copied for the first few frames (so both ping-pong textures hold it) and
//     then left alone, so a frame costs one LUT read per pixel.
//   - argus_draw: the Universe A deep field (3D value noise + point stars) is
//     computed per pixel; inside the box the lensed sky, both accretion disks
//     (false-colour amber/cyan in A, violet/turquoise in B, Doppler beaming,
//     spiral density waves, MHD ripples, knot rings) and the Einstein-ring
//     glow are composed exactly in the Zig order, in display space.
//   - Every time phase is fmod(t, period) * freq, so it stays exact for hours.
//
// @argus state 1728x722 float32
// ============================================================================

constant float PI2 = 6.2831853f;

// Geometry (units of throat radius b_0 = 1)
constant float MASS_PARAM = 0.42f;
constant float CAM_L      = 9.5f;
constant float DISK_MAX_L = 4.2f;

// Lensing box in reference pixels (1920x1200 frame); focal length 0.88 * height.
constant int   ACT_W   = 864;
constant int   ACT_H   = 720;
constant float REF_H   = 1200.0f;
constant float FOCAL   = 0.88f * 1200.0f;
constant int   KNOT_ROW  = 720;
constant int   TABLE_ROW = 721;
constant int   NUM_KNOTS = 320;
constant int   RAD_BINS  = 512;
constant int   ANG_BINS  = 1024;

// (t * freq) mod 2pi without losing precision as t grows: fmod is exact.
static inline float wp(float t, float freq) {
    return fmod(t, PI2 / freq) * freq;
}

// ---------------------------------------------------------------------------
// Camera basis (79 deg inclination, -14 deg roll) shared by init and draw.
struct Cam { float3 r, fwd, right, up; };
static inline Cam camera() {
    const float inc = 79.0f * (3.14159265f / 180.0f);
    const float tilt = -14.0f * (3.14159265f / 180.0f);
    Cam c;
    c.r = float3(sin(inc), 0.0f, cos(inc));
    c.fwd = -c.r;
    const float3 right0 = float3(0.0f, 1.0f, 0.0f);
    const float3 up0 = float3(-cos(inc), 0.0f, sin(inc));
    c.right = cos(tilt) * right0 + sin(tilt) * up0;
    c.up = -sin(tilt) * right0 + cos(tilt) * up0;
    return c;
}

// ---------------------------------------------------------------------------
// The Zig theme's hash-based 3D value noise, bit for bit (same sky pattern).
static inline float hash3(int ix, int iy, int iz) {
    uint n = uint(ix) * 1597334677u + uint(iy) * 3812015801u + uint(iz) * 2912667907u;
    n = (n ^ (n >> 13)) * 1274126177u;
    n = n ^ (n >> 16);
    return float(n & 0x00FFFFFFu) / 16777216.0f;
}

static float noise3D(float3 p) {
    const float3 fl = floor(p);
    const int ix = int(fl.x), iy = int(fl.y), iz = int(fl.z);
    const float3 f = p - fl;
    const float3 u = f * f * (3.0f - 2.0f * f);
    const float n000 = hash3(ix, iy, iz),         n100 = hash3(ix + 1, iy, iz);
    const float n010 = hash3(ix, iy + 1, iz),     n110 = hash3(ix + 1, iy + 1, iz);
    const float n001 = hash3(ix, iy, iz + 1),     n101 = hash3(ix + 1, iy, iz + 1);
    const float n011 = hash3(ix, iy + 1, iz + 1), n111 = hash3(ix + 1, iy + 1, iz + 1);
    const float nx00 = mix(n000, n100, u.x), nx10 = mix(n010, n110, u.x);
    const float nx01 = mix(n001, n101, u.x), nx11 = mix(n011, n111, u.x);
    return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

// Celestial sky for unit direction d: Universe A (sapphire galactic plane, fine stars)
// or Universe B (teal-magenta-gold starforming nebula, dense bright cluster).
static float3 celestialSky(float3 d, bool universe_b) {
    const float f1 = noise3D(d * 3.5f + float3(1.3f, -2.1f, 0.7f));
    const float f2 = noise3D(d * 7.2f + float3(-4.1f, 1.9f, -3.3f));
    const float f3 = noise3D(d * 15.0f + float3(2.7f, 5.1f, -1.4f));
    const float fbm = 0.55f * f1 + 0.30f * f2 + 0.15f * f3;
    const float star_cell = noise3D(d * 95.0f);
    const float star_tint = noise3D(d * 40.0f + float3(9.0f, 0.0f, 0.0f));
    if (!universe_b) {
        const float band = exp(-10.0f * (d.y + 0.25f * d.x) * (d.y + 0.25f * d.x));
        const float dust = smoothstep(0.35f, 0.70f, fbm);
        const float star = pow(max(0.0f, (star_cell - 0.76f) / 0.24f), 5.0f);
        return float3(0.015f + 0.045f * band * dust + 0.02f * f1,
                      0.024f + 0.075f * band * dust + 0.035f * f2,
                      0.052f + 0.145f * band * dust + 0.065f * f1)
             + star * float3(0.9f + 0.4f * star_tint, 0.92f + 0.1f * star_tint, 1.05f - 0.3f * star_tint);
    }
    const float core = smoothstep(0.28f, 0.82f, fbm);
    const float filament = pow(max(0.0f, 1.0f - abs(2.0f * f2 - 1.0f)), 3.0f);
    const float star = pow(max(0.0f, (star_cell - 0.70f) / 0.30f), 4.0f);
    return float3(0.06f + 0.42f * core * f1 + 0.35f * filament,
                  0.05f + 0.28f * core * f2 + 0.55f * filament * f3,
                  0.14f + 0.65f * core + 0.45f * filament)
         + star * float3(1.2f + 0.5f * star_tint, 1.1f + 0.2f * star_tint, 0.95f - 0.2f * star_tint);
}

// Elliptical fade of the lensing box toward its border (box-normalised coords).
static inline float edgeFade(float2 nbox) {
    return 1.0f - smoothstep(0.75f, 0.98f, length(nbox));
}

// ---------------------------------------------------------------------------
// The geodesic trace of one box pixel (bx, by) -> two LUT texels.
struct Trace { float4 a; float4 b; };

static Trace traceRay(int bx, int by) {
    Trace res;
    const float2 nbox = float2((float(bx) - 0.5f * ACT_W) / (0.5f * ACT_W),
                               (float(by) - 0.5f * ACT_H) / (0.5f * ACT_H));
    const float fade = edgeFade(nbox);
    if (fade <= 0.001f) {
        res.a = float4(-1.0f, 0.0f, 1.0f, 0.0f);
        res.b = float4(-1.0f, 0.0f, 1.0f, 0.0f);
        return res;
    }
    const Cam c = camera();
    const float sx = (float(bx) - 0.5f * ACT_W) / FOCAL;
    const float sy = (0.5f * ACT_H - float(by)) / FOCAL;
    const float3 dir = normalize(c.fwd + sx * c.right + sy * c.up);

    const float cos_a = clamp(-dot(dir, c.r), -1.0f, 1.0f);
    const float sin_a = sqrt(max(0.0f, 1.0f - cos_a * cos_a));
    const float3 epsi = sin_a > 1e-7f ? (dir + cos_a * c.r) / sin_a : float3(0.0f, 1.0f, 0.0f);

    const float r_obs = sqrt(1.0f + CAM_L * CAM_L);
    const float b = r_obs * sin_a, b2 = b * b;

    float l = CAM_L, vl = -cos_a, psi = 0.0f, z_prev = c.r.z;
    bool hit1 = false, hit2 = false;
    float4 h1 = float4(-1.0f, 0.0f, 1.0f, 0.0f);   // (radius code, phi, g, -)
    float4 h2 = float4(-1.0f, 0.0f, 1.0f, 0.0f);
    float min_abs_l = abs(l);

    for (int i = 0; i < 96; i++) {
        const float r2 = 1.0f + l * l;
        const float dlam = 0.11f * sqrt(r2);
        const float l_prev = l, psi_prev = psi;

        const float ir2 = 1.0f / r2, ir = sqrt(ir2);
        const float acc1 = l * ir2 * (b2 * ir2 * (1.0f - 1.65f * MASS_PARAM * ir) - 0.55f * MASS_PARAM * ir);
        const float vl_half = vl + 0.5f * dlam * acc1;
        l += dlam * vl_half;

        const float lm = 0.5f * (l_prev + l);
        const float ir2m = 1.0f / (1.0f + lm * lm);
        psi += dlam * b * ir2m * (1.0f + 0.65f * MASS_PARAM * sqrt(ir2m));

        const float ir2n = 1.0f / (1.0f + l * l), irn = sqrt(ir2n);
        const float acc2 = l * ir2n * (b2 * ir2n * (1.0f - 1.65f * MASS_PARAM * irn) - 0.55f * MASS_PARAM * irn);
        vl = vl_half + 0.5f * dlam * acc2;

        min_abs_l = min(min_abs_l, abs(l));
        const float z = cos(psi) * c.r.z + sin(psi) * epsi.z;

        // Equatorial-plane (disk) crossing
        if ((z_prev > 0.0f && z <= 0.0f) || (z_prev < 0.0f && z >= 0.0f)) {
            const float frac = clamp(abs(z_prev) / (abs(z_prev) + abs(z) + 1e-12f), 0.0f, 1.0f);
            const float l_cross = l_prev + frac * (l - l_prev);
            if (abs(l_cross) <= DISK_MAX_L && !(hit1 && hit2)) {
                const float psi_c = psi_prev + frac * (psi - psi_prev);
                const float3 u = cos(psi_c) * c.r + sin(psi_c) * epsi;
                float phi = atan2(u.y, u.x);
                if (phi < 0.0f) phi += PI2;
                const float norm_r = clamp(abs(l_cross) / DISK_MAX_L, 0.0f, 0.9999f);
                const float side = l_cross < 0.0f ? 1.0f : 0.0f;

                const float r_eff = sqrt(1.0f + l_cross * l_cross);
                const float v_orb = clamp(0.46f / sqrt(sqrt(r_eff)), 0.08f, 0.55f);
                const float gamma = 1.0f / sqrt(1.0f - v_orb * v_orb);
                const float lz_over_e = b * (c.r.x * epsi.y - c.r.y * epsi.x);
                const float sign_rot = l_cross >= 0.0f ? 1.0f : -0.85f;
                const float grav = sqrt(1.0f - 0.30f / r_eff);
                const float denom = gamma * (1.0f - sign_rot * v_orb * (lz_over_e / r_eff));
                const float g = clamp(grav / max(0.35f, denom), 0.45f, 1.95f);
                const float4 h = float4(norm_r + 2.0f * side, phi, g, 0.0f);
                if (!hit1) { hit1 = true; h1 = h; }
                else       { hit2 = true; h2 = h; }
            }
        }
        z_prev = z;
        if (abs(l) > 10.5f && l * vl > 0.0f) break;
    }

    // Asymptotic outgoing direction -> lensed sky of Universe A or B
    const bool in_b = l < 0.0f;
    const float cp = cos(psi), sp = sin(psi);
    const float3 u_out = cp * c.r + sp * epsi;
    const float3 du = -sp * c.r + cp * epsi;
    const float v_psi = b / sqrt(1.0f + l * l);
    const float out_norm = 1.0f / sqrt(max(1e-9f, vl * vl + v_psi * v_psi));
    const float sign_l = l >= 0.0f ? 1.0f : -1.0f;
    const float3 k_out = (vl * sign_l * u_out + v_psi * du) * out_norm;
    const float3 sky = celestialSky(k_out, in_b);

    // Einstein ring and throat photon-sphere glow
    const float grazing = exp(-14.0f * min_abs_l * min_abs_l) * exp(-4.5f * abs(b - 1.18f));
    const float rim = exp(-32.0f * (b - 1.15f) * (b - 1.15f));
    const float ring = clamp(0.85f * grazing + 0.65f * rim, 0.0f, 1.0f) * fade;

    // Universe B interior: the swirling vortex seen through the throat
    if (in_b && !hit2) {
        float phi_b = atan2(k_out.y, k_out.x);
        if (phi_b < 0.0f) phi_b += PI2;
        hit2 = true;
        h2 = float4(clamp(b / 1.18f, 0.0f, 0.999f) + 2.0f, phi_b, 1.15f + 0.35f * k_out.y, 0.0f);
    }

    const float3 s8 = clamp(round(sky * 255.0f), 0.0f, 255.0f);
    res.a = float4(h1.x, h1.y, h1.z, ring);
    res.b = float4(h2.x, h2.y, h2.z, s8.r + 256.0f * s8.g + 65536.0f * s8.b);
    return res;
}

// ---------------------------------------------------------------------------
// Plasma knots: fixed per theme (the Zig seeds them with a constant), so they are too.
static inline float krand(uint i, uint k) {
    return float(argus_hash(i * 7919u + k * 104729u + 0x9E3779B9u)) * (1.0f / 4294967295.0f);
}

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    const int x = int(gid.x), y = int(gid.y);
    float4 v = float4(0.0f);
    if (y < ACT_H) {
        const Trace t = traceRay(x % ACT_W, y);
        v = x < ACT_W ? t.a : t.b;
    } else if (y == KNOT_ROW && x < NUM_KNOTS) {
        const float side = (x & 1) == 0 ? 1.0f : -1.0f;
        const float u = krand(uint(x), 0u);
        v = float4(side * (0.25f + 4.2f * u * u), krand(uint(x), 1u) * PI2,
                   0.65f + 0.95f * krand(uint(x), 2u), 0.0f);
    }
    state.write(v, gid);
}

// Advances the knots (infall through the throat, Keplerian shear) and gathers their
// deposits into the table row. The LUT rows are static: copied only on the first frames.
kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    const int x = int(gid.x), y = int(gid.y);
    if (y < ACT_H) {
        if (f.frame < 4u) next.write(prev.read(gid), gid);
        return;
    }
    if (y == KNOT_ROW) {
        float4 k = prev.read(gid);
        if (x < NUM_KNOTS) {
            const float dt = clamp(f.dt, 0.0f, 0.1f);
            const float r_eff = sqrt(1.0f + k.x * k.x);
            const float sign_rot = k.x >= 0.0f ? 1.0f : -0.85f;
            const float omega = sign_rot * (1.85f / (r_eff * sqrt(r_eff)));
            k.y = fmod(k.y + omega * dt, PI2);
            if (k.y < 0.0f) k.y += PI2;
            k.x -= 0.18f * dt / r_eff;
            if (k.x < -4.6f) k.x += 9.2f;
        }
        next.write(k, gid);
        return;
    }
    // Table row: x < 512 radial ring deposits (A, B); 512..1535 m5 azimuthal spokes.
    float4 v = float4(0.0f);
    if (x < RAD_BINS + ANG_BINS) {
        for (int i = 0; i < NUM_KNOTS; i++) {
            const float4 k = prev.read(uint2(i, KNOT_ROW));
            const float norm_r = abs(k.x) / DISK_MAX_L;
            if (norm_r >= 0.92f) continue;
            if (x < RAD_BINS) {
                const int db = x - int(norm_r * RAD_BINS);
                if (abs(db) <= 4) {
                    const float w = 0.028f * k.z * exp(-0.25f * float(db * db));
                    if (k.x >= 0.0f) v.x += w; else v.y += w;
                }
            } else {
                const int pb = int(k.y / PI2 * ANG_BINS) & (ANG_BINS - 1);
                if (pb == x - RAD_BINS) v.z += 0.12f * k.z;
            }
        }
    }
    next.write(v, gid);
}

// ---------------------------------------------------------------------------
// Disk palettes (the Zig colour LUTs, evaluated directly): display-space colour.
static inline float3 diskColor(float g, float I, bool univ_b) {
    const float e = I * (0.85f + 1.35f * I);
    float3 lin;
    if (!univ_b) {
        lin = e * float3(pow(max(0.05f, g * 1.20f), 0.65f),
                         pow(max(0.02f, g * 0.95f - 0.05f), 1.05f),
                         pow(max(0.01f, g * 0.85f - 0.15f), 1.45f));
    } else {
        lin = e * float3(pow(max(0.04f, g * 0.98f), 0.90f),
                         pow(max(0.04f, g * 1.08f), 0.85f),
                         pow(max(0.08f, g * 1.30f + 0.10f), 0.65f));
    }
    lin = lin / (1.0f + 0.55f * lin);
    return saturate(pow(lin, float3(0.78f)));
}

struct DiskSample { float3 color; float opacity; };

// One disk crossing: radius code (norm_r + 2*side), azimuth, Doppler factor (palette units).
static DiskSample diskSample(float code, float phi, float g_val, float t,
                             texture2d<float> state) {
    const bool side_b = code >= 2.0f;
    const float norm_r = code - (side_b ? 2.0f : 0.0f);
    const int r_bin = clamp(int(norm_r * RAD_BINS), 0, RAD_BINS - 1);
    const int p_bin = int(phi / PI2 * ANG_BINS) & (ANG_BINS - 1);
    const float4 knot_rad = state.read(uint2(r_bin, TABLE_ROW));
    const float spoke = state.read(uint2(RAD_BINS + p_bin, TABLE_ROW)).z;

    const float l_abs = norm_r * DISK_MAX_L;
    const float r_eff = sqrt(1.0f + l_abs * l_abs);
    const float om_r = 1.0f - norm_r;
    const float outer_taper = exp(-2.60f * norm_r * norm_r) * om_r * om_r;
    const float shear = 9.0f * sin(wp(t, 0.105f));
    const float omega_loc = 2.65f / (r_eff * sqrt(r_eff));

    const float m5 = sin(5.0f * phi - wp(t, 6.80f)) * cos(2.0f * phi + wp(t, 2.4f)) + spoke;
    const float doppler = clamp(0.30f + g_val * g_val * 0.58f, 0.35f, 1.95f);

    DiskSample s;
    if (!side_b) {
        const float inner_boost = 1.0f - 0.35f / sqrt(r_eff);
        const float rings = 0.80f + 0.25f * sin(24.0f * norm_r - wp(t, 4.2f)) * cos(39.0f * norm_r + wp(t, 2.9f));
        const float base = outer_taper * inner_boost * rings + knot_rad.x;
        const float sp = 10.5f * log(r_eff) - wp(t, 2.1f) + shear * omega_loc;
        const float m3 = cos(3.0f * phi - wp(t, 4.60f) + 0.65f * sin(phi + wp(t, 1.8f)));
        const float turb = 0.56f + 0.36f * cos(sp + 2.0f * phi) + 0.22f * m3 + 0.16f * m5 * sin(sp);
        const float flux = base * max(0.08f, turb) * doppler;
        s.color = diskColor(g_val, min(flux * 215.0f, 255.0f) / 255.0f, false);
        s.opacity = clamp(base * 1.45f, 0.0f, 0.92f);
    } else {
        const float base = (0.28f + 0.62f * outer_taper) * (0.82f + 0.32f * cos(18.0f * norm_r - wp(t, 4.8f))) + knot_rad.y;
        const float sp = -8.5f * log(r_eff) + wp(t, 1.8f) - 0.9f * shear * omega_loc;
        const float m2 = sin(2.0f * phi - wp(t, 3.20f));
        const float turb = 0.52f + 0.38f * cos(sp - phi) + 0.22f * m2 + 0.18f * m5;
        const float flux = base * max(0.08f, turb) * doppler * 0.68f;
        s.color = diskColor(g_val, min(flux * 185.0f, 255.0f) / 255.0f, true);
        s.opacity = clamp(base * 1.25f, 0.0f, 0.85f);
    }
    return s;
}

// Universe A deep field behind everything: galactic dust band, ambient glow, point stars.
static float3 deepField(uint2 gid, constant ArgusFrame& f, Cam c) {
    const float h = float(f.height);
    const float sx = (float(gid.x) - 0.5f * float(f.width)) / (0.88f * h);
    const float sy = (0.5f * h - float(gid.y)) / (0.88f * h);
    const float3 d = normalize(c.fwd + sx * c.right + sy * c.up);
    const float f1 = noise3D(d * 3.5f + float3(1.3f, -2.1f, 0.7f));
    const float f2 = noise3D(d * 7.2f + float3(-4.1f, 1.9f, -3.3f));
    const float band = exp(-10.0f * (d.y + 0.25f * d.x) * (d.y + 0.25f * d.x));
    const float dust = smoothstep(0.35f, 0.70f, 0.65f * f1 + 0.35f * f2);
    const float cf = dot(d, c.fwd);
    const float impact = sqrt(1.0f + CAM_L * CAM_L) * sqrt(max(0.0f, 1.0f - cf * cf));
    const float glow = 0.035f / (1.0f + 0.12f * impact * impact);
    float3 col = float3(0.012f + 0.040f * band * dust + 0.018f * f1 + glow * 0.55f,
                        0.018f + 0.068f * band * dust + 0.030f * f2 + glow * 0.65f,
                        0.042f + 0.135f * band * dust + 0.058f * f1 + glow * 1.10f);
    col = saturate(round(col * 255.0f) / 255.0f);

    // ~3800 crisp 3x3 Gaussian stars at 1920x1200: at most one per 24-pixel cell.
    const uint2 cell = gid / 24u;
    const uint ch = argus_hash(cell.x * 73856093u ^ cell.y * 19349663u ^ 0x51ED27u);
    if ((ch & 0xFFFFu) < 62259u) {                              // 95% of cells hold a star
        const uint h2 = argus_hash(ch);
        const int2 sp = int2(cell * 24u) + 1 + int2(int(h2 % 22u), int((h2 >> 8) % 22u));
        const int2 o = int2(gid) - sp;
        if (abs(o.x) <= 1 && abs(o.y) <= 1) {
            const float ub = float((h2 >> 16) & 0xFFu) / 255.0f;
            const float tint = float(argus_hash(h2) & 0xFFFFu) / 65535.0f;
            const float lum = 0.18f + 0.82f * ub * ub;
            const float k = exp(-1.15f * float(o.x * o.x + o.y * o.y)) * (230.0f / 255.0f);
            col += lum * k * float3(0.82f + 0.35f * tint, 0.88f + 0.12f * tint, 1.12f - 0.28f * tint);
        }
    }
    return saturate(col);
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> state [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    const Cam c = camera();
    float3 col = deepField(gid, f, c);

    // Position in the lensing box (reference pixels, scaled with the screen height)
    const float s = REF_H / float(f.height);
    const float2 bp = (float2(gid) - 0.5f * float2(f.width, f.height)) * s + 0.5f * float2(ACT_W, ACT_H);
    if (bp.x >= 0.0f && bp.y >= 0.0f && bp.x < float(ACT_W) && bp.y < float(ACT_H)) {
        const int2 bi = int2(bp);
        const float fade_raw = edgeFade(float2((float(bi.x) - 0.5f * ACT_W) / (0.5f * ACT_W),
                                               (float(bi.y) - 0.5f * ACT_H) / (0.5f * ACT_H)));
        if (fade_raw > 0.001f) {
            const float4 A = state.read(uint2(bi));
            const float4 B = state.read(uint2(bi.x + ACT_W, bi.y));
            const float t = f.time;

            // Lensed sky (RGB8 packed in one float), faded into the deep field at the border
            const uint pk = uint(B.w);
            const float3 sky = float3(float(pk & 0xFFu), float((pk >> 8) & 0xFFu), float(pk >> 16)) / 255.0f;
            col = mix(col, sky, fade_raw);
            const float fade = (round(fade_raw * 63.0f) + 1.0f) / 64.0f;

            // Secondary caustic / Universe B interior crossing, behind the primary
            if (B.x >= 0.0f) {
                const float g2 = 0.45f + 0.1f * clamp((B.z - 0.35f) / 1.80f * 15.0f, 0.0f, 15.0f);
                const DiskSample s2 = diskSample(B.x, B.y, g2, t, state);
                col = saturate(col + s2.color * (0.75f * fade));
            }
            // Primary disk crossing: semi-transparent over what lies behind
            if (A.x >= 0.0f) {
                const float g1 = 0.45f + 0.1f * clamp((A.z - 0.35f) / 1.80f * 15.9375f - 0.5f, 0.0f, 15.0f);
                const DiskSample s1 = diskSample(A.x, A.y, g1, t, state);
                col = col * (1.0f - 0.65f * s1.opacity * fade);
                col = saturate(col + s1.color * fade);
            }
            // Einstein ring and exotic throat glow, pulsing
            if (A.w > 0.0f) {
                const float pulse = 9.0f + 4.0f * sin(wp(t, 3.4f));
                const float boost = A.w * 15.0f * pulse * fade / 255.0f;
                col = saturate(col + boost * float3(11.0f / 16.0f, 15.0f / 16.0f, 1.0f));
            }
        }
    }
    out.write(float4(col, 1.0f), gid);
}

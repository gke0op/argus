// ============================================================================
// OPUS EBRU STUDIO // themes/Opus_Ebru_Studio.metal
// Author: Claude Opus (Anthropic), 2026-10-16.
//
// A marbling bath in a daylight studio, seen from straight above in a frame of
// brushed aluminium. Liquid metal and indigo ink are worked by a quick, restless
// hand, and the glass ceiling, with its 3 x 7 grid of studio lights on slim
// beams, slides across every pool of metal.
//
// Ebru (Turkish paper marbling) floats colours on a thickened bath and draws
// them out with a stylus. Nothing here is scripted: the hand is a random number
// generator.
//
// THE HAND. One row of the state holds it: a stylus whose velocity is an
// Ornstein-Uhlenbeck process (a random walk with momentum: it darts, turns, and
// is pushed back from the frame) and whose depth is a second one, so it dips in
// and lifts out at random. Lifted, it hovers and flicks in drops, at random, of
// metal or of deep or bright ink. It watches the bath: the scarcer the metal,
// the likelier the next drop is metal.
//
// THE BATH. An Ebru bath is thickened (kitre, gum tragacanth) until a stylus
// moves it at a Reynolds number of about one or less. There inertia hardly
// matters and each bit of liquid simply drags its neighbours (viscosity). That is
// the flow modelled here, a Stokes flow in a shallow layer (Brinkman: viscosity
// plus drag from the floor):
//   * the stylus drags a no-slip core of liquid with it and the drag spreads
//     outward over a few stylus widths: a stream function psi = (V x r) Phi(r), so
//     the surface is never compressed;
//   * it leaves a wake, a stored psi that spreads by viscosity and dies away
//     against the floor, so lines keep moving after the hand has passed;
//   * a slow convection keeps the bath from ever being still;
//   * the liquid sticks to the frame (no slip) and climbs it in a meniscus.
// Each cell is traced back along the flow; near the stylus in three sub-steps that
// follow it as it moves, so fast strokes stay smooth. Velocities come from the
// stream function's analytic gradient. Drops spread as exact area-adding maps
// (Lu, Jaffer et al., "Mathematical Marbling", 2012): a drop growing by area
// pi*dA moves every point p to c + (p-c) sqrt(1 + dA/|p-c|^2).
//
// THE LIQUIDS. The metal holds itself together: an Allen-Cahn surface-tension
// term keeps its edges sharp, rounds them and pinches thin threads into beads.
// The ink mixes, from indigo to a bright cyan-blue. The metal is shaded as a
// mirror, the ink as a glossy dielectric (2% reflection at normal incidence,
// rising to grazing by Fresnel), and the aluminium with an anisotropic
// (Kajiya-Kay) highlight across its grain from the nearest lights.
//
// State (1600 x 980, half float): rows 0..978 are the bath: x = metal 0..1,
// y = ink tone, z = wake stream function. The last row holds the hand (its
// position split into a coarse and a fine half, so half floats keep it exact).
//
// COST. Half floats halve the memory traffic of both kernels. The convection is
// smooth, so it is evaluated once per cell; only cells near the dipped stylus trace
// it in sub-steps. Reflections are filtered by their footprint (the curvature of the
// surface and the grazing angle), so the lights never alias into grain at the
// edges, and each pixel evaluates the room once unless it is on a metal-ink edge.
//
// @argus state 1600x980
// @argus steps 1
// ============================================================================

constant float PI  = 3.14159265f;
constant float TAU = 6.2831853f;
constant int   STEPS = 1;

// ----------------------------------------------------------------- the frame --
// A camera straight above at height ZC (focal length FC) looks down on the bath at
// z = 0. The frame lies on it, RIM_H thick, with its inner edge BORDER (in screen
// units) in from each screen edge; it runs out past the screen on every side.
constant float ZC     = 3.0f;
constant float FC     = 2.22f;
constant float BORDER = 0.15f;
constant float RIM_H  = 0.075f;
constant float CHAMF  = 0.016f;   // the rounded inner edge

// ------------------------------------------------------------------ the hand --
constant float TAU_V  = 0.8f;    // s: how long the hand keeps a direction
constant float SIG_V  = 0.85f;   // rms stylus speed, in bath units per second
constant float TAU_Z  = 1.3f;    // s: how long it stays in or out of the bath
constant float Z_MEAN = 0.25f;
constant float Z_SIG  = 0.55f;
constant float STY_A  = 0.012f;  // the stylus's no-slip core (a fine awl)
constant float STY_L  = 0.035f;  // the distance over which its drag falls off
constant float DROP_DUR = 0.45f;  // s for a drop to spread
constant float DROP_GAP = 0.05f;
constant float RATE_LIFTED = 6.0f, RATE_DIPPED = 0.8f;   // drops per second

// ------------------------------------------------------------------ the bath --
constant float TAU_W  = 1.6f;    // s: the wake's lifetime (floor drag)
constant float KAPPA  = 6.0f;    // 1/s: how fast the stylus leaves motion in the liquid
constant float BETA   = 0.7f;
constant float D_WAKE = 0.24f;   // cells^2 per step: the wake's viscous spread (near the stability limit)
constant float AMB    = 0.009f;  // stream-function amplitude of the slow convection
constant float WALL_D = 0.035f;  // no-slip boundary layer at the frame
constant float M_DIFF = 0.07f;   // metal surface tension (Allen-Cahn): interface spread
constant float M_SHARP = 0.12f;  //   ... and the pull back to 0 or 1
constant float B_DIFF = 0.06f;   // ink tone mixing

static inline float rnd(uint s, uint k) {
    return float(argus_hash(s ^ argus_hash(k * 0x85EBCA6Bu + 0x632BE5ABu))) * (1.0f / 4294967296.0f);
}
static inline float gauss(uint s, uint k) {
    const float u1 = max(rnd(s, k), 1e-7f), u2 = rnd(s, k + 1u);
    return sqrt(-2.0f * log(u1)) * cos(TAU * u2);
}
static inline float2 half_extent(constant ArgusFrame& f) {
    return float2(f.width, f.height) / float(min(f.width, f.height));
}
// The bath's half-size in world units (z = 0 maps to the screen scaled by FC / ZC).
static inline float2 bath_extent(constant ArgusFrame& f) {
    return (half_extent(f) - BORDER) * (ZC / FC);
}
static inline float ease3(float x) { x = saturate(x); return 1.0f - (1.0f - x) * (1.0f - x) * (1.0f - x); }

// ---------------------------------------------------------- the hand's texels --
struct Hand {
    float2 X, V;            // stylus position and velocity
    float z, flick;         // depth process (dipped when > 0), a spare random process
    float2 dc;              // the current drop's centre
    float age, R2, kind, tone;  // its age (s), final r^2, 1 = metal, ink tone
    float mfrac;            // estimated metal fraction
};

template <typename Tex>
static Hand read_hand(Tex s, uint row) {
    const float4 a = s.read(uint2(0, row)), b = s.read(uint2(1, row));
    const float4 c = s.read(uint2(2, row)), d = s.read(uint2(3, row));
    Hand H;
    H.X = a.xy + d.zw; H.V = a.zw;          // coarse + fine
    H.z = b.x; H.flick = b.y; H.dc = b.zw;
    H.age = c.x; H.R2 = c.y; H.kind = c.z; H.tone = c.w;
    H.mfrac = d.y;
    return H;
}
static float4 hand_texel(Hand H, uint i) {
    const float2 Xc = float2(half2(H.X));
    switch (i) {
        case 0: return float4(Xc, H.V);
        case 1: return float4(H.z, H.flick, H.dc);
        case 2: return float4(min(H.age, 60.0f), H.R2, H.kind, H.tone);
        default: return float4(0.0f, H.mfrac, H.X - Xc);
    }
}
static inline float dipped(Hand H) { return smoothstep(0.0f, 0.35f, H.z); }
// lifted, the hand hovers and flicks in drops: it drifts slowly, so drops land in drops
static inline float hover_k(Hand H) { return mix(0.3f, 1.0f, dipped(H)); }

// ----------------------------------------------------------------- the flow --
// Each returns (psi, dpsi/dx, dpsi/dy). The velocity is (dpsi/dy, -dpsi/dx).

// The stylus: (V x r) Phi(r). Inside the core the liquid moves with V; outside, the
// drag falls off and the displaced liquid comes back around the sides.
static inline float3 psi_hand(float2 p, Hand H) {
    const float2 r = p - H.X;
    const float rho = sqrt(dot(r, r) + STY_A * STY_A);
    const float phi = exp(-(rho - STY_A) / STY_L);
    const float s = H.V.x * r.y - H.V.y * r.x;
    const float k = s / (STY_L * rho);
    return float3(s * phi, -phi * (H.V.y + k * r.x), phi * (H.V.x - k * r.y));
}
// argus_noise with its exact gradient: (n, dn/dx, dn/dy).
static inline float3 noise_grad(float2 p) {
    const float2 i = floor(p);
    const float2 fr = p - i;
    const float2 u = fr * fr * (3.0f - 2.0f * fr);
    const float2 du = 6.0f * fr * (1.0f - fr);
    const uint2 c = uint2(int2(i) + 32768);
    const float a = argus_rand(c, 0u), b = argus_rand(c + uint2(1, 0), 0u);
    const float d = argus_rand(c + uint2(0, 1), 0u), e = argus_rand(c + uint2(1, 1), 0u);
    const float k1 = b - a, k2 = d - a, k3 = e - d - b + a;
    return float3(2.0f * (a + k1 * u.x + k2 * u.y + k3 * u.x * u.y) - 1.0f,
                  2.0f * du.x * (k1 + k3 * u.y), 2.0f * du.y * (k2 + k3 * u.x));
}
// The slow convection that keeps the bath alive: two drifting layers of noise.
static inline float3 psi_amb(float2 p, float t) {
    const float3 n1 = noise_grad(p * 1.3f + float2(0.026f, -0.018f) * t);
    const float3 n2 = noise_grad(p * 2.3f - float2(0.022f, 0.032f) * t + 7.3f);
    return AMB * float3(n1.x + 0.6f * n2.x, 1.3f * n1.yz + 1.38f * n2.yz);
}
// No slip: the flow fades to zero in a thin layer along the frame.
static inline float3 wall_w(float2 p, float2 B) {
    const float2 d = max(B - abs(p), 0.0f);
    const float2 ex = exp(-d / WALL_D);
    const float2 w = 1.0f - ex;
    const float2 dw = -sign(p) * ex / WALL_D;
    return float3(w.x * w.y, dw.x * w.y, w.x * dw.y);
}

// ------------------------------------------------------------ state sampling --
static inline float4 rd(texture2d<float, access::read> tex, int x, int y, int w, int h) {
    return tex.read(uint2(clamp(x, 0, w - 1), clamp(y, 0, h - 1)));
}

// Clamped Catmull-Rom resample, and the 5-point Laplacian at the same spot (bilinear over
// the four central texels), both from one 4x4 read.
static float4 sample_cr(texture2d<float, access::read> tex, float2 pos, int w, int h, thread float4& lap) {
    const float2 q = pos - 0.5f;
    const float2 b = floor(q);
    const float2 t = q - b;
    const float2 t2 = t * t, t3 = t2 * t;
    const float4 wx = float4(-0.5f * t3.x + t2.x - 0.5f * t.x, 1.5f * t3.x - 2.5f * t2.x + 1.0f,
                             -1.5f * t3.x + 2.0f * t2.x + 0.5f * t.x, 0.5f * t3.x - 0.5f * t2.x);
    const float4 wy = float4(-0.5f * t3.y + t2.y - 0.5f * t.y, 1.5f * t3.y - 2.5f * t2.y + 1.0f,
                             -1.5f * t3.y + 2.0f * t2.y + 0.5f * t.y, 0.5f * t3.y - 0.5f * t2.y);
    const int x0 = int(b.x), y0 = int(b.y);
    float4 v[4][4];
    for (int j = 0; j < 4; j++)
        for (int i = 0; i < 4; i++) v[j][i] = rd(tex, x0 - 1 + i, y0 - 1 + j, w, h);
    float4 acc = 0.0f;
    for (int j = 0; j < 4; j++)
        acc += wy[j] * (wx[0] * v[j][0] + wx[1] * v[j][1] + wx[2] * v[j][2] + wx[3] * v[j][3]);
    const float4 lo = min(min(v[1][1], v[1][2]), min(v[2][1], v[2][2]));
    const float4 hi = max(max(v[1][1], v[1][2]), max(v[2][1], v[2][2]));
    const float4 l11 = v[0][1] + v[2][1] + v[1][0] + v[1][2] - 4.0f * v[1][1];
    const float4 l12 = v[0][2] + v[2][2] + v[1][1] + v[1][3] - 4.0f * v[1][2];
    const float4 l21 = v[1][1] + v[3][1] + v[2][0] + v[2][2] - 4.0f * v[2][1];
    const float4 l22 = v[1][2] + v[3][2] + v[2][1] + v[2][3] - 4.0f * v[2][2];
    lap = mix(mix(l11, l12, t.x), mix(l21, l22, t.x), t.y);
    return clamp(acc, lo, hi);
}

static float ink_tone_field(float2 p, uint seed) {
    return 0.5f + 0.5f * argus_fbm(p * 1.3f + float2(float(seed & 255u), float((seed >> 8) & 255u)) * 0.37f, 4);
}

static inline float2 cell_pos(uint2 gid, int w, int hl, float2 B) {
    return float2(((float(gid.x) + 0.5f) / float(w) * 2.0f - 1.0f) * B.x,
                  (1.0f - (float(gid.y) + 0.5f) / float(hl) * 2.0f) * B.y);
}

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    const int w = int(f.state_width), hl = int(f.state_height) - 1;
    const float2 B = bath_extent(f);
    const uint sd = argus_hash(f.seed ^ 0xA511E9B3u);
    if (int(gid.y) == hl) {
        Hand H;
        H.X = float2(rnd(sd, 1u) - 0.5f, rnd(sd, 2u) - 0.5f) * B;
        H.V = 0.0f; H.z = -0.3f; H.flick = 0.0f; H.dc = H.X;
        H.age = DROP_DUR + DROP_GAP; H.R2 = 0.0f; H.kind = 1.0f; H.tone = 0.5f;
        H.mfrac = 0.3f;
        state.write(gid.x < 4u ? hand_texel(H, gid.x) : float4(0.0f), gid);
        return;
    }
    // The bath starts as ink with a few random pools of metal already resting in it.
    const float2 P = cell_pos(gid, w, hl, B);
    float m = 0.0f;
    for (uint i = 0; i < 6u; i++) {
        const float2 c = (float2(rnd(sd, 10u + i), rnd(sd, 20u + i)) * 2.0f - 1.0f) * B * 0.8f;
        const float r = 0.08f + 0.22f * rnd(sd, 30u + i);
        m = max(m, smoothstep(r + 0.004f, r - 0.004f, length(P - c)));
    }
    state.write(float4(m, ink_tone_field(P, f.seed), 0.0f, 0.0f), gid);
}

// ------------------------------------------------------------------ the step --
kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    const int w = int(f.state_width), h = int(f.state_height), hl = h - 1;
    if (int(gid.x) >= w || int(gid.y) >= h) return;
    const float2 B = bath_extent(f);
    const float dt = clamp(f.dt, 0.0f, 1.0f / 15.0f) / float(STEPS);
    Hand H = read_hand(prev, uint(hl));

    if (int(gid.y) == hl) {
        // ------------------------------------------------ the hand rolls its dice --
        if (gid.x >= 4u) { next.write(float4(0.0f), gid); return; }
        const uint s = argus_hash(f.frame * 0x9E3779B9u ^ f.seed);
        H.V += -H.V * (dt / TAU_V) + SIG_V * sqrt(2.0f * dt / TAU_V) * float2(gauss(s, 1u), gauss(s, 3u));
        const float2 lim = B * 0.78f;
        H.V -= (max(abs(H.X) - lim, 0.0f) * sign(H.X)) * 30.0f * dt;     // the frame turns it back
        // lifted, the hand hovers and sprinkles: it drifts slowly, so drops fall on drops
        H.X = clamp(H.X + H.V * dt * hover_k(H), -B * 0.92f, B * 0.92f);
        H.z += (Z_MEAN - H.z) * (dt / TAU_Z) + Z_SIG * sqrt(2.0f * dt / TAU_Z) * gauss(s, 5u);
        H.flick += -H.flick * (dt / 0.12f) + sqrt(2.0f * dt / 0.12f) * gauss(s, 7u);
        // the hand looks at the bath
        float ms = 0.0f;
        for (uint k = 0; k < 16u; k++)
            ms += prev.read(uint2(min(uint(rnd(s, 20u + k) * float(w)), uint(w - 1)),
                                  min(uint(rnd(s, 40u + k) * float(hl)), uint(hl - 1)))).x;
        H.mfrac = mix(H.mfrac, ms / 16.0f, 0.02f);
        // a drop?
        H.age += dt;
        if (H.age > DROP_DUR + DROP_GAP) {
            const float rate = mix(RATE_LIFTED, RATE_DIPPED, dipped(H));
            if (rnd(s, 60u) < rate * dt) {
                const float pm = clamp(0.5f + 2.5f * (0.42f - H.mfrac), 0.15f, 0.85f);
                H.age = 0.0f;
                H.dc = H.X;
                H.kind = rnd(s, 61u) < pm ? 1.0f : 0.0f;
                const float R = 0.035f + 0.17f * pow(rnd(s, 62u), 1.5f);
                H.R2 = R * R;
                // deep or bright, never in between: each ink drop is a ring you can see
                H.tone = rnd(s, 63u) < 0.5f ? 0.05f + 0.2f * rnd(s, 64u) : 0.8f + 0.2f * rnd(s, 64u);
            }
        }
        next.write(hand_texel(H, gid.x), gid);
        return;
    }

    // --------------------------------------------------------- the liquid moves --
    const float2 P0 = cell_pos(gid, w, hl, B);
    const float hx = 2.0f * B.x / float(w), hy = 2.0f * B.y / float(hl);
    const float a = dipped(H);
    const int x = int(gid.x), y = int(gid.y);
    const float4 c4 = prev.read(gid);
    const float4 r4 = rd(prev, x + 1, y, w, hl), l4 = rd(prev, x - 1, y, w, hl);
    const float4 u4 = rd(prev, x, y - 1, w, hl), d4 = rd(prev, x, y + 1, w, hl);   // up = row - 1

    // Trace back along the flow. The flow is the stylus and the convection, held still at the
    // frame (psi = W (a psi_hand + psi_amb)), plus the wake. The convection and the wake are
    // smooth and slow, so they are taken once at the cell; near the dipped stylus the trace
    // follows it in sub-steps as it moves, so fast strokes stay smooth.
    const float3 ph = psi_hand(P0, H);
    const float3 ww = wall_w(P0, B);
    const float3 pa = psi_amb(P0, f.time);
    const float2 ga = ww.x * pa.yz + pa.x * ww.yz;
    const float2 vslow = float2(ga.y + (u4.z - d4.z) / (2.0f * hy), -ga.x - (r4.z - l4.z) / (2.0f * hx));
    float2 P = P0 - vslow * dt;
    const float2 rh = P0 - H.X;
    const float reach = 0.25f + dot(H.V, H.V) * dt * dt * 4.0f;    // the stylus's influence (r ~ 0.5)
    if (a > 1e-3f && dot(rh, rh) < reach) {
        const int SUB = 3;
        const float sdt = dt / float(SUB);
        Hand Hs = H;
        float2 Ph = P0;
        for (int i = 0; i < SUB; i++) {
            Hs.X = H.X + H.V * hover_k(H) * (dt - (float(i) + 0.5f) * sdt);
            const float3 phs = psi_hand(Ph, Hs);
            const float2 g = a * (ww.x * phs.yz + phs.x * ww.yz);
            Ph -= float2(g.y, -g.x) * sdt;
        }
        P += Ph - P0;
    }

    // a drop spreading: the exact area-adding map, pulled back
    bool fresh = false;
    if (H.age < DROP_DUR) {
        const float dl = H.R2 * (ease3((H.age + dt) / DROP_DUR) - ease3(H.age / DROP_DUR));
        const float2 q = P - H.dc;
        const float d2 = dot(q, q);
        if (d2 < dl) fresh = true;
        else P = H.dc + q * sqrt(1.0f - dl / d2);
    }

    float4 lap;
    const float2 pos = float2((P.x / B.x + 1.0f) * 0.5f * float(w), (1.0f - P.y / B.y) * 0.5f * float(hl));
    float4 s = sample_cr(prev, pos, w, hl, lap);
    float m = s.x, b = s.y;
    if (fresh) {
        m = H.kind;
        b = H.kind > 0.5f ? 0.5f : H.tone;
    } else {
        // the metal holds together; the ink mixes
        m += M_DIFF * lap.x + M_SHARP * m * (1.0f - m) * (m - 0.5f);
        b += B_DIFF * lap.y;
    }

    // the wake: momentum left by the stylus, spread by viscosity, lost to the floor
    float pw = c4.z;
    const float lw = r4.z + l4.z + u4.z + d4.z - 4.0f * pw;
    const float near = exp(-sqrt(dot(rh, rh) + STY_A * STY_A) / STY_L);
    pw += D_WAKE * lw - (dt / TAU_W) * pw + dt * KAPPA * a * near * (BETA * ph.x - pw);
    pw *= ww.x;

    next.write(float4(saturate(m), saturate(b), pw, 0.0f), gid);
}

// ============================================================== the shading ==

// The glass ceiling, in tan-angle coordinates (x/z, y/z) as seen from the bath: a grid of
// slim beams, a studio light centred in each pane of the middle 7 x 3, overcast daylight
// through the rest.
constant float  CEIL_H  = 3.6f;                        // the ceiling's height, in bath units
constant float2 PITCH   = float2(0.185f, 0.24f);       // pane size
constant float2 LAMP    = float2(0.056f, 0.034f);      // a light's half-size
constant float  BEAM_W  = 0.0035f;                     // beam half-width
constant float  AA      = 0.0008f;                     // about a pixel, in tan-angle units
constant float3 LAMP_COL = float3(1.0f, 0.975f, 0.94f) * 9.0f;    // ~5600 K panels
constant float3 SKY_COL  = float3(0.085f, 0.10f, 0.125f);          // overcast, through glass
constant float3 WALL_COL = float3(0.030f, 0.032f, 0.035f);        // the studio's walls
constant float3 METAL_F0 = float3(0.80f, 0.81f, 0.82f);           // the liquid metal
constant float3 ALU_F0   = float3(0.91f, 0.92f, 0.92f);           // aluminium
constant float3 INK_DEEP   = float3(0.0035f, 0.006f, 0.030f);     // indigo
constant float3 INK_BRIGHT = float3(0.010f, 0.105f, 0.200f);      // bright cyan-blue

static inline float sd_rbox(float2 q, float2 b, float r) {
    const float2 dd = abs(q) - b + r;
    return length(max(dd, 0.0f)) + min(max(dd.x, dd.y), 0.0f) - r;
}

// What a mirror sees looking along R (unit, world: z up). `blur` (tan-angle units) softens
// the reflection for a surface that is less than a perfect mirror.
static float3 env(float3 R, float blur) {
    float3 col = WALL_COL;
    if (R.z > 0.02f) {
        const float2 tq = R.xy / R.z;
        float3 c = SKY_COL * (0.55f + 0.45f * R.z);
        // the beams between the panes
        const float2 db = abs(fract(tq / PITCH) - 0.5f) * PITCH;
        c *= smoothstep(BEAM_W - AA - blur, BEAM_W + AA + blur, min(db.x, db.y)) * mix(0.9f, 0.3f, saturate(blur * 60.0f)) + mix(0.1f, 0.7f, saturate(blur * 60.0f));
        // the lights
        const float2 k = round(tq / PITCH);
        if (abs(k.x) <= 3.0f && abs(k.y) <= 1.0f) {
            const float sd = sd_rbox(tq - k * PITCH, LAMP, 0.008f);
            const float spread = (LAMP.x * LAMP.y) / ((LAMP.x + blur) * (LAMP.y + blur));   // same power, larger patch
            c += LAMP_COL * spread * smoothstep(AA + blur, -AA - blur, sd);
            c += LAMP_COL * 0.012f * exp(-max(sd, 0.0f) / (0.018f + blur));   // the diffuser's glow
        }
        col = mix(WALL_COL, c, smoothstep(0.02f, 0.12f, R.z));
    }
    return col;
}

static inline float3 schlick(float3 F0, float c) {
    const float m = pow(1.0f - saturate(c), 5.0f);
    return F0 + (1.0f - F0) * m;
}

// Brushed aluminium at world point P, normal n, grain T. The highlight streaks come from
// the lights nearest across the grain: along a bar brushed in x, the 7 columns of the
// nearest row; along a bar brushed in y, the 3 rows of the nearest column.
static float3 brushed(float3 P, float3 n, float3 T, bool along_x, float grain, float3 V) {
    float spec = 0.0f;
    const float2 lp = PITCH * CEIL_H;
    if (along_x) {
        const float ly = clamp(round(P.y / lp.y), -1.0f, 1.0f) * lp.y;
        for (int i = -3; i <= 3; i++) {
            const float3 Lc = normalize(float3(float(i) * lp.x, ly, CEIL_H) - P);
            const float3 Hc = normalize(Lc + V);
            const float th = dot(T, Hc);
            spec += pow(sqrt(saturate(1.0f - th * th)), 160.0f) * saturate(dot(n, Hc) * 4.0f);
        }
    } else {
        const float lx = clamp(round(P.x / lp.x), -3.0f, 3.0f) * lp.x;
        for (int j = -1; j <= 1; j++) {
            const float3 Lc = normalize(float3(lx, float(j) * lp.y, CEIL_H) - P);
            const float3 Hc = normalize(Lc + V);
            const float th = dot(T, Hc);
            spec += pow(sqrt(saturate(1.0f - th * th)), 160.0f) * saturate(dot(n, Hc) * 4.0f);
        }
    }
    const float3 F = schlick(ALU_F0, saturate(dot(n, V)));
    const float up = saturate(n.z);
    const float3 amb = float3(0.040f, 0.043f, 0.048f) * (0.35f + 0.65f * up);   // the bright ceiling, blurred
    return F * (amb * (0.8f + 0.4f * grain) + float3(1.0f, 0.975f, 0.94f) * spec * 0.05f * (0.4f + 1.2f * grain));
}

// The grain: fine streaks along `along`, varying across it.
static inline float grain_at(float along, float across, float salt) {
    return saturate(0.5f + 0.32f * argus_noise(float2(across * 1100.0f + salt, along * 2.0f))
                         + 0.18f * argus_noise(float2(across * 2600.0f, along * 6.0f + salt))
                         + 0.14f * argus_noise(float2(across * 240.0f + salt, along * 0.7f)));
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> state [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    const float2 B = bath_extent(f);
    const float2 uv = argus_uv(gid, f);
    const uint hl = f.state_height - 1u;
    const float vscale = float(hl) / float(f.state_height);
    const float vmax = (float(hl) - 0.5f) / float(f.state_height);
    const float3 KEY = normalize(float3(0.0f, 0.0f, 1.0f));

    const float3 d = normalize(float3(uv, -FC));
    const float3 V = -d;
    auto st_at = [&](float2 p) {
        return state.sample(smp, float2((p.x / B.x + 1.0f) * 0.5f, min((1.0f - p.y / B.y) * 0.5f * vscale, vmax)));
    };

    const float2 Pl = uv * (ZC / FC);                 // where the ray meets the bath plane
    const float2 Pt = uv * ((ZC - RIM_H) / FC);       // ... and the frame's top face
    const float2 ot = abs(Pt) - B;                    // > 0: on the frame's top
    float3 col;

    if (max(ot.x, ot.y) > 0.0f) {
        // ------------------------------------------------------ the frame's top --
        // four solid bars, mitred at the corners, each brushed along its length
        const bool vbar = ot.x > ot.y;
        const float2 outward = vbar ? float2(sign(Pt.x), 0.0f) : float2(0.0f, sign(Pt.y));
        const float o = max(ot.x, ot.y);
        const float along = vbar ? Pt.y : Pt.x, across = vbar ? Pt.x : Pt.y;
        const float3 T = vbar ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
        const float gr = grain_at(along, across, vbar ? 37.0f : 0.0f);
        // the inner edge is rounded over into the bath
        const float e = saturate(1.0f - o / CHAMF);
        const float tilt = 1.25f * e * e;
        const float3 n = normalize(float3(-outward * sin(tilt), cos(tilt)));
        col = brushed(float3(Pt, RIM_H), n, T, !vbar, gr, V);
        // the rounded edge also mirrors the room a little
        col += e * 0.12f * schlick(ALU_F0, saturate(dot(n, V))) * env(reflect(d, n), 0.0f);
        // the mitre seams where the bars meet
        if (ot.x > 0.0f && ot.y > 0.0f) col *= mix(1.0f, 0.3f, smoothstep(0.0022f, 0.0006f, abs(ot.x - ot.y)));
    } else if (abs(Pl.x) < B.x && abs(Pl.y) < B.y) {
        // ---------------------------------------------------------- the liquid --
        const float2 P = Pl;
        const float4 s = st_at(P);
        const float2 tx = float2(2.0f * B.x / float(f.state_width), 2.0f * B.y / float(hl)) * 1.5f;
        const float4 sr = st_at(P + float2(tx.x, 0.0f)), sl = st_at(P - float2(tx.x, 0.0f));
        const float4 su = st_at(P + float2(0.0f, tx.y)), sd = st_at(P - float2(0.0f, tx.y));
        // the metal stands proud of the ink, with rounded edges
        const float hm = 0.010f;
        // (its height saturates just short of 0 and 1, so the half-float rounding of a resting
        // pool cannot ripple its mirror)
        auto ht = [](float m) { return smoothstep(0.03f, 0.97f, m); };
        const float h0 = ht(s.x), hr = ht(sr.x), hl_ = ht(sl.x), hu = ht(su.x), hd = ht(sd.x);
        float2 grad = float2(hr - hl_, hu - hd) * hm / (2.0f * tx);
        // the meniscus: the liquid climbs the frame where it touches it
        const float dwx = B.x - abs(P.x), dwy = B.y - abs(P.y);
        grad += float2(sign(P.x) * exp(-dwx / 0.012f), sign(P.y) * exp(-dwy / 0.012f)) * 0.6f;
        const float3 n = normalize(float3(-grad, 1.0f));
        const float3 R = reflect(d, n);
        const float ndv = saturate(dot(n, V));
        // The reflection's footprint: one pixel turns the normal by the surface's curvature
        // times the pixel size, the reflection by twice that, and the ceiling's tan-angle
        // coordinates by that over R.z^2. Filtering the room by it keeps the edges from grain.
        const float kx = hr - 2.0f * h0 + hl_, ky = hu - 2.0f * h0 + hd;
        const float curv = hm * (abs(kx) / (tx.x * tx.x) + abs(ky) / (tx.y * tx.y))
                         + 50.0f * (exp(-dwx / 0.012f) + exp(-dwy / 0.012f));   // the meniscus's own bend
        const float pix = 2.0f * (ZC / FC) / float(f.height);
        const float foot = 2.0f * curv * pix / max(R.z * R.z, 0.03f);
        const float wm = smoothstep(0.3f, 0.7f, s.x);
        const float3 er = wm > 0.0f ? env(R, min(0.0015f + foot, 0.08f)) : float3(0.0f);
        const float3 eri = wm < 1.0f ? env(R, 0.06f + foot) : float3(0.0f);   // the ink is glossy, not a mirror

        // ink: a glossy dielectric, lit from the bright ceiling above
        const float3 body = mix(INK_DEEP, INK_BRIGHT, s.y * s.y);
        const float lit = 0.25f + 0.75f * saturate(dot(n, KEY));
        const float Fb = 0.02f + 0.98f * pow(1.0f - ndv, 5.0f);
        const float3 ci = body * lit * (1.0f - Fb) + Fb * eri;

        // the metal: a mirror
        const float3 cm = schlick(METAL_F0, ndv) * er;

        col = mix(ci, cm, wm);
        // the frame's contact shadow
        col *= 0.5f + 0.5f * smoothstep(0.0f, 0.10f, min(dwx, dwy));
    } else {
        // ------------------------------------------- the frame's inner face --
        const float zx = abs(uv.x) > 1e-5f ? ZC - B.x * FC / abs(uv.x) : -1e9f;
        const float zy = abs(uv.y) > 1e-5f ? ZC - B.y * FC / abs(uv.y) : -1e9f;
        const bool vbar = zx > zy;
        const float z = clamp(max(zx, zy), 0.0f, RIM_H);
        const float2 inward = vbar ? float2(-sign(uv.x), 0.0f) : float2(0.0f, -sign(uv.y));
        const float3 P3 = float3(uv * (ZC - z) / FC, z);
        const float gr = grain_at(vbar ? P3.y : P3.x, z * 3.0f, 71.0f);
        col = brushed(P3, float3(inward, 0.0f), float3(0.0f, 0.0f, 1.0f), false, gr, V) * (0.35f + 0.65f * z / RIM_H);
    }

    col *= 1.0f - 0.12f * dot(uv / half_extent(f), uv / half_extent(f));
    col *= 1.5f;
    out.write(float4(argus_srgb(argus_aces(col)), 1.0f), gid);
}

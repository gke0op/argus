// ============================================================================
// EBRU STUDIO // themes/Ebru_Studio.metal
// The WGSL translation of themes/Ebru_Studio.metal (web/themes/Ebru_Studio.wgsl), one to one.
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

const PI: f32  = 3.14159265;
const TAU: f32 = 6.2831853;
const STEPS: i32 = 1;

// ----------------------------------------------------------------- the frame --
// A camera straight above at height ZC (focal length FC) looks down on the bath at
// z = 0. The frame lies on it, RIM_H thick, with its inner edge BORDER (in screen
// units) in from each screen edge; it runs out past the screen on every side.
const ZC: f32     = 3.0;
const FC: f32     = 2.22;
const BORDER: f32 = 0.15;
const RIM_H: f32  = 0.075;
const CHAMF: f32  = 0.016;   // the rounded inner edge

// ------------------------------------------------------------------ the hand --
const TAU_V: f32  = 0.8;     // s: how long the hand keeps a direction
const SIG_V: f32  = 0.85;    // rms stylus speed, in bath units per second
const TAU_Z: f32  = 1.3;     // s: how long it stays in or out of the bath
const Z_MEAN: f32 = 0.25;
const Z_SIG: f32  = 0.55;
const STY_A: f32  = 0.012;   // the stylus's no-slip core (a fine awl)
const STY_L: f32  = 0.035;   // the distance over which its drag falls off
const DROP_DUR: f32 = 0.45;  // s for a drop to spread
const DROP_GAP: f32 = 0.05;
const RATE_LIFTED: f32 = 6.0; const RATE_DIPPED: f32 = 0.8;   // drops per second

// ------------------------------------------------------------------ the bath --
const TAU_W: f32  = 1.6;     // s: the wake's lifetime (floor drag)
const KAPPA: f32  = 6.0;     // 1/s: how fast the stylus leaves motion in the liquid
const BETA: f32   = 0.7;
const D_WAKE: f32 = 0.24;    // cells^2 per step: the wake's viscous spread (near the stability limit)
const AMB: f32    = 0.009;   // stream-function amplitude of the slow convection
const WALL_D: f32 = 0.035;   // no-slip boundary layer at the frame
const M_DIFF: f32 = 0.07;    // metal surface tension (Allen-Cahn): interface spread
const M_SHARP: f32 = 0.12;   //   ... and the pull back to 0 or 1
const B_DIFF: f32 = 0.06;    // ink tone mixing

fn rnd(s: u32, k: u32) -> f32 {
    return f32(argus_hash(s ^ argus_hash(k * 0x85EBCA6Bu + 0x632BE5ABu))) * (1.0 / 4294967296.0);
}
fn gauss(s: u32, k: u32) -> f32 {
    let u1 = max(rnd(s, k), 1e-7); let u2 = rnd(s, k + 1u);
    return sqrt(-2.0 * log(u1)) * cos(TAU * u2);
}
fn half_extent(fr: ArgusFrame) -> vec2f {
    return vec2f(f32(fr.width), f32(fr.height)) / f32(min(fr.width, fr.height));
}
// The bath's half-size in world units (z = 0 maps to the screen scaled by FC / ZC).
fn bath_extent(fr: ArgusFrame) -> vec2f {
    return (half_extent(fr) - BORDER) * (ZC / FC);
}
fn ease3(x_in: f32) -> f32 { let x = saturate(x_in); return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x); }

// Metal's round(): halfway cases away from zero (WGSL's round() goes to even).
fn round_away(x: vec2f) -> vec2f { let t = trunc(x); return select(t, t + sign(x), abs(x - t) >= vec2f(0.5)); }
fn round_away1(x: f32) -> f32 { let t = trunc(x); return select(t, t + sign(x), abs(x - t) >= 0.5); }

// ---------------------------------------------------------- the hand's texels --
struct Hand {
    X: vec2f, V: vec2f,     // stylus position and velocity
    z: f32, flick: f32,     // depth process (dipped when > 0), a spare random process
    dc: vec2f,              // the current drop's centre
    age: f32, R2: f32, kind: f32, tone: f32,  // its age (s), final r^2, 1 = metal, ink tone
    mfrac: f32,             // estimated metal fraction
}

fn read_hand(s: texture_2d<f32>, row: u32) -> Hand {
    let a = textureLoad(s, vec2u(0u, row), 0); let b = textureLoad(s, vec2u(1u, row), 0);
    let c = textureLoad(s, vec2u(2u, row), 0); let d = textureLoad(s, vec2u(3u, row), 0);
    var H: Hand;
    H.X = a.xy + d.zw; H.V = a.zw;          // coarse + fine
    H.z = b.x; H.flick = b.y; H.dc = b.zw;
    H.age = c.x; H.R2 = c.y; H.kind = c.z; H.tone = c.w;
    H.mfrac = d.y;
    return H;
}
fn hand_texel(H: Hand, i: u32) -> vec4f {
    let Xc = unpack2x16float(pack2x16float(H.X));   // Metal: float2(half2(H.X))
    switch (i) {
        case 0u: { return vec4f(Xc, H.V); }
        case 1u: { return vec4f(H.z, H.flick, H.dc); }
        case 2u: { return vec4f(min(H.age, 60.0), H.R2, H.kind, H.tone); }
        default: { return vec4f(0.0, H.mfrac, H.X - Xc); }
    }
}
fn dipped(H: Hand) -> f32 { return smoothstep(0.0, 0.35, H.z); }
// lifted, the hand hovers and flicks in drops: it drifts slowly, so drops land in drops
fn hover_k(H: Hand) -> f32 { return mix(0.3, 1.0, dipped(H)); }

// ----------------------------------------------------------------- the flow --
// Each returns (psi, dpsi/dx, dpsi/dy). The velocity is (dpsi/dy, -dpsi/dx).

// The stylus: (V x r) Phi(r). Inside the core the liquid moves with V; outside, the
// drag falls off and the displaced liquid comes back around the sides.
fn psi_hand(p: vec2f, H: Hand) -> vec3f {
    let r = p - H.X;
    let rho = sqrt(dot(r, r) + STY_A * STY_A);
    let phi = exp(-(rho - STY_A) / STY_L);
    let s = H.V.x * r.y - H.V.y * r.x;
    let k = s / (STY_L * rho);
    return vec3f(s * phi, -phi * (H.V.y + k * r.x), phi * (H.V.x - k * r.y));
}
// argus_noise with its exact gradient: (n, dn/dx, dn/dy).
fn noise_grad(p: vec2f) -> vec3f {
    let i = floor(p);
    let fr = p - i;
    let u = fr * fr * (3.0 - 2.0 * fr);
    let du = 6.0 * fr * (1.0 - fr);
    let c = vec2u(vec2i(i) + 32768);
    let a = argus_rand(c, 0u); let b = argus_rand(c + vec2u(1u, 0u), 0u);
    let d = argus_rand(c + vec2u(0u, 1u), 0u); let e = argus_rand(c + vec2u(1u, 1u), 0u);
    let k1 = b - a; let k2 = d - a; let k3 = e - d - b + a;
    return vec3f(2.0 * (a + k1 * u.x + k2 * u.y + k3 * u.x * u.y) - 1.0,
                 2.0 * du.x * (k1 + k3 * u.y), 2.0 * du.y * (k2 + k3 * u.x));
}
// The slow convection that keeps the bath alive: two drifting layers of noise.
fn psi_amb(p: vec2f, t: f32) -> vec3f {
    let n1 = noise_grad(p * 1.3 + vec2f(0.026, -0.018) * t);
    let n2 = noise_grad(p * 2.3 - vec2f(0.022, 0.032) * t + 7.3);
    return AMB * vec3f(n1.x + 0.6 * n2.x, 1.3 * n1.yz + 1.38 * n2.yz);
}
// No slip: the flow fades to zero in a thin layer along the frame.
fn wall_w(p: vec2f, B: vec2f) -> vec3f {
    let d = max(B - abs(p), vec2f(0.0));
    let ex = exp(-d / WALL_D);
    let w = 1.0 - ex;
    let dw = -sign(p) * ex / WALL_D;
    return vec3f(w.x * w.y, dw.x * w.y, w.x * dw.y);
}

// ------------------------------------------------------------ state sampling --
fn rd(tex: texture_2d<f32>, x: i32, y: i32, w: i32, h: i32) -> vec4f {
    return textureLoad(tex, vec2u(u32(clamp(x, 0, w - 1)), u32(clamp(y, 0, h - 1))), 0);
}

// Clamped Catmull-Rom resample, and the 5-point Laplacian at the same spot (bilinear over
// the four central texels), both from one 4x4 read.
fn sample_cr(tex: texture_2d<f32>, pos: vec2f, w: i32, h: i32, lap: ptr<function, vec4f>) -> vec4f {
    let q = pos - 0.5;
    let b = floor(q);
    let t = q - b;
    let t2 = t * t; let t3 = t2 * t;
    let wx = vec4f(-0.5 * t3.x + t2.x - 0.5 * t.x, 1.5 * t3.x - 2.5 * t2.x + 1.0,
                   -1.5 * t3.x + 2.0 * t2.x + 0.5 * t.x, 0.5 * t3.x - 0.5 * t2.x);
    let wy = vec4f(-0.5 * t3.y + t2.y - 0.5 * t.y, 1.5 * t3.y - 2.5 * t2.y + 1.0,
                   -1.5 * t3.y + 2.0 * t2.y + 0.5 * t.y, 0.5 * t3.y - 0.5 * t2.y);
    let x0 = i32(b.x); let y0 = i32(b.y);
    var v: array<array<vec4f, 4>, 4>;
    for (var j = 0; j < 4; j++) {
        for (var i = 0; i < 4; i++) { v[j][i] = rd(tex, x0 - 1 + i, y0 - 1 + j, w, h); }
    }
    var acc = vec4f(0.0);
    for (var j = 0; j < 4; j++) {
        acc += wy[j] * (wx[0] * v[j][0] + wx[1] * v[j][1] + wx[2] * v[j][2] + wx[3] * v[j][3]);
    }
    let lo = min(min(v[1][1], v[1][2]), min(v[2][1], v[2][2]));
    let hi = max(max(v[1][1], v[1][2]), max(v[2][1], v[2][2]));
    let l11 = v[0][1] + v[2][1] + v[1][0] + v[1][2] - 4.0 * v[1][1];
    let l12 = v[0][2] + v[2][2] + v[1][1] + v[1][3] - 4.0 * v[1][2];
    let l21 = v[1][1] + v[3][1] + v[2][0] + v[2][2] - 4.0 * v[2][1];
    let l22 = v[1][2] + v[3][2] + v[2][1] + v[2][3] - 4.0 * v[2][2];
    *lap = mix(mix(l11, l12, t.x), mix(l21, l22, t.x), t.y);
    return clamp(acc, lo, hi);
}

fn ink_tone_field(p: vec2f, seed: u32) -> f32 {
    return 0.5 + 0.5 * argus_fbm(p * 1.3 + vec2f(f32(seed & 255u), f32((seed >> 8u) & 255u)) * 0.37, 4);
}

fn cell_pos(gid: vec2u, w: i32, hl: i32, B: vec2f) -> vec2f {
    return vec2f(((f32(gid.x) + 0.5) / f32(w) * 2.0 - 1.0) * B.x,
                 (1.0 - (f32(gid.y) + 0.5) / f32(hl) * 2.0) * B.y);
}

@compute @workgroup_size(8, 8)
fn argus_init(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    let w = i32(f.state_width); let hl = i32(f.state_height) - 1;
    let B = bath_extent(f);
    let sd = argus_hash(f.seed ^ 0xA511E9B3u);
    if (i32(gid.y) == hl) {
        var H: Hand;
        H.X = vec2f(rnd(sd, 1u) - 0.5, rnd(sd, 2u) - 0.5) * B;
        H.V = vec2f(0.0); H.z = -0.3; H.flick = 0.0; H.dc = H.X;
        H.age = DROP_DUR + DROP_GAP; H.R2 = 0.0; H.kind = 1.0; H.tone = 0.5;
        H.mfrac = 0.3;
        textureStore(argus_state_out, gid, select(vec4f(0.0), hand_texel(H, gid.x), gid.x < 4u));
        return;
    }
    // The bath starts as ink with a few random pools of metal already resting in it.
    let P = cell_pos(gid, w, hl, B);
    var m = 0.0;
    for (var i = 0u; i < 6u; i++) {
        let c = (vec2f(rnd(sd, 10u + i), rnd(sd, 20u + i)) * 2.0 - 1.0) * B * 0.8;
        let r = 0.08 + 0.22 * rnd(sd, 30u + i);
        m = max(m, smoothstep(r + 0.004, r - 0.004, length(P - c)));
    }
    textureStore(argus_state_out, gid, vec4f(m, ink_tone_field(P, f.seed), 0.0, 0.0));
}

// ------------------------------------------------------------------ the step --
@compute @workgroup_size(8, 8)
fn argus_step(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    let w = i32(f.state_width); let h = i32(f.state_height); let hl = h - 1;
    if (i32(gid.x) >= w || i32(gid.y) >= h) { return; }
    let B = bath_extent(f);
    let dt = clamp(f.dt, 0.0, 1.0f / 15.0f) / f32(STEPS);
    var H = read_hand(argus_state, u32(hl));

    if (i32(gid.y) == hl) {
        // ------------------------------------------------ the hand rolls its dice --
        if (gid.x >= 4u) { textureStore(argus_state_out, gid, vec4f(0.0)); return; }
        let s = argus_hash((f.frame * 0x9E3779B9u) ^ f.seed);
        H.V += -H.V * (dt / TAU_V) + SIG_V * sqrt(2.0 * dt / TAU_V) * vec2f(gauss(s, 1u), gauss(s, 3u));
        let lim = B * 0.78;
        H.V -= (max(abs(H.X) - lim, vec2f(0.0)) * sign(H.X)) * 30.0 * dt;     // the frame turns it back
        // lifted, the hand hovers and sprinkles: it drifts slowly, so drops fall on drops
        H.X = clamp(H.X + H.V * dt * hover_k(H), -B * 0.92, B * 0.92);
        H.z += (Z_MEAN - H.z) * (dt / TAU_Z) + Z_SIG * sqrt(2.0 * dt / TAU_Z) * gauss(s, 5u);
        H.flick += -H.flick * (dt / 0.12) + sqrt(2.0 * dt / 0.12) * gauss(s, 7u);
        // the hand looks at the bath
        var ms = 0.0;
        for (var k = 0u; k < 16u; k++) {
            ms += textureLoad(argus_state, vec2u(min(u32(rnd(s, 20u + k) * f32(w)), u32(w - 1)),
                                                 min(u32(rnd(s, 40u + k) * f32(hl)), u32(hl - 1))), 0).x;
        }
        H.mfrac = mix(H.mfrac, ms / 16.0, 0.02);
        // a drop?
        H.age += dt;
        if (H.age > DROP_DUR + DROP_GAP) {
            let rate = mix(RATE_LIFTED, RATE_DIPPED, dipped(H));
            if (rnd(s, 60u) < rate * dt) {
                let pm = clamp(0.5 + 2.5 * (0.42 - H.mfrac), 0.15, 0.85);
                H.age = 0.0;
                H.dc = H.X;
                H.kind = select(0.0, 1.0, rnd(s, 61u) < pm);
                let R = 0.035 + 0.17 * pow(rnd(s, 62u), 1.5);
                H.R2 = R * R;
                // deep or bright, never in between: each ink drop is a ring you can see
                H.tone = select(0.8 + 0.2 * rnd(s, 64u), 0.05 + 0.2 * rnd(s, 64u), rnd(s, 63u) < 0.5);
            }
        }
        textureStore(argus_state_out, gid, hand_texel(H, gid.x));
        return;
    }

    // --------------------------------------------------------- the liquid moves --
    let P0 = cell_pos(gid, w, hl, B);
    let hx = 2.0 * B.x / f32(w); let hy = 2.0 * B.y / f32(hl);
    let a = dipped(H);
    let x = i32(gid.x); let y = i32(gid.y);
    let c4 = textureLoad(argus_state, gid, 0);
    let r4 = rd(argus_state, x + 1, y, w, hl); let l4 = rd(argus_state, x - 1, y, w, hl);
    let u4 = rd(argus_state, x, y - 1, w, hl); let d4 = rd(argus_state, x, y + 1, w, hl);   // up = row - 1

    // Trace back along the flow. The flow is the stylus and the convection, held still at the
    // frame (psi = W (a psi_hand + psi_amb)), plus the wake. The convection and the wake are
    // smooth and slow, so they are taken once at the cell; near the dipped stylus the trace
    // follows it in sub-steps as it moves, so fast strokes stay smooth.
    let ph = psi_hand(P0, H);
    let ww = wall_w(P0, B);
    let pa = psi_amb(P0, f.time);
    let ga = ww.x * pa.yz + pa.x * ww.yz;
    let vslow = vec2f(ga.y + (u4.z - d4.z) / (2.0 * hy), -ga.x - (r4.z - l4.z) / (2.0 * hx));
    var P = P0 - vslow * dt;
    let rh = P0 - H.X;
    let reach = 0.25 + dot(H.V, H.V) * dt * dt * 4.0;    // the stylus's influence (r ~ 0.5)
    if (a > 1e-3 && dot(rh, rh) < reach) {
        let SUB = 3;
        let sdt = dt / f32(SUB);
        var Hs = H;
        var Ph = P0;
        for (var i = 0; i < SUB; i++) {
            Hs.X = H.X + H.V * hover_k(H) * (dt - (f32(i) + 0.5) * sdt);
            let phs = psi_hand(Ph, Hs);
            let g = a * (ww.x * phs.yz + phs.x * ww.yz);
            Ph -= vec2f(g.y, -g.x) * sdt;
        }
        P += Ph - P0;
    }

    // a drop spreading: the exact area-adding map, pulled back
    var fresh = false;
    if (H.age < DROP_DUR) {
        let dl = H.R2 * (ease3((H.age + dt) / DROP_DUR) - ease3(H.age / DROP_DUR));
        let q = P - H.dc;
        let d2 = dot(q, q);
        if (d2 < dl) { fresh = true; }
        else { P = H.dc + q * sqrt(1.0 - dl / d2); }
    }

    var lap: vec4f;
    let pos = vec2f((P.x / B.x + 1.0) * 0.5 * f32(w), (1.0 - P.y / B.y) * 0.5 * f32(hl));
    let s = sample_cr(argus_state, pos, w, hl, &lap);
    var m = s.x; var b = s.y;
    if (fresh) {
        m = H.kind;
        b = select(H.tone, 0.5, H.kind > 0.5);
    } else {
        // the metal holds together; the ink mixes
        m += M_DIFF * lap.x + M_SHARP * m * (1.0 - m) * (m - 0.5);
        b += B_DIFF * lap.y;
    }

    // the wake: momentum left by the stylus, spread by viscosity, lost to the floor
    var pw = c4.z;
    let lw = r4.z + l4.z + u4.z + d4.z - 4.0 * pw;
    let near = exp(-sqrt(dot(rh, rh) + STY_A * STY_A) / STY_L);
    pw += D_WAKE * lw - (dt / TAU_W) * pw + dt * KAPPA * a * near * (BETA * ph.x - pw);
    pw *= ww.x;

    textureStore(argus_state_out, gid, vec4f(saturate(m), saturate(b), pw, 0.0));
}

// ============================================================== the shading ==

// The glass ceiling, in tan-angle coordinates (x/z, y/z) as seen from the bath: a grid of
// slim beams, a studio light centred in each pane of the middle 7 x 3, overcast daylight
// through the rest.
const CEIL_H: f32    = 3.6;                            // the ceiling's height, in bath units
const PITCH: vec2f   = vec2f(0.185, 0.24);             // pane size
const LAMP: vec2f    = vec2f(0.056, 0.034);            // a light's half-size
const BEAM_W: f32    = 0.0035;                         // beam half-width
const AA: f32        = 0.0008;                         // about a pixel, in tan-angle units
const LAMP_COL: vec3f = vec3f(1.0, 0.975, 0.94) * 9.0;    // ~5600 K panels
const SKY_COL: vec3f  = vec3f(0.085, 0.10, 0.125);        // overcast, through glass
const WALL_COL: vec3f = vec3f(0.030, 0.032, 0.035);       // the studio's walls
const METAL_F0: vec3f = vec3f(0.80, 0.81, 0.82);          // the liquid metal
const ALU_F0: vec3f   = vec3f(0.91, 0.92, 0.92);          // aluminium
const INK_DEEP: vec3f   = vec3f(0.0035, 0.006, 0.030);    // indigo
const INK_BRIGHT: vec3f = vec3f(0.010, 0.105, 0.200);     // bright cyan-blue

fn sd_rbox(q: vec2f, b: vec2f, r: f32) -> f32 {
    let dd = abs(q) - b + r;
    return length(max(dd, vec2f(0.0))) + min(max(dd.x, dd.y), 0.0) - r;
}

// What a mirror sees looking along R (unit, world: z up). `blur` (tan-angle units) softens
// the reflection for a surface that is less than a perfect mirror.
fn env(R: vec3f, blur: f32) -> vec3f {
    var col = WALL_COL;
    if (R.z > 0.02) {
        let tq = R.xy / R.z;
        var c = SKY_COL * (0.55 + 0.45 * R.z);
        // the beams between the panes
        let db = abs(fract(tq / PITCH) - 0.5) * PITCH;
        c *= smoothstep(BEAM_W - AA - blur, BEAM_W + AA + blur, min(db.x, db.y)) * mix(0.9, 0.3, saturate(blur * 60.0)) + mix(0.1, 0.7, saturate(blur * 60.0));
        // the lights
        let k = round_away(tq / PITCH);
        if (abs(k.x) <= 3.0 && abs(k.y) <= 1.0) {
            let sd = sd_rbox(tq - k * PITCH, LAMP, 0.008);
            let spread = (LAMP.x * LAMP.y) / ((LAMP.x + blur) * (LAMP.y + blur));   // same power, larger patch
            c += LAMP_COL * spread * smoothstep(AA + blur, -AA - blur, sd);
            c += LAMP_COL * 0.012 * exp(-max(sd, 0.0) / (0.018 + blur));   // the diffuser's glow
        }
        col = mix(WALL_COL, c, smoothstep(0.02, 0.12, R.z));
    }
    return col;
}

fn schlick(F0: vec3f, c: f32) -> vec3f {
    let m = pow(1.0 - saturate(c), 5.0);
    return F0 + (1.0 - F0) * m;
}

// Brushed aluminium at world point P, normal n, grain T. The highlight streaks come from
// the lights nearest across the grain: along a bar brushed in x, the 7 columns of the
// nearest row; along a bar brushed in y, the 3 rows of the nearest column.
fn brushed(P: vec3f, n: vec3f, T: vec3f, along_x: bool, grain: f32, V: vec3f) -> vec3f {
    var spec = 0.0;
    let lp = PITCH * CEIL_H;
    if (along_x) {
        let ly = clamp(round_away1(P.y / lp.y), -1.0, 1.0) * lp.y;
        for (var i = -3; i <= 3; i++) {
            let Lc = normalize(vec3f(f32(i) * lp.x, ly, CEIL_H) - P);
            let Hc = normalize(Lc + V);
            let th = dot(T, Hc);
            spec += pow(sqrt(saturate(1.0 - th * th)), 160.0) * saturate(dot(n, Hc) * 4.0);
        }
    } else {
        let lx = clamp(round_away1(P.x / lp.x), -3.0, 3.0) * lp.x;
        for (var j = -1; j <= 1; j++) {
            let Lc = normalize(vec3f(lx, f32(j) * lp.y, CEIL_H) - P);
            let Hc = normalize(Lc + V);
            let th = dot(T, Hc);
            spec += pow(sqrt(saturate(1.0 - th * th)), 160.0) * saturate(dot(n, Hc) * 4.0);
        }
    }
    let F = schlick(ALU_F0, saturate(dot(n, V)));
    let up = saturate(n.z);
    let amb = vec3f(0.040, 0.043, 0.048) * (0.35 + 0.65 * up);   // the bright ceiling, blurred
    return F * (amb * (0.8 + 0.4 * grain) + vec3f(1.0, 0.975, 0.94) * spec * 0.05 * (0.4 + 1.2 * grain));
}

// The grain: fine streaks along `along`, varying across it.
fn grain_at(along: f32, across: f32, salt: f32) -> f32 {
    return saturate(0.5 + 0.32 * argus_noise(vec2f(across * 1100.0 + salt, along * 2.0))
                        + 0.18 * argus_noise(vec2f(across * 2600.0, along * 6.0 + salt))
                        + 0.14 * argus_noise(vec2f(across * 240.0 + salt, along * 0.7)));
}

// The state at bath point p (Metal: a lambda in argus_draw, sampling with filter::linear,
// address::clamp_to_edge).
fn st_at(p: vec2f, B: vec2f, vscale: f32, vmax: f32) -> vec4f {
    return argus_sample(argus_state, argus_linear_clamp, vec2f((p.x / B.x + 1.0) * 0.5, min((1.0 - p.y / B.y) * 0.5 * vscale, vmax)));
}
// The metal's height (Metal: a lambda in argus_draw).
fn ht(m: f32) -> f32 { return smoothstep(0.03, 0.97, m); }

@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    let B = bath_extent(f);
    let uv = argus_uv(gid, f);
    let hl = f.state_height - 1u;
    let vscale = f32(hl) / f32(f.state_height);
    let vmax = (f32(hl) - 0.5) / f32(f.state_height);
    let KEY = normalize(vec3f(0.0, 0.0, 1.0));

    let d = normalize(vec3f(uv, -FC));
    let V = -d;

    let Pl = uv * (ZC / FC);                 // where the ray meets the bath plane
    let Pt = uv * ((ZC - RIM_H) / FC);       // ... and the frame's top face
    let ot = abs(Pt) - B;                    // > 0: on the frame's top
    var col: vec3f;

    if (max(ot.x, ot.y) > 0.0) {
        // ------------------------------------------------------ the frame's top --
        // four solid bars, mitred at the corners, each brushed along its length
        let vbar = ot.x > ot.y;
        let outward = select(vec2f(0.0, sign(Pt.y)), vec2f(sign(Pt.x), 0.0), vbar);
        let o = max(ot.x, ot.y);
        let along = select(Pt.x, Pt.y, vbar); let across = select(Pt.y, Pt.x, vbar);
        let T = select(vec3f(1.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0), vbar);
        let gr = grain_at(along, across, select(0.0, 37.0, vbar));
        // the inner edge is rounded over into the bath
        let e = saturate(1.0 - o / CHAMF);
        let tilt = 1.25 * e * e;
        let n = normalize(vec3f(-outward * sin(tilt), cos(tilt)));
        col = brushed(vec3f(Pt, RIM_H), n, T, !vbar, gr, V);
        // the rounded edge also mirrors the room a little
        col += e * 0.12 * schlick(ALU_F0, saturate(dot(n, V))) * env(reflect(d, n), 0.0);
        // the mitre seams where the bars meet
        if (ot.x > 0.0 && ot.y > 0.0) { col *= mix(1.0, 0.3, smoothstep(0.0022, 0.0006, abs(ot.x - ot.y))); }
    } else if (abs(Pl.x) < B.x && abs(Pl.y) < B.y) {
        // ---------------------------------------------------------- the liquid --
        let P = Pl;
        let s = st_at(P, B, vscale, vmax);
        let tx = vec2f(2.0 * B.x / f32(f.state_width), 2.0 * B.y / f32(hl)) * 1.5;
        let sr = st_at(P + vec2f(tx.x, 0.0), B, vscale, vmax); let sl = st_at(P - vec2f(tx.x, 0.0), B, vscale, vmax);
        let su = st_at(P + vec2f(0.0, tx.y), B, vscale, vmax); let sd = st_at(P - vec2f(0.0, tx.y), B, vscale, vmax);
        // the metal stands proud of the ink, with rounded edges
        let hm = 0.010;
        // (its height saturates just short of 0 and 1, so the half-float rounding of a resting
        // pool cannot ripple its mirror)
        let h0 = ht(s.x); let hr = ht(sr.x); let hl_ = ht(sl.x); let hu = ht(su.x); let hd = ht(sd.x);
        var grad = vec2f(hr - hl_, hu - hd) * hm / (2.0 * tx);
        // the meniscus: the liquid climbs the frame where it touches it
        let dwx = B.x - abs(P.x); let dwy = B.y - abs(P.y);
        grad += vec2f(sign(P.x) * exp(-dwx / 0.012), sign(P.y) * exp(-dwy / 0.012)) * 0.6;
        let n = normalize(vec3f(-grad, 1.0));
        let R = reflect(d, n);
        let ndv = saturate(dot(n, V));
        // The reflection's footprint: one pixel turns the normal by the surface's curvature
        // times the pixel size, the reflection by twice that, and the ceiling's tan-angle
        // coordinates by that over R.z^2. Filtering the room by it keeps the edges from grain.
        let kx = hr - 2.0 * h0 + hl_; let ky = hu - 2.0 * h0 + hd;
        let curv = hm * (abs(kx) / (tx.x * tx.x) + abs(ky) / (tx.y * tx.y))
                 + 50.0 * (exp(-dwx / 0.012) + exp(-dwy / 0.012));   // the meniscus's own bend
        let pix = 2.0 * (ZC / FC) / f32(f.height);
        let foot = 2.0 * curv * pix / max(R.z * R.z, 0.03);
        let wm = smoothstep(0.3, 0.7, s.x);
        var er = vec3f(0.0);
        if (wm > 0.0) { er = env(R, min(0.0015 + foot, 0.08)); }
        var eri = vec3f(0.0);
        if (wm < 1.0) { eri = env(R, 0.06 + foot); }   // the ink is glossy, not a mirror

        // ink: a glossy dielectric, lit from the bright ceiling above
        let body = mix(INK_DEEP, INK_BRIGHT, s.y * s.y);
        let lit = 0.25 + 0.75 * saturate(dot(n, KEY));
        let Fb = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
        let ci = body * lit * (1.0 - Fb) + Fb * eri;

        // the metal: a mirror
        let cm = schlick(METAL_F0, ndv) * er;

        col = mix(ci, cm, wm);
        // the frame's contact shadow
        col *= 0.5 + 0.5 * smoothstep(0.0, 0.10, min(dwx, dwy));
    } else {
        // ------------------------------------------- the frame's inner face --
        let zx = select(-1e9, ZC - B.x * FC / abs(uv.x), abs(uv.x) > 1e-5);
        let zy = select(-1e9, ZC - B.y * FC / abs(uv.y), abs(uv.y) > 1e-5);
        let vbar = zx > zy;
        let z = clamp(max(zx, zy), 0.0, RIM_H);
        let inward = select(vec2f(0.0, -sign(uv.y)), vec2f(-sign(uv.x), 0.0), vbar);
        let P3 = vec3f(uv * (ZC - z) / FC, z);
        let gr = grain_at(select(P3.x, P3.y, vbar), z * 3.0, 71.0);
        col = brushed(P3, vec3f(inward, 0.0), vec3f(0.0, 0.0, 1.0), false, gr, V) * (0.35 + 0.65 * z / RIM_H);
    }

    col *= 1.0 - 0.12 * dot(uv / half_extent(f), uv / half_extent(f));
    col *= 1.5;
    textureStore(argus_out, gid, vec4f(argus_srgb(argus_aces(col)), 1.0));
}

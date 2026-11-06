// ============================================================================
// web/themes/Tutorial_Reef.wgsl — a wallpaper that remembers: GPU state
//
// A one-to-one WGSL translation of themes/Tutorial_Reef.metal.
// A Gray-Scott reaction-diffusion: two chemicals, A and B, spread across a grid
// and react (A + 2B -> 3B). From one simple local rule grow corals, spots and
// worms that never settle, because the reaction rates drift slowly over time.
//
// What's new compared with Tutorial_Tides:
//   - A STATE texture that persists between frames. Each pixel of it holds (A, B).
//   - argus_init  writes the first state once (textureStore into argus_state_out).
//   - argus_step  reads the previous state (textureLoad from argus_state) and writes
//                 the next one (textureStore into argus_state_out). The host swaps the
//                 two textures after every step: "ping-pong". A kernel can't safely read
//                 and write one texture, because neighbours are being updated at the
//                 same time.
//   - argus_draw  gets the current state as argus_state and turns it into colour.
//
// The directives below set the state size (smaller than the screen: cheaper, and
// the draw smooths it back up) and how many simulation steps run per frame.
//
// @argus state 960x600
// @argus steps 12
// ============================================================================

// Reaction rates vary across the screen and drift with time, so different regions
// grow different patterns and the whole reef keeps changing. They vary with sin/cos
// of the position so they wrap around the grid's edges without a seam.
fn rates(uv01: vec2f, t: f32) -> vec2f {
    let tau = 6.2831853;
    let fy = 0.5 + 0.5 * sin(tau * uv01.y + t * 0.02);
    let kx = 0.5 + 0.5 * cos(tau * uv01.x - t * 0.015);
    let feed = mix(0.026, 0.046, fy);
    let kill = mix(0.057, 0.064, kx);
    return vec2f(feed, kill);
}

@compute @workgroup_size(8, 8)
fn argus_init(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.state_width || gid.y >= f.state_height) { return; }
    // Everywhere: all A, no B. Then scatter small seeds of B (different every load).
    let blob = gid / 12u;
    let seed = argus_rand(blob, f.seed) > 0.985;
    textureStore(argus_state_out, gid, vec4f(1.0, select(0.0, 1.0, seed), 0.0, 0.0));
}

// Read a neighbour, wrapping around the edges (the grid is a torus: no borders).
fn at(gid: vec2u, w: u32, h: u32, dx: i32, dy: i32) -> vec2f {
    return textureLoad(argus_state, vec2u(u32((i32(gid.x) + dx + i32(w)) % i32(w)), u32((i32(gid.y) + dy + i32(h)) % i32(h))), 0).xy;
}

@compute @workgroup_size(8, 8)
fn argus_step(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    let w = f.state_width;
    let h = f.state_height;
    if (gid.x >= w || gid.y >= h) { return; }

    let c = at(gid, w, h, 0, 0);
    // Laplacian: how much this cell differs from its neighbours (drives diffusion).
    let lap = 0.2 * (at(gid, w, h, 1, 0) + at(gid, w, h, -1, 0) + at(gid, w, h, 0, 1) + at(gid, w, h, 0, -1))
            + 0.05 * (at(gid, w, h, 1, 1) + at(gid, w, h, -1, 1) + at(gid, w, h, 1, -1) + at(gid, w, h, -1, -1)) - c;
    let fk = rates(argus_uv01(gid, w, h), f.time);
    let a = c.x;
    let b = c.y;
    let react = a * b * b;
    var n = vec2f(a + 1.0 * lap.x - react + fk.x * (1.0 - a),
                  b + 0.5 * lap.y + react - (fk.x + fk.y) * b);

    // Keep it alive: now and then a new seed lands somewhere.
    let tick = f.frame / 90u;
    let drop = vec2u(argus_hash(tick * 2u + f.seed) % w, argus_hash(tick * 2u + 1u + f.seed) % h);
    if (length(vec2f(gid) - vec2f(drop)) < 4.0) { n.y = 1.0; }

    textureStore(argus_state_out, gid, vec4f(saturate(n), 0.0, 0.0));
}

@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    if (gid.x >= f.width || gid.y >= f.height) { return; }
    // Sampling with a linear filter smooths the 960x600 state up to 1920x1200
    // (Metal: constexpr sampler smooth(filter::linear, address::repeat)).
    let uv = argus_uv01(gid, f.width, f.height);
    let b = argus_sample(argus_state, argus_linear_repeat, uv).y;

    // Light it like an embossed relief: the slope of B against a light from the top left.
    let px = 1.0 / vec2f(f32(f.state_width), f32(f.state_height));
    let slope = argus_sample(argus_state, argus_linear_repeat, uv - px).y - argus_sample(argus_state, argus_linear_repeat, uv + px).y;

    let deep = vec3f(0.01, 0.03, 0.07);
    let coral = argus_palette(b * 0.9 + 0.05 * sin(f.time * 0.05),
                              vec3f(0.55, 0.35, 0.40), vec3f(0.45, 0.35, 0.30),
                              vec3f(1.0, 1.0, 1.0), vec3f(0.0, 0.15, 0.25));
    var col = mix(deep, coral, smoothstep(0.05, 0.35, b));
    col += vec3f(1.0, 0.9, 0.8) * max(slope, 0.0) * 2.5;     // lit edges
    col *= 1.0 - 0.35 * length(argus_uv(gid, f)) * 0.5;      // gentle vignette
    textureStore(argus_out, gid, vec4f(saturate(col), 1.0));
}

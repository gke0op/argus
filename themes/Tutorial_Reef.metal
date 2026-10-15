// ============================================================================
// themes/Tutorial_Reef.metal — a wallpaper that remembers: GPU state
//
// A Gray-Scott reaction-diffusion: two chemicals, A and B, spread across a grid
// and react (A + 2B -> 3B). From one simple local rule grow corals, spots and
// worms that never settle, because the reaction rates drift slowly over time.
//
// What's new compared with Tutorial_Tides:
//   - A STATE texture that persists between frames. Each pixel of it holds (A, B).
//   - argus_init  writes the first state once.
//   - argus_step  reads the previous state (texture 0) and writes the next one
//                 (texture 1). Argus swaps the two textures after every step:
//                 "ping-pong". A kernel can't safely read and write one texture,
//                 because neighbours are being updated at the same time.
//   - argus_draw  gets the current state as texture 1 and turns it into colour.
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
static float2 rates(float2 uv01, float t) {
    const float tau = 6.2831853f;
    const float fy = 0.5f + 0.5f * sin(tau * uv01.y + t * 0.02f);
    const float kx = 0.5f + 0.5f * cos(tau * uv01.x - t * 0.015f);
    const float feed = mix(0.026f, 0.046f, fy);
    const float kill = mix(0.057f, 0.064f, kx);
    return float2(feed, kill);
}

kernel void argus_init(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> state [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.state_width || gid.y >= f.state_height) return;
    // Everywhere: all A, no B. Then scatter small seeds of B (different every load).
    const uint2 blob = gid / 12u;
    const bool seed = argus_rand(blob, f.seed) > 0.985f;
    state.write(float4(1.0f, seed ? 1.0f : 0.0f, 0.0f, 0.0f), gid);
}

kernel void argus_step(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::read> prev [[texture(0)]],
                       texture2d<float, access::write> next [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    const uint w = f.state_width, h = f.state_height;
    if (gid.x >= w || gid.y >= h) return;

    // Read a neighbour, wrapping around the edges (the grid is a torus: no borders).
    auto at = [&](int dx, int dy) {
        return prev.read(uint2((int(gid.x) + dx + int(w)) % int(w), (int(gid.y) + dy + int(h)) % int(h))).xy;
    };
    const float2 c = at(0, 0);
    // Laplacian: how much this cell differs from its neighbours (drives diffusion).
    const float2 lap = 0.2f * (at(1, 0) + at(-1, 0) + at(0, 1) + at(0, -1))
                     + 0.05f * (at(1, 1) + at(-1, 1) + at(1, -1) + at(-1, -1)) - c;
    const float2 fk = rates(argus_uv01(gid, w, h), f.time);
    const float a = c.x, b = c.y;
    const float react = a * b * b;
    float2 n = float2(a + 1.0f * lap.x - react + fk.x * (1.0f - a),
                      b + 0.5f * lap.y + react - (fk.x + fk.y) * b);

    // Keep it alive: now and then a new seed lands somewhere.
    const uint tick = f.frame / 90u;
    const uint2 drop = uint2(argus_hash(tick * 2u + f.seed) % w, argus_hash(tick * 2u + 1u + f.seed) % h);
    if (length(float2(gid) - float2(drop)) < 4.0f) n.y = 1.0f;

    next.write(float4(saturate(n), 0.0f, 0.0f), gid);
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       texture2d<float> state [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= f.width || gid.y >= f.height) return;
    // Sampling with a linear filter smooths the 960x600 state up to 1920x1200.
    constexpr sampler smooth(filter::linear, address::repeat);
    const float2 uv = argus_uv01(gid, f.width, f.height);
    const float b = state.sample(smooth, uv).y;

    // Light it like an embossed relief: the slope of B against a light from the top left.
    const float2 px = 1.0f / float2(f.state_width, f.state_height);
    const float slope = state.sample(smooth, uv - px).y - state.sample(smooth, uv + px).y;

    const float3 deep = float3(0.01f, 0.03f, 0.07f);
    const float3 coral = argus_palette(b * 0.9f + 0.05f * sin(f.time * 0.05f),
                                       float3(0.55f, 0.35f, 0.40f), float3(0.45f, 0.35f, 0.30f),
                                       float3(1.0f, 1.0f, 1.0f), float3(0.0f, 0.15f, 0.25f));
    float3 col = mix(deep, coral, smoothstep(0.05f, 0.35f, b));
    col += float3(1.0f, 0.9f, 0.8f) * max(slope, 0.0f) * 2.5f;     // lit edges
    col *= 1.0f - 0.35f * length(argus_uv(gid, f)) * 0.5f;          // gentle vignette
    out.write(float4(saturate(col), 1.0f), gid);
}

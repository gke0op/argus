// ============================================================================
// themes/Tutorial_Tides.metal — your first Argus Metal wallpaper
//
// An aurora over a night sea, built up in five small steps. Every Argus Metal
// theme is a `kernel` the GPU runs once per pixel, all pixels at the same time:
// you never loop over the screen, you only answer "what colour is MY pixel?".
//
// Try it:   make harness THEME=themes/Tutorial_Tides.metal   (renders a PNG)
//           drop this file onto a Space in the Argus menu, then edit and save:
//           Argus hot-reloads it within a second.
//
// Things you get for free (src/gpu/argus_prelude.metal):
//   ArgusFrame f   f.time (seconds), f.width/f.height, f.frame, f.seed
//   argus_uv       pixel -> centred coords, y up, short side spans -1..1
//   argus_noise / argus_fbm / argus_palette / argus_srgb / argus_aces
// ============================================================================

// A star field: one candidate star per grid cell, twinkling at its own rate.
static float stars(float2 p, float t) {
    const float2 cell = floor(p * 90.0f);
    const float2 local = fract(p * 90.0f) - 0.5f;
    const float r = argus_rand(uint2(int2(cell) + 4096), 7u);
    if (r < 0.92f) return 0.0f;                                   // most cells are empty
    const float twinkle = 0.6f + 0.4f * sin(t * (1.0f + 3.0f * r) + r * 40.0f);
    return twinkle * smoothstep(0.12f, 0.0f, length(local));      // a soft dot in the cell
}

// The aurora curtain's brightness at sky point p: a wavy band, warped by noise.
static float aurora(float2 p, float t) {
    // STEP 3 — domain warping: bend the coordinates with noise before using them.
    const float warp = argus_fbm(float2(p.x * 1.5f, t * 0.05f), 4);
    const float y = p.y - 0.35f - 0.25f * warp - 0.08f * sin(p.x * 2.0f + t * 0.3f);
    // A band around y == 0 that fades upward slowly and downward fast.
    const float band = exp(-max(y, 0.0f) * 4.0f) * smoothstep(-0.05f, 0.02f, y);
    // STEP 4 — fine vertical rays drifting sideways.
    const float rays = 0.55f + 0.45f * argus_noise(float2(p.x * 22.0f + t * 0.4f, t * 0.2f));
    return band * rays;
}

static float3 sky(float2 p, float t) {
    // STEP 1 — a vertical gradient: deep blue overhead, lighter at the horizon.
    float3 col = mix(float3(0.02f, 0.04f, 0.10f), float3(0.00f, 0.01f, 0.03f), saturate(p.y));
    col += stars(p, t) * float3(0.9f, 0.95f, 1.0f);
    // STEP 5 — colour from a cosine palette: green at the base, violet at the top.
    const float a = aurora(p, t);
    const float3 tint = argus_palette(saturate(p.y) * 0.8f + 0.1f * sin(t * 0.1f),
                                      float3(0.5f), float3(0.5f), float3(1.0f), float3(0.30f, 0.20f, 0.20f));
    col += a * mix(float3(0.1f, 1.0f, 0.5f), tint, 0.45f) * 1.4f;
    return col;
}

kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
                       texture2d<float, access::write> out [[texture(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    // The grid can be a little larger than the screen; skip threads past the edge.
    if (gid.x >= f.width || gid.y >= f.height) return;

    // STEP 2 — coordinates: (0,0) mid-screen, y up. The horizon sits a bit below centre.
    const float2 uv = argus_uv(gid, f);
    const float horizon = -0.25f;
    const float t = f.time;

    float3 col;
    if (uv.y > horizon) {
        col = sky(float2(uv.x, uv.y - horizon), t);
    } else {
        // The sea mirrors the sky, rippled: reflect the point and nudge it with moving noise.
        const float depth = horizon - uv.y;
        const float2 ripple = float2(argus_noise(float2(uv.x * 6.0f, depth * 40.0f / (depth + 0.05f) - t * 0.8f)),
                                     argus_noise(float2(uv.x * 3.0f + 9.0f, depth * 25.0f - t * 0.5f))) * 0.04f;
        const float2 mirrored = float2(uv.x, depth) + ripple * (0.3f + depth * 3.0f);
        col = sky(mirrored, t) * (0.55f - 0.35f * saturate(depth * 1.6f));
        col += float3(0.0f, 0.01f, 0.02f);
    }

    // Kernels write display values in 0..1; the alpha is ignored (wallpapers are opaque).
    out.write(float4(saturate(col), 1.0f), gid);
}

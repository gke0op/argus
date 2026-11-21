// ============================================================================
// web/themes/Tutorial_Tides.wgsl — your first Argus wallpaper, in the browser
//
// A one-to-one WGSL translation of themes/Tutorial_Tides.metal (same steps, same numbers).
// An aurora over a night sea, built up in five small steps. Every Argus theme is a
// compute kernel the GPU runs once per pixel, all pixels at the same time: you never loop
// over the screen, you only answer "what colour is MY pixel?".
//
// Try it:   open web/index.html (served over http://localhost) and pick Tutorial_Tides.
//
// Things you get for free (web/prelude.wgsl, the twin of src/gpu/argus_prelude.metal):
//   f              f.time (seconds), f.width/f.height, f.frame, f.seed
//   argus_uv       pixel -> centred coords, y up, short side spans -1..1
//   argus_noise / argus_fbm / argus_palette / argus_srgb / argus_aces
// ============================================================================

// A star field: one candidate star per grid cell, twinkling at its own rate.
fn stars(p: vec2f, t: f32) -> f32 {
    let cell = floor(p * 90.0);
    let local = fract(p * 90.0) - 0.5;
    let r = argus_rand(vec2u(vec2i(cell) + 4096), 7u);
    if (r < 0.92) { return 0.0; }                                  // most cells are empty
    let twinkle = 0.6 + 0.4 * sin(t * (1.0 + 3.0 * r) + r * 40.0);
    return twinkle * smoothstep(0.12, 0.0, length(local));         // a soft dot in the cell
}

// The aurora curtain's brightness at sky point p: a wavy band, warped by noise.
fn aurora(p: vec2f, t: f32) -> f32 {
    // STEP 3 — domain warping: bend the coordinates with noise before using them.
    let warp = argus_fbm(vec2f(p.x * 1.5, t * 0.05), 4);
    let y = p.y - 0.35 - 0.25 * warp - 0.08 * sin(p.x * 2.0 + t * 0.3);
    // A band around y == 0 that fades upward slowly and downward fast.
    let band = exp(-max(y, 0.0) * 4.0) * smoothstep(-0.05, 0.02, y);
    // STEP 4 — fine vertical rays drifting sideways.
    let rays = 0.55 + 0.45 * argus_noise(vec2f(p.x * 22.0 + t * 0.4, t * 0.2));
    return band * rays;
}

fn sky(p: vec2f, t: f32) -> vec3f {
    // STEP 1 — a vertical gradient: deep blue overhead, lighter at the horizon.
    var col = mix(vec3f(0.02, 0.04, 0.10), vec3f(0.00, 0.01, 0.03), saturate(p.y));
    col += stars(p, t) * vec3f(0.9, 0.95, 1.0);
    // STEP 5 — colour from a cosine palette: green at the base, violet at the top.
    let a = aurora(p, t);
    let tint = argus_palette(saturate(p.y) * 0.8 + 0.1 * sin(t * 0.1),
                             vec3f(0.5), vec3f(0.5), vec3f(1.0), vec3f(0.30, 0.20, 0.20));
    col += a * mix(vec3f(0.1, 1.0, 0.5), tint, 0.45) * 1.4;
    return col;
}

@compute @workgroup_size(8, 8)
fn argus_draw(@builtin(global_invocation_id) id: vec3u) {
    let gid = id.xy;
    // The grid can be a little larger than the screen; skip threads past the edge.
    if (gid.x >= f.width || gid.y >= f.height) { return; }

    // STEP 2 — coordinates: (0,0) mid-screen, y up. The horizon sits a bit below centre.
    let uv = argus_uv(gid, f);
    let horizon = -0.25;
    let t = f.time;

    var col: vec3f;
    if (uv.y > horizon) {
        col = sky(vec2f(uv.x, uv.y - horizon), t);
    } else {
        // The sea mirrors the sky, rippled: reflect the point and nudge it with moving noise.
        let depth = horizon - uv.y;
        let ripple = vec2f(argus_noise(vec2f(uv.x * 6.0, depth * 40.0 / (depth + 0.05) - t * 0.8)),
                           argus_noise(vec2f(uv.x * 3.0 + 9.0, depth * 25.0 - t * 0.5))) * 0.04;
        let mirrored = vec2f(uv.x, depth) + ripple * (0.3 + depth * 3.0);
        col = sky(mirrored, t) * (0.55 - 0.35 * saturate(depth * 1.6));
        col += vec3f(0.0, 0.01, 0.02);
    }

    // Kernels write display values in 0..1; the alpha is ignored (wallpapers are opaque).
    textureStore(argus_out, gid, vec4f(saturate(col), 1.0));
}

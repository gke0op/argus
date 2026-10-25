// ============================================================================
// themes/cpu/Tutorial_Tides.zig — CPU port of themes/Tutorial_Tides.metal
//
// An aurora over a night sea, shaded N pixels per call by argus_kernel.zig. Same functions,
// constants and steps as the Metal original; the only change is the GPU's own trick made
// explicit: sky and sea pixels are both shaded by one sky() call, the sea at a mirrored point.
// ============================================================================

const k = @import("argus_kernel.zig");
const F = k.F;
const V2 = k.V2;
const V3 = k.V3;
const f = k.f;
const v3 = k.v3;

comptime {
    k.exportKernelTheme(@This());
}

// A star field: one candidate star per grid cell, twinkling at its own rate.
fn stars(p: V2, t: F) F {
    const q = p.scale(f(90));
    const local = q.fract().sub(k.v2(0.5, 0.5));
    const r = k.rand(k.cell(q.floor(), 4096), 7);
    const twinkle = f(0.6) + f(0.4) * k.sin(t * (f(1) + f(3) * r) + r * f(40));
    return k.sel(r < f(0.92), f(0), twinkle * k.smoothstep(0.12, 0.0, local.length())); // most cells are empty
}

// The aurora curtain's brightness at sky point p: a wavy band, warped by noise.
fn aurora(p: V2, t: F) F {
    const warp = k.fbm(.{ .x = p.x * f(1.5), .y = t * f(0.05) }, 4);
    const y = p.y - f(0.35) - f(0.25) * warp - f(0.08) * k.sin(p.x * f(2) + t * f(0.3));
    const band = k.exp(-@max(y, f(0)) * f(4)) * k.smoothstep(-0.05, 0.02, y);
    const rays = f(0.55) + f(0.45) * k.noise(.{ .x = p.x * f(22) + t * f(0.4), .y = t * f(0.2) });
    return band * rays;
}

fn sky(p: V2, t: F) V3 {
    const col = V3.mix(v3(0.02, 0.04, 0.10), v3(0.00, 0.01, 0.03), k.saturate(p.y))
        .add(v3(0.9, 0.95, 1.0).scale(stars(p, t)));
    const tint = k.palette(k.saturate(p.y) * f(0.8) + f(0.1) * k.sin(t * f(0.1)), v3(0.5, 0.5, 0.5), v3(0.5, 0.5, 0.5), v3(1, 1, 1), v3(0.30, 0.20, 0.20));
    return col.add(V3.mix(v3(0.1, 1.0, 0.5), tint, f(0.45)).scale(aurora(p, t) * f(1.4)));
}

pub fn draw(fr: *const k.Frame, gid: k.Gid) V3 {
    const uv = k.uv(gid, fr);
    const horizon = f(-0.25);
    const t = f(fr.time);
    const is_sky = uv.y > horizon;

    // The sea mirrors the sky, rippled. depth is clamped at 0 so sky lanes stay finite.
    const depth = @max(horizon - uv.y, f(0));
    const ripple = (V2{
        .x = k.noise(.{ .x = uv.x * f(6), .y = depth * f(40) / (depth + f(0.05)) - t * f(0.8) }),
        .y = k.noise(.{ .x = uv.x * f(3) + f(9), .y = depth * f(25) - t * f(0.5) }),
    }).scale(f(0.04));
    const mirrored = (V2{ .x = uv.x, .y = depth }).add(ripple.scale(f(0.3) + depth * f(3)));

    const col = sky(V2.select(is_sky, .{ .x = uv.x, .y = uv.y - horizon }, mirrored), t);
    const sea = col.scale(f(0.55) - f(0.35) * k.saturate(depth * f(1.6))).add(v3(0.0, 0.01, 0.02));
    return V3.select(is_sky, col, sea).saturate();
}

// ============================================================================
// themes/cpu/Tutorial_Tides.zig — CPU port of themes/Tutorial_Tides.metal
//
// Line for line with the Metal original (same structure, same constants), run by
// argus_kernel.zig: an aurora over a night sea, now on any CPU (Linux, a VM, no GPU).
// ============================================================================

const k = @import("argus_kernel.zig");
const F2 = k.F2;
const F3 = k.F3;
const f2 = k.f2;
const f3 = k.f3;
const s3 = k.s3;

comptime {
    k.exportKernelTheme(@This());
}

fn stars(p: F2, t: f32) f32 {
    const cell = @floor(p * k.s2(90.0));
    const local = k.fract(p * k.s2(90.0)) - k.s2(0.5);
    const r = k.argus_rand(k.cellOf(cell, 4096), 7);
    if (r < 0.92) return 0.0;
    const twinkle = 0.6 + 0.4 * @sin(t * (1.0 + 3.0 * r) + r * 40.0);
    return twinkle * k.smoothstep(0.12, 0.0, k.length(local));
}

fn aurora(p: F2, t: f32) f32 {
    const warp = k.argus_fbm(f2(p[0] * 1.5, t * 0.05), 4);
    const y = p[1] - 0.35 - 0.25 * warp - 0.08 * @sin(p[0] * 2.0 + t * 0.3);
    const band = @exp(-@max(y, 0.0) * 4.0) * k.smoothstep(-0.05, 0.02, y);
    const rays = 0.55 + 0.45 * k.argus_noise(f2(p[0] * 22.0 + t * 0.4, t * 0.2));
    return band * rays;
}

fn sky(p: F2, t: f32) F3 {
    var col = k.mix(f3(0.02, 0.04, 0.10), f3(0.00, 0.01, 0.03), s3(k.saturate(p[1])));
    col += s3(stars(p, t)) * f3(0.9, 0.95, 1.0);
    const a = aurora(p, t);
    const tint = k.argus_palette(k.saturate(p[1]) * 0.8 + 0.1 * @sin(t * 0.1), s3(0.5), s3(0.5), s3(1.0), f3(0.30, 0.20, 0.20));
    col += s3(a) * k.mix(f3(0.1, 1.0, 0.5), tint, s3(0.45)) * s3(1.4);
    return col;
}

pub fn draw(f: *const k.Frame, gid: [2]u32) k.F4 {
    const uv = k.argus_uv(gid, f);
    const horizon: f32 = -0.25;
    const t = f.time;

    var col: F3 = undefined;
    if (uv[1] > horizon) {
        col = sky(f2(uv[0], uv[1] - horizon), t);
    } else {
        const depth = horizon - uv[1];
        const ripple = f2(
            k.argus_noise(f2(uv[0] * 6.0, depth * 40.0 / (depth + 0.05) - t * 0.8)),
            k.argus_noise(f2(uv[0] * 3.0 + 9.0, depth * 25.0 - t * 0.5)),
        ) * k.s2(0.04);
        const mirrored = f2(uv[0], depth) + ripple * k.s2(0.3 + depth * 3.0);
        col = sky(mirrored, t) * s3(0.55 - 0.35 * k.saturate(depth * 1.6));
        col += f3(0.0, 0.01, 0.02);
    }
    const c = k.saturate(col);
    return .{ c[0], c[1], c[2], 1.0 };
}

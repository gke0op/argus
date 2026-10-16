// ============================================================================
// ARGUS TEST FIXTURE // tests/fixtures/Fixture_Stateless.zig
//
// Test-only theme (never shipped): the stateless C ABI, `argus_render_theme`. Every pixel is a
// pure function of (x, y, phase), so two loads render identical frames, and every pixel is lit.
// ============================================================================

export fn argus_render_theme(pixels: [*]u32, width: u32, height: u32, phase: f64, step_count: u64) callconv(.c) void {
    _ = step_count;
    const w: usize = width;
    const h: usize = height;
    const shift: usize = @intFromFloat(@mod(phase, 1.0) * 255.0);
    for (0..h) |y| {
        const g: u32 = @intCast(y * 255 / @max(h, 1));
        for (0..w) |x| {
            const r: u32 = @intCast((x * 255 / @max(w, 1) + shift) % 256);
            pixels[y * w + x] = 0xFF00_0000 | (0x60 << 16) | (g << 8) | r; // 0xFF_BB_GG_RR
        }
    }
}

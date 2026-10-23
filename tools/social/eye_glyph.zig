// ============================================================================
// ARGUS // tools/social/eye_glyph.zig
//
// Writes the menu-bar eye glyph as an 8-bit alpha PGM on stdout, drawn by the app's own
// rasteriser (src/desktop/status_glyph.zig): N Spaces, the iris on Space CUR (0-based), PX pixels.
//
//   zig run -O ReleaseFast --dep status_glyph -Mroot=tools/social/eye_glyph.zig \
//     -Mstatus_glyph=src/desktop/status_glyph.zig -- 32 4 0 > eye.pgm
// ============================================================================

const std = @import("std");
const glyph = @import("status_glyph");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.UsageEyeGlyphPxSpacesCurrent;
    const px = try std.fmt.parseInt(usize, args[1], 10);
    const n = try std.fmt.parseInt(usize, args[2], 10);
    const cur = try std.fmt.parseInt(usize, args[3], 10);
    if (px == 0 or px > glyph.MAX_PX) return error.PxOutOfRange;
    var alpha: [glyph.MAX_PX * glyph.MAX_PX]u8 = undefined;
    glyph.render(&alpha, px, n, cur, false);
    var head: [32]u8 = undefined;
    const h = try std.fmt.bufPrint(&head, "P5\n{d} {d}\n255\n", .{ px, px });
    for ([_][]const u8{ h, alpha[0 .. px * px] }) |bytes| {
        var off: usize = 0;
        while (off < bytes.len) {
            const w = std.c.write(1, bytes[off..].ptr, bytes.len - off);
            if (w <= 0) std.process.exit(2);
            off += @intCast(w);
        }
    }
}

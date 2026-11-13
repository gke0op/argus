//! tools/share.zig: a link that opens a Zig theme on the ARGUS-BENCH page, compiled, run and
//! graded in the browser, with nothing uploaded.
//!
//!   zig run tools/share.zig -- themes/My_Theme.zig [BASE_URL]      (or: make share THEME=...)
//!
//! Prints BASE_URL#zig=<source, raw deflate, base64url>&name=<file stem>. The source rides in the
//! URL fragment, which the browser never sends to the server; the bench page inflates it with
//! DecompressionStream('deflate-raw'). BASE_URL defaults to the public bench page.

const std = @import("std");
const flate = std.compress.flate;

pub const default_base = "https://gke0op.github.io/argus/bench/";

/// The share link for `source`, saved as `name`.zig, on the bench page at `base`.
pub fn link(gpa: std.mem.Allocator, base: []const u8, name: []const u8, source: []const u8) ![]u8 {
    const packed_bytes = try deflateRaw(gpa, source);
    defer gpa.free(packed_bytes);
    const enc = std.base64.url_safe_no_pad.Encoder;
    const b64 = try gpa.alloc(u8, enc.calcSize(packed_bytes.len));
    defer gpa.free(b64);
    _ = enc.encode(b64, packed_bytes);
    return std.fmt.allocPrint(gpa, "{s}#zig={s}&name={s}", .{ base, b64, name });
}

/// `bytes` as a raw deflate stream (no zlib or gzip header), at the best compression.
pub fn deflateRaw(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try out.ensureUnusedCapacity(64);
    const window = try gpa.alloc(u8, flate.max_window_len);
    defer gpa.free(window);
    var c = try flate.Compress.init(&out.writer, window, .raw, .best);
    try c.writer.writeAll(bytes);
    try c.finish();
    return out.toOwnedSlice();
}

/// A theme name the bench page accepts: the file's stem, with anything but [A-Za-z0-9_] as '_'.
pub fn themeName(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    const stem = std.fs.path.stem(path);
    const out = try gpa.dupe(u8, if (stem.len == 0) "Model_Theme" else stem);
    for (out) |*ch| {
        if (!std.ascii.isAlphanumeric(ch.*) and ch.* != '_') ch.* = '_';
    }
    return out;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        try std.Io.File.stderr().writeStreamingAll(io, "usage: share THEME.zig [BASE_URL]\n");
        std.process.exit(2);
    }
    const path = args[1];
    const base = if (args.len > 2) args[2] else default_base;
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited);
    const name = try themeName(arena, path);
    const url = try link(arena, base, name, source);
    try std.Io.File.stdout().writeStreamingAll(io, url);
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
}

fn inflateRaw(gpa: std.mem.Allocator, packed_bytes: []const u8) ![]u8 {
    var in: std.Io.Reader = .fixed(packed_bytes);
    const window = try gpa.alloc(u8, flate.max_window_len);
    defer gpa.free(window);
    var d: flate.Decompress = .init(&in, .raw, window);
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    _ = try d.reader.streamRemaining(&out.writer);
    return out.toOwnedSlice();
}

test "deflateRaw round-trips a theme-sized source" {
    const gpa = std.testing.allocator;
    var src: std.ArrayList(u8) = .empty;
    defer src.deinit(gpa);
    for (0..400) |i| try src.print(gpa, "const k{d}: f32 = {d}.0; // a line of a theme\n", .{ i, i * 7 });
    const z = try deflateRaw(gpa, src.items);
    defer gpa.free(z);
    try std.testing.expect(z.len < src.items.len / 3);
    const back = try inflateRaw(gpa, z);
    defer gpa.free(back);
    try std.testing.expectEqualStrings(src.items, back);
}

test "deflateRaw handles empty and tiny input" {
    const gpa = std.testing.allocator;
    for ([_][]const u8{ "", "x", "const std = @import(\"std\");" }) |s| {
        const z = try deflateRaw(gpa, s);
        defer gpa.free(z);
        const back = try inflateRaw(gpa, z);
        defer gpa.free(back);
        try std.testing.expectEqualStrings(s, back);
    }
}

test "link: base, base64url payload, name" {
    const gpa = std.testing.allocator;
    const url = try link(gpa, default_base, "My_Theme", "pub fn main() void {}\n");
    defer gpa.free(url);
    try std.testing.expect(std.mem.startsWith(u8, url, default_base ++ "#zig="));
    try std.testing.expect(std.mem.endsWith(u8, url, "&name=My_Theme"));
    const payload = url[(default_base ++ "#zig=").len..std.mem.find(u8, url, "&name=").?];
    for (payload) |ch| try std.testing.expect(std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_');
}

test "themeName keeps the stem and replaces other characters" {
    const gpa = std.testing.allocator;
    const a = try themeName(gpa, "themes/Claude Opus-Field.zig");
    defer gpa.free(a);
    try std.testing.expectEqualStrings("Claude_Opus_Field", a);
}

//! tools/share.zig: links that open a theme in the browser, with nothing uploaded: on the home
//! page, where it fills the screen, and on the ARGUS-BENCH page, where it is compiled, run and
//! graded.
//!
//!   zig run tools/share.zig -- themes/My_Theme.zig [SITE_URL]      (or: make share THEME=...)
//!
//! Prints two lines, SITE_URL#K=... (home) and SITE_URLbench/#K=... (bench), K being `zig` for a
//! .zig theme and `wgsl` for a .wgsl one, the source as raw deflate in base64url, then
//! &name=<file stem>. The source rides in the URL fragment, which the browser never sends to the
//! server; the pages inflate it with DecompressionStream('deflate-raw'). SITE_URL defaults to
//! the public site.

const std = @import("std");
const flate = std.compress.flate;

pub const default_site = "https://gke0op.github.io/argus/";
pub const default_base = default_site ++ "bench/";

/// `zig` or `wgsl`, from the file name (anything else is taken as Zig).
pub fn kindOf(path: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, path, ".wgsl")) "wgsl" else "zig";
}

/// The share link for `source` (a `kind` theme named `name`) on the page at `base`.
pub fn link(gpa: std.mem.Allocator, base: []const u8, kind: []const u8, name: []const u8, source: []const u8) ![]u8 {
    const packed_bytes = try deflateRaw(gpa, source);
    defer gpa.free(packed_bytes);
    const enc = std.base64.url_safe_no_pad.Encoder;
    const b64 = try gpa.alloc(u8, enc.calcSize(packed_bytes.len));
    defer gpa.free(b64);
    _ = enc.encode(b64, packed_bytes);
    return std.fmt.allocPrint(gpa, "{s}#{s}={s}&name={s}", .{ base, kind, b64, name });
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
        try std.Io.File.stderr().writeStreamingAll(io, "usage: share THEME.zig|THEME.wgsl [SITE_URL]\n");
        std.process.exit(2);
    }
    const path = args[1];
    const site = if (args.len > 2) args[2] else default_site;
    const source = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited);
    const name = try themeName(arena, path);
    const kind = kindOf(path);
    const home = try link(arena, site, kind, name, source);
    const bench = try link(arena, try std.fmt.allocPrint(arena, "{s}bench/", .{site}), kind, name, source);
    const out = try std.fmt.allocPrint(arena, "{s}\n{s}\n", .{ home, bench });
    try std.Io.File.stdout().writeStreamingAll(io, out);
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
    const url = try link(gpa, default_base, "zig", "My_Theme", "pub fn main() void {}\n");
    defer gpa.free(url);
    try std.testing.expect(std.mem.startsWith(u8, url, default_base ++ "#zig="));
    try std.testing.expect(std.mem.endsWith(u8, url, "&name=My_Theme"));
    const payload = url[(default_base ++ "#zig=").len..std.mem.find(u8, url, "&name=").?];
    for (payload) |ch| try std.testing.expect(std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_');
}

test "kindOf: .wgsl is WGSL, anything else Zig" {
    try std.testing.expectEqualStrings("wgsl", kindOf("web/themes/Reef.wgsl"));
    try std.testing.expectEqualStrings("zig", kindOf("themes/My.zig"));
    const gpa = std.testing.allocator;
    const url = try link(gpa, default_site, "wgsl", "Reef", "@compute @workgroup_size(8, 8) fn argus_draw() {}");
    defer gpa.free(url);
    try std.testing.expect(std.mem.startsWith(u8, url, default_site ++ "#wgsl="));
}

test "themeName keeps the stem and replaces other characters" {
    const gpa = std.testing.allocator;
    const a = try themeName(gpa, "themes/Claude Opus-Field.zig");
    defer gpa.free(a);
    try std.testing.expectEqualStrings("Claude_Opus_Field", a);
}

//! site/tools/community.zig: the home page's list of every merged theme, as JSON.
//!
//!   zig run site/tools/community.zig -- OUT.json MANIFEST.json THEME...
//!
//! THEME is a tracked `.zig` theme (themes/*.zig, bench/submissions/*.zig: built to wasm by
//! `make web-wasm-all`, listed only if MANIFEST.json says it compiled) or a `.wgsl` theme
//! (web/themes/*.wgsl, run by WebGPU). Each entry: { id, label, kind, build?, src, line }, the
//! line being the first sentence of the file's header comment. The home page adds the entries
//! whose id is not one of its own curated themes.

const std = @import("std");

pub const Entry = struct {
    id: []const u8,
    label: []const u8,
    kind: []const u8,
    build: ?[]const u8 = null,
    src: []const u8,
    line: []const u8,
};

const max_line = 160;

/// The first sentence of the header comment (`//!`, else leading `//` lines), at most 160
/// characters; "" if there is none. Skipped: rules (lines of only -, =, * or /), directives
/// (`@argus...`) and `Author:` lines; a leading file path (`themes/X.zig: `) is dropped.
pub fn caption(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var words: std.ArrayList(u8) = .empty;
    defer words.deinit(gpa);
    var it = std.mem.splitScalar(u8, text, '\n');
    var seen_comment = false;
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) {
            if (seen_comment and words.items.len > 0) break;
            continue;
        }
        if (!std.mem.startsWith(u8, line, "//")) break;
        seen_comment = true;
        var body = std.mem.trimStart(u8, line, "/!");
        body = std.mem.trim(u8, body, " \t");
        if (body.len == 0) {
            if (words.items.len > 0) break;
            continue;
        }
        if (std.mem.trim(u8, body, "-=*/ ").len == 0) continue;
        if (body[0] == '@' or std.mem.startsWith(u8, body, "Author:")) continue;
        body = dropPath(body);
        if (body.len == 0) continue;
        if (words.items.len > 0) try words.append(gpa, ' ');
        try words.appendSlice(gpa, body);
        if (std.mem.findScalar(u8, words.items, '.') != null or words.items.len >= max_line) break;
    }
    return firstSentence(gpa, words.items);
}

/// A `// @argus web off: <why>` line in the header: a theme that ships in the app but does not
/// run well in a browser yet (too heavy for one wasm thread, say) stays out of the site's picker.
pub fn webOff(text: []const u8) bool {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "//")) return false; // the header is over
        const body = std.mem.trim(u8, std.mem.trimStart(u8, line, "/!"), " \t");
        if (std.mem.startsWith(u8, body, "@argus web off")) return true;
    }
    return false;
}

/// "themes/X.zig: text" -> "text": a header that opens with its own path (no spaces before the
/// colon, a slash and a dot in it). Anything else is returned as it is.
fn dropPath(s: []const u8) []const u8 {
    const colon = std.mem.find(u8, s, ": ") orelse return s;
    const head = s[0..colon];
    if (std.mem.findScalar(u8, head, ' ') != null) return s;
    if (std.mem.findScalar(u8, head, '/') == null or std.mem.findScalar(u8, head, '.') == null) return s;
    return std.mem.trim(u8, s[colon + 2 ..], " \t");
}

fn firstSentence(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var end: usize = s.len;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '.' and (i + 1 == s.len or s[i + 1] == ' ')) {
            end = i + 1;
            break;
        }
    }
    if (end <= max_line) return gpa.dupe(u8, s[0..end]);
    var cut: usize = max_line - 1;
    while (cut > 0 and s[cut] != ' ') cut -= 1;
    if (cut == 0) cut = max_line - 1;
    return std.fmt.allocPrint(gpa, "{s}…", .{std.mem.trimEnd(u8, s[0..cut], " ,;:")});
}

/// "My_Theme" -> "My Theme".
pub fn labelOf(gpa: std.mem.Allocator, id: []const u8) ![]u8 {
    const out = try gpa.dupe(u8, id);
    for (out) |*ch| {
        if (ch.* == '_') ch.* = ' ';
    }
    return out;
}

const Built = struct { name: []const u8, compiled: bool };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) {
        try std.Io.File.stderr().writeStreamingAll(io, "usage: community OUT.json MANIFEST.json THEME...\n");
        std.process.exit(2);
    }
    const cwd = std.Io.Dir.cwd();
    const manifest_text = cwd.readFileAlloc(io, args[2], arena, .unlimited) catch "[]";
    const built = try std.json.parseFromSliceLeaky([]Built, arena, manifest_text, .{ .ignore_unknown_fields = true });

    var entries: std.ArrayList(Entry) = .empty;
    for (args[3..]) |path| {
        const ext = std.fs.path.extension(path);
        const id = std.fs.path.stem(path);
        const text = cwd.readFileAlloc(io, path, arena, .unlimited) catch continue;
        if (webOff(text)) continue; // the theme says it does not run well in a browser (yet)
        const line = try caption(arena, text);
        if (std.mem.eql(u8, ext, ".zig")) {
            const ok = for (built) |b| {
                if (std.mem.eql(u8, b.name, id)) break b.compiled;
            } else false;
            if (!ok) continue; // did not build to wasm: the PR's harness verdict says why
            try entries.append(arena, .{ .id = id, .label = try labelOf(arena, id), .kind = "wasm", .build = id, .src = path, .line = line });
        } else if (std.mem.eql(u8, ext, ".wgsl")) {
            // The source to link: the Metal theme it ports, when there is one.
            const metal = try std.fmt.allocPrint(arena, "themes/{s}.metal", .{id});
            const src = if (cwd.access(io, metal, .{})) |_| metal else |_| path;
            try entries.append(arena, .{ .id = id, .label = try labelOf(arena, id), .kind = "wgsl", .src = src, .line = line });
        }
    }
    const json = try std.fmt.allocPrint(arena, "{f}\n", .{std.json.fmt(entries.items, .{ .emit_null_optional_fields = false })});
    try cwd.writeFile(io, .{ .sub_path = args[1], .data = json });
}

test "caption: the first sentence of a //! header" {
    const gpa = std.testing.allocator;
    const c = try caption(gpa,
        \\//! Lorenz Ribbons: the Lorenz attractor drawn as glowing ribbons. Track B.
        \\//! More text.
        \\const std = @import("std");
    );
    defer gpa.free(c);
    try std.testing.expectEqualStrings("Lorenz Ribbons: the Lorenz attractor drawn as glowing ribbons.", c);
}

test "caption: // lines joined, rules skipped, stops at code" {
    const gpa = std.testing.allocator;
    const c = try caption(gpa,
        \\// ============================
        \\// A reef that remembers
        \\// between frames
        \\@compute @workgroup_size(8, 8)
    );
    defer gpa.free(c);
    try std.testing.expectEqualStrings("A reef that remembers between frames", c);
}

test "caption: none, and a long one is cut at a word" {
    const gpa = std.testing.allocator;
    const none = try caption(gpa, "const std = @import(\"std\");\n");
    defer gpa.free(none);
    try std.testing.expectEqualStrings("", none);
    var long: std.ArrayList(u8) = .empty;
    defer long.deinit(gpa);
    try long.appendSlice(gpa, "//! ");
    for (0..60) |_| try long.appendSlice(gpa, "word ");
    const c = try caption(gpa, long.items);
    defer gpa.free(c);
    try std.testing.expect(c.len <= max_line + 3);
    try std.testing.expect(std.mem.endsWith(u8, c, "…"));
}

test "labelOf" {
    const gpa = std.testing.allocator;
    const l = try labelOf(gpa, "Carbon_Erta_Ale");
    defer gpa.free(l);
    try std.testing.expectEqualStrings("Carbon Erta Ale", l);
}

test "caption: directives, Author: lines and a leading path are skipped" {
    const gpa = std.testing.allocator;
    const c = try caption(gpa,
        \\// @argus-theme: custom_shader
        \\// ============================================================================
        \\// themes/Reservoir_Field.zig: 64 echo state networks, one shared reservoir
        \\// Author: Claude (Anthropic), working in Claude Code, 2026-10-25.
        \\//
        \\// What you see: the live activations of a real echo state network.
        \\const std = @import("std");
    );
    defer gpa.free(c);
    try std.testing.expectEqualStrings("64 echo state networks, one shared reservoir", c);
    // A colon in prose is not a path.
    const p = try caption(gpa, "//! Night Tide: a coast at night. More.\n");
    defer gpa.free(p);
    try std.testing.expectEqualStrings("Night Tide: a coast at night.", p);
}

test "webOff: the header directive, and only in the header" {
    try std.testing.expect(webOff("// Reservoir\n// @argus web off: too heavy for one wasm thread\nconst x = 1;\n"));
    try std.testing.expect(!webOff("// Reservoir\nconst x = 1;\n// @argus web off: after the header\n"));
    try std.testing.expect(!webOff("//! A theme. @argus web off is mentioned, not declared.\n"));
}

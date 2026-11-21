//! site/tools/render.zig: fill the site's HTML templates from BENCHMARK.md, so the leaderboard
//! and the zero-shot prompt on the site are the document's own, never a hand copy.
//!
//!   zig run site/tools/render.zig -- BENCHMARK.md in.html out.html
//!
//! Placeholders in the template:
//!   <!-- @LEADERBOARD -->  the "Cross-model leaderboard" table, as an HTML <table>
//!   <!-- @PROMPT -->       the zero-shot prompt (the blockquote under "Zero-shot"), HTML-escaped
//! A placeholder whose source cannot be found is an error, so a reworded BENCHMARK.md fails the
//! build instead of shipping an empty table.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) {
        std.debug.print("usage: render BENCHMARK.md in.html out.html\n", .{});
        std.process.exit(2);
    }
    const cwd = std.Io.Dir.cwd();
    const md = try cwd.readFileAlloc(io, args[1], arena, .unlimited);
    const tpl = try cwd.readFileAlloc(io, args[2], arena, .unlimited);
    const out = try render(arena, md, tpl);
    try cwd.writeFile(io, .{ .sub_path = args[3], .data = out });
}

pub fn render(a: Allocator, md: []const u8, tpl: []const u8) ![]u8 {
    var out: []u8 = try a.dupe(u8, tpl);
    if (std.mem.find(u8, out, "<!-- @LEADERBOARD -->") != null) {
        const table = try leaderboard(a, md);
        out = try std.mem.replaceOwned(u8, a, out, "<!-- @LEADERBOARD -->", table);
    }
    if (std.mem.find(u8, out, "<!-- @PROMPT -->") != null) {
        const p = try escape(a, try prompt(md));
        out = try std.mem.replaceOwned(u8, a, out, "<!-- @PROMPT -->", p);
    }
    return out;
}

/// The zero-shot prompt: the first line after "### Zero-shot" that starts with `> *"`.
pub fn prompt(md: []const u8) ![]const u8 {
    const at = std.mem.find(u8, md, "### Zero-shot") orelse return error.NoZeroShotSection;
    var it = std.mem.splitScalar(u8, md[at..], '\n');
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "> *\"")) {
            const body = std.mem.trimEnd(u8, line[4..], " \r");
            if (!std.mem.endsWith(u8, body, "\"*")) return error.PromptNotClosed;
            return body[0 .. body.len - 2];
        }
    }
    return error.NoPrompt;
}

/// The "### Cross-model leaderboard" table: header row, separator, rows, as an HTML table.
pub fn leaderboard(a: Allocator, md: []const u8) ![]u8 {
    const at = std.mem.find(u8, md, "### Cross-model leaderboard") orelse return error.NoLeaderboardSection;
    var w: std.Io.Writer.Allocating = .init(a);
    const ww = &w.writer;
    try ww.writeAll("<table class=\"lb\" id=\"leaderboard\">\n");
    var it = std.mem.splitScalar(u8, md[at..], '\n');
    var row: usize = 0;
    var in_table = false;
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (!std.mem.startsWith(u8, line, "|")) {
            if (in_table) break;
            continue;
        }
        in_table = true;
        defer row += 1;
        if (row == 1) continue; // the | :--- | separator
        const tag = if (row == 0) "th" else "td";
        if (row == 0) try ww.writeAll("<thead>") else if (row == 2) try ww.writeAll("<tbody>\n");
        try ww.writeAll("<tr>");
        var cells = std.mem.splitScalar(u8, line[1 .. line.len - 1], '|');
        while (cells.next()) |cell| {
            if (row == 0) {
                try ww.print("<th scope=\"col\"><button type=\"button\">", .{});
                try inline_md(ww, std.mem.trim(u8, cell, " "));
                try ww.writeAll("</button></th>");
            } else {
                try ww.print("<{s}>", .{tag});
                try inline_md(ww, std.mem.trim(u8, cell, " "));
                try ww.print("</{s}>", .{tag});
            }
        }
        try ww.writeAll("</tr>");
        if (row == 0) try ww.writeAll("</thead>\n") else try ww.writeAll("\n");
    }
    if (row < 3) return error.LeaderboardEmpty;
    try ww.writeAll("</tbody>\n</table>");
    return w.toOwnedSlice();
}

/// The table's inline Markdown: `code`, \* (a literal asterisk), HTML-escaped text.
fn inline_md(w: *std.Io.Writer, s: []const u8) !void {
    var code = false;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const ch = s[i];
        if (ch == '\\' and i + 1 < s.len) {
            i += 1;
            try escapeByte(w, s[i]);
        } else if (ch == '`') {
            try w.writeAll(if (code) "</code>" else "<code>");
            code = !code;
        } else try escapeByte(w, ch);
    }
    if (code) try w.writeAll("</code>");
}

fn escapeByte(w: *std.Io.Writer, ch: u8) !void {
    switch (ch) {
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '&' => try w.writeAll("&amp;"),
        '"' => try w.writeAll("&quot;"),
        else => try w.writeByte(ch),
    }
}

fn escape(a: Allocator, s: []const u8) ![]u8 {
    var w: std.Io.Writer.Allocating = .init(a);
    for (s) |ch| try escapeByte(&w.writer, ch);
    return w.toOwnedSlice();
}

const sample =
    \\### Zero-shot (a model)
    \\
    \\> *"Read `BENCHMARK.md` & go"*
    \\
    \\### Cross-model leaderboard (2026-10-19)
    \\
    \\| Model | CPU ms | Note |
    \\| :--- | ---: | :--- |
    \\| A <b> | 1.40\* | `u01` |
    \\| B | 2.19 | none |
    \\
    \\after
;

test "prompt" {
    try std.testing.expectEqualStrings("Read `BENCHMARK.md` & go", try prompt(sample));
}

test "leaderboard" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const t = try leaderboard(arena.allocator(), sample);
    try std.testing.expect(std.mem.find(u8, t, "<td>A &lt;b&gt;</td><td>1.40*</td><td><code>u01</code></td>") != null);
    try std.testing.expect(std.mem.find(u8, t, "<td>B</td>") != null);
    try std.testing.expect(std.mem.find(u8, t, "after") == null);
    try std.testing.expect(std.mem.find(u8, t, ":---") == null);
}

test "render fills both placeholders" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const out = try render(arena.allocator(), sample, "<p><!-- @PROMPT --></p><!-- @LEADERBOARD -->");
    try std.testing.expect(std.mem.startsWith(u8, out, "<p>Read `BENCHMARK.md` &amp; go</p><table"));
}

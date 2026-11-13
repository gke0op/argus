//! bench/feed.zig: the live board's feed (feed.json) from GitHub's pull requests.
//!
//!   zig run bench/feed.zig -- IN_DIR OWNER/REPO GENERATED_AT > feed.json
//!
//! IN_DIR holds what `gh api` fetched (.github/workflows/bench-feed.yml): pulls.json (the
//! repository's pull requests), and per pull request N, files-N.json and comments-N.json. Every
//! file a pull request adds under bench/submissions/ as <Model>_<Name>.zig is one entry: the pull
//! request, the model (the name up to its first `_`), a raw URL for the source at the head
//! commit, and the grades bench-comment.yml posted: the native harness's verdict and the browser
//! build's reference grade (web/zigc/grade.mjs) from the comment's `argus-bench-data` line. An
//! entry is "waiting" until a grade for its pull request's current head is posted, then "graded";
//! a grade for an older head makes it "stale".
//!
//! Everything read here is untrusted text from pull requests: names, SHAs and repository names
//! are checked against their shapes and dropped if they do not fit; titles and logins are passed
//! through as JSON strings (the page shows them as text).
const std = @import("std");

const User = struct { login: []const u8 = "" };
const Repo = struct { full_name: []const u8 = "" };
const Head = struct { sha: []const u8 = "", repo: ?Repo = null };
const Pull = struct {
    number: u32,
    title: []const u8 = "",
    state: []const u8 = "",
    merged_at: ?[]const u8 = null,
    updated_at: []const u8 = "",
    html_url: []const u8 = "",
    user: ?User = null,
    head: Head = .{},
};
const File = struct { filename: []const u8 = "", status: []const u8 = "" };
const Comment = struct { user: ?User = null, body: ?[]const u8 = null, html_url: []const u8 = "", updated_at: []const u8 = "" };

/// The browser build's reference grade of one theme (web/zigc/grade.mjs, via the comment).
pub const BrowserGrade = struct {
    ruler: ?[]const u8 = null,
    moduleSha256: ?[]const u8 = null,
    outcome: []const u8 = "",
    gates: []const ?bool = &.{},
};
const ThemeData = struct { name: []const u8 = "", ext: []const u8 = "", native: []const u8 = "", browser: ?BrowserGrade = null };
/// The `<!-- argus-bench-data: {...} -->` line of a bench comment.
pub const BenchData = struct { head: []const u8 = "", themes: []const ThemeData = &.{} };

pub const Native = struct {
    verdict: []const u8,
    /// The head commit the grade was for; null in a comment from before the data line.
    head: ?[]const u8,
    comment: []const u8,
    at: []const u8,
};
pub const Entry = struct {
    pr: u32,
    title: []const u8,
    author: []const u8,
    state: []const u8,
    updated: []const u8,
    url: []const u8,
    headRepo: []const u8,
    headSha: []const u8,
    path: []const u8,
    name: []const u8,
    model: []const u8,
    raw: []const u8,
    status: []const u8,
    native: ?Native,
    browser: ?BrowserGrade,
};
const Feed = struct { version: u32 = 1, generated: []const u8, repo: []const u8, entries: []const Entry };

fn allIn(s: []const u8, comptime ok: fn (u8) bool) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!ok(c)) return false;
    return true;
}
fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}
fn isHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
}
fn isRepoPartChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.';
}
/// "owner/name": exactly two parts of letters, digits, `-`, `_`, `.`, neither "." nor "..".
pub fn isRepo(s: []const u8) bool {
    const slash = std.mem.findScalar(u8, s, '/') orelse return false;
    const owner = s[0..slash];
    const name = s[slash + 1 ..];
    for ([_][]const u8{ owner, name }) |part| {
        if (!allIn(part, isRepoPartChar) or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}
pub fn isSha(s: []const u8, len: usize) bool {
    return s.len == len and allIn(s, isHex);
}

/// "bench/submissions/<Name>.zig" -> Name, if Name is letters, digits and `_`.
pub fn submissionName(path: []const u8) ?[]const u8 {
    const prefix = "bench/submissions/";
    if (!std.mem.startsWith(u8, path, prefix) or !std.mem.endsWith(u8, path, ".zig")) return null;
    const name = path[prefix.len .. path.len - ".zig".len];
    return if (allIn(name, isNameChar)) name else null;
}

/// The model: the name up to its first `_` (BENCHMARK.md: <Model>_<Theme>.zig).
pub fn modelOf(name: []const u8) []const u8 {
    return name[0 .. std.mem.findScalar(u8, name, '_') orelse name.len];
}

/// The data line of a bench comment, parsed and checked; null if absent or malformed.
pub fn parseData(arena: std.mem.Allocator, body: []const u8) ?BenchData {
    const open = "<!-- argus-bench-data: ";
    const start = (std.mem.find(u8, body, open) orelse return null) + open.len;
    const end = std.mem.findPos(u8, body, start, " -->") orelse return null;
    var d = std.json.parseFromSliceLeaky(BenchData, arena, body[start..end], .{ .ignore_unknown_fields = true }) catch return null;
    if (!isSha(d.head, 40)) d.head = "";
    var kept: std.ArrayList(ThemeData) = .empty;
    for (d.themes) |t| {
        if (!allIn(t.name, isNameChar)) continue;
        var copy = t;
        if (copy.browser) |b| {
            var g = b;
            if (g.moduleSha256) |m| if (!isSha(m, 64)) {
                g.moduleSha256 = null;
            };
            if (g.ruler) |r| if (!isSha(r, 64)) {
                g.ruler = null;
            };
            if (!allIn(g.outcome, isNameCharOrDash)) g.outcome = "";
            if (g.gates.len != 8) g.gates = &.{};
            copy.browser = g;
        }
        if (!(std.mem.eql(u8, copy.native, "PASS") or std.mem.eql(u8, copy.native, "FAIL"))) copy.native = "";
        kept.append(arena, copy) catch return null;
    }
    d.themes = kept.items;
    return d;
}
fn isNameCharOrDash(c: u8) bool {
    return isNameChar(c) or c == '-';
}

/// A bench comment from before the data line: "**`NAME.zig`: PASS**" lines.
pub fn legacyVerdict(body: []const u8, name: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, body, '\n');
    while (it.next()) |line| {
        const l = std.mem.trim(u8, line, " \r");
        if (!std.mem.startsWith(u8, l, "**`")) continue;
        const rest = l[3..];
        if (!std.mem.startsWith(u8, rest, name) or !std.mem.startsWith(u8, rest[name.len..], ".zig`: ")) continue;
        const v = rest[name.len + ".zig`: ".len ..];
        if (std.mem.startsWith(u8, v, "PASS")) return "PASS";
        if (std.mem.startsWith(u8, v, "FAIL")) return "FAIL";
    }
    return null;
}

fn readJson(comptime T: type, arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !?T {
    const bytes = dir.readFileAlloc(io, path, arena, .unlimited) catch |e| switch (e) {
        error.FileNotFound => return null,
        else => return e,
    };
    return try std.json.parseFromSliceLeaky(T, arena, bytes, .{ .ignore_unknown_fields = true });
}

fn lessThan(_: void, a: Entry, b: Entry) bool {
    const o = std.mem.order(u8, a.updated, b.updated);
    return if (o == .eq) std.mem.order(u8, a.name, b.name) == .lt else o == .gt;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 4) {
        try std.Io.File.stderr().writeStreamingAll(io, "usage: feed IN_DIR OWNER/REPO GENERATED_AT\n");
        std.process.exit(2);
    }
    var dir = try std.Io.Dir.cwd().openDir(io, args[1], .{});
    defer dir.close(io);
    const repo = args[2];
    const pulls = (try readJson([]const Pull, arena, io, dir, "pulls.json")) orelse &.{};

    var entries: std.ArrayList(Entry) = .empty;
    for (pulls) |p| {
        const files = (try readJson([]const File, arena, io, dir, try std.fmt.allocPrint(arena, "files-{d}.json", .{p.number}))) orelse continue;
        const comments = (try readJson([]const Comment, arena, io, dir, try std.fmt.allocPrint(arena, "comments-{d}.json", .{p.number}))) orelse &.{};
        // The last bench comment by the workflow.
        var bench: ?Comment = null;
        for (comments) |c| {
            const login = if (c.user) |u| u.login else "";
            const body = c.body orelse continue;
            if (std.mem.eql(u8, login, "github-actions[bot]") and std.mem.startsWith(u8, body, "<!-- argus-bench -->")) bench = c;
        }
        const data: ?BenchData = if (bench) |b| parseData(arena, b.body.?) else null;
        const head_repo = if (p.head.repo) |r| r.full_name else "";
        const sha_ok = isSha(p.head.sha, 40) and isRepo(head_repo);
        const state: []const u8 = if (std.mem.eql(u8, p.state, "open")) "open" else if (p.merged_at != null) "merged" else "closed";
        for (files) |f| {
            if (std.mem.eql(u8, f.status, "removed")) continue;
            const name = submissionName(f.filename) orelse continue;
            var native: ?Native = null;
            var browser: ?BrowserGrade = null;
            if (bench) |b| {
                if (data) |d| {
                    for (d.themes) |t| if (std.mem.eql(u8, t.name, name)) {
                        if (t.native.len > 0) native = .{ .verdict = t.native, .head = if (d.head.len > 0) d.head else null, .comment = b.html_url, .at = b.updated_at };
                        browser = t.browser;
                    };
                } else if (legacyVerdict(b.body.?, name)) |v| {
                    native = .{ .verdict = v, .head = null, .comment = b.html_url, .at = b.updated_at };
                }
            }
            const status: []const u8 = if (!std.mem.eql(u8, state, "open")) state else if (native) |n|
                (if (n.head) |h| (if (std.mem.eql(u8, h, p.head.sha)) "graded" else "stale") else "graded")
            else
                "waiting";
            try entries.append(arena, .{
                .pr = p.number,
                .title = p.title,
                .author = if (p.user) |u| u.login else "",
                .state = state,
                .updated = p.updated_at,
                .url = p.html_url,
                .headRepo = if (sha_ok) head_repo else "",
                .headSha = if (sha_ok) p.head.sha else "",
                .path = f.filename,
                .name = name,
                .model = modelOf(name),
                .raw = if (sha_ok) try std.fmt.allocPrint(arena, "https://raw.githubusercontent.com/{s}/{s}/{s}", .{ head_repo, p.head.sha, f.filename }) else "",
                .status = status,
                .native = native,
                .browser = browser,
            });
        }
    }
    std.mem.sort(Entry, entries.items, {}, lessThan);
    const out = try std.fmt.allocPrint(arena, "{f}\n", .{std.json.fmt(Feed{ .generated = args[3], .repo = repo, .entries = entries.items }, .{ .whitespace = .indent_1 })});
    try std.Io.File.stdout().writeStreamingAll(io, out);
}

test submissionName {
    try std.testing.expectEqualStrings("Opus_Nebula", submissionName("bench/submissions/Opus_Nebula.zig").?);
    try std.testing.expect(submissionName("bench/submissions/a/b.zig") == null);
    try std.testing.expect(submissionName("bench/submissions/x-y.zig") == null);
    try std.testing.expect(submissionName("themes/Opus_Nebula.zig") == null);
    try std.testing.expect(submissionName("bench/submissions/README.md") == null);
    try std.testing.expectEqualStrings("Opus", modelOf("Opus_Nebula_2"));
    try std.testing.expectEqualStrings("Solo", modelOf("Solo"));
}

const A40: [40]u8 = @splat('a');
const B64: [64]u8 = @splat('b');
const C64: [64]u8 = @splat('c');

test isRepo {
    try std.testing.expect(isRepo("gke0op/argus"));
    try std.testing.expect(isRepo("a-b.c/d_e.f"));
    try std.testing.expect(!isRepo("evil/../repo"));
    try std.testing.expect(!isRepo("../argus"));
    try std.testing.expect(!isRepo("owner"));
    try std.testing.expect(!isRepo("o/n/x"));
    try std.testing.expect(!isRepo("o/"));
}

test parseData {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const good = "<!-- argus-bench -->\n<!-- argus-bench-data: {\"head\":\"" ++ A40 ++ "\",\"themes\":[{\"name\":\"Opus_X\",\"ext\":\"zig\",\"native\":\"PASS\",\"browser\":{\"ruler\":\"" ++ B64 ++ "\",\"moduleSha256\":\"" ++ C64 ++ "\",\"outcome\":\"verdict\",\"gates\":[true,true,true,true,true,true,true,false]}},{\"name\":\"bad name\",\"native\":\"PASS\"}]} -->\n### x";
    const d = parseData(a, good).?;
    try std.testing.expectEqual(@as(usize, 1), d.themes.len);
    try std.testing.expectEqualStrings("PASS", d.themes[0].native);
    try std.testing.expectEqual(@as(usize, 8), d.themes[0].browser.?.gates.len);
    // A malformed SHA is dropped, not passed on.
    const bad = "<!-- argus-bench-data: {\"head\":\"zz\",\"themes\":[{\"name\":\"A\",\"native\":\"MAYBE\",\"browser\":{\"moduleSha256\":\"<script>\",\"outcome\":\"x y\",\"gates\":[true]}}]} -->";
    const e = parseData(a, bad).?;
    try std.testing.expectEqualStrings("", e.head);
    try std.testing.expectEqualStrings("", e.themes[0].native);
    try std.testing.expect(e.themes[0].browser.?.moduleSha256 == null);
    try std.testing.expectEqualStrings("", e.themes[0].browser.?.outcome);
    try std.testing.expectEqual(@as(usize, 0), e.themes[0].browser.?.gates.len);
    try std.testing.expect(parseData(a, "no data here") == null);
}

test legacyVerdict {
    const body = "<!-- argus-bench -->\n### ARGUS-BENCH: native harness\n\n**`Opus_X.zig`: FAIL**\n\n**`Opus_Y.zig`: PASS**\n";
    try std.testing.expectEqualStrings("FAIL", legacyVerdict(body, "Opus_X").?);
    try std.testing.expectEqualStrings("PASS", legacyVerdict(body, "Opus_Y").?);
    try std.testing.expect(legacyVerdict(body, "Opus") == null);
}

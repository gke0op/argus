//! web/zigc/bundle.zig: the Zig lib files the bench page's compiler needs, in one file.
//!
//!   zig run web/zigc/bundle.zig -- LIB_DIR OUT.bin [LIST.txt]
//!
//! LIB_DIR is the lib/ of the official Zig 0.17.0 release (tools/get-zig.sh installs it).
//! Zig runs AstGen on every file reachable through an `@import("x.zig")` string, whether or not
//! the code is ever analyzed, so a compile reads the whole import closure of std/std.zig (and of
//! compiler_rt.zig, which web/zigc/root.zig builds into every module): 698 files. That closure
//! is what this bundles, so any theme that imports std finds every file it can reach, and
//! nothing else (lib/ also holds libc headers and sources, 242 MB, that no theme build opens).
//! The release itself ships the closure's 86 test files (`*_test.zig`, `test.zig`) empty, which
//! is why its closure is 18.0 MB where the source tarball's is 31.5 MB; web/zigc/test.mjs
//! checks that every module comes out byte-identical either way.
//!
//! Format (read by web/zigc/stdlib.js): "ZIGLIB1\n", the index length (u32 little-endian), the
//! index ("path\tsize\n" per file, sorted, paths relative to LIB_DIR), then every file's bytes
//! in index order. The page fetches it gzipped (OUT.bin.gz).
const std = @import("std");

const roots = [_][]const u8{ "std/std.zig", "compiler_rt.zig" };

/// Append the `@import("*.zig")` targets of `source` (a file at `path`, relative to the lib
/// dir) to `out`, resolved against the file's directory. Module imports ("std", "builtin",
/// "root") are not files and are skipped.
fn scanImports(gpa: std.mem.Allocator, path: []const u8, source: [:0]const u8, out: *std.ArrayList([]u8)) !void {
    var tok: std.zig.Tokenizer = .init(source);
    const dir = std.fs.path.dirnamePosix(path) orelse "";
    var prev2: std.zig.Token.Tag = .invalid;
    var prev1: std.zig.Token.Tag = .invalid;
    var prev2_text: []const u8 = "";
    while (true) {
        const t = tok.next();
        if (t.tag == .eof) break;
        if (t.tag == .string_literal and prev1 == .l_paren and prev2 == .builtin and std.mem.eql(u8, prev2_text, "@import")) {
            const lit = source[t.loc.start..t.loc.end];
            const name = lit[1 .. lit.len - 1];
            if (std.mem.endsWith(u8, name, ".zig")) {
                const full = try std.fs.path.resolveAllocPosix(gpa, &.{ dir, name });
                try out.append(gpa, full);
            }
        }
        prev2 = prev1;
        prev2_text = if (prev1 == .builtin) prev2_text else "";
        prev1 = t.tag;
        if (t.tag == .builtin) prev2_text = source[t.loc.start..t.loc.end];
    }
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) {
        try std.Io.File.stderr().writeStreamingAll(io, "usage: bundle LIB_DIR OUT.bin [LIST.txt]\n");
        std.process.exit(2);
    }
    var lib = try std.Io.Dir.cwd().openDir(io, args[1], .{});
    defer lib.close(io);

    // Breadth-first over the import graph.
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var queue: std.ArrayList([]u8) = .empty;
    for (roots) |r| try queue.append(arena, try arena.dupe(u8, r));
    var files: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < queue.items.len) : (i += 1) {
        const p = queue.items[i];
        if (seen.contains(p)) continue;
        try seen.put(arena, p, {});
        try files.append(arena, p);
        const src = try lib.readFileAllocOptions(io, p, arena, .unlimited, .of(u8), 0);
        try scanImports(arena, p, src, &queue);
    }
    std.mem.sort([]const u8, files.items, {}, lessThan);

    var index: std.ArrayList(u8) = .empty;
    var data: std.ArrayList(u8) = .empty;
    var raw_total: usize = 0;
    var empty: usize = 0;
    for (files.items) |p| {
        const bytes = try lib.readFileAlloc(io, p, arena, .unlimited);
        raw_total += bytes.len;
        if (bytes.len == 0) empty += 1;
        try index.print(arena, "{s}\t{d}\n", .{ p, bytes.len });
        try data.appendSlice(arena, bytes);
    }

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, "ZIGLIB1\n");
    var len_le: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_le, @intCast(index.items.len), .little);
    try out.appendSlice(arena, &len_le);
    try out.appendSlice(arena, index.items);
    try out.appendSlice(arena, data.items);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[2], .data = out.items });
    if (args.len > 3) {
        var list: std.ArrayList(u8) = .empty;
        for (files.items) |p| try list.print(arena, "{s}\n", .{p});
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[3], .data = list.items });
    }
    var msg: [256]u8 = undefined;
    const line = try std.fmt.bufPrint(&msg, "bundle: {d} files ({d} empty), {d} bytes -> {s}\n", .{ files.items.len, empty, raw_total, args[2] });
    try std.Io.File.stderr().writeStreamingAll(io, line);
}

test scanImports {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var out: std.ArrayList([]u8) = .empty;
    const src =
        \\const std = @import("std");
        \\const a = @import("a.zig");
        \\const b = @import("../up/b.zig");
        \\test { _ = @import("x_test.zig"); }
        \\// @import("comment.zig") is not a token
        \\const s = "@import(\"string.zig\")";
    ;
    try scanImports(arena.allocator(), "std/dir/f.zig", src, &out);
    try std.testing.expectEqual(@as(usize, 3), out.items.len);
    try std.testing.expectEqualStrings("std/dir/a.zig", out.items[0]);
    try std.testing.expectEqualStrings("std/up/b.zig", out.items[1]);
    try std.testing.expectEqualStrings("std/dir/x_test.zig", out.items[2]);
}

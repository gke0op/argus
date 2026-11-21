//! tools/msl2wgsl.zig: translates an Argus Metal theme (themes/<Name>.metal, written against
//! src/gpu/argus_prelude.metal) into the WGSL the browser runs (web/README.md's contract; the
//! host prepends web/prelude.wgsl).
//!
//!   zig run tools/msl2wgsl.zig -- themes/Night_Tide.metal -o web/themes/Night_Tide.wgsl
//!   zig run tools/msl2wgsl.zig -- --out-dir DIR themes/A.metal themes/B.metal   # DIR/A.wgsl ...
//!   zig run tools/msl2wgsl.zig -- --check themes/*.metal     # translate, report, write nothing
//!
//! A theme the translator cannot handle fails with `file:line:col: error: <the construct>` and
//! exit status 1; nothing is written then, so a page never runs a wrong translation.
//! The pipeline (tools/msl2wgsl/): preprocess and lex (lex.zig), parse to an AST (parse.zig),
//! type-check and lower to WGSL (lower.zig).
const std = @import("std");
const lex = @import("msl2wgsl/lex.zig");
const parse = @import("msl2wgsl/parse.zig");
const lower = @import("msl2wgsl/lower.zig");

pub const Result = union(enum) {
    ok: []const u8,
    err: lex.Diag,
};

/// The theme's leading comment block, verbatim, and every later `// @argus` directive line, so
/// the host reads the same directives and the header's account carries over.
fn header(a: std.mem.Allocator, src: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.splitScalar(u8, src, '\n');
    var in_header = true;
    var in_block = false;
    while (it.next()) |raw| {
        const l = std.mem.trimEnd(u8, raw, "\r");
        const t = std.mem.trim(u8, l, " \t");
        if (in_header) {
            if (in_block) {
                try out.appendSlice(a, l);
                try out.append(a, '\n');
                if (std.mem.find(u8, t, "*/") != null) in_block = false;
                continue;
            }
            if (t.len == 0 and out.items.len > 0) {
                in_header = false; // the header ends at its first blank line
                continue;
            }
            if (t.len == 0 or std.mem.startsWith(u8, t, "//")) {
                try out.appendSlice(a, l);
                try out.append(a, '\n');
                continue;
            }
            if (std.mem.startsWith(u8, t, "/*")) {
                try out.appendSlice(a, l);
                try out.append(a, '\n');
                in_block = std.mem.find(u8, t, "*/") == null;
                continue;
            }
            in_header = false;
        }
        if (std.mem.find(u8, l, "@argus")) |at| {
            try out.print(a, "// {s}\n", .{l[at..]});
        }
    }
    // trailing blank lines of the header block
    while (out.items.len >= 2 and out.items[out.items.len - 1] == '\n' and out.items[out.items.len - 2] == '\n') out.items.len -= 1;
    return out.items;
}

/// Translates one theme. `label` names it in the output header (themes/X.metal).
pub fn translate(a: std.mem.Allocator, src: []const u8, label: []const u8) !Result {
    var diag: lex.Diag = .{};
    const r = translateInner(a, src, label, &diag) catch |e| switch (e) {
        error.Unsupported => return .{ .err = diag },
        error.OutOfMemory => return error.OutOfMemory,
    };
    return .{ .ok = r };
}

fn translateInner(a: std.mem.Allocator, src: []const u8, label: []const u8, diag: *lex.Diag) lex.Error![]const u8 {
    const toks = try lex.lex(a, src, diag);
    var pp: lex.Preprocessor = .{ .a = a, .diag = diag };
    const toks2 = try pp.run(toks);
    const items = try parse.parse(a, toks2, diag);
    var lw: lower.Lowerer = .{ .a = a, .diag = diag };
    try lw.run(items);
    return lw.emit(try header(a, src), label);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    var inputs: std.ArrayList([]const u8) = .empty;
    var out_path: ?[]const u8 = null;
    var out_dir: ?[]const u8 = null;
    var check = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const x = args[i];
        if (std.mem.eql(u8, x, "-o")) {
            i += 1;
            if (i >= args.len) break;
            out_path = args[i];
        } else if (std.mem.eql(u8, x, "--out-dir")) {
            i += 1;
            if (i >= args.len) break;
            out_dir = args[i];
        } else if (std.mem.eql(u8, x, "--check")) {
            check = true;
        } else try inputs.append(arena, x);
    }
    const stderr = std.Io.File.stderr();
    if (inputs.items.len == 0 or (!check and out_dir == null and inputs.items.len != 1)) {
        try stderr.writeStreamingAll(io, "usage: msl2wgsl THEME.metal [-o OUT.wgsl]\n       msl2wgsl --out-dir DIR THEME.metal...\n       msl2wgsl --check THEME.metal...\n");
        std.process.exit(2);
    }
    var failed: usize = 0;
    for (inputs.items) |path| {
        const src = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited);
        const res = try translate(arena, src, path);
        switch (res) {
            .err => |d| {
                failed += 1;
                try stderr.writeStreamingAll(io, try std.fmt.allocPrint(arena, "{s}:{d}:{d}: error: {s}\n", .{ path, d.line, d.col, d.msg }));
            },
            .ok => |wgsl| {
                if (check) {
                    try stderr.writeStreamingAll(io, try std.fmt.allocPrint(arena, "{s}: ok ({d} lines of WGSL)\n", .{ path, std.mem.countScalar(u8, wgsl, '\n') }));
                } else if (out_dir) |dir| {
                    const op = try std.fmt.allocPrint(arena, "{s}/{s}.wgsl", .{ dir, std.fs.path.stem(path) });
                    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = op, .data = wgsl });
                    try stderr.writeStreamingAll(io, try std.fmt.allocPrint(arena, "{s} -> {s}\n", .{ path, op }));
                } else if (out_path) |op| {
                    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = op, .data = wgsl });
                } else {
                    try std.Io.File.stdout().writeStreamingAll(io, wgsl);
                }
            },
        }
    }
    if (failed > 0) std.process.exit(1);
}

test "translate: a small theme" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src =
        \\// A test theme. It is small.
        \\// @argus state 4x4
        \\
        \\constant float K[3] = { 1.0f, 2.0f, 3 };
        \\static float wave(float x, int k) { x += 1; return sin(x * K[k]) + k; }
        \\kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]],
        \\                       texture2d<float, access::write> out [[texture(0)]],
        \\                       uint2 gid [[thread_position_in_grid]]) {
        \\    if (gid.x >= f.width || gid.y >= f.height) return;
        \\    float3 c = 0.5f;
        \\    c.xy *= wave(f.time, 1);
        \\    int n = 0;
        \\    for (int i = 0; i < 4; i++) n += i > 1 ? i : 2;
        \\    out.write(float4(c * n, 1), gid);
        \\}
    ;
    const r = try translate(a, src, "themes/Test.metal");
    switch (r) {
        .err => |d| {
            std.debug.print("{d}:{d}: {s}\n", .{ d.line, d.col, d.msg });
            return error.TestUnexpectedResult;
        },
        .ok => |w| {
            try std.testing.expect(std.mem.startsWith(u8, w, "// A test theme. It is small.\n// @argus state 4x4\n"));
            try std.testing.expect(std.mem.find(u8, w, "const K: array<f32, 3> = array<f32, 3>(1.0f, 2.0f, 3.0f);") != null);
            try std.testing.expect(std.mem.find(u8, w, "fn wave(x_in: f32, k: i32) -> f32") != null);
            try std.testing.expect(std.mem.find(u8, w, "textureStore(argus_out, gid, ") != null);
        },
    }
}

test "translate: an unsupported construct names itself" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const src =
        \\kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        \\    float x = dfdx(f.time) > 0.0f ? 0.0f : 1.0f;
        \\    out.write(float4(x), gid);
        \\}
    ;
    const r = try translate(arena.allocator(), src, "t.metal");
    try std.testing.expect(r == .err);
    try std.testing.expect(std.mem.find(u8, r.err.msg, "dfdx") != null);
    try std.testing.expectEqual(@as(u32, 2), r.err.line);
}

test {
    _ = lex;
    _ = parse;
}

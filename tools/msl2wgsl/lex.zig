//! msl2wgsl lexer and preprocessor: C++ tokens of the Metal subset Argus themes use, with
//! `#define` (object- and function-like), `#undef`, `#ifdef`/`#ifndef`/`#if 0|1`/`#else`/
//! `#endif`; `#include` and `#pragma` are ignored (the Argus prelude is the only include).
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tag = enum { ident, int_lit, float_lit, char_lit, str_lit, punct, directive, eof };

pub const Token = struct {
    tag: Tag,
    text: []const u8,
    line: u32,
    col: u32,
};

/// Where a translation failed, and why (the CLI prints `file:line:col: msg`).
pub const Diag = struct {
    line: u32 = 0,
    col: u32 = 0,
    msg: []const u8 = "",
};

pub const Error = error{ Unsupported, OutOfMemory };

pub fn fail(a: Allocator, diag: *Diag, line: u32, col: u32, comptime fmt: []const u8, args: anytype) Error {
    diag.line = line;
    diag.col = col;
    diag.msg = std.fmt.allocPrint(a, fmt, args) catch "out of memory";
    return error.Unsupported;
}

const puncts3 = [_][]const u8{ "<<=", ">>=", "..." };
const puncts2 = [_][]const u8{ "->", "++", "--", "<<", ">>", "<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "::" };

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}
fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

pub fn lex(a: Allocator, src: []const u8, diag: *Diag) Error![]Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    var line: u32 = 1;
    var line_start: usize = 0;
    var at_bol = true;
    while (i < src.len) {
        const c = src[i];
        const col: u32 = @intCast(i - line_start + 1);
        if (c == '\n') {
            i += 1;
            line += 1;
            line_start = i;
            at_bol = true;
            continue;
        }
        if (c == ' ' or c == '\t' or c == '\r' or c == '\x0c') {
            i += 1;
            continue;
        }
        if (c == '/' and i + 1 < src.len and src[i + 1] == '/') {
            while (i < src.len and src[i] != '\n') i += 1;
            continue;
        }
        if (c == '/' and i + 1 < src.len and src[i + 1] == '*') {
            i += 2;
            while (i + 1 < src.len and !(src[i] == '*' and src[i + 1] == '/')) {
                if (src[i] == '\n') {
                    line += 1;
                    line_start = i + 1;
                }
                i += 1;
            }
            i += 2;
            continue;
        }
        if (c == '#' and at_bol) {
            // A directive: to the end of the line, with backslash continuations.
            const start_line = line;
            var text: std.ArrayList(u8) = .empty;
            i += 1;
            while (i < src.len and src[i] != '\n') {
                if (src[i] == '\\' and i + 1 < src.len and src[i + 1] == '\n') {
                    i += 2;
                    line += 1;
                    line_start = i;
                    try text.append(a, ' ');
                    continue;
                }
                if (src[i] == '/' and i + 1 < src.len and src[i + 1] == '/') {
                    while (i < src.len and src[i] != '\n') i += 1;
                    break;
                }
                try text.append(a, src[i]);
                i += 1;
            }
            try out.append(a, .{ .tag = .directive, .text = text.items, .line = start_line, .col = col });
            continue;
        }
        at_bol = false;
        if (isIdentStart(c)) {
            const s = i;
            while (i < src.len and isIdentChar(src[i])) i += 1;
            try out.append(a, .{ .tag = .ident, .text = src[s..i], .line = line, .col = col });
            continue;
        }
        if (std.ascii.isDigit(c) or (c == '.' and i + 1 < src.len and std.ascii.isDigit(src[i + 1]))) {
            const s = i;
            var is_float = false;
            if (c == '0' and i + 1 < src.len and (src[i + 1] == 'x' or src[i + 1] == 'X')) {
                i += 2;
                while (i < src.len and std.ascii.isHex(src[i])) i += 1;
                if (i < src.len and (src[i] == '.' or src[i] == 'p' or src[i] == 'P')) {
                    return fail(a, diag, line, col, "hexadecimal float literals are not supported", .{});
                }
            } else {
                while (i < src.len and std.ascii.isDigit(src[i])) i += 1;
                if (i < src.len and src[i] == '.') {
                    is_float = true;
                    i += 1;
                    while (i < src.len and std.ascii.isDigit(src[i])) i += 1;
                }
                if (i < src.len and (src[i] == 'e' or src[i] == 'E')) {
                    is_float = true;
                    i += 1;
                    if (i < src.len and (src[i] == '+' or src[i] == '-')) i += 1;
                    while (i < src.len and std.ascii.isDigit(src[i])) i += 1;
                }
            }
            while (i < src.len and isIdentChar(src[i])) {
                const sc = src[i];
                if (sc == 'f' or sc == 'F' or sc == 'h' or sc == 'H') is_float = true;
                i += 1;
            }
            try out.append(a, .{ .tag = if (is_float) .float_lit else .int_lit, .text = src[s..i], .line = line, .col = col });
            continue;
        }
        if (c == '\'' or c == '"') {
            const s = i;
            i += 1;
            while (i < src.len and src[i] != c) {
                if (src[i] == '\\') i += 1;
                if (i < src.len and src[i] == '\n') return fail(a, diag, line, col, "unterminated literal", .{});
                i += 1;
            }
            i += 1;
            try out.append(a, .{ .tag = if (c == '"') .str_lit else .char_lit, .text = src[s..@min(i, src.len)], .line = line, .col = col });
            continue;
        }
        var matched: ?[]const u8 = null;
        for (puncts3) |p| {
            if (std.mem.startsWith(u8, src[i..], p)) {
                matched = p;
                break;
            }
        }
        if (matched == null) for (puncts2) |p| {
            if (std.mem.startsWith(u8, src[i..], p)) {
                matched = p;
                break;
            }
        };
        if (matched) |p| {
            try out.append(a, .{ .tag = .punct, .text = src[i .. i + p.len], .line = line, .col = col });
            i += p.len;
            continue;
        }
        if (std.mem.findScalar(u8, "+-*/%<>=!&|^~?:;,.()[]{}", c) != null) {
            try out.append(a, .{ .tag = .punct, .text = src[i .. i + 1], .line = line, .col = col });
            i += 1;
            continue;
        }
        return fail(a, diag, line, col, "unexpected character '{c}'", .{c});
    }
    try out.append(a, .{ .tag = .eof, .text = "", .line = line, .col = 1 });
    return out.items;
}

/// Unescapes a C string or char literal body (the text between the quotes).
pub fn unescape(a: Allocator, body: []const u8) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        if (body[i] != '\\' or i + 1 >= body.len) {
            try out.append(a, body[i]);
            continue;
        }
        i += 1;
        const e: u8 = switch (body[i]) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            '0' => 0,
            '\\' => '\\',
            '\'' => '\'',
            '"' => '"',
            else => body[i],
        };
        try out.append(a, e);
    }
    return out.items;
}

const Macro = struct {
    params: ?[]const []const u8,
    body: []const Token,
};

pub const Preprocessor = struct {
    a: Allocator,
    diag: *Diag,
    macros: std.StringHashMapUnmanaged(Macro) = .empty,
    disabled: std.ArrayList([]const u8) = .empty,

    pub fn run(self: *Preprocessor, toks: []const Token) Error![]Token {
        var out: std.ArrayList(Token) = .empty;
        // #if stack: each entry says whether this level is active and whether a branch was taken.
        const Cond = struct { active: bool, taken: bool, parent: bool };
        var conds: std.ArrayList(Cond) = .empty;
        var active = true;
        var i: usize = 0;
        while (i < toks.len) {
            const t = toks[i];
            if (t.tag == .directive) {
                i += 1;
                const d = std.mem.trim(u8, t.text, " \t\r");
                var it = std.mem.tokenizeAny(u8, d, " \t(");
                const kw = it.next() orelse continue;
                if (std.mem.eql(u8, kw, "ifdef") or std.mem.eql(u8, kw, "ifndef")) {
                    const name = it.next() orelse return fail(self.a, self.diag, t.line, t.col, "#{s} without a name", .{kw});
                    const def = self.macros.contains(name);
                    const v = if (kw[2] == 'd') def else !def;
                    try conds.append(self.a, .{ .active = active and v, .taken = v, .parent = active });
                    active = active and v;
                    continue;
                }
                if (std.mem.eql(u8, kw, "if")) {
                    const rest = std.mem.trim(u8, d[2..], " \t");
                    const v: bool = if (std.mem.eql(u8, rest, "0")) false else if (std.mem.eql(u8, rest, "1")) true else return fail(self.a, self.diag, t.line, t.col, "#if with an expression is not supported (only #if 0 / #if 1)", .{});
                    try conds.append(self.a, .{ .active = active and v, .taken = v, .parent = active });
                    active = active and v;
                    continue;
                }
                if (std.mem.eql(u8, kw, "else")) {
                    if (conds.items.len == 0) return fail(self.a, self.diag, t.line, t.col, "#else without #if", .{});
                    const top = &conds.items[conds.items.len - 1];
                    top.active = top.parent and !top.taken;
                    top.taken = true;
                    active = top.active;
                    continue;
                }
                if (std.mem.eql(u8, kw, "elif")) return fail(self.a, self.diag, t.line, t.col, "#elif is not supported", .{});
                if (std.mem.eql(u8, kw, "endif")) {
                    if (conds.items.len == 0) return fail(self.a, self.diag, t.line, t.col, "#endif without #if", .{});
                    active = conds.pop().?.parent;
                    continue;
                }
                if (!active) continue;
                if (std.mem.eql(u8, kw, "define")) {
                    try self.define(t, d["define".len..]);
                } else if (std.mem.eql(u8, kw, "undef")) {
                    if (it.next()) |name| _ = self.macros.remove(name);
                } else if (std.mem.eql(u8, kw, "include") or std.mem.eql(u8, kw, "pragma")) {
                    // The Argus prelude includes <metal_stdlib>; pragmas don't change meaning here.
                } else {
                    return fail(self.a, self.diag, t.line, t.col, "preprocessor directive #{s} is not supported", .{kw});
                }
                continue;
            }
            if (!active) {
                i += 1;
                continue;
            }
            i = try self.expandOne(toks, i, &out, t);
        }
        if (conds.items.len != 0) return fail(self.a, self.diag, 0, 0, "unterminated #if", .{});
        return out.items;
    }

    fn define(self: *Preprocessor, t: Token, rest_in: []const u8) Error!void {
        const rest = std.mem.trimStart(u8, rest_in, " \t");
        var n: usize = 0;
        while (n < rest.len and isIdentChar(rest[n])) n += 1;
        if (n == 0) return fail(self.a, self.diag, t.line, t.col, "#define without a name", .{});
        const name = rest[0..n];
        var params: ?[]const []const u8 = null;
        var body_text = rest[n..];
        if (body_text.len > 0 and body_text[0] == '(') {
            const close = std.mem.findScalar(u8, body_text, ')') orelse return fail(self.a, self.diag, t.line, t.col, "#define {s}: unterminated parameter list", .{name});
            var ps: std.ArrayList([]const u8) = .empty;
            var pit = std.mem.tokenizeAny(u8, body_text[1..close], " \t,");
            while (pit.next()) |p| {
                if (std.mem.eql(u8, p, "...")) return fail(self.a, self.diag, t.line, t.col, "#define {s}: variadic macros are not supported", .{name});
                try ps.append(self.a, p);
            }
            params = ps.items;
            body_text = body_text[close + 1 ..];
        }
        if (std.mem.findScalar(u8, body_text, '#') != null) return fail(self.a, self.diag, t.line, t.col, "#define {s}: the # and ## operators are not supported", .{name});
        var sub_diag: Diag = .{};
        const body = lex(self.a, body_text, &sub_diag) catch return fail(self.a, self.diag, t.line, t.col, "#define {s}: {s}", .{ name, sub_diag.msg });
        try self.macros.put(self.a, name, .{ .params = params, .body = body[0 .. body.len - 1] });
    }

    fn isDisabled(self: *Preprocessor, name: []const u8) bool {
        for (self.disabled.items) |d| if (std.mem.eql(u8, d, name)) return true;
        return false;
    }

    /// Emits toks[i] (expanding it if it names a macro) and returns the next index.
    fn expandOne(self: *Preprocessor, toks: []const Token, i: usize, out: *std.ArrayList(Token), site: Token) Error!usize {
        const t = toks[i];
        if (t.tag != .ident or self.isDisabled(t.text)) {
            if (t.tag != .eof or i + 1 == toks.len) try out.append(self.a, retarget(t, site));
            return i + 1;
        }
        const m = self.macros.get(t.text) orelse {
            try out.append(self.a, retarget(t, site));
            return i + 1;
        };
        var next = i + 1;
        var body: std.ArrayList(Token) = .empty;
        if (m.params) |params| {
            if (next >= toks.len or !(toks[next].tag == .punct and std.mem.eql(u8, toks[next].text, "("))) {
                try out.append(self.a, retarget(t, site));
                return i + 1;
            }
            // Arguments: split on top-level commas.
            var args: std.ArrayList([]const Token) = .empty;
            var depth: usize = 0;
            var start = next + 1;
            var j = next + 1;
            while (j < toks.len) : (j += 1) {
                const x = toks[j];
                if (x.tag == .eof) return fail(self.a, self.diag, t.line, t.col, "macro {s}: unterminated argument list", .{t.text});
                if (x.tag != .punct) continue;
                if (x.text[0] == '(' or x.text[0] == '[' or x.text[0] == '{') depth += 1;
                if (x.text[0] == ')' or x.text[0] == ']' or x.text[0] == '}') {
                    if (depth == 0) {
                        try args.append(self.a, toks[start..j]);
                        break;
                    }
                    depth -= 1;
                }
                if (depth == 0 and x.text[0] == ',' and x.text.len == 1) {
                    try args.append(self.a, toks[start..j]);
                    start = j + 1;
                }
            }
            next = j + 1;
            if (args.items.len == 1 and args.items[0].len == 0 and params.len == 0) args.items.len = 0;
            if (args.items.len != params.len) return fail(self.a, self.diag, t.line, t.col, "macro {s} takes {d} arguments, given {d}", .{ t.text, params.len, args.items.len });
            for (m.body) |b| {
                var replaced = false;
                if (b.tag == .ident) for (params, 0..) |p, k| {
                    if (std.mem.eql(u8, p, b.text)) {
                        try body.appendSlice(self.a, args.items[k]);
                        replaced = true;
                        break;
                    }
                };
                if (!replaced) try body.append(self.a, b);
            }
        } else {
            try body.appendSlice(self.a, m.body);
        }
        try self.disabled.append(self.a, t.text);
        var k: usize = 0;
        while (k < body.items.len) k = try self.expandOne(body.items, k, out, if (site.line == t.line and site.col == t.col) t else site);
        _ = self.disabled.pop();
        return next;
    }

    fn retarget(t: Token, site: Token) Token {
        var r = t;
        if (site.line != 0) {
            r.line = site.line;
            r.col = site.col;
        }
        return r;
    }
};

test "lexer: numbers, punctuation, comments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var d: Diag = .{};
    const toks = try lex(arena.allocator(), "x <<= 0x7feb352dU; // c\n/* b */ y = .5f + 1e-3 + 2u;", &d);
    try std.testing.expectEqual(@as(usize, 13), toks.len);
    try std.testing.expectEqualStrings("<<=", toks[1].text);
    try std.testing.expectEqual(Tag.int_lit, toks[2].tag);
    try std.testing.expectEqual(Tag.float_lit, toks[6].tag);
    try std.testing.expectEqual(@as(u32, 2), toks[5].line);
}

test "preprocessor: function-like macro" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: Diag = .{};
    const toks = try lex(a, "#define SQ(x) ((x) * (x))\nfloat y = SQ(a + 1);\n", &d);
    var pp: Preprocessor = .{ .a = a, .diag = &d };
    const out = try pp.run(toks);
    var s: std.ArrayList(u8) = .empty;
    for (out) |t| try s.appendSlice(a, t.text);
    try std.testing.expectEqualStrings("floaty=((a+1)*(a+1));", s.items);
}

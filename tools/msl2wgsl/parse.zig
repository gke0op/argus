//! msl2wgsl parser: a recursive-descent parser for the C++/Metal subset Argus themes are
//! written in, producing the untyped AST below. Types are resolved later (lower.zig); the parser
//! only needs to know which identifiers name types, to tell declarations from expressions.
const std = @import("std");
const Allocator = std.mem.Allocator;
const lex = @import("lex.zig");
const Token = lex.Token;
const Diag = lex.Diag;
const Error = lex.Error;

pub const Space = enum { none, thread, constant, device, threadgroup };

pub const TArg = union(enum) {
    ty: *TypeRef,
    name: []const u8, // access::read, and the like
    int: i64,
};

pub const TypeRef = struct {
    name: []const u8,
    targs: []const TArg = &.{},
    is_const: bool = false,
    space: Space = .none,
    ref: bool = false,
    ptr: u8 = 0,
    line: u32 = 0,
    col: u32 = 0,
};

pub const Expr = struct {
    line: u32,
    col: u32,
    kind: Kind,

    pub const Kind = union(enum) {
        ident: []const u8,
        int_lit: struct { value: u64, unsigned: bool },
        float_lit: []const u8, // digits as written, without the suffix
        bool_lit: bool,
        char_lit: u8,
        str_lit: []const u8,
        unary: struct { op: []const u8, e: *Expr },
        postfix: struct { op: []const u8, e: *Expr },
        binary: struct { op: []const u8, a: *Expr, b: *Expr },
        assign: struct { op: []const u8, lhs: *Expr, rhs: *Expr },
        ternary: struct { c: *Expr, a: *Expr, b: *Expr },
        call: struct { callee: *Expr, args: []*Expr, targs: []const TypeRef = &.{} },
        member: struct { e: *Expr, name: []const u8, arrow: bool = false },
        index: struct { e: *Expr, i: *Expr },
        cast: struct { ty: TypeRef, e: *Expr },
        construct: struct { ty: TypeRef, args: []*Expr },
        init_list: []*Expr,
        lambda: *Lambda,
        comma: struct { a: *Expr, b: *Expr },
    };
};

pub const Attr = struct { name: []const u8, arg: ?i64 = null };

pub const Param = struct {
    ty: TypeRef,
    name: []const u8,
    dims: []const ?*Expr = &.{},
    default: ?*Expr = null,
    attr: ?Attr = null,
    line: u32 = 0,
    col: u32 = 0,
};

pub const Lambda = struct {
    by_ref: bool,
    params: []Param,
    ret: ?TypeRef,
    body: *Stmt,
    line: u32,
    col: u32,
};

pub const Declarator = struct {
    name: []const u8,
    dims: []const ?*Expr = &.{},
    init: ?*Expr = null,
    ctor: ?[]*Expr = null,
    line: u32,
    col: u32,
};

pub const Case = struct {
    values: []*Expr,
    is_default: bool,
    body: []*Stmt,
    line: u32,
};

pub const Stmt = struct {
    line: u32,
    col: u32,
    kind: Kind,

    pub const Kind = union(enum) {
        block: []*Stmt,
        decl: struct { ty: TypeRef, decls: []Declarator, is_constexpr: bool, is_threadgroup: bool },
        expr: *Expr,
        if_: struct { c: *Expr, then: *Stmt, els: ?*Stmt },
        for_: struct { init: ?*Stmt, cond: ?*Expr, incr: ?*Expr, body: *Stmt },
        while_: struct { c: *Expr, body: *Stmt },
        do_while: struct { body: *Stmt, c: *Expr },
        ret: ?*Expr,
        brk,
        cont,
        empty,
        switch_: struct { e: *Expr, cases: []Case },
    };
};

pub const Func = struct {
    name: []const u8,
    ret: TypeRef,
    params: []Param,
    body: ?*Stmt,
    tparams: []const []const u8 = &.{},
    is_kernel: bool,
    line: u32,
    col: u32,
    index: u32,
};

pub const Field = struct { ty: TypeRef, name: []const u8, dims: []const ?*Expr, line: u32, col: u32 };

pub const Struct = struct { name: []const u8, fields: []Field, line: u32, col: u32 };

pub const Global = struct { ty: TypeRef, decls: []Declarator, is_constexpr: bool, line: u32, col: u32 };

pub const Item = union(enum) {
    func: *Func,
    strct: *Struct,
    global: *Global,
    typedef: struct { name: []const u8, ty: TypeRef },
};

const builtin_scalars = [_][]const u8{ "bool", "char", "uchar", "short", "ushort", "int", "uint", "long", "ulong", "half", "float", "double" };
const builtin_others = [_][]const u8{
    "void",          "texture2d",     "sampler",       "atomic_uint", "atomic_int", "ArgusFrame", "ArgusStats", "ArgusProc", "auto",
    "size_t",        "int8_t",        "uint8_t",       "int16_t",     "uint16_t",   "int32_t",    "uint32_t",   "vec",       "array",
    "packed_float2", "packed_float3", "packed_float4", "unsigned",    "signed",
};

pub fn isBuiltinTypeName(n: []const u8) bool {
    for (builtin_others) |b| if (std.mem.eql(u8, n, b)) return true;
    for (builtin_scalars) |b| {
        if (!std.mem.startsWith(u8, n, b)) continue;
        const rest = n[b.len..];
        if (rest.len == 0) return true;
        if (rest.len == 1 and rest[0] >= '2' and rest[0] <= '4') return true;
        if (rest.len == 3 and rest[0] >= '2' and rest[0] <= '4' and rest[1] == 'x' and rest[2] >= '2' and rest[2] <= '4') return true;
    }
    return false;
}

pub const Parser = struct {
    a: Allocator,
    diag: *Diag,
    toks: []const Token,
    pos: usize = 0,
    types: std.StringHashMapUnmanaged(void) = .empty,
    tparams: []const []const u8 = &.{},
    func_count: u32 = 0,

    fn peek(self: *Parser) Token {
        return self.toks[self.pos];
    }
    fn peekAt(self: *Parser, k: usize) Token {
        return self.toks[@min(self.pos + k, self.toks.len - 1)];
    }
    fn advance(self: *Parser) Token {
        const t = self.toks[self.pos];
        if (self.pos + 1 < self.toks.len) self.pos += 1;
        return t;
    }
    fn isP(self: *Parser, s: []const u8) bool {
        const t = self.peek();
        return t.tag == .punct and std.mem.eql(u8, t.text, s);
    }
    fn isPAt(self: *Parser, k: usize, s: []const u8) bool {
        const t = self.peekAt(k);
        return t.tag == .punct and std.mem.eql(u8, t.text, s);
    }
    fn isKw(self: *Parser, s: []const u8) bool {
        const t = self.peek();
        return t.tag == .ident and std.mem.eql(u8, t.text, s);
    }
    fn eatP(self: *Parser, s: []const u8) bool {
        if (self.isP(s)) {
            _ = self.advance();
            return true;
        }
        return false;
    }
    fn eatKw(self: *Parser, s: []const u8) bool {
        if (self.isKw(s)) {
            _ = self.advance();
            return true;
        }
        return false;
    }
    fn failHere(self: *Parser, comptime fmt: []const u8, args: anytype) Error {
        const t = self.peek();
        return lex.fail(self.a, self.diag, t.line, t.col, fmt, args);
    }
    fn expectP(self: *Parser, s: []const u8) Error!void {
        if (!self.eatP(s)) {
            const t = self.peek();
            return self.failHere("expected '{s}', found '{s}'", .{ s, if (t.tag == .eof) "end of file" else t.text });
        }
    }
    fn expectIdent(self: *Parser) Error![]const u8 {
        const t = self.peek();
        if (t.tag != .ident) return self.failHere("expected a name, found '{s}'", .{t.text});
        _ = self.advance();
        return t.text;
    }

    fn isTypeName(self: *Parser, n: []const u8) bool {
        if (isBuiltinTypeName(n)) return true;
        if (self.types.contains(n)) return true;
        for (self.tparams) |p| if (std.mem.eql(u8, p, n)) return true;
        return false;
    }

    const qualifiers = [_][]const u8{ "const", "constant", "thread", "device", "threadgroup", "constexpr", "static", "inline", "volatile", "metal" };

    /// Whether a type starts here (qualifiers or a type name).
    fn atTypeStart(self: *Parser) bool {
        const t = self.peek();
        if (t.tag != .ident) return false;
        for (qualifiers) |q| if (std.mem.eql(u8, t.text, q)) {
            if (std.mem.eql(u8, q, "metal")) return self.isPAt(1, "::");
            return true;
        };
        return self.isTypeName(t.text);
    }

    pub fn new(self: *Parser, comptime T: type, v: T) Error!*T {
        const p = try self.a.create(T);
        p.* = v;
        return p;
    }

    // ------------------------------------------------------------------ types
    const TypeFlags = struct { is_constexpr: bool = false, is_static: bool = false, is_threadgroup: bool = false };

    fn parseType(self: *Parser, flags: *TypeFlags) Error!TypeRef {
        var ty: TypeRef = .{ .name = "", .line = self.peek().line, .col = self.peek().col };
        while (true) {
            if (self.eatKw("const")) {
                ty.is_const = true;
            } else if (self.eatKw("constant")) {
                ty.space = .constant;
            } else if (self.eatKw("thread")) {
                ty.space = .thread;
            } else if (self.eatKw("device")) {
                ty.space = .device;
            } else if (self.eatKw("threadgroup")) {
                ty.space = .threadgroup;
                flags.is_threadgroup = true;
            } else if (self.eatKw("constexpr")) {
                flags.is_constexpr = true;
                ty.is_const = true;
            } else if (self.eatKw("static")) {
                flags.is_static = true;
            } else if (self.eatKw("inline") or self.eatKw("volatile")) {} else break;
        }
        if (self.isKw("metal") and self.isPAt(1, "::")) {
            _ = self.advance();
            _ = self.advance();
        }
        var name = try self.expectIdent();
        if (std.mem.eql(u8, name, "unsigned")) {
            name = "uint";
            if (self.isKw("int") or self.isKw("char") or self.isKw("short")) {
                const w = self.advance().text;
                name = if (std.mem.eql(u8, w, "char")) "uchar" else if (std.mem.eql(u8, w, "short")) "ushort" else "uint";
            }
        } else if (std.mem.eql(u8, name, "signed")) {
            name = "int";
            if (self.isKw("int") or self.isKw("char") or self.isKw("short")) name = self.advance().text;
        }
        ty.name = name;
        if (self.isP("<") and (std.mem.eql(u8, name, "texture2d") or std.mem.eql(u8, name, "vec") or std.mem.eql(u8, name, "array"))) {
            _ = self.advance();
            var targs: std.ArrayList(TArg) = .empty;
            while (true) {
                const t = self.peek();
                if (t.tag == .int_lit) {
                    _ = self.advance();
                    try targs.append(self.a, .{ .int = std.fmt.parseInt(i64, std.mem.trimEnd(u8, t.text, "uUlL"), 0) catch 0 });
                } else if (t.tag == .ident and (self.isPAt(1, "::"))) {
                    var full: std.ArrayList(u8) = .empty;
                    try full.appendSlice(self.a, self.advance().text);
                    while (self.eatP("::")) {
                        try full.appendSlice(self.a, "::");
                        try full.appendSlice(self.a, try self.expectIdent());
                    }
                    try targs.append(self.a, .{ .name = full.items });
                } else {
                    var f2: TypeFlags = .{};
                    const inner = try self.new(TypeRef, try self.parseType(&f2));
                    try targs.append(self.a, .{ .ty = inner });
                }
                if (self.eatP(",")) continue;
                if (self.eatP(">")) break;
                if (self.isP(">>")) return self.failHere("nested template arguments ('>>') are not supported", .{});
                return self.failHere("expected ',' or '>' in template arguments", .{});
            }
            ty.targs = targs.items;
        }
        while (true) {
            if (self.eatKw("const")) {
                ty.is_const = true;
            } else if (self.eatP("&")) {
                ty.ref = true;
            } else if (self.eatP("*")) {
                ty.ptr += 1;
            } else if (self.isKw("thread") or self.isKw("constant") or self.isKw("device")) {
                // `float thread &x` style: an address space after the type
                const s = self.advance().text;
                ty.space = if (std.mem.eql(u8, s, "thread")) .thread else if (std.mem.eql(u8, s, "constant")) .constant else .device;
            } else break;
        }
        if (self.isP("&&")) return self.failHere("rvalue references are not supported", .{});
        return ty;
    }

    fn parseAttr(self: *Parser) Error!?Attr {
        if (!(self.isP("[") and self.isPAt(1, "["))) return null;
        _ = self.advance();
        _ = self.advance();
        const name = try self.expectIdent();
        var arg: ?i64 = null;
        if (self.eatP("(")) {
            const t = self.advance();
            if (t.tag == .int_lit) arg = std.fmt.parseInt(i64, std.mem.trimEnd(u8, t.text, "uUlL"), 0) catch null;
            while (!self.isP(")")) {
                if (self.peek().tag == .eof) return self.failHere("unterminated attribute", .{});
                _ = self.advance();
            }
            _ = self.advance();
        }
        try self.expectP("]");
        try self.expectP("]");
        return .{ .name = name, .arg = arg };
    }

    fn parseDims(self: *Parser) Error![]const ?*Expr {
        var dims: std.ArrayList(?*Expr) = .empty;
        while (self.isP("[") and !self.isPAt(1, "[")) {
            _ = self.advance();
            if (self.eatP("]")) {
                try dims.append(self.a, null);
                continue;
            }
            try dims.append(self.a, try self.parseExpr());
            try self.expectP("]");
        }
        return dims.items;
    }

    fn parseParams(self: *Parser) Error![]Param {
        try self.expectP("(");
        var ps: std.ArrayList(Param) = .empty;
        if (self.isKw("void") and self.isPAt(1, ")")) _ = self.advance();
        while (!self.eatP(")")) {
            const t = self.peek();
            var fl: TypeFlags = .{};
            const ty = try self.parseType(&fl);
            var p: Param = .{ .ty = ty, .name = "", .line = t.line, .col = t.col };
            if (self.peek().tag == .ident) p.name = self.advance().text;
            p.dims = try self.parseDims();
            p.attr = try self.parseAttr();
            if (self.eatP("=")) p.default = try self.parseAssign();
            try ps.append(self.a, p);
            if (!self.eatP(",")) {
                try self.expectP(")");
                break;
            }
        }
        return ps.items;
    }

    // ------------------------------------------------------------------ top level
    pub fn parseUnit(self: *Parser) Error![]Item {
        var items: std.ArrayList(Item) = .empty;
        while (self.peek().tag != .eof) {
            if (self.eatP(";")) continue;
            if (self.eatKw("using")) {
                if (self.eatKw("namespace")) {
                    _ = try self.expectIdent();
                    try self.expectP(";");
                    continue;
                }
                const name = try self.expectIdent();
                try self.expectP("=");
                var fl: TypeFlags = .{};
                const ty = try self.parseType(&fl);
                try self.expectP(";");
                try self.types.put(self.a, name, {});
                try items.append(self.a, .{ .typedef = .{ .name = name, .ty = ty } });
                continue;
            }
            if (self.eatKw("typedef")) {
                var fl: TypeFlags = .{};
                const ty = try self.parseType(&fl);
                const name = try self.expectIdent();
                try self.expectP(";");
                try self.types.put(self.a, name, {});
                try items.append(self.a, .{ .typedef = .{ .name = name, .ty = ty } });
                continue;
            }
            if (self.isKw("struct")) {
                try items.append(self.a, .{ .strct = try self.parseStruct() });
                continue;
            }
            var tparams: []const []const u8 = &.{};
            if (self.eatKw("template")) {
                try self.expectP("<");
                var tp: std.ArrayList([]const u8) = .empty;
                while (true) {
                    if (!(self.eatKw("typename") or self.eatKw("class"))) return self.failHere("only `typename` template parameters are supported", .{});
                    try tp.append(self.a, try self.expectIdent());
                    if (self.eatP(",")) continue;
                    try self.expectP(">");
                    break;
                }
                tparams = tp.items;
            }
            const is_kernel = self.eatKw("kernel") or blk: {
                if (self.isP("[") and self.isPAt(1, "[") and std.mem.eql(u8, self.peekAt(2).text, "kernel")) {
                    _ = try self.parseAttr();
                    break :blk true;
                }
                break :blk false;
            };
            const start = self.peek();
            if (!self.atTypeStart()) return self.failHere("expected a declaration, found '{s}'", .{start.text});
            self.tparams = tparams;
            defer self.tparams = &.{};
            var fl: TypeFlags = .{};
            const ty = try self.parseType(&fl);
            const name_tok = self.peek();
            const name = try self.expectIdent();
            if (self.isP("(") and !(fl.is_constexpr and std.mem.eql(u8, ty.name, "sampler"))) {
                const params = try self.parseParams();
                _ = try self.parseAttr();
                var body: ?*Stmt = null;
                if (!self.eatP(";")) body = try self.parseBlock();
                const f = try self.new(Func, .{ .name = name, .ret = ty, .params = params, .body = body, .tparams = tparams, .is_kernel = is_kernel, .line = name_tok.line, .col = name_tok.col, .index = self.func_count });
                self.func_count += 1;
                try items.append(self.a, .{ .func = f });
                continue;
            }
            if (tparams.len > 0) return self.failHere("template variables are not supported", .{});
            const decls = try self.parseDeclaratorsAfterName(name, name_tok);
            try items.append(self.a, .{ .global = try self.new(Global, .{ .ty = ty, .decls = decls, .is_constexpr = fl.is_constexpr, .line = start.line, .col = start.col }) });
        }
        return items.items;
    }

    fn parseStruct(self: *Parser) Error!*Struct {
        const t = self.advance();
        const name = try self.expectIdent();
        try self.types.put(self.a, name, {});
        try self.expectP("{");
        var fields: std.ArrayList(Field) = .empty;
        while (!self.eatP("}")) {
            const ft = self.peek();
            if (!self.atTypeStart()) return self.failHere("unsupported struct member '{s}' (only data fields are supported)", .{ft.text});
            var fl: TypeFlags = .{};
            const ty = try self.parseType(&fl);
            while (true) {
                const nt = self.peek();
                const fname = try self.expectIdent();
                if (self.isP("(")) return self.failHere("member functions in structs are not supported", .{});
                const dims = try self.parseDims();
                if (self.isP("=") or self.isP("{")) return self.failHere("default member initialisers are not supported", .{});
                try fields.append(self.a, .{ .ty = ty, .name = fname, .dims = dims, .line = nt.line, .col = nt.col });
                if (self.eatP(",")) continue;
                try self.expectP(";");
                break;
            }
        }
        try self.expectP(";");
        return self.new(Struct, .{ .name = name, .fields = fields.items, .line = t.line, .col = t.col });
    }

    fn parseDeclaratorsAfterName(self: *Parser, first: []const u8, first_tok: Token) Error![]Declarator {
        var decls: std.ArrayList(Declarator) = .empty;
        var name = first;
        var nt = first_tok;
        while (true) {
            var d: Declarator = .{ .name = name, .line = nt.line, .col = nt.col };
            d.dims = try self.parseDims();
            if (self.eatP("=")) {
                d.init = try self.parseAssign();
            } else if (self.isP("{")) {
                d.init = try self.parseInitList();
            } else if (self.isP("(")) {
                _ = self.advance();
                var args: std.ArrayList(*Expr) = .empty;
                while (!self.eatP(")")) {
                    try args.append(self.a, try self.parseAssign());
                    if (!self.eatP(",")) {
                        try self.expectP(")");
                        break;
                    }
                }
                d.ctor = args.items;
            }
            try decls.append(self.a, d);
            if (self.eatP(",")) {
                // a `*` or `&` per declarator is not supported; plain names only
                nt = self.peek();
                name = try self.expectIdent();
                continue;
            }
            try self.expectP(";");
            break;
        }
        return decls.items;
    }

    // ------------------------------------------------------------------ statements
    fn parseBlock(self: *Parser) Error!*Stmt {
        const t = self.peek();
        try self.expectP("{");
        var list: std.ArrayList(*Stmt) = .empty;
        while (!self.eatP("}")) {
            if (self.peek().tag == .eof) return self.failHere("unterminated block", .{});
            try list.append(self.a, try self.parseStmt());
        }
        return self.new(Stmt, .{ .line = t.line, .col = t.col, .kind = .{ .block = list.items } });
    }

    fn mk(self: *Parser, t: Token, k: Stmt.Kind) Error!*Stmt {
        return self.new(Stmt, .{ .line = t.line, .col = t.col, .kind = k });
    }

    /// A declaration starts here: a type, then a name (not `float3(...)` as an expression).
    fn atDecl(self: *Parser) bool {
        if (!self.atTypeStart()) return false;
        const t = self.peek();
        if (self.isTypeName(t.text) and (self.isPAt(1, "(") or self.isPAt(1, "{") or self.isPAt(1, "::"))) return false;
        return true;
    }

    fn parseStmt(self: *Parser) Error!*Stmt {
        const t = self.peek();
        if (self.isP("{")) return self.parseBlock();
        if (self.eatP(";")) return self.mk(t, .empty);
        if (self.eatKw("if")) {
            try self.expectP("(");
            const c = try self.parseExpr();
            try self.expectP(")");
            const then = try self.parseStmt();
            var els: ?*Stmt = null;
            if (self.eatKw("else")) els = try self.parseStmt();
            return self.mk(t, .{ .if_ = .{ .c = c, .then = then, .els = els } });
        }
        if (self.eatKw("for")) {
            try self.expectP("(");
            var init: ?*Stmt = null;
            if (!self.eatP(";")) {
                if (self.atDecl()) {
                    init = try self.parseDeclStmt();
                } else {
                    const e = try self.parseExpr();
                    try self.expectP(";");
                    init = try self.mk(t, .{ .expr = e });
                }
            }
            var cond: ?*Expr = null;
            if (!self.isP(";")) cond = try self.parseExpr();
            try self.expectP(";");
            var incr: ?*Expr = null;
            if (!self.isP(")")) incr = try self.parseExpr();
            try self.expectP(")");
            const body = try self.parseStmt();
            return self.mk(t, .{ .for_ = .{ .init = init, .cond = cond, .incr = incr, .body = body } });
        }
        if (self.eatKw("while")) {
            try self.expectP("(");
            const c = try self.parseExpr();
            try self.expectP(")");
            return self.mk(t, .{ .while_ = .{ .c = c, .body = try self.parseStmt() } });
        }
        if (self.eatKw("do")) {
            const body = try self.parseStmt();
            if (!self.eatKw("while")) return self.failHere("expected 'while' after a do body", .{});
            try self.expectP("(");
            const c = try self.parseExpr();
            try self.expectP(")");
            try self.expectP(";");
            return self.mk(t, .{ .do_while = .{ .body = body, .c = c } });
        }
        if (self.eatKw("return")) {
            if (self.eatP(";")) return self.mk(t, .{ .ret = null });
            const e = try self.parseExpr();
            try self.expectP(";");
            return self.mk(t, .{ .ret = e });
        }
        if (self.eatKw("break")) {
            try self.expectP(";");
            return self.mk(t, .brk);
        }
        if (self.eatKw("continue")) {
            try self.expectP(";");
            return self.mk(t, .cont);
        }
        if (self.eatKw("switch")) return self.parseSwitch(t);
        if (self.isKw("goto")) return self.failHere("goto is not supported", .{});
        if (self.atDecl()) return self.parseDeclStmt();
        const e = try self.parseExpr();
        try self.expectP(";");
        return self.mk(t, .{ .expr = e });
    }

    fn parseDeclStmt(self: *Parser) Error!*Stmt {
        const t = self.peek();
        var fl: TypeFlags = .{};
        const ty = try self.parseType(&fl);
        const nt = self.peek();
        const name = try self.expectIdent();
        const decls = try self.parseDeclaratorsAfterName(name, nt);
        return self.mk(t, .{ .decl = .{ .ty = ty, .decls = decls, .is_constexpr = fl.is_constexpr, .is_threadgroup = fl.is_threadgroup } });
    }

    fn parseSwitch(self: *Parser, t: Token) Error!*Stmt {
        try self.expectP("(");
        const e = try self.parseExpr();
        try self.expectP(")");
        try self.expectP("{");
        var cases: std.ArrayList(Case) = .empty;
        while (!self.eatP("}")) {
            const ct = self.peek();
            var c: Case = .{ .values = &.{}, .is_default = false, .body = &.{}, .line = ct.line };
            var vals: std.ArrayList(*Expr) = .empty;
            if (self.eatKw("case")) {
                try vals.append(self.a, try self.parseTernary());
                try self.expectP(":");
            } else if (self.eatKw("default")) {
                c.is_default = true;
                try self.expectP(":");
            } else return self.failHere("expected 'case' or 'default' in switch", .{});
            var body: std.ArrayList(*Stmt) = .empty;
            while (!self.isKw("case") and !self.isKw("default") and !self.isP("}")) {
                try body.append(self.a, try self.parseStmt());
            }
            c.values = vals.items;
            c.body = body.items;
            try cases.append(self.a, c);
        }
        return self.mk(t, .{ .switch_ = .{ .e = e, .cases = cases.items } });
    }

    // ------------------------------------------------------------------ expressions
    fn mkE(self: *Parser, t: Token, k: Expr.Kind) Error!*Expr {
        return self.new(Expr, .{ .line = t.line, .col = t.col, .kind = k });
    }

    pub fn parseExpr(self: *Parser) Error!*Expr {
        var e = try self.parseAssign();
        while (self.isP(",")) {
            const t = self.advance();
            const b = try self.parseAssign();
            e = try self.mkE(t, .{ .comma = .{ .a = e, .b = b } });
        }
        return e;
    }

    const assign_ops = [_][]const u8{ "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=" };

    fn parseAssign(self: *Parser) Error!*Expr {
        if (self.isP("{")) return self.parseInitList();
        const lhs = try self.parseTernary();
        const t = self.peek();
        if (t.tag == .punct) for (assign_ops) |op| {
            if (std.mem.eql(u8, t.text, op)) {
                _ = self.advance();
                const rhs = try self.parseAssign();
                return self.mkE(t, .{ .assign = .{ .op = op, .lhs = lhs, .rhs = rhs } });
            }
        };
        return lhs;
    }

    fn parseTernary(self: *Parser) Error!*Expr {
        const c = try self.parseBin(0);
        if (self.isP("?")) {
            const t = self.advance();
            const a = try self.parseAssign();
            try self.expectP(":");
            const b = try self.parseAssign();
            return self.mkE(t, .{ .ternary = .{ .c = c, .a = a, .b = b } });
        }
        return c;
    }

    const levels = [_][]const []const u8{
        &.{"||"},         &.{"&&"},                   &.{"|"},          &.{"^"},        &.{"&"},
        &.{ "==", "!=" }, &.{ "<", ">", "<=", ">=" }, &.{ "<<", ">>" }, &.{ "+", "-" }, &.{ "*", "/", "%" },
    };

    fn parseBin(self: *Parser, level: usize) Error!*Expr {
        if (level == levels.len) return self.parseUnary();
        var e = try self.parseBin(level + 1);
        while (true) {
            const t = self.peek();
            if (t.tag != .punct) break;
            var found: ?[]const u8 = null;
            for (levels[level]) |op| if (std.mem.eql(u8, t.text, op)) {
                found = op;
            };
            const op = found orelse break;
            _ = self.advance();
            const b = try self.parseBin(level + 1);
            e = try self.mkE(t, .{ .binary = .{ .op = op, .a = e, .b = b } });
        }
        return e;
    }

    fn parseUnary(self: *Parser) Error!*Expr {
        const t = self.peek();
        if (t.tag == .punct) {
            for ([_][]const u8{ "-", "+", "!", "~", "++", "--", "*", "&" }) |op| {
                if (std.mem.eql(u8, t.text, op)) {
                    _ = self.advance();
                    const e = try self.parseUnary();
                    return self.mkE(t, .{ .unary = .{ .op = op, .e = e } });
                }
            }
            // C-style cast: `(type) expr`
            if (std.mem.eql(u8, t.text, "(") and self.peekAt(1).tag == .ident and self.isTypeName(self.peekAt(1).text)) {
                const save = self.pos;
                _ = self.advance();
                var fl: TypeFlags = .{};
                const ty = self.parseType(&fl) catch null;
                if (ty != null and self.eatP(")")) {
                    const e = try self.parseUnary();
                    return self.mkE(t, .{ .cast = .{ .ty = ty.?, .e = e } });
                }
                self.pos = save;
            }
        }
        return self.parsePostfix();
    }

    fn parseArgs(self: *Parser) Error![]*Expr {
        try self.expectP("(");
        var args: std.ArrayList(*Expr) = .empty;
        while (!self.eatP(")")) {
            try args.append(self.a, try self.parseAssign());
            if (!self.eatP(",")) {
                try self.expectP(")");
                break;
            }
        }
        return args.items;
    }

    fn parsePostfix(self: *Parser) Error!*Expr {
        var e = try self.parsePrimary();
        while (true) {
            const t = self.peek();
            if (self.isP("(")) {
                const args = try self.parseArgs();
                e = try self.mkE(t, .{ .call = .{ .callee = e, .args = args } });
            } else if (self.isP("[") and !self.isPAt(1, "[")) {
                _ = self.advance();
                const i = try self.parseExpr();
                try self.expectP("]");
                e = try self.mkE(t, .{ .index = .{ .e = e, .i = i } });
            } else if (self.isP(".") or self.isP("->")) {
                const arrow = self.advance().text.len == 2;
                const name = try self.expectIdent();
                e = try self.mkE(t, .{ .member = .{ .e = e, .name = name, .arrow = arrow } });
            } else if (self.isP("++") or self.isP("--")) {
                const op = self.advance().text;
                e = try self.mkE(t, .{ .postfix = .{ .op = op, .e = e } });
            } else break;
        }
        return e;
    }

    fn parseInitList(self: *Parser) Error!*Expr {
        const t = self.peek();
        try self.expectP("{");
        var items: std.ArrayList(*Expr) = .empty;
        while (!self.eatP("}")) {
            try items.append(self.a, try self.parseAssign());
            if (!self.eatP(",")) {
                try self.expectP("}");
                break;
            }
        }
        return self.mkE(t, .{ .init_list = items.items });
    }

    fn parseLambda(self: *Parser) Error!*Expr {
        const t = self.advance(); // [
        var by_ref = false;
        while (!self.eatP("]")) {
            const c = self.advance();
            if (c.tag == .punct and std.mem.eql(u8, c.text, "&")) by_ref = true;
            if (c.tag == .ident) return lex.fail(self.a, self.diag, c.line, c.col, "lambda captures by name are not supported (use [&] or [=])", .{});
            if (c.tag == .eof) return self.failHere("unterminated lambda capture list", .{});
        }
        const params: []Param = if (self.isP("(")) try self.parseParams() else &.{};
        _ = self.eatKw("mutable");
        var ret: ?TypeRef = null;
        if (self.eatP("->")) {
            var fl: TypeFlags = .{};
            ret = try self.parseType(&fl);
        }
        const body = try self.parseBlock();
        const l = try self.new(Lambda, .{ .by_ref = by_ref, .params = params, .ret = ret, .body = body, .line = t.line, .col = t.col });
        return self.mkE(t, .{ .lambda = l });
    }

    fn parsePrimary(self: *Parser) Error!*Expr {
        const t = self.peek();
        switch (t.tag) {
            .int_lit => {
                _ = self.advance();
                var txt = t.text;
                var unsigned = false;
                while (txt.len > 0 and std.mem.findScalar(u8, "uUlL", txt[txt.len - 1]) != null) {
                    if (txt[txt.len - 1] == 'u' or txt[txt.len - 1] == 'U') unsigned = true;
                    txt = txt[0 .. txt.len - 1];
                }
                const is_hex = txt.len > 1 and txt[0] == '0' and (txt[1] == 'x' or txt[1] == 'X');
                const v: u64 = if (is_hex)
                    std.fmt.parseInt(u64, txt[2..], 16) catch return self.failHere("bad integer literal '{s}'", .{t.text})
                else if (txt.len > 1 and txt[0] == '0')
                    std.fmt.parseInt(u64, txt[1..], 8) catch return self.failHere("bad integer literal '{s}'", .{t.text})
                else
                    std.fmt.parseInt(u64, txt, 10) catch return self.failHere("bad integer literal '{s}'", .{t.text});
                if (v > 0xffffffff) return self.failHere("integer literal '{s}' does not fit 32 bits", .{t.text});
                if (v > 0x7fffffff) unsigned = true;
                return self.mkE(t, .{ .int_lit = .{ .value = v, .unsigned = unsigned } });
            },
            .float_lit => {
                _ = self.advance();
                var txt = t.text;
                while (txt.len > 0 and std.mem.findScalar(u8, "fFhHlL", txt[txt.len - 1]) != null) txt = txt[0 .. txt.len - 1];
                return self.mkE(t, .{ .float_lit = txt });
            },
            .char_lit => {
                _ = self.advance();
                const body = try lex.unescape(self.a, t.text[1 .. t.text.len - 1]);
                if (body.len != 1) return self.failHere("multi-character literal {s}", .{t.text});
                return self.mkE(t, .{ .char_lit = body[0] });
            },
            .str_lit => {
                _ = self.advance();
                var s: std.ArrayList(u8) = .empty;
                try s.appendSlice(self.a, try lex.unescape(self.a, t.text[1 .. t.text.len - 1]));
                // adjacent literals concatenate
                while (self.peek().tag == .str_lit) {
                    const n = self.advance();
                    try s.appendSlice(self.a, try lex.unescape(self.a, n.text[1 .. n.text.len - 1]));
                }
                return self.mkE(t, .{ .str_lit = s.items });
            },
            .punct => {
                if (self.isP("(")) {
                    _ = self.advance();
                    const e = try self.parseExpr();
                    try self.expectP(")");
                    return e;
                }
                if (self.isP("[")) return self.parseLambda();
                if (self.isP("{")) return self.parseInitList();
                if (self.isP("::")) {
                    _ = self.advance();
                    return self.parsePrimary();
                }
                return self.failHere("unexpected '{s}' in an expression", .{t.text});
            },
            .ident => {
                if (self.eatKw("true")) return self.mkE(t, .{ .bool_lit = true });
                if (self.eatKw("false")) return self.mkE(t, .{ .bool_lit = false });
                if (self.isKw("metal") and self.isPAt(1, "::")) {
                    _ = self.advance();
                    _ = self.advance();
                    return self.parsePrimary();
                }
                for ([_][]const u8{ "static_cast", "reinterpret_cast", "as_type" }) |kw| {
                    if (!self.isKw(kw)) continue;
                    _ = self.advance();
                    try self.expectP("<");
                    var fl: TypeFlags = .{};
                    const ty = try self.parseType(&fl);
                    try self.expectP(">");
                    const args = try self.parseArgs();
                    if (std.mem.eql(u8, kw, "reinterpret_cast")) return lex.fail(self.a, self.diag, t.line, t.col, "reinterpret_cast is not supported", .{});
                    const callee = try self.mkE(t, .{ .ident = kw });
                    const targs = try self.a.alloc(TypeRef, 1);
                    targs[0] = ty;
                    return self.mkE(t, .{ .call = .{ .callee = callee, .args = args, .targs = targs } });
                }
                if (self.isKw("sizeof")) return self.failHere("sizeof is not supported", .{});
                // a type used as a value: `float3(...)`, `Line{...}`, `vec<float, 3>(...)`
                if (self.isTypeName(t.text) and (self.isPAt(1, "{") or self.isPAt(1, "<"))) {
                    var fl: TypeFlags = .{};
                    const ty = try self.parseType(&fl);
                    if (self.isP("{")) {
                        const il = try self.parseInitList();
                        return self.mkE(t, .{ .construct = .{ .ty = ty, .args = il.kind.init_list } });
                    }
                    const args = try self.parseArgs();
                    return self.mkE(t, .{ .construct = .{ .ty = ty, .args = args } });
                }
                _ = self.advance();
                var name = t.text;
                if (self.isP("::")) {
                    var full: std.ArrayList(u8) = .empty;
                    try full.appendSlice(self.a, name);
                    while (self.eatP("::")) {
                        try full.appendSlice(self.a, "::");
                        try full.appendSlice(self.a, try self.expectIdent());
                    }
                    name = full.items;
                }
                return self.mkE(t, .{ .ident = name });
            },
            else => return self.failHere("unexpected end of file", .{}),
        }
    }
};

pub fn parse(a: Allocator, toks: []const Token, diag: *Diag) Error![]Item {
    var p: Parser = .{ .a = a, .diag = diag, .toks = toks };
    return p.parseUnit();
}

test "parser: a kernel with a lambda, a template and a struct" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: Diag = .{};
    const src =
        \\struct Blk { float2 c; float2 h; };
        \\template <typename T> static T twice(T x) { return x + x; }
        \\constant float K[3] = { 1.0f, 2.0f, 3.0f };
        \\kernel void argus_draw(constant ArgusFrame& f [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        \\    auto at = [&](int dx) { return float(dx) * K[1]; };
        \\    Blk b; b.c.xy = float2(at(1), twice(2.0f));
        \\    out.write(float4(b.c, 0.0f, 1.0f), gid);
        \\}
    ;
    const toks = try lex.lex(a, src, &d);
    const items = try parse(a, toks, &d);
    try std.testing.expectEqual(@as(usize, 4), items.len);
    try std.testing.expect(items[3].func.is_kernel);
    try std.testing.expectEqual(@as(usize, 3), items[3].func.params.len);
    try std.testing.expectEqualStrings("buffer", items[3].func.params[0].attr.?.name);
}

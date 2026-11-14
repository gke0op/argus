//! msl2wgsl lowering: type inference over the parsed Metal AST and WGSL emission.
//!
//! Metal (C++) converts between int, uint, float and bool implicitly, overloads functions, has
//! references, pointers, templates and lambdas; WGSL has none of these. Every expression is typed
//! here, and the WGSL is written with every conversion explicit:
//!   - conversions: usual arithmetic conversions, scalar-to-vector splats, bool contexts;
//!   - overloads and templates: resolved per call and instantiated per distinct argument shape
//!     (a function called with two textures, two lambdas or two pointer kinds becomes two WGSL
//!     functions);
//!   - textures, samplers, the frame and the stats buffer are module-scope bindings in WGSL, so
//!     parameters of those types disappear and their uses name the binding;
//!   - `thread T&` becomes `ptr<function, T>`; `thread T*` into an array becomes the array's
//!     pointer plus an offset; `constant char*` strings live in one constant pool;
//!   - lambdas become functions whose captures are extra parameters (pointers when written);
//!   - ternaries become select() when both sides are cheap and pure, else an if/else;
//!   - side effects inside expressions (x++, assignments, impure ternaries) become statements
//!     before the statement that uses them, in evaluation order.
//! Anything outside the subset fails with the construct named, never with silent wrong code.
const std = @import("std");
const Allocator = std.mem.Allocator;
const lex = @import("lex.zig");
const P = @import("parse.zig");
const Error = lex.Error;

// ======================================================================================= types
pub const Scalar = enum(u8) { bool, i32, u32, f32 };
pub const Access = enum { sample, read, write };

pub const Type = union(enum) {
    void,
    scalar: Scalar,
    vec: struct { s: Scalar, n: u8 },
    mat: struct { c: u8, r: u8 },
    strct: u32,
    array: struct { elem: *const Type, len: u32 },
    atomic: Scalar,
    texture: Access,
    sampler,
    ptr: *const Type,
    lambda,
    auto,
};

fn eql(a: Type, b: Type) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .void, .sampler, .lambda, .auto => true,
        .scalar => |s| s == b.scalar,
        .vec => |v| v.s == b.vec.s and v.n == b.vec.n,
        .mat => |m| m.c == b.mat.c and m.r == b.mat.r,
        .strct => |i| i == b.strct,
        .array => |x| x.len == b.array.len and eql(x.elem.*, b.array.elem.*),
        .atomic => |s| s == b.atomic,
        .texture => |t| t == b.texture,
        .ptr => |p| eql(p.*, b.ptr.*),
    };
}

fn shape(s: Scalar, n: u8) Type {
    return if (n <= 1) .{ .scalar = s } else .{ .vec = .{ .s = s, .n = n } };
}
fn scalarOf(t: Type) ?Scalar {
    return switch (t) {
        .scalar => |s| s,
        .vec => |v| v.s,
        else => null,
    };
}
fn widthOf(t: Type) u8 {
    return switch (t) {
        .vec => |v| v.n,
        else => 1,
    };
}
fn rank(s: Scalar) u8 {
    return @backingInt(s);
}
fn promote(s: Scalar) Scalar {
    return if (s == .bool) .i32 else s;
}
fn maxScalar(a: Scalar, b: Scalar) Scalar {
    return if (rank(a) >= rank(b)) a else b;
}

const Field = struct { name: []const u8, wname: []const u8, ty: Type };
const StructInfo = struct { name: []const u8, wname: []const u8, fields: []Field };

// ======================================================================================= values
const SymKind = enum { let_, var_, ptr, gconst, static_ };

const PtrKind = enum { local, pool, proc };
const PtrVal = struct {
    kind: PtrKind,
    ref: []const u8 = "", // local: the array reference text (`b` or `(*b)`); proc: the index
    ptr: []const u8 = "", // local: the pointer text (`&b` or `b`)
    off: []const u8 = "0i",
    elem: Type,
    n: u32 = 0,
    writable: bool = false,
};

const SamplerVal = struct { g: []const u8, pixel: bool };

const Special = union(enum) {
    none,
    texture: []const u8,
    sampler: SamplerVal,
    lambda: *LambdaVal,
    ptr: PtrVal,
    frame,
    stats,
    typename: Type,
    procs,
    funcs: []const u8,
    level: []const u8,
};

const Sym = struct {
    name: []const u8,
    wname: []const u8,
    kind: SymKind,
    ty: Type,
    special: Special = .none,
    ival: ?i64 = null,
    param: bool = false,
    needs_var: bool = false,
    flat_inner: u32 = 0,
    workgroup: bool = false,
    helper: ?[]const u8 = null, // a WGSL declaration to emit when this name is used (M_PI_F)
};

const Lv = enum { none, let_, ref };
const Lit = union(enum) { int: i64, float: []const u8, boolean: bool };

const Swz = struct { base: []const u8, comps: []const u8 };
const Flat = struct { name: []const u8, row: []const u8, inner: u32, elem: Type };

const Val = struct {
    ty: Type,
    text: []const u8,
    lv: Lv = .none,
    addr: ?[]const u8 = null,
    lit: ?Lit = null,
    pure: bool = true,
    cheap: bool = true,
    swz: ?Swz = null,
    special: Special = .none,
    psym: ?*Sym = null,
    proc_idx: ?[]const u8 = null,
    flat: ?Flat = null,
    workgroup: bool = false,
};

const CapMode = enum { value, ref, static_ };
const Capture = struct { name: []const u8, sym: *Sym, mode: CapMode };
const LambdaDef = struct { ast: *P.Lambda, caps: []Capture, id: u32, name: []const u8 };
const LambdaVal = struct { def: *LambdaDef, env: []const []const u8 };

const Bind = union(enum) {
    value: Type,
    ref: Type,
    erased: Special,
    garray: *Sym,
    lambda: *LambdaVal,
    ptr: struct { kind: PtrKind, elem: Type, n: u32, writable: bool },
};

const TBind = struct { name: []const u8, ty: Type };

const Instance = struct {
    key: []const u8,
    name: []const u8,
    func: ?*P.Func,
    ldef: ?*LambdaDef = null,
    binds: []Bind,
    tbinds: []TBind,
    ret: Type,
    text: []const u8 = "",
    state: enum { pending, busy, done } = .pending,
    impure: bool = false,
};

const KernelKind = enum { init, step, draw };

const Ctx = struct {
    out: *std.ArrayList(u8),
    indent: usize = 1,
    scope: std.ArrayList(*Sym) = .empty,
    ret: ?Type = null,
    infer_ret: bool = false,
    inst: ?*Instance = null,
    kernel: ?KernelKind = null,
    retry: bool = false,
    global: bool = false,
    tbinds: []TBind = &.{},
    owner: []const u8 = "",
    wg_size: u32 = 8,
};

// ======================================================================================= tables
const reserved = [_][]const u8{
    // WGSL keywords and reserved words
    "alias",                 "break",                 "case",                "const",              "const_assert",  "continue",          "continuing",         "default",            "diagnostic",
    "discard",               "else",                  "enable",              "false",              "fn",            "for",               "if",                 "let",                "loop",
    "override",              "requires",              "return",              "struct",             "switch",        "true",              "var",                "while",              "NULL",
    "Self",                  "abstract",              "active",              "alignas",            "alignof",       "as",                "asm",                "asm_fragment",       "async",
    "attribute",             "auto",                  "await",               "become",             "binding_array", "cast",              "catch",              "class",              "co_await",
    "co_return",             "co_yield",              "coherent",            "column_major",       "common",        "compile",           "compile_fragment",   "concept",            "const_cast",
    "consteval",             "constexpr",             "constinit",           "crate",              "debugger",      "decltype",          "delete",             "demote",             "demote_to_helper",
    "do",                    "dynamic_cast",          "enum",                "explicit",           "export",        "extends",           "extern",             "external",           "fallthrough",
    "filter",                "final",                 "finally",             "friend",             "from",          "fxgroup",           "get",                "goto",               "groupshared",
    "highp",                 "impl",                  "implements",          "import",             "inline",        "instanceof",        "interface",          "layout",             "lowp",
    "macro",                 "macro_rules",           "match",               "mediump",            "meta",          "mod",               "module",             "move",               "mut",
    "mutable",               "namespace",             "new",                 "nil",                "noexcept",      "noinline",          "nointerpolation",    "noperspective",      "null",
    "nullptr",               "of",                    "operator",            "package",            "packoffset",    "partition",         "pass",               "patch",              "pixelfragment",
    "precise",               "precision",             "premerge",            "priv",               "protected",     "pub",               "public",             "readonly",           "ref",
    "regardless",            "register",              "reinterpret_cast",    "require",            "resource",      "restrict",          "self",               "set",                "shared",
    "sizeof",                "smooth",                "snorm",               "static",             "static_assert", "static_cast",       "std",                "subroutine",         "super",
    "target",                "template",              "this",                "thread_local",       "throw",         "trait",             "try",                "type",               "typedef",
    "typeid",                "typename",              "typeof",              "union",              "unless",        "unorm",             "unsafe",             "unsized",            "use",
    "using",                 "varying",               "virtual",             "volatile",           "wgsl",          "where",             "with",               "writeonly",          "yield",
    // predeclared types
    "bool",                  "f16",                   "f32",                 "i32",                "u32",           "vec2",              "vec3",               "vec4",               "mat2x2",
    "mat3x3",                "mat4x4",                "array",               "atomic",             "ptr",           "sampler",           "sampler_comparison", "texture_2d",         "texture_storage_2d",
    "vec2f",                 "vec3f",                 "vec4f",               "vec2i",              "vec3i",         "vec4i",             "vec2u",              "vec3u",              "vec4u",
    // builtin functions
    "abs",                   "acos",                  "acosh",               "all",                "any",           "arrayLength",       "asin",               "asinh",              "atan",
    "atan2",                 "atanh",                 "bitcast",             "ceil",               "clamp",         "cos",               "cosh",               "countLeadingZeros",  "countOneBits",
    "countTrailingZeros",    "cross",                 "degrees",             "determinant",        "distance",      "dot",               "exp",                "exp2",               "extractBits",
    "faceForward",           "firstLeadingBit",       "firstTrailingBit",    "floor",              "fma",           "fract",             "frexp",              "insertBits",         "inverseSqrt",
    "ldexp",                 "length",                "log",                 "log2",               "max",           "min",               "mix",                "modf",               "normalize",
    "pow",                   "quantizeToF16",         "radians",             "reflect",            "refract",       "reverseBits",       "round",              "saturate",           "select",
    "sign",                  "sin",                   "sinh",                "smoothstep",         "sqrt",          "step",              "tan",                "tanh",               "transpose",
    "trunc",                 "textureDimensions",     "textureLoad",         "textureSampleLevel", "textureStore",  "workgroupBarrier",  "storageBarrier",     "atomicLoad",         "atomicStore",
    "atomicAdd",             "atomicSub",             "atomicMax",           "atomicMin",          "atomicAnd",     "atomicOr",          "atomicXor",          "atomicExchange",     "textureSample",
    // the WGSL prelude's module-scope names
    "f",                     "s",                     "argus_state",         "argus_state_out",    "argus_data",    "argus_out",         "argus_vitals",       "argus_linear_clamp", "argus_linear_repeat",
    "argus_linear_repeat_s", "argus_linear_repeat_t", "argus_nearest_clamp", "argus_proc_char",    "argus_sample",  "argus_clear_state", "ArgusVitals",
};

fn isReserved(n: []const u8) bool {
    for (reserved) |r| if (std.mem.eql(u8, r, n)) return true;
    return std.mem.startsWith(u8, n, "m2w_") or std.mem.startsWith(u8, n, "__");
}

const PreludeFn = struct { name: []const u8, params: []const Type, ret: Type };

const t_f32: Type = .{ .scalar = .f32 };
const t_i32: Type = .{ .scalar = .i32 };
const t_u32: Type = .{ .scalar = .u32 };
const t_bool: Type = .{ .scalar = .bool };
const t_v2f: Type = .{ .vec = .{ .s = .f32, .n = 2 } };
const t_v3f: Type = .{ .vec = .{ .s = .f32, .n = 3 } };
const t_v4f: Type = .{ .vec = .{ .s = .f32, .n = 4 } };
const t_v2u: Type = .{ .vec = .{ .s = .u32, .n = 2 } };
const t_frame: Type = .{ .strct = 0 };

const prelude_fns = [_]PreludeFn{
    .{ .name = "argus_days_j2000", .params = &.{t_frame}, .ret = t_f32 },
    .{ .name = "argus_utc_seconds", .params = &.{t_frame}, .ret = t_f32 },
    .{ .name = "argus_uv", .params = &.{ t_v2u, t_frame }, .ret = t_v2f },
    .{ .name = "argus_uv01", .params = &.{ t_v2u, t_u32, t_u32 }, .ret = t_v2f },
    .{ .name = "argus_hash", .params = &.{t_u32}, .ret = t_u32 },
    .{ .name = "argus_rand", .params = &.{ t_v2u, t_u32 }, .ret = t_f32 },
    .{ .name = "argus_noise", .params = &.{t_v2f}, .ret = t_f32 },
    .{ .name = "argus_fbm", .params = &.{ t_v2f, t_i32 }, .ret = t_f32 },
    .{ .name = "argus_palette", .params = &.{ t_f32, t_v3f, t_v3f, t_v3f, t_v3f }, .ret = t_v3f },
    .{ .name = "argus_srgb", .params = &.{t_v3f}, .ret = t_v3f },
    .{ .name = "argus_aces", .params = &.{t_v3f}, .ret = t_v3f },
};

const MathConst = struct { name: []const u8, value: []const u8 };
const math_consts = [_]MathConst{
    .{ .name = "M_PI_F", .value = "3.14159265358979323846f" },
    .{ .name = "M_PI_2_F", .value = "1.57079632679489661923f" },
    .{ .name = "M_PI_4_F", .value = "0.78539816339744830962f" },
    .{ .name = "M_1_PI_F", .value = "0.31830988618379067154f" },
    .{ .name = "M_2_PI_F", .value = "0.63661977236758134308f" },
    .{ .name = "M_2_SQRTPI_F", .value = "1.12837916709551257390f" },
    .{ .name = "M_SQRT2_F", .value = "1.41421356237309504880f" },
    .{ .name = "M_SQRT1_2_F", .value = "0.70710678118654752440f" },
    .{ .name = "M_E_F", .value = "2.71828182845904523536f" },
    .{ .name = "M_LN2_F", .value = "0.69314718055994530942f" },
    .{ .name = "M_LN10_F", .value = "2.30258509299404568402f" },
    .{ .name = "M_LOG2E_F", .value = "1.44269504088896340736f" },
    .{ .name = "M_LOG10E_F", .value = "0.43429448190325182765f" },
    .{ .name = "FLT_MAX", .value = "3.40282346638528859812e+38f" },
    .{ .name = "MAXFLOAT", .value = "3.40282346638528859812e+38f" },
    .{ .name = "FLT_MIN", .value = "1.17549435082228750797e-38f" },
    .{ .name = "FLT_EPSILON", .value = "1.1920928955078125e-07f" },
};

// ======================================================================================= lowerer
pub const Lowerer = struct {
    a: Allocator,
    diag: *lex.Diag,
    structs: std.ArrayList(StructInfo) = .empty,
    struct_idx: std.StringHashMapUnmanaged(u32) = .empty,
    typedefs: std.StringHashMapUnmanaged(P.TypeRef) = .empty,
    funcs: std.StringHashMapUnmanaged(std.ArrayList(*P.Func)) = .empty,
    globals: std.StringHashMapUnmanaged(*Sym) = .empty,
    pool: std.ArrayList(i32) = .empty,
    pool_idx: std.StringHashMapUnmanaged(u32) = .empty,
    insts: std.ArrayList(*Instance) = .empty,
    inst_idx: std.StringHashMapUnmanaged(*Instance) = .empty,
    ldefs: std.StringHashMapUnmanaged(*LambdaDef) = .empty,
    helpers: std.ArrayList(u8) = .empty,
    helper_set: std.StringHashMapUnmanaged(void) = .empty,
    wg_vars: std.ArrayList(u8) = .empty,
    decls: std.ArrayList(u8) = .empty,
    kernels: std.ArrayList(u8) = .empty,
    used: std.StringHashMapUnmanaged(void) = .empty,
    tmp: u32 = 0,
    lambda_count: u32 = 0,
    pending_copyback: std.ArrayList([]const u8) = .empty,
    /// Instances created, in order (keys and names), so a discarded lowering pass can drop
    /// the ones it made.
    inst_log: std.ArrayList(*Instance) = .empty,
    ctx: *Ctx = undefined,

    // ----------------------------------------------------------------- utilities
    fn err(self: *Lowerer, at_line: u32, col: u32, comptime fmt: []const u8, args: anytype) Error {
        return lex.fail(self.a, self.diag, at_line, col, fmt, args);
    }
    fn errE(self: *Lowerer, e: *const P.Expr, comptime fmt: []const u8, args: anytype) Error {
        return lex.fail(self.a, self.diag, e.line, e.col, fmt, args);
    }
    fn p(self: *Lowerer, comptime fmt: []const u8, args: anytype) Error![]const u8 {
        return std.fmt.allocPrint(self.a, fmt, args);
    }
    fn line(self: *Lowerer, comptime fmt: []const u8, args: anytype) Error!void {
        const out = self.ctx.out;
        for (0..self.ctx.indent) |_| try out.appendSlice(self.a, "    ");
        try out.print(self.a, fmt, args);
        try out.append(self.a, '\n');
    }
    fn newTmp(self: *Lowerer) Error![]const u8 {
        self.tmp += 1;
        return self.p("m2w_{d}", .{self.tmp});
    }
    fn wname(self: *Lowerer, n: []const u8) Error![]const u8 {
        if (isReserved(n)) return self.p("{s}_", .{n});
        return n;
    }
    fn uniqueName(self: *Lowerer, base: []const u8) Error![]const u8 {
        var name = try self.wname(base);
        var k: u32 = 2;
        while (self.used.contains(name)) : (k += 1) name = try self.p("{s}_{d}", .{ try self.wname(base), k });
        try self.used.put(self.a, name, {});
        return name;
    }
    fn needHelper(self: *Lowerer, key: []const u8, text: []const u8) Error!void {
        if (self.helper_set.contains(key)) return;
        try self.helper_set.put(self.a, key, {});
        try self.helpers.appendSlice(self.a, text);
    }

    fn beginCapture(self: *Lowerer, extra_indent: usize) Error!struct { old: *std.ArrayList(u8), old_indent: usize } {
        const buf = try self.a.create(std.ArrayList(u8));
        buf.* = .empty;
        const old = self.ctx.out;
        const oi = self.ctx.indent;
        self.ctx.out = buf;
        self.ctx.indent += extra_indent;
        return .{ .old = old, .old_indent = oi };
    }
    fn endCapture(self: *Lowerer, saved: anytype) []const u8 {
        const txt = self.ctx.out.items;
        self.ctx.out = saved.old;
        self.ctx.indent = saved.old_indent;
        return txt;
    }
    fn raw(self: *Lowerer, txt: []const u8) Error!void {
        try self.ctx.out.appendSlice(self.a, txt);
    }

    // ----------------------------------------------------------------- type text
    pub fn tyText(self: *Lowerer, t: Type) Error![]const u8 {
        return switch (t) {
            .void => "void",
            .scalar => |s| scalarText(s),
            .vec => |v| switch (v.s) {
                .f32 => self.p("vec{d}f", .{v.n}),
                .i32 => self.p("vec{d}i", .{v.n}),
                .u32 => self.p("vec{d}u", .{v.n}),
                .bool => self.p("vec{d}<bool>", .{v.n}),
            },
            .mat => |m| self.p("mat{d}x{d}f", .{ m.c, m.r }),
            .strct => |i| self.structs.items[i].wname,
            .array => |x| self.p("array<{s}, {d}>", .{ try self.tyText(x.elem.*), x.len }),
            .atomic => |s| self.p("atomic<{s}>", .{scalarText(s)}),
            .texture => "texture",
            .sampler => "sampler",
            .ptr => "i32", // stored pointers are offsets into the string pool (see coerce)
            .lambda => "lambda",
            .auto => "auto",
        };
    }
    fn scalarText(s: Scalar) []const u8 {
        return switch (s) {
            .bool => "bool",
            .i32 => "i32",
            .u32 => "u32",
            .f32 => "f32",
        };
    }
    fn mslName(self: *Lowerer, t: Type) Error![]const u8 {
        return switch (t) {
            .scalar => |s| switch (s) {
                .bool => "bool",
                .i32 => "int",
                .u32 => "uint",
                .f32 => "float",
            },
            .vec => |v| self.p("{s}{d}", .{ try self.mslName(.{ .scalar = v.s }), v.n }),
            .mat => |m| self.p("float{d}x{d}", .{ m.c, m.r }),
            .strct => |i| self.structs.items[i].name,
            .array => |x| self.p("{s}[{d}]", .{ try self.mslName(x.elem.*), x.len }),
            else => self.tyText(t),
        };
    }

    fn newType(self: *Lowerer, t: Type) Error!*const Type {
        const q = try self.a.create(Type);
        q.* = t;
        return q;
    }

    // ----------------------------------------------------------------- type resolution
    fn tbindLookup(self: *Lowerer, name: []const u8) ?Type {
        for (self.ctx.tbinds) |b| if (std.mem.eql(u8, b.name, name)) return b.ty;
        return null;
    }

    fn baseType(self: *Lowerer, tr: P.TypeRef) Error!Type {
        const n = tr.name;
        if (self.tbindLookup(n)) |t| return t;
        if (self.typedefs.get(n)) |td| {
            var inner = td;
            inner.is_const = inner.is_const or tr.is_const;
            return self.baseType(inner);
        }
        if (self.struct_idx.get(n)) |i| return .{ .strct = i };
        if (std.mem.eql(u8, n, "void")) return .void;
        if (std.mem.eql(u8, n, "auto")) return .auto;
        if (std.mem.eql(u8, n, "sampler")) return .sampler;
        if (std.mem.eql(u8, n, "atomic_uint")) return .{ .atomic = .u32 };
        if (std.mem.eql(u8, n, "atomic_int")) return .{ .atomic = .i32 };
        if (std.mem.eql(u8, n, "texture2d")) {
            var acc: Access = .sample;
            for (tr.targs) |ta| switch (ta) {
                .name => |an| {
                    if (std.mem.endsWith(u8, an, "::read")) acc = .read else if (std.mem.endsWith(u8, an, "::write")) acc = .write else if (std.mem.endsWith(u8, an, "::sample")) acc = .sample else return self.err(tr.line, tr.col, "texture access '{s}' is not supported (read, write and sample are)", .{an});
                },
                .ty => |t| {
                    const et = try self.baseType(t.*);
                    if (!(et == .scalar and (et.scalar == .f32))) return self.err(tr.line, tr.col, "only texture2d<float> (or half) textures are supported", .{});
                },
                .int => {},
            };
            return .{ .texture = acc };
        }
        if (std.mem.eql(u8, n, "vec")) {
            if (tr.targs.len != 2 or tr.targs[0] != .ty or tr.targs[1] != .int) return self.err(tr.line, tr.col, "vec<T, N> needs a type and a size", .{});
            const et = try self.baseType(tr.targs[0].ty.*);
            const s = scalarOf(et) orelse return self.err(tr.line, tr.col, "vec<T, N> of a non-scalar", .{});
            return shape(s, @intCast(tr.targs[1].int));
        }
        if (std.mem.startsWith(u8, n, "packed_")) return self.baseType(.{ .name = n["packed_".len..], .line = tr.line, .col = tr.col });
        const scalars = [_]struct { []const u8, Scalar }{
            .{ "bool", .bool },    .{ "char", .i32 },    .{ "uchar", .u32 },   .{ "short", .i32 },    .{ "ushort", .u32 },
            .{ "int", .i32 },      .{ "uint", .u32 },    .{ "half", .f32 },    .{ "float", .f32 },    .{ "size_t", .u32 },
            .{ "int8_t", .i32 },   .{ "uint8_t", .u32 }, .{ "int16_t", .i32 }, .{ "uint16_t", .u32 }, .{ "int32_t", .i32 },
            .{ "uint32_t", .u32 },
        };
        for (scalars) |sc| {
            if (std.mem.eql(u8, n, sc[0])) return .{ .scalar = sc[1] };
        }
        for (scalars[0..10]) |sc| {
            if (!std.mem.startsWith(u8, n, sc[0])) continue;
            const rest = n[sc[0].len..];
            if (rest.len == 1 and rest[0] >= '2' and rest[0] <= '4') return shape(sc[1], rest[0] - '0');
            if (rest.len == 3 and rest[1] == 'x' and rest[0] >= '2' and rest[0] <= '4' and rest[2] >= '2' and rest[2] <= '4') {
                if (sc[1] != .f32) return self.err(tr.line, tr.col, "only float matrices are supported ({s})", .{n});
                return .{ .mat = .{ .c = rest[0] - '0', .r = rest[2] - '0' } };
            }
        }
        if (std.mem.eql(u8, n, "double") or std.mem.eql(u8, n, "long") or std.mem.eql(u8, n, "ulong")) return self.err(tr.line, tr.col, "type '{s}' has no WGSL equivalent", .{n});
        return self.err(tr.line, tr.col, "unknown type '{s}'", .{n});
    }

    fn resolveType(self: *Lowerer, tr: P.TypeRef) Error!Type {
        var t = try self.baseType(tr);
        var k: u8 = 0;
        while (k < tr.ptr) : (k += 1) {
            const inner = try self.newType(t);
            t = .{ .ptr = inner };
        }
        return t;
    }

    fn withDims(self: *Lowerer, base: Type, dims: []const ?*P.Expr, init: ?*P.Expr, line_: u32, col: u32) Error!Type {
        var t = base;
        var i = dims.len;
        while (i > 0) {
            i -= 1;
            var len: u32 = 0;
            if (dims[i]) |d| {
                const v = self.evalInt(d) orelse return self.errE(d, "array size is not a constant integer", .{});
                if (v <= 0) return self.errE(d, "array size must be positive", .{});
                len = @intCast(v);
            } else {
                if (i != 0) return self.err(line_, col, "only the outer array size may be omitted", .{});
                const ie = init orelse return self.err(line_, col, "array without a size needs an initialiser", .{});
                len = switch (ie.kind) {
                    .init_list => |l| @intCast(l.len),
                    .str_lit => |s| @intCast(s.len + 1),
                    else => return self.err(line_, col, "array without a size needs an initialiser list", .{}),
                };
            }
            const inner = try self.newType(t);
            t = .{ .array = .{ .elem = inner, .len = len } };
        }
        return t;
    }

    // ----------------------------------------------------------------- constant integers
    fn evalInt(self: *Lowerer, e: *const P.Expr) ?i64 {
        switch (e.kind) {
            .int_lit => |l| return @intCast(l.value),
            .char_lit => |c| return c,
            .bool_lit => |b| return @intFromBool(b),
            .ident => |n| {
                if (self.lookup(n)) |s| return s.ival;
                return null;
            },
            .unary => |u| {
                const v = self.evalInt(u.e) orelse return null;
                if (std.mem.eql(u8, u.op, "-")) return -v;
                if (std.mem.eql(u8, u.op, "+")) return v;
                if (std.mem.eql(u8, u.op, "~")) return ~v;
                if (std.mem.eql(u8, u.op, "!")) return @intFromBool(v == 0);
                return null;
            },
            .binary => |b| {
                const x = self.evalInt(b.a) orelse return null;
                const y = self.evalInt(b.b) orelse return null;
                const op = b.op;
                if (std.mem.eql(u8, op, "+")) return x + y;
                if (std.mem.eql(u8, op, "-")) return x - y;
                if (std.mem.eql(u8, op, "*")) return x * y;
                if (std.mem.eql(u8, op, "/")) return if (y == 0) null else @divTrunc(x, y);
                if (std.mem.eql(u8, op, "%")) return if (y == 0) null else @rem(x, y);
                if (std.mem.eql(u8, op, "<<")) return if (y < 0 or y > 62) null else x << @intCast(y);
                if (std.mem.eql(u8, op, ">>")) return if (y < 0 or y > 62) null else x >> @intCast(y);
                if (std.mem.eql(u8, op, "&")) return x & y;
                if (std.mem.eql(u8, op, "|")) return x | y;
                if (std.mem.eql(u8, op, "^")) return x ^ y;
                if (std.mem.eql(u8, op, "<")) return @intFromBool(x < y);
                if (std.mem.eql(u8, op, ">")) return @intFromBool(x > y);
                if (std.mem.eql(u8, op, "<=")) return @intFromBool(x <= y);
                if (std.mem.eql(u8, op, ">=")) return @intFromBool(x >= y);
                if (std.mem.eql(u8, op, "==")) return @intFromBool(x == y);
                if (std.mem.eql(u8, op, "!=")) return @intFromBool(x != y);
                return null;
            },
            .ternary => |t| {
                const c = self.evalInt(t.c) orelse return null;
                return if (c != 0) self.evalInt(t.a) else self.evalInt(t.b);
            },
            .call => |c| {
                if (c.args.len != 1 or c.callee.kind != .ident) return null;
                const n = c.callee.kind.ident;
                if (std.mem.eql(u8, n, "int") or std.mem.eql(u8, n, "uint") or std.mem.eql(u8, n, "short") or std.mem.eql(u8, n, "ushort")) return self.evalInt(c.args[0]);
                return null;
            },
            .cast => |c| return self.evalInt(c.e),
            else => return null,
        }
    }

    // ----------------------------------------------------------------- scopes
    fn lookup(self: *Lowerer, name: []const u8) ?*Sym {
        var i = self.ctx.scope.items.len;
        while (i > 0) {
            i -= 1;
            const s = self.ctx.scope.items[i];
            if (std.mem.eql(u8, s.name, name)) return s;
        }
        return self.globals.get(name);
    }
    fn push(self: *Lowerer, s: *Sym) Error!void {
        try self.ctx.scope.append(self.a, s);
    }
    fn newSym(self: *Lowerer, s: Sym) Error!*Sym {
        const q = try self.a.create(Sym);
        q.* = s;
        return q;
    }

    // ----------------------------------------------------------------- literals and conversions
    fn floatText(self: *Lowerer, digits: []const u8) Error![]const u8 {
        var d = digits;
        var neg = false;
        if (d.len > 0 and d[0] == '-') {
            neg = true;
            d = d[1..];
        }
        var b: std.ArrayList(u8) = .empty;
        if (neg) try b.append(self.a, '-');
        if (d.len > 0 and d[0] == '.') try b.append(self.a, '0');
        const has_dot = std.mem.findScalar(u8, d, '.') != null;
        const epos = std.mem.findAny(u8, d, "eE");
        if (epos) |ep| {
            try b.appendSlice(self.a, d[0..ep]);
            if (has_dot and d[ep - 1] == '.') try b.append(self.a, '0');
            if (!has_dot) try b.appendSlice(self.a, ".0");
            try b.appendSlice(self.a, d[ep..]);
        } else {
            try b.appendSlice(self.a, d);
            if (!has_dot) try b.appendSlice(self.a, ".0") else if (d[d.len - 1] == '.') try b.append(self.a, '0');
        }
        try b.append(self.a, 'f');
        return b.items;
    }

    fn litText(self: *Lowerer, l: Lit, to: Scalar) Error!?[]const u8 {
        switch (l) {
            .int => |v| return switch (to) {
                .f32 => try self.p("{d}.0f", .{v}),
                .i32 => if (v >= std.math.minInt(i32) and v <= std.math.maxInt(i32)) try self.p("{d}i", .{v}) else null,
                .u32 => try self.p("{d}u", .{@as(u32, @truncate(@as(u64, @bitCast(v))))}),
                .bool => if (v != 0) "true" else "false",
            },
            .float => |t| {
                const v = std.fmt.parseFloat(f64, t) catch return null;
                return switch (to) {
                    .f32 => try self.floatText(t),
                    .i32 => try self.p("{d}i", .{@as(i64, @intFromFloat(@trunc(v)))}),
                    .u32 => if (v >= 0) try self.p("{d}u", .{@as(i64, @intFromFloat(@trunc(v)))}) else null,
                    .bool => if (v != 0) "true" else "false",
                };
            },
            .boolean => |b| return switch (to) {
                .f32 => if (b) "1.0f" else "0.0f",
                .i32 => if (b) "1i" else "0i",
                .u32 => if (b) "1u" else "0u",
                .bool => if (b) "true" else "false",
            },
        }
    }

    fn describe(self: *Lowerer, v: Val) Error![]const u8 {
        return switch (v.special) {
            .none => self.mslName(v.ty),
            .texture => "a texture",
            .sampler => "a sampler",
            .lambda => "a lambda",
            .ptr => "a pointer",
            .frame => "the frame (ArgusFrame)",
            .stats => "the stats (ArgusStats)",
            .typename => "a type name",
            .procs => "s.procs",
            .funcs => |n| self.p("the function {s}", .{n}),
            .level => "level()",
        };
    }

    /// Converts v to `to` as Metal does implicitly (and for explicit casts: same rules).
    fn coerce(self: *Lowerer, v: Val, to: Type, e: *const P.Expr) Error![]const u8 {
        if (v.flat != null) return self.errE(e, "a row of a two-dimensional constant array cannot be used as a value", .{});
        if (v.special == .frame and eql(to, t_frame)) return "f";
        if (v.special == .stats and eql(to, .{ .strct = 2 })) return "s";
        if (v.special == .ptr and to == .ptr) {
            if (v.special.ptr.kind != .pool) return self.errE(e, "only constant string pointers can be stored", .{});
            return v.special.ptr.off;
        }
        if (v.special != .none) return self.errE(e, "cannot use {s} as a value of type {s}", .{ try self.describe(v), try self.mslName(to) });
        if (eql(v.ty, to)) return v.text;
        if (v.lit) |l| {
            if (scalarOf(to)) |ts| {
                if (try self.litText(l, ts)) |txt| {
                    if (to == .vec) return self.p("{s}({s})", .{ try self.tyText(to), txt });
                    return txt;
                }
            }
        }
        switch (to) {
            .scalar => |ts| switch (v.ty) {
                .scalar => |fs| {
                    if (ts == .bool) return self.p("({s} != {s})", .{ v.text, zeroOf(fs) });
                    return self.p("{s}({s})", .{ scalarText(ts), v.text });
                },
                else => {},
            },
            .vec => |tv| switch (v.ty) {
                .scalar => {
                    const inner = try self.coerce(v, .{ .scalar = tv.s }, e);
                    return self.p("{s}({s})", .{ try self.tyText(to), inner });
                },
                .vec => |fv| if (fv.n == tv.n) {
                    if (tv.s == .bool) return self.p("({s} != {s}())", .{ v.text, try self.tyText(v.ty) });
                    return self.p("{s}({s})", .{ try self.tyText(to), v.text });
                },
                else => {},
            },
            else => {},
        }
        return self.errE(e, "cannot convert {s} to {s}", .{ try self.mslName(v.ty), try self.mslName(to) });
    }

    fn zeroOf(s: Scalar) []const u8 {
        return switch (s) {
            .bool => "false",
            .i32 => "0i",
            .u32 => "0u",
            .f32 => "0.0f",
        };
    }

    fn toBool(self: *Lowerer, v: Val, e: *const P.Expr) Error![]const u8 {
        if (v.special == .ptr) return self.errE(e, "a pointer used as a condition is not supported", .{});
        if (v.ty != .scalar) return self.errE(e, "a condition must be a scalar, found {s}", .{try self.mslName(v.ty)});
        return self.coerce(v, t_bool, e);
    }

    fn zeroValue(self: *Lowerer, t: Type) Error![]const u8 {
        return self.p("{s}()", .{try self.tyText(t)});
    }

    // ----------------------------------------------------------------- entry
    pub fn run(self: *Lowerer, items: []const P.Item) Error!void {
        const top = try self.a.create(Ctx);
        const top_out = try self.a.create(std.ArrayList(u8));
        top_out.* = .empty;
        top.* = .{ .out = top_out, .global = true, .indent = 0 };
        self.ctx = top;
        try self.registerPrelude();
        for (items) |it| switch (it) {
            .strct => |s| try self.declStruct(s),
            .typedef => |t| try self.typedefs.put(self.a, t.name, t.ty),
            .func => |f| {
                const gop = try self.funcs.getOrPut(self.a, f.name);
                if (!gop.found_existing) gop.value_ptr.* = .empty;
                if (f.body != null) {
                    // a later definition replaces an earlier prototype with the same parameters
                    var replaced = false;
                    for (gop.value_ptr.items) |*g| if (g.*.body == null and g.*.params.len == f.params.len) {
                        g.* = f;
                        replaced = true;
                    };
                    if (!replaced) try gop.value_ptr.append(self.a, f);
                } else try gop.value_ptr.append(self.a, f);
            },
            .global => |g| try self.declGlobal(g),
        };
        var found = false;
        for ([_][]const u8{ "argus_init", "argus_step", "argus_draw" }, 0..) |k, ki| {
            const list = self.funcs.get(k) orelse continue;
            for (list.items) |f| {
                if (!f.is_kernel) return self.err(f.line, f.col, "{s} must be a kernel", .{k});
                if (f.body == null) continue;
                try self.lowerKernel(f, @fromBackingInt(@intCast(ki)));
                found = true;
            }
        }
        var it = self.funcs.iterator();
        while (it.next()) |kv| {
            for (kv.value_ptr.items) |f| if (f.is_kernel and !std.mem.eql(u8, f.name, "argus_init") and !std.mem.eql(u8, f.name, "argus_step") and !std.mem.eql(u8, f.name, "argus_draw")) {
                return self.err(f.line, f.col, "kernel {s}: Argus only runs argus_init, argus_step and argus_draw", .{f.name});
            };
        }
        if (self.funcs.get("argus_draw") == null or !found) return self.err(1, 1, "no argus_draw kernel", .{});
    }

    fn addStruct(self: *Lowerer, name: []const u8, fields: []Field) Error!u32 {
        const idx: u32 = @intCast(self.structs.items.len);
        try self.structs.append(self.a, .{ .name = name, .wname = name, .fields = fields });
        try self.struct_idx.put(self.a, name, idx);
        try self.used.put(self.a, name, {});
        return idx;
    }

    fn registerPrelude(self: *Lowerer) Error!void {
        const frame_fields = [_]struct { []const u8, Type }{
            .{ "time", t_f32 },       .{ "dt", t_f32 },          .{ "frame", t_u32 },        .{ "width", t_u32 },
            .{ "height", t_u32 },     .{ "state_width", t_u32 }, .{ "state_height", t_u32 }, .{ "seed", t_u32 },
            .{ "days_j2000", t_i32 }, .{ "day_frac", t_f32 },    .{ "utc_offset_s", t_i32 },
        };
        var ff: std.ArrayList(Field) = .empty;
        for (frame_fields) |x| try ff.append(self.a, .{ .name = x[0], .wname = x[0], .ty = x[1] });
        _ = try self.addStruct("ArgusFrame", ff.items); // 0
        var pf: std.ArrayList(Field) = .empty;
        try pf.append(self.a, .{ .name = "name", .wname = "name", .ty = .{ .array = .{ .elem = try self.newType(t_u32), .len = 32 } } });
        try pf.append(self.a, .{ .name = "cpu", .wname = "cpu", .ty = t_f32 });
        try pf.append(self.a, .{ .name = "mem_gb", .wname = "mem_gb", .ty = t_f32 });
        _ = try self.addStruct("ArgusProc", pf.items); // 1
        const stats_fields = [_]struct { []const u8, Type }{
            .{ "seq", t_u32 },            .{ "sample_dt", t_f32 },        .{ "uptime_s", t_u32 },          .{ "thermal", t_u32 },
            .{ "cpu_total", t_f32 },      .{ "cpu_count", t_u32 },        .{ "cpu_p_cores", t_u32 },       .{ "cpu_e_cores", t_u32 },
            .{ "mem_total_gb", t_f32 },   .{ "mem_used_gb", t_f32 },      .{ "mem_compressed_gb", t_f32 }, .{ "mem_wired_gb", t_f32 },
            .{ "swap_used_gb", t_f32 },   .{ "mem_pressure", t_u32 },     .{ "gpu_busy", t_f32 },          .{ "battery_present", t_u32 },
            .{ "battery_charge", t_f32 }, .{ "battery_charging", t_u32 }, .{ "on_ac", t_u32 },             .{ "battery_minutes", t_f32 },
            .{ "net_rx_bps", t_f32 },     .{ "net_tx_bps", t_f32 },       .{ "disk_free_gb", t_f32 },      .{ "disk_total_gb", t_f32 },
            .{ "proc_count", t_u32 },
        };
        var sf: std.ArrayList(Field) = .empty;
        for (stats_fields) |x| try sf.append(self.a, .{ .name = x[0], .wname = x[0], .ty = x[1] });
        try sf.append(self.a, .{ .name = "cpu_core", .wname = "cpu_core", .ty = .{ .array = .{ .elem = try self.newType(t_f32), .len = 32 } } });
        try sf.append(self.a, .{ .name = "procs", .wname = "procs", .ty = .{ .array = .{ .elem = try self.newType(.{ .strct = 1 }), .len = 5 } } });
        _ = try self.addStruct("ArgusStats", sf.items); // 2

        const consts = [_]struct { []const u8, Type, ?i64 }{
            .{ "ARGUS_TIME_PERIOD", t_f32, null },
            .{ "ARGUS_STATS_MAX_CORES", t_u32, 32 },
            .{ "ARGUS_STATS_TOP", t_u32, 5 },
        };
        for (consts) |c| try self.globals.put(self.a, c[0], try self.newSym(.{ .name = c[0], .wname = c[0], .kind = .gconst, .ty = c[1], .ival = c[2] }));
        for (math_consts) |m| {
            const decl = try self.p("const {s}: f32 = {s};\n", .{ m.name, m.value });
            try self.globals.put(self.a, m.name, try self.newSym(.{ .name = m.name, .wname = m.name, .kind = .gconst, .ty = t_f32, .helper = decl }));
        }
        for (reserved) |r| try self.used.put(self.a, r, {});
        for (prelude_fns) |f| try self.used.put(self.a, f.name, {});
        try self.used.put(self.a, "ARGUS_TIME_PERIOD", {});
        try self.used.put(self.a, "M2W_STR", {});
    }

    fn declStruct(self: *Lowerer, s: *P.Struct) Error!void {
        if (self.struct_idx.contains(s.name)) return self.err(s.line, s.col, "struct {s} is defined twice (or shadows a prelude struct)", .{s.name});
        var fields: std.ArrayList(Field) = .empty;
        for (s.fields) |f| {
            const bt = try self.resolveType(f.ty);
            if (f.ty.ref or bt == .ptr or bt == .texture or bt == .sampler) return self.err(f.line, f.col, "struct field {s}.{s}: references, pointers, textures and samplers in structs are not supported", .{ s.name, f.name });
            const t = try self.withDims(bt, f.dims, null, f.line, f.col);
            try fields.append(self.a, .{ .name = f.name, .wname = try self.wname(f.name), .ty = t });
        }
        const idx = try self.addStruct(s.name, fields.items);
        if (isReserved(s.name)) self.structs.items[idx].wname = try self.p("{s}_", .{s.name});
        try self.decls.print(self.a, "struct {s} {{\n", .{self.structs.items[idx].wname});
        for (fields.items) |f| try self.decls.print(self.a, "    {s}: {s},\n", .{ f.wname, try self.tyText(f.ty) });
        try self.decls.appendSlice(self.a, "}\n\n");
    }

    // ----------------------------------------------------------------- samplers
    fn samplerFrom(self: *Lowerer, args: []const *P.Expr, line_: u32, col: u32) Error!SamplerVal {
        var linear = false;
        var s_rep = false;
        var t_rep = false;
        var pixel = false;
        for (args) |e| {
            const n = switch (e.kind) {
                .ident => |n| n,
                else => return self.errE(e, "sampler arguments must be enum values like filter::linear", .{}),
            };
            if (std.mem.eql(u8, n, "filter::linear") or std.mem.eql(u8, n, "mag_filter::linear") or std.mem.eql(u8, n, "min_filter::linear")) {
                linear = true;
            } else if (std.mem.eql(u8, n, "filter::nearest") or std.mem.eql(u8, n, "mag_filter::nearest") or std.mem.eql(u8, n, "min_filter::nearest")) {
                linear = false;
            } else if (std.mem.eql(u8, n, "address::repeat")) {
                s_rep = true;
                t_rep = true;
            } else if (std.mem.eql(u8, n, "address::clamp_to_edge")) {
                s_rep = false;
                t_rep = false;
            } else if (std.mem.eql(u8, n, "s_address::repeat")) {
                s_rep = true;
            } else if (std.mem.eql(u8, n, "t_address::repeat")) {
                t_rep = true;
            } else if (std.mem.eql(u8, n, "s_address::clamp_to_edge")) {
                s_rep = false;
            } else if (std.mem.eql(u8, n, "t_address::clamp_to_edge")) {
                t_rep = false;
            } else if (std.mem.eql(u8, n, "coord::pixel")) {
                pixel = true;
            } else if (std.mem.eql(u8, n, "coord::normalized") or std.mem.startsWith(u8, n, "mip_filter::") or std.mem.eql(u8, n, "r_address::clamp_to_edge")) {} else {
                return self.errE(e, "sampler option {s} has no WGSL binding in the Argus prelude (linear or nearest, clamp_to_edge or repeat)", .{n});
            }
        }
        const g: []const u8 = if (linear) (if (s_rep and t_rep) "argus_linear_repeat" else if (s_rep) "argus_linear_repeat_s" else if (t_rep) "argus_linear_repeat_t" else "argus_linear_clamp") else if (!s_rep and !t_rep) "argus_nearest_clamp" else return self.err(line_, col, "a nearest-filtered repeating sampler has no binding in the WGSL prelude", .{});
        return .{ .g = g, .pixel = pixel };
    }

    // ----------------------------------------------------------------- globals
    fn declGlobal(self: *Lowerer, g: *P.Global) Error!void {
        var ctx: Ctx = .{ .out = try self.a.create(std.ArrayList(u8)), .global = true, .indent = 0 };
        ctx.out.* = .empty;
        const saved = self.ctx;
        self.ctx = &ctx;
        defer self.ctx = saved;
        const bt = try self.resolveType(g.ty);
        for (g.decls) |d| {
            if (self.globals.contains(d.name) or self.struct_idx.contains(d.name)) return self.err(d.line, d.col, "{s} is declared twice (or shadows a prelude name)", .{d.name});
            if (bt == .sampler) {
                const args: []const *P.Expr = d.ctor orelse &.{};
                const sv = try self.samplerFrom(args, d.line, d.col);
                try self.globals.put(self.a, d.name, try self.newSym(.{ .name = d.name, .wname = d.name, .kind = .static_, .ty = .sampler, .special = .{ .sampler = sv } }));
                continue;
            }
            if (g.ty.space != .constant and !g.ty.is_const and !g.is_constexpr) return self.err(d.line, d.col, "global variable {s}: only `constant` (read-only) globals are supported", .{d.name});
            const t = try self.withDims(bt, d.dims, d.init, d.line, d.col);
            // strings: constant char X[] = "..."
            if (t == .array and t.array.elem.* == .scalar and d.init != null and d.init.?.kind == .str_lit) {
                const off = try self.poolString(d.init.?.kind.str_lit);
                try self.globals.put(self.a, d.name, try self.newSym(.{ .name = d.name, .wname = d.name, .kind = .static_, .ty = .{ .ptr = try self.newType(t_i32) }, .special = .{ .ptr = .{ .kind = .pool, .off = try self.p("{d}i", .{off}), .elem = t_i32, .n = t.array.len } } }));
                continue;
            }
            const init = d.init orelse return self.err(d.line, d.col, "constant {s} needs an initialiser", .{d.name});
            const wn = try self.uniqueName(d.name);
            var flat_inner: u32 = 0;
            var decl_t = t;
            var text: []const u8 = undefined;
            if (t == .array and t.array.elem.* == .array) {
                // Safari rejects nested const arrays: flatten to one dimension, row-major.
                const inner = t.array.elem.*.array;
                if (inner.elem.* == .array) return self.err(d.line, d.col, "constant arrays with more than two dimensions are not supported", .{});
                flat_inner = inner.len;
                decl_t = .{ .array = .{ .elem = inner.elem, .len = t.array.len * inner.len } };
                const rows = switch (init.kind) {
                    .init_list => |l| l,
                    else => return self.errE(init, "a two-dimensional constant array needs a nested initialiser list", .{}),
                };
                var items: std.ArrayList(*P.Expr) = .empty;
                for (rows) |r| {
                    const cols = switch (r.kind) {
                        .init_list => |l| l,
                        else => return self.errE(r, "expected a row initialiser list", .{}),
                    };
                    if (cols.len > inner.len) return self.errE(r, "too many initialisers in a row", .{});
                    try items.appendSlice(self.a, cols);
                    // short rows: zero-fill
                    var k = cols.len;
                    while (k < inner.len) : (k += 1) {
                        const z = try self.a.create(P.Expr);
                        z.* = .{ .line = r.line, .col = r.col, .kind = .{ .int_lit = .{ .value = 0, .unsigned = false } } };
                        try items.append(self.a, z);
                    }
                }
                text = try self.constructList(decl_t, items.items, init);
            } else {
                text = try self.initText(t, init);
            }
            if (ctx.out.items.len != 0) return self.errE(init, "constant {s}: its initialiser is not a constant expression", .{d.name});
            try self.decls.print(self.a, "const {s}: {s} = {s};\n", .{ wn, try self.tyText(decl_t), text });
            var ival: ?i64 = null;
            if (t == .scalar and t.scalar != .f32) ival = self.evalInt(init);
            try self.globals.put(self.a, d.name, try self.newSym(.{ .name = d.name, .wname = wn, .kind = .gconst, .ty = t, .ival = ival, .flat_inner = flat_inner }));
        }
    }

    fn poolString(self: *Lowerer, s: []const u8) Error!u32 {
        if (self.pool_idx.get(s)) |o| return o;
        const off: u32 = @intCast(self.pool.items.len);
        for (s) |c| try self.pool.append(self.a, @as(i8, @bitCast(c)));
        try self.pool.append(self.a, 0);
        try self.pool_idx.put(self.a, s, off);
        return off;
    }

    /// The WGSL for an initialiser of type t: an init list, or an expression converted to t.
    fn initText(self: *Lowerer, t: Type, init: *P.Expr) Error![]const u8 {
        switch (init.kind) {
            .init_list => |items| return self.constructList(t, items, init),
            else => {
                const v = try self.lowerExpr(init);
                return self.coerce(v, t, init);
            },
        }
    }

    fn constructList(self: *Lowerer, t: Type, items: []const *P.Expr, e: *P.Expr) Error![]const u8 {
        var parts: std.ArrayList([]const u8) = .empty;
        switch (t) {
            .strct => |si| {
                const fields = self.structs.items[si].fields;
                if (items.len > fields.len) return self.errE(e, "too many initialisers for {s}", .{self.structs.items[si].name});
                for (fields, 0..) |f, i| {
                    if (i < items.len) try parts.append(self.a, try self.initText(f.ty, items[i])) else try parts.append(self.a, try self.zeroValue(f.ty));
                }
            },
            .array => |arr| {
                if (items.len > arr.len) return self.errE(e, "too many initialisers ({d}) for an array of {d}", .{ items.len, arr.len });
                for (items) |it| try parts.append(self.a, try self.initText(arr.elem.*, it));
                var k = items.len;
                while (k < arr.len) : (k += 1) try parts.append(self.a, try self.zeroValue(arr.elem.*));
            },
            .scalar, .vec, .mat => {
                if (items.len == 0) return self.zeroValue(t);
                if (items.len == 1 and t == .scalar) return self.initText(t, items[0]);
                var vals: std.ArrayList(Val) = .empty;
                for (items) |it| try vals.append(self.a, try self.lowerExpr(it));
                return self.constructVals(t, vals.items, items, e);
            },
            else => return self.errE(e, "an initialiser list for {s} is not supported", .{try self.mslName(t)}),
        }
        return self.p("{s}({s})", .{ try self.tyText(t), try std.mem.join(self.a, ", ", parts.items) });
    }

    // ----------------------------------------------------------------- kernels
    fn usesThreadgroup(f: *P.Func) bool {
        for (f.params) |prm| if (prm.attr) |at| {
            if (std.mem.eql(u8, at.name, "thread_position_in_threadgroup") or std.mem.eql(u8, at.name, "threads_per_threadgroup") or
                std.mem.eql(u8, at.name, "thread_index_in_threadgroup") or std.mem.eql(u8, at.name, "threadgroup_position_in_grid")) return true;
        };
        if (f.body) |b| return stmtHasThreadgroup(b);
        return false;
    }
    fn stmtHasThreadgroup(s: *P.Stmt) bool {
        return switch (s.kind) {
            .block => |l| for (l) |x| {
                if (stmtHasThreadgroup(x)) break true;
            } else false,
            .decl => |d| d.is_threadgroup,
            else => false,
        };
    }

    fn lowerKernel(self: *Lowerer, f: *P.Func, kind: KernelKind) Error!void {
        const wg: u32 = if (usesThreadgroup(f)) 16 else 8;
        var body: std.ArrayList(u8) = .empty;
        var ctx: Ctx = .{ .out = &body, .kernel = kind, .ret = .void, .owner = f.name, .wg_size = wg };
        const inst = try self.a.create(Instance);
        inst.* = .{ .key = f.name, .name = f.name, .func = f, .binds = &.{}, .tbinds = &.{}, .ret = .void, .state = .busy };
        ctx.inst = inst;
        const saved = self.ctx;
        self.ctx = &ctx;
        defer self.ctx = saved;
        var builtins: std.ArrayList([]const u8) = .empty;
        try builtins.append(self.a, "@builtin(global_invocation_id) m2w_gid: vec3u");
        var need_lid = false;
        var need_lidx = false;
        var need_wid = false;
        for (f.params) |prm| {
            const at = prm.attr orelse return self.err(prm.line, prm.col, "kernel parameter {s} has no [[...]] attribute", .{prm.name});
            const t = try self.resolveType(prm.ty);
            const nm = prm.name;
            if (std.mem.eql(u8, at.name, "buffer")) {
                const special: Special = if (eql(t, t_frame)) .frame else if (eql(t, .{ .strct = 2 })) .stats else return self.err(prm.line, prm.col, "kernel buffer {s}: only ArgusFrame (buffer 0) and ArgusStats (buffer 1) exist", .{nm});
                try self.push(try self.newSym(.{ .name = nm, .wname = if (special == .frame) "f" else "s", .kind = .static_, .ty = t, .special = special }));
            } else if (std.mem.eql(u8, at.name, "texture")) {
                if (t != .texture) return self.err(prm.line, prm.col, "[[texture]] parameter {s} is not a texture2d", .{nm});
                const idx = at.arg orelse return self.err(prm.line, prm.col, "[[texture]] parameter {s} needs an index, [[texture(n)]]", .{nm});
                const g: []const u8 = switch (kind) {
                    .draw => if (idx == 0) "argus_out" else if (idx == 1) "argus_state" else "",
                    .init => if (idx == 0) "argus_state_out" else if (idx == 1) "argus_data" else "",
                    .step => if (idx == 0) "argus_state" else if (idx == 1) "argus_state_out" else "",
                };
                if (g.len == 0) return self.err(prm.line, prm.col, "texture({d}) does not exist in {s}", .{ idx, f.name });
                const is_write = std.mem.endsWith(u8, g, "out");
                if (is_write != (t.texture == .write)) return self.err(prm.line, prm.col, "texture({d}) of {s} must be {s}", .{ idx, f.name, if (is_write) "access::write" else "readable (access::read or sample)" });
                try self.push(try self.newSym(.{ .name = nm, .wname = g, .kind = .static_, .ty = t, .special = .{ .texture = g } }));
            } else {
                const n2 = widthOf(t);
                const sel: []const u8 = if (n2 == 2) ".xy" else if (n2 == 1) ".x" else ".xyz";
                const src: []const u8 = if (std.mem.eql(u8, at.name, "thread_position_in_grid")) blk: {
                    break :blk try self.p("m2w_gid{s}", .{sel});
                } else if (std.mem.eql(u8, at.name, "thread_position_in_threadgroup")) blk: {
                    need_lid = true;
                    break :blk try self.p("m2w_lid{s}", .{sel});
                } else if (std.mem.eql(u8, at.name, "threadgroup_position_in_grid")) blk: {
                    need_wid = true;
                    break :blk try self.p("m2w_wid{s}", .{sel});
                } else if (std.mem.eql(u8, at.name, "thread_index_in_threadgroup")) blk: {
                    need_lidx = true;
                    break :blk "m2w_lidx";
                } else if (std.mem.eql(u8, at.name, "threads_per_threadgroup")) blk: {
                    break :blk if (n2 == 2) try self.p("vec2u({d}u, {d}u)", .{ wg, wg }) else if (n2 == 1) try self.p("{d}u", .{wg * wg}) else try self.p("vec3u({d}u, {d}u, 1u)", .{ wg, wg });
                } else return self.err(prm.line, prm.col, "kernel attribute [[{s}]] is not supported", .{at.name});
                if (scalarOf(t) != .u32) return self.err(prm.line, prm.col, "[[{s}]] parameter must be uint, uint2 or uint3", .{at.name});
                const wn = try self.wname(nm);
                try self.line("let {s}: {s} = {s};", .{ wn, try self.tyText(t), src });
                try self.push(try self.newSym(.{ .name = nm, .wname = wn, .kind = .let_, .ty = t }));
            }
        }
        if (need_lid) try builtins.append(self.a, "@builtin(local_invocation_id) m2w_lid: vec3u");
        if (need_lidx) try builtins.append(self.a, "@builtin(local_invocation_index) m2w_lidx: u32");
        if (need_wid) try builtins.append(self.a, "@builtin(workgroup_id) m2w_wid: vec3u");
        try self.lowerStmtList(f.body.?.kind.block);
        try self.kernels.print(self.a, "// {s} (Metal line {d})\n@compute @workgroup_size({d}, {d})\nfn {s}({s}) {{\n{s}}}\n\n", .{ f.name, f.line, wg, wg, f.name, try std.mem.join(self.a, ",\n        ", builtins.items), body.items });
    }

    // ----------------------------------------------------------------- statements
    fn lowerStmtList(self: *Lowerer, list: []const *P.Stmt) Error!void {
        const mark = self.ctx.scope.items.len;
        defer self.ctx.scope.items.len = mark;
        for (list) |s| try self.lowerStmt(s);
    }

    /// A statement as the body of if/for/while: always a braced block in WGSL.
    fn lowerBody(self: *Lowerer, s: *P.Stmt) Error!void {
        self.ctx.indent += 1;
        defer self.ctx.indent -= 1;
        switch (s.kind) {
            .block => |l| try self.lowerStmtList(l),
            else => try self.lowerStmtList(&.{s}),
        }
    }

    fn lowerStmt(self: *Lowerer, s: *P.Stmt) Error!void {
        switch (s.kind) {
            .block => |l| {
                try self.line("{{", .{});
                self.ctx.indent += 1;
                try self.lowerStmtList(l);
                self.ctx.indent -= 1;
                try self.line("}}", .{});
            },
            .empty => {},
            .decl => |d| try self.lowerDecl(s, d.ty, d.decls, d.is_constexpr, d.is_threadgroup),
            .expr => |e| try self.lowerExprStmt(e),
            .if_ => try self.lowerIf(s, false),
            .ret => |e| {
                if (e) |x| {
                    if (self.ctx.kernel != null) return self.err(s.line, s.col, "a kernel returns nothing", .{});
                    const rt = self.ctx.ret;
                    if (rt == null) {
                        const v = try self.lowerExpr(x);
                        if (v.special != .none) return self.errE(x, "returning {s} is not supported", .{try self.describe(v)});
                        self.ctx.ret = v.ty;
                        try self.line("return {s};", .{v.text});
                        return;
                    }
                    if (rt.? == .void) return self.err(s.line, s.col, "returning a value from a void function", .{});
                    if (rt.? == .ptr) {
                        const v = try self.lowerExpr(x);
                        if (v.special != .ptr or v.special.ptr.kind != .pool) return self.errE(x, "a function returning a pointer may only return constant strings", .{});
                        try self.line("return {s};", .{v.special.ptr.off});
                        return;
                    }
                    const txt = try self.initText(rt.?, x);
                    try self.line("return {s};", .{txt});
                } else {
                    if (self.ctx.ret == null) self.ctx.ret = .void;
                    try self.line("return;", .{});
                }
            },
            .brk => try self.line("break;", .{}),
            .cont => try self.line("continue;", .{}),
            .while_ => |w| {
                const cap = try self.beginCapture(1);
                const c = try self.toBool(try self.lowerExpr(w.c), w.c);
                const pre = self.endCapture(cap);
                if (pre.len == 0) {
                    try self.line("while ({s}) {{", .{c});
                    try self.lowerBody(w.body);
                    try self.line("}}", .{});
                } else {
                    try self.line("loop {{", .{});
                    try self.raw(pre);
                    self.ctx.indent += 1;
                    try self.line("if (!({s})) {{ break; }}", .{c});
                    self.ctx.indent -= 1;
                    try self.lowerBody(w.body);
                    try self.line("}}", .{});
                }
            },
            .do_while => |w| {
                try self.line("loop {{", .{});
                try self.lowerBody(w.body);
                self.ctx.indent += 1;
                try self.line("continuing {{", .{});
                self.ctx.indent += 1;
                const c = try self.toBool(try self.lowerExpr(w.c), w.c);
                try self.line("break if !({s});", .{c});
                self.ctx.indent -= 1;
                try self.line("}}", .{});
                self.ctx.indent -= 1;
                try self.line("}}", .{});
            },
            .for_ => |fs| try self.lowerFor(s, fs.init, fs.cond, fs.incr, fs.body),
            .switch_ => |sw| try self.lowerSwitch(s, sw.e, sw.cases),
        }
    }

    fn lowerIf(self: *Lowerer, s: *P.Stmt, chained: bool) Error!void {
        const ifs = s.kind.if_;
        const c = try self.toBool(try self.lowerExpr(ifs.c), ifs.c);
        if (chained) try self.raw(" if (") else {
            for (0..self.ctx.indent) |_| try self.raw("    ");
            try self.raw("if (");
        }
        try self.raw(c);
        try self.raw(") {\n");
        try self.lowerBody(ifs.then);
        for (0..self.ctx.indent) |_| try self.raw("    ");
        try self.raw("}");
        if (ifs.els) |e| {
            if (e.kind == .if_) {
                // `else if` stays a chain unless the next condition needs statements first
                const cap = try self.beginCapture(1);
                _ = try self.lowerExpr(e.kind.if_.c);
                const pre = self.endCapture(cap);
                if (pre.len == 0) {
                    try self.raw(" else");
                    return self.lowerIf(e, true);
                }
            }
            try self.raw(" else {\n");
            try self.lowerBody(e);
            for (0..self.ctx.indent) |_| try self.raw("    ");
            try self.raw("}\n");
        } else try self.raw("\n");
    }

    fn oneLine(txt: []const u8) ?[]const u8 {
        if (std.mem.countScalar(u8, txt, '\n') != 1) return null;
        const t = std.mem.trim(u8, txt, " \n");
        if (!std.mem.endsWith(u8, t, ";")) return null;
        if (std.mem.startsWith(u8, t, "_ =")) return null;
        return t[0 .. t.len - 1];
    }

    fn lowerFor(self: *Lowerer, s: *P.Stmt, init: ?*P.Stmt, cond: ?*P.Expr, incr: ?*P.Expr, body: *P.Stmt) Error!void {
        _ = s;
        const mark = self.ctx.scope.items.len;
        defer self.ctx.scope.items.len = mark;
        // Lower the init into a buffer: one plain statement goes in the for header.
        var init_txt: []const u8 = "";
        var init_header: ?[]const u8 = null;
        if (init) |is| {
            const cap = try self.beginCapture(1);
            try self.lowerStmt(is);
            init_txt = self.endCapture(cap);
            init_header = oneLine(init_txt);
        }
        const ccap = try self.beginCapture(2);
        const c: []const u8 = if (cond) |ce| try self.toBool(try self.lowerExpr(ce), ce) else "true";
        const cpre = self.endCapture(ccap);
        var incr_txt: []const u8 = "";
        var incr_header: ?[]const u8 = null;
        if (incr) |ie| {
            const icap = try self.beginCapture(3);
            try self.lowerExprStmt(ie);
            incr_txt = self.endCapture(icap);
            incr_header = oneLine(incr_txt);
            if (incr_header) |h| if (std.mem.startsWith(u8, h, "let ") or std.mem.startsWith(u8, h, "var ")) {
                incr_header = null;
            };
        }
        const simple = cpre.len == 0 and (incr == null or incr_header != null) and (init == null or init_header != null);
        if (simple) {
            try self.line("for ({s}; {s}; {s}) {{", .{ init_header orelse "", if (cond == null) "" else c, incr_header orelse "" });
            try self.lowerBody(body);
            try self.line("}}", .{});
            return;
        }
        try self.line("{{", .{});
        try self.raw(init_txt);
        self.ctx.indent += 1;
        try self.line("loop {{", .{});
        try self.raw(cpre);
        if (cond != null) {
            self.ctx.indent += 1;
            try self.line("if (!({s})) {{ break; }}", .{c});
            self.ctx.indent -= 1;
        }
        try self.lowerBody(body);
        if (incr != null) {
            self.ctx.indent += 1;
            try self.line("continuing {{", .{});
            try self.raw(incr_txt);
            try self.line("}}", .{});
            self.ctx.indent -= 1;
        }
        try self.line("}}", .{});
        self.ctx.indent -= 1;
        try self.line("}}", .{});
    }

    fn endsInJump(list: []const *P.Stmt) bool {
        if (list.len == 0) return false;
        const last = list[list.len - 1];
        return switch (last.kind) {
            .brk, .ret, .cont => true,
            .block => |l| endsInJump(l),
            else => false,
        };
    }

    fn lowerSwitch(self: *Lowerer, s: *P.Stmt, sel: *P.Expr, cases: []const P.Case) Error!void {
        const v = try self.lowerExpr(sel);
        const st = scalarOf(v.ty) orelse return self.errE(sel, "switch on {s}", .{try self.mslName(v.ty)});
        if (v.ty != .scalar or st == .f32) return self.errE(sel, "switch on {s}: only integers are supported", .{try self.mslName(v.ty)});
        const sty: Type = .{ .scalar = promote(st) };
        const sel_txt = try self.coerce(v, sty, sel);
        try self.line("switch ({s}) {{", .{sel_txt});
        self.ctx.indent += 1;
        var labels: std.ArrayList([]const u8) = .empty;
        for (cases, 0..) |c, ci| {
            if (c.is_default) try labels.append(self.a, "default") else for (c.values) |ve| {
                const lv = try self.lowerExpr(ve);
                try labels.append(self.a, try self.coerce(lv, sty, ve));
            }
            if (c.body.len == 0 and ci + 1 < cases.len) continue; // label group
            try self.line("case {s}: {{", .{try std.mem.join(self.a, ", ", labels.items)});
            labels.items.len = 0;
            self.ctx.indent += 1;
            // C falls through into the next case: WGSL doesn't, so the next bodies follow here
            // (a `break` inside them still leaves the switch)
            var k = ci;
            while (true) : (k += 1) {
                var body = cases[k].body;
                const jumps = endsInJump(body);
                if (body.len > 0 and body[body.len - 1].kind == .brk) body = body[0 .. body.len - 1];
                if (k == ci and (jumps or k + 1 == cases.len)) {
                    try self.lowerStmtList(body);
                } else {
                    try self.line("{{", .{});
                    self.ctx.indent += 1;
                    try self.lowerStmtList(body);
                    self.ctx.indent -= 1;
                    try self.line("}}", .{});
                }
                if (jumps or k + 1 == cases.len) break;
            }
            self.ctx.indent -= 1;
            try self.line("}}", .{});
        }
        var has_default = false;
        for (cases) |c| if (c.is_default) {
            has_default = true;
        };
        if (!has_default) try self.line("default: {{}}", .{});
        self.ctx.indent -= 1;
        try self.line("}}", .{});
        _ = s;
    }

    fn lowerDecl(self: *Lowerer, s: *P.Stmt, tr: P.TypeRef, decls: []const P.Declarator, is_constexpr: bool, is_tg: bool) Error!void {
        const bt = try self.resolveType(tr);
        for (decls) |d| {
            if (bt == .sampler) {
                const args: []const *P.Expr = d.ctor orelse &.{};
                const sv = try self.samplerFrom(args, d.line, d.col);
                try self.push(try self.newSym(.{ .name = d.name, .wname = d.name, .kind = .static_, .ty = .sampler, .special = .{ .sampler = sv } }));
                continue;
            }
            if (bt == .auto) {
                const init = d.init orelse return self.err(d.line, d.col, "auto {s} needs an initialiser", .{d.name});
                if (init.kind == .lambda) {
                    try self.defineLambda(d.name, init.kind.lambda);
                    continue;
                }
                const v = try self.lowerExpr(init);
                if (v.special != .none) return self.errE(init, "auto {s} = {s} is not supported", .{ d.name, try self.describe(v) });
                const wn = try self.wname(d.name);
                if (tr.is_const) {
                    try self.line("let {s}: {s} = {s};", .{ wn, try self.tyText(v.ty), v.text });
                    try self.push(try self.newSym(.{ .name = d.name, .wname = wn, .kind = .let_, .ty = v.ty }));
                } else {
                    try self.line("var {s}: {s} = {s};", .{ wn, try self.tyText(v.ty), v.text });
                    try self.push(try self.newSym(.{ .name = d.name, .wname = wn, .kind = .var_, .ty = v.ty }));
                }
                continue;
            }
            const t = try self.withDims(bt, d.dims, d.init, d.line, d.col);
            if (is_tg) {
                if (self.ctx.kernel == null) return self.err(d.line, d.col, "threadgroup memory outside a kernel", .{});
                if (d.init != null) return self.err(d.line, d.col, "threadgroup variables cannot be initialised", .{});
                const wn = try self.uniqueName(d.name);
                try self.wg_vars.print(self.a, "var<workgroup> {s}: {s};\n", .{ wn, try self.tyText(t) });
                try self.push(try self.newSym(.{ .name = d.name, .wname = wn, .kind = .var_, .ty = t, .workgroup = true }));
                continue;
            }
            if (tr.ref) {
                // thread T& r = lvalue;
                const init = d.init orelse return self.err(d.line, d.col, "reference {s} needs an initialiser", .{d.name});
                const v = try self.lowerExpr(init);
                if (tr.is_const and tr.space != .thread) {
                    const wn = try self.wname(d.name);
                    try self.line("let {s}: {s} = {s};", .{ wn, try self.tyText(t), try self.coerce(v, t, init) });
                    try self.push(try self.newSym(.{ .name = d.name, .wname = wn, .kind = .let_, .ty = t }));
                    continue;
                }
                if (!eql(v.ty, t)) return self.errE(init, "reference {s} of type {s} bound to {s}", .{ d.name, try self.mslName(t), try self.mslName(v.ty) });
                const addr = (try self.addrOf(v)) orelse return self.errE(init, "a reference to this expression (not a whole variable) is not supported", .{});
                const wn = try self.wname(d.name);
                try self.line("let {s} = {s};", .{ wn, addr });
                try self.push(try self.newSym(.{ .name = d.name, .wname = wn, .kind = .ptr, .ty = t }));
                continue;
            }
            if (t == .ptr) {
                // a constant string pointer: its pool offset
                const init = d.init orelse return self.err(d.line, d.col, "pointer {s} needs an initialiser", .{d.name});
                const v = try self.lowerExpr(init);
                if (v.special != .ptr) return self.err(d.line, d.col, "pointer {s} must point into an array or a string", .{d.name});
                // the pointer is fixed here (changing it later fails in requireWritable)
                var pv = v.special.ptr;
                const wn = try self.wname(d.name);
                if (!std.mem.eql(u8, pv.off, "0i")) {
                    try self.line("let {s}_off: i32 = {s};", .{ wn, pv.off });
                    pv.off = try self.p("{s}_off", .{wn});
                }
                if (pv.kind == .proc) {
                    try self.line("let {s}_idx: u32 = u32({s});", .{ wn, pv.ref });
                    pv.ref = try self.p("{s}_idx", .{wn});
                }
                try self.push(try self.newSym(.{ .name = d.name, .wname = wn, .kind = .static_, .ty = t, .special = .{ .ptr = pv } }));
                continue;
            }
            if (t == .texture) return self.err(d.line, d.col, "local texture variables are not supported ({s})", .{d.name});
            const wn = try self.wname(d.name);
            const is_let = (tr.is_const or is_constexpr) and t != .array;
            var init_txt: ?[]const u8 = null;
            if (d.init) |init| {
                if (t == .array and t.array.elem.* == .scalar and init.kind == .str_lit) return self.err(d.line, d.col, "local string arrays are not supported", .{});
                init_txt = try self.initText(t, init);
            } else if (d.ctor) |args| {
                var vals: std.ArrayList(Val) = .empty;
                for (args) |x| try vals.append(self.a, try self.lowerExpr(x));
                init_txt = try self.constructVals(t, vals.items, args, if (args.len > 0) args[0] else return self.err(d.line, d.col, "empty constructor", .{}));
            }
            if (is_let) {
                const it = init_txt orelse return self.err(d.line, d.col, "const {s} needs an initialiser", .{d.name});
                try self.line("let {s}: {s} = {s};", .{ wn, try self.tyText(t), it });
                try self.push(try self.newSym(.{ .name = d.name, .wname = wn, .kind = .let_, .ty = t }));
            } else {
                if (init_txt) |it| try self.line("var {s}: {s} = {s};", .{ wn, try self.tyText(t), it }) else try self.line("var {s}: {s};", .{ wn, try self.tyText(t) });
                try self.push(try self.newSym(.{ .name = d.name, .wname = wn, .kind = .var_, .ty = t }));
            }
        }
        _ = s;
    }

    // ----------------------------------------------------------------- expression statements
    fn lowerExprStmt(self: *Lowerer, e: *P.Expr) Error!void {
        switch (e.kind) {
            .assign => _ = try self.lowerAssign(e, true),
            .postfix => |x| try self.incStmt(x.e, x.op, e),
            .unary => |u| {
                if (std.mem.eql(u8, u.op, "++") or std.mem.eql(u8, u.op, "--")) return self.incStmt(u.e, u.op, e);
                const v = try self.lowerExpr(e);
                if (v.ty != .void) try self.line("_ = {s};", .{v.text});
            },
            .comma => |c| {
                try self.lowerExprStmt(c.a);
                try self.lowerExprStmt(c.b);
            },
            .ternary => |t| {
                const c = try self.toBool(try self.lowerExpr(t.c), t.c);
                try self.line("if ({s}) {{", .{c});
                self.ctx.indent += 1;
                try self.lowerExprStmt(t.a);
                self.ctx.indent -= 1;
                try self.line("}} else {{", .{});
                self.ctx.indent += 1;
                try self.lowerExprStmt(t.b);
                self.ctx.indent -= 1;
                try self.line("}}", .{});
            },
            else => {
                const v = try self.lowerExpr(e);
                if (v.special != .none) return;
                if (v.ty == .void) {
                    if (v.text.len > 0) try self.line("{s};", .{v.text});
                } else if (!v.pure) try self.line("_ = {s};", .{v.text});
            },
        }
    }

    fn requireWritable(self: *Lowerer, v: Val, e: *const P.Expr) Error!void {
        if (v.lv == .ref) {
            if (v.workgroup) if (self.ctx.inst) |i| {
                i.impure = true;
            };
            return;
        }
        if (v.psym) |ps| {
            if (!ps.needs_var) {
                ps.needs_var = true;
                self.ctx.retry = true;
            }
            return;
        }
        if (v.special == .ptr) return self.errE(e, "changing a pointer itself (not what it points to) is not supported", .{});
        return self.errE(e, "cannot assign to this expression (it is const or a temporary)", .{});
    }

    fn incStmt(self: *Lowerer, target: *P.Expr, op: []const u8, e: *P.Expr) Error!void {
        const v = try self.lowerExpr(target);
        try self.requireWritable(v, e);
        const s = scalarOf(v.ty) orelse return self.errE(e, "{s} on {s}", .{ op, try self.mslName(v.ty) });
        if (v.swz != null) return self.errE(e, "{s} on a swizzle", .{op});
        if (v.ty == .scalar and (s == .i32 or s == .u32)) {
            try self.line("{s}{s};", .{ v.text, op });
        } else {
            const one = try self.coerce(.{ .ty = t_i32, .text = "1i", .lit = .{ .int = 1 } }, v.ty, e);
            try self.line("{s} {c}= {s};", .{ v.text, op[0], one });
        }
    }

    fn lowerAssign(self: *Lowerer, e: *P.Expr, as_stmt: bool) Error!?Val {
        const as = e.kind.assign;
        const lhs = try self.lowerExpr(as.lhs);
        try self.requireWritable(lhs, as.lhs);
        if (lhs.flat != null) return self.errE(as.lhs, "assigning to a row of a constant array", .{});
        if (lhs.ty == .atomic) return self.errE(as.lhs, "assign atomics with atomic_store_explicit", .{});
        var rhs_txt: []const u8 = undefined;
        var op: []const u8 = "=";
        if (std.mem.eql(u8, as.op, "=")) {
            rhs_txt = try self.initText(lhs.ty, as.rhs);
        } else {
            const rv = try self.lowerExpr(as.rhs);
            const bop = as.op[0 .. as.op.len - 1];
            const r = try self.arith(bop, lhs, rv, e);
            if (eql(r.val.ty, lhs.ty) and lhs.swz == null) {
                op = as.op;
                rhs_txt = r.b;
            } else {
                rhs_txt = try self.coerce(r.val, lhs.ty, e);
            }
        }
        if (lhs.swz) |sw| {
            const t = try self.newTmp();
            try self.line("let {s}: {s} = {s};", .{ t, try self.tyText(lhs.ty), rhs_txt });
            for (sw.comps, 0..) |c, i| try self.line("{s}.{c} = {s}.{c};", .{ sw.base, c, t, "xyzw"[i] });
        } else {
            try self.line("{s} {s} {s};", .{ lhs.text, op, rhs_txt });
        }
        if (as_stmt) return null;
        var r = lhs;
        r.pure = false;
        r.lit = null;
        return r;
    }

    fn addrOf(self: *Lowerer, v: Val) Error!?[]const u8 {
        if (v.addr) |a| return a;
        if (v.psym) |ps| if (std.mem.eql(u8, v.text, ps.wname)) {
            if (!ps.needs_var) {
                ps.needs_var = true;
                self.ctx.retry = true;
            }
            return try self.p("&{s}", .{ps.wname});
        };
        return null;
    }

    // ----------------------------------------------------------------- expressions
    fn lowerExpr(self: *Lowerer, e: *P.Expr) Error!Val {
        switch (e.kind) {
            .ident => |n| return self.lowerIdent(n, e),
            .int_lit => |l| {
                const t: Type = if (l.unsigned) t_u32 else t_i32;
                return .{ .ty = t, .text = try self.p("{d}{s}", .{ l.value, if (l.unsigned) "u" else "i" }), .lit = .{ .int = @intCast(l.value) } };
            },
            .float_lit => |t| return .{ .ty = t_f32, .text = try self.floatText(t), .lit = .{ .float = t } },
            .bool_lit => |b| return .{ .ty = t_bool, .text = if (b) "true" else "false", .lit = .{ .boolean = b } },
            .char_lit => |c| return .{ .ty = t_i32, .text = try self.p("{d}i", .{c}), .lit = .{ .int = c } },
            .str_lit => |s| {
                const off = try self.poolString(s);
                return .{ .ty = .{ .ptr = try self.newType(t_i32) }, .text = "", .special = .{ .ptr = .{ .kind = .pool, .off = try self.p("{d}i", .{off}), .elem = t_i32, .n = @intCast(s.len + 1) } } };
            },
            .unary => return self.lowerUnary(e),
            .postfix => |x| {
                const v = try self.lowerExpr(x.e);
                try self.requireWritable(v, e);
                if (v.special == .ptr) return self.errE(e, "pointer increments are not supported", .{});
                const t = try self.newTmp();
                try self.line("let {s}: {s} = {s};", .{ t, try self.tyText(v.ty), v.text });
                try self.incStmt(x.e, x.op, e);
                return .{ .ty = v.ty, .text = t, .pure = false };
            },
            .binary => return self.lowerBinary(e),
            .assign => return (try self.lowerAssign(e, false)).?,
            .ternary => return self.lowerTernary(e),
            .call => return self.lowerCall(e),
            .member => return self.lowerMember(e),
            .index => return self.lowerIndex(e),
            .cast => |c| {
                const t = try self.resolveType(c.ty);
                const v = try self.lowerExpr(c.e);
                var r = v;
                r.text = try self.convertExplicit(v, t, c.e);
                r.ty = t;
                r.lv = .none;
                r.addr = null;
                r.swz = null;
                r.psym = null;
                if (v.lit) |l| if (scalarOf(t)) |ts| if (ts != .bool) {
                    r.lit = l;
                };
                return self.halfRound(c.ty.name, r);
            },
            .construct => |c| {
                const t = try self.resolveType(c.ty);
                return self.constructCall(t, c.args, e);
            },
            .init_list => return self.errE(e, "an initialiser list needs a known type here", .{}),
            .lambda => return self.errE(e, "lambdas are supported only as `auto name = [&](...) {{ ... }};`", .{}),
            .comma => |c| {
                try self.lowerExprStmt(c.a);
                return self.lowerExpr(c.b);
            },
        }
    }

    /// Metal's half is translated to f32 (web/README.md); an explicit conversion to a half type
    /// still rounds to half precision, as Metal does (themes use it to split a value into a
    /// half-exact coarse part and a fine remainder before storing both in a 16-bit texture).
    fn halfRound(self: *Lowerer, type_name: []const u8, v: Val) Error!Val {
        if (!std.mem.startsWith(u8, type_name, "half")) return v;
        if (scalarOf(v.ty) != .f32) return v;
        var r = v;
        r.text = try self.p("quantizeToF16({s})", .{v.text});
        r.lit = null;
        return r;
    }

    fn convertExplicit(self: *Lowerer, v: Val, t: Type, e: *const P.Expr) Error![]const u8 {
        if (v.lit) |l| if (scalarOf(t)) |ts| if (t == .scalar) {
            if (try self.litText(l, ts)) |txt| return txt;
        };
        return self.coerce(v, t, e);
    }

    fn stripNs(n: []const u8) []const u8 {
        for ([_][]const u8{ "metal::", "fast::", "precise::", "metal::fast::", "metal::precise::" }) |pre| {
            if (std.mem.startsWith(u8, n, pre)) return stripNs(n[pre.len..]);
        }
        return n;
    }

    fn symVal(self: *Lowerer, s: *Sym) Error!Val {
        switch (s.kind) {
            .let_ => return .{ .ty = s.ty, .text = s.wname, .lv = if (s.param) .none else .let_, .psym = if (s.param) s else null },
            .var_ => return .{ .ty = s.ty, .text = s.wname, .lv = .ref, .addr = if (s.workgroup) null else try self.p("&{s}", .{s.wname}), .workgroup = s.workgroup },
            .ptr => return .{ .ty = s.ty, .text = try self.p("(*{s})", .{s.wname}), .lv = .ref, .addr = s.wname },
            .gconst => {
                if (s.helper) |h| try self.needHelper(s.name, h);
                return .{ .ty = s.ty, .text = s.wname, .lv = .let_, .lit = if (s.ival) |iv| (if (s.ty == .scalar and s.ty.scalar != .f32) Lit{ .int = iv } else null) else null };
            },
            .static_ => return .{ .ty = s.ty, .text = switch (s.special) {
                .frame => "f",
                .stats => "s",
                .texture => |g| g,
                else => "",
            }, .special = s.special },
        }
    }

    fn lowerIdent(self: *Lowerer, raw_name: []const u8, e: *P.Expr) Error!Val {
        const n = stripNs(raw_name);
        if (self.lookup(n)) |s| {
            var v = try self.symVal(s);
            if (s.kind == .gconst) {
                v.lit = null; // keep named constants by name
                if (s.flat_inner > 0) v.flat = .{ .name = s.wname, .row = "", .inner = s.flat_inner, .elem = s.ty.array.elem.*.array.elem.* };
            }
            return v;
        }
        if (self.funcs.contains(n)) return .{ .ty = .void, .text = n, .special = .{ .funcs = n } };
        if (P.isBuiltinTypeName(n) or self.struct_idx.contains(n) or self.typedefs.contains(n)) {
            const t = try self.resolveType(.{ .name = n, .line = e.line, .col = e.col });
            return .{ .ty = t, .text = "", .special = .{ .typename = t } };
        }
        if (std.mem.indexOf(u8, n, "::") != null) return .{ .ty = .void, .text = n, .special = .{ .funcs = n } };
        return .{ .ty = .void, .text = n, .special = .{ .funcs = n } };
    }

    fn lowerUnary(self: *Lowerer, e: *P.Expr) Error!Val {
        const u = e.kind.unary;
        if (std.mem.eql(u8, u.op, "++") or std.mem.eql(u8, u.op, "--")) {
            try self.incStmt(u.e, u.op, e);
            var v = try self.lowerExpr(u.e);
            v.pure = false;
            return v;
        }
        if (std.mem.eql(u8, u.op, "&")) {
            const v = try self.lowerExpr(u.e);
            if (v.lv != .ref) return self.errE(e, "taking the address of this expression is not supported", .{});
            return .{ .ty = .{ .ptr = try self.newType(v.ty) }, .text = try self.p("&{s}", .{v.text}), .pure = false, .workgroup = v.workgroup };
        }
        const v = try self.lowerExpr(u.e);
        if (std.mem.eql(u8, u.op, "*")) {
            if (v.special != .ptr) return self.errE(e, "dereferencing {s}", .{try self.describe(v)});
            return self.ptrIndex(v, .{ .ty = t_i32, .text = "0i", .lit = .{ .int = 0 } }, e);
        }
        if (v.special != .none) return self.errE(e, "operator {s} on {s}", .{ u.op, try self.describe(v) });
        if (std.mem.eql(u8, u.op, "+")) return v;
        if (std.mem.eql(u8, u.op, "!")) {
            const b = try self.toBool(v, u.e);
            return .{ .ty = t_bool, .text = try self.p("!({s})", .{b}), .pure = v.pure, .cheap = v.cheap };
        }
        const s = scalarOf(v.ty) orelse if (v.ty == .mat and std.mem.eql(u8, u.op, "-")) Scalar.f32 else return self.errE(e, "operator {s} on {s}", .{ u.op, try self.mslName(v.ty) });
        if (std.mem.eql(u8, u.op, "-")) {
            if (v.lit) |l| switch (l) {
                .int => |iv| {
                    const t: Type = if (s == .u32) t_u32 else t_i32;
                    if (s == .u32) return .{ .ty = t, .text = try self.p("{d}u", .{@as(u32, @truncate(@as(u64, @bitCast(-iv))))}), .lit = .{ .int = -iv } };
                    return .{ .ty = t, .text = try self.p("-{d}i", .{iv}), .lit = .{ .int = -iv } };
                },
                .float => |ft| {
                    const nt = if (ft.len > 0 and ft[0] == '-') ft[1..] else try self.p("-{s}", .{ft});
                    return .{ .ty = t_f32, .text = try self.floatText(nt), .lit = .{ .float = nt } };
                },
                .boolean => {},
            };
            const ps = promote(s);
            const t = if (v.ty == .mat) v.ty else shape(ps, widthOf(v.ty));
            const txt = try self.coerce(v, t, u.e);
            if (ps == .u32) return .{ .ty = t, .text = try self.p("({s}() - {s})", .{ try self.tyText(t), txt }), .pure = v.pure, .cheap = v.cheap };
            return .{ .ty = t, .text = try self.p("(-{s})", .{txt}), .pure = v.pure, .cheap = v.cheap };
        }
        if (std.mem.eql(u8, u.op, "~")) {
            if (s == .f32) return self.errE(e, "~ on a float", .{});
            const t = shape(promote(s), widthOf(v.ty));
            return .{ .ty = t, .text = try self.p("(~{s})", .{try self.coerce(v, t, u.e)}), .pure = v.pure, .cheap = v.cheap };
        }
        return self.errE(e, "unary operator {s} is not supported", .{u.op});
    }

    const Arith = struct { val: Val, a: []const u8, b: []const u8 };

    fn isCmp(op: []const u8) bool {
        for ([_][]const u8{ "<", ">", "<=", ">=", "==", "!=" }) |c| if (std.mem.eql(u8, op, c)) return true;
        return false;
    }

    /// C++'s usual arithmetic conversions for `a op b`, and the WGSL for it.
    fn arith(self: *Lowerer, op: []const u8, a: Val, b: Val, e: *const P.Expr) Error!Arith {
        const pure = a.pure and b.pure;
        const cheap = a.cheap and b.cheap;
        const decays = a.special == .none and a.ty == .array and a.flat == null;
        if ((a.special == .ptr or decays) and (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-"))) {
            if (b.ty != .scalar or b.ty.scalar == .f32 or b.special != .none) return self.errE(e, "pointer arithmetic needs an integer", .{});
            var pv = if (decays) ((try self.arrayPtr(a)) orelse return self.errE(e, "pointer arithmetic on this array is not supported", .{})).ptr else a.special.ptr;
            const bt = try self.coerce(b, t_i32, e);
            pv.off = if (std.mem.eql(u8, pv.off, "0i")) (if (op[0] == '-') try self.p("(-{s})", .{bt}) else bt) else try self.p("({s} {s} {s})", .{ pv.off, op, bt });
            return .{ .val = .{ .ty = a.ty, .text = "", .special = .{ .ptr = pv }, .pure = pure }, .a = "", .b = bt };
        }
        if (a.special != .none or b.special != .none) return self.errE(e, "operator {s} on {s} and {s}", .{ op, try self.describe(a), try self.describe(b) });
        if (a.ty == .mat or b.ty == .mat) return self.matArith(op, a, b, e);
        const sa = scalarOf(a.ty) orelse return self.errE(e, "operator {s} on {s}", .{ op, try self.mslName(a.ty) });
        const sb = scalarOf(b.ty) orelse return self.errE(e, "operator {s} on {s}", .{ op, try self.mslName(b.ty) });
        const na = widthOf(a.ty);
        const nb = widthOf(b.ty);
        if (na > 1 and nb > 1 and na != nb) return self.errE(e, "operator {s} on {s} and {s}", .{ op, try self.mslName(a.ty), try self.mslName(b.ty) });
        const n = @max(na, nb);
        if (std.mem.eql(u8, op, "<<") or std.mem.eql(u8, op, ">>")) {
            const ps = promote(sa);
            if (ps == .f32 or sb == .f32) return self.errE(e, "shift of a float", .{});
            const rt = shape(ps, na);
            const at = try self.coerce(a, rt, e);
            const bt = try self.coerce(b, shape(.u32, na), e);
            return .{ .val = .{ .ty = rt, .text = try self.p("({s} {s} {s})", .{ at, op, bt }), .pure = pure, .cheap = cheap }, .a = at, .b = bt };
        }
        const bitwise = std.mem.eql(u8, op, "&") or std.mem.eql(u8, op, "|") or std.mem.eql(u8, op, "^");
        var k: Scalar = undefined;
        if ((bitwise or std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=")) and sa == .bool and sb == .bool) {
            k = .bool;
        } else {
            // a literal adopts the other side's kind when that keeps its value (2 * x, x < 0)
            const pa = promote(sa);
            const pb = promote(sb);
            k = maxScalar(pa, pb);
            if (a.lit != null and a.lit.? == .int and b.lit == null and pb != .bool) k = if (pa == .f32 or pb == .f32) .f32 else pb;
            if (b.lit != null and b.lit.? == .int and a.lit == null and pa != .bool) k = if (pa == .f32 or pb == .f32) .f32 else pa;
        }
        if (bitwise and k == .f32) return self.errE(e, "bitwise operator {s} on a float", .{op});
        const cmp = isCmp(op);
        const splat = cmp or bitwise;
        const at = try self.coerce(a, shape(k, if (splat) n else na), e);
        const bt = try self.coerce(b, shape(k, if (splat) n else nb), e);
        const rt: Type = if (cmp) shape(.bool, n) else shape(k, n);
        if (std.mem.eql(u8, op, "%") and k == .f32) {
            return .{ .val = .{ .ty = rt, .text = try self.p("({s} % {s})", .{ at, bt }), .pure = pure, .cheap = cheap }, .a = at, .b = bt };
        }
        return .{ .val = .{ .ty = rt, .text = try self.p("({s} {s} {s})", .{ at, op, bt }), .pure = pure, .cheap = cheap }, .a = at, .b = bt };
    }

    fn matArith(self: *Lowerer, op: []const u8, a: Val, b: Val, e: *const P.Expr) Error!Arith {
        const pure = a.pure and b.pure;
        var rt: Type = undefined;
        var at: []const u8 = undefined;
        var bt: []const u8 = undefined;
        if (std.mem.eql(u8, op, "*")) {
            if (a.ty == .mat and b.ty == .mat) {
                if (a.ty.mat.c != b.ty.mat.r) return self.errE(e, "matrix product with mismatched sizes", .{});
                rt = .{ .mat = .{ .c = b.ty.mat.c, .r = a.ty.mat.r } };
                at = a.text;
                bt = b.text;
            } else if (a.ty == .mat) {
                if (b.ty == .vec) {
                    rt = shape(.f32, a.ty.mat.r);
                    at = a.text;
                    bt = try self.coerce(b, shape(.f32, a.ty.mat.c), e);
                } else {
                    rt = a.ty;
                    at = a.text;
                    bt = try self.coerce(b, t_f32, e);
                }
            } else {
                if (a.ty == .vec) {
                    rt = shape(.f32, b.ty.mat.c);
                    at = try self.coerce(a, shape(.f32, b.ty.mat.r), e);
                    bt = b.text;
                } else {
                    rt = b.ty;
                    at = try self.coerce(a, t_f32, e);
                    bt = b.text;
                }
            }
        } else if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) {
            if (!(a.ty == .mat and b.ty == .mat and eql(a.ty, b.ty))) return self.errE(e, "matrix {s} needs two matrices of the same size", .{op});
            rt = a.ty;
            at = a.text;
            bt = b.text;
        } else return self.errE(e, "operator {s} on a matrix", .{op});
        return .{ .val = .{ .ty = rt, .text = try self.p("({s} {s} {s})", .{ at, op, bt }), .pure = pure, .cheap = false }, .a = at, .b = bt };
    }

    fn lowerBinary(self: *Lowerer, e: *P.Expr) Error!Val {
        const b = e.kind.binary;
        if (std.mem.eql(u8, b.op, "&&") or std.mem.eql(u8, b.op, "||")) {
            const av = try self.lowerExpr(b.a);
            const at = try self.toBool(av, b.a);
            const cap = try self.beginCapture(1);
            const bv = try self.lowerExpr(b.b);
            const bt = try self.toBool(bv, b.b);
            const pre = self.endCapture(cap);
            if (pre.len == 0 and bv.pure) return .{ .ty = t_bool, .text = try self.p("({s} {s} {s})", .{ at, b.op, bt }), .pure = av.pure, .cheap = av.cheap and bv.cheap };
            if (self.ctx.global) return self.errE(e, "side effects in a constant expression", .{});
            const t = try self.newTmp();
            try self.line("var {s}: bool = {s};", .{ t, at });
            try self.line("if ({s}{s}) {{", .{ if (b.op[0] == '|') "!" else "", t });
            try self.raw(pre);
            self.ctx.indent += 1;
            try self.line("{s} = {s};", .{ t, bt });
            self.ctx.indent -= 1;
            try self.line("}}", .{});
            return .{ .ty = t_bool, .text = t, .pure = false };
        }
        const av = try self.lowerExpr(b.a);
        const bv = try self.lowerExpr(b.b);
        const r = try self.arith(b.op, av, bv, e);
        return r.val;
    }

    fn unify(self: *Lowerer, a: Val, b: Val, e: *const P.Expr) Error!Type {
        if (eql(a.ty, b.ty)) return a.ty;
        const sa = scalarOf(a.ty) orelse return self.errE(e, "mismatched types {s} and {s}", .{ try self.mslName(a.ty), try self.mslName(b.ty) });
        const sb = scalarOf(b.ty) orelse return self.errE(e, "mismatched types {s} and {s}", .{ try self.mslName(a.ty), try self.mslName(b.ty) });
        const na = widthOf(a.ty);
        const nb = widthOf(b.ty);
        if (na > 1 and nb > 1 and na != nb) return self.errE(e, "mismatched types {s} and {s}", .{ try self.mslName(a.ty), try self.mslName(b.ty) });
        var k = maxScalar(promote(sa), promote(sb));
        if (sa == .bool and sb == .bool) k = .bool;
        if (a.lit != null and b.lit == null and sb != .bool) k = if (sa == .f32 or sb == .f32) .f32 else sb;
        if (b.lit != null and a.lit == null and sa != .bool) k = if (sa == .f32 or sb == .f32) .f32 else sa;
        return shape(k, @max(na, nb));
    }

    fn lowerTernary(self: *Lowerer, e: *P.Expr) Error!Val {
        const t = e.kind.ternary;
        const cv = try self.lowerExpr(t.c);
        const c = try self.toBool(cv, t.c);
        const capa = try self.beginCapture(1);
        const va = try self.lowerExpr(t.a);
        const prea = self.endCapture(capa);
        const capb = try self.beginCapture(1);
        const vb = try self.lowerExpr(t.b);
        const preb = self.endCapture(capb);
        // pointers into the string pool: select the offset
        if (va.special == .ptr and vb.special == .ptr and va.special.ptr.kind == .pool and vb.special.ptr.kind == .pool and prea.len == 0 and preb.len == 0) {
            var pv = va.special.ptr;
            pv.off = try self.p("select({s}, {s}, {s})", .{ vb.special.ptr.off, va.special.ptr.off, c });
            return .{ .ty = va.ty, .text = "", .special = .{ .ptr = pv } };
        }
        if (va.special != .none or vb.special != .none) return self.errE(e, "a ternary choosing between {s} and {s} is not supported", .{ try self.describe(va), try self.describe(vb) });
        var rt: Type = undefined;
        if (va.ty == .strct or va.ty == .array or va.ty == .mat or vb.ty == .strct or vb.ty == .array) {
            if (!eql(va.ty, vb.ty)) return self.errE(e, "a ternary between {s} and {s}", .{ try self.mslName(va.ty), try self.mslName(vb.ty) });
            rt = va.ty;
        } else rt = try self.unify(va, vb, e);
        const easy = prea.len == 0 and preb.len == 0 and va.pure and vb.pure and va.cheap and vb.cheap and rt != .array;
        if (easy or self.ctx.global) {
            if (prea.len != 0 or preb.len != 0) return self.errE(e, "side effects in a constant expression", .{});
            const at = try self.coerce(va, rt, t.a);
            const bt = try self.coerce(vb, rt, t.b);
            var r: Val = .{ .ty = rt, .text = try self.p("select({s}, {s}, {s})", .{ bt, at, c }), .pure = cv.pure };
            if (va.lit != null and vb.lit != null) r.lit = null;
            return r;
        }
        const tmp = try self.newTmp();
        try self.line("var {s}: {s};", .{ tmp, try self.tyText(rt) });
        try self.line("if ({s}) {{", .{c});
        try self.raw(prea);
        self.ctx.indent += 1;
        try self.line("{s} = {s};", .{ tmp, try self.coerce(va, rt, t.a) });
        self.ctx.indent -= 1;
        try self.line("}} else {{", .{});
        try self.raw(preb);
        self.ctx.indent += 1;
        try self.line("{s} = {s};", .{ tmp, try self.coerce(vb, rt, t.b) });
        self.ctx.indent -= 1;
        try self.line("}}", .{});
        return .{ .ty = rt, .text = tmp, .pure = va.pure and vb.pure, .cheap = true };
    }

    fn swizzleIndex(c: u8) ?u8 {
        return switch (c) {
            'x', 'r' => 0,
            'y', 'g' => 1,
            'z', 'b' => 2,
            'w', 'a' => 3,
            else => null,
        };
    }

    fn lowerMember(self: *Lowerer, e: *P.Expr) Error!Val {
        const m = e.kind.member;
        const base = try self.lowerExpr(m.e);
        if (m.arrow) return self.errE(e, "the -> operator is not supported", .{});
        if (base.special == .stats and std.mem.eql(u8, m.name, "procs")) return .{ .ty = .void, .text = "s.procs", .special = .procs };
        if (base.special != .none and base.special != .frame and base.special != .stats) return self.errE(e, "member .{s} of {s}", .{ m.name, try self.describe(base) });
        switch (base.ty) {
            .strct => |si| {
                const info = self.structs.items[si];
                for (info.fields) |f| {
                    if (!std.mem.eql(u8, f.name, m.name)) continue;
                    if (si == 1 and std.mem.eql(u8, f.name, "name")) {
                        const idx = base.proc_idx orelse return self.errE(e, "ArgusProc.name outside s.procs[i]", .{});
                        return .{ .ty = .{ .ptr = try self.newType(t_u32) }, .text = "", .special = .{ .ptr = .{ .kind = .proc, .ref = idx, .elem = t_u32, .n = 32 } } };
                    }
                    return .{ .ty = f.ty, .text = try self.p("{s}.{s}", .{ base.text, f.wname }), .lv = base.lv, .psym = base.psym, .pure = base.pure, .cheap = base.cheap, .workgroup = base.workgroup };
                }
                return self.errE(e, "{s} has no member '{s}'", .{ info.name, m.name });
            },
            .vec => |v| {
                if (m.name.len == 0 or m.name.len > 4) return self.errE(e, "bad swizzle .{s}", .{m.name});
                var comps: std.ArrayList(u8) = .empty;
                for (m.name) |c| {
                    const ix = swizzleIndex(c) orelse return self.errE(e, "bad swizzle .{s}", .{m.name});
                    if (ix >= v.n) return self.errE(e, "swizzle .{s} on a {d}-component vector", .{ m.name, v.n });
                    try comps.append(self.a, "xyzw"[ix]);
                }
                const t = shape(v.s, @intCast(comps.items.len));
                var r: Val = .{ .ty = t, .text = try self.p("{s}.{s}", .{ base.text, comps.items }), .pure = base.pure, .cheap = base.cheap, .psym = base.psym };
                if (comps.items.len == 1) {
                    r.lv = base.lv;
                } else if (base.lv == .ref) {
                    for (comps.items, 0..) |c, i| for (comps.items[0..i]) |c2| if (c == c2) return self.errE(e, "assignment to a swizzle with a repeated component", .{});
                    r.lv = .ref;
                    r.swz = .{ .base = base.text, .comps = comps.items };
                }
                return r;
            },
            else => return self.errE(e, "member .{s} of {s}", .{ m.name, try self.mslName(base.ty) }),
        }
    }

    fn indexText(self: *Lowerer, v: Val, e: *const P.Expr) Error![]const u8 {
        if (v.special != .none) return self.errE(e, "an index must be an integer", .{});
        const s = scalarOf(v.ty) orelse return self.errE(e, "an index must be an integer", .{});
        if (v.ty != .scalar or s == .f32) return self.errE(e, "an index must be an integer, found {s}", .{try self.mslName(v.ty)});
        if (s == .bool) return self.coerce(v, t_i32, e);
        return v.text;
    }

    fn ptrIndex(self: *Lowerer, base: Val, iv: Val, e: *const P.Expr) Error!Val {
        const pv = base.special.ptr;
        const it = try self.coerce(iv, t_i32, e);
        const off = if (std.mem.eql(u8, pv.off, "0i")) it else if (std.mem.eql(u8, it, "0i")) pv.off else try self.p("({s} + {s})", .{ pv.off, it });
        switch (pv.kind) {
            .local => return .{ .ty = pv.elem, .text = try self.p("{s}[{s}]", .{ pv.ref, off }), .lv = if (pv.writable) .ref else .let_, .pure = iv.pure },
            .pool => return .{ .ty = pv.elem, .text = try self.p("M2W_STR[{s}]", .{off}), .lv = .let_, .pure = iv.pure },
            .proc => return .{ .ty = t_u32, .text = try self.p("argus_proc_char(u32({s}), u32({s}))", .{ pv.ref, off }), .pure = iv.pure },
        }
    }

    fn lowerIndex(self: *Lowerer, e: *P.Expr) Error!Val {
        const x = e.kind.index;
        const base = try self.lowerExpr(x.e);
        const iv = try self.lowerExpr(x.i);
        if (base.flat) |fl| {
            const it = try self.indexText(iv, x.i);
            if (fl.row.len == 0) {
                var r = base;
                r.flat = .{ .name = fl.name, .row = it, .inner = fl.inner, .elem = fl.elem };
                return r;
            }
            return .{ .ty = fl.elem, .text = try self.p("{s}[({s}) * {d} + ({s})]", .{ fl.name, fl.row, fl.inner, it }), .lv = .let_, .pure = base.pure and iv.pure };
        }
        if (base.special == .procs) {
            const it = try self.indexText(iv, x.i);
            return .{ .ty = .{ .strct = 1 }, .text = try self.p("s.procs[{s}]", .{it}), .proc_idx = it, .lv = .let_ };
        }
        if (base.special == .ptr) return self.ptrIndex(base, iv, x.i);
        if (base.special != .none) return self.errE(e, "indexing {s}", .{try self.describe(base)});
        const it = try self.indexText(iv, x.i);
        const pure = base.pure and iv.pure;
        switch (base.ty) {
            .array => |arr| {
                if (arr.elem.* == .ptr) return .{ .ty = arr.elem.*, .text = "", .special = .{ .ptr = .{ .kind = .pool, .off = try self.p("{s}[{s}]", .{ base.text, it }), .elem = arr.elem.*.ptr.* } }, .pure = pure };
                return .{ .ty = arr.elem.*, .text = try self.p("{s}[{s}]", .{ base.text, it }), .lv = base.lv, .psym = base.psym, .pure = pure, .cheap = base.cheap and iv.cheap, .workgroup = base.workgroup };
            },
            .vec => |v| return .{ .ty = .{ .scalar = v.s }, .text = try self.p("{s}[{s}]", .{ base.text, it }), .lv = base.lv, .psym = base.psym, .pure = pure, .cheap = base.cheap and iv.cheap },
            .mat => |m| return .{ .ty = shape(.f32, m.r), .text = try self.p("{s}[{s}]", .{ base.text, it }), .lv = base.lv, .psym = base.psym, .pure = pure, .cheap = base.cheap and iv.cheap },
            else => return self.errE(e, "indexing {s}", .{try self.mslName(base.ty)}),
        }
    }

    // ----------------------------------------------------------------- constructors
    fn constructCall(self: *Lowerer, t: Type, args: []const *P.Expr, e: *P.Expr) Error!Val {
        switch (t) {
            .strct, .array => return .{ .ty = t, .text = try self.constructList(t, args, e), .cheap = true },
            else => {},
        }
        var vals: std.ArrayList(Val) = .empty;
        var pure = true;
        var cheap = true;
        for (args) |x| {
            const v = try self.lowerExpr(x);
            pure = pure and v.pure;
            cheap = cheap and v.cheap;
            try vals.append(self.a, v);
        }
        var r: Val = .{ .ty = t, .text = try self.constructVals(t, vals.items, args, e), .pure = pure, .cheap = cheap };
        if (t == .scalar and vals.items.len == 1 and vals.items[0].lit != null and t.scalar != .bool) r.lit = try self.convLit(vals.items[0].lit.?, t.scalar);
        return r;
    }

    fn convLit(self: *Lowerer, l: Lit, to: Scalar) Error!?Lit {
        _ = self;
        switch (l) {
            .int, .boolean => return l,
            .float => |ft| {
                if (to == .f32) return l;
                const v = std.fmt.parseFloat(f64, ft) catch return null;
                return Lit{ .int = @intFromFloat(@trunc(v)) };
            },
        }
    }

    fn constructVals(self: *Lowerer, t: Type, vals: []const Val, args: []const *P.Expr, e: *const P.Expr) Error![]const u8 {
        switch (t) {
            .scalar => |s| {
                if (vals.len == 0) return self.zeroValue(t);
                if (vals.len != 1) return self.errE(e, "{s}(...) takes one value", .{scalarText(s)});
                if (vals[0].ty == .vec) return self.errE(e, "{s}(vector)", .{scalarText(s)});
                return self.convertExplicit(vals[0], t, args[0]);
            },
            .vec => |v| {
                if (vals.len == 0) return self.zeroValue(t);
                if (vals.len == 1) {
                    if (vals[0].ty == .scalar or vals[0].special != .none) {
                        const inner = try self.convertExplicit(vals[0], .{ .scalar = v.s }, args[0]);
                        return self.p("{s}({s})", .{ try self.tyText(t), inner });
                    }
                    if (vals[0].ty == .vec and vals[0].ty.vec.n == v.n) return self.coerce(vals[0], t, args[0]);
                    if (vals[0].ty == .vec and vals[0].ty.vec.n > v.n) {
                        // float3(float4) is not C++; but float2(v.xyz) would be: reject both
                        return self.errE(e, "{s}({s}): narrowing a vector by construction", .{ try self.mslName(t), try self.mslName(vals[0].ty) });
                    }
                }
                var total: u32 = 0;
                var parts: std.ArrayList([]const u8) = .empty;
                for (vals, 0..) |x, i| {
                    const w = widthOf(x.ty);
                    if (x.ty != .scalar and x.ty != .vec) return self.errE(args[i], "{s} in a vector constructor", .{try self.describe(x)});
                    total += w;
                    try parts.append(self.a, try self.coerce(x, shape(v.s, w), args[i]));
                }
                if (total != v.n) return self.errE(e, "{s} constructor with {d} components", .{ try self.mslName(t), total });
                return self.p("{s}({s})", .{ try self.tyText(t), try std.mem.join(self.a, ", ", parts.items) });
            },
            .mat => |m| {
                var parts: std.ArrayList([]const u8) = .empty;
                if (vals.len == 1 and vals[0].ty == .scalar) {
                    // diagonal
                    const d = try self.coerce(vals[0], t_f32, args[0]);
                    for (0..m.c) |ci| for (0..m.r) |ri| try parts.append(self.a, if (ci == ri) d else "0.0f");
                } else if (vals.len == 1 and vals[0].ty == .mat) {
                    if (!eql(vals[0].ty, t)) return self.errE(e, "matrix size conversion", .{});
                    return vals[0].text;
                } else if (vals.len == m.c) {
                    for (vals, 0..) |x, i| try parts.append(self.a, try self.coerce(x, shape(.f32, m.r), args[i]));
                } else if (vals.len == @as(usize, m.c) * m.r) {
                    for (vals, 0..) |x, i| try parts.append(self.a, try self.coerce(x, t_f32, args[i]));
                } else return self.errE(e, "{s} constructor with {d} arguments", .{ try self.mslName(t), vals.len });
                return self.p("{s}({s})", .{ try self.tyText(t), try std.mem.join(self.a, ", ", parts.items) });
            },
            else => return self.errE(e, "constructing {s}", .{try self.mslName(t)}),
        }
    }

    // ----------------------------------------------------------------- calls
    fn lowerArgs(self: *Lowerer, args: []const *P.Expr) Error![]Val {
        const vals = try self.a.alloc(Val, args.len);
        for (args, 0..) |x, i| vals[i] = try self.lowerExpr(x);
        return vals;
    }

    fn lowerCall(self: *Lowerer, e: *P.Expr) Error!Val {
        const c = e.kind.call;
        if (c.callee.kind == .member) return self.lowerMethod(e);
        if (c.callee.kind != .ident) return self.errE(e, "calling an expression is not supported", .{});
        const name = stripNs(c.callee.kind.ident);
        if (c.targs.len > 0) {
            if (c.args.len != 1) return self.errE(e, "{s} takes one argument", .{name});
            const v = try self.lowerExpr(c.args[0]);
            const t = try self.resolveType(c.targs[0]);
            if (std.mem.eql(u8, name, "as_type")) {
                if (scalarOf(v.ty) == null or scalarOf(t) == null or widthOf(t) != widthOf(v.ty)) return self.errE(e, "as_type between {s} and {s}", .{ try self.mslName(v.ty), try self.mslName(t) });
                if (scalarOf(t).? == .bool or scalarOf(v.ty).? == .bool) return self.errE(e, "as_type with bool", .{});
                return .{ .ty = t, .text = try self.p("bitcast<{s}>({s})", .{ try self.tyText(t), v.text }), .pure = v.pure, .cheap = v.cheap };
            }
            return self.halfRound(c.targs[0].name, .{ .ty = t, .text = try self.convertExplicit(v, t, c.args[0]), .pure = v.pure, .cheap = v.cheap });
        }
        if (self.lookup(name)) |s| {
            if (s.special == .lambda) return self.callLambda(s.special.lambda, c.args, e);
            if (s.kind != .static_ or s.special != .typename) return self.errE(e, "{s} is not a function", .{name});
        }
        if (P.isBuiltinTypeName(name) or self.struct_idx.contains(name) or self.typedefs.contains(name)) {
            const t = try self.resolveType(.{ .name = name, .line = e.line, .col = e.col });
            const v = try self.constructCall(t, c.args, e);
            return self.halfRound(name, v);
        }
        if (self.funcs.get(name)) |list| return self.callUser(name, list.items, c.args, e);
        for (prelude_fns) |pf| if (std.mem.eql(u8, pf.name, name)) {
            if (c.args.len != pf.params.len) return self.errE(e, "{s} takes {d} arguments", .{ name, pf.params.len });
            var parts: std.ArrayList([]const u8) = .empty;
            var pure = true;
            for (c.args, 0..) |x, i| {
                const v = try self.lowerExpr(x);
                pure = pure and v.pure;
                try parts.append(self.a, try self.coerce(v, pf.params[i], x));
            }
            return .{ .ty = pf.ret, .text = try self.p("{s}({s})", .{ name, try std.mem.join(self.a, ", ", parts.items) }), .pure = pure, .cheap = false };
        };
        return self.callBuiltin(name, c.args, e);
    }

    // ---- textures
    fn lowerMethod(self: *Lowerer, e: *P.Expr) Error!Val {
        const c = e.kind.call;
        const m = c.callee.kind.member;
        const base = try self.lowerExpr(m.e);
        if (base.special != .texture) return self.errE(e, "method .{s}() on {s} is not supported", .{ m.name, try self.describe(base) });
        const g = base.special.texture;
        const args = try self.lowerArgs(c.args);
        const n = m.name;
        if (std.mem.eql(u8, n, "get_width") or std.mem.eql(u8, n, "get_height")) {
            if (args.len > 1 or (args.len == 1 and !(args[0].lit != null and args[0].lit.? == .int and args[0].lit.?.int == 0))) return self.errE(e, "mip levels are not supported", .{});
            return .{ .ty = t_u32, .text = try self.p("textureDimensions({s}).{s}", .{ g, if (n[4] == 'w') "x" else "y" }) };
        }
        if (std.mem.eql(u8, n, "read")) {
            if (args.len < 1 or args.len > 2) return self.errE(e, "read(coord[, lod])", .{});
            if (std.mem.endsWith(u8, g, "out")) return self.errE(e, "reading a write-only texture", .{});
            const ct = args[0].ty;
            if (!(ct == .vec and ct.vec.n == 2 and (ct.vec.s == .u32 or ct.vec.s == .i32))) return self.errE(c.args[0], "read() needs a uint2 or int2 coordinate, found {s}", .{try self.mslName(ct)});
            if (args.len == 2 and !(args[1].lit != null and args[1].lit.? == .int and args[1].lit.?.int == 0)) return self.errE(e, "mip levels are not supported", .{});
            return .{ .ty = t_v4f, .text = try self.p("textureLoad({s}, {s}, 0)", .{ g, args[0].text }), .pure = args[0].pure, .cheap = args[0].cheap };
        }
        if (std.mem.eql(u8, n, "write")) {
            if (args.len != 2) return self.errE(e, "write(value, coord)", .{});
            if (!std.mem.endsWith(u8, g, "out")) return self.errE(e, "writing a read-only texture", .{});
            const ct = args[1].ty;
            if (!(ct == .vec and ct.vec.n == 2 and (ct.vec.s == .u32 or ct.vec.s == .i32))) return self.errE(c.args[1], "write() needs a uint2 or int2 coordinate, found {s}", .{try self.mslName(ct)});
            const vt = try self.coerce(args[0], t_v4f, c.args[0]);
            if (self.ctx.inst) |i| i.impure = true;
            return .{ .ty = .void, .text = try self.p("textureStore({s}, {s}, {s})", .{ g, args[1].text, vt }), .pure = false };
        }
        if (std.mem.eql(u8, n, "sample")) {
            if (args.len < 2 or args.len > 3) return self.errE(e, "sample(sampler, uv[, level(x)])", .{});
            if (args[0].special != .sampler) return self.errE(c.args[0], "sample() needs a sampler", .{});
            if (std.mem.endsWith(u8, g, "out")) return self.errE(e, "sampling a write-only texture", .{});
            const sv = args[0].special.sampler;
            var uv = try self.coerce(args[1], t_v2f, c.args[1]);
            if (sv.pixel) uv = try self.p("({s} / vec2f(textureDimensions({s})))", .{ uv, g });
            var lvl: []const u8 = "0.0f";
            if (args.len == 3) {
                if (args[2].special != .level) return self.errE(c.args[2], "sample(): only a level(x) option is supported", .{});
                lvl = args[2].special.level;
            }
            return .{ .ty = t_v4f, .text = try self.p("textureSampleLevel({s}, {s}, {s}, {s})", .{ g, sv.g, uv, lvl }), .pure = args[1].pure, .cheap = args[1].cheap };
        }
        return self.errE(e, "texture method .{s}() is not supported", .{n});
    }

    // ---- builtins
    const fn1_float = [_][2][]const u8{
        .{ "sin", "sin" },         .{ "cos", "cos" },     .{ "tan", "tan" },           .{ "asin", "asin" },         .{ "acos", "acos" },
        .{ "atan", "atan" },       .{ "sinh", "sinh" },   .{ "cosh", "cosh" },         .{ "tanh", "tanh" },         .{ "asinh", "asinh" },
        .{ "acosh", "acosh" },     .{ "atanh", "atanh" }, .{ "exp", "exp" },           .{ "exp2", "exp2" },         .{ "log", "log" },
        .{ "log2", "log2" },       .{ "sqrt", "sqrt" },   .{ "rsqrt", "inverseSqrt" }, .{ "floor", "floor" },       .{ "ceil", "ceil" },
        .{ "fract", "fract" },     .{ "trunc", "trunc" }, .{ "rint", "round" },        .{ "saturate", "saturate" }, .{ "degrees", "degrees" },
        .{ "radians", "radians" },
    };
    const fn_any = [_][2][]const u8{
        .{ "abs", "abs" },  .{ "fabs", "abs" }, .{ "sign", "sign" },   .{ "min", "min" }, .{ "max", "max" },
        .{ "fmin", "min" }, .{ "fmax", "max" }, .{ "clamp", "clamp" },
    };
    const fn_float_n = [_][2][]const u8{
        .{ "pow", "pow" },               .{ "powr", "pow" }, .{ "step", "step" }, .{ "atan2", "atan2" }, .{ "mix", "mix" },
        .{ "smoothstep", "smoothstep" }, .{ "fma", "fma" },  .{ "fmod", "%" },
    };

    fn callBuiltin(self: *Lowerer, name: []const u8, arg_exprs: []const *P.Expr, e: *P.Expr) Error!Val {
        if (std.mem.eql(u8, name, "threadgroup_barrier")) {
            if (self.ctx.kernel == null) return self.errE(e, "threadgroup_barrier outside a kernel", .{});
            if (self.ctx.inst) |i| i.impure = true;
            return .{ .ty = .void, .text = "workgroupBarrier()", .pure = false };
        }
        if (std.mem.startsWith(u8, name, "atomic_")) return self.callAtomic(name, arg_exprs, e);
        if (std.mem.startsWith(u8, name, "simd_") or std.mem.startsWith(u8, name, "quad_") or std.mem.startsWith(u8, name, "simdgroup_"))
            return self.errE(e, "{s}(): SIMD-group functions have no WGSL equivalent the Argus web host can use (WGSL subgroups are an optional extension it does not enable)", .{name});
        if (std.mem.eql(u8, name, "level")) {
            if (arg_exprs.len != 1) return self.errE(e, "level(x)", .{});
            const v = try self.lowerExpr(arg_exprs[0]);
            return .{ .ty = .void, .text = "", .special = .{ .level = try self.coerce(v, t_f32, arg_exprs[0]) } };
        }
        if (std.mem.eql(u8, name, "sincos")) {
            // sincos(x, cosval): returns sin(x), writes cos(x) through the reference
            if (arg_exprs.len != 2) return self.errE(e, "sincos(x, cosval) takes 2 arguments", .{});
            const x = try self.lowerExpr(arg_exprs[0]);
            const cv = try self.lowerExpr(arg_exprs[1]);
            try self.requireWritable(cv, arg_exprs[1]);
            const t = shape(.f32, widthOf(x.ty));
            if (!eql(cv.ty, t)) return self.errE(arg_exprs[1], "sincos(): the cosine goes to a {s}", .{try self.mslName(t)});
            const tmp = try self.newTmp();
            try self.line("let {s}: {s} = {s};", .{ tmp, try self.tyText(t), try self.coerce(x, t, arg_exprs[0]) });
            if (cv.swz) |sw| {
                for (sw.comps, 0..) |c, i| try self.line("{s}.{c} = cos({s}).{c};", .{ sw.base, c, tmp, "xyzw"[i] });
            } else try self.line("{s} = cos({s});", .{ cv.text, tmp });
            return .{ .ty = t, .text = try self.p("sin({s})", .{tmp}), .pure = false };
        }
        const args = try self.lowerArgs(arg_exprs);
        var pure = true;
        var cheap = true;
        for (args, 0..) |v, i| {
            if (v.special != .none) return self.errE(arg_exprs[i], "{s} passed to {s}()", .{ try self.describe(v), name });
            pure = pure and v.pure;
            cheap = cheap and v.cheap;
        }
        const R = struct {
            fn val(t: Type, text: []const u8, pu: bool, ch: bool) Val {
                return .{ .ty = t, .text = text, .pure = pu, .cheap = ch };
            }
        };
        for (fn1_float) |f| if (std.mem.eql(u8, f[0], name)) {
            if (args.len != 1) return self.errE(e, "{s}() takes one argument", .{name});
            const t = shape(.f32, widthOf(args[0].ty));
            if (scalarOf(args[0].ty) == null) return self.errE(e, "{s}() of {s}", .{ name, try self.mslName(args[0].ty) });
            return R.val(t, try self.p("{s}({s})", .{ f[1], try self.coerce(args[0], t, arg_exprs[0]) }), pure, cheap);
        };
        if (std.mem.eql(u8, name, "round")) {
            if (args.len != 1) return self.errE(e, "round() takes one argument", .{});
            const t = shape(.f32, widthOf(args[0].ty));
            const tt = try self.tyText(t);
            const hn = try self.p("m2w_round_{s}", .{tt});
            try self.needHelper(hn, try self.p("// Metal's round(): halfway cases away from zero (WGSL's round() goes to even).\nfn {s}(x: {s}) -> {s} {{ let t = trunc(x); return select(t, t + sign(x), abs(x - t) >= {s}(0.5f)); }}\n", .{ hn, tt, tt, tt }));
            return R.val(t, try self.p("{s}({s})", .{ hn, try self.coerce(args[0], t, arg_exprs[0]) }), pure, cheap);
        }
        if (std.mem.eql(u8, name, "log10")) {
            if (args.len != 1) return self.errE(e, "log10() takes one argument", .{});
            const t = shape(.f32, widthOf(args[0].ty));
            return R.val(t, try self.p("(log2({s}) * 0.30102999566398119521f)", .{try self.coerce(args[0], t, arg_exprs[0])}), pure, cheap);
        }
        if (std.mem.eql(u8, name, "exp10")) {
            if (args.len != 1) return self.errE(e, "exp10() takes one argument", .{});
            const t = shape(.f32, widthOf(args[0].ty));
            return R.val(t, try self.p("exp2({s} * 3.32192809488736234787f)", .{try self.coerce(args[0], t, arg_exprs[0])}), pure, cheap);
        }
        for (fn_any) |f| if (std.mem.eql(u8, f[0], name)) {
            const want: usize = if (std.mem.eql(u8, name, "clamp")) 3 else if (std.mem.eql(u8, name, "abs") or std.mem.eql(u8, name, "fabs") or std.mem.eql(u8, name, "sign")) 1 else 2;
            if (args.len != want) return self.errE(e, "{s}() takes {d} arguments", .{ name, want });
            var t = args[0].ty;
            for (args[1..]) |x| t = try self.unify(.{ .ty = t, .text = "" }, x, e);
            if (scalarOf(t) == null) return self.errE(e, "{s}() of {s}", .{ name, try self.mslName(t) });
            if (scalarOf(t).? == .bool) t = shape(.i32, widthOf(t));
            if (name[0] == 'f' or std.mem.eql(u8, name, "sign")) t = shape(.f32, widthOf(t));
            if (std.mem.eql(u8, name, "abs") and scalarOf(t).? == .u32) return R.val(t, args[0].text, pure, cheap);
            var parts: std.ArrayList([]const u8) = .empty;
            for (args, 0..) |x, i| try parts.append(self.a, try self.coerce(x, t, arg_exprs[i]));
            return R.val(t, try self.p("{s}({s})", .{ f[1], try std.mem.join(self.a, ", ", parts.items) }), pure, cheap);
        };
        for (fn_float_n) |f| if (std.mem.eql(u8, f[0], name)) {
            const want: usize = if (std.mem.eql(u8, name, "mix") or std.mem.eql(u8, name, "smoothstep") or std.mem.eql(u8, name, "fma")) 3 else 2;
            if (args.len != want) return self.errE(e, "{s}() takes {d} arguments", .{ name, want });
            var n: u8 = 1;
            for (args) |x| {
                if (scalarOf(x.ty) == null) return self.errE(e, "{s}() of {s}", .{ name, try self.mslName(x.ty) });
                n = @max(n, widthOf(x.ty));
            }
            const t = shape(.f32, n);
            var parts: std.ArrayList([]const u8) = .empty;
            for (args, 0..) |x, i| try parts.append(self.a, try self.coerce(x, t, arg_exprs[i]));
            if (std.mem.eql(u8, name, "fmod")) return R.val(t, try self.p("({s} % {s})", .{ parts.items[0], parts.items[1] }), pure, cheap);
            if ((std.mem.eql(u8, name, "pow") or std.mem.eql(u8, name, "powr")) and args[1].lit != null) {
                const l = args[1].lit.?;
                const is_two = switch (l) {
                    .int => |v| v == 2,
                    .float => |ft| (std.fmt.parseFloat(f64, ft) catch 0) == 2.0,
                    else => false,
                };
                if (is_two) {
                    // Metal folds pow(x, 2) into x * x (defined for negative x, unlike WGSL's pow)
                    const tt = try self.tyText(t);
                    const hn = try self.p("m2w_sq_{s}", .{tt});
                    try self.needHelper(hn, try self.p("fn {s}(x: {s}) -> {s} {{ return x * x; }}\n", .{ hn, tt, tt }));
                    return R.val(t, try self.p("{s}({s})", .{ hn, parts.items[0] }), pure, cheap);
                }
            }
            return R.val(t, try self.p("{s}({s})", .{ f[1], try std.mem.join(self.a, ", ", parts.items) }), pure, cheap);
        };
        if (std.mem.eql(u8, name, "select")) {
            if (args.len != 3) return self.errE(e, "select() takes 3 arguments", .{});
            const t = try self.unify(args[0], args[1], e);
            const cs = scalarOf(args[2].ty) orelse return self.errE(e, "select() condition", .{});
            if (cs != .bool) return self.errE(arg_exprs[2], "select() condition must be bool", .{});
            if (args[2].ty == .vec and widthOf(args[2].ty) != widthOf(t)) return self.errE(arg_exprs[2], "select() condition width", .{});
            return R.val(t, try self.p("select({s}, {s}, {s})", .{ try self.coerce(args[0], t, arg_exprs[0]), try self.coerce(args[1], t, arg_exprs[1]), args[2].text }), pure, cheap);
        }
        if (std.mem.eql(u8, name, "length") or std.mem.eql(u8, name, "normalize")) {
            if (args.len != 1) return self.errE(e, "{s}() takes one argument", .{name});
            const t = shape(.f32, widthOf(args[0].ty));
            const rt = if (name[0] == 'l') t_f32 else t;
            return R.val(rt, try self.p("{s}({s})", .{ name, try self.coerce(args[0], t, arg_exprs[0]) }), pure, cheap);
        }
        if (std.mem.eql(u8, name, "distance") or std.mem.eql(u8, name, "dot") or std.mem.eql(u8, name, "cross") or std.mem.eql(u8, name, "reflect")) {
            if (args.len != 2) return self.errE(e, "{s}() takes two arguments", .{name});
            var t = try self.unify(args[0], args[1], e);
            const s = scalarOf(t) orelse return self.errE(e, "{s}() of {s}", .{ name, try self.mslName(t) });
            if (s != .f32 and !std.mem.eql(u8, name, "dot")) t = shape(.f32, widthOf(t));
            const rt: Type = if (std.mem.eql(u8, name, "distance")) t_f32 else if (std.mem.eql(u8, name, "dot")) .{ .scalar = scalarOf(t).? } else t;
            return R.val(rt, try self.p("{s}({s}, {s})", .{ name, try self.coerce(args[0], t, arg_exprs[0]), try self.coerce(args[1], t, arg_exprs[1]) }), pure, cheap);
        }
        if (std.mem.eql(u8, name, "refract")) {
            if (args.len != 3) return self.errE(e, "refract() takes 3 arguments", .{});
            const t = shape(.f32, widthOf(args[0].ty));
            return R.val(t, try self.p("refract({s}, {s}, {s})", .{ try self.coerce(args[0], t, arg_exprs[0]), try self.coerce(args[1], t, arg_exprs[1]), try self.coerce(args[2], t_f32, arg_exprs[2]) }), pure, cheap);
        }
        if (std.mem.eql(u8, name, "faceforward")) {
            if (args.len != 3) return self.errE(e, "faceforward() takes 3 arguments", .{});
            const t = shape(.f32, widthOf(args[0].ty));
            return R.val(t, try self.p("faceForward({s}, {s}, {s})", .{ try self.coerce(args[0], t, arg_exprs[0]), try self.coerce(args[1], t, arg_exprs[1]), try self.coerce(args[2], t, arg_exprs[2]) }), pure, cheap);
        }
        if (std.mem.eql(u8, name, "all") or std.mem.eql(u8, name, "any")) {
            if (args.len != 1 or scalarOf(args[0].ty) != .bool) return self.errE(e, "{s}() needs a bool vector", .{name});
            return R.val(t_bool, try self.p("{s}({s})", .{ name, args[0].text }), pure, cheap);
        }
        if (std.mem.eql(u8, name, "transpose") or std.mem.eql(u8, name, "determinant")) {
            if (args.len != 1 or args[0].ty != .mat) return self.errE(e, "{s}() needs a matrix", .{name});
            const m = args[0].ty.mat;
            const rt: Type = if (name[0] == 'd') t_f32 else .{ .mat = .{ .c = m.r, .r = m.c } };
            return R.val(rt, try self.p("{s}({s})", .{ name, args[0].text }), pure, cheap);
        }
        const bits = [_][2][]const u8{ .{ "popcount", "countOneBits" }, .{ "clz", "countLeadingZeros" }, .{ "ctz", "countTrailingZeros" }, .{ "reverse_bits", "reverseBits" } };
        for (bits) |bf| if (std.mem.eql(u8, bf[0], name)) {
            if (args.len != 1) return self.errE(e, "{s}() takes one argument", .{name});
            const s = scalarOf(args[0].ty) orelse return self.errE(e, "{s}() of {s}", .{ name, try self.mslName(args[0].ty) });
            if (s != .i32 and s != .u32) return self.errE(e, "{s}() of {s}", .{ name, try self.mslName(args[0].ty) });
            return R.val(args[0].ty, try self.p("{s}({s})", .{ bf[1], args[0].text }), pure, cheap);
        };
        if (std.mem.eql(u8, name, "isnan") or std.mem.eql(u8, name, "isinf") or std.mem.eql(u8, name, "isfinite")) {
            // WGSL has none: test the bits (exact, whatever the backend's float optimisations)
            if (args.len != 1 or scalarOf(args[0].ty) == null) return self.errE(e, "{s}() takes one float", .{name});
            const n = widthOf(args[0].ty);
            const t = shape(.f32, n);
            const tt = try self.tyText(t);
            const ut = try self.tyText(shape(.u32, n));
            const bt = try self.tyText(shape(.bool, n));
            const hn = try self.p("m2w_{s}_{s}", .{ name, tt });
            const body: []const u8 = if (std.mem.eql(u8, name, "isfinite"))
                try self.p("(bitcast<{s}>(x) & {s}(0x7f800000u)) != {s}(0x7f800000u)", .{ ut, ut, ut })
            else if (std.mem.eql(u8, name, "isnan"))
                try self.p("(bitcast<{s}>(x) & {s}(0x7fffffffu)) > {s}(0x7f800000u)", .{ ut, ut, ut })
            else
                try self.p("(bitcast<{s}>(x) & {s}(0x7fffffffu)) == {s}(0x7f800000u)", .{ ut, ut, ut });
            try self.needHelper(hn, try self.p("// Metal's {s}(), by the IEEE-754 bits (WGSL has no such builtin).\nfn {s}(x: {s}) -> {s} {{ return {s}; }}\n", .{ name, hn, tt, bt, body }));
            return R.val(shape(.bool, n), try self.p("{s}({s})", .{ hn, try self.coerce(args[0], t, arg_exprs[0]) }), pure, cheap);
        }
        return self.errE(e, "unknown function '{s}'", .{name});
    }

    fn callAtomic(self: *Lowerer, name: []const u8, arg_exprs: []const *P.Expr, e: *P.Expr) Error!Val {
        const ops = [_][2][]const u8{
            .{ "atomic_store_explicit", "atomicStore" },   .{ "atomic_load_explicit", "atomicLoad" },
            .{ "atomic_fetch_add_explicit", "atomicAdd" }, .{ "atomic_fetch_sub_explicit", "atomicSub" },
            .{ "atomic_fetch_max_explicit", "atomicMax" }, .{ "atomic_fetch_min_explicit", "atomicMin" },
            .{ "atomic_fetch_and_explicit", "atomicAnd" }, .{ "atomic_fetch_or_explicit", "atomicOr" },
            .{ "atomic_fetch_xor_explicit", "atomicXor" }, .{ "atomic_exchange_explicit", "atomicExchange" },
        };
        for (ops) |o| {
            if (!std.mem.eql(u8, o[0], name)) continue;
            const is_load = std.mem.eql(u8, o[1], "atomicLoad");
            const want: usize = if (is_load) 2 else 3;
            if (arg_exprs.len != want) return self.errE(e, "{s} takes {d} arguments", .{ name, want });
            const pv = try self.lowerExpr(arg_exprs[0]);
            if (pv.ty != .ptr or pv.ty.ptr.* != .atomic) return self.errE(arg_exprs[0], "{s} needs &atomic", .{name});
            const s = pv.ty.ptr.*.atomic;
            if (self.ctx.inst) |i| i.impure = true;
            if (is_load) return .{ .ty = .{ .scalar = s }, .text = try self.p("atomicLoad({s})", .{pv.text}), .pure = false };
            const v = try self.lowerExpr(arg_exprs[1]);
            const vt = try self.coerce(v, .{ .scalar = s }, arg_exprs[1]);
            const rt: Type = if (std.mem.eql(u8, o[1], "atomicStore")) .void else .{ .scalar = s };
            return .{ .ty = rt, .text = try self.p("{s}({s}, {s})", .{ o[1], pv.text, vt }), .pure = false };
        }
        return self.errE(e, "{s} is not supported", .{name});
    }

    // ---- user functions
    const Match = struct { cost: u32, binds: []Bind, tbinds: []TBind };

    fn tparamOf(f: *P.Func, name: []const u8) bool {
        for (f.tparams) |t| if (std.mem.eql(u8, t, name)) return true;
        return false;
    }

    fn matchFunc(self: *Lowerer, f: *P.Func, args: []const Val) Error!?Match {
        if (args.len > f.params.len) return null;
        for (f.params[args.len..]) |prm| if (prm.default == null) return null;
        var binds: std.ArrayList(Bind) = .empty;
        var tb: std.ArrayList(TBind) = .empty;
        var cost: u32 = 0;
        const saved_tb = self.ctx.tbinds;
        defer self.ctx.tbinds = saved_tb;
        for (f.params, 0..) |prm, i| {
            self.ctx.tbinds = tb.items;
            if (i >= args.len) {
                // default argument: a value of the declared type
                const t = try self.resolveType(prm.ty);
                try binds.append(self.a, .{ .value = t });
                continue;
            }
            const a = args[i];
            const pt = prm.ty;
            const is_t = tparamOf(f, pt.name) and pt.ptr == 0 and prm.dims.len == 0;
            if (is_t) {
                var known: ?Type = null;
                for (tb.items) |b| if (std.mem.eql(u8, b.name, pt.name)) {
                    known = b.ty;
                };
                switch (a.special) {
                    .lambda => |lv| {
                        try tb.append(self.a, .{ .name = pt.name, .ty = .lambda });
                        try binds.append(self.a, .{ .lambda = lv });
                        continue;
                    },
                    .texture => |g| {
                        try tb.append(self.a, .{ .name = pt.name, .ty = .{ .texture = .read } });
                        try binds.append(self.a, .{ .erased = .{ .texture = g } });
                        continue;
                    },
                    .sampler => |sv| {
                        try tb.append(self.a, .{ .name = pt.name, .ty = .sampler });
                        try binds.append(self.a, .{ .erased = .{ .sampler = sv } });
                        continue;
                    },
                    .ptr => |pv| {
                        try tb.append(self.a, .{ .name = pt.name, .ty = a.ty });
                        try binds.append(self.a, .{ .ptr = .{ .kind = pv.kind, .elem = pv.elem, .n = pv.n, .writable = pv.writable } });
                        continue;
                    },
                    .frame, .stats => {
                        try tb.append(self.a, .{ .name = pt.name, .ty = a.ty });
                        try binds.append(self.a, .{ .erased = a.special });
                        continue;
                    },
                    .none => {},
                    else => return null,
                }
                if (a.ty == .array and !pt.ref) {
                    // an array argument decays to a pointer
                    const ap = (try self.arrayPtr(a)) orelse return null;
                    try tb.append(self.a, .{ .name = pt.name, .ty = .{ .ptr = a.ty.array.elem } });
                    try binds.append(self.a, ap.bind);
                    continue;
                }
                if (known) |k| {
                    if (!eql(k, a.ty)) return null;
                } else try tb.append(self.a, .{ .name = pt.name, .ty = a.ty });
                if (pt.ref and !pt.is_const and pt.space != .constant) {
                    if (a.lv != .ref and a.psym == null) return null;
                    try binds.append(self.a, .{ .ref = a.ty });
                } else try binds.append(self.a, .{ .value = a.ty });
                continue;
            }
            const t0 = try self.resolveType(pt);
            if (t0 == .texture) {
                if (a.special != .texture) return null;
                const g = a.special.texture;
                if ((t0.texture == .write) != std.mem.endsWith(u8, g, "out")) return null;
                try binds.append(self.a, .{ .erased = a.special });
                continue;
            }
            if (t0 == .sampler) {
                if (a.special != .sampler) return null;
                try binds.append(self.a, .{ .erased = a.special });
                continue;
            }
            if (eql(t0, t_frame) and (pt.ref or pt.space == .constant)) {
                if (a.special != .frame) return null;
                try binds.append(self.a, .{ .erased = .frame });
                continue;
            }
            if (eql(t0, .{ .strct = 2 })) {
                if (a.special != .stats) return null;
                try binds.append(self.a, .{ .erased = .stats });
                continue;
            }
            if (t0 == .ptr or (prm.dims.len > 0 and !pt.is_const)) {
                // T* (or a non-const T x[N]): a pointer into an array
                const elem = if (t0 == .ptr) t0.ptr.* else t0;
                if (a.special == .ptr) {
                    const pv = a.special.ptr;
                    if (!eql(pv.elem, elem)) return null;
                    try binds.append(self.a, .{ .ptr = .{ .kind = pv.kind, .elem = pv.elem, .n = pv.n, .writable = pv.writable } });
                    continue;
                }
                if (a.ty == .array and eql(a.ty.array.elem.*, elem)) {
                    const ap = (try self.arrayPtr(a)) orelse return null;
                    try binds.append(self.a, ap.bind);
                    continue;
                }
                return null;
            }
            const t = try self.withDims(t0, prm.dims, null, prm.line, prm.col);
            if (a.special != .none) {
                if (a.special == .frame and eql(t, t_frame)) {
                    try binds.append(self.a, .{ .value = t });
                    continue;
                }
                return null;
            }
            if (pt.ref and !pt.is_const and pt.space != .constant) {
                if (!eql(a.ty, t)) return null;
                if (a.lv != .ref and a.psym == null) return null;
                try binds.append(self.a, .{ .ref = t });
                continue;
            }
            if (eql(a.ty, t)) {
                try binds.append(self.a, .{ .value = t });
                continue;
            }
            const c = self.convCost(a, t) orelse return null;
            cost += c;
            try binds.append(self.a, .{ .value = t });
        }
        return .{ .cost = cost, .binds = binds.items, .tbinds = tb.items };
    }

    const ArrPtr = struct { bind: Bind, ptr: PtrVal };

    fn arrayPtr(self: *Lowerer, a: Val) Error!?ArrPtr {
        if (a.ty != .array) return null;
        const elem = a.ty.array.elem.*;
        if (a.lv == .ref) {
            const addr = (try self.addrOf(a)) orelse return null;
            const pv: PtrVal = .{ .kind = .local, .ref = a.text, .ptr = addr, .elem = elem, .n = a.ty.array.len, .writable = true };
            return .{ .bind = .{ .ptr = .{ .kind = .local, .elem = elem, .n = a.ty.array.len, .writable = true } }, .ptr = pv };
        }
        if (a.lv == .let_) {
            // a constant array: pass it by name (the parameter disappears)
            if (self.globals.get(a.text)) |gs| {
                if (gs.kind == .gconst) return .{ .bind = .{ .garray = gs }, .ptr = undefined };
            }
            var it = self.globals.valueIterator();
            while (it.next()) |gs| if (gs.*.kind == .gconst and std.mem.eql(u8, gs.*.wname, a.text)) return .{ .bind = .{ .garray = gs.* }, .ptr = undefined };
        }
        return null;
    }

    fn convCost(self: *Lowerer, a: Val, t: Type) ?u32 {
        _ = self;
        const sa = scalarOf(a.ty) orelse return null;
        const st = scalarOf(t) orelse return null;
        const na = widthOf(a.ty);
        const nt = widthOf(t);
        if (a.ty == .scalar and t == .vec) return 4;
        if (na != nt) return null;
        if (a.lit != null) return 1;
        if (sa == st) return 0;
        if (rank(st) > rank(sa)) return 2;
        return 3;
    }

    fn bindKey(self: *Lowerer, b: Bind) Error![]const u8 {
        return switch (b) {
            .value => |t| self.p("v:{s}", .{try self.tyText(t)}),
            .ref => |t| self.p("r:{s}", .{try self.tyText(t)}),
            .erased => |s| switch (s) {
                .texture => |g| self.p("t:{s}", .{g}),
                .sampler => |sv| self.p("s:{s}:{}", .{ sv.g, sv.pixel }),
                .frame => "frame",
                .stats => "stats",
                else => "?",
            },
            .garray => |gs| self.p("g:{s}", .{gs.wname}),
            .lambda => |lv| blk: {
                var k: std.ArrayList(u8) = .empty;
                try k.print(self.a, "l:{d}", .{lv.def.id});
                for (lv.def.caps) |cp| try k.print(self.a, ":{s}={s}/{s}", .{ cp.name, @tagName(cp.mode), try self.tyText(cp.sym.ty) });
                break :blk k.items;
            },
            .ptr => |pb| self.p("p:{s}:{s}:{d}:{}", .{ @tagName(pb.kind), try self.tyText(pb.elem), if (pb.kind == .local) pb.n else 0, pb.writable }),
        };
    }

    fn callUser(self: *Lowerer, name: []const u8, cands: []const *P.Func, arg_exprs: []const *P.Expr, e: *P.Expr) Error!Val {
        if (self.ctx.global) return self.errE(e, "calling {s}() in a constant initialiser: not a constant expression in WGSL", .{name});
        const args = try self.lowerArgs(arg_exprs);
        var best: ?Match = null;
        var best_f: *P.Func = undefined;
        for (cands) |f| {
            if (f.is_kernel) continue;
            const m = (try self.matchFunc(f, args)) orelse continue;
            if (best == null or m.cost < best.?.cost) {
                best = m;
                best_f = f;
            }
        }
        const m = best orelse {
            var tys: std.ArrayList([]const u8) = .empty;
            for (args) |x| try tys.append(self.a, try self.describe(x));
            return self.errE(e, "no {s}() takes ({s})", .{ name, try std.mem.join(self.a, ", ", tys.items) });
        };
        const f = best_f;
        if (f.body == null) return self.errE(e, "{s}() is declared but never defined", .{name});
        var key: std.ArrayList(u8) = .empty;
        try key.print(self.a, "f{d}", .{f.index});
        for (m.binds) |b| try key.print(self.a, "|{s}", .{try self.bindKey(b)});
        const inst = blk: {
            if (self.inst_idx.get(key.items)) |i| break :blk i;
            const saved_tb = self.ctx.tbinds;
            self.ctx.tbinds = m.tbinds;
            const ret = try self.resolveType(f.ret);
            self.ctx.tbinds = saved_tb;
            const i = try self.a.create(Instance);
            i.* = .{ .key = key.items, .name = try self.uniqueName(f.name), .func = f, .binds = m.binds, .tbinds = m.tbinds, .ret = ret };
            try self.inst_idx.put(self.a, key.items, i);
            try self.inst_log.append(self.a, i);
            try self.lowerInstance(i);
            break :blk i;
        };
        if (inst.state == .busy) return self.errE(e, "{s}() calls itself: recursion is not supported in WGSL", .{name});
        // arguments
        var parts: std.ArrayList([]const u8) = .empty;
        var pure = !inst.impure;
        for (f.params, 0..) |prm, i| {
            const b = m.binds[i];
            const ae: *const P.Expr = if (i < arg_exprs.len) arg_exprs[i] else prm.default.?;
            const a = if (i < args.len) args[i] else try self.lowerExpr(prm.default.?);
            pure = pure and a.pure;
            switch (b) {
                .value => |t| {
                    if (a.special == .frame) {
                        try parts.append(self.a, "f");
                        continue;
                    }
                    try parts.append(self.a, try self.coerce(a, t, ae));
                },
                .ref => |t| {
                    pure = false;
                    if (try self.addrOf(a)) |addr| {
                        try parts.append(self.a, addr);
                    } else {
                        // copy in, pass the copy, copy back
                        if (!a.pure) return self.errE(ae, "a reference argument with side effects", .{});
                        const tmp = try self.newTmp();
                        try self.line("var {s}: {s} = {s};", .{ tmp, try self.tyText(t), a.text });
                        try parts.append(self.a, try self.p("&{s}", .{tmp}));
                        try self.copyBack(a, tmp);
                    }
                },
                .erased, .garray => {},
                .lambda => |lv| {
                    for (lv.env) |env| try parts.append(self.a, env);
                    pure = false;
                },
                .ptr => |pb| {
                    const pv = if (a.special == .ptr) a.special.ptr else try self.arrayPtrVal(a);
                    switch (pb.kind) {
                        .local => {
                            try parts.append(self.a, pv.ptr);
                            try parts.append(self.a, pv.off);
                            pure = false;
                        },
                        .pool => try parts.append(self.a, pv.off),
                        .proc => {
                            try parts.append(self.a, try self.p("u32({s})", .{pv.ref}));
                            try parts.append(self.a, pv.off);
                        },
                    }
                },
            }
        }
        const call = try self.p("{s}({s})", .{ inst.name, try std.mem.join(self.a, ", ", parts.items) });
        if (inst.ret == .ptr) {
            if (inst.ret.ptr.* != .scalar or inst.ret.ptr.*.scalar != .i32 or self.pending_copyback.items.len > 0) return self.errE(e, "{s}() returns a pointer: only constant char* (strings) are supported", .{name});
            return .{ .ty = inst.ret, .text = "", .special = .{ .ptr = .{ .kind = .pool, .off = call, .elem = t_i32 } }, .pure = pure, .cheap = false };
        }
        if (self.pending_copyback.items.len > 0) {
            // the call writes through copies: run it now, then copy back
            const backs = try self.a.dupe([]const u8, self.pending_copyback.items);
            self.pending_copyback.items.len = 0;
            if (inst.ret == .void) {
                try self.line("{s};", .{call});
                for (backs) |bk| try self.line("{s}", .{bk});
                return .{ .ty = .void, .text = "", .pure = false, .cheap = false, .special = .none };
            }
            const r = try self.newTmp();
            try self.line("let {s}: {s} = {s};", .{ r, try self.tyText(inst.ret), call });
            for (backs) |bk| try self.line("{s}", .{bk});
            return .{ .ty = inst.ret, .text = r, .pure = false, .cheap = true };
        }
        return .{ .ty = inst.ret, .text = call, .pure = pure, .cheap = false };
    }

    fn arrayPtrVal(self: *Lowerer, a: Val) Error!PtrVal {
        const ap = (try self.arrayPtr(a)) orelse return error.Unsupported;
        return ap.ptr;
    }

    fn copyBack(self: *Lowerer, target: Val, tmp: []const u8) Error!void {
        if (target.swz) |sw| {
            var s: std.ArrayList(u8) = .empty;
            for (sw.comps, 0..) |c, i| try s.print(self.a, "{s}.{c} = {s}.{c}; ", .{ sw.base, c, tmp, "xyzw"[i] });
            try self.pending_copyback.append(self.a, s.items);
            return;
        }
        if (target.lv != .ref) {
            if (target.psym) |ps| {
                if (!ps.needs_var) {
                    ps.needs_var = true;
                    self.ctx.retry = true;
                }
            } else return error.Unsupported;
        }
        try self.pending_copyback.append(self.a, try self.p("{s} = {s};", .{ target.text, tmp }));
    }

    /// Lowers a function instance's body; re-lowers once if a by-value parameter turned out to
    /// be assigned (WGSL parameters are immutable: those get a `var` copy).
    fn lowerInstance(self: *Lowerer, inst: *Instance) Error!void {
        const f = inst.func.?;
        inst.state = .busy;
        var marks: std.ArrayList(bool) = .empty;
        for (f.params) |_| try marks.append(self.a, false);
        var attempt: u32 = 0;
        while (true) : (attempt += 1) {
            const mark_insts = self.insts.items.len;
            const mark_log = self.inst_log.items.len;
            var body: std.ArrayList(u8) = .empty;
            var ctx: Ctx = .{ .out = &body, .ret = inst.ret, .inst = inst, .tbinds = inst.tbinds, .owner = inst.name };
            const saved = self.ctx;
            self.ctx = &ctx;
            defer self.ctx = saved;
            var sig: std.ArrayList([]const u8) = .empty;
            var prologue: std.ArrayList(u8) = .empty;
            var psyms: std.ArrayList(?*Sym) = .empty;
            for (f.params, 0..) |prm, i| {
                const pn = if (prm.name.len == 0) try self.p("m2w_unused{d}", .{i}) else prm.name;
                const wn = try self.wname(pn);
                var ps: ?*Sym = null;
                switch (inst.binds[i]) {
                    .value => |t| {
                        if (marks.items[i]) {
                            try sig.append(self.a, try self.p("{s}_in: {s}", .{ wn, try self.tyText(t) }));
                            try prologue.print(self.a, "    var {s}: {s} = {s}_in;\n", .{ wn, try self.tyText(t), wn });
                            ps = try self.newSym(.{ .name = pn, .wname = wn, .kind = .var_, .ty = t });
                        } else {
                            try sig.append(self.a, try self.p("{s}: {s}", .{ wn, try self.tyText(t) }));
                            ps = try self.newSym(.{ .name = pn, .wname = wn, .kind = .let_, .ty = t, .param = true });
                        }
                    },
                    .ref => |t| {
                        try sig.append(self.a, try self.p("{s}: ptr<function, {s}>", .{ wn, try self.tyText(t) }));
                        ps = try self.newSym(.{ .name = pn, .wname = wn, .kind = .ptr, .ty = t });
                    },
                    .erased => |sp| {
                        const t: Type = switch (sp) {
                            .texture => .{ .texture = .read },
                            .sampler => .sampler,
                            .frame => t_frame,
                            .stats => .{ .strct = 2 },
                            else => .void,
                        };
                        ps = try self.newSym(.{ .name = pn, .wname = switch (sp) {
                            .frame => "f",
                            .stats => "s",
                            else => wn,
                        }, .kind = .static_, .ty = t, .special = sp });
                    },
                    .garray => |gs| {
                        var alias = gs.*;
                        alias.name = pn;
                        ps = try self.newSym(alias);
                    },
                    .lambda => |lv| {
                        var env: std.ArrayList([]const u8) = .empty;
                        for (lv.def.caps) |cp| {
                            if (cp.mode == .static_) continue;
                            const en = try self.p("{s}_{s}", .{ wn, try self.wname(cp.name) });
                            const tt = try self.tyText(cp.sym.ty);
                            if (cp.mode == .ref) try sig.append(self.a, try self.p("{s}: ptr<function, {s}>", .{ en, tt })) else try sig.append(self.a, try self.p("{s}: {s}", .{ en, tt }));
                            try env.append(self.a, en);
                        }
                        const nlv = try self.a.create(LambdaVal);
                        nlv.* = .{ .def = lv.def, .env = env.items };
                        ps = try self.newSym(.{ .name = pn, .wname = wn, .kind = .static_, .ty = .lambda, .special = .{ .lambda = nlv } });
                    },
                    .ptr => |pb| {
                        var pv: PtrVal = .{ .kind = pb.kind, .elem = pb.elem, .n = pb.n, .writable = pb.writable, .off = try self.p("{s}_off", .{wn}) };
                        switch (pb.kind) {
                            .local => {
                                try sig.append(self.a, try self.p("{s}: ptr<function, array<{s}, {d}>>", .{ wn, try self.tyText(pb.elem), pb.n }));
                                pv.ref = try self.p("(*{s})", .{wn});
                                pv.ptr = wn;
                            },
                            .pool => {},
                            .proc => {
                                try sig.append(self.a, try self.p("{s}_idx: u32", .{wn}));
                                pv.ref = try self.p("{s}_idx", .{wn});
                            },
                        }
                        try sig.append(self.a, try self.p("{s}_off: i32", .{wn}));
                        ps = try self.newSym(.{ .name = pn, .wname = wn, .kind = .static_, .ty = .{ .ptr = try self.newType(pb.elem) }, .special = .{ .ptr = pv } });
                    },
                }
                try psyms.append(self.a, ps);
                if (ps) |s| try self.push(s);
            }
            try self.lowerStmtList(f.body.?.kind.block);
            if (ctx.retry and attempt < 3) {
                var changed = false;
                for (psyms.items, 0..) |ps, i| if (ps) |s| if (s.needs_var and !marks.items[i]) {
                    marks.items[i] = true;
                    changed = true;
                };
                if (changed) {
                    // drop what this pass instantiated: the next pass makes what it needs
                    for (self.inst_log.items[mark_log..]) |d| {
                        _ = self.inst_idx.remove(d.key);
                        _ = self.used.remove(d.name);
                    }
                    self.inst_log.items.len = mark_log;
                    self.insts.items.len = mark_insts;
                    continue;
                }
            }
            const ret_txt = if (inst.ret == .void) "" else if (inst.ret == .ptr) " -> i32" else try self.p(" -> {s}", .{try self.tyText(inst.ret)});
            inst.text = try self.p("// {s} (Metal line {d})\nfn {s}({s}){s} {{\n{s}{s}}}\n\n", .{ f.name, f.line, inst.name, try std.mem.join(self.a, ", ", sig.items), ret_txt, prologue.items, body.items });
            break;
        }
        inst.state = .done;
        try self.insts.append(self.a, inst);
    }

    // ---- lambdas
    fn collectIdents(self: *Lowerer, e: *const P.Expr, out: *std.StringHashMapUnmanaged(bool), lvalue: bool) Error!void {
        switch (e.kind) {
            .ident => |n| {
                const gop = try out.getOrPut(self.a, n);
                if (!gop.found_existing) gop.value_ptr.* = false;
                if (lvalue) gop.value_ptr.* = true;
            },
            .unary => |u| try self.collectIdents(u.e, out, lvalue or std.mem.eql(u8, u.op, "++") or std.mem.eql(u8, u.op, "--") or std.mem.eql(u8, u.op, "&")),
            .postfix => |u| try self.collectIdents(u.e, out, true),
            .binary => |b| {
                try self.collectIdents(b.a, out, false);
                try self.collectIdents(b.b, out, false);
            },
            .assign => |a| {
                try self.collectIdents(a.lhs, out, true);
                try self.collectIdents(a.rhs, out, false);
            },
            .ternary => |t| {
                try self.collectIdents(t.c, out, false);
                try self.collectIdents(t.a, out, lvalue);
                try self.collectIdents(t.b, out, lvalue);
            },
            .call => |c| {
                try self.collectIdents(c.callee, out, false);
                // an argument is written when it may bind to a reference (or pointer) parameter
                for (c.args, 0..) |x, i| try self.collectIdents(x, out, self.argMayBeWritten(c.callee, i, c.args.len));
            },
            .member => |m| try self.collectIdents(m.e, out, lvalue),
            .index => |x| {
                try self.collectIdents(x.e, out, lvalue);
                try self.collectIdents(x.i, out, false);
            },
            .cast => |c| try self.collectIdents(c.e, out, false),
            .construct => |c| for (c.args) |x| try self.collectIdents(x, out, false),
            .init_list => |l| for (l) |x| try self.collectIdents(x, out, false),
            .lambda => |l| try self.collectStmtIdents(l.body, out),
            .comma => |c| {
                try self.collectIdents(c.a, out, false);
                try self.collectIdents(c.b, out, false);
            },
            else => {},
        }
    }

    fn paramWrites(prm: P.Param) bool {
        const t = prm.ty;
        if (t.ptr > 0 and !t.is_const and t.space != .constant) return true;
        if (prm.dims.len > 0 and !t.is_const) return true;
        return t.ref and !t.is_const and t.space != .constant;
    }

    /// Whether argument i of a call may be written by the callee (a reference or pointer
    /// parameter, sincos's cosine, an atomic): what a lambda must capture by pointer.
    fn argMayBeWritten(self: *Lowerer, callee: *const P.Expr, i: usize, nargs: usize) bool {
        const n = switch (callee.kind) {
            .ident => |x| stripNs(x),
            else => return false, // texture methods write nothing they are given
        };
        if (self.lookup(n)) |s| {
            if (s.special == .lambda) {
                const ps = s.special.lambda.def.ast.params;
                return i < ps.len and paramWrites(ps[i]);
            }
        }
        if (self.funcs.get(n)) |list| {
            for (list.items) |f| {
                if (f.params.len < nargs or i >= f.params.len) continue;
                if (paramWrites(f.params[i])) return true;
            }
            return false;
        }
        if (std.mem.eql(u8, n, "sincos")) return i == 1;
        if (std.mem.startsWith(u8, n, "atomic_")) return i == 0;
        return false;
    }

    fn collectStmtIdents(self: *Lowerer, s: *const P.Stmt, out: *std.StringHashMapUnmanaged(bool)) Error!void {
        switch (s.kind) {
            .block => |l| for (l) |x| try self.collectStmtIdents(x, out),
            .decl => |d| for (d.decls) |dd| {
                if (dd.init) |i| try self.collectIdents(i, out, false);
                if (dd.ctor) |c| for (c) |x| try self.collectIdents(x, out, false);
                for (dd.dims) |dm| if (dm) |x| try self.collectIdents(x, out, false);
            },
            .expr => |e| try self.collectIdents(e, out, false),
            .if_ => |i| {
                try self.collectIdents(i.c, out, false);
                try self.collectStmtIdents(i.then, out);
                if (i.els) |e| try self.collectStmtIdents(e, out);
            },
            .for_ => |f| {
                if (f.init) |i| try self.collectStmtIdents(i, out);
                if (f.cond) |c| try self.collectIdents(c, out, false);
                if (f.incr) |c| try self.collectIdents(c, out, false);
                try self.collectStmtIdents(f.body, out);
            },
            .while_ => |w| {
                try self.collectIdents(w.c, out, false);
                try self.collectStmtIdents(w.body, out);
            },
            .do_while => |w| {
                try self.collectIdents(w.c, out, false);
                try self.collectStmtIdents(w.body, out);
            },
            .ret => |r| if (r) |e| try self.collectIdents(e, out, false),
            .switch_ => |sw| {
                try self.collectIdents(sw.e, out, false);
                for (sw.cases) |c| for (c.body) |x| try self.collectStmtIdents(x, out);
            },
            else => {},
        }
    }

    fn defineLambda(self: *Lowerer, name: []const u8, l: *P.Lambda) Error!void {
        var ids: std.StringHashMapUnmanaged(bool) = .empty;
        try self.collectStmtIdents(l.body, &ids);
        var caps: std.ArrayList(Capture) = .empty;
        var env: std.ArrayList([]const u8) = .empty;
        // capture in a fixed order: the order of the enclosing scope
        for (self.ctx.scope.items) |s| {
            const written = ids.get(s.name) orelse continue;
            // the innermost symbol of this name only
            if (self.lookup(s.name) != s) continue;
            var shadowed_by_param = false;
            for (l.params) |prm| if (std.mem.eql(u8, prm.name, s.name)) {
                shadowed_by_param = true;
            };
            if (shadowed_by_param) continue;
            switch (s.kind) {
                .static_, .gconst => {
                    try caps.append(self.a, .{ .name = s.name, .sym = s, .mode = .static_ });
                    if (s.special == .lambda) {
                        // a lambda calling another lambda: carry its environment too
                        for (s.special.lambda.def.caps, 0..) |cp, k| {
                            _ = k;
                            if (cp.mode == .static_) continue;
                            return self.err(l.line, l.col, "a lambda that calls another capturing lambda is not supported", .{});
                        }
                    }
                    if (s.special == .ptr) return self.err(l.line, l.col, "a lambda capturing the pointer {s} is not supported", .{s.name});
                },
                .let_ => {
                    if (!l.by_ref and written) return self.err(l.line, l.col, "lambda writes its by-value capture {s}", .{s.name});
                    if (written and s.param) {
                        // a by-value parameter the lambda writes: it must be a var first
                        if (!s.needs_var) {
                            s.needs_var = true;
                            self.ctx.retry = true;
                        }
                    }
                    try caps.append(self.a, .{ .name = s.name, .sym = s, .mode = .value });
                    try env.append(self.a, s.wname);
                },
                .var_ => {
                    if (s.workgroup) {
                        try caps.append(self.a, .{ .name = s.name, .sym = s, .mode = .static_ });
                        continue;
                    }
                    if (written and l.by_ref) {
                        try caps.append(self.a, .{ .name = s.name, .sym = s, .mode = .ref });
                        try env.append(self.a, try self.p("&{s}", .{s.wname}));
                    } else if (l.by_ref) {
                        try caps.append(self.a, .{ .name = s.name, .sym = s, .mode = .value });
                        try env.append(self.a, s.wname);
                    } else {
                        // [=]: a copy taken now
                        const t = try self.newTmp();
                        try self.line("let {s}: {s} = {s};", .{ t, try self.tyText(s.ty), s.wname });
                        try caps.append(self.a, .{ .name = s.name, .sym = s, .mode = .value });
                        try env.append(self.a, t);
                    }
                },
                .ptr => {
                    if (written) {
                        try caps.append(self.a, .{ .name = s.name, .sym = s, .mode = .ref });
                        try env.append(self.a, s.wname);
                    } else {
                        try caps.append(self.a, .{ .name = s.name, .sym = s, .mode = .value });
                        try env.append(self.a, try self.p("(*{s})", .{s.wname}));
                    }
                },
            }
        }
        const key = try self.p("{x}|{s}", .{ @intFromPtr(l), self.ctx.owner });
        const def = blk: {
            if (self.ldefs.get(key)) |d| break :blk d;
            const d = try self.a.create(LambdaDef);
            self.lambda_count += 1;
            d.* = .{ .ast = l, .caps = caps.items, .id = self.lambda_count, .name = try self.p("{s}_{s}", .{ self.ctx.owner, name }) };
            try self.ldefs.put(self.a, key, d);
            break :blk d;
        };
        def.caps = caps.items;
        const lv = try self.a.create(LambdaVal);
        lv.* = .{ .def = def, .env = env.items };
        try self.push(try self.newSym(.{ .name = name, .wname = name, .kind = .static_, .ty = .lambda, .special = .{ .lambda = lv } }));
    }

    fn callLambda(self: *Lowerer, lv: *LambdaVal, arg_exprs: []const *P.Expr, e: *P.Expr) Error!Val {
        const def = lv.def;
        const l = def.ast;
        if (arg_exprs.len != l.params.len) return self.errE(e, "lambda {s} takes {d} arguments", .{ def.name, l.params.len });
        const args = try self.lowerArgs(arg_exprs);
        var binds: std.ArrayList(Bind) = .empty;
        var key: std.ArrayList(u8) = .empty;
        try key.print(self.a, "L{d}", .{def.id});
        for (l.params, 0..) |prm, i| {
            var t = try self.resolveType(prm.ty);
            if (t == .auto) t = args[i].ty;
            t = try self.withDims(t, prm.dims, null, prm.line, prm.col);
            if (args[i].special != .none) return self.errE(arg_exprs[i], "passing {s} to a lambda is not supported", .{try self.describe(args[i])});
            const b: Bind = if (prm.ty.ref and !prm.ty.is_const) .{ .ref = t } else .{ .value = t };
            try binds.append(self.a, b);
            try key.print(self.a, "|{s}", .{try self.bindKey(b)});
        }
        for (def.caps) |cp| try key.print(self.a, "|{s}:{s}", .{ cp.name, @tagName(cp.mode) });
        const inst = blk: {
            if (self.inst_idx.get(key.items)) |i| break :blk i;
            const i = try self.a.create(Instance);
            i.* = .{ .key = key.items, .name = try self.uniqueName(def.name), .func = null, .ldef = def, .binds = binds.items, .tbinds = &.{}, .ret = .void };
            try self.inst_idx.put(self.a, key.items, i);
            try self.inst_log.append(self.a, i);
            try self.lowerLambdaInstance(i);
            break :blk i;
        };
        if (inst.state == .busy) return self.errE(e, "lambda {s} calls itself", .{def.name});
        var parts: std.ArrayList([]const u8) = .empty;
        var pure = !inst.impure;
        for (binds.items, 0..) |b, i| switch (b) {
            .value => |t| try parts.append(self.a, try self.coerce(args[i], t, arg_exprs[i])),
            .ref => {
                pure = false;
                const addr = (try self.addrOf(args[i])) orelse return self.errE(arg_exprs[i], "a reference argument that is not a whole variable", .{});
                try parts.append(self.a, addr);
            },
            else => unreachable,
        };
        var k: usize = 0;
        for (def.caps) |cp| {
            if (cp.mode == .static_) continue;
            if (cp.mode == .ref) pure = false;
            try parts.append(self.a, lv.env[k]);
            k += 1;
        }
        return .{ .ty = inst.ret, .text = try self.p("{s}({s})", .{ inst.name, try std.mem.join(self.a, ", ", parts.items) }), .pure = pure, .cheap = false };
    }

    fn lowerLambdaInstance(self: *Lowerer, inst: *Instance) Error!void {
        const def = inst.ldef.?;
        const l = def.ast;
        inst.state = .busy;
        var body: std.ArrayList(u8) = .empty;
        var ctx: Ctx = .{ .out = &body, .inst = inst, .owner = inst.name };
        if (l.ret) |rt| {
            ctx.ret = try self.resolveType(rt);
        } else {
            ctx.ret = null;
            ctx.infer_ret = true;
        }
        const saved = self.ctx;
        ctx.tbinds = saved.tbinds;
        self.ctx = &ctx;
        defer self.ctx = saved;
        var sig: std.ArrayList([]const u8) = .empty;
        var prologue: std.ArrayList(u8) = .empty;
        for (def.caps) |cp| {
            switch (cp.mode) {
                .static_ => try self.push(cp.sym),
                .value => {
                    const wn = try self.wname(cp.name);
                    try sig.append(self.a, try self.p("{s}: {s}", .{ wn, try self.tyText(cp.sym.ty) }));
                    try self.push(try self.newSym(.{ .name = cp.name, .wname = wn, .kind = .let_, .ty = cp.sym.ty }));
                },
                .ref => {
                    const wn = try self.wname(cp.name);
                    try sig.append(self.a, try self.p("{s}: ptr<function, {s}>", .{ wn, try self.tyText(cp.sym.ty) }));
                    try self.push(try self.newSym(.{ .name = cp.name, .wname = wn, .kind = .ptr, .ty = cp.sym.ty }));
                },
            }
        }
        var lam_params: std.ArrayList([]const u8) = .empty;
        for (l.params, 0..) |prm, i| {
            const wn = try self.wname(prm.name);
            switch (inst.binds[i]) {
                .value => |t| {
                    // lambda parameters may be assigned: always give them a var copy
                    try lam_params.append(self.a, try self.p("{s}_in: {s}", .{ wn, try self.tyText(t) }));
                    try prologue.print(self.a, "    var {s}: {s} = {s}_in;\n", .{ wn, try self.tyText(t), wn });
                    try self.push(try self.newSym(.{ .name = prm.name, .wname = wn, .kind = .var_, .ty = t }));
                },
                .ref => |t| {
                    try lam_params.append(self.a, try self.p("{s}: ptr<function, {s}>", .{ wn, try self.tyText(t) }));
                    try self.push(try self.newSym(.{ .name = prm.name, .wname = wn, .kind = .ptr, .ty = t }));
                },
                else => unreachable,
            }
        }
        try self.lowerStmtList(l.body.kind.block);
        const ret: Type = ctx.ret orelse .void;
        inst.ret = ret;
        try lam_params.appendSlice(self.a, sig.items);
        const ret_txt = if (ret == .void) "" else try self.p(" -> {s}", .{try self.tyText(ret)});
        inst.text = try self.p("// lambda {s} (Metal line {d})\nfn {s}({s}){s} {{\n{s}{s}}}\n\n", .{ def.name, l.line, inst.name, try std.mem.join(self.a, ", ", lam_params.items), ret_txt, prologue.items, body.items });
        inst.state = .done;
        try self.insts.append(self.a, inst);
    }

    // ----------------------------------------------------------------- output
    pub fn emit(self: *Lowerer, header: []const u8, label: []const u8) Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(self.a, header);
        try out.print(self.a, "\n// ---- Translated from {s} by tools/msl2wgsl.zig; do not edit: change the .metal file. ----\n\n", .{label});
        if (self.pool.items.len > 0) {
            try out.print(self.a, "// The theme's strings, NUL-terminated (Metal's constant char arrays).\nconst M2W_STR = array<i32, {d}>(", .{self.pool.items.len});
            for (self.pool.items, 0..) |c, i| {
                if (i > 0) try out.appendSlice(self.a, ", ");
                if (i % 24 == 0) try out.appendSlice(self.a, "\n    ");
                try out.print(self.a, "{d}", .{c});
            }
            try out.appendSlice(self.a, ");\n\n");
        }
        if (self.helpers.items.len > 0) {
            try out.appendSlice(self.a, self.helpers.items);
            try out.append(self.a, '\n');
        }
        try out.appendSlice(self.a, self.decls.items);
        try out.append(self.a, '\n');
        if (self.wg_vars.items.len > 0) {
            try out.appendSlice(self.a, self.wg_vars.items);
            try out.append(self.a, '\n');
        }
        for (self.insts.items) |i| try out.appendSlice(self.a, i.text);
        try out.appendSlice(self.a, self.kernels.items);
        return out.items;
    }
};

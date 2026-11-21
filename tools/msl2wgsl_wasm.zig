//! tools/msl2wgsl_wasm.zig: the Metal-to-WGSL translator (tools/msl2wgsl.zig) as a wasm module, so
//! a page translates a dropped or linked .metal theme itself (web/msl2wgsl/msl2wgsl.js).
//!
//!   make web-msl2wgsl     # web/msl2wgsl/msl2wgsl.wasm
//!
//! The page writes the source into memory from `alloc`, calls `translate`, then reads the result
//! (`result_ptr`, `result_len`): the WGSL when `translate` returns 1, else the diagnostic
//! "line:col: message". Each call frees the previous call's memory.

const std = @import("std");
const msl2wgsl = @import("msl2wgsl.zig");

var arena_state: std.heap.ArenaAllocator = .init(std.heap.wasm_allocator);
var result: []const u8 = "";

/// Memory for the page to write `n` bytes of input into (freed by the next `translate`).
export fn alloc(n: usize) ?[*]u8 {
    const buf = arena_state.allocator().alloc(u8, n) catch return null;
    return buf.ptr;
}

/// Translates `len` bytes at `src` (a theme labelled `label`). 1: `result_*` is the WGSL; 0: it
/// is the diagnostic; 2: out of memory.
export fn translate(src: [*]const u8, len: usize, label: [*]const u8, label_len: usize) u32 {
    const a = arena_state.allocator();
    const r = msl2wgsl.translate(a, src[0..len], label[0..label_len]) catch {
        result = "out of memory";
        return 2;
    };
    switch (r) {
        .ok => |wgsl| {
            result = wgsl;
            return 1;
        },
        .err => |d| {
            result = std.fmt.allocPrint(a, "{d}:{d}: {s}", .{ d.line, d.col, d.msg }) catch "out of memory";
            return 0;
        },
    }
}

export fn result_ptr() [*]const u8 {
    return result.ptr;
}

export fn result_len() usize {
    return result.len;
}

/// Frees everything from the last call (the page calls it once it has read the result).
export fn reset() void {
    _ = arena_state.reset(.free_all);
    result = "";
}

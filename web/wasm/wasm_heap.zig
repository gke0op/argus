// ============================================================================
// web/wasm/wasm_heap.zig — std.heap.page_allocator for threaded WebAssembly
//
// Zig 0.17's std has no page allocator for wasm with threads (heap.WasmAllocator is a compile
// error unless single_threaded), but it lets the root module supply one: runtime.zig exposes
// this as `root.os.heap.page_allocator`, so a theme's `std.heap.page_allocator` (and the SDK's
// CountingAllocator, which wraps it) resolve here without a line of the theme changing.
//
// Whole 64 KiB wasm pages from memory.grow, a first-fit free list, one spinlock. Allocation is
// rare (a theme allocates once, in init; the host a few frame buffers), so simple wins.
// ============================================================================

const std = @import("std");
const Alignment = std.mem.Alignment;

pub const page_size: usize = 64 * 1024;

const Free = struct { pages: usize, next: ?*Free };

var lock: std.atomic.Value(u32) = .init(0);
var free_list: ?*Free = null;
/// Pages taken from memory.grow so far (for stats).
pub var pages_grown: usize = 0;

pub const allocator: std.mem.Allocator = .{ .ptr = undefined, .vtable = &vtable };

const vtable: std.mem.Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .remap = remap,
    .free = free,
};

fn acquire() void {
    while (lock.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}
fn release() void {
    lock.store(0, .release);
}

inline fn pagesFor(len: usize) usize {
    return @max(1, std.math.divCeil(usize, len, page_size) catch unreachable);
}

fn alloc(_: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
    if (alignment.toByteUnits() > page_size) return null;
    const n = pagesFor(len);
    acquire();
    defer release();
    var link: *?*Free = &free_list;
    while (link.*) |blk| : (link = &blk.next) {
        if (blk.pages < n) continue;
        if (blk.pages == n) {
            link.* = blk.next;
        } else {
            const rest: *Free = @ptrFromInt(@intFromPtr(blk) + n * page_size);
            rest.* = .{ .pages = blk.pages - n, .next = blk.next };
            link.* = rest;
        }
        return @ptrCast(blk);
    }
    const first = @wasmMemoryGrow(0, n);
    if (first < 0) return null;
    pages_grown += n;
    return @ptrFromInt(@as(usize, @intCast(first)) * page_size);
}

fn resize(_: *anyopaque, buf: []u8, _: Alignment, new_len: usize, _: usize) bool {
    return pagesFor(new_len) == pagesFor(buf.len);
}

fn remap(ctx: *anyopaque, buf: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
    return if (resize(ctx, buf, alignment, new_len, ra)) buf.ptr else null;
}

fn free(_: *anyopaque, buf: []u8, _: Alignment, _: usize) void {
    const blk: *Free = @ptrCast(@alignCast(buf.ptr));
    acquire();
    defer release();
    blk.* = .{ .pages = pagesFor(buf.len), .next = free_list };
    free_list = blk;
}

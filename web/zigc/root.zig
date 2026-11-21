// web/zigc/root.zig — the root module for a theme compiled in the browser (web/zigc).
//
// zig.wasm has only the self-hosted wasm backend. For an executable it builds compiler_rt as a
// separate library, which its wasm linker then cannot read (Zig 0.17.0: the archive is written
// as a bare object; a self-hosted object has no target_features section). So compiler_rt is
// compiled into the same compilation instead, as Zig itself does for an object (the `.zcu`
// strategy in Compilation.zig): `-Mcompiler_rt=/lib/compiler_rt.zig`, imported here.
// The self-hosted linker also cannot leave a weak function undefined, which runtime.zig relies
// on for hand-written themes; `web_absent` below stands in for it.
// Everything else is web/wasm/runtime.zig, the root `make web-wasm` builds, unchanged.
const runtime = @import("runtime");

/// The optional theme ABI functions this theme does not export (runtime.zig `weak`): the page
/// links once with none listed, and again with the ones the linker reported undefined.
pub const web_absent: []const []const u8 = &@import("absent").names;

/// std.heap.page_allocator for threaded wasm (runtime.zig, wasm_heap.zig).
pub const os = runtime.os;

comptime {
    _ = runtime;
    _ = @import("compiler_rt");
}

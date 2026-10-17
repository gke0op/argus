// ============================================================================
// ARGUS DESKTOP // src/desktop/verify_child.zig
//
// A standalone `--verify-dylib` for the watchdog tests: the app checks themes with its own
// executable, but the test binary can't run as one. Same check (space_config.verifyDylibSafety).
// ============================================================================

const std = @import("std");
const sc = @import("space_config.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3 or !std.mem.eql(u8, args[1], "--verify-dylib")) std.process.exit(2);
    var path_z_buf: [512]u8 = undefined;
    const dylib_z = std.fmt.bufPrintSentinel(&path_z_buf, "{s}", .{args[2]}, 0) catch std.process.exit(1);
    std.process.exit(if (sc.verifyDylibSafety(dylib_z)) 0 else 1);
}

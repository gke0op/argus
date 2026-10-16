//! ARGUS-BENCH test ledger, for the tools in src/ (claim_check, gpu_bench). Same schema and
//! verdict as themes/argus_theme_sdk.zig `ledger` (theme tests): the theme module owns that
//! file, so the tools cannot import it. Keep the two in step.
const std = @import("std");

pub const Record = struct {
    id: []const u8,
    claim: []const u8,
    /// Reference quantity and its source (paper, closed form, independent code).
    reference: []const u8,
    conditions: []const u8,
    /// What `measured` is, with units.
    quantity: []const u8,
    measured: f64,
    /// Pass iff lo <= measured <= hi; no bounds = reported, not asserted.
    lo: ?f64 = null,
    hi: ?f64 = null,
    source: []const u8,
};

pub fn emit(r: Record) bool {
    const asserted = r.lo != null or r.hi != null;
    const pass = !std.math.isNan(r.measured) and
        (r.lo == null or r.measured >= r.lo.?) and (r.hi == null or r.measured <= r.hi.?);
    std.debug.print("\nLEDGER {f}\n", .{std.json.fmt(.{
        .id = r.id,
        .claim = r.claim,
        .reference = r.reference,
        .conditions = r.conditions,
        .quantity = r.quantity,
        .measured = if (std.math.isFinite(r.measured)) @as(?f64, r.measured) else null,
        .lo = r.lo,
        .hi = r.hi,
        .pass = if (asserted) @as(?bool, pass) else null,
        .source = r.source,
    }, .{})});
    return pass or !asserted;
}

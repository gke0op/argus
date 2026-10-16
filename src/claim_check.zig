//! ARGUS-BENCH claim checker: does the artifact do what it claims?
//! Separate from theme_harness.zig (does the artifact work?). Passing one never implies the other.
//!
//!   make claims THEME=themes/X.zig
//!
//! Reads the theme's `claims` (sdk.Claims), drives its `probeEquatorialRay`, and compares
//! against an independent reference written here, not shared with any theme:
//!   - critical impact parameters b_c (prograde / retrograde) for the declared metric,
//!   - total deflection angles of escaping equatorial photons at several b.
//! Status: NO CLAIM | DECLARED (no probe, unverified) | REFERENCE-VALIDATED | FALSIFIED.
//! Limits: equatorial rays only (inclination untested); the probe is trusted to route
//! through the same light-path code as draw().
//! Each check at the declared spin also prints a `LEDGER {json}` record (src/ledger.zig);
//! `make ledger` collects them.
const std = @import("std");
const theme = @import("theme");
const ledger = @import("ledger.zig");

const LEDGER_SRC = "make claims";

// ---------------- Independent reference: equatorial Kerr null geodesics (G = c = M = 1) ----------------
// Radial potential R(r) = (r^2 + a^2 - a b)^2 - Delta (b - a)^2, Delta = r^2 - 2r + a^2.
// dphi/dr = [(b - a) + a (r^2 + a^2 - a b) / Delta] / sqrt(R).  b > 0 is prograde. a = 0 is Schwarzschild.

fn radialPot(r: f64, a: f64, b: f64) f64 {
    const delta = r * r - 2.0 * r + a * a;
    const p = r * r + a * a - a * b;
    return p * p - delta * (b - a) * (b - a);
}

/// Outermost turning point outside the horizon, or null when the photon is captured.
fn turningPoint(a: f64, b: f64) ?f64 {
    const r_h = 1.0 + @sqrt(1.0 - a * a);
    const dr = 1.0e-3;
    var r = 4.0 * @abs(b) + 10.0;
    while (r - dr > r_h) : (r -= dr) {
        if (radialPot(r - dr, a, b) < 0.0) {
            var lo = r - dr;
            var hi = r;
            for (0..80) |_| {
                const mid = 0.5 * (lo + hi);
                if (radialPot(mid, a, b) < 0.0) lo = mid else hi = mid;
            }
            return hi;
        }
    }
    return null;
}

/// Total deflection (rad) by midpoint quadrature in s, with r = r0 / (1 - s^2) removing the
/// inverse-square-root singularity at the turning point. Null when captured.
fn refDeflection(a: f64, b: f64) ?f64 {
    const r0 = turningPoint(a, b) orelse return null;
    const n: usize = 200_000;
    var sum: f64 = 0.0;
    for (0..n) |i| {
        const s = (@as(f64, @floatFromInt(i)) + 0.5) / @as(f64, @floatFromInt(n));
        const x = 1.0 - s * s;
        const r = r0 / x;
        const delta = r * r - 2.0 * r + a * a;
        const dphi_dr = ((b - a) + a * (r * r + a * a - a * b) / delta) / @sqrt(radialPot(r, a, b));
        sum += dphi_dr * (r0 / (x * x)) * 2.0 * s;
    }
    return 2.0 * @abs(sum) / @as(f64, @floatFromInt(n)) - std.math.pi;
}

/// Closed form (Bardeen 1973): signed critical b of the equatorial photon orbits.
fn closedFormCriticalB(a: f64, prograde: bool) f64 {
    return if (prograde)
        -a + 6.0 * @cos(std.math.acos(-a) / 3.0)
    else
        -a - 6.0 * @cos(std.math.acos(a) / 3.0);
}

/// Signed critical b by bisection on capture; `captured` is the oracle.
fn bisectCritical(ctx: anytype, comptime captured: fn (@TypeOf(ctx), f64) bool, sign: f64) f64 {
    var lo: f64 = 0.5; // captured
    var hi: f64 = 12.0; // escapes
    for (0..60) |_| {
        const mid = 0.5 * (lo + hi);
        if (captured(ctx, sign * mid)) lo = mid else hi = mid;
    }
    return sign * 0.5 * (lo + hi);
}

fn refCaptured(a: f64, b: f64) bool {
    return turningPoint(a, b) == null;
}

fn themeCaptured(st: *const theme.State, b: f64) bool {
    return st.probeEquatorialRay(b).captured;
}

const BC_REL_TOL = 0.015;
const DEFL_ABS_TOL = 0.02;
const DEFL_REL_TOL = 0.02;

/// Compares the theme's probe against the reference for spin `a`; returns failures.
fn compare(st: *const theme.State, a: f64, verbose: bool) usize {
    var fails: usize = 0;
    for ([_]f64{ 1.0, -1.0 }) |sign| {
        const side = if (sign > 0) "prograde " else "retrograde";
        const ref_bc = closedFormCriticalB(a, sign > 0);
        const th_bc = bisectCritical(st, themeCaptured, sign);
        const bc_err = @abs(th_bc - ref_bc) / @abs(ref_bc);
        const bc_ok = bc_err <= BC_REL_TOL;
        if (!bc_ok) fails += 1;
        var cond_buf: [256]u8 = undefined;
        var id_buf: [64]u8 = undefined;
        if (verbose) {
            std.debug.print("  {s} b_c   theme {d:>8.4}  ref {d:>8.4}  rel err {d:>7.4}  {s}\n", .{ side, th_bc, ref_bc, bc_err, if (bc_ok) "PASS" else "FAIL" });
            _ = ledger.emit(.{
                .id = std.fmt.bufPrint(&id_buf, "claims.b_c.{s}", .{if (sign > 0) "prograde" else "retrograde"}) catch unreachable,
                .claim = "Equatorial photons are captured below the Kerr critical impact parameter b_c",
                .reference = "Bardeen 1973 closed form b_c (checked against src/claim_check.zig's own numerical turning-point search)",
                .conditions = std.fmt.bufPrint(&cond_buf, "{s} metric, declared a/M = {d:.3}, equatorial rays through the theme's probe, 60 bisections on capture; ref b_c = {d:.6} M", .{ @tagName(theme.claims.metric), a, ref_bc }) catch unreachable,
                .quantity = "|b_c theme - b_c ref| / |b_c ref|",
                .measured = bc_err,
                .hi = BC_REL_TOL,
                .source = LEDGER_SRC,
            });
        }
        for ([_]f64{ 1.3, 1.6, 2.2, 3.0 }) |k| {
            const b = k * ref_bc;
            const ref_d = refDeflection(a, b) orelse unreachable;
            const p = st.probeEquatorialRay(b);
            const th_d = if (p.captured) std.math.nan(f64) else p.deflection;
            const err = @abs(th_d - ref_d);
            const ok = !p.captured and err <= @max(DEFL_ABS_TOL, DEFL_REL_TOL * ref_d);
            if (!ok) fails += 1;
            if (verbose) {
                std.debug.print("  {s} b={d:>7.3}  deflection theme {d:>8.4}  ref {d:>8.4}  rad  {s}\n", .{ side, b, th_d, ref_d, if (ok) "PASS" else "FAIL" });
                _ = ledger.emit(.{
                    .id = std.fmt.bufPrint(&id_buf, "claims.deflection.{s}.{d:.1}b_c", .{ if (sign > 0) "prograde" else "retrograde", k }) catch unreachable,
                    .claim = "Escaping equatorial photons are deflected by the Kerr angle",
                    .reference = "independent quadrature of the equatorial Kerr orbit equation dphi/dr (src/claim_check.zig)",
                    .conditions = std.fmt.bufPrint(&cond_buf, "{s} metric, declared a/M = {d:.3}, b = {d:.4} M ({d:.1} b_c); ref deflection {d:.6} rad", .{ @tagName(theme.claims.metric), a, b, k, ref_d }) catch unreachable,
                    .quantity = "|deflection theme - deflection ref| (rad)",
                    .measured = err,
                    .hi = @max(DEFL_ABS_TOL, DEFL_REL_TOL * ref_d),
                    .source = LEDGER_SRC,
                });
            }
        }
    }
    return fails;
}

pub fn main() !void {
    // Reference self-check: two independent methods must agree before anything is judged.
    for ([_]f64{ 0.0, 0.5, 0.94 }) |a| {
        for ([_]bool{ true, false }) |pro| {
            const num = bisectCritical(a, refCaptured, if (pro) 1.0 else -1.0);
            const cf = closedFormCriticalB(a, pro);
            if (@abs(num - cf) > 1e-4) {
                std.debug.print("REFERENCE SELF-CHECK FAILED: a={d} prograde={} numeric {d} closed-form {d}\n", .{ a, pro, num, cf });
                std.process.exit(3);
            }
        }
    }
    // Weak-field sanity: deflection -> 4/b for large b (Schwarzschild).
    const wf = refDeflection(0.0, 2000.0).?;
    if (@abs(wf - 4.0 / 2000.0) > 2e-5) {
        std.debug.print("REFERENCE SELF-CHECK FAILED: weak-field deflection {d}\n", .{wf});
        std.process.exit(3);
    }
    std.debug.print("reference self-check: closed-form vs numerical b_c agree (a = 0, 0.5, 0.94); weak field OK\n", .{});

    if (!@hasDecl(theme, "claims") or theme.claims.metric == .none) {
        std.debug.print("STATUS: NO CLAIM (theme declares no spacetime)\n", .{});
        return;
    }
    const c = theme.claims;
    std.debug.print("declared: metric={s} a/M={d:.3} i={d:.1} deg\n", .{ @tagName(c.metric), c.spin, c.inclination_deg });
    if (!@hasDecl(theme.State, "probeEquatorialRay")) {
        std.debug.print("STATUS: DECLARED (no probe, unverified)\n", .{});
        return;
    }

    const st = try theme.State.init(std.heap.page_allocator, 1920, 1200, 1.0);
    defer st.deinit(std.heap.page_allocator);

    const a_claim: f64 = if (c.metric == .kerr) c.spin else 0.0;
    std.debug.print("checking against reference at declared a/M = {d:.3}:\n", .{a_claim});
    const fails = compare(st, a_claim, true);
    if (fails == 0) {
        std.debug.print("STATUS: REFERENCE-VALIDATED (equatorial light paths; inclination untested)\n", .{});
        return;
    }
    std.debug.print("STATUS: FALSIFIED ({d} checks failed for the declared {s} a/M = {d:.3})\n", .{ fails, @tagName(c.metric), a_claim });
    // Diagnose: which spin are the light paths actually consistent with?
    for ([_]f64{ 0.0, 0.25, 0.5, 0.75, 0.94, 0.99 }) |a| {
        if (a == a_claim) continue;
        if (compare(st, a, false) == 0) std.debug.print("  light paths ARE consistent with a/M = {d:.2}{s}\n", .{ a, if (a == 0.0) " (Schwarzschild)" else "" });
    }
    std.process.exit(1);
}

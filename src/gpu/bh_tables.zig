// ============================================================================
// ARGUS GPU PROTOTYPE // src/gpu/bh_tables.zig
//
// Copies themes/Opus_Black_Hole.zig's tables into the layouts the Metal kernel reads
// (src/gpu/opus_black_hole.metal: struct Static / struct Frame / buffers 0-4).
// `st` is the theme's `*State`; nothing in the theme is modified.
// ============================================================================

const std = @import("std");

pub const R_BINS = 384;
pub const NSPOT = 6;
pub const EMIT_N = 1024;
pub const BB_N = 1024;
/// TAU_THICK * e^TAU_NOISE, private in the theme.
pub const TAU_BEHIND: f32 = @floatCast(5.0 * @exp(@as(f64, 1.2)));

pub const Frame = extern struct {
    gshift: [2][R_BINS]u16,
    grow: [2][R_BINS]u16,
    spot_mask: [R_BINS]u8,
    spot_rb: [NSPOT]f32,
    spot_wr: [NSPOT]f32,
    spot_wp: [NSPOT]f32,
    spot_amp: [NSPOT]f32,
    spot_q: [NSPOT]u16,
    gw: [2]f32,
    gnorm: f32,
    exposure: f32,
    tau_behind: f32,
    width: u32,
    height: u32,
};

pub const Static = extern struct {
    tau_tab: [R_BINS]f32,
    lntau_tab: [R_BINS]f32,
    emit_tab: [EMIT_N + 1]f32,
    lin8: [256]f32,
    bb: [BB_N][3]f32,
    srgb: [4096]u8,
};

pub fn fillStatic(st: anytype, out: *Static) void {
    comptime {
        std.debug.assert(@sizeOf(@TypeOf(st.recs[0])) == 18);
    }
    out.tau_tab = st.tau_tab;
    out.lntau_tab = st.lntau_tab;
    out.emit_tab = st.emit_tab;
    out.lin8 = st.lin8;
    out.bb = st.bb;
    out.srgb = st.srgb;
}

pub fn fillFrame(st: anytype, out: *Frame) void {
    out.gshift = st.gshift;
    out.grow = st.grow;
    out.spot_mask = st.spot_mask;
    out.spot_rb = st.spot_rb;
    out.spot_wr = st.spot_wr;
    out.spot_wp = st.spot_wp;
    out.spot_amp = st.spot_amp;
    out.spot_q = st.spot_q;
    out.gw = st.gw;
    out.gnorm = st.gnorm;
    out.exposure = st.exposure;
    out.tau_behind = TAU_BEHIND;
    out.width = @intCast(st.w);
    out.height = @intCast(st.h);
}

/// The per-pixel buffers the kernel binds at indices 0-4, as raw bytes.
pub fn pixelBuffers(st: anytype) [5][]const u8 {
    return .{
        std.mem.sliceAsBytes(st.recs),
        std.mem.sliceAsBytes(st.bg),
        std.mem.sliceAsBytes(st.row_x0),
        std.mem.sliceAsBytes(st.row_x1),
        std.mem.sliceAsBytes(&st.noise),
    };
}

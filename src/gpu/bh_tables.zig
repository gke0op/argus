// ============================================================================
// ARGUS GPU // src/gpu/bh_tables.zig
//
// Copies a Kerr-disk theme's tables into the layouts the Metal kernels read
// (src/gpu/opus_black_hole.metal: struct Static / Frame / TraceParams / View).
// `st` is the theme's `*State`; nothing in the theme is modified.
//
// The GPU path traces its own image (bh_meter -> bh_trace -> bh_footprint) at the
// window's native size and shades it every frame (bh_shade). From the theme it needs
// only resolution-free tables: colour and opacity tables, the temperature profile,
// the turbulence noise, the geometry, and the per-frame step() state.
// ============================================================================

const std = @import("std");

pub const R_BINS = 384;
pub const NP = 1024;
pub const NSPOT = 6;
pub const EMIT_N = 1024;
pub const BB_N = 1024;
pub const PT_N = 4096;
pub const NR = 2048; // turbulence rows
pub const N_OCT = 2; // turbulence octaves
pub const NBAND = 12; // turbulence lifetime bands

/// One generation of eddies (mirrors the theme's TurbGen and `struct TurbGen`).
pub const TurbGen = extern struct { w: f32, age_q: f32, rowoff: u32, phoff: u32 };
/// Samples per pixel side in the GPU trace (2 -> 4 samples per pixel).
pub const SS: u32 = 2;
/// Exposure metering grid width (the theme meters on the same 192-wide grid).
pub const METER_W: u32 = 192;

pub const Frame = extern struct {
    gen: [N_OCT][NBAND][2]TurbGen,
    spot_mask: [R_BINS]u8,
    spot_rb: [NSPOT]f32,
    spot_wr: [NSPOT]f32,
    spot_wp: [NSPOT]f32,
    spot_amp: [NSPOT]f32,
    spot_q: [NSPOT]u16,
    exposure: f32,
    width: u32,
    height: u32,
    spot_age: [NSPOT]f32,
    spot_om: [NSPOT]f32,
};

pub const Static = extern struct {
    lntau_tab: [R_BINS]f32, // ln vertical extinction depth per radial bin
    lnem_tab: [R_BINS]f32, // ln vertical thermalisation depth per radial bin
    emit_tab: [EMIT_N + 1]f32,
    lin8: [256]f32,
    bb: [BB_N][3]f32,
    sband: [N_OCT][R_BINS]f32, // log2(eddy lifetime / L0) per octave and radial bin
    om_row: [NR]f32, // Omega at each turbulence row
    cell_r0: f32, // octave-0 eddy cell: radial bins
    cell_p0: f32, // octave-0 eddy cell: azimuth, Q16
    turb_sigma: f32, // rms of ln(dissipation): the theme's TURB_SIGMA
    rho_row: [N_OCT]f32, // neighbour correlation of each noise plane: rows, phase cells
    rho_ph: [N_OCT]f32,
    foot_cr: [N_OCT]f32, // footprint filter cell constants (box average of the rendered field)
    foot_cp: [N_OCT]f32,
    sky_gain: f32, // 0 = black sky (the theme's SKY_VISIBLE)
    fcol_follow: f32, // 1 = f_col re-evaluated at the turbulence/spot temperature (FCOL_FOLLOWS)
    srgb: [4096]u8,
};

/// Geometry and sky placement for the GPU trace (mirrors `struct TraceParams`).
pub const TraceParams = extern struct {
    gal_n: [4]f32,
    gal_c: [4]f32,
    a: f32,
    sin_i: f32,
    cos_i: f32,
    incl: f32,
    rh: f32,
    r_in: f32,
    r_out: f32,
    lnr_in: f32,
    lnr_span: f32,
    lnt_span: f32, // ln(R_OUT * 1.05 / r_in): the temperature table's log-radius span
    mpp: f32, // M per pixel at the traced resolution
    pix_ang: f32, // sky angle per pixel at the camera
    exposure: f32,
    width: u32,
    height: u32,
    row0: u32, // first row of this tile
    grid_w: u32, // exposure meter grid
    grid_h: u32,
    spot_rmax: f32, // hot spots orbit inside this radius: gas there is never baked static
    _pad: u32 = 0, // Metal rounds the struct to 16 bytes (float4 members)
};

/// Per-frame view state the presenter adds to the theme's Frame (mirrors `struct View`).
pub const View = extern struct {
    width: u32, // traced (native) size
    height: u32,
    out_w: u32, // output size: the drawable, or the 1920x1200 menu preview
    out_h: u32,
    rows_done: u32, // rows the trace has finished; later rows draw black
    exposure: f32,
    headroom: f32, // display EDR headroom: 1 = SDR
    out_mode: OutMode,
};

pub const OutMode = enum(u32) {
    linear = 0, // extended-range linear sRGB (RGBA16F)
    srgb = 1, // 8-bit sRGB (menu previews, SDR layers)
    pq = 2, // HDR10: BT.2020 primaries, PQ, 10-bit (EDR layers)
};

pub fn fillStatic(st: anytype, out: *Static) void {
    out.lntau_tab = st.lntau_tab;
    out.lnem_tab = st.lnem_tab;
    out.emit_tab = st.emit_tab;
    out.lin8 = st.lin8;
    out.bb = st.bb;
    out.sband = st.sband;
    out.om_row = st.om_row;
    out.cell_r0 = st.cell_r0;
    out.cell_p0 = st.cell_p0;
    out.turb_sigma = st.turb_sigma;
    out.rho_row = st.rho_row;
    out.rho_ph = st.rho_ph;
    out.foot_cr = st.foot_cr;
    out.foot_cp = st.foot_cp;
    out.sky_gain = st.sky_gain;
    out.fcol_follow = st.fcol_follow;
    out.srgb = st.srgb;
}

pub fn fillFrame(st: anytype, out: *Frame) void {
    for (0..N_OCT) |j| {
        for (0..NBAND) |n| {
            for (0..2) |g| {
                const t = st.gen[j][n][g];
                out.gen[j][n][g] = .{ .w = t.w, .age_q = t.age_q, .rowoff = t.rowoff, .phoff = t.phoff };
            }
        }
    }
    out.spot_mask = st.spot_mask;
    out.spot_rb = st.spot_rb;
    out.spot_wr = st.spot_wr;
    out.spot_wp = st.spot_wp;
    out.spot_amp = st.spot_amp;
    out.spot_q = st.spot_q;
    out.exposure = st.exposure;
    out.width = @intCast(st.w);
    out.height = @intCast(st.h);
    out.spot_age = st.spot_age;
    out.spot_om = st.spot_om;
}

/// Geometry for a `w` x `h` trace. Exposure and the tile row are filled in by the caller.
pub fn fillTrace(st: anytype, w: u32, h: u32, out: *TraceParams) void {
    const g = st.geo;
    const half_h = st.mpp * @as(f64, @floatFromInt(st.h)) / 2.0; // the theme's HALF_H
    const mpp = 2.0 * half_h / @as(f64, @floatFromInt(h));
    out.* = .{
        .gal_n = .{ @floatCast(st.gal_n[0]), @floatCast(st.gal_n[1]), @floatCast(st.gal_n[2]), 0 },
        .gal_c = .{ @floatCast(st.gal_c[0]), @floatCast(st.gal_c[1]), @floatCast(st.gal_c[2]), 0 },
        .a = @floatCast(g.a),
        .sin_i = @floatCast(g.sin_i),
        .cos_i = @floatCast(g.cos_i),
        .incl = @floatCast(g.incl),
        .rh = @floatCast(g.rh),
        .r_in = @floatCast(g.r_in),
        .r_out = @floatCast(g.r_out),
        .lnr_in = @floatCast(st.lnr_in),
        .lnr_span = @floatCast(st.lnr_span),
        .lnt_span = @floatCast(@log(g.r_out * 1.05 / g.r_in)),
        .mpp = @floatCast(mpp),
        .pix_ang = @floatCast(mpp * st.pix_ang / st.mpp),
        .exposure = 1.0,
        .width = w,
        .height = h,
        .row0 = 0,
        .grid_w = METER_W,
        .grid_h = @max(1, METER_W * h / @max(w, 1)),
        .spot_rmax = @floatCast(st.spot_rmax),
    };
    comptime std.debug.assert(@sizeOf(TraceParams) == 112);
}

/// Exposure from the meter kernel's luminances (0 = not inner disk): the theme's rule,
/// 99th-percentile inner-disk luminance at EXPO_TARGET.
pub fn exposureFrom(lum: []const f32, target: f64) f32 {
    var hist: [512]u32 = @splat(0);
    var count: u64 = 0;
    for (lum) |yl| {
        if (!(yl > 0.0)) continue;
        const bin: usize = @intFromFloat(std.math.clamp((std.math.log2(@as(f64, yl)) + 32.0) * 8.0, 0.0, 511.0));
        hist[bin] += 1;
        count += 1;
    }
    if (count == 0) return 1.0;
    var acc: u64 = 0;
    const want = count - count / 100;
    for (hist, 0..) |c, b| {
        acc += c;
        if (acc >= want) return @floatCast(target / std.math.pow(f64, 2.0, @as(f64, @floatFromInt(b)) / 8.0 - 32.0));
    }
    return 1.0;
}

/// The theme's turbulence noise (N_OCT x NR x NP bytes).
pub fn noiseBytes(st: anytype) []const u8 {
    return std.mem.sliceAsBytes(&st.noise);
}

/// The computed disk: temperature, ln extinction depth, ln thermalisation depth (3 x PT_N floats).
pub fn ttabBytes(st: anytype) []const u8 {
    return std.mem.sliceAsBytes(&st.dtab);
}

/// Bytes per traced pixel kept on the GPU: record (6) + background (4, RGB9E5) + the share of
/// the background that lies behind the animated gas (1) + its line-of-sight slant ln(1/mu) (1)
/// + the transmission of faint gas in front of it (1).
/// The trace also needs 2 bytes per pixel of light-travel phase until the footprint pass is done.
pub const BYTES_PER_PIXEL: usize = 13;
pub const TEMP_BYTES_PER_PIXEL: usize = 2;

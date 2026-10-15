const std = @import("std");
const math = std.math;
pub const sc = @import("desktop/space_config.zig");
pub const obs_mod = @import("desktop/observatory.zig");
const gpu = @import("gpu/presenter.zig");
const metal_theme = @import("gpu/metal_theme.zig");
const status_glyph = @import("desktop/status_glyph.zig");

pub const NATIVE_W = sc.NATIVE_W;
pub const NATIVE_H = sc.NATIVE_H;
pub const NATIVE_PIXELS = sc.NATIVE_PIXELS;
pub const NATIVE_SCALE = sc.NATIVE_SCALE;
pub const POPOVER_W = sc.POPOVER_W;
pub const POPOVER_H = sc.POPOVER_H;
pub const POPOVER_SCALE = sc.POPOVER_SCALE;
pub const POPOVER_BMP_W = sc.POPOVER_BMP_W;
pub const POPOVER_BMP_H = sc.POPOVER_BMP_H;
pub const POPOVER_PIXELS = sc.POPOVER_PIXELS;
pub const SPACE_LIST_TOP = sc.SPACE_LIST_TOP;
pub const SPACE_ROW_STEP = sc.SPACE_ROW_STEP;
pub const romanNumeral = sc.romanNumeral;
pub const STAR_BOX = sc.STAR_BOX;
pub const N_PHASES = sc.N_PHASES;
pub const N_ENERGIES = sc.N_ENERGIES;
pub const ENERGIES_KEV = sc.ENERGIES_KEV;
pub const N_VORTICES = sc.N_VORTICES;
pub const WAVE_G = sc.WAVE_G;
pub const WAVE_SIZE = sc.WAVE_SIZE;
pub const MAX_SPACES = sc.MAX_SPACES;
pub const DEFAULT_STATE_PATH = sc.DEFAULT_STATE_PATH;
pub const ZIG_017_BIN = sc.ZIG_017_BIN;

pub const CustomThemeRenderFn = sc.CustomThemeRenderFn;
pub const ThemeInitFn = sc.ThemeInitFn;
pub const ThemeDeinitFn = sc.ThemeDeinitFn;
pub const ThemeStepFn = sc.ThemeStepFn;
pub const ThemeDrawFn = sc.ThemeDrawFn;
pub const SpaceMode = sc.SpaceMode;
pub const SpaceConfig = sc.SpaceConfig;

pub const Observatory = obs_mod.Observatory;

pub var g_io: std.Io = undefined;

// ============================================================================
// BARE-METAL MACOS APP-KIT / CORE-GRAPHICS / CORETEXT / SKYLIGHT BRIDGE
// ============================================================================

const CGPoint = extern struct { x: f64, y: f64 };
const CGSize = extern struct { width: f64, height: f64 };
const CGRect = extern struct { origin: CGPoint, size: CGSize };

const MsgSend0 = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque;
const MsgSendVoid = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void;
const MsgSendVoidBool = *const fn (?*anyopaque, ?*anyopaque, bool) callconv(.c) void;
const MsgSendVoidInt = *const fn (?*anyopaque, ?*anyopaque, isize) callconv(.c) void;
const MsgSendVoidUInt = *const fn (?*anyopaque, ?*anyopaque, usize) callconv(.c) void;
const MsgSendVoidFloat = *const fn (?*anyopaque, ?*anyopaque, f64) callconv(.c) void;
const MsgSendVoidId = *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void;
const MsgSendIdRetId = *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque;
const MsgSendUIntRetId = *const fn (?*anyopaque, ?*anyopaque, usize) callconv(.c) ?*anyopaque;
const MsgSendId2 = *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void;
const MsgSendInitWin = *const fn (?*anyopaque, ?*anyopaque, CGRect, usize, usize, bool) callconv(.c) ?*anyopaque;
const MsgSendSetFrame = *const fn (?*anyopaque, ?*anyopaque, CGRect, bool) callconv(.c) void;
const MsgSendStatusItem = *const fn (?*anyopaque, ?*anyopaque, f64) callconv(.c) ?*anyopaque;
const MsgSendUTF8 = *const fn (?*anyopaque, ?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque;
const MsgSendTimer = *const fn (?*anyopaque, ?*anyopaque, f64, ?*anyopaque, ?*anyopaque, ?*anyopaque, bool) callconv(.c) ?*anyopaque;
const MsgSendRetPoint = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) CGPoint;
const MsgSendRetRect = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) CGRect;
const MsgSendRetInt = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) isize;
const MsgSendRetCStr = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?[*:0]const u8;
const MsgSendInitRect = *const fn (?*anyopaque, ?*anyopaque, CGRect) callconv(.c) ?*anyopaque;
const MsgSendInitImage = *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque, CGSize) callconv(.c) ?*anyopaque;
const MsgSendRetF64 = *const fn (?*anyopaque, ?*anyopaque) callconv(.c) f64;

const MacBridge = struct {
    obs: *Observatory,
    objc_getClass: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque,
    sel_registerName: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque,
    msg0: MsgSend0,
    msgVoid: MsgSendVoid,
    msgBool: MsgSendVoidBool,
    msgInt: MsgSendVoidInt,
    msgUInt: MsgSendVoidUInt,
    msgFloat: MsgSendVoidFloat,
    msgId: MsgSendVoidId,
    msgIdRetId: MsgSendIdRetId,
    msgUIntRetId: MsgSendUIntRetId,
    msgId2: MsgSendId2,
    msgInitWin: MsgSendInitWin,
    msgSetFrame: MsgSendSetFrame,
    msgUTF8: MsgSendUTF8,
    msgRetPoint: MsgSendRetPoint,
    msgRetRect: MsgSendRetRect,
    msgRetInt: MsgSendRetInt,
    msgRetCStr: MsgSendRetCStr,
    msgInitImage: MsgSendInitImage,

    // CoreGraphics
    CGBitmapContextCreate: *const fn (?*anyopaque, usize, usize, usize, usize, ?*anyopaque, u32) callconv(.c) ?*anyopaque,
    CGBitmapContextCreateImage: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    CGDataProviderCreateWithData: *const fn (?*anyopaque, ?*const anyopaque, usize, ?*const anyopaque) callconv(.c) ?*anyopaque,
    CGImageCreate: *const fn (usize, usize, usize, usize, usize, ?*anyopaque, u32, ?*anyopaque, ?*const f64, bool, i32) callconv(.c) ?*anyopaque,
    CGContextDrawImage: *const fn (?*anyopaque, CGRect, ?*anyopaque) callconv(.c) void,
    CGContextRelease: *const fn (?*anyopaque) callconv(.c) void,
    CGImageRelease: *const fn (?*anyopaque) callconv(.c) void,
    CGImageGetWidth: *const fn (?*anyopaque) callconv(.c) usize,
    CGImageGetHeight: *const fn (?*anyopaque) callconv(.c) usize,
    CGContextSaveGState: *const fn (?*anyopaque) callconv(.c) void,
    CGContextRestoreGState: *const fn (?*anyopaque) callconv(.c) void,
    CGContextScaleCTM: *const fn (?*anyopaque, f64, f64) callconv(.c) void,
    CGContextClearRect: *const fn (?*anyopaque, CGRect) callconv(.c) void,
    CGContextSetRGBFillColor: *const fn (?*anyopaque, f64, f64, f64, f64) callconv(.c) void,
    CGContextSetRGBStrokeColor: *const fn (?*anyopaque, f64, f64, f64, f64) callconv(.c) void,
    CGContextSetLineWidth: *const fn (?*anyopaque, f64) callconv(.c) void,
    CGContextBeginPath: *const fn (?*anyopaque) callconv(.c) void,
    CGContextMoveToPoint: *const fn (?*anyopaque, f64, f64) callconv(.c) void,
    CGContextAddLineToPoint: *const fn (?*anyopaque, f64, f64) callconv(.c) void,
    CGContextClosePath: *const fn (?*anyopaque) callconv(.c) void,
    CGContextFillPath: *const fn (?*anyopaque) callconv(.c) void,
    CGContextStrokePath: *const fn (?*anyopaque) callconv(.c) void,
    CGPathCreateWithRoundedRect: *const fn (CGRect, f64, f64, ?*const anyopaque) callconv(.c) ?*anyopaque,
    CGContextAddPath: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    CGContextClip: *const fn (?*anyopaque) callconv(.c) void,
    CGPathRelease: *const fn (?*anyopaque) callconv(.c) void,
    CGContextSetTextPosition: *const fn (?*anyopaque, f64, f64) callconv(.c) void,

    // CoreFoundation & ImageIO & CoreText
    CFURLCreateFromFileSystemRepresentation: *const fn (?*anyopaque, [*]const u8, isize, bool) callconv(.c) ?*anyopaque,
    CGImageSourceCreateWithURL: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque,
    CGImageSourceCreateWithData: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque,
    CGImageSourceCreateImageAtIndex: *const fn (?*anyopaque, usize, ?*anyopaque) callconv(.c) ?*anyopaque,
    CFRelease: *const fn (?*anyopaque) callconv(.c) void,
    CFStringCreateWithBytes: *const fn (?*anyopaque, [*]const u8, isize, u32, bool) callconv(.c) ?*anyopaque,
    CFAttributedStringCreate: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque,
    CTLineCreateWithAttributedString: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    CTLineDraw: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    CFArrayGetCount: *const fn (?*anyopaque) callconv(.c) isize,
    CFArrayGetValueAtIndex: *const fn (?*anyopaque, isize) callconv(.c) ?*anyopaque,
    CFDictionaryGetValue: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque,
    CFNumberGetValue: *const fn (?*anyopaque, i32, *anyopaque) callconv(.c) bool,

    // SkyLight private framework for dynamic macOS Spaces discovery & per-Space window binding
    cgs_conn: u32,
    CGSGetActiveSpace: *const fn (u32) callconv(.c) u64,
    CGSCopyManagedDisplaySpaces: *const fn (u32) callconv(.c) ?*anyopaque,
    CGSMoveWindowsToManagedSpace: *const fn (u32, ?*anyopaque, u64) callconv(.c) void,
    cf_key_spaces: ?*anyopaque,
    cf_key_id64: ?*anyopaque,
    cf_key_type: ?*anyopaque,

    // CoreText Font Attribute Dictionaries (SF Pro & Menlo)
    dict_title: ?*anyopaque,
    dict_body: ?*anyopaque,
    dict_small: ?*anyopaque,
    dict_mono: ?*anyopaque,

    ns_app: ?*anyopaque,
    NSWindow: ?*anyopaque,
    NSNumber: ?*anyopaque,
    NSArray: ?*anyopaque,
    NSURL: ?*anyopaque,
    desktop_level: isize,
    normal_window: bool,
    native_data_providers: [MAX_SPACES]?*anyopaque = @splat(null),
    popover_win: ?*anyopaque,
    popover_layer: ?*anyopaque,
    popover_bitmap_ctx: ?*anyopaque,
    status_button: ?*anyopaque,
    NSImage: ?*anyopaque,
    // Menu bar glyph: image size in points/pixels, and the (Spaces, current) it last showed.
    glyph_pt: f64,
    glyph_px: usize,
    glyph_n: usize = 0,
    glyph_cur: usize = std.math.maxInt(usize),
    glyph_alpha: [status_glyph.MAX_PX * status_glyph.MAX_PX]u8 = undefined,
    glyph_rgba: [status_glyph.MAX_PX * status_glyph.MAX_PX * 4]u8 = undefined,
    color_space: ?*anyopaque,
    display_id: u32,
    CGDisplayIsAsleep: *const fn (u32) callconv(.c) u32,
    CGSessionCopyCurrentDictionary: *const fn () callconv(.c) ?*anyopaque,
    cf_key_screen_locked: ?*anyopaque,
    cf_true: ?*const anyopaque,
    screen_locked: bool = false,
    sel_occlusion_state: ?*anyopaque,
    /// frame_idx + 1 of each Space's last rendered frame (0 = never), for warm-rate neighbors.
    last_render_tick: [MAX_SPACES]usize = @splat(0),
    perf_log: bool = false,
    // GPU prototype (`--gpu`): Metal presenters for Spaces whose theme has a GPU port.
    gpu_enabled: bool = false,
    gpu: [MAX_SPACES]?gpu.Presenter = @splat(null),
    gpu_tried: [MAX_SPACES]?*anyopaque = @splat(null),
    // Metal-only themes (themes/*.metal), one presenter per Space.
    mt: [MAX_SPACES]?gpu.ThemePresenter = @splat(null),
    mt_last_tick: [MAX_SPACES]usize = @splat(0),
    perf_renders: [MAX_SPACES]u16 = @splat(0),
    perf_visible: u16 = 0,
    screen_rect: CGRect,
    pboard_filenames_type: ?*anyopaque,
    popover_visible: bool = false,

    CATransaction: ?*anyopaque,
    NSString: ?*anyopaque,
    NSEvent: ?*anyopaque,
    sel_set_contents: ?*anyopaque,
    sel_flush: ?*anyopaque,
    sel_set_title: ?*anyopaque,
    sel_str_utf8: ?*anyopaque,
    sel_disable_actions: ?*anyopaque,
    sel_set_alpha: ?*anyopaque,
    sel_win_num: ?*anyopaque,
    sel_num_with_int: ?*anyopaque,
    sel_arr_with_obj: ?*anyopaque,

    frame_idx: usize = 0,
    max_frames: usize = 0,

    // ========================================================================
    // PER-SPACE NATIVE NSWINDOW & SKYLIGHT SPACE BINDING (120Hz Zero-Lag Swipe)
    // ========================================================================

    pub fn ensureSpaceWindow(self: *MacBridge, idx: usize) void {
        var sp = &self.obs.spaces[idx];
        if (sp.desktop_win == null) {
            const win_rect = if (self.normal_window)
                CGRect{ .origin = .{ .x = 120.0, .y = 120.0 }, .size = .{ .width = 960.0, .height = 600.0 } }
            else
                self.screen_rect;
            const style_mask: usize = if (self.normal_window) (1 | 2 | 4 | 8) else 0;
            const win = self.msgInitWin(
                self.msg0(self.NSWindow, self.sel_registerName("alloc")),
                self.sel_registerName("initWithContentRect:styleMask:backing:defer:"),
                win_rect,
                style_mask,
                2,
                false,
            );
            if (!self.normal_window) {
                self.msgInt(win, self.sel_registerName("setLevel:"), self.desktop_level);
                // Stationary (1 << 4) | IgnoresCycle (1 << 6) | FullScreenNone (1 << 9):
                // - Stationary (1 << 4) tells macOS Exposé / Show Desktop (4-finger pinch) that this window IS part of the desktop,
                //   so pinching never pushes the background away and never disables the 4-finger pinch gesture!
                // - Omitting CanJoinAllSpaces (1 << 0) keeps each window bound to its own Space for 120Hz trackpad swipe sliding!
                self.msgUInt(win, self.sel_registerName("setCollectionBehavior:"), (1 << 4) | (1 << 6) | (1 << 9));
                self.msgBool(win, self.sel_registerName("setIgnoresMouseEvents:"), true);
                self.msgSetFrame(win, self.sel_registerName("setFrame:display:"), self.screen_rect, true);
            }
            self.msgBool(win, self.sel_registerName("setOpaque:"), true);
            if (self.objc_getClass("NSColor")) |NSColor| {
                if (self.msg0(NSColor, self.sel_registerName("blackColor"))) |black_col| {
                    self.msgId(win, self.sel_registerName("setBackgroundColor:"), black_col);
                }
            }
            self.msgId(win, self.sel_registerName("orderFrontRegardless"), null);

            const view = self.msg0(win, self.sel_registerName("contentView"));
            // Layer-hosting mode (`setLayer:` before `setWantsLayer:true` + `NSViewLayerContentsRedrawNever = 0`):
            // Prevents AppKit's `_NSViewBackingLayer` from wiping `layer.contents` when swiping onto an unvisited Space!
            if (self.objc_getClass("CALayer")) |CALayer_cls| {
                if (self.msg0(CALayer_cls, self.sel_registerName("layer"))) |host_layer| {
                    self.msgFloat(host_layer, self.sel_registerName("setContentsScale:"), NATIVE_SCALE);
                    self.msgBool(host_layer, self.sel_registerName("setOpaque:"), true);
                    self.msgId(view, self.sel_registerName("setLayer:"), host_layer);
                }
            }
            self.msgBool(view, self.sel_registerName("setWantsLayer:"), true);
            self.msgInt(view, self.sel_registerName("setLayerContentsRedrawPolicy:"), 0);
            const layer = self.msg0(view, self.sel_registerName("layer"));
            self.msgFloat(layer, self.sel_registerName("setContentsScale:"), NATIVE_SCALE);

            sp.desktop_win = win;
            sp.desktop_layer = layer;
            sp.hidden_for_passthrough = false;
        }

        if (!self.normal_window and sp.bound_space_id != sp.space_id and sp.space_id > 0) {
            self.bindWindowToSpace(idx);
        }
    }

    pub fn bindWindowToSpace(self: *MacBridge, idx: usize) void {
        if (self.normal_window or idx >= self.obs.n_spaces) return;
        var sp = &self.obs.spaces[idx];
        if (sp.space_id == 0) return;
        if (sp.desktop_win) |win| {
            const wid: usize = @intCast(self.msgRetInt(win, self.sel_win_num));
            if (self.msgUIntRetId(self.NSNumber, self.sel_num_with_int, wid)) |num_obj| {
                if (self.msgIdRetId(self.NSArray, self.sel_arr_with_obj, num_obj)) |win_arr| {
                    self.CGSMoveWindowsToManagedSpace(self.cgs_conn, win_arr, sp.space_id);
                    sp.bound_space_id = sp.space_id;
                }
            }
        }
    }

    pub fn syncSpacesFromSkyLight(self: *MacBridge, initial_setup: bool) void {
        const active_id = self.CGSGetActiveSpace(self.cgs_conn);
        const displays = self.CGSCopyManagedDisplaySpaces(self.cgs_conn) orelse return;
        defer self.CFRelease(displays);

        var discovered_ids: [MAX_SPACES]u64 = @splat(0);
        var count: usize = 0;

        const n_disp = self.CFArrayGetCount(displays);
        var d_i: isize = 0;
        while (d_i < n_disp) : (d_i += 1) {
            const disp_dict = self.CFArrayGetValueAtIndex(displays, d_i) orelse continue;
            const sp_arr = self.CFDictionaryGetValue(disp_dict, self.cf_key_spaces) orelse continue;
            const n_sp = self.CFArrayGetCount(sp_arr);
            var s_i: isize = 0;
            while (s_i < n_sp and count < MAX_SPACES) : (s_i += 1) {
                const sp_dict = self.CFArrayGetValueAtIndex(sp_arr, s_i) orelse continue;
                var sid: i64 = 0;
                var stype: i64 = 0;
                if (self.CFDictionaryGetValue(sp_dict, self.cf_key_id64)) |num_id| {
                    _ = self.CFNumberGetValue(num_id, 4, &sid); // 4 = kCFNumberSInt64Type
                }
                if (self.CFDictionaryGetValue(sp_dict, self.cf_key_type)) |num_t| {
                    _ = self.CFNumberGetValue(num_t, 4, &stype);
                }
                // type == 0 is a standard macOS Desktop Space
                if (stype == 0 and sid > 0) {
                    discovered_ids[count] = @intCast(sid);
                    count += 1;
                }
            }
        }

        if (count == 0) return;

        if (initial_setup) {
            self.obs.n_spaces = count;
            self.obs.active_space_id = active_id;

            for (0..count) |idx| {
                self.obs.spaces[idx].space_id = discovered_ids[idx];
                self.obs.spaces[idx].index_1based = idx + 1;
                if (discovered_ids[idx] == active_id) {
                    self.obs.active_space_idx = idx;
                }
            }

            for (0..count) |idx| {
                self.ensureSpaceWindow(idx);
                self.bindWindowToSpace(idx);
            }

            if (!self.loadStateFromDisk()) {
                for (0..count) |idx| {
                    self.obs.spaces[idx].mode = .passthrough;
                }
                _ = self.loadCodeFileIntoSpaceInternal(self.obs.active_space_idx, "themes/Gemini_Wormhole.zig", false);
            }
            for (0..count) |idx| {
                if (self.obs.spaces[idx].cg_image == null and self.obs.spaces[idx].mode != .passthrough) {
                    self.renderSpaceAtIndex(idx);
                } else if (self.obs.spaces[idx].mode == .passthrough) {
                    self.renderSpaceAtIndex(idx);
                }
            }
            self.saveStateToDisk();
            return;
        }

        // Release WindowServer/CGImage resources for any Space that was closed in Mission Control
        for (0..self.obs.n_spaces) |old_idx| {
            const old_sid = self.obs.spaces[old_idx].space_id;
            var still_present = false;
            for (0..count) |new_idx| {
                if (discovered_ids[new_idx] == old_sid) {
                    still_present = true;
                    break;
                }
            }
            if (!still_present) {
                if (self.obs.spaces[old_idx].cg_image) |old_img| {
                    self.CGImageRelease(old_img);
                    self.obs.spaces[old_idx].cg_image = null;
                }
                if (self.obs.spaces[old_idx].desktop_win) |win| {
                    self.msgFloat(win, self.sel_set_alpha, 0.0);
                }
            }
        }

        const sync_res = self.obs.syncSpaceOrderByIds(discovered_ids[0..count], active_id);
        if (!sync_res.order_changed) return;

        for (0..count) |idx| {
            self.ensureSpaceWindow(idx);
            self.bindWindowToSpace(idx);
            if ((sync_res.moved_mask & (@as(u16, 1) << @intCast(idx))) != 0) {
                // Shader Spaces wrap the slot's per-index CGDataProvider; release the old slot's
                // CGImage and re-render immediately into the new slot's buffer + provider.
                if (self.obs.spaces[idx].mode != .picture) {
                    if (self.obs.spaces[idx].cg_image) |old_img| {
                        self.CGImageRelease(old_img);
                        self.obs.spaces[idx].cg_image = null;
                    }
                }
                self.renderSpaceAtIndex(idx);
            }
        }
        self.msgVoid(self.CATransaction, self.sel_flush);
        self.saveStateToDisk();
        if (self.popover_visible) self.flushPopoverLayer();
    }

    pub fn handleSpaceSwitch(self: *MacBridge, cur_space_id: u64) void {
        _ = cur_space_id;
        // Always reconcile with SkyLight on Space switch: if the user or macOS MRU rearranged
        // Spaces in Mission Control, `syncSpaceOrderByIds` moves each SpaceConfig with its `space_id`
        // (and when order is unchanged, it updates `active_space_idx` in O(N) with zero window work).
        self.syncSpacesFromSkyLight(false);
    }

    // ========================================================================
    // VECTOR UI & CORETEXT HELPERS (Stats-Grade Rounded Cards & Typography)
    // ========================================================================

    pub fn fillRoundRect(self: *MacBridge, ctx: ?*anyopaque, w_total: f64, h_total: f64, x: f64, top_y: f64, w: f64, h: f64, radius: f64, r: f64, g: f64, b: f64, a: f64) void {
        _ = w_total;
        const cg_y = h_total - top_y - h;
        const rect = CGRect{ .origin = .{ .x = x, .y = cg_y }, .size = .{ .width = w, .height = h } };
        const rad = @min(radius, @min(w * 0.5, h * 0.5));
        if (self.CGPathCreateWithRoundedRect(rect, rad, rad, null)) |path| {
            defer self.CGPathRelease(path);
            self.CGContextSetRGBFillColor(ctx, r, g, b, a);
            self.CGContextBeginPath(ctx);
            self.CGContextAddPath(ctx, path);
            self.CGContextFillPath(ctx);
        }
    }

    pub fn strokeRoundRect(self: *MacBridge, ctx: ?*anyopaque, h_total: f64, x: f64, top_y: f64, w: f64, h: f64, radius: f64, line_w: f64, r: f64, g: f64, b: f64, a: f64) void {
        const cg_y = h_total - top_y - h;
        const rect = CGRect{ .origin = .{ .x = x, .y = cg_y }, .size = .{ .width = w, .height = h } };
        const rad = @min(radius, @min(w * 0.5, h * 0.5));
        if (self.CGPathCreateWithRoundedRect(rect, rad, rad, null)) |path| {
            defer self.CGPathRelease(path);
            self.CGContextSetRGBStrokeColor(ctx, r, g, b, a);
            self.CGContextSetLineWidth(ctx, line_w);
            self.CGContextBeginPath(ctx);
            self.CGContextAddPath(ctx, path);
            self.CGContextStrokePath(ctx);
        }
    }

    pub fn drawCTText(self: *MacBridge, ctx: ?*anyopaque, h_total: f64, x: f64, top_y: f64, text: []const u8, dict: ?*anyopaque, r: f64, g: f64, b: f64, a: f64) void {
        if (text.len == 0) return;
        const cf_str = self.CFStringCreateWithBytes(null, text.ptr, @intCast(text.len), 0x08000100, false) orelse return;
        defer self.CFRelease(cf_str);
        const attr_str = self.CFAttributedStringCreate(null, cf_str, dict) orelse return;
        defer self.CFRelease(attr_str);
        const line = self.CTLineCreateWithAttributedString(attr_str) orelse return;
        defer self.CFRelease(line);

        self.CGContextSetRGBFillColor(ctx, r, g, b, a);
        self.CGContextSetTextPosition(ctx, x, h_total - top_y - 11.0);
        self.CTLineDraw(line, ctx);
    }

    pub fn drawCTFmt(self: *MacBridge, ctx: ?*anyopaque, h_total: f64, x: f64, top_y: f64, dict: ?*anyopaque, r: f64, g: f64, b: f64, a: f64, comptime fmt: []const u8, args: anytype) void {
        var buf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
        self.drawCTText(ctx, h_total, x, top_y, s, dict, r, g, b, a);
    }

    pub fn drawButtonPill(self: *MacBridge, ctx: ?*anyopaque, h_total: f64, x: f64, top_y: f64, w: f64, h: f64, label: []const u8, active: bool) void {
        if (active) {
            self.fillRoundRect(ctx, POPOVER_W, h_total, x, top_y, w, h, 6.0, 0.04, 0.52, 1.0, 0.92);
            self.drawCTText(ctx, h_total, x + 8.0, top_y + 3.0, label, self.dict_small, 1.0, 1.0, 1.0, 1.0);
        } else {
            self.fillRoundRect(ctx, POPOVER_W, h_total, x, top_y, w, h, 6.0, 0.22, 0.22, 0.27, 0.95);
            self.strokeRoundRect(ctx, h_total, x, top_y, w, h, 6.0, 1.0, 0.32, 0.32, 0.38, 0.9);
            self.drawCTText(ctx, h_total, x + 8.0, top_y + 3.0, label, self.dict_small, 0.88, 0.89, 0.93, 1.0);
        }
    }

    /// Redraws the menu bar glyph (ring of Spaces + iris on the current one) when the
    /// Space count or the current Space changes. Set as a template image so macOS tints it.
    pub fn updateStatusGlyph(self: *MacBridge) void {
        const n = @max(@as(usize, 1), @min(self.obs.n_spaces, MAX_SPACES));
        const cur = @min(self.obs.active_space_idx, n - 1);
        if (n == self.glyph_n and cur == self.glyph_cur) return;
        const button = self.status_button orelse return;
        const px = self.glyph_px;

        status_glyph.render(self.glyph_alpha[0 .. px * px], px, n, cur);
        // Premultiplied black: only alpha matters for a template image.
        for (0..px * px) |i| {
            self.glyph_rgba[i * 4 + 0] = 0;
            self.glyph_rgba[i * 4 + 1] = 0;
            self.glyph_rgba[i * 4 + 2] = 0;
            self.glyph_rgba[i * 4 + 3] = self.glyph_alpha[i];
        }
        // kCGImageAlphaPremultipliedLast = 1
        const ctx = self.CGBitmapContextCreate(@ptrCast(&self.glyph_rgba), px, px, 8, px * 4, self.color_space, 1) orelse return;
        defer self.CGContextRelease(ctx);
        const cg_img = self.CGBitmapContextCreateImage(ctx) orelse return;
        defer self.CGImageRelease(cg_img);

        const alloc_img = self.msg0(self.NSImage, self.sel_registerName("alloc"));
        const ns_img = self.msgInitImage(alloc_img, self.sel_registerName("initWithCGImage:size:"), cg_img, .{ .width = self.glyph_pt, .height = self.glyph_pt }) orelse return;
        self.msgBool(ns_img, self.sel_registerName("setTemplate:"), true);
        self.msgId(button, self.sel_registerName("setImage:"), ns_img);
        self.msgVoid(ns_img, self.sel_registerName("release"));

        var tbuf: [64]u8 = undefined;
        const tip = std.fmt.bufPrintSentinel(&tbuf, "Argus \xc2\xb7 Space {d} of {d}", .{ cur + 1, n }, 0) catch "Argus";
        if (self.msgUTF8(self.NSString, self.sel_str_utf8, tip.ptr)) |tip_ns| {
            self.msgId(button, self.sel_registerName("setToolTip:"), tip_ns);
        }

        self.glyph_n = n;
        self.glyph_cur = cur;
    }

    // ========================================================================
    // PER-SPACE DESKTOP RENDERING (Each Space Window Has Its Own CALayer!)
    // ========================================================================

    pub fn renderSpaceAtIndex(self: *MacBridge, idx: usize) void {
        if (idx >= self.obs.n_spaces) return;
        self.ensureSpaceWindow(idx);
        var sp = &self.obs.spaces[idx];
        const win = sp.desktop_win orelse return;
        const layer = sp.desktop_layer orelse return;

        if (sp.mode == .passthrough) {
            if (!sp.hidden_for_passthrough) {
                self.msgFloat(win, self.sel_set_alpha, 0.0);
                sp.hidden_for_passthrough = true;
            }
            return;
        }

        if (sp.hidden_for_passthrough) {
            self.msgFloat(win, self.sel_set_alpha, 1.0);
            sp.hidden_for_passthrough = false;
            self.bindWindowToSpace(idx);
        }

        if (sp.mode == .picture) {
            if (sp.cg_image) |cg_img| {
                // Direct GPU CALayer presentation on this Space's dedicated window!
                self.msgBool(self.CATransaction, self.sel_disable_actions, true);
                self.msgId(layer, self.sel_set_contents, cg_img);
                return;
            }
        }

        if (sp.mode != .custom_shader or !sp.metal_theme) self.dropMetalTheme(idx);
        if (sp.mode != .custom_shader or sp.metal_theme) self.dropGpu(idx);
        if (sp.mode == .custom_shader and sp.metal_theme) {
            _ = self.renderSpaceMetal(idx);
            return;
        }
        if (sp.mode == .custom_shader and self.gpu_enabled and self.renderSpaceGpu(idx)) return;

        // A picture Space whose image failed to load shows the window's black background.
        if (sp.mode != .custom_shader) {
            if (sp.cg_image) |old| {
                self.msgId(layer, self.sel_set_contents, null);
                self.CGImageRelease(old);
                sp.cg_image = null;
            }
            return;
        }

        // Every animated Space presents ONLY from a buffer it owns; never fall back to a shared one.
        if (self.native_data_providers[idx] == null) return;
        _ = self.obs.renderNativeShaderForSpaceIsolated(idx, self.obs.phase_accum);

        const cg_img_opt = self.CGImageCreate(
            NATIVE_W,
            NATIVE_H,
            8,
            32,
            NATIVE_W * 4,
            self.color_space,
            5 | (4 << 12),
            self.native_data_providers[idx],
            null,
            false,
            0,
        );

        if (cg_img_opt) |cg_img| {
            self.msgBool(self.CATransaction, self.sel_disable_actions, true);
            self.msgId(layer, self.sel_set_contents, cg_img);
            if (self.frame_idx <= 1) {
                self.msgVoid(self.CATransaction, self.sel_flush);
            }
            if (sp.cg_image) |old| self.CGImageRelease(old);
            sp.cg_image = cg_img;
        }
    }

    fn dropMetalTheme(self: *MacBridge, idx: usize) void {
        if (self.mt[idx]) |*p| p.destroy();
        self.mt[idx] = null;
    }

    /// Draws a Metal-only theme into its Space's CAMetalLayer. Time advances by the real gap
    /// since the Space's last frame, so warm (10 FPS) neighbors animate at the right speed.
    fn renderSpaceMetal(self: *MacBridge, idx: usize) bool {
        const sp = &self.obs.spaces[idx];
        if (self.mt[idx]) |*p| {
            const host = self.msg0(p.layer, self.sel_registerName("superlayer"));
            if (p.gen != sp.dylib_gen or host != sp.desktop_layer) self.dropMetalTheme(idx);
        }
        if (self.mt[idx] == null) {
            var buf: [131072]u8 = undefined;
            const src = std.Io.Dir.cwd().readFile(g_io, sp.getPath(), &buf) catch return false;
            const seed: u32 = @truncate(std.hash.Wyhash.hash(sp.space_id, sp.getPath()));
            self.mt[idx] = gpu.ThemePresenter.create(src, sp.getLabel(), sp.dylib_gen, seed, sp.desktop_layer, self.color_space, NATIVE_W, NATIVE_H) orelse return false;
            self.mt_last_tick[idx] = self.frame_idx;
        }
        const ticks = self.frame_idx -| self.mt_last_tick[idx];
        self.mt_last_tick[idx] = self.frame_idx;
        const dt = std.math.clamp(@as(f32, @floatFromInt(ticks)) / 30.0, 1.0 / 30.0, 0.5);
        return self.mt[idx].?.render(dt);
    }

    fn dropGpu(self: *MacBridge, idx: usize) void {
        if (self.gpu[idx]) |*p| p.destroy();
        self.gpu[idx] = null;
    }

    /// Steps the theme on the CPU and shades it on the GPU into the Space's CAMetalLayer.
    /// False when the theme has no GPU port (the caller falls back to the CPU path).
    fn renderSpaceGpu(self: *MacBridge, idx: usize) bool {
        const sp = &self.obs.spaces[idx];
        if (self.gpu[idx]) |*p| {
            const host = self.msg0(p.layer, self.sel_registerName("superlayer"));
            if (p.handle != sp.dylib_handle or host != sp.desktop_layer) self.dropGpu(idx);
        }
        if (self.gpu[idx] == null) {
            if (self.gpu_tried[idx] == sp.dylib_handle) return false; // not a GPU build: don't retry every frame
            self.gpu_tried[idx] = sp.dylib_handle;
            self.gpu[idx] = gpu.Presenter.create(sp.dylib_handle, sp.theme_state, sp.desktop_layer, self.color_space, NATIVE_W, NATIVE_H) orelse return false;
        }
        self.obs.stepSpace(idx);
        return self.gpu[idx].?.render();
    }

    /// True while the login window / lock screen covers the session (CGSSessionScreenIsLocked).
    pub fn isScreenLocked(self: *MacBridge) bool {
        const dict = self.CGSessionCopyCurrentDictionary() orelse return false;
        defer self.CFRelease(dict);
        const v = self.CFDictionaryGetValue(dict, self.cf_key_screen_locked) orelse return false;
        return @intFromPtr(v) == @intFromPtr(self.cf_true);
    }

    /// True when any part of the Space's window is on screen (NSWindowOcclusionStateVisible).
    /// A neighbor's window turns visible as soon as a swipe starts dragging it in.
    pub fn spaceWindowVisible(self: *MacBridge, idx: usize) bool {
        const win = self.obs.spaces[idx].desktop_win orelse return false;
        const state: usize = @bitCast(self.msgRetInt(win, self.sel_occlusion_state));
        return (state & (1 << 1)) != 0;
    }

    /// Renders a Space if it is on screen, or if it is a warm neighbor whose last frame is
    /// `warm_ticks` old. Returns true when it rendered.
    fn renderIfDue(self: *MacBridge, idx: usize, warm_ticks: usize) bool {
        const visible = self.spaceWindowVisible(idx);
        if (visible) self.perf_visible |= @as(u16, 1) << @intCast(idx);
        const last = self.last_render_tick[idx];
        const due = visible or (warm_ticks != 0 and (last == 0 or self.frame_idx + 1 >= last + warm_ticks));
        if (!due) return false;
        self.renderSpaceAtIndex(idx);
        self.last_render_tick[idx] = self.frame_idx + 1;
        self.perf_renders[idx] +|= 1;
        return true;
    }

    pub fn renderAllSpaces(self: *MacBridge) void {
        for (0..self.obs.n_spaces) |idx| {
            self.renderSpaceAtIndex(idx);
        }
    }

    pub fn renderActiveDesktopSpace(self: *MacBridge) void {
        self.renderSpaceAtIndex(self.obs.active_space_idx);
    }

    // ========================================================================
    // @2X RETINA BARE-TEXTURE PANORAMA POPOVER (No Glass/Blur/Sheen Effects)
    // ========================================================================

    pub fn panoramaSlotIndex(self: *const MacBridge, x: f64, top_y: f64) ?usize {
        if (top_y < 30.0 or top_y > 92.0) return null;
        const visible = @max(@as(usize, 1), @min(self.obs.n_spaces, MAX_SPACES));
        const W: f64 = @floatFromInt(POPOVER_W);
        const pad_x: f64 = 16.0;
        const usable_w = W - pad_x * 2.0;
        if (x < pad_x or x >= W - pad_x) return null;
        const slot_step = usable_w / @as(f64, @floatFromInt(visible));
        const raw_idx: usize = @intFromFloat(@max(0.0, (x - pad_x) / slot_step));
        return @min(visible - 1, raw_idx);
    }

    pub fn renderStatsPopover(self: *MacBridge) void {
        const ctx = self.popover_bitmap_ctx;
        const W: f64 = @floatFromInt(POPOVER_W);
        const H: f64 = @floatFromInt(POPOVER_H);
        const scale_f: f64 = @floatFromInt(POPOVER_SCALE);

        // Scale the CoreGraphics CTM by 2.0x so all textures & CoreText glyphs rasterize at native Retina resolution!
        self.CGContextSaveGState(ctx);
        defer self.CGContextRestoreGState(ctx);
        self.CGContextScaleCTM(ctx, scale_f, scale_f);

        self.CGContextClearRect(ctx, CGRect{ .origin = .{ .x = 0.0, .y = 0.0 }, .size = .{ .width = W, .height = H } });

        // Flat, effect-free dark matte bar (#16161A)
        self.fillRoundRect(ctx, W, H, 1.0, 1.0, W - 2.0, H - 2.0, 16.0, 0.086, 0.086, 0.102, 1.0);

        // 1. Bare Top Header Bar (y = 10..28):
        //    - Left: Bare 3-bar icon (clicking opens the themes/ folder next to Argus.app in Finder)
        //    - Center: "Argus"
        //    - Right: Bare "Quit" label
        self.fillRoundRect(ctx, W, H, 20.0, 16.0, 3.5, 7.0, 1.0, 0.85, 0.87, 0.92, 1.0);
        self.fillRoundRect(ctx, W, H, 25.5, 11.0, 3.5, 12.0, 1.0, 0.85, 0.87, 0.92, 1.0);
        self.fillRoundRect(ctx, W, H, 31.0, 14.0, 3.5, 9.0, 1.0, 0.85, 0.87, 0.92, 1.0);

        self.drawCTText(ctx, H, W * 0.5 - 20.0, 10.5, "Argus", self.dict_title, 0.96, 0.96, 0.98, 1.0);
        self.drawCTText(ctx, H, W - 44.0, 11.5, "Quit", self.dict_small, 0.62, 0.64, 0.70, 1.0);

        // 2. Horizontal Bare-Texture Panorama Strip (Spaces I..VIII)
        const visible = @max(@as(usize, 1), @min(self.obs.n_spaces, MAX_SPACES));
        const pad_x: f64 = 16.0;
        const gap: f64 = 8.0;
        const usable_w = W - pad_x * 2.0;
        const slot_step = usable_w / @as(f64, @floatFromInt(visible));
        const thumb_w = @max(28.0, slot_step - gap);
        const thumb_h: f64 = 50.0;
        const thumb_y: f64 = 34.0;

        for (0..visible) |idx| {
            const sp = &self.obs.spaces[idx];
            const sx = pad_x + @as(f64, @floatFromInt(idx)) * slot_step + gap * 0.5;
            const is_active = (idx == self.obs.active_space_idx);
            const is_drag_hover = (self.obs.drag_hover_idx != null and self.obs.drag_hover_idx.? == idx);

            // Bare 16:10 Texture Frame (actual CGImage texture, zero sheen/blur overlays)
            self.drawSpaceThumbnail(ctx, H, sx, thumb_y, thumb_w, thumb_h, sp);

            if (is_drag_hover) {
                self.strokeRoundRect(ctx, H, sx - 1.0, thumb_y - 1.0, thumb_w + 2.0, thumb_h + 2.0, 5.0, 1.5, 1.0, 1.0, 1.0, 1.0);
            } else if (is_active) {
                self.strokeRoundRect(ctx, H, sx - 1.0, thumb_y - 1.0, thumb_w + 2.0, thumb_h + 2.0, 5.0, 1.2, 0.92, 0.94, 0.98, 0.95);
            }

            // Bare Roman Numeral (I..VIII) in the top-left corner inside the frame (no box, no effects)
            const roman = romanNumeral(sp.index_1based);
            const rx = sx + 5.5;
            const ry = thumb_y + 4.0;

            if (is_active) {
                self.drawCTText(ctx, H, rx, ry, roman, self.dict_small, 1.0, 1.0, 1.0, 1.0);
            } else {
                self.drawCTText(ctx, H, rx, ry, roman, self.dict_small, 0.78, 0.80, 0.86, 0.92);
            }
        }
    }

    fn drawSpaceThumbnail(self: *MacBridge, ctx: ?*anyopaque, h_total: f64, x: f64, top_y: f64, w: f64, h: f64, sp: *const SpaceConfig) void {
        if (sp.cg_image) |cg_img| {
            // Draw the actual bare rendered CGImage texture for this Space (theme or Picture)
            const cg_y = h_total - top_y - h;
            const rect = CGRect{ .origin = .{ .x = x, .y = cg_y }, .size = .{ .width = w, .height = h } };
            self.CGContextSaveGState(ctx);
            if (self.CGPathCreateWithRoundedRect(rect, 4.5, 4.5, null)) |path| {
                self.CGContextAddPath(ctx, path);
                self.CGContextClip(ctx);
                self.CGPathRelease(path);
            }
            self.CGContextDrawImage(ctx, rect, cg_img);
            self.CGContextRestoreGState(ctx);
        } else {
            // Bare flat dark tile when Space is passthrough (macOS Default)
            self.fillRoundRect(ctx, POPOVER_W, h_total, x, top_y, w, h, 4.5, 0.13, 0.14, 0.17, 1.0);
        }
    }

    pub fn flushPopoverLayer(self: *MacBridge) void {
        self.renderStatsPopover();
        if (self.CGBitmapContextCreateImage(self.popover_bitmap_ctx)) |cg_img| {
            self.msgId(self.popover_layer, self.sel_set_contents, cg_img);
            self.msgVoid(self.CATransaction, self.sel_flush);
            self.CGImageRelease(cg_img);
        }
    }

    pub fn openThemesFolder(_: *MacBridge) void {
        _ = std.process.spawn(g_io, .{
            .argv = &[_][]const u8{ "/usr/bin/open", "themes" },
        }) catch {};
    }

    // ========================================================================
    // ASSIGN THEME, PICTURE OR CODE TO A SPECIFIC MACOS DESKTOP SPACE
    // ========================================================================

    pub fn applyThemeModeToSpace(self: *MacBridge, space_idx: usize, mode: SpaceMode) void {
        if (space_idx >= self.obs.n_spaces) return;
        var sp = &self.obs.spaces[space_idx];
        if (mode == .passthrough) {
            if (sp.cg_image) |old| {
                self.CGImageRelease(old);
                sp.cg_image = null;
            }
        }
        sp.mode = mode;
        sp.setLabel(mode.label());
        self.renderSpaceAtIndex(space_idx);
        self.bindWindowToSpace(space_idx);
        self.saveStateToDisk();
    }

    pub fn saveStateToDisk(self: *const MacBridge) void {
        var buf: [16384]u8 = undefined;
        const data = self.obs.serializeStateConfig(&buf);
        std.Io.Dir.cwd().writeFile(g_io, .{
            .sub_path = DEFAULT_STATE_PATH,
            .data = data,
        }) catch {};
    }

    pub fn loadStateFromDisk(self: *MacBridge) bool {
        var buf: [16384]u8 = undefined;
        const content = std.Io.Dir.cwd().readFile(g_io, DEFAULT_STATE_PATH, &buf) catch return false;
        if (content.len == 0) return false;

        var loaded_any = false;
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trimEnd(u8, raw_line, "\r");
            if (line.len == 0) continue;
            var cols = std.mem.splitScalar(u8, line, '\t');
            const idx_str = cols.next() orelse continue;
            const mode_str = cols.next() orelse continue;
            const label_str = cols.next() orelse "";
            const path_str = cols.next() orelse "";
            const sid_str = cols.next() orelse "";

            const parsed_idx = std.fmt.parseInt(usize, idx_str, 10) catch continue;
            const saved_sid = if (sid_str.len > 0) (std.fmt.parseInt(u64, sid_str, 10) catch 0) else 0;
            var idx: usize = parsed_idx;
            if (saved_sid > 0) {
                for (0..self.obs.n_spaces) |s_i| {
                    if (self.obs.spaces[s_i].space_id == saved_sid) {
                        idx = s_i;
                        break;
                    }
                }
            }
            if (idx >= self.obs.n_spaces) continue;
            const mode = SpaceMode.fromModeName(mode_str) orelse continue;

            var sp = &self.obs.spaces[idx];
            switch (mode) {
                .picture => {
                    if (path_str.len > 0 and !isImagePath(path_str) and self.loadCodeFileIntoSpaceInternal(idx, path_str, false)) {
                        loaded_any = true;
                    } else if (path_str.len > 0 and self.loadImageIntoSpaceInternal(idx, path_str, false)) {
                        loaded_any = true;
                    } else {
                        sp.mode = .passthrough;
                    }
                },
                .custom_shader => {
                    if (path_str.len > 0 and self.loadCodeFileIntoSpaceInternal(idx, path_str, false)) {
                        loaded_any = true;
                    } else {
                        sp.mode = .passthrough;
                    }
                },
                .passthrough => {
                    sp.mode = mode;
                    sp.setLabel(if (label_str.len > 0) label_str else mode.label());
                    sp.setPath(path_str);
                    loaded_any = true;
                },
            }
        }
        return loaded_any;
    }

    pub fn hotReloadModifiedShaders(self: *MacBridge) void {
        for (0..self.obs.n_spaces) |idx| {
            var sp = &self.obs.spaces[idx];
            const p = sp.getPath();
            if (p.len == 0) continue;
            if (sp.mode == .custom_shader) {
                if (std.Io.Dir.cwd().statFile(g_io, p, .{})) |st| {
                    if (st.mtime.nanoseconds != sp.last_mtime) {
                        sp.last_mtime = st.mtime.nanoseconds;
                        if (self.obs.loadShaderIntoSpace(idx, p)) {
                            self.renderSpaceAtIndex(idx);
                            self.saveStateToDisk();
                        }
                    }
                } else |_| {}
            }
        }
    }

    pub fn isImagePath(path: []const u8) bool {
        if (path.len == 0) return false;
        const ext = std.Io.Dir.path.extension(path);
        return std.ascii.eqlIgnoreCase(ext, ".png") or
            std.ascii.eqlIgnoreCase(ext, ".jpg") or
            std.ascii.eqlIgnoreCase(ext, ".jpeg") or
            std.ascii.eqlIgnoreCase(ext, ".heic") or
            std.ascii.eqlIgnoreCase(ext, ".webp") or
            std.ascii.eqlIgnoreCase(ext, ".gif") or
            std.ascii.eqlIgnoreCase(ext, ".bmp") or
            std.ascii.eqlIgnoreCase(ext, ".tiff") or
            std.ascii.eqlIgnoreCase(ext, ".img");
    }

    pub fn assignFileToSpace(self: *MacBridge, space_idx: usize, path: []const u8) bool {
        if (space_idx >= self.obs.n_spaces) return false;
        if (isImagePath(path)) {
            return self.loadImageIntoSpace(space_idx, path);
        } else {
            return self.loadCodeFileIntoSpace(space_idx, path);
        }
    }

    pub fn bakeCGImageCover(self: *MacBridge, raw_img: ?*anyopaque) ?*anyopaque {
        const w_px = self.CGImageGetWidth(raw_img);
        const h_px = self.CGImageGetHeight(raw_img);
        if (w_px == 0 or h_px == 0) return null;

        // Bake at @2x Retina resolution (1920x1200) so wallpapers and thumbnails are razor-sharp
        const bake_w: usize = NATIVE_W;
        const bake_h: usize = NATIVE_H;
        const ctx = self.CGBitmapContextCreate(
            null,
            bake_w,
            bake_h,
            8,
            bake_w * 4,
            self.color_space,
            1 | (4 << 12),
        ) orelse return null;
        defer self.CGContextRelease(ctx);

        const W: f64 = @floatFromInt(bake_w);
        const H: f64 = @floatFromInt(bake_h);
        const img_w: f64 = @floatFromInt(w_px);
        const img_h: f64 = @floatFromInt(h_px);

        self.CGContextClearRect(ctx, CGRect{ .origin = .{ .x = 0.0, .y = 0.0 }, .size = .{ .width = W, .height = H } });

        // Aspect-fill ("cover") scaling so any image fills the 16:10 display cleanly without stretching
        const scale = @max(W / img_w, H / img_h);
        const draw_w = img_w * scale;
        const draw_h = img_h * scale;
        const draw_x = (W - draw_w) * 0.5;
        const draw_y = (H - draw_h) * 0.5;

        self.CGContextDrawImage(
            ctx,
            CGRect{
                .origin = .{ .x = draw_x, .y = draw_y },
                .size = .{ .width = draw_w, .height = draw_h },
            },
            raw_img,
        );
        return self.CGBitmapContextCreateImage(ctx);
    }

    pub fn loadImageIntoSpace(self: *MacBridge, space_idx: usize, path: []const u8) bool {
        return self.loadImageIntoSpaceInternal(space_idx, path, true);
    }

    pub fn loadImageIntoSpaceInternal(self: *MacBridge, space_idx: usize, path: []const u8, save_state: bool) bool {
        if (space_idx >= self.obs.n_spaces) return false;
        const cf_url = self.CFURLCreateFromFileSystemRepresentation(null, path.ptr, @intCast(path.len), false) orelse return false;
        defer self.CFRelease(cf_url);

        const img_src = self.CGImageSourceCreateWithURL(cf_url, null) orelse return false;
        defer self.CFRelease(img_src);

        const raw_img = self.CGImageSourceCreateImageAtIndex(img_src, 0, null) orelse return false;
        defer self.CGImageRelease(raw_img);

        // Eagerly decode and rasterize into a standalone 32-bit RGBA CGImage while img_src is alive
        const baked_img = self.bakeCGImageCover(raw_img) orelse return false;

        var sp = &self.obs.spaces[space_idx];
        if (sp.cg_image) |old| self.CGImageRelease(old);
        sp.cg_image = baked_img;
        sp.mode = .picture;
        sp.setPath(path);
        sp.setLabel(std.Io.Dir.path.basename(path));

        self.renderSpaceAtIndex(space_idx);
        self.bindWindowToSpace(space_idx);
        if (save_state) self.saveStateToDisk();
        return true;
    }

    pub fn loadImageDataIntoSpace(self: *MacBridge, space_idx: usize, ns_data: ?*anyopaque, label: []const u8) bool {
        if (space_idx >= self.obs.n_spaces or ns_data == null) return false;
        const img_src = self.CGImageSourceCreateWithData(ns_data, null) orelse return false;
        defer self.CFRelease(img_src);

        const raw_img = self.CGImageSourceCreateImageAtIndex(img_src, 0, null) orelse return false;
        defer self.CGImageRelease(raw_img);

        const baked_img = self.bakeCGImageCover(raw_img) orelse return false;

        var sp = &self.obs.spaces[space_idx];
        if (sp.cg_image) |old| self.CGImageRelease(old);
        sp.cg_image = baked_img;
        sp.mode = .picture;
        sp.setLabel(label);

        // Persist raw dropped NSData bytes on disk so browser-dropped images survive app restarts!
        var drop_path_buf: [256]u8 = undefined;
        const drop_path = std.fmt.bufPrint(&drop_path_buf, ".argus_dropped_space_{d}.img", .{space_idx}) catch label;
        const bytes_ptr = self.msg0(ns_data, self.sel_registerName("bytes"));
        const bytes_len = self.msgRetInt(ns_data, self.sel_registerName("length"));
        if (bytes_ptr != null and bytes_len > 0) {
            const slice: [*]const u8 = @ptrCast(bytes_ptr.?);
            if (std.Io.Dir.cwd().writeFile(g_io, .{
                .sub_path = drop_path,
                .data = slice[0..@intCast(bytes_len)],
            })) |_| {
                sp.setPath(drop_path);
            } else |_| {
                sp.setPath(label);
            }
        } else {
            sp.setPath(label);
        }

        self.renderSpaceAtIndex(space_idx);
        self.bindWindowToSpace(space_idx);
        self.saveStateToDisk();
        return true;
    }

    pub fn loadCodeFileIntoSpace(self: *MacBridge, space_idx: usize, path: []const u8) bool {
        return self.loadCodeFileIntoSpaceInternal(space_idx, path, true);
    }

    pub fn loadCodeFileIntoSpaceInternal(self: *MacBridge, space_idx: usize, path: []const u8, save_state: bool) bool {
        var buf: [131072]u8 = undefined;
        const content = std.Io.Dir.cwd().readFile(g_io, path, &buf) catch return false;
        if (content.len == 0) return false;

        // Live Hot-Compilable Custom .zig Shader (`sdk.exportTheme` or `export fn argus_render_theme`),
        // or a Metal-only theme (`.metal` with `kernel void argus_draw`)
        if ((std.mem.endsWith(u8, path, ".metal") and std.mem.indexOf(u8, content, "argus_draw") != null) or
            std.mem.indexOf(u8, content, "argus_render_theme") != null or
            std.mem.indexOf(u8, content, "exportTheme") != null or
            std.mem.indexOf(u8, content, "argus_theme_init") != null or
            std.mem.indexOf(u8, content, "argus_theme_sdk.zig") != null or
            std.mem.indexOf(u8, content, "@argus-theme: custom_shader") != null)
        {
            if (self.obs.loadShaderIntoSpace(space_idx, path)) {
                self.renderSpaceAtIndex(space_idx);
                self.bindWindowToSpace(space_idx);
                if (save_state) self.saveStateToDisk();
                return true;
            }
        }

        // Not an Argus SDK theme (or it failed to compile/verify): leave the Space as it was.
        return false;
    }

    pub fn promptOpenFile(self: *MacBridge, out_buf: *[1024]u8) ?[]const u8 {
        const NSOpenPanel = self.objc_getClass("NSOpenPanel") orelse return null;
        const panel = self.msg0(NSOpenPanel, self.sel_registerName("openPanel")) orelse return null;
        self.msgBool(panel, self.sel_registerName("setCanChooseFiles:"), true);
        self.msgBool(panel, self.sel_registerName("setCanChooseDirectories:"), false);
        self.msgBool(panel, self.sel_registerName("setAllowsMultipleSelection:"), false);

        // Temporarily hide the level-101 popover so it never blocks the modal NSOpenPanel
        const was_visible = self.popover_visible;
        if (was_visible) {
            self.msgId(self.popover_win, self.sel_registerName("orderOut:"), null);
        }
        self.msgBool(self.ns_app, self.sel_registerName("activateIgnoringOtherApps:"), true);

        const resp = self.msgRetInt(panel, self.sel_registerName("runModal"));

        if (was_visible) {
            self.msgId(self.popover_win, self.sel_registerName("makeKeyAndOrderFront:"), null);
            self.msgId(self.popover_win, self.sel_registerName("orderFrontRegardless"), null);
        }
        if (resp != 1) return null;

        const url = self.msg0(panel, self.sel_registerName("URL")) orelse return null;
        const path_ns = self.msg0(url, self.sel_registerName("path")) orelse return null;
        const cstr = self.msgRetCStr(path_ns, self.sel_registerName("UTF8String")) orelse return null;
        const slice = std.mem.span(cstr);
        const n = @min(out_buf.len, slice.len);
        @memcpy(out_buf[0..n], slice[0..n]);
        return out_buf[0..n];
    }
};

var g_bridge: ?*MacBridge = null;

fn onAcceptsFirstMouse(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) bool {
    return true;
}

fn onPrepareForDragOperation(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) bool {
    return true;
}

fn onDraggingEntered(_: ?*anyopaque, _: ?*anyopaque, sender: ?*anyopaque) callconv(.c) usize {
    const b = g_bridge orelse return 0;
    const loc = b.msgRetPoint(sender, b.sel_registerName("draggingLocation"));
    const top_y = (@as(f64, @floatFromInt(POPOVER_H)) - 1.0) - loc.y;
    b.obs.drag_hover_idx = b.panoramaSlotIndex(loc.x, top_y) orelse b.obs.active_space_idx;
    b.flushPopoverLayer();
    return 1; // NSDragOperationCopy
}

fn onDraggingUpdated(self_obj: ?*anyopaque, cmd_sel: ?*anyopaque, sender: ?*anyopaque) callconv(.c) usize {
    return onDraggingEntered(self_obj, cmd_sel, sender);
}

fn onDraggingExited(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const b = g_bridge orelse return;
    b.obs.drag_hover_idx = null;
    b.flushPopoverLayer();
}

fn onPerformDragOperation(_: ?*anyopaque, _: ?*anyopaque, sender: ?*anyopaque) callconv(.c) bool {
    const b = g_bridge orelse return false;
    const loc = b.msgRetPoint(sender, b.sel_registerName("draggingLocation"));
    const top_y = (@as(f64, @floatFromInt(POPOVER_H)) - 1.0) - loc.y;

    var target_idx: usize = b.obs.active_space_idx;
    if (b.obs.drag_hover_idx) |hover_idx| {
        target_idx = hover_idx;
    } else if (b.panoramaSlotIndex(loc.x, top_y)) |slot_idx| {
        target_idx = slot_idx;
    }
    b.obs.drag_hover_idx = null;

    const pboard = b.msg0(sender, b.sel_registerName("draggingPasteboard")) orelse return false;
    var ok = false;

    // 1. Modern macOS Finder / Desktop / Photos file URL pasteboard item (`public.file-url`)
    if (b.NSURL) |NSURL_cls| {
        if (b.msgIdRetId(NSURL_cls, b.sel_registerName("URLFromPasteboard:"), pboard)) |ns_url| {
            if (b.msg0(ns_url, b.sel_registerName("path"))) |path_ns| {
                if (b.msgRetCStr(path_ns, b.sel_registerName("UTF8String"))) |cstr| {
                    ok = b.assignFileToSpace(target_idx, std.mem.span(cstr));
                }
            }
        }
    }

    // 2. Legacy `NSFilenamesPboardType` property list fallback
    if (!ok) {
        if (b.msgUTF8(b.NSString, b.sel_str_utf8, "NSFilenamesPboardType")) |fn_type| {
            if (b.msgIdRetId(pboard, b.sel_registerName("propertyListForType:"), fn_type)) |files_arr| {
                if (b.msgUIntRetId(files_arr, b.sel_registerName("objectAtIndex:"), 0)) |first_ns| {
                    if (b.msgRetCStr(first_ns, b.sel_registerName("UTF8String"))) |cstr| {
                        ok = b.assignFileToSpace(target_idx, std.mem.span(cstr));
                    }
                }
            }
        }
    }

    // 3. Direct image data dragged from browsers, Preview, or Screenshots (`public.png` / `public.tiff`)
    if (!ok) {
        const raw_types = [_][*:0]const u8{ "public.png", "public.tiff" };
        for (raw_types) |t_cstr| {
            if (b.msgUTF8(b.NSString, b.sel_str_utf8, t_cstr)) |t_ns| {
                if (b.msgIdRetId(pboard, b.sel_registerName("dataForType:"), t_ns)) |ns_data| {
                    if (b.loadImageDataIntoSpace(target_idx, ns_data, "Dropped Image")) {
                        ok = true;
                        break;
                    }
                }
            }
        }
    }

    b.renderActiveDesktopSpace();
    b.flushPopoverLayer();
    return ok;
}

fn onStatusItemClick(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const b = g_bridge orelse return;
    b.popover_visible = !b.popover_visible;
    if (b.popover_visible) {
        b.syncSpacesFromSkyLight(false);
        b.renderAllSpaces();
        const mouse = b.msgRetPoint(b.NSEvent, b.sel_registerName("mouseLocation"));
        const pop_w: f64 = @floatFromInt(POPOVER_W);
        const pop_h: f64 = @floatFromInt(POPOVER_H);
        const px = math.clamp(mouse.x - pop_w * 0.5, 12.0, b.screen_rect.size.width - pop_w - 12.0);
        const py = b.screen_rect.size.height - 30.0 - pop_h;
        const frame = CGRect{
            .origin = .{ .x = px, .y = py },
            .size = .{ .width = pop_w, .height = pop_h },
        };
        b.msgSetFrame(b.popover_win, b.sel_registerName("setFrame:display:"), frame, true);
        b.flushPopoverLayer();
        b.msgBool(b.ns_app, b.sel_registerName("activateIgnoringOtherApps:"), true);
        b.msgId(b.popover_win, b.sel_registerName("makeKeyAndOrderFront:"), null);
        b.msgId(b.popover_win, b.sel_registerName("orderFrontRegardless"), null);
    } else {
        b.msgId(b.popover_win, b.sel_registerName("orderOut:"), null);
    }
}

fn onPopoverMouseDown(_: ?*anyopaque, _: ?*anyopaque, event: ?*anyopaque) callconv(.c) void {
    const b = g_bridge orelse return;
    const loc = b.msgRetPoint(event, b.sel_registerName("locationInWindow"));
    const x = loc.x;
    const y = (@as(f64, @floatFromInt(POPOVER_H)) - 1.0) - loc.y;
    const W: f64 = @floatFromInt(POPOVER_W);
    if (x < 0.0 or y < 0.0 or x >= W or y >= @as(f64, @floatFromInt(POPOVER_H))) return;

    // 1. Header Bar (y = 8..35):
    //    - Top-left 3-bar icon (x = 10..64): opens the themes/ folder next to Argus.app in Finder!
    //    - Top-right "Quit" (x = W - 60..W): exits Argus
    if (y >= 6.0 and y <= 35.0) {
        if (x >= 10.0 and x <= 64.0) {
            b.openThemesFolder();
        } else if (x >= W - 64.0 and x <= W) {
            std.process.exit(0);
        }
    }
    // 2. Horizontal Panorama Viewports (Spaces I..VIII side-by-side):
    //    Clicking any Space viewport cycles its theme and persists to disk
    else if (b.panoramaSlotIndex(x, y)) |idx| {
        if (idx < b.obs.n_spaces) {
            var sp = &b.obs.spaces[idx];
            sp.mode = sp.mode.next();
            if (sp.mode == .custom_shader and sp.custom_render_fn == null and sp.theme_draw_fn == null) {
                sp.mode = sp.mode.next();
            }
            if (sp.mode == .picture and (!MacBridge.isImagePath(sp.getPath()) or sp.cg_image == null)) {
                sp.mode = .passthrough;
            }
            if (sp.mode == .passthrough) {
                if (sp.cg_image) |old| {
                    b.CGImageRelease(old);
                    sp.cg_image = null;
                }
            }
            sp.setLabel(sp.mode.label());
            b.renderSpaceAtIndex(idx);
            b.bindWindowToSpace(idx);
            b.saveStateToDisk();
        }
    }

    b.renderActiveDesktopSpace();
    b.flushPopoverLayer();
}

fn onPopoverMouseDragged(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {}

fn onPopoverMouseUp(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {}

/// Off-screen neighbors re-render every 3rd 30 Hz tick (~10 FPS).
const NEIGHBOR_WARM_TICKS: usize = 3;

/// Compiles a `.metal` theme to check it before it replaces a Space's current theme.
fn validateMetalTheme(src: []const u8, label: []const u8) bool {
    var err_buf: [2048]u8 = undefined;
    var t = metal_theme.Theme.compile(src, label, @intCast(NATIVE_W), @intCast(NATIVE_H), 0, &err_buf) catch {
        std.debug.print("argus: {s} not loaded: {s}\n", .{ label, std.mem.sliceTo(&err_buf, 0) });
        return false;
    };
    t.deinit();
    return true;
}

fn isAnimatedSpaceMode(m: SpaceMode) bool {
    return m == .custom_shader;
}

fn onTick(_: ?*anyopaque, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    const b = g_bridge orelse return;
    if (b.max_frames != 0 and b.frame_idx >= b.max_frames) {
        std.process.exit(0);
    }
    // Pause completely (0% CPU) when display is asleep or lid is closed
    if (b.frame_idx > 5 and b.CGDisplayIsAsleep(b.display_id) != 0) {
        return;
    }

    // Re-assert per-Space window bindings once after NSRunLoop startup flushes AppKit's deferred _orderFront
    if (b.frame_idx == 1) {
        for (0..b.obs.n_spaces) |idx| {
            b.bindWindowToSpace(idx);
        }
    }

    // Auto-detect Mission Control Space reordering, additions, or removals every 0.5s (15 ticks)
    if ((b.frame_idx % 15) == 0) {
        b.syncSpacesFromSkyLight(false);
    }

    // Once per second, check if any active .zig shader file on disk was edited and hot-reload its .dylib
    if ((b.frame_idx % 30) == 0) {
        b.hotReloadModifiedShaders();
    }

    // Track active Space ID in O(1) for the Menu Bar & Popover indicator
    const cur_space_id = b.CGSGetActiveSpace(b.cgs_conn);
    const space_changed = (cur_space_id != b.obs.active_space_id);
    if (space_changed) {
        b.handleSpaceSwitch(cur_space_id);
        if (b.popover_visible) b.flushPopoverLayer();
    }

    // Once per second: is the lock screen up? (Display sleep is handled above.)
    if ((b.frame_idx % 30) == 0) {
        b.screen_locked = b.isScreenLocked();
    }

    // Render only what can be seen. The active Space renders at 30 FPS while its window is on screen.
    // Its nearest animated left/right neighbors (scanning past passthrough / picture Spaces) stay warm
    // at ~10 FPS so a swipe never reveals a stale frame, and jump to 30 FPS the moment their window
    // turns visible mid-swipe. Nothing renders while a fullscreen app's Space is active (it is not one
    // of ours, so active_space_id no longer matches the active slot), or while the screen is locked.
    const active_idx = b.obs.active_space_idx;
    const active_is_ours = active_idx < b.obs.n_spaces and
        b.obs.spaces[active_idx].space_id == b.obs.active_space_id;
    var rendered_any = false;
    if (!b.obs.paused and active_is_ours and !b.screen_locked) {
        b.obs.phase_accum += (1.0 / 150.0) * b.obs.spin_mult;

        if (isAnimatedSpaceMode(b.obs.spaces[active_idx].mode)) {
            const t0 = std.Io.Clock.awake.now(g_io);
            // First second: render unconditionally while AppKit settles window visibility.
            if (b.renderIfDue(active_idx, if (b.frame_idx < 30) 1 else 0)) {
                const elapsed_ns: u64 = @intCast(@max(@as(i96, 0), t0.durationTo(std.Io.Clock.awake.now(g_io)).nanoseconds));
                b.obs.last_compute_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;
                rendered_any = true;
            }
        }

        var scan_l: usize = active_idx;
        while (scan_l > 0) {
            scan_l -= 1;
            if (isAnimatedSpaceMode(b.obs.spaces[scan_l].mode)) {
                if (b.renderIfDue(scan_l, NEIGHBOR_WARM_TICKS)) rendered_any = true;
                break;
            }
        }

        var scan_r: usize = active_idx + 1;
        while (scan_r < b.obs.n_spaces) : (scan_r += 1) {
            if (isAnimatedSpaceMode(b.obs.spaces[scan_r].mode)) {
                if (b.renderIfDue(scan_r, NEIGHBOR_WARM_TICKS)) rendered_any = true;
                break;
            }
        }
    } else if (!b.obs.paused and !b.screen_locked) {
        // A fullscreen app's Space is active. Our windows are normally all hidden, but Mission Control
        // opened from there shows a desktop Space behind its thumbnails: keep whatever is on screen live.
        for (0..b.obs.n_spaces) |idx| {
            if (isAnimatedSpaceMode(b.obs.spaces[idx].mode) and b.renderIfDue(idx, 0)) rendered_any = true;
        }
    }

    if (b.perf_log and (b.frame_idx % 30) == 29) {
        std.debug.print("[perf] t={d} active={d} ours={} locked={} visible=0x{x:0>2} renders/s:", .{
            b.frame_idx / 30, active_idx, active_is_ours, b.screen_locked, b.perf_visible,
        });
        for (0..b.obs.n_spaces) |idx| std.debug.print(" {d}", .{b.perf_renders[idx]});
        std.debug.print(" active_us={d:.0}\n", .{b.obs.last_compute_us});
        b.perf_renders = @splat(0);
        b.perf_visible = 0;
    }

    if (b.popover_visible and (b.frame_idx % 3) == 0) {
        b.flushPopoverLayer();
    } else if (rendered_any) {
        // Single batched CATransaction flush per tick so off-screen/incoming Space windows update live mid-swipe
        b.msgVoid(b.CATransaction, b.sel_flush);
    }

    if (space_changed or (b.frame_idx % 15) == 0) {
        b.updateStatusGlyph();
    }

    b.frame_idx += 1;
}

extern "c" fn chdir(path: [*:0]const u8) c_int;
extern "c" fn _NSGetExecutablePath(buf: [*]u8, bufsize: *u32) c_int;

pub fn main(init: std.process.Init) !void {
    g_io = init.io;
    sc.g_io = init.io;
    const alloc = std.heap.page_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    // When launched via `open Argus.app`, macOS launchd sets cwd to `/`.
    // Use `_NSGetExecutablePath` (with `args[0]` fallback) to anchor cwd to the parent folder of `Argus.app`.
    var exe_buf: [1024]u8 = undefined;
    var exe_len: u32 = @intCast(exe_buf.len);
    const exe_slice: []const u8 = if (_NSGetExecutablePath(&exe_buf, &exe_len) == 0)
        std.mem.sliceTo(&exe_buf, 0)
    else if (args.len > 0)
        args[0]
    else
        "";
    if (std.mem.indexOf(u8, exe_slice, "/Argus.app/Contents/MacOS/")) |pos| {
        if (pos > 0 and pos < 960) {
            var dir_z_buf: [1024]u8 = undefined;
            if (std.fmt.bufPrintSentinel(&dir_z_buf, "{s}", .{exe_slice[0..pos]}, 0)) |dir_z| {
                _ = chdir(dir_z.ptr);
            } else |_| {}
        }
    }

    var headless_test = false;
    var normal_window = false;
    var max_frames: usize = 0;
    var perf_log = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--verify-dylib") and i + 1 < args.len) {
            var path_z_buf: [512]u8 = undefined;
            const dylib_z = std.fmt.bufPrintSentinel(&path_z_buf, "{s}", .{args[i + 1]}, 0) catch std.process.exit(1);
            if (sc.verifyDylibSafety(dylib_z)) {
                std.process.exit(0);
            } else {
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, a, "--test-frame") or std.mem.eql(u8, a, "--headless")) {
            headless_test = true;
        } else if (std.mem.eql(u8, a, "--perf-log")) {
            perf_log = true;
        } else if (std.mem.eql(u8, a, "--gpu")) {
            sc.gpu_ports = true;
        } else if (std.mem.eql(u8, a, "--cpu")) {
            sc.gpu_ports = false;
        } else if (std.mem.eql(u8, a, "--window")) {
            normal_window = true;
        } else if (std.mem.eql(u8, a, "--frames") and i + 1 < args.len) {
            i += 1;
            max_frames = try std.fmt.parseInt(usize, args[i], 10);
        }
    }

    const obs = try Observatory.init(alloc);
    defer obs.deinit(alloc);

    if (headless_test) {
        const theme_path = "themes/Gemini_Wormhole.zig";
        const loaded = obs.loadShaderIntoSpace(0, theme_path);
        const t0 = std.Io.Clock.awake.now(g_io);
        for (0..20) |f| {
            _ = obs.renderNativeShaderForSpaceIsolated(0, @as(f64, @floatFromInt(f)) / 90.0);
        }
        const elapsed_ns: u64 = @intCast(@max(@as(i96, 0), t0.durationTo(std.Io.Clock.awake.now(g_io)).nanoseconds));
        const avg_us = (@as(f64, @floatFromInt(elapsed_ns)) / 20.0) / 1000.0;

        var buf: [1024]u8 = undefined;
        const msg = try std.fmt.bufPrint(
            &buf,
            "========================================================================\n" ++
                " ARGUS.APP MULTI-SPACE ENGINE SELF-CHECK (Zig 0.17.0)\n" ++
                "========================================================================\n" ++
                " Theme compile + verify  : {s} ({s})\n" ++
                " Avg Frame Render Time   : {d:.1} us/frame over 20 frames\n" ++
                " Struct Memory Size      : {d:.2} MiB (virtual; buffers are demand-paged)\n" ++
                "========================================================================\n",
            .{
                theme_path,
                if (loaded) "OK" else "FAILED",
                avg_us,
                @as(f64, @floatFromInt(@sizeOf(Observatory))) / (1024.0 * 1024.0),
            },
        );
        try std.Io.File.stdout().writeStreamingAll(g_io, msg);
        return;
    }

    // Dynamically load macOS system frameworks from the dyld shared cache
    const libobjc = std.c.dlopen("/usr/lib/libobjc.A.dylib", .{ .LAZY = true }) orelse return error.ObjcLoadFailed;
    const libcg = std.c.dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", .{ .LAZY = true }) orelse return error.CGLoadFailed;
    const libcf = std.c.dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", .{ .LAZY = true }) orelse return error.CFLoadFailed;
    const libct = std.c.dlopen("/System/Library/Frameworks/CoreText.framework/CoreText", .{ .LAZY = true }) orelse return error.CTLoadFailed;
    const libimageio = std.c.dlopen("/System/Library/Frameworks/ImageIO.framework/ImageIO", .{ .LAZY = true }) orelse return error.ImageIOLoadFailed;
    const libskylight = std.c.dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", .{ .LAZY = true }) orelse return error.SkyLightLoadFailed;
    _ = std.c.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", .{ .LAZY = true }) orelse return error.AppKitLoadFailed;
    _ = std.c.dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", .{ .LAZY = true }) orelse return error.QuartzLoadFailed;

    const objc_getClass: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libobjc, "objc_getClass") orelse return error.SymbolMissing));
    const sel_registerName: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libobjc, "sel_registerName") orelse return error.SymbolMissing));
    const objc_allocateClassPair: *const fn (?*anyopaque, [*:0]const u8, usize) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libobjc, "objc_allocateClassPair") orelse return error.SymbolMissing));
    const class_addMethod: *const fn (?*anyopaque, ?*anyopaque, *const anyopaque, [*:0]const u8) callconv(.c) bool = @ptrCast(@alignCast(std.c.dlsym(libobjc, "class_addMethod") orelse return error.SymbolMissing));
    const objc_registerClassPair: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libobjc, "objc_registerClassPair") orelse return error.SymbolMissing));
    const msgSend_raw: *align(4) const anyopaque = @alignCast(std.c.dlsym(libobjc, "objc_msgSend") orelse return error.SymbolMissing);

    const CGMainDisplayID: *const fn () callconv(.c) u32 = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGMainDisplayID") orelse return error.SymbolMissing));
    const CGDisplayBounds: *const fn (u32) callconv(.c) CGRect = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGDisplayBounds") orelse return error.SymbolMissing));
    const CGDisplayCopyColorSpace: *const fn (u32) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGDisplayCopyColorSpace") orelse return error.SymbolMissing));
    const CGDisplayIsAsleep: *const fn (u32) callconv(.c) u32 = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGDisplayIsAsleep") orelse return error.SymbolMissing));
    const CGSessionCopyCurrentDictionary: *const fn () callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGSessionCopyCurrentDictionary") orelse return error.SymbolMissing));
    const CGWindowLevelForKey: *const fn (i32) callconv(.c) i32 = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGWindowLevelForKey") orelse return error.SymbolMissing));
    const CGColorSpaceCreateDeviceRGB: *const fn () callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGColorSpaceCreateDeviceRGB") orelse return error.SymbolMissing));
    const CGBitmapContextCreate: *const fn (?*anyopaque, usize, usize, usize, usize, ?*anyopaque, u32) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGBitmapContextCreate") orelse return error.SymbolMissing));
    const CGBitmapContextCreateImage: *const fn (?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGBitmapContextCreateImage") orelse return error.SymbolMissing));
    const CGDataProviderCreateWithData: *const fn (?*anyopaque, ?*const anyopaque, usize, ?*const anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGDataProviderCreateWithData") orelse return error.SymbolMissing));
    const CGImageCreate: *const fn (usize, usize, usize, usize, usize, ?*anyopaque, u32, ?*anyopaque, ?*const f64, bool, i32) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGImageCreate") orelse return error.SymbolMissing));
    const CGContextDrawImage: *const fn (?*anyopaque, CGRect, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextDrawImage") orelse return error.SymbolMissing));
    const CGContextRelease: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextRelease") orelse return error.SymbolMissing));
    const CGImageRelease: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGImageRelease") orelse return error.SymbolMissing));
    const CGImageGetWidth: *const fn (?*anyopaque) callconv(.c) usize = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGImageGetWidth") orelse return error.SymbolMissing));
    const CGImageGetHeight: *const fn (?*anyopaque) callconv(.c) usize = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGImageGetHeight") orelse return error.SymbolMissing));
    const CGContextSaveGState: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextSaveGState") orelse return error.SymbolMissing));
    const CGContextRestoreGState: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextRestoreGState") orelse return error.SymbolMissing));
    const CGContextScaleCTM: *const fn (?*anyopaque, f64, f64) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextScaleCTM") orelse return error.SymbolMissing));
    const CGContextClearRect: *const fn (?*anyopaque, CGRect) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextClearRect") orelse return error.SymbolMissing));
    const CGContextSetRGBFillColor: *const fn (?*anyopaque, f64, f64, f64, f64) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextSetRGBFillColor") orelse return error.SymbolMissing));
    const CGContextSetRGBStrokeColor: *const fn (?*anyopaque, f64, f64, f64, f64) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextSetRGBStrokeColor") orelse return error.SymbolMissing));
    const CGContextSetLineWidth: *const fn (?*anyopaque, f64) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextSetLineWidth") orelse return error.SymbolMissing));
    const CGContextBeginPath: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextBeginPath") orelse return error.SymbolMissing));
    const CGContextMoveToPoint: *const fn (?*anyopaque, f64, f64) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextMoveToPoint") orelse return error.SymbolMissing));
    const CGContextAddLineToPoint: *const fn (?*anyopaque, f64, f64) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextAddLineToPoint") orelse return error.SymbolMissing));
    const CGContextClosePath: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextClosePath") orelse return error.SymbolMissing));
    const CGContextFillPath: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextFillPath") orelse return error.SymbolMissing));
    const CGContextStrokePath: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextStrokePath") orelse return error.SymbolMissing));
    const CGPathCreateWithRoundedRect: *const fn (CGRect, f64, f64, ?*const anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGPathCreateWithRoundedRect") orelse return error.SymbolMissing));
    const CGContextAddPath: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextAddPath") orelse return error.SymbolMissing));
    const CGContextClip: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextClip") orelse return error.SymbolMissing));
    const CGPathRelease: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGPathRelease") orelse return error.SymbolMissing));
    const CGContextSetTextPosition: *const fn (?*anyopaque, f64, f64) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcg, "CGContextSetTextPosition") orelse return error.SymbolMissing));

    const CFURLCreateFromFileSystemRepresentation: *const fn (?*anyopaque, [*]const u8, isize, bool) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFURLCreateFromFileSystemRepresentation") orelse return error.SymbolMissing));
    const CFRelease: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFRelease") orelse return error.SymbolMissing));
    const CFStringCreateWithCString: *const fn (?*anyopaque, [*:0]const u8, u32) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFStringCreateWithCString") orelse return error.SymbolMissing));
    const CFStringCreateWithBytes: *const fn (?*anyopaque, [*]const u8, isize, u32, bool) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFStringCreateWithBytes") orelse return error.SymbolMissing));
    const CFDictionaryCreate: *const fn (?*anyopaque, [*]?*const anyopaque, [*]?*const anyopaque, isize, ?*const anyopaque, ?*const anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFDictionaryCreate") orelse return error.SymbolMissing));
    const CFAttributedStringCreate: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFAttributedStringCreate") orelse return error.SymbolMissing));
    const CFArrayGetCount: *const fn (?*anyopaque) callconv(.c) isize = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFArrayGetCount") orelse return error.SymbolMissing));
    const CFArrayGetValueAtIndex: *const fn (?*anyopaque, isize) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFArrayGetValueAtIndex") orelse return error.SymbolMissing));
    const CFDictionaryGetValue: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFDictionaryGetValue") orelse return error.SymbolMissing));
    const CFNumberGetValue: *const fn (?*anyopaque, i32, *anyopaque) callconv(.c) bool = @ptrCast(@alignCast(std.c.dlsym(libcf, "CFNumberGetValue") orelse return error.SymbolMissing));

    const CTFontCreateWithName: *const fn (?*anyopaque, f64, ?*const anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libct, "CTFontCreateWithName") orelse return error.SymbolMissing));
    const CTLineCreateWithAttributedString: *const fn (?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libct, "CTLineCreateWithAttributedString") orelse return error.SymbolMissing));
    const CTLineDraw: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libct, "CTLineDraw") orelse return error.SymbolMissing));

    const kCTFontAttributeName_ptr: *const ?*const anyopaque = @ptrCast(@alignCast(std.c.dlsym(libct, "kCTFontAttributeName") orelse return error.SymbolMissing));
    const kCTForegroundColorFromContext_ptr: *const ?*const anyopaque = @ptrCast(@alignCast(std.c.dlsym(libct, "kCTForegroundColorFromContextAttributeName") orelse return error.SymbolMissing));
    const kCFBooleanTrue_ptr: *const ?*const anyopaque = @ptrCast(@alignCast(std.c.dlsym(libcf, "kCFBooleanTrue") orelse return error.SymbolMissing));

    const CGImageSourceCreateWithURL: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libimageio, "CGImageSourceCreateWithURL") orelse return error.SymbolMissing));
    const CGImageSourceCreateWithData: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libimageio, "CGImageSourceCreateWithData") orelse return error.SymbolMissing));
    const CGImageSourceCreateImageAtIndex: *const fn (?*anyopaque, usize, ?*anyopaque) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libimageio, "CGImageSourceCreateImageAtIndex") orelse return error.SymbolMissing));

    const CGSMainConnectionID: *const fn () callconv(.c) u32 = @ptrCast(@alignCast(std.c.dlsym(libskylight, "CGSMainConnectionID") orelse return error.SymbolMissing));
    const CGSGetActiveSpace: *const fn (u32) callconv(.c) u64 = @ptrCast(@alignCast(std.c.dlsym(libskylight, "CGSGetActiveSpace") orelse return error.SymbolMissing));
    const CGSCopyManagedDisplaySpaces: *const fn (u32) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(libskylight, "CGSCopyManagedDisplaySpaces") orelse return error.SymbolMissing));
    const CGSMoveWindowsToManagedSpace: *const fn (u32, ?*anyopaque, u64) callconv(.c) void = @ptrCast(@alignCast(std.c.dlsym(libskylight, "CGSMoveWindowsToManagedSpace") orelse return error.SymbolMissing));

    const msg0: MsgSend0 = @ptrCast(msgSend_raw);
    const msgVoid: MsgSendVoid = @ptrCast(msgSend_raw);
    const msgBool: MsgSendVoidBool = @ptrCast(msgSend_raw);
    const msgInt: MsgSendVoidInt = @ptrCast(msgSend_raw);
    const msgUInt: MsgSendVoidUInt = @ptrCast(msgSend_raw);
    const msgFloat: MsgSendVoidFloat = @ptrCast(msgSend_raw);
    const msgId: MsgSendVoidId = @ptrCast(msgSend_raw);
    const msgIdRetId: MsgSendIdRetId = @ptrCast(msgSend_raw);
    const msgUIntRetId: MsgSendUIntRetId = @ptrCast(msgSend_raw);
    const msgId2: MsgSendId2 = @ptrCast(msgSend_raw);
    const msgInitWin: MsgSendInitWin = @ptrCast(msgSend_raw);
    const msgSetFrame: MsgSendSetFrame = @ptrCast(msgSend_raw);
    const msgStatusItem: MsgSendStatusItem = @ptrCast(msgSend_raw);
    const msgUTF8: MsgSendUTF8 = @ptrCast(msgSend_raw);
    const msgTimer: MsgSendTimer = @ptrCast(msgSend_raw);
    const msgRetPoint: MsgSendRetPoint = @ptrCast(msgSend_raw);
    const msgRetRect: MsgSendRetRect = @ptrCast(msgSend_raw);
    const msgRetInt: MsgSendRetInt = @ptrCast(msgSend_raw);
    const msgRetCStr: MsgSendRetCStr = @ptrCast(msgSend_raw);
    const msgInitRect: MsgSendInitRect = @ptrCast(msgSend_raw);
    const msgInitImage: MsgSendInitImage = @ptrCast(msgSend_raw);
    const msgRetF64: MsgSendRetF64 = @ptrCast(msgSend_raw);
    const msgSetImagePosition: MsgSendVoidUInt = @ptrCast(msgSend_raw);

    // Prepare CoreText Font Attribute Dictionaries (Helvetica Neue / SF & Menlo)
    const cf_font_ui = CFStringCreateWithCString(null, "HelveticaNeue-Medium", 0x08000100);
    const cf_font_bold = CFStringCreateWithCString(null, "HelveticaNeue-Bold", 0x08000100);
    const cf_font_mono = CFStringCreateWithCString(null, "Menlo-Regular", 0x08000100);

    const ct_title = CTFontCreateWithName(cf_font_bold, 13.5, null);
    const ct_body = CTFontCreateWithName(cf_font_ui, 12.0, null);
    const ct_small = CTFontCreateWithName(cf_font_ui, 10.5, null);
    const ct_mono = CTFontCreateWithName(cf_font_mono, 11.0, null);

    var keys = [2]?*const anyopaque{ kCTFontAttributeName_ptr.*, kCTForegroundColorFromContext_ptr.* };
    var vals_title = [2]?*const anyopaque{ ct_title, kCFBooleanTrue_ptr.* };
    var vals_body = [2]?*const anyopaque{ ct_body, kCFBooleanTrue_ptr.* };
    var vals_small = [2]?*const anyopaque{ ct_small, kCFBooleanTrue_ptr.* };
    var vals_mono = [2]?*const anyopaque{ ct_mono, kCFBooleanTrue_ptr.* };

    const dict_title = CFDictionaryCreate(null, &keys, &vals_title, 2, null, null);
    const dict_body = CFDictionaryCreate(null, &keys, &vals_body, 2, null, null);
    const dict_small = CFDictionaryCreate(null, &keys, &vals_small, 2, null, null);
    const dict_mono = CFDictionaryCreate(null, &keys, &vals_mono, 2, null, null);

    // 1. Register Objective-C Controller & Drag-and-Drop Popover View Classes
    const NSObject = objc_getClass("NSObject") orelse return error.NoNSObject;
    const ctrl_cls = objc_allocateClassPair(NSObject, "ArgusStudioController", 0) orelse return error.ClassAllocFailed;
    _ = class_addMethod(ctrl_cls, sel_registerName("onTick:"), @ptrCast(&onTick), "v@:@");
    _ = class_addMethod(ctrl_cls, sel_registerName("onStatusItemClick:"), @ptrCast(&onStatusItemClick), "v@:@");
    objc_registerClassPair(ctrl_cls);
    const ctrl_instance = msg0(msg0(ctrl_cls, sel_registerName("alloc")), sel_registerName("init"));

    const NSView = objc_getClass("NSView") orelse return error.NoNSView;
    const pop_view_cls = objc_allocateClassPair(NSView, "ArgusPopoverView", 0) orelse return error.ClassAllocFailed;
    _ = class_addMethod(pop_view_cls, sel_registerName("mouseDown:"), @ptrCast(&onPopoverMouseDown), "v@:@");
    _ = class_addMethod(pop_view_cls, sel_registerName("mouseDragged:"), @ptrCast(&onPopoverMouseDragged), "v@:@");
    _ = class_addMethod(pop_view_cls, sel_registerName("mouseUp:"), @ptrCast(&onPopoverMouseUp), "v@:@");
    _ = class_addMethod(pop_view_cls, sel_registerName("acceptsFirstMouse:"), @ptrCast(&onAcceptsFirstMouse), "B@:@");
    _ = class_addMethod(pop_view_cls, sel_registerName("draggingEntered:"), @ptrCast(&onDraggingEntered), "Q@:@");
    _ = class_addMethod(pop_view_cls, sel_registerName("draggingUpdated:"), @ptrCast(&onDraggingUpdated), "Q@:@");
    _ = class_addMethod(pop_view_cls, sel_registerName("draggingExited:"), @ptrCast(&onDraggingExited), "v@:@");
    _ = class_addMethod(pop_view_cls, sel_registerName("prepareForDragOperation:"), @ptrCast(&onPrepareForDragOperation), "B@:@");
    _ = class_addMethod(pop_view_cls, sel_registerName("performDragOperation:"), @ptrCast(&onPerformDragOperation), "B@:@");
    objc_registerClassPair(pop_view_cls);

    // 2. Initialize NSApplication as Menu-Bar Accessory
    const NSApplication = objc_getClass("NSApplication") orelse return error.NoNSApp;
    const ns_app = msg0(NSApplication, sel_registerName("sharedApplication"));
    msgInt(ns_app, sel_registerName("setActivationPolicy:"), if (normal_window) 0 else 1);
    msgVoid(ns_app, sel_registerName("finishLaunching"));

    // 3. Display Geometry & Classes for Per-Space NSWindows
    const display_id = CGMainDisplayID();
    const screen_rect = CGDisplayBounds(display_id);
    const desktop_level: isize = @intCast(CGWindowLevelForKey(2) + 1);
    const NSWindow = objc_getClass("NSWindow") orelse return error.NoNSWindow;
    const NSNumber = objc_getClass("NSNumber") orelse return error.NoNSNumber;
    const NSURL = objc_getClass("NSURL");

    // 4. Create @2x Retina Rounded Popover Window (360x442 logical points -> 720x884 Retina pixels)
    const pop_rect = CGRect{
        .origin = .{ .x = screen_rect.size.width - 390.0, .y = screen_rect.size.height - 472.0 },
        .size = .{ .width = @floatFromInt(POPOVER_W), .height = @floatFromInt(POPOVER_H) },
    };
    const popover_win = msgInitWin(
        msg0(NSWindow, sel_registerName("alloc")),
        sel_registerName("initWithContentRect:styleMask:backing:defer:"),
        pop_rect,
        0,
        2,
        false,
    );
    msgInt(popover_win, sel_registerName("setLevel:"), 101);
    msgUInt(popover_win, sel_registerName("setCollectionBehavior:"), (1 << 0) | (1 << 3) | (1 << 6) | (1 << 8));
    msgBool(popover_win, sel_registerName("setHidesOnDeactivate:"), false);
    msgBool(popover_win, sel_registerName("setOpaque:"), false);
    if (objc_getClass("NSColor")) |NSColor| {
        if (msg0(NSColor, sel_registerName("clearColor"))) |clear_col| {
            msgId(popover_win, sel_registerName("setBackgroundColor:"), clear_col);
        }
    }
    msgBool(popover_win, sel_registerName("setHasShadow:"), true);

    const pop_view = msgInitRect(
        msg0(pop_view_cls, sel_registerName("alloc")),
        sel_registerName("initWithFrame:"),
        CGRect{ .origin = .{ .x = 0.0, .y = 0.0 }, .size = pop_rect.size },
    );
    msgBool(pop_view, sel_registerName("setWantsLayer:"), true);
    msgId(popover_win, sel_registerName("setContentView:"), pop_view);
    const popover_layer = msg0(pop_view, sel_registerName("layer"));
    msgFloat(popover_layer, sel_registerName("setContentsScale:"), @floatFromInt(POPOVER_SCALE));

    // Register Popover View & Window for Finder/Browser/Photos Drag-and-Drop
    const NSString = objc_getClass("NSString") orelse return error.NoNSString;
    const NSArray = objc_getClass("NSArray") orelse return error.NoNSArray;
    const NSMutableArray = objc_getClass("NSMutableArray") orelse return error.NoNSArray;
    const pboard_filenames_type = msg0(msgUTF8(NSString, sel_registerName("stringWithUTF8String:"), "NSFilenamesPboardType"), sel_registerName("retain"));
    if (msg0(NSMutableArray, sel_registerName("array"))) |drag_types| {
        const drag_type_cstrs = [_][*:0]const u8{
            "public.file-url",
            "NSFilenamesPboardType",
            "public.png",
            "public.tiff",
        };
        for (drag_type_cstrs) |dt| {
            if (msgUTF8(NSString, sel_registerName("stringWithUTF8String:"), dt)) |dt_ns| {
                msgId(drag_types, sel_registerName("addObject:"), dt_ns);
            }
        }
        msgId(pop_view, sel_registerName("registerForDraggedTypes:"), drag_types);
        msgId(popover_win, sel_registerName("registerForDraggedTypes:"), drag_types);
    }

    // 5. Create Top Menu Bar Status Item
    const NSStatusBar = objc_getClass("NSStatusBar") orelse return error.NoStatusBar;
    const sys_bar = msg0(NSStatusBar, sel_registerName("systemStatusBar"));
    const status_item = msgStatusItem(sys_bar, sel_registerName("statusItemWithLength:"), -1.0);
    _ = msg0(status_item, sel_registerName("retain"));
    const status_button = msg0(status_item, sel_registerName("button"));
    // The glyph image is the whole status item: no title text.
    msgSetImagePosition(status_button, sel_registerName("setImagePosition:"), 1); // NSImageOnly
    // Fill the bar: glyph = menu bar thickness minus a little air, at 2x pixels.
    const bar_thickness = msgRetF64(sys_bar, sel_registerName("thickness"));
    const glyph_pt: f64 = math.clamp(@round(bar_thickness - 4.0), 12.0, @as(f64, @floatFromInt(status_glyph.MAX_PX / 2)));
    const glyph_px: usize = @intFromFloat(glyph_pt * 2.0);
    msgId(status_button, sel_registerName("setTarget:"), ctrl_instance);
    msgId(status_button, sel_registerName("setAction:"), sel_registerName("onStatusItemClick:"));

    // 6. Create CoreGraphics Bitmap Contexts (Native Display ColorSpace + kCGImageAlphaNoneSkipLast = 5
    //    on full-screen wallpaper contexts so QuartzCore skips CPU vUnpremultiplyData & TRC conversions!)
    const color_space = CGDisplayCopyColorSpace(display_id) orelse CGColorSpaceCreateDeviceRGB();
    // Every Space MUST own its provider. Falling back to a shared buffer would make several Space
    // layers alias one memory region (the "rave strobe" bug class), so fail loudly.
    var native_data_providers: [MAX_SPACES]?*anyopaque = @splat(null);
    for (0..MAX_SPACES) |idx| {
        native_data_providers[idx] = CGDataProviderCreateWithData(
            null,
            @ptrCast(&obs.space_native_pixels[idx]),
            NATIVE_PIXELS * 4,
            null,
        ) orelse return error.DataProviderFailed;
    }
    const popover_bitmap_ctx = CGBitmapContextCreate(
        @ptrCast(&obs.popover_pixels),
        POPOVER_BMP_W,
        POPOVER_BMP_H,
        8,
        POPOVER_BMP_W * 4,
        color_space,
        1 | (4 << 12),
    ) orelse return error.BitmapContextFailed;

    var bridge = MacBridge{
        .obs = obs,
        .objc_getClass = objc_getClass,
        .sel_registerName = sel_registerName,
        .msg0 = msg0,
        .msgVoid = msgVoid,
        .msgBool = msgBool,
        .msgInt = msgInt,
        .msgUInt = msgUInt,
        .msgFloat = msgFloat,
        .msgId = msgId,
        .msgIdRetId = msgIdRetId,
        .msgUIntRetId = msgUIntRetId,
        .msgId2 = msgId2,
        .msgInitWin = msgInitWin,
        .msgSetFrame = msgSetFrame,
        .msgUTF8 = msgUTF8,
        .msgRetPoint = msgRetPoint,
        .msgRetRect = msgRetRect,
        .msgRetInt = msgRetInt,
        .msgRetCStr = msgRetCStr,
        .msgInitImage = msgInitImage,
        .CGBitmapContextCreate = CGBitmapContextCreate,
        .CGBitmapContextCreateImage = CGBitmapContextCreateImage,
        .CGDataProviderCreateWithData = CGDataProviderCreateWithData,
        .CGImageCreate = CGImageCreate,
        .CGContextDrawImage = CGContextDrawImage,
        .CGContextRelease = CGContextRelease,
        .CGImageRelease = CGImageRelease,
        .CGImageGetWidth = CGImageGetWidth,
        .CGImageGetHeight = CGImageGetHeight,
        .CGContextSaveGState = CGContextSaveGState,
        .CGContextRestoreGState = CGContextRestoreGState,
        .CGContextScaleCTM = CGContextScaleCTM,
        .CGContextClearRect = CGContextClearRect,
        .CGContextSetRGBFillColor = CGContextSetRGBFillColor,
        .CGContextSetRGBStrokeColor = CGContextSetRGBStrokeColor,
        .CGContextSetLineWidth = CGContextSetLineWidth,
        .CGContextBeginPath = CGContextBeginPath,
        .CGContextMoveToPoint = CGContextMoveToPoint,
        .CGContextAddLineToPoint = CGContextAddLineToPoint,
        .CGContextClosePath = CGContextClosePath,
        .CGContextFillPath = CGContextFillPath,
        .CGContextStrokePath = CGContextStrokePath,
        .CGPathCreateWithRoundedRect = CGPathCreateWithRoundedRect,
        .CGContextAddPath = CGContextAddPath,
        .CGContextClip = CGContextClip,
        .CGPathRelease = CGPathRelease,
        .CGContextSetTextPosition = CGContextSetTextPosition,
        .CFURLCreateFromFileSystemRepresentation = CFURLCreateFromFileSystemRepresentation,
        .CGImageSourceCreateWithURL = CGImageSourceCreateWithURL,
        .CGImageSourceCreateWithData = CGImageSourceCreateWithData,
        .CGImageSourceCreateImageAtIndex = CGImageSourceCreateImageAtIndex,
        .CFRelease = CFRelease,
        .CFStringCreateWithBytes = CFStringCreateWithBytes,
        .CFAttributedStringCreate = CFAttributedStringCreate,
        .CTLineCreateWithAttributedString = CTLineCreateWithAttributedString,
        .CTLineDraw = CTLineDraw,
        .CFArrayGetCount = CFArrayGetCount,
        .CFArrayGetValueAtIndex = CFArrayGetValueAtIndex,
        .CFDictionaryGetValue = CFDictionaryGetValue,
        .CFNumberGetValue = CFNumberGetValue,
        .cgs_conn = CGSMainConnectionID(),
        .CGSGetActiveSpace = CGSGetActiveSpace,
        .CGSCopyManagedDisplaySpaces = CGSCopyManagedDisplaySpaces,
        .CGSMoveWindowsToManagedSpace = CGSMoveWindowsToManagedSpace,
        .cf_key_spaces = CFStringCreateWithCString(null, "Spaces", 0x08000100),
        .cf_key_id64 = CFStringCreateWithCString(null, "id64", 0x08000100),
        .cf_key_type = CFStringCreateWithCString(null, "type", 0x08000100),
        .dict_title = dict_title,
        .dict_body = dict_body,
        .dict_small = dict_small,
        .dict_mono = dict_mono,
        .ns_app = ns_app,
        .NSWindow = NSWindow,
        .NSNumber = NSNumber,
        .NSArray = NSArray,
        .NSURL = NSURL,
        .desktop_level = desktop_level,
        .normal_window = normal_window,
        .native_data_providers = native_data_providers,
        .popover_win = popover_win,
        .popover_layer = popover_layer,
        .popover_bitmap_ctx = popover_bitmap_ctx,
        .status_button = status_button,
        .NSImage = objc_getClass("NSImage"),
        .glyph_pt = glyph_pt,
        .glyph_px = glyph_px,
        .color_space = color_space,
        .display_id = display_id,
        .CGDisplayIsAsleep = CGDisplayIsAsleep,
        .CGSessionCopyCurrentDictionary = CGSessionCopyCurrentDictionary,
        .cf_key_screen_locked = CFStringCreateWithCString(null, "CGSSessionScreenIsLocked", 0x08000100),
        .cf_true = kCFBooleanTrue_ptr.*,
        .sel_occlusion_state = sel_registerName("occlusionState"),
        .perf_log = perf_log,
        .gpu_enabled = sc.gpu_ports,
        .screen_rect = screen_rect,
        .pboard_filenames_type = pboard_filenames_type,
        .CATransaction = objc_getClass("CATransaction"),
        .NSString = NSString,
        .NSEvent = objc_getClass("NSEvent"),
        .sel_set_contents = sel_registerName("setContents:"),
        .sel_flush = sel_registerName("flush"),
        .sel_set_title = sel_registerName("setTitle:"),
        .sel_str_utf8 = sel_registerName("stringWithUTF8String:"),
        .sel_disable_actions = sel_registerName("setDisableActions:"),
        .sel_set_alpha = sel_registerName("setAlphaValue:"),
        .sel_win_num = sel_registerName("windowNumber"),
        .sel_num_with_int = sel_registerName("numberWithInteger:"),
        .sel_arr_with_obj = sel_registerName("arrayWithObject:"),
        .max_frames = max_frames,
    };
    g_bridge = &bridge;
    sc.metal_validate = validateMetalTheme;

    // Disable macOS App Nap so NSTimer is never coalesced or throttled during Space swipes.
    // 0x00EFFFFF = NSActivityUserInitiatedAllowingIdleSystemSleep: clears bit 20
    // (NSActivityIdleSystemSleepDisabled) so a wallpaper never blocks the Mac from idle-sleeping.
    if (objc_getClass("NSProcessInfo")) |NSProcessInfo_cls| {
        if (msg0(NSProcessInfo_cls, sel_registerName("processInfo"))) |proc_info| {
            if (msgUTF8(NSString, sel_registerName("stringWithUTF8String:"), "Argus Live Wallpaper")) |reason_ns| {
                const MsgBeginActivity = *const fn (?*anyopaque, ?*anyopaque, u64, ?*anyopaque) callconv(.c) ?*anyopaque;
                const msgBeginActivity: MsgBeginActivity = @ptrCast(msgSend_raw);
                if (msgBeginActivity(proc_info, sel_registerName("beginActivityWithOptions:reason:"), 0x00EFFFFF, reason_ns)) |act_token| {
                    _ = msg0(act_token, sel_registerName("retain"));
                }
            }
        }
    }

    // Discover all user Desktop Spaces from SkyLight and bind a dedicated NSWindow to each Space!
    bridge.syncSpacesFromSkyLight(true);
    bridge.updateStatusGlyph();

    // Schedule 30 FPS NSTimer in NSRunLoopCommonModes
    const NSTimer = objc_getClass("NSTimer") orelse return error.NoNSTimer;
    const ns_timer = msgTimer(
        NSTimer,
        sel_registerName("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),
        1.0 / 30.0,
        ctrl_instance,
        sel_registerName("onTick:"),
        null,
        true,
    );
    const NSRunLoop = objc_getClass("NSRunLoop") orelse return error.NoRunLoop;
    const cur_loop = msg0(NSRunLoop, sel_registerName("currentRunLoop"));
    if (msgUTF8(NSString, sel_registerName("stringWithUTF8String:"), "kCFRunLoopCommonModes")) |common_modes| {
        msgId2(cur_loop, sel_registerName("addTimer:forMode:"), ns_timer, common_modes);
    }

    onTick(null, null, null);
    msgVoid(ns_app, sel_registerName("run"));
}

test "Observatory multi-Space engine: default Spaces, shader hot-compilation and config parsing" {
    g_io = std.testing.io;
    sc.g_io = std.testing.io;
    const alloc = std.testing.allocator;
    const obs = try Observatory.init(alloc);
    defer obs.deinit(alloc);

    // Every Space starts untouched; the app picks the first-launch theme.
    for (obs.spaces) |sp| try std.testing.expectEqual(SpaceMode.passthrough, sp.mode);

    // Verify live .zig shader hot-compilation (.dylib via dlopen) and execution on Space 2 (stateless) & Space 3 (stateful SDK)
    obs.n_spaces = 4;
    const compiled = obs.spaces[2].compileAndLoadShader(2, "themes/Gemini_Wormhole.zig");
    try std.testing.expect(compiled);
    try std.testing.expectEqual(SpaceMode.custom_shader, obs.spaces[2].mode);
    try std.testing.expect(obs.spaces[2].custom_render_fn != null);

    @memset(&obs.space_native_pixels[2], 0);
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(2, 0.25));
    // Verify the wormhole shader populated non-zero RGBA pixels
    try std.testing.expect(obs.space_native_pixels[2][(NATIVE_H / 2) * NATIVE_W + (NATIVE_W / 2 - 240)] != 0);

    // Verify stateful SDK theme hot-compilation (`themes/Echo.zig`)
    const compiled_sdk = obs.spaces[3].compileAndLoadShader(3, "themes/Echo.zig");
    try std.testing.expect(compiled_sdk);
    try std.testing.expect(obs.spaces[3].theme_state != null);
    @memset(&obs.space_native_pixels[3], 0);
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(3, 0.25));
    // Echo's background is black, so look for any lit (non-black RGB) pixel.
    var lit: usize = 0;
    for (obs.space_native_pixels[3]) |p| {
        if (p & 0x00FF_FFFF != 0) lit += 1;
    }
    try std.testing.expect(lit > 0);

    // Verify persistent state serialization & mode parsing
    var conf_buf: [2048]u8 = undefined;
    const serialized = obs.serializeStateConfig(&conf_buf);
    try std.testing.expect(std.mem.indexOf(u8, serialized, "2\tcustom_shader\tGemini_Wormhole.zig\tthemes/Gemini_Wormhole.zig") != null);
    try std.testing.expectEqual(SpaceMode.custom_shader, SpaceMode.fromModeName("custom_shader").?);
    // Configs saved by builds with built-in modes load those Spaces as untouched.
    for ([_][]const u8{ "magnetar_gr", "kronos_wave", "code_terminal" }) |legacy| {
        try std.testing.expectEqual(SpaceMode.passthrough, SpaceMode.fromModeName(legacy).?);
    }
    try std.testing.expect(SpaceMode.fromModeName("bogus") == null);
}

test "Native 1920x1200 Retina shader rendering (Echo.zig) and Watchdog isolation" {
    g_io = std.testing.io;
    sc.g_io = std.testing.io;
    const alloc = std.testing.allocator;
    const obs = try Observatory.init(alloc);
    defer obs.deinit(alloc);

    obs.n_spaces = 3;
    const ok_echo = obs.spaces[1].compileAndLoadShader(1, "themes/Echo.zig");
    try std.testing.expect(ok_echo);
    try std.testing.expectEqual(NATIVE_W, obs.spaces[1].render_w);
    try std.testing.expectEqual(NATIVE_H, obs.spaces[1].render_h);

    @memset(&obs.space_native_pixels[1], 0);
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(1, 0.1));
    try std.testing.expect(obs.space_native_pixels[1][(NATIVE_H / 2) * NATIVE_W + (NATIVE_W / 2)] != 0);

    // Write a faulty theme that reports NaN and verify Watchdog blocks it before loading into Space 1
    const bad_shader_path = "/tmp/argus_bad_watchdog_test.zig";
    const bad_src =
        \\pub export fn argus_theme_init(w: u32, h: u32, scale: f64) callconv(.c) ?*anyopaque {
        \\    _ = w; _ = h; _ = scale;
        \\    return @ptrFromInt(0x1000);
        \\}
        \\pub export fn argus_theme_deinit(s: ?*anyopaque) callconv(.c) void { _ = s; }
        \\pub export fn argus_theme_step(s: ?*anyopaque, dt: f64) callconv(.c) void { _ = s; _ = dt; }
        \\pub export fn argus_theme_draw(s: ?*anyopaque, p: [*]u32, len: usize, stride: usize) callconv(.c) void {
        \\    _ = s; _ = p; _ = len; _ = stride;
        \\}
        \\pub export fn argus_theme_has_nan(s: ?*anyopaque) callconv(.c) bool {
        \\    _ = s;
        \\    return true;
        \\}
    ;
    try std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = bad_shader_path, .data = bad_src });
    const rejected = obs.spaces[1].compileAndLoadShader(1, bad_shader_path);
    try std.testing.expect(!rejected);
    // Previous valid Echo.zig shader remains intact on Space 1!
    try std.testing.expectEqualStrings("Echo.zig", obs.spaces[1].getLabel());
}

test "Isolated per-Space shader buffers never alias each other" {
    g_io = std.testing.io;
    sc.g_io = std.testing.io;
    const alloc = std.testing.allocator;
    const obs = try Observatory.init(alloc);
    defer obs.deinit(alloc);
    obs.n_spaces = 3;

    try std.testing.expect(obs.loadShaderIntoSpace(0, "themes/Gemini_Wormhole.zig"));
    try std.testing.expect(obs.loadShaderIntoSpace(1, "themes/Echo.zig"));

    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(0, 0.1));
    const snap = try alloc.dupe(u32, &obs.space_native_pixels[0]);
    defer alloc.free(snap);

    // Rendering a DIFFERENT Space must not touch Space 0's pixels (the "rave strobe" bug class).
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(1, 0.1));
    try std.testing.expectEqualSlices(u32, snap, &obs.space_native_pixels[0]);
    try std.testing.expect(!std.mem.eql(u32, &obs.space_native_pixels[0], &obs.space_native_pixels[1]));
}

test "Reloading a shader into a dirty Space repaints instead of inheriting stale pixels" {
    g_io = std.testing.io;
    sc.g_io = std.testing.io;
    const alloc = std.testing.allocator;
    const obs = try Observatory.init(alloc);
    defer obs.deinit(alloc);
    obs.n_spaces = 3;

    // Space 1: render the wormhole, then plant "previous theme" garbage in the interior while leaving the
    // probe pixels (corners) intact, so a probe-based background-skip heuristic would be fooled.
    try std.testing.expect(obs.loadShaderIntoSpace(1, "themes/Gemini_Wormhole.zig"));
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(1, 0.1));
    const garbage_idx = 100 * NATIVE_W + 100;
    obs.space_native_pixels[1][garbage_idx] = 0xFF00FF00;

    // Reload through the production entry point, then render one frame.
    try std.testing.expect(obs.loadShaderIntoSpace(1, "themes/Gemini_Wormhole.zig"));
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(1, 0.1));

    // Space 2: the same theme from a clean load, one frame.
    try std.testing.expect(obs.loadShaderIntoSpace(2, "themes/Gemini_Wormhole.zig"));
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(2, 0.1));

    try std.testing.expect(obs.space_native_pixels[1][garbage_idx] != 0xFF00FF00);
    try std.testing.expectEqualSlices(u32, &obs.space_native_pixels[2], &obs.space_native_pixels[1]);
}

test "Mission Control Space reordering moves themes with space_id and resets moved shader buffers" {
    g_io = std.testing.io;
    sc.g_io = std.testing.io;
    const alloc = std.testing.allocator;
    const obs = try Observatory.init(alloc);
    defer obs.deinit(alloc);

    obs.n_spaces = 4;
    const initial_ids = [_]u64{ 3, 4, 7, 6 };
    for (0..4) |i| {
        obs.spaces[i].space_id = initial_ids[i];
        obs.spaces[i].index_1based = i + 1;
    }

    // Slot 1 (space_id = 4) has Gemini_Wormhole.zig; Slot 3 (space_id = 6) has a picture
    try std.testing.expect(obs.loadShaderIntoSpace(1, "themes/Gemini_Wormhole.zig"));
    obs.spaces[3].mode = .picture;
    obs.spaces[3].setLabel("Photo.png");

    // Render the wormhole in Slot 1, and plant stale garbage in Slot 3's native buffer while copying
    // the wormhole's corner probe pixels into Slot 3 so a missing reset on move would be caught.
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(1, 0.1));
    @memcpy(&obs.space_native_pixels[3], &obs.space_native_pixels[1]);
    const garbage_idx = 100 * NATIVE_W + 100;
    obs.space_native_pixels[3][garbage_idx] = 0xFF00FF00;

    // Simulate user dragging Space id=4 (the wormhole) to Slot 3 and Space id=6 (Picture) to Slot 1 in Mission Control
    const reordered_ids = [_]u64{ 3, 6, 7, 4 };
    const sync1 = obs.syncSpaceOrderByIds(&reordered_ids, 4);
    try std.testing.expect(sync1.order_changed);
    try std.testing.expectEqual(@as(usize, 3), obs.active_space_idx);
    try std.testing.expectEqual(@as(u64, 6), obs.spaces[1].space_id);
    try std.testing.expectEqual(SpaceMode.picture, obs.spaces[1].mode);
    try std.testing.expectEqual(@as(usize, 2), obs.spaces[1].index_1based);
    try std.testing.expectEqual(@as(u64, 4), obs.spaces[3].space_id);
    try std.testing.expectEqual(SpaceMode.custom_shader, obs.spaces[3].mode);
    try std.testing.expectEqual(@as(usize, 4), obs.spaces[3].index_1based);

    // Slot 3's native buffer must have been reset on move so rendering the wormhole at Slot 3 wipes the planted garbage
    try std.testing.expect(obs.renderNativeShaderForSpaceIsolated(3, 0.1));
    try std.testing.expect(obs.space_native_pixels[3][garbage_idx] != 0xFF00FF00);

    // Second sync with unchanged order must be a no-op fast path
    const sync2 = obs.syncSpaceOrderByIds(&reordered_ids, 6);
    try std.testing.expect(!sync2.order_changed);
    try std.testing.expectEqual(@as(u16, 0), sync2.moved_mask);
    try std.testing.expectEqual(@as(usize, 1), obs.active_space_idx);
}


test {
    _ = status_glyph;
    _ = metal_theme;
}

test "Metal-only themes load into a Space and render on the GPU" {
    g_io = std.testing.io;
    sc.g_io = std.testing.io;
    const alloc = std.testing.allocator;
    const obs = try Observatory.init(alloc);
    defer obs.deinit(alloc);
    obs.n_spaces = 2;

    try std.testing.expect(obs.loadShaderIntoSpace(1, "themes/Tutorial_Reef.metal"));
    try std.testing.expect(obs.spaces[1].metal_theme);
    try std.testing.expectEqual(SpaceMode.custom_shader, obs.spaces[1].mode);
    try std.testing.expectEqualStrings("Tutorial_Reef.metal", obs.spaces[1].getLabel());
    // A .metal file without `argus_draw` is refused and the Space keeps its theme.
    try std.Io.Dir.cwd().writeFile(g_io, .{ .sub_path = "/tmp/argus_not_a_theme.metal", .data = "kernel void other() {}" });
    try std.testing.expect(!obs.loadShaderIntoSpace(1, "/tmp/argus_not_a_theme.metal"));
    try std.testing.expectEqualStrings("Tutorial_Reef.metal", obs.spaces[1].getLabel());

    const mtl = @import("gpu/metal.zig");
    for ([_][]const u8{ "themes/Tutorial_Tides.metal", "themes/Tutorial_Reef.metal" }) |path| {
        var buf: [131072]u8 = undefined;
        const src = try std.Io.Dir.cwd().readFile(g_io, path, &buf);
        var err_buf: [2048]u8 = undefined;
        var t = metal_theme.Theme.compile(src, path, 64, 40, 1, &err_buf) catch |e| {
            std.debug.print("{s}: {s}\n", .{ path, std.mem.sliceTo(&err_buf, 0) });
            return e;
        };
        defer t.deinit();
        const out = mtl.newTexture(t.dev, mtl.PIXEL_RGBA32F, 64, 40, mtl.STORAGE_SHARED);
        defer mtl.release(out);
        for (0..3) |_| {
            const cb = mtl.msg(mtl.Id, t.queue, "commandBuffer", .{});
            t.encode(cb, out, 1.0 / 30.0);
            mtl.msg(void, cb, "commit", .{});
            mtl.msg(void, cb, "waitUntilCompleted", .{});
            try std.testing.expect(mtl.msg(usize, cb, "status", .{}) != 5);
        }
    }
}

// ============================================================================
// ARGUS DESKTOP // src/desktop/desktop_picture.zig
//
// Theme stills as each theme Space's macOS desktop picture, while Argus runs.
//
// macOS judges a Space from its desktop picture, not from Argus's desktop-level window above it:
// - On macOS 26 the menu bar is clear, and over a bright picture WindowServer adds a frosted
//   legibility band (its own window, the top ~83 pt, layered above desktop-level windows). That
//   band blurs the live theme under it, so a dark theme gets a grey haze across the top.
// - The Spaces bar in Mission Control draws each Space from its picture and leaves Argus out.
// So when a theme Space is visited (or a theme lands on the active Space) and has settled for a
// second, its current frame is written once to a PNG and set as that Space's desktop picture.
// The user's own picture is recorded first and put back when the Space returns to passthrough
// ("macOS Default") or Argus quits.
//
// `setDesktopImageURL:forScreen:` only reaches the active Space, so stills are set per Space, as
// each one is visited. Work is once per visit or theme load, never per frame: the per-tick path
// is a few integer compares. On quit, when every Space goes back to the same picture of the
// user's (the usual case), one call with AppKit's all-Spaces option restores them all and makes
// it the picture new Spaces start with; otherwise the active Space is restored and the ledger on
// disk keeps the others' originals, restored on their next visit after a restart (also after a
// crash).
// ============================================================================

const std = @import("std");
const sc = @import("space_config.zig");
const settings = @import("settings.zig");

/// Settings key (desktop/settings.zig); on unless set to 0.
pub const SETTING_KEY = "mission_control_stills";

pub const MAX_ENTRIES: usize = 32;
pub const UUID_MAX: usize = 48;
pub const URL_MAX: usize = 1024;
/// Ticks a theme must run on the active Space before its still is taken (30 ticks = 1 s at 30 Hz),
/// so the still is a developed frame, not the first one after a load.
pub const SETTLE_TICKS: usize = 30;
/// Unused stills are kept this long: a Space created from a themed Space keeps pointing at its file.
pub const PRUNE_DAYS: i96 = 14;

const STILLS_SUBDIR = "/Library/Application Support/Argus/Desktop Stills";
const LEDGER_NAME = "ledger.tsv";

pub const Entry = struct {
    uuid_buf: [UUID_MAX]u8 = @splat(0),
    uuid_len: usize = 0,
    /// The user's desktop picture URL (absoluteString) before Argus set a still; empty = unknown.
    orig_buf: [URL_MAX]u8 = @splat(0),
    orig_len: usize = 0,
    /// Signature of the still currently set on this Space; 0 = none set.
    applied_sig: u64 = 0,

    pub fn uuid(self: *const Entry) []const u8 {
        return self.uuid_buf[0..self.uuid_len];
    }
    pub fn original(self: *const Entry) []const u8 {
        return self.orig_buf[0..self.orig_len];
    }
    pub fn setOriginal(self: *Entry, s: []const u8) void {
        const n = @min(s.len, URL_MAX);
        @memcpy(self.orig_buf[0..n], s[0..n]);
        self.orig_len = n;
    }
};

/// A Space and the desktop picture macOS has for it (url_len 0: unknown).
pub const Pic = struct {
    uuid_buf: [UUID_MAX]u8 = @splat(0),
    uuid_len: usize = 0,
    url_buf: [URL_MAX]u8 = @splat(0),
    url_len: usize = 0,

    pub fn uuid(self: *const Pic) []const u8 {
        return self.uuid_buf[0..self.uuid_len];
    }
    pub fn url(self: *const Pic) []const u8 {
        return self.url_buf[0..self.url_len];
    }
    pub fn setURL(self: *Pic, s: []const u8) void {
        if (s.len > URL_MAX) return;
        @memcpy(self.url_buf[0..s.len], s);
        self.url_len = s.len;
    }
};

/// Identifies what a still shows: the mode, the theme/picture path and, for themes, the file mtime
/// (so a hot-reload makes a new still). 0 means passthrough: nothing of Argus's to show.
pub fn stillSignature(sp: *const sc.SpaceConfig) u64 {
    if (sp.mode == .passthrough) return 0;
    var h = std.hash.Wyhash.init(0x41524755);
    h.update(&[_]u8{@intFromEnum(sp.mode)});
    h.update(sp.getPath());
    if (sp.mode == .custom_shader) h.update(std.mem.asBytes(&sp.last_mtime));
    const v = h.final();
    return if (v == 0) 1 else v;
}

/// The ledger: one line per Space Argus has touched, `uuid \t applied_sig_hex \t original_url`.
pub const Ledger = struct {
    entries: [MAX_ENTRIES]Entry = @splat(.{}),
    n: usize = 0,

    pub fn find(self: *Ledger, space_uuid: []const u8) ?*Entry {
        for (self.entries[0..self.n]) |*e| {
            if (std.mem.eql(u8, e.uuid(), space_uuid)) return e;
        }
        return null;
    }

    pub fn findOrAdd(self: *Ledger, space_uuid: []const u8) ?*Entry {
        if (self.find(space_uuid)) |e| return e;
        if (space_uuid.len == 0 or space_uuid.len > UUID_MAX) return null;
        if (self.n == MAX_ENTRIES) {
            // Full: drop the oldest entry that holds no still (nothing to restore there).
            var victim: ?usize = null;
            for (self.entries[0..self.n], 0..) |*e, i| {
                if (e.applied_sig == 0) {
                    victim = i;
                    break;
                }
            }
            const vi = victim orelse return null;
            self.remove(vi);
        }
        const e = &self.entries[self.n];
        e.* = .{};
        @memcpy(e.uuid_buf[0..space_uuid.len], space_uuid);
        e.uuid_len = space_uuid.len;
        self.n += 1;
        return e;
    }

    pub fn remove(self: *Ledger, i: usize) void {
        if (i >= self.n) return;
        var j = i;
        while (j + 1 < self.n) : (j += 1) self.entries[j] = self.entries[j + 1];
        self.n -= 1;
    }

    pub fn serialize(self: *const Ledger, out: []u8) []const u8 {
        var pos: usize = 0;
        for (self.entries[0..self.n]) |*e| {
            if (e.orig_len == 0) continue;
            const w = std.fmt.bufPrint(out[pos..], "{s}\t{x}\t{s}\n", .{ e.uuid(), e.applied_sig, e.original() }) catch break;
            pos += w.len;
        }
        return out[0..pos];
    }

    pub fn parse(self: *Ledger, text: []const u8) void {
        self.n = 0;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trimEnd(u8, raw, "\r");
            var cols = std.mem.splitScalar(u8, line, '\t');
            const u = cols.next() orelse continue;
            const sig_s = cols.next() orelse continue;
            const orig = cols.next() orelse "";
            const sig = std.fmt.parseInt(u64, sig_s, 16) catch continue;
            if (orig.len == 0 or orig.len > URL_MAX) continue;
            const e = self.findOrAdd(u) orelse continue;
            e.applied_sig = sig;
            e.setOriginal(orig);
        }
    }
};

// ----------------------------------------------------------------------------
// Native side (AppKit / ImageIO / SkyLight), loaded lazily with dlsym
// ----------------------------------------------------------------------------

const Id = ?*anyopaque;
const Sel = ?*anyopaque;
const Msg0 = *const fn (Id, Sel) callconv(.c) Id;
const Msg1 = *const fn (Id, Sel, Id) callconv(.c) Id;
const MsgIdx = *const fn (Id, Sel, usize) callconv(.c) Id;
const MsgCStr = *const fn (Id, Sel, [*:0]const u8) callconv(.c) Id;
const MsgRetCStr = *const fn (Id, Sel) callconv(.c) ?[*:0]const u8;
const MsgSetDesktop = *const fn (Id, Sel, Id, Id, Id, ?*Id) callconv(.c) bool;
const Msg2 = *const fn (Id, Sel, Id, Id) callconv(.c) Id;
const MsgBoolArg = *const fn (Id, Sel, bool) callconv(.c) Id;
const MsgRetBool1 = *const fn (Id, Sel, Id) callconv(.c) bool;
const MsgRetUsize = *const fn (Id, Sel) callconv(.c) usize;
const MsgPList = *const fn (Id, Sel, Id, usize, ?*anyopaque, ?*Id) callconv(.c) Id;

const CGPoint = extern struct { x: f64, y: f64 };
const CGSize = extern struct { width: f64, height: f64 };
const CGRect = extern struct { origin: CGPoint, size: CGSize };

const Native = struct {
    getClass: *const fn ([*:0]const u8) callconv(.c) Id,
    sel: *const fn ([*:0]const u8) callconv(.c) Sel,
    msg0: Msg0,
    msg1: Msg1,
    msgIdx: MsgIdx,
    msgCStr: MsgCStr,
    msgRetCStr: MsgRetCStr,
    msgSetDesktop: MsgSetDesktop,
    msg2: Msg2,
    msgBoolArg: MsgBoolArg,
    msgRetBool1: MsgRetBool1,
    msgRetUsize: MsgRetUsize,
    msgPList: MsgPList,
    /// AppKit's `NSWorkspaceDesktopImageAllSpacesKey` (an exported NSString); null when this
    /// macOS lacks it, and then quitting restores Spaces one visit at a time.
    all_spaces_key: Id,
    CFRelease: *const fn (?*anyopaque) callconv(.c) void,
    CFStringCreateWithCString: *const fn (?*anyopaque, [*:0]const u8, u32) callconv(.c) ?*anyopaque,
    CFStringGetCString: *const fn (?*anyopaque, [*]u8, isize, u32) callconv(.c) bool,
    CFArrayGetCount: *const fn (?*anyopaque) callconv(.c) isize,
    CFArrayGetValueAtIndex: *const fn (?*anyopaque, isize) callconv(.c) ?*anyopaque,
    CFDictionaryGetValue: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque,
    CFNumberGetValue: *const fn (?*anyopaque, i32, *anyopaque) callconv(.c) bool,
    CFURLCreateFromFileSystemRepresentation: *const fn (?*anyopaque, [*]const u8, isize, bool) callconv(.c) ?*anyopaque,
    CGImageDestinationCreateWithURL: *const fn (?*anyopaque, ?*anyopaque, usize, ?*anyopaque) callconv(.c) ?*anyopaque,
    CGImageDestinationAddImage: *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) void,
    CGImageDestinationFinalize: *const fn (?*anyopaque) callconv(.c) bool,
    CGImageGetWidth: *const fn (?*anyopaque) callconv(.c) usize,
    CGImageGetHeight: *const fn (?*anyopaque) callconv(.c) usize,
    CGImageGetColorSpace: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    CGBitmapContextCreate: *const fn (?*anyopaque, usize, usize, usize, usize, ?*anyopaque, u32) callconv(.c) ?*anyopaque,
    CGBitmapContextCreateImage: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    CGContextDrawImage: *const fn (?*anyopaque, CGRect, ?*anyopaque) callconv(.c) void,
    CGContextRelease: *const fn (?*anyopaque) callconv(.c) void,
    CGImageRelease: *const fn (?*anyopaque) callconv(.c) void,
    CGSMainConnectionID: *const fn () callconv(.c) u32,
    CGSCopyManagedDisplaySpaces: *const fn (u32) callconv(.c) ?*anyopaque,
    key_spaces: ?*anyopaque,
    key_id64: ?*anyopaque,
    key_uuid: ?*anyopaque,
    key_type: ?*anyopaque,
    uti_png: ?*anyopaque,

    fn load() ?Native {
        const objc = std.c.dlopen("/usr/lib/libobjc.A.dylib", .{ .LAZY = true }) orelse return null;
        const cf = std.c.dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", .{ .LAZY = true }) orelse return null;
        const iio = std.c.dlopen("/System/Library/Frameworks/ImageIO.framework/ImageIO", .{ .LAZY = true }) orelse return null;
        const cg = std.c.dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", .{ .LAZY = true }) orelse return null;
        const sky = std.c.dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", .{ .LAZY = true }) orelse return null;
        const appkit = std.c.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", .{ .LAZY = true }) orelse return null;
        const all_key: ?*const Id = @ptrCast(@alignCast(std.c.dlsym(appkit, "NSWorkspaceDesktopImageAllSpacesKey")));
        const msg = std.c.dlsym(objc, "objc_msgSend") orelse return null;
        const mkstr: *const fn (?*anyopaque, [*:0]const u8, u32) callconv(.c) ?*anyopaque = @ptrCast(@alignCast(std.c.dlsym(cf, "CFStringCreateWithCString") orelse return null));
        return .{
            .getClass = @ptrCast(@alignCast(std.c.dlsym(objc, "objc_getClass") orelse return null)),
            .sel = @ptrCast(@alignCast(std.c.dlsym(objc, "sel_registerName") orelse return null)),
            .msg0 = @ptrCast(@alignCast(msg)),
            .msg1 = @ptrCast(@alignCast(msg)),
            .msgIdx = @ptrCast(@alignCast(msg)),
            .msgCStr = @ptrCast(@alignCast(msg)),
            .msgRetCStr = @ptrCast(@alignCast(msg)),
            .msgSetDesktop = @ptrCast(@alignCast(msg)),
            .msg2 = @ptrCast(@alignCast(msg)),
            .msgBoolArg = @ptrCast(@alignCast(msg)),
            .msgRetBool1 = @ptrCast(@alignCast(msg)),
            .msgRetUsize = @ptrCast(@alignCast(msg)),
            .msgPList = @ptrCast(@alignCast(msg)),
            .all_spaces_key = if (all_key) |k| k.* else null,
            .CFRelease = @ptrCast(@alignCast(std.c.dlsym(cf, "CFRelease") orelse return null)),
            .CFStringCreateWithCString = mkstr,
            .CFStringGetCString = @ptrCast(@alignCast(std.c.dlsym(cf, "CFStringGetCString") orelse return null)),
            .CFArrayGetCount = @ptrCast(@alignCast(std.c.dlsym(cf, "CFArrayGetCount") orelse return null)),
            .CFArrayGetValueAtIndex = @ptrCast(@alignCast(std.c.dlsym(cf, "CFArrayGetValueAtIndex") orelse return null)),
            .CFDictionaryGetValue = @ptrCast(@alignCast(std.c.dlsym(cf, "CFDictionaryGetValue") orelse return null)),
            .CFNumberGetValue = @ptrCast(@alignCast(std.c.dlsym(cf, "CFNumberGetValue") orelse return null)),
            .CFURLCreateFromFileSystemRepresentation = @ptrCast(@alignCast(std.c.dlsym(cf, "CFURLCreateFromFileSystemRepresentation") orelse return null)),
            .CGImageDestinationCreateWithURL = @ptrCast(@alignCast(std.c.dlsym(iio, "CGImageDestinationCreateWithURL") orelse return null)),
            .CGImageDestinationAddImage = @ptrCast(@alignCast(std.c.dlsym(iio, "CGImageDestinationAddImage") orelse return null)),
            .CGImageDestinationFinalize = @ptrCast(@alignCast(std.c.dlsym(iio, "CGImageDestinationFinalize") orelse return null)),
            .CGSMainConnectionID = @ptrCast(@alignCast(std.c.dlsym(sky, "CGSMainConnectionID") orelse return null)),
            .CGImageGetWidth = @ptrCast(@alignCast(std.c.dlsym(cg, "CGImageGetWidth") orelse return null)),
            .CGImageGetHeight = @ptrCast(@alignCast(std.c.dlsym(cg, "CGImageGetHeight") orelse return null)),
            .CGImageGetColorSpace = @ptrCast(@alignCast(std.c.dlsym(cg, "CGImageGetColorSpace") orelse return null)),
            .CGBitmapContextCreate = @ptrCast(@alignCast(std.c.dlsym(cg, "CGBitmapContextCreate") orelse return null)),
            .CGBitmapContextCreateImage = @ptrCast(@alignCast(std.c.dlsym(cg, "CGBitmapContextCreateImage") orelse return null)),
            .CGContextDrawImage = @ptrCast(@alignCast(std.c.dlsym(cg, "CGContextDrawImage") orelse return null)),
            .CGContextRelease = @ptrCast(@alignCast(std.c.dlsym(cg, "CGContextRelease") orelse return null)),
            .CGImageRelease = @ptrCast(@alignCast(std.c.dlsym(cg, "CGImageRelease") orelse return null)),
            .CGSCopyManagedDisplaySpaces = @ptrCast(@alignCast(std.c.dlsym(sky, "CGSCopyManagedDisplaySpaces") orelse return null)),
            .key_spaces = mkstr(null, "Spaces", 0x08000100),
            .key_id64 = mkstr(null, "id64", 0x08000100),
            .key_uuid = mkstr(null, "uuid", 0x08000100),
            .key_type = mkstr(null, "type", 0x08000100),
            .uti_png = mkstr(null, "public.png", 0x08000100),
        };
    }

    /// The screen whose Spaces CGSGetActiveSpace reports: the first NSScreen (the menu-bar display).
    fn mainScreen(self: *const Native) Id {
        const screens = self.msg0(self.getClass("NSScreen"), self.sel("screens")) orelse return null;
        return self.msgIdx(screens, self.sel("objectAtIndex:"), 0);
    }

    fn workspace(self: *const Native) Id {
        return self.msg0(self.getClass("NSWorkspace"), self.sel("sharedWorkspace"));
    }

    /// The active Space's desktop picture as an absoluteString; null when macOS reports none
    /// (e.g. a non-file wallpaper), in which case Argus leaves that Space alone.
    fn currentDesktopURL(self: *const Native, out: []u8) ?[]const u8 {
        const screen = self.mainScreen() orelse return null;
        const url = self.msg1(self.workspace(), self.sel("desktopImageURLForScreen:"), screen) orelse return null;
        const abs = self.msg0(url, self.sel("absoluteString")) orelse return null;
        const s = self.msgRetCStr(abs, self.sel("UTF8String")) orelse return null;
        const sl = std.mem.sliceTo(s, 0);
        if (sl.len == 0 or sl.len > out.len) return null;
        @memcpy(out[0..sl.len], sl);
        return out[0..sl.len];
    }

    /// Sets the active Space's picture; with `all_spaces`, every Space of the main display's.
    fn setDesktopURL(self: *const Native, abs_url: []const u8) bool {
        return self.setDesktopURLOn(abs_url, false);
    }

    fn setDesktopURLOn(self: *const Native, abs_url: []const u8, all_spaces: bool) bool {
        var buf: [URL_MAX + 1]u8 = undefined;
        if (abs_url.len > URL_MAX) return false;
        @memcpy(buf[0..abs_url.len], abs_url);
        buf[abs_url.len] = 0;
        const screen = self.mainScreen() orelse return false;
        const str = self.msgCStr(self.getClass("NSString"), self.sel("stringWithUTF8String:"), @ptrCast(&buf)) orelse return false;
        const url = self.msg1(self.getClass("NSURL"), self.sel("URLWithString:"), str) orelse return false;
        const opts = if (all_spaces) blk: {
            const key = self.all_spaces_key orelse return false;
            const yes = self.msgBoolArg(self.getClass("NSNumber"), self.sel("numberWithBool:"), true);
            break :blk self.msg2(self.getClass("NSDictionary"), self.sel("dictionaryWithObject:forKey:"), yes, key);
        } else self.msg0(self.getClass("NSDictionary"), self.sel("dictionary"));
        var err: Id = null;
        return self.msgSetDesktop(self.workspace(), self.sel("setDesktopImageURL:forScreen:options:error:"), url, screen, opts, &err);
    }

    fn spaceUUID(self: *const Native, space_id: u64, out: []u8) ?[]const u8 {
        const displays = self.CGSCopyManagedDisplaySpaces(self.CGSMainConnectionID()) orelse return null;
        defer self.CFRelease(displays);
        var d: isize = 0;
        while (d < self.CFArrayGetCount(displays)) : (d += 1) {
            const disp = self.CFArrayGetValueAtIndex(displays, d) orelse continue;
            const spaces = self.CFDictionaryGetValue(disp, self.key_spaces) orelse continue;
            var s: isize = 0;
            while (s < self.CFArrayGetCount(spaces)) : (s += 1) {
                const sp = self.CFArrayGetValueAtIndex(spaces, s) orelse continue;
                var sid: i64 = 0;
                const num = self.CFDictionaryGetValue(sp, self.key_id64) orelse continue;
                _ = self.CFNumberGetValue(num, 4, &sid); // kCFNumberSInt64Type
                if (sid <= 0 or @as(u64, @intCast(sid)) != space_id) continue;
                const u = self.CFDictionaryGetValue(sp, self.key_uuid) orelse return null;
                if (!self.CFStringGetCString(u, out.ptr, @intCast(out.len), 0x08000100)) return null;
                const sl = std.mem.sliceTo(out, 0);
                return if (sl.len > 0) sl else null;
            }
        }
        return null;
    }

    /// The UUIDs of every current Space, on every display. Null when SkyLight reports none.
    fn currentSpaceUUIDs(self: *const Native, out: []Pic) ?usize {
        const displays = self.CGSCopyManagedDisplaySpaces(self.CGSMainConnectionID()) orelse return null;
        defer self.CFRelease(displays);
        var n: usize = 0;
        var d: isize = 0;
        while (d < self.CFArrayGetCount(displays)) : (d += 1) {
            const disp = self.CFArrayGetValueAtIndex(displays, d) orelse continue;
            const spaces = self.CFDictionaryGetValue(disp, self.key_spaces) orelse continue;
            var s: isize = 0;
            while (s < self.CFArrayGetCount(spaces)) : (s += 1) {
                const sp = self.CFArrayGetValueAtIndex(spaces, s) orelse continue;
                // Desktops only (type 0); a fullscreen app's Space has no picture of its own.
                var kind: i64 = 0;
                if (self.CFDictionaryGetValue(sp, self.key_type)) |t| _ = self.CFNumberGetValue(t, 4, &kind);
                if (kind != 0) continue;
                const u = self.CFDictionaryGetValue(sp, self.key_uuid) orelse continue;
                if (n == out.len) return null; // more Spaces than we can check: don't guess
                out[n] = .{};
                if (!self.CFStringGetCString(u, &out[n].uuid_buf, UUID_MAX, 0x08000100)) return null;
                out[n].uuid_len = std.mem.indexOfScalar(u8, &out[n].uuid_buf, 0) orelse return null;
                if (out[n].uuid_len > 0) n += 1;
            }
        }
        return if (n > 0) n else null;
    }

    fn nsString(self: *const Native, z: [*:0]const u8) Id {
        return self.msgCStr(self.getClass("NSString"), self.sel("stringWithUTF8String:"), z);
    }

    /// `obj[key]` when `obj` is a dictionary, else null (the store's layout is not ours to trust).
    fn dictGet(self: *const Native, obj: Id, key: [*:0]const u8) Id {
        const o = obj orelse return null;
        if (!self.msgRetBool1(o, self.sel("isKindOfClass:"), self.getClass("NSDictionary"))) return null;
        return self.msg1(o, self.sel("objectForKey:"), self.nsString(key));
    }

    /// Reads, never writes, the per-Space desktop pictures macOS keeps in the wallpaper store
    /// (`com.apple.wallpaper/Store/Index.plist`, macOS 14+): `Spaces/<uuid>/Default/Desktop/
    /// Content/Choices[0]` holds an image choice whose `Configuration` plist has `url.relative`.
    /// Fills `pics[i].url` for each Space in `pics` (url_len stays 0 where the store has no image).
    /// False when the store cannot be read.
    fn storePictures(self: *const Native, pics: []Pic) bool {
        const home = std.c.getenv("HOME") orelse return false;
        var path_buf: [600]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/Library/Application Support/com.apple.wallpaper/Store/Index.plist\x00", .{std.mem.sliceTo(home, 0)}) catch return false;
        const root = self.msg1(self.getClass("NSDictionary"), self.sel("dictionaryWithContentsOfFile:"), self.nsString(@ptrCast(path.ptr)));
        const spaces = self.dictGet(root, "Spaces") orelse return false;
        for (pics) |*pic| {
            var ubuf: [UUID_MAX + 1]u8 = @splat(0);
            @memcpy(ubuf[0..pic.uuid_len], pic.uuid());
            const content = self.dictGet(self.dictGet(self.dictGet(self.msg1(spaces, self.sel("objectForKey:"), self.nsString(@ptrCast(&ubuf))), "Default"), "Desktop"), "Content");
            const choices = self.dictGet(content, "Choices") orelse continue;
            if (!self.msgRetBool1(choices, self.sel("isKindOfClass:"), self.getClass("NSArray"))) continue;
            if (self.msgRetUsize(choices, self.sel("count")) != 1) continue; // shuffles and such: not one picture
            const choice = self.msgIdx(choices, self.sel("objectAtIndex:"), 0);
            const provider = self.dictGet(choice, "Provider") orelse continue;
            const prov = self.msgRetCStr(provider, self.sel("UTF8String")) orelse continue;
            if (!std.mem.eql(u8, std.mem.sliceTo(prov, 0), "com.apple.wallpaper.choice.image")) continue;
            const cfg = self.dictGet(choice, "Configuration") orelse continue;
            if (!self.msgRetBool1(cfg, self.sel("isKindOfClass:"), self.getClass("NSData"))) continue;
            var err: Id = null;
            const plist = self.msgPList(self.getClass("NSPropertyListSerialization"), self.sel("propertyListWithData:options:format:error:"), cfg, 0, null, &err);
            const rel = self.dictGet(self.dictGet(plist, "url"), "relative") orelse continue;
            if (!self.msgRetBool1(rel, self.sel("isKindOfClass:"), self.getClass("NSString"))) continue;
            const u = self.msgRetCStr(rel, self.sel("UTF8String")) orelse continue;
            pic.setURL(std.mem.sliceTo(u, 0));
        }
        return true;
    }

    /// A private copy of a frame. Theme frames wrap a pixel buffer that the next render overwrites,
    /// so the background encoder must never read the live one.
    fn copyImage(self: *const Native, img: ?*anyopaque) ?*anyopaque {
        const w = self.CGImageGetWidth(img);
        const h = self.CGImageGetHeight(img);
        if (w == 0 or h == 0) return null;
        // kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big, like the frames Argus presents.
        const ctx = self.CGBitmapContextCreate(null, w, h, 8, 0, self.CGImageGetColorSpace(img), 5 | (4 << 12)) orelse return null;
        defer self.CGContextRelease(ctx);
        const r = CGRect{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = @floatFromInt(w), .height = @floatFromInt(h) } };
        self.CGContextDrawImage(ctx, r, img);
        return self.CGBitmapContextCreateImage(ctx);
    }

    fn writePNG(self: *const Native, cg_image: ?*anyopaque, path: []const u8) bool {
        const url = self.CFURLCreateFromFileSystemRepresentation(null, path.ptr, @intCast(path.len), false) orelse return false;
        defer self.CFRelease(url);
        const dest = self.CGImageDestinationCreateWithURL(url, self.uti_png, 1, null) orelse return false;
        defer self.CFRelease(dest);
        self.CGImageDestinationAddImage(dest, cg_image, null);
        return self.CGImageDestinationFinalize(dest);
    }
};

// ----------------------------------------------------------------------------
// Per-visit driver
// ----------------------------------------------------------------------------

const JOB_IDLE: u8 = 0;
const JOB_RUNNING: u8 = 1;
const JOB_OK: u8 = 2;
const JOB_FAILED: u8 = 3;

/// One background PNG encode. The main thread fills it and starts the thread; the thread only
/// writes the file and publishes `state`; the main thread reads the result on a later tick.
const Job = struct {
    state: std.atomic.Value(u8) = std.atomic.Value(u8).init(JOB_IDLE),
    space_id: u64 = 0,
    sig: u64 = 0,
    uuid_buf: [UUID_MAX]u8 = @splat(0),
    uuid_len: usize = 0,
    path_buf: [700]u8 = @splat(0),
    path_len: usize = 0,
    image: ?*anyopaque = null,

    fn uuid(self: *const Job) []const u8 {
        return self.uuid_buf[0..self.uuid_len];
    }
    fn path(self: *const Job) []const u8 {
        return self.path_buf[0..self.path_len];
    }
};

fn encodeJob(native: *const Native, job: *Job) void {
    const ok = native.writePNG(job.image, job.path());
    native.CGImageRelease(job.image);
    job.image = null;
    job.state.store(if (ok) JOB_OK else JOB_FAILED, .release);
}

pub const DesktopPictures = struct {
    native: ?Native = null,
    ledger: Ledger = .{},
    dir_buf: [512]u8 = @splat(0),
    dir_len: usize = 0,
    /// Native side loaded and the stills folder exists.
    ready: bool = false,
    /// The user setting (`mission_control_stills`, on by default). When off, every visited Space
    /// that still shows one of our stills gets its own picture back.
    enabled: bool = false,
    /// Set when a still's frame has been copied for encoding; see takeStillStarted.
    still_started: bool = false,

    // Current visit
    cur_space_id: u64 = 0,
    cur_uuid_buf: [UUID_MAX]u8 = @splat(0),
    cur_uuid_len: usize = 0,
    last_sig: u64 = 0,
    sig_since: usize = 0,
    done: bool = false,

    job: Job = .{},

    pub fn init(self: *DesktopPictures) void {
        self.enabled = settings.getBool(SETTING_KEY, true);
        const home = std.c.getenv("HOME") orelse return;
        const dir = std.fmt.bufPrint(&self.dir_buf, "{s}" ++ STILLS_SUBDIR, .{std.mem.sliceTo(home, 0)}) catch return;
        self.dir_len = dir.len;
        var path_buf: [600]u8 = undefined;
        const lp = std.fmt.bufPrint(&path_buf, "{s}/" ++ LEDGER_NAME, .{dir}) catch return;
        var text_buf: [MAX_ENTRIES * (UUID_MAX + URL_MAX + 24)]u8 = undefined;
        if (std.Io.Dir.cwd().readFile(sc.g_io, lp, &text_buf)) |text| self.ledger.parse(text) else |_| {}
        // Off and nothing to restore: touch nothing (no folder, no frameworks).
        if (!self.enabled and self.ledger.n == 0) return;
        std.Io.Dir.cwd().createDirPath(sc.g_io, dir) catch return;
        self.native = Native.load() orelse return;
        self.pruneStills();
        self.ready = true;
    }

    /// Settings API: is the feature on?
    pub fn missionControlStills(self: *const DesktopPictures) bool {
        return self.enabled;
    }

    /// Settings API: switch the feature on or off and persist it. Turning it off hands the active
    /// Space back to the user's picture on the next tick, and every other Space on its next visit.
    pub fn setMissionControlStills(self: *DesktopPictures, on: bool) void {
        self.enabled = on;
        settings.setBool(SETTING_KEY, on);
        if (!self.ready) {
            const keep = self.enabled;
            self.init();
            self.enabled = keep;
        }
    }

    fn stillsDir(self: *const DesktopPictures) []const u8 {
        return self.dir_buf[0..self.dir_len];
    }

    fn saveLedger(self: *const DesktopPictures) void {
        var path_buf: [600]u8 = undefined;
        const lp = std.fmt.bufPrint(&path_buf, "{s}/" ++ LEDGER_NAME, .{self.stillsDir()}) catch return;
        var text_buf: [MAX_ENTRIES * (UUID_MAX + URL_MAX + 24)]u8 = undefined;
        std.Io.Dir.cwd().writeFile(sc.g_io, .{ .sub_path = lp, .data = self.ledger.serialize(&text_buf) }) catch {};
    }

    fn stillPath(self: *const DesktopPictures, space_uuid: []const u8, sig: u64, out: []u8) ?[]const u8 {
        return std.fmt.bufPrint(out, "{s}/{s}-{x}.png", .{ self.stillsDir(), space_uuid, sig }) catch null;
    }

    /// True when a desktop picture URL is one of Argus's stills (never record those as originals).
    fn isOurs(self: *const DesktopPictures, abs_url: []const u8) bool {
        _ = self;
        if (!std.mem.startsWith(u8, abs_url, "file://")) return false;
        // Stills live under ".../Application Support/Argus/Desktop Stills/"; URLs percent-encode spaces.
        return std.mem.indexOf(u8, abs_url, "/Application%20Support/Argus/Desktop%20Stills/") != null;
    }

    /// The user's own picture behind `cur` for the Space `space_uuid`. When `cur` is one of our stills
    /// it may belong to another Space: macOS seeds a new Space with the picture of the Space it was
    /// created from, so a Space made while Argus ran can show another Space's still. Then the owner's
    /// recorded original is the picture that Space would have had.
    fn originalFor(self: *DesktopPictures, space_uuid: []const u8, cur: []const u8) ?[]const u8 {
        if (!self.isOurs(cur)) return cur;
        if (self.ledger.find(space_uuid)) |e| {
            if (e.orig_len > 0) return e.original();
        }
        const owner = stillOwner(cur) orelse return null;
        const o = self.ledger.find(owner) orelse return null;
        return if (o.orig_len > 0) o.original() else null;
    }

    /// True on the tick a fresh frame should be published for the coming still: GPU Spaces only
    /// snapshot their frame after a load or while the menu is open, so the caller asks for one.
    pub fn wantsFreshFrame(self: *const DesktopPictures, frame: usize) bool {
        return self.ready and self.enabled and !self.done and self.last_sig != 0 and
            frame -% self.sig_since == SETTLE_TICKS - 2;
    }

    /// True while the active Space's still is yet to be taken: its preview must be a full frame.
    /// Otherwise previews stay small, so a GPU Space keeps no full-size copy of its frame around.
    pub fn wantsFullFrame(self: *const DesktopPictures) bool {
        return self.ready and self.enabled and !self.done and self.last_sig != 0;
    }

    /// True once after a still's frame was copied for encoding: the caller can go back to a
    /// small preview and release the full-size one.
    pub fn takeStillStarted(self: *DesktopPictures) bool {
        defer self.still_started = false;
        return self.still_started;
    }

    /// Called every tick; costs a few compares unless the active Space or its theme just changed.
    /// `sig` is `stillSignature` of the active Space; `cg_image` is its latest presented frame.
    pub fn tick(self: *DesktopPictures, space_id: u64, theme_sig: u64, cg_image: ?*anyopaque, frame: usize) void {
        if (!self.ready) return;
        const sig = if (self.enabled) theme_sig else 0;
        if (space_id != self.cur_space_id) {
            self.cur_space_id = space_id;
            self.cur_uuid_len = 0;
            if (self.native.?.spaceUUID(space_id, &self.cur_uuid_buf)) |u| self.cur_uuid_len = u.len;
            self.last_sig = sig;
            self.sig_since = frame;
            self.done = (self.cur_uuid_len == 0);
        } else if (sig != self.last_sig) {
            self.last_sig = sig;
            self.sig_since = frame;
            self.done = false;
        }

        switch (self.job.state.load(.acquire)) {
            JOB_RUNNING => return, // one encode at a time
            JOB_OK, JOB_FAILED => |st| {
                self.finishJob(st == JOB_OK, space_id, sig);
                self.job.state.store(JOB_IDLE, .release);
            },
            else => {},
        }

        if (self.done) return;
        const space_uuid = self.cur_uuid_buf[0..self.cur_uuid_len];

        if (sig == 0) {
            // Passthrough, or the feature is off: hand the Space back to the user's own picture.
            self.restore(space_uuid);
            self.done = true;
            return;
        }
        if (self.ledger.find(space_uuid)) |e| {
            if (e.applied_sig == sig) {
                self.done = true; // this exact still is already set: never reload it
                return;
            }
        }
        if (cg_image == null or frame -% self.sig_since < SETTLE_TICKS) return;
        self.done = true;
        self.startJob(space_id, space_uuid, sig, cg_image);
    }

    fn startJob(self: *DesktopPictures, space_id: u64, space_uuid: []const u8, sig: u64, cg_image: ?*anyopaque) void {
        const n = &self.native.?;
        const p = self.stillPath(space_uuid, sig, &self.job.path_buf) orelse return;
        self.job.path_len = p.len;
        @memcpy(self.job.uuid_buf[0..space_uuid.len], space_uuid);
        self.job.uuid_len = space_uuid.len;
        self.job.space_id = space_id;
        self.job.sig = sig;
        self.job.image = n.copyImage(cg_image) orelse return;
        self.job.state.store(JOB_RUNNING, .release);
        const t = std.Thread.spawn(.{}, encodeJob, .{ n, &self.job }) catch {
            n.CGImageRelease(self.job.image);
            self.job.image = null;
            self.job.state.store(JOB_IDLE, .release);
            return;
        };
        t.detach();
        self.still_started = true;
    }

    /// Main thread, after the encode: set the still only if the user is still on that Space and
    /// it still shows the same theme; otherwise drop the file (the next visit makes a new one).
    fn finishJob(self: *DesktopPictures, ok: bool, space_id: u64, sig: u64) void {
        const job = &self.job;
        if (!ok) return;
        if (job.space_id != space_id or job.sig != sig) {
            unlinkPath(job.path());
            return;
        }
        const n = &self.native.?;
        var cur_buf: [URL_MAX]u8 = undefined;
        // No readable picture to restore later (nil or non-file wallpaper): leave this Space alone.
        const cur = n.currentDesktopURL(&cur_buf) orelse return unlinkPath(job.path());
        // First visit, the user picked a new picture since, or a Space seeded with another Space's still.
        var orig_buf: [URL_MAX]u8 = undefined;
        const orig_src = self.originalFor(job.uuid(), cur) orelse return unlinkPath(job.path());
        @memcpy(orig_buf[0..orig_src.len], orig_src);
        const orig = orig_buf[0..orig_src.len];
        const e = self.ledger.findOrAdd(job.uuid()) orelse return unlinkPath(job.path());
        e.setOriginal(orig);
        var url_buf: [URL_MAX]u8 = undefined;
        const url = fileURL(job.path(), &url_buf) orelse return unlinkPath(job.path());
        if (!n.setDesktopURL(url)) return unlinkPath(job.path());
        e.applied_sig = sig;
        self.saveLedger();
    }

    /// Hands the active Space back to the user's own picture if it shows one of our stills,
    /// whether Argus set it there or macOS copied it in when the Space was created. Still files
    /// are left in place: other Spaces may show the same file (they are pruned after PRUNE_DAYS).
    fn restore(self: *DesktopPictures, space_uuid: []const u8) void {
        const n = &self.native.?;
        var cur_buf: [URL_MAX]u8 = undefined;
        if (n.currentDesktopURL(&cur_buf)) |cur| {
            // Only undo our own still; if the user chose another picture meanwhile, keep theirs.
            if (self.isOurs(cur) and !self.setUserPicture(space_uuid, cur)) {
                return; // nothing settable: keep the still (and the ledger) rather than a broken picture
            }
        }
        if (self.ledger.find(space_uuid)) |e| {
            if (e.applied_sig != 0) {
                e.applied_sig = 0;
                self.saveLedger();
            }
        }
    }

    /// Sets the user's own picture behind our still `cur`. macOS refuses a file that has since been
    /// moved or deleted, so this falls back to any other original the user had that still exists.
    fn setUserPicture(self: *DesktopPictures, space_uuid: []const u8, cur: []const u8) bool {
        const n = &self.native.?;
        if (self.originalFor(space_uuid, cur)) |orig| {
            if (n.setDesktopURL(orig)) return true;
        }
        for (self.ledger.entries[0..self.ledger.n]) |*e| {
            if (e.orig_len > 0 and !self.isOurs(e.original()) and n.setDesktopURL(e.original())) return true;
        }
        return false;
    }

    /// Deletes stills older than PRUNE_DAYS that no Space is known to show. Startup only.
    fn pruneStills(self: *const DesktopPictures) void {
        var dir = std.Io.Dir.cwd().openDir(sc.g_io, self.stillsDir(), .{ .iterate = true }) catch return;
        defer dir.close(sc.g_io);
        const now_ns = std.Io.Clock.real.now(sc.g_io).nanoseconds;
        var it = dir.iterate();
        while (it.next(sc.g_io) catch null) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".png")) continue;
            var applied = false;
            for (self.ledger.entries[0..self.ledger.n]) |*e| {
                if (e.applied_sig == 0) continue;
                var nb: [UUID_MAX + 24]u8 = undefined;
                const want = std.fmt.bufPrint(&nb, "{s}-{x}.png", .{ e.uuid(), e.applied_sig }) catch continue;
                if (std.mem.eql(u8, want, entry.name)) applied = true;
            }
            if (applied) continue;
            const st = dir.statFile(sc.g_io, entry.name, .{}) catch continue;
            if (now_ns - st.mtime.nanoseconds > PRUNE_DAYS * std.time.ns_per_day) dir.deleteFile(sc.g_io, entry.name) catch {};
        }
    }

    /// The one picture of the user's that every Space goes back to on quit, when there is exactly
    /// one and at least one Space shows a still of ours; else null. `pics` are all current Spaces
    /// with the picture macOS has for each (url_len 0: unknown, which rules this out).
    pub fn quitPicture(self: *DesktopPictures, pics: []const Pic) ?[]const u8 {
        var common: ?[]const u8 = null;
        var any_ours = false;
        for (pics) |*p| {
            if (p.url_len == 0) return null;
            const ours = self.isOurs(p.url());
            const own = self.originalFor(p.uuid(), p.url()) orelse return null;
            if (self.isOurs(own)) return null;
            any_ours = any_ours or ours;
            if (common) |c| {
                if (!std.mem.eql(u8, c, own)) return null;
            } else common = own;
        }
        return if (any_ours) common else null;
    }

    /// On quit, when every Space goes back to the same picture: set it on all Spaces at once.
    /// That also makes it the picture new Spaces start with. False when it does not apply.
    fn restoreAllForQuit(self: *DesktopPictures) bool {
        const n = &self.native.?;
        if (n.all_spaces_key == null) return false;
        var pics: [MAX_ENTRIES]Pic = undefined;
        const count = n.currentSpaceUUIDs(&pics) orelse return false;
        if (!n.storePictures(pics[0..count])) return false;
        var url_buf: [URL_MAX]u8 = undefined;
        const pick = self.quitPicture(pics[0..count]) orelse return false;
        @memcpy(url_buf[0..pick.len], pick);
        if (!n.setDesktopURLOn(url_buf[0..pick.len], true)) return false;
        for (self.ledger.entries[0..self.ledger.n]) |*e| e.applied_sig = 0;
        self.saveLedger();
        return true;
    }

    /// On quit: every Space back to the user's picture in one call when they all share one;
    /// otherwise the active Space. Other Spaces cannot be reached through the public API without
    /// visiting them; their originals stay in the ledger and come back on their next visit after
    /// Argus starts again (immediately for a Space that is no longer themed, or when the feature
    /// is off).
    pub fn restoreForQuit(self: *DesktopPictures, space_id: u64) void {
        if (!self.ready) return;
        if (self.restoreAllForQuit()) return;
        var ubuf: [UUID_MAX]u8 = @splat(0);
        const u = self.native.?.spaceUUID(space_id, &ubuf) orelse return;
        self.restore(u);
        // macOS also copies the last picture set into the default that new Spaces start with, so a
        // still set earlier on another Space would seed every Space created after Argus quits.
        // Setting the active Space's own picture again makes a user picture the last one set.
        var cur_buf: [URL_MAX]u8 = undefined;
        if (self.native.?.currentDesktopURL(&cur_buf)) |cur| {
            if (!self.isOurs(cur)) _ = self.native.?.setDesktopURL(cur);
        }
    }
};

/// The Space UUID a still URL belongs to: stills are named `<space-uuid>-<sig hex>.png`.
pub fn stillOwner(abs_url: []const u8) ?[]const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, abs_url, '/') orelse return null;
    const name = abs_url[slash + 1 ..];
    if (!std.mem.endsWith(u8, name, ".png")) return null;
    const dash = std.mem.lastIndexOfScalar(u8, name, '-') orelse return null;
    return if (dash > 0) name[0..dash] else null;
}

fn unlinkPath(path: []const u8) void {
    var z: [701]u8 = undefined;
    if (path.len >= z.len) return;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    _ = std.c.unlink(@ptrCast(&z));
}

/// Percent-encodes an absolute POSIX path into a file:// URL string.
pub fn fileURL(path: []const u8, out: []u8) ?[]const u8 {
    const head = "file://";
    if (out.len < head.len) return null;
    @memcpy(out[0..head.len], head);
    var pos: usize = head.len;
    for (path) |c| {
        const plain = std.ascii.isAlphanumeric(c) or c == '/' or c == '-' or c == '_' or c == '.' or c == '~';
        if (plain) {
            if (pos + 1 > out.len) return null;
            out[pos] = c;
            pos += 1;
        } else {
            if (pos + 3 > out.len) return null;
            _ = std.fmt.bufPrint(out[pos .. pos + 3], "%{X:0>2}", .{c}) catch return null;
            pos += 3;
        }
    }
    return out[0..pos];
}

test "still signature: passthrough is 0, themes change with path and mtime" {
    var sp: sc.SpaceConfig = .{ .mode = .passthrough };
    try std.testing.expectEqual(@as(u64, 0), stillSignature(&sp));
    sp.mode = .custom_shader;
    sp.setPath("themes/Cygnus_A.zig");
    const a = stillSignature(&sp);
    try std.testing.expect(a != 0);
    try std.testing.expectEqual(a, stillSignature(&sp));
    sp.last_mtime = 42;
    const b = stillSignature(&sp);
    try std.testing.expect(b != a);
    sp.setPath("themes/Night_Tide.metal");
    try std.testing.expect(stillSignature(&sp) != b);
}

test "ledger round-trips Spaces with an original, applied or restored" {
    var l: Ledger = .{};
    const e1 = l.findOrAdd("AAAA-1").?;
    e1.applied_sig = 0xbeef;
    e1.setOriginal("file:///Users/me/Pictures/Lake%20Tahoe.heic");
    const e2 = l.findOrAdd("BBBB-2").?;
    e2.setOriginal("file:///x.png"); // applied_sig 0: restored, but its original is kept for cloned Spaces
    _ = l.findOrAdd("CCCC-3").?; // no original: not persisted
    try std.testing.expectEqual(e1, l.findOrAdd("AAAA-1").?);

    var buf: [4096]u8 = undefined;
    const text = l.serialize(&buf);
    var l2: Ledger = .{};
    l2.parse(text);
    try std.testing.expectEqual(@as(usize, 2), l2.n);
    const r = l2.find("AAAA-1").?;
    try std.testing.expectEqual(@as(u64, 0xbeef), r.applied_sig);
    try std.testing.expectEqualStrings("file:///Users/me/Pictures/Lake%20Tahoe.heic", r.original());
    try std.testing.expectEqual(@as(u64, 0), l2.find("BBBB-2").?.applied_sig);
    try std.testing.expect(l2.find("CCCC-3") == null);
}

test "ledger evicts a restored entry when full, never one holding a still" {
    var l: Ledger = .{};
    var name: [16]u8 = undefined;
    for (0..MAX_ENTRIES) |i| {
        const u = try std.fmt.bufPrint(&name, "U{d}", .{i});
        const e = l.findOrAdd(u).?;
        e.applied_sig = if (i == 5) 0 else 1;
    }
    try std.testing.expect(l.findOrAdd("NEW") != null);
    try std.testing.expect(l.find("U5") == null);
    try std.testing.expect(l.find("U4") != null);
    for (l.entries[0..l.n]) |*e| e.applied_sig = 1;
    try std.testing.expect(l.findOrAdd("NEWER") == null);
}

test "still owner is the Space UUID in the still's file name" {
    try std.testing.expectEqualStrings(
        "75F2A850-DE83-442F-952E-62D360F90EA9",
        stillOwner("file:///Users/me/Library/Application%20Support/Argus/Desktop%20Stills/75F2A850-DE83-442F-952E-62D360F90EA9-8369291325f4e51a.png").?,
    );
    try std.testing.expect(stillOwner("file:///Users/me/Pictures/a.jpeg") == null);
}

test "file URLs percent-encode spaces and keep path separators" {
    var buf: [256]u8 = undefined;
    const u = fileURL("/Users/me/Library/Application Support/Argus/Desktop Stills/AB-1f.png", &buf).?;
    try std.testing.expectEqualStrings("file:///Users/me/Library/Application%20Support/Argus/Desktop%20Stills/AB-1f.png", u);
}

fn testPic(space_uuid: []const u8, url: []const u8) Pic {
    var p: Pic = .{};
    @memcpy(p.uuid_buf[0..space_uuid.len], space_uuid);
    p.uuid_len = space_uuid.len;
    p.setURL(url);
    return p;
}

const STILL_A = "file:///Users/me/Library/Application%20Support/Argus/Desktop%20Stills/AAAA-1-beef.png";
const LAKE = "file:///Users/me/Pictures/Lake%20Tahoe.heic";

test "quit: every Space goes back to the one picture they share" {
    var dp: DesktopPictures = .{};
    dp.ledger.findOrAdd("AAAA-1").?.setOriginal(LAKE);
    const pics = [_]Pic{
        testPic("AAAA-1", STILL_A), // our still, original recorded
        testPic("BBBB-2", LAKE), // never themed
        testPic("CCCC-3", STILL_A), // seeded by macOS from AAAA-1's still when it was created
    };
    try std.testing.expectEqualStrings(LAKE, dp.quitPicture(&pics).?);
}

test "quit: Spaces with different pictures are restored one at a time" {
    var dp: DesktopPictures = .{};
    dp.ledger.findOrAdd("AAAA-1").?.setOriginal(LAKE);
    const pics = [_]Pic{ testPic("AAAA-1", STILL_A), testPic("BBBB-2", "file:///Users/me/Pictures/Other.jpg") };
    try std.testing.expect(dp.quitPicture(&pics) == null);
}

test "quit: nothing of ours on screen, or a picture we cannot read, sets nothing" {
    var dp: DesktopPictures = .{};
    dp.ledger.findOrAdd("AAAA-1").?.setOriginal(LAKE);
    const plain = [_]Pic{ testPic("AAAA-1", LAKE), testPic("BBBB-2", LAKE) };
    try std.testing.expect(dp.quitPicture(&plain) == null);
    const unknown = [_]Pic{ testPic("AAAA-1", STILL_A), testPic("BBBB-2", "") }; // e.g. a dynamic wallpaper
    try std.testing.expect(dp.quitPicture(&unknown) == null);
    var orphan: DesktopPictures = .{}; // a still whose original was never recorded
    const pics = [_]Pic{testPic("AAAA-1", STILL_A)};
    try std.testing.expect(orphan.quitPicture(&pics) == null);
}

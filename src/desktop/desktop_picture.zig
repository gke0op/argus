// ============================================================================
// ARGUS DESKTOP // src/desktop/desktop_picture.zig
//
// Mission Control Spaces-bar stills. The Spaces bar draws each Space from its macOS desktop
// picture and leaves out Argus's desktop-level windows, so a theme Space would show the system
// wallpaper there. When a theme Space is visited (or a theme lands on the active Space) and has
// settled for a second, its current frame is written once to a PNG and set as that Space's
// desktop picture. The user's own picture is recorded first and put back when the Space returns
// to passthrough ("macOS Default") or Argus quits.
//
// `setDesktopImageURL:forScreen:` only reaches the active Space, so all of this happens per Space,
// as each one is visited. Work is once per visit or theme load, never per frame: the per-tick
// path is a few integer compares. The ledger on disk keeps the originals across restarts, so a
// Space that still shows a still after a crash or quit is restored on its next visit.
// ============================================================================

const std = @import("std");
const sc = @import("space_config.zig");

pub const MAX_ENTRIES: usize = 32;
pub const UUID_MAX: usize = 48;
pub const URL_MAX: usize = 1024;
/// Ticks a theme must run on the active Space before its still is taken (30 ticks = 1 s at 30 Hz),
/// so the still is a developed frame, not the first one after a load.
pub const SETTLE_TICKS: usize = 30;

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
            if (e.applied_sig == 0) continue; // only Spaces that still need restoring
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
            if (sig == 0 or orig.len > URL_MAX) continue;
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

const Native = struct {
    getClass: *const fn ([*:0]const u8) callconv(.c) Id,
    sel: *const fn ([*:0]const u8) callconv(.c) Sel,
    msg0: Msg0,
    msg1: Msg1,
    msgIdx: MsgIdx,
    msgCStr: MsgCStr,
    msgRetCStr: MsgRetCStr,
    msgSetDesktop: MsgSetDesktop,
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
    CGSMainConnectionID: *const fn () callconv(.c) u32,
    CGSCopyManagedDisplaySpaces: *const fn (u32) callconv(.c) ?*anyopaque,
    key_spaces: ?*anyopaque,
    key_id64: ?*anyopaque,
    key_uuid: ?*anyopaque,
    uti_png: ?*anyopaque,

    fn load() ?Native {
        const objc = std.c.dlopen("/usr/lib/libobjc.A.dylib", .{ .LAZY = true }) orelse return null;
        const cf = std.c.dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", .{ .LAZY = true }) orelse return null;
        const iio = std.c.dlopen("/System/Library/Frameworks/ImageIO.framework/ImageIO", .{ .LAZY = true }) orelse return null;
        const sky = std.c.dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", .{ .LAZY = true }) orelse return null;
        _ = std.c.dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", .{ .LAZY = true }) orelse return null;
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
            .CGSCopyManagedDisplaySpaces = @ptrCast(@alignCast(std.c.dlsym(sky, "CGSCopyManagedDisplaySpaces") orelse return null)),
            .key_spaces = mkstr(null, "Spaces", 0x08000100),
            .key_id64 = mkstr(null, "id64", 0x08000100),
            .key_uuid = mkstr(null, "uuid", 0x08000100),
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

    fn setDesktopURL(self: *const Native, abs_url: []const u8) bool {
        var buf: [URL_MAX + 1]u8 = undefined;
        if (abs_url.len > URL_MAX) return false;
        @memcpy(buf[0..abs_url.len], abs_url);
        buf[abs_url.len] = 0;
        const screen = self.mainScreen() orelse return false;
        const str = self.msgCStr(self.getClass("NSString"), self.sel("stringWithUTF8String:"), @ptrCast(&buf)) orelse return false;
        const url = self.msg1(self.getClass("NSURL"), self.sel("URLWithString:"), str) orelse return false;
        const opts = self.msg0(self.getClass("NSDictionary"), self.sel("dictionary"));
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

pub const DesktopPictures = struct {
    native: ?Native = null,
    ledger: Ledger = .{},
    dir_buf: [512]u8 = @splat(0),
    dir_len: usize = 0,
    enabled: bool = false,

    // Current visit
    cur_space_id: u64 = 0,
    cur_uuid_buf: [UUID_MAX]u8 = @splat(0),
    cur_uuid_len: usize = 0,
    last_sig: u64 = 0,
    sig_since: usize = 0,
    done: bool = false,

    pub fn init(self: *DesktopPictures) void {
        const home = std.c.getenv("HOME") orelse return;
        const dir = std.fmt.bufPrint(&self.dir_buf, "{s}" ++ STILLS_SUBDIR, .{std.mem.sliceTo(home, 0)}) catch return;
        self.dir_len = dir.len;
        std.Io.Dir.cwd().createDirPath(sc.g_io, dir) catch return;
        self.native = Native.load() orelse return;
        var path_buf: [600]u8 = undefined;
        const lp = std.fmt.bufPrint(&path_buf, "{s}/" ++ LEDGER_NAME, .{dir}) catch return;
        var text_buf: [MAX_ENTRIES * (UUID_MAX + URL_MAX + 24)]u8 = undefined;
        if (std.Io.Dir.cwd().readFile(sc.g_io, lp, &text_buf)) |text| self.ledger.parse(text) else |_| {}
        self.enabled = true;
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
        const prefix = "file://";
        if (!std.mem.startsWith(u8, abs_url, prefix)) return false;
        // Stills live under ".../Application Support/Argus/Desktop Stills/"; URLs percent-encode spaces.
        return std.mem.indexOf(u8, abs_url, "/Application%20Support/Argus/Desktop%20Stills/") != null or
            std.mem.indexOf(u8, abs_url[prefix.len..], self.stillsDir()) != null;
    }

    /// Called every tick; costs a few compares unless the active Space or its theme just changed.
    /// `sig` is `stillSignature` of the active Space; `cg_image` is its latest presented frame.
    pub fn tick(self: *DesktopPictures, space_id: u64, sig: u64, cg_image: ?*anyopaque, frame: usize) void {
        if (!self.enabled) return;
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
        if (self.done) return;
        const space_uuid = self.cur_uuid_buf[0..self.cur_uuid_len];

        if (sig == 0) {
            // Passthrough: hand the Space back to the user's own picture, right away.
            if (self.ledger.find(space_uuid)) |e| self.restore(e, space_uuid);
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
        self.apply(space_uuid, sig, cg_image);
    }

    fn apply(self: *DesktopPictures, space_uuid: []const u8, sig: u64, cg_image: ?*anyopaque) void {
        const n = &self.native.?;
        var cur_buf: [URL_MAX]u8 = undefined;
        // No readable picture to restore later (nil or non-file wallpaper): leave this Space alone.
        const cur = n.currentDesktopURL(&cur_buf) orelse return;
        const e = self.ledger.findOrAdd(space_uuid) orelse return;
        if (!self.isOurs(cur)) {
            e.setOriginal(cur); // first visit, or the user picked a new picture since
        } else if (e.orig_len == 0) {
            return; // one of our stills with no recorded original: nothing safe to restore to
        }

        var path_buf: [700]u8 = undefined;
        const path = self.stillPath(space_uuid, sig, &path_buf) orelse return;
        if (!n.writePNG(cg_image, path)) return;
        var url_buf: [URL_MAX]u8 = undefined;
        const url = fileURL(path, &url_buf) orelse return;
        if (!n.setDesktopURL(url)) {
            unlinkPath(path);
            return;
        }
        const old_sig = e.applied_sig;
        e.applied_sig = sig;
        self.saveLedger();
        if (old_sig != 0 and old_sig != sig) self.deleteStill(space_uuid, old_sig);
    }

    fn restore(self: *DesktopPictures, e: *Entry, space_uuid: []const u8) void {
        if (e.applied_sig == 0) return;
        const n = &self.native.?;
        var cur_buf: [URL_MAX]u8 = undefined;
        const cur = n.currentDesktopURL(&cur_buf);
        // Only undo our own still; if the user chose another picture meanwhile, keep theirs.
        if (cur == null or self.isOurs(cur.?)) {
            if (e.orig_len > 0) _ = n.setDesktopURL(e.original());
        }
        self.deleteStill(space_uuid, e.applied_sig);
        e.applied_sig = 0;
        self.saveLedger();
    }

    fn deleteStill(self: *const DesktopPictures, space_uuid: []const u8, sig: u64) void {
        var path_buf: [700]u8 = undefined;
        if (self.stillPath(space_uuid, sig, &path_buf)) |p| unlinkPath(p);
    }

    /// On quit: restore the active Space. Other Spaces cannot be reached through the public API
    /// without visiting them; their originals stay in the ledger and are restored on next visit
    /// after Argus starts again (a passthrough Space restores immediately; a theme Space keeps
    /// its still, which matches what Argus draws there).
    pub fn restoreActiveForQuit(self: *DesktopPictures, space_id: u64) void {
        if (!self.enabled) return;
        var ubuf: [UUID_MAX]u8 = @splat(0);
        const u = self.native.?.spaceUUID(space_id, &ubuf) orelse return;
        if (self.ledger.find(u)) |e| self.restore(e, u);
    }
};

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
    sp.setPath("themes/Echo.zig");
    const a = stillSignature(&sp);
    try std.testing.expect(a != 0);
    try std.testing.expectEqual(a, stillSignature(&sp));
    sp.last_mtime = 42;
    const b = stillSignature(&sp);
    try std.testing.expect(b != a);
    sp.setPath("themes/Gemini_Wormhole.zig");
    try std.testing.expect(stillSignature(&sp) != b);
}

test "ledger round-trips Spaces that still need restoring and drops restored ones" {
    var l: Ledger = .{};
    const e1 = l.findOrAdd("AAAA-1").?;
    e1.applied_sig = 0xbeef;
    e1.setOriginal("file:///Users/me/Pictures/Lake%20Tahoe.heic");
    const e2 = l.findOrAdd("BBBB-2").?;
    e2.setOriginal("file:///x.png"); // applied_sig 0: already restored, not persisted
    try std.testing.expectEqual(e1, l.findOrAdd("AAAA-1").?);

    var buf: [4096]u8 = undefined;
    const text = l.serialize(&buf);
    var l2: Ledger = .{};
    l2.parse(text);
    try std.testing.expectEqual(@as(usize, 1), l2.n);
    const r = l2.find("AAAA-1").?;
    try std.testing.expectEqual(@as(u64, 0xbeef), r.applied_sig);
    try std.testing.expectEqualStrings("file:///Users/me/Pictures/Lake%20Tahoe.heic", r.original());
    try std.testing.expect(l2.find("BBBB-2") == null);
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

test "file URLs percent-encode spaces and keep path separators" {
    var buf: [256]u8 = undefined;
    const u = fileURL("/Users/me/Library/Application Support/Argus/Desktop Stills/AB-1f.png", &buf).?;
    try std.testing.expectEqualStrings("file:///Users/me/Library/Application%20Support/Argus/Desktop%20Stills/AB-1f.png", u);
}

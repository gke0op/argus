// ============================================================================
// ARGUS LINUX // src/linux/x11.zig
//
// The X11 wire protocol, spoken directly over the server's unix socket with raw Linux
// syscalls: no libX11, no libxcb, no libc. Only what a wallpaper needs: connect (with the
// MIT-MAGIC-COOKIE-1 from $XAUTHORITY when the server wants one), one desktop-type window,
// one GC, and PutImage in row bands that fit the server's maximum request length.
// ============================================================================

const std = @import("std");
const linux = std.os.linux;

pub const Error = error{ SocketFailed, ConnectFailed, WriteFailed, ReadFailed, SetupRefused, NoTrueColor, BadDisplay };

pub const Shm = struct {
    seg: u32,
    opcode: u8,
    completion: u8, // the extension's first event code: ShmCompletion
    mem: []u32,
    w: usize,
    h: usize,
    pending: bool = false,
};

pub const Conn = struct {
    fd: i32,
    id_base: u32,
    id_mask: u32,
    next_id: u32 = 0,
    max_req_bytes: usize,
    root: u32,
    width: u16,
    height: u16,
    depth: u8,
    /// Byte offset of red/green/blue within a 32-bit LSB-first ZPixmap pixel.
    red_shift: u5,
    green_shift: u5,
    blue_shift: u5,

    pub fn newId(self: *Conn) u32 {
        self.next_id += 1;
        return self.id_base | (self.next_id & self.id_mask);
    }

    fn send(self: *Conn, bytes: []const u8) Error!void {
        var off: usize = 0;
        while (off < bytes.len) {
            const rc = linux.write(self.fd, bytes[off..].ptr, bytes.len - off);
            if (linux.errno(rc) == .INTR) continue;
            if (linux.errno(rc) != .SUCCESS or rc == 0) return error.WriteFailed;
            off += rc;
        }
    }

    fn recvExact(self: *Conn, buf: []u8) Error!void {
        var off: usize = 0;
        while (off < buf.len) {
            const rc = linux.read(self.fd, buf[off..].ptr, buf.len - off);
            if (linux.errno(rc) == .INTR) continue;
            if (linux.errno(rc) != .SUCCESS or rc == 0) return error.ReadFailed;
            off += rc;
        }
    }

    /// Opens `:N` (DISPLAY) at /tmp/.X11-unix/XN. `cookie` is the 16-byte MIT-MAGIC-COOKIE-1
    /// or null for servers without access control (Xvfb's default).
    pub fn open(display: u32, cookie: ?[16]u8) Error!Conn {
        const fd_rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
        if (linux.errno(fd_rc) != .SUCCESS) return error.SocketFailed;
        const fd: i32 = @intCast(fd_rc);

        var addr = linux.sockaddr.un{ .family = linux.AF.UNIX, .path = undefined };
        @memset(&addr.path, 0);
        const p = std.fmt.bufPrint(&addr.path, "/tmp/.X11-unix/X{d}", .{display}) catch return error.BadDisplay;
        if (linux.errno(linux.connect(fd, @ptrCast(&addr), @intCast(@offsetOf(linux.sockaddr.un, "path") + p.len))) != .SUCCESS)
            return error.ConnectFailed;

        var c: Conn = undefined;
        c.fd = fd;
        c.next_id = 0;

        // Setup request: little-endian ('l'), protocol 11.0, optional auth.
        var req: [12 + 20 + 16]u8 = @splat(0);
        req[0] = 'l';
        std.mem.writeInt(u16, req[2..4], 11, .little);
        var req_len: usize = 12;
        if (cookie) |ck| {
            std.mem.writeInt(u16, req[6..8], 18, .little);
            std.mem.writeInt(u16, req[8..10], 16, .little);
            @memcpy(req[12..30], "MIT-MAGIC-COOKIE-1");
            @memcpy(req[32..48], &ck); // name padded 18 -> 20
            req_len = 48;
        }
        try c.send(req[0..req_len]);

        var head: [8]u8 = undefined;
        try c.recvExact(&head);
        const extra = @as(usize, std.mem.readInt(u16, head[6..8], .little)) * 4;
        var body_buf: [65536]u8 = undefined;
        if (extra > body_buf.len) return error.SetupRefused;
        const body = body_buf[0..extra];
        try c.recvExact(body);
        if (head[0] != 1) return error.SetupRefused;

        c.id_base = std.mem.readInt(u32, body[4..8], .little);
        c.id_mask = std.mem.readInt(u32, body[8..12], .little);
        const vendor_len = std.mem.readInt(u16, body[16..18], .little);
        c.max_req_bytes = @as(usize, std.mem.readInt(u16, body[18..20], .little)) * 4;
        const n_formats = body[21];
        var o: usize = 32 + ((vendor_len + 3) & ~@as(usize, 3)) + 8 * @as(usize, n_formats);

        // First screen.
        c.root = std.mem.readInt(u32, body[o..][0..4], .little);
        c.width = std.mem.readInt(u16, body[o + 20 ..][0..2], .little);
        c.height = std.mem.readInt(u16, body[o + 22 ..][0..2], .little);
        const root_visual = std.mem.readInt(u32, body[o + 32 ..][0..4], .little);
        c.depth = body[o + 38];
        const n_depths = body[o + 39];
        o += 40;
        // Find the root visual to read its channel masks (TrueColor expected).
        var found = false;
        for (0..n_depths) |_| {
            const n_vis = std.mem.readInt(u16, body[o + 2 ..][0..2], .little);
            o += 8;
            for (0..n_vis) |_| {
                if (std.mem.readInt(u32, body[o..][0..4], .little) == root_visual) {
                    if (body[o + 4] != 4) return error.NoTrueColor; // class TrueColor
                    c.red_shift = @intCast(@ctz(std.mem.readInt(u32, body[o + 8 ..][0..4], .little)));
                    c.green_shift = @intCast(@ctz(std.mem.readInt(u32, body[o + 12 ..][0..4], .little)));
                    c.blue_shift = @intCast(@ctz(std.mem.readInt(u32, body[o + 16 ..][0..4], .little)));
                    found = true;
                }
                o += 24;
            }
        }
        if (!found) return error.NoTrueColor;
        return c;
    }

    pub fn internAtom(self: *Conn, name: []const u8) Error!u32 {
        var r: [64]u8 = @splat(0);
        const padded = (name.len + 3) & ~@as(usize, 3);
        r[0] = 16; // InternAtom
        std.mem.writeInt(u16, r[2..4], @intCast(2 + padded / 4), .little);
        std.mem.writeInt(u16, r[4..6], @intCast(name.len), .little);
        @memcpy(r[8..][0..name.len], name);
        try self.send(r[0 .. 8 + padded]);
        var rep: [32]u8 = undefined;
        while (true) { // skip any queued events/errors until the reply
            try self.recvExact(&rep);
            if (rep[0] == 1) break;
            if (rep[0] == 0) return error.ReadFailed;
        }
        return std.mem.readInt(u32, rep[8..12], .little);
    }

    /// A full-screen, borderless InputOutput window with a black background.
    pub fn createWindow(self: *Conn) Error!u32 {
        const wid = self.newId();
        var r: [36]u8 = @splat(0);
        r[0] = 1; // CreateWindow
        r[1] = self.depth;
        std.mem.writeInt(u16, r[2..4], 9, .little);
        std.mem.writeInt(u32, r[4..8], wid, .little);
        std.mem.writeInt(u32, r[8..12], self.root, .little);
        std.mem.writeInt(u16, r[16..18], self.width, .little);
        std.mem.writeInt(u16, r[18..20], self.height, .little);
        std.mem.writeInt(u16, r[22..24], 1, .little); // InputOutput
        std.mem.writeInt(u32, r[28..32], 0x2, .little); // CWBackPixel
        std.mem.writeInt(u32, r[32..36], 0, .little); // black
        try self.send(&r);
        return wid;
    }

    pub fn changeProperty32(self: *Conn, win: u32, prop: u32, kind: u32, values: []const u32) Error!void {
        var r: [24 + 4 * 8]u8 = @splat(0);
        r[0] = 18; // ChangeProperty, mode Replace
        std.mem.writeInt(u16, r[2..4], @intCast(6 + values.len), .little);
        std.mem.writeInt(u32, r[4..8], win, .little);
        std.mem.writeInt(u32, r[8..12], prop, .little);
        std.mem.writeInt(u32, r[12..16], kind, .little);
        r[16] = 32;
        std.mem.writeInt(u32, r[20..24], @intCast(values.len), .little);
        for (values, 0..) |v, i| std.mem.writeInt(u32, r[24 + 4 * i ..][0..4], v, .little);
        try self.send(r[0 .. 24 + 4 * values.len]);
    }

    pub fn changePropertyString(self: *Conn, win: u32, prop: u32, s: []const u8) Error!void {
        var r: [24 + 64]u8 = @splat(0);
        const padded = (s.len + 3) & ~@as(usize, 3);
        r[0] = 18;
        std.mem.writeInt(u16, r[2..4], @intCast(6 + padded / 4), .little);
        std.mem.writeInt(u32, r[4..8], win, .little);
        std.mem.writeInt(u32, r[8..12], prop, .little);
        std.mem.writeInt(u32, r[12..16], 31, .little); // STRING
        r[16] = 8;
        std.mem.writeInt(u32, r[20..24], @intCast(s.len), .little);
        @memcpy(r[24..][0..s.len], s);
        try self.send(r[0 .. 24 + padded]);
    }

    pub fn mapWindow(self: *Conn, win: u32) Error!void {
        var r: [8]u8 = @splat(0);
        r[0] = 8;
        std.mem.writeInt(u16, r[2..4], 2, .little);
        std.mem.writeInt(u32, r[4..8], win, .little);
        try self.send(&r);
    }

    pub fn createGC(self: *Conn, drawable: u32) Error!u32 {
        const gc = self.newId();
        var r: [16]u8 = @splat(0);
        r[0] = 55;
        std.mem.writeInt(u16, r[2..4], 4, .little);
        std.mem.writeInt(u32, r[4..8], gc, .little);
        std.mem.writeInt(u32, r[8..12], drawable, .little);
        try self.send(&r);
        return gc;
    }

    /// Sends an Argus frame (memory bytes [R, G, B, A] per pixel) as ZPixmap row bands.
    /// `scratch` holds one band: at least max_req_bytes bytes.
    pub fn putFrame(self: *Conn, win: u32, gc: u32, px: []const u32, w: usize, h: usize, scratch: []u8) Error!void {
        const rows_per = @max(1, (self.max_req_bytes - 24) / (w * 4));
        var y: usize = 0;
        while (y < h) : (y += rows_per) {
            const n = @min(rows_per, h - y);
            const data_len = n * w * 4;
            const r = scratch[0 .. 24 + data_len];
            @memset(r[0..24], 0);
            r[0] = 72; // PutImage
            r[1] = 2; // ZPixmap
            std.mem.writeInt(u16, r[2..4], @intCast((24 + data_len) / 4), .little);
            std.mem.writeInt(u32, r[4..8], win, .little);
            std.mem.writeInt(u32, r[8..12], gc, .little);
            std.mem.writeInt(u16, r[12..14], @intCast(w), .little);
            std.mem.writeInt(u16, r[14..16], @intCast(n), .little);
            std.mem.writeInt(i16, r[18..20], @intCast(y), .little);
            r[21] = self.depth;
            const out: []align(1) u32 = std.mem.bytesAsSlice(u32, r[24..]);
            for (px[y * w ..][0 .. n * w], out) |p, *d| {
                d.* = ((p & 0xFF) << self.red_shift) | (((p >> 8) & 0xFF) << self.green_shift) | (((p >> 16) & 0xFF) << self.blue_shift);
            }
            try self.send(r);
        }
    }

    /// MIT-SHM: a w x h frame in System V shared memory that the server reads in place, so a
    /// frame costs a 40-byte request instead of w*h*4 bytes through the socket. Null when the
    /// server lacks the extension (or isn't local).
    pub fn shmInit(self: *Conn, w: usize, h: usize) ?Shm {
        var q: [20]u8 = @splat(0);
        const name = "MIT-SHM";
        q[0] = 98; // QueryExtension
        std.mem.writeInt(u16, q[2..4], 2 + 2, .little);
        std.mem.writeInt(u16, q[4..6], name.len, .little);
        @memcpy(q[8..][0..name.len], name);
        self.send(q[0..16]) catch return null;
        var rep: [32]u8 = undefined;
        while (true) {
            self.recvExact(&rep) catch return null;
            if (rep[0] == 1) break;
            if (rep[0] == 0) return null;
        }
        if (rep[8] == 0) return null; // not present
        const opcode = rep[9];
        const first_event = rep[10];

        const bytes = w * h * 4;
        const id_rc = linux.syscall3(.shmget, 0, bytes, 0o1000 | 0o600); // IPC_PRIVATE, IPC_CREAT | rw owner
        if (linux.errno(id_rc) != .SUCCESS) return null;
        const shmid: u32 = @intCast(id_rc);
        const addr = linux.syscall3(.shmat, shmid, 0, 0);
        if (linux.errno(addr) != .SUCCESS) {
            _ = linux.syscall3(.shmctl, shmid, 0, 0); // IPC_RMID
            return null;
        }
        const seg = self.newId();
        var a: [16]u8 = @splat(0);
        a[0] = opcode;
        a[1] = 1; // ShmAttach
        std.mem.writeInt(u16, a[2..4], 4, .little);
        std.mem.writeInt(u32, a[4..8], seg, .little);
        std.mem.writeInt(u32, a[8..12], shmid, .little);
        a[12] = 1; // read-only for the server
        self.send(&a) catch return null;
        // Round trip (InternAtom) so the server has attached before the segment is marked for
        // removal; it then disappears by itself when both sides exit.
        _ = self.internAtom("WM_NAME") catch return null;
        _ = linux.syscall3(.shmctl, shmid, 0, 0); // IPC_RMID
        const mem: [*]u32 = @ptrFromInt(addr);
        return .{ .seg = seg, .opcode = opcode, .completion = first_event, .mem = mem[0 .. w * h], .w = w, .h = h };
    }

    /// Sends the shared frame (already in the server's pixel format) and asks for a completion
    /// event; call shmWait before writing the next frame into `mem`.
    pub fn shmPut(self: *Conn, s: *Shm, win: u32, gc: u32) Error!void {
        var r: [40]u8 = @splat(0);
        r[0] = s.opcode;
        r[1] = 3; // ShmPutImage
        std.mem.writeInt(u16, r[2..4], 10, .little);
        std.mem.writeInt(u32, r[4..8], win, .little);
        std.mem.writeInt(u32, r[8..12], gc, .little);
        std.mem.writeInt(u16, r[12..14], @intCast(s.w), .little); // total size
        std.mem.writeInt(u16, r[14..16], @intCast(s.h), .little);
        std.mem.writeInt(u16, r[20..22], @intCast(s.w), .little); // source size
        std.mem.writeInt(u16, r[22..24], @intCast(s.h), .little);
        r[28] = self.depth;
        r[29] = 2; // ZPixmap
        r[30] = 1; // send ShmCompletion
        std.mem.writeInt(u32, r[32..36], s.seg, .little);
        try self.send(&r);
        s.pending = true;
    }

    /// Blocks until the server has finished reading the last shmPut's frame.
    pub fn shmWait(self: *Conn, s: *Shm) Error!void {
        while (s.pending) {
            var ev: [32]u8 = undefined;
            try self.recvExact(&ev);
            if ((ev[0] & 0x7F) == s.completion) s.pending = false;
            if (ev[0] == 0) std.debug.print("x11 error code={d} major={d}\n", .{ ev[1], ev[10] });
        }
    }

    /// Writes an Argus frame ([R, G, B, A] bytes) into the shared frame in server pixel order.
    pub fn shmFill(self: *const Conn, s: *Shm, px: []const u32) void {
        for (px[0..s.mem.len], s.mem) |p, *d| {
            d.* = ((p & 0xFF) << self.red_shift) | (((p >> 8) & 0xFF) << self.green_shift) | (((p >> 16) & 0xFF) << self.blue_shift);
        }
    }

    /// Reads and reports any queued X errors without blocking (events are not selected).
    pub fn drainErrors(self: *Conn) void {
        var pfd = [1]linux.pollfd{.{ .fd = self.fd, .events = linux.POLL.IN, .revents = 0 }};
        while (linux.poll(&pfd, 1, 0) == 1) {
            var ev: [32]u8 = undefined;
            self.recvExact(&ev) catch return;
            if (ev[0] == 0) std.debug.print("x11 error code={d} major={d}\n", .{ ev[1], ev[10] });
        }
    }
};

/// The MIT-MAGIC-COOKIE-1 for `display` from an .Xauthority file's bytes, if present.
pub fn findCookie(xauth: []const u8, display: u32) ?[16]u8 {
    var num_buf: [12]u8 = undefined;
    const want = std.fmt.bufPrint(&num_buf, "{d}", .{display}) catch return null;
    var o: usize = 0;
    var any: ?[16]u8 = null;
    while (o + 2 <= xauth.len) {
        o += 2; // family
        var fields: [4][]const u8 = undefined;
        for (&fields) |*f| {
            if (o + 2 > xauth.len) return any;
            const n = std.mem.readInt(u16, xauth[o..][0..2], .big);
            o += 2;
            if (o + n > xauth.len) return any;
            f.* = xauth[o..][0..n];
            o += n;
        }
        if (std.mem.eql(u8, fields[2], "MIT-MAGIC-COOKIE-1") and fields[3].len == 16) {
            const ck = fields[3][0..16].*;
            if (std.mem.eql(u8, fields[1], want)) return ck;
            if (any == null) any = ck;
        }
    }
    return any;
}

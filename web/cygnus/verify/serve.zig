// ============================================================================
// ARGUS WEB // web/cygnus/verify/serve.zig
//
// Dev server for web/cygnus: serves the repo root read-only over http://127.0.0.1:PORT and
// accepts PUT /web/cygnus/verify/out/<name> (the verify page uploads its frames there, so they
// can be compared byte for byte with the offline renderer's on disk). One request per
// connection; nothing outside the root is served, nothing outside verify/out/ is written.
//
//   zig run web/cygnus/verify/serve.zig -- ROOT PORT
// ============================================================================

const std = @import("std");

const OUT_PREFIX = "/web/cygnus/verify/out/";

fn contentType(path: []const u8) []const u8 {
    const types = [_][2][]const u8{
        .{ ".html", "text/html; charset=utf-8" },  .{ ".js", "text/javascript" },    .{ ".mjs", "text/javascript" },
        .{ ".wgsl", "text/plain; charset=utf-8" }, .{ ".wasm", "application/wasm" }, .{ ".json", "application/json" },
        .{ ".png", "image/png" },                  .{ ".css", "text/css" },
    };
    for (types) |t| if (std.mem.endsWith(u8, path, t[0])) return t[1];
    return "application/octet-stream";
}

fn safe(path: []const u8) bool {
    return path.len > 0 and path[0] == '/' and std.mem.find(u8, path, "..") == null and std.mem.findScalar(u8, path, '\\') == null;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) return error.Usage;
    const root = try std.Io.Dir.cwd().openDir(io, args[1], .{});
    const port = try std.fmt.parseInt(u16, args[2], 10);
    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", port);
    var server = try addr.listen(io, .{ .reuse_address = true });
    std.debug.print("serving {s} on http://127.0.0.1:{d}/\n", .{ args[1], port });
    while (true) {
        const stream = server.accept(io) catch continue;
        defer stream.close(io);
        handle(io, gpa, root, stream) catch |e| switch (e) {
            error.HttpConnectionClosing => {},
            else => std.debug.print("request failed: {s}\n", .{@errorName(e)}),
        };
    }
}

fn handle(io: std.Io, gpa: std.mem.Allocator, root: std.Io.Dir, stream: std.Io.net.Stream) !void {
    var rbuf: [16 * 1024]u8 = undefined;
    var wbuf: [64 * 1024]u8 = undefined;
    var sr = stream.reader(io, &rbuf);
    var sw = stream.writer(io, &wbuf);
    var http = std.http.Server.init(&sr.interface, &sw.interface);
    var req = try http.receiveHead();
    const target = req.head.target;
    // The head lives in the read buffer, which reading a body overwrites: copy the path out first.
    const path = try gpa.dupe(u8, target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len]);
    defer gpa.free(path);
    const no_cache = [_]std.http.Header{.{ .name = "cache-control", .value = "no-store" }};
    std.debug.print("{s} {s}\n", .{ @tagName(req.head.method), path });
    if (!safe(path)) return req.respond("bad path\n", .{ .status = .bad_request, .keep_alive = false });
    switch (req.head.method) {
        .PUT => {
            if (!std.mem.startsWith(u8, path, OUT_PREFIX) or std.mem.findScalar(u8, path[OUT_PREFIX.len..], '/') != null)
                return req.respond("PUT only to verify/out/\n", .{ .status = .forbidden, .keep_alive = false });
            var body_buf: [64 * 1024]u8 = undefined;
            const body = try (try req.readerExpectContinue(&body_buf)).allocRemaining(gpa, .limited(512 << 20));
            defer gpa.free(body);
            root.createDirPath(io, OUT_PREFIX[1 .. OUT_PREFIX.len - 1]) catch {};
            try root.writeFile(io, .{ .sub_path = path[1..], .data = body });
            std.debug.print("PUT {s} ({d} bytes)\n", .{ path, body.len });
            return req.respond("ok\n", .{ .keep_alive = false });
        },
        .GET, .HEAD => {
            const rel = if (std.mem.endsWith(u8, path, "/")) try std.fmt.allocPrint(gpa, "{s}index.html", .{path[1..]}) else try gpa.dupe(u8, path[1..]);
            defer gpa.free(rel);
            const data = root.readFileAlloc(io, rel, gpa, .limited(512 << 20)) catch
                return req.respond("not found\n", .{ .status = .not_found, .keep_alive = false });
            defer gpa.free(data);
            const headers = [_]std.http.Header{ no_cache[0], .{ .name = "content-type", .value = contentType(rel) } };
            return req.respond(data, .{ .keep_alive = false, .extra_headers = &headers });
        },
        else => return req.respond("method not allowed\n", .{ .status = .method_not_allowed, .keep_alive = false }),
    }
}

//! site/tools/serve.zig: serve the assembled site the way GitHub Pages will, for local checks.
//!
//!   zig run site/tools/serve.zig -- _site 8136 [--prefix /argus] [--isolate]
//!
//! The site is mounted under --prefix (Pages serves a project site at /<repo>/), so a URL that
//! only works at the domain root shows up here as a 404. No COOP/COEP headers unless --isolate:
//! Pages cannot send them, so by default the page has to get isolation from
//! coi-serviceworker.js, as it will live. GET and HEAD only, 127.0.0.1 only, nothing outside
//! ROOT, one request per connection (the same shape as web/cygnus/verify/serve.zig).

const std = @import("std");

fn contentType(path: []const u8) []const u8 {
    const types = [_][2][]const u8{
        .{ ".html", "text/html; charset=utf-8" },  .{ ".js", "text/javascript; charset=utf-8" },
        .{ ".mjs", "text/javascript" },            .{ ".css", "text/css; charset=utf-8" },
        .{ ".wgsl", "text/plain; charset=utf-8" }, .{ ".md", "text/markdown; charset=utf-8" },
        .{ ".txt", "text/plain; charset=utf-8" },  .{ ".zig", "text/plain; charset=utf-8" },
        .{ ".wasm", "application/wasm" },          .{ ".json", "application/json" },
        .{ ".xml", "application/xml" },            .{ ".png", "image/png" },
        .{ ".jpg", "image/jpeg" },                 .{ ".svg", "image/svg+xml" },
        .{ ".ico", "image/x-icon" },               .{ ".webmanifest", "application/manifest+json" },
    };
    for (types) |t| if (std.mem.endsWith(u8, path, t[0])) return t[1];
    return "application/octet-stream";
}

fn safe(path: []const u8) bool {
    return path.len > 0 and path[0] == '/' and std.mem.find(u8, path, "..") == null and std.mem.findScalar(u8, path, '\\') == null;
}

const Options = struct { prefix: []const u8 = "/argus", isolate: bool = false };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) {
        std.debug.print("usage: serve ROOT PORT [--prefix /argus] [--isolate]\n", .{});
        std.process.exit(2);
    }
    var opt: Options = .{};
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--isolate")) opt.isolate = true else if (std.mem.eql(u8, args[i], "--prefix") and i + 1 < args.len) {
            i += 1;
            opt.prefix = std.mem.trimEnd(u8, args[i], "/");
        }
    }
    const root = try std.Io.Dir.cwd().openDir(io, args[1], .{});
    const port = try std.fmt.parseInt(u16, args[2], 10);
    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", port);
    var server = try addr.listen(io, .{ .reuse_address = true });
    std.debug.print("serving {s} on http://127.0.0.1:{d}{s}/ ({s})\n", .{ args[1], port, opt.prefix, if (opt.isolate) "COOP/COEP sent" else "no COOP/COEP, as GitHub Pages" });
    while (true) {
        const stream = server.accept(io) catch continue;
        defer stream.close(io);
        handle(io, gpa, root, stream, opt) catch |e| switch (e) {
            error.HttpConnectionClosing => {},
            else => std.debug.print("request failed: {s}\n", .{@errorName(e)}),
        };
    }
}

fn handle(io: std.Io, gpa: std.mem.Allocator, root: std.Io.Dir, stream: std.Io.net.Stream, opt: Options) !void {
    var rbuf: [16 * 1024]u8 = undefined;
    var wbuf: [64 * 1024]u8 = undefined;
    var sr = stream.reader(io, &rbuf);
    var sw = stream.writer(io, &wbuf);
    var http = std.http.Server.init(&sr.interface, &sw.interface);
    var req = try http.receiveHead();
    const target = req.head.target;
    const path = try gpa.dupe(u8, target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len]);
    defer gpa.free(path);
    if (req.head.method != .GET and req.head.method != .HEAD)
        return req.respond("method not allowed\n", .{ .status = .method_not_allowed, .keep_alive = false });
    if (!safe(path)) return req.respond("bad path\n", .{ .status = .bad_request, .keep_alive = false });

    var hdr: [4]std.http.Header = undefined;
    var n: usize = 0;
    hdr[n] = .{ .name = "cache-control", .value = "no-store" };
    n += 1;
    if (opt.isolate) {
        hdr[n] = .{ .name = "cross-origin-opener-policy", .value = "same-origin" };
        hdr[n + 1] = .{ .name = "cross-origin-embedder-policy", .value = "require-corp" };
        n += 2;
    }

    if (!std.mem.startsWith(u8, path, opt.prefix) or (path.len > opt.prefix.len and path[opt.prefix.len] != '/') or path.len == opt.prefix.len) {
        const loc = try std.fmt.allocPrint(gpa, "{s}/", .{opt.prefix});
        defer gpa.free(loc);
        hdr[n] = .{ .name = "location", .value = loc };
        return req.respond("", .{ .status = .found, .keep_alive = false, .extra_headers = hdr[0 .. n + 1] });
    }
    const sub = path[opt.prefix.len + 1 ..];
    const rel = if (sub.len == 0 or std.mem.endsWith(u8, sub, "/")) try std.fmt.allocPrint(gpa, "{s}index.html", .{sub}) else try gpa.dupe(u8, sub);
    defer gpa.free(rel);
    const data = root.readFileAlloc(io, rel, gpa, .limited(512 << 20)) catch |e| {
        if (e == error.IsDir) {
            // Pages answers /dir with a redirect to /dir/.
            const loc = try std.fmt.allocPrint(gpa, "{s}/", .{path});
            defer gpa.free(loc);
            hdr[n] = .{ .name = "location", .value = loc };
            return req.respond("", .{ .status = .moved_permanently, .keep_alive = false, .extra_headers = hdr[0 .. n + 1] });
        }
        const page = root.readFileAlloc(io, "404.html", gpa, .limited(1 << 20)) catch null;
        defer if (page) |p| gpa.free(p);
        hdr[n] = .{ .name = "content-type", .value = "text/html; charset=utf-8" };
        return req.respond(page orelse "not found\n", .{ .status = .not_found, .keep_alive = false, .extra_headers = hdr[0 .. n + 1] });
    };
    defer gpa.free(data);
    hdr[n] = .{ .name = "content-type", .value = contentType(rel) };
    return req.respond(data, .{ .keep_alive = false, .extra_headers = hdr[0 .. n + 1] });
}

test "safe paths" {
    try std.testing.expect(safe("/argus/index.html"));
    try std.testing.expect(!safe("/argus/../etc/passwd"));
    try std.testing.expect(!safe("relative"));
}

test "content types" {
    try std.testing.expectEqualStrings("application/wasm", contentType("web/wasm/build/x.st.wasm"));
    try std.testing.expectEqualStrings("text/html; charset=utf-8", contentType("bench/index.html"));
}

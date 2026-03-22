const std = @import("std");
const config_mod = @import("config.zig");
const lean_client = @import("lean_client.zig");
const lean_types = @import("lean_types.zig");
const db_mod = @import("db.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    cfg: config_mod.Config,
    db: db_mod.Db,
    db_mu: std.Thread.Mutex,

    pub fn deinit(self: *App) void {
        self.db_mu.lock();
        self.db.close();
        self.db_mu.unlock();
        self.cfg.deinit();
    }

    pub fn syncOnce(self: *App) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const fetch = lean_client.getJson(a, self.cfg.lean_urls, "/lean/v0/fork_choice") catch return;
        defer lean_client.deinitFetchResult(a, &fetch);

        const parsed = std.json.parseFromSlice(lean_types.ForkChoice, a, fetch.body, .{
            .ignore_unknown_fields = true,
        }) catch return;
        defer parsed.deinit();

        const now_ms: i64 = @intCast(@divFloor(std.time.nanoTimestamp(), std.time.ns_per_ms));

        self.db_mu.lock();
        defer self.db_mu.unlock();
        self.db.persistForkChoice(parsed.value, fetch.body, fetch.source_url, now_ms) catch return;
    }

    fn forkChoiceLive(self: *App, arena: std.mem.Allocator) !struct { body: []u8, stale: bool } {
        const fetch = lean_client.getJson(arena, self.cfg.lean_urls, "/lean/v0/fork_choice") catch {
            self.db_mu.lock();
            defer self.db_mu.unlock();
            const snap = self.db.latestSnapshotJson(self.allocator) orelse return error.NoData;
            return .{ .body = snap, .stale = true };
        };
        defer lean_client.deinitFetchResult(arena, &fetch);

        const parsed = try std.json.parseFromSlice(lean_types.ForkChoice, arena, fetch.body, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        const now_ms: i64 = @intCast(@divFloor(std.time.nanoTimestamp(), std.time.ns_per_ms));

        self.db_mu.lock();
        self.db.persistForkChoice(parsed.value, fetch.body, fetch.source_url, now_ms) catch {};
        self.db_mu.unlock();

        const owned = try self.allocator.dupe(u8, fetch.body);
        return .{ .body = owned, .stale = false };
    }

    fn respondJson(request: *std.http.Server.Request, status: std.http.Status, body: []const u8, extra: []const std.http.Header) !void {
        var headers: [5]std.http.Header = undefined;
        headers[0] = .{ .name = "Access-Control-Allow-Origin", .value = "*" };
        headers[1] = .{ .name = "Content-Type", .value = "application/json" };
        const n_base: usize = 2;
        @memcpy(headers[n_base..][0..extra.len], extra);
        try request.respond(body, .{
            .status = status,
            .extra_headers = headers[0 .. n_base + extra.len],
            .keep_alive = false,
        });
    }

    fn respondText(request: *std.http.Server.Request, status: std.http.Status, content_type: []const u8, body: []const u8) !void {
        try request.respond(body, .{
            .status = status,
            .extra_headers = &.{
                .{ .name = "Access-Control-Allow-Origin", .value = "*" },
                .{ .name = "Content-Type", .value = content_type },
            },
            .keep_alive = false,
        });
    }

    fn respond404(request: *std.http.Server.Request) !void {
        try respondJson(request, .not_found, "{\"error\":\"not_found\"}", &.{});
    }

    pub fn handleConnection(self: *App, connection: std.net.Server.Connection) void {
        const read_buffer = self.allocator.alloc(u8, 8192) catch {
            connection.stream.close();
            return;
        };
        defer self.allocator.free(read_buffer);
        const write_buffer = self.allocator.alloc(u8, 65536) catch {
            connection.stream.close();
            return;
        };
        defer self.allocator.free(write_buffer);

        var stream_reader = connection.stream.reader(read_buffer);
        var stream_writer = connection.stream.writer(write_buffer);

        var http_server = std.http.Server.init(stream_reader.interface(), &stream_writer.interface);
        var request = http_server.receiveHead() catch {
            connection.stream.close();
            return;
        };

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        const target = request.head.target;
        const path_only = if (std.mem.indexOfScalar(u8, target, '?')) |q| target[0..q] else target;

        if (request.head.method == .OPTIONS) {
            _ = request.respond("", .{
                .status = .no_content,
                .extra_headers = &.{
                    .{ .name = "Access-Control-Allow-Origin", .value = "*" },
                    .{ .name = "Access-Control-Allow-Methods", .value = "GET, OPTIONS" },
                    .{ .name = "Access-Control-Allow-Headers", .value = "Content-Type" },
                },
                .keep_alive = false,
            }) catch {};
            connection.stream.close();
            return;
        }

        if (request.head.method != .GET) {
            respond404(&request) catch {};
            connection.stream.close();
            return;
        }

        if (std.mem.eql(u8, path_only, "/api/health")) {
            self.handleHealth(&request, a) catch {
                _ = request.respond("{\"error\":\"internal\"}", .{ .status = .internal_server_error, .keep_alive = false }) catch {};
            };
            connection.stream.close();
            return;
        }

        if (std.mem.eql(u8, path_only, "/api/fork_choice")) {
            self.handleForkChoice(&request, a) catch {
                _ = request.respond("{\"error\":\"unavailable\"}", .{ .status = .service_unavailable, .keep_alive = false }) catch {};
            };
            connection.stream.close();
            return;
        }

        if (std.mem.eql(u8, path_only, "/api/slots")) {
            self.handleSlots(&request, target) catch {
                _ = request.respond("{\"error\":\"internal\"}", .{ .status = .internal_server_error, .keep_alive = false }) catch {};
            };
            connection.stream.close();
            return;
        }

        if (std.mem.startsWith(u8, path_only, "/api/slot/")) {
            const rest = path_only["/api/slot/".len..];
            const slot = std.fmt.parseInt(u64, rest, 10) catch {
                respond404(&request) catch {};
                connection.stream.close();
                return;
            };
            self.handleSlot(&request, slot) catch {
                _ = request.respond("{\"error\":\"internal\"}", .{ .status = .internal_server_error, .keep_alive = false }) catch {};
            };
            connection.stream.close();
            return;
        }

        if (std.mem.startsWith(u8, path_only, "/api/block/")) {
            const hex_root = path_only["/api/block/".len..];
            self.handleBlock(&request, hex_root) catch {
                _ = request.respond("{\"error\":\"internal\"}", .{ .status = .internal_server_error, .keep_alive = false }) catch {};
            };
            connection.stream.close();
            return;
        }

        if (std.mem.startsWith(u8, path_only, "/assets/")) {
            self.serveStatic(&request, path_only) catch respond404(&request) catch {};
            connection.stream.close();
            return;
        }

        if (std.mem.eql(u8, path_only, "/") or std.mem.eql(u8, path_only, "/index.html")) {
            self.serveIndex(&request) catch respond404(&request) catch {};
            connection.stream.close();
            return;
        }

        respond404(&request) catch {};
        connection.stream.close();
    }

    fn handleHealth(self: *App, request: *std.http.Server.Request, arena: std.mem.Allocator) !void {
        _ = arena;
        var lean_ok = false;
        if (lean_client.getJson(self.allocator, self.cfg.lean_urls, "/lean/v0/health")) |fr| {
            defer lean_client.deinitFetchResult(self.allocator, &fr);
            if (std.json.parseFromSlice(lean_types.Health, self.allocator, fr.body, .{
                .ignore_unknown_fields = true,
            })) |parsed| {
                defer parsed.deinit();
                lean_ok = std.mem.eql(u8, parsed.value.status, "healthy") or
                    std.mem.eql(u8, parsed.value.status, "ok");
            } else |_| {}
        } else |_| {}

        self.db_mu.lock();
        const meta = self.db.latestMeta(self.allocator) catch null;
        self.db_mu.unlock();
        defer if (meta) |m| m.deinit(self.allocator);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);
        try w.writeAll("{\"lean_upstream_ok\":");
        try w.print("{s}", .{if (lean_ok) "true" else "false"});
        try w.writeAll(",\"db\":");
        if (meta) |m| {
            try w.print("{{\"last_sync_ms\":{d},\"source\":\"", .{m.fetched_at_ms});
            try jsonEscapeString(w, m.source_url);
            try w.writeAll("\",\"head\":\"");
            try jsonEscapeString(w, m.head);
            try w.print("\",\"justified_slot\":{d},\"finalized_slot\":{d},\"validator_count\":{d}", .{
                m.justified_slot, m.finalized_slot, m.validator_count,
            });
            try w.writeByte('}');
        } else {
            try w.writeAll("null");
        }
        try w.writeByte('}');

        try respondJson(request, .ok, buf.items, &.{});
    }

    fn handleForkChoice(self: *App, request: *std.http.Server.Request, arena: std.mem.Allocator) !void {
        const live = self.forkChoiceLive(arena) catch {
            try respondJson(request, .service_unavailable, "{\"error\":\"no_data\"}", &.{});
            return;
        };
        defer self.allocator.free(live.body);

        const stale_hdr = [_]std.http.Header{.{
            .name = "X-Nemo-Stale",
            .value = "true",
        }};
        if (live.stale) {
            try respondJson(request, .ok, live.body, &stale_hdr);
        } else {
            try respondJson(request, .ok, live.body, &.{});
        }
    }

    fn handleSlots(self: *App, request: *std.http.Server.Request, target: []const u8) !void {
        var limit: usize = 200;
        if (std.mem.indexOf(u8, target, "limit=")) |i| {
            const start = i + "limit=".len;
            const rest = target[start..];
            const end = std.mem.indexOfScalar(u8, rest, '&') orelse rest.len;
            limit = std.fmt.parseInt(usize, rest[0..end], 10) catch 200;
            if (limit > 2000) limit = 2000;
        }

        self.db_mu.lock();
        const slots = self.db.listSlots(self.allocator, limit) catch {
            self.db_mu.unlock();
            return error.DbError;
        };
        self.db_mu.unlock();
        defer self.allocator.free(slots);

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);
        try w.writeAll("{\"slots\":[");
        for (slots, 0..) |s, idx| {
            if (idx > 0) try w.writeByte(',');
            try w.print("{d}", .{s});
        }
        try w.print("],\"limit\":{d}", .{limit});
        try w.writeByte('}');

        try respondJson(request, .ok, buf.items, &.{});
    }

    fn handleSlot(self: *App, request: *std.http.Server.Request, slot: u64) !void {
        self.db_mu.lock();
        const rows = self.db.blocksAtSlot(self.allocator, slot) catch {
            self.db_mu.unlock();
            return error.DbError;
        };
        self.db_mu.unlock();
        defer {
            for (rows) |r| r.deinit(self.allocator);
            self.allocator.free(rows);
        }

        if (rows.len == 0) {
            try respondJson(request, .not_found, "{\"error\":\"slot_not_found\"}", &.{});
            return;
        }

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);
        try w.writeAll("{\"slot\":");
        try w.print("{d}", .{slot});
        try w.writeAll(",\"blocks\":[");
        for (rows, 0..) |row, idx| {
            if (idx > 0) try w.writeByte(',');
            try w.writeByte('{');
            try w.writeAll("\"root\":\"");
            try jsonEscapeString(w, row.root);
            try w.writeAll("\",\"parent_root\":\"");
            try jsonEscapeString(w, row.parent_root);
            try w.print("\",\"proposer_index\":{d},\"weight\":{d},\"source_url\":\"", .{
                row.proposer_index, row.weight,
            });
            try jsonEscapeString(w, row.source_url);
            try w.print("\",\"updated_at_ms\":{d}", .{row.updated_at_ms});
            try w.writeByte('}');
        }
        try w.writeAll("]}");

        try respondJson(request, .ok, buf.items, &.{});
    }

    fn handleBlock(self: *App, request: *std.http.Server.Request, hex_root: []const u8) !void {
        self.db_mu.lock();
        const row = self.db.blockByRoot(self.allocator, hex_root) catch {
            self.db_mu.unlock();
            return error.DbError;
        };
        self.db_mu.unlock();
        defer if (row) |r| r.deinit(self.allocator);

        const b = row orelse {
            try respondJson(request, .not_found, "{\"error\":\"block_not_found\"}", &.{});
            return;
        };

        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);
        try w.writeAll("{\"root\":\"");
        try jsonEscapeString(w, b.root);
        try w.writeAll("\",\"slot\":");
        try w.print("{d}", .{b.slot});
        try w.writeAll(",\"parent_root\":\"");
        try jsonEscapeString(w, b.parent_root);
        try w.print("\",\"proposer_index\":{d},\"weight\":{d},\"source_url\":\"", .{
            b.proposer_index, b.weight,
        });
        try jsonEscapeString(w, b.source_url);
        try w.print("\",\"updated_at_ms\":{d}", .{b.updated_at_ms});
        try w.writeByte('}');

        try respondJson(request, .ok, buf.items, &.{});
    }

    fn serveIndex(self: *App, request: *std.http.Server.Request) !void {
        const path = try std.fs.path.join(self.allocator, &.{ self.cfg.web_dist, "index.html" });
        defer self.allocator.free(path);
        const file = std.fs.cwd().openFile(path, .{}) catch {
            try respondText(request, .not_found, "text/plain", "index.html missing; build the web UI (see README)");
            return;
        };
        defer file.close();
        const max_size = 2 * 1024 * 1024;
        const data = file.readToEndAlloc(self.allocator, max_size) catch {
            try respondText(request, .internal_server_error, "text/plain", "read error");
            return;
        };
        defer self.allocator.free(data);
        try respondText(request, .ok, "text/html", data);
    }

    fn serveStatic(self: *App, request: *std.http.Server.Request, path_only: []const u8) !void {
        const rel = path_only["/assets/".len..];
        if (rel.len == 0 or std.mem.indexOfScalar(u8, rel, '/') != null or std.mem.startsWith(u8, rel, ".")) {
            return error.BadPath;
        }
        const path = try std.fs.path.join(self.allocator, &.{ self.cfg.web_dist, "assets", rel });
        defer self.allocator.free(path);
        const file = std.fs.cwd().openFile(path, .{}) catch return error.NotFound;
        defer file.close();
        const data = file.readToEndAlloc(self.allocator, 4 * 1024 * 1024) catch return error.ReadFailed;
        defer self.allocator.free(data);
        const ct = contentType(rel);
        try respondText(request, .ok, ct, data);
    }
};

fn jsonEscapeString(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\' => try w.writeAll("\\\\"),
            '"' => try w.writeAll("\\\""),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try w.writeAll("\\u");
                    var uesc: [4]u8 = undefined;
                    _ = try std.fmt.bufPrint(&uesc, "{x:0>4}", .{@as(u16, @intCast(c))});
                    try w.writeAll(&uesc);
                } else {
                    try w.writeByte(c);
                }
            },
        }
    }
}

fn contentType(name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, name, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, name, ".css")) return "text/css";
    if (std.mem.endsWith(u8, name, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, name, ".png")) return "image/png";
    if (std.mem.endsWith(u8, name, ".woff2")) return "font/woff2";
    return "application/octet-stream";
}

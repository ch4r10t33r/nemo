const std = @import("std");
const config_mod = @import("config.zig");
const db_mod = @import("db.zig");
const server_mod = @import("server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cfg = try config_mod.Config.load(allocator);

    const db = try db_mod.Db.open(allocator, cfg.db_path);

    var app = server_mod.App{
        .allocator = allocator,
        .cfg = cfg,
        .db = db,
        .db_mu = .{},
    };
    defer app.deinit();

    const address = try std.net.Address.parseIp4("0.0.0.0", app.cfg.port);
    var listen = try address.listen(.{ .reuse_address = true });
    defer listen.deinit();

    std.log.info("nemo listening on http://0.0.0.0:{d}", .{app.cfg.port});
    std.log.info("lean upstreams: {s}", .{app.cfg.lean_urls[0]});
    std.log.info("database: {s}", .{app.cfg.db_path});
    std.log.info("static assets: {s}", .{app.cfg.web_dist});

    app.syncOnce();

    const sync_thread = try std.Thread.spawn(.{}, syncLoop, .{&app});
    defer sync_thread.join();

    while (true) {
        const conn = listen.accept() catch |err| {
            std.log.err("accept: {}", .{err});
            continue;
        };
        app.handleConnection(conn);
    }
}

fn syncLoop(app: *server_mod.App) void {
    while (true) {
        std.Thread.sleep(app.cfg.sync_interval_ns);
        app.syncOnce();
    }
}

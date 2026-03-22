const std = @import("std");

// Align with leanSpec `SECONDS_PER_SLOT` (`lean_spec/subspecs/chain/config.py`).
const default_sync_interval_sec: u64 = 4;

pub const Config = struct {
    lean_urls: [][]const u8,
    port: u16,
    db_path: []const u8,
    sync_interval_ns: u64,
    web_dist: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        for (self.lean_urls) |s| self.allocator.free(s);
        self.allocator.free(self.lean_urls);
        self.allocator.free(self.db_path);
        self.allocator.free(self.web_dist);
    }

    pub fn load(allocator: std.mem.Allocator) !Config {
        var url_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (url_list.items) |s| allocator.free(s);
            url_list.deinit(allocator);
        }

        const raw = std.process.getEnvVarOwned(allocator, "LEAN_API_URL") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try allocator.dupe(u8, "http://127.0.0.1:5052"),
            else => return err,
        };
        defer allocator.free(raw);

        var it = std.mem.splitScalar(u8, raw, ',');
        while (it.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t\r\n");
            if (trimmed.len == 0) continue;
            const no_slash = std.mem.trimRight(u8, trimmed, "/");
            try url_list.append(allocator, try allocator.dupe(u8, no_slash));
        }
        if (url_list.items.len == 0) {
            try url_list.append(allocator, try allocator.dupe(u8, "http://127.0.0.1:5052"));
        }

        const lean_urls = try url_list.toOwnedSlice(allocator);

        const port: u16 = blk: {
            if (std.process.getEnvVarOwned(allocator, "NEMO_PORT")) |p| {
                defer allocator.free(p);
                break :blk try std.fmt.parseInt(u16, p, 10);
            } else |_| {
                break :blk 5053;
            }
        };

        const db_path = std.process.getEnvVarOwned(allocator, "NEMO_DB_PATH") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try allocator.dupe(u8, "nemo.db"),
            else => return err,
        };

        const sync_sec: u64 = blk: {
            if (std.process.getEnvVarOwned(allocator, "SYNC_INTERVAL_SEC")) |s| {
                defer allocator.free(s);
                break :blk try std.fmt.parseInt(u64, s, 10);
            } else |_| {
                break :blk default_sync_interval_sec;
            }
        };

        const web_dist = std.process.getEnvVarOwned(allocator, "WEB_DIST") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => try allocator.dupe(u8, "frontend/dist"),
            else => return err,
        };

        return .{
            .lean_urls = lean_urls,
            .port = port,
            .db_path = db_path,
            .sync_interval_ns = sync_sec * std.time.ns_per_s,
            .web_dist = web_dist,
            .allocator = allocator,
        };
    }
};

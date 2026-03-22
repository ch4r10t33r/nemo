const std = @import("std");

pub const FetchResult = struct {
    body: []u8,
    source_url: []u8,
};

pub fn deinitFetchResult(allocator: std.mem.Allocator, r: *const FetchResult) void {
    allocator.free(r.body);
    allocator.free(r.source_url);
}

/// GET path (e.g. "/lean/v0/fork_choice") from the first base URL that responds with 200.
/// Caller owns returned fields (allocated with `allocator`).
pub fn getJson(
    allocator: std.mem.Allocator,
    base_urls: []const []const u8,
    path: []const u8,
) !FetchResult {
    var last_err: anyerror = error.LeanNodeUnavailable;

    for (base_urls) |base| {
        const uri_str = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base, path });
        defer allocator.free(uri_str);

        const uri = std.Uri.parse(uri_str) catch continue;

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var req = client.request(.GET, uri, .{
            .extra_headers = &.{.{ .name = "Accept", .value = "application/json" }},
        }) catch |err| {
            last_err = err;
            continue;
        };
        defer req.deinit();

        req.sendBodiless() catch |err| {
            last_err = err;
            continue;
        };

        var redirect_buffer: [1024]u8 = undefined;
        var response = req.receiveHead(&redirect_buffer) catch |err| {
            last_err = err;
            continue;
        };

        if (response.head.status != .ok) {
            last_err = error.HttpNotOk;
            continue;
        }

        var body: std.ArrayList(u8) = .empty;
        errdefer body.deinit(allocator);

        var transfer_buffer: [8192]u8 = undefined;
        const body_reader = response.reader(&transfer_buffer);
        var read_buf: [8192]u8 = undefined;
        var read_failed = false;
        while (true) {
            const n = body_reader.readSliceShort(&read_buf) catch {
                read_failed = true;
                break;
            };
            if (n == 0) break;
            try body.appendSlice(allocator, read_buf[0..n]);
        }
        if (read_failed) continue;

        const owned_body = try body.toOwnedSlice(allocator);
        const url_copy = try allocator.dupe(u8, base);
        return .{ .body = owned_body, .source_url = url_copy };
    }

    return last_err;
}

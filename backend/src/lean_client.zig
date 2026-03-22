const std = @import("std");

pub const FetchResult = struct {
    body: []u8,
    source_url: []u8,
};

pub fn deinitFetchResult(allocator: std.mem.Allocator, r: *const FetchResult) void {
    allocator.free(r.body);
    allocator.free(r.source_url);
}

/// GET `path` from a single base URL (no trailing slash on `base`). HTTP 200 and full body required.
/// Caller owns returned fields (allocated with `allocator`).
pub fn fetchJsonSingleBase(
    allocator: std.mem.Allocator,
    base: []const u8,
    path: []const u8,
) !FetchResult {
    const uri_str = try std.fmt.allocPrint(allocator, "{s}{s}", .{ base, path });
    defer allocator.free(uri_str);

    const uri = std.Uri.parse(uri_str) catch return error.InvalidUri;

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var req = client.request(.GET, uri, .{
        .keep_alive = false,
        .headers = .{ .accept_encoding = .omit },
        .extra_headers = &.{.{ .name = "Accept", .value = "application/json" }},
    }) catch |err| return err;
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buffer: [1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buffer);

    if (response.head.status != .ok) return error.HttpNotOk;

    var body: std.ArrayList(u8) = .empty;
    errdefer body.deinit(allocator);

    var transfer_buffer: [8192]u8 = undefined;
    const body_reader = response.reader(&transfer_buffer);
    var read_buf: [8192]u8 = undefined;
    while (true) {
        const n = body_reader.readSliceShort(&read_buf) catch return error.BodyReadFailed;
        if (n == 0) break;
        try body.appendSlice(allocator, read_buf[0..n]);
    }

    const owned_body = try body.toOwnedSlice(allocator);
    const url_copy = try allocator.dupe(u8, base);
    return .{ .body = owned_body, .source_url = url_copy };
}

/// GET path from each base URL in order until one returns HTTP 200 with a full body.
/// For invalid JSON or application-level failures, use per-URL fetch in the caller instead.
/// Caller owns returned fields (allocated with `allocator`).
pub fn getJson(
    allocator: std.mem.Allocator,
    base_urls: []const []const u8,
    path: []const u8,
) !FetchResult {
    var last_err: anyerror = error.LeanNodeUnavailable;

    for (base_urls) |base| {
        const fr = fetchJsonSingleBase(allocator, base, path) catch |err| {
            last_err = err;
            continue;
        };
        return fr;
    }

    return last_err;
}

const std = @import("std");
const lean_types = @import("lean_types.zig");

const sqlite3 = opaque {};
const sqlite3_stmt = opaque {};

const SQLITE_OK: c_int = 0;
const SQLITE_ROW: c_int = 100;
const SQLITE_DONE: c_int = 101;
const sqlite3_destructor_fn = ?*const fn (?*anyopaque) callconv(.c) void;

extern "c" fn sqlite3_open_v2(
    filename: [*:0]const u8,
    ppDb: *?*sqlite3,
    flags: c_int,
    zVfs: ?[*:0]const u8,
) c_int;
extern "c" fn sqlite3_close(db: *sqlite3) c_int;
extern "c" fn sqlite3_exec(
    db: ?*sqlite3,
    sql: [*:0]const u8,
    callback: ?*const anyopaque,
    arg: ?*anyopaque,
    errmsg: ?*?[*:0]u8,
) c_int;
extern "c" fn sqlite3_free(ptr: ?*anyopaque) void;
extern "c" fn sqlite3_prepare_v2(
    db: *sqlite3,
    zSql: [*:0]const u8,
    nByte: c_int,
    ppStmt: *?*sqlite3_stmt,
    pzTail: ?*?[*:0]const u8,
) c_int;
extern "c" fn sqlite3_finalize(stmt: ?*sqlite3_stmt) c_int;
extern "c" fn sqlite3_reset(stmt: *sqlite3_stmt) c_int;
extern "c" fn sqlite3_bind_text(
    stmt: *sqlite3_stmt,
    i: c_int,
    z: ?[*]const u8,
    n: c_int,
    destructor: sqlite3_destructor_fn,
) c_int;
extern "c" fn sqlite3_bind_int64(stmt: *sqlite3_stmt, i: c_int, v: i64) c_int;
extern "c" fn sqlite3_step(stmt: *sqlite3_stmt) c_int;
extern "c" fn sqlite3_column_text(stmt: *sqlite3_stmt, iCol: c_int) ?[*:0]const u8;
extern "c" fn sqlite3_column_int64(stmt: *sqlite3_stmt, iCol: c_int) i64;

const SQLITE_OPEN_READWRITE: c_int = 0x00000002;
const SQLITE_OPEN_CREATE: c_int = 0x00000004;

/// SQLITE_STATIC: pointers must remain valid until `sqlite3_step` returns.
fn bindText(stmt: *sqlite3_stmt, idx: c_int, text: []const u8) c_int {
    return sqlite3_bind_text(stmt, idx, text.ptr, @intCast(text.len), null);
}

pub const Db = struct {
    raw: *sqlite3,
    allocator: std.mem.Allocator,

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Db {
        const zpath = try allocator.dupeZ(u8, path);
        defer allocator.free(zpath);

        var db_out: ?*sqlite3 = null;
        const flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;
        const rc = sqlite3_open_v2(zpath.ptr, &db_out, flags, null);
        if (rc != SQLITE_OK) return error.SqliteOpenFailed;
        const db = db_out orelse return error.SqliteOpenFailed;

        const self = Db{ .raw = db, .allocator = allocator };
        try self.execSchema();
        return self;
    }

    pub fn close(self: *Db) void {
        _ = sqlite3_close(self.raw);
    }

    fn execSchema(self: *const Db) !void {
        const schema =
            \\CREATE TABLE IF NOT EXISTS block_record (
            \\  root TEXT PRIMARY KEY NOT NULL,
            \\  slot INTEGER NOT NULL,
            \\  parent_root TEXT NOT NULL,
            \\  proposer_index INTEGER NOT NULL,
            \\  weight INTEGER NOT NULL,
            \\  source_url TEXT NOT NULL,
            \\  updated_at INTEGER NOT NULL
            \\);
            \\CREATE INDEX IF NOT EXISTS idx_block_slot ON block_record(slot);
            \\CREATE TABLE IF NOT EXISTS fork_choice_snapshot (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  fetched_at INTEGER NOT NULL,
            \\  head TEXT NOT NULL,
            \\  justified_slot INTEGER NOT NULL,
            \\  justified_root TEXT NOT NULL,
            \\  finalized_slot INTEGER NOT NULL,
            \\  finalized_root TEXT NOT NULL,
            \\  validator_count INTEGER NOT NULL,
            \\  raw_json TEXT NOT NULL,
            \\  source_url TEXT NOT NULL
            \\);
        ;
        var errmsg: ?[*:0]u8 = null;
        defer if (errmsg) |m| sqlite3_free(m);
        const rc = sqlite3_exec(self.raw, schema, null, null, &errmsg);
        if (rc != SQLITE_OK) return error.SqliteSchemaFailed;
    }

    pub fn persistForkChoice(
        self: *Db,
        fc: lean_types.ForkChoice,
        raw_json: []const u8,
        source_url: []const u8,
        now_ms: i64,
    ) !void {
        var stmt_ins_block: ?*sqlite3_stmt = null;

        const sql_block =
            \\INSERT INTO block_record (root, slot, parent_root, proposer_index, weight, source_url, updated_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?)
            \\ON CONFLICT(root) DO UPDATE SET
            \\  slot=excluded.slot,
            \\  parent_root=excluded.parent_root,
            \\  proposer_index=excluded.proposer_index,
            \\  weight=excluded.weight,
            \\  source_url=excluded.source_url,
            \\  updated_at=excluded.updated_at
        ;
        if (sqlite3_prepare_v2(self.raw, sql_block, -1, &stmt_ins_block, null) != SQLITE_OK) return error.SqlitePrepareFailed;
        const st_b = stmt_ins_block.?;

        for (fc.nodes) |n| {
            _ = sqlite3_reset(st_b);
            _ = bindText(st_b, 1, n.root);
            _ = sqlite3_bind_int64(st_b, 2, @intCast(n.slot));
            _ = bindText(st_b, 3, n.parent_root);
            _ = sqlite3_bind_int64(st_b, 4, @intCast(n.proposer_index));
            _ = sqlite3_bind_int64(st_b, 5, @intCast(n.weight));
            _ = bindText(st_b, 6, source_url);
            _ = sqlite3_bind_int64(st_b, 7, now_ms);
            const step_rc = sqlite3_step(st_b);
            if (step_rc != SQLITE_DONE) return error.SqliteInsertFailed;
        }

        _ = sqlite3_finalize(stmt_ins_block);
        stmt_ins_block = null;

        var stmt_snap: ?*sqlite3_stmt = null;
        defer _ = sqlite3_finalize(stmt_snap);
        const sql_snap =
            \\INSERT INTO fork_choice_snapshot (
            \\  fetched_at, head, justified_slot, justified_root, finalized_slot, finalized_root,
            \\  validator_count, raw_json, source_url
            \\) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ;
        if (sqlite3_prepare_v2(self.raw, sql_snap, -1, &stmt_snap, null) != SQLITE_OK) return error.SqlitePrepareFailed;
        const st_s = stmt_snap.?;

        _ = sqlite3_bind_int64(st_s, 1, now_ms);
        _ = bindText(st_s, 2, fc.head);
        _ = sqlite3_bind_int64(st_s, 3, @intCast(fc.justified.slot));
        _ = bindText(st_s, 4, fc.justified.root);
        _ = sqlite3_bind_int64(st_s, 5, @intCast(fc.finalized.slot));
        _ = bindText(st_s, 6, fc.finalized.root);
        _ = sqlite3_bind_int64(st_s, 7, @intCast(fc.validator_count));
        _ = bindText(st_s, 8, raw_json);
        _ = bindText(st_s, 9, source_url);

        if (sqlite3_step(st_s) != SQLITE_DONE) return error.SqliteInsertFailed;
    }

    pub fn latestSnapshotJson(self: *Db, allocator: std.mem.Allocator) ?[]u8 {
        var stmt: ?*sqlite3_stmt = null;
        defer _ = sqlite3_finalize(stmt);
        const sql = "SELECT raw_json FROM fork_choice_snapshot ORDER BY id DESC LIMIT 1";
        if (sqlite3_prepare_v2(self.raw, sql, -1, &stmt, null) != SQLITE_OK or stmt == null) return null;
        const st = stmt.?;
        if (sqlite3_step(st) != SQLITE_ROW) return null;
        const txt = sqlite3_column_text(st, 0) orelse return null;
        const len = std.mem.len(txt);
        return allocator.dupe(u8, txt[0..len]) catch null;
    }

    pub const Meta = struct {
        fetched_at_ms: i64,
        source_url: []u8,
        head: []u8,
        justified_slot: u64,
        finalized_slot: u64,
        validator_count: u64,

        pub fn deinit(self: Meta, allocator: std.mem.Allocator) void {
            allocator.free(self.source_url);
            allocator.free(self.head);
        }
    };

    pub fn latestMeta(self: *Db, allocator: std.mem.Allocator) !?Meta {
        var stmt: ?*sqlite3_stmt = null;
        defer _ = sqlite3_finalize(stmt);
        const sql =
            \\SELECT fetched_at, source_url, head, justified_slot, finalized_slot, validator_count
            \\FROM fork_choice_snapshot ORDER BY id DESC LIMIT 1
        ;
        if (sqlite3_prepare_v2(self.raw, sql, -1, &stmt, null) != SQLITE_OK or stmt == null) return null;
        const st = stmt.?;
        if (sqlite3_step(st) != SQLITE_ROW) return null;

        const src = sqlite3_column_text(st, 1) orelse return error.SqliteBadRow;
        const head = sqlite3_column_text(st, 2) orelse return error.SqliteBadRow;

        return Meta{
            .fetched_at_ms = sqlite3_column_int64(st, 0),
            .source_url = try allocator.dupe(u8, src[0..std.mem.len(src)]),
            .head = try allocator.dupe(u8, head[0..std.mem.len(head)]),
            .justified_slot = @intCast(sqlite3_column_int64(st, 3)),
            .finalized_slot = @intCast(sqlite3_column_int64(st, 4)),
            .validator_count = @intCast(sqlite3_column_int64(st, 5)),
        };
    }

    pub const BlockRow = struct {
        root: []u8,
        slot: u64,
        parent_root: []u8,
        proposer_index: u64,
        weight: u64,
        source_url: []u8,
        updated_at_ms: i64,

        pub fn deinit(self: BlockRow, allocator: std.mem.Allocator) void {
            allocator.free(self.root);
            allocator.free(self.parent_root);
            allocator.free(self.source_url);
        }
    };

    pub fn blocksAtSlot(self: *Db, allocator: std.mem.Allocator, slot: u64) ![]BlockRow {
        var stmt: ?*sqlite3_stmt = null;
        defer _ = sqlite3_finalize(stmt);
        const sql = "SELECT root, slot, parent_root, proposer_index, weight, source_url, updated_at FROM block_record WHERE slot = ? ORDER BY weight DESC";
        if (sqlite3_prepare_v2(self.raw, sql, -1, &stmt, null) != SQLITE_OK or stmt == null) return error.SqlitePrepareFailed;
        const st = stmt.?;
        _ = sqlite3_bind_int64(st, 1, @intCast(slot));

        var rows: std.ArrayList(BlockRow) = .empty;
        errdefer {
            for (rows.items) |r| r.deinit(allocator);
            rows.deinit(allocator);
        }

        while (sqlite3_step(st) == SQLITE_ROW) {
            const root_t = sqlite3_column_text(st, 0) orelse return error.SqliteBadRow;
            const pr_t = sqlite3_column_text(st, 2) orelse return error.SqliteBadRow;
            const su_t = sqlite3_column_text(st, 5) orelse return error.SqliteBadRow;
            try rows.append(allocator, .{
                .root = try allocator.dupe(u8, root_t[0..std.mem.len(root_t)]),
                .slot = @intCast(sqlite3_column_int64(st, 1)),
                .parent_root = try allocator.dupe(u8, pr_t[0..std.mem.len(pr_t)]),
                .proposer_index = @intCast(sqlite3_column_int64(st, 3)),
                .weight = @intCast(sqlite3_column_int64(st, 4)),
                .source_url = try allocator.dupe(u8, su_t[0..std.mem.len(su_t)]),
                .updated_at_ms = sqlite3_column_int64(st, 6),
            });
        }
        return rows.toOwnedSlice(allocator);
    }

    pub fn blockByRoot(self: *Db, allocator: std.mem.Allocator, root: []const u8) !?BlockRow {
        var stmt: ?*sqlite3_stmt = null;
        defer _ = sqlite3_finalize(stmt);
        const sql = "SELECT root, slot, parent_root, proposer_index, weight, source_url, updated_at FROM block_record WHERE root = ? LIMIT 1";
        if (sqlite3_prepare_v2(self.raw, sql, -1, &stmt, null) != SQLITE_OK or stmt == null) return error.SqlitePrepareFailed;
        const st = stmt.?;
        _ = bindText(st, 1, root);

        if (sqlite3_step(st) != SQLITE_ROW) return null;

        const root_t = sqlite3_column_text(st, 0) orelse return error.SqliteBadRow;
        const pr_t = sqlite3_column_text(st, 2) orelse return error.SqliteBadRow;
        const su_t = sqlite3_column_text(st, 5) orelse return error.SqliteBadRow;
        return BlockRow{
            .root = try allocator.dupe(u8, root_t[0..std.mem.len(root_t)]),
            .slot = @intCast(sqlite3_column_int64(st, 1)),
            .parent_root = try allocator.dupe(u8, pr_t[0..std.mem.len(pr_t)]),
            .proposer_index = @intCast(sqlite3_column_int64(st, 3)),
            .weight = @intCast(sqlite3_column_int64(st, 4)),
            .source_url = try allocator.dupe(u8, su_t[0..std.mem.len(su_t)]),
            .updated_at_ms = sqlite3_column_int64(st, 6),
        };
    }

    pub fn listSlots(self: *Db, allocator: std.mem.Allocator, limit: usize) ![]u64 {
        var stmt: ?*sqlite3_stmt = null;
        defer _ = sqlite3_finalize(stmt);
        const sql = "SELECT DISTINCT slot FROM block_record ORDER BY slot DESC LIMIT ?";
        if (sqlite3_prepare_v2(self.raw, sql, -1, &stmt, null) != SQLITE_OK or stmt == null) return error.SqlitePrepareFailed;
        const st = stmt.?;
        _ = sqlite3_bind_int64(st, 1, @intCast(limit));

        var slots: std.ArrayList(u64) = .empty;
        errdefer slots.deinit(allocator);
        while (sqlite3_step(st) == SQLITE_ROW) {
            try slots.append(allocator, @intCast(sqlite3_column_int64(st, 0)));
        }
        return slots.toOwnedSlice(allocator);
    }
};

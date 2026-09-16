const std = @import("std");

pub const Record = struct {
    request_id: []u8,
    semantic_hash: []u8,
    event_json: []u8,
    seq: u64,
};

pub const AppendResult = struct { seq: u64, duplicate: bool };

pub const MemoryLog = struct {
    allocator: std.mem.Allocator,
    records: std.ArrayList(Record) = .empty,
    sync_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) MemoryLog {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *MemoryLog) void {
        for (self.records.items) |record| {
            self.allocator.free(record.request_id);
            self.allocator.free(record.semantic_hash);
            self.allocator.free(record.event_json);
        }
        self.records.deinit(self.allocator);
    }

    pub fn append(self: *MemoryLog, request_id: []const u8, semantic_hash: []const u8, event_json: []const u8) !AppendResult {
        for (self.records.items) |record| {
            if (!std.mem.eql(u8, record.request_id, request_id)) continue;
            if (!std.mem.eql(u8, record.semantic_hash, semantic_hash)) return error.IdempotencyConflict;
            return .{ .seq = record.seq, .duplicate = true };
        }
        const record = Record{
            .request_id = try self.allocator.dupe(u8, request_id),
            .semantic_hash = try self.allocator.dupe(u8, semantic_hash),
            .event_json = try self.allocator.dupe(u8, event_json),
            .seq = self.records.items.len + 1,
        };
        errdefer self.allocator.free(record.request_id);
        errdefer self.allocator.free(record.semantic_hash);
        errdefer self.allocator.free(record.event_json);
        try self.records.append(self.allocator, record);
        self.sync_count += 1;
        return .{ .seq = record.seq, .duplicate = false };
    }
};

pub fn appendSynced(file: std.Io.File, io: std.Io, bytes: []const u8) !void {
    try file.writeStreamingAll(io, bytes);
    try file.writeStreamingAll(io, "\n");
    try file.sync(io);
}

pub const PersistentRecord = struct {
    seq: u64,
    request_id: []const u8,
    semantic_hash: []const u8,
    event_json: []const u8,
};

pub fn appendPersistent(
    project: std.Io.Dir,
    io: std.Io,
    allocator: std.mem.Allocator,
    request_id: []const u8,
    semantic_hash: []const u8,
    event_json: []const u8,
) !AppendResult {
    try project.createDirPath(io, ".ztasks");
    const existing = project.readFileAlloc(io, ".ztasks/events.jsonl", allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => try allocator.alloc(u8, 0),
        else => return err,
    };
    defer allocator.free(existing);
    var last_seq: u64 = 0;
    var lines = std.mem.splitScalar(u8, existing, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parsed = std.json.parseFromSlice(PersistentRecord, allocator, line, .{ .ignore_unknown_fields = false, .allocate = .alloc_always }) catch return error.StoreCorrupt;
        defer parsed.deinit();
        if (parsed.value.seq != last_seq + 1) return error.StoreCorrupt;
        last_seq = parsed.value.seq;
        if (std.mem.eql(u8, parsed.value.request_id, request_id)) {
            if (!std.mem.eql(u8, parsed.value.semantic_hash, semantic_hash)) return error.IdempotencyConflict;
            return .{ .seq = parsed.value.seq, .duplicate = true };
        }
    }
    const record = PersistentRecord{
        .seq = last_seq + 1,
        .request_id = request_id,
        .semantic_hash = semantic_hash,
        .event_json = event_json,
    };
    const encoded = try std.json.Stringify.valueAlloc(allocator, record, .{});
    defer allocator.free(encoded);
    const line = try allocator.alloc(u8, encoded.len + 1);
    defer allocator.free(line);
    @memcpy(line[0..encoded.len], encoded);
    line[encoded.len] = '\n';
    const file = try project.createFile(io, ".ztasks/events.jsonl", .{ .read = true, .truncate = false });
    defer file.close(io);
    const offset = try file.length(io);
    try file.writePositionalAll(io, line, offset);
    try file.sync(io);
    return .{ .seq = record.seq, .duplicate = false };
}

test "append assigns contiguous sequence and syncs before success" {
    var log = MemoryLog.init(std.testing.allocator);
    defer log.deinit();
    const first = try log.append("req-1", "hash-a", "{\"type\":\"task.started\"}");
    const second = try log.append("req-2", "hash-b", "{\"type\":\"task.progress\"}");
    try std.testing.expectEqual(@as(u64, 1), first.seq);
    try std.testing.expectEqual(@as(u64, 2), second.seq);
    try std.testing.expectEqual(@as(usize, 2), log.sync_count);
}

test "identical request retry returns original without append" {
    var log = MemoryLog.init(std.testing.allocator);
    defer log.deinit();
    const first = try log.append("req-1", "hash-a", "event-a");
    const retry = try log.append("req-1", "hash-a", "event-a");
    try std.testing.expectEqual(first.seq, retry.seq);
    try std.testing.expect(retry.duplicate);
    try std.testing.expectEqual(@as(usize, 1), log.records.items.len);
}

test "request identity conflict is rejected" {
    var log = MemoryLog.init(std.testing.allocator);
    defer log.deinit();
    _ = try log.append("req-1", "hash-a", "event-a");
    try std.testing.expectError(error.IdempotencyConflict, log.append("req-1", "hash-b", "event-b"));
}

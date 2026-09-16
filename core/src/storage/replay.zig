const std = @import("std");

pub const ReplayRecord = struct { seq: u64, request_id: []const u8 };
pub const ReplayResult = struct {
    records: []ReplayRecord,
    parsed: []std.json.Parsed(ReplayRecord),
    last_seq: u64,
    truncated_tail: bool,

    pub fn deinit(self: *ReplayResult, allocator: std.mem.Allocator) void {
        for (self.parsed) |*item| item.deinit();
        allocator.free(self.parsed);
        allocator.free(self.records);
    }
};

pub fn replay(allocator: std.mem.Allocator, bytes: []const u8) !ReplayResult {
    var records: std.ArrayList(ReplayRecord) = .empty;
    errdefer records.deinit(allocator);
    var parsed_items: std.ArrayList(std.json.Parsed(ReplayRecord)) = .empty;
    errdefer {
        for (parsed_items.items) |*item| item.deinit();
        parsed_items.deinit(allocator);
    }
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var offset: usize = 0;
    var truncated_tail = false;
    while (lines.next()) |line| {
        const is_final_fragment = offset + line.len == bytes.len and (bytes.len == 0 or bytes[bytes.len - 1] != '\n');
        offset += line.len + 1;
        if (line.len == 0) continue;
        var parsed = std.json.parseFromSlice(ReplayRecord, allocator, line, .{ .ignore_unknown_fields = false, .allocate = .alloc_always }) catch {
            if (is_final_fragment) {
                truncated_tail = true;
                break;
            }
            return error.StoreCorrupt;
        };
        errdefer parsed.deinit();
        const expected: u64 = records.items.len + 1;
        if (parsed.value.seq != expected) return error.NonContiguousSequence;
        try records.append(allocator, parsed.value);
        try parsed_items.append(allocator, parsed);
    }
    return .{
        .records = try records.toOwnedSlice(allocator),
        .parsed = try parsed_items.toOwnedSlice(allocator),
        .last_seq = records.items.len,
        .truncated_tail = truncated_tail,
    };
}

test "strict replay requires contiguous sequence" {
    const valid = "{\"seq\":1,\"request_id\":\"req-1\"}\n{\"seq\":2,\"request_id\":\"req-2\"}\n";
    var result = try replay(std.testing.allocator, valid);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 2), result.last_seq);
    const gap = "{\"seq\":1,\"request_id\":\"req-1\"}\n{\"seq\":3,\"request_id\":\"req-3\"}\n";
    try std.testing.expectError(error.NonContiguousSequence, replay(std.testing.allocator, gap));
}

test "truncated final fragment is recoverable but interior corruption is fatal" {
    const truncated = "{\"seq\":1,\"request_id\":\"req-1\"}\n{\"seq\":";
    var recovered = try replay(std.testing.allocator, truncated);
    defer recovered.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 1), recovered.last_seq);
    try std.testing.expect(recovered.truncated_tail);
    const interior = "{\"seq\":1,\"request_id\":\"req-1\"}\nnot-json\n{\"seq\":2,\"request_id\":\"req-2\"}\n";
    try std.testing.expectError(error.StoreCorrupt, replay(std.testing.allocator, interior));
}

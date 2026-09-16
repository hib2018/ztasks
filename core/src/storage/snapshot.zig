const std = @import("std");

pub const Snapshot = struct {
    version: u8,
    last_seq: u64,
    prefix_identity: []const u8,
    runtime_json: []const u8,

    pub fn encode(self: Snapshot, allocator: std.mem.Allocator) ![]u8 {
        return std.json.Stringify.valueAlloc(allocator, self, .{});
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(Snapshot) {
        return std.json.parseFromSlice(Snapshot, allocator, bytes, .{ .ignore_unknown_fields = false, .allocate = .alloc_always }) catch error.InvalidSnapshot;
    }

    pub fn validate(self: Snapshot, expected_seq: u64, expected_prefix: []const u8) !void {
        if (self.version != 1 or self.last_seq != expected_seq) return error.StaleSnapshot;
        if (!std.mem.eql(u8, self.prefix_identity, expected_prefix)) return error.PrefixMismatch;
    }
};

pub fn writeAtomic(dir: std.Io.Dir, io: std.Io, path: []const u8, bytes: []const u8) !void {
    var atomic = try dir.createFileAtomic(io, path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(io);
    try atomic.file.writeStreamingAll(io, bytes);
    try atomic.file.sync(io);
    try atomic.replace(io);
}

test "snapshot round trip preserves sequence prefix and runtime bytes" {
    const original = Snapshot{ .version = 1, .last_seq = 42, .prefix_identity = "sha256:abc", .runtime_json = "[{\"task_id\":\"T001\"}]" };
    const encoded = try original.encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    var decoded = try Snapshot.decode(std.testing.allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqual(original.last_seq, decoded.value.last_seq);
    try std.testing.expectEqualStrings(original.prefix_identity, decoded.value.prefix_identity);
    try std.testing.expectEqualStrings(original.runtime_json, decoded.value.runtime_json);
}

test "stale sequence and prefix mismatch reject snapshot" {
    const snapshot = Snapshot{ .version = 1, .last_seq = 42, .prefix_identity = "sha256:abc", .runtime_json = "[]" };
    try std.testing.expectError(error.StaleSnapshot, snapshot.validate(43, "sha256:abc"));
    try std.testing.expectError(error.PrefixMismatch, snapshot.validate(42, "sha256:def"));
}

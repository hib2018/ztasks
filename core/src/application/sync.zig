const std = @import("std");

pub const Definition = struct { id: []const u8, fingerprint: []const u8 };
pub const Prior = struct { id: []const u8, fingerprint: []const u8, missing: bool = false };

pub const Authority = struct {
    source_digest: []const u8,
    last_event_seq: u64,
};

pub const Transaction = struct {
    prior: Authority,
    candidate_digest: []const u8,
    artifact_persisted: bool = false,
    event_committed: bool = false,

    pub fn artifactPersisted(self: *Transaction) void {
        self.artifact_persisted = true;
    }

    pub fn eventCommitted(self: *Transaction) !void {
        if (!self.artifact_persisted) return error.ArtifactNotPersisted;
        self.event_committed = true;
    }

    pub fn authority(self: Transaction) Authority {
        if (!self.event_committed) return self.prior;
        return .{ .source_digest = self.candidate_digest, .last_event_seq = self.prior.last_event_seq + 1 };
    }

    pub fn hasInertArtifact(self: Transaction) bool {
        return self.artifact_persisted and !self.event_committed;
    }
};

pub const ChangeSet = struct {
    added: []const []const u8,
    changed: []const []const u8,
    missing: []const []const u8,
    reappeared: []const []const u8,

    pub fn deinit(self: ChangeSet, allocator: std.mem.Allocator) void {
        for (self.added) |value| allocator.free(value);
        for (self.changed) |value| allocator.free(value);
        for (self.missing) |value| allocator.free(value);
        for (self.reappeared) |value| allocator.free(value);
        allocator.free(self.added);
        allocator.free(self.changed);
        allocator.free(self.missing);
        allocator.free(self.reappeared);
    }
};

pub fn diff(allocator: std.mem.Allocator, prior: []const Prior, current: []const Definition) !ChangeSet {
    var added: std.ArrayList([]const u8) = .empty;
    var changed: std.ArrayList([]const u8) = .empty;
    var missing: std.ArrayList([]const u8) = .empty;
    var reappeared: std.ArrayList([]const u8) = .empty;
    errdefer for (added.items) |value| allocator.free(value);
    errdefer for (changed.items) |value| allocator.free(value);
    errdefer for (missing.items) |value| allocator.free(value);
    errdefer for (reappeared.items) |value| allocator.free(value);
    defer added.deinit(allocator);
    defer changed.deinit(allocator);
    defer missing.deinit(allocator);
    defer reappeared.deinit(allocator);
    for (current) |definition| {
        const old = findPrior(prior, definition.id) orelse {
            try added.append(allocator, try allocator.dupe(u8, definition.id));
            continue;
        };
        if (old.missing) try reappeared.append(allocator, try allocator.dupe(u8, definition.id));
        if (!std.mem.eql(u8, old.fingerprint, definition.fingerprint)) try changed.append(allocator, try allocator.dupe(u8, definition.id));
    }
    for (prior) |old| if (!old.missing and findDefinition(current, old.id) == null) try missing.append(allocator, try allocator.dupe(u8, old.id));
    return .{
        .added = try added.toOwnedSlice(allocator),
        .changed = try changed.toOwnedSlice(allocator),
        .missing = try missing.toOwnedSlice(allocator),
        .reappeared = try reappeared.toOwnedSlice(allocator),
    };
}

fn findPrior(values: []const Prior, id: []const u8) ?Prior {
    for (values) |value| if (std.mem.eql(u8, value.id, id)) return value;
    return null;
}

fn findDefinition(values: []const Definition, id: []const u8) ?Definition {
    for (values) |value| if (std.mem.eql(u8, value.id, id)) return value;
    return null;
}

test "sync diff distinguishes added changed missing reappeared and no change" {
    const result = try diff(std.testing.allocator, &.{
        .{ .id = "T001", .fingerprint = "old" },
        .{ .id = "T002", .fingerprint = "same" },
        .{ .id = "T003", .fingerprint = "gone" },
        .{ .id = "T004", .fingerprint = "before", .missing = true },
    }, &.{
        .{ .id = "T001", .fingerprint = "new" },
        .{ .id = "T002", .fingerprint = "same" },
        .{ .id = "T004", .fingerprint = "after" },
        .{ .id = "T005", .fingerprint = "added" },
    });
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("T005", result.added[0]);
    try std.testing.expectEqualStrings("T001", result.changed[0]);
    try std.testing.expectEqualStrings("T003", result.missing[0]);
    try std.testing.expectEqualStrings("T004", result.reappeared[0]);
}

test "no-change sync still produces an empty auditable change set" {
    const result = try diff(std.testing.allocator, &.{.{ .id = "T001", .fingerprint = "same" }}, &.{.{ .id = "T001", .fingerprint = "same" }});
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.added.len + result.changed.len + result.missing.len + result.reappeared.len);
}

test "invalid source and artifact failure preserve prior authority" {
    const prior = Authority{ .source_digest = "sha256:old", .last_event_seq = 4 };
    const transaction = Transaction{ .prior = prior, .candidate_digest = "sha256:new" };
    try std.testing.expectEqualStrings("sha256:old", transaction.authority().source_digest);
    try std.testing.expectEqual(@as(u64, 4), transaction.authority().last_event_seq);
}

test "artifact written but event failed remains inert and prior authority wins" {
    const prior = Authority{ .source_digest = "sha256:old", .last_event_seq = 4 };
    var transaction = Transaction{ .prior = prior, .candidate_digest = "sha256:new" };
    transaction.artifactPersisted();
    try std.testing.expect(transaction.hasInertArtifact());
    try std.testing.expectEqualStrings("sha256:old", transaction.authority().source_digest);
}

test "event commit requires artifacts and atomically advances authority even if snapshot later fails" {
    const prior = Authority{ .source_digest = "sha256:old", .last_event_seq = 4 };
    var invalid = Transaction{ .prior = prior, .candidate_digest = "sha256:new" };
    try std.testing.expectError(error.ArtifactNotPersisted, invalid.eventCommitted());

    var transaction = Transaction{ .prior = prior, .candidate_digest = "sha256:new" };
    transaction.artifactPersisted();
    try transaction.eventCommitted();
    try std.testing.expectEqualStrings("sha256:new", transaction.authority().source_digest);
    try std.testing.expectEqual(@as(u64, 5), transaction.authority().last_event_seq);
}

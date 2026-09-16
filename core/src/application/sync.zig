const std = @import("std");

pub const Definition = struct { id: []const u8, fingerprint: []const u8 };
pub const Prior = struct { id: []const u8, fingerprint: []const u8, missing: bool = false };

pub const ChangeSet = struct {
    added: []const []const u8,
    changed: []const []const u8,
    missing: []const []const u8,
    reappeared: []const []const u8,

    pub fn deinit(self: ChangeSet, allocator: std.mem.Allocator) void {
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
    defer added.deinit(allocator);
    defer changed.deinit(allocator);
    defer missing.deinit(allocator);
    defer reappeared.deinit(allocator);
    for (current) |definition| {
        const old = findPrior(prior, definition.id) orelse {
            try added.append(allocator, definition.id);
            continue;
        };
        if (old.missing) try reappeared.append(allocator, definition.id);
        if (!std.mem.eql(u8, old.fingerprint, definition.fingerprint)) try changed.append(allocator, definition.id);
    }
    for (prior) |old| if (!old.missing and findDefinition(current, old.id) == null) try missing.append(allocator, old.id);
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

const std = @import("std");

pub const Severity = enum { info, warning, @"error" };

pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity,
    message: []const u8,
};

pub const Probe = struct {
    source_valid: bool = true,
    history_valid: bool = true,
    snapshot_present: bool = false,
    snapshot_current: bool = true,
    orphan_artifact_count: usize = 0,
    lock_available: bool = true,
    filesystem_writable: bool = true,
};

pub const Report = struct {
    diagnostics: []Diagnostic,

    pub fn deinit(self: Report, allocator: std.mem.Allocator) void {
        allocator.free(self.diagnostics);
    }

    pub fn healthy(self: Report) bool {
        for (self.diagnostics) |diagnostic| if (diagnostic.severity == .@"error") return false;
        return true;
    }
};

pub fn diagnose(allocator: std.mem.Allocator, probe: Probe) !Report {
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    defer diagnostics.deinit(allocator);
    if (!probe.source_valid) try diagnostics.append(allocator, .{ .code = "source.invalid", .severity = .@"error", .message = "Task source cannot be parsed" });
    if (!probe.history_valid) try diagnostics.append(allocator, .{ .code = "history.corrupt", .severity = .@"error", .message = "Event history is corrupt" });
    if (probe.snapshot_present and !probe.snapshot_current) try diagnostics.append(allocator, .{ .code = "snapshot.stale", .severity = .warning, .message = "Snapshot is stale and can be rebuilt from Events" });
    if (probe.orphan_artifact_count != 0) try diagnostics.append(allocator, .{ .code = "artifact.orphaned", .severity = .warning, .message = "Unreferenced immutable source artifacts are inert" });
    if (!probe.lock_available) try diagnostics.append(allocator, .{ .code = "lock.busy", .severity = .warning, .message = "Another writer currently holds the Project lock" });
    if (!probe.filesystem_writable) try diagnostics.append(allocator, .{ .code = "filesystem.read_only", .severity = .@"error", .message = "Runtime directory is not writable" });
    if (diagnostics.items.len == 0) try diagnostics.append(allocator, .{ .code = "project.healthy", .severity = .info, .message = "No Project integrity problems found" });
    return .{ .diagnostics = try diagnostics.toOwnedSlice(allocator) };
}

test "doctor reports corrupt history stale snapshot orphan artifact and filesystem failure" {
    const report = try diagnose(std.testing.allocator, .{
        .history_valid = false,
        .snapshot_present = true,
        .snapshot_current = false,
        .orphan_artifact_count = 2,
        .filesystem_writable = false,
    });
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(!report.healthy());
    try std.testing.expectEqual(@as(usize, 4), report.diagnostics.len);
    try std.testing.expectEqualStrings("history.corrupt", report.diagnostics[0].code);
    try std.testing.expectEqualStrings("snapshot.stale", report.diagnostics[1].code);
    try std.testing.expectEqualStrings("artifact.orphaned", report.diagnostics[2].code);
    try std.testing.expectEqualStrings("filesystem.read_only", report.diagnostics[3].code);
}

test "doctor distinguishes a busy lock from an unhealthy Project" {
    const report = try diagnose(std.testing.allocator, .{ .lock_available = false });
    defer report.deinit(std.testing.allocator);
    try std.testing.expect(report.healthy());
    try std.testing.expectEqualStrings("lock.busy", report.diagnostics[0].code);
}

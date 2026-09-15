const std = @import("std");

pub const TaskSourceKind = enum { speckit };

pub const Resolution = struct {
    kind: TaskSourceKind = .speckit,
    locator: []const u8,
};

pub fn resolve(
    explicit: ?[]const u8,
    active_feature: ?[]const u8,
    fallback_candidates: []const []const u8,
) !Resolution {
    if (explicit) |locator| return checked(locator);
    if (active_feature) |locator| return checked(locator);
    if (fallback_candidates.len == 0) return error.SourceNotFound;
    if (fallback_candidates.len != 1) return error.SourceAmbiguous;
    return checked(fallback_candidates[0]);
}

fn checked(locator: []const u8) !Resolution {
    if (locator.len == 0 or std.fs.path.isAbsolute(locator) or std.mem.indexOfScalar(u8, locator, '\\') != null) {
        return error.PathEscapesProject;
    }
    var components = std.mem.splitScalar(u8, locator, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) {
            return error.PathEscapesProject;
        }
    }
    if (!std.mem.endsWith(u8, locator, "/tasks.md") and !std.mem.eql(u8, locator, "tasks.md")) {
        return error.InvalidSourceLocator;
    }
    return .{ .locator = locator };
}

test "source resolution precedence is explicit then feature then sole candidate" {
    try std.testing.expectEqualStrings("specs/explicit/tasks.md", (try resolve("specs/explicit/tasks.md", "specs/active/tasks.md", &.{"specs/only/tasks.md"})).locator);
    try std.testing.expectEqualStrings("specs/active/tasks.md", (try resolve(null, "specs/active/tasks.md", &.{"specs/only/tasks.md"})).locator);
    try std.testing.expectEqualStrings("specs/only/tasks.md", (try resolve(null, null, &.{"specs/only/tasks.md"})).locator);
}

test "source resolution rejects absence ambiguity and project escape" {
    try std.testing.expectError(error.SourceNotFound, resolve(null, null, &.{}));
    try std.testing.expectError(error.SourceAmbiguous, resolve(null, null, &.{ "specs/a/tasks.md", "specs/b/tasks.md" }));
    try std.testing.expectError(error.PathEscapesProject, resolve("../tasks.md", null, &.{}));
    try std.testing.expectError(error.PathEscapesProject, resolve("/tmp/tasks.md", null, &.{}));
}

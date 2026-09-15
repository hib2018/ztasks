const std = @import("std");
const content_policy = @import("content_policy.zig");

pub const SourceSpan = struct {
    locator: []const u8,
    line: u32,
    column: u32,

    pub fn validate(self: SourceSpan) !void {
        content_policy.validateSourceLocator(self.locator) catch |err| switch (err) {
            error.InvalidSourceLocator => return error.InvalidSourceLocator,
            else => return err,
        };
        if (self.line == 0 or self.column == 0) return error.InvalidSourceSpan;
    }
};

pub const PhaseDefinition = struct {
    id: []const u8,
    title: []const u8,
    order: u32,
    source: SourceSpan,

    pub fn validate(self: PhaseDefinition) !void {
        content_policy.validateIdentifier(self.id) catch return error.InvalidIdentifier;
        content_policy.validateTitle(self.title) catch |err| return err;
        try self.source.validate();
    }
};

pub const MetadataValue = union(enum) {
    string: []const u8,
    integer: i64,
    boolean: bool,
};

pub const MetadataEntry = struct {
    key: []const u8,
    value: MetadataValue,

    pub fn validate(self: MetadataEntry) !void {
        content_policy.validateIdentifier(self.key) catch return error.InvalidMetadata;
        switch (self.value) {
            .string => |value| content_policy.validateRequiredText(value, content_policy.message_limit, true) catch return error.InvalidMetadata,
            .integer, .boolean => {},
        }
    }
};

pub const TaskDefinition = struct {
    id: []const u8,
    title: []const u8,
    phase_id: []const u8,
    order: u32,
    dependencies: []const []const u8,
    parallel_hint: bool,
    story: ?[]const u8,
    source: SourceSpan,
    source_checked: bool,
    metadata: []const MetadataEntry,

    pub fn validate(self: TaskDefinition) !void {
        if (!isTaskId(self.id)) return error.InvalidTaskId;
        try content_policy.validateTitle(self.title);
        content_policy.validateIdentifier(self.phase_id) catch return error.InvalidIdentifier;
        if (self.story) |story| content_policy.validateIdentifier(story) catch return error.InvalidIdentifier;
        try self.source.validate();

        for (self.dependencies, 0..) |dependency, index| {
            if (!isTaskId(dependency)) return error.InvalidTaskId;
            if (std.mem.eql(u8, dependency, self.id)) return error.SelfDependency;
            for (self.dependencies[0..index]) |prior| {
                if (std.mem.eql(u8, dependency, prior)) return error.DuplicateDependency;
            }
        }
        for (self.metadata) |entry| try entry.validate();
    }

    pub fn invalidForTest(id: []const u8) TaskDefinition {
        return .{
            .id = id,
            .title = "Valid title",
            .phase_id = "phase-1",
            .order = 0,
            .dependencies = &.{},
            .parallel_hint = false,
            .story = null,
            .source = .{ .locator = "specs/001/tasks.md", .line = 1, .column = 1 },
            .source_checked = false,
            .metadata = &.{},
        };
    }
};

pub fn isTaskId(value: []const u8) bool {
    if (value.len < 2 or value[0] != 'T') return false;
    for (value[1..]) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}

test "source spans require project relative locator and one-based coordinates" {
    const valid = SourceSpan{ .locator = "specs/001/tasks.md", .line = 1, .column = 1 };
    try valid.validate();
    try std.testing.expectError(error.InvalidSourceLocator, (SourceSpan{ .locator = "../tasks.md", .line = 1, .column = 1 }).validate());
    try std.testing.expectError(error.InvalidSourceSpan, (SourceSpan{ .locator = "tasks.md", .line = 0, .column = 1 }).validate());
}

test "phase definitions validate required identity title and order" {
    const phase = PhaseDefinition{
        .id = "phase-1",
        .title = "Setup",
        .order = 0,
        .source = .{ .locator = "specs/001/tasks.md", .line = 3, .column = 1 },
    };
    try phase.validate();
    try std.testing.expectError(error.InvalidIdentifier, (PhaseDefinition{ .id = "", .title = "Setup", .order = 0, .source = phase.source }).validate());
}

test "task definitions validate id title references and metadata" {
    const dependencies = [_][]const u8{"T001"};
    const metadata = [_]MetadataEntry{.{ .key = "priority", .value = .{ .string = "P1" } }};
    const task = TaskDefinition{
        .id = "T002",
        .title = "Add protocol",
        .phase_id = "phase-1",
        .order = 1,
        .dependencies = &dependencies,
        .parallel_hint = false,
        .story = "US1",
        .source = .{ .locator = "specs/001/tasks.md", .line = 6, .column = 1 },
        .source_checked = false,
        .metadata = &metadata,
    };
    try task.validate();
    try std.testing.expectError(error.InvalidTaskId, (TaskDefinition.invalidForTest("001")).validate());
}

test "task dependencies reject duplicate and self references" {
    var task = TaskDefinition.invalidForTest("T002");
    task.dependencies = &.{ "T001", "T001" };
    try std.testing.expectError(error.DuplicateDependency, task.validate());
    task.dependencies = &.{"T002"};
    try std.testing.expectError(error.SelfDependency, task.validate());
}

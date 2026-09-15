const std = @import("std");
const definition_query = @import("definition_query.zig");
const reducer = @import("../domain/reducer.zig");
const speckit = @import("../sources/speckit.zig");

pub const OperationClass = enum { query, mutation };
pub const OperationMapping = struct {
    class: OperationClass,
    event_type: ?[]const u8,
};

pub fn classify(operation: []const u8) !OperationMapping {
    const queries = [_][]const u8{
        "version.get", "project.inspect", "task.list",    "task.show",
        "event.list",  "source.validate", "health.check",
    };
    for (queries) |query| {
        if (std.mem.eql(u8, operation, query)) return .{ .class = .query, .event_type = null };
    }
    const mutations = [_]struct { operation: []const u8, event_type: []const u8 }{
        .{ .operation = "project.init", .event_type = "project.initialized" },
        .{ .operation = "source.sync", .event_type = "source.synced" },
        .{ .operation = "task.start", .event_type = "task.started" },
        .{ .operation = "task.progress", .event_type = "task.progress" },
        .{ .operation = "task.pause_ack", .event_type = "task.paused" },
        .{ .operation = "task.resume_ack", .event_type = "task.resumed" },
        .{ .operation = "task.block", .event_type = "task.blocked" },
        .{ .operation = "task.fail", .event_type = "task.failed" },
        .{ .operation = "task.complete", .event_type = "task.completed" },
        .{ .operation = "task.skip", .event_type = "task.skipped" },
        .{ .operation = "task.comment", .event_type = "task.comment" },
        .{ .operation = "human.pause_request", .event_type = "human.pause_requested" },
        .{ .operation = "human.resume_request", .event_type = "human.resume_requested" },
        .{ .operation = "human.retry_request", .event_type = "human.retry_requested" },
        .{ .operation = "human.stop_request", .event_type = "human.stop_requested" },
        .{ .operation = "human.skip_request", .event_type = "human.skip_requested" },
        .{ .operation = "human.inspect_request", .event_type = "human.inspect_requested" },
        .{ .operation = "human.comment", .event_type = "human.comment" },
        .{ .operation = "intervention.respond", .event_type = "intervention.responded" },
    };
    for (mutations) |mutation| {
        if (std.mem.eql(u8, operation, mutation.operation)) return .{ .class = .mutation, .event_type = mutation.event_type };
    }
    return error.UnknownOperation;
}

pub fn validateSource(
    allocator: std.mem.Allocator,
    locator: []const u8,
    markdown: []const u8,
) !speckit.ParsedBatch {
    var batch = try speckit.parse(allocator, locator, markdown);
    errdefer batch.deinit(allocator);
    const inputs = try allocator.alloc(definition_query.DefinitionInput, batch.tasks.len);
    defer allocator.free(inputs);
    for (batch.tasks, 0..) |task, index| {
        inputs[index] = .{ .id = task.id, .dependencies = task.dependencies };
    }
    try definition_query.validateDefinitions(inputs);
    return batch;
}

pub fn listInitial(
    allocator: std.mem.Allocator,
    batch: *const speckit.ParsedBatch,
) !reducer.Projection {
    const inputs = try allocator.alloc(reducer.DefinitionInput, batch.tasks.len);
    defer allocator.free(inputs);
    for (batch.tasks, 0..) |task, index| {
        inputs[index] = .{ .id = task.id, .dependencies = task.dependencies };
    }
    return reducer.projectInitial(allocator, inputs, &.{});
}

pub fn showIndex(batch: *const speckit.ParsedBatch, task_id: []const u8) !usize {
    for (batch.tasks, 0..) |task, index| {
        if (std.mem.eql(u8, task.id, task_id)) return index;
    }
    return error.TaskNotFound;
}

test "read operations never map to events" {
    const operations = [_][]const u8{ "task.list", "task.show", "source.validate" };
    for (operations) |operation| {
        const mapping = try classify(operation);
        try std.testing.expectEqual(OperationClass.query, mapping.class);
        try std.testing.expect(mapping.event_type == null);
    }
}

test "unknown operations are rejected" {
    try std.testing.expectError(error.UnknownOperation, classify("task.delete"));
}

test "source validation list and show remain read-only services" {
    const markdown =
        \\## Phase 1
        \\- [ ] T001 Base
        \\- [ ] T002 Work (depends on T001)
    ;
    var batch = try validateSource(std.testing.allocator, "tasks.md", markdown);
    defer batch.deinit(std.testing.allocator);
    var projection = try listInitial(std.testing.allocator, &batch);
    defer projection.deinit(std.testing.allocator);
    try std.testing.expectEqual(reducer.Status.ready, projection.tasks[0].status);
    try std.testing.expectEqual(reducer.Status.pending, projection.tasks[1].status);
    try std.testing.expectEqual(@as(usize, 1), try showIndex(&batch, "T002"));
    try std.testing.expectError(error.TaskNotFound, showIndex(&batch, "T999"));
}

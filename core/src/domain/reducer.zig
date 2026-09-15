const std = @import("std");
const task_runtime = @import("task_runtime.zig");

pub const Status = task_runtime.RuntimeStatus;

pub const DefinitionInput = struct {
    id: []const u8,
    dependencies: []const []const u8,
};

pub const ExistingRuntime = struct {
    id: []const u8,
    status: Status,
};

pub const ProjectedTask = struct {
    id: []const u8,
    status: Status,
    unsatisfied: []const []const u8,
};

pub const Projection = struct {
    tasks: []ProjectedTask,

    pub fn deinit(self: *Projection, allocator: std.mem.Allocator) void {
        for (self.tasks) |task| allocator.free(task.unsatisfied);
        allocator.free(self.tasks);
    }
};

pub fn projectInitial(
    allocator: std.mem.Allocator,
    definitions: []const DefinitionInput,
    existing: []const ExistingRuntime,
) !Projection {
    const tasks = try allocator.alloc(ProjectedTask, definitions.len);
    errdefer allocator.free(tasks);
    var initialized: usize = 0;
    errdefer for (tasks[0..initialized]) |task| allocator.free(task.unsatisfied);

    for (definitions, 0..) |definition, index| {
        var unsatisfied: std.ArrayList([]const u8) = .empty;
        defer unsatisfied.deinit(allocator);
        for (definition.dependencies) |dependency| {
            const status = findStatus(existing, dependency);
            if (status == null or (status.? != .completed and status.? != .skipped)) {
                try unsatisfied.append(allocator, dependency);
            }
        }
        const owned = try unsatisfied.toOwnedSlice(allocator);
        tasks[index] = .{
            .id = definition.id,
            .status = if (owned.len == 0) .ready else .pending,
            .unsatisfied = owned,
        };
        initialized += 1;
    }
    return .{ .tasks = tasks };
}

fn findStatus(existing: []const ExistingRuntime, id: []const u8) ?Status {
    for (existing) |runtime| {
        if (std.mem.eql(u8, runtime.id, id)) return runtime.status;
    }
    return null;
}

test "initial projection derives pending and ready without events" {
    var projection = try projectInitial(std.testing.allocator, &.{
        .{ .id = "T001", .dependencies = &.{} },
        .{ .id = "T002", .dependencies = &.{"T001"} },
    }, &.{});
    defer projection.deinit(std.testing.allocator);
    try std.testing.expectEqual(Status.ready, projection.tasks[0].status);
    try std.testing.expectEqual(Status.pending, projection.tasks[1].status);
    try std.testing.expectEqualStrings("T001", projection.tasks[1].unsatisfied[0]);
}

test "completed and skipped dependencies both unlock readiness" {
    var completed = try projectInitial(std.testing.allocator, &.{.{ .id = "T002", .dependencies = &.{ "T001", "T003" } }}, &.{
        .{ .id = "T001", .status = .completed },
        .{ .id = "T003", .status = .skipped },
    });
    defer completed.deinit(std.testing.allocator);
    try std.testing.expectEqual(Status.ready, completed.tasks[0].status);
}

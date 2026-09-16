const std = @import("std");
const task_runtime = @import("task_runtime.zig");
const event = @import("event.zig");
const transition = @import("transition.zig");
const intervention = @import("intervention.zig");

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

pub const ExecutionFact = struct {
    event_type: event.EventType,
    seq: u64,
    timestamp: []const u8,
    agent: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    message: ?[]const u8 = null,
    retry_correlated: bool = false,
};

pub fn applyExecution(state: *task_runtime.TaskRuntime, fact: ExecutionFact) !void {
    if (fact.seq != state.last_event_seq + 1) return error.NonContiguousSequence;
    const needs_reason = fact.event_type == .task_blocked or fact.event_type == .task_failed;
    const next = try transition.validate(state.status, fact.event_type, .{
        .has_required_reason = !needs_reason or (fact.message != null and fact.message.?.len != 0),
        .has_retry_correlation = fact.retry_correlated,
    });
    switch (fact.event_type) {
        .task_started => {
            state.attempt += 1;
            state.started_at = fact.timestamp;
            if (fact.agent) |agent| state.agent = agent;
            if (fact.session_id) |session| state.session_id = session;
            state.current_action = null;
            state.blocked_reason = null;
            state.last_error = null;
        },
        .task_progress => state.current_action = fact.message,
        .task_blocked => state.blocked_reason = fact.message,
        .task_failed => state.last_error = .{ .code = "execution_failed", .message = fact.message.? },
        .task_resumed => state.blocked_reason = null,
        .task_completed, .task_skipped => state.current_action = null,
        .task_paused, .task_comment => {},
        else => return error.InvalidEvent,
    }
    state.status = next;
    state.updated_at = fact.timestamp;
    state.last_event_seq = fact.seq;
}

pub fn replayTask(task_id: []const u8, dependencies_satisfied: bool, facts: []const ExecutionFact) !task_runtime.TaskRuntime {
    var state = task_runtime.TaskRuntime.init(task_id, dependencies_satisfied);
    for (facts) |fact| try applyExecution(&state, fact);
    return state;
}

pub const InterventionState = intervention.InterventionState;
pub const InterventionProjection = struct {
    request_event_id: []const u8,
    action: intervention.InterventionAction,
    state: InterventionState,
    response_event_id: ?[]const u8 = null,
    lifecycle_event_id: ?[]const u8 = null,

    pub fn init(request_event_id: []const u8, action: intervention.InterventionAction) InterventionProjection {
        return .{ .request_event_id = request_event_id, .action = action, .state = .pending };
    }
};

pub const InterventionFact = struct {
    kind: enum { responded, lifecycle_resolved },
    event_id: []const u8,
    outcome: intervention.ResponseOutcome = .acknowledged,
};

pub fn reduceIntervention(projection: *InterventionProjection, fact: InterventionFact) !void {
    switch (fact.kind) {
        .responded => {
            if (projection.state != .pending) return error.InvalidIntervention;
            projection.response_event_id = fact.event_id;
            projection.state = switch (fact.outcome) {
                .acknowledged => .acknowledged,
                .rejected => .rejected,
                .unsupported => .unsupported,
                .completed => .resolved,
            };
        },
        .lifecycle_resolved => {
            if (projection.state == .rejected or projection.state == .unsupported or projection.state == .resolved) return error.InvalidIntervention;
            projection.lifecycle_event_id = fact.event_id;
            projection.state = .resolved;
        },
    }
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

test "execution reduction updates attempts action and lifecycle" {
    var state = task_runtime.TaskRuntime.init("T001", true);
    try applyExecution(&state, .{ .event_type = .task_started, .seq = 1, .timestamp = "2026-09-16T00:00:00Z", .agent = "pi", .session_id = "run-1" });
    try std.testing.expectEqual(Status.running, state.status);
    try std.testing.expectEqual(@as(u32, 1), state.attempt);
    try applyExecution(&state, .{ .event_type = .task_progress, .seq = 2, .timestamp = "2026-09-16T00:01:00Z", .message = "editing parser" });
    try std.testing.expectEqualStrings("editing parser", state.current_action.?);
    try applyExecution(&state, .{ .event_type = .task_failed, .seq = 3, .timestamp = "2026-09-16T00:02:00Z", .message = "compile failed" });
    try std.testing.expectEqual(Status.failed, state.status);
    try applyExecution(&state, .{ .event_type = .task_started, .seq = 4, .timestamp = "2026-09-16T00:03:00Z", .retry_correlated = true });
    try std.testing.expectEqual(@as(u32, 2), state.attempt);
}

test "replay is deterministic and terminal dependency unlock is immediate" {
    const facts = [_]ExecutionFact{
        .{ .event_type = .task_started, .seq = 1, .timestamp = "2026-09-16T00:00:00Z" },
        .{ .event_type = .task_completed, .seq = 2, .timestamp = "2026-09-16T00:01:00Z" },
    };
    const first = try replayTask("T001", true, &facts);
    const second = try replayTask("T001", true, &facts);
    try std.testing.expectEqualDeep(first, second);
    const downstream = try projectInitial(std.testing.allocator, &.{.{ .id = "T002", .dependencies = &.{"T001"} }}, &.{.{ .id = "T001", .status = first.status }});
    var projection = downstream;
    defer projection.deinit(std.testing.allocator);
    try std.testing.expectEqual(Status.ready, projection.tasks[0].status);
}

test "intervention reduction distinguishes pending response and lifecycle resolution" {
    var projection = InterventionProjection.init("request-1", .pause);
    try reduceIntervention(&projection, .{ .kind = .responded, .event_id = "response-1", .outcome = .acknowledged });
    try std.testing.expectEqual(InterventionState.acknowledged, projection.state);
    try reduceIntervention(&projection, .{ .kind = .lifecycle_resolved, .event_id = "paused-1" });
    try std.testing.expectEqual(InterventionState.resolved, projection.state);
}

test "rejected and unsupported intervention outcomes remain explicit" {
    var rejected = InterventionProjection.init("request-1", .stop);
    try reduceIntervention(&rejected, .{ .kind = .responded, .event_id = "response-1", .outcome = .rejected });
    try std.testing.expectEqual(InterventionState.rejected, rejected.state);
    var unsupported = InterventionProjection.init("request-2", .pause);
    try reduceIntervention(&unsupported, .{ .kind = .responded, .event_id = "response-2", .outcome = .unsupported });
    try std.testing.expectEqual(InterventionState.unsupported, unsupported.state);
}

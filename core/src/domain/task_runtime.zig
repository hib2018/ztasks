const std = @import("std");
const content_policy = @import("content_policy.zig");
const task_definition = @import("task_definition.zig");

pub const RuntimeStatus = enum {
    pending,
    ready,
    running,
    paused,
    blocked,
    failed,
    completed,
    skipped,

    pub fn parse(value: []const u8) ?RuntimeStatus {
        inline for (std.meta.fields(RuntimeStatus)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn isTerminal(self: RuntimeStatus) bool {
        return self == .completed or self == .skipped;
    }
};

pub const DefinitionState = enum {
    current,
    missing,

    pub fn parse(value: []const u8) ?DefinitionState {
        inline for (std.meta.fields(DefinitionState)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }
};

pub const ErrorDetail = struct {
    code: []const u8,
    message: []const u8,

    pub fn validate(self: ErrorDetail) !void {
        content_policy.validateIdentifier(self.code) catch return error.InvalidIdentifier;
        try content_policy.validateMessage(self.message);
    }
};

pub const PendingIntervention = struct {
    event_id: []const u8,
    action: []const u8,
};

pub const TaskRuntime = struct {
    task_id: []const u8,
    definition_state: DefinitionState,
    status: RuntimeStatus,
    agent: ?[]const u8,
    session_id: ?[]const u8,
    attempt: u32,
    started_at: ?[]const u8,
    updated_at: ?[]const u8,
    current_action: ?[]const u8,
    blocked_reason: ?[]const u8,
    last_error: ?ErrorDetail,
    pending_interventions: []const PendingIntervention,
    unsatisfied_dependencies: []const []const u8,
    last_event_seq: u64,

    pub fn init(task_id: []const u8, dependencies_satisfied: bool) TaskRuntime {
        return .{
            .task_id = task_id,
            .definition_state = .current,
            .status = if (dependencies_satisfied) .ready else .pending,
            .agent = null,
            .session_id = null,
            .attempt = 0,
            .started_at = null,
            .updated_at = null,
            .current_action = null,
            .blocked_reason = null,
            .last_error = null,
            .pending_interventions = &.{},
            .unsatisfied_dependencies = &.{},
            .last_event_seq = 0,
        };
    }

    pub fn validate(self: TaskRuntime) !void {
        if (!task_definition.isTaskId(self.task_id)) return error.InvalidTaskId;
        if (self.agent) |agent| try content_policy.validateIdentifier(agent);
        if (self.session_id) |session| try content_policy.validateIdentifier(session);
        if (self.current_action) |action| try content_policy.validateMessage(action);
        if (self.blocked_reason) |reason| try content_policy.validateMessage(reason);
        if (self.last_error) |detail| try detail.validate();
        for (self.unsatisfied_dependencies) |dependency| {
            if (!task_definition.isTaskId(dependency)) return error.InvalidTaskId;
        }
    }
};

test "runtime and definition states are closed enums" {
    try std.testing.expectEqual(RuntimeStatus.ready, RuntimeStatus.parse("ready").?);
    try std.testing.expect(RuntimeStatus.parse("todo") == null);
    try std.testing.expectEqual(DefinitionState.missing, DefinitionState.parse("missing").?);
}

test "task runtime starts from dependency-derived status" {
    const ready = TaskRuntime.init("T001", true);
    try std.testing.expectEqual(RuntimeStatus.ready, ready.status);
    try std.testing.expectEqual(@as(u32, 0), ready.attempt);

    const pending = TaskRuntime.init("T002", false);
    try std.testing.expectEqual(RuntimeStatus.pending, pending.status);
    try std.testing.expectEqual(DefinitionState.current, pending.definition_state);
}

test "safe error detail stores only sanitized summary" {
    const detail = ErrorDetail{ .code = "compile_failed", .message = "compiler returned an error" };
    try detail.validate();
    try std.testing.expectError(error.InvalidText, (ErrorDetail{ .code = "compile_failed", .message = "secret\x00" }).validate());
}

test "terminal status classification is explicit" {
    try std.testing.expect(RuntimeStatus.completed.isTerminal());
    try std.testing.expect(RuntimeStatus.skipped.isTerminal());
    try std.testing.expect(!RuntimeStatus.failed.isTerminal());
}

const std = @import("std");
const runtime = @import("task_runtime.zig");

pub const InterventionAction = enum { pause, @"resume", retry, stop, skip, inspect, comment };
pub const InterventionState = enum { pending, acknowledged, rejected, unsupported, resolved };
pub const ResponseOutcome = enum { acknowledged, rejected, unsupported, completed };

pub const InterventionRequest = struct {
    event_id: []const u8,
    task_id: []const u8,
    action: InterventionAction,
    state: InterventionState,
    response_event_id: ?[]const u8 = null,
    lifecycle_event_id: ?[]const u8 = null,

    pub fn respond(self: *InterventionRequest, event_id: []const u8, outcome: ResponseOutcome) !void {
        if (self.state != .pending) return error.InterventionAlreadyResponded;
        self.response_event_id = event_id;
        self.state = switch (outcome) {
            .acknowledged => .acknowledged,
            .rejected => .rejected,
            .unsupported => .unsupported,
            .completed => .resolved,
        };
    }

    pub fn resolve(self: *InterventionRequest, event_id: []const u8) !void {
        if (self.state == .rejected or self.state == .unsupported or self.state == .resolved) return error.InvalidInterventionResolution;
        self.lifecycle_event_id = event_id;
        self.state = .resolved;
    }
};

pub fn validateCreation(
    action: InterventionAction,
    status: runtime.RuntimeStatus,
    definition_state: runtime.DefinitionState,
    existing: []const InterventionRequest,
) !void {
    if (definition_state == .missing and action != .inspect and action != .comment) return error.DefinitionMissing;
    const lifecycle_valid = switch (action) {
        .pause => status == .running,
        .@"resume" => status == .paused or status == .blocked,
        .retry => status == .failed,
        .stop => status == .running or status == .paused or status == .blocked,
        .skip => !status.isTerminal(),
        .inspect, .comment => true,
    };
    if (!lifecycle_valid) return error.InvalidIntervention;
    for (existing) |pending| {
        if (pending.state == .rejected or pending.state == .unsupported or pending.state == .resolved) continue;
        if (pending.action == action) return error.InterventionAlreadyPending;
        if (isControl(pending.action) and isControl(action)) return error.InterventionConflict;
    }
}

fn isControl(action: InterventionAction) bool {
    return action != .inspect and action != .comment;
}

fn requestForTest(action: InterventionAction) InterventionRequest {
    return .{ .event_id = "evt-request", .task_id = "T001", .action = action, .state = .pending };
}

test "intervention creation follows lifecycle rules" {
    try validateCreation(.pause, .running, .current, &.{});
    try validateCreation(.@"resume", .paused, .current, &.{});
    try validateCreation(.@"resume", .blocked, .current, &.{});
    try validateCreation(.retry, .failed, .current, &.{});
    try validateCreation(.stop, .running, .current, &.{});
    try validateCreation(.skip, .ready, .current, &.{});
    try validateCreation(.inspect, .completed, .current, &.{});
    try validateCreation(.comment, .skipped, .current, &.{});
    try std.testing.expectError(error.InvalidIntervention, validateCreation(.pause, .ready, .current, &.{}));
}

test "missing definitions remain inspectable and commentable only" {
    try validateCreation(.inspect, .failed, .missing, &.{});
    try validateCreation(.comment, .failed, .missing, &.{});
    try std.testing.expectError(error.DefinitionMissing, validateCreation(.retry, .failed, .missing, &.{}));
}

test "unresolved control requests reject duplicate and conflicting controls" {
    const pending = [_]InterventionRequest{requestForTest(.pause)};
    try std.testing.expectError(error.InterventionAlreadyPending, validateCreation(.pause, .running, .current, &pending));
    try std.testing.expectError(error.InterventionConflict, validateCreation(.stop, .running, .current, &pending));
    try validateCreation(.comment, .running, .current, &pending);
}

test "responses and lifecycle resolution retain correlation" {
    var request = requestForTest(.pause);
    try request.respond("evt-response", .acknowledged);
    try std.testing.expectEqual(InterventionState.acknowledged, request.state);
    try request.resolve("evt-paused");
    try std.testing.expectEqual(InterventionState.resolved, request.state);
    try std.testing.expectEqualStrings("evt-paused", request.lifecycle_event_id.?);
}

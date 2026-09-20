const std = @import("std");
const event = @import("../domain/event.zig");

pub const Mapping = struct { event_type: event.EventType };

pub fn map(operation: []const u8, actor: event.ActorKind) !Mapping {
    const mapped: event.EventType = if (std.mem.eql(u8, operation, "project.init")) event.EventType.project_initialized else if (std.mem.eql(u8, operation, "project.bootstrap")) .project_runtime_bootstrapped else if (std.mem.eql(u8, operation, "source.sync")) .source_synced else if (std.mem.eql(u8, operation, "task.start")) event.EventType.task_started else if (std.mem.eql(u8, operation, "task.progress")) .task_progress else if (std.mem.eql(u8, operation, "task.pause_ack")) .task_paused else if (std.mem.eql(u8, operation, "task.resume_ack")) .task_resumed else if (std.mem.eql(u8, operation, "task.block")) .task_blocked else if (std.mem.eql(u8, operation, "task.fail")) .task_failed else if (std.mem.eql(u8, operation, "task.complete")) .task_completed else if (std.mem.eql(u8, operation, "task.skip")) .task_skipped else if (std.mem.eql(u8, operation, "task.comment")) .task_comment else if (std.mem.eql(u8, operation, "human.pause_request")) .human_pause_requested else if (std.mem.eql(u8, operation, "human.resume_request")) .human_resume_requested else if (std.mem.eql(u8, operation, "human.retry_request")) .human_retry_requested else if (std.mem.eql(u8, operation, "human.stop_request")) .human_stop_requested else if (std.mem.eql(u8, operation, "human.skip_request")) .human_skip_requested else if (std.mem.eql(u8, operation, "human.inspect_request")) .human_inspect_requested else if (std.mem.eql(u8, operation, "human.comment")) .human_comment else if (std.mem.eql(u8, operation, "intervention.respond")) .intervention_responded else return error.UnknownOperation;

    const allowed = switch (mapped) {
        .project_initialized, .project_runtime_bootstrapped => actor == .human or actor == .system,
        .source_synced => true,
        .task_progress, .task_paused, .task_resumed, .task_skipped, .task_comment => actor == .agent or actor == .adapter,
        .task_started, .task_blocked, .task_failed, .task_completed => actor == .agent or actor == .adapter or actor == .human,
        .human_pause_requested, .human_resume_requested, .human_retry_requested, .human_stop_requested, .human_skip_requested, .human_inspect_requested, .human_comment => actor == .human,
        .intervention_responded => actor == .agent or actor == .adapter,
    };
    if (!allowed) return error.ActorNotAllowed;
    return .{ .event_type = mapped };
}

test "project operations map to exact system events" {
    try std.testing.expectEqual(event.EventType.project_initialized, (try map("project.init", .human)).event_type);
    try std.testing.expectEqual(event.EventType.source_synced, (try map("source.sync", .adapter)).event_type);
    try std.testing.expectError(error.ActorNotAllowed, map("project.init", .agent));
}

test "execution operations map to exactly one core-selected event" {
    const cases = [_]struct { operation: []const u8, event_type: event.EventType }{
        .{ .operation = "task.start", .event_type = .task_started },
        .{ .operation = "task.progress", .event_type = .task_progress },
        .{ .operation = "task.pause_ack", .event_type = .task_paused },
        .{ .operation = "task.resume_ack", .event_type = .task_resumed },
        .{ .operation = "task.block", .event_type = .task_blocked },
        .{ .operation = "task.fail", .event_type = .task_failed },
        .{ .operation = "task.complete", .event_type = .task_completed },
        .{ .operation = "task.skip", .event_type = .task_skipped },
        .{ .operation = "task.comment", .event_type = .task_comment },
    };
    for (cases) |case| try std.testing.expectEqual(case.event_type, (try map(case.operation, .agent)).event_type);
}

test "execution operation actor allowlist is enforced" {
    try std.testing.expectError(error.ActorNotAllowed, map("task.progress", .human));
    try std.testing.expectError(error.ActorNotAllowed, map("task.skip", .human));
    try std.testing.expectError(error.ActorNotAllowed, map("task.comment", .human));
    try std.testing.expectEqual(event.EventType.task_started, (try map("task.start", .human)).event_type);
}

test "query and arbitrary event append cannot map to an execution event" {
    try std.testing.expectError(error.UnknownOperation, map("task.list", .agent));
    try std.testing.expectError(error.UnknownOperation, map("event.append", .agent));
}

test "human operations and acknowledgement operations cannot impersonate each other" {
    try std.testing.expectEqual(event.EventType.human_pause_requested, (try map("human.pause_request", .human)).event_type);
    try std.testing.expectEqual(event.EventType.human_comment, (try map("human.comment", .human)).event_type);
    try std.testing.expectError(error.ActorNotAllowed, map("human.pause_request", .agent));
    try std.testing.expectEqual(event.EventType.intervention_responded, (try map("intervention.respond", .adapter)).event_type);
    try std.testing.expectError(error.ActorNotAllowed, map("intervention.respond", .human));
}

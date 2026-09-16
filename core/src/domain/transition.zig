const std = @import("std");
const event = @import("event.zig");
const runtime = @import("task_runtime.zig");

pub const Conditions = struct {
    has_required_reason: bool = false,
    has_retry_correlation: bool = false,
};

pub fn validate(from: runtime.RuntimeStatus, event_type: event.EventType, conditions: Conditions) !runtime.RuntimeStatus {
    if (event_type == .task_comment) return from;
    if (from.isTerminal()) return error.InvalidTransition;
    if ((event_type == .task_blocked or event_type == .task_failed) and !conditions.has_required_reason) {
        return error.ReasonRequired;
    }
    return switch (event_type) {
        .task_started => switch (from) {
            .ready => .running,
            .failed => if (conditions.has_retry_correlation) .running else error.RetryRequired,
            else => error.InvalidTransition,
        },
        .task_progress => if (from == .running) .running else error.InvalidTransition,
        .task_paused => if (from == .running) .paused else error.InvalidTransition,
        .task_resumed => if (from == .paused or from == .blocked) .running else error.InvalidTransition,
        .task_blocked => if (from == .ready or from == .running or from == .paused) .blocked else error.InvalidTransition,
        .task_failed => if (from == .running or from == .paused or from == .blocked) .failed else error.InvalidTransition,
        .task_completed => if (from == .running) .completed else error.InvalidTransition,
        .task_skipped => .skipped,
        else => error.InvalidTransition,
    };
}

test "execution transition table accepts every specified lifecycle edge" {
    const cases = [_]struct { from: runtime.RuntimeStatus, event_type: event.EventType, to: runtime.RuntimeStatus, retry: bool = false }{
        .{ .from = .ready, .event_type = .task_started, .to = .running },
        .{ .from = .failed, .event_type = .task_started, .to = .running, .retry = true },
        .{ .from = .running, .event_type = .task_progress, .to = .running },
        .{ .from = .running, .event_type = .task_paused, .to = .paused },
        .{ .from = .paused, .event_type = .task_resumed, .to = .running },
        .{ .from = .blocked, .event_type = .task_resumed, .to = .running },
        .{ .from = .ready, .event_type = .task_blocked, .to = .blocked },
        .{ .from = .running, .event_type = .task_blocked, .to = .blocked },
        .{ .from = .paused, .event_type = .task_blocked, .to = .blocked },
        .{ .from = .running, .event_type = .task_failed, .to = .failed },
        .{ .from = .paused, .event_type = .task_failed, .to = .failed },
        .{ .from = .blocked, .event_type = .task_failed, .to = .failed },
        .{ .from = .running, .event_type = .task_completed, .to = .completed },
        .{ .from = .failed, .event_type = .task_skipped, .to = .skipped },
        .{ .from = .pending, .event_type = .task_skipped, .to = .skipped },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.to, try validate(case.from, case.event_type, .{
            .has_required_reason = true,
            .has_retry_correlation = case.retry,
        }));
    }
}

test "terminal tasks accept comments only" {
    try std.testing.expectEqual(runtime.RuntimeStatus.completed, try validate(.completed, .task_comment, .{}));
    try std.testing.expectEqual(runtime.RuntimeStatus.skipped, try validate(.skipped, .task_comment, .{}));
    try std.testing.expectError(error.InvalidTransition, validate(.completed, .task_started, .{}));
    try std.testing.expectError(error.InvalidTransition, validate(.skipped, .task_progress, .{}));
}

test "failed restart requires retry correlation" {
    try std.testing.expectError(error.RetryRequired, validate(.failed, .task_started, .{}));
}

test "blocked and failed events require safe reason or error" {
    try std.testing.expectError(error.ReasonRequired, validate(.running, .task_blocked, .{}));
    try std.testing.expectError(error.ReasonRequired, validate(.running, .task_failed, .{}));
}

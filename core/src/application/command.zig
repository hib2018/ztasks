const std = @import("std");
const content_policy = @import("../domain/content_policy.zig");
const event = @import("../domain/event.zig");
const runtime = @import("../domain/task_runtime.zig");
const transition = @import("../domain/transition.zig");
const operation_map = @import("operation_map.zig");
const request_protocol = @import("../protocol/request.zig");

pub const PreparedEvent = struct {
    encoded: []u8,
    semantic_hash: [64]u8,
    status_after: runtime.RuntimeStatus,
    attempt_after: u32,

    pub fn deinit(self: PreparedEvent, allocator: std.mem.Allocator) void {
        allocator.free(self.encoded);
    }
};

pub fn prepare(
    allocator: std.mem.Allocator,
    request: request_protocol.Request,
    current_status: runtime.RuntimeStatus,
    current_attempt: u32,
    retry_correlated: bool,
    seq: u64,
    timestamp: []const u8,
) !PreparedEvent {
    const mapping = try operation_map.map(request.op, request.actor.kind);
    const raw_message = payloadMessage(request.op, request.payload.object);
    var sanitized: ?content_policy.SanitizedText = null;
    defer if (sanitized) |value| value.deinit(allocator);
    if (raw_message) |message| sanitized = try content_policy.sanitizeText(allocator, "payload.message", message);
    const safe_message: ?[]const u8 = if (sanitized) |value| value.value else null;
    const status_after = try transition.validate(current_status, mapping.event_type, .{
        .has_required_reason = safe_message != null and safe_message.?.len != 0,
        .has_retry_correlation = retry_correlated,
    });
    const attempt_after = current_attempt + @intFromBool(mapping.event_type == .task_started);
    const event_id = try std.fmt.allocPrint(allocator, "evt-{d}", .{seq});
    defer allocator.free(event_id);
    const stored = .{
        .version = @as(u8, 1),
        .event_id = event_id,
        .seq = seq,
        .request_id = request.request_id,
        .timestamp = timestamp,
        .actor = request.actor,
        .type = mapping.event_type.wireName(),
        .task_id = request.task_id,
        .session_id = payloadString(request.payload.object, "session_id"),
        .payload = .{ .message = safe_message },
        .status_after = @tagName(status_after),
        .attempt_after = attempt_after,
        .redactions = if (sanitized) |value| value.redactions else &.{},
    };
    const encoded = try std.json.Stringify.valueAlloc(allocator, stored, .{});
    if (encoded.len > content_policy.event_limit) {
        allocator.free(encoded);
        return error.EventTooLarge;
    }
    return .{
        .encoded = encoded,
        .semantic_hash = semanticHash(request),
        .status_after = status_after,
        .attempt_after = attempt_after,
    };
}

pub fn prepareIntervention(
    allocator: std.mem.Allocator,
    request: request_protocol.Request,
    current_status: runtime.RuntimeStatus,
    current_attempt: u32,
    seq: u64,
    timestamp: []const u8,
) !PreparedEvent {
    const mapping = try operation_map.map(request.op, request.actor.kind);
    const raw_message = payloadString(request.payload.object, "message") orelse payloadString(request.payload.object, "focus");
    var sanitized: ?content_policy.SanitizedText = null;
    defer if (sanitized) |value| value.deinit(allocator);
    if (raw_message) |message| sanitized = try content_policy.sanitizeText(allocator, "payload.message", message);
    const event_id = try std.fmt.allocPrint(allocator, "evt-{d}", .{seq});
    defer allocator.free(event_id);
    const stored = .{
        .version = @as(u8, 1),
        .event_id = event_id,
        .seq = seq,
        .request_id = request.request_id,
        .timestamp = timestamp,
        .actor = request.actor,
        .type = mapping.event_type.wireName(),
        .task_id = request.task_id,
        .session_id = @as(?[]const u8, null),
        .payload = .{
            .action = interventionAction(mapping.event_type),
            .request_event_id = payloadString(request.payload.object, "request_event_id"),
            .outcome = payloadString(request.payload.object, "outcome"),
            .message = if (sanitized) |value| value.value else null,
        },
        .status_after = @tagName(current_status),
        .attempt_after = current_attempt,
        .redactions = if (sanitized) |value| value.redactions else &.{},
    };
    const encoded = try std.json.Stringify.valueAlloc(allocator, stored, .{});
    if (encoded.len > content_policy.event_limit) {
        allocator.free(encoded);
        return error.EventTooLarge;
    }
    return .{
        .encoded = encoded,
        .semantic_hash = semanticHash(request),
        .status_after = current_status,
        .attempt_after = current_attempt,
    };
}

fn interventionAction(event_type: event.EventType) ?[]const u8 {
    return switch (event_type) {
        .human_pause_requested => "pause",
        .human_resume_requested => "resume",
        .human_retry_requested => "retry",
        .human_stop_requested => "stop",
        .human_skip_requested => "skip",
        .human_inspect_requested => "inspect",
        .human_comment => "comment",
        else => null,
    };
}

pub fn semanticHash(request: request_protocol.Request) [64]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(request.op);
    hash.update(&.{0});
    hash.update(request.request_id);
    hash.update(&.{0});
    if (request.task_id) |task_id| hash.update(task_id);
    const payload = request.payload.object;
    var iterator = payload.iterator();
    while (iterator.next()) |entry| {
        hash.update(entry.key_ptr.*);
        hash.update(&.{0});
        if (entry.value_ptr.* == .string) hash.update(entry.value_ptr.string);
        hash.update(&.{0});
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

fn payloadMessage(operation: []const u8, payload: std.json.ObjectMap) ?[]const u8 {
    const field = if (std.mem.eql(u8, operation, "task.progress")) "current_action" else if (std.mem.eql(u8, operation, "task.block")) "reason" else if (std.mem.eql(u8, operation, "task.complete")) "result" else "message";
    return payloadString(payload, field);
}

fn payloadString(payload: std.json.ObjectMap, field: []const u8) ?[]const u8 {
    const value = payload.get(field) orelse return null;
    return if (value == .string) value.string else null;
}

test "prepare maps sanitizes transitions and sizes one event" {
    const line = "{\"version\":1,\"request_id\":\"req-1\",\"op\":\"task.progress\",\"actor\":{\"kind\":\"agent\",\"id\":\"pi\"},\"task_id\":\"T001\",\"payload\":{\"current_action\":\"token=secret-value\"}}";
    var request = try request_protocol.decode(std.testing.allocator, line);
    defer request.deinit();
    const prepared = try prepare(std.testing.allocator, request.value, .running, 1, false, 2, "2026-09-16T00:00:00Z");
    defer prepared.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, prepared.encoded, "secret-value") == null);
    try std.testing.expect(std.mem.indexOf(u8, prepared.encoded, "[REDACTED:token]") != null);
    try std.testing.expectEqual(runtime.RuntimeStatus.running, prepared.status_after);
}

const std = @import("std");
const content_policy = @import("../domain/content_policy.zig");
const event = @import("../domain/event.zig");
const task_definition = @import("../domain/task_definition.zig");

pub const max_line_size = 1_048_576;

pub const Request = struct {
    version: u8,
    request_id: []const u8,
    op: []const u8,
    actor: event.Actor,
    task_id: ?[]const u8 = null,
    payload: std.json.Value,
};

pub fn decode(allocator: std.mem.Allocator, line: []const u8) !std.json.Parsed(Request) {
    if (line.len > max_line_size) return error.LineTooLarge;
    var parsed = std.json.parseFromSlice(Request, allocator, line, .{
        .ignore_unknown_fields = false,
        .allocate = .alloc_always,
    }) catch return error.InvalidRequest;
    errdefer parsed.deinit();

    if (parsed.value.version != 1) return error.UnsupportedVersion;
    content_policy.validateIdentifier(parsed.value.request_id) catch return error.InvalidRequest;
    content_policy.validateIdentifier(parsed.value.op) catch return error.InvalidRequest;
    parsed.value.actor.validate() catch return error.InvalidRequest;
    if (parsed.value.task_id) |task_id| if (!task_definition.isTaskId(task_id)) return error.InvalidRequest;
    if (parsed.value.payload != .object) return error.InvalidRequest;
    try validatePayload(parsed.value.op, parsed.value.payload.object);
    return parsed;
}

fn validatePayload(op: []const u8, object: std.json.ObjectMap) !void {
    const allowed = allowedPayloadFields(op) orelse return error.UnknownOperation;
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        const field = entry.key_ptr.*;
        if (content_policy.isProhibitedField(field)) return error.ProhibitedField;
        var found = false;
        for (allowed) |candidate| {
            if (std.mem.eql(u8, field, candidate)) {
                found = true;
                break;
            }
        }
        if (!found) return error.InvalidRequest;
    }
}

fn allowedPayloadFields(op: []const u8) ?[]const []const u8 {
    const none = &[_][]const u8{};
    const message = &[_][]const u8{"message"};
    const focus = &[_][]const u8{"focus"};
    if (std.mem.eql(u8, op, "version.get") or
        std.mem.eql(u8, op, "project.inspect") or
        std.mem.eql(u8, op, "health.check") or
        std.mem.eql(u8, op, "task.pause_ack") or
        std.mem.eql(u8, op, "task.resume_ack") or
        std.mem.eql(u8, op, "task.skip") or
        std.mem.eql(u8, op, "human.pause_request") or
        std.mem.eql(u8, op, "human.resume_request") or
        std.mem.eql(u8, op, "human.retry_request") or
        std.mem.eql(u8, op, "human.stop_request") or
        std.mem.eql(u8, op, "human.skip_request")) return none;
    if (std.mem.eql(u8, op, "task.start")) return &.{"session_id"};
    if (std.mem.eql(u8, op, "human.comment") or std.mem.eql(u8, op, "task.comment")) return message;
    if (std.mem.eql(u8, op, "human.inspect_request")) return focus;
    if (std.mem.eql(u8, op, "task.progress")) return &.{"current_action"};
    if (std.mem.eql(u8, op, "task.block")) return &.{"reason"};
    if (std.mem.eql(u8, op, "task.fail")) return &.{ "code", "message" };
    if (std.mem.eql(u8, op, "task.complete")) return &.{"result"};
    if (std.mem.eql(u8, op, "intervention.respond")) return &.{ "request_event_id", "outcome", "message" };
    if (std.mem.eql(u8, op, "task.list")) return &.{ "status", "phase", "agent" };
    if (std.mem.eql(u8, op, "task.show") or std.mem.eql(u8, op, "event.list")) return &.{ "limit", "after_seq" };
    if (std.mem.eql(u8, op, "source.validate") or std.mem.eql(u8, op, "project.init") or std.mem.eql(u8, op, "source.sync")) return &.{"locator"};
    return null;
}

test "strict request envelope accepts required fields and rejects unknown fields" {
    const valid = "{\"version\":1,\"request_id\":\"req-1\",\"op\":\"version.get\",\"actor\":{\"kind\":\"human\",\"id\":\"operator\"},\"payload\":{}}";
    var request = try decode(std.testing.allocator, valid);
    defer request.deinit();
    try std.testing.expectEqualStrings("req-1", request.value.request_id);

    const unknown = "{\"version\":1,\"request_id\":\"req-1\",\"op\":\"version.get\",\"actor\":{\"kind\":\"human\"},\"payload\":{},\"extra\":true}";
    try std.testing.expectError(error.InvalidRequest, decode(std.testing.allocator, unknown));
}

test "request transport line is limited to one MiB" {
    const oversized = try std.testing.allocator.alloc(u8, 1_048_577);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'x');
    try std.testing.expectError(error.LineTooLarge, decode(std.testing.allocator, oversized));
}

test "version and request identity are validated" {
    const unsupported = "{\"version\":2,\"request_id\":\"req-1\",\"op\":\"version.get\",\"actor\":{\"kind\":\"human\"},\"payload\":{}}";
    try std.testing.expectError(error.UnsupportedVersion, decode(std.testing.allocator, unsupported));
    const empty_identity = "{\"version\":1,\"request_id\":\"\",\"op\":\"version.get\",\"actor\":{\"kind\":\"human\"},\"payload\":{}}";
    try std.testing.expectError(error.InvalidRequest, decode(std.testing.allocator, empty_identity));
}

test "prohibited payload field is classified without echoing its value" {
    const prohibited = "{\"version\":1,\"request_id\":\"req-1\",\"op\":\"human.comment\",\"actor\":{\"kind\":\"human\"},\"task_id\":\"T001\",\"payload\":{\"private_reasoning\":\"must-not-echo\"}}";
    try std.testing.expectError(error.ProhibitedField, decode(std.testing.allocator, prohibited));
}

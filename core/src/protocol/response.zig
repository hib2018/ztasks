const std = @import("std");

pub const ErrorCode = enum {
    invalid_request,
    line_too_large,
    unsupported_version,
    unknown_operation,
    field_too_large,
    prohibited_field,
    invalid_text,
    event_too_large,
    task_not_found,
    definition_missing,
    invalid_transition,
    dependency_unsatisfied,
    invalid_event,
    intervention_already_pending,
    intervention_conflict,
    source_not_found,
    source_ambiguous,
    source_invalid,
    source_changed,
    idempotency_conflict,
    store_locked,
    store_corrupt,
    io_error,
};

pub const ProtocolError = struct {
    code: ErrorCode,
    message: []const u8,
    details: std.json.Value,
};

pub const Response = struct {
    version: u8,
    request_id: []const u8,
    ok: bool,
    result: ?std.json.Value = null,
    warnings: ?[]const std.json.Value = null,
    @"error": ?ProtocolError = null,
};

pub fn decode(allocator: std.mem.Allocator, line: []const u8) !std.json.Parsed(Response) {
    if (line.len > 1_048_576) return error.LineTooLarge;
    var parsed = std.json.parseFromSlice(Response, allocator, line, .{
        .ignore_unknown_fields = false,
        .allocate = .alloc_always,
    }) catch return error.InvalidResponse;
    errdefer parsed.deinit();
    if (parsed.value.version != 1) return error.UnsupportedVersion;
    if (parsed.value.request_id.len == 0) return error.InvalidResponse;
    if (parsed.value.ok and (parsed.value.result == null or parsed.value.@"error" != null)) return error.InvalidResponse;
    if (!parsed.value.ok and (parsed.value.@"error" == null or parsed.value.result != null)) return error.InvalidResponse;
    return parsed;
}

pub fn encodeError(
    allocator: std.mem.Allocator,
    request_id: []const u8,
    code: ErrorCode,
    details: anytype,
) ![]u8 {
    const response = .{
        .version = @as(u8, 1),
        .request_id = request_id,
        .ok = false,
        .@"error" = .{
            .code = code,
            .message = errorMessage(code),
            .details = details,
        },
    };
    return std.json.Stringify.valueAlloc(allocator, response, .{});
}

fn errorMessage(code: ErrorCode) []const u8 {
    return switch (code) {
        .invalid_request => "request does not match the protocol contract",
        .line_too_large => "request line exceeds the transport limit",
        .unsupported_version => "unsupported protocol version",
        .unknown_operation => "unknown protocol operation",
        .field_too_large => "field exceeds its size limit",
        .prohibited_field => "field is prohibited by content policy",
        .invalid_text => "field contains invalid text",
        .event_too_large => "canonical event exceeds its size limit",
        .task_not_found => "task was not found",
        .definition_missing => "task definition is not current",
        .invalid_transition => "runtime transition is invalid",
        .dependency_unsatisfied => "task dependencies are not satisfied",
        .invalid_event => "event is invalid",
        .intervention_already_pending => "intervention is already pending",
        .intervention_conflict => "intervention conflicts with a pending request",
        .source_not_found => "task source was not found",
        .source_ambiguous => "task source selection is ambiguous",
        .source_invalid => "task source is invalid",
        .source_changed => "task source digest has changed",
        .idempotency_conflict => "request identity was reused with different semantics",
        .store_locked => "runtime store is locked",
        .store_corrupt => "runtime store is corrupt",
        .io_error => "runtime storage operation failed",
    };
}

test "error response preserves request identity and stable code" {
    const encoded = try encodeError(std.testing.allocator, "req-1", .unsupported_version, .{ .supported_version = 1 });
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"version\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"request_id\":\"req-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\"code\":\"unsupported_version\"") != null);
}

test "content policy errors expose metadata but never rejected values" {
    const encoded = try encodeError(std.testing.allocator, "req-2", .field_too_large, .{
        .field = "payload.message",
        .limit = 4096,
    });
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "payload.message") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "must-not-echo") == null);
}

test "strict response decoder rejects unknown fields and invalid success shape" {
    const valid = "{\"version\":1,\"request_id\":\"req-1\",\"ok\":true,\"result\":{},\"warnings\":[]}";
    var parsed = try decode(std.testing.allocator, valid);
    defer parsed.deinit();
    const unknown = "{\"version\":1,\"request_id\":\"req-1\",\"ok\":true,\"result\":{},\"extra\":true}";
    try std.testing.expectError(error.InvalidResponse, decode(std.testing.allocator, unknown));
}

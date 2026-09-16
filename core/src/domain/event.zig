const std = @import("std");
const content_policy = @import("content_policy.zig");
const task_definition = @import("task_definition.zig");

pub const ActorKind = enum { human, agent, adapter, system };

pub const Actor = struct {
    kind: ActorKind,
    id: ?[]const u8 = null,

    pub fn validate(self: Actor) !void {
        if (self.id) |id| try content_policy.validateIdentifier(id);
    }
};

pub const EventType = enum {
    project_initialized,
    source_synced,
    task_started,
    task_progress,
    task_paused,
    task_resumed,
    task_blocked,
    task_failed,
    task_completed,
    task_skipped,
    task_comment,
    human_pause_requested,
    human_resume_requested,
    human_retry_requested,
    human_stop_requested,
    human_skip_requested,
    human_inspect_requested,
    human_comment,
    intervention_responded,

    pub fn wireName(self: EventType) []const u8 {
        return switch (self) {
            .project_initialized => "project.initialized",
            .source_synced => "source.synced",
            .task_started => "task.started",
            .task_progress => "task.progress",
            .task_paused => "task.paused",
            .task_resumed => "task.resumed",
            .task_blocked => "task.blocked",
            .task_failed => "task.failed",
            .task_completed => "task.completed",
            .task_skipped => "task.skipped",
            .task_comment => "task.comment",
            .human_pause_requested => "human.pause_requested",
            .human_resume_requested => "human.resume_requested",
            .human_retry_requested => "human.retry_requested",
            .human_stop_requested => "human.stop_requested",
            .human_skip_requested => "human.skip_requested",
            .human_inspect_requested => "human.inspect_requested",
            .human_comment => "human.comment",
            .intervention_responded => "intervention.responded",
        };
    }
};

pub const InterventionOutcome = enum { acknowledged, rejected, unsupported, completed };

pub const EventPayload = union(enum) {
    project_initialized: struct { source_digest: []const u8, definition_ref: []const u8, dependency_digest: []const u8 },
    source_synced: struct {
        previous_digest: []const u8,
        source_digest: []const u8,
        definition_ref: []const u8,
        dependency_digest: []const u8,
        added: []const []const u8 = &.{},
        changed: []const []const u8 = &.{},
        missing: []const []const u8 = &.{},
        reappeared: []const []const u8 = &.{},
    },
    started: struct {},
    progress: struct { current_action: []const u8 },
    paused: struct {},
    resumed: struct {},
    blocked: struct { reason: []const u8 },
    failed: struct { code: []const u8, message: []const u8 },
    completed: struct { result: ?[]const u8 = null },
    skipped: struct {},
    comment: struct { message: []const u8 },
    human_request: struct { focus: ?[]const u8 = null },
    intervention_response: struct { outcome: InterventionOutcome, message: ?[]const u8 = null },
};

pub const Event = struct {
    version: u8,
    event_id: []const u8,
    seq: u64,
    request_id: []const u8,
    timestamp: []const u8,
    actor: Actor,
    event_type: EventType,
    task_id: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    correlation_id: ?[]const u8 = null,
    payload: EventPayload,
    redactions: []const content_policy.Redaction = &.{},

    pub fn validate(self: Event, allocator: std.mem.Allocator) !void {
        if (self.version != 1 or self.seq == 0) return error.InvalidEvent;
        try content_policy.validateIdentifier(self.event_id);
        try content_policy.validateIdentifier(self.request_id);
        try content_policy.validateIdentifier(self.timestamp);
        try self.actor.validate();
        if (self.task_id) |task_id| if (!task_definition.isTaskId(task_id)) return error.InvalidTaskId;
        if (self.session_id) |session_id| try content_policy.validateIdentifier(session_id);
        if (self.correlation_id) |correlation_id| try content_policy.validateIdentifier(correlation_id);
        try validatePayload(self.event_type, self.payload, allocator);
        for (self.redactions) |redaction| {
            try content_policy.validateIdentifier(redaction.field);
            try content_policy.validateIdentifier(redaction.class);
        }

        const canonical = try std.json.Stringify.valueAlloc(allocator, self, .{});
        defer allocator.free(canonical);
        try validateCanonicalSize(canonical.len);
    }

    pub fn startedForTest() Event {
        return .{
            .version = 1,
            .event_id = "evt-1",
            .seq = 1,
            .request_id = "req-1",
            .timestamp = "2026-09-15T00:00:00Z",
            .actor = .{ .kind = .agent, .id = "pi" },
            .event_type = .task_started,
            .task_id = "T001",
            .payload = .{ .started = .{} },
        };
    }
};

pub fn validateCanonicalSize(size: usize) !void {
    if (size > content_policy.event_limit) return error.EventTooLarge;
}

fn validatePayload(event_type: EventType, payload: EventPayload, allocator: std.mem.Allocator) !void {
    const valid_pair = switch (event_type) {
        .project_initialized => payload == .project_initialized,
        .source_synced => payload == .source_synced,
        .task_started => payload == .started,
        .task_progress => payload == .progress,
        .task_paused => payload == .paused,
        .task_resumed => payload == .resumed,
        .task_blocked => payload == .blocked,
        .task_failed => payload == .failed,
        .task_completed => payload == .completed,
        .task_skipped => payload == .skipped,
        .task_comment, .human_comment => payload == .comment,
        .human_pause_requested, .human_resume_requested, .human_retry_requested, .human_stop_requested, .human_skip_requested, .human_inspect_requested => payload == .human_request,
        .intervention_responded => payload == .intervention_response,
    };
    if (!valid_pair) return error.InvalidEvent;

    switch (payload) {
        .project_initialized => |value| {
            try content_policy.validateIdentifier(value.source_digest);
            try content_policy.validateSourceLocator(value.definition_ref);
            try content_policy.validateIdentifier(value.dependency_digest);
        },
        .source_synced => |value| {
            try content_policy.validateIdentifier(value.previous_digest);
            try content_policy.validateIdentifier(value.source_digest);
            try content_policy.validateSourceLocator(value.definition_ref);
            try content_policy.validateIdentifier(value.dependency_digest);
            for (value.added) |id| if (!task_definition.isTaskId(id)) return error.InvalidTaskId;
            for (value.changed) |id| if (!task_definition.isTaskId(id)) return error.InvalidTaskId;
            for (value.missing) |id| if (!task_definition.isTaskId(id)) return error.InvalidTaskId;
            for (value.reappeared) |id| if (!task_definition.isTaskId(id)) return error.InvalidTaskId;
        },
        .progress => |value| try ensureSanitized(allocator, "payload.current_action", value.current_action),
        .blocked => |value| try ensureSanitized(allocator, "payload.reason", value.reason),
        .failed => |value| {
            try content_policy.validateIdentifier(value.code);
            try ensureSanitized(allocator, "payload.message", value.message);
        },
        .completed => |value| if (value.result) |result| try ensureSanitized(allocator, "payload.result", result),
        .comment => |value| try ensureSanitized(allocator, "payload.message", value.message),
        .human_request => |value| if (value.focus) |focus| try ensureSanitized(allocator, "payload.focus", focus),
        .intervention_response => |value| if (value.message) |message| try ensureSanitized(allocator, "payload.message", message),
        .started, .paused, .resumed, .skipped => {},
    }
}

fn ensureSanitized(allocator: std.mem.Allocator, field: []const u8, value: []const u8) !void {
    const sanitized = try content_policy.sanitizeText(allocator, field, value);
    defer sanitized.deinit(allocator);
    if (!std.mem.eql(u8, sanitized.value, value)) return error.UnsanitizedCredential;
}

test "actor kinds and bounded identifiers are validated" {
    try (Actor{ .kind = .agent, .id = "pi" }).validate();
    try std.testing.expectError(error.FieldTooLarge, (Actor{ .kind = .human, .id = "x" ** 129 }).validate());
}

test "event identity and sequence are required" {
    const event = Event.startedForTest();
    try event.validate(std.testing.allocator);
    var invalid = event;
    invalid.seq = 0;
    try std.testing.expectError(error.InvalidEvent, invalid.validate(std.testing.allocator));
}

test "event payload is closed and typed by event kind" {
    const event = Event{
        .version = 1,
        .event_id = "evt-1",
        .seq = 1,
        .request_id = "req-1",
        .timestamp = "2026-09-15T00:00:00Z",
        .actor = .{ .kind = .agent, .id = "pi" },
        .event_type = .task_progress,
        .task_id = "T001",
        .payload = .{ .progress = .{ .current_action = "editing parser" } },
    };
    try event.validate(std.testing.allocator);
}

test "canonical event size is limited to 65536 UTF-8 bytes" {
    try validateCanonicalSize(65_536);
    try std.testing.expectError(error.EventTooLarge, validateCanonicalSize(65_537));
}

test "event kind and payload variant must match" {
    var event = Event.startedForTest();
    event.payload = .{ .progress = .{ .current_action = "editing parser" } };
    try std.testing.expectError(error.InvalidEvent, event.validate(std.testing.allocator));
}

test "source sync payload carries artifact identities and exact change sets" {
    const value = Event{
        .version = 1,
        .event_id = "evt-sync",
        .seq = 1,
        .request_id = "req-sync",
        .timestamp = "2026-09-16T00:00:00Z",
        .actor = .{ .kind = .human },
        .event_type = .source_synced,
        .payload = .{ .source_synced = .{
            .previous_digest = "sha256:old",
            .source_digest = "sha256:new",
            .definition_ref = ".ztasks/sources/new/definition.json",
            .dependency_digest = "sha256:deps",
            .added = &.{"T002"},
            .missing = &.{"T001"},
        } },
    };
    try value.validate(std.testing.allocator);
}

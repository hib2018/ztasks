const std = @import("std");
const query = @import("../application/query.zig");
const request_protocol = @import("request.zig");
const response_protocol = @import("response.zig");
const command = @import("../application/command.zig");
const content_policy = @import("../domain/content_policy.zig");
const event_domain = @import("../domain/event.zig");
const runtime_domain = @import("../domain/task_runtime.zig");
const intervention_domain = @import("../domain/intervention.zig");
const operation_map = @import("../application/operation_map.zig");
const event_log = @import("../storage/event_log.zig");
const project_lock = @import("../storage/lock.zig");
const snapshot_store = @import("../storage/snapshot.zig");
const project_init = @import("../application/project_init.zig");
const sync_application = @import("../application/sync.zig");
const doctor_application = @import("../application/doctor.zig");
const compatibility = @import("compatibility.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    source_locator: ?[]const u8 = null,
};

pub fn handleLine(context: Context, line: []const u8) ![]u8 {
    var request = request_protocol.decode(context.allocator, line) catch |err| {
        const code: response_protocol.ErrorCode = switch (err) {
            error.LineTooLarge => .line_too_large,
            error.UnsupportedVersion => .unsupported_version,
            error.UnknownOperation => .unknown_operation,
            error.ProhibitedField => .prohibited_field,
            else => .invalid_request,
        };
        return response_protocol.encodeError(context.allocator, "", code, .{});
    };
    defer request.deinit();

    if (std.mem.eql(u8, request.value.op, "version.get")) {
        return encodeSuccess(context.allocator, request.value.request_id, .{
            .product_version = compatibility.product_version,
            .protocol_version = compatibility.protocol_version,
            .data_version = compatibility.data_version,
            .capabilities = [_][]const u8{ "project.init", "source.sync", "project.inspect", "health.check", "source.validate", "task.list", "task.show" },
        });
    }
    if (std.mem.eql(u8, request.value.op, "source.validate") or
        std.mem.eql(u8, request.value.op, "task.list") or
        std.mem.eql(u8, request.value.op, "task.show"))
    {
        return handleTaskQuery(context, request.value) catch |err| {
            const code: response_protocol.ErrorCode = switch (err) {
                error.SourceNotFound => .source_not_found,
                error.SourceAmbiguous => .source_ambiguous,
                error.TaskNotFound => .task_not_found,
                error.PathEscapesProject => .source_invalid,
                else => .source_invalid,
            };
            return response_protocol.encodeError(context.allocator, request.value.request_id, code, .{});
        };
    }
    if (std.mem.eql(u8, request.value.op, "event.list")) {
        return handleEventList(context, request.value) catch
            return response_protocol.encodeError(context.allocator, request.value.request_id, .store_corrupt, .{});
    }
    if (std.mem.eql(u8, request.value.op, "project.inspect") or std.mem.eql(u8, request.value.op, "health.check")) {
        return handleProjectQuery(context, request.value) catch
            return response_protocol.encodeError(context.allocator, request.value.request_id, .store_corrupt, .{});
    }
    if (std.mem.eql(u8, request.value.op, "project.init") or std.mem.eql(u8, request.value.op, "source.sync")) {
        return handleProjectMutation(context, request.value) catch |err| {
            const code: response_protocol.ErrorCode = switch (err) {
                error.SourceNotFound => .source_not_found,
                error.SourceAmbiguous => .source_ambiguous,
                error.IdempotencyConflict => .idempotency_conflict,
                error.StoreLocked => .store_locked,
                error.AlreadyInitialized, error.NotInitialized => .invalid_transition,
                else => .io_error,
            };
            return response_protocol.encodeError(context.allocator, request.value.request_id, code, .{});
        };
    }
    const mapping = query.classify(request.value.op) catch
        return response_protocol.encodeError(context.allocator, request.value.request_id, .unknown_operation, .{});
    if (mapping.class == .mutation) {
        return handleMutation(context, request.value) catch |err| {
            const code: response_protocol.ErrorCode = switch (err) {
                error.TaskNotFound => .task_not_found,
                error.DependencyUnsatisfied => .dependency_unsatisfied,
                error.IdempotencyConflict => .idempotency_conflict,
                error.StoreLocked => .store_locked,
                error.InterventionAlreadyPending => .intervention_already_pending,
                error.InterventionConflict => .intervention_conflict,
                error.InvalidIntervention => .invalid_event,
                error.InvalidTransition, error.RetryRequired, error.ReasonRequired => .invalid_transition,
                error.EventTooLarge => .event_too_large,
                else => .io_error,
            };
            return response_protocol.encodeError(context.allocator, request.value.request_id, code, .{});
        };
    }
    return response_protocol.encodeError(context.allocator, request.value.request_id, .unknown_operation, .{});
}

fn handleTaskQuery(context: Context, request: request_protocol.Request) ![]u8 {
    const locator = try resolveLocator(context);
    defer context.allocator.free(locator);
    const project = try std.Io.Dir.openDirAbsolute(context.io, context.project_root, .{});
    defer project.close(context.io);
    const markdown = project.readFileAlloc(context.io, locator, context.allocator, .limited(4 * 1024 * 1024)) catch return error.SourceNotFound;
    defer context.allocator.free(markdown);
    var batch = try query.validateSource(context.allocator, locator, markdown);
    defer batch.deinit(context.allocator);
    try persistDependencyArtifact(context, project, &batch);

    if (std.mem.eql(u8, request.op, "source.validate")) {
        var digest_buffer: [71]u8 = undefined;
        @memcpy(digest_buffer[0..7], "sha256:");
        @memcpy(digest_buffer[7..], &batch.dependency_artifact.source_digest);
        return encodeSuccess(context.allocator, request.request_id, .{
            .locator = locator,
            .source_digest = digest_buffer[0..],
            .phase_count = batch.phases.len,
            .task_count = batch.tasks.len,
            .diagnostics = batch.dependency_artifact.diagnostics,
        });
    }

    var history = try loadHistory(context, project);
    defer history.deinit(context.allocator);
    const task_results = try context.allocator.alloc(TaskResult, batch.tasks.len);
    defer context.allocator.free(task_results);
    var built_results: usize = 0;
    defer for (task_results[0..built_results]) |task| context.allocator.free(task.unsatisfied_dependencies);
    for (batch.tasks, 0..) |task, index| {
        const runtime = runtimeFor(context.allocator, &batch, &history, task.id) catch return error.SourceInvalid;
        task_results[index] = .{
            .id = task.id,
            .phase = phaseTitle(&batch, task.phase_id),
            .title = task.title,
            .status = @tagName(runtime.status),
            .agent = runtime.agent,
            .session_id = runtime.session_id,
            .current_action = runtime.current_action,
            .unsatisfied_dependencies = runtime.unsatisfied,
        };
        built_results += 1;
    }
    if (std.mem.eql(u8, request.op, "task.list")) {
        return encodeSuccess(context.allocator, request.request_id, .{ .tasks = task_results });
    }
    const task_id = request.task_id orelse return error.TaskNotFound;
    const index = try query.showIndex(&batch, task_id);
    return encodeSuccess(context.allocator, request.request_id, .{ .task = task_results[index] });
}

fn persistDependencyArtifact(context: Context, project: std.Io.Dir, batch: anytype) !void {
    const canonical = try batch.dependency_artifact.canonicalJson(context.allocator);
    defer context.allocator.free(canonical);
    const path = try std.fmt.allocPrint(
        context.allocator,
        ".ztasks/sources/{s}/dependencies.json",
        .{batch.dependency_artifact.source_digest},
    );
    defer context.allocator.free(path);
    var atomic = try project.createFileAtomic(context.io, path, .{ .make_path = true, .replace = true });
    defer atomic.deinit(context.io);
    try atomic.file.writeStreamingAll(context.io, canonical);
    try atomic.file.sync(context.io);
    try atomic.replace(context.io);
}

const TaskResult = struct {
    id: []const u8,
    phase: []const u8,
    title: []const u8,
    status: []const u8,
    agent: ?[]const u8,
    session_id: ?[]const u8,
    current_action: ?[]const u8,
    unsatisfied_dependencies: []const []const u8,
};

const StoredEvent = struct {
    version: u8,
    event_id: []const u8,
    seq: u64,
    request_id: []const u8,
    timestamp: []const u8,
    actor: event_domain.Actor,
    type: []const u8,
    task_id: ?[]const u8,
    session_id: ?[]const u8,
    payload: std.json.Value,
    status_after: ?[]const u8 = null,
    attempt_after: u32 = 0,
    redactions: []const content_policy.Redaction,
};

const HistoryItem = struct {
    record: std.json.Parsed(event_log.PersistentRecord),
    event: std.json.Parsed(StoredEvent),
};

const History = struct {
    items: []HistoryItem,

    fn deinit(self: *History, allocator: std.mem.Allocator) void {
        for (self.items) |*item| {
            item.event.deinit();
            item.record.deinit();
        }
        allocator.free(self.items);
    }
};

const RuntimeView = struct {
    status: runtime_domain.RuntimeStatus,
    attempt: u32,
    agent: ?[]const u8,
    session_id: ?[]const u8,
    current_action: ?[]const u8,
    unsatisfied: []const []const u8,
};

fn loadHistory(context: Context, project: std.Io.Dir) !History {
    const bytes = project.readFileAlloc(context.io, ".ztasks/events.jsonl", context.allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{ .items = try context.allocator.alloc(HistoryItem, 0) },
        else => return err,
    };
    defer context.allocator.free(bytes);
    var items: std.ArrayList(HistoryItem) = .empty;
    errdefer {
        for (items.items) |*item| {
            item.event.deinit();
            item.record.deinit();
        }
        items.deinit(context.allocator);
    }
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var expected_seq: u64 = 1;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var record = std.json.parseFromSlice(event_log.PersistentRecord, context.allocator, line, .{ .ignore_unknown_fields = false, .allocate = .alloc_always }) catch return error.StoreCorrupt;
        errdefer record.deinit();
        if (record.value.seq != expected_seq) return error.StoreCorrupt;
        var stored_event = std.json.parseFromSlice(StoredEvent, context.allocator, record.value.event_json, .{ .ignore_unknown_fields = false, .allocate = .alloc_always }) catch return error.StoreCorrupt;
        errdefer stored_event.deinit();
        if (stored_event.value.seq != record.value.seq or !std.mem.eql(u8, stored_event.value.request_id, record.value.request_id)) return error.StoreCorrupt;
        try items.append(context.allocator, .{ .record = record, .event = stored_event });
        expected_seq += 1;
    }
    return .{ .items = try items.toOwnedSlice(context.allocator) };
}

fn runtimeFor(allocator: std.mem.Allocator, batch: anytype, history: *const History, task_id: []const u8) !RuntimeView {
    const definition = batch.tasks[try query.showIndex(batch, task_id)];
    var status: ?runtime_domain.RuntimeStatus = null;
    var attempt: u32 = 0;
    var agent: ?[]const u8 = null;
    var session_id: ?[]const u8 = null;
    var current_action: ?[]const u8 = null;
    for (history.items) |item| {
        if (item.event.value.task_id) |event_task_id| {
            if (std.mem.eql(u8, event_task_id, task_id)) {
                status = runtime_domain.RuntimeStatus.parse(item.event.value.status_after orelse return error.StoreCorrupt) orelse return error.StoreCorrupt;
                attempt = item.event.value.attempt_after;
                if (std.mem.eql(u8, item.event.value.type, "task.started")) {
                    agent = item.event.value.actor.id;
                    session_id = item.event.value.session_id;
                }
                if (std.mem.eql(u8, item.event.value.type, "task.progress")) current_action = eventMessage(item.event.value);
                if (status.?.isTerminal()) current_action = null;
            }
        }
    }
    if (status) |current| return .{ .status = current, .attempt = attempt, .agent = agent, .session_id = session_id, .current_action = current_action, .unsatisfied = try allocator.alloc([]const u8, 0) };

    var unsatisfied: std.ArrayList([]const u8) = .empty;
    defer unsatisfied.deinit(allocator);
    for (definition.dependencies) |dependency| {
        const dependency_status = latestStatus(history, dependency);
        if (dependency_status == null or !dependency_status.?.isTerminal()) try unsatisfied.append(allocator, dependency);
    }
    const owned = try unsatisfied.toOwnedSlice(allocator);
    return .{ .status = if (owned.len == 0) .ready else .pending, .attempt = 0, .agent = null, .session_id = null, .current_action = null, .unsatisfied = owned };
}

fn latestStatus(history: *const History, task_id: []const u8) ?runtime_domain.RuntimeStatus {
    var result: ?runtime_domain.RuntimeStatus = null;
    for (history.items) |item| {
        if (item.event.value.task_id) |event_task_id| {
            if (std.mem.eql(u8, event_task_id, task_id)) result = runtime_domain.RuntimeStatus.parse(item.event.value.status_after orelse continue);
        }
    }
    return result;
}

fn eventMessage(stored_event: StoredEvent) ?[]const u8 {
    if (stored_event.payload != .object) return null;
    const value = stored_event.payload.object.get("message") orelse return null;
    return if (value == .string) value.string else null;
}

fn handleMutation(context: Context, request: request_protocol.Request) ![]u8 {
    const task_id = request.task_id orelse return error.TaskNotFound;
    const locator = try resolveLocator(context);
    defer context.allocator.free(locator);
    const project = try std.Io.Dir.openDirAbsolute(context.io, context.project_root, .{});
    defer project.close(context.io);
    const markdown = project.readFileAlloc(context.io, locator, context.allocator, .limited(4 * 1024 * 1024)) catch return error.SourceNotFound;
    defer context.allocator.free(markdown);
    var batch = try query.validateSource(context.allocator, locator, markdown);
    defer batch.deinit(context.allocator);
    try persistDependencyArtifact(context, project, &batch);
    _ = query.showIndex(&batch, task_id) catch return error.TaskNotFound;

    var lock = try project_lock.ProjectLock.acquire(project, context.io);
    defer lock.release();
    var history = try loadHistory(context, project);
    defer history.deinit(context.allocator);
    const semantic_hash = command.semanticHash(request);
    for (history.items) |item| {
        if (!std.mem.eql(u8, item.record.value.request_id, request.request_id)) continue;
        if (!std.mem.eql(u8, item.record.value.semantic_hash, &semantic_hash)) return error.IdempotencyConflict;
        const runtime = try runtimeFor(context.allocator, &batch, &history, task_id);
        defer context.allocator.free(runtime.unsatisfied);
        return encodeSuccess(context.allocator, request.request_id, .{
            .event = item.event.value,
            .runtime = runtimeResult(task_id, runtime),
        });
    }

    const current = try runtimeFor(context.allocator, &batch, &history, task_id);
    defer context.allocator.free(current.unsatisfied);
    if (current.status == .pending and std.mem.eql(u8, request.op, "task.start")) return error.DependencyUnsatisfied;
    const timestamp = try utcTimestamp(context.allocator, context.io);
    defer context.allocator.free(timestamp);
    const mapping = try operation_map.map(request.op, request.actor.kind);
    const is_intervention = isInterventionEvent(mapping.event_type);
    if (is_intervention) try validateIntervention(context.allocator, request, mapping.event_type, current.status, &history);
    const prepared = if (is_intervention)
        try command.prepareIntervention(context.allocator, request, current.status, current.attempt, history.items.len + 1, timestamp)
    else
        try command.prepare(context.allocator, request, current.status, current.attempt, hasPendingRetry(&history, task_id), history.items.len + 1, timestamp);
    defer prepared.deinit(context.allocator);
    const append_result = try event_log.appendPersistent(project, context.io, context.allocator, request.request_id, &prepared.semantic_hash, prepared.encoded);
    if (append_result.duplicate) return error.StoreCorrupt;

    const events_bytes = try project.readFileAlloc(context.io, ".ztasks/events.jsonl", context.allocator, .limited(64 * 1024 * 1024));
    defer context.allocator.free(events_bytes);
    const prefix = prefixIdentity(events_bytes);
    const snapshot = snapshot_store.Snapshot{
        .version = 1,
        .last_seq = append_result.seq,
        .prefix_identity = &prefix,
        .runtime_json = prepared.encoded,
    };
    const snapshot_bytes = try snapshot.encode(context.allocator);
    defer context.allocator.free(snapshot_bytes);
    try snapshot_store.writeAtomic(project, context.io, ".ztasks/state.json", snapshot_bytes);

    var stored_event = try std.json.parseFromSlice(StoredEvent, context.allocator, prepared.encoded, .{ .ignore_unknown_fields = false, .allocate = .alloc_always });
    defer stored_event.deinit();
    const runtime = RuntimeView{
        .status = prepared.status_after,
        .attempt = prepared.attempt_after,
        .agent = if (std.mem.eql(u8, request.op, "task.start")) request.actor.id else current.agent,
        .session_id = stored_event.value.session_id orelse current.session_id,
        .current_action = if (prepared.status_after.isTerminal()) null else if (std.mem.eql(u8, request.op, "task.progress")) eventMessage(stored_event.value) else current.current_action,
        .unsatisfied = &.{},
    };
    return encodeSuccess(context.allocator, request.request_id, .{
        .event = stored_event.value,
        .runtime = runtimeResult(task_id, runtime),
    });
}

fn isInterventionEvent(event_type: event_domain.EventType) bool {
    return switch (event_type) {
        .human_pause_requested, .human_resume_requested, .human_retry_requested, .human_stop_requested, .human_skip_requested, .human_inspect_requested, .human_comment, .intervention_responded => true,
        else => false,
    };
}

fn validateIntervention(
    allocator: std.mem.Allocator,
    request: request_protocol.Request,
    event_type: event_domain.EventType,
    status: runtime_domain.RuntimeStatus,
    history: *const History,
) !void {
    var requests: std.ArrayList(intervention_domain.InterventionRequest) = .empty;
    defer requests.deinit(allocator);
    for (history.items) |item| {
        const action = actionFromEventType(item.event.value.type) orelse continue;
        try requests.append(allocator, .{
            .event_id = item.event.value.event_id,
            .task_id = item.event.value.task_id orelse continue,
            .action = action,
            .state = .pending,
        });
    }
    for (history.items) |item| {
        if (!std.mem.eql(u8, item.event.value.type, "intervention.responded") or item.event.value.payload != .object) continue;
        const request_id_value = item.event.value.payload.object.get("request_event_id") orelse continue;
        const outcome_value = item.event.value.payload.object.get("outcome") orelse continue;
        if (request_id_value != .string or outcome_value != .string) continue;
        for (requests.items) |*pending| {
            if (!std.mem.eql(u8, pending.event_id, request_id_value.string)) continue;
            pending.respond(item.event.value.event_id, parseOutcome(outcome_value.string) orelse continue) catch {};
        }
    }
    for (history.items) |item| {
        for (requests.items) |*pending| {
            if (!std.mem.eql(u8, pending.task_id, item.event.value.task_id orelse continue)) continue;
            if (lifecycleResolves(pending.action, item.event.value.type)) {
                pending.resolve(item.event.value.event_id) catch {};
            }
        }
    }
    if (event_type == .intervention_responded) {
        const correlated = payloadStringValue(request.payload.object, "request_event_id") orelse return error.InvalidIntervention;
        for (requests.items) |pending| {
            if (std.mem.eql(u8, pending.event_id, correlated) and pending.state == .pending) return;
        }
        return error.InvalidIntervention;
    }
    const action = actionFromEventType(event_type.wireName()) orelse return error.InvalidIntervention;
    var same_task: std.ArrayList(intervention_domain.InterventionRequest) = .empty;
    defer same_task.deinit(allocator);
    for (requests.items) |pending| {
        if (request.task_id != null and std.mem.eql(u8, pending.task_id, request.task_id.?)) try same_task.append(allocator, pending);
    }
    try intervention_domain.validateCreation(action, status, .current, same_task.items);
}

fn lifecycleResolves(action: intervention_domain.InterventionAction, event_type: []const u8) bool {
    return switch (action) {
        .pause => std.mem.eql(u8, event_type, "task.paused"),
        .@"resume" => std.mem.eql(u8, event_type, "task.resumed"),
        .retry => std.mem.eql(u8, event_type, "task.started"),
        .stop => std.mem.eql(u8, event_type, "task.failed") or std.mem.eql(u8, event_type, "task.skipped"),
        .skip => std.mem.eql(u8, event_type, "task.skipped"),
        .inspect, .comment => false,
    };
}

fn hasPendingRetry(history: *const History, task_id: []const u8) bool {
    var pending = false;
    for (history.items) |item| {
        const event_task_id = item.event.value.task_id orelse continue;
        if (!std.mem.eql(u8, event_task_id, task_id)) continue;
        if (std.mem.eql(u8, item.event.value.type, "human.retry_requested")) pending = true;
        if (std.mem.eql(u8, item.event.value.type, "task.started")) pending = false;
    }
    return pending;
}

fn actionFromEventType(event_type: []const u8) ?intervention_domain.InterventionAction {
    if (std.mem.eql(u8, event_type, "human.pause_requested")) return .pause;
    if (std.mem.eql(u8, event_type, "human.resume_requested")) return .@"resume";
    if (std.mem.eql(u8, event_type, "human.retry_requested")) return .retry;
    if (std.mem.eql(u8, event_type, "human.stop_requested")) return .stop;
    if (std.mem.eql(u8, event_type, "human.skip_requested")) return .skip;
    if (std.mem.eql(u8, event_type, "human.inspect_requested")) return .inspect;
    if (std.mem.eql(u8, event_type, "human.comment")) return .comment;
    return null;
}

fn parseOutcome(value: []const u8) ?intervention_domain.ResponseOutcome {
    if (std.mem.eql(u8, value, "acknowledged")) return .acknowledged;
    if (std.mem.eql(u8, value, "rejected")) return .rejected;
    if (std.mem.eql(u8, value, "unsupported")) return .unsupported;
    if (std.mem.eql(u8, value, "completed")) return .completed;
    return null;
}

fn payloadStringValue(payload: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = payload.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

fn runtimeResult(task_id: []const u8, runtime: RuntimeView) struct {
    task_id: []const u8,
    status: []const u8,
    attempt: u32,
    agent: ?[]const u8,
    session_id: ?[]const u8,
    current_action: ?[]const u8,
} {
    return .{
        .task_id = task_id,
        .status = @tagName(runtime.status),
        .attempt = runtime.attempt,
        .agent = runtime.agent,
        .session_id = runtime.session_id,
        .current_action = runtime.current_action,
    };
}

fn handleEventList(context: Context, request: request_protocol.Request) ![]u8 {
    const project = try std.Io.Dir.openDirAbsolute(context.io, context.project_root, .{});
    defer project.close(context.io);
    var history = try loadHistory(context, project);
    defer history.deinit(context.allocator);
    var events: std.ArrayList(StoredEvent) = .empty;
    defer events.deinit(context.allocator);
    for (history.items) |item| {
        if (request.task_id) |task_id| {
            if (item.event.value.task_id == null or !std.mem.eql(u8, item.event.value.task_id.?, task_id)) continue;
        }
        try events.append(context.allocator, item.event.value);
    }
    return encodeSuccess(context.allocator, request.request_id, .{ .events = events.items });
}

const StoredDefinitionTask = struct {
    id: []const u8,
    title: []const u8,
    phase_id: []const u8,
    order: u32,
    dependencies: []const []const u8,
    parallel_hint: bool,
    story: ?[]const u8,
    fingerprint: []const u8,
};

const StoredDefinition = struct {
    version: u8,
    source: std.json.Value,
    phases: std.json.Value,
    tasks: []const StoredDefinitionTask,
};

const PriorCatalog = struct {
    items: []sync_application.Prior,

    fn deinit(self: PriorCatalog, allocator: std.mem.Allocator) void {
        for (self.items) |item| {
            allocator.free(item.id);
            allocator.free(item.fingerprint);
        }
        allocator.free(self.items);
    }
};

const ProjectEventPayload = struct {
    previous_digest: ?[]const u8,
    source_digest: []const u8,
    definition_ref: []const u8,
    definition_digest: []const u8,
    dependency_digest: []const u8,
    added: []const []const u8,
    changed: []const []const u8,
    missing: []const []const u8,
    reappeared: []const []const u8,
};

fn handleProjectMutation(context: Context, request: request_protocol.Request) ![]u8 {
    _ = try operation_map.map(request.op, request.actor.kind);
    const project = try std.Io.Dir.openDirAbsolute(context.io, context.project_root, .{});
    defer project.close(context.io);
    var lock = try project_lock.ProjectLock.acquire(project, context.io);
    defer lock.release();
    var history = try loadHistory(context, project);
    defer history.deinit(context.allocator);

    const initialized = latestProjectEvent(&history) != null;
    if (std.mem.eql(u8, request.op, "project.init") and initialized) return error.AlreadyInitialized;
    if (std.mem.eql(u8, request.op, "source.sync") and !initialized) return error.NotInitialized;
    const semantic_hash = command.semanticHash(request);
    for (history.items) |item| {
        if (!std.mem.eql(u8, item.record.value.request_id, request.request_id)) continue;
        if (!std.mem.eql(u8, item.record.value.semantic_hash, &semantic_hash)) return error.IdempotencyConflict;
        return encodeSuccess(context.allocator, request.request_id, .{ .event = item.event.value });
    }

    const locator_override = payloadStringValue(request.payload.object, "locator");
    const locator = if (locator_override) |value| try context.allocator.dupe(u8, value) else try resolveLocator(context);
    defer context.allocator.free(locator);
    const markdown = project.readFileAlloc(context.io, locator, context.allocator, .limited(4 * 1024 * 1024)) catch return error.SourceNotFound;
    defer context.allocator.free(markdown);
    var persisted = try project_init.persistSource(project, context.io, context.allocator, locator, markdown);
    defer persisted.deinit(context.allocator);

    var changes = sync_application.ChangeSet{
        .added = try context.allocator.alloc([]const u8, 0),
        .changed = try context.allocator.alloc([]const u8, 0),
        .missing = try context.allocator.alloc([]const u8, 0),
        .reappeared = try context.allocator.alloc([]const u8, 0),
    };
    defer changes.deinit(context.allocator);
    var previous_digest: []const u8 = "";
    if (latestProjectEvent(&history)) |prior_event| {
        previous_digest = payloadStringFromValue(prior_event.payload, "source_digest") orelse return error.StoreCorrupt;
        const prior_catalog = try buildPriorCatalog(context, project, &history);
        defer prior_catalog.deinit(context.allocator);
        var definition = try std.json.parseFromSlice(StoredDefinition, context.allocator, persisted.definition_json, .{ .ignore_unknown_fields = false, .allocate = .alloc_always });
        defer definition.deinit();
        const current = try context.allocator.alloc(sync_application.Definition, definition.value.tasks.len);
        defer context.allocator.free(current);
        for (definition.value.tasks, 0..) |task, index| current[index] = .{ .id = task.id, .fingerprint = task.fingerprint };
        changes.deinit(context.allocator);
        changes = try sync_application.diff(context.allocator, prior_catalog.items, current);
    }

    const seq: u64 = @intCast(history.items.len + 1);
    const timestamp = try utcTimestamp(context.allocator, context.io);
    defer context.allocator.free(timestamp);
    const event_id = try std.fmt.allocPrint(context.allocator, "evt-{d}", .{seq});
    defer context.allocator.free(event_id);
    const event_type = if (std.mem.eql(u8, request.op, "project.init")) "project.initialized" else "source.synced";
    const payload: ProjectEventPayload = if (std.mem.eql(u8, request.op, "project.init"))
        .{
            .previous_digest = @as(?[]const u8, null),
            .source_digest = persisted.source_digest[0..],
            .definition_ref = persisted.artifacts.definition_ref,
            .definition_digest = persisted.artifacts.definition_digest[0..],
            .dependency_digest = persisted.artifacts.dependency_digest[0..],
            .added = &.{},
            .changed = &.{},
            .missing = &.{},
            .reappeared = &.{},
        }
    else
        .{
            .previous_digest = @as(?[]const u8, previous_digest),
            .source_digest = persisted.source_digest[0..],
            .definition_ref = persisted.artifacts.definition_ref,
            .definition_digest = persisted.artifacts.definition_digest[0..],
            .dependency_digest = persisted.artifacts.dependency_digest[0..],
            .added = changes.added,
            .changed = changes.changed,
            .missing = changes.missing,
            .reappeared = changes.reappeared,
        };
    const encoded = try std.json.Stringify.valueAlloc(context.allocator, .{
        .version = @as(u8, 1),
        .event_id = event_id,
        .seq = seq,
        .request_id = request.request_id,
        .timestamp = timestamp,
        .actor = request.actor,
        .type = event_type,
        .task_id = @as(?[]const u8, null),
        .session_id = @as(?[]const u8, null),
        .payload = payload,
        .status_after = @as(?[]const u8, null),
        .attempt_after = @as(u32, 0),
        .redactions = [_]content_policy.Redaction{},
    }, .{});
    defer context.allocator.free(encoded);
    _ = try event_log.appendPersistent(project, context.io, context.allocator, request.request_id, &semantic_hash, encoded);
    var stored_event = try std.json.parseFromSlice(StoredEvent, context.allocator, encoded, .{ .ignore_unknown_fields = false, .allocate = .alloc_always });
    defer stored_event.deinit();
    return encodeSuccess(context.allocator, request.request_id, .{ .event = stored_event.value });
}

fn handleProjectQuery(context: Context, request: request_protocol.Request) ![]u8 {
    const project = try std.Io.Dir.openDirAbsolute(context.io, context.project_root, .{});
    defer project.close(context.io);
    if (std.mem.eql(u8, request.op, "health.check")) return handleHealthCheck(context, request, project);
    var history = try loadHistory(context, project);
    defer history.deinit(context.allocator);
    const latest = latestProjectEvent(&history);
    if (std.mem.eql(u8, request.op, "project.inspect")) {
        return encodeSuccess(context.allocator, request.request_id, .{
            .initialized = latest != null,
            .last_event_seq = history.items.len,
            .source_digest = if (latest) |item| payloadStringFromValue(item.payload, "source_digest") else null,
            .definition_ref = if (latest) |item| payloadStringFromValue(item.payload, "definition_ref") else null,
        });
    }
    unreachable;
}

fn handleHealthCheck(context: Context, request: request_protocol.Request, project: std.Io.Dir) ![]u8 {
    var probe = doctor_application.Probe{};
    var event_count: usize = 0;
    var initialized = false;
    var history = loadHistory(context, project) catch {
        probe.history_valid = false;
        const report = try doctor_application.diagnose(context.allocator, probe);
        defer report.deinit(context.allocator);
        return encodeSuccess(context.allocator, request.request_id, .{
            .healthy = report.healthy(),
            .event_count = event_count,
            .initialized = initialized,
            .diagnostics = report.diagnostics,
        });
    };
    defer history.deinit(context.allocator);
    event_count = history.items.len;
    initialized = latestProjectEvent(&history) != null;

    const snapshot_bytes = project.readFileAlloc(context.io, ".ztasks/state.json", context.allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => blk: {
            probe.snapshot_present = true;
            probe.snapshot_current = false;
            break :blk null;
        },
    };
    if (snapshot_bytes) |bytes| {
        defer context.allocator.free(bytes);
        probe.snapshot_present = true;
        var snapshot = snapshot_store.Snapshot.decode(context.allocator, bytes) catch null;
        if (snapshot) |*parsed| {
            defer parsed.deinit();
            probe.snapshot_current = parsed.value.last_seq == event_count;
        } else probe.snapshot_current = false;
    }
    const report = try doctor_application.diagnose(context.allocator, probe);
    defer report.deinit(context.allocator);
    return encodeSuccess(context.allocator, request.request_id, .{
        .healthy = report.healthy(),
        .event_count = event_count,
        .initialized = initialized,
        .diagnostics = report.diagnostics,
    });
}

fn latestProjectEvent(history: *const History) ?StoredEvent {
    var index = history.items.len;
    while (index > 0) {
        index -= 1;
        const item = history.items[index].event.value;
        if (std.mem.eql(u8, item.type, "project.initialized") or std.mem.eql(u8, item.type, "source.synced")) return item;
    }
    return null;
}

fn payloadStringFromValue(payload: std.json.Value, key: []const u8) ?[]const u8 {
    if (payload != .object) return null;
    const value = payload.object.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

fn buildPriorCatalog(context: Context, project: std.Io.Dir, history: *const History) !PriorCatalog {
    var items: std.ArrayList(sync_application.Prior) = .empty;
    errdefer {
        for (items.items) |item| {
            context.allocator.free(item.id);
            context.allocator.free(item.fingerprint);
        }
        items.deinit(context.allocator);
    }
    var history_index = history.items.len;
    var latest = true;
    while (history_index > 0) {
        history_index -= 1;
        const event = history.items[history_index].event.value;
        if (!std.mem.eql(u8, event.type, "project.initialized") and !std.mem.eql(u8, event.type, "source.synced")) continue;
        const reference = payloadStringFromValue(event.payload, "definition_ref") orelse return error.StoreCorrupt;
        const bytes = try project.readFileAlloc(context.io, reference, context.allocator, .limited(16 * 1024 * 1024));
        defer context.allocator.free(bytes);
        var document = std.json.parseFromSlice(StoredDefinition, context.allocator, bytes, .{ .ignore_unknown_fields = false, .allocate = .alloc_always }) catch return error.StoreCorrupt;
        defer document.deinit();
        for (document.value.tasks) |task| {
            var exists = false;
            for (items.items) |item| if (std.mem.eql(u8, item.id, task.id)) {
                exists = true;
                break;
            };
            if (exists) continue;
            try items.append(context.allocator, .{
                .id = try context.allocator.dupe(u8, task.id),
                .fingerprint = try context.allocator.dupe(u8, task.fingerprint),
                .missing = !latest,
            });
        }
        latest = false;
    }
    return .{ .items = try items.toOwnedSlice(context.allocator) };
}

fn prefixIdentity(bytes: []const u8) [71]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    var result: [71]u8 = undefined;
    @memcpy(result[0..7], "sha256:");
    @memcpy(result[7..], &hex);
    return result;
}

fn utcTimestamp(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    const now = std.Io.Clock.real.now(io);
    const seconds: u64 = @intCast(@divFloor(now.nanoseconds, std.time.ns_per_s));
    const epoch = std.time.epoch.EpochSeconds{ .secs = seconds };
    const year_day = epoch.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

fn phaseTitle(batch: anytype, phase_id: []const u8) []const u8 {
    for (batch.phases) |phase| {
        if (std.mem.eql(u8, phase.id, phase_id)) return phase.title;
    }
    return "";
}

fn resolveLocator(context: Context) ![]u8 {
    if (context.source_locator) |locator| {
        try validateLocator(locator);
        return context.allocator.dupe(u8, locator);
    }

    const project = try std.Io.Dir.openDirAbsolute(context.io, context.project_root, .{});
    defer project.close(context.io);
    const specs = project.openDir(context.io, "specs", .{ .iterate = true }) catch return error.SourceNotFound;
    defer specs.close(context.io);
    var iterator = specs.iterate();
    var selected: ?[]u8 = null;
    errdefer if (selected) |locator| context.allocator.free(locator);
    while (try iterator.next(context.io)) |entry| {
        if (entry.kind != .directory) continue;
        const candidate = try std.fmt.allocPrint(context.allocator, "specs/{s}/tasks.md", .{entry.name});
        const stat = project.statFile(context.io, candidate, .{}) catch {
            context.allocator.free(candidate);
            continue;
        };
        if (stat.kind != .file) {
            context.allocator.free(candidate);
            continue;
        }
        if (selected != null) {
            context.allocator.free(candidate);
            return error.SourceAmbiguous;
        }
        selected = candidate;
    }
    return selected orelse error.SourceNotFound;
}

fn validateLocator(locator: []const u8) !void {
    if (locator.len == 0 or std.fs.path.isAbsolute(locator) or std.mem.indexOfScalar(u8, locator, '\\') != null) return error.PathEscapesProject;
    var components = std.mem.splitScalar(u8, locator, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..")) return error.PathEscapesProject;
    }
}

fn encodeSuccess(allocator: std.mem.Allocator, request_id: []const u8, result: anytype) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = @as(u8, 1),
        .request_id = request_id,
        .ok = true,
        .result = result,
        .warnings = [_][]const u8{},
    }, .{});
}

test "read-only handler returns correlated version response" {
    const line = "{\"version\":1,\"request_id\":\"req-1\",\"op\":\"version.get\",\"actor\":{\"kind\":\"human\"},\"payload\":{}}";
    const response = try handleLine(.{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_root = "/tmp",
    }, line);
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"request_id\":\"req-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"protocol_version\":1") != null);
}

test "read-only handler rejects mutations without producing an event" {
    const line = "{\"version\":1,\"request_id\":\"req-2\",\"op\":\"task.start\",\"actor\":{\"kind\":\"human\"},\"task_id\":\"T001\",\"payload\":{}}";
    const response = try handleLine(.{
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .project_root = "/tmp",
    }, line);
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"ok\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"event\"") == null);
}

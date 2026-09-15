const std = @import("std");
const query = @import("../application/query.zig");
const request_protocol = @import("request.zig");
const response_protocol = @import("response.zig");

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
            .protocol_version = @as(u8, 1),
            .capabilities = [_][]const u8{ "source.validate", "task.list", "task.show" },
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

    var projection = try query.listInitial(context.allocator, &batch);
    defer projection.deinit(context.allocator);
    const task_results = try context.allocator.alloc(TaskResult, batch.tasks.len);
    defer context.allocator.free(task_results);
    for (batch.tasks, 0..) |task, index| {
        task_results[index] = .{
            .id = task.id,
            .phase = phaseTitle(&batch, task.phase_id),
            .title = task.title,
            .status = @tagName(projection.tasks[index].status),
            .unsatisfied_dependencies = projection.tasks[index].unsatisfied,
        };
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
    unsatisfied_dependencies: []const []const u8,
};

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

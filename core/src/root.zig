const std = @import("std");

pub const protocol_version: u32 = 1;
pub const content_policy = @import("domain/content_policy.zig");
pub const task_definition = @import("domain/task_definition.zig");
pub const task_runtime = @import("domain/task_runtime.zig");
pub const event = @import("domain/event.zig");
pub const protocol_request = @import("protocol/request.zig");
pub const protocol_response = @import("protocol/response.zig");
pub const compatibility = @import("protocol/compatibility.zig");
pub const source = @import("sources/source.zig");
pub const dependency_extraction = @import("sources/dependency_extraction.zig");
pub const speckit = @import("sources/speckit.zig");
pub const definition_query = @import("application/definition_query.zig");
pub const sync_application = @import("application/sync.zig");
pub const reducer = @import("domain/reducer.zig");
pub const query = @import("application/query.zig");
pub const protocol_handler = @import("protocol/handler.zig");
pub const transition = @import("domain/transition.zig");
pub const operation_map = @import("application/operation_map.zig");
pub const storage_paths = @import("storage/paths.zig");
pub const storage_lock = @import("storage/lock.zig");
pub const event_log = @import("storage/event_log.zig");
pub const replay = @import("storage/replay.zig");
pub const snapshot = @import("storage/snapshot.zig");
pub const source_artifact_store = @import("storage/source_artifact_store.zig");
pub const command = @import("application/command.zig");
pub const intervention = @import("domain/intervention.zig");
pub const project_init = @import("application/project_init.zig");
pub const doctor = @import("application/doctor.zig");

test "protocol version starts at one" {
    try std.testing.expectEqual(@as(u32, 1), protocol_version);
}

test "Zig accepts every shared Protocol v1 golden envelope" {
    const contents = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "protocol/fixtures/v1/envelopes.jsonl",
        std.testing.allocator,
        .limited(2 * 1024 * 1024),
    );
    defer std.testing.allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        count += 1;
        if (std.mem.indexOf(u8, line, "\"op\"") != null) {
            var parsed = try protocol_request.decode(std.testing.allocator, line);
            parsed.deinit();
        } else {
            var parsed = try protocol_response.decode(std.testing.allocator, line);
            parsed.deinit();
        }
    }
    try std.testing.expectEqual(@as(usize, 6), count);
}

test "property sweep keeps dependency diff and Protocol decoding deterministic" {
    var index: usize = 1;
    while (index <= 128) : (index += 1) {
        const line = try std.fmt.allocPrint(std.testing.allocator, "{{\"version\":1,\"request_id\":\"property-{d}\",\"op\":\"version.get\",\"actor\":{{\"kind\":\"system\"}},\"payload\":{{}}}}", .{index});
        defer std.testing.allocator.free(line);
        var request = try protocol_request.decode(std.testing.allocator, line);
        defer request.deinit();
        try std.testing.expectEqualStrings("version.get", request.value.op);
        const changes = try sync_application.diff(std.testing.allocator, &.{.{ .id = "T001", .fingerprint = "same" }}, &.{.{ .id = "T001", .fingerprint = "same" }});
        defer changes.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), changes.added.len + changes.changed.len + changes.missing.len + changes.reappeared.len);
    }
    const source_bytes = "## Phase 1\n- [ ] T001 Base\n- [ ] T002 Next (depends on T001)\n";
    var first_source = try speckit.parse(std.testing.allocator, "tasks.md", source_bytes);
    defer first_source.deinit(std.testing.allocator);
    var second_source = try speckit.parse(std.testing.allocator, "tasks.md", source_bytes);
    defer second_source.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(first_source.dependency_artifact.dependencies, second_source.dependency_artifact.dependencies);

    const facts = [_]reducer.ExecutionFact{
        .{ .event_type = .task_started, .seq = 1, .timestamp = "2026-01-01T00:00:00Z" },
        .{ .event_type = .task_completed, .seq = 2, .timestamp = "2026-01-01T00:01:00Z" },
    };
    const first_replay = try reducer.replayTask("T001", true, &facts);
    const second_replay = try reducer.replayTask("T001", true, &facts);
    try std.testing.expectEqualDeep(first_replay, second_replay);
}

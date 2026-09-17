const std = @import("std");
const query = @import("query.zig");
const speckit = @import("../sources/speckit.zig");
const artifact_store = @import("../storage/source_artifact_store.zig");

pub const PersistedSource = struct {
    batch: speckit.ParsedBatch,
    definition_json: []u8,
    dependency_json: []u8,
    artifacts: artifact_store.StoredArtifacts,
    source_digest: [71]u8,

    pub fn deinit(self: *PersistedSource, allocator: std.mem.Allocator) void {
        self.artifacts.deinit(allocator);
        allocator.free(self.definition_json);
        allocator.free(self.dependency_json);
        self.batch.deinit(allocator);
    }
};

pub fn persistSource(
    project: std.Io.Dir,
    io: std.Io,
    allocator: std.mem.Allocator,
    locator: []const u8,
    markdown: []const u8,
) !PersistedSource {
    var batch = try query.validateSource(allocator, locator, markdown);
    errdefer batch.deinit(allocator);
    const definition_json = try canonicalDefinition(allocator, &batch);
    errdefer allocator.free(definition_json);
    const dependency_json = try batch.dependency_artifact.canonicalJson(allocator);
    errdefer allocator.free(dependency_json);
    var source_digest: [71]u8 = undefined;
    @memcpy(source_digest[0..7], "sha256:");
    @memcpy(source_digest[7..], &batch.dependency_artifact.source_digest);
    const artifacts = try artifact_store.writeVerified(project, io, allocator, &source_digest, definition_json, dependency_json);
    return .{
        .batch = batch,
        .definition_json = definition_json,
        .dependency_json = dependency_json,
        .artifacts = artifacts,
        .source_digest = source_digest,
    };
}

const PhaseArtifact = struct { id: []const u8, title: []const u8, order: u32 };
const TaskArtifact = struct {
    id: []const u8,
    title: []const u8,
    phase_id: []const u8,
    order: u32,
    dependencies: []const []const u8,
    parallel_hint: bool,
    story: ?[]const u8,
    fingerprint: []const u8,
};

pub fn canonicalDefinition(allocator: std.mem.Allocator, batch: *const speckit.ParsedBatch) ![]u8 {
    const phases = try allocator.alloc(PhaseArtifact, batch.phases.len);
    defer allocator.free(phases);
    for (batch.phases, 0..) |phase, index| phases[index] = .{ .id = phase.id, .title = phase.title, .order = phase.order };
    const tasks = try allocator.alloc(TaskArtifact, batch.tasks.len);
    defer allocator.free(tasks);
    const fingerprints = try allocator.alloc([71]u8, batch.tasks.len);
    defer allocator.free(fingerprints);
    for (batch.tasks, 0..) |task, index| {
        const semantic = try std.json.Stringify.valueAlloc(allocator, .{
            .id = task.id,
            .title = task.title,
            .phase_id = task.phase_id,
            .order = task.order,
            .dependencies = task.dependencies,
            .parallel_hint = task.parallel_hint,
            .story = task.story,
        }, .{});
        defer allocator.free(semantic);
        fingerprints[index] = artifact_store.digest(semantic);
        tasks[index] = .{
            .id = task.id,
            .title = task.title,
            .phase_id = task.phase_id,
            .order = task.order,
            .dependencies = task.dependencies,
            .parallel_hint = task.parallel_hint,
            .story = task.story,
            .fingerprint = &fingerprints[index],
        };
    }
    var digest_buffer: [71]u8 = undefined;
    @memcpy(digest_buffer[0..7], "sha256:");
    @memcpy(digest_buffer[7..], &batch.dependency_artifact.source_digest);
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{
        .version = @as(u8, 1),
        .source = .{ .locator = batch.locator, .digest = digest_buffer[0..] },
        .phases = phases,
        .tasks = tasks,
    }, .{});
    defer allocator.free(encoded);
    const output = try allocator.alloc(u8, encoded.len + 1);
    @memcpy(output[0..encoded.len], encoded);
    output[encoded.len] = '\n';
    return output;
}

test "project source persistence creates both artifacts without changing source bytes" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const markdown = "## Phase 1\n- [ ] T001 Base\n";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tasks.md", .data = markdown });
    const before = try temporary.dir.readFileAlloc(std.testing.io, "tasks.md", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(before);
    var persisted = try persistSource(temporary.dir, std.testing.io, std.testing.allocator, "tasks.md", markdown);
    defer persisted.deinit(std.testing.allocator);
    const after = try temporary.dir.readFileAlloc(std.testing.io, "tasks.md", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    _ = try temporary.dir.statFile(std.testing.io, persisted.artifacts.definition_ref, .{});
    const dependency_path = try std.fmt.allocPrint(std.testing.allocator, ".ztasks/sources/{s}/dependencies.json", .{persisted.source_digest[7..]});
    defer std.testing.allocator.free(dependency_path);
    _ = try temporary.dir.statFile(std.testing.io, dependency_path, .{});
    try std.testing.expect(std.mem.endsWith(u8, persisted.dependency_json, "\n"));
}

const std = @import("std");

pub const Evidence = struct { line: u32, column: u32 };
pub const Dependency = struct {
    task_id: []const u8,
    depends_on: []const []const u8,
    evidence: Evidence,
};
pub const Diagnostic = struct {
    code: []const u8,
    task_id: []const u8,
    line: u32,
    column: u32,
};

pub const Artifact = struct {
    locator: []const u8,
    source_digest: [64]u8,
    dependencies: []Dependency,
    diagnostics: []Diagnostic,

    pub fn deinit(self: *Artifact, allocator: std.mem.Allocator) void {
        for (self.dependencies) |dependency| allocator.free(dependency.depends_on);
        allocator.free(self.dependencies);
        allocator.free(self.diagnostics);
    }

    pub fn validateSource(self: Artifact, source: []const u8) !void {
        if (!std.mem.eql(u8, &self.source_digest, &sourceDigest(source))) return error.SourceChanged;
    }

    pub fn canonicalJson(self: Artifact, allocator: std.mem.Allocator) ![]u8 {
        var digest_buffer: [71]u8 = undefined;
        @memcpy(digest_buffer[0..7], "sha256:");
        @memcpy(digest_buffer[7..], &self.source_digest);
        const value = .{
            .version = @as(u8, 1),
            .contract_version = @as(u8, 1),
            .source = .{ .locator = self.locator, .digest = digest_buffer[0..] },
            .dependencies = self.dependencies,
            .diagnostics = self.diagnostics,
        };
        const json = try std.json.Stringify.valueAlloc(allocator, value, .{});
        defer allocator.free(json);
        const output = try allocator.alloc(u8, json.len + 1);
        @memcpy(output[0..json.len], json);
        output[json.len] = '\n';
        return output;
    }
};

pub fn extract(allocator: std.mem.Allocator, locator: []const u8, source: []const u8) !Artifact {
    var dependencies: std.ArrayList(Dependency) = .empty;
    errdefer {
        for (dependencies.items) |dependency| allocator.free(dependency.depends_on);
        dependencies.deinit(allocator);
    }
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    errdefer diagnostics.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: u32 = 0;
    while (lines.next()) |raw_line| {
        line_number += 1;
        const task_id = recognizedTaskId(raw_line) orelse continue;
        const line = std.mem.trimEnd(u8, raw_line, " ");
        if (try parseExactClause(allocator, line)) |clause| {
            try dependencies.append(allocator, .{
                .task_id = task_id,
                .depends_on = clause.ids,
                .evidence = .{ .line = line_number, .column = @intCast(clause.column) },
            });
        } else if (looksLikeDependency(line)) {
            try diagnostics.append(allocator, .{ .code = "dependency_ambiguous", .task_id = task_id, .line = line_number, .column = 1 });
        } else {
            try diagnostics.append(allocator, .{ .code = "dependency_not_declared", .task_id = task_id, .line = line_number, .column = 1 });
        }
    }

    return .{
        .locator = locator,
        .source_digest = sourceDigest(source),
        .dependencies = try dependencies.toOwnedSlice(allocator),
        .diagnostics = try diagnostics.toOwnedSlice(allocator),
    };
}

const ParsedClause = struct { ids: []const []const u8, column: usize };

fn parseExactClause(allocator: std.mem.Allocator, line: []const u8) !?ParsedClause {
    const marker = " (depends on ";
    const start = std.mem.lastIndexOf(u8, line, marker) orelse return null;
    if (line.len < start + marker.len + 2 or line[line.len - 1] != ')') return null;
    if (std.mem.indexOf(u8, line[0..start], marker) != null) return null;
    const declaration = line[start + marker.len .. line.len - 1];
    if (declaration.len == 0) return null;

    var ids: std.ArrayList([]const u8) = .empty;
    errdefer ids.deinit(allocator);
    var parts = std.mem.splitSequence(u8, declaration, ", ");
    while (parts.next()) |id| {
        if (!isTaskId(id)) return null;
        try ids.append(allocator, id);
    }
    if (ids.items.len == 0) return null;
    return .{ .ids = try ids.toOwnedSlice(allocator), .column = start + 2 };
}

fn recognizedTaskId(raw_line: []const u8) ?[]const u8 {
    const line = std.mem.trimStart(u8, raw_line, " \t");
    if (line.len < 8 or (line[0] != '-' and line[0] != '*' and line[0] != '+') or line[1] != ' ') return null;
    if (!(std.mem.startsWith(u8, line[2..], "[ ] ") or std.mem.startsWith(u8, line[2..], "[x] ") or std.mem.startsWith(u8, line[2..], "[X] "))) return null;
    const id_start: usize = 6;
    var id_end = id_start;
    while (id_end < line.len and line[id_end] != ' ') : (id_end += 1) {}
    const id = line[id_start..id_end];
    return if (isTaskId(id)) id else null;
}

fn isTaskId(value: []const u8) bool {
    if (value.len < 2 or value[0] != 'T') return false;
    for (value[1..]) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}

fn looksLikeDependency(line: []const u8) bool {
    var index: usize = 0;
    while (index + "depend".len <= line.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(line[index .. index + "depend".len], "depend")) return true;
    }
    return false;
}

fn sourceDigest(source: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

test "exact terminal clause preserves dependency order and evidence" {
    var artifact = try extract(std.testing.allocator, "tasks.md", "- [ ] T003 Work (depends on T002, T001)\n");
    defer artifact.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), artifact.dependencies.len);
    try std.testing.expectEqualStrings("T002", artifact.dependencies[0].depends_on[0]);
    try std.testing.expectEqualStrings("T001", artifact.dependencies[0].depends_on[1]);
    try std.testing.expectEqual(@as(u32, 1), artifact.dependencies[0].evidence.line);
    try std.testing.expectEqual(@as(u32, 17), artifact.dependencies[0].evidence.column);
}

test "ambiguous and absent declarations diagnose without edges" {
    var ambiguous = try extract(std.testing.allocator, "tasks.md", "- [ ] T002 Work (Depends on T001)\n");
    defer ambiguous.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("dependency_ambiguous", ambiguous.diagnostics[0].code);
    try std.testing.expectEqual(@as(usize, 0), ambiguous.dependencies.len);

    var absent = try extract(std.testing.allocator, "tasks.md", "- [ ] T002 Work\n");
    defer absent.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("dependency_not_declared", absent.diagnostics[0].code);
}

test "canonical JSON and digest are deterministic and stale artifacts reject" {
    const source = "- [ ] T001 Base\n- [ ] T002 Work (depends on T001)\n";
    var first = try extract(std.testing.allocator, "tasks.md", source);
    defer first.deinit(std.testing.allocator);
    var second = try extract(std.testing.allocator, "tasks.md", source);
    defer second.deinit(std.testing.allocator);
    const first_json = try first.canonicalJson(std.testing.allocator);
    defer std.testing.allocator.free(first_json);
    const second_json = try second.canonicalJson(std.testing.allocator);
    defer std.testing.allocator.free(second_json);
    try std.testing.expectEqualSlices(u8, first_json, second_json);
    try std.testing.expect(first_json[first_json.len - 1] == '\n');
    try first.validateSource(source);
    try std.testing.expectError(error.SourceChanged, first.validateSource("changed"));
}

test "exact shared fixture matches canonical artifact bytes" {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "protocol/fixtures/speckit/dependencies/exact/tasks.md",
        std.testing.allocator,
        .limited(64 * 1024),
    );
    defer std.testing.allocator.free(source);
    const expected = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "protocol/fixtures/speckit/dependencies/exact/expected.json",
        std.testing.allocator,
        .limited(64 * 1024),
    );
    defer std.testing.allocator.free(expected);
    var artifact = try extract(std.testing.allocator, "tasks.md", source);
    defer artifact.deinit(std.testing.allocator);
    const actual = try artifact.canonicalJson(std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}

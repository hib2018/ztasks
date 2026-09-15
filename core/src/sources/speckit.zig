const std = @import("std");
const task_definition = @import("../domain/task_definition.zig");
const dependency_extraction = @import("dependency_extraction.zig");

pub const ParsedBatch = struct {
    locator: []u8,
    source_bytes: []u8,
    phases: []task_definition.PhaseDefinition,
    tasks: []task_definition.TaskDefinition,
    dependency_artifact: dependency_extraction.Artifact,

    pub fn deinit(self: *ParsedBatch, allocator: std.mem.Allocator) void {
        for (self.phases) |phase| allocator.free(phase.id);
        allocator.free(self.phases);
        allocator.free(self.tasks);
        self.dependency_artifact.deinit(allocator);
        allocator.free(self.source_bytes);
        allocator.free(self.locator);
    }
};

pub fn parse(allocator: std.mem.Allocator, locator_input: []const u8, markdown: []const u8) !ParsedBatch {
    const locator = try allocator.dupe(u8, locator_input);
    errdefer allocator.free(locator);
    const source = try allocator.dupe(u8, markdown);
    errdefer allocator.free(source);
    var artifact = try dependency_extraction.extract(allocator, locator, source);
    errdefer artifact.deinit(allocator);

    var phases: std.ArrayList(task_definition.PhaseDefinition) = .empty;
    errdefer {
        for (phases.items) |phase| allocator.free(phase.id);
        phases.deinit(allocator);
    }
    var tasks: std.ArrayList(task_definition.TaskDefinition) = .empty;
    errdefer tasks.deinit(allocator);

    var current_phase: ?usize = null;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: u32 = 0;
    while (lines.next()) |raw_line| {
        line_number += 1;
        const line = std.mem.trimEnd(u8, raw_line, " \t\r");
        if (std.mem.startsWith(u8, line, "## ")) {
            const title = std.mem.trim(u8, line[3..], " \t");
            if (title.len == 0) return error.InvalidPhase;
            const id = try std.fmt.allocPrint(allocator, "phase-{d}", .{phases.items.len + 1});
            errdefer allocator.free(id);
            const phase = task_definition.PhaseDefinition{
                .id = id,
                .title = title,
                .order = @intCast(phases.items.len),
                .source = .{ .locator = locator, .line = line_number, .column = 1 },
            };
            try phase.validate();
            try phases.append(allocator, phase);
            current_phase = phases.items.len - 1;
            continue;
        }

        const phase_index = current_phase orelse continue;
        const row = parseTaskRow(line) orelse continue;
        const phase = phases.items[phase_index];
        const dependencies = dependenciesFor(&artifact, row.id);
        const task = task_definition.TaskDefinition{
            .id = row.id,
            .title = row.title,
            .phase_id = phase.id,
            .order = @intCast(tasks.items.len),
            .dependencies = dependencies,
            .parallel_hint = row.parallel_hint,
            .story = row.story,
            .source = .{ .locator = locator, .line = line_number, .column = row.column },
            .source_checked = row.checked,
            .metadata = &.{},
        };
        try task.validate();
        try tasks.append(allocator, task);
    }

    return .{
        .locator = locator,
        .source_bytes = source,
        .phases = try phases.toOwnedSlice(allocator),
        .tasks = try tasks.toOwnedSlice(allocator),
        .dependency_artifact = artifact,
    };
}

const ParsedRow = struct {
    id: []const u8,
    title: []const u8,
    parallel_hint: bool,
    story: ?[]const u8,
    checked: bool,
    column: u32,
};

fn parseTaskRow(raw_line: []const u8) ?ParsedRow {
    const line = std.mem.trimStart(u8, raw_line, " \t");
    const indent = raw_line.len - line.len;
    if (line.len < 8 or (line[0] != '-' and line[0] != '*' and line[0] != '+') or line[1] != ' ') return null;
    const checked = if (std.mem.startsWith(u8, line[2..], "[ ] ")) false else if (std.mem.startsWith(u8, line[2..], "[x] ") or std.mem.startsWith(u8, line[2..], "[X] ")) true else return null;
    var cursor: usize = 6;
    const id_start = cursor;
    while (cursor < line.len and line[cursor] != ' ') : (cursor += 1) {}
    if (cursor == line.len or !task_definition.isTaskId(line[id_start..cursor])) return null;
    const id = line[id_start..cursor];
    cursor += 1;

    var parallel_hint = false;
    if (std.mem.startsWith(u8, line[cursor..], "[P] ")) {
        parallel_hint = true;
        cursor += 4;
    }
    var story: ?[]const u8 = null;
    if (cursor < line.len and line[cursor] == '[') {
        const close = std.mem.indexOfScalarPos(u8, line, cursor, ']') orelse return null;
        const label = line[cursor + 1 .. close];
        if (label.len >= 3 and std.mem.startsWith(u8, label, "US")) {
            for (label[2..]) |byte| if (!std.ascii.isDigit(byte)) return null;
            if (close + 1 >= line.len or line[close + 1] != ' ') return null;
            story = label;
            cursor = close + 2;
        }
    }
    if (cursor >= line.len) return null;
    var title_end = line.len;
    if (std.mem.lastIndexOf(u8, line, " (depends on ")) |clause| {
        if (line[line.len - 1] == ')') title_end = clause;
    }
    const title = std.mem.trim(u8, line[cursor..title_end], " \t");
    if (title.len == 0) return null;
    return .{
        .id = id,
        .title = title,
        .parallel_hint = parallel_hint,
        .story = story,
        .checked = checked,
        .column = @intCast(indent + 1),
    };
}

fn dependenciesFor(artifact: *const dependency_extraction.Artifact, task_id: []const u8) []const []const u8 {
    for (artifact.dependencies) |dependency| {
        if (std.mem.eql(u8, dependency.task_id, task_id)) return dependency.depends_on;
    }
    return &.{};
}

test "recognized rows preserve phases order hints story checkbox and title" {
    const markdown =
        \\# Tasks
        \\
        \\## Phase 1: Setup
        \\- [x] T001 [P] [US1] Build core
        \\- [ ] T002 Add protocol (depends on T001)
    ;
    var batch = try parse(std.testing.allocator, "specs/001/tasks.md", markdown);
    defer batch.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), batch.phases.len);
    try std.testing.expectEqualStrings("Phase 1: Setup", batch.phases[0].title);
    try std.testing.expectEqual(@as(usize, 2), batch.tasks.len);
    try std.testing.expect(batch.tasks[0].parallel_hint);
    try std.testing.expectEqualStrings("US1", batch.tasks[0].story.?);
    try std.testing.expect(batch.tasks[0].source_checked);
    try std.testing.expectEqualStrings("Build core", batch.tasks[0].title);
    try std.testing.expectEqualStrings("T001", batch.tasks[1].dependencies[0]);
}

test "unrecognized prose and tasks without phase do not become definitions" {
    const markdown =
        \\- [ ] T999 Outside a phase
        \\## Phase 1
        \\Narrative T001 is not a task
        \\- [ ] T001 Valid task
    ;
    var batch = try parse(std.testing.allocator, "tasks.md", markdown);
    defer batch.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), batch.tasks.len);
    try std.testing.expectEqualStrings("T001", batch.tasks[0].id);
}

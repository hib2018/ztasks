const std = @import("std");

pub const DefinitionInput = struct {
    id: []const u8,
    dependencies: []const []const u8,
};

pub fn validateDefinitions(definitions: []const DefinitionInput) !void {
    for (definitions, 0..) |definition, index| {
        for (definitions[0..index]) |prior| {
            if (std.mem.eql(u8, definition.id, prior.id)) return error.DuplicateTaskId;
        }
        for (definition.dependencies) |dependency| {
            if (std.mem.eql(u8, definition.id, dependency)) return error.SelfDependency;
            if (findDefinition(definitions, dependency) == null) return error.MissingDependency;
        }
    }
    for (definitions) |definition| {
        for (definition.dependencies) |dependency| {
            if (reaches(definitions, dependency, definition.id, 0)) return error.DependencyCycle;
        }
    }
}

fn findDefinition(definitions: []const DefinitionInput, id: []const u8) ?DefinitionInput {
    for (definitions) |definition| {
        if (std.mem.eql(u8, definition.id, id)) return definition;
    }
    return null;
}

fn reaches(definitions: []const DefinitionInput, from: []const u8, target: []const u8, depth: usize) bool {
    if (std.mem.eql(u8, from, target)) return true;
    if (depth >= definitions.len) return true;
    const definition = findDefinition(definitions, from) orelse return false;
    for (definition.dependencies) |dependency| {
        if (reaches(definitions, dependency, target, depth + 1)) return true;
    }
    return false;
}

test "definition batch rejects duplicate missing and self dependencies atomically" {
    try std.testing.expectError(error.DuplicateTaskId, validateDefinitions(&.{ task("T001", &.{}), task("T001", &.{}) }));
    try std.testing.expectError(error.MissingDependency, validateDefinitions(&.{task("T001", &.{"T999"})}));
    try std.testing.expectError(error.SelfDependency, validateDefinitions(&.{task("T001", &.{"T001"})}));
}

test "definition batch rejects dependency cycles" {
    try std.testing.expectError(error.DependencyCycle, validateDefinitions(&.{ task("T001", &.{"T002"}), task("T002", &.{"T001"}) }));
}

fn task(id: []const u8, dependencies: []const []const u8) DefinitionInput {
    return .{ .id = id, .dependencies = dependencies };
}

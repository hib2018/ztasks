const std = @import("std");

pub const RuntimePaths = struct {
    root: []u8,
    events: []u8,
    snapshot: []u8,
    lock: []u8,

    pub fn init(allocator: std.mem.Allocator, project_root: []const u8) !RuntimePaths {
        if (!std.fs.path.isAbsolute(project_root)) return error.ProjectRootNotAbsolute;
        const root = try std.fs.path.join(allocator, &.{ project_root, ".ztasks" });
        errdefer allocator.free(root);
        return .{
            .root = root,
            .events = try std.fs.path.join(allocator, &.{ root, "events.jsonl" }),
            .snapshot = try std.fs.path.join(allocator, &.{ root, "state.json" }),
            .lock = try std.fs.path.join(allocator, &.{ root, "write.lock" }),
        };
    }

    pub fn deinit(self: RuntimePaths, allocator: std.mem.Allocator) void {
        allocator.free(self.events);
        allocator.free(self.snapshot);
        allocator.free(self.lock);
        allocator.free(self.root);
    }

    pub fn validateOwned(self: RuntimePaths, candidate: []const u8) !void {
        if (!std.mem.startsWith(u8, candidate, self.root) or candidate.len <= self.root.len or candidate[self.root.len] != std.fs.path.sep) {
            return error.PathOutsideRuntime;
        }
    }
};

test "runtime paths are project-local and reject prefix collisions" {
    const paths = try RuntimePaths.init(std.testing.allocator, "/project");
    defer paths.deinit(std.testing.allocator);
    try paths.validateOwned("/project/.ztasks/events.jsonl");
    try std.testing.expectError(error.PathOutsideRuntime, paths.validateOwned("/project/.ztasks-evil/events.jsonl"));
    try std.testing.expectError(error.PathOutsideRuntime, paths.validateOwned("/tmp/events.jsonl"));
}

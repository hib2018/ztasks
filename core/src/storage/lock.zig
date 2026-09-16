const std = @import("std");

const Entry = struct { path: []u8, owner: u64, held: bool };

pub const LockRegistry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator) LockRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LockRegistry) void {
        for (self.entries.items) |entry| self.allocator.free(entry.path);
        self.entries.deinit(self.allocator);
    }

    pub fn acquire(self: *LockRegistry, path: []const u8, owner: u64) !Guard {
        for (self.entries.items, 0..) |entry, index| {
            if (!std.mem.eql(u8, entry.path, path)) continue;
            if (entry.held) return error.StoreLocked;
            self.entries.items[index] = .{ .path = entry.path, .owner = owner, .held = true };
            return .{ .registry = self, .index = index };
        }
        try self.entries.append(self.allocator, .{ .path = try self.allocator.dupe(u8, path), .owner = owner, .held = true });
        return .{ .registry = self, .index = self.entries.items.len - 1 };
    }
};

pub const Guard = struct {
    registry: *LockRegistry,
    index: usize,

    pub fn release(self: *Guard) void {
        self.registry.entries.items[self.index].held = false;
    }

    pub fn processExited(self: *Guard) void {
        self.release();
    }
};

pub const ProjectLock = struct {
    file: std.Io.File,
    io: std.Io,
    held: bool = true,

    pub fn acquire(project: std.Io.Dir, io: std.Io) !ProjectLock {
        try project.createDirPath(io, ".ztasks");
        const file = project.createFile(io, ".ztasks/write.lock", .{
            .read = true,
            .truncate = false,
            .lock = .exclusive,
            .lock_nonblocking = true,
        }) catch |err| switch (err) {
            error.WouldBlock => return error.StoreLocked,
            else => return err,
        };
        return .{ .file = file, .io = io };
    }

    pub fn release(self: *ProjectLock) void {
        if (!self.held) return;
        self.file.unlock(self.io);
        self.file.close(self.io);
        self.held = false;
    }
};

test "second writer is rejected until stable project lock is released" {
    var registry = LockRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var first = try registry.acquire("/project/.ztasks/write.lock", 1001);
    try std.testing.expectError(error.StoreLocked, registry.acquire("/project/.ztasks/write.lock", 1002));
    first.release();
    var second = try registry.acquire("/project/.ztasks/write.lock", 1002);
    second.release();
}

test "process exit release makes lock acquirable" {
    var registry = LockRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var owner = try registry.acquire("/project/.ztasks/write.lock", 1001);
    owner.processExited();
    var replacement = try registry.acquire("/project/.ztasks/write.lock", 1002);
    replacement.release();
}

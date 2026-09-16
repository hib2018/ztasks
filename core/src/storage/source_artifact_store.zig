const std = @import("std");

pub const StoredArtifacts = struct {
    definition_ref: []u8,
    definition_digest: [71]u8,
    dependency_digest: [71]u8,

    pub fn deinit(self: StoredArtifacts, allocator: std.mem.Allocator) void {
        allocator.free(self.definition_ref);
    }
};

pub fn writeVerified(
    project: std.Io.Dir,
    io: std.Io,
    allocator: std.mem.Allocator,
    source_digest: []const u8,
    definition_json: []const u8,
    dependency_json: []const u8,
) !StoredArtifacts {
    if (!validDigest(source_digest)) return error.InvalidSourceDigest;
    const key = source_digest[7..];
    const definition_ref = try std.fmt.allocPrint(allocator, ".ztasks/sources/{s}/definition.json", .{key});
    errdefer allocator.free(definition_ref);
    const dependency_ref = try std.fmt.allocPrint(allocator, ".ztasks/sources/{s}/dependencies.json", .{key});
    defer allocator.free(dependency_ref);
    try writeImmutable(project, io, allocator, definition_ref, definition_json);
    try writeImmutable(project, io, allocator, dependency_ref, dependency_json);
    return .{
        .definition_ref = definition_ref,
        .definition_digest = digest(definition_json),
        .dependency_digest = digest(dependency_json),
    };
}

fn writeImmutable(project: std.Io.Dir, io: std.Io, allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    if (project.readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024))) |existing| {
        defer allocator.free(existing);
        if (!std.mem.eql(u8, existing, bytes)) return error.ArtifactConflict;
        return;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
    var atomic = try project.createFileAtomic(io, path, .{ .make_path = true, .replace = false });
    defer atomic.deinit(io);
    try atomic.file.writeStreamingAll(io, bytes);
    try atomic.file.sync(io);
    try atomic.replace(io);
}

fn validDigest(value: []const u8) bool {
    if (value.len != 71 or !std.mem.startsWith(u8, value, "sha256:")) return false;
    for (value[7..]) |character| if (!std.ascii.isHex(character)) return false;
    return true;
}

pub fn digest(bytes: []const u8) [71]u8 {
    var raw: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &raw, .{});
    const hex = std.fmt.bytesToHex(raw, .lower);
    var result: [71]u8 = undefined;
    @memcpy(result[0..7], "sha256:");
    @memcpy(result[7..], &hex);
    return result;
}

test "artifact digests are deterministic and source keys are verified" {
    try std.testing.expectEqualStrings(&digest("definition"), &digest("definition"));
    try std.testing.expect(validDigest("sha256:" ++ "a" ** 64));
    try std.testing.expect(!validDigest("sha256:short"));
}

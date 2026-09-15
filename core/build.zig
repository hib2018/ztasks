const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core_module = b.addModule("ztasks_core", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const library = b.addLibrary(.{
        .name = "ztasks_core",
        .root_module = core_module,
        .linkage = .static,
    });
    b.installArtifact(library);

    const executable = b.addExecutable(.{
        .name = "ztasks-core",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ztasks_core", .module = core_module },
            },
        }),
    });
    b.installArtifact(executable);

    const library_tests = b.addTest(.{ .root_module = core_module });
    const executable_tests = b.addTest(.{ .root_module = executable.root_module });
    const test_step = b.step("test", "Run all Zig core tests");
    test_step.dependOn(&b.addRunArtifact(library_tests).step);
    test_step.dependOn(&b.addRunArtifact(executable_tests).step);
}

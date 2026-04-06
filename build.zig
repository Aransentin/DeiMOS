const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // This exists as it contains a lot of sorting, which
    // comptime doesn't handle well
    const test_index_gen_exe = b.addExecutable(.{
        .name = "test_index_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_index_gen.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
        }),
    });
    const run_gen_exe = b.addRunArtifact(test_index_gen_exe);
    run_gen_exe.step.dependOn(&test_index_gen_exe.step);
    const test_indices_zig = run_gen_exe.addOutputFileArg("test_indices.zig");

    const deimos = b.addExecutable(.{
        .name = "deimos",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/deimos.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
        }),
    });
    deimos.root_module.addAnonymousImport("test_indices", .{ .root_source_file = test_indices_zig });
    b.installArtifact(deimos);

    const phobos = b.addExecutable(.{
        .name = "phobos",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/phobos.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
        }),
    });
    phobos.root_module.addAnonymousImport("test_indices", .{ .root_source_file = test_indices_zig });
    b.installArtifact(phobos);
}

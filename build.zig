const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zflagz", .{
        .root_source_file = b.path("zflagz.zig"),
        .target = target,
    });

    const example_git_commit_exe = b.addExecutable(.{
        .name = "git-commit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/git_commit.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zflagz", .module = mod },
            },
        }),
    });

    b.installArtifact(example_git_commit_exe);

    const run_example_git_commit_step = b.step("example_git-commit", "Run the example: git-commit");

    const run_example_git_commit_cmd = b.addRunArtifact(example_git_commit_exe);
    run_example_git_commit_step.dependOn(&run_example_git_commit_cmd.step);

    run_example_git_commit_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_example_git_commit_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

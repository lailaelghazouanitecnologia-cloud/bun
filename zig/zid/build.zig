const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============ ZID EXECUTABLE ============

    const exe = b.addExecutable(.{
        .name = "zid",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // ============ RUN ============

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run zid");
    run_step.dependOn(&run_cmd.step);

    // ============ TESTS ============

    const test_step = b.step("test", "Run all tests");

    // Main module tests (inline tests in src/)
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(main_tests).step);

    // Test files in test/
    const test_files = [_][]const u8{
        "test/cli_test.zig",
        "test/strings_test.zig",
        "test/capsules_test.zig",
        "test/patches_test.zig",
        "test/toolchain_test.zig",
        "test/update_test.zig",
        "test/misc_test.zig",
    };

    for (test_files) |test_file| {
        const t = b.addTest(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // ============ ZID MODULE ============

    // Export framework as module for transpiler projects
    _ = b.addModule("zid", .{
        .root_source_file = b.path("src/framework/framework.zig"),
    });

    // ============ FORMAT ============

    const fmt_step = b.step("fmt", "Format source code");
    const fmt = b.addFmt(.{
        .paths = &.{"src"},
    });
    fmt_step.dependOn(&fmt.step);
}

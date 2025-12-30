const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============ ZID MODULE ============

    // Export zid as a module (used by tests and external projects)
    const zid_mod = b.addModule("zid", .{
        .root_source_file = b.path("src/zid.zig"),
    });

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

    // Test files in test/ - add zid module dependency
    const test_files = [_][]const u8{
        // Existing tests
        "test/cli_test.zig",
        "test/strings_test.zig",
        "test/capsules_test.zig",
        "test/patches_test.zig",
        "test/toolchain_test.zig",
        "test/update_test.zig",
        "test/misc_test.zig",
        "test/apps_test.zig",
        "test/framework_test.zig",
        // Unit tests
        "test/unit/versions_test.zig",
        "test/unit/resolver_test.zig",
        "test/unit/template_test.zig",
        "test/unit/custom_toolchain_test.zig",
        "test/unit/api_test.zig",
    };

    for (test_files) |test_file| {
        const t = b.addTest(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });
        // Add zid module so tests can @import("zid")
        t.root_module.addImport("zid", zid_mod);
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // ============ FORMAT ============

    const fmt_step = b.step("fmt", "Format source code");
    const fmt = b.addFmt(.{
        .paths = &.{"src"},
    });
    fmt_step.dependOn(&fmt.step);
}

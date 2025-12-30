const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============ MAIN EXECUTABLE ============

    const exe = b.addExecutable(.{
        .name = "zid",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // ============ RUN COMMAND ============

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the zid CLI");
    run_step.dependOn(&run_cmd.step);

    // ============ TESTS ============

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // ============ FRAMEWORK MODULE ============

    // Export as a module for transpiler projects
    _ = b.addModule("zid", .{
        .root_source_file = b.path("src/framework/mod.zig"),
    });
}

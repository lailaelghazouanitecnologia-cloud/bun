//! Example: Working with environment and platform detection
//!
//! Demonstrates how to detect the environment and use
//! type-safe environment variables.
//!
//! Run with: zig build test -- --test-filter "example: environment"

const std = @import("std");
const zid = @import("zid");

test "example: detect platform and build triplet" {
    // Get platform information at compile time (zero cost)
    const platform = zid.Environment.getPlatform();
    const arch = zid.Environment.getArch();
    const triplet = zid.Environment.getTriplet();

    std.debug.print("\n", .{});
    std.debug.print("Platform: {s}\n", .{platform});
    std.debug.print("Architecture: {s}\n", .{arch});
    std.debug.print("Triplet: {s}\n", .{triplet});

    // Verify triplet format
    try std.testing.expect(std.mem.indexOf(u8, triplet, "-") != null);
    try std.testing.expect(std.mem.startsWith(u8, triplet, platform));
}

test "example: detect CI environment" {
    const is_ci = zid.env_var.isCI();
    const ci_name = zid.env_var.getCIName();

    std.debug.print("\n", .{});
    std.debug.print("Running in CI: {}\n", .{is_ci});
    if (ci_name) |name| {
        std.debug.print("CI System: {s}\n", .{name});
    }

    // In local development, CI should be false
    // (unless actually running in CI)
    if (!is_ci) {
        try std.testing.expect(ci_name == null);
    }
}

test "example: use type-safe environment variables" {
    // These are type-safe - they return the correct type
    const home = zid.env_var.HOME.get();
    const debug = zid.env_var.ZID_DEBUG.get();
    const timeout = zid.env_var.ZID_TIMEOUT.get();

    std.debug.print("\n", .{});
    if (home) |h| {
        std.debug.print("Home: {s}\n", .{h});
        try std.testing.expect(h.len > 0);
    }

    // debug is bool, not string
    std.debug.print("Debug mode: {}\n", .{debug orelse false});

    // timeout is u32 with default of 30
    std.debug.print("HTTP timeout: {} seconds\n", .{timeout orelse 30});
    try std.testing.expectEqual(@as(?u32, 30), timeout);
}

test "example: check feature flags" {
    // Compile-time flags (zero cost)
    const use_colors = zid.feature_flags.useColors();
    const show_progress = zid.feature_flags.showProgress();
    const is_verbose = zid.feature_flags.isVerbose();

    std.debug.print("\n", .{});
    std.debug.print("Use colors: {}\n", .{use_colors});
    std.debug.print("Show progress: {}\n", .{show_progress});
    std.debug.print("Verbose mode: {}\n", .{is_verbose});

    // In test mode, verbose should be false unless ZID_VERBOSE is set
    if (!zid.Environment.isDebug) {
        // Can't assert much here as it depends on environment
    }
}

test "example: detect special environments" {
    std.debug.print("\n", .{});

    // These detect special runtime environments
    if (zid.Environment.isDocker()) {
        std.debug.print("Running in Docker container\n", .{});
    }

    if (zid.Environment.isWSL()) {
        std.debug.print("Running in WSL\n", .{});
    }

    if (zid.Environment.isNixOS()) {
        std.debug.print("Running on NixOS\n", .{});
    }

    // At least one detection should work without crashing
    _ = zid.Environment.isDocker();
    _ = zid.Environment.isWSL();
    _ = zid.Environment.isNixOS();
}

test "example: parse OS and architecture from string" {
    // Useful when parsing download URLs or config files
    const os = zid.Environment.OperatingSystem.fromString("linux");
    const arch = zid.Environment.Architecture.fromString("x86_64");

    try std.testing.expectEqual(zid.Environment.OperatingSystem.linux, os.?);
    try std.testing.expectEqual(zid.Environment.Architecture.x86_64, arch.?);

    // Alternative names also work
    const os2 = zid.Environment.OperatingSystem.fromString("darwin");
    const arch2 = zid.Environment.Architecture.fromString("arm64");

    try std.testing.expectEqual(zid.Environment.OperatingSystem.darwin, os2.?);
    try std.testing.expectEqual(zid.Environment.Architecture.aarch64, arch2.?);

    // Invalid values return null
    try std.testing.expect(zid.Environment.OperatingSystem.fromString("invalid") == null);
}

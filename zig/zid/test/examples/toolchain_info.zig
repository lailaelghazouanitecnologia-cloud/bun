//! Example: Toolchain information and version parsing
//!
//! Demonstrates how to work with toolchain definitions,
//! version parsing, and constraints.
//!
//! Run with: zig build test -- --test-filter "example: toolchain"

const std = @import("std");
const zid = @import("zid");

const toolchain = zid.toolchain;
const versions = toolchain.versions;

test "example: list supported toolchains" {
    const supported = toolchain.supportedTools();

    std.debug.print("\n", .{});
    std.debug.print("Supported toolchains ({} total):\n", .{supported.len});

    for (supported) |tool| {
        const is_supported = toolchain.isSupported(tool.name);
        std.debug.print("  - {s} (supported: {})\n", .{ tool.name, is_supported });
        try std.testing.expect(is_supported);
    }

    // Unknown tools should not be supported
    try std.testing.expect(!toolchain.isSupported("unknown_tool_xyz"));
}

test "example: parse semantic versions" {
    // Standard semver
    const v1 = versions.Version.parse("1.2.3");
    try std.testing.expectEqual(@as(u32, 1), v1.ok.major);
    try std.testing.expectEqual(@as(u32, 2), v1.ok.minor);
    try std.testing.expectEqual(@as(u32, 3), v1.ok.patch);

    // With 'v' prefix (common in Git tags)
    const v2 = versions.Version.parse("v0.14.0");
    try std.testing.expectEqual(@as(u32, 0), v2.ok.major);
    try std.testing.expectEqual(@as(u32, 14), v2.ok.minor);

    // Two-part version
    const v3 = versions.Version.parse("1.0");
    try std.testing.expectEqual(@as(u32, 1), v3.ok.major);
    try std.testing.expectEqual(@as(u32, 0), v3.ok.minor);
    try std.testing.expectEqual(@as(u32, 0), v3.ok.patch);

    std.debug.print("\n", .{});
    std.debug.print("Parsed versions:\n", .{});
    std.debug.print("  1.2.3 → {}.{}.{}\n", .{ v1.ok.major, v1.ok.minor, v1.ok.patch });
    std.debug.print("  v0.14.0 → {}.{}.{}\n", .{ v2.ok.major, v2.ok.minor, v2.ok.patch });
    std.debug.print("  1.0 → {}.{}.{}\n", .{ v3.ok.major, v3.ok.minor, v3.ok.patch });
}

test "example: compare versions" {
    const v1_0_0 = versions.Version{ .major = 1, .minor = 0, .patch = 0 };
    const v1_2_0 = versions.Version{ .major = 1, .minor = 2, .patch = 0 };
    const v2_0_0 = versions.Version{ .major = 2, .minor = 0, .patch = 0 };

    // Comparison
    try std.testing.expect(v1_0_0.compare(v1_2_0) == .lt);
    try std.testing.expect(v1_2_0.compare(v1_0_0) == .gt);
    try std.testing.expect(v1_0_0.compare(v1_0_0) == .eq);
    try std.testing.expect(v2_0_0.compare(v1_2_0) == .gt);

    std.debug.print("\n", .{});
    std.debug.print("Version comparisons:\n", .{});
    std.debug.print("  1.0.0 < 1.2.0: {}\n", .{v1_0_0.compare(v1_2_0) == .lt});
    std.debug.print("  2.0.0 > 1.2.0: {}\n", .{v2_0_0.compare(v1_2_0) == .gt});
}

test "example: version constraints" {
    const v1_5_0 = versions.Version{ .major = 1, .minor = 5, .patch = 0 };

    // Exact match constraint
    const exact = versions.Constraint{
        .op = .eq,
        .version = versions.Version{ .major = 1, .minor = 5, .patch = 0 },
    };
    try std.testing.expect(exact.satisfies(v1_5_0));

    // Greater than or equal
    const gte = versions.Constraint{
        .op = .gte,
        .version = versions.Version{ .major = 1, .minor = 0, .patch = 0 },
    };
    try std.testing.expect(gte.satisfies(v1_5_0));

    // Less than
    const lt = versions.Constraint{
        .op = .lt,
        .version = versions.Version{ .major = 2, .minor = 0, .patch = 0 },
    };
    try std.testing.expect(lt.satisfies(v1_5_0));

    std.debug.print("\n", .{});
    std.debug.print("Constraint checks for 1.5.0:\n", .{});
    std.debug.print("  == 1.5.0: {}\n", .{exact.satisfies(v1_5_0)});
    std.debug.print("  >= 1.0.0: {}\n", .{gte.satisfies(v1_5_0)});
    std.debug.print("  < 2.0.0: {}\n", .{lt.satisfies(v1_5_0)});
}

test "example: get toolchain registry info" {
    // Get info about a known toolchain
    const registry = toolchain.registry;

    // registry.get() returns a non-optional pointer for known tools
    const bun_info = registry.get(.bun);
    std.debug.print("\n", .{});
    std.debug.print("Bun toolchain info:\n", .{});
    std.debug.print("  Name: {s}\n", .{bun_info.name});
    std.debug.print("  Binary: {s}\n", .{bun_info.binary});
    std.debug.print("  Archive format: {s}\n", .{@tagName(bun_info.archive)});

    try std.testing.expectEqualStrings("bun", bun_info.name);
    try std.testing.expectEqualStrings("bun", bun_info.binary);

    const zig_info = registry.get(.zig);
    std.debug.print("\n", .{});
    std.debug.print("Zig toolchain info:\n", .{});
    std.debug.print("  Name: {s}\n", .{zig_info.name});
    std.debug.print("  Binary: {s}\n", .{zig_info.binary});
    std.debug.print("  Archive format: {s}\n", .{@tagName(zig_info.archive)});

    try std.testing.expectEqualStrings("zig", zig_info.name);
    try std.testing.expectEqualStrings("zig", zig_info.binary);
}

test "example: format version for display" {
    const version = versions.Version{ .major = 1, .minor = 2, .patch = 3 };

    var buf: [32]u8 = undefined;
    const formatted = version.format(&buf);

    try std.testing.expectEqualStrings("1.2.3", formatted);
    std.debug.print("\nFormatted version: {s}\n", .{formatted});
}

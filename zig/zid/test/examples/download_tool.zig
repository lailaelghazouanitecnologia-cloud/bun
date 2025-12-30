//! Example: Download a tool with progress
//!
//! Demonstrates how to use the HTTP client to download
//! a file with progress reporting.
//!
//! Run with: zig build test -- --test-filter "example: download"

const std = @import("std");
const zid = @import("zid");

/// Progress callback that prints a progress bar
fn printProgress(current: u64, total: u64, _: ?*anyopaque) void {
    if (total == 0) return;

    const percent = @as(u8, @intCast(@min(100, (current * 100) / total)));
    const bar_width: usize = 40;
    const filled = (percent * bar_width) / 100;

    std.debug.print("\r[", .{});
    for (0..bar_width) |i| {
        if (i < filled) {
            std.debug.print("=", .{});
        } else if (i == filled) {
            std.debug.print(">", .{});
        } else {
            std.debug.print(" ", .{});
        }
    }

    const current_mb = @as(f64, @floatFromInt(current)) / (1024 * 1024);
    const total_mb = @as(f64, @floatFromInt(total)) / (1024 * 1024);
    std.debug.print("] {d}% ({d:.1} / {d:.1} MB)", .{ percent, current_mb, total_mb });
}

test "example: download with progress bar" {
    // This is a demonstration - the URL doesn't exist
    // In real use, you would download an actual file

    var progress = zid.http.Progress{
        .total = 1000,
        .current = 0,
        .callback = printProgress,
    };

    // Simulate progress updates
    progress.update(250);
    try std.testing.expectEqual(@as(u8, 25), progress.percent());

    progress.update(250);
    try std.testing.expectEqual(@as(u8, 50), progress.percent());

    progress.update(500);
    try std.testing.expectEqual(@as(u8, 100), progress.percent());
}

test "example: parse GitHub release URL" {
    // Example: Parse a GitHub releases URL
    const url = "https://github.com/example/tool/releases/download/v1.0.0/tool-linux-x64.tar.gz";

    const parsed = zid.http.Url.parse(url);
    try std.testing.expect(parsed != null);
    try std.testing.expectEqualStrings("github.com", parsed.?.host);
    try std.testing.expect(parsed.?.isHttps());
}

test "example: build download URL for platform" {
    // Build a platform-specific download URL
    const base = "https://example.com/releases/v1.0.0/tool";
    const platform = zid.Environment.getPlatform();
    const arch = zid.Environment.getArch();

    var buf: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&buf, "{s}-{s}-{s}.tar.gz", .{ base, platform, arch }) catch unreachable;

    // Verify it contains platform info
    try std.testing.expect(std.mem.indexOf(u8, url, platform) != null);
    try std.testing.expect(std.mem.indexOf(u8, url, arch) != null);
}

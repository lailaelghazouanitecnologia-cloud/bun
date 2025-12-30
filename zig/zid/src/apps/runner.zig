const std = @import("std");
const registry = @import("registry.zig");

/// App Runner
/// Executes registered apps with proper environment setup.

pub fn run(alloc: std.mem.Allocator, name: []const u8, args: []const []const u8) !void {
    const app = try registry.get(alloc, name) orelse {
        std.debug.print("App not found: {s}\n", .{name});
        std.debug.print("Use 'zid add' to register an app.\n", .{});
        return error.AppNotFound;
    };

    // Build argv
    var argv = std.ArrayList([]const u8).init(alloc);
    try argv.append(app.path);
    try argv.appendSlice(args);

    // Setup environment with Zid toolchain paths
    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    // Add ~/.zid/bin to PATH
    if (env_map.get("PATH")) |path| {
        const zid_home = try getZidHome(alloc);
        defer alloc.free(zid_home);

        const new_path = try std.fmt.allocPrint(alloc, "{s}/bin:{s}", .{ zid_home, path });
        defer alloc.free(new_path);

        try env_map.put("PATH", new_path);
    }

    // Spawn the process
    var child = std.process.Child.init(argv.items, alloc);
    child.env_map = &env_map;

    // Inherit stdio
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    _ = try child.spawnAndWait();
}

fn getZidHome(alloc: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("ZID_HOME")) |home| {
        return alloc.dupe(u8, home);
    }

    const home = std.posix.getenv("HOME") orelse "/tmp";
    return std.fmt.allocPrint(alloc, "{s}/.zid", .{home});
}

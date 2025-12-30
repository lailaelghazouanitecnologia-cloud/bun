const std = @import("std");

/// Toolchain Registry
/// Tracks installed tools and their versions.
/// Stores data in ~/.zid/toolchain/

pub const available_tools = [_][]const u8{
    "zig",
    "rust",
    "bun",
    "node",
    "go",
    "python",
    "deno",
};

const Entry = struct {
    tool: []const u8,
    version: []const u8,
    path: []const u8,
    active: bool,
};

/// Get Zid home directory
pub fn getZidHome(alloc: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("ZID_HOME")) |home| {
        return alloc.dupe(u8, home);
    }

    const home = std.posix.getenv("HOME") orelse "/tmp";
    return std.fmt.allocPrint(alloc, "{s}/.zid", .{home});
}

/// Get toolchain directory
pub fn getToolchainDir(alloc: std.mem.Allocator) ![]const u8 {
    const zid_home = try getZidHome(alloc);
    defer alloc.free(zid_home);
    return std.fmt.allocPrint(alloc, "{s}/toolchain", .{zid_home});
}

/// Get install path for a tool version
pub fn getInstallPath(alloc: std.mem.Allocator, tool: []const u8, version: []const u8) ![]const u8 {
    const toolchain_dir = try getToolchainDir(alloc);
    defer alloc.free(toolchain_dir);
    return std.fmt.allocPrint(alloc, "{s}/{s}/{s}", .{ toolchain_dir, tool, version });
}

/// Check if a specific version is installed
pub fn isInstalled(alloc: std.mem.Allocator, tool: []const u8, version: []const u8) !bool {
    const path = try getInstallPath(alloc, tool, version);
    defer alloc.free(path);

    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

/// Check if any version of tool is installed
pub fn hasAnyVersion(alloc: std.mem.Allocator, tool: []const u8) !bool {
    const versions = try listVersions(alloc, tool);
    return versions.len > 0;
}

/// List installed versions of a tool
pub fn listVersions(alloc: std.mem.Allocator, tool: []const u8) ![]const []const u8 {
    const toolchain_dir = try getToolchainDir(alloc);
    defer alloc.free(toolchain_dir);

    const tool_dir = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ toolchain_dir, tool });
    defer alloc.free(tool_dir);

    var dir = std.fs.openDirAbsolute(tool_dir, .{ .iterate = true }) catch {
        return &[_][]const u8{};
    };
    defer dir.close();

    var versions = std.ArrayList([]const u8).init(alloc);
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            try versions.append(try alloc.dupe(u8, entry.name));
        }
    }

    return versions.toOwnedSlice();
}

/// List all installed tools
pub fn listInstalled(alloc: std.mem.Allocator) ![]const @import("mod.zig").Tool {
    var tools = std.ArrayList(@import("mod.zig").Tool).init(alloc);

    for (available_tools) |tool_name| {
        const versions = try listVersions(alloc, tool_name);
        const active = try getActiveVersion(alloc, tool_name);

        for (versions) |version| {
            const path = try getInstallPath(alloc, tool_name, version);
            const is_active = if (active) |a| std.mem.eql(u8, a, version) else false;

            try tools.append(.{
                .name = tool_name,
                .version = version,
                .path = path,
                .active = is_active,
            });
        }
    }

    return tools.toOwnedSlice();
}

/// Register a newly installed tool
pub fn register(alloc: std.mem.Allocator, tool: []const u8, version: []const u8, path: []const u8) !void {
    _ = alloc;
    _ = tool;
    _ = version;
    _ = path;
    // TODO: Write to registry file
}

/// Unregister a tool
pub fn unregister(alloc: std.mem.Allocator, tool: []const u8, version: []const u8) !void {
    _ = alloc;
    _ = tool;
    _ = version;
    // TODO: Remove from registry file
}

/// Get active version of a tool
pub fn getActiveVersion(alloc: std.mem.Allocator, tool: []const u8) !?[]const u8 {
    const zid_home = try getZidHome(alloc);
    defer alloc.free(zid_home);

    const active_file = try std.fmt.allocPrint(alloc, "{s}/toolchain/{s}/active", .{ zid_home, tool });
    defer alloc.free(active_file);

    const file = std.fs.openFileAbsolute(active_file, .{}) catch return null;
    defer file.close();

    return file.readToEndAlloc(alloc, 256) catch null;
}

/// Set active version of a tool
pub fn setActive(alloc: std.mem.Allocator, tool: []const u8, version: []const u8) !void {
    // Verify version is installed
    if (!try isInstalled(alloc, tool, version)) {
        std.debug.print("{s}@{s} is not installed.\n", .{ tool, version });
        return error.NotInstalled;
    }

    const zid_home = try getZidHome(alloc);
    defer alloc.free(zid_home);

    // Ensure directory exists
    const tool_dir = try std.fmt.allocPrint(alloc, "{s}/toolchain/{s}", .{ zid_home, tool });
    defer alloc.free(tool_dir);

    std.fs.makeDirAbsolute(tool_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Write active version
    const active_file = try std.fmt.allocPrint(alloc, "{s}/active", .{tool_dir});
    defer alloc.free(active_file);

    const file = try std.fs.createFileAbsolute(active_file, .{});
    defer file.close();
    try file.writeAll(version);

    // Update symlink in bin/
    try updateBinSymlink(alloc, tool, version);

    std.debug.print("Now using {s}@{s}\n", .{ tool, version });
}

/// Get path to active tool binary
pub fn getActivePath(alloc: std.mem.Allocator, tool: []const u8) !?[]const u8 {
    const version = try getActiveVersion(alloc, tool) orelse return null;
    defer alloc.free(version);

    const install_path = try getInstallPath(alloc, tool, version);
    defer alloc.free(install_path);

    // Return binary path
    return std.fmt.allocPrint(alloc, "{s}/bin/{s}", .{ install_path, tool });
}

fn updateBinSymlink(alloc: std.mem.Allocator, tool: []const u8, version: []const u8) !void {
    const zid_home = try getZidHome(alloc);
    defer alloc.free(zid_home);

    const bin_dir = try std.fmt.allocPrint(alloc, "{s}/bin", .{zid_home});
    defer alloc.free(bin_dir);

    // Ensure bin directory exists
    std.fs.makeDirAbsolute(bin_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const symlink_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ bin_dir, tool });
    defer alloc.free(symlink_path);

    const target_path = try getInstallPath(alloc, tool, version);
    defer alloc.free(target_path);

    const binary_path = try std.fmt.allocPrint(alloc, "{s}/bin/{s}", .{ target_path, tool });
    defer alloc.free(binary_path);

    // Remove existing symlink
    std.fs.deleteFileAbsolute(symlink_path) catch {};

    // Create new symlink
    std.fs.symLinkAbsolute(binary_path, symlink_path, .{}) catch |err| {
        std.debug.print("Failed to create symlink: {}\n", .{err});
    };
}

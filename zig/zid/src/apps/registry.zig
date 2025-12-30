const std = @import("std");
const mod = @import("mod.zig");

/// Apps Registry
/// Stores registered apps in ~/.zid/apps/registry.json

const Registry = struct {
    apps: []mod.App,
};

/// Get Zid home directory
fn getZidHome(alloc: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("ZID_HOME")) |home| {
        return alloc.dupe(u8, home);
    }

    const home = std.posix.getenv("HOME") orelse "/tmp";
    return std.fmt.allocPrint(alloc, "{s}/.zid", .{home});
}

/// Get apps directory
pub fn getAppsDir(alloc: std.mem.Allocator) ![]const u8 {
    const zid_home = try getZidHome(alloc);
    defer alloc.free(zid_home);
    return std.fmt.allocPrint(alloc, "{s}/apps", .{zid_home});
}

/// Get registry file path
fn getRegistryPath(alloc: std.mem.Allocator) ![]const u8 {
    const apps_dir = try getAppsDir(alloc);
    defer alloc.free(apps_dir);
    return std.fmt.allocPrint(alloc, "{s}/registry.json", .{apps_dir});
}

/// Check if an app exists
pub fn exists(alloc: std.mem.Allocator, name: []const u8) !bool {
    const apps = try list(alloc);
    for (apps) |app| {
        if (std.mem.eql(u8, app.name, name)) return true;
    }
    return false;
}

/// Get an app by name
pub fn get(alloc: std.mem.Allocator, name: []const u8) !?mod.App {
    const apps = try list(alloc);
    for (apps) |app| {
        if (std.mem.eql(u8, app.name, name)) return app;
    }
    return null;
}

/// List all registered apps
pub fn list(alloc: std.mem.Allocator) ![]mod.App {
    const registry_path = try getRegistryPath(alloc);
    defer alloc.free(registry_path);

    const file = std.fs.openFileAbsolute(registry_path, .{}) catch {
        return &[_]mod.App{};
    };
    defer file.close();

    const content = try file.readToEndAlloc(alloc, 1024 * 1024);
    defer alloc.free(content);

    const parsed = std.json.parseFromSlice(Registry, alloc, content, .{}) catch {
        return &[_]mod.App{};
    };

    return parsed.value.apps;
}

/// Register an app
pub fn register(alloc: std.mem.Allocator, app: mod.App) !void {
    // Ensure directories exist
    const apps_dir = try getAppsDir(alloc);
    defer alloc.free(apps_dir);

    std.fs.makeDirAbsolute(apps_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Load existing registry
    var apps = std.ArrayList(mod.App).init(alloc);
    const existing = try list(alloc);
    try apps.appendSlice(existing);

    // Remove if already exists
    var i: usize = 0;
    while (i < apps.items.len) {
        if (std.mem.eql(u8, apps.items[i].name, app.name)) {
            _ = apps.orderedRemove(i);
        } else {
            i += 1;
        }
    }

    // Add new app
    try apps.append(app);

    // Save registry
    try save(alloc, apps.items);

    // Create symlink in bin/
    try createSymlink(alloc, app);
}

/// Remove an app
pub fn remove(alloc: std.mem.Allocator, name: []const u8) !void {
    var apps = std.ArrayList(mod.App).init(alloc);
    const existing = try list(alloc);
    try apps.appendSlice(existing);

    // Find and remove
    var i: usize = 0;
    while (i < apps.items.len) {
        if (std.mem.eql(u8, apps.items[i].name, name)) {
            _ = apps.orderedRemove(i);
            break;
        }
        i += 1;
    }

    // Save registry
    try save(alloc, apps.items);

    // Remove symlink
    try removeSymlink(alloc, name);
}

fn save(alloc: std.mem.Allocator, apps: []mod.App) !void {
    const registry_path = try getRegistryPath(alloc);
    defer alloc.free(registry_path);

    const file = try std.fs.createFileAbsolute(registry_path, .{});
    defer file.close();

    try std.json.stringify(Registry{ .apps = apps }, .{ .whitespace = .indent_2 }, file.writer());
}

fn createSymlink(alloc: std.mem.Allocator, app: mod.App) !void {
    const zid_home = try getZidHome(alloc);
    defer alloc.free(zid_home);

    const bin_dir = try std.fmt.allocPrint(alloc, "{s}/bin", .{zid_home});
    defer alloc.free(bin_dir);

    // Ensure bin directory exists
    std.fs.makeDirAbsolute(bin_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const symlink_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ bin_dir, app.name });
    defer alloc.free(symlink_path);

    // Remove existing symlink
    std.fs.deleteFileAbsolute(symlink_path) catch {};

    // Create new symlink
    std.fs.symLinkAbsolute(app.path, symlink_path, .{}) catch |err| {
        std.debug.print("Failed to create symlink: {}\n", .{err});
    };
}

fn removeSymlink(alloc: std.mem.Allocator, name: []const u8) !void {
    const zid_home = try getZidHome(alloc);
    defer alloc.free(zid_home);

    const symlink_path = try std.fmt.allocPrint(alloc, "{s}/bin/{s}", .{ zid_home, name });
    defer alloc.free(symlink_path);

    std.fs.deleteFileAbsolute(symlink_path) catch {};
}

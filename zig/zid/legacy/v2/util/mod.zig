const std = @import("std");

/// Utility functions for Zid

/// Get Zid home directory (~/.zid)
pub fn getZidHome(alloc: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("ZID_HOME")) |home| {
        return alloc.dupe(u8, home);
    }

    const home = std.posix.getenv("HOME") orelse "/tmp";
    return std.fmt.allocPrint(alloc, "{s}/.zid", .{home});
}

/// Ensure Zid directories exist
pub fn ensureZidDirs(alloc: std.mem.Allocator) !void {
    const zid_home = try getZidHome(alloc);
    defer alloc.free(zid_home);

    const dirs = [_][]const u8{
        "",          // ~/.zid
        "/bin",      // ~/.zid/bin
        "/toolchain", // ~/.zid/toolchain
        "/apps",     // ~/.zid/apps
        "/cache",    // ~/.zid/cache
    };

    for (dirs) |dir| {
        const path = try std.fmt.allocPrint(alloc, "{s}{s}", .{ zid_home, dir });
        defer alloc.free(path);

        std.fs.makeDirAbsolute(path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

/// Simple glob pattern matching
pub fn glob(alloc: std.mem.Allocator, pattern: []const u8) ![]const []const u8 {
    var results = std.ArrayList([]const u8).init(alloc);

    // Extract directory and pattern parts
    var dir_path: []const u8 = ".";
    var file_pattern: []const u8 = pattern;

    if (std.mem.lastIndexOf(u8, pattern, "/")) |idx| {
        dir_path = pattern[0..idx];
        file_pattern = pattern[idx + 1 ..];
    }

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch {
        return results.toOwnedSlice();
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and matchPattern(entry.name, file_pattern)) {
            const full_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dir_path, entry.name });
            try results.append(full_path);
        }
    }

    return results.toOwnedSlice();
}

/// Simple wildcard pattern matching
fn matchPattern(name: []const u8, pattern: []const u8) bool {
    // Handle simple wildcards
    if (std.mem.eql(u8, pattern, "*")) return true;

    if (std.mem.startsWith(u8, pattern, "*.")) {
        const ext = pattern[1..];
        return std.mem.endsWith(u8, name, ext);
    }

    if (std.mem.endsWith(u8, pattern, ".*")) {
        const prefix = pattern[0 .. pattern.len - 2];
        return std.mem.startsWith(u8, name, prefix);
    }

    return std.mem.eql(u8, name, pattern);
}

/// Read file contents
pub fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(alloc, 10 * 1024 * 1024);
}

/// Write file contents
pub fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Get file extension
pub fn getExtension(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

/// Change file extension
pub fn changeExtension(alloc: std.mem.Allocator, path: []const u8, new_ext: []const u8) ![]const u8 {
    const stem = std.fs.path.stem(path);
    return std.fmt.allocPrint(alloc, "{s}{s}", .{ stem, new_ext });
}

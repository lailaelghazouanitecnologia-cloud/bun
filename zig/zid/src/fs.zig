//! File System utilities
//!
//! Cross-platform file operations with proper error handling.

const std = @import("std");
const Environment = @import("env.zig");
const Output = @import("output.zig");

const log = Output.scoped(.FS);

// ============ FILE OPERATIONS ============

/// Read entire file contents
pub fn readFile(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(alloc, std.math.maxInt(usize));
}

/// Read file as string with null terminator
pub fn readFileZ(alloc: std.mem.Allocator, path: []const u8) ![:0]u8 {
    const content = try readFile(alloc, path);
    const result = try alloc.allocSentinel(u8, content.len, 0);
    @memcpy(result, content);
    alloc.free(content);
    return result;
}

/// Write content to file
pub fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Append content to file
pub fn appendFile(path: []const u8, content: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .write_only });
    defer file.close();
    try file.seekFromEnd(0);
    try file.writeAll(content);
}

/// Check if file exists
pub fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Check if path is a directory
pub fn isDir(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Check if path is a file
pub fn isFile(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

/// Get file size
pub fn fileSize(path: []const u8) !u64 {
    const stat = try std.fs.cwd().statFile(path);
    return stat.size;
}

/// Get file modification time
pub fn modTime(path: []const u8) !i128 {
    const stat = try std.fs.cwd().statFile(path);
    return stat.mtime;
}

/// Delete file
pub fn deleteFile(path: []const u8) !void {
    try std.fs.cwd().deleteFile(path);
}

/// Delete directory (must be empty)
pub fn deleteDir(path: []const u8) !void {
    try std.fs.cwd().deleteDir(path);
}

/// Delete directory tree recursively
pub fn deleteTree(path: []const u8) !void {
    std.fs.cwd().deleteTree(path) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
}

/// Copy file
pub fn copyFile(src: []const u8, dest: []const u8) !void {
    try std.fs.cwd().copyFile(src, std.fs.cwd(), dest, .{});
}

/// Rename/move file
pub fn rename(old: []const u8, new: []const u8) !void {
    try std.fs.cwd().rename(old, new);
}

// ============ DIRECTORY OPERATIONS ============

/// Create directory
pub fn mkdir(path: []const u8) !void {
    std.fs.cwd().makeDir(path) catch |err| {
        if (err == error.PathAlreadyExists) return;
        return err;
    };
}

/// Create directory and all parents
pub fn mkdirAll(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| {
        if (err == error.PathAlreadyExists) return;
        return err;
    };
}

/// List directory contents
pub fn readDir(alloc: std.mem.Allocator, path: []const u8) ![]Entry {
    var entries = std.ArrayList(Entry).init(alloc);

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try entries.append(.{
            .name = try alloc.dupe(u8, entry.name),
            .kind = entry.kind,
        });
    }

    return entries.toOwnedSlice();
}

pub const Entry = struct {
    name: []const u8,
    kind: std.fs.Dir.Entry.Kind,

    pub fn isDir(self: Entry) bool {
        return self.kind == .directory;
    }

    pub fn isFile(self: Entry) bool {
        return self.kind == .file;
    }

    pub fn isSymlink(self: Entry) bool {
        return self.kind == .sym_link;
    }
};

// ============ PATH OPERATIONS ============

/// Join path components
pub fn join(alloc: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    return std.fs.path.join(alloc, paths);
}

/// Get directory name
pub fn dirname(path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse ".";
}

/// Get base name
pub fn basename(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

/// Get file extension
pub fn extension(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

/// Get file stem (name without extension)
pub fn stem(path: []const u8) []const u8 {
    return std.fs.path.stem(path);
}

/// Resolve to absolute path
pub fn realpath(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().realpathAlloc(alloc, path);
}

/// Normalize path (remove . and ..)
pub fn normalize(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    var components = std.ArrayList([]const u8).init(alloc);
    defer components.deinit();

    var iter = std.mem.splitScalar(u8, path, Environment.pathSeparator);
    while (iter.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (components.items.len > 0) {
                _ = components.pop();
            }
        } else {
            try components.append(part);
        }
    }

    return join(alloc, components.items);
}

/// Check if path is absolute
pub fn isAbsolute(path: []const u8) bool {
    return std.fs.path.isAbsolute(path);
}

/// Make path relative to base
pub fn relative(alloc: std.mem.Allocator, base: []const u8, target: []const u8) ![]u8 {
    // Simple implementation - could be improved
    if (std.mem.startsWith(u8, target, base)) {
        var result = target[base.len..];
        if (result.len > 0 and result[0] == Environment.pathSeparator) {
            result = result[1..];
        }
        return alloc.dupe(u8, result);
    }
    return alloc.dupe(u8, target);
}

// ============ GLOB ============

/// Simple glob pattern matching
pub fn glob(alloc: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
    var results = std.ArrayList([]const u8).init(alloc);

    // Extract directory and file pattern
    const dir_path = dirname(pattern);
    const file_pattern = basename(pattern);

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch {
        return results.toOwnedSlice();
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (matchGlob(entry.name, file_pattern)) {
            const full_path = try join(alloc, &.{ dir_path, entry.name });
            try results.append(full_path);
        }
    }

    return results.toOwnedSlice();
}

fn matchGlob(name: []const u8, pattern: []const u8) bool {
    // Handle * wildcard
    if (std.mem.eql(u8, pattern, "*")) return true;

    if (std.mem.startsWith(u8, pattern, "*.")) {
        const ext = pattern[1..];
        return std.mem.endsWith(u8, name, ext);
    }

    if (std.mem.endsWith(u8, pattern, ".*")) {
        const prefix = pattern[0 .. pattern.len - 2];
        return std.mem.startsWith(u8, name, prefix);
    }

    // Check for * in middle
    if (std.mem.indexOf(u8, pattern, "*")) |star_idx| {
        const prefix = pattern[0..star_idx];
        const suffix = pattern[star_idx + 1 ..];

        return std.mem.startsWith(u8, name, prefix) and
            std.mem.endsWith(u8, name, suffix);
    }

    return std.mem.eql(u8, name, pattern);
}

// ============ SYMLINKS ============

/// Create symlink
pub fn symlink(target: []const u8, link_path: []const u8) !void {
    std.fs.cwd().symLink(target, link_path, .{}) catch |err| {
        // On Windows, try directory symlink
        if (Environment.isWindows and err == error.AccessDenied) {
            try std.fs.cwd().symLink(target, link_path, .{ .is_directory = true });
            return;
        }
        return err;
    };
}

/// Read symlink target
pub fn readLink(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readLink(path, &.{}) catch |err| {
        _ = err;
        // Use threadlocal buffer
        var buf: [4096]u8 = undefined;
        const link = try std.fs.cwd().readLink(path, &buf);
        return alloc.dupe(u8, link);
    };
}

// ============ TEMP ============

/// Get temp directory
pub fn tempDir() []const u8 {
    if (Environment.isWindows) {
        return std.posix.getenv("TEMP") orelse
            std.posix.getenv("TMP") orelse
            "C:\\Windows\\Temp";
    }
    return std.posix.getenv("TMPDIR") orelse "/tmp";
}

/// Create temp file
pub fn tempFile(alloc: std.mem.Allocator, prefix: []const u8) !struct { path: []u8, file: std.fs.File } {
    const tmp = tempDir();
    const random = std.crypto.random.int(u64);
    const name = try std.fmt.allocPrint(alloc, "{s}/{s}-{x}", .{ tmp, prefix, random });

    const file = try std.fs.cwd().createFile(name, .{});
    return .{ .path = name, .file = file };
}

// ============ TESTS ============

test "exists" {
    try std.testing.expect(exists("/"));
    try std.testing.expect(!exists("/nonexistent-path-12345"));
}

test "matchGlob" {
    try std.testing.expect(matchGlob("file.txt", "*.txt"));
    try std.testing.expect(matchGlob("file.txt", "*"));
    try std.testing.expect(!matchGlob("file.txt", "*.md"));
}

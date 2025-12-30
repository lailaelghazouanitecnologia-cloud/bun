//! Search API
//!
//! Búsqueda de archivos y contenido.
//!
//! ```zig
//! const zid = @import("zid");
//!
//! // Glob patterns
//! const files = try zid.search.glob("**/*.ts");
//! const configs = try zid.search.glob("**/package.json");
//!
//! // Grep en archivos
//! const matches = try zid.search.grep("src/", "TODO");
//! for (matches) |m| {
//!     print("{s}:{d}: {s}\n", .{m.file, m.line, m.text});
//! }
//!
//! // Find files
//! const large = try zid.search.find(".", .{ .min_size = 1024 * 1024 });
//! ```

const std = @import("std");

// ============ GLOB ============

/// Find files matching glob pattern
pub fn glob(allocator: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
    return globIn(allocator, ".", pattern);
}

/// Find files matching glob pattern in directory
pub fn globIn(allocator: std.mem.Allocator, base: []const u8, pattern: []const u8) ![][]const u8 {
    var results = std.ArrayList([]const u8).init(allocator);

    // Parse pattern
    const is_recursive = std.mem.indexOf(u8, pattern, "**") != null;
    const ext = getPatternExt(pattern);

    try walkDir(allocator, base, ext, is_recursive, &results);

    return results.toOwnedSlice();
}

fn getPatternExt(pattern: []const u8) ?[]const u8 {
    // Extract extension from patterns like "**/*.ts" or "*.js"
    if (std.mem.lastIndexOf(u8, pattern, "*.")) |pos| {
        return pattern[pos + 1 ..];
    }
    return null;
}

fn walkDir(
    allocator: std.mem.Allocator,
    path: []const u8,
    ext: ?[]const u8,
    recursive: bool,
    results: *std.ArrayList([]const u8),
) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ path, entry.name }) catch continue;

        if (entry.kind == .directory) {
            if (recursive and !std.mem.startsWith(u8, entry.name, ".")) {
                try walkDir(allocator, full_path, ext, recursive, results);
            }
        } else if (entry.kind == .file) {
            // Check extension
            if (ext) |e| {
                const file_ext = std.fs.path.extension(entry.name);
                if (!std.mem.eql(u8, file_ext, e)) continue;
            }
            try results.append(try allocator.dupe(u8, full_path));
        }
    }
}

// ============ GREP ============

/// Search for pattern in files
pub fn grep(allocator: std.mem.Allocator, path: []const u8, pattern: []const u8) ![]Match {
    var matches = std.ArrayList(Match).init(allocator);

    const stat = std.fs.cwd().statFile(path) catch return matches.toOwnedSlice();

    if (stat.kind == .directory) {
        try grepDir(allocator, path, pattern, &matches);
    } else {
        try grepFile(allocator, path, pattern, &matches);
    }

    return matches.toOwnedSlice();
}

fn grepDir(
    allocator: std.mem.Allocator,
    path: []const u8,
    pattern: []const u8,
    matches: *std.ArrayList(Match),
) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) continue;

        var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ path, entry.name }) catch continue;

        if (entry.kind == .directory) {
            try grepDir(allocator, full_path, pattern, matches);
        } else if (entry.kind == .file) {
            try grepFile(allocator, full_path, pattern, matches);
        }
    }
}

fn grepFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    pattern: []const u8,
    matches: *std.ArrayList(Match),
) !void {
    const content = std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024) catch return;
    defer allocator.free(content);

    var line_num: u32 = 1;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, pattern) != null) {
            try matches.append(.{
                .file = try allocator.dupe(u8, path),
                .line = line_num,
                .column = @intCast(std.mem.indexOf(u8, line, pattern).? + 1),
                .text = try allocator.dupe(u8, line),
            });
        }
        line_num += 1;
    }
}

pub const Match = struct {
    file: []const u8,
    line: u32,
    column: u32,
    text: []const u8,
};

// ============ FIND ============

/// Find files with options
pub fn find(allocator: std.mem.Allocator, path: []const u8, opts: FindOptions) ![][]const u8 {
    var results = std.ArrayList([]const u8).init(allocator);
    try findWalk(allocator, path, opts, &results);
    return results.toOwnedSlice();
}

pub const FindOptions = struct {
    /// File extension filter
    ext: ?[]const u8 = null,
    /// Minimum file size
    min_size: ?u64 = null,
    /// Maximum file size
    max_size: ?u64 = null,
    /// Name contains
    name_contains: ?[]const u8 = null,
    /// Only files
    files_only: bool = false,
    /// Only directories
    dirs_only: bool = false,
    /// Max depth
    max_depth: ?u32 = null,
};

fn findWalk(
    allocator: std.mem.Allocator,
    path: []const u8,
    opts: FindOptions,
    results: *std.ArrayList([]const u8),
) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) continue;

        var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ path, entry.name }) catch continue;

        const is_dir = entry.kind == .directory;
        const is_file = entry.kind == .file;

        // Apply filters
        var matches = true;

        if (opts.files_only and !is_file) matches = false;
        if (opts.dirs_only and !is_dir) matches = false;

        if (opts.ext) |ext| {
            if (!std.mem.endsWith(u8, entry.name, ext)) matches = false;
        }

        if (opts.name_contains) |needle| {
            if (std.mem.indexOf(u8, entry.name, needle) == null) matches = false;
        }

        if (is_file and (opts.min_size != null or opts.max_size != null)) {
            const stat = dir.statFile(entry.name) catch continue;
            if (opts.min_size) |min| {
                if (stat.size < min) matches = false;
            }
            if (opts.max_size) |max| {
                if (stat.size > max) matches = false;
            }
        }

        if (matches) {
            try results.append(try allocator.dupe(u8, full_path));
        }

        // Recurse into directories
        if (is_dir) {
            try findWalk(allocator, full_path, opts, results);
        }
    }
}

// ============ REPLACE ============

/// Replace text in file
pub fn replace(allocator: std.mem.Allocator, path: []const u8, old: []const u8, new: []const u8) !u32 {
    const content = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    defer allocator.free(content);

    var count: u32 = 0;
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var i: usize = 0;
    while (i < content.len) {
        if (i + old.len <= content.len and std.mem.eql(u8, content[i .. i + old.len], old)) {
            try result.appendSlice(new);
            i += old.len;
            count += 1;
        } else {
            try result.append(content[i]);
            i += 1;
        }
    }

    if (count > 0) {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(result.items);
    }

    return count;
}

/// Replace in multiple files
pub fn replaceAll(
    allocator: std.mem.Allocator,
    files: []const []const u8,
    old: []const u8,
    new: []const u8,
) !u32 {
    var total: u32 = 0;
    for (files) |file| {
        total += replace(allocator, file, old, new) catch 0;
    }
    return total;
}

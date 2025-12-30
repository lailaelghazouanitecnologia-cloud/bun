//! Filesystem API
//!
//! Operaciones de filesystem potentes y seguras.
//!
//! ```zig
//! const zid = @import("zid");
//!
//! // Leer/escribir
//! const data = try zid.fs.read("file.txt");
//! try zid.fs.write("out.txt", data);
//! try zid.fs.append("log.txt", "line\n");
//!
//! // Copiar/mover
//! try zid.fs.copy("src/", "dist/");
//! try zid.fs.move("old.txt", "new.txt");
//!
//! // Directorios
//! try zid.fs.mkdir("path/to/dir");
//! try zid.fs.rmdir("temp/");
//!
//! // Info
//! if (zid.fs.exists("file.txt")) { ... }
//! const info = try zid.fs.stat("file.txt");
//! ```

const std = @import("std");
const api = @import("api.zig");

// ============ READ/WRITE ============

/// Read entire file contents
pub fn read(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024);
}

/// Read file as lines
pub fn readLines(allocator: std.mem.Allocator, path: []const u8) !std.ArrayList([]const u8) {
    const content = try read(allocator, path);
    var lines = std.ArrayList([]const u8).init(allocator);

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        try lines.append(line);
    }

    return lines;
}

/// Write data to file (creates or overwrites)
pub fn write(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(data);
}

/// Append data to file
pub fn append(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .write_only });
    defer file.close();
    try file.seekFromEnd(0);
    try file.writeAll(data);
}

/// Write JSON to file
pub fn writeJson(path: []const u8, value: anytype) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buffered = std.io.bufferedWriter(file.writer());
    try std.json.stringify(value, .{ .whitespace = .indent_2 }, buffered.writer());
    try buffered.flush();
}

// ============ COPY/MOVE/DELETE ============

/// Copy file or directory recursively
pub fn copy(src: []const u8, dest: []const u8) !void {
    const stat = try std.fs.cwd().statFile(src);

    if (stat.kind == .directory) {
        try copyDir(src, dest);
    } else {
        try copyFile(src, dest);
    }
}

fn copyFile(src: []const u8, dest: []const u8) !void {
    try std.fs.cwd().copyFile(src, std.fs.cwd(), dest, .{});
}

fn copyDir(src: []const u8, dest: []const u8) !void {
    // Create dest directory
    std.fs.cwd().makePath(dest) catch {};

    var dir = try std.fs.cwd().openDir(src, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        var src_buf: [std.fs.max_path_bytes]u8 = undefined;
        var dest_buf: [std.fs.max_path_bytes]u8 = undefined;

        const src_path = try std.fmt.bufPrint(&src_buf, "{s}/{s}", .{ src, entry.name });
        const dest_path = try std.fmt.bufPrint(&dest_buf, "{s}/{s}", .{ dest, entry.name });

        if (entry.kind == .directory) {
            try copyDir(src_path, dest_path);
        } else {
            try copyFile(src_path, dest_path);
        }
    }
}

/// Move/rename file or directory
pub fn move(src: []const u8, dest: []const u8) !void {
    try std.fs.cwd().rename(src, dest);
}

/// Delete file
pub fn rm(path: []const u8) !void {
    try std.fs.cwd().deleteFile(path);
}

/// Delete directory recursively
pub fn rmdir(path: []const u8) !void {
    try std.fs.cwd().deleteTree(path);
}

/// Delete file or directory (auto-detect)
pub fn remove(path: []const u8) !void {
    const stat = std.fs.cwd().statFile(path) catch return;
    if (stat.kind == .directory) {
        try rmdir(path);
    } else {
        try rm(path);
    }
}

// ============ DIRECTORIES ============

/// Create directory (and parents)
pub fn mkdir(path: []const u8) !void {
    try std.fs.cwd().makePath(path);
}

/// Create temp directory
pub fn tmpdir(allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
    const tmp = std.fs.cwd().openDir("/tmp", .{}) catch std.fs.cwd();

    var buf: [32]u8 = undefined;
    const random = std.crypto.random.int(u64);
    const suffix = std.fmt.bufPrint(&buf, "{x}", .{random}) catch "tmp";

    const name = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ prefix, suffix });
    try tmp.makePath(name);

    return std.fmt.allocPrint(allocator, "/tmp/{s}", .{name});
}

/// List directory contents
pub fn ls(allocator: std.mem.Allocator, path: []const u8) ![]Entry {
    var entries = std.ArrayList(Entry).init(allocator);

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try entries.append(.{
            .name = try allocator.dupe(u8, entry.name),
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
};

// ============ INFO ============

/// Check if path exists
pub fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Check if path is directory
pub fn isDir(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Check if path is file
pub fn isFile(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

/// Get file info
pub fn stat(path: []const u8) !Stat {
    const s = try std.fs.cwd().statFile(path);
    return .{
        .size = s.size,
        .kind = s.kind,
        .mtime = s.mtime,
        .atime = s.atime,
    };
}

pub const Stat = struct {
    size: u64,
    kind: std.fs.Dir.Entry.Kind,
    mtime: i128,
    atime: i128,

    pub fn isDir(self: Stat) bool {
        return self.kind == .directory;
    }

    pub fn isFile(self: Stat) bool {
        return self.kind == .file;
    }
};

/// Get absolute path
pub fn realpath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.fs.cwd().realpathAlloc(allocator, path);
}

/// Get basename
pub fn basename(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

/// Get directory name
pub fn dirname(path: []const u8) ?[]const u8 {
    return std.fs.path.dirname(path);
}

/// Get extension
pub fn extname(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

/// Join paths
pub fn join(allocator: std.mem.Allocator, paths: []const []const u8) ![]const u8 {
    return std.fs.path.join(allocator, paths);
}

// ============ PERMISSIONS ============

/// Make file executable
pub fn chmod(path: []const u8, mode: std.fs.File.Mode) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();
    try file.chmod(mode);
}

/// Make executable (755)
pub fn makeExecutable(path: []const u8) !void {
    try chmod(path, 0o755);
}

//! File System - Cross-platform file operations

const std = @import("std");
const Environment = @import("env.zig");

pub fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn isDir(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

pub fn isFile(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

pub fn read(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(alloc, std.math.maxInt(usize));
}

pub fn write(path: []const u8, data: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(data);
}

pub fn mkdir(path: []const u8) !void {
    std.fs.cwd().makeDir(path) catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };
}

pub fn mkdirp(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };
}

pub fn remove(path: []const u8) !void {
    try std.fs.cwd().deleteFile(path);
}

pub fn removeTree(path: []const u8) void {
    std.fs.cwd().deleteTree(path) catch {};
}

pub fn copy(src: []const u8, dst: []const u8) !void {
    try std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{});
}

pub fn realpath(alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().realpathAlloc(alloc, path);
}

// Path utilities
pub const path = struct {
    pub fn join(alloc: std.mem.Allocator, paths: []const []const u8) ![]u8 {
        return std.fs.path.join(alloc, paths);
    }

    pub fn dirname(p: []const u8) []const u8 {
        return std.fs.path.dirname(p) orelse ".";
    }

    pub fn basename(p: []const u8) []const u8 {
        return std.fs.path.basename(p);
    }

    pub fn extension(p: []const u8) []const u8 {
        return std.fs.path.extension(p);
    }
};

pub fn tmpdir() []const u8 {
    if (Environment.isWindows) {
        return std.posix.getenv("TEMP") orelse "C:\\Windows\\Temp";
    }
    return std.posix.getenv("TMPDIR") orelse "/tmp";
}

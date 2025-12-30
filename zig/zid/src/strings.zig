//! Strings - String utilities
//!
//! Common string operations.

const std = @import("std");

pub fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, s, prefix);
}

pub fn endsWith(s: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, s, suffix);
}

pub fn contains(s: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, s, needle) != null;
}

pub fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\n\r");
}

pub fn split(s: []const u8, delim: u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitScalar(u8, s, delim);
}

/// String builder
pub const Builder = struct {
    list: std.ArrayList(u8),

    pub fn init(alloc: std.mem.Allocator) Builder {
        return .{ .list = std.ArrayList(u8).init(alloc) };
    }

    pub fn deinit(self: *Builder) void {
        self.list.deinit();
    }

    pub fn append(self: *Builder, s: []const u8) !void {
        try self.list.appendSlice(s);
    }

    pub fn appendFmt(self: *Builder, comptime fmt: []const u8, args: anytype) !void {
        try self.list.writer().print(fmt, args);
    }

    pub fn slice(self: Builder) []const u8 {
        return self.list.items;
    }

    pub fn toOwned(self: *Builder) ![]u8 {
        return self.list.toOwnedSlice();
    }
};

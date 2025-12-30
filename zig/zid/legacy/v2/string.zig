//! String utilities
//!
//! Provides string manipulation, building, and joining utilities.

const std = @import("std");
const Environment = @import("env.zig");
const allocators = @import("allocators.zig");

// ============ STRING BUILDER ============

/// Efficient string builder for incremental construction
pub const StringBuilder = struct {
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .buffer = std.ArrayList(u8).init(alloc),
        };
    }

    pub fn initCapacity(alloc: std.mem.Allocator, capacity: usize) !Self {
        var buffer = std.ArrayList(u8).init(alloc);
        try buffer.ensureTotalCapacity(capacity);
        return .{ .buffer = buffer };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn append(self: *Self, s: []const u8) !void {
        try self.buffer.appendSlice(s);
    }

    pub fn appendChar(self: *Self, c: u8) !void {
        try self.buffer.append(c);
    }

    pub fn appendFmt(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        try self.buffer.writer().print(fmt, args);
    }

    pub fn appendLine(self: *Self, s: []const u8) !void {
        try self.append(s);
        try self.append(Environment.lineEnding);
    }

    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn toOwnedSlice(self: *Self) ![]u8 {
        return self.buffer.toOwnedSlice();
    }

    pub fn slice(self: Self) []const u8 {
        return self.buffer.items;
    }

    pub fn len(self: Self) usize {
        return self.buffer.items.len;
    }

    pub fn writer(self: *Self) std.ArrayList(u8).Writer {
        return self.buffer.writer();
    }
};

// ============ STRING JOINER ============

/// Join strings with a separator
pub const StringJoiner = struct {
    parts: std.ArrayList([]const u8),
    separator: []const u8,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator, separator: []const u8) Self {
        return .{
            .parts = std.ArrayList([]const u8).init(alloc),
            .separator = separator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parts.deinit();
    }

    pub fn add(self: *Self, part: []const u8) !void {
        try self.parts.append(part);
    }

    pub fn join(self: Self, alloc: std.mem.Allocator) ![]u8 {
        if (self.parts.items.len == 0) return try alloc.alloc(u8, 0);

        // Calculate total length
        var total_len: usize = 0;
        for (self.parts.items, 0..) |part, i| {
            total_len += part.len;
            if (i < self.parts.items.len - 1) {
                total_len += self.separator.len;
            }
        }

        // Build result
        var result = try alloc.alloc(u8, total_len);
        var offset: usize = 0;

        for (self.parts.items, 0..) |part, i| {
            @memcpy(result[offset .. offset + part.len], part);
            offset += part.len;

            if (i < self.parts.items.len - 1) {
                @memcpy(result[offset .. offset + self.separator.len], self.separator);
                offset += self.separator.len;
            }
        }

        return result;
    }
};

// ============ UTILITY FUNCTIONS ============

/// Check if string starts with prefix
pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, s, prefix);
}

/// Check if string ends with suffix
pub fn endsWith(s: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, s, suffix);
}

/// Check if string contains substring
pub fn contains(s: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, s, needle) != null;
}

/// Trim whitespace from both ends
pub fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\n\r");
}

/// Trim whitespace from left
pub fn trimLeft(s: []const u8) []const u8 {
    return std.mem.trimLeft(u8, s, " \t\n\r");
}

/// Trim whitespace from right
pub fn trimRight(s: []const u8) []const u8 {
    return std.mem.trimRight(u8, s, " \t\n\r");
}

/// Split string by separator
pub fn split(s: []const u8, sep: []const u8) std.mem.SplitIterator(u8, .sequence) {
    return std.mem.splitSequence(u8, s, sep);
}

/// Split string by single character
pub fn splitScalar(s: []const u8, sep: u8) std.mem.SplitIterator(u8, .scalar) {
    return std.mem.splitScalar(u8, s, sep);
}

/// Replace all occurrences
pub fn replaceAll(alloc: std.mem.Allocator, s: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(alloc);
    var remaining = s;

    while (std.mem.indexOf(u8, remaining, needle)) |idx| {
        try result.appendSlice(remaining[0..idx]);
        try result.appendSlice(replacement);
        remaining = remaining[idx + needle.len ..];
    }
    try result.appendSlice(remaining);

    return result.toOwnedSlice();
}

/// Repeat string n times
pub fn repeat(alloc: std.mem.Allocator, s: []const u8, n: usize) ![]u8 {
    const result = try alloc.alloc(u8, s.len * n);
    var offset: usize = 0;
    for (0..n) |_| {
        @memcpy(result[offset .. offset + s.len], s);
        offset += s.len;
    }
    return result;
}

/// Pad left to width
pub fn padLeft(alloc: std.mem.Allocator, s: []const u8, width: usize, pad_char: u8) ![]u8 {
    if (s.len >= width) return try alloc.dupe(u8, s);

    const padding = width - s.len;
    var result = try alloc.alloc(u8, width);
    @memset(result[0..padding], pad_char);
    @memcpy(result[padding..], s);
    return result;
}

/// Pad right to width
pub fn padRight(alloc: std.mem.Allocator, s: []const u8, width: usize, pad_char: u8) ![]u8 {
    if (s.len >= width) return try alloc.dupe(u8, s);

    var result = try alloc.alloc(u8, width);
    @memcpy(result[0..s.len], s);
    @memset(result[s.len..], pad_char);
    return result;
}

/// Convert to lowercase (ASCII only)
pub fn toLower(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = try alloc.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

/// Convert to uppercase (ASCII only)
pub fn toUpper(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = try alloc.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

/// Check if string is empty or whitespace only
pub fn isBlank(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isWhitespace(c)) return false;
    }
    return true;
}

/// Format string (allocates)
pub fn format(alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![]u8 {
    return std.fmt.allocPrint(alloc, fmt, args);
}

// ============ TESTS ============

test "StringBuilder" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var sb = StringBuilder.init(arena.allocator());
    try sb.append("Hello");
    try sb.append(" ");
    try sb.append("World");

    try std.testing.expectEqualStrings("Hello World", sb.slice());
}

test "StringJoiner" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var joiner = StringJoiner.init(alloc, ", ");
    try joiner.add("a");
    try joiner.add("b");
    try joiner.add("c");

    const result = try joiner.join(alloc);
    try std.testing.expectEqualStrings("a, b, c", result);
}

test "replaceAll" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const result = try replaceAll(arena.allocator(), "hello world", "o", "0");
    try std.testing.expectEqualStrings("hell0 w0rld", result);
}

//! JSON API
//!
//! Parsing y serialización JSON.
//!
//! ```zig
//! const zid = @import("zid");
//!
//! // Parse JSON
//! const data = try zid.json.parse(Config, content);
//!
//! // Stringify
//! const str = try zid.json.stringify(data);
//!
//! // Read/write JSON files
//! const config = try zid.json.readFile(Config, "config.json");
//! try zid.json.writeFile("out.json", data);
//! ```

const std = @import("std");
const fs = @import("fs.zig");

// ============ PARSE ============

/// Parse JSON string to type
pub fn parse(comptime T: type, allocator: std.mem.Allocator, str: []const u8) !T {
    return std.json.parseFromSlice(T, allocator, str, .{});
}

/// Parse JSON with options
pub fn parseOpts(
    comptime T: type,
    allocator: std.mem.Allocator,
    str: []const u8,
    opts: std.json.ParseOptions,
) !T {
    return std.json.parseFromSlice(T, allocator, str, opts);
}

/// Parse to dynamic Value
pub fn parseValue(allocator: std.mem.Allocator, str: []const u8) !std.json.Value {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, str, .{});
    return parsed.value;
}

// ============ STRINGIFY ============

/// Convert value to JSON string
pub fn stringify(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    try std.json.stringify(value, .{}, list.writer());
    return list.toOwnedSlice();
}

/// Convert to pretty JSON
pub fn stringifyPretty(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    try std.json.stringify(value, .{ .whitespace = .indent_2 }, list.writer());
    return list.toOwnedSlice();
}

// ============ FILE OPERATIONS ============

/// Read and parse JSON file
pub fn readFile(comptime T: type, allocator: std.mem.Allocator, path: []const u8) !T {
    const content = try fs.read(allocator, path);
    defer allocator.free(content);
    return parse(T, allocator, content);
}

/// Write value as JSON to file
pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, value: anytype) !void {
    const content = try stringifyPretty(allocator, value);
    defer allocator.free(content);
    try fs.write(path, content);
}

// ============ DYNAMIC ACCESS ============

/// Get value from path (e.g., "user.name" or "items[0].id")
pub fn get(value: std.json.Value, path: []const u8) ?std.json.Value {
    var current = value;
    var parts = std.mem.splitScalar(u8, path, '.');

    while (parts.next()) |part| {
        // Check for array access [n]
        if (std.mem.indexOf(u8, part, "[")) |bracket_start| {
            const key = part[0..bracket_start];
            const idx_str = part[bracket_start + 1 .. part.len - 1];
            const idx = std.fmt.parseInt(usize, idx_str, 10) catch return null;

            // Get object value
            if (key.len > 0) {
                current = switch (current) {
                    .object => |obj| obj.get(key) orelse return null,
                    else => return null,
                };
            }

            // Get array element
            current = switch (current) {
                .array => |arr| if (idx < arr.items.len) arr.items[idx] else return null,
                else => return null,
            };
        } else {
            current = switch (current) {
                .object => |obj| obj.get(part) orelse return null,
                else => return null,
            };
        }
    }

    return current;
}

/// Get string value at path
pub fn getString(value: std.json.Value, path: []const u8) ?[]const u8 {
    const v = get(value, path) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

/// Get integer value at path
pub fn getInt(value: std.json.Value, path: []const u8) ?i64 {
    const v = get(value, path) orelse return null;
    return switch (v) {
        .integer => |i| i,
        else => null,
    };
}

/// Get boolean value at path
pub fn getBool(value: std.json.Value, path: []const u8) ?bool {
    const v = get(value, path) orelse return null;
    return switch (v) {
        .bool => |b| b,
        else => null,
    };
}

// ============ MERGE ============

/// Merge two JSON objects (b overrides a)
pub fn merge(allocator: std.mem.Allocator, a: std.json.Value, b: std.json.Value) !std.json.Value {
    if (a != .object or b != .object) {
        return b;
    }

    var result = std.json.ObjectMap.init(allocator);

    // Copy all from a
    var iter_a = a.object.iterator();
    while (iter_a.next()) |entry| {
        try result.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Override/add from b
    var iter_b = b.object.iterator();
    while (iter_b.next()) |entry| {
        const existing = result.get(entry.key_ptr.*);
        if (existing != null and existing.? == .object and entry.value_ptr.* == .object) {
            // Recursively merge objects
            const merged = try merge(allocator, existing.?, entry.value_ptr.*);
            try result.put(entry.key_ptr.*, merged);
        } else {
            try result.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    return .{ .object = result };
}

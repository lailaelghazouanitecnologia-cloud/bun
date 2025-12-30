//! Apps Registry
//!
//! Register programs as direct commands.

const std = @import("std");
const Output = @import("../output.zig");
const zid = @import("../zid.zig");
const fs = @import("../fs.zig");

pub const App = struct {
    name: []const u8,
    path: []const u8,
};

var registry: ?std.StringHashMap(App) = null;

pub fn isApp(name: []const u8) bool {
    // TODO: Check registry
    _ = name;
    return false;
}

pub fn exec(alloc: std.mem.Allocator, name: []const u8, args: []const []const u8) !void {
    _ = alloc;
    _ = args;
    Output.err("App not found: {s}\n", .{name});
    return error.AppNotFound;
}

pub fn add(alloc: std.mem.Allocator, source: []const u8, name: ?[]const u8) !void {
    const app_name = name orelse std.fs.path.basename(source);

    Output.print("Adding app: {s}\n", .{app_name});

    // Resolve path
    const path = try fs.realpath(alloc, source);
    defer alloc.free(path);

    // TODO: Build if needed, register

    Output.success("Added: {s}\n", .{app_name});
    Output.print("Run with: {s}\n", .{app_name});
}

pub fn remove(alloc: std.mem.Allocator, name: []const u8) !void {
    _ = alloc;
    Output.print("Removing app: {s}\n", .{name});
    Output.success("Removed: {s}\n", .{name});
}

pub fn list(alloc: std.mem.Allocator) !void {
    _ = alloc;
    Output.bold("Registered apps:\n", .{});
    Output.print("  (none registered yet)\n", .{});
}

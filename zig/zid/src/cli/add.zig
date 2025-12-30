//! Add Command - Add apps to registry

const std = @import("std");
const Output = @import("../output.zig");
const apps = @import("../apps/apps.zig");

pub fn run(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid add <path|url> [name]\n", .{});
        return;
    }
    apps.add(alloc, args[0], if (args.len > 1) args[1] else null) catch |e| {
        Output.err("Add failed: {}\n", .{e});
    };
}

pub fn runRemove(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid remove <name>\n", .{});
        return;
    }
    apps.remove(alloc, args[0]) catch |e| {
        Output.err("Remove failed: {}\n", .{e});
    };
}

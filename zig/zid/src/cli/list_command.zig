//! List Command
//!
//! List installed tools and apps.
//!
//! Usage:
//!   zid list
//!   zid ls

const std = @import("std");
const Output = @import("../output.zig");
const toolchain = @import("../toolchain/mod.zig");
const apps = @import("../apps/mod.zig");

pub fn exec(alloc: std.mem.Allocator, args: []const []const u8) void {
    const show_apps = args.len > 0 and std.mem.eql(u8, args[0], "apps");
    const show_tools = args.len > 0 and std.mem.eql(u8, args[0], "tools");
    const show_all = args.len == 0 or (!show_apps and !show_tools);

    if (show_all or show_tools) {
        Output.bold("Installed Tools:\n", .{});
        toolchain.list(alloc) catch |err| {
            Output.err("  Failed to list tools: {}\n", .{err});
        };
        Output.print("\n", .{});
    }

    if (show_all or show_apps) {
        Output.bold("Registered Apps:\n", .{});
        apps.list(alloc) catch |err| {
            Output.err("  Failed to list apps: {}\n", .{err});
        };
    }
}

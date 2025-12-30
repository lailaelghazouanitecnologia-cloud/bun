//! Add Command
//!
//! Add apps to the registry. Apps become direct commands.
//!
//! Usage:
//!   zid add ./my-tool
//!   zid add https://github.com/user/repo

const std = @import("std");
const Output = @import("../output.zig");
const apps = @import("../apps/mod.zig");

pub fn exec(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        printHelp();
        return;
    }

    apps.add(alloc, args) catch |err| {
        Output.err("Add failed: {}\n", .{err});
    };
}

pub fn execRemove(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid remove <app-name>\n", .{});
        return;
    }

    apps.remove(alloc, args) catch |err| {
        Output.err("Remove failed: {}\n", .{err});
    };
}

fn printHelp() void {
    const help =
        \\Usage: zid add <source> [name]
        \\
        \\Add an app to the registry. The app becomes a direct command.
        \\
        \\Sources:
        \\  ./path/to/project       Local project (will build if needed)
        \\  ./path/to/binary        Local binary (registers directly)
        \\  https://github.com/...  Git repository (clones and builds)
        \\
        \\Examples:
        \\  zid add ./my-tool                    Add local project
        \\  zid add ./bin/my-app my-app          Add binary with custom name
        \\  zid add https://github.com/user/repo Clone and add from GitHub
        \\
    ;
    Output.print("{s}", .{help});
}

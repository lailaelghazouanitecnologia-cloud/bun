//! Add Command - Add apps to registry
//!
//! Register programs as direct commands.
//!
//! Examples:
//!   zid add myprogram.js          # Register JS script
//!   zid add ./build/myapp         # Register binary
//!   zid add . --name myproject    # Register current directory as project

const std = @import("std");
const zid = @import("../zid.zig");
const Output = zid.Output;
const apps = @import("../apps/apps.zig");

pub fn run(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        showHelp();
        return;
    }

    var source: ?[]const u8 = null;
    var name: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--name") or std.mem.eql(u8, arg, "-n")) {
            if (i + 1 < args.len) {
                i += 1;
                name = args[i];
            } else {
                Output.err("--name requires a value\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            showHelp();
            return;
        } else if (source == null) {
            source = arg;
        }
    }

    if (source == null) {
        Output.err("Missing source path\n", .{});
        showHelp();
        return;
    }

    switch (apps.add(alloc, source.?, name)) {
        .ok => {},
        .err => |e| {
            Output.err("Failed to add app: {s}\n", .{e.message});
        },
    }
}

pub fn runRemove(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.err("Missing app name\n", .{});
        Output.print("Usage: zid remove <name>\n", .{});
        return;
    }

    switch (apps.remove(alloc, args[0])) {
        .ok => {},
        .err => |e| {
            Output.err("Failed to remove app: {s}\n", .{e.message});
        },
    }
}

pub fn runList(alloc: std.mem.Allocator) void {
    apps.list(alloc);
}

fn showHelp() void {
    Output.bold("zid add", .{});
    Output.print(" - Register programs as commands\n\n", .{});
    Output.print("Usage: zid add <path> [options]\n\n", .{});
    Output.print("Options:\n", .{});
    Output.print("  --name, -n <name>   Custom command name\n", .{});
    Output.print("\nExamples:\n", .{});
    Output.print("  zid add myprogram.js          # Register as 'myprogram'\n", .{});
    Output.print("  zid add ./build/app -n myapp  # Register as 'myapp'\n", .{});
    Output.print("  zid add .                     # Register current project\n", .{});
    Output.print("\nOnce registered, run directly:\n", .{});
    Output.print("  myprogram [args]\n", .{});
}

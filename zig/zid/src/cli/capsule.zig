//! Capsule Command - Manage library capsules
//!
//! Commands:
//!   zid capsule add <name>    - Install a capsule
//!   zid capsule remove <name> - Remove a capsule
//!   zid capsule list          - List installed capsules
//!   zid capsule info <name>   - Show capsule info

const std = @import("std");
const zid = @import("../zid.zig");
const capsules = @import("../capsules/capsules.zig");
const Output = zid.Output;

/// Run capsule command
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        showHelp();
        return;
    }

    const sub = args[0];
    const sub_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    if (eql(sub, "add") or eql(sub, "install")) {
        runAdd(allocator, sub_args);
    } else if (eql(sub, "remove") or eql(sub, "rm")) {
        runRemove(allocator, sub_args);
    } else if (eql(sub, "list") or eql(sub, "ls")) {
        runList(allocator);
    } else if (eql(sub, "info")) {
        runInfo(allocator, sub_args);
    } else if (eql(sub, "available")) {
        runAvailable();
    } else if (eql(sub, "help") or eql(sub, "-h")) {
        showHelp();
    } else {
        Output.err("Unknown subcommand: {s}\n", .{sub});
        showHelp();
    }
}

/// Install a capsule
fn runAdd(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.err("Missing capsule name\n", .{});
        Output.print("Usage: zid capsule add <name>\n", .{});
        return;
    }

    const name = args[0];

    switch (capsules.install(allocator, name)) {
        .ok => |cap| {
            Output.success("Capsule {s}@{s} installed\n", .{ cap.name, cap.version });
            if (cap.description.len > 0) {
                Output.print("  {s}\n", .{cap.description});
            }
        },
        .err => |e| {
            Output.err("Failed to install {s}: {s}\n", .{ name, e.message });
        },
    }
}

/// Remove a capsule
pub fn runRemove(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.err("Missing capsule name\n", .{});
        Output.print("Usage: zid capsule remove <name>\n", .{});
        return;
    }

    const name = args[0];

    switch (capsules.remove(allocator, name)) {
        .ok => {
            Output.success("Capsule {s} removed\n", .{name});
        },
        .err => |e| {
            Output.err("Failed to remove {s}: {s}\n", .{ name, e.message });
        },
    }
}

/// List installed capsules
pub fn runList(allocator: std.mem.Allocator) void {
    capsules.list(allocator);
}

/// Show capsule info
fn runInfo(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.err("Missing capsule name\n", .{});
        Output.print("Usage: zid capsule info <name>\n", .{});
        return;
    }

    const name = args[0];

    // Check if it's a built-in
    if (capsules.registry.getBuiltin(name)) |cap| {
        Output.bold("{s}@{s}\n", .{ cap.name, cap.version });
        Output.print("  Type: built-in\n", .{});
        Output.print("  {s}\n", .{cap.description});
        return;
    }

    // Check if installed
    var mgr = capsules.Manager.init(allocator);
    if (mgr.get(name)) |cap| {
        Output.bold("{s}@{s}\n", .{ cap.name, cap.version });
        Output.print("  Type: {s}\n", .{@tagName(cap.kind)});
        Output.print("  Path: {s}\n", .{cap.path});
    } else {
        Output.print("Capsule '{s}' not found.\n", .{name});
        Output.print("Run 'zid capsule available' to see available capsules.\n", .{});
    }
}

/// Show available capsules
fn runAvailable() void {
    Output.bold("Available capsules:\n\n", .{});

    Output.print("Built-in:\n", .{});
    for (capsules.registry.listBuiltins()) |cap| {
        Output.print("  {s: <12} {s}\n", .{ cap.name, cap.description });
    }

    Output.print("\nUse 'zid capsule add <name>' to install.\n", .{});
}

fn showHelp() void {
    Output.bold("zid capsule", .{});
    Output.print(" - Manage library capsules\n\n", .{});
    Output.print("Commands:\n", .{});
    Output.print("  add <name>      Install a capsule\n", .{});
    Output.print("  remove <name>   Remove a capsule\n", .{});
    Output.print("  list            List installed capsules\n", .{});
    Output.print("  info <name>     Show capsule details\n", .{});
    Output.print("  available       List available capsules\n", .{});
    Output.print("\nExamples:\n", .{});
    Output.print("  zid capsule add webgpu\n", .{});
    Output.print("  zid capsule list\n", .{});
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

//! CLI - Command Line Interface
//!
//! Command routing and execution.

const std = @import("std");
const Output = @import("output.zig");

// Commands
pub const InstallCommand = @import("cli/install.zig");
pub const AddCommand = @import("cli/add.zig");
pub const InitCommand = @import("cli/init.zig");
pub const BuildCommand = @import("cli/build.zig");
pub const HelpCommand = @import("cli/help.zig");

// Subsystems
const toolchain = @import("toolchain/toolchain.zig");
const apps = @import("apps/apps.zig");

pub fn run(alloc: std.mem.Allocator) !void {
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        HelpCommand.run(alloc, &.{});
        return;
    }

    const cmd = args[1];
    const cmd_args = if (args.len > 2) args[2..] else &[_][]const u8{};

    // Global flags
    if (eql(cmd, "-h") or eql(cmd, "--help")) {
        HelpCommand.run(alloc, &.{});
        return;
    }
    if (eql(cmd, "-v") or eql(cmd, "--version")) {
        Output.print("zid 0.1.0\n", .{});
        return;
    }

    // Route command
    if (Command.parse(cmd)) |command| {
        command.run(alloc, cmd_args);
    } else if (apps.isApp(cmd)) {
        try apps.exec(alloc, cmd, cmd_args);
    } else {
        Output.err("Unknown command: {s}\n", .{cmd});
        Output.print("Run 'zid help' for usage.\n", .{});
    }
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub const Command = enum {
    // Toolchain
    install,
    uninstall,
    list,
    use,
    // Apps
    add,
    remove,
    // Framework
    init,
    build,
    watch,
    // Meta
    help,

    pub fn parse(s: []const u8) ?Command {
        const map = std.StaticStringMap(Command).initComptime(.{
            .{ "install", .install },
            .{ "i", .install },
            .{ "uninstall", .uninstall },
            .{ "rm", .uninstall },
            .{ "list", .list },
            .{ "ls", .list },
            .{ "use", .use },
            .{ "add", .add },
            .{ "remove", .remove },
            .{ "init", .init },
            .{ "create", .init },
            .{ "build", .build },
            .{ "b", .build },
            .{ "watch", .watch },
            .{ "w", .watch },
            .{ "help", .help },
        });
        return map.get(s);
    }

    pub fn run(self: Command, alloc: std.mem.Allocator, args: []const []const u8) void {
        switch (self) {
            .install => InstallCommand.run(alloc, args),
            .uninstall => InstallCommand.runUninstall(alloc, args),
            .list => InstallCommand.runList(alloc),
            .use => InstallCommand.runUse(alloc, args),
            .add => AddCommand.run(alloc, args),
            .remove => AddCommand.runRemove(alloc, args),
            .init => InitCommand.run(alloc, args),
            .build => BuildCommand.run(alloc, args),
            .watch => BuildCommand.runWatch(alloc, args),
            .help => HelpCommand.run(alloc, args),
        }
    }
};

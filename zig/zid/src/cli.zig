//! CLI - Command Line Interface
//!
//! Orchestrates command parsing and dispatching.
//! Commands are defined in cli/ subdirectory.

const std = @import("std");
const Output = @import("output.zig");
const Environment = @import("env.zig");

// ============ COMMANDS ============

pub const InstallCommand = @import("cli/install_command.zig");
pub const ListCommand = @import("cli/list_command.zig");
pub const AddCommand = @import("cli/add_command.zig");
pub const InitCommand = @import("cli/init_command.zig");
pub const BuildCommand = @import("cli/build_command.zig");
pub const HelpCommand = @import("cli/help_command.zig");

// Subsystems
const toolchain = @import("toolchain/mod.zig");
const apps = @import("apps/mod.zig");

// ============ CLI ============

pub const Cli = struct {
    alloc: std.mem.Allocator,
    args: []const []const u8,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Self {
        const process_args = try std.process.argsAlloc(alloc);
        return .{
            .alloc = alloc,
            .args = process_args,
        };
    }

    pub fn deinit(self: *Self) void {
        std.process.argsFree(self.alloc, self.args);
    }

    /// Main entry point - called from main.zig
    pub fn start(alloc: std.mem.Allocator) !void {
        var cli = try Cli.init(alloc);
        defer cli.deinit();

        try cli.run();
    }

    fn run(self: *Self) !void {
        if (self.args.len < 2) {
            HelpCommand.exec(self.alloc, &.{});
            return;
        }

        const cmd_name = self.args[1];
        const cmd_args = if (self.args.len > 2) self.args[2..] else &[_][]const u8{};

        // Check for global flags first
        if (isFlag(cmd_name)) {
            self.handleFlag(cmd_name);
            return;
        }

        // Route to command
        const command = Command.parse(cmd_name) orelse {
            // Check if it's a registered app
            if (apps.isRegistered(cmd_name)) {
                return apps.execute(self.alloc, cmd_name, cmd_args);
            }

            Output.err("Unknown command: {s}\n", .{cmd_name});
            Output.print("\nRun 'zid help' for usage.\n", .{});
            return;
        };

        command.exec(self.alloc, cmd_args);
    }

    fn handleFlag(self: *Self, flag: []const u8) void {
        _ = self;
        if (eql(flag, "-h") or eql(flag, "--help")) {
            HelpCommand.printHelp();
        } else if (eql(flag, "-v") or eql(flag, "--version")) {
            Output.print("zid 0.1.0\n", .{});
        } else {
            Output.err("Unknown flag: {s}\n", .{flag});
        }
    }

    fn isFlag(s: []const u8) bool {
        return s.len > 0 and s[0] == '-';
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

// ============ COMMAND ENUM ============

pub const Command = enum {
    // Toolchain
    install,
    uninstall,
    list,
    use,

    // Apps
    add,
    remove,
    run,

    // Framework
    init,
    build,
    watch,

    // Meta
    help,
    version,
    upgrade,

    const Self = @This();

    /// Parse command name to enum
    pub fn parse(name: []const u8) ?Self {
        const map = std.StaticStringMap(Self).initComptime(.{
            // Toolchain
            .{ "install", .install },
            .{ "i", .install },
            .{ "uninstall", .uninstall },
            .{ "rm", .uninstall },
            .{ "list", .list },
            .{ "ls", .list },
            .{ "use", .use },

            // Apps
            .{ "add", .add },
            .{ "remove", .remove },
            .{ "run", .run },
            .{ "x", .run },

            // Framework
            .{ "init", .init },
            .{ "create", .init },
            .{ "build", .build },
            .{ "b", .build },
            .{ "watch", .watch },
            .{ "w", .watch },

            // Meta
            .{ "help", .help },
            .{ "version", .version },
            .{ "upgrade", .upgrade },
        });

        return map.get(name);
    }

    /// Execute the command
    pub fn exec(self: Self, alloc: std.mem.Allocator, args: []const []const u8) void {
        switch (self) {
            .install => InstallCommand.exec(alloc, args),
            .uninstall => InstallCommand.execUninstall(alloc, args),
            .list => ListCommand.exec(alloc, args),
            .use => InstallCommand.execUse(alloc, args),
            .add => AddCommand.exec(alloc, args),
            .remove => AddCommand.execRemove(alloc, args),
            .run => apps.run(alloc, args) catch |err| {
                Output.err("Run failed: {}\n", .{err});
            },
            .init => InitCommand.exec(alloc, args),
            .build => BuildCommand.exec(alloc, args),
            .watch => BuildCommand.execWatch(alloc, args),
            .help => HelpCommand.exec(alloc, args),
            .version => Output.print("zid 0.1.0\n", .{}),
            .upgrade => Output.print("Upgrade not yet implemented\n", .{}),
        }
    }
};

// ============ TESTS ============

test "Command.parse" {
    try std.testing.expectEqual(Command.install, Command.parse("install").?);
    try std.testing.expectEqual(Command.install, Command.parse("i").?);
    try std.testing.expectEqual(Command.build, Command.parse("b").?);
    try std.testing.expect(Command.parse("nonexistent") == null);
}

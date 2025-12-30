//! CLI - Command Line Interface
//!
//! Command routing and execution.
//!
//! Supports:
//!   zid <command> <args>     # Normal commands
//!   zid <toolchain> <args>   # Run toolchain (bun, zig, node, etc.)

const std = @import("std");
const Output = @import("output.zig");

// Commands
pub const InstallCommand = @import("cli/install.zig");
pub const AddCommand = @import("cli/add.zig");
pub const InitCommand = @import("cli/init.zig");
pub const BuildCommand = @import("cli/build.zig");
pub const CapsuleCommand = @import("cli/capsule.zig");
pub const HelpCommand = @import("cli/help.zig");

// Subsystems
const toolchain = @import("toolchain/toolchain.zig");
const resolver = @import("toolchain/resolver.zig");
const apps = @import("apps/apps.zig");
const patches = @import("patches/patches.zig");

pub fn run(alloc: std.mem.Allocator) !void {
    // Auto-check for security patches at startup (silent)
    checkPatches(alloc);

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

    // Try as command first
    if (Command.parse(cmd)) |command| {
        command.run(alloc, cmd_args);
        return;
    }

    // Try as toolchain (zid bun, zid zig, zid node, etc.)
    if (toolchain.isSupported(cmd)) {
        const exit_code = resolver.runToolchain(alloc, cmd, cmd_args) catch |e| {
            Output.err("Failed to run toolchain: {}\n", .{e});
            return;
        };
        std.process.exit(exit_code);
    }

    // Try as registered app
    if (apps.isApp(cmd)) {
        try apps.exec(alloc, cmd, cmd_args);
        return;
    }

    // Unknown command
    Output.err("Unknown command: {s}\n", .{cmd});
    Output.print("\nDid you mean one of:\n", .{});
    Output.print("  zid install {s}    # Install toolchain\n", .{cmd});
    Output.print("  zid add {s}        # Register app\n", .{cmd});
    Output.print("\nRun 'zid help' for usage.\n", .{});
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
    toolchain_cmd,
    // Apps
    add,
    remove,
    run_app,
    // Capsules
    capsule,
    // Framework
    init,
    build,
    watch,
    // Meta
    help,
    update,
    conflicts,

    pub fn parse(s: []const u8) ?Command {
        const map = std.StaticStringMap(Command).initComptime(.{
            // Toolchain
            .{ "install", .install },
            .{ "i", .install },
            .{ "uninstall", .uninstall },
            .{ "rm", .uninstall },
            .{ "list", .list },
            .{ "ls", .list },
            .{ "use", .use },
            .{ "toolchain", .toolchain_cmd },
            .{ "tc", .toolchain_cmd },
            // Apps
            .{ "add", .add },
            .{ "remove", .remove },
            .{ "run", .run_app },
            // Capsules
            .{ "capsule", .capsule },
            .{ "cap", .capsule },
            // Framework
            .{ "init", .init },
            .{ "create", .init },
            .{ "build", .build },
            .{ "b", .build },
            .{ "watch", .watch },
            .{ "w", .watch },
            // Meta
            .{ "help", .help },
            .{ "update", .update },
            .{ "upgrade", .update },
            .{ "conflicts", .conflicts },
        });
        return map.get(s);
    }

    pub fn run(self: Command, alloc: std.mem.Allocator, args: []const []const u8) void {
        switch (self) {
            .install => InstallCommand.run(alloc, args),
            .uninstall => InstallCommand.runUninstall(alloc, args),
            .list => InstallCommand.runList(alloc),
            .use => InstallCommand.runUse(alloc, args),
            .toolchain_cmd => toolchain.custom.runCommand(alloc, args),
            .add => AddCommand.run(alloc, args),
            .remove => AddCommand.runRemove(alloc, args),
            .run_app => runApp(alloc, args),
            .capsule => CapsuleCommand.run(alloc, args),
            .init => InitCommand.run(alloc, args),
            .build => BuildCommand.run(alloc, args),
            .watch => BuildCommand.runWatch(alloc, args),
            .help => HelpCommand.run(alloc, args),
            .update => @import("cli/update.zig").run(alloc, args),
            .conflicts => runConflicts(alloc),
        }
    }
};

// ============ RUN APP ============

fn runApp(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.err("Missing app name\n", .{});
        Output.print("Usage: zid run <app> [args]\n", .{});
        return;
    }

    const app_name = args[0];
    const app_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    // Try as toolchain first
    if (toolchain.isSupported(app_name)) {
        const exit_code = resolver.runToolchain(alloc, app_name, app_args) catch {
            Output.err("Failed to run {s}\n", .{app_name});
            return;
        };
        if (exit_code != 0) {
            Output.err("{s} exited with code {d}\n", .{ app_name, exit_code });
        }
        return;
    }

    // Try as registered app
    apps.exec(alloc, app_name, app_args) catch {
        Output.err("App '{s}' not found\n", .{app_name});
        Output.print("Register with: zid add <path> --name {s}\n", .{app_name});
    };
}

// ============ CONFLICTS ============

fn runConflicts(alloc: std.mem.Allocator) void {
    Output.bold("Toolchain Conflicts:\n\n", .{});

    const conflicts = resolver.detectAllConflicts(alloc) catch {
        Output.err("Failed to detect conflicts\n", .{});
        return;
    };

    if (conflicts.len == 0) {
        Output.success("No conflicts detected!\n", .{});
        return;
    }

    for (conflicts) |conflict| {
        Output.print("  {s}\n", .{conflict.command});
        Output.print("    System: {s}\n", .{conflict.system_path});
        Output.print("    Zid:    {s}\n", .{conflict.zid_path});
        Output.print("\n", .{});
    }

    Output.print("To use zid's version: zid <toolchain> <args>\n", .{});
    Output.print("Example: zid bun run build.ts\n", .{});
}

// ============ INTERNAL ============

/// Check for security patches at startup (runs silently)
fn checkPatches(alloc: std.mem.Allocator) void {
    // Only check critical patches silently
    switch (patches.check(alloc)) {
        .ok => |pending| {
            for (pending) |patch| {
                if (patch.severity == .critical) {
                    // Auto-apply critical security patches
                    var mgr = patches.Manager.init(alloc);
                    defer mgr.deinit();
                    _ = mgr.apply(patch);
                }
            }
        },
        .err => {}, // Silently ignore network errors
    }
}

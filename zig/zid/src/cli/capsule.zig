//! Capsule Command - Manage library capsules
//!
//! Commands:
//!   zid capsule add <name>    - Install a capsule
//!   zid capsule remove <name> - Remove a capsule
//!   zid capsule list          - List installed capsules
//!   zid capsule info <name>   - Show capsule info
//!   zid capsule create <name> - Create new user capsule
//!   zid capsule paths         - Show library paths for compilers

const std = @import("std");
const zid = @import("../zid.zig");
const capsules = @import("../capsules/capsules.zig");
const paths = @import("../capsules/paths.zig");
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
    } else if (eql(sub, "create") or eql(sub, "new")) {
        runCreate(allocator, sub_args);
    } else if (eql(sub, "paths")) {
        runPaths(allocator, sub_args);
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

/// Create a new user capsule
fn runCreate(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.err("Missing capsule name\n", .{});
        Output.print("Usage: zid capsule create <name>\n", .{});
        return;
    }

    const name = args[0];

    // Validate name
    if (!isValidName(name)) {
        Output.err("Invalid capsule name: {s}\n", .{name});
        Output.print("Name must be lowercase alphanumeric with hyphens.\n", .{});
        return;
    }

    Output.print("Creating capsule: {s}...\n", .{name});

    // Create capsule structure
    switch (capsules.integration.createStubCapsule(allocator, name)) {
        .ok => {
            var mgr = capsules.Manager.init(allocator);

            Output.success("Created capsule: {s}\n\n", .{name});
            Output.print("Structure:\n", .{});
            Output.print("  {s}/capsules/intern/{s}/\n", .{ mgr.home_dir, name });
            Output.print("  ├── capsule.json      # Metadata\n", .{});
            Output.print("  └── src/\n", .{});
            Output.print("      └── {s}.zig       # Main module\n", .{name});
            Output.print("\nEdit src/{s}.zig to add your code.\n", .{name});
            Output.print("\nFor C libraries, add:\n", .{});
            Output.print("  include/              # Headers (.h)\n", .{});
            Output.print("  lib/                  # Libraries (.a, .so)\n", .{});
        },
        .err => |e| {
            Output.err("Failed to create capsule: {s}\n", .{e.message});
        },
    }
}

/// Show library paths for compilers
fn runPaths(allocator: std.mem.Allocator, args: []const []const u8) void {
    // Check for flags
    for (args) |arg| {
        if (eql(arg, "--c") or eql(arg, "-c")) {
            // Output C/C++ flags
            var buf: [4096]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            paths.generateCFlags(allocator, stream.writer()) catch {};
            Output.print("{s}\n", .{stream.getWritten()});
            return;
        }
        if (eql(arg, "--zig") or eql(arg, "-z")) {
            // Output Zig flags
            var buf: [4096]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            paths.generateZigFlags(allocator, stream.writer()) catch {};
            Output.print("{s}\n", .{stream.getWritten()});
            return;
        }
        if (eql(arg, "--env") or eql(arg, "-e")) {
            // Output environment variables
            var buf: [4096]u8 = undefined;
            var stream = std.io.fixedBufferStream(&buf);
            paths.generateEnvVars(allocator, stream.writer()) catch {};
            Output.print("{s}", .{stream.getWritten()});
            return;
        }
    }

    // Default: show summary
    paths.printSummary(allocator);
}

fn isValidName(name: []const u8) bool {
    if (name.len == 0 or name.len > 64) return false;

    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_') {
            return false;
        }
    }

    // Must start with letter
    return std.ascii.isAlphabetic(name[0]);
}

fn showHelp() void {
    Output.bold("zid capsule", .{});
    Output.print(" - Manage library capsules\n\n", .{});
    Output.print("Commands:\n", .{});
    Output.print("  add <name>      Install a capsule from registry\n", .{});
    Output.print("  remove <name>   Remove a capsule\n", .{});
    Output.print("  list            List installed capsules\n", .{});
    Output.print("  info <name>     Show capsule details\n", .{});
    Output.print("  available       List available capsules\n", .{});
    Output.print("  create <name>   Create new user capsule\n", .{});
    Output.print("  paths           Show library paths for compilers\n", .{});
    Output.print("\nCompiler Integration:\n", .{});
    Output.print("  paths --c       C/C++ compiler flags (-I, -L, -l)\n", .{});
    Output.print("  paths --zig     Zig compiler flags\n", .{});
    Output.print("  paths --env     Export as environment variables\n", .{});
    Output.print("\nExamples:\n", .{});
    Output.print("  zid capsule add webgpu          # Install from registry\n", .{});
    Output.print("  zid capsule create my-lib       # Create your own\n", .{});
    Output.print("  gcc main.c $(zid capsule paths --c)  # Use with C\n", .{});
    Output.print("  eval $(zid capsule paths --env)      # Export paths\n", .{});
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

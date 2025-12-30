const std = @import("std");
const toolchain = @import("toolchain/mod.zig");
const apps = @import("apps/mod.zig");
const framework = @import("framework/mod.zig");

pub const Command = enum {
    // Toolchain commands
    install,
    uninstall,
    list,
    use,

    // Apps commands
    add,
    remove,
    run,

    // Framework commands
    init,
    build,
    watch,

    // Meta
    help,
    version,
};

pub fn run(alloc: std.mem.Allocator) !void {
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    const cmd = parseCommand(args[1]) orelse {
        // Check if it's an app command
        if (apps.isRegistered(args[1])) {
            return apps.execute(alloc, args[1], args[2..]);
        }
        std.debug.print("Unknown command: {s}\n", .{args[1]});
        printHelp();
        return;
    };

    const cmd_args = if (args.len > 2) args[2..] else &[_][]const u8{};

    switch (cmd) {
        // Toolchain
        .install => try toolchain.install(alloc, cmd_args),
        .uninstall => try toolchain.uninstall(alloc, cmd_args),
        .list => try toolchain.list(alloc),
        .use => try toolchain.use(alloc, cmd_args),

        // Apps
        .add => try apps.add(alloc, cmd_args),
        .remove => try apps.remove(alloc, cmd_args),
        .run => try apps.run(alloc, cmd_args),

        // Framework
        .init => try framework.init(alloc, cmd_args),
        .build => try framework.build(alloc, cmd_args),
        .watch => try framework.watch(alloc, cmd_args),

        // Meta
        .help => printHelp(),
        .version => printVersion(),
    }
}

fn parseCommand(arg: []const u8) ?Command {
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
        .{ "run", .run },
        .{ "init", .init },
        .{ "build", .build },
        .{ "b", .build },
        .{ "watch", .watch },
        .{ "w", .watch },
        .{ "help", .help },
        .{ "-h", .help },
        .{ "--help", .help },
        .{ "version", .version },
        .{ "-v", .version },
        .{ "--version", .version },
    });
    return map.get(arg);
}

fn printHelp() void {
    const help =
        \\Zid - Universal Development Toolkit
        \\
        \\Usage: zid <command> [options]
        \\
        \\Toolchain Commands:
        \\  install, i <tool>[@version]   Install a tool (zig, rust, bun, node...)
        \\  uninstall, rm <tool>          Remove a tool
        \\  list, ls                      List installed tools
        \\  use <tool>@<version>          Switch active version
        \\
        \\Apps Commands:
        \\  add <path|url>                Add app to registry (becomes a command)
        \\  remove <name>                 Remove app from registry
        \\  run <name> [args]             Run an app explicitly
        \\
        \\Framework Commands:
        \\  init [template]               Initialize a new transpiler project
        \\  build, b                      Build the project
        \\  watch, w                      Watch and rebuild on changes
        \\
        \\Options:
        \\  -h, --help                    Show this help
        \\  -v, --version                 Show version
        \\
        \\Examples:
        \\  zid install zig@0.13.0        Install Zig 0.13.0
        \\  zid install rust              Install latest Rust
        \\  zid add ./my-tool             Add local tool as command
        \\  zid init lua-to-wasm          Create new transpiler project
        \\
    ;
    std.debug.print("{s}", .{help});
}

fn printVersion() void {
    std.debug.print("zid 0.1.0\n", .{});
}

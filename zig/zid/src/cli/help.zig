//! Help Command

const std = @import("std");
const Output = @import("../output.zig");

pub fn run(alloc: std.mem.Allocator, args: []const []const u8) void {
    _ = alloc;
    if (args.len > 0) {
        printCommandHelp(args[0]);
    } else {
        printHelp();
    }
}

pub fn printHelp() void {
    Output.print(
        \\
        \\  {s}Zid{s} - Universal Development Toolkit
        \\
        \\  {s}Usage:{s} zid <command> [options]
        \\
        \\  {s}Toolchain:{s}
        \\    install, i <tool>[@ver]   Install tool (zig, rust, bun, node...)
        \\    uninstall, rm <tool>      Remove tool
        \\    list, ls                  List installed tools
        \\    use <tool>@<ver>          Switch version
        \\
        \\  {s}Apps:{s}
        \\    add <path|url>            Add app (becomes a command)
        \\    remove <name>             Remove app
        \\
        \\  {s}Framework:{s}
        \\    init [template]           Create transpiler project
        \\    build, b                  Build project
        \\    watch, w                  Watch mode
        \\
        \\  {s}Discovery:{s}
        \\    search, s <query>         Search for tools
        \\    completions               Generate shell completions
        \\
        \\  {s}Options:{s}
        \\    -h, --help                Show help
        \\    -v, --version             Show version
        \\
        \\  {s}Examples:{s}
        \\    zid install zig@0.13.0
        \\    zid add ./my-tool
        \\    zid init lua-to-wasm
        \\
    , .{
        Output.Color.bold, Output.Color.reset,
        Output.Color.bold, Output.Color.reset,
        Output.Color.cyan, Output.Color.reset,
        Output.Color.cyan, Output.Color.reset,
        Output.Color.cyan, Output.Color.reset,
        Output.Color.cyan, Output.Color.reset,
        Output.Color.cyan, Output.Color.reset,
        Output.Color.dim,  Output.Color.reset,
    });
}

fn printCommandHelp(cmd: []const u8) void {
    _ = cmd;
    printHelp();
}

//! Help Command
//!
//! Display help information.

const std = @import("std");
const Output = @import("../output.zig");

pub fn exec(alloc: std.mem.Allocator, args: []const []const u8) void {
    _ = alloc;

    if (args.len > 0) {
        printCommandHelp(args[0]);
    } else {
        printHelp();
    }
}

pub fn printHelp() void {
    const help =
        \\
        \\  Zid - Universal Development Toolkit
        \\
        \\  Usage: zid <command> [options]
        \\
        \\  Toolchain Commands:
        \\    install, i <tool>[@version]   Install a tool (zig, rust, bun, node...)
        \\    uninstall, rm <tool>          Remove a tool
        \\    list, ls                      List installed tools
        \\    use <tool>@<version>          Switch active version
        \\
        \\  Apps Commands:
        \\    add <path|url>                Add app to registry (becomes a command)
        \\    remove <name>                 Remove app from registry
        \\    run <name> [args]             Run an app explicitly
        \\
        \\  Framework Commands:
        \\    init [template]               Initialize a new transpiler project
        \\    build, b                      Build the project
        \\    watch, w                      Watch and rebuild on changes
        \\
        \\  Options:
        \\    -h, --help                    Show this help
        \\    -v, --version                 Show version
        \\
        \\  Examples:
        \\    zid install zig@0.13.0        Install Zig 0.13.0
        \\    zid install rust              Install latest Rust
        \\    zid add ./my-tool             Add local tool as command
        \\    zid init lua-to-wasm          Create new transpiler project
        \\
        \\  Learn more: https://github.com/example/zid
        \\
    ;
    Output.print("{s}", .{help});
}

fn printCommandHelp(command: []const u8) void {
    if (std.mem.eql(u8, command, "install") or std.mem.eql(u8, command, "i")) {
        Output.print(
            \\Usage: zid install <tool>[@version]
            \\
            \\Install a development tool. If no version is specified,
            \\installs the latest stable version.
            \\
            \\Available tools: zig, rust, bun, node, go, deno, python
            \\
            \\Examples:
            \\  zid install zig@0.13.0
            \\  zid install rust
            \\
        , .{});
    } else if (std.mem.eql(u8, command, "add")) {
        Output.print(
            \\Usage: zid add <source> [name]
            \\
            \\Add an app to the registry. The app becomes a direct command.
            \\
            \\Sources:
            \\  ./path/to/project       Local project
            \\  https://github.com/...  Git repository
            \\
        , .{});
    } else if (std.mem.eql(u8, command, "init")) {
        Output.print(
            \\Usage: zid init [template] [name]
            \\
            \\Initialize a new transpiler project.
            \\
            \\Templates:
            \\  basic         Basic transpiler template
            \\  lua-to-wasm   Lua to WebAssembly
            \\  markdown      Markdown processor
            \\
        , .{});
    } else if (std.mem.eql(u8, command, "build") or std.mem.eql(u8, command, "b")) {
        Output.print(
            \\Usage: zid build [options]
            \\
            \\Build the current transpiler project.
            \\
            \\Options:
            \\  --watch, -w    Watch for changes
            \\  --output, -o   Output directory
            \\
        , .{});
    } else {
        Output.err("Unknown command: {s}\n", .{command});
        Output.print("Run 'zid help' for a list of commands.\n", .{});
    }
}

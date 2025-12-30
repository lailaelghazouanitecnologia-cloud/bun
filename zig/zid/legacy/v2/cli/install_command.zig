//! Install Command
//!
//! Install development tools (zig, rust, bun, node, etc.)
//!
//! Usage:
//!   zid install zig@0.13.0
//!   zid install rust
//!   zid i bun

const std = @import("std");
const Output = @import("../output.zig");
const toolchain = @import("../toolchain/mod.zig");

pub fn exec(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        printHelp();
        return;
    }

    toolchain.install(alloc, args) catch |err| {
        Output.err("Install failed: {}\n", .{err});
    };
}

pub fn execUninstall(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid uninstall <tool>[@version]\n", .{});
        return;
    }

    toolchain.uninstall(alloc, args) catch |err| {
        Output.err("Uninstall failed: {}\n", .{err});
    };
}

pub fn execUse(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid use <tool>@<version>\n", .{});
        return;
    }

    toolchain.use(alloc, args) catch |err| {
        Output.err("Use failed: {}\n", .{err});
    };
}

fn printHelp() void {
    const help =
        \\Usage: zid install <tool>[@version]
        \\
        \\Install a development tool. If no version is specified,
        \\installs the latest stable version.
        \\
        \\Available tools:
        \\  zig       Zig programming language
        \\  rust      Rust programming language (via rustup)
        \\  bun       Bun JavaScript runtime
        \\  node      Node.js runtime
        \\  go        Go programming language
        \\  deno      Deno JavaScript runtime
        \\  python    Python programming language
        \\
        \\Examples:
        \\  zid install zig@0.13.0    Install specific version
        \\  zid install rust          Install latest Rust
        \\  zid i bun@1.0.0           Short alias
        \\
        \\Options:
        \\  --force, -f    Reinstall even if already installed
        \\
    ;
    Output.print("{s}", .{help});
}

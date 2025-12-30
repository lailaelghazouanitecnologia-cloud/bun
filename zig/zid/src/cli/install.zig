//! Install Command - Install development tools

const std = @import("std");
const Output = @import("../output.zig");
const toolchain = @import("../toolchain/toolchain.zig");

pub fn run(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid install <tool>[@version]\n\n", .{});
        Output.print("Tools: zig, rust, bun, node, go, deno, python\n", .{});
        return;
    }
    toolchain.install(alloc, args[0]) catch |e| {
        Output.err("Install failed: {}\n", .{e});
    };
}

pub fn runUninstall(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid uninstall <tool>[@version]\n", .{});
        return;
    }
    toolchain.uninstall(alloc, args[0]) catch |e| {
        Output.err("Uninstall failed: {}\n", .{e});
    };
}

pub fn runList(alloc: std.mem.Allocator) void {
    toolchain.list(alloc) catch |e| {
        Output.err("List failed: {}\n", .{e});
    };
}

pub fn runUse(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid use <tool>@<version>\n", .{});
        return;
    }
    toolchain.use(alloc, args[0]) catch |e| {
        Output.err("Use failed: {}\n", .{e});
    };
}

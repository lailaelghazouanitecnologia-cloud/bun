//! Install Command - Install development tools
//!
//! Uses toolchain module with Maybe error handling.

const std = @import("std");
const zid = @import("../zid.zig");
const toolchain = @import("../toolchain/toolchain.zig");
const Output = zid.Output;

pub fn run(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        showUsage();
        return;
    }

    // Install each tool specified
    for (args) |spec| {
        switch (toolchain.install(alloc, spec)) {
            .ok => {},
            .err => |e| {
                Output.err("Install failed: {s}\n", .{e.message});
                if (e.path.len > 0) {
                    Output.err("  path: {s}\n", .{e.path});
                }
            },
        }
    }
}

pub fn runUninstall(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid uninstall <tool>[@version]\n", .{});
        return;
    }

    for (args) |spec| {
        switch (toolchain.uninstall(alloc, spec)) {
            .ok => {},
            .err => |e| {
                Output.err("Uninstall failed: {s}\n", .{e.message});
            },
        }
    }
}

pub fn runList(alloc: std.mem.Allocator) void {
    toolchain.list(alloc);
}

pub fn runUse(alloc: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.print("Usage: zid use <tool>@<version>\n", .{});
        return;
    }

    switch (toolchain.use(alloc, args[0])) {
        .ok => {},
        .err => |e| {
            Output.err("Use failed: {s}\n", .{e.message});
        },
    }
}

fn showUsage() void {
    Output.bold("Usage: zid install <tool>[@version]\n\n", .{});
    Output.print("Install development tools.\n\n", .{});

    Output.bold("Supported tools:\n", .{});
    for (toolchain.supportedTools()) |tool| {
        Output.print("  {s: <10} - {s}\n", .{ tool.name, tool.description });
    }

    Output.print("\n", .{});
    Output.bold("Examples:\n", .{});
    Output.print("  zid install bun          # Install latest bun\n", .{});
    Output.print("  zid install zig@0.13.0   # Install specific version\n", .{});
    Output.print("  zid install node rust    # Install multiple\n", .{});
}

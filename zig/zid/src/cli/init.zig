//! Init Command - Create transpiler project

const std = @import("std");
const Output = @import("../output.zig");
const framework = @import("../framework/framework.zig");

pub fn run(alloc: std.mem.Allocator, args: []const []const u8) void {
    const template = if (args.len > 0) args[0] else "basic";
    const name = if (args.len > 1) args[1] else "my-transpiler";

    framework.init(alloc, template, name) catch |e| {
        Output.err("Init failed: {}\n", .{e});
    };
}

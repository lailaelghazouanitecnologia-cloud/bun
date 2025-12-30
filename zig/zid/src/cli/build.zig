//! Build Command - Build transpiler project

const std = @import("std");
const Output = @import("../output.zig");
const framework = @import("../framework/framework.zig");

pub fn run(alloc: std.mem.Allocator, args: []const []const u8) void {
    _ = args;
    framework.build(alloc) catch |e| {
        Output.err("Build failed: {}\n", .{e});
    };
}

pub fn runWatch(alloc: std.mem.Allocator, args: []const []const u8) void {
    _ = args;
    framework.watch(alloc) catch |e| {
        Output.err("Watch failed: {}\n", .{e});
    };
}

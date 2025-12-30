//! Build Command
//!
//! Build the current transpiler project.
//!
//! Usage:
//!   zid build
//!   zid watch

const std = @import("std");
const Output = @import("../output.zig");
const framework = @import("../framework/mod.zig");

pub fn exec(alloc: std.mem.Allocator, args: []const []const u8) void {
    framework.build(alloc, args) catch |err| {
        Output.err("Build failed: {}\n", .{err});
    };
}

pub fn execWatch(alloc: std.mem.Allocator, args: []const []const u8) void {
    framework.watch(alloc, args) catch |err| {
        Output.err("Watch failed: {}\n", .{err});
    };
}

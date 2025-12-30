//! Init Command
//!
//! Initialize a new transpiler project.
//!
//! Usage:
//!   zid init
//!   zid init lua-to-wasm

const std = @import("std");
const Output = @import("../output.zig");
const framework = @import("../framework/mod.zig");

pub fn exec(alloc: std.mem.Allocator, args: []const []const u8) void {
    framework.init(alloc, args) catch |err| {
        Output.err("Init failed: {}\n", .{err});
    };
}

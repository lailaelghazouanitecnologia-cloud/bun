//! Zid - Universal Development Toolkit
//!
//! Main entry point.

const std = @import("std");
const builtin = @import("builtin");
const zid = @import("zid.zig");
const cli = @import("cli.zig");
const Output = @import("output.zig");
const Environment = @import("env.zig");

pub const std_options = .{
    .log_level = if (Environment.isDebug) .debug else .info,
};

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = if (Environment.isDebug) 10 else 0,
    }){};
    defer _ = gpa.deinit();

    cli.run(gpa.allocator()) catch |err| {
        Output.err("error: {}\n", .{err});
        std.process.exit(1);
    };
}

pub const panic = if (Environment.isDebug) zid.panic else std.builtin.default_panic;

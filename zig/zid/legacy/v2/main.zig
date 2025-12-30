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

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = if (Environment.isDebug) 10 else 0,
    }){};
    defer {
        if (Environment.isDebug) {
            _ = gpa.deinit();
        }
    }
    const alloc = gpa.allocator();

    // Run CLI
    cli.Cli.start(alloc) catch |err| {
        if (Environment.isDebug) {
            Output.err("Fatal error: {}\n", .{err});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
        }
        std.process.exit(1);
    };
}

// Override panic handler in debug builds
pub const panic = if (Environment.isDebug) zid.panic else std.builtin.default_panic;

test {
    // Run all tests
    std.testing.refAllDecls(@This());
    _ = @import("zid.zig");
    _ = @import("cli.zig");
    _ = @import("env.zig");
    _ = @import("allocators.zig");
    _ = @import("string.zig");
    _ = @import("output.zig");
    _ = @import("fs.zig");
}

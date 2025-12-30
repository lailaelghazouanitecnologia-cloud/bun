//! Zid - Universal Development Toolkit
//!
//! Root module that exports all public APIs.
//! Import via: const zid = @import("zid");

const std = @import("std");
const builtin = @import("builtin");

// ============ CORE EXPORTS ============

pub const Environment = @import("env.zig");
pub const allocators = @import("allocators.zig");
pub const string = @import("string.zig");
pub const Output = @import("output.zig");
pub const fs = @import("fs.zig");

// ============ SUBSYSTEMS ============

pub const cli = @import("cli.zig");
pub const toolchain = @import("toolchain/mod.zig");
pub const apps = @import("apps/mod.zig");
pub const framework = @import("framework/mod.zig");

// ============ FRAMEWORK RE-EXPORTS ============

pub const Pipeline = framework.Pipeline;
pub const Step = framework.Step;
pub const Metadata = framework.Metadata;

// ============ ALLOCATORS ============

/// Default allocator - use for most allocations
pub const default_allocator = allocators.default_allocator;

/// Arena allocator for temporary/scoped allocations
pub const ArenaAllocator = std.heap.ArenaAllocator;

/// Debug allocator with leak detection (only in debug builds)
pub const debug_allocator = if (Environment.isDebug)
    allocators.debug_allocator
else
    default_allocator;

// ============ GLOBAL STATE ============

/// Thread-local scratch buffer for temporary operations
pub threadlocal var path_buffer: [4096]u8 = undefined;

/// Thread-local string buffer
pub threadlocal var string_buffer: [8192]u8 = undefined;

// ============ VERSION ============

pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

pub const version_string = "0.1.0";

// ============ UTILITIES ============

/// Get Zid home directory (~/.zid or $ZID_HOME)
pub fn getHome(alloc: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("ZID_HOME")) |home| {
        return alloc.dupe(u8, home);
    }
    const home = std.posix.getenv("HOME") orelse
        if (Environment.isWindows) std.posix.getenv("USERPROFILE") orelse "." else "/tmp";
    return std.fmt.allocPrint(alloc, "{s}/.zid", .{home});
}

/// Get bin directory (~/.zid/bin)
pub fn getBinDir(alloc: std.mem.Allocator) ![]const u8 {
    const home = try getHome(alloc);
    defer alloc.free(home);
    return std.fmt.allocPrint(alloc, "{s}/bin", .{home});
}

/// Ensure all Zid directories exist
pub fn ensureDirs(alloc: std.mem.Allocator) !void {
    const home = try getHome(alloc);
    defer alloc.free(home);

    const dirs = [_][]const u8{ "", "/bin", "/toolchain", "/apps", "/cache" };

    for (dirs) |dir| {
        const path = try std.fmt.allocPrint(alloc, "{s}{s}", .{ home, dir });
        defer alloc.free(path);

        std.fs.makeDirAbsolute(path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

// ============ PANIC HANDLER ============

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);

    if (Environment.isDebug) {
        Output.err("PANIC: {s}\n", .{msg});
        if (error_return_trace) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    }

    std.debug.defaultPanic(msg, error_return_trace, ret_addr);
}

// ============ TESTS ============

test {
    std.testing.refAllDecls(@This());
}

test "getHome" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const home = try getHome(arena.allocator());
    try std.testing.expect(home.len > 0);
    try std.testing.expect(std.mem.endsWith(u8, home, ".zid"));
}

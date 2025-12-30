//! Zid - Universal Development Toolkit
//!
//! Root module that exports all public APIs.
//! Import via: const zid = @import("zid");
//!
//! This file follows the same pattern as bun.zig in the Bun codebase.

const std = @import("std");
const builtin = @import("builtin");

// ============ CORE EXPORTS ============

pub const Environment = @import("env.zig");
pub const Output = @import("output.zig");
pub const strings = @import("strings.zig");
pub const fs = @import("fs.zig");

// ============ SUBSYSTEMS ============

pub const cli = @import("cli.zig");
pub const toolchain = @import("toolchain/toolchain.zig");
pub const apps = @import("apps/apps.zig");
pub const framework = @import("framework/framework.zig");

// ============ ALLOCATORS ============

/// Default allocator for general use.
/// In release: c_allocator for performance
/// In debug: GeneralPurposeAllocator for leak detection
pub const default_allocator: std.mem.Allocator = if (Environment.isDebug)
    std.heap.page_allocator
else
    std.heap.c_allocator;

/// Create an arena allocator backed by the default allocator
pub fn arena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(default_allocator);
}

// ============ THREAD-LOCAL BUFFERS ============

/// Thread-local path buffer for temporary path operations
/// Avoids allocations for common operations (critical for performance)
pub threadlocal var path_buf: [4096]u8 = undefined;

/// Thread-local string buffer
pub threadlocal var string_buf: [8192]u8 = undefined;

// ============ VERSION ============

pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};

pub const version_string = "0.1.0";

// ============ PATHS ============

/// Get Zid home directory (~/.zid or $ZID_HOME)
pub fn getHome() []const u8 {
    if (std.posix.getenv("ZID_HOME")) |home| {
        return home;
    }
    const home = std.posix.getenv("HOME") orelse
        if (Environment.isWindows) std.posix.getenv("USERPROFILE") orelse "." else "/tmp";

    // Use threadlocal buffer
    return std.fmt.bufPrint(&path_buf, "{s}/.zid", .{home}) catch ".zid";
}

/// Get bin directory (~/.zid/bin)
pub fn getBinDir() []const u8 {
    const home = getHome();
    return std.fmt.bufPrint(&path_buf, "{s}/bin", .{home}) catch "bin";
}

// ============ PANIC HANDLER ============

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);

    Output.err("PANIC: {s}\n", .{msg});

    if (Environment.isDebug) {
        if (error_return_trace) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    }

    std.debug.defaultPanic(msg, error_return_trace, ret_addr);
}

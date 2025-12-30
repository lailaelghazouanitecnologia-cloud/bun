//! Zid - Universal Development Toolkit
//!
//! Root module that exports all public APIs.
//! Import via: const zid = @import("zid");
//!
//! This file follows the same pattern as bun.zig in the Bun codebase.

const std = @import("std");
const builtin = @import("builtin");

// ============ MISC (Core Patterns) ============

pub const misc = @import("misc/mod.zig");

// Re-export key types at top level
pub const Maybe = misc.Maybe;
pub const Error = misc.Error;
pub const Dispatch = misc.Dispatch;
pub const StateMachine = misc.StateMachine;
pub const bufs = misc.bufs;

// Convenience functions
pub const ok = misc.ok;
pub const err = misc.err;
pub const fail = misc.fail;

// Collections
pub const SmallList = misc.SmallList;
pub const HivePool = misc.HivePool;

// Logger (structured logging with source locations)
pub const Log = misc.Log;
pub const Msg = misc.Msg;
pub const Loc = misc.Loc;
pub const Location = misc.Location;
pub const Range = misc.Range;
pub const ScopedLog = misc.ScopedLog;

// Options (configuration)
pub const Target = misc.Target;
pub const OutputFormat = misc.OutputFormat;
pub const OptLevel = misc.OptLevel;
pub const Toolchain = misc.Toolchain;
pub const BuildOptions = misc.BuildOptions;
pub const GlobalConfig = misc.GlobalConfig;
pub const Features = misc.Features;

// Caching
pub const CacheSet = misc.CacheSet;
pub const FileCache = misc.FileCache;
pub const ContentCache = misc.ContentCache;
pub const LruCache = misc.LruCache;

// Progress tracking
pub const Progress = misc.Progress;
pub const ProgressBar = misc.ProgressBar;
pub const Spinner = misc.Spinner;
pub const TaskTracker = misc.TaskTracker;

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
pub const capsules = @import("capsules/capsules.zig");
pub const patches = @import("patches/patches.zig");
pub const api = @import("api/api.zig");

// ============ ALLOCATORS ============

/// Default allocator for general use.
/// In release: c_allocator for performance
/// In debug: page_allocator for debugging
pub const default_allocator: std.mem.Allocator = if (Environment.isDebug)
    std.heap.page_allocator
else
    std.heap.c_allocator;

/// Create an arena allocator backed by the default allocator
pub fn arena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(default_allocator);
}

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

    return std.fmt.bufPrint(bufs.path(), "{s}/.zid", .{home}) catch ".zid";
}

/// Get bin directory (~/.zid/bin)
pub fn getBinDir() []const u8 {
    const home = getHome();
    return std.fmt.bufPrint(bufs.path2(), "{s}/bin", .{home}) catch "bin";
}

// ============ PANIC HANDLER ============

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @branchHint(.cold);

    Output.err("PANIC: {s}\n", .{msg});

    if (Environment.isDebug) {
        if (error_return_trace) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    }

    std.debug.defaultPanic(msg, error_return_trace, ret_addr);
}

// ============ EXAMPLES ============

/// Example: Using Maybe for error handling
pub fn exampleMaybe() Maybe(i32) {
    const result = std.fmt.parseInt(i32, "123", 10) catch |e| {
        return fail(i32, e, .parse, "");
    };
    return ok(i32, result);
}

/// Example: Using dispatch
pub fn exampleDispatch() void {
    const TestOp = enum { add, sub, mul };

    const Ctx = struct {
        value: i32 = 0,

        pub fn handle_add(self: *@This(), n: i32) !i32 {
            self.value += n;
            return self.value;
        }
        pub fn handle_sub(self: *@This(), n: i32) !i32 {
            self.value -= n;
            return self.value;
        }
        pub fn handle_mul(self: *@This(), n: i32) !i32 {
            self.value *= n;
            return self.value;
        }
    };

    var ctx = Ctx{};
    var vm = Dispatch(TestOp, Ctx, i32).init(&ctx);
    _ = vm.exec(.add, 10);
}

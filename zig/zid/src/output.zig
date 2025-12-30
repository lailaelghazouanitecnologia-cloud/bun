//! Output - Terminal output with colors
//!
//! Follows the pattern from Bun's output.zig

const std = @import("std");
const Environment = @import("env.zig");

const stderr = std.io.getStdErr().writer();
const stdout = std.io.getStdOut().writer();

// ============ COLORS ============

pub const Color = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const cyan = "\x1b[36m";
};

fn useColor() bool {
    return Environment.supportsColor();
}

// ============ OUTPUT FUNCTIONS ============

pub fn print(comptime fmt: []const u8, args: anytype) void {
    stdout.print(fmt, args) catch {};
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (useColor()) {
        stderr.print(Color.red ++ fmt ++ Color.reset, args) catch {};
    } else {
        stderr.print(fmt, args) catch {};
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (useColor()) {
        stderr.print(Color.yellow ++ "warning: " ++ Color.reset ++ fmt, args) catch {};
    } else {
        stderr.print("warning: " ++ fmt, args) catch {};
    }
}

pub fn success(comptime fmt: []const u8, args: anytype) void {
    if (useColor()) {
        stdout.print(Color.green ++ fmt ++ Color.reset, args) catch {};
    } else {
        stdout.print(fmt, args) catch {};
    }
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (useColor()) {
        stdout.print(Color.cyan ++ fmt ++ Color.reset, args) catch {};
    } else {
        stdout.print(fmt, args) catch {};
    }
}

pub fn bold(comptime fmt: []const u8, args: anytype) void {
    if (useColor()) {
        stdout.print(Color.bold ++ fmt ++ Color.reset, args) catch {};
    } else {
        stdout.print(fmt, args) catch {};
    }
}

// ============ SCOPED LOGGING ============

/// Scoped logger - enable with ZID_DEBUG_<SCOPE>=1
pub fn scoped(comptime scope: @Type(.enum_literal)) type {
    return struct {
        pub fn log(comptime fmt: []const u8, args: anytype) void {
            if (comptime !Environment.isDebug) return;

            const scope_name = @tagName(scope);
            const env_key = "ZID_DEBUG_" ++ scope_name;

            if (std.posix.getenv(env_key) == null and
                std.posix.getenv("ZID_DEBUG") == null) return;

            if (useColor()) {
                stderr.print(Color.dim ++ "[" ++ scope_name ++ "] " ++ Color.reset ++ fmt ++ "\n", args) catch {};
            } else {
                stderr.print("[" ++ scope_name ++ "] " ++ fmt ++ "\n", args) catch {};
            }
        }
    };
}

// ============ FORMATTING ============

pub fn formatSize(bytes: u64) struct { val: f64, unit: []const u8 } {
    const units = [_][]const u8{ "B", "KB", "MB", "GB" };
    var size: f64 = @floatFromInt(bytes);
    var i: usize = 0;
    while (size >= 1024 and i < units.len - 1) : (i += 1) {
        size /= 1024;
    }
    return .{ .val = size, .unit = units[i] };
}

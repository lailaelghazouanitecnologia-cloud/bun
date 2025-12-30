//! Output - Terminal output with colors and formatting
//!
//! Usage:
//!   Output.print("Hello {s}\n", .{"World"});
//!   Output.err("Error: {s}\n", .{msg});
//!   Output.success("Done!\n", .{});
//!
//! Scoped logging:
//!   const log = Output.scoped(.CLI);
//!   log.debug("debug message", .{});

const std = @import("std");
const Environment = @import("env.zig");

// ============ WRITERS ============

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

// ============ COLOR SUPPORT ============

var color_enabled: ?bool = null;

pub fn enableColor(enabled: bool) void {
    color_enabled = enabled;
}

fn shouldUseColor() bool {
    if (color_enabled) |enabled| return enabled;
    return Environment.supportsColor();
}

// ============ ANSI CODES ============

pub const Color = enum {
    reset,
    bold,
    dim,
    italic,
    underline,
    // Foreground
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    // Bright foreground
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    pub fn code(self: Color) []const u8 {
        return switch (self) {
            .reset => "\x1b[0m",
            .bold => "\x1b[1m",
            .dim => "\x1b[2m",
            .italic => "\x1b[3m",
            .underline => "\x1b[4m",
            .black => "\x1b[30m",
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .bright_black => "\x1b[90m",
            .bright_red => "\x1b[91m",
            .bright_green => "\x1b[92m",
            .bright_yellow => "\x1b[93m",
            .bright_blue => "\x1b[94m",
            .bright_magenta => "\x1b[95m",
            .bright_cyan => "\x1b[96m",
            .bright_white => "\x1b[97m",
        };
    }
};

// ============ OUTPUT FUNCTIONS ============

/// Print to stdout
pub fn print(comptime fmt: []const u8, args: anytype) void {
    stdout.print(fmt, args) catch {};
}

/// Print to stderr
pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (shouldUseColor()) {
        stderr.print(Color.red.code() ++ fmt ++ Color.reset.code(), args) catch {};
    } else {
        stderr.print(fmt, args) catch {};
    }
}

/// Print warning (yellow)
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (shouldUseColor()) {
        stderr.print(Color.yellow.code() ++ "warning: " ++ Color.reset.code() ++ fmt, args) catch {};
    } else {
        stderr.print("warning: " ++ fmt, args) catch {};
    }
}

/// Print success (green)
pub fn success(comptime fmt: []const u8, args: anytype) void {
    if (shouldUseColor()) {
        stdout.print(Color.green.code() ++ fmt ++ Color.reset.code(), args) catch {};
    } else {
        stdout.print(fmt, args) catch {};
    }
}

/// Print info (cyan)
pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (shouldUseColor()) {
        stdout.print(Color.cyan.code() ++ fmt ++ Color.reset.code(), args) catch {};
    } else {
        stdout.print(fmt, args) catch {};
    }
}

/// Print debug (dim, only in debug builds)
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (comptime !Environment.isDebug) return;

    if (shouldUseColor()) {
        stderr.print(Color.dim.code() ++ "[debug] " ++ fmt ++ Color.reset.code(), args) catch {};
    } else {
        stderr.print("[debug] " ++ fmt, args) catch {};
    }
}

/// Print with specific color
pub fn colored(color: Color, comptime fmt: []const u8, args: anytype) void {
    if (shouldUseColor()) {
        stdout.print(color.code() ++ fmt ++ Color.reset.code(), args) catch {};
    } else {
        stdout.print(fmt, args) catch {};
    }
}

/// Print bold
pub fn bold(comptime fmt: []const u8, args: anytype) void {
    if (shouldUseColor()) {
        stdout.print(Color.bold.code() ++ fmt ++ Color.reset.code(), args) catch {};
    } else {
        stdout.print(fmt, args) catch {};
    }
}

// ============ PROGRESS ============

/// Simple progress indicator
pub const Progress = struct {
    total: usize,
    current: usize = 0,
    message: []const u8,

    pub fn init(total: usize, message: []const u8) Progress {
        return .{ .total = total, .message = message };
    }

    pub fn update(self: *Progress, current: usize) void {
        self.current = current;
        self.render();
    }

    pub fn increment(self: *Progress) void {
        self.current += 1;
        self.render();
    }

    pub fn finish(self: *Progress) void {
        self.current = self.total;
        self.render();
        print("\n", .{});
    }

    fn render(self: Progress) void {
        const percent = if (self.total > 0)
            (self.current * 100) / self.total
        else
            100;

        // Clear line and print progress
        print("\r\x1b[K{s} [{d}/{d}] {d}%", .{
            self.message,
            self.current,
            self.total,
            percent,
        });
    }
};

// ============ SPINNER ============

/// Animated spinner for long operations
pub const Spinner = struct {
    frames: []const []const u8 = &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    current: usize = 0,
    message: []const u8,
    running: bool = false,

    pub fn init(message: []const u8) Spinner {
        return .{ .message = message };
    }

    pub fn start(self: *Spinner) void {
        self.running = true;
        self.render();
    }

    pub fn tick(self: *Spinner) void {
        if (!self.running) return;
        self.current = (self.current + 1) % self.frames.len;
        self.render();
    }

    pub fn stop(self: *Spinner) void {
        self.running = false;
        print("\r\x1b[K", .{}); // Clear line
    }

    pub fn success_msg(self: *Spinner, msg: []const u8) void {
        self.stop();
        success("{s} {s}\n", .{ "✓", msg });
    }

    pub fn fail(self: *Spinner, msg: []const u8) void {
        self.stop();
        err("{s} {s}\n", .{ "✗", msg });
    }

    fn render(self: Spinner) void {
        if (shouldUseColor()) {
            print("\r{s}{s} {s}", .{ Color.cyan.code(), self.frames[self.current], self.message });
        } else {
            print("\r{s} {s}", .{ self.frames[self.current], self.message });
        }
    }
};

// ============ SCOPED LOGGING ============

/// Log scope for module-specific debugging
pub const Scope = enum {
    CLI,
    Toolchain,
    Apps,
    Framework,
    Pipeline,
    FS,
    HTTP,
    Other,
};

/// Create a scoped logger
/// Enable with ZID_DEBUG_<SCOPE>=1 environment variable
pub fn scoped(comptime scope: Scope) type {
    const scope_name = @tagName(scope);

    return struct {
        pub fn log(comptime fmt: []const u8, args: anytype) void {
            if (comptime !Environment.isDebug) return;

            // Check if this scope is enabled
            const env_key = "ZID_DEBUG_" ++ scope_name;
            if (std.posix.getenv(env_key) == null and
                std.posix.getenv("ZID_DEBUG_ALL") == null)
            {
                return;
            }

            if (shouldUseColor()) {
                stderr.print(
                    Color.dim.code() ++ "[" ++ scope_name ++ "] " ++ Color.reset.code() ++ fmt ++ "\n",
                    args,
                ) catch {};
            } else {
                stderr.print("[" ++ scope_name ++ "] " ++ fmt ++ "\n", args) catch {};
            }
        }

        pub const dbg = log;
    };
}

// ============ FORMATTING HELPERS ============

/// Format file size
pub fn formatSize(bytes: u64) struct { value: f64, unit: []const u8 } {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var size: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (size >= 1024 and unit_idx < units.len - 1) {
        size /= 1024;
        unit_idx += 1;
    }

    return .{ .value = size, .unit = units[unit_idx] };
}

/// Format duration
pub fn formatDuration(ns: u64) struct { value: f64, unit: []const u8 } {
    if (ns < 1000) return .{ .value = @floatFromInt(ns), .unit = "ns" };
    if (ns < 1_000_000) return .{ .value = @as(f64, @floatFromInt(ns)) / 1000, .unit = "µs" };
    if (ns < 1_000_000_000) return .{ .value = @as(f64, @floatFromInt(ns)) / 1_000_000, .unit = "ms" };
    return .{ .value = @as(f64, @floatFromInt(ns)) / 1_000_000_000, .unit = "s" };
}

// ============ TESTS ============

test "formatSize" {
    const result = formatSize(1536);
    try std.testing.expectEqual(@as(f64, 1.5), result.value);
    try std.testing.expectEqualStrings("KB", result.unit);
}

test "formatDuration" {
    const result = formatDuration(1_500_000);
    try std.testing.expectEqual(@as(f64, 1.5), result.value);
    try std.testing.expectEqualStrings("ms", result.unit);
}

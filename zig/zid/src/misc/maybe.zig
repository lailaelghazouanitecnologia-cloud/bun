//! Maybe - Generic error/result union
//!
//! Pattern from Bun's SystemError.Maybe(T)
//! Carries either an error with context or a success value.
//!
//! Usage:
//!   fn readFile(path: []const u8) Maybe([]u8) {
//!       const file = std.fs.openFile(path, .{}) catch |e| {
//!           return .{ .err = Error.from(e, .read_file, path) };
//!       };
//!       return .{ .ok = file.readToEndAlloc(...) };
//!   }
//!
//!   switch (readFile("test.txt")) {
//!       .ok => |data| { ... },
//!       .err => |e| { e.print(); },
//!   }

const std = @import("std");

/// Generic Maybe type - either error or result
pub fn Maybe(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: Error,

        const Self = @This();

        pub fn unwrap(self: Self) T {
            return switch (self) {
                .ok => |v| v,
                .err => |e| {
                    e.print();
                    @panic("unwrap on error");
                },
            };
        }

        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .ok => |v| v,
                .err => default,
            };
        }

        pub fn isOk(self: Self) bool {
            return self == .ok;
        }

        pub fn isErr(self: Self) bool {
            return self == .err;
        }

        pub fn map(self: Self, comptime f: fn (T) T) Self {
            return switch (self) {
                .ok => |v| .{ .ok = f(v) },
                .err => |e| .{ .err = e },
            };
        }
    };
}

/// Error with full context
pub const Error = struct {
    code: Code,
    errno: i32 = 0,
    message: []const u8 = "",
    path: []const u8 = "",
    syscall: []const u8 = "",
    step: Step = .unknown,

    pub const Code = enum(u16) {
        ok = 0,
        // System
        not_found = 1,
        permission_denied = 2,
        io_error = 3,
        out_of_memory = 4,
        // Parse
        syntax_error = 100,
        unexpected_token = 101,
        invalid_utf8 = 102,
        // Toolchain
        tool_not_found = 200,
        version_not_found = 201,
        download_failed = 202,
        // App
        app_not_found = 300,
        build_failed = 301,
        // Generic
        unknown = 999,
    };

    pub const Step = enum {
        unknown,
        // IO
        read_file,
        write_file,
        open_dir,
        // Parse
        lex,
        parse,
        emit,
        // Build
        resolve,
        compile,
        link,
        // Network
        download,
        extract,
    };

    /// Create error from std error
    pub fn from(err: anyerror, step: Step, path: []const u8) Error {
        return .{
            .code = mapError(err),
            .step = step,
            .path = path,
            .message = @errorName(err),
        };
    }

    /// Create with message
    pub fn withMessage(code: Code, comptime fmt: []const u8, args: anytype) Error {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch "error";
        return .{ .code = code, .message = msg };
    }

    /// Print error
    pub fn print(self: Error) void {
        const stderr = std.io.getStdErr().writer();
        stderr.print("\x1b[31merror\x1b[0m[{s}]: {s}", .{
            @tagName(self.code),
            self.message,
        }) catch {};
        if (self.path.len > 0) {
            stderr.print(" ({s})", .{self.path}) catch {};
        }
        if (self.step != .unknown) {
            stderr.print(" at {s}", .{@tagName(self.step)}) catch {};
        }
        stderr.print("\n", .{}) catch {};
    }

    fn mapError(err: anyerror) Code {
        return switch (err) {
            error.FileNotFound => .not_found,
            error.AccessDenied => .permission_denied,
            error.OutOfMemory => .out_of_memory,
            else => .unknown,
        };
    }
};

/// Convenience: ok result
pub fn ok(comptime T: type, value: T) Maybe(T) {
    return .{ .ok = value };
}

/// Convenience: error result
pub fn err(comptime T: type, e: Error) Maybe(T) {
    return .{ .err = e };
}

/// Convenience: error from std error
pub fn fromError(comptime T: type, e: anyerror, step: Error.Step, path: []const u8) Maybe(T) {
    return .{ .err = Error.from(e, step, path) };
}

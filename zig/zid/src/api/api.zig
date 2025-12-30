//! Zid Public API
//!
//! API para crear scripts Zig potentes. Ejemplo:
//!
//! ```zig
//! const zid = @import("zid");
//!
//! pub fn main() !void {
//!     // Filesystem
//!     try zid.fs.copy("src/", "dist/");
//!     try zid.fs.write("config.json", data);
//!
//!     // Search
//!     const files = try zid.search.glob("**/*.ts");
//!     const matches = try zid.search.grep(files, "TODO");
//!
//!     // Shell
//!     const result = try zid.shell.exec("npm", .{"install"});
//!     try zid.shell.pipe("cat file.txt", "grep pattern");
//!
//!     // Templates
//!     try zid.template.create("svelte-app", "my-project");
//!
//!     // HTTP
//!     const body = try zid.http.get("https://api.example.com");
//!
//!     // Toolchains
//!     try zid.toolchain.run("bun", .{"build"});
//! }
//! ```

const std = @import("std");

// ============ CORE EXPORTS ============

pub const fs = @import("fs.zig");
pub const search = @import("search.zig");
pub const shell = @import("shell.zig");
pub const template = @import("template.zig");
pub const http = @import("http.zig");
pub const json = @import("json.zig");

// ============ ZID INTERNALS ============

const zid = @import("../zid.zig");
pub const toolchain = @import("../toolchain/toolchain.zig");
pub const capsules = @import("../capsules/capsules.zig");
pub const Output = zid.Output;
pub const Maybe = zid.Maybe;
pub const ok = zid.ok;
pub const err = zid.err;

// ============ COMMON TYPES ============

pub const Path = []const u8;
pub const Bytes = []const u8;

pub const Error = struct {
    code: Code,
    message: []const u8,
    path: ?[]const u8 = null,

    pub const Code = enum {
        not_found,
        permission_denied,
        already_exists,
        invalid_path,
        io_error,
        network_error,
        parse_error,
        timeout,
        unknown,
    };
};

pub const Result = union(enum) {
    ok: void,
    err: Error,
};

// ============ CONTEXT ============

/// Script context - provides allocator and config
pub const Context = struct {
    allocator: std.mem.Allocator,
    cwd: []const u8,
    args: []const []const u8,
    env: std.process.EnvMap,

    pub fn init(allocator: std.mem.Allocator) !Context {
        return .{
            .allocator = allocator,
            .cwd = try std.fs.cwd().realpathAlloc(allocator, "."),
            .args = try std.process.argsAlloc(allocator),
            .env = try std.process.getEnvMap(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.allocator.free(self.cwd);
        std.process.argsFree(self.allocator, self.args);
        self.env.deinit();
    }

    pub fn getArg(self: *Context, index: usize) ?[]const u8 {
        if (index < self.args.len) return self.args[index];
        return null;
    }

    pub fn getEnv(self: *Context, key: []const u8) ?[]const u8 {
        return self.env.get(key);
    }
};

// ============ HELPERS ============

/// Print to stdout
pub fn print(comptime fmt: []const u8, args: anytype) void {
    Output.print(fmt, args);
}

/// Print error to stderr
pub fn printErr(comptime fmt: []const u8, args: anytype) void {
    Output.err(fmt, args);
}

/// Print success message
pub fn success(comptime fmt: []const u8, args: anytype) void {
    Output.success(fmt, args);
}

/// Print warning
pub fn warn(comptime fmt: []const u8, args: anytype) void {
    Output.warn(fmt, args);
}

/// Exit with code
pub fn exit(code: u8) noreturn {
    std.process.exit(code);
}

/// Get home directory
pub fn home() []const u8 {
    return zid.getHome();
}

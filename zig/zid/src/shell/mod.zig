//! Zid Shell - Fast embedded shell
//!
//! A powerful shell implementation with:
//! - Builtins: echo, cd, pwd, ls, cat, mkdir, rm, cp, mv, etc.
//! - Pipes: cmd1 | cmd2 | cmd3
//! - Redirects: > >> < 2> &>
//! - Variables: $VAR ${VAR}
//! - Globs: *.zig file?.txt
//! - Operators: && || ; &
//!
//! ## Usage
//!
//! ```zig
//! const zid = @import("zid");
//!
//! // Execute a command
//! var shell = try zid.shell.Interpreter.init(allocator);
//! defer shell.deinit();
//!
//! const result = try shell.exec("ls -la | grep .zig");
//! print("{s}", .{result.stdout});
//!
//! // Run interactive REPL
//! try zid.shell.repl(allocator);
//! ```

const std = @import("std");

// Core modules
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const builtins = @import("builtins.zig");
pub const interpreter = @import("interpreter.zig");
pub const completions = @import("completions.zig");

// Re-export key types
pub const Lexer = lexer.Lexer;
pub const Token = lexer.Token;
pub const Parser = parser.Parser;
pub const Node = parser.Node;
pub const Interpreter = interpreter.Interpreter;
pub const ExecResult = interpreter.ExecResult;
pub const ExitCode = interpreter.ExitCode;

// Builtins
pub const Builtin = builtins.Builtin;
pub const Context = builtins.Context;
pub const isBuiltin = builtins.isBuiltin;
pub const getBuiltin = builtins.get;

// Completions
pub const ShellType = completions.ShellType;
pub const detectShell = completions.detectShell;
pub const generateCompletions = completions.generate;
pub const installCompletions = completions.install;

// ============ CONVENIENCE API ============

/// Execute a shell command and return the result
pub fn exec(allocator: std.mem.Allocator, cmd: []const u8) !ExecResult {
    var interp = try Interpreter.init(allocator);
    defer interp.deinit();
    return try interp.exec(cmd);
}

/// Run a command, check for success, return stdout
pub fn run(allocator: std.mem.Allocator, cmd: []const u8) ![]const u8 {
    const result = try exec(allocator, cmd);
    if (result.exit_code != 0) {
        return error.CommandFailed;
    }
    return result.stdout;
}

/// Run a command silently, just return exit code
pub fn system(allocator: std.mem.Allocator, cmd: []const u8) !u8 {
    const result = try exec(allocator, cmd);
    return result.exit_code;
}

/// Start interactive REPL
pub const repl = interpreter.repl;

/// Check if a command exists
pub fn hasCommand(allocator: std.mem.Allocator, cmd: []const u8) bool {
    if (isBuiltin(cmd)) return true;

    const path_env = std.posix.getenv("PATH") orelse return false;
    var paths = std.mem.splitScalar(u8, path_env, ':');

    while (paths.next()) |dir| {
        const full = std.fs.path.join(allocator, &.{ dir, cmd }) catch continue;
        defer allocator.free(full);
        std.fs.accessAbsolute(full, .{ .mode = .execute_only }) catch continue;
        return true;
    }

    return false;
}

/// Get shell environment variable
pub fn getenv(key: []const u8) ?[]const u8 {
    return std.posix.getenv(key);
}

/// Get current working directory
pub fn cwd(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.posix.getcwd(&buf) catch return error.CwdError;
    return allocator.dupe(u8, path);
}

// ============ TESTS ============

test {
    _ = lexer;
    _ = parser;
    _ = builtins;
    _ = interpreter;
    _ = completions;
}

test "exec simple command" {
    const result = try exec(std.testing.allocator, "echo test");
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("test\n", result.stdout);
}

test "run returns stdout" {
    const output = try run(std.testing.allocator, "echo hello");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("hello\n", output);
}

test "hasCommand" {
    try std.testing.expect(hasCommand(std.testing.allocator, "echo")); // builtin
    try std.testing.expect(hasCommand(std.testing.allocator, "cd")); // builtin
}

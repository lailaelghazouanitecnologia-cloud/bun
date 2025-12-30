//! Shell API
//!
//! Ejecutar comandos y pipelines.
//!
//! ```zig
//! const zid = @import("zid");
//!
//! // Ejecutar comando
//! const result = try zid.shell.exec("ls", .{"-la"});
//! print("stdout: {s}\n", .{result.stdout});
//!
//! // Ejecutar con shell
//! try zid.shell.sh("echo 'hello' | grep 'ell'");
//!
//! // Background
//! const proc = try zid.shell.spawn("npm", .{"run", "dev"});
//! defer proc.kill();
//!
//! // Toolchain (usa zid's toolchains si disponible)
//! try zid.shell.run("bun", .{"build"});
//! ```

const std = @import("std");
const builtin = @import("builtin");

// ============ EXEC ============

/// Execute command and wait for completion
pub fn exec(allocator: std.mem.Allocator, cmd: []const u8, args: anytype) !ExecResult {
    return execOpts(allocator, cmd, args, .{});
}

/// Execute with options
pub fn execOpts(
    allocator: std.mem.Allocator,
    cmd: []const u8,
    args: anytype,
    opts: ExecOptions,
) !ExecResult {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append(cmd);

    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info == .Struct and args_info.Struct.is_tuple) {
        inline for (args) |arg| {
            try argv.append(arg);
        }
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.cwd = if (opts.cwd) |c| .{ .cwd = c } else null;

    if (opts.capture_stdout) {
        child.stdout_behavior = .Pipe;
    }
    if (opts.capture_stderr) {
        child.stderr_behavior = .Pipe;
    }

    try child.spawn();

    var stdout_data: []u8 = &.{};
    var stderr_data: []u8 = &.{};

    if (opts.capture_stdout) {
        stdout_data = try child.stdout.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    }
    if (opts.capture_stderr) {
        stderr_data = try child.stderr.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
    }

    const term = try child.wait();

    return .{
        .stdout = stdout_data,
        .stderr = stderr_data,
        .exit_code = if (term == .Exited) term.Exited else 1,
        .success = term == .Exited and term.Exited == 0,
    };
}

pub const ExecOptions = struct {
    cwd: ?[]const u8 = null,
    capture_stdout: bool = true,
    capture_stderr: bool = true,
    timeout_ms: ?u32 = null,
    env: ?*const std.process.EnvMap = null,
};

pub const ExecResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
    success: bool,

    pub fn output(self: ExecResult) []const u8 {
        return self.stdout;
    }
};

// ============ SHELL ============

/// Execute shell command (uses sh -c)
pub fn sh(allocator: std.mem.Allocator, command: []const u8) !ExecResult {
    const shell_cmd = if (builtin.os.tag == .windows) "cmd" else "sh";
    const shell_arg = if (builtin.os.tag == .windows) "/c" else "-c";

    return exec(allocator, shell_cmd, .{ shell_arg, command });
}

/// Execute and check success
pub fn run(allocator: std.mem.Allocator, cmd: []const u8, args: anytype) !void {
    const result = try exec(allocator, cmd, args);
    if (!result.success) {
        return error.CommandFailed;
    }
}

// ============ SPAWN ============

/// Spawn process in background
pub fn spawn(allocator: std.mem.Allocator, cmd: []const u8, args: anytype) !Process {
    var argv = std.ArrayList([]const u8).init(allocator);

    try argv.append(cmd);

    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    if (args_info == .Struct and args_info.Struct.is_tuple) {
        inline for (args) |arg| {
            try argv.append(arg);
        }
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    return .{
        .child = child,
        .allocator = allocator,
    };
}

pub const Process = struct {
    child: std.process.Child,
    allocator: std.mem.Allocator,

    /// Kill the process
    pub fn kill(self: *Process) void {
        _ = self.child.kill() catch {};
    }

    /// Wait for completion
    pub fn wait(self: *Process) !u8 {
        const term = try self.child.wait();
        return if (term == .Exited) term.Exited else 1;
    }

    /// Check if still running
    pub fn isRunning(self: *Process) bool {
        // Try to get exit status without blocking
        const result = self.child.wait() catch return true;
        return result != .Exited;
    }

    /// Read stdout
    pub fn readStdout(self: *Process) ![]u8 {
        if (self.child.stdout) |stdout| {
            return stdout.reader().readAllAlloc(self.allocator, 10 * 1024 * 1024);
        }
        return &.{};
    }
};

// ============ PIPE ============

/// Pipe output from one command to another
pub fn pipe(allocator: std.mem.Allocator, cmd1: []const u8, cmd2: []const u8) !ExecResult {
    // Execute first command
    const result1 = try sh(allocator, cmd1);
    if (!result1.success) {
        return result1;
    }

    // Create temp file with output
    const tmp = "/tmp/zid-pipe-tmp";
    {
        const file = try std.fs.createFileAbsolute(tmp, .{});
        defer file.close();
        try file.writeAll(result1.stdout);
    }
    defer std.fs.deleteFileAbsolute(tmp) catch {};

    // Execute second command with input
    const full_cmd = try std.fmt.allocPrint(allocator, "cat {s} | {s}", .{ tmp, cmd2 });
    defer allocator.free(full_cmd);

    return sh(allocator, full_cmd);
}

// ============ WHICH ============

/// Find command in PATH
pub fn which(allocator: std.mem.Allocator, cmd: []const u8) !?[]const u8 {
    const path_env = std.posix.getenv("PATH") orelse return null;

    var paths = std.mem.splitScalar(u8, path_env, ':');
    while (paths.next()) |dir| {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, cmd }) catch continue;

        std.fs.accessAbsolute(full_path, .{ .mode = .execute_only }) catch continue;
        return try allocator.dupe(u8, full_path);
    }

    return null;
}

/// Check if command exists in PATH
pub fn hasCommand(cmd: []const u8) bool {
    const path_env = std.posix.getenv("PATH") orelse return false;

    var paths = std.mem.splitScalar(u8, path_env, ':');
    while (paths.next()) |dir| {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, cmd }) catch continue;

        std.fs.accessAbsolute(full_path, .{ .mode = .execute_only }) catch continue;
        return true;
    }

    return false;
}

// ============ ENV ============

/// Get environment variable
pub fn getenv(key: []const u8) ?[]const u8 {
    return std.posix.getenv(key);
}

/// Get current working directory
pub fn cwd(allocator: std.mem.Allocator) ![]const u8 {
    return std.fs.cwd().realpathAlloc(allocator, ".");
}

/// Change directory
pub fn cd(path: []const u8) !void {
    try std.posix.chdir(path);
}

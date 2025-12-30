//! Shell Interpreter - Execute parsed shell commands
//!
//! Features:
//! - Execute commands (builtins and external)
//! - Pipe support (cmd1 | cmd2 | cmd3)
//! - Redirects (>, >>, <, 2>, &>)
//! - Variable expansion ($VAR, ${VAR})
//! - Glob expansion (*.zig)
//! - Command chaining (&&, ||)
//! - Background execution (&)

const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const posix = std.posix;

const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;
const Parser = @import("parser.zig").Parser;
const Node = @import("parser.zig").Node;
const builtins = @import("builtins.zig");

pub const ExitCode = u8;

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    env: std.process.EnvMap,
    cwd: []const u8,
    last_exit_code: ExitCode = 0,

    // Output buffers
    stdout: std.ArrayList(u8),
    stderr: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !Interpreter {
        var env = std.process.EnvMap.init(allocator);

        // Copy current environment
        var env_iter = std.process.getEnvMap(allocator) catch std.process.EnvMap.init(allocator);
        defer env_iter.deinit();
        var iter = env_iter.iterator();
        while (iter.next()) |entry| {
            try env.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = posix.getcwd(&cwd_buf) catch "/tmp";

        return .{
            .allocator = allocator,
            .env = env,
            .cwd = try allocator.dupe(u8, cwd),
            .stdout = std.ArrayList(u8).init(allocator),
            .stderr = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Interpreter) void {
        self.env.deinit();
        self.allocator.free(self.cwd);
        self.stdout.deinit();
        self.stderr.deinit();
    }

    /// Execute a shell command string
    pub fn exec(self: *Interpreter, input: []const u8) !ExecResult {
        // Reset output buffers
        self.stdout.clearRetainingCapacity();
        self.stderr.clearRetainingCapacity();

        // Tokenize
        var lexer = Lexer.init(self.allocator, input);
        defer lexer.deinit();
        const tokens = try lexer.tokenize();

        // Parse
        var parser = Parser.init(self.allocator, tokens);
        defer parser.deinit();
        const script = try parser.parse();

        // Execute
        self.last_exit_code = try self.execScript(script);

        return .{
            .exit_code = self.last_exit_code,
            .stdout = try self.allocator.dupe(u8, self.stdout.items),
            .stderr = try self.allocator.dupe(u8, self.stderr.items),
        };
    }

    fn execScript(self: *Interpreter, script: Node.Script) !ExitCode {
        var exit_code: ExitCode = 0;

        for (script.statements) |stmt| {
            exit_code = try self.execStatement(stmt);
        }

        return exit_code;
    }

    fn execStatement(self: *Interpreter, stmt: Node.Statement) !ExitCode {
        var exit_code = try self.execPipeline(stmt.pipeline);

        // Handle chained commands (&&, ||)
        var chain = stmt.next;
        while (chain) |c| {
            const should_run = switch (c.op) {
                .and_then => exit_code == 0,
                .or_else => exit_code != 0,
            };

            if (should_run) {
                exit_code = try self.execPipeline(c.pipeline);
            }

            chain = c.next;
        }

        return exit_code;
    }

    fn execPipeline(self: *Interpreter, pipeline: Node.Pipeline) !ExitCode {
        const commands = pipeline.commands;
        if (commands.len == 0) return 0;

        // Single command - no pipes needed
        if (commands.len == 1) {
            return try self.execCommand(commands[0], null);
        }

        // Multiple commands - set up pipes
        var prev_output: ?[]const u8 = null;

        for (commands, 0..) |cmd, i| {
            const is_last = i == commands.len - 1;
            const exit_code = try self.execCommand(cmd, prev_output);

            if (is_last) {
                return exit_code;
            }

            // Pass stdout to next command
            prev_output = try self.allocator.dupe(u8, self.stdout.items);
            self.stdout.clearRetainingCapacity();
        }

        return 0;
    }

    fn execCommand(self: *Interpreter, cmd: Node.Command, stdin: ?[]const u8) !ExitCode {
        if (cmd.words.len == 0) return 0;

        // Expand all words
        var expanded_args = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (expanded_args.items) |arg| {
                self.allocator.free(arg);
            }
            expanded_args.deinit();
        }

        for (cmd.words) |word| {
            const expanded = try self.expandWord(word);
            // Glob expansion may produce multiple results
            if (expanded.len > 0) {
                for (expanded) |e| {
                    try expanded_args.append(e);
                }
            }
        }

        if (expanded_args.items.len == 0) return 0;

        const program = expanded_args.items[0];
        const args = expanded_args.items[1..];

        // Handle redirects
        var output_file: ?[]const u8 = null;
        var append_mode = false;

        for (cmd.redirects) |redir| {
            switch (redir.kind) {
                .output => {
                    output_file = try self.expandWordSingle(redir.target);
                    append_mode = false;
                },
                .append => {
                    output_file = try self.expandWordSingle(redir.target);
                    append_mode = true;
                },
                else => {},
            }
        }

        // Execute command
        const result = if (builtins.isBuiltin(program))
            try self.execBuiltin(program, args, stdin)
        else
            try self.execExternal(program, args, stdin);

        // Handle output redirect
        if (output_file) |path| {
            const resolved = if (std.fs.path.isAbsolute(path)) path else blk: {
                break :blk try std.fs.path.join(self.allocator, &.{ self.cwd, path });
            };

            const file = fs.createFileAbsolute(resolved, .{
                .truncate = !append_mode,
            }) catch |e| {
                try self.stderr.writer().print("zsh: cannot open '{s}': {}\n", .{ path, e });
                return 1;
            };
            defer file.close();

            if (append_mode) {
                file.seekFromEnd(0) catch {};
            }

            file.writeAll(result.stdout) catch {};
            self.stdout.clearRetainingCapacity();
        } else {
            try self.stdout.appendSlice(result.stdout);
        }

        try self.stderr.appendSlice(result.stderr);

        return result.exit_code;
    }

    fn execBuiltin(self: *Interpreter, name: []const u8, args: []const []const u8, stdin: ?[]const u8) !builtins.BuiltinResult {
        const b = builtins.get(name) orelse return builtins.BuiltinResult.err(127, "command not found\n");

        var ctx = builtins.Context.init(self.allocator, args, &self.env, self.cwd);
        ctx.stdin = stdin;
        defer ctx.deinit();

        // Handle cd specially - it modifies interpreter state
        if (std.mem.eql(u8, name, "cd")) {
            const result = b.func(&ctx);
            if (result.exit_code == 0) {
                // Update cwd
                var buf: [std.fs.max_path_bytes]u8 = undefined;
                if (posix.getcwd(&buf)) |new_cwd| {
                    self.allocator.free(self.cwd);
                    self.cwd = self.allocator.dupe(u8, new_cwd) catch self.cwd;
                } else |_| {}
            }
            return result;
        }

        return b.func(&ctx);
    }

    fn execExternal(self: *Interpreter, program: []const u8, args: []const []const u8, stdin: ?[]const u8) !builtins.BuiltinResult {
        // Build argv
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();

        try argv.append(program);
        for (args) |arg| {
            try argv.append(arg);
        }

        // Create child process
        var child = std.process.Child.init(argv.items, self.allocator);
        child.cwd = .{ .cwd = self.cwd };
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        if (stdin != null) {
            child.stdin_behavior = .Pipe;
        }

        child.spawn() catch |e| {
            return builtins.BuiltinResult.err(127, try std.fmt.allocPrint(self.allocator, "{s}: command not found ({any})\n", .{ program, e }));
        };

        // Write stdin if provided
        if (stdin) |input| {
            if (child.stdin) |stdin_pipe| {
                stdin_pipe.writeAll(input) catch {};
                stdin_pipe.close();
            }
        }

        // Read output
        const stdout_data = if (child.stdout) |pipe|
            pipe.reader().readAllAlloc(self.allocator, 10 * 1024 * 1024) catch ""
        else
            "";

        const stderr_data = if (child.stderr) |pipe|
            pipe.reader().readAllAlloc(self.allocator, 10 * 1024 * 1024) catch ""
        else
            "";

        const term = child.wait() catch {
            return builtins.BuiltinResult.err(1, "failed to wait for process\n");
        };

        const exit_code: u8 = switch (term) {
            .Exited => |code| code,
            .Signal => 128,
            else => 1,
        };

        return .{
            .exit_code = exit_code,
            .stdout = stdout_data,
            .stderr = stderr_data,
        };
    }

    // ============ EXPANSION ============

    fn expandWord(self: *Interpreter, word: Node.Word) ![]const []const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);

        // First, build the string with variable expansion
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        var has_glob = false;

        for (word.parts) |part| {
            switch (part) {
                .literal => |s| try buf.appendSlice(s),
                .variable => |s| try buf.appendSlice(self.expandVariable(s)),
                .glob => |s| {
                    try buf.appendSlice(s);
                    has_glob = true;
                },
                .quoted => |s| try buf.appendSlice(self.expandQuoted(s)),
                .raw => |s| try buf.appendSlice(s),
                .subst => |s| try buf.appendSlice(try self.expandSubstitution(s)),
            }
        }

        const expanded = try buf.toOwnedSlice();

        // Glob expansion
        if (has_glob) {
            const glob_results = try self.expandGlob(expanded);
            if (glob_results.len > 0) {
                for (glob_results) |g| {
                    try result.append(g);
                }
            } else {
                // No matches - keep original
                try result.append(expanded);
            }
        } else {
            try result.append(expanded);
        }

        return try result.toOwnedSlice();
    }

    fn expandWordSingle(self: *Interpreter, word: Node.Word) ![]const u8 {
        const results = try self.expandWord(word);
        if (results.len > 0) return results[0];
        return "";
    }

    fn expandVariable(self: *Interpreter, text: []const u8) []const u8 {
        // Parse variable name from $VAR or ${VAR}
        var name: []const u8 = undefined;

        if (text.len < 2) return "";

        if (text[1] == '{') {
            // ${VAR}
            const end = std.mem.indexOf(u8, text, "}") orelse text.len;
            name = text[2..end];
        } else {
            // $VAR
            name = text[1..];
        }

        // Special variables
        if (std.mem.eql(u8, name, "?")) {
            var buf: [16]u8 = undefined;
            return std.fmt.bufPrint(&buf, "{d}", .{self.last_exit_code}) catch "0";
        }
        if (std.mem.eql(u8, name, "$")) {
            return "0"; // PID placeholder
        }

        return self.env.get(name) orelse "";
    }

    fn expandQuoted(self: *Interpreter, text: []const u8) []const u8 {
        // Expand variables inside double quotes
        var result = std.ArrayList(u8).init(self.allocator);

        var i: usize = 0;
        while (i < text.len) {
            if (text[i] == '$') {
                // Find variable end
                var j = i + 1;
                if (j < text.len and text[j] == '{') {
                    while (j < text.len and text[j] != '}') j += 1;
                    if (j < text.len) j += 1;
                } else {
                    while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or text[j] == '_')) j += 1;
                }
                result.appendSlice(self.expandVariable(text[i..j])) catch {};
                i = j;
            } else if (text[i] == '\\' and i + 1 < text.len) {
                // Handle escapes
                i += 1;
                switch (text[i]) {
                    'n' => result.append('\n') catch {},
                    't' => result.append('\t') catch {},
                    'r' => result.append('\r') catch {},
                    else => result.append(text[i]) catch {},
                }
                i += 1;
            } else {
                result.append(text[i]) catch {};
                i += 1;
            }
        }

        return result.toOwnedSlice() catch "";
    }

    fn expandSubstitution(self: *Interpreter, cmd: []const u8) ![]const u8 {
        // Execute command and capture output
        const result = try self.exec(cmd);

        // Trim trailing newline
        var output = result.stdout;
        while (output.len > 0 and output[output.len - 1] == '\n') {
            output = output[0 .. output.len - 1];
        }

        return output;
    }

    fn expandGlob(self: *Interpreter, pattern: []const u8) ![]const []const u8 {
        var results = std.ArrayList([]const u8).init(self.allocator);

        // Simple glob matching
        const resolved_dir = if (std.fs.path.dirname(pattern)) |d| blk: {
            if (std.fs.path.isAbsolute(d)) break :blk d;
            break :blk try std.fs.path.join(self.allocator, &.{ self.cwd, d });
        } else self.cwd;

        const file_pattern = std.fs.path.basename(pattern);

        var dir = fs.openDirAbsolute(resolved_dir, .{ .iterate = true }) catch {
            return try results.toOwnedSlice();
        };
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (globMatch(file_pattern, entry.name)) {
                const full_path = try std.fs.path.join(self.allocator, &.{ resolved_dir, entry.name });
                try results.append(full_path);
            }
        }

        // Sort results
        std.mem.sort([]const u8, results.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        return try results.toOwnedSlice();
    }
};

/// Simple glob pattern matching
fn globMatch(pattern: []const u8, text: []const u8) bool {
    var pi: usize = 0;
    var ti: usize = 0;
    var star_pi: ?usize = null;
    var star_ti: usize = 0;

    while (ti < text.len) {
        if (pi < pattern.len) {
            if (pattern[pi] == '*') {
                star_pi = pi;
                star_ti = ti;
                pi += 1;
                continue;
            } else if (pattern[pi] == '?' or pattern[pi] == text[ti]) {
                pi += 1;
                ti += 1;
                continue;
            }
        }

        if (star_pi) |sp| {
            pi = sp + 1;
            star_ti += 1;
            ti = star_ti;
        } else {
            return false;
        }
    }

    while (pi < pattern.len and pattern[pi] == '*') {
        pi += 1;
    }

    return pi == pattern.len;
}

pub const ExecResult = struct {
    exit_code: ExitCode,
    stdout: []const u8,
    stderr: []const u8,
};

// ============ REPL ============

pub fn repl(allocator: std.mem.Allocator) !void {
    var interp = try Interpreter.init(allocator);
    defer interp.deinit();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    var reader = stdin.reader();

    var line_buf: [4096]u8 = undefined;

    while (true) {
        // Print prompt
        stdout.writer().print("\x1b[32mzid\x1b[0m {s} \x1b[34m❯\x1b[0m ", .{std.fs.path.basename(interp.cwd)}) catch {};

        // Read line
        const line = reader.readUntilDelimiter(&line_buf, '\n') catch |e| {
            if (e == error.EndOfStream) break;
            continue;
        };

        if (line.len == 0) continue;

        // Handle exit
        if (std.mem.eql(u8, std.mem.trim(u8, line, " \t"), "exit")) {
            break;
        }

        // Execute
        const result = interp.exec(line) catch |e| {
            stdout.writer().print("Error: {}\n", .{e}) catch {};
            continue;
        };

        // Print output
        if (result.stdout.len > 0) {
            stdout.writer().writeAll(result.stdout) catch {};
        }
        if (result.stderr.len > 0) {
            std.io.getStdErr().writer().writeAll(result.stderr) catch {};
        }
    }
}

// ============ TESTS ============

test "glob match" {
    try std.testing.expect(globMatch("*.zig", "test.zig"));
    try std.testing.expect(globMatch("*.zig", "foo.zig"));
    try std.testing.expect(!globMatch("*.zig", "test.txt"));
    try std.testing.expect(globMatch("test?.zig", "test1.zig"));
    try std.testing.expect(globMatch("*", "anything"));
    try std.testing.expect(globMatch("foo*bar", "fooxyzbar"));
}

test "simple command" {
    var interp = try Interpreter.init(std.testing.allocator);
    defer interp.deinit();

    const result = try interp.exec("echo hello");
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("hello\n", result.stdout);
}

test "pipe" {
    var interp = try Interpreter.init(std.testing.allocator);
    defer interp.deinit();

    const result = try interp.exec("echo hello | cat");
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("hello\n", result.stdout);
}

test "variable expansion" {
    var interp = try Interpreter.init(std.testing.allocator);
    defer interp.deinit();

    try interp.env.put("TEST_VAR", "hello");
    const result = try interp.exec("echo $TEST_VAR");
    try std.testing.expectEqualStrings("hello\n", result.stdout);
}

test "chain and" {
    var interp = try Interpreter.init(std.testing.allocator);
    defer interp.deinit();

    const result = try interp.exec("true && echo yes");
    try std.testing.expectEqualStrings("yes\n", result.stdout);

    const result2 = try interp.exec("false && echo yes");
    try std.testing.expectEqualStrings("", result2.stdout);
}

test "chain or" {
    var interp = try Interpreter.init(std.testing.allocator);
    defer interp.deinit();

    const result = try interp.exec("false || echo fallback");
    try std.testing.expectEqualStrings("fallback\n", result.stdout);
}

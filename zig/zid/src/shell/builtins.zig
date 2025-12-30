//! Shell Builtins - Native implementations of common commands
//!
//! Builtins run in-process for better performance:
//! - echo, printf
//! - cd, pwd
//! - ls, cat, head, tail
//! - mkdir, rm, cp, mv, touch
//! - which, env, export, unset
//! - true, false, test, [
//! - read, source

const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const posix = std.posix;

pub const ExitCode = u8;

pub const BuiltinResult = struct {
    exit_code: ExitCode,
    stdout: []const u8,
    stderr: []const u8,

    pub const success = BuiltinResult{ .exit_code = 0, .stdout = "", .stderr = "" };

    pub fn err(code: ExitCode, msg: []const u8) BuiltinResult {
        return .{ .exit_code = code, .stdout = "", .stderr = msg };
    }
};

pub const Builtin = struct {
    name: []const u8,
    func: *const fn (*Context) BuiltinResult,
    description: []const u8,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    args: []const []const u8,
    env: *std.process.EnvMap,
    cwd: []const u8,
    stdin: ?[]const u8 = null,
    stdout: std.ArrayList(u8),
    stderr: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, args: []const []const u8, env: *std.process.EnvMap, cwd: []const u8) Context {
        return .{
            .allocator = allocator,
            .args = args,
            .env = env,
            .cwd = cwd,
            .stdout = std.ArrayList(u8).init(allocator),
            .stderr = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.stdout.deinit();
        self.stderr.deinit();
    }

    pub fn write(self: *Context, data: []const u8) void {
        self.stdout.appendSlice(data) catch {};
    }

    pub fn writeLine(self: *Context, data: []const u8) void {
        self.stdout.appendSlice(data) catch {};
        self.stdout.append('\n') catch {};
    }

    pub fn writeErr(self: *Context, data: []const u8) void {
        self.stderr.appendSlice(data) catch {};
    }

    pub fn print(self: *Context, comptime fmt: []const u8, args: anytype) void {
        std.fmt.format(self.stdout.writer(), fmt, args) catch {};
    }

    pub fn printErr(self: *Context, comptime fmt: []const u8, args: anytype) void {
        std.fmt.format(self.stderr.writer(), fmt, args) catch {};
    }
};

// ============ BUILTIN REGISTRY ============

pub const builtins = [_]Builtin{
    .{ .name = "echo", .func = &echo, .description = "Print arguments to stdout" },
    .{ .name = "printf", .func = &printf_builtin, .description = "Formatted output" },
    .{ .name = "cd", .func = &cd, .description = "Change directory" },
    .{ .name = "pwd", .func = &pwd, .description = "Print working directory" },
    .{ .name = "ls", .func = &ls, .description = "List directory contents" },
    .{ .name = "cat", .func = &cat, .description = "Concatenate and print files" },
    .{ .name = "head", .func = &head, .description = "Output first lines of file" },
    .{ .name = "tail", .func = &tail, .description = "Output last lines of file" },
    .{ .name = "mkdir", .func = &mkdir, .description = "Create directories" },
    .{ .name = "rm", .func = &rm, .description = "Remove files or directories" },
    .{ .name = "cp", .func = &cp, .description = "Copy files" },
    .{ .name = "mv", .func = &mv, .description = "Move/rename files" },
    .{ .name = "touch", .func = &touch, .description = "Create empty file or update timestamp" },
    .{ .name = "which", .func = &which, .description = "Locate a command" },
    .{ .name = "env", .func = &env, .description = "Print environment variables" },
    .{ .name = "export", .func = &export, .description = "Set environment variable" },
    .{ .name = "unset", .func = &unset, .description = "Unset environment variable" },
    .{ .name = "true", .func = &true_builtin, .description = "Return success" },
    .{ .name = "false", .func = &false_builtin, .description = "Return failure" },
    .{ .name = "test", .func = &test_builtin, .description = "Evaluate conditional expression" },
    .{ .name = "[", .func = &test_builtin, .description = "Evaluate conditional expression" },
    .{ .name = "exit", .func = &exit_builtin, .description = "Exit shell" },
    .{ .name = "basename", .func = &basename, .description = "Strip directory from filename" },
    .{ .name = "dirname", .func = &dirname, .description = "Strip filename from path" },
    .{ .name = "seq", .func = &seq, .description = "Print sequence of numbers" },
    .{ .name = "wc", .func = &wc, .description = "Word, line, character count" },
    .{ .name = "sort", .func = &sort, .description = "Sort lines" },
    .{ .name = "uniq", .func = &uniq, .description = "Report or omit repeated lines" },
    .{ .name = "grep", .func = &grep, .description = "Search for patterns" },
};

pub fn get(name: []const u8) ?*const Builtin {
    for (&builtins) |*b| {
        if (std.mem.eql(u8, b.name, name)) return b;
    }
    return null;
}

pub fn isBuiltin(name: []const u8) bool {
    return get(name) != null;
}

// ============ IMPLEMENTATIONS ============

fn echo(ctx: *Context) BuiltinResult {
    const args = ctx.args;
    var no_newline = false;
    var start: usize = 0;

    // Check for -n flag
    if (args.len > 0 and std.mem.eql(u8, args[0], "-n")) {
        no_newline = true;
        start = 1;
    }

    // Print args separated by spaces
    for (args[start..], 0..) |arg, i| {
        if (i > 0) ctx.write(" ");
        ctx.write(arg);
    }

    if (!no_newline) ctx.write("\n");

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn printf_builtin(ctx: *Context) BuiltinResult {
    if (ctx.args.len == 0) {
        return BuiltinResult.err(1, "printf: missing format\n");
    }

    const format = ctx.args[0];
    var arg_idx: usize = 1;

    var i: usize = 0;
    while (i < format.len) : (i += 1) {
        if (format[i] == '\\' and i + 1 < format.len) {
            i += 1;
            switch (format[i]) {
                'n' => ctx.write("\n"),
                't' => ctx.write("\t"),
                'r' => ctx.write("\r"),
                '\\' => ctx.write("\\"),
                else => {
                    ctx.write("\\");
                    ctx.write(format[i .. i + 1]);
                },
            }
        } else if (format[i] == '%' and i + 1 < format.len) {
            i += 1;
            switch (format[i]) {
                's' => {
                    if (arg_idx < ctx.args.len) {
                        ctx.write(ctx.args[arg_idx]);
                        arg_idx += 1;
                    }
                },
                'd' => {
                    if (arg_idx < ctx.args.len) {
                        ctx.write(ctx.args[arg_idx]);
                        arg_idx += 1;
                    }
                },
                '%' => ctx.write("%"),
                else => {
                    ctx.write("%");
                    ctx.write(format[i .. i + 1]);
                },
            }
        } else {
            ctx.write(format[i .. i + 1]);
        }
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn cd(ctx: *Context) BuiltinResult {
    const target = if (ctx.args.len > 0) ctx.args[0] else ctx.env.get("HOME") orelse "/";

    const resolved = if (std.fs.path.isAbsolute(target))
        target
    else blk: {
        const full = std.fs.path.join(ctx.allocator, &.{ ctx.cwd, target }) catch {
            return BuiltinResult.err(1, "cd: failed to resolve path\n");
        };
        break :blk full;
    };

    // Verify directory exists
    std.fs.accessAbsolute(resolved, .{}) catch {
        ctx.printErr("cd: {s}: No such file or directory\n", .{target});
        return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
    };

    // Change directory
    posix.chdir(resolved) catch {
        ctx.printErr("cd: {s}: Not a directory\n", .{target});
        return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
    };

    return BuiltinResult.success;
}

fn pwd(ctx: *Context) BuiltinResult {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = posix.getcwd(&buf) catch {
        return BuiltinResult.err(1, "pwd: cannot get current directory\n");
    };
    ctx.writeLine(cwd);
    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn ls(ctx: *Context) BuiltinResult {
    var show_hidden = false;
    var long_format = false;
    var paths = std.ArrayList([]const u8).init(ctx.allocator);
    defer paths.deinit();

    // Parse args
    for (ctx.args) |arg| {
        if (arg.len > 0 and arg[0] == '-') {
            for (arg[1..]) |c| {
                switch (c) {
                    'a' => show_hidden = true,
                    'l' => long_format = true,
                    else => {},
                }
            }
        } else {
            paths.append(arg) catch {};
        }
    }

    if (paths.items.len == 0) {
        paths.append(".") catch {};
    }

    for (paths.items) |path| {
        var dir = fs.openDirAbsolute(if (std.fs.path.isAbsolute(path)) path else blk: {
            break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, path }) catch ".";
        }, .{ .iterate = true }) catch {
            ctx.printErr("ls: cannot access '{s}': No such file or directory\n", .{path});
            continue;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (!show_hidden and entry.name[0] == '.') continue;

            if (long_format) {
                const kind_char: u8 = switch (entry.kind) {
                    .directory => 'd',
                    .sym_link => 'l',
                    else => '-',
                };
                ctx.print("{c}rw-r--r--  {s}\n", .{ kind_char, entry.name });
            } else {
                ctx.print("{s}  ", .{entry.name});
            }
        }

        if (!long_format) ctx.write("\n");
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = ctx.stderr.items };
}

fn cat(ctx: *Context) BuiltinResult {
    if (ctx.args.len == 0) {
        // Read from stdin
        if (ctx.stdin) |input| {
            ctx.write(input);
        }
        return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
    }

    for (ctx.args) |path| {
        const resolved = if (std.fs.path.isAbsolute(path)) path else blk: {
            break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, path }) catch path;
        };

        const file = fs.openFileAbsolute(resolved, .{}) catch {
            ctx.printErr("cat: {s}: No such file or directory\n", .{path});
            continue;
        };
        defer file.close();

        const content = file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch {
            ctx.printErr("cat: {s}: Error reading file\n", .{path});
            continue;
        };
        ctx.write(content);
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = ctx.stderr.items };
}

fn head(ctx: *Context) BuiltinResult {
    var lines: usize = 10;
    var file_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        if (std.mem.eql(u8, ctx.args[i], "-n") and i + 1 < ctx.args.len) {
            i += 1;
            lines = std.fmt.parseInt(usize, ctx.args[i], 10) catch 10;
        } else {
            file_path = ctx.args[i];
        }
    }

    const input = if (file_path) |path| blk: {
        const resolved = if (std.fs.path.isAbsolute(path)) path else (std.fs.path.join(ctx.allocator, &.{ ctx.cwd, path }) catch path);
        const file = fs.openFileAbsolute(resolved, .{}) catch {
            ctx.printErr("head: {s}: No such file\n", .{path});
            return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
        };
        defer file.close();
        break :blk file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch "";
    } else ctx.stdin orelse "";

    var line_count: usize = 0;
    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        if (line_count >= lines) break;
        ctx.writeLine(line);
        line_count += 1;
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn tail(ctx: *Context) BuiltinResult {
    var lines: usize = 10;
    var file_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        if (std.mem.eql(u8, ctx.args[i], "-n") and i + 1 < ctx.args.len) {
            i += 1;
            lines = std.fmt.parseInt(usize, ctx.args[i], 10) catch 10;
        } else {
            file_path = ctx.args[i];
        }
    }

    const input = if (file_path) |path| blk: {
        const resolved = if (std.fs.path.isAbsolute(path)) path else (std.fs.path.join(ctx.allocator, &.{ ctx.cwd, path }) catch path);
        const file = fs.openFileAbsolute(resolved, .{}) catch {
            ctx.printErr("tail: {s}: No such file\n", .{path});
            return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
        };
        defer file.close();
        break :blk file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch "";
    } else ctx.stdin orelse "";

    // Collect lines
    var all_lines = std.ArrayList([]const u8).init(ctx.allocator);
    defer all_lines.deinit();
    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        all_lines.append(line) catch {};
    }

    // Print last N lines
    const start = if (all_lines.items.len > lines) all_lines.items.len - lines else 0;
    for (all_lines.items[start..]) |line| {
        ctx.writeLine(line);
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn mkdir(ctx: *Context) BuiltinResult {
    var parents = false;

    for (ctx.args) |arg| {
        if (std.mem.eql(u8, arg, "-p")) {
            parents = true;
        } else {
            const resolved = if (std.fs.path.isAbsolute(arg)) arg else blk: {
                break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, arg }) catch arg;
            };

            if (parents) {
                fs.makeDirAbsolute(resolved) catch |e| {
                    if (e != error.PathAlreadyExists) {
                        ctx.printErr("mkdir: cannot create '{s}': {}\n", .{ arg, e });
                    }
                };
            } else {
                fs.makeDirAbsolute(resolved) catch |e| {
                    ctx.printErr("mkdir: cannot create '{s}': {}\n", .{ arg, e });
                };
            }
        }
    }

    return .{ .exit_code = 0, .stdout = "", .stderr = ctx.stderr.items };
}

fn rm(ctx: *Context) BuiltinResult {
    var recursive = false;
    var force = false;

    for (ctx.args) |arg| {
        if (arg.len > 0 and arg[0] == '-') {
            for (arg[1..]) |c| {
                switch (c) {
                    'r', 'R' => recursive = true,
                    'f' => force = true,
                    else => {},
                }
            }
        } else {
            const resolved = if (std.fs.path.isAbsolute(arg)) arg else blk: {
                break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, arg }) catch arg;
            };

            if (recursive) {
                fs.deleteTreeAbsolute(resolved) catch |e| {
                    if (!force) {
                        ctx.printErr("rm: cannot remove '{s}': {}\n", .{ arg, e });
                    }
                };
            } else {
                fs.deleteFileAbsolute(resolved) catch |e| {
                    if (!force) {
                        ctx.printErr("rm: cannot remove '{s}': {}\n", .{ arg, e });
                    }
                };
            }
        }
    }

    return .{ .exit_code = 0, .stdout = "", .stderr = ctx.stderr.items };
}

fn cp(ctx: *Context) BuiltinResult {
    if (ctx.args.len < 2) {
        return BuiltinResult.err(1, "cp: missing operand\n");
    }

    const src = ctx.args[0];
    const dst = ctx.args[1];

    const src_resolved = if (std.fs.path.isAbsolute(src)) src else blk: {
        break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, src }) catch src;
    };
    const dst_resolved = if (std.fs.path.isAbsolute(dst)) dst else blk: {
        break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, dst }) catch dst;
    };

    fs.copyFileAbsolute(src_resolved, dst_resolved, .{}) catch |e| {
        ctx.printErr("cp: cannot copy '{s}' to '{s}': {}\n", .{ src, dst, e });
        return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
    };

    return BuiltinResult.success;
}

fn mv(ctx: *Context) BuiltinResult {
    if (ctx.args.len < 2) {
        return BuiltinResult.err(1, "mv: missing operand\n");
    }

    const src = ctx.args[0];
    const dst = ctx.args[1];

    const src_resolved = if (std.fs.path.isAbsolute(src)) src else blk: {
        break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, src }) catch src;
    };
    const dst_resolved = if (std.fs.path.isAbsolute(dst)) dst else blk: {
        break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, dst }) catch dst;
    };

    fs.renameAbsolute(src_resolved, dst_resolved) catch |e| {
        ctx.printErr("mv: cannot move '{s}' to '{s}': {}\n", .{ src, dst, e });
        return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
    };

    return BuiltinResult.success;
}

fn touch(ctx: *Context) BuiltinResult {
    for (ctx.args) |arg| {
        const resolved = if (std.fs.path.isAbsolute(arg)) arg else blk: {
            break :blk std.fs.path.join(ctx.allocator, &.{ ctx.cwd, arg }) catch arg;
        };

        const file = fs.createFileAbsolute(resolved, .{ .truncate = false }) catch {
            ctx.printErr("touch: cannot touch '{s}'\n", .{arg});
            continue;
        };
        file.close();
    }

    return .{ .exit_code = 0, .stdout = "", .stderr = ctx.stderr.items };
}

fn which(ctx: *Context) BuiltinResult {
    if (ctx.args.len == 0) {
        return BuiltinResult.err(1, "which: missing argument\n");
    }

    const path_env = ctx.env.get("PATH") orelse "/usr/bin:/bin";

    for (ctx.args) |cmd| {
        // Check builtins first
        if (isBuiltin(cmd)) {
            ctx.print("{s}: shell built-in command\n", .{cmd});
            continue;
        }

        // Search PATH
        var found = false;
        var paths = std.mem.splitScalar(u8, path_env, ':');
        while (paths.next()) |dir| {
            const full = std.fs.path.join(ctx.allocator, &.{ dir, cmd }) catch continue;
            fs.accessAbsolute(full, .{ .mode = .execute_only }) catch continue;
            ctx.writeLine(full);
            found = true;
            break;
        }

        if (!found) {
            ctx.printErr("{s} not found\n", .{cmd});
        }
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = ctx.stderr.items };
}

fn env(ctx: *Context) BuiltinResult {
    var iter = ctx.env.iterator();
    while (iter.next()) |entry| {
        ctx.print("{s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn export(ctx: *Context) BuiltinResult {
    for (ctx.args) |arg| {
        if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
            const key = arg[0..eq_pos];
            const value = arg[eq_pos + 1 ..];
            ctx.env.put(key, value) catch {};
        }
    }
    return BuiltinResult.success;
}

fn unset(ctx: *Context) BuiltinResult {
    for (ctx.args) |arg| {
        _ = ctx.env.remove(arg);
    }
    return BuiltinResult.success;
}

fn true_builtin(_: *Context) BuiltinResult {
    return .{ .exit_code = 0, .stdout = "", .stderr = "" };
}

fn false_builtin(_: *Context) BuiltinResult {
    return .{ .exit_code = 1, .stdout = "", .stderr = "" };
}

fn test_builtin(ctx: *Context) BuiltinResult {
    if (ctx.args.len == 0) return .{ .exit_code = 1, .stdout = "", .stderr = "" };

    // Simple test implementations
    if (ctx.args.len >= 2) {
        const op = ctx.args[0];
        const arg = ctx.args[1];

        if (std.mem.eql(u8, op, "-f")) {
            // File exists and is regular file
            fs.accessAbsolute(arg, .{}) catch {
                return .{ .exit_code = 1, .stdout = "", .stderr = "" };
            };
            return .{ .exit_code = 0, .stdout = "", .stderr = "" };
        } else if (std.mem.eql(u8, op, "-d")) {
            // Directory exists
            var dir = fs.openDirAbsolute(arg, .{}) catch {
                return .{ .exit_code = 1, .stdout = "", .stderr = "" };
            };
            dir.close();
            return .{ .exit_code = 0, .stdout = "", .stderr = "" };
        } else if (std.mem.eql(u8, op, "-n")) {
            // String is not empty
            return .{ .exit_code = if (arg.len > 0) 0 else 1, .stdout = "", .stderr = "" };
        } else if (std.mem.eql(u8, op, "-z")) {
            // String is empty
            return .{ .exit_code = if (arg.len == 0) 0 else 1, .stdout = "", .stderr = "" };
        }
    }

    if (ctx.args.len >= 3) {
        const left = ctx.args[0];
        const op = ctx.args[1];
        const right = ctx.args[2];

        if (std.mem.eql(u8, op, "=") or std.mem.eql(u8, op, "==")) {
            return .{ .exit_code = if (std.mem.eql(u8, left, right)) 0 else 1, .stdout = "", .stderr = "" };
        } else if (std.mem.eql(u8, op, "!=")) {
            return .{ .exit_code = if (!std.mem.eql(u8, left, right)) 0 else 1, .stdout = "", .stderr = "" };
        }
    }

    return .{ .exit_code = 1, .stdout = "", .stderr = "" };
}

fn exit_builtin(ctx: *Context) BuiltinResult {
    const code: u8 = if (ctx.args.len > 0)
        std.fmt.parseInt(u8, ctx.args[0], 10) catch 1
    else
        0;
    return .{ .exit_code = code, .stdout = "", .stderr = "" };
}

fn basename(ctx: *Context) BuiltinResult {
    if (ctx.args.len == 0) {
        return BuiltinResult.err(1, "basename: missing operand\n");
    }
    ctx.writeLine(std.fs.path.basename(ctx.args[0]));
    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn dirname(ctx: *Context) BuiltinResult {
    if (ctx.args.len == 0) {
        return BuiltinResult.err(1, "dirname: missing operand\n");
    }
    ctx.writeLine(std.fs.path.dirname(ctx.args[0]) orelse ".");
    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn seq(ctx: *Context) BuiltinResult {
    var first: i64 = 1;
    var last: i64 = 1;
    var step: i64 = 1;

    if (ctx.args.len == 1) {
        last = std.fmt.parseInt(i64, ctx.args[0], 10) catch 1;
    } else if (ctx.args.len == 2) {
        first = std.fmt.parseInt(i64, ctx.args[0], 10) catch 1;
        last = std.fmt.parseInt(i64, ctx.args[1], 10) catch 1;
    } else if (ctx.args.len >= 3) {
        first = std.fmt.parseInt(i64, ctx.args[0], 10) catch 1;
        step = std.fmt.parseInt(i64, ctx.args[1], 10) catch 1;
        last = std.fmt.parseInt(i64, ctx.args[2], 10) catch 1;
    }

    var i = first;
    while (i <= last) : (i += step) {
        ctx.print("{d}\n", .{i});
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn wc(ctx: *Context) BuiltinResult {
    const input = if (ctx.args.len > 0) blk: {
        const path = ctx.args[0];
        const resolved = if (std.fs.path.isAbsolute(path)) path else (std.fs.path.join(ctx.allocator, &.{ ctx.cwd, path }) catch path);
        const file = fs.openFileAbsolute(resolved, .{}) catch {
            ctx.printErr("wc: {s}: No such file\n", .{path});
            return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
        };
        defer file.close();
        break :blk file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch "";
    } else ctx.stdin orelse "";

    var lines: usize = 0;
    var words: usize = 0;
    var in_word = false;

    for (input) |c| {
        if (c == '\n') lines += 1;
        if (std.ascii.isWhitespace(c)) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            words += 1;
        }
    }

    ctx.print("{d} {d} {d}\n", .{ lines, words, input.len });
    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn sort(ctx: *Context) BuiltinResult {
    const input = if (ctx.args.len > 0) blk: {
        const path = ctx.args[0];
        const resolved = if (std.fs.path.isAbsolute(path)) path else (std.fs.path.join(ctx.allocator, &.{ ctx.cwd, path }) catch path);
        const file = fs.openFileAbsolute(resolved, .{}) catch {
            ctx.printErr("sort: {s}: No such file\n", .{path});
            return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
        };
        defer file.close();
        break :blk file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch "";
    } else ctx.stdin orelse "";

    var lines_list = std.ArrayList([]const u8).init(ctx.allocator);
    defer lines_list.deinit();

    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        if (line.len > 0) lines_list.append(line) catch {};
    }

    std.mem.sort([]const u8, lines_list.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (lines_list.items) |line| {
        ctx.writeLine(line);
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn uniq(ctx: *Context) BuiltinResult {
    const input = ctx.stdin orelse "";

    var prev: ?[]const u8 = null;
    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        if (prev == null or !std.mem.eql(u8, prev.?, line)) {
            ctx.writeLine(line);
            prev = line;
        }
    }

    return .{ .exit_code = 0, .stdout = ctx.stdout.items, .stderr = "" };
}

fn grep(ctx: *Context) BuiltinResult {
    if (ctx.args.len == 0) {
        return BuiltinResult.err(1, "grep: missing pattern\n");
    }

    const pattern = ctx.args[0];
    const input = if (ctx.args.len > 1) blk: {
        const path = ctx.args[1];
        const resolved = if (std.fs.path.isAbsolute(path)) path else (std.fs.path.join(ctx.allocator, &.{ ctx.cwd, path }) catch path);
        const file = fs.openFileAbsolute(resolved, .{}) catch {
            ctx.printErr("grep: {s}: No such file\n", .{path});
            return .{ .exit_code = 1, .stdout = "", .stderr = ctx.stderr.items };
        };
        defer file.close();
        break :blk file.readToEndAlloc(ctx.allocator, 10 * 1024 * 1024) catch "";
    } else ctx.stdin orelse "";

    var found = false;
    var line_iter = std.mem.splitScalar(u8, input, '\n');
    while (line_iter.next()) |line| {
        if (std.mem.indexOf(u8, line, pattern) != null) {
            ctx.writeLine(line);
            found = true;
        }
    }

    return .{ .exit_code = if (found) 0 else 1, .stdout = ctx.stdout.items, .stderr = "" };
}

// ============ TESTS ============

test "echo builtin" {
    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();

    var ctx = Context.init(std.testing.allocator, &.{ "hello", "world" }, &env_map, "/tmp");
    defer ctx.deinit();

    const result = echo(&ctx);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("hello world\n", result.stdout);
}

test "pwd builtin" {
    var env_map = std.process.EnvMap.init(std.testing.allocator);
    defer env_map.deinit();

    var ctx = Context.init(std.testing.allocator, &.{}, &env_map, "/tmp");
    defer ctx.deinit();

    const result = pwd(&ctx);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

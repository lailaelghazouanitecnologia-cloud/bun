//! System Calls Abstraction
//!
//! Cross-platform syscall wrapper inspired by Bun's sys.zig.
//! Provides consistent API across Linux, macOS, and Windows.
//!
//! All operations return Maybe(T) for consistent error handling.

const std = @import("std");
const builtin = @import("builtin");
const Environment = @import("env.zig");
const misc = @import("misc/mod.zig");

pub const Maybe = misc.Maybe;
pub const Error = misc.Error;

// ============ PLATFORM-SPECIFIC IMPORTS ============

const posix = std.posix;
const fs = std.fs;

// ============ FILE DESCRIPTOR ============

pub const FileDescriptor = if (Environment.isWindows)
    std.os.windows.HANDLE
else
    posix.fd_t;

pub const invalid_fd: FileDescriptor = if (Environment.isWindows)
    std.os.windows.INVALID_HANDLE_VALUE
else
    -1;

// ============ OPERATION TAGS ============

/// All system operations for error reporting
pub const Tag = enum(u8) {
    // File operations
    open,
    close,
    read,
    write,
    pread,
    pwrite,
    stat,
    fstat,
    lstat,
    chmod,
    fchmod,
    chown,
    fchown,
    truncate,
    ftruncate,

    // Directory operations
    mkdir,
    rmdir,
    getcwd,
    chdir,
    opendir,
    readdir,

    // Link operations
    unlink,
    rename,
    symlink,
    readlink,
    link,
    realpath,

    // Process operations
    fork,
    exec,
    wait,
    kill,

    // Socket operations
    socket,
    connect,
    bind,
    listen,
    accept,
    send,
    recv,

    // Memory operations
    mmap,
    munmap,

    // Misc
    ioctl,
    fcntl,
    access,
    pipe,
    dup,
    dup2,

    pub fn name(self: Tag) []const u8 {
        return @tagName(self);
    }
};

// ============ OPEN FLAGS ============

pub const O = struct {
    pub const RDONLY = posix.O.RDONLY;
    pub const WRONLY = posix.O.WRONLY;
    pub const RDWR = posix.O.RDWR;
    pub const CREAT = posix.O.CREAT;
    pub const EXCL = posix.O.EXCL;
    pub const TRUNC = posix.O.TRUNC;
    pub const APPEND = posix.O.APPEND;
    pub const NONBLOCK = posix.O.NONBLOCK;
    pub const CLOEXEC = posix.O.CLOEXEC;

    // Platform-specific
    pub const DIRECTORY = if (@hasField(posix.O, "DIRECTORY")) posix.O.DIRECTORY else 0;
    pub const NOFOLLOW = if (@hasField(posix.O, "NOFOLLOW")) posix.O.NOFOLLOW else 0;
};

// ============ STAT ============

pub const Stat = struct {
    size: u64,
    mtime: i128,
    atime: i128,
    ctime: i128,
    mode: u32,
    kind: Kind,

    pub const Kind = enum {
        file,
        directory,
        symlink,
        block_device,
        character_device,
        fifo,
        socket,
        unknown,
    };

    pub fn isDir(self: Stat) bool {
        return self.kind == .directory;
    }

    pub fn isFile(self: Stat) bool {
        return self.kind == .file;
    }

    pub fn isSymlink(self: Stat) bool {
        return self.kind == .symlink;
    }
};

fn statToStat(st: posix.Stat) Stat {
    const kind: Stat.Kind = blk: {
        const m = st.mode & posix.S.IFMT;
        break :blk switch (m) {
            posix.S.IFDIR => .directory,
            posix.S.IFREG => .file,
            posix.S.IFLNK => .symlink,
            posix.S.IFBLK => .block_device,
            posix.S.IFCHR => .character_device,
            posix.S.IFIFO => .fifo,
            posix.S.IFSOCK => .socket,
            else => .unknown,
        };
    };

    return .{
        .size = @intCast(st.size),
        .mtime = st.mtime().tv_sec,
        .atime = st.atime().tv_sec,
        .ctime = st.ctime().tv_sec,
        .mode = st.mode,
        .kind = kind,
    };
}

// ============ ERROR CONVERSION ============

fn toError(comptime T: type, err: anyerror, tag: Tag, path: []const u8) Maybe(T) {
    const code: Error.Code = switch (err) {
        error.FileNotFound, error.NoSuchFile => .not_found,
        error.AccessDenied, error.PermissionDenied => .permission_denied,
        error.FileExists, error.PathAlreadyExists => .already_exists,
        error.IsDir => .is_directory,
        error.NotDir => .not_directory,
        error.NoSpaceLeft => .no_space,
        error.Interrupted => .interrupted,
        error.Busy, error.DeviceBusy => .busy,
        error.InvalidArgument => .invalid_input,
        error.BrokenPipe => .broken_pipe,
        error.ConnectionRefused => .connection_refused,
        error.ConnectionReset => .connection_reset,
        error.TimedOut => .timeout,
        error.WouldBlock => .would_block,
        else => .unknown,
    };

    const step: Error.Step = switch (tag) {
        .open, .opendir => .open_file,
        .read, .pread, .readdir, .readlink => .read_file,
        .write, .pwrite => .write_file,
        .close => .close_file,
        .stat, .fstat, .lstat => .stat_file,
        .mkdir => .create_dir,
        .rmdir, .unlink => .delete,
        .rename => .rename,
        .symlink, .link => .symlink,
        .chmod, .fchmod, .chown, .fchown => .chmod,
        .getcwd, .chdir, .realpath => .resolve_path,
        .connect => .connect,
        .bind, .listen, .accept => .bind,
        .send, .recv => .network,
        else => .unknown,
    };

    return .{
        .err = .{
            .code = code,
            .message = @errorName(err),
            .path = path,
            .step = step,
        },
    };
}

fn ok(comptime T: type, value: T) Maybe(T) {
    return .{ .ok = value };
}

// ============ FILE OPERATIONS ============

/// Open a file
pub fn open(path: []const u8, flags: u32, mode: u32) Maybe(FileDescriptor) {
    if (comptime Environment.isWindows) {
        // Windows implementation would go here
        @compileError("Windows not yet supported");
    }

    const path_z = std.fs.cwd().realpathZ(path, &path_buf) catch {
        return openDirect(path, flags, mode);
    };
    return openDirect(path_z, flags, mode);
}

var path_buf: [Environment.max_path]u8 = undefined;

fn openDirect(path: []const u8, flags: u32, mode: u32) Maybe(FileDescriptor) {
    const path_sentinel = if (path.len > 0 and path[path.len - 1] == 0)
        @as([*:0]const u8, @ptrCast(path.ptr))
    else blk: {
        if (path.len >= path_buf.len) {
            return toError(FileDescriptor, error.NameTooLong, .open, path);
        }
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;
        break :blk @as([*:0]const u8, @ptrCast(&path_buf));
    };

    const result = posix.openZ(path_sentinel, @bitCast(flags), mode);
    if (result == -1) {
        const err = posix.errno(result);
        return toError(FileDescriptor, switch (err) {
            .NOENT => error.FileNotFound,
            .ACCES => error.AccessDenied,
            .EXIST => error.FileExists,
            .ISDIR => error.IsDir,
            .NOTDIR => error.NotDir,
            else => error.Unexpected,
        }, .open, path);
    }
    return ok(FileDescriptor, result);
}

/// Close a file descriptor
pub fn close(fd: FileDescriptor) Maybe(void) {
    if (comptime Environment.isWindows) {
        @compileError("Windows not yet supported");
    }

    posix.close(fd);
    return ok(void, {});
}

/// Read from file descriptor
pub fn read(fd: FileDescriptor, buf: []u8) Maybe(usize) {
    if (comptime Environment.isWindows) {
        @compileError("Windows not yet supported");
    }

    const result = posix.read(fd, buf);
    if (result < 0) {
        return toError(usize, error.Unexpected, .read, "");
    }
    return ok(usize, @intCast(result));
}

/// Write to file descriptor
pub fn write(fd: FileDescriptor, buf: []const u8) Maybe(usize) {
    if (comptime Environment.isWindows) {
        @compileError("Windows not yet supported");
    }

    const result = posix.write(fd, buf);
    if (result < 0) {
        return toError(usize, error.Unexpected, .write, "");
    }
    return ok(usize, @intCast(result));
}

/// Get file status
pub fn stat(path: []const u8) Maybe(Stat) {
    const st = fs.cwd().statFile(path) catch |e| {
        return toError(Stat, e, .stat, path);
    };
    return ok(Stat, statToStat(st));
}

/// Get file status (no follow symlinks)
pub fn lstat(path: []const u8) Maybe(Stat) {
    // For lstat we need to not follow symlinks
    var path_buf_local: [Environment.max_path]u8 = undefined;
    @memcpy(path_buf_local[0..path.len], path);
    path_buf_local[path.len] = 0;

    const st = posix.lstat(@ptrCast(&path_buf_local)) catch |e| {
        return toError(Stat, e, .lstat, path);
    };
    return ok(Stat, statToStat(st));
}

/// Check file access
pub fn access(path: []const u8, mode: u32) Maybe(void) {
    fs.cwd().access(path, @bitCast(mode)) catch |e| {
        return toError(void, e, .access, path);
    };
    return ok(void, {});
}

/// Check if path exists
pub fn exists(path: []const u8) bool {
    return switch (access(path, 0)) {
        .ok => true,
        .err => false,
    };
}

// ============ DIRECTORY OPERATIONS ============

/// Create directory
pub fn mkdir(path: []const u8, mode: u32) Maybe(void) {
    _ = mode; // Mode is ignored by std.fs.makeDir on non-POSIX
    fs.cwd().makeDir(path) catch |e| {
        return toError(void, e, .mkdir, path);
    };
    return ok(void, {});
}

/// Create directory and parents
pub fn mkdirp(path: []const u8) Maybe(void) {
    fs.cwd().makePath(path) catch |e| {
        return toError(void, e, .mkdir, path);
    };
    return ok(void, {});
}

/// Remove directory
pub fn rmdir(path: []const u8) Maybe(void) {
    fs.cwd().deleteDir(path) catch |e| {
        return toError(void, e, .rmdir, path);
    };
    return ok(void, {});
}

/// Get current working directory
pub fn getcwd(buf: []u8) Maybe([]const u8) {
    const result = fs.cwd().realpathAlloc(std.heap.page_allocator, ".") catch |e| {
        return toError([]const u8, e, .getcwd, ".");
    };
    defer std.heap.page_allocator.free(result);

    if (result.len > buf.len) {
        return toError([]const u8, error.NameTooLong, .getcwd, ".");
    }
    @memcpy(buf[0..result.len], result);
    return ok([]const u8, buf[0..result.len]);
}

/// Change current directory
pub fn chdir(path: []const u8) Maybe(void) {
    std.posix.chdirZ(@ptrCast(path.ptr)) catch |e| {
        return toError(void, e, .chdir, path);
    };
    return ok(void, {});
}

// ============ LINK OPERATIONS ============

/// Remove file
pub fn unlink(path: []const u8) Maybe(void) {
    fs.cwd().deleteFile(path) catch |e| {
        return toError(void, e, .unlink, path);
    };
    return ok(void, {});
}

/// Rename file
pub fn rename(old: []const u8, new: []const u8) Maybe(void) {
    fs.cwd().rename(old, new) catch |e| {
        return toError(void, e, .rename, old);
    };
    return ok(void, {});
}

/// Create symbolic link
pub fn symlink(target: []const u8, linkpath: []const u8) Maybe(void) {
    fs.cwd().symLink(target, linkpath, .{}) catch |e| {
        return toError(void, e, .symlink, linkpath);
    };
    return ok(void, {});
}

/// Read symbolic link
pub fn readlink(path: []const u8, buf: []u8) Maybe([]const u8) {
    const result = fs.cwd().readLink(path, buf) catch |e| {
        return toError([]const u8, e, .readlink, path);
    };
    return ok([]const u8, result);
}

/// Get real (canonical) path
pub fn realpath(allocator: std.mem.Allocator, path: []const u8) Maybe([]u8) {
    const result = fs.cwd().realpathAlloc(allocator, path) catch |e| {
        return toError([]u8, e, .realpath, path);
    };
    return ok([]u8, result);
}

// ============ COPY OPERATIONS ============

/// Copy file (efficient, uses platform-specific APIs)
pub fn copyFile(src: []const u8, dest: []const u8) Maybe(void) {
    if (comptime Environment.isLinux) {
        // Try copy_file_range first (most efficient)
        return copyFileLinux(src, dest);
    } else {
        return copyFileGeneric(src, dest);
    }
}

fn copyFileLinux(src: []const u8, dest: []const u8) Maybe(void) {
    // Open source
    const src_fd = switch (open(src, O.RDONLY, 0)) {
        .ok => |fd| fd,
        .err => |e| return .{ .err = e },
    };
    defer _ = close(src_fd);

    // Get source size
    const src_stat = switch (stat(src)) {
        .ok => |s| s,
        .err => |e| return .{ .err = e },
    };

    // Open/create destination
    const dest_fd = switch (open(dest, O.WRONLY | O.CREAT | O.TRUNC, 0o644)) {
        .ok => |fd| fd,
        .err => |e| return .{ .err = e },
    };
    defer _ = close(dest_fd);

    // Use sendfile for zero-copy
    var remaining = src_stat.size;
    while (remaining > 0) {
        const chunk = @min(remaining, 1024 * 1024 * 1024); // 1GB chunks
        const sent = posix.sendfile(dest_fd, src_fd, null, chunk);
        if (sent == 0) break;
        if (sent < 0) {
            return toError(void, error.Unexpected, .write, dest);
        }
        remaining -= @intCast(sent);
    }

    return ok(void, {});
}

fn copyFileGeneric(src: []const u8, dest: []const u8) Maybe(void) {
    fs.cwd().copyFile(src, fs.cwd(), dest, .{}) catch |e| {
        return toError(void, e, .write, dest);
    };
    return ok(void, {});
}

// ============ PROCESS OPERATIONS ============

/// Execute command and wait for result
pub const ExecResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    term: std.process.Child.Term,

    pub fn exitCode(self: ExecResult) u8 {
        return switch (self.term) {
            .Exited => |code| code,
            else => 1,
        };
    }

    pub fn success(self: ExecResult) bool {
        return self.term == .Exited and self.term.Exited == 0;
    }
};

pub fn exec(allocator: std.mem.Allocator, argv: []const []const u8) Maybe(ExecResult) {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    child.spawn() catch |e| {
        return toError(ExecResult, e, .exec, argv[0]);
    };

    const stdout = child.stdout.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch "";
    const stderr = child.stderr.?.reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch "";

    const term = child.wait() catch |e| {
        return toError(ExecResult, e, .wait, argv[0]);
    };

    return ok(ExecResult, .{
        .stdout = stdout,
        .stderr = stderr,
        .term = term,
    });
}

// ============ UTILITIES ============

/// Write entire buffer to fd (handles partial writes)
pub fn writeAll(fd: FileDescriptor, buf: []const u8) Maybe(void) {
    var written: usize = 0;
    while (written < buf.len) {
        const result = switch (write(fd, buf[written..])) {
            .ok => |n| n,
            .err => |e| return .{ .err = e },
        };
        if (result == 0) break;
        written += result;
    }
    return ok(void, {});
}

/// Read entire file into memory
pub fn readFile(allocator: std.mem.Allocator, path: []const u8) Maybe([]u8) {
    const content = fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024) catch |e| {
        return toError([]u8, e, .read, path);
    };
    return ok([]u8, content);
}

/// Write entire buffer to file
pub fn writeFile(path: []const u8, data: []const u8) Maybe(void) {
    const file = fs.cwd().createFile(path, .{}) catch |e| {
        return toError(void, e, .write, path);
    };
    defer file.close();

    file.writeAll(data) catch |e| {
        return toError(void, e, .write, path);
    };
    return ok(void, {});
}

// ============ TESTS ============

test "sys: stat existing file" {
    const result = stat("/etc/passwd");
    switch (result) {
        .ok => |s| {
            try std.testing.expect(s.kind == .file);
            try std.testing.expect(s.size > 0);
        },
        .err => {
            // May not exist on all systems, skip
        },
    }
}

test "sys: exists" {
    try std.testing.expect(exists("/"));
    try std.testing.expect(!exists("/nonexistent_path_12345"));
}

test "sys: mkdir and rmdir" {
    const test_dir = "/tmp/zid_sys_test_dir";

    // Clean up first
    _ = rmdir(test_dir);

    // Create
    switch (mkdir(test_dir, 0o755)) {
        .ok => {},
        .err => return error.MkdirFailed,
    }

    try std.testing.expect(exists(test_dir));

    // Remove
    switch (rmdir(test_dir)) {
        .ok => {},
        .err => return error.RmdirFailed,
    }

    try std.testing.expect(!exists(test_dir));
}

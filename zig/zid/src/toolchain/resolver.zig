//! Toolchain Resolver
//!
//! Detecta y resuelve conflictos entre toolchains de zid y comandos del sistema.
//!
//! Estrategia:
//! - Si `bun` existe en PATH del sistema, usar `zid bun` para el de zid
//! - Detectar automáticamente conflictos al instalar
//! - Ofrecer aliases alternativos
//!
//! Ejemplo:
//!   $ zid install bun
//!   ⚠ 'bun' already exists in /usr/bin/bun
//!
//!   Use one of:
//!     zid bun          # Run zid's bun
//!     zid use bun      # Make zid's bun the default
//!     bun              # System bun (current)

const std = @import("std");
const zid = @import("../zid.zig");
const registry = @import("registry.zig");

const Output = zid.Output;
const Maybe = zid.Maybe;

const log = zid.ScopedLog("resolver");

// ============ CONFLICT DETECTION ============

pub const Conflict = struct {
    command: []const u8,
    system_path: []const u8,
    zid_path: []const u8,
    priority: Priority,

    pub const Priority = enum {
        system, // System command takes precedence
        zid, // Zid toolchain takes precedence
        ambiguous, // User must choose
    };
};

/// Check if command exists in system PATH (excluding ~/.zid/bin)
pub fn findSystemCommand(allocator: std.mem.Allocator, cmd: []const u8) ?[]const u8 {
    const path_env = std.posix.getenv("PATH") orelse return null;
    const zid_bin = zid.getHome() ++ "/bin";

    var paths = std.mem.splitScalar(u8, path_env, ':');
    while (paths.next()) |dir| {
        // Skip zid's bin directory
        if (std.mem.startsWith(u8, dir, zid_bin)) continue;

        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, cmd }) catch continue;

        std.fs.accessAbsolute(full_path, .{ .mode = .execute_only }) catch continue;

        // Found in system PATH
        return allocator.dupe(u8, full_path) catch null;
    }

    return null;
}

/// Check if zid has this toolchain installed
pub fn findZidToolchain(cmd: []const u8) ?[]const u8 {
    const home = zid.getHome();
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const zid_path = std.fmt.bufPrint(&buf, "{s}/bin/{s}", .{ home, cmd }) catch return null;

    std.fs.accessAbsolute(zid_path, .{ .mode = .execute_only }) catch return null;
    return zid_path;
}

/// Detect conflict for a command
pub fn detectConflict(allocator: std.mem.Allocator, cmd: []const u8) ?Conflict {
    const system_path = findSystemCommand(allocator, cmd) orelse return null;
    const zid_path = findZidToolchain(cmd) orelse {
        allocator.free(system_path);
        return null;
    };

    log.debug("conflict detected: {s} exists at {s} and {s}", .{ cmd, system_path, zid_path });

    return .{
        .command = cmd,
        .system_path = system_path,
        .zid_path = zid_path,
        .priority = .system, // System takes precedence by default
    };
}

/// Check all installed toolchains for conflicts
pub fn detectAllConflicts(allocator: std.mem.Allocator) ![]Conflict {
    var conflicts = std.ArrayList(Conflict).init(allocator);

    // Check each known toolchain
    for (registry.tools) |tool| {
        if (detectConflict(allocator, tool.name)) |conflict| {
            try conflicts.append(conflict);
        }
    }

    return conflicts.toOwnedSlice();
}

// ============ RESOLUTION ============

/// Print conflict warning during installation
pub fn warnConflict(conflict: Conflict) void {
    Output.warn("\n'{s}' already exists at: {s}\n\n", .{ conflict.command, conflict.system_path });
    Output.print("To use zid's version:\n", .{});
    Output.print("  zid {s} <args>       ", .{conflict.command});
    Output.print("# Run zid's {s}\n", .{conflict.command});
    Output.print("  zid use {s}@<ver>   ", .{conflict.command});
    Output.print("# Switch default to zid's\n\n", .{});
}

/// Get the resolved path for a command
pub fn resolve(allocator: std.mem.Allocator, cmd: []const u8, prefer_zid: bool) ![]const u8 {
    if (prefer_zid) {
        // Try zid first
        if (findZidToolchain(cmd)) |path| {
            return allocator.dupe(u8, path);
        }
    }

    // Try system
    if (findSystemCommand(allocator, cmd)) |path| {
        return path;
    }

    // Try zid as fallback
    if (findZidToolchain(cmd)) |path| {
        return allocator.dupe(u8, path);
    }

    return error.CommandNotFound;
}

// ============ RUN TOOLCHAIN ============

/// Run a toolchain command through zid
pub fn runToolchain(
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    args: []const []const u8,
) !u8 {
    // Find toolchain path
    const home = zid.getHome();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tool_path = std.fmt.bufPrint(&path_buf, "{s}/bin/{s}", .{ home, tool_name }) catch {
        Output.err("Path too long\n", .{});
        return 1;
    };

    // Check if installed
    std.fs.accessAbsolute(tool_path, .{ .mode = .execute_only }) catch {
        Output.err("Toolchain '{s}' not installed.\n", .{tool_name});
        Output.print("Install with: zid install {s}\n", .{tool_name});
        return 1;
    };

    // Build argv
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append(tool_path);
    for (args) |arg| {
        try argv.append(arg);
    }

    // Execute
    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const term = try child.wait();

    return if (term == .Exited) term.Exited else 1;
}

// ============ ALIAS MANAGEMENT ============

pub const Alias = struct {
    name: []const u8,
    target: []const u8,
    is_zid: bool,
};

/// Get all command aliases
pub fn getAliases(allocator: std.mem.Allocator) ![]Alias {
    var aliases = std.ArrayList(Alias).init(allocator);

    const home = zid.getHome();
    var bin_buf: [256]u8 = undefined;
    const bin_dir = std.fmt.bufPrint(&bin_buf, "{s}/bin", .{home}) catch return aliases.toOwnedSlice();

    var dir = std.fs.openDirAbsolute(bin_dir, .{ .iterate = true }) catch return aliases.toOwnedSlice();
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .sym_link and entry.kind != .file) continue;

        // Get target
        var target_buf: [std.fs.max_path_bytes]u8 = undefined;
        const target = dir.readLink(entry.name, &target_buf) catch continue;

        try aliases.append(.{
            .name = try allocator.dupe(u8, entry.name),
            .target = try allocator.dupe(u8, target),
            .is_zid = true,
        });
    }

    return aliases.toOwnedSlice();
}

/// Create alias for toolchain
pub fn createAlias(name: []const u8, tool: []const u8, version: []const u8) Maybe(void) {
    const home = zid.getHome();

    var target_buf: [256]u8 = undefined;
    const target = std.fmt.bufPrint(&target_buf, "{s}/toolchains/{s}/{s}/{s}", .{
        home,
        tool,
        version,
        tool,
    }) catch return zid.err(void, .{ .code = .internal_error, .message = "path too long" });

    var link_buf: [256]u8 = undefined;
    const link = std.fmt.bufPrint(&link_buf, "{s}/bin/{s}", .{ home, name }) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    // Remove existing
    std.fs.deleteFileAbsolute(link) catch {};

    // Create symlink
    std.posix.symlinkat(target, std.fs.cwd().fd, link) catch |e| {
        return zid.fail(void, e, .write_file, link);
    };

    Output.success("Created alias: {s} -> {s}\n", .{ name, tool });
    return zid.ok(void, {});
}

// ============ TESTS ============

test "findSystemCommand" {
    // 'ls' should exist on all Unix systems
    const result = findSystemCommand(std.testing.allocator, "ls");
    try std.testing.expect(result != null);
    if (result) |path| {
        std.testing.allocator.free(path);
    }
}

test "conflict detection" {
    const conflict = detectConflict(std.testing.allocator, "nonexistent-command-12345");
    try std.testing.expect(conflict == null);
}

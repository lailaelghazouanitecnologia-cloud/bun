//! Apps Registry
//!
//! Register programs as direct commands.
//! Apps are stored in ~/.zid/apps.json and symlinked to ~/.zid/bin/
//!
//! Usage:
//!   zid add myprogram.js          # Register script
//!   zid add ./build/myapp         # Register binary
//!   zid add . --name myproject    # Register current project
//!   myprogram                     # Run directly (if ~/.zid/bin in PATH)

const std = @import("std");
const zid = @import("../zid.zig");
const Output = zid.Output;
const Maybe = zid.Maybe;

pub const db = @import("db.zig");
pub const Database = db.Database;
pub const AppEntry = db.AppEntry;
pub const AppKind = db.AppKind;

const log = zid.ScopedLog("apps");

/// Check if name is a registered app
pub fn isApp(name: []const u8) bool {
    var database = Database.init(std.heap.page_allocator);
    defer database.deinit();

    switch (database.load()) {
        .ok => {},
        .err => return false,
    }

    return database.has(name);
}

/// Execute a registered app
pub fn exec(alloc: std.mem.Allocator, name: []const u8, args: []const []const u8) !void {
    var database = Database.init(alloc);
    defer database.deinit();

    switch (database.load()) {
        .ok => {},
        .err => |e| {
            Output.err("Failed to load apps: {s}\n", .{e.message});
            return error.LoadFailed;
        },
    }

    const entry = database.get(name) orelse {
        Output.err("App not found: {s}\n", .{name});
        return error.AppNotFound;
    };

    log.debug("executing {s} ({s})", .{ name, entry.path });

    // Build command
    var cmd_args = std.ArrayList([]const u8).init(alloc);
    defer cmd_args.deinit();

    switch (entry.kind) {
        .binary => {
            try cmd_args.append(entry.path);
        },
        .script => {
            // Detect interpreter
            const ext = std.fs.path.extension(entry.path);
            if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".ts")) {
                try cmd_args.append("bun");
            } else if (std.mem.eql(u8, ext, ".py")) {
                try cmd_args.append("python3");
            } else if (std.mem.eql(u8, ext, ".sh")) {
                try cmd_args.append("sh");
            }
            try cmd_args.append(entry.path);
        },
        .project => {
            // Build and run
            try cmd_args.append("zid");
            try cmd_args.append("build");
            try cmd_args.append("--run");
        },
    }

    // Add user args
    for (args) |arg| {
        try cmd_args.append(arg);
    }

    // Execute
    var child = std.process.Child.init(cmd_args.items, alloc);
    child.cwd = if (entry.kind == .project) entry.path else null;

    const term = try child.spawnAndWait();

    if (term.Exited != 0) {
        return error.ExecFailed;
    }
}

/// Add an app to registry
pub fn add(alloc: std.mem.Allocator, source: []const u8, name_override: ?[]const u8) Maybe(void) {
    var database = Database.init(alloc);
    defer database.deinit();

    switch (database.load()) {
        .ok => {},
        .err => |e| return zid.err(void, e),
    }

    // Resolve path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = std.fs.realpath(source, &path_buf) catch |e| {
        return zid.fail(void, e, .read_file, source);
    };

    // Determine name
    const app_name = name_override orelse std.fs.path.stem(source);

    // Check if already exists
    if (database.has(app_name)) {
        Output.warn("App '{s}' already registered. Updating...\n", .{app_name});
    }

    // Detect kind
    const kind = detectKind(full_path);

    Output.print("Adding app: {s}\n", .{app_name});
    Output.print("  Path: {s}\n", .{full_path});
    Output.print("  Type: {s}\n", .{@tagName(kind)});

    // Add to database
    const entry = AppEntry{
        .name = app_name,
        .path = full_path,
        .kind = kind,
        .added_at = std.time.timestamp(),
    };

    switch (database.add(entry)) {
        .ok => {},
        .err => |e| return zid.err(void, e),
    }

    // Create symlink in bin/
    switch (createSymlink(alloc, app_name, full_path, kind)) {
        .ok => {},
        .err => {}, // Non-fatal
    }

    Output.success("Added: {s}\n", .{app_name});
    Output.print("\nRun with: {s}\n", .{app_name});
    Output.print("(Make sure ~/.zid/bin is in your PATH)\n", .{});

    return zid.ok(void, {});
}

/// Remove an app from registry
pub fn remove(alloc: std.mem.Allocator, name: []const u8) Maybe(void) {
    var database = Database.init(alloc);
    defer database.deinit();

    switch (database.load()) {
        .ok => {},
        .err => |e| return zid.err(void, e),
    }

    switch (database.remove(name)) {
        .ok => |removed| {
            if (removed) {
                // Remove symlink
                const home = zid.getHome();
                var path_buf: [256]u8 = undefined;
                const link_path = std.fmt.bufPrint(&path_buf, "{s}/bin/{s}", .{ home, name }) catch "";
                std.fs.deleteFileAbsolute(link_path) catch {};

                Output.success("Removed: {s}\n", .{name});
            } else {
                Output.err("App not found: {s}\n", .{name});
            }
        },
        .err => |e| return zid.err(void, e),
    }

    return zid.ok(void, {});
}

/// List all registered apps
pub fn list(alloc: std.mem.Allocator) void {
    var database = Database.init(alloc);
    defer database.deinit();

    switch (database.load()) {
        .ok => {},
        .err => |e| {
            Output.err("Failed to load apps: {s}\n", .{e.message});
            return;
        },
    }

    Output.bold("Registered apps:\n\n", .{});

    const apps = database.all();
    if (apps.len == 0) {
        Output.print("  (none)\n", .{});
        Output.print("\nUse 'zid add <file>' to register an app.\n", .{});
        return;
    }

    for (apps) |app| {
        Output.print("  {s: <16} [{s}] {s}\n", .{
            app.name,
            @tagName(app.kind),
            app.path,
        });
    }

    Output.print("\nTotal: {d} app(s)\n", .{apps.len});
}

// ============ INTERNAL ============

fn detectKind(path: []const u8) AppKind {
    // Check if directory (project)
    const stat = std.fs.cwd().statFile(path) catch return .binary;
    if (stat.kind == .directory) {
        return .project;
    }

    // Check extension
    const ext = std.fs.path.extension(path);
    const script_exts = [_][]const u8{ ".js", ".ts", ".py", ".sh", ".rb", ".pl" };
    for (script_exts) |e| {
        if (std.mem.eql(u8, ext, e)) {
            return .script;
        }
    }

    return .binary;
}

fn createSymlink(alloc: std.mem.Allocator, name: []const u8, target: []const u8, kind: AppKind) Maybe(void) {
    const home = zid.getHome();

    // Ensure bin directory exists
    var bin_buf: [256]u8 = undefined;
    const bin_dir = std.fmt.bufPrint(&bin_buf, "{s}/bin", .{home}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    std.fs.makeDirAbsolute(bin_dir) catch |e| {
        if (e != error.PathAlreadyExists) {
            return zid.fail(void, e, .write_file, bin_dir);
        }
    };

    // Create wrapper script or symlink
    var link_buf: [256]u8 = undefined;
    const link_path = std.fmt.bufPrint(&link_buf, "{s}/bin/{s}", .{ home, name }) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    // Remove existing
    std.fs.deleteFileAbsolute(link_path) catch {};

    if (kind == .binary) {
        // Direct symlink for binaries
        std.fs.symLinkAbsolute(target, link_path, .{}) catch |e| {
            return zid.fail(void, e, .write_file, link_path);
        };
    } else {
        // Wrapper script for scripts/projects
        const wrapper = std.fmt.allocPrint(alloc,
            \\#!/bin/sh
            \\exec zid run {s} "$@"
            \\
        , .{name}) catch {
            return zid.err(void, .{ .code = .internal_error, .message = "alloc failed" });
        };
        defer alloc.free(wrapper);

        const file = std.fs.createFileAbsolute(link_path, .{ .mode = 0o755 }) catch |e| {
            return zid.fail(void, e, .write_file, link_path);
        };
        defer file.close();

        file.writeAll(wrapper) catch |e| {
            return zid.fail(void, e, .write_file, link_path);
        };
    }

    log.debug("created symlink: {s} -> {s}", .{ link_path, target });
    return zid.ok(void, {});
}

//! Capsules - Library/module system
//!
//! Capsules are reusable libraries that can be:
//! - intern/: Built-in capsules (bundled with zid)
//! - extern/: External capsules (fetched from registry)
//!
//! Examples: webgpu bindings, wasm runtimes, native libraries

const std = @import("std");
const zid = @import("../zid.zig");
const Maybe = zid.Maybe;
const Output = zid.Output;

const log = zid.ScopedLog("capsules");

// Re-export submodules
pub const registry = @import("registry.zig");
pub const fetcher = @import("fetcher.zig");
pub const manifest = @import("manifest.zig");
pub const integration = @import("integration.zig");
pub const paths = @import("paths.zig");

// Re-export types
pub const Capsule = registry.Capsule;
pub const CapsuleKind = registry.CapsuleKind;
pub const Manifest = manifest.Manifest;

/// Capsule manager
pub const Manager = struct {
    allocator: std.mem.Allocator,
    home_dir: []const u8,
    capsules_dir: []const u8,
    intern_dir: []const u8,
    extern_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const home = zid.getHome();

        var capsules_buf: [256]u8 = undefined;
        var intern_buf: [256]u8 = undefined;
        var extern_buf: [256]u8 = undefined;

        const capsules_dir = std.fmt.bufPrint(&capsules_buf, "{s}/capsules", .{home}) catch home;
        const intern_dir = std.fmt.bufPrint(&intern_buf, "{s}/capsules/intern", .{home}) catch home;
        const extern_dir = std.fmt.bufPrint(&extern_buf, "{s}/capsules/extern", .{home}) catch home;

        return .{
            .allocator = allocator,
            .home_dir = home,
            .capsules_dir = capsules_dir,
            .intern_dir = intern_dir,
            .extern_dir = extern_dir,
        };
    }

    /// Ensure directories exist
    pub fn ensureDirs(self: *Self) void {
        const dirs = [_][]const u8{
            self.capsules_dir,
            self.intern_dir,
            self.extern_dir,
        };

        for (dirs) |dir| {
            std.fs.makeDirAbsolute(dir) catch |e| {
                if (e != error.PathAlreadyExists) {
                    log.err("failed to create {s}", .{dir});
                }
            };
        }
    }

    /// Install a capsule
    pub fn install(self: *Self, name: []const u8) Maybe(Capsule) {
        self.ensureDirs();

        // Check if it's a built-in capsule
        if (registry.getBuiltin(name)) |builtin| {
            return self.installBuiltin(builtin);
        }

        // Otherwise fetch from registry
        return self.installExternal(name);
    }

    fn installBuiltin(self: *Self, cap: *const registry.BuiltinCapsule) Maybe(Capsule) {
        Output.print("Installing capsule: {s}...\n", .{cap.name});

        var path_buf: [256]u8 = undefined;
        const dest = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
            self.intern_dir,
            cap.name,
        }) catch {
            return zid.err(Capsule, .{ .code = .internal_error, .message = "path too long" });
        };

        // Create capsule directory
        std.fs.makeDirAbsolute(dest) catch |e| {
            if (e != error.PathAlreadyExists) {
                return zid.fail(Capsule, e, .write_file, dest);
            }
        };

        Output.success("Installed {s}\n", .{cap.name});

        return zid.ok(Capsule, .{
            .name = cap.name,
            .version = cap.version,
            .kind = .intern,
            .path = dest,
            .description = cap.description,
        });
    }

    fn installExternal(self: *Self, name: []const u8) Maybe(Capsule) {
        Output.print("Fetching capsule: {s}...\n", .{name});

        // Fetch manifest from registry
        const mf = switch (fetcher.fetchManifest(self.allocator, name)) {
            .ok => |m| m,
            .err => |e| return zid.err(Capsule, e),
        };

        var path_buf: [256]u8 = undefined;
        const dest = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
            self.extern_dir,
            name,
        }) catch {
            return zid.err(Capsule, .{ .code = .internal_error, .message = "path too long" });
        };

        // Download and extract
        switch (fetcher.download(self.allocator, mf.url, dest)) {
            .ok => {},
            .err => |e| return zid.err(Capsule, e),
        }

        Output.success("Installed {s}@{s}\n", .{ name, mf.version });

        return zid.ok(Capsule, .{
            .name = name,
            .version = mf.version,
            .kind = .extern_,
            .path = dest,
            .description = mf.description,
        });
    }

    /// Remove a capsule
    pub fn remove(self: *Self, name: []const u8) Maybe(void) {
        // Try intern first
        var path_buf: [256]u8 = undefined;
        var path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
            self.intern_dir,
            name,
        }) catch return zid.err(void, .{ .code = .internal_error, .message = "path too long" });

        if (std.fs.accessAbsolute(path, .{})) |_| {
            std.fs.deleteTreeAbsolute(path) catch |e| {
                return zid.fail(void, e, .write_file, path);
            };
            Output.success("Removed {s}\n", .{name});
            return zid.ok(void, {});
        } else |_| {}

        // Try extern
        path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
            self.extern_dir,
            name,
        }) catch return zid.err(void, .{ .code = .internal_error, .message = "path too long" });

        std.fs.deleteTreeAbsolute(path) catch |e| {
            return zid.fail(void, e, .write_file, path);
        };

        Output.success("Removed {s}\n", .{name});
        return zid.ok(void, {});
    }

    /// List installed capsules
    pub fn listInstalled(self: *Self) void {
        Output.bold("Installed capsules:\n\n", .{});

        var has_any = false;

        // List intern
        if (self.listDir(self.intern_dir, "intern")) {
            has_any = true;
        }

        // List extern
        if (self.listDir(self.extern_dir, "extern")) {
            has_any = true;
        }

        if (!has_any) {
            Output.print("  (none)\n", .{});
        }

        Output.print("\nUse 'zid capsule add <name>' to install.\n", .{});
    }

    fn listDir(self: *Self, dir_path: []const u8, kind: []const u8) bool {
        _ = self;
        var has_any = false;

        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return false;
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .directory) continue;
            Output.print("  [{s}] {s}\n", .{ kind, entry.name });
            has_any = true;
        }

        return has_any;
    }

    /// Get capsule by name
    pub fn get(self: *Self, name: []const u8) ?Capsule {
        var path_buf: [256]u8 = undefined;

        // Check intern
        var path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
            self.intern_dir,
            name,
        }) catch return null;

        if (std.fs.accessAbsolute(path, .{})) |_| {
            return Capsule{
                .name = name,
                .version = "local",
                .kind = .intern,
                .path = path,
                .description = "",
            };
        } else |_| {}

        // Check extern
        path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
            self.extern_dir,
            name,
        }) catch return null;

        if (std.fs.accessAbsolute(path, .{})) |_| {
            return Capsule{
                .name = name,
                .version = "unknown",
                .kind = .extern_,
                .path = path,
                .description = "",
            };
        } else |_| {}

        return null;
    }
};

// ============ PUBLIC API ============

pub fn install(allocator: std.mem.Allocator, name: []const u8) Maybe(Capsule) {
    var mgr = Manager.init(allocator);
    return mgr.install(name);
}

pub fn remove(allocator: std.mem.Allocator, name: []const u8) Maybe(void) {
    var mgr = Manager.init(allocator);
    return mgr.remove(name);
}

pub fn list(allocator: std.mem.Allocator) void {
    var mgr = Manager.init(allocator);
    mgr.listInstalled();
}

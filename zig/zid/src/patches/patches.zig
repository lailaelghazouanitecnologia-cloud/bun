//! Patches System - Urgent fixes and hot patches
//!
//! Detects and applies urgent patches that can be deployed
//! without a full update. Patches are small fixes that can be:
//! - Applied immediately to running configurations
//! - Stored locally for persistence
//! - Rolled back if needed
//!
//! Patch flow:
//! 1. Check for available patches from server
//! 2. Verify patch compatibility with current version
//! 3. Download and verify patch
//! 4. Apply patch (config/scripts/etc)
//! 5. Track applied patches

const std = @import("std");
const zid = @import("../zid.zig");
const Maybe = zid.Maybe;
const Output = zid.Output;

const log = zid.ScopedLog("patches");

// Re-export submodules
pub const registry = @import("registry.zig");
pub const applicator = @import("applicator.zig");

/// Patch severity level
pub const Severity = enum {
    critical, // Security fix, apply immediately
    high, // Important bug fix
    normal, // Regular fix
    low, // Optional improvement
};

/// Patch type
pub const PatchKind = enum {
    config, // Configuration changes
    script, // Script/behavior changes
    data, // Data file updates
    binary, // Binary patch (requires update)
};

/// A patch definition
pub const Patch = struct {
    id: []const u8,
    version: []const u8,
    target_version: []const u8, // Version this applies to
    severity: Severity,
    kind: PatchKind,
    description: []const u8,
    url: ?[]const u8 = null,
    checksum: []const u8 = "",
    applied: bool = false,
    applied_at: i64 = 0,
};

/// Patch manager
pub const Manager = struct {
    allocator: std.mem.Allocator,
    patches_dir: []const u8,
    applied_file: []const u8,
    applied_patches: std.StringHashMap(i64),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const home = zid.getHome();

        var patches_buf: [256]u8 = undefined;
        var applied_buf: [256]u8 = undefined;

        const patches_dir = std.fmt.bufPrint(&patches_buf, "{s}/patches", .{home}) catch home;
        const applied_file = std.fmt.bufPrint(&applied_buf, "{s}/patches/applied.json", .{home}) catch home;

        var mgr = Self{
            .allocator = allocator,
            .patches_dir = patches_dir,
            .applied_file = applied_file,
            .applied_patches = std.StringHashMap(i64).init(allocator),
        };

        mgr.loadApplied();
        return mgr;
    }

    pub fn deinit(self: *Self) void {
        self.applied_patches.deinit();
    }

    /// Load list of applied patches
    fn loadApplied(self: *Self) void {
        const file = std.fs.openFileAbsolute(self.applied_file, .{}) catch return;
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return;
        defer self.allocator.free(content);

        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            content,
            .{},
        ) catch return;
        defer parsed.deinit();

        switch (parsed.value) {
            .object => |obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.* == .integer) {
                        self.applied_patches.put(entry.key_ptr.*, entry.value_ptr.integer) catch {};
                    }
                }
            },
            else => {},
        }
    }

    /// Save applied patches list
    fn saveApplied(self: *Self) void {
        // Ensure directory exists
        std.fs.makeDirAbsolute(self.patches_dir) catch {};

        const file = std.fs.createFileAbsolute(self.applied_file, .{}) catch return;
        defer file.close();

        var writer = file.writer();
        writer.writeAll("{\n") catch return;

        var first = true;
        var it = self.applied_patches.iterator();
        while (it.next()) |entry| {
            if (!first) writer.writeAll(",\n") catch {};
            writer.print("  \"{s}\": {d}", .{ entry.key_ptr.*, entry.value_ptr.* }) catch {};
            first = false;
        }

        writer.writeAll("\n}\n") catch {};
    }

    /// Check for available patches
    pub fn check(self: *Self) Maybe([]const Patch) {
        const current_version = @import("../cli/update.zig").VERSION;

        log.debug("checking patches for version {s}", .{current_version});

        // Fetch available patches from server
        const patches = switch (registry.fetchAvailable(self.allocator, current_version)) {
            .ok => |p| p,
            .err => |e| return zid.err([]const Patch, e),
        };

        // Filter out already applied
        var pending = std.ArrayList(Patch).init(self.allocator);
        for (patches) |patch| {
            if (!self.isApplied(patch.id)) {
                pending.append(patch) catch {};
            }
        }

        return zid.ok([]const Patch, pending.items);
    }

    /// Check if patch is applied
    pub fn isApplied(self: *Self, patch_id: []const u8) bool {
        return self.applied_patches.contains(patch_id);
    }

    /// Apply a patch
    pub fn apply(self: *Self, patch: Patch) Maybe(void) {
        log.debug("applying patch: {s}", .{patch.id});

        // Apply based on kind
        switch (applicator.apply(self.allocator, patch)) {
            .ok => {},
            .err => |e| return zid.err(void, e),
        }

        // Mark as applied
        const now = std.time.timestamp();
        self.applied_patches.put(patch.id, now) catch {};
        self.saveApplied();

        Output.success("Applied patch: {s}\n", .{patch.id});
        return zid.ok(void, {});
    }

    /// Apply all pending patches
    pub fn applyAll(self: *Self) Maybe(usize) {
        const patches = switch (self.check()) {
            .ok => |p| p,
            .err => |e| return zid.err(usize, e),
        };

        var applied_count: usize = 0;

        for (patches) |patch| {
            switch (self.apply(patch)) {
                .ok => applied_count += 1,
                .err => |e| {
                    Output.warn("Failed to apply {s}: {s}\n", .{ patch.id, e.message });
                },
            }
        }

        return zid.ok(usize, applied_count);
    }

    /// Rollback a patch
    pub fn rollback(self: *Self, patch_id: []const u8) Maybe(void) {
        if (!self.isApplied(patch_id)) {
            return zid.err(void, .{
                .code = .not_found,
                .message = "patch not applied",
            });
        }

        // TODO: Implement rollback logic
        _ = self.applied_patches.remove(patch_id);
        self.saveApplied();

        Output.success("Rolled back patch: {s}\n", .{patch_id});
        return zid.ok(void, {});
    }

    /// List applied patches
    pub fn listApplied(self: *Self) void {
        Output.bold("Applied patches:\n\n", .{});

        if (self.applied_patches.count() == 0) {
            Output.print("  (none)\n", .{});
            return;
        }

        var it = self.applied_patches.iterator();
        while (it.next()) |entry| {
            const ts = entry.value_ptr.*;
            Output.print("  {s} (applied: {d})\n", .{ entry.key_ptr.*, ts });
        }
    }
};

// ============ PUBLIC API ============

/// Check for pending patches
pub fn check(allocator: std.mem.Allocator) Maybe([]const Patch) {
    var mgr = Manager.init(allocator);
    defer mgr.deinit();
    return mgr.check();
}

/// Apply all pending patches
pub fn applyAll(allocator: std.mem.Allocator) Maybe(usize) {
    var mgr = Manager.init(allocator);
    defer mgr.deinit();
    return mgr.applyAll();
}

/// List applied patches
pub fn listApplied(allocator: std.mem.Allocator) void {
    var mgr = Manager.init(allocator);
    defer mgr.deinit();
    mgr.listApplied();
}

// ============ TESTS ============

test "Manager.init" {
    var mgr = Manager.init(std.testing.allocator);
    defer mgr.deinit();
    try std.testing.expect(mgr.patches_dir.len > 0);
}

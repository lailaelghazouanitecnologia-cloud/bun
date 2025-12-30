//! Apps Database - Persistent storage for registered apps
//!
//! Stores app registrations in ~/.zid/apps.json
//! Format: { "appname": { "path": "/full/path", "type": "binary|script" } }

const std = @import("std");
const zid = @import("../zid.zig");
const Maybe = zid.Maybe;

const log = zid.ScopedLog("apps.db");

/// App entry in database
pub const AppEntry = struct {
    name: []const u8,
    path: []const u8,
    kind: AppKind,
    added_at: i64, // Unix timestamp

    pub fn jsonStringify(self: *const AppEntry, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("path");
        try jw.write(self.path);
        try jw.objectField("kind");
        try jw.write(@tagName(self.kind));
        try jw.objectField("added_at");
        try jw.write(self.added_at);
        try jw.endObject();
    }
};

pub const AppKind = enum {
    binary, // Compiled executable
    script, // Script file (JS, Python, etc.)
    project, // Zid project (build before run)
};

/// Database manager
pub const Database = struct {
    allocator: std.mem.Allocator,
    db_path: []const u8,
    entries: std.StringHashMap(AppEntry),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const home = zid.getHome();
        var path_buf: [256]u8 = undefined;
        const db_path = std.fmt.bufPrint(&path_buf, "{s}/apps.json", .{home}) catch "~/.zid/apps.json";

        return .{
            .allocator = allocator,
            .db_path = db_path,
            .entries = std.StringHashMap(AppEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit();
    }

    /// Load database from disk
    pub fn load(self: *Self) Maybe(void) {
        const file = std.fs.openFileAbsolute(self.db_path, .{}) catch |e| {
            if (e == error.FileNotFound) {
                // No database yet, start fresh
                return zid.ok(void, {});
            }
            return zid.fail(void, e, .read_file, self.db_path);
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch |e| {
            return zid.fail(void, e, .read_file, self.db_path);
        };
        defer self.allocator.free(content);

        // Parse JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            content,
            .{},
        ) catch {
            return zid.err(void, .{ .code = .parse_error, .message = "invalid apps.json" });
        };
        defer parsed.deinit();

        // Load entries
        if (parsed.value == .object) {
            var it = parsed.value.object.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                const obj = entry.value_ptr.*;

                if (obj != .object) continue;

                const path = if (obj.object.get("path")) |p| switch (p) {
                    .string => |s| s,
                    else => continue,
                } else continue;

                const kind_str = if (obj.object.get("kind")) |k| switch (k) {
                    .string => |s| s,
                    else => "binary",
                } else "binary";

                const kind: AppKind = std.meta.stringToEnum(AppKind, kind_str) orelse .binary;

                const added_at: i64 = if (obj.object.get("added_at")) |a| switch (a) {
                    .integer => |i| i,
                    else => 0,
                } else 0;

                self.entries.put(name, .{
                    .name = name,
                    .path = path,
                    .kind = kind,
                    .added_at = added_at,
                }) catch continue;
            }
        }

        log.debug("loaded {d} apps", .{self.entries.count()});
        return zid.ok(void, {});
    }

    /// Save database to disk
    pub fn save(self: *Self) Maybe(void) {
        // Ensure parent directory exists
        const home = zid.getHome();
        std.fs.makeDirAbsolute(home) catch |e| {
            if (e != error.PathAlreadyExists) {
                return zid.fail(void, e, .write_file, home);
            }
        };

        const file = std.fs.createFileAbsolute(self.db_path, .{}) catch |e| {
            return zid.fail(void, e, .write_file, self.db_path);
        };
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        var jw = std.json.writeStream(buffered.writer(), .{});

        jw.beginObject() catch {};

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            jw.objectField(entry.key_ptr.*) catch {};
            entry.value_ptr.jsonStringify(&jw) catch {};
        }

        jw.endObject() catch {};
        buffered.flush() catch {};

        log.debug("saved {d} apps", .{self.entries.count()});
        return zid.ok(void, {});
    }

    /// Add an app entry
    pub fn add(self: *Self, entry: AppEntry) Maybe(void) {
        self.entries.put(entry.name, entry) catch {
            return zid.err(void, .{ .code = .internal_error, .message = "failed to add app" });
        };
        return self.save();
    }

    /// Remove an app entry
    pub fn remove(self: *Self, name: []const u8) Maybe(bool) {
        if (self.entries.remove(name)) {
            return switch (self.save()) {
                .ok => zid.ok(bool, true),
                .err => |e| zid.err(bool, e),
            };
        }
        return zid.ok(bool, false);
    }

    /// Get an app by name
    pub fn get(self: *Self, name: []const u8) ?AppEntry {
        return self.entries.get(name);
    }

    /// Check if app exists
    pub fn has(self: *Self, name: []const u8) bool {
        return self.entries.contains(name);
    }

    /// Get all apps
    pub fn all(self: *Self) []AppEntry {
        var list = std.ArrayList(AppEntry).init(self.allocator);
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            list.append(entry.value_ptr.*) catch continue;
        }
        return list.toOwnedSlice() catch &.{};
    }
};

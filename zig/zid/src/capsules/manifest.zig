//! Capsule Manifest - Configuration for capsules
//!
//! Each capsule has a manifest file (capsule.json/capsule.yaml)
//! defining metadata, dependencies, and build configuration.

const std = @import("std");
const zid = @import("../zid.zig");
const Maybe = zid.Maybe;

const log = zid.ScopedLog("manifest");

/// Manifest file names
pub const MANIFEST_FILES = [_][]const u8{
    "capsule.json",
    "capsule.yaml",
    "capsule.toml",
};

/// Capsule manifest
pub const Manifest = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8 = "",
    author: []const u8 = "",
    license: []const u8 = "",
    url: []const u8 = "",
    repository: []const u8 = "",
    homepage: []const u8 = "",

    /// Dependencies
    dependencies: []const Dependency = &.{},

    /// Build configuration
    build: ?Build = null,

    /// Platform-specific info
    platforms: []const Platform = &.{},

    /// Dependency on another capsule
    pub const Dependency = struct {
        name: []const u8,
        version: []const u8 = "*",
        optional: bool = false,
    };

    /// Build configuration
    pub const Build = struct {
        /// Build command
        cmd: ?[]const u8 = null,
        /// Source directory
        src_dir: []const u8 = "src",
        /// Output artifacts
        artifacts: []const []const u8 = &.{},
        /// Required tools
        tools: []const []const u8 = &.{},
    };

    /// Platform-specific configuration
    pub const Platform = struct {
        os: []const u8,
        arch: []const u8 = "any",
        url: []const u8 = "",
        checksum: []const u8 = "",
    };
};

/// Parse manifest from JSON
pub fn parseJson(allocator: std.mem.Allocator, json_str: []const u8) Maybe(Manifest) {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_str,
        .{},
    ) catch |e| {
        return zid.fail(Manifest, e, .parse, "capsule.json");
    };
    defer parsed.deinit();

    return parseValue(allocator, parsed.value);
}

/// Parse manifest from JSON value
fn parseValue(allocator: std.mem.Allocator, value: std.json.Value) Maybe(Manifest) {
    const obj = switch (value) {
        .object => |o| o,
        else => return zid.err(Manifest, .{
            .code = .invalid_input,
            .message = "manifest must be an object",
        }),
    };

    // Required fields
    const name = getString(obj, "name") orelse {
        return zid.err(Manifest, .{
            .code = .invalid_input,
            .message = "manifest missing 'name' field",
        });
    };

    const version = getString(obj, "version") orelse {
        return zid.err(Manifest, .{
            .code = .invalid_input,
            .message = "manifest missing 'version' field",
        });
    };

    // Optional fields
    const description = getString(obj, "description") orelse "";
    const author = getString(obj, "author") orelse "";
    const license = getString(obj, "license") orelse "";
    const url = getString(obj, "url") orelse "";
    const repository = getString(obj, "repository") orelse "";
    const homepage = getString(obj, "homepage") orelse "";

    // Parse dependencies
    var deps = std.ArrayList(Manifest.Dependency).init(allocator);
    if (obj.get("dependencies")) |deps_val| {
        switch (deps_val) {
            .object => |deps_obj| {
                var it = deps_obj.iterator();
                while (it.next()) |entry| {
                    const dep_ver = switch (entry.value_ptr.*) {
                        .string => |s| s,
                        else => "*",
                    };
                    deps.append(.{
                        .name = entry.key_ptr.*,
                        .version = dep_ver,
                    }) catch {};
                }
            },
            else => {},
        }
    }

    // Parse build config
    var build: ?Manifest.Build = null;
    if (obj.get("build")) |build_val| {
        switch (build_val) {
            .object => |build_obj| {
                build = .{
                    .cmd = getString(build_obj, "cmd"),
                    .src_dir = getString(build_obj, "src_dir") orelse "src",
                };
            },
            else => {},
        }
    }

    log.debug("parsed manifest: {s}@{s}", .{ name, version });

    return zid.ok(Manifest, .{
        .name = name,
        .version = version,
        .description = description,
        .author = author,
        .license = license,
        .url = url,
        .repository = repository,
        .homepage = homepage,
        .dependencies = deps.items,
        .build = build,
    });
}

/// Helper to get string from object
fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

/// Load manifest from directory
pub fn load(allocator: std.mem.Allocator, dir_path: []const u8) Maybe(Manifest) {
    // Try each manifest file
    for (MANIFEST_FILES) |filename| {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir_path, filename }) catch continue;

        const file = std.fs.openFileAbsolute(path, .{}) catch continue;
        defer file.close();

        const content = file.readToEndAlloc(allocator, 1024 * 1024) catch continue;
        defer allocator.free(content);

        if (std.mem.endsWith(u8, filename, ".json")) {
            return parseJson(allocator, content);
        }
        // TODO: YAML/TOML parsing
    }

    return zid.err(Manifest, .{
        .code = .not_found,
        .message = "no manifest file found",
        .path = dir_path,
    });
}

/// Save manifest to file
pub fn save(allocator: std.mem.Allocator, manifest: Manifest, dir_path: []const u8) Maybe(void) {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/capsule.json", .{dir_path}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    const file = std.fs.createFileAbsolute(path, .{}) catch |e| {
        return zid.fail(void, e, .write_file, path);
    };
    defer file.close();

    // Write JSON manually (simple approach)
    var writer = file.writer();

    writer.print(
        \\{{
        \\  "name": "{s}",
        \\  "version": "{s}",
        \\  "description": "{s}"
        \\}}
    , .{
        manifest.name,
        manifest.version,
        manifest.description,
    }) catch |e| {
        return zid.fail(void, e, .write_file, path);
    };

    _ = allocator;
    return zid.ok(void, {});
}

// ============ TESTS ============

test "parseJson" {
    const json =
        \\{
        \\  "name": "test-capsule",
        \\  "version": "1.0.0",
        \\  "description": "A test capsule"
        \\}
    ;

    const result = parseJson(std.testing.allocator, json);
    switch (result) {
        .ok => |m| {
            try std.testing.expectEqualStrings("test-capsule", m.name);
            try std.testing.expectEqualStrings("1.0.0", m.version);
        },
        .err => |e| {
            std.debug.print("Parse error: {s}\n", .{e.message});
            try std.testing.expect(false);
        },
    }
}

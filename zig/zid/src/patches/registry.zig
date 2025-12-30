//! Patch Registry - Fetch available patches from server
//!
//! Queries the patch server for available patches
//! compatible with the current version.

const std = @import("std");
const zid = @import("../zid.zig");
const patches = @import("patches.zig");
const Maybe = zid.Maybe;

const log = zid.ScopedLog("patch-reg");

/// Patch server endpoint
const PATCH_SERVER = "https://zid.dev/api/patches";

/// Fetch available patches for version
pub fn fetchAvailable(allocator: std.mem.Allocator, version: []const u8) Maybe([]const patches.Patch) {
    var url_buf: [512]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}?version={s}", .{
        PATCH_SERVER,
        version,
    }) catch {
        return zid.err([]const patches.Patch, .{ .code = .internal_error, .message = "URL too long" });
    };

    log.debug("fetching patches: {s}", .{url});

    // Fetch JSON
    const json = switch (fetchUrl(allocator, url)) {
        .ok => |data| data,
        .err => |e| return zid.err([]const patches.Patch, e),
    };
    defer allocator.free(json);

    // Parse patches
    return parsePatches(allocator, json);
}

/// Parse patches from JSON
fn parsePatches(allocator: std.mem.Allocator, json: []const u8) Maybe([]const patches.Patch) {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json,
        .{},
    ) catch |e| {
        return zid.fail([]const patches.Patch, e, .parse, "patches");
    };
    defer parsed.deinit();

    const arr = switch (parsed.value) {
        .array => |a| a,
        else => return zid.err([]const patches.Patch, .{
            .code = .invalid_input,
            .message = "expected array",
        }),
    };

    var result = std.ArrayList(patches.Patch).init(allocator);

    for (arr.items) |item| {
        const obj = switch (item) {
            .object => |o| o,
            else => continue,
        };

        const id = getString(obj, "id") orelse continue;
        const version = getString(obj, "version") orelse "1.0.0";
        const target_version = getString(obj, "target_version") orelse "*";
        const description = getString(obj, "description") orelse "";

        const severity = parseSeverity(getString(obj, "severity") orelse "normal");
        const kind = parseKind(getString(obj, "kind") orelse "config");

        result.append(.{
            .id = id,
            .version = version,
            .target_version = target_version,
            .severity = severity,
            .kind = kind,
            .description = description,
            .url = getString(obj, "url"),
            .checksum = getString(obj, "checksum") orelse "",
        }) catch {};
    }

    return zid.ok([]const patches.Patch, result.items);
}

fn parseSeverity(s: []const u8) patches.Severity {
    if (std.mem.eql(u8, s, "critical")) return .critical;
    if (std.mem.eql(u8, s, "high")) return .high;
    if (std.mem.eql(u8, s, "low")) return .low;
    return .normal;
}

fn parseKind(s: []const u8) patches.PatchKind {
    if (std.mem.eql(u8, s, "script")) return .script;
    if (std.mem.eql(u8, s, "data")) return .data;
    if (std.mem.eql(u8, s, "binary")) return .binary;
    return .config;
}

fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

/// Fetch URL to memory
fn fetchUrl(allocator: std.mem.Allocator, url: []const u8) Maybe([]const u8) {
    const uri = std.Uri.parse(url) catch {
        return zid.err([]const u8, .{
            .code = .invalid_input,
            .message = "invalid URL",
        });
    };

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var req = client.open(.GET, uri, .{}) catch |e| {
        return zid.fail([]const u8, e, .network, url);
    };
    defer req.deinit();

    req.send() catch |e| {
        return zid.fail([]const u8, e, .network, url);
    };

    req.wait() catch |e| {
        return zid.fail([]const u8, e, .network, url);
    };

    if (req.response.status != .ok) {
        // Return empty array on 404 (no patches)
        if (req.response.status == .not_found) {
            return zid.ok([]const u8, "[]");
        }
        return zid.err([]const u8, .{
            .code = .network_error,
            .message = "request failed",
        });
    }

    const body = req.reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch |e| {
        return zid.fail([]const u8, e, .read_file, url);
    };

    return zid.ok([]const u8, body);
}

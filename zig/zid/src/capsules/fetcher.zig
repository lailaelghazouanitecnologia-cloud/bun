//! Capsule Fetcher - Download external capsules
//!
//! Fetches capsules from the registry server.
//! Uses Maybe for error handling and Progress for tracking.

const std = @import("std");
const zid = @import("../zid.zig");
const manifest = @import("manifest.zig");
const registry = @import("registry.zig");

const Maybe = zid.Maybe;
const Output = zid.Output;
const Progress = zid.misc.progress;
const Manifest = manifest.Manifest;

const log = zid.ScopedLog("fetcher");

/// Registry endpoints
const REGISTRY_BASE = "https://zid.dev/api/capsules";
const MANIFEST_ENDPOINT = "/manifest";
const DOWNLOAD_ENDPOINT = "/download";

/// Fetch manifest from registry
pub fn fetchManifest(allocator: std.mem.Allocator, name: []const u8) Maybe(Manifest) {
    var url_buf: [512]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}/{s}{s}", .{
        REGISTRY_BASE,
        name,
        MANIFEST_ENDPOINT,
    }) catch {
        return zid.err(Manifest, .{ .code = .internal_error, .message = "URL too long" });
    };

    log.debug("fetching manifest: {s}", .{url});

    // Download manifest JSON
    const json = switch (downloadToMemory(allocator, url)) {
        .ok => |data| data,
        .err => |e| return zid.err(Manifest, e),
    };
    defer allocator.free(json);

    // Parse manifest
    return manifest.parseJson(allocator, json);
}

/// Download capsule archive
pub fn download(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_dir: []const u8,
) Maybe(void) {
    log.debug("downloading: {s} -> {s}", .{ url, dest_dir });

    // Create temp file for archive
    var archive_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const archive_path = std.fmt.bufPrint(&archive_path_buf, "{s}.tar.gz", .{dest_dir}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    // Download archive
    switch (downloadFile(allocator, url, archive_path)) {
        .ok => {},
        .err => |e| return zid.err(void, e),
    }

    // Extract archive
    const extractor = @import("../toolchain/extractor.zig");
    switch (extractor.extract(allocator, archive_path, dest_dir)) {
        .ok => {},
        .err => |e| return zid.err(void, e),
    }

    // Cleanup archive
    std.fs.deleteFileAbsolute(archive_path) catch {};

    return zid.ok(void, {});
}

/// Download file to path
fn downloadFile(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
) Maybe(usize) {
    const uri = std.Uri.parse(url) catch {
        return zid.err(usize, .{
            .code = .invalid_input,
            .message = "invalid URL",
            .path = url,
        });
    };

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var req = client.open(.GET, uri, .{}) catch |e| {
        return zid.fail(usize, e, .network, url);
    };
    defer req.deinit();

    req.send() catch |e| {
        return zid.fail(usize, e, .network, url);
    };

    req.wait() catch |e| {
        return zid.fail(usize, e, .network, url);
    };

    if (req.response.status != .ok) {
        return zid.err(usize, .{
            .code = .network_error,
            .message = "HTTP error",
            .errno = @intFromEnum(req.response.status),
        });
    }

    // Create output file
    const file = std.fs.createFileAbsolute(dest_path, .{}) catch |e| {
        return zid.fail(usize, e, .write_file, dest_path);
    };
    defer file.close();

    // Read and write
    var total: usize = 0;
    var buf: [8192]u8 = undefined;

    while (true) {
        const bytes = req.reader().read(&buf) catch |e| {
            return zid.fail(usize, e, .read_file, url);
        };
        if (bytes == 0) break;

        file.writeAll(buf[0..bytes]) catch |e| {
            return zid.fail(usize, e, .write_file, dest_path);
        };
        total += bytes;
    }

    log.debug("downloaded {d} bytes", .{total});
    return zid.ok(usize, total);
}

/// Download to memory
fn downloadToMemory(allocator: std.mem.Allocator, url: []const u8) Maybe([]const u8) {
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
        return zid.err([]const u8, .{
            .code = .network_error,
            .message = "HTTP error",
        });
    }

    const body = req.reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch |e| {
        return zid.fail([]const u8, e, .read_file, url);
    };

    return zid.ok([]const u8, body);
}

/// Check if capsule exists in registry
pub fn exists(allocator: std.mem.Allocator, name: []const u8) bool {
    var url_buf: [512]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}/{s}", .{
        REGISTRY_BASE,
        name,
    }) catch return false;

    const uri = std.Uri.parse(url) catch return false;

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var req = client.open(.HEAD, uri, .{}) catch return false;
    defer req.deinit();

    req.send() catch return false;
    req.wait() catch return false;

    return req.response.status == .ok;
}

/// Get available versions for a capsule
pub fn getVersions(allocator: std.mem.Allocator, name: []const u8) Maybe([]const []const u8) {
    var url_buf: [512]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}/{s}/versions", .{
        REGISTRY_BASE,
        name,
    }) catch {
        return zid.err([]const []const u8, .{ .code = .internal_error, .message = "URL too long" });
    };

    const json = switch (downloadToMemory(allocator, url)) {
        .ok => |data| data,
        .err => |e| return zid.err([]const []const u8, e),
    };
    defer allocator.free(json);

    // Parse JSON array of versions
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json,
        .{},
    ) catch |e| {
        return zid.fail([]const []const u8, e, .parse, "versions");
    };
    defer parsed.deinit();

    const arr = switch (parsed.value) {
        .array => |a| a,
        else => return zid.err([]const []const u8, .{
            .code = .invalid_input,
            .message = "expected array",
        }),
    };

    var versions = std.ArrayList([]const u8).init(allocator);
    for (arr.items) |item| {
        switch (item) {
            .string => |s| versions.append(allocator.dupe(u8, s) catch continue) catch {},
            else => {},
        }
    }

    return zid.ok([]const []const u8, versions.items);
}

// ============ TESTS ============

test "URL building" {
    var buf: [512]u8 = undefined;
    const url = std.fmt.bufPrint(&buf, "{s}/{s}{s}", .{
        REGISTRY_BASE,
        "webgpu",
        MANIFEST_ENDPOINT,
    }) catch unreachable;
    try std.testing.expectEqualStrings("https://zid.dev/api/capsules/webgpu/manifest", url);
}

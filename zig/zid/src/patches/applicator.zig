//! Patch Applicator - Apply patches to the system
//!
//! Handles different patch types:
//! - config: Update configuration files
//! - script: Update scripts/behavior
//! - data: Update data files
//! - binary: Trigger full update

const std = @import("std");
const zid = @import("../zid.zig");
const patches = @import("patches.zig");
const Maybe = zid.Maybe;
const Output = zid.Output;

const log = zid.ScopedLog("patch-app");

/// Apply a patch
pub fn apply(allocator: std.mem.Allocator, patch: patches.Patch) Maybe(void) {
    log.debug("applying {s} patch: {s}", .{ @tagName(patch.kind), patch.id });

    return switch (patch.kind) {
        .config => applyConfig(allocator, patch),
        .script => applyScript(allocator, patch),
        .data => applyData(allocator, patch),
        .binary => applyBinary(allocator, patch),
    };
}

/// Apply configuration patch
fn applyConfig(allocator: std.mem.Allocator, patch: patches.Patch) Maybe(void) {
    const url = patch.url orelse {
        return zid.err(void, .{
            .code = .invalid_input,
            .message = "patch has no URL",
        });
    };

    // Download patch content
    const content = switch (downloadPatch(allocator, url)) {
        .ok => |c| c,
        .err => |e| return zid.err(void, e),
    };
    defer allocator.free(content);

    // Parse as JSON config update
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        content,
        .{},
    ) catch |e| {
        return zid.fail(void, e, .parse, "patch content");
    };
    defer parsed.deinit();

    // Apply config changes
    switch (parsed.value) {
        .object => |obj| {
            if (obj.get("file")) |file_val| {
                const file_path = switch (file_val) {
                    .string => |s| s,
                    else => return zid.err(void, .{
                        .code = .invalid_input,
                        .message = "invalid file path",
                    }),
                };

                if (obj.get("content")) |content_val| {
                    const new_content = switch (content_val) {
                        .string => |s| s,
                        else => return zid.err(void, .{
                            .code = .invalid_input,
                            .message = "invalid content",
                        }),
                    };

                    // Write new content
                    const home = zid.getHome();
                    var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{
                        home,
                        file_path,
                    }) catch {
                        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
                    };

                    const file = std.fs.createFileAbsolute(full_path, .{}) catch |e| {
                        return zid.fail(void, e, .write_file, full_path);
                    };
                    defer file.close();

                    file.writeAll(new_content) catch |e| {
                        return zid.fail(void, e, .write_file, full_path);
                    };

                    log.debug("wrote config to {s}", .{full_path});
                }
            }
        },
        else => {
            return zid.err(void, .{
                .code = .invalid_input,
                .message = "patch must be object",
            });
        },
    }

    return zid.ok(void, {});
}

/// Apply script patch
fn applyScript(allocator: std.mem.Allocator, patch: patches.Patch) Maybe(void) {
    const url = patch.url orelse {
        return zid.err(void, .{
            .code = .invalid_input,
            .message = "patch has no URL",
        });
    };

    // Download script
    const script = switch (downloadPatch(allocator, url)) {
        .ok => |c| c,
        .err => |e| return zid.err(void, e),
    };
    defer allocator.free(script);

    // Save script to patches directory
    const home = zid.getHome();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/patches/scripts/{s}.sh", .{
        home,
        patch.id,
    }) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    // Ensure directory exists
    if (std.fs.path.dirname(path)) |dir| {
        std.fs.makeDirAbsolute(dir) catch {};
    }

    const file = std.fs.createFileAbsolute(path, .{}) catch |e| {
        return zid.fail(void, e, .write_file, path);
    };
    defer file.close();

    file.writeAll(script) catch |e| {
        return zid.fail(void, e, .write_file, path);
    };

    // Make executable
    std.fs.cwd().chmod(path, 0o755) catch {};

    log.debug("installed script: {s}", .{path});
    return zid.ok(void, {});
}

/// Apply data patch
fn applyData(allocator: std.mem.Allocator, patch: patches.Patch) Maybe(void) {
    const url = patch.url orelse {
        return zid.err(void, .{
            .code = .invalid_input,
            .message = "patch has no URL",
        });
    };

    // Download data
    const data = switch (downloadPatch(allocator, url)) {
        .ok => |c| c,
        .err => |e| return zid.err(void, e),
    };
    defer allocator.free(data);

    // Save to data directory
    const home = zid.getHome();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/patches/data/{s}", .{
        home,
        patch.id,
    }) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    // Ensure directory exists
    if (std.fs.path.dirname(path)) |dir| {
        std.fs.makeDirAbsolute(dir) catch {};
    }

    const file = std.fs.createFileAbsolute(path, .{}) catch |e| {
        return zid.fail(void, e, .write_file, path);
    };
    defer file.close();

    file.writeAll(data) catch |e| {
        return zid.fail(void, e, .write_file, path);
    };

    log.debug("installed data: {s}", .{path});
    return zid.ok(void, {});
}

/// Apply binary patch (trigger full update)
fn applyBinary(allocator: std.mem.Allocator, patch: patches.Patch) Maybe(void) {
    _ = allocator;

    Output.warn("Patch {s} requires a binary update.\n", .{patch.id});
    Output.print("Run 'zid update' to apply this patch.\n", .{});

    // Don't mark as applied - update command will handle it
    return zid.err(void, .{
        .code = .invalid_input,
        .message = "requires zid update",
    });
}

/// Download patch content
fn downloadPatch(allocator: std.mem.Allocator, url: []const u8) Maybe([]const u8) {
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
            .message = "download failed",
        });
    }

    const body = req.reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch |e| {
        return zid.fail([]const u8, e, .read_file, url);
    };

    return zid.ok([]const u8, body);
}

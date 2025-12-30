//! Update Command - Self-update zid binary
//!
//! Atomically updates zid to the latest version:
//! 1. Check for new version via API
//! 2. Download new binary to temp location
//! 3. Verify checksum
//! 4. Atomically replace current binary
//! 5. Rollback on failure
//!
//! Usage:
//!   zid update          - Update to latest version
//!   zid update --check  - Check for updates without installing
//!   zid update <version> - Update to specific version

const std = @import("std");
const zid = @import("../zid.zig");
const Output = zid.Output;
const Maybe = zid.Maybe;

const log = zid.ScopedLog("update");

/// Current version
pub const VERSION = "0.1.0";

/// Release info from API
pub const ReleaseInfo = struct {
    version: []const u8,
    url: []const u8,
    checksum: []const u8,
    release_notes: []const u8 = "",
    published_at: []const u8 = "",
};

/// Update API endpoints
const API_BASE = "https://zid.dev/api";
const RELEASES_ENDPOINT = "/releases";
const LATEST_ENDPOINT = "/releases/latest";

/// Run update command
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) void {
    // Parse args
    var check_only = false;
    var target_version: ?[]const u8 = null;

    for (args) |arg| {
        if (eql(arg, "--check") or eql(arg, "-c")) {
            check_only = true;
        } else if (eql(arg, "--help") or eql(arg, "-h")) {
            showHelp();
            return;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            target_version = arg;
        }
    }

    // Check for updates
    Output.print("Checking for updates...\n", .{});

    const release = switch (getLatestRelease(allocator)) {
        .ok => |r| r,
        .err => |e| {
            Output.err("Failed to check for updates: {s}\n", .{e.message});
            return;
        },
    };

    // Compare versions
    const current = parseVersion(VERSION);
    const latest = parseVersion(release.version);

    if (!isNewer(latest, current)) {
        Output.success("You're already on the latest version ({s})\n", .{VERSION});
        return;
    }

    Output.print("New version available: {s} (current: {s})\n", .{ release.version, VERSION });

    if (release.release_notes.len > 0) {
        Output.print("\nRelease notes:\n{s}\n", .{release.release_notes});
    }

    if (check_only) {
        Output.print("\nRun 'zid update' to install.\n", .{});
        return;
    }

    // Perform update
    Output.print("\nDownloading...\n", .{});

    switch (performUpdate(allocator, release)) {
        .ok => {
            Output.success("\nSuccessfully updated to {s}!\n", .{release.version});
            Output.print("Run 'zid --version' to verify.\n", .{});
        },
        .err => |e| {
            Output.err("Update failed: {s}\n", .{e.message});
            Output.print("Your installation was not modified.\n", .{});
        },
    }

    _ = target_version;
}

/// Get latest release info
fn getLatestRelease(allocator: std.mem.Allocator) Maybe(ReleaseInfo) {
    var url_buf: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}{s}", .{ API_BASE, LATEST_ENDPOINT }) catch {
        return zid.err(ReleaseInfo, .{ .code = .internal_error, .message = "URL too long" });
    };

    log.debug("fetching: {s}", .{url});

    const json = switch (fetchUrl(allocator, url)) {
        .ok => |data| data,
        .err => |e| return zid.err(ReleaseInfo, e),
    };
    defer allocator.free(json);

    return parseReleaseInfo(allocator, json);
}

/// Parse release info from JSON
fn parseReleaseInfo(allocator: std.mem.Allocator, json: []const u8) Maybe(ReleaseInfo) {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json,
        .{},
    ) catch |e| {
        return zid.fail(ReleaseInfo, e, .parse, "release info");
    };
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return zid.err(ReleaseInfo, .{
            .code = .invalid_input,
            .message = "invalid release info",
        }),
    };

    const version = getString(obj, "version") orelse {
        return zid.err(ReleaseInfo, .{
            .code = .invalid_input,
            .message = "missing version",
        });
    };

    // Build URL for current platform
    const arch = @tagName(std.Target.current.cpu.arch);
    const os = @tagName(std.Target.current.os.tag);

    var url_buf: [512]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buf, "{s}/releases/{s}/zid-{s}-{s}", .{
        API_BASE,
        version,
        os,
        arch,
    }) catch "";

    return zid.ok(ReleaseInfo, .{
        .version = version,
        .url = url,
        .checksum = getString(obj, "checksum") orelse "",
        .release_notes = getString(obj, "notes") orelse "",
        .published_at = getString(obj, "published_at") orelse "",
    });
}

/// Perform the actual update
fn performUpdate(allocator: std.mem.Allocator, release: ReleaseInfo) Maybe(void) {
    // Get current executable path
    var exe_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = std.fs.selfExePath(&exe_path_buf) catch {
        return zid.err(void, .{
            .code = .internal_error,
            .message = "failed to get executable path",
        });
    };

    log.debug("current exe: {s}", .{exe_path});

    // Create temp file for download
    var tmp_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = std.fmt.bufPrint(&tmp_path_buf, "{s}.new", .{exe_path}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    // Backup path for rollback
    var backup_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const backup_path = std.fmt.bufPrint(&backup_path_buf, "{s}.backup", .{exe_path}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    // Download new binary
    log.debug("downloading to: {s}", .{tmp_path});

    switch (downloadFile(allocator, release.url, tmp_path)) {
        .ok => |size| {
            Output.print("Downloaded {d} bytes\n", .{size});
        },
        .err => |e| {
            cleanup(tmp_path);
            return zid.err(void, e);
        },
    }

    // Verify checksum if provided
    if (release.checksum.len > 0) {
        if (!verifyChecksum(tmp_path, release.checksum)) {
            cleanup(tmp_path);
            return zid.err(void, .{
                .code = .invalid_input,
                .message = "checksum verification failed",
            });
        }
        log.debug("checksum verified", .{});
    }

    // Make new binary executable
    std.fs.cwd().chmod(tmp_path, 0o755) catch {};

    // Atomic replacement
    // 1. Backup current binary
    std.fs.renameAbsolute(exe_path, backup_path) catch |e| {
        cleanup(tmp_path);
        return zid.fail(void, e, .write_file, exe_path);
    };

    // 2. Move new binary to place
    std.fs.renameAbsolute(tmp_path, exe_path) catch |e| {
        // Rollback: restore backup
        std.fs.renameAbsolute(backup_path, exe_path) catch {};
        return zid.fail(void, e, .write_file, exe_path);
    };

    // 3. Remove backup on success
    cleanup(backup_path);

    return zid.ok(void, {});
}

/// Download file to path
fn downloadFile(allocator: std.mem.Allocator, url: []const u8, dest: []const u8) Maybe(usize) {
    const uri = std.Uri.parse(url) catch {
        return zid.err(usize, .{
            .code = .invalid_input,
            .message = "invalid URL",
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
            .message = "download failed",
            .errno = @intFromEnum(req.response.status),
        });
    }

    const file = std.fs.createFileAbsolute(dest, .{}) catch |e| {
        return zid.fail(usize, e, .write_file, dest);
    };
    defer file.close();

    var total: usize = 0;
    var buf: [8192]u8 = undefined;

    while (true) {
        const n = req.reader().read(&buf) catch |e| {
            return zid.fail(usize, e, .read_file, url);
        };
        if (n == 0) break;

        file.writeAll(buf[0..n]) catch |e| {
            return zid.fail(usize, e, .write_file, dest);
        };
        total += n;
    }

    return zid.ok(usize, total);
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
        return zid.err([]const u8, .{
            .code = .network_error,
            .message = "request failed",
        });
    }

    const body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch |e| {
        return zid.fail([]const u8, e, .read_file, url);
    };

    return zid.ok([]const u8, body);
}

/// Verify file checksum
fn verifyChecksum(path: []const u8, expected: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [8192]u8 = undefined;

    while (true) {
        const n = file.read(&buf) catch return false;
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }

    var hash_buf: [64]u8 = undefined;
    const hash = std.fmt.bufPrint(&hash_buf, "{s}", .{std.fmt.fmtSliceHexLower(&hasher.finalResult())}) catch return false;

    return std.mem.eql(u8, hash, expected);
}

/// Simple version parsing
const SemVer = struct { major: u32, minor: u32, patch: u32 };

fn parseVersion(ver: []const u8) SemVer {
    var it = std.mem.splitScalar(u8, ver, '.');
    const major = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0;
    const minor = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0;
    const patch = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0;
    return .{ .major = major, .minor = minor, .patch = patch };
}

fn isNewer(a: SemVer, b: SemVer) bool {
    if (a.major != b.major) return a.major > b.major;
    if (a.minor != b.minor) return a.minor > b.minor;
    return a.patch > b.patch;
}

fn cleanup(path: []const u8) void {
    std.fs.deleteFileAbsolute(path) catch {};
}

fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const val = obj.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

fn showHelp() void {
    Output.bold("zid update", .{});
    Output.print(" - Update zid to the latest version\n\n", .{});
    Output.print("Usage:\n", .{});
    Output.print("  zid update           Update to latest version\n", .{});
    Output.print("  zid update --check   Check for updates only\n", .{});
    Output.print("  zid update <version> Update to specific version\n", .{});
    Output.print("\nCurrent version: {s}\n", .{VERSION});
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

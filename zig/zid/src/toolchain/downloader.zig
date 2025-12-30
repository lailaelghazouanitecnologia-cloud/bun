//! Downloader - HTTP client with progress tracking
//!
//! Downloads files with progress callback using misc.Progress.
//! Uses Maybe for error handling.

const std = @import("std");
const zid = @import("../zid.zig");
const Maybe = zid.Maybe;
const Progress = zid.misc.progress;
const Output = zid.Output;

const log = zid.ScopedLog("download");

/// Download state
pub const Download = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
    total_size: ?usize = null,
    downloaded: usize = 0,
    progress_node: ?*Progress.Node = null,

    /// Download result
    pub const Result = struct {
        path: []const u8,
        size: usize,
        hash: u64,
    };

    pub fn init(allocator: std.mem.Allocator, url: []const u8, dest_path: []const u8) Download {
        return .{
            .allocator = allocator,
            .url = url,
            .dest_path = dest_path,
        };
    }

    /// Set progress node for updates
    pub fn setProgress(self: *Download, node: *Progress.Node) void {
        self.progress_node = node;
    }

    /// Execute download
    pub fn run(self: *Download) Maybe(Result) {
        log.debug("downloading {s}", .{self.url});

        // Parse URL
        const uri = std.Uri.parse(self.url) catch {
            return zid.err(Result, .{
                .code = .invalid_input,
                .message = "invalid URL",
                .path = self.url,
            });
        };

        // Create HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Create output file
        const file = std.fs.createFileAbsolute(self.dest_path, .{}) catch |e| {
            return zid.fail(Result, e, .write_file, self.dest_path);
        };
        defer file.close();

        // Make request
        var req = client.open(.GET, uri, .{}) catch |e| {
            return zid.fail(Result, e, .network, self.url);
        };
        defer req.deinit();

        req.send() catch |e| {
            return zid.fail(Result, e, .network, self.url);
        };

        req.wait() catch |e| {
            return zid.fail(Result, e, .network, self.url);
        };

        // Check response status
        if (req.response.status != .ok) {
            return zid.err(Result, .{
                .code = .network_error,
                .message = "HTTP error",
                .errno = @intFromEnum(req.response.status),
            });
        }

        // Get content length
        if (req.response.content_length) |len| {
            self.total_size = len;
            if (self.progress_node) |node| {
                node.setTotal(len);
            }
        }

        // Read response body in chunks
        var hasher = std.hash.Wyhash.init(0);
        var buf: [8192]u8 = undefined;

        while (true) {
            const bytes_read = req.reader().read(&buf) catch |e| {
                return zid.fail(Result, e, .read_file, self.url);
            };

            if (bytes_read == 0) break;

            // Write to file
            file.writeAll(buf[0..bytes_read]) catch |e| {
                return zid.fail(Result, e, .write_file, self.dest_path);
            };

            // Update hash
            hasher.update(buf[0..bytes_read]);

            // Update progress
            self.downloaded += bytes_read;
            if (self.progress_node) |node| {
                node.setCompleted(self.downloaded);
            }
        }

        log.debug("downloaded {d} bytes", .{self.downloaded});

        return zid.ok(Result, .{
            .path = self.dest_path,
            .size = self.downloaded,
            .hash = hasher.final(),
        });
    }
};

/// Simple download function
pub fn download(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
) Maybe(Download.Result) {
    var dl = Download.init(allocator, url, dest_path);
    return dl.run();
}

/// Download with progress bar
pub fn downloadWithProgress(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
    label: []const u8,
) Maybe(Download.Result) {
    var progress_ctx = Progress{};
    const root = progress_ctx.start(label, 0);
    defer root.end();

    var dl = Download.init(allocator, url, dest_path);
    dl.setProgress(root);

    return dl.run();
}

/// Download to memory (for small files)
pub fn downloadToMemory(
    allocator: std.mem.Allocator,
    url: []const u8,
) Maybe([]const u8) {
    log.debug("downloading to memory: {s}", .{url});

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

/// Check if URL is reachable (HEAD request)
pub fn checkUrl(allocator: std.mem.Allocator, url: []const u8) bool {
    const uri = std.Uri.parse(url) catch return false;

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var req = client.open(.HEAD, uri, .{}) catch return false;
    defer req.deinit();

    req.send() catch return false;
    req.wait() catch return false;

    return req.response.status == .ok;
}

// ============ TESTS ============

test "Download.init" {
    const dl = Download.init(std.testing.allocator, "https://example.com/file", "/tmp/file");
    try std.testing.expectEqualStrings("https://example.com/file", dl.url);
    try std.testing.expectEqualStrings("/tmp/file", dl.dest_path);
}

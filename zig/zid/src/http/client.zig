//! HTTP Client
//!
//! Simple HTTP client wrapper for downloading files and making requests.
//! Designed for toolchain downloads with progress reporting.
//!
//! Usage:
//!   var client = Client.init(allocator);
//!   defer client.deinit();
//!
//!   // Simple GET
//!   const response = try client.get("https://example.com/api");
//!   defer response.deinit();
//!
//!   // Download with progress
//!   try client.download("https://example.com/file.zip", "/tmp/file.zip", progress);

const std = @import("std");
const Allocator = std.mem.Allocator;
const Uri = std.Uri;

const zid = @import("../zid.zig");
const Environment = zid.Environment;
const Maybe = zid.Maybe;
const Error = zid.Error;
const feature_flags = zid.feature_flags;

// ============ TYPES ============

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    PATCH,
    OPTIONS,

    pub fn toString(self: Method) []const u8 {
        return @tagName(self);
    }
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Response = struct {
    allocator: Allocator,
    status: u16,
    body: []const u8,
    headers: std.StringHashMap([]const u8),

    pub fn ok(self: Response) bool {
        return self.status >= 200 and self.status < 300;
    }

    pub fn isRedirect(self: Response) bool {
        return self.status >= 300 and self.status < 400;
    }

    pub fn getHeader(self: Response, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
        self.headers.deinit();
    }
};

pub const RequestOptions = struct {
    method: Method = .GET,
    headers: []const Header = &.{},
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30_000,
    follow_redirects: bool = true,
    max_redirects: u8 = 5,
};

pub const DownloadOptions = struct {
    timeout_ms: u32 = 300_000, // 5 minutes for downloads
    chunk_size: usize = 64 * 1024, // 64KB chunks
    verify_size: bool = true,
};

pub const Progress = struct {
    total: u64 = 0,
    current: u64 = 0,
    callback: ?*const fn (current: u64, total: u64, userdata: ?*anyopaque) void = null,
    userdata: ?*anyopaque = null,

    pub fn update(self: *Progress, bytes: u64) void {
        self.current += bytes;
        if (self.callback) |cb| {
            cb(self.current, self.total, self.userdata);
        }
    }

    pub fn percent(self: Progress) u8 {
        if (self.total == 0) return 0;
        return @intCast(@min(100, (self.current * 100) / self.total));
    }
};

// ============ CLIENT ============

pub const Client = struct {
    allocator: Allocator,
    default_timeout_ms: u32,
    user_agent: []const u8,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .default_timeout_ms = feature_flags.default_http_timeout * 1000,
            .user_agent = "zid/" ++ zid.version_string,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // No resources to free currently
    }

    /// Simple GET request
    pub fn get(self: *Self, url: []const u8) Maybe(Response) {
        return self.request(url, .{});
    }

    /// POST request with body
    pub fn post(self: *Self, url: []const u8, body: []const u8) Maybe(Response) {
        return self.request(url, .{
            .method = .POST,
            .body = body,
        });
    }

    /// General request
    pub fn request(self: *Self, url: []const u8, options: RequestOptions) Maybe(Response) {
        // Parse URL
        const uri = Uri.parse(url) catch {
            return .{ .err = .{
                .code = .invalid_input,
                .message = "Invalid URL",
                .path = url,
                .step = .network,
            } };
        };

        // Create HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Build request
        var req = client.open(
            @enumFromInt(@intFromEnum(options.method)),
            uri,
            .{
                .server_header_buffer = self.allocator.alloc(u8, 16 * 1024) catch {
                    return .{ .err = .{
                        .code = .out_of_memory,
                        .message = "Failed to allocate header buffer",
                        .step = .network,
                    } };
                },
            },
        ) catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .connect,
            } };
        };
        defer req.deinit();

        // Add headers
        req.headers.user_agent = .{ .override = self.user_agent };
        for (options.headers) |header| {
            req.headers.append(
                @enumFromInt(std.http.Header.name2int(header.name) orelse continue),
                header.value,
            );
        }

        // Send request
        req.send() catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .network,
            } };
        };

        // Write body if present
        if (options.body) |body| {
            req.writer().writeAll(body) catch |e| {
                return .{ .err = .{
                    .code = mapHttpError(e),
                    .message = @errorName(e),
                    .path = url,
                    .step = .network,
                } };
            };
        }

        req.finish() catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .network,
            } };
        };

        // Wait for response
        req.wait() catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .network,
            } };
        };

        // Read body
        const body = req.reader().readAllAlloc(self.allocator, 100 * 1024 * 1024) catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .download,
            } };
        };

        return .{ .ok = .{
            .allocator = self.allocator,
            .status = @intFromEnum(req.status),
            .body = body,
            .headers = std.StringHashMap([]const u8).init(self.allocator),
        } };
    }

    /// Download file with optional progress
    pub fn download(
        self: *Self,
        url: []const u8,
        dest_path: []const u8,
        progress: ?*Progress,
        options: DownloadOptions,
    ) Maybe(void) {
        _ = options;

        // Parse URL
        const uri = Uri.parse(url) catch {
            return .{ .err = .{
                .code = .invalid_input,
                .message = "Invalid URL",
                .path = url,
                .step = .network,
            } };
        };

        // Create HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Open request
        var req = client.open(.GET, uri, .{
            .server_header_buffer = self.allocator.alloc(u8, 16 * 1024) catch {
                return .{ .err = .{
                    .code = .out_of_memory,
                    .message = "Failed to allocate header buffer",
                    .step = .network,
                } };
            },
        }) catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .connect,
            } };
        };
        defer req.deinit();

        req.headers.user_agent = .{ .override = self.user_agent };

        req.send() catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .network,
            } };
        };

        req.finish() catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .network,
            } };
        };

        req.wait() catch |e| {
            return .{ .err = .{
                .code = mapHttpError(e),
                .message = @errorName(e),
                .path = url,
                .step = .network,
            } };
        };

        // Get content length for progress
        if (progress) |p| {
            if (req.response.content_length) |len| {
                p.total = len;
            }
        }

        // Open destination file
        const file = std.fs.cwd().createFile(dest_path, .{}) catch |e| {
            return .{ .err = .{
                .code = .permission_denied,
                .message = @errorName(e),
                .path = dest_path,
                .step = .write_file,
            } };
        };
        defer file.close();

        // Read and write in chunks
        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            const bytes_read = req.reader().read(&buf) catch |e| {
                return .{ .err = .{
                    .code = mapHttpError(e),
                    .message = @errorName(e),
                    .path = url,
                    .step = .download,
                } };
            };

            if (bytes_read == 0) break;

            file.writeAll(buf[0..bytes_read]) catch |e| {
                return .{ .err = .{
                    .code = .io_error,
                    .message = @errorName(e),
                    .path = dest_path,
                    .step = .write_file,
                } };
            };

            if (progress) |p| {
                p.update(bytes_read);
            }
        }

        return .{ .ok = {} };
    }

    fn mapHttpError(e: anyerror) Error.Code {
        return switch (e) {
            error.ConnectionRefused => .connection_refused,
            error.ConnectionResetByPeer => .connection_reset,
            error.HostUnreachable => .host_not_found,
            error.NetworkUnreachable => .network_error,
            error.Timeout, error.ConnectionTimedOut => .timeout,
            error.OutOfMemory => .out_of_memory,
            else => .network_error,
        };
    }
};

// ============ CONVENIENCE FUNCTIONS ============

/// Quick GET request
pub fn get(allocator: Allocator, url: []const u8) Maybe(Response) {
    var client = Client.init(allocator);
    defer client.deinit();
    return client.get(url);
}

/// Quick download
pub fn download(allocator: Allocator, url: []const u8, dest: []const u8) Maybe(void) {
    var client = Client.init(allocator);
    defer client.deinit();
    return client.download(url, dest, null, .{});
}

// ============ URL UTILITIES ============

pub const Url = struct {
    scheme: []const u8,
    host: []const u8,
    port: ?u16,
    path: []const u8,
    query: ?[]const u8,

    pub fn parse(url: []const u8) ?Url {
        const uri = Uri.parse(url) catch return null;
        return .{
            .scheme = if (uri.scheme) |s| s else "https",
            .host = if (uri.host) |h| h.raw else return null,
            .port = uri.port,
            .path = if (uri.path.raw.len > 0) uri.path.raw else "/",
            .query = if (uri.query) |q| q.raw else null,
        };
    }

    pub fn isHttps(self: Url) bool {
        return std.mem.eql(u8, self.scheme, "https");
    }
};

// ============ TESTS ============

test "Url.parse valid URL" {
    const url = Url.parse("https://example.com/path?query=1");
    try std.testing.expect(url != null);
    try std.testing.expectEqualStrings("https", url.?.scheme);
    try std.testing.expectEqualStrings("example.com", url.?.host);
    try std.testing.expectEqualStrings("/path", url.?.path);
}

test "Url.parse with port" {
    const url = Url.parse("http://localhost:8080/api");
    try std.testing.expect(url != null);
    try std.testing.expectEqual(@as(?u16, 8080), url.?.port);
}

test "Url.isHttps" {
    const https_url = Url.parse("https://example.com").?;
    const http_url = Url.parse("http://example.com").?;

    try std.testing.expect(https_url.isHttps());
    try std.testing.expect(!http_url.isHttps());
}

test "Progress.percent" {
    var progress = Progress{ .total = 100, .current = 0 };
    try std.testing.expectEqual(@as(u8, 0), progress.percent());

    progress.current = 50;
    try std.testing.expectEqual(@as(u8, 50), progress.percent());

    progress.current = 100;
    try std.testing.expectEqual(@as(u8, 100), progress.percent());
}

test "Progress.percent with zero total" {
    const progress = Progress{ .total = 0, .current = 50 };
    try std.testing.expectEqual(@as(u8, 0), progress.percent());
}

test "Client.init" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    try std.testing.expect(client.default_timeout_ms > 0);
    try std.testing.expect(std.mem.startsWith(u8, client.user_agent, "zid/"));
}

test "Method.toString" {
    try std.testing.expectEqualStrings("GET", Method.GET.toString());
    try std.testing.expectEqualStrings("POST", Method.POST.toString());
    try std.testing.expectEqualStrings("DELETE", Method.DELETE.toString());
}

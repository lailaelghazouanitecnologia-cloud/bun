//! HTTP API
//!
//! Cliente HTTP simple.
//!
//! ```zig
//! const zid = @import("zid");
//!
//! // GET request
//! const body = try zid.http.get("https://api.example.com/data");
//!
//! // POST request
//! const resp = try zid.http.post("https://api.example.com/users", .{
//!     .body = "{\"name\": \"test\"}",
//!     .headers = &.{.{ "Content-Type", "application/json" }},
//! });
//!
//! // Download file
//! try zid.http.download("https://example.com/file.zip", "local.zip");
//! ```

const std = @import("std");

// ============ GET ============

/// Simple GET request
pub fn get(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    const resp = try request(allocator, .GET, url, .{});
    return resp.body;
}

/// GET with headers
pub fn getWithHeaders(
    allocator: std.mem.Allocator,
    url: []const u8,
    headers: []const Header,
) ![]u8 {
    const resp = try request(allocator, .GET, url, .{ .headers = headers });
    return resp.body;
}

// ============ POST ============

/// Simple POST request
pub fn post(allocator: std.mem.Allocator, url: []const u8, opts: RequestOptions) !Response {
    return request(allocator, .POST, url, opts);
}

/// POST JSON
pub fn postJson(allocator: std.mem.Allocator, url: []const u8, body: []const u8) !Response {
    return request(allocator, .POST, url, .{
        .body = body,
        .headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
    });
}

// ============ REQUEST ============

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const RequestOptions = struct {
    body: ?[]const u8 = null,
    headers: []const Header = &.{},
    timeout_ms: u32 = 30000,
    follow_redirects: bool = true,
};

pub const Response = struct {
    status: u16,
    body: []u8,
    headers: []Header,

    pub fn ok(self: Response) bool {
        return self.status >= 200 and self.status < 300;
    }

    pub fn json(self: Response, comptime T: type, allocator: std.mem.Allocator) !T {
        return std.json.parseFromSlice(T, allocator, self.body, .{});
    }
};

/// Make HTTP request
pub fn request(
    allocator: std.mem.Allocator,
    method: Method,
    url: []const u8,
    opts: RequestOptions,
) !Response {
    // Parse URL
    const uri = try std.Uri.parse(url);

    // Create client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Build headers
    var headers = std.http.Client.Request.Headers{};
    for (opts.headers) |h| {
        if (std.mem.eql(u8, h.name, "Content-Type")) {
            headers.content_type = .{ .override = h.value };
        }
    }

    // Make request
    const http_method = switch (method) {
        .GET => .GET,
        .POST => .POST,
        .PUT => .PUT,
        .DELETE => .DELETE,
        .PATCH => .PATCH,
        .HEAD => .HEAD,
        .OPTIONS => .OPTIONS,
    };

    var req = try client.open(http_method, uri, .{
        .headers = headers,
    });
    defer req.deinit();

    if (opts.body) |body| {
        req.transfer_encoding = .{ .content_length = body.len };
    }

    try req.send();

    if (opts.body) |body| {
        try req.writer().writeAll(body);
        try req.finish();
    }

    try req.wait();

    // Read response
    const body = try req.reader().readAllAlloc(allocator, 10 * 1024 * 1024);

    return .{
        .status = @intFromEnum(req.status),
        .body = body,
        .headers = &.{},
    };
}

// ============ DOWNLOAD ============

/// Download file to path
pub fn download(allocator: std.mem.Allocator, url: []const u8, dest: []const u8) !void {
    const body = try get(allocator, url);
    defer allocator.free(body);

    const file = try std.fs.cwd().createFile(dest, .{});
    defer file.close();
    try file.writeAll(body);
}

/// Download with progress callback
pub fn downloadWithProgress(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest: []const u8,
    progress_fn: *const fn (downloaded: u64, total: ?u64) void,
) !void {
    _ = progress_fn;
    // For now, just use simple download
    try download(allocator, url, dest);
}

// ============ HELPERS ============

/// URL encode string
pub fn urlEncode(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    for (str) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try result.append(c);
        } else {
            try result.writer().print("%{X:0>2}", .{c});
        }
    }

    return result.toOwnedSlice();
}

/// Build query string from params
pub fn buildQuery(allocator: std.mem.Allocator, params: anytype) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    const T = @TypeOf(params);
    const info = @typeInfo(T);

    if (info == .Struct) {
        var first = true;
        inline for (info.Struct.fields) |field| {
            if (!first) try result.append('&');
            first = false;

            try result.appendSlice(field.name);
            try result.append('=');

            const val = @field(params, field.name);
            const encoded = try urlEncode(allocator, val);
            defer allocator.free(encoded);
            try result.appendSlice(encoded);
        }
    }

    return result.toOwnedSlice();
}

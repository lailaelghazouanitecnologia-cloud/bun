//! Registry - Tool definitions and download URLs
//!
//! Defines supported tools with their download sources.
//! Uses misc patterns for error handling and logging.

const std = @import("std");
const zid = @import("../zid.zig");
const Version = @import("versions.zig").Version;
const Maybe = zid.Maybe;
const Environment = zid.Environment;

const log = zid.ScopedLog("registry");

/// Supported tool types
pub const ToolKind = enum {
    bun,
    zig,
    node,
    deno,
    go,
    rust,

    pub fn string(self: ToolKind) []const u8 {
        return @tagName(self);
    }

    pub fn fromString(s: []const u8) ?ToolKind {
        inline for (std.meta.fields(ToolKind)) |f| {
            if (std.mem.eql(u8, s, f.name)) {
                return @enumFromInt(f.value);
            }
        }
        return null;
    }
};

/// Tool definition with download info
pub const ToolDef = struct {
    kind: ToolKind,
    name: []const u8,
    description: []const u8,
    homepage: []const u8,
    /// URL template with {version}, {os}, {arch} placeholders
    url_template: []const u8,
    /// Archive format
    archive: Archive,
    /// Binary name inside archive
    binary: []const u8,
    /// Path inside archive to binary (optional)
    binary_path: ?[]const u8 = null,

    pub const Archive = enum {
        tar_gz,
        tar_xz,
        zip,
        none, // Direct binary
    };

    /// Get download URL for specific version and platform
    pub fn getUrl(self: ToolDef, version: Version, buf: []u8) Maybe([]const u8) {
        const os_str = getOsString();
        const arch_str = getArchString();

        var ver_buf: [32]u8 = undefined;
        const ver_str = if (version.isLatest())
            "latest"
        else
            version.format(&ver_buf);

        // Simple template replacement
        var result_len: usize = 0;
        var i: usize = 0;
        const template = self.url_template;

        while (i < template.len) {
            if (i + 8 < template.len and std.mem.eql(u8, template[i .. i + 9], "{version}")) {
                @memcpy(buf[result_len .. result_len + ver_str.len], ver_str);
                result_len += ver_str.len;
                i += 9;
            } else if (i + 3 < template.len and std.mem.eql(u8, template[i .. i + 4], "{os}")) {
                @memcpy(buf[result_len .. result_len + os_str.len], os_str);
                result_len += os_str.len;
                i += 4;
            } else if (i + 5 < template.len and std.mem.eql(u8, template[i .. i + 6], "{arch}")) {
                @memcpy(buf[result_len .. result_len + arch_str.len], arch_str);
                result_len += arch_str.len;
                i += 6;
            } else {
                buf[result_len] = template[i];
                result_len += 1;
                i += 1;
            }
        }

        return zid.ok([]const u8, buf[0..result_len]);
    }

    fn getOsString() []const u8 {
        if (Environment.isMac) return "darwin";
        if (Environment.isLinux) return "linux";
        if (Environment.isWindows) return "windows";
        return "unknown";
    }

    fn getArchString() []const u8 {
        if (Environment.isAarch64) return "aarch64";
        if (Environment.isX64) return "x86_64";
        return "unknown";
    }
};

/// Tool registry - all supported tools
pub const tools = [_]ToolDef{
    // Bun
    .{
        .kind = .bun,
        .name = "bun",
        .description = "JavaScript runtime & toolkit",
        .homepage = "https://bun.sh",
        .url_template = "https://github.com/oven-sh/bun/releases/download/bun-v{version}/bun-{os}-{arch}.zip",
        .archive = .zip,
        .binary = "bun",
        .binary_path = "bun-{os}-{arch}",
    },
    // Zig
    .{
        .kind = .zig,
        .name = "zig",
        .description = "Systems programming language",
        .homepage = "https://ziglang.org",
        .url_template = "https://ziglang.org/download/{version}/zig-{os}-{arch}-{version}.tar.xz",
        .archive = .tar_xz,
        .binary = "zig",
    },
    // Node.js
    .{
        .kind = .node,
        .name = "node",
        .description = "JavaScript runtime",
        .homepage = "https://nodejs.org",
        .url_template = "https://nodejs.org/dist/v{version}/node-v{version}-{os}-{arch}.tar.gz",
        .archive = .tar_gz,
        .binary = "node",
        .binary_path = "bin",
    },
    // Deno
    .{
        .kind = .deno,
        .name = "deno",
        .description = "Secure JavaScript/TypeScript runtime",
        .homepage = "https://deno.land",
        .url_template = "https://github.com/denoland/deno/releases/download/v{version}/deno-{arch}-{os}.zip",
        .archive = .zip,
        .binary = "deno",
    },
    // Go
    .{
        .kind = .go,
        .name = "go",
        .description = "Go programming language",
        .homepage = "https://go.dev",
        .url_template = "https://go.dev/dl/go{version}.{os}-{arch}.tar.gz",
        .archive = .tar_gz,
        .binary = "go",
        .binary_path = "bin",
    },
    // Rust (rustup)
    .{
        .kind = .rust,
        .name = "rust",
        .description = "Rust programming language",
        .homepage = "https://rust-lang.org",
        .url_template = "https://static.rust-lang.org/rustup/dist/{arch}-{os}/rustup-init",
        .archive = .none,
        .binary = "rustup-init",
    },
};

/// Get tool definition by kind
pub fn get(kind: ToolKind) *const ToolDef {
    for (&tools) |*t| {
        if (t.kind == kind) return t;
    }
    unreachable;
}

/// Get tool definition by name
pub fn getByName(name: []const u8) ?*const ToolDef {
    const kind = ToolKind.fromString(name) orelse return null;
    return get(kind);
}

/// List all supported tools
pub fn listAll() []const ToolDef {
    return &tools;
}

/// Parse tool spec (e.g., "bun@1.1.0", "zig", "node@latest")
pub const ToolSpec = struct {
    kind: ToolKind,
    version: Version,

    pub fn parse(spec: []const u8) Maybe(ToolSpec) {
        const at_pos = std.mem.indexOf(u8, spec, "@");
        const name = if (at_pos) |p| spec[0..p] else spec;
        const ver_str = if (at_pos) |p| spec[p + 1 ..] else "latest";

        const kind = ToolKind.fromString(name) orelse {
            return zid.err(ToolSpec, .{
                .code = .not_found,
                .message = "unknown tool",
                .path = name,
            });
        };

        return switch (Version.parse(ver_str)) {
            .ok => |v| zid.ok(ToolSpec, .{ .kind = kind, .version = v }),
            .err => |e| zid.err(ToolSpec, e),
        };
    }

    pub fn getDef(self: ToolSpec) *const ToolDef {
        return get(self.kind);
    }
};

// ============ TESTS ============

test "ToolKind.fromString" {
    try std.testing.expectEqual(ToolKind.bun, ToolKind.fromString("bun").?);
    try std.testing.expectEqual(ToolKind.zig, ToolKind.fromString("zig").?);
    try std.testing.expect(ToolKind.fromString("invalid") == null);
}

test "ToolSpec.parse" {
    const spec1 = ToolSpec.parse("bun@1.1.0").unwrap();
    try std.testing.expectEqual(ToolKind.bun, spec1.kind);
    try std.testing.expectEqual(@as(u32, 1), spec1.version.major);
    try std.testing.expectEqual(@as(u32, 1), spec1.version.minor);

    const spec2 = ToolSpec.parse("zig").unwrap();
    try std.testing.expectEqual(ToolKind.zig, spec2.kind);
    try std.testing.expect(spec2.version.isLatest());
}

test "ToolDef.getUrl" {
    const bun = get(.bun);
    var buf: [256]u8 = undefined;
    const url = bun.getUrl(Version.parse("1.1.0").unwrap(), &buf).unwrap();
    try std.testing.expect(std.mem.indexOf(u8, url, "1.1.0") != null);
}

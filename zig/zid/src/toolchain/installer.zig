const std = @import("std");
const registry = @import("registry.zig");

/// Tool Installer
/// Downloads and installs development tools from official sources.

pub const InstallError = error{
    UnsupportedTool,
    UnsupportedPlatform,
    DownloadFailed,
    ExtractionFailed,
    PermissionDenied,
    OutOfMemory,
    NetworkError,
};

/// Install a tool
pub fn install(alloc: std.mem.Allocator, tool: []const u8, version: ?[]const u8) !void {
    const source = getSource(tool) orelse {
        std.debug.print("Unknown tool: {s}\n", .{tool});
        std.debug.print("Available: zig, rust, bun, node, go, python, deno\n", .{});
        return error.UnsupportedTool;
    };

    const target_version = version orelse try fetchLatestVersion(alloc, source);

    // Check if already installed
    if (try registry.isInstalled(alloc, tool, target_version)) {
        std.debug.print("{s}@{s} is already installed.\n", .{ tool, target_version });
        std.debug.print("Use 'zid use {s}@{s}' to activate it.\n", .{ tool, target_version });
        return;
    }

    const url = try buildDownloadUrl(alloc, source, target_version);
    defer alloc.free(url);

    std.debug.print("Downloading from {s}...\n", .{url});

    // Download
    const archive_path = try download(alloc, url);
    defer alloc.free(archive_path);

    // Extract
    const install_path = try registry.getInstallPath(alloc, tool, target_version);
    defer alloc.free(install_path);

    std.debug.print("Extracting to {s}...\n", .{install_path});
    try extract(archive_path, install_path);

    // Register
    try registry.register(alloc, tool, target_version, install_path);

    std.debug.print("Successfully installed {s}@{s}\n", .{ tool, target_version });

    // Set as active if first install of this tool
    if (!try registry.hasAnyVersion(alloc, tool)) {
        try registry.setActive(alloc, tool, target_version);
        std.debug.print("Set as active version.\n", .{});
    }
}

/// Uninstall a tool
pub fn uninstall(alloc: std.mem.Allocator, tool: []const u8, version: ?[]const u8) !void {
    if (version) |v| {
        try uninstallVersion(alloc, tool, v);
    } else {
        try uninstallAll(alloc, tool);
    }
}

fn uninstallVersion(alloc: std.mem.Allocator, tool: []const u8, version: []const u8) !void {
    if (!try registry.isInstalled(alloc, tool, version)) {
        std.debug.print("{s}@{s} is not installed.\n", .{ tool, version });
        return;
    }

    const path = try registry.getInstallPath(alloc, tool, version);
    defer alloc.free(path);

    // Remove directory
    std.fs.deleteTreeAbsolute(path) catch |err| {
        std.debug.print("Failed to remove {s}: {}\n", .{ path, err });
        return err;
    };

    // Unregister
    try registry.unregister(alloc, tool, version);
    std.debug.print("Uninstalled {s}@{s}\n", .{ tool, version });
}

fn uninstallAll(alloc: std.mem.Allocator, tool: []const u8) !void {
    const versions = try registry.listVersions(alloc, tool);
    for (versions) |v| {
        try uninstallVersion(alloc, tool, v);
    }
}

// ============ Sources ============

const Source = struct {
    name: []const u8,
    base_url: []const u8,
    version_url: []const u8,
    platform_format: PlatformFormat,

    const PlatformFormat = enum {
        zig,     // x86_64-linux, x86_64-macos, x86_64-windows
        rust,    // rustup
        node,    // linux-x64, darwin-x64, win-x64
        go,      // linux-amd64, darwin-amd64, windows-amd64
        generic, // download script
    };
};

const sources = [_]Source{
    .{
        .name = "zig",
        .base_url = "https://ziglang.org/download",
        .version_url = "https://ziglang.org/download/index.json",
        .platform_format = .zig,
    },
    .{
        .name = "rust",
        .base_url = "https://sh.rustup.rs",
        .version_url = "https://static.rust-lang.org/dist/channel-rust-stable.toml",
        .platform_format = .rust,
    },
    .{
        .name = "bun",
        .base_url = "https://github.com/oven-sh/bun/releases/download",
        .version_url = "https://api.github.com/repos/oven-sh/bun/releases/latest",
        .platform_format = .generic,
    },
    .{
        .name = "node",
        .base_url = "https://nodejs.org/dist",
        .version_url = "https://nodejs.org/dist/index.json",
        .platform_format = .node,
    },
    .{
        .name = "go",
        .base_url = "https://go.dev/dl",
        .version_url = "https://go.dev/dl/?mode=json",
        .platform_format = .go,
    },
    .{
        .name = "deno",
        .base_url = "https://github.com/denoland/deno/releases/download",
        .version_url = "https://api.github.com/repos/denoland/deno/releases/latest",
        .platform_format = .generic,
    },
};

fn getSource(tool: []const u8) ?Source {
    for (sources) |s| {
        if (std.mem.eql(u8, s.name, tool)) return s;
    }
    return null;
}

fn fetchLatestVersion(alloc: std.mem.Allocator, source: Source) ![]const u8 {
    _ = alloc;
    _ = source;
    // TODO: HTTP fetch and parse version
    return "latest";
}

fn buildDownloadUrl(alloc: std.mem.Allocator, source: Source, version: []const u8) ![]const u8 {
    const platform = getPlatformString(source.platform_format);
    return std.fmt.allocPrint(alloc, "{s}/{s}/{s}-{s}.tar.gz", .{
        source.base_url,
        version,
        source.name,
        platform,
    });
}

fn getPlatformString(format: Source.PlatformFormat) []const u8 {
    const os = @import("builtin").os.tag;
    const arch = @import("builtin").cpu.arch;

    return switch (format) {
        .zig => switch (os) {
            .linux => switch (arch) {
                .x86_64 => "x86_64-linux",
                .aarch64 => "aarch64-linux",
                else => "unknown",
            },
            .macos => switch (arch) {
                .x86_64 => "x86_64-macos",
                .aarch64 => "aarch64-macos",
                else => "unknown",
            },
            .windows => "x86_64-windows",
            else => "unknown",
        },
        .node => switch (os) {
            .linux => "linux-x64",
            .macos => "darwin-x64",
            .windows => "win-x64",
            else => "unknown",
        },
        .go => switch (os) {
            .linux => "linux-amd64",
            .macos => "darwin-amd64",
            .windows => "windows-amd64",
            else => "unknown",
        },
        else => "unknown",
    };
}

fn download(alloc: std.mem.Allocator, url: []const u8) ![]const u8 {
    _ = alloc;
    _ = url;
    // TODO: HTTP download
    return "/tmp/zid-download.tar.gz";
}

fn extract(archive_path: []const u8, dest_path: []const u8) !void {
    _ = archive_path;
    _ = dest_path;
    // TODO: Extract tar.gz/zip
}

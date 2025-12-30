//! Installer - Orchestrate tool installation
//!
//! Handles the full installation flow:
//! parse spec → resolve URL → download → extract → link
//!
//! Uses misc patterns: Maybe, Progress, ScopedLog, Cache.

const std = @import("std");
const zid = @import("../zid.zig");
const registry = @import("registry.zig");
const versions = @import("versions.zig");
const downloader = @import("downloader.zig");
const extractor = @import("extractor.zig");

const Maybe = zid.Maybe;
const Output = zid.Output;
const Progress = zid.misc.progress;
const Version = versions.Version;
const ToolSpec = registry.ToolSpec;
const ToolKind = registry.ToolKind;

const log = zid.ScopedLog("installer");

/// Installation result
pub const InstallResult = struct {
    tool: ToolKind,
    version: Version,
    path: []const u8,
    binary: []const u8,
};

/// Installer state
pub const Installer = struct {
    allocator: std.mem.Allocator,
    home_dir: []const u8,
    cache_dir: []const u8,
    bin_dir: []const u8,
    toolchains_dir: []const u8,

    const Self = @This();

    /// Initialize installer with default directories
    pub fn init(allocator: std.mem.Allocator) Self {
        const home = zid.getHome();

        var cache_buf: [256]u8 = undefined;
        var bin_buf: [256]u8 = undefined;
        var toolchains_buf: [256]u8 = undefined;

        const cache_dir = std.fmt.bufPrint(&cache_buf, "{s}/cache", .{home}) catch home;
        const bin_dir = std.fmt.bufPrint(&bin_buf, "{s}/bin", .{home}) catch home;
        const toolchains_dir = std.fmt.bufPrint(&toolchains_buf, "{s}/toolchains", .{home}) catch home;

        return .{
            .allocator = allocator,
            .home_dir = home,
            .cache_dir = cache_dir,
            .bin_dir = bin_dir,
            .toolchains_dir = toolchains_dir,
        };
    }

    /// Ensure all directories exist
    pub fn ensureDirs(self: *Self) void {
        const dirs = [_][]const u8{
            self.home_dir,
            self.cache_dir,
            self.bin_dir,
            self.toolchains_dir,
        };

        for (dirs) |dir| {
            std.fs.makeDirAbsolute(dir) catch |e| {
                if (e != error.PathAlreadyExists) {
                    log.err("failed to create {s}: {s}", .{ dir, @errorName(e) });
                }
            };
        }
    }

    /// Install a tool from spec string (e.g., "bun@1.1.0")
    pub fn install(self: *Self, spec_str: []const u8) Maybe(InstallResult) {
        // Parse spec
        const spec = switch (ToolSpec.parse(spec_str)) {
            .ok => |s| s,
            .err => |e| return zid.err(InstallResult, e),
        };

        return self.installSpec(spec);
    }

    /// Install from parsed spec
    pub fn installSpec(self: *Self, spec: ToolSpec) Maybe(InstallResult) {
        const tool_def = spec.getDef();

        Output.bold("Installing {s}", .{tool_def.name});
        if (!spec.version.isLatest()) {
            var ver_buf: [32]u8 = undefined;
            Output.print("@{s}", .{spec.version.format(&ver_buf)});
        }
        Output.print("...\n", .{});

        self.ensureDirs();

        // Build paths
        var ver_buf: [32]u8 = undefined;
        const ver_str = spec.version.format(&ver_buf);

        var tool_dir_buf: [256]u8 = undefined;
        const tool_dir = std.fmt.bufPrint(&tool_dir_buf, "{s}/{s}/{s}", .{
            self.toolchains_dir,
            tool_def.name,
            ver_str,
        }) catch {
            return zid.err(InstallResult, .{ .code = .internal_error, .message = "path too long" });
        };

        // Check if already installed
        if (self.isInstalled(spec.kind, spec.version)) {
            Output.warn("{s}@{s} is already installed\n", .{ tool_def.name, ver_str });
            return zid.ok(InstallResult, .{
                .tool = spec.kind,
                .version = spec.version,
                .path = tool_dir,
                .binary = tool_def.binary,
            });
        }

        // Get download URL
        var url_buf: [512]u8 = undefined;
        const url = switch (tool_def.getUrl(spec.version, &url_buf)) {
            .ok => |u| u,
            .err => |e| return zid.err(InstallResult, e),
        };

        log.debug("download URL: {s}", .{url});

        // Download
        Output.print("  Downloading...\n", .{});
        const archive_ext = switch (tool_def.archive) {
            .tar_gz => ".tar.gz",
            .tar_xz => ".tar.xz",
            .zip => ".zip",
            .none => "",
        };

        var archive_path_buf: [256]u8 = undefined;
        const archive_path = std.fmt.bufPrint(&archive_path_buf, "{s}/{s}-{s}{s}", .{
            self.cache_dir,
            tool_def.name,
            ver_str,
            archive_ext,
        }) catch {
            return zid.err(InstallResult, .{ .code = .internal_error, .message = "path too long" });
        };

        switch (downloader.download(self.allocator, url, archive_path)) {
            .ok => |result| {
                Output.print("  Downloaded {d} bytes\n", .{result.size});
            },
            .err => |e| {
                Output.err("  Download failed: {s}\n", .{e.message});
                return zid.err(InstallResult, e);
            },
        }

        // Extract
        if (tool_def.archive != .none) {
            Output.print("  Extracting...\n", .{});
            switch (extractor.extract(self.allocator, archive_path, tool_dir)) {
                .ok => |result| {
                    Output.print("  Extracted {d} files\n", .{result.files_count});
                },
                .err => |e| {
                    Output.err("  Extraction failed: {s}\n", .{e.message});
                    return zid.err(InstallResult, e);
                },
            }

            // Cleanup archive
            extractor.cleanup(archive_path);
        }

        // Create symlink in bin/
        self.linkBinary(tool_def, tool_dir);

        Output.success("Installed {s}@{s}\n", .{ tool_def.name, ver_str });

        return zid.ok(InstallResult, .{
            .tool = spec.kind,
            .version = spec.version,
            .path = tool_dir,
            .binary = tool_def.binary,
        });
    }

    /// Check if tool version is installed
    pub fn isInstalled(self: *Self, kind: ToolKind, version: Version) bool {
        const tool_def = registry.get(kind);
        var ver_buf: [32]u8 = undefined;
        const ver_str = version.format(&ver_buf);

        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}/{s}/{s}", .{
            self.toolchains_dir,
            tool_def.name,
            ver_str,
            tool_def.binary,
        }) catch return false;

        std.fs.accessAbsolute(path, .{}) catch return false;
        return true;
    }

    /// Create symlink in bin directory
    fn linkBinary(self: *Self, tool_def: *const registry.ToolDef, tool_dir: []const u8) void {
        var target_buf: [256]u8 = undefined;
        var link_buf: [256]u8 = undefined;

        // Build target path (binary inside extracted dir)
        const target = if (tool_def.binary_path) |bp|
            std.fmt.bufPrint(&target_buf, "{s}/{s}/{s}", .{ tool_dir, bp, tool_def.binary }) catch return
        else
            std.fmt.bufPrint(&target_buf, "{s}/{s}", .{ tool_dir, tool_def.binary }) catch return;

        // Build link path
        const link = std.fmt.bufPrint(&link_buf, "{s}/{s}", .{
            self.bin_dir,
            tool_def.binary,
        }) catch return;

        // Remove existing symlink
        std.fs.deleteFileAbsolute(link) catch {};

        // Create symlink
        std.posix.symlinkat(target, std.fs.cwd().fd, link) catch |e| {
            log.err("failed to create symlink: {s}", .{@errorName(e)});
        };

        // Make binary executable
        std.fs.cwd().chmod(target, 0o755) catch {};

        log.debug("linked {s} -> {s}", .{ link, target });
    }

    /// Uninstall a tool version
    pub fn uninstall(self: *Self, spec_str: []const u8) Maybe(void) {
        const spec = switch (ToolSpec.parse(spec_str)) {
            .ok => |s| s,
            .err => |e| return zid.err(void, e),
        };

        const tool_def = spec.getDef();
        var ver_buf: [32]u8 = undefined;
        const ver_str = spec.version.format(&ver_buf);

        var tool_dir_buf: [256]u8 = undefined;
        const tool_dir = std.fmt.bufPrint(&tool_dir_buf, "{s}/{s}/{s}", .{
            self.toolchains_dir,
            tool_def.name,
            ver_str,
        }) catch {
            return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
        };

        // Remove directory
        std.fs.deleteTreeAbsolute(tool_dir) catch |e| {
            return zid.fail(void, e, .write_file, tool_dir);
        };

        Output.success("Uninstalled {s}@{s}\n", .{ tool_def.name, ver_str });
        return zid.ok(void, {});
    }

    /// List installed tools
    pub fn listInstalled(self: *Self) void {
        Output.bold("Installed tools:\n\n", .{});

        var has_any = false;

        // Iterate toolchains directory
        var dir = std.fs.openDirAbsolute(self.toolchains_dir, .{ .iterate = true }) catch {
            Output.print("  (none)\n", .{});
            return;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .directory) continue;

            // Open tool directory
            var tool_dir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
            defer tool_dir.close();

            // List versions
            var ver_iter = tool_dir.iterate();
            while (ver_iter.next() catch null) |ver_entry| {
                if (ver_entry.kind != .directory) continue;

                Output.print("  {s}@{s}\n", .{ entry.name, ver_entry.name });
                has_any = true;
            }
        }

        if (!has_any) {
            Output.print("  (none)\n", .{});
        }

        Output.print("\nUse 'zid install <tool>' to install.\n", .{});
    }
};

// ============ PUBLIC API ============

/// Quick install function
pub fn install(allocator: std.mem.Allocator, spec: []const u8) Maybe(InstallResult) {
    var installer = Installer.init(allocator);
    return installer.install(spec);
}

/// Quick uninstall function
pub fn uninstall(allocator: std.mem.Allocator, spec: []const u8) Maybe(void) {
    var installer = Installer.init(allocator);
    return installer.uninstall(spec);
}

/// List installed tools
pub fn list(allocator: std.mem.Allocator) void {
    var installer = Installer.init(allocator);
    installer.listInstalled();
}

// ============ TESTS ============

test "Installer.init" {
    const installer = Installer.init(std.testing.allocator);
    try std.testing.expect(installer.home_dir.len > 0);
}

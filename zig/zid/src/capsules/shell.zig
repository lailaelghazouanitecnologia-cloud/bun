//! Shell Integration - Auto-configure environment
//!
//! Automatically updates shell environment when capsules change:
//! - ~/.zidrc: Environment variables for capsules
//! - Sources from ~/.bashrc, ~/.zshrc, etc.
//!
//! On capsule install/remove, regenerates ~/.zidrc

const std = @import("std");
const zid = @import("../zid.zig");
const capsules = @import("capsules.zig");
const paths = @import("paths.zig");
const Maybe = zid.Maybe;
const Output = zid.Output;

const log = zid.ScopedLog("shell");

/// Shell RC file path
fn getRcPath() []const u8 {
    const home = zid.getHome();
    var buf: [256]u8 = undefined;
    return std.fmt.bufPrint(&buf, "{s}/zidrc", .{home}) catch "~/.zid/zidrc";
}

/// Regenerate ~/.zid/zidrc with current capsule paths
pub fn updateRc(allocator: std.mem.Allocator) Maybe(void) {
    const home = zid.getHome();

    var rc_path_buf: [256]u8 = undefined;
    const rc_path = std.fmt.bufPrint(&rc_path_buf, "{s}/zidrc", .{home}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    const file = std.fs.createFileAbsolute(rc_path, .{}) catch |e| {
        return zid.fail(void, e, .write_file, rc_path);
    };
    defer file.close();

    var writer = file.writer();

    // Header
    writer.writeAll(
        \\# Zid Environment Configuration
        \\# Auto-generated - do not edit manually
        \\# Source this file in your shell: source ~/.zid/zidrc
        \\
        \\
    ) catch {};

    // ZID base paths
    writer.print("export ZID_HOME=\"{s}\"\n", .{home}) catch {};

    var bin_buf: [256]u8 = undefined;
    const bin_dir = std.fmt.bufPrint(&bin_buf, "{s}/bin", .{home}) catch home;
    writer.print("export PATH=\"{s}:$PATH\"\n\n", .{bin_dir}) catch {};

    // Capsule paths
    const capsule_paths = switch (paths.getAllPaths(allocator)) {
        .ok => |p| p,
        .err => return zid.ok(void, {}),
    };

    if (capsule_paths.len == 0) {
        writer.writeAll("# No capsules installed\n") catch {};
        return zid.ok(void, {});
    }

    // C/C++ paths
    writer.writeAll("# C/C++ Include Paths\n") catch {};
    var first = true;
    for (capsule_paths) |p| {
        if (first) {
            writer.print("export C_INCLUDE_PATH=\"{s}", .{p.include_dir}) catch {};
            first = false;
        } else {
            writer.print(":{s}", .{p.include_dir}) catch {};
        }
    }
    writer.writeAll(":$C_INCLUDE_PATH\"\n") catch {};
    writer.writeAll("export CPLUS_INCLUDE_PATH=\"$C_INCLUDE_PATH\"\n\n") catch {};

    // Library paths
    writer.writeAll("# Library Paths\n") catch {};
    first = true;
    for (capsule_paths) |p| {
        if (first) {
            writer.print("export LIBRARY_PATH=\"{s}", .{p.lib_dir}) catch {};
            first = false;
        } else {
            writer.print(":{s}", .{p.lib_dir}) catch {};
        }
    }
    writer.writeAll(":$LIBRARY_PATH\"\n") catch {};
    writer.writeAll("export LD_LIBRARY_PATH=\"$LIBRARY_PATH:$LD_LIBRARY_PATH\"\n\n") catch {};

    // PKG_CONFIG_PATH
    writer.writeAll("# pkg-config\n") catch {};
    first = true;
    for (capsule_paths) |p| {
        var pkgconfig_buf: [std.fs.max_path_bytes]u8 = undefined;
        const pkgconfig_path = std.fmt.bufPrint(&pkgconfig_buf, "{s}/lib/pkgconfig", .{
            std.fs.path.dirname(p.lib_dir) orelse p.lib_dir,
        }) catch continue;

        if (first) {
            writer.print("export PKG_CONFIG_PATH=\"{s}", .{pkgconfig_path}) catch {};
            first = false;
        } else {
            writer.print(":{s}", .{pkgconfig_path}) catch {};
        }
    }
    if (!first) {
        writer.writeAll(":$PKG_CONFIG_PATH\"\n") catch {};
    }

    log.debug("updated zidrc", .{});
    return zid.ok(void, {});
}

/// Setup shell integration (add source to .bashrc/.zshrc)
pub fn setup(allocator: std.mem.Allocator) Maybe(void) {
    _ = allocator;

    const user_home = std.posix.getenv("HOME") orelse return zid.err(void, .{
        .code = .not_found,
        .message = "HOME not set",
    });

    const zid_home = zid.getHome();
    var rc_path_buf: [256]u8 = undefined;
    const zidrc = std.fmt.bufPrint(&rc_path_buf, "{s}/zidrc", .{zid_home}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    const source_line = std.fmt.allocPrint(std.heap.page_allocator,
        \\
        \\# Zid - Universal Development Toolkit
        \\[ -f "{s}" ] && source "{s}"
        \\
    , .{ zidrc, zidrc }) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "alloc failed" });
    };

    // Try to add to shell rc files
    const rc_files = [_][]const u8{
        ".bashrc",
        ".zshrc",
        ".profile",
    };

    var added = false;
    for (rc_files) |rc| {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const rc_full = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ user_home, rc }) catch continue;

        // Check if file exists
        std.fs.accessAbsolute(rc_full, .{}) catch continue;

        // Check if already added
        const file = std.fs.openFileAbsolute(rc_full, .{}) catch continue;
        const content = file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024) catch {
            file.close();
            continue;
        };
        file.close();

        if (std.mem.indexOf(u8, content, "zidrc") != null) {
            // Already added
            added = true;
            continue;
        }

        // Append to file
        const append_file = std.fs.openFileAbsolute(rc_full, .{ .mode = .write_only }) catch continue;
        defer append_file.close();
        append_file.seekFromEnd(0) catch continue;
        append_file.writeAll(source_line) catch continue;

        Output.print("Added zid to {s}\n", .{rc});
        added = true;
    }

    if (!added) {
        Output.warn("Could not find shell rc file.\n", .{});
        Output.print("Add this to your shell config:\n", .{});
        Output.print("  source {s}\n", .{zidrc});
    }

    return zid.ok(void, {});
}

/// Check if shell is configured
pub fn isConfigured() bool {
    const user_home = std.posix.getenv("HOME") orelse return false;

    const rc_files = [_][]const u8{ ".bashrc", ".zshrc", ".profile" };

    for (rc_files) |rc| {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const rc_full = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ user_home, rc }) catch continue;

        const file = std.fs.openFileAbsolute(rc_full, .{}) catch continue;
        defer file.close();

        const content = file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024) catch continue;

        if (std.mem.indexOf(u8, content, "zidrc") != null) {
            return true;
        }
    }

    return false;
}

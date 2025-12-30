//! Extractor - Archive extraction
//!
//! Extract tar.gz, tar.xz, and zip archives.
//! Uses Maybe for error handling.

const std = @import("std");
const zid = @import("../zid.zig");
const Maybe = zid.Maybe;
const Output = zid.Output;

const log = zid.ScopedLog("extract");

/// Archive format
pub const Format = enum {
    tar_gz,
    tar_xz,
    zip,
    unknown,

    /// Detect format from file extension
    pub fn fromPath(path: []const u8) Format {
        if (std.mem.endsWith(u8, path, ".tar.gz") or std.mem.endsWith(u8, path, ".tgz")) {
            return .tar_gz;
        }
        if (std.mem.endsWith(u8, path, ".tar.xz") or std.mem.endsWith(u8, path, ".txz")) {
            return .tar_xz;
        }
        if (std.mem.endsWith(u8, path, ".zip")) {
            return .zip;
        }
        return .unknown;
    }

    pub fn string(self: Format) []const u8 {
        return switch (self) {
            .tar_gz => "tar.gz",
            .tar_xz => "tar.xz",
            .zip => "zip",
            .unknown => "unknown",
        };
    }
};

/// Extraction result
pub const Result = struct {
    dest_dir: []const u8,
    files_count: usize,
    root_dir: ?[]const u8, // Top-level directory in archive (if any)
};

/// Extract archive to destination directory
pub fn extract(
    allocator: std.mem.Allocator,
    archive_path: []const u8,
    dest_dir: []const u8,
) Maybe(Result) {
    const format = Format.fromPath(archive_path);

    log.debug("extracting {s} ({s}) to {s}", .{
        archive_path,
        format.string(),
        dest_dir,
    });

    // Create destination directory
    std.fs.makeDirAbsolute(dest_dir) catch |e| {
        if (e != error.PathAlreadyExists) {
            return zid.fail(Result, e, .write_file, dest_dir);
        }
    };

    return switch (format) {
        .tar_gz => extractTarGz(allocator, archive_path, dest_dir),
        .tar_xz => extractTarXz(allocator, archive_path, dest_dir),
        .zip => extractZip(allocator, archive_path, dest_dir),
        .unknown => zid.err(Result, .{
            .code = .invalid_input,
            .message = "unknown archive format",
            .path = archive_path,
        }),
    };
}

/// Extract tar.gz archive
fn extractTarGz(
    allocator: std.mem.Allocator,
    archive_path: []const u8,
    dest_dir: []const u8,
) Maybe(Result) {
    const file = std.fs.openFileAbsolute(archive_path, .{}) catch |e| {
        return zid.fail(Result, e, .read_file, archive_path);
    };
    defer file.close();

    // Decompress gzip
    var gzip = std.compress.gzip.decompressor(file.reader());

    // Extract tar
    return extractTar(allocator, &gzip, dest_dir);
}

/// Extract tar.xz archive
fn extractTarXz(
    allocator: std.mem.Allocator,
    archive_path: []const u8,
    dest_dir: []const u8,
) Maybe(Result) {
    const file = std.fs.openFileAbsolute(archive_path, .{}) catch |e| {
        return zid.fail(Result, e, .read_file, archive_path);
    };
    defer file.close();

    // Decompress xz
    var xz = std.compress.xz.decompress(allocator, file.reader()) catch |e| {
        return zid.fail(Result, e, .read_file, archive_path);
    };
    defer xz.deinit();

    // Extract tar
    return extractTar(allocator, xz.reader(), dest_dir);
}

/// Extract tar from reader
fn extractTar(
    allocator: std.mem.Allocator,
    reader: anytype,
    dest_dir: []const u8,
) Maybe(Result) {
    var tar = std.tar.reader(reader, .{});

    var files_count: usize = 0;
    var root_dir: ?[]const u8 = null;

    while (tar.next() catch |e| {
        return zid.fail(Result, e, .read_file, "");
    }) |entry| {
        // Get full path
        const name = entry.name();

        // Track root directory
        if (root_dir == null and std.mem.indexOf(u8, name, "/") != null) {
            const sep = std.mem.indexOf(u8, name, "/").?;
            root_dir = allocator.dupe(u8, name[0..sep]) catch null;
        }

        // Build destination path
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dest_dir, name }) catch continue;

        switch (entry.kind) {
            .directory => {
                std.fs.makeDirAbsolute(full_path) catch |e| {
                    if (e != error.PathAlreadyExists) continue;
                };
            },
            .file => {
                // Ensure parent directory exists
                if (std.fs.path.dirname(full_path)) |parent| {
                    std.fs.makeDirAbsolute(parent) catch {};
                }

                // Create file
                const out_file = std.fs.createFileAbsolute(full_path, .{}) catch continue;
                defer out_file.close();

                // Copy content
                var buf: [8192]u8 = undefined;
                var file_reader = entry.reader();
                while (true) {
                    const bytes = file_reader.read(&buf) catch break;
                    if (bytes == 0) break;
                    out_file.writeAll(buf[0..bytes]) catch break;
                }

                files_count += 1;
            },
            .sym_link => {
                const link_name = entry.linkName();
                std.posix.symlinkat(link_name, std.fs.cwd().fd, full_path) catch {};
            },
            else => {},
        }
    }

    log.debug("extracted {d} files", .{files_count});

    return zid.ok(Result, .{
        .dest_dir = dest_dir,
        .files_count = files_count,
        .root_dir = root_dir,
    });
}

/// Extract zip archive
fn extractZip(
    allocator: std.mem.Allocator,
    archive_path: []const u8,
    dest_dir: []const u8,
) Maybe(Result) {
    const file = std.fs.openFileAbsolute(archive_path, .{}) catch |e| {
        return zid.fail(Result, e, .read_file, archive_path);
    };
    defer file.close();

    var zip = std.zip.ZipArchive(std.fs.File).init(file) catch |e| {
        return zid.fail(Result, e, .read_file, archive_path);
    };

    var files_count: usize = 0;
    var root_dir: ?[]const u8 = null;

    var iter = zip.iterator();
    while (iter.next() catch null) |entry| {
        const name = entry.filename;

        // Track root directory
        if (root_dir == null and std.mem.indexOf(u8, name, "/") != null) {
            const sep = std.mem.indexOf(u8, name, "/").?;
            root_dir = allocator.dupe(u8, name[0..sep]) catch null;
        }

        // Build destination path
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dest_dir, name }) catch continue;

        // Handle directory
        if (std.mem.endsWith(u8, name, "/")) {
            std.fs.makeDirAbsolute(full_path) catch {};
            continue;
        }

        // Ensure parent directory exists
        if (std.fs.path.dirname(full_path)) |parent| {
            std.fs.makeDirAbsolute(parent) catch {};
        }

        // Extract file
        const out_file = std.fs.createFileAbsolute(full_path, .{}) catch continue;
        defer out_file.close();

        var reader = entry.reader(allocator) catch continue;
        defer reader.deinit();

        var buf: [8192]u8 = undefined;
        while (true) {
            const bytes = reader.read(&buf) catch break;
            if (bytes == 0) break;
            out_file.writeAll(buf[0..bytes]) catch break;
        }

        files_count += 1;
    }

    log.debug("extracted {d} files", .{files_count});

    return zid.ok(Result, .{
        .dest_dir = dest_dir,
        .files_count = files_count,
        .root_dir = root_dir,
    });
}

/// Delete archive file after extraction
pub fn cleanup(archive_path: []const u8) void {
    std.fs.deleteFileAbsolute(archive_path) catch {};
}

// ============ TESTS ============

test "Format.fromPath" {
    try std.testing.expectEqual(Format.tar_gz, Format.fromPath("file.tar.gz"));
    try std.testing.expectEqual(Format.tar_xz, Format.fromPath("file.tar.xz"));
    try std.testing.expectEqual(Format.zip, Format.fromPath("file.zip"));
    try std.testing.expectEqual(Format.unknown, Format.fromPath("file.txt"));
}

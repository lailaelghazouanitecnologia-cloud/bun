//! Example: File operations with sys module
//!
//! Demonstrates how to use sys.zig for cross-platform
//! file operations with proper error handling.
//!
//! Run with: zig build test -- --test-filter "example: file"

const std = @import("std");
const zid = @import("zid");

test "example: file exists check" {
    // Check if common system paths exist
    const root_exists = zid.sys.exists("/");
    const tmp_exists = zid.sys.exists("/tmp");

    try std.testing.expect(root_exists);
    if (zid.Environment.isPosix) {
        try std.testing.expect(tmp_exists);
    }

    // Non-existent path
    const fake_exists = zid.sys.exists("/this/path/does/not/exist/12345");
    try std.testing.expect(!fake_exists);
}

test "example: get file info with stat" {
    // Stat a known file
    switch (zid.sys.stat("/etc/passwd")) {
        .ok => |info| {
            std.debug.print("\n/etc/passwd info:\n", .{});
            std.debug.print("  Size: {} bytes\n", .{info.size});
            std.debug.print("  Type: {s}\n", .{@tagName(info.kind)});
            std.debug.print("  Is file: {}\n", .{info.isFile()});

            try std.testing.expect(info.isFile());
            try std.testing.expect(info.size > 0);
        },
        .err => {
            // May not exist on all systems (e.g., Windows)
            std.debug.print("\n/etc/passwd not found (expected on non-POSIX)\n", .{});
        },
    }
}

test "example: directory operations" {
    const test_dir = "/tmp/zid_example_test";

    // Clean up from previous runs
    _ = zid.sys.rmdir(test_dir);

    // Create directory
    switch (zid.sys.mkdir(test_dir, 0o755)) {
        .ok => {
            std.debug.print("\nCreated directory: {s}\n", .{test_dir});

            // Verify it exists
            try std.testing.expect(zid.sys.exists(test_dir));

            // Stat should show it's a directory
            switch (zid.sys.stat(test_dir)) {
                .ok => |info| {
                    try std.testing.expect(info.isDir());
                },
                .err => unreachable,
            }

            // Clean up
            switch (zid.sys.rmdir(test_dir)) {
                .ok => {
                    std.debug.print("Removed directory: {s}\n", .{test_dir});
                },
                .err => |e| {
                    std.debug.print("Failed to remove: {s}\n", .{e.message});
                },
            }
        },
        .err => |e| {
            std.debug.print("\nFailed to create dir: {s}\n", .{e.message});
        },
    }
}

test "example: write and read file" {
    const test_file = "/tmp/zid_example_test.txt";
    const content = "Hello from Zid!";

    // Write file
    switch (zid.sys.writeFile(test_file, content)) {
        .ok => {
            std.debug.print("\nWrote to: {s}\n", .{test_file});

            // Read it back
            switch (zid.sys.readFile(std.testing.allocator, test_file)) {
                .ok => |data| {
                    defer std.testing.allocator.free(data);
                    try std.testing.expectEqualStrings(content, data);
                    std.debug.print("Read back: {s}\n", .{data});
                },
                .err => |e| {
                    std.debug.print("Read failed: {s}\n", .{e.message});
                    return error.ReadFailed;
                },
            }

            // Clean up
            _ = zid.sys.unlink(test_file);
        },
        .err => |e| {
            std.debug.print("\nWrite failed: {s}\n", .{e.message});
        },
    }
}

test "example: error handling with Maybe" {
    // Try to stat a non-existent file
    const result = zid.sys.stat("/nonexistent/file/path");

    switch (result) {
        .ok => {
            // Should not happen
            try std.testing.expect(false);
        },
        .err => |e| {
            // Expected error
            std.debug.print("\nExpected error: {s} (code: {s})\n", .{
                e.message,
                @tagName(e.code),
            });

            try std.testing.expectEqual(zid.Error.Code.not_found, e.code);
        },
    }
}

test "example: copy file efficiently" {
    const src = "/tmp/zid_copy_src.txt";
    const dst = "/tmp/zid_copy_dst.txt";
    const content = "Data to copy\n" ** 100; // ~1.3KB

    // Create source file
    switch (zid.sys.writeFile(src, content)) {
        .ok => {},
        .err => return, // Skip if we can't write
    }
    defer _ = zid.sys.unlink(src);

    // Copy file (uses sendfile on Linux for efficiency)
    switch (zid.sys.copyFile(src, dst)) {
        .ok => {
            defer _ = zid.sys.unlink(dst);

            // Verify copy
            switch (zid.sys.readFile(std.testing.allocator, dst)) {
                .ok => |data| {
                    defer std.testing.allocator.free(data);
                    try std.testing.expectEqualStrings(content, data);
                    std.debug.print("\nFile copied successfully ({} bytes)\n", .{data.len});
                },
                .err => return error.VerifyFailed,
            }
        },
        .err => |e| {
            std.debug.print("\nCopy failed: {s}\n", .{e.message});
        },
    }
}

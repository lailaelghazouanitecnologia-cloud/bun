//! Capsule Paths - Library path configuration for compilers
//!
//! Generates include/library paths for different compilers:
//! - C/C++: -I, -L, -l flags
//! - Zig: --mod, -L flags
//! - Rust: -L flags, extern crate
//! - Go: -I flags
//!
//! Usage:
//!   zid capsule paths         # Show all paths
//!   zid capsule paths --c     # C/C++ flags
//!   zid capsule paths --zig   # Zig flags
//!   eval $(zid capsule paths --env)  # Export as env vars

const std = @import("std");
const zid = @import("../zid.zig");
const capsules = @import("capsules.zig");
const Maybe = zid.Maybe;
const Output = zid.Output;

const log = zid.ScopedLog("paths");

/// Compiler type
pub const Compiler = enum {
    c, // C/C++ (gcc, clang)
    zig, // Zig
    rust, // Rust (rustc, cargo)
    go, // Go
};

/// Path configuration for a capsule
pub const CapsulePaths = struct {
    name: []const u8,
    include_dir: []const u8, // Headers (-I)
    lib_dir: []const u8, // Libraries (-L)
    src_dir: []const u8, // Source files
    lib_name: ?[]const u8, // Library name (-l)
};

/// Get paths for all installed capsules
pub fn getAllPaths(allocator: std.mem.Allocator) Maybe([]const CapsulePaths) {
    const mgr = capsules.Manager.init(allocator);
    var paths_list = std.ArrayList(CapsulePaths).init(allocator);

    // Scan intern capsules
    scanCapsules(allocator, mgr.intern_dir, &paths_list);

    // Scan extern capsules
    scanCapsules(allocator, mgr.extern_dir, &paths_list);

    return zid.ok([]const CapsulePaths, paths_list.items);
}

fn scanCapsules(allocator: std.mem.Allocator, dir_path: []const u8, paths_list: *std.ArrayList(CapsulePaths)) void {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .directory) continue;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const capsule_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
            dir_path,
            entry.name,
        }) catch continue;

        var include_buf: [std.fs.max_path_bytes]u8 = undefined;
        var lib_buf: [std.fs.max_path_bytes]u8 = undefined;
        var src_buf: [std.fs.max_path_bytes]u8 = undefined;

        paths_list.append(.{
            .name = allocator.dupe(u8, entry.name) catch continue,
            .include_dir = std.fmt.bufPrint(&include_buf, "{s}/include", .{capsule_path}) catch capsule_path,
            .lib_dir = std.fmt.bufPrint(&lib_buf, "{s}/lib", .{capsule_path}) catch capsule_path,
            .src_dir = std.fmt.bufPrint(&src_buf, "{s}/src", .{capsule_path}) catch capsule_path,
            .lib_name = entry.name,
        }) catch {};
    }
}

/// Generate compiler flags for C/C++
pub fn generateCFlags(allocator: std.mem.Allocator, writer: anytype) !void {
    const paths = switch (getAllPaths(allocator)) {
        .ok => |p| p,
        .err => return,
    };

    for (paths) |p| {
        // Include path
        try writer.print("-I{s} ", .{p.include_dir});
        // Library path
        try writer.print("-L{s} ", .{p.lib_dir});
        // Link library
        if (p.lib_name) |name| {
            try writer.print("-l{s} ", .{name});
        }
    }
}

/// Generate compiler flags for Zig
pub fn generateZigFlags(allocator: std.mem.Allocator, writer: anytype) !void {
    const paths = switch (getAllPaths(allocator)) {
        .ok => |p| p,
        .err => return,
    };

    for (paths) |p| {
        // Library path for linking
        try writer.print("-L{s} ", .{p.lib_dir});
        // Can also add module paths
        try writer.print("--mod {s}:{s}/{s}.zig ", .{ p.name, p.src_dir, p.name });
    }
}

/// Generate environment variables
pub fn generateEnvVars(allocator: std.mem.Allocator, writer: anytype) !void {
    const home = zid.getHome();

    // ZID paths
    try writer.print("export ZID_HOME=\"{s}\"\n", .{home});

    var capsules_buf: [256]u8 = undefined;
    const capsules_dir = std.fmt.bufPrint(&capsules_buf, "{s}/capsules", .{home}) catch return;
    try writer.print("export ZID_CAPSULES=\"{s}\"\n", .{capsules_dir});

    // C paths
    var c_include = std.ArrayList(u8).init(allocator);
    var c_lib = std.ArrayList(u8).init(allocator);

    const paths = switch (getAllPaths(allocator)) {
        .ok => |p| p,
        .err => return,
    };

    for (paths) |p| {
        if (c_include.items.len > 0) try c_include.append(':');
        try c_include.appendSlice(p.include_dir);

        if (c_lib.items.len > 0) try c_lib.append(':');
        try c_lib.appendSlice(p.lib_dir);
    }

    if (c_include.items.len > 0) {
        try writer.print("export C_INCLUDE_PATH=\"{s}:$C_INCLUDE_PATH\"\n", .{c_include.items});
        try writer.print("export CPLUS_INCLUDE_PATH=\"{s}:$CPLUS_INCLUDE_PATH\"\n", .{c_include.items});
    }

    if (c_lib.items.len > 0) {
        try writer.print("export LIBRARY_PATH=\"{s}:$LIBRARY_PATH\"\n", .{c_lib.items});
        try writer.print("export LD_LIBRARY_PATH=\"{s}:$LD_LIBRARY_PATH\"\n", .{c_lib.items});
    }
}

/// Print paths summary
pub fn printSummary(allocator: std.mem.Allocator) void {
    const paths = switch (getAllPaths(allocator)) {
        .ok => |p| p,
        .err => {
            Output.print("No capsules installed.\n", .{});
            return;
        },
    };

    if (paths.len == 0) {
        Output.print("No capsules installed.\n", .{});
        return;
    }

    Output.bold("Capsule Paths:\n\n", .{});

    for (paths) |p| {
        Output.print("  {s}:\n", .{p.name});
        Output.print("    include: {s}\n", .{p.include_dir});
        Output.print("    lib:     {s}\n", .{p.lib_dir});
        Output.print("    src:     {s}\n", .{p.src_dir});
        Output.print("\n", .{});
    }

    Output.print("Usage:\n", .{});
    Output.print("  C/C++:  eval $(zid capsule paths --env)\n", .{});
    Output.print("  Zig:    zig build $(zid capsule paths --zig)\n", .{});
}

// ============ TESTS ============

test "Compiler enum" {
    const c: Compiler = .c;
    const zig_comp: Compiler = .zig;
    try std.testing.expect(c != zig_comp);
}

test "CapsulePaths struct" {
    const paths = CapsulePaths{
        .name = "test",
        .include_dir = "/path/include",
        .lib_dir = "/path/lib",
        .src_dir = "/path/src",
        .lib_name = "test",
    };
    try std.testing.expectEqualStrings("test", paths.name);
}

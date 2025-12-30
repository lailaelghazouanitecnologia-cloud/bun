//! Capsule Integration - Make capsules importable in Zig projects
//!
//! Generates build.zig configuration to use installed capsules.
//! Creates module paths for @import("capsule-name").

const std = @import("std");
const zid = @import("../zid.zig");
const capsules = @import("capsules.zig");
const Maybe = zid.Maybe;
const Output = zid.Output;

const log = zid.ScopedLog("capsule-int");

/// Module info for build.zig integration
pub const ModuleInfo = struct {
    name: []const u8,
    path: []const u8,
    dependencies: []const []const u8,
};

/// Generate zig build module paths for installed capsules
pub fn getModulePaths(allocator: std.mem.Allocator) Maybe([]const ModuleInfo) {
    var mgr = capsules.Manager.init(allocator);
    var modules = std.ArrayList(ModuleInfo).init(allocator);

    // Scan intern capsules
    scanDir(allocator, mgr.intern_dir, &modules);

    // Scan extern capsules
    scanDir(allocator, mgr.extern_dir, &modules);

    return zid.ok([]const ModuleInfo, modules.items);
}

fn scanDir(allocator: std.mem.Allocator, dir_path: []const u8, modules: *std.ArrayList(ModuleInfo)) void {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .directory) continue;

        // Look for main module file
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        // Try src/<name>.zig
        var src_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/src/{s}.zig", .{
            dir_path,
            entry.name,
            entry.name,
        }) catch continue;

        if (std.fs.accessAbsolute(src_path, .{})) |_| {
            modules.append(.{
                .name = allocator.dupe(u8, entry.name) catch continue,
                .path = allocator.dupe(u8, src_path) catch continue,
                .dependencies = &.{},
            }) catch {};
            continue;
        } else |_| {}

        // Try src/lib.zig
        src_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/src/lib.zig", .{
            dir_path,
            entry.name,
        }) catch continue;

        if (std.fs.accessAbsolute(src_path, .{})) |_| {
            modules.append(.{
                .name = allocator.dupe(u8, entry.name) catch continue,
                .path = allocator.dupe(u8, src_path) catch continue,
                .dependencies = &.{},
            }) catch {};
            continue;
        } else |_| {}

        // Try <name>.zig at root
        src_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/{s}.zig", .{
            dir_path,
            entry.name,
            entry.name,
        }) catch continue;

        if (std.fs.accessAbsolute(src_path, .{})) |_| {
            modules.append(.{
                .name = allocator.dupe(u8, entry.name) catch continue,
                .path = allocator.dupe(u8, src_path) catch continue,
                .dependencies = &.{},
            }) catch {};
        } else |_| {}
    }
}

/// Generate build.zig.zon snippet for capsule dependencies
pub fn generateZon(allocator: std.mem.Allocator, writer: anytype) !void {
    const modules = switch (getModulePaths(allocator)) {
        .ok => |m| m,
        .err => return,
    };

    try writer.writeAll(".{\n");
    try writer.writeAll("    .name = \"my-project\",\n");
    try writer.writeAll("    .version = \"0.0.0\",\n");
    try writer.writeAll("    .dependencies = .{\n");

    for (modules) |mod| {
        try writer.print("        .{s} = .{{\n", .{mod.name});
        try writer.print("            .path = \"{s}\",\n", .{mod.path});
        try writer.writeAll("        },\n");
    }

    try writer.writeAll("    },\n");
    try writer.writeAll("}\n");
}

/// Generate build.zig snippet for adding capsule modules
pub fn generateBuildZig(allocator: std.mem.Allocator, writer: anytype) !void {
    const modules = switch (getModulePaths(allocator)) {
        .ok => |m| m,
        .err => return,
    };

    try writer.writeAll("// Auto-generated capsule imports\n");
    try writer.writeAll("pub fn addCapsuleModules(b: *std.Build, exe: *std.Build.Step.Compile) void {\n");

    for (modules) |mod| {
        try writer.print("    exe.addModule(\"{s}\", b.createModule(.{{\n", .{mod.name});
        try writer.print("        .source_file = .{{ .path = \"{s}\" }},\n", .{mod.path});
        try writer.writeAll("    }));\n");
    }

    try writer.writeAll("}\n");
}

/// Create a stub capsule for testing
pub fn createStubCapsule(allocator: std.mem.Allocator, name: []const u8) Maybe(void) {
    var mgr = capsules.Manager.init(allocator);
    mgr.ensureDirs();

    // Create capsule directory
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const capsule_dir = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
        mgr.intern_dir,
        name,
    }) catch return zid.err(void, .{ .code = .internal_error, .message = "path too long" });

    std.fs.makeDirAbsolute(capsule_dir) catch |e| {
        if (e != error.PathAlreadyExists) {
            return zid.fail(void, e, .write_file, capsule_dir);
        }
    };

    // Create src directory
    var src_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const src_dir = std.fmt.bufPrint(&src_dir_buf, "{s}/src", .{capsule_dir}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    std.fs.makeDirAbsolute(src_dir) catch |e| {
        if (e != error.PathAlreadyExists) {
            return zid.fail(void, e, .write_file, src_dir);
        }
    };

    // Create main module file
    var mod_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const mod_path = std.fmt.bufPrint(&mod_path_buf, "{s}/{s}.zig", .{ src_dir, name }) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    const file = std.fs.createFileAbsolute(mod_path, .{}) catch |e| {
        return zid.fail(void, e, .write_file, mod_path);
    };
    defer file.close();

    // Write stub content
    file.writer().print(
        \\//! {s} capsule - Auto-generated stub
        \\
        \\const std = @import("std");
        \\
        \\pub const version = "0.1.0";
        \\
        \\pub fn init() void {{
        \\    // Initialize {s}
        \\}}
        \\
        \\pub fn deinit() void {{
        \\    // Cleanup {s}
        \\}}
        \\
    , .{ name, name, name }) catch |e| {
        return zid.fail(void, e, .write_file, mod_path);
    };

    // Create capsule.json
    var manifest_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const manifest_path = std.fmt.bufPrint(&manifest_path_buf, "{s}/capsule.json", .{capsule_dir}) catch {
        return zid.err(void, .{ .code = .internal_error, .message = "path too long" });
    };

    const manifest_file = std.fs.createFileAbsolute(manifest_path, .{}) catch |e| {
        return zid.fail(void, e, .write_file, manifest_path);
    };
    defer manifest_file.close();

    manifest_file.writer().print(
        \\{{
        \\  "name": "{s}",
        \\  "version": "0.1.0",
        \\  "description": "{s} capsule"
        \\}}
        \\
    , .{ name, name }) catch |e| {
        return zid.fail(void, e, .write_file, manifest_path);
    };

    log.debug("created stub capsule: {s}", .{name});
    return zid.ok(void, {});
}

// ============ TESTS ============

test "ModuleInfo" {
    const info = ModuleInfo{
        .name = "test",
        .path = "/path/to/test.zig",
        .dependencies = &.{},
    };
    try std.testing.expectEqualStrings("test", info.name);
}

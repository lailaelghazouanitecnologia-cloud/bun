const std = @import("std");
const registry = @import("registry.zig");
const runner = @import("runner.zig");

/// Apps Registry
/// Register user programs as direct commands.
/// No need for `zid run myapp` - just type `myapp`!
///
/// How it works:
///   1. User adds an app: `zid add ./my-tool`
///   2. Zid compiles it (if needed) and registers it
///   3. App becomes available as a command in ~/.zid/bin/
///   4. User can run it directly: `my-tool arg1 arg2`

pub const App = struct {
    name: []const u8,
    path: []const u8,
    source: Source,
    version: ?[]const u8 = null,

    pub const Source = enum {
        local,  // Local path
        git,    // Git repository
        url,    // Download URL
    };
};

/// Check if an app is registered
pub fn isRegistered(name: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    return registry.exists(arena.allocator(), name) catch false;
}

/// Execute a registered app
pub fn execute(alloc: std.mem.Allocator, name: []const u8, args: []const []const u8) !void {
    return runner.run(alloc, name, args);
}

/// Add an app to the registry
/// Accepts: local path, git URL, or download URL
pub fn add(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        printAddHelp();
        return;
    }

    const source = args[0];
    const name = if (args.len > 1) args[1] else inferName(source);

    std.debug.print("Adding app: {s}\n", .{name});

    // Determine source type
    if (std.mem.startsWith(u8, source, "https://github.com") or
        std.mem.startsWith(u8, source, "git@"))
    {
        try addFromGit(alloc, source, name);
    } else if (std.mem.startsWith(u8, source, "http://") or
        std.mem.startsWith(u8, source, "https://"))
    {
        try addFromUrl(alloc, source, name);
    } else {
        try addFromLocal(alloc, source, name);
    }
}

/// Remove an app from the registry
pub fn remove(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zid remove <app-name>\n", .{});
        return;
    }

    const name = args[0];

    if (!try registry.exists(alloc, name)) {
        std.debug.print("App '{s}' is not registered.\n", .{name});
        return;
    }

    try registry.remove(alloc, name);
    std.debug.print("Removed app: {s}\n", .{name});
}

/// Run an app explicitly (useful for apps not in PATH)
pub fn run(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zid run <app-name> [args...]\n", .{});
        return;
    }

    const name = args[0];
    const app_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    try runner.run(alloc, name, app_args);
}

/// List all registered apps
pub fn list(alloc: std.mem.Allocator) !void {
    const apps = try registry.list(alloc);

    if (apps.len == 0) {
        std.debug.print("No apps registered.\n", .{});
        std.debug.print("Use 'zid add <path>' to add an app.\n", .{});
        return;
    }

    std.debug.print("Registered apps:\n\n", .{});
    for (apps) |app| {
        std.debug.print("  {s}", .{app.name});
        if (app.version) |v| {
            std.debug.print(" ({s})", .{v});
        }
        std.debug.print("\n", .{});
    }
}

// ============ Internal ============

fn addFromLocal(alloc: std.mem.Allocator, path: []const u8, name: []const u8) !void {
    // Resolve to absolute path
    const abs_path = try std.fs.cwd().realpathAlloc(alloc, path);
    defer alloc.free(abs_path);

    // Check if it's a directory or file
    const stat = try std.fs.cwd().statFile(path);

    if (stat.kind == .directory) {
        // It's a project - try to build it
        try buildAndRegister(alloc, abs_path, name);
    } else {
        // It's a binary - register directly
        try registry.register(alloc, .{
            .name = name,
            .path = abs_path,
            .source = .local,
        });
    }

    std.debug.print("Added app: {s}\n", .{name});
    std.debug.print("Run with: {s}\n", .{name});
}

fn addFromGit(alloc: std.mem.Allocator, url: []const u8, name: []const u8) !void {
    const apps_dir = try registry.getAppsDir(alloc);
    defer alloc.free(apps_dir);

    const clone_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ apps_dir, name });
    defer alloc.free(clone_path);

    std.debug.print("Cloning {s}...\n", .{url});

    // Clone repository
    var child = std.process.Child.init(&.{ "git", "clone", "--depth=1", url, clone_path }, alloc);
    _ = try child.spawnAndWait();

    // Build and register
    try buildAndRegister(alloc, clone_path, name);

    std.debug.print("Added app from git: {s}\n", .{name});
}

fn addFromUrl(alloc: std.mem.Allocator, url: []const u8, name: []const u8) !void {
    _ = alloc;
    _ = url;
    _ = name;
    // TODO: Download and install
    std.debug.print("URL install not yet implemented\n", .{});
}

fn buildAndRegister(alloc: std.mem.Allocator, project_path: []const u8, name: []const u8) !void {
    // Detect project type and build
    const build_file = try detectBuildSystem(alloc, project_path);

    if (build_file) |bf| {
        std.debug.print("Building with {s}...\n", .{bf});
        try buildProject(alloc, project_path, bf);
    }

    // Find the binary
    const binary_path = try findBinary(alloc, project_path, name);

    // Register it
    try registry.register(alloc, .{
        .name = name,
        .path = binary_path,
        .source = .local,
    });
}

fn detectBuildSystem(alloc: std.mem.Allocator, path: []const u8) !?[]const u8 {
    const build_files = [_][]const u8{
        "build.zig",      // Zig
        "Cargo.toml",     // Rust
        "package.json",   // Node/Bun
        "go.mod",         // Go
        "Makefile",       // Make
        "CMakeLists.txt", // CMake
    };

    for (build_files) |bf| {
        const full_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ path, bf });
        defer alloc.free(full_path);

        std.fs.accessAbsolute(full_path, .{}) catch continue;
        return bf;
    }

    return null;
}

fn buildProject(alloc: std.mem.Allocator, path: []const u8, build_file: []const u8) !void {
    const cmd: []const []const u8 = if (std.mem.eql(u8, build_file, "build.zig"))
        &.{ "zig", "build", "-Doptimize=ReleaseFast" }
    else if (std.mem.eql(u8, build_file, "Cargo.toml"))
        &.{ "cargo", "build", "--release" }
    else if (std.mem.eql(u8, build_file, "package.json"))
        &.{ "bun", "build" }
    else if (std.mem.eql(u8, build_file, "go.mod"))
        &.{ "go", "build", "-o", "." }
    else if (std.mem.eql(u8, build_file, "Makefile"))
        &.{"make"}
    else
        return;

    var child = std.process.Child.init(cmd, alloc);
    child.cwd = path;
    _ = try child.spawnAndWait();
}

fn findBinary(alloc: std.mem.Allocator, project_path: []const u8, name: []const u8) ![]const u8 {
    // Common binary locations
    const locations = [_][]const u8{
        "zig-out/bin/{s}",
        "target/release/{s}",
        "dist/{s}",
        "build/{s}",
        "{s}",
    };

    for (locations) |loc| {
        const path = try std.fmt.allocPrint(alloc, "{s}/" ++ loc, .{ project_path, name });
        std.fs.accessAbsolute(path, .{}) catch {
            alloc.free(path);
            continue;
        };
        return path;
    }

    return error.BinaryNotFound;
}

fn inferName(source: []const u8) []const u8 {
    // Get basename
    if (std.mem.lastIndexOf(u8, source, "/")) |idx| {
        const name = source[idx + 1 ..];
        // Remove .git suffix if present
        if (std.mem.endsWith(u8, name, ".git")) {
            return name[0 .. name.len - 4];
        }
        return name;
    }
    return source;
}

fn printAddHelp() void {
    const help =
        \\Usage: zid add <source> [name]
        \\
        \\Add an app to the registry. The app becomes a direct command.
        \\
        \\Sources:
        \\  ./path/to/project       Local project (will build if needed)
        \\  ./path/to/binary        Local binary (registers directly)
        \\  https://github.com/...  Git repository (clones and builds)
        \\  https://example.com/app Download URL (downloads binary)
        \\
        \\Examples:
        \\  zid add ./my-tool                    Add local project
        \\  zid add ./bin/my-app my-app          Add binary with custom name
        \\  zid add https://github.com/user/repo Clone and add from GitHub
        \\
    ;
    std.debug.print("{s}", .{help});
}

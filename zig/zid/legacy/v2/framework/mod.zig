const std = @import("std");
const pipeline = @import("pipeline.zig");
const metadata = @import("metadata.zig");

/// Zid Framework
/// API for building transpilers and code transformation tools.
///
/// Core concepts:
///   - Pipeline: Chain of transformation steps
///   - Metadata: Language capabilities and features
///   - .az: Universal intermediate representation

pub const Pipeline = pipeline.Pipeline;
pub const Step = pipeline.Step;
pub const Metadata = metadata.Metadata;

/// Initialize a new transpiler project
pub fn init(alloc: std.mem.Allocator, args: []const []const u8) !void {
    const template = if (args.len > 0) args[0] else "basic";
    const name = if (args.len > 1) args[1] else "my-transpiler";

    std.debug.print("Creating new transpiler project: {s}\n", .{name});
    std.debug.print("Template: {s}\n", .{template});

    // Create project directory
    std.fs.cwd().makeDir(name) catch |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("Directory '{s}' already exists.\n", .{name});
            return;
        }
        return err;
    };

    // Generate project files based on template
    try generateProject(alloc, name, template);

    std.debug.print("\nProject created!\n", .{});
    std.debug.print("  cd {s}\n", .{name});
    std.debug.print("  zid build\n", .{});
}

/// Build the current project
pub fn build(alloc: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    // Find project config
    const config = try findProjectConfig(alloc) orelse {
        std.debug.print("No zid.zig found. Run 'zid init' first.\n", .{});
        return error.NoProject;
    };
    defer alloc.free(config);

    std.debug.print("Building...\n", .{});

    // Load and run pipeline
    // TODO: Load from zid.zig
    var pipe = Pipeline.init(alloc);
    defer pipe.deinit();

    try pipe.run();

    std.debug.print("Build complete.\n", .{});
}

/// Watch for changes and rebuild
pub fn watch(alloc: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;
    _ = alloc;
    std.debug.print("Watching for changes... (Ctrl+C to stop)\n", .{});
    // TODO: Implement file watcher
}

// ============ Templates ============

fn generateProject(alloc: std.mem.Allocator, name: []const u8, template: []const u8) !void {
    if (std.mem.eql(u8, template, "basic")) {
        try generateBasicTemplate(alloc, name);
    } else if (std.mem.eql(u8, template, "lua-to-wasm")) {
        try generateLuaToWasmTemplate(alloc, name);
    } else if (std.mem.eql(u8, template, "markdown")) {
        try generateMarkdownTemplate(alloc, name);
    } else {
        std.debug.print("Unknown template: {s}\n", .{template});
        std.debug.print("Available: basic, lua-to-wasm, markdown\n", .{});
    }
}

fn generateBasicTemplate(alloc: std.mem.Allocator, name: []const u8) !void {
    // zid.zig - Project configuration
    const zid_zig =
        \\const std = @import("std");
        \\const zid = @import("zid");
        \\
        \\/// Pipeline definition
        \\pub const pipeline = zid.Pipeline{
        \\    .input = "src/*.lua",
        \\    .output = "dist/",
        \\    .steps = &.{ lex, parse, emit },
        \\};
        \\
        \\/// Source language metadata
        \\pub const source_lang = zid.Metadata{
        \\    .name = "lua",
        \\    .extensions = &.{".lua"},
        \\    .features = .{
        \\        .first_class_functions = true,
        \\        .dynamic_typing = true,
        \\        .tables = true,
        \\    },
        \\};
        \\
        \\/// Target language metadata
        \\pub const target_lang = zid.Metadata{
        \\    .name = "wat",
        \\    .extensions = &.{".wat", ".wasm"},
        \\    .features = .{
        \\        .static_typing = true,
        \\        .linear_memory = true,
        \\    },
        \\};
        \\
        \\// ============ STEPS ============
        \\
        \\fn lex(source: []const u8) ![]Token {
        \\    _ = source;
        \\    // TODO: Implement lexer
        \\    return &.{};
        \\}
        \\
        \\fn parse(tokens: []Token) !AST {
        \\    _ = tokens;
        \\    // TODO: Implement parser
        \\    return .{};
        \\}
        \\
        \\fn emit(ast: AST) ![]const u8 {
        \\    _ = ast;
        \\    // TODO: Implement emitter
        \\    return "";
        \\}
        \\
        \\// ============ TYPES ============
        \\
        \\pub const Token = struct {
        \\    kind: Kind,
        \\    text: []const u8,
        \\
        \\    pub const Kind = enum { ident, number, string, keyword, symbol, eof };
        \\};
        \\
        \\pub const AST = struct {
        \\    nodes: []Node = &.{},
        \\
        \\    pub const Node = struct {
        \\        kind: Kind,
        \\        children: []Node = &.{},
        \\
        \\        pub const Kind = enum { program, function, call, literal, ident };
        \\    };
        \\};
        \\
    ;

    try writeFile(alloc, name, "zid.zig", zid_zig);

    // build.zig
    const build_zig =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "transpiler",
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    b.installArtifact(exe);
        \\}
        \\
    ;

    try writeFile(alloc, name, "build.zig", build_zig);

    // src/main.zig
    const main_zig =
        \\const std = @import("std");
        \\const zid_config = @import("../zid.zig");
        \\
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    defer _ = gpa.deinit();
        \\    const alloc = gpa.allocator();
        \\
        \\    const args = try std.process.argsAlloc(alloc);
        \\    defer std.process.argsFree(alloc, args);
        \\
        \\    if (args.len < 2) {
        \\        std.debug.print("Usage: transpiler <file.lua>\n", .{});
        \\        return;
        \\    }
        \\
        \\    // Run pipeline
        \\    const output = try zid_config.pipeline.run(args[1]);
        \\    std.debug.print("{s}\n", .{output});
        \\}
        \\
    ;

    try writeFile(alloc, name, "src/main.zig", main_zig);

    // Example source file
    const example_lua =
        \\-- Example Lua file
        \\function hello(name)
        \\    print("Hello, " .. name)
        \\end
        \\
        \\hello("World")
        \\
    ;

    try writeFile(alloc, name, "src/example.lua", example_lua);
}

fn generateLuaToWasmTemplate(alloc: std.mem.Allocator, name: []const u8) !void {
    // Similar to basic but with Lua->WASM specific code
    try generateBasicTemplate(alloc, name);
}

fn generateMarkdownTemplate(alloc: std.mem.Allocator, name: []const u8) !void {
    // Markdown processor template
    try generateBasicTemplate(alloc, name);
}

fn writeFile(alloc: std.mem.Allocator, project: []const u8, path: []const u8, content: []const u8) !void {
    const full_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ project, path });
    defer alloc.free(full_path);

    // Create parent directories
    if (std.mem.lastIndexOf(u8, path, "/")) |idx| {
        const dir = path[0..idx];
        const dir_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ project, dir });
        defer alloc.free(dir_path);

        std.fs.cwd().makePath(dir_path) catch {};
    }

    const file = try std.fs.cwd().createFile(full_path, .{});
    defer file.close();
    try file.writeAll(content);
}

fn findProjectConfig(alloc: std.mem.Allocator) !?[]const u8 {
    const config_files = [_][]const u8{ "zid.zig", "zid.yaml", "zid.json" };

    for (config_files) |file| {
        std.fs.cwd().access(file, .{}) catch continue;
        return alloc.dupe(u8, file);
    }

    return null;
}

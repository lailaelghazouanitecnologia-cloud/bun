//! Transpiler Framework
//!
//! API for building transpilers. Provides:
//! - Pipeline: Multi-stage transformation chain
//! - IR: Intermediate representation for AST/code
//! - Metadata: Project configuration
//!
//! Quick Start:
//! ```zig
//! const zid = @import("zid");
//!
//! pub const pipeline = zid.Pipeline{
//!     .name = "my-transpiler",
//!     .input = "src/*.mylang",
//!     .stages = &.{
//!         .{ .name = "parse", .run = parse },
//!         .{ .name = "emit", .run = emit },
//!     },
//! };
//! ```

const std = @import("std");
const Output = @import("../output.zig");
const fs = @import("../fs.zig");

// Re-export pipeline components
const pipeline = @import("pipeline.zig");
pub const Pipeline = pipeline.Pipeline;
pub const Stage = pipeline.Stage;
pub const StageContext = pipeline.StageContext;
pub const debugStage = pipeline.debugStage;
pub const identityStage = pipeline.identityStage;

// Re-export IR components
pub const ir = @import("ir.zig");
pub const IR = ir;
pub const Builder = ir.Builder;
pub const Node = ir.Node;
pub const NodeRef = ir.NodeRef;
pub const Location = ir.Location;
pub const Type = ir.Type;
pub const BinaryOp = ir.BinaryOp;
pub const UnaryOp = ir.UnaryOp;

pub const Metadata = @import("metadata.zig").Metadata;

pub fn init(alloc: std.mem.Allocator, template: []const u8, name: []const u8) !void {
    Output.print("Creating project: {s}\n", .{name});
    Output.print("Template: {s}\n", .{template});

    // Create directory
    try fs.mkdir(name);

    // Generate files
    try generateProject(alloc, name, template);

    Output.success("\nProject created!\n", .{});
    Output.print("  cd {s}\n", .{name});
    Output.print("  zid build\n", .{});
}

pub fn build(alloc: std.mem.Allocator) !void {
    _ = alloc;

    if (!fs.exists("zid.zig") and !fs.exists("zid.yaml")) {
        Output.err("No zid.zig or zid.yaml found.\n", .{});
        Output.print("Run 'zid init' to create a project.\n", .{});
        return error.NoProject;
    }

    Output.print("Building...\n", .{});
    // TODO: Run pipeline
    Output.success("Build complete.\n", .{});
}

pub fn watch(alloc: std.mem.Allocator) !void {
    _ = alloc;
    Output.print("Watching for changes... (Ctrl+C to stop)\n", .{});
    // TODO: File watcher
}

fn generateProject(alloc: std.mem.Allocator, name: []const u8, template: []const u8) !void {
    _ = template;

    // zid.zig
    const zid_content =
        \\//! Transpiler Configuration
        \\
        \\const zid = @import("zid");
        \\
        \\pub const config = .{
        \\    .name = "my-transpiler",
        \\    .input = "src/*.lua",
        \\    .output = "dist/",
        \\};
        \\
        \\pub const pipeline = zid.Pipeline{
        \\    .steps = &.{ lex, parse, emit },
        \\};
        \\
        \\fn lex(src: []const u8) ![]Token {
        \\    _ = src;
        \\    return &.{};
        \\}
        \\
        \\fn parse(tokens: []Token) !AST {
        \\    _ = tokens;
        \\    return .{};
        \\}
        \\
        \\fn emit(ast: AST) ![]const u8 {
        \\    _ = ast;
        \\    return "";
        \\}
        \\
        \\const Token = struct { kind: enum { eof }, text: []const u8 };
        \\const AST = struct {};
        \\
    ;

    const path = try fs.path.join(alloc, &.{ name, "zid.zig" });
    defer alloc.free(path);
    try fs.write(path, zid_content);

    // build.zig
    const build_content =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const exe = b.addExecutable(.{
        \\        .name = "transpiler",
        \\        .root_source_file = b.path("src/main.zig"),
        \\        .target = b.standardTargetOptions(.{}),
        \\        .optimize = b.standardOptimizeOption(.{}),
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    ;

    const build_path = try fs.path.join(alloc, &.{ name, "build.zig" });
    defer alloc.free(build_path);
    try fs.write(build_path, build_content);

    // src/
    const src_dir = try fs.path.join(alloc, &.{ name, "src" });
    defer alloc.free(src_dir);
    try fs.mkdir(src_dir);

    // src/main.zig
    const main_content =
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    std.debug.print("Transpiler ready\n", .{});
        \\}
        \\
    ;

    const main_path = try fs.path.join(alloc, &.{ name, "src/main.zig" });
    defer alloc.free(main_path);
    try fs.write(main_path, main_content);
}

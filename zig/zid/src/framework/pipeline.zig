//! Pipeline - Transformation chain for transpilers
//!
//! A pipeline defines the transformation stages:
//! 1. Source → Tokens (Lexer)
//! 2. Tokens → AST (Parser)
//! 3. AST → IR (Lower)
//! 4. IR → IR (Transform)
//! 5. IR → Output (Emit)
//!
//! Example:
//! ```zig
//! pub const pipeline = Pipeline{
//!     .input = "src/*.mylang",
//!     .output = "dist/",
//!     .stages = &.{
//!         .{ .name = "lex", .run = myLexer },
//!         .{ .name = "parse", .run = myParser },
//!         .{ .name = "emit", .run = jsEmitter },
//!     },
//! };
//! ```

const std = @import("std");
const zid = @import("../zid.zig");
const ir = @import("ir.zig");

pub const IR = ir;
pub const Builder = ir.Builder;
pub const Node = ir.Node;
pub const NodeRef = ir.NodeRef;

/// Pipeline configuration
pub const Pipeline = struct {
    name: []const u8 = "transpiler",
    input: []const u8 = "src/*",
    output: []const u8 = "dist/",
    stages: []const Stage = &.{},

    /// Run the pipeline on all matching files
    pub fn run(self: Pipeline, alloc: std.mem.Allocator) !void {
        const Output = zid.Output;
        Output.print("Running pipeline: {s}\n", .{self.name});

        // Find input files
        const files = try findFiles(alloc, self.input);
        defer alloc.free(files);

        if (files.len == 0) {
            Output.warn("No files matching: {s}\n", .{self.input});
            return;
        }

        Output.print("Processing {d} file(s)...\n", .{files.len});

        // Process each file
        for (files) |file| {
            try self.processFile(alloc, file);
        }

        Output.success("Pipeline complete.\n", .{});
    }

    fn processFile(self: Pipeline, alloc: std.mem.Allocator, path: []const u8) !void {
        const Output = zid.Output;
        Output.print("  {s}\n", .{path});

        // Read source
        const source = std.fs.cwd().readFileAlloc(alloc, path, 10 * 1024 * 1024) catch |e| {
            Output.err("Failed to read {s}: {}\n", .{ path, e });
            return e;
        };
        defer alloc.free(source);

        // Run stages
        var ctx = StageContext{
            .allocator = alloc,
            .source = source,
            .path = path,
            .ir = Builder.init(alloc),
            .output = std.ArrayList(u8).init(alloc),
        };
        defer ctx.ir.deinit();
        defer ctx.output.deinit();

        for (self.stages) |stage| {
            stage.run(&ctx) catch |e| {
                Output.err("Stage '{s}' failed: {}\n", .{ stage.name, e });
                return e;
            };
        }

        // Write output
        if (ctx.output.items.len > 0) {
            const out_path = try self.outputPath(alloc, path);
            defer alloc.free(out_path);

            // Ensure output directory
            if (std.fs.path.dirname(out_path)) |dir| {
                std.fs.makeDirAbsolute(dir) catch {};
            }

            const file = try std.fs.createFileAbsolute(out_path, .{});
            defer file.close();
            try file.writeAll(ctx.output.items);
        }
    }

    fn outputPath(self: Pipeline, alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
        const basename = std.fs.path.basename(input);
        const stem = std.fs.path.stem(basename);
        return std.fmt.allocPrint(alloc, "{s}/{s}.js", .{ self.output, stem });
    }

    fn findFiles(alloc: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(alloc);

        // Simple glob: src/*.ext
        const dir_part = std.fs.path.dirname(pattern) orelse ".";
        const ext = std.fs.path.extension(pattern);

        var dir = std.fs.cwd().openDir(dir_part, .{ .iterate = true }) catch {
            return list.toOwnedSlice();
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            const file_ext = std.fs.path.extension(entry.name);
            if (ext.len == 0 or std.mem.eql(u8, file_ext, ext)) {
                const full_path = try std.fs.path.join(alloc, &.{ dir_part, entry.name });
                try list.append(full_path);
            }
        }

        return list.toOwnedSlice();
    }
};

/// Stage context - passed between stages
pub const StageContext = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    path: []const u8,
    ir: Builder,
    output: std.ArrayList(u8),
    errors: std.ArrayList(Error) = undefined,

    pub const Error = struct {
        loc: ir.Location,
        message: []const u8,
        severity: enum { @"error", warning, hint },
    };

    pub fn init(self: *StageContext) void {
        self.errors = std.ArrayList(Error).init(self.allocator);
    }

    pub fn reportError(self: *StageContext, loc: ir.Location, msg: []const u8) void {
        self.errors.append(.{
            .loc = loc,
            .message = msg,
            .severity = .@"error",
        }) catch {};
    }
};

/// Pipeline stage
pub const Stage = struct {
    name: []const u8,
    run: *const fn (*StageContext) anyerror!void,
};

// ============ BUILT-IN STAGES ============

/// Debug stage - prints IR
pub fn debugStage(ctx: *StageContext) !void {
    const stdout = std.io.getStdOut().writer();
    try ir.print(&ctx.ir, stdout);
}

/// Identity stage - copies source to output
pub fn identityStage(ctx: *StageContext) !void {
    try ctx.output.appendSlice(ctx.source);
}

// ============ HELPERS ============

/// Create a simple lexer stage
pub fn lexerStage(comptime TokenType: type, lexFn: *const fn ([]const u8) []TokenType) Stage {
    const S = struct {
        fn run(ctx: *StageContext) !void {
            const tokens = lexFn(ctx.source);
            _ = tokens;
            // Store tokens in context for parser stage
        }
    };
    return .{ .name = "lexer", .run = S.run };
}

/// Create a simple emitter stage
pub fn emitterStage(emitFn: *const fn (*Builder, std.ArrayList(u8).Writer) anyerror!void) Stage {
    const S = struct {
        fn run(ctx: *StageContext) !void {
            try emitFn(&ctx.ir, ctx.output.writer());
        }
    };
    return .{ .name = "emit", .run = S.run };
}

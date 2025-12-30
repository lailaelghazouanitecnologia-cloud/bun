//! Template API
//!
//! Sistema de templates para crear proyectos.
//!
//! ```zig
//! const zid = @import("zid");
//!
//! // Crear proyecto desde template
//! try zid.template.create("svelte-kit", "my-app", .{
//!     .name = "my-app",
//!     .author = "user",
//! });
//!
//! // Registrar template custom
//! try zid.template.register("my-template", "/path/to/template");
//!
//! // Listar templates
//! const templates = try zid.template.list();
//! ```

const std = @import("std");
const fs = @import("fs.zig");

// ============ BUILT-IN TEMPLATES ============

pub const BuiltinTemplate = struct {
    name: []const u8,
    description: []const u8,
    files: []const File,

    pub const File = struct {
        path: []const u8,
        content: []const u8,
    };
};

pub const builtin_templates = [_]BuiltinTemplate{
    // Basic Zig project
    .{
        .name = "zig",
        .description = "Basic Zig project",
        .files = &.{
            .{ .path = "build.zig", .content = zig_build },
            .{ .path = "src/main.zig", .content = zig_main },
            .{ .path = ".gitignore", .content = zig_gitignore },
        },
    },
    // Zig library
    .{
        .name = "zig-lib",
        .description = "Zig library project",
        .files = &.{
            .{ .path = "build.zig", .content = zig_lib_build },
            .{ .path = "src/lib.zig", .content = zig_lib_src },
            .{ .path = ".gitignore", .content = zig_gitignore },
        },
    },
    // Zid script
    .{
        .name = "zid-script",
        .description = "Zid script project",
        .files = &.{
            .{ .path = "script.zig", .content = zid_script },
        },
    },
    // Transpiler
    .{
        .name = "transpiler",
        .description = "Language transpiler project",
        .files = &.{
            .{ .path = "build.zig", .content = transpiler_build },
            .{ .path = "src/main.zig", .content = transpiler_main },
            .{ .path = "src/lexer.zig", .content = transpiler_lexer },
            .{ .path = "src/parser.zig", .content = transpiler_parser },
            .{ .path = "src/emitter.zig", .content = transpiler_emitter },
        },
    },
};

// ============ CREATE ============

/// Create project from template
pub fn create(
    allocator: std.mem.Allocator,
    template_name: []const u8,
    project_name: []const u8,
    vars: anytype,
) !void {
    // Find template
    const tmpl = findBuiltin(template_name) orelse {
        // Try custom template
        return createFromPath(allocator, template_name, project_name, vars);
    };

    // Create project directory
    try fs.mkdir(project_name);

    // Create files
    for (tmpl.files) |file| {
        var path_buf: [256]u8 = undefined;
        const full_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ project_name, file.path });

        // Ensure parent directory exists
        if (std.fs.path.dirname(file.path)) |dir| {
            var dir_buf: [256]u8 = undefined;
            const full_dir = try std.fmt.bufPrint(&dir_buf, "{s}/{s}", .{ project_name, dir });
            try fs.mkdir(full_dir);
        }

        // Process template variables
        const content = try processVars(allocator, file.content, project_name, vars);
        defer allocator.free(content);

        try fs.write(full_path, content);
    }
}

/// Create from directory template
fn createFromPath(
    allocator: std.mem.Allocator,
    template_path: []const u8,
    project_name: []const u8,
    vars: anytype,
) !void {
    // Check if template exists
    if (!fs.isDir(template_path)) {
        return error.TemplateNotFound;
    }

    // Copy template
    try fs.copy(template_path, project_name);

    // Process all files for variable substitution
    const files = try @import("search.zig").glob(allocator, project_name ++ "/**/*");
    defer allocator.free(files);

    for (files) |file| {
        if (fs.isDir(file)) continue;

        const content = fs.read(allocator, file) catch continue;
        defer allocator.free(content);

        const processed = try processVars(allocator, content, project_name, vars);
        defer allocator.free(processed);

        if (!std.mem.eql(u8, content, processed)) {
            try fs.write(file, processed);
        }
    }
}

fn processVars(
    allocator: std.mem.Allocator,
    content: []const u8,
    project_name: []const u8,
    vars: anytype,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);

    var i: usize = 0;
    while (i < content.len) {
        // Look for {{variable}}
        if (i + 2 < content.len and content[i] == '{' and content[i + 1] == '{') {
            const end = std.mem.indexOf(u8, content[i..], "}}") orelse {
                try result.append(content[i]);
                i += 1;
                continue;
            };

            const var_name = std.mem.trim(u8, content[i + 2 .. i + end], " ");

            // Replace with value
            if (std.mem.eql(u8, var_name, "name") or std.mem.eql(u8, var_name, "project_name")) {
                try result.appendSlice(project_name);
            } else {
                // Check vars struct
                const VarsType = @TypeOf(vars);
                const vars_info = @typeInfo(VarsType);

                if (vars_info == .Struct) {
                    inline for (vars_info.Struct.fields) |field| {
                        if (std.mem.eql(u8, field.name, var_name)) {
                            const val = @field(vars, field.name);
                            if (@TypeOf(val) == []const u8) {
                                try result.appendSlice(val);
                            }
                        }
                    }
                }
            }

            i += end + 2;
        } else {
            try result.append(content[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

// ============ LIST ============

/// List available templates
pub fn list() []const BuiltinTemplate {
    return &builtin_templates;
}

/// Find builtin template by name
pub fn findBuiltin(name: []const u8) ?*const BuiltinTemplate {
    for (&builtin_templates) |*t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}

// ============ TEMPLATE CONTENTS ============

const zig_build =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    const exe = b.addExecutable(.{
    \\        .name = "{{name}}",
    \\        .root_source_file = b.path("src/main.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\
    \\    b.installArtifact(exe);
    \\
    \\    const run_cmd = b.addRunArtifact(exe);
    \\    run_cmd.step.dependOn(b.getInstallStep());
    \\
    \\    const run_step = b.step("run", "Run the application");
    \\    run_step.dependOn(&run_cmd.step);
    \\}
;

const zig_main =
    \\const std = @import("std");
    \\
    \\pub fn main() !void {
    \\    std.debug.print("Hello, {{name}}!\n", .{});
    \\}
;

const zig_gitignore =
    \\zig-cache/
    \\zig-out/
    \\.zig-cache/
    \\*.o
    \\*.a
;

const zig_lib_build =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    _ = b.addModule("{{name}}", .{
    \\        .root_source_file = b.path("src/lib.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\
    \\    const tests = b.addTest(.{
    \\        .root_source_file = b.path("src/lib.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\
    \\    const test_step = b.step("test", "Run tests");
    \\    test_step.dependOn(&b.addRunArtifact(tests).step);
    \\}
;

const zig_lib_src =
    \\//! {{name}} library
    \\
    \\const std = @import("std");
    \\
    \\pub fn add(a: i32, b: i32) i32 {
    \\    return a + b;
    \\}
    \\
    \\test "add" {
    \\    try std.testing.expectEqual(@as(i32, 3), add(1, 2));
    \\}
;

const zid_script =
    \\//! {{name}} - Zid script
    \\
    \\const zid = @import("zid");
    \\
    \\pub fn main() !void {
    \\    zid.print("Running {{name}}...\n", .{});
    \\
    \\    // Filesystem
    \\    const files = try zid.search.glob(zid.allocator, "**/*.zig");
    \\    zid.print("Found {d} Zig files\n", .{files.len});
    \\
    \\    // Shell
    \\    const result = try zid.shell.exec(zid.allocator, "echo", .{"Hello from shell"});
    \\    zid.print("{s}", .{result.stdout});
    \\}
;

const transpiler_build =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    const exe = b.addExecutable(.{
    \\        .name = "{{name}}",
    \\        .root_source_file = b.path("src/main.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\
    \\    b.installArtifact(exe);
    \\
    \\    const run_step = b.step("run", "Run transpiler");
    \\    run_step.dependOn(&b.addRunArtifact(exe).step);
    \\}
;

const transpiler_main =
    \\const std = @import("std");
    \\const Lexer = @import("lexer.zig").Lexer;
    \\const Parser = @import("parser.zig").Parser;
    \\const Emitter = @import("emitter.zig").Emitter;
    \\
    \\pub fn main() !void {
    \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    \\    defer _ = gpa.deinit();
    \\    const allocator = gpa.allocator();
    \\
    \\    const args = try std.process.argsAlloc(allocator);
    \\    defer std.process.argsFree(allocator, args);
    \\
    \\    if (args.len < 2) {
    \\        std.debug.print("Usage: {{name}} <file>\n", .{});
    \\        return;
    \\    }
    \\
    \\    const source = try std.fs.cwd().readFileAlloc(allocator, args[1], 10 * 1024 * 1024);
    \\    defer allocator.free(source);
    \\
    \\    var lexer = Lexer.init(source);
    \\    const tokens = try lexer.tokenize(allocator);
    \\
    \\    var parser = Parser.init(tokens);
    \\    const ast = try parser.parse(allocator);
    \\
    \\    var emitter = Emitter.init(allocator);
    \\    const output = try emitter.emit(ast);
    \\
    \\    const stdout = std.io.getStdOut().writer();
    \\    try stdout.writeAll(output);
    \\}
;

const transpiler_lexer =
    \\//! Lexer - tokenize source code
    \\
    \\const std = @import("std");
    \\
    \\pub const Token = struct {
    \\    kind: Kind,
    \\    text: []const u8,
    \\    line: u32,
    \\
    \\    pub const Kind = enum {
    \\        identifier,
    \\        number,
    \\        string,
    \\        lparen,
    \\        rparen,
    \\        eof,
    \\    };
    \\};
    \\
    \\pub const Lexer = struct {
    \\    source: []const u8,
    \\    pos: usize = 0,
    \\    line: u32 = 1,
    \\
    \\    pub fn init(source: []const u8) Lexer {
    \\        return .{ .source = source };
    \\    }
    \\
    \\    pub fn tokenize(self: *Lexer, allocator: std.mem.Allocator) ![]Token {
    \\        var tokens = std.ArrayList(Token).init(allocator);
    \\
    \\        while (self.pos < self.source.len) {
    \\            const token = self.nextToken();
    \\            try tokens.append(token);
    \\            if (token.kind == .eof) break;
    \\        }
    \\
    \\        return tokens.toOwnedSlice();
    \\    }
    \\
    \\    fn nextToken(self: *Lexer) Token {
    \\        self.skipWhitespace();
    \\
    \\        if (self.pos >= self.source.len) {
    \\            return .{ .kind = .eof, .text = "", .line = self.line };
    \\        }
    \\
    \\        // TODO: Implement tokenization
    \\        const start = self.pos;
    \\        self.pos += 1;
    \\
    \\        return .{
    \\            .kind = .identifier,
    \\            .text = self.source[start..self.pos],
    \\            .line = self.line,
    \\        };
    \\    }
    \\
    \\    fn skipWhitespace(self: *Lexer) void {
    \\        while (self.pos < self.source.len) {
    \\            const c = self.source[self.pos];
    \\            if (c == '\n') self.line += 1;
    \\            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
    \\            self.pos += 1;
    \\        }
    \\    }
    \\};
;

const transpiler_parser =
    \\//! Parser - build AST from tokens
    \\
    \\const std = @import("std");
    \\const Token = @import("lexer.zig").Token;
    \\
    \\pub const Node = struct {
    \\    kind: Kind,
    \\    children: []Node = &.{},
    \\    token: ?Token = null,
    \\
    \\    pub const Kind = enum {
    \\        program,
    \\        expression,
    \\        call,
    \\        literal,
    \\    };
    \\};
    \\
    \\pub const Parser = struct {
    \\    tokens: []const Token,
    \\    pos: usize = 0,
    \\
    \\    pub fn init(tokens: []const Token) Parser {
    \\        return .{ .tokens = tokens };
    \\    }
    \\
    \\    pub fn parse(self: *Parser, allocator: std.mem.Allocator) !Node {
    \\        var children = std.ArrayList(Node).init(allocator);
    \\
    \\        while (!self.isAtEnd()) {
    \\            const expr = try self.parseExpression(allocator);
    \\            try children.append(expr);
    \\        }
    \\
    \\        return .{
    \\            .kind = .program,
    \\            .children = try children.toOwnedSlice(),
    \\        };
    \\    }
    \\
    \\    fn parseExpression(self: *Parser, allocator: std.mem.Allocator) !Node {
    \\        _ = allocator;
    \\        const token = self.advance();
    \\        return .{ .kind = .literal, .token = token };
    \\    }
    \\
    \\    fn advance(self: *Parser) Token {
    \\        if (!self.isAtEnd()) self.pos += 1;
    \\        return self.tokens[self.pos - 1];
    \\    }
    \\
    \\    fn isAtEnd(self: *Parser) bool {
    \\        return self.pos >= self.tokens.len or self.tokens[self.pos].kind == .eof;
    \\    }
    \\};
;

const transpiler_emitter =
    \\//! Emitter - generate output from AST
    \\
    \\const std = @import("std");
    \\const Node = @import("parser.zig").Node;
    \\
    \\pub const Emitter = struct {
    \\    allocator: std.mem.Allocator,
    \\    output: std.ArrayList(u8),
    \\
    \\    pub fn init(allocator: std.mem.Allocator) Emitter {
    \\        return .{
    \\            .allocator = allocator,
    \\            .output = std.ArrayList(u8).init(allocator),
    \\        };
    \\    }
    \\
    \\    pub fn emit(self: *Emitter, ast: Node) ![]const u8 {
    \\        try self.emitNode(ast);
    \\        return self.output.toOwnedSlice();
    \\    }
    \\
    \\    fn emitNode(self: *Emitter, node: Node) !void {
    \\        switch (node.kind) {
    \\            .program => {
    \\                for (node.children) |child| {
    \\                    try self.emitNode(child);
    \\                }
    \\            },
    \\            .literal => {
    \\                if (node.token) |t| {
    \\                    try self.output.appendSlice(t.text);
    \\                }
    \\            },
    \\            else => {},
    \\        }
    \\    }
    \\};
;

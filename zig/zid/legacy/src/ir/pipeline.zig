const std = @import("std");
const types = @import("types.zig");
const nodes = @import("nodes.zig");
const builder = @import("builder.zig");

// Lifters (AST → IR)
const lua_lift = @import("../lift/lua.zig");

// Lowers (IR → Target)
const wat_lower = @import("../lower/wat.zig");

// Language capabilities
const capabilities = @import("../lang/capabilities.zig");

const Type = types.Type;
const Node = nodes.Node;
const Builder = builder.Builder;

/// IR Pipeline - Orchestrates the full compilation flow
/// Source → Lex → Parse → Lift → [Transforms] → Lower → Output
pub const Pipeline = struct {
    alloc: std.mem.Allocator,
    transforms: std.ArrayList(TransformFn),
    diagnostics: std.ArrayList(Diagnostic),

    pub const TransformFn = *const fn (*Node, std.mem.Allocator) anyerror!void;

    pub const Diagnostic = struct {
        level: Level,
        message: []const u8,
        location: ?Location = null,

        pub const Level = enum { info, warning, error_ };
        pub const Location = struct {
            line: u32,
            column: u32,
            file: ?[]const u8 = null,
        };
    };

    pub fn init(alloc: std.mem.Allocator) Pipeline {
        return .{
            .alloc = alloc,
            .transforms = std.ArrayList(TransformFn).init(alloc),
            .diagnostics = std.ArrayList(Diagnostic).init(alloc),
        };
    }

    pub fn deinit(self: *Pipeline) void {
        self.transforms.deinit();
        self.diagnostics.deinit();
    }

    /// Add a transform pass
    pub fn addTransform(self: *Pipeline, transform: TransformFn) !void {
        try self.transforms.append(transform);
    }

    /// Compile from source language to target
    pub fn compile(
        self: *Pipeline,
        source: []const u8,
        lang: []const u8,
        target: []const u8,
    ) ![]const u8 {
        // Step 0: Check capability compatibility
        const compat = try self.checkCompatibility(lang, target);
        if (!compat.isCompatible()) {
            for (compat.errors.slice()) |err| {
                try self.report(.error_, err);
            }
            return error.IncompatibleLanguages;
        }
        // Log warnings
        for (compat.warnings.slice()) |warn| {
            try self.report(.warning, warn);
        }

        // Step 1: Parse source to AST
        const ast = try self.parse(source, lang);

        // Step 2: Lift AST to IR
        var ir = try self.lift(ast, source, lang);

        // Step 3: Apply transforms
        for (self.transforms.items) |transform| {
            try transform(&ir, self.alloc);
        }

        // Step 4: Lower IR to target
        return self.lower(ir, target);
    }

    /// Check if source language can be transpiled to target
    fn checkCompatibility(self: *Pipeline, lang: []const u8, target: []const u8) !capabilities.CompatResult {
        _ = self;
        const source_caps = capabilities.get(lang) orelse return capabilities.CompatResult{};
        const target_caps = capabilities.get(target) orelse return capabilities.CompatResult{};
        return source_caps.canTranspileTo(target_caps);
    }

    /// Get capabilities for a language
    pub fn getCapabilities(lang: []const u8) ?capabilities.Capabilities {
        return capabilities.get(lang);
    }

    /// Parse source to language-specific AST
    fn parse(self: *Pipeline, source: []const u8, lang: []const u8) !anytype {
        if (std.mem.eql(u8, lang, "lua")) {
            const lua_lexer = @import("../builtin/lua/lexer.zig");
            const lua_parser = @import("../builtin/lua/parser.zig");

            var lexer = lua_lexer.Lexer{ .source = source };
            var tokens = std.ArrayList(lua_lexer.Token).init(self.alloc);
            while (true) {
                const tok = lexer.next();
                try tokens.append(tok);
                if (tok.kind == .eof) break;
            }

            var parser = lua_parser.Parser{
                .tokens = tokens.items,
                .source = source,
                .alloc = self.alloc,
            };
            return parser.parse();
        }

        // TODO: Add more language parsers
        return error.UnsupportedLanguage;
    }

    /// Lift language AST to universal IR
    fn lift(self: *Pipeline, ast: anytype, source: []const u8, lang: []const u8) !Node {
        if (std.mem.eql(u8, lang, "lua")) {
            var lifter = lua_lift.LuaLift.init(self.alloc, source);
            return lifter.lift(ast);
        }

        // TODO: Add more language lifters
        return error.UnsupportedLanguage;
    }

    /// Lower IR to target format
    fn lower(self: *Pipeline, ir: Node, target: []const u8) ![]const u8 {
        if (std.mem.eql(u8, target, "wat")) {
            var lower = wat_lower.WatLower.init(self.alloc);
            return lower.lower(ir);
        }

        // TODO: Add more target lowers
        return error.UnsupportedTarget;
    }

    /// Add a diagnostic message
    pub fn report(self: *Pipeline, level: Diagnostic.Level, message: []const u8) !void {
        try self.diagnostics.append(.{
            .level = level,
            .message = message,
        });
    }

    /// Get all error diagnostics
    pub fn errors(self: *Pipeline) []const Diagnostic {
        var result = std.ArrayList(Diagnostic).init(self.alloc);
        for (self.diagnostics.items) |d| {
            if (d.level == .error_) {
                result.append(d) catch {};
            }
        }
        return result.items;
    }
};

// ============ BUILT-IN TRANSFORMS ============

/// Dead code elimination
pub fn deadCodeElimination(ir: *Node, alloc: std.mem.Allocator) !void {
    _ = alloc;
    switch (ir.*) {
        .module => |*m| {
            // Remove unreachable items
            // TODO: implement DCE
            _ = m;
        },
        else => {},
    }
}

/// Constant folding
pub fn constantFolding(ir: *Node, alloc: std.mem.Allocator) !void {
    _ = alloc;
    switch (ir.*) {
        .binary => |*b| {
            // Try to fold constant expressions
            const left = b.left.*;
            const right = b.right.*;

            if (left == .int_lit and right == .int_lit) {
                const l = left.int_lit.value;
                const r = right.int_lit.value;

                const result: ?i64 = switch (b.op) {
                    .add => l + r,
                    .sub => l - r,
                    .mul => l * r,
                    .div => if (r != 0) @divTrunc(l, r) else null,
                    .rem => if (r != 0) @rem(l, r) else null,
                    else => null,
                };

                if (result) |v| {
                    ir.* = Node{ .int_lit = .{ .value = v } };
                }
            }
        },
        .module => |m| {
            for (m.items) |*item| {
                try constantFolding(item, alloc);
            }
        },
        .func => |f| {
            if (f.body) |body| {
                var body_copy = body.*;
                try constantFolding(&body_copy, alloc);
            }
        },
        .block => |b| {
            for (b.stmts) |*stmt| {
                try constantFolding(stmt, alloc);
            }
        },
        else => {},
    }
}

/// Type inference pass
pub fn inferTypes(ir: *Node, alloc: std.mem.Allocator) !void {
    _ = alloc;
    switch (ir.*) {
        .binary => |*b| {
            // Infer binary expression type from operands
            if (b.typ == null) {
                const left_type = b.left.getType();
                const right_type = b.right.getType();

                // Use left type if both are same, otherwise use wider type
                if (left_type) |lt| {
                    if (right_type) |rt| {
                        if (lt.eql(rt)) {
                            b.typ = lt;
                        }
                    } else {
                        b.typ = lt;
                    }
                } else if (right_type) |rt| {
                    b.typ = rt;
                }
            }
        },
        else => {},
    }
}

// ============ CONVENIENCE FUNCTIONS ============

/// Quick compile from Lua to WAT via IR
pub fn luaToWat(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    var pipeline = Pipeline.init(alloc);
    defer pipeline.deinit();

    // Add optimization passes
    try pipeline.addTransform(constantFolding);

    return pipeline.compile(source, "lua", "wat");
}

// ============ TESTS ============

test "pipeline lua to wat" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\function add(a, b)
        \\    return a + b
        \\end
    ;

    var pipeline = Pipeline.init(alloc);
    const wat = try pipeline.compile(source, "lua", "wat");

    try std.testing.expect(std.mem.indexOf(u8, wat, "(module") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "func $add") != null);
}

test "constant folding transform" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Create 1 + 2 expression
    var b = builder.Builder.init(alloc);
    const one = b.int(1);
    const two = b.int(2);
    var add = b.add(try b.alloc_node(one), try b.alloc_node(two));

    try constantFolding(&add, alloc);

    // Should be folded to 3
    try std.testing.expect(add == .int_lit);
    try std.testing.expectEqual(@as(i64, 3), add.int_lit.value);
}

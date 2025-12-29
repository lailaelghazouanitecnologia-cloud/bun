const std = @import("std");

/// Transpiler Directives
/// Commands embedded in source code to control transpilation behavior
///
/// Syntax: @zid:<command>(<args>)
/// Or comment-based: // @zid:<command>(<args>)
///
pub const Directive = union(enum) {
    // ============ FFI / INTEROP ============

    /// Use external library from another language
    /// @zid:use_lib("wgpu", "rust") - use Rust's wgpu crate
    /// @zid:use_lib("raylib", "c") - use C raylib
    use_lib: UseLib,

    /// Export this function/module for use from another language
    /// @zid:export("c") - generate C bindings
    /// @zid:export("wasm") - export as WASM module
    export: Export,

    /// Import bindings from generated FFI
    /// @zid:import_ffi("./bindings.h")
    import_ffi: ImportFFI,

    /// Inline foreign code (will not be transpiled)
    /// @zid:foreign("c") { ... }
    foreign: Foreign,

    // ============ TRANSPILATION CONTROL ============

    /// Skip transpilation for this block (keep as-is)
    /// @zid:passthrough
    passthrough: void,

    /// Force LLM assistance for this block
    /// @zid:llm_assist("complex pattern matching")
    llm_assist: LLMAssist,

    /// Never use LLM for this block (fail if can't auto-transpile)
    /// @zid:no_llm
    no_llm: void,

    /// Specify target-specific implementation
    /// @zid:target("wat") { ... }
    /// @zid:target("rust") { ... }
    target_impl: TargetImpl,

    /// Conditional compilation based on target
    /// @zid:if_target("wasm") { ... }
    if_target: IfTarget,

    // ============ TYPE HINTS ============

    /// Override inferred type for transpilation
    /// @zid:type(i32)
    type_hint: TypeHint,

    /// Mark as nullable (for targets with null)
    /// @zid:nullable
    nullable: void,

    /// Mark as non-null (for safety)
    /// @zid:non_null
    non_null: void,

    /// Specify ownership semantics
    /// @zid:owned / @zid:borrowed / @zid:shared
    ownership: Ownership,

    // ============ MEMORY ============

    /// Allocate on stack (if possible)
    /// @zid:stack
    stack_alloc: void,

    /// Allocate on heap
    /// @zid:heap
    heap_alloc: void,

    /// Use specific allocator
    /// @zid:alloc("arena")
    allocator: Allocator,

    /// Mark for manual memory management
    /// @zid:manual_memory
    manual_memory: void,

    // ============ OPTIMIZATION ============

    /// Inline this function
    /// @zid:inline
    inline_fn: void,

    /// Never inline
    /// @zid:noinline
    noinline: void,

    /// Unroll loop
    /// @zid:unroll(4)
    unroll: Unroll,

    /// SIMD hint
    /// @zid:simd
    simd: void,

    // ============ SAFETY ============

    /// Disable bounds checking
    /// @zid:unchecked
    unchecked: void,

    /// Enable extra runtime checks
    /// @zid:checked
    checked: void,

    /// Mark as unsafe (allows unsafe operations)
    /// @zid:unsafe
    unsafe_block: void,

    // ============ DOCUMENTATION ============

    /// Preserve comment in output
    /// @zid:keep_comment
    keep_comment: void,

    /// Generate documentation
    /// @zid:doc("Description")
    doc: Doc,

    // ============ TESTING ============

    /// Only include in test builds
    /// @zid:test_only
    test_only: void,

    /// Exclude from test builds
    /// @zid:no_test
    no_test: void,

    // ============ STRUCTS ============

    pub const UseLib = struct {
        name: []const u8,
        lang: []const u8,
        version: ?[]const u8 = null,
        features: []const []const u8 = &.{},
    };

    pub const Export = struct {
        target: []const u8, // "c", "wasm", "python", etc.
        name: ?[]const u8 = null, // override exported name
        visibility: Visibility = .public,

        pub const Visibility = enum { public, internal };
    };

    pub const ImportFFI = struct {
        path: []const u8,
        lang: ?[]const u8 = null,
    };

    pub const Foreign = struct {
        lang: []const u8,
        code: []const u8,
    };

    pub const LLMAssist = struct {
        reason: ?[]const u8 = null,
        max_tokens: u32 = 1024,
        temperature: f32 = 0.2,
    };

    pub const TargetImpl = struct {
        target: []const u8,
        code: []const u8,
    };

    pub const IfTarget = struct {
        target: []const u8,
        condition: ?[]const u8 = null, // e.g., "wasm32" or "wasm64"
    };

    pub const TypeHint = struct {
        type_name: []const u8,
    };

    pub const Ownership = enum {
        owned, // Transfer ownership
        borrowed, // Temporary borrow
        shared, // Reference counted
        copy, // Copy semantics
    };

    pub const Allocator = struct {
        name: []const u8, // "arena", "page", "general", etc.
    };

    pub const Unroll = struct {
        factor: ?u32 = null, // null = full unroll
    };

    pub const Doc = struct {
        text: []const u8,
    };
};

/// Parse directives from source code
pub const DirectiveParser = struct {
    source: []const u8,
    pos: usize = 0,
    alloc: std.mem.Allocator,
    directives: std.ArrayList(ParsedDirective),

    pub const ParsedDirective = struct {
        directive: Directive,
        line: u32,
        column: u32,
        span_start: usize,
        span_end: usize,
    };

    pub fn init(alloc: std.mem.Allocator, source: []const u8) DirectiveParser {
        return .{
            .source = source,
            .alloc = alloc,
            .directives = std.ArrayList(ParsedDirective).init(alloc),
        };
    }

    pub fn deinit(self: *DirectiveParser) void {
        self.directives.deinit();
    }

    /// Parse all directives in source
    pub fn parse(self: *DirectiveParser) ![]ParsedDirective {
        var line: u32 = 1;
        var line_start: usize = 0;

        while (self.pos < self.source.len) {
            // Track line numbers
            if (self.source[self.pos] == '\n') {
                line += 1;
                line_start = self.pos + 1;
            }

            // Look for @zid:
            if (self.startsWith("@zid:")) {
                const start = self.pos;
                const column = @as(u32, @intCast(self.pos - line_start + 1));

                if (try self.parseDirective()) |dir| {
                    try self.directives.append(.{
                        .directive = dir,
                        .line = line,
                        .column = column,
                        .span_start = start,
                        .span_end = self.pos,
                    });
                }
            } else {
                self.pos += 1;
            }
        }

        return self.directives.items;
    }

    fn parseDirective(self: *DirectiveParser) !?Directive {
        self.pos += 5; // Skip "@zid:"

        // Get command name
        const cmd_start = self.pos;
        while (self.pos < self.source.len and (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        const cmd = self.source[cmd_start..self.pos];

        // Parse based on command
        if (std.mem.eql(u8, cmd, "use_lib")) {
            return try self.parseUseLib();
        } else if (std.mem.eql(u8, cmd, "export")) {
            return try self.parseExport();
        } else if (std.mem.eql(u8, cmd, "passthrough")) {
            return .passthrough;
        } else if (std.mem.eql(u8, cmd, "llm_assist")) {
            return try self.parseLLMAssist();
        } else if (std.mem.eql(u8, cmd, "no_llm")) {
            return .no_llm;
        } else if (std.mem.eql(u8, cmd, "target")) {
            return try self.parseTargetImpl();
        } else if (std.mem.eql(u8, cmd, "if_target")) {
            return try self.parseIfTarget();
        } else if (std.mem.eql(u8, cmd, "type")) {
            return try self.parseTypeHint();
        } else if (std.mem.eql(u8, cmd, "nullable")) {
            return .nullable;
        } else if (std.mem.eql(u8, cmd, "non_null")) {
            return .non_null;
        } else if (std.mem.eql(u8, cmd, "owned")) {
            return .{ .ownership = .owned };
        } else if (std.mem.eql(u8, cmd, "borrowed")) {
            return .{ .ownership = .borrowed };
        } else if (std.mem.eql(u8, cmd, "shared")) {
            return .{ .ownership = .shared };
        } else if (std.mem.eql(u8, cmd, "stack")) {
            return .stack_alloc;
        } else if (std.mem.eql(u8, cmd, "heap")) {
            return .heap_alloc;
        } else if (std.mem.eql(u8, cmd, "inline")) {
            return .inline_fn;
        } else if (std.mem.eql(u8, cmd, "noinline")) {
            return .noinline;
        } else if (std.mem.eql(u8, cmd, "unroll")) {
            return try self.parseUnroll();
        } else if (std.mem.eql(u8, cmd, "simd")) {
            return .simd;
        } else if (std.mem.eql(u8, cmd, "unchecked")) {
            return .unchecked;
        } else if (std.mem.eql(u8, cmd, "checked")) {
            return .checked;
        } else if (std.mem.eql(u8, cmd, "unsafe")) {
            return .unsafe_block;
        } else if (std.mem.eql(u8, cmd, "foreign")) {
            return try self.parseForeign();
        } else if (std.mem.eql(u8, cmd, "doc")) {
            return try self.parseDoc();
        } else if (std.mem.eql(u8, cmd, "test_only")) {
            return .test_only;
        } else if (std.mem.eql(u8, cmd, "no_test")) {
            return .no_test;
        }

        return null;
    }

    fn parseUseLib(self: *DirectiveParser) !Directive {
        _ = try self.expect('(');
        const name = try self.parseString();
        _ = try self.expect(',');
        self.skipWhitespace();
        const lang = try self.parseString();
        _ = try self.expect(')');

        return .{ .use_lib = .{
            .name = name,
            .lang = lang,
        } };
    }

    fn parseExport(self: *DirectiveParser) !Directive {
        _ = try self.expect('(');
        const target = try self.parseString();
        _ = try self.expect(')');

        return .{ .export = .{ .target = target } };
    }

    fn parseLLMAssist(self: *DirectiveParser) !Directive {
        var assist = Directive.LLMAssist{};

        if (self.pos < self.source.len and self.source[self.pos] == '(') {
            self.pos += 1;
            assist.reason = try self.parseString();
            _ = try self.expect(')');
        }

        return .{ .llm_assist = assist };
    }

    fn parseTargetImpl(self: *DirectiveParser) !Directive {
        _ = try self.expect('(');
        const target = try self.parseString();
        _ = try self.expect(')');

        // Find code block
        self.skipWhitespace();
        const code = try self.parseBlock();

        return .{ .target_impl = .{
            .target = target,
            .code = code,
        } };
    }

    fn parseIfTarget(self: *DirectiveParser) !Directive {
        _ = try self.expect('(');
        const target = try self.parseString();
        _ = try self.expect(')');

        return .{ .if_target = .{ .target = target } };
    }

    fn parseTypeHint(self: *DirectiveParser) !Directive {
        _ = try self.expect('(');
        const type_name = try self.parseIdent();
        _ = try self.expect(')');

        return .{ .type_hint = .{ .type_name = type_name } };
    }

    fn parseUnroll(self: *DirectiveParser) !Directive {
        var factor: ?u32 = null;

        if (self.pos < self.source.len and self.source[self.pos] == '(') {
            self.pos += 1;
            factor = try self.parseNumber();
            _ = try self.expect(')');
        }

        return .{ .unroll = .{ .factor = factor } };
    }

    fn parseForeign(self: *DirectiveParser) !Directive {
        _ = try self.expect('(');
        const lang = try self.parseString();
        _ = try self.expect(')');

        self.skipWhitespace();
        const code = try self.parseBlock();

        return .{ .foreign = .{
            .lang = lang,
            .code = code,
        } };
    }

    fn parseDoc(self: *DirectiveParser) !Directive {
        _ = try self.expect('(');
        const text = try self.parseString();
        _ = try self.expect(')');

        return .{ .doc = .{ .text = text } };
    }

    // ============ HELPERS ============

    fn startsWith(self: *DirectiveParser, prefix: []const u8) bool {
        if (self.pos + prefix.len > self.source.len) return false;
        return std.mem.eql(u8, self.source[self.pos..][0..prefix.len], prefix);
    }

    fn skipWhitespace(self: *DirectiveParser) void {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
        }
    }

    fn expect(self: *DirectiveParser, char: u8) !u8 {
        self.skipWhitespace();
        if (self.pos >= self.source.len or self.source[self.pos] != char) {
            return error.UnexpectedChar;
        }
        self.pos += 1;
        return char;
    }

    fn parseString(self: *DirectiveParser) ![]const u8 {
        self.skipWhitespace();
        if (self.pos >= self.source.len or self.source[self.pos] != '"') {
            return error.ExpectedString;
        }
        self.pos += 1;

        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') self.pos += 1;
            self.pos += 1;
        }
        const end = self.pos;
        self.pos += 1; // Skip closing quote

        return self.source[start..end];
    }

    fn parseIdent(self: *DirectiveParser) ![]const u8 {
        self.skipWhitespace();
        const start = self.pos;
        while (self.pos < self.source.len and (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        if (start == self.pos) return error.ExpectedIdent;
        return self.source[start..self.pos];
    }

    fn parseNumber(self: *DirectiveParser) !u32 {
        self.skipWhitespace();
        const start = self.pos;
        while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
            self.pos += 1;
        }
        if (start == self.pos) return error.ExpectedNumber;
        return std.fmt.parseInt(u32, self.source[start..self.pos], 10) catch return error.InvalidNumber;
    }

    fn parseBlock(self: *DirectiveParser) ![]const u8 {
        if (self.pos >= self.source.len or self.source[self.pos] != '{') {
            return error.ExpectedBlock;
        }
        self.pos += 1;

        const start = self.pos;
        var depth: u32 = 1;

        while (self.pos < self.source.len and depth > 0) {
            if (self.source[self.pos] == '{') depth += 1;
            if (self.source[self.pos] == '}') depth -= 1;
            self.pos += 1;
        }

        return self.source[start .. self.pos - 1];
    }
};

// ============ COMMAND LIST ============

/// All available transpiler commands with descriptions
pub const commands = [_]CommandInfo{
    // FFI / Interop
    .{ .name = "use_lib", .syntax = "@zid:use_lib(\"name\", \"lang\")", .description = "Import library from another language", .category = .ffi },
    .{ .name = "export", .syntax = "@zid:export(\"target\")", .description = "Export for use from another language", .category = .ffi },
    .{ .name = "import_ffi", .syntax = "@zid:import_ffi(\"path\")", .description = "Import FFI bindings file", .category = .ffi },
    .{ .name = "foreign", .syntax = "@zid:foreign(\"lang\") { code }", .description = "Inline foreign code (not transpiled)", .category = .ffi },

    // Transpilation Control
    .{ .name = "passthrough", .syntax = "@zid:passthrough", .description = "Skip transpilation, keep as-is", .category = .transpile },
    .{ .name = "llm_assist", .syntax = "@zid:llm_assist(\"reason\")", .description = "Request LLM help for this block", .category = .transpile },
    .{ .name = "no_llm", .syntax = "@zid:no_llm", .description = "Never use LLM (fail if can't auto)", .category = .transpile },
    .{ .name = "target", .syntax = "@zid:target(\"t\") { code }", .description = "Target-specific implementation", .category = .transpile },
    .{ .name = "if_target", .syntax = "@zid:if_target(\"t\")", .description = "Conditional on target", .category = .transpile },

    // Types
    .{ .name = "type", .syntax = "@zid:type(T)", .description = "Override inferred type", .category = .types },
    .{ .name = "nullable", .syntax = "@zid:nullable", .description = "Mark as nullable", .category = .types },
    .{ .name = "non_null", .syntax = "@zid:non_null", .description = "Mark as non-null", .category = .types },
    .{ .name = "owned", .syntax = "@zid:owned", .description = "Transfer ownership", .category = .types },
    .{ .name = "borrowed", .syntax = "@zid:borrowed", .description = "Temporary borrow", .category = .types },
    .{ .name = "shared", .syntax = "@zid:shared", .description = "Reference counted", .category = .types },

    // Memory
    .{ .name = "stack", .syntax = "@zid:stack", .description = "Allocate on stack", .category = .memory },
    .{ .name = "heap", .syntax = "@zid:heap", .description = "Allocate on heap", .category = .memory },
    .{ .name = "alloc", .syntax = "@zid:alloc(\"name\")", .description = "Use specific allocator", .category = .memory },
    .{ .name = "manual_memory", .syntax = "@zid:manual_memory", .description = "Manual memory management", .category = .memory },

    // Optimization
    .{ .name = "inline", .syntax = "@zid:inline", .description = "Inline function", .category = .optimize },
    .{ .name = "noinline", .syntax = "@zid:noinline", .description = "Never inline", .category = .optimize },
    .{ .name = "unroll", .syntax = "@zid:unroll(n)", .description = "Unroll loop n times", .category = .optimize },
    .{ .name = "simd", .syntax = "@zid:simd", .description = "SIMD optimization hint", .category = .optimize },

    // Safety
    .{ .name = "unchecked", .syntax = "@zid:unchecked", .description = "Disable bounds checking", .category = .safety },
    .{ .name = "checked", .syntax = "@zid:checked", .description = "Enable extra checks", .category = .safety },
    .{ .name = "unsafe", .syntax = "@zid:unsafe", .description = "Allow unsafe operations", .category = .safety },

    // Documentation
    .{ .name = "keep_comment", .syntax = "@zid:keep_comment", .description = "Preserve in output", .category = .docs },
    .{ .name = "doc", .syntax = "@zid:doc(\"text\")", .description = "Add documentation", .category = .docs },

    // Testing
    .{ .name = "test_only", .syntax = "@zid:test_only", .description = "Only in test builds", .category = .testing },
    .{ .name = "no_test", .syntax = "@zid:no_test", .description = "Exclude from tests", .category = .testing },
};

pub const CommandInfo = struct {
    name: []const u8,
    syntax: []const u8,
    description: []const u8,
    category: Category,

    pub const Category = enum {
        ffi,
        transpile,
        types,
        memory,
        optimize,
        safety,
        docs,
        testing,
    };
};

/// Print all available commands
pub fn printHelp(writer: anytype) !void {
    try writer.print("\n=== ZID TRANSPILER COMMANDS ===\n\n", .{});

    inline for (std.meta.tags(CommandInfo.Category)) |cat| {
        try writer.print("{s}:\n", .{@tagName(cat)});
        for (commands) |cmd| {
            if (cmd.category == cat) {
                try writer.print("  {s: <30} {s}\n", .{ cmd.syntax, cmd.description });
            }
        }
        try writer.print("\n", .{});
    }
}

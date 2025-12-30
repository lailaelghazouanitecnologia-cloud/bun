const std = @import("std");
const config = @import("config.zig");

// Built-in modules (embedded)
const lua_lexer = @import("builtin/lua/lexer.zig");
const lua_parser = @import("builtin/lua/parser.zig");
const rust_lexer = @import("builtin/rust/lexer.zig");
const rust_parser = @import("builtin/rust/parser.zig");
const wat_emitter = @import("builtin/wat/emitter.zig");
const rust_emitter = @import("builtin/rust/emitter.zig");

// IR Pipeline (new architecture)
const ir_pipeline = @import("ir/pipeline.zig");

// LLM-assisted transpilation
const llm = @import("lang/llm.zig");
const capabilities = @import("lang/capabilities.zig");

pub fn compileFile(alloc: std.mem.Allocator, file_path: []const u8, target_override: ?[]const u8) ![]const u8 {
    // Read source file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
    const source = try file.readToEndAlloc(alloc, 10 * 1024 * 1024);

    // Detect language from extension
    const ext = std.fs.path.extension(file_path);
    const lang = detectLang(ext);

    // Get target from config or override
    const target = target_override orelse try getDefaultTarget(alloc, lang);

    return compile(alloc, source, lang, target);
}

pub const CompileMode = enum {
    direct, // Direct AST → Target (legacy, faster for simple cases)
    ir, // AST → IR → Target (new, preserves semantics for complex transpilation)
    llm, // IR + LLM for complex features that can't be auto-transpiled
    hybrid, // Auto-transpile what we can, LLM for conflicts
};

/// Result from LLM-assisted compilation
pub const LLMCompileResult = struct {
    /// The transpiled code
    code: []const u8,

    /// Warnings from LLM
    warnings: []const llm.LLMTranspiler.LLMResponse.Warning,

    /// Conflicts that were processed
    conflicts_count: usize,

    /// Whether all conflicts were resolved with high confidence
    fully_resolved: bool,
};

pub fn compile(alloc: std.mem.Allocator, source: []const u8, lang: []const u8, target: []const u8) ![]const u8 {
    return compileWithMode(alloc, source, lang, target, .direct);
}

pub fn compileWithMode(alloc: std.mem.Allocator, source: []const u8, lang: []const u8, target: []const u8, mode: CompileMode) ![]const u8 {
    switch (mode) {
        .ir => return compileViaIR(alloc, source, lang, target),
        .llm => {
            const result = try compileWithLLM(alloc, source, lang, target, .{});
            return result.code;
        },
        .hybrid => {
            const result = try compileHybrid(alloc, source, lang, target);
            return result.code;
        },
        .direct => {},
    }

    // Direct mode - fast path for simple transpilation
    // Lua -> WAT
    if (std.mem.eql(u8, lang, "lua") and std.mem.eql(u8, target, "wat")) {
        return compileLuaToWat(alloc, source);
    }

    // Lua -> Rust
    if (std.mem.eql(u8, lang, "lua") and std.mem.eql(u8, target, "rust")) {
        return compileLuaToRust(alloc, source);
    }

    // Rust -> WAT
    if (std.mem.eql(u8, lang, "rust") and std.mem.eql(u8, target, "wat")) {
        return compileRustToWat(alloc, source);
    }

    // Rust -> Rust (format/normalize)
    if (std.mem.eql(u8, lang, "rust") and std.mem.eql(u8, target, "rust")) {
        return compileRustToRust(alloc, source);
    }

    // Try IR pipeline as fallback
    return compileViaIR(alloc, source, lang, target);
}

/// Compile using LLM for all complex features
pub fn compileWithLLM(
    alloc: std.mem.Allocator,
    source: []const u8,
    lang: []const u8,
    target: []const u8,
    llm_config: llm.LLMTranspiler.Config,
) !LLMCompileResult {
    var transpiler = llm.LLMTranspiler.init(alloc, llm_config);
    defer transpiler.deinit();

    // Check capabilities and find conflicts
    const source_caps = capabilities.get(lang);
    const target_caps = capabilities.get(target);

    if (source_caps != null and target_caps != null) {
        const compat = source_caps.?.canTranspileTo(target_caps.?);

        // Mark all features that need transformation as conflicts
        if (compat.hasTransforms()) {
            for (compat.info.slice()) |info| {
                try transpiler.addConflict(.{
                    .kind = .unsupported_feature,
                    .source = source,
                    .location = .{ .line = 1, .column = 1 },
                    .source_lang = lang,
                    .target_lang = target,
                    .feature = .generics, // TODO: detect actual feature
                    .context = info,
                });
            }
        }
    }

    // Process conflicts with LLM
    try transpiler.processConflicts();

    // If no conflicts or all resolved, compile normally
    if (transpiler.conflicts.items.len == 0) {
        return LLMCompileResult{
            .code = try compileViaIR(alloc, source, lang, target),
            .warnings = &.{},
            .conflicts_count = 0,
            .fully_resolved = true,
        };
    }

    // Return LLM-transpiled code
    return LLMCompileResult{
        .code = transpiler.getTranspiled(0) orelse "",
        .warnings = transpiler.getWarnings(),
        .conflicts_count = transpiler.conflicts.items.len,
        .fully_resolved = transpiler.allResolved(0.8),
    };
}

/// Hybrid mode: auto-transpile what we can, LLM for conflicts
pub fn compileHybrid(
    alloc: std.mem.Allocator,
    source: []const u8,
    lang: []const u8,
    target: []const u8,
) !LLMCompileResult {
    // First, try IR pipeline
    const ir_result = compileViaIR(alloc, source, lang, target) catch |err| {
        // If IR fails, fall back to full LLM
        if (err == error.IncompatibleLanguages or err == error.UnsupportedLanguage) {
            return compileWithLLM(alloc, source, lang, target, .{});
        }
        return err;
    };

    // Check for warnings that indicate partial transpilation
    var pipeline = ir_pipeline.Pipeline.init(alloc);
    defer pipeline.deinit();

    const compat = pipeline.checkCompatibility(lang, target) catch {
        return LLMCompileResult{
            .code = ir_result,
            .warnings = &.{},
            .conflicts_count = 0,
            .fully_resolved = true,
        };
    };

    // If there are transforms needed, use LLM for those parts
    if (compat.hasTransforms()) {
        return compileWithLLM(alloc, source, lang, target, .{});
    }

    return LLMCompileResult{
        .code = ir_result,
        .warnings = &.{},
        .conflicts_count = 0,
        .fully_resolved = true,
    };
}

fn compileViaIR(alloc: std.mem.Allocator, source: []const u8, lang: []const u8, target: []const u8) ![]const u8 {
    var pipeline = ir_pipeline.Pipeline.init(alloc);
    defer pipeline.deinit();

    // Add optimization transforms
    try pipeline.addTransform(ir_pipeline.constantFolding);

    return pipeline.compile(source, lang, target);
}

fn compileLuaToWat(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    const tokens = try lex(lua_lexer, alloc, source);
    var parser = lua_parser.Parser{
        .tokens = tokens,
        .source = source,
        .alloc = alloc,
    };
    const ast = try parser.parse();
    var emitter = wat_emitter.Emitter.init(alloc, source);
    return emitter.emit(ast);
}

fn compileLuaToRust(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    const tokens = try lex(lua_lexer, alloc, source);
    var parser = lua_parser.Parser{
        .tokens = tokens,
        .source = source,
        .alloc = alloc,
    };
    const ast = try parser.parse();
    var emitter = rust_emitter.Emitter.init(alloc, source);
    return emitter.emit(ast);
}

fn compileRustToWat(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    const tokens = try lex(rust_lexer, alloc, source);
    var parser = rust_parser.Parser{
        .tokens = tokens,
        .source = source,
        .alloc = alloc,
    };
    const ast = try parser.parse();
    var emitter = wat_emitter.Emitter.init(alloc, source);
    return emitter.emit(ast);
}

fn compileRustToRust(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    const tokens = try lex(rust_lexer, alloc, source);
    var parser = rust_parser.Parser{
        .tokens = tokens,
        .source = source,
        .alloc = alloc,
    };
    const ast = try parser.parse();
    var emitter = rust_emitter.Emitter.init(alloc, source);
    return emitter.emit(ast);
}

fn lex(comptime L: type, alloc: std.mem.Allocator, source: []const u8) ![]L.Token {
    var lexer = L.Lexer{ .source = source };
    var tokens = std.ArrayList(L.Token).init(alloc);
    while (true) {
        const tok = lexer.next();
        try tokens.append(tok);
        if (tok.kind == .eof) break;
    }
    return tokens.items;
}

fn detectLang(ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".lua")) return "lua";
    if (std.mem.eql(u8, ext, ".rs")) return "rust";
    if (std.mem.eql(u8, ext, ".py")) return "python";
    if (std.mem.eql(u8, ext, ".lisp") or std.mem.eql(u8, ext, ".scm")) return "lisp";
    if (std.mem.eql(u8, ext, ".js")) return "javascript";
    return "unknown";
}

fn getDefaultTarget(alloc: std.mem.Allocator, lang: []const u8) ![]const u8 {
    const cfg = try config.load(alloc);
    if (config.getDefaultTarget(cfg, lang)) |target| {
        return target;
    }
    // Default fallback
    return "wat";
}

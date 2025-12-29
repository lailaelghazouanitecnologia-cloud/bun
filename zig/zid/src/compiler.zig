const std = @import("std");
const config = @import("config.zig");

// Built-in modules (embedded)
const lua_lexer = @import("builtin/lua/lexer.zig");
const lua_parser = @import("builtin/lua/parser.zig");
const rust_lexer = @import("builtin/rust/lexer.zig");
const rust_parser = @import("builtin/rust/parser.zig");
const wat_emitter = @import("builtin/wat/emitter.zig");
const rust_emitter = @import("builtin/rust/emitter.zig");

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

pub fn compile(alloc: std.mem.Allocator, source: []const u8, lang: []const u8, target: []const u8) ![]const u8 {
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

    std.debug.print("No compiler available for {s} -> {s}\n", .{ lang, target });
    return error.NoCompilerAvailable;
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

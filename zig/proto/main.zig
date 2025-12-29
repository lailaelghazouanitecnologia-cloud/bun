const std = @import("std");
const t = @import("templates.zig");
const engine = @import("engine.zig");

pub fn compile(source: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    // Lex
    var lexer = engine.Lexer{ .source = source };
    var tokens = std.ArrayList(t.Token).init(alloc);
    while (true) {
        const tok = lexer.next();
        try tokens.append(tok);
        if (tok.kind == .eof) break;
    }

    // Parse
    var parser = engine.Parser{
        .tokens = tokens.items,
        .source = source,
        .alloc = alloc,
    };
    const ast = try parser.parse();

    // Emit
    var output = std.ArrayList(u8).init(alloc);
    var emitter = engine.Emitter{
        .op = .{ .out = &output },
        .source = source,
        .locals = std.StringHashMap(u32).init(alloc),
        .alloc = alloc,
    };

    return try emitter.emit(ast);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const source =
        \\-- Lua -> WAT
        \\function add(a, b)
        \\    return a + b
        \\end
        \\
        \\function sum(n)
        \\    local total = 0
        \\    local i = 1
        \\    while i < n do
        \\        total = total + i
        \\        i = i + 1
        \\    end
        \\    return total
        \\end
    ;

    std.debug.print("=== LUA ===\n{s}\n\n", .{source});
    std.debug.print("=== WAT ===\n{s}\n", .{try compile(source, alloc)});
}

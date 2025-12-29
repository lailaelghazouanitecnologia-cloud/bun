const std = @import("std");
const t = @import("templates.zig");
const engine = @import("engine.zig");

// ============ DATA ============

fn Data(comptime T: type) type {
    return struct {
        value: T,

        const Self = @This();

        pub fn of(value: T) Self {
            return .{ .value = value };
        }

        pub fn map(self: Self, comptime f: anytype) Data(@typeInfo(@TypeOf(f)).Fn.return_type.?) {
            return .{ .value = f(self.value) };
        }

        pub fn unwrap(self: Self) T {
            return self.value;
        }
    };
}

// ============ COMPOSE ============

fn compose(comptime functions: anytype) fn (anytype) @typeInfo(@TypeOf(functions[functions.len - 1])).Fn.return_type.? {
    return struct {
        fn run(input: anytype) @typeInfo(@TypeOf(functions[functions.len - 1])).Fn.return_type.? {
            var result: anytype = input;
            inline for (functions) |f| {
                result = f(result);
            }
            return result;
        }
    }.run;
}

// ============ PIPELINE ============

pub fn compile(source: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    // 1. Lex
    var lexer = engine.Lexer{ .source = source };
    var tokens = std.ArrayList(t.Token).init(allocator);
    while (true) {
        const tok = lexer.next();
        try tokens.append(tok);
        if (tok.kind == .eof) break;
    }

    // 2. Parse
    var parser = engine.Parser{
        .tokens = tokens.items,
        .source = source,
        .allocator = allocator,
    };
    const ast = try parser.parse();

    // 3. Emit WAT
    var emitter = engine.Emitter{
        .output = std.ArrayList(u8).init(allocator),
        .source = source,
        .locals = std.StringHashMap(u32).init(allocator),
        .allocator = allocator,
    };

    return try emitter.emit(ast);
}

// ============ MAIN ============

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const source =
        \\-- Ejemplo Lua -> WAT
        \\function add(a, b)
        \\    return a + b
        \\end
        \\
        \\function factorial(n)
        \\    if n < 2 then
        \\        return 1
        \\    else
        \\        return n * factorial(n - 1)
        \\    end
        \\end
    ;

    std.debug.print("=== INPUT (Lua) ===\n{s}\n\n", .{source});

    const wat = try compile(source, allocator);

    std.debug.print("=== OUTPUT (WAT) ===\n{s}\n", .{wat});
}

// ============ TESTS ============

test "add function" {
    const source = "function add(a, b)\n    return a + b\nend";
    const wat = try compile(source, std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.add") != null);
}

test "multiply" {
    const source = "function mul(x, y)\n    return x * y\nend";
    const wat = try compile(source, std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.mul") != null);
}

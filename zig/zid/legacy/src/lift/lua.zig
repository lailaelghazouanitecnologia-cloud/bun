const std = @import("std");
const lua_parser = @import("../builtin/lua/parser.zig");
const ir_types = @import("../ir/types.zig");
const ir_nodes = @import("../ir/nodes.zig");

const LuaNode = lua_parser.Node;
const LuaNodeKind = lua_parser.NodeKind;
const Type = ir_types.Type;
const Node = ir_nodes.Node;

/// Lua AST → IR Lift
/// Converts Lua's parsed AST to universal IR representation
pub const LuaLift = struct {
    alloc: std.mem.Allocator,
    source: []const u8,

    pub fn init(alloc: std.mem.Allocator, source: []const u8) LuaLift {
        return .{
            .alloc = alloc,
            .source = source,
        };
    }

    /// Lift entire Lua program to IR module
    pub fn lift(self: *LuaLift, ast: LuaNode) !Node {
        return switch (ast.kind) {
            .program => self.liftProgram(ast),
            else => self.liftNode(ast),
        };
    }

    fn liftProgram(self: *LuaLift, node: LuaNode) !Node {
        var items = std.ArrayList(Node).init(self.alloc);

        for (node.children) |child| {
            const ir_node = try self.liftNode(child);
            try items.append(ir_node);
        }

        return Node{ .module = .{
            .name = "main",
            .items = try items.toOwnedSlice(),
        } };
    }

    fn liftNode(self: *LuaLift, node: LuaNode) !Node {
        return switch (node.kind) {
            .program => self.liftProgram(node),
            .func_decl => self.liftFunc(node),
            .block => self.liftBlock(node),
            .return_stmt => self.liftReturn(node),
            .local_decl => self.liftLocal(node),
            .assign_stmt => self.liftAssign(node),
            .if_stmt => self.liftIf(node),
            .while_stmt => self.liftWhile(node),
            .for_stmt => self.liftFor(node),
            .binary_expr => self.liftBinary(node),
            .unary_expr => self.liftUnary(node),
            .call_expr => self.liftCall(node),
            .index_expr => self.liftIndex(node),
            .identifier => self.liftIdent(node),
            .number_lit => self.liftNumber(node),
            .string_lit => self.liftString(node),
            .bool_lit => self.liftBool(node),
            .nil_lit => self.liftNil(),
            .table_lit => self.liftTable(node),
            .param => unreachable, // Handled in liftFunc
        };
    }

    fn liftFunc(self: *LuaLift, node: LuaNode) !Node {
        const name = if (node.token) |tok| tok.text(self.source) else "anonymous";

        // Parse params (all children except last which is body)
        var params = std.ArrayList(ir_nodes.Param).init(self.alloc);
        const body_idx = node.children.len - 1;

        for (node.children[0..body_idx]) |child| {
            if (child.kind == .param) {
                const param_name = if (child.token) |tok| tok.text(self.source) else "_";
                try params.append(.{
                    .name = param_name,
                    .typ = .any, // Lua is dynamically typed
                });
            }
        }

        // Lift body
        const body_node = try self.liftNode(node.children[body_idx]);
        const body_ptr = try self.allocNode(body_node);

        return Node{ .func = .{
            .name = name,
            .params = try params.toOwnedSlice(),
            .body = body_ptr,
        } };
    }

    fn liftBlock(self: *LuaLift, node: LuaNode) !Node {
        var stmts = std.ArrayList(Node).init(self.alloc);

        for (node.children) |child| {
            try stmts.append(try self.liftNode(child));
        }

        return Node{ .block = .{
            .stmts = try stmts.toOwnedSlice(),
        } };
    }

    fn liftReturn(self: *LuaLift, node: LuaNode) !Node {
        if (node.children.len > 0) {
            const value = try self.liftNode(node.children[0]);
            return Node{ .return_ = .{
                .value = try self.allocNode(value),
            } };
        }
        return Node{ .return_ = .{} };
    }

    fn liftLocal(self: *LuaLift, node: LuaNode) !Node {
        const name = if (node.token) |tok| tok.text(self.source) else "_";

        var value: ?*const Node = null;
        if (node.children.len > 0) {
            const val = try self.liftNode(node.children[0]);
            value = try self.allocNode(val);
        }

        return Node{ .let = .{
            .name = name,
            .value = value,
            .mutable = true, // Lua variables are mutable by default
        } };
    }

    fn liftAssign(self: *LuaLift, node: LuaNode) !Node {
        if (node.children.len < 2) {
            return Node{ .expr_stmt = .{
                .expr = try self.allocNode(try self.liftNil()),
            } };
        }

        const target = try self.liftNode(node.children[0]);
        const value = try self.liftNode(node.children[1]);

        return Node{ .assign = .{
            .target = try self.allocNode(target),
            .value = try self.allocNode(value),
        } };
    }

    fn liftIf(self: *LuaLift, node: LuaNode) !Node {
        if (node.children.len < 2) {
            return self.liftNil();
        }

        // First condition and then block
        const cond = try self.liftNode(node.children[0]);
        const then_block = try self.liftNode(node.children[1]);

        // Handle else/elseif chain
        var else_node: ?*const Node = null;
        if (node.children.len > 2) {
            // Has else or elseif
            if (node.children.len == 3) {
                // Simple else
                const else_block = try self.liftNode(node.children[2]);
                else_node = try self.allocNode(else_block);
            } else {
                // elseif chain - build nested if
                else_node = try self.buildElseIfChain(node.children[2..]);
            }
        }

        return Node{ .if_ = .{
            .cond = try self.allocNode(cond),
            .then_ = try self.allocNode(then_block),
            .else_ = else_node,
        } };
    }

    fn buildElseIfChain(self: *LuaLift, children: []const LuaNode) !*const Node {
        if (children.len == 0) {
            return self.allocNode(try self.liftNil());
        }
        if (children.len == 1) {
            // Final else block
            return self.allocNode(try self.liftNode(children[0]));
        }

        // elseif: cond, block, rest...
        const cond = try self.liftNode(children[0]);
        const then_block = try self.liftNode(children[1]);
        const else_node = if (children.len > 2)
            try self.buildElseIfChain(children[2..])
        else
            null;

        return self.allocNode(Node{ .if_ = .{
            .cond = try self.allocNode(cond),
            .then_ = try self.allocNode(then_block),
            .else_ = else_node,
        } });
    }

    fn liftWhile(self: *LuaLift, node: LuaNode) !Node {
        if (node.children.len < 2) {
            return self.liftNil();
        }

        const cond = try self.liftNode(node.children[0]);
        const body = try self.liftNode(node.children[1]);

        return Node{ .while_ = .{
            .cond = try self.allocNode(cond),
            .body = try self.allocNode(body),
        } };
    }

    fn liftFor(self: *LuaLift, node: LuaNode) !Node {
        // Lua numeric for: for i = start, end, step do ... end
        // children: [identifier, start, end, (step?), body]
        if (node.children.len < 4) {
            return self.liftNil();
        }

        const binding = if (node.children[0].token) |tok|
            tok.text(self.source)
        else
            "i";

        // Create range expression: start..end
        const start = try self.liftNode(node.children[1]);
        const end = try self.liftNode(node.children[2]);
        const range = Node{ .binary = .{
            .op = .range,
            .left = try self.allocNode(start),
            .right = try self.allocNode(end),
        } };

        // Body is last child
        const body_idx = node.children.len - 1;
        const body = try self.liftNode(node.children[body_idx]);

        return Node{ .for_ = .{
            .binding = binding,
            .iter = try self.allocNode(range),
            .body = try self.allocNode(body),
        } };
    }

    fn liftBinary(self: *LuaLift, node: LuaNode) !Node {
        if (node.children.len < 2) {
            return self.liftNil();
        }

        const left = try self.liftNode(node.children[0]);
        const right = try self.liftNode(node.children[1]);

        const op = if (node.token) |tok| self.tokenToBinaryOp(tok) else .add;

        return Node{ .binary = .{
            .op = op,
            .left = try self.allocNode(left),
            .right = try self.allocNode(right),
        } };
    }

    fn tokenToBinaryOp(self: *LuaLift, tok: lua_parser.lexer.Token) ir_nodes.BinaryOp {
        _ = self;
        const lexer = @import("../builtin/lua/lexer.zig");
        return switch (tok.kind) {
            .plus => .add,
            .minus => .sub,
            .star => .mul,
            .slash => .div,
            .percent => .rem,
            .caret => .pow,
            .eqeq => .eq,
            .neq => .ne,
            .lt => .lt,
            .gt => .gt,
            .lte => .le,
            .gte => .ge,
            .kw_and => .and_,
            .kw_or => .or_,
            .dotdot => .concat,
            else => .add,
        };
    }

    fn liftUnary(self: *LuaLift, node: LuaNode) !Node {
        if (node.children.len < 1) {
            return self.liftNil();
        }

        const operand = try self.liftNode(node.children[0]);
        const op = if (node.token) |tok| self.tokenToUnaryOp(tok) else .neg;

        return Node{ .unary = .{
            .op = op,
            .operand = try self.allocNode(operand),
        } };
    }

    fn tokenToUnaryOp(self: *LuaLift, tok: lua_parser.lexer.Token) ir_nodes.UnaryOp {
        _ = self;
        const lexer = @import("../builtin/lua/lexer.zig");
        return switch (tok.kind) {
            .minus => .neg,
            .kw_not => .not,
            else => .neg,
        };
    }

    fn liftCall(self: *LuaLift, node: LuaNode) !Node {
        // Get function name from token
        const func_name = if (node.token) |tok| tok.text(self.source) else "unknown";
        const func_ident = Node{ .ident = .{ .name = func_name } };

        var args = std.ArrayList(ir_nodes.Arg).init(self.alloc);
        for (node.children) |child| {
            const arg_value = try self.liftNode(child);
            try args.append(.{
                .value = try self.allocNode(arg_value),
            });
        }

        return Node{ .call = .{
            .func = try self.allocNode(func_ident),
            .args = try args.toOwnedSlice(),
        } };
    }

    fn liftIndex(self: *LuaLift, node: LuaNode) !Node {
        if (node.children.len < 2) {
            return self.liftNil();
        }

        const object = try self.liftNode(node.children[0]);
        const idx = node.children[1];

        // Check if it's field access (string literal index)
        if (idx.kind == .string_lit) {
            const field_name = if (idx.token) |tok| tok.text(self.source) else "";
            return Node{ .field = .{
                .object = try self.allocNode(object),
                .field = field_name,
            } };
        }

        const index_expr = try self.liftNode(idx);
        return Node{ .index = .{
            .object = try self.allocNode(object),
            .index = try self.allocNode(index_expr),
        } };
    }

    fn liftIdent(self: *LuaLift, node: LuaNode) !Node {
        const name = if (node.token) |tok| tok.text(self.source) else "_";
        return Node{ .ident = .{
            .name = name,
            .typ = .any, // Lua is dynamically typed
        } };
    }

    fn liftNumber(self: *LuaLift, node: LuaNode) !Node {
        const text = node.value orelse "0";

        // Check if it's a float
        for (text) |c| {
            if (c == '.') {
                const val = std.fmt.parseFloat(f64, text) catch 0.0;
                return Node{ .float_lit = .{ .value = val } };
            }
        }

        const val = std.fmt.parseInt(i64, text, 10) catch 0;
        return Node{ .int_lit = .{ .value = val } };
    }

    fn liftString(self: *LuaLift, node: LuaNode) !Node {
        const text = if (node.token) |tok| tok.text(self.source) else "";
        // Remove quotes
        var value = text;
        if (value.len >= 2) {
            if (value[0] == '"' or value[0] == '\'') {
                value = value[1 .. value.len - 1];
            }
        }
        return Node{ .string_lit = .{ .value = value } };
    }

    fn liftBool(self: *LuaLift, node: LuaNode) !Node {
        const val = if (node.value) |v|
            std.mem.eql(u8, v, "true")
        else
            false;
        return Node{ .bool_lit = .{ .value = val } };
    }

    fn liftNil(self: *LuaLift) !Node {
        // Nil maps to an optional type with null value
        // For now, use a special identifier
        _ = self;
        return Node{ .ident = .{
            .name = "nil",
            .typ = .{ .option = .{ .inner = &Type.any } },
        } };
    }

    fn liftTable(self: *LuaLift, node: LuaNode) !Node {
        // Tables can be arrays or objects
        // For simplicity, treat as array if all elements are sequential
        var elems = std.ArrayList(Node).init(self.alloc);
        for (node.children) |child| {
            try elems.append(try self.liftNode(child));
        }
        return Node{ .array_lit = .{
            .elems = try elems.toOwnedSlice(),
        } };
    }

    // Helper to allocate node on heap
    fn allocNode(self: *LuaLift, node: Node) !*const Node {
        const ptr = try self.alloc.create(Node);
        ptr.* = node;
        return ptr;
    }
};

// ============ TESTS ============

test "lift simple function" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source =
        \\function add(a, b)
        \\    return a + b
        \\end
    ;

    const lexer = @import("../builtin/lua/lexer.zig");
    var lex = lexer.Lexer{ .source = source };
    var tokens = std.ArrayList(lexer.Token).init(alloc);
    while (true) {
        const tok = lex.next();
        try tokens.append(tok);
        if (tok.kind == .eof) break;
    }

    var parser = lua_parser.Parser{
        .tokens = tokens.items,
        .source = source,
        .alloc = alloc,
    };
    const ast = try parser.parse();

    var lift = LuaLift.init(alloc, source);
    const ir = try lift.lift(ast);

    // Verify we got a module
    try std.testing.expect(ir == .module);
    try std.testing.expectEqual(@as(usize, 1), ir.module.items.len);
}

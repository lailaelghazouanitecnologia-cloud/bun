const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;
const TokenKind = lexer.TokenKind;

pub const NodeKind = enum {
    program,
    func_decl,
    param,
    block,
    return_stmt,
    local_decl,
    assign_stmt,
    if_stmt,
    while_stmt,
    for_stmt,
    binary_expr,
    unary_expr,
    call_expr,
    index_expr,
    identifier,
    number_lit,
    string_lit,
    bool_lit,
    nil_lit,
    table_lit,
};

pub const Node = struct {
    kind: NodeKind,
    token: ?Token = null,
    children: []Node = &.{},
    value: ?[]const u8 = null,
};

pub const Parser = struct {
    tokens: []Token,
    source: []const u8,
    pos: usize = 0,
    alloc: std.mem.Allocator,

    pub fn parse(self: *Parser) !Node {
        var stmts = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.eof)) {
            if (self.check(.kw_function)) {
                try stmts.append(try self.parseFunction());
            } else if (self.check(.kw_local)) {
                try stmts.append(try self.parseLocal());
            } else if (self.check(.kw_if)) {
                try stmts.append(try self.parseIf());
            } else if (self.check(.kw_while)) {
                try stmts.append(try self.parseWhile());
            } else if (self.check(.kw_for)) {
                try stmts.append(try self.parseFor());
            } else if (self.check(.kw_return)) {
                try stmts.append(try self.parseReturn());
            } else if (self.check(.ident)) {
                try stmts.append(try self.parseExprStmt());
            } else {
                self.pos += 1;
            }
        }
        return .{ .kind = .program, .children = try stmts.toOwnedSlice() };
    }

    fn parseFunction(self: *Parser) !Node {
        _ = self.expect(.kw_function);
        const name = self.expect(.ident);
        _ = self.expect(.lparen);

        var params = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.rparen) and !self.check(.eof)) {
            try params.append(.{ .kind = .param, .token = self.expect(.ident) });
            if (!self.match(.comma)) break;
        }
        _ = self.expect(.rparen);

        const body = try self.parseBlock();
        _ = self.expect(.kw_end);

        var children = std.ArrayList(Node).init(self.alloc);
        try children.appendSlice(try params.toOwnedSlice());
        try children.append(body);
        return .{ .kind = .func_decl, .token = name, .children = try children.toOwnedSlice() };
    }

    fn parseBlock(self: *Parser) !Node {
        var stmts = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.kw_end) and !self.check(.kw_else) and !self.check(.kw_elseif) and
            !self.check(.kw_until) and !self.check(.eof))
        {
            if (self.check(.kw_local)) {
                try stmts.append(try self.parseLocal());
            } else if (self.check(.kw_return)) {
                try stmts.append(try self.parseReturn());
                break;
            } else if (self.check(.kw_if)) {
                try stmts.append(try self.parseIf());
            } else if (self.check(.kw_while)) {
                try stmts.append(try self.parseWhile());
            } else if (self.check(.kw_for)) {
                try stmts.append(try self.parseFor());
            } else if (self.check(.kw_break)) {
                self.pos += 1;
            } else if (self.check(.ident)) {
                try stmts.append(try self.parseExprStmt());
            } else {
                break;
            }
        }
        return .{ .kind = .block, .children = try stmts.toOwnedSlice() };
    }

    fn parseLocal(self: *Parser) !Node {
        _ = self.expect(.kw_local);
        const name = self.expect(.ident);
        _ = self.expect(.eq);
        const value = try self.parseExpr();
        return .{
            .kind = .local_decl,
            .token = name,
            .children = try self.allocSlice(&[_]Node{value}),
        };
    }

    fn parseReturn(self: *Parser) !Node {
        _ = self.expect(.kw_return);
        if (self.check(.kw_end) or self.check(.kw_else) or self.check(.eof)) {
            return .{ .kind = .return_stmt, .children = &.{} };
        }
        return .{
            .kind = .return_stmt,
            .children = try self.allocSlice(&[_]Node{try self.parseExpr()}),
        };
    }

    fn parseIf(self: *Parser) !Node {
        _ = self.expect(.kw_if);
        const cond = try self.parseExpr();
        _ = self.expect(.kw_then);
        const then_block = try self.parseBlock();

        var children = std.ArrayList(Node).init(self.alloc);
        try children.append(cond);
        try children.append(then_block);

        while (self.match(.kw_elseif)) {
            const elif_cond = try self.parseExpr();
            _ = self.expect(.kw_then);
            const elif_block = try self.parseBlock();
            try children.append(elif_cond);
            try children.append(elif_block);
        }

        if (self.match(.kw_else)) {
            try children.append(try self.parseBlock());
        }
        _ = self.expect(.kw_end);

        return .{ .kind = .if_stmt, .children = try children.toOwnedSlice() };
    }

    fn parseWhile(self: *Parser) !Node {
        _ = self.expect(.kw_while);
        const cond = try self.parseExpr();
        _ = self.expect(.kw_do);
        const body = try self.parseBlock();
        _ = self.expect(.kw_end);
        return .{
            .kind = .while_stmt,
            .children = try self.allocSlice(&[_]Node{ cond, body }),
        };
    }

    fn parseFor(self: *Parser) !Node {
        _ = self.expect(.kw_for);
        const var_name = self.expect(.ident);
        _ = self.expect(.eq);
        const start = try self.parseExpr();
        _ = self.expect(.comma);
        const end = try self.parseExpr();

        var step: ?Node = null;
        if (self.match(.comma)) {
            step = try self.parseExpr();
        }

        _ = self.expect(.kw_do);
        const body = try self.parseBlock();
        _ = self.expect(.kw_end);

        var children = std.ArrayList(Node).init(self.alloc);
        try children.append(.{ .kind = .identifier, .token = var_name });
        try children.append(start);
        try children.append(end);
        if (step) |s| try children.append(s);
        try children.append(body);

        return .{ .kind = .for_stmt, .children = try children.toOwnedSlice() };
    }

    fn parseExprStmt(self: *Parser) !Node {
        const expr = try self.parseExpr();
        // Check if it's an assignment
        if (self.match(.eq)) {
            const value = try self.parseExpr();
            return .{
                .kind = .assign_stmt,
                .children = try self.allocSlice(&[_]Node{ expr, value }),
            };
        }
        return expr;
    }

    fn parseExpr(self: *Parser) !Node {
        return self.parseOr();
    }

    fn parseOr(self: *Parser) !Node {
        var left = try self.parseAnd();
        while (self.match(.kw_or)) {
            const op = self.tokens[self.pos - 1];
            const right = try self.parseAnd();
            left = .{
                .kind = .binary_expr,
                .token = op,
                .children = try self.allocSlice(&[_]Node{ left, right }),
            };
        }
        return left;
    }

    fn parseAnd(self: *Parser) !Node {
        var left = try self.parseComparison();
        while (self.match(.kw_and)) {
            const op = self.tokens[self.pos - 1];
            const right = try self.parseComparison();
            left = .{
                .kind = .binary_expr,
                .token = op,
                .children = try self.allocSlice(&[_]Node{ left, right }),
            };
        }
        return left;
    }

    fn parseComparison(self: *Parser) !Node {
        var left = try self.parseConcat();
        while (self.checkAny(&.{ .eqeq, .neq, .lt, .gt, .lte, .gte })) {
            const op = self.current();
            self.pos += 1;
            const right = try self.parseConcat();
            left = .{
                .kind = .binary_expr,
                .token = op,
                .children = try self.allocSlice(&[_]Node{ left, right }),
            };
        }
        return left;
    }

    fn parseConcat(self: *Parser) !Node {
        var left = try self.parseAddSub();
        while (self.match(.dotdot)) {
            const op = self.tokens[self.pos - 1];
            const right = try self.parseAddSub();
            left = .{
                .kind = .binary_expr,
                .token = op,
                .children = try self.allocSlice(&[_]Node{ left, right }),
            };
        }
        return left;
    }

    fn parseAddSub(self: *Parser) !Node {
        var left = try self.parseMulDiv();
        while (self.checkAny(&.{ .plus, .minus })) {
            const op = self.current();
            self.pos += 1;
            const right = try self.parseMulDiv();
            left = .{
                .kind = .binary_expr,
                .token = op,
                .children = try self.allocSlice(&[_]Node{ left, right }),
            };
        }
        return left;
    }

    fn parseMulDiv(self: *Parser) !Node {
        var left = try self.parseUnary();
        while (self.checkAny(&.{ .star, .slash, .percent })) {
            const op = self.current();
            self.pos += 1;
            const right = try self.parseUnary();
            left = .{
                .kind = .binary_expr,
                .token = op,
                .children = try self.allocSlice(&[_]Node{ left, right }),
            };
        }
        return left;
    }

    fn parseUnary(self: *Parser) !Node {
        if (self.checkAny(&.{ .minus, .kw_not })) {
            const op = self.current();
            self.pos += 1;
            const operand = try self.parseUnary();
            return .{
                .kind = .unary_expr,
                .token = op,
                .children = try self.allocSlice(&[_]Node{operand}),
            };
        }
        return self.parsePower();
    }

    fn parsePower(self: *Parser) !Node {
        var left = try self.parsePostfix();
        if (self.match(.caret)) {
            const op = self.tokens[self.pos - 1];
            const right = try self.parseUnary(); // Right associative
            left = .{
                .kind = .binary_expr,
                .token = op,
                .children = try self.allocSlice(&[_]Node{ left, right }),
            };
        }
        return left;
    }

    fn parsePostfix(self: *Parser) !Node {
        var left = try self.parsePrimary();
        while (true) {
            if (self.match(.lparen)) {
                // Function call
                var args = std.ArrayList(Node).init(self.alloc);
                while (!self.check(.rparen) and !self.check(.eof)) {
                    try args.append(try self.parseExpr());
                    if (!self.match(.comma)) break;
                }
                _ = self.expect(.rparen);
                left = .{
                    .kind = .call_expr,
                    .token = left.token,
                    .children = try args.toOwnedSlice(),
                };
            } else if (self.match(.lbracket)) {
                // Index
                const index = try self.parseExpr();
                _ = self.expect(.rbracket);
                left = .{
                    .kind = .index_expr,
                    .children = try self.allocSlice(&[_]Node{ left, index }),
                };
            } else if (self.match(.dot)) {
                // Field access
                const field = self.expect(.ident);
                left = .{
                    .kind = .index_expr,
                    .children = try self.allocSlice(&[_]Node{
                        left,
                        .{ .kind = .string_lit, .token = field },
                    }),
                };
            } else {
                break;
            }
        }
        return left;
    }

    fn parsePrimary(self: *Parser) !Node {
        if (self.check(.number)) {
            const tok = self.current();
            self.pos += 1;
            return .{ .kind = .number_lit, .token = tok, .value = tok.text(self.source) };
        }
        if (self.check(.string)) {
            const tok = self.current();
            self.pos += 1;
            return .{ .kind = .string_lit, .token = tok };
        }
        if (self.check(.ident)) {
            const tok = self.current();
            self.pos += 1;
            return .{ .kind = .identifier, .token = tok };
        }
        if (self.match(.kw_true)) {
            return .{ .kind = .bool_lit, .value = "true" };
        }
        if (self.match(.kw_false)) {
            return .{ .kind = .bool_lit, .value = "false" };
        }
        if (self.match(.kw_nil)) {
            return .{ .kind = .nil_lit };
        }
        if (self.match(.lbrace)) {
            // Table literal
            var entries = std.ArrayList(Node).init(self.alloc);
            while (!self.check(.rbrace) and !self.check(.eof)) {
                try entries.append(try self.parseExpr());
                _ = self.match(.comma);
                _ = self.match(.semicolon);
            }
            _ = self.expect(.rbrace);
            return .{ .kind = .table_lit, .children = try entries.toOwnedSlice() };
        }
        if (self.match(.lparen)) {
            const expr = try self.parseExpr();
            _ = self.expect(.rparen);
            return expr;
        }
        return .{ .kind = .nil_lit };
    }

    // Helpers
    fn allocSlice(self: *Parser, items: []const Node) ![]Node {
        const slice = try self.alloc.alloc(Node, items.len);
        @memcpy(slice, items);
        return slice;
    }

    fn current(self: *Parser) Token {
        return if (self.pos < self.tokens.len) self.tokens[self.pos] else .{ .kind = .eof, .start = 0, .end = 0 };
    }

    fn check(self: *Parser, kind: TokenKind) bool {
        return self.current().kind == kind;
    }

    fn checkAny(self: *Parser, kinds: []const TokenKind) bool {
        const k = self.current().kind;
        for (kinds) |kind| {
            if (k == kind) return true;
        }
        return false;
    }

    fn match(self: *Parser, kind: TokenKind) bool {
        if (self.check(kind)) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn expect(self: *Parser, kind: TokenKind) Token {
        if (self.check(kind)) {
            const tok = self.current();
            self.pos += 1;
            return tok;
        }
        return .{ .kind = .invalid, .start = 0, .end = 0 };
    }
};

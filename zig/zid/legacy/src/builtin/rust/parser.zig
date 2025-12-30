const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;
const TokenKind = lexer.TokenKind;

pub const NodeKind = enum {
    program,
    fn_decl,
    param,
    block,
    let_stmt,
    expr_stmt,
    return_stmt,
    if_expr,
    match_expr,
    match_arm,
    loop_expr,
    while_expr,
    for_expr,
    struct_decl,
    enum_decl,
    impl_block,
    trait_decl,
    field,
    variant,
    binary_expr,
    unary_expr,
    call_expr,
    method_call,
    field_access,
    index_expr,
    path_expr,
    struct_expr,
    tuple_expr,
    array_expr,
    range_expr,
    closure_expr,
    identifier,
    number_lit,
    string_lit,
    bool_lit,
    type_annotation,
    generic_params,
    lifetime,
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
        var items = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.eof)) {
            if (self.check(.kw_fn) or (self.check(.kw_pub) and self.peekNext(.kw_fn))) {
                try items.append(try self.parseFn());
            } else if (self.check(.kw_struct) or (self.check(.kw_pub) and self.peekNext(.kw_struct))) {
                try items.append(try self.parseStruct());
            } else if (self.check(.kw_enum) or (self.check(.kw_pub) and self.peekNext(.kw_enum))) {
                try items.append(try self.parseEnum());
            } else if (self.check(.kw_impl)) {
                try items.append(try self.parseImpl());
            } else if (self.check(.kw_trait) or (self.check(.kw_pub) and self.peekNext(.kw_trait))) {
                try items.append(try self.parseTrait());
            } else if (self.check(.kw_use)) {
                self.skipUntil(.semicolon);
            } else if (self.check(.kw_mod)) {
                self.skipUntil(.semicolon);
            } else {
                self.pos += 1;
            }
        }
        return .{ .kind = .program, .children = try items.toOwnedSlice() };
    }

    fn parseFn(self: *Parser) !Node {
        var is_pub = false;
        if (self.match(.kw_pub)) is_pub = true;
        _ = is_pub;

        _ = self.expect(.kw_fn);
        const name = self.expect(.ident);

        // Generic params
        var generics: ?Node = null;
        if (self.check(.lt)) {
            generics = try self.parseGenerics();
        }

        _ = self.expect(.lparen);
        var params = std.ArrayList(Node).init(self.alloc);

        // self param
        if (self.check(.ampersand) or self.check(.kw_mut) or self.check(.kw_self)) {
            try params.append(try self.parseSelfParam());
            _ = self.match(.comma);
        }

        while (!self.check(.rparen) and !self.check(.eof)) {
            try params.append(try self.parseParam());
            if (!self.match(.comma)) break;
        }
        _ = self.expect(.rparen);

        // Return type
        var ret_type: ?Node = null;
        if (self.match(.arrow)) {
            ret_type = try self.parseType();
        }

        // Where clause
        if (self.check(.kw_where)) {
            self.skipUntil(.lbrace);
        }

        // Body
        var body: ?Node = null;
        if (self.check(.lbrace)) {
            body = try self.parseBlock();
        } else {
            _ = self.match(.semicolon);
        }

        var children = std.ArrayList(Node).init(self.alloc);
        try children.appendSlice(try params.toOwnedSlice());
        if (generics) |g| try children.append(g);
        if (ret_type) |r| try children.append(r);
        if (body) |b| try children.append(b);

        return .{ .kind = .fn_decl, .token = name, .children = try children.toOwnedSlice() };
    }

    fn parseSelfParam(self: *Parser) !Node {
        const start = self.pos;
        if (self.match(.ampersand)) {
            _ = self.match(.lifetime);
            _ = self.match(.kw_mut);
        }
        _ = self.expect(.kw_self);
        return .{ .kind = .param, .token = self.tokens[start], .value = "self" };
    }

    fn parseParam(self: *Parser) !Node {
        _ = self.match(.kw_mut);
        const name = self.expect(.ident);
        _ = self.expect(.colon);
        const typ = try self.parseType();
        return .{ .kind = .param, .token = name, .children = try self.allocSlice(&[_]Node{typ}) };
    }

    fn parseType(self: *Parser) !Node {
        // Handle &, &mut, *const, *mut, impl, dyn, etc.
        if (self.match(.ampersand)) {
            _ = self.match(.lifetime);
            _ = self.match(.kw_mut);
            const inner = try self.parseType();
            return .{ .kind = .type_annotation, .value = "&", .children = try self.allocSlice(&[_]Node{inner}) };
        }
        if (self.match(.star)) {
            _ = self.match(.kw_const);
            _ = self.match(.kw_mut);
            const inner = try self.parseType();
            return .{ .kind = .type_annotation, .value = "*", .children = try self.allocSlice(&[_]Node{inner}) };
        }
        if (self.match(.kw_impl) or self.match(.kw_dyn)) {
            return try self.parseType();
        }
        if (self.check(.lbracket)) {
            return try self.parseArrayType();
        }
        if (self.check(.lparen)) {
            return try self.parseTupleType();
        }

        // Path type
        return try self.parsePath();
    }

    fn parseArrayType(self: *Parser) !Node {
        _ = self.expect(.lbracket);
        const elem = try self.parseType();
        var children = std.ArrayList(Node).init(self.alloc);
        try children.append(elem);
        if (self.match(.semicolon)) {
            try children.append(try self.parseExpr());
        }
        _ = self.expect(.rbracket);
        return .{ .kind = .type_annotation, .value = "[]", .children = try children.toOwnedSlice() };
    }

    fn parseTupleType(self: *Parser) !Node {
        _ = self.expect(.lparen);
        var types = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.rparen) and !self.check(.eof)) {
            try types.append(try self.parseType());
            if (!self.match(.comma)) break;
        }
        _ = self.expect(.rparen);
        return .{ .kind = .type_annotation, .value = "()", .children = try types.toOwnedSlice() };
    }

    fn parsePath(self: *Parser) !Node {
        var parts = std.ArrayList(Node).init(self.alloc);
        while (true) {
            if (self.check(.ident) or self.check(.kw_Self) or self.check(.kw_self) or self.check(.kw_super) or self.check(.kw_crate)) {
                const tok = self.current();
                self.pos += 1;
                try parts.append(.{ .kind = .identifier, .token = tok });
            } else {
                break;
            }

            // Generic args
            if (self.check(.lt)) {
                try parts.append(try self.parseGenericArgs());
            }

            if (!self.match(.coloncolon)) break;
        }
        if (parts.items.len == 1) {
            return parts.items[0];
        }
        return .{ .kind = .path_expr, .children = try parts.toOwnedSlice() };
    }

    fn parseGenerics(self: *Parser) !Node {
        _ = self.expect(.lt);
        var params = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.gt) and !self.check(.eof)) {
            if (self.check(.lifetime)) {
                try params.append(.{ .kind = .lifetime, .token = self.current() });
                self.pos += 1;
            } else if (self.check(.ident)) {
                try params.append(.{ .kind = .identifier, .token = self.current() });
                self.pos += 1;
            }
            // Skip bounds
            if (self.match(.colon)) {
                while (!self.check(.comma) and !self.check(.gt) and !self.check(.eof)) {
                    self.pos += 1;
                }
            }
            if (!self.match(.comma)) break;
        }
        _ = self.expect(.gt);
        return .{ .kind = .generic_params, .children = try params.toOwnedSlice() };
    }

    fn parseGenericArgs(self: *Parser) !Node {
        _ = self.expect(.lt);
        var args = std.ArrayList(Node).init(self.alloc);
        var depth: u32 = 1;
        while (depth > 0 and !self.check(.eof)) {
            if (self.check(.lt)) depth += 1;
            if (self.check(.gt)) {
                depth -= 1;
                if (depth == 0) break;
            }
            if (self.check(.ident) or self.check(.lifetime)) {
                try args.append(.{ .kind = .identifier, .token = self.current() });
            }
            self.pos += 1;
        }
        _ = self.expect(.gt);
        return .{ .kind = .generic_params, .children = try args.toOwnedSlice() };
    }

    fn parseBlock(self: *Parser) !Node {
        _ = self.expect(.lbrace);
        var stmts = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.rbrace) and !self.check(.eof)) {
            if (self.check(.kw_let)) {
                try stmts.append(try self.parseLet());
            } else if (self.check(.kw_return)) {
                try stmts.append(try self.parseReturn());
            } else if (self.check(.kw_if)) {
                try stmts.append(try self.parseIf());
            } else if (self.check(.kw_match)) {
                try stmts.append(try self.parseMatch());
            } else if (self.check(.kw_loop)) {
                try stmts.append(try self.parseLoop());
            } else if (self.check(.kw_while)) {
                try stmts.append(try self.parseWhile());
            } else if (self.check(.kw_for)) {
                try stmts.append(try self.parseFor());
            } else {
                const expr = try self.parseExpr();
                if (self.match(.semicolon)) {
                    try stmts.append(.{ .kind = .expr_stmt, .children = try self.allocSlice(&[_]Node{expr}) });
                } else {
                    try stmts.append(expr);
                }
            }
        }
        _ = self.expect(.rbrace);
        return .{ .kind = .block, .children = try stmts.toOwnedSlice() };
    }

    fn parseLet(self: *Parser) !Node {
        _ = self.expect(.kw_let);
        const is_mut = self.match(.kw_mut);
        _ = is_mut;
        const name = self.expect(.ident);

        var typ: ?Node = null;
        if (self.match(.colon)) {
            typ = try self.parseType();
        }

        var value: ?Node = null;
        if (self.match(.eq)) {
            value = try self.parseExpr();
        }

        _ = self.match(.semicolon);

        var children = std.ArrayList(Node).init(self.alloc);
        if (typ) |t| try children.append(t);
        if (value) |v| try children.append(v);

        return .{ .kind = .let_stmt, .token = name, .children = try children.toOwnedSlice() };
    }

    fn parseReturn(self: *Parser) !Node {
        _ = self.expect(.kw_return);
        if (self.check(.semicolon) or self.check(.rbrace)) {
            _ = self.match(.semicolon);
            return .{ .kind = .return_stmt };
        }
        const expr = try self.parseExpr();
        _ = self.match(.semicolon);
        return .{ .kind = .return_stmt, .children = try self.allocSlice(&[_]Node{expr}) };
    }

    fn parseIf(self: *Parser) !Node {
        _ = self.expect(.kw_if);
        const cond = try self.parseExpr();
        const then_block = try self.parseBlock();

        var children = std.ArrayList(Node).init(self.alloc);
        try children.append(cond);
        try children.append(then_block);

        if (self.match(.kw_else)) {
            if (self.check(.kw_if)) {
                try children.append(try self.parseIf());
            } else {
                try children.append(try self.parseBlock());
            }
        }

        return .{ .kind = .if_expr, .children = try children.toOwnedSlice() };
    }

    fn parseMatch(self: *Parser) !Node {
        _ = self.expect(.kw_match);
        const scrutinee = try self.parseExpr();
        _ = self.expect(.lbrace);

        var arms = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.rbrace) and !self.check(.eof)) {
            try arms.append(try self.parseMatchArm());
        }
        _ = self.expect(.rbrace);

        var children = std.ArrayList(Node).init(self.alloc);
        try children.append(scrutinee);
        try children.appendSlice(try arms.toOwnedSlice());

        return .{ .kind = .match_expr, .children = try children.toOwnedSlice() };
    }

    fn parseMatchArm(self: *Parser) !Node {
        // Simple pattern parsing
        const pattern = try self.parseExpr();
        _ = self.expect(.fat_arrow);
        const body = try self.parseExpr();
        _ = self.match(.comma);
        return .{ .kind = .match_arm, .children = try self.allocSlice(&[_]Node{ pattern, body }) };
    }

    fn parseLoop(self: *Parser) !Node {
        _ = self.expect(.kw_loop);
        const body = try self.parseBlock();
        return .{ .kind = .loop_expr, .children = try self.allocSlice(&[_]Node{body}) };
    }

    fn parseWhile(self: *Parser) !Node {
        _ = self.expect(.kw_while);
        const cond = try self.parseExpr();
        const body = try self.parseBlock();
        return .{ .kind = .while_expr, .children = try self.allocSlice(&[_]Node{ cond, body }) };
    }

    fn parseFor(self: *Parser) !Node {
        _ = self.expect(.kw_for);
        const pat = self.expect(.ident);
        _ = self.expect(.kw_in);
        const iter = try self.parseExpr();
        const body = try self.parseBlock();
        return .{
            .kind = .for_expr,
            .token = pat,
            .children = try self.allocSlice(&[_]Node{ iter, body }),
        };
    }

    fn parseStruct(self: *Parser) !Node {
        _ = self.match(.kw_pub);
        _ = self.expect(.kw_struct);
        const name = self.expect(.ident);

        var generics: ?Node = null;
        if (self.check(.lt)) {
            generics = try self.parseGenerics();
        }

        var fields = std.ArrayList(Node).init(self.alloc);
        if (self.match(.lbrace)) {
            while (!self.check(.rbrace) and !self.check(.eof)) {
                _ = self.match(.kw_pub);
                const field_name = self.expect(.ident);
                _ = self.expect(.colon);
                const field_type = try self.parseType();
                try fields.append(.{
                    .kind = .field,
                    .token = field_name,
                    .children = try self.allocSlice(&[_]Node{field_type}),
                });
                _ = self.match(.comma);
            }
            _ = self.expect(.rbrace);
        } else if (self.match(.lparen)) {
            // Tuple struct
            while (!self.check(.rparen) and !self.check(.eof)) {
                _ = self.match(.kw_pub);
                const field_type = try self.parseType();
                try fields.append(.{ .kind = .field, .children = try self.allocSlice(&[_]Node{field_type}) });
                _ = self.match(.comma);
            }
            _ = self.expect(.rparen);
            _ = self.match(.semicolon);
        } else {
            _ = self.match(.semicolon);
        }

        var children = std.ArrayList(Node).init(self.alloc);
        if (generics) |g| try children.append(g);
        try children.appendSlice(try fields.toOwnedSlice());

        return .{ .kind = .struct_decl, .token = name, .children = try children.toOwnedSlice() };
    }

    fn parseEnum(self: *Parser) !Node {
        _ = self.match(.kw_pub);
        _ = self.expect(.kw_enum);
        const name = self.expect(.ident);

        var generics: ?Node = null;
        if (self.check(.lt)) {
            generics = try self.parseGenerics();
        }

        var variants = std.ArrayList(Node).init(self.alloc);
        _ = self.expect(.lbrace);
        while (!self.check(.rbrace) and !self.check(.eof)) {
            const variant_name = self.expect(.ident);
            var variant_fields = std.ArrayList(Node).init(self.alloc);

            if (self.match(.lparen)) {
                while (!self.check(.rparen) and !self.check(.eof)) {
                    try variant_fields.append(try self.parseType());
                    _ = self.match(.comma);
                }
                _ = self.expect(.rparen);
            } else if (self.match(.lbrace)) {
                while (!self.check(.rbrace) and !self.check(.eof)) {
                    const fname = self.expect(.ident);
                    _ = self.expect(.colon);
                    const ftype = try self.parseType();
                    try variant_fields.append(.{
                        .kind = .field,
                        .token = fname,
                        .children = try self.allocSlice(&[_]Node{ftype}),
                    });
                    _ = self.match(.comma);
                }
                _ = self.expect(.rbrace);
            }

            try variants.append(.{
                .kind = .variant,
                .token = variant_name,
                .children = try variant_fields.toOwnedSlice(),
            });
            _ = self.match(.comma);
        }
        _ = self.expect(.rbrace);

        var children = std.ArrayList(Node).init(self.alloc);
        if (generics) |g| try children.append(g);
        try children.appendSlice(try variants.toOwnedSlice());

        return .{ .kind = .enum_decl, .token = name, .children = try children.toOwnedSlice() };
    }

    fn parseImpl(self: *Parser) !Node {
        _ = self.expect(.kw_impl);

        var generics: ?Node = null;
        if (self.check(.lt)) {
            generics = try self.parseGenerics();
        }

        const typ = try self.parseType();

        // Skip trait impl "for Type"
        if (self.match(.kw_for)) {
            _ = try self.parseType();
        }

        // Where clause
        if (self.check(.kw_where)) {
            self.skipUntil(.lbrace);
        }

        _ = self.expect(.lbrace);
        var items = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.rbrace) and !self.check(.eof)) {
            if (self.check(.kw_fn) or (self.check(.kw_pub) and self.peekNext(.kw_fn))) {
                try items.append(try self.parseFn());
            } else if (self.check(.kw_type)) {
                self.skipUntil(.semicolon);
            } else if (self.check(.kw_const)) {
                self.skipUntil(.semicolon);
            } else {
                self.pos += 1;
            }
        }
        _ = self.expect(.rbrace);

        var children = std.ArrayList(Node).init(self.alloc);
        try children.append(typ);
        if (generics) |g| try children.append(g);
        try children.appendSlice(try items.toOwnedSlice());

        return .{ .kind = .impl_block, .children = try children.toOwnedSlice() };
    }

    fn parseTrait(self: *Parser) !Node {
        _ = self.match(.kw_pub);
        _ = self.expect(.kw_trait);
        const name = self.expect(.ident);

        var generics: ?Node = null;
        if (self.check(.lt)) {
            generics = try self.parseGenerics();
        }

        // Skip bounds
        if (self.match(.colon)) {
            while (!self.check(.lbrace) and !self.check(.eof)) {
                self.pos += 1;
            }
        }

        _ = self.expect(.lbrace);
        var items = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.rbrace) and !self.check(.eof)) {
            if (self.check(.kw_fn)) {
                try items.append(try self.parseFn());
            } else if (self.check(.kw_type)) {
                self.skipUntil(.semicolon);
            } else {
                self.pos += 1;
            }
        }
        _ = self.expect(.rbrace);

        var children = std.ArrayList(Node).init(self.alloc);
        if (generics) |g| try children.append(g);
        try children.appendSlice(try items.toOwnedSlice());

        return .{ .kind = .trait_decl, .token = name, .children = try children.toOwnedSlice() };
    }

    fn parseExpr(self: *Parser) !Node {
        return self.parseAssign();
    }

    fn parseAssign(self: *Parser) !Node {
        var left = try self.parseOr();
        if (self.checkAny(&.{ .eq, .pluseq, .minuseq, .stareq, .slasheq })) {
            const op = self.current();
            self.pos += 1;
            const right = try self.parseAssign();
            left = .{ .kind = .binary_expr, .token = op, .children = try self.allocSlice(&[_]Node{ left, right }) };
        }
        return left;
    }

    fn parseOr(self: *Parser) !Node {
        var left = try self.parseAnd();
        while (self.match(.pipepipe)) {
            const op = self.tokens[self.pos - 1];
            const right = try self.parseAnd();
            left = .{ .kind = .binary_expr, .token = op, .children = try self.allocSlice(&[_]Node{ left, right }) };
        }
        return left;
    }

    fn parseAnd(self: *Parser) !Node {
        var left = try self.parseComparison();
        while (self.match(.ampamp)) {
            const op = self.tokens[self.pos - 1];
            const right = try self.parseComparison();
            left = .{ .kind = .binary_expr, .token = op, .children = try self.allocSlice(&[_]Node{ left, right }) };
        }
        return left;
    }

    fn parseComparison(self: *Parser) !Node {
        var left = try self.parseAddSub();
        while (self.checkAny(&.{ .eqeq, .neq, .lt, .gt, .lte, .gte })) {
            const op = self.current();
            self.pos += 1;
            const right = try self.parseAddSub();
            left = .{ .kind = .binary_expr, .token = op, .children = try self.allocSlice(&[_]Node{ left, right }) };
        }
        return left;
    }

    fn parseAddSub(self: *Parser) !Node {
        var left = try self.parseMulDiv();
        while (self.checkAny(&.{ .plus, .minus })) {
            const op = self.current();
            self.pos += 1;
            const right = try self.parseMulDiv();
            left = .{ .kind = .binary_expr, .token = op, .children = try self.allocSlice(&[_]Node{ left, right }) };
        }
        return left;
    }

    fn parseMulDiv(self: *Parser) !Node {
        var left = try self.parseUnary();
        while (self.checkAny(&.{ .star, .slash, .percent })) {
            const op = self.current();
            self.pos += 1;
            const right = try self.parseUnary();
            left = .{ .kind = .binary_expr, .token = op, .children = try self.allocSlice(&[_]Node{ left, right }) };
        }
        return left;
    }

    fn parseUnary(self: *Parser) !Node {
        if (self.checkAny(&.{ .minus, .bang, .star, .ampersand })) {
            const op = self.current();
            self.pos += 1;
            _ = self.match(.kw_mut);
            const operand = try self.parseUnary();
            return .{ .kind = .unary_expr, .token = op, .children = try self.allocSlice(&[_]Node{operand}) };
        }
        return self.parsePostfix();
    }

    fn parsePostfix(self: *Parser) !Node {
        var left = try self.parsePrimary();
        while (true) {
            if (self.match(.lparen)) {
                var args = std.ArrayList(Node).init(self.alloc);
                while (!self.check(.rparen) and !self.check(.eof)) {
                    try args.append(try self.parseExpr());
                    if (!self.match(.comma)) break;
                }
                _ = self.expect(.rparen);
                left = .{ .kind = .call_expr, .token = left.token, .children = try args.toOwnedSlice() };
            } else if (self.match(.dot)) {
                const field = self.expect(.ident);
                if (self.check(.lparen)) {
                    // Method call
                    _ = self.expect(.lparen);
                    var args = std.ArrayList(Node).init(self.alloc);
                    try args.append(left);
                    while (!self.check(.rparen) and !self.check(.eof)) {
                        try args.append(try self.parseExpr());
                        if (!self.match(.comma)) break;
                    }
                    _ = self.expect(.rparen);
                    left = .{ .kind = .method_call, .token = field, .children = try args.toOwnedSlice() };
                } else {
                    left = .{ .kind = .field_access, .token = field, .children = try self.allocSlice(&[_]Node{left}) };
                }
            } else if (self.match(.lbracket)) {
                const index = try self.parseExpr();
                _ = self.expect(.rbracket);
                left = .{ .kind = .index_expr, .children = try self.allocSlice(&[_]Node{ left, index }) };
            } else if (self.match(.question)) {
                left = .{ .kind = .unary_expr, .value = "?", .children = try self.allocSlice(&[_]Node{left}) };
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
        if (self.match(.kw_true)) return .{ .kind = .bool_lit, .value = "true" };
        if (self.match(.kw_false)) return .{ .kind = .bool_lit, .value = "false" };
        if (self.check(.ident) or self.check(.kw_Self) or self.check(.kw_self)) {
            return try self.parsePath();
        }
        if (self.match(.lparen)) {
            if (self.check(.rparen)) {
                _ = self.expect(.rparen);
                return .{ .kind = .tuple_expr };
            }
            const expr = try self.parseExpr();
            if (self.match(.comma)) {
                var items = std.ArrayList(Node).init(self.alloc);
                try items.append(expr);
                while (!self.check(.rparen) and !self.check(.eof)) {
                    try items.append(try self.parseExpr());
                    if (!self.match(.comma)) break;
                }
                _ = self.expect(.rparen);
                return .{ .kind = .tuple_expr, .children = try items.toOwnedSlice() };
            }
            _ = self.expect(.rparen);
            return expr;
        }
        if (self.match(.lbracket)) {
            var items = std.ArrayList(Node).init(self.alloc);
            while (!self.check(.rbracket) and !self.check(.eof)) {
                try items.append(try self.parseExpr());
                if (!self.match(.comma)) break;
            }
            _ = self.expect(.rbracket);
            return .{ .kind = .array_expr, .children = try items.toOwnedSlice() };
        }
        if (self.check(.lbrace)) {
            return try self.parseBlock();
        }
        if (self.check(.pipe)) {
            return try self.parseClosure();
        }

        return .{ .kind = .identifier };
    }

    fn parseClosure(self: *Parser) !Node {
        _ = self.expect(.pipe);
        var params = std.ArrayList(Node).init(self.alloc);
        while (!self.check(.pipe) and !self.check(.eof)) {
            const name = self.expect(.ident);
            var typ: ?Node = null;
            if (self.match(.colon)) {
                typ = try self.parseType();
            }
            var children = std.ArrayList(Node).init(self.alloc);
            if (typ) |t| try children.append(t);
            try params.append(.{ .kind = .param, .token = name, .children = try children.toOwnedSlice() });
            if (!self.match(.comma)) break;
        }
        _ = self.expect(.pipe);

        var ret_type: ?Node = null;
        if (self.match(.arrow)) {
            ret_type = try self.parseType();
        }

        const body = try self.parseExpr();

        var children = std.ArrayList(Node).init(self.alloc);
        try children.appendSlice(try params.toOwnedSlice());
        if (ret_type) |r| try children.append(r);
        try children.append(body);

        return .{ .kind = .closure_expr, .children = try children.toOwnedSlice() };
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

    fn check(self: *Parser, kind: TokenKind) bool { return self.current().kind == kind; }

    fn checkAny(self: *Parser, kinds: []const TokenKind) bool {
        const k = self.current().kind;
        for (kinds) |kind| {
            if (k == kind) return true;
        }
        return false;
    }

    fn peekNext(self: *Parser, kind: TokenKind) bool {
        if (self.pos + 1 < self.tokens.len) {
            return self.tokens[self.pos + 1].kind == kind;
        }
        return false;
    }

    fn match(self: *Parser, kind: TokenKind) bool {
        if (self.check(kind)) { self.pos += 1; return true; }
        return false;
    }

    fn expect(self: *Parser, kind: TokenKind) Token {
        if (self.check(kind)) { const tok = self.current(); self.pos += 1; return tok; }
        return .{ .kind = .invalid, .start = 0, .end = 0 };
    }

    fn skipUntil(self: *Parser, kind: TokenKind) void {
        while (!self.check(kind) and !self.check(.eof)) {
            self.pos += 1;
        }
        _ = self.match(kind);
    }
};

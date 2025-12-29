// Engine: código fijo que procesa templates

const std = @import("std");
const t = @import("templates.zig");

// ============ LEXER ============

pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,

    pub fn next(self: *Lexer) t.Token {
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            return .{ .kind = .eof, .start = self.pos, .end = self.pos };
        }

        const start = self.pos;
        const c = self.source[self.pos];

        // Operators / delimiters
        inline for (t.operators) |op| {
            if (self.match(op[0])) {
                return .{ .kind = op[1], .start = start, .end = self.pos };
            }
        }

        // Number
        if (isDigit(c)) {
            while (self.pos < self.source.len and isDigit(self.source[self.pos])) {
                self.pos += 1;
            }
            return .{ .kind = .number, .start = start, .end = self.pos };
        }

        // Identifier / keyword
        if (isAlpha(c)) {
            while (self.pos < self.source.len and isAlphaNum(self.source[self.pos])) {
                self.pos += 1;
            }
            const text = self.source[start..self.pos];

            // Check keywords
            inline for (t.keywords) |kw| {
                if (std.mem.eql(u8, text, kw[0])) {
                    return .{ .kind = kw[1], .start = start, .end = self.pos };
                }
            }

            return .{ .kind = .ident, .start = start, .end = self.pos };
        }

        self.pos += 1;
        return .{ .kind = .invalid, .start = start, .end = self.pos };
    }

    fn match(self: *Lexer, pattern: []const u8) bool {
        if (self.pos + pattern.len > self.source.len) return false;
        if (std.mem.eql(u8, self.source[self.pos .. self.pos + pattern.len], pattern)) {
            self.pos += @intCast(pattern.len);
            return true;
        }
        return false;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else if (c == '-' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '-') {
                // Comment: skip to end of line
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isAlphaNum(c: u8) bool {
        return isAlpha(c) or isDigit(c);
    }
};

// ============ PARSER ============

pub const Parser = struct {
    tokens: []t.Token,
    source: []const u8,
    pos: usize = 0,
    allocator: std.mem.Allocator,

    pub fn parse(self: *Parser) !t.Node {
        var funcs = std.ArrayList(t.Node).init(self.allocator);

        while (!self.check(.eof)) {
            if (self.check(.kw_function)) {
                try funcs.append(try self.parseFunction());
            } else {
                self.pos += 1; // skip unknown
            }
        }

        return .{
            .kind = .program,
            .children = try funcs.toOwnedSlice(),
        };
    }

    fn parseFunction(self: *Parser) !t.Node {
        _ = self.expect(.kw_function);
        const name = self.expect(.ident);

        _ = self.expect(.lparen);
        var params = std.ArrayList(t.Node).init(self.allocator);
        while (!self.check(.rparen)) {
            try params.append(.{
                .kind = .param,
                .token = self.expect(.ident),
            });
            if (!self.match(.comma)) break;
        }
        _ = self.expect(.rparen);

        const body = try self.parseBlock();

        _ = self.expect(.kw_end);

        var children = std.ArrayList(t.Node).init(self.allocator);
        try children.appendSlice(try params.toOwnedSlice());
        try children.append(body);

        return .{
            .kind = .func_decl,
            .token = name,
            .children = try children.toOwnedSlice(),
        };
    }

    fn parseBlock(self: *Parser) !t.Node {
        var stmts = std.ArrayList(t.Node).init(self.allocator);

        while (!self.check(.kw_end) and !self.check(.kw_else) and !self.check(.eof)) {
            if (self.check(.kw_return)) {
                try stmts.append(try self.parseReturn());
            } else if (self.check(.kw_local)) {
                try stmts.append(try self.parseLocal());
            } else if (self.check(.kw_if)) {
                try stmts.append(try self.parseIf());
            } else {
                break;
            }
        }

        return .{
            .kind = .block,
            .children = try stmts.toOwnedSlice(),
        };
    }

    fn parseReturn(self: *Parser) !t.Node {
        _ = self.expect(.kw_return);
        return .{
            .kind = .return_stmt,
            .children = &.{try self.parseExpr()},
        };
    }

    fn parseLocal(self: *Parser) !t.Node {
        _ = self.expect(.kw_local);
        const name = self.expect(.ident);
        _ = self.expect(.eq);
        return .{
            .kind = .local_decl,
            .token = name,
            .children = &.{try self.parseExpr()},
        };
    }

    fn parseIf(self: *Parser) !t.Node {
        _ = self.expect(.kw_if);
        const cond = try self.parseExpr();
        _ = self.expect(.kw_then);
        const then_block = try self.parseBlock();

        var children = std.ArrayList(t.Node).init(self.allocator);
        try children.append(cond);
        try children.append(then_block);

        if (self.match(.kw_else)) {
            try children.append(try self.parseBlock());
        }

        return .{
            .kind = .if_stmt,
            .children = try children.toOwnedSlice(),
        };
    }

    fn parseExpr(self: *Parser) !t.Node {
        var left = try self.parsePrimary();

        while (self.checkOp()) {
            const op = self.current();
            self.pos += 1;
            const right = try self.parsePrimary();
            left = .{
                .kind = .binary_expr,
                .token = op,
                .children = &.{ left, right },
            };
        }

        return left;
    }

    fn parsePrimary(self: *Parser) !t.Node {
        if (self.check(.number)) {
            const tok = self.current();
            self.pos += 1;
            return .{
                .kind = .number_lit,
                .token = tok,
                .value = tok.text(self.source),
            };
        }

        if (self.check(.ident)) {
            const tok = self.current();
            self.pos += 1;

            // Function call?
            if (self.match(.lparen)) {
                var args = std.ArrayList(t.Node).init(self.allocator);
                while (!self.check(.rparen)) {
                    try args.append(try self.parseExpr());
                    if (!self.match(.comma)) break;
                }
                _ = self.expect(.rparen);
                return .{
                    .kind = .call_expr,
                    .token = tok,
                    .children = try args.toOwnedSlice(),
                };
            }

            return .{
                .kind = .identifier,
                .token = tok,
            };
        }

        if (self.match(.lparen)) {
            const expr = try self.parseExpr();
            _ = self.expect(.rparen);
            return expr;
        }

        return .{ .kind = .number_lit, .value = "0" };
    }

    fn current(self: *Parser) t.Token {
        if (self.pos >= self.tokens.len) return .{ .kind = .eof, .start = 0, .end = 0 };
        return self.tokens[self.pos];
    }

    fn check(self: *Parser, kind: t.TokenKind) bool {
        return self.current().kind == kind;
    }

    fn checkOp(self: *Parser) bool {
        const k = self.current().kind;
        return k == .plus or k == .minus or k == .star or k == .slash or k == .lt or k == .gt;
    }

    fn match(self: *Parser, kind: t.TokenKind) bool {
        if (self.check(kind)) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn expect(self: *Parser, kind: t.TokenKind) t.Token {
        if (self.check(kind)) {
            const tok = self.current();
            self.pos += 1;
            return tok;
        }
        return .{ .kind = .invalid, .start = 0, .end = 0 };
    }
};

// ============ EMITTER (WAT) ============

pub const Emitter = struct {
    output: std.ArrayList(u8),
    indent: u32 = 0,
    source: []const u8,
    locals: std.StringHashMap(u32),
    local_count: u32 = 0,
    allocator: std.mem.Allocator,

    pub fn emit(self: *Emitter, node: t.Node) ![]const u8 {
        try self.emitNode(node);
        return self.output.items;
    }

    fn emitNode(self: *Emitter, node: t.Node) !void {
        switch (node.kind) {
            .program => {
                try self.write("(module\n");
                self.indent += 1;
                for (node.children) |child| {
                    try self.emitNode(child);
                }
                self.indent -= 1;
                try self.write(")\n");
            },

            .func_decl => {
                const name = node.token.?.text(self.source);
                self.locals.clearRetainingCapacity();
                self.local_count = 0;

                try self.writeIndent();
                try self.write("(func $");
                try self.write(name);

                // Params
                var param_count: u32 = 0;
                for (node.children) |child| {
                    if (child.kind == .param) {
                        const pname = child.token.?.text(self.source);
                        try self.write(" (param $");
                        try self.write(pname);
                        try self.write(" i32)");
                        try self.locals.put(pname, param_count);
                        param_count += 1;
                    }
                }
                self.local_count = param_count;

                try self.write(" (result i32)\n");
                self.indent += 1;

                // Body
                for (node.children) |child| {
                    if (child.kind == .block) {
                        for (child.children) |stmt| {
                            try self.emitNode(stmt);
                        }
                    }
                }

                self.indent -= 1;
                try self.writeIndent();
                try self.write(")\n");

                // Export
                try self.writeIndent();
                try self.write("(export \"");
                try self.write(name);
                try self.write("\" (func $");
                try self.write(name);
                try self.write("))\n");
            },

            .return_stmt => {
                for (node.children) |child| {
                    try self.emitNode(child);
                }
            },

            .local_decl => {
                const name = node.token.?.text(self.source);
                try self.locals.put(name, self.local_count);
                self.local_count += 1;

                // Emit value
                for (node.children) |child| {
                    try self.emitNode(child);
                }

                try self.writeIndent();
                try self.write("local.set $");
                try self.write(name);
                try self.write("\n");
            },

            .if_stmt => {
                // Condition
                try self.emitNode(node.children[0]);

                try self.writeIndent();
                try self.write("(if (result i32)\n");
                self.indent += 1;

                // Then
                try self.writeIndent();
                try self.write("(then\n");
                self.indent += 1;
                for (node.children[1].children) |stmt| {
                    try self.emitNode(stmt);
                }
                self.indent -= 1;
                try self.writeIndent();
                try self.write(")\n");

                // Else
                try self.writeIndent();
                try self.write("(else\n");
                self.indent += 1;
                if (node.children.len > 2) {
                    for (node.children[2].children) |stmt| {
                        try self.emitNode(stmt);
                    }
                } else {
                    try self.writeIndent();
                    try self.write("i32.const 0\n");
                }
                self.indent -= 1;
                try self.writeIndent();
                try self.write(")\n");

                self.indent -= 1;
                try self.writeIndent();
                try self.write(")\n");
            },

            .binary_expr => {
                // Left
                try self.emitNode(node.children[0]);
                // Right
                try self.emitNode(node.children[1]);

                // Operator
                const op = node.token.?.kind;
                try self.writeIndent();
                switch (op) {
                    .plus => try self.write("i32.add\n"),
                    .minus => try self.write("i32.sub\n"),
                    .star => try self.write("i32.mul\n"),
                    .slash => try self.write("i32.div_s\n"),
                    .lt => try self.write("i32.lt_s\n"),
                    .gt => try self.write("i32.gt_s\n"),
                    else => {},
                }
            },

            .call_expr => {
                // Args
                for (node.children) |arg| {
                    try self.emitNode(arg);
                }

                const name = node.token.?.text(self.source);
                try self.writeIndent();
                try self.write("call $");
                try self.write(name);
                try self.write("\n");
            },

            .identifier => {
                const name = node.token.?.text(self.source);
                try self.writeIndent();
                try self.write("local.get $");
                try self.write(name);
                try self.write("\n");
            },

            .number_lit => {
                try self.writeIndent();
                try self.write("i32.const ");
                try self.write(node.value orelse "0");
                try self.write("\n");
            },

            else => {},
        }
    }

    fn write(self: *Emitter, str: []const u8) !void {
        try self.output.appendSlice(str);
    }

    fn writeIndent(self: *Emitter) !void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) {
            try self.output.appendSlice("  ");
        }
    }
};

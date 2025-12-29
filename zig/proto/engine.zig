// Engine simplificado con op helper

const std = @import("std");
const t = @import("templates.zig");

// ============ LEXER ============

pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,

    pub fn next(self: *Lexer) t.Token {
        self.skipWhitespace();
        if (self.pos >= self.source.len) return .{ .kind = .eof, .start = self.pos, .end = self.pos };

        const start = self.pos;
        const c = self.source[self.pos];

        inline for (t.operators) |op| {
            if (self.match(op[0])) return .{ .kind = op[1], .start = start, .end = self.pos };
        }

        if (isDigit(c)) {
            while (self.pos < self.source.len and isDigit(self.source[self.pos])) self.pos += 1;
            return .{ .kind = .number, .start = start, .end = self.pos };
        }

        if (isAlpha(c)) {
            while (self.pos < self.source.len and isAlphaNum(self.source[self.pos])) self.pos += 1;
            const text = self.source[start..self.pos];
            inline for (t.keywords) |kw| {
                if (std.mem.eql(u8, text, kw[0])) return .{ .kind = kw[1], .start = start, .end = self.pos };
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
            const ch = self.source[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                self.pos += 1;
            } else if (ch == '-' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '-') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
            } else break;
        }
    }

    fn isDigit(c: u8) bool { return c >= '0' and c <= '9'; }
    fn isAlpha(c: u8) bool { return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'; }
    fn isAlphaNum(c: u8) bool { return isAlpha(c) or isDigit(c); }
};

// ============ PARSER ============

pub const Parser = struct {
    tokens: []t.Token,
    source: []const u8,
    pos: usize = 0,
    alloc: std.mem.Allocator,

    pub fn parse(self: *Parser) !t.Node {
        var funcs = std.ArrayList(t.Node).init(self.alloc);
        while (!self.check(.eof)) {
            if (self.check(.kw_function)) try funcs.append(try self.parseFunction())
            else self.pos += 1;
        }
        return .{ .kind = .program, .children = try funcs.toOwnedSlice() };
    }

    fn parseFunction(self: *Parser) !t.Node {
        _ = self.expect(.kw_function);
        const name = self.expect(.ident);
        _ = self.expect(.lparen);

        var params = std.ArrayList(t.Node).init(self.alloc);
        while (!self.check(.rparen)) {
            try params.append(.{ .kind = .param, .token = self.expect(.ident) });
            if (!self.match(.comma)) break;
        }
        _ = self.expect(.rparen);

        const body = try self.parseBlock();
        _ = self.expect(.kw_end);

        var children = std.ArrayList(t.Node).init(self.alloc);
        try children.appendSlice(try params.toOwnedSlice());
        try children.append(body);
        return .{ .kind = .func_decl, .token = name, .children = try children.toOwnedSlice() };
    }

    fn parseBlock(self: *Parser) !t.Node {
        var stmts = std.ArrayList(t.Node).init(self.alloc);
        while (!self.check(.kw_end) and !self.check(.kw_else) and !self.check(.eof)) {
            if (self.check(.kw_return)) try stmts.append(try self.parseReturn())
            else if (self.check(.kw_local)) try stmts.append(try self.parseLocal())
            else if (self.check(.kw_if)) try stmts.append(try self.parseIf())
            else if (self.check(.kw_while)) try stmts.append(try self.parseWhile())
            else break;
        }
        return .{ .kind = .block, .children = try stmts.toOwnedSlice() };
    }

    fn parseReturn(self: *Parser) !t.Node {
        _ = self.expect(.kw_return);
        return .{ .kind = .return_stmt, .children = try self.allocSlice(&[_]t.Node{try self.parseExpr()}) };
    }

    fn parseLocal(self: *Parser) !t.Node {
        _ = self.expect(.kw_local);
        const name = self.expect(.ident);
        _ = self.expect(.eq);
        return .{ .kind = .local_decl, .token = name, .children = try self.allocSlice(&[_]t.Node{try self.parseExpr()}) };
    }

    fn parseIf(self: *Parser) !t.Node {
        _ = self.expect(.kw_if);
        const cond = try self.parseExpr();
        _ = self.expect(.kw_then);
        const then_block = try self.parseBlock();

        var children = std.ArrayList(t.Node).init(self.alloc);
        try children.append(cond);
        try children.append(then_block);
        if (self.match(.kw_else)) try children.append(try self.parseBlock());
        return .{ .kind = .if_stmt, .children = try children.toOwnedSlice() };
    }

    fn parseWhile(self: *Parser) !t.Node {
        _ = self.expect(.kw_while);
        const cond = try self.parseExpr();
        _ = self.expect(.kw_do);
        const body = try self.parseBlock();
        _ = self.expect(.kw_end);
        return .{ .kind = .while_stmt, .children = try self.allocSlice(&[_]t.Node{ cond, body }) };
    }

    fn parseExpr(self: *Parser) !t.Node {
        var left = try self.parsePrimary();
        while (self.checkOp()) {
            const op = self.current();
            self.pos += 1;
            var children = try self.alloc.alloc(t.Node, 2);
            children[0] = left;
            children[1] = try self.parsePrimary();
            left = .{ .kind = .binary_expr, .token = op, .children = children };
        }
        return left;
    }

    fn parsePrimary(self: *Parser) !t.Node {
        if (self.check(.number)) {
            const tok = self.current();
            self.pos += 1;
            return .{ .kind = .number_lit, .token = tok, .value = tok.text(self.source) };
        }
        if (self.check(.ident)) {
            const tok = self.current();
            self.pos += 1;
            if (self.match(.lparen)) {
                var args = std.ArrayList(t.Node).init(self.alloc);
                while (!self.check(.rparen)) {
                    try args.append(try self.parseExpr());
                    if (!self.match(.comma)) break;
                }
                _ = self.expect(.rparen);
                return .{ .kind = .call_expr, .token = tok, .children = try args.toOwnedSlice() };
            }
            return .{ .kind = .identifier, .token = tok };
        }
        if (self.match(.lparen)) {
            const expr = try self.parseExpr();
            _ = self.expect(.rparen);
            return expr;
        }
        return .{ .kind = .number_lit, .value = "0" };
    }

    fn allocSlice(self: *Parser, items: []const t.Node) ![]t.Node {
        var slice = try self.alloc.alloc(t.Node, items.len);
        @memcpy(slice, items);
        return slice;
    }

    fn current(self: *Parser) t.Token {
        return if (self.pos < self.tokens.len) self.tokens[self.pos] else .{ .kind = .eof, .start = 0, .end = 0 };
    }
    fn check(self: *Parser, kind: t.TokenKind) bool { return self.current().kind == kind; }
    fn checkOp(self: *Parser) bool {
        const k = self.current().kind;
        return k == .plus or k == .minus or k == .star or k == .slash or k == .lt or k == .gt;
    }
    fn match(self: *Parser, kind: t.TokenKind) bool {
        if (self.check(kind)) { self.pos += 1; return true; }
        return false;
    }
    fn expect(self: *Parser, kind: t.TokenKind) t.Token {
        if (self.check(kind)) { const tok = self.current(); self.pos += 1; return tok; }
        return .{ .kind = .invalid, .start = 0, .end = 0 };
    }
};

// ============ OP HELPER ============

pub const Op = struct {
    out: *std.ArrayList(u8),
    indent: u32 = 0,

    // Core print
    pub fn p(self: *Op, comptime fmt: []const u8, args: anytype) void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) self.out.appendSlice("  ") catch {};
        self.out.writer().print(fmt, args) catch {};
    }

    // Indent control
    pub fn in(self: *Op) void { self.indent += 1; }
    pub fn de(self: *Op) void { if (self.indent > 0) self.indent -= 1; }

    // WAT opcodes
    pub fn module(self: *Op) void { self.p("(module\n", .{}); self.in(); }
    pub fn moduleEnd(self: *Op) void { self.de(); self.p(")\n", .{}); }

    pub fn func(self: *Op, name: []const u8, params: []const u8) void {
        self.p("(func ${s}{s} (result i32)\n", .{ name, params });
        self.in();
    }
    pub fn funcEnd(self: *Op) void { self.de(); self.p(")\n", .{}); }

    pub fn export(self: *Op, name: []const u8) void {
        self.p("(export \"{s}\" (func ${s}))\n", .{ name, name });
    }

    pub fn block(self: *Op, label: []const u8) void { self.p("(block ${s}\n", .{label}); self.in(); }
    pub fn loop(self: *Op, label: []const u8) void { self.p("(loop ${s}\n", .{label}); self.in(); }
    pub fn end(self: *Op) void { self.de(); self.p(")\n", .{}); }

    pub fn @"if"(self: *Op) void { self.p("(if (result i32)\n", .{}); self.in(); }
    pub fn then(self: *Op) void { self.p("(then\n", .{}); self.in(); }
    pub fn @"else"(self: *Op) void { self.de(); self.p(")\n", .{}); self.p("(else\n", .{}); self.in(); }

    pub fn br(self: *Op, label: []const u8) void { self.p("br ${s}\n", .{label}); }
    pub fn br_if(self: *Op, label: []const u8) void { self.p("br_if ${s}\n", .{label}); }

    pub fn local_get(self: *Op, name: []const u8) void { self.p("local.get ${s}\n", .{name}); }
    pub fn local_set(self: *Op, name: []const u8) void { self.p("local.set ${s}\n", .{name}); }

    pub fn i32_const(self: *Op, val: []const u8) void { self.p("i32.const {s}\n", .{val}); }
    pub fn i32_add(self: *Op) void { self.p("i32.add\n", .{}); }
    pub fn i32_sub(self: *Op) void { self.p("i32.sub\n", .{}); }
    pub fn i32_mul(self: *Op) void { self.p("i32.mul\n", .{}); }
    pub fn i32_div(self: *Op) void { self.p("i32.div_s\n", .{}); }
    pub fn i32_lt(self: *Op) void { self.p("i32.lt_s\n", .{}); }
    pub fn i32_gt(self: *Op) void { self.p("i32.gt_s\n", .{}); }
    pub fn i32_eqz(self: *Op) void { self.p("i32.eqz\n", .{}); }

    pub fn call(self: *Op, name: []const u8) void { self.p("call ${s}\n", .{name}); }

    // Binary op from token
    pub fn binop(self: *Op, kind: t.TokenKind) void {
        switch (kind) {
            .plus => self.i32_add(),
            .minus => self.i32_sub(),
            .star => self.i32_mul(),
            .slash => self.i32_div(),
            .lt => self.i32_lt(),
            .gt => self.i32_gt(),
            else => {},
        }
    }
};

// ============ EMITTER ============

pub const Emitter = struct {
    op: Op,
    source: []const u8,
    locals: std.StringHashMap(u32),
    local_count: u32 = 0,
    alloc: std.mem.Allocator,

    pub fn emit(self: *Emitter, node: t.Node) ![]const u8 {
        self.emitNode(node);
        return self.op.out.items;
    }

    fn emitNode(self: *Emitter, node: t.Node) void {
        switch (node.kind) {
            .program => {
                self.op.module();
                for (node.children) |child| self.emitNode(child);
                self.op.moduleEnd();
            },

            .func_decl => {
                const name = node.token.?.text(self.source);
                self.locals.clearRetainingCapacity();
                self.local_count = 0;

                var params = std.ArrayList(u8).init(self.alloc);
                for (node.children) |child| {
                    if (child.kind == .param) {
                        const pname = child.token.?.text(self.source);
                        params.writer().print(" (param ${s} i32)", .{pname}) catch {};
                        self.locals.put(pname, self.local_count) catch {};
                        self.local_count += 1;
                    }
                }

                self.op.func(name, params.items);
                for (node.children) |child| {
                    if (child.kind == .block) {
                        for (child.children) |stmt| self.emitNode(stmt);
                    }
                }
                self.op.funcEnd();
                self.op.export(name);
            },

            .return_stmt => {
                for (node.children) |child| self.emitNode(child);
            },

            .local_decl => {
                const name = node.token.?.text(self.source);
                self.locals.put(name, self.local_count) catch {};
                self.local_count += 1;
                for (node.children) |child| self.emitNode(child);
                self.op.local_set(name);
            },

            .while_stmt => {
                self.op.block("break");
                self.op.loop("continue");
                self.emitNode(node.children[0]); // condition
                self.op.i32_eqz();
                self.op.br_if("break");
                for (node.children[1].children) |stmt| self.emitNode(stmt); // body
                self.op.br("continue");
                self.op.end();
                self.op.end();
                self.op.i32_const("0"); // while returns 0
            },

            .if_stmt => {
                self.emitNode(node.children[0]);
                self.op.@"if"();
                self.op.then();
                for (node.children[1].children) |stmt| self.emitNode(stmt);
                self.op.@"else"();
                if (node.children.len > 2) {
                    for (node.children[2].children) |stmt| self.emitNode(stmt);
                } else {
                    self.op.i32_const("0");
                }
                self.op.end();
                self.op.end();
            },

            .binary_expr => {
                self.emitNode(node.children[0]);
                self.emitNode(node.children[1]);
                self.op.binop(node.token.?.kind);
            },

            .call_expr => {
                for (node.children) |arg| self.emitNode(arg);
                self.op.call(node.token.?.text(self.source));
            },

            .identifier => self.op.local_get(node.token.?.text(self.source)),
            .number_lit => self.op.i32_const(node.value orelse "0"),

            else => {},
        }
    }
};

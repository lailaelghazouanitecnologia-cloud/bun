//! Shell Parser - AST builder
//!
//! Parses shell tokens into an Abstract Syntax Tree.
//!
//! Grammar (simplified):
//!   script     = statement*
//!   statement  = pipeline (('&&' | '||') pipeline)* [';' | '&' | '\n']
//!   pipeline   = command ('|' command)*
//!   command    = word+ [redirect*]
//!   redirect   = ('>' | '>>' | '<' | '2>' | '2>>' | '&>' | '2>&1') word

const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("lexer.zig").Token;

/// AST Node types
pub const Node = union(enum) {
    script: Script,
    statement: Statement,
    pipeline: Pipeline,
    command: Command,
    redirect: Redirect,
    word: Word,

    pub const Script = struct {
        statements: []Statement,
    };

    pub const Statement = struct {
        pipeline: Pipeline,
        next: ?*ChainedPipeline = null,
        background: bool = false,
    };

    pub const ChainedPipeline = struct {
        op: ChainOp,
        pipeline: Pipeline,
        next: ?*ChainedPipeline = null,
    };

    pub const ChainOp = enum {
        and_then, // &&
        or_else, // ||
    };

    pub const Pipeline = struct {
        commands: []Command,
        pipe_stderr: bool = false, // |& instead of |
    };

    pub const Command = struct {
        words: []Word,
        redirects: []Redirect,
        is_subshell: bool = false,
    };

    pub const Redirect = struct {
        kind: RedirectKind,
        target: Word,
        fd: ?u8 = null,
    };

    pub const RedirectKind = enum {
        output, // >
        append, // >>
        input, // <
        err_output, // 2>
        err_append, // 2>>
        both_output, // &>
        fd_dup, // 2>&1
    };

    pub const Word = struct {
        parts: []WordPart,
    };

    pub const WordPart = union(enum) {
        literal: []const u8,
        variable: []const u8,
        glob: []const u8,
        subst: []const u8, // command substitution
        quoted: []const u8, // "string"
        raw: []const u8, // 'string'
    };
};

pub const Parser = struct {
    tokens: []const Token,
    pos: usize = 0,
    allocator: std.mem.Allocator,

    // Memory pools for AST nodes
    statements: std.ArrayList(Node.Statement),
    pipelines: std.ArrayList(Node.Pipeline),
    commands: std.ArrayList(Node.Command),
    redirects: std.ArrayList(Node.Redirect),
    words: std.ArrayList(Node.Word),
    word_parts: std.ArrayList(Node.WordPart),
    chains: std.ArrayList(Node.ChainedPipeline),

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Parser {
        return .{
            .tokens = tokens,
            .allocator = allocator,
            .statements = std.ArrayList(Node.Statement).init(allocator),
            .pipelines = std.ArrayList(Node.Pipeline).init(allocator),
            .commands = std.ArrayList(Node.Command).init(allocator),
            .redirects = std.ArrayList(Node.Redirect).init(allocator),
            .words = std.ArrayList(Node.Word).init(allocator),
            .word_parts = std.ArrayList(Node.WordPart).init(allocator),
            .chains = std.ArrayList(Node.ChainedPipeline).init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.statements.deinit();
        self.pipelines.deinit();
        self.commands.deinit();
        self.redirects.deinit();
        self.words.deinit();
        self.word_parts.deinit();
        self.chains.deinit();
    }

    pub fn parse(self: *Parser) !Node.Script {
        var stmts = std.ArrayList(Node.Statement).init(self.allocator);
        defer stmts.deinit();

        while (!self.isAtEnd()) {
            // Skip newlines between statements
            while (self.check(.newline)) {
                self.advance();
            }

            if (self.isAtEnd()) break;

            const stmt = try self.parseStatement();
            try stmts.append(stmt);
        }

        return .{ .statements = try stmts.toOwnedSlice() };
    }

    fn parseStatement(self: *Parser) !Node.Statement {
        const pipeline = try self.parsePipeline();

        var stmt = Node.Statement{
            .pipeline = pipeline,
            .background = false,
        };

        // Check for chained pipelines (&&, ||)
        if (self.check(.and_op) or self.check(.or_op)) {
            stmt.next = try self.parseChainedPipelines();
        }

        // Check for background or terminator
        if (self.check(.background)) {
            stmt.background = true;
            self.advance();
        } else if (self.check(.semicolon) or self.check(.newline)) {
            self.advance();
        }

        return stmt;
    }

    fn parseChainedPipelines(self: *Parser) !*Node.ChainedPipeline {
        const chain = try self.allocator.create(Node.ChainedPipeline);

        chain.op = if (self.check(.and_op)) .and_then else .or_else;
        self.advance();

        chain.pipeline = try self.parsePipeline();
        chain.next = null;

        if (self.check(.and_op) or self.check(.or_op)) {
            chain.next = try self.parseChainedPipelines();
        }

        return chain;
    }

    fn parsePipeline(self: *Parser) !Node.Pipeline {
        var cmds = std.ArrayList(Node.Command).init(self.allocator);
        defer cmds.deinit();

        var pipe_stderr = false;

        // First command
        try cmds.append(try self.parseCommand());

        // Additional piped commands
        while (self.check(.pipe) or self.check(.pipe_err)) {
            if (self.check(.pipe_err)) pipe_stderr = true;
            self.advance();
            try cmds.append(try self.parseCommand());
        }

        return .{
            .commands = try cmds.toOwnedSlice(),
            .pipe_stderr = pipe_stderr,
        };
    }

    fn parseCommand(self: *Parser) !Node.Command {
        var words_list = std.ArrayList(Node.Word).init(self.allocator);
        defer words_list.deinit();

        var redirects_list = std.ArrayList(Node.Redirect).init(self.allocator);
        defer redirects_list.deinit();

        while (!self.isAtEnd()) {
            const tok = self.current();

            // Check for redirect operators
            if (self.isRedirect(tok.kind)) {
                try redirects_list.append(try self.parseRedirect());
                continue;
            }

            // Check for pipeline/statement terminators
            if (self.isTerminator(tok.kind)) break;

            // Parse word
            const word = try self.parseWord();
            try words_list.append(word);
        }

        return .{
            .words = try words_list.toOwnedSlice(),
            .redirects = try redirects_list.toOwnedSlice(),
        };
    }

    fn parseRedirect(self: *Parser) !Node.Redirect {
        const tok = self.current();
        self.advance();

        const kind: Node.RedirectKind = switch (tok.kind) {
            .redirect_out => .output,
            .redirect_append => .append,
            .redirect_in => .input,
            .redirect_err => .err_output,
            .redirect_err_append => .err_append,
            .redirect_both => .both_output,
            .redirect_fd => .fd_dup,
            else => unreachable,
        };

        // For 2>&1, there's no target word
        if (kind == .fd_dup) {
            return .{
                .kind = kind,
                .target = .{ .parts = &.{} },
                .fd = 1,
            };
        }

        // Parse target file
        const target = try self.parseWord();

        return .{
            .kind = kind,
            .target = target,
        };
    }

    fn parseWord(self: *Parser) !Node.Word {
        var parts = std.ArrayList(Node.WordPart).init(self.allocator);
        defer parts.deinit();

        // Parse a single word (one token, or compound like $var"text")
        const tok = self.current();

        switch (tok.kind) {
            .word => {
                try parts.append(.{ .literal = tok.text });
                self.advance();
            },
            .glob => {
                try parts.append(.{ .glob = tok.text });
                self.advance();
            },
            .variable => {
                try parts.append(.{ .variable = tok.text });
                self.advance();
            },
            .string => {
                // Remove quotes
                const text = tok.text;
                const inner = if (text.len >= 2) text[1 .. text.len - 1] else text;
                try parts.append(.{ .quoted = inner });
                self.advance();
            },
            .raw_string => {
                const text = tok.text;
                const inner = if (text.len >= 2) text[1 .. text.len - 1] else text;
                try parts.append(.{ .raw = inner });
                self.advance();
            },
            .backtick => {
                const text = tok.text;
                const inner = if (text.len >= 2) text[1 .. text.len - 1] else text;
                try parts.append(.{ .subst = inner });
                self.advance();
            },
            .subst_start => {
                // Handle $(...)
                self.advance();
                // TODO: parse nested command
                var depth: usize = 1;
                const start = self.pos;
                while (!self.isAtEnd() and depth > 0) {
                    if (self.check(.lparen)) depth += 1;
                    if (self.check(.rparen)) depth -= 1;
                    if (depth > 0) self.advance();
                }
                if (self.check(.rparen)) self.advance();
                _ = start;
            },
            else => {},
        }

        return .{ .parts = try parts.toOwnedSlice() };
    }

    // ============ HELPERS ============

    fn current(self: *Parser) Token {
        if (self.pos < self.tokens.len) return self.tokens[self.pos];
        return .{ .kind = .eof, .text = "", .pos = 0 };
    }

    fn advance(self: *Parser) void {
        if (self.pos < self.tokens.len) self.pos += 1;
    }

    fn check(self: *Parser, kind: Token.Kind) bool {
        return self.current().kind == kind;
    }

    fn isAtEnd(self: *Parser) bool {
        return self.current().kind == .eof;
    }

    fn isRedirect(self: *Parser, kind: Token.Kind) bool {
        _ = self;
        return switch (kind) {
            .redirect_out, .redirect_append, .redirect_in, .redirect_err, .redirect_err_append, .redirect_both, .redirect_fd => true,
            else => false,
        };
    }

    fn isTerminator(self: *Parser, kind: Token.Kind) bool {
        _ = self;
        return switch (kind) {
            .pipe, .pipe_err, .and_op, .or_op, .semicolon, .background, .newline, .eof => true,
            else => false,
        };
    }
};

// ============ PRETTY PRINT ============

pub fn printScript(script: Node.Script, writer: anytype) !void {
    for (script.statements) |stmt| {
        try printStatement(stmt, writer);
        try writer.writeAll("\n");
    }
}

fn printStatement(stmt: Node.Statement, writer: anytype) !void {
    try printPipeline(stmt.pipeline, writer);

    var chain = stmt.next;
    while (chain) |c| {
        const op = if (c.op == .and_then) " && " else " || ";
        try writer.writeAll(op);
        try printPipeline(c.pipeline, writer);
        chain = c.next;
    }

    if (stmt.background) try writer.writeAll(" &");
}

fn printPipeline(pipeline: Node.Pipeline, writer: anytype) !void {
    for (pipeline.commands, 0..) |cmd, i| {
        if (i > 0) {
            const sep = if (pipeline.pipe_stderr) " |& " else " | ";
            try writer.writeAll(sep);
        }
        try printCommand(cmd, writer);
    }
}

fn printCommand(cmd: Node.Command, writer: anytype) !void {
    for (cmd.words, 0..) |word, i| {
        if (i > 0) try writer.writeAll(" ");
        try printWord(word, writer);
    }

    for (cmd.redirects) |redir| {
        try writer.writeAll(" ");
        const op = switch (redir.kind) {
            .output => ">",
            .append => ">>",
            .input => "<",
            .err_output => "2>",
            .err_append => "2>>",
            .both_output => "&>",
            .fd_dup => "2>&1",
        };
        try writer.writeAll(op);
        if (redir.kind != .fd_dup) {
            try writer.writeAll(" ");
            try printWord(redir.target, writer);
        }
    }
}

fn printWord(word: Node.Word, writer: anytype) !void {
    for (word.parts) |part| {
        switch (part) {
            .literal => |s| try writer.writeAll(s),
            .variable => |s| try writer.writeAll(s),
            .glob => |s| try writer.writeAll(s),
            .quoted => |s| try writer.print("\"{s}\"", .{s}),
            .raw => |s| try writer.print("'{s}'", .{s}),
            .subst => |s| try writer.print("`{s}`", .{s}),
        }
    }
}

// ============ TESTS ============

test "parse simple command" {
    var lexer = Lexer.init(std.testing.allocator, "echo hello world");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = Parser.init(std.testing.allocator, tokens);
    defer parser.deinit();
    const script = try parser.parse();

    try std.testing.expectEqual(@as(usize, 1), script.statements.len);
    try std.testing.expectEqual(@as(usize, 1), script.statements[0].pipeline.commands.len);
    try std.testing.expectEqual(@as(usize, 3), script.statements[0].pipeline.commands[0].words.len);
}

test "parse pipeline" {
    var lexer = Lexer.init(std.testing.allocator, "ls -la | grep foo | wc -l");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = Parser.init(std.testing.allocator, tokens);
    defer parser.deinit();
    const script = try parser.parse();

    try std.testing.expectEqual(@as(usize, 3), script.statements[0].pipeline.commands.len);
}

test "parse redirect" {
    var lexer = Lexer.init(std.testing.allocator, "echo hello > out.txt");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = Parser.init(std.testing.allocator, tokens);
    defer parser.deinit();
    const script = try parser.parse();

    const cmd = script.statements[0].pipeline.commands[0];
    try std.testing.expectEqual(@as(usize, 1), cmd.redirects.len);
    try std.testing.expectEqual(Node.RedirectKind.output, cmd.redirects[0].kind);
}

test "parse chain" {
    var lexer = Lexer.init(std.testing.allocator, "cmd1 && cmd2 || cmd3");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();

    var parser = Parser.init(std.testing.allocator, tokens);
    defer parser.deinit();
    const script = try parser.parse();

    try std.testing.expect(script.statements[0].next != null);
    try std.testing.expectEqual(Node.ChainOp.and_then, script.statements[0].next.?.op);
}

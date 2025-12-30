//! Shell Lexer - Tokenizer for shell commands
//!
//! Supports:
//! - Commands and arguments
//! - Pipes: |
//! - Redirects: > >> < 2> 2>&1
//! - Variables: $VAR ${VAR}
//! - Strings: "double" 'single'
//! - Glob patterns: * ? [...]
//! - Command substitution: $(cmd) `cmd`
//! - Operators: && || ; &

const std = @import("std");

pub const Token = struct {
    kind: Kind,
    text: []const u8,
    pos: usize,

    pub const Kind = enum {
        // Literals
        word, // command or argument
        string, // "quoted string"
        raw_string, // 'raw string'
        variable, // $VAR or ${VAR}
        glob, // *.txt, file?.zig

        // Operators
        pipe, // |
        pipe_err, // |&
        and_op, // &&
        or_op, // ||
        semicolon, // ;
        background, // &
        newline, // \n

        // Redirects
        redirect_out, // >
        redirect_append, // >>
        redirect_in, // <
        redirect_err, // 2>
        redirect_err_append, // 2>>
        redirect_both, // &>
        redirect_fd, // 2>&1

        // Grouping
        lparen, // (
        rparen, // )
        lbrace, // {
        rbrace, // }

        // Substitution
        subst_start, // $(
        backtick, // `

        // Special
        eof,
        invalid,
    };

    pub fn format(self: Token, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}(\"{s}\")", .{ @tagName(self.kind), self.text });
    }
};

pub const Lexer = struct {
    input: []const u8,
    pos: usize = 0,
    tokens: std.ArrayList(Token),

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Lexer {
        return .{
            .input = input,
            .tokens = std.ArrayList(Token).init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
    }

    pub fn tokenize(self: *Lexer) ![]const Token {
        while (self.pos < self.input.len) {
            const token = try self.nextToken();
            if (token.kind == .eof) break;
            try self.tokens.append(token);
        }
        try self.tokens.append(.{ .kind = .eof, .text = "", .pos = self.pos });
        return self.tokens.items;
    }

    fn nextToken(self: *Lexer) !Token {
        self.skipWhitespace();

        if (self.pos >= self.input.len) {
            return .{ .kind = .eof, .text = "", .pos = self.pos };
        }

        const start = self.pos;
        const c = self.input[self.pos];

        // Single character tokens
        switch (c) {
            '\n' => {
                self.pos += 1;
                return .{ .kind = .newline, .text = "\n", .pos = start };
            },
            ';' => {
                self.pos += 1;
                return .{ .kind = .semicolon, .text = ";", .pos = start };
            },
            '(' => {
                self.pos += 1;
                return .{ .kind = .lparen, .text = "(", .pos = start };
            },
            ')' => {
                self.pos += 1;
                return .{ .kind = .rparen, .text = ")", .pos = start };
            },
            '{' => {
                self.pos += 1;
                return .{ .kind = .lbrace, .text = "{", .pos = start };
            },
            '}' => {
                self.pos += 1;
                return .{ .kind = .rbrace, .text = "}", .pos = start };
            },
            '`' => return self.scanBacktick(),
            '"' => return self.scanString(),
            '\'' => return self.scanRawString(),
            '$' => return self.scanVariable(),
            '|' => return self.scanPipe(),
            '&' => return self.scanAmpersand(),
            '>' => return self.scanRedirectOut(),
            '<' => return self.scanRedirectIn(),
            '2' => {
                if (self.peek(1) == '>') return self.scanRedirectErr();
                return self.scanWord();
            },
            else => return self.scanWord(),
        }
    }

    fn scanWord(self: *Lexer) Token {
        const start = self.pos;
        var has_glob = false;

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            switch (c) {
                // Word terminators
                ' ', '\t', '\n', '\r', ';', '|', '&', '>', '<', '(', ')', '{', '}', '"', '\'', '`' => break,
                // Glob characters
                '*', '?', '[' => {
                    has_glob = true;
                    self.pos += 1;
                },
                // Escape
                '\\' => {
                    self.pos += 1;
                    if (self.pos < self.input.len) self.pos += 1;
                },
                // Variable in word
                '$' => break,
                else => self.pos += 1,
            }
        }

        const text = self.input[start..self.pos];
        return .{
            .kind = if (has_glob) .glob else .word,
            .text = text,
            .pos = start,
        };
    }

    fn scanString(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1; // skip opening "

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == '"') {
                self.pos += 1;
                break;
            } else if (c == '\\' and self.pos + 1 < self.input.len) {
                self.pos += 2; // skip escape sequence
            } else {
                self.pos += 1;
            }
        }

        return .{ .kind = .string, .text = self.input[start..self.pos], .pos = start };
    }

    fn scanRawString(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1; // skip opening '

        while (self.pos < self.input.len and self.input[self.pos] != '\'') {
            self.pos += 1;
        }

        if (self.pos < self.input.len) self.pos += 1; // skip closing '

        return .{ .kind = .raw_string, .text = self.input[start..self.pos], .pos = start };
    }

    fn scanVariable(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1; // skip $

        if (self.pos >= self.input.len) {
            return .{ .kind = .word, .text = "$", .pos = start };
        }

        // $( - command substitution
        if (self.input[self.pos] == '(') {
            self.pos += 1;
            return .{ .kind = .subst_start, .text = "$(", .pos = start };
        }

        // ${VAR} - braced variable
        if (self.input[self.pos] == '{') {
            self.pos += 1;
            while (self.pos < self.input.len and self.input[self.pos] != '}') {
                self.pos += 1;
            }
            if (self.pos < self.input.len) self.pos += 1; // skip }
            return .{ .kind = .variable, .text = self.input[start..self.pos], .pos = start };
        }

        // $VAR - simple variable
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.pos += 1;
            } else {
                break;
            }
        }

        return .{ .kind = .variable, .text = self.input[start..self.pos], .pos = start };
    }

    fn scanBacktick(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1; // skip opening `

        while (self.pos < self.input.len and self.input[self.pos] != '`') {
            if (self.input[self.pos] == '\\' and self.pos + 1 < self.input.len) {
                self.pos += 2;
            } else {
                self.pos += 1;
            }
        }

        if (self.pos < self.input.len) self.pos += 1; // skip closing `

        return .{ .kind = .backtick, .text = self.input[start..self.pos], .pos = start };
    }

    fn scanPipe(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1;

        if (self.pos < self.input.len) {
            switch (self.input[self.pos]) {
                '|' => {
                    self.pos += 1;
                    return .{ .kind = .or_op, .text = "||", .pos = start };
                },
                '&' => {
                    self.pos += 1;
                    return .{ .kind = .pipe_err, .text = "|&", .pos = start };
                },
                else => {},
            }
        }

        return .{ .kind = .pipe, .text = "|", .pos = start };
    }

    fn scanAmpersand(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1;

        if (self.pos < self.input.len) {
            switch (self.input[self.pos]) {
                '&' => {
                    self.pos += 1;
                    return .{ .kind = .and_op, .text = "&&", .pos = start };
                },
                '>' => {
                    self.pos += 1;
                    return .{ .kind = .redirect_both, .text = "&>", .pos = start };
                },
                else => {},
            }
        }

        return .{ .kind = .background, .text = "&", .pos = start };
    }

    fn scanRedirectOut(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1;

        if (self.pos < self.input.len and self.input[self.pos] == '>') {
            self.pos += 1;
            return .{ .kind = .redirect_append, .text = ">>", .pos = start };
        }

        return .{ .kind = .redirect_out, .text = ">", .pos = start };
    }

    fn scanRedirectIn(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1;
        return .{ .kind = .redirect_in, .text = "<", .pos = start };
    }

    fn scanRedirectErr(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 2; // skip 2>

        if (self.pos < self.input.len and self.input[self.pos] == '>') {
            self.pos += 1;
            return .{ .kind = .redirect_err_append, .text = "2>>", .pos = start };
        }

        if (self.pos < self.input.len and self.input[self.pos] == '&') {
            self.pos += 1;
            if (self.pos < self.input.len and self.input[self.pos] == '1') {
                self.pos += 1;
                return .{ .kind = .redirect_fd, .text = "2>&1", .pos = start };
            }
        }

        return .{ .kind = .redirect_err, .text = "2>", .pos = start };
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.input.len) {
            switch (self.input[self.pos]) {
                ' ', '\t', '\r' => self.pos += 1,
                '#' => {
                    // Skip comment until newline
                    while (self.pos < self.input.len and self.input[self.pos] != '\n') {
                        self.pos += 1;
                    }
                },
                else => break,
            }
        }
    }

    fn peek(self: *Lexer, offset: usize) u8 {
        const idx = self.pos + offset;
        if (idx < self.input.len) return self.input[idx];
        return 0;
    }
};

// ============ TESTS ============

test "tokenize simple command" {
    var lexer = Lexer.init(std.testing.allocator, "echo hello world");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqual(Token.Kind.word, tokens[0].kind);
    try std.testing.expectEqualStrings("echo", tokens[0].text);
}

test "tokenize pipe" {
    var lexer = Lexer.init(std.testing.allocator, "ls | grep foo");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(@as(usize, 5), tokens.len);
    try std.testing.expectEqual(Token.Kind.pipe, tokens[1].kind);
}

test "tokenize variable" {
    var lexer = Lexer.init(std.testing.allocator, "echo $HOME ${PATH}");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(Token.Kind.variable, tokens[1].kind);
    try std.testing.expectEqualStrings("$HOME", tokens[1].text);
    try std.testing.expectEqual(Token.Kind.variable, tokens[2].kind);
    try std.testing.expectEqualStrings("${PATH}", tokens[2].text);
}

test "tokenize redirect" {
    var lexer = Lexer.init(std.testing.allocator, "echo hello > out.txt 2>&1");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(Token.Kind.redirect_out, tokens[2].kind);
    try std.testing.expectEqual(Token.Kind.redirect_fd, tokens[4].kind);
}

test "tokenize glob" {
    var lexer = Lexer.init(std.testing.allocator, "ls *.zig src/*.zig");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(Token.Kind.glob, tokens[1].kind);
    try std.testing.expectEqual(Token.Kind.glob, tokens[2].kind);
}

test "tokenize string" {
    var lexer = Lexer.init(std.testing.allocator, "echo \"hello world\" 'raw'");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(Token.Kind.string, tokens[1].kind);
    try std.testing.expectEqual(Token.Kind.raw_string, tokens[2].kind);
}

test "tokenize operators" {
    var lexer = Lexer.init(std.testing.allocator, "cmd1 && cmd2 || cmd3");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(Token.Kind.and_op, tokens[1].kind);
    try std.testing.expectEqual(Token.Kind.or_op, tokens[3].kind);
}

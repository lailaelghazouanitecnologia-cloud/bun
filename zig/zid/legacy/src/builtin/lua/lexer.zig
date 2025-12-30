const std = @import("std");

pub const TokenKind = enum {
    // Literals
    number,
    ident,
    string,

    // Keywords
    kw_function,
    kw_end,
    kw_return,
    kw_local,
    kw_if,
    kw_then,
    kw_else,
    kw_elseif,
    kw_while,
    kw_do,
    kw_for,
    kw_in,
    kw_repeat,
    kw_until,
    kw_break,
    kw_nil,
    kw_true,
    kw_false,
    kw_and,
    kw_or,
    kw_not,

    // Operators
    plus,
    minus,
    star,
    slash,
    percent,
    caret,
    eq,
    eqeq,
    neq,
    lt,
    gt,
    lte,
    gte,
    dotdot,

    // Delimiters
    lparen,
    rparen,
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    comma,
    semicolon,
    colon,
    dot,

    // Special
    eof,
    invalid,
};

pub const Token = struct {
    kind: TokenKind,
    start: u32,
    end: u32,

    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

const keywords = std.StaticStringMap(TokenKind).initComptime(.{
    .{ "function", .kw_function },
    .{ "end", .kw_end },
    .{ "return", .kw_return },
    .{ "local", .kw_local },
    .{ "if", .kw_if },
    .{ "then", .kw_then },
    .{ "else", .kw_else },
    .{ "elseif", .kw_elseif },
    .{ "while", .kw_while },
    .{ "do", .kw_do },
    .{ "for", .kw_for },
    .{ "in", .kw_in },
    .{ "repeat", .kw_repeat },
    .{ "until", .kw_until },
    .{ "break", .kw_break },
    .{ "nil", .kw_nil },
    .{ "true", .kw_true },
    .{ "false", .kw_false },
    .{ "and", .kw_and },
    .{ "or", .kw_or },
    .{ "not", .kw_not },
});

pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,

    pub fn next(self: *Lexer) Token {
        self.skipWhitespace();
        if (self.pos >= self.source.len) return .{ .kind = .eof, .start = self.pos, .end = self.pos };

        const start = self.pos;
        const c = self.source[self.pos];

        // Two-char operators
        if (self.pos + 1 < self.source.len) {
            const c2 = self.source[self.pos + 1];
            if (c == '=' and c2 == '=') { self.pos += 2; return .{ .kind = .eqeq, .start = start, .end = self.pos }; }
            if (c == '~' and c2 == '=') { self.pos += 2; return .{ .kind = .neq, .start = start, .end = self.pos }; }
            if (c == '<' and c2 == '=') { self.pos += 2; return .{ .kind = .lte, .start = start, .end = self.pos }; }
            if (c == '>' and c2 == '=') { self.pos += 2; return .{ .kind = .gte, .start = start, .end = self.pos }; }
            if (c == '.' and c2 == '.') { self.pos += 2; return .{ .kind = .dotdot, .start = start, .end = self.pos }; }
        }

        // Single-char operators
        switch (c) {
            '+' => { self.pos += 1; return .{ .kind = .plus, .start = start, .end = self.pos }; },
            '-' => { self.pos += 1; return .{ .kind = .minus, .start = start, .end = self.pos }; },
            '*' => { self.pos += 1; return .{ .kind = .star, .start = start, .end = self.pos }; },
            '/' => { self.pos += 1; return .{ .kind = .slash, .start = start, .end = self.pos }; },
            '%' => { self.pos += 1; return .{ .kind = .percent, .start = start, .end = self.pos }; },
            '^' => { self.pos += 1; return .{ .kind = .caret, .start = start, .end = self.pos }; },
            '=' => { self.pos += 1; return .{ .kind = .eq, .start = start, .end = self.pos }; },
            '<' => { self.pos += 1; return .{ .kind = .lt, .start = start, .end = self.pos }; },
            '>' => { self.pos += 1; return .{ .kind = .gt, .start = start, .end = self.pos }; },
            '(' => { self.pos += 1; return .{ .kind = .lparen, .start = start, .end = self.pos }; },
            ')' => { self.pos += 1; return .{ .kind = .rparen, .start = start, .end = self.pos }; },
            '{' => { self.pos += 1; return .{ .kind = .lbrace, .start = start, .end = self.pos }; },
            '}' => { self.pos += 1; return .{ .kind = .rbrace, .start = start, .end = self.pos }; },
            '[' => { self.pos += 1; return .{ .kind = .lbracket, .start = start, .end = self.pos }; },
            ']' => { self.pos += 1; return .{ .kind = .rbracket, .start = start, .end = self.pos }; },
            ',' => { self.pos += 1; return .{ .kind = .comma, .start = start, .end = self.pos }; },
            ';' => { self.pos += 1; return .{ .kind = .semicolon, .start = start, .end = self.pos }; },
            ':' => { self.pos += 1; return .{ .kind = .colon, .start = start, .end = self.pos }; },
            '.' => { self.pos += 1; return .{ .kind = .dot, .start = start, .end = self.pos }; },
            else => {},
        }

        // String
        if (c == '"' or c == '\'') {
            return self.lexString(c);
        }

        // Number
        if (isDigit(c)) {
            while (self.pos < self.source.len and (isDigit(self.source[self.pos]) or self.source[self.pos] == '.')) {
                self.pos += 1;
            }
            return .{ .kind = .number, .start = start, .end = self.pos };
        }

        // Identifier or keyword
        if (isAlpha(c)) {
            while (self.pos < self.source.len and isAlphaNum(self.source[self.pos])) {
                self.pos += 1;
            }
            const text = self.source[start..self.pos];
            const kind = keywords.get(text) orelse .ident;
            return .{ .kind = kind, .start = start, .end = self.pos };
        }

        self.pos += 1;
        return .{ .kind = .invalid, .start = start, .end = self.pos };
    }

    fn lexString(self: *Lexer, quote: u8) Token {
        const start = self.pos;
        self.pos += 1; // skip opening quote
        while (self.pos < self.source.len and self.source[self.pos] != quote) {
            if (self.source[self.pos] == '\\') self.pos += 1;
            self.pos += 1;
        }
        if (self.pos < self.source.len) self.pos += 1; // skip closing quote
        return .{ .kind = .string, .start = start, .end = self.pos };
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                self.pos += 1;
            } else if (ch == '-' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '-') {
                // Comment
                self.pos += 2;
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

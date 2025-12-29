const std = @import("std");

pub const TokenKind = enum {
    // Literals
    number,
    ident,
    string,
    char_lit,
    lifetime,

    // Keywords
    kw_fn,
    kw_let,
    kw_mut,
    kw_const,
    kw_static,
    kw_if,
    kw_else,
    kw_match,
    kw_loop,
    kw_while,
    kw_for,
    kw_in,
    kw_break,
    kw_continue,
    kw_return,
    kw_struct,
    kw_enum,
    kw_impl,
    kw_trait,
    kw_type,
    kw_where,
    kw_pub,
    kw_mod,
    kw_use,
    kw_as,
    kw_self,
    kw_Self,
    kw_super,
    kw_crate,
    kw_ref,
    kw_move,
    kw_async,
    kw_await,
    kw_dyn,
    kw_true,
    kw_false,

    // Operators
    plus,
    minus,
    star,
    slash,
    percent,
    caret,
    ampersand,
    pipe,
    bang,
    eq,
    eqeq,
    neq,
    lt,
    gt,
    lte,
    gte,
    ampamp,
    pipepipe,
    pluseq,
    minuseq,
    stareq,
    slasheq,
    arrow,      // ->
    fat_arrow,  // =>
    coloncolon, // ::
    dotdot,     // ..
    dotdoteq,   // ..=

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
    question,
    at,
    hash,

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
    .{ "fn", .kw_fn },
    .{ "let", .kw_let },
    .{ "mut", .kw_mut },
    .{ "const", .kw_const },
    .{ "static", .kw_static },
    .{ "if", .kw_if },
    .{ "else", .kw_else },
    .{ "match", .kw_match },
    .{ "loop", .kw_loop },
    .{ "while", .kw_while },
    .{ "for", .kw_for },
    .{ "in", .kw_in },
    .{ "break", .kw_break },
    .{ "continue", .kw_continue },
    .{ "return", .kw_return },
    .{ "struct", .kw_struct },
    .{ "enum", .kw_enum },
    .{ "impl", .kw_impl },
    .{ "trait", .kw_trait },
    .{ "type", .kw_type },
    .{ "where", .kw_where },
    .{ "pub", .kw_pub },
    .{ "mod", .kw_mod },
    .{ "use", .kw_use },
    .{ "as", .kw_as },
    .{ "self", .kw_self },
    .{ "Self", .kw_Self },
    .{ "super", .kw_super },
    .{ "crate", .kw_crate },
    .{ "ref", .kw_ref },
    .{ "move", .kw_move },
    .{ "async", .kw_async },
    .{ "await", .kw_await },
    .{ "dyn", .kw_dyn },
    .{ "true", .kw_true },
    .{ "false", .kw_false },
});

pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,

    pub fn next(self: *Lexer) Token {
        self.skipWhitespace();
        if (self.pos >= self.source.len) return .{ .kind = .eof, .start = self.pos, .end = self.pos };

        const start = self.pos;
        const c = self.source[self.pos];

        // Three-char operators
        if (self.pos + 2 < self.source.len) {
            const c2 = self.source[self.pos + 1];
            const c3 = self.source[self.pos + 2];
            if (c == '.' and c2 == '.' and c3 == '=') { self.pos += 3; return .{ .kind = .dotdoteq, .start = start, .end = self.pos }; }
        }

        // Two-char operators
        if (self.pos + 1 < self.source.len) {
            const c2 = self.source[self.pos + 1];
            if (c == '=' and c2 == '=') { self.pos += 2; return .{ .kind = .eqeq, .start = start, .end = self.pos }; }
            if (c == '!' and c2 == '=') { self.pos += 2; return .{ .kind = .neq, .start = start, .end = self.pos }; }
            if (c == '<' and c2 == '=') { self.pos += 2; return .{ .kind = .lte, .start = start, .end = self.pos }; }
            if (c == '>' and c2 == '=') { self.pos += 2; return .{ .kind = .gte, .start = start, .end = self.pos }; }
            if (c == '&' and c2 == '&') { self.pos += 2; return .{ .kind = .ampamp, .start = start, .end = self.pos }; }
            if (c == '|' and c2 == '|') { self.pos += 2; return .{ .kind = .pipepipe, .start = start, .end = self.pos }; }
            if (c == '+' and c2 == '=') { self.pos += 2; return .{ .kind = .pluseq, .start = start, .end = self.pos }; }
            if (c == '-' and c2 == '=') { self.pos += 2; return .{ .kind = .minuseq, .start = start, .end = self.pos }; }
            if (c == '*' and c2 == '=') { self.pos += 2; return .{ .kind = .stareq, .start = start, .end = self.pos }; }
            if (c == '/' and c2 == '=') { self.pos += 2; return .{ .kind = .slasheq, .start = start, .end = self.pos }; }
            if (c == '-' and c2 == '>') { self.pos += 2; return .{ .kind = .arrow, .start = start, .end = self.pos }; }
            if (c == '=' and c2 == '>') { self.pos += 2; return .{ .kind = .fat_arrow, .start = start, .end = self.pos }; }
            if (c == ':' and c2 == ':') { self.pos += 2; return .{ .kind = .coloncolon, .start = start, .end = self.pos }; }
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
            '&' => { self.pos += 1; return .{ .kind = .ampersand, .start = start, .end = self.pos }; },
            '|' => { self.pos += 1; return .{ .kind = .pipe, .start = start, .end = self.pos }; },
            '!' => { self.pos += 1; return .{ .kind = .bang, .start = start, .end = self.pos }; },
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
            '?' => { self.pos += 1; return .{ .kind = .question, .start = start, .end = self.pos }; },
            '@' => { self.pos += 1; return .{ .kind = .at, .start = start, .end = self.pos }; },
            '#' => { self.pos += 1; return .{ .kind = .hash, .start = start, .end = self.pos }; },
            else => {},
        }

        // Lifetime 'a
        if (c == '\'') {
            self.pos += 1;
            if (self.pos < self.source.len and isAlpha(self.source[self.pos])) {
                while (self.pos < self.source.len and isAlphaNum(self.source[self.pos])) {
                    self.pos += 1;
                }
                return .{ .kind = .lifetime, .start = start, .end = self.pos };
            }
            // Char literal
            return self.lexChar();
        }

        // String
        if (c == '"') {
            return self.lexString();
        }

        // Raw string r#"..."#
        if (c == 'r' and self.pos + 1 < self.source.len and (self.source[self.pos + 1] == '#' or self.source[self.pos + 1] == '"')) {
            return self.lexRawString();
        }

        // Number
        if (isDigit(c)) {
            return self.lexNumber();
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

    fn lexString(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1; // skip "
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') self.pos += 1;
            self.pos += 1;
        }
        if (self.pos < self.source.len) self.pos += 1;
        return .{ .kind = .string, .start = start, .end = self.pos };
    }

    fn lexChar(self: *Lexer) Token {
        const start = self.pos - 1; // already consumed '
        if (self.source[self.pos] == '\\') self.pos += 1;
        self.pos += 1;
        if (self.pos < self.source.len and self.source[self.pos] == '\'') self.pos += 1;
        return .{ .kind = .char_lit, .start = start, .end = self.pos };
    }

    fn lexRawString(self: *Lexer) Token {
        const start = self.pos;
        self.pos += 1; // skip r
        var hashes: u32 = 0;
        while (self.pos < self.source.len and self.source[self.pos] == '#') {
            hashes += 1;
            self.pos += 1;
        }
        if (self.pos < self.source.len and self.source[self.pos] == '"') {
            self.pos += 1;
            while (self.pos < self.source.len) {
                if (self.source[self.pos] == '"') {
                    self.pos += 1;
                    var closing_hashes: u32 = 0;
                    while (self.pos < self.source.len and self.source[self.pos] == '#' and closing_hashes < hashes) {
                        closing_hashes += 1;
                        self.pos += 1;
                    }
                    if (closing_hashes == hashes) break;
                } else {
                    self.pos += 1;
                }
            }
        }
        return .{ .kind = .string, .start = start, .end = self.pos };
    }

    fn lexNumber(self: *Lexer) Token {
        const start = self.pos;
        // Check for 0x, 0b, 0o
        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len) {
            const next = self.source[self.pos + 1];
            if (next == 'x' or next == 'X') {
                self.pos += 2;
                while (self.pos < self.source.len and isHexDigit(self.source[self.pos])) self.pos += 1;
                return .{ .kind = .number, .start = start, .end = self.pos };
            }
            if (next == 'b' or next == 'B') {
                self.pos += 2;
                while (self.pos < self.source.len and (self.source[self.pos] == '0' or self.source[self.pos] == '1' or self.source[self.pos] == '_')) self.pos += 1;
                return .{ .kind = .number, .start = start, .end = self.pos };
            }
            if (next == 'o' or next == 'O') {
                self.pos += 2;
                while (self.pos < self.source.len and isOctalDigit(self.source[self.pos])) self.pos += 1;
                return .{ .kind = .number, .start = start, .end = self.pos };
            }
        }

        // Decimal with optional . and e
        while (self.pos < self.source.len and (isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        if (self.pos < self.source.len and self.source[self.pos] == '.' and self.pos + 1 < self.source.len and isDigit(self.source[self.pos + 1])) {
            self.pos += 1;
            while (self.pos < self.source.len and (isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
                self.pos += 1;
            }
        }
        // Type suffix like i32, u64, f64
        if (self.pos < self.source.len and isAlpha(self.source[self.pos])) {
            while (self.pos < self.source.len and isAlphaNum(self.source[self.pos])) {
                self.pos += 1;
            }
        }
        return .{ .kind = .number, .start = start, .end = self.pos };
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
                self.pos += 1;
            } else if (ch == '/' and self.pos + 1 < self.source.len) {
                if (self.source[self.pos + 1] == '/') {
                    self.pos += 2;
                    while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
                } else if (self.source[self.pos + 1] == '*') {
                    self.pos += 2;
                    while (self.pos + 1 < self.source.len and !(self.source[self.pos] == '*' and self.source[self.pos + 1] == '/')) {
                        self.pos += 1;
                    }
                    self.pos += 2;
                } else {
                    break;
                }
            } else {
                break;
            }
        }
    }

    fn isDigit(c: u8) bool { return c >= '0' and c <= '9'; }
    fn isHexDigit(c: u8) bool { return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F') or c == '_'; }
    fn isOctalDigit(c: u8) bool { return (c >= '0' and c <= '7') or c == '_'; }
    fn isAlpha(c: u8) bool { return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'; }
    fn isAlphaNum(c: u8) bool { return isAlpha(c) or isDigit(c); }
};

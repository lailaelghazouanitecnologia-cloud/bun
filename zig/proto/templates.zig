// Templates: datos que definen el lenguaje

pub const TokenKind = enum {
    // Literals
    number,
    ident,

    // Keywords
    kw_function,
    kw_end,
    kw_return,
    kw_local,
    kw_if,
    kw_then,
    kw_else,
    kw_while,
    kw_do,

    // Operators
    plus,
    minus,
    star,
    slash,
    eq,
    lt,
    gt,

    // Delimiters
    lparen,
    rparen,
    comma,

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

pub const keywords = .{
    .{ "function", .kw_function },
    .{ "end", .kw_end },
    .{ "return", .kw_return },
    .{ "local", .kw_local },
    .{ "if", .kw_if },
    .{ "then", .kw_then },
    .{ "else", .kw_else },
    .{ "while", .kw_while },
    .{ "do", .kw_do },
};

pub const operators = .{
    .{ "+", .plus },
    .{ "-", .minus },
    .{ "*", .star },
    .{ "/", .slash },
    .{ "=", .eq },
    .{ "<", .lt },
    .{ ">", .gt },
    .{ "(", .lparen },
    .{ ")", .rparen },
    .{ ",", .comma },
};

pub const NodeKind = enum {
    program,
    func_decl,
    param,
    block,
    return_stmt,
    local_decl,
    if_stmt,
    while_stmt,
    binary_expr,
    call_expr,
    identifier,
    number_lit,
};

pub const Node = struct {
    kind: NodeKind,
    token: ?Token = null,
    children: []Node = &.{},
    value: ?[]const u8 = null,
};

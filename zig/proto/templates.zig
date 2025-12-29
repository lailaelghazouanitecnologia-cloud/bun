// Templates: datos que definen el lenguaje

// ============ TOKENS ============

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

// ============ AST NODES ============

pub const NodeKind = enum {
    program,
    func_decl,
    param,
    block,
    return_stmt,
    local_decl,
    if_stmt,
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

// ============ WAT OPCODES ============

pub const WatOp = enum {
    local_get,
    local_set,
    i32_const,
    i32_add,
    i32_sub,
    i32_mul,
    i32_div_s,
    i32_lt_s,
    i32_gt_s,
    call,
    @"if",
    @"else",
    end,
};

pub const op_map = .{
    .{ .plus, .i32_add },
    .{ .minus, .i32_sub },
    .{ .star, .i32_mul },
    .{ .slash, .i32_div_s },
    .{ .lt, .i32_lt_s },
    .{ .gt, .i32_gt_s },
};

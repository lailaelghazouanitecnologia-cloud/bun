const std = @import("std");
const Type = @import("types.zig").Type;

/// IR Node - Universal AST representation
pub const Node = union(enum) {
    // Module level
    module: Module,
    import: Import,
    func: Func,
    struct_decl: StructDecl,
    enum_decl: EnumDecl,
    trait_decl: TraitDecl,
    impl_block: ImplBlock,
    const_decl: ConstDecl,
    type_alias: TypeAlias,

    // Statements
    block: Block,
    let: Let,
    assign: Assign,
    return_: Return,
    break_: Break,
    continue_: Continue,
    if_: If,
    match_: Match,
    loop_: Loop,
    while_: While,
    for_: For,
    expr_stmt: ExprStmt,

    // Expressions
    binary: Binary,
    unary: Unary,
    call: Call,
    method_call: MethodCall,
    field: FieldAccess,
    index: Index,
    cast: Cast,
    ref: Ref,
    deref: Deref,

    // Literals
    ident: Ident,
    int_lit: IntLit,
    float_lit: FloatLit,
    bool_lit: BoolLit,
    string_lit: StringLit,
    char_lit: CharLit,
    array_lit: ArrayLit,
    tuple_lit: TupleLit,
    struct_lit: StructLit,

    // Advanced
    closure: Closure,
    spawn: Spawn,
    await_: Await,
    try_: Try,
    throw: Throw,

    pub fn getType(self: Node) ?Type {
        return switch (self) {
            .int_lit => |i| i.typ,
            .float_lit => |f| f.typ,
            .bool_lit => .bool,
            .string_lit => .string,
            .char_lit => .char,
            .ident => |id| id.typ,
            .binary => |b| b.typ,
            .unary => |u| u.typ,
            .call => |c| c.ret_type,
            .method_call => |m| m.ret_type,
            .field => |f| f.typ,
            .index => |i| i.typ,
            .cast => |c| c.to,
            .closure => |c| Type{ .closure = .{
                .params = c.param_types,
                .ret = c.ret_type,
                .captures = c.captures,
            } },
            else => null,
        };
    }
};

// ============ MODULE LEVEL ============

pub const Module = struct {
    name: []const u8,
    items: []Node,
};

pub const Import = struct {
    path: []const u8,
    alias: ?[]const u8 = null,
    items: []const []const u8 = &.{}, // specific imports
};

pub const Func = struct {
    name: []const u8,
    generics: []const GenericParam = &.{},
    params: []const Param,
    ret_type: ?*const Type = null,
    body: ?*const Node = null, // null = declaration only
    is_pub: bool = false,
    is_async: bool = false,
    is_extern: bool = false,
};

pub const Param = struct {
    name: []const u8,
    typ: Type,
    default: ?*const Node = null,
    mutable: bool = false,
};

pub const GenericParam = struct {
    name: []const u8,
    bounds: []const Bound = &.{},
    default: ?Type = null,
};

pub const Bound = struct {
    trait: []const u8,
    args: []const Type = &.{},
};

pub const StructDecl = struct {
    name: []const u8,
    generics: []const GenericParam = &.{},
    fields: []const FieldDecl,
    is_pub: bool = false,
};

pub const FieldDecl = struct {
    name: []const u8,
    typ: Type,
    default: ?*const Node = null,
    is_pub: bool = true,
};

pub const EnumDecl = struct {
    name: []const u8,
    generics: []const GenericParam = &.{},
    variants: []const VariantDecl,
    is_pub: bool = false,
};

pub const VariantDecl = struct {
    name: []const u8,
    payload: ?Type = null,
    value: ?i64 = null,
};

pub const TraitDecl = struct {
    name: []const u8,
    generics: []const GenericParam = &.{},
    bounds: []const Bound = &.{}, // supertraits
    methods: []const Func,
    is_pub: bool = false,
};

pub const ImplBlock = struct {
    generics: []const GenericParam = &.{},
    trait: ?[]const u8 = null,
    target: Type,
    methods: []const Func,
};

pub const ConstDecl = struct {
    name: []const u8,
    typ: ?Type = null,
    value: *const Node,
    is_pub: bool = false,
};

pub const TypeAlias = struct {
    name: []const u8,
    generics: []const GenericParam = &.{},
    target: Type,
    is_pub: bool = false,
};

// ============ STATEMENTS ============

pub const Block = struct {
    stmts: []Node,
    typ: ?Type = null, // expression block type
};

pub const Let = struct {
    name: []const u8,
    typ: ?Type = null,
    value: ?*const Node = null,
    mutable: bool = false,
};

pub const Assign = struct {
    target: *const Node,
    value: *const Node,
    op: ?BinaryOp = null, // for +=, -= etc
};

pub const Return = struct {
    value: ?*const Node = null,
};

pub const Break = struct {
    label: ?[]const u8 = null,
    value: ?*const Node = null,
};

pub const Continue = struct {
    label: ?[]const u8 = null,
};

pub const If = struct {
    cond: *const Node,
    then_: *const Node,
    else_: ?*const Node = null,
    typ: ?Type = null, // for if expressions
};

pub const Match = struct {
    scrutinee: *const Node,
    arms: []const MatchArm,
    typ: ?Type = null,
};

pub const MatchArm = struct {
    pattern: Pattern,
    guard: ?*const Node = null,
    body: *const Node,
};

pub const Pattern = union(enum) {
    wildcard,
    ident: []const u8,
    literal: *const Node,
    tuple: []const Pattern,
    struct_: StructPattern,
    enum_: EnumPattern,
    or_: []const Pattern,
    range: RangePattern,
};

pub const StructPattern = struct {
    name: ?[]const u8 = null,
    fields: []const FieldPattern,
    rest: bool = false,
};

pub const FieldPattern = struct {
    name: []const u8,
    pattern: ?Pattern = null,
};

pub const EnumPattern = struct {
    variant: []const u8,
    payload: ?Pattern = null,
};

pub const RangePattern = struct {
    start: ?*const Node = null,
    end: ?*const Node = null,
    inclusive: bool = false,
};

pub const Loop = struct {
    label: ?[]const u8 = null,
    body: *const Node,
};

pub const While = struct {
    label: ?[]const u8 = null,
    cond: *const Node,
    body: *const Node,
};

pub const For = struct {
    label: ?[]const u8 = null,
    binding: []const u8,
    iter: *const Node,
    body: *const Node,
};

pub const ExprStmt = struct {
    expr: *const Node,
};

// ============ EXPRESSIONS ============

pub const Binary = struct {
    op: BinaryOp,
    left: *const Node,
    right: *const Node,
    typ: ?Type = null,
};

pub const BinaryOp = enum {
    // Arithmetic
    add,
    sub,
    mul,
    div,
    rem,
    pow,

    // Bitwise
    bit_and,
    bit_or,
    bit_xor,
    shl,
    shr,

    // Logical
    and_,
    or_,

    // Comparison
    eq,
    ne,
    lt,
    le,
    gt,
    ge,

    // Other
    range,
    range_inclusive,
    concat,

    pub fn symbol(self: BinaryOp) []const u8 {
        return switch (self) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .rem => "%",
            .pow => "**",
            .bit_and => "&",
            .bit_or => "|",
            .bit_xor => "^",
            .shl => "<<",
            .shr => ">>",
            .and_ => "&&",
            .or_ => "||",
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .range => "..",
            .range_inclusive => "..=",
            .concat => "++",
        };
    }
};

pub const Unary = struct {
    op: UnaryOp,
    operand: *const Node,
    typ: ?Type = null,
};

pub const UnaryOp = enum {
    neg,
    not,
    bit_not,
    ref_,
    ref_mut,
    deref,
    try_,
    await_,

    pub fn symbol(self: UnaryOp) []const u8 {
        return switch (self) {
            .neg => "-",
            .not => "!",
            .bit_not => "~",
            .ref_ => "&",
            .ref_mut => "&mut",
            .deref => "*",
            .try_ => "?",
            .await_ => "await",
        };
    }
};

pub const Call = struct {
    func: *const Node,
    args: []const Arg,
    ret_type: ?Type = null,
};

pub const Arg = struct {
    name: ?[]const u8 = null,
    value: *const Node,
};

pub const MethodCall = struct {
    receiver: *const Node,
    method: []const u8,
    args: []const Arg,
    ret_type: ?Type = null,
};

pub const FieldAccess = struct {
    object: *const Node,
    field: []const u8,
    typ: ?Type = null,
};

pub const Index = struct {
    object: *const Node,
    index: *const Node,
    typ: ?Type = null,
};

pub const Cast = struct {
    value: *const Node,
    to: Type,
};

pub const Ref = struct {
    value: *const Node,
    mutable: bool = false,
};

pub const Deref = struct {
    value: *const Node,
    typ: ?Type = null,
};

// ============ LITERALS ============

pub const Ident = struct {
    name: []const u8,
    typ: ?Type = null,
};

pub const IntLit = struct {
    value: i64,
    typ: ?Type = .i32,
};

pub const FloatLit = struct {
    value: f64,
    typ: ?Type = .f64,
};

pub const BoolLit = struct {
    value: bool,
};

pub const StringLit = struct {
    value: []const u8,
};

pub const CharLit = struct {
    value: u32,
};

pub const ArrayLit = struct {
    elems: []const Node,
    typ: ?Type = null,
};

pub const TupleLit = struct {
    elems: []const Node,
};

pub const StructLit = struct {
    name: ?[]const u8 = null,
    fields: []const FieldInit,
};

pub const FieldInit = struct {
    name: []const u8,
    value: *const Node,
};

// ============ ADVANCED ============

pub const Closure = struct {
    params: []const Param,
    param_types: []const Type,
    ret_type: ?*const Type = null,
    body: *const Node,
    captures: []const @import("types.zig").Capture = &.{},
};

pub const Spawn = struct {
    func: *const Node,
};

pub const Await = struct {
    future: *const Node,
    typ: ?Type = null,
};

pub const Try = struct {
    expr: *const Node,
    typ: ?Type = null,
};

pub const Throw = struct {
    value: *const Node,
};

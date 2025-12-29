# Modulo 06: Language Plugins

## Proposito

Define la interfaz y utilidades para plugins de lenguaje. Un language plugin convierte codigo fuente en un AST que Zid puede procesar.

## Responsabilidades

- Interface LanguagePlugin
- AST generico
- Utilidades de lexing comunes
- Utilidades de parsing comunes
- Source locations

## Estructura Propuesta

```zig
// zig/src/language/mod.zig
pub const Plugin = @import("plugin.zig");
pub const AST = @import("ast.zig");
pub const Token = @import("token.zig");
pub const Lexer = @import("lexer.zig");
pub const Location = @import("location.zig");
```

## Interfaces

### LanguagePlugin Interface

```zig
pub const LanguagePlugin = struct {
    /// Metadata
    name: []const u8,
    version: Version,
    extensions: []const []const u8,

    /// Tokenizer
    tokenize: fn(
        source: []const u8,
        options: TokenizeOptions,
    ) Error!TokenStream,

    /// Parser
    parse: fn(
        tokens: TokenStream,
        options: ParseOptions,
    ) Error!*AST,

    /// Optional: Semantic analysis
    analyze: ?fn(
        ast: *AST,
        options: AnalyzeOptions,
    ) Error!void = null,

    /// Optional: Pretty print
    format: ?fn(
        ast: *AST,
        options: FormatOptions,
    ) Error![]const u8 = null,
};

pub const TokenizeOptions = struct {
    preserve_comments: bool = false,
    preserve_whitespace: bool = false,
};

pub const ParseOptions = struct {
    source_type: SourceType = .module,
    allow_errors: bool = false,  // Continue on syntax errors
    jsx: bool = false,
    decorators: bool = false,
};

pub const SourceType = enum {
    module,
    script,
    expression,
};
```

### AST Generico

```zig
pub const AST = struct {
    allocator: Allocator,
    root: *Node,
    source: []const u8,
    errors: []SyntaxError,

    pub fn init(allocator: Allocator) AST;
    pub fn deinit(self: *AST) void;

    /// Crear nodo
    pub fn node(self: *AST, kind: NodeKind, loc: Location) *Node;

    /// Visitar nodos
    pub fn walk(self: *AST, visitor: *Visitor) void;

    /// Buscar nodos
    pub fn find(self: *AST, kind: NodeKind) []*Node;
    pub fn findAt(self: *AST, offset: u32) ?*Node;
};

pub const Node = struct {
    kind: NodeKind,
    loc: Location,
    parent: ?*Node,
    children: []*Node,
    data: NodeData,

    pub fn appendChild(self: *Node, child: *Node) void;
    pub fn replaceWith(self: *Node, new: *Node) void;
    pub fn remove(self: *Node) void;
};

/// Tipos de nodos genericos
/// Cada language plugin puede definir sus propios tipos
pub const NodeKind = enum(u16) {
    // Programa
    program,
    module,

    // Declaraciones
    variable_decl,
    function_decl,
    class_decl,
    import_decl,
    export_decl,

    // Statements
    block,
    if_stmt,
    for_stmt,
    while_stmt,
    return_stmt,
    expression_stmt,

    // Expressions
    identifier,
    literal,
    binary_expr,
    unary_expr,
    call_expr,
    member_expr,
    array_expr,
    object_expr,
    function_expr,
    arrow_expr,

    // Otros
    comment,
    error_node,

    // Custom (plugins pueden extender)
    custom = 0x8000,
    _,
};

pub const NodeData = union {
    none: void,
    string: []const u8,
    number: f64,
    boolean: bool,
    list: []*Node,
    custom: *anyopaque,
};
```

### Tokens

```zig
pub const TokenStream = struct {
    tokens: []Token,
    source: []const u8,

    pub fn get(self: *TokenStream, index: usize) Token;
    pub fn peek(self: *TokenStream, offset: i32) ?Token;
    pub fn slice(self: *TokenStream, start: usize, end: usize) []Token;
};

pub const Token = struct {
    kind: TokenKind,
    start: u32,
    end: u32,
    line: u32,
    column: u32,

    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

pub const TokenKind = enum(u16) {
    // Literals
    identifier,
    number,
    string,
    template,
    regex,

    // Punctuation
    lparen,     // (
    rparen,     // )
    lbrace,     // {
    rbrace,     // }
    lbracket,   // [
    rbracket,   // ]
    semicolon,  // ;
    comma,      // ,
    dot,        // .
    colon,      // :

    // Operators
    plus,
    minus,
    star,
    slash,
    percent,
    equals,
    double_equals,
    triple_equals,
    bang,
    bang_equals,
    less_than,
    greater_than,
    ampersand,
    pipe,
    caret,

    // Keywords (custom per language)
    keyword = 0x100,

    // Comments
    comment,
    multiline_comment,

    // Special
    eof,
    error_token,
    whitespace,
    newline,

    // Custom
    custom = 0x8000,
    _,
};
```

### Location / Source Maps

```zig
pub const Location = struct {
    start: Position,
    end: Position,

    pub const Position = struct {
        offset: u32,  // Byte offset
        line: u32,    // 1-based
        column: u32,  // 0-based (UTF-16 code units for compat)
    };

    pub fn merge(a: Location, b: Location) Location {
        return .{
            .start = if (a.start.offset < b.start.offset) a.start else b.start,
            .end = if (a.end.offset > b.end.offset) a.end else b.end,
        };
    }
};

pub const SourceMap = struct {
    version: u8 = 3,
    file: ?[]const u8,
    source_root: ?[]const u8,
    sources: []const []const u8,
    sources_content: []const ?[]const u8,
    mappings: []const u8,

    pub fn encode(mappings: []Mapping) []const u8;
    pub fn decode(vlq: []const u8) []Mapping;

    pub const Mapping = struct {
        generated_line: u32,
        generated_column: u32,
        source: ?u32,
        original_line: ?u32,
        original_column: ?u32,
        name: ?u32,
    };
};
```

### Visitor Pattern

```zig
pub const Visitor = struct {
    enter: ?fn(node: *Node, ctx: *anyopaque) VisitResult = null,
    leave: ?fn(node: *Node, ctx: *anyopaque) void = null,
    context: *anyopaque,

    pub const VisitResult = enum {
        continue_,   // Visitar hijos
        skip,        // No visitar hijos
        stop,        // Parar completamente
    };
};

// Uso
pub fn countFunctions(ast: *AST) u32 {
    var count: u32 = 0;
    ast.walk(&Visitor{
        .enter = struct {
            fn enter(node: *Node, ctx: *anyopaque) Visitor.VisitResult {
                if (node.kind == .function_decl or node.kind == .function_expr) {
                    const c = @ptrCast(*u32, ctx);
                    c.* += 1;
                }
                return .continue_;
            }
        }.enter,
        .context = &count,
    });
    return count;
}
```

## Ejemplo: Plugin TypeScript

```zig
pub const typescript_plugin = LanguagePlugin{
    .name = "typescript",
    .version = .{ .major = 1, .minor = 0, .patch = 0 },
    .extensions = &.{ ".ts", ".tsx", ".mts", ".cts" },
    .tokenize = ts_tokenize,
    .parse = ts_parse,
    .analyze = ts_analyze,
};

fn ts_tokenize(source: []const u8, options: TokenizeOptions) Error!TokenStream {
    var lexer = TypeScriptLexer.init(source);
    var tokens = std.ArrayList(Token).init(allocator);

    while (lexer.next()) |token| {
        if (!options.preserve_comments and token.kind == .comment) continue;
        try tokens.append(token);
    }

    return TokenStream{ .tokens = tokens.toOwnedSlice(), .source = source };
}

fn ts_parse(tokens: TokenStream, options: ParseOptions) Error!*AST {
    var parser = TypeScriptParser.init(tokens, options);
    return parser.parse();
}
```

## Dependencias

- **Core**: Tipos, memoria
- **Plugin System**: Registro de plugins

## Estimacion

- **Lineas**: ~1,500
- **Complejidad**: Media
- **Prioridad**: Alta

## Checklist Implementacion

- [ ] `plugin.zig` - Interface LanguagePlugin
- [ ] `ast.zig` - AST generico
- [ ] `token.zig` - Tokens y TokenStream
- [ ] `location.zig` - Locations y SourceMap
- [ ] `visitor.zig` - Visitor pattern
- [ ] `lexer.zig` - Utilidades lexer
- [ ] `mod.zig` - Re-exports

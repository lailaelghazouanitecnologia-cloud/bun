# Modulo 09: Meta (Metaprogramacion)

## Proposito

El modulo Meta es el corazon de Zid. Provee herramientas de metaprogramacion (comptime) para que el usuario genere su propio lenguaje sin escribir codigo repetitivo.

## Responsabilidades

- Generacion de tipos de Token
- Generacion de nodos AST
- Generacion de parser helpers
- Generacion de visitors
- Generacion de printers/emitters
- Utilidades comptime

## Estructura

```zig
// zig/src/meta/mod.zig
pub const TokenGen = @import("token_gen.zig");
pub const ASTGen = @import("ast_gen.zig");
pub const ParserGen = @import("parser_gen.zig");
pub const VisitorGen = @import("visitor_gen.zig");
pub const PrinterGen = @import("printer_gen.zig");
pub const comptime_utils = @import("comptime_utils.zig");
```

## TokenGen

Genera un tipo Token completo desde una especificacion declarativa.

### Especificacion

```zig
const spec = .{
    // Patrones de tokens
    .patterns = .{
        .identifier = "[a-zA-Z_][a-zA-Z0-9_]*",
        .number = "[0-9]+\\.?[0-9]*",
        .string = "\"[^\"]*\"",
        .whitespace = "[ \\t\\n\\r]+",
        .comment = "//[^\\n]*",
    },

    // Keywords (generan enum automaticamente)
    .keywords = .{
        "fn", "let", "const", "var",
        "if", "else", "while", "for",
        "return", "break", "continue",
        "true", "false", "null",
    },

    // Operadores (generan enum automaticamente)
    .operators = .{
        .{ "=", "equals" },
        .{ "==", "double_equals" },
        .{ "!=", "not_equals" },
        .{ "+", "plus" },
        .{ "-", "minus" },
        .{ "*", "star" },
        .{ "/", "slash" },
        .{ "&&", "and" },
        .{ "||", "or" },
    },

    // Delimitadores
    .delimiters = .{
        .{ "(", "lparen" },
        .{ ")", "rparen" },
        .{ "{", "lbrace" },
        .{ "}", "rbrace" },
        .{ "[", "lbracket" },
        .{ "]", "rbracket" },
        .{ ";", "semicolon" },
        .{ ",", "comma" },
        .{ ".", "dot" },
        .{ ":", "colon" },
    },

    // Opciones
    .options = .{
        .skip_whitespace = true,
        .skip_comments = false,
    },
};
```

### Output Generado

```zig
pub fn TokenGen(comptime spec: anytype) type {
    return struct {
        pub const Kind = blk: {
            // Genera enum con todos los tokens
            var fields: []const std.builtin.Type.EnumField = &.{};

            // Agregar patterns
            inline for (spec.patterns) |p| {
                fields = fields ++ .{.{ .name = p.name }};
            }

            // Agregar keywords
            inline for (spec.keywords) |kw| {
                fields = fields ++ .{.{ .name = "kw_" ++ kw }};
            }

            // Agregar operators
            inline for (spec.operators) |op| {
                fields = fields ++ .{.{ .name = op[1] }};
            }

            // Agregar delimiters
            inline for (spec.delimiters) |d| {
                fields = fields ++ .{.{ .name = d[1] }};
            }

            // Agregar especiales
            fields = fields ++ .{
                .{ .name = "eof" },
                .{ .name = "invalid" },
            };

            break :blk @Type(.{ .Enum = .{ .fields = fields } });
        };

        kind: Kind,
        start: u32,
        end: u32,
        line: u32,
        column: u32,

        const Self = @This();

        // Metodos generados
        pub fn text(self: Self, source: []const u8) []const u8 {
            return source[self.start..self.end];
        }

        pub fn isKeyword(self: Self) bool {
            const val = @intFromEnum(self.kind);
            return val >= keyword_range.start and val < keyword_range.end;
        }

        pub fn isOperator(self: Self) bool {
            const val = @intFromEnum(self.kind);
            return val >= operator_range.start and val < operator_range.end;
        }

        // Lexer generado
        pub const Lexer = struct {
            source: []const u8,
            pos: u32 = 0,
            line: u32 = 1,
            column: u32 = 0,

            pub fn next(self: *Lexer) Self {
                if (spec.options.skip_whitespace) {
                    self.skipWhitespace();
                }

                if (self.pos >= self.source.len) {
                    return .{ .kind = .eof, .start = self.pos, .end = self.pos };
                }

                // Intentar cada patron en orden
                inline for (matchers) |matcher| {
                    if (matcher.match(self)) |token| {
                        return token;
                    }
                }

                return .{ .kind = .invalid, .start = self.pos, .end = self.pos + 1 };
            }

            pub fn tokenize(self: *Lexer, allocator: Allocator) ![]Self {
                var tokens = std.ArrayList(Self).init(allocator);
                while (true) {
                    const tok = self.next();
                    try tokens.append(tok);
                    if (tok.kind == .eof) break;
                }
                return tokens.toOwnedSlice();
            }
        };

        // Keyword lookup generado
        pub const keyword_map = blk: {
            var map: std.ComptimeStringMap(Kind) = .{};
            inline for (spec.keywords) |kw| {
                map.put(kw, @field(Kind, "kw_" ++ kw));
            }
            break :blk map;
        };
    };
}
```

### Uso

```zig
const Token = zid.TokenGen(my_spec);
var lexer = Token.Lexer{ .source = source_code };
const tokens = try lexer.tokenize(allocator);
```

---

## ASTGen

Genera tipos de nodos AST desde una especificacion declarativa.

### Especificacion

```zig
const ast_spec = .{
    // Nodo raiz
    .Program = .{
        .children = &.{.statements},
        .statements = .list(.Statement),
    },

    // Declaraciones
    .FnDecl = .{
        .tag = .declaration,
        .fields = &.{ .name, .params, .return_type, .body },
        .name = .Identifier,
        .params = .list(.Param),
        .return_type = .optional(.TypeExpr),
        .body = .Block,
    },

    .VarDecl = .{
        .tag = .declaration,
        .fields = &.{ .name, .type_ann, .value },
        .name = .Identifier,
        .type_ann = .optional(.TypeExpr),
        .value = .optional(.Expr),
    },

    // Statements
    .Block = .{
        .tag = .statement,
        .children = &.{.statements},
        .statements = .list(.Statement),
    },

    .IfStmt = .{
        .tag = .statement,
        .fields = &.{ .condition, .then_branch, .else_branch },
        .condition = .Expr,
        .then_branch = .Block,
        .else_branch = .optional(.Block),
    },

    // Expresiones
    .BinaryExpr = .{
        .tag = .expression,
        .fields = &.{ .left, .op, .right },
        .left = .Expr,
        .op = .Operator,
        .right = .Expr,
    },

    .CallExpr = .{
        .tag = .expression,
        .fields = &.{ .callee, .args },
        .callee = .Expr,
        .args = .list(.Expr),
    },

    .Identifier = .{
        .tag = .expression,
        .fields = &.{.name},
        .name = .string,
    },

    .Literal = .{
        .tag = .expression,
        .fields = &.{.value},
        .value = .variant(.{ .number, .string, .boolean, .null }),
    },
};
```

### Output Generado

```zig
pub fn ASTGen(comptime spec: anytype) type {
    return struct {
        allocator: Allocator,
        arena: std.heap.ArenaAllocator,

        // Enum de todos los tipos de nodo
        pub const NodeKind = blk: {
            var fields: []const std.builtin.Type.EnumField = &.{};
            inline for (std.meta.fields(@TypeOf(spec))) |field| {
                fields = fields ++ .{.{ .name = field.name }};
            }
            break :blk @Type(.{ .Enum = .{ .fields = fields } });
        };

        // Genera struct para cada nodo
        pub const Program = generateStruct(spec.Program);
        pub const FnDecl = generateStruct(spec.FnDecl);
        pub const VarDecl = generateStruct(spec.VarDecl);
        pub const Block = generateStruct(spec.Block);
        pub const IfStmt = generateStruct(spec.IfStmt);
        pub const BinaryExpr = generateStruct(spec.BinaryExpr);
        pub const CallExpr = generateStruct(spec.CallExpr);
        pub const Identifier = generateStruct(spec.Identifier);
        pub const Literal = generateStruct(spec.Literal);

        // Union de todos los nodos
        pub const Node = union(NodeKind) {
            program: *Program,
            fn_decl: *FnDecl,
            var_decl: *VarDecl,
            block: *Block,
            if_stmt: *IfStmt,
            binary_expr: *BinaryExpr,
            call_expr: *CallExpr,
            identifier: *Identifier,
            literal: *Literal,
        };

        // Helpers para crear nodos
        pub fn create(self: *@This(), comptime kind: NodeKind, data: anytype) *Node {
            const NodeType = std.meta.TagPayload(Node, kind);
            const ptr = self.arena.allocator().create(NodeType) catch unreachable;
            ptr.* = data;
            return &@unionInit(Node, @tagName(kind), ptr);
        }

        // Location tracking
        pub const Loc = struct {
            start: u32,
            end: u32,
            line: u32,
        };

        // Base para todos los nodos
        fn NodeBase(comptime fields_spec: anytype) type {
            return struct {
                loc: Loc,
                parent: ?*Node = null,
                // Campos especificos generados desde fields_spec
            };
        }
    };
}
```

---

## ParserGen

Genera helpers de parsing con manejo de precedencia automatico.

### Especificacion

```zig
const parser_spec = .{
    // Tabla de precedencia (menor a mayor)
    .precedence = .{
        .{ .equals },                           // 1 (lowest)
        .{ .double_equals, .not_equals },       // 2
        .{ .less, .greater, .less_eq, .greater_eq }, // 3
        .{ .plus, .minus },                     // 4
        .{ .star, .slash, .percent },           // 5
        .{ .dot, .lbracket },                   // 6 (highest)
    },

    // Asociatividad
    .right_assoc = .{ .equals },
    .left_assoc = .{ .plus, .minus, .star, .slash },

    // Operadores prefijos
    .prefix = .{ .minus, .bang },

    // Operadores postfijos
    .postfix = .{ .plus_plus, .minus_minus },
};
```

### Output Generado

```zig
pub fn ParserGen(
    comptime Token: type,
    comptime AST: type,
    comptime spec: anytype,
) type {
    return struct {
        tokens: []const Token,
        pos: usize = 0,
        ast: AST,
        errors: std.ArrayList(ParseError),

        const Self = @This();

        // === Metodos Base ===

        pub fn current(self: *Self) Token {
            return if (self.pos < self.tokens.len)
                self.tokens[self.pos]
            else
                Token{ .kind = .eof };
        }

        pub fn peek(self: *Self, offset: usize) ?Token {
            const idx = self.pos + offset;
            return if (idx < self.tokens.len) self.tokens[idx] else null;
        }

        pub fn advance(self: *Self) Token {
            const tok = self.current();
            if (self.pos < self.tokens.len) self.pos += 1;
            return tok;
        }

        pub fn expect(self: *Self, kind: Token.Kind) !Token {
            if (self.current().kind == kind) {
                return self.advance();
            }
            return self.err(.unexpected_token);
        }

        pub fn match(self: *Self, kind: Token.Kind) bool {
            if (self.current().kind == kind) {
                _ = self.advance();
                return true;
            }
            return false;
        }

        pub fn check(self: *Self, kind: Token.Kind) bool {
            return self.current().kind == kind;
        }

        // === Expresiones con Precedencia (Pratt Parser) ===

        pub fn parseExpr(self: *Self) !*AST.Node {
            return self.parsePrecedence(0);
        }

        fn parsePrecedence(self: *Self, min_prec: u8) !*AST.Node {
            // Prefix
            var left = try self.parsePrefix();

            // Infix (mientras la precedencia sea mayor)
            while (getPrecedence(self.current().kind)) |prec| {
                if (prec < min_prec) break;

                const op = self.advance();
                const next_prec = if (isRightAssoc(op.kind)) prec else prec + 1;
                const right = try self.parsePrecedence(next_prec);

                left = self.ast.create(.binary_expr, .{
                    .left = left,
                    .op = op,
                    .right = right,
                });
            }

            return left;
        }

        // Generado desde spec.precedence
        fn getPrecedence(kind: Token.Kind) ?u8 {
            return switch (kind) {
                inline for (spec.precedence, 0..) |level, i| {
                    inline for (level) |op| {
                        op => i + 1,
                    }
                },
                else => null,
            };
        }

        // Generado desde spec.right_assoc
        fn isRightAssoc(kind: Token.Kind) bool {
            return switch (kind) {
                inline for (spec.right_assoc) |op| op => true,
                else => false,
            };
        }

        // === Helpers para el Usuario ===

        /// Parsea una lista separada por un token
        pub fn list(
            self: *Self,
            comptime parseFn: fn(*Self) anyerror!*AST.Node,
            comptime separator: Token.Kind,
            comptime end: Token.Kind,
        ) ![]const *AST.Node {
            var items = std.ArrayList(*AST.Node).init(self.ast.allocator);

            while (!self.check(end) and !self.check(.eof)) {
                try items.append(try parseFn(self));
                if (!self.match(separator)) break;
            }

            return items.toOwnedSlice();
        }

        /// Parsea algo opcional
        pub fn optional(
            self: *Self,
            comptime parseFn: fn(*Self) anyerror!*AST.Node,
            comptime start: Token.Kind,
        ) ?*AST.Node {
            if (self.match(start)) {
                return parseFn(self) catch null;
            }
            return null;
        }

        /// Parsea entre delimitadores
        pub fn between(
            self: *Self,
            comptime open: Token.Kind,
            comptime close: Token.Kind,
            comptime parseFn: fn(*Self) anyerror!*AST.Node,
        ) !*AST.Node {
            _ = try self.expect(open);
            const result = try parseFn(self);
            _ = try self.expect(close);
            return result;
        }

        // === Error Recovery ===

        pub fn synchronize(self: *Self) void {
            while (!self.check(.eof)) {
                if (self.current().kind == .semicolon) {
                    _ = self.advance();
                    return;
                }
                // Sincronizar en keywords de statement
                switch (self.current().kind) {
                    .kw_fn, .kw_let, .kw_if, .kw_while, .kw_return => return,
                    else => _ = self.advance(),
                }
            }
        }
    };
}
```

---

## VisitorGen

Genera visitor pattern automaticamente desde la especificacion de AST.

```zig
pub fn VisitorGen(comptime AST: type) type {
    return struct {
        // Genera un tipo Visitor con metodos para cada nodo
        pub const Visitor = blk: {
            var fields: []const std.builtin.Type.StructField = &.{};

            // Un campo de funcion por cada tipo de nodo
            inline for (std.meta.fields(AST.NodeKind)) |kind| {
                const NodeType = std.meta.TagPayload(AST.Node, @field(AST.NodeKind, kind.name));
                fields = fields ++ .{.{
                    .name = "visit_" ++ kind.name,
                    .type = ?fn(*NodeType, *anyopaque) VisitResult,
                    .default_value = null,
                }};
            }

            fields = fields ++ .{.{
                .name = "context",
                .type = *anyopaque,
            }};

            break :blk @Type(.{ .Struct = .{ .fields = fields } });
        };

        pub const VisitResult = enum {
            continue_,
            skip_children,
            stop,
        };

        pub fn walk(node: *AST.Node, visitor: *Visitor) void {
            const result = switch (node.*) {
                inline else => |n, tag| blk: {
                    const visit_fn = @field(visitor, "visit_" ++ @tagName(tag));
                    break :blk if (visit_fn) |f| f(n, visitor.context) else .continue_;
                },
            };

            if (result == .stop) return;
            if (result == .skip_children) return;

            // Visitar hijos
            for (node.children()) |child| {
                walk(child, visitor);
            }
        }
    };
}
```

---

## PrinterGen

Genera printer/emitter con source map tracking.

```zig
pub fn PrinterGen(comptime AST: type) type {
    return struct {
        output: std.ArrayList(u8),
        indent_level: u32 = 0,
        line: u32 = 1,
        column: u32 = 0,
        mappings: std.ArrayList(Mapping),

        const Self = @This();

        pub fn print(self: *Self, str: []const u8) void {
            self.output.appendSlice(str) catch unreachable;
            self.updatePosition(str);
        }

        pub fn printWithLoc(self: *Self, str: []const u8, loc: AST.Loc) void {
            self.mappings.append(.{
                .generated_line = self.line,
                .generated_column = self.column,
                .original_line = loc.line,
                .original_column = loc.column,
            }) catch unreachable;
            self.print(str);
        }

        pub fn newline(self: *Self) void {
            self.print("\n");
            self.line += 1;
            self.column = 0;
            self.printIndent();
        }

        pub fn indent(self: *Self) void {
            self.indent_level += 1;
        }

        pub fn dedent(self: *Self) void {
            if (self.indent_level > 0) self.indent_level -= 1;
        }

        pub fn printIndent(self: *Self) void {
            var i: u32 = 0;
            while (i < self.indent_level) : (i += 1) {
                self.print("  ");
            }
        }

        pub fn space(self: *Self) void {
            self.print(" ");
        }

        pub fn toOwnedSlice(self: *Self) []u8 {
            return self.output.toOwnedSlice();
        }

        pub fn getSourceMap(self: *Self) SourceMap {
            return .{ .mappings = self.mappings.toOwnedSlice() };
        }
    };
}
```

---

## Dependencias

- **Core**: Tipos, memoria, comptime utils

## Estimacion

- **Lineas**: ~2,500
- **Complejidad**: Alta (metaprogramacion)
- **Prioridad**: CRITICA

## Checklist Implementacion

- [ ] `comptime_utils.zig` - Utilidades comptime
- [ ] `token_gen.zig` - Generador de tokens
- [ ] `ast_gen.zig` - Generador de AST
- [ ] `parser_gen.zig` - Generador de parser
- [ ] `visitor_gen.zig` - Generador de visitor
- [ ] `printer_gen.zig` - Generador de printer
- [ ] `mod.zig` - Re-exports

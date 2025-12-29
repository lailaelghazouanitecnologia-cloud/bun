# Zid - Filosofia de Diseno

## Principio Fundamental

**Zid NO es un runtime pre-definido. Es un TOOLKIT de metaprogramacion.**

```
Bun/Node/Deno:  Runtime completo → Usuario ejecuta codigo
Zid:            Herramientas     → Usuario CONSTRUYE su runtime
```

## Lo que Zid OFRECE (Esqueleto)

```
┌─────────────────────────────────────────────────────────┐
│                    ZID TOOLKIT                          │
├─────────────────────────────────────────────────────────┤
│  Core          │ Memoria, errores, plataforma           │
│  IO            │ Archivos, streams, watcher             │
│  CLI Builder   │ Herramientas para crear CLI            │
│  Plugin System │ Registro y carga                       │
│  Config        │ Carga de configuracion                 │
├─────────────────────────────────────────────────────────┤
│              METAPROGRAMACION (comptime)                │
├─────────────────────────────────────────────────────────┤
│  TokenGen     │ Genera tipos de tokens desde spec       │
│  ASTGen       │ Genera nodos AST desde spec             │
│  ParserGen    │ Genera parser desde gramatica           │
│  VisitorGen   │ Genera visitors desde AST               │
│  PrinterGen   │ Genera printer desde AST                │
└─────────────────────────────────────────────────────────┘
```

## Lo que Zid NO INCLUYE (Usuario define)

```
┌─────────────────────────────────────────────────────────┐
│              DEFINIDO POR EL USUARIO                    │
├─────────────────────────────────────────────────────────┤
│  Tokens        │ Que tokens tiene MI lenguaje           │
│  AST Nodes     │ Que nodos tiene MI AST                 │
│  Parser        │ Como parseo MI sintaxis                │
│  Semantica     │ Que significa MI codigo                │
│  Emision       │ A que target emito                     │
└─────────────────────────────────────────────────────────┘
```

## Ejemplo: Crear un Lenguaje con Zid

```zig
// mi_lenguaje.zig
const zid = @import("zid");

// 1. DEFINIR MIS TOKENS (usando metaprogramacion)
pub const Token = zid.TokenGen.generate(.{
    // Literales
    .identifier = .{ .pattern = "[a-zA-Z_][a-zA-Z0-9_]*" },
    .number = .{ .pattern = "[0-9]+" },
    .string = .{ .pattern = "\"[^\"]*\"" },

    // Keywords (generados automaticamente)
    .keywords = .{ "fn", "let", "if", "else", "return" },

    // Operadores
    .operators = .{
        .plus = "+",
        .minus = "-",
        .star = "*",
        .equals = "=",
        .double_equals = "==",
    },

    // Delimitadores
    .delimiters = .{
        .lparen = "(",
        .rparen = ")",
        .lbrace = "{",
        .rbrace = "}",
    },
});

// 2. DEFINIR MI AST (usando metaprogramacion)
pub const AST = zid.ASTGen.generate(.{
    .Program = .{ .children = .{ .statements } },

    .FnDecl = .{
        .fields = .{ .name, .params, .body },
        .name = .identifier,
        .params = .list(.identifier),
        .body = .Block,
    },

    .LetDecl = .{
        .fields = .{ .name, .value },
        .name = .identifier,
        .value = .Expr,
    },

    .IfStmt = .{
        .fields = .{ .condition, .then_branch, .else_branch },
        .condition = .Expr,
        .then_branch = .Block,
        .else_branch = .optional(.Block),
    },

    .BinaryExpr = .{
        .fields = .{ .left, .op, .right },
        .left = .Expr,
        .op = .operator,
        .right = .Expr,
    },

    // ... etc
});

// 3. USAR PARSER HELPERS (no escribir a mano)
pub const Parser = zid.ParserGen.generate(Token, AST, .{
    // Reglas de precedencia
    .precedence = .{
        .{ .equals, .double_equals },  // Lowest
        .{ .plus, .minus },
        .{ .star, .slash },            // Highest
    },

    // Asociatividad
    .left_assoc = .{ .plus, .minus, .star },
    .right_assoc = .{ .equals },
});

// 4. EMITIR A MI TARGET
pub const Emitter = zid.EmitterGen.generate(AST, .{
    .Program = emitProgram,
    .FnDecl = emitFunction,
    .LetDecl = emitLet,
    // ... solo escribo la logica, no el boilerplate
});

fn emitFunction(node: *AST.FnDecl, ctx: *EmitContext) void {
    ctx.print("function ");
    ctx.print(node.name);
    ctx.print("(");
    // ...
}
```

## Metaprogramacion: TokenGen

```zig
// zid/meta/token_gen.zig
pub fn generate(comptime spec: anytype) type {
    // Cuenta tokens
    const num_tokens = countTokens(spec);

    return struct {
        pub const Kind = enum(u16) {
            // Generado desde spec.keywords
            // Generado desde spec.operators
            // Generado desde spec.delimiters
            // ...
        };

        kind: Kind,
        start: u32,
        end: u32,

        // Metodos generados
        pub fn text(self: @This(), source: []const u8) []const u8 {
            return source[self.start..self.end];
        }

        pub fn isKeyword(self: @This()) bool {
            return @intFromEnum(self.kind) >= keyword_start and
                   @intFromEnum(self.kind) < keyword_end;
        }

        // Lexer generado
        pub const Lexer = generateLexer(spec);
    };
}
```

## Metaprogramacion: ASTGen

```zig
// zid/meta/ast_gen.zig
pub fn generate(comptime spec: anytype) type {
    return struct {
        // Genera enum de tipos de nodo
        pub const NodeKind = generateNodeKindEnum(spec);

        // Genera struct para cada nodo
        pub const Program = generateNodeStruct(spec.Program);
        pub const FnDecl = generateNodeStruct(spec.FnDecl);
        // ... todos generados

        // Genera union de todos los nodos
        pub const Node = union(NodeKind) {
            program: *Program,
            fn_decl: *FnDecl,
            // ...
        };

        // Visitor generado automaticamente
        pub const Visitor = generateVisitor(spec);

        // Walker generado
        pub fn walk(root: *Node, visitor: *Visitor) void {
            // Implementacion generada
        }
    };
}
```

## Metaprogramacion: ParserGen

```zig
// zid/meta/parser_gen.zig
pub fn generate(
    comptime Token: type,
    comptime AST: type,
    comptime rules: anytype,
) type {
    return struct {
        tokens: []const Token,
        pos: usize,
        ast: *AST,

        // Metodos base (siempre disponibles)
        pub fn current(self: *@This()) Token { ... }
        pub fn peek(self: *@This(), n: usize) ?Token { ... }
        pub fn advance(self: *@This()) Token { ... }
        pub fn expect(self: *@This(), kind: Token.Kind) !Token { ... }
        pub fn match(self: *@This(), kind: Token.Kind) bool { ... }

        // Expresiones con precedencia (generado desde rules.precedence)
        pub fn parseExpr(self: *@This()) !*AST.Expr {
            return self.parsePrecedence(0);
        }

        fn parsePrecedence(self: *@This(), min_prec: u8) !*AST.Expr {
            // Pratt parser generado automaticamente
        }

        // Helpers para el usuario
        pub fn list(
            self: *@This(),
            comptime parseFn: fn(*@This()) !*AST.Node,
            comptime separator: Token.Kind,
        ) ![]const *AST.Node { ... }

        pub fn optional(
            self: *@This(),
            comptime parseFn: fn(*@This()) !*AST.Node,
        ) ?*AST.Node { ... }
    };
}
```

## Ventajas de este Enfoque

| Aspecto | Runtime Tradicional | Zid Toolkit |
|---------|--------------------|--------------|
| Tokens | Hardcoded | Usuario define |
| AST | Hardcoded | Usuario define |
| Parser | Hardcoded | Usuario define (con helpers) |
| Boilerplate | Mucho | Generado por metaprogramacion |
| Flexibilidad | Baja | Total |
| Curva aprendizaje | Baja | Media |

## Estructura Final de Zid

```
zig/src/
├── core/           # Memoria, errores, tipos base
├── io/             # Archivos, streams
├── cli/            # Builder de CLI
├── plugin/         # Sistema de plugins
├── config/         # Carga de config
└── meta/           # METAPROGRAMACION
    ├── token_gen.zig    # Genera tokens desde spec
    ├── ast_gen.zig      # Genera AST desde spec
    ├── parser_gen.zig   # Genera parser helpers
    ├── visitor_gen.zig  # Genera visitors
    ├── printer_gen.zig  # Genera printers
    └── common.zig       # Utilidades comptime
```

## Resumen

```
Zid = Core + IO + CLI + Plugins + Config + METAPROGRAMACION

El usuario usa metaprogramacion para:
- Definir tokens de SU lenguaje
- Definir AST de SU lenguaje
- Generar parser con helpers
- Generar visitors/printers

Nosotros NO predefinimos:
- Ningun token especifico
- Ningun nodo AST especifico
- Ningun parser especifico
- Ningun target especifico

Solo herramientas para construirlos.
```

# Zid - Language Construction Toolkit

## Filosofia

**Zid NO es un runtime pre-definido. Es un TOOLKIT de metaprogramacion.**

```
Bun/Node/Deno:  Runtime completo → Usuario ejecuta codigo
Zid:            Herramientas     → Usuario CONSTRUYE su runtime
```

**Lee [00_PHILOSOPHY.md](./00_PHILOSOPHY.md) primero.**

## Estructura de Modulos

```
zig/
├── docs/
│   ├── README.md              # Este archivo
│   ├── 00_PHILOSOPHY.md       # Filosofia de diseno
│   ├── 01_CORE.md             # Sistema base
│   ├── 02_PLUGIN_SYSTEM.md    # Sistema de plugins
│   ├── 03_CLI.md              # Comandos dinamicos
│   ├── 04_IO.md               # I/O asincrono
│   ├── 05_RESOLVER.md         # Resolucion de modulos
│   ├── 06_LANGUAGE.md         # Interface para parsers
│   ├── 07_TARGET.md           # Interface para emitters
│   ├── 08_CONFIG.md           # Sistema de configuracion
│   └── 09_META.md             # METAPROGRAMACION (core)
└── src/                       # (futuro) Codigo fuente Zid
```

## Modulos

### Esqueleto (Lo que Zid provee)

| # | Modulo | Lineas | Descripcion |
|---|--------|--------|-------------|
| 1 | **Core** | ~2,000 | Tipos base, memoria, errores, plataforma |
| 2 | **IO** | ~4,000 | I/O asincrono cross-platform |
| 3 | **Plugin** | ~2,000 | Registro y carga de plugins |
| 4 | **CLI** | ~1,500 | Builder de comandos dinamico |
| 5 | **Config** | ~1,000 | Carga de configuracion |
| 9 | **Meta** | ~2,500 | **METAPROGRAMACION** (TokenGen, ASTGen, etc) |

### Interfaces (El usuario implementa)

| # | Modulo | Lineas | Descripcion |
|---|--------|--------|-------------|
| 5 | **Resolver** | ~1,500 | Interface de resolucion (usuario extiende) |
| 6 | **Language** | ~500 | Interface para language plugins |
| 7 | **Target** | ~500 | Interface para target plugins |

**Total Zid: ~15,000 lineas**

## Lo que Zid NO incluye

```
❌ Tokens pre-definidos     → Usuario los genera con TokenGen
❌ AST pre-definido         → Usuario lo genera con ASTGen
❌ Parser pre-definido      → Usuario lo genera con ParserGen
❌ Targets pre-definidos    → Usuario implementa sus emitters
```

## Grafo de Dependencias

```
                         ┌──────────┐
                         │   CORE   │
                         └────┬─────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
    ┌────▼────┐         ┌─────▼─────┐        ┌─────▼─────┐
    │   IO    │         │   META    │        │  Config   │
    └────┬────┘         │ (comptime)│        └───────────┘
         │              └─────┬─────┘
         │                    │
    ┌────▼────┐         ┌─────▼─────┐
    │Resolver │         │  Plugin   │
    │Interface│         │  System   │
    └─────────┘         └─────┬─────┘
                              │
                        ┌─────▼─────┐
                        │    CLI    │
                        │  Builder  │
                        └─────┬─────┘
                              │
              ┌───────────────┴───────────────┐
              │                               │
        ┌─────▼─────┐                   ┌─────▼─────┐
        │ Language  │                   │  Target   │
        │ Interface │                   │ Interface │
        └───────────┘                   └───────────┘
```

## Flujo de Usuario

```
1. Usuario define tokens      → TokenGen genera Lexer
2. Usuario define AST         → ASTGen genera Node types
3. Usuario define gramatica   → ParserGen genera helpers
4. Usuario implementa parser  → Usa los helpers generados
5. Usuario implementa target  → PrinterGen ayuda con output
```

## Ejemplo Completo

```zig
const zid = @import("zid");

// 1. DEFINIR TOKENS
pub const Token = zid.meta.TokenGen(.{
    .keywords = .{ "fn", "let", "if", "return" },
    .operators = .{ .{ "+", "plus" }, .{ "=", "equals" } },
    .delimiters = .{ .{ "(", "lparen" }, .{ ")", "rparen" } },
});

// 2. DEFINIR AST
pub const AST = zid.meta.ASTGen(.{
    .Program = .{ .statements = .list(.Statement) },
    .FnDecl = .{ .name = .Identifier, .body = .Block },
    .BinaryExpr = .{ .left = .Expr, .op = .Token, .right = .Expr },
});

// 3. CREAR PARSER (con helpers generados)
pub const Parser = zid.meta.ParserGen(Token, AST, .{
    .precedence = .{ .{ .plus }, .{ .star } },
});

// 4. IMPLEMENTAR LOGICA
pub fn parse(source: []const u8) !*AST.Node {
    var lexer = Token.Lexer{ .source = source };
    const tokens = try lexer.tokenize(allocator);

    var parser = Parser{ .tokens = tokens };
    return parser.parseProgram();
}

// 5. EMITIR A TARGET
pub fn emit(ast: *AST.Node) []const u8 {
    var printer = zid.meta.PrinterGen(AST){};
    // ... emit logic
    return printer.toOwnedSlice();
}
```

## Orden de Lectura

1. **00_PHILOSOPHY.md** - Entender el enfoque
2. **01_CORE.md** - Base del sistema
3. **09_META.md** - Metaprogramacion (el corazon)
4. **04_IO.md** - Operaciones de archivo
5. **02_PLUGIN_SYSTEM.md** - Sistema de plugins
6. **03_CLI.md** - Constructor de CLI
7. **06_LANGUAGE.md** - Interface de lenguaje
8. **07_TARGET.md** - Interface de target
9. **05_RESOLVER.md** - Resolucion de modulos
10. **08_CONFIG.md** - Configuracion

---

*Zid: Construye tu propio lenguaje*

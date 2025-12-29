# Zid - Template-Based Language Toolkit

## Concepto

Zid funciona como un **emulador**:

```
TEMPLATES (datos)     +     ENGINE (código fijo)
     ↓                           ↓
  Configuran              Interpreta y ejecuta
```

**Lee [00_ARCHITECTURE.md](./00_ARCHITECTURE.md) primero.**

## Templates Disponibles

| Template | Define | Ejemplo |
|----------|--------|---------|
| **Opcode** | Operaciones VM | `ADD`, `PUSH`, `CALL` |
| **Token** | Léxico | `+`, `fn`, `[0-9]+` |
| **Node** | AST | `BinaryExpr`, `FnDecl` |
| **Rule** | Gramática | `Expr → Term + Term` |
| **Emit** | Output | `"function " + name + "("` |

## Estructura

```
zig/
├── docs/
│   ├── README.md           # Este archivo
│   ├── 00_ARCHITECTURE.md  # Templates + Engine
│   ├── 01_CORE.md          # Tipos base
│   ├── 02_TEMPLATES.md     # Todos los templates
│   ├── 03_ENGINE.md        # El intérprete
│   ├── 04_IO.md            # I/O
│   └── 05_CLI.md           # Comandos
└── src/
    ├── core/               # Tipos, memoria
    ├── templates/          # Estructuras de templates
    └── engine/             # El intérprete fijo
```

## Ejemplo Rápido

```zig
// 1. DATOS: Defino mis templates
const tokens = [_]TokenTemplate{
    .{ .name = "plus", .pattern = "+" },
    .{ .name = "num", .pattern = "[0-9]+" },
};

const rules = [_]RuleTemplate{
    .{ .name = "expr", .pattern = &.{ "num", "plus", "num" } },
};

const emit = [_]EmitTemplate{
    .{ .node = "expr", .format = &.{ .field("left"), " + ", .field("right") } },
};

// 2. ENGINE: Proceso con el intérprete fijo
var engine = Engine.init(tokens, rules, emit);

const ast = engine.parse("1 + 2");
const output = engine.emit(ast);  // "1 + 2"
```

## Analogía

```
EMULADOR NES                    ZID
─────────────────────────────────────────────────
opcodes.json (LDA=0xA9)    ←→   tokens.zig (plus="+")
cpu.zig (fetch/decode/exec) ←→   engine.zig (lex/parse/emit)

Los opcodes son DATOS           Los templates son DATOS
El CPU es CÓDIGO FIJO           El engine es CÓDIGO FIJO
```

## Documentos

1. **00_ARCHITECTURE.md** - Visión completa
2. **01_CORE.md** - Tipos base
3. **04_IO.md** - Operaciones de archivo
4. **05_CLI.md** - Constructor de CLI

---

*Zid: Templates + Engine = Tu lenguaje*

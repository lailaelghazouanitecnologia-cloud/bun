# Zid - Arquitectura de Templates e Intérprete

## Concepto Fundamental

Zid funciona como un **emulador**: templates (datos) + intérprete (engine fijo).

```
┌─────────────────────────────────────────────────────────────┐
│                      TEMPLATES (DATOS)                      │
│  Definen QUÉ hacer - son configuración, no código           │
├─────────────────────────────────────────────────────────────┤
│  Opcodes      │ Operaciones fundamentales personalizables   │
│  Tokens       │ Patrones léxicos                            │
│  Nodes        │ Estructura del AST                          │
│  Rules        │ Gramática / producciones                    │
│  Emitters     │ Cómo generar output                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    ENGINE (CÓDIGO FIJO)                     │
│  Sabe CÓMO ejecutar - lee templates y procesa               │
├─────────────────────────────────────────────────────────────┤
│  engine.zig   │ Loop principal que interpreta templates     │
└─────────────────────────────────────────────────────────────┘
```

## Analogía: Emulador vs Zid

```
EMULADOR 6502:
┌──────────────┐     ┌──────────────┐
│   OPCODES    │     │     CPU      │
│ LDA = 0xA9   │ ──▶ │ fetch()      │
│ STA = 0x85   │     │ decode()     │
│ ADC = 0x69   │     │ execute()    │
└──────────────┘     └──────────────┘
    (datos)            (intérprete)

ZID:
┌──────────────┐     ┌──────────────┐
│  TEMPLATES   │     │    ENGINE    │
│ token: "+"   │ ──▶ │ lex()        │
│ node: Binary │     │ parse()      │
│ rule: E+T    │     │ emit()       │
└──────────────┘     └──────────────┘
    (datos)            (intérprete)
```

## Tipos de Templates

### 1. Opcode Templates (Operaciones Base)

```zig
const OpcodeTemplate = struct {
    name: []const u8,
    code: u16,
    handler: HandlerType,
    operands: []const OperandType,

    const HandlerType = enum {
        // Operaciones de stack
        push, pop, dup, swap,
        // Aritméticas
        add, sub, mul, div, mod,
        // Comparación
        eq, neq, lt, gt, lte, gte,
        // Control de flujo
        jump, jump_if, call, ret,
        // Memoria
        load, store, alloc, free,
        // Custom
        custom,
    };
};

// Usuario define sus opcodes
const my_opcodes = [_]OpcodeTemplate{
    .{ .name = "PUSH", .code = 0x01, .handler = .push, .operands = &.{.immediate} },
    .{ .name = "ADD", .code = 0x10, .handler = .add, .operands = &.{} },
    .{ .name = "CALL", .code = 0x20, .handler = .call, .operands = &.{.address} },
    // Opcode custom con handler propio
    .{ .name = "PRINT", .code = 0xF0, .handler = .custom, .operands = &.{} },
};
```

### 2. Token Templates

```zig
const TokenTemplate = struct {
    name: []const u8,
    kind: TokenKind,
    pattern: Pattern,
    precedence: ?u8 = null,
    assoc: ?Assoc = null,

    const TokenKind = enum { literal, pattern, keyword, operator, delimiter };
    const Pattern = union { literal: []const u8, regex: []const u8 };
    const Assoc = enum { left, right, none };
};

const my_tokens = [_]TokenTemplate{
    // Literales
    .{ .name = "plus", .kind = .operator, .pattern = .{ .literal = "+" }, .precedence = 4, .assoc = .left },
    .{ .name = "star", .kind = .operator, .pattern = .{ .literal = "*" }, .precedence = 5, .assoc = .left },

    // Patterns
    .{ .name = "number", .kind = .pattern, .pattern = .{ .regex = "[0-9]+" } },
    .{ .name = "ident", .kind = .pattern, .pattern = .{ .regex = "[a-zA-Z_][a-zA-Z0-9_]*" } },

    // Keywords
    .{ .name = "fn", .kind = .keyword, .pattern = .{ .literal = "fn" } },
    .{ .name = "let", .kind = .keyword, .pattern = .{ .literal = "let" } },
};
```

### 3. Node Templates (AST)

```zig
const NodeTemplate = struct {
    name: []const u8,
    tag: NodeTag,
    fields: []const FieldDef,

    const NodeTag = enum { expr, stmt, decl, type, pattern };
    const FieldDef = struct {
        name: []const u8,
        kind: FieldKind,
    };
    const FieldKind = enum { node, node_list, token, value, optional_node };
};

const my_nodes = [_]NodeTemplate{
    .{
        .name = "BinaryExpr",
        .tag = .expr,
        .fields = &.{
            .{ .name = "left", .kind = .node },
            .{ .name = "op", .kind = .token },
            .{ .name = "right", .kind = .node },
        },
    },
    .{
        .name = "FnDecl",
        .tag = .decl,
        .fields = &.{
            .{ .name = "name", .kind = .token },
            .{ .name = "params", .kind = .node_list },
            .{ .name = "body", .kind = .node },
        },
    },
    .{
        .name = "Literal",
        .tag = .expr,
        .fields = &.{
            .{ .name = "value", .kind = .value },
        },
    },
};
```

### 4. Rule Templates (Gramática)

```zig
const RuleTemplate = struct {
    name: []const u8,           // Nombre de la producción
    produces: []const u8,       // Qué nodo genera
    pattern: []const RuleItem,  // Patrón a matchear

    const RuleItem = union {
        token: []const u8,      // Nombre de token
        node: []const u8,       // Nombre de nodo/regla
        optional: []const u8,   // Opcional
        repeat: []const u8,     // Repetición (0+)
        repeat1: []const u8,    // Repetición (1+)
    };
};

const my_rules = [_]RuleTemplate{
    .{
        .name = "expr",
        .produces = "BinaryExpr",
        .pattern = &.{ .{ .node = "term" }, .{ .token = "plus" }, .{ .node = "term" } },
    },
    .{
        .name = "fn_decl",
        .produces = "FnDecl",
        .pattern = &.{
            .{ .token = "fn" },
            .{ .token = "ident" },
            .{ .token = "lparen" },
            .{ .repeat = "param" },
            .{ .token = "rparen" },
            .{ .node = "block" },
        },
    },
};
```

### 5. Emit Templates

```zig
const EmitTemplate = struct {
    node: []const u8,           // Qué nodo emite
    format: []const FormatItem, // Cómo emitirlo

    const FormatItem = union {
        literal: []const u8,    // Texto literal
        field: []const u8,      // Campo del nodo
        indent: void,           // Aumentar indent
        dedent: void,           // Reducir indent
        newline: void,          // Nueva línea
        space: void,            // Espacio
    };
};

const emit_to_js = [_]EmitTemplate{
    .{
        .node = "BinaryExpr",
        .format = &.{
            .{ .field = "left" },
            .{ .space = {} },
            .{ .field = "op" },
            .{ .space = {} },
            .{ .field = "right" },
        },
    },
    .{
        .node = "FnDecl",
        .format = &.{
            .{ .literal = "function " },
            .{ .field = "name" },
            .{ .literal = "(" },
            .{ .field = "params" },
            .{ .literal = ") {" },
            .{ .newline = {} },
            .{ .indent = {} },
            .{ .field = "body" },
            .{ .dedent = {} },
            .{ .newline = {} },
            .{ .literal = "}" },
        },
    },
};

// Otro target: Python
const emit_to_python = [_]EmitTemplate{
    .{
        .node = "FnDecl",
        .format = &.{
            .{ .literal = "def " },
            .{ .field = "name" },
            .{ .literal = "(" },
            .{ .field = "params" },
            .{ .literal = "):" },
            .{ .newline = {} },
            .{ .indent = {} },
            .{ .field = "body" },
            .{ .dedent = {} },
        },
    },
};
```

## Engine (Intérprete Fijo)

```zig
const Engine = struct {
    // Templates cargados
    opcodes: []const OpcodeTemplate,
    tokens: []const TokenTemplate,
    nodes: []const NodeTemplate,
    rules: []const RuleTemplate,
    emitters: []const EmitTemplate,

    // Estado runtime
    stack: Stack,
    memory: Memory,
    pc: usize,

    pub fn init(config: EngineConfig) Engine {
        return .{
            .opcodes = config.opcodes,
            .tokens = config.tokens,
            .nodes = config.nodes,
            .rules = config.rules,
            .emitters = config.emitters,
            .stack = Stack.init(),
            .memory = Memory.init(),
            .pc = 0,
        };
    }

    // ===== LEXER (usa token templates) =====
    pub fn lex(self: *Engine, source: []const u8) []Token {
        var tokens = ArrayList(Token).init();
        var pos: usize = 0;

        while (pos < source.len) {
            // Intenta cada template en orden
            for (self.tokens) |template| {
                if (self.matchToken(source, pos, template)) |len| {
                    tokens.append(.{
                        .template = template,
                        .start = pos,
                        .end = pos + len,
                    });
                    pos += len;
                    break;
                }
            }
        }

        return tokens.items;
    }

    // ===== PARSER (usa rule templates) =====
    pub fn parse(self: *Engine, tokens: []Token) *Node {
        return self.parseRule(tokens, "program");
    }

    fn parseRule(self: *Engine, tokens: []Token, rule_name: []const u8) *Node {
        // Busca el rule template
        const rule = self.findRule(rule_name);

        // Intenta matchear el pattern
        var node = self.createNode(rule.produces);

        for (rule.pattern) |item| {
            switch (item) {
                .token => |name| {
                    node.addChild(self.expectToken(name));
                },
                .node => |name| {
                    node.addChild(self.parseRule(tokens, name));
                },
                .repeat => |name| {
                    while (self.canMatch(name)) {
                        node.addChild(self.parseRule(tokens, name));
                    }
                },
                // ...
            }
        }

        return node;
    }

    // ===== EMITTER (usa emit templates) =====
    pub fn emit(self: *Engine, node: *Node) []const u8 {
        var output = ArrayList(u8).init();
        self.emitNode(&output, node);
        return output.items;
    }

    fn emitNode(self: *Engine, output: *ArrayList(u8), node: *Node) void {
        // Busca el emit template para este nodo
        const template = self.findEmitter(node.template.name);

        for (template.format) |item| {
            switch (item) {
                .literal => |text| output.appendSlice(text),
                .field => |name| {
                    const child = node.getField(name);
                    self.emitNode(output, child);
                },
                .newline => output.append('\n'),
                .space => output.append(' '),
                .indent => self.indent_level += 1,
                .dedent => self.indent_level -= 1,
            }
        }
    }

    // ===== VM (usa opcode templates) =====
    pub fn execute(self: *Engine, bytecode: []const u8) void {
        while (self.pc < bytecode.len) {
            const opcode = bytecode[self.pc];
            const template = self.findOpcode(opcode);

            // Lee operandos según template
            const operands = self.readOperands(template.operands);

            // Ejecuta según handler
            switch (template.handler) {
                .push => self.stack.push(operands[0]),
                .pop => _ = self.stack.pop(),
                .add => {
                    const b = self.stack.pop();
                    const a = self.stack.pop();
                    self.stack.push(a + b);
                },
                .jump => self.pc = operands[0],
                .call => self.call(operands[0]),
                .custom => self.customHandler(template, operands),
                // ...
            }

            self.pc += 1 + template.operands.len;
        }
    }
};
```

## Uso Completo

```zig
// 1. Definir templates para MI lenguaje
const my_language = LanguageTemplates{
    .opcodes = my_opcodes,
    .tokens = my_tokens,
    .nodes = my_nodes,
    .rules = my_rules,
};

// 2. Definir templates de emisión para MI target
const my_target = emit_to_js;  // o emit_to_python, etc.

// 3. Crear engine con los templates
var engine = Engine.init(.{
    .language = my_language,
    .target = my_target,
});

// 4. Procesar código
const source = "fn add(a, b) { a + b }";
const tokens = engine.lex(source);
const ast = engine.parse(tokens);
const output = engine.emit(ast);
// output = "function add(a, b) {\n  a + b\n}"
```

## Resumen

```
DATOS (personalizables):
├── Opcodes     → Operaciones de la VM
├── Tokens      → Léxico del lenguaje
├── Nodes       → Estructura del AST
├── Rules       → Gramática
└── Emitters    → Formato de salida

CÓDIGO (fijo):
└── Engine      → Interpreta todos los templates
    ├── lex()       → Lee token templates
    ├── parse()     → Lee rule templates
    ├── emit()      → Lee emit templates
    └── execute()   → Lee opcode templates
```

**El engine NUNCA cambia. Solo los templates.**

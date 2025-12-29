# Zid - Target Final

## Visión

Runtime dinámico y modular. Componentes intercambiables.

```
┌─────────────────────────────────────────────────────────────┐
│                         ZID                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│   │ Lexer   │───▶│ Parser  │───▶│ Runtime │───▶│ Target  │ │
│   │ Plugin  │    │ Plugin  │    │ Plugin  │    │ Plugin  │ │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│        │              │              │              │       │
│        ▼              ▼              ▼              ▼       │
│   ┌─────────────────────────────────────────────────────┐  │
│   │                    TEMPLATES                        │  │
│   │  tokens, nodes, opcodes, rules, validators          │  │
│   └─────────────────────────────────────────────────────┘  │
│                            │                                │
│                            ▼                                │
│   ┌─────────────────────────────────────────────────────┐  │
│   │                      OP                             │  │
│   │  Helpers unificados para emitir a cualquier target  │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Componentes

### 1. Templates (Datos)

```zig
// Cada lenguaje define sus templates
const lua = @import("langs/lua.zig");
const python = @import("langs/python.zig");
const custom = @import("langs/my_dsl.zig");

// Selección dinámica
const lang = switch (ext) {
    ".lua" => lua.templates,
    ".py" => python.templates,
    ".dsl" => custom.templates,
    else => default.templates,
};
```

### 2. Op (Emisión unificada)

```zig
// Op genérico - mismo API para cualquier target
pub const Op = struct {
    target: Target,

    // Estructura
    pub fn module(self: *Op) void { self.target.module(); }
    pub fn func(self: *Op, name: []const u8) void { self.target.func(name); }
    pub fn end(self: *Op) void { self.target.end(); }

    // Operaciones
    pub fn add(self: *Op) void { self.target.add(); }
    pub fn sub(self: *Op) void { self.target.sub(); }
    pub fn call(self: *Op, name: []const u8) void { self.target.call(name); }

    // Variables
    pub fn local_get(self: *Op, name: []const u8) void { self.target.local_get(name); }
    pub fn local_set(self: *Op, name: []const u8) void { self.target.local_set(name); }
};
```

### 3. Targets (Salida)

```zig
// WAT
pub const WatTarget = struct {
    pub fn add(self: *@This()) void { self.emit("i32.add\n"); }
    pub fn func(self: *@This(), name: []const u8) void {
        self.emit("(func ${s}\n", .{name});
    }
};

// JavaScript
pub const JsTarget = struct {
    pub fn add(self: *@This()) void { self.emit(" + "); }
    pub fn func(self: *@This(), name: []const u8) void {
        self.emit("function {s}(", .{name});
    }
};

// Bytecode (runtime propio)
pub const BytecodeTarget = struct {
    pub fn add(self: *@This()) void { self.emit_byte(OP_ADD); }
    pub fn func(self: *@This(), name: []const u8) void {
        self.emit_byte(OP_FUNC);
        self.emit_string(name);
    }
};

// LLVM IR
pub const LlvmTarget = struct {
    pub fn add(self: *@This()) void {
        self.emit("%{d} = add i32 %{d}, %{d}\n", .{...});
    }
};
```

### 4. Runtime (VM propia)

```zig
pub const VM = struct {
    stack: [256]Value,
    sp: u8 = 0,
    code: []const u8,
    ip: usize = 0,
    globals: std.StringHashMap(Value),

    pub fn run(self: *VM) !Value {
        while (self.ip < self.code.len) {
            const op = self.code[self.ip];
            self.ip += 1;

            switch (op) {
                OP_CONST => self.push(self.readConst()),
                OP_ADD => self.push(self.pop() + self.pop()),
                OP_SUB => { const b = self.pop(); self.push(self.pop() - b); },
                OP_MUL => self.push(self.pop() * self.pop()),
                OP_DIV => { const b = self.pop(); self.push(self.pop() / b); },
                OP_CALL => self.call(self.readString()),
                OP_RET => return self.pop(),
                OP_LOCAL_GET => self.push(self.locals[self.readByte()]),
                OP_LOCAL_SET => self.locals[self.readByte()] = self.pop(),
                OP_JMP => self.ip = self.readU16(),
                OP_JMP_IF_FALSE => {
                    const addr = self.readU16();
                    if (!self.pop().toBool()) self.ip = addr;
                },
                else => {},
            }
        }
        return self.pop();
    }
};
```

## Flujo Completo

```
                    ┌─────────────┐
                    │   Source    │
                    │  (.lua/.py) │
                    └──────┬──────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│                      FRONTEND                            │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐              │
│  │ Lexer   │───▶│ Parser  │───▶│   AST   │              │
│  │(template)│   │(template)│   │         │              │
│  └─────────┘    └─────────┘    └─────────┘              │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│                      MIDDLE                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐              │
│  │Validate │───▶│Transform│───▶│Optimize │              │
│  │(optional)│   │(optional)│   │(optional)│             │
│  └─────────┘    └─────────┘    └─────────┘              │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────┐
│                      BACKEND                             │
│            ┌─────────────┴─────────────┐                 │
│            ▼                           ▼                 │
│     ┌─────────────┐             ┌─────────────┐         │
│     │   COMPILE   │             │  INTERPRET  │         │
│     └──────┬──────┘             └──────┬──────┘         │
│            │                           │                 │
│     ┌──────┴──────┐                    ▼                 │
│     ▼      ▼      ▼             ┌─────────────┐         │
│   WAT    JS    LLVM            │     VM      │         │
│            │                    │   (stack)   │         │
│            ▼                    └─────────────┘         │
│     ┌─────────────┐                    │                 │
│     │   Output    │                    ▼                 │
│     │  (archivo)  │             ┌─────────────┐         │
│     └─────────────┘             │   Result    │         │
│                                 └─────────────┘         │
└──────────────────────────────────────────────────────────┘
```

## API Final

```zig
const zid = @import("zid");

// Opción 1: Compilar a WAT
const wat = zid.compile(.{
    .source = source,
    .lang = .lua,
    .target = .wat,
});
try std.fs.writeFile("out.wat", wat);

// Opción 2: Compilar a JS
const js = zid.compile(.{
    .source = source,
    .lang = .lua,
    .target = .javascript,
});

// Opción 3: Ejecutar directamente
const result = zid.run(.{
    .source = source,
    .lang = .lua,
});
std.debug.print("Result: {}\n", .{result});

// Opción 4: Compilar a bytecode + ejecutar
const bytecode = zid.compile(.{
    .source = source,
    .lang = .lua,
    .target = .bytecode,
});
var vm = zid.VM.init(bytecode);
const result2 = try vm.run();

// Opción 5: Pipeline custom
const result3 = zid.pipeline(.{
    .source = source,
    .steps = .{
        .{ .lex, lua.tokens },
        .{ .parse, lua.grammar },
        .{ .validate, my_rules },      // opcional
        .{ .transform, my_optimizer }, // opcional
        .{ .emit, .wat },
    },
});
```

## Estructura de Archivos

```
zid/
├── src/
│   ├── core/
│   │   ├── op.zig          # Op genérico
│   │   ├── value.zig       # Tipos de valor
│   │   └── error.zig       # Errores
│   │
│   ├── frontend/
│   │   ├── lexer.zig       # Lexer genérico
│   │   ├── parser.zig      # Parser genérico
│   │   └── ast.zig         # AST genérico
│   │
│   ├── backend/
│   │   ├── vm.zig          # VM con stack
│   │   ├── compiler.zig    # AST → Bytecode
│   │   └── targets/
│   │       ├── wat.zig
│   │       ├── js.zig
│   │       ├── llvm.zig
│   │       └── bytecode.zig
│   │
│   ├── langs/              # Templates por lenguaje
│   │   ├── lua.zig
│   │   ├── python.zig
│   │   └── lisp.zig
│   │
│   └── main.zig
│
├── examples/
│   ├── lua_to_wat.zig
│   ├── python_to_js.zig
│   └── custom_lang.zig
│
└── build.zig
```

## Métricas Objetivo

| Componente | Líneas | Estado |
|------------|--------|--------|
| Core (Op, Value, Error) | ~200 | ✅ Proto |
| Frontend (Lexer, Parser) | ~300 | ✅ Proto |
| VM | ~150 | Pendiente |
| Target WAT | ~100 | ✅ Proto |
| Target JS | ~100 | Pendiente |
| Target Bytecode | ~100 | Pendiente |
| Lang Lua | ~100 | ✅ Proto |
| Lang Python | ~100 | Pendiente |
| **Total** | **~1,200** | ~40% |

## vs Bun

| | Bun | Zid |
|--|-----|-----|
| Líneas | ~850,000 | ~1,200 |
| Lenguajes | JS/TS fijo | Cualquiera (templates) |
| Targets | JS (JSC) | WAT, JS, Bytecode, LLVM |
| Runtime | JSC | VM propia + compilación |
| Extensible | Plugins limitados | Todo es plugin |
| Propósito | Producción | Aprendizaje + DSLs |

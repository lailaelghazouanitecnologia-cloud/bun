# Zid

Templates + Op + Engine.

## Estructura

```
proto/
├── templates.zig   # Datos: tokens, nodes
├── engine.zig      # Lexer, Parser, Op, Emitter
└── main.zig        # compile(source) → wat
```

## Op Helper

```zig
// Cada opcode = 1 método
self.op.module();
self.op.func("add", params);
self.op.block("break");
self.op.loop("continue");
self.op.i32_const("42");
self.op.i32_add();
self.op.local_get("x");
self.op.br_if("break");
self.op.end();
```

## Ejemplo

```lua
function add(a, b)
    return a + b
end
```

```wat
(module
  (func $add (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.add
  )
  (export "add" (func $add))
)
```

## Bun VM vs Zid

Ver comparación detallada abajo.

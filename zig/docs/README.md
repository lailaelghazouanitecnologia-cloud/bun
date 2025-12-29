# Zid

Templates + Engine. Simple.

```
Templates (datos)  →  Engine (fijo)  →  Output
```

## Estructuras

```zig
// Data: envuelve valor
const data = Data.of(source).map(lex).map(parse).map(emit);

// Validator: opcional, simple condición
if (!validator.check(tokens)) return error;

// Compose: pipeline de funciones
const run = compose(lex, parse, emit);
const output = run(source);
```

## Proto: Lua → WAT

Ver `proto/` para ejemplo funcional.

```lua
-- input.lua
function add(a, b)
    return a + b
end
```

```wat
;; output.wat
(module
  (func $add (param $a i32) (param $b i32) (result i32)
    local.get $a
    local.get $b
    i32.add
  )
  (export "add" (func $add))
)
```

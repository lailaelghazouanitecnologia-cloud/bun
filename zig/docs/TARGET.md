# Zid - Target Final

## Visión

Framework de transpilación modular. Instala solo lo que necesitas.

```
zid add @lang/lua          # Instalar lenguaje
zid add @target/wat        # Instalar target
zid config set lua wat     # lua → wat
zid run file.lua           # Transpila y ejecuta
```

## CLI

### Instalar módulos

```bash
# Lenguajes
zid add @lang/lua
zid add @lang/python
zid add @lang/lisp

# Targets
zid add @target/wat
zid add @target/js
zid add @target/bytecode

# Ver instalados
zid list
# @lang/lua
# @target/wat

# Desinstalar
zid remove @lang/python
```

### Configurar mappings

```bash
# Sintaxis: zid config <action> [lang] [target]

# Añadir mapping
zid config add lua wat        # lua → wat
zid config add lua js         # lua → js (múltiples targets)
zid config add python js      # python → js

# Ver config
zid config list
# lua → wat, js
# python → js

# Cambiar default
zid config set lua bytecode   # lua default = bytecode

# Eliminar mapping
zid config remove lua js      # quitar lua → js
```

### Usar

```bash
# Transpila con default target
zid run file.lua              # usa config default (wat)

# Especificar target
zid run file.lua --target js

# Solo transpilar (no ejecutar)
zid build file.lua -o out.wat

# REPL
zid repl lua
```

## Estructura de Módulos

```
~/.zid/
├── modules/
│   ├── @lang/
│   │   ├── lua/
│   │   │   ├── mod.zig       # Entry point
│   │   │   ├── lexer.zig
│   │   │   ├── parser.zig
│   │   │   └── keywords.zig
│   │   └── python/
│   │       └── ...
│   │
│   └── @target/
│       ├── wat/
│       │   ├── mod.zig
│       │   └── emitter.zig
│       └── js/
│           └── ...
│
└── config.json
```

### config.json

```json
{
  "mappings": {
    "lua": {
      "default": "wat",
      "targets": ["wat", "js"]
    },
    "python": {
      "default": "js",
      "targets": ["js"]
    }
  },
  "modules": {
    "@lang/lua": "0.1.0",
    "@lang/python": "0.1.0",
    "@target/wat": "0.1.0",
    "@target/js": "0.1.0"
  }
}
```

## Módulo Interface

### @lang/* (Lenguaje)

```zig
// @lang/lua/mod.zig
pub const Lang = struct {
    pub const name = "lua";
    pub const extensions = &.{ ".lua" };

    pub const Lexer = @import("lexer.zig").Lexer;
    pub const Parser = @import("parser.zig").Parser;
    pub const Node = @import("ast.zig").Node;
};
```

### @target/* (Target)

```zig
// @target/wat/mod.zig
pub const Target = struct {
    pub const name = "wat";
    pub const extension = ".wat";

    pub const Emitter = @import("emitter.zig").Emitter;
    pub const Op = @import("op.zig").Op;
};
```

## Comptime Build

Cuando ejecutas `zid run`, genera código especializado:

```zig
// Generado en ~/.zid/cache/lua_wat.zig
const lang = @import("modules/@lang/lua/mod.zig").Lang;
const target = @import("modules/@target/wat/mod.zig").Target;

pub fn compile(source: []const u8) ![]const u8 {
    var lexer = lang.Lexer{ .source = source };
    // ... solo código necesario
}
```

## Registry (Checkers)

```zig
// Saber qué está instalado
const zid = @import("zid");

if (zid.hasLang("lua")) {
    // ...
}

if (zid.hasTarget("wat")) {
    // ...
}

// Listar
for (zid.installedLangs()) |lang| {
    std.debug.print("{s}\n", .{lang});
}
```

## User Overrides

```bash
# Override en proyecto local
zid init                      # Crea zid.json

# zid.json
{
  "overrides": {
    "@lang/lua": {
      "keywords": "./my_keywords.zig"
    },
    "@target/wat": {
      "emit_add": "./my_add.zig"
    }
  }
}
```

```zig
// my_keywords.zig - Override keywords de Lua
pub const keywords = .{
    .{ "function", .kw_function },
    .{ "end", .kw_end },
    .{ "mi_keyword", .kw_custom },  // Custom
};
```

## Publicar Módulos

```bash
# Crear módulo
zid new @lang/mylang
zid new @target/mytarget

# Estructura generada
mylang/
├── mod.zig
├── lexer.zig
├── parser.zig
└── zid.mod.json

# Publicar
zid publish
```

## Métricas

| Instalación | Tamaño |
|-------------|--------|
| Base (CLI only) | ~50KB |
| + @lang/lua | +5KB |
| + @target/wat | +3KB |
| + @target/js | +3KB |
| Full (todo) | ~100KB |

## vs Bun

| | Bun | Zid |
|--|-----|-----|
| `bun add` | npm packages | @lang/*, @target/* |
| `bunfig.toml` | config | zid.json / config.json |
| Runtime | JSC fijo | Modular (targets) |
| Lenguajes | JS/TS | Cualquiera instalado |

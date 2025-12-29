# Zid - Target Final (Comptime)

## Visión

**Zero-cost abstractions** como Bun. Comptime genera código especializado.
Si no usas Python, no está en el binario. Si no emites a JS, no existe.

```
┌─────────────────────────────────────────────────────────────┐
│                    COMPTIME                                  │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐                 │
│   │  Lang   │    │ Target  │    │Features │                 │
│   │  .lua   │    │  .wat   │    │  .vm    │                 │
│   └────┬────┘    └────┬────┘    └────┬────┘                 │
│        │              │              │                       │
│        └──────────────┴──────────────┘                       │
│                       │                                      │
│                       ▼                                      │
│            ┌─────────────────────┐                          │
│            │  SPECIALIZED BUILD  │                          │
│            │  Solo código usado  │                          │
│            └─────────────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

## Checkers & Control

### Checkers Comptime

```zig
// Saber qué está registrado en comptime
pub fn Registry(comptime config: Config) type {
    return struct {
        // Checkers - verificar qué existe
        pub const has_lexer = config.lang != .none;
        pub const has_parser = config.lang != .none;
        pub const has_vm = config.vm;
        pub const has_optimizer = config.optimize;

        // Qué targets están disponibles
        pub const targets = config.targets;
        pub fn hasTarget(comptime t: TargetKind) bool {
            inline for (targets) |target| {
                if (target == t) return true;
            }
            return false;
        }

        // Qué features están activas
        pub const features = config.features;
        pub fn hasFeature(comptime f: Feature) bool {
            inline for (features) |feat| {
                if (feat == f) return true;
            }
            return false;
        }
    };
}

// Uso en código
const reg = Registry(config);
if (reg.has_vm) {
    // Código VM - solo existe si vm = true
}
if (reg.hasTarget(.wat)) {
    // Código WAT - solo si target incluye .wat
}
```

### User Overrides

```zig
// Usuario puede override cualquier parte del flujo
const Compiler = zid.Compiler(.{
    .lang = .lua,
    .target = .wat,

    // Override lexer completo
    .lexer = MyCustomLexer,

    // Override solo keywords
    .keywords = my_keywords,

    // Override parser parcial
    .parse_expr = myParseExpr,

    // Override emitter para un opcode específico
    .emit_add = myEmitAdd,

    // Hook en el pipeline
    .after_parse = myTransform,
    .before_emit = myOptimize,
});
```

### Override Granular

```zig
// Override a nivel de opcode
const MyTarget = zid.Target(.wat, .{
    // Override solo i32.add
    .add = struct {
        pub fn emit(op: *Op) void {
            op.raw(";; custom add\n");
            op.raw("i32.add\n");
        }
    }.emit,

    // El resto usa default
});

// Override a nivel de nodo
const MyParser = zid.Parser(.lua, .{
    // Override solo parsing de if
    .parse_if = struct {
        pub fn parse(p: *Parser) !Node {
            // Mi lógica custom para if
        }
    }.parse,
});
```

### Pipeline Hooks

```zig
const Compiler = zid.Compiler(.{
    .lang = .lua,
    .target = .wat,

    // Hooks en cada fase
    .hooks = .{
        .on_token = logToken,        // Cada token
        .on_node = validateNode,     // Cada nodo AST
        .on_emit = trackEmit,        // Cada emisión
        .on_error = handleError,     // Cada error
    },

    // Transformaciones
    .transforms = &.{
        deadCodeElimination,
        constantFolding,
        inlineSmallFunctions,
    },

    // Validaciones
    .validators = &.{
        checkTypes,
        checkScopes,
        checkUnused,
    },
});
```

### Registro Dinámico (Opcional)

```zig
// Para casos donde necesitas runtime flexibility
pub const DynamicRegistry = struct {
    lexers: std.StringHashMap(LexerFn),
    parsers: std.StringHashMap(ParserFn),
    emitters: std.StringHashMap(EmitterFn),

    pub fn register(self: *@This(), name: []const u8, component: anytype) void {
        // Registrar en runtime
    }

    pub fn has(self: *@This(), name: []const u8) bool {
        return self.lexers.contains(name) or
               self.parsers.contains(name) or
               self.emitters.contains(name);
    }
};

// Combinar comptime + runtime
const compiler = Compiler(.{
    .lang = .lua,
    .dynamic = true,  // Habilita registro runtime
});
compiler.registry.register("my_transform", myTransform);
```

## Arquitectura Comptime

### 1. Selección en Comptime (no runtime)

```zig
// build.zig - Usuario configura qué necesita
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "my_transpiler",
        .root_source_file = .{ .path = "main.zig" },
    });

    // Solo compila lo que necesitas
    const options = b.addOptions();
    options.addOption(Lang, "lang", .lua);      // Solo Lua
    options.addOption(Target, "target", .wat);  // Solo WAT
    options.addOption(bool, "vm", false);       // Sin VM

    exe.addOptions("config", options);
}
```

### 2. Generación Especializada

```zig
// zid.zig - Genera tipos especializados en comptime
const config = @import("config");

// Solo existe el lexer de Lua si lang = .lua
pub const Lexer = switch (config.lang) {
    .lua => @import("langs/lua/lexer.zig").Lexer,
    .python => @import("langs/python/lexer.zig").Lexer,
    .lisp => @import("langs/lisp/lexer.zig").Lexer,
};

// Solo existe el emitter de WAT si target = .wat
pub const Emitter = switch (config.target) {
    .wat => @import("targets/wat.zig").Emitter,
    .js => @import("targets/js.zig").Emitter,
    .bytecode => @import("targets/bytecode.zig").Emitter,
};

// VM solo existe si vm = true
pub const VM = if (config.vm)
    @import("runtime/vm.zig").VM
else
    void;
```

### 3. Zero-Cost Op

```zig
// Op especializado - sin vtables, todo inline
pub fn Op(comptime TargetType: type) type {
    return struct {
        target: *TargetType,

        // Todas las funciones son inline
        pub inline fn add(self: @This()) void {
            self.target.add();
        }

        pub inline fn local_get(self: @This(), name: []const u8) void {
            self.target.local_get(name);
        }

        pub inline fn call(self: @This(), name: []const u8) void {
            self.target.call(name);
        }
    };
}

// Uso - cero overhead
var wat_target = WatTarget.init(&output);
var op = Op(WatTarget){ .target = &wat_target };
op.add();  // Inline directo a: output.append("i32.add\n")
```

### 4. Templates Comptime

```zig
// langs/lua.zig - Todo resuelto en comptime
pub const keywords = comptimeStringMap(TokenKind, .{
    .{ "function", .kw_function },
    .{ "end", .kw_end },
    .{ "return", .kw_return },
    .{ "local", .kw_local },
    .{ "while", .kw_while },
    .{ "if", .kw_if },
});

pub const Lexer = struct {
    source: []const u8,
    pos: u32 = 0,

    // Lookup en O(1) con perfect hash generado en comptime
    pub inline fn checkKeyword(self: *@This(), text: []const u8) TokenKind {
        return keywords.get(text) orelse .ident;
    }
};
```

## Comparación: Dinámico vs Comptime

### Dinámico (lento)

```zig
// Runtime dispatch - LENTO
const Emitter = struct {
    vtable: *const VTable,  // Indirección

    pub fn add(self: *@This()) void {
        self.vtable.add(self);  // Call indirecto
    }
};

// Cada llamada: load vtable → load fn ptr → call
```

### Comptime (rápido, como Bun)

```zig
// Static dispatch - RÁPIDO
pub fn Emitter(comptime Target: type) type {
    return struct {
        target: Target,

        pub inline fn add(self: *@This()) void {
            self.target.add();  // Inline directo
        }
    };
}

// Cada llamada: código inline, sin indirección
```

## Tamaño del Binario

```
Configuración: Lua → WAT (sin VM)
├── Lexer Lua:     ~2KB
├── Parser Lua:    ~4KB
├── Emitter WAT:   ~3KB
└── Total:         ~9KB

Configuración: Lua + Python → WAT + JS + VM
├── Lexer Lua:     ~2KB
├── Lexer Python:  ~3KB
├── Parser Lua:    ~4KB
├── Parser Python: ~5KB
├── Emitter WAT:   ~3KB
├── Emitter JS:    ~3KB
├── VM:            ~8KB
└── Total:         ~28KB

// Código no usado = no existe en binario
```

## Pipeline Comptime

```zig
// Pipeline especializado generado en comptime
pub fn Pipeline(comptime config: Config) type {
    return struct {
        // Solo campos necesarios
        lexer: if (config.needs_lexer) Lexer(config.lang) else void,
        parser: if (config.needs_parser) Parser(config.lang) else void,
        emitter: if (config.needs_emit) Emitter(config.target) else void,
        vm: if (config.needs_vm) VM else void,

        pub fn run(self: *@This(), source: []const u8) !Result {
            // Código especializado, sin branches innecesarios
            if (config.needs_lexer) {
                const tokens = self.lexer.lex(source);
                if (config.needs_parser) {
                    const ast = self.parser.parse(tokens);
                    if (config.needs_emit) {
                        return self.emitter.emit(ast);
                    }
                    if (config.needs_vm) {
                        return self.vm.run(ast);
                    }
                }
            }
        }
    };
}
```

## API Final

```zig
// main.zig del usuario
const zid = @import("zid");

// Tipo especializado en comptime
const Compiler = zid.Compiler(.{
    .lang = .lua,
    .target = .wat,
});

pub fn main() !void {
    var compiler = Compiler.init(allocator);
    const wat = try compiler.compile(source);
    // wat es []const u8 listo para escribir
}
```

## Build Configurations

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Transpilador Lua → WAT
    _ = addZid(b, "lua2wat", .{ .lang = .lua, .target = .wat });

    // Transpilador Python → JS
    _ = addZid(b, "py2js", .{ .lang = .python, .target = .js });

    // Intérprete Lua con VM
    _ = addZid(b, "lua_vm", .{ .lang = .lua, .target = .bytecode, .vm = true });

    // Multi-lenguaje (binario más grande)
    _ = addZid(b, "multi", .{
        .langs = &.{ .lua, .python, .lisp },
        .targets = &.{ .wat, .js },
        .vm = true,
    });
}

fn addZid(b: *std.Build, name: []const u8, config: Config) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{ .name = name, ... });

    const options = b.addOptions();
    inline for (std.meta.fields(Config)) |field| {
        options.addOption(field.type, field.name, @field(config, field.name));
    }
    exe.addOptions("config", options);

    return exe;
}
```

## Estructura Final

```
zid/
├── src/
│   ├── zid.zig              # Entry point con comptime switch
│   │
│   ├── core/
│   │   ├── op.zig           # Op(comptime Target) - inline
│   │   ├── value.zig        # Tagged union optimizado
│   │   └── ast.zig          # AST compacto
│   │
│   ├── langs/               # Cada lang = módulo independiente
│   │   ├── lua/
│   │   │   ├── lexer.zig    # Lexer especializado Lua
│   │   │   ├── parser.zig   # Parser especializado Lua
│   │   │   └── keywords.zig # ComptimeStringMap
│   │   ├── python/
│   │   └── lisp/
│   │
│   ├── targets/             # Cada target = módulo independiente
│   │   ├── wat.zig
│   │   ├── js.zig
│   │   ├── bytecode.zig
│   │   └── llvm.zig
│   │
│   └── runtime/             # Solo si vm = true
│       └── vm.zig
│
└── build.zig                # Configuración comptime
```

## Métricas

| Config | Código Compilado | Binario |
|--------|-----------------|---------|
| lua → wat | ~400 líneas | ~9KB |
| lua → wat + vm | ~550 líneas | ~17KB |
| lua + python → wat + js | ~700 líneas | ~25KB |
| todo | ~1,200 líneas | ~40KB |

## vs Bun

| Aspecto | Bun | Zid |
|---------|-----|-----|
| Dispatch | Static (comptime) | Static (comptime) |
| Código no usado | No existe | No existe |
| Vtables | No | No |
| Inline | Sí | Sí |
| Perfect hash | Sí (keywords) | Sí (keywords) |
| Tamaño | ~15MB (todo) | ~9KB-40KB (configurable) |

**Mismo patrón que Bun**: comptime genera código especializado, sin overhead de runtime.

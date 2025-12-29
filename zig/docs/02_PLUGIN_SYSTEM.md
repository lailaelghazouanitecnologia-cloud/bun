# Modulo 02: Plugin System

## Proposito

El sistema de plugins es el corazon de Zid. Permite cargar, registrar y ejecutar plugins que extienden la funcionalidad del runtime.

## Responsabilidades

- Registro global de plugins
- Carga dinamica de plugins
- Validacion de interfaces
- Ciclo de vida de plugins
- Comunicacion entre plugins

## Tipos de Plugins

| Tipo | Interface | Proposito |
|------|-----------|-----------|
| Language | `LanguagePlugin` | Parsear lenguajes de entrada |
| Target | `TargetPlugin` | Emitir a lenguajes de salida |
| Transform | `TransformPlugin` | Transformar AST |
| Loader | `LoaderPlugin` | Cargar tipos de archivo |
| Command | `CommandPlugin` | Comandos CLI |

## Estructura Propuesta

```zig
// zig/src/plugin/mod.zig
pub const Registry = @import("registry.zig");
pub const Loader = @import("loader.zig");
pub const Interface = @import("interface.zig");
pub const Lifecycle = @import("lifecycle.zig");
```

## Interfaces

### Plugin Base

```zig
pub const Plugin = struct {
    name: []const u8,
    version: Version,
    kind: PluginKind,

    // Lifecycle
    init_fn: ?fn(*PluginContext) Error!void,
    deinit_fn: ?fn(*PluginContext) void,

    // Metadata
    dependencies: []const []const u8,
    provides: []const []const u8,
};

pub const PluginKind = enum {
    language,
    target,
    transform,
    loader,
    command,
};

pub const Version = struct {
    major: u16,
    minor: u16,
    patch: u16,
};
```

### Registry

```zig
pub const Registry = struct {
    plugins: std.StringHashMap(*Plugin),
    languages: std.StringHashMap(*LanguagePlugin),
    targets: std.StringHashMap(*TargetPlugin),
    transforms: std.ArrayList(*TransformPlugin),
    loaders: std.StringHashMap(*LoaderPlugin),
    commands: std.StringHashMap(*CommandPlugin),

    pub fn init(allocator: Allocator) Registry;
    pub fn deinit(self: *Registry) void;

    pub fn register(self: *Registry, plugin: *Plugin) Error!void;
    pub fn unregister(self: *Registry, name: []const u8) void;

    pub fn getLanguage(self: *Registry, ext: []const u8) ?*LanguagePlugin;
    pub fn getTarget(self: *Registry, name: []const u8) ?*TargetPlugin;
    pub fn getLoader(self: *Registry, ext: []const u8) ?*LoaderPlugin;
    pub fn getCommand(self: *Registry, name: []const u8) ?*CommandPlugin;
};
```

### LanguagePlugin

```zig
pub const LanguagePlugin = struct {
    base: Plugin,
    extensions: []const []const u8,  // [".ts", ".tsx"]

    // Lexer
    tokenize: fn(source: []const u8, ctx: *TokenizeContext) Error!TokenList,

    // Parser
    parse: fn(tokens: TokenList, ctx: *ParseContext) Error!*AST,

    // Optional: Semantic analysis
    analyze: ?fn(ast: *AST, ctx: *AnalyzeContext) Error!void,
};

pub const TokenList = struct {
    tokens: []Token,

    pub const Token = struct {
        kind: u32,
        start: u32,
        end: u32,
        value: ?[]const u8,
    };
};
```

### TargetPlugin

```zig
pub const TargetPlugin = struct {
    base: Plugin,
    name: []const u8,  // "javascript", "python", "rust"

    // Emitter
    emit: fn(ast: *AST, ctx: *EmitContext) Error![]const u8,

    // Optional: Source maps
    generate_sourcemap: ?fn(ast: *AST) Error!SourceMap,

    // Optional: Post-processing
    post_process: ?fn(output: []const u8) Error![]const u8,
};
```

### TransformPlugin

```zig
pub const TransformPlugin = struct {
    base: Plugin,
    priority: i32,  // Orden de ejecucion

    // Transformer
    transform: fn(ast: *AST, ctx: *TransformContext) Error!*AST,

    // Filter: Solo aplicar a ciertos nodos
    filter: ?fn(node: *ASTNode) bool,
};
```

### LoaderPlugin

```zig
pub const LoaderPlugin = struct {
    base: Plugin,
    extensions: []const []const u8,
    mime_types: []const []const u8,

    // Load file content
    load: fn(path: []const u8, ctx: *LoadContext) Error!LoadResult,

    pub const LoadResult = union(enum) {
        source: []const u8,      // Codigo fuente
        binary: []const u8,      // Datos binarios
        reference: []const u8,   // Path/URL
    };
};
```

### CommandPlugin

```zig
pub const CommandPlugin = struct {
    base: Plugin,
    name: []const u8,        // "build", "run", "test"
    description: []const u8,
    usage: []const u8,

    // Execute command
    execute: fn(args: []const []const u8, ctx: *CommandContext) Error!i32,

    // Tab completion
    complete: ?fn(partial: []const u8) []const []const u8,
};
```

## Carga de Plugins

### Desde Configuracion

```zig
// zid.config.zig o zid.config.ts
pub const plugins = .{
    .languages = .{
        .typescript = "@zid/lang-typescript",
        .python = "zid-lang-python",
        .custom = "./plugins/mylang.zig",
    },
    .targets = .{
        .javascript = "@zid/target-js",
        .python = "@zid/target-python",
    },
};
```

### Programatico

```zig
var registry = Registry.init(allocator);
defer registry.deinit();

// Registrar plugin built-in
try registry.register(&typescript_plugin);

// Cargar plugin desde archivo
const custom = try PluginLoader.load("./plugins/mylang.so");
try registry.register(custom);
```

## Dependencias

- **Core**: Tipos base, memoria, errores

## Estimacion

- **Lineas**: ~3,000
- **Complejidad**: Media-Alta
- **Prioridad**: CRITICA

## Checklist Implementacion

- [ ] `interface.zig` - Definicion de interfaces
- [ ] `registry.zig` - Registro global
- [ ] `loader.zig` - Carga dinamica
- [ ] `lifecycle.zig` - Init/deinit
- [ ] `context.zig` - Contextos de ejecucion
- [ ] `mod.zig` - Re-exports

## Notas

- Los plugins pueden ser **estaticos** (compilados) o **dinamicos** (cargados en runtime)
- El sistema debe validar que las interfaces son compatibles
- Manejar errores de carga gracefully

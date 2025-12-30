# Zid Architecture

## Visión General

Zid sigue patrones de diseño inspirados en Bun: un binario monolítico, orientación a rendimiento, y APIs que minimizan allocaciones.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ZID ARCHITECTURE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐          │
│  │    CLI     │   │ Toolchain  │   │  Capsules  │   │  Patches   │          │
│  │  Commands  │   │  Manager   │   │   System   │   │   System   │          │
│  └─────┬──────┘   └─────┬──────┘   └─────┬──────┘   └─────┬──────┘          │
│        │                │                │                │                  │
│        └────────────────┴────────────────┴────────────────┘                  │
│                                   │                                          │
│                     ┌─────────────▼─────────────┐                            │
│                     │      Core Patterns         │                           │
│                     │   (Maybe, Dispatch, etc)   │                           │
│                     └─────────────┬─────────────┘                            │
│                                   │                                          │
│        ┌─────────────────┬────────┴────────┬─────────────────┐               │
│        │                 │                 │                 │               │
│  ┌─────▼─────┐    ┌──────▼──────┐   ┌──────▼──────┐   ┌──────▼──────┐       │
│  │  Output   │    │   Strings   │   │     FS      │   │ Environment │       │
│  │ (colors)  │    │ (utilities) │   │ (filesystem)│   │  (platform) │       │
│  └───────────┘    └─────────────┘   └─────────────┘   └─────────────┘       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Estructura de Módulos

### 1. Root Module (`zid.zig`)

Punto de entrada que re-exporta todas las APIs públicas:

```zig
const zid = @import("zid");

// Core patterns
const result = zid.Maybe(Config);
const log = zid.ScopedLog("my-module");

// Subsystems
zid.toolchain.install("bun@latest");
zid.capsules.add("webgpu");
```

### 2. Core Patterns (`misc/`)

Patrones fundamentales usados en todo el codebase:

```
misc/
├── maybe.zig       # Maybe(T) - Result type con contexto
├── dispatch.zig    # Dispatch comptime para opcodes
├── buffers.zig     # Buffers threadlocal pre-allocated
├── state.zig       # State machines basadas en unions
├── logger.zig      # Logging estructurado
├── options.zig     # Target, OptLevel, BuildOptions
├── cache.zig       # FileCache, LruCache, ContentCache
├── progress.zig    # Progress bars y spinners
└── collections/
    ├── list.zig    # SmallList (u32 indices)
    └── pool.zig    # HivePool (stable pointers)
```

#### Maybe(T) - Error Handling

```zig
pub fn Maybe(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: Error,
    };
}

pub const Error = struct {
    code: Code,
    message: []const u8,
    path: []const u8 = "",
    step: Step = .unknown,

    pub const Code = enum(u16) {
        ok = 0,
        not_found = 100,
        permission_denied = 101,
        parse_error = 103,
        network_error = 150,
        // ...
    };
};
```

**Por qué no `!T`?** Porque `Maybe` incluye:
- Mensaje de error legible
- Path del archivo afectado
- Paso en el que falló
- Código numérico para matching

#### Dispatch - Comptime Opcodes

Para crear VMs o parsers eficientes:

```zig
pub fn Dispatch(comptime Op: type) type {
    return struct {
        pub fn dispatch(op: Op, ctx: anytype) void {
            switch (op) {
                inline else => |tag| {
                    const handler = @field(ctx, @tagName(tag));
                    handler(ctx);
                }
            }
        }
    };
}
```

### 3. CLI Commands (`cli/`)

Cada comando es un módulo separado:

```
cli/
├── cli.zig         # Dispatcher principal
├── install.zig     # zid install <tool>
├── add.zig         # zid add <app>
├── capsule.zig     # zid capsule <subcmd>
├── update.zig      # zid update
├── patch.zig       # zid patch <subcmd>
└── help.zig        # zid help
```

```zig
// cli.zig - Command dispatch
pub fn run(args: []const []const u8) !void {
    const cmd = parseCommand(args[0]);
    switch (cmd) {
        .install => install.run(args[1..]),
        .capsule => capsule.run(args[1..]),
        // ...
    }
}
```

### 4. Toolchain Manager (`toolchain/`)

Gestión de compiladores y runtimes:

```
toolchain/
├── toolchain.zig   # API pública
├── versions.zig    # Semver parsing
├── registry.zig    # Tool definitions (URLs, formats)
├── custom.zig      # Custom toolchains (toolchains.json)
├── resolver.zig    # Conflict detection
├── downloader.zig  # HTTP + progress
├── extractor.zig   # tar.gz, tar.xz, zip
└── installer.zig   # Orchestration
```

#### Flujo de Instalación

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Parse      │────▶│   Resolve    │────▶│   Download   │
│   "bun@1.0"  │     │   URL        │     │   + Progress │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Symlink    │◀────│   Install    │◀────│   Extract    │
│   ~/.zid/bin │     │   Validate   │     │   Archive    │
└──────────────┘     └──────────────┘     └──────────────┘
```

#### Conflict Detection

```zig
// resolver.zig
pub fn checkConflict(tool: []const u8) ?Conflict {
    const system_path = findSystemCommand(tool);
    const zid_path = getZidPath(tool);

    if (system_path != null and zid_path != null) {
        return Conflict{
            .tool = tool,
            .system = system_path.?,
            .zid = zid_path.?,
        };
    }
    return null;
}
```

### 5. Capsules System (`capsules/`)

Sistema de librería de módulos:

```
capsules/
├── capsules.zig    # Manager API
├── registry.zig    # Built-in capsule definitions
├── fetcher.zig     # Download externals
├── manifest.zig    # capsule.json parsing
├── paths.zig       # Path resolution
├── shell.zig       # Shell environment config
└── integration.zig # Build system integration
```

#### Built-in vs External

```zig
pub const CapsuleKind = enum {
    intern,   // Bundled con zid
    extern_,  // Descargadas del registry
};

// intern capsules: ~/.zid/capsules/intern/webgpu/
// extern capsules: ~/.zid/capsules/extern/my-lib/
```

### 6. Patches System (`patches/`)

Correcciones urgentes sin actualizar todo zid:

```
patches/
├── patches.zig     # Manager API
├── registry.zig    # Fetch available patches
└── applicator.zig  # Apply patches
```

**Flujo de patches:**
1. Al iniciar zid, consulta patches disponibles
2. Si hay patches pendientes, los aplica
3. Registra en `~/.zid/patches/applied.json`

### 7. API Module (`api/`)

API pública para scripts Zig:

```
api/
├── api.zig         # Re-exports
├── fs.zig          # Filesystem operations
├── shell.zig       # Shell execution
├── http.zig        # HTTP client
├── search.zig      # Glob/grep
├── template.zig    # Project templates
└── json.zig        # JSON utilities
```

```zig
// Uso en script externo
const zid = @import("zid");

pub fn main() !void {
    // Todos los submódulos disponibles
    const content = try zid.api.fs.read(allocator, "file.txt");
    const result = try zid.api.shell.exec(allocator, "ls", .{});
    const resp = try zid.api.http.get(allocator, "https://...");
}
```

### 8. Framework (`framework/`)

API para crear transpilers:

```
framework/
├── framework.zig   # Re-exports
├── ir.zig          # Intermediate Representation
├── pipeline.zig    # Compilation pipeline
└── metadata.zig    # Source metadata & diagnostics
```

```zig
// Definir un transpiler
const pipeline = Pipeline{
    .name = "lua-to-wasm",
    .stages = &[_]Stage{
        .parse,
        .transform,
        .codegen,
    },
};
```

## Patrones de Diseño

### 1. Zero Allocation Paths

Preferir APIs que no allocan:

```zig
// ✅ BIEN - No alloca
pub fn basename(path: []const u8) []const u8 {
    const idx = std.mem.lastIndexOfScalar(u8, path, '/');
    return if (idx) |i| path[i + 1 ..] else path;
}

// ❌ EVITAR - Alloca innecesariamente
pub fn basename(alloc: Allocator, path: []const u8) ![]u8 {
    return try alloc.dupe(u8, extractBasename(path));
}
```

### 2. Comptime Dispatch

Usar comptime para eliminar overhead:

```zig
// El switch se resuelve en comptime
inline else => |tag| {
    const handler = @field(handlers, @tagName(tag));
    handler();
}
```

### 3. Threadlocal Buffers

Evitar allocaciones repetidas:

```zig
threadlocal var path_buf: [4096]u8 = undefined;

pub fn joinPath(parts: []const []const u8) []const u8 {
    // Usa buffer threadlocal, no alloca
    var pos: usize = 0;
    for (parts) |part| {
        @memcpy(path_buf[pos..][0..part.len], part);
        pos += part.len;
    }
    return path_buf[0..pos];
}
```

### 4. Tagged Unions para State

```zig
pub const DownloadState = union(enum) {
    idle,
    connecting: struct { url: []const u8 },
    downloading: struct { progress: u64, total: u64 },
    extracting,
    done: struct { path: []const u8 },
    failed: Error,
};
```

## Flujo de Datos

### Instalación de Toolchain

```
User: zid install bun@1.1.0
         │
         ▼
    ┌─────────────────┐
    │ cli/install.zig │  Parse args
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │ toolchain/      │  Check if already installed
    │ installer.zig   │
    └────────┬────────┘
             │ Not installed
             ▼
    ┌─────────────────┐
    │ toolchain/      │  Build download URL
    │ registry.zig    │  (or custom.zig)
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │ toolchain/      │  Check PATH conflicts
    │ resolver.zig    │
    └────────┬────────┘
             │ No conflict (or user confirmed)
             ▼
    ┌─────────────────┐
    │ toolchain/      │  HTTP GET + progress
    │ downloader.zig  │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │ toolchain/      │  tar.gz / zip
    │ extractor.zig   │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────┐
    │ toolchain/      │  Create symlink
    │ installer.zig   │  ~/.zid/bin/bun
    └────────┬────────┘
             │
             ▼
    Output: ✅ bun 1.1.0 installed
```

## Estructura de Directorios

```
~/.zid/
├── bin/                  # Symlinks activos
│   ├── bun -> ../toolchains/bun/1.1.0/bun
│   └── zig -> ../toolchains/zig/0.14.0/zig
│
├── toolchains/           # Versiones instaladas
│   ├── bun/
│   │   ├── 1.0.0/
│   │   └── 1.1.0/
│   └── zig/
│       └── 0.14.0/
│
├── capsules/             # Librería de módulos
│   ├── intern/           # Built-in
│   └── extern/           # Downloaded
│
├── patches/              # Parches
│   ├── applied.json
│   └── scripts/
│
├── apps/                 # Apps registradas
│
├── cache/                # Downloads cache
│
├── toolchains.json       # Custom toolchains (opcional)
└── config.json           # Configuración global
```

## Consideraciones de Rendimiento

### 1. Startup Time

- No cargar módulos innecesarios
- Lazy loading de subsistemas
- Comptime donde sea posible

### 2. Memory

- Preferir slices sobre allocaciones
- Threadlocal buffers para paths
- SmallList con u32 indices (no punteros)

### 3. I/O

- Async HTTP downloads
- Progress sin bloquear
- Buffered file I/O

## Extensibilidad

### Custom Toolchains

```json
// ~/.zid/toolchains.json
{
  "gleam": {
    "url_template": "https://github.com/gleam-lang/gleam/...",
    "archive": "tar_gz",
    "binary": "gleam"
  }
}
```

### Custom Capsules

```json
// capsule.json
{
  "name": "my-lib",
  "version": "1.0.0",
  "dependencies": ["sqlite"],
  "build": {
    "src_dir": "src"
  }
}
```

# Zid

**Universal Development Toolkit** - Un solo binario para gestionar toolchains, apps, y crear transpilers.

```
┌─────────────────────────────────────────────────────────────────┐
│  ZID = Toolchain Manager + Apps Registry + Transpiler Framework │
└─────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    ┌─────────┐         ┌─────────┐         ┌─────────────┐
    │ zig     │         │ mi-tool │         │ lua → wasm  │
    │ rust    │         │ scripts │         │ dsl → rust  │
    │ bun     │         │ builds  │         │ custom lang │
    │ node    │         └─────────┘         └─────────────┘
    │ go      │
    └─────────┘
```

## El Plan

### 1. Toolchain Manager
Descargar e instalar compiladores/runtimes automáticamente:

```bash
zid install bun              # Descarga bun latest
zid install zig@0.13.0       # Versión específica
zid install rust node go     # Múltiples
zid list                     # Ver instalados
zid use bun@1.0.0            # Cambiar versión activa
zid remove rust@1.75.0       # Eliminar
```

**Toolchains soportados:**
| Tool | Source | Formato |
|------|--------|---------|
| `bun` | github.com/oven-sh/bun | tar.gz |
| `zig` | ziglang.org | tar.xz |
| `rust` | rustup.rs | installer |
| `node` | nodejs.org | tar.gz |
| `go` | go.dev | tar.gz |
| `deno` | github.com/denoland/deno | zip |

### 2. Apps Registry
Tus programas se convierten en comandos directos:

```bash
zid add ./my-script.sh       # Registrar script
zid add ./build-tool         # Registrar binario
zid my-script                # Ejecutar directamente (sin "zid run")
zid remove my-script         # Eliminar del registry
```

### 3. Transpiler Framework
API para crear transpilers con Pipeline + Metadata:

```bash
zid init lua-to-wasm         # Crear proyecto transpiler
zid build                    # Compilar
```

## Estado Actual

### Implementado (misc/)

Core patterns siguiendo arquitectura de Bun:

| Módulo | Descripción | Estado |
|--------|-------------|--------|
| `maybe.zig` | `Maybe(T)` error union con contexto | ✅ |
| `dispatch.zig` | Opcode dispatch comptime (VM-like) | ✅ |
| `buffers.zig` | Threadlocal buffers pre-allocated | ✅ |
| `state.zig` | State machines basadas en unions | ✅ |
| `logger.zig` | Logging estructurado + Location | ✅ |
| `options.zig` | Target, OptLevel, BuildOptions | ✅ |
| `cache.zig` | FileCache, ContentCache, LruCache | ✅ |
| `progress.zig` | ProgressBar, Spinner, TaskTracker | ✅ |
| `collections/` | SmallList, HivePool | ✅ |

### Por Implementar

```
[ ] toolchain/downloader.zig   - HTTP download con progress
[ ] toolchain/extractor.zig    - Descomprimir tar.gz/zip/xz
[ ] toolchain/registry.zig     - URLs y versiones por tool
[ ] toolchain/versions.zig     - Parsing de versiones semver
[ ] toolchain/installer.zig    - Orquestador de instalación
[ ] apps/registry.zig          - Base de datos de apps
[ ] apps/runner.zig            - Ejecutor de apps
[ ] framework/pipeline.zig     - Pipeline de transpilación
[ ] framework/ir.zig           - Intermediate representation
```

## Arquitectura

```
src/
├── main.zig              # Entry point
├── zid.zig               # Root module (como bun.zig)
├── env.zig               # Platform detection
├── output.zig            # Terminal I/O con colores
├── strings.zig           # String utilities
├── fs.zig                # Filesystem operations
├── cli.zig               # Command dispatcher
│
├── cli/                  # CLI Commands
│   ├── install.zig       # zid install <tool>
│   ├── add.zig           # zid add <app>
│   ├── init.zig          # zid init <project>
│   ├── build.zig         # zid build
│   └── help.zig          # zid help
│
├── misc/                 # Core Patterns (VM-like, Bun style)
│   ├── maybe.zig         # Maybe(T) - Result type
│   ├── dispatch.zig      # Comptime opcode dispatch
│   ├── buffers.zig       # Threadlocal buffer pool
│   ├── state.zig         # Union-based state machines
│   ├── logger.zig        # Structured logging
│   ├── options.zig       # Configuration types
│   ├── cache.zig         # Multi-layer caching
│   ├── progress.zig      # Progress tracking
│   └── collections/      # Memory-efficient collections
│       ├── list.zig      # SmallList (u32 bounds)
│       └── pool.zig      # HivePool (stable pointers)
│
├── toolchain/            # Toolchain Manager
│   └── toolchain.zig
│
├── apps/                 # Apps Registry
│   └── apps.zig
│
└── framework/            # Transpiler Framework
    ├── framework.zig
    ├── metadata.zig
    └── pipeline.zig
```

## Patrones Core (de Bun)

### Maybe(T) - Error Handling
```zig
const zid = @import("zid");

fn readConfig(path: []const u8) zid.Maybe(Config) {
    const file = std.fs.openFile(path, .{}) catch |e| {
        return zid.fail(Config, e, .read_file, path);
    };
    // ...
    return zid.ok(Config, config);
}

// Uso
switch (readConfig("zid.json")) {
    .ok => |cfg| useConfig(cfg),
    .err => |e| e.print(),
}
```

### Progress Tracking
```zig
var progress = zid.Progress{};
const root = progress.start("Installing", 3);

const download = root.start("Downloading", file_size);
// ... download loop
download.completeOne();
download.end();

root.end();
```

### Scoped Logging
```zig
const log = zid.ScopedLog("toolchain");

// Solo imprime si ZID_DEBUG_TOOLCHAIN=1
log.debug("downloading {s}", .{url});
log.err("failed: {s}", .{msg});
```

## Próximos Pasos

1. **Downloader**: HTTP client con progress callback
2. **Extractor**: Soportar tar.gz, tar.xz, zip
3. **Registry**: JSON/TOML con URLs de releases
4. **Install command**: Orquestar download → extract → link

## Directorios

```
~/.zid/
├── bin/                  # Symlinks a versiones activas
│   ├── bun -> ../toolchains/bun/1.1.0/bun
│   ├── zig -> ../toolchains/zig/0.13.0/zig
│   └── my-app -> ../apps/my-app/run
│
├── toolchains/           # Versiones instaladas
│   ├── bun/
│   │   ├── 1.0.0/
│   │   └── 1.1.0/
│   ├── zig/
│   │   └── 0.13.0/
│   └── ...
│
├── apps/                 # Apps registradas
│   └── my-app/
│
├── cache/                # Downloads cache
│
└── config.json           # Configuración global
```

## Build

```bash
# Compilar
zig build -Doptimize=ReleaseFast

# Output
./zig-out/bin/zid

# Desarrollo
zig build run -- help
zig build test
```

## Licencia

MIT

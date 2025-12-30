# Zid

**Universal Development Toolkit** - Un solo binario para gestionar toolchains, apps, capsules, y crear transpilers.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ZID = Toolchain Manager + Apps Registry + Capsules + Transpiler Framework  │
└─────────────────────────────────────────────────────────────────────────────┘
         │                    │                │                  │
         ▼                    ▼                ▼                  ▼
    ┌─────────┐         ┌─────────┐      ┌──────────┐      ┌─────────────┐
    │ zig     │         │ mi-tool │      │ webgpu   │      │ lua → wasm  │
    │ rust    │         │ scripts │      │ wasm     │      │ dsl → rust  │
    │ bun     │         │ builds  │      │ sqlite   │      │ custom lang │
    │ node    │         └─────────┘      └──────────┘      └─────────────┘
    │ go      │
    │ deno    │
    └─────────┘
```

## Instalación

```bash
# Build from source
zig build -Doptimize=ReleaseFast

# Add to PATH
export PATH="$HOME/.zid/bin:$PATH"
```

## Comandos

### 1. Toolchain Manager

Descargar e instalar compiladores/runtimes automáticamente:

```bash
zid install bun              # Descarga bun latest
zid install zig@0.13.0       # Versión específica
zid install rust node go     # Múltiples
zid list                     # Ver instalados
zid use bun@1.0.0            # Cambiar versión activa
zid uninstall rust@1.75.0    # Eliminar
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

### 3. Capsules (Library System)

Librería de módulos reutilizables (como WebGPU bindings, WASM runtime, etc.):

```bash
zid capsule add webgpu       # Instalar capsule
zid capsule add sqlite       # Otra capsule
zid capsule list             # Ver instaladas
zid capsule info webgpu      # Detalles
zid capsule remove webgpu    # Eliminar
zid capsule available        # Ver disponibles
```

**Capsules disponibles (built-in):**
| Capsule | Descripción |
|---------|-------------|
| `webgpu` | WebGPU bindings para GPU computing |
| `wasm` | WebAssembly runtime integration |
| `sqlite` | SQLite database bindings |
| `crypto` | Extended cryptographic operations |
| `http2` | HTTP/2 protocol support |
| `image` | Image encoding/decoding (PNG, JPEG, WebP) |

**Tipos de capsules:**
- `intern/` - Built-in, bundled con zid
- `extern/` - External, descargadas del registry

### 4. Self-Update

Actualizar zid sin perder configuración:

```bash
zid update                   # Actualizar a la última versión
zid update --check           # Solo verificar si hay updates
zid update 0.2.0             # Actualizar a versión específica
```

### 5. Patches (Urgent Fixes)

Sistema de parches para correcciones urgentes:

```bash
zid patch check              # Ver parches disponibles
zid patch apply              # Aplicar todos los parches
zid patch list               # Ver parches aplicados
zid patch rollback <id>      # Revertir un parche
```

### 6. Transpiler Framework

API para crear transpilers con Pipeline + Metadata:

```bash
zid init lua-to-wasm         # Crear proyecto transpiler
zid build                    # Compilar
zid watch                    # Watch mode
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
│   ├── capsule.zig       # zid capsule <subcommand>
│   ├── update.zig        # zid update
│   ├── patch.zig         # zid patch <subcommand>
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
│   ├── toolchain.zig     # Public API
│   ├── versions.zig      # Semver parsing
│   ├── registry.zig      # Tool definitions
│   ├── downloader.zig    # HTTP client + progress
│   ├── extractor.zig     # tar.gz/xz/zip extraction
│   └── installer.zig     # Install orchestration
│
├── capsules/             # Capsule System
│   ├── capsules.zig      # Manager API
│   ├── registry.zig      # Built-in definitions
│   ├── fetcher.zig       # Download externals
│   └── manifest.zig      # Capsule manifest format
│
├── patches/              # Patch System
│   ├── patches.zig       # Manager API
│   ├── registry.zig      # Fetch available patches
│   └── applicator.zig    # Apply patches
│
├── apps/                 # Apps Registry
│   └── apps.zig
│
└── framework/            # Transpiler Framework
    ├── framework.zig
    ├── metadata.zig
    └── pipeline.zig
```

## Estado de Implementación

### Core Patterns (misc/) ✅

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

### Toolchain Manager ✅

| Módulo | Descripción | Estado |
|--------|-------------|--------|
| `versions.zig` | Semver parsing y comparación | ✅ |
| `registry.zig` | Definición de tools + URLs | ✅ |
| `downloader.zig` | HTTP download con progress | ✅ |
| `extractor.zig` | tar.gz, tar.xz, zip | ✅ |
| `installer.zig` | Orquestación completa | ✅ |

### Capsules System ✅

| Módulo | Descripción | Estado |
|--------|-------------|--------|
| `capsules.zig` | Manager API | ✅ |
| `registry.zig` | Built-in capsule definitions | ✅ |
| `fetcher.zig` | External capsule download | ✅ |
| `manifest.zig` | Capsule manifest parsing | ✅ |

### Patches System ✅

| Módulo | Descripción | Estado |
|--------|-------------|--------|
| `patches.zig` | Manager API | ✅ |
| `registry.zig` | Fetch available patches | ✅ |
| `applicator.zig` | Apply patches | ✅ |

### Self-Update ✅

| Feature | Descripción | Estado |
|---------|-------------|--------|
| Version check | Consultar API por nuevas versiones | ✅ |
| Atomic update | Reemplazo atómico con rollback | ✅ |
| Checksum verify | Verificación de integridad | ✅ |

### Pendiente

```
[ ] Apps registry - Base de datos persistente
[ ] Framework IR - Intermediate representation
[ ] Server component - Para registry remoto
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
├── capsules/             # Librería de módulos
│   ├── intern/           # Built-in capsules
│   │   ├── webgpu/
│   │   └── sqlite/
│   └── extern/           # Downloaded capsules
│
├── patches/              # Parches aplicados
│   ├── applied.json      # Registro de parches
│   ├── scripts/          # Parches de script
│   └── data/             # Parches de datos
│
├── apps/                 # Apps registradas
│   └── my-app/
│
├── cache/                # Downloads cache
│
└── config.json           # Configuración global
```

## Debug

Habilitar logging por subsistema:

```bash
ZID_DEBUG_TOOLCHAIN=1 zid install bun
ZID_DEBUG_DOWNLOAD=1 zid install zig
ZID_DEBUG_CAPSULES=1 zid capsule add webgpu
ZID_DEBUG_PATCHES=1 zid patch check
```

## Build

```bash
# Compilar release
zig build -Doptimize=ReleaseFast

# Output
./zig-out/bin/zid

# Desarrollo
zig build run -- help
zig build test
```

## Licencia

MIT

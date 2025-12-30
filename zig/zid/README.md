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

## API para Scripts

Zid expone una API pública para crear scripts y herramientas en Zig:

```zig
const zid = @import("zid");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // === Filesystem ===
    const content = try zid.api.fs.read(allocator, "config.json");
    try zid.api.fs.write("output.txt", "Hello!");
    try zid.api.fs.mkdir("new-dir");

    // Path utilities
    const name = zid.fs.paths.basename("/path/to/file.txt");  // "file.txt"
    const ext = zid.fs.paths.extension("file.txt");           // ".txt"
    const dir = zid.fs.paths.dirname("/path/to/file.txt");    // "/path/to"

    // === Shell ===
    if (zid.api.shell.hasCommand("bun")) {
        const result = try zid.api.shell.exec(allocator, "bun", .{"--version"});
        if (result.success) {
            std.debug.print("Bun version: {s}", .{result.stdout});
        }
    }

    // === HTTP ===
    const body = try zid.api.http.get(allocator, "https://api.example.com/data");

    // === Templates ===
    const templates = zid.api.template.list();
    if (zid.api.template.findBuiltin("zig")) |tmpl| {
        std.debug.print("Template: {s}\n", .{tmpl.name});
    }

    // === Search ===
    const matches = try zid.api.search.glob(allocator, "src/**/*.zig");
}
```

### API Modules

| Módulo | Descripción |
|--------|-------------|
| `zid.api.fs` | Filesystem: read, write, copy, mkdir, stat |
| `zid.api.shell` | Shell: exec, hasCommand, getEnv |
| `zid.api.http` | HTTP: get, post, download |
| `zid.api.search` | Search: glob, grep |
| `zid.api.template` | Templates: list, findBuiltin |
| `zid.api.json` | JSON: parse, stringify |

## Custom Toolchains

Añade tus propios toolchains creando `~/.zid/toolchains.json`:

```json
{
  "gleam": {
    "description": "Gleam language",
    "homepage": "https://gleam.run",
    "url_template": "https://github.com/gleam-lang/gleam/releases/download/v{version}/gleam-v{version}-{arch}-unknown-{os}-musl.tar.gz",
    "archive": "tar_gz",
    "binary": "gleam"
  },
  "vlang": {
    "description": "V programming language",
    "homepage": "https://vlang.io",
    "url_template": "https://github.com/vlang/v/releases/download/{version}/v_{os}.zip",
    "archive": "zip",
    "binary": "v",
    "binary_path": "v"
  }
}
```

**Placeholders disponibles:**
- `{version}` - Versión (ej: "1.0.0")
- `{os}` - Sistema operativo (linux, darwin, windows)
- `{arch}` - Arquitectura (x86_64, aarch64)

Luego: `zid install gleam@1.0.0`

## Detección de Conflictos

Zid detecta cuando una herramienta existe en el sistema Y en zid:

```
$ zid install bun
⚠️  Conflicto detectado: 'bun'
   Sistema: /usr/local/bin/bun (v1.0.0)
   Zid:     ~/.zid/bin/bun (v1.1.0)

Soluciones:
  1. Usar 'zid bun' para ejecutar la versión de zid
  2. Ejecutar 'zid use bun' para cambiar PATH
```

### Ejecutar con Prefijo

```bash
# Ejecuta la versión de zid, evitando conflictos
zid bun run script.ts
zid zig build
zid node app.js
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
| `resolver.zig` | Detección de conflictos | ✅ |
| `custom.zig` | Custom toolchains via JSON | ✅ |
| `downloader.zig` | HTTP download con progress | ✅ |
| `extractor.zig` | tar.gz, tar.xz, zip | ✅ |
| `installer.zig` | Orquestación completa | ✅ |

### API Module ✅

| Módulo | Descripción | Estado |
|--------|-------------|--------|
| `fs.zig` | Filesystem operations | ✅ |
| `shell.zig` | Shell execution | ✅ |
| `http.zig` | HTTP client | ✅ |
| `search.zig` | Glob/grep | ✅ |
| `template.zig` | Project templates | ✅ |
| `json.zig` | JSON utilities | ✅ |

### Capsules System ✅

| Módulo | Descripción | Estado |
|--------|-------------|--------|
| `capsules.zig` | Manager API | ✅ |
| `registry.zig` | Built-in capsule definitions | ✅ |
| `fetcher.zig` | External capsule download | ✅ |
| `manifest.zig` | Capsule manifest parsing | ✅ |
| `paths.zig` | Capsule path resolution | ✅ |
| `shell.zig` | Shell environment config | ✅ |
| `integration.zig` | Build system integration | ✅ |

### Patches System ✅

| Módulo | Descripción | Estado |
|--------|-------------|--------|
| `patches.zig` | Manager API | ✅ |
| `registry.zig` | Fetch available patches | ✅ |
| `applicator.zig` | Apply patches | ✅ |

**Nota**: Los patches se ejecutan automáticamente al inicio de zid, no son un comando CLI.

### Framework (Transpilers) ✅

| Módulo | Descripción | Estado |
|--------|-------------|--------|
| `ir.zig` | Intermediate Representation | ✅ |
| `pipeline.zig` | Compilation pipeline | ✅ |
| `metadata.zig` | Source metadata | ✅ |

### Self-Update ✅

| Feature | Descripción | Estado |
|---------|-------------|--------|
| Version check | Consultar API por nuevas versiones | ✅ |
| Atomic update | Reemplazo atómico con rollback | ✅ |
| Checksum verify | Verificación de integridad | ✅ |

## Tests

```bash
# Ejecutar todos los tests (requiere Zig 0.14+)
zig build test

# Con resumen detallado
zig build test --summary all

# Test específico
zig build test -- --test-filter "version"
```

**Estado actual**: ✅ 155/155 tests pasan

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

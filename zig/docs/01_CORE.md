# Modulo 01: Core

## Proposito

El modulo Core es la base de Zid. Contiene tipos fundamentales, manejo de memoria, errores y utilidades que todos los demas modulos usan.

## Responsabilidades

- Tipos primitivos y estructuras base
- Allocators y manejo de memoria
- Sistema de errores unificado
- Deteccion de plataforma (compile-time)
- Variables de entorno tipadas
- Utilidades de strings

## Archivos de Referencia en Bun

| Archivo Bun | Lineas | Usar en Zid |
|-------------|--------|-------------|
| `src/env.zig` | 179 | SI - Deteccion plataforma |
| `src/env_var.zig` | 673 | SI - Env vars tipadas |
| `src/memory.zig` | ~200 | SI - Utilidades memoria |
| `src/allocators.zig` | 935 | PARCIAL - Solo lo esencial |

## Estructura Propuesta

```zig
// zig/src/core/mod.zig
pub const Platform = @import("platform.zig");
pub const Memory = @import("memory.zig");
pub const Error = @import("error.zig");
pub const Types = @import("types.zig");
pub const Env = @import("env.zig");
```

## Interfaces

### Platform (compile-time)

```zig
pub const Platform = struct {
    pub const os: OS = detect_os();
    pub const arch: Arch = detect_arch();

    pub const OS = enum { linux, macos, windows };
    pub const Arch = enum { x64, arm64, wasm };

    pub const is_posix = os != .windows;
    pub const is_native = arch != .wasm;
};
```

### Error

```zig
pub const Error = union(enum) {
    system: SystemError,
    plugin: PluginError,
    config: ConfigError,
    io: IOError,

    pub fn format(self: Error) []const u8;
    pub fn code(self: Error) u32;
};

pub const Result(T) = union(enum) {
    ok: T,
    err: Error,
};
```

### Memory

```zig
pub const Allocator = struct {
    alloc_fn: fn(usize) ?[*]u8,
    free_fn: fn([*]u8, usize) void,

    pub fn alloc(self: *Allocator, comptime T: type, n: usize) ?[]T;
    pub fn free(self: *Allocator, ptr: anytype) void;
    pub fn dupe(self: *Allocator, bytes: []const u8) ?[]u8;
};

pub const default_allocator: Allocator = ...;
pub const arena_allocator: Allocator = ...;
```

### Env

```zig
pub const Env = struct {
    pub fn get(key: []const u8) ?[]const u8;
    pub fn set(key: []const u8, value: []const u8) bool;
    pub fn unset(key: []const u8) void;

    // Typed accessors
    pub fn home() ?[]const u8;
    pub fn tmp() []const u8;
    pub fn path() []const u8;
};
```

## Dependencias

**Ninguna** - Este es el modulo base.

## Estimacion

- **Lineas**: ~2,000
- **Complejidad**: Baja
- **Prioridad**: CRITICA (primero a implementar)

## Codigo de Referencia

### De env.zig (Bun)

```zig
// Deteccion compile-time
pub const isMac = builtin.target.os.tag == .macos;
pub const isLinux = builtin.target.os.tag == .linux;
pub const isWindows = builtin.target.os.tag == .windows;
pub const isAarch64 = builtin.target.cpu.arch.isAARCH64();
pub const isX64 = builtin.target.cpu.arch == .x86_64;

pub const OperatingSystem = enum {
    mac, linux, windows, wasm,

    pub fn nameString(self: OperatingSystem) []const u8 {
        return switch (self) {
            .mac => "darwin",
            .linux => "linux",
            .windows => "win32",
            .wasm => "wasm",
        };
    }
};
```

### De env_var.zig (Bun)

```zig
// Variables de entorno con tipos
pub const HOME = EnvVar("HOME", "USERPROFILE");
pub const TMPDIR = EnvVar("TMPDIR", "TEMP");
pub const PATH = EnvVar("PATH", "Path");

fn EnvVar(comptime posix: []const u8, comptime windows: []const u8) type {
    return struct {
        pub fn get() ?[]const u8 {
            const key = if (Platform.is_windows) windows else posix;
            return std.os.getenv(key);
        }
    };
}
```

## Checklist Implementacion

- [ ] `platform.zig` - Deteccion OS/Arch
- [ ] `types.zig` - Tipos base (String, Result, etc)
- [ ] `error.zig` - Sistema de errores
- [ ] `memory.zig` - Allocators
- [ ] `env.zig` - Variables de entorno
- [ ] `strings.zig` - Utilidades strings
- [ ] `mod.zig` - Re-exports

## Notas

Este modulo debe ser **estable** antes de continuar con otros. Todo depende de el.

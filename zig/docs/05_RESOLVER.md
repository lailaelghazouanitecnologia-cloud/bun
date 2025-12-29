# Modulo 05: Resolver

## Proposito

El modulo Resolver se encarga de encontrar y resolver modulos/archivos desde specifiers (imports). Es generico y funciona para cualquier lenguaje.

## Responsabilidades

- Resolucion de paths relativos/absolutos
- Resolucion de modulos npm-style
- Soporte para alias y mappings
- Cache de resoluciones
- Extensiones configurables

## Archivos de Referencia en Bun

| Archivo Bun | Lineas | Usar en Zid |
|-------------|--------|-------------|
| `src/resolver/resolver.zig` | ~5,000 | ADAPTAR - Generalizar |
| `src/resolver/resolve_path.zig` | ~800 | SI - Path resolution |
| `src/resolver/package_json.zig` | ~1,500 | OPCIONAL - Solo si npm |

## Estructura Propuesta

```zig
// zig/src/resolver/mod.zig
pub const Resolver = @import("resolver.zig");
pub const Path = @import("path.zig");
pub const Cache = @import("cache.zig");
pub const Config = @import("config.zig");
```

## Interfaces

### Resolver Principal

```zig
pub const Resolver = struct {
    allocator: Allocator,
    config: ResolverConfig,
    cache: ResolverCache,

    pub fn init(allocator: Allocator, config: ResolverConfig) Resolver;
    pub fn deinit(self: *Resolver) void;

    /// Resuelve un specifier desde un archivo origen
    pub fn resolve(
        self: *Resolver,
        specifier: []const u8,
        from: []const u8,
    ) Error!Resolution;

    /// Resuelve sin cache
    pub fn resolveUncached(
        self: *Resolver,
        specifier: []const u8,
        from: []const u8,
    ) Error!Resolution;

    /// Invalida cache para un path
    pub fn invalidate(self: *Resolver, path: []const u8) void;

    /// Limpia todo el cache
    pub fn clearCache(self: *Resolver) void;
};

pub const Resolution = struct {
    path: []const u8,           // Path absoluto resuelto
    loader: ?LoaderKind,        // Loader sugerido
    package: ?PackageInfo,      // Info del package (si aplica)
    is_external: bool,          // Marcar como externo
    namespace: []const u8,      // "file", "node", "bun", custom

    pub const PackageInfo = struct {
        name: []const u8,
        version: []const u8,
        main: ?[]const u8,
    };
};
```

### Configuracion

```zig
pub const ResolverConfig = struct {
    /// Directorios base para resolver
    roots: []const []const u8,

    /// Extensiones a probar (en orden)
    extensions: []const []const u8 = &.{
        ".ts", ".tsx", ".js", ".jsx", ".json",
    },

    /// Alias de paths
    /// { "@/*": "./src/*" }
    aliases: std.StringHashMap([]const u8),

    /// Campos de package.json a usar
    main_fields: []const []const u8 = &.{
        "module", "main", "browser",
    },

    /// Condiciones de exports
    conditions: []const []const u8 = &.{
        "import", "require", "default",
    },

    /// Directorios de modulos
    module_dirs: []const []const u8 = &.{
        "node_modules",
    },

    /// Preservar symlinks
    preserve_symlinks: bool = false,

    /// Modulos externos (no resolver)
    externals: []const []const u8 = &.{},
};
```

### Tipos de Resolucion

```zig
pub const ResolveKind = enum {
    /// Path relativo: "./foo", "../bar"
    relative,

    /// Path absoluto: "/home/user/foo"
    absolute,

    /// Modulo: "lodash", "@scope/pkg"
    module,

    /// Built-in: "node:fs", "bun:sqlite"
    builtin,

    /// URL: "https://...", "file://..."
    url,

    /// Custom namespace: "virtual:config"
    custom,
};

pub fn classifySpecifier(specifier: []const u8) ResolveKind {
    if (specifier.len == 0) return .relative;

    if (specifier[0] == '/') return .absolute;
    if (specifier[0] == '.') return .relative;

    if (std.mem.indexOf(u8, specifier, "://")) |_| return .url;
    if (std.mem.indexOf(u8, specifier, ":")) |i| {
        if (i == 1 and Platform.os == .windows) return .absolute; // C:\
        const prefix = specifier[0..i];
        if (isBuiltinPrefix(prefix)) return .builtin;
        return .custom;
    }

    return .module;
}
```

### Cache de Resoluciones

```zig
pub const ResolverCache = struct {
    resolutions: std.StringHashMap(Resolution),
    package_jsons: std.StringHashMap(*PackageJson),
    real_paths: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator) ResolverCache;
    pub fn deinit(self: *ResolverCache) void;

    pub fn get(self: *ResolverCache, key: []const u8) ?Resolution;
    pub fn put(self: *ResolverCache, key: []const u8, value: Resolution) void;
    pub fn invalidate(self: *ResolverCache, key: []const u8) void;
};
```

### Package.json Support (Opcional)

```zig
pub const PackageJson = struct {
    name: ?[]const u8,
    version: ?[]const u8,
    main: ?[]const u8,
    module: ?[]const u8,
    browser: ?std.json.Value,
    exports: ?std.json.Value,
    imports: ?std.json.Value,
    type_field: ?[]const u8,  // "module" | "commonjs"
    side_effects: ?std.json.Value,

    pub fn parse(allocator: Allocator, content: []const u8) Error!PackageJson;
    pub fn resolveExport(self: *PackageJson, subpath: []const u8, conditions: []const []const u8) ?[]const u8;
};
```

## Algoritmo de Resolucion

```
resolve(specifier, from):
    1. Clasificar specifier (relative, absolute, module, builtin, url)

    2. Si relative o absolute:
       - Normalizar path
       - Probar extensiones si no tiene
       - Probar index files si es directorio
       - Return path resuelto

    3. Si module:
       - Buscar en node_modules hacia arriba
       - Leer package.json
       - Resolver via "exports" o "main"
       - Return path resuelto

    4. Si builtin:
       - Retornar como externo o resolver built-in

    5. Si url:
       - Retornar como externo

    6. Cache resultado
```

## Extensibilidad via Plugins

```zig
// Los plugins pueden agregar resolvers custom
pub const ResolverPlugin = struct {
    /// Prefijos que maneja: ["virtual:", "raw:"]
    prefixes: []const []const u8,

    /// Resolver custom
    resolve: fn(specifier: []const u8, from: []const u8) Error!?Resolution,
};

// Ejemplo: resolver virtual
const virtual_resolver = ResolverPlugin{
    .prefixes = &.{"virtual:"},
    .resolve = struct {
        fn resolve(specifier: []const u8, from: []const u8) Error!?Resolution {
            const name = specifier["virtual:".len..];
            return Resolution{
                .path = name,
                .namespace = "virtual",
                .is_external = false,
            };
        }
    }.resolve,
};
```

## Dependencias

- **Core**: Tipos, errores
- **IO**: Lectura de archivos, stat

## Estimacion

- **Lineas**: ~3,000
- **Complejidad**: Media
- **Prioridad**: Alta

## Checklist Implementacion

- [ ] `resolver.zig` - Resolver principal
- [ ] `path.zig` - Resolucion de paths
- [ ] `module.zig` - Resolucion de modulos
- [ ] `package_json.zig` - Parser package.json
- [ ] `cache.zig` - Sistema de cache
- [ ] `config.zig` - Configuracion
- [ ] `mod.zig` - Re-exports

## Notas

- El resolver debe ser **lazy** - no escanear todo el filesystem
- Cache agresivo pero con invalidacion correcta
- Soportar watch mode (invalidar cuando archivos cambian)

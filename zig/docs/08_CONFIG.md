# Modulo 08: Config

## Proposito

El modulo Config maneja la carga y validacion de configuracion de Zid. Soporta multiples formatos y merge de configuraciones.

## Responsabilidades

- Carga de archivos de config
- Validacion de schema
- Merge de configs (defaults + proyecto + cli)
- Hot reload de config
- Generacion de config

## Archivos de Referencia en Bun

| Archivo Bun | Lineas | Usar en Zid |
|-------------|--------|-------------|
| `src/bunfig.zig` | 1,255 | ADAPTAR - Generalizar |
| `src/options.zig` | 2,681 | PARCIAL - Schema |

## Estructura Propuesta

```zig
// zig/src/config/mod.zig
pub const Config = @import("config.zig");
pub const Loader = @import("loader.zig");
pub const Schema = @import("schema.zig");
pub const Defaults = @import("defaults.zig");
```

## Interfaces

### Config Principal

```zig
pub const Config = struct {
    /// Plugins habilitados
    plugins: PluginsConfig,

    /// Configuracion de build
    build: BuildConfig,

    /// Configuracion de runtime
    runtime: RuntimeConfig,

    /// Configuracion de resolver
    resolve: ResolveConfig,

    /// Comandos custom
    scripts: std.StringHashMap([]const u8),

    /// Path al archivo de config
    config_path: ?[]const u8,

    pub fn load(allocator: Allocator, options: LoadOptions) Error!Config;
    pub fn merge(base: Config, override: Config) Config;
    pub fn validate(self: *Config) Error!void;
    pub fn toJson(self: *Config) []const u8;
};

pub const LoadOptions = struct {
    /// Buscar config en directorios padre
    search_ancestors: bool = true,

    /// Path explicito a config
    config_path: ?[]const u8 = null,

    /// Directorio base
    cwd: []const u8,

    /// Override desde CLI
    cli_overrides: ?CliOverrides = null,
};
```

### Configuracion de Plugins

```zig
pub const PluginsConfig = struct {
    /// Plugins de lenguaje
    /// { ".ts": "@zid/lang-typescript" }
    languages: std.StringHashMap(PluginSpec),

    /// Plugins de target
    /// { "javascript": "@zid/target-js" }
    targets: std.StringHashMap(PluginSpec),

    /// Plugins de transform (orden importa)
    transforms: []const PluginSpec,

    /// Plugins de loader
    loaders: std.StringHashMap(PluginSpec),

    /// Plugins de comando
    commands: std.StringHashMap(PluginSpec),
};

pub const PluginSpec = union(enum) {
    /// Plugin npm: "@zid/lang-typescript"
    npm: []const u8,

    /// Plugin local: "./plugins/mylang.zig"
    local: []const u8,

    /// Plugin inline (solo para built-ins)
    builtin: []const u8,

    /// Plugin con config
    with_config: struct {
        name: []const u8,
        config: std.json.Value,
    },
};
```

### Configuracion de Build

```zig
pub const BuildConfig = struct {
    /// Entrypoints
    entry: []const []const u8 = &.{},

    /// Directorio de salida
    outdir: []const u8 = "./dist",

    /// Nombre del archivo de salida
    outfile: ?[]const u8 = null,

    /// Formato de salida
    format: OutputFormat = .esm,

    /// Target de salida
    target: []const u8 = "javascript",

    /// Minificar
    minify: bool = false,

    /// Source maps
    sourcemap: SourceMapOption = .none,

    /// Splitting (code splitting)
    splitting: bool = false,

    /// Tree shaking
    tree_shaking: bool = true,

    /// Define (reemplazos en compile time)
    define: std.StringHashMap([]const u8),

    /// External (no bundlear)
    external: []const []const u8 = &.{},
};
```

### Configuracion de Runtime

```zig
pub const RuntimeConfig = struct {
    /// Variables de entorno
    env: std.StringHashMap([]const u8),

    /// Directorio de trabajo
    cwd: ?[]const u8 = null,

    /// Modo watch
    watch: bool = false,

    /// Hot reload
    hot: bool = false,

    /// Puerto para dev server
    port: u16 = 3000,

    /// Host para dev server
    host: []const u8 = "localhost",
};
```

### Configuracion de Resolver

```zig
pub const ResolveConfig = struct {
    /// Alias de paths
    alias: std.StringHashMap([]const u8),

    /// Extensiones a probar
    extensions: []const []const u8 = &.{
        ".ts", ".tsx", ".js", ".jsx", ".json",
    },

    /// Main fields en package.json
    main_fields: []const []const u8 = &.{
        "module", "main",
    },

    /// Conditions para exports
    conditions: []const []const u8 = &.{
        "import", "default",
    },

    /// Directorios de modulos
    module_dirs: []const []const u8 = &.{
        "node_modules",
    },
};
```

## Archivos de Config Soportados

```
zid.config.ts    (preferido)
zid.config.js
zid.config.json
zid.config.toml
zid.config.yaml
.zidrc
.zidrc.json
package.json (campo "zid")
```

## Loader de Config

```zig
pub const ConfigLoader = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ConfigLoader;

    /// Buscar y cargar config
    pub fn load(self: *ConfigLoader, options: LoadOptions) Error!Config {
        // 1. Buscar archivo de config
        const config_path = self.findConfig(options.cwd) orelse {
            return Defaults.config;
        };

        // 2. Leer archivo
        const content = try IO.File.readAll(config_path);

        // 3. Parsear segun extension
        const parsed = switch (getExtension(config_path)) {
            ".ts", ".js" => try self.loadScript(config_path),
            ".json" => try self.loadJson(content),
            ".toml" => try self.loadToml(content),
            ".yaml" => try self.loadYaml(content),
            else => return error.UnsupportedConfigFormat,
        };

        // 4. Validar
        try Schema.validate(parsed);

        // 5. Merge con defaults
        var config = Defaults.config;
        config = Config.merge(config, parsed);

        // 6. Aplicar CLI overrides
        if (options.cli_overrides) |cli| {
            config = Config.merge(config, cli.toConfig());
        }

        return config;
    }

    fn findConfig(self: *ConfigLoader, start_dir: []const u8) ?[]const u8 {
        const config_names = &.{
            "zid.config.ts",
            "zid.config.js",
            "zid.config.json",
            "zid.config.toml",
            ".zidrc",
        };

        var dir = start_dir;
        while (true) {
            for (config_names) |name| {
                const path = Path.join(dir, name);
                if (IO.exists(path)) return path;
            }

            // Subir al padre
            const parent = Path.dirname(dir);
            if (std.mem.eql(u8, parent, dir)) break;
            dir = parent;
        }

        return null;
    }
};
```

## Ejemplo zid.config.ts

```typescript
import type { ZidConfig } from 'zid';

export default {
  plugins: {
    languages: {
      '.ts': '@zid/lang-typescript',
      '.py': 'zid-lang-python',
      '.zid': './plugins/zid-lang.ts',
    },
    targets: {
      javascript: '@zid/target-js',
      python: '@zid/target-python',
    },
    transforms: [
      '@zid/transform-minify',
      './transforms/custom.ts',
    ],
  },

  build: {
    entry: ['./src/index.ts'],
    outdir: './dist',
    format: 'esm',
    target: 'javascript',
    minify: true,
    sourcemap: 'external',
  },

  resolve: {
    alias: {
      '@': './src',
      '~': './lib',
    },
  },

  runtime: {
    watch: true,
    port: 3000,
  },

  scripts: {
    dev: 'zid run --watch src/index.ts',
    build: 'zid build',
    test: 'zid test',
  },
} satisfies ZidConfig;
```

## Defaults

```zig
pub const Defaults = struct {
    pub const config = Config{
        .plugins = .{
            .languages = defaultLanguages(),
            .targets = defaultTargets(),
            .transforms = &.{},
            .loaders = defaultLoaders(),
            .commands = &.{},
        },
        .build = .{
            .format = .esm,
            .minify = false,
            .sourcemap = .none,
        },
        .runtime = .{
            .port = 3000,
            .host = "localhost",
        },
        .resolve = .{
            .extensions = &.{ ".ts", ".js", ".json" },
        },
        .scripts = .{},
        .config_path = null,
    };

    fn defaultLanguages() std.StringHashMap(PluginSpec) {
        // Lenguajes built-in
        return .{
            .{ ".ts", .{ .builtin = "typescript" } },
            .{ ".tsx", .{ .builtin = "typescript" } },
            .{ ".js", .{ .builtin = "javascript" } },
            .{ ".jsx", .{ .builtin = "javascript" } },
            .{ ".json", .{ .builtin = "json" } },
        };
    }
};
```

## Dependencias

- **Core**: Tipos, errores
- **IO**: Lectura de archivos

## Estimacion

- **Lineas**: ~1,000
- **Complejidad**: Media
- **Prioridad**: Media

## Checklist Implementacion

- [ ] `config.zig` - Estructuras de config
- [ ] `loader.zig` - Carga de config
- [ ] `schema.zig` - Validacion
- [ ] `defaults.zig` - Valores por defecto
- [ ] `merge.zig` - Merge de configs
- [ ] `mod.zig` - Re-exports

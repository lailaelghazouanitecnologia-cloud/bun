# Modulo 03: CLI

## Proposito

El modulo CLI provee un sistema de comandos dinamico donde los comandos pueden ser registrados via plugins o configuracion.

## Responsabilidades

- Parsing de argumentos
- Routing de comandos
- Help automatico
- Tab completion
- Subcomandos anidados
- Flags globales vs locales

## Archivos de Referencia en Bun

| Archivo Bun | Lineas | Usar en Zid |
|-------------|--------|-------------|
| `src/cli.zig` | 1,762 | ADAPTAR - Hacerlo dinamico |
| `src/cli/Arguments.zig` | ~500 | SI - Parser de args |
| `src/deps/zig-clap/` | ~2,000 | EVALUAR - Libreria clap |

## Estructura Propuesta

```zig
// zig/src/cli/mod.zig
pub const Parser = @import("parser.zig");
pub const Router = @import("router.zig");
pub const Help = @import("help.zig");
pub const Completion = @import("completion.zig");
```

## Interfaces

### CLI App

```zig
pub const App = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,

    commands: std.StringHashMap(*Command),
    global_flags: []Flag,

    pub fn init(name: []const u8) App;
    pub fn addCommand(self: *App, cmd: *Command) void;
    pub fn addGlobalFlag(self: *App, flag: Flag) void;
    pub fn run(self: *App, args: []const []const u8) Error!i32;
};
```

### Command

```zig
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,

    flags: []Flag,
    positional: []Positional,
    subcommands: ?std.StringHashMap(*Command),

    // Handler
    run: fn(ctx: *CommandContext) Error!i32,

    // Optional
    validate: ?fn(ctx: *CommandContext) Error!void,
    complete: ?fn(partial: []const u8) []const []const u8,
};

pub const CommandContext = struct {
    app: *App,
    command: *Command,
    flags: FlagValues,
    args: []const []const u8,
    stdin: std.fs.File,
    stdout: std.fs.File,
    stderr: std.fs.File,
};
```

### Flags y Argumentos

```zig
pub const Flag = struct {
    name: []const u8,
    short: ?u8,           // -v
    long: []const u8,     // --verbose
    description: []const u8,
    kind: FlagKind,
    default: ?[]const u8,
    required: bool,
};

pub const FlagKind = enum {
    boolean,    // --verbose
    string,     // --output=file.js
    number,     // --port=3000
    list,       // --include=a --include=b
};

pub const Positional = struct {
    name: []const u8,
    description: []const u8,
    required: bool,
    variadic: bool,  // Acepta multiples valores
};
```

## Comandos Built-in

```zig
// Comandos que vienen con Zid
pub const builtin_commands = [_]*Command{
    &run_command,      // zid run file.ts
    &build_command,    // zid build
    &init_command,     // zid init
    &plugin_command,   // zid plugin add/remove/list
    &help_command,     // zid help [command]
    &version_command,  // zid --version
};
```

### Comando Run

```zig
const run_command = Command{
    .name = "run",
    .description = "Execute a file",
    .usage = "zid run [flags] <file> [args...]",
    .flags = &[_]Flag{
        .{ .long = "watch", .short = 'w', .kind = .boolean, .description = "Watch for changes" },
        .{ .long = "target", .short = 't', .kind = .string, .description = "Output target" },
    },
    .positional = &[_]Positional{
        .{ .name = "file", .required = true },
        .{ .name = "args", .variadic = true },
    },
    .run = runHandler,
};

fn runHandler(ctx: *CommandContext) Error!i32 {
    const file = ctx.args[0];
    const watch = ctx.flags.getBool("watch");
    const target = ctx.flags.getString("target") orelse "javascript";

    // 1. Resolver archivo
    // 2. Cargar con loader apropiado
    // 3. Parsear con language plugin
    // 4. Transformar
    // 5. Emitir con target plugin
    // 6. Ejecutar o guardar

    return 0;
}
```

### Comando Plugin

```zig
const plugin_command = Command{
    .name = "plugin",
    .description = "Manage plugins",
    .subcommands = &.{
        .{ "add", &plugin_add_command },
        .{ "remove", &plugin_remove_command },
        .{ "list", &plugin_list_command },
    },
};
```

## Integracion con Plugin System

```zig
// Los plugins pueden registrar comandos
pub fn registerPluginCommands(app: *App, registry: *PluginRegistry) void {
    var iter = registry.commands.iterator();
    while (iter.next()) |entry| {
        const cmd_plugin = entry.value_ptr.*;
        app.addCommand(cmd_plugin.toCommand());
    }
}
```

## Help Automatico

```
$ zid --help
Zid - Universal Runtime v0.1.0

USAGE:
    zid <command> [options]

COMMANDS:
    run       Execute a file
    build     Build project
    init      Initialize new project
    plugin    Manage plugins
    help      Show help

GLOBAL FLAGS:
    -v, --verbose    Verbose output
    -q, --quiet      Quiet mode
    --config         Config file path

Run 'zid help <command>' for more information.
```

## Tab Completion

```zig
pub fn generateCompletions(app: *App, shell: Shell) []const u8 {
    return switch (shell) {
        .bash => generateBashCompletions(app),
        .zsh => generateZshCompletions(app),
        .fish => generateFishCompletions(app),
        .powershell => generatePowerShellCompletions(app),
    };
}
```

## Dependencias

- **Core**: Tipos, errores
- **Plugin System**: Para comandos dinamicos

## Estimacion

- **Lineas**: ~2,000
- **Complejidad**: Media
- **Prioridad**: Alta

## Checklist Implementacion

- [ ] `parser.zig` - Parsing de argumentos
- [ ] `router.zig` - Routing de comandos
- [ ] `command.zig` - Estructura Command
- [ ] `flags.zig` - Manejo de flags
- [ ] `help.zig` - Generacion de ayuda
- [ ] `completion.zig` - Tab completion
- [ ] `builtin/` - Comandos built-in
- [ ] `mod.zig` - Re-exports

## Codigo de Referencia

### De cli.zig (Bun)

```zig
pub const Command = struct {
    pub const Tag = enum {
        RunCommand,
        TestCommand,
        BuildCommand,
        // ... 30+ comandos
    };

    pub fn which(allocator: Allocator, args: []const []const u8) Tag {
        // Router basado en el primer argumento
        if (args.len == 0) return .RunCommand;

        const cmd = args[0];
        if (RootCommandMatcher.match(cmd)) |tag| {
            return tag;
        }
        return .RunCommand;
    }
};
```

Zid lo hace **dinamico** - los comandos se registran, no se hardcodean.

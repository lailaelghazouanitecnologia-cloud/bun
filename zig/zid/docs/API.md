# Zid API Reference

## Introducción

Zid expone una API pública para crear scripts y herramientas en Zig:

```zig
const zid = @import("zid");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Usar cualquier módulo de la API
    const content = try zid.api.fs.read(allocator, "config.json");
    const result = try zid.api.shell.exec(allocator, "ls", .{"-la"});
}
```

## Módulos

| Módulo | Descripción |
|--------|-------------|
| `zid.api.fs` | Filesystem: read, write, copy, mkdir, stat |
| `zid.api.shell` | Shell: exec, hasCommand, getEnv |
| `zid.api.search` | Search: glob, grep, find |
| `zid.api.template` | Templates: list, findBuiltin, create |
| `zid.api.json` | JSON: parse, stringify |
| `zid.http` | HTTP client: get, post, download con progress |

---

## zid.api.fs

Operaciones de filesystem.

### read

Lee el contenido completo de un archivo.

```zig
pub fn read(allocator: Allocator, path: []const u8) ![]u8
```

**Ejemplo:**
```zig
const content = try zid.api.fs.read(allocator, "config.json");
defer allocator.free(content);
```

### readLines

Lee un archivo como lista de líneas.

```zig
pub fn readLines(allocator: Allocator, path: []const u8) !ArrayList([]const u8)
```

**Ejemplo:**
```zig
var lines = try zid.api.fs.readLines(allocator, "log.txt");
defer lines.deinit();

for (lines.items) |line| {
    std.debug.print("{s}\n", .{line});
}
```

### write

Escribe datos a un archivo (crea o sobrescribe).

```zig
pub fn write(path: []const u8, data: []const u8) !void
```

**Ejemplo:**
```zig
try zid.api.fs.write("output.txt", "Hello, World!\n");
```

### append

Añade datos al final de un archivo.

```zig
pub fn append(path: []const u8, data: []const u8) !void
```

### writeJson

Escribe un valor como JSON formateado.

```zig
pub fn writeJson(path: []const u8, value: anytype) !void
```

**Ejemplo:**
```zig
const config = .{
    .name = "my-app",
    .version = "1.0.0",
};
try zid.api.fs.writeJson("config.json", config);
```

### copy

Copia archivo o directorio recursivamente.

```zig
pub fn copy(src: []const u8, dest: []const u8) !void
```

**Ejemplo:**
```zig
try zid.api.fs.copy("src/", "dist/");
try zid.api.fs.copy("config.json", "config.backup.json");
```

### move

Mueve/renombra archivo o directorio.

```zig
pub fn move(src: []const u8, dest: []const u8) !void
```

### remove

Elimina archivo.

```zig
pub fn remove(path: []const u8) !void
```

### mkdir

Crea directorio (y padres si no existen).

```zig
pub fn mkdir(path: []const u8) !void
```

### rmdir

Elimina directorio recursivamente.

```zig
pub fn rmdir(path: []const u8) !void
```

### exists

Verifica si existe un archivo o directorio.

```zig
pub fn exists(path: []const u8) bool
```

### stat

Obtiene información del archivo.

```zig
pub fn stat(path: []const u8) !Stat

pub const Stat = struct {
    size: u64,
    mtime: i128,
    kind: Kind,

    pub const Kind = enum { file, directory, symlink, other };
};
```

### paths

Utilidades de path que no allocan.

```zig
// Obtener nombre de archivo
const name = zid.fs.paths.basename("/path/to/file.txt");  // "file.txt"

// Obtener extensión
const ext = zid.fs.paths.extension("file.txt");  // ".txt"

// Obtener directorio
const dir = zid.fs.paths.dirname("/path/to/file.txt");  // "/path/to"
```

---

## zid.api.shell

Ejecución de comandos.

### exec

Ejecuta comando y espera el resultado.

```zig
pub fn exec(
    allocator: Allocator,
    cmd: []const u8,
    args: anytype,
) !ExecResult

pub const ExecResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
    success: bool,

    pub fn output(self: ExecResult) []const u8;  // stdout o stderr
};
```

**Ejemplo:**
```zig
const result = try zid.api.shell.exec(allocator, "ls", .{"-la", "/tmp"});
if (result.success) {
    std.debug.print("Output: {s}\n", .{result.stdout});
} else {
    std.debug.print("Error: {s}\n", .{result.stderr});
}
```

### execOpts

Ejecuta con opciones adicionales.

```zig
pub fn execOpts(
    allocator: Allocator,
    cmd: []const u8,
    args: anytype,
    opts: ExecOptions,
) !ExecResult

pub const ExecOptions = struct {
    cwd: ?[]const u8 = null,           // Directorio de trabajo
    capture_stdout: bool = true,        // Capturar stdout
    capture_stderr: bool = true,        // Capturar stderr
    timeout_ms: ?u32 = null,            // Timeout en ms
    env: ?*const EnvMap = null,         // Variables de entorno
};
```

**Ejemplo:**
```zig
const result = try zid.api.shell.execOpts(allocator, "npm", .{"install"}, .{
    .cwd = "/path/to/project",
    .timeout_ms = 60000,
});
```

### hasCommand

Verifica si un comando existe en PATH.

```zig
pub fn hasCommand(cmd: []const u8) bool
```

**Ejemplo:**
```zig
if (zid.api.shell.hasCommand("bun")) {
    // bun está disponible
}
```

### getEnv

Obtiene variable de entorno.

```zig
pub fn getEnv(key: []const u8) ?[]const u8
```

---

## zid.http

Cliente HTTP con soporte para downloads y progress tracking.

### Client

```zig
pub const Client = struct {
    allocator: Allocator,
    default_timeout_ms: u32,
    user_agent: []const u8,

    pub fn init(allocator: Allocator) Client;
    pub fn get(self: *Self, url: []const u8) Maybe(Response);
    pub fn post(self: *Self, url: []const u8, body: []const u8) Maybe(Response);
    pub fn download(
        self: *Self,
        url: []const u8,
        dest_path: []const u8,
        progress: ?*Progress,
        options: DownloadOptions,
    ) Maybe(void);
};
```

### Response

```zig
pub const Response = struct {
    status: u16,
    body: []const u8,

    pub fn ok(self: Response) bool;  // status 200-299
};
```

### Progress

Tracking de progreso para downloads.

```zig
pub const Progress = struct {
    total: u64 = 0,
    current: u64 = 0,
    callback: ?*const fn (current: u64, total: u64, userdata: ?*anyopaque) void = null,
    userdata: ?*anyopaque = null,

    pub fn update(self: *Progress, bytes: u64) void;
    pub fn percent(self: Progress) u8;
    pub fn reset(self: *Progress) void;
};
```

**Ejemplo con progress bar:**
```zig
fn printProgress(current: u64, total: u64, _: ?*anyopaque) void {
    const pct = if (total > 0) (current * 100) / total else 0;
    std.debug.print("\rDownloading: {}%", .{pct});
}

var progress = zid.http.Progress{
    .callback = printProgress,
};

var client = zid.http.Client.init(allocator);
_ = client.download(url, "/tmp/file.tar.gz", &progress, .{});
```

### Url

Parsing de URLs.

```zig
pub const Url = struct {
    scheme: []const u8,
    host: []const u8,
    port: ?u16,
    path: []const u8,
    query: ?[]const u8,

    pub fn parse(url: []const u8) ?Url;
    pub fn isHttps(self: Url) bool;
};
```

### Funciones de conveniencia

```zig
// GET simple (sin crear Client)
pub fn get(allocator: Allocator, url: []const u8) Maybe(Response);

// POST simple
pub fn post(allocator: Allocator, url: []const u8, body: []const u8) Maybe(Response);

// Download directo
pub fn download(
    allocator: Allocator,
    url: []const u8,
    dest_path: []const u8,
    progress: ?*Progress,
) Maybe(void);
```

**Ejemplo GET:**
```zig
switch (zid.http.get(allocator, "https://api.example.com/data")) {
    .ok => |r| std.debug.print("Body: {s}\n", .{r.body}),
    .err => |e| e.print(),
}
```

---

## zid.api.search

Búsqueda de archivos.

### Match

```zig
pub const Match = struct {
    file: []const u8,
    line: u32,
    column: u32,
    text: []const u8,
};
```

### FindOptions

```zig
pub const FindOptions = struct {
    ext: ?[]const u8 = null,      // Filtrar por extensión
    min_size: ?u64 = null,        // Tamaño mínimo
    max_size: ?u64 = null,        // Tamaño máximo
    files_only: bool = false,     // Solo archivos
    dirs_only: bool = false,      // Solo directorios
    hidden: bool = false,         // Incluir ocultos
};
```

### glob

Busca archivos por patrón glob.

```zig
pub fn glob(allocator: Allocator, pattern: []const u8) ![]const []const u8
```

**Ejemplo:**
```zig
const files = try zid.api.search.glob(allocator, "src/**/*.zig");
for (files) |file| {
    std.debug.print("Found: {s}\n", .{file});
}
```

### grep

Busca texto en archivos.

```zig
pub fn grep(allocator: Allocator, pattern: []const u8, files: []const []const u8) ![]Match
```

---

## zid.api.template

Gestión de templates de proyecto.

### Template

```zig
pub const Template = struct {
    name: []const u8,
    description: []const u8,
    category: Category,

    pub const Category = enum {
        app,
        lib,
        cli,
        other,
    };
};
```

### list

Lista todos los templates disponibles.

```zig
pub fn list() []const Template
```

### findBuiltin

Busca un template built-in por nombre.

```zig
pub fn findBuiltin(name: []const u8) ?Template
```

**Ejemplo:**
```zig
if (zid.api.template.findBuiltin("zig")) |tmpl| {
    std.debug.print("Template: {s} - {s}\n", .{tmpl.name, tmpl.description});
}
```

---

## zid.api.json

Utilidades JSON.

### parseValue

Parsea string JSON.

```zig
pub const parseValue = std.json.parseFromSlice;
```

### stringify

Convierte valor a JSON string.

```zig
pub const stringify = std.json.stringify;
```

**Ejemplo:**
```zig
const data = .{ .name = "test", .value = 42 };
var buf: [1024]u8 = undefined;
var stream = std.io.fixedBufferStream(&buf);
try std.json.stringify(data, .{}, stream.writer());
const json_str = stream.getWritten();
```

---

## Core Types

### Maybe(T)

Result type con contexto de error.

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
};
```

**Ejemplo:**
```zig
fn readConfig(path: []const u8) zid.Maybe(Config) {
    const file = std.fs.openFile(path, .{}) catch |e| {
        return zid.fail(Config, e, .read_file, path);
    };
    defer file.close();
    // ...
    return zid.ok(Config, config);
}

// Uso
switch (readConfig("config.json")) {
    .ok => |cfg| useConfig(cfg),
    .err => |e| {
        std.debug.print("Error: {s} at {s}\n", .{e.message, e.path});
    },
}
```

### Context

Contexto de script con allocator y config.

```zig
pub const Context = struct {
    allocator: Allocator,
    cwd: []const u8,
    args: []const []const u8,
    env: EnvMap,

    pub fn init(allocator: Allocator) !Context;
    pub fn deinit(self: *Context) void;
    pub fn getArg(self: *Context, index: usize) ?[]const u8;
    pub fn getEnv(self: *Context, key: []const u8) ?[]const u8;
};
```

**Ejemplo:**
```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var ctx = try zid.api.Context.init(gpa.allocator());
    defer ctx.deinit();

    const name = ctx.getArg(1) orelse "default";
    const home = ctx.getEnv("HOME") orelse "/tmp";
}
```

---

## Helper Functions

### Output

```zig
// Print to stdout
zid.api.print("Hello {s}\n", .{name});

// Print error to stderr
zid.api.printErr("Error: {s}\n", .{msg});

// Print success (green)
zid.api.success("Done!\n", .{});

// Print warning (yellow)
zid.api.warn("Warning: {s}\n", .{msg});

// Exit with code
zid.api.exit(1);

// Get home directory
const home = zid.api.home();
```

---

## Subsistemas

### Toolchain

```zig
const toolchain = zid.toolchain;

// Verificar si tool está soportado
if (toolchain.isSupported("bun")) { ... }

// Listar tools soportados
const tools = toolchain.supportedTools();

// Version parsing
const v = toolchain.versions.Version.parse("1.2.3");
```

### Capsules

```zig
const capsules = zid.capsules;

// Verificar si capsule es built-in
if (capsules.registry.isBuiltin("webgpu")) { ... }

// Obtener info de capsule
if (capsules.registry.getBuiltin("sqlite")) |cap| {
    std.debug.print("{s}: {s}\n", .{cap.name, cap.description});
}

// Listar built-ins
const builtins = capsules.registry.listBuiltins();
```

# Modulo 07: Target Plugins

## Proposito

Define la interfaz y utilidades para plugins de target/emision. Un target plugin convierte un AST en codigo de salida (JavaScript, Python, Rust, WASM, etc.).

## Responsabilidades

- Interface TargetPlugin
- Code generation utilities
- Source map generation
- Output formatting
- Minification hooks

## Estructura Propuesta

```zig
// zig/src/target/mod.zig
pub const Plugin = @import("plugin.zig");
pub const Emitter = @import("emitter.zig");
pub const SourceMap = @import("sourcemap.zig");
pub const Printer = @import("printer.zig");
```

## Interfaces

### TargetPlugin Interface

```zig
pub const TargetPlugin = struct {
    /// Metadata
    name: []const u8,           // "javascript", "python", "rust"
    version: Version,
    file_extension: []const u8, // ".js", ".py", ".rs"

    /// Emit code from AST
    emit: fn(
        ast: *AST,
        options: EmitOptions,
    ) Error!EmitResult,

    /// Optional: Generate source map
    generate_sourcemap: ?fn(
        ast: *AST,
        output: []const u8,
    ) Error!SourceMap = null,

    /// Optional: Post-process output
    post_process: ?fn(
        output: []const u8,
        options: PostProcessOptions,
    ) Error![]const u8 = null,

    /// Optional: Minify
    minify: ?fn(
        output: []const u8,
        options: MinifyOptions,
    ) Error![]const u8 = null,
};

pub const EmitOptions = struct {
    /// Output format
    format: OutputFormat = .esm,

    /// Target environment
    target: TargetEnv = .browser,

    /// Indentation
    indent: Indent = .{ .spaces = 2 },

    /// Line endings
    line_ending: LineEnding = .lf,

    /// Generate source maps
    sourcemap: SourceMapOption = .none,

    /// Minify output
    minify: bool = false,

    /// Preserve comments
    comments: bool = true,
};

pub const OutputFormat = enum {
    esm,        // ES Modules
    cjs,        // CommonJS
    iife,       // Immediately Invoked Function Expression
    umd,        // Universal Module Definition
    amd,        // Asynchronous Module Definition
    system,     // SystemJS
    raw,        // No module wrapper
};

pub const TargetEnv = enum {
    browser,
    node,
    deno,
    bun,
    worker,
    neutral,
};

pub const Indent = union(enum) {
    tabs: void,
    spaces: u8,
};

pub const LineEnding = enum {
    lf,     // \n (Unix)
    crlf,   // \r\n (Windows)
    cr,     // \r (old Mac)
};

pub const SourceMapOption = enum {
    none,
    inline,     // Inline en el archivo
    external,   // Archivo .map separado
    both,       // Ambos
};
```

### EmitResult

```zig
pub const EmitResult = struct {
    /// Generated code
    code: []const u8,

    /// Source map (if requested)
    sourcemap: ?SourceMap,

    /// Metadata
    metadata: EmitMetadata,
};

pub const EmitMetadata = struct {
    /// Imports externos encontrados
    imports: []const []const u8,

    /// Exports generados
    exports: []const []const u8,

    /// Size stats
    size_original: usize,
    size_output: usize,

    /// Warnings durante emit
    warnings: []const Warning,
};
```

### Printer Utilities

```zig
pub const Printer = struct {
    output: std.ArrayList(u8),
    indent_level: u32,
    options: EmitOptions,
    line: u32,
    column: u32,

    // Source map tracking
    mappings: std.ArrayList(SourceMap.Mapping),
    current_source: ?u32,

    pub fn init(allocator: Allocator, options: EmitOptions) Printer;
    pub fn deinit(self: *Printer) void;

    /// Print string
    pub fn print(self: *Printer, str: []const u8) void;

    /// Print with source location tracking
    pub fn printWithLoc(self: *Printer, str: []const u8, loc: Location) void;

    /// Print formatted
    pub fn printf(self: *Printer, comptime fmt: []const u8, args: anytype) void;

    /// Newline
    pub fn newline(self: *Printer) void;

    /// Indentation
    pub fn indent(self: *Printer) void;
    pub fn dedent(self: *Printer) void;
    pub fn printIndent(self: *Printer) void;

    /// Spacing
    pub fn space(self: *Printer) void;
    pub fn optionalSpace(self: *Printer) void;  // Solo si no minifying

    /// Semicolons
    pub fn semicolon(self: *Printer) void;
    pub fn optionalSemicolon(self: *Printer) void;

    /// Get output
    pub fn toOwnedSlice(self: *Printer) []u8;
    pub fn getSourceMap(self: *Printer) ?SourceMap;
};
```

### Code Templates

```zig
/// Templates para diferentes formatos de modulo
pub const Templates = struct {
    pub const esm_header = "";
    pub const esm_footer = "";

    pub const cjs_header = "";
    pub const cjs_footer = "";

    pub const iife_header =
        \\(function() {
        \\"use strict";
        \\
    ;
    pub const iife_footer =
        \\})();
    ;

    pub const umd_header =
        \\(function(root, factory) {
        \\  if (typeof define === 'function' && define.amd) {
        \\    define([], factory);
        \\  } else if (typeof module === 'object' && module.exports) {
        \\    module.exports = factory();
        \\  } else {
        \\    root.{name} = factory();
        \\  }
        \\})(typeof self !== 'undefined' ? self : this, function() {
        \\"use strict";
        \\
    ;
    pub const umd_footer =
        \\});
    ;
};
```

## Ejemplo: Target JavaScript

```zig
pub const javascript_target = TargetPlugin{
    .name = "javascript",
    .version = .{ .major = 1, .minor = 0, .patch = 0 },
    .file_extension = ".js",
    .emit = js_emit,
    .generate_sourcemap = js_sourcemap,
    .minify = js_minify,
};

fn js_emit(ast: *AST, options: EmitOptions) Error!EmitResult {
    var printer = Printer.init(allocator, options);
    defer printer.deinit();

    // Emit header basado en formato
    switch (options.format) {
        .iife => printer.print(Templates.iife_header),
        .umd => printer.print(Templates.umd_header),
        else => {},
    }

    // Emit AST
    try emitNode(&printer, ast.root);

    // Emit footer
    switch (options.format) {
        .iife => printer.print(Templates.iife_footer),
        .umd => printer.print(Templates.umd_footer),
        else => {},
    }

    return EmitResult{
        .code = printer.toOwnedSlice(),
        .sourcemap = if (options.sourcemap != .none) printer.getSourceMap() else null,
        .metadata = .{
            .imports = collectImports(ast),
            .exports = collectExports(ast),
            .size_original = ast.source.len,
            .size_output = printer.output.items.len,
            .warnings = &.{},
        },
    };
}

fn emitNode(printer: *Printer, node: *Node) Error!void {
    switch (node.kind) {
        .program, .module => {
            for (node.children) |child| {
                try emitNode(printer, child);
                printer.newline();
            }
        },

        .variable_decl => {
            printer.printWithLoc("const ", node.loc);
            // ... emit declaracion
        },

        .function_decl => {
            printer.printWithLoc("function ", node.loc);
            // ... emit funcion
        },

        .identifier => {
            const name = node.data.string;
            printer.printWithLoc(name, node.loc);
        },

        .literal => {
            // ... emit literal
        },

        // ... otros nodos
        else => {},
    }
}
```

## Ejemplo: Target Python

```zig
pub const python_target = TargetPlugin{
    .name = "python",
    .version = .{ .major = 1, .minor = 0, .patch = 0 },
    .file_extension = ".py",
    .emit = py_emit,
};

fn py_emit(ast: *AST, options: EmitOptions) Error!EmitResult {
    var printer = Printer.init(allocator, options);

    for (ast.root.children) |node| {
        switch (node.kind) {
            .variable_decl => {
                // JS: const x = 1;
                // Python: x = 1
                const name = getVarName(node);
                const value = getVarValue(node);
                printer.printf("{s} = ", .{name});
                try emitPyExpr(&printer, value);
                printer.newline();
            },

            .function_decl => {
                // JS: function foo(a, b) { return a + b; }
                // Python: def foo(a, b):\n    return a + b
                printer.print("def ");
                printer.print(getFuncName(node));
                printer.print("(");
                // ... params
                printer.print("):");
                printer.newline();
                printer.indent();
                // ... body
                printer.dedent();
            },

            // ... otros
            else => {},
        }
    }

    return EmitResult{
        .code = printer.toOwnedSlice(),
        .sourcemap = null,
        .metadata = .{...},
    };
}
```

## Dependencias

- **Core**: Tipos, memoria
- **Plugin System**: Registro
- **Language**: AST (para leer)

## Estimacion

- **Lineas**: ~1,500
- **Complejidad**: Media
- **Prioridad**: Alta

## Checklist Implementacion

- [ ] `plugin.zig` - Interface TargetPlugin
- [ ] `emitter.zig` - EmitResult, EmitOptions
- [ ] `printer.zig` - Utilidades de printing
- [ ] `sourcemap.zig` - Generacion source maps
- [ ] `templates.zig` - Templates de modulos
- [ ] `mod.zig` - Re-exports

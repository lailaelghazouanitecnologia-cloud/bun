# Bun VM vs Zid

## Resumen

| Aspecto | Bun VM | Zid |
|---------|--------|-----|
| Líneas | ~3,800 (solo VM) | ~400 (todo) |
| Enfoque | Runtime completo | Transpilador |
| Ejecuta | En memoria (JSC) | Genera código (WAT) |
| Complejidad | Alta | Baja |
| Dependencias | JSC, libuv, etc | Solo std |

## Bun VirtualMachine

```zig
// 3,773 líneas - Estado global para ejecución JS
const VirtualMachine = @This();

// ~50 campos de estado
global: *JSGlobalObject,          // JSC global object
allocator: std.mem.Allocator,
transpiler: Transpiler,           // JS/TS → JS
bun_watcher: ImportWatcher,       // Hot reload
console: *ConsoleObject,
log: *logger.Log,
event_loop_handle: ?*PlatformEventLoop,  // libuv/uws
timer: bun.api.Timer.All,
node_fs: ?*NodeFS,
hot_reload: HotReload,
jsc_vm: *VM,                      // JavaScriptCore VM
plugin_runner: ?PluginRunner,
source_mappings: SavedSourceMap,
macros: MacroMap,
// ... 40+ campos más
```

### Flujo Bun
```
Source → Transpiler → JSC Bytecode → JSC VM → Resultado
           ↓
    (parse, transform)
           ↓
    JavaScriptCore ejecuta en memoria
```

### Dependencias Bun
```
VirtualMachine
├── JSGlobalObject (JSC)
├── Transpiler
│   ├── js_parser.zig (~40K líneas con ast/)
│   ├── js_lexer.zig
│   └── js_printer.zig
├── EventLoop
│   ├── uws (Linux/macOS)
│   └── libuv (Windows)
├── ModuleLoader
├── ConsoleObject
├── Timer
├── NodeFS
└── ... (+20 subsistemas)
```

## Zid

```zig
// ~400 líneas total
// templates.zig - 93 líneas
pub const TokenKind = enum { number, ident, kw_function, ... };
pub const NodeKind = enum { program, func_decl, binary_expr, ... };
pub const keywords = .{ .{ "function", .kw_function }, ... };
pub const operators = .{ .{ "+", .plus }, ... };

// engine.zig - ~300 líneas
pub const Lexer = struct { ... };   // 60 líneas
pub const Parser = struct { ... };  // 120 líneas
pub const Op = struct { ... };      // 70 líneas
pub const Emitter = struct { ... }; // 90 líneas
```

### Flujo Zid
```
Source → Lexer → Parser → Emitter → WAT (texto)
                            ↓
                       Op helpers
                            ↓
                    Archivo .wat listo
```

### Dependencias Zid
```
Zid
├── templates.zig (datos)
└── engine.zig (código)
    ├── Lexer
    ├── Parser
    ├── Op
    └── Emitter

Total: 2 archivos, ~400 líneas
```

## Comparación de Código

### Ejecutar una función

**Bun** (simplificado):
```zig
// 1. Cargar módulo
const source = try fs.readFile(path);

// 2. Transpilar
var transpiler = Transpiler.init(vm, ...);
const result = try transpiler.transpile(source, ...);

// 3. Ejecutar en JSC
const module = try vm.global.evaluateModule(result.code);
try vm.event_loop.tick();

// 4. Manejar resultado
if (vm.unhandled_pending_rejection) |err| {
    // ... manejo de errores
}
```

**Zid**:
```zig
const wat = try compile(source, allocator);
// Listo. wat es texto que puedes:
// - Guardar a archivo
// - Pasar a wasm2binary
// - Ejecutar en browser
```

### Emitir un loop

**Bun** (js_printer.zig):
```zig
fn printWhileStatement(stmt: *Stmt.While) void {
    self.print("while");
    self.printSpace();
    self.print("(");
    self.printExpression(stmt.condition);
    self.print(")");
    self.printSpace();
    self.printStatement(stmt.body);
}
// + manejo de sourcemaps
// + manejo de minificación
// + manejo de ASI
// + ~200 líneas de contexto
```

**Zid**:
```zig
.while_stmt => {
    self.op.block("break");
    self.op.loop("continue");
    self.emitNode(node.children[0]);
    self.op.i32_eqz();
    self.op.br_if("break");
    for (node.children[1].children) |stmt| self.emitNode(stmt);
    self.op.br("continue");
    self.op.end();
    self.op.end();
},
```

## Complejidad

| Componente | Bun | Zid |
|------------|-----|-----|
| Lexer | ~3,400 líneas | ~60 líneas |
| Parser | ~40,000 líneas (con ast/) | ~120 líneas |
| Emitter | ~6,100 líneas | ~90 líneas |
| VM/Runtime | ~3,800 líneas | 0 (genera código) |
| Event Loop | ~800 líneas | 0 |
| **Total core** | **~54,000 líneas** | **~400 líneas** |

## ¿Por qué la diferencia?

### Bun hace más:
- Ejecuta código en memoria
- Event loop async
- Hot reload
- Source maps
- Node.js compatibility
- npm/modules
- Macros
- Plugins en runtime
- Error handling complejo
- GC integration

### Zid hace menos (pero suficiente):
- Solo transpila
- Output es texto
- Sin runtime
- Sin async
- Sin GC
- Templates definen todo

## Cuándo usar cada uno

**Bun**: Runtime completo, compatibilidad Node, producción

**Zid**:
- Aprender compiladores
- DSLs simples
- Generar WASM
- Prototipos rápidos
- Cuando no necesitas runtime

## Conclusión

```
Bun  = Runtime completo = ~850K líneas total
Zid  = Transpilador     = ~400 líneas total

Ratio: 2000:1

Zid NO reemplaza Bun.
Zid es para entender cómo funciona sin la complejidad.
```

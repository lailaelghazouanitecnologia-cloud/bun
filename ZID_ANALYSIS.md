# Zid - Analisis de Arquitectura

## Objetivo

Zid es un runtime configurable y multi-target basado en el analisis de Bun. Permite:
- Definir lenguajes de entrada personalizados
- Emitir a multiples targets (JS, Python, Rust, WASM, etc.)
- Configuracion dinamica de funcionalidades
- Sistema de plugins modular

## Complejidad de Bun por Modulo

| Modulo | Lineas Zig | Archivos | Proposito | Decision Zid |
|--------|------------|----------|-----------|--------------|
| bun.js/ | 151,176 | 344 | Runtime JS, VM, APIs | Reemplazable |
| css/ | 72,651 | 96 | Parser/Processor CSS | Opcional (plugin) |
| install/ | 50,761 | 68 | Package Manager | Opcional (plugin) |
| deps/ | 34,546 | 34 | Dependencias externas | Parcial |
| cli/ | 25,759 | 40 | Comandos CLI | Reusable (dinamico) |
| shell/ | 22,675 | 47 | Shell cross-platform | Opcional (plugin) |
| bundler/ | 21,012 | 38 | Empaquetador | Adaptable |
| http/ | 12,434 | 30 | Cliente/Servidor HTTP | Opcional (plugin) |
| resolver/ | 9,500 | 6 | Resolucion modulos | Core |
| io/ | 4,454 | 8 | I/O asincrono | Core |

## Componentes Core Esenciales (~30K lineas)

```
bun.zig (3,714)     - Punto entrada, imports centralizados
sys.zig (4,349)     - Syscalls cross-platform
env.zig (179)       - Deteccion plataforma compile-time
env_var.zig (673)   - Variables entorno tipadas
cli.zig (1,762)     - Router de comandos
options.zig (2,681) - Configuracion y opciones
fs.zig (2,040)      - Sistema archivos
io/ (4,454)         - I/O asincrono
resolver/ (9,500)   - Resolucion modulos generica
```

## Componentes Especificos de JavaScript (~200K lineas)

Estos seran REEMPLAZADOS por el sistema de plugins:

```
js_printer.zig (6,123)   - Emite codigo JS
js_parser.zig (1,277)    - Wrapper parser
js_lexer.zig (3,403)     - Tokenizer JS
ast/ (330K bytes)        - AST especifico JS/TS
bun.js/bindings/ (150K)  - Bindings JavaScriptCore (C++)
transpiler.zig (1,615)   - Pipeline parse->transform->emit
```

## Arquitectura Zid

```
                          +------------------+
                          |   ZID CORE       |
                          |   (~15K lineas)  |
                          +--------+---------+
                                   |
         +-------------------------+-------------------------+
         |                         |                         |
    +----v----+              +-----v-----+            +------v------+
    | sys.zig |              | Plugin    |            | CLI Router  |
    | env.zig |              | Registry  |            | (dynamic)   |
    | io/     |              |           |            |             |
    +---------+              +-----+-----+            +-------------+
                                   |
         +------------+------------+------------+------------+
         |            |            |            |            |
    +----v----+  +----v----+  +----v----+  +----v----+  +----v----+
    | Lexer   |  | Parser  |  | AST     |  | Trans-  |  | Emitter |
    | Plugin  |  | Plugin  |  | Plugin  |  | former  |  | Plugin  |
    |         |  |         |  |         |  | Plugin  |  |         |
    +---------+  +---------+  +---------+  +---------+  +---------+
```

## Sistema de Plugins

### Interfaz LanguagePlugin

```typescript
interface LanguagePlugin {
  name: string;
  extensions: string[];

  // Lexer
  tokenize(source: string): Token[];

  // Parser
  parse(tokens: Token[]): ASTNode;

  // Transformers
  transform(ast: ASTNode, options: TransformOptions): ASTNode;
}
```

### Interfaz TargetPlugin

```typescript
interface TargetPlugin {
  name: string;

  // Emitter
  emit(ast: ASTNode, options: EmitOptions): string;

  // Sourcemap
  generateSourceMap?(ast: ASTNode): SourceMap;

  // Post-process
  postProcess?(output: string): string;
}
```

## Configuracion (zid.config.ts)

```typescript
export default {
  // Lenguajes de entrada
  languages: {
    "typescript": "@zid/lang-typescript",
    "rust": "zid-lang-rust",
    "mylang": "./plugins/mylang.ts"
  },

  // Targets de salida
  targets: {
    "javascript": "@zid/target-js",
    "python": "@zid/target-python",
    "wasm": "@zid/target-wasm",
  },

  // Pipeline personalizado
  pipeline: {
    parse: ["mylang-parser"],
    transform: ["optimizer", "minifier"],
    emit: ["javascript", "sourcemap"]
  },

  // Modulos opcionales
  modules: {
    http: false,
    bundler: true,
    shell: false,
    packageManager: true
  }
};
```

## Resumen

```
TOTAL BUN:           ~610,000 lineas Zig
                     ~237,000 lineas C++ (JSC bindings)
                     -------------------------
                     ~850,000 lineas codigo core

ZID CORE ESTIMADO:   ~20,000 lineas (sys, env, io, cli base)
                     + Plugins dinamicos segun necesidad

REDUCCION:           ~97% menos codigo base
                     100% configurable
                     Multi-target desde dia 1
```

## Loaders Base (Extensibles via Plugins)

Los loaders actuales de Bun que pueden servir como referencia:

- jsx, js, ts, tsx (JavaScript family)
- css (Stylesheets)
- file (Binary copy)
- json, jsonc, toml, yaml (Data formats)
- wasm (WebAssembly)
- napi (Native addons)
- base64, dataurl, text (Encodings)
- bunsh (Shell scripts)
- sqlite, sqlite_embedded (Database)
- html (Markup)

## Archivos Clave de Referencia

- `/src/bun.zig` - Estructura de imports centralizada
- `/src/sys.zig` - Syscalls cross-platform
- `/src/env.zig` - Deteccion de plataforma
- `/src/cli.zig` - Router de comandos
- `/src/transpiler.zig` - Pipeline de transpilacion
- `/src/js_printer.zig` - Emision de codigo
- `/src/ast/` - Estructura AST

## Proximos Pasos

1. Extraer core minimo de Bun (sys, env, io, cli base)
2. Implementar PluginRegistry
3. Crear interfaces LanguagePlugin y TargetPlugin
4. Implementar primer plugin de lenguaje (TypeScript)
5. Implementar primer target (JavaScript)
6. Sistema de configuracion dinamica
7. Hot reload de plugins

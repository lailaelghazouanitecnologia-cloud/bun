# Zid Test Strategy & Results

## Estado Actual

✅ **155/155 tests pasan** (Zig 0.14.0)

```bash
# Ejecutar tests
zig build test --summary all
```

## Estructura de Tests

```
test/
├── unit/                      # Tests unitarios por módulo
│   ├── versions_test.zig      # Version parsing & comparison
│   ├── resolver_test.zig      # Conflict detection
│   ├── template_test.zig      # Template variables
│   ├── custom_toolchain_test.zig  # Custom toolchains JSON
│   └── api_test.zig           # API module tests
│
├── examples/                  # Ejemplos prácticos de uso
│   ├── download_tool.zig      # Progress bar y URL parsing
│   ├── environment.zig        # Detección de plataforma/CI
│   ├── file_operations.zig    # Operaciones con sys.zig
│   └── toolchain_info.zig     # Versiones y registry info
│
├── toolchain_test.zig         # Toolchain system
├── capsules_test.zig          # Capsules system
├── patches_test.zig           # Patches system
├── framework_test.zig         # Transpiler framework
├── misc_test.zig              # Core patterns (Maybe, collections)
├── apps_test.zig              # Apps registry
├── update_test.zig            # Self-update
├── cli_test.zig               # CLI commands
└── strings_test.zig           # String utilities
```

## Tests por Módulo

### Toolchain (toolchain_test.zig)
| Test | Descripción |
|------|-------------|
| version: parse valid semver | `1.2.3` → major=1, minor=2, patch=3 |
| version: parse with v prefix | `v0.13.0` → major=0, minor=13 |
| version: parse latest | `latest` reconocido como especial |
| version: compare | eq, lt, gt correctos |
| version: format | Version → string |
| constraint: parse exact | `1.2.3` → op=eq |
| constraint: parse caret | `^1.2.0` → op=caret |
| constraint: parse tilde | `~1.2.0` → op=tilde |
| constraint: parse gte | `>=2.0.0` → op=gte |
| constraint: satisfies | Version matches constraint |
| registry: ToolKind enum | bun, zig, node, deno, go, rust |
| registry: get returns valid tool | Tool definitions exist |
| registry: getByName | String lookup works |
| toolchain: supportedTools | Returns tool list |
| toolchain: isSupported | bun, zig supported; unknown not |

### Capsules (capsules_test.zig)
| Test | Descripción |
|------|-------------|
| registry: getBuiltin | webgpu, sqlite existen |
| registry: returns null for unknown | Capsule inexistente |
| registry: isBuiltin | Verifica built-in capsules |
| registry: listBuiltins | ≥6 capsules |
| registry: CapsuleKind | intern vs extern |
| registry: Category | runtime, native, tool, framework |
| manifest: Manifest struct | name, version, description |
| manifest: Dependency struct | Dependencias con optional |
| manifest: Build defaults | src_dir = "src" |
| manifest: MANIFEST_FILES | capsule.json existe |
| integration: ModuleInfo | name, path, dependencies |
| builtin: webgpu category | category = .runtime |
| builtin: sqlite category | category = .native |

### Core Patterns (misc_test.zig)
| Test | Descripción |
|------|-------------|
| maybe: ok returns value | Maybe(T).ok funciona |
| maybe: err returns error | Maybe(T).err con código y mensaje |
| maybe: Error codes | Todos los códigos definidos |
| maybe: Error with path | Path en errores |
| maybe: Error Step enum | read_file, write_file, etc. |
| SmallList: init | Inicialización correcta |

### API Module (api_test.zig)
| Test | Descripción |
|------|-------------|
| fs: paths.basename | Extrae nombre de archivo |
| fs: paths.extension | Extrae extensión |
| fs: paths.dirname | Extrae directorio |
| search: Match struct | file, line, column, text |
| search: FindOptions | Defaults sensatos |
| shell: ExecResult.ok | success=true, exit_code=0 |
| shell: ExecResult con error | success=false, exit_code=1 |
| shell: ExecOptions | capture_stdout/stderr defaults |
| shell: hasCommand | Encuentra comandos del sistema |
| http: Response.ok | Status 2xx es ok |
| http: Method enum | GET, POST, PUT, DELETE |
| http: Header struct | name, value |
| json: module exports | parseValue, stringify existen |

### Framework (framework_test.zig)
| Test | Descripción |
|------|-------------|
| IR: NodeKind values | expression, statement, etc. |
| IR: Node struct | kind, range, parent |
| pipeline: Stage enum | parse, transform, codegen |
| pipeline: Pipeline struct | name, stages |
| metadata: SourceLocation | file, line, column |
| metadata: Diagnostic | severity, message, location |

### CLI (cli_test.zig)
| Test | Descripción |
|------|-------------|
| command parsing | help, install, add, etc. |
| help flags | -h, --help |
| version flags | -v, --version |

### Examples (test/examples/)

Ejemplos prácticos que demuestran uso real de la API:

| Archivo | Descripción |
|---------|-------------|
| `download_tool.zig` | Progress bar, URL parsing, platform detection |
| `environment.zig` | Detección de plataforma (Linux/macOS/Windows), CI, env vars |
| `file_operations.zig` | sys.zig: stat, mkdir, read/write files |
| `toolchain_info.zig` | Version parsing, comparison, constraints, registry |

```bash
# Ejecutar solo ejemplos
zig build test -- --test-filter "example:"
```

## Principios de Testing

### 1. Test Comportamiento, No Implementación
```zig
// ✅ BIEN - Testa el contrato
test "Version.parse handles semver" {
    const v = versions.Version.parse("1.0.0").ok;
    try testing.expect(v.major == 1);
}

// ❌ MAL - Testa implementación interna
test "Version uses u32 for major" {
    // Esto falla si cambias el tipo interno
}
```

### 2. Test Edge Cases Reales
```zig
// ✅ BIEN - Edge case que causa bugs
test "constraint: satisfies exact" {
    const c = versions.Constraint{ .op = .eq, .version = .{...} };
    try testing.expect(c.satisfies(.{ .major = 1, .minor = 2, .patch = 3 }));
    try testing.expect(!c.satisfies(.{ .major = 1, .minor = 2, .patch = 4 }));
}

// ❌ MAL - Caso obvio
test "1 + 1 = 2" {}
```

### 3. No Test Wrappers de std
```zig
// ❌ NO testear - es un wrapper de std
pub fn isDir(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}
```

## Qué NO Testear

1. **Output/UI** - Cambia constantemente
2. **Wrappers de std** - Confía en Zig
3. **Código que solo delega** - No hay lógica
4. **Casos triviales** - No aportan valor

## Comandos

```bash
# Todos los tests
zig build test

# Con summary detallado
zig build test --summary all

# Test específico
zig build test -- --test-filter "version"

# Verbose
zig build test -- --verbose
```

## Requisitos

- **Zig 0.14.0+** - Usa `@branchHint` en lugar de `@setCold`
- **Linux/macOS** - Tests usan comandos Unix (`ls`)

## Notas

- Los tests no requieren acceso a red (no hacen HTTP real)
- Todos los tests son determinísticos
- Tiempo de ejecución: ~2 segundos

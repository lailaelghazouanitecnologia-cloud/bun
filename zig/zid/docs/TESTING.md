# Zid Test Strategy

## Principios

1. **Test comportamiento, no implementación** - Si cambias internals, tests no deberían fallar
2. **Test los contratos públicos** - API que usuarios/otros módulos usan
3. **Test edge cases que causan bugs reales** - No casos obvios
4. **No test por coverage** - Coverage 100% != código correcto

## Qué Testear

### 1. CRÍTICO - Parsing y Validación

```
┌─────────────────────────────────────────────────────────┐
│  Input del usuario → Parse → Validación → Acción       │
│                      ^^^^^^                             │
│                      AQUÍ es donde fallan las cosas    │
└─────────────────────────────────────────────────────────┘
```

- **Version parsing**: "1.0.0", "latest", "1.0.0-beta", malformado
- **ToolSpec parsing**: "bun@1.0", "bun", "@1.0" (inválido)
- **URL template expansion**: {version}, {os}, {arch}
- **JSON config**: toolchains.json, apps.json, capsule.json

### 2. IMPORTANTE - Lógica de Negocio

- **Conflict detection**: Sistema tiene bun, zid tiene bun
- **Path resolution**: ~/.zid/bin vs /usr/bin
- **Template variables**: {{name}}, {{version}}

### 3. ÚTIL - Edge Cases

- Path vacío
- Versión "0.0.0"
- Archivo no existe
- Permisos denegados
- JSON malformado

## Qué NO Testear

### Trivial
```zig
// NO testear esto:
pub fn isDir(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}
// Es un wrapper de std, si falla es bug de Zig
```

### Output/UI
```zig
// NO testear esto:
Output.print("Installing {s}...\n", .{name});
// Cambia constantemente, no es lógica
```

### Código que solo delega
```zig
// NO testear esto:
pub fn install(spec: []const u8) Maybe(Result) {
    return installer.install(spec);  // Solo delega
}
```

## Estructura de Tests

```
test/
├── unit/
│   ├── versions_test.zig      # Version parsing
│   ├── maybe_test.zig         # Maybe(T) pattern
│   ├── json_test.zig          # JSON helpers
│   └── template_test.zig      # Variable substitution
│
├── integration/
│   ├── toolchain_test.zig     # Install flow (mock HTTP)
│   ├── capsule_test.zig       # Capsule + shell.rc
│   └── conflict_test.zig      # System vs zid conflict
│
└── fixtures/
    ├── valid_config.json
    ├── invalid_config.json
    └── mock_responses/
```

## Ejemplos de Buenos Tests

### ✅ Buen test - Comportamiento específico
```zig
test "Version.parse handles semver with prerelease" {
    const v = Version.parse("1.0.0-beta.1").unwrap();
    try testing.expectEqual(@as(u32, 1), v.major);
    try testing.expectEqualStrings("beta.1", v.prerelease.?);
}
```

### ❌ Mal test - Obvio/trivial
```zig
test "Version has major field" {
    const v = Version{ .major = 1 };
    try testing.expectEqual(@as(u32, 1), v.major);
}
```

### ✅ Buen test - Edge case real
```zig
test "ToolSpec.parse rejects empty name" {
    const result = ToolSpec.parse("@1.0.0");
    try testing.expect(result == .err);
    try testing.expectEqual(ErrorCode.invalid_input, result.err.code);
}
```

### ❌ Mal test - Test de implementación
```zig
test "installer calls downloader" {
    // Testea implementación, no comportamiento
    // Si cambias cómo funciona internamente, test falla
}
```

## Fixtures Necesarios

### toolchains.json (válido)
```json
{
  "gleam": {
    "url_template": "https://example.com/{version}/gleam-{os}.tar.gz",
    "binary": "gleam"
  }
}
```

### toolchains.json (inválido - falta url)
```json
{
  "broken": {
    "binary": "broken"
  }
}
```

## Comandos

```bash
# Todos los tests
zig build test

# Test específico
zig build test -- --test-filter "Version.parse"

# Con verbose
zig build test -- --verbose
```

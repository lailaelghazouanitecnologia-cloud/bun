//! Conflict Resolver Tests
//!
//! Tests para detección de conflictos entre toolchains del sistema y zid.
//! Crítico para UX - el usuario debe saber cuándo hay conflictos.

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");
const resolver = zid.toolchain.resolver;

// ============================================================================
// DETECCIÓN DE COMANDOS DEL SISTEMA
// ============================================================================

test "findSystemCommand: encuentra comando existente" {
    // 'ls' debería existir en todos los sistemas Unix
    const result = resolver.findSystemCommand(testing.allocator, "ls");
    try testing.expect(result != null);
    if (result) |path| {
        defer testing.allocator.free(path);
        try testing.expect(std.mem.indexOf(u8, path, "ls") != null);
    }
}

test "findSystemCommand: retorna null para comando inexistente" {
    const result = resolver.findSystemCommand(testing.allocator, "comando_que_no_existe_12345_xyz");
    try testing.expect(result == null);
}

test "findSystemCommand: no incluye ~/.zid/bin" {
    // Este test verifica que findSystemCommand excluye el directorio de zid
    // para evitar detectar conflictos falsos
    const result = resolver.findSystemCommand(testing.allocator, "ls");
    if (result) |path| {
        defer testing.allocator.free(path);
        // No debería contener ".zid/bin"
        try testing.expect(std.mem.indexOf(u8, path, ".zid/bin") == null);
    }
}

// ============================================================================
// DETECCIÓN DE CONFLICTOS
// ============================================================================

test "detectConflict: retorna null cuando no hay toolchain de zid" {
    // Para un comando que existe en sistema pero no en zid
    const result = resolver.detectConflict(testing.allocator, "ls");
    // 'ls' no es un toolchain de zid, así que no hay conflicto
    try testing.expect(result == null);
}

test "detectConflict: retorna null para comando inexistente" {
    const result = resolver.detectConflict(testing.allocator, "zid_test_fake_command_999");
    try testing.expect(result == null);
}

// ============================================================================
// ESTRUCTURA DE CONFLICTO
// ============================================================================

test "Conflict: struct tiene campos correctos" {
    const conflict = resolver.Conflict{
        .command = "bun",
        .system_path = "/usr/bin/bun",
        .zid_path = "/home/user/.zid/bin/bun",
        .priority = .system,
    };

    try testing.expectEqualStrings("bun", conflict.command);
    try testing.expectEqualStrings("/usr/bin/bun", conflict.system_path);
    try testing.expectEqual(resolver.Conflict.Priority.system, conflict.priority);
}

test "Conflict.Priority: valores de enum" {
    try testing.expect(@intFromEnum(resolver.Conflict.Priority.system) != @intFromEnum(resolver.Conflict.Priority.zid));
}

// ============================================================================
// ALIAS
// ============================================================================

test "Alias: struct tiene campos correctos" {
    const alias = resolver.Alias{
        .name = "bun",
        .target = "/path/to/bun",
        .is_zid = true,
    };

    try testing.expectEqualStrings("bun", alias.name);
    try testing.expect(alias.is_zid);
}

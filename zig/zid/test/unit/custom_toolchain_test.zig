//! Custom Toolchain Tests
//!
//! Tests para el sistema de toolchains personalizados.
//! Crítico: parsing de toolchains.json y validación.

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");
const custom = zid.toolchain.custom;

// ============================================================================
// CustomToolchain STRUCT
// ============================================================================

test "CustomToolchain: campos básicos" {
    const tc = custom.CustomToolchain{
        .name = "gleam",
        .description = "Gleam language",
        .url_template = "https://example.com/{version}/gleam.tar.gz",
        .binary = "gleam",
    };

    try testing.expectEqualStrings("gleam", tc.name);
    try testing.expectEqualStrings("Gleam language", tc.description);
}

test "CustomToolchain: archive default es tar_gz" {
    const tc = custom.CustomToolchain{
        .name = "test",
        .url_template = "https://example.com/test.tar.gz",
        .binary = "test",
    };

    try testing.expectEqual(custom.CustomToolchain.Archive.tar_gz, tc.archive);
}

test "CustomToolchain.Archive.fromString: reconoce formatos" {
    try testing.expectEqual(custom.CustomToolchain.Archive.tar_gz, custom.CustomToolchain.Archive.fromString("tar_gz"));
    try testing.expectEqual(custom.CustomToolchain.Archive.tar_gz, custom.CustomToolchain.Archive.fromString("tar.gz"));
    try testing.expectEqual(custom.CustomToolchain.Archive.tar_xz, custom.CustomToolchain.Archive.fromString("tar_xz"));
    try testing.expectEqual(custom.CustomToolchain.Archive.zip, custom.CustomToolchain.Archive.fromString("zip"));
    try testing.expectEqual(custom.CustomToolchain.Archive.none, custom.CustomToolchain.Archive.fromString("none"));
    try testing.expectEqual(custom.CustomToolchain.Archive.none, custom.CustomToolchain.Archive.fromString("binary"));
}

test "CustomToolchain.Archive.fromString: default para desconocido" {
    try testing.expectEqual(custom.CustomToolchain.Archive.tar_gz, custom.CustomToolchain.Archive.fromString("unknown_format"));
}

// ============================================================================
// DATABASE
// ============================================================================

test "Database: init no crashea" {
    var db = custom.Database.init(testing.allocator);
    defer db.deinit();

    // Debería inicializar vacío
    try testing.expect(!db.has("anything"));
}

test "Database: get retorna null para inexistente" {
    var db = custom.Database.init(testing.allocator);
    defer db.deinit();

    try testing.expect(db.get("nonexistent") == null);
}

// ============================================================================
// TOOLDEF CONVERSION
// ============================================================================

test "toToolDef: convierte CustomToolchain a ToolDef" {
    const tc = custom.CustomToolchain{
        .name = "mytools",
        .description = "My tools",
        .homepage = "https://example.com",
        .url_template = "https://example.com/{version}/tool.zip",
        .archive = .zip,
        .binary = "mytool",
        .binary_path = "bin",
    };

    const def = tc.toToolDef();

    try testing.expectEqualStrings("mytools", def.name);
    try testing.expectEqualStrings("My tools", def.description);
    try testing.expectEqualStrings("mytool", def.binary);
    try testing.expectEqual(zid.toolchain.registry.ToolDef.Archive.zip, def.archive);
}

// ============================================================================
// URL TEMPLATE - Crítico para descargas
// ============================================================================

test "url_template: contiene placeholders esperados" {
    const tc = custom.CustomToolchain{
        .name = "test",
        .url_template = "https://example.com/{version}/tool-{os}-{arch}.tar.gz",
        .binary = "test",
    };

    try testing.expect(std.mem.indexOf(u8, tc.url_template, "{version}") != null);
    try testing.expect(std.mem.indexOf(u8, tc.url_template, "{os}") != null);
    try testing.expect(std.mem.indexOf(u8, tc.url_template, "{arch}") != null);
}

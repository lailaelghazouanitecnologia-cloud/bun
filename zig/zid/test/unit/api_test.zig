//! API Module Tests
//!
//! Tests para la API pública de Zid.
//! Solo testeamos lógica, no wrappers de std.

const std = @import("std");
const testing = std.testing;

// ============================================================================
// FS - Solo lógica, no wrappers
// ============================================================================

test "fs: basename extrae nombre de archivo" {
    const fs = @import("../src/api/fs.zig");

    try testing.expectEqualStrings("file.txt", fs.basename("/path/to/file.txt"));
    try testing.expectEqualStrings("file.txt", fs.basename("file.txt"));
}

test "fs: extname extrae extensión" {
    const fs = @import("../src/api/fs.zig");

    try testing.expectEqualStrings(".txt", fs.extname("file.txt"));
    try testing.expectEqualStrings(".gz", fs.extname("file.tar.gz"));
    try testing.expectEqualStrings("", fs.extname("noext"));
}

test "fs: dirname extrae directorio" {
    const fs = @import("../src/api/fs.zig");

    try testing.expectEqualStrings("/path/to", fs.dirname("/path/to/file.txt").?);
    try testing.expect(fs.dirname("file.txt") == null);
}

// ============================================================================
// SEARCH - Lógica de patrones
// ============================================================================

test "search: Match struct tiene campos correctos" {
    const search = @import("../src/api/search.zig");

    const match = search.Match{
        .file = "src/main.zig",
        .line = 42,
        .column = 10,
        .text = "TODO: fix this",
    };

    try testing.expectEqualStrings("src/main.zig", match.file);
    try testing.expectEqual(@as(u32, 42), match.line);
}

test "search: FindOptions tiene defaults sensatos" {
    const search = @import("../src/api/search.zig");

    const opts = search.FindOptions{};

    try testing.expect(opts.ext == null);
    try testing.expect(opts.min_size == null);
    try testing.expect(!opts.files_only);
    try testing.expect(!opts.dirs_only);
}

// ============================================================================
// SHELL - Estructuras de resultado
// ============================================================================

test "shell: ExecResult.ok verifica success" {
    const shell = @import("../src/api/shell.zig");

    const success = shell.ExecResult{
        .stdout = "output",
        .stderr = "",
        .exit_code = 0,
        .success = true,
    };

    try testing.expect(success.success);
    try testing.expectEqual(@as(u8, 0), success.exit_code);
}

test "shell: ExecResult con error" {
    const shell = @import("../src/api/shell.zig");

    const failure = shell.ExecResult{
        .stdout = "",
        .stderr = "error message",
        .exit_code = 1,
        .success = false,
    };

    try testing.expect(!failure.success);
    try testing.expectEqual(@as(u8, 1), failure.exit_code);
}

test "shell: ExecOptions tiene defaults" {
    const shell = @import("../src/api/shell.zig");

    const opts = shell.ExecOptions{};

    try testing.expect(opts.cwd == null);
    try testing.expect(opts.capture_stdout);
    try testing.expect(opts.capture_stderr);
}

test "shell: hasCommand encuentra comandos del sistema" {
    const shell = @import("../src/api/shell.zig");

    // 'ls' debería existir en sistemas Unix
    try testing.expect(shell.hasCommand("ls"));
    try testing.expect(!shell.hasCommand("comando_inexistente_xyz_123"));
}

// ============================================================================
// HTTP - Estructuras
// ============================================================================

test "http: Response.ok verifica status 2xx" {
    const http = @import("../src/api/http.zig");

    const ok_resp = http.Response{
        .status = 200,
        .body = "{}",
        .headers = &.{},
    };
    try testing.expect(ok_resp.ok());

    const created = http.Response{
        .status = 201,
        .body = "{}",
        .headers = &.{},
    };
    try testing.expect(created.ok());

    const not_found = http.Response{
        .status = 404,
        .body = "{}",
        .headers = &.{},
    };
    try testing.expect(!not_found.ok());

    const server_error = http.Response{
        .status = 500,
        .body = "{}",
        .headers = &.{},
    };
    try testing.expect(!server_error.ok());
}

test "http: Method enum tiene valores correctos" {
    const http = @import("../src/api/http.zig");

    try testing.expect(http.Method.GET != http.Method.POST);
    try testing.expect(http.Method.PUT != http.Method.DELETE);
}

test "http: Header struct" {
    const http = @import("../src/api/http.zig");

    const header = http.Header{
        .name = "Content-Type",
        .value = "application/json",
    };

    try testing.expectEqualStrings("Content-Type", header.name);
    try testing.expectEqualStrings("application/json", header.value);
}

// ============================================================================
// JSON - Helpers
// ============================================================================

test "json: parseValue no crashea con JSON válido" {
    const json = @import("../src/api/json.zig");

    const content = "{\"key\": \"value\"}";
    // Solo verificamos que no crashea
    _ = json.parseValue(testing.allocator, content) catch {};
}

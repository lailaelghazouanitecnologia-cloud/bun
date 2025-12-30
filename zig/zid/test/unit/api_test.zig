//! API Module Tests
//!
//! Tests para la API pública de Zid.
//! Solo testeamos lógica, no wrappers de std.

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");

// ============================================================================
// FS - Solo lógica, no wrappers
// ============================================================================

test "fs: paths.basename extrae nombre de archivo" {
    try testing.expectEqualStrings("file.txt", zid.fs.paths.basename("/path/to/file.txt"));
    try testing.expectEqualStrings("file.txt", zid.fs.paths.basename("file.txt"));
}

test "fs: paths.extension extrae extensión" {
    try testing.expectEqualStrings(".txt", zid.fs.paths.extension("file.txt"));
    try testing.expectEqualStrings(".gz", zid.fs.paths.extension("file.tar.gz"));
    try testing.expectEqualStrings("", zid.fs.paths.extension("noext"));
}

test "fs: paths.dirname extrae directorio" {
    try testing.expectEqualStrings("/path/to", zid.fs.paths.dirname("/path/to/file.txt"));
    try testing.expectEqualStrings(".", zid.fs.paths.dirname("file.txt"));
}

// ============================================================================
// SEARCH - Lógica de patrones
// ============================================================================

test "search: Match struct tiene campos correctos" {
    const search = zid.api.search;

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
    const search = zid.api.search;

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
    const shell = zid.api.shell;

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
    const shell = zid.api.shell;

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
    const shell = zid.api.shell;

    const opts = shell.ExecOptions{};

    try testing.expect(opts.cwd == null);
    try testing.expect(opts.capture_stdout);
    try testing.expect(opts.capture_stderr);
}

test "shell: hasCommand encuentra comandos del sistema" {
    const shell = zid.api.shell;

    // 'ls' debería existir en sistemas Unix
    try testing.expect(shell.hasCommand("ls"));
    try testing.expect(!shell.hasCommand("comando_inexistente_xyz_123"));
}

// ============================================================================
// HTTP - Estructuras
// ============================================================================

test "http: Response.ok verifica status 2xx" {
    const http = zid.api.http;
    var body_buf: [2]u8 = "{}".*;

    const ok_resp = http.Response{
        .status = 200,
        .body = &body_buf,
        .headers = &.{},
    };
    try testing.expect(ok_resp.ok());

    const created = http.Response{
        .status = 201,
        .body = &body_buf,
        .headers = &.{},
    };
    try testing.expect(created.ok());

    const not_found = http.Response{
        .status = 404,
        .body = &body_buf,
        .headers = &.{},
    };
    try testing.expect(!not_found.ok());

    const server_error = http.Response{
        .status = 500,
        .body = &body_buf,
        .headers = &.{},
    };
    try testing.expect(!server_error.ok());
}

test "http: Method enum tiene valores correctos" {
    const http = zid.api.http;

    try testing.expect(http.Method.GET != http.Method.POST);
    try testing.expect(http.Method.PUT != http.Method.DELETE);
}

test "http: Header struct" {
    const http = zid.api.http;

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

test "json: module exports exist" {
    const json = zid.api.json;
    // Verify module exports exist (no runtime allocation)
    _ = json.parseValue;
    _ = json.stringify;
}

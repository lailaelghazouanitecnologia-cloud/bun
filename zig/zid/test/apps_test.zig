//! Apps Registry Tests

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");
const apps = zid.apps;
const db = apps.db;

test "AppKind enum values" {
    const binary = db.AppKind.binary;
    const script = db.AppKind.script;
    const project = db.AppKind.project;

    try testing.expectEqual(@as(u2, 0), @intFromEnum(binary));
    try testing.expectEqual(@as(u2, 1), @intFromEnum(script));
    try testing.expectEqual(@as(u2, 2), @intFromEnum(project));
}

test "AppEntry struct" {
    const entry = db.AppEntry{
        .name = "myapp",
        .path = "/usr/local/bin/myapp",
        .kind = .binary,
        .added_at = 1234567890,
    };

    try testing.expectEqualStrings("myapp", entry.name);
    try testing.expectEqualStrings("/usr/local/bin/myapp", entry.path);
    try testing.expectEqual(db.AppKind.binary, entry.kind);
}

test "Database init" {
    const alloc = testing.allocator;
    var database = db.Database.init(alloc);
    defer database.deinit();

    // Database should start empty
    try testing.expect(!database.has("anything"));
    try testing.expect(database.get("anything") == null);
}

test "Database add and get" {
    const alloc = testing.allocator;
    var database = db.Database.init(alloc);
    defer database.deinit();

    const entry = db.AppEntry{
        .name = "testapp",
        .path = "/test/path",
        .kind = .script,
        .added_at = 0,
    };

    // Add entry directly to hashmap (bypassing save)
    try database.entries.put(entry.name, entry);

    try testing.expect(database.has("testapp"));
    const retrieved = database.get("testapp");
    try testing.expect(retrieved != null);
    try testing.expectEqual(db.AppKind.script, retrieved.?.kind);
}

test "script extension detection" {
    // Script extensions
    const js_ext = std.fs.path.extension("file.js");
    try testing.expectEqualStrings(".js", js_ext);

    const ts_ext = std.fs.path.extension("file.ts");
    try testing.expectEqualStrings(".ts", ts_ext);

    const py_ext = std.fs.path.extension("file.py");
    try testing.expectEqualStrings(".py", py_ext);
}

test "path stem extraction" {
    const stem1 = std.fs.path.stem("myprogram.js");
    try testing.expectEqualStrings("myprogram", stem1);

    const stem2 = std.fs.path.stem("/path/to/app.exe");
    try testing.expectEqualStrings("app", stem2);

    const stem3 = std.fs.path.stem("noext");
    try testing.expectEqualStrings("noext", stem3);
}

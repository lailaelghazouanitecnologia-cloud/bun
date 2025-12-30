//! Capsules System Tests

const std = @import("std");
const testing = std.testing;

const capsules = @import("../src/capsules/capsules.zig");
const registry = @import("../src/capsules/registry.zig");
const manifest = @import("../src/capsules/manifest.zig");
const integration = @import("../src/capsules/integration.zig");

// ============ REGISTRY TESTS ============

test "registry: getBuiltin returns known capsules" {
    const webgpu = registry.getBuiltin("webgpu");
    try testing.expect(webgpu != null);
    try testing.expectEqualStrings("webgpu", webgpu.?.name);
    try testing.expectEqualStrings("0.1.0", webgpu.?.version);

    const sqlite = registry.getBuiltin("sqlite");
    try testing.expect(sqlite != null);
    try testing.expectEqualStrings("sqlite", sqlite.?.name);
}

test "registry: getBuiltin returns null for unknown" {
    const unknown = registry.getBuiltin("nonexistent-capsule");
    try testing.expect(unknown == null);
}

test "registry: isBuiltin" {
    try testing.expect(registry.isBuiltin("webgpu"));
    try testing.expect(registry.isBuiltin("wasm"));
    try testing.expect(registry.isBuiltin("sqlite"));
    try testing.expect(registry.isBuiltin("crypto"));
    try testing.expect(!registry.isBuiltin("unknown"));
    try testing.expect(!registry.isBuiltin(""));
}

test "registry: listBuiltins returns all" {
    const builtins = registry.listBuiltins();
    try testing.expect(builtins.len >= 6); // webgpu, wasm, sqlite, crypto, http2, image
}

test "registry: CapsuleKind values" {
    const intern: registry.CapsuleKind = .intern;
    const extern_: registry.CapsuleKind = .extern_;
    try testing.expect(intern != extern_);
}

test "registry: Category values" {
    const categories = [_]registry.Category{ .runtime, .native, .tool, .framework };
    try testing.expect(categories.len == 4);
}

// ============ MANIFEST TESTS ============

test "manifest: parseJson valid" {
    const json =
        \\{
        \\  "name": "test-capsule",
        \\  "version": "1.2.3",
        \\  "description": "A test capsule"
        \\}
    ;

    switch (manifest.parseJson(testing.allocator, json)) {
        .ok => |m| {
            try testing.expectEqualStrings("test-capsule", m.name);
            try testing.expectEqualStrings("1.2.3", m.version);
            try testing.expectEqualStrings("A test capsule", m.description);
        },
        .err => |e| {
            std.debug.print("Parse error: {s}\n", .{e.message});
            try testing.expect(false);
        },
    }
}

test "manifest: parseJson with dependencies" {
    const json =
        \\{
        \\  "name": "with-deps",
        \\  "version": "0.1.0",
        \\  "dependencies": {
        \\    "sqlite": "^1.0.0",
        \\    "crypto": "*"
        \\  }
        \\}
    ;

    switch (manifest.parseJson(testing.allocator, json)) {
        .ok => |m| {
            try testing.expectEqualStrings("with-deps", m.name);
            try testing.expect(m.dependencies.len == 2);
        },
        .err => {
            try testing.expect(false);
        },
    }
}

test "manifest: parseJson missing name fails" {
    const json =
        \\{
        \\  "version": "1.0.0"
        \\}
    ;

    switch (manifest.parseJson(testing.allocator, json)) {
        .ok => try testing.expect(false), // Should fail
        .err => |e| {
            try testing.expect(std.mem.indexOf(u8, e.message, "name") != null);
        },
    }
}

test "manifest: parseJson missing version fails" {
    const json =
        \\{
        \\  "name": "no-version"
        \\}
    ;

    switch (manifest.parseJson(testing.allocator, json)) {
        .ok => try testing.expect(false),
        .err => |e| {
            try testing.expect(std.mem.indexOf(u8, e.message, "version") != null);
        },
    }
}

test "manifest: parseJson invalid json fails" {
    const json = "{ invalid json }";

    switch (manifest.parseJson(testing.allocator, json)) {
        .ok => try testing.expect(false),
        .err => {}, // Expected to fail
    }
}

test "manifest: MANIFEST_FILES contains expected files" {
    const files = manifest.MANIFEST_FILES;
    try testing.expect(files.len >= 3);

    var has_json = false;
    for (files) |f| {
        if (std.mem.eql(u8, f, "capsule.json")) {
            has_json = true;
        }
    }
    try testing.expect(has_json);
}

// ============ INTEGRATION TESTS ============

test "integration: ModuleInfo struct" {
    const info = integration.ModuleInfo{
        .name = "test-module",
        .path = "/path/to/test.zig",
        .dependencies = &.{},
    };

    try testing.expectEqualStrings("test-module", info.name);
    try testing.expectEqualStrings("/path/to/test.zig", info.path);
    try testing.expect(info.dependencies.len == 0);
}

// ============ MANAGER TESTS ============

test "manager: init creates valid manager" {
    var mgr = capsules.Manager.init(testing.allocator);
    try testing.expect(mgr.home_dir.len > 0);
    try testing.expect(mgr.capsules_dir.len > 0);
    try testing.expect(mgr.intern_dir.len > 0);
    try testing.expect(mgr.extern_dir.len > 0);

    // Paths should be related
    try testing.expect(std.mem.indexOf(u8, mgr.capsules_dir, "capsules") != null);
    try testing.expect(std.mem.indexOf(u8, mgr.intern_dir, "intern") != null);
    try testing.expect(std.mem.indexOf(u8, mgr.extern_dir, "extern") != null);
}

test "manager: get returns null for non-installed" {
    var mgr = capsules.Manager.init(testing.allocator);
    const result = mgr.get("definitely-not-installed-12345");
    try testing.expect(result == null);
}

// ============ CAPSULE STRUCT TESTS ============

test "capsule: struct fields" {
    const cap = registry.Capsule{
        .name = "test",
        .version = "1.0.0",
        .kind = .intern,
        .path = "/path/to/capsule",
        .description = "Test capsule",
    };

    try testing.expectEqualStrings("test", cap.name);
    try testing.expectEqualStrings("1.0.0", cap.version);
    try testing.expect(cap.kind == .intern);
}

// ============ BUILTIN CAPSULE TESTS ============

test "builtin: webgpu has correct category" {
    const webgpu = registry.getBuiltin("webgpu").?;
    try testing.expect(webgpu.category == .runtime);
}

test "builtin: sqlite has correct category" {
    const sqlite = registry.getBuiltin("sqlite").?;
    try testing.expect(sqlite.category == .native);
}

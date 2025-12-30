//! Capsules System Tests

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");

const capsules = zid.capsules;
const registry = capsules.registry;
const manifest = capsules.manifest;
const integration = capsules.integration;

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

test "manifest: Manifest struct fields" {
    const m = manifest.Manifest{
        .name = "test",
        .version = "1.0.0",
        .description = "Test capsule",
    };
    try testing.expectEqualStrings("test", m.name);
    try testing.expectEqualStrings("1.0.0", m.version);
}

test "manifest: Dependency struct" {
    const dep = manifest.Manifest.Dependency{
        .name = "sqlite",
        .version = "^1.0.0",
    };
    try testing.expectEqualStrings("sqlite", dep.name);
    try testing.expect(!dep.optional);
}

test "manifest: Build struct defaults" {
    const build = manifest.Manifest.Build{};
    try testing.expectEqualStrings("src", build.src_dir);
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

test "manager: Manager struct exists" {
    // Just verify struct exists and can be accessed
    _ = capsules.Manager;
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

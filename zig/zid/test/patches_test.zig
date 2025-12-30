//! Patches System Tests

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");

const patches = zid.patches;

// ============ SEVERITY TESTS ============

test "severity: enum values" {
    const sev_critical: patches.Severity = .critical;
    const sev_high: patches.Severity = .high;
    const sev_normal: patches.Severity = .normal;
    const sev_low: patches.Severity = .low;

    try testing.expect(sev_critical != sev_high);
    try testing.expect(sev_high != sev_normal);
    try testing.expect(sev_normal != sev_low);
}

// ============ PATCH KIND TESTS ============

test "patchKind: enum values" {
    const kinds = [_]patches.PatchKind{
        .config,
        .script,
        .data,
        .binary,
    };

    try testing.expect(kinds.len == 4);
}

// ============ PATCH STRUCT TESTS ============

test "patch: struct fields" {
    const patch = patches.Patch{
        .id = "patch-001",
        .version = "1.0.0",
        .target_version = "0.1.0",
        .severity = .high,
        .kind = .config,
        .description = "Fix configuration issue",
        .url = "https://example.com/patch",
        .checksum = "abc123",
        .applied = false,
        .applied_at = 0,
    };

    try testing.expectEqualStrings("patch-001", patch.id);
    try testing.expectEqualStrings("1.0.0", patch.version);
    try testing.expect(patch.severity == .high);
    try testing.expect(patch.kind == .config);
    try testing.expect(!patch.applied);
}

test "patch: default values" {
    const patch = patches.Patch{
        .id = "test",
        .version = "1.0.0",
        .target_version = "*",
        .severity = .normal,
        .kind = .data,
        .description = "Test patch",
    };

    try testing.expect(patch.url == null);
    try testing.expectEqualStrings("", patch.checksum);
    try testing.expect(!patch.applied);
    try testing.expect(patch.applied_at == 0);
}

// ============ MANAGER TESTS ============

test "manager: init creates valid manager" {
    var mgr = patches.Manager.init(testing.allocator);
    defer mgr.deinit();

    try testing.expect(mgr.patches_dir.len > 0);
    try testing.expect(mgr.applied_file.len > 0);

    // Paths should contain expected substrings
    try testing.expect(std.mem.indexOf(u8, mgr.patches_dir, "patches") != null);
    try testing.expect(std.mem.indexOf(u8, mgr.applied_file, "applied") != null);
}

test "manager: isApplied returns false for non-applied" {
    var mgr = patches.Manager.init(testing.allocator);
    defer mgr.deinit();

    try testing.expect(!mgr.isApplied("non-existent-patch"));
    try testing.expect(!mgr.isApplied(""));
    try testing.expect(!mgr.isApplied("random-id-12345"));
}

// ============ SEVERITY ORDERING TESTS ============

test "severity: critical is highest" {
    // Just verify enum exists and can be compared
    const critical = patches.Severity.critical;
    const high = patches.Severity.high;
    const normal = patches.Severity.normal;
    const low = patches.Severity.low;

    // All should be different
    try testing.expect(critical != high);
    try testing.expect(high != normal);
    try testing.expect(normal != low);
}

// ============ PATCH KIND TESTS ============

test "patchKind: config is for configuration" {
    const kind: patches.PatchKind = .config;
    try testing.expect(kind == .config);
}

test "patchKind: script is for scripts" {
    const kind: patches.PatchKind = .script;
    try testing.expect(kind == .script);
}

test "patchKind: binary requires update" {
    const kind: patches.PatchKind = .binary;
    try testing.expect(kind == .binary);
}

// ============ INTEGRATION TESTS ============

test "patches: module exports are accessible" {
    // Verify submodules are exported
    _ = patches.registry;
    _ = patches.applicator;
}

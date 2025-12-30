//! Capsule Registry - Built-in and external capsule definitions
//!
//! Defines available capsules:
//! - intern: Built-in capsules bundled with zid
//! - extern: External capsules fetched from registry

const std = @import("std");
const zid = @import("../zid.zig");
const Maybe = zid.Maybe;

/// Capsule kind
pub const CapsuleKind = enum {
    intern, // Built-in, bundled
    extern_, // External, fetched
};

/// Capsule category
pub const Category = enum {
    runtime, // Runtime/VM bindings (webgpu, wasm)
    native, // Native library bindings
    tool, // Development tools
    framework, // Framework integrations
};

/// A capsule instance
pub const Capsule = struct {
    name: []const u8,
    version: []const u8,
    kind: CapsuleKind,
    path: []const u8,
    description: []const u8,
    category: Category = .native,
    dependencies: []const []const u8 = &.{},
};

/// Built-in capsule definition
pub const BuiltinCapsule = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    category: Category,
    /// Source files to copy (relative to zid source)
    sources: []const []const u8 = &.{},
    /// Build commands
    build_cmd: ?[]const u8 = null,
};

/// Built-in capsules registry
pub const builtins = [_]BuiltinCapsule{
    // WebGPU bindings (Rust → Zig)
    .{
        .name = "webgpu",
        .version = "0.1.0",
        .description = "WebGPU bindings for GPU computing and graphics",
        .category = .runtime,
    },
    // WASM runtime
    .{
        .name = "wasm",
        .version = "0.1.0",
        .description = "WebAssembly runtime integration",
        .category = .runtime,
    },
    // SQLite bindings
    .{
        .name = "sqlite",
        .version = "0.1.0",
        .description = "SQLite database bindings",
        .category = .native,
    },
    // Crypto extensions
    .{
        .name = "crypto",
        .version = "0.1.0",
        .description = "Extended cryptographic operations",
        .category = .native,
    },
    // HTTP/2 client
    .{
        .name = "http2",
        .version = "0.1.0",
        .description = "HTTP/2 protocol support",
        .category = .native,
    },
    // Image processing
    .{
        .name = "image",
        .version = "0.1.0",
        .description = "Image encoding/decoding (PNG, JPEG, WebP)",
        .category = .native,
    },
};

// ============ LOOKUP FUNCTIONS ============

/// Get built-in capsule by name
pub fn getBuiltin(name: []const u8) ?*const BuiltinCapsule {
    for (&builtins) |*cap| {
        if (std.mem.eql(u8, cap.name, name)) {
            return cap;
        }
    }
    return null;
}

/// Check if capsule is built-in
pub fn isBuiltin(name: []const u8) bool {
    return getBuiltin(name) != null;
}

/// List all built-in capsules
pub fn listBuiltins() []const BuiltinCapsule {
    return &builtins;
}

/// Get capsules by category
pub fn getByCategory(category: Category) []const BuiltinCapsule {
    // Return all and let caller filter
    // In real impl would use comptime filtering
    _ = category;
    return &builtins;
}

// ============ EXTERNAL REGISTRY ============

/// External capsule registry URL
pub const REGISTRY_URL = "https://zid.dev/capsules";

/// External capsule info from registry
pub const ExternalCapsule = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    url: []const u8,
    checksum: []const u8,
    dependencies: []const []const u8,
};

// ============ TESTS ============

test "getBuiltin" {
    const webgpu = getBuiltin("webgpu");
    try std.testing.expect(webgpu != null);
    try std.testing.expectEqualStrings("webgpu", webgpu.?.name);

    const unknown = getBuiltin("unknown");
    try std.testing.expect(unknown == null);
}

test "isBuiltin" {
    try std.testing.expect(isBuiltin("webgpu"));
    try std.testing.expect(isBuiltin("sqlite"));
    try std.testing.expect(!isBuiltin("unknown"));
}

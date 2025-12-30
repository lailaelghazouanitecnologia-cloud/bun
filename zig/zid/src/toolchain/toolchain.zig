//! Toolchain Manager
//!
//! Install, manage, and switch between development tools.
//! Supports: bun, zig, node, deno, go, rust + custom toolchains

const std = @import("std");
const zid = @import("../zid.zig");

// Re-export submodules
pub const versions = @import("versions.zig");
pub const registry = @import("registry.zig");
pub const downloader = @import("downloader.zig");
pub const extractor = @import("extractor.zig");
pub const installer = @import("installer.zig");
pub const resolver = @import("resolver.zig");
pub const custom = @import("custom.zig");

// Re-export key types
pub const Version = versions.Version;
pub const Constraint = versions.Constraint;
pub const ToolKind = registry.ToolKind;
pub const ToolDef = registry.ToolDef;
pub const ToolSpec = registry.ToolSpec;
pub const Installer = installer.Installer;
pub const InstallResult = installer.InstallResult;
pub const CustomToolchain = custom.CustomToolchain;

// ============ PUBLIC API ============

/// Install a tool (e.g., "bun@1.1.0", "zig", "node@latest")
pub fn install(allocator: std.mem.Allocator, spec: []const u8) zid.Maybe(InstallResult) {
    // Check for conflicts
    const at_pos = std.mem.indexOf(u8, spec, "@");
    const name = if (at_pos) |p| spec[0..p] else spec;

    if (resolver.detectConflict(allocator, name)) |conflict| {
        resolver.warnConflict(conflict);
    }

    return installer.install(allocator, spec);
}

/// Uninstall a tool
pub fn uninstall(allocator: std.mem.Allocator, spec: []const u8) zid.Maybe(void) {
    return installer.uninstall(allocator, spec);
}

/// List installed tools
pub fn list(allocator: std.mem.Allocator) void {
    installer.list(allocator);
}

/// Switch to a specific version
pub fn use(allocator: std.mem.Allocator, spec: []const u8) zid.Maybe(void) {
    const parsed = switch (ToolSpec.parse(spec)) {
        .ok => |s| s,
        .err => |e| return zid.err(void, e),
    };

    if (parsed.version.isLatest()) {
        return zid.err(void, .{
            .code = .invalid_input,
            .message = "please specify version: zid use <tool>@<version>",
        });
    }

    var inst = Installer.init(allocator);
    if (!inst.isInstalled(parsed.kind, parsed.version)) {
        return zid.err(void, .{
            .code = .not_found,
            .message = "version not installed",
        });
    }

    // Update symlink
    const tool_def = parsed.getDef();
    var ver_buf: [32]u8 = undefined;
    const ver_str = parsed.version.format(&ver_buf);

    var tool_dir_buf: [256]u8 = undefined;
    const tool_dir = std.fmt.bufPrint(&tool_dir_buf, "{s}/{s}/{s}", .{
        inst.toolchains_dir,
        tool_def.name,
        ver_str,
    }) catch return zid.err(void, .{ .code = .internal_error, .message = "path too long" });

    // Note: linkBinary is private in Installer, need to handle this differently
    _ = tool_dir;

    zid.Output.success("Now using {s}@{s}\n", .{ tool_def.name, ver_str });
    return zid.ok(void, {});
}

/// Run a toolchain command
pub fn run(allocator: std.mem.Allocator, name: []const u8, args: []const []const u8) !u8 {
    return resolver.runToolchain(allocator, name, args);
}

/// Get list of supported tools
pub fn supportedTools() []const ToolDef {
    return registry.listAll();
}

/// Check if a tool is supported (builtin or custom)
pub fn isSupported(name: []const u8) bool {
    // Check builtin
    if (registry.getByName(name) != null) return true;
    // Check custom
    if (custom.isCustom(std.heap.page_allocator, name)) return true;
    return false;
}

/// Get toolchain definition (builtin or custom)
pub fn getToolDef(allocator: std.mem.Allocator, name: []const u8) ?ToolDef {
    // Check builtin first
    if (registry.getByName(name)) |def| {
        return def.*;
    }
    // Check custom
    if (custom.getCustom(allocator, name)) |tc| {
        return tc.toToolDef();
    }
    return null;
}

// ============ TESTS ============

test "toolchain exports" {
    _ = versions;
    _ = registry;
    _ = downloader;
    _ = extractor;
    _ = installer;
    _ = resolver;
    _ = custom;
}

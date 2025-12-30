const std = @import("std");
const installer = @import("installer.zig");
const registry = @import("registry.zig");

/// Toolchain Manager
/// Install, manage, and switch between development tools.
/// Starts empty - user installs what they need.
///
/// Supported tools:
///   - zig     (ziglang.org)
///   - rust    (rustup)
///   - bun     (bun.sh)
///   - node    (nodejs.org)
///   - go      (go.dev)
///   - python  (python.org)
///   - deno    (deno.land)

pub const Tool = struct {
    name: []const u8,
    version: []const u8,
    path: []const u8,
    active: bool = false,
};

/// Install a tool
/// Examples:
///   install zig@0.13.0
///   install rust (latest)
///   install bun@1.0.0
pub fn install(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zid install <tool>[@version]\n", .{});
        std.debug.print("\nAvailable tools:\n", .{});
        for (registry.available_tools) |tool| {
            std.debug.print("  {s}\n", .{tool});
        }
        return;
    }

    const spec = parseToolSpec(args[0]);
    std.debug.print("Installing {s}", .{spec.name});
    if (spec.version) |v| {
        std.debug.print("@{s}", .{v});
    } else {
        std.debug.print(" (latest)", .{});
    }
    std.debug.print("...\n", .{});

    try installer.install(alloc, spec.name, spec.version);
}

/// Uninstall a tool
pub fn uninstall(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zid uninstall <tool>[@version]\n", .{});
        return;
    }

    const spec = parseToolSpec(args[0]);
    try installer.uninstall(alloc, spec.name, spec.version);
}

/// List installed tools
pub fn list(alloc: std.mem.Allocator) !void {
    const tools = try registry.listInstalled(alloc);

    if (tools.len == 0) {
        std.debug.print("No tools installed.\n", .{});
        std.debug.print("Use 'zid install <tool>' to install tools.\n", .{});
        return;
    }

    std.debug.print("Installed tools:\n\n", .{});
    for (tools) |tool| {
        const marker: []const u8 = if (tool.active) " *" else "  ";
        std.debug.print("{s} {s}@{s}\n", .{ marker, tool.name, tool.version });
    }
    std.debug.print("\n* = active version\n", .{});
}

/// Switch active version of a tool
pub fn use(alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: zid use <tool>@<version>\n", .{});
        return;
    }

    const spec = parseToolSpec(args[0]);
    if (spec.version == null) {
        std.debug.print("Please specify a version: zid use {s}@<version>\n", .{spec.name});
        return;
    }

    try registry.setActive(alloc, spec.name, spec.version.?);
}

/// Get path to active tool binary
pub fn getPath(alloc: std.mem.Allocator, tool_name: []const u8) !?[]const u8 {
    return registry.getActivePath(alloc, tool_name);
}

const ToolSpec = struct {
    name: []const u8,
    version: ?[]const u8,
};

fn parseToolSpec(spec: []const u8) ToolSpec {
    if (std.mem.indexOf(u8, spec, "@")) |at| {
        return .{
            .name = spec[0..at],
            .version = spec[at + 1 ..],
        };
    }
    return .{ .name = spec, .version = null };
}

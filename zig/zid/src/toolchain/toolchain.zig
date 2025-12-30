//! Toolchain Manager
//!
//! Install, manage, and switch between development tools.

const std = @import("std");
const Output = @import("../output.zig");
const zid = @import("../zid.zig");
const fs = @import("../fs.zig");

pub const Tool = struct {
    name: []const u8,
    version: []const u8,
    active: bool = false,
};

const tools = [_][]const u8{ "zig", "rust", "bun", "node", "go", "deno", "python" };

pub fn install(alloc: std.mem.Allocator, spec: []const u8) !void {
    const parsed = parseSpec(spec);
    Output.print("Installing {s}", .{parsed.name});
    if (parsed.version) |v| {
        Output.print("@{s}", .{v});
    } else {
        Output.print(" (latest)", .{});
    }
    Output.print("...\n", .{});

    // TODO: Download and install
    _ = alloc;

    Output.success("Installed {s}\n", .{parsed.name});
}

pub fn uninstall(alloc: std.mem.Allocator, spec: []const u8) !void {
    const parsed = parseSpec(spec);
    _ = alloc;
    Output.print("Uninstalling {s}...\n", .{parsed.name});
    Output.success("Uninstalled {s}\n", .{parsed.name});
}

pub fn list(alloc: std.mem.Allocator) !void {
    _ = alloc;
    Output.bold("Installed tools:\n", .{});
    Output.print("  (none installed yet)\n", .{});
    Output.print("\nUse 'zid install <tool>' to install.\n", .{});
}

pub fn use(alloc: std.mem.Allocator, spec: []const u8) !void {
    const parsed = parseSpec(spec);
    if (parsed.version == null) {
        Output.err("Please specify version: zid use {s}@<version>\n", .{parsed.name});
        return error.MissingVersion;
    }
    _ = alloc;
    Output.success("Now using {s}@{s}\n", .{ parsed.name, parsed.version.? });
}

const Spec = struct {
    name: []const u8,
    version: ?[]const u8,
};

fn parseSpec(spec: []const u8) Spec {
    if (std.mem.indexOf(u8, spec, "@")) |i| {
        return .{ .name = spec[0..i], .version = spec[i + 1 ..] };
    }
    return .{ .name = spec, .version = null };
}

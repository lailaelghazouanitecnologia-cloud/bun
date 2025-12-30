//! Patch Command - Manage patches
//!
//! Commands:
//!   zid patch check     - Check for available patches
//!   zid patch apply     - Apply all pending patches
//!   zid patch list      - List applied patches
//!   zid patch rollback  - Rollback a patch

const std = @import("std");
const zid = @import("../zid.zig");
const patches = @import("../patches/patches.zig");
const Output = zid.Output;

/// Run patch command
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        runCheck(allocator);
        return;
    }

    const sub = args[0];
    const sub_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    if (eql(sub, "check")) {
        runCheck(allocator);
    } else if (eql(sub, "apply")) {
        runApply(allocator);
    } else if (eql(sub, "list")) {
        runList(allocator);
    } else if (eql(sub, "rollback")) {
        runRollback(allocator, sub_args);
    } else if (eql(sub, "help") or eql(sub, "-h")) {
        showHelp();
    } else {
        Output.err("Unknown subcommand: {s}\n", .{sub});
        showHelp();
    }
}

/// Check for available patches
fn runCheck(allocator: std.mem.Allocator) void {
    Output.print("Checking for patches...\n", .{});

    switch (patches.check(allocator)) {
        .ok => |pending| {
            if (pending.len == 0) {
                Output.success("No pending patches.\n", .{});
                return;
            }

            Output.bold("Available patches:\n\n", .{});
            for (pending) |patch| {
                const sev = switch (patch.severity) {
                    .critical => "\x1b[31mCRITICAL\x1b[0m",
                    .high => "\x1b[33mHIGH\x1b[0m",
                    .normal => "NORMAL",
                    .low => "LOW",
                };

                Output.print("  {s} [{s}] {s}\n", .{ patch.id, sev, patch.description });
            }

            Output.print("\nRun 'zid patch apply' to apply all patches.\n", .{});
        },
        .err => |e| {
            Output.err("Failed to check patches: {s}\n", .{e.message});
        },
    }
}

/// Apply all pending patches
fn runApply(allocator: std.mem.Allocator) void {
    Output.print("Applying patches...\n", .{});

    switch (patches.applyAll(allocator)) {
        .ok => |count| {
            if (count == 0) {
                Output.print("No patches to apply.\n", .{});
            } else {
                Output.success("Applied {d} patch(es).\n", .{count});
            }
        },
        .err => |e| {
            Output.err("Failed to apply patches: {s}\n", .{e.message});
        },
    }
}

/// List applied patches
fn runList(allocator: std.mem.Allocator) void {
    patches.listApplied(allocator);
}

/// Rollback a patch
fn runRollback(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        Output.err("Missing patch ID\n", .{});
        Output.print("Usage: zid patch rollback <patch-id>\n", .{});
        return;
    }

    const patch_id = args[0];

    var mgr = patches.Manager.init(allocator);
    defer mgr.deinit();

    switch (mgr.rollback(patch_id)) {
        .ok => {
            Output.success("Rolled back patch: {s}\n", .{patch_id});
        },
        .err => |e| {
            Output.err("Failed to rollback: {s}\n", .{e.message});
        },
    }
}

fn showHelp() void {
    Output.bold("zid patch", .{});
    Output.print(" - Manage urgent fixes\n\n", .{});
    Output.print("Commands:\n", .{});
    Output.print("  check             Check for available patches\n", .{});
    Output.print("  apply             Apply all pending patches\n", .{});
    Output.print("  list              List applied patches\n", .{});
    Output.print("  rollback <id>     Rollback a specific patch\n", .{});
    Output.print("\nExamples:\n", .{});
    Output.print("  zid patch check\n", .{});
    Output.print("  zid patch apply\n", .{});
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

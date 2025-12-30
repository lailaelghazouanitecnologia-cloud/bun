//! CLI Tests

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");
const cli = zid.cli;

test "parse command" {
    try testing.expectEqual(cli.Command.install, cli.Command.parse("install").?);
    try testing.expectEqual(cli.Command.install, cli.Command.parse("i").?);
    try testing.expectEqual(cli.Command.build, cli.Command.parse("b").?);
    try testing.expect(cli.Command.parse("nonexistent") == null);
}

test "parse command aliases" {
    try testing.expectEqual(cli.Command.uninstall, cli.Command.parse("rm").?);
    try testing.expectEqual(cli.Command.list, cli.Command.parse("ls").?);
    try testing.expectEqual(cli.Command.init, cli.Command.parse("create").?);
    try testing.expectEqual(cli.Command.watch, cli.Command.parse("w").?);
}

test "parse new commands" {
    // Capsule commands
    try testing.expectEqual(cli.Command.capsule, cli.Command.parse("capsule").?);
    try testing.expectEqual(cli.Command.capsule, cli.Command.parse("cap").?);

    // Update commands
    try testing.expectEqual(cli.Command.update, cli.Command.parse("update").?);
    try testing.expectEqual(cli.Command.update, cli.Command.parse("upgrade").?);

    // Note: patch is not a CLI command - it runs automatically at startup
}

test "all commands exist" {

    // Verify all enum variants can be parsed
    // Note: patch removed - it's auto-run at startup for security
    const commands = [_][]const u8{
        "install",
        "uninstall",
        "list",
        "use",
        "add",
        "remove",
        "capsule",
        "init",
        "build",
        "watch",
        "help",
        "update",
    };

    for (commands) |cmd| {
        try testing.expect(cli.Command.parse(cmd) != null);
    }
}

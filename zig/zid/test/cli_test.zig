//! CLI Tests

const std = @import("std");
const testing = std.testing;

test "parse command" {
    const cli = @import("../src/cli.zig");

    try testing.expectEqual(cli.Command.install, cli.Command.parse("install").?);
    try testing.expectEqual(cli.Command.install, cli.Command.parse("i").?);
    try testing.expectEqual(cli.Command.build, cli.Command.parse("b").?);
    try testing.expect(cli.Command.parse("nonexistent") == null);
}

test "parse command aliases" {
    const cli = @import("../src/cli.zig");

    try testing.expectEqual(cli.Command.uninstall, cli.Command.parse("rm").?);
    try testing.expectEqual(cli.Command.list, cli.Command.parse("ls").?);
    try testing.expectEqual(cli.Command.init, cli.Command.parse("create").?);
    try testing.expectEqual(cli.Command.watch, cli.Command.parse("w").?);
}

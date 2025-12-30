//! String utilities tests

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");
const strings = zid.strings;

test "string operations" {
    try testing.expect(strings.startsWith("hello world", "hello"));
    try testing.expect(strings.endsWith("hello world", "world"));
    try testing.expect(strings.contains("hello world", "lo wo"));
}

test "trim" {
    try testing.expectEqualStrings("hello", strings.trim("  hello  "));
    try testing.expectEqualStrings("hello", strings.trim("\n\thello\n\t"));
}

test "StringBuilder" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var sb = strings.Builder.init(arena.allocator());
    try sb.append("Hello");
    try sb.append(" ");
    try sb.append("World");

    try testing.expectEqualStrings("Hello World", sb.slice());
}

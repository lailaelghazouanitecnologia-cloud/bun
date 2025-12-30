//! Update System Tests

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");

const update = zid.cli.UpdateCommand;

// ============ VERSION TESTS ============

test "update: VERSION is defined" {
    try testing.expect(update.VERSION.len > 0);
    try testing.expect(std.mem.indexOf(u8, update.VERSION, ".") != null);
}

test "update: ReleaseInfo struct" {
    const info = update.ReleaseInfo{
        .version = "0.2.0",
        .url = "https://example.com/download",
        .checksum = "abc123def456",
        .release_notes = "Bug fixes",
        .published_at = "2024-01-01",
    };

    try testing.expectEqualStrings("0.2.0", info.version);
    try testing.expectEqualStrings("https://example.com/download", info.url);
    try testing.expectEqualStrings("abc123def456", info.checksum);
}

test "update: ReleaseInfo default values" {
    const info = update.ReleaseInfo{
        .version = "1.0.0",
        .url = "https://example.com",
        .checksum = "",
    };

    try testing.expectEqualStrings("", info.release_notes);
    try testing.expectEqualStrings("", info.published_at);
}

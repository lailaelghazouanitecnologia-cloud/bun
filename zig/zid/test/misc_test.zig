//! Misc Module Tests (Core Patterns)

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");

const misc = zid.misc;

// ============ MAYBE TESTS ============

test "maybe: ok returns value" {
    const result = misc.ok(i32, 42);
    switch (result) {
        .ok => |v| try testing.expect(v == 42),
        .err => try testing.expect(false),
    }
}

test "maybe: err returns error" {
    const result = misc.err(i32, .{
        .code = .not_found,
        .message = "file not found",
    });

    switch (result) {
        .ok => try testing.expect(false),
        .err => |e| {
            try testing.expect(e.code == .not_found);
            try testing.expectEqualStrings("file not found", e.message);
        },
    }
}

test "maybe: Error codes exist" {
    const codes = [_]misc.Error.Code{
        .ok,
        .not_found,
        .permission_denied,
        .invalid_input,
        .network_error,
        .parse_error,
        .internal_error,
    };
    try testing.expect(codes.len >= 7);
}

test "maybe: Error with path" {
    const e = misc.Error{
        .code = .not_found,
        .message = "not found",
        .path = "/some/path",
    };

    try testing.expectEqualStrings("/some/path", e.path);
}

test "maybe: Error Step enum" {
    const steps = [_]misc.Error.Step{
        .read_file,
        .write_file,
        .parse,
        .network,
        .unknown,
    };
    try testing.expect(steps.len >= 5);
}

// ============ COLLECTIONS TESTS ============

test "SmallList: init" {
    const List = misc.SmallList(u32);
    const list = List.init();
    try testing.expect(list.len == 0);
}

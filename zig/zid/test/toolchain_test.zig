//! Toolchain System Tests

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");

const toolchain = zid.toolchain;
const versions = toolchain.versions;
const registry = toolchain.registry;

// ============ VERSION TESTS ============

test "version: parse valid semver" {
    switch (versions.Version.parse("1.2.3")) {
        .ok => |v| {
            try testing.expect(v.major == 1);
            try testing.expect(v.minor == 2);
            try testing.expect(v.patch == 3);
        },
        .err => try testing.expect(false),
    }
}

test "version: parse with v prefix" {
    switch (versions.Version.parse("v0.13.0")) {
        .ok => |v| {
            try testing.expect(v.major == 0);
            try testing.expect(v.minor == 13);
            try testing.expect(v.patch == 0);
        },
        .err => try testing.expect(false),
    }
}

test "version: parse latest" {
    switch (versions.Version.parse("latest")) {
        .ok => |v| {
            try testing.expect(v.isLatest());
        },
        .err => try testing.expect(false),
    }
}

test "version: compare equal" {
    const v1 = versions.Version{ .major = 1, .minor = 0, .patch = 0 };
    const v2 = versions.Version{ .major = 1, .minor = 0, .patch = 0 };
    try testing.expect(v1.compare(v2) == .eq);
}

test "version: compare major difference" {
    const v1 = versions.Version{ .major = 2, .minor = 0, .patch = 0 };
    const v2 = versions.Version{ .major = 1, .minor = 0, .patch = 0 };
    try testing.expect(v1.compare(v2) == .gt);
    try testing.expect(v2.compare(v1) == .lt);
}

test "version: compare minor difference" {
    const v1 = versions.Version{ .major = 1, .minor = 5, .patch = 0 };
    const v2 = versions.Version{ .major = 1, .minor = 3, .patch = 0 };
    try testing.expect(v1.compare(v2) == .gt);
}

test "version: compare patch difference" {
    const v1 = versions.Version{ .major = 1, .minor = 0, .patch = 5 };
    const v2 = versions.Version{ .major = 1, .minor = 0, .patch = 3 };
    try testing.expect(v1.compare(v2) == .gt);
}

test "version: format" {
    const v = versions.Version{ .major = 1, .minor = 2, .patch = 3 };
    var buf: [32]u8 = undefined;
    const formatted = v.format(&buf);
    try testing.expectEqualStrings("1.2.3", formatted);
}

test "version: latest constant" {
    const v = versions.Version.latest;
    try testing.expect(v.isLatest());
}

// ============ CONSTRAINT TESTS ============

test "constraint: parse exact" {
    switch (versions.Constraint.parse("1.2.3")) {
        .ok => |c| {
            try testing.expect(c.op == .eq);
            try testing.expect(c.version.major == 1);
        },
        .err => try testing.expect(false),
    }
}

test "constraint: parse caret" {
    switch (versions.Constraint.parse("^1.2.0")) {
        .ok => |c| {
            try testing.expect(c.op == .caret);
        },
        .err => try testing.expect(false),
    }
}

test "constraint: parse tilde" {
    switch (versions.Constraint.parse("~1.2.0")) {
        .ok => |c| {
            try testing.expect(c.op == .tilde);
        },
        .err => try testing.expect(false),
    }
}

test "constraint: parse gte" {
    switch (versions.Constraint.parse(">=2.0.0")) {
        .ok => |c| {
            try testing.expect(c.op == .gte);
        },
        .err => try testing.expect(false),
    }
}

test "constraint: satisfies exact" {
    const c = versions.Constraint{
        .op = .eq,
        .version = .{ .major = 1, .minor = 2, .patch = 3 },
    };

    try testing.expect(c.satisfies(.{ .major = 1, .minor = 2, .patch = 3 }));
    try testing.expect(!c.satisfies(.{ .major = 1, .minor = 2, .patch = 4 }));
}

// ============ REGISTRY TESTS ============

test "registry: ToolKind enum" {
    const kinds = [_]registry.ToolKind{
        .bun,
        .zig,
        .node,
        .deno,
        .go,
        .rust,
    };
    try testing.expect(kinds.len == 6);
}

test "registry: get returns valid tool" {
    const bun = registry.get(.bun);
    try testing.expectEqualStrings("bun", bun.name);
    try testing.expect(bun.archive == .zip);
}

test "registry: get zig tool" {
    const zig_tool = registry.get(.zig);
    try testing.expectEqualStrings("zig", zig_tool.name);
    try testing.expect(zig_tool.archive == .tar_xz);
}

test "registry: getByName" {
    const bun = registry.getByName("bun");
    try testing.expect(bun != null);
    try testing.expectEqualStrings("bun", bun.?.name);

    const unknown = registry.getByName("unknown-tool");
    try testing.expect(unknown == null);
}

test "registry: listAll returns all tools" {
    const all = registry.listAll();
    try testing.expect(all.len >= 6);
}

// ============ TOOLCHAIN API TESTS ============

test "toolchain: supportedTools returns list" {
    const tools = toolchain.supportedTools();
    try testing.expect(tools.len >= 6);
}

test "toolchain: isSupported" {
    try testing.expect(toolchain.isSupported("bun"));
    try testing.expect(toolchain.isSupported("zig"));
    try testing.expect(toolchain.isSupported("node"));
    try testing.expect(!toolchain.isSupported("unknown"));
}

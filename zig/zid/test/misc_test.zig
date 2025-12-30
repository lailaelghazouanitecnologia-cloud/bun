//! Misc Module Tests (Core Patterns)

const std = @import("std");
const testing = std.testing;

const misc = @import("../src/misc/mod.zig");
const maybe_mod = @import("../src/misc/maybe.zig");
const progress_mod = @import("../src/misc/progress.zig");
const options_mod = @import("../src/misc/options.zig");
const cache_mod = @import("../src/misc/cache.zig");

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

test "maybe: Operation enum" {
    const ops = [_]misc.Error.Op{
        .read_file,
        .write_file,
        .parse,
        .network,
        .unknown,
    };
    try testing.expect(ops.len >= 5);
}

// ============ OPTIONS TESTS ============

test "options: Target enum" {
    const targets = [_]options_mod.Target{
        .native,
        .linux_x64,
        .linux_aarch64,
        .macos_x64,
        .macos_aarch64,
        .windows_x64,
        .wasm32,
    };
    try testing.expect(targets.len >= 7);
}

test "options: OutputFormat enum" {
    const formats = [_]options_mod.OutputFormat{
        .zig,
        .c,
        .llvm,
        .wasm,
        .js,
    };
    try testing.expect(formats.len >= 5);
}

test "options: OptLevel enum" {
    const levels = [_]options_mod.OptLevel{
        .none,
        .debug,
        .release_safe,
        .release_fast,
        .release_small,
    };
    try testing.expect(levels.len == 5);
}

test "options: Toolchain enum" {
    const toolchains = [_]options_mod.Toolchain{
        .zig,
        .llvm,
        .gcc,
        .msvc,
    };
    try testing.expect(toolchains.len == 4);
}

test "options: BuildOptions struct" {
    const opts = options_mod.BuildOptions{
        .target = .native,
        .opt_level = .debug,
        .output_format = .zig,
        .toolchain = .zig,
    };

    try testing.expect(opts.target == .native);
    try testing.expect(opts.opt_level == .debug);
}

test "options: Features packed struct" {
    var features = options_mod.Features{};
    try testing.expect(!features.jsx);
    try testing.expect(!features.typescript);

    features.jsx = true;
    features.typescript = true;

    try testing.expect(features.jsx);
    try testing.expect(features.typescript);
}

test "options: GlobalConfig struct" {
    const config = options_mod.GlobalConfig{};
    try testing.expect(!config.verbose);
    try testing.expect(!config.quiet);
    try testing.expect(!config.no_color);
}

// ============ PROGRESS TESTS ============

test "progress: Bar struct" {
    var bar = progress_mod.Bar{
        .total = 100,
        .current = 0,
    };

    try testing.expect(bar.total == 100);
    try testing.expect(bar.current == 0);

    bar.current = 50;
    try testing.expect(bar.current == 50);
}

test "progress: Spinner frames" {
    const spinner = progress_mod.Spinner{};
    try testing.expect(spinner.frames.len > 0);
}

test "progress: TaskTracker" {
    var tracker = progress_mod.TaskTracker{};

    try testing.expect(tracker.active_count == 0);
    try testing.expect(tracker.completed_count == 0);
}

// ============ CACHE TESTS ============

test "cache: Set struct" {
    var set = cache_mod.Set{
        .allocator = testing.allocator,
    };
    _ = set;
    // Just verify it compiles
}

test "cache: LruCache basic" {
    const Cache = cache_mod.LruCache(u32, []const u8, 4);
    var cache = Cache{};

    cache.put(1, "one");
    cache.put(2, "two");

    try testing.expectEqualStrings("one", cache.get(1).?);
    try testing.expectEqualStrings("two", cache.get(2).?);
    try testing.expect(cache.get(3) == null);
}

test "cache: LruCache eviction" {
    const Cache = cache_mod.LruCache(u32, u32, 2);
    var cache = Cache{};

    cache.put(1, 10);
    cache.put(2, 20);
    cache.put(3, 30); // Should evict 1

    try testing.expect(cache.get(1) == null);
    try testing.expect(cache.get(2).? == 20);
    try testing.expect(cache.get(3).? == 30);
}

//! Tool Search - Search tools by text, tags, and categories
//!
//! Provides fuzzy search and filtering for tool discovery.
//!
//! ## Usage
//! ```zig
//! const search = @import("toolchain/search.zig");
//!
//! // Search by text
//! const results = search.query("javascript runtime");
//!
//! // Filter by category
//! const langs = search.byCategory(.language);
//!
//! // Filter by tag
//! const web = search.byTag("web");
//! ```

const std = @import("std");
const registry = @import("registry.zig");
const ToolKind = registry.ToolKind;
const ToolDef = registry.ToolDef;

// ============ ENHANCED METADATA ============

/// Tool category for filtering
pub const Category = enum {
    runtime, // JavaScript/language runtimes
    language, // Programming language toolchains
    build, // Build tools
    package_manager, // Package managers
    devtools, // Developer tools

    pub fn string(self: Category) []const u8 {
        return switch (self) {
            .runtime => "runtime",
            .language => "language",
            .build => "build",
            .package_manager => "package_manager",
            .devtools => "devtools",
        };
    }

    pub fn description(self: Category) []const u8 {
        return switch (self) {
            .runtime => "Language runtimes",
            .language => "Programming language toolchains",
            .build => "Build systems and bundlers",
            .package_manager => "Package managers",
            .devtools => "Developer tools",
        };
    }
};

/// Enhanced tool metadata for search
pub const ToolMeta = struct {
    kind: ToolKind,
    name: []const u8,
    description: []const u8,
    long_description: []const u8 = "",
    homepage: []const u8,
    category: Category,
    tags: []const []const u8 = &.{},
    aliases: []const []const u8 = &.{},
    keywords: []const []const u8 = &.{},
    related: []const ToolKind = &.{},
};

/// Enhanced tool registry with metadata
pub const tool_metadata = [_]ToolMeta{
    // Bun
    .{
        .kind = .bun,
        .name = "bun",
        .description = "JavaScript runtime & toolkit",
        .long_description = "Bun is an all-in-one JavaScript runtime and toolkit designed for speed. It includes a bundler, test runner, and Node.js-compatible package manager.",
        .homepage = "https://bun.sh",
        .category = .runtime,
        .tags = &.{ "javascript", "typescript", "runtime", "bundler", "fast" },
        .aliases = &.{},
        .keywords = &.{ "js", "ts", "node", "npm", "web", "server" },
        .related = &.{ .node, .deno },
    },
    // Zig
    .{
        .kind = .zig,
        .name = "zig",
        .description = "Systems programming language",
        .long_description = "Zig is a general-purpose programming language and toolchain for building optimal, and maintainable software.",
        .homepage = "https://ziglang.org",
        .category = .language,
        .tags = &.{ "systems", "low-level", "safe", "fast" },
        .aliases = &.{},
        .keywords = &.{ "c", "cpp", "embedded", "wasm", "compile" },
        .related = &.{ .rust, .go },
    },
    // Node.js
    .{
        .kind = .node,
        .name = "node",
        .description = "JavaScript runtime",
        .long_description = "Node.js is a JavaScript runtime built on Chrome's V8 engine. It enables running JavaScript on the server-side.",
        .homepage = "https://nodejs.org",
        .category = .runtime,
        .tags = &.{ "javascript", "runtime", "server", "v8" },
        .aliases = &.{"nodejs"},
        .keywords = &.{ "js", "npm", "web", "backend", "express" },
        .related = &.{ .bun, .deno },
    },
    // Deno
    .{
        .kind = .deno,
        .name = "deno",
        .description = "Secure JavaScript/TypeScript runtime",
        .long_description = "Deno is a secure runtime for JavaScript and TypeScript. It uses V8 and is built in Rust.",
        .homepage = "https://deno.land",
        .category = .runtime,
        .tags = &.{ "javascript", "typescript", "runtime", "secure" },
        .aliases = &.{},
        .keywords = &.{ "js", "ts", "web", "server", "rust" },
        .related = &.{ .bun, .node },
    },
    // Go
    .{
        .kind = .go,
        .name = "go",
        .description = "Go programming language",
        .long_description = "Go is an open source programming language that makes it easy to build simple, reliable, and efficient software.",
        .homepage = "https://go.dev",
        .category = .language,
        .tags = &.{ "language", "compiled", "concurrent", "google" },
        .aliases = &.{"golang"},
        .keywords = &.{ "goroutine", "channel", "backend", "cli", "cloud" },
        .related = &.{ .rust, .zig },
    },
    // Rust
    .{
        .kind = .rust,
        .name = "rust",
        .description = "Rust programming language",
        .long_description = "Rust is a systems programming language focused on safety, speed, and concurrency.",
        .homepage = "https://rust-lang.org",
        .category = .language,
        .tags = &.{ "systems", "safe", "fast", "memory" },
        .aliases = &.{"rustlang"},
        .keywords = &.{ "cargo", "crate", "ownership", "wasm", "cli" },
        .related = &.{ .zig, .go },
    },
};

// ============ SEARCH FUNCTIONS ============

/// Search result with relevance score
pub const SearchResult = struct {
    meta: *const ToolMeta,
    score: u32,
    match_reason: MatchReason,
};

pub const MatchReason = enum {
    name_exact,
    name_partial,
    alias,
    description,
    tag,
    keyword,
    category,
};

/// Search tools by query string
pub fn query(q: []const u8, results: []SearchResult) usize {
    if (q.len == 0) return 0;

    var count: usize = 0;
    const query_lower = lowerBuf(q);

    for (&tool_metadata) |*meta| {
        if (count >= results.len) break;

        const maybe_score = scoreTool(meta, query_lower);
        if (maybe_score) |score_info| {
            results[count] = .{
                .meta = meta,
                .score = score_info.score,
                .match_reason = score_info.reason,
            };
            count += 1;
        }
    }

    // Sort by score (descending)
    sortResults(results[0..count]);

    return count;
}

const ScoreInfo = struct {
    score: u32,
    reason: MatchReason,
};

fn scoreTool(meta: *const ToolMeta, query_lower: []const u8) ?ScoreInfo {
    // Check exact name match (highest priority)
    if (std.mem.eql(u8, meta.name, query_lower)) {
        return .{ .score = 1000, .reason = .name_exact };
    }

    // Check partial name match
    if (std.mem.indexOf(u8, meta.name, query_lower) != null) {
        return .{ .score = 800, .reason = .name_partial };
    }

    // Check aliases
    for (meta.aliases) |alias| {
        if (std.mem.eql(u8, alias, query_lower) or std.mem.indexOf(u8, alias, query_lower) != null) {
            return .{ .score = 700, .reason = .alias };
        }
    }

    // Check tags
    for (meta.tags) |tag| {
        if (std.mem.indexOf(u8, tag, query_lower) != null) {
            return .{ .score = 500, .reason = .tag };
        }
    }

    // Check keywords
    for (meta.keywords) |keyword| {
        if (std.mem.indexOf(u8, keyword, query_lower) != null) {
            return .{ .score = 400, .reason = .keyword };
        }
    }

    // Check description
    const desc_lower = lowerBuf(meta.description);
    if (std.mem.indexOf(u8, desc_lower, query_lower) != null) {
        return .{ .score = 300, .reason = .description };
    }

    return null;
}

fn sortResults(results: []SearchResult) void {
    std.mem.sort(SearchResult, results, {}, struct {
        fn lessThan(_: void, a: SearchResult, b: SearchResult) bool {
            return a.score > b.score;
        }
    }.lessThan);
}

var lower_buf: [256]u8 = undefined;
fn lowerBuf(s: []const u8) []const u8 {
    const len = @min(s.len, lower_buf.len);
    for (s[0..len], 0..) |c, i| {
        lower_buf[i] = std.ascii.toLower(c);
    }
    return lower_buf[0..len];
}

/// Filter by category
pub fn byCategory(cat: Category, results: []*const ToolMeta) usize {
    var count: usize = 0;
    for (&tool_metadata) |*meta| {
        if (count >= results.len) break;
        if (meta.category == cat) {
            results[count] = meta;
            count += 1;
        }
    }
    return count;
}

/// Filter by tag
pub fn byTag(tag: []const u8, results: []*const ToolMeta) usize {
    var count: usize = 0;
    for (&tool_metadata) |*meta| {
        if (count >= results.len) break;
        for (meta.tags) |t| {
            if (std.mem.eql(u8, t, tag)) {
                results[count] = meta;
                count += 1;
                break;
            }
        }
    }
    return count;
}

/// Get metadata by kind
pub fn getMeta(kind: ToolKind) ?*const ToolMeta {
    for (&tool_metadata) |*meta| {
        if (meta.kind == kind) return meta;
    }
    return null;
}

/// Get related tools
pub fn getRelated(kind: ToolKind, results: []*const ToolMeta) usize {
    const meta = getMeta(kind) orelse return 0;
    var count: usize = 0;
    for (meta.related) |rel| {
        if (count >= results.len) break;
        if (getMeta(rel)) |rel_meta| {
            results[count] = rel_meta;
            count += 1;
        }
    }
    return count;
}

/// List all available tools
pub fn listAll() []const ToolMeta {
    return &tool_metadata;
}

/// List all categories
pub fn listCategories() []const Category {
    return &.{ .runtime, .language, .build, .package_manager, .devtools };
}

/// List all unique tags
pub fn listTags(buf: [][]const u8) usize {
    var count: usize = 0;
    var seen = std.BoundedArray([64]u8, 64){};

    for (&tool_metadata) |*meta| {
        for (meta.tags) |tag| {
            var found = false;
            for (seen.slice()) |s| {
                if (std.mem.eql(u8, &s, tag)) {
                    found = true;
                    break;
                }
            }
            if (!found and count < buf.len) {
                var tag_copy: [64]u8 = undefined;
                @memcpy(tag_copy[0..tag.len], tag);
                seen.appendAssumeCapacity(tag_copy);
                buf[count] = tag;
                count += 1;
            }
        }
    }

    return count;
}

// ============ TESTS ============

test "query by name" {
    var results: [10]SearchResult = undefined;
    const count = query("bun", &results);

    try std.testing.expect(count > 0);
    try std.testing.expectEqual(ToolKind.bun, results[0].meta.kind);
    try std.testing.expectEqual(MatchReason.name_exact, results[0].match_reason);
}

test "query by tag" {
    var results: [10]SearchResult = undefined;
    const count = query("javascript", &results);

    try std.testing.expect(count >= 3); // bun, node, deno
}

test "byCategory" {
    var results: [10]*const ToolMeta = undefined;
    const count = byCategory(.runtime, &results);

    try std.testing.expect(count >= 3); // bun, node, deno
}

test "byTag" {
    var results: [10]*const ToolMeta = undefined;
    const count = byTag("systems", &results);

    try std.testing.expect(count >= 2); // zig, rust
}

test "getRelated" {
    var results: [10]*const ToolMeta = undefined;
    const count = getRelated(.bun, &results);

    try std.testing.expect(count == 2); // node, deno
}

//! CLI Search Command
//!
//! Search for tools by text, category, or tag.
//!
//! Usage:
//!   zid search javascript        # Search by text
//!   zid search -c runtime        # Filter by category
//!   zid search -t fast           # Filter by tag
//!   zid search --list-tags       # List all tags
//!   zid search --list-categories # List all categories

const std = @import("std");
const Output = @import("../output.zig");
const search = @import("../toolchain/search.zig");
const Category = search.Category;

pub fn run(_: std.mem.Allocator, args: []const []const u8) void {
    var query: ?[]const u8 = null;
    var category: ?Category = null;
    var tag: ?[]const u8 = null;
    var list_tags = false;
    var list_categories = false;
    var show_related = false;
    var json_output = false;

    // Parse args
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (eql(arg, "--category") or eql(arg, "-c")) {
            if (i + 1 < args.len) {
                i += 1;
                category = parseCategory(args[i]);
                if (category == null) {
                    Output.err("Unknown category: {s}\n", .{args[i]});
                    Output.print("Run 'zid search --list-categories' to see available categories.\n", .{});
                    return;
                }
            }
        } else if (eql(arg, "--tag") or eql(arg, "-t")) {
            if (i + 1 < args.len) {
                i += 1;
                tag = args[i];
            }
        } else if (eql(arg, "--list-tags")) {
            list_tags = true;
        } else if (eql(arg, "--list-categories")) {
            list_categories = true;
        } else if (eql(arg, "--related") or eql(arg, "-r")) {
            show_related = true;
        } else if (eql(arg, "--json")) {
            json_output = true;
        } else if (eql(arg, "--help") or eql(arg, "-h")) {
            printHelp();
            return;
        } else if (arg.len > 0 and arg[0] != '-') {
            query = arg;
        }
    }

    // Handle list commands
    if (list_categories) {
        printCategories();
        return;
    }
    if (list_tags) {
        printTags();
        return;
    }

    // Search
    if (category) |cat| {
        searchByCategory(cat, json_output);
    } else if (tag) |t| {
        searchByTag(t, json_output);
    } else if (query) |q| {
        searchByQuery(q, show_related, json_output);
    } else {
        // No query - list all tools
        listAllTools(json_output);
    }
}

fn searchByQuery(q: []const u8, show_related: bool, json_output: bool) void {
    var results: [20]search.SearchResult = undefined;
    const count = search.query(q, &results);

    if (count == 0) {
        Output.print("No tools found matching '{s}'\n", .{q});
        Output.print("\nTry:\n", .{});
        Output.print("  zid search --list-categories\n", .{});
        Output.print("  zid search --list-tags\n", .{});
        return;
    }

    if (json_output) {
        printResultsJson(results[0..count]);
        return;
    }

    Output.bold("Search results for '{s}':\n\n", .{q});

    for (results[0..count]) |result| {
        printToolResult(result.meta, result.match_reason);
    }

    // Show related for top result if requested
    if (show_related and count > 0) {
        var related: [10]*const search.ToolMeta = undefined;
        const rel_count = search.getRelated(results[0].meta.kind, &related);
        if (rel_count > 0) {
            Output.print("\nRelated tools:\n", .{});
            for (related[0..rel_count]) |rel| {
                Output.print("  {s} - {s}\n", .{ rel.name, rel.description });
            }
        }
    }
}

fn searchByCategory(cat: Category, json_output: bool) void {
    var results: [20]*const search.ToolMeta = undefined;
    const count = search.byCategory(cat, &results);

    if (json_output) {
        printMetaListJson(results[0..count]);
        return;
    }

    Output.bold("{s}:\n\n", .{cat.description()});

    for (results[0..count]) |meta| {
        Output.print("  \x1b[32m{s}\x1b[0m - {s}\n", .{ meta.name, meta.description });
        Output.print("    Tags: ", .{});
        for (meta.tags, 0..) |t, i| {
            if (i > 0) Output.print(", ", .{});
            Output.print("{s}", .{t});
        }
        Output.print("\n\n", .{});
    }
}

fn searchByTag(tag_name: []const u8, json_output: bool) void {
    var results: [20]*const search.ToolMeta = undefined;
    const count = search.byTag(tag_name, &results);

    if (count == 0) {
        Output.print("No tools found with tag '{s}'\n", .{tag_name});
        Output.print("Run 'zid search --list-tags' to see available tags.\n", .{});
        return;
    }

    if (json_output) {
        printMetaListJson(results[0..count]);
        return;
    }

    Output.bold("Tools with tag '{s}':\n\n", .{tag_name});

    for (results[0..count]) |meta| {
        Output.print("  \x1b[32m{s}\x1b[0m - {s}\n", .{ meta.name, meta.description });
    }
}

fn listAllTools(json_output: bool) void {
    const all = search.listAll();

    if (json_output) {
        printMetaListJson(ptrSlice(all));
        return;
    }

    Output.bold("Available Tools:\n\n", .{});

    // Group by category
    inline for (search.listCategories()) |cat| {
        var found = false;
        for (all) |*meta| {
            if (meta.category == cat) {
                if (!found) {
                    Output.print("  {s}:\n", .{cat.description()});
                    found = true;
                }
                Output.print("    \x1b[32m{s}\x1b[0m - {s}\n", .{ meta.name, meta.description });
            }
        }
        if (found) Output.print("\n", .{});
    }
}

fn printCategories() void {
    Output.bold("Available Categories:\n\n", .{});
    for (search.listCategories()) |cat| {
        Output.print("  {s:<20} {s}\n", .{ cat.string(), cat.description() });
    }
    Output.print("\nUsage: zid search -c <category>\n", .{});
}

fn printTags() void {
    Output.bold("Available Tags:\n\n", .{});

    // Collect unique tags
    const all = search.listAll();
    var printed: [64][]const u8 = undefined;
    var count: usize = 0;

    for (all) |*meta| {
        for (meta.tags) |tag| {
            var found = false;
            for (printed[0..count]) |p| {
                if (std.mem.eql(u8, p, tag)) {
                    found = true;
                    break;
                }
            }
            if (!found and count < 64) {
                printed[count] = tag;
                count += 1;
            }
        }
    }

    // Print tags in columns
    var col: usize = 0;
    for (printed[0..count]) |tag| {
        Output.print("  {s:<15}", .{tag});
        col += 1;
        if (col >= 4) {
            Output.print("\n", .{});
            col = 0;
        }
    }
    if (col > 0) Output.print("\n", .{});

    Output.print("\nUsage: zid search -t <tag>\n", .{});
}

fn printToolResult(meta: *const search.ToolMeta, reason: search.MatchReason) void {
    Output.print("  \x1b[32m{s}\x1b[0m", .{meta.name});

    // Show match reason
    switch (reason) {
        .name_exact => Output.print(" (exact match)", .{}),
        .alias => Output.print(" (alias)", .{}),
        .tag => Output.print(" (tag)", .{}),
        .keyword => Output.print(" (keyword)", .{}),
        else => {},
    }

    Output.print("\n", .{});
    Output.print("    {s}\n", .{meta.description});
    Output.print("    Category: {s}\n", .{meta.category.string()});
    Output.print("    Tags: ", .{});
    for (meta.tags, 0..) |t, i| {
        if (i > 0) Output.print(", ", .{});
        Output.print("{s}", .{t});
    }
    Output.print("\n    Homepage: {s}\n\n", .{meta.homepage});
}

fn printResultsJson(results: []const search.SearchResult) void {
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("[") catch return;
    for (results, 0..) |result, i| {
        if (i > 0) stdout.writeAll(",") catch return;
        printMetaJson(stdout, result.meta) catch return;
    }
    stdout.writeAll("]\n") catch return;
}

fn printMetaListJson(metas: []const *const search.ToolMeta) void {
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("[") catch return;
    for (metas, 0..) |meta, i| {
        if (i > 0) stdout.writeAll(",") catch return;
        printMetaJson(stdout, meta) catch return;
    }
    stdout.writeAll("]\n") catch return;
}

fn printMetaJson(writer: anytype, meta: *const search.ToolMeta) !void {
    try writer.print(
        \\{{"name":"{s}","description":"{s}","category":"{s}","homepage":"{s}","tags":[
    , .{ meta.name, meta.description, meta.category.string(), meta.homepage });

    for (meta.tags, 0..) |t, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{t});
    }
    try writer.writeAll("]}}");
}

fn parseCategory(s: []const u8) ?Category {
    if (eql(s, "runtime")) return .runtime;
    if (eql(s, "language")) return .language;
    if (eql(s, "build")) return .build;
    if (eql(s, "package_manager") or eql(s, "pm")) return .package_manager;
    if (eql(s, "devtools") or eql(s, "tools")) return .devtools;
    return null;
}

fn printHelp() void {
    Output.bold("zid search - Search for tools\n\n", .{});
    Output.print("Usage:\n", .{});
    Output.print("  zid search <query>                 Search by text\n", .{});
    Output.print("  zid search -c <category>           Filter by category\n", .{});
    Output.print("  zid search -t <tag>                Filter by tag\n", .{});
    Output.print("  zid search --list-categories       List categories\n", .{});
    Output.print("  zid search --list-tags             List all tags\n", .{});
    Output.print("\n", .{});
    Output.print("Options:\n", .{});
    Output.print("  -c, --category <cat>   Filter by category\n", .{});
    Output.print("  -t, --tag <tag>        Filter by tag\n", .{});
    Output.print("  -r, --related          Show related tools\n", .{});
    Output.print("      --json             Output as JSON\n", .{});
    Output.print("      --list-categories  List available categories\n", .{});
    Output.print("      --list-tags        List available tags\n", .{});
    Output.print("  -h, --help             Show this help\n", .{});
    Output.print("\n", .{});
    Output.print("Examples:\n", .{});
    Output.print("  zid search javascript     # Find JS-related tools\n", .{});
    Output.print("  zid search -c runtime     # List all runtimes\n", .{});
    Output.print("  zid search -t fast        # Tools tagged 'fast'\n", .{});
    Output.print("  zid search bun --related  # Bun and similar tools\n", .{});
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn ptrSlice(comptime slice: []const search.ToolMeta) []const *const search.ToolMeta {
    var result: [slice.len]*const search.ToolMeta = undefined;
    for (slice, 0..) |*item, i| {
        result[i] = item;
    }
    return &result;
}

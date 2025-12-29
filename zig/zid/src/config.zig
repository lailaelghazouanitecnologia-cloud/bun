const std = @import("std");

pub const Mapping = struct {
    default: []const u8,
    targets: std.ArrayList([]const u8),
};

pub const Config = struct {
    mappings: std.StringHashMap(Mapping),
    modules: std.StringHashMap([]const u8),
};

pub fn getConfigDir(alloc: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("HOME")) |home| {
        return std.fmt.allocPrint(alloc, "{s}/.zid", .{home});
    }
    return error.NoHomeDir;
}

pub fn getConfigPath(alloc: std.mem.Allocator) ![]const u8 {
    const dir = try getConfigDir(alloc);
    return std.fmt.allocPrint(alloc, "{s}/config.json", .{dir});
}

pub fn load(alloc: std.mem.Allocator) !Config {
    const path = try getConfigPath(alloc);

    const file = std.fs.openFileAbsolute(path, .{}) catch {
        // Return empty config if file doesn't exist
        return Config{
            .mappings = std.StringHashMap(Mapping).init(alloc),
            .modules = std.StringHashMap([]const u8).init(alloc),
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(alloc, 1024 * 1024);
    return parse(alloc, content);
}

pub fn save(alloc: std.mem.Allocator, cfg: Config) !void {
    const dir = try getConfigDir(alloc);

    // Ensure directory exists
    std.fs.makeDirAbsolute(dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const path = try getConfigPath(alloc);
    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();

    try write(file.writer(), cfg);
}

pub fn addMapping(cfg: *Config, alloc: std.mem.Allocator, lang: []const u8, target: []const u8) !void {
    const lang_copy = try alloc.dupe(u8, lang);
    const target_copy = try alloc.dupe(u8, target);

    if (cfg.mappings.getPtr(lang_copy)) |mapping| {
        try mapping.targets.append(target_copy);
    } else {
        var targets = std.ArrayList([]const u8).init(alloc);
        try targets.append(target_copy);
        try cfg.mappings.put(lang_copy, .{
            .default = target_copy,
            .targets = targets,
        });
    }
}

pub fn setDefault(cfg: *Config, lang: []const u8, target: []const u8) !void {
    if (cfg.mappings.getPtr(lang)) |mapping| {
        mapping.default = target;
    } else {
        return error.LangNotConfigured;
    }
}

pub fn removeMapping(cfg: *Config, lang: []const u8, target: []const u8) !void {
    if (cfg.mappings.getPtr(lang)) |mapping| {
        var i: usize = 0;
        while (i < mapping.targets.items.len) {
            if (std.mem.eql(u8, mapping.targets.items[i], target)) {
                _ = mapping.targets.orderedRemove(i);
            } else {
                i += 1;
            }
        }
        if (mapping.targets.items.len == 0) {
            _ = cfg.mappings.remove(lang);
        }
    }
}

pub fn getDefaultTarget(cfg: Config, lang: []const u8) ?[]const u8 {
    if (cfg.mappings.get(lang)) |mapping| {
        return mapping.default;
    }
    return null;
}

fn parse(alloc: std.mem.Allocator, content: []const u8) !Config {
    var cfg = Config{
        .mappings = std.StringHashMap(Mapping).init(alloc),
        .modules = std.StringHashMap([]const u8).init(alloc),
    };

    const parsed = std.json.parseFromSlice(std.json.Value, alloc, content, .{}) catch {
        return cfg;
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    // Parse mappings
    if (root.get("mappings")) |mappings_val| {
        var mit = mappings_val.object.iterator();
        while (mit.next()) |entry| {
            const lang = try alloc.dupe(u8, entry.key_ptr.*);
            const map_obj = entry.value_ptr.object;

            var targets = std.ArrayList([]const u8).init(alloc);
            if (map_obj.get("targets")) |targets_arr| {
                for (targets_arr.array.items) |t| {
                    try targets.append(try alloc.dupe(u8, t.string));
                }
            }

            const default = if (map_obj.get("default")) |d|
                try alloc.dupe(u8, d.string)
            else if (targets.items.len > 0)
                targets.items[0]
            else
                "";

            try cfg.mappings.put(lang, .{
                .default = default,
                .targets = targets,
            });
        }
    }

    // Parse modules
    if (root.get("modules")) |modules_val| {
        var mit = modules_val.object.iterator();
        while (mit.next()) |entry| {
            const name = try alloc.dupe(u8, entry.key_ptr.*);
            const version = try alloc.dupe(u8, entry.value_ptr.string);
            try cfg.modules.put(name, version);
        }
    }

    return cfg;
}

fn write(writer: anytype, cfg: Config) !void {
    try writer.writeAll("{\n");

    // Write mappings
    try writer.writeAll("  \"mappings\": {\n");
    var first_mapping = true;
    var mit = cfg.mappings.iterator();
    while (mit.next()) |entry| {
        if (!first_mapping) try writer.writeAll(",\n");
        first_mapping = false;

        try writer.print("    \"{s}\": {{\n", .{entry.key_ptr.*});
        try writer.print("      \"default\": \"{s}\",\n", .{entry.value_ptr.default});
        try writer.writeAll("      \"targets\": [");

        var first_target = true;
        for (entry.value_ptr.targets.items) |t| {
            if (!first_target) try writer.writeAll(", ");
            first_target = false;
            try writer.print("\"{s}\"", .{t});
        }

        try writer.writeAll("]\n    }");
    }
    try writer.writeAll("\n  },\n");

    // Write modules
    try writer.writeAll("  \"modules\": {\n");
    var first_module = true;
    var moit = cfg.modules.iterator();
    while (moit.next()) |entry| {
        if (!first_module) try writer.writeAll(",\n");
        first_module = false;
        try writer.print("    \"{s}\": \"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    try writer.writeAll("\n  }\n");

    try writer.writeAll("}\n");
}

const std = @import("std");
const config = @import("config.zig");

pub const ModuleType = enum {
    lang,
    target,
};

pub fn parseModuleName(name: []const u8) !struct { type: ModuleType, name: []const u8 } {
    if (std.mem.startsWith(u8, name, "@lang/")) {
        return .{ .type = .lang, .name = name[6..] };
    } else if (std.mem.startsWith(u8, name, "@target/")) {
        return .{ .type = .target, .name = name[8..] };
    }
    return error.InvalidModuleName;
}

pub fn getModulesDir(alloc: std.mem.Allocator) ![]const u8 {
    const cfg_dir = try config.getConfigDir(alloc);
    return std.fmt.allocPrint(alloc, "{s}/modules", .{cfg_dir});
}

pub fn getModulePath(alloc: std.mem.Allocator, module_name: []const u8) ![]const u8 {
    const modules_dir = try getModulesDir(alloc);
    return std.fmt.allocPrint(alloc, "{s}/{s}", .{ modules_dir, module_name });
}

pub fn install(alloc: std.mem.Allocator, module_name: []const u8) !void {
    const parsed = try parseModuleName(module_name);
    const modules_dir = try getModulesDir(alloc);

    // Create modules directory structure
    const type_dir = if (parsed.type == .lang) "@lang" else "@target";
    const full_dir = try std.fmt.allocPrint(alloc, "{s}/{s}/{s}", .{ modules_dir, type_dir, parsed.name });

    std.fs.makeDirAbsolute(modules_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const type_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ modules_dir, type_dir });
    std.fs.makeDirAbsolute(type_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    std.fs.makeDirAbsolute(full_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create mod.zig template
    const mod_path = try std.fmt.allocPrint(alloc, "{s}/mod.zig", .{full_dir});
    const mod_file = std.fs.createFileAbsolute(mod_path, .{ .exclusive = true }) catch |err| {
        if (err == error.PathAlreadyExists) {
            // Already installed
            return;
        }
        return err;
    };
    defer mod_file.close();

    if (parsed.type == .lang) {
        try mod_file.writer().print(
            \\// @lang/{s}
            \\pub const Lang = struct {{
            \\    pub const name = "{s}";
            \\    pub const extensions = &.{{ ".{s}" }};
            \\
            \\    pub const Lexer = @import("lexer.zig").Lexer;
            \\    pub const Parser = @import("parser.zig").Parser;
            \\}};
            \\
        , .{ parsed.name, parsed.name, parsed.name });

        // Create lexer.zig stub
        const lexer_path = try std.fmt.allocPrint(alloc, "{s}/lexer.zig", .{full_dir});
        const lexer_file = try std.fs.createFileAbsolute(lexer_path, .{});
        defer lexer_file.close();
        try lexer_file.writeAll(
            \\const std = @import("std");
            \\
            \\pub const Lexer = struct {
            \\    source: []const u8,
            \\    pos: u32 = 0,
            \\
            \\    pub fn next(self: *Lexer) Token {
            \\        // TODO: implement
            \\        _ = self;
            \\        return .{ .kind = .eof, .start = 0, .end = 0 };
            \\    }
            \\};
            \\
            \\pub const Token = struct {
            \\    kind: TokenKind,
            \\    start: u32,
            \\    end: u32,
            \\};
            \\
            \\pub const TokenKind = enum {
            \\    eof,
            \\    invalid,
            \\    // TODO: add tokens
            \\};
            \\
        );

        // Create parser.zig stub
        const parser_path = try std.fmt.allocPrint(alloc, "{s}/parser.zig", .{full_dir});
        const parser_file = try std.fs.createFileAbsolute(parser_path, .{});
        defer parser_file.close();
        try parser_file.writeAll(
            \\const std = @import("std");
            \\
            \\pub const Parser = struct {
            \\    alloc: std.mem.Allocator,
            \\
            \\    pub fn parse(self: *Parser, tokens: anytype) !Node {
            \\        _ = self;
            \\        _ = tokens;
            \\        return .{ .kind = .program };
            \\    }
            \\};
            \\
            \\pub const Node = struct {
            \\    kind: NodeKind,
            \\    children: []Node = &.{},
            \\};
            \\
            \\pub const NodeKind = enum {
            \\    program,
            \\    // TODO: add nodes
            \\};
            \\
        );
    } else {
        try mod_file.writer().print(
            \\// @target/{s}
            \\pub const Target = struct {{
            \\    pub const name = "{s}";
            \\    pub const extension = ".{s}";
            \\
            \\    pub const Emitter = @import("emitter.zig").Emitter;
            \\}};
            \\
        , .{ parsed.name, parsed.name, parsed.name });

        // Create emitter.zig stub
        const emitter_path = try std.fmt.allocPrint(alloc, "{s}/emitter.zig", .{full_dir});
        const emitter_file = try std.fs.createFileAbsolute(emitter_path, .{});
        defer emitter_file.close();
        try emitter_file.writeAll(
            \\const std = @import("std");
            \\
            \\pub const Emitter = struct {
            \\    output: std.ArrayList(u8),
            \\
            \\    pub fn init(alloc: std.mem.Allocator) Emitter {
            \\        return .{ .output = std.ArrayList(u8).init(alloc) };
            \\    }
            \\
            \\    pub fn emit(self: *Emitter, node: anytype) ![]const u8 {
            \\        _ = node;
            \\        // TODO: implement
            \\        return self.output.items;
            \\    }
            \\};
            \\
        );
    }

    // Update config
    var cfg = try config.load(alloc);
    try cfg.modules.put(try alloc.dupe(u8, module_name), try alloc.dupe(u8, "0.1.0"));
    try config.save(alloc, cfg);
}

pub fn remove(alloc: std.mem.Allocator, module_name: []const u8) !void {
    const path = try getModulePath(alloc, module_name);

    // Remove directory
    std.fs.deleteTreeAbsolute(path) catch {};

    // Update config
    var cfg = try config.load(alloc);
    _ = cfg.modules.remove(module_name);
    try config.save(alloc, cfg);
}

pub fn create(alloc: std.mem.Allocator, module_name: []const u8) !void {
    const parsed = try parseModuleName(module_name);

    // Create in current directory
    std.fs.cwd().makeDir(parsed.name) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create mod.zig
    const mod_path = try std.fmt.allocPrint(alloc, "{s}/mod.zig", .{parsed.name});
    const mod_file = try std.fs.cwd().createFile(mod_path, .{});
    defer mod_file.close();

    if (parsed.type == .lang) {
        try mod_file.writer().print(
            \\// @lang/{s}
            \\pub const Lang = struct {{
            \\    pub const name = "{s}";
            \\    pub const extensions = &.{{ ".{s}" }};
            \\
            \\    pub const Lexer = @import("lexer.zig").Lexer;
            \\    pub const Parser = @import("parser.zig").Parser;
            \\}};
            \\
        , .{ parsed.name, parsed.name, parsed.name });
    } else {
        try mod_file.writer().print(
            \\// @target/{s}
            \\pub const Target = struct {{
            \\    pub const name = "{s}";
            \\    pub const extension = ".{s}";
            \\
            \\    pub const Emitter = @import("emitter.zig").Emitter;
            \\}};
            \\
        , .{ parsed.name, parsed.name, parsed.name });
    }

    // Create zid.mod.json
    const json_path = try std.fmt.allocPrint(alloc, "{s}/zid.mod.json", .{parsed.name});
    const json_file = try std.fs.cwd().createFile(json_path, .{});
    defer json_file.close();
    try json_file.writer().print(
        \\{{
        \\  "name": "{s}",
        \\  "version": "0.1.0",
        \\  "type": "{s}"
        \\}}
        \\
    , .{ module_name, if (parsed.type == .lang) "lang" else "target" });
}

pub fn isInstalled(alloc: std.mem.Allocator, module_name: []const u8) !bool {
    const cfg = try config.load(alloc);
    return cfg.modules.contains(module_name);
}

pub fn getLangModule(alloc: std.mem.Allocator, lang_name: []const u8) ![]const u8 {
    const module_name = try std.fmt.allocPrint(alloc, "@lang/{s}", .{lang_name});
    if (!try isInstalled(alloc, module_name)) {
        return error.ModuleNotInstalled;
    }
    return getModulePath(alloc, module_name);
}

pub fn getTargetModule(alloc: std.mem.Allocator, target_name: []const u8) ![]const u8 {
    const module_name = try std.fmt.allocPrint(alloc, "@target/{s}", .{target_name});
    if (!try isInstalled(alloc, module_name)) {
        return error.ModuleNotInstalled;
    }
    return getModulePath(alloc, module_name);
}

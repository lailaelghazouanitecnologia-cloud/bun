const std = @import("std");
const config = @import("config.zig");
const modules = @import("modules.zig");
const compiler = @import("compiler.zig");

pub fn run(alloc: std.mem.Allocator) !void {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next(); // skip program name

    const cmd = args.next() orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, cmd, "add")) {
        try cmdAdd(alloc, &args);
    } else if (std.mem.eql(u8, cmd, "remove")) {
        try cmdRemove(alloc, &args);
    } else if (std.mem.eql(u8, cmd, "list")) {
        try cmdList(alloc);
    } else if (std.mem.eql(u8, cmd, "config")) {
        try cmdConfig(alloc, &args);
    } else if (std.mem.eql(u8, cmd, "run")) {
        try cmdRun(alloc, &args);
    } else if (std.mem.eql(u8, cmd, "build")) {
        try cmdBuild(alloc, &args);
    } else if (std.mem.eql(u8, cmd, "init")) {
        try cmdInit(alloc);
    } else if (std.mem.eql(u8, cmd, "new")) {
        try cmdNew(alloc, &args);
    } else if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
        printUsage();
    } else if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "-v") or std.mem.eql(u8, cmd, "--version")) {
        std.debug.print("zid 0.1.0\n", .{});
    } else {
        // Assume it's a file to run
        try cmdRunFile(alloc, cmd, &args);
    }
}

fn cmdAdd(alloc: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const module_name = args.next() orelse {
        std.debug.print("Usage: zid add <@lang/name | @target/name>\n", .{});
        return;
    };

    if (!std.mem.startsWith(u8, module_name, "@lang/") and !std.mem.startsWith(u8, module_name, "@target/")) {
        std.debug.print("Error: Module must start with @lang/ or @target/\n", .{});
        return;
    }

    try modules.install(alloc, module_name);
    std.debug.print("Installed {s}\n", .{module_name});
}

fn cmdRemove(alloc: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const module_name = args.next() orelse {
        std.debug.print("Usage: zid remove <@lang/name | @target/name>\n", .{});
        return;
    };

    try modules.remove(alloc, module_name);
    std.debug.print("Removed {s}\n", .{module_name});
}

fn cmdList(alloc: std.mem.Allocator) !void {
    const cfg = try config.load(alloc);

    std.debug.print("Installed modules:\n", .{});
    var it = cfg.modules.iterator();
    while (it.next()) |entry| {
        std.debug.print("  {s} ({s})\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    std.debug.print("\nMappings:\n", .{});
    var mit = cfg.mappings.iterator();
    while (mit.next()) |entry| {
        std.debug.print("  {s} -> {s}\n", .{ entry.key_ptr.*, entry.value_ptr.default });
    }
}

fn cmdConfig(alloc: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const action = args.next() orelse {
        std.debug.print("Usage: zid config <add|set|remove|list> [lang] [target]\n", .{});
        return;
    };

    if (std.mem.eql(u8, action, "list")) {
        try cmdList(alloc);
        return;
    }

    const lang = args.next() orelse {
        std.debug.print("Usage: zid config {s} <lang> <target>\n", .{action});
        return;
    };

    const target = args.next() orelse {
        std.debug.print("Usage: zid config {s} {s} <target>\n", .{ action, lang });
        return;
    };

    var cfg = try config.load(alloc);

    if (std.mem.eql(u8, action, "add")) {
        try config.addMapping(&cfg, alloc, lang, target);
        try config.save(alloc, cfg);
        std.debug.print("Added {s} -> {s}\n", .{ lang, target });
    } else if (std.mem.eql(u8, action, "set")) {
        try config.setDefault(&cfg, lang, target);
        try config.save(alloc, cfg);
        std.debug.print("Set {s} default -> {s}\n", .{ lang, target });
    } else if (std.mem.eql(u8, action, "remove")) {
        try config.removeMapping(&cfg, lang, target);
        try config.save(alloc, cfg);
        std.debug.print("Removed {s} -> {s}\n", .{ lang, target });
    }
}

fn cmdRun(alloc: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const file = args.next() orelse {
        std.debug.print("Usage: zid run <file> [--target <target>]\n", .{});
        return;
    };
    try cmdRunFile(alloc, file, args);
}

fn cmdRunFile(alloc: std.mem.Allocator, file: []const u8, args: *std.process.ArgIterator) !void {
    var target: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--target") or std.mem.eql(u8, arg, "-t")) {
            target = args.next();
        }
    }

    const result = try compiler.compileFile(alloc, file, target);
    std.debug.print("{s}", .{result});
}

fn cmdBuild(alloc: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const file = args.next() orelse {
        std.debug.print("Usage: zid build <file> [-o output] [--target <target>]\n", .{});
        return;
    };

    var output: ?[]const u8 = null;
    var target: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-o")) {
            output = args.next();
        } else if (std.mem.eql(u8, arg, "--target") or std.mem.eql(u8, arg, "-t")) {
            target = args.next();
        }
    }

    const result = try compiler.compileFile(alloc, file, target);

    if (output) |out_path| {
        const out_file = try std.fs.cwd().createFile(out_path, .{});
        defer out_file.close();
        try out_file.writeAll(result);
        std.debug.print("Written to {s}\n", .{out_path});
    } else {
        std.debug.print("{s}", .{result});
    }
}

fn cmdInit(alloc: std.mem.Allocator) !void {
    _ = alloc;
    const file = std.fs.cwd().createFile("zid.json", .{ .exclusive = true }) catch |err| {
        if (err == error.PathAlreadyExists) {
            std.debug.print("zid.json already exists\n", .{});
            return;
        }
        return err;
    };
    defer file.close();

    try file.writeAll(
        \\{
        \\  "overrides": {}
        \\}
        \\
    );
    std.debug.print("Created zid.json\n", .{});
}

fn cmdNew(alloc: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const module_name = args.next() orelse {
        std.debug.print("Usage: zid new <@lang/name | @target/name>\n", .{});
        return;
    };

    try modules.create(alloc, module_name);
    std.debug.print("Created {s}\n", .{module_name});
}

fn printUsage() void {
    std.debug.print(
        \\zid - modular transpiler framework
        \\
        \\Usage: zid <command> [args]
        \\
        \\Commands:
        \\  add <module>          Install @lang/* or @target/*
        \\  remove <module>       Uninstall module
        \\  list                  List installed modules
        \\  config <action>       Configure lang -> target mappings
        \\    add <lang> <target>   Add mapping
        \\    set <lang> <target>   Set default target
        \\    remove <lang> <target> Remove mapping
        \\    list                  Show config
        \\  run <file>            Transpile and execute
        \\  build <file>          Transpile to file
        \\  init                  Create zid.json
        \\  new <module>          Create new module
        \\  help                  Show this help
        \\  version               Show version
        \\
        \\Examples:
        \\  zid add @lang/lua
        \\  zid add @target/wat
        \\  zid config add lua wat
        \\  zid run file.lua
        \\  zid build file.lua -o out.wat
        \\
    , .{});
}

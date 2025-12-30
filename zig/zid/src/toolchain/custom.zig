//! Custom Toolchains
//!
//! Permite al usuario añadir sus propios toolchains via ~/.zid/toolchains.json
//!
//! Formato:
//! ```json
//! {
//!   "gleam": {
//!     "description": "Gleam language",
//!     "homepage": "https://gleam.run",
//!     "url_template": "https://github.com/gleam-lang/gleam/releases/download/v{version}/gleam-v{version}-{arch}-{os}.tar.gz",
//!     "archive": "tar_gz",
//!     "binary": "gleam"
//!   }
//! }
//! ```
//!
//! Uso:
//!   zid toolchain add gleam --url "..." --binary gleam
//!   zid install gleam@1.0.0

const std = @import("std");
const zid = @import("../zid.zig");
const registry = @import("registry.zig");

const Output = zid.Output;
const Maybe = zid.Maybe;

const log = zid.ScopedLog("custom");

// ============ TYPES ============

pub const CustomToolchain = struct {
    name: []const u8,
    description: []const u8 = "",
    homepage: []const u8 = "",
    url_template: []const u8,
    archive: Archive = .tar_gz,
    binary: []const u8,
    binary_path: ?[]const u8 = null,

    pub const Archive = enum {
        tar_gz,
        tar_xz,
        zip,
        none,

        pub fn fromString(s: []const u8) Archive {
            if (std.mem.eql(u8, s, "tar_gz") or std.mem.eql(u8, s, "tar.gz")) return .tar_gz;
            if (std.mem.eql(u8, s, "tar_xz") or std.mem.eql(u8, s, "tar.xz")) return .tar_xz;
            if (std.mem.eql(u8, s, "zip")) return .zip;
            if (std.mem.eql(u8, s, "none") or std.mem.eql(u8, s, "binary")) return .none;
            return .tar_gz;
        }
    };

    /// Convert to registry ToolDef format
    pub fn toToolDef(self: CustomToolchain) registry.ToolDef {
        return .{
            .kind = .bun, // Placeholder, custom toolchains use name
            .name = self.name,
            .description = self.description,
            .homepage = self.homepage,
            .url_template = self.url_template,
            .archive = switch (self.archive) {
                .tar_gz => .tar_gz,
                .tar_xz => .tar_xz,
                .zip => .zip,
                .none => .none,
            },
            .binary = self.binary,
            .binary_path = self.binary_path,
        };
    }
};

// ============ DATABASE ============

pub const Database = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    toolchains: std.StringHashMap(CustomToolchain),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const home = zid.getHome();
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/toolchains.json", .{home}) catch "~/.zid/toolchains.json";

        return .{
            .allocator = allocator,
            .path = path,
            .toolchains = std.StringHashMap(CustomToolchain).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.toolchains.deinit();
    }

    /// Load from disk
    pub fn load(self: *Self) Maybe(void) {
        const file = std.fs.openFileAbsolute(self.path, .{}) catch |e| {
            if (e == error.FileNotFound) {
                return zid.ok(void, {});
            }
            return zid.fail(void, e, .read_file, self.path);
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch |e| {
            return zid.fail(void, e, .read_file, self.path);
        };
        defer self.allocator.free(content);

        // Parse JSON
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch {
            return zid.err(void, .{ .code = .parse_error, .message = "invalid toolchains.json" });
        };
        defer parsed.deinit();

        // Load entries
        if (parsed.value == .object) {
            var it = parsed.value.object.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                const obj = entry.value_ptr.*;

                if (obj != .object) continue;

                const tc = parseToolchain(name, obj.object) orelse continue;
                self.toolchains.put(name, tc) catch continue;
            }
        }

        log.debug("loaded {d} custom toolchains", .{self.toolchains.count()});
        return zid.ok(void, {});
    }

    /// Save to disk
    pub fn save(self: *Self) Maybe(void) {
        // Ensure parent directory exists
        const home = zid.getHome();
        std.fs.makeDirAbsolute(home) catch {};

        const file = std.fs.createFileAbsolute(self.path, .{}) catch |e| {
            return zid.fail(void, e, .write_file, self.path);
        };
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        var jw = std.json.writeStream(buffered.writer(), .{ .whitespace = .indent_2 });

        jw.beginObject() catch {};

        var it = self.toolchains.iterator();
        while (it.next()) |entry| {
            const tc = entry.value_ptr.*;

            jw.objectField(tc.name) catch {};
            jw.beginObject() catch {};

            jw.objectField("description") catch {};
            jw.write(tc.description) catch {};

            jw.objectField("homepage") catch {};
            jw.write(tc.homepage) catch {};

            jw.objectField("url_template") catch {};
            jw.write(tc.url_template) catch {};

            jw.objectField("archive") catch {};
            jw.write(@tagName(tc.archive)) catch {};

            jw.objectField("binary") catch {};
            jw.write(tc.binary) catch {};

            if (tc.binary_path) |bp| {
                jw.objectField("binary_path") catch {};
                jw.write(bp) catch {};
            }

            jw.endObject() catch {};
        }

        jw.endObject() catch {};
        buffered.flush() catch {};

        return zid.ok(void, {});
    }

    /// Add custom toolchain
    pub fn add(self: *Self, tc: CustomToolchain) Maybe(void) {
        self.toolchains.put(tc.name, tc) catch {
            return zid.err(void, .{ .code = .internal_error, .message = "failed to add toolchain" });
        };
        return self.save();
    }

    /// Remove custom toolchain
    pub fn remove(self: *Self, name: []const u8) Maybe(bool) {
        if (self.toolchains.remove(name)) {
            return switch (self.save()) {
                .ok => zid.ok(bool, true),
                .err => |e| zid.err(bool, e),
            };
        }
        return zid.ok(bool, false);
    }

    /// Get toolchain by name
    pub fn get(self: *Self, name: []const u8) ?CustomToolchain {
        return self.toolchains.get(name);
    }

    /// Check if exists
    pub fn has(self: *Self, name: []const u8) bool {
        return self.toolchains.contains(name);
    }

    /// List all
    pub fn list(self: *Self) []CustomToolchain {
        var result = std.ArrayList(CustomToolchain).init(self.allocator);
        var it = self.toolchains.iterator();
        while (it.next()) |entry| {
            result.append(entry.value_ptr.*) catch continue;
        }
        return result.toOwnedSlice() catch &.{};
    }
};

fn parseToolchain(name: []const u8, obj: std.json.ObjectMap) ?CustomToolchain {
    const url = if (obj.get("url_template")) |v| switch (v) {
        .string => |s| s,
        else => return null,
    } else return null;

    const binary = if (obj.get("binary")) |v| switch (v) {
        .string => |s| s,
        else => name,
    } else name;

    const desc = if (obj.get("description")) |v| switch (v) {
        .string => |s| s,
        else => "",
    } else "";

    const homepage = if (obj.get("homepage")) |v| switch (v) {
        .string => |s| s,
        else => "",
    } else "";

    const archive_str = if (obj.get("archive")) |v| switch (v) {
        .string => |s| s,
        else => "tar_gz",
    } else "tar_gz";

    const binary_path = if (obj.get("binary_path")) |v| switch (v) {
        .string => |s| s,
        else => null,
    } else null;

    return .{
        .name = name,
        .description = desc,
        .homepage = homepage,
        .url_template = url,
        .archive = CustomToolchain.Archive.fromString(archive_str),
        .binary = binary,
        .binary_path = binary_path,
    };
}

// ============ CLI ============

/// Run toolchain subcommand
pub fn runCommand(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len == 0) {
        showHelp();
        return;
    }

    const sub = args[0];
    const sub_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    if (std.mem.eql(u8, sub, "add") or std.mem.eql(u8, sub, "register")) {
        runAdd(allocator, sub_args);
    } else if (std.mem.eql(u8, sub, "remove") or std.mem.eql(u8, sub, "rm")) {
        runRemove(allocator, sub_args);
    } else if (std.mem.eql(u8, sub, "list") or std.mem.eql(u8, sub, "ls")) {
        runList(allocator);
    } else {
        Output.err("Unknown subcommand: {s}\n", .{sub});
        showHelp();
    }
}

fn runAdd(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len < 1) {
        Output.err("Missing toolchain name\n", .{});
        Output.print("Usage: zid toolchain add <name> --url <template> --binary <name>\n", .{});
        return;
    }

    const name = args[0];
    var url: ?[]const u8 = null;
    var binary: []const u8 = name;
    var archive: []const u8 = "tar_gz";
    var desc: []const u8 = "";

    // Parse options
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--url") and i + 1 < args.len) {
            i += 1;
            url = args[i];
        } else if (std.mem.eql(u8, arg, "--binary") and i + 1 < args.len) {
            i += 1;
            binary = args[i];
        } else if (std.mem.eql(u8, arg, "--archive") and i + 1 < args.len) {
            i += 1;
            archive = args[i];
        } else if (std.mem.eql(u8, arg, "--desc") and i + 1 < args.len) {
            i += 1;
            desc = args[i];
        }
    }

    if (url == null) {
        Output.err("Missing --url\n", .{});
        Output.print("Example: --url 'https://.../{version}/tool-{os}-{arch}.tar.gz'\n", .{});
        return;
    }

    var db = Database.init(allocator);
    defer db.deinit();
    _ = db.load();

    switch (db.add(.{
        .name = name,
        .description = desc,
        .url_template = url.?,
        .archive = CustomToolchain.Archive.fromString(archive),
        .binary = binary,
    })) {
        .ok => {
            Output.success("Added toolchain: {s}\n", .{name});
            Output.print("Install with: zid install {s}@<version>\n", .{name});
        },
        .err => |e| {
            Output.err("Failed: {s}\n", .{e.message});
        },
    }
}

fn runRemove(allocator: std.mem.Allocator, args: []const []const u8) void {
    if (args.len < 1) {
        Output.err("Missing toolchain name\n", .{});
        return;
    }

    var db = Database.init(allocator);
    defer db.deinit();
    _ = db.load();

    switch (db.remove(args[0])) {
        .ok => |removed| {
            if (removed) {
                Output.success("Removed: {s}\n", .{args[0]});
            } else {
                Output.err("Not found: {s}\n", .{args[0]});
            }
        },
        .err => |e| {
            Output.err("Failed: {s}\n", .{e.message});
        },
    }
}

fn runList(allocator: std.mem.Allocator) void {
    var db = Database.init(allocator);
    defer db.deinit();
    _ = db.load();

    Output.bold("Custom Toolchains:\n\n", .{});

    const toolchains = db.list();
    if (toolchains.len == 0) {
        Output.print("  (none)\n", .{});
        Output.print("\nAdd with: zid toolchain add <name> --url <template>\n", .{});
        return;
    }

    for (toolchains) |tc| {
        Output.print("  {s: <16} {s}\n", .{ tc.name, tc.description });
    }
}

fn showHelp() void {
    Output.bold("zid toolchain", .{});
    Output.print(" - Manage custom toolchains\n\n", .{});
    Output.print("Commands:\n", .{});
    Output.print("  add <name>     Add custom toolchain\n", .{});
    Output.print("  remove <name>  Remove custom toolchain\n", .{});
    Output.print("  list           List custom toolchains\n", .{});
    Output.print("\nOptions for 'add':\n", .{});
    Output.print("  --url <template>   URL with {version}, {os}, {arch}\n", .{});
    Output.print("  --binary <name>    Binary name inside archive\n", .{});
    Output.print("  --archive <type>   tar_gz, tar_xz, zip, none\n", .{});
    Output.print("  --desc <text>      Description\n", .{});
    Output.print("\nExample:\n", .{});
    Output.print("  zid toolchain add gleam \\\n", .{});
    Output.print("    --url 'https://github.com/gleam-lang/gleam/releases/download/v{version}/gleam-v{version}-{arch}-unknown-{os}-musl.tar.gz' \\\n", .{});
    Output.print("    --binary gleam\n", .{});
}

// ============ INTEGRATION ============

/// Check if name is a custom toolchain
pub fn isCustom(allocator: std.mem.Allocator, name: []const u8) bool {
    var db = Database.init(allocator);
    defer db.deinit();
    switch (db.load()) {
        .ok => {},
        .err => return false,
    }
    return db.has(name);
}

/// Get custom toolchain def
pub fn getCustom(allocator: std.mem.Allocator, name: []const u8) ?CustomToolchain {
    var db = Database.init(allocator);
    defer db.deinit();
    switch (db.load()) {
        .ok => {},
        .err => return null,
    }
    return db.get(name);
}

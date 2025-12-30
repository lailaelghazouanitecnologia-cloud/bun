const std = @import("std");

/// Module resolution for built-in and user modules
pub const Resolver = struct {
    alloc: std.mem.Allocator,
    lang: []const u8,

    // Registered modules
    builtin_modules: std.StringHashMap(Module),
    user_modules: std.StringHashMap(Module),

    pub fn init(alloc: std.mem.Allocator, lang: []const u8) Resolver {
        var r = Resolver{
            .alloc = alloc,
            .lang = lang,
            .builtin_modules = std.StringHashMap(Module).init(alloc),
            .user_modules = std.StringHashMap(Module).init(alloc),
        };

        // Register built-ins based on language
        if (std.mem.eql(u8, lang, "lua")) {
            r.registerLuaBuiltins();
        } else if (std.mem.eql(u8, lang, "rust")) {
            r.registerRustBuiltins();
        }

        return r;
    }

    pub fn resolve(self: *Resolver, name: []const u8) ?Module {
        // Check user modules first (allow override)
        if (self.user_modules.get(name)) |m| return m;

        // Then built-ins
        if (self.builtin_modules.get(name)) |m| return m;

        return null;
    }

    pub fn register(self: *Resolver, name: []const u8, module: Module) !void {
        try self.user_modules.put(name, module);
    }

    pub fn has(self: *Resolver, name: []const u8) bool {
        return self.user_modules.contains(name) or self.builtin_modules.contains(name);
    }

    pub fn list(self: *Resolver) []const []const u8 {
        var names = std.ArrayList([]const u8).init(self.alloc);

        var it = self.builtin_modules.keyIterator();
        while (it.next()) |key| {
            names.append(key.*) catch {};
        }

        var uit = self.user_modules.keyIterator();
        while (uit.next()) |key| {
            names.append(key.*) catch {};
        }

        return names.items;
    }

    // ============ LUA BUILT-INS ============

    fn registerLuaBuiltins(self: *Resolver) void {
        const lua_modules = .{
            .{ "io", Module{ .kind = .native, .funcs = &lua_io_funcs } },
            .{ "os", Module{ .kind = .native, .funcs = &lua_os_funcs } },
            .{ "string", Module{ .kind = .native, .funcs = &lua_string_funcs } },
            .{ "math", Module{ .kind = .native, .funcs = &lua_math_funcs } },
            .{ "table", Module{ .kind = .native, .funcs = &lua_table_funcs } },
            .{ "coroutine", Module{ .kind = .native, .funcs = &lua_coroutine_funcs } },
            .{ "debug", Module{ .kind = .native, .funcs = &lua_debug_funcs } },
            .{ "package", Module{ .kind = .native, .funcs = &lua_package_funcs } },
        };

        inline for (lua_modules) |m| {
            self.builtin_modules.put(m[0], m[1]) catch {};
        }
    }

    // ============ RUST BUILT-INS ============

    fn registerRustBuiltins(self: *Resolver) void {
        const rust_modules = .{
            .{ "std::io", Module{ .kind = .native, .funcs = &rust_io_funcs } },
            .{ "std::fs", Module{ .kind = .native, .funcs = &rust_fs_funcs } },
            .{ "std::vec", Module{ .kind = .native, .funcs = &rust_vec_funcs } },
            .{ "std::string", Module{ .kind = .native, .funcs = &rust_string_funcs } },
            .{ "std::collections", Module{ .kind = .native, .funcs = &rust_collections_funcs } },
            .{ "std::env", Module{ .kind = .native, .funcs = &rust_env_funcs } },
            .{ "std::path", Module{ .kind = .native, .funcs = &rust_path_funcs } },
            .{ "std::process", Module{ .kind = .native, .funcs = &rust_process_funcs } },
            .{ "std::thread", Module{ .kind = .native, .funcs = &rust_thread_funcs } },
            .{ "std::sync", Module{ .kind = .native, .funcs = &rust_sync_funcs } },
            .{ "std::net", Module{ .kind = .native, .funcs = &rust_net_funcs } },
            .{ "std::time", Module{ .kind = .native, .funcs = &rust_time_funcs } },
        };

        inline for (rust_modules) |m| {
            self.builtin_modules.put(m[0], m[1]) catch {};
        }
    }
};

// ============ MODULE & FUNCTION TYPES ============

pub const Module = struct {
    kind: ModuleKind,
    funcs: []const Func = &.{},
    types: []const Type = &.{},
    source: ?[]const u8 = null,
};

pub const ModuleKind = enum {
    native,     // Implemented in Zig
    source,     // Implemented in source language
    external,   // External library
};

pub const Func = struct {
    name: []const u8,
    params: []const Param = &.{},
    ret: ValueType = .void,
    native: ?*const fn ([]Value) Value = null,
};

pub const Param = struct {
    name: []const u8,
    typ: ValueType,
};

pub const Type = struct {
    name: []const u8,
    fields: []const Field = &.{},
};

pub const Field = struct {
    name: []const u8,
    typ: ValueType,
};

pub const ValueType = enum {
    void,
    i32,
    i64,
    f32,
    f64,
    bool,
    string,
    bytes,
    array,
    table,
    func,
    any,
};

pub const Value = union(enum) {
    void,
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
    bool: bool,
    string: []const u8,
    bytes: []u8,
    array: []Value,
    table: std.StringHashMap(Value),
    func: *const fn ([]Value) Value,

    pub fn asI32(self: Value) i32 {
        return switch (self) {
            .i32 => |v| v,
            .i64 => |v| @intCast(v),
            .f32 => |v| @intFromFloat(v),
            .f64 => |v| @intFromFloat(v),
            .bool => |v| if (v) @as(i32, 1) else 0,
            else => 0,
        };
    }

    pub fn asString(self: Value) []const u8 {
        return switch (self) {
            .string => |v| v,
            else => "",
        };
    }

    pub fn asBool(self: Value) bool {
        return switch (self) {
            .bool => |v| v,
            .i32 => |v| v != 0,
            .void => false,
            else => true,
        };
    }
};

// ============ LUA FUNCTION SIGNATURES ============

const lua_io_funcs = [_]Func{
    .{ .name = "read", .params = &.{.{ .name = "file", .typ = .string }}, .ret = .string },
    .{ .name = "write", .params = &.{.{ .name = "file", .typ = .string }, .{ .name = "data", .typ = .string }}, .ret = .void },
    .{ .name = "open", .params = &.{.{ .name = "file", .typ = .string }, .{ .name = "mode", .typ = .string }}, .ret = .any },
    .{ .name = "close", .params = &.{.{ .name = "handle", .typ = .any }}, .ret = .void },
    .{ .name = "lines", .params = &.{.{ .name = "file", .typ = .string }}, .ret = .func },
    .{ .name = "input", .params = &.{.{ .name = "file", .typ = .string }}, .ret = .any },
    .{ .name = "output", .params = &.{.{ .name = "file", .typ = .string }}, .ret = .any },
    .{ .name = "flush", .ret = .void },
};

const lua_os_funcs = [_]Func{
    .{ .name = "clock", .ret = .f64 },
    .{ .name = "date", .params = &.{.{ .name = "format", .typ = .string }}, .ret = .string },
    .{ .name = "time", .ret = .i64 },
    .{ .name = "exit", .params = &.{.{ .name = "code", .typ = .i32 }}, .ret = .void },
    .{ .name = "getenv", .params = &.{.{ .name = "name", .typ = .string }}, .ret = .string },
    .{ .name = "execute", .params = &.{.{ .name = "cmd", .typ = .string }}, .ret = .i32 },
    .{ .name = "remove", .params = &.{.{ .name = "file", .typ = .string }}, .ret = .bool },
    .{ .name = "rename", .params = &.{.{ .name = "old", .typ = .string }, .{ .name = "new", .typ = .string }}, .ret = .bool },
    .{ .name = "tmpname", .ret = .string },
};

const lua_string_funcs = [_]Func{
    .{ .name = "len", .params = &.{.{ .name = "s", .typ = .string }}, .ret = .i32 },
    .{ .name = "sub", .params = &.{.{ .name = "s", .typ = .string }, .{ .name = "i", .typ = .i32 }, .{ .name = "j", .typ = .i32 }}, .ret = .string },
    .{ .name = "upper", .params = &.{.{ .name = "s", .typ = .string }}, .ret = .string },
    .{ .name = "lower", .params = &.{.{ .name = "s", .typ = .string }}, .ret = .string },
    .{ .name = "rep", .params = &.{.{ .name = "s", .typ = .string }, .{ .name = "n", .typ = .i32 }}, .ret = .string },
    .{ .name = "reverse", .params = &.{.{ .name = "s", .typ = .string }}, .ret = .string },
    .{ .name = "byte", .params = &.{.{ .name = "s", .typ = .string }, .{ .name = "i", .typ = .i32 }}, .ret = .i32 },
    .{ .name = "char", .params = &.{.{ .name = "n", .typ = .i32 }}, .ret = .string },
    .{ .name = "find", .params = &.{.{ .name = "s", .typ = .string }, .{ .name = "pattern", .typ = .string }}, .ret = .i32 },
    .{ .name = "match", .params = &.{.{ .name = "s", .typ = .string }, .{ .name = "pattern", .typ = .string }}, .ret = .string },
    .{ .name = "gsub", .params = &.{.{ .name = "s", .typ = .string }, .{ .name = "pattern", .typ = .string }, .{ .name = "repl", .typ = .string }}, .ret = .string },
    .{ .name = "format", .params = &.{.{ .name = "fmt", .typ = .string }}, .ret = .string },
};

const lua_math_funcs = [_]Func{
    .{ .name = "abs", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "ceil", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .i64 },
    .{ .name = "floor", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .i64 },
    .{ .name = "max", .params = &.{.{ .name = "a", .typ = .f64 }, .{ .name = "b", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "min", .params = &.{.{ .name = "a", .typ = .f64 }, .{ .name = "b", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "sqrt", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "pow", .params = &.{.{ .name = "x", .typ = .f64 }, .{ .name = "y", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "sin", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "cos", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "tan", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "log", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "exp", .params = &.{.{ .name = "x", .typ = .f64 }}, .ret = .f64 },
    .{ .name = "random", .ret = .f64 },
    .{ .name = "randomseed", .params = &.{.{ .name = "seed", .typ = .i64 }}, .ret = .void },
};

const lua_table_funcs = [_]Func{
    .{ .name = "insert", .params = &.{.{ .name = "t", .typ = .table }, .{ .name = "v", .typ = .any }}, .ret = .void },
    .{ .name = "remove", .params = &.{.{ .name = "t", .typ = .table }, .{ .name = "i", .typ = .i32 }}, .ret = .any },
    .{ .name = "sort", .params = &.{.{ .name = "t", .typ = .table }}, .ret = .void },
    .{ .name = "concat", .params = &.{.{ .name = "t", .typ = .table }, .{ .name = "sep", .typ = .string }}, .ret = .string },
    .{ .name = "pack", .ret = .table },
    .{ .name = "unpack", .params = &.{.{ .name = "t", .typ = .table }}, .ret = .any },
};

const lua_coroutine_funcs = [_]Func{
    .{ .name = "create", .params = &.{.{ .name = "f", .typ = .func }}, .ret = .any },
    .{ .name = "resume", .params = &.{.{ .name = "co", .typ = .any }}, .ret = .any },
    .{ .name = "yield", .ret = .any },
    .{ .name = "status", .params = &.{.{ .name = "co", .typ = .any }}, .ret = .string },
    .{ .name = "wrap", .params = &.{.{ .name = "f", .typ = .func }}, .ret = .func },
};

const lua_debug_funcs = [_]Func{
    .{ .name = "traceback", .ret = .string },
    .{ .name = "getinfo", .params = &.{.{ .name = "level", .typ = .i32 }}, .ret = .table },
    .{ .name = "getlocal", .params = &.{.{ .name = "level", .typ = .i32 }, .{ .name = "n", .typ = .i32 }}, .ret = .any },
    .{ .name = "setlocal", .params = &.{.{ .name = "level", .typ = .i32 }, .{ .name = "n", .typ = .i32 }, .{ .name = "v", .typ = .any }}, .ret = .void },
};

const lua_package_funcs = [_]Func{
    .{ .name = "loadlib", .params = &.{.{ .name = "lib", .typ = .string }, .{ .name = "func", .typ = .string }}, .ret = .func },
    .{ .name = "searchpath", .params = &.{.{ .name = "name", .typ = .string }, .{ .name = "path", .typ = .string }}, .ret = .string },
};

// ============ RUST FUNCTION SIGNATURES ============

const rust_io_funcs = [_]Func{
    .{ .name = "stdin", .ret = .any },
    .{ .name = "stdout", .ret = .any },
    .{ .name = "stderr", .ret = .any },
    .{ .name = "read_line", .params = &.{.{ .name = "buf", .typ = .string }}, .ret = .i32 },
    .{ .name = "BufReader::new", .params = &.{.{ .name = "r", .typ = .any }}, .ret = .any },
    .{ .name = "BufWriter::new", .params = &.{.{ .name = "w", .typ = .any }}, .ret = .any },
};

const rust_fs_funcs = [_]Func{
    .{ .name = "read_to_string", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .string },
    .{ .name = "write", .params = &.{.{ .name = "path", .typ = .string }, .{ .name = "data", .typ = .bytes }}, .ret = .void },
    .{ .name = "read", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .bytes },
    .{ .name = "create", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .any },
    .{ .name = "open", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .any },
    .{ .name = "remove_file", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .void },
    .{ .name = "remove_dir", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .void },
    .{ .name = "create_dir", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .void },
    .{ .name = "create_dir_all", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .void },
    .{ .name = "read_dir", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .any },
    .{ .name = "metadata", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .any },
    .{ .name = "copy", .params = &.{.{ .name = "from", .typ = .string }, .{ .name = "to", .typ = .string }}, .ret = .i64 },
    .{ .name = "rename", .params = &.{.{ .name = "from", .typ = .string }, .{ .name = "to", .typ = .string }}, .ret = .void },
};

const rust_vec_funcs = [_]Func{
    .{ .name = "new", .ret = .array },
    .{ .name = "with_capacity", .params = &.{.{ .name = "cap", .typ = .i32 }}, .ret = .array },
    .{ .name = "push", .params = &.{.{ .name = "v", .typ = .any }}, .ret = .void },
    .{ .name = "pop", .ret = .any },
    .{ .name = "len", .ret = .i32 },
    .{ .name = "is_empty", .ret = .bool },
    .{ .name = "clear", .ret = .void },
    .{ .name = "get", .params = &.{.{ .name = "i", .typ = .i32 }}, .ret = .any },
    .{ .name = "first", .ret = .any },
    .{ .name = "last", .ret = .any },
    .{ .name = "iter", .ret = .any },
};

const rust_string_funcs = [_]Func{
    .{ .name = "new", .ret = .string },
    .{ .name = "from", .params = &.{.{ .name = "s", .typ = .string }}, .ret = .string },
    .{ .name = "push_str", .params = &.{.{ .name = "s", .typ = .string }}, .ret = .void },
    .{ .name = "push", .params = &.{.{ .name = "c", .typ = .i32 }}, .ret = .void },
    .{ .name = "len", .ret = .i32 },
    .{ .name = "is_empty", .ret = .bool },
    .{ .name = "clear", .ret = .void },
    .{ .name = "contains", .params = &.{.{ .name = "pat", .typ = .string }}, .ret = .bool },
    .{ .name = "starts_with", .params = &.{.{ .name = "pat", .typ = .string }}, .ret = .bool },
    .{ .name = "ends_with", .params = &.{.{ .name = "pat", .typ = .string }}, .ret = .bool },
    .{ .name = "replace", .params = &.{.{ .name = "from", .typ = .string }, .{ .name = "to", .typ = .string }}, .ret = .string },
    .{ .name = "trim", .ret = .string },
    .{ .name = "to_uppercase", .ret = .string },
    .{ .name = "to_lowercase", .ret = .string },
    .{ .name = "split", .params = &.{.{ .name = "pat", .typ = .string }}, .ret = .any },
    .{ .name = "chars", .ret = .any },
    .{ .name = "bytes", .ret = .any },
};

const rust_collections_funcs = [_]Func{
    .{ .name = "HashMap::new", .ret = .table },
    .{ .name = "HashMap::insert", .params = &.{.{ .name = "k", .typ = .any }, .{ .name = "v", .typ = .any }}, .ret = .any },
    .{ .name = "HashMap::get", .params = &.{.{ .name = "k", .typ = .any }}, .ret = .any },
    .{ .name = "HashMap::remove", .params = &.{.{ .name = "k", .typ = .any }}, .ret = .any },
    .{ .name = "HashMap::contains_key", .params = &.{.{ .name = "k", .typ = .any }}, .ret = .bool },
    .{ .name = "HashSet::new", .ret = .any },
    .{ .name = "HashSet::insert", .params = &.{.{ .name = "v", .typ = .any }}, .ret = .bool },
    .{ .name = "HashSet::contains", .params = &.{.{ .name = "v", .typ = .any }}, .ret = .bool },
    .{ .name = "BTreeMap::new", .ret = .table },
    .{ .name = "VecDeque::new", .ret = .array },
};

const rust_env_funcs = [_]Func{
    .{ .name = "var", .params = &.{.{ .name = "key", .typ = .string }}, .ret = .string },
    .{ .name = "set_var", .params = &.{.{ .name = "key", .typ = .string }, .{ .name = "val", .typ = .string }}, .ret = .void },
    .{ .name = "remove_var", .params = &.{.{ .name = "key", .typ = .string }}, .ret = .void },
    .{ .name = "vars", .ret = .any },
    .{ .name = "current_dir", .ret = .string },
    .{ .name = "set_current_dir", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .void },
    .{ .name = "args", .ret = .any },
};

const rust_path_funcs = [_]Func{
    .{ .name = "Path::new", .params = &.{.{ .name = "s", .typ = .string }}, .ret = .any },
    .{ .name = "PathBuf::new", .ret = .any },
    .{ .name = "exists", .ret = .bool },
    .{ .name = "is_file", .ret = .bool },
    .{ .name = "is_dir", .ret = .bool },
    .{ .name = "extension", .ret = .string },
    .{ .name = "file_name", .ret = .string },
    .{ .name = "parent", .ret = .any },
    .{ .name = "join", .params = &.{.{ .name = "path", .typ = .string }}, .ret = .any },
};

const rust_process_funcs = [_]Func{
    .{ .name = "Command::new", .params = &.{.{ .name = "prog", .typ = .string }}, .ret = .any },
    .{ .name = "exit", .params = &.{.{ .name = "code", .typ = .i32 }}, .ret = .void },
    .{ .name = "abort", .ret = .void },
    .{ .name = "id", .ret = .i32 },
};

const rust_thread_funcs = [_]Func{
    .{ .name = "spawn", .params = &.{.{ .name = "f", .typ = .func }}, .ret = .any },
    .{ .name = "sleep", .params = &.{.{ .name = "dur", .typ = .any }}, .ret = .void },
    .{ .name = "yield_now", .ret = .void },
    .{ .name = "current", .ret = .any },
    .{ .name = "park", .ret = .void },
};

const rust_sync_funcs = [_]Func{
    .{ .name = "Mutex::new", .params = &.{.{ .name = "v", .typ = .any }}, .ret = .any },
    .{ .name = "RwLock::new", .params = &.{.{ .name = "v", .typ = .any }}, .ret = .any },
    .{ .name = "Arc::new", .params = &.{.{ .name = "v", .typ = .any }}, .ret = .any },
    .{ .name = "mpsc::channel", .ret = .any },
};

const rust_net_funcs = [_]Func{
    .{ .name = "TcpListener::bind", .params = &.{.{ .name = "addr", .typ = .string }}, .ret = .any },
    .{ .name = "TcpStream::connect", .params = &.{.{ .name = "addr", .typ = .string }}, .ret = .any },
    .{ .name = "UdpSocket::bind", .params = &.{.{ .name = "addr", .typ = .string }}, .ret = .any },
};

const rust_time_funcs = [_]Func{
    .{ .name = "Instant::now", .ret = .any },
    .{ .name = "Duration::from_secs", .params = &.{.{ .name = "secs", .typ = .i64 }}, .ret = .any },
    .{ .name = "Duration::from_millis", .params = &.{.{ .name = "ms", .typ = .i64 }}, .ret = .any },
    .{ .name = "SystemTime::now", .ret = .any },
};

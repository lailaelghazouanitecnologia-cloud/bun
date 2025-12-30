//! Logger - Structured logging with source locations
//!
//! Pattern from Bun's logger.zig.
//! Provides Kind, Loc, Location, Range, Data, Msg, and Log types for
//! structured error reporting with source file context.

const std = @import("std");
const Environment = @import("../env.zig");
const Output = @import("../output.zig");

// ============ MESSAGE KIND ============

/// Message severity levels
pub const Kind = enum(u8) {
    err = 0,
    warn = 1,
    note = 2,
    debug = 3,
    verbose = 4,

    /// Check if this kind should print given the log level
    pub inline fn shouldPrint(this: Kind, level: Log.Level) bool {
        return switch (level) {
            .err => switch (this) {
                .err, .note => true,
                else => false,
            },
            .warn => switch (this) {
                .err, .warn, .note => true,
                else => false,
            },
            .info, .debug => this != .verbose,
            .verbose => true,
        };
    }

    /// Get string representation
    pub inline fn string(self: Kind) []const u8 {
        return switch (self) {
            .err => "error",
            .warn => "warn",
            .note => "note",
            .debug => "debug",
            .verbose => "verbose",
        };
    }
};

// ============ SOURCE LOCATIONS ============

/// Minimal location - just byte offset
/// -1 means empty/unknown location
pub const Loc = struct {
    start: i32 = -1,

    pub const Empty = Loc{ .start = -1 };

    pub inline fn toNullable(loc: Loc) ?Loc {
        return if (loc.start == -1) null else loc;
    }

    pub inline fn toUsize(self: *const Loc) usize {
        return @as(usize, @intCast(@max(self.start, 0)));
    }

    pub inline fn isEmpty(this: Loc) bool {
        return this.start == Empty.start;
    }

    pub inline fn eql(loc: Loc, other: Loc) bool {
        return loc.start == other.start;
    }
};

/// Full location with file, line, column info
pub const Location = struct {
    file: []const u8,
    namespace: []const u8 = "file",
    line_text: ?[]const u8 = null,
    length: usize = 0,
    offset: usize = 0,
    line: i32, // 1-based, <=0 means unknown
    column: i32, // 0-based in bytes

    pub fn init(
        file: []const u8,
        line: i32,
        column: i32,
    ) Location {
        return Location{
            .file = file,
            .line = line,
            .column = column,
        };
    }

    pub fn withText(
        file: []const u8,
        line: i32,
        column: i32,
        line_text: []const u8,
    ) Location {
        return Location{
            .file = file,
            .line = line,
            .column = column,
            .line_text = line_text,
        };
    }

    pub fn clone(this: Location, allocator: std.mem.Allocator) !Location {
        return Location{
            .file = try allocator.dupe(u8, this.file),
            .namespace = this.namespace,
            .line = this.line,
            .column = this.column,
            .length = this.length,
            .line_text = if (this.line_text) |t| try allocator.dupe(u8, t) else null,
            .offset = this.offset,
        };
    }

    pub fn memoryCost(this: *const Location) usize {
        var cost: usize = 0;
        cost += this.file.len;
        cost += this.namespace.len;
        if (this.line_text) |text| cost += text.len;
        return cost;
    }
};

/// Range in source - location + length
pub const Range = struct {
    loc: Loc = Loc.Empty,
    len: i32 = 0,

    pub const none = Range{ .loc = Loc.Empty, .len = 0 };

    pub fn in(this: Range, buf: []const u8) []const u8 {
        if (this.loc.start < 0 or this.len <= 0) return "";
        const slice = buf[@as(usize, @intCast(this.loc.start))..];
        return slice[0..@min(@as(usize, @intCast(this.len)), slice.len)];
    }

    pub fn contains(this: Range, k: i32) bool {
        return k >= this.loc.start and k < this.loc.start + this.len;
    }

    pub inline fn isEmpty(r: *const Range) bool {
        return r.len == 0 and r.loc.start == Loc.Empty.start;
    }

    pub fn end(self: *const Range) Loc {
        return Loc{ .start = self.loc.start + self.len };
    }
};

// ============ MESSAGE DATA ============

/// Compact string reference within a parent string
/// Saves memory for small substrings
pub const BabyString = packed struct(u32) {
    offset: u16,
    len: u16,

    pub fn in(parent: []const u8, text: []const u8) BabyString {
        const idx = std.mem.indexOf(u8, parent, text) orelse 0;
        return BabyString{
            .offset = @as(u16, @truncate(idx)),
            .len = @as(u16, @truncate(text.len)),
        };
    }

    pub fn slice(this: BabyString, container: []const u8) []const u8 {
        if (this.offset + this.len > container.len) return "";
        return container[this.offset..][0..this.len];
    }
};

/// Message data - text + optional location
pub const Data = struct {
    text: []const u8,
    location: ?Location = null,

    pub fn memoryCost(this: *const Data) usize {
        var cost: usize = this.text.len;
        if (this.location) |*loc| {
            cost += loc.memoryCost();
        }
        return cost;
    }

    pub fn clone(this: Data, allocator: std.mem.Allocator) !Data {
        return Data{
            .text = if (this.text.len > 0) try allocator.dupe(u8, this.text) else "",
            .location = if (this.location) |l| try l.clone(allocator) else null,
        };
    }

    pub fn deinit(d: *Data, allocator: std.mem.Allocator) void {
        if (d.location) |*loc| {
            if (loc.line_text) |t| allocator.free(t);
            allocator.free(loc.file);
        }
        if (d.text.len > 0) allocator.free(d.text);
    }
};

// ============ MESSAGES ============

/// Complete message with kind, data, and optional notes
pub const Msg = struct {
    kind: Kind = Kind.err,
    data: Data,
    metadata: Metadata = .build,
    notes: []Data = &.{},

    pub const Metadata = union(enum) {
        build,
        resolve: Resolve,

        pub const Resolve = struct {
            specifier: BabyString,
            err: anyerror = error.ModuleNotFound,
        };
    };

    pub fn memoryCost(this: *const Msg) usize {
        var cost: usize = this.data.memoryCost();
        for (this.notes) |*note| {
            cost += note.memoryCost();
        }
        return cost;
    }

    pub fn clone(this: *const Msg, allocator: std.mem.Allocator) !Msg {
        var notes = try allocator.alloc(Data, this.notes.len);
        for (this.notes, 0..) |note, i| {
            notes[i] = try note.clone(allocator);
        }
        return Msg{
            .kind = this.kind,
            .data = try this.data.clone(allocator),
            .metadata = this.metadata,
            .notes = notes,
        };
    }

    pub fn deinit(msg: *Msg, allocator: std.mem.Allocator) void {
        msg.data.deinit(allocator);
        for (msg.notes) |*note| {
            note.deinit(allocator);
        }
        if (msg.notes.len > 0) allocator.free(msg.notes);
        msg.notes = &.{};
    }

    /// Format message for display
    pub fn format(msg: *const Msg, writer: anytype) !void {
        // Kind prefix
        try writer.print("{s}: ", .{msg.kind.string()});

        // Main text
        try writer.print("{s}", .{msg.data.text});

        // Location info
        if (msg.data.location) |loc| {
            if (loc.file.len > 0) {
                try writer.print("\n  at {s}", .{loc.file});
                if (loc.line > 0) {
                    try writer.print(":{d}", .{loc.line});
                    if (loc.column >= 0) {
                        try writer.print(":{d}", .{loc.column});
                    }
                }
            }

            // Show line text with caret
            if (loc.line_text) |line_text| {
                try writer.print("\n  {d} | {s}", .{ loc.line, line_text });
                if (loc.column > 0) {
                    try writer.writeAll("\n      ");
                    try writer.writeByteNTimes(' ', @as(usize, @intCast(loc.column)));
                    try writer.writeAll("^");
                }
            }
        }

        // Notes
        for (msg.notes) |note| {
            try writer.print("\n  note: {s}", .{note.text});
        }
    }
};

// ============ LOG COLLECTION ============

/// Collection of messages with counts
pub const Log = struct {
    warnings: u32 = 0,
    errors: u32 = 0,
    msgs: std.ArrayList(Msg),
    level: Level = if (Environment.isDebug) Level.debug else Level.warn,

    pub const Level = enum(i8) {
        verbose = 0,
        debug = 1,
        info = 2,
        warn = 3,
        err = 4,

        pub fn atLeast(this: Level, other: Level) bool {
            return @intFromEnum(this) <= @intFromEnum(other);
        }

        pub const labels = std.EnumArray(Level, []const u8).init(.{
            .verbose = "verbose",
            .debug = "debug",
            .info = "info",
            .warn = "warn",
            .err = "error",
        });
    };

    pub var default_level: Level = Level.warn;

    pub fn init(allocator: std.mem.Allocator) Log {
        return Log{
            .msgs = std.ArrayList(Msg).init(allocator),
            .level = default_level,
        };
    }

    pub fn deinit(log: *Log) void {
        for (log.msgs.items) |*msg| {
            msg.deinit(log.msgs.allocator);
        }
        log.msgs.deinit();
    }

    pub fn reset(this: *Log) void {
        for (this.msgs.items) |*msg| {
            msg.deinit(this.msgs.allocator);
        }
        this.msgs.clearRetainingCapacity();
        this.warnings = 0;
        this.errors = 0;
    }

    pub inline fn hasErrors(this: *const Log) bool {
        return this.errors > 0;
    }

    pub inline fn hasAny(this: *const Log) bool {
        return (this.warnings + this.errors) > 0;
    }

    pub fn memoryCost(this: *const Log) usize {
        var cost: usize = 0;
        for (this.msgs.items) |*msg| {
            cost += msg.memoryCost();
        }
        return cost;
    }

    // ============ ADD MESSAGES ============

    fn addMsg(log: *Log, msg: Msg) !void {
        try log.msgs.append(msg);
    }

    /// Add error message
    pub fn addError(log: *Log, text: []const u8) !void {
        @branchHint(.cold);
        log.errors += 1;
        try log.addMsg(.{
            .kind = .err,
            .data = .{ .text = text },
        });
    }

    /// Add error with location
    pub fn addErrorAt(log: *Log, text: []const u8, loc: Location) !void {
        @branchHint(.cold);
        log.errors += 1;
        try log.addMsg(.{
            .kind = .err,
            .data = .{ .text = text, .location = loc },
        });
    }

    /// Add formatted error
    pub fn addErrorFmt(
        log: *Log,
        allocator: std.mem.Allocator,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        @branchHint(.cold);
        const text = try std.fmt.allocPrint(allocator, fmt, args);
        try log.addError(text);
    }

    /// Add warning message
    pub fn addWarning(log: *Log, text: []const u8) !void {
        @branchHint(.cold);
        if (!Kind.shouldPrint(.warn, log.level)) return;
        log.warnings += 1;
        try log.addMsg(.{
            .kind = .warn,
            .data = .{ .text = text },
        });
    }

    /// Add warning with location
    pub fn addWarningAt(log: *Log, text: []const u8, loc: Location) !void {
        @branchHint(.cold);
        if (!Kind.shouldPrint(.warn, log.level)) return;
        log.warnings += 1;
        try log.addMsg(.{
            .kind = .warn,
            .data = .{ .text = text, .location = loc },
        });
    }

    /// Add debug message (only in debug builds or verbose mode)
    pub fn addDebug(log: *Log, text: []const u8) !void {
        if (!Kind.shouldPrint(.debug, log.level)) return;
        try log.addMsg(.{
            .kind = .debug,
            .data = .{ .text = text },
        });
    }

    /// Add note (attached to previous error/warning)
    pub fn addNote(log: *Log, text: []const u8) !void {
        try log.addMsg(.{
            .kind = .note,
            .data = .{ .text = text },
        });
    }

    // ============ PRINT ============

    /// Print all messages
    pub fn print(log: *Log) void {
        for (log.msgs.items) |*msg| {
            var buf: [4096]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            msg.format(fbs.writer()) catch continue;
            Output.err("{s}\n", .{fbs.getWritten()});
        }
    }

    /// Print summary
    pub fn printSummary(log: *Log) void {
        if (log.errors > 0 or log.warnings > 0) {
            Output.err("\n{d} error(s), {d} warning(s)\n", .{ log.errors, log.warnings });
        }
    }
};

// ============ SCOPED LOGGING ============

/// Scoped logger for subsystems
/// Enable with ZID_DEBUG_<SCOPE>=1
pub fn ScopedLog(comptime scope: []const u8) type {
    return struct {
        const scope_name = scope;
        var enabled: ?bool = null;

        fn isEnabled() bool {
            if (enabled) |e| return e;
            // Check environment variable
            const env_name = "ZID_DEBUG_" ++ scope;
            enabled = if (std.posix.getenv(env_name)) |v|
                std.mem.eql(u8, v, "1") or std.mem.eql(u8, v, "true")
            else
                Environment.isDebug;
            return enabled.?;
        }

        pub fn debug(comptime fmt: []const u8, args: anytype) void {
            if (!isEnabled()) return;
            Output.debug("[" ++ scope ++ "] " ++ fmt ++ "\n", args);
        }

        pub fn info(comptime fmt: []const u8, args: anytype) void {
            Output.print("[" ++ scope ++ "] " ++ fmt ++ "\n", args);
        }

        pub fn warn(comptime fmt: []const u8, args: anytype) void {
            Output.warn("[" ++ scope ++ "] " ++ fmt ++ "\n", args);
        }

        pub fn err(comptime fmt: []const u8, args: anytype) void {
            Output.err("[" ++ scope ++ "] " ++ fmt ++ "\n", args);
        }
    };
}

// ============ TESTS ============

test "Log basic usage" {
    const allocator = std.testing.allocator;

    var log = Log.init(allocator);
    defer log.deinit();

    try log.addError("test error");
    try log.addWarning("test warning");

    try std.testing.expectEqual(@as(u32, 1), log.errors);
    try std.testing.expectEqual(@as(u32, 1), log.warnings);
    try std.testing.expectEqual(@as(usize, 2), log.msgs.items.len);
}

test "Location creation" {
    const loc = Location.init("test.zig", 10, 5);
    try std.testing.expectEqualStrings("test.zig", loc.file);
    try std.testing.expectEqual(@as(i32, 10), loc.line);
    try std.testing.expectEqual(@as(i32, 5), loc.column);
}

test "BabyString" {
    const parent = "hello world error";
    const baby = BabyString.in(parent, "world");
    try std.testing.expectEqualStrings("world", baby.slice(parent));
}

test "Range" {
    const source = "const x = 42;";
    const range = Range{ .loc = .{ .start = 6 }, .len = 1 };
    try std.testing.expectEqualStrings("x", range.in(source));
}

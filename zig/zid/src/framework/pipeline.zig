const std = @import("std");

/// Pipeline
/// A chain of transformation steps that process source code.
///
/// Example:
/// ```zig
/// const pipeline = Pipeline{
///     .input = "src/*.lua",
///     .output = "dist/",
///     .steps = &.{ lex, parse, emit },
/// };
/// ```
pub const Pipeline = struct {
    /// Input glob pattern
    input: []const u8 = "src/*",

    /// Output directory
    output: []const u8 = "dist/",

    /// Transformation steps
    steps: []const Step = &.{},

    /// Watch mode - rebuild on changes
    watch: bool = false,

    /// Parallel processing
    parallel: bool = false,

    /// Internal state
    alloc: std.mem.Allocator = undefined,
    cache: ?*Cache = null,

    pub fn init(alloc: std.mem.Allocator) Pipeline {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Pipeline) void {
        if (self.cache) |c| {
            c.deinit();
        }
    }

    /// Run the pipeline on all matching files
    pub fn run(self: *Pipeline) !void {
        const files = try self.findInputFiles();
        defer self.alloc.free(files);

        for (files) |file| {
            try self.processFile(file);
        }
    }

    /// Run the pipeline on a single file
    pub fn runFile(self: *Pipeline, path: []const u8) ![]const u8 {
        return self.processFile(path);
    }

    /// Add a transformation step
    pub fn addStep(self: *Pipeline, step: Step) !void {
        _ = self;
        _ = step;
        // TODO: Dynamic step addition
    }

    fn findInputFiles(self: *Pipeline) ![]const []const u8 {
        var files = std.ArrayList([]const u8).init(self.alloc);

        // Simple glob matching
        var dir = std.fs.cwd().openDir("src", .{ .iterate = true }) catch {
            return files.toOwnedSlice();
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                const path = try std.fmt.allocPrint(self.alloc, "src/{s}", .{entry.name});
                try files.append(path);
            }
        }

        return files.toOwnedSlice();
    }

    fn processFile(self: *Pipeline, path: []const u8) ![]const u8 {
        // Check cache
        if (self.cache) |cache| {
            if (try cache.get(path)) |cached| {
                return cached;
            }
        }

        // Read input
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var data: []const u8 = try file.readToEndAlloc(self.alloc, 10 * 1024 * 1024);

        // Run through steps
        for (self.steps) |step| {
            data = try step.run(data);
        }

        // Cache result
        if (self.cache) |cache| {
            try cache.put(path, data);
        }

        // Write output
        try self.writeOutput(path, data);

        return data;
    }

    fn writeOutput(self: *Pipeline, input_path: []const u8, data: []const u8) !void {
        // Ensure output directory exists
        std.fs.cwd().makePath(self.output) catch {};

        // Get output path
        const basename = std.fs.path.basename(input_path);
        const output_path = try std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ self.output, basename });
        defer self.alloc.free(output_path);

        // Write
        const file = try std.fs.cwd().createFile(output_path, .{});
        defer file.close();
        try file.writeAll(data);
    }
};

/// A single transformation step
pub const Step = struct {
    name: []const u8 = "unnamed",
    func: *const fn ([]const u8) anyerror![]const u8,

    pub fn run(self: Step, input: []const u8) ![]const u8 {
        return self.func(input);
    }
};

/// Simple cache for pipeline outputs
pub const Cache = struct {
    alloc: std.mem.Allocator,
    entries: std.StringHashMap(Entry),

    const Entry = struct {
        data: []const u8,
        mtime: i128,
    };

    pub fn init(alloc: std.mem.Allocator) Cache {
        return .{
            .alloc = alloc,
            .entries = std.StringHashMap(Entry).init(alloc),
        };
    }

    pub fn deinit(self: *Cache) void {
        self.entries.deinit();
    }

    pub fn get(self: *Cache, path: []const u8) !?[]const u8 {
        const entry = self.entries.get(path) orelse return null;

        // Check if file changed
        const stat = try std.fs.cwd().statFile(path);
        if (stat.mtime != entry.mtime) {
            return null; // Cache invalidated
        }

        return entry.data;
    }

    pub fn put(self: *Cache, path: []const u8, data: []const u8) !void {
        const stat = try std.fs.cwd().statFile(path);
        try self.entries.put(path, .{
            .data = data,
            .mtime = stat.mtime,
        });
    }
};

// ============ Helper Functions ============

/// Create a step from a function
pub fn step(comptime name: []const u8, comptime func: anytype) Step {
    return .{
        .name = name,
        .func = func,
    };
}

/// Chain multiple steps
pub fn chain(steps: []const Step) Step {
    return .{
        .name = "chain",
        .func = struct {
            fn run(input: []const u8) ![]const u8 {
                var data = input;
                for (steps) |s| {
                    data = try s.run(data);
                }
                return data;
            }
        }.run,
    };
}

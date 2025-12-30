//! Cache - File and content caching
//!
//! Pattern from Bun's cache.zig.
//! Provides efficient caching for file contents, parsed data, and build artifacts.

const std = @import("std");
const Environment = @import("../env.zig");
const Output = @import("../output.zig");
const bufs = @import("buffers.zig").bufs;

// ============ CACHE SET ============

/// Combined cache for all subsystems
pub const Set = struct {
    files: FileCache,
    content: ContentCache,
    path: PathCache,

    pub fn init(allocator: std.mem.Allocator) Set {
        return Set{
            .files = FileCache.init(allocator),
            .content = ContentCache.init(allocator),
            .path = PathCache.init(allocator),
        };
    }

    pub fn deinit(self: *Set) void {
        self.files.deinit();
        self.content.deinit();
        self.path.deinit();
    }

    pub fn clear(self: *Set) void {
        self.files.clear();
        self.content.clear();
        self.path.clear();
    }

    /// Get memory usage
    pub fn memoryCost(self: *const Set) usize {
        return self.files.memoryCost() + self.content.memoryCost() + self.path.memoryCost();
    }
};

// ============ FILE CACHE ============

/// Cache for file contents
pub const FileCache = struct {
    entries: std.StringHashMap(Entry),
    shared_buffer: std.ArrayList(u8),

    pub const Entry = struct {
        contents: []const u8,
        mtime: i128 = 0,
        size: u64 = 0,
        hash: u64 = 0,
        owned: bool = true,

        pub fn deinit(entry: *Entry, allocator: std.mem.Allocator) void {
            if (entry.owned and entry.contents.len > 0) {
                allocator.free(entry.contents);
                entry.contents = "";
            }
        }

        pub fn isStale(entry: *const Entry, current_mtime: i128) bool {
            return entry.mtime != current_mtime;
        }
    };

    pub fn init(allocator: std.mem.Allocator) FileCache {
        return FileCache{
            .entries = std.StringHashMap(Entry).init(allocator),
            .shared_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *FileCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.entries.allocator);
        }
        self.entries.deinit();
        self.shared_buffer.deinit();
    }

    pub fn clear(self: *FileCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.entries.allocator);
        }
        self.entries.clearRetainingCapacity();
        self.shared_buffer.clearRetainingCapacity();
    }

    /// Get cached file contents
    pub fn get(self: *FileCache, path: []const u8) ?*Entry {
        return self.entries.getPtr(path);
    }

    /// Put file contents in cache
    pub fn put(self: *FileCache, path: []const u8, contents: []const u8, mtime: i128) !void {
        const duped_path = try self.entries.allocator.dupe(u8, path);
        const duped_contents = try self.entries.allocator.dupe(u8, contents);

        try self.entries.put(duped_path, Entry{
            .contents = duped_contents,
            .mtime = mtime,
            .size = contents.len,
            .hash = std.hash.Wyhash.hash(0, contents),
        });
    }

    /// Read file, using cache if available
    pub fn readFile(self: *FileCache, path: []const u8) !Entry {
        // Check cache first
        if (self.get(path)) |entry| {
            return entry.*;
        }

        // Read from disk
        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            return err;
        };
        defer file.close();

        const stat = try file.stat();
        const contents = try file.readToEndAlloc(self.entries.allocator, std.math.maxInt(usize));

        const entry = Entry{
            .contents = contents,
            .mtime = stat.mtime,
            .size = stat.size,
            .hash = std.hash.Wyhash.hash(0, contents),
        };

        // Cache it
        const duped_path = try self.entries.allocator.dupe(u8, path);
        try self.entries.put(duped_path, entry);

        return entry;
    }

    /// Get shared buffer for temporary file reads
    pub fn sharedBuffer(self: *FileCache) *std.ArrayList(u8) {
        self.shared_buffer.clearRetainingCapacity();
        return &self.shared_buffer;
    }

    pub fn memoryCost(self: *const FileCache) usize {
        var cost: usize = 0;
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            cost += entry.key_ptr.len;
            cost += entry.value_ptr.contents.len;
        }
        cost += self.shared_buffer.capacity;
        return cost;
    }
};

// ============ CONTENT CACHE ============

/// Content-addressed cache (by hash)
pub const ContentCache = struct {
    entries: std.AutoHashMap(u64, Entry),

    pub const Entry = struct {
        data: []const u8,
        ref_count: u32 = 1,

        pub fn retain(self: *Entry) void {
            self.ref_count += 1;
        }

        pub fn release(self: *Entry, allocator: std.mem.Allocator) bool {
            self.ref_count -= 1;
            if (self.ref_count == 0) {
                if (self.data.len > 0) {
                    allocator.free(self.data);
                }
                return true; // Entry can be removed
            }
            return false;
        }
    };

    pub fn init(allocator: std.mem.Allocator) ContentCache {
        return ContentCache{
            .entries = std.AutoHashMap(u64, Entry).init(allocator),
        };
    }

    pub fn deinit(self: *ContentCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.data.len > 0) {
                self.entries.allocator.free(entry.value_ptr.data);
            }
        }
        self.entries.deinit();
    }

    pub fn clear(self: *ContentCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.data.len > 0) {
                self.entries.allocator.free(entry.value_ptr.data);
            }
        }
        self.entries.clearRetainingCapacity();
    }

    /// Compute hash for content
    pub fn hash(content: []const u8) u64 {
        return std.hash.Wyhash.hash(0, content);
    }

    /// Get by hash
    pub fn get(self: *ContentCache, content_hash: u64) ?*Entry {
        return self.entries.getPtr(content_hash);
    }

    /// Put content with automatic hash
    pub fn put(self: *ContentCache, content: []const u8) !u64 {
        const h = hash(content);
        if (self.entries.getPtr(h)) |entry| {
            entry.retain();
            return h;
        }

        const duped = try self.entries.allocator.dupe(u8, content);
        try self.entries.put(h, Entry{ .data = duped });
        return h;
    }

    /// Release reference
    pub fn release(self: *ContentCache, content_hash: u64) void {
        if (self.entries.getPtr(content_hash)) |entry| {
            if (entry.release(self.entries.allocator)) {
                _ = self.entries.remove(content_hash);
            }
        }
    }

    pub fn memoryCost(self: *const ContentCache) usize {
        var cost: usize = 0;
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            cost += entry.value_ptr.data.len;
        }
        return cost;
    }
};

// ============ PATH CACHE ============

/// Cache for resolved paths
pub const PathCache = struct {
    entries: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) PathCache {
        return PathCache{
            .entries = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PathCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.entries.allocator.free(entry.key_ptr.*);
            self.entries.allocator.free(entry.value_ptr.*);
        }
        self.entries.deinit();
    }

    pub fn clear(self: *PathCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.entries.allocator.free(entry.key_ptr.*);
            self.entries.allocator.free(entry.value_ptr.*);
        }
        self.entries.clearRetainingCapacity();
    }

    /// Get resolved path
    pub fn get(self: *PathCache, key: []const u8) ?[]const u8 {
        return self.entries.get(key);
    }

    /// Cache resolved path
    pub fn put(self: *PathCache, key: []const u8, resolved: []const u8) !void {
        const duped_key = try self.entries.allocator.dupe(u8, key);
        const duped_val = try self.entries.allocator.dupe(u8, resolved);
        try self.entries.put(duped_key, duped_val);
    }

    pub fn memoryCost(self: *const PathCache) usize {
        var cost: usize = 0;
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            cost += entry.key_ptr.len;
            cost += entry.value_ptr.len;
        }
        return cost;
    }
};

// ============ LRU CACHE ============

/// LRU cache with fixed capacity
pub fn LruCache(comptime K: type, comptime V: type, comptime capacity: usize) type {
    return struct {
        entries: [capacity]Entry = undefined,
        used: usize = 0,
        head: u32 = 0, // Most recently used
        tail: u32 = 0, // Least recently used

        const Self = @This();

        const Entry = struct {
            key: K,
            value: V,
            prev: u32,
            next: u32,
            valid: bool = false,
        };

        pub fn get(self: *Self, key: K) ?*V {
            for (&self.entries, 0..) |*entry, i| {
                if (entry.valid and std.meta.eql(entry.key, key)) {
                    self.moveToFront(@intCast(i));
                    return &entry.value;
                }
            }
            return null;
        }

        pub fn put(self: *Self, key: K, value: V) void {
            // Check if already exists
            for (&self.entries, 0..) |*entry, i| {
                if (entry.valid and std.meta.eql(entry.key, key)) {
                    entry.value = value;
                    self.moveToFront(@intCast(i));
                    return;
                }
            }

            // Find slot (LRU eviction if full)
            const slot: u32 = if (self.used < capacity) blk: {
                const s: u32 = @intCast(self.used);
                self.used += 1;
                break :blk s;
            } else self.tail;

            self.entries[slot] = Entry{
                .key = key,
                .value = value,
                .prev = 0,
                .next = 0,
                .valid = true,
            };
            self.moveToFront(slot);
        }

        fn moveToFront(self: *Self, index: u32) void {
            if (index == self.head) return;

            const entry = &self.entries[index];

            // Remove from current position
            if (entry.prev != index) {
                self.entries[entry.prev].next = entry.next;
            }
            if (entry.next != index) {
                self.entries[entry.next].prev = entry.prev;
            }
            if (index == self.tail) {
                self.tail = entry.prev;
            }

            // Move to front
            entry.next = self.head;
            entry.prev = index;
            self.entries[self.head].prev = index;
            self.head = index;
        }

        pub fn count(self: *const Self) usize {
            return self.used;
        }
    };
}

// ============ DISK CACHE ============

/// Persistent disk cache for build artifacts
pub const DiskCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) DiskCache {
        return DiskCache{
            .allocator = allocator,
            .cache_dir = cache_dir,
        };
    }

    /// Get cache path for a key
    pub fn getCachePath(self: *DiskCache, key: []const u8) ![]const u8 {
        const hash_val = std.hash.Wyhash.hash(0, key);
        return std.fmt.allocPrint(
            self.allocator,
            "{s}/{x:0>16}",
            .{ self.cache_dir, hash_val },
        );
    }

    /// Check if cache entry exists
    pub fn exists(self: *DiskCache, key: []const u8) bool {
        const path = self.getCachePath(key) catch return false;
        defer self.allocator.free(path);
        std.fs.accessAbsolute(path, .{}) catch return false;
        return true;
    }

    /// Read from disk cache
    pub fn read(self: *DiskCache, key: []const u8) ![]const u8 {
        const path = try self.getCachePath(key);
        defer self.allocator.free(path);

        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();

        return try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
    }

    /// Write to disk cache
    pub fn write(self: *DiskCache, key: []const u8, data: []const u8) !void {
        const path = try self.getCachePath(key);
        defer self.allocator.free(path);

        // Ensure cache directory exists
        std.fs.makeDirAbsolute(self.cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        try file.writeAll(data);
    }

    /// Delete cache entry
    pub fn delete(self: *DiskCache, key: []const u8) !void {
        const path = try self.getCachePath(key);
        defer self.allocator.free(path);
        std.fs.deleteFileAbsolute(path) catch {};
    }
};

// ============ TESTS ============

test "FileCache basic" {
    const allocator = std.testing.allocator;
    var cache = FileCache.init(allocator);
    defer cache.deinit();

    try cache.put("/test/file.txt", "hello world", 12345);
    const entry = cache.get("/test/file.txt");
    try std.testing.expect(entry != null);
    try std.testing.expectEqualStrings("hello world", entry.?.contents);
    try std.testing.expectEqual(@as(i128, 12345), entry.?.mtime);
}

test "ContentCache dedup" {
    const allocator = std.testing.allocator;
    var cache = ContentCache.init(allocator);
    defer cache.deinit();

    const h1 = try cache.put("same content");
    const h2 = try cache.put("same content");
    try std.testing.expectEqual(h1, h2);

    // Check ref count increased
    const entry = cache.get(h1);
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(@as(u32, 2), entry.?.ref_count);
}

test "LruCache eviction" {
    var cache = LruCache(u32, []const u8, 3){};

    cache.put(1, "one");
    cache.put(2, "two");
    cache.put(3, "three");
    cache.put(4, "four"); // Evicts 1

    try std.testing.expect(cache.get(1) == null);
    try std.testing.expect(cache.get(2) != null);
    try std.testing.expect(cache.get(4) != null);
}

test "PathCache" {
    const allocator = std.testing.allocator;
    var cache = PathCache.init(allocator);
    defer cache.deinit();

    try cache.put("./relative", "/absolute/path");
    const resolved = cache.get("./relative");
    try std.testing.expect(resolved != null);
    try std.testing.expectEqualStrings("/absolute/path", resolved.?);
}

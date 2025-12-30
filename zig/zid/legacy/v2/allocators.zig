//! Allocators - Memory allocation strategies
//!
//! Hierarchy:
//!   default_allocator  - General purpose (c_allocator or page_allocator)
//!   debug_allocator    - With leak detection (debug builds only)
//!   ArenaAllocator     - For temporary/scoped allocations
//!   ScopedAllocator    - Arena with automatic cleanup

const std = @import("std");
const builtin = @import("builtin");
const Environment = @import("env.zig");

// ============ DEFAULT ALLOCATOR ============

/// Default allocator for general use
/// Uses c_allocator when available, otherwise page_allocator
pub const default_allocator: std.mem.Allocator = blk: {
    // In release builds, prefer c_allocator for better performance
    if (!Environment.isDebug) {
        break :blk std.heap.c_allocator;
    }
    // In debug, use page_allocator for better debugging
    break :blk std.heap.page_allocator;
};

// ============ DEBUG ALLOCATOR ============

/// Debug allocator with leak detection
/// Only available in debug builds
pub const debug_allocator: std.mem.Allocator = if (Environment.isDebug)
    std.heap.GeneralPurposeAllocator(.{
        .stack_trace_frames = 10,
        .enable_memory_limit = true,
        .thread_safe = true,
    }){}.allocator()
else
    default_allocator;

// ============ ARENA ALLOCATOR ============

/// Create an arena allocator backed by the default allocator
pub fn arena() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(default_allocator);
}

// ============ SCOPED ALLOCATOR ============

/// Scoped allocator that automatically frees on scope exit
/// Usage:
///   var scope = ScopedAllocator.init();
///   defer scope.deinit();
///   const alloc = scope.allocator();
pub const ScopedAllocator = struct {
    arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init() Self {
        return .{
            .arena = std.heap.ArenaAllocator.init(default_allocator),
        };
    }

    pub fn initWith(backing: std.mem.Allocator) Self {
        return .{
            .arena = std.heap.ArenaAllocator.init(backing),
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Reset the arena, freeing all allocations but keeping capacity
    pub fn reset(self: *Self) void {
        self.arena.reset(.retain_capacity);
    }

    /// Reset and free all memory
    pub fn resetAndFree(self: *Self) void {
        self.arena.reset(.free_all);
    }
};

// ============ FIXED BUFFER ALLOCATOR ============

/// Create a fixed buffer allocator from a slice
pub fn fixedBuffer(buffer: []u8) std.heap.FixedBufferAllocator {
    return std.heap.FixedBufferAllocator.init(buffer);
}

/// Create a fixed buffer allocator from a threadlocal buffer
pub fn threadLocalBuffer(comptime size: usize) std.heap.FixedBufferAllocator {
    const S = struct {
        threadlocal var buffer: [size]u8 = undefined;
    };
    return std.heap.FixedBufferAllocator.init(&S.buffer);
}

// ============ BOUNDED ALLOCATOR ============

/// Allocator with a memory limit
pub const BoundedAllocator = struct {
    backing: std.mem.Allocator,
    max_bytes: usize,
    allocated: usize = 0,

    const Self = @This();

    pub fn init(backing: std.mem.Allocator, max_bytes: usize) Self {
        return .{
            .backing = backing,
            .max_bytes = max_bytes,
        };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.allocated + len > self.max_bytes) {
            return null; // Limit exceeded
        }

        if (self.backing.rawAlloc(len, ptr_align, ret_addr)) |ptr| {
            self.allocated += len;
            return ptr;
        }
        return null;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (new_len > buf.len) {
            const delta = new_len - buf.len;
            if (self.allocated + delta > self.max_bytes) {
                return false;
            }
        }

        if (self.backing.rawResize(buf, buf_align, new_len, ret_addr)) {
            if (new_len > buf.len) {
                self.allocated += new_len - buf.len;
            } else {
                self.allocated -= buf.len - new_len;
            }
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.allocated -= buf.len;
        self.backing.rawFree(buf, buf_align, ret_addr);
    }

    pub fn bytesAllocated(self: Self) usize {
        return self.allocated;
    }

    pub fn bytesRemaining(self: Self) usize {
        return self.max_bytes - self.allocated;
    }
};

// ============ UTILITY FUNCTIONS ============

/// Duplicate a slice using the given allocator
pub fn dupe(alloc: std.mem.Allocator, comptime T: type, slice: []const T) ![]T {
    return alloc.dupe(T, slice);
}

/// Duplicate a string using the given allocator
pub fn dupeZ(alloc: std.mem.Allocator, s: []const u8) ![:0]u8 {
    return alloc.dupeZ(u8, s);
}

/// Free a slice allocated with dupe
pub fn free(alloc: std.mem.Allocator, slice: anytype) void {
    alloc.free(slice);
}

// ============ TESTS ============

test "ScopedAllocator" {
    var scope = ScopedAllocator.init();
    defer scope.deinit();

    const alloc = scope.allocator();
    const data = try alloc.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), data.len);
}

test "BoundedAllocator" {
    var bounded = BoundedAllocator.init(std.heap.page_allocator, 1024);
    const alloc = bounded.allocator();

    // Should succeed
    const data = try alloc.alloc(u8, 512);
    try std.testing.expectEqual(@as(usize, 512), bounded.bytesAllocated());

    // Should fail (exceeds limit)
    const result = alloc.alloc(u8, 1024);
    try std.testing.expectEqual(@as(?[]u8, null), result);

    alloc.free(data);
    try std.testing.expectEqual(@as(usize, 0), bounded.bytesAllocated());
}

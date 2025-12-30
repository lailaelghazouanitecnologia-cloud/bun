//! Pool - Object pools with stable pointers
//!
//! Pattern from Bun's HiveArray.
//! Provides stable pointers (no reallocation) with efficient reuse via bitset.

const std = @import("std");

/// HivePool - Fixed-capacity pool with stable pointers
/// Objects can be borrowed and returned without moving.
pub fn HivePool(comptime T: type, comptime capacity: u16) type {
    return struct {
        buffer: [capacity]T = undefined,
        used: std.bit_set.IntegerBitSet(capacity) = .{},

        const Self = @This();

        /// Get a free slot
        pub fn get(self: *Self) ?*T {
            const index = self.used.findFirstUnset() orelse return null;
            self.used.set(index);
            return &self.buffer[index];
        }

        /// Return a slot
        pub fn put(self: *Self, ptr: *T) void {
            const index = self.indexOf(ptr) orelse return;
            std.debug.assert(self.used.isSet(index));
            ptr.* = undefined;
            self.used.unset(index);
        }

        /// Get index of pointer
        pub fn indexOf(self: *Self, ptr: *T) ?usize {
            const base = @intFromPtr(&self.buffer[0]);
            const addr = @intFromPtr(ptr);
            if (addr < base) return null;
            const offset = addr - base;
            if (offset % @sizeOf(T) != 0) return null;
            const index = offset / @sizeOf(T);
            if (index >= capacity) return null;
            return index;
        }

        /// Check if slot is used
        pub fn isUsed(self: Self, index: usize) bool {
            return self.used.isSet(index);
        }

        /// Count used slots
        pub fn count(self: Self) usize {
            return self.used.count();
        }

        /// Count free slots
        pub fn free(self: Self) usize {
            return capacity - self.count();
        }

        /// Iterate over used items
        pub fn usedIterator(self: *Self) UsedIterator {
            return .{ .pool = self, .index = 0 };
        }

        pub const UsedIterator = struct {
            pool: *Self,
            index: usize,

            pub fn next(self: *UsedIterator) ?*T {
                while (self.index < capacity) : (self.index += 1) {
                    if (self.pool.used.isSet(self.index)) {
                        const ptr = &self.pool.buffer[self.index];
                        self.index += 1;
                        return ptr;
                    }
                }
                return null;
            }
        };
    };
}

/// Arena Pool - Grows dynamically, still stable pointers
pub fn ArenaPool(comptime T: type) type {
    return struct {
        chunks: std.ArrayList(*Chunk),
        free_list: ?*T = null,

        const CHUNK_SIZE = 64;

        const Chunk = struct {
            items: [CHUNK_SIZE]T = undefined,
        };

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{ .chunks = std.ArrayList(*Chunk).init(alloc) };
        }

        pub fn deinit(self: *Self) void {
            for (self.chunks.items) |chunk| {
                self.chunks.allocator.destroy(chunk);
            }
            self.chunks.deinit();
        }

        pub fn get(self: *Self) !*T {
            // Try free list first
            if (self.free_list) |free| {
                self.free_list = @ptrCast(@alignCast(free));
                return free;
            }

            // Need new chunk?
            if (self.chunks.items.len == 0 or self.isChunkFull()) {
                const chunk = try self.chunks.allocator.create(Chunk);
                try self.chunks.append(chunk);
            }

            // Allocate from current chunk
            const chunk = self.chunks.items[self.chunks.items.len - 1];
            _ = chunk;
            return error.NotImplemented; // Simplified
        }

        pub fn put(self: *Self, ptr: *T) void {
            // Add to free list (intrusive linked list)
            const next: *?*T = @ptrCast(@alignCast(ptr));
            next.* = self.free_list;
            self.free_list = ptr;
        }

        fn isChunkFull(self: Self) bool {
            _ = self;
            return true; // Simplified
        }
    };
}

/// Handle - Typed index into pool (safer than raw pointers)
/// T is the element type for documentation, not used in the handle itself
pub fn Handle(comptime _: type) type {
    return packed struct {
        index: u16,
        generation: u16, // Detect use-after-free

        const Self = @This();
        pub const invalid = Self{ .index = 0xFFFF, .generation = 0 };

        pub fn isValid(self: Self) bool {
            return self.index != 0xFFFF;
        }
    };
}

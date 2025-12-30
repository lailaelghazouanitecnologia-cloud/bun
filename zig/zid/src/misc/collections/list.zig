//! List - Memory-efficient list variants
//!
//! Pattern from Bun's BabyList - uses u32 instead of usize to save memory.
//! Critical for AST nodes where millions of lists may exist.

const std = @import("std");

/// SmallList - List with u32 length/capacity (max 4B elements)
/// Saves 8 bytes per list on 64-bit systems.
pub fn SmallList(comptime T: type) type {
    return struct {
        ptr: [*]T = undefined,
        len: u32 = 0,
        cap: u32 = 0,

        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            if (self.cap > 0) {
                alloc.free(self.ptr[0..self.cap]);
            }
            self.* = .{};
        }

        pub fn append(self: *Self, alloc: std.mem.Allocator, item: T) !void {
            if (self.len >= self.cap) {
                try self.grow(alloc);
            }
            self.ptr[self.len] = item;
            self.len += 1;
        }

        pub fn items(self: Self) []T {
            if (self.len == 0) return &.{};
            return self.ptr[0..self.len];
        }

        pub fn get(self: Self, i: u32) ?T {
            if (i >= self.len) return null;
            return self.ptr[i];
        }

        pub fn set(self: *Self, i: u32, val: T) void {
            if (i < self.len) self.ptr[i] = val;
        }

        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.ptr[self.len];
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        fn grow(self: *Self, alloc: std.mem.Allocator) !void {
            const new_cap: u32 = if (self.cap == 0) 8 else self.cap * 2;
            const new_ptr = try alloc.alloc(T, new_cap);

            if (self.len > 0) {
                @memcpy(new_ptr[0..self.len], self.ptr[0..self.len]);
            }
            if (self.cap > 0) {
                alloc.free(self.ptr[0..self.cap]);
            }

            self.ptr = new_ptr.ptr;
            self.cap = new_cap;
        }
    };
}

/// TinyList - Stack-allocated small list with overflow to heap
pub fn TinyList(comptime T: type, comptime stack_size: usize) type {
    return struct {
        stack: [stack_size]T = undefined,
        heap: ?[]T = null,
        len: u32 = 0,

        const Self = @This();

        pub fn append(self: *Self, alloc: std.mem.Allocator, item: T) !void {
            if (self.len < stack_size) {
                self.stack[self.len] = item;
            } else {
                if (self.heap == null) {
                    self.heap = try alloc.alloc(T, stack_size * 2);
                    @memcpy(self.heap.?[0..stack_size], &self.stack);
                } else if (self.len >= self.heap.?.len) {
                    self.heap = try alloc.realloc(self.heap.?, self.heap.?.len * 2);
                }
                self.heap.?[self.len] = item;
            }
            self.len += 1;
        }

        pub fn items(self: *Self) []T {
            if (self.len == 0) return &.{};
            if (self.heap) |h| return h[0..self.len];
            return self.stack[0..self.len];
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            if (self.heap) |h| alloc.free(h);
            self.* = .{};
        }
    };
}

/// Span - Non-owning slice with u32 indices
pub fn Span(comptime T: type) type {
    return struct {
        ptr: [*]const T,
        start: u32,
        end: u32,

        const Self = @This();

        pub fn init(slice: []const T) Self {
            return .{
                .ptr = slice.ptr,
                .start = 0,
                .end = @intCast(slice.len),
            };
        }

        pub fn slice(self: Self) []const T {
            return self.ptr[self.start..self.end];
        }

        pub fn len(self: Self) u32 {
            return self.end - self.start;
        }

        pub fn get(self: Self, i: u32) ?T {
            if (i >= self.len()) return null;
            return self.ptr[self.start + i];
        }
    };
}

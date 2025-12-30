//! Buffers - Threadlocal buffer pool
//!
//! Pattern from Bun's resolver.zig bufs struct.
//! Provides pre-allocated threadlocal buffers to avoid allocations in hot paths.
//!
//! Usage:
//!   const path = bufs.path();
//!   const result = std.fmt.bufPrint(path, "{s}/{s}", .{dir, file});

const std = @import("std");

/// Buffer sizes
pub const PATH_SIZE = 4096;
pub const STRING_SIZE = 8192;
pub const SMALL_SIZE = 512;
pub const LARGE_SIZE = 65536;

/// Threadlocal buffer pool
pub const bufs = struct {
    // Path buffers
    pub threadlocal var path_buf: [PATH_SIZE]u8 = undefined;
    pub threadlocal var path_buf2: [PATH_SIZE]u8 = undefined;
    pub threadlocal var path_buf3: [PATH_SIZE]u8 = undefined;

    // String buffers
    pub threadlocal var string_buf: [STRING_SIZE]u8 = undefined;
    pub threadlocal var string_buf2: [STRING_SIZE]u8 = undefined;

    // Small buffers
    pub threadlocal var small_buf: [SMALL_SIZE]u8 = undefined;
    pub threadlocal var small_buf2: [SMALL_SIZE]u8 = undefined;

    // Large buffer for bulk operations
    pub threadlocal var large_buf: [LARGE_SIZE]u8 = undefined;

    // Token buffer (for lexer)
    pub threadlocal var token_buf: [4096]u8 = undefined;

    // === Accessors (inline for zero overhead) ===

    pub inline fn path() *[PATH_SIZE]u8 {
        return &path_buf;
    }

    pub inline fn path2() *[PATH_SIZE]u8 {
        return &path_buf2;
    }

    pub inline fn path3() *[PATH_SIZE]u8 {
        return &path_buf3;
    }

    pub inline fn string() *[STRING_SIZE]u8 {
        return &string_buf;
    }

    pub inline fn string2() *[STRING_SIZE]u8 {
        return &string_buf2;
    }

    pub inline fn small() *[SMALL_SIZE]u8 {
        return &small_buf;
    }

    pub inline fn large() *[LARGE_SIZE]u8 {
        return &large_buf;
    }

    pub inline fn token() *[4096]u8 {
        return &token_buf;
    }

    /// Get buffer by enum (for dynamic selection)
    pub fn get(comptime which: Buffer) []u8 {
        return switch (which) {
            .path => &path_buf,
            .path2 => &path_buf2,
            .path3 => &path_buf3,
            .string => &string_buf,
            .string2 => &string_buf2,
            .small => &small_buf,
            .small2 => &small_buf2,
            .large => &large_buf,
            .token => &token_buf,
        };
    }

    pub const Buffer = enum {
        path,
        path2,
        path3,
        string,
        string2,
        small,
        small2,
        large,
        token,
    };
};

/// Fixed buffer allocator from threadlocal buffer
pub fn fixedAlloc(comptime which: bufs.Buffer) std.heap.FixedBufferAllocator {
    return std.heap.FixedBufferAllocator.init(bufs.get(which));
}

/// Scoped buffer - resets on scope exit
pub const ScopedBuffer = struct {
    buf: []u8,
    pos: usize = 0,

    pub fn init(buf: []u8) ScopedBuffer {
        return .{ .buf = buf };
    }

    pub fn alloc(self: *ScopedBuffer, n: usize) ?[]u8 {
        if (self.pos + n > self.buf.len) return null;
        const slice = self.buf[self.pos .. self.pos + n];
        self.pos += n;
        return slice;
    }

    pub fn reset(self: *ScopedBuffer) void {
        self.pos = 0;
    }

    pub fn remaining(self: ScopedBuffer) usize {
        return self.buf.len - self.pos;
    }
};

/// Ring buffer for streaming
pub fn RingBuffer(comptime size: usize) type {
    return struct {
        data: [size]u8 = undefined,
        head: usize = 0,
        tail: usize = 0,

        const Self = @This();

        pub fn write(self: *Self, bytes: []const u8) usize {
            var written: usize = 0;
            for (bytes) |b| {
                const next = (self.head + 1) % size;
                if (next == self.tail) break; // full
                self.data[self.head] = b;
                self.head = next;
                written += 1;
            }
            return written;
        }

        pub fn read(self: *Self, out: []u8) usize {
            var i: usize = 0;
            while (i < out.len and self.tail != self.head) {
                out[i] = self.data[self.tail];
                self.tail = (self.tail + 1) % size;
                i += 1;
            }
            return i;
        }

        pub fn len(self: Self) usize {
            if (self.head >= self.tail) {
                return self.head - self.tail;
            }
            return size - self.tail + self.head;
        }

        pub fn isEmpty(self: Self) bool {
            return self.head == self.tail;
        }

        pub fn isFull(self: Self) bool {
            return (self.head + 1) % size == self.tail;
        }
    };
}

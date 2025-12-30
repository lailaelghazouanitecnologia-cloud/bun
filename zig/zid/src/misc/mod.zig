//! Misc - Miscellaneous utilities
//!
//! Core patterns and utilities used throughout Zid.
//! Follows Bun's organization: collections/, allocators/, threading/

const std = @import("std");

// ============ ERROR HANDLING ============

pub const maybe = @import("maybe.zig");
pub const Maybe = maybe.Maybe;
pub const Error = maybe.Error;

// ============ DISPATCH/VM ============

pub const dispatch = @import("dispatch.zig");
pub const Dispatch = dispatch.Dispatch;
pub const Instruction = dispatch.Instruction;

// ============ BUFFERS ============

pub const buffers = @import("buffers.zig");
pub const bufs = buffers.bufs;
pub const RingBuffer = buffers.RingBuffer;

// ============ STATE MACHINES ============

pub const state = @import("state.zig");
pub const StateMachine = state.StateMachine;
pub const Pipeline = state.Pipeline;
pub const PipelineState = state.PipelineState;

// ============ COLLECTIONS ============

pub const SmallList = @import("collections/list.zig").SmallList;
pub const TinyList = @import("collections/list.zig").TinyList;
pub const Span = @import("collections/list.zig").Span;

pub const HivePool = @import("collections/pool.zig").HivePool;
pub const ArenaPool = @import("collections/pool.zig").ArenaPool;
pub const Handle = @import("collections/pool.zig").Handle;

// ============ CONVENIENCE ============

/// Create ok result
pub fn ok(comptime T: type, value: T) Maybe(T) {
    return .{ .ok = value };
}

/// Create error result
pub fn err(comptime T: type, e: Error) Maybe(T) {
    return .{ .err = e };
}

/// Create error from std error
pub fn fail(comptime T: type, e: anyerror, step: Error.Step, path: []const u8) Maybe(T) {
    return .{ .err = Error.from(e, step, path) };
}

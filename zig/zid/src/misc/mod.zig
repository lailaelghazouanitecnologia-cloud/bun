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

// ============ LOGGING ============

pub const logger = @import("logger.zig");
pub const Log = logger.Log;
pub const Msg = logger.Msg;
pub const Kind = logger.Kind;
pub const Loc = logger.Loc;
pub const Location = logger.Location;
pub const Range = logger.Range;
pub const ScopedLog = logger.ScopedLog;

// ============ OPTIONS ============

pub const options = @import("options.zig");
pub const Target = options.Target;
pub const OutputFormat = options.OutputFormat;
pub const OptLevel = options.OptLevel;
pub const Toolchain = options.Toolchain;
pub const BuildOptions = options.BuildOptions;
pub const GlobalConfig = options.GlobalConfig;
pub const Features = options.Features;

// ============ CACHING ============

pub const cache = @import("cache.zig");
pub const CacheSet = cache.Set;
pub const FileCache = cache.FileCache;
pub const ContentCache = cache.ContentCache;
pub const PathCache = cache.PathCache;
pub const LruCache = cache.LruCache;
pub const DiskCache = cache.DiskCache;

// ============ PROGRESS ============

pub const progress = @import("progress.zig");
pub const Progress = progress;
pub const ProgressBar = progress.Bar;
pub const Spinner = progress.Spinner;
pub const TaskTracker = progress.TaskTracker;

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

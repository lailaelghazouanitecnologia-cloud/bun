//! Feature Flags
//!
//! Compile-time and runtime feature flags inspired by Bun.
//! Use these to enable/disable features or use experimental code paths.
//!
//! Compile-time flags are resolved at build time (zero cost).
//! Runtime flags check environment variables at startup.

const std = @import("std");
const Environment = @import("env.zig");
const env_var = @import("env_var.zig");

// ============ COMPILE-TIME FLAGS ============

/// Use platform-specific optimizations
pub const use_platform_optimizations = !Environment.isWasm;

/// Enable SIMD string operations (when available)
pub const use_simd = Environment.isX64 or Environment.isAarch64;

/// Use sendfile/copy_file_range on Linux for efficient copies
pub const use_zero_copy = Environment.isLinux;

/// Enable colored output by default
pub const default_colors = Environment.isPosix;

/// Enable file descriptor reuse for performance
pub const reuse_file_descriptors = !Environment.isWindows;

/// Enable parallel downloads
pub const parallel_downloads = true;

/// Maximum parallel downloads
pub const max_parallel_downloads = 4;

/// Enable HTTP keep-alive
pub const http_keepalive = true;

/// Enable download caching
pub const download_caching = true;

/// Default HTTP timeout in seconds
pub const default_http_timeout = 30;

/// Maximum file size for in-memory operations (100MB)
pub const max_memory_file_size = 100 * 1024 * 1024;

/// Buffer size for file operations
pub const file_buffer_size = 64 * 1024; // 64KB

/// Enable progress bars by default
pub const show_progress = true;

/// Enable auto-update checks
pub const auto_update_check = true;

/// Days between update checks
pub const update_check_interval_days = 7;

// ============ EXPERIMENTAL FLAGS ============

/// Experimental: Use new resolver algorithm
pub const experimental_resolver = false;

/// Experimental: Enable capsule hot-reload
pub const experimental_hot_reload = false;

/// Experimental: Use memory-mapped I/O
pub const experimental_mmap = false;

// ============ DEBUG FLAGS ============

/// Always show debug information
pub const always_debug = Environment.isDebug;

/// Show timing information for operations
pub const show_timing = Environment.isDebug;

/// Dump intermediate state on errors
pub const dump_on_error = Environment.isDebug;

// ============ RUNTIME FLAGS ============

/// Runtime flag that can be toggled via environment variable
pub fn RuntimeFlag(comptime name: []const u8, comptime default: bool) type {
    return struct {
        var cached: ?bool = null;

        pub fn get() bool {
            if (cached) |v| return v;

            // Check environment variable
            if (std.posix.getenv(name)) |val| {
                cached = parseBool(val);
                return cached.?;
            }

            cached = default;
            return default;
        }

        pub fn reset() void {
            cached = null;
        }

        fn parseBool(val: []const u8) bool {
            if (val.len == 0) return false;
            return val[0] != '0' and
                !std.mem.eql(u8, val, "false") and
                !std.mem.eql(u8, val, "no") and
                !std.mem.eql(u8, val, "off");
        }
    };
}

// Runtime flags (checked via environment)
pub const DISABLE_COLORS = RuntimeFlag("ZID_NO_COLOR", false);
pub const DISABLE_PROGRESS = RuntimeFlag("ZID_NO_PROGRESS", false);
pub const DISABLE_CACHE = RuntimeFlag("ZID_NO_CACHE", false);
pub const DISABLE_UPDATE_CHECK = RuntimeFlag("ZID_NO_UPDATE_CHECK", false);
pub const FORCE_DOWNLOAD = RuntimeFlag("ZID_FORCE_DOWNLOAD", false);
pub const VERBOSE = RuntimeFlag("ZID_VERBOSE", false);
pub const TRACE = RuntimeFlag("ZID_TRACE", false);

// ============ HELPER FUNCTIONS ============

/// Should show colors in output?
pub fn useColors() bool {
    if (DISABLE_COLORS.get()) return false;
    if (env_var.NO_COLOR.get() orelse false) return false;
    if (env_var.FORCE_COLOR.get() orelse false) return true;
    return std.io.getStdErr().isTty();
}

/// Should show progress bars?
pub fn showProgress() bool {
    if (DISABLE_PROGRESS.get()) return false;
    if (env_var.isCI()) return false; // No progress in CI
    return show_progress and std.io.getStdErr().isTty();
}

/// Should use download cache?
pub fn useCache() bool {
    if (DISABLE_CACHE.get()) return false;
    return download_caching;
}

/// Should check for updates?
pub fn checkForUpdates() bool {
    if (DISABLE_UPDATE_CHECK.get()) return false;
    return auto_update_check;
}

/// Get HTTP timeout
pub fn httpTimeout() u32 {
    return env_var.ZID_TIMEOUT.get() orelse default_http_timeout;
}

/// Is verbose mode enabled?
pub fn isVerbose() bool {
    return VERBOSE.get() or Environment.isDebug;
}

/// Is trace mode enabled?
pub fn isTrace() bool {
    return TRACE.get();
}

// ============ TESTS ============

test "feature_flags: compile-time flags exist" {
    // Just verify they compile
    _ = use_platform_optimizations;
    _ = use_simd;
    _ = use_zero_copy;
    _ = parallel_downloads;
}

test "feature_flags: runtime flags" {
    // Reset any cached values
    DISABLE_COLORS.reset();
    VERBOSE.reset();

    // Test default behavior
    _ = useColors();
    _ = showProgress();
    _ = isVerbose();
}

test "feature_flags: httpTimeout" {
    const timeout = httpTimeout();
    try std.testing.expect(timeout > 0);
    try std.testing.expect(timeout <= 300); // Max 5 minutes
}

//! Environment - Compile-time platform and build configuration
//!
//! Zero-cost conditionals for platform-specific code.
//! Follows the pattern from Bun's env.zig

const std = @import("std");
const builtin = @import("builtin");

// ============ PLATFORM ============

pub const os = builtin.os.tag;
pub const arch = builtin.cpu.arch;

pub const isLinux = os == .linux;
pub const isDarwin = os == .macos;
pub const isMacOS = isDarwin;
pub const isWindows = os == .windows;
pub const isFreeBSD = os == .freebsd;

pub const isPosix = isLinux or isDarwin or isFreeBSD;
pub const isUnix = isPosix;

pub const isX64 = arch == .x86_64;
pub const isAarch64 = arch == .aarch64;
pub const isWasm = arch == .wasm32 or arch == .wasm64;

pub const is64Bit = @sizeOf(usize) == 8;

// ============ BUILD MODE ============

pub const optimize = builtin.mode;

pub const isDebug = optimize == .Debug;
pub const isReleaseSafe = optimize == .ReleaseSafe;
pub const isReleaseFast = optimize == .ReleaseFast;
pub const isReleaseSmall = optimize == .ReleaseSmall;
pub const isRelease = isReleaseSafe or isReleaseFast or isReleaseSmall;

pub const isTest = builtin.is_test;

// ============ PATHS ============

pub const path_sep: u8 = if (isWindows) '\\' else '/';
pub const path_sep_str: []const u8 = if (isWindows) "\\" else "/";
pub const path_delimiter: u8 = if (isWindows) ';' else ':';
pub const line_sep: []const u8 = if (isWindows) "\r\n" else "\n";

// ============ LIMITS ============

pub const max_path = if (isWindows) 32767 else 4096;

// ============ RUNTIME CHECKS ============

pub fn isTTY() bool {
    if (isWindows) return true;
    return std.io.getStdErr().isTty();
}

pub fn supportsColor() bool {
    if (std.posix.getenv("NO_COLOR") != null) return false;
    if (std.posix.getenv("FORCE_COLOR") != null) return true;
    return isTTY();
}

pub fn isCI() bool {
    return std.posix.getenv("CI") != null or
        std.posix.getenv("GITHUB_ACTIONS") != null;
}

// ============ PLATFORM STRINGS ============

pub fn getPlatform() []const u8 {
    return comptime if (isLinux) "linux" else if (isDarwin) "darwin" else if (isWindows) "windows" else "unknown";
}

pub fn getArch() []const u8 {
    return comptime if (isX64) "x86_64" else if (isAarch64) "aarch64" else "unknown";
}

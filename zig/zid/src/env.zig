//! Environment - Compile-time platform and build configuration
//!
//! Use these constants for zero-cost platform-specific code:
//!   if (Environment.isLinux) { ... }
//!   if (comptime Environment.isDebug) { ... }

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
pub const isOpenBSD = os == .openbsd;
pub const isNetBSD = os == .netbsd;

pub const isPosix = isLinux or isDarwin or isFreeBSD or isOpenBSD or isNetBSD;
pub const isUnix = isPosix;

pub const isX64 = arch == .x86_64;
pub const isX86 = arch == .x86;
pub const isAarch64 = arch == .aarch64;
pub const isArm = arch == .arm;
pub const isWasm = arch == .wasm32 or arch == .wasm64;

pub const is64Bit = @sizeOf(usize) == 8;
pub const is32Bit = @sizeOf(usize) == 4;

// ============ BUILD MODE ============

pub const optimize = builtin.mode;

pub const isDebug = optimize == .Debug;
pub const isReleaseSafe = optimize == .ReleaseSafe;
pub const isReleaseFast = optimize == .ReleaseFast;
pub const isReleaseSmall = optimize == .ReleaseSmall;
pub const isRelease = isReleaseSafe or isReleaseFast or isReleaseSmall;

pub const isTest = builtin.is_test;

// ============ FEATURES ============

/// Whether we have SIMD support
pub const hasSIMD = isX64 or isAarch64;

/// Whether we have hardware AES support
pub const hasAES = isX64 or isAarch64;

/// Pointer size in bytes
pub const ptrSize = @sizeOf(usize);

/// Cache line size (typical)
pub const cacheLineSize = 64;

// ============ PATHS ============

pub const pathSeparator: u8 = if (isWindows) '\\' else '/';
pub const pathSeparatorStr: []const u8 = if (isWindows) "\\" else "/";

pub const pathDelimiter: u8 = if (isWindows) ';' else ':';
pub const pathDelimiterStr: []const u8 = if (isWindows) ";" else ":";

pub const lineEnding: []const u8 = if (isWindows) "\r\n" else "\n";

// ============ LIMITS ============

pub const maxPathBytes: usize = if (isWindows) 32767 else 4096;
pub const maxFileNameBytes: usize = 255;

// ============ FEATURE FLAGS ============

/// Enable verbose debug logging
pub const enableDebugLogs = isDebug and !isTest;

/// Enable memory leak detection
pub const enableLeakDetection = isDebug;

/// Enable performance profiling
pub const enableProfiling = false;

/// Enable assertions in release builds
pub const enableReleaseAssertions = isReleaseSafe;

// ============ PLATFORM STRINGS ============

pub fn getPlatformName() []const u8 {
    if (isLinux) return "linux";
    if (isDarwin) return "darwin";
    if (isWindows) return "windows";
    if (isFreeBSD) return "freebsd";
    return "unknown";
}

pub fn getArchName() []const u8 {
    if (isX64) return "x86_64";
    if (isAarch64) return "aarch64";
    if (isArm) return "arm";
    if (isX86) return "x86";
    if (isWasm) return "wasm";
    return "unknown";
}

pub fn getTriple() []const u8 {
    return comptime getArchName() ++ "-" ++ getPlatformName();
}

// ============ RUNTIME CHECKS ============

/// Check if running in CI environment
pub fn isCI() bool {
    return std.posix.getenv("CI") != null or
        std.posix.getenv("GITHUB_ACTIONS") != null or
        std.posix.getenv("GITLAB_CI") != null or
        std.posix.getenv("JENKINS_URL") != null;
}

/// Check if running in TTY
pub fn isTTY() bool {
    if (isWindows) {
        return true; // TODO: proper Windows check
    }
    const stderr = std.io.getStdErr();
    return stderr.isTty();
}

/// Check if color output is supported
pub fn supportsColor() bool {
    if (std.posix.getenv("NO_COLOR") != null) return false;
    if (std.posix.getenv("FORCE_COLOR") != null) return true;
    return isTTY();
}

//! Environment - Compile-time platform and build configuration
//!
//! Zero-cost conditionals for platform-specific code.
//! Inspired by Bun's env.zig - all platform detection at compile time.

const std = @import("std");
const builtin = @import("builtin");

// ============ PLATFORM ============

pub const os = builtin.os.tag;
pub const arch = builtin.cpu.arch;
pub const abi = builtin.abi;

pub const isLinux = os == .linux;
pub const isDarwin = os == .macos;
pub const isMacOS = isDarwin;
pub const isWindows = os == .windows;
pub const isFreeBSD = os == .freebsd;
pub const isOpenBSD = os == .openbsd;
pub const isNetBSD = os == .netbsd;
pub const isBSD = isFreeBSD or isOpenBSD or isNetBSD;

pub const isPosix = isLinux or isDarwin or isBSD;
pub const isUnix = isPosix;
pub const isNative = builtin.target.isNative();

// ============ ARCHITECTURE ============

pub const isX64 = arch == .x86_64;
pub const isX86 = arch == .x86;
pub const isAarch64 = arch == .aarch64;
pub const isArm = arch == .arm;
pub const isWasm = arch == .wasm32 or arch == .wasm64;
pub const isWasm32 = arch == .wasm32;
pub const isWasm64 = arch == .wasm64;

pub const is64Bit = @sizeOf(usize) == 8;
pub const is32Bit = @sizeOf(usize) == 4;
pub const pointerSize = @sizeOf(usize);

// ============ ABI ============

pub const isMusl = abi == .musl;
pub const isGnu = abi == .gnu;

// ============ BUILD MODE ============

pub const optimize = builtin.mode;

pub const isDebug = optimize == .Debug;
pub const isReleaseSafe = optimize == .ReleaseSafe;
pub const isReleaseFast = optimize == .ReleaseFast;
pub const isReleaseSmall = optimize == .ReleaseSmall;
pub const isRelease = isReleaseSafe or isReleaseFast or isReleaseSmall;
pub const isOptimized = isRelease;

pub const isTest = builtin.is_test;

// ============ PATHS ============

pub const path_sep: u8 = if (isWindows) '\\' else '/';
pub const path_sep_str: []const u8 = if (isWindows) "\\" else "/";
pub const path_delimiter: u8 = if (isWindows) ';' else ':';
pub const line_sep: []const u8 = if (isWindows) "\r\n" else "\n";

// ============ LIMITS ============

pub const max_path = if (isWindows) 32767 else 4096;
pub const max_symlinks = if (isLinux) 40 else 32;
pub const page_size = std.mem.page_size;

// Stack size varies by platform
pub const default_stack_size: usize = if (isWindows)
    1 * 1024 * 1024 // 1MB on Windows
else if (isDarwin)
    8 * 1024 * 1024 // 8MB on macOS
else
    2 * 1024 * 1024; // 2MB on Linux

// ============ OPERATING SYSTEM ENUM ============

pub const OperatingSystem = enum {
    linux,
    darwin,
    windows,
    freebsd,
    openbsd,
    netbsd,
    unknown,

    /// Get current OS at comptime
    pub fn current() OperatingSystem {
        return comptime if (isLinux)
            .linux
        else if (isDarwin)
            .darwin
        else if (isWindows)
            .windows
        else if (isFreeBSD)
            .freebsd
        else if (isOpenBSD)
            .openbsd
        else if (isNetBSD)
            .netbsd
        else
            .unknown;
    }

    /// Display name for user-facing output
    pub fn displayName(self: OperatingSystem) []const u8 {
        return switch (self) {
            .linux => "Linux",
            .darwin => "macOS",
            .windows => "Windows",
            .freebsd => "FreeBSD",
            .openbsd => "OpenBSD",
            .netbsd => "NetBSD",
            .unknown => "Unknown",
        };
    }

    /// Name for URLs and filenames
    pub fn name(self: OperatingSystem) []const u8 {
        return switch (self) {
            .linux => "linux",
            .darwin => "darwin",
            .windows => "windows",
            .freebsd => "freebsd",
            .openbsd => "openbsd",
            .netbsd => "netbsd",
            .unknown => "unknown",
        };
    }

    /// Node.js compatible name (process.platform)
    pub fn nodeCompatName(self: OperatingSystem) []const u8 {
        return switch (self) {
            .darwin => "darwin",
            .linux => "linux",
            .windows => "win32",
            .freebsd => "freebsd",
            .openbsd => "openbsd",
            .netbsd => "netbsd",
            .unknown => "unknown",
        };
    }

    /// Parse from string
    pub fn fromString(str: []const u8) ?OperatingSystem {
        const map = std.StaticStringMap(OperatingSystem).initComptime(.{
            .{ "linux", .linux },
            .{ "Linux", .linux },
            .{ "darwin", .darwin },
            .{ "macos", .darwin },
            .{ "macOS", .darwin },
            .{ "osx", .darwin },
            .{ "windows", .windows },
            .{ "win32", .windows },
            .{ "Windows", .windows },
            .{ "freebsd", .freebsd },
            .{ "openbsd", .openbsd },
            .{ "netbsd", .netbsd },
        });
        return map.get(str);
    }
};

// ============ ARCHITECTURE ENUM ============

pub const Architecture = enum {
    x86_64,
    aarch64,
    x86,
    arm,
    wasm32,
    wasm64,
    unknown,

    /// Get current architecture at comptime
    pub fn current() Architecture {
        return comptime if (isX64)
            .x86_64
        else if (isAarch64)
            .aarch64
        else if (isX86)
            .x86
        else if (isArm)
            .arm
        else if (isWasm32)
            .wasm32
        else if (isWasm64)
            .wasm64
        else
            .unknown;
    }

    /// Name for URLs and filenames
    pub fn name(self: Architecture) []const u8 {
        return switch (self) {
            .x86_64 => "x86_64",
            .aarch64 => "aarch64",
            .x86 => "x86",
            .arm => "arm",
            .wasm32 => "wasm32",
            .wasm64 => "wasm64",
            .unknown => "unknown",
        };
    }

    /// Alternative names (some tools use different conventions)
    pub fn altName(self: Architecture) []const u8 {
        return switch (self) {
            .x86_64 => "x64",
            .aarch64 => "arm64",
            .x86 => "ia32",
            .arm => "arm",
            else => self.name(),
        };
    }

    /// Parse from string
    pub fn fromString(str: []const u8) ?Architecture {
        const map = std.StaticStringMap(Architecture).initComptime(.{
            .{ "x86_64", .x86_64 },
            .{ "x64", .x86_64 },
            .{ "amd64", .x86_64 },
            .{ "aarch64", .aarch64 },
            .{ "arm64", .aarch64 },
            .{ "x86", .x86 },
            .{ "i386", .x86 },
            .{ "i686", .x86 },
            .{ "ia32", .x86 },
            .{ "arm", .arm },
            .{ "wasm32", .wasm32 },
            .{ "wasm64", .wasm64 },
        });
        return map.get(str);
    }
};

// ============ TRIPLET ============

/// Get platform triplet string (e.g., "linux-x86_64", "darwin-aarch64")
pub fn getTriplet() []const u8 {
    return comptime OperatingSystem.current().name() ++ "-" ++ Architecture.current().name();
}

/// Get triplet with ABI suffix if musl
pub fn getTripletWithAbi() []const u8 {
    return comptime if (isMusl)
        getTriplet() ++ "-musl"
    else
        getTriplet();
}

// ============ RUNTIME CHECKS ============

pub fn isTTY() bool {
    if (isWindows) {
        // Windows always returns true for console apps
        return true;
    }
    return std.io.getStdErr().isTty();
}

pub fn supportsColor() bool {
    if (std.posix.getenv("NO_COLOR") != null) return false;
    if (std.posix.getenv("FORCE_COLOR") != null) return true;
    return isTTY();
}

pub fn isCI() bool {
    return std.posix.getenv("CI") != null or
        std.posix.getenv("GITHUB_ACTIONS") != null or
        std.posix.getenv("GITLAB_CI") != null or
        std.posix.getenv("JENKINS_URL") != null or
        std.posix.getenv("CIRCLECI") != null or
        std.posix.getenv("TRAVIS") != null or
        std.posix.getenv("TF_BUILD") != null;
}

pub fn isDocker() bool {
    if (!isLinux) return false;
    // Check for /.dockerenv file
    std.fs.accessAbsolute("/.dockerenv", .{}) catch return false;
    return true;
}

pub fn isWSL() bool {
    if (!isLinux) return false;
    // Check for Microsoft in kernel version
    if (std.posix.getenv("WSL_DISTRO_NAME") != null) return true;
    // Could also check /proc/version but env var is faster
    return false;
}

pub fn isNixOS() bool {
    if (!isLinux) return false;
    std.fs.accessAbsolute("/etc/NIXOS", .{}) catch return false;
    return true;
}

// ============ PLATFORM STRINGS ============

/// Get platform name for display
pub fn getPlatformDisplay() []const u8 {
    return comptime OperatingSystem.current().displayName();
}

/// Get platform name for URLs/filenames
pub fn getPlatform() []const u8 {
    return comptime OperatingSystem.current().name();
}

/// Get architecture name
pub fn getArch() []const u8 {
    return comptime Architecture.current().name();
}

/// Get alternative architecture name
pub fn getArchAlt() []const u8 {
    return comptime Architecture.current().altName();
}

// ============ TESTS ============

test "env: platform detection" {
    // At least one platform should be true
    try std.testing.expect(isLinux or isDarwin or isWindows or isBSD or isWasm);
}

test "env: architecture detection" {
    // At least one arch should be true
    try std.testing.expect(isX64 or isAarch64 or isX86 or isArm or isWasm);
}

test "env: triplet" {
    const triplet = getTriplet();
    try std.testing.expect(triplet.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, triplet, "-") != null);
}

test "env: OperatingSystem enum" {
    const current = OperatingSystem.current();
    try std.testing.expect(current != .unknown);
    try std.testing.expect(current.name().len > 0);
    try std.testing.expect(current.displayName().len > 0);
}

test "env: Architecture enum" {
    const current = Architecture.current();
    try std.testing.expect(current != .unknown);
    try std.testing.expect(current.name().len > 0);
}

test "env: fromString" {
    try std.testing.expectEqual(OperatingSystem.linux, OperatingSystem.fromString("linux").?);
    try std.testing.expectEqual(OperatingSystem.darwin, OperatingSystem.fromString("macos").?);
    try std.testing.expectEqual(Architecture.x86_64, Architecture.fromString("x64").?);
    try std.testing.expectEqual(Architecture.aarch64, Architecture.fromString("arm64").?);
}

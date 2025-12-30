//! Type-Safe Environment Variables
//!
//! Inspired by Bun's env_var.zig - provides compile-time typed
//! environment variable access with defaults and validation.
//!
//! Usage:
//!   const home = env_var.HOME.get() orelse "/tmp";
//!   const debug = env_var.ZID_DEBUG.get();  // bool
//!   const timeout = env_var.ZID_TIMEOUT.get();  // ?u32

const std = @import("std");
const Environment = @import("env.zig");

// ============ VARIABLE KINDS ============

pub const Kind = enum {
    string,
    boolean,
    unsigned,
    signed,
    path,
};

// ============ VARIABLE DEFINITION ============

pub fn Variable(comptime kind: Kind, comptime ReturnType: type) type {
    return struct {
        name: []const u8,
        posix_name: ?[]const u8,
        windows_name: ?[]const u8,
        default: ?ReturnType,

        const Self = @This();

        pub fn get(self: Self) ?ReturnType {
            const env_name = if (Environment.isWindows)
                self.windows_name orelse self.name
            else
                self.posix_name orelse self.name;

            const value = std.posix.getenv(env_name) orelse {
                return self.default;
            };

            return switch (kind) {
                .string, .path => value,
                .boolean => parseBool(value),
                .unsigned => std.fmt.parseUnsigned(ReturnType, value, 10) catch self.default,
                .signed => std.fmt.parseInt(ReturnType, value, 10) catch self.default,
            };
        }

        pub fn getWithDefault(self: Self, default: ReturnType) ReturnType {
            return self.get() orelse default;
        }

        pub fn isSet(self: Self) bool {
            const env_name = if (Environment.isWindows)
                self.windows_name orelse self.name
            else
                self.posix_name orelse self.name;

            return std.posix.getenv(env_name) != null;
        }
    };
}

fn parseBool(value: []const u8) ?bool {
    if (value.len == 0) return false;

    const truthy = [_][]const u8{ "1", "true", "yes", "on", "TRUE", "YES", "ON" };
    const falsy = [_][]const u8{ "0", "false", "no", "off", "FALSE", "NO", "OFF" };

    for (truthy) |t| {
        if (std.mem.eql(u8, value, t)) return true;
    }
    for (falsy) |f| {
        if (std.mem.eql(u8, value, f)) return false;
    }

    // Non-empty value is truthy (like Bun)
    return true;
}

// ============ HELPER CONSTRUCTORS ============

pub fn String(comptime name: []const u8, comptime default: ?[]const u8) Variable(.string, []const u8) {
    return .{
        .name = name,
        .posix_name = null,
        .windows_name = null,
        .default = default,
    };
}

pub fn Bool(comptime name: []const u8, comptime default: ?bool) Variable(.boolean, bool) {
    return .{
        .name = name,
        .posix_name = null,
        .windows_name = null,
        .default = default,
    };
}

pub fn Unsigned(comptime name: []const u8, comptime default: ?u32) Variable(.unsigned, u32) {
    return .{
        .name = name,
        .posix_name = null,
        .windows_name = null,
        .default = default,
    };
}

pub fn Path(comptime name: []const u8) Variable(.path, []const u8) {
    return .{
        .name = name,
        .posix_name = null,
        .windows_name = null,
        .default = null,
    };
}

/// Platform-specific variable (different name on POSIX vs Windows)
pub fn PlatformString(
    comptime posix_name: ?[]const u8,
    comptime windows_name: ?[]const u8,
) Variable(.string, []const u8) {
    return .{
        .name = posix_name orelse windows_name orelse "",
        .posix_name = posix_name,
        .windows_name = windows_name,
        .default = null,
    };
}

// ============ ZID-SPECIFIC VARIABLES ============

/// Zid home directory (~/.zid)
pub const ZID_HOME = String("ZID_HOME", null);

/// Zid bin directory
pub const ZID_BIN = String("ZID_BIN", null);

/// Enable debug mode
pub const ZID_DEBUG = Bool("ZID_DEBUG", false);

/// Debug specific subsystem
pub const ZID_DEBUG_TOOLCHAIN = Bool("ZID_DEBUG_TOOLCHAIN", false);
pub const ZID_DEBUG_DOWNLOAD = Bool("ZID_DEBUG_DOWNLOAD", false);
pub const ZID_DEBUG_CAPSULES = Bool("ZID_DEBUG_CAPSULES", false);
pub const ZID_DEBUG_PATCHES = Bool("ZID_DEBUG_PATCHES", false);

/// Quiet mode (less output)
pub const ZID_QUIET = Bool("ZID_QUIET", false);

/// Disable colors
pub const NO_COLOR = Bool("NO_COLOR", false);

/// Force colors
pub const FORCE_COLOR = Bool("FORCE_COLOR", false);

/// HTTP timeout in seconds
pub const ZID_TIMEOUT = Unsigned("ZID_TIMEOUT", 30);

/// HTTP proxy
pub const HTTP_PROXY = String("HTTP_PROXY", null);
pub const HTTPS_PROXY = String("HTTPS_PROXY", null);
pub const NO_PROXY = String("NO_PROXY", null);

/// GitHub token for rate limiting
pub const GITHUB_TOKEN = String("GITHUB_TOKEN", null);

/// GitHub API domain (for proxies in China)
pub const GITHUB_API_DOMAIN = String("GITHUB_API_DOMAIN", "api.github.com");

// ============ STANDARD VARIABLES ============

/// Home directory
pub const HOME = PlatformString("HOME", "USERPROFILE");

/// Username
pub const USER = PlatformString("USER", "USERNAME");

/// Temporary directory
pub const TMPDIR = PlatformString("TMPDIR", "TEMP");

/// System PATH
pub const PATH = String("PATH", null);

/// Current shell
pub const SHELL = PlatformString("SHELL", null);

/// Editor
pub const EDITOR = String("EDITOR", null);
pub const VISUAL = String("VISUAL", null);

/// Terminal
pub const TERM = String("TERM", null);

/// Language/locale
pub const LANG = String("LANG", null);
pub const LC_ALL = String("LC_ALL", null);

// ============ CI VARIABLES ============

/// Generic CI flag
pub const CI = Bool("CI", false);

/// GitHub Actions
pub const GITHUB_ACTIONS = Bool("GITHUB_ACTIONS", false);
pub const GITHUB_SHA = String("GITHUB_SHA", null);
pub const GITHUB_REF = String("GITHUB_REF", null);
pub const GITHUB_REPOSITORY = String("GITHUB_REPOSITORY", null);
pub const GITHUB_RUN_ID = String("GITHUB_RUN_ID", null);

/// GitLab CI
pub const GITLAB_CI = Bool("GITLAB_CI", false);
pub const CI_COMMIT_SHA = String("CI_COMMIT_SHA", null);

/// Jenkins
pub const JENKINS_URL = String("JENKINS_URL", null);
pub const BUILD_NUMBER = String("BUILD_NUMBER", null);

/// CircleCI
pub const CIRCLECI = Bool("CIRCLECI", false);

/// Travis CI
pub const TRAVIS = Bool("TRAVIS", false);

/// Azure Pipelines
pub const TF_BUILD = Bool("TF_BUILD", false);

/// Buildkite
pub const BUILDKITE = Bool("BUILDKITE", false);

// ============ HELPER FUNCTIONS ============

/// Get home directory (with fallback)
pub fn getHome() []const u8 {
    return HOME.get() orelse if (Environment.isWindows) "C:\\Users\\Default" else "/tmp";
}

/// Get temp directory
pub fn getTmpDir() []const u8 {
    return TMPDIR.get() orelse if (Environment.isWindows) "C:\\Windows\\Temp" else "/tmp";
}

/// Get Zid home directory
pub fn getZidHome() []const u8 {
    if (ZID_HOME.get()) |home| {
        return home;
    }
    // Fall back to ~/.zid
    const home = getHome();
    var buf: [4096]u8 = undefined;
    return std.fmt.bufPrint(&buf, "{s}/.zid", .{home}) catch ".zid";
}

/// Check if running in CI
pub fn isCI() bool {
    return CI.get() orelse
        GITHUB_ACTIONS.get() orelse
        GITLAB_CI.get() orelse
        CIRCLECI.get() orelse
        TRAVIS.get() orelse
        TF_BUILD.get() orelse
        BUILDKITE.get() orelse
        JENKINS_URL.isSet() orelse
        false;
}

/// Get CI name if detected
pub fn getCIName() ?[]const u8 {
    if (GITHUB_ACTIONS.get() orelse false) return "GitHub Actions";
    if (GITLAB_CI.get() orelse false) return "GitLab CI";
    if (CIRCLECI.get() orelse false) return "CircleCI";
    if (TRAVIS.get() orelse false) return "Travis CI";
    if (TF_BUILD.get() orelse false) return "Azure Pipelines";
    if (BUILDKITE.get() orelse false) return "Buildkite";
    if (JENKINS_URL.isSet()) return "Jenkins";
    if (CI.get() orelse false) return "CI";
    return null;
}

/// Check if debug is enabled for a scope
pub fn isDebugEnabled(comptime scope: []const u8) bool {
    // Check specific scope first
    if (comptime std.mem.eql(u8, scope, "toolchain")) {
        return ZID_DEBUG_TOOLCHAIN.get() orelse false;
    }
    if (comptime std.mem.eql(u8, scope, "download")) {
        return ZID_DEBUG_DOWNLOAD.get() orelse false;
    }
    if (comptime std.mem.eql(u8, scope, "capsules")) {
        return ZID_DEBUG_CAPSULES.get() orelse false;
    }
    if (comptime std.mem.eql(u8, scope, "patches")) {
        return ZID_DEBUG_PATCHES.get() orelse false;
    }
    // Fall back to global debug
    return ZID_DEBUG.get() orelse false;
}

/// Should use colors in output?
pub fn useColors() bool {
    if (NO_COLOR.get() orelse false) return false;
    if (FORCE_COLOR.get() orelse false) return true;

    // Check if TTY
    return std.io.getStdErr().isTty();
}

// ============ TESTS ============

test "env_var: bool parsing" {
    try std.testing.expect(parseBool("1") == true);
    try std.testing.expect(parseBool("true") == true);
    try std.testing.expect(parseBool("yes") == true);
    try std.testing.expect(parseBool("0") == false);
    try std.testing.expect(parseBool("false") == false);
    try std.testing.expect(parseBool("no") == false);
    try std.testing.expect(parseBool("") == false);
    try std.testing.expect(parseBool("anything") == true); // Non-empty = true
}

test "env_var: HOME exists" {
    // HOME should exist on most systems
    const home = HOME.get();
    if (home) |h| {
        try std.testing.expect(h.len > 0);
    }
}

test "env_var: default values" {
    const timeout = ZID_TIMEOUT.get();
    try std.testing.expectEqual(@as(?u32, 30), timeout);
}

test "env_var: isCI" {
    // In normal execution, CI should be false
    // (unless we're actually running in CI!)
    _ = isCI(); // Just verify it doesn't crash
}

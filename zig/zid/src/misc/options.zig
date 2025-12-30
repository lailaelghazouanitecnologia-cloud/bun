//! Options - Configuration and options normalization
//!
//! Pattern from Bun's options.zig.
//! Provides normalized configuration with defaults and validation.

const std = @import("std");
const Environment = @import("../env.zig");

// ============ TARGETS ============

/// Build/execution target platform
pub const Target = enum {
    native,
    linux_x64,
    linux_aarch64,
    macos_x64,
    macos_aarch64,
    windows_x64,
    wasm32,
    wasm64,

    pub const Map = std.StaticStringMap(Target).initComptime(.{
        .{ "native", .native },
        .{ "linux-x64", .linux_x64 },
        .{ "linux-aarch64", .linux_aarch64 },
        .{ "macos-x64", .macos_x64 },
        .{ "macos-aarch64", .macos_aarch64 },
        .{ "windows-x64", .windows_x64 },
        .{ "wasm32", .wasm32 },
        .{ "wasm64", .wasm64 },
    });

    pub fn fromString(str: []const u8) ?Target {
        return Map.get(str);
    }

    pub fn string(self: Target) []const u8 {
        return switch (self) {
            .native => "native",
            .linux_x64 => "linux-x64",
            .linux_aarch64 => "linux-aarch64",
            .macos_x64 => "macos-x64",
            .macos_aarch64 => "macos-aarch64",
            .windows_x64 => "windows-x64",
            .wasm32 => "wasm32",
            .wasm64 => "wasm64",
        };
    }

    pub inline fn isWasm(self: Target) bool {
        return self == .wasm32 or self == .wasm64;
    }

    pub inline fn isNative(self: Target) bool {
        return self == .native;
    }

    /// Get native target for current platform
    pub fn getNative() Target {
        if (Environment.isLinux) {
            return if (Environment.isAarch64) .linux_aarch64 else .linux_x64;
        } else if (Environment.isMac) {
            return if (Environment.isAarch64) .macos_aarch64 else .macos_x64;
        } else if (Environment.isWindows) {
            return .windows_x64;
        }
        return .native;
    }
};

// ============ OUTPUT FORMATS ============

/// Output format for builds
pub const OutputFormat = enum {
    exe, // Executable
    lib, // Static library
    dylib, // Dynamic library
    obj, // Object file
    wasm, // WebAssembly

    pub const Map = std.StaticStringMap(OutputFormat).initComptime(.{
        .{ "exe", .exe },
        .{ "lib", .lib },
        .{ "dylib", .dylib },
        .{ "obj", .obj },
        .{ "wasm", .wasm },
    });

    pub fn fromString(str: []const u8) ?OutputFormat {
        return Map.get(str);
    }

    pub fn string(self: OutputFormat) []const u8 {
        return switch (self) {
            .exe => "exe",
            .lib => "lib",
            .dylib => "dylib",
            .obj => "obj",
            .wasm => "wasm",
        };
    }

    pub fn extension(self: OutputFormat, target: Target) []const u8 {
        return switch (self) {
            .exe => if (target == .windows_x64) ".exe" else "",
            .lib => ".a",
            .dylib => if (target == .windows_x64) ".dll" else if (target.isMac()) ".dylib" else ".so",
            .obj => ".o",
            .wasm => ".wasm",
        };
    }

    fn isMac(target: Target) bool {
        return target == .macos_x64 or target == .macos_aarch64;
    }
};

// ============ OPTIMIZATION ============

/// Optimization level
pub const OptLevel = enum(u2) {
    none = 0, // -O0: No optimization (fast compile)
    speed = 1, // -O2: Optimize for speed
    size = 2, // -Os: Optimize for size
    aggressive = 3, // -O3: Aggressive optimization

    pub const Map = std.StaticStringMap(OptLevel).initComptime(.{
        .{ "none", .none },
        .{ "0", .none },
        .{ "speed", .speed },
        .{ "2", .speed },
        .{ "size", .size },
        .{ "s", .size },
        .{ "aggressive", .aggressive },
        .{ "3", .aggressive },
    });

    pub fn fromString(str: []const u8) ?OptLevel {
        return Map.get(str);
    }

    pub fn string(self: OptLevel) []const u8 {
        return switch (self) {
            .none => "none",
            .speed => "speed",
            .size => "size",
            .aggressive => "aggressive",
        };
    }
};

// ============ TOOLCHAIN OPTIONS ============

/// Toolchain/compiler to use
pub const Toolchain = enum {
    zig,
    rust,
    go,
    bun,
    node,
    deno,
    clang,
    gcc,
    auto, // Auto-detect from project

    pub const Map = std.StaticStringMap(Toolchain).initComptime(.{
        .{ "zig", .zig },
        .{ "rust", .rust },
        .{ "go", .go },
        .{ "bun", .bun },
        .{ "node", .node },
        .{ "deno", .deno },
        .{ "clang", .clang },
        .{ "gcc", .gcc },
        .{ "auto", .auto },
    });

    pub fn fromString(str: []const u8) ?Toolchain {
        return Map.get(str);
    }

    pub fn string(self: Toolchain) []const u8 {
        return switch (self) {
            .zig => "zig",
            .rust => "rust",
            .go => "go",
            .bun => "bun",
            .node => "node",
            .deno => "deno",
            .clang => "clang",
            .gcc => "gcc",
            .auto => "auto",
        };
    }

    /// Get file extensions associated with this toolchain
    pub fn extensions(self: Toolchain) []const []const u8 {
        return switch (self) {
            .zig => &.{ ".zig", ".zir" },
            .rust => &.{ ".rs", ".rlib" },
            .go => &.{".go"},
            .bun, .node, .deno => &.{ ".js", ".ts", ".jsx", ".tsx", ".mjs", ".cjs" },
            .clang, .gcc => &.{ ".c", ".cpp", ".cc", ".cxx", ".h", ".hpp" },
            .auto => &.{},
        };
    }
};

// ============ BUILD OPTIONS ============

/// Build configuration options
pub const BuildOptions = struct {
    // Core options
    target: Target = .native,
    output_format: OutputFormat = .exe,
    opt_level: OptLevel = .none,
    toolchain: Toolchain = .auto,

    // Paths
    root_dir: []const u8 = ".",
    output_dir: []const u8 = "build",
    cache_dir: []const u8 = ".zid-cache",

    // Entry points
    entry_points: []const []const u8 = &.{},

    // Flags
    debug: bool = true,
    strip: bool = false,
    emit_asm: bool = false,
    emit_llvm_ir: bool = false,
    verbose: bool = false,
    incremental: bool = true,

    // Limits
    max_errors: u32 = 20,
    max_threads: ?u32 = null,

    // Feature flags
    enable_safety: bool = true,
    enable_stack_protector: bool = true,

    pub fn init() BuildOptions {
        return .{};
    }

    pub fn setRelease(self: *BuildOptions) void {
        self.debug = false;
        self.strip = true;
        self.opt_level = .speed;
        self.enable_safety = false;
    }

    pub fn setDebug(self: *BuildOptions) void {
        self.debug = true;
        self.strip = false;
        self.opt_level = .none;
        self.enable_safety = true;
    }

    /// Get effective thread count
    pub fn getThreads(self: BuildOptions) u32 {
        if (self.max_threads) |t| return t;
        const cpus = std.Thread.getCpuCount() catch 1;
        return @intCast(@min(cpus, 256));
    }
};

// ============ GLOBAL CONFIG ============

/// Global configuration (from config file or environment)
pub const GlobalConfig = struct {
    // Directories
    home_dir: []const u8 = "",
    bin_dir: []const u8 = "",
    cache_dir: []const u8 = "",
    toolchain_dir: []const u8 = "",

    // Default toolchain versions
    default_zig: ?[]const u8 = null,
    default_rust: ?[]const u8 = null,
    default_go: ?[]const u8 = null,
    default_node: ?[]const u8 = null,
    default_bun: ?[]const u8 = null,

    // Behavior
    auto_update: bool = false,
    telemetry: bool = false,
    color: ColorMode = .auto,
    log_level: LogLevel = .info,

    pub const ColorMode = enum {
        auto,
        always,
        never,

        pub fn shouldUse(self: ColorMode) bool {
            return switch (self) {
                .always => true,
                .never => false,
                .auto => Environment.supportsColor(),
            };
        }
    };

    pub const LogLevel = enum(u3) {
        silent = 0,
        err = 1,
        warn = 2,
        info = 3,
        debug = 4,
        verbose = 5,

        pub fn atLeast(self: LogLevel, other: LogLevel) bool {
            return @intFromEnum(self) >= @intFromEnum(other);
        }
    };

    pub fn init() GlobalConfig {
        return .{};
    }

    /// Load from environment variables
    pub fn loadFromEnv(self: *GlobalConfig) void {
        if (std.posix.getenv("ZID_HOME")) |h| self.home_dir = h;
        if (std.posix.getenv("ZID_CACHE")) |c| self.cache_dir = c;
        if (std.posix.getenv("ZID_NO_COLOR")) |_| self.color = .never;
        if (std.posix.getenv("ZID_DEBUG")) |_| self.log_level = .debug;
        if (std.posix.getenv("ZID_VERBOSE")) |_| self.log_level = .verbose;
    }
};

// ============ FEATURE FLAGS ============

/// Packed feature flags for efficient storage
pub const Features = packed struct(u16) {
    jsx: bool = false,
    typescript: bool = false,
    sourcemaps: bool = false,
    hot_reload: bool = false,
    tree_shaking: bool = false,
    minify: bool = false,
    bundle: bool = false,
    splitting: bool = false,
    _padding: u8 = 0,

    pub const none = Features{};
    pub const all = Features{
        .jsx = true,
        .typescript = true,
        .sourcemaps = true,
        .hot_reload = true,
        .tree_shaking = true,
        .minify = true,
        .bundle = true,
        .splitting = true,
    };

    pub fn merge(self: Features, other: Features) Features {
        const a: u16 = @bitCast(self);
        const b: u16 = @bitCast(other);
        return @bitCast(a | b);
    }

    pub fn hasAny(self: Features) bool {
        const v: u16 = @bitCast(self);
        return (v & 0xFF) != 0;
    }
};

// ============ TESTS ============

test "Target parsing" {
    try std.testing.expectEqual(Target.linux_x64, Target.fromString("linux-x64").?);
    try std.testing.expectEqual(Target.wasm32, Target.fromString("wasm32").?);
    try std.testing.expect(Target.fromString("invalid") == null);
}

test "OptLevel parsing" {
    try std.testing.expectEqual(OptLevel.none, OptLevel.fromString("0").?);
    try std.testing.expectEqual(OptLevel.speed, OptLevel.fromString("speed").?);
    try std.testing.expectEqual(OptLevel.size, OptLevel.fromString("s").?);
}

test "BuildOptions defaults" {
    var opts = BuildOptions.init();
    try std.testing.expect(opts.debug);
    try std.testing.expect(!opts.strip);

    opts.setRelease();
    try std.testing.expect(!opts.debug);
    try std.testing.expect(opts.strip);
    try std.testing.expectEqual(OptLevel.speed, opts.opt_level);
}

test "Features packed" {
    const f = Features{ .jsx = true, .typescript = true };
    try std.testing.expect(f.jsx);
    try std.testing.expect(f.typescript);
    try std.testing.expect(!f.minify);
    try std.testing.expect(f.hasAny());
    try std.testing.expect(!Features.none.hasAny());
}

const std = @import("std");

/// Project Configuration - zid.yaml / zid.json
/// Defines project-level transpilation settings
pub const ProjectConfig = struct {
    /// Project name
    name: []const u8 = "untitled",

    /// Project version
    version: []const u8 = "0.1.0",

    /// Source language
    lang: []const u8 = "lua",

    /// Default target
    target: []const u8 = "wat",

    /// Alternative targets
    targets: []const []const u8 = &.{},

    /// Source directory
    src: []const u8 = "src",

    /// Output directory
    out: []const u8 = "dist",

    /// Entry point file
    entry: ?[]const u8 = null,

    // ============ DEPENDENCIES ============

    /// External libraries from other languages
    libs: []const LibDependency = &.{},

    /// Zid packages
    packages: []const PackageDependency = &.{},

    // ============ TRANSPILATION ============

    /// Compilation mode
    mode: Mode = .ir,

    /// LLM configuration (only for marked blocks)
    llm: ?LLMConfig = null,

    /// Feature overrides
    features: FeatureOverrides = .{},

    /// Optimization level
    optimize: Optimize = .default,

    // ============ OUTPUT ============

    /// Export configuration
    exports: []const Export = &.{},

    /// Generate bindings for other languages
    bindings: []const Binding = &.{},

    // ============ TYPES ============

    pub const Mode = enum {
        direct, // Fast, simple transpilation
        ir, // Via IR, preserves semantics
        hybrid, // Auto + LLM for conflicts
    };

    pub const Optimize = enum {
        none, // No optimization
        default, // Standard optimizations
        size, // Optimize for size
        speed, // Optimize for speed
    };

    pub const LibDependency = struct {
        /// Library name
        name: []const u8,

        /// Source language
        lang: []const u8,

        /// Version constraint
        version: ?[]const u8 = null,

        /// Specific features to use
        features: []const []const u8 = &.{},

        /// Path to local library (optional)
        path: ?[]const u8 = null,

        /// Git repository (optional)
        git: ?[]const u8 = null,

        /// Registry (npm, crates.io, etc.)
        registry: ?[]const u8 = null,
    };

    pub const PackageDependency = struct {
        /// Package name (@lang/name or @target/name)
        name: []const u8,

        /// Version
        version: ?[]const u8 = null,
    };

    pub const LLMConfig = struct {
        /// LLM endpoint
        endpoint: []const u8 = "http://localhost:11434/api/generate",

        /// Model name
        model: []const u8 = "codellama",

        /// Temperature
        temperature: f32 = 0.2,

        /// Max tokens per request
        max_tokens: u32 = 2048,

        /// Timeout in seconds
        timeout: u32 = 30,

        /// Only use for blocks marked with @zid:llm_assist
        only_marked: bool = true,
    };

    pub const FeatureOverrides = struct {
        /// Force specific features on/off
        enable: []const []const u8 = &.{},
        disable: []const []const u8 = &.{},

        /// Passthrough features (keep as-is)
        passthrough: []const []const u8 = &.{},

        /// Features that should error if used
        forbidden: []const []const u8 = &.{},
    };

    pub const Export = struct {
        /// What to export (function/module name)
        name: []const u8,

        /// Export as different name
        as: ?[]const u8 = null,

        /// Visibility
        visibility: Visibility = .public,

        pub const Visibility = enum { public, internal };
    };

    pub const Binding = struct {
        /// Target language for bindings
        lang: []const u8,

        /// Output path
        output: []const u8,

        /// Include only specific exports
        include: []const []const u8 = &.{},

        /// Exclude specific exports
        exclude: []const []const u8 = &.{},
    };
};

/// Parse zid.yaml or zid.json
pub const ConfigParser = struct {
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) ConfigParser {
        return .{ .alloc = alloc };
    }

    /// Load config from file
    pub fn load(self: *ConfigParser, path: []const u8) !ProjectConfig {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.alloc, 1024 * 1024);

        // Detect format
        if (std.mem.endsWith(u8, path, ".json")) {
            return self.parseJson(content);
        } else if (std.mem.endsWith(u8, path, ".yaml") or std.mem.endsWith(u8, path, ".yml")) {
            return self.parseYaml(content);
        }

        return error.UnknownConfigFormat;
    }

    /// Find and load config from current directory
    pub fn loadDefault(self: *ConfigParser) !ProjectConfig {
        const config_files = [_][]const u8{
            "zid.yaml",
            "zid.yml",
            "zid.json",
        };

        for (config_files) |file| {
            if (self.load(file)) |config| {
                return config;
            } else |_| {
                continue;
            }
        }

        return ProjectConfig{}; // Default config
    }

    fn parseJson(self: *ConfigParser, content: []const u8) !ProjectConfig {
        _ = self;
        var config = ProjectConfig{};

        // Simple JSON parsing (real impl would use std.json)
        if (std.mem.indexOf(u8, content, "\"name\"")) |_| {
            // TODO: proper JSON parsing
        }

        return config;
    }

    fn parseYaml(self: *ConfigParser, content: []const u8) !ProjectConfig {
        var config = ProjectConfig{};
        var lines = std.mem.splitScalar(u8, content, '\n');

        var current_section: ?[]const u8 = null;
        var libs = std.ArrayList(ProjectConfig.LibDependency).init(self.alloc);
        var exports = std.ArrayList(ProjectConfig.Export).init(self.alloc);
        var bindings = std.ArrayList(ProjectConfig.Binding).init(self.alloc);

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Check for section
            if (!std.mem.startsWith(u8, trimmed, "  ") and !std.mem.startsWith(u8, trimmed, "-")) {
                if (std.mem.indexOf(u8, trimmed, ":")) |colon| {
                    const key = trimmed[0..colon];
                    const value = std.mem.trim(u8, trimmed[colon + 1 ..], " \t");

                    if (value.len == 0) {
                        current_section = key;
                    } else {
                        try self.setField(&config, key, value);
                    }
                }
            } else if (std.mem.startsWith(u8, trimmed, "  - ") and current_section != null) {
                // List item
                const item = trimmed[4..];
                if (std.mem.eql(u8, current_section.?, "libs")) {
                    try libs.append(.{ .name = item, .lang = "unknown" });
                } else if (std.mem.eql(u8, current_section.?, "exports")) {
                    try exports.append(.{ .name = item });
                }
            } else if (std.mem.startsWith(u8, trimmed, "  ")) {
                // Nested property
                const nested = std.mem.trim(u8, trimmed, " \t");
                if (std.mem.indexOf(u8, nested, ":")) |colon| {
                    const key = nested[0..colon];
                    const value = std.mem.trim(u8, nested[colon + 1 ..], " \t");

                    if (current_section) |section| {
                        if (std.mem.eql(u8, section, "llm")) {
                            if (config.llm == null) config.llm = .{};
                            try self.setLLMField(&config.llm.?, key, value);
                        } else if (std.mem.eql(u8, section, "features")) {
                            // Handle features
                        }
                    }
                }
            }
        }

        if (libs.items.len > 0) config.libs = try libs.toOwnedSlice();
        if (exports.items.len > 0) config.exports = try exports.toOwnedSlice();
        if (bindings.items.len > 0) config.bindings = try bindings.toOwnedSlice();

        return config;
    }

    fn setField(self: *ConfigParser, config: *ProjectConfig, key: []const u8, value: []const u8) !void {
        _ = self;
        if (std.mem.eql(u8, key, "name")) {
            config.name = value;
        } else if (std.mem.eql(u8, key, "version")) {
            config.version = value;
        } else if (std.mem.eql(u8, key, "lang")) {
            config.lang = value;
        } else if (std.mem.eql(u8, key, "target")) {
            config.target = value;
        } else if (std.mem.eql(u8, key, "src")) {
            config.src = value;
        } else if (std.mem.eql(u8, key, "out")) {
            config.out = value;
        } else if (std.mem.eql(u8, key, "entry")) {
            config.entry = value;
        } else if (std.mem.eql(u8, key, "mode")) {
            config.mode = std.meta.stringToEnum(ProjectConfig.Mode, value) orelse .ir;
        } else if (std.mem.eql(u8, key, "optimize")) {
            config.optimize = std.meta.stringToEnum(ProjectConfig.Optimize, value) orelse .default;
        }
    }

    fn setLLMField(self: *ConfigParser, llm: *ProjectConfig.LLMConfig, key: []const u8, value: []const u8) !void {
        _ = self;
        if (std.mem.eql(u8, key, "endpoint")) {
            llm.endpoint = value;
        } else if (std.mem.eql(u8, key, "model")) {
            llm.model = value;
        } else if (std.mem.eql(u8, key, "temperature")) {
            llm.temperature = std.fmt.parseFloat(f32, value) catch 0.2;
        } else if (std.mem.eql(u8, key, "max_tokens")) {
            llm.max_tokens = std.fmt.parseInt(u32, value, 10) catch 2048;
        } else if (std.mem.eql(u8, key, "timeout")) {
            llm.timeout = std.fmt.parseInt(u32, value, 10) catch 30;
        } else if (std.mem.eql(u8, key, "only_marked")) {
            llm.only_marked = std.mem.eql(u8, value, "true");
        }
    }
};

/// Generate default config file
pub fn generateDefault(alloc: std.mem.Allocator, format: enum { yaml, json }) ![]const u8 {
    var out = std.ArrayList(u8).init(alloc);
    const w = out.writer();

    if (format == .yaml) {
        try w.writeAll(
            \\# Zid Project Configuration
            \\
            \\name: my-project
            \\version: 0.1.0
            \\
            \\# Source language
            \\lang: lua
            \\
            \\# Target language(s)
            \\target: wat
            \\targets:
            \\  - wat
            \\  - rust
            \\
            \\# Directories
            \\src: src
            \\out: dist
            \\entry: main.lua
            \\
            \\# Compilation mode: direct, ir, hybrid
            \\mode: ir
            \\
            \\# Optimization: none, default, size, speed
            \\optimize: default
            \\
            \\# External libraries
            \\libs:
            \\  - name: wgpu
            \\    lang: rust
            \\    version: "0.19"
            \\    features:
            \\      - webgl
            \\      - vulkan
            \\
            \\  - name: raylib
            \\    lang: c
            \\    path: ./vendor/raylib
            \\
            \\# LLM configuration (only for @zid:llm_assist blocks)
            \\llm:
            \\  endpoint: http://localhost:11434/api/generate
            \\  model: codellama
            \\  temperature: 0.2
            \\  max_tokens: 2048
            \\  timeout: 30
            \\  only_marked: true  # IMPORTANT: only for marked blocks
            \\
            \\# Feature overrides
            \\features:
            \\  enable:
            \\    - closures
            \\  disable:
            \\    - threads  # Target doesn't support
            \\  passthrough:
            \\    - comments
            \\    - type_hints
            \\  forbidden:
            \\    - eval  # Security risk
            \\
            \\# Exports
            \\exports:
            \\  - name: main
            \\  - name: init
            \\    as: initialize
            \\
            \\# Generate bindings
            \\bindings:
            \\  - lang: c
            \\    output: bindings/myproject.h
            \\  - lang: python
            \\    output: bindings/myproject.pyi
            \\
        );
    } else {
        try w.writeAll(
            \\{
            \\  "name": "my-project",
            \\  "version": "0.1.0",
            \\  "lang": "lua",
            \\  "target": "wat",
            \\  "targets": ["wat", "rust"],
            \\  "src": "src",
            \\  "out": "dist",
            \\  "entry": "main.lua",
            \\  "mode": "ir",
            \\  "optimize": "default",
            \\  "libs": [
            \\    {
            \\      "name": "wgpu",
            \\      "lang": "rust",
            \\      "version": "0.19",
            \\      "features": ["webgl", "vulkan"]
            \\    },
            \\    {
            \\      "name": "raylib",
            \\      "lang": "c",
            \\      "path": "./vendor/raylib"
            \\    }
            \\  ],
            \\  "llm": {
            \\    "endpoint": "http://localhost:11434/api/generate",
            \\    "model": "codellama",
            \\    "temperature": 0.2,
            \\    "max_tokens": 2048,
            \\    "timeout": 30,
            \\    "only_marked": true
            \\  },
            \\  "features": {
            \\    "enable": ["closures"],
            \\    "disable": ["threads"],
            \\    "passthrough": ["comments", "type_hints"],
            \\    "forbidden": ["eval"]
            \\  },
            \\  "exports": [
            \\    { "name": "main" },
            \\    { "name": "init", "as": "initialize" }
            \\  ],
            \\  "bindings": [
            \\    { "lang": "c", "output": "bindings/myproject.h" },
            \\    { "lang": "python", "output": "bindings/myproject.pyi" }
            \\  ]
            \\}
            \\
        );
    }

    return out.toOwnedSlice();
}

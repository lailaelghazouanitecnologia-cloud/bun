const std = @import("std");

/// Language Metadata
/// Describes the capabilities and features of a programming language.
/// Used to determine compatibility and required transformations.
pub const Metadata = struct {
    /// Language name
    name: []const u8 = "unknown",

    /// File extensions
    extensions: []const []const u8 = &.{},

    /// Language features
    features: Features = .{},

    /// Paradigms supported
    paradigms: Paradigms = .{},

    /// Type system
    types: Types = .{},

    /// Memory model
    memory: Memory = .{},

    pub const Features = struct {
        // Functions
        first_class_functions: bool = false,
        closures: bool = false,
        generators: bool = false,
        async_await: bool = false,
        coroutines: bool = false,

        // Types
        static_typing: bool = false,
        dynamic_typing: bool = false,
        gradual_typing: bool = false,
        generics: bool = false,
        type_inference: bool = false,

        // Control flow
        pattern_matching: bool = false,
        exceptions: bool = false,
        result_types: bool = false,
        optionals: bool = false,

        // Data structures
        tables: bool = false,
        arrays: bool = false,
        maps: bool = false,
        tuples: bool = false,
        structs: bool = false,
        classes: bool = false,
        enums: bool = false,
        unions: bool = false,

        // Memory
        garbage_collection: bool = false,
        manual_memory: bool = false,
        linear_memory: bool = false,
        reference_counting: bool = false,

        // Metaprogramming
        macros: bool = false,
        reflection: bool = false,
        comptime: bool = false,
    };

    pub const Paradigms = struct {
        functional: bool = false,
        imperative: bool = false,
        object_oriented: bool = false,
        procedural: bool = false,
    };

    pub const Types = struct {
        integers: []const []const u8 = &.{},
        floats: []const []const u8 = &.{},
        strings: []const []const u8 = &.{},
        booleans: []const []const u8 = &.{},
    };

    pub const Memory = struct {
        stack_allocated: bool = false,
        heap_allocated: bool = false,
        linear_memory: bool = false,
    };

    /// Check if a feature is supported
    pub fn hasFeature(self: Metadata, feature: Feature) bool {
        return switch (feature) {
            .first_class_functions => self.features.first_class_functions,
            .closures => self.features.closures,
            .generators => self.features.generators,
            .async_await => self.features.async_await,
            .static_typing => self.features.static_typing,
            .dynamic_typing => self.features.dynamic_typing,
            .generics => self.features.generics,
            .pattern_matching => self.features.pattern_matching,
            .exceptions => self.features.exceptions,
            .tables => self.features.tables,
            .garbage_collection => self.features.garbage_collection,
            .manual_memory => self.features.manual_memory,
            .macros => self.features.macros,
            .comptime => self.features.comptime,
        };
    }

    /// Check if this language can transpile to target
    pub fn canTranspileTo(self: Metadata, target: Metadata) Compatibility {
        var missing = std.ArrayList(Feature).init(std.heap.page_allocator);
        var transforms = std.ArrayList(Transform).init(std.heap.page_allocator);

        // Check each feature we use
        inline for (std.meta.fields(Features)) |field| {
            const source_has = @field(self.features, field.name);
            const target_has = @field(target.features, field.name);

            if (source_has and !target_has) {
                const feature = std.meta.stringToEnum(Feature, field.name) orelse continue;

                // Check if there's a known transformation
                if (getTransform(feature)) |transform| {
                    transforms.append(transform) catch {};
                } else {
                    missing.append(feature) catch {};
                }
            }
        }

        return .{
            .compatible = missing.items.len == 0,
            .missing_features = missing.toOwnedSlice() catch &.{},
            .required_transforms = transforms.toOwnedSlice() catch &.{},
        };
    }
};

/// Feature enumeration
pub const Feature = enum {
    first_class_functions,
    closures,
    generators,
    async_await,
    static_typing,
    dynamic_typing,
    generics,
    pattern_matching,
    exceptions,
    tables,
    garbage_collection,
    manual_memory,
    macros,
    comptime,
};

/// Transformation for unsupported features
pub const Transform = struct {
    feature: Feature,
    strategy: Strategy,
    description: []const u8,

    pub const Strategy = enum {
        emulate,    // Emulate the feature
        simplify,   // Simplify to supported subset
        polyfill,   // Add runtime support
        remove,     // Remove (with warning)
        error,      // Error out
    };
};

/// Compatibility result
pub const Compatibility = struct {
    compatible: bool,
    missing_features: []const Feature,
    required_transforms: []const Transform,
};

/// Known transformations for common feature gaps
fn getTransform(feature: Feature) ?Transform {
    return switch (feature) {
        .closures => Transform{
            .feature = .closures,
            .strategy = .emulate,
            .description = "Convert closures to explicit state passing",
        },
        .exceptions => Transform{
            .feature = .exceptions,
            .strategy = .emulate,
            .description = "Convert exceptions to result types",
        },
        .generators => Transform{
            .feature = .generators,
            .strategy = .emulate,
            .description = "Convert generators to state machines",
        },
        .garbage_collection => Transform{
            .feature = .garbage_collection,
            .strategy = .polyfill,
            .description = "Add reference counting or arena allocator",
        },
        else => null,
    };
}

// ============ Predefined Language Metadata ============

pub const lua = Metadata{
    .name = "lua",
    .extensions = &.{ ".lua", ".luau" },
    .features = .{
        .first_class_functions = true,
        .closures = true,
        .dynamic_typing = true,
        .tables = true,
        .garbage_collection = true,
        .coroutines = true,
    },
    .paradigms = .{
        .functional = true,
        .imperative = true,
        .procedural = true,
    },
};

pub const rust = Metadata{
    .name = "rust",
    .extensions = &.{".rs"},
    .features = .{
        .first_class_functions = true,
        .closures = true,
        .generators = false,
        .async_await = true,
        .static_typing = true,
        .generics = true,
        .type_inference = true,
        .pattern_matching = true,
        .result_types = true,
        .optionals = true,
        .structs = true,
        .enums = true,
        .manual_memory = true,
        .macros = true,
    },
    .paradigms = .{
        .functional = true,
        .imperative = true,
    },
};

pub const zig = Metadata{
    .name = "zig",
    .extensions = &.{".zig"},
    .features = .{
        .first_class_functions = true,
        .closures = false,
        .static_typing = true,
        .generics = true,
        .optionals = true,
        .structs = true,
        .enums = true,
        .unions = true,
        .manual_memory = true,
        .comptime = true,
    },
    .paradigms = .{
        .imperative = true,
        .procedural = true,
    },
};

pub const wat = Metadata{
    .name = "wat",
    .extensions = &.{ ".wat", ".wasm" },
    .features = .{
        .static_typing = true,
    },
    .memory = .{
        .linear_memory = true,
    },
};

pub const javascript = Metadata{
    .name = "javascript",
    .extensions = &.{ ".js", ".mjs", ".cjs" },
    .features = .{
        .first_class_functions = true,
        .closures = true,
        .generators = true,
        .async_await = true,
        .dynamic_typing = true,
        .exceptions = true,
        .classes = true,
        .garbage_collection = true,
    },
    .paradigms = .{
        .functional = true,
        .imperative = true,
        .object_oriented = true,
    },
};

pub const python = Metadata{
    .name = "python",
    .extensions = &.{".py"},
    .features = .{
        .first_class_functions = true,
        .closures = true,
        .generators = true,
        .async_await = true,
        .dynamic_typing = true,
        .gradual_typing = true,
        .exceptions = true,
        .classes = true,
        .garbage_collection = true,
    },
    .paradigms = .{
        .functional = true,
        .imperative = true,
        .object_oriented = true,
    },
};

/// Get metadata for a language by name
pub fn get(name: []const u8) ?Metadata {
    const map = std.StaticStringMap(Metadata).initComptime(.{
        .{ "lua", lua },
        .{ "rust", rust },
        .{ "zig", zig },
        .{ "wat", wat },
        .{ "wasm", wat },
        .{ "javascript", javascript },
        .{ "js", javascript },
        .{ "python", python },
        .{ "py", python },
    });
    return map.get(name);
}

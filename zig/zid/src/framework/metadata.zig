//! Metadata - Language capabilities

const std = @import("std");

pub const Metadata = struct {
    name: []const u8,
    extensions: []const []const u8 = &.{},
    features: Features = .{},

    pub const Features = struct {
        closures: bool = false,
        generics: bool = false,
        async_await: bool = false,
        pattern_match: bool = false,
        gc: bool = false,
    };
};

// Predefined languages
pub const lua = Metadata{
    .name = "lua",
    .extensions = &.{ ".lua", ".luau" },
    .features = .{ .closures = true, .gc = true },
};

pub const rust = Metadata{
    .name = "rust",
    .extensions = &.{".rs"},
    .features = .{ .closures = true, .generics = true, .pattern_match = true, .async_await = true },
};

pub const zig = Metadata{
    .name = "zig",
    .extensions = &.{".zig"},
    .features = .{ .generics = true },
};

pub const wat = Metadata{
    .name = "wat",
    .extensions = &.{ ".wat", ".wasm" },
};

pub fn get(name: []const u8) ?Metadata {
    const map = std.StaticStringMap(Metadata).initComptime(.{
        .{ "lua", lua },
        .{ "rust", rust },
        .{ "zig", zig },
        .{ "wat", wat },
        .{ "wasm", wat },
    });
    return map.get(name);
}

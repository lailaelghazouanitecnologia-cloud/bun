//! Pipeline - Transformation chain

const std = @import("std");

pub const Pipeline = struct {
    input: []const u8 = "src/*",
    output: []const u8 = "dist/",
    steps: []const Step = &.{},

    pub fn run(self: Pipeline, alloc: std.mem.Allocator) !void {
        _ = alloc;
        for (self.steps) |step| {
            _ = step;
            // TODO: Execute step
        }
    }
};

pub const Step = struct {
    name: []const u8,
    func: *const fn ([]const u8) anyerror![]const u8,
};

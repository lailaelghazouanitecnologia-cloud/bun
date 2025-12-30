//! Dispatch - VM-like opcode execution system
//!
//! Pattern from Bun's H2 frame parser dispatch.
//! Uses comptime for zero-overhead event dispatch.
//!
//! Usage:
//!   const VM = Dispatch(Op, Context, Result);
//!   var vm = VM.init(&ctx);
//!   const result = vm.exec(.parse, input);

const std = @import("std");
const Maybe = @import("maybe.zig").Maybe;
const Error = @import("maybe.zig").Error;

/// Create a dispatch table for opcodes
pub fn Dispatch(
    comptime Op: type, // Opcode enum
    comptime Ctx: type, // Context type
    comptime Result: type, // Result type
) type {
    return struct {
        ctx: *Ctx,
        ip: usize = 0, // instruction pointer
        err: ?Error = null, // current error (can be set by handlers)

        const Self = @This();

        pub fn init(ctx: *Ctx) Self {
            return .{ .ctx = ctx };
        }

        /// Execute single opcode
        pub fn exec(self: *Self, comptime op: Op, input: anytype) Maybe(Result) {
            // Get handler at comptime
            const handler = comptime getHandler(op);

            // Execute with error capture
            self.err = null;
            const result = handler(self.ctx, input) catch |e| {
                if (self.err) |stored| {
                    return .{ .err = stored };
                }
                return .{ .err = Error.from(e, opToStep(op), "") };
            };

            self.ip += 1;
            return .{ .ok = result };
        }

        /// Execute sequence of opcodes
        pub fn execSeq(self: *Self, comptime ops: []const Op, input: anytype) Maybe(Result) {
            var current = input;
            inline for (ops) |op| {
                switch (self.exec(op, current)) {
                    .ok => |v| current = v,
                    .err => |e| return .{ .err = e },
                }
            }
            return .{ .ok = current };
        }

        /// Set error (called from handlers)
        pub fn setError(self: *Self, code: Error.Code, msg: []const u8) void {
            self.err = .{ .code = code, .message = msg };
        }

        fn getHandler(comptime op: Op) fn (*Ctx, anytype) anyerror!Result {
            // Handlers must be defined in Ctx as: fn handle_<opname>
            const name = "handle_" ++ @tagName(op);
            if (@hasDecl(Ctx, name)) {
                return @field(Ctx, name);
            }
            @compileError("Missing handler: " ++ name);
        }

        fn opToStep(op: Op) Error.Step {
            // Map opcode to error step
            return switch (@tagName(op)[0]) {
                'l' => .lex,
                'p' => .parse,
                'e' => .emit,
                'r' => .resolve,
                else => .unknown,
            };
        }
    };
}

/// Simple opcode enum for pipelines
pub const PipelineOp = enum {
    lex,
    parse,
    transform,
    emit,
    write,
};

/// Instruction for bytecode-style execution
pub const Instruction = struct {
    op: u8,
    a: u16 = 0, // operand A
    b: u16 = 0, // operand B
    c: u16 = 0, // operand C

    pub fn decode(bytes: []const u8) Instruction {
        return .{
            .op = bytes[0],
            .a = std.mem.readInt(u16, bytes[1..3], .little),
            .b = std.mem.readInt(u16, bytes[3..5], .little),
            .c = std.mem.readInt(u16, bytes[5..7], .little),
        };
    }

    pub fn encode(self: Instruction) [7]u8 {
        var out: [7]u8 = undefined;
        out[0] = self.op;
        std.mem.writeInt(u16, out[1..3], self.a, .little);
        std.mem.writeInt(u16, out[3..5], self.b, .little);
        std.mem.writeInt(u16, out[5..7], self.c, .little);
        return out;
    }
};

/// Frame for call stack
pub const Frame = struct {
    ip: usize, // instruction pointer
    bp: usize, // base pointer
    ret: usize, // return address
};

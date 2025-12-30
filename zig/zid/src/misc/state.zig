//! State - Union-based state machines
//!
//! Pattern from Bun's shell/states/Cmd.zig.
//! Each state carries only relevant data. Compiler ensures exhaustive handling.
//!
//! Usage:
//!   var machine = StateMachine.init(.idle);
//!   machine.transition(.parsing, .{ .tokens = tokens });
//!   switch (machine.state) {
//!       .idle => {},
//!       .parsing => |ctx| processTokens(ctx.tokens),
//!   }

const std = @import("std");

/// Generic state machine builder
pub fn StateMachine(comptime States: type) type {
    return struct {
        state: States,
        prev: ?States = null,
        transitions: u32 = 0,

        const Self = @This();

        pub fn init(initial: States) Self {
            return .{ .state = initial };
        }

        /// Transition to new state
        pub fn transition(self: *Self, new_state: States) void {
            self.prev = self.state;
            self.state = new_state;
            self.transitions += 1;
        }

        /// Check current state
        pub fn is(self: Self, comptime check: @typeInfo(States).@"union".tag_type.?) bool {
            return self.state == check;
        }

        /// Get data for current state (if matches)
        pub fn get(self: Self, comptime tag: @typeInfo(States).@"union".tag_type.?) ?@TypeOf(tag) {
            if (@as(@typeInfo(States).@"union".tag_type.?, self.state) == tag) {
                return @field(self.state, @tagName(tag));
            }
            return null;
        }

        fn TypeOf(comptime tag: @typeInfo(States).@"union".tag_type.?) type {
            const fields = @typeInfo(States).@"union".fields;
            inline for (fields) |f| {
                if (std.mem.eql(u8, f.name, @tagName(tag))) {
                    return f.type;
                }
            }
            unreachable;
        }
    };
}

// ============ Example: Pipeline State Machine ============

/// Pipeline execution states
pub const PipelineState = union(enum) {
    idle: void,
    reading: struct {
        path: []const u8,
        offset: usize,
    },
    lexing: struct {
        source: []const u8,
        pos: usize,
    },
    parsing: struct {
        tokens: []const Token,
        index: usize,
    },
    emitting: struct {
        ast: *const AST,
    },
    writing: struct {
        path: []const u8,
        data: []const u8,
    },
    done: struct {
        output_path: []const u8,
    },
    failed: struct {
        step: Step,
        message: []const u8,
    },

    pub const Step = enum { read, lex, parse, emit, write };

    // Placeholder types
    pub const Token = struct { kind: u8, text: []const u8 };
    pub const AST = struct {};
};

pub const Pipeline = StateMachine(PipelineState);

// ============ Example: Command State Machine ============

/// Command execution states (like Bun's shell Cmd)
pub const CmdState = union(enum) {
    idle: void,
    expanding_args: struct {
        args: []const []const u8,
        index: u32,
        expanded: std.ArrayList([]const u8),
    },
    executing: struct {
        pid: ?std.process.Child.Id,
    },
    waiting: struct {
        start_time: i64,
    },
    done: struct {
        exit_code: u8,
        stdout: ?[]const u8,
        stderr: ?[]const u8,
    },
};

pub const Cmd = StateMachine(CmdState);

// ============ Async State for Event Loop ============

/// Async operation states
pub const AsyncState = union(enum) {
    pending: void,
    running: struct {
        started: i64,
    },
    completed: struct {
        result: []const u8,
    },
    failed: struct {
        code: u16,
        message: []const u8,
    },
    cancelled: void,

    pub fn isPending(self: AsyncState) bool {
        return self == .pending;
    }

    pub fn isDone(self: AsyncState) bool {
        return self == .completed or self == .failed or self == .cancelled;
    }
};

// ============ Transition Builder ============

/// Builder for valid state transitions
pub fn TransitionTable(comptime S: type) type {
    const Tag = @typeInfo(S).@"union".tag_type.?;
    const tag_count = @typeInfo(Tag).@"enum".fields.len;

    return struct {
        valid: [tag_count]std.bit_set.IntegerBitSet(tag_count) = [_]std.bit_set.IntegerBitSet(tag_count){.{}} ** tag_count,

        const Self = @This();

        pub fn allow(self: *Self, from: Tag, to: Tag) *Self {
            self.valid[@intFromEnum(from)].set(@intFromEnum(to));
            return self;
        }

        pub fn canTransition(self: Self, from: Tag, to: Tag) bool {
            return self.valid[@intFromEnum(from)].isSet(@intFromEnum(to));
        }
    };
}

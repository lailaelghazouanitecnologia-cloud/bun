//! Intermediate Representation (IR)
//!
//! A common IR format for building transpilers. Provides:
//! - Node types for expressions, statements, declarations
//! - Source locations for error reporting
//! - Type information for semantic analysis
//! - Visitor pattern for transformations
//!
//! Example usage:
//! ```zig
//! const ir = @import("zid").ir;
//!
//! // Build IR from parsed source
//! var builder = ir.Builder.init(allocator);
//! const func = builder.function("main", &.{}, .void);
//! builder.addStmt(func, builder.returnStmt(builder.intLiteral(0)));
//! ```

const std = @import("std");

/// Source location for error reporting
pub const Location = struct {
    file: []const u8 = "",
    line: u32 = 0,
    column: u32 = 0,
    offset: u32 = 0,
    length: u32 = 0,

    pub fn format(self: Location, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}:{d}:{d}", .{ self.file, self.line, self.column });
    }
};

/// Span from start to end location
pub const Span = struct {
    start: Location,
    end: Location,
};

/// Node reference (index into node array)
pub const NodeRef = u32;
pub const null_ref: NodeRef = std.math.maxInt(NodeRef);

/// IR Node - all expressions and statements
pub const Node = struct {
    tag: Tag,
    loc: Location,
    data: Data,

    pub const Tag = enum(u8) {
        // Literals
        int_literal,
        float_literal,
        string_literal,
        bool_literal,
        null_literal,

        // Identifiers
        identifier,
        qualified_name,

        // Operators
        binary_op,
        unary_op,
        ternary,

        // Access
        member_access,
        index_access,
        call,

        // Declarations
        var_decl,
        const_decl,
        func_decl,
        param_decl,
        type_decl,
        struct_decl,
        enum_decl,

        // Statements
        block,
        if_stmt,
        while_stmt,
        for_stmt,
        for_in_stmt,
        return_stmt,
        break_stmt,
        continue_stmt,
        expr_stmt,
        assign_stmt,

        // Types
        type_ref,
        array_type,
        optional_type,
        pointer_type,
        func_type,

        // Special
        comment,
        directive,
        error_node,
    };

    pub const Data = union {
        int: i64,
        float: f64,
        str: []const u8,
        boolean: bool,
        unary: struct {
            op: UnaryOp,
            operand: NodeRef,
        },
        binary: struct {
            op: BinaryOp,
            lhs: NodeRef,
            rhs: NodeRef,
        },
        call: struct {
            callee: NodeRef,
            args_start: u32,
            args_count: u32,
        },
        func: struct {
            name: []const u8,
            params_start: u32,
            params_count: u32,
            return_type: NodeRef,
            body: NodeRef,
        },
        var_decl: struct {
            name: []const u8,
            type_node: NodeRef,
            init: NodeRef,
            is_mutable: bool,
        },
        if_stmt: struct {
            condition: NodeRef,
            then_branch: NodeRef,
            else_branch: NodeRef,
        },
        loop: struct {
            init: NodeRef,
            condition: NodeRef,
            update: NodeRef,
            body: NodeRef,
        },
        block: struct {
            stmts_start: u32,
            stmts_count: u32,
        },
        single: NodeRef,
        none: void,
    };
};

/// Binary operators
pub const BinaryOp = enum {
    // Arithmetic
    add,
    sub,
    mul,
    div,
    mod,
    // Comparison
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    // Logical
    @"and",
    @"or",
    // Bitwise
    bit_and,
    bit_or,
    bit_xor,
    shl,
    shr,
    // Assignment
    assign,
    add_assign,
    sub_assign,
    mul_assign,
    div_assign,
};

/// Unary operators
pub const UnaryOp = enum {
    neg,
    not,
    bit_not,
    deref,
    addr_of,
    try_op,
    optional,
};

/// Type information
pub const Type = struct {
    tag: TypeTag,
    data: TypeData,

    pub const TypeTag = enum {
        void,
        bool,
        int,
        uint,
        float,
        string,
        array,
        slice,
        optional,
        pointer,
        function,
        struct_type,
        enum_type,
        any,
        error_type,
    };

    pub const TypeData = union {
        int_bits: u8, // 8, 16, 32, 64
        float_bits: u8, // 32, 64
        element: *const Type, // array, slice, optional, pointer
        func: struct {
            params: []const Type,
            ret: *const Type,
        },
        none: void,
    };

    // Common types
    pub const void_type = Type{ .tag = .void, .data = .{ .none = {} } };
    pub const bool_type = Type{ .tag = .bool, .data = .{ .none = {} } };
    pub const i32_type = Type{ .tag = .int, .data = .{ .int_bits = 32 } };
    pub const i64_type = Type{ .tag = .int, .data = .{ .int_bits = 64 } };
    pub const f32_type = Type{ .tag = .float, .data = .{ .float_bits = 32 } };
    pub const f64_type = Type{ .tag = .float, .data = .{ .float_bits = 64 } };
    pub const string_type = Type{ .tag = .string, .data = .{ .none = {} } };
    pub const any_type = Type{ .tag = .any, .data = .{ .none = {} } };
};

/// IR Builder - construct IR nodes
pub const Builder = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    extra: std.ArrayList(NodeRef),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(Node).init(allocator),
            .extra = std.ArrayList(NodeRef).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.nodes.deinit();
        self.extra.deinit();
    }

    /// Get node by reference
    pub fn get(self: *Self, ref: NodeRef) *Node {
        return &self.nodes.items[ref];
    }

    /// Add a node and return its reference
    fn addNode(self: *Self, node: Node) NodeRef {
        const ref: NodeRef = @intCast(self.nodes.items.len);
        self.nodes.append(node) catch return null_ref;
        return ref;
    }

    // ============ Literals ============

    pub fn intLiteral(self: *Self, value: i64) NodeRef {
        return self.addNode(.{
            .tag = .int_literal,
            .loc = .{},
            .data = .{ .int = value },
        });
    }

    pub fn floatLiteral(self: *Self, value: f64) NodeRef {
        return self.addNode(.{
            .tag = .float_literal,
            .loc = .{},
            .data = .{ .float = value },
        });
    }

    pub fn stringLiteral(self: *Self, value: []const u8) NodeRef {
        return self.addNode(.{
            .tag = .string_literal,
            .loc = .{},
            .data = .{ .str = value },
        });
    }

    pub fn boolLiteral(self: *Self, value: bool) NodeRef {
        return self.addNode(.{
            .tag = .bool_literal,
            .loc = .{},
            .data = .{ .boolean = value },
        });
    }

    pub fn nullLiteral(self: *Self) NodeRef {
        return self.addNode(.{
            .tag = .null_literal,
            .loc = .{},
            .data = .{ .none = {} },
        });
    }

    // ============ Identifiers ============

    pub fn identifier(self: *Self, name: []const u8) NodeRef {
        return self.addNode(.{
            .tag = .identifier,
            .loc = .{},
            .data = .{ .str = name },
        });
    }

    // ============ Operators ============

    pub fn binary(self: *Self, op: BinaryOp, lhs: NodeRef, rhs: NodeRef) NodeRef {
        return self.addNode(.{
            .tag = .binary_op,
            .loc = .{},
            .data = .{ .binary = .{ .op = op, .lhs = lhs, .rhs = rhs } },
        });
    }

    pub fn unary(self: *Self, op: UnaryOp, operand: NodeRef) NodeRef {
        return self.addNode(.{
            .tag = .unary_op,
            .loc = .{},
            .data = .{ .unary = .{ .op = op, .operand = operand } },
        });
    }

    // ============ Declarations ============

    pub fn varDecl(self: *Self, name: []const u8, type_node: NodeRef, init_value: NodeRef, is_mutable: bool) NodeRef {
        return self.addNode(.{
            .tag = if (is_mutable) .var_decl else .const_decl,
            .loc = .{},
            .data = .{ .var_decl = .{
                .name = name,
                .type_node = type_node,
                .init = init_value,
                .is_mutable = is_mutable,
            } },
        });
    }

    pub fn funcDecl(self: *Self, name: []const u8, params: []const NodeRef, ret_type: NodeRef, body: NodeRef) NodeRef {
        const params_start: u32 = @intCast(self.extra.items.len);
        for (params) |p| {
            self.extra.append(p) catch {};
        }
        return self.addNode(.{
            .tag = .func_decl,
            .loc = .{},
            .data = .{ .func = .{
                .name = name,
                .params_start = params_start,
                .params_count = @intCast(params.len),
                .return_type = ret_type,
                .body = body,
            } },
        });
    }

    // ============ Statements ============

    pub fn block(self: *Self, stmts: []const NodeRef) NodeRef {
        const stmts_start: u32 = @intCast(self.extra.items.len);
        for (stmts) |s| {
            self.extra.append(s) catch {};
        }
        return self.addNode(.{
            .tag = .block,
            .loc = .{},
            .data = .{ .block = .{
                .stmts_start = stmts_start,
                .stmts_count = @intCast(stmts.len),
            } },
        });
    }

    pub fn ifStmt(self: *Self, condition: NodeRef, then_branch: NodeRef, else_branch: NodeRef) NodeRef {
        return self.addNode(.{
            .tag = .if_stmt,
            .loc = .{},
            .data = .{ .if_stmt = .{
                .condition = condition,
                .then_branch = then_branch,
                .else_branch = else_branch,
            } },
        });
    }

    pub fn whileStmt(self: *Self, condition: NodeRef, body: NodeRef) NodeRef {
        return self.addNode(.{
            .tag = .while_stmt,
            .loc = .{},
            .data = .{ .loop = .{
                .init = null_ref,
                .condition = condition,
                .update = null_ref,
                .body = body,
            } },
        });
    }

    pub fn forStmt(self: *Self, init_node: NodeRef, condition: NodeRef, update: NodeRef, body: NodeRef) NodeRef {
        return self.addNode(.{
            .tag = .for_stmt,
            .loc = .{},
            .data = .{ .loop = .{
                .init = init_node,
                .condition = condition,
                .update = update,
                .body = body,
            } },
        });
    }

    pub fn returnStmt(self: *Self, value: NodeRef) NodeRef {
        return self.addNode(.{
            .tag = .return_stmt,
            .loc = .{},
            .data = .{ .single = value },
        });
    }

    pub fn exprStmt(self: *Self, expr: NodeRef) NodeRef {
        return self.addNode(.{
            .tag = .expr_stmt,
            .loc = .{},
            .data = .{ .single = expr },
        });
    }

    // ============ Calls ============

    pub fn call(self: *Self, callee: NodeRef, args: []const NodeRef) NodeRef {
        const args_start: u32 = @intCast(self.extra.items.len);
        for (args) |a| {
            self.extra.append(a) catch {};
        }
        return self.addNode(.{
            .tag = .call,
            .loc = .{},
            .data = .{ .call = .{
                .callee = callee,
                .args_start = args_start,
                .args_count = @intCast(args.len),
            } },
        });
    }

    // ============ Access ============

    pub fn memberAccess(self: *Self, object: NodeRef, member: []const u8) NodeRef {
        const member_ref = self.identifier(member);
        return self.addNode(.{
            .tag = .member_access,
            .loc = .{},
            .data = .{ .binary = .{
                .op = .add, // Unused
                .lhs = object,
                .rhs = member_ref,
            } },
        });
    }

    pub fn indexAccess(self: *Self, object: NodeRef, index: NodeRef) NodeRef {
        return self.addNode(.{
            .tag = .index_access,
            .loc = .{},
            .data = .{ .binary = .{
                .op = .add, // Unused
                .lhs = object,
                .rhs = index,
            } },
        });
    }
};

/// Visitor pattern for IR transformations
pub fn Visitor(comptime Context: type) type {
    return struct {
        context: Context,
        visit_fn: *const fn (Context, *Node) void,

        const Self = @This();

        pub fn visit(self: *Self, builder: *Builder, ref: NodeRef) void {
            if (ref == null_ref) return;
            const node = builder.get(ref);
            self.visit_fn(self.context, node);

            // Visit children based on node type
            switch (node.tag) {
                .binary_op => {
                    self.visit(builder, node.data.binary.lhs);
                    self.visit(builder, node.data.binary.rhs);
                },
                .unary_op => {
                    self.visit(builder, node.data.unary.operand);
                },
                .if_stmt => {
                    self.visit(builder, node.data.if_stmt.condition);
                    self.visit(builder, node.data.if_stmt.then_branch);
                    self.visit(builder, node.data.if_stmt.else_branch);
                },
                .while_stmt, .for_stmt => {
                    self.visit(builder, node.data.loop.init);
                    self.visit(builder, node.data.loop.condition);
                    self.visit(builder, node.data.loop.update);
                    self.visit(builder, node.data.loop.body);
                },
                .return_stmt, .expr_stmt => {
                    self.visit(builder, node.data.single);
                },
                .block => {
                    const start = node.data.block.stmts_start;
                    const count = node.data.block.stmts_count;
                    for (builder.extra.items[start .. start + count]) |stmt| {
                        self.visit(builder, stmt);
                    }
                },
                .call => {
                    self.visit(builder, node.data.call.callee);
                    const start = node.data.call.args_start;
                    const count = node.data.call.args_count;
                    for (builder.extra.items[start .. start + count]) |arg| {
                        self.visit(builder, arg);
                    }
                },
                .func_decl => {
                    self.visit(builder, node.data.func.body);
                },
                .var_decl, .const_decl => {
                    self.visit(builder, node.data.var_decl.type_node);
                    self.visit(builder, node.data.var_decl.init);
                },
                else => {},
            }
        }
    };
}

/// Print IR for debugging
pub fn print(builder: *Builder, writer: anytype) !void {
    for (builder.nodes.items, 0..) |node, i| {
        try writer.print("[{d}] {s}", .{ i, @tagName(node.tag) });
        switch (node.tag) {
            .int_literal => try writer.print(" = {d}", .{node.data.int}),
            .float_literal => try writer.print(" = {d}", .{node.data.float}),
            .string_literal, .identifier => try writer.print(" = \"{s}\"", .{node.data.str}),
            .bool_literal => try writer.print(" = {}", .{node.data.boolean}),
            .binary_op => try writer.print(" {s} [{d}, {d}]", .{
                @tagName(node.data.binary.op),
                node.data.binary.lhs,
                node.data.binary.rhs,
            }),
            .unary_op => try writer.print(" {s} [{d}]", .{
                @tagName(node.data.unary.op),
                node.data.unary.operand,
            }),
            .func_decl => try writer.print(" {s}() -> body[{d}]", .{
                node.data.func.name,
                node.data.func.body,
            }),
            else => {},
        }
        try writer.print("\n", .{});
    }
}

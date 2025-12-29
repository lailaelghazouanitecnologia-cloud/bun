const std = @import("std");
const ir_types = @import("../ir/types.zig");
const ir_nodes = @import("../ir/nodes.zig");

const Type = ir_types.Type;
const Node = ir_nodes.Node;

/// IR → WAT Lower
/// Converts universal IR to WebAssembly text format
pub const WatLower = struct {
    out: std.ArrayList(u8),
    alloc: std.mem.Allocator,
    indent: u32 = 0,
    locals: std.StringHashMap(LocalInfo),
    local_count: u32 = 0,
    label_count: u32 = 0,
    in_function: bool = false,

    const LocalInfo = struct {
        index: u32,
        wat_type: []const u8,
    };

    pub fn init(alloc: std.mem.Allocator) WatLower {
        return .{
            .out = std.ArrayList(u8).init(alloc),
            .alloc = alloc,
            .locals = std.StringHashMap(LocalInfo).init(alloc),
        };
    }

    pub fn deinit(self: *WatLower) void {
        self.out.deinit();
        self.locals.deinit();
    }

    /// Lower IR to WAT string
    pub fn lower(self: *WatLower, ir: Node) ![]const u8 {
        try self.lowerNode(ir);
        return self.out.items;
    }

    fn lowerNode(self: *WatLower, node: Node) !void {
        switch (node) {
            .module => |m| try self.lowerModule(m),
            .func => |f| try self.lowerFunc(f),
            .block => |b| try self.lowerBlock(b),
            .let => |l| try self.lowerLet(l),
            .assign => |a| try self.lowerAssign(a),
            .return_ => |r| try self.lowerReturn(r),
            .if_ => |i| try self.lowerIf(i),
            .while_ => |w| try self.lowerWhile(w),
            .for_ => |f| try self.lowerFor(f),
            .loop_ => |l| try self.lowerLoop(l),
            .break_ => try self.lowerBreak(),
            .continue_ => try self.lowerContinue(),
            .binary => |b| try self.lowerBinary(b),
            .unary => |u| try self.lowerUnary(u),
            .call => |c| try self.lowerCall(c),
            .method_call => |m| try self.lowerMethodCall(m),
            .field => |f| try self.lowerField(f),
            .index => |i| try self.lowerIndex(i),
            .cast => |c| try self.lowerCast(c),
            .ident => |i| try self.lowerIdent(i),
            .int_lit => |i| try self.lowerInt(i),
            .float_lit => |f| try self.lowerFloat(f),
            .bool_lit => |b| try self.lowerBool(b),
            .string_lit => |s| try self.lowerString(s),
            .expr_stmt => |e| try self.lowerNode(e.expr.*),
            else => {},
        }
    }

    fn lowerModule(self: *WatLower, mod: ir_nodes.Module) !void {
        try self.p("(module", .{});
        try self.newline();
        self.indent += 1;

        // Memory declaration
        try self.p("(memory 1)", .{});
        try self.newline();

        // Emit all items
        for (mod.items) |item| {
            try self.lowerNode(item);
        }

        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();
    }

    fn lowerFunc(self: *WatLower, func: ir_nodes.Func) !void {
        // Reset locals for new function
        self.locals.clearRetainingCapacity();
        self.local_count = 0;
        self.in_function = true;

        // Build param string and collect local info
        var params_buf = std.ArrayList(u8).init(self.alloc);
        defer params_buf.deinit();

        for (func.params) |param| {
            const wat_type = self.typeToWat(param.typ);
            try params_buf.writer().print(" (param ${s} {s})", .{ param.name, wat_type });
            try self.locals.put(param.name, .{
                .index = self.local_count,
                .wat_type = wat_type,
            });
            self.local_count += 1;
        }

        // Determine return type
        const ret_type = if (func.ret_type) |t| self.typeToWat(t.*) else "i32";

        try self.p("(func ${s}{s} (result {s})", .{ func.name, params_buf.items, ret_type });
        try self.newline();
        self.indent += 1;

        // Pre-scan for local declarations in body
        if (func.body) |body| {
            try self.collectLocals(body.*);
        }

        // Emit local declarations
        var it = self.locals.iterator();
        while (it.next()) |entry| {
            // Skip params (already declared)
            if (entry.value_ptr.index < func.params.len) continue;
            try self.p("(local ${s} {s})", .{ entry.key_ptr.*, entry.value_ptr.wat_type });
            try self.newline();
        }

        // Emit body
        if (func.body) |body| {
            try self.lowerNode(body.*);
        }

        // Default return if no explicit return
        try self.p("{s}.const 0", .{ret_type[0..3]});
        try self.newline();

        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();

        // Export function
        if (func.is_pub or !func.is_extern) {
            try self.p("(export \"{s}\" (func ${s}))", .{ func.name, func.name });
            try self.newline();
        }

        self.in_function = false;
    }

    fn collectLocals(self: *WatLower, node: Node) !void {
        switch (node) {
            .block => |b| {
                for (b.stmts) |stmt| {
                    try self.collectLocals(stmt);
                }
            },
            .let => |l| {
                if (!self.locals.contains(l.name)) {
                    const wat_type = if (l.typ) |t| self.typeToWat(t) else "i32";
                    try self.locals.put(l.name, .{
                        .index = self.local_count,
                        .wat_type = wat_type,
                    });
                    self.local_count += 1;
                }
            },
            .if_ => |i| {
                try self.collectLocals(i.then_.*);
                if (i.else_) |e| try self.collectLocals(e.*);
            },
            .while_ => |w| try self.collectLocals(w.body.*),
            .for_ => |f| {
                // For loop variable
                if (!self.locals.contains(f.binding)) {
                    try self.locals.put(f.binding, .{
                        .index = self.local_count,
                        .wat_type = "i32",
                    });
                    self.local_count += 1;
                }
                try self.collectLocals(f.body.*);
            },
            .loop_ => |l| try self.collectLocals(l.body.*),
            else => {},
        }
    }

    fn lowerBlock(self: *WatLower, block: ir_nodes.Block) !void {
        for (block.stmts) |stmt| {
            try self.lowerNode(stmt);
        }
    }

    fn lowerLet(self: *WatLower, let: ir_nodes.Let) !void {
        if (let.value) |val| {
            try self.lowerNode(val.*);
            try self.p("local.set ${s}", .{let.name});
            try self.newline();
        }
    }

    fn lowerAssign(self: *WatLower, assign: ir_nodes.Assign) !void {
        // Get target name
        const target = assign.target.*;
        switch (target) {
            .ident => |id| {
                // Handle compound assignment
                if (assign.op) |op| {
                    try self.p("local.get ${s}", .{id.name});
                    try self.newline();
                    try self.lowerNode(assign.value.*);
                    try self.lowerBinaryOp(op);
                } else {
                    try self.lowerNode(assign.value.*);
                }
                try self.p("local.set ${s}", .{id.name});
                try self.newline();
            },
            else => {
                // TODO: field/index assignment
            },
        }
    }

    fn lowerReturn(self: *WatLower, ret: ir_nodes.Return) !void {
        if (ret.value) |val| {
            try self.lowerNode(val.*);
        } else {
            try self.p("i32.const 0", .{});
            try self.newline();
        }
        try self.p("return", .{});
        try self.newline();
    }

    fn lowerIf(self: *WatLower, if_: ir_nodes.If) !void {
        // Emit condition
        try self.lowerNode(if_.cond.*);

        try self.p("(if (result i32)", .{});
        try self.newline();
        self.indent += 1;

        // Then block
        try self.p("(then", .{});
        try self.newline();
        self.indent += 1;
        try self.lowerNode(if_.then_.*);
        try self.p("i32.const 0", .{}); // Default result
        try self.newline();
        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();

        // Else block
        try self.p("(else", .{});
        try self.newline();
        self.indent += 1;
        if (if_.else_) |else_| {
            try self.lowerNode(else_.*);
        }
        try self.p("i32.const 0", .{}); // Default result
        try self.newline();
        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();

        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();
    }

    fn lowerWhile(self: *WatLower, while_: ir_nodes.While) !void {
        const label = self.label_count;
        self.label_count += 1;

        try self.p("(block $break{d}", .{label});
        try self.newline();
        self.indent += 1;
        try self.p("(loop $continue{d}", .{label});
        try self.newline();
        self.indent += 1;

        // Condition check
        try self.lowerNode(while_.cond.*);
        try self.p("i32.eqz", .{});
        try self.newline();
        try self.p("br_if $break{d}", .{label});
        try self.newline();

        // Body
        try self.lowerNode(while_.body.*);

        // Loop back
        try self.p("br $continue{d}", .{label});
        try self.newline();

        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();
        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();
    }

    fn lowerFor(self: *WatLower, for_: ir_nodes.For) !void {
        const label = self.label_count;
        self.label_count += 1;

        // Extract range bounds from iterator
        const iter = for_.iter.*;
        switch (iter) {
            .binary => |b| {
                if (b.op == .range or b.op == .range_inclusive) {
                    // Initialize loop variable
                    try self.lowerNode(b.left.*);
                    try self.p("local.set ${s}", .{for_.binding});
                    try self.newline();

                    try self.p("(block $break{d}", .{label});
                    try self.newline();
                    self.indent += 1;
                    try self.p("(loop $continue{d}", .{label});
                    try self.newline();
                    self.indent += 1;

                    // Condition: var <= end
                    try self.p("local.get ${s}", .{for_.binding});
                    try self.newline();
                    try self.lowerNode(b.right.*);
                    if (b.op == .range_inclusive) {
                        try self.p("i32.gt_s", .{});
                    } else {
                        try self.p("i32.ge_s", .{});
                    }
                    try self.newline();
                    try self.p("br_if $break{d}", .{label});
                    try self.newline();

                    // Body
                    try self.lowerNode(for_.body.*);

                    // Increment
                    try self.p("local.get ${s}", .{for_.binding});
                    try self.newline();
                    try self.p("i32.const 1", .{});
                    try self.newline();
                    try self.p("i32.add", .{});
                    try self.newline();
                    try self.p("local.set ${s}", .{for_.binding});
                    try self.newline();

                    // Loop back
                    try self.p("br $continue{d}", .{label});
                    try self.newline();

                    self.indent -= 1;
                    try self.p(")", .{});
                    try self.newline();
                    self.indent -= 1;
                    try self.p(")", .{});
                    try self.newline();
                }
            },
            else => {
                // TODO: iterator-based for loops
            },
        }
    }

    fn lowerLoop(self: *WatLower, loop_: ir_nodes.Loop) !void {
        const label = self.label_count;
        self.label_count += 1;

        try self.p("(block $break{d}", .{label});
        try self.newline();
        self.indent += 1;
        try self.p("(loop $continue{d}", .{label});
        try self.newline();
        self.indent += 1;

        try self.lowerNode(loop_.body.*);

        try self.p("br $continue{d}", .{label});
        try self.newline();

        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();
        self.indent -= 1;
        try self.p(")", .{});
        try self.newline();
    }

    fn lowerBreak(self: *WatLower) !void {
        // Uses most recent block label
        try self.p("br $break{d}", .{self.label_count - 1});
        try self.newline();
    }

    fn lowerContinue(self: *WatLower) !void {
        try self.p("br $continue{d}", .{self.label_count - 1});
        try self.newline();
    }

    fn lowerBinary(self: *WatLower, binary: ir_nodes.Binary) !void {
        try self.lowerNode(binary.left.*);
        try self.lowerNode(binary.right.*);
        try self.lowerBinaryOp(binary.op);
    }

    fn lowerBinaryOp(self: *WatLower, op: ir_nodes.BinaryOp) !void {
        const wat_op = switch (op) {
            .add => "i32.add",
            .sub => "i32.sub",
            .mul => "i32.mul",
            .div => "i32.div_s",
            .rem => "i32.rem_s",
            .bit_and => "i32.and",
            .bit_or => "i32.or",
            .bit_xor => "i32.xor",
            .shl => "i32.shl",
            .shr => "i32.shr_s",
            .and_ => "i32.and",
            .or_ => "i32.or",
            .eq => "i32.eq",
            .ne => "i32.ne",
            .lt => "i32.lt_s",
            .le => "i32.le_s",
            .gt => "i32.gt_s",
            .ge => "i32.ge_s",
            else => "i32.add",
        };
        try self.p("{s}", .{wat_op});
        try self.newline();
    }

    fn lowerUnary(self: *WatLower, unary: ir_nodes.Unary) !void {
        switch (unary.op) {
            .neg => {
                try self.p("i32.const 0", .{});
                try self.newline();
                try self.lowerNode(unary.operand.*);
                try self.p("i32.sub", .{});
                try self.newline();
            },
            .not => {
                try self.lowerNode(unary.operand.*);
                try self.p("i32.eqz", .{});
                try self.newline();
            },
            .bit_not => {
                try self.lowerNode(unary.operand.*);
                try self.p("i32.const -1", .{});
                try self.newline();
                try self.p("i32.xor", .{});
                try self.newline();
            },
            else => {
                try self.lowerNode(unary.operand.*);
            },
        }
    }

    fn lowerCall(self: *WatLower, call: ir_nodes.Call) !void {
        // Emit arguments
        for (call.args) |arg| {
            try self.lowerNode(arg.value.*);
        }

        // Get function name
        const func = call.func.*;
        switch (func) {
            .ident => |id| {
                try self.p("call ${s}", .{id.name});
                try self.newline();
            },
            else => {
                // TODO: indirect calls
            },
        }
    }

    fn lowerMethodCall(self: *WatLower, method: ir_nodes.MethodCall) !void {
        // Emit receiver as first argument
        try self.lowerNode(method.receiver.*);

        // Emit other arguments
        for (method.args) |arg| {
            try self.lowerNode(arg.value.*);
        }

        // Synthesize function name (receiver_type_method)
        try self.p("call ${s}", .{method.method});
        try self.newline();
    }

    fn lowerField(self: *WatLower, _: ir_nodes.FieldAccess) !void {
        // TODO: struct field access via memory offset
        try self.p("i32.const 0 ;; field access stub", .{});
        try self.newline();
    }

    fn lowerIndex(self: *WatLower, idx: ir_nodes.Index) !void {
        // TODO: array/memory indexing
        _ = idx;
        try self.p("i32.const 0 ;; index access stub", .{});
        try self.newline();
    }

    fn lowerCast(self: *WatLower, cast: ir_nodes.Cast) !void {
        try self.lowerNode(cast.value.*);
        // TODO: type conversions (f32.convert_i32_s, etc.)
    }

    fn lowerIdent(self: *WatLower, id: ir_nodes.Ident) !void {
        // Check for special nil value
        if (std.mem.eql(u8, id.name, "nil")) {
            try self.p("i32.const 0", .{});
            try self.newline();
            return;
        }

        try self.p("local.get ${s}", .{id.name});
        try self.newline();
    }

    fn lowerInt(self: *WatLower, lit: ir_nodes.IntLit) !void {
        try self.p("i32.const {d}", .{lit.value});
        try self.newline();
    }

    fn lowerFloat(self: *WatLower, lit: ir_nodes.FloatLit) !void {
        try self.p("f64.const {d}", .{lit.value});
        try self.newline();
    }

    fn lowerBool(self: *WatLower, lit: ir_nodes.BoolLit) !void {
        try self.p("i32.const {d}", .{@as(i32, if (lit.value) 1 else 0)});
        try self.newline();
    }

    fn lowerString(self: *WatLower, _: ir_nodes.StringLit) !void {
        // TODO: string handling via memory + data section
        try self.p("i32.const 0 ;; string stub", .{});
        try self.newline();
    }

    // ============ HELPERS ============

    fn typeToWat(self: *WatLower, typ: Type) []const u8 {
        _ = self;
        return switch (typ) {
            .void => "i32",
            .bool => "i32",
            .i8, .i16, .i32, .u8, .u16, .u32 => "i32",
            .i64, .u64 => "i64",
            .f32 => "f32",
            .f64 => "f64",
            .char => "i32",
            .any => "i32", // Dynamic types default to i32
            else => "i32",
        };
    }

    fn p(self: *WatLower, comptime fmt: []const u8, args: anytype) !void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) {
            try self.out.appendSlice("  ");
        }
        try self.out.writer().print(fmt, args);
    }

    fn newline(self: *WatLower) !void {
        try self.out.append('\n');
    }
};

// ============ CONVENIENCE FUNCTION ============

/// Lower IR module to WAT string
pub fn lowerToWat(alloc: std.mem.Allocator, ir: Node) ![]const u8 {
    var lower = WatLower.init(alloc);
    defer lower.deinit();
    return try lower.lower(ir);
}

// ============ TESTS ============

test "lower simple function" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Build IR manually
    const builder = @import("../ir/builder.zig");
    var b = builder.Builder.init(alloc);

    // Create: fn add(a: i32, b: i32) -> i32 { return a + b; }
    const a_ident = b.ident("a");
    const b_ident = b.ident("b");
    const add_expr = b.add(try b.alloc_node(a_ident), try b.alloc_node(b_ident));
    const ret = b.return_(try b.alloc_node(add_expr));
    const body = try b.block(&[_]ir_nodes.Node{ret});

    const func = try b.func(
        "add",
        &[_]ir_nodes.Param{
            b.param("a", .i32),
            b.param("b", .i32),
        },
        try b.alloc_node(body),
    );

    const mod = try b.module("test", &[_]ir_nodes.Node{func});

    var lower = WatLower.init(alloc);
    const wat = try lower.lower(mod);

    // Should contain module, func, and operations
    try std.testing.expect(std.mem.indexOf(u8, wat, "(module") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "func $add") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat, "i32.add") != null);
}

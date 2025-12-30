const std = @import("std");

// Generic emitter - works with any AST
pub const Emitter = struct {
    out: std.ArrayList(u8),
    source: []const u8,
    alloc: std.mem.Allocator,
    indent: u32 = 0,

    pub fn init(alloc: std.mem.Allocator, source: []const u8) Emitter {
        return .{
            .out = std.ArrayList(u8).init(alloc),
            .source = source,
            .alloc = alloc,
        };
    }

    pub fn emit(self: *Emitter, node: anytype) ![]const u8 {
        try self.emitNode(node);
        return self.out.items;
    }

    fn emitNode(self: *Emitter, node: anytype) !void {
        const kind = @tagName(node.kind);

        if (std.mem.eql(u8, kind, "program")) {
            for (node.children) |child| try self.emitNode(child);
        } else if (std.mem.eql(u8, kind, "func_decl") or std.mem.eql(u8, kind, "fn_decl")) {
            try self.emitFn(node);
        } else if (std.mem.eql(u8, kind, "struct_decl")) {
            try self.emitStruct(node);
        } else if (std.mem.eql(u8, kind, "enum_decl")) {
            try self.emitEnum(node);
        } else if (std.mem.eql(u8, kind, "impl_block")) {
            try self.emitImpl(node);
        } else if (std.mem.eql(u8, kind, "block")) {
            try self.emitBlock(node);
        } else if (std.mem.eql(u8, kind, "let_stmt") or std.mem.eql(u8, kind, "local_decl")) {
            try self.emitLet(node);
        } else if (std.mem.eql(u8, kind, "return_stmt")) {
            try self.emitReturn(node);
        } else if (std.mem.eql(u8, kind, "if_stmt") or std.mem.eql(u8, kind, "if_expr")) {
            try self.emitIf(node);
        } else if (std.mem.eql(u8, kind, "while_stmt") or std.mem.eql(u8, kind, "while_expr")) {
            try self.emitWhile(node);
        } else if (std.mem.eql(u8, kind, "for_stmt") or std.mem.eql(u8, kind, "for_expr")) {
            try self.emitFor(node);
        } else if (std.mem.eql(u8, kind, "loop_expr")) {
            try self.emitLoop(node);
        } else if (std.mem.eql(u8, kind, "match_expr")) {
            try self.emitMatch(node);
        } else if (std.mem.eql(u8, kind, "binary_expr")) {
            try self.emitBinary(node);
        } else if (std.mem.eql(u8, kind, "unary_expr")) {
            try self.emitUnary(node);
        } else if (std.mem.eql(u8, kind, "call_expr")) {
            try self.emitCall(node);
        } else if (std.mem.eql(u8, kind, "method_call")) {
            try self.emitMethodCall(node);
        } else if (std.mem.eql(u8, kind, "field_access")) {
            try self.emitFieldAccess(node);
        } else if (std.mem.eql(u8, kind, "index_expr")) {
            try self.emitIndex(node);
        } else if (std.mem.eql(u8, kind, "identifier")) {
            if (node.token) |tok| self.p("{s}", .{tok.text(self.source)});
        } else if (std.mem.eql(u8, kind, "number_lit")) {
            self.p("{s}", .{node.value orelse "0"});
        } else if (std.mem.eql(u8, kind, "string_lit")) {
            if (node.token) |tok| self.p("{s}", .{tok.text(self.source)});
        } else if (std.mem.eql(u8, kind, "bool_lit")) {
            self.p("{s}", .{node.value orelse "false"});
        } else if (std.mem.eql(u8, kind, "array_expr") or std.mem.eql(u8, kind, "tuple_expr")) {
            try self.emitArray(node);
        } else if (std.mem.eql(u8, kind, "closure_expr")) {
            try self.emitClosure(node);
        } else if (std.mem.eql(u8, kind, "expr_stmt")) {
            if (node.children.len > 0) {
                self.pi("", .{});
                try self.emitNode(node.children[0]);
                self.raw(";\n");
            }
        } else if (std.mem.eql(u8, kind, "assign_stmt")) {
            try self.emitAssign(node);
        } else if (std.mem.eql(u8, kind, "path_expr")) {
            try self.emitPath(node);
        }
    }

    fn emitFn(self: *Emitter, node: anytype) !void {
        const name = if (node.token) |t| t.text(self.source) else "unknown";

        // Collect params
        var params = std.ArrayList(u8).init(self.alloc);
        var has_body = false;
        var body_idx: usize = 0;

        for (node.children, 0..) |child, i| {
            const ckind = @tagName(child.kind);
            if (std.mem.eql(u8, ckind, "param")) {
                if (params.items.len > 0) try params.appendSlice(", ");
                if (child.token) |t| {
                    try params.writer().print("{s}: i32", .{t.text(self.source)});
                } else if (child.value) |v| {
                    try params.appendSlice(v);
                }
            } else if (std.mem.eql(u8, ckind, "block")) {
                has_body = true;
                body_idx = i;
            }
        }

        self.pi("fn {s}({s}) -> i32 {{\n", .{ name, params.items });
        self.indent += 1;

        if (has_body) {
            for (node.children[body_idx].children) |stmt| {
                try self.emitNode(stmt);
            }
        }

        self.indent -= 1;
        self.pi("}}\n\n", .{});
    }

    fn emitStruct(self: *Emitter, node: anytype) !void {
        const name = if (node.token) |t| t.text(self.source) else "Unknown";
        self.pi("struct {s} {{\n", .{name});
        self.indent += 1;

        for (node.children) |child| {
            const ckind = @tagName(child.kind);
            if (std.mem.eql(u8, ckind, "field")) {
                if (child.token) |t| {
                    self.pi("{s}: ", .{t.text(self.source)});
                    if (child.children.len > 0) {
                        try self.emitType(child.children[0]);
                    } else {
                        self.raw("i32");
                    }
                    self.raw(",\n");
                }
            }
        }

        self.indent -= 1;
        self.pi("}}\n\n", .{});
    }

    fn emitEnum(self: *Emitter, node: anytype) !void {
        const name = if (node.token) |t| t.text(self.source) else "Unknown";
        self.pi("enum {s} {{\n", .{name});
        self.indent += 1;

        for (node.children) |child| {
            const ckind = @tagName(child.kind);
            if (std.mem.eql(u8, ckind, "variant")) {
                if (child.token) |t| {
                    self.pi("{s}", .{t.text(self.source)});
                    if (child.children.len > 0) {
                        self.raw("(");
                        for (child.children, 0..) |fc, i| {
                            if (i > 0) self.raw(", ");
                            try self.emitType(fc);
                        }
                        self.raw(")");
                    }
                    self.raw(",\n");
                }
            }
        }

        self.indent -= 1;
        self.pi("}}\n\n", .{});
    }

    fn emitImpl(self: *Emitter, node: anytype) !void {
        self.pi("impl ", .{});
        if (node.children.len > 0) {
            try self.emitType(node.children[0]);
        }
        self.raw(" {\n");
        self.indent += 1;

        for (node.children[1..]) |child| {
            const ckind = @tagName(child.kind);
            if (std.mem.eql(u8, ckind, "fn_decl") or std.mem.eql(u8, ckind, "func_decl")) {
                try self.emitFn(child);
            }
        }

        self.indent -= 1;
        self.pi("}}\n\n", .{});
    }

    fn emitBlock(self: *Emitter, node: anytype) !void {
        self.raw("{\n");
        self.indent += 1;
        for (node.children) |child| try self.emitNode(child);
        self.indent -= 1;
        self.pi("}}", .{});
    }

    fn emitLet(self: *Emitter, node: anytype) !void {
        const name = if (node.token) |t| t.text(self.source) else "_";
        self.pi("let mut {s}", .{name});

        // Type annotation
        for (node.children) |child| {
            const ckind = @tagName(child.kind);
            if (std.mem.eql(u8, ckind, "type_annotation")) {
                self.raw(": ");
                try self.emitType(child);
                break;
            }
        }

        // Value
        for (node.children) |child| {
            const ckind = @tagName(child.kind);
            if (!std.mem.eql(u8, ckind, "type_annotation") and !std.mem.eql(u8, ckind, "param")) {
                self.raw(" = ");
                try self.emitNode(child);
                break;
            }
        }

        self.raw(";\n");
    }

    fn emitReturn(self: *Emitter, node: anytype) !void {
        if (node.children.len > 0) {
            self.pi("", .{});
            try self.emitNode(node.children[0]);
            self.raw("\n");
        } else {
            self.pi("return;\n", .{});
        }
    }

    fn emitIf(self: *Emitter, node: anytype) !void {
        self.pi("if ", .{});
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]); // condition
        }
        self.raw(" ");

        if (node.children.len > 1) {
            try self.emitNode(node.children[1]); // then block
        }

        if (node.children.len > 2) {
            self.raw(" else ");
            try self.emitNode(node.children[2]); // else block
        }
        self.raw("\n");
    }

    fn emitWhile(self: *Emitter, node: anytype) !void {
        self.pi("while ", .{});
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]); // condition
        }
        self.raw(" ");
        if (node.children.len > 1) {
            try self.emitNode(node.children[1]); // body
        }
        self.raw("\n");
    }

    fn emitFor(self: *Emitter, node: anytype) !void {
        const var_name = if (node.token) |t| t.text(self.source) else "i";
        self.pi("for {s} in ", .{var_name});
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]); // iterator
        }
        self.raw(" ");
        if (node.children.len > 1) {
            try self.emitNode(node.children[1]); // body
        }
        self.raw("\n");
    }

    fn emitLoop(self: *Emitter, node: anytype) !void {
        self.pi("loop ", .{});
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]);
        }
        self.raw("\n");
    }

    fn emitMatch(self: *Emitter, node: anytype) !void {
        self.pi("match ", .{});
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]); // scrutinee
        }
        self.raw(" {\n");
        self.indent += 1;

        for (node.children[1..]) |arm| {
            const akind = @tagName(arm.kind);
            if (std.mem.eql(u8, akind, "match_arm")) {
                self.pi("", .{});
                if (arm.children.len > 0) try self.emitNode(arm.children[0]); // pattern
                self.raw(" => ");
                if (arm.children.len > 1) try self.emitNode(arm.children[1]); // body
                self.raw(",\n");
            }
        }

        self.indent -= 1;
        self.pi("}}\n", .{});
    }

    fn emitBinary(self: *Emitter, node: anytype) !void {
        if (node.children.len >= 2) {
            try self.emitNode(node.children[0]);
            if (node.token) |tok| {
                self.raw(" ");
                self.raw(self.mapOp(tok.kind));
                self.raw(" ");
            }
            try self.emitNode(node.children[1]);
        }
    }

    fn emitUnary(self: *Emitter, node: anytype) !void {
        if (node.token) |tok| {
            self.raw(self.mapOp(tok.kind));
        } else if (node.value) |v| {
            self.raw(v);
        }
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]);
        }
    }

    fn emitCall(self: *Emitter, node: anytype) !void {
        if (node.token) |tok| {
            self.p("{s}", .{tok.text(self.source)});
        }
        self.raw("(");
        for (node.children, 0..) |arg, i| {
            if (i > 0) self.raw(", ");
            try self.emitNode(arg);
        }
        self.raw(")");
    }

    fn emitMethodCall(self: *Emitter, node: anytype) !void {
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]); // receiver
        }
        self.raw(".");
        if (node.token) |tok| {
            self.p("{s}", .{tok.text(self.source)});
        }
        self.raw("(");
        for (node.children[1..], 0..) |arg, i| {
            if (i > 0) self.raw(", ");
            try self.emitNode(arg);
        }
        self.raw(")");
    }

    fn emitFieldAccess(self: *Emitter, node: anytype) !void {
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]);
        }
        self.raw(".");
        if (node.token) |tok| {
            self.p("{s}", .{tok.text(self.source)});
        }
    }

    fn emitIndex(self: *Emitter, node: anytype) !void {
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]);
        }
        self.raw("[");
        if (node.children.len > 1) {
            try self.emitNode(node.children[1]);
        }
        self.raw("]");
    }

    fn emitArray(self: *Emitter, node: anytype) !void {
        const is_tuple = std.mem.eql(u8, @tagName(node.kind), "tuple_expr");
        self.raw(if (is_tuple) "(" else "[");
        for (node.children, 0..) |item, i| {
            if (i > 0) self.raw(", ");
            try self.emitNode(item);
        }
        self.raw(if (is_tuple) ")" else "]");
    }

    fn emitClosure(self: *Emitter, node: anytype) !void {
        self.raw("|");
        var first = true;
        for (node.children) |child| {
            const ckind = @tagName(child.kind);
            if (std.mem.eql(u8, ckind, "param")) {
                if (!first) self.raw(", ");
                first = false;
                if (child.token) |t| {
                    self.p("{s}", .{t.text(self.source)});
                }
            }
        }
        self.raw("| ");

        // Body is last non-param child
        if (node.children.len > 0) {
            const last = node.children[node.children.len - 1];
            const lkind = @tagName(last.kind);
            if (!std.mem.eql(u8, lkind, "param") and !std.mem.eql(u8, lkind, "type_annotation")) {
                try self.emitNode(last);
            }
        }
    }

    fn emitAssign(self: *Emitter, node: anytype) !void {
        self.pi("", .{});
        if (node.children.len > 0) {
            try self.emitNode(node.children[0]);
        }
        self.raw(" = ");
        if (node.children.len > 1) {
            try self.emitNode(node.children[1]);
        }
        self.raw(";\n");
    }

    fn emitPath(self: *Emitter, node: anytype) !void {
        for (node.children, 0..) |part, i| {
            if (i > 0) self.raw("::");
            const pkind = @tagName(part.kind);
            if (std.mem.eql(u8, pkind, "identifier")) {
                if (part.token) |t| {
                    self.p("{s}", .{t.text(self.source)});
                }
            } else {
                try self.emitNode(part);
            }
        }
    }

    fn emitType(self: *Emitter, node: anytype) !void {
        const kind = @tagName(node.kind);
        if (std.mem.eql(u8, kind, "identifier")) {
            if (node.token) |t| {
                self.p("{s}", .{t.text(self.source)});
            }
        } else if (std.mem.eql(u8, kind, "type_annotation")) {
            if (node.value) |v| {
                self.raw(v);
            }
            for (node.children) |child| {
                try self.emitType(child);
            }
        } else if (std.mem.eql(u8, kind, "path_expr")) {
            try self.emitPath(node);
        } else {
            self.raw("i32");
        }
    }

    fn mapOp(self: *Emitter, kind: anytype) []const u8 {
        _ = self;
        return switch (kind) {
            .plus => "+",
            .minus => "-",
            .star => "*",
            .slash => "/",
            .percent => "%",
            .eqeq => "==",
            .neq => "!=",
            .lt => "<",
            .gt => ">",
            .lte => "<=",
            .gte => ">=",
            .ampamp => "&&",
            .pipepipe => "||",
            .eq => "=",
            .bang => "!",
            .ampersand => "&",
            .pipe => "|",
            else => "",
        };
    }

    // Output helpers
    fn p(self: *Emitter, comptime fmt: []const u8, args: anytype) void {
        self.out.writer().print(fmt, args) catch {};
    }

    fn pi(self: *Emitter, comptime fmt: []const u8, args: anytype) void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) self.out.appendSlice("    ") catch {};
        self.out.writer().print(fmt, args) catch {};
    }

    fn raw(self: *Emitter, s: []const u8) void {
        self.out.appendSlice(s) catch {};
    }
};

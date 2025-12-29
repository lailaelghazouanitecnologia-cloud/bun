const std = @import("std");
const lua_lexer = @import("../lua/lexer.zig");
const lua_parser = @import("../lua/parser.zig");
const Node = lua_parser.Node;
const NodeKind = lua_parser.NodeKind;
const TokenKind = lua_lexer.TokenKind;

pub const Emitter = struct {
    out: std.ArrayList(u8),
    source: []const u8,
    locals: std.StringHashMap(u32),
    local_count: u32 = 0,
    alloc: std.mem.Allocator,
    indent: u32 = 0,

    pub fn init(alloc: std.mem.Allocator, source: []const u8) Emitter {
        return .{
            .out = std.ArrayList(u8).init(alloc),
            .source = source,
            .locals = std.StringHashMap(u32).init(alloc),
            .alloc = alloc,
        };
    }

    pub fn emit(self: *Emitter, node: Node) ![]const u8 {
        self.emitNode(node);
        return self.out.items;
    }

    fn emitNode(self: *Emitter, node: Node) void {
        switch (node.kind) {
            .program => {
                self.p("(module\n", .{});
                self.indent += 1;
                for (node.children) |child| self.emitNode(child);
                self.indent -= 1;
                self.p(")\n", .{});
            },

            .func_decl => {
                const name = node.token.?.text(self.source);
                self.locals.clearRetainingCapacity();
                self.local_count = 0;

                // Collect params
                var params_buf = std.ArrayList(u8).init(self.alloc);
                var local_decls = std.ArrayList(u8).init(self.alloc);

                for (node.children) |child| {
                    if (child.kind == .param) {
                        const pname = child.token.?.text(self.source);
                        params_buf.writer().print(" (param ${s} i32)", .{pname}) catch {};
                        self.locals.put(pname, self.local_count) catch {};
                        self.local_count += 1;
                    } else if (child.kind == .block) {
                        // Pre-scan for local declarations
                        for (child.children) |stmt| {
                            if (stmt.kind == .local_decl) {
                                const lname = stmt.token.?.text(self.source);
                                if (!self.locals.contains(lname)) {
                                    local_decls.writer().print("  (local ${s} i32)\n", .{lname}) catch {};
                                    self.locals.put(lname, self.local_count) catch {};
                                    self.local_count += 1;
                                }
                            }
                        }
                    }
                }

                self.p("(func ${s}{s} (result i32)\n", .{ name, params_buf.items });
                self.indent += 1;

                // Emit local declarations
                if (local_decls.items.len > 0) {
                    self.out.appendSlice(local_decls.items) catch {};
                }

                // Emit body
                for (node.children) |child| {
                    if (child.kind == .block) {
                        for (child.children) |stmt| self.emitNode(stmt);
                    }
                }

                self.indent -= 1;
                self.p(")\n", .{});
                self.p("(export \"{s}\" (func ${s}))\n", .{ name, name });
            },

            .return_stmt => {
                if (node.children.len > 0) {
                    self.emitNode(node.children[0]);
                } else {
                    self.p("i32.const 0\n", .{});
                }
            },

            .local_decl => {
                const name = node.token.?.text(self.source);
                if (node.children.len > 0) {
                    self.emitNode(node.children[0]);
                    self.p("local.set ${s}\n", .{name});
                }
            },

            .assign_stmt => {
                if (node.children.len >= 2) {
                    const target = node.children[0];
                    if (target.kind == .identifier) {
                        const name = target.token.?.text(self.source);
                        self.emitNode(node.children[1]);
                        self.p("local.set ${s}\n", .{name});
                    }
                }
            },

            .while_stmt => {
                self.p("(block $break\n", .{});
                self.indent += 1;
                self.p("(loop $continue\n", .{});
                self.indent += 1;

                // Condition
                self.emitNode(node.children[0]);
                self.p("i32.eqz\n", .{});
                self.p("br_if $break\n", .{});

                // Body
                if (node.children.len > 1) {
                    for (node.children[1].children) |stmt| self.emitNode(stmt);
                }

                self.p("br $continue\n", .{});
                self.indent -= 1;
                self.p(")\n", .{});
                self.indent -= 1;
                self.p(")\n", .{});
                self.p("i32.const 0\n", .{});
            },

            .for_stmt => {
                // for var = start, end, step do body end
                // children: [var, start, end, (step?), body]
                if (node.children.len >= 4) {
                    const var_node = node.children[0];
                    const var_name = var_node.token.?.text(self.source);

                    // Initialize
                    self.emitNode(node.children[1]); // start
                    self.p("local.set ${s}\n", .{var_name});

                    self.p("(block $break\n", .{});
                    self.indent += 1;
                    self.p("(loop $continue\n", .{});
                    self.indent += 1;

                    // Condition: var <= end
                    self.p("local.get ${s}\n", .{var_name});
                    self.emitNode(node.children[2]); // end
                    self.p("i32.gt_s\n", .{});
                    self.p("br_if $break\n", .{});

                    // Body (last child)
                    const body = node.children[node.children.len - 1];
                    for (body.children) |stmt| self.emitNode(stmt);

                    // Increment
                    self.p("local.get ${s}\n", .{var_name});
                    if (node.children.len == 5) {
                        self.emitNode(node.children[3]); // step
                    } else {
                        self.p("i32.const 1\n", .{});
                    }
                    self.p("i32.add\n", .{});
                    self.p("local.set ${s}\n", .{var_name});

                    self.p("br $continue\n", .{});
                    self.indent -= 1;
                    self.p(")\n", .{});
                    self.indent -= 1;
                    self.p(")\n", .{});
                }
                self.p("i32.const 0\n", .{});
            },

            .if_stmt => {
                // children: [cond, then, (elseif_cond, elseif_then)*, else?]
                self.emitNode(node.children[0]); // condition
                self.p("(if (result i32)\n", .{});
                self.indent += 1;
                self.p("(then\n", .{});
                self.indent += 1;

                // Then block
                if (node.children.len > 1) {
                    for (node.children[1].children) |stmt| self.emitNode(stmt);
                }
                if (node.children[1].children.len == 0 or
                    node.children[1].children[node.children[1].children.len - 1].kind != .return_stmt)
                {
                    self.p("i32.const 0\n", .{});
                }

                self.indent -= 1;
                self.p(")\n", .{});
                self.p("(else\n", .{});
                self.indent += 1;

                // Else block (if exists, it's the last odd-indexed child)
                if (node.children.len > 2 and node.children.len % 2 == 1) {
                    const else_block = node.children[node.children.len - 1];
                    for (else_block.children) |stmt| self.emitNode(stmt);
                    if (else_block.children.len == 0 or
                        else_block.children[else_block.children.len - 1].kind != .return_stmt)
                    {
                        self.p("i32.const 0\n", .{});
                    }
                } else {
                    self.p("i32.const 0\n", .{});
                }

                self.indent -= 1;
                self.p(")\n", .{});
                self.indent -= 1;
                self.p(")\n", .{});
            },

            .binary_expr => {
                self.emitNode(node.children[0]);
                self.emitNode(node.children[1]);
                if (node.token) |tok| {
                    switch (tok.kind) {
                        .plus => self.p("i32.add\n", .{}),
                        .minus => self.p("i32.sub\n", .{}),
                        .star => self.p("i32.mul\n", .{}),
                        .slash => self.p("i32.div_s\n", .{}),
                        .percent => self.p("i32.rem_s\n", .{}),
                        .lt => self.p("i32.lt_s\n", .{}),
                        .gt => self.p("i32.gt_s\n", .{}),
                        .lte => self.p("i32.le_s\n", .{}),
                        .gte => self.p("i32.ge_s\n", .{}),
                        .eqeq => self.p("i32.eq\n", .{}),
                        .neq => self.p("i32.ne\n", .{}),
                        .kw_and => self.p("i32.and\n", .{}),
                        .kw_or => self.p("i32.or\n", .{}),
                        else => {},
                    }
                }
            },

            .unary_expr => {
                if (node.token) |tok| {
                    if (tok.kind == .minus) {
                        self.p("i32.const 0\n", .{});
                        self.emitNode(node.children[0]);
                        self.p("i32.sub\n", .{});
                    } else if (tok.kind == .kw_not) {
                        self.emitNode(node.children[0]);
                        self.p("i32.eqz\n", .{});
                    }
                }
            },

            .call_expr => {
                for (node.children) |arg| self.emitNode(arg);
                if (node.token) |tok| {
                    self.p("call ${s}\n", .{tok.text(self.source)});
                }
            },

            .identifier => {
                if (node.token) |tok| {
                    self.p("local.get ${s}\n", .{tok.text(self.source)});
                }
            },

            .number_lit => {
                self.p("i32.const {s}\n", .{node.value orelse "0"});
            },

            .bool_lit => {
                if (node.value) |v| {
                    if (std.mem.eql(u8, v, "true")) {
                        self.p("i32.const 1\n", .{});
                    } else {
                        self.p("i32.const 0\n", .{});
                    }
                }
            },

            .nil_lit => {
                self.p("i32.const 0\n", .{});
            },

            else => {},
        }
    }

    fn p(self: *Emitter, comptime fmt: []const u8, args: anytype) void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1) {
            self.out.appendSlice("  ") catch {};
        }
        self.out.writer().print(fmt, args) catch {};
    }
};

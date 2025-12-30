const std = @import("std");
const types = @import("types.zig");
const nodes = @import("nodes.zig");

const Type = types.Type;
const Node = nodes.Node;

/// IR Builder - Fluent API for constructing IR nodes
pub const Builder = struct {
    alloc: std.mem.Allocator,
    nodes: std.ArrayList(Node),

    pub fn init(alloc: std.mem.Allocator) Builder {
        return .{
            .alloc = alloc,
            .nodes = std.ArrayList(Node).init(alloc),
        };
    }

    pub fn deinit(self: *Builder) void {
        self.nodes.deinit();
    }

    // ============ MODULE LEVEL ============

    pub fn module(self: *Builder, name: []const u8, items: []Node) !Node {
        const items_copy = try self.alloc.dupe(Node, items);
        return Node{ .module = .{
            .name = name,
            .items = items_copy,
        } };
    }

    pub fn import_(self: *Builder, path: []const u8) Node {
        _ = self;
        return Node{ .import = .{ .path = path } };
    }

    pub fn importAs(self: *Builder, path: []const u8, alias: []const u8) Node {
        _ = self;
        return Node{ .import = .{ .path = path, .alias = alias } };
    }

    pub fn importItems(self: *Builder, path: []const u8, items: []const []const u8) !Node {
        const items_copy = try self.alloc.dupe([]const u8, items);
        return Node{ .import = .{ .path = path, .items = items_copy } };
    }

    pub fn func(self: *Builder, name: []const u8, params: []const nodes.Param, body: ?*const Node) !Node {
        const params_copy = try self.alloc.dupe(nodes.Param, params);
        return Node{ .func = .{
            .name = name,
            .params = params_copy,
            .body = body,
        } };
    }

    pub fn funcPub(self: *Builder, name: []const u8, params: []const nodes.Param, ret: ?*const Type, body: ?*const Node) !Node {
        const params_copy = try self.alloc.dupe(nodes.Param, params);
        return Node{ .func = .{
            .name = name,
            .params = params_copy,
            .ret_type = ret,
            .body = body,
            .is_pub = true,
        } };
    }

    pub fn asyncFunc(self: *Builder, name: []const u8, params: []const nodes.Param, ret: ?*const Type, body: ?*const Node) !Node {
        const params_copy = try self.alloc.dupe(nodes.Param, params);
        return Node{ .func = .{
            .name = name,
            .params = params_copy,
            .ret_type = ret,
            .body = body,
            .is_async = true,
        } };
    }

    pub fn externFunc(self: *Builder, name: []const u8, params: []const nodes.Param, ret: ?*const Type) !Node {
        const params_copy = try self.alloc.dupe(nodes.Param, params);
        return Node{ .func = .{
            .name = name,
            .params = params_copy,
            .ret_type = ret,
            .is_extern = true,
        } };
    }

    pub fn structDecl(self: *Builder, name: []const u8, fields: []const nodes.FieldDecl) !Node {
        const fields_copy = try self.alloc.dupe(nodes.FieldDecl, fields);
        return Node{ .struct_decl = .{
            .name = name,
            .fields = fields_copy,
        } };
    }

    pub fn enumDecl(self: *Builder, name: []const u8, variants: []const nodes.VariantDecl) !Node {
        const variants_copy = try self.alloc.dupe(nodes.VariantDecl, variants);
        return Node{ .enum_decl = .{
            .name = name,
            .variants = variants_copy,
        } };
    }

    pub fn traitDecl(self: *Builder, name: []const u8, methods: []const nodes.Func) !Node {
        const methods_copy = try self.alloc.dupe(nodes.Func, methods);
        return Node{ .trait_decl = .{
            .name = name,
            .methods = methods_copy,
        } };
    }

    pub fn implBlock(self: *Builder, target: Type, methods: []const nodes.Func) !Node {
        const methods_copy = try self.alloc.dupe(nodes.Func, methods);
        return Node{ .impl_block = .{
            .target = target,
            .methods = methods_copy,
        } };
    }

    pub fn implTrait(self: *Builder, trait: []const u8, target: Type, methods: []const nodes.Func) !Node {
        const methods_copy = try self.alloc.dupe(nodes.Func, methods);
        return Node{ .impl_block = .{
            .trait = trait,
            .target = target,
            .methods = methods_copy,
        } };
    }

    pub fn constDecl(self: *Builder, name: []const u8, value: *const Node) Node {
        _ = self;
        return Node{ .const_decl = .{
            .name = name,
            .value = value,
        } };
    }

    pub fn typeAlias(self: *Builder, name: []const u8, target: Type) Node {
        _ = self;
        return Node{ .type_alias = .{
            .name = name,
            .target = target,
        } };
    }

    // ============ STATEMENTS ============

    pub fn block(self: *Builder, stmts: []Node) !Node {
        const stmts_copy = try self.alloc.dupe(Node, stmts);
        return Node{ .block = .{ .stmts = stmts_copy } };
    }

    pub fn let_(self: *Builder, name: []const u8, value: ?*const Node) Node {
        _ = self;
        return Node{ .let = .{
            .name = name,
            .value = value,
        } };
    }

    pub fn letTyped(self: *Builder, name: []const u8, typ: Type, value: ?*const Node) Node {
        _ = self;
        return Node{ .let = .{
            .name = name,
            .typ = typ,
            .value = value,
        } };
    }

    pub fn letMut(self: *Builder, name: []const u8, value: ?*const Node) Node {
        _ = self;
        return Node{ .let = .{
            .name = name,
            .value = value,
            .mutable = true,
        } };
    }

    pub fn assign(self: *Builder, target: *const Node, value: *const Node) Node {
        _ = self;
        return Node{ .assign = .{
            .target = target,
            .value = value,
        } };
    }

    pub fn assignOp(self: *Builder, target: *const Node, op: nodes.BinaryOp, value: *const Node) Node {
        _ = self;
        return Node{ .assign = .{
            .target = target,
            .value = value,
            .op = op,
        } };
    }

    pub fn return_(self: *Builder, value: ?*const Node) Node {
        _ = self;
        return Node{ .return_ = .{ .value = value } };
    }

    pub fn break_(self: *Builder) Node {
        _ = self;
        return Node{ .break_ = .{} };
    }

    pub fn breakLabel(self: *Builder, label: []const u8) Node {
        _ = self;
        return Node{ .break_ = .{ .label = label } };
    }

    pub fn breakValue(self: *Builder, value: *const Node) Node {
        _ = self;
        return Node{ .break_ = .{ .value = value } };
    }

    pub fn continue_(self: *Builder) Node {
        _ = self;
        return Node{ .continue_ = .{} };
    }

    pub fn continueLabel(self: *Builder, label: []const u8) Node {
        _ = self;
        return Node{ .continue_ = .{ .label = label } };
    }

    pub fn if_(self: *Builder, cond: *const Node, then_: *const Node, else_: ?*const Node) Node {
        _ = self;
        return Node{ .if_ = .{
            .cond = cond,
            .then_ = then_,
            .else_ = else_,
        } };
    }

    pub fn match_(self: *Builder, scrutinee: *const Node, arms: []const nodes.MatchArm) !Node {
        const arms_copy = try self.alloc.dupe(nodes.MatchArm, arms);
        return Node{ .match_ = .{
            .scrutinee = scrutinee,
            .arms = arms_copy,
        } };
    }

    pub fn loop_(self: *Builder, body: *const Node) Node {
        _ = self;
        return Node{ .loop_ = .{ .body = body } };
    }

    pub fn loopLabel(self: *Builder, label: []const u8, body: *const Node) Node {
        _ = self;
        return Node{ .loop_ = .{
            .label = label,
            .body = body,
        } };
    }

    pub fn while_(self: *Builder, cond: *const Node, body: *const Node) Node {
        _ = self;
        return Node{ .while_ = .{
            .cond = cond,
            .body = body,
        } };
    }

    pub fn for_(self: *Builder, binding: []const u8, iter: *const Node, body: *const Node) Node {
        _ = self;
        return Node{ .for_ = .{
            .binding = binding,
            .iter = iter,
            .body = body,
        } };
    }

    pub fn exprStmt(self: *Builder, expr: *const Node) Node {
        _ = self;
        return Node{ .expr_stmt = .{ .expr = expr } };
    }

    // ============ EXPRESSIONS ============

    pub fn binary(self: *Builder, op: nodes.BinaryOp, left: *const Node, right: *const Node) Node {
        _ = self;
        return Node{ .binary = .{
            .op = op,
            .left = left,
            .right = right,
        } };
    }

    pub fn add(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.add, left, right);
    }

    pub fn sub(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.sub, left, right);
    }

    pub fn mul(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.mul, left, right);
    }

    pub fn div(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.div, left, right);
    }

    pub fn rem(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.rem, left, right);
    }

    pub fn eq(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.eq, left, right);
    }

    pub fn ne(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.ne, left, right);
    }

    pub fn lt(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.lt, left, right);
    }

    pub fn le(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.le, left, right);
    }

    pub fn gt(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.gt, left, right);
    }

    pub fn ge(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.ge, left, right);
    }

    pub fn and_(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.and_, left, right);
    }

    pub fn or_(self: *Builder, left: *const Node, right: *const Node) Node {
        return self.binary(.or_, left, right);
    }

    pub fn unary(self: *Builder, op: nodes.UnaryOp, operand: *const Node) Node {
        _ = self;
        return Node{ .unary = .{
            .op = op,
            .operand = operand,
        } };
    }

    pub fn neg(self: *Builder, operand: *const Node) Node {
        return self.unary(.neg, operand);
    }

    pub fn not(self: *Builder, operand: *const Node) Node {
        return self.unary(.not, operand);
    }

    pub fn call(self: *Builder, func_node: *const Node, args: []const nodes.Arg) !Node {
        const args_copy = try self.alloc.dupe(nodes.Arg, args);
        return Node{ .call = .{
            .func = func_node,
            .args = args_copy,
        } };
    }

    pub fn callSimple(self: *Builder, func_node: *const Node, values: []const *const Node) !Node {
        var args = std.ArrayList(nodes.Arg).init(self.alloc);
        for (values) |v| {
            try args.append(.{ .value = v });
        }
        return Node{ .call = .{
            .func = func_node,
            .args = args.items,
        } };
    }

    pub fn methodCall(self: *Builder, receiver: *const Node, method: []const u8, args: []const nodes.Arg) !Node {
        const args_copy = try self.alloc.dupe(nodes.Arg, args);
        return Node{ .method_call = .{
            .receiver = receiver,
            .method = method,
            .args = args_copy,
        } };
    }

    pub fn field(self: *Builder, object: *const Node, field_name: []const u8) Node {
        _ = self;
        return Node{ .field = .{
            .object = object,
            .field = field_name,
        } };
    }

    pub fn index(self: *Builder, object: *const Node, idx: *const Node) Node {
        _ = self;
        return Node{ .index = .{
            .object = object,
            .index = idx,
        } };
    }

    pub fn cast(self: *Builder, value: *const Node, to: Type) Node {
        _ = self;
        return Node{ .cast = .{
            .value = value,
            .to = to,
        } };
    }

    pub fn ref(self: *Builder, value: *const Node) Node {
        _ = self;
        return Node{ .ref = .{ .value = value } };
    }

    pub fn refMut(self: *Builder, value: *const Node) Node {
        _ = self;
        return Node{ .ref = .{
            .value = value,
            .mutable = true,
        } };
    }

    pub fn deref(self: *Builder, value: *const Node) Node {
        _ = self;
        return Node{ .deref = .{ .value = value } };
    }

    // ============ LITERALS ============

    pub fn ident(self: *Builder, name: []const u8) Node {
        _ = self;
        return Node{ .ident = .{ .name = name } };
    }

    pub fn identTyped(self: *Builder, name: []const u8, typ: Type) Node {
        _ = self;
        return Node{ .ident = .{ .name = name, .typ = typ } };
    }

    pub fn int(self: *Builder, value: i64) Node {
        _ = self;
        return Node{ .int_lit = .{ .value = value } };
    }

    pub fn intTyped(self: *Builder, value: i64, typ: Type) Node {
        _ = self;
        return Node{ .int_lit = .{ .value = value, .typ = typ } };
    }

    pub fn float(self: *Builder, value: f64) Node {
        _ = self;
        return Node{ .float_lit = .{ .value = value } };
    }

    pub fn floatTyped(self: *Builder, value: f64, typ: Type) Node {
        _ = self;
        return Node{ .float_lit = .{ .value = value, .typ = typ } };
    }

    pub fn boolean(self: *Builder, value: bool) Node {
        _ = self;
        return Node{ .bool_lit = .{ .value = value } };
    }

    pub fn true_(self: *Builder) Node {
        return self.boolean(true);
    }

    pub fn false_(self: *Builder) Node {
        return self.boolean(false);
    }

    pub fn string(self: *Builder, value: []const u8) Node {
        _ = self;
        return Node{ .string_lit = .{ .value = value } };
    }

    pub fn char(self: *Builder, value: u32) Node {
        _ = self;
        return Node{ .char_lit = .{ .value = value } };
    }

    pub fn array(self: *Builder, elems: []const Node) !Node {
        const elems_copy = try self.alloc.dupe(Node, elems);
        return Node{ .array_lit = .{ .elems = elems_copy } };
    }

    pub fn tuple(self: *Builder, elems: []const Node) !Node {
        const elems_copy = try self.alloc.dupe(Node, elems);
        return Node{ .tuple_lit = .{ .elems = elems_copy } };
    }

    pub fn structLit(self: *Builder, name: ?[]const u8, fields: []const nodes.FieldInit) !Node {
        const fields_copy = try self.alloc.dupe(nodes.FieldInit, fields);
        return Node{ .struct_lit = .{
            .name = name,
            .fields = fields_copy,
        } };
    }

    // ============ ADVANCED ============

    pub fn closure(self: *Builder, params: []const nodes.Param, body: *const Node) !Node {
        const params_copy = try self.alloc.dupe(nodes.Param, params);
        var param_types = std.ArrayList(Type).init(self.alloc);
        for (params) |p| {
            try param_types.append(p.typ);
        }
        return Node{ .closure = .{
            .params = params_copy,
            .param_types = param_types.items,
            .body = body,
        } };
    }

    pub fn spawn(self: *Builder, func_node: *const Node) Node {
        _ = self;
        return Node{ .spawn = .{ .func = func_node } };
    }

    pub fn await_(self: *Builder, future: *const Node) Node {
        _ = self;
        return Node{ .await_ = .{ .future = future } };
    }

    pub fn try_(self: *Builder, expr: *const Node) Node {
        _ = self;
        return Node{ .try_ = .{ .expr = expr } };
    }

    pub fn throw(self: *Builder, value: *const Node) Node {
        _ = self;
        return Node{ .throw = .{ .value = value } };
    }

    // ============ HELPERS ============

    /// Allocate a node on the heap and return a pointer
    pub fn alloc_node(self: *Builder, node: Node) !*const Node {
        const ptr = try self.alloc.create(Node);
        ptr.* = node;
        return ptr;
    }

    /// Allocate a type on the heap and return a pointer
    pub fn alloc_type(self: *Builder, typ: Type) !*const Type {
        const ptr = try self.alloc.create(Type);
        ptr.* = typ;
        return ptr;
    }

    /// Create a parameter
    pub fn param(self: *Builder, name: []const u8, typ: Type) nodes.Param {
        _ = self;
        return .{ .name = name, .typ = typ };
    }

    /// Create a mutable parameter
    pub fn paramMut(self: *Builder, name: []const u8, typ: Type) nodes.Param {
        _ = self;
        return .{ .name = name, .typ = typ, .mutable = true };
    }

    /// Create a field declaration
    pub fn fieldDecl(self: *Builder, name: []const u8, typ: Type) nodes.FieldDecl {
        _ = self;
        return .{ .name = name, .typ = typ };
    }

    /// Create a variant declaration
    pub fn variantDecl(self: *Builder, name: []const u8) nodes.VariantDecl {
        _ = self;
        return .{ .name = name };
    }

    /// Create a variant with payload
    pub fn variantPayload(self: *Builder, name: []const u8, payload: Type) nodes.VariantDecl {
        _ = self;
        return .{ .name = name, .payload = payload };
    }

    /// Create a match arm
    pub fn matchArm(self: *Builder, pattern: nodes.Pattern, body: *const Node) nodes.MatchArm {
        _ = self;
        return .{ .pattern = pattern, .body = body };
    }

    /// Create an argument
    pub fn arg(self: *Builder, value: *const Node) nodes.Arg {
        _ = self;
        return .{ .value = value };
    }

    /// Create a named argument
    pub fn namedArg(self: *Builder, name: []const u8, value: *const Node) nodes.Arg {
        _ = self;
        return .{ .name = name, .value = value };
    }

    /// Create a field initializer
    pub fn fieldInit(self: *Builder, name: []const u8, value: *const Node) nodes.FieldInit {
        _ = self;
        return .{ .name = name, .value = value };
    }
};

// ============ PATTERN BUILDERS ============

pub const PatternBuilder = struct {
    pub fn wildcard() nodes.Pattern {
        return .wildcard;
    }

    pub fn ident(name: []const u8) nodes.Pattern {
        return .{ .ident = name };
    }

    pub fn literal(node: *const Node) nodes.Pattern {
        return .{ .literal = node };
    }

    pub fn tuple(alloc: std.mem.Allocator, patterns: []const nodes.Pattern) !nodes.Pattern {
        const copy = try alloc.dupe(nodes.Pattern, patterns);
        return .{ .tuple = copy };
    }

    pub fn struct_(name: ?[]const u8, fields: []const nodes.FieldPattern, rest: bool) nodes.Pattern {
        return .{ .struct_ = .{
            .name = name,
            .fields = fields,
            .rest = rest,
        } };
    }

    pub fn enum_(variant: []const u8, payload: ?nodes.Pattern) nodes.Pattern {
        return .{ .enum_ = .{
            .variant = variant,
            .payload = payload,
        } };
    }

    pub fn or_(alloc: std.mem.Allocator, patterns: []const nodes.Pattern) !nodes.Pattern {
        const copy = try alloc.dupe(nodes.Pattern, patterns);
        return .{ .or_ = copy };
    }

    pub fn range(start: ?*const Node, end: ?*const Node, inclusive: bool) nodes.Pattern {
        return .{ .range = .{
            .start = start,
            .end = end,
            .inclusive = inclusive,
        } };
    }
};

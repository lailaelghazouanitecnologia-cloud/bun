const std = @import("std");

/// IR Type System - Universal type representation
pub const Type = union(enum) {
    // Primitives
    void,
    bool,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f32,
    f64,
    char,

    // Compound
    string,
    bytes,
    array: ArrayType,
    slice: SliceType,
    tuple: TupleType,
    struct_: StructType,
    enum_: EnumType,
    union_: UnionType,

    // Advanced
    option: OptionType,
    result: ResultType,
    ref: RefType,
    ptr: PtrType,
    func: FuncType,
    closure: ClosureType,

    // Parametric
    generic: GenericType,
    param: ParamType, // T in generic<T>

    // Special
    any,
    never,
    unknown,

    pub fn eql(self: Type, other: Type) bool {
        return std.meta.eql(self, other);
    }

    pub fn isNumeric(self: Type) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .f32, .f64 => true,
            else => false,
        };
    }

    pub fn isInteger(self: Type) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => true,
            else => false,
        };
    }

    pub fn isFloat(self: Type) bool {
        return switch (self) {
            .f32, .f64 => true,
            else => false,
        };
    }

    pub fn isSigned(self: Type) bool {
        return switch (self) {
            .i8, .i16, .i32, .i64, .f32, .f64 => true,
            else => false,
        };
    }

    pub fn bitSize(self: Type) ?u32 {
        return switch (self) {
            .bool => 1,
            .i8, .u8 => 8,
            .i16, .u16 => 16,
            .i32, .u32, .f32, .char => 32,
            .i64, .u64, .f64 => 64,
            .ptr, .ref => 32, // Assuming 32-bit target
            else => null,
        };
    }
};

pub const ArrayType = struct {
    elem: *const Type,
    len: ?usize = null, // null = dynamic
};

pub const SliceType = struct {
    elem: *const Type,
};

pub const TupleType = struct {
    elems: []const Type,
};

pub const StructType = struct {
    name: ?[]const u8 = null,
    fields: []const Field,
    generics: []const GenericParam = &.{},
};

pub const Field = struct {
    name: []const u8,
    typ: Type,
    default: ?*const anyopaque = null,
    mutable: bool = true,
    public: bool = true,
};

pub const EnumType = struct {
    name: ?[]const u8 = null,
    variants: []const Variant,
    generics: []const GenericParam = &.{},
};

pub const Variant = struct {
    name: []const u8,
    payload: ?Type = null, // For enum with data
    value: ?i64 = null, // For C-style enums
};

pub const UnionType = struct {
    name: ?[]const u8 = null,
    members: []const Type,
    tagged: bool = true,
};

pub const OptionType = struct {
    inner: *const Type,
};

pub const ResultType = struct {
    ok: *const Type,
    err: *const Type,
};

pub const RefType = struct {
    inner: *const Type,
    mutable: bool = false,
    lifetime: ?[]const u8 = null,
};

pub const PtrType = struct {
    inner: *const Type,
    mutable: bool = true,
    nullable: bool = false,
};

pub const FuncType = struct {
    params: []const Type,
    ret: *const Type,
    variadic: bool = false,
};

pub const ClosureType = struct {
    params: []const Type,
    ret: *const Type,
    captures: []const Capture = &.{},
};

pub const Capture = struct {
    name: []const u8,
    typ: Type,
    by_ref: bool = false,
    mutable: bool = false,
};

pub const GenericType = struct {
    base: *const Type,
    args: []const Type,
};

pub const GenericParam = struct {
    name: []const u8,
    bounds: []const Bound = &.{},
    default: ?Type = null,
};

pub const ParamType = struct {
    name: []const u8,
    bounds: []const Bound = &.{},
};

pub const Bound = struct {
    trait: []const u8,
    args: []const Type = &.{},
};

// ============ TYPE HELPERS ============

pub fn makeArray(alloc: std.mem.Allocator, elem: Type, len: ?usize) !Type {
    const elem_ptr = try alloc.create(Type);
    elem_ptr.* = elem;
    return Type{ .array = .{ .elem = elem_ptr, .len = len } };
}

pub fn makeSlice(alloc: std.mem.Allocator, elem: Type) !Type {
    const elem_ptr = try alloc.create(Type);
    elem_ptr.* = elem;
    return Type{ .slice = .{ .elem = elem_ptr } };
}

pub fn makeOption(alloc: std.mem.Allocator, inner: Type) !Type {
    const inner_ptr = try alloc.create(Type);
    inner_ptr.* = inner;
    return Type{ .option = .{ .inner = inner_ptr } };
}

pub fn makeResult(alloc: std.mem.Allocator, ok: Type, err: Type) !Type {
    const ok_ptr = try alloc.create(Type);
    const err_ptr = try alloc.create(Type);
    ok_ptr.* = ok;
    err_ptr.* = err;
    return Type{ .result = .{ .ok = ok_ptr, .err = err_ptr } };
}

pub fn makeRef(alloc: std.mem.Allocator, inner: Type, mutable: bool) !Type {
    const inner_ptr = try alloc.create(Type);
    inner_ptr.* = inner;
    return Type{ .ref = .{ .inner = inner_ptr, .mutable = mutable } };
}

pub fn makePtr(alloc: std.mem.Allocator, inner: Type, mutable: bool) !Type {
    const inner_ptr = try alloc.create(Type);
    inner_ptr.* = inner;
    return Type{ .ptr = .{ .inner = inner_ptr, .mutable = mutable } };
}

pub fn makeFunc(alloc: std.mem.Allocator, params: []const Type, ret: Type) !Type {
    const ret_ptr = try alloc.create(Type);
    ret_ptr.* = ret;
    const params_copy = try alloc.dupe(Type, params);
    return Type{ .func = .{ .params = params_copy, .ret = ret_ptr } };
}

// ============ TYPE PRINTING ============

pub fn format(typ: Type, alloc: std.mem.Allocator) ![]const u8 {
    var buf = std.ArrayList(u8).init(alloc);
    try formatType(&buf, typ);
    return buf.items;
}

fn formatType(buf: *std.ArrayList(u8), typ: Type) !void {
    switch (typ) {
        .void => try buf.appendSlice("void"),
        .bool => try buf.appendSlice("bool"),
        .i8 => try buf.appendSlice("i8"),
        .i16 => try buf.appendSlice("i16"),
        .i32 => try buf.appendSlice("i32"),
        .i64 => try buf.appendSlice("i64"),
        .u8 => try buf.appendSlice("u8"),
        .u16 => try buf.appendSlice("u16"),
        .u32 => try buf.appendSlice("u32"),
        .u64 => try buf.appendSlice("u64"),
        .f32 => try buf.appendSlice("f32"),
        .f64 => try buf.appendSlice("f64"),
        .char => try buf.appendSlice("char"),
        .string => try buf.appendSlice("string"),
        .bytes => try buf.appendSlice("bytes"),
        .any => try buf.appendSlice("any"),
        .never => try buf.appendSlice("never"),
        .unknown => try buf.appendSlice("unknown"),

        .array => |a| {
            try buf.appendSlice("[");
            try formatType(buf, a.elem.*);
            if (a.len) |l| {
                try buf.writer().print("; {d}", .{l});
            }
            try buf.appendSlice("]");
        },

        .slice => |s| {
            try buf.appendSlice("[]");
            try formatType(buf, s.elem.*);
        },

        .tuple => |t| {
            try buf.appendSlice("(");
            for (t.elems, 0..) |elem, i| {
                if (i > 0) try buf.appendSlice(", ");
                try formatType(buf, elem);
            }
            try buf.appendSlice(")");
        },

        .struct_ => |s| {
            if (s.name) |n| {
                try buf.appendSlice(n);
            } else {
                try buf.appendSlice("struct { ... }");
            }
        },

        .enum_ => |e| {
            if (e.name) |n| {
                try buf.appendSlice(n);
            } else {
                try buf.appendSlice("enum { ... }");
            }
        },

        .option => |o| {
            try buf.appendSlice("?");
            try formatType(buf, o.inner.*);
        },

        .result => |r| {
            try buf.appendSlice("Result<");
            try formatType(buf, r.ok.*);
            try buf.appendSlice(", ");
            try formatType(buf, r.err.*);
            try buf.appendSlice(">");
        },

        .ref => |r| {
            try buf.appendSlice(if (r.mutable) "&mut " else "&");
            try formatType(buf, r.inner.*);
        },

        .ptr => |p| {
            try buf.appendSlice(if (p.mutable) "*mut " else "*");
            try formatType(buf, p.inner.*);
        },

        .func => |f| {
            try buf.appendSlice("fn(");
            for (f.params, 0..) |param, i| {
                if (i > 0) try buf.appendSlice(", ");
                try formatType(buf, param);
            }
            try buf.appendSlice(") -> ");
            try formatType(buf, f.ret.*);
        },

        .closure => |c| {
            try buf.appendSlice("|");
            for (c.params, 0..) |param, i| {
                if (i > 0) try buf.appendSlice(", ");
                try formatType(buf, param);
            }
            try buf.appendSlice("| -> ");
            try formatType(buf, c.ret.*);
        },

        .generic => |g| {
            try formatType(buf, g.base.*);
            try buf.appendSlice("<");
            for (g.args, 0..) |arg, i| {
                if (i > 0) try buf.appendSlice(", ");
                try formatType(buf, arg);
            }
            try buf.appendSlice(">");
        },

        .param => |p| {
            try buf.appendSlice(p.name);
        },

        else => try buf.appendSlice("?"),
    }
}

//! Framework & IR Tests

const std = @import("std");
const testing = std.testing;
const framework = @import("../src/framework/framework.zig");
const ir = framework.ir;

// ============ IR Tests ============

test "Location struct" {
    const loc = ir.Location{
        .file = "test.zig",
        .line = 10,
        .column = 5,
        .offset = 100,
        .length = 10,
    };

    try testing.expectEqualStrings("test.zig", loc.file);
    try testing.expectEqual(@as(u32, 10), loc.line);
    try testing.expectEqual(@as(u32, 5), loc.column);
}

test "null_ref constant" {
    try testing.expectEqual(std.math.maxInt(ir.NodeRef), ir.null_ref);
}

test "Node.Tag enum" {
    // Verify some tag values exist
    const int_tag = ir.Node.Tag.int_literal;
    const str_tag = ir.Node.Tag.string_literal;
    const func_tag = ir.Node.Tag.func_decl;

    try testing.expect(int_tag != str_tag);
    try testing.expect(func_tag != int_tag);
}

test "BinaryOp enum" {
    const add = ir.BinaryOp.add;
    const sub = ir.BinaryOp.sub;
    const eq = ir.BinaryOp.eq;

    try testing.expect(add != sub);
    try testing.expect(eq != add);
}

test "UnaryOp enum" {
    const neg = ir.UnaryOp.neg;
    const not = ir.UnaryOp.not;

    try testing.expect(neg != not);
}

test "Type common types" {
    // Verify common types exist
    const void_t = ir.Type.void_type;
    const bool_t = ir.Type.bool_type;
    const i32_t = ir.Type.i32_type;
    const string_t = ir.Type.string_type;

    try testing.expectEqual(ir.Type.TypeTag.void, void_t.tag);
    try testing.expectEqual(ir.Type.TypeTag.bool, bool_t.tag);
    try testing.expectEqual(ir.Type.TypeTag.int, i32_t.tag);
    try testing.expectEqual(ir.Type.TypeTag.string, string_t.tag);
}

test "Builder init/deinit" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    // Builder should start empty
    try testing.expectEqual(@as(usize, 0), builder.nodes.items.len);
}

test "Builder int literal" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const ref = builder.intLiteral(42);
    try testing.expect(ref != ir.null_ref);

    const node = builder.get(ref);
    try testing.expectEqual(ir.Node.Tag.int_literal, node.tag);
    try testing.expectEqual(@as(i64, 42), node.data.int);
}

test "Builder string literal" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const ref = builder.stringLiteral("hello");
    const node = builder.get(ref);

    try testing.expectEqual(ir.Node.Tag.string_literal, node.tag);
    try testing.expectEqualStrings("hello", node.data.str);
}

test "Builder bool literal" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const true_ref = builder.boolLiteral(true);
    const false_ref = builder.boolLiteral(false);

    try testing.expect(builder.get(true_ref).data.boolean);
    try testing.expect(!builder.get(false_ref).data.boolean);
}

test "Builder identifier" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const ref = builder.identifier("myVar");
    const node = builder.get(ref);

    try testing.expectEqual(ir.Node.Tag.identifier, node.tag);
    try testing.expectEqualStrings("myVar", node.data.str);
}

test "Builder binary operation" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const lhs = builder.intLiteral(5);
    const rhs = builder.intLiteral(3);
    const add_ref = builder.binary(.add, lhs, rhs);

    const node = builder.get(add_ref);
    try testing.expectEqual(ir.Node.Tag.binary_op, node.tag);
    try testing.expectEqual(ir.BinaryOp.add, node.data.binary.op);
    try testing.expectEqual(lhs, node.data.binary.lhs);
    try testing.expectEqual(rhs, node.data.binary.rhs);
}

test "Builder unary operation" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const operand = builder.intLiteral(5);
    const neg_ref = builder.unary(.neg, operand);

    const node = builder.get(neg_ref);
    try testing.expectEqual(ir.Node.Tag.unary_op, node.tag);
    try testing.expectEqual(ir.UnaryOp.neg, node.data.unary.op);
}

test "Builder return statement" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const value = builder.intLiteral(0);
    const ret = builder.returnStmt(value);

    const node = builder.get(ret);
    try testing.expectEqual(ir.Node.Tag.return_stmt, node.tag);
    try testing.expectEqual(value, node.data.single);
}

test "Builder block" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const stmt1 = builder.intLiteral(1);
    const stmt2 = builder.intLiteral(2);
    const blk = builder.block(&.{ stmt1, stmt2 });

    const node = builder.get(blk);
    try testing.expectEqual(ir.Node.Tag.block, node.tag);
    try testing.expectEqual(@as(u32, 2), node.data.block.stmts_count);
}

test "Builder function call" {
    const alloc = testing.allocator;
    var builder = ir.Builder.init(alloc);
    defer builder.deinit();

    const callee = builder.identifier("print");
    const arg = builder.stringLiteral("hello");
    const call_ref = builder.call(callee, &.{arg});

    const node = builder.get(call_ref);
    try testing.expectEqual(ir.Node.Tag.call, node.tag);
    try testing.expectEqual(callee, node.data.call.callee);
    try testing.expectEqual(@as(u32, 1), node.data.call.args_count);
}

// ============ Pipeline Tests ============

test "Pipeline struct defaults" {
    const p = framework.Pipeline{};

    try testing.expectEqualStrings("transpiler", p.name);
    try testing.expectEqualStrings("src/*", p.input);
    try testing.expectEqualStrings("dist/", p.output);
}

test "Stage struct" {
    const stage = framework.Stage{
        .name = "test",
        .run = struct {
            fn run(_: *framework.StageContext) !void {}
        }.run,
    };

    try testing.expectEqualStrings("test", stage.name);
}

//! Template Tests
//!
//! Tests para el sistema de templates de proyectos.
//! Crítico: la sustitución de variables debe funcionar correctamente.

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");
const template = zid.api.template;

// ============================================================================
// BUILT-IN TEMPLATES
// ============================================================================

test "builtin_templates: existen templates básicos" {
    const templates = template.builtin_templates;
    try testing.expect(templates.len > 0);
}

test "findBuiltin: encuentra template 'zig'" {
    const result = template.findBuiltin("zig");
    try testing.expect(result != null);
    try testing.expectEqualStrings("zig", result.?.name);
}

test "findBuiltin: encuentra template 'transpiler'" {
    const result = template.findBuiltin("transpiler");
    try testing.expect(result != null);
}

test "findBuiltin: retorna null para template inexistente" {
    const result = template.findBuiltin("template_que_no_existe_xyz");
    try testing.expect(result == null);
}

test "list: retorna todos los templates" {
    const templates = template.list();
    try testing.expect(templates.len >= 3); // zig, zig-lib, transpiler, etc.
}

// ============================================================================
// ESTRUCTURA DE TEMPLATE
// ============================================================================

test "BuiltinTemplate: tiene campos requeridos" {
    const zig_tmpl = template.findBuiltin("zig").?;
    try testing.expect(zig_tmpl.name.len > 0);
    try testing.expect(zig_tmpl.description.len > 0);
    try testing.expect(zig_tmpl.files.len > 0);
}

test "BuiltinTemplate.File: tiene path y content" {
    const zig_tmpl = template.findBuiltin("zig").?;
    for (zig_tmpl.files) |file| {
        try testing.expect(file.path.len > 0);
        try testing.expect(file.content.len > 0);
    }
}

test "template 'zig': incluye build.zig" {
    const zig_tmpl = template.findBuiltin("zig").?;
    var has_build = false;
    for (zig_tmpl.files) |file| {
        if (std.mem.eql(u8, file.path, "build.zig")) {
            has_build = true;
            break;
        }
    }
    try testing.expect(has_build);
}

test "template 'zig': incluye src/main.zig" {
    const zig_tmpl = template.findBuiltin("zig").?;
    var has_main = false;
    for (zig_tmpl.files) |file| {
        if (std.mem.eql(u8, file.path, "src/main.zig")) {
            has_main = true;
            break;
        }
    }
    try testing.expect(has_main);
}

test "template 'transpiler': incluye lexer y parser" {
    const tmpl = template.findBuiltin("transpiler").?;
    var has_lexer = false;
    var has_parser = false;

    for (tmpl.files) |file| {
        if (std.mem.indexOf(u8, file.path, "lexer") != null) has_lexer = true;
        if (std.mem.indexOf(u8, file.path, "parser") != null) has_parser = true;
    }

    try testing.expect(has_lexer);
    try testing.expect(has_parser);
}

// ============================================================================
// CONTENIDO DE TEMPLATES
// ============================================================================

test "template content: contiene {{name}} placeholder" {
    const zig_tmpl = template.findBuiltin("zig").?;
    var has_placeholder = false;

    for (zig_tmpl.files) |file| {
        if (std.mem.indexOf(u8, file.content, "{{name}}") != null) {
            has_placeholder = true;
            break;
        }
    }

    try testing.expect(has_placeholder);
}

test "template 'zig-lib': es diferente a 'zig'" {
    const zig = template.findBuiltin("zig").?;
    const zig_lib = template.findBuiltin("zig-lib").?;

    try testing.expect(!std.mem.eql(u8, zig.description, zig_lib.description));
}

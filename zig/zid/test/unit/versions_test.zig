//! Version Parsing Tests
//!
//! Tests críticos para parsing de versiones.
//! Estos tests cubren:
//! - Formatos válidos comunes
//! - Edge cases que causan bugs reales
//! - Errores que deben ser rechazados

const std = @import("std");
const testing = std.testing;
const zid = @import("zid");
const versions = zid.toolchain.versions;
const Version = versions.Version;
const Constraint = versions.Constraint;

// ============================================================================
// CASOS VÁLIDOS - Lo que usuarios realmente usan
// ============================================================================

test "parse: semver completo '1.2.3'" {
    const v = Version.parse("1.2.3").unwrap();
    try testing.expectEqual(@as(u32, 1), v.major);
    try testing.expectEqual(@as(u32, 2), v.minor);
    try testing.expectEqual(@as(u32, 3), v.patch);
    try testing.expect(v.prerelease == null);
}

test "parse: solo major '1'" {
    const v = Version.parse("1").unwrap();
    try testing.expectEqual(@as(u32, 1), v.major);
    try testing.expectEqual(@as(u32, 0), v.minor);
    try testing.expectEqual(@as(u32, 0), v.patch);
}

test "parse: major.minor '1.2'" {
    const v = Version.parse("1.2").unwrap();
    try testing.expectEqual(@as(u32, 1), v.major);
    try testing.expectEqual(@as(u32, 2), v.minor);
    try testing.expectEqual(@as(u32, 0), v.patch);
}

test "parse: con prefijo 'v'" {
    const v1 = Version.parse("v1.2.3").unwrap();
    const v2 = Version.parse("V1.2.3").unwrap();
    try testing.expectEqual(@as(u32, 1), v1.major);
    try testing.expectEqual(@as(u32, 1), v2.major);
}

test "parse: prerelease '-beta'" {
    const v = Version.parse("1.0.0-beta").unwrap();
    try testing.expectEqualStrings("beta", v.prerelease.?);
}

test "parse: prerelease '-beta.1'" {
    const v = Version.parse("1.0.0-beta.1").unwrap();
    try testing.expectEqualStrings("beta.1", v.prerelease.?);
}

test "parse: prerelease '-rc.1'" {
    const v = Version.parse("2.0.0-rc.1").unwrap();
    try testing.expectEqual(@as(u32, 2), v.major);
    try testing.expectEqualStrings("rc.1", v.prerelease.?);
}

test "parse: build metadata '+build'" {
    const v = Version.parse("1.0.0+build").unwrap();
    try testing.expectEqualStrings("build", v.build.?);
}

test "parse: prerelease + build '1.0.0-beta+build'" {
    const v = Version.parse("1.0.0-beta+build").unwrap();
    try testing.expectEqualStrings("beta", v.prerelease.?);
    try testing.expectEqualStrings("build", v.build.?);
}

test "parse: keyword 'latest'" {
    const v = Version.parse("latest").unwrap();
    try testing.expect(v.isLatest());
}

// ============================================================================
// EDGE CASES - Inputs que causan bugs reales
// ============================================================================

test "parse: versión cero '0.0.0'" {
    const v = Version.parse("0.0.0").unwrap();
    try testing.expectEqual(@as(u32, 0), v.major);
    try testing.expectEqual(@as(u32, 0), v.minor);
    try testing.expectEqual(@as(u32, 0), v.patch);
}

test "parse: números grandes '999.999.999'" {
    const v = Version.parse("999.999.999").unwrap();
    try testing.expectEqual(@as(u32, 999), v.major);
    try testing.expectEqual(@as(u32, 999), v.minor);
    try testing.expectEqual(@as(u32, 999), v.patch);
}

test "parse: prerelease vacío después de guión (edge case)" {
    // "1.0.0-" debería manejar el caso de prerelease vacío
    const result = Version.parse("1.0.0-");
    // Verificar que no crashea, aunque el prerelease esté vacío
    try testing.expect(result == .ok);
}

// ============================================================================
// ERRORES - Inputs inválidos que deben ser rechazados
// ============================================================================

test "parse: string vacío → error" {
    const result = Version.parse("");
    try testing.expect(result == .err);
    try testing.expectEqual(@as(@TypeOf(result.err.code), .invalid_input), result.err.code);
}

test "parse: letras en major → error" {
    const result = Version.parse("abc.1.2");
    try testing.expect(result == .err);
    try testing.expectEqual(@as(@TypeOf(result.err.code), .parse_error), result.err.code);
}

test "parse: número negativo → error" {
    // "-1.0.0" no debería parsearse como versión válida
    const result = Version.parse("-1.0.0");
    try testing.expect(result == .err);
}

// ============================================================================
// COMPARACIÓN - Lógica de ordenamiento
// ============================================================================

test "compare: mayor version gana" {
    const v1 = Version.parse("1.0.0").unwrap();
    const v2 = Version.parse("2.0.0").unwrap();
    try testing.expect(v1.lessThan(v2));
    try testing.expect(!v2.lessThan(v1));
}

test "compare: minor version desempata" {
    const v1 = Version.parse("1.1.0").unwrap();
    const v2 = Version.parse("1.2.0").unwrap();
    try testing.expect(v1.lessThan(v2));
}

test "compare: patch version desempata" {
    const v1 = Version.parse("1.1.1").unwrap();
    const v2 = Version.parse("1.1.2").unwrap();
    try testing.expect(v1.lessThan(v2));
}

test "compare: prerelease < release (semver spec)" {
    const pre = Version.parse("1.0.0-beta").unwrap();
    const rel = Version.parse("1.0.0").unwrap();
    try testing.expect(pre.lessThan(rel));
}

test "compare: igualdad" {
    const v1 = Version.parse("1.2.3").unwrap();
    const v2 = Version.parse("1.2.3").unwrap();
    try testing.expect(v1.eql(v2));
    try testing.expect(!v1.lessThan(v2));
    try testing.expect(!v2.lessThan(v1));
}

// ============================================================================
// CONSTRAINTS - Rangos de versión
// ============================================================================

test "constraint: >= satisface versiones mayores o iguales" {
    const c = Constraint.parse(">=1.0.0").unwrap();
    try testing.expect(c.satisfies(Version.parse("1.0.0").unwrap()));
    try testing.expect(c.satisfies(Version.parse("1.0.1").unwrap()));
    try testing.expect(c.satisfies(Version.parse("2.0.0").unwrap()));
    try testing.expect(!c.satisfies(Version.parse("0.9.9").unwrap()));
}

test "constraint: < satisface versiones menores" {
    const c = Constraint.parse("<2.0.0").unwrap();
    try testing.expect(c.satisfies(Version.parse("1.9.9").unwrap()));
    try testing.expect(!c.satisfies(Version.parse("2.0.0").unwrap()));
    try testing.expect(!c.satisfies(Version.parse("2.0.1").unwrap()));
}

test "constraint: ^ (caret) permite minor/patch updates" {
    const c = Constraint.parse("^1.2.0").unwrap();
    try testing.expect(c.satisfies(Version.parse("1.2.0").unwrap()));
    try testing.expect(c.satisfies(Version.parse("1.2.5").unwrap()));
    try testing.expect(c.satisfies(Version.parse("1.9.0").unwrap()));
    try testing.expect(!c.satisfies(Version.parse("2.0.0").unwrap())); // major cambió
    try testing.expect(!c.satisfies(Version.parse("1.1.0").unwrap())); // menor que constraint
}

test "constraint: ~ (tilde) solo permite patch updates" {
    const c = Constraint.parse("~1.2.0").unwrap();
    try testing.expect(c.satisfies(Version.parse("1.2.0").unwrap()));
    try testing.expect(c.satisfies(Version.parse("1.2.5").unwrap()));
    try testing.expect(!c.satisfies(Version.parse("1.3.0").unwrap())); // minor cambió
}

// ============================================================================
// FORMAT - Roundtrip parsing
// ============================================================================

test "format: roundtrip básico" {
    const original = "1.2.3";
    const v = Version.parse(original).unwrap();
    var buf: [32]u8 = undefined;
    const formatted = v.format(&buf);
    try testing.expectEqualStrings("1.2.3", formatted);
}

test "format: latest" {
    const v = Version.parse("latest").unwrap();
    var buf: [32]u8 = undefined;
    const formatted = v.format(&buf);
    try testing.expectEqualStrings("latest", formatted);
}

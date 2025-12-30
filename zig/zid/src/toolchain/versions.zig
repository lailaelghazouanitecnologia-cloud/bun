//! Versions - Semantic versioning parser
//!
//! Parse and compare version strings (semver).
//! Uses misc.Maybe for error handling.

const std = @import("std");
const zid = @import("../zid.zig");
const Maybe = zid.Maybe;

/// Semantic version
pub const Version = struct {
    major: u32 = 0,
    minor: u32 = 0,
    patch: u32 = 0,
    prerelease: ?[]const u8 = null,
    build: ?[]const u8 = null,

    pub const latest = Version{ .major = std.math.maxInt(u32) };

    /// Parse version string (e.g., "1.2.3", "1.2.3-beta", "1.2.3+build")
    pub fn parse(str: []const u8) Maybe(Version) {
        if (str.len == 0) {
            return zid.err(Version, .{
                .code = .invalid_input,
                .message = "empty version string",
            });
        }

        // Handle "latest" keyword
        if (std.mem.eql(u8, str, "latest")) {
            return zid.ok(Version, latest);
        }

        var version = Version{};
        var remaining = str;

        // Skip 'v' prefix if present
        if (remaining[0] == 'v' or remaining[0] == 'V') {
            remaining = remaining[1..];
        }

        // Parse major
        const major_end = std.mem.indexOfAny(u8, remaining, ".-+") orelse remaining.len;
        version.major = std.fmt.parseInt(u32, remaining[0..major_end], 10) catch {
            return zid.err(Version, .{
                .code = .parse_error,
                .message = "invalid major version",
            });
        };

        if (major_end >= remaining.len) {
            return zid.ok(Version, version);
        }

        remaining = remaining[major_end..];
        if (remaining.len == 0 or remaining[0] != '.') {
            return zid.ok(Version, version);
        }
        remaining = remaining[1..]; // skip '.'

        // Parse minor
        const minor_end = std.mem.indexOfAny(u8, remaining, ".-+") orelse remaining.len;
        if (minor_end > 0) {
            version.minor = std.fmt.parseInt(u32, remaining[0..minor_end], 10) catch {
                return zid.err(Version, .{
                    .code = .parse_error,
                    .message = "invalid minor version",
                });
            };
        }

        if (minor_end >= remaining.len) {
            return zid.ok(Version, version);
        }

        remaining = remaining[minor_end..];
        if (remaining.len == 0 or remaining[0] != '.') {
            // Could be prerelease or build
            if (remaining[0] == '-') {
                version.prerelease = remaining[1..];
            } else if (remaining[0] == '+') {
                version.build = remaining[1..];
            }
            return zid.ok(Version, version);
        }
        remaining = remaining[1..]; // skip '.'

        // Parse patch
        const patch_end = std.mem.indexOfAny(u8, remaining, "-+") orelse remaining.len;
        if (patch_end > 0) {
            version.patch = std.fmt.parseInt(u32, remaining[0..patch_end], 10) catch {
                return zid.err(Version, .{
                    .code = .parse_error,
                    .message = "invalid patch version",
                });
            };
        }

        if (patch_end >= remaining.len) {
            return zid.ok(Version, version);
        }

        remaining = remaining[patch_end..];

        // Parse prerelease
        if (remaining.len > 0 and remaining[0] == '-') {
            const pre_end = std.mem.indexOf(u8, remaining[1..], "+") orelse remaining.len - 1;
            version.prerelease = remaining[1 .. pre_end + 1];
            remaining = remaining[pre_end + 1 ..];
        }

        // Parse build
        if (remaining.len > 0 and remaining[0] == '+') {
            version.build = remaining[1..];
        }

        return zid.ok(Version, version);
    }

    /// Format version as string
    pub fn format(self: Version, buf: []u8) []const u8 {
        var len: usize = 0;

        if (self.major == std.math.maxInt(u32)) {
            return "latest";
        }

        len += (std.fmt.bufPrint(buf[len..], "{d}.{d}.{d}", .{
            self.major,
            self.minor,
            self.patch,
        }) catch return "").len;

        if (self.prerelease) |pre| {
            buf[len] = '-';
            len += 1;
            @memcpy(buf[len .. len + pre.len], pre);
            len += pre.len;
        }

        if (self.build) |b| {
            buf[len] = '+';
            len += 1;
            @memcpy(buf[len .. len + b.len], b);
            len += b.len;
        }

        return buf[0..len];
    }

    /// Compare versions (-1, 0, 1)
    pub fn compare(a: Version, b: Version) std.math.Order {
        if (a.major != b.major) return std.math.order(a.major, b.major);
        if (a.minor != b.minor) return std.math.order(a.minor, b.minor);
        if (a.patch != b.patch) return std.math.order(a.patch, b.patch);

        // Prerelease versions have lower precedence
        if (a.prerelease != null and b.prerelease == null) return .lt;
        if (a.prerelease == null and b.prerelease != null) return .gt;

        return .eq;
    }

    pub fn lessThan(a: Version, b: Version) bool {
        return compare(a, b) == .lt;
    }

    pub fn eql(a: Version, b: Version) bool {
        return compare(a, b) == .eq;
    }

    pub fn isLatest(self: Version) bool {
        return self.major == std.math.maxInt(u32);
    }
};

/// Version constraint (e.g., ">=1.0.0", "^1.2.0", "~1.2.3")
pub const Constraint = struct {
    op: Op,
    version: Version,

    pub const Op = enum {
        eq, // =1.0.0 (exact)
        gt, // >1.0.0
        gte, // >=1.0.0
        lt, // <1.0.0
        lte, // <=1.0.0
        caret, // ^1.0.0 (compatible)
        tilde, // ~1.0.0 (patch updates)
    };

    pub fn parse(str: []const u8) Maybe(Constraint) {
        var s = str;
        var op: Op = .eq;

        if (s.len >= 2) {
            if (std.mem.eql(u8, s[0..2], ">=")) {
                op = .gte;
                s = s[2..];
            } else if (std.mem.eql(u8, s[0..2], "<=")) {
                op = .lte;
                s = s[2..];
            }
        }

        if (s.len >= 1 and op == .eq) {
            switch (s[0]) {
                '>' => {
                    op = .gt;
                    s = s[1..];
                },
                '<' => {
                    op = .lt;
                    s = s[1..];
                },
                '^' => {
                    op = .caret;
                    s = s[1..];
                },
                '~' => {
                    op = .tilde;
                    s = s[1..];
                },
                '=' => {
                    op = .eq;
                    s = s[1..];
                },
                else => {},
            }
        }

        return switch (Version.parse(s)) {
            .ok => |v| zid.ok(Constraint, .{ .op = op, .version = v }),
            .err => |e| zid.err(Constraint, e),
        };
    }

    /// Check if version satisfies constraint
    pub fn satisfies(self: Constraint, v: Version) bool {
        return switch (self.op) {
            .eq => v.eql(self.version),
            .gt => v.compare(self.version) == .gt,
            .gte => v.compare(self.version) != .lt,
            .lt => v.compare(self.version) == .lt,
            .lte => v.compare(self.version) != .gt,
            .caret => v.major == self.version.major and v.compare(self.version) != .lt,
            .tilde => v.major == self.version.major and
                v.minor == self.version.minor and
                v.compare(self.version) != .lt,
        };
    }
};

// ============ TESTS ============

test "Version.parse basic" {
    const v = Version.parse("1.2.3").unwrap();
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqual(@as(u32, 2), v.minor);
    try std.testing.expectEqual(@as(u32, 3), v.patch);
}

test "Version.parse with v prefix" {
    const v = Version.parse("v1.2.3").unwrap();
    try std.testing.expectEqual(@as(u32, 1), v.major);
}

test "Version.parse prerelease" {
    const v = Version.parse("1.0.0-beta.1").unwrap();
    try std.testing.expectEqual(@as(u32, 1), v.major);
    try std.testing.expectEqualStrings("beta.1", v.prerelease.?);
}

test "Version.compare" {
    const v1 = Version.parse("1.0.0").unwrap();
    const v2 = Version.parse("2.0.0").unwrap();
    try std.testing.expect(v1.lessThan(v2));
    try std.testing.expect(!v2.lessThan(v1));
}

test "Constraint.satisfies" {
    const c = Constraint.parse(">=1.0.0").unwrap();
    try std.testing.expect(c.satisfies(Version.parse("1.0.0").unwrap()));
    try std.testing.expect(c.satisfies(Version.parse("2.0.0").unwrap()));
    try std.testing.expect(!c.satisfies(Version.parse("0.9.0").unwrap()));
}

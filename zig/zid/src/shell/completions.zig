//! Shell Completions Generator
//!
//! Generates shell completions for bash, zsh, and fish.
//!
//! ## Usage
//! ```zig
//! const completions = @import("shell/completions.zig");
//!
//! // Generate completions
//! const bash = completions.generate(.bash);
//! const zsh = completions.generate(.zsh);
//! const fish = completions.generate(.fish);
//!
//! // Detect shell and get completions
//! const shell = completions.detectShell();
//! const script = completions.generate(shell);
//! ```

const std = @import("std");
const builtin = @import("builtin");

/// Supported shell types
pub const ShellType = enum {
    bash,
    zsh,
    fish,
    pwsh,
    unknown,

    pub fn fromString(s: []const u8) ShellType {
        const basename = std.fs.path.basename(s);
        if (std.mem.eql(u8, basename, "bash")) return .bash;
        if (std.mem.eql(u8, basename, "zsh")) return .zsh;
        if (std.mem.eql(u8, basename, "fish")) return .fish;
        if (std.mem.eql(u8, basename, "pwsh")) return .pwsh;
        if (std.mem.eql(u8, basename, "powershell")) return .pwsh;
        return .unknown;
    }

    pub fn string(self: ShellType) []const u8 {
        return switch (self) {
            .bash => "bash",
            .zsh => "zsh",
            .fish => "fish",
            .pwsh => "pwsh",
            .unknown => "unknown",
        };
    }
};

/// Detect current shell from environment
pub fn detectShell() ShellType {
    if (std.posix.getenv("SHELL")) |shell| {
        return ShellType.fromString(shell);
    }
    return .unknown;
}

/// Command definition for completions
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    aliases: []const []const u8 = &.{},
    flags: []const Flag = &.{},
    subcommands: []const Command = &.{},
    positional: ?Positional = null,
};

pub const Flag = struct {
    long: []const u8,
    short: ?u8 = null,
    description: []const u8,
    has_value: bool = false,
    value_type: ?[]const u8 = null,
    choices: []const []const u8 = &.{},
};

pub const Positional = struct {
    name: []const u8,
    completion_type: CompletionType,
    multiple: bool = false,
};

pub const CompletionType = enum {
    file,
    directory,
    tool,
    version,
    custom,
};

/// Zid CLI commands
pub const zid_commands = [_]Command{
    .{
        .name = "install",
        .description = "Install a tool",
        .aliases = &.{"i"},
        .flags = &.{
            .{ .long = "force", .short = 'f', .description = "Force reinstall" },
            .{ .long = "global", .short = 'g', .description = "Install globally" },
            .{ .long = "version", .short = 'v', .description = "Specific version", .has_value = true },
        },
        .positional = .{ .name = "tool", .completion_type = .tool },
    },
    .{
        .name = "update",
        .description = "Update installed tools",
        .aliases = &.{"up"},
        .flags = &.{
            .{ .long = "all", .short = 'a', .description = "Update all tools" },
        },
        .positional = .{ .name = "tool", .completion_type = .tool, .multiple = true },
    },
    .{
        .name = "list",
        .description = "List installed tools",
        .aliases = &.{"ls"},
        .flags = &.{
            .{ .long = "all", .short = 'a', .description = "Show all available" },
            .{ .long = "json", .description = "Output as JSON" },
        },
    },
    .{
        .name = "search",
        .description = "Search for tools",
        .aliases = &.{"s"},
        .flags = &.{
            .{ .long = "category", .short = 'c', .description = "Filter by category", .has_value = true },
            .{ .long = "tag", .short = 't', .description = "Filter by tag", .has_value = true },
        },
        .positional = .{ .name = "query", .completion_type = .custom },
    },
    .{
        .name = "use",
        .description = "Switch to a specific tool version",
        .flags = &.{
            .{ .long = "global", .short = 'g', .description = "Set as global default" },
        },
        .positional = .{ .name = "tool@version", .completion_type = .tool },
    },
    .{
        .name = "init",
        .description = "Initialize zid in current directory",
        .flags = &.{
            .{ .long = "force", .short = 'f', .description = "Overwrite existing config" },
        },
    },
    .{
        .name = "add",
        .description = "Add a capsule dependency",
        .aliases = &.{"a"},
        .positional = .{ .name = "capsule", .completion_type = .custom },
    },
    .{
        .name = "patch",
        .description = "Apply or manage patches",
        .subcommands = &.{
            .{ .name = "apply", .description = "Apply a patch" },
            .{ .name = "create", .description = "Create a patch" },
            .{ .name = "list", .description = "List patches" },
        },
    },
    .{
        .name = "completions",
        .description = "Generate shell completions",
        .flags = &.{
            .{ .long = "shell", .short = 's', .description = "Shell type", .has_value = true, .choices = &.{ "bash", "zsh", "fish" } },
            .{ .long = "install", .description = "Install to profile" },
        },
    },
    .{
        .name = "help",
        .description = "Show help",
        .aliases = &.{"h"},
    },
    .{
        .name = "version",
        .description = "Show version",
        .aliases = &.{"v"},
    },
};

/// Global flags
pub const global_flags = [_]Flag{
    .{ .long = "help", .short = 'h', .description = "Show help" },
    .{ .long = "version", .short = 'V', .description = "Show version" },
    .{ .long = "quiet", .short = 'q', .description = "Suppress output" },
    .{ .long = "verbose", .description = "Verbose output" },
    .{ .long = "color", .description = "Color mode", .has_value = true, .choices = &.{ "auto", "always", "never" } },
};

// ============ GENERATORS ============

/// Generate completions for specified shell
pub fn generate(shell: ShellType, writer: anytype) !void {
    switch (shell) {
        .bash => try generateBash(writer),
        .zsh => try generateZsh(writer),
        .fish => try generateFish(writer),
        else => return error.UnsupportedShell,
    }
}

fn generateBash(writer: anytype) !void {
    try writer.writeAll(
        \\#!/usr/bin/env bash
        \\
        \\_zid_completions() {
        \\    local cur prev words cword
        \\    _init_completion || return
        \\
        \\    local commands="
    );

    // Add commands
    for (zid_commands) |cmd| {
        try writer.print("{s} ", .{cmd.name});
        for (cmd.aliases) |alias| {
            try writer.print("{s} ", .{alias});
        }
    }

    try writer.writeAll(
        \\"
        \\
        \\    case "$prev" in
        \\        zid)
        \\            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        \\            return
        \\            ;;
        \\        install|i|update|up|use)
        \\            # Complete with available tools
        \\            local tools="bun zig node deno go rust"
        \\            COMPREPLY=($(compgen -W "$tools" -- "$cur"))
        \\            return
        \\            ;;
        \\        --shell|-s)
        \\            COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
        \\            return
        \\            ;;
        \\    esac
        \\
        \\    # Handle flags
        \\    if [[ "$cur" == -* ]]; then
        \\        local flags="--help -h --version -V --quiet -q --verbose --color"
        \\        COMPREPLY=($(compgen -W "$flags" -- "$cur"))
        \\        return
        \\    fi
        \\}
        \\
        \\complete -F _zid_completions zid
        \\
    );
}

fn generateZsh(writer: anytype) !void {
    try writer.writeAll(
        \\#compdef zid
        \\
        \\_zid() {
        \\    local -a commands
        \\    commands=(
        \\
    );

    // Add commands with descriptions
    for (zid_commands) |cmd| {
        try writer.print("        '{s}:{s}'\n", .{ cmd.name, cmd.description });
        for (cmd.aliases) |alias| {
            try writer.print("        '{s}:{s}'\n", .{ alias, cmd.description });
        }
    }

    try writer.writeAll(
        \\    )
        \\
        \\    local -a tools
        \\    tools=(
        \\        'bun:JavaScript runtime & toolkit'
        \\        'zig:Systems programming language'
        \\        'node:JavaScript runtime'
        \\        'deno:Secure JavaScript/TypeScript runtime'
        \\        'go:Go programming language'
        \\        'rust:Rust programming language'
        \\    )
        \\
        \\    _arguments -s \
        \\        '1: :->cmd' \
        \\        '*: :->args' \
        \\        '--help[Show help]' \
        \\        '-h[Show help]' \
        \\        '--version[Show version]' \
        \\        '-V[Show version]' \
        \\        '--quiet[Suppress output]' \
        \\        '-q[Suppress output]' \
        \\        '--verbose[Verbose output]' \
        \\        '--color[Color mode]:mode:(auto always never)'
        \\
        \\    case $state in
        \\    cmd)
        \\        _describe 'command' commands
        \\        ;;
        \\    args)
        \\        case $line[1] in
        \\        install|i|update|up|use)
        \\            _describe 'tool' tools
        \\            ;;
        \\        search|s)
        \\            _message 'search query'
        \\            ;;
        \\        completions)
        \\            _arguments \
        \\                '--shell[Shell type]:shell:(bash zsh fish)' \
        \\                '-s[Shell type]:shell:(bash zsh fish)' \
        \\                '--install[Install to profile]'
        \\            ;;
        \\        esac
        \\        ;;
        \\    esac
        \\}
        \\
        \\_zid "$@"
        \\
    );
}

fn generateFish(writer: anytype) !void {
    try writer.writeAll(
        \\# Zid completions for fish
        \\
        \\# Clear existing
        \\complete -e -c zid
        \\
        \\# Subcommands
        \\
    );

    for (zid_commands) |cmd| {
        try writer.print(
            "complete -c zid -n '__fish_use_subcommand' -a '{s}' -d '{s}'\n",
            .{ cmd.name, cmd.description },
        );
        for (cmd.aliases) |alias| {
            try writer.print(
                "complete -c zid -n '__fish_use_subcommand' -a '{s}' -d '{s}'\n",
                .{ alias, cmd.description },
            );
        }
    }

    try writer.writeAll(
        \\
        \\# Tools for install/update/use
        \\set -l tools 'bun\tJavaScript runtime' 'zig\tSystems language' 'node\tJS runtime' 'deno\tSecure TS runtime' 'go\tGo language' 'rust\tRust language'
        \\
        \\complete -c zid -n '__fish_seen_subcommand_from install i update up use' -a "$tools"
        \\
        \\# Global flags
        \\complete -c zid -s h -l help -d 'Show help'
        \\complete -c zid -s V -l version -d 'Show version'
        \\complete -c zid -s q -l quiet -d 'Suppress output'
        \\complete -c zid -l verbose -d 'Verbose output'
        \\complete -c zid -l color -d 'Color mode' -xa 'auto always never'
        \\
        \\# Completions command
        \\complete -c zid -n '__fish_seen_subcommand_from completions' -s s -l shell -d 'Shell type' -xa 'bash zsh fish'
        \\complete -c zid -n '__fish_seen_subcommand_from completions' -l install -d 'Install to profile'
        \\
    );
}

// ============ INSTALL ============

/// Shell profile paths
pub const ShellProfiles = struct {
    pub fn getProfilePaths(shell: ShellType) []const []const u8 {
        return switch (shell) {
            .bash => &.{ ".bashrc", ".bash_profile", ".profile" },
            .zsh => &.{ ".zshrc", ".zprofile" },
            .fish => &.{".config/fish/config.fish"},
            else => &.{},
        };
    }

    pub fn getCompletionDir(shell: ShellType) ?[]const u8 {
        return switch (shell) {
            .bash => ".bash_completion.d",
            .zsh => ".zsh/completions",
            .fish => ".config/fish/completions",
            else => null,
        };
    }

    pub fn getCompletionFilename(shell: ShellType) []const u8 {
        return switch (shell) {
            .bash => "zid.bash",
            .zsh => "_zid",
            .fish => "zid.fish",
            else => "zid",
        };
    }
};

/// Install completions to user's shell config
pub fn install(allocator: std.mem.Allocator, shell: ShellType) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;

    // Get completion directory
    const comp_dir_rel = ShellProfiles.getCompletionDir(shell) orelse return error.UnsupportedShell;
    const comp_dir = try std.fs.path.join(allocator, &.{ home, comp_dir_rel });
    defer allocator.free(comp_dir);

    // Create directory if needed
    std.fs.makeDirAbsolute(comp_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Write completion file
    const filename = ShellProfiles.getCompletionFilename(shell);
    const filepath = try std.fs.path.join(allocator, &.{ comp_dir, filename });
    defer allocator.free(filepath);

    const file = try std.fs.createFileAbsolute(filepath, .{});
    defer file.close();

    try generate(shell, file.writer());
}

// ============ TESTS ============

test "detectShell" {
    // Test fromString
    try std.testing.expectEqual(ShellType.bash, ShellType.fromString("/bin/bash"));
    try std.testing.expectEqual(ShellType.zsh, ShellType.fromString("/usr/bin/zsh"));
    try std.testing.expectEqual(ShellType.fish, ShellType.fromString("/usr/local/bin/fish"));
}

test "generate bash completions" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try generate(.bash, fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "_zid_completions") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "complete -F") != null);
}

test "generate zsh completions" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try generate(.zsh, fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "#compdef zid") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_describe") != null);
}

test "generate fish completions" {
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try generate(.fish, fbs.writer());

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "complete -c zid") != null);
}

//! CLI Completions Command
//!
//! Generate and install shell completions.
//!
//! Usage:
//!   zid completions              # Print for current shell
//!   zid completions --shell zsh  # Print for specific shell
//!   zid completions --install    # Install to shell config

const std = @import("std");
const Output = @import("../output.zig");
const completions = @import("../shell/mod.zig").completions;
const ShellType = completions.ShellType;

pub fn run(alloc: std.mem.Allocator, args: []const []const u8) void {
    var shell: ?ShellType = null;
    var do_install = false;

    // Parse args
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (eql(arg, "--shell") or eql(arg, "-s")) {
            if (i + 1 < args.len) {
                i += 1;
                shell = ShellType.fromString(args[i]);
                if (shell == .unknown) {
                    Output.err("Unknown shell: {s}\n", .{args[i]});
                    Output.print("Supported: bash, zsh, fish\n", .{});
                    return;
                }
            }
        } else if (eql(arg, "--install")) {
            do_install = true;
        } else if (eql(arg, "--help") or eql(arg, "-h")) {
            printHelp();
            return;
        } else if (arg.len > 0 and arg[0] != '-') {
            // Positional argument - treat as shell name
            shell = ShellType.fromString(arg);
        }
    }

    // Detect shell if not specified
    const target_shell = shell orelse completions.detectShell();
    if (target_shell == .unknown) {
        Output.err("Could not detect shell. Please specify with --shell.\n", .{});
        Output.print("Supported: bash, zsh, fish\n", .{});
        return;
    }

    if (do_install) {
        // Install completions to shell config
        installCompletions(alloc, target_shell);
    } else {
        // Print completions to stdout
        printCompletions(target_shell);
    }
}

fn printCompletions(shell: ShellType) void {
    var buf: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    completions.generate(shell, fbs.writer()) catch |err| {
        Output.err("Failed to generate completions: {}\n", .{err});
        return;
    };

    const stdout = std.io.getStdOut().writer();
    stdout.writeAll(fbs.getWritten()) catch {};
}

fn installCompletions(alloc: std.mem.Allocator, shell: ShellType) void {
    completions.install(alloc, shell) catch |err| {
        Output.err("Failed to install completions: {}\n", .{err});
        return;
    };

    Output.success("Completions installed for {s}!\n", .{shell.string()});
    Output.print("\nRestart your shell or run:\n", .{});

    switch (shell) {
        .bash => Output.print("  source ~/.bash_completion.d/zid.bash\n", .{}),
        .zsh => Output.print("  source ~/.zsh/completions/_zid\n", .{}),
        .fish => Output.print("  source ~/.config/fish/completions/zid.fish\n", .{}),
        else => {},
    }
}

fn printHelp() void {
    Output.bold("zid completions - Shell completion support\n\n", .{});
    Output.print("Usage:\n", .{});
    Output.print("  zid completions                    Print for current shell\n", .{});
    Output.print("  zid completions --shell <shell>    Print for specific shell\n", .{});
    Output.print("  zid completions --install          Install to shell config\n", .{});
    Output.print("\n", .{});
    Output.print("Options:\n", .{});
    Output.print("  -s, --shell <shell>   Shell type: bash, zsh, fish\n", .{});
    Output.print("      --install         Install completions to config\n", .{});
    Output.print("  -h, --help            Show this help\n", .{});
    Output.print("\n", .{});
    Output.print("Examples:\n", .{});
    Output.print("  zid completions > ~/.bash_completion.d/zid.bash\n", .{});
    Output.print("  zid completions --shell zsh --install\n", .{});
    Output.print("  eval \"$(zid completions)\"\n", .{});
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

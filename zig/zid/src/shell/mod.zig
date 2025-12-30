//! Shell Module - Shell integration and completions
//!
//! Provides shell completions, environment management, and integration.

pub const completions = @import("completions.zig");

// Re-export common types
pub const ShellType = completions.ShellType;
pub const detectShell = completions.detectShell;
pub const generate = completions.generate;
pub const install = completions.install;

test {
    _ = completions;
}

# Zid Development Guide

This is the Zid repository - a universal development toolkit with toolchain manager, apps registry, and transpiler framework. Written in Zig.

## Building

```bash
zig build                  # Debug build
zig build -Doptimize=ReleaseFast  # Release build
zig build run -- help      # Run with args
```

## Testing

```bash
zig build test             # Run all tests
```

## Project Structure

```
src/
├── main.zig              # Entry point
├── zid.zig               # Root module (exports all APIs)
├── cli.zig               # CLI command router
├── env.zig               # Platform/build conditionals
├── output.zig            # Terminal output with colors
├── strings.zig           # String utilities
├── fs.zig                # File system operations
├── cli/                  # CLI commands
│   ├── install.zig       # install/uninstall/use
│   ├── add.zig           # add/remove apps
│   ├── init.zig          # init project
│   ├── build.zig         # build/watch
│   └── help.zig          # help
├── toolchain/            # Toolchain manager
│   └── toolchain.zig
├── apps/                 # Apps registry
│   └── apps.zig
└── framework/            # Transpiler framework
    ├── framework.zig
    ├── pipeline.zig
    └── metadata.zig
```

## Key Patterns

- **Root module**: `zid.zig` exports all public APIs
- **Environment**: `env.zig` for compile-time platform checks
- **Threadlocal buffers**: `zid.path_buf` for temp operations
- **Scoped logging**: `Output.scoped(.CLI)` with `ZID_DEBUG_CLI=1`
- **Commands**: Each command in separate file in `cli/`

## Architecture

Following Bun's architecture:
1. Core utilities (env, output, strings, fs)
2. CLI with separate command files
3. Subsystems (toolchain, apps, framework)
4. Tests in separate `test/` directory

## Important Notes

- Tests go in `test/`, not inline
- Use `zid.default_allocator` for allocations
- Check `Environment.isDebug` for debug-only code
- Follow existing code patterns

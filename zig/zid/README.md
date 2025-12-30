# Zid

Universal Development Toolkit - Toolchain manager, apps registry, and transpiler framework.

## Features

- **Toolchain Manager**: Install and manage compilers (zig, rust, bun, node, go...)
- **Apps Registry**: User programs become direct commands
- **Framework**: API for building transpilers with Pipeline

## Install

```bash
zig build -Doptimize=ReleaseFast
# Binary at: zig-out/bin/zid
```

## Usage

```bash
# Toolchain
zid install zig@0.13.0    # Install Zig
zid install rust          # Install latest Rust
zid list                  # List installed tools
zid use zig@0.12.0        # Switch version

# Apps
zid add ./my-tool         # Add app (becomes command)
zid my-tool               # Run directly

# Framework
zid init lua-to-wasm      # Create transpiler project
zid build                 # Build
zid watch                 # Watch mode
```

## Project Structure

```
zid/
├── src/                  # Source code
│   ├── main.zig          # Entry point
│   ├── zid.zig           # Root module
│   ├── cli.zig           # CLI router
│   ├── cli/              # Commands
│   ├── toolchain/        # Toolchain manager
│   ├── apps/             # Apps registry
│   └── framework/        # Transpiler framework
├── test/                 # Tests
├── scripts/              # Build scripts
└── build.zig             # Build configuration
```

## Development

```bash
zig build run -- help     # Run with args
zig build test            # Run tests
zig build fmt             # Format code
```

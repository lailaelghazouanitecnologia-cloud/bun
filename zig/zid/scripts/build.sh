#!/bin/bash
# Build script for zid

set -e

cd "$(dirname "$0")/.."

echo "Building zid..."
zig build -Doptimize=ReleaseFast

echo "Done: zig-out/bin/zid"

#!/usr/bin/env bash
# Builds the cycles_core crate for macOS (arm64 & x86_64) and creates a universal dylib.
# Run on a macOS host or in GitHub Actions on a macos-latest runner before `flutter build macos`.
set -euo pipefail

cd "$(dirname "$0")/../rust"

echo "Building cycles_core for macOS (Apple Silicon + Intel)..."
rustup target add aarch64-apple-darwin x86_64-apple-darwin || true

cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

mkdir -p ../macos/Frameworks
lipo -create \
  target/aarch64-apple-darwin/release/libcycles_core.dylib \
  target/x86_64-apple-darwin/release/libcycles_core.dylib \
  -output ../macos/Frameworks/libcycles_core.dylib

echo "Created universal macOS dylib at macos/Frameworks/libcycles_core.dylib"

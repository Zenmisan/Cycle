#!/usr/bin/env bash
# Cross-compiles the rust/ crate for Android ABIs and drops the .so files into
# android/app/src/main/jniLibs/ where Gradle picks them up automatically.
# Run this before `flutter build apk` / `flutter run -d <android-device>`
# whenever the Rust crate changes. Requires: cargo-ndk, rustup android targets,
# ANDROID_NDK_HOME pointing at an installed NDK.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to your NDK install, e.g. \$HOME/Android/Sdk/ndk/<version>}"

cargo ndk \
  -t arm64-v8a -t armeabi-v7a -t x86_64 \
  -o android/app/src/main/jniLibs \
  --manifest-path rust/Cargo.toml \
  build --release

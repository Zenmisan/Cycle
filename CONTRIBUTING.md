# Contributing to Cycles

Thank you for your interest in contributing to **Cycles**! Whether you are reporting a bug, proposing a feature, or writing code, your help is welcome.

Cycles is a local-first, peer-to-peer proximity task sync app built with **Flutter**, **Rust**, **Automerge CRDTs**, and **Bluetooth Low Energy (BLE)**.

---

## 🛠️ Prerequisites

To build and contribute to Cycles, ensure you have the following installed on your machine:

1. **Flutter SDK**: `>= 3.13.2` with Dart SDK `>= 3.13.2`.
   - Verify with: `flutter doctor`
2. **Rust Toolchain**: Stable Rust with `edition = "2024"`.
   - Install via [rustup.rs](https://rustup.rs/): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
3. **Flutter Rust Bridge Codegen**:
   - Install version 2.13.0:
     ```bash
     cargo install 'flutter_rust_bridge_codegen@=2.13.0'
     ```
4. **Linux BLE Development Packages** (for Linux development):
   - BlueZ development headers and D-Bus libraries:
     ```bash
     sudo apt-get install libdbus-1-dev pkg-config
     ```
5. **Android NDK & cargo-ndk** (for Android cross-compilation):
   - Install `cargo-ndk`:
     ```bash
     cargo install cargo-ndk
     ```
   - Add Rust Android targets:
     ```bash
     rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
     ```

---

## 🚀 Setting Up the Development Environment

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Zenmisan/Cycle.git
   cd Cycle
   ```

2. **Fetch Flutter dependencies**:
   ```bash
   flutter pub get
   ```

3. **Build the Rust core library**:
   ```bash
   cd rust
   cargo build
   cd ..
   ```

---

## 🔄 Code Generation Workflow

Cycles uses code generators for both its database layer (Drift) and its Rust-to-Dart FFI bridge (`flutter_rust_bridge`). Whenever you modify Rust FFI signatures or Drift table definitions, run the appropriate generator:

### 1. Flutter Rust Bridge (FFI)
When changing [`rust/src/api.rs`](file:///home/zenmi/Projects/Cycle/rust/src/api.rs):
```bash
flutter_rust_bridge_codegen generate \
  --rust-root rust \
  --rust-input crate::api \
  --dart-output lib/rust_bridge
```

### 2. Drift SQLite Schema
When changing [`lib/data/tables.dart`](file:///home/zenmi/Projects/Cycle/lib/data/tables.dart) or [`lib/data/database.dart`](file:///home/zenmi/Projects/Cycle/lib/data/database.dart):
```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 🧪 Testing & Verification

Before submitting changes, ensure all tests pass across both Rust and Dart:

### 1. Run Rust Core Tests
Tests all CRDT merge logic, BLE chunking, CRC32 verification, TOFU pairing, and tie-breaking:
```bash
cd rust
cargo test
cd ..
```

### 2. Run Flutter Static Analysis
Ensure there are no lint or type warnings:
```bash
flutter analyze
```

### 3. Run Flutter Widget & Bridge Tests
```bash
flutter test
```

### 4. Verify Android Native Cross-Compilation (Optional but recommended)
If you made changes to Rust dependencies or platform bindings:
```bash
ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/<version> ./scripts/build_android_rust.sh
```

---

## 📐 Architecture Invariants

When working on the codebase, adhere to these architectural rules:

1. **The Single-Store Invariant**:
   - Drift owns relational queries for the UI; Automerge owns conflict resolution and merge history.
   - Raw Automerge binary change vectors are stored in the SQLite `sync_changes` table.
   - Never create a second database or diverge relational state from the Automerge document.
2. **Platform Gating**:
   - BlueZ and `bluer` dependencies must be target-gated under `#[cfg(target_os = "linux")]` in Rust to ensure Android, iOS, and Windows continue to compile cleanly without missing symbols.
3. **No Central Server Dependency**:
   - All primary synchronization must operate purely over peer-to-peer mechanisms (BLE GATT / local mDNS). Do not add remote cloud service requirements to core workflows.

---

## 📝 Commit Conventions

We follow [Conventional Commits](https://www.conventionalcommits.org/) for commit messages:

- `feat:` A new feature (e.g. `feat(ble): add RSSI signal sorting to peer list`)
- `fix:` A bug fix (e.g. `fix(crdt): prevent duplicate state vector serialization`)
- `docs:` Documentation improvements
- `refactor:` Code reorganization without behavioral changes
- `test:` Adding or correcting tests

---

## 🤝 Pull Request Process

1. Fork the repository and create your feature branch: `git checkout -b feat/my-feature`.
2. Commit your changes with clear, conventional messages.
3. Run `cargo test`, `flutter analyze`, and `flutter test`.
4. Submit a Pull Request describing the context, changes, and testing evidence.

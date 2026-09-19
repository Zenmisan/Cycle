<p align="center">
  <img src="assets/icon/cycle.svg" alt="Cycles Logo" width="128" height="128">
</p>

<h1 align="center">Cycles</h1>

<p align="center">
  <strong>Offline-first, peer-to-peer proximity task sync — no account, no cloud, no server required.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/flutter-3.13+-02569B.svg?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/rust-edition%202024-DEA584.svg?logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/CRDT-Automerge-ff69b4.svg" alt="Automerge CRDT">
  <img src="https://img.shields.io/badge/platforms-Android%20%7C%20Linux%20%7C%20Windows%20%7C%20iOS-brightgreen.svg" alt="Platforms">
</p>

---

## 💡 What is Cycles?

Most task managers force a trade-off:
- **Cloud-hosted apps** (Todoist, Vikunja) require accounts, constant internet access, and trusting third-party servers with your personal data.
- **Local-first apps** (Super Productivity) store data on-device, but syncing requires manual cloud accounts (Dropbox, WebDAV) and fails when devices are offline or not on the same Wi-Fi network.

**Cycles bridges this gap.** It is a true local-first task app that synchronizes directly between nearby devices using **Bluetooth Low Energy (BLE)**:
- **Zero Shared Infrastructure**: Sync while camping, on a plane, or during internet outages.
- **No Accounts or Telemetry**: No emails, passwords, or tracking.
- **Conflict-Free Replicated Data**: Concurrent offline edits merge deterministically via **Automerge CRDTs**.

---

## ✨ Features

- **📶 Proximity Peer-to-Peer Sync**: Automatic BLE discovery, deterministic role tie-breaking, and chunked GATT transfer with CRC32 verification.
- **⚡ Single-Store Architecture**: Blends reactive SQLite queries ([Drift](https://drift.simonbinder.eu/)) for sub-millisecond UI rendering with Automerge binary change-tracking for conflict resolution.
- **🔒 Trust On First Use (TOFU)**: Pair devices securely on the fly. View, trust, or revoke peers anytime in the Nearby Devices screen.
- **🎨 Modern Cross-Platform UI**: Built with Flutter for consistent typography, adaptive layouts, and responsive themes across Android, Linux, iOS, and Windows.
- **🦀 High-Performance Rust Core**: Networking, framing, and CRDT math run in compiled native Rust via `flutter_rust_bridge`.

---

## 🏛️ System Architecture

Cycles employs a clean layered architecture connecting the Flutter UI to the native Rust CRDT and BLE engine:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter / Dart UI Layer                     │
│  ┌───────────────────────┐           ┌───────────────────────┐  │
│  │  Reactive Task Views  │           │ Nearby Devices Screen │  │
│  └───────────┬───────────┘           └───────────┬───────────┘  │
│              │ (Streams)                         │ (Scan/Pair)  │
│  ┌───────────▼───────────┐           ┌───────────▼───────────┐  │
│  │   Drift Relational    │◄──────────┤   BleSyncService      │  │
│  │   SQLite Database     │ (SyncDiff)│   (State & Discovery) │  │
│  └───────────────────────┘           └───────────┬───────────┘  │
└──────────────────────────────────────────────────┼──────────────┘
                                                   │ FFI
┌──────────────────────────────────────────────────▼──────────────┐
│                    Rust Core (cycles_core)                      │
│  ┌───────────────────────┐           ┌───────────────────────┐  │
│  │   Automerge Engine    │           │    BLE GATT Engine    │  │
│  │ (crdt.rs / store.rs)  │           │  (Central & Server)   │  │
│  └───────────┬───────────┘           └───────────┬───────────┘  │
│              │                                   │              │
│  ┌───────────▼───────────┐           ┌───────────▼───────────┐  │
│  │ SQLite `sync_changes` │           │   Chunking & CRC32    │  │
│  │  Binary Blob Storage  │           │   Framing Protocol    │  │
│  └───────────────────────┘           └───────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

For complete technical specifications, see [ARCHITECTURE.md](ARCHITECTURE.md) and [docs/SYNC_PROTOCOL.md](docs/SYNC_PROTOCOL.md).

---

## 🚀 Quickstart & Development

### Prerequisites
- **Flutter SDK**: `>= 3.13.2`
- **Rust Toolchain**: Stable (Edition 2024)
- **flutter_rust_bridge_codegen**: `v2.13.0` (`cargo install 'flutter_rust_bridge_codegen@=2.13.0'`)
- **BlueZ Development Headers** (Linux): `sudo apt-get install libdbus-1-dev pkg-config`

### 1. Clone and Install Dependencies
```bash
git clone https://github.com/Zenmisan/Cycle.git
cd Cycle

flutter pub get
```

### 2. Build the Rust Core Library
```bash
cd rust
cargo build --release
cd ..
```

### 3. Run the Application
To run on your desktop (Linux/macOS/Windows):
```bash
flutter run
```

To run on a connected Android device:
```bash
# 1. Cross-compile native Rust libraries for Android
ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/<version> ./scripts/build_android_rust.sh

# 2. Launch Flutter on Android
flutter run -d <device-id>
```

---

## 🧪 Testing

Cycles maintains automated test suites across both Rust and Flutter:

```bash
# Run Rust CRDT, framing, pairing, and tie-breaking tests
cd rust && cargo test && cd ..

# Run Flutter static analysis
flutter analyze

# Run Flutter widget and FFI bridge tests
flutter test
```

---

## 📚 Documentation

- [System Architecture](ARCHITECTURE.md) — Comprehensive guide to the single-store boundary, CRDTs, and subsystem design.
- [Proximity Sync Protocol](docs/SYNC_PROTOCOL.md) — BLE GATT characteristics, binary frame header layout, and sync state machine.
- [Contributing Guide](CONTRIBUTING.md) — Development setup, codegen instructions, and commit standards.
- [Security Policy](SECURITY.md) — Threat model, zero-knowledge privacy guarantees, and vulnerability reporting.

---

## 🗺️ Roadmap & Phases

- [x] **Phase 1: MVP**: Flutter reactive task dashboard + Drift SQLite relational store.
- [x] **Phase 2: FFI Toolchain**: `flutter_rust_bridge` cross-compilation and automated bridge test pipeline.
- [x] **Phase 3: BLE Discovery & Transport**: GATT Central/Server, deterministic tie-breaking, TOFU pairing, and chunked byte pipe with CRC32.
- [x] **Phase 4: CRDT Engine**: Automerge document replication, vector clock exchange, and single-store SQLite integration.
- [ ] **Phase 5: Fast-Path Transports**: Opportunistic local Wi-Fi mDNS + TCP socket upgrades.
- [ ] **Phase 6: Remote Relay Server**: Optional zero-knowledge self-hosted relay for non-proximity sync.
- [ ] **Phase 7: Feature Polish**: Due date reminders, local notifications, recurring rules, and import/export tools.

---

## 📄 License

Cycles is licensed under the [MIT License](LICENSE).

<p align="center">
  <img src="assets/icon/cycle.svg" alt="Cycles Logo" width="128" height="128">
</p>

<h1 align="center">Cycles</h1>

<p align="center">
  <strong>Offline-first, peer-to-peer proximity task sync - no account, no cloud, no server required.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/version-1.0.0-14b8a6.svg" alt="Version 1.0.0">
  <img src="https://img.shields.io/badge/flutter-3.13+-02569B.svg?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/rust-edition%202024-DEA584.svg?logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/go-1.22+-00ADD8.svg?logo=go&logoColor=white" alt="Go">
  <img src="https://img.shields.io/badge/CRDT-Automerge-ff69b4.svg" alt="Automerge CRDT">
  <img src="https://img.shields.io/badge/platforms-Android%20%7C%20Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20iOS-brightgreen.svg" alt="Platforms">
  <img src="https://img.shields.io/badge/tests-passing-brightgreen.svg" alt="Tests">
</p>

---

## What is Cycles?

Most task managers force a compromise:
- **Cloud-hosted apps** (Todoist, Vikunja, TickTick) require central accounts, constant internet access, and surrender your personal data to remote servers.
- **Local-first apps** (Super Productivity, Logseq) store data on-device, but cross-device synchronization requires manual cloud accounts (Dropbox, WebDAV, Google Drive) and fails whenever devices are offline or off-grid.

**Cycles eliminates this compromise.** It is a true local-first task app that synchronizes directly between devices in physical proximity using **Wi-Fi Direct**, **Local LAN mDNS**, and **Bluetooth Low Energy (BLE)**:
- **Zero Shared Infrastructure**: Sync while camping, on a plane, in a subway, or during internet outages.
- **No Accounts or Telemetry**: No emails, passwords, phone numbers, or analytics tracking.
- **Conflict-Free Replicated Data**: Concurrent multi-device edits merge deterministically via **Automerge CRDTs**.

---

## Features

- **4-Tier Transport Hierarchy**:
  1. **Wi-Fi Direct P2P** (~15-50 MB/s direct device-to-device Wi-Fi without routers).
  2. **Local LAN Fast-Path** (~5-20 MB/s mDNS discovery over shared Wi-Fi / Ethernet).
  3. **Proximity BLE GATT** (~50-200 KB/s zero-infrastructure proximity sync with chunked CRC-32 frames).
  4. **Remote Zero-Knowledge Relay** (optional self-hosted Go WebSocket server for out-of-proximity sync).
- **Single-Store Architecture**: Blends reactive SQLite queries ([Drift](https://drift.simonbinder.eu/)) for sub-millisecond UI rendering with Automerge binary change-tracking (`sync_changes`) for mathematical conflict resolution.
- **Full-Featured Task Management**: Markdown notes, project organization, tag filtering, priority tiers (None, Low, Medium, High), and due dates with time picker.
- **Recurring Tasks**: Flexible recurrence rules (Daily, Weekdays, Weekly, Monthly, Yearly) that automatically advance and reschedule the next occurrence when completed.
- **Local Notifications**: Timezone-aware due-date reminders with automated cancellation when tasks complete.
- **Home-Screen Widgets**: Native Material Design 3 widget for Android and WidgetKit extension for iOS (App Group container).
- **One-Click Migration**: Import tasks, projects, notes, and priorities seamlessly from **Vikunja**, **Todoist**, and **Super Productivity**.
- **Trust On First Use (TOFU)**: Pair devices securely on the fly. View, trust, or revoke peers anytime in the Nearby Devices screen.
- **High-Performance Native Core**: Networking, framing, and CRDT math run in compiled native Rust via `flutter_rust_bridge`.

---

## System Architecture

Cycles employs a layered architecture connecting the Flutter UI to the native Rust engine and native OS subsystems:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter / Dart UI Layer                      │
│  ┌───────────────────────┐           ┌───────────────────────┐  │
│  │ Task & Import Screens │           │ Nearby Devices Screen │  │
│  └───────────┬───────────┘           └───────────┬───────────┘  │
│              │ (Streams)                         │              │
│  ┌───────────▼───────────┐           ┌───────────▼───────────┐  │
│  │   Drift Relational    │◄──────────┤   SyncOrchestrator    │  │
│  │   SQLite Database     │ (SyncDiff)│ (WFD, LAN, BLE, Relay)│  │
│  └───────────────────────┘           └───────────┬───────────┘  │
└──────────────────────────────────────────────────┼──────────────┘
                                                   │ FFI
┌──────────────────────────────────────────────────▼──────────────┐
│                    Rust Core (cycles_core)                      │
│  ┌───────────────────────┐           ┌───────────────────────┐  │
│  │   Automerge Engine    │           │ Multi-Tier Transports │  │
│  │ (crdt.rs / store.rs)  │           │(WFD, LAN, BLE, Relay) │  │
│  └───────────┬───────────┘           └───────────┬───────────┘  │
│              │                                   │              │
│  ┌───────────▼───────────┐           ┌───────────▼───────────┐  │
│  │ SQLite `sync_changes` │           │   Chunking & CRC32    │  │
│  │  Binary Blob Storage  │           │   Framing Protocol    │  │
│  └───────────────────────┘           └───────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

For complete technical specifications, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Downloads & Releases

Pre-compiled standalone packages for v1.0.0 are available on the [GitHub Releases](https://github.com/Zenmisan/Cycle/releases) page:

| Platform | Package Format | Binary Name | Notes |
| :--- | :--- | :--- | :--- |
| **Android** | Standalone APK | `cycles-1.0.0-android.apk` | Arm64, Armeabi-v7a, x86_64 native libraries |
| **Linux** | AppImage | `cycles-1.0.0-linux.AppImage` | Universal Linux binary (Ubuntu, Fedora, Arch, Debian) |
| **Linux** | Debian / Ubuntu | `cycles-1.0.0-linux.deb` | Standard dpkg package |
| **Linux** | Red Hat / Fedora | `cycles-1.0.0-linux.rpm` | Standard RPM package |
| **Linux** | Portable Tarball | `cycles-1.0.0-linux.tar.gz` | Portable distribution |
| **Windows** | Setup Installer | `cycles-1.0.0-windows.exe` | InnoSetup executable installer |
| **Windows** | Portable Zip | `cycles-1.0.0-windows-portable.zip` | Standalone portable bundle |
| **macOS** | Apple Disk Image | `cycles-1.0.0-macos.dmg` | Universal DMG (Apple Silicon & Intel) |
| **iOS** | Xcode Project | Source build | Build from source with development provisioning |

### Verifying Release Checksums
Verify package integrity using SHA-256 before installation:
```bash
sha256sum -c SHA256SUMS
```

---

## Quickstart & Development

### Prerequisites
- **Flutter SDK**: `>= 3.13.2`
- **Rust Toolchain**: Stable (Edition 2024)
- **flutter_rust_bridge_codegen**: `v2.13.0` (`cargo install 'flutter_rust_bridge_codegen@=2.13.0'`)
- **BlueZ Development Headers** (Linux): `sudo apt-get install libdbus-1-dev pkg-config`
- **Android NDK** (for Android cross-compilation): Recommended NDK `r26`+ and `cargo-ndk`.

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
To run on desktop (Linux/macOS/Windows):
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

## Testing

Cycles maintains exhaustive automated test suites across Rust, Flutter, and the Go relay server:

```bash
# 1. Run Rust CRDT, framing, pairing, LAN, Wi-Fi Direct, and relay client tests (28 passed)
cd rust && cargo test && cd ..

# 2. Run Flutter static analysis (0 issues)
flutter analyze

# 3. Run Flutter unit, widget, Wi-Fi Direct, import, and recurrence tests (23 passed)
flutter test

# 4. Run Go relay server unit & integration tests (7 passed)
cd relay-server && go test -v ./... && cd ..
```

---

## Documentation Index

- [System Architecture](ARCHITECTURE.md) - Comprehensive guide to the single-store boundary, CRDTs, and subsystem design.
- [Multi-Tier Transports](docs/TRANSPORTS.md) - Detailed guide to the Wi-Fi Direct, Local LAN, BLE GATT, and Relay hierarchy.
- [Single-Store CRDT Storage](docs/CRDT_STORAGE.md) - Automerge schema, SQLite `sync_changes` persistence, and vector clock exchange.
- [Proximity Sync Protocol](docs/SYNC_PROTOCOL.md) - BLE GATT characteristics, 10-byte binary frame header layout, and state machine.
- [Platform Setup Guide](docs/PLATFORM_GUIDE.md) - Linux, Android NDK cross-compilation, macOS dylib, iOS Swift GATT bridge, and Windows build instructions.
- [Data Import & Migration](docs/IMPORT_MIGRATION.md) - Step-by-step guides for importing from Vikunja, Todoist, and Super Productivity.
- [Relay Server Deployment](docs/RELAY_DEPLOYMENT.md) - Production deployment instructions for the self-hosted Go relay server with Docker and TLS.
- [Contributing Guide](CONTRIBUTING.md) - Development setup, codegen instructions, and commit standards.
- [Security Policy](SECURITY.md) - Threat model, zero-knowledge privacy guarantees, and vulnerability reporting.

---

## Roadmap

Upcoming features and improvements planned for future releases:

- [ ] **End-to-End Encrypted Relay Vaults**: Zero-knowledge payload encryption for untrusted public relay nodes.
- [ ] **Collaborative Spaces**: Granular project-level access controls and team workspaces over peer-to-peer meshes.
- [ ] **QR-Code Discovery**: Immediate optical peer discovery and key exchange for quick pairing.
- [ ] **Background Mesh Sync**: Autonomous background sync daemon for desktop workstations and headless servers.

---

## Craftsmanship

Cycles is an open-source project architected and built with craftsmanship by **[Zenmi](https://github.com/Zenmisan)**.

---

## License

Cycles is open-source software licensed under the [MIT License](LICENSE).

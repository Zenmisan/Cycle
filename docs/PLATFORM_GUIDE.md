# Cycles: Cross-Platform Setup & Build Guide

Cycles targets **Android**, **Linux**, **iOS**, and **Windows**. This document details the platform-specific dependencies, native bridges, build pipelines, and permission requirements for each operating system.

---

## 1. Supported Platforms Matrix

| Platform | Primary Transport | Background Sync | Home Screen Widget | Native Bridge Language | Supported Host OS |
|---|---|---|---|---|---|
| **Linux** | BLE (`bluer` / BlueZ) + LAN | Systemd / Desktop daemon | N/A (Desktop) | Rust (`bluer`, D-Bus) | Linux |
| **Android** | Wi-Fi Direct + BLE + LAN | Android Foreground / WorkManager | AppWidgetProvider (XML + Kotlin) | Kotlin (`cycles/ble_permissions`, `cycles/wifi_direct`, `cycles/widget`) | Linux, macOS, Windows |
| **macOS** | BLE (`CoreBluetooth`) + LAN | macOS LaunchAgent / Menu bar | N/A (Desktop) | Swift (`CoreBluetooth`) / native dylib | macOS (Local or GitHub Actions) |
| **iOS** | BLE (Central & Peripheral) + LAN | Background Modes (`bluetooth-central`, `bluetooth-peripheral`) | WidgetKit (SwiftUI) | Swift (`CyclesBlePeripheralPlugin`, `CyclesWidgetPlugin`) | macOS |
| **Windows** | LAN + Wi-Fi Direct + BLE | Windows Background Task | N/A (Desktop) | C++/WinRT | Windows |

---

## 2. Linux Setup & Build

### 2.1. Prerequisites
- **Flutter SDK**: `>= 3.13.2`
- **Rust Toolchain**: Stable (Edition 2024)
- **BlueZ D-Bus Development Headers**:
  ```bash
  sudo apt-get install -y libdbus-1-dev pkg-config libclang-dev
  ```

### 2.2. Build & Run
```bash
# Build Rust crate
cd rust && cargo build --release && cd ..

# Run Flutter desktop app
flutter run -d linux
```

### 2.3. BLE Notes
On Linux, Cycles communicates directly with the BlueZ daemon via the `bluer` crate. Ensure your user belongs to the `bluetooth` group and the Bluetooth service is active:
```bash
sudo systemctl status bluetooth
```

---

## 3. Android Setup & Build

### 3.1. Prerequisites
- **Android SDK & NDK**: Installed via Android Studio or command-line tools. Recommended NDK: `r26` or newer.
- **`cargo-ndk`**:
  ```bash
  cargo install cargo-ndk
  ```
- **Rust Android Targets**:
  ```bash
  rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
  ```

### 3.2. Compiling Rust Native Libraries (`libcycles_core.so`)
Cycles includes an automated cross-compilation script:
```bash
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/<version>
./scripts/build_android_rust.sh
```
This builds and places optimized `.so` binaries into:
- `android/app/src/main/jniLibs/arm64-v8a/`
- `android/app/src/main/jniLibs/armeabi-v7a/`
- `android/app/src/main/jniLibs/x86_64/`

### 3.3. Android BLE Permissions (Android 12+)
Starting in Android 12 (API 31), Bluetooth permissions were separated from Location:
- `android.permission.BLUETOOTH_SCAN` (`usesPermissionFlags="neverForLocation"`)
- `android.permission.BLUETOOTH_CONNECT`
- `android.permission.BLUETOOTH_ADVERTISE`
- `android.permission.POST_NOTIFICATIONS` (Android 13+ / API 33)

Cycles implements a dedicated native permission plugin:
[`android/app/src/main/kotlin/com/example/cycles/BlePermissionsPlugin.kt`](file:///home/zenmi/Projects/Cycle/android/app/src/main/kotlin/com/example/cycles/BlePermissionsPlugin.kt). The Flutter app prompts the user transparently when toggling BLE advertising or initiating nearby scans.

### 3.4. Android Home Screen Widget
- **Provider**: [`CycleAppWidgetProvider.kt`](file:///home/zenmi/Projects/Cycle/android/app/src/main/kotlin/com/example/cycles/CycleAppWidgetProvider.kt)
- **Data Plugin**: [`WidgetDataPlugin.kt`](file:///home/zenmi/Projects/Cycle/android/app/src/main/kotlin/com/example/cycles/WidgetDataPlugin.kt) (`cycles/widget` channel)
- **Storage**: JSON payload stored in Android `SharedPreferences` (`CyclesWidgetPrefs`)
- **Auto-Sync**: Whenever tasks mutate in Drift, [`WidgetSyncService`](file:///home/zenmi/Projects/Cycle/lib/services/widget_sync_service.dart) serializes the top pending tasks and updates `AppWidgetManager`.

---

## 4. macOS Setup & Build

*Note: Building native macOS applications requires a Mac with Xcode, or running via the automated GitHub Actions CI workflow.*

### 4.1. Prerequisites & Compilation
- **Xcode & Command Line Tools**
- **Rust Toolchain**: `aarch64-apple-darwin` and `x86_64-apple-darwin`
- **Native dylib compilation**:
  ```bash
  ./scripts/build_macos_rust.sh
  ```
  This creates a universal fat binary `libcycles_core.dylib` combining both Apple Silicon and Intel architectures.

### 4.2. Local Build
```bash
flutter build macos --release
```

### 4.3. Cloud Build via GitHub Actions
For contributors on Linux or Windows who do not have a physical Mac, Cycles includes a complete automated macOS release build job in [`.github/workflows/ci.yml`](file:///home/zenmi/Projects/Cycle/.github/workflows/ci.yml) running on `macos-latest`. Every push or release creates and uploads a zipped `Cycles-macOS.zip` bundle.

---

## 5. iOS Setup & Build

*Note: Building and signing iOS binaries requires a macOS host with Xcode installed.*

### 5.1. Swift BLE GATT Server Bridge
iOS apps acting as BLE Peripherals require `CBPeripheralManager`. Cycles provides a custom Swift plugin:
[`ios/Runner/CyclesBlePeripheralPlugin.swift`](file:///home/zenmi/Projects/Cycle/ios/Runner/CyclesBlePeripheralPlugin.swift)
- Channel: `cycles/ble_peripheral`
- Advertises `0xFD01` service UUID with local name `Cycles-<short_id>`.
- Publishes Characteristic `0xFD02` (`.writeWithoutResponse`, `.read`, `.notify`).

### 5.2. iOS WidgetKit Integration
- **Target**: `CyclesWidget` ([`ios/CyclesWidget/CyclesWidget.swift`](file:///home/zenmi/Projects/Cycle/ios/CyclesWidget/CyclesWidget.swift))
- **Container**: App Group `group.com.example.cycles` shared between Flutter Runner and Widget Extension via `UserDefaults(suiteName:)`.
- **Reload Trigger**: [`CyclesWidgetPlugin.swift`](file:///home/zenmi/Projects/Cycle/ios/Runner/CyclesWidgetPlugin.swift) invokes `WidgetCenter.shared.reloadAllTimelines()`.

### 5.3. Sideloading the Pre-Built iOS IPA (.ipa)
For users who want to run Cycles on iOS using the pre-compiled unsigned binary, an `.ipa` package is provided for sideloading via AltStore, Sideloadly, or TrollStore.
Refer to the complete instructions, security advisories, and installation walkthrough in the [iOS Sideloading & Installation Guide](IOS_INSTALL.md) (or online at `/docs/ios-install`).

---

## 6. Windows Setup & Build

*Note: Building native Windows applications requires Windows 10/11 with Visual Studio C++ Build Tools.*

### 5.1. Wi-Fi Direct on Windows
Windows handles Wi-Fi Direct through the WinRT `Windows.Devices.WiFiDirect` APIs. See detailed findings in [`.agents/tracks/wifi_direct_20260919/findings.md`](file:///home/zenmi/Projects/Cycle/.agents/tracks/wifi_direct_20260919/findings.md).

### 5.2. BLE on Windows
BLE GATT Client and Server roles on Windows are implemented via `Windows.Devices.Bluetooth.GenericAttributeProfile`.

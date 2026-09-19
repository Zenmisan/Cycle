# Cycles — Cross-Platform Setup & Build Guide

Cycles targets **Android**, **Linux**, **iOS**, and **Windows**. This document details the platform-specific dependencies, native bridges, build pipelines, and permission requirements for each operating system.

---

## 1. Supported Platforms Matrix

| Platform | Primary Transport | Background Sync | Home Screen Widget | Native Bridge Language | Supported Host OS |
|---|---|---|---|---|---|
| **Linux** | BLE (`bluer` / BlueZ) + LAN | Systemd / Desktop daemon | N/A (Desktop) | Rust (`bluer`, D-Bus) | Linux |
| **Android** | Wi-Fi Direct + BLE + LAN | Android Foreground / WorkManager | AppWidgetProvider (XML + Kotlin) | Kotlin (`cycles/ble_permissions`, `cycles/wifi_direct`, `cycles/widget`) | Linux, macOS, Windows |
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

## 4. iOS Setup & Build

*Note: Building and signing iOS binaries requires a macOS host with Xcode installed.*

### 4.1. Swift BLE GATT Server Bridge
iOS apps acting as BLE Peripherals require `CBPeripheralManager`. Cycles provides a custom Swift plugin:
[`ios/Runner/CyclesBlePeripheralPlugin.swift`](file:///home/zenmi/Projects/Cycle/ios/Runner/CyclesBlePeripheralPlugin.swift)
- Channel: `cycles/ble_peripheral`
- Advertises `0xFD01` service UUID with local name `Cycles-<short_id>`.
- Publishes Characteristic `0xFD02` (`.writeWithoutResponse`, `.read`, `.notify`).

### 4.2. iOS WidgetKit Integration
- **Target**: `CyclesWidget` ([`ios/CyclesWidget/CyclesWidget.swift`](file:///home/zenmi/Projects/Cycle/ios/CyclesWidget/CyclesWidget.swift))
- **Container**: App Group `group.com.example.cycles` shared between Flutter Runner and Widget Extension via `UserDefaults(suiteName:)`.
- **Reload Trigger**: [`CyclesWidgetPlugin.swift`](file:///home/zenmi/Projects/Cycle/ios/Runner/CyclesWidgetPlugin.swift) invokes `WidgetCenter.shared.reloadAllTimelines()`.

---

## 5. Windows Setup & Build

*Note: Building native Windows applications requires Windows 10/11 with Visual Studio C++ Build Tools.*

### 5.1. Wi-Fi Direct on Windows
Windows handles Wi-Fi Direct through the WinRT `Windows.Devices.WiFiDirect` APIs. See detailed findings in [`.agents/tracks/wifi_direct_20260919/findings.md`](file:///home/zenmi/Projects/Cycle/.agents/tracks/wifi_direct_20260919/findings.md).

### 5.2. BLE on Windows
BLE GATT Client and Server roles on Windows are implemented via `Windows.Devices.Bluetooth.GenericAttributeProfile`.

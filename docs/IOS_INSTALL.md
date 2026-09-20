# Sideloading and Installing Cycles on iOS (.ipa)

This guide covers how to download, verify, and sideload the unsigned iOS application package (`.ipa`) for Cycles onto your iPhone or iPad.

---

## 1. Official Package & Verification

Cycles provides a standalone, unsigned `.ipa` build for users who want to run Cycles on iOS prior to or alongside the official Apple App Store release.

| Property | Value |
|---|---|
| **File Name** | `cycles-1.0.0-ios-unsigned.ipa` |
| **Direct Download** | [Download .ipa](https://coqcmyd9hbvvcznj.public.blob.vercel-storage.com/cycles-1.0.0-ios-unsigned.ipa) |
| **Package Type** | Unsigned iOS Application Archive |
| **Target iOS** | iOS 16.0 or newer (iPhone and iPad) |
| **SHA-256 Checksum** | `5672346179770ae6f2a063bcb22536b36af985778140da484da5ba6a95ed237e` |

### Verifying the Package Integrity

Before installing any sideloaded file, verify its SHA-256 checksum to ensure the package has not been tampered with or corrupted during transit.

**macOS or Linux terminal:**
```bash
shasum -a 256 cycles-1.0.0-ios-unsigned.ipa
```

**Windows PowerShell:**
```powershell
Get-FileHash cycles-1.0.0-ios-unsigned.ipa -Algorithm SHA256
```

Confirm that the calculated hash matches `5672346179770ae6f2a063bcb22536b36af985778140da484da5ba6a95ed237e` exactly.

---

## 2. Security Advisory & Liability Disclaimer

### The Risks of Installing Random Unsigned IPA Files

On iOS, official applications distributed through the App Store undergo automated screening, static code analysis, and manual review by Apple to verify that they comply with sandboxing rules and do not contain known malware.

An **unsigned IPA** has bypassed this process. Sideloading arbitrary, unknown IPA files downloaded from unverified websites carries severe security hazards:

- **Malicious Modifications**: Third-party sites frequently bundle trojans, credential sniffers, keyloggers, or hidden background cryptominers into modified IPAs.
- **Excessive Privileges**: Sideloaded apps can prompt for permissions (Camera, Microphone, Photo Library, Local Network, Bluetooth) that can be abused to extract personal information.
- **Phishing and Fake Interfaces**: Malicious clones can imitate system dialogs or web logins to capture your credentials.
- **Provisioning Risks**: Entering your primary Apple ID credentials into third-party, closed-source signing utilities poses credential interception risks if the tool is untrustworthy.

### Cycles Trust Architecture

Cycles is built on transparent, auditable principles:
- **100% Open Source**: All source code (Flutter UI, Rust CRDT engine, Swift bridges, and build scripts) is publicly viewable at [github.com/Zenmisan/Cycle](https://github.com/Zenmisan/Cycle).
- **Local-First & Offline**: Cycles contains zero telemetry, zero analytics, zero external API dependencies, and no remote server connections. Tasks remain strictly on your local device storage.
- **Reproducible**: You can inspect every line of the codebase or compile the `.ipa` directly from source using Xcode on a macOS host.

### Disclaimer of Liability

Please read this disclaimer carefully before proceeding:

> Sideloading software onto an iOS device is performed entirely at your own discretion and risk. While Cycles is open-source and non-malicious, the author (Zenmi) and all project contributors accept no responsibility or liability for any damages, device instability, operating system boot loops, data loss, profile revocations, Apple ID security flags, or any other issues that may occur through the installation, sideloading, or use of this unsigned IPA, or through the use of third-party sideloading tools. You are solely responsible for backing up your device and verifying all software packages before installation.

---

## 3. Installation Methods & Mediums

Because iOS requires all executables to be cryptographically signed before running, an unsigned `.ipa` must be resigned with your own Apple ID certificate (free or paid) or installed through a kernel-level certificate bypass (such as TrollStore).

Choose one of the methods below based on your operating system and iOS version.

---

### Method A: AltStore / AltServer (macOS & Windows)

AltStore is the most widely used and reliable sideloading tool for standard iOS devices. It uses your personal Apple ID to generate a 7-day developer certificate and refreshes apps automatically over local Wi-Fi.

#### Requirements
- A Mac running macOS 10.14.4+ or a PC running Windows 10/11 (with iTunes and iCloud installed directly from Apple, not the Microsoft Store).
- An Apple ID (a secondary/burner Apple ID is supported if preferred).
- USB cable for initial setup.

#### Steps
1. Download and install **AltServer** on your computer from [altstore.io](https://altstore.io).
2. Connect your iPhone or iPad to your computer via USB and tap **Trust This Computer** on your device.
3. On Windows: Open AltServer from the system tray, click **Install AltStore**, and select your connected device.
   On macOS: Click the AltServer menu bar icon, click **Install Mail Plug-in** (if prompted), enable it in Mail Preferences, and select **Install AltStore → [Your Device]**.
4. Enter your Apple ID and password when prompted. AltServer will sign and install the AltStore app onto your device.
5. On your iPhone, open **Settings → General → VPN & Device Management**. Find your Apple ID under "Developer App" and tap **Trust**.
6. On iOS 16 or newer: Open **Settings → Privacy & Security → Developer Mode**. Turn it **On** and reboot your device when prompted.
7. Download `cycles-1.0.0-ios-unsigned.ipa` using Safari on your iPhone, or transfer it to your device via AirDrop.
8. Open the **AltStore** app on your iPhone, navigate to the **My Apps** tab, tap the **+** icon in the top corner, and select the downloaded Cycles IPA.
9. AltStore will sign and install Cycles. Once finished, Cycles will appear on your Home Screen.

*Note on Free Apple IDs: Apps signed with a free Apple ID expire after 7 days. As long as your phone and computer are on the same Wi-Fi network and AltServer is running, AltStore will refresh Cycles automatically in the background.*

---

### Method B: Sideloadly (macOS & Windows)

Sideloadly is a fast desktop tool that resigns and installs IPAs directly over USB or Wi-Fi without needing a mobile companion app.

#### Requirements
- Computer running Windows or macOS.
- USB cable.
- Free Apple ID.

#### Steps
1. Download and install **Sideloadly** from [sideloadly.io](https://sideloadly.io).
2. Connect your iOS device to your computer.
3. Download `cycles-1.0.0-ios-unsigned.ipa` onto your computer.
4. Drag and drop the `.ipa` file into the Sideloadly window.
5. Enter your Apple ID email in the **Apple ID** field.
6. Click **Start**. Sideloadly will request your password (or app-specific password if 2FA is active), sign the binary, and push it to your device.
7. On your iPhone:
   - Go to **Settings → General → VPN & Device Management** and trust your developer profile.
   - If on iOS 16+, verify **Developer Mode** is turned on in **Settings → Privacy & Security**.
8. Launch Cycles from your Home Screen.

---

### Method C: TrollStore (iOS 14.0 - 15.4.1 & Selected Versions up to 17.0)

If your device runs an iOS version vulnerable to the CoreTrust bug, TrollStore allows permanent app installation without 7-day certificate expiration, without App ID limits, and without requiring a computer.

#### Steps
1. Ensure TrollStore is properly installed and configured on your compatible device (refer to the official TrollStore GitHub repository for setup instructions).
2. Download `cycles-1.0.0-ios-unsigned.ipa` directly in Safari on your iPhone.
3. In Safari's download manager, tap the downloaded file, tap the **Share** button, and choose **TrollStore**.
4. TrollStore will install Cycles with root-level binary entitlements.
5. Cycles will be available permanently without revokes or re-signing requirements.

---

### Method D: Xcode & Self-Compilation (macOS Developers)

If you have a Mac with Xcode and prefer to build from source code directly:

1. Clone the repository:
   ```bash
   git clone https://github.com/Zenmisan/Cycle.git
   cd Cycle
   ```
2. Fetch dependencies and compile the Rust native core:
   ```bash
   flutter pub get
   ./scripts/build_macos_rust.sh
   ```
3. Open the iOS workspace:
   ```bash
   open ios/Runner.xcworkspace
   ```
4. In Xcode, select the **Runner** project in the navigator, go to **Signing & Capabilities**, select your **Personal Team**, and choose a unique Bundle Identifier.
5. Connect your iPhone, select it as the build destination, and click **Run** (`Cmd + R`).

---

## 4. Post-Installation Device Permissions

When you launch Cycles for the first time on iOS, the system will ask for specific permissions. These are required for Cycles to operate its off-grid synchronization:

1. **Bluetooth (`NSBluetoothAlwaysUsageDescription`)**:
   - Required for local peer discovery and proximity synchronization over BLE GATT. Cycles uses Bluetooth solely to broadcast and receive task changes between nearby devices.
2. **Local Network (`NSLocalNetworkUsageDescription`)**:
   - Required for mDNS LAN discovery. This allows Cycles to find other instances on your home or office Wi-Fi network for high-speed synchronization without routing traffic through the internet.
3. **Notifications**:
   - Optional. Used to alert you when background sync completes or when scheduled task reminders trigger.

---

## 5. Frequently Asked Questions

### Why does the app stop opening after 7 days?
If you installed via a free Apple ID on AltStore or Sideloadly, Apple limits free developer provisioning profiles to 7 days. You must refresh the certificate before it expires:
- In AltStore: Keep AltServer running on your PC/Mac while on the same Wi-Fi network, or tap "Refresh All" in the AltStore app.
- In Sideloadly: Re-connect your device and click Start to re-sign.
- Users with a paid Apple Developer Account ($99/year) receive 365-day provisioning certificates.

### Does sideloading void my Apple warranty or jailbreak my phone?
No. Sideloading using AltStore or Sideloadly uses official Apple developer signing APIs. It does not modify system files, does not bypass kernel security, and does not void your hardware warranty.

### When will Cycles be available on the official App Store?
Cycles is currently in preparation for official Apple App Store review. Once approved, you will be able to install and receive automatic updates directly through the App Store without needing to sideload or re-sign certificates.

# Security Policy

## Security & Privacy Philosophy

**Cycles** is designed from the ground up as a **local-first, zero-infrastructure, privacy-preserving application**:
- **No Central Server**: Tasks, notes, and metadata are stored entirely on your local device.
- **No Accounts or Telemetry**: No user accounts, passwords, email addresses, or cloud analytics exist in Cycles.
- **Peer-to-Peer Proximity**: Direct device-to-device communication occurs strictly over local Bluetooth Low Energy (BLE) or local subnet Wi-Fi.

---

## Threat Model & Guarantees

### 1. Bluetooth Low Energy (BLE) Privacy
- **Presence Advertising**: Device presence broadcasting is opt-in and toggleable directly in the UI. When disabled, the device stops advertising its GATT service and remains silent to nearby scanners.
- **Device Identifiers**: Devices advertise a truncated pseudo-random identifier (`Cycles-<short_id>`) rather than revealing persistent personal or hardware identifiers over the air.

### 2. Trust On First Use (TOFU)
- Inbound sync handshakes register remote devices using a **Trust On First Use (TOFU)** model.
- Users can view, trust, or untrust any discovered peer via the Nearby Devices interface.
- Sync exchanges require explicit peer trust; untrusted peers are ignored.

### 3. Data Integrity & Framing
- Every chunked frame transferred over the BLE transport is protected by a 32-bit CRC (`crc32fast`).
- Corrupted frames, truncation, or payload tamper attempts are dropped immediately before reaching the Automerge CRDT parser.

---

## Reporting a Vulnerability

If you discover a security vulnerability or privacy flaw within Cycles:

1. **Do not disclose publicly**: Please do not open public GitHub issues for sensitive security vulnerabilities.
2. **Email the Maintainer**: Send a report detailing the issue and reproduction steps to `zenmisan@gmail.com`.
3. **Response Timeline**: You will receive an acknowledgment within 48 hours, followed by a status update and remediation plan.
4. **Advisory & Credit**: Once a patch is released, credit will be given in the release notes (unless you request anonymity).

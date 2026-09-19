//! Wi-Fi Direct transport for high-speed point-to-point data synchronization
//! between Android and Windows devices.
//!
//! Once an OS-level P2P group is formed (via Android WifiP2pManager or
//! Windows WinRT WiFiDirect), this transport connects over the point-to-point
//! IP socket and reuses the shared frame protocol (`ble::framing`) and
//! tie-breaking rules (`ble::tie_break`).

pub mod transport;

pub use transport::{sync_round_wifi_direct, CYCLES_WIFI_DIRECT_PORT};

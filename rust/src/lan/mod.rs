//! LAN fast-path: mDNS discovery + TCP transport, used opportunistically
//! when a paired peer happens to share a network with this device. BLE
//! (`crate::ble`) remains the universal fallback that always works — this
//! module exists purely for speed when the opportunity is there.

pub mod discovery;
pub mod transport;

pub use discovery::{browse_once, advertise, LanPeer, CYCLES_LAN_SERVICE_TYPE};
pub use transport::sync_round;

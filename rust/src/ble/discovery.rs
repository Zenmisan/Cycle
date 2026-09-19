//! BLE discovery and advertising logic for Cycles peer detection.

use uuid::Uuid;

/// Cycles primary service UUID: `6379636c-6573-7379-6e63-000000000001` (ASCII "cyclessync-0001")
pub const CYCLES_SERVICE_UUID: Uuid = Uuid::from_u128(0x6379636c_6573_7379_6e63_000000000001);

/// Cycles sync characteristic UUID (read, write, notify): `6379636c-6573-7379-6e63-000000000002`
pub const CYCLES_CHAR_SYNC_UUID: Uuid = Uuid::from_u128(0x6379636c_6573_7379_6e63_000000000002);

pub const ADVERTISEMENT_PREFIX: &str = "Cycles-";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoveredPeer {
    pub device_id: String,
    pub display_name: String,
    pub address: String,
    pub rssi: Option<i16>,
}

impl DiscoveredPeer {
    /// Formats the advertisement name for a device ID.
    pub fn make_local_name(device_id: &str) -> String {
        let short_id = if device_id.len() > 8 {
            &device_id[..8]
        } else {
            device_id
        };
        format!("{ADVERTISEMENT_PREFIX}{short_id}")
    }

    /// Attempts to extract the short device ID from an advertised name.
    pub fn parse_device_id_from_name(name: &str) -> Option<String> {
        if let Some(stripped) = name.strip_prefix(ADVERTISEMENT_PREFIX) {
            if !stripped.is_empty() {
                return Some(stripped.to_string());
            }
        }
        None
    }
}

#[cfg(target_os = "linux")]
pub mod linux {
    use super::*;
    use bluer::{
        adv::{Advertisement, AdvertisementHandle},
        Session,
    };
    use std::collections::BTreeSet;

    /// Publishes a BLE advertisement for this device on the default Linux adapter.
    pub async fn advertise_cycles_presence(
        device_id: &str,
    ) -> Result<AdvertisementHandle, Box<dyn std::error::Error + Send + Sync>> {
        let session = Session::new().await?;
        let adapter = session.default_adapter().await?;
        adapter.set_powered(true).await?;

        let local_name = DiscoveredPeer::make_local_name(device_id);
        let adv = Advertisement {
            service_uuids: BTreeSet::from([CYCLES_SERVICE_UUID]),
            discoverable: Some(true),
            local_name: Some(local_name),
            ..Default::default()
        };

        let handle = adapter.advertise(adv).await?;
        Ok(handle)
    }

    /// Discovers nearby Cycles peers on the default Linux adapter.
    pub async fn scan_for_cycles_peers(
    ) -> Result<Vec<DiscoveredPeer>, Box<dyn std::error::Error + Send + Sync>> {
        let session = Session::new().await?;
        let adapter = session.default_adapter().await?;
        adapter.set_powered(true).await?;

        let device_addresses = adapter.device_addresses().await?;
        let mut peers = Vec::new();

        for addr in device_addresses {
            if let Ok(dev) = adapter.device(addr) {
                if let Ok(Some(name)) = dev.name().await {
                    if let Some(short_id) = DiscoveredPeer::parse_device_id_from_name(&name) {
                        let rssi = dev.rssi().await.ok().flatten();
                        peers.push(DiscoveredPeer {
                            device_id: short_id,
                            display_name: name,
                            address: addr.to_string(),
                            rssi,
                        });
                    }
                }
            }
        }

        Ok(peers)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_name_formatting_and_parsing() {
        let device_id = "a1b2c3d4e5f67890";
        let adv_name = DiscoveredPeer::make_local_name(device_id);
        assert_eq!(adv_name, "Cycles-a1b2c3d4");

        let extracted = DiscoveredPeer::parse_device_id_from_name(&adv_name).unwrap();
        assert_eq!(extracted, "a1b2c3d4");
    }

    #[test]
    fn test_foreign_name_ignored() {
        assert!(DiscoveredPeer::parse_device_id_from_name("RandomSpeaker").is_none());
        assert!(DiscoveredPeer::parse_device_id_from_name("Cycles-").is_none());
    }
}

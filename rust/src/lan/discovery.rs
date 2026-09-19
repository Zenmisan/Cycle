//! mDNS discovery for the LAN fast-path. Mirrors `ble::discovery`'s shape:
//! advertise a `device_id`, browse for peers, extract their `device_id`s.
//! Not required for sync to work (BLE always works) — this only lets a sync
//! round prefer a much faster local socket when one happens to be available.

use mdns_sd::{ResolvedService, ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashMap;
use std::net::IpAddr;
use std::time::Duration;

pub const CYCLES_LAN_SERVICE_TYPE: &str = "_cycles._tcp.local.";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LanPeer {
    pub device_id: String,
    pub addr: IpAddr,
    pub port: u16,
}

/// Advertises this device's presence on the LAN. Returns the daemon (keep it
/// alive for as long as advertising should continue — dropping it stops it)
/// and the registered fullname.
pub fn advertise(device_id: &str, port: u16) -> Result<(ServiceDaemon, String), String> {
    let daemon = ServiceDaemon::new().map_err(|e| e.to_string())?;
    let host_name = format!("{device_id}.local.");
    let mut properties = HashMap::new();
    properties.insert("device_id".to_string(), device_id.to_string());

    let service = ServiceInfo::new(
        CYCLES_LAN_SERVICE_TYPE,
        device_id,
        &host_name,
        "",
        port,
        properties,
    )
    .map_err(|e| e.to_string())?
    .enable_addr_auto();

    let fullname = service.get_fullname().to_string();
    daemon.register(service).map_err(|e| e.to_string())?;
    Ok((daemon, fullname))
}

/// Browses for `_cycles._tcp.local.` peers for up to `timeout`, returning
/// whatever peers responded (their own `device_id` extracted from the TXT
/// record, not the mDNS instance name — the two happen to match here, but
/// callers should trust the TXT record as the source of truth).
pub fn browse_once(timeout: Duration) -> Result<Vec<LanPeer>, String> {
    let daemon = ServiceDaemon::new().map_err(|e| e.to_string())?;
    let receiver = daemon
        .browse(CYCLES_LAN_SERVICE_TYPE)
        .map_err(|e| e.to_string())?;

    let mut peers = Vec::new();
    let deadline = std::time::Instant::now() + timeout;

    while std::time::Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(std::time::Instant::now());
        match receiver.recv_timeout(remaining) {
            Ok(ServiceEvent::ServiceResolved(info)) => {
                if let Some(peer) = peer_from_info(&info) {
                    peers.push(peer);
                }
            }
            Ok(_) => continue,
            Err(_) => break,
        }
    }

    let _ = daemon.shutdown();
    Ok(peers)
}

fn peer_from_info(info: &ResolvedService) -> Option<LanPeer> {
    let device_id = info.get_property_val_str("device_id")?.to_string();
    let addr = info.get_addresses().iter().next()?.to_ip_addr();
    Some(LanPeer {
        device_id,
        addr,
        port: info.get_port(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn advertise_and_browse_find_each_other() {
        let (daemon, _fullname) = advertise("test-device-lan", 5588).expect("advertise failed");

        let peers = browse_once(Duration::from_secs(3)).expect("browse failed");
        assert!(
            peers.iter().any(|p| p.device_id == "test-device-lan"),
            "expected to discover our own advertisement, got: {peers:?}"
        );

        let _ = daemon.shutdown();
    }
}

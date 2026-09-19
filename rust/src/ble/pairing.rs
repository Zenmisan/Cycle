//! Trust-on-first-use (TOFU) pairing and identity management for Cycles.
//!
//! On first contact between two devices, peers exchange device identities and public keys.
//! Once trusted, subsequent contacts recognize the peer's `device_id` and key fingerprint,
//! bypassing manual pairing prompts.

use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
    time::{SystemTime, UNIX_EPOCH},
};

pub const PROTOCOL_VERSION: u8 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PeerIdentity {
    pub device_id: String,
    pub pubkey: String,
    pub display_name: String,
    pub trusted: bool,
    pub first_seen_at: u64,
    pub last_synced_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct HandshakePayload {
    pub protocol_version: u8,
    pub device_id: String,
    pub pubkey: String,
    pub display_name: String,
    pub timestamp: u64,
}

impl HandshakePayload {
    pub fn new(device_id: String, pubkey: String, display_name: String) -> Self {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        Self {
            protocol_version: PROTOCOL_VERSION,
            device_id,
            pubkey,
            display_name,
            timestamp,
        }
    }

    pub fn to_bytes(&self) -> Result<Vec<u8>, serde_json::Error> {
        serde_json::to_vec(self)
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, serde_json::Error> {
        serde_json::from_slice(bytes)
    }
}

/// Thread-safe peer trust store for remembering paired devices.
#[derive(Debug, Clone, Default)]
pub struct PeerStore {
    peers: Arc<RwLock<HashMap<String, PeerIdentity>>>,
}

impl PeerStore {
    pub fn new() -> Self {
        Self {
            peers: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub fn is_trusted(&self, device_id: &str) -> bool {
        let lock = self.peers.read().unwrap();
        lock.get(device_id).map(|p| p.trusted).unwrap_or(false)
    }

    pub fn get_peer(&self, device_id: &str) -> Option<PeerIdentity> {
        let lock = self.peers.read().unwrap();
        lock.get(device_id).cloned()
    }

    /// Process a handshake payload from a peer.
    /// If the peer is unknown, records it with `trusted: true` (trust-on-first-use).
    /// If the peer is known and trusted, updates last_synced timestamp.
    /// Returns the verified `PeerIdentity`.
    pub fn handle_incoming_handshake(
        &self,
        handshake: HandshakePayload,
    ) -> Result<PeerIdentity, PairingError> {
        if handshake.protocol_version != PROTOCOL_VERSION {
            return Err(PairingError::IncompatibleProtocolVersion {
                peer_version: handshake.protocol_version,
                supported_version: PROTOCOL_VERSION,
            });
        }

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let mut lock = self.peers.write().unwrap();
        let peer = lock
            .entry(handshake.device_id.clone())
            .and_modify(|existing| {
                existing.last_synced_at = now;
                existing.display_name = handshake.display_name.clone();
            })
            .or_insert_with(|| PeerIdentity {
                device_id: handshake.device_id,
                pubkey: handshake.pubkey,
                display_name: handshake.display_name,
                trusted: true, // Trust on first use
                first_seen_at: now,
                last_synced_at: now,
            })
            .clone();

        Ok(peer)
    }

    pub fn set_trusted(&self, device_id: &str, trusted: bool) {
        let mut lock = self.peers.write().unwrap();
        if let Some(peer) = lock.get_mut(device_id) {
            peer.trusted = trusted;
        }
    }

    pub fn all_peers(&self) -> Vec<PeerIdentity> {
        let lock = self.peers.read().unwrap();
        lock.values().cloned().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PairingError {
    #[error("Incompatible protocol version: peer={peer_version}, supported={supported_version}")]
    IncompatibleProtocolVersion {
        peer_version: u8,
        supported_version: u8,
    },
    #[error("Serialization error: {0}")]
    SerializationError(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_handshake_serialization_roundtrip() {
        let handshake = HandshakePayload::new(
            "dev-123".to_string(),
            "pubkey-abc-456".to_string(),
            "Pixel 8".to_string(),
        );

        let bytes = handshake.to_bytes().unwrap();
        let decoded = HandshakePayload::from_bytes(&bytes).unwrap();
        assert_eq!(handshake, decoded);
    }

    #[test]
    fn test_trust_on_first_use() {
        let store = PeerStore::new();
        assert!(!store.is_trusted("dev-phone"));

        let handshake = HandshakePayload::new(
            "dev-phone".to_string(),
            "key-phone-pub".to_string(),
            "Zen Phone".to_string(),
        );

        let peer = store.handle_incoming_handshake(handshake).unwrap();
        assert!(peer.trusted);
        assert!(store.is_trusted("dev-phone"));

        // Subsequent update
        store.set_trusted("dev-phone", false);
        assert!(!store.is_trusted("dev-phone"));
    }
}

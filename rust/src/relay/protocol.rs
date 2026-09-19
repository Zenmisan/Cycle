//! Wire protocol for the relay server (`relay_server_20260919`, standalone
//! Go service). JSON over a WebSocket text frame — simple, human-readable,
//! easy for a Go server to parse without any Automerge/CRDT knowledge. The
//! server only ever reads `to`/`from`, never `payload`'s contents.

use serde::{Deserialize, Serialize};

/// Sent once, immediately after connecting, to identify this client.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    Connect {
        device_id: String,
        token: String,
    },
    Data {
        to: String,
        #[serde(with = "base64_bytes")]
        payload: Vec<u8>,
    },
}

/// Received from the server: either a routed message from a peer, or an
/// error (e.g. peer not connected, bad auth).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage {
    Data {
        from: String,
        #[serde(with = "base64_bytes")]
        payload: Vec<u8>,
    },
    Error {
        message: String,
    },
}

mod base64_bytes {
    use base64::Engine;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(bytes: &[u8], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&base64::engine::general_purpose::STANDARD.encode(bytes))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = String::deserialize(d)?;
        base64::engine::general_purpose::STANDARD
            .decode(&s)
            .map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connect_message_round_trips_through_json() {
        let msg = ClientMessage::Connect {
            device_id: "device-a".to_string(),
            token: "secret".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let parsed: ClientMessage = serde_json::from_str(&json).unwrap();
        matches!(parsed, ClientMessage::Connect { .. });
    }

    #[test]
    fn data_message_payload_round_trips_as_base64() {
        let payload = vec![0u8, 1, 2, 255, 254, 253];
        let msg = ClientMessage::Data {
            to: "device-b".to_string(),
            payload: payload.clone(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let parsed: ClientMessage = serde_json::from_str(&json).unwrap();
        match parsed {
            ClientMessage::Data { payload: p, to } => {
                assert_eq!(p, payload);
                assert_eq!(to, "device-b");
            }
            _ => panic!("expected Data variant"),
        }
    }

    #[test]
    fn server_data_message_parses() {
        let json = r#"{"type":"data","from":"device-a","payload":"AAEC"}"#;
        let parsed: ServerMessage = serde_json::from_str(json).unwrap();
        match parsed {
            ServerMessage::Data { from, payload } => {
                assert_eq!(from, "device-a");
                assert_eq!(payload, vec![0, 1, 2]);
            }
            _ => panic!("expected Data variant"),
        }
    }
}

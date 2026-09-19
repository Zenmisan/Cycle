//! BLE Central implementation for connecting to peers and transferring chunked frames.

#[cfg(target_os = "linux")]
use super::{
    discovery::{CYCLES_CHAR_SYNC_UUID, CYCLES_SERVICE_UUID},
    framing::{Chunker, Frame, Reassembler},
};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CentralError {
    #[error("Device not found: {0}")]
    DeviceNotFound(String),
    #[error("Failed to connect to device: {0}")]
    ConnectionFailed(String),
    #[error("Required service {0} not found on peripheral")]
    ServiceNotFound(String),
    #[error("Required characteristic {0} not found on peripheral")]
    CharacteristicNotFound(String),
    #[error("GATT write error: {0}")]
    WriteError(String),
    #[error("GATT read error: {0}")]
    ReadError(String),
}

#[cfg(target_os = "linux")]
pub mod linux {
    use super::*;
    use bluer::{Address, Session};

    pub struct CyclesBleClient {
        pub peer_address: Address,
    }

    impl CyclesBleClient {
        pub fn new(peer_address: Address) -> Self {
            Self { peer_address }
        }

        /// Sends a chunked payload to the peer and awaits the reassembled response.
        pub async fn send_and_receive(
            &self,
            payload: &[u8],
            chunk_size: usize,
        ) -> Result<Option<Vec<u8>>, CentralError> {
            let session = Session::new()
                .await
                .map_err(|e| CentralError::ConnectionFailed(e.to_string()))?;
            let adapter = session
                .default_adapter()
                .await
                .map_err(|e| CentralError::ConnectionFailed(e.to_string()))?;

            let device = adapter
                .device(self.peer_address)
                .map_err(|e| CentralError::DeviceNotFound(e.to_string()))?;

            if !device.is_connected().await.unwrap_or(false) {
                device
                    .connect()
                    .await
                    .map_err(|e| CentralError::ConnectionFailed(e.to_string()))?;
            }

            // Locate the Cycles Sync Characteristic
            let mut sync_char = None;
            for service in device
                .services()
                .await
                .map_err(|e| CentralError::ServiceNotFound(e.to_string()))?
            {
                if service.uuid().await.unwrap_or_default() == CYCLES_SERVICE_UUID {
                    for charac in service.characteristics().await.unwrap_or_default() {
                        if charac.uuid().await.unwrap_or_default() == CYCLES_CHAR_SYNC_UUID {
                            sync_char = Some(charac);
                            break;
                        }
                    }
                }
            }

            let sync_char = sync_char.ok_or_else(|| {
                CentralError::CharacteristicNotFound(CYCLES_CHAR_SYNC_UUID.to_string())
            })?;

            // Chunk the payload into MTU-sized frames
            let frames = Chunker::chunk(1, payload, chunk_size);
            for frame in frames {
                let encoded = frame.encode();
                sync_char
                    .write(&encoded)
                    .await
                    .map_err(|e| CentralError::WriteError(e.to_string()))?;
            }

            // Read response frames from peripheral
            let mut reassembler = Reassembler::new();
            loop {
                let chunk_bytes = sync_char
                    .read()
                    .await
                    .map_err(|e| CentralError::ReadError(e.to_string()))?;

                if chunk_bytes.is_empty() {
                    break;
                }

                if let Ok(frame) = Frame::decode(&chunk_bytes) {
                    if let Ok(Some(complete)) = reassembler.feed(frame) {
                        return Ok(Some(complete));
                    }
                }
            }

            Ok(None)
        }
    }
}

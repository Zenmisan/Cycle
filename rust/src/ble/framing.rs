//! Chunking and framing protocol for BLE payloads.
//!
//! BLE MTU limits individual GATT attribute transfers (typically 23 to 512 bytes).
//! This module implements the framed packet chunker and reassembler:
//! `[MsgId: 2B][Seq: 2B][TotalChunks: 2B][Payload: NB][CRC32: 4B]`

use crc32fast::Hasher;
use std::collections::HashMap;

/// Minimum frame size: 2 (MsgId) + 2 (Seq) + 2 (TotalChunks) + 4 (CRC32) = 10 bytes.
pub const FRAME_HEADER_LEN: usize = 6;
pub const FRAME_TRAILER_LEN: usize = 4;
pub const MIN_FRAME_LEN: usize = FRAME_HEADER_LEN + FRAME_TRAILER_LEN;

/// Default MTU-safe chunk payload size (e.g. 512 MTU - 10 bytes = 502, or 240 for typical LE connections).
pub const DEFAULT_MAX_CHUNK_PAYLOAD: usize = 240;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub msg_id: u16,
    pub seq: u16,
    pub total_chunks: u16,
    pub payload: Vec<u8>,
    pub crc32: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum FramingError {
    #[error("Frame too short: expected at least {MIN_FRAME_LEN} bytes, got {0}")]
    FrameTooShort(usize),
    #[error("Invalid chunk sequence {seq} for total chunks {total_chunks}")]
    InvalidSequence { seq: u16, total_chunks: u16 },
    #[error("CRC32 mismatch: expected {expected:#010x}, calculated {calculated:#010x}")]
    ChecksumMismatch { expected: u32, calculated: u32 },
    #[error("Incomplete message {msg_id}: received {received}/{total} chunks")]
    IncompleteMessage {
        msg_id: u16,
        received: usize,
        total: u16,
    },
}

impl Frame {
    pub fn encode(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(MIN_FRAME_LEN + self.payload.len());
        buf.extend_from_slice(&self.msg_id.to_be_bytes());
        buf.extend_from_slice(&self.seq.to_be_bytes());
        buf.extend_from_slice(&self.total_chunks.to_be_bytes());
        buf.extend_from_slice(&self.payload);
        buf.extend_from_slice(&self.crc32.to_be_bytes());
        buf
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, FramingError> {
        if bytes.len() < MIN_FRAME_LEN {
            return Err(FramingError::FrameTooShort(bytes.len()));
        }

        let msg_id = u16::from_be_bytes([bytes[0], bytes[1]]);
        let seq = u16::from_be_bytes([bytes[2], bytes[3]]);
        let total_chunks = u16::from_be_bytes([bytes[4], bytes[5]]);

        if total_chunks == 0 || seq >= total_chunks {
            return Err(FramingError::InvalidSequence { seq, total_chunks });
        }

        let payload_len = bytes.len() - MIN_FRAME_LEN;
        let payload = bytes[FRAME_HEADER_LEN..FRAME_HEADER_LEN + payload_len].to_vec();

        let trailer_start = bytes.len() - FRAME_TRAILER_LEN;
        let crc32 = u32::from_be_bytes([
            bytes[trailer_start],
            bytes[trailer_start + 1],
            bytes[trailer_start + 2],
            bytes[trailer_start + 3],
        ]);

        Ok(Self {
            msg_id,
            seq,
            total_chunks,
            payload,
            crc32,
        })
    }
}

/// Chunker partitions arbitrary payloads into a sequence of MTU-sized Frames.
pub struct Chunker;

impl Chunker {
    pub fn chunk(msg_id: u16, payload: &[u8], max_chunk_size: usize) -> Vec<Frame> {
        let max_chunk = if max_chunk_size == 0 {
            DEFAULT_MAX_CHUNK_PAYLOAD
        } else {
            max_chunk_size
        };

        let mut hasher = Hasher::new();
        hasher.update(payload);
        let crc32 = hasher.finalize();

        if payload.is_empty() {
            return vec![Frame {
                msg_id,
                seq: 0,
                total_chunks: 1,
                payload: Vec::new(),
                crc32,
            }];
        }

        let chunks: Vec<&[u8]> = payload.chunks(max_chunk).collect();
        let total_chunks = chunks.len() as u16;

        chunks
            .into_iter()
            .enumerate()
            .map(|(i, chunk)| Frame {
                msg_id,
                seq: i as u16,
                total_chunks,
                payload: chunk.to_vec(),
                crc32,
            })
            .collect()
    }
}

/// Reassembler collects frames and reconstructs complete payloads with CRC32 verification.
#[derive(Default)]
pub struct Reassembler {
    pending_messages: HashMap<u16, MessageAssembly>,
}

struct MessageAssembly {
    total_chunks: u16,
    expected_crc: u32,
    chunks: HashMap<u16, Vec<u8>>,
}

impl Reassembler {
    pub fn new() -> Self {
        Self {
            pending_messages: HashMap::new(),
        }
    }

    /// Feed an incoming frame.
    /// Returns `Ok(Some(payload))` when the entire message has been assembled and verified.
    /// Returns `Ok(None)` if more chunks are expected.
    pub fn feed(&mut self, frame: Frame) -> Result<Option<Vec<u8>>, FramingError> {
        let msg_id = frame.msg_id;
        let entry = self
            .pending_messages
            .entry(msg_id)
            .or_insert_with(|| MessageAssembly {
                total_chunks: frame.total_chunks,
                expected_crc: frame.crc32,
                chunks: HashMap::new(),
            });

        entry.chunks.insert(frame.seq, frame.payload);

        if entry.chunks.len() == entry.total_chunks as usize {
            let assembly = self.pending_messages.remove(&msg_id).unwrap();
            let mut full_payload = Vec::new();

            for seq in 0..assembly.total_chunks {
                match assembly.chunks.get(&seq) {
                    Some(chunk) => full_payload.extend_from_slice(chunk),
                    None => {
                        return Err(FramingError::IncompleteMessage {
                            msg_id,
                            received: assembly.chunks.len(),
                            total: assembly.total_chunks,
                        });
                    }
                }
            }

            let mut hasher = Hasher::new();
            hasher.update(&full_payload);
            let calculated_crc = hasher.finalize();

            if calculated_crc != assembly.expected_crc {
                return Err(FramingError::ChecksumMismatch {
                    expected: assembly.expected_crc,
                    calculated: calculated_crc,
                });
            }

            Ok(Some(full_payload))
        } else {
            Ok(None)
        }
    }

    pub fn clear(&mut self) {
        self.pending_messages.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_single_frame_roundtrip() {
        let data = b"Hello, Cycles BLE!".to_vec();
        let frames = Chunker::chunk(1, &data, 100);
        assert_eq!(frames.len(), 1);

        let encoded = frames[0].encode();
        let decoded = Frame::decode(&encoded).unwrap();
        assert_eq!(decoded, frames[0]);

        let mut reassembler = Reassembler::new();
        let result = reassembler.feed(decoded).unwrap();
        assert_eq!(result, Some(data));
    }

    #[test]
    fn test_multi_frame_chunking_and_reassembly() {
        // 10 KB payload
        let data: Vec<u8> = (0..10_000).map(|i| (i % 256) as u8).collect();
        let chunk_size = 200;
        let frames = Chunker::chunk(42, &data, chunk_size);
        assert_eq!(frames.len(), 50);

        let mut reassembler = Reassembler::new();
        let mut completed = None;

        for (i, frame) in frames.into_iter().enumerate() {
            let encoded = frame.encode();
            let decoded = Frame::decode(&encoded).unwrap();
            let res = reassembler.feed(decoded).unwrap();
            if i == 49 {
                completed = res;
            } else {
                assert!(res.is_none());
            }
        }

        assert_eq!(completed, Some(data));
    }

    #[test]
    fn test_out_of_order_reassembly() {
        let data = b"Out of order test payload that will be split into multiple chunks".to_vec();
        let frames = Chunker::chunk(99, &data, 10);
        assert!(frames.len() > 1);

        let mut reassembler = Reassembler::new();

        // Feed chunks in reverse order
        let mut completed = None;
        for frame in frames.into_iter().rev() {
            let res = reassembler.feed(frame).unwrap();
            if res.is_some() {
                completed = res;
            }
        }

        assert_eq!(completed, Some(data));
    }

    #[test]
    fn test_corrupted_payload_checksum_mismatch() {
        let data = b"Integrity check payload".to_vec();
        let mut frames = Chunker::chunk(7, &data, 100);
        // Corrupt a byte in payload
        frames[0].payload[0] ^= 0xFF;

        let mut reassembler = Reassembler::new();
        let err = reassembler.feed(frames[0].clone()).unwrap_err();
        match err {
            FramingError::ChecksumMismatch { .. } => {}
            _ => panic!("Expected ChecksumMismatch error, got {:?}", err),
        }
    }
}

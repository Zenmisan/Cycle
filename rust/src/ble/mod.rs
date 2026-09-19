//! BLE Transport subsystem for Cycles.
//!
//! Provides peer discovery, tie-breaking, framing/chunking, and GATT client/server byte transport.

pub mod central;
pub mod discovery;
pub mod framing;
pub mod pairing;
pub mod peripheral;
pub mod tie_break;
pub mod transport;

pub use discovery::{CYCLES_CHAR_SYNC_UUID, CYCLES_SERVICE_UUID};
pub use framing::{Chunker, Frame, Reassembler};
pub use pairing::{HandshakePayload, PeerIdentity, PeerStore};
pub use tie_break::{decide_role, BleRole};
pub use transport::{merge_incoming, MergeResult, SimulatedBleNode};

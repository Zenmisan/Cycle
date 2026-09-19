//! High-level BLE transport coordinator and CRDT seam contract.
//!
//! Provides the seam for `automerge_core_20260919`:
//! `fn merge_incoming(bytes: Vec<u8>) -> MergeResult`
//!
//! Handles bidirectional chunked frame transmission, pairing verification,
//! and simulated channel verification for testing.

use super::{
    framing::{Chunker, Frame, Reassembler},
    pairing::PeerStore,
    tie_break::decide_role,
};

/// The result of an incoming sync merge operation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MergeResult {
    /// Optional response bytes to send back to the peer (e.g. Automerge sync response or ACK).
    pub response_bytes: Option<Vec<u8>>,
    /// True if merge was applied cleanly.
    pub success: bool,
}

/// Merges incoming bytes from a BLE sync exchange.
/// When the CRDT state is initialized, feeds the payload into Automerge and generates
/// the next sync round message. Falls back to ACK echo for standalone transport tests.
pub fn merge_incoming(bytes: Vec<u8>) -> MergeResult {
    if let Some(reply) = crate::api::process_crdt_sync_payload("ble-peer", &bytes) {
        return MergeResult {
            response_bytes: Some(reply),
            success: true,
        };
    }

    let mut ack_response = b"ACK:".to_vec();
    ack_response.extend_from_slice(&bytes);
    MergeResult {
        response_bytes: Some(ack_response),
        success: true,
    }
}

/// Simulated in-memory BLE channel for testing full protocol flow (discovery,
/// tie-breaking, chunking, CRC32, reassembly, bidirectional response).
pub struct SimulatedBleNode {
    pub device_id: String,
    pub peer_store: PeerStore,
    pub reassembler: Reassembler,
}

impl SimulatedBleNode {
    pub fn new(device_id: &str) -> Self {
        Self {
            device_id: device_id.to_string(),
            peer_store: PeerStore::new(),
            reassembler: Reassembler::new(),
        }
    }

    /// Simulates a bidirectional sync exchange between this node and a remote node.
    /// Returns (receiver_received_payload, initiator_received_response).
    pub fn sync_with(
        &mut self,
        remote: &mut SimulatedBleNode,
        outgoing_payload: &[u8],
        chunk_size: usize,
    ) -> Result<(Vec<u8>, Vec<u8>), Box<dyn std::error::Error>> {
        // 1. Tie-break roles
        let local_role = decide_role(&self.device_id, &remote.device_id)?;
        let remote_role = decide_role(&remote.device_id, &self.device_id)?;
        assert_ne!(local_role, remote_role, "Roles must be mutually exclusive");

        // 2. Chunk outgoing payload (Initiator -> Receiver)
        let frames = Chunker::chunk(1, outgoing_payload, chunk_size);

        // 3. Transmit frames to remote reassembler
        let mut receiver_payload = None;
        for frame in frames {
            let wire_bytes = frame.encode();
            let decoded = Frame::decode(&wire_bytes)?;
            if let Some(complete) = remote.reassembler.feed(decoded)? {
                receiver_payload = Some(complete);
            }
        }

        let received = receiver_payload.ok_or("Receiver did not complete payload reassembly")?;

        // 4. Receiver calls merge_incoming
        let merge_res = merge_incoming(received.clone());
        let response_to_send = merge_res
            .response_bytes
            .ok_or("No response bytes from merge")?;

        // 5. Reverse direction: Receiver -> Initiator
        let resp_frames = Chunker::chunk(2, &response_to_send, chunk_size);
        let mut initiator_response = None;
        for frame in resp_frames {
            let wire_bytes = frame.encode();
            let decoded = Frame::decode(&wire_bytes)?;
            if let Some(complete) = self.reassembler.feed(decoded)? {
                initiator_response = Some(complete);
            }
        }

        let final_resp =
            initiator_response.ok_or("Initiator did not complete response reassembly")?;

        Ok((received, final_resp))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_merge_incoming_stub() {
        let input = b"test-crdt-payload".to_vec();
        let result = merge_incoming(input.clone());
        assert!(result.success);
        assert_eq!(result.response_bytes, Some([b"ACK:", &input[..]].concat()));
    }

    #[test]
    fn test_bidirectional_simulated_ble_transport() {
        let mut node_a = SimulatedBleNode::new("device-02-initiator");
        let mut node_b = SimulatedBleNode::new("device-01-receiver");

        // 15 KB payload to force multi-chunking across MTU boundaries
        let payload: Vec<u8> = (0..15_000).map(|i| (i % 256) as u8).collect();
        let chunk_size = 200; // Small MTU chunk size -> ~75 frames

        let (received_by_b, response_received_by_a) = node_a
            .sync_with(&mut node_b, &payload, chunk_size)
            .expect("Simulated BLE sync failed");

        // Verify A -> B integrity
        assert_eq!(received_by_b.len(), 15_000);
        assert_eq!(received_by_b, payload);

        // Verify B -> A reverse direction integrity
        let expected_ack = [b"ACK:", &payload[..]].concat();
        assert_eq!(response_received_by_a.len(), expected_ack.len());
        assert_eq!(response_received_by_a, expected_ack);
    }

    #[test]
    fn test_crdt_automerge_sync_over_simulated_ble_frames() {
        use crate::crdt::{SyncSession, TaskDoc, TaskRecord};

        let mut doc_a = TaskDoc::new();
        let mut doc_b = TaskDoc::new();

        let mut session_a = SyncSession::new();
        let mut session_b = SyncSession::new();

        // Add a task to doc A
        let task = TaskRecord {
            id: "task-ble-001".to_string(),
            project_id: "project-1".to_string(),
            title: "Test BLE CRDT Sync".to_string(),
            notes: "This task traveled over simulated BLE chunked frames".to_string(),
            due_millis: Some(1742400000000),
            tags: vec!["ble".to_string(), "p2p".to_string()],
            status: "open".to_string(),
            priority: 1,
            created_at_millis: 1742400000000,
            updated_at_millis: 1742400000000,
        };
        doc_a.upsert_task(&task).expect("upsert task");

        let mut total_chunks_transferred = 0;
        let mut rounds = 0;

        loop {
            rounds += 1;
            assert!(rounds < 20, "sync did not converge within 20 rounds");
            let mut quiet = true;

            // A -> B step
            if let Some(msg_a) = session_a.generate_message(&mut doc_a) {
                quiet = false;
                // Chunk into small 20-byte BLE frames
                let frames_a = Chunker::chunk(rounds as u16 * 2, &msg_a, 20);
                total_chunks_transferred += frames_a.len();
                let mut reassembler_b = Reassembler::new();
                let mut reassembled_b = None;
                for frame in frames_a {
                    let wire = frame.encode();
                    let decoded = Frame::decode(&wire).expect("decode wire on B");
                    if let Some(payload) = reassembler_b.feed(decoded).expect("feed on B") {
                        reassembled_b = Some(payload);
                    }
                }
                let payload = reassembled_b.expect("reassembly completed on B");
                session_b.receive_message(&mut doc_b, payload).expect("receive on B");
            }

            // B -> A step
            if let Some(msg_b) = session_b.generate_message(&mut doc_b) {
                quiet = false;
                let frames_b = Chunker::chunk(rounds as u16 * 2 + 1, &msg_b, 20);
                total_chunks_transferred += frames_b.len();
                let mut reassembler_a = Reassembler::new();
                let mut reassembled_a = None;
                for frame in frames_b {
                    let wire = frame.encode();
                    let decoded = Frame::decode(&wire).expect("decode wire on A");
                    if let Some(payload) = reassembler_a.feed(decoded).expect("feed on A") {
                        reassembled_a = Some(payload);
                    }
                }
                let payload = reassembled_a.expect("reassembly completed on A");
                session_a.receive_message(&mut doc_a, payload).expect("receive on A");
            }

            if quiet {
                break;
            }
        }

        assert!(total_chunks_transferred > 1);

        // Both docs converged!
        let all_a = doc_a.all_tasks();
        let all_b = doc_b.all_tasks();
        assert_eq!(all_a.len(), 1);
        assert_eq!(all_b.len(), 1);
        assert_eq!(all_a[0].id, "task-ble-001");
        assert_eq!(all_b[0].id, "task-ble-001");
        assert_eq!(all_a[0].title, all_b[0].title);
        assert_eq!(all_a[0].notes, all_b[0].notes);
    }
}

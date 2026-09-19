//! Socket transport for Wi-Fi Direct point-to-point links.
//!
//! Reuses the exact same framing protocol as BLE (`ble::framing`) and
//! the deterministic tie-breaking role assignment (`ble::tie_break`).
//! Data transfers over a dedicated TCP port (`47226`) on the Wi-Fi Direct subnet,
//! feeding into `api::merge_incoming` / `generate_sync_message`.

use std::io::{Read, Write};
use std::net::{IpAddr, TcpListener, TcpStream};

use crate::ble::framing::{Chunker, Frame, Reassembler};
use crate::ble::tie_break::{decide_role, BleRole};

/// Dedicated port for Cycles Wi-Fi Direct P2P sync sockets.
/// Kept distinct from LAN port (47225) to avoid any port binding conflicts.
pub const CYCLES_WIFI_DIRECT_PORT: u16 = 47226;

const MAX_CHUNK: usize = 32 * 1024; // High-throughput P2P Wi-Fi link.

/// Executes one synchronous transfer round over a Wi-Fi Direct IP link.
/// Role tie-breaking determines which side connects (Central) vs listens (Peripheral).
pub fn sync_round_wifi_direct(
    local_id: &str,
    remote_id: &str,
    peer_addr: IpAddr,
    peer_port: u16,
    local_port: u16,
    outgoing_message: Vec<u8>,
) -> Result<Vec<u8>, String> {
    let role = decide_role(local_id, remote_id).map_err(|e| e.to_string())?;

    let mut stream = match role {
        BleRole::Central => {
            TcpStream::connect((peer_addr, peer_port)).map_err(|e| e.to_string())?
        }
        BleRole::Peripheral => {
            let listener =
                TcpListener::bind(("0.0.0.0", local_port)).map_err(|e| e.to_string())?;
            let (stream, _) = listener.accept().map_err(|e| e.to_string())?;
            stream
        }
    };

    send_message(&mut stream, 1, &outgoing_message)?;
    receive_message(&mut stream)
}

fn send_message(stream: &mut TcpStream, msg_id: u16, payload: &[u8]) -> Result<(), String> {
    for frame in Chunker::chunk(msg_id, payload, MAX_CHUNK) {
        let encoded = frame.encode();
        let len = (encoded.len() as u32).to_be_bytes();
        stream.write_all(&len).map_err(|e| e.to_string())?;
        stream.write_all(&encoded).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn receive_message(stream: &mut TcpStream) -> Result<Vec<u8>, String> {
    let mut reassembler = Reassembler::new();
    loop {
        let mut len_buf = [0u8; 4];
        stream.read_exact(&mut len_buf).map_err(|e| e.to_string())?;
        let len = u32::from_be_bytes(len_buf) as usize;

        let mut frame_buf = vec![0u8; len];
        stream.read_exact(&mut frame_buf).map_err(|e| e.to_string())?;
        let frame = Frame::decode(&frame_buf).map_err(|e| e.to_string())?;

        if let Some(payload) = reassembler.feed(frame).map_err(|e| e.to_string())? {
            return Ok(payload);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;

    #[test]
    fn test_wifi_direct_bidirectional_exchange_over_loopback() {
        let port = 58240;
        let payload_from_a: Vec<u8> = (0..50_000).map(|i| (i % 251) as u8).collect();
        let payload_from_b: Vec<u8> = (0..35_000).map(|i| ((i * 13) % 251) as u8).collect();

        let a_payload = payload_from_a.clone();
        let b_expected = payload_from_a.clone();
        let a_expected = payload_from_b.clone();
        let b_payload = payload_from_b.clone();

        // "device-b" > "device-a" => device-b is Central, device-a is Peripheral
        let handle_a = thread::spawn(move || {
            sync_round_wifi_direct(
                "device-a",
                "device-b",
                "127.0.0.1".parse().unwrap(),
                0,
                port,
                a_payload,
            )
        });

        // Give listener a moment to bind
        thread::sleep(std::time::Duration::from_millis(50));

        let handle_b = thread::spawn(move || {
            sync_round_wifi_direct(
                "device-b",
                "device-a",
                "127.0.0.1".parse().unwrap(),
                port,
                0,
                b_payload,
            )
        });

        let received_by_a = handle_a.join().unwrap().expect("Side A failed");
        let received_by_b = handle_b.join().unwrap().expect("Side B failed");

        assert_eq!(received_by_a, a_expected);
        assert_eq!(received_by_b, b_expected);
    }

    #[test]
    fn test_wifi_direct_crdt_automerge_convergence_over_p2p_socket() {
        use crate::crdt::{SyncSession, TaskDoc, TaskRecord};

        let mut doc_a = TaskDoc::new();
        let mut doc_b = TaskDoc::new();

        let task_a = TaskRecord {
            id: "task-wfd-001".to_string(),
            project_id: "proj-1".to_string(),
            title: "Task on A via Wi-Fi Direct".to_string(),
            notes: "Transferred over Wi-Fi Direct TCP socket".to_string(),
            due_millis: None,
            tags: vec!["wifi-direct".to_string()],
            status: "open".to_string(),
            priority: 1,
            created_at_millis: 1742400000000,
            updated_at_millis: 1742400000000,
        };
        let task_b = TaskRecord {
            id: "task-wfd-002".to_string(),
            project_id: "proj-1".to_string(),
            title: "Task on B via Wi-Fi Direct".to_string(),
            notes: "Local task on side B".to_string(),
            due_millis: None,
            tags: vec!["p2p".to_string()],
            status: "open".to_string(),
            priority: 2,
            created_at_millis: 1742400001000,
            updated_at_millis: 1742400001000,
        };

        doc_a.upsert_task(&task_a).unwrap();
        doc_b.upsert_task(&task_b).unwrap();

        let mut session_a = SyncSession::new();
        let mut session_b = SyncSession::new();
        let mut port = 58245;

        // Drive sync rounds until both sides have no more messages
        for _ in 0..10 {
            port += 1;
            let msg_a_opt = session_a.generate_message(&mut doc_a);
            let msg_b_opt = session_b.generate_message(&mut doc_b);

            if msg_a_opt.is_none() && msg_b_opt.is_none() {
                break;
            }

            let msg_a = msg_a_opt.unwrap_or_default();
            let msg_b = msg_b_opt.unwrap_or_default();

            let handle_a = {
                let msg = msg_a.clone();
                thread::spawn(move || {
                    sync_round_wifi_direct(
                        "device-a",
                        "device-b",
                        "127.0.0.1".parse().unwrap(),
                        0,
                        port,
                        msg,
                    )
                })
            };

            thread::sleep(std::time::Duration::from_millis(30));

            let handle_b = {
                let msg = msg_b.clone();
                thread::spawn(move || {
                    sync_round_wifi_direct(
                        "device-b",
                        "device-a",
                        "127.0.0.1".parse().unwrap(),
                        port,
                        0,
                        msg,
                    )
                })
            };

            let received_by_a = handle_a.join().unwrap().expect("Side A sync failed");
            let received_by_b = handle_b.join().unwrap().expect("Side B sync failed");

            if !received_by_a.is_empty() {
                let _ = session_a.receive_message(&mut doc_a, received_by_a);
            }
            if !received_by_b.is_empty() {
                let _ = session_b.receive_message(&mut doc_b, received_by_b);
            }
        }

        let tasks_a = doc_a.all_tasks();
        let tasks_b = doc_b.all_tasks();

        assert_eq!(tasks_a.len(), 2);
        assert_eq!(tasks_b.len(), 2);
        let ids_a: Vec<_> = tasks_a.iter().map(|t| t.id.as_str()).collect();
        let ids_b: Vec<_> = tasks_b.iter().map(|t| t.id.as_str()).collect();
        assert!(ids_a.contains(&"task-wfd-001"));
        assert!(ids_a.contains(&"task-wfd-002"));
        assert_eq!(ids_a, ids_b);
    }
}

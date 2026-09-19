//! TCP transport for the LAN fast-path. Same framing as BLE (`ble::framing`)
//! and the same tie-breaking rule (`ble::tie_break`) — LAN just swaps GATT
//! reads/writes for a plain socket. Once connected, calls the exact same
//! `api::merge_incoming`/`generate_sync_message` seam the BLE transport uses;
//! this module knows nothing about Automerge.

use std::io::{Read, Write};
use std::net::{IpAddr, TcpListener, TcpStream};

use crate::ble::framing::{Chunker, Frame, Reassembler};
use crate::ble::tie_break::{decide_role, BleRole};

const MAX_CHUNK: usize = 16 * 1024; // LAN has no MTU pressure — chunk generously.

/// Runs one full sync round over a LAN TCP connection with `peer_addr`.
/// `role` decides whether this side listens (Peripheral-equivalent) or
/// connects (Central-equivalent) — reuses `decide_role` so LAN and BLE never
/// disagree about who initiates for a given device-id pair.
///
/// `local_id`/`remote_id` decide the role; `local_port` is where this device
/// listens when it's the Peripheral-equivalent side.
pub fn sync_round(
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
            let listener = TcpListener::bind(("0.0.0.0", local_port)).map_err(|e| e.to_string())?;
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
    fn bidirectional_multi_kb_exchange_over_loopback() {
        // "device-b" > "device-a" lexicographically, so B is Central (connects),
        // A is Peripheral (listens) — matches decide_role's rule exactly.
        let port = 58234;
        let payload_from_a: Vec<u8> = (0..20_000).map(|i| (i % 251) as u8).collect();
        let payload_from_b: Vec<u8> = (0..15_000).map(|i| ((i * 7) % 251) as u8).collect();

        let a_payload = payload_from_a.clone();
        let b_expected = payload_from_a.clone();
        let a_expected = payload_from_b.clone();
        let b_payload = payload_from_b.clone();

        let handle_a = thread::spawn(move || {
            sync_round(
                "device-a",
                "device-b",
                "127.0.0.1".parse().unwrap(),
                0, // peripheral side doesn't dial out
                port,
                a_payload,
            )
        });

        // Give the listener a moment to bind before the client connects.
        thread::sleep(std::time::Duration::from_millis(100));

        let handle_b = thread::spawn(move || {
            sync_round(
                "device-b",
                "device-a",
                "127.0.0.1".parse().unwrap(),
                port,
                0,
                b_payload,
            )
        });

        let received_by_a = handle_a.join().unwrap().expect("A's sync round failed");
        let received_by_b = handle_b.join().unwrap().expect("B's sync round failed");

        assert_eq!(received_by_a, a_expected);
        assert_eq!(received_by_b, b_expected);
    }
}

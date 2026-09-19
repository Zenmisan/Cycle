//! WebSocket relay client — last-resort transport for syncing with a peer
//! that's out of BLE/LAN/WiFi Direct range entirely. Opt-in only; the caller
//! (`api::sync_with_peer_relay`) is responsible for checking the user's
//! settings before ever reaching this module. This module knows nothing
//! about Automerge — it just moves one message to `peer_id` and waits for
//! one message back, addressed from that same `peer_id`.

use futures_util::{SinkExt, StreamExt};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::tungstenite::Message as WsMessage;

use super::protocol::{ClientMessage, ServerMessage};

const RESPONSE_TIMEOUT: Duration = Duration::from_secs(15);

/// Connects to `relay_url`, identifies as `local_id`, sends `outgoing` to
/// `peer_id`, and waits for exactly one response addressed back from that
/// peer. Returns an error if the peer never responds within the timeout
/// (e.g. not currently connected to the relay) — that's an expected,
/// non-fatal outcome the caller should treat as "relay sync unavailable
/// right now," not a crash.
pub async fn sync_via_relay(
    relay_url: &str,
    token: &str,
    local_id: &str,
    peer_id: &str,
    outgoing: Vec<u8>,
) -> Result<Vec<u8>, String> {
    let (ws_stream, _) = tokio_tungstenite::connect_async(relay_url)
        .await
        .map_err(|e| format!("relay connect failed: {e}"))?;
    let (mut write, mut read) = ws_stream.split();

    send(
        &mut write,
        &ClientMessage::Connect {
            device_id: local_id.to_string(),
            token: token.to_string(),
        },
    )
    .await?;

    send(
        &mut write,
        &ClientMessage::Data {
            to: peer_id.to_string(),
            payload: outgoing,
        },
    )
    .await?;

    let response = timeout(RESPONSE_TIMEOUT, async {
        while let Some(msg) = read.next().await {
            let msg = msg.map_err(|e| format!("relay read failed: {e}"))?;
            let WsMessage::Text(text) = msg else {
                continue;
            };
            let parsed: ServerMessage =
                serde_json::from_str(&text).map_err(|e| format!("bad relay message: {e}"))?;
            match parsed {
                ServerMessage::Data { from, payload } if from == peer_id => {
                    return Ok(payload);
                }
                ServerMessage::Data { .. } => continue, // not from our peer, ignore
                ServerMessage::Error { message } => {
                    return Err(format!("relay error: {message}"));
                }
            }
        }
        Err("relay connection closed before peer responded".to_string())
    })
    .await
    .map_err(|_| "timed out waiting for peer via relay".to_string())??;

    Ok(response)
}

async fn send<S>(
    write: &mut futures_util::stream::SplitSink<S, WsMessage>,
    msg: &ClientMessage,
) -> Result<(), String>
where
    S: futures_util::Sink<WsMessage>,
    <S as futures_util::Sink<WsMessage>>::Error: std::fmt::Display,
{
    let json = serde_json::to_string(msg).map_err(|e| e.to_string())?;
    write
        .send(WsMessage::Text(json.into()))
        .await
        .map_err(|e| format!("relay send failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crdt::{SyncSession, TaskDoc, TaskRecord};
    use std::collections::HashMap;
    use std::sync::Arc;
    use tokio::net::TcpListener;
    use tokio::sync::Mutex;

    /// Minimal in-process relay: accepts connections, reads each client's
    /// Connect message, then routes subsequent Data messages by `to` field
    /// to whichever other connection identified as that device_id. Just
    /// enough to test the real client against real routing logic — not the
    /// production Go server (that's `relay_server_20260919`'s job).
    async fn run_mock_relay(listener: TcpListener) {
        let clients: Arc<Mutex<HashMap<String, tokio::sync::mpsc::UnboundedSender<ServerMessage>>>> =
            Arc::new(Mutex::new(HashMap::new()));

        loop {
            let Ok((stream, _)) = listener.accept().await else {
                return;
            };
            let clients = clients.clone();
            tokio::spawn(async move {
                let Ok(ws) = tokio_tungstenite::accept_async(stream).await else {
                    return;
                };
                let (mut write, mut read) = ws.split();
                let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<ServerMessage>();

                let mut device_id = None;
                while let Some(Ok(WsMessage::Text(text))) = read.next().await {
                    let Ok(msg) = serde_json::from_str::<ClientMessage>(&text) else {
                        continue;
                    };
                    match msg {
                        ClientMessage::Connect { device_id: id, .. } => {
                            clients.lock().await.insert(id.clone(), tx.clone());
                            device_id = Some(id);
                            break;
                        }
                        ClientMessage::Data { .. } => continue,
                    }
                }

                let Some(my_id) = device_id else { return };

                let forward_task = tokio::spawn(async move {
                    while let Some(server_msg) = rx.recv().await {
                        let json = serde_json::to_string(&server_msg).unwrap();
                        if write.send(WsMessage::Text(json.into())).await.is_err() {
                            break;
                        }
                    }
                });

                while let Some(Ok(WsMessage::Text(text))) = read.next().await {
                    let Ok(ClientMessage::Data { to, payload }) =
                        serde_json::from_str::<ClientMessage>(&text)
                    else {
                        continue;
                    };
                    if let Some(peer_tx) = clients.lock().await.get(&to) {
                        let _ = peer_tx.send(ServerMessage::Data {
                            from: my_id.clone(),
                            payload,
                        });
                    }
                }

                clients.lock().await.remove(&my_id);
                forward_task.abort();
            });
        }
    }

    async fn start_mock_relay() -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(run_mock_relay(listener));
        format!("ws://{addr}")
    }

    #[tokio::test]
    async fn message_routes_correctly_between_two_peers() {
        let url = start_mock_relay().await;

        let url_b = url.clone();
        let responder = tokio::spawn(async move {
            // Side B: connect, wait for A's message, echo something back.
            let (ws, _) = tokio_tungstenite::connect_async(&url_b).await.unwrap();
            let (mut write, mut read) = ws.split();
            send(
                &mut write,
                &ClientMessage::Connect {
                    device_id: "device-b".to_string(),
                    token: "t".to_string(),
                },
            )
            .await
            .unwrap();

            while let Some(Ok(WsMessage::Text(text))) = read.next().await {
                if let Ok(ServerMessage::Data { from, payload }) =
                    serde_json::from_str::<ServerMessage>(&text)
                {
                    assert_eq!(from, "device-a");
                    assert_eq!(payload, b"hello from a".to_vec());
                    send(
                        &mut write,
                        &ClientMessage::Data {
                            to: "device-a".to_string(),
                            payload: b"hello from b".to_vec(),
                        },
                    )
                    .await
                    .unwrap();
                    break;
                }
            }
        });

        // Give B a moment to connect before A sends.
        tokio::time::sleep(Duration::from_millis(100)).await;

        let response = sync_via_relay(
            &url,
            "t",
            "device-a",
            "device-b",
            b"hello from a".to_vec(),
        )
        .await
        .expect("relay sync failed");

        assert_eq!(response, b"hello from b".to_vec());
        responder.await.unwrap();
    }

    /// Real end-to-end check against the actual `relay-server/` Go binary —
    /// not the in-process mock above. Ignored by default since it needs an
    /// external process; run explicitly:
    ///
    /// ```sh
    /// cd relay-server && go build -o /tmp/cycles-relay-test .
    /// RELAY_AUTH_TOKEN=test-secret PORT=8199 /tmp/cycles-relay-test &
    /// cargo test relay::client::tests::real_relay_server_routes_a_message -- --ignored
    /// ```
    #[tokio::test]
    #[ignore = "requires a running relay-server instance, see doc comment"]
    async fn real_relay_server_routes_a_message() {
        let url = "ws://127.0.0.1:8199/ws";
        let token = "test-secret";

        let responder = tokio::spawn(async move {
            let (ws, _) = tokio_tungstenite::connect_async(url).await.unwrap();
            let (mut write, mut read) = ws.split();
            send(
                &mut write,
                &ClientMessage::Connect {
                    device_id: "real-device-b".to_string(),
                    token: token.to_string(),
                },
            )
            .await
            .unwrap();

            while let Some(Ok(WsMessage::Text(text))) = read.next().await {
                if let Ok(ServerMessage::Data { from, payload }) =
                    serde_json::from_str::<ServerMessage>(&text)
                {
                    assert_eq!(from, "real-device-a");
                    assert_eq!(payload, b"hello real relay".to_vec());
                    send(
                        &mut write,
                        &ClientMessage::Data {
                            to: "real-device-a".to_string(),
                            payload: b"reply from real relay".to_vec(),
                        },
                    )
                    .await
                    .unwrap();
                    break;
                }
            }
        });

        tokio::time::sleep(Duration::from_millis(150)).await;

        let response = sync_via_relay(
            url,
            token,
            "real-device-a",
            "real-device-b",
            b"hello real relay".to_vec(),
        )
        .await
        .expect("real relay sync failed");

        assert_eq!(response, b"reply from real relay".to_vec());
        responder.await.unwrap();
    }

    #[tokio::test]
    async fn crdt_task_syncs_through_mock_relay() {
        let url = start_mock_relay().await;

        let mut doc_a = TaskDoc::new();
        let mut session_a = SyncSession::new();
        doc_a
            .upsert_task(&TaskRecord {
                id: "task-relay-001".to_string(),
                project_id: "p1".to_string(),
                title: "Synced over relay".to_string(),
                notes: String::new(),
                due_millis: None,
                tags: vec![],
                status: "open".to_string(),
                priority: 0,
                created_at_millis: 0,
                updated_at_millis: 0,
            })
            .unwrap();

        // B's doc/session are shared with the test body (via Arc<Mutex<_>>)
        // rather than moved fully into the responder task, since the
        // responder must keep running across *multiple* rounds — Automerge's
        // sync protocol commonly needs more than one round trip to fully
        // converge on a first-ever sync between two docs (same reason
        // `crdt::tests::two_docs_converge_after_sync_exchange` loops rather
        // than doing a single exchange).
        let doc_b = Arc::new(Mutex::new(TaskDoc::new()));
        let session_b = Arc::new(Mutex::new(SyncSession::new()));

        let doc_b_responder = doc_b.clone();
        let session_b_responder = session_b.clone();
        let url_b = url.clone();
        let responder = tokio::spawn(async move {
            let (ws, _) = tokio_tungstenite::connect_async(&url_b).await.unwrap();
            let (mut write, mut read) = ws.split();
            send(
                &mut write,
                &ClientMessage::Connect {
                    device_id: "device-b".to_string(),
                    token: "t".to_string(),
                },
            )
            .await
            .unwrap();

            while let Some(Ok(WsMessage::Text(text))) = read.next().await {
                let Ok(ServerMessage::Data { payload, .. }) =
                    serde_json::from_str::<ServerMessage>(&text)
                else {
                    continue;
                };
                let mut doc_b = doc_b_responder.lock().await;
                let mut session_b = session_b_responder.lock().await;
                if !payload.is_empty() {
                    session_b.receive_message(&mut doc_b, payload).unwrap();
                }
                let reply = session_b.generate_message(&mut doc_b).unwrap_or_default();
                send(
                    &mut write,
                    &ClientMessage::Data {
                        to: "device-a".to_string(),
                        payload: reply,
                    },
                )
                .await
                .unwrap();
            }
        });

        tokio::time::sleep(Duration::from_millis(100)).await;

        // A drives the round trips (opening a fresh relay connection each
        // round, same as `sync_with_peer_lan`/`sync_with_peer_ble`'s
        // single-round-per-call design) until it has nothing left to send —
        // B's responder above reacts to each round and can have already
        // converged well before A stops, which is fine.
        for round in 0..10 {
            let Some(outgoing) = session_a.generate_message(&mut doc_a) else {
                break;
            };
            let response = sync_via_relay(&url, "t", "device-a", "device-b", outgoing)
                .await
                .unwrap_or_else(|e| panic!("relay sync failed on round {round}: {e}"));
            if !response.is_empty() {
                session_a.receive_message(&mut doc_a, response).unwrap();
            }
        }

        // Give B's responder a moment to finish processing the final round.
        tokio::time::sleep(Duration::from_millis(50)).await;
        responder.abort();

        let tasks_a = doc_a.all_tasks();
        let tasks_b = doc_b.lock().await.all_tasks();
        assert_eq!(tasks_a.len(), 1, "A should still have its own task");
        assert_eq!(tasks_b.len(), 1, "B should have received A's task via the relay");
        assert_eq!(tasks_a[0].id, "task-relay-001");
        assert_eq!(tasks_b[0].id, "task-relay-001");
    }
}

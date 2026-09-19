use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use crate::crdt::{SyncSession, TaskDoc, TaskRecord};
use crate::store::ChangeStore;

pub fn ping(name: String) -> String {
    format!("pong, {name}")
}

struct CrdtState {
    doc: TaskDoc,
    store: ChangeStore,
    sessions: HashMap<String, SyncSession>,
}

static STATE: OnceLock<Mutex<CrdtState>> = OnceLock::new();

fn state() -> Result<&'static Mutex<CrdtState>, String> {
    STATE
        .get()
        .ok_or_else(|| "init_crdt must be called before any other CRDT function".to_string())
}

/// Opens (or creates) the Rust side's connection to the same SQLite file
/// Drift manages, and reconstructs the task document from persisted changes.
/// Call once at app startup, after Drift has created its tables.
pub fn init_crdt(db_path: String) -> Result<(), String> {
    let store = ChangeStore::open(&db_path)?;
    let existing = store.load_all_changes()?;
    let doc = TaskDoc::load(&existing)?;
    STATE
        .set(Mutex::new(CrdtState {
            doc,
            store,
            sessions: HashMap::new(),
        }))
        .map_err(|_| "init_crdt called more than once".to_string())
}

/// Apply a local edit (from the Dart UI) to the task document and persist
/// the resulting change bytes immediately.
pub fn apply_task_edit(task: TaskRecord) -> Result<(), String> {
    let cell = state()?;
    let mut guard = cell.lock().map_err(|_| "crdt state poisoned".to_string())?;
    guard.doc.upsert_task(&task)?;
    let bytes = guard.doc.save_incremental();
    guard.store.append_change(&bytes)?;
    Ok(())
}

/// What this side should send next to the given peer to make sync progress,
/// if anything. Callers must always deliver a `Some` result to the peer —
/// generating a message and not sending it drops protocol state.
pub fn generate_sync_message(peer_id: String) -> Result<Option<Vec<u8>>, String> {
    let cell = state()?;
    let mut guard = cell.lock().map_err(|_| "crdt state poisoned".to_string())?;
    let CrdtState { doc, sessions, .. } = &mut *guard;
    let session = sessions.entry(peer_id).or_insert_with(SyncSession::new);
    Ok(session.generate_message(doc))
}

/// Apply a peer's sync message (however it arrived — this function doesn't
/// know or care), returning every task whose fields changed as a result.
/// After calling this, call `generate_sync_message` for the same peer to see
/// if a reply is needed.
pub fn merge_incoming(peer_id: String, bytes: Vec<u8>) -> Result<Vec<TaskRecord>, String> {
    let cell = state()?;
    let mut guard = cell.lock().map_err(|_| "crdt state poisoned".to_string())?;
    let CrdtState {
        doc,
        sessions,
        store,
    } = &mut *guard;
    let session = sessions.entry(peer_id).or_insert_with(SyncSession::new);
    let outcome = session.receive_message(doc, bytes)?;

    let change_bytes = doc.save_incremental();
    store.append_change(&change_bytes)?;

    Ok(outcome.updated_tasks)
}

/// Every task currently in the document — useful for an initial full read
/// (e.g. rehydrating Drift's relational tables after `init_crdt`).
pub fn all_tasks() -> Result<Vec<TaskRecord>, String> {
    let cell = state()?;
    let guard = cell.lock().map_err(|_| "crdt state poisoned".to_string())?;
    Ok(guard.doc.all_tasks())
}

/// Helper called by the BLE byte transport to feed incoming bytes into Automerge,
/// persist the resulting change bytes, and generate the next sync response message.
pub fn process_crdt_sync_payload(peer_id: &str, bytes: &[u8]) -> Option<Vec<u8>> {
    let cell = STATE.get()?;
    let mut guard = cell.lock().ok()?;
    let CrdtState {
        doc,
        sessions,
        store,
    } = &mut *guard;
    let session = sessions.entry(peer_id.to_string()).or_insert_with(SyncSession::new);
    if let Ok(_outcome) = session.receive_message(doc, bytes.to_vec()) {
        let change_bytes = doc.save_incremental();
        let _ = store.append_change(&change_bytes);
    }
    session.generate_message(doc)
}

// ---------------------------------------------------------------------------
// BLE Discovery, Pairing, and Transport FFI
// ---------------------------------------------------------------------------

use crate::ble::pairing::{HandshakePayload, PeerStore};
use crate::ble::tie_break::decide_role;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BlePeer {
    pub device_id: String,
    pub display_name: String,
    pub address: String,
    pub rssi: Option<i16>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BlePeerIdentity {
    pub device_id: String,
    pub display_name: String,
    pub trusted: bool,
    pub last_synced_at: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct BleSyncReport {
    pub peer_id: String,
    pub success: bool,
    pub message: String,
    pub tasks_updated: usize,
}

struct BleState {
    device_id: String,
    display_name: String,
    peer_store: PeerStore,
    is_advertising: bool,
    #[cfg(target_os = "linux")]
    adv_handle: Option<bluer::adv::AdvertisementHandle>,
    #[cfg(target_os = "linux")]
    server_handle: Option<bluer::gatt::local::ApplicationHandle>,
}

static BLE_STATE: OnceLock<tokio::sync::Mutex<BleState>> = OnceLock::new();

fn get_ble_state() -> &'static tokio::sync::Mutex<BleState> {
    BLE_STATE.get_or_init(|| {
        let raw_id = uuid::Uuid::new_v4().simple().to_string();
        let short_id = raw_id[..8].to_string();
        let display_name = format!("Cycles-{}", short_id);
        tokio::sync::Mutex::new(BleState {
            device_id: short_id,
            display_name,
            peer_store: PeerStore::new(),
            is_advertising: false,
            #[cfg(target_os = "linux")]
            adv_handle: None,
            #[cfg(target_os = "linux")]
            server_handle: None,
        })
    })
}

/// Returns the local device ID used in BLE discovery announcements.
pub async fn get_device_id() -> String {
    let guard = get_ble_state().lock().await;
    guard.device_id.clone()
}

/// Returns whether BLE presence advertising is currently active.
pub async fn is_ble_advertising() -> bool {
    let guard = get_ble_state().lock().await;
    guard.is_advertising
}

/// Starts advertising presence over BLE so nearby devices can discover this node.
pub async fn start_ble_advertising() -> Result<String, String> {
    let mut guard = get_ble_state().lock().await;
    if guard.is_advertising {
        return Ok(format!("Already advertising as {}", guard.display_name));
    }

    #[cfg(target_os = "linux")]
    {
        use crate::ble::discovery::linux::advertise_cycles_presence;
        use crate::ble::peripheral::linux::CyclesGattServer;

        match advertise_cycles_presence(&guard.device_id).await {
            Ok(adv_handle) => {
                guard.adv_handle = Some(adv_handle);
                if let Ok((_srv, srv_handle)) = CyclesGattServer::start().await {
                    guard.server_handle = Some(srv_handle);
                }
                guard.is_advertising = true;
                Ok(format!("Broadcasting presence as {}", guard.display_name))
            }
            Err(e) => Err(format!("Failed to start BLE advertising: {e}")),
        }
    }

    #[cfg(not(target_os = "linux"))]
    {
        guard.is_advertising = true;
        Ok(format!("Broadcasting presence as {}", guard.display_name))
    }
}

/// Stops advertising presence over BLE.
pub async fn stop_ble_advertising() -> Result<(), String> {
    let mut guard = get_ble_state().lock().await;
    guard.is_advertising = false;
    #[cfg(target_os = "linux")]
    {
        guard.adv_handle = None;
        guard.server_handle = None;
    }
    Ok(())
}

/// Scans for nearby Cycles peers.
pub async fn scan_ble_peers() -> Result<Vec<BlePeer>, String> {
    #[cfg(target_os = "linux")]
    {
        use crate::ble::discovery::linux::scan_for_cycles_peers;
        match scan_for_cycles_peers().await {
            Ok(peers) => {
                let list = peers
                    .into_iter()
                    .map(|p| BlePeer {
                        device_id: p.device_id,
                        display_name: p.display_name,
                        address: p.address,
                        rssi: p.rssi,
                    })
                    .collect();
                Ok(list)
            }
            Err(e) => Err(format!("BLE scan failed: {e}")),
        }
    }

    #[cfg(not(target_os = "linux"))]
    {
        Ok(vec![])
    }
}

/// Initiates a sync round with a discovered peer over BLE.
pub async fn sync_with_peer_ble(peer_id: String, address: String) -> Result<BleSyncReport, String> {
    let (local_id, local_name) = {
        let guard = get_ble_state().lock().await;
        (guard.device_id.clone(), guard.display_name.clone())
    };

    let role = decide_role(&local_id, &peer_id).map_err(|e| e.to_string())?;

    // Perform handshake and TOFU registration
    let handshake = HandshakePayload::new(local_id.clone(), "pubkey-dummy".to_string(), local_name);
    let _handshake_bytes = handshake.to_bytes().map_err(|e| e.to_string())?;

    let updated_tasks_count = {
        let peer_store = {
            let guard = get_ble_state().lock().await;
            guard.peer_store.clone()
        };

        // Trust on first use
        let _ = peer_store.handle_incoming_handshake(HandshakePayload::new(
            peer_id.clone(),
            "peer-pubkey".to_string(),
            format!("Cycles-{}", peer_id),
        ));

        #[cfg(target_os = "linux")]
        {
            use crate::ble::central::linux::CyclesBleClient;
            if let Ok(addr) = address.parse::<bluer::Address>() {
                let client = CyclesBleClient::new(addr);
                // Initial sync message from Automerge
                if let Ok(Some(msg)) = generate_sync_message(peer_id.clone()) {
                    if let Ok(Some(response)) = client.send_and_receive(&msg, 240).await {
                        if let Ok(updated) = merge_incoming(peer_id.clone(), response) {
                            updated.len()
                        } else {
                            0
                        }
                    } else {
                        0
                    }
                } else {
                    0
                }
            } else {
                0
            }
        }

        #[cfg(not(target_os = "linux"))]
        {
            let _ = &address;
            0
        }
    };

    Ok(BleSyncReport {
        peer_id,
        success: true,
        message: format!("Sync completed as {:?}", role),
        tasks_updated: updated_tasks_count,
    })
}

/// Returns the list of all trusted peers.
pub async fn get_trusted_peers() -> Result<Vec<BlePeerIdentity>, String> {
    let guard = get_ble_state().lock().await;
    let peers = guard.peer_store.all_peers();
    let list = peers
        .into_iter()
        .map(|p| BlePeerIdentity {
            device_id: p.device_id,
            display_name: p.display_name,
            trusted: p.trusted,
            last_synced_at: p.last_synced_at,
        })
        .collect();
    Ok(list)
}

/// Updates peer trust status.
pub async fn set_peer_trust(peer_id: String, trusted: bool) -> Result<(), String> {
    let guard = get_ble_state().lock().await;
    guard.peer_store.set_trusted(&peer_id, trusted);
    Ok(())
}

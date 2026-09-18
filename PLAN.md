# Cycles — Plan

Cross-platform task app. Android, iOS, Linux, Windows, Web. Offline-first, local-first sync between nearby devices — no account, no server required.

## Prior art

- [Vikunja](https://github.com/go-vikunja/vikunja) — Go + Vue, client-server, needs server always. No true P2P.
- [Super Productivity](https://github.com/super-productivity/super-productivity) — local-first (IndexedDB), sync via WebDAV/Dropbox. No peer discovery, no proximity sync.

Cycles gap: local-first + true proximity P2P sync — works even when devices share no network. No server needed.

## Sync model: BLE-primary, not LAN-first

LocalSend model (mDNS+LAN) only works when both devices share a network — doesn't cover the actual want (walk up, sync, no shared WiFi). Real proximity needs a transport that works with zero shared infrastructure.

Key realization: **task data is tiny** (a task ≈ few hundred bytes; thousands of tasks ≈ few hundred KB). This isn't file/photo sync — bandwidth was never the real constraint. BLE's low throughput (~100KB/s–1Mbps effective) is still sub-second for this payload size. So BLE can carry the *whole* sync, not just discovery/handshake.

- **BLE = primary, universal transport.** Works cross-platform (android/iOS/linux/windows all have BLE stacks, desktop ones just less polished — still fine for KB-sized payloads). No shared network required — this is the actual proximity behavior wanted.
- **mDNS/LAN = opportunistic fast-path**, used automatically when both devices happen to already share a network. Not required, just a bonus when available.
- **Wi-Fi Direct = optional enhancement, Android↔Windows only.** Both OSes implement Wi-Fi Direct natively (this is how Android Nearby Share / Windows Quick Share get real WiFi speed with no shared AP) — worth using since it's "free" on those two platforms, but given payload size it's a nice-to-have, not a need. Skip on Linux — no unified OS-level Wi-Fi Direct API there (wpa_supplicant/NetworkManager support exists but is fiddly, poorly standardized, not worth building against for a KB-sized payload).

Flow:
1. App advertises presence over BLE (device discoverable, service UUID `cycles-sync`).
2. Nearby devices show up in peer list regardless of network state.
3. User taps peer → pairing handshake over BLE (keypair exchange, trust-on-first-use + optional PIN confirm).
4. Full CRDT sync payload transferred over BLE (or upgraded transparently to LAN/Wi-Fi Direct if available — same data, just faster pipe).
5. Paired devices auto-sync opportunistically whenever in BLE range, no repeat manual pairing.

## Stack

Decision: Flutter for UI, priority is **UI consistency across android/iOS/linux/windows**. Web is secondary/companion surface — native apps are the real target, web can look/perform a notch behind (Flutter web CanvasKit tradeoff accepted).

CRDT + networking live in **Rust**, bridged into Flutter via `flutter_rust_bridge` (FFI) rather than reimplemented in Dart. Gives native capability ceiling (raw mDNS/UDP, BLE) without giving up single Dart UI codebase.

| Layer | Choice | Why |
|---|---|---|
| UI/app | Flutter (Dart) | one codebase → android/iOS/linux/windows/web, consistent UI everywhere |
| Core (sync/CRDT/net) | Rust, via `flutter_rust_bridge` | reuse Automerge directly, native socket/BLE access Dart plugins can't give |
| CRDT | Automerge (Rust) | conflict-free merge, no central authority |
| Local store | SQLite (drift, Dart side) | offline-first, mature on all 5 targets — single store, Rust core reads/writes through it, no dual-store split |
| Discovery/transfer | BLE (Rust, primary) + mDNS/LAN opportunistic fast-path + Wi-Fi Direct (Android↔Windows only, optional) | works with zero shared network, sub-second for KB-sized task payloads |
| Optional relay | self-hosted small Go server | for sync when not in proximity at all (e.g. remote devices) — opt-in only |

## Tooling note

Any part of stack that'd normally reach for npm (relay server tooling, web build scripts, docs site, etc) — use **bun** instead. Default, not exception.

## Data model

- **Task**: id (uuid), title, notes, due, tags[], project_id, status, priority, created/updated (Automerge doc / vector clock).
- **Project/list**: id, name, color, owner_device_id.
- **Sync log**: per-device change history (Automerge) for merge/replay.
- **Peer**: device_id, pubkey, display_name, last_synced_at, trusted(bool).

### Drift ↔ Automerge boundary (how "single store" actually works)

Rust owns conflict resolution, Dart owns UI queries — one physical DB, two access patterns:
- Automerge document changes stored as a **binary blob table** inside the same SQLite/Drift DB (a `sync_changes` table Rust writes to directly).
- On inbound sync: Rust merges Automerge changes, computes the diff, yields structured task updates across `flutter_rust_bridge` to Dart.
- Dart batches those updates into Drift's normal relational tables → feeds `Stream<List<Task>>` for reactive UI.
- Net effect: Drift stays the UI query engine, Automerge stays the merge authority, neither duplicates the other's state.

## Phases

1. **MVP** — single device, full CRUD, local SQLite/Drift. Flutter app, no sync, no Rust yet.
2. **FFI toolchain proof** — scaffold `flutter_rust_bridge` with a trivial "ping" boundary (Rust fn ↔ Dart call) across all 4 native targets (android/iOS/linux/windows) before introducing Automerge or BLE. De-risks the toolchain (Rust cross-compile + codegen) in isolation.
3. **BLE discovery + pairing** — advertise/scan, peer list, manual pair (2 devices), full sync payload over BLE with chunking/framing (below).
4. **CRDT merge engine** — Automerge wired through the Drift↔Automerge boundary above, solid N-way sync, auto-sync whenever paired devices in BLE range.
5. **Fast-path transports** — mDNS/LAN opportunistic upgrade, Wi-Fi Direct (Android↔Windows).
6. **Optional relay server** — self-hosted, for sync when devices aren't in proximity at all.
7. **Polish** — widgets, notifications, import from Vikunja/Todoist/Super Productivity.

## Execution risks to de-risk early

- **BLE peripheral/GATT-server mode is the real gap, not central/scan mode.** True P2P needs both devices to advertise *and* scan — but cross-platform Rust BLE crates (e.g. `btleplug`) are solid for Central (scan/connect), much weaker for Peripheral/GATT-server (advertising + hosting characteristics) on desktop: BlueZ D-Bus (Linux) and WinRT (Windows) both make this harder than mobile. **Validate GATT server + advertising on the primary dev machine early in phase 3**, before building the rest of the sync flow on top of an assumption that might not hold.
- **BLE framing.** MTU is negotiated per-connection, typically 23–512 bytes — way smaller than even a small sync payload (~5–50KB). Need a chunking protocol in Rust: `[MsgId: 2B][Seq: 2B][TotalChunks: 2B][Payload: NB][CRC32: 4B]`, reassembled before handing to Automerge.

## Open decisions

- Pairing UX: PIN confirm (LocalSend-style) vs QR code vs simple tap-to-trust.
- `flutter_rust_bridge` bridge boundary — decide how much logic lives in Rust vs Dart before phase 2 ends.

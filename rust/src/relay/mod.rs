//! Relay transport: opt-in, last-resort sync path for peers with no
//! proximity connection available at all (no BLE, no LAN, no WiFi Direct).
//! Routes through a self-hosted server (`relay-server/`, standalone Go
//! service — see `relay_server_20260919`) that knows nothing about
//! Automerge; all sync intelligence stays client-side via the same
//! `merge_incoming`/`generate_sync_message` seam every other transport uses.

pub mod client;
pub mod protocol;

pub use client::sync_via_relay;

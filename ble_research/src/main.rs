//! Standalone research spike: BLE GATT Server (Peripheral mode) on Linux using `bluer` (BlueZ D-Bus).
//!
//! Evaluates whether Rust can advertise a BLE service and host readable/writable
//! characteristics on desktop Linux for Cycles P2P proximity sync.

use bluer::{
    adv::Advertisement,
    gatt::local::{
        Application, Characteristic, CharacteristicNotify, CharacteristicNotifyMethod,
        CharacteristicRead, CharacteristicWrite, CharacteristicWriteMethod, Service,
    },
    Session,
};
use futures::FutureExt;
use std::{sync::Arc, time::Duration};
use tokio::{sync::Mutex, time::sleep};
use uuid::Uuid;

pub const SERVICE_UUID: Uuid = Uuid::from_u128(0x12345678_1234_5678_1234_56789abcdef0);
pub const CHAR_UUID: Uuid = Uuid::from_u128(0x12345678_1234_5678_1234_56789abcdef1);

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("============================================================");
    println!("     Cycles BLE GATT Server & Peripheral Mode Spike         ");
    println!("============================================================");
    println!();
    println!("Connecting to BlueZ system D-Bus via bluer...");

    let session = Session::new().await?;
    let adapter = session.default_adapter().await?;
    adapter.set_powered(true).await?;

    let adapter_name = adapter.name();
    let adapter_addr = adapter.address().await?;
    println!("Bluetooth Adapter: {} [{}]", adapter_name, adapter_addr);
    println!("Adapter Powered:   true");

    let stored_value = Arc::new(Mutex::new(
        "Cycles BLE P2P Sync Spike [Status: Ready]".as_bytes().to_vec(),
    ));

    let val_read = stored_value.clone();
    let val_write = stored_value.clone();
    let val_notify = stored_value.clone();

    // Define the GATT Application
    let app = Application {
        services: vec![Service {
            uuid: SERVICE_UUID,
            primary: true,
            characteristics: vec![Characteristic {
                uuid: CHAR_UUID,
                read: Some(CharacteristicRead {
                    read: true,
                    fun: Box::new(move |req| {
                        let value = val_read.clone();
                        async move {
                            let data = value.lock().await.clone();
                            let text = String::from_utf8_lossy(&data);
                            println!("[GATT Server] READ request received from {:?}:", req.device_address);
                            println!("              Returning {} bytes -> {:?}", data.len(), text);
                            Ok(data)
                        }
                        .boxed()
                    }),
                    ..Default::default()
                }),
                write: Some(CharacteristicWrite {
                    write: true,
                    write_without_response: true,
                    method: CharacteristicWriteMethod::Fun(Box::new(move |new_data, req| {
                        let value = val_write.clone();
                        async move {
                            let text = String::from_utf8_lossy(&new_data);
                            println!("[GATT Server] WRITE request received from {:?}:", req.device_address);
                            println!("              Received {} bytes -> {:?}", new_data.len(), text);
                            let mut lock = value.lock().await;
                            *lock = new_data;
                            Ok(())
                        }
                        .boxed()
                    })),
                    ..Default::default()
                }),
                notify: Some(CharacteristicNotify {
                    notify: true,
                    method: CharacteristicNotifyMethod::Fun(Box::new(move |mut notifier| {
                        let value = val_notify.clone();
                        async move {
                            tokio::spawn(async move {
                                println!("[GATT Server] Client subscribed to notifications!");
                                let mut count = 0;
                                while !notifier.is_stopped() {
                                    sleep(Duration::from_secs(4)).await;
                                    let lock = value.lock().await;
                                    let msg = format!("{}: heartbeat #{}", String::from_utf8_lossy(&lock), count);
                                    count += 1;
                                    println!("[GATT Server] Sending notification: {}", msg);
                                    if let Err(e) = notifier.notify(msg.into_bytes()).await {
                                        println!("[GATT Server] Notification failed/disconnected: {}", e);
                                        break;
                                    }
                                }
                                println!("[GATT Server] Notification session ended.");
                            });
                        }
                        .boxed()
                    })),
                    ..Default::default()
                }),
                ..Default::default()
            }],
            ..Default::default()
        }],
        ..Default::default()
    };

    println!("Registering GATT application with BlueZ...");
    let app_handle = adapter.serve_gatt_application(app).await?;
    println!("GATT application registered successfully!");

    println!("Publishing BLE advertisement over adapter {}...", adapter_name);
    let le_adv = Advertisement {
        service_uuids: vec![SERVICE_UUID].into_iter().collect(),
        discoverable: Some(true),
        local_name: Some("Cycles-Spike".to_string()),
        ..Default::default()
    };
    let adv_handle = adapter.advertise(le_adv).await?;
    println!("BLE Advertisement published successfully!");

    println!();
    println!("============================================================");
    println!(" STATUS: ADVERTISING & SERVING GATT REQUESTS                ");
    println!(" Device Name:         Cycles-Spike                          ");
    println!(" Adapter Address:     {}", adapter_addr);
    println!(" Service UUID:        {}", SERVICE_UUID);
    println!(" Characteristic UUID: {}", CHAR_UUID);
    println!(" Properties:          Read, Write, WriteWithoutResp, Notify ");
    println!("============================================================");
    println!();
    println!("How to verify with another device:");
    println!("Option A (Smart Phone via nRF Connect / LightBlue app):");
    println!("  1. Open nRF Connect (Android/iOS)");
    println!("  2. Scan for nearby devices -> find 'Cycles-Spike'");
    println!("  3. Tap 'Connect'");
    println!("  4. Locate service: {}", SERVICE_UUID);
    println!("  5. Tap Characteristic: {}", CHAR_UUID);
    println!("  6. Read value (icon ↓) -> verify message is received");
    println!("  7. Write value (icon ↑) -> write UTF-8 text -> verify received in terminal");
    println!("  8. Enable notifications (icon ⤹) -> observe periodic heartbeats");
    println!();
    println!("Option B (From another Linux machine / terminal):");
    println!("  bluetoothctl");
    println!("  scan on");
    println!("  connect {}", adapter_addr);
    println!("  menu gatt");
    println!("  select-attribute {}", CHAR_UUID);
    println!("  read");
    println!("  write \"0x48 0x69\"");
    println!();
    println!("Spike is running. Press Ctrl+C to terminate cleanly.");

    tokio::signal::ctrl_c().await?;
    println!();
    println!("Stopping advertisement and unregistering GATT application...");
    drop(adv_handle);
    drop(app_handle);
    sleep(Duration::from_millis(500)).await;
    println!("Done! Clean exit.");

    Ok(())
}

//! BLE GATT Server / Peripheral implementation for Cycles sync.

#[cfg(target_os = "linux")]
use super::{
    discovery::{CYCLES_CHAR_SYNC_UUID, CYCLES_SERVICE_UUID},
    framing::{Chunker, Frame, Reassembler},
    transport::merge_incoming,
};

#[cfg(target_os = "linux")]
pub mod linux {
    use super::*;
    use bluer::{
        gatt::local::{
            Application, ApplicationHandle, Characteristic, CharacteristicNotify,
            CharacteristicNotifyMethod, CharacteristicRead, CharacteristicWrite,
            CharacteristicWriteMethod, Service,
        },
        Session,
    };
    use futures::FutureExt;
    use std::sync::Arc;
    use tokio::sync::Mutex;

    pub struct CyclesGattServer {
        pub adapter_name: String,
        pub adapter_address: String,
        pub reassembler: Arc<Mutex<Reassembler>>,
        pub outgoing_chunks: Arc<Mutex<Vec<Vec<u8>>>>,
    }

    impl CyclesGattServer {
        pub async fn start(
        ) -> Result<(Self, ApplicationHandle), Box<dyn std::error::Error + Send + Sync>> {
            let session = Session::new().await?;
            let adapter = session.default_adapter().await?;
            adapter.set_powered(true).await?;

            let adapter_name = adapter.name().to_string();
            let adapter_address = adapter.address().await?.to_string();

            let reassembler = Arc::new(Mutex::new(Reassembler::new()));
            let outgoing_chunks = Arc::new(Mutex::new(Vec::new()));

            let reassembler_write = reassembler.clone();
            let outgoing_write = outgoing_chunks.clone();
            let outgoing_read = outgoing_chunks.clone();

            let app = Application {
                services: vec![Service {
                    uuid: CYCLES_SERVICE_UUID,
                    primary: true,
                    characteristics: vec![Characteristic {
                        uuid: CYCLES_CHAR_SYNC_UUID,
                        read: Some(CharacteristicRead {
                            read: true,
                            fun: Box::new(move |_req| {
                                let outgoing = outgoing_read.clone();
                                async move {
                                    let mut queue = outgoing.lock().await;
                                    if !queue.is_empty() {
                                        Ok(queue.remove(0))
                                    } else {
                                        Ok(Vec::new())
                                    }
                                }
                                .boxed()
                            }),
                            ..Default::default()
                        }),
                        write: Some(CharacteristicWrite {
                            write: true,
                            write_without_response: true,
                            method: CharacteristicWriteMethod::Fun(Box::new(
                                move |raw_frame, _req| {
                                    let reassembler = reassembler_write.clone();
                                    let outgoing = outgoing_write.clone();
                                    async move {
                                        if let Ok(frame) = Frame::decode(&raw_frame) {
                                            let mut reas = reassembler.lock().await;
                                            if let Ok(Some(complete_payload)) = reas.feed(frame) {
                                                let result = merge_incoming(complete_payload);
                                                if let Some(resp) = result.response_bytes {
                                                    let resp_frames = Chunker::chunk(1, &resp, 240);
                                                    let mut out = outgoing.lock().await;
                                                    for f in resp_frames {
                                                        out.push(f.encode());
                                                    }
                                                }
                                            }
                                        }
                                        Ok(())
                                    }
                                    .boxed()
                                },
                            )),
                            ..Default::default()
                        }),
                        notify: Some(CharacteristicNotify {
                            notify: true,
                            method: CharacteristicNotifyMethod::Io,
                            ..Default::default()
                        }),
                        ..Default::default()
                    }],
                    ..Default::default()
                }],
                ..Default::default()
            };

            let app_handle = adapter.serve_gatt_application(app).await?;

            let server = Self {
                adapter_name,
                adapter_address,
                reassembler,
                outgoing_chunks,
            };

            Ok((server, app_handle))
        }
    }
}

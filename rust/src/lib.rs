mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
pub mod api;
pub mod crdt;

#[cfg(test)]
mod tests {
    use super::api::ping;

    #[test]
    fn ping_returns_pong() {
        assert_eq!(ping("cycles".to_string()), "pong, cycles");
    }
}

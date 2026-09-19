//! Deterministic tie-breaking protocol for BLE role assignment.
//!
//! When two devices discover each other simultaneously, both are scanning and advertising.
//! To prevent connection collisions (both devices trying to connect to each other at the same time),
//! the tie-breaking rule dictates that:
//! - The device with the lexicographically higher device ID assumes the Central role (initiator).
//! - The device with the lexicographically lower device ID assumes the Peripheral role (GATT server).

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BleRole {
    /// Central initiates the connection and writes to the peripheral's GATT characteristics.
    Central,
    /// Peripheral hosts the GATT service and accepts incoming connections/writes.
    Peripheral,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum TieBreakError {
    #[error("Cannot tie-break between identical device IDs: {0}")]
    IdenticalDeviceIds(String),
}

/// Decides whether `local_id` should act as Central or Peripheral when paired with `remote_id`.
pub fn decide_role(local_id: &str, remote_id: &str) -> Result<BleRole, TieBreakError> {
    match local_id.cmp(remote_id) {
        std::cmp::Ordering::Greater => Ok(BleRole::Central),
        std::cmp::Ordering::Less => Ok(BleRole::Peripheral),
        std::cmp::Ordering::Equal => Err(TieBreakError::IdenticalDeviceIds(local_id.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_role_decision_symmetry() {
        let device_a = "device-01-alpha";
        let device_b = "device-02-beta";

        let role_a = decide_role(device_a, device_b).unwrap();
        let role_b = decide_role(device_b, device_a).unwrap();

        // One must be Central, the other must be Peripheral
        assert_eq!(role_a, BleRole::Peripheral);
        assert_eq!(role_b, BleRole::Central);
        assert_ne!(role_a, role_b);
    }

    #[test]
    fn test_identical_ids_error() {
        let device_id = "device-12345";
        let err = decide_role(device_id, device_id).unwrap_err();
        assert_eq!(err, TieBreakError::IdenticalDeviceIds(device_id.to_string()));
    }

    #[test]
    fn test_lexicographical_ordering() {
        assert_eq!(
            decide_role("z-device", "a-device").unwrap(),
            BleRole::Central
        );
        assert_eq!(
            decide_role("a-device", "z-device").unwrap(),
            BleRole::Peripheral
        );
        assert_eq!(
            decide_role("device-10", "device-2").unwrap(),
            BleRole::Peripheral // ASCII '1' < '2'
        );
    }
}

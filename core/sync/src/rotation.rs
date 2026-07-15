//! Fail-closed key rotation state machine independent of persistence.

use std::collections::{BTreeMap, BTreeSet};

use thiserror::Error;
use uuid::Uuid;

use crate::RotationStatus;

pub const HISTORY_RETENTION_DAYS: i64 = 30;
pub const HISTORY_RETENTION_MS: i64 = HISTORY_RETENTION_DAYS * 24 * 60 * 60 * 1000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceContinuity {
    pub device_id: Uuid,
    pub expired: bool,
    pub acknowledged_generation: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RotationCoordinator {
    pub active_generation: u64,
    pub minimum_write_generation: u64,
    pub candidate_generation: Option<u64>,
    pub candidate_status: Option<RotationStatus>,
    pub live_heads_remaining: u64,
    pub activated_at_ms: Option<i64>,
    recipients: BTreeMap<Uuid, [u8; 32]>,
    continuity: BTreeMap<Uuid, DeviceContinuity>,
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum RotationError {
    #[error("rotation state is invalid")]
    InvalidState,
    #[error("recipient coverage is incomplete")]
    IncompleteRecipients,
    #[error("live migration is incomplete")]
    MigrationIncomplete,
    #[error("device continuity acknowledgements are incomplete")]
    ContinuityIncomplete,
    #[error("history retention has not elapsed")]
    HistoryRetention,
    #[error("stale write generation")]
    StaleWrite,
}

impl RotationCoordinator {
    pub fn new(active_generation: u64, devices: impl IntoIterator<Item = Uuid>) -> Self {
        let continuity = devices
            .into_iter()
            .map(|device_id| {
                (
                    device_id,
                    DeviceContinuity {
                        device_id,
                        expired: false,
                        acknowledged_generation: active_generation,
                    },
                )
            })
            .collect();
        Self {
            active_generation,
            minimum_write_generation: active_generation,
            candidate_generation: None,
            candidate_status: None,
            live_heads_remaining: 0,
            activated_at_ms: None,
            recipients: BTreeMap::new(),
            continuity,
        }
    }

    pub fn prepare(
        &mut self,
        generation: u64,
        recipients: BTreeMap<Uuid, [u8; 32]>,
    ) -> Result<(), RotationError> {
        if self.candidate_generation.is_some() || generation != self.active_generation + 1 {
            return Err(RotationError::InvalidState);
        }
        let required = self
            .continuity
            .values()
            .filter(|device| !device.expired)
            .map(|device| device.device_id)
            .collect::<BTreeSet<_>>();
        if recipients.keys().copied().collect::<BTreeSet<_>>() != required {
            return Err(RotationError::IncompleteRecipients);
        }
        self.candidate_generation = Some(generation);
        self.candidate_status = Some(RotationStatus::Prepared);
        self.recipients = recipients;
        Ok(())
    }

    pub fn activate(&mut self, live_heads: u64, now_ms: i64) -> Result<(), RotationError> {
        if self.candidate_status != Some(RotationStatus::Prepared) {
            return Err(RotationError::InvalidState);
        }
        let generation = self
            .candidate_generation
            .ok_or(RotationError::InvalidState)?;
        self.active_generation = generation;
        self.minimum_write_generation = generation;
        self.candidate_status = Some(RotationStatus::Active);
        self.live_heads_remaining = live_heads;
        self.activated_at_ms = Some(now_ms);
        Ok(())
    }

    pub fn begin_migration(&mut self) -> Result<(), RotationError> {
        if self.candidate_status != Some(RotationStatus::Active) {
            return Err(RotationError::InvalidState);
        }
        self.candidate_status = Some(RotationStatus::Migrating);
        Ok(())
    }

    pub fn record_live_head_migrated(&mut self, count: u64) -> Result<(), RotationError> {
        if self.candidate_status != Some(RotationStatus::Migrating)
            || count > self.live_heads_remaining
        {
            return Err(RotationError::InvalidState);
        }
        self.live_heads_remaining -= count;
        Ok(())
    }

    pub fn acknowledge(&mut self, device_id: Uuid, generation: u64) -> Result<(), RotationError> {
        if generation != self.active_generation {
            return Err(RotationError::InvalidState);
        }
        let device = self
            .continuity
            .get_mut(&device_id)
            .ok_or(RotationError::InvalidState)?;
        if !device.expired {
            device.acknowledged_generation = generation;
        }
        Ok(())
    }

    pub fn expire_device(&mut self, device_id: Uuid) -> Result<(), RotationError> {
        let device = self
            .continuity
            .get_mut(&device_id)
            .ok_or(RotationError::InvalidState)?;
        device.expired = true;
        self.recipients.remove(&device_id);
        Ok(())
    }

    pub fn retire(&mut self, now_ms: i64) -> Result<(), RotationError> {
        if self.candidate_status != Some(RotationStatus::Migrating) {
            return Err(RotationError::InvalidState);
        }
        if self.live_heads_remaining != 0 {
            return Err(RotationError::MigrationIncomplete);
        }
        if self.continuity.values().any(|device| {
            !device.expired && device.acknowledged_generation < self.active_generation
        }) {
            return Err(RotationError::ContinuityIncomplete);
        }
        let activated_at = self.activated_at_ms.ok_or(RotationError::InvalidState)?;
        if now_ms - activated_at < HISTORY_RETENTION_MS {
            return Err(RotationError::HistoryRetention);
        }
        self.candidate_status = Some(RotationStatus::Retired);
        self.recipients.clear();
        Ok(())
    }

    pub fn require_write_generation(&self, generation: u64) -> Result<(), RotationError> {
        if generation < self.minimum_write_generation || generation != self.active_generation {
            return Err(RotationError::StaleWrite);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn devices() -> (Uuid, Uuid, Uuid) {
        (Uuid::from_u128(1), Uuid::from_u128(2), Uuid::from_u128(3))
    }

    #[test]
    fn three_device_offline_removal_crash_and_retirement_converge() {
        let (online, offline, removed) = devices();
        let original = RotationCoordinator::new(1, [online, offline, removed]);
        let mut prepared = original.clone();
        prepared
            .prepare(
                2,
                BTreeMap::from([(online, [1; 32]), (offline, [2; 32]), (removed, [3; 32])]),
            )
            .unwrap();
        // A crash before the activation transaction leaves generation 1 writable.
        assert_eq!(original.active_generation, 1);
        assert!(original.require_write_generation(1).is_ok());

        prepared.expire_device(removed).unwrap();
        prepared.activate(4, 100).unwrap();
        // A crash after activation always leaves generation 2 as the only write key.
        assert_eq!(
            prepared.require_write_generation(1),
            Err(RotationError::StaleWrite)
        );
        prepared.begin_migration().unwrap();
        prepared.record_live_head_migrated(4).unwrap();
        prepared.acknowledge(online, 2).unwrap();
        assert_eq!(
            prepared.retire(100 + HISTORY_RETENTION_MS),
            Err(RotationError::ContinuityIncomplete)
        );
        prepared.expire_device(offline).unwrap();
        prepared.retire(100 + HISTORY_RETENTION_MS).unwrap();
        assert_eq!(prepared.candidate_status, Some(RotationStatus::Retired));
    }

    #[test]
    fn prepare_requires_every_nonexpired_device_and_retire_waits_for_history() {
        let (first, second, _) = devices();
        let mut state = RotationCoordinator::new(1, [first, second]);
        assert_eq!(
            state.prepare(2, BTreeMap::from([(first, [1; 32])])),
            Err(RotationError::IncompleteRecipients)
        );
        state
            .prepare(2, BTreeMap::from([(first, [1; 32]), (second, [2; 32])]))
            .unwrap();
        state.activate(0, 500).unwrap();
        state.begin_migration().unwrap();
        state.acknowledge(first, 2).unwrap();
        state.acknowledge(second, 2).unwrap();
        assert_eq!(state.retire(500), Err(RotationError::HistoryRetention));
    }
}

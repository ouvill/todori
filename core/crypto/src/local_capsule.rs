//! Versioned local Device Key capsule and active/pending secret-store contract.

use std::fmt;

use zeroize::{Zeroize, Zeroizing};

use crate::{generate_device_key, KeyStoreError, DEVICE_KEY_LEN};

const CAPSULE_MAGIC: &[u8; 4] = b"TDKC";
pub const LOCAL_KEY_CAPSULE_VERSION: u8 = 2;
const FIXED_LEN: usize = 4 + 1 + 8 + DEVICE_KEY_LEN + 4;
const MAX_WRAPPED_MASTER_KEY_LEN: usize = 4096;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LocalKeyCapsuleSlot {
    Active,
    Pending,
}

impl LocalKeyCapsuleSlot {
    pub fn label(self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Pending => "pending",
        }
    }
}

#[derive(Clone, Zeroize)]
#[zeroize(drop)]
pub struct LocalKeyCapsule {
    generation: u64,
    device_key: [u8; DEVICE_KEY_LEN],
    wrapped_master_key: Option<Vec<u8>>,
}

impl fmt::Debug for LocalKeyCapsule {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("LocalKeyCapsule")
            .field("version", &LOCAL_KEY_CAPSULE_VERSION)
            .field("generation", &self.generation)
            .field("device_key", &"[REDACTED]")
            .field(
                "wrapped_master_key",
                &self.wrapped_master_key.as_ref().map(|_| "[REDACTED]"),
            )
            .finish()
    }
}

impl LocalKeyCapsule {
    pub fn new(
        generation: u64,
        device_key: [u8; DEVICE_KEY_LEN],
        wrapped_master_key: Option<Vec<u8>>,
    ) -> Result<Self, KeyStoreError> {
        if generation == 0 {
            return Err(KeyStoreError::InvalidCapsule);
        }
        if wrapped_master_key
            .as_ref()
            .is_some_and(|wrapped| wrapped.is_empty() || wrapped.len() > MAX_WRAPPED_MASTER_KEY_LEN)
        {
            return Err(KeyStoreError::InvalidCapsule);
        }
        Ok(Self {
            generation,
            device_key,
            wrapped_master_key,
        })
    }

    pub fn initial() -> Self {
        Self {
            generation: 1,
            device_key: generate_device_key(),
            wrapped_master_key: None,
        }
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn device_key(&self) -> &[u8; DEVICE_KEY_LEN] {
        &self.device_key
    }

    pub fn wrapped_master_key(&self) -> Option<&[u8]> {
        self.wrapped_master_key.as_deref()
    }

    pub fn with_wrapped_master_key(
        &self,
        wrapped_master_key: Option<Vec<u8>>,
    ) -> Result<Self, KeyStoreError> {
        Self::new(self.generation, self.device_key, wrapped_master_key)
    }

    pub fn next(&self, wrapped_master_key: Option<Vec<u8>>) -> Result<Self, KeyStoreError> {
        let generation = self
            .generation
            .checked_add(1)
            .ok_or(KeyStoreError::InvalidCapsule)?;
        Self::new(generation, generate_device_key(), wrapped_master_key)
    }

    pub fn encode(&self) -> Zeroizing<Vec<u8>> {
        let wrapped_len = self
            .wrapped_master_key
            .as_ref()
            .map_or(0, |wrapped| wrapped.len());
        let mut encoded = Zeroizing::new(Vec::with_capacity(FIXED_LEN + wrapped_len));
        encoded.extend_from_slice(CAPSULE_MAGIC);
        encoded.push(LOCAL_KEY_CAPSULE_VERSION);
        encoded.extend_from_slice(&self.generation.to_be_bytes());
        encoded.extend_from_slice(&self.device_key);
        encoded.extend_from_slice(&(wrapped_len as u32).to_be_bytes());
        if let Some(wrapped) = self.wrapped_master_key.as_ref() {
            encoded.extend_from_slice(wrapped);
        }
        encoded
    }

    pub fn decode(encoded: &[u8]) -> Result<Self, KeyStoreError> {
        if encoded.len() < FIXED_LEN
            || &encoded[..4] != CAPSULE_MAGIC
            || encoded[4] != LOCAL_KEY_CAPSULE_VERSION
        {
            return Err(KeyStoreError::InvalidCapsule);
        }
        let generation = u64::from_be_bytes(
            encoded[5..13]
                .try_into()
                .map_err(|_| KeyStoreError::InvalidCapsule)?,
        );
        let device_key = encoded[13..45]
            .try_into()
            .map_err(|_| KeyStoreError::InvalidCapsule)?;
        let wrapped_len = u32::from_be_bytes(
            encoded[45..49]
                .try_into()
                .map_err(|_| KeyStoreError::InvalidCapsule)?,
        ) as usize;
        if wrapped_len > MAX_WRAPPED_MASTER_KEY_LEN || encoded.len() != FIXED_LEN + wrapped_len {
            return Err(KeyStoreError::InvalidCapsule);
        }
        let wrapped_master_key = (wrapped_len != 0).then(|| encoded[FIXED_LEN..].to_vec());
        Self::new(generation, device_key, wrapped_master_key)
    }
}

pub trait LocalKeyCapsuleStore {
    fn load(&self, slot: LocalKeyCapsuleSlot) -> Result<Option<LocalKeyCapsule>, KeyStoreError>;
    fn store(
        &mut self,
        slot: LocalKeyCapsuleSlot,
        capsule: &LocalKeyCapsule,
    ) -> Result<(), KeyStoreError>;
    fn delete(&mut self, slot: LocalKeyCapsuleSlot) -> Result<(), KeyStoreError>;
}

#[derive(Default)]
pub struct InMemoryLocalKeyCapsuleStore {
    active: Option<LocalKeyCapsule>,
    pending: Option<LocalKeyCapsule>,
}

impl LocalKeyCapsuleStore for InMemoryLocalKeyCapsuleStore {
    fn load(&self, slot: LocalKeyCapsuleSlot) -> Result<Option<LocalKeyCapsule>, KeyStoreError> {
        Ok(match slot {
            LocalKeyCapsuleSlot::Active => self.active.clone(),
            LocalKeyCapsuleSlot::Pending => self.pending.clone(),
        })
    }

    fn store(
        &mut self,
        slot: LocalKeyCapsuleSlot,
        capsule: &LocalKeyCapsule,
    ) -> Result<(), KeyStoreError> {
        match slot {
            LocalKeyCapsuleSlot::Active => self.active = Some(capsule.clone()),
            LocalKeyCapsuleSlot::Pending => self.pending = Some(capsule.clone()),
        }
        Ok(())
    }

    fn delete(&mut self, slot: LocalKeyCapsuleSlot) -> Result<(), KeyStoreError> {
        match slot {
            LocalKeyCapsuleSlot::Active => self.active = None,
            LocalKeyCapsuleSlot::Pending => self.pending = None,
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capsule_v2_roundtrips_and_rejects_noncanonical_input() {
        let capsule = LocalKeyCapsule::new(7, [0x42; 32], Some(vec![1, 2, 3])).unwrap();
        let encoded = capsule.encode();
        let decoded = LocalKeyCapsule::decode(&encoded).unwrap();
        assert_eq!(decoded.generation(), 7);
        assert_eq!(decoded.device_key(), &[0x42; 32]);
        assert_eq!(decoded.wrapped_master_key(), Some([1, 2, 3].as_slice()));

        let mut old_version = encoded.to_vec();
        old_version[4] = 1;
        assert!(matches!(
            LocalKeyCapsule::decode(&old_version),
            Err(KeyStoreError::InvalidCapsule)
        ));
        assert!(matches!(
            LocalKeyCapsule::new(0, [0; 32], None),
            Err(KeyStoreError::InvalidCapsule)
        ));
    }

    #[test]
    fn capsule_debug_redacts_both_secrets() {
        let capsule = LocalKeyCapsule::new(1, [0x42; 32], Some(vec![9, 8, 7])).unwrap();
        let rendered = format!("{capsule:?}");
        assert!(!rendered.contains("66, 66"));
        assert!(!rendered.contains("9, 8, 7"));
        assert!(rendered.contains("[REDACTED]"));
    }
}

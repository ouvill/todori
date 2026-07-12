//! Encrypted sync blob envelope.

use thiserror::Error;
use todori_crypto::{decrypt, encrypt, CryptoError};

use crate::field_map::SyncPlaintext;

pub const ENVELOPE_VERSION: u8 = 3;
pub const MAX_ENCRYPTED_BLOB_LEN: usize = 64 * 1024;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum EnvelopeError {
    #[error("encrypted blob is empty")]
    EmptyBlob,
    #[error("unsupported encrypted blob version")]
    UnsupportedVersion,
    #[error("encrypted blob exceeds 64KB limit")]
    BlobTooLarge,
    #[error("plaintext JSON serialization failed")]
    Serialization,
    #[error("plaintext JSON deserialization failed")]
    Deserialization,
    #[error("crypto error: {0}")]
    Crypto(#[from] CryptoError),
}

pub fn encrypt_plaintext(
    dek: &[u8; 32],
    collection: &str,
    record_id: &str,
    plaintext: &SyncPlaintext,
) -> Result<Vec<u8>, EnvelopeError> {
    plaintext
        .validate_for_collection(collection, record_id)
        .map_err(|_| EnvelopeError::Serialization)?;
    let plaintext_json = serde_json::to_vec(plaintext).map_err(|_| EnvelopeError::Serialization)?;
    let inner = encrypt(dek, &plaintext_json, &aad(collection, record_id))?;
    let mut out = Vec::with_capacity(1 + inner.len());
    out.push(ENVELOPE_VERSION);
    out.extend_from_slice(&inner);
    if out.len() > MAX_ENCRYPTED_BLOB_LEN {
        return Err(EnvelopeError::BlobTooLarge);
    }
    Ok(out)
}

pub fn decrypt_plaintext(
    dek: &[u8; 32],
    collection: &str,
    record_id: &str,
    blob: &[u8],
) -> Result<SyncPlaintext, EnvelopeError> {
    if blob.is_empty() {
        return Err(EnvelopeError::EmptyBlob);
    }
    if blob.len() > MAX_ENCRYPTED_BLOB_LEN {
        return Err(EnvelopeError::BlobTooLarge);
    }
    if blob[0] != ENVELOPE_VERSION {
        return Err(EnvelopeError::UnsupportedVersion);
    }
    let plaintext_json = decrypt(dek, &blob[1..], &aad(collection, record_id))?;
    let plaintext: SyncPlaintext =
        serde_json::from_slice(&plaintext_json).map_err(|_| EnvelopeError::Deserialization)?;
    plaintext
        .validate_for_collection(collection, record_id)
        .map_err(|_| EnvelopeError::Deserialization)?;
    Ok(plaintext)
}

fn aad(collection: &str, record_id: &str) -> Vec<u8> {
    format!("todori-sync-envelope/v2\ncollection:{collection}\nrecord_id:{record_id}").into_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hlc::Hlc;
    use todori_domain::{new_list, CompletedTimerSession, List, TimerFinishKind, TimerMode, Uuid};

    fn key(byte: u8) -> [u8; 32] {
        [byte; 32]
    }

    fn record_id() -> String {
        todori_domain::Uuid::from_u128(1).to_string()
    }

    fn plaintext() -> SyncPlaintext {
        let hlc = Hlc {
            wall_ms: 1_799_000_000_000,
            counter: 1,
            device_id: "device-a".to_string(),
        };
        SyncPlaintext::from_list(&sample_list(), hlc).unwrap()
    }

    fn sample_list() -> List {
        new_list("Inbox".into(), "7fffffffffffffffffffffffffffffff".into(), 1).unwrap()
    }

    #[test]
    fn envelope_roundtrips_plaintext() {
        let record_id = record_id();
        let blob = encrypt_plaintext(&key(0x42), "lists", &record_id, &plaintext()).unwrap();

        let decrypted = decrypt_plaintext(&key(0x42), "lists", &record_id, &blob).unwrap();

        assert_eq!(decrypted, plaintext());
        assert_eq!(blob[0], ENVELOPE_VERSION);
    }

    #[test]
    fn envelope_rejects_wrong_dek() {
        let record_id = record_id();
        let blob = encrypt_plaintext(&key(0x42), "lists", &record_id, &plaintext()).unwrap();

        assert_eq!(
            decrypt_plaintext(&key(0x24), "lists", &record_id, &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn envelope_rejects_record_id_or_collection_swap() {
        let record_id = record_id();
        let other_record_id = todori_domain::Uuid::from_u128(2).to_string();
        let blob = encrypt_plaintext(&key(0x42), "lists", &record_id, &plaintext()).unwrap();

        assert_eq!(
            decrypt_plaintext(&key(0x42), "tasks", &record_id, &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        );
        assert_eq!(
            decrypt_plaintext(&key(0x42), "lists", &other_record_id, &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn timer_session_uses_existing_envelope_and_rejects_wrong_tenant_root_dek() {
        let session = CompletedTimerSession {
            id: Uuid::now_v7(),
            task_id: Uuid::now_v7(),
            mode: TimerMode::Stopwatch,
            finish_kind: TimerFinishKind::Completed,
            started_at: 1_000,
            ended_at: 2_000,
            active_duration_ms: 900,
            created_at: 2_001,
        };
        let plaintext = SyncPlaintext::from_timer_session(
            &session,
            Hlc {
                wall_ms: 2_001,
                counter: 0,
                device_id: "device-a".into(),
            },
        )
        .unwrap();
        let record_id = session.id.to_string();
        let blob = encrypt_plaintext(&key(0x42), "timer_sessions", &record_id, &plaintext).unwrap();

        assert_eq!(blob[0], 3);
        assert_eq!(
            decrypt_plaintext(&key(0x42), "timer_sessions", &record_id, &blob).unwrap(),
            plaintext
        );
        assert!(matches!(
            decrypt_plaintext(&key(0x24), "timer_sessions", &record_id, &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        ));
        assert!(decrypt_plaintext(&key(0x42), "tasks", &record_id, &blob).is_err());
    }

    #[test]
    fn envelope_rejects_tampering() {
        let record_id = record_id();
        let mut blob = encrypt_plaintext(&key(0x42), "lists", &record_id, &plaintext()).unwrap();
        let last = blob.len() - 1;
        blob[last] ^= 0xff;

        assert_eq!(
            decrypt_plaintext(&key(0x42), "lists", &record_id, &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn envelope_rejects_unknown_version() {
        let record_id = record_id();
        let mut blob = encrypt_plaintext(&key(0x42), "lists", &record_id, &plaintext()).unwrap();
        blob[0] = ENVELOPE_VERSION + 1;

        assert_eq!(
            decrypt_plaintext(&key(0x42), "lists", &record_id, &blob),
            Err(EnvelopeError::UnsupportedVersion)
        );
    }

    #[test]
    fn envelope_rejects_blobs_over_64kb() {
        let blob = vec![ENVELOPE_VERSION; MAX_ENCRYPTED_BLOB_LEN + 1];

        assert_eq!(
            decrypt_plaintext(&key(0x42), "tasks", &record_id(), &blob),
            Err(EnvelopeError::BlobTooLarge)
        );
    }

    #[test]
    fn envelope_rejects_final_encrypted_blob_over_64kb() {
        let hlc = Hlc {
            wall_ms: 1_799_000_000_000,
            counter: 1,
            device_id: "device-a".to_string(),
        };
        let mut list = sample_list();
        list.name = "x".repeat(MAX_ENCRYPTED_BLOB_LEN);
        let plaintext = SyncPlaintext::from_list(&list, hlc).unwrap();

        assert_eq!(
            encrypt_plaintext(&key(0x42), "lists", &record_id(), &plaintext),
            Err(EnvelopeError::BlobTooLarge)
        );
    }
}

//! Encrypted sync blob envelope.

use thiserror::Error;
use todori_crypto::{decrypt, encrypt, CryptoError};

use crate::field_map::SyncPlaintext;

pub const ENVELOPE_VERSION: u8 = 2;
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
    serde_json::from_slice(&plaintext_json).map_err(|_| EnvelopeError::Deserialization)
}

fn aad(collection: &str, record_id: &str) -> Vec<u8> {
    format!("todori-sync-envelope/v2\ncollection:{collection}\nrecord_id:{record_id}").into_bytes()
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use serde_json::json;

    use super::*;
    use crate::hlc::Hlc;

    fn key(byte: u8) -> [u8; 32] {
        [byte; 32]
    }

    fn plaintext() -> SyncPlaintext {
        let hlc = Hlc {
            wall_ms: 1_799_000_000_000,
            counter: 1,
            device_id: "device-a".to_string(),
        };
        SyncPlaintext::from_single_hlc(
            BTreeMap::from([
                ("title".to_string(), json!("Buy milk")),
                ("priority".to_string(), json!(2)),
            ]),
            hlc,
        )
        .unwrap()
    }

    #[test]
    fn envelope_roundtrips_plaintext() {
        let blob = encrypt_plaintext(&key(0x42), "tasks", "record-1", &plaintext()).unwrap();

        let decrypted = decrypt_plaintext(&key(0x42), "tasks", "record-1", &blob).unwrap();

        assert_eq!(decrypted, plaintext());
        assert_eq!(blob[0], ENVELOPE_VERSION);
    }

    #[test]
    fn envelope_rejects_wrong_dek() {
        let blob = encrypt_plaintext(&key(0x42), "tasks", "record-1", &plaintext()).unwrap();

        assert_eq!(
            decrypt_plaintext(&key(0x24), "tasks", "record-1", &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn envelope_rejects_record_id_or_collection_swap() {
        let blob = encrypt_plaintext(&key(0x42), "tasks", "record-1", &plaintext()).unwrap();

        assert_eq!(
            decrypt_plaintext(&key(0x42), "lists", "record-1", &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        );
        assert_eq!(
            decrypt_plaintext(&key(0x42), "tasks", "record-2", &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn envelope_rejects_tampering() {
        let mut blob = encrypt_plaintext(&key(0x42), "tasks", "record-1", &plaintext()).unwrap();
        let last = blob.len() - 1;
        blob[last] ^= 0xff;

        assert_eq!(
            decrypt_plaintext(&key(0x42), "tasks", "record-1", &blob),
            Err(EnvelopeError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn envelope_rejects_unknown_version() {
        let mut blob = encrypt_plaintext(&key(0x42), "tasks", "record-1", &plaintext()).unwrap();
        blob[0] = ENVELOPE_VERSION + 1;

        assert_eq!(
            decrypt_plaintext(&key(0x42), "tasks", "record-1", &blob),
            Err(EnvelopeError::UnsupportedVersion)
        );
    }

    #[test]
    fn envelope_rejects_blobs_over_64kb() {
        let blob = vec![ENVELOPE_VERSION; MAX_ENCRYPTED_BLOB_LEN + 1];

        assert_eq!(
            decrypt_plaintext(&key(0x42), "tasks", "record-1", &blob),
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
        let plaintext = SyncPlaintext::from_single_hlc(
            BTreeMap::from([(
                "note".to_string(),
                json!("x".repeat(MAX_ENCRYPTED_BLOB_LEN)),
            )]),
            hlc,
        )
        .unwrap();

        assert_eq!(
            encrypt_plaintext(&key(0x42), "tasks", "record-1", &plaintext),
            Err(EnvelopeError::BlobTooLarge)
        );
    }
}

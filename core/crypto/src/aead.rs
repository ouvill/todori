//! XChaCha20-Poly1305 によるレコード暗号化。
//!
//! AAD（Associated Data）にはレコードID・collection名を呼び出し側が渡す想定。
//! 暗号文の入れ替え（別レコードの暗号文を別IDのレコードとして差し替える攻撃）を
//! 検知・防止するための設計であり、詳細は `docs/03_技術仕様書.md` §4.8 を参照。

use chacha20poly1305::{
    aead::{Aead, AeadCore, KeyInit, OsRng, Payload},
    XChaCha20Poly1305, XNonce,
};
use thiserror::Error;

const NONCE_LEN: usize = 24;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum CryptoError {
    #[error("encryption failed")]
    EncryptionFailed,
    #[error("decryption failed (invalid key, AAD, or tampered ciphertext)")]
    DecryptionFailed,
    #[error("ciphertext is too short to contain a nonce")]
    CiphertextTooShort,
}

/// `plaintext` を `key` (32byte) で XChaCha20-Poly1305 暗号化する。
///
/// 戻り値は `nonce(24byte) || ciphertext` の連結。
pub fn encrypt(key: &[u8; 32], plaintext: &[u8], aad: &[u8]) -> Result<Vec<u8>, CryptoError> {
    let cipher = XChaCha20Poly1305::new(key.into());
    let nonce = XChaCha20Poly1305::generate_nonce(&mut OsRng);
    let ciphertext = cipher
        .encrypt(
            &nonce,
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| CryptoError::EncryptionFailed)?;

    let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

/// `encrypt` で生成された `nonce(24byte) || ciphertext` を復号する。
pub fn decrypt(key: &[u8; 32], blob: &[u8], aad: &[u8]) -> Result<Vec<u8>, CryptoError> {
    if blob.len() < NONCE_LEN {
        return Err(CryptoError::CiphertextTooShort);
    }
    let (nonce_bytes, ciphertext) = blob.split_at(NONCE_LEN);
    let nonce = XNonce::from_slice(nonce_bytes);
    let cipher = XChaCha20Poly1305::new(key.into());
    cipher
        .decrypt(
            nonce,
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|_| CryptoError::DecryptionFailed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_key() -> [u8; 32] {
        [0x42; 32]
    }

    #[test]
    fn encrypt_then_decrypt_roundtrips() {
        let key = test_key();
        let plaintext = b"buy milk";
        let aad = b"task:0196a000-0000-7000-8000-000000000000";

        let blob = encrypt(&key, plaintext, aad).unwrap();
        let decrypted = decrypt(&key, &blob, aad).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn decrypt_fails_with_mismatched_aad() {
        let key = test_key();
        let plaintext = b"buy milk";
        let blob = encrypt(&key, plaintext, b"task:id-1").unwrap();

        let result = decrypt(&key, &blob, b"task:id-2");

        assert_eq!(result, Err(CryptoError::DecryptionFailed));
    }

    #[test]
    fn decrypt_fails_with_tampered_ciphertext() {
        let key = test_key();
        let plaintext = b"buy milk";
        let aad = b"task:id-1";
        let mut blob = encrypt(&key, plaintext, aad).unwrap();

        let last = blob.len() - 1;
        blob[last] ^= 0xFF;

        let result = decrypt(&key, &blob, aad);

        assert_eq!(result, Err(CryptoError::DecryptionFailed));
    }

    #[test]
    fn decrypt_fails_with_too_short_blob() {
        let key = test_key();
        let result = decrypt(&key, b"short", b"aad");
        assert_eq!(result, Err(CryptoError::CiphertextTooShort));
    }
}

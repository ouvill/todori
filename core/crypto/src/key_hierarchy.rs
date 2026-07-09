//! Account key hierarchy helpers.
//!
//! These helpers implement the key wrapping primitives described in
//! `docs/03_技術仕様書.md` §4.2-§4.3. Plain keys returned by this module are
//! process-local material; callers must not persist them unwrapped.

use rand::{rngs::OsRng, RngCore};
use thiserror::Error;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::Zeroizing;

use crate::{decrypt, derive_key, encrypt, CryptoError};

pub const KEY_LEN: usize = 32;

pub const KEK_PW_INFO: &[u8] = b"todori/kek-pw/v1";
pub const RECOVERY_KEY_INFO: &[u8] = b"todori/recovery-key-wrap-key/v1";

pub const WRAP_MK_BY_KEK_PW_AAD: &[u8] = b"todori/wrap/mk-by-kek-pw/v1";
pub const WRAP_MK_BY_DEVICE_KEY_AAD: &[u8] = b"todori/wrap/mk-by-device-key/v1";
pub const WRAP_MK_BY_RECOVERY_KEY_AAD: &[u8] = b"todori/wrap/mk-by-recovery-key/v1";
pub const WRAP_USER_SK_BY_MK_AAD: &[u8] = b"todori/wrap/user-x25519-sk-by-mk/v1";
pub const WRAP_TENANT_DEK_BY_MK_AAD: &[u8] = b"todori/wrap/tenant-root-dek-by-mk/v1";
pub const WRAP_LIST_DEK_BY_MK_AAD: &[u8] = b"todori/wrap/list-dek-by-mk/v1";
pub const WRAP_LOCAL_LIST_DEK_BY_MK_AAD_PREFIX: &[u8] = b"todori/wrap/local-list-dek-by-mk/v1/";

const RECOVERY_WORDS: &[&str] = &[
    "amber", "anchor", "apricot", "atlas", "bamboo", "beacon", "birch", "breeze", "cabin", "cedar",
    "cinder", "cobalt", "coral", "cotton", "dawn", "delta", "ember", "fern", "flint", "garden",
    "harbor", "hazel", "indigo", "juniper", "kiwi", "lantern", "linen", "maple", "meadow", "mint",
    "nectar", "olive", "onyx", "orchard", "pearl", "pine", "plum", "quartz", "river", "sage",
    "silver", "spruce", "stone", "sunset", "teal", "thistle", "topaz", "valley", "violet",
    "willow", "winter", "yarrow", "zinc", "acorn", "basil", "brook", "clover", "dune", "elm",
    "frost", "grove", "iris", "laurel", "moss",
];

#[derive(Debug, Error, PartialEq, Eq)]
pub enum KeyHierarchyError {
    #[error("wrapped key did not contain exactly 32 bytes")]
    InvalidUnwrappedKeyLength,
    #[error("crypto error: {0}")]
    Crypto(#[from] CryptoError),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserX25519KeyPair {
    pub secret_key: [u8; KEY_LEN],
    pub public_key: [u8; KEY_LEN],
}

pub fn generate_master_key() -> [u8; KEY_LEN] {
    random_key()
}

pub fn generate_tenant_root_dek() -> [u8; KEY_LEN] {
    random_key()
}

pub fn generate_list_dek() -> [u8; KEY_LEN] {
    random_key()
}

pub fn generate_device_public_key() -> [u8; KEY_LEN] {
    generate_user_x25519_key_pair().public_key
}

pub fn generate_user_x25519_key_pair() -> UserX25519KeyPair {
    let secret = StaticSecret::random_from_rng(OsRng);
    let public = PublicKey::from(&secret);
    UserX25519KeyPair {
        secret_key: secret.to_bytes(),
        public_key: public.to_bytes(),
    }
}

pub fn generate_recovery_key() -> String {
    let mut bytes = [0u8; 24];
    OsRng.fill_bytes(&mut bytes);
    bytes
        .iter()
        .map(|byte| RECOVERY_WORDS[usize::from(*byte) % RECOVERY_WORDS.len()])
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn derive_kek_pw(export_key: &[u8]) -> [u8; KEY_LEN] {
    derive_key(export_key, KEK_PW_INFO)
}

pub fn derive_recovery_wrap_key(recovery_key: &str) -> [u8; KEY_LEN] {
    derive_key(recovery_key.trim().as_bytes(), RECOVERY_KEY_INFO)
}

pub fn wrap_master_key_with_kek_pw(
    master_key: &[u8; KEY_LEN],
    kek_pw: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(master_key, kek_pw, WRAP_MK_BY_KEK_PW_AAD)
}

pub fn unwrap_master_key_with_kek_pw(
    wrapped: &[u8],
    kek_pw: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(wrapped, kek_pw, WRAP_MK_BY_KEK_PW_AAD)
}

pub fn wrap_master_key_with_device_key(
    master_key: &[u8; KEY_LEN],
    device_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(master_key, device_key, WRAP_MK_BY_DEVICE_KEY_AAD)
}

pub fn unwrap_master_key_with_device_key(
    wrapped: &[u8],
    device_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(wrapped, device_key, WRAP_MK_BY_DEVICE_KEY_AAD)
}

pub fn wrap_master_key_with_recovery_key(
    master_key: &[u8; KEY_LEN],
    recovery_wrap_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(master_key, recovery_wrap_key, WRAP_MK_BY_RECOVERY_KEY_AAD)
}

pub fn unwrap_master_key_with_recovery_key(
    wrapped: &[u8],
    recovery_wrap_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(wrapped, recovery_wrap_key, WRAP_MK_BY_RECOVERY_KEY_AAD)
}

pub fn wrap_user_secret_key_with_master_key(
    user_secret_key: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(user_secret_key, master_key, WRAP_USER_SK_BY_MK_AAD)
}

pub fn unwrap_user_secret_key_with_master_key(
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(wrapped, master_key, WRAP_USER_SK_BY_MK_AAD)
}

pub fn wrap_tenant_root_dek_with_master_key(
    tenant_dek: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(tenant_dek, master_key, WRAP_TENANT_DEK_BY_MK_AAD)
}

pub fn unwrap_tenant_root_dek_with_master_key(
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(wrapped, master_key, WRAP_TENANT_DEK_BY_MK_AAD)
}

pub fn wrap_list_dek_with_master_key(
    list_dek: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(list_dek, master_key, WRAP_LIST_DEK_BY_MK_AAD)
}

pub fn unwrap_list_dek_with_master_key(
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(wrapped, master_key, WRAP_LIST_DEK_BY_MK_AAD)
}

pub fn wrap_local_list_dek_with_master_key(
    list_id: &str,
    list_dek: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(list_dek, master_key, &local_list_dek_wrap_aad(list_id))
}

pub fn unwrap_local_list_dek_with_master_key(
    list_id: &str,
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(wrapped, master_key, &local_list_dek_wrap_aad(list_id))
}

fn local_list_dek_wrap_aad(list_id: &str) -> Vec<u8> {
    let mut aad = Vec::with_capacity(WRAP_LOCAL_LIST_DEK_BY_MK_AAD_PREFIX.len() + list_id.len());
    aad.extend_from_slice(WRAP_LOCAL_LIST_DEK_BY_MK_AAD_PREFIX);
    aad.extend_from_slice(list_id.as_bytes());
    aad
}

fn random_key() -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];
    OsRng.fill_bytes(&mut key);
    key
}

fn wrap_key(
    plaintext_key: &[u8; KEY_LEN],
    wrapping_key: &[u8; KEY_LEN],
    aad: &[u8],
) -> Result<Vec<u8>, KeyHierarchyError> {
    encrypt(wrapping_key, plaintext_key, aad).map_err(KeyHierarchyError::from)
}

fn unwrap_key(
    wrapped: &[u8],
    wrapping_key: &[u8; KEY_LEN],
    aad: &[u8],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    let plaintext = Zeroizing::new(decrypt(wrapping_key, wrapped, aad)?);
    if plaintext.len() != KEY_LEN {
        return Err(KeyHierarchyError::InvalidUnwrappedKeyLength);
    }
    let mut out = [0u8; KEY_LEN];
    out.copy_from_slice(&plaintext);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(byte: u8) -> [u8; KEY_LEN] {
        [byte; KEY_LEN]
    }

    #[test]
    fn generated_keys_have_expected_lengths() {
        assert_eq!(generate_master_key().len(), KEY_LEN);
        assert_eq!(generate_tenant_root_dek().len(), KEY_LEN);
        assert_eq!(generate_list_dek().len(), KEY_LEN);

        let pair = generate_user_x25519_key_pair();
        assert_eq!(pair.secret_key.len(), KEY_LEN);
        assert_eq!(pair.public_key.len(), KEY_LEN);
    }

    #[test]
    fn recovery_key_is_human_readable_and_derives_deterministically() {
        let recovery_key = generate_recovery_key();
        assert_eq!(recovery_key.split_whitespace().count(), 24);
        assert_eq!(
            derive_recovery_wrap_key(&recovery_key),
            derive_recovery_wrap_key(&recovery_key)
        );
    }

    #[test]
    fn kek_pw_derivation_is_context_bound() {
        let export_key = b"opaque export key";
        assert_eq!(
            derive_kek_pw(export_key),
            derive_key(export_key, KEK_PW_INFO)
        );
        assert_ne!(derive_kek_pw(export_key), derive_key(export_key, b"other"));
    }

    #[test]
    fn master_key_wrap_roundtrips_for_password_device_and_recovery_keys() {
        let master_key = key(0x42);
        let kek_pw = key(0x11);
        let device_key = key(0x22);
        let recovery_key = key(0x33);

        let by_password = wrap_master_key_with_kek_pw(&master_key, &kek_pw).unwrap();
        let by_device = wrap_master_key_with_device_key(&master_key, &device_key).unwrap();
        let by_recovery = wrap_master_key_with_recovery_key(&master_key, &recovery_key).unwrap();

        assert_eq!(
            unwrap_master_key_with_kek_pw(&by_password, &kek_pw).unwrap(),
            master_key
        );
        assert_eq!(
            unwrap_master_key_with_device_key(&by_device, &device_key).unwrap(),
            master_key
        );
        assert_eq!(
            unwrap_master_key_with_recovery_key(&by_recovery, &recovery_key).unwrap(),
            master_key
        );
    }

    #[test]
    fn wrapped_key_rejects_wrong_key() {
        let master_key = key(0x42);
        let wrapped = wrap_master_key_with_kek_pw(&master_key, &key(0x11)).unwrap();

        assert_eq!(
            unwrap_master_key_with_kek_pw(&wrapped, &key(0x12)),
            Err(KeyHierarchyError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn wrapped_key_rejects_wrong_aad_context() {
        let master_key = key(0x42);
        let wrapping_key = key(0x11);
        let wrapped = wrap_master_key_with_kek_pw(&master_key, &wrapping_key).unwrap();

        assert_eq!(
            unwrap_master_key_with_device_key(&wrapped, &wrapping_key),
            Err(KeyHierarchyError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn user_secret_tenant_dek_and_list_dek_roundtrip_with_distinct_contexts() {
        let master_key = key(0x42);
        let user_secret_key = key(0x10);
        let tenant_dek = key(0x20);
        let list_dek = key(0x30);

        let wrapped_user_secret =
            wrap_user_secret_key_with_master_key(&user_secret_key, &master_key).unwrap();
        let wrapped_tenant =
            wrap_tenant_root_dek_with_master_key(&tenant_dek, &master_key).unwrap();
        let wrapped_list = wrap_list_dek_with_master_key(&list_dek, &master_key).unwrap();

        assert_eq!(
            unwrap_user_secret_key_with_master_key(&wrapped_user_secret, &master_key).unwrap(),
            user_secret_key
        );
        assert_eq!(
            unwrap_tenant_root_dek_with_master_key(&wrapped_tenant, &master_key).unwrap(),
            tenant_dek
        );
        assert_eq!(
            unwrap_list_dek_with_master_key(&wrapped_list, &master_key).unwrap(),
            list_dek
        );
        assert_eq!(
            unwrap_tenant_root_dek_with_master_key(&wrapped_list, &master_key),
            Err(KeyHierarchyError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn local_list_dek_wrap_is_bound_to_list_id() {
        let master_key = key(0x10);
        let list_dek = key(0x20);
        let wrapped =
            wrap_local_list_dek_with_master_key("list-a", &list_dek, &master_key).unwrap();

        assert_eq!(
            unwrap_local_list_dek_with_master_key("list-a", &wrapped, &master_key).unwrap(),
            list_dek
        );
        assert!(unwrap_local_list_dek_with_master_key("list-b", &wrapped, &master_key).is_err());
    }
}

//! Account key hierarchy helpers.
//!
//! These helpers implement the key wrapping primitives described in
//! `docs/03_技術仕様書.md` §4.2-§4.3. Plain keys returned by this module are
//! process-local material; callers must not persist them unwrapped.

use bip39::{Language, Mnemonic};
use rand::{rngs::OsRng, RngCore};
use thiserror::Error;
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::{decrypt, derive_key, encrypt, CryptoError, CRYPTO_SUITE_ID};

pub const KEY_LEN: usize = 32;
pub const ACCOUNT_ROOT_PRIVATE_KEY_LEN: usize = 64;
pub const INITIAL_KEY_GENERATION: u64 = 1;

pub const KEK_PW_INFO: &[u8] = b"taskveil/kek-pw/v1";
pub const RECOVERY_KEY_INFO: &[u8] = b"taskveil/recovery-key-wrap-key/v1";

const WRAP_AAD_MAGIC: &[u8; 4] = b"TWK1";
const WRAP_AAD_LEN: usize = 63;

#[derive(Clone, Copy)]
#[repr(u8)]
enum WrapPurpose {
    MasterKeyByPassword = 1,
    MasterKeyByRecovery = 2,
    MasterKeyByDevice = 3,
    AccountSecretByMasterKey = 4,
    TenantDekByMasterKey = 5,
    ListDekByMasterKey = 6,
    LocalTenantDekByMasterKey = 7,
    LocalListDekByMasterKey = 8,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum KeyHierarchyError {
    #[error("wrapped key had an invalid plaintext length")]
    InvalidUnwrappedKeyLength,
    #[error("crypto error: {0}")]
    Crypto(#[from] CryptoError),
    #[error("invalid BIP39 recovery key")]
    InvalidRecoveryKey,
    #[error("invalid key wrap context")]
    InvalidWrapContext,
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

pub fn generate_recovery_key() -> Zeroizing<String> {
    let mut entropy = Zeroizing::new([0u8; 32]);
    OsRng.fill_bytes(&mut *entropy);
    let mnemonic = Mnemonic::from_entropy_in(Language::English, &*entropy)
        .expect("32-byte entropy always produces a 24-word BIP39 mnemonic");
    Zeroizing::new(mnemonic.to_string())
}

pub fn derive_kek_pw(export_key: &[u8]) -> [u8; KEY_LEN] {
    derive_key(export_key, KEK_PW_INFO)
}

pub fn derive_recovery_wrap_key(recovery_key: &str) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    let mnemonic = Mnemonic::parse_in(Language::English, recovery_key)
        .map_err(|_| KeyHierarchyError::InvalidRecoveryKey)?;
    if mnemonic.word_count() != 24 {
        return Err(KeyHierarchyError::InvalidRecoveryKey);
    }
    let entropy = Zeroizing::new(mnemonic.to_entropy());
    if entropy.len() != KEY_LEN {
        return Err(KeyHierarchyError::InvalidRecoveryKey);
    }
    Ok(derive_key(&entropy, RECOVERY_KEY_INFO))
}

pub fn wrap_master_key_with_kek_pw(
    user_id: Uuid,
    generation: u64,
    master_key: &[u8; KEY_LEN],
    kek_pw: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(
        master_key,
        kek_pw,
        wrap_aad(
            WrapPurpose::MasterKeyByPassword,
            generation,
            Some(user_id),
            None,
            None,
        ),
    )
}

pub fn unwrap_master_key_with_kek_pw(
    user_id: Uuid,
    generation: u64,
    wrapped: &[u8],
    kek_pw: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(
        wrapped,
        kek_pw,
        wrap_aad(
            WrapPurpose::MasterKeyByPassword,
            generation,
            Some(user_id),
            None,
            None,
        ),
    )
}

pub fn wrap_master_key_with_device_key(
    user_id: Uuid,
    generation: u64,
    master_key: &[u8; KEY_LEN],
    device_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(
        master_key,
        device_key,
        wrap_aad(
            WrapPurpose::MasterKeyByDevice,
            generation,
            Some(user_id),
            None,
            None,
        ),
    )
}

pub fn unwrap_master_key_with_device_key(
    user_id: Uuid,
    generation: u64,
    wrapped: &[u8],
    device_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(
        wrapped,
        device_key,
        wrap_aad(
            WrapPurpose::MasterKeyByDevice,
            generation,
            Some(user_id),
            None,
            None,
        ),
    )
}

pub fn wrap_master_key_with_recovery_key(
    user_id: Uuid,
    generation: u64,
    master_key: &[u8; KEY_LEN],
    recovery_wrap_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(
        master_key,
        recovery_wrap_key,
        wrap_aad(
            WrapPurpose::MasterKeyByRecovery,
            generation,
            Some(user_id),
            None,
            None,
        ),
    )
}

pub fn unwrap_master_key_with_recovery_key(
    user_id: Uuid,
    generation: u64,
    wrapped: &[u8],
    recovery_wrap_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(
        wrapped,
        recovery_wrap_key,
        wrap_aad(
            WrapPurpose::MasterKeyByRecovery,
            generation,
            Some(user_id),
            None,
            None,
        ),
    )
}

pub fn wrap_account_root_private_key_with_master_key(
    user_id: Uuid,
    generation: u64,
    account_root_private_key: &[u8; ACCOUNT_ROOT_PRIVATE_KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    encrypt(
        master_key,
        account_root_private_key,
        &wrap_aad(
            WrapPurpose::AccountSecretByMasterKey,
            generation,
            Some(user_id),
            None,
            None,
        )?,
    )
    .map_err(KeyHierarchyError::from)
}

pub fn unwrap_account_root_private_key_with_master_key(
    user_id: Uuid,
    generation: u64,
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<Zeroizing<[u8; ACCOUNT_ROOT_PRIVATE_KEY_LEN]>, KeyHierarchyError> {
    let plaintext = Zeroizing::new(decrypt(
        master_key,
        wrapped,
        &wrap_aad(
            WrapPurpose::AccountSecretByMasterKey,
            generation,
            Some(user_id),
            None,
            None,
        )?,
    )?);
    if plaintext.len() != ACCOUNT_ROOT_PRIVATE_KEY_LEN {
        return Err(KeyHierarchyError::InvalidUnwrappedKeyLength);
    }
    let mut output = Zeroizing::new([0u8; ACCOUNT_ROOT_PRIVATE_KEY_LEN]);
    output.copy_from_slice(&plaintext);
    Ok(output)
}

pub fn wrap_tenant_root_dek_with_master_key(
    tenant_id: Uuid,
    generation: u64,
    tenant_dek: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(
        tenant_dek,
        master_key,
        wrap_aad(
            WrapPurpose::TenantDekByMasterKey,
            generation,
            None,
            Some(tenant_id),
            None,
        ),
    )
}

pub fn unwrap_tenant_root_dek_with_master_key(
    tenant_id: Uuid,
    generation: u64,
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(
        wrapped,
        master_key,
        wrap_aad(
            WrapPurpose::TenantDekByMasterKey,
            generation,
            None,
            Some(tenant_id),
            None,
        ),
    )
}

pub fn wrap_list_dek_with_master_key(
    tenant_id: Uuid,
    list_id: Uuid,
    generation: u64,
    list_dek: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(
        list_dek,
        master_key,
        wrap_aad(
            WrapPurpose::ListDekByMasterKey,
            generation,
            None,
            Some(tenant_id),
            Some(list_id),
        ),
    )
}

pub fn unwrap_list_dek_with_master_key(
    tenant_id: Uuid,
    list_id: Uuid,
    generation: u64,
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(
        wrapped,
        master_key,
        wrap_aad(
            WrapPurpose::ListDekByMasterKey,
            generation,
            None,
            Some(tenant_id),
            Some(list_id),
        ),
    )
}

pub fn wrap_local_list_dek_with_master_key(
    tenant_id: Uuid,
    list_id: Uuid,
    generation: u64,
    list_dek: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(
        list_dek,
        master_key,
        wrap_aad(
            WrapPurpose::LocalListDekByMasterKey,
            generation,
            None,
            Some(tenant_id),
            Some(list_id),
        ),
    )
}

pub fn unwrap_local_list_dek_with_master_key(
    tenant_id: Uuid,
    list_id: Uuid,
    generation: u64,
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(
        wrapped,
        master_key,
        wrap_aad(
            WrapPurpose::LocalListDekByMasterKey,
            generation,
            None,
            Some(tenant_id),
            Some(list_id),
        ),
    )
}

pub fn wrap_local_tenant_root_dek_with_master_key(
    tenant_id: Uuid,
    generation: u64,
    tenant_dek: &[u8; KEY_LEN],
    master_key: &[u8; KEY_LEN],
) -> Result<Vec<u8>, KeyHierarchyError> {
    wrap_key(
        tenant_dek,
        master_key,
        wrap_aad(
            WrapPurpose::LocalTenantDekByMasterKey,
            generation,
            None,
            Some(tenant_id),
            None,
        ),
    )
}

pub fn unwrap_local_tenant_root_dek_with_master_key(
    tenant_id: Uuid,
    generation: u64,
    wrapped: &[u8],
    master_key: &[u8; KEY_LEN],
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    unwrap_key(
        wrapped,
        master_key,
        wrap_aad(
            WrapPurpose::LocalTenantDekByMasterKey,
            generation,
            None,
            Some(tenant_id),
            None,
        ),
    )
}

fn wrap_aad(
    purpose: WrapPurpose,
    generation: u64,
    user_id: Option<Uuid>,
    tenant_id: Option<Uuid>,
    list_id: Option<Uuid>,
) -> Result<[u8; WRAP_AAD_LEN], KeyHierarchyError> {
    let valid_context = match purpose {
        WrapPurpose::MasterKeyByPassword
        | WrapPurpose::MasterKeyByRecovery
        | WrapPurpose::MasterKeyByDevice
        | WrapPurpose::AccountSecretByMasterKey => {
            user_id.is_some_and(|id| !id.is_nil()) && tenant_id.is_none() && list_id.is_none()
        }
        WrapPurpose::TenantDekByMasterKey | WrapPurpose::LocalTenantDekByMasterKey => {
            user_id.is_none() && tenant_id.is_some_and(|id| !id.is_nil()) && list_id.is_none()
        }
        WrapPurpose::ListDekByMasterKey | WrapPurpose::LocalListDekByMasterKey => {
            user_id.is_none()
                && tenant_id.is_some_and(|id| !id.is_nil())
                && list_id.is_some_and(|id| !id.is_nil())
        }
    };
    if generation == 0 || !valid_context {
        return Err(KeyHierarchyError::InvalidWrapContext);
    }
    let mut aad = [0u8; WRAP_AAD_LEN];
    aad[..4].copy_from_slice(WRAP_AAD_MAGIC);
    aad[4] = purpose as u8;
    aad[5..7].copy_from_slice(&CRYPTO_SUITE_ID.to_be_bytes());
    aad[7..15].copy_from_slice(&generation.to_be_bytes());
    if let Some(id) = user_id {
        aad[15..31].copy_from_slice(id.as_bytes());
    }
    if let Some(id) = tenant_id {
        aad[31..47].copy_from_slice(id.as_bytes());
    }
    if let Some(id) = list_id {
        aad[47..63].copy_from_slice(id.as_bytes());
    }
    Ok(aad)
}

fn random_key() -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];
    OsRng.fill_bytes(&mut key);
    key
}

fn wrap_key(
    plaintext_key: &[u8; KEY_LEN],
    wrapping_key: &[u8; KEY_LEN],
    aad: Result<[u8; WRAP_AAD_LEN], KeyHierarchyError>,
) -> Result<Vec<u8>, KeyHierarchyError> {
    encrypt(wrapping_key, plaintext_key, &aad?).map_err(KeyHierarchyError::from)
}

fn unwrap_key(
    wrapped: &[u8],
    wrapping_key: &[u8; KEY_LEN],
    aad: Result<[u8; WRAP_AAD_LEN], KeyHierarchyError>,
) -> Result<[u8; KEY_LEN], KeyHierarchyError> {
    let plaintext = Zeroizing::new(decrypt(wrapping_key, wrapped, &aad?)?);
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

    fn id(value: u128) -> Uuid {
        Uuid::from_u128(value)
    }

    #[test]
    fn generated_keys_have_expected_lengths() {
        assert_eq!(generate_master_key().len(), KEY_LEN);
        assert_eq!(generate_tenant_root_dek().len(), KEY_LEN);
        assert_eq!(generate_list_dek().len(), KEY_LEN);
    }

    #[test]
    fn recovery_key_is_human_readable_and_derives_deterministically() {
        let recovery_key = generate_recovery_key();
        assert_eq!(recovery_key.split_whitespace().count(), 24);
        let mnemonic = Mnemonic::parse_in(Language::English, recovery_key.as_str()).unwrap();
        assert_eq!(mnemonic.word_count(), 24);
        assert_eq!(mnemonic.to_entropy().len(), 32);
        assert_eq!(
            derive_recovery_wrap_key(&recovery_key).unwrap(),
            derive_recovery_wrap_key(&recovery_key).unwrap()
        );
    }

    #[test]
    fn recovery_key_rejects_wrong_checksum_and_word_count() {
        let recovery_key = generate_recovery_key();
        let mut words = recovery_key.split_whitespace().collect::<Vec<_>>();
        words[23] = if words[23] == "abandon" {
            "ability"
        } else {
            "abandon"
        };
        assert_eq!(
            derive_recovery_wrap_key(&words.join(" ")),
            Err(KeyHierarchyError::InvalidRecoveryKey)
        );
        assert_eq!(
            derive_recovery_wrap_key(&words[..12].join(" ")),
            Err(KeyHierarchyError::InvalidRecoveryKey)
        );
    }

    #[test]
    fn bip39_256_bit_zero_entropy_vector_is_accepted() {
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
        let mnemonic = Mnemonic::parse_in(Language::English, phrase).unwrap();
        assert_eq!(mnemonic.to_entropy(), vec![0u8; 32]);
        assert_eq!(
            derive_recovery_wrap_key(phrase).unwrap(),
            derive_key(&[0u8; 32], RECOVERY_KEY_INFO)
        );
    }

    #[test]
    fn recovery_key_applies_nfkd_before_word_and_checksum_validation() {
        let canonical = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art";
        let compatibility_form = canonical.replacen("abandon", "ａｂａｎｄｏｎ", 1);

        assert_eq!(
            derive_recovery_wrap_key(&compatibility_form).unwrap(),
            derive_recovery_wrap_key(canonical).unwrap()
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
        let user_id = id(1);
        let master_key = key(0x42);
        let kek_pw = key(0x11);
        let device_key = key(0x22);
        let recovery_key = key(0x33);

        let by_password =
            wrap_master_key_with_kek_pw(user_id, INITIAL_KEY_GENERATION, &master_key, &kek_pw)
                .unwrap();
        let by_device = wrap_master_key_with_device_key(
            user_id,
            INITIAL_KEY_GENERATION,
            &master_key,
            &device_key,
        )
        .unwrap();
        let by_recovery = wrap_master_key_with_recovery_key(
            user_id,
            INITIAL_KEY_GENERATION,
            &master_key,
            &recovery_key,
        )
        .unwrap();

        assert_eq!(
            unwrap_master_key_with_kek_pw(user_id, INITIAL_KEY_GENERATION, &by_password, &kek_pw)
                .unwrap(),
            master_key
        );
        assert_eq!(
            unwrap_master_key_with_device_key(
                user_id,
                INITIAL_KEY_GENERATION,
                &by_device,
                &device_key,
            )
            .unwrap(),
            master_key
        );
        assert_eq!(
            unwrap_master_key_with_recovery_key(
                user_id,
                INITIAL_KEY_GENERATION,
                &by_recovery,
                &recovery_key,
            )
            .unwrap(),
            master_key
        );
    }

    #[test]
    fn wrapped_key_rejects_wrong_key() {
        let master_key = key(0x42);
        let wrapped = wrap_master_key_with_kek_pw(id(1), 1, &master_key, &key(0x11)).unwrap();

        assert_eq!(
            unwrap_master_key_with_kek_pw(id(1), 1, &wrapped, &key(0x12)),
            Err(KeyHierarchyError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn wrapped_key_rejects_wrong_aad_context() {
        let master_key = key(0x42);
        let wrapping_key = key(0x11);
        let wrapped = wrap_master_key_with_kek_pw(id(1), 1, &master_key, &wrapping_key).unwrap();

        assert_eq!(
            unwrap_master_key_with_device_key(id(1), 1, &wrapped, &wrapping_key),
            Err(KeyHierarchyError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn wrapped_key_rejects_wrong_identity_and_generation() {
        let master_key = key(0x42);
        let wrapping_key = key(0x11);
        let wrapped = wrap_master_key_with_kek_pw(id(1), 7, &master_key, &wrapping_key).unwrap();

        assert!(unwrap_master_key_with_kek_pw(id(2), 7, &wrapped, &wrapping_key).is_err());
        assert!(unwrap_master_key_with_kek_pw(id(1), 8, &wrapped, &wrapping_key).is_err());
    }

    #[test]
    fn wrap_context_rejects_generation_zero_and_nil_required_ids() {
        assert_eq!(
            wrap_master_key_with_kek_pw(Uuid::nil(), 1, &key(0x42), &key(0x11)),
            Err(KeyHierarchyError::InvalidWrapContext)
        );
        assert_eq!(
            wrap_master_key_with_kek_pw(id(1), 0, &key(0x42), &key(0x11)),
            Err(KeyHierarchyError::InvalidWrapContext)
        );
        assert_eq!(
            wrap_list_dek_with_master_key(id(1), Uuid::nil(), 1, &key(0x42), &key(0x11)),
            Err(KeyHierarchyError::InvalidWrapContext)
        );
    }

    #[test]
    fn twk1_aad_matches_canonical_63_byte_golden_vector() {
        let aad = wrap_aad(
            WrapPurpose::MasterKeyByPassword,
            7,
            Some(Uuid::from_u128(0x000102030405060708090a0b0c0d0e0f)),
            None,
            None,
        )
        .unwrap();

        assert_eq!(
            aad,
            [
                0x54, 0x57, 0x4b, 0x31, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x07, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c,
                0x0d, 0x0e, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            ]
        );
    }

    #[test]
    fn account_root_tenant_dek_and_list_dek_roundtrip_with_distinct_contexts() {
        let master_key = key(0x42);
        let account_root_private = [0x10; ACCOUNT_ROOT_PRIVATE_KEY_LEN];
        let tenant_dek = key(0x20);
        let list_dek = key(0x30);
        let user_id = id(1);
        let tenant_id = id(2);
        let list_id = id(3);

        let wrapped_account_root = wrap_account_root_private_key_with_master_key(
            user_id,
            1,
            &account_root_private,
            &master_key,
        )
        .unwrap();
        let wrapped_tenant =
            wrap_tenant_root_dek_with_master_key(tenant_id, 1, &tenant_dek, &master_key).unwrap();
        let wrapped_list =
            wrap_list_dek_with_master_key(tenant_id, list_id, 1, &list_dek, &master_key).unwrap();

        assert_eq!(
            *unwrap_account_root_private_key_with_master_key(
                user_id,
                1,
                &wrapped_account_root,
                &master_key
            )
            .unwrap(),
            account_root_private
        );
        assert_eq!(
            unwrap_tenant_root_dek_with_master_key(tenant_id, 1, &wrapped_tenant, &master_key)
                .unwrap(),
            tenant_dek
        );
        assert_eq!(
            unwrap_list_dek_with_master_key(tenant_id, list_id, 1, &wrapped_list, &master_key)
                .unwrap(),
            list_dek
        );
        assert_eq!(
            unwrap_tenant_root_dek_with_master_key(tenant_id, 1, &wrapped_list, &master_key),
            Err(KeyHierarchyError::Crypto(CryptoError::DecryptionFailed))
        );
    }

    #[test]
    fn local_list_dek_wrap_is_bound_to_list_id() {
        let master_key = key(0x10);
        let list_dek = key(0x20);
        let tenant_id = id(1);
        let list_id = id(2);
        let wrapped =
            wrap_local_list_dek_with_master_key(tenant_id, list_id, 1, &list_dek, &master_key)
                .unwrap();

        assert_eq!(
            unwrap_local_list_dek_with_master_key(tenant_id, list_id, 1, &wrapped, &master_key)
                .unwrap(),
            list_dek
        );
        assert!(
            unwrap_local_list_dek_with_master_key(tenant_id, id(3), 1, &wrapped, &master_key)
                .is_err()
        );
    }

    #[test]
    fn local_tenant_root_dek_wrap_is_bound_to_tenant_id_and_local_context() {
        let master_key = key(0x10);
        let tenant_dek = key(0x20);
        let tenant_id = id(1);
        let wrapped =
            wrap_local_tenant_root_dek_with_master_key(tenant_id, 1, &tenant_dek, &master_key)
                .unwrap();

        assert_eq!(
            unwrap_local_tenant_root_dek_with_master_key(tenant_id, 1, &wrapped, &master_key)
                .unwrap(),
            tenant_dek
        );
        assert!(
            unwrap_local_tenant_root_dek_with_master_key(id(2), 1, &wrapped, &master_key).is_err()
        );
        assert!(
            unwrap_tenant_root_dek_with_master_key(tenant_id, 1, &wrapped, &master_key).is_err()
        );
        assert!(
            unwrap_local_tenant_root_dek_with_master_key(tenant_id, 1, &wrapped, &key(0x11))
                .is_err()
        );
    }
}

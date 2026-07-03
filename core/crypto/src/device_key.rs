//! Device Key (DK) の生成・保存抽象・ローカルDB鍵導出。
//!
//! `docs/03_技術仕様書.md` §4.3 / §5.3 / §7.1 に基づき、DKは32byte乱数として
//! OSキーチェーンへ保存し、SQLCipher用のローカルDB鍵はDKからHKDF-SHA256で導出する。

use rand::{rngs::OsRng, RngCore};
use thiserror::Error;

use crate::kdf::derive_key;

/// Device Key (DK) のバイト長。
pub const DEVICE_KEY_LEN: usize = 32;

/// SQLCipher用ローカルDB鍵をDKから導出する際のHKDF context。
///
/// バージョン付き文字列として固定し、将来の鍵用途追加や導出仕様変更と分離する。
pub const LOCAL_DB_KEY_INFO: &[u8] = b"todori/local-db-key/v1";

/// OSキーチェーン抽象が返すエラー。
#[derive(Debug, Error, PartialEq, Eq)]
pub enum KeyStoreError {
    /// プラットフォーム固有バックエンドの失敗。
    #[error("key store backend error: {0}")]
    Backend(String),
}

/// OSキーチェーンに保存する32byteのDevice Key (DK)を生成する。
pub fn generate_device_key() -> [u8; DEVICE_KEY_LEN] {
    let mut key = [0u8; DEVICE_KEY_LEN];
    OsRng.fill_bytes(&mut key);
    key
}

/// Device Key (DK) からSQLCipher用ローカルDB鍵を導出する。
pub fn derive_local_db_key(device_key: &[u8; DEVICE_KEY_LEN]) -> [u8; DEVICE_KEY_LEN] {
    derive_key(device_key, LOCAL_DB_KEY_INFO)
}

/// Device Key (DK) のOSキーチェーン保存抽象。
pub trait DeviceKeyStore {
    fn load(&self) -> Result<Option<[u8; DEVICE_KEY_LEN]>, KeyStoreError>;
    fn store(&mut self, key: &[u8; DEVICE_KEY_LEN]) -> Result<(), KeyStoreError>;
    fn delete(&mut self) -> Result<(), KeyStoreError>;
}

/// 保存済みDKを取得し、未生成なら新規生成して保存する。
pub fn ensure_device_key(
    store: &mut impl DeviceKeyStore,
) -> Result<[u8; DEVICE_KEY_LEN], KeyStoreError> {
    if let Some(key) = store.load()? {
        return Ok(key);
    }

    let key = generate_device_key();
    store.store(&key)?;
    Ok(key)
}

/// テストダブル兼デスクトップ開発用の暫定Device Key Store。
///
/// 本番のOSキーチェーン実装は後続タスクで行う。平文でメモリ保持するため本番使用禁止。
#[derive(Default)]
pub struct InMemoryDeviceKeyStore {
    key: Option<[u8; DEVICE_KEY_LEN]>,
}

impl InMemoryDeviceKeyStore {
    pub fn new() -> Self {
        Self::default()
    }
}

impl DeviceKeyStore for InMemoryDeviceKeyStore {
    fn load(&self) -> Result<Option<[u8; DEVICE_KEY_LEN]>, KeyStoreError> {
        Ok(self.key)
    }

    fn store(&mut self, key: &[u8; DEVICE_KEY_LEN]) -> Result<(), KeyStoreError> {
        self.key = Some(*key);
        Ok(())
    }

    fn delete(&mut self) -> Result<(), KeyStoreError> {
        self.key = None;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_device_key_returns_32_random_bytes() {
        let first = generate_device_key();
        let second = generate_device_key();

        assert_eq!(first.len(), DEVICE_KEY_LEN);
        assert_eq!(second.len(), DEVICE_KEY_LEN);
        assert_ne!(first, second);
    }

    #[test]
    fn derive_local_db_key_is_deterministic_and_context_is_fixed() {
        let device_key = [0x42; DEVICE_KEY_LEN];
        let expected = [
            52, 203, 119, 73, 63, 167, 63, 59, 54, 15, 231, 141, 31, 197, 89, 220, 75, 31, 214,
            157, 187, 18, 192, 167, 125, 52, 56, 209, 103, 156, 95, 166,
        ];

        assert_eq!(LOCAL_DB_KEY_INFO, b"todori/local-db-key/v1");
        assert_eq!(
            derive_local_db_key(&device_key),
            derive_local_db_key(&device_key)
        );
        assert_eq!(derive_local_db_key(&device_key), expected);
    }

    #[test]
    fn derive_local_db_key_differs_by_device_key() {
        let first = [0x11; DEVICE_KEY_LEN];
        let second = [0x22; DEVICE_KEY_LEN];

        assert_ne!(derive_local_db_key(&first), derive_local_db_key(&second));
    }

    #[test]
    fn ensure_device_key_generates_stores_and_reuses_key() {
        let mut store = InMemoryDeviceKeyStore::new();

        let first = ensure_device_key(&mut store).unwrap();
        let second = ensure_device_key(&mut store).unwrap();

        assert_eq!(first, second);
        assert_eq!(store.load().unwrap(), Some(first));
    }

    #[test]
    fn ensure_device_key_generates_new_key_after_delete() {
        let mut store = InMemoryDeviceKeyStore::new();

        let first = ensure_device_key(&mut store).unwrap();
        store.delete().unwrap();
        let second = ensure_device_key(&mut store).unwrap();

        assert_ne!(first, second);
        assert_eq!(store.load().unwrap(), Some(second));
    }
}

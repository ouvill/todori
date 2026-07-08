use std::{
    fs,
    path::{Path, PathBuf},
};

use todori_crypto::{ensure_device_key, DeviceKeyStore, KeyStoreError, DEVICE_KEY_LEN};

const DEVICE_KEY_FILE_NAME: &str = "device.key";
const SESSION_TOKEN_FILE_NAME: &str = "session.token";
const MASTER_KEY_WRAP_FILE_NAME: &str = "master_key.wrap";
#[cfg(any(target_os = "ios", target_os = "macos"))]
const KEYCHAIN_SERVICE: &str = "dev.todori.todori.device-key";
#[cfg(any(target_os = "ios", target_os = "macos"))]
const SESSION_TOKEN_KEYCHAIN_SERVICE: &str = "dev.todori.todori.session-token";
#[cfg(any(target_os = "ios", target_os = "macos"))]
const MASTER_KEY_WRAP_KEYCHAIN_SERVICE: &str = "dev.todori.todori.master-key-wrap";
#[cfg(any(target_os = "ios", target_os = "macos"))]
const KEYCHAIN_ACCOUNT: &str = "default";
#[cfg(any(target_os = "ios", target_os = "macos"))]
const ERR_SEC_ITEM_NOT_FOUND: i32 = -25300;
#[cfg(target_os = "macos")]
const ERR_SEC_MISSING_ENTITLEMENT: i32 = -34018;

pub(crate) fn load_or_create_device_key(
    db_dir: impl AsRef<Path>,
) -> Result<[u8; DEVICE_KEY_LEN], KeyStoreError> {
    let mut file_store = FileDeviceKeyStore::new(db_dir);

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        if is_flutter_test_process() {
            return ensure_device_key(&mut file_store);
        }

        let mut keychain_store = AppleKeychainDeviceKeyStore::new();
        ensure_device_key_with_migration(&mut keychain_store, &mut file_store)
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        ensure_device_key(&mut file_store)
    }
}

pub(crate) enum AccountSecretKind {
    SessionToken,
    MasterKeyWrap,
}

pub(crate) fn load_account_secret(
    db_dir: impl AsRef<Path>,
    kind: AccountSecretKind,
) -> Result<Option<Vec<u8>>, KeyStoreError> {
    let file_store = FileSecretStore::new(db_dir, kind.file_name());

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        if is_flutter_test_process() {
            return file_store.load();
        }
        AppleKeychainSecretStore::new(kind.keychain_service()).load()
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        file_store.load()
    }
}

pub(crate) fn store_account_secret(
    db_dir: impl AsRef<Path>,
    kind: AccountSecretKind,
    value: &[u8],
) -> Result<(), KeyStoreError> {
    let file_store = FileSecretStore::new(db_dir, kind.file_name());

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        if is_flutter_test_process() {
            return file_store.store(value);
        }
        AppleKeychainSecretStore::new(kind.keychain_service()).store(value)
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        file_store.store(value)
    }
}

pub(crate) fn delete_account_secret(
    db_dir: impl AsRef<Path>,
    kind: AccountSecretKind,
) -> Result<(), KeyStoreError> {
    let file_store = FileSecretStore::new(db_dir, kind.file_name());

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        if is_flutter_test_process() {
            return file_store.delete();
        }
        AppleKeychainSecretStore::new(kind.keychain_service()).delete()
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        file_store.delete()
    }
}

impl AccountSecretKind {
    fn file_name(&self) -> &'static str {
        match self {
            AccountSecretKind::SessionToken => SESSION_TOKEN_FILE_NAME,
            AccountSecretKind::MasterKeyWrap => MASTER_KEY_WRAP_FILE_NAME,
        }
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    fn keychain_service(&self) -> &'static str {
        match self {
            AccountSecretKind::SessionToken => SESSION_TOKEN_KEYCHAIN_SERVICE,
            AccountSecretKind::MasterKeyWrap => MASTER_KEY_WRAP_KEYCHAIN_SERVICE,
        }
    }
}

#[cfg(any(test, target_os = "ios", target_os = "macos"))]
pub(crate) fn ensure_device_key_with_migration(
    primary_store: &mut impl DeviceKeyStore,
    file_store: &mut impl DeviceKeyStore,
) -> Result<[u8; DEVICE_KEY_LEN], KeyStoreError> {
    if let Some(key) = primary_store.load()? {
        return Ok(key);
    }

    if let Some(file_key) = file_store.load()? {
        match primary_store.store(&file_key) {
            Ok(()) => {
                let _ = file_store.delete();
            }
            Err(_) => {
                return Ok(file_key);
            }
        }

        return Ok(file_key);
    }

    ensure_device_key(primary_store)
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
struct AppleKeychainSecretStore {
    service: String,
    account: String,
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
impl AppleKeychainSecretStore {
    fn new(service: impl Into<String>) -> Self {
        Self {
            service: service.into(),
            account: KEYCHAIN_ACCOUNT.to_string(),
        }
    }

    fn options(
        &self,
        backend: KeychainBackend,
    ) -> security_framework::base::Result<security_framework::passwords::PasswordOptions> {
        use security_framework::{
            access_control::{ProtectionMode, SecAccessControl},
            passwords::{AccessControlOptions, PasswordOptions},
        };

        let mut options = PasswordOptions::new_generic_password(&self.service, &self.account);
        options.set_access_synchronized(Some(false));
        match backend {
            KeychainBackend::DataProtection => {
                let access_control = SecAccessControl::create_with_protection(
                    Some(ProtectionMode::AccessibleAfterFirstUnlockThisDeviceOnly),
                    AccessControlOptions::empty().bits(),
                )?;
                options.set_access_control(access_control);
                options.use_protected_keychain();
            }
            #[cfg(target_os = "macos")]
            KeychainBackend::Legacy => {}
        }
        Ok(options)
    }

    fn load(&self) -> Result<Option<Vec<u8>>, KeyStoreError> {
        #[cfg(target_os = "macos")]
        {
            match self.load_from_backend(KeychainBackend::DataProtection) {
                Ok(bytes) => Ok(bytes),
                Err(error) if is_keychain_missing_entitlement(&error) => {
                    log_legacy_keychain_fallback();
                    self.load_from_backend(KeychainBackend::Legacy)
                        .map_err(keychain_error)
                }
                Err(error) => Err(keychain_error(error)),
            }
        }

        #[cfg(target_os = "ios")]
        {
            self.load_from_backend(KeychainBackend::DataProtection)
                .map_err(keychain_error)
        }
    }

    fn store(&self, value: &[u8]) -> Result<(), KeyStoreError> {
        #[cfg(target_os = "macos")]
        {
            match self.store_in_backend(KeychainBackend::DataProtection, value) {
                Ok(()) => Ok(()),
                Err(error) if is_keychain_missing_entitlement(&error) => {
                    log_legacy_keychain_fallback();
                    self.store_in_backend(KeychainBackend::Legacy, value)
                        .map_err(keychain_error)
                }
                Err(error) => Err(keychain_error(error)),
            }
        }

        #[cfg(target_os = "ios")]
        {
            self.store_in_backend(KeychainBackend::DataProtection, value)
                .map_err(keychain_error)
        }
    }

    fn delete(&self) -> Result<(), KeyStoreError> {
        #[cfg(target_os = "macos")]
        {
            let data_protection_error =
                match self.delete_from_backend(KeychainBackend::DataProtection) {
                    Ok(()) => None,
                    Err(error) if is_keychain_missing_entitlement(&error) => {
                        log_legacy_keychain_fallback();
                        None
                    }
                    Err(error) => Some(error),
                };
            let legacy_error = self.delete_from_backend(KeychainBackend::Legacy).err();
            if let Some(error) = data_protection_error {
                return Err(keychain_error(error));
            }
            if let Some(error) = legacy_error {
                return Err(keychain_error(error));
            }
            Ok(())
        }

        #[cfg(target_os = "ios")]
        {
            self.delete_from_backend(KeychainBackend::DataProtection)
                .map_err(keychain_error)
        }
    }

    fn load_from_backend(
        &self,
        backend: KeychainBackend,
    ) -> security_framework::base::Result<Option<Vec<u8>>> {
        match security_framework::passwords::generic_password(self.options(backend)?) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(error) if is_keychain_item_not_found(&error) => Ok(None),
            Err(error) => Err(error),
        }
    }

    fn store_in_backend(
        &self,
        backend: KeychainBackend,
        value: &[u8],
    ) -> security_framework::base::Result<()> {
        security_framework::passwords::set_generic_password_options(value, self.options(backend)?)
    }

    fn delete_from_backend(
        &self,
        backend: KeychainBackend,
    ) -> security_framework::base::Result<()> {
        match security_framework::passwords::delete_generic_password_options(self.options(backend)?)
        {
            Ok(()) => Ok(()),
            Err(error) if is_keychain_item_not_found(&error) => Ok(()),
            Err(error) => Err(error),
        }
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub struct AppleKeychainDeviceKeyStore {
    service: String,
    account: String,
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
impl AppleKeychainDeviceKeyStore {
    pub fn new() -> Self {
        Self::with_service_account(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
    }

    fn with_service_account(service: impl Into<String>, account: impl Into<String>) -> Self {
        Self {
            service: service.into(),
            account: account.into(),
        }
    }

    fn options(
        &self,
        backend: KeychainBackend,
    ) -> security_framework::base::Result<security_framework::passwords::PasswordOptions> {
        use security_framework::{
            access_control::{ProtectionMode, SecAccessControl},
            passwords::{AccessControlOptions, PasswordOptions},
        };

        let mut options = PasswordOptions::new_generic_password(&self.service, &self.account);
        options.set_access_synchronized(Some(false));
        match backend {
            KeychainBackend::DataProtection => {
                let access_control = SecAccessControl::create_with_protection(
                    Some(ProtectionMode::AccessibleAfterFirstUnlockThisDeviceOnly),
                    AccessControlOptions::empty().bits(),
                )?;
                options.set_access_control(access_control);
                options.use_protected_keychain();
            }
            #[cfg(target_os = "macos")]
            KeychainBackend::Legacy => {}
        }

        Ok(options)
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
#[derive(Clone, Copy)]
enum KeychainBackend {
    DataProtection,
    #[cfg(target_os = "macos")]
    Legacy,
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
impl Default for AppleKeychainDeviceKeyStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
impl DeviceKeyStore for AppleKeychainDeviceKeyStore {
    fn load(&self) -> Result<Option<[u8; DEVICE_KEY_LEN]>, KeyStoreError> {
        self.load_with_fallback()
    }

    fn store(&mut self, key: &[u8; DEVICE_KEY_LEN]) -> Result<(), KeyStoreError> {
        self.store_with_fallback(key)
    }

    fn delete(&mut self) -> Result<(), KeyStoreError> {
        self.delete_with_fallback()
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
impl AppleKeychainDeviceKeyStore {
    #[cfg(target_os = "macos")]
    fn load_with_fallback(&self) -> Result<Option<[u8; DEVICE_KEY_LEN]>, KeyStoreError> {
        match self.load_from_backend(KeychainBackend::DataProtection) {
            Ok(Some(bytes)) => key_from_keychain_bytes(bytes).map(Some),
            Ok(None) => self
                .load_from_backend(KeychainBackend::Legacy)
                .map_err(keychain_error)
                .and_then(|bytes| bytes.map(key_from_keychain_bytes).transpose()),
            Err(error) if is_keychain_missing_entitlement(&error) => {
                log_legacy_keychain_fallback();
                self.load_from_backend(KeychainBackend::Legacy)
                    .map_err(keychain_error)
                    .and_then(|bytes| bytes.map(key_from_keychain_bytes).transpose())
            }
            Err(error) => Err(keychain_error(error)),
        }
    }

    #[cfg(target_os = "ios")]
    fn load_with_fallback(&self) -> Result<Option<[u8; DEVICE_KEY_LEN]>, KeyStoreError> {
        self.load_from_backend(KeychainBackend::DataProtection)
            .map_err(keychain_error)
            .and_then(|bytes| bytes.map(key_from_keychain_bytes).transpose())
    }

    #[cfg(target_os = "macos")]
    fn store_with_fallback(&self, key: &[u8; DEVICE_KEY_LEN]) -> Result<(), KeyStoreError> {
        match self.store_in_backend(KeychainBackend::DataProtection, key) {
            Ok(()) => Ok(()),
            Err(error) if is_keychain_missing_entitlement(&error) => {
                log_legacy_keychain_fallback();
                self.store_in_backend(KeychainBackend::Legacy, key)
                    .map_err(keychain_error)
            }
            Err(error) => Err(keychain_error(error)),
        }
    }

    #[cfg(target_os = "ios")]
    fn store_with_fallback(&self, key: &[u8; DEVICE_KEY_LEN]) -> Result<(), KeyStoreError> {
        self.store_in_backend(KeychainBackend::DataProtection, key)
            .map_err(keychain_error)
    }

    #[cfg(target_os = "macos")]
    fn delete_with_fallback(&self) -> Result<(), KeyStoreError> {
        let data_protection_error = match self.delete_from_backend(KeychainBackend::DataProtection)
        {
            Ok(()) => None,
            Err(error) if is_keychain_missing_entitlement(&error) => {
                log_legacy_keychain_fallback();
                None
            }
            Err(error) => Some(error),
        };

        let legacy_error = self.delete_from_backend(KeychainBackend::Legacy).err();

        if let Some(error) = data_protection_error {
            return Err(keychain_error(error));
        }

        if let Some(error) = legacy_error {
            return Err(keychain_error(error));
        }

        Ok(())
    }

    #[cfg(target_os = "ios")]
    fn delete_with_fallback(&self) -> Result<(), KeyStoreError> {
        self.delete_from_backend(KeychainBackend::DataProtection)
            .map_err(keychain_error)
    }

    fn load_from_backend(
        &self,
        backend: KeychainBackend,
    ) -> security_framework::base::Result<Option<Vec<u8>>> {
        match security_framework::passwords::generic_password(self.options(backend)?) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(error) if is_keychain_item_not_found(&error) => Ok(None),
            Err(error) => Err(error),
        }
    }

    fn store_in_backend(
        &self,
        backend: KeychainBackend,
        key: &[u8; DEVICE_KEY_LEN],
    ) -> security_framework::base::Result<()> {
        security_framework::passwords::set_generic_password_options(key, self.options(backend)?)
    }

    fn delete_from_backend(
        &self,
        backend: KeychainBackend,
    ) -> security_framework::base::Result<()> {
        match security_framework::passwords::delete_generic_password_options(self.options(backend)?)
        {
            Ok(()) => Ok(()),
            Err(error) if is_keychain_item_not_found(&error) => Ok(()),
            Err(error) => Err(error),
        }
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn is_keychain_item_not_found(error: &security_framework::base::Error) -> bool {
    error.code() == ERR_SEC_ITEM_NOT_FOUND
}

#[cfg(target_os = "macos")]
fn is_keychain_missing_entitlement(error: &security_framework::base::Error) -> bool {
    error.code() == ERR_SEC_MISSING_ENTITLEMENT
}

#[cfg(target_os = "macos")]
fn log_legacy_keychain_fallback() {
    static LOG_ONCE: std::sync::Once = std::sync::Once::new();
    LOG_ONCE.call_once(|| eprintln!("keychain: legacy fallback"));
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn keychain_error(error: security_framework::base::Error) -> KeyStoreError {
    KeyStoreError::Backend(format!("Apple Keychain error code {}", error.code()))
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn key_from_keychain_bytes(bytes: Vec<u8>) -> Result<[u8; DEVICE_KEY_LEN], KeyStoreError> {
    if bytes.len() != DEVICE_KEY_LEN {
        return Err(KeyStoreError::Backend(format!(
            "invalid Keychain device key length: expected {DEVICE_KEY_LEN}, got {}",
            bytes.len()
        )));
    }

    let mut key = [0u8; DEVICE_KEY_LEN];
    key.copy_from_slice(&bytes);
    Ok(key)
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn is_flutter_test_process() -> bool {
    if std::env::var_os("FLUTTER_TEST").is_some() || std::env::var_os("DART_TEST").is_some() {
        return true;
    }

    std::env::current_exe()
        .ok()
        .and_then(|path| path.file_name().map(|name| name == "flutter_tester"))
        .unwrap_or(false)
}

/// Development-only Device Key Store backed by a plaintext file.
///
/// This stores the 32-byte DK as raw binary plaintext in `device.key`, so it
/// must not be used as the primary production store. It remains only as a
/// migration fallback for existing local development installs and as the
/// non-Apple development store.
pub struct FileDeviceKeyStore {
    path: PathBuf,
}

impl FileDeviceKeyStore {
    pub fn new(dir: impl AsRef<Path>) -> Self {
        Self {
            path: dir.as_ref().join(DEVICE_KEY_FILE_NAME),
        }
    }
}

struct FileSecretStore {
    path: PathBuf,
}

impl FileSecretStore {
    fn new(dir: impl AsRef<Path>, file_name: &str) -> Self {
        Self {
            path: dir.as_ref().join(file_name),
        }
    }

    fn load(&self) -> Result<Option<Vec<u8>>, KeyStoreError> {
        match fs::read(&self.path) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(KeyStoreError::Backend(error.to_string())),
        }
    }

    fn store(&self, value: &[u8]) -> Result<(), KeyStoreError> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .map_err(|error| KeyStoreError::Backend(error.to_string()))?;
        }

        fs::write(&self.path, value).map_err(|error| KeyStoreError::Backend(error.to_string()))
    }

    fn delete(&self) -> Result<(), KeyStoreError> {
        match fs::remove_file(&self.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(KeyStoreError::Backend(error.to_string())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakeDeviceKeyStore {
        key: Option<[u8; DEVICE_KEY_LEN]>,
        fail_store: bool,
        delete_count: usize,
    }

    impl FakeDeviceKeyStore {
        fn empty() -> Self {
            Self {
                key: None,
                fail_store: false,
                delete_count: 0,
            }
        }

        fn with_key(byte: u8) -> Self {
            Self {
                key: Some([byte; DEVICE_KEY_LEN]),
                fail_store: false,
                delete_count: 0,
            }
        }
    }

    impl DeviceKeyStore for FakeDeviceKeyStore {
        fn load(&self) -> Result<Option<[u8; DEVICE_KEY_LEN]>, KeyStoreError> {
            Ok(self.key)
        }

        fn store(&mut self, key: &[u8; DEVICE_KEY_LEN]) -> Result<(), KeyStoreError> {
            if self.fail_store {
                return Err(KeyStoreError::Backend("injected store failure".to_string()));
            }

            self.key = Some(*key);
            Ok(())
        }

        fn delete(&mut self) -> Result<(), KeyStoreError> {
            self.delete_count += 1;
            self.key = None;
            Ok(())
        }
    }

    fn assert_key_matches(actual: [u8; DEVICE_KEY_LEN], expected: [u8; DEVICE_KEY_LEN]) {
        assert!(actual == expected, "device key mismatch");
    }

    fn assert_optional_key_matches(
        actual: Option<[u8; DEVICE_KEY_LEN]>,
        expected: Option<[u8; DEVICE_KEY_LEN]>,
    ) {
        assert!(actual == expected, "device key mismatch");
    }

    #[test]
    fn migration_moves_file_key_to_primary_and_deletes_file_key() {
        let mut primary_store = FakeDeviceKeyStore::empty();
        let mut file_store = FakeDeviceKeyStore::with_key(0x42);

        let key = ensure_device_key_with_migration(&mut primary_store, &mut file_store).unwrap();

        assert_key_matches(key, [0x42; DEVICE_KEY_LEN]);
        assert_optional_key_matches(primary_store.key, Some([0x42; DEVICE_KEY_LEN]));
        assert!(file_store.key.is_none(), "file device key was not deleted");
        assert_eq!(file_store.delete_count, 1);
    }

    #[test]
    fn migration_keeps_file_key_when_primary_store_fails() {
        let mut primary_store = FakeDeviceKeyStore::empty();
        primary_store.fail_store = true;
        let mut file_store = FakeDeviceKeyStore::with_key(0x42);

        let key = ensure_device_key_with_migration(&mut primary_store, &mut file_store).unwrap();

        assert_key_matches(key, [0x42; DEVICE_KEY_LEN]);
        assert!(primary_store.key.is_none(), "primary device key was stored");
        assert_optional_key_matches(file_store.key, Some([0x42; DEVICE_KEY_LEN]));
        assert_eq!(file_store.delete_count, 0);
    }

    #[test]
    fn migration_uses_primary_key_when_both_stores_have_keys() {
        let mut primary_store = FakeDeviceKeyStore::with_key(0x11);
        let mut file_store = FakeDeviceKeyStore::with_key(0x22);

        let key = ensure_device_key_with_migration(&mut primary_store, &mut file_store).unwrap();

        assert_key_matches(key, [0x11; DEVICE_KEY_LEN]);
        assert_optional_key_matches(primary_store.key, Some([0x11; DEVICE_KEY_LEN]));
        assert_optional_key_matches(file_store.key, Some([0x22; DEVICE_KEY_LEN]));
        assert_eq!(file_store.delete_count, 0);
    }

    #[test]
    fn migration_generates_primary_key_when_both_stores_are_empty() {
        let mut primary_store = FakeDeviceKeyStore::empty();
        let mut file_store = FakeDeviceKeyStore::empty();

        let key = ensure_device_key_with_migration(&mut primary_store, &mut file_store).unwrap();

        assert_optional_key_matches(primary_store.key, Some(key));
        assert!(file_store.key.is_none(), "file device key was stored");
        assert_eq!(file_store.delete_count, 0);
    }

    #[cfg(target_os = "macos")]
    #[test]
    #[ignore = "touches the real macOS Keychain; run manually during platform verification"]
    fn apple_keychain_device_key_store_round_trips_real_keychain_item() {
        let service = format!("{}.test.{}", KEYCHAIN_SERVICE, std::process::id());
        let mut store =
            AppleKeychainDeviceKeyStore::with_service_account(service, KEYCHAIN_ACCOUNT);
        let key = [0x7b; DEVICE_KEY_LEN];

        let _ = store.delete();
        store.store(&key).unwrap();
        assert_optional_key_matches(store.load().unwrap(), Some(key));
        store.delete().unwrap();
        assert!(
            store.load().unwrap().is_none(),
            "device key was not deleted"
        );
    }
}

impl DeviceKeyStore for FileDeviceKeyStore {
    fn load(&self) -> Result<Option<[u8; DEVICE_KEY_LEN]>, KeyStoreError> {
        match fs::read(&self.path) {
            Ok(bytes) => {
                if bytes.len() != DEVICE_KEY_LEN {
                    return Err(KeyStoreError::Backend(format!(
                        "invalid device key length: expected {DEVICE_KEY_LEN}, got {}",
                        bytes.len()
                    )));
                }

                let mut key = [0u8; DEVICE_KEY_LEN];
                key.copy_from_slice(&bytes);
                Ok(Some(key))
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(KeyStoreError::Backend(error.to_string())),
        }
    }

    fn store(&mut self, key: &[u8; DEVICE_KEY_LEN]) -> Result<(), KeyStoreError> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .map_err(|error| KeyStoreError::Backend(error.to_string()))?;
        }

        fs::write(&self.path, key).map_err(|error| KeyStoreError::Backend(error.to_string()))
    }

    fn delete(&mut self) -> Result<(), KeyStoreError> {
        match fs::remove_file(&self.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(KeyStoreError::Backend(error.to_string())),
        }
    }
}

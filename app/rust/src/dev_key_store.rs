use std::{
    fs,
    path::{Path, PathBuf},
};

use todori_crypto::{DeviceKeyStore, KeyStoreError, DEVICE_KEY_LEN};

const DEVICE_KEY_FILE_NAME: &str = "device.key";

/// Development-only Device Key Store backed by a plaintext file.
///
/// This is a temporary development implementation. It stores the 32-byte DK as
/// raw binary plaintext in `device.key`, so it must not be used in production.
/// A later task will replace this with an OS keychain implementation such as
/// iOS Keychain.
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

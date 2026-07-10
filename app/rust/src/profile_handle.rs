use std::{
    future::Future,
    path::{Path, PathBuf},
    sync::OnceLock,
};

use todori_client::{ClientError, ClientProfile, ProfileConfig};

static PROFILE: OnceLock<ClientProfile> = OnceLock::new();

pub(crate) fn init_profile(db_dir: String, default_inbox_name: String) -> Result<(), String> {
    let requested_path = profile_db_path(&db_dir);
    if let Some(existing) = PROFILE.get() {
        return ensure_same_path(existing, &requested_path);
    }

    let candidate = ClientProfile::open(ProfileConfig::new(db_dir, default_inbox_name))
        .map_err(|error| error.to_string())?;
    match PROFILE.set(candidate) {
        Ok(()) => Ok(()),
        Err(candidate) => {
            let existing = PROFILE
                .get()
                .ok_or_else(|| "core already initialized".to_string())?;
            ensure_same_path(existing, candidate.db_path())
        }
    }
}

pub(crate) fn profile() -> Result<&'static ClientProfile, String> {
    PROFILE
        .get()
        .ok_or_else(|| "core is not initialized".to_string())
}

pub(crate) fn run_network<T>(
    future: impl Future<Output = Result<T, ClientError>>,
) -> Result<T, String> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|_| "client runtime is unavailable".to_string())?
        .block_on(future)
        .map_err(|error| error.to_string())
}

fn profile_db_path(db_dir: impl AsRef<Path>) -> PathBuf {
    db_dir.as_ref().join("todori.db")
}

fn ensure_same_path(profile: &ClientProfile, requested_path: &Path) -> Result<(), String> {
    if profile.db_path() == requested_path {
        Ok(())
    } else {
        Err("core already initialized with a different database path".to_string())
    }
}

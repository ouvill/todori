use std::{
    path::{Path, PathBuf},
    sync::OnceLock,
};

use todori_client::{LocalProfileConfig, TodoriClient};

static CLIENT: OnceLock<TodoriClient> = OnceLock::new();

pub(crate) fn init_client(db_dir: String, default_inbox_name: String) -> Result<(), String> {
    let requested_path = local_profile_db_path(&db_dir);
    if let Some(existing) = CLIENT.get() {
        return ensure_same_path(existing, &requested_path);
    }

    let candidate = TodoriClient::open(LocalProfileConfig::new(db_dir, default_inbox_name))
        .map_err(|error| error.to_string())?;
    match CLIENT.set(candidate) {
        Ok(()) => Ok(()),
        Err(candidate) => {
            let existing = CLIENT
                .get()
                .ok_or_else(|| "core already initialized".to_string())?;
            ensure_same_path(existing, candidate.db_path())
        }
    }
}

pub(crate) fn client() -> Result<&'static TodoriClient, String> {
    CLIENT
        .get()
        .ok_or_else(|| "core is not initialized".to_string())
}

fn local_profile_db_path(db_dir: impl AsRef<Path>) -> PathBuf {
    db_dir.as_ref().join("todori.db")
}

fn ensure_same_path(client: &TodoriClient, requested_path: &Path) -> Result<(), String> {
    if client.db_path() == requested_path {
        Ok(())
    } else {
        Err("core already initialized with a different database path".to_string())
    }
}

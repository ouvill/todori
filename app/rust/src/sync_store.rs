use std::path::{Path, PathBuf};

use todori_domain::{List, Task, Uuid};
use todori_storage::{
    open_encrypted, ListRepository, NewSyncOutboxEntry, SettingsRepository, SqliteListRepository,
    SqliteSettingsRepository, SqliteSyncStateRepository, SqliteTaskRepository, StorageError,
    SyncStateRepository, TaskRepository,
};
use todori_sync::{LocalSyncOutboxEntry, LocalSyncStore, NewLocalSyncOutboxEntry};

pub(crate) struct BridgeSyncStore {
    db_path: PathBuf,
    db_key: [u8; 32],
}

impl BridgeSyncStore {
    pub(crate) fn new(db_path: PathBuf, db_key: [u8; 32]) -> Self {
        Self { db_path, db_key }
    }
}

impl LocalSyncStore for BridgeSyncStore {
    fn list_outbox(&mut self, limit: usize) -> Result<Vec<LocalSyncOutboxEntry>, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .list_outbox(limit)
                .map(|entries| {
                    entries
                        .into_iter()
                        .map(|entry| LocalSyncOutboxEntry {
                            id: entry.id,
                            record_id: entry.record_id,
                            collection: entry.collection,
                            hlc: entry.hlc,
                            deleted: entry.deleted,
                            blob: entry.blob,
                            created_at: entry.created_at,
                        })
                        .collect()
                })
                .map_err(|error| error.to_string())
        })
    }

    fn has_outbox_entry(&mut self, collection: &str, record_id: Uuid) -> Result<bool, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .has_outbox_entry(collection, record_id)
                .map_err(|error| error.to_string())
        })
    }

    fn ack_outbox(&mut self, id: i64) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository.ack_outbox(id).map_err(|error| error.to_string())
        })
    }

    fn get_cursor_seq(&mut self, name: &str) -> Result<Option<i64>, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .get_cursor(name)
                .map(|cursor| cursor.map(|cursor| cursor.seq))
                .map_err(|error| error.to_string())
        })
    }

    fn set_cursor(&mut self, name: &str, seq: i64, updated_at: i64) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .set_cursor(name, seq, updated_at)
                .map_err(|error| error.to_string())
        })
    }

    fn delete_cursor(&mut self, name: &str) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .delete_cursor(name)
                .map_err(|error| error.to_string())
        })
    }

    fn get_setting(&mut self, key: &str) -> Result<Option<String>, String> {
        with_settings_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .get_setting(key)
                .map_err(|error| error.to_string())
        })
    }

    fn set_setting(&mut self, key: &str, value: &str, updated_at: i64) -> Result<(), String> {
        with_settings_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .set_setting(key, value, updated_at)
                .map_err(|error| error.to_string())
        })
    }

    fn enqueue_outbox(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .enqueue_outbox(NewSyncOutboxEntry {
                    record_id: entry.record_id,
                    collection: entry.collection,
                    hlc: entry.hlc,
                    deleted: entry.deleted,
                    blob: entry.blob,
                    created_at: entry.created_at,
                })
                .map(|_| ())
                .map_err(|error| error.to_string())
        })
    }

    fn get_record_state(
        &mut self,
        collection: &str,
        record_id: Uuid,
    ) -> Result<Option<String>, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .get_record_state(collection, record_id)
                .map_err(|error| error.to_string())
        })
    }

    fn upsert_record_state(
        &mut self,
        collection: &str,
        record_id: Uuid,
        plaintext_json: &str,
        updated_at: i64,
    ) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .upsert_record_state(collection, record_id, plaintext_json, updated_at)
                .map_err(|error| error.to_string())
        })
    }

    fn delete_record_state(&mut self, collection: &str, record_id: Uuid) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .delete_record_state(collection, record_id)
                .map_err(|error| error.to_string())
        })
    }

    fn default_list_id(&mut self) -> Result<Option<Uuid>, String> {
        with_list_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .get_default()
                .map(|list| list.map(|list| list.id))
                .map_err(|error| error.to_string())
        })
    }

    fn get_list(&mut self, id: Uuid) -> Result<Option<List>, String> {
        with_list_repository(&self.db_path, &self.db_key, |repository| {
            match repository.get(id) {
                Ok(list) => Ok(Some(list)),
                Err(StorageError::NotFound(_)) => Ok(None),
                Err(error) => Err(error.to_string()),
            }
        })
    }

    fn upsert_list_for_sync(&mut self, list: List) -> Result<(), String> {
        with_list_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .upsert_for_sync(list)
                .map_err(|error| error.to_string())
        })
    }

    fn delete_list_with_tasks_for_sync(&mut self, list_id: Uuid) -> Result<usize, String> {
        with_list_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .delete_with_tasks_for_sync(list_id)
                .map_err(|error| error.to_string())
        })
    }

    fn get_task(&mut self, id: Uuid) -> Result<Option<Task>, String> {
        with_task_repository(&self.db_path, &self.db_key, |repository| {
            match repository.get(id) {
                Ok(task) => Ok(Some(task)),
                Err(StorageError::NotFound(_)) => Ok(None),
                Err(error) => Err(error.to_string()),
            }
        })
    }

    fn upsert_task_for_sync(&mut self, task: Task) -> Result<(), String> {
        with_task_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .upsert_for_sync(task)
                .map_err(|error| error.to_string())
        })
    }

    fn delete_task_subtree_for_sync(&mut self, task_id: Uuid) -> Result<usize, String> {
        with_task_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .delete_subtree_for_sync(task_id)
                .map_err(|error| error.to_string())
        })
    }
}

fn with_sync_repository<T>(
    db_path: &Path,
    db_key: &[u8; 32],
    f: impl FnOnce(&mut SqliteSyncStateRepository) -> Result<T, String>,
) -> Result<T, String> {
    let connection = open_encrypted(db_path, db_key).map_err(|error| error.to_string())?;
    let mut repository = SqliteSyncStateRepository::new(connection);
    f(&mut repository)
}

fn with_settings_repository<T>(
    db_path: &Path,
    db_key: &[u8; 32],
    f: impl FnOnce(&mut SqliteSettingsRepository) -> Result<T, String>,
) -> Result<T, String> {
    let connection = open_encrypted(db_path, db_key).map_err(|error| error.to_string())?;
    let mut repository = SqliteSettingsRepository::new(connection);
    f(&mut repository)
}

fn with_task_repository<T>(
    db_path: &Path,
    db_key: &[u8; 32],
    f: impl FnOnce(&mut SqliteTaskRepository) -> Result<T, String>,
) -> Result<T, String> {
    let connection = open_encrypted(db_path, db_key).map_err(|error| error.to_string())?;
    let mut repository = SqliteTaskRepository::new(connection);
    f(&mut repository)
}

fn with_list_repository<T>(
    db_path: &Path,
    db_key: &[u8; 32],
    f: impl FnOnce(&mut SqliteListRepository) -> Result<T, String>,
) -> Result<T, String> {
    let connection = open_encrypted(db_path, db_key).map_err(|error| error.to_string())?;
    let mut repository = SqliteListRepository::new(connection);
    f(&mut repository)
}

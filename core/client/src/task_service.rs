use std::path::{Path, PathBuf};

use thiserror::Error;
use todori_domain::{update_due_at, update_note, update_priority, update_title, List, Task, Uuid};
use todori_storage::{
    open_encrypted, NewSyncOutboxEntry, SqliteWriteTx, StorageError, TaskUndoOperation,
};
use todori_sync::{
    enqueue_list_sync, enqueue_task_sync, LocalMutationSyncStore, LocalSyncKeys,
    NewLocalSyncOutboxEntry,
};

#[derive(Debug, Error)]
pub enum ClientError {
    #[error("storage operation failed: {0}")]
    Storage(#[from] StorageError),
    #[error("domain operation failed: {0}")]
    Domain(#[from] todori_domain::DomainError),
    #[error("local sync preparation failed")]
    Sync,
    #[error("local sync key is unavailable for list {0}")]
    MissingListKey(Uuid),
}

#[derive(Debug, Clone)]
pub struct LocalMutationContext {
    pub device_id: String,
    pub keys: LocalSyncKeys,
}

#[derive(Debug, Clone)]
pub struct UpdateTaskInput {
    pub task_id: Uuid,
    pub title: String,
    pub note: String,
    pub priority: i32,
    pub due_at: Option<i64>,
    pub now_ms: i64,
}

pub struct Client {
    pub(crate) db_path: PathBuf,
    pub(crate) db_key: [u8; 32],
}

impl Client {
    pub fn new(db_path: impl Into<PathBuf>, db_key: [u8; 32]) -> Self {
        Self {
            db_path: db_path.into(),
            db_key,
        }
    }

    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    pub fn update_task(
        &self,
        input: UpdateTaskInput,
        sync: &LocalMutationContext,
    ) -> Result<Task, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let before = transaction.get_task(input.task_id)?;
        if !sync.keys.contains_list(before.list_id) {
            return Err(ClientError::MissingListKey(before.list_id));
        }
        let task = update_title(before.clone(), input.title, input.now_ms)?;
        let task = update_note(task, input.note, input.now_ms)?;
        let task = update_priority(task, input.priority, input.now_ms)?;
        let updated = update_due_at(task, input.due_at, input.now_ms)?;

        transaction.update_with_undo(
            before,
            updated.clone(),
            TaskUndoOperation::Edit,
            input.now_ms,
        )?;
        enqueue_task_in_transaction(&mut transaction, sync, &updated, false, input.now_ms)?;
        transaction.commit()?;
        Ok(updated)
    }
}

pub(crate) fn enqueue_task_in_transaction(
    transaction: &mut SqliteWriteTx<'_>,
    sync: &LocalMutationContext,
    task: &Task,
    deleted: bool,
    now_ms: i64,
) -> Result<(), ClientError> {
    let mut store = TransactionalMutationStore { transaction };
    let mut now = || Ok(now_ms);
    enqueue_task_sync(
        &mut store,
        &sync.keys,
        &sync.device_id,
        task,
        deleted,
        &mut now,
    )
    .map_err(|_| ClientError::Sync)
}

pub(crate) fn enqueue_list_in_transaction(
    transaction: &mut SqliteWriteTx<'_>,
    sync: &LocalMutationContext,
    list: &List,
    deleted: bool,
    now_ms: i64,
) -> Result<(), ClientError> {
    let mut store = TransactionalMutationStore { transaction };
    let mut now = || Ok(now_ms);
    enqueue_list_sync(
        &mut store,
        &sync.keys,
        &sync.device_id,
        list,
        deleted,
        &mut now,
    )
    .map_err(|_| ClientError::Sync)
}

struct TransactionalMutationStore<'transaction, 'connection> {
    transaction: &'transaction mut SqliteWriteTx<'connection>,
}

impl LocalMutationSyncStore for TransactionalMutationStore<'_, '_> {
    fn has_outbox_entry(&mut self, collection: &str, record_id: Uuid) -> Result<bool, String> {
        self.transaction
            .has_outbox_entry(collection, record_id)
            .map_err(|error| error.to_string())
    }

    fn get_setting(&mut self, key: &str) -> Result<Option<String>, String> {
        self.transaction
            .get_setting(key)
            .map_err(|error| error.to_string())
    }

    fn set_setting(&mut self, key: &str, value: &str, updated_at: i64) -> Result<(), String> {
        self.transaction
            .set_setting(key, value, updated_at)
            .map_err(|error| error.to_string())
    }

    fn enqueue_outbox(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String> {
        self.transaction
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
    }

    fn get_record_state(
        &mut self,
        collection: &str,
        record_id: Uuid,
    ) -> Result<Option<String>, String> {
        self.transaction
            .get_record_state(collection, record_id)
            .map_err(|error| error.to_string())
    }

    fn upsert_record_state(
        &mut self,
        collection: &str,
        record_id: Uuid,
        plaintext_json: &str,
        updated_at: i64,
    ) -> Result<(), String> {
        self.transaction
            .upsert_record_state(collection, record_id, plaintext_json, updated_at)
            .map_err(|error| error.to_string())
    }

    fn delete_record_state(&mut self, collection: &str, record_id: Uuid) -> Result<(), String> {
        self.transaction
            .delete_record_state(collection, record_id)
            .map_err(|error| error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;
    use todori_domain::{new_list, new_task};
    use todori_storage::{
        ListRepository, SettingsRepository, SqliteListRepository, SqliteSettingsRepository,
        SqliteSyncStateRepository, SqliteTaskRepository, SyncStateRepository, TaskRepository,
    };
    use todori_sync::{Hlc, LocalSyncKeys, SYNC_LOCAL_HLC_SETTING_KEY, TASKS_COLLECTION};

    use super::*;

    const DB_KEY: [u8; 32] = [0x83; 32];
    const BASE_MS: i64 = 1_799_000_000_000;

    struct Fixture {
        _temp_dir: TempDir,
        client: Client,
        task: Task,
        sync: LocalMutationContext,
    }

    fn fixture() -> Fixture {
        let temp_dir = TempDir::new().unwrap();
        let db_path = temp_dir.path().join("client.sqlite3");
        let list = new_list("Inbox".to_string(), "a0".to_string(), BASE_MS).unwrap();
        let task = new_task(
            list.id,
            None,
            "before".to_string(),
            "a0".to_string(),
            BASE_MS,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        let mut lists = SqliteListRepository::new(connection);
        lists.insert(list.clone()).unwrap();
        drop(lists);
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        let mut tasks = SqliteTaskRepository::new(connection);
        tasks.insert(task.clone()).unwrap();
        drop(tasks);
        let baseline_hlc = Hlc {
            wall_ms: BASE_MS - 1_000,
            counter: 0,
            device_id: "device-a".to_string(),
        }
        .encode()
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        let mut settings = SqliteSettingsRepository::new(connection);
        settings
            .set_setting(SYNC_LOCAL_HLC_SETTING_KEY, &baseline_hlc, BASE_MS)
            .unwrap();
        drop(settings);
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        let mut sync_state = SqliteSyncStateRepository::new(connection);
        sync_state
            .upsert_record_state(TASKS_COLLECTION, task.id, "baseline", BASE_MS)
            .unwrap();

        Fixture {
            _temp_dir: temp_dir,
            client: Client::new(db_path, DB_KEY),
            task,
            sync: LocalMutationContext {
                device_id: "device-a".to_string(),
                keys: LocalSyncKeys {
                    list_deks: vec![(list.id, [0x44; 32])],
                },
            },
        }
    }

    fn update_input(task_id: Uuid) -> UpdateTaskInput {
        UpdateTaskInput {
            task_id,
            title: "after".to_string(),
            note: "atomic".to_string(),
            priority: 2,
            due_at: Some(BASE_MS + 60_000),
            now_ms: BASE_MS + 1_000,
        }
    }

    #[test]
    fn task_update_commits_domain_undo_hlc_outbox_and_record_state_together() {
        let fixture = fixture();
        let updated = fixture
            .client
            .update_task(update_input(fixture.task.id), &fixture.sync)
            .unwrap();
        assert_eq!(updated.title, "after");

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        assert_eq!(tasks.get(fixture.task.id).unwrap().title, "after");
        assert!(tasks.latest_unconsumed_undo().unwrap().is_some());
        drop(tasks);

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let settings = SqliteSettingsRepository::new(connection);
        assert!(settings
            .get_setting(SYNC_LOCAL_HLC_SETTING_KEY)
            .unwrap()
            .is_some());
        drop(settings);

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let sync = SqliteSyncStateRepository::new(connection);
        assert_eq!(sync.list_outbox(10).unwrap().len(), 1);
        assert_ne!(
            sync.get_record_state(TASKS_COLLECTION, fixture.task.id)
                .unwrap()
                .as_deref(),
            Some("baseline")
        );
    }

    #[test]
    fn outbox_failure_rolls_back_domain_undo_hlc_and_record_state() {
        assert_atomic_rollback(
            "CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_outbox BEGIN SELECT RAISE(ABORT, 'fail outbox'); END;",
        );
    }

    #[test]
    fn record_state_failure_rolls_back_domain_undo_hlc_and_outbox() {
        assert_atomic_rollback(
            "CREATE TRIGGER fail_state BEFORE UPDATE ON sync_record_states BEGIN SELECT RAISE(ABORT, 'fail state'); END;",
        );
    }

    #[test]
    fn missing_list_key_rolls_back_without_domain_change() {
        let fixture = fixture();
        let missing = LocalMutationContext {
            device_id: "device-a".to_string(),
            keys: LocalSyncKeys::default(),
        };
        let error = fixture
            .client
            .update_task(update_input(fixture.task.id), &missing)
            .unwrap_err();
        assert!(matches!(error, ClientError::MissingListKey(_)));

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        assert_eq!(tasks.get(fixture.task.id).unwrap().title, "before");
        assert!(tasks.latest_unconsumed_undo().unwrap().is_none());
    }

    fn assert_atomic_rollback(trigger_sql: &str) {
        let fixture = fixture();
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        connection.execute_batch(trigger_sql).unwrap();
        drop(connection);

        assert!(fixture
            .client
            .update_task(update_input(fixture.task.id), &fixture.sync)
            .is_err());

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        assert_eq!(tasks.get(fixture.task.id).unwrap().title, "before");
        assert!(tasks.latest_unconsumed_undo().unwrap().is_none());
        drop(tasks);

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let settings = SqliteSettingsRepository::new(connection);
        let stored_hlc = settings
            .get_setting(SYNC_LOCAL_HLC_SETTING_KEY)
            .unwrap()
            .unwrap();
        assert_eq!(Hlc::decode(&stored_hlc).unwrap().wall_ms, BASE_MS - 1_000);
        drop(settings);

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let sync = SqliteSyncStateRepository::new(connection);
        assert!(sync.list_outbox(10).unwrap().is_empty());
        assert_eq!(
            sync.get_record_state(TASKS_COLLECTION, fixture.task.id)
                .unwrap()
                .as_deref(),
            Some("baseline")
        );
    }
}

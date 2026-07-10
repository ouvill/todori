//! `todori-storage`: ローカルストレージアクセス層。
//!
//! SQLCipherで暗号化されたSQLite上に `ListRepository` / `TaskRepository` を実装する
//! （`docs/03_技術仕様書.md` §5）。

use std::{path::Path, str::FromStr, time::Duration};

use rusqlite::{params, Connection, OptionalExtension, Transaction, TransactionBehavior};
use thiserror::Error;
use todori_domain::{fractional_index_after, new_default_list, List, Task, TaskStatus, Uuid};

const SCHEMA: &str = include_str!("schema.sql");
const BASELINE_SCHEMA_VERSION: i32 = 1;
pub const LATEST_SCHEMA_VERSION: i32 = 14;
const LOCAL_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(5);

const MIGRATIONS: &[Migration] = &[
    Migration {
        target_version: 2,
        name: "add_lists_archived_at",
        apply: add_lists_archived_at,
    },
    Migration {
        target_version: 3,
        name: "add_lists_is_default",
        apply: add_lists_is_default,
    },
    Migration {
        target_version: 4,
        name: "rebuild_tasks_fts_triggers",
        apply: rebuild_tasks_fts_triggers,
    },
    Migration {
        target_version: 5,
        name: "add_settings",
        apply: add_settings,
    },
    Migration {
        target_version: 6,
        name: "add_reminders",
        apply: add_reminders,
    },
    Migration {
        target_version: 7,
        name: "add_performance_indexes",
        apply: add_performance_indexes,
    },
    Migration {
        target_version: 8,
        name: "add_sync_outbox_and_cursors",
        apply: add_sync_outbox_and_cursors,
    },
    Migration {
        target_version: 9,
        name: "add_sync_record_states",
        apply: add_sync_record_states,
    },
    Migration {
        target_version: 10,
        name: "add_local_crypto_cache",
        apply: add_local_crypto_cache,
    },
    Migration {
        target_version: 11,
        name: "replace_sync_metadata_v2",
        apply: replace_sync_metadata_v2,
    },
    Migration {
        target_version: 12,
        name: "normalize_fixed_width_ranks",
        apply: normalize_fixed_width_ranks,
    },
    Migration {
        target_version: 13,
        name: "add_sync_quarantine",
        apply: add_sync_quarantine,
    },
    Migration {
        target_version: 14,
        name: "add_pending_list_key_bundles",
        apply: add_pending_list_key_bundles,
    },
];

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("record not found: {0}")]
    NotFound(Uuid),
    #[error("invalid task status in database: {0}")]
    InvalidStatus(String),
    #[error("invalid undo operation in database: {0}")]
    InvalidUndoOperation(String),
    #[error("invalid sync state in database: {0}")]
    InvalidSyncState(String),
    #[error("invalid sync collection: {0}")]
    InvalidSyncCollection(String),
    #[error(
        "sync record {record_id} belongs to collection {existing}, not requested collection {requested}"
    )]
    SyncCollectionMismatch {
        record_id: Uuid,
        existing: String,
        requested: String,
    },
    #[error("invalid uuid in database: {0}")]
    InvalidUuid(#[from] uuid::Error),
    #[error("invalid task snapshot in database: {0}")]
    InvalidTaskSnapshot(#[from] serde_json::Error),
    #[error("undo entry already used: {0}")]
    UndoConsumed(Uuid),
    #[error("task changed after undo was created: {0}")]
    UndoConflict(Uuid),
    #[error("default list cannot be {operation}: {list_id}")]
    DefaultListProtected {
        operation: &'static str,
        list_id: Uuid,
    },
    #[error("database cannot be read with the provided SQLCipher key")]
    InvalidDatabaseKey,
    #[error("unsupported database schema version: found {found}, latest supported {latest}")]
    UnsupportedSchemaVersion { found: i32, latest: i32 },
    #[error("incompatible database schema: {0}")]
    IncompatibleSchema(String),
    #[error(
        "local profile is bound to tenant {bound_tenant_id}, not requested tenant {requested_tenant_id}"
    )]
    LocalProfileTenantMismatch {
        bound_tenant_id: Uuid,
        requested_tenant_id: Uuid,
    },
    #[error(
        "local profile is bound to user {bound_user_id}, not requested user {requested_user_id}"
    )]
    LocalProfileUserMismatch {
        bound_user_id: Uuid,
        requested_user_id: Uuid,
    },
    #[error("local crypto cache contains entries for a different tenant")]
    LocalCryptoCacheTenantMismatch,
    #[error(
        "failed to migrate database schema to version {target_version} ({migration}): {source}"
    )]
    MigrationFailed {
        target_version: i32,
        migration: &'static str,
        #[source]
        source: rusqlite::Error,
    },
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
}

#[derive(Clone, Copy)]
struct Migration {
    target_version: i32,
    name: &'static str,
    apply: fn(&Transaction<'_>) -> rusqlite::Result<()>,
}

/// Undo対象のタスク操作種別。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskUndoOperation {
    Delete,
    Complete,
    Edit,
}

/// ローカル専用のタスクUndo履歴。
#[derive(Debug, Clone, PartialEq)]
pub struct TaskUndoEntry {
    pub id: Uuid,
    pub operation_type: TaskUndoOperation,
    pub task_id: Uuid,
    pub list_id: Uuid,
    pub before_snapshot: Task,
    pub after_updated_at: i64,
    pub after_deleted_at: Option<i64>,
    pub after_completed_at: Option<i64>,
    pub created_at: i64,
    pub consumed_at: Option<i64>,
}

/// A task returned by the cross-list Home smart view, annotated with its
/// containing list name for UI context.
#[derive(Debug, Clone, PartialEq)]
pub struct HomeTask {
    pub task: Task,
    pub list_name: String,
    pub is_home_target: bool,
}

/// A local reminder scheduled on the device for a task.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reminder {
    pub id: Uuid,
    pub task_id: Uuid,
    pub remind_at: i64,
    pub snoozed_until: Option<i64>,
    pub created_at: i64,
}

/// 未ACKのrecord headに保持する暗号化済みsemantic state。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncOutboxState {
    Live { mutation_hlc: String, blob: Vec<u8> },
    Tombstone { delete_hlc: String },
}

/// recordごとにcoalesceされた未ACKのpush head。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncOutboxEntry {
    pub op_id: Uuid,
    pub record_id: Uuid,
    pub collection: String,
    pub base_revision_hlc: Option<String>,
    pub revision_hlc: String,
    pub state: SyncOutboxState,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewSyncOutboxEntry {
    pub op_id: Uuid,
    pub record_id: Uuid,
    pub collection: String,
    pub base_revision_hlc: Option<String>,
    pub revision_hlc: String,
    pub state: SyncOutboxState,
    pub created_at: i64,
}

/// 復号・mergeに使うlocal semantic state。tombstoneは平文を保持しない。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncRecordSemanticState {
    Live {
        mutation_hlc: String,
        plaintext_json: String,
    },
    Tombstone {
        delete_hlc: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncRecordState {
    pub record_id: Uuid,
    pub collection: String,
    pub current_revision_hlc: Option<String>,
    pub state: SyncRecordSemanticState,
    pub updated_at: i64,
}

/// テナントDB内のpull cursor。ローカルDBはテナントごとに分離する。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncCursor {
    pub name: String,
    pub seq: i64,
    pub updated_at: i64,
}

/// An encrypted remote head that could not yet be safely applied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncQuarantineEntry {
    pub record_id: Uuid,
    pub collection: String,
    pub seq: i64,
    pub revision_hlc: String,
    pub state: SyncOutboxState,
    pub reason: String,
    pub required_list_id: Option<Uuid>,
    pub first_failed_at: i64,
    pub last_failed_at: i64,
    pub attempt_count: i64,
}

/// SQLCipher内に保持するaccount-bound local profile identity。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalProfileBinding {
    pub tenant_id: Uuid,
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub bound_at: i64,
    pub updated_at: i64,
}

/// Master Keyでwrap済みのList DEK bundle。
///
/// `wrapped_list_dek`はopaque bytesとして保存し、このstorage層では復号しない。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalListKeyBundle {
    pub tenant_id: Uuid,
    pub list_id: Uuid,
    pub wrapped_list_dek: Vec<u8>,
    pub updated_at: i64,
}

/// Server upload待ちのopaqueなMK-wrapped List DEK bundle。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PendingListKeyBundle {
    pub tenant_id: Uuid,
    pub list_id: Uuid,
    pub wrapped_list_dek: Vec<u8>,
    pub created_at: i64,
}

/// account bindingとMK-wrapped List DEK cacheの永続化を担うリポジトリ。
pub trait LocalCryptoRepository {
    fn load_binding(&self) -> Result<Option<LocalProfileBinding>, StorageError>;
    fn bind_and_replace_bundles(
        &mut self,
        binding: LocalProfileBinding,
        bundles: &[LocalListKeyBundle],
    ) -> Result<(), StorageError>;
    fn load_bundles(&self, tenant_id: Uuid) -> Result<Vec<LocalListKeyBundle>, StorageError>;
}

/// タスクの永続化を担うリポジトリ。
///
/// SQLite(SQLCipher)実装は [`SqliteTaskRepository`] を参照。同期シグネチャのみを定義する。
pub trait TaskRepository {
    fn get(&self, id: Uuid) -> Result<Task, StorageError>;
    fn insert(&mut self, task: Task) -> Result<(), StorageError>;
    fn update(&mut self, task: Task) -> Result<(), StorageError>;
    fn list_all_for_sync(&self) -> Result<Vec<Task>, StorageError>;
    fn list_active_by_list(&self, list_id: Uuid) -> Result<Vec<Task>, StorageError>;
    fn list_home(
        &self,
        today_start_ms: i64,
        tomorrow_start_ms: i64,
    ) -> Result<Vec<HomeTask>, StorageError>;
    fn search_tasks(&self, query: &str) -> Result<Vec<Task>, StorageError>;
    fn count_descendants(&self, task_id: Uuid) -> Result<usize, StorageError>;
    fn delete_subtree(&mut self, task_id: Uuid) -> Result<usize, StorageError>;
}

/// リストの永続化を担うリポジトリ。
///
/// SQLite(SQLCipher)実装は [`SqliteListRepository`] を参照。
pub trait ListRepository {
    fn get(&self, id: Uuid) -> Result<List, StorageError>;
    fn insert(&mut self, list: List) -> Result<(), StorageError>;
    fn update(&mut self, list: List) -> Result<(), StorageError>;
    fn list_all(&self) -> Result<Vec<List>, StorageError>;
    fn list_archived(&self) -> Result<Vec<List>, StorageError>;
    fn get_default(&self) -> Result<Option<List>, StorageError>;
    fn ensure_default_list(&mut self, name: String, now_ms: i64) -> Result<List, StorageError>;
    fn count_tasks(&self, list_id: Uuid) -> Result<usize, StorageError>;
    fn delete_with_tasks(&mut self, list_id: Uuid) -> Result<usize, StorageError>;
}

/// 設定値の永続化を担うリポジトリ。
///
/// 値はSQLCipher暗号化DB内に保存し、キーごとの最新値だけを保持する。
pub trait SettingsRepository {
    fn get_setting(&self, key: &str) -> Result<Option<String>, StorageError>;
    fn set_setting(&mut self, key: &str, value: &str, updated_at: i64) -> Result<(), StorageError>;
}

/// リマインダーの永続化を担うリポジトリ。
pub trait ReminderRepository {
    fn set_task_reminder(
        &mut self,
        task_id: Uuid,
        remind_at: i64,
        created_at: i64,
    ) -> Result<Reminder, StorageError>;
    fn clear_task_reminders(&mut self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError>;
    fn list_task_reminders(&self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError>;
    fn list_task_subtree_reminders(&self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError>;
    fn list_list_reminders(&self, list_id: Uuid) -> Result<Vec<Reminder>, StorageError>;
    fn list_pending_reminders(&self, now_ms: i64) -> Result<Vec<Reminder>, StorageError>;
    fn snooze_reminder(
        &mut self,
        reminder_id: Uuid,
        snoozed_until: i64,
    ) -> Result<Reminder, StorageError>;
}

/// 同期outboxとpull cursorの永続化を担うリポジトリ。
pub trait SyncStateRepository {
    fn put_outbox_head(
        &mut self,
        entry: NewSyncOutboxEntry,
    ) -> Result<SyncOutboxEntry, StorageError>;
    fn list_outbox_heads(&self, limit: usize) -> Result<Vec<SyncOutboxEntry>, StorageError>;
    fn has_outbox_head(&self, collection: &str, record_id: Uuid) -> Result<bool, StorageError>;
    fn ack_outbox_op(&mut self, op_id: Uuid) -> Result<bool, StorageError>;
    fn get_record_state(
        &self,
        collection: &str,
        record_id: Uuid,
    ) -> Result<Option<SyncRecordState>, StorageError>;
    fn put_record_state(&mut self, state: SyncRecordState) -> Result<(), StorageError>;
    fn get_cursor(&self, name: &str) -> Result<Option<SyncCursor>, StorageError>;
    fn set_cursor(&mut self, name: &str, seq: i64, updated_at: i64) -> Result<(), StorageError>;
    fn delete_cursor(&mut self, name: &str) -> Result<(), StorageError>;
    fn put_quarantine(&mut self, entry: SyncQuarantineEntry) -> Result<(), StorageError>;
    fn list_quarantine(&self, limit: usize) -> Result<Vec<SyncQuarantineEntry>, StorageError>;
    fn list_replayable_quarantine(
        &self,
        after: Option<(i64, Uuid)>,
        limit: usize,
    ) -> Result<Vec<SyncQuarantineEntry>, StorageError>;
    fn delete_quarantine(&mut self, record_id: Uuid) -> Result<bool, StorageError>;
}

/// A short-lived SQLite write transaction shared by domain and sync-state writes.
///
/// The transaction starts with [`TransactionBehavior::Immediate`] so concurrent
/// desktop frontends serialize before reading and incrementing the local HLC.
/// Dropping this value without calling [`Self::commit`] rolls back every write.
pub struct SqliteWriteTx<'connection> {
    transaction: Transaction<'connection>,
}

impl<'connection> SqliteWriteTx<'connection> {
    pub fn begin(connection: &'connection mut Connection) -> Result<Self, StorageError> {
        let transaction = connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
        Ok(Self { transaction })
    }

    pub fn get_task(&self, id: Uuid) -> Result<Task, StorageError> {
        get_task_on(&self.transaction, id)
    }

    pub fn get_list(&self, id: Uuid) -> Result<List, StorageError> {
        get_list_on(&self.transaction, id)
    }

    pub fn list_active_tasks_by_list(&self, list_id: Uuid) -> Result<Vec<Task>, StorageError> {
        list_active_tasks_by_list_on(&self.transaction, list_id)
    }

    pub fn list_lists_including_archived(&self) -> Result<Vec<List>, StorageError> {
        let mut statement = self.transaction.prepare(
            "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                    is_default, created_at, updated_at
             FROM lists
             ORDER BY sort_order ASC, id ASC",
        )?;
        let lists = statement
            .query_map([], row_to_list)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(lists)
    }

    pub fn insert_task(&mut self, task: Task) -> Result<(), StorageError> {
        insert_task_on(&self.transaction, &task)
    }

    pub fn insert_list(&mut self, list: List) -> Result<(), StorageError> {
        insert_list_on(&self.transaction, &list)
    }

    pub fn put_local_list_key_bundle(
        &mut self,
        bundle: LocalListKeyBundle,
    ) -> Result<(), StorageError> {
        put_local_list_key_bundle_on(&self.transaction, &bundle)
    }

    pub fn put_pending_list_key_bundle(
        &mut self,
        bundle: PendingListKeyBundle,
    ) -> Result<(), StorageError> {
        put_pending_list_key_bundle_on(&self.transaction, &bundle)
    }

    pub fn update_task(&mut self, task: Task) -> Result<(), StorageError> {
        update_task_on(&self.transaction, &task)
    }

    pub fn update_list(&mut self, list: List) -> Result<(), StorageError> {
        update_list_on(&self.transaction, &list)
    }

    pub fn update_task_with_undo(
        &mut self,
        before: Task,
        after: Task,
        operation_type: TaskUndoOperation,
        created_at: i64,
    ) -> Result<TaskUndoEntry, StorageError> {
        update_task_with_undo_on(&self.transaction, before, after, operation_type, created_at)
    }

    pub fn update_with_undo(
        &mut self,
        before: Task,
        after: Task,
        operation_type: TaskUndoOperation,
        created_at: i64,
    ) -> Result<TaskUndoEntry, StorageError> {
        self.update_task_with_undo(before, after, operation_type, created_at)
    }

    pub fn undo_task_operation(
        &mut self,
        undo_id: Uuid,
        consumed_at: i64,
    ) -> Result<Task, StorageError> {
        undo_task_operation_on(&self.transaction, undo_id, consumed_at)
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>, StorageError> {
        get_setting_on(&self.transaction, key)
    }

    pub fn set_setting(
        &mut self,
        key: &str,
        value: &str,
        updated_at: i64,
    ) -> Result<(), StorageError> {
        set_setting_on(&self.transaction, key, value, updated_at)
    }

    pub fn put_outbox_head(
        &mut self,
        entry: NewSyncOutboxEntry,
    ) -> Result<SyncOutboxEntry, StorageError> {
        put_outbox_head_on(&self.transaction, entry)
    }

    pub fn list_outbox_heads(&self, limit: usize) -> Result<Vec<SyncOutboxEntry>, StorageError> {
        list_outbox_heads_on(&self.transaction, limit)
    }

    pub fn has_outbox_head(&self, collection: &str, record_id: Uuid) -> Result<bool, StorageError> {
        has_outbox_head_on(&self.transaction, collection, record_id)
    }

    pub fn ack_outbox_op(&mut self, op_id: Uuid) -> Result<bool, StorageError> {
        ack_outbox_op_on(&self.transaction, op_id)
    }

    pub fn get_record_state(
        &self,
        collection: &str,
        record_id: Uuid,
    ) -> Result<Option<SyncRecordState>, StorageError> {
        get_record_state_on(&self.transaction, collection, record_id)
    }

    pub fn put_record_state(&mut self, state: SyncRecordState) -> Result<(), StorageError> {
        put_record_state_on(&self.transaction, state)
    }

    pub fn commit(self) -> Result<(), StorageError> {
        self.transaction.commit().map_err(StorageError::from)
    }
}

/// An owned `BEGIN IMMEDIATE` transaction for sync runs that must move across
/// adapter boundaries without borrowing or self-referencing a connection.
///
/// Calling [`Self::commit`] or [`Self::rollback`] returns the opened
/// connection. Dropping an unfinished value rolls every write back.
pub struct OwnedSqliteWriteTx {
    connection: Option<Connection>,
}

impl OwnedSqliteWriteTx {
    pub fn begin(connection: Connection) -> Result<Self, StorageError> {
        connection.execute_batch("BEGIN IMMEDIATE")?;
        Ok(Self {
            connection: Some(connection),
        })
    }

    fn connection(&self) -> &Connection {
        self.connection
            .as_ref()
            .expect("active owned transaction always has a connection")
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>, StorageError> {
        get_setting_on(self.connection(), key)
    }

    pub fn set_setting(
        &mut self,
        key: &str,
        value: &str,
        updated_at: i64,
    ) -> Result<(), StorageError> {
        set_setting_on(self.connection(), key, value, updated_at)
    }

    pub fn put_outbox_head(
        &mut self,
        entry: NewSyncOutboxEntry,
    ) -> Result<SyncOutboxEntry, StorageError> {
        put_outbox_head_on(self.connection(), entry)
    }

    pub fn list_outbox_heads(&self, limit: usize) -> Result<Vec<SyncOutboxEntry>, StorageError> {
        list_outbox_heads_on(self.connection(), limit)
    }

    pub fn has_outbox_head(&self, collection: &str, record_id: Uuid) -> Result<bool, StorageError> {
        has_outbox_head_on(self.connection(), collection, record_id)
    }

    pub fn ack_outbox_op(&mut self, op_id: Uuid) -> Result<bool, StorageError> {
        ack_outbox_op_on(self.connection(), op_id)
    }

    pub fn ack_pending_list_key_bundle(
        &mut self,
        tenant_id: Uuid,
        list_id: Uuid,
        wrapped_list_dek: &[u8],
    ) -> Result<bool, StorageError> {
        ack_pending_list_key_bundle_on(self.connection(), tenant_id, list_id, wrapped_list_dek)
    }

    pub fn get_record_state(
        &self,
        collection: &str,
        record_id: Uuid,
    ) -> Result<Option<SyncRecordState>, StorageError> {
        get_record_state_on(self.connection(), collection, record_id)
    }

    pub fn put_record_state(&mut self, state: SyncRecordState) -> Result<(), StorageError> {
        put_record_state_on(self.connection(), state)
    }

    pub fn get_cursor(&self, name: &str) -> Result<Option<SyncCursor>, StorageError> {
        get_cursor_on(self.connection(), name)
    }

    pub fn set_cursor(
        &mut self,
        name: &str,
        seq: i64,
        updated_at: i64,
    ) -> Result<(), StorageError> {
        set_cursor_on(self.connection(), name, seq, updated_at)
    }

    pub fn delete_cursor(&mut self, name: &str) -> Result<(), StorageError> {
        delete_cursor_on(self.connection(), name)
    }

    pub fn put_quarantine(&mut self, entry: SyncQuarantineEntry) -> Result<(), StorageError> {
        put_quarantine_on(self.connection(), entry)
    }

    pub fn list_quarantine(&self, limit: usize) -> Result<Vec<SyncQuarantineEntry>, StorageError> {
        list_quarantine_on(self.connection(), limit)
    }

    pub fn list_replayable_quarantine(
        &self,
        after: Option<(i64, Uuid)>,
        limit: usize,
    ) -> Result<Vec<SyncQuarantineEntry>, StorageError> {
        list_replayable_quarantine_on(self.connection(), after, limit)
    }

    pub fn delete_quarantine(&mut self, record_id: Uuid) -> Result<bool, StorageError> {
        delete_quarantine_on(self.connection(), record_id)
    }

    pub fn default_list_id(&self) -> Result<Option<Uuid>, StorageError> {
        get_default_list_on(self.connection()).map(|list| list.map(|list| list.id))
    }

    pub fn get_list(&self, id: Uuid) -> Result<Option<List>, StorageError> {
        optional_not_found(get_list_on(self.connection(), id))
    }

    pub fn upsert_list_for_sync(&mut self, list: List) -> Result<(), StorageError> {
        upsert_list_for_sync_on(self.connection(), list)
    }

    pub fn delete_list_with_tasks_for_sync(
        &mut self,
        list_id: Uuid,
    ) -> Result<usize, StorageError> {
        delete_list_with_tasks_for_sync_on(self.connection(), list_id)
    }

    pub fn get_task(&self, id: Uuid) -> Result<Option<Task>, StorageError> {
        optional_not_found(get_task_on(self.connection(), id))
    }

    pub fn upsert_task_for_sync(&mut self, task: Task) -> Result<(), StorageError> {
        upsert_task_for_sync_on(self.connection(), task)
    }

    pub fn delete_task_subtree_for_sync(&mut self, task_id: Uuid) -> Result<usize, StorageError> {
        delete_task_subtree_on(self.connection(), task_id)
    }

    pub fn commit(mut self) -> Result<Connection, StorageError> {
        self.connection().execute_batch("COMMIT")?;
        Ok(self
            .connection
            .take()
            .expect("committed owned transaction has a connection"))
    }

    pub fn rollback(mut self) -> Result<Connection, StorageError> {
        self.connection().execute_batch("ROLLBACK")?;
        Ok(self
            .connection
            .take()
            .expect("rolled back owned transaction has a connection"))
    }
}

impl Drop for OwnedSqliteWriteTx {
    fn drop(&mut self) {
        if let Some(connection) = &self.connection {
            let _ = connection.execute_batch("ROLLBACK");
        }
    }
}

fn optional_not_found<T>(result: Result<T, StorageError>) -> Result<Option<T>, StorageError> {
    match result {
        Ok(value) => Ok(Some(value)),
        Err(StorageError::NotFound(_)) => Ok(None),
        Err(error) => Err(error),
    }
}

/// Opens a SQLCipher encrypted SQLite database and migrates it to the latest schema.
pub fn open_encrypted(path: &Path, key: &[u8; 32]) -> Result<Connection, StorageError> {
    let mut connection = Connection::open(path)?;
    connection.busy_timeout(LOCAL_DB_BUSY_TIMEOUT)?;
    apply_sqlcipher_key(&connection, key)?;
    ensure_schema(&mut connection, MIGRATIONS)?;
    Ok(connection)
}

fn apply_sqlcipher_key(connection: &Connection, key: &[u8; 32]) -> Result<(), StorageError> {
    let key_hex = hex::encode(key);
    connection.execute_batch(&format!("PRAGMA key = \"x'{key_hex}'\";"))?;
    Ok(())
}

fn ensure_schema(
    connection: &mut Connection,
    migrations: &[Migration],
) -> Result<(), StorageError> {
    let mut user_version =
        read_user_version(connection).map_err(|_| StorageError::InvalidDatabaseKey)?;
    if user_version > LATEST_SCHEMA_VERSION {
        return Err(StorageError::UnsupportedSchemaVersion {
            found: user_version,
            latest: LATEST_SCHEMA_VERSION,
        });
    }

    if user_version == 0 {
        user_version = ensure_baseline_schema(connection)?;
    }

    if user_version > LATEST_SCHEMA_VERSION {
        return Err(StorageError::UnsupportedSchemaVersion {
            found: user_version,
            latest: LATEST_SCHEMA_VERSION,
        });
    }

    apply_pending_migrations(connection, user_version, migrations)?;
    Ok(())
}

fn read_user_version(connection: &Connection) -> rusqlite::Result<i32> {
    connection.query_row("PRAGMA user_version", [], |row| row.get(0))
}

fn ensure_baseline_schema(connection: &mut Connection) -> Result<i32, StorageError> {
    if has_user_schema_objects(connection)? {
        validate_baseline_v1_schema(connection)?;
    }

    let transaction = connection.transaction()?;
    transaction.execute_batch(SCHEMA)?;
    set_user_version(&transaction, BASELINE_SCHEMA_VERSION)?;
    transaction.commit()?;

    Ok(BASELINE_SCHEMA_VERSION)
}

fn apply_pending_migrations(
    connection: &mut Connection,
    current_version: i32,
    migrations: &[Migration],
) -> Result<(), StorageError> {
    if current_version == LATEST_SCHEMA_VERSION {
        return Ok(());
    }

    let pending = migrations
        .iter()
        .filter(|migration| migration.target_version > current_version)
        .collect::<Vec<_>>();
    if pending.is_empty() {
        return Err(StorageError::IncompatibleSchema(format!(
            "missing migration from version {current_version} to {LATEST_SCHEMA_VERSION}"
        )));
    }

    for (expected_version, migration) in (current_version + 1..).zip(pending.iter()) {
        if migration.target_version != expected_version {
            return Err(StorageError::IncompatibleSchema(format!(
                "missing migration to version {expected_version}"
            )));
        }
    }

    let transaction = connection.transaction()?;
    let mut final_migration = pending[0];
    for migration in pending {
        final_migration = migration;
        (migration.apply)(&transaction).map_err(|source| StorageError::MigrationFailed {
            target_version: migration.target_version,
            migration: migration.name,
            source,
        })?;
        set_user_version(&transaction, migration.target_version).map_err(|source| {
            StorageError::MigrationFailed {
                target_version: migration.target_version,
                migration: migration.name,
                source,
            }
        })?;
    }
    transaction
        .commit()
        .map_err(|source| StorageError::MigrationFailed {
            target_version: final_migration.target_version,
            migration: final_migration.name,
            source,
        })?;

    Ok(())
}

fn set_user_version(connection: &Connection, version: i32) -> rusqlite::Result<()> {
    connection.execute_batch(&format!("PRAGMA user_version = {version};"))
}

fn add_lists_archived_at(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch("ALTER TABLE lists ADD COLUMN archived_at INTEGER NULL;")
}

fn add_lists_is_default(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "ALTER TABLE lists ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0;
         UPDATE lists
         SET is_default = 1
         WHERE id = (
             SELECT id
             FROM lists
             WHERE archived_at IS NULL
             ORDER BY sort_order ASC, id ASC
             LIMIT 1
         );
         CREATE UNIQUE INDEX idx_lists_single_default
             ON lists(is_default)
             WHERE is_default = 1;",
    )
}

fn rebuild_tasks_fts_triggers(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "DROP TRIGGER IF EXISTS tasks_fts_ai;
         DROP TRIGGER IF EXISTS tasks_fts_au;
         DROP TRIGGER IF EXISTS tasks_fts_au_delete;
         DROP TRIGGER IF EXISTS tasks_fts_au_insert;
         DROP TRIGGER IF EXISTS tasks_fts_ad;
         DROP TABLE IF EXISTS tasks_fts;

         CREATE VIRTUAL TABLE tasks_fts USING fts5(
             task_id UNINDEXED,
             title,
             note,
             tokenize = 'unicode61'
         );

         INSERT INTO tasks_fts(task_id, title, note)
         SELECT id, title, note
         FROM tasks
         WHERE deleted_at IS NULL;

         CREATE TRIGGER tasks_fts_ai
         AFTER INSERT ON tasks
         WHEN NEW.deleted_at IS NULL
         BEGIN
             INSERT INTO tasks_fts(task_id, title, note)
             VALUES (NEW.id, NEW.title, NEW.note);
         END;

         CREATE TRIGGER tasks_fts_au
         AFTER UPDATE OF id, title, note, deleted_at ON tasks
         BEGIN
             DELETE FROM tasks_fts WHERE task_id = OLD.id;
             INSERT INTO tasks_fts(task_id, title, note)
             SELECT NEW.id, NEW.title, NEW.note
             WHERE NEW.deleted_at IS NULL;
         END;

         CREATE TRIGGER tasks_fts_ad
         AFTER DELETE ON tasks
         BEGIN
             DELETE FROM tasks_fts WHERE task_id = OLD.id;
         END;",
    )
}

fn add_settings(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE settings (
             key TEXT PRIMARY KEY,
             value TEXT NOT NULL,
             updated_at INTEGER NOT NULL
         );",
    )
}

fn add_reminders(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE IF NOT EXISTS reminders (
             id TEXT PRIMARY KEY NOT NULL,
             task_id TEXT NOT NULL,
             remind_at INTEGER NOT NULL,
             snoozed_until INTEGER,
             created_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS idx_reminders_task_id ON reminders(task_id);
         CREATE INDEX IF NOT EXISTS idx_reminders_pending
             ON reminders(snoozed_until, remind_at);",
    )
}

fn add_performance_indexes(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE INDEX IF NOT EXISTS idx_tasks_list_sort_order
             ON tasks(list_id, sort_order, id);
         CREATE INDEX IF NOT EXISTS idx_tasks_home_targets
             ON tasks(due_at, status, completed_at, list_id)
             WHERE due_at IS NOT NULL;",
    )
}

fn add_sync_outbox_and_cursors(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE IF NOT EXISTS sync_outbox (
             id INTEGER PRIMARY KEY AUTOINCREMENT,
             record_id TEXT NOT NULL,
             collection TEXT NOT NULL,
             hlc TEXT NOT NULL,
             deleted INTEGER NOT NULL DEFAULT 0,
             blob BLOB NOT NULL,
             created_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS idx_sync_outbox_stable_order
             ON sync_outbox(created_at, id);
         CREATE TABLE IF NOT EXISTS sync_cursors (
             name TEXT PRIMARY KEY NOT NULL,
             seq INTEGER NOT NULL,
             updated_at INTEGER NOT NULL
         );",
    )
}

fn has_user_schema_objects(connection: &Connection) -> Result<bool, StorageError> {
    let count: i64 = connection.query_row(
        "SELECT count(*)
         FROM sqlite_master
         WHERE type IN ('table', 'view')
           AND name NOT LIKE 'sqlite_%'",
        [],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}

fn validate_baseline_v1_schema(connection: &Connection) -> Result<(), StorageError> {
    for (table, required_columns) in BASELINE_V1_COLUMNS {
        let columns = table_columns(connection, table)?;
        if columns.is_empty() {
            return Err(StorageError::IncompatibleSchema(format!(
                "missing baseline v1 table {table}"
            )));
        }

        for required_column in *required_columns {
            if !columns.iter().any(|column| column == required_column) {
                return Err(StorageError::IncompatibleSchema(format!(
                    "missing baseline v1 column {table}.{required_column}"
                )));
            }
        }
    }

    let list_columns = table_columns(connection, "lists")?;
    if list_columns.iter().any(|column| column == "archived_at") {
        return Err(StorageError::IncompatibleSchema(
            "lists.archived_at exists while user_version is 0".to_string(),
        ));
    }
    if list_columns.iter().any(|column| column == "is_default") {
        return Err(StorageError::IncompatibleSchema(
            "lists.is_default exists while user_version is 0".to_string(),
        ));
    }

    Ok(())
}

fn add_sync_record_states(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE IF NOT EXISTS sync_record_states (
             record_id TEXT NOT NULL,
             collection TEXT NOT NULL,
             plaintext_json TEXT NOT NULL,
             updated_at INTEGER NOT NULL,
             PRIMARY KEY (collection, record_id)
         );",
    )
}

fn add_local_crypto_cache(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE local_profile_binding (
             singleton INTEGER PRIMARY KEY NOT NULL CHECK (singleton = 1),
             tenant_id TEXT NOT NULL,
             user_id TEXT NOT NULL,
             device_id TEXT NOT NULL,
             bound_at INTEGER NOT NULL,
             updated_at INTEGER NOT NULL
         );
         CREATE TABLE local_list_key_bundles (
             tenant_id TEXT NOT NULL,
             list_id TEXT NOT NULL,
             wrapped_list_dek BLOB NOT NULL CHECK (length(wrapped_list_dek) > 0),
             updated_at INTEGER NOT NULL,
             PRIMARY KEY (tenant_id, list_id)
         );
         CREATE INDEX idx_local_list_key_bundles_tenant
             ON local_list_key_bundles(tenant_id);
         INSERT INTO local_profile_binding (
             singleton, tenant_id, user_id, device_id, bound_at, updated_at
         )
         SELECT 1,
                tenant.value,
                account_user.value,
                device.value,
                MIN(tenant.updated_at, account_user.updated_at, device.updated_at),
                MAX(tenant.updated_at, account_user.updated_at, device.updated_at)
         FROM settings AS tenant,
              settings AS account_user,
              settings AS device
         WHERE tenant.key = 'account_tenant_id'
           AND account_user.key = 'account_user_id'
           AND device.key = 'account_device_id'
           AND trim(tenant.value) <> ''
           AND trim(account_user.value) <> ''
           AND trim(device.value) <> ''
         LIMIT 1;",
    )
}

/// Protocol v2 is intentionally destructive for local sync metadata.
/// Domain rows and the account-bound crypto cache are left untouched; callers
/// regenerate v2 seed heads after opening the migrated profile.
fn replace_sync_metadata_v2(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "DROP TABLE IF EXISTS sync_outbox;
         DROP TABLE IF EXISTS sync_record_states;
         DROP TABLE IF EXISTS sync_cursors;

         CREATE TABLE sync_outbox (
             record_id TEXT PRIMARY KEY NOT NULL,
             collection TEXT NOT NULL CHECK (collection IN ('lists', 'tasks')),
             op_id TEXT NOT NULL UNIQUE,
             base_revision_hlc TEXT,
             revision_hlc TEXT NOT NULL,
             state_kind TEXT NOT NULL CHECK (state_kind IN ('live', 'tombstone')),
             semantic_hlc TEXT NOT NULL,
             blob BLOB,
             created_at INTEGER NOT NULL,
             CHECK (
                 (state_kind = 'live' AND blob IS NOT NULL AND length(blob) > 0)
                 OR (state_kind = 'tombstone' AND blob IS NULL)
             )
         );
         CREATE INDEX idx_sync_outbox_stable_order
             ON sync_outbox(created_at, record_id);

         CREATE TABLE sync_record_states (
             record_id TEXT PRIMARY KEY NOT NULL,
             collection TEXT NOT NULL CHECK (collection IN ('lists', 'tasks')),
             current_revision_hlc TEXT,
             state_kind TEXT NOT NULL CHECK (state_kind IN ('live', 'tombstone')),
             semantic_hlc TEXT NOT NULL,
             plaintext_json TEXT,
             updated_at INTEGER NOT NULL,
             CHECK (
                 (state_kind = 'live' AND plaintext_json IS NOT NULL)
                 OR (state_kind = 'tombstone' AND plaintext_json IS NULL)
             )
         );

         CREATE TABLE sync_cursors (
             name TEXT PRIMARY KEY NOT NULL,
             seq INTEGER NOT NULL,
             updated_at INTEGER NOT NULL
         );",
    )
}

/// Pre-release destructive rank migration. Domain order is preserved while all
/// sync metadata is discarded so the caller can seed strict typed payloads.
fn normalize_fixed_width_ranks(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "WITH ranked AS (
             SELECT id,
                    printf('%016x%016x', row_number() OVER (ORDER BY sort_order, id), 0) AS rank
             FROM lists
         )
         UPDATE lists
         SET sort_order = (SELECT rank FROM ranked WHERE ranked.id = lists.id);

         WITH ranked AS (
             SELECT id,
                    printf('%016x%016x',
                           row_number() OVER (
                               PARTITION BY list_id, parent_task_id
                               ORDER BY sort_order, id
                           ),
                           0) AS rank
             FROM tasks
         )
         UPDATE tasks
         SET sort_order = (SELECT rank FROM ranked WHERE ranked.id = tasks.id);",
    )?;
    replace_sync_metadata_v2(transaction)
}

fn add_sync_quarantine(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE sync_quarantine (
             record_id TEXT PRIMARY KEY NOT NULL,
             collection TEXT NOT NULL CHECK (collection IN ('lists', 'tasks')),
             seq INTEGER NOT NULL CHECK (seq > 0),
             revision_hlc TEXT NOT NULL,
             state_kind TEXT NOT NULL CHECK (state_kind IN ('live', 'tombstone')),
             semantic_hlc TEXT NOT NULL,
             blob BLOB,
             reason TEXT NOT NULL CHECK (reason IN (
                 'missing_dek', 'no_matching_dek', 'authentication_failed',
                 'corrupt_envelope', 'invalid_plaintext'
             )),
             required_list_id TEXT,
             first_failed_at INTEGER NOT NULL,
             last_failed_at INTEGER NOT NULL,
             attempt_count INTEGER NOT NULL CHECK (attempt_count > 0),
             CHECK (
                 (state_kind = 'live' AND blob IS NOT NULL AND length(blob) > 0)
                 OR (state_kind = 'tombstone' AND blob IS NULL)
             )
         );
         CREATE INDEX idx_sync_quarantine_seq
             ON sync_quarantine(seq, record_id);",
    )
}

fn add_pending_list_key_bundles(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE pending_list_key_bundles (
             tenant_id TEXT NOT NULL,
             list_id TEXT NOT NULL,
             wrapped_list_dek BLOB NOT NULL CHECK (length(wrapped_list_dek) > 0),
             created_at INTEGER NOT NULL,
             PRIMARY KEY (tenant_id, list_id)
         );
         CREATE INDEX idx_pending_list_key_bundles_created
             ON pending_list_key_bundles(created_at, list_id);",
    )
}

const BASELINE_V1_COLUMNS: &[(&str, &[&str])] = &[
    (
        "tasks",
        &[
            "id",
            "list_id",
            "parent_task_id",
            "title",
            "note",
            "status",
            "priority",
            "due_at",
            "scheduled_at",
            "estimated_minutes",
            "sort_order",
            "completed_at",
            "closed_reason",
            "deleted_at",
            "assignee",
            "created_at",
            "updated_at",
        ],
    ),
    (
        "lists",
        &[
            "id",
            "name",
            "color",
            "icon",
            "org_id",
            "sort_order",
            "created_at",
            "updated_at",
        ],
    ),
    (
        "task_undo_entries",
        &[
            "id",
            "operation_type",
            "task_id",
            "list_id",
            "before_snapshot",
            "after_updated_at",
            "after_deleted_at",
            "after_completed_at",
            "created_at",
            "consumed_at",
        ],
    ),
    ("tasks_fts", &["title", "note"]),
];

fn table_columns(connection: &Connection, table: &str) -> Result<Vec<String>, StorageError> {
    let mut statement = connection.prepare(&format!("PRAGMA table_info({table})"))?;
    let columns = statement
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(columns)
}

/// SQLite-backed implementation of [`TaskRepository`].
pub struct SqliteTaskRepository {
    connection: Connection,
}

impl SqliteTaskRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    pub fn list_subtree_for_sync(&self, task_id: Uuid) -> Result<Vec<Task>, StorageError> {
        let mut statement = self.connection.prepare(
            "WITH RECURSIVE subtree(id) AS (
                 SELECT id FROM tasks WHERE id = ?1
                 UNION ALL
                 SELECT tasks.id
                 FROM tasks
                 INNER JOIN subtree ON tasks.parent_task_id = subtree.id
             )
             SELECT id, list_id, parent_task_id, title, note, status, priority,
                    due_at, scheduled_at, estimated_minutes, sort_order,
                    completed_at, closed_reason, deleted_at, assignee,
                    created_at, updated_at
             FROM tasks
             WHERE id IN (SELECT id FROM subtree)
             ORDER BY sort_order ASC, id ASC",
        )?;
        let tasks = statement
            .query_map([task_id.to_string()], row_to_task)?
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(StorageError::from)?;
        Ok(tasks)
    }

    pub fn upsert_for_sync(&mut self, task: Task) -> Result<(), StorageError> {
        upsert_task_for_sync_on(&self.connection, task)
    }

    pub fn delete_subtree_for_sync(&mut self, task_id: Uuid) -> Result<usize, StorageError> {
        let transaction = self.connection.transaction()?;
        let deleted = delete_task_subtree_on(&transaction, task_id)?;
        transaction.commit()?;
        Ok(deleted)
    }

    /// Updates a task and records the undo snapshot in the same SQLite transaction.
    pub fn update_with_undo(
        &mut self,
        before: Task,
        after: Task,
        operation_type: TaskUndoOperation,
        created_at: i64,
    ) -> Result<TaskUndoEntry, StorageError> {
        let transaction = self.connection.transaction()?;
        let entry =
            update_task_with_undo_on(&transaction, before, after, operation_type, created_at)?;
        transaction.commit()?;

        Ok(entry)
    }

    pub fn latest_unconsumed_undo(&self) -> Result<Option<TaskUndoEntry>, StorageError> {
        self.connection
            .query_row(
                "SELECT id, operation_type, task_id, list_id, before_snapshot,
                        after_updated_at, after_deleted_at, after_completed_at,
                        created_at, consumed_at
                 FROM task_undo_entries
                 WHERE consumed_at IS NULL
                   AND operation_type != 'delete'
                 ORDER BY created_at DESC, rowid DESC
                 LIMIT 1",
                [],
                row_to_task_undo_entry,
            )
            .optional()?
            .transpose()
    }

    pub fn undo_task_operation(
        &mut self,
        undo_id: Uuid,
        consumed_at: i64,
    ) -> Result<Task, StorageError> {
        let transaction = self.connection.transaction()?;
        let restored = undo_task_operation_on(&transaction, undo_id, consumed_at)?;
        transaction.commit()?;

        Ok(restored)
    }
}

impl TaskRepository for SqliteTaskRepository {
    fn get(&self, id: Uuid) -> Result<Task, StorageError> {
        get_task_on(&self.connection, id)
    }

    fn insert(&mut self, task: Task) -> Result<(), StorageError> {
        insert_task_on(&self.connection, &task)
    }

    fn update(&mut self, task: Task) -> Result<(), StorageError> {
        update_task_on(&self.connection, &task)
    }

    fn list_all_for_sync(&self) -> Result<Vec<Task>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT id, list_id, parent_task_id, title, note, status, priority,
                    due_at, scheduled_at, estimated_minutes, sort_order,
                    completed_at, closed_reason, deleted_at, assignee,
                    created_at, updated_at
             FROM tasks
             ORDER BY created_at ASC, id ASC",
        )?;
        let tasks = statement
            .query_map([], row_to_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(tasks)
    }

    fn list_active_by_list(&self, list_id: Uuid) -> Result<Vec<Task>, StorageError> {
        list_active_tasks_by_list_on(&self.connection, list_id)
    }

    fn list_home(
        &self,
        today_start_ms: i64,
        tomorrow_start_ms: i64,
    ) -> Result<Vec<HomeTask>, StorageError> {
        let mut statement = self.connection.prepare(
            "WITH RECURSIVE home_targets(id) AS (
                 SELECT tasks.id
                 FROM tasks
                 INNER JOIN lists ON lists.id = tasks.list_id
                 WHERE lists.archived_at IS NULL
                   AND tasks.due_at IS NOT NULL
                   AND (
                       tasks.status IN ('todo', 'in_progress')
                       OR (
                           tasks.status IN ('done', 'wont_do')
                           AND tasks.completed_at >= ?1
                           AND tasks.completed_at < ?2
                       )
                   )
             ),
             home_scope(id) AS (
                 SELECT id FROM home_targets
                 UNION
                 SELECT child.id
                 FROM tasks child
                 INNER JOIN home_scope parent ON child.parent_task_id = parent.id
             ),
             home_ancestors(id) AS (
                 SELECT tasks.parent_task_id
                 FROM tasks
                 INNER JOIN home_targets ON home_targets.id = tasks.id
                 WHERE tasks.parent_task_id IS NOT NULL
                 UNION
                 SELECT tasks.parent_task_id
                 FROM tasks
                 INNER JOIN home_ancestors ancestor ON ancestor.id = tasks.id
                 WHERE tasks.parent_task_id IS NOT NULL
             ),
             home_display_scope(id) AS (
                 SELECT id FROM home_scope
                 UNION
                 SELECT id FROM home_ancestors
             )
             SELECT tasks.id, tasks.list_id, tasks.parent_task_id, tasks.title,
                    tasks.note, tasks.status, tasks.priority, tasks.due_at,
                    tasks.scheduled_at, tasks.estimated_minutes, tasks.sort_order,
                    tasks.completed_at, tasks.closed_reason, tasks.deleted_at,
                    tasks.assignee, tasks.created_at, tasks.updated_at,
                    lists.name,
                    EXISTS(SELECT 1 FROM home_targets WHERE home_targets.id = tasks.id)
             FROM tasks
             INNER JOIN lists ON lists.id = tasks.list_id
             INNER JOIN home_display_scope ON home_display_scope.id = tasks.id
             WHERE lists.archived_at IS NULL
             ORDER BY tasks.due_at IS NULL ASC,
                      tasks.due_at ASC,
                      tasks.sort_order ASC,
                      tasks.id ASC",
        )?;
        let tasks = statement
            .query_map(params![today_start_ms, tomorrow_start_ms], row_to_home_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(tasks)
    }

    fn search_tasks(&self, query: &str) -> Result<Vec<Task>, StorageError> {
        let Some(match_query) = build_fts_prefix_query(query) else {
            return Ok(Vec::new());
        };

        let mut statement = self.connection.prepare(
            "SELECT tasks.id, tasks.list_id, tasks.parent_task_id, tasks.title,
                    tasks.note, tasks.status, tasks.priority, tasks.due_at,
                    tasks.scheduled_at, tasks.estimated_minutes, tasks.sort_order,
                    tasks.completed_at, tasks.closed_reason, tasks.deleted_at,
                    tasks.assignee, tasks.created_at, tasks.updated_at
             FROM tasks_fts
             INNER JOIN tasks ON tasks.id = tasks_fts.task_id
             WHERE tasks_fts MATCH ?1
               AND tasks.deleted_at IS NULL
             ORDER BY bm25(tasks_fts) ASC,
                      tasks.updated_at DESC,
                      tasks.id ASC",
        )?;
        let tasks = statement
            .query_map([match_query], row_to_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(tasks)
    }

    fn count_descendants(&self, task_id: Uuid) -> Result<usize, StorageError> {
        count_task_descendants_on(&self.connection, task_id)
    }

    fn delete_subtree(&mut self, task_id: Uuid) -> Result<usize, StorageError> {
        self.get(task_id)?;
        let transaction = self.connection.transaction()?;
        let deleted = delete_task_subtree_on(&transaction, task_id)?;
        transaction.commit()?;
        Ok(deleted)
    }
}

fn get_task_on(connection: &Connection, id: Uuid) -> Result<Task, StorageError> {
    let task = connection
        .query_row(
            "SELECT id, list_id, parent_task_id, title, note, status, priority,
                    due_at, scheduled_at, estimated_minutes, sort_order,
                    completed_at, closed_reason, deleted_at, assignee,
                    created_at, updated_at
             FROM tasks
             WHERE id = ?1",
            [id.to_string()],
            row_to_task,
        )
        .optional()?;

    task.ok_or(StorageError::NotFound(id))
}

fn upsert_task_for_sync_on(connection: &Connection, task: Task) -> Result<(), StorageError> {
    let exists = connection
        .query_row(
            "SELECT 1 FROM tasks WHERE id = ?1",
            [task.id.to_string()],
            |_| Ok(()),
        )
        .optional()?
        .is_some();
    if exists {
        update_task_on(connection, &task)
    } else {
        insert_task_on(connection, &task)
    }
}

fn list_active_tasks_by_list_on(
    connection: &Connection,
    list_id: Uuid,
) -> Result<Vec<Task>, StorageError> {
    let mut statement = connection.prepare(
        "SELECT id, list_id, parent_task_id, title, note, status, priority,
                due_at, scheduled_at, estimated_minutes, sort_order,
                completed_at, closed_reason, deleted_at, assignee,
                created_at, updated_at
         FROM tasks
         WHERE list_id = ?1
         ORDER BY sort_order ASC, id ASC",
    )?;
    let tasks = statement
        .query_map([list_id.to_string()], row_to_task)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(tasks)
}

fn insert_task_on(connection: &Connection, task: &Task) -> Result<(), StorageError> {
    connection.execute(
        "INSERT INTO tasks (
            id, list_id, parent_task_id, title, note, status, priority,
            due_at, scheduled_at, estimated_minutes, sort_order,
            completed_at, closed_reason, deleted_at, assignee,
            created_at, updated_at
        ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11,
            ?12, ?13, ?14, ?15, ?16, ?17
        )",
        params![
            task.id.to_string(),
            task.list_id.to_string(),
            task.parent_task_id.map(|id| id.to_string()),
            task.title,
            task.note,
            status_to_str(task.status),
            task.priority,
            task.due_at,
            task.scheduled_at,
            task.estimated_minutes,
            task.sort_order,
            task.completed_at,
            task.closed_reason,
            task.deleted_at,
            task.assignee.map(|id| id.to_string()),
            task.created_at,
            task.updated_at,
        ],
    )?;
    Ok(())
}

fn update_task_on(connection: &Connection, task: &Task) -> Result<(), StorageError> {
    let changed = connection.execute(
        "UPDATE tasks
         SET list_id = ?2,
             parent_task_id = ?3,
             title = ?4,
             note = ?5,
             status = ?6,
             priority = ?7,
             due_at = ?8,
             scheduled_at = ?9,
             estimated_minutes = ?10,
             sort_order = ?11,
             completed_at = ?12,
             closed_reason = ?13,
             deleted_at = ?14,
             assignee = ?15,
             created_at = ?16,
             updated_at = ?17
         WHERE id = ?1",
        params![
            task.id.to_string(),
            task.list_id.to_string(),
            task.parent_task_id.map(|id| id.to_string()),
            task.title,
            task.note,
            status_to_str(task.status),
            task.priority,
            task.due_at,
            task.scheduled_at,
            task.estimated_minutes,
            task.sort_order,
            task.completed_at,
            task.closed_reason,
            task.deleted_at,
            task.assignee.map(|id| id.to_string()),
            task.created_at,
            task.updated_at,
        ],
    )?;

    if changed == 0 {
        return Err(StorageError::NotFound(task.id));
    }

    Ok(())
}

fn update_task_with_undo_on(
    connection: &Connection,
    before: Task,
    after: Task,
    operation_type: TaskUndoOperation,
    created_at: i64,
) -> Result<TaskUndoEntry, StorageError> {
    let entry = TaskUndoEntry {
        id: Uuid::now_v7(),
        operation_type,
        task_id: before.id,
        list_id: before.list_id,
        before_snapshot: before,
        after_updated_at: after.updated_at,
        after_deleted_at: after.deleted_at,
        after_completed_at: after.completed_at,
        created_at,
        consumed_at: None,
    };

    update_task_on(connection, &after)?;
    insert_task_undo_on(connection, &entry)?;
    Ok(entry)
}

fn undo_task_operation_on(
    connection: &Connection,
    undo_id: Uuid,
    consumed_at: i64,
) -> Result<Task, StorageError> {
    let entry = connection
        .query_row(
            "SELECT id, operation_type, task_id, list_id, before_snapshot,
                    after_updated_at, after_deleted_at, after_completed_at,
                    created_at, consumed_at
             FROM task_undo_entries
             WHERE id = ?1",
            [undo_id.to_string()],
            row_to_task_undo_entry,
        )
        .optional()?
        .transpose()?
        .ok_or(StorageError::NotFound(undo_id))?;

    if entry.consumed_at.is_some() {
        return Err(StorageError::UndoConsumed(undo_id));
    }

    let current = get_task_on(connection, entry.task_id)?;
    if current.updated_at != entry.after_updated_at
        || current.deleted_at != entry.after_deleted_at
        || current.completed_at != entry.after_completed_at
    {
        return Err(StorageError::UndoConflict(entry.task_id));
    }

    update_task_on(connection, &entry.before_snapshot)?;
    let changed = connection.execute(
        "UPDATE task_undo_entries
         SET consumed_at = ?2
         WHERE id = ?1 AND consumed_at IS NULL",
        params![undo_id.to_string(), consumed_at],
    )?;
    if changed == 0 {
        return Err(StorageError::UndoConsumed(undo_id));
    }

    Ok(entry.before_snapshot)
}

fn build_fts_prefix_query(query: &str) -> Option<String> {
    let terms = query
        .split_whitespace()
        .filter(|term| !term.is_empty())
        .map(|term| format!("\"{}\"*", term.replace('"', "\"\"")))
        .collect::<Vec<_>>();

    (!terms.is_empty()).then(|| terms.join(" AND "))
}

fn count_task_descendants_on(
    connection: &Connection,
    task_id: Uuid,
) -> Result<usize, StorageError> {
    let count: i64 = connection.query_row(
        "WITH RECURSIVE subtree(id) AS (
            SELECT id FROM tasks WHERE parent_task_id = ?1
            UNION ALL
            SELECT tasks.id
            FROM tasks
            INNER JOIN subtree ON tasks.parent_task_id = subtree.id
         )
         SELECT count(*) FROM subtree",
        [task_id.to_string()],
        |row| row.get(0),
    )?;
    usize::try_from(count).map_err(|_| {
        StorageError::IncompatibleSchema("task descendant count exceeded usize".to_string())
    })
}

fn delete_task_subtree_on(connection: &Connection, task_id: Uuid) -> Result<usize, StorageError> {
    connection.execute(
        "WITH RECURSIVE subtree(id) AS (
            SELECT id FROM tasks WHERE id = ?1
            UNION ALL
            SELECT tasks.id
            FROM tasks
            INNER JOIN subtree ON tasks.parent_task_id = subtree.id
         )
         DELETE FROM task_undo_entries
         WHERE task_id IN (SELECT id FROM subtree)",
        [task_id.to_string()],
    )?;
    connection.execute(
        "WITH RECURSIVE subtree(id) AS (
            SELECT id FROM tasks WHERE id = ?1
            UNION ALL
            SELECT tasks.id
            FROM tasks
            INNER JOIN subtree ON tasks.parent_task_id = subtree.id
         )
         DELETE FROM reminders
         WHERE task_id IN (SELECT id FROM subtree)",
        [task_id.to_string()],
    )?;
    let deleted = connection.execute(
        "WITH RECURSIVE subtree(id) AS (
            SELECT id FROM tasks WHERE id = ?1
            UNION ALL
            SELECT tasks.id
            FROM tasks
            INNER JOIN subtree ON tasks.parent_task_id = subtree.id
         )
         DELETE FROM tasks
         WHERE id IN (SELECT id FROM subtree)",
        [task_id.to_string()],
    )?;
    Ok(deleted)
}

fn insert_task_undo_on(connection: &Connection, entry: &TaskUndoEntry) -> Result<(), StorageError> {
    connection.execute(
        "INSERT INTO task_undo_entries (
            id, operation_type, task_id, list_id, before_snapshot,
            after_updated_at, after_deleted_at, after_completed_at,
            created_at, consumed_at
        ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10
        )",
        params![
            entry.id.to_string(),
            undo_operation_to_str(entry.operation_type),
            entry.task_id.to_string(),
            entry.list_id.to_string(),
            serde_json::to_string(&entry.before_snapshot)?,
            entry.after_updated_at,
            entry.after_deleted_at,
            entry.after_completed_at,
            entry.created_at,
            entry.consumed_at,
        ],
    )?;
    Ok(())
}

fn get_list_on(connection: &Connection, id: Uuid) -> Result<List, StorageError> {
    let list = connection
        .query_row(
            "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                    is_default, created_at, updated_at
             FROM lists
             WHERE id = ?1",
            [id.to_string()],
            row_to_list,
        )
        .optional()?;
    list.ok_or(StorageError::NotFound(id))
}

fn get_default_list_on(connection: &Connection) -> Result<Option<List>, StorageError> {
    connection
        .query_row(
            "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                    is_default, created_at, updated_at
             FROM lists
             WHERE is_default = 1
             LIMIT 1",
            [],
            row_to_list,
        )
        .optional()
        .map_err(StorageError::from)
}

fn insert_list_on(connection: &Connection, list: &List) -> Result<(), StorageError> {
    connection.execute(
        "INSERT INTO lists (
            id, name, color, icon, org_id, sort_order, is_default, archived_at,
            created_at, updated_at
        ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10
        )",
        params![
            list.id.to_string(),
            list.name,
            list.color,
            list.icon,
            list.org_id.map(|id| id.to_string()),
            list.sort_order,
            list.is_default,
            list.archived_at,
            list.created_at,
            list.updated_at,
        ],
    )?;
    Ok(())
}

fn upsert_list_for_sync_on(connection: &Connection, list: List) -> Result<(), StorageError> {
    let exists = connection
        .query_row(
            "SELECT 1 FROM lists WHERE id = ?1",
            [list.id.to_string()],
            |_| Ok(()),
        )
        .optional()?
        .is_some();
    if exists {
        update_list_on(connection, &list)
    } else {
        insert_list_on(connection, &list)
    }
}

fn delete_list_with_tasks_for_sync_on(
    connection: &Connection,
    list_id: Uuid,
) -> Result<usize, StorageError> {
    let task_count: i64 = connection
        .query_row(
            "SELECT count(*) FROM tasks WHERE list_id = ?1",
            [list_id.to_string()],
            |row| row.get(0),
        )
        .optional()?
        .unwrap_or(0);
    connection.execute(
        "DELETE FROM task_undo_entries
         WHERE task_id IN (SELECT id FROM tasks WHERE list_id = ?1)",
        [list_id.to_string()],
    )?;
    connection.execute(
        "DELETE FROM reminders
         WHERE task_id IN (SELECT id FROM tasks WHERE list_id = ?1)",
        [list_id.to_string()],
    )?;
    connection.execute(
        "DELETE FROM tasks WHERE list_id = ?1",
        [list_id.to_string()],
    )?;
    connection.execute("DELETE FROM lists WHERE id = ?1", [list_id.to_string()])?;
    usize::try_from(task_count)
        .map_err(|_| StorageError::IncompatibleSchema("list task count exceeded usize".to_string()))
}

fn update_list_on(connection: &Connection, list: &List) -> Result<(), StorageError> {
    if list.is_default && list.archived_at.is_some() {
        return Err(StorageError::DefaultListProtected {
            operation: "archived",
            list_id: list.id,
        });
    }
    let changed = connection.execute(
        "UPDATE lists
         SET name = ?2,
             color = ?3,
             icon = ?4,
             org_id = ?5,
             sort_order = ?6,
             is_default = ?7,
             archived_at = ?8,
             created_at = ?9,
             updated_at = ?10
         WHERE id = ?1",
        params![
            list.id.to_string(),
            list.name,
            list.color,
            list.icon,
            list.org_id.map(|id| id.to_string()),
            list.sort_order,
            list.is_default,
            list.archived_at,
            list.created_at,
            list.updated_at,
        ],
    )?;
    if changed == 0 {
        return Err(StorageError::NotFound(list.id));
    }
    Ok(())
}

/// SQLite-backed implementation of [`ListRepository`].
pub struct SqliteListRepository {
    connection: Connection,
}

impl SqliteListRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    pub fn upsert_for_sync(&mut self, list: List) -> Result<(), StorageError> {
        upsert_list_for_sync_on(&self.connection, list)
    }

    pub fn delete_with_tasks_for_sync(&mut self, list_id: Uuid) -> Result<usize, StorageError> {
        let transaction = self.connection.transaction()?;
        let task_count = delete_list_with_tasks_for_sync_on(&transaction, list_id)?;
        transaction.commit()?;
        Ok(task_count)
    }
}

impl ListRepository for SqliteListRepository {
    fn get(&self, id: Uuid) -> Result<List, StorageError> {
        get_list_on(&self.connection, id)
    }

    fn insert(&mut self, list: List) -> Result<(), StorageError> {
        insert_list_on(&self.connection, &list)
    }

    fn update(&mut self, list: List) -> Result<(), StorageError> {
        update_list_on(&self.connection, &list)
    }

    fn list_all(&self) -> Result<Vec<List>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                    is_default, created_at, updated_at
             FROM lists
             WHERE archived_at IS NULL
             ORDER BY sort_order ASC, id ASC",
        )?;
        let lists = statement
            .query_map([], row_to_list)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(lists)
    }

    fn list_archived(&self) -> Result<Vec<List>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                    is_default, created_at, updated_at
             FROM lists
             WHERE archived_at IS NOT NULL
             ORDER BY sort_order ASC, id ASC",
        )?;
        let lists = statement
            .query_map([], row_to_list)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(lists)
    }

    fn get_default(&self) -> Result<Option<List>, StorageError> {
        get_default_list_on(&self.connection)
    }

    fn ensure_default_list(&mut self, name: String, now_ms: i64) -> Result<List, StorageError> {
        if let Some(list) = self.get_default()? {
            return Ok(list);
        }

        let last_rank: Option<String> =
            self.connection
                .query_row("SELECT max(sort_order) FROM lists", [], |row| row.get(0))?;
        let sort_order = fractional_index_after(last_rank.as_deref())
            .map_err(|error| StorageError::IncompatibleSchema(error.to_string()))?;
        let list = new_default_list(name, sort_order, now_ms)
            .map_err(|error| StorageError::IncompatibleSchema(error.to_string()))?;
        self.insert(list.clone())?;
        Ok(list)
    }

    fn count_tasks(&self, list_id: Uuid) -> Result<usize, StorageError> {
        let count: i64 = self.connection.query_row(
            "SELECT count(*) FROM tasks WHERE list_id = ?1",
            [list_id.to_string()],
            |row| row.get(0),
        )?;
        usize::try_from(count).map_err(|_| {
            StorageError::IncompatibleSchema("list task count exceeded usize".to_string())
        })
    }

    fn delete_with_tasks(&mut self, list_id: Uuid) -> Result<usize, StorageError> {
        let list = self.get(list_id)?;
        if list.is_default {
            return Err(StorageError::DefaultListProtected {
                operation: "deleted",
                list_id,
            });
        }
        let transaction = self.connection.transaction()?;
        let task_count: i64 = transaction.query_row(
            "SELECT count(*) FROM tasks WHERE list_id = ?1",
            [list_id.to_string()],
            |row| row.get(0),
        )?;
        transaction.execute(
            "DELETE FROM task_undo_entries
             WHERE task_id IN (SELECT id FROM tasks WHERE list_id = ?1)",
            [list_id.to_string()],
        )?;
        transaction.execute(
            "DELETE FROM reminders
             WHERE task_id IN (SELECT id FROM tasks WHERE list_id = ?1)",
            [list_id.to_string()],
        )?;
        transaction.execute(
            "DELETE FROM tasks WHERE list_id = ?1",
            [list_id.to_string()],
        )?;
        let changed =
            transaction.execute("DELETE FROM lists WHERE id = ?1", [list_id.to_string()])?;
        if changed == 0 {
            return Err(StorageError::NotFound(list_id));
        }
        transaction.commit()?;
        usize::try_from(task_count).map_err(|_| {
            StorageError::IncompatibleSchema("list task count exceeded usize".to_string())
        })
    }
}

/// SQLite-backed implementation of [`SettingsRepository`].
pub struct SqliteSettingsRepository {
    connection: Connection,
}

impl SqliteSettingsRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }
}

impl SettingsRepository for SqliteSettingsRepository {
    fn get_setting(&self, key: &str) -> Result<Option<String>, StorageError> {
        get_setting_on(&self.connection, key)
    }

    fn set_setting(&mut self, key: &str, value: &str, updated_at: i64) -> Result<(), StorageError> {
        set_setting_on(&self.connection, key, value, updated_at)
    }
}

/// SQLCipher-backed local profile binding and wrapped List DEK cache.
pub struct SqliteLocalCryptoRepository {
    connection: Connection,
}

impl SqliteLocalCryptoRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }
}

impl LocalCryptoRepository for SqliteLocalCryptoRepository {
    fn load_binding(&self) -> Result<Option<LocalProfileBinding>, StorageError> {
        load_local_profile_binding_on(&self.connection)
    }

    fn bind_and_replace_bundles(
        &mut self,
        binding: LocalProfileBinding,
        bundles: &[LocalListKeyBundle],
    ) -> Result<(), StorageError> {
        for bundle in bundles {
            if bundle.tenant_id != binding.tenant_id {
                return Err(StorageError::LocalProfileTenantMismatch {
                    bound_tenant_id: binding.tenant_id,
                    requested_tenant_id: bundle.tenant_id,
                });
            }
        }

        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        if let Some(existing) = load_local_profile_binding_on(&transaction)? {
            if existing.tenant_id != binding.tenant_id {
                return Err(StorageError::LocalProfileTenantMismatch {
                    bound_tenant_id: existing.tenant_id,
                    requested_tenant_id: binding.tenant_id,
                });
            }
            if existing.user_id != binding.user_id {
                return Err(StorageError::LocalProfileUserMismatch {
                    bound_user_id: existing.user_id,
                    requested_user_id: binding.user_id,
                });
            }
        }

        transaction.execute(
            "INSERT INTO local_profile_binding (
                 singleton, tenant_id, user_id, device_id, bound_at, updated_at
             ) VALUES (1, ?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(singleton) DO UPDATE SET
                 device_id = excluded.device_id,
                 updated_at = excluded.updated_at",
            params![
                binding.tenant_id.to_string(),
                binding.user_id.to_string(),
                binding.device_id.to_string(),
                binding.bound_at,
                binding.updated_at,
            ],
        )?;
        transaction.execute("DELETE FROM local_list_key_bundles", [])?;
        for bundle in bundles {
            transaction.execute(
                "INSERT INTO local_list_key_bundles (
                     tenant_id, list_id, wrapped_list_dek, updated_at
                 ) VALUES (?1, ?2, ?3, ?4)",
                params![
                    bundle.tenant_id.to_string(),
                    bundle.list_id.to_string(),
                    bundle.wrapped_list_dek,
                    bundle.updated_at,
                ],
            )?;
        }
        transaction.commit()?;
        Ok(())
    }

    fn load_bundles(&self, tenant_id: Uuid) -> Result<Vec<LocalListKeyBundle>, StorageError> {
        if let Some(binding) = load_local_profile_binding_on(&self.connection)? {
            if binding.tenant_id != tenant_id {
                return Err(StorageError::LocalProfileTenantMismatch {
                    bound_tenant_id: binding.tenant_id,
                    requested_tenant_id: tenant_id,
                });
            }
        }
        let foreign_count: i64 = self.connection.query_row(
            "SELECT count(*) FROM local_list_key_bundles WHERE tenant_id <> ?1",
            [tenant_id.to_string()],
            |row| row.get(0),
        )?;
        if foreign_count != 0 {
            return Err(StorageError::LocalCryptoCacheTenantMismatch);
        }
        load_local_list_key_bundles_on(&self.connection, tenant_id)
    }
}

fn load_local_profile_binding_on(
    connection: &Connection,
) -> Result<Option<LocalProfileBinding>, StorageError> {
    let row = connection
        .query_row(
            "SELECT tenant_id, user_id, device_id, bound_at, updated_at
             FROM local_profile_binding
             WHERE singleton = 1",
            [],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                ))
            },
        )
        .optional()?;
    row.map(|(tenant_id, user_id, device_id, bound_at, updated_at)| {
        Ok(LocalProfileBinding {
            tenant_id: Uuid::parse_str(&tenant_id)?,
            user_id: Uuid::parse_str(&user_id)?,
            device_id: Uuid::parse_str(&device_id)?,
            bound_at,
            updated_at,
        })
    })
    .transpose()
}

fn load_local_list_key_bundles_on(
    connection: &Connection,
    tenant_id: Uuid,
) -> Result<Vec<LocalListKeyBundle>, StorageError> {
    let mut statement = connection.prepare(
        "SELECT list_id, wrapped_list_dek, updated_at
         FROM local_list_key_bundles
         WHERE tenant_id = ?1
         ORDER BY list_id ASC",
    )?;
    let rows = statement
        .query_map([tenant_id.to_string()], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Vec<u8>>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    rows.into_iter()
        .map(|(list_id, wrapped_list_dek, updated_at)| {
            Ok(LocalListKeyBundle {
                tenant_id,
                list_id: Uuid::parse_str(&list_id)?,
                wrapped_list_dek,
                updated_at,
            })
        })
        .collect()
}

fn get_setting_on(connection: &Connection, key: &str) -> Result<Option<String>, StorageError> {
    connection
        .query_row(
            "SELECT value
             FROM settings
             WHERE key = ?1",
            [key],
            |row| row.get(0),
        )
        .optional()
        .map_err(StorageError::from)
}

fn set_setting_on(
    connection: &Connection,
    key: &str,
    value: &str,
    updated_at: i64,
) -> Result<(), StorageError> {
    connection.execute(
        "INSERT INTO settings (key, value, updated_at)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(key) DO UPDATE SET
             value = excluded.value,
             updated_at = excluded.updated_at",
        params![key, value, updated_at],
    )?;
    Ok(())
}

/// SQLite-backed implementation of [`ReminderRepository`].
pub struct SqliteReminderRepository {
    connection: Connection,
}

impl SqliteReminderRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }
}

impl ReminderRepository for SqliteReminderRepository {
    fn set_task_reminder(
        &mut self,
        task_id: Uuid,
        remind_at: i64,
        created_at: i64,
    ) -> Result<Reminder, StorageError> {
        ensure_task_exists(&self.connection, task_id)?;
        let reminder = Reminder {
            id: Uuid::now_v7(),
            task_id,
            remind_at,
            snoozed_until: None,
            created_at,
        };
        let transaction = self.connection.transaction()?;
        delete_task_reminders_on(&transaction, task_id)?;
        insert_reminder_on(&transaction, &reminder)?;
        transaction.commit()?;
        Ok(reminder)
    }

    fn clear_task_reminders(&mut self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError> {
        let reminders = list_task_reminders_on(&self.connection, task_id)?;
        delete_task_reminders_on(&self.connection, task_id)?;
        Ok(reminders)
    }

    fn list_task_reminders(&self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError> {
        list_task_reminders_on(&self.connection, task_id)
    }

    fn list_task_subtree_reminders(&self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError> {
        ensure_task_exists(&self.connection, task_id)?;
        let mut statement = self.connection.prepare(
            "WITH RECURSIVE subtree(id) AS (
                 SELECT id FROM tasks WHERE id = ?1
                 UNION ALL
                 SELECT tasks.id
                 FROM tasks
                 INNER JOIN subtree ON tasks.parent_task_id = subtree.id
             )
             SELECT id, task_id, remind_at, snoozed_until, created_at
             FROM reminders
             WHERE task_id IN (SELECT id FROM subtree)
             ORDER BY COALESCE(snoozed_until, remind_at) ASC, created_at ASC, id ASC",
        )?;
        let reminders = statement
            .query_map([task_id.to_string()], row_to_reminder)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(reminders)
    }

    fn list_list_reminders(&self, list_id: Uuid) -> Result<Vec<Reminder>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT reminders.id, reminders.task_id, reminders.remind_at,
                    reminders.snoozed_until, reminders.created_at
             FROM reminders
             INNER JOIN tasks ON tasks.id = reminders.task_id
             WHERE tasks.list_id = ?1
             ORDER BY COALESCE(reminders.snoozed_until, reminders.remind_at) ASC,
                      reminders.created_at ASC,
                      reminders.id ASC",
        )?;
        let reminders = statement
            .query_map([list_id.to_string()], row_to_reminder)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(reminders)
    }

    fn list_pending_reminders(&self, now_ms: i64) -> Result<Vec<Reminder>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT reminders.id, reminders.task_id, reminders.remind_at,
                    reminders.snoozed_until, reminders.created_at
             FROM reminders
             INNER JOIN tasks ON tasks.id = reminders.task_id
             WHERE COALESCE(reminders.snoozed_until, reminders.remind_at) > ?1
               AND tasks.status IN ('todo', 'in_progress')
               AND tasks.deleted_at IS NULL
             ORDER BY COALESCE(reminders.snoozed_until, reminders.remind_at) ASC,
                      reminders.created_at ASC,
                      reminders.id ASC",
        )?;
        let reminders = statement
            .query_map([now_ms], row_to_reminder)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(reminders)
    }

    fn snooze_reminder(
        &mut self,
        reminder_id: Uuid,
        snoozed_until: i64,
    ) -> Result<Reminder, StorageError> {
        let changed = self.connection.execute(
            "UPDATE reminders
             SET snoozed_until = ?2
             WHERE id = ?1",
            params![reminder_id.to_string(), snoozed_until],
        )?;
        if changed == 0 {
            return Err(StorageError::NotFound(reminder_id));
        }
        self.connection
            .query_row(
                "SELECT id, task_id, remind_at, snoozed_until, created_at
                 FROM reminders
                 WHERE id = ?1",
                [reminder_id.to_string()],
                row_to_reminder,
            )
            .map_err(StorageError::from)
    }
}

/// SQLite-backed implementation of [`SyncStateRepository`].
pub struct SqliteSyncStateRepository {
    connection: Connection,
}

impl SqliteSyncStateRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    pub fn get_record_state(
        &self,
        collection: &str,
        record_id: Uuid,
    ) -> Result<Option<SyncRecordState>, StorageError> {
        get_record_state_on(&self.connection, collection, record_id)
    }

    pub fn put_record_state(&mut self, state: SyncRecordState) -> Result<(), StorageError> {
        put_record_state_on(&self.connection, state)
    }

    pub fn put_quarantine(&mut self, entry: SyncQuarantineEntry) -> Result<(), StorageError> {
        put_quarantine_on(&self.connection, entry)
    }

    pub fn list_quarantine(&self, limit: usize) -> Result<Vec<SyncQuarantineEntry>, StorageError> {
        list_quarantine_on(&self.connection, limit)
    }

    pub fn list_replayable_quarantine(
        &self,
        after: Option<(i64, Uuid)>,
        limit: usize,
    ) -> Result<Vec<SyncQuarantineEntry>, StorageError> {
        list_replayable_quarantine_on(&self.connection, after, limit)
    }

    pub fn delete_quarantine(&mut self, record_id: Uuid) -> Result<bool, StorageError> {
        delete_quarantine_on(&self.connection, record_id)
    }

    pub fn list_pending_list_key_bundles(
        &self,
        tenant_id: Uuid,
        limit: usize,
    ) -> Result<Vec<PendingListKeyBundle>, StorageError> {
        list_pending_list_key_bundles_on(&self.connection, tenant_id, limit)
    }

    pub fn ack_pending_list_key_bundle(
        &mut self,
        tenant_id: Uuid,
        list_id: Uuid,
        wrapped_list_dek: &[u8],
    ) -> Result<bool, StorageError> {
        ack_pending_list_key_bundle_on(&self.connection, tenant_id, list_id, wrapped_list_dek)
    }
}

fn put_local_list_key_bundle_on(
    connection: &Connection,
    bundle: &LocalListKeyBundle,
) -> Result<(), StorageError> {
    let binding = load_local_profile_binding_on(connection)?.ok_or_else(|| {
        StorageError::IncompatibleSchema("local profile binding is missing".to_string())
    })?;
    if binding.tenant_id != bundle.tenant_id {
        return Err(StorageError::LocalProfileTenantMismatch {
            bound_tenant_id: binding.tenant_id,
            requested_tenant_id: bundle.tenant_id,
        });
    }
    let existing = connection
        .query_row(
            "SELECT wrapped_list_dek FROM local_list_key_bundles
             WHERE tenant_id = ?1 AND list_id = ?2",
            params![bundle.tenant_id.to_string(), bundle.list_id.to_string()],
            |row| row.get::<_, Vec<u8>>(0),
        )
        .optional()?;
    if let Some(existing) = existing {
        return if existing == bundle.wrapped_list_dek {
            Ok(())
        } else {
            Err(StorageError::IncompatibleSchema(
                "local list key bundle is immutable".to_string(),
            ))
        };
    }
    connection.execute(
        "INSERT INTO local_list_key_bundles (
             tenant_id, list_id, wrapped_list_dek, updated_at
         ) VALUES (?1, ?2, ?3, ?4)",
        params![
            bundle.tenant_id.to_string(),
            bundle.list_id.to_string(),
            bundle.wrapped_list_dek,
            bundle.updated_at,
        ],
    )?;
    Ok(())
}

fn put_pending_list_key_bundle_on(
    connection: &Connection,
    bundle: &PendingListKeyBundle,
) -> Result<(), StorageError> {
    let binding = load_local_profile_binding_on(connection)?.ok_or_else(|| {
        StorageError::IncompatibleSchema("local profile binding is missing".to_string())
    })?;
    if binding.tenant_id != bundle.tenant_id {
        return Err(StorageError::LocalProfileTenantMismatch {
            bound_tenant_id: binding.tenant_id,
            requested_tenant_id: bundle.tenant_id,
        });
    }
    let existing = connection
        .query_row(
            "SELECT wrapped_list_dek FROM pending_list_key_bundles
             WHERE tenant_id = ?1 AND list_id = ?2",
            params![bundle.tenant_id.to_string(), bundle.list_id.to_string()],
            |row| row.get::<_, Vec<u8>>(0),
        )
        .optional()?;
    if let Some(existing) = existing {
        return if existing == bundle.wrapped_list_dek {
            Ok(())
        } else {
            Err(StorageError::IncompatibleSchema(
                "pending list key bundle is immutable".to_string(),
            ))
        };
    }
    connection.execute(
        "INSERT INTO pending_list_key_bundles (
             tenant_id, list_id, wrapped_list_dek, created_at
         ) VALUES (?1, ?2, ?3, ?4)",
        params![
            bundle.tenant_id.to_string(),
            bundle.list_id.to_string(),
            bundle.wrapped_list_dek,
            bundle.created_at,
        ],
    )?;
    Ok(())
}

fn list_pending_list_key_bundles_on(
    connection: &Connection,
    tenant_id: Uuid,
    limit: usize,
) -> Result<Vec<PendingListKeyBundle>, StorageError> {
    let limit = i64::try_from(limit).unwrap_or(i64::MAX);
    let mut statement = connection.prepare(
        "SELECT list_id, wrapped_list_dek, created_at
         FROM pending_list_key_bundles
         WHERE tenant_id = ?1
         ORDER BY created_at ASC, list_id ASC
         LIMIT ?2",
    )?;
    let rows = statement
        .query_map(params![tenant_id.to_string(), limit], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Vec<u8>>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    rows.into_iter()
        .map(|(list_id, wrapped_list_dek, created_at)| {
            Ok(PendingListKeyBundle {
                tenant_id,
                list_id: Uuid::parse_str(&list_id)?,
                wrapped_list_dek,
                created_at,
            })
        })
        .collect()
}

fn ack_pending_list_key_bundle_on(
    connection: &Connection,
    tenant_id: Uuid,
    list_id: Uuid,
    wrapped_list_dek: &[u8],
) -> Result<bool, StorageError> {
    Ok(connection.execute(
        "DELETE FROM pending_list_key_bundles
         WHERE tenant_id = ?1 AND list_id = ?2 AND wrapped_list_dek = ?3",
        params![tenant_id.to_string(), list_id.to_string(), wrapped_list_dek],
    )? != 0)
}

impl SyncStateRepository for SqliteSyncStateRepository {
    fn put_outbox_head(
        &mut self,
        entry: NewSyncOutboxEntry,
    ) -> Result<SyncOutboxEntry, StorageError> {
        put_outbox_head_on(&self.connection, entry)
    }

    fn list_outbox_heads(&self, limit: usize) -> Result<Vec<SyncOutboxEntry>, StorageError> {
        list_outbox_heads_on(&self.connection, limit)
    }

    fn has_outbox_head(&self, collection: &str, record_id: Uuid) -> Result<bool, StorageError> {
        has_outbox_head_on(&self.connection, collection, record_id)
    }

    fn ack_outbox_op(&mut self, op_id: Uuid) -> Result<bool, StorageError> {
        ack_outbox_op_on(&self.connection, op_id)
    }

    fn get_record_state(
        &self,
        collection: &str,
        record_id: Uuid,
    ) -> Result<Option<SyncRecordState>, StorageError> {
        get_record_state_on(&self.connection, collection, record_id)
    }

    fn put_record_state(&mut self, state: SyncRecordState) -> Result<(), StorageError> {
        put_record_state_on(&self.connection, state)
    }

    fn get_cursor(&self, name: &str) -> Result<Option<SyncCursor>, StorageError> {
        get_cursor_on(&self.connection, name)
    }

    fn set_cursor(&mut self, name: &str, seq: i64, updated_at: i64) -> Result<(), StorageError> {
        set_cursor_on(&self.connection, name, seq, updated_at)
    }

    fn delete_cursor(&mut self, name: &str) -> Result<(), StorageError> {
        delete_cursor_on(&self.connection, name)
    }

    fn put_quarantine(&mut self, entry: SyncQuarantineEntry) -> Result<(), StorageError> {
        put_quarantine_on(&self.connection, entry)
    }

    fn list_quarantine(&self, limit: usize) -> Result<Vec<SyncQuarantineEntry>, StorageError> {
        list_quarantine_on(&self.connection, limit)
    }

    fn list_replayable_quarantine(
        &self,
        after: Option<(i64, Uuid)>,
        limit: usize,
    ) -> Result<Vec<SyncQuarantineEntry>, StorageError> {
        list_replayable_quarantine_on(&self.connection, after, limit)
    }

    fn delete_quarantine(&mut self, record_id: Uuid) -> Result<bool, StorageError> {
        delete_quarantine_on(&self.connection, record_id)
    }
}

fn get_cursor_on(connection: &Connection, name: &str) -> Result<Option<SyncCursor>, StorageError> {
    connection
        .query_row(
            "SELECT name, seq, updated_at
             FROM sync_cursors
             WHERE name = ?1",
            [name],
            row_to_sync_cursor,
        )
        .optional()
        .map_err(StorageError::from)
}

fn set_cursor_on(
    connection: &Connection,
    name: &str,
    seq: i64,
    updated_at: i64,
) -> Result<(), StorageError> {
    connection.execute(
        "INSERT INTO sync_cursors (name, seq, updated_at)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(name) DO UPDATE SET
             seq = excluded.seq,
             updated_at = excluded.updated_at",
        params![name, seq, updated_at],
    )?;
    Ok(())
}

fn delete_cursor_on(connection: &Connection, name: &str) -> Result<(), StorageError> {
    connection.execute("DELETE FROM sync_cursors WHERE name = ?1", [name])?;
    Ok(())
}

fn get_record_state_on(
    connection: &Connection,
    collection: &str,
    record_id: Uuid,
) -> Result<Option<SyncRecordState>, StorageError> {
    validate_sync_collection(collection)?;
    let state = connection
        .query_row(
            "SELECT record_id, collection, current_revision_hlc, state_kind,
                    semantic_hlc, plaintext_json, updated_at
             FROM sync_record_states
             WHERE record_id = ?1",
            [record_id.to_string()],
            row_to_sync_record_state,
        )
        .optional()?
        .transpose()?;
    if let Some(state) = &state {
        ensure_requested_collection(record_id, &state.collection, collection)?;
    }
    Ok(state)
}

fn put_record_state_on(
    connection: &Connection,
    state: SyncRecordState,
) -> Result<(), StorageError> {
    validate_sync_collection(&state.collection)?;
    ensure_sync_collection_matches(connection, state.record_id, &state.collection)?;
    let (state_kind, semantic_hlc, plaintext_json) = match state.state {
        SyncRecordSemanticState::Live {
            mutation_hlc,
            plaintext_json,
        } => ("live", mutation_hlc, Some(plaintext_json)),
        SyncRecordSemanticState::Tombstone { delete_hlc } => ("tombstone", delete_hlc, None),
    };
    connection.execute(
        "INSERT INTO sync_record_states (
             record_id, collection, current_revision_hlc, state_kind,
             semantic_hlc, plaintext_json, updated_at
         ) VALUES (
             ?1, ?2, ?3, ?4, ?5, ?6, ?7
         )
         ON CONFLICT(record_id) DO UPDATE SET
             collection = excluded.collection,
             current_revision_hlc = excluded.current_revision_hlc,
             state_kind = excluded.state_kind,
             semantic_hlc = excluded.semantic_hlc,
             plaintext_json = excluded.plaintext_json,
             updated_at = excluded.updated_at",
        params![
            state.record_id.to_string(),
            state.collection,
            state.current_revision_hlc,
            state_kind,
            semantic_hlc,
            plaintext_json,
            state.updated_at,
        ],
    )?;
    Ok(())
}

fn put_outbox_head_on(
    connection: &Connection,
    entry: NewSyncOutboxEntry,
) -> Result<SyncOutboxEntry, StorageError> {
    validate_sync_collection(&entry.collection)?;
    ensure_sync_collection_matches(connection, entry.record_id, &entry.collection)?;
    let (state_kind, semantic_hlc, blob) = match entry.state {
        SyncOutboxState::Live { mutation_hlc, blob } => ("live", mutation_hlc, Some(blob)),
        SyncOutboxState::Tombstone { delete_hlc } => ("tombstone", delete_hlc, None),
    };
    connection.execute(
        "INSERT INTO sync_outbox (
             record_id, collection, op_id, base_revision_hlc, revision_hlc,
             state_kind, semantic_hlc, blob, created_at
         ) VALUES (
             ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9
         )
         ON CONFLICT(record_id) DO UPDATE SET
             collection = excluded.collection,
             op_id = excluded.op_id,
             base_revision_hlc = excluded.base_revision_hlc,
             revision_hlc = excluded.revision_hlc,
             state_kind = excluded.state_kind,
             semantic_hlc = excluded.semantic_hlc,
             blob = excluded.blob,
             created_at = excluded.created_at",
        params![
            entry.record_id.to_string(),
            entry.collection,
            entry.op_id.to_string(),
            entry.base_revision_hlc,
            entry.revision_hlc,
            state_kind,
            semantic_hlc,
            blob,
            entry.created_at,
        ],
    )?;
    connection
        .query_row(
            "SELECT op_id, record_id, collection, base_revision_hlc,
                    revision_hlc, state_kind, semantic_hlc, blob, created_at
             FROM sync_outbox
             WHERE record_id = ?1",
            [entry.record_id.to_string()],
            row_to_sync_outbox_entry,
        )
        .map_err(StorageError::from)?
}

fn list_outbox_heads_on(
    connection: &Connection,
    limit: usize,
) -> Result<Vec<SyncOutboxEntry>, StorageError> {
    let limit = i64::try_from(limit)
        .map_err(|_| StorageError::IncompatibleSchema("outbox limit exceeded i64".to_string()))?;
    let mut statement = connection.prepare(
        "SELECT op_id, record_id, collection, base_revision_hlc,
                revision_hlc, state_kind, semantic_hlc, blob, created_at
         FROM sync_outbox AS outbox
         WHERE NOT EXISTS (
             SELECT 1 FROM sync_quarantine AS quarantine
             WHERE quarantine.record_id = outbox.record_id
         )
         ORDER BY created_at ASC, record_id ASC
         LIMIT ?1",
    )?;
    let entries = statement
        .query_map([limit], row_to_sync_outbox_entry)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    entries.into_iter().collect()
}

fn put_quarantine_on(
    connection: &Connection,
    entry: SyncQuarantineEntry,
) -> Result<(), StorageError> {
    validate_sync_collection(&entry.collection)?;
    ensure_sync_collection_matches(connection, entry.record_id, &entry.collection)?;
    let existing = connection
        .query_row(
            "SELECT seq, revision_hlc FROM sync_quarantine WHERE record_id = ?1",
            [entry.record_id.to_string()],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)),
        )
        .optional()?;
    if let Some((existing_seq, existing_revision_hlc)) = existing {
        if entry.seq < existing_seq {
            return Ok(());
        }
        if entry.seq == existing_seq {
            if entry.revision_hlc != existing_revision_hlc {
                return Err(StorageError::IncompatibleSchema(
                    "quarantine revision changed at the same server sequence".to_string(),
                ));
            }
            connection.execute(
                "UPDATE sync_quarantine
                 SET reason = ?2,
                     required_list_id = ?3,
                     last_failed_at = ?4,
                     attempt_count = attempt_count + 1
                 WHERE record_id = ?1",
                params![
                    entry.record_id.to_string(),
                    entry.reason,
                    entry.required_list_id.map(|id| id.to_string()),
                    entry.last_failed_at,
                ],
            )?;
            return Ok(());
        }
    }
    let (state_kind, semantic_hlc, blob) = match entry.state {
        SyncOutboxState::Live { mutation_hlc, blob } => ("live", mutation_hlc, Some(blob)),
        SyncOutboxState::Tombstone { delete_hlc } => ("tombstone", delete_hlc, None),
    };
    connection.execute(
        "INSERT INTO sync_quarantine (
             record_id, collection, seq, revision_hlc, state_kind, semantic_hlc,
             blob, reason, required_list_id, first_failed_at, last_failed_at, attempt_count
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
         ON CONFLICT(record_id) DO UPDATE SET
             collection = excluded.collection,
             seq = excluded.seq,
             revision_hlc = excluded.revision_hlc,
             state_kind = excluded.state_kind,
             semantic_hlc = excluded.semantic_hlc,
             blob = excluded.blob,
             reason = excluded.reason,
             required_list_id = excluded.required_list_id,
             first_failed_at = excluded.first_failed_at,
             last_failed_at = excluded.last_failed_at,
             attempt_count = excluded.attempt_count",
        params![
            entry.record_id.to_string(),
            entry.collection,
            entry.seq,
            entry.revision_hlc,
            state_kind,
            semantic_hlc,
            blob,
            entry.reason,
            entry.required_list_id.map(|id| id.to_string()),
            entry.first_failed_at,
            entry.last_failed_at,
            entry.attempt_count,
        ],
    )?;
    Ok(())
}

fn list_quarantine_on(
    connection: &Connection,
    limit: usize,
) -> Result<Vec<SyncQuarantineEntry>, StorageError> {
    let limit = i64::try_from(limit)
        .map_err(|_| StorageError::IncompatibleSchema("quarantine limit exceeded i64".into()))?;
    let mut statement = connection.prepare(
        "SELECT record_id, collection, seq, revision_hlc, state_kind, semantic_hlc,
                blob, reason, required_list_id, first_failed_at, last_failed_at, attempt_count
         FROM sync_quarantine ORDER BY seq ASC, record_id ASC LIMIT ?1",
    )?;
    let entries = statement
        .query_map([limit], row_to_sync_quarantine)?
        .collect::<rusqlite::Result<Vec<_>>>()?
        .into_iter()
        .collect();
    entries
}

fn list_replayable_quarantine_on(
    connection: &Connection,
    after: Option<(i64, Uuid)>,
    limit: usize,
) -> Result<Vec<SyncQuarantineEntry>, StorageError> {
    let limit = i64::try_from(limit).map_err(|_| {
        StorageError::IncompatibleSchema("quarantine replay limit exceeded i64".into())
    })?;
    let (after_seq, after_record_id) = after
        .map(|(seq, record_id)| (Some(seq), Some(record_id.to_string())))
        .unwrap_or((None, None));
    let mut statement = connection.prepare(
        "SELECT record_id, collection, seq, revision_hlc, state_kind, semantic_hlc,
                blob, reason, required_list_id, first_failed_at, last_failed_at, attempt_count
         FROM sync_quarantine
         WHERE reason IN ('missing_dek', 'no_matching_dek')
           AND (?1 IS NULL OR seq > ?1 OR (seq = ?1 AND record_id > ?2))
         ORDER BY seq ASC, record_id ASC
         LIMIT ?3",
    )?;
    let entries = statement
        .query_map(
            params![after_seq, after_record_id, limit],
            row_to_sync_quarantine,
        )?
        .collect::<rusqlite::Result<Vec<_>>>()?
        .into_iter()
        .collect();
    entries
}

fn delete_quarantine_on(connection: &Connection, record_id: Uuid) -> Result<bool, StorageError> {
    Ok(connection.execute(
        "DELETE FROM sync_quarantine WHERE record_id = ?1",
        [record_id.to_string()],
    )? == 1)
}

fn row_to_sync_quarantine(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<Result<SyncQuarantineEntry, StorageError>> {
    let record_id = match Uuid::parse_str(&row.get::<_, String>(0)?) {
        Ok(value) => value,
        Err(error) => return Ok(Err(StorageError::InvalidUuid(error))),
    };
    let collection: String = row.get(1)?;
    let state_kind: String = row.get(4)?;
    let semantic_hlc: String = row.get(5)?;
    let blob: Option<Vec<u8>> = row.get(6)?;
    let state = match (state_kind.as_str(), blob) {
        ("live", Some(blob)) => SyncOutboxState::Live {
            mutation_hlc: semantic_hlc,
            blob,
        },
        ("tombstone", None) => SyncOutboxState::Tombstone {
            delete_hlc: semantic_hlc,
        },
        _ => return Ok(Err(StorageError::InvalidSyncState(state_kind))),
    };
    let required_list_id = match row.get::<_, Option<String>>(8)? {
        Some(value) => match Uuid::parse_str(&value) {
            Ok(value) => Some(value),
            Err(error) => return Ok(Err(StorageError::InvalidUuid(error))),
        },
        None => None,
    };
    Ok(Ok(SyncQuarantineEntry {
        record_id,
        collection,
        seq: row.get(2)?,
        revision_hlc: row.get(3)?,
        state,
        reason: row.get(7)?,
        required_list_id,
        first_failed_at: row.get(9)?,
        last_failed_at: row.get(10)?,
        attempt_count: row.get(11)?,
    }))
}

fn has_outbox_head_on(
    connection: &Connection,
    collection: &str,
    record_id: Uuid,
) -> Result<bool, StorageError> {
    validate_sync_collection(collection)?;
    let existing = connection
        .query_row(
            "SELECT collection
             FROM sync_outbox
             WHERE record_id = ?1",
            [record_id.to_string()],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    if let Some(existing) = existing {
        ensure_requested_collection(record_id, &existing, collection)?;
        Ok(true)
    } else {
        Ok(false)
    }
}

fn ack_outbox_op_on(connection: &Connection, op_id: Uuid) -> Result<bool, StorageError> {
    let changed = connection.execute(
        "DELETE FROM sync_outbox WHERE op_id = ?1",
        [op_id.to_string()],
    )?;
    Ok(changed == 1)
}

fn validate_sync_collection(collection: &str) -> Result<(), StorageError> {
    match collection {
        "lists" | "tasks" => Ok(()),
        other => Err(StorageError::InvalidSyncCollection(other.to_string())),
    }
}

fn ensure_sync_collection_matches(
    connection: &Connection,
    record_id: Uuid,
    requested: &str,
) -> Result<(), StorageError> {
    let existing = connection
        .query_row(
            "SELECT collection FROM sync_record_states WHERE record_id = ?1
             UNION ALL
             SELECT collection FROM sync_outbox WHERE record_id = ?1
             UNION ALL
             SELECT collection FROM sync_quarantine WHERE record_id = ?1
             LIMIT 1",
            [record_id.to_string()],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    if let Some(existing) = existing {
        ensure_requested_collection(record_id, &existing, requested)?;
    }
    Ok(())
}

fn ensure_requested_collection(
    record_id: Uuid,
    existing: &str,
    requested: &str,
) -> Result<(), StorageError> {
    if existing == requested {
        Ok(())
    } else {
        Err(StorageError::SyncCollectionMismatch {
            record_id,
            existing: existing.to_string(),
            requested: requested.to_string(),
        })
    }
}

fn ensure_task_exists(connection: &Connection, task_id: Uuid) -> Result<(), StorageError> {
    let exists = connection
        .query_row(
            "SELECT 1 FROM tasks WHERE id = ?1 LIMIT 1",
            [task_id.to_string()],
            |_| Ok(()),
        )
        .optional()?;
    exists.ok_or(StorageError::NotFound(task_id))
}

fn list_task_reminders_on(
    connection: &Connection,
    task_id: Uuid,
) -> Result<Vec<Reminder>, StorageError> {
    let mut statement = connection.prepare(
        "SELECT id, task_id, remind_at, snoozed_until, created_at
         FROM reminders
         WHERE task_id = ?1
         ORDER BY COALESCE(snoozed_until, remind_at) ASC, created_at ASC, id ASC",
    )?;
    let reminders = statement
        .query_map([task_id.to_string()], row_to_reminder)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(reminders)
}

fn insert_reminder_on(connection: &Connection, reminder: &Reminder) -> Result<(), StorageError> {
    connection.execute(
        "INSERT INTO reminders (id, task_id, remind_at, snoozed_until, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![
            reminder.id.to_string(),
            reminder.task_id.to_string(),
            reminder.remind_at,
            reminder.snoozed_until,
            reminder.created_at,
        ],
    )?;
    Ok(())
}

fn delete_task_reminders_on(connection: &Connection, task_id: Uuid) -> Result<(), StorageError> {
    connection.execute(
        "DELETE FROM reminders WHERE task_id = ?1",
        [task_id.to_string()],
    )?;
    Ok(())
}

fn row_to_list(row: &rusqlite::Row<'_>) -> rusqlite::Result<List> {
    let id: String = row.get(0)?;
    let org_id: Option<String> = row.get(4)?;

    Ok(List {
        id: parse_uuid(id, 0)?,
        name: row.get(1)?,
        color: row.get(2)?,
        icon: row.get(3)?,
        org_id: parse_optional_uuid(org_id, 4)?,
        sort_order: row.get(5)?,
        archived_at: row.get(6)?,
        is_default: row.get(7)?,
        created_at: row.get(8)?,
        updated_at: row.get(9)?,
    })
}

fn row_to_task(row: &rusqlite::Row<'_>) -> rusqlite::Result<Task> {
    let id: String = row.get(0)?;
    let list_id: String = row.get(1)?;
    let parent_task_id: Option<String> = row.get(2)?;
    let status: String = row.get(5)?;
    let assignee: Option<String> = row.get(14)?;

    Ok(Task {
        id: parse_uuid(id, 0)?,
        list_id: parse_uuid(list_id, 1)?,
        parent_task_id: parse_optional_uuid(parent_task_id, 2)?,
        title: row.get(3)?,
        note: row.get(4)?,
        status: status_from_str(&status).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                5,
                rusqlite::types::Type::Text,
                Box::new(error),
            )
        })?,
        priority: row.get(6)?,
        due_at: row.get(7)?,
        scheduled_at: row.get(8)?,
        estimated_minutes: row.get(9)?,
        sort_order: row.get(10)?,
        completed_at: row.get(11)?,
        closed_reason: row.get(12)?,
        deleted_at: row.get(13)?,
        assignee: parse_optional_uuid(assignee, 14)?,
        created_at: row.get(15)?,
        updated_at: row.get(16)?,
    })
}

fn row_to_home_task(row: &rusqlite::Row<'_>) -> rusqlite::Result<HomeTask> {
    Ok(HomeTask {
        task: row_to_task(row)?,
        list_name: row.get(17)?,
        is_home_target: row.get(18)?,
    })
}

fn row_to_reminder(row: &rusqlite::Row<'_>) -> rusqlite::Result<Reminder> {
    let id: String = row.get(0)?;
    let task_id: String = row.get(1)?;
    Ok(Reminder {
        id: parse_uuid(id, 0)?,
        task_id: parse_uuid(task_id, 1)?,
        remind_at: row.get(2)?,
        snoozed_until: row.get(3)?,
        created_at: row.get(4)?,
    })
}

fn row_to_sync_outbox_entry(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<Result<SyncOutboxEntry, StorageError>> {
    let op_id: String = row.get(0)?;
    let record_id: String = row.get(1)?;
    let state_kind: String = row.get(5)?;
    let semantic_hlc: String = row.get(6)?;
    let blob: Option<Vec<u8>> = row.get(7)?;
    Ok((|| {
        let state = match (state_kind.as_str(), blob) {
            ("live", Some(blob)) => SyncOutboxState::Live {
                mutation_hlc: semantic_hlc,
                blob,
            },
            ("tombstone", None) => SyncOutboxState::Tombstone {
                delete_hlc: semantic_hlc,
            },
            (kind, _) => return Err(StorageError::InvalidSyncState(kind.to_string())),
        };
        Ok(SyncOutboxEntry {
            op_id: Uuid::from_str(&op_id)?,
            record_id: Uuid::from_str(&record_id)?,
            collection: row.get(2)?,
            base_revision_hlc: row.get(3)?,
            revision_hlc: row.get(4)?,
            state,
            created_at: row.get(8)?,
        })
    })())
}

fn row_to_sync_record_state(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<Result<SyncRecordState, StorageError>> {
    let record_id: String = row.get(0)?;
    let state_kind: String = row.get(3)?;
    let semantic_hlc: String = row.get(4)?;
    let plaintext_json: Option<String> = row.get(5)?;
    Ok((|| {
        let state = match (state_kind.as_str(), plaintext_json) {
            ("live", Some(plaintext_json)) => SyncRecordSemanticState::Live {
                mutation_hlc: semantic_hlc,
                plaintext_json,
            },
            ("tombstone", None) => SyncRecordSemanticState::Tombstone {
                delete_hlc: semantic_hlc,
            },
            (kind, _) => return Err(StorageError::InvalidSyncState(kind.to_string())),
        };
        Ok(SyncRecordState {
            record_id: Uuid::from_str(&record_id)?,
            collection: row.get(1)?,
            current_revision_hlc: row.get(2)?,
            state,
            updated_at: row.get(6)?,
        })
    })())
}

fn row_to_sync_cursor(row: &rusqlite::Row<'_>) -> rusqlite::Result<SyncCursor> {
    Ok(SyncCursor {
        name: row.get(0)?,
        seq: row.get(1)?,
        updated_at: row.get(2)?,
    })
}

fn row_to_task_undo_entry(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<Result<TaskUndoEntry, StorageError>> {
    let id: String = row.get(0)?;
    let operation_type: String = row.get(1)?;
    let task_id: String = row.get(2)?;
    let list_id: String = row.get(3)?;
    let before_snapshot: String = row.get(4)?;

    Ok((|| {
        Ok(TaskUndoEntry {
            id: Uuid::from_str(&id)?,
            operation_type: undo_operation_from_str(&operation_type)?,
            task_id: Uuid::from_str(&task_id)?,
            list_id: Uuid::from_str(&list_id)?,
            before_snapshot: serde_json::from_str(&before_snapshot)?,
            after_updated_at: row.get(5)?,
            after_deleted_at: row.get(6)?,
            after_completed_at: row.get(7)?,
            created_at: row.get(8)?,
            consumed_at: row.get(9)?,
        })
    })())
}

fn parse_uuid(value: String, column: usize) -> rusqlite::Result<Uuid> {
    Uuid::from_str(&value).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(
            column,
            rusqlite::types::Type::Text,
            Box::new(error),
        )
    })
}

fn parse_optional_uuid(value: Option<String>, column: usize) -> rusqlite::Result<Option<Uuid>> {
    value.map(|value| parse_uuid(value, column)).transpose()
}

fn status_to_str(status: TaskStatus) -> &'static str {
    match status {
        TaskStatus::Todo => "todo",
        TaskStatus::InProgress => "in_progress",
        TaskStatus::Done => "done",
        TaskStatus::WontDo => "wont_do",
    }
}

fn status_from_str(value: &str) -> Result<TaskStatus, StorageError> {
    match value {
        "todo" => Ok(TaskStatus::Todo),
        "in_progress" => Ok(TaskStatus::InProgress),
        "done" => Ok(TaskStatus::Done),
        "wont_do" => Ok(TaskStatus::WontDo),
        other => Err(StorageError::InvalidStatus(other.to_string())),
    }
}

fn undo_operation_to_str(operation_type: TaskUndoOperation) -> &'static str {
    match operation_type {
        TaskUndoOperation::Delete => "delete",
        TaskUndoOperation::Complete => "complete",
        TaskUndoOperation::Edit => "edit",
    }
}

fn undo_operation_from_str(value: &str) -> Result<TaskUndoOperation, StorageError> {
    match value {
        "delete" => Ok(TaskUndoOperation::Delete),
        "complete" => Ok(TaskUndoOperation::Complete),
        "edit" => Ok(TaskUndoOperation::Edit),
        other => Err(StorageError::InvalidUndoOperation(other.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;
    use todori_crypto::{derive_local_db_key, ensure_device_key, InMemoryDeviceKeyStore};
    use todori_domain::{new_list, new_task, transition_task, update_title};

    const KEY: [u8; 32] = [0x11; 32];
    const WRONG_KEY: [u8; 32] = [0x22; 32];

    fn sample_task() -> Task {
        Task {
            id: Uuid::now_v7(),
            list_id: Uuid::now_v7(),
            parent_task_id: Some(Uuid::now_v7()),
            title: "Buy milk".to_string(),
            note: "Organic whole milk".to_string(),
            status: TaskStatus::Todo,
            priority: 2,
            due_at: Some(1_800_000_000_000),
            scheduled_at: Some(1_799_900_000_000),
            estimated_minutes: Some(15),
            sort_order: "a0".to_string(),
            completed_at: None,
            closed_reason: None,
            deleted_at: None,
            assignee: Some(Uuid::now_v7()),
            created_at: 1_799_000_000_000,
            updated_at: 1_799_000_000_000,
        }
    }

    fn sample_list(sort_order: &str) -> List {
        List {
            id: Uuid::now_v7(),
            name: format!("List {sort_order}"),
            color: "#4F8EF7".to_string(),
            icon: "list".to_string(),
            org_id: None,
            sort_order: sort_order.to_string(),
            is_default: false,
            archived_at: None,
            created_at: 1_799_000_000_000,
            updated_at: 1_799_000_000_000,
        }
    }

    fn new_live_outbox(
        record_id: Uuid,
        collection: &str,
        op_id: Uuid,
        base_revision_hlc: Option<&str>,
        revision_hlc: &str,
        mutation_hlc: &str,
        blob: Vec<u8>,
    ) -> NewSyncOutboxEntry {
        NewSyncOutboxEntry {
            op_id,
            record_id,
            collection: collection.to_string(),
            base_revision_hlc: base_revision_hlc.map(str::to_string),
            revision_hlc: revision_hlc.to_string(),
            state: SyncOutboxState::Live {
                mutation_hlc: mutation_hlc.to_string(),
                blob,
            },
            created_at: 1_799_000_000_000,
        }
    }

    fn live_record_state(
        record_id: Uuid,
        collection: &str,
        current_revision_hlc: Option<&str>,
        mutation_hlc: &str,
        plaintext_json: &str,
        updated_at: i64,
    ) -> SyncRecordState {
        SyncRecordState {
            record_id,
            collection: collection.to_string(),
            current_revision_hlc: current_revision_hlc.map(str::to_string),
            state: SyncRecordSemanticState::Live {
                mutation_hlc: mutation_hlc.to_string(),
                plaintext_json: plaintext_json.to_string(),
            },
            updated_at,
        }
    }

    fn open_raw_encrypted(path: &Path, key: &[u8; 32]) -> Connection {
        let connection = Connection::open(path).unwrap();
        apply_sqlcipher_key(&connection, key).unwrap();
        connection
    }

    fn create_baseline_v1_database(path: &Path, key: &[u8; 32], set_version: bool) {
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        transaction.execute_batch(SCHEMA).unwrap();
        if set_version {
            set_user_version(&transaction, BASELINE_SCHEMA_VERSION).unwrap();
        }
        transaction.commit().unwrap();
    }

    fn insert_baseline_v1_list(connection: &Connection, list: &List) {
        connection
            .execute(
                "INSERT INTO lists (
                    id, name, color, icon, org_id, sort_order, created_at, updated_at
                ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8
                )",
                params![
                    list.id.to_string(),
                    list.name,
                    list.color,
                    list.icon,
                    list.org_id.map(|id| id.to_string()),
                    list.sort_order,
                    list.created_at,
                    list.updated_at,
                ],
            )
            .unwrap();
    }

    fn create_v2_database(path: &Path, key: &[u8; 32]) {
        create_baseline_v1_database(path, key, true);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_lists_archived_at(&transaction).unwrap();
        set_user_version(&transaction, 2).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v3_database(path: &Path, key: &[u8; 32]) {
        create_v2_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_lists_is_default(&transaction).unwrap();
        set_user_version(&transaction, 3).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v4_database(path: &Path, key: &[u8; 32]) {
        create_v3_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        rebuild_tasks_fts_triggers(&transaction).unwrap();
        set_user_version(&transaction, 4).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v5_database(path: &Path, key: &[u8; 32]) {
        create_v4_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_settings(&transaction).unwrap();
        set_user_version(&transaction, 5).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v6_database(path: &Path, key: &[u8; 32]) {
        create_v5_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_reminders(&transaction).unwrap();
        set_user_version(&transaction, 6).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v7_database(path: &Path, key: &[u8; 32]) {
        create_v6_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_performance_indexes(&transaction).unwrap();
        set_user_version(&transaction, 7).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v9_database(path: &Path, key: &[u8; 32]) {
        create_v7_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_sync_outbox_and_cursors(&transaction).unwrap();
        set_user_version(&transaction, 8).unwrap();
        add_sync_record_states(&transaction).unwrap();
        set_user_version(&transaction, 9).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v10_database(path: &Path, key: &[u8; 32]) {
        create_v9_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_local_crypto_cache(&transaction).unwrap();
        set_user_version(&transaction, 10).unwrap();
        transaction.commit().unwrap();
    }

    fn insert_v2_list(connection: &Connection, list: &List) {
        connection
            .execute(
                "INSERT INTO lists (
                    id, name, color, icon, org_id, sort_order, archived_at,
                    created_at, updated_at
                ) VALUES (
                    ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9
                )",
                params![
                    list.id.to_string(),
                    list.name,
                    list.color,
                    list.icon,
                    list.org_id.map(|id| id.to_string()),
                    list.sort_order,
                    list.archived_at,
                    list.created_at,
                    list.updated_at,
                ],
            )
            .unwrap();
    }

    fn list_column(connection: &Connection, target: &str) -> Option<(String, i32, String)> {
        let mut statement = connection.prepare("PRAGMA table_info(lists)").unwrap();
        statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i32>(3)?,
                    row.get::<_, Option<String>>(4)?.unwrap_or_default(),
                ))
            })
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .find_map(|(name, column_type, not_null, default_value)| {
                (name == target).then_some((column_type, not_null, default_value))
            })
    }

    fn archived_at_column(connection: &Connection) -> Option<(String, i32)> {
        list_column(connection, "archived_at")
            .map(|(column_type, not_null, _)| (column_type, not_null))
    }

    fn is_default_column(connection: &Connection) -> Option<(String, i32, String)> {
        list_column(connection, "is_default")
    }

    fn index_exists(connection: &Connection, index_name: &str) -> bool {
        connection
            .query_row(
                "SELECT 1
                 FROM sqlite_master
                 WHERE type = 'index' AND name = ?1
                 LIMIT 1",
                [index_name],
                |_| Ok(()),
            )
            .optional()
            .unwrap()
            .is_some()
    }

    fn setting_column(connection: &Connection, target: &str) -> Option<(String, i32)> {
        let mut statement = connection.prepare("PRAGMA table_info(settings)").unwrap();
        statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i32>(3)?,
                ))
            })
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .find_map(|(name, column_type, not_null)| {
                (name == target).then_some((column_type, not_null))
            })
    }

    fn reminder_column(connection: &Connection, target: &str) -> Option<(String, i32)> {
        let mut statement = connection.prepare("PRAGMA table_info(reminders)").unwrap();
        statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i32>(3)?,
                ))
            })
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .find_map(|(name, column_type, not_null)| {
                (name == target).then_some((column_type, not_null))
            })
    }

    fn sync_outbox_column(connection: &Connection, target: &str) -> Option<(String, i32)> {
        let mut statement = connection
            .prepare("PRAGMA table_info(sync_outbox)")
            .unwrap();
        statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i32>(3)?,
                ))
            })
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .find_map(|(name, column_type, not_null)| {
                (name == target).then_some((column_type, not_null))
            })
    }

    fn sync_cursor_column(connection: &Connection, target: &str) -> Option<(String, i32)> {
        let mut statement = connection
            .prepare("PRAGMA table_info(sync_cursors)")
            .unwrap();
        statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i32>(3)?,
                ))
            })
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .find_map(|(name, column_type, not_null)| {
                (name == target).then_some((column_type, not_null))
            })
    }

    fn count_archived_at_columns(connection: &Connection) -> usize {
        let mut statement = connection.prepare("PRAGMA table_info(lists)").unwrap();
        statement
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .filter(|column| column == "archived_at")
            .count()
    }

    fn schema_version(connection: &Connection) -> i32 {
        connection
            .query_row("PRAGMA schema_version", [], |row| row.get(0))
            .unwrap()
    }

    #[derive(Clone, Copy)]
    enum PerformanceSeedSchema {
        Latest,
        V3,
    }

    struct PerformanceSeed {
        list_ids: Vec<Uuid>,
        today_start_ms: i64,
        tomorrow_start_ms: i64,
        task_count: usize,
        due_task_count: usize,
        closed_task_count: usize,
    }

    fn seed_performance_database(
        path: &Path,
        key: &[u8; 32],
        schema: PerformanceSeedSchema,
    ) -> PerformanceSeed {
        match schema {
            PerformanceSeedSchema::Latest => {
                let mut connection = open_encrypted(path, key).unwrap();
                insert_performance_seed(&mut connection)
            }
            PerformanceSeedSchema::V3 => {
                create_v3_database(path, key);
                let mut connection = open_raw_encrypted(path, key);
                insert_performance_seed(&mut connection)
            }
        }
    }

    fn insert_performance_seed(connection: &mut Connection) -> PerformanceSeed {
        const LIST_COUNT: usize = 10;
        const TASKS_PER_LIST: usize = 1_000;
        const ROOT_TASKS_PER_LIST: usize = 700;
        const CHILD_TASKS_PER_LIST: usize = 220;

        let today_start_ms = 1_788_220_800_000;
        let tomorrow_start_ms = today_start_ms + 86_400_000;
        let mut list_ids = Vec::with_capacity(LIST_COUNT);
        let mut due_task_count = 0;
        let mut closed_task_count = 0;
        let transaction = connection.transaction().unwrap();

        {
            let mut insert_list = transaction
                .prepare(
                    "INSERT INTO lists (
                        id, name, color, icon, org_id, sort_order, is_default,
                        archived_at, created_at, updated_at
                    ) VALUES (
                        ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10
                    )",
                )
                .unwrap();
            for list_index in 0..LIST_COUNT {
                let id = Uuid::now_v7();
                list_ids.push(id);
                insert_list
                    .execute(params![
                        id.to_string(),
                        format!("Performance List {}", list_index + 1),
                        "#4F8EF7",
                        "list",
                        Option::<String>::None,
                        format!("a{list_index:02}"),
                        list_index == 0,
                        Option::<i64>::None,
                        today_start_ms - 86_400_000,
                        today_start_ms - 86_400_000,
                    ])
                    .unwrap();
            }
        }

        {
            let mut insert_task = transaction
                .prepare(
                    "INSERT INTO tasks (
                        id, list_id, parent_task_id, title, note, status, priority,
                        due_at, scheduled_at, estimated_minutes, sort_order,
                        completed_at, closed_reason, deleted_at, assignee,
                        created_at, updated_at
                    ) VALUES (
                        ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11,
                        ?12, ?13, ?14, ?15, ?16, ?17
                    )",
                )
                .unwrap();

            for (list_index, list_id) in list_ids.iter().copied().enumerate() {
                let mut root_ids = Vec::with_capacity(ROOT_TASKS_PER_LIST);
                let mut child_ids = Vec::with_capacity(CHILD_TASKS_PER_LIST);
                for task_index in 0..TASKS_PER_LIST {
                    let id = Uuid::now_v7();
                    let parent_task_id = if task_index < ROOT_TASKS_PER_LIST {
                        root_ids.push(id);
                        None
                    } else if task_index < ROOT_TASKS_PER_LIST + CHILD_TASKS_PER_LIST {
                        let parent_id =
                            root_ids[(task_index - ROOT_TASKS_PER_LIST) % root_ids.len()];
                        child_ids.push(id);
                        Some(parent_id)
                    } else {
                        Some(
                            child_ids[(task_index - ROOT_TASKS_PER_LIST - CHILD_TASKS_PER_LIST)
                                % child_ids.len()],
                        )
                    };
                    let global_index = (list_index * TASKS_PER_LIST) + task_index;
                    let status = match global_index % 10 {
                        0 => "done",
                        1 => "wont_do",
                        2 | 3 => "in_progress",
                        _ => "todo",
                    };
                    let due_at = match global_index % 6 {
                        0 => None,
                        1 => Some(today_start_ms - 86_400_000),
                        2 => Some(today_start_ms + ((global_index % 12) as i64 * 3_600_000)),
                        3 => Some(tomorrow_start_ms + ((global_index % 8) as i64 * 3_600_000)),
                        4 => Some(tomorrow_start_ms + 7 * 86_400_000),
                        _ => None,
                    };
                    if due_at.is_some() {
                        due_task_count += 1;
                    }
                    let is_closed = status == "done" || status == "wont_do";
                    let completed_at = if is_closed {
                        closed_task_count += 1;
                        if global_index % 4 == 0 {
                            Some(today_start_ms + ((global_index % 10) as i64 * 600_000))
                        } else {
                            Some(today_start_ms - 2 * 86_400_000)
                        }
                    } else {
                        None
                    };
                    let keyword = if global_index % 17 == 0 {
                        "alpha"
                    } else if global_index % 19 == 0 {
                        "日本語"
                    } else {
                        "routine"
                    };

                    insert_task
                        .execute(params![
                            id.to_string(),
                            list_id.to_string(),
                            parent_task_id.map(|parent_id| parent_id.to_string()),
                            format!("Task {global_index:05} {keyword}"),
                            format!("Seeded note {global_index:05} for {keyword} project"),
                            status,
                            (global_index % 4) as i32,
                            due_at,
                            due_at.map(|value| value - 3_600_000),
                            Some(15 + (global_index % 6) as i32 * 10),
                            format!("a{task_index:04}"),
                            completed_at,
                            (status == "wont_do").then_some("not_now".to_string()),
                            Option::<i64>::None,
                            Option::<String>::None,
                            today_start_ms - 86_400_000 + global_index as i64,
                            today_start_ms - 43_200_000 + global_index as i64,
                        ])
                        .unwrap();
                }
            }
        }

        transaction.commit().unwrap();

        PerformanceSeed {
            list_ids,
            today_start_ms,
            tomorrow_start_ms,
            task_count: LIST_COUNT * TASKS_PER_LIST,
            due_task_count,
            closed_task_count,
        }
    }

    fn default_list_ids(connection: &Connection) -> Vec<String> {
        let mut statement = connection
            .prepare("SELECT id FROM lists WHERE is_default = 1 ORDER BY id ASC")
            .unwrap();
        statement
            .query_map([], |row| row.get::<_, String>(0))
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
    }

    fn failing_archived_at_migration(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
        transaction.execute_batch(
            "ALTER TABLE lists ADD COLUMN archived_at INTEGER NULL;
             SELECT value FROM missing_failure_injection_table;",
        )
    }

    #[test]
    fn encrypted_database_reopens_with_correct_key() {
        let file = NamedTempFile::new().unwrap();
        let task = sample_task();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteTaskRepository::new(connection);
        assert_eq!(repository.get(task.id).unwrap(), task);
    }

    #[test]
    fn encrypted_database_rejects_wrong_key_on_query() {
        let file = NamedTempFile::new().unwrap();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(sample_task()).unwrap();
        }

        let result = open_encrypted(file.path(), &WRONG_KEY);

        match result {
            Err(StorageError::InvalidDatabaseKey) => {}
            Err(error) => panic!("expected invalid database key error, got {error}"),
            Ok(_) => panic!("database opened with wrong key"),
        }
    }

    #[test]
    fn device_key_store_derived_key_reopens_database_and_rejects_other_device_key() {
        let file = NamedTempFile::new().unwrap();
        let mut store = InMemoryDeviceKeyStore::new();
        let task = sample_task();

        {
            let device_key = ensure_device_key(&mut store).unwrap();
            let db_key = derive_local_db_key(&device_key);
            let connection = open_encrypted(file.path(), &db_key).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        {
            let device_key = ensure_device_key(&mut store).unwrap();
            let db_key = derive_local_db_key(&device_key);
            let connection = open_encrypted(file.path(), &db_key).unwrap();
            let repository = SqliteTaskRepository::new(connection);
            assert_eq!(repository.get(task.id).unwrap(), task);
        }

        let mut other_store = InMemoryDeviceKeyStore::new();
        let other_device_key = ensure_device_key(&mut other_store).unwrap();
        let other_db_key = derive_local_db_key(&other_device_key);

        assert!(open_encrypted(file.path(), &other_db_key).is_err());
    }

    #[test]
    fn encrypted_database_is_not_plain_sqlite() {
        let file = NamedTempFile::new().unwrap();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(sample_task()).unwrap();
        }

        let plain = Connection::open(file.path()).unwrap();
        let result: rusqlite::Result<i64> =
            plain.query_row("SELECT count(*) FROM tasks", [], |row| row.get(0));

        assert!(result.is_err());
    }

    #[test]
    fn fts5_search_matches_title_and_note() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let mut task = sample_task();
        task.title = "Plan Kyoto trip".to_string();
        task.note = "Book shinkansen tickets".to_string();

        repository.insert(task.clone()).unwrap();

        assert_eq!(
            repository.search_tasks("kyoto").unwrap(),
            vec![task.clone()]
        );
        assert_eq!(repository.search_tasks("shinkansen").unwrap(), vec![task]);
        assert!(repository.search_tasks("").unwrap().is_empty());
    }

    #[test]
    fn fts5_search_tracks_title_note_updates_and_deleted_at() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let mut task = sample_task();
        task.title = "Draft itinerary".to_string();
        task.note = "Reserve hotel".to_string();
        repository.insert(task.clone()).unwrap();

        assert_eq!(
            repository.search_tasks("hotel").unwrap(),
            vec![task.clone()]
        );

        let mut updated = task.clone();
        updated.title = "Final packing list".to_string();
        updated.note = "Bring passport".to_string();
        updated.updated_at += 1;
        repository.update(updated.clone()).unwrap();

        assert!(repository.search_tasks("hotel").unwrap().is_empty());
        assert_eq!(
            repository.search_tasks("passport").unwrap(),
            vec![updated.clone()]
        );

        let mut deleted = updated.clone();
        deleted.deleted_at = Some(updated.updated_at + 1);
        deleted.updated_at += 1;
        repository.update(deleted.clone()).unwrap();

        assert!(repository.search_tasks("passport").unwrap().is_empty());

        let mut restored = deleted.clone();
        restored.deleted_at = None;
        restored.updated_at += 1;
        repository.update(restored.clone()).unwrap();

        assert_eq!(repository.search_tasks("passport").unwrap(), vec![restored]);
    }

    #[test]
    fn fts5_search_tracks_physical_task_and_list_deletes() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        let mut kept = sample_task();
        kept.list_id = list.id;
        kept.title = "Keep searchable".to_string();
        kept.note = "retained".to_string();
        kept.sort_order = "a0".to_string();
        let mut task_deleted_by_subtree = sample_task();
        task_deleted_by_subtree.list_id = list.id;
        task_deleted_by_subtree.title = "Delete searchable subtree".to_string();
        task_deleted_by_subtree.note = "temporary".to_string();
        task_deleted_by_subtree.sort_order = "a1".to_string();
        let mut task_deleted_by_list = sample_task();
        task_deleted_by_list.list_id = list.id;
        task_deleted_by_list.title = "Delete searchable list".to_string();
        task_deleted_by_list.note = "temporary".to_string();
        task_deleted_by_list.sort_order = "a2".to_string();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(kept.clone()).unwrap();
            task_repository
                .insert(task_deleted_by_subtree.clone())
                .unwrap();
            task_repository
                .insert(task_deleted_by_list.clone())
                .unwrap();
            assert_eq!(task_repository.search_tasks("searchable").unwrap().len(), 3);

            task_repository
                .delete_subtree(task_deleted_by_subtree.id)
                .unwrap();
            let titles = task_repository
                .search_tasks("searchable")
                .unwrap()
                .into_iter()
                .map(|task| task.title)
                .collect::<Vec<_>>();
            let mut titles = titles;
            titles.sort();
            assert_eq!(titles, vec!["Delete searchable list", "Keep searchable"]);
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut list_repository = SqliteListRepository::new(connection);
        list_repository.delete_with_tasks(list.id).unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let task_repository = SqliteTaskRepository::new(connection);
        assert!(task_repository
            .search_tasks("searchable")
            .unwrap()
            .is_empty());
    }

    #[test]
    fn fts5_search_supports_english_and_japanese_prefix_queries() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let mut english = sample_task();
        english.title = "Buy milk".to_string();
        english.note = "Organic whole milk".to_string();
        english.updated_at = 1_799_000_000_000;
        let mut japanese = sample_task();
        japanese.title = "牛乳を買う".to_string();
        japanese.note = "明日の朝".to_string();
        japanese.updated_at = 1_799_000_001_000;
        repository.insert(english.clone()).unwrap();
        repository.insert(japanese.clone()).unwrap();

        assert_eq!(repository.search_tasks("milk").unwrap(), vec![english]);
        assert_eq!(
            repository.search_tasks("牛乳").unwrap(),
            vec![japanese.clone()]
        );
        assert_eq!(repository.search_tasks("明日").unwrap(), vec![japanese]);
        assert!(repository.search_tasks("乳").unwrap().is_empty());
    }

    #[test]
    fn v3_database_migrates_to_v4_and_backfills_tasks_fts() {
        let file = NamedTempFile::new().unwrap();
        create_v3_database(file.path(), &KEY);
        let mut task = sample_task();
        task.title = "Legacy searchable task".to_string();
        task.note = "Backfill target".to_string();
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteTaskRepository::new(connection);
        task.sort_order = "00000000000000010000000000000000".to_string();

        assert_eq!(
            read_user_version(repository.connection()).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(repository.search_tasks("backfill").unwrap(), vec![task]);
    }

    #[test]
    fn v6_database_migrates_to_v7_and_adds_performance_indexes() {
        let file = NamedTempFile::new().unwrap();
        create_v6_database(file.path(), &KEY);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert!(index_exists(&connection, "idx_tasks_list_sort_order"));
        assert!(index_exists(&connection, "idx_tasks_home_targets"));
    }

    #[test]
    fn v7_database_migrates_to_latest_sync_state_tables() {
        let file = NamedTempFile::new().unwrap();
        create_v7_database(file.path(), &KEY);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            sync_outbox_column(&connection, "record_id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            sync_outbox_column(&connection, "collection"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            sync_outbox_column(&connection, "op_id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            sync_outbox_column(&connection, "base_revision_hlc"),
            Some(("TEXT".to_string(), 0))
        );
        assert_eq!(
            sync_outbox_column(&connection, "revision_hlc"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            sync_outbox_column(&connection, "state_kind"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            sync_outbox_column(&connection, "blob"),
            Some(("BLOB".to_string(), 0))
        );
        assert_eq!(
            sync_cursor_column(&connection, "seq"),
            Some(("INTEGER".to_string(), 1))
        );
        assert!(index_exists(&connection, "idx_sync_outbox_stable_order"));
    }

    #[test]
    fn v9_database_migrates_to_latest_and_adds_local_crypto_cache() {
        let file = NamedTempFile::new().unwrap();
        create_v9_database(file.path(), &KEY);
        let tenant_id = Uuid::now_v7();
        let user_id = Uuid::now_v7();
        let device_id = Uuid::now_v7();
        let connection = open_raw_encrypted(file.path(), &KEY);
        for (key, value, updated_at) in [
            ("account_tenant_id", tenant_id.to_string(), 100),
            ("account_user_id", user_id.to_string(), 200),
            ("account_device_id", device_id.to_string(), 300),
        ] {
            connection
                .execute(
                    "INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)",
                    params![key, value, updated_at],
                )
                .unwrap();
        }
        drop(connection);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            table_columns(&connection, "local_profile_binding").unwrap(),
            vec![
                "singleton",
                "tenant_id",
                "user_id",
                "device_id",
                "bound_at",
                "updated_at",
            ]
        );
        assert_eq!(
            table_columns(&connection, "local_list_key_bundles").unwrap(),
            vec!["tenant_id", "list_id", "wrapped_list_dek", "updated_at"]
        );
        assert!(index_exists(
            &connection,
            "idx_local_list_key_bundles_tenant"
        ));
        assert_eq!(
            SqliteLocalCryptoRepository::new(connection)
                .load_binding()
                .unwrap(),
            Some(LocalProfileBinding {
                tenant_id,
                user_id,
                device_id,
                bound_at: 100,
                updated_at: 300,
            })
        );
    }

    #[test]
    fn v10_migration_discards_v1_sync_metadata_but_preserves_domain_rows() {
        let file = NamedTempFile::new().unwrap();
        create_v10_database(file.path(), &KEY);
        let list = sample_list("a0");
        let mut task = sample_task();
        task.list_id = list.id;
        task.parent_task_id = None;
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            let mut repository = SqliteListRepository::new(connection);
            repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            connection
                .execute(
                    "INSERT INTO sync_outbox (
                         record_id, collection, hlc, deleted, blob, created_at
                     ) VALUES (?1, 'tasks', 'v1-hlc', 0, X'01', 1)",
                    [task.id.to_string()],
                )
                .unwrap();
            connection
                .execute(
                    "INSERT INTO sync_record_states (
                         record_id, collection, plaintext_json, updated_at
                     ) VALUES (?1, 'tasks', '{}', 1)",
                    [task.id.to_string()],
                )
                .unwrap();
            connection
                .execute(
                    "INSERT INTO sync_cursors (name, seq, updated_at)
                     VALUES ('default', 99, 1)",
                    [],
                )
                .unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut migrated_list = list.clone();
        migrated_list.sort_order = "00000000000000010000000000000000".to_string();
        let mut migrated_task = task.clone();
        migrated_task.sort_order = "00000000000000010000000000000000".to_string();
        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(get_list_on(&connection, list.id).unwrap(), migrated_list);
        assert_eq!(get_task_on(&connection, task.id).unwrap(), migrated_task);
        let repository = SqliteSyncStateRepository::new(connection);
        assert!(repository.list_outbox_heads(10).unwrap().is_empty());
        assert_eq!(repository.get_record_state("tasks", task.id).unwrap(), None);
        assert_eq!(repository.get_cursor("default").unwrap(), None);
    }

    #[test]
    fn local_crypto_cache_roundtrips_and_same_account_replaces_bundles() {
        let file = NamedTempFile::new().unwrap();
        let tenant_id = Uuid::now_v7();
        let user_id = Uuid::now_v7();
        let first_device_id = Uuid::now_v7();
        let second_device_id = Uuid::now_v7();
        let first_list_id = Uuid::now_v7();
        let second_list_id = Uuid::now_v7();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteLocalCryptoRepository::new(connection);
        let initial_binding = LocalProfileBinding {
            tenant_id,
            user_id,
            device_id: first_device_id,
            bound_at: 100,
            updated_at: 100,
        };
        repository
            .bind_and_replace_bundles(
                initial_binding.clone(),
                &[LocalListKeyBundle {
                    tenant_id,
                    list_id: first_list_id,
                    wrapped_list_dek: vec![1, 2, 3],
                    updated_at: 100,
                }],
            )
            .unwrap();

        assert_eq!(repository.load_binding().unwrap(), Some(initial_binding));
        assert_eq!(
            repository.load_bundles(tenant_id).unwrap(),
            vec![LocalListKeyBundle {
                tenant_id,
                list_id: first_list_id,
                wrapped_list_dek: vec![1, 2, 3],
                updated_at: 100,
            }]
        );

        repository
            .bind_and_replace_bundles(
                LocalProfileBinding {
                    tenant_id,
                    user_id,
                    device_id: second_device_id,
                    bound_at: 999,
                    updated_at: 200,
                },
                &[LocalListKeyBundle {
                    tenant_id,
                    list_id: second_list_id,
                    wrapped_list_dek: vec![4, 5, 6],
                    updated_at: 200,
                }],
            )
            .unwrap();

        assert_eq!(
            repository.load_binding().unwrap(),
            Some(LocalProfileBinding {
                tenant_id,
                user_id,
                device_id: second_device_id,
                bound_at: 100,
                updated_at: 200,
            })
        );
        assert_eq!(
            repository.load_bundles(tenant_id).unwrap(),
            vec![LocalListKeyBundle {
                tenant_id,
                list_id: second_list_id,
                wrapped_list_dek: vec![4, 5, 6],
                updated_at: 200,
            }]
        );
    }

    #[test]
    fn failed_local_crypto_cache_replace_rolls_back_binding_and_bundles() {
        let file = NamedTempFile::new().unwrap();
        let tenant_id = Uuid::now_v7();
        let user_id = Uuid::now_v7();
        let first_device_id = Uuid::now_v7();
        let second_device_id = Uuid::now_v7();
        let list_id = Uuid::now_v7();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteLocalCryptoRepository::new(connection);
        let original_binding = LocalProfileBinding {
            tenant_id,
            user_id,
            device_id: first_device_id,
            bound_at: 100,
            updated_at: 100,
        };
        let original_bundle = LocalListKeyBundle {
            tenant_id,
            list_id,
            wrapped_list_dek: vec![1, 2, 3],
            updated_at: 100,
        };
        repository
            .bind_and_replace_bundles(original_binding.clone(), &[original_bundle.clone()])
            .unwrap();

        let result = repository.bind_and_replace_bundles(
            LocalProfileBinding {
                tenant_id,
                user_id,
                device_id: second_device_id,
                bound_at: 100,
                updated_at: 200,
            },
            &[LocalListKeyBundle {
                tenant_id,
                list_id: Uuid::now_v7(),
                wrapped_list_dek: Vec::new(),
                updated_at: 200,
            }],
        );

        assert!(matches!(result, Err(StorageError::Sqlite(_))));
        assert_eq!(repository.load_binding().unwrap(), Some(original_binding));
        assert_eq!(
            repository.load_bundles(tenant_id).unwrap(),
            vec![original_bundle]
        );
    }

    #[test]
    fn local_crypto_cache_rejects_tenant_and_user_rebinding() {
        let file = NamedTempFile::new().unwrap();
        let tenant_id = Uuid::now_v7();
        let user_id = Uuid::now_v7();
        let binding = LocalProfileBinding {
            tenant_id,
            user_id,
            device_id: Uuid::now_v7(),
            bound_at: 100,
            updated_at: 100,
        };
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteLocalCryptoRepository::new(connection);
        repository
            .bind_and_replace_bundles(binding.clone(), &[])
            .unwrap();

        let other_tenant_id = Uuid::now_v7();
        assert!(matches!(
            repository.bind_and_replace_bundles(
                LocalProfileBinding {
                    tenant_id: other_tenant_id,
                    ..binding.clone()
                },
                &[]
            ),
            Err(StorageError::LocalProfileTenantMismatch {
                bound_tenant_id,
                requested_tenant_id,
            }) if bound_tenant_id == tenant_id && requested_tenant_id == other_tenant_id
        ));

        let other_user_id = Uuid::now_v7();
        assert!(matches!(
            repository.bind_and_replace_bundles(
                LocalProfileBinding {
                    user_id: other_user_id,
                    ..binding.clone()
                },
                &[]
            ),
            Err(StorageError::LocalProfileUserMismatch {
                bound_user_id,
                requested_user_id,
            }) if bound_user_id == user_id && requested_user_id == other_user_id
        ));
        assert!(matches!(
            repository.load_bundles(other_tenant_id),
            Err(StorageError::LocalProfileTenantMismatch {
                bound_tenant_id,
                requested_tenant_id,
            }) if bound_tenant_id == tenant_id && requested_tenant_id == other_tenant_id
        ));
        assert_eq!(repository.load_binding().unwrap(), Some(binding));
    }

    #[test]
    fn local_crypto_cache_rejects_foreign_tenant_rows() {
        let file = NamedTempFile::new().unwrap();
        let tenant_id = Uuid::now_v7();
        let binding = LocalProfileBinding {
            tenant_id,
            user_id: Uuid::now_v7(),
            device_id: Uuid::now_v7(),
            bound_at: 100,
            updated_at: 100,
        };
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteLocalCryptoRepository::new(connection);
        repository
            .bind_and_replace_bundles(binding.clone(), &[])
            .unwrap();
        repository
            .connection()
            .execute(
                "INSERT INTO local_list_key_bundles (
                     tenant_id, list_id, wrapped_list_dek, updated_at
                 ) VALUES (?1, ?2, ?3, ?4)",
                params![
                    Uuid::now_v7().to_string(),
                    Uuid::now_v7().to_string(),
                    vec![1_u8, 2, 3],
                    100,
                ],
            )
            .unwrap();

        assert!(matches!(
            repository.load_bundles(tenant_id),
            Err(StorageError::LocalCryptoCacheTenantMismatch)
        ));
        repository.bind_and_replace_bundles(binding, &[]).unwrap();
        assert!(repository.load_bundles(tenant_id).unwrap().is_empty());
    }

    #[test]
    fn local_crypto_cache_survives_encrypted_database_reopen() {
        let file = NamedTempFile::new().unwrap();
        let tenant_id = Uuid::now_v7();
        let binding = LocalProfileBinding {
            tenant_id,
            user_id: Uuid::now_v7(),
            device_id: Uuid::now_v7(),
            bound_at: 100,
            updated_at: 100,
        };
        let bundle = LocalListKeyBundle {
            tenant_id,
            list_id: Uuid::now_v7(),
            wrapped_list_dek: vec![9, 8, 7],
            updated_at: 100,
        };
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteLocalCryptoRepository::new(connection);
            repository
                .bind_and_replace_bundles(binding.clone(), &[bundle.clone()])
                .unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteLocalCryptoRepository::new(connection);

        assert_eq!(repository.load_binding().unwrap(), Some(binding));
        assert_eq!(repository.load_bundles(tenant_id).unwrap(), vec![bundle]);
    }

    #[test]
    #[ignore = "task-67 manual performance verification for a 10k encrypted seed"]
    fn task_67_reports_10000_task_storage_timings() {
        let file = NamedTempFile::new().unwrap();
        let seed = seed_performance_database(file.path(), &KEY, PerformanceSeedSchema::Latest);
        assert_eq!(seed.list_ids.len(), 10);
        assert_eq!(seed.task_count, 10_000);

        let mut rows: Vec<(&str, usize, u128, String)> = Vec::new();

        let started = std::time::Instant::now();
        let home_tasks = {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let repository = SqliteTaskRepository::new(connection);
            repository
                .list_home(seed.today_start_ms, seed.tomorrow_start_ms)
                .unwrap()
        };
        rows.push((
            "get_today_tasks(list_home)",
            home_tasks.len(),
            started.elapsed().as_millis(),
            "cross-list Home query on encrypted DB".to_string(),
        ));

        let started = std::time::Instant::now();
        let list_tasks = {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let repository = SqliteTaskRepository::new(connection);
            repository.list_active_by_list(seed.list_ids[0]).unwrap()
        };
        rows.push((
            "get_tasks(list 1)",
            list_tasks.len(),
            started.elapsed().as_millis(),
            "single list, 1000 tasks".to_string(),
        ));

        let started = std::time::Instant::now();
        let search_results = {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let repository = SqliteTaskRepository::new(connection);
            repository.search_tasks("alpha").unwrap()
        };
        rows.push((
            "search_tasks(alpha)",
            search_results.len(),
            started.elapsed().as_millis(),
            "FTS5 prefix query".to_string(),
        ));

        let migration_file = NamedTempFile::new().unwrap();
        let migration_seed =
            seed_performance_database(migration_file.path(), &KEY, PerformanceSeedSchema::V3);
        assert_eq!(migration_seed.task_count, 10_000);
        let started = std::time::Instant::now();
        let migrated_connection = open_encrypted(migration_file.path(), &KEY).unwrap();
        let migration_elapsed_ms = started.elapsed().as_millis();
        assert_eq!(
            read_user_version(&migrated_connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        rows.push((
            "migration(v3_to_latest)",
            migration_seed.task_count,
            migration_elapsed_ms,
            "v4 FTS backfill + v5-v7 migrations".to_string(),
        ));

        let started = std::time::Instant::now();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteListRepository::new(connection);
            repository
                .ensure_default_list("Inbox".to_string(), seed.today_start_ms)
                .unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let repository = SqliteListRepository::new(connection);
            assert_eq!(repository.list_all().unwrap().len(), 10);
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let repository = SqliteListRepository::new(connection);
            assert!(repository.list_archived().unwrap().is_empty());
        }
        let startup_home_count = {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let repository = SqliteTaskRepository::new(connection);
            repository
                .list_home(seed.today_start_ms, seed.tomorrow_start_ms)
                .unwrap()
                .len()
        };
        let startup_elapsed_ms = started.elapsed().as_millis();
        rows.push((
            "startup_approx(init+initial_queries)",
            startup_home_count,
            startup_elapsed_ms,
            "open+default list+lists+archived+Home".to_string(),
        ));

        println!(
            "task-67 Rust performance seed: lists=10 tasks={} due={} closed={}",
            seed.task_count, seed.due_task_count, seed.closed_task_count
        );
        println!("| operation | rows | elapsed_ms | note |");
        println!("|---|---:|---:|---|");
        for (operation, count, elapsed_ms, note) in &rows {
            println!("| {operation} | {count} | {elapsed_ms} | {note} |");
        }

        assert_eq!(list_tasks.len(), 1_000);
        assert!(!home_tasks.is_empty());
        assert!(!search_results.is_empty());
        assert!(
            startup_elapsed_ms < 2_000,
            "startup approximation exceeded F-50: {startup_elapsed_ms} ms"
        );
    }

    #[test]
    fn fts5_search_works_after_reopening_encrypted_database() {
        let file = NamedTempFile::new().unwrap();
        let mut task = sample_task();
        task.title = "Encrypted search".to_string();
        task.note = "SQLCipher FTS5".to_string();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteTaskRepository::new(connection);

        assert_eq!(repository.search_tasks("sqlcipher").unwrap(), vec![task]);
    }

    #[test]
    fn new_database_is_created_via_baseline_and_migrated_to_latest_schema() {
        let file = NamedTempFile::new().unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            archived_at_column(&connection),
            Some(("INTEGER".to_string(), 0))
        );
        assert_eq!(
            is_default_column(&connection),
            Some(("INTEGER".to_string(), 1, "0".to_string()))
        );
        assert_eq!(
            setting_column(&connection, "key"),
            Some(("TEXT".to_string(), 0))
        );
        assert_eq!(
            setting_column(&connection, "value"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            setting_column(&connection, "updated_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "task_id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "remind_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "snoozed_until"),
            Some(("INTEGER".to_string(), 0))
        );
        assert_eq!(
            sync_outbox_column(&connection, "created_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            sync_cursor_column(&connection, "updated_at"),
            Some(("INTEGER".to_string(), 1))
        );
    }

    #[test]
    fn v1_database_migrates_to_latest_and_preserves_existing_data() {
        let file = NamedTempFile::new().unwrap();
        create_baseline_v1_database(file.path(), &KEY, true);

        let mut list = sample_list("a0");
        list.is_default = true;
        let mut task = sample_task();
        task.list_id = list.id;
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            insert_baseline_v1_list(&connection, &list);
        }
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        list.sort_order = "00000000000000010000000000000000".to_string();
        task.sort_order = "00000000000000010000000000000000".to_string();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            archived_at_column(&connection),
            Some(("INTEGER".to_string(), 0))
        );
        assert_eq!(
            is_default_column(&connection),
            Some(("INTEGER".to_string(), 1, "0".to_string()))
        );
        assert_eq!(
            setting_column(&connection, "value"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "created_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            sync_outbox_column(&connection, "blob"),
            Some(("BLOB".to_string(), 0))
        );
        assert_eq!(
            sync_cursor_column(&connection, "name"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            SqliteListRepository::new(open_encrypted(file.path(), &KEY).unwrap())
                .get(list.id)
                .unwrap(),
            list
        );
        assert_eq!(
            SqliteTaskRepository::new(open_encrypted(file.path(), &KEY).unwrap())
                .get(task.id)
                .unwrap(),
            task
        );
    }

    #[test]
    fn legacy_user_version_zero_v1_database_is_promoted_and_migrated() {
        let file = NamedTempFile::new().unwrap();
        create_baseline_v1_database(file.path(), &KEY, false);

        let mut list = sample_list("legacy");
        list.is_default = true;
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            insert_baseline_v1_list(&connection, &list);
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        list.sort_order = "00000000000000010000000000000000".to_string();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            archived_at_column(&connection),
            Some(("INTEGER".to_string(), 0))
        );
        assert_eq!(
            is_default_column(&connection),
            Some(("INTEGER".to_string(), 1, "0".to_string()))
        );
        assert_eq!(
            setting_column(&connection, "updated_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "task_id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            sync_outbox_column(&connection, "revision_hlc"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            SqliteListRepository::new(connection).get(list.id).unwrap(),
            list
        );
    }

    #[test]
    fn sqlite_settings_repository_returns_none_for_missing_key() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteSettingsRepository::new(connection);

        assert_eq!(repository.get_setting("ui_mode").unwrap(), None);
    }

    #[test]
    fn sqlite_settings_repository_roundtrips_setting() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSettingsRepository::new(connection);

        repository
            .set_setting("ui_mode", "simple", 1_799_000_000_000)
            .unwrap();

        assert_eq!(
            repository.get_setting("ui_mode").unwrap(),
            Some("simple".to_string())
        );
    }

    #[test]
    fn sqlite_settings_repository_overwrites_existing_setting() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSettingsRepository::new(connection);

        repository
            .set_setting("ui_mode", "simple", 1_799_000_000_000)
            .unwrap();
        repository
            .set_setting("ui_mode", "advanced", 1_799_000_001_000)
            .unwrap();

        assert_eq!(
            repository.get_setting("ui_mode").unwrap(),
            Some("advanced".to_string())
        );
        let updated_at: i64 = repository
            .connection()
            .query_row(
                "SELECT updated_at FROM settings WHERE key = ?1",
                ["ui_mode"],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(updated_at, 1_799_000_001_000);
    }

    #[test]
    fn sqlite_sync_state_repository_coalesces_record_head_and_old_ack_is_safe() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSyncStateRepository::new(connection);
        let record_id = Uuid::now_v7();
        let first_op_id = Uuid::now_v7();
        let second_op_id = Uuid::now_v7();

        repository
            .put_outbox_head(new_live_outbox(
                record_id,
                "tasks",
                first_op_id,
                Some("base-0"),
                "revision-1",
                "mutation-1",
                vec![1, 2, 3],
            ))
            .unwrap();
        let second = repository
            .put_outbox_head(NewSyncOutboxEntry {
                op_id: second_op_id,
                record_id,
                collection: "tasks".to_string(),
                base_revision_hlc: Some("base-0".to_string()),
                revision_hlc: "revision-2".to_string(),
                state: SyncOutboxState::Tombstone {
                    delete_hlc: "delete-2".to_string(),
                },
                created_at: 1_799_000_000_001,
            })
            .unwrap();

        assert_eq!(repository.list_outbox_heads(10).unwrap(), vec![second]);
        assert!(!repository.ack_outbox_op(first_op_id).unwrap());
        assert_eq!(repository.list_outbox_heads(10).unwrap().len(), 1);
        assert!(repository.ack_outbox_op(second_op_id).unwrap());
        assert!(repository.list_outbox_heads(10).unwrap().is_empty());
        assert!(!repository.ack_outbox_op(second_op_id).unwrap());
    }

    #[test]
    fn durable_quarantine_is_idempotent_and_blocks_only_its_record_outbox() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSyncStateRepository::new(connection);
        let blocked_id = Uuid::now_v7();
        let unrelated_id = Uuid::now_v7();
        for record_id in [blocked_id, unrelated_id] {
            repository
                .put_outbox_head(new_live_outbox(
                    record_id,
                    "tasks",
                    Uuid::now_v7(),
                    None,
                    "revision-local",
                    "mutation-local",
                    vec![9],
                ))
                .unwrap();
        }
        let quarantined = SyncQuarantineEntry {
            record_id: blocked_id,
            collection: "tasks".to_string(),
            seq: 7,
            revision_hlc: "revision-remote".to_string(),
            state: SyncOutboxState::Live {
                mutation_hlc: "mutation-remote".to_string(),
                blob: vec![1, 2, 3],
            },
            reason: "no_matching_dek".to_string(),
            required_list_id: None,
            first_failed_at: 10,
            last_failed_at: 10,
            attempt_count: 1,
        };
        repository.put_quarantine(quarantined.clone()).unwrap();
        repository
            .put_quarantine(SyncQuarantineEntry {
                state: SyncOutboxState::Tombstone {
                    delete_hlc: "must-not-replace".to_string(),
                },
                reason: "authentication_failed".to_string(),
                last_failed_at: 20,
                ..quarantined.clone()
            })
            .unwrap();

        let rows = repository.list_quarantine(10).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].attempt_count, 2);
        assert_eq!(rows[0].first_failed_at, 10);
        assert_eq!(rows[0].last_failed_at, 20);
        assert_eq!(rows[0].reason, "authentication_failed");
        assert_eq!(
            rows[0].state,
            SyncOutboxState::Live {
                mutation_hlc: "mutation-remote".to_string(),
                blob: vec![1, 2, 3]
            }
        );

        repository
            .put_quarantine(SyncQuarantineEntry {
                seq: 6,
                revision_hlc: "older-revision".to_string(),
                last_failed_at: 30,
                ..quarantined.clone()
            })
            .unwrap();
        let rows = repository.list_quarantine(10).unwrap();
        assert_eq!(rows[0].seq, 7);
        assert_eq!(rows[0].revision_hlc, "revision-remote");
        assert_eq!(rows[0].attempt_count, 2);
        assert!(matches!(
            repository.put_quarantine(SyncQuarantineEntry {
                revision_hlc: "different-at-same-seq".to_string(),
                ..quarantined.clone()
            }),
            Err(StorageError::IncompatibleSchema(_))
        ));
        assert!(matches!(
            repository.put_quarantine(SyncQuarantineEntry {
                collection: "lists".to_string(),
                ..quarantined.clone()
            }),
            Err(StorageError::SyncCollectionMismatch { .. })
        ));
        assert!(matches!(
            repository.put_record_state(SyncRecordState {
                record_id: blocked_id,
                collection: "lists".to_string(),
                current_revision_hlc: None,
                state: SyncRecordSemanticState::Tombstone {
                    delete_hlc: "delete".to_string(),
                },
                updated_at: 30,
            }),
            Err(StorageError::SyncCollectionMismatch { .. })
        ));

        repository
            .put_quarantine(SyncQuarantineEntry {
                seq: 8,
                revision_hlc: "newer-revision".to_string(),
                state: SyncOutboxState::Tombstone {
                    delete_hlc: "newer-delete".to_string(),
                },
                reason: "corrupt_envelope".to_string(),
                first_failed_at: 40,
                last_failed_at: 40,
                ..quarantined
            })
            .unwrap();
        let rows = repository.list_quarantine(10).unwrap();
        assert_eq!(rows[0].seq, 8);
        assert_eq!(rows[0].revision_hlc, "newer-revision");
        assert_eq!(rows[0].attempt_count, 1);
        assert_eq!(rows[0].first_failed_at, 40);
        assert!(matches!(rows[0].state, SyncOutboxState::Tombstone { .. }));
        let pushable = repository.list_outbox_heads(10).unwrap();
        assert_eq!(pushable.len(), 1);
        assert_eq!(pushable[0].record_id, unrelated_id);
        assert!(repository.has_outbox_head("tasks", blocked_id).unwrap());
        assert!(repository.delete_quarantine(blocked_id).unwrap());
        assert_eq!(repository.list_outbox_heads(10).unwrap().len(), 2);
    }

    #[test]
    fn replayable_quarantine_query_skips_corruption_without_head_of_line_blocking() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSyncStateRepository::new(connection);
        for seq in 1..=100 {
            repository
                .put_quarantine(SyncQuarantineEntry {
                    record_id: Uuid::now_v7(),
                    collection: "lists".to_string(),
                    seq,
                    revision_hlc: format!("corrupt-{seq}"),
                    state: SyncOutboxState::Live {
                        mutation_hlc: format!("mutation-{seq}"),
                        blob: vec![1],
                    },
                    reason: "corrupt_envelope".to_string(),
                    required_list_id: None,
                    first_failed_at: 10,
                    last_failed_at: 10,
                    attempt_count: 1,
                })
                .unwrap();
        }
        let waiting_id = Uuid::now_v7();
        repository
            .put_quarantine(SyncQuarantineEntry {
                record_id: waiting_id,
                collection: "lists".to_string(),
                seq: 101,
                revision_hlc: "waiting".to_string(),
                state: SyncOutboxState::Live {
                    mutation_hlc: "waiting-mutation".to_string(),
                    blob: vec![1],
                },
                reason: "missing_dek".to_string(),
                required_list_id: Some(waiting_id),
                first_failed_at: 10,
                last_failed_at: 10,
                attempt_count: 1,
            })
            .unwrap();

        let replayable = repository.list_replayable_quarantine(None, 100).unwrap();
        assert_eq!(replayable.len(), 1);
        assert_eq!(replayable[0].record_id, waiting_id);
        assert_eq!(repository.list_quarantine(100).unwrap().len(), 100);
    }

    #[test]
    fn sqlite_sync_state_repository_preserves_tagged_heads_and_states_after_reopen() {
        let file = NamedTempFile::new().unwrap();
        let record_id = Uuid::now_v7();
        let op_id = Uuid::now_v7();
        let stored = {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteSyncStateRepository::new(connection);
            let stored = repository
                .put_outbox_head(NewSyncOutboxEntry {
                    op_id,
                    record_id,
                    collection: "tasks".to_string(),
                    base_revision_hlc: Some("base-reopen".to_string()),
                    revision_hlc: "revision-reopen".to_string(),
                    state: SyncOutboxState::Live {
                        mutation_hlc: "mutation-reopen".to_string(),
                        blob: vec![7, 8, 9],
                    },
                    created_at: 1_799_000_000_000,
                })
                .unwrap();
            repository
                .put_record_state(SyncRecordState {
                    record_id,
                    collection: "tasks".to_string(),
                    current_revision_hlc: Some("revision-reopen".to_string()),
                    state: SyncRecordSemanticState::Tombstone {
                        delete_hlc: "delete-reopen".to_string(),
                    },
                    updated_at: 1_799_000_000_001,
                })
                .unwrap();
            stored
        };

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteSyncStateRepository::new(connection);

        assert_eq!(repository.list_outbox_heads(10).unwrap(), vec![stored]);
        assert_eq!(
            repository.get_record_state("tasks", record_id).unwrap(),
            Some(SyncRecordState {
                record_id,
                collection: "tasks".to_string(),
                current_revision_hlc: Some("revision-reopen".to_string()),
                state: SyncRecordSemanticState::Tombstone {
                    delete_hlc: "delete-reopen".to_string(),
                },
                updated_at: 1_799_000_000_001,
            })
        );
    }

    #[test]
    fn sqlite_sync_state_rejects_unknown_and_changed_collections() {
        let file = NamedTempFile::new().unwrap();
        let record_id = Uuid::now_v7();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSyncStateRepository::new(connection);

        assert!(matches!(
            repository.put_outbox_head(new_live_outbox(
                record_id,
                "unknown",
                Uuid::now_v7(),
                None,
                "revision-1",
                "mutation-1",
                vec![1],
            )),
            Err(StorageError::InvalidSyncCollection(collection)) if collection == "unknown"
        ));

        repository
            .put_record_state(live_record_state(
                record_id,
                "tasks",
                None,
                "mutation-1",
                "{}",
                1,
            ))
            .unwrap();
        assert!(matches!(
            repository.put_outbox_head(new_live_outbox(
                record_id,
                "lists",
                Uuid::now_v7(),
                None,
                "revision-2",
                "mutation-2",
                vec![2],
            )),
            Err(StorageError::SyncCollectionMismatch {
                record_id: mismatch_id,
                existing,
                requested,
            }) if mismatch_id == record_id && existing == "tasks" && requested == "lists"
        ));
        assert!(matches!(
            repository.get_record_state("lists", record_id),
            Err(StorageError::SyncCollectionMismatch { .. })
        ));
    }

    #[test]
    fn sync_v2_schema_rejects_malformed_live_and_tombstone_rows() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let record_id = Uuid::now_v7();
        let op_id = Uuid::now_v7();

        let live_without_blob = connection.execute(
            "INSERT INTO sync_outbox (
                 record_id, collection, op_id, revision_hlc,
                 state_kind, semantic_hlc, blob, created_at
             ) VALUES (?1, 'tasks', ?2, 'revision', 'live', 'mutation', NULL, 1)",
            params![record_id.to_string(), op_id.to_string()],
        );
        assert!(live_without_blob.is_err());

        let tombstone_with_plaintext = connection.execute(
            "INSERT INTO sync_record_states (
                 record_id, collection, current_revision_hlc,
                 state_kind, semantic_hlc, plaintext_json, updated_at
             ) VALUES (?1, 'tasks', 'revision', 'tombstone', 'delete', '{}', 1)",
            [record_id.to_string()],
        );
        assert!(tombstone_with_plaintext.is_err());
    }

    #[test]
    fn sqlite_sync_state_repository_roundtrips_pull_cursor() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSyncStateRepository::new(connection);

        assert_eq!(repository.get_cursor("default").unwrap(), None);

        repository
            .set_cursor("default", 41, 1_799_000_000_000)
            .unwrap();
        assert_eq!(
            repository.get_cursor("default").unwrap(),
            Some(SyncCursor {
                name: "default".to_string(),
                seq: 41,
                updated_at: 1_799_000_000_000,
            })
        );

        repository
            .set_cursor("default", 42, 1_799_000_001_000)
            .unwrap();
        assert_eq!(
            repository.get_cursor("default").unwrap(),
            Some(SyncCursor {
                name: "default".to_string(),
                seq: 42,
                updated_at: 1_799_000_001_000,
            })
        );
    }

    #[test]
    fn sqlite_reminder_repository_sets_lists_clears_and_snoozes_reminders() {
        let file = NamedTempFile::new().unwrap();
        let task = sample_task();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteReminderRepository::new(connection);

        let first = repository
            .set_task_reminder(task.id, 1_800_000_000_000, 1_799_000_000_000)
            .unwrap();
        assert_eq!(first.task_id, task.id);
        assert_eq!(
            repository.list_task_reminders(task.id).unwrap(),
            vec![first.clone()]
        );

        let second = repository
            .set_task_reminder(task.id, 1_800_000_600_000, 1_799_000_001_000)
            .unwrap();
        assert_ne!(first.id, second.id);
        assert_eq!(
            repository.list_task_reminders(task.id).unwrap(),
            vec![second.clone()]
        );

        let snoozed = repository
            .snooze_reminder(second.id, 1_800_004_200_000)
            .unwrap();
        assert_eq!(snoozed.snoozed_until, Some(1_800_004_200_000));
        assert_eq!(
            repository.clear_task_reminders(task.id).unwrap(),
            vec![snoozed]
        );
        assert!(repository.list_task_reminders(task.id).unwrap().is_empty());
    }

    #[test]
    fn sqlite_reminder_repository_lists_pending_open_tasks_only() {
        let file = NamedTempFile::new().unwrap();
        let mut pending_task = sample_task();
        pending_task.status = TaskStatus::Todo;
        pending_task.sort_order = "a0".to_string();
        let mut closed_task = sample_task();
        closed_task.status = TaskStatus::Done;
        closed_task.completed_at = Some(1_799_000_010_000);
        closed_task.sort_order = "a1".to_string();
        let mut expired_task = sample_task();
        expired_task.status = TaskStatus::Todo;
        expired_task.sort_order = "a2".to_string();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(pending_task.clone()).unwrap();
            task_repository.insert(closed_task.clone()).unwrap();
            task_repository.insert(expired_task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteReminderRepository::new(connection);
        let pending = repository
            .set_task_reminder(pending_task.id, 1_800_000_000_000, 1_799_000_000_000)
            .unwrap();
        repository
            .set_task_reminder(closed_task.id, 1_800_000_000_000, 1_799_000_000_000)
            .unwrap();
        repository
            .set_task_reminder(expired_task.id, 1_799_999_999_999, 1_799_000_000_000)
            .unwrap();

        assert_eq!(
            repository
                .list_pending_reminders(1_799_999_999_999)
                .unwrap(),
            vec![pending]
        );
    }

    #[test]
    fn sqlite_reminder_repository_lists_subtree_and_list_reminders_for_cancellation() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        let mut parent = sample_task();
        parent.list_id = list.id;
        parent.parent_task_id = None;
        parent.sort_order = "a0".to_string();
        let mut child = sample_task();
        child.list_id = list.id;
        child.parent_task_id = Some(parent.id);
        child.sort_order = "a1".to_string();
        let mut other = sample_task();
        other.list_id = list.id;
        other.parent_task_id = None;
        other.sort_order = "a2".to_string();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(parent.clone()).unwrap();
            task_repository.insert(child.clone()).unwrap();
            task_repository.insert(other.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteReminderRepository::new(connection);
        let parent_reminder = repository
            .set_task_reminder(parent.id, 1_800_000_000_000, 1_799_000_000_000)
            .unwrap();
        let child_reminder = repository
            .set_task_reminder(child.id, 1_800_000_600_000, 1_799_000_000_000)
            .unwrap();
        let other_reminder = repository
            .set_task_reminder(other.id, 1_800_001_200_000, 1_799_000_000_000)
            .unwrap();

        assert_eq!(
            repository.list_task_subtree_reminders(parent.id).unwrap(),
            vec![parent_reminder.clone(), child_reminder.clone()]
        );
        assert_eq!(
            repository.list_list_reminders(list.id).unwrap(),
            vec![parent_reminder, child_reminder, other_reminder]
        );
    }

    #[test]
    fn task_and_list_physical_deletes_remove_reminders() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        let mut subtree_task = sample_task();
        subtree_task.list_id = list.id;
        subtree_task.parent_task_id = None;
        subtree_task.sort_order = "a0".to_string();
        let mut list_task = sample_task();
        list_task.list_id = list.id;
        list_task.parent_task_id = None;
        list_task.sort_order = "a1".to_string();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(subtree_task.clone()).unwrap();
            task_repository.insert(list_task.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut reminder_repository = SqliteReminderRepository::new(connection);
            reminder_repository
                .set_task_reminder(subtree_task.id, 1_800_000_000_000, 1_799_000_000_000)
                .unwrap();
            reminder_repository
                .set_task_reminder(list_task.id, 1_800_000_600_000, 1_799_000_000_000)
                .unwrap();
        }

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.delete_subtree(subtree_task.id).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let reminder_repository = SqliteReminderRepository::new(connection);
            assert!(reminder_repository
                .list_task_reminders(subtree_task.id)
                .unwrap()
                .is_empty());
            assert_eq!(
                reminder_repository
                    .list_task_reminders(list_task.id)
                    .unwrap()
                    .len(),
                1
            );
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut list_repository = SqliteListRepository::new(connection);
        list_repository.delete_with_tasks(list.id).unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let reminder_repository = SqliteReminderRepository::new(connection);
        assert!(reminder_repository
            .list_list_reminders(list.id)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn v4_database_migrates_to_v5_and_adds_settings_table() {
        let file = NamedTempFile::new().unwrap();
        create_v4_database(file.path(), &KEY);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            setting_column(&connection, "key"),
            Some(("TEXT".to_string(), 0))
        );
        assert_eq!(
            setting_column(&connection, "value"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            setting_column(&connection, "updated_at"),
            Some(("INTEGER".to_string(), 1))
        );
    }

    #[test]
    fn v5_database_migrates_to_v6_and_adds_reminders_table() {
        let file = NamedTempFile::new().unwrap();
        create_v5_database(file.path(), &KEY);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            reminder_column(&connection, "id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "task_id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "remind_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "snoozed_until"),
            Some(("INTEGER".to_string(), 0))
        );
        assert_eq!(
            reminder_column(&connection, "created_at"),
            Some(("INTEGER".to_string(), 1))
        );
    }

    #[test]
    fn v2_database_promotes_first_active_list_to_default() {
        let file = NamedTempFile::new().unwrap();
        create_v2_database(file.path(), &KEY);

        let archived = List {
            archived_at: Some(1_799_000_001_000),
            ..sample_list("a0")
        };
        let active_second = sample_list("b0");
        let mut active_first = sample_list("a1");
        active_first.created_at = active_second.created_at - 1;
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            insert_v2_list(&connection, &archived);
            insert_v2_list(&connection, &active_second);
            insert_v2_list(&connection, &active_first);
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            default_list_ids(&connection),
            vec![active_first.id.to_string()]
        );
    }

    #[test]
    fn v2_database_with_no_active_lists_does_not_promote_default() {
        let file = NamedTempFile::new().unwrap();
        create_v2_database(file.path(), &KEY);

        let archived = List {
            archived_at: Some(1_799_000_001_000),
            ..sample_list("a0")
        };
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            insert_v2_list(&connection, &archived);
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert!(default_list_ids(&connection).is_empty());
    }

    #[test]
    fn ensure_default_list_creates_default_when_missing_and_keeps_existing_name() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);

        let inbox = repository
            .ensure_default_list("Inbox".to_string(), 1_799_000_000_000)
            .unwrap();
        let again = repository
            .ensure_default_list("インボックス".to_string(), 1_799_000_001_000)
            .unwrap();

        assert_eq!(inbox.id, again.id);
        assert_eq!(again.name, "Inbox");
        assert!(again.is_default);
        assert_eq!(repository.list_all().unwrap().len(), 1);
    }

    #[test]
    fn ensure_default_list_observes_ja_name_in_empty_database() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);

        let inbox = repository
            .ensure_default_list("インボックス".to_string(), 1_799_000_000_000)
            .unwrap();

        assert_eq!(inbox.name, "インボックス");
        assert!(inbox.is_default);
    }

    #[test]
    fn unique_index_prevents_multiple_default_lists() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);
        let first = repository
            .ensure_default_list("Inbox".to_string(), 1_799_000_000_000)
            .unwrap();
        let mut second = sample_list("a1");
        second.is_default = true;

        let result = repository.insert(second);

        assert!(matches!(result, Err(StorageError::Sqlite(_))));
        assert_eq!(repository.get_default().unwrap().unwrap().id, first.id);
    }

    #[test]
    fn default_list_cannot_be_archived_or_deleted_but_can_be_renamed() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);
        let mut list = repository
            .ensure_default_list("Inbox".to_string(), 1_799_000_000_000)
            .unwrap();

        list.name = "Renamed inbox".to_string();
        list.updated_at += 1;
        repository.update(list.clone()).unwrap();
        assert_eq!(repository.get(list.id).unwrap().name, "Renamed inbox");
        assert!(repository.get(list.id).unwrap().is_default);

        let mut archived = list.clone();
        archived.archived_at = Some(1_799_000_001_000);
        assert!(matches!(
            repository.update(archived),
            Err(StorageError::DefaultListProtected {
                operation: "archived",
                list_id,
            }) if list_id == list.id
        ));
        assert!(matches!(
            repository.delete_with_tasks(list.id),
            Err(StorageError::DefaultListProtected {
                operation: "deleted",
                list_id,
            }) if list_id == list.id
        ));
    }

    #[test]
    fn latest_schema_reopen_does_not_reapply_migrations() {
        let file = NamedTempFile::new().unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let before_schema_version = schema_version(&connection);
        let before_user_version = read_user_version(&connection).unwrap();
        let before_archived_at_count = count_archived_at_columns(&connection);
        let before_is_default_column = is_default_column(&connection);
        drop(connection);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(read_user_version(&connection).unwrap(), before_user_version);
        assert_eq!(schema_version(&connection), before_schema_version);
        assert_eq!(
            count_archived_at_columns(&connection),
            before_archived_at_count
        );
        assert_eq!(is_default_column(&connection), before_is_default_column);
    }

    #[test]
    fn failed_migration_rolls_back_archived_at_and_user_version() {
        let file = NamedTempFile::new().unwrap();
        create_baseline_v1_database(file.path(), &KEY, true);
        let mut connection = open_raw_encrypted(file.path(), &KEY);
        let failing_migrations = &[Migration {
            target_version: 2,
            name: "failing_archived_at",
            apply: failing_archived_at_migration,
        }];

        let result =
            apply_pending_migrations(&mut connection, BASELINE_SCHEMA_VERSION, failing_migrations);

        assert!(matches!(
            result,
            Err(StorageError::MigrationFailed {
                target_version: 2,
                migration: "failing_archived_at",
                ..
            })
        ));
        assert_eq!(
            read_user_version(&connection).unwrap(),
            BASELINE_SCHEMA_VERSION
        );
        assert_eq!(archived_at_column(&connection), None);
    }

    #[test]
    fn unsupported_newer_schema_version_is_rejected() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_raw_encrypted(file.path(), &KEY);
        set_user_version(&connection, LATEST_SCHEMA_VERSION + 1).unwrap();
        drop(connection);

        let result = open_encrypted(file.path(), &KEY);

        assert!(matches!(
            result,
            Err(StorageError::UnsupportedSchemaVersion { found, latest })
                if found == LATEST_SCHEMA_VERSION + 1 && latest == LATEST_SCHEMA_VERSION
        ));
    }

    #[test]
    fn sqlite_task_repository_insert_get_roundtrips_task() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();

        repository.insert(task.clone()).unwrap();

        assert_eq!(repository.get(task.id).unwrap(), task);
    }

    #[test]
    fn equal_task_ranks_use_record_id_as_stable_tie_break() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let list_id = Uuid::from_u128(10);
        let mut later_id = sample_task();
        later_id.id = Uuid::from_u128(12);
        later_id.list_id = list_id;
        later_id.parent_task_id = None;
        later_id.sort_order = "7fffffffffffffffffffffffffffffff".to_string();
        let mut earlier_id = later_id.clone();
        earlier_id.id = Uuid::from_u128(11);
        repository.insert(later_id.clone()).unwrap();
        repository.insert(earlier_id.clone()).unwrap();

        assert_eq!(
            repository
                .list_active_by_list(list_id)
                .unwrap()
                .into_iter()
                .map(|task| task.id)
                .collect::<Vec<_>>(),
            vec![earlier_id.id, later_id.id]
        );
    }

    #[test]
    fn sqlite_list_repository_roundtrips_and_lists_by_sort_order() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);
        let mut first = sample_list("b0");
        let second = sample_list("a0");

        repository.insert(first.clone()).unwrap();
        repository.insert(second.clone()).unwrap();

        assert_eq!(repository.get(first.id).unwrap(), first);

        first.name = "Renamed".to_string();
        first.color = "#FFAA00".to_string();
        first.icon = "star".to_string();
        first.org_id = Some(Uuid::now_v7());
        first.sort_order = "c0".to_string();
        first.archived_at = Some(1_799_000_001_000);
        first.updated_at += 1_000;
        repository.update(first.clone()).unwrap();

        assert_eq!(repository.get(first.id).unwrap(), first);
        assert_eq!(
            repository
                .list_all()
                .unwrap()
                .into_iter()
                .map(|list| list.id)
                .collect::<Vec<_>>(),
            vec![second.id]
        );
        assert_eq!(
            repository
                .list_archived()
                .unwrap()
                .into_iter()
                .map(|list| list.id)
                .collect::<Vec<_>>(),
            vec![first.id]
        );
    }

    #[test]
    fn archived_lists_use_rank_and_record_id_order() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);
        let mut later_rank = sample_list("b0000000000000000000000000000000");
        later_rank.id = Uuid::from_u128(12);
        later_rank.archived_at = Some(10);
        let mut later_id = sample_list("a0000000000000000000000000000000");
        later_id.id = Uuid::from_u128(11);
        later_id.archived_at = Some(30);
        let mut earlier_id = later_id.clone();
        earlier_id.id = Uuid::from_u128(10);
        earlier_id.archived_at = Some(20);
        repository.insert(later_rank.clone()).unwrap();
        repository.insert(later_id.clone()).unwrap();
        repository.insert(earlier_id.clone()).unwrap();

        assert_eq!(
            repository
                .list_archived()
                .unwrap()
                .into_iter()
                .map(|list| list.id)
                .collect::<Vec<_>>(),
            vec![earlier_id.id, later_id.id, later_rank.id]
        );
    }

    #[test]
    fn delete_list_removes_tasks_and_task_undo_entries() {
        let file = NamedTempFile::new().unwrap();
        let list = new_list("Inbox".to_string(), "a0".to_string(), 1_700_000_000_000).unwrap();
        let task = new_task(
            list.id,
            None,
            "Task".to_string(),
            "a0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(task.clone()).unwrap();
            let edited =
                update_title(task.clone(), "Edited".to_string(), task.updated_at + 1).unwrap();
            task_repository
                .update_with_undo(
                    task.clone(),
                    edited,
                    TaskUndoOperation::Edit,
                    task.updated_at + 1,
                )
                .unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut list_repository = SqliteListRepository::new(connection);
        assert_eq!(list_repository.count_tasks(list.id).unwrap(), 1);
        assert_eq!(list_repository.delete_with_tasks(list.id).unwrap(), 1);
        assert!(matches!(
            list_repository.get(list.id),
            Err(StorageError::NotFound(id)) if id == list.id
        ));

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let task_repository = SqliteTaskRepository::new(connection);
        assert!(matches!(
            task_repository.get(task.id),
            Err(StorageError::NotFound(id)) if id == task.id
        ));
        assert!(task_repository.latest_unconsumed_undo().unwrap().is_none());
    }

    #[test]
    fn domain_usecases_persist_task_updates_after_reopen() {
        let file = NamedTempFile::new().unwrap();
        let list = new_list("Inbox".to_string(), "a0".to_string(), 1_700_000_000_000).unwrap();
        let task = new_task(
            list.id,
            None,
            "Draft title".to_string(),
            "a0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();
        let renamed =
            update_title(task.clone(), "Final title".to_string(), 1_700_000_002_000).unwrap();
        let done =
            transition_task(renamed.clone(), TaskStatus::Done, None, 1_700_000_003_000).unwrap();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(task).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.update(renamed).unwrap();
            task_repository.update(done.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let task_repository = SqliteTaskRepository::new(connection);

        assert_eq!(task_repository.get(done.id).unwrap(), done);
    }

    #[test]
    fn delete_subtree_removes_root_descendants_and_undo_entries() {
        let file = NamedTempFile::new().unwrap();
        let list = new_list("Inbox".to_string(), "a0".to_string(), 1_700_000_000_000).unwrap();
        let active = new_task(
            list.id,
            None,
            "Keep".to_string(),
            "a0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();
        let parent = new_task(
            list.id,
            None,
            "Delete parent".to_string(),
            "b0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();
        let child = new_task(
            list.id,
            Some(parent.id),
            "Delete child".to_string(),
            "a0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut task_repository = SqliteTaskRepository::new(connection);
        task_repository.insert(active.clone()).unwrap();
        task_repository.insert(parent.clone()).unwrap();
        task_repository.insert(child).unwrap();

        let updated = update_title(
            parent.clone(),
            "Before delete".to_string(),
            parent.updated_at + 1,
        )
        .unwrap();
        task_repository
            .update_with_undo(
                parent.clone(),
                updated,
                TaskUndoOperation::Edit,
                parent.updated_at + 1,
            )
            .unwrap();

        assert_eq!(task_repository.count_descendants(parent.id).unwrap(), 1);
        assert_eq!(task_repository.delete_subtree(parent.id).unwrap(), 2);
        assert!(matches!(
            task_repository.get(parent.id),
            Err(StorageError::NotFound(id)) if id == parent.id
        ));
        assert_eq!(
            task_repository.list_active_by_list(list.id).unwrap(),
            vec![active]
        );
        assert!(task_repository.latest_unconsumed_undo().unwrap().is_none());
    }

    #[test]
    fn list_home_filters_due_active_and_closed_tasks_across_active_lists() {
        let file = NamedTempFile::new().unwrap();
        let today_start = 1_800_000_000_000;
        let tomorrow_start = today_start + 86_400_000;
        let overdue = today_start - 86_400_000;
        let tomorrow = tomorrow_start + 1_000;
        let upcoming = tomorrow_start + 86_400_000 + 1_000;

        let inbox = new_list("Inbox".to_string(), "a0".to_string(), today_start).unwrap();
        let work = new_list("Work".to_string(), "a1".to_string(), today_start).unwrap();
        let mut archived = new_list("Archive".to_string(), "a2".to_string(), today_start).unwrap();
        archived.archived_at = Some(today_start + 1);

        let mut due_today = new_task(
            inbox.id,
            None,
            "Due today".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        due_today.due_at = Some(today_start);
        let no_due_child = new_task(
            inbox.id,
            Some(due_today.id),
            "No due child".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        let no_due_parent = new_task(
            inbox.id,
            None,
            "No due parent".to_string(),
            "a4".to_string(),
            today_start,
        )
        .unwrap();
        let mut due_child = new_task(
            inbox.id,
            Some(no_due_parent.id),
            "Due child".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        due_child.due_at = Some(today_start);
        let mut overdue_task = new_task(
            work.id,
            None,
            "Overdue".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        overdue_task.due_at = Some(overdue);
        let mut tomorrow_task = new_task(
            inbox.id,
            None,
            "Tomorrow".to_string(),
            "a1".to_string(),
            today_start,
        )
        .unwrap();
        tomorrow_task.due_at = Some(tomorrow);
        let mut upcoming_task = new_task(
            inbox.id,
            None,
            "Upcoming".to_string(),
            "a2".to_string(),
            today_start,
        )
        .unwrap();
        upcoming_task.due_at = Some(upcoming);
        let no_due = new_task(
            inbox.id,
            None,
            "No due".to_string(),
            "a3".to_string(),
            today_start,
        )
        .unwrap();
        let mut archived_task = new_task(
            archived.id,
            None,
            "Archived".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        archived_task.due_at = Some(today_start);
        let mut closed_today = new_task(
            work.id,
            None,
            "Closed today".to_string(),
            "a1".to_string(),
            today_start,
        )
        .unwrap();
        closed_today.due_at = Some(today_start);
        closed_today =
            transition_task(closed_today, TaskStatus::Done, None, today_start + 1_000).unwrap();
        let mut closed_yesterday = new_task(
            work.id,
            None,
            "Closed yesterday".to_string(),
            "a2".to_string(),
            today_start,
        )
        .unwrap();
        closed_yesterday.due_at = Some(today_start);
        closed_yesterday = transition_task(
            closed_yesterday,
            TaskStatus::Done,
            None,
            today_start - 1_000,
        )
        .unwrap();
        let mut wont_do_today = new_task(
            work.id,
            None,
            "Wont do today".to_string(),
            "a3".to_string(),
            today_start,
        )
        .unwrap();
        wont_do_today.due_at = Some(today_start);
        wont_do_today = transition_task(
            wont_do_today,
            TaskStatus::WontDo,
            Some("not needed".to_string()),
            today_start + 2_000,
        )
        .unwrap();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(inbox.clone()).unwrap();
            list_repository.insert(work.clone()).unwrap();
            list_repository.insert(archived).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut task_repository = SqliteTaskRepository::new(connection);
        for task in [
            due_today,
            overdue_task,
            tomorrow_task,
            upcoming_task,
            no_due,
            archived_task,
            closed_today,
            closed_yesterday,
            wont_do_today,
            no_due_child,
            no_due_parent,
            due_child,
        ] {
            task_repository.insert(task).unwrap();
        }

        let home_tasks = task_repository
            .list_home(today_start, tomorrow_start)
            .unwrap();
        let titles = home_tasks
            .iter()
            .map(|entry| entry.task.title.as_str())
            .collect::<Vec<_>>();

        assert_eq!(
            titles,
            vec![
                "Overdue",
                "Due today",
                "Due child",
                "Closed today",
                "Wont do today",
                "Tomorrow",
                "Upcoming",
                "No due child",
                "No due parent"
            ]
        );
        assert!(
            home_tasks
                .iter()
                .find(|entry| entry.task.title == "Due today")
                .unwrap()
                .is_home_target
        );
        assert!(
            !home_tasks
                .iter()
                .find(|entry| entry.task.title == "No due child")
                .unwrap()
                .is_home_target
        );
        assert!(
            !home_tasks
                .iter()
                .find(|entry| entry.task.title == "No due parent")
                .unwrap()
                .is_home_target
        );
        assert!(
            home_tasks
                .iter()
                .find(|entry| entry.task.title == "Due child")
                .unwrap()
                .is_home_target
        );
        assert_eq!(
            home_tasks
                .iter()
                .find(|entry| entry.task.title == "Overdue")
                .unwrap()
                .list_name,
            "Work"
        );
        assert!(!titles.contains(&"No due"));
        assert!(!titles.contains(&"Archived"));
        assert!(!titles.contains(&"Closed yesterday"));
    }

    #[test]
    fn update_with_undo_records_edit_and_restores_previous_snapshot() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let updated =
            update_title(task.clone(), "Undo me".to_string(), task.updated_at + 1).unwrap();
        let undo = repository
            .update_with_undo(
                task.clone(),
                updated.clone(),
                TaskUndoOperation::Edit,
                updated.updated_at,
            )
            .unwrap();

        assert_eq!(repository.latest_unconsumed_undo().unwrap().unwrap(), undo);
        assert_eq!(repository.get(task.id).unwrap(), updated);

        let restored = repository
            .undo_task_operation(undo.id, updated.updated_at + 1)
            .unwrap();

        assert_eq!(restored, task);
        assert_eq!(repository.get(task.id).unwrap(), task);
        assert!(repository.latest_unconsumed_undo().unwrap().is_none());
        assert!(matches!(
            repository.undo_task_operation(undo.id, updated.updated_at + 2),
            Err(StorageError::UndoConsumed(id)) if id == undo.id
        ));
    }

    #[test]
    fn delete_undo_entries_are_not_returned_as_latest_undo() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let mut deleted = task.clone();
        deleted.deleted_at = Some(task.updated_at + 1);
        deleted.updated_at = task.updated_at + 1;
        repository
            .update_with_undo(
                task.clone(),
                deleted.clone(),
                TaskUndoOperation::Delete,
                deleted.updated_at,
            )
            .unwrap();

        assert!(repository.latest_unconsumed_undo().unwrap().is_none());
    }

    #[test]
    fn complete_undo_entry_restores_task_state() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let done =
            transition_task(task.clone(), TaskStatus::Done, None, task.updated_at + 1).unwrap();
        let complete_undo = repository
            .update_with_undo(
                task.clone(),
                done.clone(),
                TaskUndoOperation::Complete,
                done.updated_at,
            )
            .unwrap();

        assert_eq!(
            repository
                .undo_task_operation(complete_undo.id, done.updated_at + 1)
                .unwrap()
                .status,
            TaskStatus::Todo
        );
    }

    #[test]
    fn undo_rejects_edit_conflict_after_later_update() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let edited =
            update_title(task.clone(), "First edit".to_string(), task.updated_at + 1).unwrap();
        let undo = repository
            .update_with_undo(
                task.clone(),
                edited.clone(),
                TaskUndoOperation::Edit,
                edited.updated_at,
            )
            .unwrap();
        let second_edit = update_title(
            edited.clone(),
            "Second edit".to_string(),
            edited.updated_at + 1,
        )
        .unwrap();
        repository.update(second_edit).unwrap();

        assert!(matches!(
            repository.undo_task_operation(undo.id, edited.updated_at + 2),
            Err(StorageError::UndoConflict(id)) if id == task.id
        ));
    }

    #[test]
    fn complete_undo_rejects_physically_deleted_current_task() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let done =
            transition_task(task.clone(), TaskStatus::Done, None, task.updated_at + 1).unwrap();
        let undo = repository
            .update_with_undo(
                task.clone(),
                done.clone(),
                TaskUndoOperation::Complete,
                done.updated_at,
            )
            .unwrap();
        repository.delete_subtree(done.id).unwrap();

        assert!(matches!(
            repository.undo_task_operation(undo.id, task.updated_at + 3),
            Err(StorageError::NotFound(id)) if id == undo.id
        ));
    }

    #[test]
    fn update_returns_not_found_for_missing_task_and_list() {
        let file = NamedTempFile::new().unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut task_repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        assert!(matches!(
            task_repository.update(task.clone()),
            Err(StorageError::NotFound(id)) if id == task.id
        ));

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut list_repository = SqliteListRepository::new(connection);
        let list = sample_list("a0");
        assert!(matches!(
            list_repository.update(list.clone()),
            Err(StorageError::NotFound(id)) if id == list.id
        ));
    }

    #[test]
    fn sqlite_write_tx_commits_domain_and_sync_state_together() {
        let file = NamedTempFile::new().unwrap();
        let task = sample_task();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let edited = update_title(
            task.clone(),
            "Transactional edit".to_string(),
            task.updated_at + 1,
        )
        .unwrap();
        let mut connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut write_tx = SqliteWriteTx::begin(&mut connection).unwrap();
        assert_eq!(write_tx.get_task(task.id).unwrap(), task);
        write_tx
            .update_with_undo(
                task.clone(),
                edited.clone(),
                TaskUndoOperation::Edit,
                edited.updated_at,
            )
            .unwrap();
        write_tx
            .set_setting("sync_local_hlc", "encoded-hlc", edited.updated_at)
            .unwrap();
        let op_id = Uuid::now_v7();
        write_tx
            .put_outbox_head(new_live_outbox(
                task.id,
                "tasks",
                op_id,
                None,
                "encoded-hlc",
                "encoded-hlc",
                vec![1, 2, 3],
            ))
            .unwrap();
        write_tx
            .put_record_state(live_record_state(
                task.id,
                "tasks",
                Some("encoded-hlc"),
                "encoded-hlc",
                r#"{"title":"Transactional edit"}"#,
                edited.updated_at,
            ))
            .unwrap();
        assert_eq!(write_tx.list_outbox_heads(10).unwrap().len(), 1);
        write_tx.commit().unwrap();
        drop(connection);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteTaskRepository::new(connection);
        assert_eq!(repository.get(task.id).unwrap(), edited);
        drop(repository);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let settings = SqliteSettingsRepository::new(connection);
        assert_eq!(
            settings.get_setting("sync_local_hlc").unwrap().as_deref(),
            Some("encoded-hlc")
        );
        drop(settings);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let sync = SqliteSyncStateRepository::new(connection);
        assert_eq!(sync.list_outbox_heads(10).unwrap().len(), 1);
        assert_eq!(
            sync.get_record_state("tasks", task.id).unwrap(),
            Some(live_record_state(
                task.id,
                "tasks",
                Some("encoded-hlc"),
                "encoded-hlc",
                r#"{"title":"Transactional edit"}"#,
                edited.updated_at,
            ))
        );
    }

    #[test]
    fn sqlite_write_tx_drop_rolls_back_domain_and_sync_state_together() {
        let file = NamedTempFile::new().unwrap();
        let task = sample_task();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let edited = update_title(
            task.clone(),
            "Rolled back edit".to_string(),
            task.updated_at + 1,
        )
        .unwrap();
        let mut connection = open_encrypted(file.path(), &KEY).unwrap();
        {
            let mut write_tx = SqliteWriteTx::begin(&mut connection).unwrap();
            write_tx
                .update_with_undo(
                    task.clone(),
                    edited.clone(),
                    TaskUndoOperation::Edit,
                    edited.updated_at,
                )
                .unwrap();
            write_tx
                .set_setting("sync_local_hlc", "rolled-back-hlc", edited.updated_at)
                .unwrap();
            write_tx
                .put_outbox_head(new_live_outbox(
                    task.id,
                    "tasks",
                    Uuid::now_v7(),
                    None,
                    "rolled-back-hlc",
                    "rolled-back-hlc",
                    vec![4, 5, 6],
                ))
                .unwrap();
            write_tx
                .put_record_state(live_record_state(
                    task.id,
                    "tasks",
                    Some("rolled-back-hlc"),
                    "rolled-back-hlc",
                    r#"{"title":"Rolled back edit"}"#,
                    edited.updated_at,
                ))
                .unwrap();
        }
        drop(connection);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteTaskRepository::new(connection);
        assert_eq!(repository.get(task.id).unwrap(), task);
        assert!(repository.latest_unconsumed_undo().unwrap().is_none());
        drop(repository);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let settings = SqliteSettingsRepository::new(connection);
        assert_eq!(settings.get_setting("sync_local_hlc").unwrap(), None);
        drop(settings);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let sync = SqliteSyncStateRepository::new(connection);
        assert!(sync.list_outbox_heads(10).unwrap().is_empty());
        assert_eq!(sync.get_record_state("tasks", task.id).unwrap(), None);
    }

    #[test]
    fn owned_sqlite_write_tx_commits_domain_hlc_record_state_and_outbox() {
        let file = NamedTempFile::new().unwrap();
        let mut list = sample_list("a0");
        list.is_default = true;
        let mut task = sample_task();
        task.list_id = list.id;
        task.parent_task_id = None;
        let op_id = Uuid::now_v7();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut transaction = OwnedSqliteWriteTx::begin(connection).unwrap();
        transaction
            .set_setting("sync_local_hlc", "owned-hlc", task.updated_at)
            .unwrap();
        transaction.upsert_list_for_sync(list.clone()).unwrap();
        transaction.upsert_task_for_sync(task.clone()).unwrap();
        transaction
            .put_record_state(live_record_state(
                task.id,
                "tasks",
                Some("owned-hlc"),
                "owned-hlc",
                r#"{"title":"Owned commit"}"#,
                task.updated_at,
            ))
            .unwrap();
        transaction
            .put_outbox_head(new_live_outbox(
                task.id,
                "tasks",
                op_id,
                Some("base-hlc"),
                "owned-hlc",
                "owned-hlc",
                vec![1, 2, 3],
            ))
            .unwrap();
        transaction
            .set_cursor("default", 7, task.updated_at)
            .unwrap();
        assert_eq!(transaction.default_list_id().unwrap(), Some(list.id));
        assert_eq!(transaction.get_list(list.id).unwrap(), Some(list.clone()));
        assert_eq!(transaction.get_task(task.id).unwrap(), Some(task.clone()));
        assert!(transaction.has_outbox_head("tasks", task.id).unwrap());
        assert_eq!(transaction.list_outbox_heads(10).unwrap().len(), 1);
        assert_eq!(transaction.get_cursor("default").unwrap().unwrap().seq, 7);
        let connection = transaction.commit().unwrap();

        assert_eq!(
            get_setting_on(&connection, "sync_local_hlc")
                .unwrap()
                .as_deref(),
            Some("owned-hlc")
        );
        assert_eq!(get_list_on(&connection, list.id).unwrap(), list);
        assert_eq!(get_task_on(&connection, task.id).unwrap(), task);
        assert!(get_record_state_on(&connection, "tasks", task.id)
            .unwrap()
            .is_some());
        assert_eq!(list_outbox_heads_on(&connection, 10).unwrap().len(), 1);
        assert_eq!(
            get_cursor_on(&connection, "default").unwrap().unwrap().seq,
            7
        );
    }

    #[test]
    fn owned_sqlite_write_tx_drop_rolls_back_domain_hlc_record_state_and_outbox() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        let mut task = sample_task();
        task.list_id = list.id;
        task.parent_task_id = None;

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut transaction = OwnedSqliteWriteTx::begin(connection).unwrap();
            transaction
                .set_setting("sync_local_hlc", "rolled-back-owned-hlc", task.updated_at)
                .unwrap();
            transaction.upsert_list_for_sync(list.clone()).unwrap();
            transaction.upsert_task_for_sync(task.clone()).unwrap();
            transaction
                .put_record_state(live_record_state(
                    task.id,
                    "tasks",
                    None,
                    "rolled-back-owned-hlc",
                    r#"{"title":"Owned rollback"}"#,
                    task.updated_at,
                ))
                .unwrap();
            transaction
                .put_outbox_head(new_live_outbox(
                    task.id,
                    "tasks",
                    Uuid::now_v7(),
                    None,
                    "rolled-back-owned-hlc",
                    "rolled-back-owned-hlc",
                    vec![4, 5, 6],
                ))
                .unwrap();
            transaction
                .set_cursor("default", 9, task.updated_at)
                .unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        assert_eq!(get_setting_on(&connection, "sync_local_hlc").unwrap(), None);
        assert!(matches!(
            get_list_on(&connection, list.id),
            Err(StorageError::NotFound(id)) if id == list.id
        ));
        assert!(matches!(
            get_task_on(&connection, task.id),
            Err(StorageError::NotFound(id)) if id == task.id
        ));
        assert_eq!(
            get_record_state_on(&connection, "tasks", task.id).unwrap(),
            None
        );
        assert!(list_outbox_heads_on(&connection, 10).unwrap().is_empty());
        assert_eq!(get_cursor_on(&connection, "default").unwrap(), None);
    }

    #[test]
    fn sqlite_write_tx_commits_task_and_list_crud_without_nested_transactions() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteListRepository::new(connection);
            repository.insert(list.clone()).unwrap();
        }

        let mut task = sample_task();
        task.list_id = list.id;
        task.parent_task_id = None;
        let mut prepared = task.clone();
        prepared.note = "Updated before status transition".to_string();
        prepared.updated_at += 1;
        let done = transition_task(
            prepared.clone(),
            TaskStatus::Done,
            None,
            prepared.updated_at + 1,
        )
        .unwrap();
        let mut renamed_list = list.clone();
        renamed_list.name = "Renamed transactionally".to_string();
        renamed_list.updated_at += 1;

        let mut connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut write_tx = SqliteWriteTx::begin(&mut connection).unwrap();
        assert_eq!(write_tx.get_list(list.id).unwrap(), list);
        write_tx.update_list(renamed_list.clone()).unwrap();
        write_tx.insert_task(task.clone()).unwrap();
        write_tx.update_task(prepared.clone()).unwrap();
        assert_eq!(
            write_tx.list_active_tasks_by_list(list.id).unwrap(),
            vec![prepared.clone()]
        );
        let undo = write_tx
            .update_task_with_undo(
                prepared,
                done.clone(),
                TaskUndoOperation::Complete,
                done.updated_at,
            )
            .unwrap();
        assert_eq!(write_tx.get_task(done.id).unwrap(), done);
        write_tx.commit().unwrap();
        drop(connection);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let list_repository = SqliteListRepository::new(connection);
        assert_eq!(list_repository.get(list.id).unwrap(), renamed_list);
        drop(list_repository);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let task_repository = SqliteTaskRepository::new(connection);
        assert_eq!(task_repository.get(done.id).unwrap(), done);
        assert_eq!(
            task_repository.latest_unconsumed_undo().unwrap(),
            Some(undo)
        );
    }

    #[test]
    fn sqlite_write_tx_drop_rolls_back_undo_restore_and_list_update() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        let mut task = sample_task();
        task.list_id = list.id;
        task.parent_task_id = None;
        let edited = update_title(
            task.clone(),
            "Awaiting undo".to_string(),
            task.updated_at + 1,
        )
        .unwrap();
        let undo = {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
            drop(list_repository);

            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(task.clone()).unwrap();
            task_repository
                .update_with_undo(
                    task.clone(),
                    edited.clone(),
                    TaskUndoOperation::Edit,
                    edited.updated_at,
                )
                .unwrap()
        };
        let mut archived_list = list.clone();
        archived_list.archived_at = Some(edited.updated_at + 1);
        archived_list.updated_at = edited.updated_at + 1;

        let mut connection = open_encrypted(file.path(), &KEY).unwrap();
        {
            let mut write_tx = SqliteWriteTx::begin(&mut connection).unwrap();
            assert_eq!(
                write_tx
                    .undo_task_operation(undo.id, edited.updated_at + 1)
                    .unwrap(),
                task
            );
            write_tx.update_list(archived_list).unwrap();
            assert_eq!(write_tx.get_task(task.id).unwrap(), task);
        }
        drop(connection);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let list_repository = SqliteListRepository::new(connection);
        assert_eq!(list_repository.get(list.id).unwrap(), list);
        drop(list_repository);

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut task_repository = SqliteTaskRepository::new(connection);
        assert_eq!(task_repository.get(task.id).unwrap(), edited);
        assert_eq!(
            task_repository
                .undo_task_operation(undo.id, edited.updated_at + 2)
                .unwrap(),
            task
        );
    }

    #[test]
    fn encrypted_connections_have_finite_busy_timeout_and_write_tx_locks_immediately() {
        let file = NamedTempFile::new().unwrap();
        let mut first = open_encrypted(file.path(), &KEY).unwrap();
        let second = open_encrypted(file.path(), &KEY).unwrap();
        let busy_timeout_ms: i64 = second
            .query_row("PRAGMA busy_timeout", [], |row| row.get(0))
            .unwrap();
        assert_eq!(busy_timeout_ms, 5_000);
        second.busy_timeout(Duration::ZERO).unwrap();

        let _write_tx = SqliteWriteTx::begin(&mut first).unwrap();
        let result = second.execute(
            "INSERT INTO settings (key, value, updated_at) VALUES (?1, ?2, ?3)",
            params!["other_writer", "blocked", 1],
        );
        assert!(matches!(
            result,
            Err(rusqlite::Error::SqliteFailure(error, _))
                if error.code == rusqlite::ErrorCode::DatabaseBusy
        ));
    }

    #[test]
    fn pending_list_key_bundle_is_immutable_and_compare_acknowledged() {
        let file = NamedTempFile::new().unwrap();
        let tenant_id = Uuid::now_v7();
        let list_id = Uuid::now_v7();
        let bundle = PendingListKeyBundle {
            tenant_id,
            list_id,
            wrapped_list_dek: vec![1, 2, 3],
            created_at: 10,
        };
        let mut local_crypto =
            SqliteLocalCryptoRepository::new(open_encrypted(file.path(), &KEY).unwrap());
        local_crypto
            .bind_and_replace_bundles(
                LocalProfileBinding {
                    tenant_id,
                    user_id: Uuid::now_v7(),
                    device_id: Uuid::now_v7(),
                    bound_at: 1,
                    updated_at: 1,
                },
                &[],
            )
            .unwrap();
        let mut connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut transaction = SqliteWriteTx::begin(&mut connection).unwrap();
        transaction
            .put_pending_list_key_bundle(bundle.clone())
            .unwrap();
        transaction
            .put_pending_list_key_bundle(bundle.clone())
            .unwrap();
        let mut conflicting = bundle.clone();
        conflicting.wrapped_list_dek = vec![4, 5, 6];
        assert!(transaction
            .put_pending_list_key_bundle(conflicting)
            .is_err());
        transaction.commit().unwrap();

        let mut repository =
            SqliteSyncStateRepository::new(open_encrypted(file.path(), &KEY).unwrap());
        assert_eq!(
            repository
                .list_pending_list_key_bundles(tenant_id, 10)
                .unwrap(),
            vec![bundle.clone()]
        );
        assert!(!repository
            .ack_pending_list_key_bundle(tenant_id, list_id, &[9])
            .unwrap());
        assert!(repository
            .ack_pending_list_key_bundle(tenant_id, list_id, &bundle.wrapped_list_dek,)
            .unwrap());
        assert!(repository
            .list_pending_list_key_bundles(tenant_id, 10)
            .unwrap()
            .is_empty());
    }
}

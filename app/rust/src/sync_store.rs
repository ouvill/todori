use std::path::{Path, PathBuf};

use todori_domain::{List, Task, Uuid};
use todori_storage::{
    open_encrypted, ListRepository, NewSyncOutboxEntry, OwnedSqliteWriteTx, PendingListKeyBundle,
    SettingsRepository, SqliteListRepository, SqliteSettingsRepository, SqliteSyncStateRepository,
    SqliteTaskRepository, StorageError, SyncOutboxState, SyncQuarantineEntry,
    SyncRecordSemanticState, SyncRecordState, SyncStateRepository, TaskRepository,
};
use todori_sync::{
    EncryptedSyncState, LocalMutationSyncStore, LocalPendingListKeyBundle, LocalSyncAtomicStore,
    LocalSyncOutboxEntry, LocalSyncQuarantineEntry, LocalSyncRecordState, LocalSyncSemanticState,
    LocalSyncStore, LocalSyncWriteTransaction, NewLocalSyncOutboxEntry, PullFailureReason,
    SyncCollection,
};

pub struct BridgeSyncStore {
    db_path: PathBuf,
    db_key: [u8; 32],
}

pub struct BridgeSyncWriteTx {
    transaction: OwnedSqliteWriteTx,
}

impl BridgeSyncStore {
    pub fn new(db_path: PathBuf, db_key: [u8; 32]) -> Self {
        Self { db_path, db_key }
    }
}

impl LocalSyncAtomicStore for BridgeSyncStore {
    type WriteTransaction = BridgeSyncWriteTx;

    fn begin_write_transaction(&mut self) -> Result<Self::WriteTransaction, String> {
        let connection =
            open_encrypted(&self.db_path, &self.db_key).map_err(|error| error.to_string())?;
        let transaction =
            OwnedSqliteWriteTx::begin(connection).map_err(|error| error.to_string())?;
        Ok(BridgeSyncWriteTx { transaction })
    }
}

impl LocalMutationSyncStore for BridgeSyncStore {
    fn has_outbox_head(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
    ) -> Result<bool, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .has_outbox_head(collection.as_str(), record_id)
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

    fn put_outbox_head(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .put_outbox_head(NewSyncOutboxEntry {
                    op_id: entry.op_id,
                    record_id: entry.record_id,
                    collection: entry.collection.to_string(),
                    base_revision_hlc: entry.base_revision_hlc,
                    revision_hlc: entry.revision_hlc,
                    state: match entry.state {
                        EncryptedSyncState::Live { mutation_hlc, blob } => {
                            SyncOutboxState::Live { mutation_hlc, blob }
                        }
                        EncryptedSyncState::Tombstone { delete_hlc } => {
                            SyncOutboxState::Tombstone { delete_hlc }
                        }
                    },
                    created_at: entry.created_at,
                })
                .map(|_| ())
                .map_err(|error| error.to_string())
        })
    }

    fn get_record_state(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
    ) -> Result<Option<LocalSyncRecordState>, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .get_record_state(collection.as_str(), record_id)
                .map(|state| state.map(storage_record_to_local))
                .map_err(|error| error.to_string())
        })
    }

    fn put_record_state(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
        state: LocalSyncRecordState,
        updated_at: i64,
    ) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .put_record_state(local_record_to_storage(
                    collection, record_id, state, updated_at,
                ))
                .map_err(|error| error.to_string())
        })
    }
}

impl LocalSyncStore for BridgeSyncStore {
    fn list_pending_list_key_bundles(
        &mut self,
        tenant_id: Uuid,
        limit: usize,
    ) -> Result<Vec<LocalPendingListKeyBundle>, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .list_pending_list_key_bundles(tenant_id, limit)
                .map_err(|error| error.to_string())
        })
        .map(|entries| entries.into_iter().map(storage_pending_to_local).collect())
    }

    fn ack_pending_list_key_bundle(
        &mut self,
        tenant_id: Uuid,
        list_id: Uuid,
        wrapped_list_dek: &[u8],
    ) -> Result<bool, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .ack_pending_list_key_bundle(tenant_id, list_id, wrapped_list_dek)
                .map_err(|error| error.to_string())
        })
    }

    fn list_outbox_heads(&mut self, limit: usize) -> Result<Vec<LocalSyncOutboxEntry>, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .list_outbox_heads(limit)
                .map(|entries| {
                    entries
                        .into_iter()
                        .map(|entry| -> Result<LocalSyncOutboxEntry, String> {
                            Ok(LocalSyncOutboxEntry {
                                op_id: entry.op_id,
                                record_id: entry.record_id,
                                collection: entry
                                    .collection
                                    .parse::<SyncCollection>()
                                    .map_err(|error| error.to_string())?,
                                base_revision_hlc: entry.base_revision_hlc,
                                revision_hlc: entry.revision_hlc,
                                state: match entry.state {
                                    SyncOutboxState::Live { mutation_hlc, blob } => {
                                        EncryptedSyncState::Live { mutation_hlc, blob }
                                    }
                                    SyncOutboxState::Tombstone { delete_hlc } => {
                                        EncryptedSyncState::Tombstone { delete_hlc }
                                    }
                                },
                                created_at: entry.created_at,
                            })
                        })
                        .collect::<Result<Vec<_>, String>>()
                })
                .map_err(|error| error.to_string())?
        })
    }

    fn ack_outbox_op(&mut self, op_id: Uuid) -> Result<bool, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .ack_outbox_op(op_id)
                .map_err(|error| error.to_string())
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

    fn put_quarantine(&mut self, entry: LocalSyncQuarantineEntry) -> Result<(), String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .put_quarantine(local_quarantine_to_storage(entry))
                .map_err(|e| e.to_string())
        })
    }

    fn list_quarantine(&mut self, limit: usize) -> Result<Vec<LocalSyncQuarantineEntry>, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository.list_quarantine(limit).map_err(|e| e.to_string())
        })?
        .into_iter()
        .map(storage_quarantine_to_local)
        .collect()
    }

    fn list_replayable_quarantine(
        &mut self,
        after: Option<(i64, Uuid)>,
        limit: usize,
    ) -> Result<Vec<LocalSyncQuarantineEntry>, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .list_replayable_quarantine(after, limit)
                .map_err(|e| e.to_string())
        })?
        .into_iter()
        .map(storage_quarantine_to_local)
        .collect()
    }

    fn delete_quarantine(&mut self, record_id: Uuid) -> Result<bool, String> {
        with_sync_repository(&self.db_path, &self.db_key, |repository| {
            repository
                .delete_quarantine(record_id)
                .map_err(|e| e.to_string())
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

impl LocalMutationSyncStore for BridgeSyncWriteTx {
    fn has_outbox_head(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
    ) -> Result<bool, String> {
        self.transaction
            .has_outbox_head(collection.as_str(), record_id)
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

    fn put_outbox_head(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String> {
        self.transaction
            .put_outbox_head(local_outbox_to_storage(entry))
            .map(|_| ())
            .map_err(|error| error.to_string())
    }

    fn get_record_state(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
    ) -> Result<Option<LocalSyncRecordState>, String> {
        self.transaction
            .get_record_state(collection.as_str(), record_id)
            .map(|state| state.map(storage_record_to_local))
            .map_err(|error| error.to_string())
    }

    fn put_record_state(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
        state: LocalSyncRecordState,
        updated_at: i64,
    ) -> Result<(), String> {
        self.transaction
            .put_record_state(local_record_to_storage(
                collection, record_id, state, updated_at,
            ))
            .map_err(|error| error.to_string())
    }
}

impl LocalSyncStore for BridgeSyncWriteTx {
    fn ack_pending_list_key_bundle(
        &mut self,
        tenant_id: Uuid,
        list_id: Uuid,
        wrapped_list_dek: &[u8],
    ) -> Result<bool, String> {
        self.transaction
            .ack_pending_list_key_bundle(tenant_id, list_id, wrapped_list_dek)
            .map_err(|error| error.to_string())
    }

    fn list_outbox_heads(&mut self, limit: usize) -> Result<Vec<LocalSyncOutboxEntry>, String> {
        self.transaction
            .list_outbox_heads(limit)
            .map_err(|error| error.to_string())?
            .into_iter()
            .map(storage_outbox_to_local)
            .collect()
    }

    fn ack_outbox_op(&mut self, op_id: Uuid) -> Result<bool, String> {
        self.transaction
            .ack_outbox_op(op_id)
            .map_err(|error| error.to_string())
    }

    fn get_cursor_seq(&mut self, name: &str) -> Result<Option<i64>, String> {
        self.transaction
            .get_cursor(name)
            .map(|cursor| cursor.map(|cursor| cursor.seq))
            .map_err(|error| error.to_string())
    }

    fn set_cursor(&mut self, name: &str, seq: i64, updated_at: i64) -> Result<(), String> {
        self.transaction
            .set_cursor(name, seq, updated_at)
            .map_err(|error| error.to_string())
    }

    fn delete_cursor(&mut self, name: &str) -> Result<(), String> {
        self.transaction
            .delete_cursor(name)
            .map_err(|error| error.to_string())
    }

    fn put_quarantine(&mut self, entry: LocalSyncQuarantineEntry) -> Result<(), String> {
        self.transaction
            .put_quarantine(local_quarantine_to_storage(entry))
            .map_err(|e| e.to_string())
    }

    fn list_quarantine(&mut self, limit: usize) -> Result<Vec<LocalSyncQuarantineEntry>, String> {
        self.transaction
            .list_quarantine(limit)
            .map_err(|e| e.to_string())?
            .into_iter()
            .map(storage_quarantine_to_local)
            .collect()
    }

    fn list_replayable_quarantine(
        &mut self,
        after: Option<(i64, Uuid)>,
        limit: usize,
    ) -> Result<Vec<LocalSyncQuarantineEntry>, String> {
        self.transaction
            .list_replayable_quarantine(after, limit)
            .map_err(|e| e.to_string())?
            .into_iter()
            .map(storage_quarantine_to_local)
            .collect()
    }

    fn delete_quarantine(&mut self, record_id: Uuid) -> Result<bool, String> {
        self.transaction
            .delete_quarantine(record_id)
            .map_err(|e| e.to_string())
    }

    fn default_list_id(&mut self) -> Result<Option<Uuid>, String> {
        self.transaction
            .default_list_id()
            .map_err(|error| error.to_string())
    }

    fn get_list(&mut self, id: Uuid) -> Result<Option<List>, String> {
        self.transaction
            .get_list(id)
            .map_err(|error| error.to_string())
    }

    fn upsert_list_for_sync(&mut self, list: List) -> Result<(), String> {
        self.transaction
            .upsert_list_for_sync(list)
            .map_err(|error| error.to_string())
    }

    fn delete_list_with_tasks_for_sync(&mut self, list_id: Uuid) -> Result<usize, String> {
        self.transaction
            .delete_list_with_tasks_for_sync(list_id)
            .map_err(|error| error.to_string())
    }

    fn get_task(&mut self, id: Uuid) -> Result<Option<Task>, String> {
        self.transaction
            .get_task(id)
            .map_err(|error| error.to_string())
    }

    fn upsert_task_for_sync(&mut self, task: Task) -> Result<(), String> {
        self.transaction
            .upsert_task_for_sync(task)
            .map_err(|error| error.to_string())
    }

    fn delete_task_subtree_for_sync(&mut self, task_id: Uuid) -> Result<usize, String> {
        self.transaction
            .delete_task_subtree_for_sync(task_id)
            .map_err(|error| error.to_string())
    }
}

impl LocalSyncWriteTransaction for BridgeSyncWriteTx {
    fn commit(self) -> Result<(), String> {
        self.transaction
            .commit()
            .map(|_| ())
            .map_err(|error| error.to_string())
    }
}

fn local_outbox_to_storage(entry: NewLocalSyncOutboxEntry) -> NewSyncOutboxEntry {
    NewSyncOutboxEntry {
        op_id: entry.op_id,
        record_id: entry.record_id,
        collection: entry.collection.to_string(),
        base_revision_hlc: entry.base_revision_hlc,
        revision_hlc: entry.revision_hlc,
        state: match entry.state {
            EncryptedSyncState::Live { mutation_hlc, blob } => {
                SyncOutboxState::Live { mutation_hlc, blob }
            }
            EncryptedSyncState::Tombstone { delete_hlc } => {
                SyncOutboxState::Tombstone { delete_hlc }
            }
        },
        created_at: entry.created_at,
    }
}

fn storage_pending_to_local(entry: PendingListKeyBundle) -> LocalPendingListKeyBundle {
    LocalPendingListKeyBundle {
        tenant_id: entry.tenant_id,
        list_id: entry.list_id,
        wrapped_list_dek: entry.wrapped_list_dek,
        created_at: entry.created_at,
    }
}

fn storage_outbox_to_local(
    entry: todori_storage::SyncOutboxEntry,
) -> Result<LocalSyncOutboxEntry, String> {
    Ok(LocalSyncOutboxEntry {
        op_id: entry.op_id,
        record_id: entry.record_id,
        collection: entry
            .collection
            .parse::<SyncCollection>()
            .map_err(|error| error.to_string())?,
        base_revision_hlc: entry.base_revision_hlc,
        revision_hlc: entry.revision_hlc,
        state: match entry.state {
            SyncOutboxState::Live { mutation_hlc, blob } => {
                EncryptedSyncState::Live { mutation_hlc, blob }
            }
            SyncOutboxState::Tombstone { delete_hlc } => {
                EncryptedSyncState::Tombstone { delete_hlc }
            }
        },
        created_at: entry.created_at,
    })
}

fn local_quarantine_to_storage(entry: LocalSyncQuarantineEntry) -> SyncQuarantineEntry {
    SyncQuarantineEntry {
        record_id: entry.record_id,
        collection: entry.collection.to_string(),
        seq: entry.seq,
        revision_hlc: entry.revision_hlc,
        state: match entry.state {
            EncryptedSyncState::Live { mutation_hlc, blob } => {
                SyncOutboxState::Live { mutation_hlc, blob }
            }
            EncryptedSyncState::Tombstone { delete_hlc } => {
                SyncOutboxState::Tombstone { delete_hlc }
            }
        },
        reason: entry.reason.as_str().to_string(),
        required_list_id: entry.required_list_id,
        first_failed_at: entry.first_failed_at,
        last_failed_at: entry.last_failed_at,
        attempt_count: entry.attempt_count,
    }
}

fn storage_quarantine_to_local(
    entry: SyncQuarantineEntry,
) -> Result<LocalSyncQuarantineEntry, String> {
    Ok(LocalSyncQuarantineEntry {
        record_id: entry.record_id,
        collection: entry
            .collection
            .parse::<SyncCollection>()
            .map_err(|e| e.to_string())?,
        seq: entry.seq,
        revision_hlc: entry.revision_hlc,
        state: match entry.state {
            SyncOutboxState::Live { mutation_hlc, blob } => {
                EncryptedSyncState::Live { mutation_hlc, blob }
            }
            SyncOutboxState::Tombstone { delete_hlc } => {
                EncryptedSyncState::Tombstone { delete_hlc }
            }
        },
        reason: entry.reason.parse::<PullFailureReason>()?,
        required_list_id: entry.required_list_id,
        first_failed_at: entry.first_failed_at,
        last_failed_at: entry.last_failed_at,
        attempt_count: entry.attempt_count,
    })
}

fn storage_record_to_local(state: SyncRecordState) -> LocalSyncRecordState {
    LocalSyncRecordState {
        current_revision_hlc: state.current_revision_hlc,
        state: match state.state {
            SyncRecordSemanticState::Live {
                mutation_hlc,
                plaintext_json,
            } => LocalSyncSemanticState::Live {
                mutation_hlc,
                plaintext_json,
            },
            SyncRecordSemanticState::Tombstone { delete_hlc } => {
                LocalSyncSemanticState::Tombstone { delete_hlc }
            }
        },
    }
}

fn local_record_to_storage(
    collection: SyncCollection,
    record_id: Uuid,
    state: LocalSyncRecordState,
    updated_at: i64,
) -> SyncRecordState {
    SyncRecordState {
        record_id,
        collection: collection.to_string(),
        current_revision_hlc: state.current_revision_hlc,
        state: match state.state {
            LocalSyncSemanticState::Live {
                mutation_hlc,
                plaintext_json,
            } => SyncRecordSemanticState::Live {
                mutation_hlc,
                plaintext_json,
            },
            LocalSyncSemanticState::Tombstone { delete_hlc } => {
                SyncRecordSemanticState::Tombstone { delete_hlc }
            }
        },
        updated_at,
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

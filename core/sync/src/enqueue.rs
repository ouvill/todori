use todori_crypto::key_hierarchy::KEY_LEN;
use todori_domain::{List, Task, Uuid};

use crate::{
    encrypt_plaintext, EncryptedSyncState, Hlc, SyncCollection, SyncPlaintext,
    SYNC_LOCAL_HLC_SETTING_KEY,
};

use crate::keys::{dek_for_list, LocalSyncKeys};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalSyncOutboxEntry {
    pub op_id: Uuid,
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub base_revision_hlc: Option<String>,
    pub revision_hlc: String,
    pub state: EncryptedSyncState,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewLocalSyncOutboxEntry {
    pub op_id: Uuid,
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub base_revision_hlc: Option<String>,
    pub revision_hlc: String,
    pub state: EncryptedSyncState,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LocalSyncSemanticState {
    Live {
        mutation_hlc: String,
        plaintext_json: String,
    },
    Tombstone {
        delete_hlc: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalSyncRecordState {
    pub current_revision_hlc: Option<String>,
    pub state: LocalSyncSemanticState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PullFailureReason {
    MissingDek,
    NoMatchingDek,
    AuthenticationFailed,
    CorruptEnvelope,
    InvalidPlaintext,
}

impl PullFailureReason {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::MissingDek => "missing_dek",
            Self::NoMatchingDek => "no_matching_dek",
            Self::AuthenticationFailed => "authentication_failed",
            Self::CorruptEnvelope => "corrupt_envelope",
            Self::InvalidPlaintext => "invalid_plaintext",
        }
    }
}

impl std::str::FromStr for PullFailureReason {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "missing_dek" => Ok(Self::MissingDek),
            "no_matching_dek" => Ok(Self::NoMatchingDek),
            "authentication_failed" => Ok(Self::AuthenticationFailed),
            "corrupt_envelope" => Ok(Self::CorruptEnvelope),
            "invalid_plaintext" => Ok(Self::InvalidPlaintext),
            _ => Err("invalid quarantine reason".to_string()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalSyncQuarantineEntry {
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub seq: i64,
    pub revision_hlc: String,
    pub state: EncryptedSyncState,
    pub reason: PullFailureReason,
    pub required_list_id: Option<Uuid>,
    pub first_failed_at: i64,
    pub last_failed_at: i64,
    pub attempt_count: i64,
}

/// The local persistence operations needed to prepare a domain mutation for sync.
///
/// Implementations must arrange for these writes and the corresponding domain
/// write to participate in the same transaction.
pub trait LocalMutationSyncStore {
    fn has_outbox_head(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
    ) -> Result<bool, String>;
    fn get_setting(&mut self, key: &str) -> Result<Option<String>, String>;
    fn set_setting(&mut self, key: &str, value: &str, updated_at: i64) -> Result<(), String>;
    fn put_outbox_head(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String>;
    fn get_record_state(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
    ) -> Result<Option<LocalSyncRecordState>, String>;
    fn put_record_state(
        &mut self,
        collection: SyncCollection,
        record_id: Uuid,
        state: LocalSyncRecordState,
        updated_at: i64,
    ) -> Result<(), String>;
}

/// The complete local persistence surface used by a sync run.
///
/// Pull/apply composes the mutation state with outbox draining, cursor updates,
/// and domain row application. Mutation-only callers should depend on
/// [`LocalMutationSyncStore`] instead.
pub trait LocalSyncStore: LocalMutationSyncStore {
    fn list_outbox_heads(&mut self, limit: usize) -> Result<Vec<LocalSyncOutboxEntry>, String>;
    fn ack_outbox_op(&mut self, op_id: Uuid) -> Result<bool, String>;
    fn get_cursor_seq(&mut self, name: &str) -> Result<Option<i64>, String>;
    fn set_cursor(&mut self, name: &str, seq: i64, updated_at: i64) -> Result<(), String>;
    fn delete_cursor(&mut self, name: &str) -> Result<(), String>;
    fn put_quarantine(&mut self, _entry: LocalSyncQuarantineEntry) -> Result<(), String> {
        Err("durable quarantine is unavailable".to_string())
    }
    fn list_quarantine(&mut self, _limit: usize) -> Result<Vec<LocalSyncQuarantineEntry>, String> {
        Ok(Vec::new())
    }
    fn delete_quarantine(&mut self, _record_id: Uuid) -> Result<bool, String> {
        Ok(false)
    }
    fn default_list_id(&mut self) -> Result<Option<Uuid>, String>;
    fn get_list(&mut self, id: Uuid) -> Result<Option<List>, String>;
    fn upsert_list_for_sync(&mut self, list: List) -> Result<(), String>;
    fn delete_list_with_tasks_for_sync(&mut self, list_id: Uuid) -> Result<usize, String>;
    fn get_task(&mut self, id: Uuid) -> Result<Option<Task>, String>;
    fn upsert_task_for_sync(&mut self, task: Task) -> Result<(), String>;
    fn delete_task_subtree_for_sync(&mut self, task_id: Uuid) -> Result<usize, String>;
}

pub trait LocalSyncWriteTransaction: LocalSyncStore {
    fn commit(self) -> Result<(), String>;
}

pub trait LocalSyncAtomicStore: LocalSyncStore {
    type WriteTransaction: LocalSyncWriteTransaction;

    fn begin_write_transaction(&mut self) -> Result<Self::WriteTransaction, String>;
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BackfillSummary {
    pub enqueued_lists: usize,
    pub enqueued_tasks: usize,
    pub skipped_existing_outbox: usize,
    pub skipped_missing_dek: usize,
}

pub fn enqueue_backfill<S, N>(
    store: &mut S,
    keys: &LocalSyncKeys,
    device_id: &str,
    lists: &[List],
    tasks: &[Task],
    now_ms: &mut N,
) -> Result<BackfillSummary, String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let mut summary = BackfillSummary::default();

    for list in lists {
        if store.has_outbox_head(SyncCollection::Lists, list.id)? {
            summary.skipped_existing_outbox += 1;
            continue;
        }
        if dek_for_list(keys, list.id).is_none() {
            summary.skipped_missing_dek += 1;
            continue;
        }
        enqueue_list_sync(store, keys, device_id, list, false, now_ms)?;
        summary.enqueued_lists += 1;
    }

    let mut sorted_tasks = tasks.iter().collect::<Vec<_>>();
    sorted_tasks.sort_by_key(|task| (task.created_at, task.id));
    for task in sorted_tasks {
        if store.has_outbox_head(SyncCollection::Tasks, task.id)? {
            summary.skipped_existing_outbox += 1;
            continue;
        }
        if dek_for_list(keys, task.list_id).is_none() {
            summary.skipped_missing_dek += 1;
            continue;
        }
        enqueue_task_sync(store, keys, device_id, task, false, now_ms)?;
        summary.enqueued_tasks += 1;
    }

    Ok(summary)
}

pub fn enqueue_task_sync<S, N>(
    store: &mut S,
    keys: &LocalSyncKeys,
    device_id: &str,
    task: &Task,
    deleted: bool,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let hlc = tick_local_hlc(store, device_id, now_ms)?;
    let encoded_hlc = hlc.encode().map_err(|_| "sync failed".to_string())?;
    let previous_state = store.get_record_state(SyncCollection::Tasks, task.id)?;
    let base_revision_hlc = previous_state
        .as_ref()
        .and_then(|state| state.current_revision_hlc.clone());
    let dek = dek_for_list(keys, task.list_id)
        .ok_or_else(|| "missing list key for task sync".to_string())?;
    let plaintext = changed_task_plaintext(previous_state.as_ref(), task, hlc.clone())?;
    enqueue_plaintext(
        store,
        EnqueuePlaintextRequest {
            record_id: task.id,
            collection: SyncCollection::Tasks,
            deleted,
            plaintext: &plaintext,
            dek: &dek,
            revision_hlc: &hlc,
            semantic_hlc: &encoded_hlc,
            base_revision_hlc,
        },
        now_ms,
    )
}

pub fn enqueue_list_sync<S, N>(
    store: &mut S,
    keys: &LocalSyncKeys,
    device_id: &str,
    list: &List,
    deleted: bool,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let hlc = tick_local_hlc(store, device_id, now_ms)?;
    let encoded_hlc = hlc.encode().map_err(|_| "sync failed".to_string())?;
    let previous_state = store.get_record_state(SyncCollection::Lists, list.id)?;
    let base_revision_hlc = previous_state
        .as_ref()
        .and_then(|state| state.current_revision_hlc.clone());
    let dek =
        dek_for_list(keys, list.id).ok_or_else(|| "missing list key for list sync".to_string())?;
    let plaintext = changed_list_plaintext(previous_state.as_ref(), list, hlc.clone())?;
    enqueue_plaintext(
        store,
        EnqueuePlaintextRequest {
            record_id: list.id,
            collection: SyncCollection::Lists,
            deleted,
            plaintext: &plaintext,
            dek: &dek,
            revision_hlc: &hlc,
            semantic_hlc: &encoded_hlc,
            base_revision_hlc,
        },
        now_ms,
    )
}

pub(crate) struct RebasePlaintextRequest<'a> {
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub plaintext: &'a SyncPlaintext,
    pub dek: &'a [u8; KEY_LEN],
    pub device_id: &'a str,
    pub base_revision_hlc: &'a str,
}

pub(crate) fn enqueue_merged_plaintext<S, N>(
    store: &mut S,
    request: RebasePlaintextRequest<'_>,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let revision_hlc =
        tick_local_hlc_after(store, request.device_id, request.base_revision_hlc, now_ms)?;
    let mutation_hlc = request
        .plaintext
        .record_hlc()
        .encode()
        .map_err(|_| "sync failed".to_string())?;
    enqueue_plaintext(
        store,
        EnqueuePlaintextRequest {
            record_id: request.record_id,
            collection: request.collection,
            deleted: false,
            plaintext: request.plaintext,
            dek: request.dek,
            revision_hlc: &revision_hlc,
            semantic_hlc: &mutation_hlc,
            base_revision_hlc: Some(request.base_revision_hlc.to_string()),
        },
        now_ms,
    )
}

pub(crate) struct RebaseTombstoneRequest<'a> {
    pub record_id: Uuid,
    pub collection: SyncCollection,
    pub delete_hlc: &'a str,
    pub device_id: &'a str,
    pub base_revision_hlc: &'a str,
}

pub(crate) fn enqueue_rebased_tombstone<S, N>(
    store: &mut S,
    request: RebaseTombstoneRequest<'_>,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    Hlc::decode(request.delete_hlc).map_err(|_| "sync failed".to_string())?;
    let revision_hlc =
        tick_local_hlc_after(store, request.device_id, request.base_revision_hlc, now_ms)?
            .encode()
            .map_err(|_| "sync failed".to_string())?;
    store.put_outbox_head(NewLocalSyncOutboxEntry {
        op_id: Uuid::now_v7(),
        record_id: request.record_id,
        collection: request.collection,
        base_revision_hlc: Some(request.base_revision_hlc.to_string()),
        revision_hlc,
        state: EncryptedSyncState::Tombstone {
            delete_hlc: request.delete_hlc.to_string(),
        },
        created_at: now_ms()?,
    })?;
    store.put_record_state(
        request.collection,
        request.record_id,
        LocalSyncRecordState {
            current_revision_hlc: Some(request.base_revision_hlc.to_string()),
            state: LocalSyncSemanticState::Tombstone {
                delete_hlc: request.delete_hlc.to_string(),
            },
        },
        now_ms()?,
    )
}

struct EnqueuePlaintextRequest<'a> {
    record_id: Uuid,
    collection: SyncCollection,
    deleted: bool,
    plaintext: &'a SyncPlaintext,
    dek: &'a [u8; KEY_LEN],
    revision_hlc: &'a Hlc,
    semantic_hlc: &'a str,
    base_revision_hlc: Option<String>,
}

fn enqueue_plaintext<S, N>(
    store: &mut S,
    request: EnqueuePlaintextRequest<'_>,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let state = if request.deleted {
        EncryptedSyncState::Tombstone {
            delete_hlc: request.semantic_hlc.to_string(),
        }
    } else {
        let blob = encrypt_plaintext(
            request.dek,
            request.collection.as_str(),
            &request.record_id.to_string(),
            request.plaintext,
        )
        .map_err(|_| "sync failed".to_string())?;
        EncryptedSyncState::Live {
            mutation_hlc: request.semantic_hlc.to_string(),
            blob,
        }
    };
    let revision_hlc = request
        .revision_hlc
        .encode()
        .map_err(|_| "sync failed".to_string())?;
    store.put_outbox_head(NewLocalSyncOutboxEntry {
        op_id: Uuid::now_v7(),
        record_id: request.record_id,
        collection: request.collection,
        base_revision_hlc: request.base_revision_hlc.clone(),
        revision_hlc,
        state,
        created_at: now_ms()?,
    })?;
    let semantic_state = if request.deleted {
        LocalSyncSemanticState::Tombstone {
            delete_hlc: request.semantic_hlc.to_string(),
        }
    } else {
        let plaintext_json =
            serde_json::to_string(request.plaintext).map_err(|_| "sync failed".to_string())?;
        LocalSyncSemanticState::Live {
            mutation_hlc: request.semantic_hlc.to_string(),
            plaintext_json,
        }
    };
    store.put_record_state(
        request.collection,
        request.record_id,
        LocalSyncRecordState {
            current_revision_hlc: request.base_revision_hlc,
            state: semantic_state,
        },
        now_ms()?,
    )
}

fn tick_local_hlc<S, N>(store: &mut S, device_id: &str, now_ms: &mut N) -> Result<Hlc, String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let mut clock = match store.get_setting(SYNC_LOCAL_HLC_SETTING_KEY)? {
        Some(encoded) if !encoded.is_empty() => {
            Hlc::decode(&encoded).unwrap_or_else(|_| Hlc::new(device_id.to_string()))
        }
        _ => Hlc::new(device_id.to_string()),
    };
    let hlc = clock.now(now_ms()?);
    store.set_setting(
        SYNC_LOCAL_HLC_SETTING_KEY,
        &hlc.encode().map_err(|_| "sync failed".to_string())?,
        now_ms()?,
    )?;
    Ok(hlc)
}

fn tick_local_hlc_after<S, N>(
    store: &mut S,
    device_id: &str,
    remote_revision_hlc: &str,
    now_ms: &mut N,
) -> Result<Hlc, String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let mut clock = match store.get_setting(SYNC_LOCAL_HLC_SETTING_KEY)? {
        Some(encoded) if !encoded.is_empty() => {
            Hlc::decode(&encoded).unwrap_or_else(|_| Hlc::new(device_id.to_string()))
        }
        _ => Hlc::new(device_id.to_string()),
    };
    let remote = Hlc::decode(remote_revision_hlc).map_err(|_| "sync failed".to_string())?;
    let hlc = clock.merge(&remote, now_ms()?);
    store.set_setting(
        SYNC_LOCAL_HLC_SETTING_KEY,
        &hlc.encode().map_err(|_| "sync failed".to_string())?,
        now_ms()?,
    )?;
    Ok(hlc)
}

pub(crate) fn observe_remote_hlc<S, N>(
    store: &mut S,
    device_id: &str,
    remote_revision_hlc: &str,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalMutationSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let mut clock = match store.get_setting(SYNC_LOCAL_HLC_SETTING_KEY)? {
        Some(encoded) if !encoded.is_empty() => {
            Hlc::decode(&encoded).unwrap_or_else(|_| Hlc::new(device_id.to_string()))
        }
        _ => Hlc::new(device_id.to_string()),
    };
    let remote = Hlc::decode(remote_revision_hlc).map_err(|_| "sync failed".to_string())?;
    let observed = clock.merge(&remote, now_ms()?);
    store.set_setting(
        SYNC_LOCAL_HLC_SETTING_KEY,
        &observed.encode().map_err(|_| "sync failed".to_string())?,
        now_ms()?,
    )
}

pub(crate) fn task_plaintext(task: &Task, hlc: Hlc) -> SyncPlaintext {
    SyncPlaintext::from_task(task, hlc).expect("domain task has a valid fixed-width rank")
}

pub(crate) fn list_plaintext(list: &List, hlc: Hlc) -> SyncPlaintext {
    SyncPlaintext::from_list(list, hlc).expect("domain list has a valid fixed-width rank")
}

fn changed_task_plaintext(
    previous: Option<&LocalSyncRecordState>,
    task: &Task,
    hlc: Hlc,
) -> Result<SyncPlaintext, String> {
    match previous.map(|state| &state.state) {
        Some(LocalSyncSemanticState::Live { plaintext_json, .. }) => {
            let previous: SyncPlaintext =
                serde_json::from_str(plaintext_json).map_err(|_| "sync failed".to_string())?;
            previous
                .stamp_task_changes(task, hlc)
                .map_err(|_| "sync failed".to_string())
        }
        _ => SyncPlaintext::from_task(task, hlc).map_err(|_| "sync failed".to_string()),
    }
}

fn changed_list_plaintext(
    previous: Option<&LocalSyncRecordState>,
    list: &List,
    hlc: Hlc,
) -> Result<SyncPlaintext, String> {
    match previous.map(|state| &state.state) {
        Some(LocalSyncSemanticState::Live { plaintext_json, .. }) => {
            let previous: SyncPlaintext =
                serde_json::from_str(plaintext_json).map_err(|_| "sync failed".to_string())?;
            previous
                .stamp_list_changes(list, hlc)
                .map_err(|_| "sync failed".to_string())
        }
        _ => SyncPlaintext::from_list(list, hlc).map_err(|_| "sync failed".to_string()),
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;
    use todori_domain::TaskStatus;

    #[derive(Default)]
    struct FakeStore {
        outbox: Vec<LocalSyncOutboxEntry>,
        settings: HashMap<String, String>,
        record_states: HashMap<(SyncCollection, Uuid), LocalSyncRecordState>,
    }

    impl LocalMutationSyncStore for FakeStore {
        fn has_outbox_head(
            &mut self,
            collection: SyncCollection,
            record_id: Uuid,
        ) -> Result<bool, String> {
            Ok(self
                .outbox
                .iter()
                .any(|entry| entry.collection == collection && entry.record_id == record_id))
        }

        fn get_setting(&mut self, key: &str) -> Result<Option<String>, String> {
            Ok(self.settings.get(key).cloned())
        }

        fn set_setting(&mut self, key: &str, value: &str, _updated_at: i64) -> Result<(), String> {
            self.settings.insert(key.to_string(), value.to_string());
            Ok(())
        }

        fn put_outbox_head(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String> {
            self.outbox.retain(|head| head.record_id != entry.record_id);
            self.outbox.push(LocalSyncOutboxEntry {
                op_id: entry.op_id,
                record_id: entry.record_id,
                collection: entry.collection,
                base_revision_hlc: entry.base_revision_hlc,
                revision_hlc: entry.revision_hlc,
                state: entry.state,
                created_at: entry.created_at,
            });
            Ok(())
        }

        fn get_record_state(
            &mut self,
            collection: SyncCollection,
            record_id: Uuid,
        ) -> Result<Option<LocalSyncRecordState>, String> {
            Ok(self.record_states.get(&(collection, record_id)).cloned())
        }

        fn put_record_state(
            &mut self,
            collection: SyncCollection,
            record_id: Uuid,
            state: LocalSyncRecordState,
            _updated_at: i64,
        ) -> Result<(), String> {
            self.record_states.insert((collection, record_id), state);
            Ok(())
        }
    }

    #[test]
    fn backfill_enqueues_lists_before_tasks() {
        let list = sample_list(uuid(1), 10);
        let task = sample_task(uuid(2), list.id, 20);
        let mut store = FakeStore::default();
        let keys = sync_keys(&[list.id]);
        let mut now = ticking_now();

        let summary = enqueue_backfill(
            &mut store,
            &keys,
            "device-a",
            &[list.clone()],
            &[task.clone()],
            &mut now,
        )
        .unwrap();

        assert_eq!(summary.enqueued_lists, 1);
        assert_eq!(summary.enqueued_tasks, 1);
        assert_eq!(store.outbox[0].collection, SyncCollection::Lists);
        assert_eq!(store.outbox[0].record_id, list.id);
        assert_eq!(store.outbox[1].collection, SyncCollection::Tasks);
        assert_eq!(store.outbox[1].record_id, task.id);
    }

    #[test]
    fn backfill_skips_records_that_already_have_outbox_rows() {
        let list = sample_list(uuid(3), 10);
        let task = sample_task(uuid(4), list.id, 20);
        let mut store = FakeStore::default();
        store
            .outbox
            .push(existing_outbox(SyncCollection::Tasks, task.id));
        let keys = sync_keys(&[list.id]);
        let mut now = ticking_now();

        let summary = enqueue_backfill(
            &mut store,
            &keys,
            "device-a",
            &[list.clone()],
            &[task],
            &mut now,
        )
        .unwrap();

        assert_eq!(summary.enqueued_lists, 1);
        assert_eq!(summary.enqueued_tasks, 0);
        assert_eq!(summary.skipped_existing_outbox, 1);
        assert_eq!(store.outbox.len(), 2);
        assert_eq!(
            store
                .outbox
                .iter()
                .filter(|entry| entry.collection == SyncCollection::Tasks)
                .count(),
            1
        );
    }

    #[test]
    fn backfill_enqueues_tasks_by_created_at() {
        let list = sample_list(uuid(5), 10);
        let later = sample_task(uuid(6), list.id, 30);
        let earlier = sample_task(uuid(7), list.id, 20);
        let mut store = FakeStore::default();
        let keys = sync_keys(&[list.id]);
        let mut now = ticking_now();

        enqueue_backfill(
            &mut store,
            &keys,
            "device-a",
            &[list],
            &[later.clone(), earlier.clone()],
            &mut now,
        )
        .unwrap();

        let task_ids = store
            .outbox
            .iter()
            .filter(|entry| entry.collection == SyncCollection::Tasks)
            .map(|entry| entry.record_id)
            .collect::<Vec<_>>();
        assert_eq!(task_ids, vec![earlier.id, later.id]);
    }

    #[test]
    fn backfill_skips_records_for_lists_missing_deks_and_keeps_processing() {
        let missing_list = sample_list(uuid(8), 10);
        let synced_list = sample_list(uuid(9), 11);
        let missing_task = sample_task(uuid(10), missing_list.id, 20);
        let synced_task = sample_task(uuid(11), synced_list.id, 21);
        let mut store = FakeStore::default();
        let keys = sync_keys(&[synced_list.id]);
        let mut now = ticking_now();

        let summary = enqueue_backfill(
            &mut store,
            &keys,
            "device-a",
            &[missing_list.clone(), synced_list.clone()],
            &[missing_task.clone(), synced_task.clone()],
            &mut now,
        )
        .unwrap();

        assert_eq!(summary.enqueued_lists, 1);
        assert_eq!(summary.enqueued_tasks, 1);
        assert_eq!(summary.skipped_missing_dek, 2);
        assert!(store
            .outbox
            .iter()
            .all(|entry| entry.record_id != missing_list.id && entry.record_id != missing_task.id));
        assert!(store
            .outbox
            .iter()
            .any(|entry| entry.record_id == synced_list.id));
        assert!(store
            .outbox
            .iter()
            .any(|entry| entry.record_id == synced_task.id));
    }

    fn sync_keys(list_ids: &[Uuid]) -> LocalSyncKeys {
        LocalSyncKeys {
            list_deks: list_ids.iter().map(|id| (*id, [7; KEY_LEN])).collect(),
        }
    }

    fn ticking_now() -> impl FnMut() -> Result<i64, String> {
        let mut now = 1_799_000_000_000;
        move || {
            now += 1;
            Ok(now)
        }
    }

    fn sample_list(id: Uuid, created_at: i64) -> List {
        List {
            id,
            name: format!("List {id}"),
            color: "#ffffff".to_string(),
            icon: "list".to_string(),
            org_id: None,
            sort_order: "7fffffffffffffffffffffffffffffff".to_string(),
            is_default: false,
            archived_at: None,
            created_at,
            updated_at: created_at,
        }
    }

    fn sample_task(id: Uuid, list_id: Uuid, created_at: i64) -> Task {
        Task {
            id,
            list_id,
            parent_task_id: None,
            title: format!("Task {id}"),
            note: String::new(),
            status: TaskStatus::Todo,
            priority: 0,
            due_at: None,
            scheduled_at: None,
            estimated_minutes: None,
            sort_order: "7fffffffffffffffffffffffffffffff".to_string(),
            completed_at: None,
            closed_reason: None,
            deleted_at: None,
            assignee: None,
            created_at,
            updated_at: created_at,
        }
    }

    fn existing_outbox(collection: SyncCollection, record_id: Uuid) -> LocalSyncOutboxEntry {
        LocalSyncOutboxEntry {
            op_id: Uuid::now_v7(),
            record_id,
            collection,
            base_revision_hlc: None,
            revision_hlc: Hlc::new("existing").now(1).encode().unwrap(),
            state: EncryptedSyncState::Live {
                mutation_hlc: Hlc::new("existing").now(1).encode().unwrap(),
                blob: vec![1],
            },
            created_at: 1,
        }
    }

    fn uuid(value: u128) -> Uuid {
        Uuid::from_u128(value)
    }
}

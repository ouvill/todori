use std::collections::BTreeMap;

use serde_json::{json, Value};
use todori_crypto::key_hierarchy::KEY_LEN;
use todori_domain::{List, Task, TaskStatus, Uuid};

use crate::{
    encrypt_plaintext, Hlc, SyncPlaintext, LISTS_COLLECTION, SYNC_LOCAL_HLC_SETTING_KEY,
    TASKS_COLLECTION,
};

use crate::keys::{dek_for_list, LocalSyncKeys};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalSyncOutboxEntry {
    pub id: i64,
    pub record_id: Uuid,
    pub collection: String,
    pub hlc: String,
    pub deleted: bool,
    pub blob: Vec<u8>,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewLocalSyncOutboxEntry {
    pub record_id: Uuid,
    pub collection: String,
    pub hlc: String,
    pub deleted: bool,
    pub blob: Vec<u8>,
    pub created_at: i64,
}

pub trait LocalSyncStore {
    fn list_outbox(&mut self, limit: usize) -> Result<Vec<LocalSyncOutboxEntry>, String>;
    fn has_outbox_entry(&mut self, collection: &str, record_id: Uuid) -> Result<bool, String>;
    fn ack_outbox(&mut self, id: i64) -> Result<(), String>;
    fn get_cursor_seq(&mut self, name: &str) -> Result<Option<i64>, String>;
    fn set_cursor(&mut self, name: &str, seq: i64, updated_at: i64) -> Result<(), String>;
    fn delete_cursor(&mut self, name: &str) -> Result<(), String>;
    fn get_setting(&mut self, key: &str) -> Result<Option<String>, String>;
    fn set_setting(&mut self, key: &str, value: &str, updated_at: i64) -> Result<(), String>;
    fn enqueue_outbox(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String>;
    fn get_record_state(
        &mut self,
        collection: &str,
        record_id: Uuid,
    ) -> Result<Option<String>, String>;
    fn upsert_record_state(
        &mut self,
        collection: &str,
        record_id: Uuid,
        plaintext_json: &str,
        updated_at: i64,
    ) -> Result<(), String>;
    fn delete_record_state(&mut self, collection: &str, record_id: Uuid) -> Result<(), String>;
    fn default_list_id(&mut self) -> Result<Option<Uuid>, String>;
    fn get_list(&mut self, id: Uuid) -> Result<Option<List>, String>;
    fn upsert_list_for_sync(&mut self, list: List) -> Result<(), String>;
    fn delete_list_with_tasks_for_sync(&mut self, list_id: Uuid) -> Result<usize, String>;
    fn get_task(&mut self, id: Uuid) -> Result<Option<Task>, String>;
    fn upsert_task_for_sync(&mut self, task: Task) -> Result<(), String>;
    fn delete_task_subtree_for_sync(&mut self, task_id: Uuid) -> Result<usize, String>;
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
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let mut summary = BackfillSummary::default();

    for list in lists {
        if store.has_outbox_entry(LISTS_COLLECTION, list.id)? {
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
        if store.has_outbox_entry(TASKS_COLLECTION, task.id)? {
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
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let hlc = tick_local_hlc(store, device_id, now_ms)?;
    let dek = dek_for_list(keys, task.list_id)
        .ok_or_else(|| "missing list key for task sync".to_string())?;
    let plaintext = task_plaintext(task, hlc.clone());
    enqueue_plaintext(
        store,
        EnqueuePlaintextRequest {
            record_id: task.id,
            collection: TASKS_COLLECTION,
            deleted,
            plaintext: &plaintext,
            dek: &dek,
            hlc: &hlc,
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
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let hlc = tick_local_hlc(store, device_id, now_ms)?;
    let dek =
        dek_for_list(keys, list.id).ok_or_else(|| "missing list key for list sync".to_string())?;
    let plaintext = list_plaintext(list, hlc.clone());
    enqueue_plaintext(
        store,
        EnqueuePlaintextRequest {
            record_id: list.id,
            collection: LISTS_COLLECTION,
            deleted,
            plaintext: &plaintext,
            dek: &dek,
            hlc: &hlc,
        },
        now_ms,
    )
}

pub(crate) fn enqueue_merged_plaintext<S, N>(
    store: &mut S,
    record_id: Uuid,
    collection: &str,
    plaintext: &SyncPlaintext,
    dek: &[u8; KEY_LEN],
    device_id: &str,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let mut merged = plaintext.clone();
    let hlc = tick_local_hlc(store, device_id, now_ms)?;
    for field_hlc in merged.field_hlcs.values_mut() {
        if *field_hlc < hlc {
            *field_hlc = hlc.clone();
        }
    }
    enqueue_plaintext(
        store,
        EnqueuePlaintextRequest {
            record_id,
            collection,
            deleted: false,
            plaintext: &merged,
            dek,
            hlc: &hlc,
        },
        now_ms,
    )
}

struct EnqueuePlaintextRequest<'a> {
    record_id: Uuid,
    collection: &'a str,
    deleted: bool,
    plaintext: &'a SyncPlaintext,
    dek: &'a [u8; KEY_LEN],
    hlc: &'a Hlc,
}

fn enqueue_plaintext<S, N>(
    store: &mut S,
    request: EnqueuePlaintextRequest<'_>,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let blob = if request.deleted {
        Vec::new()
    } else {
        encrypt_plaintext(
            request.dek,
            request.collection,
            &request.record_id.to_string(),
            request.plaintext,
        )
        .map_err(|_| "sync failed".to_string())?
    };
    let encoded_hlc = request
        .hlc
        .encode()
        .map_err(|_| "sync failed".to_string())?;
    store.enqueue_outbox(NewLocalSyncOutboxEntry {
        record_id: request.record_id,
        collection: request.collection.to_string(),
        hlc: encoded_hlc,
        deleted: request.deleted,
        blob,
        created_at: now_ms()?,
    })?;
    if request.deleted {
        store.delete_record_state(request.collection, request.record_id)
    } else {
        let plaintext_json =
            serde_json::to_string(request.plaintext).map_err(|_| "sync failed".to_string())?;
        store.upsert_record_state(
            request.collection,
            request.record_id,
            &plaintext_json,
            now_ms()?,
        )
    }
}

fn tick_local_hlc<S, N>(store: &mut S, device_id: &str, now_ms: &mut N) -> Result<Hlc, String>
where
    S: LocalSyncStore,
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

pub(crate) fn task_plaintext(task: &Task, hlc: Hlc) -> SyncPlaintext {
    SyncPlaintext::from_single_hlc(
        BTreeMap::from([
            ("list_id".to_string(), json!(task.list_id.to_string())),
            (
                "parent_task_id".to_string(),
                option_uuid_value(task.parent_task_id),
            ),
            ("title".to_string(), json!(task.title)),
            ("note".to_string(), json!(task.note)),
            ("status".to_string(), json!(status_to_string(task.status))),
            ("priority".to_string(), json!(task.priority)),
            ("due_at".to_string(), option_i64_value(task.due_at)),
            (
                "scheduled_at".to_string(),
                option_i64_value(task.scheduled_at),
            ),
            (
                "estimated_minutes".to_string(),
                option_i32_value(task.estimated_minutes),
            ),
            (
                "completed_at".to_string(),
                option_i64_value(task.completed_at),
            ),
            (
                "closed_reason".to_string(),
                option_string_value(task.closed_reason.clone()),
            ),
            ("deleted_at".to_string(), option_i64_value(task.deleted_at)),
            ("assignee".to_string(), option_uuid_value(task.assignee)),
            ("created_at".to_string(), json!(task.created_at)),
            ("updated_at".to_string(), json!(task.updated_at)),
        ]),
        hlc,
    )
    .expect("task sync plaintext excludes sort_order and has matching HLC keys")
}

pub(crate) fn list_plaintext(list: &List, hlc: Hlc) -> SyncPlaintext {
    SyncPlaintext::from_single_hlc(
        BTreeMap::from([
            ("name".to_string(), json!(list.name)),
            ("color".to_string(), json!(list.color)),
            ("icon".to_string(), json!(list.icon)),
            ("org_id".to_string(), option_uuid_value(list.org_id)),
            ("is_default".to_string(), json!(list.is_default)),
            (
                "archived_at".to_string(),
                option_i64_value(list.archived_at),
            ),
            ("created_at".to_string(), json!(list.created_at)),
            ("updated_at".to_string(), json!(list.updated_at)),
        ]),
        hlc,
    )
    .expect("list sync plaintext excludes sort_order and has matching HLC keys")
}

pub(crate) fn status_to_string(status: TaskStatus) -> String {
    match status {
        TaskStatus::Todo => "todo",
        TaskStatus::InProgress => "in_progress",
        TaskStatus::Done => "done",
        TaskStatus::WontDo => "wont_do",
    }
    .to_string()
}

pub(crate) fn parse_status(value: &str) -> Result<TaskStatus, String> {
    match value {
        "todo" => Ok(TaskStatus::Todo),
        "in_progress" => Ok(TaskStatus::InProgress),
        "done" => Ok(TaskStatus::Done),
        "wont_do" => Ok(TaskStatus::WontDo),
        other => Err(format!("invalid task status: {other}")),
    }
}

pub(crate) fn option_uuid_value(value: Option<Uuid>) -> Value {
    value.map(|id| json!(id.to_string())).unwrap_or(Value::Null)
}

fn option_i64_value(value: Option<i64>) -> Value {
    value.map(Value::from).unwrap_or(Value::Null)
}

fn option_i32_value(value: Option<i32>) -> Value {
    value.map(Value::from).unwrap_or(Value::Null)
}

fn option_string_value(value: Option<String>) -> Value {
    value.map(Value::from).unwrap_or(Value::Null)
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;

    #[derive(Default)]
    struct FakeStore {
        next_outbox_id: i64,
        outbox: Vec<LocalSyncOutboxEntry>,
        cursors: HashMap<String, i64>,
        settings: HashMap<String, String>,
        record_states: HashMap<(String, Uuid), String>,
    }

    impl LocalSyncStore for FakeStore {
        fn list_outbox(&mut self, limit: usize) -> Result<Vec<LocalSyncOutboxEntry>, String> {
            Ok(self.outbox.iter().take(limit).cloned().collect())
        }

        fn has_outbox_entry(&mut self, collection: &str, record_id: Uuid) -> Result<bool, String> {
            Ok(self
                .outbox
                .iter()
                .any(|entry| entry.collection == collection && entry.record_id == record_id))
        }

        fn ack_outbox(&mut self, id: i64) -> Result<(), String> {
            self.outbox.retain(|entry| entry.id != id);
            Ok(())
        }

        fn get_cursor_seq(&mut self, name: &str) -> Result<Option<i64>, String> {
            Ok(self.cursors.get(name).copied())
        }

        fn set_cursor(&mut self, name: &str, seq: i64, _updated_at: i64) -> Result<(), String> {
            self.cursors.insert(name.to_string(), seq);
            Ok(())
        }

        fn delete_cursor(&mut self, name: &str) -> Result<(), String> {
            self.cursors.remove(name);
            Ok(())
        }

        fn get_setting(&mut self, key: &str) -> Result<Option<String>, String> {
            Ok(self.settings.get(key).cloned())
        }

        fn set_setting(&mut self, key: &str, value: &str, _updated_at: i64) -> Result<(), String> {
            self.settings.insert(key.to_string(), value.to_string());
            Ok(())
        }

        fn enqueue_outbox(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String> {
            self.next_outbox_id += 1;
            self.outbox.push(LocalSyncOutboxEntry {
                id: self.next_outbox_id,
                record_id: entry.record_id,
                collection: entry.collection,
                hlc: entry.hlc,
                deleted: entry.deleted,
                blob: entry.blob,
                created_at: entry.created_at,
            });
            Ok(())
        }

        fn get_record_state(
            &mut self,
            collection: &str,
            record_id: Uuid,
        ) -> Result<Option<String>, String> {
            Ok(self
                .record_states
                .get(&(collection.to_string(), record_id))
                .cloned())
        }

        fn upsert_record_state(
            &mut self,
            collection: &str,
            record_id: Uuid,
            plaintext_json: &str,
            _updated_at: i64,
        ) -> Result<(), String> {
            self.record_states.insert(
                (collection.to_string(), record_id),
                plaintext_json.to_string(),
            );
            Ok(())
        }

        fn delete_record_state(&mut self, collection: &str, record_id: Uuid) -> Result<(), String> {
            self.record_states
                .remove(&(collection.to_string(), record_id));
            Ok(())
        }

        fn default_list_id(&mut self) -> Result<Option<Uuid>, String> {
            Ok(None)
        }

        fn get_list(&mut self, _id: Uuid) -> Result<Option<List>, String> {
            Ok(None)
        }

        fn upsert_list_for_sync(&mut self, _list: List) -> Result<(), String> {
            Ok(())
        }

        fn delete_list_with_tasks_for_sync(&mut self, _list_id: Uuid) -> Result<usize, String> {
            Ok(0)
        }

        fn get_task(&mut self, _id: Uuid) -> Result<Option<Task>, String> {
            Ok(None)
        }

        fn upsert_task_for_sync(&mut self, _task: Task) -> Result<(), String> {
            Ok(())
        }

        fn delete_task_subtree_for_sync(&mut self, _task_id: Uuid) -> Result<usize, String> {
            Ok(0)
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
        assert_eq!(store.outbox[0].collection, LISTS_COLLECTION);
        assert_eq!(store.outbox[0].record_id, list.id);
        assert_eq!(store.outbox[1].collection, TASKS_COLLECTION);
        assert_eq!(store.outbox[1].record_id, task.id);
    }

    #[test]
    fn backfill_skips_records_that_already_have_outbox_rows() {
        let list = sample_list(uuid(3), 10);
        let task = sample_task(uuid(4), list.id, 20);
        let mut store = FakeStore::default();
        store
            .outbox
            .push(existing_outbox(TASKS_COLLECTION, task.id));
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
                .filter(|entry| entry.collection == TASKS_COLLECTION)
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
            .filter(|entry| entry.collection == TASKS_COLLECTION)
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
            sort_order: "a0".to_string(),
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
            sort_order: "a0".to_string(),
            completed_at: None,
            closed_reason: None,
            deleted_at: None,
            assignee: None,
            created_at,
            updated_at: created_at,
        }
    }

    fn existing_outbox(collection: &str, record_id: Uuid) -> LocalSyncOutboxEntry {
        LocalSyncOutboxEntry {
            id: 99,
            record_id,
            collection: collection.to_string(),
            hlc: "existing".to_string(),
            deleted: false,
            blob: Vec::new(),
            created_at: 1,
        }
    }

    fn uuid(value: u128) -> Uuid {
        Uuid::from_u128(value)
    }
}

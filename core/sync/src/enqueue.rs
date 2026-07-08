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
    fn ack_outbox(&mut self, id: i64) -> Result<(), String>;
    fn get_cursor_seq(&mut self, name: &str) -> Result<Option<i64>, String>;
    fn set_cursor(&mut self, name: &str, seq: i64, updated_at: i64) -> Result<(), String>;
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
    fn get_list(&mut self, id: Uuid) -> Result<Option<List>, String>;
    fn upsert_list_for_sync(&mut self, list: List) -> Result<(), String>;
    fn delete_list_with_tasks_for_sync(&mut self, list_id: Uuid) -> Result<usize, String>;
    fn get_task(&mut self, id: Uuid) -> Result<Option<Task>, String>;
    fn upsert_task_for_sync(&mut self, task: Task) -> Result<(), String>;
    fn delete_task_subtree_for_sync(&mut self, task_id: Uuid) -> Result<usize, String>;
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

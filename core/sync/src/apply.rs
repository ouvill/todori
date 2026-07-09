use std::collections::BTreeMap;

use serde_json::Value;
use todori_domain::{List, Task, TaskStatus, Uuid};

use crate::{
    decrypt_plaintext, merge_lww, Hlc, PullRecord, PushOp, PushStatus, SyncEngine, SyncPlaintext,
    SyncRunSummary, LISTS_COLLECTION, SYNC_CURSOR_NAME, TASKS_COLLECTION,
};

use crate::enqueue::{
    enqueue_merged_plaintext, list_plaintext, parse_status, task_plaintext, LocalSyncStore,
};
use crate::keys::{dek_for_list, LocalSyncKeys};

const PUSH_BATCH_LIMIT: usize = 100;
const MAX_PUSH_DRAIN_ITERATIONS: usize = 100;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActiveSyncContext {
    pub server_url: String,
    pub tenant_id: Uuid,
    pub device_id: String,
    pub session_token: String,
    pub keys: LocalSyncKeys,
}

pub async fn run_sync_now<S, N>(
    context: ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
) -> Result<SyncRunSummary, String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let engine = SyncEngine::new(
        context.server_url.clone(),
        context.tenant_id,
        context.session_token.clone(),
    )
    .map_err(|_| "sync failed".to_string())?;
    let mut summary = SyncRunSummary::default();

    for _ in 0..MAX_PUSH_DRAIN_ITERATIONS {
        let outbox = store.list_outbox(PUSH_BATCH_LIMIT)?;
        if outbox.is_empty() {
            break;
        }
        summary.pushed_count += outbox.len();
        let push_ops = outbox
            .into_iter()
            .map(|entry| PushOp {
                outbox_id: entry.id,
                record_id: entry.record_id,
                collection: entry.collection,
                hlc: entry.hlc,
                deleted: entry.deleted,
                blob: entry.blob,
            })
            .collect::<Vec<_>>();
        let push_outcome = engine
            .push_batch(push_ops)
            .await
            .map_err(|_| "sync failed".to_string())?;
        for outcome in push_outcome.outcomes {
            match outcome.status {
                PushStatus::Accepted | PushStatus::NoOp => {
                    store.ack_outbox(outcome.outbox_id)?;
                    summary.push_acked_count += 1;
                }
                PushStatus::Superseded => {
                    store.ack_outbox(outcome.outbox_id)?;
                    summary.push_superseded_count += 1;
                }
            }
        }
    }

    loop {
        let since = store.get_cursor_seq(SYNC_CURSOR_NAME)?.unwrap_or(0);
        let page = engine
            .pull_page(since, 100)
            .await
            .map_err(|_| "sync failed".to_string())?;
        if page.records.is_empty() {
            break;
        }
        summary.pulled_count += page.records.len();
        for record in &page.records {
            apply_pull_record(record, &context, store, now_ms, &mut summary)?;
        }
        store.set_cursor(SYNC_CURSOR_NAME, page.next_since, now_ms()?)?;
        if !page.has_more {
            break;
        }
    }

    Ok(summary)
}

fn apply_pull_record<S, N>(
    record: &PullRecord,
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    summary: &mut SyncRunSummary,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    match record.collection.as_str() {
        LISTS_COLLECTION => apply_pull_list(record, context, store, now_ms, summary),
        TASKS_COLLECTION => apply_pull_task(record, context, store, now_ms, summary),
        _ => {
            summary.decrypt_failed_count += 1;
            Ok(())
        }
    }
}

fn apply_pull_list<S, N>(
    record: &PullRecord,
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    summary: &mut SyncRunSummary,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    if record.deleted {
        let deleted = store.delete_list_with_tasks_for_sync(record.record_id)?;
        summary.deleted_count += 1 + deleted;
        store.delete_record_state(LISTS_COLLECTION, record.record_id)?;
        return Ok(());
    }

    let dek = match dek_for_list(&context.keys, record.record_id) {
        Some(dek) => dek,
        None => {
            summary.decrypt_failed_count += 1;
            return Ok(());
        }
    };
    let incoming = decrypt_plaintext(
        &dek,
        LISTS_COLLECTION,
        &record.record_id.to_string(),
        &record.blob,
    );
    let incoming = match incoming {
        Ok(incoming) => incoming,
        Err(_) => {
            summary.decrypt_failed_count += 1;
            return Ok(());
        }
    };
    let existing = store.get_list(record.record_id)?;
    let stored_plaintext = stored_sync_plaintext(store, LISTS_COLLECTION, record.record_id)?;
    let (merged, needs_repush) = match (stored_plaintext, existing.as_ref()) {
        (Some(local_plaintext), _) => {
            let merge = merge_lww(&local_plaintext, &incoming).map_err(|_| "sync failed")?;
            let needs_repush = merge.needs_repush();
            (merge.plaintext, needs_repush)
        }
        (None, Some(local)) => {
            let local_plaintext = list_plaintext(local, record_hlc_or_initial(&incoming));
            let merge = merge_lww(&local_plaintext, &incoming).map_err(|_| "sync failed")?;
            let needs_repush = merge.needs_repush();
            (merge.plaintext, needs_repush)
        }
        (None, None) => (incoming, false),
    };
    let mut list = list_from_plaintext(record.record_id, existing.as_ref(), &merged, now_ms)?;
    if list.is_default {
        if let Some(default_list_id) = store.default_list_id()? {
            if default_list_id != list.id {
                // Inbox重複のマージ方針はBACKLOG #30の裁定待ち。ここでは同期を失敗させないための暫定デモーション。
                list.is_default = false;
            }
        }
    }
    store.upsert_list_for_sync(list)?;
    store_sync_plaintext(store, LISTS_COLLECTION, record.record_id, &merged, now_ms)?;
    summary.applied_count += 1;
    if needs_repush {
        enqueue_merged_plaintext(
            store,
            record.record_id,
            LISTS_COLLECTION,
            &merged,
            &dek,
            &context.device_id,
            now_ms,
        )?;
        summary.repush_count += 1;
    }
    Ok(())
}

fn apply_pull_task<S, N>(
    record: &PullRecord,
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    summary: &mut SyncRunSummary,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    if record.deleted {
        let deleted = store.delete_task_subtree_for_sync(record.record_id)?;
        summary.deleted_count += deleted;
        store.delete_record_state(TASKS_COLLECTION, record.record_id)?;
        return Ok(());
    }

    let existing = store.get_task(record.record_id)?;
    let incoming = match decrypt_task_plaintext(record, existing.as_ref(), &context.keys) {
        Some(incoming) => incoming,
        None => {
            summary.decrypt_failed_count += 1;
            return Ok(());
        }
    };
    let dek = if let Some(incoming_dek) = incoming
        .fields
        .get("list_id")
        .and_then(Value::as_str)
        .and_then(|list_id| list_id.parse::<Uuid>().ok())
        .and_then(|list_id| dek_for_list(&context.keys, list_id))
    {
        incoming_dek
    } else {
        summary.decrypt_failed_count += 1;
        return Ok(());
    };
    let stored_plaintext = stored_sync_plaintext(store, TASKS_COLLECTION, record.record_id)?;
    let (merged, needs_repush) = match (stored_plaintext, existing.as_ref()) {
        (Some(local_plaintext), _) => {
            let merge = merge_lww(&local_plaintext, &incoming).map_err(|_| "sync failed")?;
            let needs_repush = merge.needs_repush();
            (merge.plaintext, needs_repush)
        }
        (None, Some(local)) => {
            let local_plaintext = task_plaintext(local, record_hlc_or_initial(&incoming));
            let merge = merge_lww(&local_plaintext, &incoming).map_err(|_| "sync failed")?;
            let needs_repush = merge.needs_repush();
            (merge.plaintext, needs_repush)
        }
        (None, None) => (incoming, false),
    };
    let task = task_from_plaintext(record.record_id, existing.as_ref(), &merged, now_ms)?;
    store.upsert_task_for_sync(task)?;
    store_sync_plaintext(store, TASKS_COLLECTION, record.record_id, &merged, now_ms)?;
    summary.applied_count += 1;
    if needs_repush {
        enqueue_merged_plaintext(
            store,
            record.record_id,
            TASKS_COLLECTION,
            &merged,
            &dek,
            &context.device_id,
            now_ms,
        )?;
        summary.repush_count += 1;
    }
    Ok(())
}

fn stored_sync_plaintext<S>(
    store: &mut S,
    collection: &str,
    record_id: Uuid,
) -> Result<Option<SyncPlaintext>, String>
where
    S: LocalSyncStore,
{
    store
        .get_record_state(collection, record_id)?
        .map(|json| serde_json::from_str(&json).map_err(|_| "sync failed".to_string()))
        .transpose()
}

fn store_sync_plaintext<S, N>(
    store: &mut S,
    collection: &str,
    record_id: Uuid,
    plaintext: &SyncPlaintext,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let plaintext_json = serde_json::to_string(plaintext).map_err(|_| "sync failed".to_string())?;
    store.upsert_record_state(collection, record_id, &plaintext_json, now_ms()?)
}

fn decrypt_task_plaintext(
    record: &PullRecord,
    existing: Option<&Task>,
    keys: &LocalSyncKeys,
) -> Option<SyncPlaintext> {
    let mut candidates = Vec::new();
    if let Some(task) = existing {
        if let Some(dek) = dek_for_list(keys, task.list_id) {
            candidates.push(dek);
        }
    }
    for (_, dek) in &keys.list_deks {
        if !candidates.iter().any(|candidate| candidate == dek) {
            candidates.push(*dek);
        }
    }
    candidates.into_iter().find_map(|dek| {
        decrypt_plaintext(
            &dek,
            TASKS_COLLECTION,
            &record.record_id.to_string(),
            &record.blob,
        )
        .ok()
    })
}

fn record_hlc_or_initial(plaintext: &SyncPlaintext) -> Hlc {
    plaintext
        .record_hlc()
        .cloned()
        .unwrap_or_else(|| Hlc::new("sync"))
}

fn task_from_plaintext<N>(
    id: Uuid,
    existing: Option<&Task>,
    plaintext: &SyncPlaintext,
    now_ms: &mut N,
) -> Result<Task, String>
where
    N: FnMut() -> Result<i64, String>,
{
    let fields = &plaintext.fields;
    let existing = existing.cloned();
    Ok(Task {
        id,
        list_id: value_uuid(fields, "list_id")?
            .or_else(|| existing.as_ref().map(|task| task.list_id))
            .ok_or_else(|| "sync failed".to_string())?,
        parent_task_id: value_uuid(fields, "parent_task_id")?
            .or_else(|| existing.as_ref().and_then(|task| task.parent_task_id)),
        title: value_string(fields, "title")
            .or_else(|| existing.as_ref().map(|task| task.title.clone()))
            .unwrap_or_default(),
        note: value_string(fields, "note")
            .or_else(|| existing.as_ref().map(|task| task.note.clone()))
            .unwrap_or_default(),
        status: value_string(fields, "status")
            .as_deref()
            .map(parse_status)
            .transpose()?
            .or_else(|| existing.as_ref().map(|task| task.status))
            .unwrap_or(TaskStatus::Todo),
        priority: value_i64(fields, "priority")
            .map(|value| value as i32)
            .or_else(|| existing.as_ref().map(|task| task.priority))
            .unwrap_or(0),
        due_at: value_i64(fields, "due_at")
            .or_else(|| existing.as_ref().and_then(|task| task.due_at)),
        scheduled_at: value_i64(fields, "scheduled_at")
            .or_else(|| existing.as_ref().and_then(|task| task.scheduled_at)),
        estimated_minutes: value_i64(fields, "estimated_minutes")
            .map(|value| value as i32)
            .or_else(|| existing.as_ref().and_then(|task| task.estimated_minutes)),
        sort_order: existing
            .as_ref()
            .map(|task| task.sort_order.clone())
            .unwrap_or_else(|| "a0".to_string()),
        completed_at: value_i64(fields, "completed_at")
            .or_else(|| existing.as_ref().and_then(|task| task.completed_at)),
        closed_reason: value_string(fields, "closed_reason").or_else(|| {
            existing
                .as_ref()
                .and_then(|task| task.closed_reason.clone())
        }),
        deleted_at: value_i64(fields, "deleted_at")
            .or_else(|| existing.as_ref().and_then(|task| task.deleted_at)),
        assignee: value_uuid(fields, "assignee")?
            .or_else(|| existing.as_ref().and_then(|task| task.assignee)),
        created_at: value_i64(fields, "created_at")
            .or_else(|| existing.as_ref().map(|task| task.created_at))
            .unwrap_or_else(|| now_ms().unwrap_or(0)),
        updated_at: value_i64(fields, "updated_at")
            .or_else(|| existing.as_ref().map(|task| task.updated_at))
            .unwrap_or_else(|| now_ms().unwrap_or(0)),
    })
}

fn list_from_plaintext<N>(
    id: Uuid,
    existing: Option<&List>,
    plaintext: &SyncPlaintext,
    now_ms: &mut N,
) -> Result<List, String>
where
    N: FnMut() -> Result<i64, String>,
{
    let fields = &plaintext.fields;
    let existing = existing.cloned();
    Ok(List {
        id,
        name: value_string(fields, "name")
            .or_else(|| existing.as_ref().map(|list| list.name.clone()))
            .unwrap_or_default(),
        color: value_string(fields, "color")
            .or_else(|| existing.as_ref().map(|list| list.color.clone()))
            .unwrap_or_default(),
        icon: value_string(fields, "icon")
            .or_else(|| existing.as_ref().map(|list| list.icon.clone()))
            .unwrap_or_default(),
        org_id: value_uuid(fields, "org_id")?
            .or_else(|| existing.as_ref().and_then(|list| list.org_id)),
        sort_order: existing
            .as_ref()
            .map(|list| list.sort_order.clone())
            .unwrap_or_else(|| "a0".to_string()),
        is_default: value_bool(fields, "is_default")
            .or_else(|| existing.as_ref().map(|list| list.is_default))
            .unwrap_or(false),
        archived_at: value_i64(fields, "archived_at")
            .or_else(|| existing.as_ref().and_then(|list| list.archived_at)),
        created_at: value_i64(fields, "created_at")
            .or_else(|| existing.as_ref().map(|list| list.created_at))
            .unwrap_or_else(|| now_ms().unwrap_or(0)),
        updated_at: value_i64(fields, "updated_at")
            .or_else(|| existing.as_ref().map(|list| list.updated_at))
            .unwrap_or_else(|| now_ms().unwrap_or(0)),
    })
}

fn value_string(fields: &BTreeMap<String, Value>, key: &str) -> Option<String> {
    fields.get(key)?.as_str().map(ToOwned::to_owned)
}

fn value_i64(fields: &BTreeMap<String, Value>, key: &str) -> Option<i64> {
    fields.get(key)?.as_i64()
}

fn value_bool(fields: &BTreeMap<String, Value>, key: &str) -> Option<bool> {
    fields.get(key)?.as_bool()
}

fn value_uuid(fields: &BTreeMap<String, Value>, key: &str) -> Result<Option<Uuid>, String> {
    fields
        .get(key)
        .and_then(Value::as_str)
        .map(str::parse::<Uuid>)
        .transpose()
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use todori_crypto::key_hierarchy::KEY_LEN;

    use super::*;
    use crate::{encrypt_plaintext, LocalSyncOutboxEntry, NewLocalSyncOutboxEntry};

    #[derive(Default)]
    struct FakeStore {
        lists: HashMap<Uuid, List>,
        record_states: HashMap<(String, Uuid), String>,
        outbox: Vec<LocalSyncOutboxEntry>,
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

        fn get_cursor_seq(&mut self, _name: &str) -> Result<Option<i64>, String> {
            Ok(None)
        }

        fn set_cursor(&mut self, _name: &str, _seq: i64, _updated_at: i64) -> Result<(), String> {
            Ok(())
        }

        fn delete_cursor(&mut self, _name: &str) -> Result<(), String> {
            Ok(())
        }

        fn get_setting(&mut self, _key: &str) -> Result<Option<String>, String> {
            Ok(None)
        }

        fn set_setting(
            &mut self,
            _key: &str,
            _value: &str,
            _updated_at: i64,
        ) -> Result<(), String> {
            Ok(())
        }

        fn enqueue_outbox(&mut self, entry: NewLocalSyncOutboxEntry) -> Result<(), String> {
            self.outbox.push(LocalSyncOutboxEntry {
                id: self.outbox.len() as i64 + 1,
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
            Ok(self
                .lists
                .values()
                .find(|list| list.is_default)
                .map(|list| list.id))
        }

        fn get_list(&mut self, id: Uuid) -> Result<Option<List>, String> {
            Ok(self.lists.get(&id).cloned())
        }

        fn upsert_list_for_sync(&mut self, list: List) -> Result<(), String> {
            if list.is_default
                && self
                    .lists
                    .values()
                    .any(|existing| existing.is_default && existing.id != list.id)
            {
                return Err("default list conflict".to_string());
            }
            self.lists.insert(list.id, list);
            Ok(())
        }

        fn delete_list_with_tasks_for_sync(&mut self, list_id: Uuid) -> Result<usize, String> {
            self.lists.remove(&list_id);
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
    fn pull_default_list_with_existing_different_default_demotes_local_row_only() {
        let local_default = sample_list(uuid(1), true);
        let incoming_list = sample_list(uuid(2), true);
        let dek = [0x7a; KEY_LEN];
        let record = encrypted_list_record(&incoming_list, &dek);
        let context = context_for(incoming_list.id, dek);
        let mut store = FakeStore::default();
        store.lists.insert(local_default.id, local_default);
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        apply_pull_list(&record, &context, &mut store, &mut now, &mut summary).unwrap();

        assert!(!store.lists.get(&incoming_list.id).unwrap().is_default);
        let stored_plaintext =
            stored_sync_plaintext(&mut store, LISTS_COLLECTION, incoming_list.id).unwrap();
        assert_eq!(
            stored_plaintext
                .unwrap()
                .fields
                .get("is_default")
                .and_then(Value::as_bool),
            Some(true)
        );
        assert_eq!(store.outbox.len(), 0);
        assert_eq!(summary.applied_count, 1);
        assert_eq!(summary.repush_count, 0);
    }

    #[test]
    fn pull_default_list_without_existing_default_keeps_default_flag() {
        let incoming_list = sample_list(uuid(3), true);
        let dek = [0x3b; KEY_LEN];
        let record = encrypted_list_record(&incoming_list, &dek);
        let context = context_for(incoming_list.id, dek);
        let mut store = FakeStore::default();
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        apply_pull_list(&record, &context, &mut store, &mut now, &mut summary).unwrap();

        assert!(store.lists.get(&incoming_list.id).unwrap().is_default);
        assert_eq!(summary.applied_count, 1);
        assert_eq!(summary.repush_count, 0);
    }

    fn encrypted_list_record(list: &List, dek: &[u8; KEY_LEN]) -> PullRecord {
        let hlc = Hlc {
            wall_ms: list.updated_at,
            counter: 0,
            device_id: "remote".to_string(),
        };
        let plaintext = list_plaintext(list, hlc.clone());
        let blob = encrypt_plaintext(dek, LISTS_COLLECTION, &list.id.to_string(), &plaintext)
            .expect("test list plaintext encrypts");
        PullRecord {
            record_id: list.id,
            collection: LISTS_COLLECTION.to_string(),
            seq: 1,
            hlc: hlc.encode().unwrap(),
            deleted: false,
            blob,
        }
    }

    fn context_for(list_id: Uuid, dek: [u8; KEY_LEN]) -> ActiveSyncContext {
        ActiveSyncContext {
            server_url: "http://localhost".to_string(),
            tenant_id: uuid(100),
            device_id: "local".to_string(),
            session_token: "token".to_string(),
            keys: LocalSyncKeys {
                list_deks: vec![(list_id, dek)],
            },
        }
    }

    fn sample_list(id: Uuid, is_default: bool) -> List {
        List {
            id,
            name: format!("List {id}"),
            color: "#ffffff".to_string(),
            icon: "list".to_string(),
            org_id: None,
            sort_order: "a0".to_string(),
            is_default,
            archived_at: None,
            created_at: 1_799_000_000_000,
            updated_at: 1_799_000_000_000,
        }
    }

    fn ticking_now() -> impl FnMut() -> Result<i64, String> {
        let mut now = 1_799_000_000_000;
        move || {
            now += 1;
            Ok(now)
        }
    }

    fn uuid(value: u128) -> Uuid {
        Uuid::from_u128(value)
    }
}

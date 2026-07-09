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
    let list = list_from_plaintext(record.record_id, existing.as_ref(), &merged, now_ms)?;
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

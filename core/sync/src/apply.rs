use std::{
    collections::{HashMap, HashSet},
    future::Future,
    pin::Pin,
};

use base64::{engine::general_purpose::STANDARD, Engine as _};
use todori_domain::{List, Task, Uuid};

use crate::{
    account::{AccountClient, ListDekBundleDto},
    decrypt_plaintext, merge_lww, EncryptedSyncState, EnvelopeError, Hlc, PullRecord, PushOp,
    PushStatus, SyncCollection, SyncEngine, SyncEngineError, SyncPlaintext, SyncRunSummary,
    LISTS_COLLECTION, SYNC_CURSOR_NAME, SYNC_UPGRADE_REQUIRED_SETTING_KEY, TASKS_COLLECTION,
};

use crate::enqueue::{
    enqueue_merged_plaintext, enqueue_rebased_tombstone, list_plaintext, observe_remote_hlc,
    task_plaintext, LocalFullResyncPhase, LocalSyncAtomicStore, LocalSyncQuarantineEntry,
    LocalSyncRecordState, LocalSyncSemanticState, LocalSyncStore, LocalSyncWriteTransaction,
    PullFailureReason, RebasePlaintextRequest, RebaseTombstoneRequest,
};
use crate::keys::{dek_for_list, LocalSyncKeys};

const PUSH_BATCH_LIMIT: usize = 100;
const MAX_PUSH_DRAIN_ITERATIONS: usize = 100;
const QUARANTINE_REPLAY_BATCH_LIMIT: usize = 100;
const KEY_BUNDLE_UPLOAD_BATCH_LIMIT: usize = 100;
const FULL_RESYNC_PAGE_LIMIT: i64 = 100;
const FULL_RESYNC_SWEEP_BATCH_LIMIT: usize = 100;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ApplyDisposition {
    AppliedCurrent,
    Rebased,
    Deferred(PullFailureReason, Option<Uuid>),
    UpgradeRequired(u8),
}

enum TaskDependencyDisposition {
    Valid,
    Missing,
    Deleted(String),
}

pub trait SyncKeyRefresher {
    fn refresh<'a>(
        &'a mut self,
    ) -> Pin<Box<dyn Future<Output = Result<LocalSyncKeys, String>> + Send + 'a>>;
}

struct UnavailableKeyRefresher;

impl SyncKeyRefresher for UnavailableKeyRefresher {
    fn refresh<'a>(
        &'a mut self,
    ) -> Pin<Box<dyn Future<Output = Result<LocalSyncKeys, String>> + Send + 'a>> {
        Box::pin(async { Err("key refresh unavailable".to_string()) })
    }
}

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
    S: LocalSyncAtomicStore,
    N: FnMut() -> Result<i64, String>,
{
    run_sync_now_with_key_refresh(context, store, now_ms, &mut UnavailableKeyRefresher).await
}

pub async fn run_sync_now_with_key_refresh<S, N, R>(
    context: ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    key_refresher: &mut R,
) -> Result<SyncRunSummary, String>
where
    S: LocalSyncAtomicStore,
    N: FnMut() -> Result<i64, String>,
    R: SyncKeyRefresher,
{
    let mut no_pre_push = |_store: &mut S| Ok(());
    run_sync_now_with_key_refresh_and_pre_push(
        context,
        store,
        now_ms,
        key_refresher,
        &mut no_pre_push,
    )
    .await
}

pub async fn run_sync_now_with_key_refresh_and_pre_push<S, N, R, P>(
    mut context: ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    key_refresher: &mut R,
    pre_push: &mut P,
) -> Result<SyncRunSummary, String>
where
    S: LocalSyncAtomicStore,
    N: FnMut() -> Result<i64, String>,
    R: SyncKeyRefresher,
    P: FnMut(&mut S) -> Result<(), String>,
{
    let engine = SyncEngine::new(
        context.server_url.clone(),
        context.tenant_id,
        context.session_token.clone(),
    )
    .map_err(|_| "sync failed".to_string())?;
    let mut summary = SyncRunSummary::default();

    let durable_upgrade_block = store.get_setting(SYNC_UPGRADE_REQUIRED_SETTING_KEY)?;
    if durable_upgrade_block
        .as_deref()
        .is_some_and(upgrade_block_is_active)
    {
        return Err("upgrade required".to_string());
    }
    let since = store.get_cursor_seq(SYNC_CURSOR_NAME)?.unwrap_or(0);
    let preflight = match engine.preflight(since).await {
        Ok(preflight) => {
            if durable_upgrade_block.is_some() {
                store.set_setting(SYNC_UPGRADE_REQUIRED_SETTING_KEY, "0:0", now_ms()?)?;
            }
            preflight
        }
        Err(SyncEngineError::UpgradeRequired {
            protocol_version,
            envelope_version,
        }) => {
            store.set_setting(
                SYNC_UPGRADE_REQUIRED_SETTING_KEY,
                &upgrade_block_value(protocol_version, envelope_version),
                now_ms()?,
            )?;
            return Err("upgrade required".to_string());
        }
        Err(_) => return Err("sync failed".to_string()),
    };
    // Initial local rows must have durable outbox protection before any remote
    // absence sweep. This hook is intentionally before key-bundle/entity push.
    pre_push(store)?;

    let ran_full_resync = store.load_full_resync()?.is_some() || preflight.full_resync_required;
    let refreshed_in_full_resync = if ran_full_resync {
        run_full_resync(
            &engine,
            &mut context,
            store,
            now_ms,
            key_refresher,
            &mut summary,
        )
        .await?
    } else {
        false
    };

    // ADR-016: a normal device must reconcile every remote head visible at
    // preflight before it may upload keys or entities. This closes the stale
    // outbox / late-descendant window that existed when push preceded pull.
    let refreshed_in_normal_pull = if !ran_full_resync {
        pull_to_closure(
            &engine,
            &mut context,
            store,
            now_ms,
            key_refresher,
            &mut summary,
        )
        .await?
    } else {
        false
    };

    loop {
        let pending = store
            .list_pending_list_key_bundles(context.tenant_id, KEY_BUNDLE_UPLOAD_BATCH_LIMIT)?;
        if pending.is_empty() {
            break;
        }
        let client = AccountClient::new(context.server_url.clone())
            .map_err(|_| "sync failed".to_string())?;
        for bundle in pending {
            client
                .upsert_list_key_bundle(
                    context.tenant_id,
                    &context.session_token,
                    ListDekBundleDto {
                        list_id: bundle.list_id,
                        wrapped_list_dek: STANDARD.encode(&bundle.wrapped_list_dek),
                    },
                )
                .await
                .map_err(|_| "sync failed".to_string())?;
            let mut transaction = store.begin_write_transaction()?;
            if !transaction.ack_pending_list_key_bundle(
                bundle.tenant_id,
                bundle.list_id,
                &bundle.wrapped_list_dek,
            )? {
                return Err("sync failed".to_string());
            }
            transaction.commit()?;
        }
    }

    // A full resync already retried missing-key records once and classified
    // the remaining failures durably. Replaying them immediately would issue
    // the same key refresh twice in one run without any new server state.
    if !store.list_replayable_quarantine(None, 1)?.is_empty() {
        if !refreshed_in_full_resync
            && !refreshed_in_normal_pull
            && !store.list_replayable_quarantine(None, 1)?.is_empty()
        {
            context.keys = key_refresher.refresh().await?;
        }
        if let Err(error) = replay_quarantine(&context, store, now_ms, &mut summary) {
            if let Some(envelope_version) = replay_upgrade_version(&error) {
                store.set_setting(
                    SYNC_UPGRADE_REQUIRED_SETTING_KEY,
                    &upgrade_block_value(crate::protocol::SYNC_PROTOCOL_VERSION, envelope_version),
                    now_ms()?,
                )?;
                return Err("upgrade required".to_string());
            }
            return Err(error);
        }
    }

    for _ in 0..MAX_PUSH_DRAIN_ITERATIONS {
        let outbox = store.list_outbox_heads(PUSH_BATCH_LIMIT)?;
        if outbox.is_empty() {
            break;
        }
        summary.pushed_count += outbox.len();
        let revisions = outbox
            .iter()
            .map(|entry| (entry.op_id, entry.revision_hlc.clone()))
            .collect::<HashMap<_, _>>();
        let push_ops = outbox
            .into_iter()
            .map(|entry| PushOp {
                op_id: entry.op_id,
                record_id: entry.record_id,
                collection: entry.collection,
                base_revision_hlc: entry.base_revision_hlc,
                revision_hlc: entry.revision_hlc,
                state: entry.state,
            })
            .collect::<Vec<_>>();
        let push_outcome = engine
            .push_batch(push_ops)
            .await
            .map_err(|_| "sync failed".to_string())?;
        for outcome in push_outcome.outcomes {
            match outcome.status {
                PushStatus::Accepted | PushStatus::NoOp => {
                    let revision_hlc = revisions
                        .get(&outcome.op_id)
                        .ok_or_else(|| "sync failed".to_string())?;
                    let mut transaction = store.begin_write_transaction()?;
                    if transaction.ack_outbox_op(outcome.op_id)? {
                        update_current_revision(
                            &mut transaction,
                            outcome.collection,
                            outcome.record_id,
                            revision_hlc,
                            now_ms,
                        )?;
                        summary.push_acked_count += 1;
                    }
                    transaction.commit()?;
                }
                PushStatus::Superseded => {
                    let current = outcome
                        .current
                        .as_ref()
                        .ok_or_else(|| "sync failed".to_string())?;
                    let mut transaction = store.begin_write_transaction()?;
                    reconcile_nonaccepted_push_in_transaction(
                        current,
                        outcome.op_id,
                        &context,
                        &mut transaction,
                        now_ms,
                        &mut summary,
                    )?;
                    transaction.commit()?;
                    summary.push_superseded_count += 1;
                }
                PushStatus::Conflict => {
                    let current = outcome
                        .current
                        .as_ref()
                        .ok_or_else(|| "sync failed".to_string())?;
                    let mut transaction = store.begin_write_transaction()?;
                    reconcile_nonaccepted_push_in_transaction(
                        current,
                        outcome.op_id,
                        &context,
                        &mut transaction,
                        now_ms,
                        &mut summary,
                    )?;
                    transaction.commit()?;
                    summary.push_conflict_count += 1;
                }
            }
        }
    }

    Ok(summary)
}

async fn pull_to_closure<S, N, R>(
    engine: &SyncEngine,
    context: &mut ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    key_refresher: &mut R,
    summary: &mut SyncRunSummary,
) -> Result<bool, String>
where
    S: LocalSyncAtomicStore,
    N: FnMut() -> Result<i64, String>,
    R: SyncKeyRefresher,
{
    let mut refreshed = false;
    loop {
        let since = store.get_cursor_seq(SYNC_CURSOR_NAME)?.unwrap_or(0);
        let page = engine
            .pull_page(since, 100)
            .await
            .map_err(|_| "sync failed".to_string())?;
        match apply_pull_page(&page, context, store, now_ms, false) {
            Ok(page_summary) => merge_summary(summary, page_summary),
            Err(PageApplyError::MissingKey) => {
                context.keys = key_refresher.refresh().await?;
                refreshed = true;
                if let Err(error) = replay_quarantine(context, store, now_ms, summary) {
                    if let Some(envelope_version) = replay_upgrade_version(&error) {
                        store.set_setting(
                            SYNC_UPGRADE_REQUIRED_SETTING_KEY,
                            &upgrade_block_value(
                                crate::protocol::SYNC_PROTOCOL_VERSION,
                                envelope_version,
                            ),
                            now_ms()?,
                        )?;
                        return Err("upgrade required".to_string());
                    }
                    return Err(error);
                }
                let page_summary = apply_pull_page(&page, context, store, now_ms, true)
                    .map_err(page_apply_error_to_string)?;
                merge_summary(summary, page_summary);
            }
            Err(PageApplyError::UpgradeRequired(envelope_version)) => {
                store.set_setting(
                    SYNC_UPGRADE_REQUIRED_SETTING_KEY,
                    &upgrade_block_value(crate::protocol::SYNC_PROTOCOL_VERSION, envelope_version),
                    now_ms()?,
                )?;
                return Err("upgrade required".to_string());
            }
            Err(error) => return Err(page_apply_error_to_string(error)),
        }
        if !page.has_more {
            let proof = page
                .closure_proof
                .clone()
                .filter(|_| page.reached_closure())
                .ok_or_else(|| "sync failed".to_string())?;
            engine
                .ack_continuity(proof)
                .await
                .map_err(|_| "sync failed".to_string())?;
            return Ok(refreshed);
        }
    }
}

async fn run_full_resync<S, N, R>(
    engine: &SyncEngine,
    context: &mut ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    key_refresher: &mut R,
    summary: &mut SyncRunSummary,
) -> Result<bool, String>
where
    S: LocalSyncAtomicStore,
    N: FnMut() -> Result<i64, String>,
    R: SyncKeyRefresher,
{
    let mut refreshed_keys = false;
    if store
        .load_full_resync()
        .map_err(|_| "sync failed".to_string())?
        .is_none()
    {
        let start = engine
            .begin_full_resync()
            .await
            .map_err(|_| "sync failed".to_string())?;
        let mut transaction = store
            .begin_write_transaction()
            .map_err(|_| "sync failed".to_string())?;
        transaction
            .start_full_resync(Uuid::now_v7(), start.generation, start.base_seq, now_ms()?)
            .map_err(|_| "sync failed".to_string())?;
        transaction
            .commit()
            .map_err(|_| "sync failed".to_string())?;
    }

    loop {
        let progress = store
            .load_full_resync()
            .map_err(|_| "sync failed".to_string())?
            .ok_or_else(|| "sync failed".to_string())?;
        match progress.phase {
            LocalFullResyncPhase::Base => {
                let page = engine
                    .scan_base_page(
                        progress.continuity_generation,
                        progress.base_cursor.as_ref(),
                        FULL_RESYNC_PAGE_LIMIT,
                    )
                    .await
                    .map_err(|_| "sync failed".to_string())?;
                if page.has_more && page.next_cursor.is_none() {
                    return Err("sync failed".to_string());
                }
                let base_complete = !page.has_more;
                let page_updated_at = now_ms()?;
                let apply = apply_full_resync_page(
                    &page.records,
                    context,
                    store,
                    now_ms,
                    false,
                    |transaction| {
                        transaction.advance_full_resync_base(
                            progress.generation_id,
                            page.next_cursor.as_ref(),
                            base_complete,
                            page_updated_at,
                        )
                    },
                );
                let page_summary = match apply {
                    Ok(summary) => summary,
                    Err(PageApplyError::MissingKey) => {
                        context.keys = key_refresher.refresh().await?;
                        refreshed_keys = true;
                        match apply_full_resync_page(
                            &page.records,
                            context,
                            store,
                            now_ms,
                            true,
                            |transaction| {
                                transaction.advance_full_resync_base(
                                    progress.generation_id,
                                    page.next_cursor.as_ref(),
                                    base_complete,
                                    page_updated_at,
                                )
                            },
                        ) {
                            Ok(summary) => summary,
                            Err(PageApplyError::UpgradeRequired(version)) => {
                                persist_full_resync_upgrade_block(store, now_ms, version)?;
                                return Err("upgrade required".to_string());
                            }
                            Err(error) => return Err(page_apply_error_to_string(error)),
                        }
                    }
                    Err(PageApplyError::UpgradeRequired(version)) => {
                        persist_full_resync_upgrade_block(store, now_ms, version)?;
                        return Err("upgrade required".to_string());
                    }
                    Err(error) => return Err(page_apply_error_to_string(error)),
                };
                merge_summary(summary, page_summary);
            }
            LocalFullResyncPhase::Delta => {
                let page = engine
                    .pull_page_for_generation(
                        progress.delta_cursor,
                        FULL_RESYNC_PAGE_LIMIT,
                        Some(progress.continuity_generation),
                    )
                    .await
                    .map_err(|_| "sync failed".to_string())?;
                let reached_closure = page.reached_closure();
                let page_updated_at = now_ms()?;
                let apply = apply_full_resync_page(
                    &page.records,
                    context,
                    store,
                    now_ms,
                    false,
                    |transaction| {
                        transaction.advance_full_resync_delta(
                            progress.generation_id,
                            page.next_since,
                            page_updated_at,
                        )?;
                        if reached_closure {
                            transaction.enter_full_resync_sweep(
                                progress.generation_id,
                                page.high_water,
                                page_updated_at,
                            )?;
                        }
                        Ok(())
                    },
                );
                let page_summary = match apply {
                    Ok(summary) => summary,
                    Err(PageApplyError::MissingKey) => {
                        context.keys = key_refresher.refresh().await?;
                        refreshed_keys = true;
                        match apply_full_resync_page(
                            &page.records,
                            context,
                            store,
                            now_ms,
                            true,
                            |transaction| {
                                transaction.advance_full_resync_delta(
                                    progress.generation_id,
                                    page.next_since,
                                    page_updated_at,
                                )?;
                                if reached_closure {
                                    transaction.enter_full_resync_sweep(
                                        progress.generation_id,
                                        page.high_water,
                                        page_updated_at,
                                    )?;
                                }
                                Ok(())
                            },
                        ) {
                            Ok(summary) => summary,
                            Err(PageApplyError::UpgradeRequired(version)) => {
                                persist_full_resync_upgrade_block(store, now_ms, version)?;
                                return Err("upgrade required".to_string());
                            }
                            Err(error) => return Err(page_apply_error_to_string(error)),
                        }
                    }
                    Err(PageApplyError::UpgradeRequired(version)) => {
                        persist_full_resync_upgrade_block(store, now_ms, version)?;
                        return Err("upgrade required".to_string());
                    }
                    Err(error) => return Err(page_apply_error_to_string(error)),
                };
                merge_summary(summary, page_summary);
            }
            LocalFullResyncPhase::Sweep => {
                let mut transaction = store
                    .begin_write_transaction()
                    .map_err(|_| "sync failed".to_string())?;
                let swept = transaction
                    .sweep_full_resync_batch(
                        progress.generation_id,
                        FULL_RESYNC_SWEEP_BATCH_LIMIT,
                        now_ms()?,
                    )
                    .map_err(|_| "sync failed".to_string())?;
                transaction
                    .commit()
                    .map_err(|_| "sync failed".to_string())?;
                summary.deleted_count += swept.swept_lists + swept.swept_tasks;
                if swept.scanned_records == 0 {
                    let mut transaction = store
                        .begin_write_transaction()
                        .map_err(|_| "sync failed".to_string())?;
                    let high_water = transaction
                        .finalize_full_resync(progress.generation_id, SYNC_CURSOR_NAME, now_ms()?)
                        .map_err(|_| "sync failed".to_string())?;
                    transaction
                        .commit()
                        .map_err(|_| "sync failed".to_string())?;
                    let closure = engine
                        .pull_page_for_generation(
                            high_water,
                            FULL_RESYNC_PAGE_LIMIT,
                            Some(progress.continuity_generation),
                        )
                        .await
                        .map_err(|_| "sync failed".to_string())?;
                    let proof = closure
                        .closure_proof
                        .clone()
                        .filter(|_| closure.reached_closure())
                        .ok_or_else(|| "sync failed".to_string())?;
                    engine
                        .ack_continuity(proof)
                        .await
                        .map_err(|_| "sync failed".to_string())?;
                    return Ok(refreshed_keys);
                }
            }
        }
    }
}

fn persist_full_resync_upgrade_block<S, N>(
    store: &mut S,
    now_ms: &mut N,
    envelope_version: u8,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    store.set_setting(
        SYNC_UPGRADE_REQUIRED_SETTING_KEY,
        &upgrade_block_value(crate::protocol::SYNC_PROTOCOL_VERSION, envelope_version),
        now_ms()?,
    )
}

fn apply_full_resync_page<S, N, F>(
    records: &[PullRecord],
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    quarantine_missing: bool,
    finish: F,
) -> Result<SyncRunSummary, PageApplyError>
where
    S: LocalSyncAtomicStore,
    N: FnMut() -> Result<i64, String>,
    F: FnOnce(&mut S::WriteTransaction) -> Result<(), String>,
{
    let progress = store
        .load_full_resync()
        .map_err(|_| PageApplyError::Hard)?
        .ok_or(PageApplyError::Hard)?;
    let mut transaction = store
        .begin_write_transaction()
        .map_err(|_| PageApplyError::Hard)?;
    let mut page_summary = SyncRunSummary {
        pulled_count: records.len(),
        ..SyncRunSummary::default()
    };
    for record in records {
        let disposition =
            apply_pull_record(record, context, &mut transaction, now_ms, &mut page_summary)
                .map_err(|_| PageApplyError::Hard)?;
        match disposition {
            ApplyDisposition::AppliedCurrent | ApplyDisposition::Rebased => {
                if transaction
                    .delete_quarantine(record.record_id)
                    .map_err(|_| PageApplyError::Hard)?
                {
                    page_summary.resolved_quarantine_count += 1;
                }
            }
            ApplyDisposition::Deferred(reason, required_list_id) => {
                if matches!(
                    reason,
                    PullFailureReason::MissingDek | PullFailureReason::NoMatchingDek
                ) && !quarantine_missing
                {
                    return Err(PageApplyError::MissingKey);
                }
                let failed_at = now_ms().map_err(|_| PageApplyError::Hard)?;
                transaction
                    .put_quarantine(LocalSyncQuarantineEntry {
                        record_id: record.record_id,
                        collection: record.collection,
                        seq: record.seq,
                        revision_hlc: record.revision_hlc.clone(),
                        state: record.state.clone(),
                        reason,
                        required_list_id,
                        first_failed_at: failed_at,
                        last_failed_at: failed_at,
                        attempt_count: 1,
                    })
                    .map_err(|_| PageApplyError::Hard)?;
                page_summary.decrypt_failed_count += 1;
                if matches!(
                    reason,
                    PullFailureReason::MissingDek | PullFailureReason::NoMatchingDek
                ) {
                    page_summary.missing_key_quarantined_count += 1;
                } else {
                    page_summary.corruption_quarantined_count += 1;
                }
            }
            ApplyDisposition::UpgradeRequired(version) => {
                return Err(PageApplyError::UpgradeRequired(version));
            }
        }
        // Server presence is independent of decrypt/quarantine success.
        transaction
            .mark_full_resync_record(progress.generation_id, record.collection, record.record_id)
            .map_err(|_| PageApplyError::Hard)?;
    }
    finish(&mut transaction).map_err(|_| PageApplyError::Hard)?;
    transaction.commit().map_err(|_| PageApplyError::Hard)?;
    Ok(page_summary)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PageApplyError {
    MissingKey,
    UpgradeRequired(u8),
    Hard,
}

fn page_apply_error_to_string(error: PageApplyError) -> String {
    match error {
        PageApplyError::UpgradeRequired(_) => "upgrade required".to_string(),
        PageApplyError::MissingKey | PageApplyError::Hard => "sync failed".to_string(),
    }
}

fn merge_summary(target: &mut SyncRunSummary, page: SyncRunSummary) {
    target.pulled_count += page.pulled_count;
    target.applied_count += page.applied_count;
    target.deleted_count += page.deleted_count;
    target.decrypt_failed_count += page.decrypt_failed_count;
    target.repush_count += page.repush_count;
    target.missing_key_quarantined_count += page.missing_key_quarantined_count;
    target.corruption_quarantined_count += page.corruption_quarantined_count;
    target.resolved_quarantine_count += page.resolved_quarantine_count;
}

fn apply_pull_page<S, N>(
    page: &crate::DeltaPage,
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    quarantine_missing: bool,
) -> Result<SyncRunSummary, PageApplyError>
where
    S: LocalSyncAtomicStore,
    N: FnMut() -> Result<i64, String>,
{
    let mut transaction = store
        .begin_write_transaction()
        .map_err(|_| PageApplyError::Hard)?;
    let mut page_summary = SyncRunSummary {
        pulled_count: page.records.len(),
        ..SyncRunSummary::default()
    };
    for record in &page.records {
        let disposition =
            apply_pull_record(record, context, &mut transaction, now_ms, &mut page_summary)
                .map_err(|_| PageApplyError::Hard)?;
        match disposition {
            ApplyDisposition::AppliedCurrent | ApplyDisposition::Rebased => {
                if transaction
                    .delete_quarantine(record.record_id)
                    .map_err(|_| PageApplyError::Hard)?
                {
                    page_summary.resolved_quarantine_count += 1;
                }
            }
            ApplyDisposition::Deferred(reason, required_list_id) => {
                if matches!(
                    reason,
                    PullFailureReason::MissingDek | PullFailureReason::NoMatchingDek
                ) && !quarantine_missing
                {
                    return Err(PageApplyError::MissingKey);
                }
                let failed_at = now_ms().map_err(|_| PageApplyError::Hard)?;
                transaction
                    .put_quarantine(LocalSyncQuarantineEntry {
                        record_id: record.record_id,
                        collection: record.collection,
                        seq: record.seq,
                        revision_hlc: record.revision_hlc.clone(),
                        state: record.state.clone(),
                        reason,
                        required_list_id,
                        first_failed_at: failed_at,
                        last_failed_at: failed_at,
                        attempt_count: 1,
                    })
                    .map_err(|_| PageApplyError::Hard)?;
                page_summary.decrypt_failed_count += 1;
                if matches!(
                    reason,
                    PullFailureReason::MissingDek | PullFailureReason::NoMatchingDek
                ) {
                    page_summary.missing_key_quarantined_count += 1;
                } else {
                    page_summary.corruption_quarantined_count += 1;
                }
            }
            ApplyDisposition::UpgradeRequired(version) => {
                return Err(PageApplyError::UpgradeRequired(version));
            }
        }
    }
    transaction
        .set_cursor(
            SYNC_CURSOR_NAME,
            page.next_since,
            now_ms().map_err(|_| PageApplyError::Hard)?,
        )
        .map_err(|_| PageApplyError::Hard)?;
    transaction.commit().map_err(|_| PageApplyError::Hard)?;
    Ok(page_summary)
}

fn replay_quarantine<S, N>(
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    summary: &mut SyncRunSummary,
) -> Result<(), String>
where
    S: LocalSyncAtomicStore,
    N: FnMut() -> Result<i64, String>,
{
    let mut after = None;
    loop {
        let entries = store.list_replayable_quarantine(after, QUARANTINE_REPLAY_BATCH_LIMIT)?;
        if entries.is_empty() {
            break;
        }
        let page_len = entries.len();
        for entry in entries {
            after = Some((entry.seq, entry.record_id));
            let record = PullRecord {
                record_id: entry.record_id,
                collection: entry.collection,
                seq: entry.seq,
                revision_hlc: entry.revision_hlc,
                state: entry.state,
            };
            let mut transaction = store.begin_write_transaction()?;
            let mut replay_summary = SyncRunSummary::default();
            match apply_pull_record(
                &record,
                context,
                &mut transaction,
                now_ms,
                &mut replay_summary,
            )? {
                ApplyDisposition::AppliedCurrent | ApplyDisposition::Rebased => {
                    transaction.delete_quarantine(record.record_id)?;
                    transaction.commit()?;
                    replay_summary.resolved_quarantine_count += 1;
                    merge_summary(summary, replay_summary);
                }
                ApplyDisposition::Deferred(reason, required_list_id) => {
                    let failed_at = now_ms()?;
                    transaction.put_quarantine(LocalSyncQuarantineEntry {
                        record_id: record.record_id,
                        collection: record.collection,
                        seq: record.seq,
                        revision_hlc: record.revision_hlc,
                        state: record.state,
                        reason,
                        required_list_id,
                        first_failed_at: failed_at,
                        last_failed_at: failed_at,
                        attempt_count: 1,
                    })?;
                    transaction.commit()?;
                }
                ApplyDisposition::UpgradeRequired(version) => {
                    return Err(format!("upgrade required:{version}"));
                }
            }
        }
        if page_len < QUARANTINE_REPLAY_BATCH_LIMIT {
            break;
        }
    }
    Ok(())
}

fn update_current_revision<S, N>(
    store: &mut S,
    collection: SyncCollection,
    record_id: Uuid,
    revision_hlc: &str,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let Some(mut state) = store.get_record_state(collection, record_id)? else {
        return Err("sync failed".to_string());
    };
    state.current_revision_hlc = Some(revision_hlc.to_string());
    store.put_record_state(collection, record_id, state, now_ms()?)
}

fn reconcile_nonaccepted_push_in_transaction<S, N>(
    current: &PullRecord,
    stale_op_id: Uuid,
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    summary: &mut SyncRunSummary,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    if !store.ack_outbox_op(stale_op_id)? {
        return Ok(());
    }
    match apply_pull_record(current, context, store, now_ms, summary)? {
        ApplyDisposition::AppliedCurrent | ApplyDisposition::Rebased => Ok(()),
        ApplyDisposition::Deferred(_, _) | ApplyDisposition::UpgradeRequired(_) => {
            Err("sync failed".to_string())
        }
    }
}

fn apply_pull_record<S, N>(
    record: &PullRecord,
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    summary: &mut SyncRunSummary,
) -> Result<ApplyDisposition, String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    match record.collection {
        SyncCollection::Lists => apply_pull_list(record, context, store, now_ms, summary),
        SyncCollection::Tasks => apply_pull_task(record, context, store, now_ms, summary),
        SyncCollection::TimerSessions => Ok(ApplyDisposition::Deferred(
            PullFailureReason::InvalidPlaintext,
            None,
        )),
    }
}

fn apply_pull_list<S, N>(
    record: &PullRecord,
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    summary: &mut SyncRunSummary,
) -> Result<ApplyDisposition, String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    observe_remote_hlc(store, &context.device_id, &record.revision_hlc, now_ms)?;
    let local_state = store.get_record_state(SyncCollection::Lists, record.record_id)?;
    let (incoming_mutation_hlc, blob) = match &record.state {
        EncryptedSyncState::Tombstone { delete_hlc } => {
            store.delete_outbox_head(SyncCollection::Lists, record.record_id)?;
            let known_tasks = store.list_tasks_by_list_for_sync(record.record_id)?;
            for task in &known_tasks {
                store.delete_outbox_head(SyncCollection::Tasks, task.id)?;
                let base_revision = store
                    .get_record_state(SyncCollection::Tasks, task.id)?
                    .and_then(|state| state.current_revision_hlc);
                enqueue_rebased_tombstone(
                    store,
                    RebaseTombstoneRequest {
                        record_id: task.id,
                        collection: SyncCollection::Tasks,
                        delete_hlc,
                        device_id: &context.device_id,
                        base_revision_hlc: base_revision.as_deref(),
                    },
                    now_ms,
                )?;
            }
            let deleted = store.delete_list_with_tasks_for_sync(record.record_id)?;
            summary.deleted_count += 1 + deleted;
            store.put_record_state(
                SyncCollection::Lists,
                record.record_id,
                LocalSyncRecordState {
                    current_revision_hlc: Some(record.revision_hlc.clone()),
                    state: LocalSyncSemanticState::Tombstone {
                        delete_hlc: delete_hlc.clone(),
                    },
                },
                now_ms()?,
            )?;
            return Ok(ApplyDisposition::AppliedCurrent);
        }
        EncryptedSyncState::Live { mutation_hlc, blob } => {
            if let Some(LocalSyncRecordState {
                state: LocalSyncSemanticState::Tombstone { delete_hlc },
                ..
            }) = local_state.as_ref()
            {
                if compare_encoded_hlc(delete_hlc, mutation_hlc)? != std::cmp::Ordering::Less {
                    enqueue_rebased_tombstone(
                        store,
                        RebaseTombstoneRequest {
                            record_id: record.record_id,
                            collection: SyncCollection::Lists,
                            delete_hlc,
                            device_id: &context.device_id,
                            base_revision_hlc: Some(&record.revision_hlc),
                        },
                        now_ms,
                    )?;
                    summary.repush_count += 1;
                    return Ok(ApplyDisposition::Rebased);
                }
            }
            (mutation_hlc, blob)
        }
    };
    let Some(dek) = dek_for_list(&context.keys, record.record_id) else {
        return Ok(ApplyDisposition::Deferred(
            PullFailureReason::MissingDek,
            Some(record.record_id),
        ));
    };
    let incoming = decrypt_plaintext(&dek, LISTS_COLLECTION, &record.record_id.to_string(), blob);
    let incoming = match incoming {
        Ok(incoming) => incoming,
        Err(error) => {
            return Ok(classify_envelope_error(
                error,
                Some(record.record_id),
                blob.first().copied().unwrap_or(0),
            ));
        }
    };
    let existing = store.get_list(record.record_id)?;
    let stored_plaintext = stored_sync_plaintext(store, SyncCollection::Lists, record.record_id)?;
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
    store_sync_plaintext(
        store,
        SyncCollection::Lists,
        record.record_id,
        &record.revision_hlc,
        incoming_mutation_hlc,
        &merged,
        now_ms,
    )?;
    summary.applied_count += 1;
    if needs_repush {
        enqueue_merged_plaintext(
            store,
            RebasePlaintextRequest {
                record_id: record.record_id,
                collection: SyncCollection::Lists,
                plaintext: &merged,
                dek: &dek,
                device_id: &context.device_id,
                base_revision_hlc: &record.revision_hlc,
            },
            now_ms,
        )?;
        summary.repush_count += 1;
    }
    Ok(if needs_repush {
        ApplyDisposition::Rebased
    } else {
        ApplyDisposition::AppliedCurrent
    })
}

fn apply_pull_task<S, N>(
    record: &PullRecord,
    context: &ActiveSyncContext,
    store: &mut S,
    now_ms: &mut N,
    summary: &mut SyncRunSummary,
) -> Result<ApplyDisposition, String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    observe_remote_hlc(store, &context.device_id, &record.revision_hlc, now_ms)?;
    let existing = store.get_task(record.record_id)?;
    let local_state = store.get_record_state(SyncCollection::Tasks, record.record_id)?;
    let (incoming_mutation_hlc, _blob) = match &record.state {
        EncryptedSyncState::Tombstone { delete_hlc } => {
            store.delete_outbox_head(SyncCollection::Tasks, record.record_id)?;
            let deleted = store.delete_task_subtree_for_sync(record.record_id)?;
            summary.deleted_count += deleted;
            store.put_record_state(
                SyncCollection::Tasks,
                record.record_id,
                LocalSyncRecordState {
                    current_revision_hlc: Some(record.revision_hlc.clone()),
                    state: LocalSyncSemanticState::Tombstone {
                        delete_hlc: delete_hlc.clone(),
                    },
                },
                now_ms()?,
            )?;
            return Ok(ApplyDisposition::AppliedCurrent);
        }
        EncryptedSyncState::Live { mutation_hlc, blob } => {
            if let Some(LocalSyncRecordState {
                state: LocalSyncSemanticState::Tombstone { delete_hlc },
                ..
            }) = local_state.as_ref()
            {
                if compare_encoded_hlc(delete_hlc, mutation_hlc)? != std::cmp::Ordering::Less {
                    enqueue_rebased_tombstone(
                        store,
                        RebaseTombstoneRequest {
                            record_id: record.record_id,
                            collection: SyncCollection::Tasks,
                            delete_hlc,
                            device_id: &context.device_id,
                            base_revision_hlc: Some(&record.revision_hlc),
                        },
                        now_ms,
                    )?;
                    summary.repush_count += 1;
                    return Ok(ApplyDisposition::Rebased);
                }
            }
            (mutation_hlc, blob)
        }
    };
    let incoming = match decrypt_task_plaintext(record, existing.as_ref(), &context.keys) {
        Ok(incoming) => incoming,
        Err(disposition) => return Ok(disposition),
    };
    let incoming_list_id = match &incoming {
        SyncPlaintext::Task(task) => task.placement.value.list_id,
        SyncPlaintext::List(_) | SyncPlaintext::TimerSession(_) => {
            return Err("sync failed".to_string())
        }
    };
    let dek = if let Some(incoming_dek) = dek_for_list(&context.keys, incoming_list_id) {
        incoming_dek
    } else {
        return Ok(ApplyDisposition::Deferred(
            PullFailureReason::MissingDek,
            Some(incoming_list_id),
        ));
    };
    let stored_plaintext = stored_sync_plaintext(store, SyncCollection::Tasks, record.record_id)?;
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
    let dependency = task_dependency_disposition(store, &task)?;
    if matches!(dependency, TaskDependencyDisposition::Missing)
        && store.load_full_resync()?.is_some()
    {
        return Ok(ApplyDisposition::Deferred(
            PullFailureReason::MissingDependency,
            Some(task.list_id),
        ));
    }
    if let TaskDependencyDisposition::Deleted(delete_hlc) = dependency {
        store.delete_outbox_head(SyncCollection::Tasks, record.record_id)?;
        let deleted = store.delete_task_subtree_for_sync(record.record_id)?;
        summary.deleted_count += deleted;
        enqueue_rebased_tombstone(
            store,
            RebaseTombstoneRequest {
                record_id: record.record_id,
                collection: SyncCollection::Tasks,
                delete_hlc: &delete_hlc,
                device_id: &context.device_id,
                base_revision_hlc: Some(&record.revision_hlc),
            },
            now_ms,
        )?;
        summary.repush_count += 1;
        return Ok(ApplyDisposition::Rebased);
    }
    if matches!(dependency, TaskDependencyDisposition::Missing) {
        let delete_hlc = record.revision_hlc.clone();
        store.delete_outbox_head(SyncCollection::Tasks, record.record_id)?;
        let deleted = store.delete_task_subtree_for_sync(record.record_id)?;
        summary.deleted_count += deleted;
        enqueue_rebased_tombstone(
            store,
            RebaseTombstoneRequest {
                record_id: record.record_id,
                collection: SyncCollection::Tasks,
                delete_hlc: &delete_hlc,
                device_id: &context.device_id,
                base_revision_hlc: Some(&record.revision_hlc),
            },
            now_ms,
        )?;
        summary.repush_count += 1;
        return Ok(ApplyDisposition::Rebased);
    }
    store.upsert_task_for_sync(task)?;
    store_sync_plaintext(
        store,
        SyncCollection::Tasks,
        record.record_id,
        &record.revision_hlc,
        incoming_mutation_hlc,
        &merged,
        now_ms,
    )?;
    summary.applied_count += 1;
    if needs_repush {
        enqueue_merged_plaintext(
            store,
            RebasePlaintextRequest {
                record_id: record.record_id,
                collection: SyncCollection::Tasks,
                plaintext: &merged,
                dek: &dek,
                device_id: &context.device_id,
                base_revision_hlc: &record.revision_hlc,
            },
            now_ms,
        )?;
        summary.repush_count += 1;
    }
    Ok(if needs_repush {
        ApplyDisposition::Rebased
    } else {
        ApplyDisposition::AppliedCurrent
    })
}

fn task_dependency_disposition<S>(
    store: &mut S,
    task: &Task,
) -> Result<TaskDependencyDisposition, String>
where
    S: LocalSyncStore,
{
    if let Some(LocalSyncRecordState {
        state: LocalSyncSemanticState::Tombstone { delete_hlc },
        ..
    }) = store.get_record_state(SyncCollection::Lists, task.list_id)?
    {
        return Ok(TaskDependencyDisposition::Deleted(delete_hlc));
    }
    if store.get_list(task.list_id)?.is_none() {
        return Ok(TaskDependencyDisposition::Missing);
    }

    let mut parent_id = task.parent_task_id;
    let mut visited = HashSet::new();
    while let Some(id) = parent_id {
        if !visited.insert(id) {
            return Ok(TaskDependencyDisposition::Missing);
        }
        if let Some(LocalSyncRecordState {
            state: LocalSyncSemanticState::Tombstone { delete_hlc },
            ..
        }) = store.get_record_state(SyncCollection::Tasks, id)?
        {
            return Ok(TaskDependencyDisposition::Deleted(delete_hlc));
        }
        let Some(parent) = store.get_task(id)? else {
            return Ok(TaskDependencyDisposition::Missing);
        };
        if parent.list_id != task.list_id {
            return Ok(TaskDependencyDisposition::Missing);
        }
        parent_id = parent.parent_task_id;
    }
    Ok(TaskDependencyDisposition::Valid)
}

fn stored_sync_plaintext<S>(
    store: &mut S,
    collection: SyncCollection,
    record_id: Uuid,
) -> Result<Option<SyncPlaintext>, String>
where
    S: LocalSyncStore,
{
    match store.get_record_state(collection, record_id)? {
        Some(LocalSyncRecordState {
            state: LocalSyncSemanticState::Live { plaintext_json, .. },
            ..
        }) => {
            let plaintext: SyncPlaintext =
                serde_json::from_str(&plaintext_json).map_err(|_| "sync failed".to_string())?;
            plaintext
                .validate_for_collection(collection.as_str(), &record_id.to_string())
                .map_err(|_| "sync failed".to_string())?;
            Ok(Some(plaintext))
        }
        Some(LocalSyncRecordState {
            state: LocalSyncSemanticState::Tombstone { .. },
            ..
        })
        | None => Ok(None),
    }
}

fn store_sync_plaintext<S, N>(
    store: &mut S,
    collection: SyncCollection,
    record_id: Uuid,
    current_revision_hlc: &str,
    incoming_mutation_hlc: &str,
    plaintext: &SyncPlaintext,
    now_ms: &mut N,
) -> Result<(), String>
where
    S: LocalSyncStore,
    N: FnMut() -> Result<i64, String>,
{
    let plaintext_json = serde_json::to_string(plaintext).map_err(|_| "sync failed".to_string())?;
    let merged_mutation_hlc = plaintext
        .record_hlc()
        .encode()
        .map_err(|_| "sync failed".to_string())?;
    let mutation_hlc = if compare_encoded_hlc(&merged_mutation_hlc, incoming_mutation_hlc)?
        == std::cmp::Ordering::Less
    {
        incoming_mutation_hlc.to_string()
    } else {
        merged_mutation_hlc
    };
    store.put_record_state(
        collection,
        record_id,
        LocalSyncRecordState {
            current_revision_hlc: Some(current_revision_hlc.to_string()),
            state: LocalSyncSemanticState::Live {
                mutation_hlc,
                plaintext_json,
            },
        },
        now_ms()?,
    )
}

fn compare_encoded_hlc(left: &str, right: &str) -> Result<std::cmp::Ordering, String> {
    let left = Hlc::decode(left).map_err(|_| "sync failed".to_string())?;
    let right = Hlc::decode(right).map_err(|_| "sync failed".to_string())?;
    Ok(left.cmp(&right))
}

fn decrypt_task_plaintext(
    record: &PullRecord,
    existing: Option<&Task>,
    keys: &LocalSyncKeys,
) -> Result<SyncPlaintext, ApplyDisposition> {
    let EncryptedSyncState::Live { blob, .. } = &record.state else {
        return Err(ApplyDisposition::Deferred(
            PullFailureReason::CorruptEnvelope,
            None,
        ));
    };
    if blob.is_empty() || blob.len() > crate::MAX_ENCRYPTED_BLOB_LEN {
        return Err(ApplyDisposition::Deferred(
            PullFailureReason::CorruptEnvelope,
            None,
        ));
    }
    if blob[0] != crate::ENVELOPE_VERSION {
        return Err(ApplyDisposition::UpgradeRequired(blob[0]));
    }
    let mut candidates = Vec::new();
    let mut expected_list_id = None;
    let mut expected_dek_available = false;
    if let Some(task) = existing {
        expected_list_id = Some(task.list_id);
        if let Some(dek) = dek_for_list(keys, task.list_id) {
            expected_dek_available = true;
            candidates.push((task.list_id, dek));
        }
    }
    for (list_id, dek) in &keys.list_deks {
        if !candidates
            .iter()
            .any(|(candidate_list_id, _)| candidate_list_id == list_id)
        {
            candidates.push((*list_id, *dek));
        }
    }
    if candidates.is_empty() {
        return Err(ApplyDisposition::Deferred(
            if expected_list_id.is_some() {
                PullFailureReason::MissingDek
            } else {
                PullFailureReason::NoMatchingDek
            },
            expected_list_id,
        ));
    }
    let mut invalid_plaintext = false;
    for (candidate_list_id, dek) in candidates {
        match decrypt_plaintext(&dek, TASKS_COLLECTION, &record.record_id.to_string(), blob) {
            Ok(plaintext) => {
                let SyncPlaintext::Task(task) = &plaintext else {
                    invalid_plaintext = true;
                    continue;
                };
                if task.placement.value.list_id == candidate_list_id {
                    return Ok(plaintext);
                }
            }
            Err(EnvelopeError::UnsupportedVersion) => {
                return Err(ApplyDisposition::UpgradeRequired(blob[0]))
            }
            Err(EnvelopeError::Deserialization | EnvelopeError::Serialization) => {
                invalid_plaintext = true;
            }
            Err(_) => {}
        }
    }
    if !expected_dek_available && expected_list_id.is_some() {
        Err(ApplyDisposition::Deferred(
            PullFailureReason::MissingDek,
            expected_list_id,
        ))
    } else if invalid_plaintext {
        Err(ApplyDisposition::Deferred(
            PullFailureReason::InvalidPlaintext,
            expected_list_id,
        ))
    } else if expected_list_id.is_some() {
        Err(ApplyDisposition::Deferred(
            PullFailureReason::AuthenticationFailed,
            expected_list_id,
        ))
    } else {
        Err(ApplyDisposition::Deferred(
            PullFailureReason::NoMatchingDek,
            None,
        ))
    }
}

fn classify_envelope_error(
    error: EnvelopeError,
    required_list_id: Option<Uuid>,
    envelope_version: u8,
) -> ApplyDisposition {
    match error {
        EnvelopeError::UnsupportedVersion => ApplyDisposition::UpgradeRequired(envelope_version),
        EnvelopeError::Crypto(_) => {
            ApplyDisposition::Deferred(PullFailureReason::AuthenticationFailed, required_list_id)
        }
        EnvelopeError::Deserialization | EnvelopeError::Serialization => {
            ApplyDisposition::Deferred(PullFailureReason::InvalidPlaintext, required_list_id)
        }
        EnvelopeError::EmptyBlob | EnvelopeError::BlobTooLarge => {
            ApplyDisposition::Deferred(PullFailureReason::CorruptEnvelope, required_list_id)
        }
    }
}

fn upgrade_block_value(protocol_version: u16, envelope_version: u8) -> String {
    format!("{protocol_version}:{envelope_version}")
}

fn upgrade_block_is_active(value: &str) -> bool {
    let Some((protocol, envelope)) = value.split_once(':') else {
        return true;
    };
    let (Ok(protocol), Ok(envelope)) = (protocol.parse::<u16>(), envelope.parse::<u8>()) else {
        return true;
    };
    crate::protocol::SYNC_PROTOCOL_VERSION < protocol || crate::ENVELOPE_VERSION < envelope
}

fn replay_upgrade_version(error: &str) -> Option<u8> {
    error
        .strip_prefix("upgrade required:")
        .and_then(|value| value.parse().ok())
}

fn record_hlc_or_initial(plaintext: &SyncPlaintext) -> Hlc {
    plaintext.record_hlc().clone()
}

fn task_from_plaintext<N>(
    id: Uuid,
    _existing: Option<&Task>,
    plaintext: &SyncPlaintext,
    _now_ms: &mut N,
) -> Result<Task, String>
where
    N: FnMut() -> Result<i64, String>,
{
    plaintext
        .validate_for_collection(TASKS_COLLECTION, &id.to_string())
        .map_err(|_| "sync failed".to_string())?;
    let SyncPlaintext::Task(fields) = plaintext else {
        return Err("sync failed".to_string());
    };
    Ok(Task {
        id,
        list_id: fields.placement.value.list_id,
        parent_task_id: fields.placement.value.parent_task_id,
        title: fields.title.value.clone(),
        note: fields.note.value.clone(),
        status: fields.completion.value.status,
        priority: fields.priority.value,
        due: fields.due.value.clone(),
        scheduled_at: fields.scheduled_at.value,
        estimated_minutes: fields.estimated_minutes.value,
        sort_order: fields.placement.value.rank.clone(),
        completed_at: fields.completion.value.completed_at,
        closed_reason: fields.completion.value.closed_reason.clone(),
        deleted_at: None,
        assignee: fields.assignee.value,
        created_at: fields.created_at.value,
        updated_at: fields.updated_at.value,
    })
}

fn list_from_plaintext<N>(
    id: Uuid,
    _existing: Option<&List>,
    plaintext: &SyncPlaintext,
    _now_ms: &mut N,
) -> Result<List, String>
where
    N: FnMut() -> Result<i64, String>,
{
    plaintext
        .validate_for_collection(LISTS_COLLECTION, &id.to_string())
        .map_err(|_| "sync failed".to_string())?;
    let SyncPlaintext::List(fields) = plaintext else {
        return Err("sync failed".to_string());
    };
    Ok(List {
        id,
        name: fields.name.value.clone(),
        color: fields.color.value.clone(),
        icon: fields.icon.value.clone(),
        org_id: fields.org_id.value,
        sort_order: fields.placement.value.rank.clone(),
        is_default: fields.is_default.value,
        archived_at: fields.archived_at.value,
        created_at: fields.created_at.value,
        updated_at: fields.updated_at.value,
    })
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use todori_crypto::key_hierarchy::KEY_LEN;
    use todori_domain::new_task;

    use super::*;
    use crate::{
        encrypt_plaintext, LocalMutationSyncStore, LocalSyncOutboxEntry, NewLocalSyncOutboxEntry,
    };

    #[derive(Default)]
    struct FakeStore {
        lists: HashMap<Uuid, List>,
        tasks: HashMap<Uuid, Task>,
        record_states: HashMap<(SyncCollection, Uuid), LocalSyncRecordState>,
        outbox: Vec<LocalSyncOutboxEntry>,
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

    impl LocalSyncStore for FakeStore {
        fn list_outbox_heads(&mut self, limit: usize) -> Result<Vec<LocalSyncOutboxEntry>, String> {
            Ok(self.outbox.iter().take(limit).cloned().collect())
        }

        fn ack_outbox_op(&mut self, op_id: Uuid) -> Result<bool, String> {
            let previous_len = self.outbox.len();
            self.outbox.retain(|entry| entry.op_id != op_id);
            Ok(previous_len != self.outbox.len())
        }

        fn delete_outbox_head(
            &mut self,
            collection: SyncCollection,
            record_id: Uuid,
        ) -> Result<bool, String> {
            let previous_len = self.outbox.len();
            self.outbox
                .retain(|entry| entry.collection != collection || entry.record_id != record_id);
            Ok(previous_len != self.outbox.len())
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
            let previous = self.tasks.len();
            self.tasks.retain(|_, task| task.list_id != list_id);
            Ok(previous - self.tasks.len())
        }

        fn get_task(&mut self, id: Uuid) -> Result<Option<Task>, String> {
            Ok(self.tasks.get(&id).cloned())
        }

        fn list_tasks_by_list_for_sync(&mut self, list_id: Uuid) -> Result<Vec<Task>, String> {
            Ok(self
                .tasks
                .values()
                .filter(|task| task.list_id == list_id)
                .cloned()
                .collect())
        }

        fn upsert_task_for_sync(&mut self, task: Task) -> Result<(), String> {
            self.tasks.insert(task.id, task);
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
            stored_sync_plaintext(&mut store, SyncCollection::Lists, incoming_list.id).unwrap();
        let SyncPlaintext::List(stored) = stored_plaintext.unwrap() else {
            panic!("list");
        };
        assert!(stored.is_default.value);
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

    #[test]
    fn remote_tombstone_discards_newer_local_live_and_outbox() {
        let list_id = uuid(30);
        let local = sample_list(list_id, false);
        let local_hlc = Hlc {
            wall_ms: 1_799_000_000_500,
            counter: 0,
            device_id: "local".to_string(),
        }
        .encode()
        .unwrap();
        let delete_hlc = Hlc {
            wall_ms: 1_799_000_000_100,
            counter: 0,
            device_id: "remote".to_string(),
        }
        .encode()
        .unwrap();
        let revision_hlc = Hlc {
            wall_ms: 1_799_000_000_600,
            counter: 0,
            device_id: "remote".to_string(),
        }
        .encode()
        .unwrap();
        let mut store = FakeStore::default();
        store.lists.insert(list_id, local.clone());
        store.record_states.insert(
            (SyncCollection::Lists, list_id),
            LocalSyncRecordState {
                current_revision_hlc: Some(local_hlc.clone()),
                state: LocalSyncSemanticState::Live {
                    mutation_hlc: local_hlc.clone(),
                    plaintext_json: serde_json::to_string(&list_plaintext(
                        &local,
                        Hlc::decode(&local_hlc).unwrap(),
                    ))
                    .unwrap(),
                },
            },
        );
        store.outbox.push(LocalSyncOutboxEntry {
            op_id: Uuid::now_v7(),
            record_id: list_id,
            collection: SyncCollection::Lists,
            base_revision_hlc: Some(local_hlc.clone()),
            revision_hlc: local_hlc,
            state: EncryptedSyncState::Live {
                mutation_hlc: Hlc::decode(&revision_hlc).unwrap().encode().unwrap(),
                blob: vec![1],
            },
            created_at: 1,
        });
        let record = PullRecord {
            record_id: list_id,
            collection: SyncCollection::Lists,
            seq: 2,
            revision_hlc: revision_hlc.clone(),
            state: EncryptedSyncState::Tombstone {
                delete_hlc: delete_hlc.clone(),
            },
        };
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        apply_pull_list(
            &record,
            &context_for(list_id, [3; KEY_LEN]),
            &mut store,
            &mut now,
            &mut summary,
        )
        .unwrap();

        assert!(!store.lists.contains_key(&list_id));
        assert!(store.outbox.is_empty());
        assert_eq!(
            store.record_states[&(SyncCollection::Lists, list_id)],
            LocalSyncRecordState {
                current_revision_hlc: Some(revision_hlc),
                state: LocalSyncSemanticState::Tombstone { delete_hlc },
            }
        );
        assert_eq!(summary.repush_count, 0);
    }

    #[test]
    fn remote_list_tombstone_replaces_known_descendant_live_outbox_with_tombstone() {
        let list_id = uuid(33);
        let list = sample_list(list_id, false);
        let task = new_task(
            list_id,
            None,
            "known descendant".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            1_799_000_000_000,
        )
        .unwrap();
        let current_revision = Hlc {
            wall_ms: 1_799_000_000_100,
            counter: 0,
            device_id: "local".to_string(),
        }
        .encode()
        .unwrap();
        let delete_hlc = Hlc {
            wall_ms: 1_799_000_000_200,
            counter: 0,
            device_id: "remote".to_string(),
        }
        .encode()
        .unwrap();
        let mut store = FakeStore::default();
        store.lists.insert(list_id, list);
        store.tasks.insert(task.id, task.clone());
        store.record_states.insert(
            (SyncCollection::Tasks, task.id),
            LocalSyncRecordState {
                current_revision_hlc: Some(current_revision.clone()),
                state: LocalSyncSemanticState::Live {
                    mutation_hlc: current_revision.clone(),
                    plaintext_json: serde_json::to_string(&task_plaintext(
                        &task,
                        Hlc::decode(&current_revision).unwrap(),
                    ))
                    .unwrap(),
                },
            },
        );
        store.outbox.push(LocalSyncOutboxEntry {
            op_id: Uuid::now_v7(),
            record_id: task.id,
            collection: SyncCollection::Tasks,
            base_revision_hlc: Some(current_revision.clone()),
            revision_hlc: current_revision,
            state: EncryptedSyncState::Live {
                mutation_hlc: delete_hlc.clone(),
                blob: vec![1],
            },
            created_at: 1,
        });
        let record = PullRecord {
            record_id: list_id,
            collection: SyncCollection::Lists,
            seq: 3,
            revision_hlc: delete_hlc.clone(),
            state: EncryptedSyncState::Tombstone {
                delete_hlc: delete_hlc.clone(),
            },
        };
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        apply_pull_list(
            &record,
            &context_for(list_id, [5; KEY_LEN]),
            &mut store,
            &mut now,
            &mut summary,
        )
        .unwrap();

        assert!(!store.tasks.contains_key(&task.id));
        assert_eq!(store.outbox.len(), 1);
        assert_eq!(store.outbox[0].record_id, task.id);
        assert!(matches!(
            store.outbox[0].state,
            EncryptedSyncState::Tombstone { .. }
        ));
    }

    #[test]
    fn late_descendant_of_tombstoned_list_is_not_materialized_and_cascades() {
        let list_id = uuid(31);
        let task_id = uuid(32);
        let dek = [4; KEY_LEN];
        let task = new_task(
            list_id,
            None,
            "late".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            1_799_000_000_000,
        )
        .unwrap();
        let mut task = task;
        task.id = task_id;
        let hlc = Hlc {
            wall_ms: 1_799_000_000_200,
            counter: 0,
            device_id: "remote".to_string(),
        };
        let plaintext = task_plaintext(&task, hlc.clone());
        let record = encrypted_task_record(task_id, &plaintext, &dek, &hlc);
        let mut store = FakeStore::default();
        store.record_states.insert(
            (SyncCollection::Lists, list_id),
            LocalSyncRecordState {
                current_revision_hlc: Some(record.revision_hlc.clone()),
                state: LocalSyncSemanticState::Tombstone {
                    delete_hlc: record.revision_hlc.clone(),
                },
            },
        );
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        apply_pull_task(
            &record,
            &context_for(list_id, dek),
            &mut store,
            &mut now,
            &mut summary,
        )
        .unwrap();

        assert!(!store.tasks.contains_key(&task_id));
        assert_eq!(store.outbox.len(), 1);
        assert!(matches!(
            store.outbox[0].state,
            EncryptedSyncState::Tombstone { .. }
        ));
        assert_eq!(summary.repush_count, 1);
    }

    #[test]
    fn conflict_current_merges_distinct_fields_and_rebases_without_first_client() {
        let list_id = uuid(4);
        let dek = [0x4c; KEY_LEN];
        let base_clock = Hlc {
            wall_ms: 1_799_000_000_000,
            counter: 0,
            device_id: "base".to_string(),
        };
        let local_clock = Hlc {
            wall_ms: 1_799_000_000_100,
            counter: 0,
            device_id: "client-b".to_string(),
        };
        let remote_clock = Hlc {
            wall_ms: 1_799_000_000_101,
            counter: 0,
            device_id: "client-a".to_string(),
        };
        let server_revision = Hlc {
            wall_ms: 1_799_000_000_102,
            counter: 0,
            device_id: "client-a".to_string(),
        }
        .encode()
        .unwrap();
        let base_list = sample_list(list_id, false);
        let mut local_list_for_plaintext = base_list.clone();
        local_list_for_plaintext.color = "#00ff00".to_string();
        let local_plaintext = list_plaintext(&base_list, base_clock.clone())
            .stamp_list_changes(&local_list_for_plaintext, local_clock.clone())
            .unwrap();
        let mut remote_list_for_plaintext = base_list.clone();
        remote_list_for_plaintext.name = "Remote name".to_string();
        let remote_plaintext = list_plaintext(&base_list, base_clock)
            .stamp_list_changes(&remote_list_for_plaintext, remote_clock.clone())
            .unwrap();

        let blob = encrypt_plaintext(
            &dek,
            LISTS_COLLECTION,
            &list_id.to_string(),
            &remote_plaintext,
        )
        .unwrap();
        let record = PullRecord {
            record_id: list_id,
            collection: SyncCollection::Lists,
            seq: 2,
            revision_hlc: server_revision.clone(),
            state: EncryptedSyncState::Live {
                mutation_hlc: remote_clock.encode().unwrap(),
                blob,
            },
        };
        let context = context_for(list_id, dek);
        let mut local_list = base_list;
        local_list.color = "#00ff00".to_string();
        let mut store = FakeStore::default();
        store.lists.insert(list_id, local_list);
        store.record_states.insert(
            (SyncCollection::Lists, list_id),
            LocalSyncRecordState {
                current_revision_hlc: Some(
                    Hlc {
                        wall_ms: 1_799_000_000_001,
                        counter: 0,
                        device_id: "base".to_string(),
                    }
                    .encode()
                    .unwrap(),
                ),
                state: LocalSyncSemanticState::Live {
                    mutation_hlc: local_clock.encode().unwrap(),
                    plaintext_json: serde_json::to_string(&local_plaintext).unwrap(),
                },
            },
        );
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        apply_pull_list(&record, &context, &mut store, &mut now, &mut summary).unwrap();

        let merged_list = store.lists.get(&list_id).unwrap();
        assert_eq!(merged_list.name, "Remote name");
        assert_eq!(merged_list.color, "#00ff00");
        assert_eq!(summary.repush_count, 1);
        assert_eq!(store.outbox.len(), 1);
        assert_eq!(
            store.outbox[0].base_revision_hlc.as_deref(),
            Some(server_revision.as_str())
        );
        let EncryptedSyncState::Live { blob, .. } = &store.outbox[0].state else {
            panic!("expected rebased live head");
        };
        let rebased =
            decrypt_plaintext(&dek, LISTS_COLLECTION, &list_id.to_string(), blob).unwrap();
        let SyncPlaintext::List(rebased) = rebased else {
            panic!("list");
        };
        assert_eq!(rebased.name.value, "Remote name");
        assert_eq!(rebased.color.value, "#00ff00");
    }

    #[test]
    fn undecryptable_conflict_current_keeps_the_local_outbox_head() {
        let list_id = uuid(5);
        let dek = [0x5d; KEY_LEN];
        let semantic_hlc = Hlc {
            wall_ms: 1_799_000_000_010,
            counter: 0,
            device_id: "local".to_string(),
        }
        .encode()
        .unwrap();
        let revision_hlc = Hlc {
            wall_ms: 1_799_000_000_011,
            counter: 0,
            device_id: "local".to_string(),
        }
        .encode()
        .unwrap();
        let stale_op_id = Uuid::now_v7();
        let mut store = FakeStore::default();
        store.outbox.push(LocalSyncOutboxEntry {
            op_id: stale_op_id,
            record_id: list_id,
            collection: SyncCollection::Lists,
            base_revision_hlc: None,
            revision_hlc: revision_hlc.clone(),
            state: EncryptedSyncState::Live {
                mutation_hlc: semantic_hlc,
                blob: vec![1, 2, 3],
            },
            created_at: 1,
        });
        let current = PullRecord {
            record_id: list_id,
            collection: SyncCollection::Lists,
            seq: 1,
            revision_hlc,
            state: EncryptedSyncState::Live {
                mutation_hlc: Hlc {
                    wall_ms: 1_799_000_000_009,
                    counter: 0,
                    device_id: "remote".to_string(),
                }
                .encode()
                .unwrap(),
                blob: vec![0xff; 8],
            },
        };
        let context = context_for(list_id, dek);
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        assert_eq!(
            apply_pull_record(&current, &context, &mut store, &mut now, &mut summary).unwrap(),
            ApplyDisposition::UpgradeRequired(0xff)
        );

        assert_eq!(store.outbox.len(), 1);
        assert_eq!(store.outbox[0].op_id, stale_op_id);
        assert_eq!(summary.decrypt_failed_count, 0);
    }

    #[test]
    fn pull_rejects_authenticated_task_with_unencodable_field_clock() {
        let list_id = uuid(50);
        let record_id = uuid(51);
        let dek = [0x51; KEY_LEN];
        let task = new_task(
            list_id,
            None,
            "invalid clock".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            1,
        )
        .unwrap();
        let clock = Hlc {
            wall_ms: 1_799_000_000_050,
            counter: 0,
            device_id: "remote".to_string(),
        };
        let mut plaintext = SyncPlaintext::from_task(&task, clock.clone()).unwrap();
        let SyncPlaintext::Task(fields) = &mut plaintext else {
            panic!("task");
        };
        fields.note.hlc.device_id.clear();
        let plaintext_json = serde_json::to_vec(&plaintext).unwrap();
        let aad = format!("todori-sync-envelope/v2\ncollection:tasks\nrecord_id:{record_id}");
        let mut blob = vec![crate::ENVELOPE_VERSION];
        blob.extend_from_slice(
            &todori_crypto::encrypt(&dek, &plaintext_json, aad.as_bytes()).unwrap(),
        );
        let record = PullRecord {
            record_id,
            collection: SyncCollection::Tasks,
            seq: 1,
            revision_hlc: Hlc {
                wall_ms: clock.wall_ms + 1,
                ..clock.clone()
            }
            .encode()
            .unwrap(),
            state: EncryptedSyncState::Live {
                mutation_hlc: clock.encode().unwrap(),
                blob,
            },
        };
        let context = context_for(list_id, dek);
        let mut store = FakeStore::default();
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        assert_eq!(
            apply_pull_record(&record, &context, &mut store, &mut now, &mut summary).unwrap(),
            ApplyDisposition::Deferred(PullFailureReason::InvalidPlaintext, None)
        );
        assert_eq!(summary.decrypt_failed_count, 0);
        assert!(!store
            .record_states
            .contains_key(&(SyncCollection::Tasks, record_id)));
    }

    #[test]
    fn task_decryption_binds_the_authenticated_dek_to_plaintext_placement() {
        let list_a = uuid(60);
        let list_b = uuid(61);
        let list_c = uuid(62);
        let record_id = uuid(63);
        let dek_a = [0x60; KEY_LEN];
        let dek_b = [0x61; KEY_LEN];
        let mut existing = new_task(
            list_a,
            None,
            "move".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            1,
        )
        .unwrap();
        existing.id = record_id;
        let clock = Hlc {
            wall_ms: 1_799_000_000_060,
            counter: 0,
            device_id: "remote".to_string(),
        };

        let mut moved = existing.clone();
        moved.list_id = list_b;
        let moved_plaintext = SyncPlaintext::from_task(&moved, clock.clone()).unwrap();
        let moved_record = encrypted_task_record(record_id, &moved_plaintext, &dek_b, &clock);
        let moved_keys = LocalSyncKeys {
            list_deks: vec![(list_b, dek_b)],
            tenant_root_dek: None,
        };
        let SyncPlaintext::Task(decrypted_move) =
            decrypt_task_plaintext(&moved_record, Some(&existing), &moved_keys).unwrap()
        else {
            panic!("task");
        };
        assert_eq!(decrypted_move.placement.value.list_id, list_b);

        let mut mismatched = existing.clone();
        mismatched.list_id = list_c;
        let mismatched_plaintext = SyncPlaintext::from_task(&mismatched, clock.clone()).unwrap();
        let mismatched_record =
            encrypted_task_record(record_id, &mismatched_plaintext, &dek_b, &clock);
        let all_keys = LocalSyncKeys {
            list_deks: vec![(list_a, dek_a), (list_b, dek_b)],
            tenant_root_dek: None,
        };
        assert_eq!(
            decrypt_task_plaintext(&mismatched_record, Some(&existing), &all_keys),
            Err(ApplyDisposition::Deferred(
                PullFailureReason::AuthenticationFailed,
                Some(list_a)
            ))
        );
        assert_eq!(
            decrypt_task_plaintext(&mismatched_record, None, &all_keys),
            Err(ApplyDisposition::Deferred(
                PullFailureReason::NoMatchingDek,
                None
            ))
        );

        let no_matching_key = LocalSyncKeys {
            list_deks: vec![(list_b, [0x62; KEY_LEN])],
            tenant_root_dek: None,
        };
        assert_eq!(
            decrypt_task_plaintext(&moved_record, Some(&existing), &no_matching_key),
            Err(ApplyDisposition::Deferred(
                PullFailureReason::MissingDek,
                Some(list_a)
            ))
        );
    }

    #[test]
    fn stale_response_does_not_apply_after_a_newer_local_head_replaces_its_op() {
        let list_id = uuid(6);
        let dek = [0x6e; KEY_LEN];
        let current = encrypted_list_record(
            &List {
                name: "Remote stale".to_string(),
                ..sample_list(list_id, false)
            },
            &dek,
        );
        let newer_op_id = Uuid::now_v7();
        let clock = Hlc {
            wall_ms: 1_799_000_000_020,
            counter: 0,
            device_id: "new-local".to_string(),
        }
        .encode()
        .unwrap();
        let mut store = FakeStore::default();
        store.lists.insert(
            list_id,
            List {
                name: "New local".to_string(),
                ..sample_list(list_id, false)
            },
        );
        store.outbox.push(LocalSyncOutboxEntry {
            op_id: newer_op_id,
            record_id: list_id,
            collection: SyncCollection::Lists,
            base_revision_hlc: None,
            revision_hlc: clock.clone(),
            state: EncryptedSyncState::Live {
                mutation_hlc: clock,
                blob: vec![1],
            },
            created_at: 1,
        });
        let context = context_for(list_id, dek);
        let mut now = ticking_now();
        let mut summary = SyncRunSummary::default();

        reconcile_nonaccepted_push_in_transaction(
            &current,
            Uuid::now_v7(),
            &context,
            &mut store,
            &mut now,
            &mut summary,
        )
        .unwrap();

        assert_eq!(store.lists[&list_id].name, "New local");
        assert_eq!(store.outbox.len(), 1);
        assert_eq!(store.outbox[0].op_id, newer_op_id);
        assert_eq!(summary.applied_count, 0);
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
            collection: SyncCollection::Lists,
            seq: 1,
            revision_hlc: hlc.encode().unwrap(),
            state: EncryptedSyncState::Live {
                mutation_hlc: hlc.encode().unwrap(),
                blob,
            },
        }
    }

    fn encrypted_task_record(
        record_id: Uuid,
        plaintext: &SyncPlaintext,
        dek: &[u8; KEY_LEN],
        hlc: &Hlc,
    ) -> PullRecord {
        PullRecord {
            record_id,
            collection: SyncCollection::Tasks,
            seq: 1,
            revision_hlc: hlc.encode().unwrap(),
            state: EncryptedSyncState::Live {
                mutation_hlc: hlc.encode().unwrap(),
                blob: encrypt_plaintext(dek, TASKS_COLLECTION, &record_id.to_string(), plaintext)
                    .unwrap(),
            },
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
                tenant_root_dek: None,
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
            sort_order: "7fffffffffffffffffffffffffffffff".to_string(),
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
#[test]
fn durable_upgrade_block_reopens_when_supported_versions_catch_up() {
    assert!(upgrade_block_is_active("5:3"));
    assert!(upgrade_block_is_active("4:4"));
    assert!(!upgrade_block_is_active("4:3"));
    assert!(!upgrade_block_is_active("0:0"));
    assert!(upgrade_block_is_active("invalid"));
}

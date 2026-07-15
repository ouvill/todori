use std::{future::Future, pin::Pin};

use todori_crypto::{load_account_secret, AccountSecretKind};
use todori_storage::{TaskRepository, TimerSessionRepository};
use todori_sync::{
    account::AccountClient, ActiveSyncContext, LocalSyncAtomicStore, LocalSyncKeys, LocalSyncStore,
    LocalSyncWriteTransaction, SyncKeyRefresher, SyncRunSummary,
};
use zeroize::Zeroizing;

use super::{
    now_ms, CryptoRuntimeState, SyncRuntimeState, TodoriClient, INITIAL_BACKFILL_CURSOR_NAME,
};
use crate::{ClientError, RealtimeTicket, SqliteSyncStore, SyncStatus};

impl TodoriClient {
    pub fn sync_status(&self) -> Result<SyncStatus, ClientError> {
        let logged_in = self.has_active_sync_context();
        let state = self.sync_state()?;
        Ok(sync_status(logged_in, &state))
    }

    pub async fn sync_now(&self) -> Result<SyncStatus, ClientError> {
        if !self.has_active_sync_context() {
            let state = self.sync_state()?;
            return Ok(sync_status(false, &state));
        }
        {
            let mut state = self.sync_state()?;
            if state.running {
                return Ok(sync_status(true, &state));
            }
            state.running = true;
            state.last_error = None;
        }
        let running = SyncRunningGuard { client: self };

        let operation = match self.begin_operation() {
            Ok(operation) => operation,
            Err(error) => return Err(error),
        };
        let result = self.run_sync_now().await;
        drop(operation);
        let timestamp = now_ms()?;
        let mut state = self.sync_state()?;
        state.running = false;
        match result {
            Ok(summary) => {
                state.last_success_at = Some(timestamp);
                state.last_error = None;
                state.last_summary = summary;
            }
            Err(ClientError::UpgradeRequired) => {
                state.last_failure_at = Some(timestamp);
                state.last_error = Some("upgrade required".to_string());
            }
            Err(_) => {
                state.last_failure_at = Some(timestamp);
                state.last_error = Some("sync failed".to_string());
            }
        }
        let status = sync_status(true, &state);
        drop(state);
        drop(running);
        Ok(status)
    }

    /// Fetches a short-lived foreground realtime ticket without exposing the
    /// session token or tenant/device identifiers to the frontend.
    pub async fn realtime_ticket(&self) -> Result<RealtimeTicket, ClientError> {
        let context = self
            .active_sync_context()
            .ok_or(ClientError::AccountRequest)?;
        let client =
            AccountClient::new(&context.server_url).map_err(|_| ClientError::AccountRequest)?;
        let response = client
            .realtime_ticket(context.tenant_id, &context.session_token)
            .await
            .map_err(|_| ClientError::AccountRequest)?;
        Ok(RealtimeTicket {
            websocket_url: response.websocket_url,
            ticket: response.ticket,
            expires_at: response.expires_at,
        })
    }

    async fn run_sync_now(&self) -> Result<SyncRunSummary, ClientError> {
        self.ensure_account_runtime_restored()?;
        let context = self
            .active_sync_context()
            .ok_or(ClientError::AccountRequest)?;
        let mut store = SqliteSyncStore::new(self.db_path.clone(), self.db_key());
        let mut clock = || now_ms().map_err(|error| error.to_string());
        let mut key_refresher = ProductionKeyRefresher { client: self };
        let mut pre_push = |store: &mut SqliteSyncStore| {
            self.run_initial_backfill_if_needed(store)
                .map_err(|error| error.to_string())
        };
        let summary = todori_sync::run_sync_now_with_key_refresh_and_pre_push(
            context.clone(),
            &mut store,
            &mut clock,
            &mut key_refresher,
            &mut pre_push,
        )
        .await
        .map_err(|error| {
            if error == "upgrade required" {
                ClientError::UpgradeRequired
            } else {
                ClientError::SyncRun
            }
        })?;
        self.retire_safe_list_deks(&context).await?;
        Ok(summary)
    }

    async fn retire_safe_list_deks(&self, context: &ActiveSyncContext) -> Result<(), ClientError> {
        let candidates =
            super::account::retained_deleted_list_key_ids_on(&self.db_path, &self.db_key())?;
        if candidates.is_empty() {
            return Ok(());
        }
        let client =
            AccountClient::new(context.server_url.clone()).map_err(|_| ClientError::SyncRun)?;
        let mut retired = Vec::new();
        for list_id in candidates {
            if client
                .retire_list_key_bundle(context.tenant_id, list_id, &context.session_token)
                .await
                .map_err(|_| ClientError::SyncRun)?
            {
                retired.push(list_id);
            }
        }
        if retired.is_empty() {
            return Ok(());
        }

        let (identity, master_key, mut keys) = {
            let account = self.account_state()?;
            let CryptoRuntimeState::Ready(crypto) = &account.crypto else {
                return Err(ClientError::AccountBoundUnavailable);
            };
            (
                crate::LocalCryptoIdentity {
                    tenant_id: crypto.tenant_id(),
                    user_id: crypto.user_id(),
                    device_id: crypto.device_id(),
                },
                *crypto.master_key(),
                crypto.sync_keys().clone(),
            )
        };
        keys.list_deks
            .retain(|(list_id, _)| !retired.contains(list_id));
        let crypto = crate::persist_local_crypto_context(
            &self.db_path,
            &self.db_key(),
            identity,
            &master_key,
            keys,
            now_ms()?,
        )?;
        self.account_state()?.crypto = CryptoRuntimeState::Ready(Box::new(crypto));
        Ok(())
    }

    fn run_initial_backfill_if_needed(
        &self,
        store: &mut SqliteSyncStore,
    ) -> Result<(), ClientError> {
        if self.active_sync_context().is_none()
            || store
                .get_cursor_seq(INITIAL_BACKFILL_CURSOR_NAME)
                .map_err(|_| ClientError::SyncRun)?
                .is_some()
        {
            return Ok(());
        }

        let lists = self.local_lists_including_archived()?;
        let tasks = self.with_task_repository(|repository| Ok(repository.list_all_for_sync()?))?;
        let timer_sessions =
            self.with_timer_repository(|repository| Ok(repository.list_completed()?))?;
        let context = self
            .active_sync_context()
            .ok_or(ClientError::AccountRequest)?;
        if lists
            .iter()
            .any(|list| !context.keys.contains_list(list.id))
        {
            // Ready local crypto must cover every local list. Never perform
            // network key creation from the synchronous pre-push hook.
            return Err(ClientError::AccountBoundUnavailable);
        }
        let mut clock = || now_ms().map_err(|error| error.to_string());
        let mut transaction = store
            .begin_write_transaction()
            .map_err(|_| ClientError::SyncRun)?;
        todori_sync::enqueue_backfill(
            &mut transaction,
            &context.keys,
            &context.device_id,
            &lists,
            &tasks,
            &timer_sessions,
            &mut clock,
        )
        .map_err(|_| ClientError::SyncRun)?;
        transaction
            .set_cursor(INITIAL_BACKFILL_CURSOR_NAME, 1, now_ms()?)
            .map_err(|_| ClientError::SyncRun)?;
        transaction.commit().map_err(|_| ClientError::SyncRun)
    }

    fn active_sync_context(&self) -> Option<ActiveSyncContext> {
        self.ensure_account_runtime_restored().ok()?;
        let account = self.account_state().ok()?;
        let session = account
            .session
            .clone()?
            .logged_in
            .then_some(account.session.clone()?)?;
        let CryptoRuntimeState::Ready(crypto) = &account.crypto else {
            return None;
        };
        let tenant_id = crypto.tenant_id();
        let device_id = crypto.device_id().to_string();
        let keys = crypto.sync_keys().clone();
        let manifest_auth_key =
            todori_sync::derive_personal_manifest_auth_key(crypto.master_key()).ok()?;
        drop(account);
        let token = load_account_secret(&self.db_dir, AccountSecretKind::SessionToken).ok()??;
        let token = Zeroizing::new(String::from_utf8(token).ok()?);
        if token.is_empty() || !session.logged_in {
            return None;
        }
        Some(ActiveSyncContext {
            server_url: self.sync_server_url().ok()?,
            tenant_id,
            device_id,
            session_token: token.to_string(),
            keys,
            manifest_auth_key,
        })
    }

    fn has_active_sync_context(&self) -> bool {
        self.active_sync_context().is_some()
    }
}

struct SyncRunningGuard<'a> {
    client: &'a TodoriClient,
}

impl Drop for SyncRunningGuard<'_> {
    fn drop(&mut self) {
        if let Ok(mut state) = self.client.sync_state() {
            state.running = false;
        }
    }
}

struct ProductionKeyRefresher<'a> {
    client: &'a TodoriClient,
}

impl SyncKeyRefresher for ProductionKeyRefresher<'_> {
    fn refresh<'a>(
        &'a mut self,
    ) -> Pin<Box<dyn Future<Output = Result<LocalSyncKeys, String>> + Send + 'a>> {
        Box::pin(async move {
            self.client
                .refresh_list_deks_for_sync()
                .await
                .map_err(|error| error.to_string())
        })
    }
}

fn sync_status(logged_in: bool, state: &SyncRuntimeState) -> SyncStatus {
    SyncStatus {
        logged_in,
        running: state.running,
        last_success_at: state.last_success_at,
        last_failure_at: state.last_failure_at,
        last_error: state.last_error.clone(),
        pushed_count: state.last_summary.pushed_count,
        push_acked_count: state.last_summary.push_acked_count,
        push_superseded_count: state.last_summary.push_superseded_count,
        pulled_count: state.last_summary.pulled_count,
        applied_count: state.last_summary.applied_count,
        deleted_count: state.last_summary.deleted_count,
        decrypt_failed_count: state.last_summary.decrypt_failed_count,
        repush_count: state.last_summary.repush_count,
        missing_key_quarantined_count: state.last_summary.missing_key_quarantined_count,
        corruption_quarantined_count: state.last_summary.corruption_quarantined_count,
        resolved_quarantine_count: state.last_summary.resolved_quarantine_count,
        upgrade_required: state.last_error.as_deref() == Some("upgrade required"),
    }
}

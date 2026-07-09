use std::{
    path::PathBuf,
    sync::{Mutex, MutexGuard, OnceLock},
    time::{SystemTime, UNIX_EPOCH},
};

use todori_crypto::{
    delete_account_secret,
    key_hierarchy::{unwrap_master_key_with_device_key, KEY_LEN},
    load_account_secret, load_or_create_device_key, store_account_secret, AccountSecretKind,
};
use todori_domain::Uuid;
use todori_storage::{
    open_encrypted, ListRepository, SettingsRepository, SqliteListRepository,
    SqliteReminderRepository, SqliteSettingsRepository, SqliteTaskRepository, TaskRepository,
};
use todori_sync::{
    account::{unwrap_list_dek_bundles, AccountClient, AccountKeyMaterial, AccountListDekMaterial},
    ActiveSyncContext, LocalSyncKeys, LocalSyncStore, SyncRunSummary, SYNC_CURSOR_NAME,
};
use zeroize::{Zeroize, Zeroizing};

use crate::{
    api::{AccountAuthResultDto, AccountSessionStateDto, SyncStatusDto},
    sync_store::BridgeSyncStore,
};

static CORE_STATE: OnceLock<CoreState> = OnceLock::new();
static ACCOUNT_STATE: OnceLock<Mutex<AccountRuntimeState>> = OnceLock::new();
static SYNC_STATE: OnceLock<Mutex<SyncRuntimeState>> = OnceLock::new();

const SYNC_SERVER_URL_SETTING_KEY: &str = "sync_server_url";
const DEFAULT_SYNC_SERVER_URL: &str = "http://localhost:3000";
const ACCOUNT_EMAIL_SETTING_KEY: &str = "account_email";
const ACCOUNT_USER_ID_SETTING_KEY: &str = "account_user_id";
const ACCOUNT_TENANT_ID_SETTING_KEY: &str = "account_tenant_id";
const ACCOUNT_DEVICE_ID_SETTING_KEY: &str = "account_device_id";
const ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY: &str = "account_session_expires_at";
const INITIAL_BACKFILL_CURSOR_NAME: &str = "initial_backfill";

pub(crate) struct CoreState {
    pub(crate) db_dir: PathBuf,
    pub(crate) db_path: PathBuf,
    pub(crate) db_key: [u8; 32],
}

struct AccountRuntimeState {
    session: Option<AccountSessionStateDto>,
    #[allow(dead_code)]
    keys: Option<AccountKeyMaterial>,
}

#[derive(Default)]
#[allow(unexpected_cfgs)]
#[flutter_rust_bridge::frb(ignore)]
struct SyncRuntimeState {
    running: bool,
    last_success_at: Option<i64>,
    last_failure_at: Option<i64>,
    last_error: Option<String>,
    last_summary: SyncRunSummary,
}

enum AccountAuthMode {
    Register,
    Login,
}

pub(crate) fn init_core_state(state: CoreState) -> Result<(), String> {
    match CORE_STATE.get() {
        Some(existing) if existing.db_path == state.db_path => Ok(()),
        Some(_) => Err("core already initialized with a different database path".to_string()),
        None => CORE_STATE
            .set(state)
            .map_err(|_| "core already initialized".to_string()),
    }
}

pub(crate) fn get_sync_server_url() -> Result<String, String> {
    let stored = get_setting(SYNC_SERVER_URL_SETTING_KEY.to_string())?;
    Ok(stored
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_SYNC_SERVER_URL.to_string()))
}

pub(crate) fn set_sync_server_url(server_url: String) -> Result<(), String> {
    let server_url = server_url.trim().trim_end_matches('/').to_string();
    if server_url.is_empty() {
        return Err("sync server URL must not be empty".to_string());
    }
    set_setting(SYNC_SERVER_URL_SETTING_KEY.to_string(), server_url)
}

pub(crate) fn get_account_session_state() -> Result<AccountSessionStateDto, String> {
    ensure_account_runtime_restored()?;
    if let Some(session) = account_runtime_state().session.clone() {
        return Ok(session);
    }

    Ok(logged_out_account_state())
}

pub(crate) fn account_register(
    email: String,
    password: String,
    server_url: Option<String>,
    device_name: Option<String>,
) -> Result<AccountAuthResultDto, String> {
    account_auth(
        email,
        password,
        server_url,
        device_name,
        AccountAuthMode::Register,
    )
}

pub(crate) fn account_login(
    email: String,
    password: String,
    server_url: Option<String>,
    device_name: Option<String>,
) -> Result<AccountAuthResultDto, String> {
    account_auth(
        email,
        password,
        server_url,
        device_name,
        AccountAuthMode::Login,
    )
}

pub(crate) fn account_logout() -> Result<(), String> {
    let state = core_state()?;
    let server_url = get_sync_server_url()?;
    let token = load_account_secret(&state.db_dir, AccountSecretKind::SessionToken)
        .map_err(|error| error.to_string())?;
    if let Some(token) = token {
        if let Ok(token) = String::from_utf8(token) {
            let client = AccountClient::new(server_url).map_err(|_| "account logout failed")?;
            run_async(client.logout(&token)).map_err(|_| "account logout failed")?;
        }
    }
    delete_account_secret(&state.db_dir, AccountSecretKind::SessionToken)
        .map_err(|error| error.to_string())?;
    delete_account_secret(&state.db_dir, AccountSecretKind::MasterKeyWrap)
        .map_err(|error| error.to_string())?;
    clear_account_settings()?;
    replace_account_runtime_state(None, None);
    Ok(())
}

pub(crate) fn get_sync_status() -> Result<SyncStatusDto, String> {
    let logged_in = has_active_sync_context();
    let state = sync_runtime_state();
    Ok(sync_status_dto(logged_in, &state))
}

pub(crate) fn sync_now() -> Result<SyncStatusDto, String> {
    if !has_active_sync_context() {
        let state = sync_runtime_state();
        return Ok(sync_status_dto(false, &state));
    }
    {
        let mut state = sync_runtime_state();
        if state.running {
            return Ok(sync_status_dto(true, &state));
        }
        state.running = true;
        state.last_error = None;
    }

    let result = run_sync_now();
    let now = now_ms()?;
    let mut state = sync_runtime_state();
    state.running = false;
    match result {
        Ok(summary) => {
            state.last_success_at = Some(now);
            state.last_error = None;
            state.last_summary = summary;
        }
        Err(_) => {
            state.last_failure_at = Some(now);
            state.last_error = Some("sync failed".to_string());
        }
    }
    Ok(sync_status_dto(true, &state))
}

pub(crate) fn ensure_list_dek_for_list(list_id: Uuid) -> Result<(), String> {
    ensure_account_runtime_restored()?;
    let state = core_state()?;
    let account = account_runtime_state();
    let Some(session) = account.session.clone() else {
        return Ok(());
    };
    if !session.logged_in {
        return Ok(());
    }
    let Some(keys) = account.keys.as_ref() else {
        return Ok(());
    };
    let existing_list_ids = keys
        .list_deks
        .iter()
        .map(|entry| entry.list_id.clone())
        .collect::<Vec<_>>();
    if existing_list_ids
        .iter()
        .any(|id| id == &list_id.to_string())
    {
        return Ok(());
    }
    let master_key = *keys.master_key;
    let tenant_id = parse_uuid(
        session
            .tenant_id
            .as_deref()
            .ok_or_else(|| "list key registration failed".to_string())?,
    )?;
    drop(account);

    let session_token = load_account_secret(&state.db_dir, AccountSecretKind::SessionToken)
        .map_err(|error| error.to_string())?
        .and_then(|bytes| String::from_utf8(bytes).ok())
        .ok_or_else(|| "list key registration failed".to_string())?;
    let material = run_async(todori_sync::ensure_list_dek_for_list(
        get_sync_server_url()?,
        tenant_id,
        &session_token,
        &master_key,
        &existing_list_ids,
        list_id,
    ))?;

    if let Some(material) = material {
        let mut account = account_runtime_state();
        if let Some(keys) = account.keys.as_mut() {
            if !keys
                .list_deks
                .iter()
                .any(|entry| entry.list_id == material.list_id)
            {
                keys.list_deks.push(material);
            }
        }
    }
    Ok(())
}

pub(crate) fn enqueue_task_sync(task: &todori_domain::Task, deleted: bool) -> Result<(), String> {
    let Some(context) = active_sync_context() else {
        return Ok(());
    };
    let state = core_state()?;
    let mut store = BridgeSyncStore::new(state.db_path.clone(), state.db_key);
    let mut now = now_ms;
    todori_sync::enqueue_task_sync(
        &mut store,
        &context.keys,
        &context.device_id,
        task,
        deleted,
        &mut now,
    )
}

pub(crate) fn enqueue_list_sync(list: &todori_domain::List, deleted: bool) -> Result<(), String> {
    let Some(context) = active_sync_context() else {
        return Ok(());
    };
    let state = core_state()?;
    let mut store = BridgeSyncStore::new(state.db_path.clone(), state.db_key);
    let mut now = now_ms;
    todori_sync::enqueue_list_sync(
        &mut store,
        &context.keys,
        &context.device_id,
        list,
        deleted,
        &mut now,
    )
}

pub(crate) fn core_state() -> Result<&'static CoreState, String> {
    CORE_STATE
        .get()
        .ok_or_else(|| "core not initialized; call init_core first".to_string())
}

pub(crate) fn now_ms() -> Result<i64, String> {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?;

    i64::try_from(duration.as_millis()).map_err(|_| "current time exceeds i64 range".to_string())
}

pub(crate) fn run_async<T, E>(
    future: impl std::future::Future<Output = Result<T, E>>,
) -> Result<T, E> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("tokio runtime can be created for bridge requests")
        .block_on(future)
}

pub(crate) fn with_task_repository<T>(
    f: impl FnOnce(&mut SqliteTaskRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteTaskRepository::new(connection);
    f(&mut repository)
}

pub(crate) fn with_list_repository<T>(
    f: impl FnOnce(&mut SqliteListRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteListRepository::new(connection);
    f(&mut repository)
}

pub(crate) fn with_settings_repository<T>(
    f: impl FnOnce(&mut SqliteSettingsRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteSettingsRepository::new(connection);
    f(&mut repository)
}

pub(crate) fn with_reminder_repository<T>(
    f: impl FnOnce(&mut SqliteReminderRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteReminderRepository::new(connection);
    f(&mut repository)
}

fn account_auth(
    email: String,
    mut password: String,
    server_url: Option<String>,
    device_name: Option<String>,
    mode: AccountAuthMode,
) -> Result<AccountAuthResultDto, String> {
    let state = core_state()?;
    let server_url = match server_url {
        Some(server_url) => {
            set_sync_server_url(server_url)?;
            get_sync_server_url()?
        }
        None => get_sync_server_url()?,
    };
    let device_key = load_or_create_device_key(&state.db_dir).map_err(|error| error.to_string())?;
    let client = AccountClient::new(server_url).map_err(|_| "account request failed")?;

    let outcome = match mode {
        AccountAuthMode::Register => {
            let initial_list_ids = local_list_ids_for_registration()?;
            let outcome = run_async(client.register(
                &email,
                &password,
                device_name.as_deref(),
                &device_key,
                initial_list_ids,
            ))
            .map_err(|_| "account request failed".to_string())?;
            password.zeroize();
            let session = account_session_to_dto(
                true,
                outcome.session.email.clone(),
                outcome.session.user_id.clone(),
                outcome.session.tenant_id.clone(),
                outcome.session.device_id.clone(),
            );
            persist_account_state(
                &state.db_dir,
                &session,
                outcome.session.expires_at_ms,
                outcome.session.session_token.as_bytes(),
                &outcome.local_wrapped_master_key,
            )?;
            let recovery_key = outcome.recovery_key.to_string();
            replace_account_runtime_state(Some(session.clone()), Some(outcome.keys));
            reset_login_sync_cursors()?;
            return Ok(AccountAuthResultDto {
                session,
                recovery_key: Some(recovery_key),
            });
        }
        AccountAuthMode::Login => {
            let outcome =
                run_async(client.login(&email, &password, device_name.as_deref(), &device_key))
                    .map_err(|_| "account request failed".to_string())?;
            password.zeroize();
            outcome
        }
    };

    let session = account_session_to_dto(
        true,
        outcome.session.email.clone(),
        outcome.session.user_id.clone(),
        outcome.session.tenant_id.clone(),
        outcome.session.device_id.clone(),
    );
    persist_account_state(
        &state.db_dir,
        &session,
        outcome.session.expires_at_ms,
        outcome.session.session_token.as_bytes(),
        &outcome.local_wrapped_master_key,
    )?;
    replace_account_runtime_state(Some(session.clone()), Some(outcome.keys));
    reset_login_sync_cursors()?;
    Ok(AccountAuthResultDto {
        session,
        recovery_key: None,
    })
}

fn run_sync_now() -> Result<SyncRunSummary, String> {
    ensure_account_runtime_restored()?;
    run_initial_backfill_if_needed()?;
    let _ = refresh_list_deks_for_sync();
    let context = active_sync_context().ok_or_else(|| "not logged in".to_string())?;
    let state = core_state()?;
    let mut store = BridgeSyncStore::new(state.db_path.clone(), state.db_key);
    let mut now = now_ms;
    run_async(todori_sync::run_sync_now(context, &mut store, &mut now))
}

fn run_initial_backfill_if_needed() -> Result<(), String> {
    if active_sync_context().is_none() {
        return Ok(());
    }
    let state = core_state()?;
    let mut store = BridgeSyncStore::new(state.db_path.clone(), state.db_key);
    if store
        .get_cursor_seq(INITIAL_BACKFILL_CURSOR_NAME)?
        .is_some()
    {
        return Ok(());
    }

    let lists = local_lists_including_archived()?;
    for list in &lists {
        ensure_list_dek_for_list(list.id)?;
    }
    let tasks = with_task_repository(|repository| {
        repository
            .list_all_for_sync()
            .map_err(|error| error.to_string())
    })?;
    let context = active_sync_context().ok_or_else(|| "not logged in".to_string())?;
    let mut now = now_ms;
    todori_sync::enqueue_backfill(
        &mut store,
        &context.keys,
        &context.device_id,
        &lists,
        &tasks,
        &mut now,
    )?;
    store.set_cursor(INITIAL_BACKFILL_CURSOR_NAME, 1, now_ms()?)?;
    Ok(())
}

fn active_sync_context() -> Option<ActiveSyncContext> {
    ensure_account_runtime_restored().ok()?;
    let state = core_state().ok()?;
    let account = account_runtime_state();
    let session = account.session.clone()?;
    if !session.logged_in {
        return None;
    }
    let keys = account.keys.as_ref()?;
    let tenant_id = parse_uuid(session.tenant_id.as_deref()?).ok()?;
    let device_id = session.device_id.clone()?;
    let sync_keys = LocalSyncKeys::from_account_keys(keys);
    drop(account);
    let session_token = load_account_secret(&state.db_dir, AccountSecretKind::SessionToken)
        .ok()
        .flatten()
        .and_then(|bytes| String::from_utf8(bytes).ok())?;
    Some(ActiveSyncContext {
        server_url: get_sync_server_url().ok()?,
        tenant_id,
        device_id,
        session_token,
        keys: sync_keys,
    })
}

fn has_active_sync_context() -> bool {
    active_sync_context().is_some()
}

fn ensure_account_runtime_restored() -> Result<(), String> {
    {
        let account = account_runtime_state();
        if account.session.is_some() {
            return Ok(());
        }
    }

    let state = core_state()?;
    let Some(_session_token) = load_account_secret(&state.db_dir, AccountSecretKind::SessionToken)
        .map_err(|error| error.to_string())?
        .and_then(|bytes| String::from_utf8(bytes).ok())
        .filter(|token| !token.is_empty())
    else {
        return Ok(());
    };
    let Some(local_wrapped_master_key) =
        load_account_secret(&state.db_dir, AccountSecretKind::MasterKeyWrap)
            .map_err(|error| error.to_string())?
    else {
        return Ok(());
    };
    let Some(email) = non_empty_setting(ACCOUNT_EMAIL_SETTING_KEY)? else {
        return Ok(());
    };
    let Some(user_id) = non_empty_setting(ACCOUNT_USER_ID_SETTING_KEY)? else {
        return Ok(());
    };
    let Some(tenant_id) = non_empty_setting(ACCOUNT_TENANT_ID_SETTING_KEY)? else {
        return Ok(());
    };
    let Some(device_id) = non_empty_setting(ACCOUNT_DEVICE_ID_SETTING_KEY)? else {
        return Ok(());
    };
    let expires_at = non_empty_setting(ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY)?
        .and_then(|value| value.parse::<i64>().ok());
    let Some(expires_at) = expires_at else {
        return Ok(());
    };
    if expires_at <= now_ms()? {
        return Ok(());
    }

    let device_key = load_or_create_device_key(&state.db_dir).map_err(|error| error.to_string())?;
    let master_key = match unwrap_master_key_with_device_key(&local_wrapped_master_key, &device_key)
    {
        Ok(master_key) => master_key,
        Err(_) => return Ok(()),
    };
    let session = account_session_to_dto(true, email, user_id, tenant_id, device_id);
    let keys = AccountKeyMaterial {
        master_key: Zeroizing::new(master_key),
        user_secret_key: Zeroizing::new([0; KEY_LEN]),
        tenant_root_dek: Zeroizing::new([0; KEY_LEN]),
        list_deks: Vec::new(),
    };
    replace_account_runtime_state(Some(session), Some(keys));
    Ok(())
}

fn refresh_list_deks_for_sync() -> Result<(), String> {
    ensure_account_runtime_restored()?;
    let state = core_state()?;
    let server_url = get_sync_server_url()?;
    let session_token = load_account_secret(&state.db_dir, AccountSecretKind::SessionToken)
        .map_err(|error| error.to_string())?
        .and_then(|bytes| String::from_utf8(bytes).ok())
        .ok_or_else(|| "list key refresh failed".to_string())?;
    let (tenant_id, master_key) = {
        let account = account_runtime_state();
        let Some(session) = account.session.as_ref() else {
            return Ok(());
        };
        if !session.logged_in {
            return Ok(());
        }
        let Some(keys) = account.keys.as_ref() else {
            return Ok(());
        };
        let tenant_id = parse_uuid(
            session
                .tenant_id
                .as_deref()
                .ok_or_else(|| "list key refresh failed".to_string())?,
        )?;
        (tenant_id, *keys.master_key)
    };

    let client =
        AccountClient::new(server_url).map_err(|_| "list key refresh failed".to_string())?;
    let bundles = run_async(client.list_key_bundles(tenant_id, &session_token))
        .map_err(|_| "list key refresh failed".to_string())?;
    let materials = unwrap_list_dek_bundles(&bundles, &master_key)
        .map_err(|_| "list key refresh failed".to_string())?;
    merge_account_list_deks(materials);
    Ok(())
}

fn merge_account_list_deks(materials: Vec<AccountListDekMaterial>) {
    let mut account = account_runtime_state();
    let Some(keys) = account.keys.as_mut() else {
        return;
    };
    for material in materials {
        if !keys
            .list_deks
            .iter()
            .any(|entry| entry.list_id == material.list_id)
        {
            keys.list_deks.push(material);
        }
    }
}

fn local_list_ids_for_registration() -> Result<Vec<Uuid>, String> {
    Ok(local_lists_including_archived()?
        .into_iter()
        .map(|list| list.id)
        .collect())
}

fn local_lists_including_archived() -> Result<Vec<todori_domain::List>, String> {
    with_list_repository(|repository| {
        let mut lists = repository.list_all().map_err(|error| error.to_string())?;
        lists.extend(
            repository
                .list_archived()
                .map_err(|error| error.to_string())?,
        );
        Ok(lists)
    })
}

fn reset_login_sync_cursors() -> Result<(), String> {
    let state = core_state()?;
    let mut store = BridgeSyncStore::new(state.db_path.clone(), state.db_key);
    store.delete_cursor(INITIAL_BACKFILL_CURSOR_NAME)?;
    store.delete_cursor(SYNC_CURSOR_NAME)
}

fn persist_account_state(
    db_dir: &PathBuf,
    session: &AccountSessionStateDto,
    expires_at_ms: i64,
    session_token: &[u8],
    local_wrapped_master_key: &[u8],
) -> Result<(), String> {
    store_account_secret(db_dir, AccountSecretKind::SessionToken, session_token)
        .map_err(|error| error.to_string())?;
    store_account_secret(
        db_dir,
        AccountSecretKind::MasterKeyWrap,
        local_wrapped_master_key,
    )
    .map_err(|error| error.to_string())?;
    set_setting(
        ACCOUNT_EMAIL_SETTING_KEY.to_string(),
        session.email.clone().unwrap_or_default(),
    )?;
    set_setting(
        ACCOUNT_USER_ID_SETTING_KEY.to_string(),
        session.user_id.clone().unwrap_or_default(),
    )?;
    set_setting(
        ACCOUNT_TENANT_ID_SETTING_KEY.to_string(),
        session.tenant_id.clone().unwrap_or_default(),
    )?;
    set_setting(
        ACCOUNT_DEVICE_ID_SETTING_KEY.to_string(),
        session.device_id.clone().unwrap_or_default(),
    )?;
    set_setting(
        ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY.to_string(),
        expires_at_ms.to_string(),
    )?;
    Ok(())
}

fn clear_account_settings() -> Result<(), String> {
    for key in [
        ACCOUNT_EMAIL_SETTING_KEY,
        ACCOUNT_USER_ID_SETTING_KEY,
        ACCOUNT_TENANT_ID_SETTING_KEY,
        ACCOUNT_DEVICE_ID_SETTING_KEY,
        ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY,
    ] {
        set_setting(key.to_string(), String::new())?;
    }
    Ok(())
}

fn get_setting(key: String) -> Result<Option<String>, String> {
    with_settings_repository(|repository| {
        repository
            .get_setting(&key)
            .map_err(|error| error.to_string())
    })
}

fn set_setting(key: String, value: String) -> Result<(), String> {
    let now_ms = now_ms()?;
    with_settings_repository(|repository| {
        repository
            .set_setting(&key, &value, now_ms)
            .map_err(|error| error.to_string())
    })
}

fn non_empty_setting(key: &str) -> Result<Option<String>, String> {
    Ok(get_setting(key.to_string())?.filter(|value| !value.trim().is_empty()))
}

fn account_session_to_dto(
    logged_in: bool,
    email: String,
    user_id: String,
    tenant_id: String,
    device_id: String,
) -> AccountSessionStateDto {
    AccountSessionStateDto {
        logged_in,
        email: Some(email),
        user_id: Some(user_id),
        tenant_id: Some(tenant_id),
        device_id: Some(device_id),
    }
}

fn logged_out_account_state() -> AccountSessionStateDto {
    AccountSessionStateDto {
        logged_in: false,
        email: None,
        user_id: None,
        tenant_id: None,
        device_id: None,
    }
}

fn account_runtime_state() -> MutexGuard<'static, AccountRuntimeState> {
    ACCOUNT_STATE
        .get_or_init(|| {
            Mutex::new(AccountRuntimeState {
                session: None,
                keys: None,
            })
        })
        .lock()
        .expect("account runtime state mutex poisoned")
}

fn replace_account_runtime_state(
    session: Option<AccountSessionStateDto>,
    keys: Option<AccountKeyMaterial>,
) {
    let mut state = account_runtime_state();
    state.session = session;
    state.keys = keys;
}

fn sync_runtime_state() -> MutexGuard<'static, SyncRuntimeState> {
    SYNC_STATE
        .get_or_init(|| Mutex::new(SyncRuntimeState::default()))
        .lock()
        .expect("sync runtime state mutex poisoned")
}

fn sync_status_dto(logged_in: bool, state: &SyncRuntimeState) -> SyncStatusDto {
    SyncStatusDto {
        logged_in,
        running: state.running,
        last_success_at: state.last_success_at,
        last_failure_at: state.last_failure_at,
        last_error: state.last_error.clone(),
        pushed_count: usize_to_i32(state.last_summary.pushed_count),
        push_acked_count: usize_to_i32(state.last_summary.push_acked_count),
        push_superseded_count: usize_to_i32(state.last_summary.push_superseded_count),
        pulled_count: usize_to_i32(state.last_summary.pulled_count),
        applied_count: usize_to_i32(state.last_summary.applied_count),
        deleted_count: usize_to_i32(state.last_summary.deleted_count),
        decrypt_failed_count: usize_to_i32(state.last_summary.decrypt_failed_count),
        repush_count: usize_to_i32(state.last_summary.repush_count),
    }
}

fn usize_to_i32(value: usize) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

fn parse_uuid(value: &str) -> Result<Uuid, String> {
    value.parse::<Uuid>().map_err(|error| error.to_string())
}

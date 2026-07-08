use std::{
    collections::BTreeMap,
    path::PathBuf,
    str::FromStr,
    sync::{Mutex, OnceLock},
    time::{SystemTime, UNIX_EPOCH},
};

use serde_json::{json, Value};
use todori_crypto::derive_local_db_key;
use todori_domain::{
    archive_list as domain_archive_list, fractional_index_after, fractional_index_between,
    new_list, new_task, rename_list as domain_rename_list, transition_task,
    unarchive_list as domain_unarchive_list, update_due_at, update_note, update_priority,
    update_title, validate_parent_for, List, Task, TaskStatus, Uuid,
};
use todori_storage::{
    open_encrypted, HomeTask, ListRepository, NewSyncOutboxEntry, Reminder, ReminderRepository,
    SettingsRepository, SqliteListRepository, SqliteReminderRepository, SqliteSettingsRepository,
    SqliteSyncStateRepository, SqliteTaskRepository, StorageError, SyncStateRepository,
    TaskRepository, TaskUndoEntry, TaskUndoOperation,
};
use todori_sync::{
    account::{AccountClient, AccountKeyMaterial},
    decrypt_plaintext, encrypt_plaintext, merge_lww, Hlc, PullRecord, PushOp, PushStatus,
    SyncEngine, SyncPlaintext, SyncRunSummary,
};
use zeroize::Zeroize;

use crate::dev_key_store::{
    delete_account_secret, load_account_secret, load_or_create_device_key, store_account_secret,
    AccountSecretKind,
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
const SYNC_CURSOR_NAME: &str = "main";
const SYNC_LOCAL_HLC_SETTING_KEY: &str = "sync_local_hlc";
const TASKS_COLLECTION: &str = "tasks";
const LISTS_COLLECTION: &str = "lists";

struct CoreState {
    db_dir: PathBuf,
    db_path: PathBuf,
    db_key: [u8; 32],
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

pub struct ListDto {
    pub id: String,
    pub name: String,
    pub color: String,
    pub icon: String,
    pub org_id: Option<String>,
    pub sort_order: String,
    pub is_default: bool,
    pub archived_at: Option<i64>,
    pub created_at: i64,
    pub updated_at: i64,
}

pub struct TaskDto {
    pub id: String,
    pub list_id: String,
    pub parent_task_id: Option<String>,
    pub title: String,
    pub note: String,
    pub status: String,
    pub priority: i32,
    pub due_at: Option<i64>,
    pub scheduled_at: Option<i64>,
    pub estimated_minutes: Option<i32>,
    pub sort_order: String,
    pub completed_at: Option<i64>,
    pub closed_reason: Option<String>,
    pub deleted_at: Option<i64>,
    pub assignee: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

pub struct TaskUndoDto {
    pub id: String,
    pub operation_type: String,
    pub task_id: String,
    pub list_id: String,
    pub task_title: String,
    pub created_at: i64,
}

pub struct HomeTaskDto {
    pub task: TaskDto,
    pub list_name: String,
    pub is_home_target: bool,
}

pub struct ReminderDto {
    pub id: String,
    pub task_id: String,
    pub remind_at: i64,
    pub snoozed_until: Option<i64>,
    pub created_at: i64,
}

#[derive(Clone)]
pub struct AccountSessionStateDto {
    pub logged_in: bool,
    pub email: Option<String>,
    pub user_id: Option<String>,
    pub tenant_id: Option<String>,
    pub device_id: Option<String>,
}

pub struct AccountAuthResultDto {
    pub session: AccountSessionStateDto,
    pub recovery_key: Option<String>,
}

#[derive(Clone)]
pub struct SyncStatusDto {
    pub logged_in: bool,
    pub running: bool,
    pub last_success_at: Option<i64>,
    pub last_failure_at: Option<i64>,
    pub last_error: Option<String>,
    pub pushed_count: i32,
    pub push_acked_count: i32,
    pub push_superseded_count: i32,
    pub pulled_count: i32,
    pub applied_count: i32,
    pub deleted_count: i32,
    pub decrypt_failed_count: i32,
    pub repush_count: i32,
}

pub fn greet(name: String) -> String {
    format!("Hello {name} from todori-core")
}

pub fn create_draft_task(title: String) -> String {
    let task = Task {
        id: Uuid::now_v7(),
        list_id: Uuid::now_v7(),
        parent_task_id: None,
        title,
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
        created_at: 0,
        updated_at: 0,
    };

    serde_json::to_string(&task).expect("Task is serializable")
}

/// Initializes Todori core for the process using `db_dir`.
///
/// This creates or loads a platform Device Key, derives the SQLCipher key,
/// initializes `<db_dir>/todori.db`, and stores only the DB path plus derived
/// key in process-global state. Reinitializing with the same DB path succeeds
/// idempotently; reinitializing with a different DB path returns an error
/// because `OnceLock` cannot safely swap process-global state.
pub fn init_core(db_dir: String, default_inbox_name: String) -> Result<(), String> {
    let db_dir = PathBuf::from(db_dir);
    std::fs::create_dir_all(&db_dir).map_err(|error| error.to_string())?;

    let device_key = load_or_create_device_key(&db_dir).map_err(|error| error.to_string())?;
    let db_key = derive_local_db_key(&device_key);
    let db_path = db_dir.join("todori.db");

    let connection = open_encrypted(&db_path, &db_key).map_err(|error| error.to_string())?;
    let mut repository = SqliteListRepository::new(connection);
    repository
        .ensure_default_list(default_inbox_name, now_ms()?)
        .map_err(|error| error.to_string())?;

    let new_state = CoreState {
        db_dir,
        db_path,
        db_key,
    };
    match CORE_STATE.get() {
        Some(existing) if existing.db_path == new_state.db_path => Ok(()),
        Some(_) => Err("core already initialized with a different database path".to_string()),
        None => CORE_STATE
            .set(new_state)
            .map_err(|_| "core already initialized".to_string()),
    }
}

pub fn get_sync_server_url() -> Result<String, String> {
    let stored = get_setting(SYNC_SERVER_URL_SETTING_KEY.to_string())?;
    Ok(stored
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_SYNC_SERVER_URL.to_string()))
}

pub fn set_sync_server_url(server_url: String) -> Result<(), String> {
    let server_url = server_url.trim().trim_end_matches('/').to_string();
    if server_url.is_empty() {
        return Err("sync server URL must not be empty".to_string());
    }
    set_setting(SYNC_SERVER_URL_SETTING_KEY.to_string(), server_url)
}

pub fn get_account_session_state() -> Result<AccountSessionStateDto, String> {
    if let Some(session) = account_runtime_state().session.clone() {
        return Ok(session);
    }

    let state = core_state()?;
    let has_session_token = load_account_secret(&state.db_dir, AccountSecretKind::SessionToken)
        .map_err(|error| error.to_string())?
        .is_some();
    let has_local_wrapped_mk = load_account_secret(&state.db_dir, AccountSecretKind::MasterKeyWrap)
        .map_err(|error| error.to_string())?
        .is_some();
    if !has_session_token || !has_local_wrapped_mk {
        return Ok(logged_out_account_state());
    }

    let email = get_setting(ACCOUNT_EMAIL_SETTING_KEY.to_string())?;
    let user_id = get_setting(ACCOUNT_USER_ID_SETTING_KEY.to_string())?;
    let tenant_id = get_setting(ACCOUNT_TENANT_ID_SETTING_KEY.to_string())?;
    let device_id = get_setting(ACCOUNT_DEVICE_ID_SETTING_KEY.to_string())?;
    if email.as_deref().unwrap_or("").is_empty()
        || user_id.as_deref().unwrap_or("").is_empty()
        || tenant_id.as_deref().unwrap_or("").is_empty()
        || device_id.as_deref().unwrap_or("").is_empty()
    {
        return Ok(logged_out_account_state());
    }

    Ok(AccountSessionStateDto {
        logged_in: true,
        email,
        user_id,
        tenant_id,
        device_id,
    })
}

pub fn account_register(
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

pub fn account_login(
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

pub fn account_logout() -> Result<(), String> {
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

pub fn get_sync_status() -> Result<SyncStatusDto, String> {
    Ok(sync_status_dto(has_active_sync_context()))
}

pub fn sync_now() -> Result<SyncStatusDto, String> {
    if !has_active_sync_context() {
        return Ok(sync_status_dto(false));
    }
    {
        let mut state = sync_runtime_state();
        if state.running {
            return Ok(sync_status_dto(true));
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
    Ok(sync_status_dto(true))
}

/// Creates a list using the caller-provided fractional `sort_order`.
///
/// Automatic fractional index generation is a later M3 concern and is not done
/// in this bridge layer.
pub fn create_list(name: String, sort_order: String) -> Result<ListDto, String> {
    let list = new_list(name, sort_order, now_ms()?).map_err(|error| error.to_string())?;
    with_list_repository(|repository| {
        repository
            .insert(list.clone())
            .map_err(|error| error.to_string())?;
        enqueue_list_sync(&list, false)?;
        Ok(list_to_dto(list))
    })
}

pub fn get_lists() -> Result<Vec<ListDto>, String> {
    with_list_repository(|repository| {
        repository
            .list_all()
            .map_err(|error| error.to_string())
            .map(|lists| lists.into_iter().map(list_to_dto).collect())
    })
}

pub fn get_archived_lists() -> Result<Vec<ListDto>, String> {
    with_list_repository(|repository| {
        repository
            .list_archived()
            .map_err(|error| error.to_string())
            .map(|lists| lists.into_iter().map(list_to_dto).collect())
    })
}

pub fn rename_list(list_id: String, name: String) -> Result<ListDto, String> {
    let list_id = parse_uuid(&list_id)?;
    let now_ms = now_ms()?;
    with_list_repository(|repository| {
        let list = repository.get(list_id).map_err(|error| error.to_string())?;
        let updated = domain_rename_list(list, name, now_ms).map_err(|error| error.to_string())?;
        repository
            .update(updated.clone())
            .map_err(|error| error.to_string())?;
        enqueue_list_sync(&updated, false)?;
        Ok(list_to_dto(updated))
    })
}

pub fn archive_list(list_id: String) -> Result<ListDto, String> {
    let list_id = parse_uuid(&list_id)?;
    let now_ms = now_ms()?;
    with_list_repository(|repository| {
        let list = repository.get(list_id).map_err(|error| error.to_string())?;
        if list.archived_at.is_none() && list.is_default {
            return Err("default list cannot be archived".to_string());
        }

        let updated = domain_archive_list(list, now_ms).map_err(|error| error.to_string())?;
        repository
            .update(updated.clone())
            .map_err(|error| error.to_string())?;
        enqueue_list_sync(&updated, false)?;
        Ok(list_to_dto(updated))
    })
}

pub fn unarchive_list(list_id: String) -> Result<ListDto, String> {
    let list_id = parse_uuid(&list_id)?;
    let now_ms = now_ms()?;
    with_list_repository(|repository| {
        let list = repository.get(list_id).map_err(|error| error.to_string())?;
        let updated = domain_unarchive_list(list, now_ms).map_err(|error| error.to_string())?;
        repository
            .update(updated.clone())
            .map_err(|error| error.to_string())?;
        enqueue_list_sync(&updated, false)?;
        Ok(list_to_dto(updated))
    })
}

/// Creates a task at the end of its sibling group using a domain-generated
/// fractional `sort_order`.
pub fn create_task(
    list_id: String,
    title: String,
    parent_task_id: Option<String>,
    due_at: Option<i64>,
    note: Option<String>,
) -> Result<TaskDto, String> {
    let list_id = parse_uuid(&list_id)?;
    let parent_task_id = parent_task_id.as_deref().map(parse_uuid).transpose()?;
    let now_ms = now_ms()?;
    with_task_repository(|repository| {
        let mut tasks = repository
            .list_active_by_list(list_id)
            .map_err(|error| error.to_string())?;

        let last_sibling_sort_order = tasks
            .iter()
            .filter(|existing| existing.parent_task_id == parent_task_id)
            .map(|existing| existing.sort_order.as_str())
            .max();
        let sort_order =
            fractional_index_after(last_sibling_sort_order).map_err(|error| error.to_string())?;
        let mut task = new_task(list_id, parent_task_id, title, sort_order, now_ms)
            .map_err(|error| error.to_string())?;
        if let Some(note) = note {
            task = update_note(task, note, now_ms).map_err(|error| error.to_string())?;
        }
        if let Some(due_at) = due_at {
            task = update_due_at(task, Some(due_at), now_ms).map_err(|error| error.to_string())?;
        }

        if let Some(parent_id) = parent_task_id {
            if !tasks.iter().any(|existing| existing.id == parent_id) {
                match repository.get(parent_id) {
                    Ok(parent) => tasks.push(parent),
                    Err(StorageError::NotFound(_)) => {}
                    Err(error) => return Err(error.to_string()),
                }
            }

            validate_parent_for(task.id, list_id, parent_id, &tasks)
                .map_err(|error| error.to_string())?;
        }

        repository
            .insert(task.clone())
            .map_err(|error| error.to_string())?;
        enqueue_task_sync(&task, false)?;
        Ok(task_to_dto(task))
    })
}

pub fn reorder_task(
    task_id: String,
    previous_task_id: Option<String>,
    next_task_id: Option<String>,
) -> Result<TaskDto, String> {
    let task_id = parse_uuid(&task_id)?;
    let previous_task_id = previous_task_id.as_deref().map(parse_uuid).transpose()?;
    let next_task_id = next_task_id.as_deref().map(parse_uuid).transpose()?;

    if previous_task_id == Some(task_id) || next_task_id == Some(task_id) {
        return Err("task cannot be reordered relative to itself".to_string());
    }
    if previous_task_id.is_some() && previous_task_id == next_task_id {
        return Err("previous and next task must be different".to_string());
    }

    let now_ms = now_ms()?;
    with_task_repository(|repository| {
        let mut task = repository.get(task_id).map_err(|error| error.to_string())?;

        let previous = previous_task_id
            .map(|boundary_id| load_reorder_boundary(repository, boundary_id, &task))
            .transpose()?;
        let next = next_task_id
            .map(|boundary_id| load_reorder_boundary(repository, boundary_id, &task))
            .transpose()?;

        let sort_order = fractional_index_between(
            previous
                .as_ref()
                .map(|boundary| boundary.sort_order.as_str()),
            next.as_ref().map(|boundary| boundary.sort_order.as_str()),
        )
        .map_err(|error| error.to_string())?;

        task.sort_order = sort_order;
        task.updated_at = now_ms;
        repository
            .update(task.clone())
            .map_err(|error| error.to_string())?;
        enqueue_task_sync(&task, false)?;
        Ok(task_to_dto(task))
    })
}

pub fn get_tasks(list_id: String) -> Result<Vec<TaskDto>, String> {
    let list_id = parse_uuid(&list_id)?;
    with_task_repository(|repository| {
        repository
            .list_active_by_list(list_id)
            .map_err(|error| error.to_string())
            .map(|tasks| tasks.into_iter().map(task_to_dto).collect())
    })
}

pub fn search_tasks(query: String) -> Result<Vec<TaskDto>, String> {
    with_task_repository(|repository| {
        repository
            .search_tasks(&query)
            .map_err(|error| error.to_string())
            .map(|tasks| tasks.into_iter().map(task_to_dto).collect())
    })
}

pub fn get_home_tasks(
    today_start_ms: i64,
    tomorrow_start_ms: i64,
) -> Result<Vec<HomeTaskDto>, String> {
    with_task_repository(|repository| {
        repository
            .list_home(today_start_ms, tomorrow_start_ms)
            .map_err(|error| error.to_string())
            .map(|tasks| tasks.into_iter().map(home_task_to_dto).collect())
    })
}

pub fn count_task_descendants(task_id: String) -> Result<i32, String> {
    let task_id = parse_uuid(&task_id)?;
    with_task_repository(|repository| {
        repository.get(task_id).map_err(|error| error.to_string())?;
        repository
            .count_descendants(task_id)
            .map_err(|error| error.to_string())
            .and_then(count_to_i32)
    })
}

pub fn count_tasks_in_list(list_id: String) -> Result<i32, String> {
    let list_id = parse_uuid(&list_id)?;
    with_list_repository(|repository| {
        repository.get(list_id).map_err(|error| error.to_string())?;
        repository
            .count_tasks(list_id)
            .map_err(|error| error.to_string())
            .and_then(count_to_i32)
    })
}

pub fn update_task(
    task_id: String,
    title: String,
    note: String,
    priority: i32,
    due_at: Option<i64>,
) -> Result<TaskDto, String> {
    if !(0..=3).contains(&priority) {
        return Err("task priority must be between 0 and 3".to_string());
    }

    let task_id = parse_uuid(&task_id)?;
    let now_ms = now_ms()?;

    with_task_repository(|repository| {
        let before = repository.get(task_id).map_err(|error| error.to_string())?;
        let task =
            update_title(before.clone(), title, now_ms).map_err(|error| error.to_string())?;
        let task = update_note(task, note, now_ms).map_err(|error| error.to_string())?;
        let task = update_priority(task, priority, now_ms).map_err(|error| error.to_string())?;
        let updated = update_due_at(task, due_at, now_ms).map_err(|error| error.to_string())?;
        repository
            .update_with_undo(before, updated.clone(), TaskUndoOperation::Edit, now_ms)
            .map_err(|error| error.to_string())?;
        enqueue_task_sync(&updated, false)?;
        Ok(task_to_dto(updated))
    })
}

pub fn set_task_status(
    task_id: String,
    status: String,
    closed_reason: Option<String>,
) -> Result<TaskDto, String> {
    let task_id = parse_uuid(&task_id)?;
    let status = parse_status(&status)?;
    let now_ms = now_ms()?;

    with_task_repository(|repository| {
        let before = repository.get(task_id).map_err(|error| error.to_string())?;
        let updated = transition_task(before.clone(), status, closed_reason, now_ms)
            .map_err(|error| error.to_string())?;
        if status == TaskStatus::Done || status == TaskStatus::WontDo {
            repository
                .update_with_undo(before, updated.clone(), TaskUndoOperation::Complete, now_ms)
                .map_err(|error| error.to_string())?;
        } else {
            repository
                .update(updated.clone())
                .map_err(|error| error.to_string())?;
        }
        enqueue_task_sync(&updated, false)?;
        Ok(task_to_dto(updated))
    })
}

pub fn delete_task(task_id: String) -> Result<(), String> {
    let task_id = parse_uuid(&task_id)?;
    with_task_repository(|repository| {
        let task = repository.get(task_id).map_err(|error| error.to_string())?;
        repository
            .delete_subtree(task_id)
            .map_err(|error| error.to_string())?;
        enqueue_task_sync(&task, true)
    })
}

pub fn delete_list(list_id: String) -> Result<(), String> {
    let list_id = parse_uuid(&list_id)?;
    with_list_repository(|repository| {
        let list = repository.get(list_id).map_err(|error| error.to_string())?;
        if list.is_default {
            return Err("default list cannot be deleted".to_string());
        }
        repository
            .delete_with_tasks(list_id)
            .map_err(|error| error.to_string())?;
        enqueue_list_sync(&list, true)
    })
}

pub fn get_latest_task_undo() -> Result<Option<TaskUndoDto>, String> {
    with_task_repository(|repository| {
        repository
            .latest_unconsumed_undo()
            .map_err(|error| error.to_string())
            .map(|entry| entry.map(task_undo_to_dto))
    })
}

pub fn undo_task_operation(undo_id: String) -> Result<TaskDto, String> {
    let undo_id = parse_uuid(&undo_id)?;
    let now_ms = now_ms()?;
    with_task_repository(|repository| {
        repository
            .undo_task_operation(undo_id, now_ms)
            .map_err(|error| error.to_string())
            .map(task_to_dto)
    })
}

pub fn get_setting(key: String) -> Result<Option<String>, String> {
    with_settings_repository(|repository| {
        repository
            .get_setting(&key)
            .map_err(|error| error.to_string())
    })
}

pub fn set_setting(key: String, value: String) -> Result<(), String> {
    let now_ms = now_ms()?;
    with_settings_repository(|repository| {
        repository
            .set_setting(&key, &value, now_ms)
            .map_err(|error| error.to_string())
    })
}

pub fn set_task_reminder(task_id: String, remind_at: i64) -> Result<ReminderDto, String> {
    let task_id = parse_uuid(&task_id)?;
    let now_ms = now_ms()?;
    with_reminder_repository(|repository| {
        repository
            .set_task_reminder(task_id, remind_at, now_ms)
            .map_err(|error| error.to_string())
            .map(reminder_to_dto)
    })
}

pub fn clear_task_reminders(task_id: String) -> Result<Vec<ReminderDto>, String> {
    let task_id = parse_uuid(&task_id)?;
    with_reminder_repository(|repository| {
        repository
            .clear_task_reminders(task_id)
            .map_err(|error| error.to_string())
            .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
    })
}

pub fn get_task_reminders(task_id: String) -> Result<Vec<ReminderDto>, String> {
    let task_id = parse_uuid(&task_id)?;
    with_reminder_repository(|repository| {
        repository
            .list_task_reminders(task_id)
            .map_err(|error| error.to_string())
            .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
    })
}

pub fn get_task_subtree_reminders(task_id: String) -> Result<Vec<ReminderDto>, String> {
    let task_id = parse_uuid(&task_id)?;
    with_reminder_repository(|repository| {
        repository
            .list_task_subtree_reminders(task_id)
            .map_err(|error| error.to_string())
            .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
    })
}

pub fn get_list_reminders(list_id: String) -> Result<Vec<ReminderDto>, String> {
    let list_id = parse_uuid(&list_id)?;
    with_reminder_repository(|repository| {
        repository
            .list_list_reminders(list_id)
            .map_err(|error| error.to_string())
            .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
    })
}

pub fn list_pending_reminders(now_ms: i64) -> Result<Vec<ReminderDto>, String> {
    with_reminder_repository(|repository| {
        repository
            .list_pending_reminders(now_ms)
            .map_err(|error| error.to_string())
            .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
    })
}

pub fn snooze_reminder(reminder_id: String, snoozed_until: i64) -> Result<ReminderDto, String> {
    let reminder_id = parse_uuid(&reminder_id)?;
    with_reminder_repository(|repository| {
        repository
            .snooze_reminder(reminder_id, snoozed_until)
            .map_err(|error| error.to_string())
            .map(reminder_to_dto)
    })
}

enum AccountAuthMode {
    Register,
    Login,
}

struct ActiveSyncContext {
    server_url: String,
    tenant_id: Uuid,
    device_id: String,
    session_token: String,
    keys: LocalSyncKeys,
}

struct LocalSyncKeys {
    tenant_root_dek: [u8; 32],
    list_deks: Vec<(String, [u8; 32])>,
}

fn run_sync_now() -> Result<SyncRunSummary, String> {
    let context = active_sync_context().ok_or_else(|| "not logged in".to_string())?;
    let engine = SyncEngine::new(
        context.server_url.clone(),
        context.tenant_id,
        context.session_token.clone(),
    )
    .map_err(|_| "sync failed".to_string())?;
    let mut summary = SyncRunSummary::default();

    let outbox = with_sync_repository(|repository| {
        repository
            .list_outbox(100)
            .map_err(|error| error.to_string())
    })?;
    summary.pushed_count = outbox.len();
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
    let push_outcome = run_async(engine.push_batch(push_ops)).map_err(|_| "sync failed")?;
    with_sync_repository(|repository| {
        for outcome in push_outcome.outcomes {
            match outcome.status {
                PushStatus::Accepted | PushStatus::NoOp => {
                    repository
                        .ack_outbox(outcome.outbox_id)
                        .map_err(|error| error.to_string())?;
                    summary.push_acked_count += 1;
                }
                PushStatus::Superseded => {
                    repository
                        .ack_outbox(outcome.outbox_id)
                        .map_err(|error| error.to_string())?;
                    summary.push_superseded_count += 1;
                }
            }
        }
        Ok(())
    })?;

    loop {
        let since = with_sync_repository(|repository| {
            repository
                .get_cursor(SYNC_CURSOR_NAME)
                .map_err(|error| error.to_string())
                .map(|cursor| cursor.map(|cursor| cursor.seq).unwrap_or(0))
        })?;
        let page = run_async(engine.pull_page(since, 100)).map_err(|_| "sync failed")?;
        if page.records.is_empty() {
            break;
        }
        summary.pulled_count += page.records.len();
        for record in &page.records {
            apply_pull_record(record, &context, &mut summary)?;
        }
        with_sync_repository(|repository| {
            repository
                .set_cursor(SYNC_CURSOR_NAME, page.next_since, now_ms()?)
                .map_err(|error| error.to_string())
        })?;
        if !page.has_more {
            break;
        }
    }

    Ok(summary)
}

fn apply_pull_record(
    record: &PullRecord,
    context: &ActiveSyncContext,
    summary: &mut SyncRunSummary,
) -> Result<(), String> {
    match record.collection.as_str() {
        LISTS_COLLECTION => apply_pull_list(record, context, summary),
        TASKS_COLLECTION => apply_pull_task(record, context, summary),
        _ => {
            summary.decrypt_failed_count += 1;
            Ok(())
        }
    }
}

fn apply_pull_list(
    record: &PullRecord,
    context: &ActiveSyncContext,
    summary: &mut SyncRunSummary,
) -> Result<(), String> {
    if record.deleted {
        with_list_repository(|repository| {
            repository
                .delete_with_tasks_for_sync(record.record_id)
                .map(|deleted| {
                    summary.deleted_count += 1 + deleted;
                })
                .map_err(|error| error.to_string())
        })?;
        with_sync_repository(|repository| {
            repository
                .delete_record_state(LISTS_COLLECTION, record.record_id)
                .map_err(|error| error.to_string())
        })?;
        return Ok(());
    }

    let incoming = decrypt_plaintext(
        &context.keys.tenant_root_dek,
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
    let existing = with_list_repository(|repository| match repository.get(record.record_id) {
        Ok(list) => Ok(Some(list)),
        Err(StorageError::NotFound(_)) => Ok(None),
        Err(error) => Err(error.to_string()),
    })?;
    let stored_plaintext = stored_sync_plaintext(LISTS_COLLECTION, record.record_id)?;
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
    let list = list_from_plaintext(record.record_id, existing.as_ref(), &merged)?;
    with_list_repository(|repository| {
        repository
            .upsert_for_sync(list.clone())
            .map_err(|error| error.to_string())
    })?;
    store_sync_plaintext(LISTS_COLLECTION, record.record_id, &merged)?;
    summary.applied_count += 1;
    if needs_repush {
        enqueue_merged_plaintext(
            record.record_id,
            LISTS_COLLECTION,
            &merged,
            &context.keys.tenant_root_dek,
            &context.device_id,
            summary,
        )?;
    }
    Ok(())
}

fn apply_pull_task(
    record: &PullRecord,
    context: &ActiveSyncContext,
    summary: &mut SyncRunSummary,
) -> Result<(), String> {
    if record.deleted {
        with_task_repository(|repository| {
            repository
                .delete_subtree_for_sync(record.record_id)
                .map(|deleted| {
                    summary.deleted_count += deleted;
                })
                .map_err(|error| error.to_string())
        })?;
        with_sync_repository(|repository| {
            repository
                .delete_record_state(TASKS_COLLECTION, record.record_id)
                .map_err(|error| error.to_string())
        })?;
        return Ok(());
    }

    let existing = with_task_repository(|repository| match repository.get(record.record_id) {
        Ok(task) => Ok(Some(task)),
        Err(StorageError::NotFound(_)) => Ok(None),
        Err(error) => Err(error.to_string()),
    })?;
    let dek = existing
        .as_ref()
        .and_then(|task| dek_for_task_list(&context.keys, &task.list_id.to_string()))
        .unwrap_or(context.keys.tenant_root_dek);
    let incoming = match decrypt_plaintext(
        &dek,
        TASKS_COLLECTION,
        &record.record_id.to_string(),
        &record.blob,
    ) {
        Ok(incoming) => incoming,
        Err(_) => {
            summary.decrypt_failed_count += 1;
            return Ok(());
        }
    };
    let dek = incoming
        .fields
        .get("list_id")
        .and_then(Value::as_str)
        .and_then(|list_id| dek_for_task_list(&context.keys, list_id))
        .unwrap_or(dek);
    let stored_plaintext = stored_sync_plaintext(TASKS_COLLECTION, record.record_id)?;
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
    let task = task_from_plaintext(record.record_id, existing.as_ref(), &merged)?;
    with_task_repository(|repository| {
        repository
            .upsert_for_sync(task)
            .map_err(|error| error.to_string())
    })?;
    store_sync_plaintext(TASKS_COLLECTION, record.record_id, &merged)?;
    summary.applied_count += 1;
    if needs_repush {
        enqueue_merged_plaintext(
            record.record_id,
            TASKS_COLLECTION,
            &merged,
            &dek,
            &context.device_id,
            summary,
        )?;
    }
    Ok(())
}

fn enqueue_task_sync(task: &Task, deleted: bool) -> Result<(), String> {
    let Some(context) = active_sync_context() else {
        return Ok(());
    };
    let hlc = tick_local_hlc(&context.device_id)?;
    let dek = dek_for_task_list(&context.keys, &task.list_id.to_string())
        .unwrap_or(context.keys.tenant_root_dek);
    let plaintext = task_plaintext(task, hlc.clone());
    enqueue_plaintext(task.id, TASKS_COLLECTION, deleted, &plaintext, &dek, &hlc)
}

fn enqueue_list_sync(list: &List, deleted: bool) -> Result<(), String> {
    let Some(context) = active_sync_context() else {
        return Ok(());
    };
    let hlc = tick_local_hlc(&context.device_id)?;
    let plaintext = list_plaintext(list, hlc.clone());
    enqueue_plaintext(
        list.id,
        LISTS_COLLECTION,
        deleted,
        &plaintext,
        &context.keys.tenant_root_dek,
        &hlc,
    )
}

fn enqueue_merged_plaintext(
    record_id: Uuid,
    collection: &str,
    plaintext: &SyncPlaintext,
    dek: &[u8; 32],
    device_id: &str,
    summary: &mut SyncRunSummary,
) -> Result<(), String> {
    let mut merged = plaintext.clone();
    let hlc = tick_local_hlc(device_id)?;
    for field_hlc in merged.field_hlcs.values_mut() {
        if *field_hlc < hlc {
            *field_hlc = hlc.clone();
        }
    }
    enqueue_plaintext(record_id, collection, false, &merged, dek, &hlc)?;
    summary.repush_count += 1;
    Ok(())
}

fn enqueue_plaintext(
    record_id: Uuid,
    collection: &str,
    deleted: bool,
    plaintext: &SyncPlaintext,
    dek: &[u8; 32],
    hlc: &Hlc,
) -> Result<(), String> {
    let blob = if deleted {
        Vec::new()
    } else {
        encrypt_plaintext(dek, collection, &record_id.to_string(), plaintext)
            .map_err(|_| "sync failed".to_string())?
    };
    let encoded_hlc = hlc.encode().map_err(|_| "sync failed".to_string())?;
    with_sync_repository(|repository| {
        let result = repository
            .enqueue_outbox(NewSyncOutboxEntry {
                record_id,
                collection: collection.to_string(),
                hlc: encoded_hlc,
                deleted,
                blob,
                created_at: now_ms()?,
            })
            .map(|_| ())
            .map_err(|error| error.to_string());
        if result.is_ok() {
            if deleted {
                repository
                    .delete_record_state(collection, record_id)
                    .map_err(|error| error.to_string())?;
            } else {
                let plaintext_json =
                    serde_json::to_string(plaintext).map_err(|_| "sync failed".to_string())?;
                repository
                    .upsert_record_state(collection, record_id, &plaintext_json, now_ms()?)
                    .map_err(|error| error.to_string())?;
            }
        }
        result
    })
}

fn stored_sync_plaintext(
    collection: &str,
    record_id: Uuid,
) -> Result<Option<SyncPlaintext>, String> {
    with_sync_repository(|repository| {
        repository
            .get_record_state(collection, record_id)
            .map_err(|error| error.to_string())
    })?
    .map(|json| serde_json::from_str(&json).map_err(|_| "sync failed".to_string()))
    .transpose()
}

fn store_sync_plaintext(
    collection: &str,
    record_id: Uuid,
    plaintext: &SyncPlaintext,
) -> Result<(), String> {
    let plaintext_json = serde_json::to_string(plaintext).map_err(|_| "sync failed".to_string())?;
    with_sync_repository(|repository| {
        repository
            .upsert_record_state(collection, record_id, &plaintext_json, now_ms()?)
            .map_err(|error| error.to_string())
    })
}

fn tick_local_hlc(device_id: &str) -> Result<Hlc, String> {
    let mut clock = match get_setting(SYNC_LOCAL_HLC_SETTING_KEY.to_string())? {
        Some(encoded) if !encoded.is_empty() => {
            Hlc::decode(&encoded).unwrap_or_else(|_| Hlc::new(device_id.to_string()))
        }
        _ => Hlc::new(device_id.to_string()),
    };
    let hlc = clock.now(now_ms()?);
    set_setting(
        SYNC_LOCAL_HLC_SETTING_KEY.to_string(),
        hlc.encode().map_err(|_| "sync failed".to_string())?,
    )?;
    Ok(hlc)
}

fn active_sync_context() -> Option<ActiveSyncContext> {
    let state = core_state().ok()?;
    let account = account_runtime_state();
    let session = account.session.clone()?;
    if !session.logged_in {
        return None;
    }
    let keys = account.keys.as_ref()?;
    let tenant_id = parse_uuid(session.tenant_id.as_deref()?).ok()?;
    let device_id = session.device_id.clone()?;
    let sync_keys = LocalSyncKeys {
        tenant_root_dek: *keys.tenant_root_dek,
        list_deks: keys
            .list_deks
            .iter()
            .map(|entry| (entry.list_id.clone(), *entry.dek))
            .collect(),
    };
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

fn dek_for_task_list(keys: &LocalSyncKeys, list_id: &str) -> Option<[u8; 32]> {
    keys.list_deks
        .iter()
        .find(|(id, _)| id == list_id)
        .map(|(_, dek)| *dek)
        .or_else(|| keys.list_deks.first().map(|(_, dek)| *dek))
}

fn record_hlc_or_initial(plaintext: &SyncPlaintext) -> Hlc {
    plaintext
        .record_hlc()
        .cloned()
        .unwrap_or_else(|| Hlc::new("sync"))
}

fn task_plaintext(task: &Task, hlc: Hlc) -> SyncPlaintext {
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

fn list_plaintext(list: &List, hlc: Hlc) -> SyncPlaintext {
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

fn task_from_plaintext(
    id: Uuid,
    existing: Option<&Task>,
    plaintext: &SyncPlaintext,
) -> Result<Task, String> {
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

fn list_from_plaintext(
    id: Uuid,
    existing: Option<&List>,
    plaintext: &SyncPlaintext,
) -> Result<List, String> {
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

fn option_uuid_value(value: Option<Uuid>) -> Value {
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
        .map(parse_uuid)
        .transpose()
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
            let outcome =
                run_async(client.register(&email, &password, device_name.as_deref(), &device_key))
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
    Ok(AccountAuthResultDto {
        session,
        recovery_key: None,
    })
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

fn account_runtime_state() -> std::sync::MutexGuard<'static, AccountRuntimeState> {
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

fn sync_runtime_state() -> std::sync::MutexGuard<'static, SyncRuntimeState> {
    SYNC_STATE
        .get_or_init(|| Mutex::new(SyncRuntimeState::default()))
        .lock()
        .expect("sync runtime state mutex poisoned")
}

fn sync_status_dto(logged_in: bool) -> SyncStatusDto {
    let state = sync_runtime_state();
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

fn run_async<T, E>(future: impl std::future::Future<Output = Result<T, E>>) -> Result<T, E> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("tokio runtime can be created for bridge requests")
        .block_on(future)
}

/// Opens a fresh SQLCipher connection per API call.
///
/// `rusqlite::Connection` is not `Sync`, so the bridge does not keep a shared
/// connection in global state. This is simple and robust for FRB thread pools,
/// but has open/PRAGMA overhead; pooling can be considered in a later task.
fn with_task_repository<T>(
    f: impl FnOnce(&mut SqliteTaskRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteTaskRepository::new(connection);
    f(&mut repository)
}

/// Opens a fresh SQLCipher connection per API call.
///
/// See `with_task_repository` for the connection management tradeoff.
fn with_list_repository<T>(
    f: impl FnOnce(&mut SqliteListRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteListRepository::new(connection);
    f(&mut repository)
}

/// Opens a fresh SQLCipher connection per sync-state API call.
///
/// See `with_task_repository` for the connection management tradeoff.
fn with_sync_repository<T>(
    f: impl FnOnce(&mut SqliteSyncStateRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteSyncStateRepository::new(connection);
    f(&mut repository)
}

/// Opens a fresh SQLCipher connection per settings API call.
///
/// See `with_task_repository` for the connection management tradeoff.
fn with_settings_repository<T>(
    f: impl FnOnce(&mut SqliteSettingsRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteSettingsRepository::new(connection);
    f(&mut repository)
}

/// Opens a fresh SQLCipher connection per reminder API call.
///
/// See `with_task_repository` for the connection management tradeoff.
fn with_reminder_repository<T>(
    f: impl FnOnce(&mut SqliteReminderRepository) -> Result<T, String>,
) -> Result<T, String> {
    let state = core_state()?;
    let connection = open_encrypted(&state.db_path, &state.db_key).map_err(|e| e.to_string())?;
    let mut repository = SqliteReminderRepository::new(connection);
    f(&mut repository)
}

fn core_state() -> Result<&'static CoreState, String> {
    CORE_STATE
        .get()
        .ok_or_else(|| "core not initialized; call init_core first".to_string())
}

fn now_ms() -> Result<i64, String> {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?;

    i64::try_from(duration.as_millis()).map_err(|_| "current time exceeds i64 range".to_string())
}

fn parse_uuid(value: &str) -> Result<Uuid, String> {
    Uuid::from_str(value).map_err(|error| error.to_string())
}

fn parse_status(value: &str) -> Result<TaskStatus, String> {
    match value {
        "todo" => Ok(TaskStatus::Todo),
        "in_progress" => Ok(TaskStatus::InProgress),
        "done" => Ok(TaskStatus::Done),
        "wont_do" => Ok(TaskStatus::WontDo),
        other => Err(format!("invalid task status: {other}")),
    }
}

fn load_reorder_boundary(
    repository: &SqliteTaskRepository,
    boundary_id: Uuid,
    task: &Task,
) -> Result<Task, String> {
    let boundary = repository
        .get(boundary_id)
        .map_err(|error| error.to_string())?;
    if boundary.list_id != task.list_id {
        return Err("reorder boundary belongs to a different list".to_string());
    }
    if boundary.parent_task_id != task.parent_task_id {
        return Err("reorder boundary belongs to a different parent".to_string());
    }
    Ok(boundary)
}

fn count_to_i32(count: usize) -> Result<i32, String> {
    i32::try_from(count).map_err(|_| "count exceeds i32 range".to_string())
}

fn status_to_string(status: TaskStatus) -> String {
    match status {
        TaskStatus::Todo => "todo",
        TaskStatus::InProgress => "in_progress",
        TaskStatus::Done => "done",
        TaskStatus::WontDo => "wont_do",
    }
    .to_string()
}

fn list_to_dto(list: List) -> ListDto {
    ListDto {
        id: list.id.to_string(),
        name: list.name,
        color: list.color,
        icon: list.icon,
        org_id: list.org_id.map(|id| id.to_string()),
        sort_order: list.sort_order,
        is_default: list.is_default,
        archived_at: list.archived_at,
        created_at: list.created_at,
        updated_at: list.updated_at,
    }
}

fn task_to_dto(task: Task) -> TaskDto {
    TaskDto {
        id: task.id.to_string(),
        list_id: task.list_id.to_string(),
        parent_task_id: task.parent_task_id.map(|id| id.to_string()),
        title: task.title,
        note: task.note,
        status: status_to_string(task.status),
        priority: task.priority,
        due_at: task.due_at,
        scheduled_at: task.scheduled_at,
        estimated_minutes: task.estimated_minutes,
        sort_order: task.sort_order,
        completed_at: task.completed_at,
        closed_reason: task.closed_reason,
        deleted_at: task.deleted_at,
        assignee: task.assignee.map(|id| id.to_string()),
        created_at: task.created_at,
        updated_at: task.updated_at,
    }
}

fn home_task_to_dto(home_task: HomeTask) -> HomeTaskDto {
    HomeTaskDto {
        task: task_to_dto(home_task.task),
        list_name: home_task.list_name,
        is_home_target: home_task.is_home_target,
    }
}

fn task_undo_to_dto(entry: TaskUndoEntry) -> TaskUndoDto {
    TaskUndoDto {
        id: entry.id.to_string(),
        operation_type: task_undo_operation_to_string(entry.operation_type),
        task_id: entry.task_id.to_string(),
        list_id: entry.list_id.to_string(),
        task_title: entry.before_snapshot.title,
        created_at: entry.created_at,
    }
}

fn reminder_to_dto(reminder: Reminder) -> ReminderDto {
    ReminderDto {
        id: reminder.id.to_string(),
        task_id: reminder.task_id.to_string(),
        remind_at: reminder.remind_at,
        snoozed_until: reminder.snoozed_until,
        created_at: reminder.created_at,
    }
}

fn task_undo_operation_to_string(operation_type: TaskUndoOperation) -> String {
    match operation_type {
        TaskUndoOperation::Delete => "delete",
        TaskUndoOperation::Complete => "complete",
        TaskUndoOperation::Edit => "edit",
    }
    .to_string()
}

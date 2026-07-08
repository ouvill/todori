use std::{
    path::PathBuf,
    str::FromStr,
    sync::{Mutex, OnceLock},
    time::{SystemTime, UNIX_EPOCH},
};

use todori_crypto::derive_local_db_key;
use todori_domain::{
    archive_list as domain_archive_list, fractional_index_after, fractional_index_between,
    new_list, new_task, rename_list as domain_rename_list, transition_task,
    unarchive_list as domain_unarchive_list, update_due_at, update_note, update_priority,
    update_title, validate_parent_for, List, Task, TaskStatus, Uuid,
};
use todori_storage::{
    open_encrypted, HomeTask, ListRepository, Reminder, ReminderRepository, SettingsRepository,
    SqliteListRepository, SqliteReminderRepository, SqliteSettingsRepository, SqliteTaskRepository,
    StorageError, TaskRepository, TaskUndoEntry, TaskUndoOperation,
};
use todori_sync::account::{AccountClient, AccountKeyMaterial};
use zeroize::Zeroize;

use crate::dev_key_store::{
    delete_account_secret, load_account_secret, load_or_create_device_key, store_account_secret,
    AccountSecretKind,
};

static CORE_STATE: OnceLock<CoreState> = OnceLock::new();
static ACCOUNT_STATE: OnceLock<Mutex<AccountRuntimeState>> = OnceLock::new();

const SYNC_SERVER_URL_SETTING_KEY: &str = "sync_server_url";
const DEFAULT_SYNC_SERVER_URL: &str = "http://localhost:3000";
const ACCOUNT_EMAIL_SETTING_KEY: &str = "account_email";
const ACCOUNT_USER_ID_SETTING_KEY: &str = "account_user_id";
const ACCOUNT_TENANT_ID_SETTING_KEY: &str = "account_tenant_id";
const ACCOUNT_DEVICE_ID_SETTING_KEY: &str = "account_device_id";
const ACCOUNT_SESSION_EXPIRES_AT_SETTING_KEY: &str = "account_session_expires_at";

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
        Ok(task_to_dto(updated))
    })
}

pub fn delete_task(task_id: String) -> Result<(), String> {
    let task_id = parse_uuid(&task_id)?;
    with_task_repository(|repository| {
        repository
            .delete_subtree(task_id)
            .map(|_| ())
            .map_err(|error| error.to_string())
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
            .map(|_| ())
            .map_err(|error| error.to_string())
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

fn run_async<T>(
    future: impl std::future::Future<Output = Result<T, todori_sync::account::AccountClientError>>,
) -> Result<T, todori_sync::account::AccountClientError> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("tokio runtime can be created for account requests")
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

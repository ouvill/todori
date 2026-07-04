use std::{
    path::PathBuf,
    str::FromStr,
    sync::OnceLock,
    time::{SystemTime, UNIX_EPOCH},
};

use todori_crypto::{derive_local_db_key, ensure_device_key};
use todori_domain::{
    delete_task as domain_delete_task, new_list, new_task, restore_task as domain_restore_task,
    transition_task, update_due_at, update_note, update_priority, update_title, List, Task,
    TaskStatus, Uuid,
};
use todori_storage::{
    open_encrypted, ListRepository, SqliteListRepository, SqliteTaskRepository, TaskRepository,
};

use crate::dev_key_store::FileDeviceKeyStore;

static CORE_STATE: OnceLock<CoreState> = OnceLock::new();

struct CoreState {
    db_path: PathBuf,
    db_key: [u8; 32],
}

pub struct ListDto {
    pub id: String,
    pub name: String,
    pub color: String,
    pub icon: String,
    pub org_id: Option<String>,
    pub sort_order: String,
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
/// This creates or loads a development plaintext `device.key`, derives the
/// SQLCipher key, initializes `<db_dir>/todori.db`, and stores only the DB path
/// plus derived key in process-global state. Reinitializing with the same DB
/// path succeeds idempotently; reinitializing with a different DB path returns
/// an error because `OnceLock` cannot safely swap process-global state.
pub fn init_core(db_dir: String) -> Result<(), String> {
    let db_dir = PathBuf::from(db_dir);
    std::fs::create_dir_all(&db_dir).map_err(|error| error.to_string())?;

    let mut key_store = FileDeviceKeyStore::new(&db_dir);
    let device_key = ensure_device_key(&mut key_store).map_err(|error| error.to_string())?;
    let db_key = derive_local_db_key(&device_key);
    let db_path = db_dir.join("todori.db");

    open_encrypted(&db_path, &db_key).map_err(|error| error.to_string())?;

    let new_state = CoreState { db_path, db_key };
    match CORE_STATE.get() {
        Some(existing) if existing.db_path == new_state.db_path => Ok(()),
        Some(_) => Err("core already initialized with a different database path".to_string()),
        None => CORE_STATE
            .set(new_state)
            .map_err(|_| "core already initialized".to_string()),
    }
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

/// Creates a task using the caller-provided fractional `sort_order`.
///
/// Automatic fractional index generation is a later M3 concern and is not done
/// in this bridge layer.
pub fn create_task(list_id: String, title: String, sort_order: String) -> Result<TaskDto, String> {
    let list_id = parse_uuid(&list_id)?;
    let task =
        new_task(list_id, None, title, sort_order, now_ms()?).map_err(|error| error.to_string())?;
    with_task_repository(|repository| {
        repository
            .insert(task.clone())
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
        let task = repository.get(task_id).map_err(|error| error.to_string())?;
        let task = update_title(task, title, now_ms).map_err(|error| error.to_string())?;
        let task = update_note(task, note, now_ms).map_err(|error| error.to_string())?;
        let task = update_priority(task, priority, now_ms).map_err(|error| error.to_string())?;
        let updated = update_due_at(task, due_at, now_ms).map_err(|error| error.to_string())?;
        repository
            .update(updated.clone())
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
        let task = repository.get(task_id).map_err(|error| error.to_string())?;
        let updated = transition_task(task, status, closed_reason, now_ms)
            .map_err(|error| error.to_string())?;
        repository
            .update(updated.clone())
            .map_err(|error| error.to_string())?;
        Ok(task_to_dto(updated))
    })
}

pub fn trash_task(task_id: String) -> Result<TaskDto, String> {
    let task_id = parse_uuid(&task_id)?;
    let now_ms = now_ms()?;

    with_task_repository(|repository| {
        let task = repository.get(task_id).map_err(|error| error.to_string())?;
        let updated = domain_delete_task(task, now_ms).map_err(|error| error.to_string())?;
        repository
            .update(updated.clone())
            .map_err(|error| error.to_string())?;
        Ok(task_to_dto(updated))
    })
}

pub fn restore_task(task_id: String) -> Result<TaskDto, String> {
    let task_id = parse_uuid(&task_id)?;
    let now_ms = now_ms()?;

    with_task_repository(|repository| {
        let task = repository.get(task_id).map_err(|error| error.to_string())?;
        let updated = domain_restore_task(task, now_ms).map_err(|error| error.to_string())?;
        repository
            .update(updated.clone())
            .map_err(|error| error.to_string())?;
        Ok(task_to_dto(updated))
    })
}

pub fn get_trashed_tasks() -> Result<Vec<TaskDto>, String> {
    with_task_repository(|repository| {
        repository
            .list_trashed()
            .map_err(|error| error.to_string())
            .map(|tasks| tasks.into_iter().map(task_to_dto).collect())
    })
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

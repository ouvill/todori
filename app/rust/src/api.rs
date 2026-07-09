use std::{path::PathBuf, str::FromStr};

use todori_crypto::{derive_local_db_key, load_or_create_device_key};
use todori_domain::{
    archive_list as domain_archive_list, fractional_index_after, fractional_index_between,
    new_list, new_task, rename_list as domain_rename_list, transition_task,
    unarchive_list as domain_unarchive_list, update_due_at, update_note, update_priority,
    update_title, validate_parent_for, List, Task, TaskStatus, Uuid,
};
use todori_storage::{
    open_encrypted, HomeTask, ListRepository, Reminder, ReminderRepository, SettingsRepository,
    SqliteListRepository, SqliteTaskRepository, StorageError, TaskRepository, TaskUndoEntry,
    TaskUndoOperation,
};

use crate::support::{
    core_state, enqueue_list_sync, enqueue_task_sync, ensure_list_dek_for_list,
    local_mutation_state, now_ms, preflight_sync_mutation, with_list_repository,
    with_reminder_repository, with_settings_repository, with_task_repository, LocalMutationState,
};

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

    let new_state = crate::support::CoreState {
        db_dir,
        db_path,
        db_key,
    };
    crate::support::init_core_state(new_state)
}

pub fn get_sync_server_url() -> Result<String, String> {
    crate::support::get_sync_server_url()
}

pub fn set_sync_server_url(server_url: String) -> Result<(), String> {
    crate::support::set_sync_server_url(server_url)
}

pub fn get_account_session_state() -> Result<AccountSessionStateDto, String> {
    crate::support::get_account_session_state()
}

pub fn account_register(
    email: String,
    password: String,
    server_url: Option<String>,
    device_name: Option<String>,
) -> Result<AccountAuthResultDto, String> {
    crate::support::account_register(email, password, server_url, device_name)
}

pub fn account_login(
    email: String,
    password: String,
    server_url: Option<String>,
    device_name: Option<String>,
) -> Result<AccountAuthResultDto, String> {
    crate::support::account_login(email, password, server_url, device_name)
}

pub fn account_logout() -> Result<(), String> {
    crate::support::account_logout()
}

pub fn get_sync_status() -> Result<SyncStatusDto, String> {
    crate::support::get_sync_status()
}

pub fn sync_now() -> Result<SyncStatusDto, String> {
    crate::support::sync_now()
}

/// Creates a list using the caller-provided fractional `sort_order`.
///
/// Automatic fractional index generation is a later M3 concern and is not done
/// in this bridge layer.
pub fn create_list(name: String, sort_order: String) -> Result<ListDto, String> {
    preflight_sync_mutation()?;
    let list = new_list(name, sort_order, now_ms()?).map_err(|error| error.to_string())?;
    ensure_list_dek_for_list(list.id)?;
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
    preflight_sync_mutation()?;
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
    preflight_sync_mutation()?;
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
    preflight_sync_mutation()?;
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
    preflight_sync_mutation()?;
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
    preflight_sync_mutation()?;
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

    match local_mutation_state()? {
        LocalMutationState::Ready(sync) => {
            let state = core_state()?;
            let client = todori_client::Client::new(state.db_path.clone(), state.db_key);
            let updated = client
                .update_task(
                    todori_client::UpdateTaskInput {
                        task_id,
                        title,
                        note,
                        priority,
                        due_at,
                        now_ms,
                    },
                    &sync,
                )
                .map_err(|error| error.to_string())?;
            return Ok(task_to_dto(updated));
        }
        LocalMutationState::AccountBoundUnavailable => {
            return Err("account-bound local sync keys are unavailable".to_string());
        }
        LocalMutationState::Anonymous => {}
    }

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
    preflight_sync_mutation()?;
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
    preflight_sync_mutation()?;
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
    preflight_sync_mutation()?;
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
    preflight_sync_mutation()?;
    let undo_id = parse_uuid(&undo_id)?;
    let now_ms = now_ms()?;
    with_task_repository(|repository| {
        let task = repository
            .undo_task_operation(undo_id, now_ms)
            .map_err(|error| error.to_string())?;
        enqueue_task_sync(&task, false)?;
        Ok(task_to_dto(task))
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

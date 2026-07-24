use std::fmt::Write as _;

use taskveil_client::chrono::{DateTime, Utc};
use taskveil_client::{
    pomodoro_target_reached_at as domain_pomodoro_target_reached_at, AccountAuthResult,
    AccountSessionState, ActiveTimerSession, BillingState, CalendarOccurrenceKind,
    CalendarOccurrenceView, CalendarRange, CivilDate, ClientError, CompletedTimerSession,
    CreateScheduleCommand, CreateTaskCommand, HomeTaskView, List, OrganizationSafetyState,
    RealtimeTicket, RecurrenceSchedule, ReminderView, ReorderTaskCommand,
    ReplaceTemplateSnapshotCommand, SaveTemplateCommand, SetTaskStatusCommand, SettlementSummary,
    Streak, SyncStatus, Task, TaskDue, TaskStatus, TaskTemplate, TaskUndoKind, TaskUndoView,
    TemplateNode, TimerFinishKind, TimerMode, TimerPhase, TimerRunState, UpdateScheduleCommand,
    UpdateTaskCommand, UpdateTemplateCommand, UtcInstant, Uuid,
};

use crate::client_handle::{client, init_client};

pub struct ListDto {
    pub id: String,
    pub name: String,
    pub color: String,
    pub icon: String,
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
    pub due: Option<TaskDueDto>,
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

pub struct TemplateNodeDto {
    pub node_key: String,
    pub parent_node_key: Option<String>,
    pub sibling_order: u32,
    pub title: String,
    pub note: String,
    pub priority: i32,
    pub estimated_minutes: Option<i32>,
}

pub struct TemplateDto {
    pub id: String,
    pub name: String,
    pub default_list_id: Option<String>,
    pub snapshot_revision: String,
    pub nodes: Vec<TemplateNodeDto>,
    pub created_at: i64,
    pub updated_at: i64,
}

pub struct ScheduleDto {
    pub id: String,
    pub template_id: String,
    pub rrule: String,
    pub starts_at: i64,
    pub time_zone: String,
    pub next_run_at: Option<i64>,
    pub enabled: bool,
    pub config_revision: String,
    pub created_at: i64,
    pub updated_at: i64,
}

pub struct StreakDto {
    pub current: u32,
    pub finalized: bool,
}

pub struct SettlementSummaryDto {
    pub generated_occurrences: u32,
    pub generated_tasks: u32,
    pub has_more: bool,
    pub outbox_changed: bool,
}

pub enum TaskDueInput {
    Date {
        due_on: String,
    },
    DateTime {
        due_at: DateTime<Utc>,
        time_zone: String,
    },
}

pub enum TaskDueDto {
    Date {
        due_on: String,
    },
    DateTime {
        due_at: DateTime<Utc>,
        time_zone: String,
    },
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

pub struct CalendarRangeInput {
    pub start_on: String,
    pub end_on: String,
    pub start_at: DateTime<Utc>,
    pub end_at: DateTime<Utc>,
}

pub enum CalendarOccurrenceKindDto {
    DateDue {
        due_on: String,
    },
    DateTimeDue {
        due_at: DateTime<Utc>,
        time_zone: String,
    },
    Scheduled {
        scheduled_at: DateTime<Utc>,
    },
    Completed {
        completed_at: DateTime<Utc>,
    },
}

pub struct CalendarOccurrenceDto {
    pub task: TaskDto,
    pub list_name: String,
    pub list_archived: bool,
    pub kind: CalendarOccurrenceKindDto,
}

pub enum TimerModeDto {
    Pomodoro,
    Stopwatch,
}

pub enum TimerPhaseDto {
    Work,
    ShortBreak,
    LongBreak,
}

pub enum TimerRunStateDto {
    Running,
    Paused,
}

pub enum TimerFinishKindDto {
    Completed,
    Interrupted,
}

pub enum ActiveTimerStartOutcomeDto {
    Started,
    Conflict,
}

pub struct ActiveTimerSessionDto {
    pub session_id: String,
    pub task_id: Option<String>,
    pub mode: TimerModeDto,
    pub phase: TimerPhaseDto,
    pub state: TimerRunStateDto,
    pub started_at: DateTime<Utc>,
    pub last_resumed_at: Option<DateTime<Utc>>,
    pub accumulated_active_ms: i64,
    pub target_duration_ms: Option<i64>,
}

pub struct CompletedTimerSessionDto {
    pub id: String,
    pub task_id: String,
    pub mode: TimerModeDto,
    pub finish_kind: TimerFinishKindDto,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub active_duration_ms: i64,
    pub created_at: DateTime<Utc>,
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
pub struct BillingStateDto {
    pub provider: String,
    pub provider_app_user_id: String,
    pub lookup_key: String,
    pub status: String,
    pub sync_allowed: bool,
    pub store_product_identifier: Option<String>,
    pub expires_at: Option<i64>,
    pub grace_expires_at: Option<i64>,
    pub will_renew: Option<bool>,
    pub environment: String,
    pub updated_at: Option<i64>,
}

pub enum SyncNowOutcomeDto {
    Synced { status: SyncStatusDto },
    BillingRequired,
}

pub struct OrganizationSafetyStateDto {
    pub owner_user_id: String,
    pub member_user_id: String,
    pub digest: String,
    pub decimal: String,
    pub qr_payload: String,
    pub verification_state: String,
    pub owner_confirmed: bool,
    pub member_confirmed: bool,
}

pub struct RealtimeTicketDto {
    pub websocket_url: String,
    pub ticket: String,
    pub expires_at: DateTime<Utc>,
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
    pub missing_key_quarantined_count: i32,
    pub corruption_quarantined_count: i32,
    pub resolved_quarantine_count: i32,
    pub upgrade_required: bool,
}

pub fn greet(name: String) -> String {
    format!("Hello {name} from taskveil-core")
}

pub fn get_local_time_zone() -> Result<String, String> {
    client_result(client()?.local_time_zone())
}

pub fn create_draft_task(title: String) -> String {
    let id = Uuid::now_v7();
    let list_id = Uuid::now_v7();
    format!(
        concat!(
            "{{\"id\":\"{}\",\"list_id\":\"{}\",\"parent_task_id\":null,",
            "\"title\":{},\"note\":\"\",\"status\":\"todo\",\"priority\":0,",
            "\"due\":null,\"scheduled_at\":null,\"estimated_minutes\":null,",
            "\"sort_order\":\"a0\",\"completed_at\":null,\"closed_reason\":null,",
            "\"deleted_at\":null,\"assignee\":null,\"created_at\":0,\"updated_at\":0}}"
        ),
        id,
        list_id,
        json_string(&title),
    )
}

/// Initializes Taskveil core for the process using `db_dir`.
///
/// This creates or loads a platform Device Key, derives the SQLCipher key,
/// initializes `<db_dir>/taskveil.db`, and stores the process-global client
/// profile. Reinitializing with the same DB path succeeds idempotently;
/// reinitializing with a different DB path returns an error.
pub fn init_core(db_dir: String, default_inbox_name: String) -> Result<(), String> {
    init_client(db_dir, default_inbox_name)
}

/// Rotates the local Device Key and SQLCipher key using the crash-recovery
/// capsule protocol. No key material crosses the Flutter bridge.
pub fn rotate_device_key() -> Result<i64, String> {
    client()?
        .rotate_device_key()
        .and_then(|generation| i64::try_from(generation).map_err(|_| ClientError::LocalKeyState))
        .map_err(|error| error.to_string())
}

pub fn get_sync_server_url() -> Result<String, String> {
    client_result(client()?.sync_server_url())
}

pub fn set_sync_server_url(server_url: String) -> Result<(), String> {
    client_result(client()?.set_sync_server_url(server_url))
}

pub fn get_account_session_state() -> Result<AccountSessionStateDto, String> {
    client_result(client()?.account_session_state()).map(account_session_to_dto)
}

pub async fn account_register(
    email: String,
    password: String,
    server_url: Option<String>,
    device_name: Option<String>,
) -> Result<AccountAuthResultDto, String> {
    client()?
        .account_register(email, password, server_url, device_name)
        .await
        .map_err(|error| error.to_string())
        .map(account_auth_to_dto)
}

pub async fn account_login(
    email: String,
    password: String,
    server_url: Option<String>,
    device_name: Option<String>,
) -> Result<AccountAuthResultDto, String> {
    client()?
        .account_login(email, password, server_url, device_name)
        .await
        .map_err(|error| error.to_string())
        .map(account_auth_to_dto)
}

pub async fn account_logout() -> Result<(), String> {
    client()?
        .account_logout()
        .await
        .map_err(|error| error.to_string())
}

pub async fn organization_safety_number(
    tenant_id: String,
    member_user_id: String,
) -> Result<OrganizationSafetyStateDto, String> {
    client()?
        .organization_safety_number(tenant_id, member_user_id)
        .await
        .map_err(|error| error.to_string())
        .map(organization_safety_to_dto)
}

pub async fn confirm_organization_safety_number(
    tenant_id: String,
    member_user_id: String,
    digest: String,
) -> Result<OrganizationSafetyStateDto, String> {
    client()?
        .confirm_organization_safety_number(tenant_id, member_user_id, digest)
        .await
        .map_err(|error| error.to_string())
        .map(organization_safety_to_dto)
}

pub fn get_sync_status() -> Result<SyncStatusDto, String> {
    client_result(client()?.sync_status()).map(sync_status_to_dto)
}

pub async fn sync_now() -> Result<SyncStatusDto, String> {
    client()?
        .sync_now()
        .await
        .map_err(|error| error.to_string())
        .map(sync_status_to_dto)
}

pub async fn sync_now_outcome() -> Result<SyncNowOutcomeDto, String> {
    match client()?.sync_now().await {
        Ok(status) => Ok(SyncNowOutcomeDto::Synced {
            status: sync_status_to_dto(status),
        }),
        Err(ClientError::EntitlementRequired) => Ok(SyncNowOutcomeDto::BillingRequired),
        Err(error) => Err(error.to_string()),
    }
}

pub async fn billing_bootstrap() -> Result<BillingStateDto, String> {
    client()?
        .billing_bootstrap()
        .await
        .map(billing_state_to_dto)
        .map_err(|error| error.to_string())
}

pub async fn refresh_billing() -> Result<BillingStateDto, String> {
    client()?
        .refresh_billing()
        .await
        .map(billing_state_to_dto)
        .map_err(|error| error.to_string())
}

pub fn get_cached_billing() -> Result<Option<BillingStateDto>, String> {
    client_result(client()?.cached_billing()).map(|state| state.map(billing_state_to_dto))
}

pub async fn get_realtime_ticket() -> Result<RealtimeTicketDto, String> {
    client()?
        .realtime_ticket()
        .await
        .map_err(|error| error.to_string())
        .map(realtime_ticket_to_dto)
}

/// Creates a list using a client-owned fractional `sort_order`.
///
/// `sort_order` remains in the FRB contract for compatibility, but rank
/// generation and rebalance are owned by `TaskveilClient`.
pub fn create_list(name: String, sort_order: String) -> Result<ListDto, String> {
    let _legacy_caller_rank = sort_order;
    client_result(client()?.create_list(name)).map(list_to_dto)
}

pub fn get_lists() -> Result<Vec<ListDto>, String> {
    client_result(client()?.get_lists()).map(|lists| lists.into_iter().map(list_to_dto).collect())
}

pub fn get_archived_lists() -> Result<Vec<ListDto>, String> {
    client_result(client()?.get_archived_lists())
        .map(|lists| lists.into_iter().map(list_to_dto).collect())
}

pub fn get_templates() -> Result<Vec<TemplateDto>, String> {
    client_result(client()?.get_templates())
        .map(|templates| templates.into_iter().map(template_to_dto).collect())
}

pub fn get_template_schedules(template_id: String) -> Result<Vec<ScheduleDto>, String> {
    client_result(client()?.get_template_schedules(parse_uuid(&template_id)?))
        .map(|schedules| schedules.into_iter().map(schedule_to_dto).collect())
}

pub fn validate_recurrence_rule(
    rrule: String,
    starts_at: i64,
    time_zone: String,
) -> Result<String, String> {
    client_result(client()?.validate_recurrence_rule(rrule, starts_at, time_zone))
}

pub fn save_task_as_template(
    task_id: String,
    name: String,
    default_list_id: Option<String>,
) -> Result<TemplateDto, String> {
    let command = SaveTemplateCommand {
        task_id: parse_uuid(&task_id)?,
        name,
        default_list_id: default_list_id.as_deref().map(parse_uuid).transpose()?,
    };
    client_result(client()?.save_task_as_template(command)).map(template_to_dto)
}

pub fn update_template(
    template_id: String,
    name: String,
    default_list_id: Option<String>,
) -> Result<TemplateDto, String> {
    let command = UpdateTemplateCommand {
        template_id: parse_uuid(&template_id)?,
        name,
        default_list_id: default_list_id.as_deref().map(parse_uuid).transpose()?,
    };
    client_result(client()?.update_template(command)).map(template_to_dto)
}

pub fn replace_template_snapshot(
    template_id: String,
    task_id: String,
) -> Result<TemplateDto, String> {
    let command = ReplaceTemplateSnapshotCommand {
        template_id: parse_uuid(&template_id)?,
        task_id: parse_uuid(&task_id)?,
    };
    client_result(client()?.replace_template_snapshot(command)).map(template_to_dto)
}

pub fn instantiate_template(template_id: String) -> Result<Vec<TaskDto>, String> {
    client_result(client()?.instantiate_template(parse_uuid(&template_id)?))
        .map(|tasks| tasks.into_iter().map(task_to_dto).collect())
}

pub fn create_schedule(
    template_id: String,
    rrule: String,
    starts_at: i64,
    time_zone: String,
) -> Result<ScheduleDto, String> {
    let command = CreateScheduleCommand {
        template_id: parse_uuid(&template_id)?,
        rrule,
        starts_at,
        time_zone,
    };
    client_result(client()?.create_schedule(command)).map(schedule_to_dto)
}

#[allow(clippy::too_many_arguments)]
pub fn update_schedule(
    schedule_id: String,
    rrule: String,
    starts_at: i64,
    time_zone: String,
    enabled: bool,
) -> Result<ScheduleDto, String> {
    let command = UpdateScheduleCommand {
        schedule_id: parse_uuid(&schedule_id)?,
        rrule,
        starts_at,
        time_zone,
        enabled,
    };
    client_result(client()?.update_schedule(command)).map(schedule_to_dto)
}

pub fn delete_schedule(schedule_id: String) -> Result<(), String> {
    client_result(client()?.delete_schedule(parse_uuid(&schedule_id)?))
}

pub fn delete_template(template_id: String) -> Result<(), String> {
    client_result(client()?.delete_template(parse_uuid(&template_id)?))
}

pub fn settle_due_schedules(at_ms: i64) -> Result<SettlementSummaryDto, String> {
    client_result(client()?.settle_due_schedules(at_ms)).map(settlement_to_dto)
}

pub fn get_schedule_streak(schedule_id: String, at_ms: i64) -> Result<StreakDto, String> {
    client_result(client()?.get_schedule_streak(parse_uuid(&schedule_id)?, at_ms))
        .map(streak_to_dto)
}

pub fn rename_list(list_id: String, name: String) -> Result<ListDto, String> {
    let list_id = parse_uuid(&list_id)?;
    client_result(client()?.rename_list(list_id, name)).map(list_to_dto)
}

pub fn archive_list(list_id: String) -> Result<ListDto, String> {
    let list_id = parse_uuid(&list_id)?;
    client_result(client()?.archive_list(list_id)).map(list_to_dto)
}

pub fn unarchive_list(list_id: String) -> Result<ListDto, String> {
    let list_id = parse_uuid(&list_id)?;
    client_result(client()?.unarchive_list(list_id)).map(list_to_dto)
}

/// Creates a task at the end of its sibling group using a client-generated
/// fractional `sort_order`.
#[allow(clippy::too_many_arguments)] // FRB exposes the complete atomic create command.
pub fn create_task(
    list_id: String,
    title: String,
    parent_task_id: Option<String>,
    due: Option<TaskDueInput>,
    note: Option<String>,
    priority: Option<i32>,
    scheduled_at: Option<i64>,
    estimated_minutes: Option<i32>,
) -> Result<TaskDto, String> {
    let command = CreateTaskCommand {
        list_id: parse_uuid(&list_id)?,
        title,
        parent_task_id: parent_task_id.as_deref().map(parse_uuid).transpose()?,
        due: due.map(parse_task_due).transpose()?,
        note,
        priority: priority.unwrap_or(0),
        scheduled_at,
        estimated_minutes,
    };
    client_result(client()?.create_task(command)).map(task_to_dto)
}

pub fn reorder_task(
    task_id: String,
    previous_task_id: Option<String>,
    next_task_id: Option<String>,
) -> Result<TaskDto, String> {
    let command = ReorderTaskCommand {
        task_id: parse_uuid(&task_id)?,
        previous_task_id: previous_task_id.as_deref().map(parse_uuid).transpose()?,
        next_task_id: next_task_id.as_deref().map(parse_uuid).transpose()?,
    };
    client_result(client()?.reorder_task(command)).map(task_to_dto)
}

pub fn get_tasks(list_id: String) -> Result<Vec<TaskDto>, String> {
    let list_id = parse_uuid(&list_id)?;
    client_result(client()?.get_tasks(list_id))
        .map(|tasks| tasks.into_iter().map(task_to_dto).collect())
}

pub fn get_active_timer_session() -> Result<Option<ActiveTimerSessionDto>, String> {
    client_result(client()?.get_active_timer_session())
        .map(|session| session.map(active_timer_to_dto))
}

pub fn start_active_timer_session(
    session: ActiveTimerSessionDto,
) -> Result<ActiveTimerStartOutcomeDto, String> {
    match client()?.start_active_timer_session(parse_active_timer(session)?) {
        Ok(()) => Ok(ActiveTimerStartOutcomeDto::Started),
        Err(ClientError::ActiveTimerConflict(_)) => Ok(ActiveTimerStartOutcomeDto::Conflict),
        Err(error) => Err(error.to_string()),
    }
}

pub fn update_active_timer_session(session: ActiveTimerSessionDto) -> Result<(), String> {
    client_result(client()?.update_active_timer_session(parse_active_timer(session)?))
}

pub fn pomodoro_target_reached_at(session: ActiveTimerSessionDto) -> Result<DateTime<Utc>, String> {
    let reached_at = domain_pomodoro_target_reached_at(&parse_active_timer(session)?)
        .map_err(|error| error.to_string())?;
    DateTime::<Utc>::from_timestamp_millis(reached_at)
        .ok_or_else(|| "timer target instant is out of range".to_string())
}

pub fn discard_active_timer_session(expected_session_id: String) -> Result<bool, String> {
    client_result(client()?.discard_active_timer_session(parse_uuid(&expected_session_id)?))
}

pub fn finish_active_timer_session(session: CompletedTimerSessionDto) -> Result<bool, String> {
    client_result(client()?.finish_active_timer_session(parse_completed_timer(session)?))
}

pub fn get_completed_timer_sessions(
    task_id: String,
) -> Result<Vec<CompletedTimerSessionDto>, String> {
    client_result(client()?.get_completed_timer_sessions(parse_uuid(&task_id)?))
        .map(|sessions| sessions.into_iter().map(completed_timer_to_dto).collect())
}

pub fn search_tasks(query: String) -> Result<Vec<TaskDto>, String> {
    client_result(client()?.search_tasks(&query))
        .map(|tasks| tasks.into_iter().map(task_to_dto).collect())
}

pub fn get_home_tasks(
    today_start_ms: i64,
    tomorrow_start_ms: i64,
) -> Result<Vec<HomeTaskDto>, String> {
    client_result(client()?.get_home_tasks(today_start_ms, tomorrow_start_ms))
        .map(|tasks| tasks.into_iter().map(home_task_to_dto).collect())
}

pub fn get_calendar_occurrences(
    range: CalendarRangeInput,
) -> Result<Vec<CalendarOccurrenceDto>, String> {
    let range = CalendarRange::new(
        CivilDate::parse(range.start_on).map_err(|error| error.to_string())?,
        CivilDate::parse(range.end_on).map_err(|error| error.to_string())?,
        UtcInstant::from_millis(range.start_at.timestamp_millis())
            .map_err(|error| error.to_string())?,
        UtcInstant::from_millis(range.end_at.timestamp_millis())
            .map_err(|error| error.to_string())?,
    )
    .map_err(|error| error.to_string())?;
    client_result(client()?.get_calendar_occurrences(range)).map(|occurrences| {
        occurrences
            .into_iter()
            .map(calendar_occurrence_to_dto)
            .collect()
    })
}

pub fn count_task_descendants(task_id: String) -> Result<i32, String> {
    let task_id = parse_uuid(&task_id)?;
    client_result(client()?.count_task_descendants(task_id)).and_then(count_to_i32)
}

pub fn count_tasks_in_list(list_id: String) -> Result<i32, String> {
    let list_id = parse_uuid(&list_id)?;
    client_result(client()?.count_tasks_in_list(list_id)).and_then(count_to_i32)
}

pub fn update_task(
    task_id: String,
    title: String,
    note: String,
    priority: i32,
    due: Option<TaskDueInput>,
    scheduled_at: Option<i64>,
    estimated_minutes: Option<i32>,
) -> Result<TaskDto, String> {
    let command = UpdateTaskCommand {
        task_id: parse_uuid(&task_id)?,
        title,
        note,
        priority,
        due: due.map(parse_task_due).transpose()?,
        scheduled_at,
        estimated_minutes,
    };
    client_result(client()?.update_task(command)).map(task_to_dto)
}

pub fn set_task_status(
    task_id: String,
    status: String,
    closed_reason: Option<String>,
) -> Result<TaskDto, String> {
    let command = SetTaskStatusCommand {
        task_id: parse_uuid(&task_id)?,
        status: parse_status(&status)?,
        closed_reason,
    };
    client_result(client()?.set_task_status(command)).map(task_to_dto)
}

pub fn delete_task(task_id: String) -> Result<(), String> {
    let task_id = parse_uuid(&task_id)?;
    client_result(client()?.delete_task(task_id))
}

pub fn delete_list(list_id: String) -> Result<(), String> {
    let list_id = parse_uuid(&list_id)?;
    client_result(client()?.delete_list(list_id))
}

pub fn get_latest_task_undo() -> Result<Option<TaskUndoDto>, String> {
    client_result(client()?.get_latest_task_undo()).map(|entry| entry.map(task_undo_to_dto))
}

pub fn undo_task_operation(undo_id: String) -> Result<TaskDto, String> {
    let undo_id = parse_uuid(&undo_id)?;
    client_result(client()?.undo_task_operation(undo_id)).map(task_to_dto)
}

pub fn get_setting(key: String) -> Result<Option<String>, String> {
    client_result(client()?.get_setting(&key))
}

pub fn set_setting(key: String, value: String) -> Result<(), String> {
    client_result(client()?.set_setting(&key, &value))
}

pub fn create_task_reminder(task_id: String, remind_at: i64) -> Result<ReminderDto, String> {
    let task_id = parse_uuid(&task_id)?;
    client_result(client()?.create_task_reminder(task_id, remind_at)).map(reminder_to_dto)
}

pub fn update_reminder(reminder_id: String, remind_at: i64) -> Result<ReminderDto, String> {
    let reminder_id = parse_uuid(&reminder_id)?;
    client_result(client()?.update_reminder(reminder_id, remind_at)).map(reminder_to_dto)
}

pub fn delete_reminder(reminder_id: String) -> Result<ReminderDto, String> {
    let reminder_id = parse_uuid(&reminder_id)?;
    client_result(client()?.delete_reminder(reminder_id)).map(reminder_to_dto)
}

pub fn clear_task_reminders(task_id: String) -> Result<Vec<ReminderDto>, String> {
    let task_id = parse_uuid(&task_id)?;
    client_result(client()?.clear_task_reminders(task_id))
        .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
}

pub fn get_task_reminders(task_id: String) -> Result<Vec<ReminderDto>, String> {
    let task_id = parse_uuid(&task_id)?;
    client_result(client()?.get_task_reminders(task_id))
        .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
}

pub fn get_task_subtree_reminders(task_id: String) -> Result<Vec<ReminderDto>, String> {
    let task_id = parse_uuid(&task_id)?;
    client_result(client()?.get_task_subtree_reminders(task_id))
        .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
}

pub fn get_list_reminders(list_id: String) -> Result<Vec<ReminderDto>, String> {
    let list_id = parse_uuid(&list_id)?;
    client_result(client()?.get_list_reminders(list_id))
        .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
}

pub fn list_pending_reminders(now_ms: i64) -> Result<Vec<ReminderDto>, String> {
    client_result(client()?.list_pending_reminders(now_ms))
        .map(|reminders| reminders.into_iter().map(reminder_to_dto).collect())
}

pub fn snooze_reminder(reminder_id: String, snoozed_until: i64) -> Result<ReminderDto, String> {
    let reminder_id = parse_uuid(&reminder_id)?;
    client_result(client()?.snooze_reminder(reminder_id, snoozed_until)).map(reminder_to_dto)
}

fn client_result<T>(result: Result<T, taskveil_client::ClientError>) -> Result<T, String> {
    result.map_err(|error| error.to_string())
}

fn parse_uuid(value: &str) -> Result<Uuid, String> {
    value.parse::<Uuid>().map_err(|error| error.to_string())
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

fn parse_task_due(input: TaskDueInput) -> Result<TaskDue, String> {
    match input {
        TaskDueInput::Date { due_on } => {
            TaskDue::date(due_on).map_err(|_| "invalid date-only due value".to_string())
        }
        TaskDueInput::DateTime { due_at, time_zone } => {
            TaskDue::date_time(due_at.timestamp_millis(), time_zone)
                .map_err(|_| "invalid datetime due value".to_string())
        }
    }
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
        due: task.due.map(task_due_to_dto),
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

fn template_to_dto(template: TaskTemplate) -> TemplateDto {
    TemplateDto {
        id: template.id.to_string(),
        name: template.name,
        default_list_id: template.default_list_id.map(|id| id.to_string()),
        snapshot_revision: template.snapshot_revision,
        nodes: template
            .snapshot
            .nodes
            .into_iter()
            .map(template_node_to_dto)
            .collect(),
        created_at: template.created_at,
        updated_at: template.updated_at,
    }
}

fn template_node_to_dto(node: TemplateNode) -> TemplateNodeDto {
    TemplateNodeDto {
        node_key: node.node_key,
        parent_node_key: node.parent_node_key,
        sibling_order: node.sibling_order,
        title: node.title,
        note: node.note,
        priority: node.priority,
        estimated_minutes: node.estimated_minutes,
    }
}

fn schedule_to_dto(schedule: RecurrenceSchedule) -> ScheduleDto {
    ScheduleDto {
        id: schedule.id.to_string(),
        template_id: schedule.template_id.to_string(),
        rrule: schedule.rrule,
        starts_at: schedule.starts_at,
        time_zone: schedule.time_zone,
        next_run_at: schedule.cursor.next_run_at(),
        enabled: schedule.enabled,
        config_revision: schedule.config_revision,
        created_at: schedule.created_at,
        updated_at: schedule.updated_at,
    }
}

fn streak_to_dto(streak: Streak) -> StreakDto {
    StreakDto {
        current: streak.current,
        finalized: streak.finalized,
    }
}

fn settlement_to_dto(summary: SettlementSummary) -> SettlementSummaryDto {
    SettlementSummaryDto {
        generated_occurrences: summary.generated_occurrences,
        generated_tasks: summary.generated_tasks,
        has_more: summary.has_more,
        outbox_changed: summary.outbox_changed,
    }
}

fn task_due_to_dto(due: TaskDue) -> TaskDueDto {
    match due {
        TaskDue::Date { due_on } => TaskDueDto::Date {
            due_on: due_on.to_string(),
        },
        TaskDue::DateTime { due_at, time_zone } => TaskDueDto::DateTime {
            due_at: DateTime::<Utc>::from_timestamp_millis(due_at.as_millis())
                .expect("UtcInstant is validated at construction"),
            time_zone: time_zone.to_string(),
        },
    }
}

fn home_task_to_dto(home_task: HomeTaskView) -> HomeTaskDto {
    HomeTaskDto {
        task: task_to_dto(home_task.task),
        list_name: home_task.list_name,
        is_home_target: home_task.is_home_target,
    }
}

fn calendar_occurrence_to_dto(occurrence: CalendarOccurrenceView) -> CalendarOccurrenceDto {
    CalendarOccurrenceDto {
        task: task_to_dto(occurrence.task),
        list_name: occurrence.list_name,
        list_archived: occurrence.list_archived,
        kind: match occurrence.kind {
            CalendarOccurrenceKind::DateDue { due_on } => CalendarOccurrenceKindDto::DateDue {
                due_on: due_on.to_string(),
            },
            CalendarOccurrenceKind::DateTimeDue { due_at, time_zone } => {
                CalendarOccurrenceKindDto::DateTimeDue {
                    due_at: instant_to_datetime(due_at),
                    time_zone: time_zone.to_string(),
                }
            }
            CalendarOccurrenceKind::Scheduled { scheduled_at } => {
                CalendarOccurrenceKindDto::Scheduled {
                    scheduled_at: instant_to_datetime(scheduled_at),
                }
            }
            CalendarOccurrenceKind::Completed { completed_at } => {
                CalendarOccurrenceKindDto::Completed {
                    completed_at: instant_to_datetime(completed_at),
                }
            }
        },
    }
}

fn instant_to_datetime(instant: UtcInstant) -> DateTime<Utc> {
    DateTime::<Utc>::from_timestamp_millis(instant.as_millis())
        .expect("UtcInstant is validated at construction")
}

fn parse_active_timer(value: ActiveTimerSessionDto) -> Result<ActiveTimerSession, String> {
    Ok(ActiveTimerSession {
        session_id: parse_uuid(&value.session_id)?,
        task_id: value.task_id.as_deref().map(parse_uuid).transpose()?,
        mode: parse_timer_mode(value.mode),
        phase: parse_timer_phase(value.phase),
        state: parse_timer_run_state(value.state),
        started_at: value.started_at.timestamp_millis(),
        last_resumed_at: value.last_resumed_at.map(|time| time.timestamp_millis()),
        accumulated_active_ms: value.accumulated_active_ms,
        target_duration_ms: value.target_duration_ms,
    })
}

fn parse_completed_timer(value: CompletedTimerSessionDto) -> Result<CompletedTimerSession, String> {
    Ok(CompletedTimerSession {
        id: parse_uuid(&value.id)?,
        task_id: parse_uuid(&value.task_id)?,
        mode: parse_timer_mode(value.mode),
        finish_kind: parse_timer_finish_kind(value.finish_kind),
        started_at: value.started_at.timestamp_millis(),
        ended_at: value.ended_at.timestamp_millis(),
        active_duration_ms: value.active_duration_ms,
        created_at: value.created_at.timestamp_millis(),
    })
}

fn active_timer_to_dto(value: ActiveTimerSession) -> ActiveTimerSessionDto {
    ActiveTimerSessionDto {
        session_id: value.session_id.to_string(),
        task_id: value.task_id.map(|id| id.to_string()),
        mode: timer_mode_to_dto(value.mode),
        phase: timer_phase_to_dto(value.phase),
        state: timer_run_state_to_dto(value.state),
        started_at: millis_to_datetime(value.started_at),
        last_resumed_at: value.last_resumed_at.map(millis_to_datetime),
        accumulated_active_ms: value.accumulated_active_ms,
        target_duration_ms: value.target_duration_ms,
    }
}

fn completed_timer_to_dto(value: CompletedTimerSession) -> CompletedTimerSessionDto {
    CompletedTimerSessionDto {
        id: value.id.to_string(),
        task_id: value.task_id.to_string(),
        mode: timer_mode_to_dto(value.mode),
        finish_kind: timer_finish_kind_to_dto(value.finish_kind),
        started_at: millis_to_datetime(value.started_at),
        ended_at: millis_to_datetime(value.ended_at),
        active_duration_ms: value.active_duration_ms,
        created_at: millis_to_datetime(value.created_at),
    }
}

fn millis_to_datetime(value: i64) -> DateTime<Utc> {
    DateTime::<Utc>::from_timestamp_millis(value).expect("domain timer timestamps are validated")
}

fn parse_timer_mode(value: TimerModeDto) -> TimerMode {
    match value {
        TimerModeDto::Pomodoro => TimerMode::Pomodoro,
        TimerModeDto::Stopwatch => TimerMode::Stopwatch,
    }
}

fn timer_mode_to_dto(value: TimerMode) -> TimerModeDto {
    match value {
        TimerMode::Pomodoro => TimerModeDto::Pomodoro,
        TimerMode::Stopwatch => TimerModeDto::Stopwatch,
    }
}

fn parse_timer_phase(value: TimerPhaseDto) -> TimerPhase {
    match value {
        TimerPhaseDto::Work => TimerPhase::Work,
        TimerPhaseDto::ShortBreak => TimerPhase::ShortBreak,
        TimerPhaseDto::LongBreak => TimerPhase::LongBreak,
    }
}

fn timer_phase_to_dto(value: TimerPhase) -> TimerPhaseDto {
    match value {
        TimerPhase::Work => TimerPhaseDto::Work,
        TimerPhase::ShortBreak => TimerPhaseDto::ShortBreak,
        TimerPhase::LongBreak => TimerPhaseDto::LongBreak,
    }
}

fn parse_timer_run_state(value: TimerRunStateDto) -> TimerRunState {
    match value {
        TimerRunStateDto::Running => TimerRunState::Running,
        TimerRunStateDto::Paused => TimerRunState::Paused,
    }
}

fn timer_run_state_to_dto(value: TimerRunState) -> TimerRunStateDto {
    match value {
        TimerRunState::Running => TimerRunStateDto::Running,
        TimerRunState::Paused => TimerRunStateDto::Paused,
    }
}

fn parse_timer_finish_kind(value: TimerFinishKindDto) -> TimerFinishKind {
    match value {
        TimerFinishKindDto::Completed => TimerFinishKind::Completed,
        TimerFinishKindDto::Interrupted => TimerFinishKind::Interrupted,
    }
}

fn timer_finish_kind_to_dto(value: TimerFinishKind) -> TimerFinishKindDto {
    match value {
        TimerFinishKind::Completed => TimerFinishKindDto::Completed,
        TimerFinishKind::Interrupted => TimerFinishKindDto::Interrupted,
    }
}

fn task_undo_to_dto(entry: TaskUndoView) -> TaskUndoDto {
    TaskUndoDto {
        id: entry.id.to_string(),
        operation_type: match entry.operation {
            TaskUndoKind::Delete => "delete",
            TaskUndoKind::Complete => "complete",
            TaskUndoKind::Edit => "edit",
        }
        .to_string(),
        task_id: entry.task_id.to_string(),
        list_id: entry.list_id.to_string(),
        task_title: entry.task_title,
        created_at: entry.created_at,
    }
}

fn reminder_to_dto(reminder: ReminderView) -> ReminderDto {
    ReminderDto {
        id: reminder.id.to_string(),
        task_id: reminder.task_id.to_string(),
        remind_at: reminder.remind_at,
        snoozed_until: reminder.snoozed_until,
        created_at: reminder.created_at,
    }
}

fn account_session_to_dto(session: AccountSessionState) -> AccountSessionStateDto {
    AccountSessionStateDto {
        logged_in: session.logged_in,
        email: session.email,
        user_id: session.user_id,
        tenant_id: session.tenant_id,
        device_id: session.device_id,
    }
}

fn realtime_ticket_to_dto(ticket: RealtimeTicket) -> RealtimeTicketDto {
    RealtimeTicketDto {
        websocket_url: ticket.websocket_url,
        ticket: ticket.ticket,
        expires_at: ticket.expires_at,
    }
}

fn account_auth_to_dto(result: AccountAuthResult) -> AccountAuthResultDto {
    AccountAuthResultDto {
        session: account_session_to_dto(result.session),
        recovery_key: result.recovery_key,
    }
}

fn billing_state_to_dto(state: BillingState) -> BillingStateDto {
    BillingStateDto {
        provider: state.provider,
        provider_app_user_id: state.provider_app_user_id,
        lookup_key: state.lookup_key,
        status: state.status,
        sync_allowed: state.sync_allowed,
        store_product_identifier: state.store_product_identifier,
        expires_at: state.expires_at,
        grace_expires_at: state.grace_expires_at,
        will_renew: state.will_renew,
        environment: state.environment,
        updated_at: state.updated_at,
    }
}

fn organization_safety_to_dto(state: OrganizationSafetyState) -> OrganizationSafetyStateDto {
    OrganizationSafetyStateDto {
        owner_user_id: state.owner_user_id,
        member_user_id: state.member_user_id,
        digest: state.digest,
        decimal: state.decimal,
        qr_payload: state.qr_payload,
        verification_state: state.verification_state,
        owner_confirmed: state.owner_confirmed,
        member_confirmed: state.member_confirmed,
    }
}

fn sync_status_to_dto(status: SyncStatus) -> SyncStatusDto {
    SyncStatusDto {
        logged_in: status.logged_in,
        running: status.running,
        last_success_at: status.last_success_at,
        last_failure_at: status.last_failure_at,
        last_error: status.last_error,
        pushed_count: saturating_i32(status.pushed_count),
        push_acked_count: saturating_i32(status.push_acked_count),
        push_superseded_count: saturating_i32(status.push_superseded_count),
        pulled_count: saturating_i32(status.pulled_count),
        applied_count: saturating_i32(status.applied_count),
        deleted_count: saturating_i32(status.deleted_count),
        decrypt_failed_count: saturating_i32(status.decrypt_failed_count),
        repush_count: saturating_i32(status.repush_count),
        missing_key_quarantined_count: saturating_i32(status.missing_key_quarantined_count),
        corruption_quarantined_count: saturating_i32(status.corruption_quarantined_count),
        resolved_quarantine_count: saturating_i32(status.resolved_quarantine_count),
        upgrade_required: status.upgrade_required,
    }
}

fn saturating_i32(value: usize) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

fn json_string(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len() + 2);
    encoded.push('"');
    for character in value.chars() {
        match character {
            '"' => encoded.push_str("\\\""),
            '\\' => encoded.push_str("\\\\"),
            '\u{08}' => encoded.push_str("\\b"),
            '\u{0c}' => encoded.push_str("\\f"),
            '\n' => encoded.push_str("\\n"),
            '\r' => encoded.push_str("\\r"),
            '\t' => encoded.push_str("\\t"),
            control if control <= '\u{1f}' => {
                write!(encoded, "\\u{:04x}", control as u32).expect("write to String")
            }
            other => encoded.push(other),
        }
    }
    encoded.push('"');
    encoded
}

#[cfg(test)]
mod tests {
    use std::future::Future;

    use super::*;

    fn assert_result_future<T>(future: impl Future<Output = Result<T, String>>) {
        drop(future);
    }

    #[test]
    #[allow(clippy::type_complexity)]
    fn all_public_function_signatures_remain_stable() {
        let _: fn(String) -> String = greet;
        let _: fn(String) -> String = create_draft_task;
        let _: fn(String, String) -> Result<(), String> = init_core;
        let _: fn() -> Result<String, String> = get_sync_server_url;
        let _: fn(String) -> Result<(), String> = set_sync_server_url;
        let _: fn() -> Result<AccountSessionStateDto, String> = get_account_session_state;
        assert_result_future(account_register(String::new(), String::new(), None, None));
        assert_result_future(account_login(String::new(), String::new(), None, None));
        assert_result_future(account_logout());
        let _: fn() -> Result<SyncStatusDto, String> = get_sync_status;
        assert_result_future(sync_now());
        assert_result_future(get_realtime_ticket());
        let _: fn(String, String) -> Result<ListDto, String> = create_list;
        let _: fn() -> Result<Vec<ListDto>, String> = get_lists;
        let _: fn() -> Result<Vec<ListDto>, String> = get_archived_lists;
        let _: fn(String, String) -> Result<ListDto, String> = rename_list;
        let _: fn(String) -> Result<ListDto, String> = archive_list;
        let _: fn(String) -> Result<ListDto, String> = unarchive_list;
        let _: fn(
            String,
            String,
            Option<String>,
            Option<TaskDueInput>,
            Option<String>,
            Option<i32>,
            Option<i64>,
            Option<i32>,
        ) -> Result<TaskDto, String> = create_task;
        let _: fn(String, Option<String>, Option<String>) -> Result<TaskDto, String> = reorder_task;
        let _: fn(String) -> Result<Vec<TaskDto>, String> = get_tasks;
        let _: fn() -> Result<Option<ActiveTimerSessionDto>, String> = get_active_timer_session;
        let _: fn(ActiveTimerSessionDto) -> Result<ActiveTimerStartOutcomeDto, String> =
            start_active_timer_session;
        let _: fn(ActiveTimerSessionDto) -> Result<(), String> = update_active_timer_session;
        let _: fn(ActiveTimerSessionDto) -> Result<DateTime<Utc>, String> =
            pomodoro_target_reached_at;
        let _: fn(String) -> Result<bool, String> = discard_active_timer_session;
        let _: fn(CompletedTimerSessionDto) -> Result<bool, String> = finish_active_timer_session;
        let _: fn(String) -> Result<Vec<CompletedTimerSessionDto>, String> =
            get_completed_timer_sessions;
        let _: fn(String) -> Result<Vec<TaskDto>, String> = search_tasks;
        let _: fn(i64, i64) -> Result<Vec<HomeTaskDto>, String> = get_home_tasks;
        let _: fn(CalendarRangeInput) -> Result<Vec<CalendarOccurrenceDto>, String> =
            get_calendar_occurrences;
        let _: fn(String) -> Result<i32, String> = count_task_descendants;
        let _: fn(String) -> Result<i32, String> = count_tasks_in_list;
        let _: fn(
            String,
            String,
            String,
            i32,
            Option<TaskDueInput>,
            Option<i64>,
            Option<i32>,
        ) -> Result<TaskDto, String> = update_task;
        let _: fn(String, String, Option<String>) -> Result<TaskDto, String> = set_task_status;
        let _: fn(String) -> Result<(), String> = delete_task;
        let _: fn(String) -> Result<(), String> = delete_list;
        let _: fn() -> Result<Option<TaskUndoDto>, String> = get_latest_task_undo;
        let _: fn(String) -> Result<TaskDto, String> = undo_task_operation;
        let _: fn(String) -> Result<Option<String>, String> = get_setting;
        let _: fn(String, String) -> Result<(), String> = set_setting;
        let _: fn(String, i64) -> Result<ReminderDto, String> = create_task_reminder;
        let _: fn(String, i64) -> Result<ReminderDto, String> = update_reminder;
        let _: fn(String) -> Result<ReminderDto, String> = delete_reminder;
        let _: fn(String) -> Result<Vec<ReminderDto>, String> = clear_task_reminders;
        let _: fn(String) -> Result<Vec<ReminderDto>, String> = get_task_reminders;
        let _: fn(String) -> Result<Vec<ReminderDto>, String> = get_task_subtree_reminders;
        let _: fn(String) -> Result<Vec<ReminderDto>, String> = get_list_reminders;
        let _: fn(i64) -> Result<Vec<ReminderDto>, String> = list_pending_reminders;
        let _: fn(String, i64) -> Result<ReminderDto, String> = snooze_reminder;
    }

    #[test]
    fn draft_task_json_escapes_title_without_lower_layer_dependencies() {
        let json = create_draft_task("quote \" slash \\ line\n牛乳".to_string());
        assert!(json.contains("\"title\":\"quote \\\" slash \\\\ line\\n牛乳\""));
        assert!(json.contains("\"status\":\"todo\""));
        assert!(json.ends_with("\"updated_at\":0}"));
    }

    #[test]
    fn calendar_bridge_rejects_invalid_or_reversed_half_open_ranges_before_client_access() {
        let start = DateTime::<Utc>::from_timestamp_millis(1_773_035_600_000).unwrap();
        let end = DateTime::<Utc>::from_timestamp_millis(1_773_118_400_000).unwrap();

        let invalid_date = get_calendar_occurrences(CalendarRangeInput {
            start_on: "2026-03-8".into(),
            end_on: "2026-03-09".into(),
            start_at: start,
            end_at: end,
        });
        assert!(matches!(
            invalid_date,
            Err(error) if error.contains("invalid civil date")
        ));

        let reversed = get_calendar_occurrences(CalendarRangeInput {
            start_on: "2026-03-09".into(),
            end_on: "2026-03-08".into(),
            start_at: start,
            end_at: end,
        });
        assert!(matches!(
            reversed,
            Err(error) if error.contains("calendar range")
        ));
    }
}

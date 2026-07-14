use todori_domain::{
    archive_list as domain_archive_list, fractional_index_after, fractional_index_between,
    new_list, new_task, rebalance_ranks, rename_list as domain_rename_list, transition_task,
    unarchive_list as domain_unarchive_list, update_due, update_estimated_minutes, update_note,
    update_priority, update_scheduled_at, update_title, validate_parent_for, ActiveTimerSession,
    CompletedTimerSession, List, Task, TaskDue, TaskStatus, Uuid,
};
use todori_storage::{
    open_encrypted, CalendarOccurrence, CalendarOccurrenceKind as StorageCalendarOccurrenceKind,
    CalendarRange as StorageCalendarRange, HomeTask, ListRepository, Reminder, ReminderRepository,
    SqliteWriteTx, StorageError, TaskRepository, TaskUndoEntry, TaskUndoOperation,
    TimerSessionRepository,
};
use zeroize::Zeroizing;

use crate::mutation_service::{
    enqueue_list_in_transaction, enqueue_task_in_transaction, enqueue_timer_session_in_transaction,
};
use crate::{
    load_local_crypto_context, ClientError, CreateTaskInput, LocalCryptoAvailability,
    LocalMutationContext, ReorderTaskInput, SetTaskStatusInput, SqliteMutationService,
    UpdateTaskInput,
};

use super::{now_ms, CryptoRuntimeState, LocalMutationState, TodoriClient};

#[derive(Debug, Clone)]
pub struct CreateTaskCommand {
    pub list_id: Uuid,
    pub title: String,
    pub parent_task_id: Option<Uuid>,
    pub due: Option<TaskDue>,
    pub note: Option<String>,
    pub priority: i32,
    pub scheduled_at: Option<i64>,
    pub estimated_minutes: Option<i32>,
}

#[derive(Debug, Clone)]
pub struct ReorderTaskCommand {
    pub task_id: Uuid,
    pub previous_task_id: Option<Uuid>,
    pub next_task_id: Option<Uuid>,
}

#[derive(Debug, Clone)]
pub struct UpdateTaskCommand {
    pub task_id: Uuid,
    pub title: String,
    pub note: String,
    pub priority: i32,
    pub due: Option<TaskDue>,
    pub scheduled_at: Option<i64>,
    pub estimated_minutes: Option<i32>,
}

#[derive(Debug, Clone)]
pub struct SetTaskStatusCommand {
    pub task_id: Uuid,
    pub status: TaskStatus,
    pub closed_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct HomeTaskView {
    pub task: Task,
    pub list_name: String,
    pub is_home_target: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalendarRange {
    pub start_on: todori_domain::CivilDate,
    pub end_on: todori_domain::CivilDate,
    pub start_at: todori_domain::UtcInstant,
    pub end_at: todori_domain::UtcInstant,
}

impl CalendarRange {
    pub fn new(
        start_on: todori_domain::CivilDate,
        end_on: todori_domain::CivilDate,
        start_at: todori_domain::UtcInstant,
        end_at: todori_domain::UtcInstant,
    ) -> Result<Self, ClientError> {
        if start_on >= end_on || start_at >= end_at {
            return Err(ClientError::InvalidCalendarRange);
        }
        Ok(Self {
            start_on,
            end_on,
            start_at,
            end_at,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CalendarOccurrenceKind {
    DateDue {
        due_on: todori_domain::CivilDate,
    },
    DateTimeDue {
        due_at: todori_domain::UtcInstant,
        time_zone: todori_domain::IanaTimeZone,
    },
    Scheduled {
        scheduled_at: todori_domain::UtcInstant,
    },
    Completed {
        completed_at: todori_domain::UtcInstant,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct CalendarOccurrenceView {
    pub task: Task,
    pub list_name: String,
    pub list_archived: bool,
    pub kind: CalendarOccurrenceKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskUndoKind {
    Delete,
    Complete,
    Edit,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TaskUndoView {
    pub id: Uuid,
    pub operation: TaskUndoKind,
    pub task_id: Uuid,
    pub list_id: Uuid,
    pub task_title: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReminderView {
    pub id: Uuid,
    pub task_id: Uuid,
    pub remind_at: i64,
    pub snoozed_until: Option<i64>,
    pub created_at: i64,
}

enum CreateListMode {
    Anonymous,
    Ready {
        tenant_id: Uuid,
        master_key: Zeroizing<[u8; 32]>,
        mutation: LocalMutationContext,
    },
}

impl TodoriClient {
    pub fn local_time_zone(&self) -> Result<String, ClientError> {
        iana_time_zone::get_timezone().map_err(|_| ClientError::LocalTimeZoneUnavailable)
    }

    pub fn create_list(&self, name: String) -> Result<List, ClientError> {
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        let mode = self.create_list_mode()?;
        match mode {
            CreateListMode::Anonymous => self.create_anonymous_list(name, now),
            CreateListMode::Ready {
                tenant_id,
                master_key,
                mutation,
            } => {
                let list = self.mutation_service().create_list(
                    name,
                    now,
                    tenant_id,
                    &master_key,
                    &mutation,
                )?;
                let refreshed =
                    load_local_crypto_context(&self.db_path, &self.db_key, Some(*master_key))?;
                let LocalCryptoAvailability::Ready(crypto) = refreshed else {
                    return Err(ClientError::AccountBoundUnavailable);
                };
                self.account_state()?.crypto = CryptoRuntimeState::Ready(crypto);
                Ok(list)
            }
        }
    }

    pub fn get_lists(&self) -> Result<Vec<List>, ClientError> {
        self.with_list_repository(|repository| Ok(repository.list_all()?))
    }

    pub fn get_archived_lists(&self) -> Result<Vec<List>, ClientError> {
        self.with_list_repository(|repository| Ok(repository.list_archived()?))
    }

    pub fn rename_list(&self, list_id: Uuid, name: String) -> Result<List, ClientError> {
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => {
                self.mutate_anonymous_list(list_id, |list| Ok(domain_rename_list(list, name, now)?))
            }
            LocalMutationState::Ready(sync) => self
                .mutation_service()
                .rename_list(list_id, name, now, &sync),
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn archive_list(&self, list_id: Uuid) -> Result<List, ClientError> {
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => self.mutate_anonymous_list(list_id, |list| {
                if list.archived_at.is_none() && list.is_default {
                    return Err(StorageError::DefaultListProtected {
                        operation: "archived",
                        list_id,
                    }
                    .into());
                }
                Ok(domain_archive_list(list, now)?)
            }),
            LocalMutationState::Ready(sync) => {
                self.mutation_service().archive_list(list_id, now, &sync)
            }
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn unarchive_list(&self, list_id: Uuid) -> Result<List, ClientError> {
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => {
                self.mutate_anonymous_list(list_id, |list| Ok(domain_unarchive_list(list, now)?))
            }
            LocalMutationState::Ready(sync) => {
                self.mutation_service().unarchive_list(list_id, now, &sync)
            }
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn delete_list(&self, list_id: Uuid) -> Result<(), ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        self.delete_list_with_state(list_id, state, now_ms()?)
    }

    pub fn create_task(&self, command: CreateTaskCommand) -> Result<Task, ClientError> {
        validate_task_planning(command.priority, command.estimated_minutes)?;
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => self.create_anonymous_task(command, now),
            LocalMutationState::Ready(sync) => self.mutation_service().create_task(
                CreateTaskInput {
                    list_id: command.list_id,
                    title: command.title,
                    parent_task_id: command.parent_task_id,
                    due: command.due,
                    note: command.note,
                    priority: command.priority,
                    scheduled_at: command.scheduled_at,
                    estimated_minutes: command.estimated_minutes,
                    now_ms: now,
                },
                &sync,
            ),
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn reorder_task(&self, command: ReorderTaskCommand) -> Result<Task, ClientError> {
        let _guard = self.operation_guard()?;
        validate_reorder_ids(
            command.task_id,
            command.previous_task_id,
            command.next_task_id,
        )?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => self.reorder_anonymous_task(command, now),
            LocalMutationState::Ready(sync) => self.mutation_service().reorder_task(
                ReorderTaskInput {
                    task_id: command.task_id,
                    previous_task_id: command.previous_task_id,
                    next_task_id: command.next_task_id,
                    now_ms: now,
                },
                &sync,
            ),
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn get_tasks(&self, list_id: Uuid) -> Result<Vec<Task>, ClientError> {
        self.with_task_repository(|repository| Ok(repository.list_active_by_list(list_id)?))
    }

    pub fn get_active_timer_session(&self) -> Result<Option<ActiveTimerSession>, ClientError> {
        self.with_timer_repository(|repository| Ok(repository.load_active()?))
    }

    pub fn start_active_timer_session(
        &self,
        session: ActiveTimerSession,
    ) -> Result<(), ClientError> {
        let _guard = self.operation_guard()?;
        let updated_at = now_ms()?;
        self.with_timer_repository(|repository| {
            match repository.start_active(session, updated_at) {
                Ok(()) => Ok(()),
                Err(StorageError::ActiveTimerConflict(active_id)) => {
                    Err(ClientError::ActiveTimerConflict(active_id))
                }
                Err(error) => Err(error.into()),
            }
        })
    }

    pub fn update_active_timer_session(
        &self,
        session: ActiveTimerSession,
    ) -> Result<(), ClientError> {
        let _guard = self.operation_guard()?;
        let updated_at = now_ms()?;
        self.with_timer_repository(|repository| {
            repository.update_active(session, updated_at)?;
            Ok(())
        })
    }

    pub fn discard_active_timer_session(
        &self,
        expected_session_id: Uuid,
    ) -> Result<bool, ClientError> {
        let _guard = self.operation_guard()?;
        self.with_timer_repository(|repository| Ok(repository.clear_active(expected_session_id)?))
    }

    pub fn get_completed_timer_sessions(
        &self,
        task_id: Uuid,
    ) -> Result<Vec<CompletedTimerSession>, ClientError> {
        self.with_timer_repository(|repository| Ok(repository.list_completed_by_task(task_id)?))
    }

    pub fn finish_active_timer_session(
        &self,
        session: CompletedTimerSession,
    ) -> Result<bool, ClientError> {
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => {
                let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
                let mut transaction = SqliteWriteTx::begin(&mut connection)?;
                let inserted = transaction.finish_active_timer_session(session)?;
                transaction.commit()?;
                Ok(inserted)
            }
            LocalMutationState::Ready(sync) => {
                let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
                let mut transaction = SqliteWriteTx::begin(&mut connection)?;
                let inserted = transaction.finish_active_timer_session(session.clone())?;
                if inserted {
                    enqueue_timer_session_in_transaction(
                        &mut transaction,
                        &sync,
                        &session,
                        false,
                        now,
                    )?;
                }
                transaction.commit()?;
                Ok(inserted)
            }
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn search_tasks(&self, query: &str) -> Result<Vec<Task>, ClientError> {
        self.with_task_repository(|repository| Ok(repository.search_tasks(query)?))
    }

    pub fn get_home_tasks(
        &self,
        today_start_ms: i64,
        tomorrow_start_ms: i64,
    ) -> Result<Vec<HomeTaskView>, ClientError> {
        self.with_task_repository(|repository| {
            Ok(repository
                .list_home(today_start_ms, tomorrow_start_ms)?
                .into_iter()
                .map(HomeTaskView::from)
                .collect())
        })
    }

    pub fn get_calendar_occurrences(
        &self,
        range: CalendarRange,
    ) -> Result<Vec<CalendarOccurrenceView>, ClientError> {
        let storage_range =
            StorageCalendarRange::new(range.start_on, range.end_on, range.start_at, range.end_at)
                .map_err(|_| ClientError::InvalidCalendarRange)?;
        self.with_task_repository(|repository| {
            Ok(repository
                .list_calendar_occurrences(&storage_range)?
                .into_iter()
                .map(CalendarOccurrenceView::from)
                .collect())
        })
    }

    pub fn count_task_descendants(&self, task_id: Uuid) -> Result<usize, ClientError> {
        self.with_task_repository(|repository| {
            repository.get(task_id)?;
            Ok(repository.count_descendants(task_id)?)
        })
    }

    pub fn count_tasks_in_list(&self, list_id: Uuid) -> Result<usize, ClientError> {
        self.with_list_repository(|repository| {
            repository.get(list_id)?;
            Ok(repository.count_tasks(list_id)?)
        })
    }

    pub fn update_task(&self, command: UpdateTaskCommand) -> Result<Task, ClientError> {
        validate_task_planning(command.priority, command.estimated_minutes)?;
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => self.update_anonymous_task(command, now),
            LocalMutationState::Ready(sync) => self.mutation_service().update_task(
                UpdateTaskInput {
                    task_id: command.task_id,
                    title: command.title,
                    note: command.note,
                    priority: command.priority,
                    due: command.due,
                    scheduled_at: command.scheduled_at,
                    estimated_minutes: command.estimated_minutes,
                    now_ms: now,
                },
                &sync,
            ),
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn set_task_status(&self, command: SetTaskStatusCommand) -> Result<Task, ClientError> {
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => self.set_anonymous_task_status(command, now),
            LocalMutationState::Ready(sync) => self.mutation_service().set_task_status(
                SetTaskStatusInput {
                    task_id: command.task_id,
                    status: command.status,
                    closed_reason: command.closed_reason,
                    now_ms: now,
                },
                &sync,
            ),
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn delete_task(&self, task_id: Uuid) -> Result<(), ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        self.delete_task_with_state(task_id, state, now_ms()?)
    }

    pub fn get_latest_task_undo(&self) -> Result<Option<TaskUndoView>, ClientError> {
        self.with_task_repository(|repository| {
            Ok(repository.latest_unconsumed_undo()?.map(TaskUndoView::from))
        })
    }

    pub fn undo_task_operation(&self, undo_id: Uuid) -> Result<Task, ClientError> {
        let _guard = self.operation_guard()?;
        let now = now_ms()?;
        match self.local_mutation_state()? {
            LocalMutationState::Anonymous => self.with_task_repository(|repository| {
                Ok(repository.undo_task_operation(undo_id, now)?)
            }),
            LocalMutationState::Ready(sync) => self
                .mutation_service()
                .undo_task_operation(undo_id, now, &sync),
            LocalMutationState::AccountBoundUnavailable => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>, ClientError> {
        self.setting(key)
    }

    pub fn set_setting(&self, key: &str, value: &str) -> Result<(), ClientError> {
        let _guard = self.operation_guard()?;
        self.set_setting_value(key, value)
    }

    pub fn set_task_reminder(
        &self,
        task_id: Uuid,
        remind_at: i64,
    ) -> Result<ReminderView, ClientError> {
        let _guard = self.operation_guard()?;
        let created_at = now_ms()?;
        self.with_reminder_repository(|repository| {
            Ok(repository
                .set_task_reminder(task_id, remind_at, created_at)?
                .into())
        })
    }

    pub fn clear_task_reminders(&self, task_id: Uuid) -> Result<Vec<ReminderView>, ClientError> {
        let _guard = self.operation_guard()?;
        self.with_reminder_repository(|repository| {
            Ok(repository
                .clear_task_reminders(task_id)?
                .into_iter()
                .map(ReminderView::from)
                .collect())
        })
    }

    pub fn get_task_reminders(&self, task_id: Uuid) -> Result<Vec<ReminderView>, ClientError> {
        self.with_reminder_repository(|repository| {
            Ok(repository
                .list_task_reminders(task_id)?
                .into_iter()
                .map(ReminderView::from)
                .collect())
        })
    }

    pub fn get_task_subtree_reminders(
        &self,
        task_id: Uuid,
    ) -> Result<Vec<ReminderView>, ClientError> {
        self.with_reminder_repository(|repository| {
            Ok(repository
                .list_task_subtree_reminders(task_id)?
                .into_iter()
                .map(ReminderView::from)
                .collect())
        })
    }

    pub fn get_list_reminders(&self, list_id: Uuid) -> Result<Vec<ReminderView>, ClientError> {
        self.with_reminder_repository(|repository| {
            Ok(repository
                .list_list_reminders(list_id)?
                .into_iter()
                .map(ReminderView::from)
                .collect())
        })
    }

    pub fn list_pending_reminders(&self, at_ms: i64) -> Result<Vec<ReminderView>, ClientError> {
        self.with_reminder_repository(|repository| {
            Ok(repository
                .list_pending_reminders(at_ms)?
                .into_iter()
                .map(ReminderView::from)
                .collect())
        })
    }

    pub fn snooze_reminder(
        &self,
        reminder_id: Uuid,
        snoozed_until: i64,
    ) -> Result<ReminderView, ClientError> {
        let _guard = self.operation_guard()?;
        self.with_reminder_repository(|repository| {
            Ok(repository
                .snooze_reminder(reminder_id, snoozed_until)?
                .into())
        })
    }
}

impl TodoriClient {
    fn mutation_service(&self) -> SqliteMutationService {
        SqliteMutationService::new(self.db_path.clone(), self.db_key())
    }

    fn create_list_mode(&self) -> Result<CreateListMode, ClientError> {
        self.ensure_account_runtime_restored()?;
        let account = self.account_state()?;
        match &account.crypto {
            CryptoRuntimeState::Anonymous => Ok(CreateListMode::Anonymous),
            CryptoRuntimeState::Ready(crypto) => Ok(CreateListMode::Ready {
                tenant_id: crypto.tenant_id(),
                master_key: Zeroizing::new(*crypto.master_key()),
                mutation: crypto.mutation_context(),
            }),
            CryptoRuntimeState::Unavailable(_) | CryptoRuntimeState::Unloaded => {
                Err(ClientError::AccountBoundUnavailable)
            }
        }
    }

    fn create_anonymous_list(&self, name: String, now: i64) -> Result<List, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let mut lists = transaction.list_lists_including_archived()?;
        lists.sort_by(|a, b| (a.sort_order.as_str(), a.id).cmp(&(b.sort_order.as_str(), b.id)));
        let rank = match fractional_index_after(lists.last().map(|list| list.sort_order.as_str())) {
            Ok(rank) => rank,
            Err(todori_domain::DomainError::SortOrderSpaceExhausted) => {
                let ranks = rebalance_ranks(lists.len() + 1)?;
                for (mut list, rank) in lists.into_iter().zip(ranks.iter()) {
                    if list.sort_order != *rank {
                        list.sort_order.clone_from(rank);
                        list.updated_at = now;
                        transaction.update_list(list)?;
                    }
                }
                ranks.last().cloned().ok_or(ClientError::Sync)?
            }
            Err(error) => return Err(error.into()),
        };
        let list = new_list(name, rank, now)?;
        transaction.insert_list(list.clone())?;
        transaction.commit()?;
        Ok(list)
    }

    fn mutate_anonymous_list(
        &self,
        list_id: Uuid,
        mutation: impl FnOnce(List) -> Result<List, ClientError>,
    ) -> Result<List, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let before = transaction.get_list(list_id)?;
        let updated = mutation(before.clone())?;
        if updated == before {
            return Ok(before);
        }
        transaction.update_list(updated.clone())?;
        transaction.commit()?;
        Ok(updated)
    }

    fn create_anonymous_task(
        &self,
        command: CreateTaskCommand,
        now: i64,
    ) -> Result<Task, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        transaction.get_list(command.list_id)?;
        let mut tasks = transaction.list_active_tasks_by_list(command.list_id)?;
        let mut siblings = tasks
            .iter()
            .filter(|task| task.parent_task_id == command.parent_task_id)
            .cloned()
            .collect::<Vec<_>>();
        siblings.sort_by(|a, b| (a.sort_order.as_str(), a.id).cmp(&(b.sort_order.as_str(), b.id)));
        let rank =
            match fractional_index_after(siblings.last().map(|task| task.sort_order.as_str())) {
                Ok(rank) => rank,
                Err(todori_domain::DomainError::SortOrderSpaceExhausted) => {
                    let ranks = rebalance_ranks(siblings.len() + 1)?;
                    for (mut sibling, rank) in siblings.into_iter().zip(ranks.iter()) {
                        if sibling.sort_order != *rank {
                            sibling.sort_order.clone_from(rank);
                            sibling.updated_at = now;
                            transaction.update_task(sibling)?;
                        }
                    }
                    ranks.last().cloned().ok_or(ClientError::Sync)?
                }
                Err(error) => return Err(error.into()),
            };
        let mut task = new_task(
            command.list_id,
            command.parent_task_id,
            command.title,
            rank,
            now,
        )?;
        if let Some(note) = command.note {
            task = update_note(task, note, now)?;
        }
        if let Some(due) = command.due {
            task = update_due(task, Some(due), now)?;
        }
        task = update_priority(task, command.priority, now)?;
        task = update_scheduled_at(task, command.scheduled_at, now)?;
        task = update_estimated_minutes(task, command.estimated_minutes, now)?;
        if let Some(parent_id) = command.parent_task_id {
            if !tasks.iter().any(|existing| existing.id == parent_id) {
                match transaction.get_task(parent_id) {
                    Ok(parent) => tasks.push(parent),
                    Err(StorageError::NotFound(_)) => {}
                    Err(error) => return Err(error.into()),
                }
            }
            validate_parent_for(task.id, command.list_id, parent_id, &tasks)?;
        }
        transaction.insert_task(task.clone())?;
        transaction.commit()?;
        Ok(task)
    }

    fn reorder_anonymous_task(
        &self,
        command: ReorderTaskCommand,
        now: i64,
    ) -> Result<Task, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let target = transaction.get_task(command.task_id)?;
        let mut scope = transaction
            .list_active_tasks_by_list(target.list_id)?
            .into_iter()
            .filter(|task| task.parent_task_id == target.parent_task_id && task.id != target.id)
            .collect::<Vec<_>>();
        scope.sort_by(|a, b| (a.sort_order.as_str(), a.id).cmp(&(b.sort_order.as_str(), b.id)));
        let insertion = insertion_index(&scope, command.previous_task_id, command.next_task_id)?;
        let previous_rank = insertion
            .checked_sub(1)
            .and_then(|index| scope.get(index))
            .map(|task| task.sort_order.as_str());
        let next_rank = scope.get(insertion).map(|task| task.sort_order.as_str());
        let midpoint = fractional_index_between(previous_rank, next_rank).ok();
        let collides = midpoint
            .as_ref()
            .is_some_and(|rank| scope.iter().any(|task| task.sort_order == *rank));
        if let Some(rank) = midpoint.filter(|_| !collides) {
            let mut updated = target;
            updated.sort_order = rank;
            updated.updated_at = now;
            transaction.update_task(updated.clone())?;
            transaction.commit()?;
            return Ok(updated);
        }

        scope.insert(insertion, target);
        let ranks = rebalance_ranks(scope.len())?;
        let mut reordered = None;
        for (mut task, rank) in scope.into_iter().zip(ranks) {
            if task.sort_order != rank {
                task.sort_order = rank;
                task.updated_at = now;
                transaction.update_task(task.clone())?;
            }
            if task.id == command.task_id {
                reordered = Some(task);
            }
        }
        transaction.commit()?;
        reordered.ok_or(ClientError::Storage(StorageError::NotFound(
            command.task_id,
        )))
    }

    fn update_anonymous_task(
        &self,
        command: UpdateTaskCommand,
        now: i64,
    ) -> Result<Task, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let before = transaction.get_task(command.task_id)?;
        let task = update_title(before.clone(), command.title, now)?;
        let task = update_note(task, command.note, now)?;
        let task = update_priority(task, command.priority, now)?;
        let task = update_due(task, command.due, now)?;
        let task = update_scheduled_at(task, command.scheduled_at, now)?;
        let updated = update_estimated_minutes(task, command.estimated_minutes, now)?;
        transaction.update_with_undo(before, updated.clone(), TaskUndoOperation::Edit, now)?;
        transaction.commit()?;
        Ok(updated)
    }

    fn set_anonymous_task_status(
        &self,
        command: SetTaskStatusCommand,
        now: i64,
    ) -> Result<Task, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let before = transaction.get_task(command.task_id)?;
        let updated = transition_task(before.clone(), command.status, command.closed_reason, now)?;
        if matches!(command.status, TaskStatus::Done | TaskStatus::WontDo) {
            transaction.update_task_with_undo(
                before,
                updated.clone(),
                TaskUndoOperation::Complete,
                now,
            )?;
        } else {
            transaction.update_task(updated.clone())?;
        }
        transaction.commit()?;
        Ok(updated)
    }

    fn delete_task_with_state(
        &self,
        task_id: Uuid,
        state: LocalMutationState,
        now: i64,
    ) -> Result<(), ClientError> {
        let sync = match state {
            LocalMutationState::Anonymous => None,
            LocalMutationState::Ready(sync) => Some(sync),
            LocalMutationState::AccountBoundUnavailable => {
                return Err(ClientError::AccountBoundUnavailable);
            }
        };
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        transaction.get_task(task_id)?;
        let tasks = transaction.list_task_subtree(task_id)?;
        let mut sessions = Vec::new();
        for task in &tasks {
            sessions.extend(transaction.list_timer_sessions_by_task(task.id)?);
        }
        if let Some(sync) = sync.as_ref() {
            for session in &sessions {
                enqueue_timer_session_in_transaction(&mut transaction, sync, session, true, now)?;
            }
            for task in &tasks {
                enqueue_task_in_transaction(&mut transaction, sync, task, true, now)?;
            }
        }
        for session in sessions {
            transaction.delete_timer_session(session.id)?;
        }
        for task in &tasks {
            transaction.clear_active_timer_for_task(task.id)?;
        }
        transaction.delete_task_subtree(task_id)?;
        transaction.commit()?;
        Ok(())
    }

    fn delete_list_with_state(
        &self,
        list_id: Uuid,
        state: LocalMutationState,
        now: i64,
    ) -> Result<(), ClientError> {
        let sync = match state {
            LocalMutationState::Anonymous => None,
            LocalMutationState::Ready(sync) => Some(sync),
            LocalMutationState::AccountBoundUnavailable => {
                return Err(ClientError::AccountBoundUnavailable);
            }
        };
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let list = transaction.get_list(list_id)?;
        if list.is_default {
            return Err(StorageError::DefaultListProtected {
                operation: "deleted",
                list_id,
            }
            .into());
        }
        let tasks = transaction.list_tasks_by_list(list_id)?;
        let mut sessions = Vec::new();
        for task in &tasks {
            sessions.extend(transaction.list_timer_sessions_by_task(task.id)?);
        }
        if let Some(sync) = sync.as_ref() {
            for session in &sessions {
                enqueue_timer_session_in_transaction(&mut transaction, sync, session, true, now)?;
            }
            for task in &tasks {
                enqueue_task_in_transaction(&mut transaction, sync, task, true, now)?;
            }
            enqueue_list_in_transaction(&mut transaction, sync, &list, true, now)?;
        }
        for session in sessions {
            transaction.delete_timer_session(session.id)?;
        }
        for task in &tasks {
            transaction.clear_active_timer_for_task(task.id)?;
        }
        transaction.delete_list_with_tasks(list_id)?;
        transaction.commit()?;
        Ok(())
    }
}

fn validate_task_planning(
    priority: i32,
    estimated_minutes: Option<i32>,
) -> Result<(), ClientError> {
    if !(0..=3).contains(&priority) {
        return Err(ClientError::InvalidPriority);
    }
    if estimated_minutes.is_some_and(|minutes| minutes <= 0 || minutes % 5 != 0) {
        return Err(ClientError::InvalidEstimatedMinutes);
    }
    Ok(())
}

fn validate_reorder_ids(
    task_id: Uuid,
    previous_task_id: Option<Uuid>,
    next_task_id: Option<Uuid>,
) -> Result<(), ClientError> {
    if previous_task_id == Some(task_id)
        || next_task_id == Some(task_id)
        || (previous_task_id.is_some() && previous_task_id == next_task_id)
    {
        return Err(todori_domain::DomainError::InvalidSortOrderBoundary.into());
    }
    Ok(())
}

fn insertion_index(
    scope: &[Task],
    previous_task_id: Option<Uuid>,
    next_task_id: Option<Uuid>,
) -> Result<usize, ClientError> {
    let find = |id| {
        scope
            .iter()
            .position(|task| task.id == id)
            .ok_or(ClientError::Storage(StorageError::NotFound(id)))
    };
    match (previous_task_id, next_task_id) {
        (None, None) => Ok(scope.len()),
        (Some(previous), None) => Ok(find(previous)? + 1),
        (None, Some(next)) => find(next),
        (Some(previous), Some(next)) => {
            let previous = find(previous)?;
            let next = find(next)?;
            if previous + 1 != next {
                return Err(todori_domain::DomainError::InvalidSortOrderBoundary.into());
            }
            Ok(next)
        }
    }
}

impl From<HomeTask> for HomeTaskView {
    fn from(value: HomeTask) -> Self {
        Self {
            task: value.task,
            list_name: value.list_name,
            is_home_target: value.is_home_target,
        }
    }
}

impl From<CalendarOccurrence> for CalendarOccurrenceView {
    fn from(value: CalendarOccurrence) -> Self {
        Self {
            task: value.task,
            list_name: value.list_name,
            list_archived: value.list_archived,
            kind: match value.kind {
                StorageCalendarOccurrenceKind::DateDue { due_on } => {
                    CalendarOccurrenceKind::DateDue { due_on }
                }
                StorageCalendarOccurrenceKind::DateTimeDue { due_at, time_zone } => {
                    CalendarOccurrenceKind::DateTimeDue { due_at, time_zone }
                }
                StorageCalendarOccurrenceKind::Scheduled { scheduled_at } => {
                    CalendarOccurrenceKind::Scheduled { scheduled_at }
                }
                StorageCalendarOccurrenceKind::Completed { completed_at } => {
                    CalendarOccurrenceKind::Completed { completed_at }
                }
            },
        }
    }
}

impl From<TaskUndoEntry> for TaskUndoView {
    fn from(value: TaskUndoEntry) -> Self {
        Self {
            id: value.id,
            operation: match value.operation_type {
                TaskUndoOperation::Delete => TaskUndoKind::Delete,
                TaskUndoOperation::Complete => TaskUndoKind::Complete,
                TaskUndoOperation::Edit => TaskUndoKind::Edit,
            },
            task_id: value.task_id,
            list_id: value.list_id,
            task_title: value.before_snapshot.title,
            created_at: value.created_at,
        }
    }
}

impl From<Reminder> for ReminderView {
    fn from(value: Reminder) -> Self {
        Self {
            id: value.id,
            task_id: value.task_id,
            remind_at: value.remind_at,
            snoozed_until: value.snoozed_until,
            created_at: value.created_at,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use tempfile::TempDir;
    use todori_domain::{
        new_list, new_task, ActiveTimerSession, CompletedTimerSession, TimerFinishKind, TimerMode,
        TimerPhase, TimerRunState,
    };
    use todori_storage::{
        ListRepository, SettingsRepository, SqliteListRepository, SqliteSettingsRepository,
        SqliteSyncStateRepository, SqliteTaskRepository, SqliteTimerSessionRepository,
        SyncStateRepository, TaskRepository, TimerSessionRepository,
    };
    use todori_sync::{LocalSyncKeys, SYNC_LOCAL_HLC_SETTING_KEY};

    use super::*;
    use crate::{
        persist_local_crypto_context,
        runtime::{AccountRuntimeState, SyncRuntimeState},
        AccountSessionState, LocalCryptoIdentity, LocalCryptoUnavailable,
    };

    const DB_KEY: [u8; 32] = [0xd2; 32];
    const BASE_MS: i64 = 1_799_500_000_000;

    #[test]
    fn timer_start_and_update_are_conditional_and_never_change_task_status() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("timer-lifecycle.sqlite3");
        let list = new_list("Timer".into(), "a0".into(), BASE_MS).unwrap();
        let task = new_task(list.id, None, "Focus".into(), "a0".into(), BASE_MS).unwrap();
        SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(list)
            .unwrap();
        SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(task.clone())
            .unwrap();
        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path: db_path.clone(),
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: None,
                session_restored: true,
                crypto: CryptoRuntimeState::Anonymous,
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };
        let running = ActiveTimerSession {
            session_id: Uuid::now_v7(),
            task_id: Some(task.id),
            mode: TimerMode::Stopwatch,
            phase: TimerPhase::Work,
            state: TimerRunState::Running,
            started_at: BASE_MS + 1_000,
            last_resumed_at: Some(BASE_MS + 1_000),
            accumulated_active_ms: 0,
            target_duration_ms: None,
        };
        client.start_active_timer_session(running.clone()).unwrap();
        let mut competing = running.clone();
        competing.session_id = Uuid::now_v7();
        assert!(matches!(
            client.start_active_timer_session(competing),
            Err(ClientError::ActiveTimerConflict(id)) if id == running.session_id
        ));

        let mut paused = running;
        paused.state = TimerRunState::Paused;
        paused.last_resumed_at = None;
        paused.accumulated_active_ms = 1_000;
        client.update_active_timer_session(paused.clone()).unwrap();
        assert_eq!(client.get_active_timer_session().unwrap(), Some(paused));
        assert!(!client.discard_active_timer_session(Uuid::now_v7()).unwrap());
        let active_id = client
            .get_active_timer_session()
            .unwrap()
            .expect("active remains after stale discard")
            .session_id;
        assert_eq!(
            SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
                .get(task.id)
                .unwrap()
                .status,
            task.status
        );
        assert!(client.discard_active_timer_session(active_id).unwrap());
    }

    #[test]
    fn finish_active_timer_enqueue_failure_rolls_back_without_changing_task_status() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("timer-finish.sqlite3");
        let list = new_list("Timer".into(), "a0".into(), BASE_MS).unwrap();
        let task = new_task(list.id, None, "Focus".into(), "a0".into(), BASE_MS).unwrap();
        SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(list.clone())
            .unwrap();
        SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(task.clone())
            .unwrap();
        let active = ActiveTimerSession {
            session_id: Uuid::now_v7(),
            task_id: Some(task.id),
            mode: TimerMode::Stopwatch,
            phase: TimerPhase::Work,
            state: TimerRunState::Paused,
            started_at: BASE_MS + 1_000,
            last_resumed_at: None,
            accumulated_active_ms: 30_000,
            target_duration_ms: None,
        };
        SqliteTimerSessionRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .start_active(active.clone(), BASE_MS + 31_000)
            .unwrap();
        let completed = CompletedTimerSession {
            id: active.session_id,
            task_id: task.id,
            mode: TimerMode::Stopwatch,
            finish_kind: TimerFinishKind::Completed,
            started_at: active.started_at,
            ended_at: BASE_MS + 31_000,
            active_duration_ms: 30_000,
            created_at: BASE_MS + 31_000,
        };
        let ready_crypto = persist_local_crypto_context(
            &db_path,
            &DB_KEY,
            LocalCryptoIdentity {
                tenant_id: Uuid::now_v7(),
                user_id: Uuid::now_v7(),
                device_id: Uuid::now_v7(),
            },
            &[0x44; 32],
            LocalSyncKeys {
                list_deks: vec![(list.id, [0x55; 32])],
                tenant_root_dek: Some(Zeroizing::new([0x56; 32])),
            },
            BASE_MS,
        )
        .unwrap();
        open_encrypted(&db_path, &DB_KEY)
            .unwrap()
            .execute_batch(
                "CREATE TRIGGER fail_timer_finish_outbox BEFORE INSERT ON sync_outbox
                 WHEN NEW.collection = 'timer_sessions'
                 BEGIN SELECT RAISE(ABORT, 'fail timer outbox'); END;",
            )
            .unwrap();
        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path: db_path.clone(),
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: None,
                session_restored: true,
                crypto: CryptoRuntimeState::Ready(ready_crypto),
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };

        let mut mismatched = completed.clone();
        mismatched.active_duration_ms -= 1;
        assert!(matches!(
            client.finish_active_timer_session(mismatched),
            Err(ClientError::Storage(
                StorageError::CompletedTimerDurationMismatch { .. }
            ))
        ));
        let timer = SqliteTimerSessionRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert_eq!(timer.load_active().unwrap(), Some(active.clone()));
        assert!(matches!(
            timer.get_completed(completed.id),
            Err(StorageError::NotFound(_))
        ));
        assert!(
            SqliteSyncStateRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
                .list_outbox_heads(10)
                .unwrap()
                .is_empty()
        );

        assert!(client
            .finish_active_timer_session(completed.clone())
            .is_err());
        let timer = SqliteTimerSessionRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert_eq!(timer.load_active().unwrap(), Some(active));
        assert!(matches!(
            timer.get_completed(completed.id),
            Err(StorageError::NotFound(_))
        ));
        let persisted_task = SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .get(task.id)
            .unwrap();
        assert_eq!(persisted_task.status, task.status);
        assert!(
            SqliteSyncStateRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
                .list_outbox_heads(10)
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn finish_active_timer_atomically_creates_one_outbox_and_preserves_task_status() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("timer-finish-success.sqlite3");
        let list = new_list("Timer".into(), "a0".into(), BASE_MS).unwrap();
        let task = new_task(list.id, None, "Focus".into(), "a0".into(), BASE_MS).unwrap();
        SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(list.clone())
            .unwrap();
        SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(task.clone())
            .unwrap();
        let active = ActiveTimerSession {
            session_id: Uuid::now_v7(),
            task_id: Some(task.id),
            mode: TimerMode::Stopwatch,
            phase: TimerPhase::Work,
            state: TimerRunState::Paused,
            started_at: BASE_MS + 1_000,
            last_resumed_at: None,
            accumulated_active_ms: 30_000,
            target_duration_ms: None,
        };
        SqliteTimerSessionRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .start_active(active.clone(), BASE_MS + 31_000)
            .unwrap();
        let completed = CompletedTimerSession {
            id: active.session_id,
            task_id: task.id,
            mode: TimerMode::Stopwatch,
            finish_kind: TimerFinishKind::Completed,
            started_at: active.started_at,
            ended_at: BASE_MS + 31_000,
            active_duration_ms: 30_000,
            created_at: BASE_MS + 31_000,
        };
        let ready_crypto = persist_local_crypto_context(
            &db_path,
            &DB_KEY,
            LocalCryptoIdentity {
                tenant_id: Uuid::now_v7(),
                user_id: Uuid::now_v7(),
                device_id: Uuid::now_v7(),
            },
            &[0x44; 32],
            LocalSyncKeys {
                list_deks: vec![(list.id, [0x55; 32])],
                tenant_root_dek: Some(Zeroizing::new([0x56; 32])),
            },
            BASE_MS,
        )
        .unwrap();
        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path: db_path.clone(),
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: None,
                session_restored: true,
                crypto: CryptoRuntimeState::Ready(ready_crypto),
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };

        assert!(client
            .finish_active_timer_session(completed.clone())
            .unwrap());
        let timer = SqliteTimerSessionRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert_eq!(timer.load_active().unwrap(), None);
        assert_eq!(timer.get_completed(completed.id).unwrap(), completed);
        assert_eq!(
            SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
                .get(task.id)
                .unwrap()
                .status,
            task.status
        );
        let outbox = SqliteSyncStateRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .list_outbox_heads(10)
            .unwrap();
        assert_eq!(outbox.len(), 1);
        assert_eq!(outbox[0].collection, "timer_sessions");
        assert_eq!(outbox[0].record_id, active.session_id);
    }

    #[test]
    fn update_task_rejects_priority_outside_public_contract_before_writing() {
        let temp = TempDir::new().unwrap();
        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path: temp.path().join("profile.sqlite3"),
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: None,
                session_restored: true,
                crypto: CryptoRuntimeState::Anonymous,
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };

        let result = client.update_task(UpdateTaskCommand {
            task_id: Uuid::now_v7(),
            title: "invalid".into(),
            note: String::new(),
            priority: 4,
            due: None,
            scheduled_at: None,
            estimated_minutes: None,
        });

        assert!(matches!(result, Err(ClientError::InvalidPriority)));
        assert!(!client.db_path.exists());
    }

    #[test]
    fn create_task_rejects_invalid_estimate_before_writing() {
        let temp = TempDir::new().unwrap();
        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path: temp.path().join("profile.sqlite3"),
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: None,
                session_restored: true,
                crypto: CryptoRuntimeState::Anonymous,
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };

        let result = client.create_task(CreateTaskCommand {
            list_id: Uuid::now_v7(),
            title: "invalid".into(),
            parent_task_id: None,
            due: None,
            note: None,
            priority: 0,
            scheduled_at: None,
            estimated_minutes: Some(24),
        });

        assert!(matches!(result, Err(ClientError::InvalidEstimatedMinutes)));
        assert!(!client.db_path.exists());
    }

    #[test]
    fn network_operation_blocks_local_mutation_and_drop_reopens_the_gate() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("gate.sqlite3");
        let list = new_list(
            "Before".into(),
            fractional_index_after(None).unwrap(),
            BASE_MS,
        )
        .unwrap();
        SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(list.clone())
            .unwrap();
        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path,
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: None,
                session_restored: true,
                crypto: CryptoRuntimeState::Anonymous,
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };

        let network_operation = client.begin_operation().unwrap();
        assert!(matches!(
            client.rename_list(list.id, "Blocked".into()),
            Err(ClientError::Busy)
        ));
        drop(network_operation);

        assert_eq!(
            client.rename_list(list.id, "Allowed".into()).unwrap().name,
            "Allowed"
        );
    }

    #[test]
    fn public_mutation_matrix_keeps_anonymous_ready_and_unavailable_distinct() {
        let run = |name: &str, crypto: CryptoRuntimeState| {
            let temp = TempDir::new().unwrap();
            let db_path = temp.path().join(format!("{name}.sqlite3"));
            let list = new_list(
                "Before".into(),
                fractional_index_after(None).unwrap(),
                BASE_MS,
            )
            .unwrap();
            SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
                .insert(list.clone())
                .unwrap();
            let client = TodoriClient {
                db_dir: temp.path().to_path_buf(),
                db_path: db_path.clone(),
                db_key: Zeroizing::new(DB_KEY),
                account: Mutex::new(AccountRuntimeState {
                    session: None,
                    session_restored: true,
                    crypto,
                }),
                sync: Mutex::new(SyncRuntimeState::default()),
                operation_busy: std::sync::atomic::AtomicBool::new(false),
            };
            (temp, db_path, list, client)
        };

        let (_temp, anonymous_path, anonymous_list, anonymous) =
            run("anonymous", CryptoRuntimeState::Anonymous);
        assert_eq!(
            anonymous
                .rename_list(anonymous_list.id, "Anonymous".into())
                .unwrap()
                .name,
            "Anonymous"
        );
        assert!(
            SqliteSyncStateRepository::new(open_encrypted(&anonymous_path, &DB_KEY).unwrap())
                .list_outbox_heads(10)
                .unwrap()
                .is_empty()
        );

        let ready_temp = TempDir::new().unwrap();
        let ready_path = ready_temp.path().join("ready.sqlite3");
        let ready_list = new_list(
            "Before".into(),
            fractional_index_after(None).unwrap(),
            BASE_MS,
        )
        .unwrap();
        SqliteListRepository::new(open_encrypted(&ready_path, &DB_KEY).unwrap())
            .insert(ready_list.clone())
            .unwrap();
        let ready_crypto = persist_local_crypto_context(
            &ready_path,
            &DB_KEY,
            LocalCryptoIdentity {
                tenant_id: Uuid::now_v7(),
                user_id: Uuid::now_v7(),
                device_id: Uuid::now_v7(),
            },
            &[0x44; 32],
            LocalSyncKeys {
                list_deks: vec![(ready_list.id, [0x55; 32])],
                tenant_root_dek: Some(Zeroizing::new([0x56; 32])),
            },
            BASE_MS,
        )
        .unwrap();
        let ready = TodoriClient {
            db_dir: ready_temp.path().to_path_buf(),
            db_path: ready_path.clone(),
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: Some(AccountSessionState {
                    logged_in: true,
                    email: Some("ready@example.com".into()),
                    user_id: Some("user".into()),
                    tenant_id: Some("tenant".into()),
                    device_id: Some("device".into()),
                }),
                session_restored: true,
                crypto: CryptoRuntimeState::Ready(ready_crypto),
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };
        ready
            .rename_list(ready_list.id, "Online ready".into())
            .unwrap();
        {
            let mut account = ready.account_state().unwrap();
            account.session = None;
            account.session_restored = true;
        }
        ready
            .rename_list(ready_list.id, "Offline ready".into())
            .unwrap();
        assert_eq!(
            SqliteSyncStateRepository::new(open_encrypted(&ready_path, &DB_KEY).unwrap())
                .list_outbox_heads(10)
                .unwrap()
                .len(),
            1
        );

        let (_temp, unavailable_path, unavailable_list, unavailable) = run(
            "unavailable",
            CryptoRuntimeState::Unavailable(LocalCryptoUnavailable::MissingMasterKey),
        );
        assert!(matches!(
            unavailable.rename_list(unavailable_list.id, "No write".into()),
            Err(ClientError::AccountBoundUnavailable)
        ));
        assert_eq!(
            SqliteListRepository::new(open_encrypted(&unavailable_path, &DB_KEY).unwrap())
                .get(unavailable_list.id)
                .unwrap(),
            unavailable_list
        );
    }

    #[test]
    fn task_delete_tombstone_failure_rolls_back_entire_subtree() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("profile.sqlite3");
        let list = new_list("Project".into(), "a0".into(), BASE_MS).unwrap();
        let root = new_task(list.id, None, "root".into(), "a0".into(), BASE_MS).unwrap();
        let child = new_task(list.id, Some(root.id), "child".into(), "a0".into(), BASE_MS).unwrap();
        SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(list.clone())
            .unwrap();
        let mut tasks = SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        tasks.insert(root.clone()).unwrap();
        tasks.insert(child.clone()).unwrap();
        drop(tasks);
        open_encrypted(&db_path, &DB_KEY)
            .unwrap()
            .execute_batch(&format!(
                "CREATE TRIGGER fail_root_tombstone BEFORE INSERT ON sync_outbox
                 WHEN NEW.record_id = '{}' BEGIN SELECT RAISE(ABORT, 'fail'); END;",
                child.id
            ))
            .unwrap();

        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path: db_path.clone(),
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: None,
                session_restored: true,
                crypto: CryptoRuntimeState::Anonymous,
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };
        let sync = LocalMutationContext {
            device_id: "device-a".into(),
            keys: LocalSyncKeys {
                list_deks: vec![(list.id, [0x55; 32])],
                tenant_root_dek: None,
            },
        };
        assert!(client
            .delete_task_with_state(root.id, LocalMutationState::Ready(sync), BASE_MS + 1)
            .is_err());

        let tasks = SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert_eq!(tasks.get(root.id).unwrap(), root);
        assert_eq!(tasks.get(child.id).unwrap(), child);
        drop(tasks);
        let sync = SqliteSyncStateRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert!(sync.list_outbox_heads(10).unwrap().is_empty());
    }

    #[test]
    fn list_delete_tombstone_failure_rolls_back_every_task_and_list() {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("profile.sqlite3");
        let list = new_list("Project".into(), "a0".into(), BASE_MS).unwrap();
        let first = new_task(list.id, None, "first".into(), "a0".into(), BASE_MS).unwrap();
        let second = new_task(list.id, None, "second".into(), "a1".into(), BASE_MS).unwrap();
        SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap())
            .insert(list.clone())
            .unwrap();
        let mut tasks = SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        tasks.insert(first.clone()).unwrap();
        tasks.insert(second.clone()).unwrap();
        drop(tasks);
        open_encrypted(&db_path, &DB_KEY)
            .unwrap()
            .execute_batch(
                "CREATE TRIGGER fail_list_tombstone BEFORE INSERT ON sync_outbox
                 WHEN NEW.collection = 'lists'
                 BEGIN SELECT RAISE(ABORT, 'fail list tombstone'); END;",
            )
            .unwrap();

        let client = TodoriClient {
            db_dir: temp.path().to_path_buf(),
            db_path: db_path.clone(),
            db_key: Zeroizing::new(DB_KEY),
            account: Mutex::new(AccountRuntimeState {
                session: None,
                session_restored: true,
                crypto: CryptoRuntimeState::Anonymous,
            }),
            sync: Mutex::new(SyncRuntimeState::default()),
            operation_busy: std::sync::atomic::AtomicBool::new(false),
        };
        let sync = LocalMutationContext {
            device_id: "device-a".into(),
            keys: LocalSyncKeys {
                list_deks: vec![(list.id, [0x55; 32])],
                tenant_root_dek: None,
            },
        };
        assert!(client
            .delete_list_with_state(list.id, LocalMutationState::Ready(sync), BASE_MS + 1)
            .is_err());

        let lists = SqliteListRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert_eq!(lists.get(list.id).unwrap(), list);
        drop(lists);
        let tasks = SqliteTaskRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert_eq!(tasks.get(first.id).unwrap(), first);
        assert_eq!(tasks.get(second.id).unwrap(), second);
        drop(tasks);
        let sync = SqliteSyncStateRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert!(sync.list_outbox_heads(10).unwrap().is_empty());
        drop(sync);
        let settings = SqliteSettingsRepository::new(open_encrypted(&db_path, &DB_KEY).unwrap());
        assert_eq!(
            settings.get_setting(SYNC_LOCAL_HLC_SETTING_KEY).unwrap(),
            None
        );
    }
}

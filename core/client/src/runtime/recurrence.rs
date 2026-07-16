use std::collections::{HashMap, HashSet};

use todori_domain::{
    calculate_streak, next_occurrence_after, scheduled_task_id, validate_and_normalize_rrule,
    virtual_next_occurrence_after_end, RecurrenceProvenance, RecurrenceSchedule, RevisionBoundary,
    ScheduleCursor, Streak, StreakOccurrence, Task, TaskStatus, TaskTemplate, TemplateNode,
    TemplateSnapshot, Uuid, SETTLEMENT_BATCH_SIZE, TEMPLATE_SNAPSHOT_SCHEMA_REVISION,
};
use todori_storage::{
    open_encrypted, RecurrenceRepository, SqliteWriteTx, StorageError, TaskRepository,
};

use crate::mutation_service::{
    enqueue_schedule_in_transaction, enqueue_task_in_transaction, enqueue_template_in_transaction,
    next_revision_in_transaction,
};
use crate::{ClientError, LocalMutationContext};

use super::{now_ms, LocalMutationState, TodoriClient};

#[derive(Debug, Clone)]
pub struct SaveTemplateCommand {
    pub task_id: Uuid,
    pub name: String,
    pub default_list_id: Option<Uuid>,
}

#[derive(Debug, Clone)]
pub struct UpdateTemplateCommand {
    pub template_id: Uuid,
    pub name: String,
    pub default_list_id: Option<Uuid>,
}

#[derive(Debug, Clone)]
pub struct ReplaceTemplateSnapshotCommand {
    pub template_id: Uuid,
    pub task_id: Uuid,
}

#[derive(Debug, Clone)]
pub struct CreateScheduleCommand {
    pub template_id: Uuid,
    pub rrule: String,
    pub starts_at: i64,
    pub time_zone: String,
}

#[derive(Debug, Clone)]
pub struct UpdateScheduleCommand {
    pub schedule_id: Uuid,
    pub rrule: String,
    pub starts_at: i64,
    pub time_zone: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct SettlementSummary {
    pub generated_occurrences: u32,
    pub generated_tasks: u32,
    pub has_more: bool,
    pub outbox_changed: bool,
}

impl TodoriClient {
    pub fn validate_recurrence_rule(
        &self,
        rrule: String,
        starts_at: i64,
        time_zone: String,
    ) -> Result<String, ClientError> {
        Ok(validate_and_normalize_rrule(&rrule, starts_at, &time_zone)?)
    }

    pub fn get_templates(&self) -> Result<Vec<TaskTemplate>, ClientError> {
        self.with_recurrence_repository(|repository| Ok(repository.list_templates()?))
    }

    pub fn get_template_schedules(
        &self,
        template_id: Uuid,
    ) -> Result<Vec<RecurrenceSchedule>, ClientError> {
        self.with_recurrence_repository(|repository| {
            Ok(repository.list_schedules_for_template(template_id)?)
        })
    }

    pub fn save_task_as_template(
        &self,
        command: SaveTemplateCommand,
    ) -> Result<TaskTemplate, ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        let now = now_ms()?;
        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let snapshot = snapshot_from_subtree(
            &transaction.list_task_subtree(command.task_id)?,
            command.task_id,
        )?;
        let revision = reserve_revision(&mut transaction, &state, now)?;
        let template = TaskTemplate {
            id: Uuid::now_v7(),
            name: command.name,
            default_list_id: command.default_list_id,
            snapshot,
            snapshot_revision: revision,
            snapshot_parent_revision: None,
            snapshot_effective_from: now,
            lineage: Vec::new(),
            created_at: now,
            updated_at: now,
        };
        template.validate()?;
        transaction.upsert_template(template.clone())?;
        if let Some(sync) = sync_context(&state) {
            enqueue_template_in_transaction(&mut transaction, sync, &template, false, now)?;
        }
        transaction.commit()?;
        Ok(template)
    }

    pub fn update_template(
        &self,
        command: UpdateTemplateCommand,
    ) -> Result<TaskTemplate, ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        let now = now_ms()?;
        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let mut template = transaction.get_template(command.template_id)?;
        template.name = command.name;
        template.default_list_id = command.default_list_id;
        template.updated_at = now;
        template.validate()?;
        transaction.upsert_template(template.clone())?;
        if let Some(sync) = sync_context(&state) {
            enqueue_template_in_transaction(&mut transaction, sync, &template, false, now)?;
        }
        transaction.commit()?;
        Ok(template)
    }

    pub fn replace_template_snapshot(
        &self,
        command: ReplaceTemplateSnapshotCommand,
    ) -> Result<TaskTemplate, ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        let now = now_ms()?;
        self.settle_all_before_edit(&state, now)?;

        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let snapshot = snapshot_from_subtree(
            &transaction.list_task_subtree(command.task_id)?,
            command.task_id,
        )?;
        let mut template = transaction.get_template(command.template_id)?;
        let previous_revision = template.snapshot_revision.clone();
        push_boundary(
            &mut template.lineage,
            &previous_revision,
            template.snapshot_parent_revision.clone(),
            template.snapshot_effective_from,
        );
        template.snapshot = snapshot;
        template.snapshot_parent_revision = Some(previous_revision);
        template.snapshot_revision = reserve_revision(&mut transaction, &state, now)?;
        template.snapshot_effective_from = now;
        template.updated_at = now;
        template.validate()?;
        transaction.upsert_template(template.clone())?;
        if let Some(sync) = sync_context(&state) {
            enqueue_template_in_transaction(&mut transaction, sync, &template, false, now)?;
        }
        transaction.commit()?;
        Ok(template)
    }

    pub fn instantiate_template(&self, template_id: Uuid) -> Result<Vec<Task>, ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        let now = now_ms()?;
        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let template = transaction.get_template(template_id)?;
        let list_id = resolve_target_list(&transaction, template.default_list_id)?;
        let tasks = instantiate_snapshot(&template, None, list_id, now)?;
        for task in &tasks {
            transaction.insert_task(task.clone())?;
            if let Some(sync) = sync_context(&state) {
                ensure_list_key(sync, list_id)?;
                enqueue_task_in_transaction(&mut transaction, sync, task, false, now)?;
            }
        }
        transaction.commit()?;
        Ok(tasks)
    }

    pub fn create_schedule(
        &self,
        command: CreateScheduleCommand,
    ) -> Result<RecurrenceSchedule, ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        let now = now_ms()?;
        let normalized =
            validate_and_normalize_rrule(&command.rrule, command.starts_at, &command.time_zone)?;
        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        transaction.get_template(command.template_id)?;
        let revision = reserve_revision(&mut transaction, &state, now)?;
        let cursor = first_cursor(
            &normalized,
            command.starts_at,
            &command.time_zone,
            command.starts_at.saturating_sub(1),
        )?;
        let schedule = RecurrenceSchedule {
            id: Uuid::now_v7(),
            template_id: command.template_id,
            rrule: normalized,
            starts_at: command.starts_at,
            time_zone: command.time_zone,
            cursor,
            enabled: true,
            config_revision: revision,
            config_parent_revision: None,
            config_effective_from: now,
            lineage: Vec::new(),
            created_at: now,
            updated_at: now,
        };
        schedule.validate()?;
        transaction.upsert_schedule(schedule.clone())?;
        if let Some(sync) = sync_context(&state) {
            enqueue_schedule_in_transaction(&mut transaction, sync, &schedule, false, now)?;
        }
        transaction.commit()?;
        Ok(schedule)
    }

    pub fn update_schedule(
        &self,
        command: UpdateScheduleCommand,
    ) -> Result<RecurrenceSchedule, ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        let now = now_ms()?;
        self.settle_all_before_edit(&state, now)?;
        let normalized =
            validate_and_normalize_rrule(&command.rrule, command.starts_at, &command.time_zone)?;
        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let mut schedule = transaction.get_schedule(command.schedule_id)?;
        let previous_revision = schedule.config_revision.clone();
        push_boundary(
            &mut schedule.lineage,
            &previous_revision,
            schedule.config_parent_revision.clone(),
            schedule.config_effective_from,
        );
        schedule.rrule = normalized;
        schedule.starts_at = command.starts_at;
        schedule.time_zone = command.time_zone;
        schedule.enabled = command.enabled;
        schedule.config_parent_revision = Some(previous_revision);
        schedule.config_revision = reserve_revision(&mut transaction, &state, now)?;
        schedule.config_effective_from = now;
        schedule.cursor = first_cursor(
            &schedule.rrule,
            schedule.starts_at,
            &schedule.time_zone,
            now,
        )?;
        schedule.updated_at = now;
        schedule.validate()?;
        transaction.upsert_schedule(schedule.clone())?;
        if let Some(sync) = sync_context(&state) {
            enqueue_schedule_in_transaction(&mut transaction, sync, &schedule, false, now)?;
        }
        transaction.commit()?;
        Ok(schedule)
    }

    pub fn delete_schedule(&self, schedule_id: Uuid) -> Result<(), ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        let now = now_ms()?;
        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let schedule = transaction.get_schedule(schedule_id)?;
        if let Some(sync) = sync_context(&state) {
            enqueue_schedule_in_transaction(&mut transaction, sync, &schedule, true, now)?;
        }
        transaction.delete_schedule(schedule_id)?;
        transaction.commit()?;
        Ok(())
    }

    pub fn delete_template(&self, template_id: Uuid) -> Result<(), ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        let now = now_ms()?;
        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let template = transaction.get_template(template_id)?;
        let schedules = transaction.list_schedules_for_template(template_id)?;
        if let Some(sync) = sync_context(&state) {
            for schedule in &schedules {
                enqueue_schedule_in_transaction(&mut transaction, sync, schedule, true, now)?;
            }
            enqueue_template_in_transaction(&mut transaction, sync, &template, true, now)?;
        }
        for schedule in schedules {
            transaction.delete_schedule(schedule.id)?;
        }
        transaction.delete_template(template_id)?;
        transaction.commit()?;
        Ok(())
    }

    /// Settles at most 100 due occurrences. Frontends yield and call again
    /// while `has_more` is true.
    pub fn settle_due_schedules(&self, at_ms: i64) -> Result<SettlementSummary, ClientError> {
        let _guard = self.operation_guard()?;
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        self.settle_batch(&state, at_ms)
    }

    pub fn get_schedule_streak(
        &self,
        schedule_id: Uuid,
        at_ms: i64,
    ) -> Result<Streak, ClientError> {
        let schedule = self
            .with_recurrence_repository(|repository| Ok(repository.get_schedule(schedule_id)?))?;
        let mut roots = self.with_task_repository(|repository| {
            Ok(repository
                .list_all_for_sync()?
                .into_iter()
                .filter(|task| {
                    task.parent_task_id.is_none()
                        && task
                            .recurrence
                            .as_ref()
                            .is_some_and(|value| value.schedule_id == schedule_id)
                })
                .collect::<Vec<_>>())
        })?;
        roots.sort_by_key(|task| task.recurrence.as_ref().map(|value| value.occurrence_at));
        let mut occurrences = Vec::with_capacity(roots.len());
        for (index, task) in roots.iter().enumerate() {
            let occurrence_at = task
                .recurrence
                .as_ref()
                .expect("filtered recurrence")
                .occurrence_at;
            let deadline_at = roots
                .get(index + 1)
                .and_then(|next| next.recurrence.as_ref().map(|value| value.occurrence_at))
                .or_else(|| schedule.cursor.next_run_at())
                .or(virtual_next_occurrence_after_end(
                    &schedule.rrule,
                    schedule.starts_at,
                    &schedule.time_zone,
                    occurrence_at,
                )?)
                .unwrap_or(i64::MAX);
            occurrences.push(StreakOccurrence {
                occurrence_at,
                deadline_at,
                status: task.status,
                completed_at: task.completed_at,
            });
        }
        Ok(calculate_streak(&occurrences, at_ms))
    }

    pub(super) fn settle_after_sync_pull(
        &self,
        at_ms: i64,
    ) -> Result<SettlementSummary, ClientError> {
        let state = self.local_mutation_state()?;
        ensure_available(&state)?;
        self.settle_batch(&state, at_ms)
    }

    fn settle_all_before_edit(
        &self,
        state: &LocalMutationState,
        at_ms: i64,
    ) -> Result<(), ClientError> {
        loop {
            let summary = self.settle_batch(state, at_ms)?;
            if !summary.has_more {
                return Ok(());
            }
        }
    }

    fn settle_batch(
        &self,
        state: &LocalMutationState,
        at_ms: i64,
    ) -> Result<SettlementSummary, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key())?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let reconciled = reconcile_superseded_tasks(&mut transaction, state, at_ms)?;
        let schedules = transaction.list_due_schedules(at_ms)?;
        let mut summary = SettlementSummary {
            outbox_changed: reconciled && sync_context(state).is_some(),
            ..SettlementSummary::default()
        };
        let mut remaining = u32::from(SETTLEMENT_BATCH_SIZE);
        for mut schedule in schedules {
            if remaining == 0 {
                break;
            }
            let template = transaction.get_template(schedule.template_id)?;
            let list_id = resolve_target_list(&transaction, template.default_list_id)?;
            if let Some(sync) = sync_context(state) {
                ensure_list_key(sync, list_id)?;
            }
            while remaining > 0 {
                let ScheduleCursor::Pending(occurrence_at) = schedule.cursor else {
                    break;
                };
                if occurrence_at > at_ms || !schedule.enabled {
                    break;
                }
                let root_id = scheduled_task_id(
                    schedule.id,
                    &schedule.config_revision,
                    &template.snapshot_revision,
                    occurrence_at,
                    root_node(&template.snapshot)?.node_key.as_str(),
                );
                let exists = match transaction.get_task(root_id) {
                    Ok(_) => true,
                    Err(StorageError::NotFound(_)) => false,
                    Err(error) => return Err(error.into()),
                };
                if !exists {
                    let provenance = RecurrenceProvenance {
                        schedule_id: schedule.id,
                        schedule_revision: schedule.config_revision.clone(),
                        template_revision: template.snapshot_revision.clone(),
                        occurrence_at,
                    };
                    let tasks = instantiate_snapshot(
                        &template,
                        Some((&schedule, provenance)),
                        list_id,
                        occurrence_at,
                    )?;
                    for task in &tasks {
                        transaction.insert_task(task.clone())?;
                        if let Some(sync) = sync_context(state) {
                            enqueue_task_in_transaction(
                                &mut transaction,
                                sync,
                                task,
                                false,
                                at_ms,
                            )?;
                        }
                    }
                    summary.generated_tasks += u32::try_from(tasks.len()).unwrap_or(u32::MAX);
                }
                summary.generated_occurrences += 1;
                remaining -= 1;
                schedule.cursor = first_cursor(
                    &schedule.rrule,
                    schedule.starts_at,
                    &schedule.time_zone,
                    occurrence_at,
                )?;
            }
            schedule.updated_at = at_ms;
            transaction.upsert_schedule(schedule.clone())?;
            if let Some(sync) = sync_context(state) {
                enqueue_schedule_in_transaction(&mut transaction, sync, &schedule, false, at_ms)?;
                summary.outbox_changed = true;
            }
        }
        summary.has_more = transaction
            .list_due_schedules(at_ms)?
            .iter()
            .any(|schedule| {
                schedule.enabled
                    && schedule
                        .cursor
                        .next_run_at()
                        .is_some_and(|next| next <= at_ms)
            });
        transaction.commit()?;
        Ok(summary)
    }
}

fn ensure_available(state: &LocalMutationState) -> Result<(), ClientError> {
    if matches!(state, LocalMutationState::AccountBoundUnavailable) {
        Err(ClientError::AccountBoundUnavailable)
    } else {
        Ok(())
    }
}

fn sync_context(state: &LocalMutationState) -> Option<&LocalMutationContext> {
    match state {
        LocalMutationState::Ready(sync) => Some(sync),
        LocalMutationState::Anonymous | LocalMutationState::AccountBoundUnavailable => None,
    }
}

fn reserve_revision(
    transaction: &mut SqliteWriteTx<'_>,
    state: &LocalMutationState,
    now: i64,
) -> Result<String, ClientError> {
    let device_id = sync_context(state)
        .map(|sync| sync.device_id.as_str())
        .unwrap_or("anonymous-local");
    next_revision_in_transaction(transaction, device_id, now)
}

fn ensure_list_key(sync: &LocalMutationContext, list_id: Uuid) -> Result<(), ClientError> {
    if sync.keys.contains_list(list_id) {
        Ok(())
    } else {
        Err(ClientError::MissingListKey(list_id))
    }
}

fn first_cursor(
    rrule: &str,
    starts_at: i64,
    time_zone: &str,
    after: i64,
) -> Result<ScheduleCursor, ClientError> {
    Ok(next_occurrence_after(rrule, starts_at, time_zone, after)?
        .map_or(ScheduleCursor::Exhausted, ScheduleCursor::Pending))
}

fn push_boundary(
    lineage: &mut Vec<RevisionBoundary>,
    revision: &str,
    parent_revision: Option<String>,
    effective_from: i64,
) {
    if lineage.iter().all(|entry| entry.revision != revision) {
        lineage.push(RevisionBoundary {
            revision: revision.to_string(),
            parent_revision,
            effective_from,
        });
        lineage.sort_by_key(|entry| entry.effective_from);
    }
}

fn snapshot_from_subtree(tasks: &[Task], root_id: Uuid) -> Result<TemplateSnapshot, ClientError> {
    let ids = tasks.iter().map(|task| task.id).collect::<HashSet<_>>();
    let mut sibling_orders = HashMap::<Option<Uuid>, Vec<&Task>>::new();
    for task in tasks {
        let parent = task.parent_task_id.filter(|id| ids.contains(id));
        sibling_orders.entry(parent).or_default().push(task);
    }
    for siblings in sibling_orders.values_mut() {
        siblings.sort_by(|left, right| {
            left.sort_order
                .cmp(&right.sort_order)
                .then(left.id.cmp(&right.id))
        });
    }
    let mut order_by_id = HashMap::new();
    for siblings in sibling_orders.values() {
        for (index, task) in siblings.iter().enumerate() {
            order_by_id.insert(task.id, u32::try_from(index).unwrap_or(u32::MAX));
        }
    }
    let snapshot = TemplateSnapshot {
        schema_revision: TEMPLATE_SNAPSHOT_SCHEMA_REVISION,
        nodes: tasks
            .iter()
            .map(|task| TemplateNode {
                node_key: task.id.to_string(),
                parent_node_key: if task.id == root_id {
                    None
                } else {
                    task.parent_task_id
                        .filter(|id| ids.contains(id))
                        .map(|id| id.to_string())
                },
                sibling_order: *order_by_id.get(&task.id).unwrap_or(&0),
                title: task.title.clone(),
                note: task.note.clone(),
                priority: task.priority,
                estimated_minutes: task.estimated_minutes,
            })
            .collect(),
    };
    snapshot.validate()?;
    Ok(snapshot)
}

fn resolve_target_list(
    transaction: &SqliteWriteTx<'_>,
    preferred: Option<Uuid>,
) -> Result<Uuid, ClientError> {
    if let Some(preferred) = preferred {
        match transaction.get_list(preferred) {
            Ok(list) if list.archived_at.is_none() => return Ok(list.id),
            Ok(_) | Err(StorageError::NotFound(_)) => {}
            Err(error) => return Err(error.into()),
        }
    }
    transaction.default_list_id()?.ok_or_else(|| {
        StorageError::IncompatibleSchema("canonical Inbox is missing".to_string()).into()
    })
}

fn root_node(snapshot: &TemplateSnapshot) -> Result<&TemplateNode, ClientError> {
    snapshot
        .nodes
        .iter()
        .find(|node| node.parent_node_key.is_none())
        .ok_or(todori_domain::RecurrenceError::InvalidRootCount.into())
}

fn instantiate_snapshot(
    template: &TaskTemplate,
    scheduled: Option<(&RecurrenceSchedule, RecurrenceProvenance)>,
    list_id: Uuid,
    created_at: i64,
) -> Result<Vec<Task>, ClientError> {
    let mut ids = HashMap::new();
    for node in &template.snapshot.nodes {
        let id = if let Some((schedule, provenance)) = scheduled.as_ref() {
            scheduled_task_id(
                schedule.id,
                &provenance.schedule_revision,
                &provenance.template_revision,
                provenance.occurrence_at,
                &node.node_key,
            )
        } else {
            Uuid::now_v7()
        };
        ids.insert(node.node_key.as_str(), id);
    }
    let mut pending = template.snapshot.nodes.iter().collect::<Vec<_>>();
    let mut tasks = Vec::with_capacity(pending.len());
    let mut materialized = HashSet::new();
    while !pending.is_empty() {
        let before = pending.len();
        pending.retain(|node| {
            if node
                .parent_node_key
                .as_ref()
                .is_some_and(|parent| !materialized.contains(parent.as_str()))
            {
                return true;
            }
            let is_root = node.parent_node_key.is_none();
            tasks.push(Task {
                id: ids[node.node_key.as_str()],
                list_id,
                parent_task_id: node
                    .parent_node_key
                    .as_ref()
                    .and_then(|parent| ids.get(parent.as_str()).copied()),
                title: node.title.clone(),
                note: node.note.clone(),
                status: TaskStatus::Todo,
                priority: node.priority,
                due: None,
                scheduled_at: scheduled
                    .as_ref()
                    .filter(|_| is_root)
                    .map(|(_, provenance)| provenance.occurrence_at),
                estimated_minutes: node.estimated_minutes,
                sort_order: format!("{:032x}", u128::from(node.sibling_order) + 1),
                completed_at: None,
                closed_reason: None,
                deleted_at: None,
                assignee: None,
                recurrence: scheduled.as_ref().map(|(_, provenance)| provenance.clone()),
                created_at,
                updated_at: created_at,
            });
            materialized.insert(node.node_key.as_str());
            false
        });
        if pending.len() == before {
            return Err(todori_domain::RecurrenceError::InvalidParent.into());
        }
    }
    Ok(tasks)
}

fn reconcile_superseded_tasks(
    transaction: &mut SqliteWriteTx<'_>,
    state: &LocalMutationState,
    now: i64,
) -> Result<bool, ClientError> {
    let schedules = transaction.list_schedules()?;
    let templates = transaction
        .list_templates()?
        .into_iter()
        .map(|template| (template.id, template))
        .collect::<HashMap<_, _>>();
    let by_schedule = schedules
        .iter()
        .map(|schedule| (schedule.id, schedule))
        .collect::<HashMap<_, _>>();
    let mut roots = transaction
        .list_all_tasks_for_sync()?
        .into_iter()
        .filter(|task| task.parent_task_id.is_none() && task.recurrence.is_some())
        .collect::<Vec<_>>();
    roots.sort_by_key(|task| task.id);
    let mut changed = false;
    for root in roots {
        let provenance = root.recurrence.as_ref().expect("filtered provenance");
        let Some(schedule) = by_schedule.get(&provenance.schedule_id) else {
            // Schedule deletion intentionally keeps generated tasks.
            continue;
        };
        let Some(template) = templates.get(&schedule.template_id) else {
            continue;
        };
        let valid = revision_accepts_occurrence(
            &schedule.lineage,
            &schedule.config_revision,
            schedule.config_parent_revision.as_deref(),
            schedule.config_effective_from,
            &provenance.schedule_revision,
            provenance.occurrence_at,
        ) && revision_accepts_occurrence(
            &template.lineage,
            &template.snapshot_revision,
            template.snapshot_parent_revision.as_deref(),
            template.snapshot_effective_from,
            &provenance.template_revision,
            provenance.occurrence_at,
        );
        if valid {
            continue;
        }
        let subtree = transaction.list_task_subtree(root.id)?;
        if let Some(sync) = sync_context(state) {
            for task in &subtree {
                enqueue_task_in_transaction(transaction, sync, task, true, now)?;
            }
        }
        transaction.delete_task_subtree(root.id)?;
        changed = true;
    }
    Ok(changed)
}

fn revision_accepts_occurrence(
    lineage: &[RevisionBoundary],
    current_revision: &str,
    current_parent: Option<&str>,
    current_effective_from: i64,
    candidate_revision: &str,
    occurrence_at: i64,
) -> bool {
    let mut boundaries = lineage.to_vec();
    if boundaries
        .iter()
        .all(|entry| entry.revision != current_revision)
    {
        boundaries.push(RevisionBoundary {
            revision: current_revision.to_string(),
            parent_revision: current_parent.map(str::to_string),
            effective_from: current_effective_from,
        });
    }
    boundaries.sort_by_key(|entry| entry.effective_from);
    let Some(index) = boundaries
        .iter()
        .position(|entry| entry.revision == candidate_revision)
    else {
        return false;
    };
    let lower = if index == 0 {
        i64::MIN
    } else {
        boundaries[index].effective_from
    };
    let upper = boundaries
        .get(index + 1)
        .map(|entry| entry.effective_from)
        .unwrap_or(i64::MAX);
    occurrence_at >= lower && occurrence_at < upper
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn revision_windows_reject_losing_and_post_cutover_old_instances() {
        let lineage = vec![RevisionBoundary {
            revision: "old".to_string(),
            parent_revision: None,
            effective_from: 100,
        }];
        assert!(revision_accepts_occurrence(
            &lineage,
            "new",
            Some("old"),
            200,
            "old",
            199,
        ));
        assert!(!revision_accepts_occurrence(
            &lineage,
            "new",
            Some("old"),
            200,
            "old",
            200,
        ));
        assert!(revision_accepts_occurrence(
            &lineage,
            "new",
            Some("old"),
            200,
            "new",
            200,
        ));
        assert!(!revision_accepts_occurrence(
            &lineage,
            "new",
            Some("old"),
            200,
            "losing-child",
            250,
        ));
    }

    #[test]
    fn scheduled_snapshot_is_content_only_and_deterministic() {
        let template = TaskTemplate {
            id: Uuid::now_v7(),
            name: "Review".to_string(),
            default_list_id: None,
            snapshot: TemplateSnapshot {
                schema_revision: TEMPLATE_SNAPSHOT_SCHEMA_REVISION,
                nodes: vec![
                    TemplateNode {
                        node_key: "root".to_string(),
                        parent_node_key: None,
                        sibling_order: 0,
                        title: "Review".to_string(),
                        note: "".to_string(),
                        priority: 1,
                        estimated_minutes: Some(30),
                    },
                    TemplateNode {
                        node_key: "child".to_string(),
                        parent_node_key: Some("root".to_string()),
                        sibling_order: 0,
                        title: "Collect".to_string(),
                        note: "Notes".to_string(),
                        priority: 0,
                        estimated_minutes: None,
                    },
                ],
            },
            snapshot_revision: "template-r1".to_string(),
            snapshot_parent_revision: None,
            snapshot_effective_from: 1,
            lineage: Vec::new(),
            created_at: 1,
            updated_at: 1,
        };
        let schedule = RecurrenceSchedule {
            id: Uuid::now_v7(),
            template_id: template.id,
            rrule: "FREQ=DAILY".to_string(),
            starts_at: 1_800_000_000_000,
            time_zone: "UTC".to_string(),
            cursor: ScheduleCursor::Pending(1_800_000_000_000),
            enabled: true,
            config_revision: "schedule-r1".to_string(),
            config_parent_revision: None,
            config_effective_from: 1,
            lineage: Vec::new(),
            created_at: 1,
            updated_at: 1,
        };
        let provenance = RecurrenceProvenance {
            schedule_id: schedule.id,
            schedule_revision: schedule.config_revision.clone(),
            template_revision: template.snapshot_revision.clone(),
            occurrence_at: schedule.starts_at,
        };
        let first = instantiate_snapshot(
            &template,
            Some((&schedule, provenance.clone())),
            Uuid::now_v7(),
            schedule.starts_at,
        )
        .unwrap();
        let second = instantiate_snapshot(
            &template,
            Some((&schedule, provenance)),
            first[0].list_id,
            schedule.starts_at,
        )
        .unwrap();
        assert_eq!(first, second);
        assert_eq!(first[0].scheduled_at, Some(schedule.starts_at));
        assert_eq!(first[1].scheduled_at, None);
        assert!(first.iter().all(|task| task.due.is_none()));
        assert!(first.iter().all(|task| task.status == TaskStatus::Todo));
    }
}

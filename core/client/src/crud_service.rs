use todori_domain::{
    archive_list as domain_archive_list, fractional_index_after, fractional_index_between,
    new_task, rebalance_ranks, rename_list as domain_rename_list, transition_task,
    unarchive_list as domain_unarchive_list, update_due_at, update_note, validate_parent_for, List,
    Task, TaskStatus, Uuid,
};
use todori_storage::{open_encrypted, SqliteWriteTx, StorageError, TaskUndoOperation};

use crate::task_service::{enqueue_list_in_transaction, enqueue_task_in_transaction};
use crate::{Client, ClientError, LocalMutationContext};

#[derive(Debug, Clone)]
pub struct CreateTaskInput {
    pub list_id: Uuid,
    pub title: String,
    pub parent_task_id: Option<Uuid>,
    pub due_at: Option<i64>,
    pub note: Option<String>,
    pub now_ms: i64,
}

#[derive(Debug, Clone)]
pub struct SetTaskStatusInput {
    pub task_id: Uuid,
    pub status: TaskStatus,
    pub closed_reason: Option<String>,
    pub now_ms: i64,
}

#[derive(Debug, Clone)]
pub struct ReorderTaskInput {
    pub task_id: Uuid,
    pub previous_task_id: Option<Uuid>,
    pub next_task_id: Option<Uuid>,
    pub now_ms: i64,
}

impl Client {
    pub fn reorder_task(
        &self,
        input: ReorderTaskInput,
        sync: &LocalMutationContext,
    ) -> Result<Task, ClientError> {
        if input.previous_task_id == Some(input.task_id)
            || input.next_task_id == Some(input.task_id)
            || (input.previous_task_id.is_some() && input.previous_task_id == input.next_task_id)
        {
            return Err(ClientError::Domain(
                todori_domain::DomainError::InvalidSortOrderBoundary,
            ));
        }
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let target = transaction.get_task(input.task_id)?;
        require_list_key(sync, target.list_id)?;
        let mut scope = transaction
            .list_active_tasks_by_list(target.list_id)?
            .into_iter()
            .filter(|task| task.parent_task_id == target.parent_task_id && task.id != target.id)
            .collect::<Vec<_>>();
        scope.sort_by(|a, b| (a.sort_order.as_str(), a.id).cmp(&(b.sort_order.as_str(), b.id)));
        let insertion = insertion_index(
            &scope,
            input.previous_task_id,
            input.next_task_id,
            target.list_id,
            target.parent_task_id,
        )?;
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
            updated.updated_at = input.now_ms;
            transaction.update_task(updated.clone())?;
            enqueue_task_in_transaction(&mut transaction, sync, &updated, false, input.now_ms)?;
            transaction.commit()?;
            return Ok(updated);
        }

        scope.insert(insertion, target);
        let ranks = rebalance_ranks(scope.len())?;
        let mut reordered = None;
        for (mut task, rank) in scope.into_iter().zip(ranks) {
            if task.sort_order != rank {
                task.sort_order = rank;
                task.updated_at = input.now_ms;
                transaction.update_task(task.clone())?;
                enqueue_task_in_transaction(&mut transaction, sync, &task, false, input.now_ms)?;
            }
            if task.id == input.task_id {
                reordered = Some(task);
            }
        }
        transaction.commit()?;
        reordered.ok_or(ClientError::Storage(StorageError::NotFound(input.task_id)))
    }

    pub fn create_task(
        &self,
        input: CreateTaskInput,
        sync: &LocalMutationContext,
    ) -> Result<Task, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        transaction.get_list(input.list_id)?;
        require_list_key(sync, input.list_id)?;
        let mut tasks = transaction.list_active_tasks_by_list(input.list_id)?;
        let last_sibling_sort_order = tasks
            .iter()
            .filter(|task| task.parent_task_id == input.parent_task_id)
            .map(|task| task.sort_order.as_str())
            .max();
        let sort_order = match fractional_index_after(last_sibling_sort_order) {
            Ok(rank) => rank,
            Err(todori_domain::DomainError::SortOrderSpaceExhausted) => {
                let mut siblings = tasks
                    .iter()
                    .filter(|task| task.parent_task_id == input.parent_task_id)
                    .cloned()
                    .collect::<Vec<_>>();
                siblings.sort_by(|a, b| {
                    (a.sort_order.as_str(), a.id).cmp(&(b.sort_order.as_str(), b.id))
                });
                for (mut sibling, rank) in siblings.into_iter().zip(rebalance_ranks(
                    tasks
                        .iter()
                        .filter(|task| task.parent_task_id == input.parent_task_id)
                        .count(),
                )?) {
                    if sibling.sort_order != rank {
                        sibling.sort_order = rank;
                        sibling.updated_at = input.now_ms;
                        transaction.update_task(sibling.clone())?;
                        enqueue_task_in_transaction(
                            &mut transaction,
                            sync,
                            &sibling,
                            false,
                            input.now_ms,
                        )?;
                    }
                }
                let refreshed = transaction.list_active_tasks_by_list(input.list_id)?;
                let last = refreshed
                    .iter()
                    .filter(|task| task.parent_task_id == input.parent_task_id)
                    .map(|task| task.sort_order.as_str())
                    .max();
                fractional_index_after(last)?
            }
            Err(error) => return Err(error.into()),
        };
        let mut task = new_task(
            input.list_id,
            input.parent_task_id,
            input.title,
            sort_order,
            input.now_ms,
        )?;
        if let Some(note) = input.note {
            task = update_note(task, note, input.now_ms)?;
        }
        if let Some(due_at) = input.due_at {
            task = update_due_at(task, Some(due_at), input.now_ms)?;
        }
        if let Some(parent_id) = input.parent_task_id {
            if !tasks.iter().any(|existing| existing.id == parent_id) {
                match transaction.get_task(parent_id) {
                    Ok(parent) => tasks.push(parent),
                    Err(StorageError::NotFound(_)) => {}
                    Err(error) => return Err(error.into()),
                }
            }
            validate_parent_for(task.id, input.list_id, parent_id, &tasks)?;
        }
        transaction.insert_task(task.clone())?;
        enqueue_task_in_transaction(&mut transaction, sync, &task, false, input.now_ms)?;
        transaction.commit()?;
        Ok(task)
    }

    pub fn set_task_status(
        &self,
        input: SetTaskStatusInput,
        sync: &LocalMutationContext,
    ) -> Result<Task, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let before = transaction.get_task(input.task_id)?;
        require_list_key(sync, before.list_id)?;
        let updated = transition_task(
            before.clone(),
            input.status,
            input.closed_reason,
            input.now_ms,
        )?;
        if matches!(input.status, TaskStatus::Done | TaskStatus::WontDo) {
            transaction.update_task_with_undo(
                before,
                updated.clone(),
                TaskUndoOperation::Complete,
                input.now_ms,
            )?;
        } else {
            transaction.update_task(updated.clone())?;
        }
        enqueue_task_in_transaction(&mut transaction, sync, &updated, false, input.now_ms)?;
        transaction.commit()?;
        Ok(updated)
    }

    pub fn undo_task_operation(
        &self,
        undo_id: Uuid,
        now_ms: i64,
        sync: &LocalMutationContext,
    ) -> Result<Task, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let task = transaction.undo_task_operation(undo_id, now_ms)?;
        require_list_key(sync, task.list_id)?;
        enqueue_task_in_transaction(&mut transaction, sync, &task, false, now_ms)?;
        transaction.commit()?;
        Ok(task)
    }

    pub fn rename_list(
        &self,
        list_id: Uuid,
        name: String,
        now_ms: i64,
        sync: &LocalMutationContext,
    ) -> Result<List, ClientError> {
        self.mutate_list(list_id, now_ms, sync, |list| {
            domain_rename_list(list, name, now_ms).map_err(ClientError::from)
        })
    }

    pub fn archive_list(
        &self,
        list_id: Uuid,
        now_ms: i64,
        sync: &LocalMutationContext,
    ) -> Result<List, ClientError> {
        self.mutate_list(list_id, now_ms, sync, |list| {
            if list.archived_at.is_none() && list.is_default {
                return Err(StorageError::DefaultListProtected {
                    operation: "archived",
                    list_id,
                }
                .into());
            }
            domain_archive_list(list, now_ms).map_err(ClientError::from)
        })
    }

    pub fn unarchive_list(
        &self,
        list_id: Uuid,
        now_ms: i64,
        sync: &LocalMutationContext,
    ) -> Result<List, ClientError> {
        self.mutate_list(list_id, now_ms, sync, |list| {
            domain_unarchive_list(list, now_ms).map_err(ClientError::from)
        })
    }

    fn mutate_list(
        &self,
        list_id: Uuid,
        now_ms: i64,
        sync: &LocalMutationContext,
        mutation: impl FnOnce(List) -> Result<List, ClientError>,
    ) -> Result<List, ClientError> {
        let mut connection = open_encrypted(&self.db_path, &self.db_key)?;
        let mut transaction = SqliteWriteTx::begin(&mut connection)?;
        let before = transaction.get_list(list_id)?;
        require_list_key(sync, before.id)?;
        let updated = mutation(before.clone())?;
        if updated == before {
            return Ok(before);
        }
        transaction.update_list(updated.clone())?;
        enqueue_list_in_transaction(&mut transaction, sync, &updated, false, now_ms)?;
        transaction.commit()?;
        Ok(updated)
    }
}

fn insertion_index(
    scope: &[Task],
    previous: Option<Uuid>,
    next: Option<Uuid>,
    list_id: Uuid,
    parent_task_id: Option<Uuid>,
) -> Result<usize, ClientError> {
    let find = |id| {
        scope
            .iter()
            .position(|task| task.id == id)
            .ok_or(ClientError::Storage(StorageError::NotFound(id)))
    };
    let index = match (previous, next) {
        (None, None) => scope.len(),
        (Some(previous), None) => find(previous)? + 1,
        (None, Some(next)) => find(next)?,
        (Some(previous), Some(next)) => {
            let previous_index = find(previous)?;
            let next_index = find(next)?;
            if previous_index + 1 != next_index {
                return Err(ClientError::Domain(
                    todori_domain::DomainError::InvalidSortOrderBoundary,
                ));
            }
            next_index
        }
    };
    if scope
        .iter()
        .any(|task| task.list_id != list_id || task.parent_task_id != parent_task_id)
    {
        return Err(ClientError::Domain(
            todori_domain::DomainError::InvalidSortOrderBoundary,
        ));
    }
    Ok(index)
}

fn require_list_key(sync: &LocalMutationContext, list_id: Uuid) -> Result<(), ClientError> {
    if sync.keys.contains_list(list_id) {
        Ok(())
    } else {
        Err(ClientError::MissingListKey(list_id))
    }
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;
    use todori_domain::{new_list, new_task};
    use todori_storage::{
        ListRepository, SettingsRepository, SqliteListRepository, SqliteSettingsRepository,
        SqliteSyncStateRepository, SqliteTaskRepository, SyncRecordSemanticState, SyncRecordState,
        SyncStateRepository, TaskRepository,
    };
    use todori_sync::{
        Hlc, LocalSyncKeys, SyncPlaintext, LISTS_COLLECTION, SYNC_LOCAL_HLC_SETTING_KEY,
        TASKS_COLLECTION,
    };

    use super::*;

    const DB_KEY: [u8; 32] = [0x85; 32];
    const BASE_MS: i64 = 1_799_100_000_000;

    struct Fixture {
        _temp: TempDir,
        client: Client,
        list: List,
        task: Task,
        sync: LocalMutationContext,
    }

    fn fixture() -> Fixture {
        let temp = TempDir::new().unwrap();
        let db_path = temp.path().join("client.sqlite3");
        let list = new_list(
            "Inbox".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            BASE_MS,
        )
        .unwrap();
        let task = new_task(
            list.id,
            None,
            "before".to_string(),
            "7fffffffffffffffffffffffffffffff".to_string(),
            BASE_MS,
        )
        .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        SqliteListRepository::new(connection)
            .insert(list.clone())
            .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        SqliteTaskRepository::new(connection)
            .insert(task.clone())
            .unwrap();
        let connection = open_encrypted(&db_path, &DB_KEY).unwrap();
        SqliteSettingsRepository::new(connection)
            .set_setting(
                SYNC_LOCAL_HLC_SETTING_KEY,
                &Hlc {
                    wall_ms: BASE_MS - 1,
                    counter: 0,
                    device_id: "device-a".to_string(),
                }
                .encode()
                .unwrap(),
                BASE_MS,
            )
            .unwrap();
        Fixture {
            _temp: temp,
            client: Client::new(db_path, DB_KEY),
            list: list.clone(),
            task,
            sync: LocalMutationContext {
                device_id: "device-a".to_string(),
                keys: LocalSyncKeys {
                    list_deks: vec![(list.id, [0x55; 32])],
                },
            },
        }
    }

    fn create_input(list_id: Uuid) -> CreateTaskInput {
        CreateTaskInput {
            list_id,
            title: "created".to_string(),
            parent_task_id: None,
            due_at: Some(BASE_MS + 60_000),
            note: Some("note".to_string()),
            now_ms: BASE_MS + 1,
        }
    }

    #[test]
    fn task_create_status_and_undo_use_transactional_sync_state() {
        let fixture = fixture();
        let created = fixture
            .client
            .create_task(create_input(fixture.list.id), &fixture.sync)
            .unwrap();
        assert_eq!(created.title, "created");
        assert_ne!(created.sort_order, fixture.task.sort_order);

        let done = fixture
            .client
            .set_task_status(
                SetTaskStatusInput {
                    task_id: created.id,
                    status: TaskStatus::Done,
                    closed_reason: None,
                    now_ms: BASE_MS + 2,
                },
                &fixture.sync,
            )
            .unwrap();
        assert_eq!(done.status, TaskStatus::Done);
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        let undo = tasks.latest_unconsumed_undo().unwrap().unwrap();
        drop(tasks);

        let restored = fixture
            .client
            .undo_task_operation(undo.id, BASE_MS + 3, &fixture.sync)
            .unwrap();
        assert_eq!(restored.status, TaskStatus::Todo);
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let sync = SqliteSyncStateRepository::new(connection);
        assert_eq!(sync.list_outbox_heads(10).unwrap().len(), 1);
        assert!(sync
            .get_record_state(TASKS_COLLECTION, created.id)
            .unwrap()
            .is_some());
    }

    #[test]
    fn account_bound_reorder_uses_midpoint_and_atomic_typed_placement() {
        let fixture = fixture();
        let created = fixture
            .client
            .create_task(create_input(fixture.list.id), &fixture.sync)
            .unwrap();
        let reordered = fixture
            .client
            .reorder_task(
                ReorderTaskInput {
                    task_id: created.id,
                    previous_task_id: None,
                    next_task_id: Some(fixture.task.id),
                    now_ms: BASE_MS + 2,
                },
                &fixture.sync,
            )
            .unwrap();
        assert!(reordered.sort_order < fixture.task.sort_order);
        assert_eq!(reordered.sort_order.len(), 32);

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let state = SqliteSyncStateRepository::new(connection)
            .get_record_state(TASKS_COLLECTION, created.id)
            .unwrap()
            .unwrap();
        let SyncRecordSemanticState::Live { plaintext_json, .. } = state.state else {
            panic!("live");
        };
        let SyncPlaintext::Task(plaintext) = serde_json::from_str(&plaintext_json).unwrap() else {
            panic!("task");
        };
        assert_eq!(plaintext.placement.value.rank, reordered.sort_order);
    }

    #[test]
    fn exhausted_gap_rebalances_only_scope_and_rolls_back_on_outbox_failure() {
        let fixture = fixture();
        let mut first = fixture.task.clone();
        first.sort_order = "00000000000000000000000000000000".to_string();
        let second = new_task(
            fixture.list.id,
            None,
            "second".to_string(),
            "00000000000000000000000000000001".to_string(),
            BASE_MS,
        )
        .unwrap();
        let target = new_task(
            fixture.list.id,
            None,
            "target".to_string(),
            "ffffffffffffffffffffffffffffffff".to_string(),
            BASE_MS,
        )
        .unwrap();
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let mut tasks = SqliteTaskRepository::new(connection);
        tasks.update(first.clone()).unwrap();
        tasks.insert(second.clone()).unwrap();
        tasks.insert(target.clone()).unwrap();
        drop(tasks);
        install_trigger(
            &fixture,
            "CREATE TRIGGER fail_rebalance_outbox BEFORE INSERT ON sync_outbox BEGIN SELECT RAISE(ABORT, 'fail'); END;",
        );

        assert!(fixture
            .client
            .reorder_task(
                ReorderTaskInput {
                    task_id: target.id,
                    previous_task_id: Some(first.id),
                    next_task_id: Some(second.id),
                    now_ms: BASE_MS + 2,
                },
                &fixture.sync,
            )
            .is_err());
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        assert_eq!(tasks.get(first.id).unwrap().sort_order, first.sort_order);
        assert_eq!(tasks.get(second.id).unwrap().sort_order, second.sort_order);
        assert_eq!(tasks.get(target.id).unwrap().sort_order, target.sort_order);
    }

    #[test]
    fn exhausted_gap_successfully_rebalances_current_scope_only() {
        let fixture = fixture();
        let mut first = fixture.task.clone();
        first.sort_order = "00000000000000000000000000000000".to_string();
        let second = new_task(
            fixture.list.id,
            None,
            "second".to_string(),
            "00000000000000000000000000000001".to_string(),
            BASE_MS,
        )
        .unwrap();
        let target = new_task(
            fixture.list.id,
            None,
            "target".to_string(),
            "ffffffffffffffffffffffffffffffff".to_string(),
            BASE_MS,
        )
        .unwrap();
        let other_list = new_list(
            "Other".to_string(),
            "bfffffffffffffffffffffffffffffff".to_string(),
            BASE_MS,
        )
        .unwrap();
        let other = new_task(
            other_list.id,
            None,
            "other".to_string(),
            "00000000000000000000000000000001".to_string(),
            BASE_MS,
        )
        .unwrap();
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let mut lists = SqliteListRepository::new(connection);
        lists.insert(other_list).unwrap();
        drop(lists);
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let mut tasks = SqliteTaskRepository::new(connection);
        tasks.update(first.clone()).unwrap();
        tasks.insert(second.clone()).unwrap();
        tasks.insert(target.clone()).unwrap();
        tasks.insert(other.clone()).unwrap();
        drop(tasks);

        let reordered = fixture
            .client
            .reorder_task(
                ReorderTaskInput {
                    task_id: target.id,
                    previous_task_id: Some(first.id),
                    next_task_id: Some(second.id),
                    now_ms: BASE_MS + 2,
                },
                &fixture.sync,
            )
            .unwrap();
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        let first_after = tasks.get(first.id).unwrap();
        let second_after = tasks.get(second.id).unwrap();
        assert!(first_after.sort_order < reordered.sort_order);
        assert!(reordered.sort_order < second_after.sort_order);
        assert_eq!(tasks.get(other.id).unwrap().sort_order, other.sort_order);
        drop(tasks);
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        assert_eq!(
            SqliteSyncStateRepository::new(connection)
                .list_outbox_heads(10)
                .unwrap()
                .len(),
            3
        );
    }

    #[test]
    fn tail_create_rebalances_when_max_rank_exhausts_space() {
        let fixture = fixture();
        let mut existing = fixture.task.clone();
        existing.sort_order = "ffffffffffffffffffffffffffffffff".to_string();
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        SqliteTaskRepository::new(connection)
            .update(existing.clone())
            .unwrap();

        let created = fixture
            .client
            .create_task(create_input(fixture.list.id), &fixture.sync)
            .unwrap();
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let existing = SqliteTaskRepository::new(connection)
            .get(existing.id)
            .unwrap();
        assert_eq!(existing.sort_order.len(), 32);
        assert!(existing.sort_order < created.sort_order);
        assert!(created.sort_order < "ffffffffffffffffffffffffffffffff".to_string());
    }

    #[test]
    fn list_mutations_commit_with_outbox_and_record_state() {
        let fixture = fixture();
        let renamed = fixture
            .client
            .rename_list(
                fixture.list.id,
                "Renamed".to_string(),
                BASE_MS + 1,
                &fixture.sync,
            )
            .unwrap();
        assert_eq!(renamed.name, "Renamed");
        let archived = fixture
            .client
            .archive_list(fixture.list.id, BASE_MS + 2, &fixture.sync)
            .unwrap();
        assert_eq!(archived.archived_at, Some(BASE_MS + 2));
        let active = fixture
            .client
            .unarchive_list(fixture.list.id, BASE_MS + 3, &fixture.sync)
            .unwrap();
        assert_eq!(active.archived_at, None);

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let sync = SqliteSyncStateRepository::new(connection);
        assert_eq!(sync.list_outbox_heads(10).unwrap().len(), 1);
        assert!(sync
            .get_record_state(LISTS_COLLECTION, fixture.list.id)
            .unwrap()
            .is_some());
    }

    #[test]
    fn idempotent_archive_and_unarchive_leave_domain_clock_state_and_outbox_unchanged() {
        let fixture = fixture();
        fixture
            .client
            .archive_list(fixture.list.id, BASE_MS + 1, &fixture.sync)
            .unwrap();
        let archived_before = list_sync_snapshot(&fixture);
        let archived_again = fixture
            .client
            .archive_list(fixture.list.id, BASE_MS + 2, &fixture.sync)
            .unwrap();
        assert_eq!(archived_again.archived_at, Some(BASE_MS + 1));
        assert_eq!(archived_again.updated_at, BASE_MS + 1);
        assert_eq!(list_sync_snapshot(&fixture), archived_before);

        fixture
            .client
            .unarchive_list(fixture.list.id, BASE_MS + 3, &fixture.sync)
            .unwrap();
        let active_before = list_sync_snapshot(&fixture);
        let active_again = fixture
            .client
            .unarchive_list(fixture.list.id, BASE_MS + 4, &fixture.sync)
            .unwrap();
        assert_eq!(active_again.archived_at, None);
        assert_eq!(active_again.updated_at, BASE_MS + 3);
        assert_eq!(list_sync_snapshot(&fixture), active_before);
    }

    #[test]
    fn task_create_outbox_failure_rolls_back_insert_hlc_and_state() {
        let fixture = fixture();
        install_trigger(
            &fixture,
            "CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_outbox BEGIN SELECT RAISE(ABORT, 'fail'); END;",
        );
        let before_hlc = local_hlc(&fixture);
        assert!(fixture
            .client
            .create_task(create_input(fixture.list.id), &fixture.sync)
            .is_err());

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        assert_eq!(
            SqliteTaskRepository::new(connection)
                .list_active_by_list(fixture.list.id)
                .unwrap()
                .len(),
            1
        );
        assert_eq!(local_hlc(&fixture), before_hlc);
    }

    #[test]
    fn status_outbox_failure_rolls_back_task_undo_hlc_and_state() {
        let fixture = fixture();
        let seeded = seed_record_state(&fixture, TASKS_COLLECTION, fixture.task.id);
        install_trigger(
            &fixture,
            "CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_outbox BEGIN SELECT RAISE(ABORT, 'fail'); END;",
        );
        let before_hlc = local_hlc(&fixture);
        assert!(fixture
            .client
            .set_task_status(
                SetTaskStatusInput {
                    task_id: fixture.task.id,
                    status: TaskStatus::Done,
                    closed_reason: None,
                    now_ms: BASE_MS + 1,
                },
                &fixture.sync,
            )
            .is_err());

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        assert_eq!(tasks.get(fixture.task.id).unwrap().status, TaskStatus::Todo);
        assert!(tasks.latest_unconsumed_undo().unwrap().is_none());
        assert_eq!(local_hlc(&fixture), before_hlc);
        assert_eq!(
            record_state(&fixture, TASKS_COLLECTION, fixture.task.id),
            seeded
        );
    }

    #[test]
    fn undo_outbox_failure_rolls_back_restore_and_consumption() {
        let fixture = fixture();
        let mut tasks = {
            let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
            SqliteTaskRepository::new(connection)
        };
        let done =
            transition_task(fixture.task.clone(), TaskStatus::Done, None, BASE_MS + 1).unwrap();
        let undo = tasks
            .update_with_undo(
                fixture.task.clone(),
                done.clone(),
                TaskUndoOperation::Complete,
                BASE_MS + 1,
            )
            .unwrap();
        drop(tasks);
        seed_record_state(&fixture, TASKS_COLLECTION, fixture.task.id);
        install_trigger(
            &fixture,
            "CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_outbox BEGIN SELECT RAISE(ABORT, 'fail'); END;",
        );

        assert!(fixture
            .client
            .undo_task_operation(undo.id, BASE_MS + 2, &fixture.sync)
            .is_err());
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        assert_eq!(tasks.get(fixture.task.id).unwrap(), done);
        assert_eq!(tasks.latest_unconsumed_undo().unwrap().unwrap().id, undo.id);
    }

    #[test]
    fn list_record_state_failure_rolls_back_domain_hlc_and_outbox() {
        let fixture = fixture();
        let seeded = seed_record_state(&fixture, LISTS_COLLECTION, fixture.list.id);
        install_trigger(
            &fixture,
            "CREATE TRIGGER fail_state BEFORE UPDATE ON sync_record_states BEGIN SELECT RAISE(ABORT, 'fail'); END;",
        );
        let before_hlc = local_hlc(&fixture);
        assert!(fixture
            .client
            .rename_list(
                fixture.list.id,
                "No commit".to_string(),
                BASE_MS + 1,
                &fixture.sync,
            )
            .is_err());

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        assert_eq!(
            SqliteListRepository::new(connection)
                .get(fixture.list.id)
                .unwrap()
                .name,
            "Inbox"
        );
        assert_eq!(local_hlc(&fixture), before_hlc);
        assert_eq!(
            record_state(&fixture, LISTS_COLLECTION, fixture.list.id),
            seeded
        );
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        assert!(SqliteSyncStateRepository::new(connection)
            .list_outbox_heads(10)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn create_rejects_missing_parent_with_domain_semantics() {
        let fixture = fixture();
        let mut input = create_input(fixture.list.id);
        input.parent_task_id = Some(Uuid::now_v7());
        assert!(matches!(
            fixture.client.create_task(input, &fixture.sync),
            Err(ClientError::Domain(
                todori_domain::DomainError::ParentNotFound
            ))
        ));
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        assert!(SqliteSyncStateRepository::new(connection)
            .list_outbox_heads(10)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn missing_list_key_rejects_task_and_list_mutations_before_commit() {
        let fixture = fixture();
        let missing = LocalMutationContext {
            device_id: "device-a".to_string(),
            keys: LocalSyncKeys::default(),
        };
        assert!(matches!(
            fixture
                .client
                .create_task(create_input(fixture.list.id), &missing),
            Err(ClientError::MissingListKey(id)) if id == fixture.list.id
        ));
        assert!(matches!(
            fixture.client.set_task_status(
                SetTaskStatusInput {
                    task_id: fixture.task.id,
                    status: TaskStatus::Done,
                    closed_reason: None,
                    now_ms: BASE_MS + 1,
                },
                &missing,
            ),
            Err(ClientError::MissingListKey(id)) if id == fixture.list.id
        ));
        assert!(matches!(
            fixture.client.rename_list(
                fixture.list.id,
                "No key".to_string(),
                BASE_MS + 1,
                &missing,
            ),
            Err(ClientError::MissingListKey(id)) if id == fixture.list.id
        ));

        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let tasks = SqliteTaskRepository::new(connection);
        assert_eq!(tasks.get(fixture.task.id).unwrap(), fixture.task);
        assert_eq!(tasks.list_active_by_list(fixture.list.id).unwrap().len(), 1);
        drop(tasks);
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        assert_eq!(
            SqliteListRepository::new(connection)
                .get(fixture.list.id)
                .unwrap(),
            fixture.list
        );
    }

    #[test]
    fn default_list_archive_is_rejected_without_sync_writes() {
        let fixture = fixture();
        let mut default_list = fixture.list.clone();
        default_list.is_default = true;
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        connection
            .execute(
                "UPDATE lists SET is_default = 1 WHERE id = ?1",
                [default_list.id.to_string()],
            )
            .unwrap();
        assert!(matches!(
            fixture
                .client
                .archive_list(default_list.id, BASE_MS + 1, &fixture.sync,),
            Err(ClientError::Storage(
                StorageError::DefaultListProtected { .. }
            ))
        ));
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        assert!(SqliteSyncStateRepository::new(connection)
            .list_outbox_heads(10)
            .unwrap()
            .is_empty());
    }

    fn install_trigger(fixture: &Fixture, sql: &str) {
        open_encrypted(fixture.client.db_path(), &DB_KEY)
            .unwrap()
            .execute_batch(sql)
            .unwrap();
    }

    fn seed_record_state(fixture: &Fixture, collection: &str, record_id: Uuid) -> String {
        let clock = Hlc {
            wall_ms: BASE_MS - 1,
            counter: 0,
            device_id: "seed".to_string(),
        };
        let plaintext = if collection == TASKS_COLLECTION {
            SyncPlaintext::from_task(&fixture.task, clock.clone()).unwrap()
        } else {
            SyncPlaintext::from_list(&fixture.list, clock.clone()).unwrap()
        };
        let plaintext_json = serde_json::to_string(&plaintext).unwrap();
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        SqliteSyncStateRepository::new(connection)
            .put_record_state(SyncRecordState {
                record_id,
                collection: collection.to_string(),
                current_revision_hlc: None,
                state: SyncRecordSemanticState::Live {
                    mutation_hlc: clock.encode().unwrap(),
                    plaintext_json: plaintext_json.clone(),
                },
                updated_at: BASE_MS,
            })
            .unwrap();
        plaintext_json
    }

    fn record_state(fixture: &Fixture, collection: &str, record_id: Uuid) -> String {
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let state = SqliteSyncStateRepository::new(connection)
            .get_record_state(collection, record_id)
            .unwrap()
            .unwrap();
        match state.state {
            SyncRecordSemanticState::Live { plaintext_json, .. } => plaintext_json,
            SyncRecordSemanticState::Tombstone { .. } => panic!("expected live state"),
        }
    }

    fn local_hlc(fixture: &Fixture) -> Option<String> {
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        SqliteSettingsRepository::new(connection)
            .get_setting(SYNC_LOCAL_HLC_SETTING_KEY)
            .unwrap()
    }

    fn list_sync_snapshot(
        fixture: &Fixture,
    ) -> (
        List,
        Option<String>,
        Option<SyncRecordState>,
        Vec<todori_storage::SyncOutboxEntry>,
    ) {
        let list =
            SqliteListRepository::new(open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap())
                .get(fixture.list.id)
                .unwrap();
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        let sync = SqliteSyncStateRepository::new(connection);
        (
            list,
            local_hlc(fixture),
            sync.get_record_state(LISTS_COLLECTION, fixture.list.id)
                .unwrap(),
            sync.list_outbox_heads(10).unwrap(),
        )
    }
}

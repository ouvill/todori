use todori_domain::{
    archive_list as domain_archive_list, fractional_index_after, new_task,
    rename_list as domain_rename_list, transition_task, unarchive_list as domain_unarchive_list,
    update_due_at, update_note, validate_parent_for, List, Task, TaskStatus, Uuid,
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

impl Client {
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
        let sort_order = fractional_index_after(last_sibling_sort_order)?;
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
        let updated = mutation(before)?;
        transaction.update_list(updated.clone())?;
        enqueue_list_in_transaction(&mut transaction, sync, &updated, false, now_ms)?;
        transaction.commit()?;
        Ok(updated)
    }
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
        SqliteSyncStateRepository, SqliteTaskRepository, SyncStateRepository, TaskRepository,
    };
    use todori_sync::{
        Hlc, LocalSyncKeys, LISTS_COLLECTION, SYNC_LOCAL_HLC_SETTING_KEY, TASKS_COLLECTION,
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
        let list = new_list("Inbox".to_string(), "a0".to_string(), BASE_MS).unwrap();
        let task = new_task(
            list.id,
            None,
            "before".to_string(),
            "a0".to_string(),
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
        assert_eq!(sync.list_outbox(10).unwrap().len(), 3);
        assert!(sync
            .get_record_state(TASKS_COLLECTION, created.id)
            .unwrap()
            .is_some());
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
        assert_eq!(sync.list_outbox(10).unwrap().len(), 3);
        assert!(sync
            .get_record_state(LISTS_COLLECTION, fixture.list.id)
            .unwrap()
            .is_some());
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
        seed_record_state(&fixture, TASKS_COLLECTION, fixture.task.id);
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
            "baseline"
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
        seed_record_state(&fixture, LISTS_COLLECTION, fixture.list.id);
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
            "baseline"
        );
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        assert!(SqliteSyncStateRepository::new(connection)
            .list_outbox(10)
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
            .list_outbox(10)
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
            .list_outbox(10)
            .unwrap()
            .is_empty());
    }

    fn install_trigger(fixture: &Fixture, sql: &str) {
        open_encrypted(fixture.client.db_path(), &DB_KEY)
            .unwrap()
            .execute_batch(sql)
            .unwrap();
    }

    fn seed_record_state(fixture: &Fixture, collection: &str, record_id: Uuid) {
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        SqliteSyncStateRepository::new(connection)
            .upsert_record_state(collection, record_id, "baseline", BASE_MS)
            .unwrap();
    }

    fn record_state(fixture: &Fixture, collection: &str, record_id: Uuid) -> String {
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        SqliteSyncStateRepository::new(connection)
            .get_record_state(collection, record_id)
            .unwrap()
            .unwrap()
    }

    fn local_hlc(fixture: &Fixture) -> Option<String> {
        let connection = open_encrypted(fixture.client.db_path(), &DB_KEY).unwrap();
        SqliteSettingsRepository::new(connection)
            .get_setting(SYNC_LOCAL_HLC_SETTING_KEY)
            .unwrap()
    }
}

//! `todori-storage`: ローカルストレージアクセス層。
//!
//! SQLCipherで暗号化されたSQLite上に `ListRepository` / `TaskRepository` を実装する
//! （`docs/03_技術仕様書.md` §5）。

use std::{path::Path, str::FromStr};

use rusqlite::{params, Connection, OptionalExtension};
use thiserror::Error;
use todori_domain::{List, Task, TaskStatus, Uuid};

const SCHEMA: &str = include_str!("schema.sql");

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("record not found: {0}")]
    NotFound(Uuid),
    #[error("invalid task status in database: {0}")]
    InvalidStatus(String),
    #[error("invalid undo operation in database: {0}")]
    InvalidUndoOperation(String),
    #[error("invalid uuid in database: {0}")]
    InvalidUuid(#[from] uuid::Error),
    #[error("invalid task snapshot in database: {0}")]
    InvalidTaskSnapshot(#[from] serde_json::Error),
    #[error("undo entry already used: {0}")]
    UndoConsumed(Uuid),
    #[error("task changed after undo was created: {0}")]
    UndoConflict(Uuid),
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
}

/// Undo対象のタスク操作種別。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskUndoOperation {
    Delete,
    Complete,
    Edit,
}

/// ローカル専用のタスクUndo履歴。
#[derive(Debug, Clone, PartialEq)]
pub struct TaskUndoEntry {
    pub id: Uuid,
    pub operation_type: TaskUndoOperation,
    pub task_id: Uuid,
    pub list_id: Uuid,
    pub before_snapshot: Task,
    pub after_updated_at: i64,
    pub after_deleted_at: Option<i64>,
    pub after_completed_at: Option<i64>,
    pub created_at: i64,
    pub consumed_at: Option<i64>,
}

/// タスクの永続化を担うリポジトリ。
///
/// SQLite(SQLCipher)実装は [`SqliteTaskRepository`] を参照。同期シグネチャのみを定義する。
pub trait TaskRepository {
    fn get(&self, id: Uuid) -> Result<Task, StorageError>;
    fn insert(&mut self, task: Task) -> Result<(), StorageError>;
    fn update(&mut self, task: Task) -> Result<(), StorageError>;
    fn list_active_by_list(&self, list_id: Uuid) -> Result<Vec<Task>, StorageError>;
    fn list_trashed(&self) -> Result<Vec<Task>, StorageError>;
}

/// リストの永続化を担うリポジトリ。
///
/// SQLite(SQLCipher)実装は [`SqliteListRepository`] を参照。
pub trait ListRepository {
    fn get(&self, id: Uuid) -> Result<List, StorageError>;
    fn insert(&mut self, list: List) -> Result<(), StorageError>;
    fn update(&mut self, list: List) -> Result<(), StorageError>;
    fn list_all(&self) -> Result<Vec<List>, StorageError>;
}

/// Opens a SQLCipher encrypted SQLite database and ensures the PoC schema exists.
pub fn open_encrypted(path: &Path, key: &[u8; 32]) -> Result<Connection, StorageError> {
    let connection = Connection::open(path)?;
    let key_hex = hex::encode(key);
    connection.execute_batch(&format!("PRAGMA key = \"x'{key_hex}'\";"))?;
    connection.execute_batch(SCHEMA)?;
    Ok(connection)
}

/// SQLite-backed implementation of [`TaskRepository`].
pub struct SqliteTaskRepository {
    connection: Connection,
}

impl SqliteTaskRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    /// Updates a task and records the undo snapshot in the same SQLite transaction.
    pub fn update_with_undo(
        &mut self,
        before: Task,
        after: Task,
        operation_type: TaskUndoOperation,
        created_at: i64,
    ) -> Result<TaskUndoEntry, StorageError> {
        let entry = TaskUndoEntry {
            id: Uuid::now_v7(),
            operation_type,
            task_id: before.id,
            list_id: before.list_id,
            before_snapshot: before,
            after_updated_at: after.updated_at,
            after_deleted_at: after.deleted_at,
            after_completed_at: after.completed_at,
            created_at,
            consumed_at: None,
        };

        let transaction = self.connection.transaction()?;
        update_task_on(&transaction, &after)?;
        insert_task_undo_on(&transaction, &entry)?;
        transaction.commit()?;

        Ok(entry)
    }

    pub fn latest_unconsumed_undo(&self) -> Result<Option<TaskUndoEntry>, StorageError> {
        self.connection
            .query_row(
                "SELECT id, operation_type, task_id, list_id, before_snapshot,
                        after_updated_at, after_deleted_at, after_completed_at,
                        created_at, consumed_at
                 FROM task_undo_entries
                 WHERE consumed_at IS NULL
                 ORDER BY created_at DESC, rowid DESC
                 LIMIT 1",
                [],
                row_to_task_undo_entry,
            )
            .optional()?
            .transpose()
    }

    pub fn undo_task_operation(
        &mut self,
        undo_id: Uuid,
        consumed_at: i64,
    ) -> Result<Task, StorageError> {
        let transaction = self.connection.transaction()?;
        let entry = transaction
            .query_row(
                "SELECT id, operation_type, task_id, list_id, before_snapshot,
                        after_updated_at, after_deleted_at, after_completed_at,
                        created_at, consumed_at
                 FROM task_undo_entries
                 WHERE id = ?1",
                [undo_id.to_string()],
                row_to_task_undo_entry,
            )
            .optional()?
            .transpose()?
            .ok_or(StorageError::NotFound(undo_id))?;

        if entry.consumed_at.is_some() {
            return Err(StorageError::UndoConsumed(undo_id));
        }

        let current = transaction
            .query_row(
                "SELECT id, list_id, parent_task_id, title, note, status, priority,
                        due_at, scheduled_at, estimated_minutes, sort_order,
                        completed_at, closed_reason, deleted_at, assignee,
                        created_at, updated_at
                 FROM tasks
                 WHERE id = ?1",
                [entry.task_id.to_string()],
                row_to_task,
            )
            .optional()?
            .ok_or(StorageError::NotFound(entry.task_id))?;

        if current.updated_at != entry.after_updated_at
            || current.deleted_at != entry.after_deleted_at
            || current.completed_at != entry.after_completed_at
        {
            return Err(StorageError::UndoConflict(entry.task_id));
        }

        update_task_on(&transaction, &entry.before_snapshot)?;
        let changed = transaction.execute(
            "UPDATE task_undo_entries
             SET consumed_at = ?2
             WHERE id = ?1 AND consumed_at IS NULL",
            params![undo_id.to_string(), consumed_at],
        )?;
        if changed == 0 {
            return Err(StorageError::UndoConsumed(undo_id));
        }
        transaction.commit()?;

        Ok(entry.before_snapshot)
    }
}

impl TaskRepository for SqliteTaskRepository {
    fn get(&self, id: Uuid) -> Result<Task, StorageError> {
        let task = self
            .connection
            .query_row(
                "SELECT id, list_id, parent_task_id, title, note, status, priority,
                        due_at, scheduled_at, estimated_minutes, sort_order,
                        completed_at, closed_reason, deleted_at, assignee,
                        created_at, updated_at
                 FROM tasks
                 WHERE id = ?1",
                [id.to_string()],
                row_to_task,
            )
            .optional()?;

        task.ok_or(StorageError::NotFound(id))
    }

    fn insert(&mut self, task: Task) -> Result<(), StorageError> {
        self.connection.execute(
            "INSERT INTO tasks (
                id, list_id, parent_task_id, title, note, status, priority,
                due_at, scheduled_at, estimated_minutes, sort_order,
                completed_at, closed_reason, deleted_at, assignee,
                created_at, updated_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11,
                ?12, ?13, ?14, ?15, ?16, ?17
            )",
            params![
                task.id.to_string(),
                task.list_id.to_string(),
                task.parent_task_id.map(|id| id.to_string()),
                task.title,
                task.note,
                status_to_str(task.status),
                task.priority,
                task.due_at,
                task.scheduled_at,
                task.estimated_minutes,
                task.sort_order,
                task.completed_at,
                task.closed_reason,
                task.deleted_at,
                task.assignee.map(|id| id.to_string()),
                task.created_at,
                task.updated_at,
            ],
        )?;
        Ok(())
    }

    fn update(&mut self, task: Task) -> Result<(), StorageError> {
        update_task_on(&self.connection, &task)
    }

    fn list_active_by_list(&self, list_id: Uuid) -> Result<Vec<Task>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT id, list_id, parent_task_id, title, note, status, priority,
                    due_at, scheduled_at, estimated_minutes, sort_order,
                    completed_at, closed_reason, deleted_at, assignee,
                    created_at, updated_at
             FROM tasks
             WHERE list_id = ?1 AND deleted_at IS NULL
             ORDER BY sort_order ASC",
        )?;
        let tasks = statement
            .query_map([list_id.to_string()], row_to_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(tasks)
    }

    fn list_trashed(&self) -> Result<Vec<Task>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT id, list_id, parent_task_id, title, note, status, priority,
                    due_at, scheduled_at, estimated_minutes, sort_order,
                    completed_at, closed_reason, deleted_at, assignee,
                    created_at, updated_at
             FROM tasks
             WHERE deleted_at IS NOT NULL
             ORDER BY deleted_at DESC",
        )?;
        let tasks = statement
            .query_map([], row_to_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(tasks)
    }
}

fn update_task_on(connection: &Connection, task: &Task) -> Result<(), StorageError> {
    let changed = connection.execute(
        "UPDATE tasks
         SET list_id = ?2,
             parent_task_id = ?3,
             title = ?4,
             note = ?5,
             status = ?6,
             priority = ?7,
             due_at = ?8,
             scheduled_at = ?9,
             estimated_minutes = ?10,
             sort_order = ?11,
             completed_at = ?12,
             closed_reason = ?13,
             deleted_at = ?14,
             assignee = ?15,
             created_at = ?16,
             updated_at = ?17
         WHERE id = ?1",
        params![
            task.id.to_string(),
            task.list_id.to_string(),
            task.parent_task_id.map(|id| id.to_string()),
            task.title,
            task.note,
            status_to_str(task.status),
            task.priority,
            task.due_at,
            task.scheduled_at,
            task.estimated_minutes,
            task.sort_order,
            task.completed_at,
            task.closed_reason,
            task.deleted_at,
            task.assignee.map(|id| id.to_string()),
            task.created_at,
            task.updated_at,
        ],
    )?;

    if changed == 0 {
        return Err(StorageError::NotFound(task.id));
    }

    Ok(())
}

fn insert_task_undo_on(connection: &Connection, entry: &TaskUndoEntry) -> Result<(), StorageError> {
    connection.execute(
        "INSERT INTO task_undo_entries (
            id, operation_type, task_id, list_id, before_snapshot,
            after_updated_at, after_deleted_at, after_completed_at,
            created_at, consumed_at
        ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10
        )",
        params![
            entry.id.to_string(),
            undo_operation_to_str(entry.operation_type),
            entry.task_id.to_string(),
            entry.list_id.to_string(),
            serde_json::to_string(&entry.before_snapshot)?,
            entry.after_updated_at,
            entry.after_deleted_at,
            entry.after_completed_at,
            entry.created_at,
            entry.consumed_at,
        ],
    )?;
    Ok(())
}

/// SQLite-backed implementation of [`ListRepository`].
pub struct SqliteListRepository {
    connection: Connection,
}

impl SqliteListRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }
}

impl ListRepository for SqliteListRepository {
    fn get(&self, id: Uuid) -> Result<List, StorageError> {
        let list = self
            .connection
            .query_row(
                "SELECT id, name, color, icon, org_id, sort_order, created_at, updated_at
                 FROM lists
                 WHERE id = ?1",
                [id.to_string()],
                row_to_list,
            )
            .optional()?;

        list.ok_or(StorageError::NotFound(id))
    }

    fn insert(&mut self, list: List) -> Result<(), StorageError> {
        self.connection.execute(
            "INSERT INTO lists (
                id, name, color, icon, org_id, sort_order, created_at, updated_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8
            )",
            params![
                list.id.to_string(),
                list.name,
                list.color,
                list.icon,
                list.org_id.map(|id| id.to_string()),
                list.sort_order,
                list.created_at,
                list.updated_at,
            ],
        )?;
        Ok(())
    }

    fn update(&mut self, list: List) -> Result<(), StorageError> {
        let changed = self.connection.execute(
            "UPDATE lists
             SET name = ?2,
                 color = ?3,
                 icon = ?4,
                 org_id = ?5,
                 sort_order = ?6,
                 created_at = ?7,
                 updated_at = ?8
             WHERE id = ?1",
            params![
                list.id.to_string(),
                list.name,
                list.color,
                list.icon,
                list.org_id.map(|id| id.to_string()),
                list.sort_order,
                list.created_at,
                list.updated_at,
            ],
        )?;

        if changed == 0 {
            return Err(StorageError::NotFound(list.id));
        }

        Ok(())
    }

    fn list_all(&self) -> Result<Vec<List>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT id, name, color, icon, org_id, sort_order, created_at, updated_at
             FROM lists
             ORDER BY sort_order ASC",
        )?;
        let lists = statement
            .query_map([], row_to_list)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(lists)
    }
}

fn row_to_list(row: &rusqlite::Row<'_>) -> rusqlite::Result<List> {
    let id: String = row.get(0)?;
    let org_id: Option<String> = row.get(4)?;

    Ok(List {
        id: parse_uuid(id, 0)?,
        name: row.get(1)?,
        color: row.get(2)?,
        icon: row.get(3)?,
        org_id: parse_optional_uuid(org_id, 4)?,
        sort_order: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

fn row_to_task(row: &rusqlite::Row<'_>) -> rusqlite::Result<Task> {
    let id: String = row.get(0)?;
    let list_id: String = row.get(1)?;
    let parent_task_id: Option<String> = row.get(2)?;
    let status: String = row.get(5)?;
    let assignee: Option<String> = row.get(14)?;

    Ok(Task {
        id: parse_uuid(id, 0)?,
        list_id: parse_uuid(list_id, 1)?,
        parent_task_id: parse_optional_uuid(parent_task_id, 2)?,
        title: row.get(3)?,
        note: row.get(4)?,
        status: status_from_str(&status).map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                5,
                rusqlite::types::Type::Text,
                Box::new(error),
            )
        })?,
        priority: row.get(6)?,
        due_at: row.get(7)?,
        scheduled_at: row.get(8)?,
        estimated_minutes: row.get(9)?,
        sort_order: row.get(10)?,
        completed_at: row.get(11)?,
        closed_reason: row.get(12)?,
        deleted_at: row.get(13)?,
        assignee: parse_optional_uuid(assignee, 14)?,
        created_at: row.get(15)?,
        updated_at: row.get(16)?,
    })
}

fn row_to_task_undo_entry(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<Result<TaskUndoEntry, StorageError>> {
    let id: String = row.get(0)?;
    let operation_type: String = row.get(1)?;
    let task_id: String = row.get(2)?;
    let list_id: String = row.get(3)?;
    let before_snapshot: String = row.get(4)?;

    Ok((|| {
        Ok(TaskUndoEntry {
            id: Uuid::from_str(&id)?,
            operation_type: undo_operation_from_str(&operation_type)?,
            task_id: Uuid::from_str(&task_id)?,
            list_id: Uuid::from_str(&list_id)?,
            before_snapshot: serde_json::from_str(&before_snapshot)?,
            after_updated_at: row.get(5)?,
            after_deleted_at: row.get(6)?,
            after_completed_at: row.get(7)?,
            created_at: row.get(8)?,
            consumed_at: row.get(9)?,
        })
    })())
}

fn parse_uuid(value: String, column: usize) -> rusqlite::Result<Uuid> {
    Uuid::from_str(&value).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(
            column,
            rusqlite::types::Type::Text,
            Box::new(error),
        )
    })
}

fn parse_optional_uuid(value: Option<String>, column: usize) -> rusqlite::Result<Option<Uuid>> {
    value.map(|value| parse_uuid(value, column)).transpose()
}

fn status_to_str(status: TaskStatus) -> &'static str {
    match status {
        TaskStatus::Todo => "todo",
        TaskStatus::InProgress => "in_progress",
        TaskStatus::Done => "done",
        TaskStatus::WontDo => "wont_do",
    }
}

fn status_from_str(value: &str) -> Result<TaskStatus, StorageError> {
    match value {
        "todo" => Ok(TaskStatus::Todo),
        "in_progress" => Ok(TaskStatus::InProgress),
        "done" => Ok(TaskStatus::Done),
        "wont_do" => Ok(TaskStatus::WontDo),
        other => Err(StorageError::InvalidStatus(other.to_string())),
    }
}

fn undo_operation_to_str(operation_type: TaskUndoOperation) -> &'static str {
    match operation_type {
        TaskUndoOperation::Delete => "delete",
        TaskUndoOperation::Complete => "complete",
        TaskUndoOperation::Edit => "edit",
    }
}

fn undo_operation_from_str(value: &str) -> Result<TaskUndoOperation, StorageError> {
    match value {
        "delete" => Ok(TaskUndoOperation::Delete),
        "complete" => Ok(TaskUndoOperation::Complete),
        "edit" => Ok(TaskUndoOperation::Edit),
        other => Err(StorageError::InvalidUndoOperation(other.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;
    use todori_crypto::{derive_local_db_key, ensure_device_key, InMemoryDeviceKeyStore};
    use todori_domain::{
        delete_task, new_list, new_task, restore_task, transition_task, update_title,
    };

    const KEY: [u8; 32] = [0x11; 32];
    const WRONG_KEY: [u8; 32] = [0x22; 32];

    fn sample_task() -> Task {
        Task {
            id: Uuid::now_v7(),
            list_id: Uuid::now_v7(),
            parent_task_id: Some(Uuid::now_v7()),
            title: "Buy milk".to_string(),
            note: "Organic whole milk".to_string(),
            status: TaskStatus::Todo,
            priority: 2,
            due_at: Some(1_800_000_000_000),
            scheduled_at: Some(1_799_900_000_000),
            estimated_minutes: Some(15),
            sort_order: "a0".to_string(),
            completed_at: None,
            closed_reason: None,
            deleted_at: None,
            assignee: Some(Uuid::now_v7()),
            created_at: 1_799_000_000_000,
            updated_at: 1_799_000_000_000,
        }
    }

    fn sample_list(sort_order: &str) -> List {
        List {
            id: Uuid::now_v7(),
            name: format!("List {sort_order}"),
            color: "#4F8EF7".to_string(),
            icon: "list".to_string(),
            org_id: None,
            sort_order: sort_order.to_string(),
            created_at: 1_799_000_000_000,
            updated_at: 1_799_000_000_000,
        }
    }

    #[test]
    fn encrypted_database_reopens_with_correct_key() {
        let file = NamedTempFile::new().unwrap();
        let task = sample_task();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteTaskRepository::new(connection);

        assert_eq!(repository.get(task.id).unwrap(), task);
    }

    #[test]
    fn encrypted_database_rejects_wrong_key_on_query() {
        let file = NamedTempFile::new().unwrap();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(sample_task()).unwrap();
        }

        let result = open_encrypted(file.path(), &WRONG_KEY);

        assert!(result.is_err());
    }

    #[test]
    fn device_key_store_derived_key_reopens_database_and_rejects_other_device_key() {
        let file = NamedTempFile::new().unwrap();
        let mut store = InMemoryDeviceKeyStore::new();
        let task = sample_task();

        {
            let device_key = ensure_device_key(&mut store).unwrap();
            let db_key = derive_local_db_key(&device_key);
            let connection = open_encrypted(file.path(), &db_key).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        {
            let device_key = ensure_device_key(&mut store).unwrap();
            let db_key = derive_local_db_key(&device_key);
            let connection = open_encrypted(file.path(), &db_key).unwrap();
            let repository = SqliteTaskRepository::new(connection);
            assert_eq!(repository.get(task.id).unwrap(), task);
        }

        let mut other_store = InMemoryDeviceKeyStore::new();
        let other_device_key = ensure_device_key(&mut other_store).unwrap();
        let other_db_key = derive_local_db_key(&other_device_key);

        assert!(open_encrypted(file.path(), &other_db_key).is_err());
    }

    #[test]
    fn encrypted_database_is_not_plain_sqlite() {
        let file = NamedTempFile::new().unwrap();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(sample_task()).unwrap();
        }

        let plain = Connection::open(file.path()).unwrap();
        let result: rusqlite::Result<i64> =
            plain.query_row("SELECT count(*) FROM tasks", [], |row| row.get(0));

        assert!(result.is_err());
    }

    #[test]
    fn fts5_search_matches_title_and_note() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();

        connection
            .execute(
                "INSERT INTO tasks_fts(rowid, title, note) VALUES (?1, ?2, ?3)",
                params![1_i64, "Plan Kyoto trip", "Book shinkansen tickets"],
            )
            .unwrap();
        let hits: i64 = connection
            .query_row(
                "SELECT count(*) FROM tasks_fts WHERE tasks_fts MATCH ?1",
                ["shinkansen"],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(hits, 1);
    }

    #[test]
    fn sqlite_task_repository_insert_get_roundtrips_task() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();

        repository.insert(task.clone()).unwrap();

        assert_eq!(repository.get(task.id).unwrap(), task);
    }

    #[test]
    fn sqlite_list_repository_roundtrips_and_lists_by_sort_order() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);
        let mut first = sample_list("b0");
        let second = sample_list("a0");

        repository.insert(first.clone()).unwrap();
        repository.insert(second.clone()).unwrap();

        assert_eq!(repository.get(first.id).unwrap(), first);

        first.name = "Renamed".to_string();
        first.color = "#FFAA00".to_string();
        first.icon = "star".to_string();
        first.org_id = Some(Uuid::now_v7());
        first.sort_order = "c0".to_string();
        first.updated_at += 1_000;
        repository.update(first.clone()).unwrap();

        assert_eq!(repository.get(first.id).unwrap(), first);
        assert_eq!(
            repository
                .list_all()
                .unwrap()
                .into_iter()
                .map(|list| list.id)
                .collect::<Vec<_>>(),
            vec![second.id, first.id]
        );
    }

    #[test]
    fn domain_usecases_persist_task_updates_after_reopen() {
        let file = NamedTempFile::new().unwrap();
        let list = new_list("Inbox".to_string(), "a0".to_string(), 1_700_000_000_000).unwrap();
        let task = new_task(
            list.id,
            None,
            "Draft title".to_string(),
            "a0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();
        let renamed =
            update_title(task.clone(), "Final title".to_string(), 1_700_000_002_000).unwrap();
        let done =
            transition_task(renamed.clone(), TaskStatus::Done, None, 1_700_000_003_000).unwrap();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(task).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.update(renamed).unwrap();
            task_repository.update(done.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let task_repository = SqliteTaskRepository::new(connection);

        assert_eq!(task_repository.get(done.id).unwrap(), done);
    }

    #[test]
    fn trashed_task_disappears_from_active_list_and_restore_reverts_it() {
        let file = NamedTempFile::new().unwrap();
        let list = new_list("Inbox".to_string(), "a0".to_string(), 1_700_000_000_000).unwrap();
        let active = new_task(
            list.id,
            None,
            "Keep".to_string(),
            "a0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();
        let to_delete = new_task(
            list.id,
            None,
            "Delete".to_string(),
            "b0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut task_repository = SqliteTaskRepository::new(connection);
        task_repository.insert(active.clone()).unwrap();
        task_repository.insert(to_delete.clone()).unwrap();

        let deleted = delete_task(to_delete, 1_700_000_002_000).unwrap();
        task_repository.update(deleted.clone()).unwrap();

        assert_eq!(
            task_repository.list_trashed().unwrap(),
            vec![deleted.clone()]
        );
        assert_eq!(
            task_repository.list_active_by_list(list.id).unwrap(),
            vec![active.clone()]
        );

        let restored = restore_task(deleted, 1_700_000_003_000).unwrap();
        task_repository.update(restored.clone()).unwrap();

        assert!(task_repository.list_trashed().unwrap().is_empty());
        assert_eq!(
            task_repository.list_active_by_list(list.id).unwrap(),
            vec![active, restored]
        );
    }

    #[test]
    fn update_with_undo_records_edit_and_restores_previous_snapshot() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let updated =
            update_title(task.clone(), "Undo me".to_string(), task.updated_at + 1).unwrap();
        let undo = repository
            .update_with_undo(
                task.clone(),
                updated.clone(),
                TaskUndoOperation::Edit,
                updated.updated_at,
            )
            .unwrap();

        assert_eq!(repository.latest_unconsumed_undo().unwrap().unwrap(), undo);
        assert_eq!(repository.get(task.id).unwrap(), updated);

        let restored = repository
            .undo_task_operation(undo.id, updated.updated_at + 1)
            .unwrap();

        assert_eq!(restored, task);
        assert_eq!(repository.get(task.id).unwrap(), task);
        assert!(repository.latest_unconsumed_undo().unwrap().is_none());
        assert!(matches!(
            repository.undo_task_operation(undo.id, updated.updated_at + 2),
            Err(StorageError::UndoConsumed(id)) if id == undo.id
        ));
    }

    #[test]
    fn delete_and_complete_undo_entries_restore_task_state() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let done =
            transition_task(task.clone(), TaskStatus::Done, None, task.updated_at + 1).unwrap();
        let complete_undo = repository
            .update_with_undo(
                task.clone(),
                done.clone(),
                TaskUndoOperation::Complete,
                done.updated_at,
            )
            .unwrap();
        assert_eq!(
            repository
                .undo_task_operation(complete_undo.id, done.updated_at + 1)
                .unwrap()
                .status,
            TaskStatus::Todo
        );

        let deleted = delete_task(task.clone(), task.updated_at + 2).unwrap();
        let delete_undo = repository
            .update_with_undo(
                task.clone(),
                deleted.clone(),
                TaskUndoOperation::Delete,
                deleted.updated_at,
            )
            .unwrap();
        assert!(repository.get(task.id).unwrap().deleted_at.is_some());

        let restored = repository
            .undo_task_operation(delete_undo.id, deleted.updated_at + 1)
            .unwrap();
        assert_eq!(restored.deleted_at, task.deleted_at);
        assert_eq!(repository.get(task.id).unwrap(), task);
    }

    #[test]
    fn undo_rejects_edit_conflict_after_later_update() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let edited =
            update_title(task.clone(), "First edit".to_string(), task.updated_at + 1).unwrap();
        let undo = repository
            .update_with_undo(
                task.clone(),
                edited.clone(),
                TaskUndoOperation::Edit,
                edited.updated_at,
            )
            .unwrap();
        let second_edit = update_title(
            edited.clone(),
            "Second edit".to_string(),
            edited.updated_at + 1,
        )
        .unwrap();
        repository.update(second_edit).unwrap();

        assert!(matches!(
            repository.undo_task_operation(undo.id, edited.updated_at + 2),
            Err(StorageError::UndoConflict(id)) if id == task.id
        ));
    }

    #[test]
    fn complete_undo_rejects_deleted_current_task() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let done =
            transition_task(task.clone(), TaskStatus::Done, None, task.updated_at + 1).unwrap();
        let undo = repository
            .update_with_undo(
                task.clone(),
                done.clone(),
                TaskUndoOperation::Complete,
                done.updated_at,
            )
            .unwrap();
        let deleted = delete_task(done, task.updated_at + 2).unwrap();
        repository.update(deleted).unwrap();

        assert!(matches!(
            repository.undo_task_operation(undo.id, task.updated_at + 3),
            Err(StorageError::UndoConflict(id)) if id == task.id
        ));
    }

    #[test]
    fn update_returns_not_found_for_missing_task_and_list() {
        let file = NamedTempFile::new().unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut task_repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        assert!(matches!(
            task_repository.update(task.clone()),
            Err(StorageError::NotFound(id)) if id == task.id
        ));

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut list_repository = SqliteListRepository::new(connection);
        let list = sample_list("a0");
        assert!(matches!(
            list_repository.update(list.clone()),
            Err(StorageError::NotFound(id)) if id == list.id
        ));
    }
}

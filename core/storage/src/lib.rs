//! `todori-storage`: ローカルストレージアクセス層。
//!
//! SQLCipherで暗号化されたSQLite上に `ListRepository` / `TaskRepository` を実装する
//! （`docs/03_技術仕様書.md` §5）。

use std::{path::Path, str::FromStr};

use rusqlite::{params, Connection, OptionalExtension, Transaction};
use thiserror::Error;
use todori_domain::{List, Task, TaskStatus, Uuid};

const SCHEMA: &str = include_str!("schema.sql");
const BASELINE_SCHEMA_VERSION: i32 = 1;
pub const LATEST_SCHEMA_VERSION: i32 = 2;

const MIGRATIONS: &[Migration] = &[Migration {
    target_version: 2,
    name: "add_lists_archived_at",
    apply: add_lists_archived_at,
}];

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
    #[error("database cannot be read with the provided SQLCipher key")]
    InvalidDatabaseKey,
    #[error("unsupported database schema version: found {found}, latest supported {latest}")]
    UnsupportedSchemaVersion { found: i32, latest: i32 },
    #[error("incompatible database schema: {0}")]
    IncompatibleSchema(String),
    #[error(
        "failed to migrate database schema to version {target_version} ({migration}): {source}"
    )]
    MigrationFailed {
        target_version: i32,
        migration: &'static str,
        #[source]
        source: rusqlite::Error,
    },
    #[error("sqlite error: {0}")]
    Sqlite(#[from] rusqlite::Error),
}

#[derive(Clone, Copy)]
struct Migration {
    target_version: i32,
    name: &'static str,
    apply: fn(&Transaction<'_>) -> rusqlite::Result<()>,
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
    fn count_descendants(&self, task_id: Uuid) -> Result<usize, StorageError>;
    fn delete_subtree(&mut self, task_id: Uuid) -> Result<usize, StorageError>;
}

/// リストの永続化を担うリポジトリ。
///
/// SQLite(SQLCipher)実装は [`SqliteListRepository`] を参照。
pub trait ListRepository {
    fn get(&self, id: Uuid) -> Result<List, StorageError>;
    fn insert(&mut self, list: List) -> Result<(), StorageError>;
    fn update(&mut self, list: List) -> Result<(), StorageError>;
    fn list_all(&self) -> Result<Vec<List>, StorageError>;
    fn list_archived(&self) -> Result<Vec<List>, StorageError>;
    fn count_tasks(&self, list_id: Uuid) -> Result<usize, StorageError>;
    fn delete_with_tasks(&mut self, list_id: Uuid) -> Result<usize, StorageError>;
}

/// Opens a SQLCipher encrypted SQLite database and migrates it to the latest schema.
pub fn open_encrypted(path: &Path, key: &[u8; 32]) -> Result<Connection, StorageError> {
    let mut connection = Connection::open(path)?;
    apply_sqlcipher_key(&connection, key)?;
    ensure_schema(&mut connection, MIGRATIONS)?;
    Ok(connection)
}

fn apply_sqlcipher_key(connection: &Connection, key: &[u8; 32]) -> Result<(), StorageError> {
    let key_hex = hex::encode(key);
    connection.execute_batch(&format!("PRAGMA key = \"x'{key_hex}'\";"))?;
    Ok(())
}

fn ensure_schema(
    connection: &mut Connection,
    migrations: &[Migration],
) -> Result<(), StorageError> {
    let mut user_version =
        read_user_version(connection).map_err(|_| StorageError::InvalidDatabaseKey)?;
    if user_version > LATEST_SCHEMA_VERSION {
        return Err(StorageError::UnsupportedSchemaVersion {
            found: user_version,
            latest: LATEST_SCHEMA_VERSION,
        });
    }

    if user_version == 0 {
        user_version = ensure_baseline_schema(connection)?;
    }

    if user_version > LATEST_SCHEMA_VERSION {
        return Err(StorageError::UnsupportedSchemaVersion {
            found: user_version,
            latest: LATEST_SCHEMA_VERSION,
        });
    }

    apply_pending_migrations(connection, user_version, migrations)?;
    Ok(())
}

fn read_user_version(connection: &Connection) -> rusqlite::Result<i32> {
    connection.query_row("PRAGMA user_version", [], |row| row.get(0))
}

fn ensure_baseline_schema(connection: &mut Connection) -> Result<i32, StorageError> {
    if has_user_schema_objects(connection)? {
        validate_baseline_v1_schema(connection)?;
    }

    let transaction = connection.transaction()?;
    transaction.execute_batch(SCHEMA)?;
    set_user_version(&transaction, BASELINE_SCHEMA_VERSION)?;
    transaction.commit()?;

    Ok(BASELINE_SCHEMA_VERSION)
}

fn apply_pending_migrations(
    connection: &mut Connection,
    current_version: i32,
    migrations: &[Migration],
) -> Result<(), StorageError> {
    if current_version == LATEST_SCHEMA_VERSION {
        return Ok(());
    }

    let pending = migrations
        .iter()
        .filter(|migration| migration.target_version > current_version)
        .collect::<Vec<_>>();
    if pending.is_empty() {
        return Err(StorageError::IncompatibleSchema(format!(
            "missing migration from version {current_version} to {LATEST_SCHEMA_VERSION}"
        )));
    }

    for (expected_version, migration) in (current_version + 1..).zip(pending.iter()) {
        if migration.target_version != expected_version {
            return Err(StorageError::IncompatibleSchema(format!(
                "missing migration to version {expected_version}"
            )));
        }
    }

    let transaction = connection.transaction()?;
    let mut final_migration = pending[0];
    for migration in pending {
        final_migration = migration;
        (migration.apply)(&transaction).map_err(|source| StorageError::MigrationFailed {
            target_version: migration.target_version,
            migration: migration.name,
            source,
        })?;
        set_user_version(&transaction, migration.target_version).map_err(|source| {
            StorageError::MigrationFailed {
                target_version: migration.target_version,
                migration: migration.name,
                source,
            }
        })?;
    }
    transaction
        .commit()
        .map_err(|source| StorageError::MigrationFailed {
            target_version: final_migration.target_version,
            migration: final_migration.name,
            source,
        })?;

    Ok(())
}

fn set_user_version(connection: &Connection, version: i32) -> rusqlite::Result<()> {
    connection.execute_batch(&format!("PRAGMA user_version = {version};"))
}

fn add_lists_archived_at(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch("ALTER TABLE lists ADD COLUMN archived_at INTEGER NULL;")
}

fn has_user_schema_objects(connection: &Connection) -> Result<bool, StorageError> {
    let count: i64 = connection.query_row(
        "SELECT count(*)
         FROM sqlite_master
         WHERE type IN ('table', 'view')
           AND name NOT LIKE 'sqlite_%'",
        [],
        |row| row.get(0),
    )?;
    Ok(count > 0)
}

fn validate_baseline_v1_schema(connection: &Connection) -> Result<(), StorageError> {
    for (table, required_columns) in BASELINE_V1_COLUMNS {
        let columns = table_columns(connection, table)?;
        if columns.is_empty() {
            return Err(StorageError::IncompatibleSchema(format!(
                "missing baseline v1 table {table}"
            )));
        }

        for required_column in *required_columns {
            if !columns.iter().any(|column| column == required_column) {
                return Err(StorageError::IncompatibleSchema(format!(
                    "missing baseline v1 column {table}.{required_column}"
                )));
            }
        }
    }

    let list_columns = table_columns(connection, "lists")?;
    if list_columns.iter().any(|column| column == "archived_at") {
        return Err(StorageError::IncompatibleSchema(
            "lists.archived_at exists while user_version is 0".to_string(),
        ));
    }

    Ok(())
}

const BASELINE_V1_COLUMNS: &[(&str, &[&str])] = &[
    (
        "tasks",
        &[
            "id",
            "list_id",
            "parent_task_id",
            "title",
            "note",
            "status",
            "priority",
            "due_at",
            "scheduled_at",
            "estimated_minutes",
            "sort_order",
            "completed_at",
            "closed_reason",
            "deleted_at",
            "assignee",
            "created_at",
            "updated_at",
        ],
    ),
    (
        "lists",
        &[
            "id",
            "name",
            "color",
            "icon",
            "org_id",
            "sort_order",
            "created_at",
            "updated_at",
        ],
    ),
    (
        "task_undo_entries",
        &[
            "id",
            "operation_type",
            "task_id",
            "list_id",
            "before_snapshot",
            "after_updated_at",
            "after_deleted_at",
            "after_completed_at",
            "created_at",
            "consumed_at",
        ],
    ),
    ("tasks_fts", &["title", "note"]),
];

fn table_columns(connection: &Connection, table: &str) -> Result<Vec<String>, StorageError> {
    let mut statement = connection.prepare(&format!("PRAGMA table_info({table})"))?;
    let columns = statement
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(columns)
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
                   AND operation_type != 'delete'
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
             WHERE list_id = ?1
             ORDER BY sort_order ASC",
        )?;
        let tasks = statement
            .query_map([list_id.to_string()], row_to_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(tasks)
    }

    fn count_descendants(&self, task_id: Uuid) -> Result<usize, StorageError> {
        count_task_descendants_on(&self.connection, task_id)
    }

    fn delete_subtree(&mut self, task_id: Uuid) -> Result<usize, StorageError> {
        self.get(task_id)?;
        let transaction = self.connection.transaction()?;
        let deleted = delete_task_subtree_on(&transaction, task_id)?;
        transaction.commit()?;
        Ok(deleted)
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

fn count_task_descendants_on(
    connection: &Connection,
    task_id: Uuid,
) -> Result<usize, StorageError> {
    let count: i64 = connection.query_row(
        "WITH RECURSIVE subtree(id) AS (
            SELECT id FROM tasks WHERE parent_task_id = ?1
            UNION ALL
            SELECT tasks.id
            FROM tasks
            INNER JOIN subtree ON tasks.parent_task_id = subtree.id
         )
         SELECT count(*) FROM subtree",
        [task_id.to_string()],
        |row| row.get(0),
    )?;
    usize::try_from(count).map_err(|_| {
        StorageError::IncompatibleSchema("task descendant count exceeded usize".to_string())
    })
}

fn delete_task_subtree_on(connection: &Connection, task_id: Uuid) -> Result<usize, StorageError> {
    connection.execute(
        "WITH RECURSIVE subtree(id) AS (
            SELECT id FROM tasks WHERE id = ?1
            UNION ALL
            SELECT tasks.id
            FROM tasks
            INNER JOIN subtree ON tasks.parent_task_id = subtree.id
         )
         DELETE FROM task_undo_entries
         WHERE task_id IN (SELECT id FROM subtree)",
        [task_id.to_string()],
    )?;
    let deleted = connection.execute(
        "WITH RECURSIVE subtree(id) AS (
            SELECT id FROM tasks WHERE id = ?1
            UNION ALL
            SELECT tasks.id
            FROM tasks
            INNER JOIN subtree ON tasks.parent_task_id = subtree.id
         )
         DELETE FROM tasks
         WHERE id IN (SELECT id FROM subtree)",
        [task_id.to_string()],
    )?;
    Ok(deleted)
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
                "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                        created_at, updated_at
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
                id, name, color, icon, org_id, sort_order, archived_at,
                created_at, updated_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9
            )",
            params![
                list.id.to_string(),
                list.name,
                list.color,
                list.icon,
                list.org_id.map(|id| id.to_string()),
                list.sort_order,
                list.archived_at,
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
                 archived_at = ?7,
                 created_at = ?8,
                 updated_at = ?9
             WHERE id = ?1",
            params![
                list.id.to_string(),
                list.name,
                list.color,
                list.icon,
                list.org_id.map(|id| id.to_string()),
                list.sort_order,
                list.archived_at,
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
            "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                    created_at, updated_at
             FROM lists
             WHERE archived_at IS NULL
             ORDER BY sort_order ASC",
        )?;
        let lists = statement
            .query_map([], row_to_list)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(lists)
    }

    fn list_archived(&self) -> Result<Vec<List>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                    created_at, updated_at
             FROM lists
             WHERE archived_at IS NOT NULL
             ORDER BY archived_at DESC, sort_order ASC",
        )?;
        let lists = statement
            .query_map([], row_to_list)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(lists)
    }

    fn count_tasks(&self, list_id: Uuid) -> Result<usize, StorageError> {
        let count: i64 = self.connection.query_row(
            "SELECT count(*) FROM tasks WHERE list_id = ?1",
            [list_id.to_string()],
            |row| row.get(0),
        )?;
        usize::try_from(count).map_err(|_| {
            StorageError::IncompatibleSchema("list task count exceeded usize".to_string())
        })
    }

    fn delete_with_tasks(&mut self, list_id: Uuid) -> Result<usize, StorageError> {
        self.get(list_id)?;
        let transaction = self.connection.transaction()?;
        let task_count: i64 = transaction.query_row(
            "SELECT count(*) FROM tasks WHERE list_id = ?1",
            [list_id.to_string()],
            |row| row.get(0),
        )?;
        transaction.execute(
            "DELETE FROM task_undo_entries
             WHERE task_id IN (SELECT id FROM tasks WHERE list_id = ?1)",
            [list_id.to_string()],
        )?;
        transaction.execute(
            "DELETE FROM tasks WHERE list_id = ?1",
            [list_id.to_string()],
        )?;
        let changed =
            transaction.execute("DELETE FROM lists WHERE id = ?1", [list_id.to_string()])?;
        if changed == 0 {
            return Err(StorageError::NotFound(list_id));
        }
        transaction.commit()?;
        usize::try_from(task_count).map_err(|_| {
            StorageError::IncompatibleSchema("list task count exceeded usize".to_string())
        })
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
        archived_at: row.get(6)?,
        created_at: row.get(7)?,
        updated_at: row.get(8)?,
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
    use todori_domain::{new_list, new_task, transition_task, update_title};

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
            archived_at: None,
            created_at: 1_799_000_000_000,
            updated_at: 1_799_000_000_000,
        }
    }

    fn open_raw_encrypted(path: &Path, key: &[u8; 32]) -> Connection {
        let connection = Connection::open(path).unwrap();
        apply_sqlcipher_key(&connection, key).unwrap();
        connection
    }

    fn create_baseline_v1_database(path: &Path, key: &[u8; 32], set_version: bool) {
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        transaction.execute_batch(SCHEMA).unwrap();
        if set_version {
            set_user_version(&transaction, BASELINE_SCHEMA_VERSION).unwrap();
        }
        transaction.commit().unwrap();
    }

    fn insert_baseline_v1_list(connection: &Connection, list: &List) {
        connection
            .execute(
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
            )
            .unwrap();
    }

    fn archived_at_column(connection: &Connection) -> Option<(String, i32)> {
        let mut statement = connection.prepare("PRAGMA table_info(lists)").unwrap();
        statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i32>(3)?,
                ))
            })
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .find_map(|(name, column_type, not_null)| {
                (name == "archived_at").then_some((column_type, not_null))
            })
    }

    fn count_archived_at_columns(connection: &Connection) -> usize {
        let mut statement = connection.prepare("PRAGMA table_info(lists)").unwrap();
        statement
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .filter(|column| column == "archived_at")
            .count()
    }

    fn schema_version(connection: &Connection) -> i32 {
        connection
            .query_row("PRAGMA schema_version", [], |row| row.get(0))
            .unwrap()
    }

    fn failing_archived_at_migration(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
        transaction.execute_batch(
            "ALTER TABLE lists ADD COLUMN archived_at INTEGER NULL;
             SELECT value FROM missing_failure_injection_table;",
        )
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

        match result {
            Err(StorageError::InvalidDatabaseKey) => {}
            Err(error) => panic!("expected invalid database key error, got {error}"),
            Ok(_) => panic!("database opened with wrong key"),
        }
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
    fn new_database_is_created_via_baseline_and_migrated_to_latest_schema() {
        let file = NamedTempFile::new().unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            archived_at_column(&connection),
            Some(("INTEGER".to_string(), 0))
        );
    }

    #[test]
    fn v1_database_migrates_to_v2_and_preserves_existing_data() {
        let file = NamedTempFile::new().unwrap();
        create_baseline_v1_database(file.path(), &KEY, true);

        let list = sample_list("a0");
        let mut task = sample_task();
        task.list_id = list.id;
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            insert_baseline_v1_list(&connection, &list);
        }
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            archived_at_column(&connection),
            Some(("INTEGER".to_string(), 0))
        );
        assert_eq!(
            SqliteListRepository::new(open_encrypted(file.path(), &KEY).unwrap())
                .get(list.id)
                .unwrap(),
            list
        );
        assert_eq!(
            SqliteTaskRepository::new(open_encrypted(file.path(), &KEY).unwrap())
                .get(task.id)
                .unwrap(),
            task
        );
    }

    #[test]
    fn legacy_user_version_zero_v1_database_is_promoted_and_migrated() {
        let file = NamedTempFile::new().unwrap();
        create_baseline_v1_database(file.path(), &KEY, false);

        let list = sample_list("legacy");
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            insert_baseline_v1_list(&connection, &list);
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            archived_at_column(&connection),
            Some(("INTEGER".to_string(), 0))
        );
        assert_eq!(
            SqliteListRepository::new(connection).get(list.id).unwrap(),
            list
        );
    }

    #[test]
    fn latest_schema_reopen_does_not_reapply_migrations() {
        let file = NamedTempFile::new().unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let before_schema_version = schema_version(&connection);
        let before_user_version = read_user_version(&connection).unwrap();
        let before_archived_at_count = count_archived_at_columns(&connection);
        drop(connection);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(read_user_version(&connection).unwrap(), before_user_version);
        assert_eq!(schema_version(&connection), before_schema_version);
        assert_eq!(
            count_archived_at_columns(&connection),
            before_archived_at_count
        );
    }

    #[test]
    fn failed_migration_rolls_back_archived_at_and_user_version() {
        let file = NamedTempFile::new().unwrap();
        create_baseline_v1_database(file.path(), &KEY, true);
        let mut connection = open_raw_encrypted(file.path(), &KEY);
        let failing_migrations = &[Migration {
            target_version: 2,
            name: "failing_archived_at",
            apply: failing_archived_at_migration,
        }];

        let result =
            apply_pending_migrations(&mut connection, BASELINE_SCHEMA_VERSION, failing_migrations);

        assert!(matches!(
            result,
            Err(StorageError::MigrationFailed {
                target_version: 2,
                migration: "failing_archived_at",
                ..
            })
        ));
        assert_eq!(
            read_user_version(&connection).unwrap(),
            BASELINE_SCHEMA_VERSION
        );
        assert_eq!(archived_at_column(&connection), None);
    }

    #[test]
    fn unsupported_newer_schema_version_is_rejected() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_raw_encrypted(file.path(), &KEY);
        set_user_version(&connection, LATEST_SCHEMA_VERSION + 1).unwrap();
        drop(connection);

        let result = open_encrypted(file.path(), &KEY);

        assert!(matches!(
            result,
            Err(StorageError::UnsupportedSchemaVersion { found, latest })
                if found == LATEST_SCHEMA_VERSION + 1 && latest == LATEST_SCHEMA_VERSION
        ));
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
        first.archived_at = Some(1_799_000_001_000);
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
            vec![second.id]
        );
        assert_eq!(
            repository
                .list_archived()
                .unwrap()
                .into_iter()
                .map(|list| list.id)
                .collect::<Vec<_>>(),
            vec![first.id]
        );
    }

    #[test]
    fn delete_list_removes_tasks_and_task_undo_entries() {
        let file = NamedTempFile::new().unwrap();
        let list = new_list("Inbox".to_string(), "a0".to_string(), 1_700_000_000_000).unwrap();
        let task = new_task(
            list.id,
            None,
            "Task".to_string(),
            "a0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(task.clone()).unwrap();
            let edited =
                update_title(task.clone(), "Edited".to_string(), task.updated_at + 1).unwrap();
            task_repository
                .update_with_undo(
                    task.clone(),
                    edited,
                    TaskUndoOperation::Edit,
                    task.updated_at + 1,
                )
                .unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut list_repository = SqliteListRepository::new(connection);
        assert_eq!(list_repository.count_tasks(list.id).unwrap(), 1);
        assert_eq!(list_repository.delete_with_tasks(list.id).unwrap(), 1);
        assert!(matches!(
            list_repository.get(list.id),
            Err(StorageError::NotFound(id)) if id == list.id
        ));

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let task_repository = SqliteTaskRepository::new(connection);
        assert!(matches!(
            task_repository.get(task.id),
            Err(StorageError::NotFound(id)) if id == task.id
        ));
        assert!(task_repository.latest_unconsumed_undo().unwrap().is_none());
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
    fn delete_subtree_removes_root_descendants_and_undo_entries() {
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
        let parent = new_task(
            list.id,
            None,
            "Delete parent".to_string(),
            "b0".to_string(),
            1_700_000_001_000,
        )
        .unwrap();
        let child = new_task(
            list.id,
            Some(parent.id),
            "Delete child".to_string(),
            "a0".to_string(),
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
        task_repository.insert(parent.clone()).unwrap();
        task_repository.insert(child).unwrap();

        let updated = update_title(
            parent.clone(),
            "Before delete".to_string(),
            parent.updated_at + 1,
        )
        .unwrap();
        task_repository
            .update_with_undo(
                parent.clone(),
                updated,
                TaskUndoOperation::Edit,
                parent.updated_at + 1,
            )
            .unwrap();

        assert_eq!(task_repository.count_descendants(parent.id).unwrap(), 1);
        assert_eq!(task_repository.delete_subtree(parent.id).unwrap(), 2);
        assert!(matches!(
            task_repository.get(parent.id),
            Err(StorageError::NotFound(id)) if id == parent.id
        ));
        assert_eq!(
            task_repository.list_active_by_list(list.id).unwrap(),
            vec![active]
        );
        assert!(task_repository.latest_unconsumed_undo().unwrap().is_none());
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
    fn delete_undo_entries_are_not_returned_as_latest_undo() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let task = sample_task();
        repository.insert(task.clone()).unwrap();

        let mut deleted = task.clone();
        deleted.deleted_at = Some(task.updated_at + 1);
        deleted.updated_at = task.updated_at + 1;
        repository
            .update_with_undo(
                task.clone(),
                deleted.clone(),
                TaskUndoOperation::Delete,
                deleted.updated_at,
            )
            .unwrap();

        assert!(repository.latest_unconsumed_undo().unwrap().is_none());
    }

    #[test]
    fn complete_undo_entry_restores_task_state() {
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
    fn complete_undo_rejects_physically_deleted_current_task() {
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
        repository.delete_subtree(done.id).unwrap();

        assert!(matches!(
            repository.undo_task_operation(undo.id, task.updated_at + 3),
            Err(StorageError::NotFound(id)) if id == undo.id
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

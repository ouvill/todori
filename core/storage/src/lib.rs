//! `todori-storage`: ローカルストレージアクセス層。
//!
//! SQLCipherで暗号化されたSQLite上に `ListRepository` / `TaskRepository` を実装する
//! （`docs/03_技術仕様書.md` §5）。

use std::{path::Path, str::FromStr};

use rusqlite::{params, Connection, OptionalExtension, Transaction};
use thiserror::Error;
use todori_domain::{new_default_list, List, Task, TaskStatus, Uuid};

const SCHEMA: &str = include_str!("schema.sql");
const BASELINE_SCHEMA_VERSION: i32 = 1;
pub const LATEST_SCHEMA_VERSION: i32 = 6;

const MIGRATIONS: &[Migration] = &[
    Migration {
        target_version: 2,
        name: "add_lists_archived_at",
        apply: add_lists_archived_at,
    },
    Migration {
        target_version: 3,
        name: "add_lists_is_default",
        apply: add_lists_is_default,
    },
    Migration {
        target_version: 4,
        name: "rebuild_tasks_fts_triggers",
        apply: rebuild_tasks_fts_triggers,
    },
    Migration {
        target_version: 5,
        name: "add_settings",
        apply: add_settings,
    },
    Migration {
        target_version: 6,
        name: "add_reminders",
        apply: add_reminders,
    },
];

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
    #[error("default list cannot be {operation}: {list_id}")]
    DefaultListProtected {
        operation: &'static str,
        list_id: Uuid,
    },
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

/// A task returned by the cross-list Home smart view, annotated with its
/// containing list name for UI context.
#[derive(Debug, Clone, PartialEq)]
pub struct HomeTask {
    pub task: Task,
    pub list_name: String,
    pub is_home_target: bool,
}

/// A local reminder scheduled on the device for a task.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reminder {
    pub id: Uuid,
    pub task_id: Uuid,
    pub remind_at: i64,
    pub snoozed_until: Option<i64>,
    pub created_at: i64,
}

/// タスクの永続化を担うリポジトリ。
///
/// SQLite(SQLCipher)実装は [`SqliteTaskRepository`] を参照。同期シグネチャのみを定義する。
pub trait TaskRepository {
    fn get(&self, id: Uuid) -> Result<Task, StorageError>;
    fn insert(&mut self, task: Task) -> Result<(), StorageError>;
    fn update(&mut self, task: Task) -> Result<(), StorageError>;
    fn list_active_by_list(&self, list_id: Uuid) -> Result<Vec<Task>, StorageError>;
    fn list_home(
        &self,
        today_start_ms: i64,
        tomorrow_start_ms: i64,
    ) -> Result<Vec<HomeTask>, StorageError>;
    fn search_tasks(&self, query: &str) -> Result<Vec<Task>, StorageError>;
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
    fn get_default(&self) -> Result<Option<List>, StorageError>;
    fn ensure_default_list(&mut self, name: String, now_ms: i64) -> Result<List, StorageError>;
    fn count_tasks(&self, list_id: Uuid) -> Result<usize, StorageError>;
    fn delete_with_tasks(&mut self, list_id: Uuid) -> Result<usize, StorageError>;
}

/// 設定値の永続化を担うリポジトリ。
///
/// 値はSQLCipher暗号化DB内に保存し、キーごとの最新値だけを保持する。
pub trait SettingsRepository {
    fn get_setting(&self, key: &str) -> Result<Option<String>, StorageError>;
    fn set_setting(&mut self, key: &str, value: &str, updated_at: i64) -> Result<(), StorageError>;
}

/// リマインダーの永続化を担うリポジトリ。
pub trait ReminderRepository {
    fn set_task_reminder(
        &mut self,
        task_id: Uuid,
        remind_at: i64,
        created_at: i64,
    ) -> Result<Reminder, StorageError>;
    fn clear_task_reminders(&mut self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError>;
    fn list_task_reminders(&self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError>;
    fn list_task_subtree_reminders(&self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError>;
    fn list_list_reminders(&self, list_id: Uuid) -> Result<Vec<Reminder>, StorageError>;
    fn list_pending_reminders(&self, now_ms: i64) -> Result<Vec<Reminder>, StorageError>;
    fn snooze_reminder(
        &mut self,
        reminder_id: Uuid,
        snoozed_until: i64,
    ) -> Result<Reminder, StorageError>;
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

fn add_lists_is_default(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "ALTER TABLE lists ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0;
         UPDATE lists
         SET is_default = 1
         WHERE id = (
             SELECT id
             FROM lists
             WHERE archived_at IS NULL
             ORDER BY sort_order ASC, created_at ASC, id ASC
             LIMIT 1
         );
         CREATE UNIQUE INDEX idx_lists_single_default
             ON lists(is_default)
             WHERE is_default = 1;",
    )
}

fn rebuild_tasks_fts_triggers(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "DROP TRIGGER IF EXISTS tasks_fts_ai;
         DROP TRIGGER IF EXISTS tasks_fts_au;
         DROP TRIGGER IF EXISTS tasks_fts_au_delete;
         DROP TRIGGER IF EXISTS tasks_fts_au_insert;
         DROP TRIGGER IF EXISTS tasks_fts_ad;
         DROP TABLE IF EXISTS tasks_fts;

         CREATE VIRTUAL TABLE tasks_fts USING fts5(
             task_id UNINDEXED,
             title,
             note,
             tokenize = 'unicode61'
         );

         INSERT INTO tasks_fts(task_id, title, note)
         SELECT id, title, note
         FROM tasks
         WHERE deleted_at IS NULL;

         CREATE TRIGGER tasks_fts_ai
         AFTER INSERT ON tasks
         WHEN NEW.deleted_at IS NULL
         BEGIN
             INSERT INTO tasks_fts(task_id, title, note)
             VALUES (NEW.id, NEW.title, NEW.note);
         END;

         CREATE TRIGGER tasks_fts_au
         AFTER UPDATE OF id, title, note, deleted_at ON tasks
         BEGIN
             DELETE FROM tasks_fts WHERE task_id = OLD.id;
             INSERT INTO tasks_fts(task_id, title, note)
             SELECT NEW.id, NEW.title, NEW.note
             WHERE NEW.deleted_at IS NULL;
         END;

         CREATE TRIGGER tasks_fts_ad
         AFTER DELETE ON tasks
         BEGIN
             DELETE FROM tasks_fts WHERE task_id = OLD.id;
         END;",
    )
}

fn add_settings(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE settings (
             key TEXT PRIMARY KEY,
             value TEXT NOT NULL,
             updated_at INTEGER NOT NULL
         );",
    )
}

fn add_reminders(transaction: &Transaction<'_>) -> rusqlite::Result<()> {
    transaction.execute_batch(
        "CREATE TABLE IF NOT EXISTS reminders (
             id TEXT PRIMARY KEY NOT NULL,
             task_id TEXT NOT NULL,
             remind_at INTEGER NOT NULL,
             snoozed_until INTEGER,
             created_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS idx_reminders_task_id ON reminders(task_id);
         CREATE INDEX IF NOT EXISTS idx_reminders_pending
             ON reminders(snoozed_until, remind_at);",
    )
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
    if list_columns.iter().any(|column| column == "is_default") {
        return Err(StorageError::IncompatibleSchema(
            "lists.is_default exists while user_version is 0".to_string(),
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

    fn list_home(
        &self,
        today_start_ms: i64,
        tomorrow_start_ms: i64,
    ) -> Result<Vec<HomeTask>, StorageError> {
        let mut statement = self.connection.prepare(
            "WITH RECURSIVE home_targets(id) AS (
                 SELECT tasks.id
                 FROM tasks
                 INNER JOIN lists ON lists.id = tasks.list_id
                 WHERE lists.archived_at IS NULL
                   AND tasks.due_at IS NOT NULL
                   AND (
                       tasks.status IN ('todo', 'in_progress')
                       OR (
                           tasks.status IN ('done', 'wont_do')
                           AND tasks.completed_at >= ?1
                           AND tasks.completed_at < ?2
                       )
                   )
             ),
             home_scope(id) AS (
                 SELECT id FROM home_targets
                 UNION
                 SELECT child.id
                 FROM tasks child
                 INNER JOIN home_scope parent ON child.parent_task_id = parent.id
             ),
             home_ancestors(id) AS (
                 SELECT tasks.parent_task_id
                 FROM tasks
                 INNER JOIN home_targets ON home_targets.id = tasks.id
                 WHERE tasks.parent_task_id IS NOT NULL
                 UNION
                 SELECT tasks.parent_task_id
                 FROM tasks
                 INNER JOIN home_ancestors ancestor ON ancestor.id = tasks.id
                 WHERE tasks.parent_task_id IS NOT NULL
             ),
             home_display_scope(id) AS (
                 SELECT id FROM home_scope
                 UNION
                 SELECT id FROM home_ancestors
             )
             SELECT tasks.id, tasks.list_id, tasks.parent_task_id, tasks.title,
                    tasks.note, tasks.status, tasks.priority, tasks.due_at,
                    tasks.scheduled_at, tasks.estimated_minutes, tasks.sort_order,
                    tasks.completed_at, tasks.closed_reason, tasks.deleted_at,
                    tasks.assignee, tasks.created_at, tasks.updated_at,
                    lists.name,
                    EXISTS(SELECT 1 FROM home_targets WHERE home_targets.id = tasks.id)
             FROM tasks
             INNER JOIN lists ON lists.id = tasks.list_id
             INNER JOIN home_display_scope ON home_display_scope.id = tasks.id
             WHERE lists.archived_at IS NULL
             ORDER BY tasks.due_at IS NULL ASC,
                      tasks.due_at ASC,
                      tasks.sort_order ASC,
                      tasks.id ASC",
        )?;
        let tasks = statement
            .query_map(params![today_start_ms, tomorrow_start_ms], row_to_home_task)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(tasks)
    }

    fn search_tasks(&self, query: &str) -> Result<Vec<Task>, StorageError> {
        let Some(match_query) = build_fts_prefix_query(query) else {
            return Ok(Vec::new());
        };

        let mut statement = self.connection.prepare(
            "SELECT tasks.id, tasks.list_id, tasks.parent_task_id, tasks.title,
                    tasks.note, tasks.status, tasks.priority, tasks.due_at,
                    tasks.scheduled_at, tasks.estimated_minutes, tasks.sort_order,
                    tasks.completed_at, tasks.closed_reason, tasks.deleted_at,
                    tasks.assignee, tasks.created_at, tasks.updated_at
             FROM tasks_fts
             INNER JOIN tasks ON tasks.id = tasks_fts.task_id
             WHERE tasks_fts MATCH ?1
               AND tasks.deleted_at IS NULL
             ORDER BY bm25(tasks_fts) ASC,
                      tasks.updated_at DESC,
                      tasks.id ASC",
        )?;
        let tasks = statement
            .query_map([match_query], row_to_task)?
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

fn build_fts_prefix_query(query: &str) -> Option<String> {
    let terms = query
        .split_whitespace()
        .filter(|term| !term.is_empty())
        .map(|term| format!("\"{}\"*", term.replace('"', "\"\"")))
        .collect::<Vec<_>>();

    (!terms.is_empty()).then(|| terms.join(" AND "))
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
    connection.execute(
        "WITH RECURSIVE subtree(id) AS (
            SELECT id FROM tasks WHERE id = ?1
            UNION ALL
            SELECT tasks.id
            FROM tasks
            INNER JOIN subtree ON tasks.parent_task_id = subtree.id
         )
         DELETE FROM reminders
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
                        is_default, created_at, updated_at
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
                id, name, color, icon, org_id, sort_order, is_default, archived_at,
                created_at, updated_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10
            )",
            params![
                list.id.to_string(),
                list.name,
                list.color,
                list.icon,
                list.org_id.map(|id| id.to_string()),
                list.sort_order,
                list.is_default,
                list.archived_at,
                list.created_at,
                list.updated_at,
            ],
        )?;
        Ok(())
    }

    fn update(&mut self, list: List) -> Result<(), StorageError> {
        if list.is_default && list.archived_at.is_some() {
            return Err(StorageError::DefaultListProtected {
                operation: "archived",
                list_id: list.id,
            });
        }
        let changed = self.connection.execute(
            "UPDATE lists
             SET name = ?2,
                 color = ?3,
                 icon = ?4,
                 org_id = ?5,
                 sort_order = ?6,
                 is_default = ?7,
                 archived_at = ?8,
                 created_at = ?9,
                 updated_at = ?10
             WHERE id = ?1",
            params![
                list.id.to_string(),
                list.name,
                list.color,
                list.icon,
                list.org_id.map(|id| id.to_string()),
                list.sort_order,
                list.is_default,
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
                    is_default, created_at, updated_at
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
                    is_default, created_at, updated_at
             FROM lists
             WHERE archived_at IS NOT NULL
             ORDER BY archived_at DESC, sort_order ASC",
        )?;
        let lists = statement
            .query_map([], row_to_list)?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(lists)
    }

    fn get_default(&self) -> Result<Option<List>, StorageError> {
        self.connection
            .query_row(
                "SELECT id, name, color, icon, org_id, sort_order, archived_at,
                        is_default, created_at, updated_at
                 FROM lists
                 WHERE is_default = 1
                 LIMIT 1",
                [],
                row_to_list,
            )
            .optional()
            .map_err(StorageError::from)
    }

    fn ensure_default_list(&mut self, name: String, now_ms: i64) -> Result<List, StorageError> {
        if let Some(list) = self.get_default()? {
            return Ok(list);
        }

        let existing_count: i64 =
            self.connection
                .query_row("SELECT count(*) FROM lists", [], |row| row.get(0))?;
        let sort_order = format!("a{existing_count}");
        let list = new_default_list(name, sort_order, now_ms)
            .map_err(|error| StorageError::IncompatibleSchema(error.to_string()))?;
        self.insert(list.clone())?;
        Ok(list)
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
        let list = self.get(list_id)?;
        if list.is_default {
            return Err(StorageError::DefaultListProtected {
                operation: "deleted",
                list_id,
            });
        }
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
            "DELETE FROM reminders
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

/// SQLite-backed implementation of [`SettingsRepository`].
pub struct SqliteSettingsRepository {
    connection: Connection,
}

impl SqliteSettingsRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }
}

impl SettingsRepository for SqliteSettingsRepository {
    fn get_setting(&self, key: &str) -> Result<Option<String>, StorageError> {
        self.connection
            .query_row(
                "SELECT value
                 FROM settings
                 WHERE key = ?1",
                [key],
                |row| row.get(0),
            )
            .optional()
            .map_err(StorageError::from)
    }

    fn set_setting(&mut self, key: &str, value: &str, updated_at: i64) -> Result<(), StorageError> {
        self.connection.execute(
            "INSERT INTO settings (key, value, updated_at)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(key) DO UPDATE SET
                 value = excluded.value,
                 updated_at = excluded.updated_at",
            params![key, value, updated_at],
        )?;
        Ok(())
    }
}

/// SQLite-backed implementation of [`ReminderRepository`].
pub struct SqliteReminderRepository {
    connection: Connection,
}

impl SqliteReminderRepository {
    pub fn new(connection: Connection) -> Self {
        Self { connection }
    }

    pub fn connection(&self) -> &Connection {
        &self.connection
    }
}

impl ReminderRepository for SqliteReminderRepository {
    fn set_task_reminder(
        &mut self,
        task_id: Uuid,
        remind_at: i64,
        created_at: i64,
    ) -> Result<Reminder, StorageError> {
        ensure_task_exists(&self.connection, task_id)?;
        let reminder = Reminder {
            id: Uuid::now_v7(),
            task_id,
            remind_at,
            snoozed_until: None,
            created_at,
        };
        let transaction = self.connection.transaction()?;
        delete_task_reminders_on(&transaction, task_id)?;
        insert_reminder_on(&transaction, &reminder)?;
        transaction.commit()?;
        Ok(reminder)
    }

    fn clear_task_reminders(&mut self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError> {
        let reminders = list_task_reminders_on(&self.connection, task_id)?;
        delete_task_reminders_on(&self.connection, task_id)?;
        Ok(reminders)
    }

    fn list_task_reminders(&self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError> {
        list_task_reminders_on(&self.connection, task_id)
    }

    fn list_task_subtree_reminders(&self, task_id: Uuid) -> Result<Vec<Reminder>, StorageError> {
        ensure_task_exists(&self.connection, task_id)?;
        let mut statement = self.connection.prepare(
            "WITH RECURSIVE subtree(id) AS (
                 SELECT id FROM tasks WHERE id = ?1
                 UNION ALL
                 SELECT tasks.id
                 FROM tasks
                 INNER JOIN subtree ON tasks.parent_task_id = subtree.id
             )
             SELECT id, task_id, remind_at, snoozed_until, created_at
             FROM reminders
             WHERE task_id IN (SELECT id FROM subtree)
             ORDER BY COALESCE(snoozed_until, remind_at) ASC, created_at ASC, id ASC",
        )?;
        let reminders = statement
            .query_map([task_id.to_string()], row_to_reminder)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(reminders)
    }

    fn list_list_reminders(&self, list_id: Uuid) -> Result<Vec<Reminder>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT reminders.id, reminders.task_id, reminders.remind_at,
                    reminders.snoozed_until, reminders.created_at
             FROM reminders
             INNER JOIN tasks ON tasks.id = reminders.task_id
             WHERE tasks.list_id = ?1
             ORDER BY COALESCE(reminders.snoozed_until, reminders.remind_at) ASC,
                      reminders.created_at ASC,
                      reminders.id ASC",
        )?;
        let reminders = statement
            .query_map([list_id.to_string()], row_to_reminder)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(reminders)
    }

    fn list_pending_reminders(&self, now_ms: i64) -> Result<Vec<Reminder>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT reminders.id, reminders.task_id, reminders.remind_at,
                    reminders.snoozed_until, reminders.created_at
             FROM reminders
             INNER JOIN tasks ON tasks.id = reminders.task_id
             WHERE COALESCE(reminders.snoozed_until, reminders.remind_at) > ?1
               AND tasks.status IN ('todo', 'in_progress')
               AND tasks.deleted_at IS NULL
             ORDER BY COALESCE(reminders.snoozed_until, reminders.remind_at) ASC,
                      reminders.created_at ASC,
                      reminders.id ASC",
        )?;
        let reminders = statement
            .query_map([now_ms], row_to_reminder)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(reminders)
    }

    fn snooze_reminder(
        &mut self,
        reminder_id: Uuid,
        snoozed_until: i64,
    ) -> Result<Reminder, StorageError> {
        let changed = self.connection.execute(
            "UPDATE reminders
             SET snoozed_until = ?2
             WHERE id = ?1",
            params![reminder_id.to_string(), snoozed_until],
        )?;
        if changed == 0 {
            return Err(StorageError::NotFound(reminder_id));
        }
        self.connection
            .query_row(
                "SELECT id, task_id, remind_at, snoozed_until, created_at
                 FROM reminders
                 WHERE id = ?1",
                [reminder_id.to_string()],
                row_to_reminder,
            )
            .map_err(StorageError::from)
    }
}

fn ensure_task_exists(connection: &Connection, task_id: Uuid) -> Result<(), StorageError> {
    let exists = connection
        .query_row(
            "SELECT 1 FROM tasks WHERE id = ?1 LIMIT 1",
            [task_id.to_string()],
            |_| Ok(()),
        )
        .optional()?;
    exists.ok_or(StorageError::NotFound(task_id))
}

fn list_task_reminders_on(
    connection: &Connection,
    task_id: Uuid,
) -> Result<Vec<Reminder>, StorageError> {
    let mut statement = connection.prepare(
        "SELECT id, task_id, remind_at, snoozed_until, created_at
         FROM reminders
         WHERE task_id = ?1
         ORDER BY COALESCE(snoozed_until, remind_at) ASC, created_at ASC, id ASC",
    )?;
    let reminders = statement
        .query_map([task_id.to_string()], row_to_reminder)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(reminders)
}

fn insert_reminder_on(connection: &Connection, reminder: &Reminder) -> Result<(), StorageError> {
    connection.execute(
        "INSERT INTO reminders (id, task_id, remind_at, snoozed_until, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![
            reminder.id.to_string(),
            reminder.task_id.to_string(),
            reminder.remind_at,
            reminder.snoozed_until,
            reminder.created_at,
        ],
    )?;
    Ok(())
}

fn delete_task_reminders_on(connection: &Connection, task_id: Uuid) -> Result<(), StorageError> {
    connection.execute(
        "DELETE FROM reminders WHERE task_id = ?1",
        [task_id.to_string()],
    )?;
    Ok(())
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
        is_default: row.get(7)?,
        created_at: row.get(8)?,
        updated_at: row.get(9)?,
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

fn row_to_home_task(row: &rusqlite::Row<'_>) -> rusqlite::Result<HomeTask> {
    Ok(HomeTask {
        task: row_to_task(row)?,
        list_name: row.get(17)?,
        is_home_target: row.get(18)?,
    })
}

fn row_to_reminder(row: &rusqlite::Row<'_>) -> rusqlite::Result<Reminder> {
    let id: String = row.get(0)?;
    let task_id: String = row.get(1)?;
    Ok(Reminder {
        id: parse_uuid(id, 0)?,
        task_id: parse_uuid(task_id, 1)?,
        remind_at: row.get(2)?,
        snoozed_until: row.get(3)?,
        created_at: row.get(4)?,
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
            is_default: false,
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

    fn create_v2_database(path: &Path, key: &[u8; 32]) {
        create_baseline_v1_database(path, key, true);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_lists_archived_at(&transaction).unwrap();
        set_user_version(&transaction, 2).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v3_database(path: &Path, key: &[u8; 32]) {
        create_v2_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_lists_is_default(&transaction).unwrap();
        set_user_version(&transaction, 3).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v4_database(path: &Path, key: &[u8; 32]) {
        create_v3_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        rebuild_tasks_fts_triggers(&transaction).unwrap();
        set_user_version(&transaction, 4).unwrap();
        transaction.commit().unwrap();
    }

    fn create_v5_database(path: &Path, key: &[u8; 32]) {
        create_v4_database(path, key);
        let mut connection = open_raw_encrypted(path, key);
        let transaction = connection.transaction().unwrap();
        add_settings(&transaction).unwrap();
        set_user_version(&transaction, 5).unwrap();
        transaction.commit().unwrap();
    }

    fn insert_v2_list(connection: &Connection, list: &List) {
        connection
            .execute(
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
            )
            .unwrap();
    }

    fn list_column(connection: &Connection, target: &str) -> Option<(String, i32, String)> {
        let mut statement = connection.prepare("PRAGMA table_info(lists)").unwrap();
        statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i32>(3)?,
                    row.get::<_, Option<String>>(4)?.unwrap_or_default(),
                ))
            })
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
            .unwrap()
            .into_iter()
            .find_map(|(name, column_type, not_null, default_value)| {
                (name == target).then_some((column_type, not_null, default_value))
            })
    }

    fn archived_at_column(connection: &Connection) -> Option<(String, i32)> {
        list_column(connection, "archived_at")
            .map(|(column_type, not_null, _)| (column_type, not_null))
    }

    fn is_default_column(connection: &Connection) -> Option<(String, i32, String)> {
        list_column(connection, "is_default")
    }

    fn setting_column(connection: &Connection, target: &str) -> Option<(String, i32)> {
        let mut statement = connection.prepare("PRAGMA table_info(settings)").unwrap();
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
                (name == target).then_some((column_type, not_null))
            })
    }

    fn reminder_column(connection: &Connection, target: &str) -> Option<(String, i32)> {
        let mut statement = connection.prepare("PRAGMA table_info(reminders)").unwrap();
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
                (name == target).then_some((column_type, not_null))
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

    fn default_list_ids(connection: &Connection) -> Vec<String> {
        let mut statement = connection
            .prepare("SELECT id FROM lists WHERE is_default = 1 ORDER BY id ASC")
            .unwrap();
        statement
            .query_map([], |row| row.get::<_, String>(0))
            .unwrap()
            .collect::<rusqlite::Result<Vec<_>>>()
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
        let mut repository = SqliteTaskRepository::new(connection);
        let mut task = sample_task();
        task.title = "Plan Kyoto trip".to_string();
        task.note = "Book shinkansen tickets".to_string();

        repository.insert(task.clone()).unwrap();

        assert_eq!(
            repository.search_tasks("kyoto").unwrap(),
            vec![task.clone()]
        );
        assert_eq!(repository.search_tasks("shinkansen").unwrap(), vec![task]);
        assert!(repository.search_tasks("").unwrap().is_empty());
    }

    #[test]
    fn fts5_search_tracks_title_note_updates_and_deleted_at() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let mut task = sample_task();
        task.title = "Draft itinerary".to_string();
        task.note = "Reserve hotel".to_string();
        repository.insert(task.clone()).unwrap();

        assert_eq!(
            repository.search_tasks("hotel").unwrap(),
            vec![task.clone()]
        );

        let mut updated = task.clone();
        updated.title = "Final packing list".to_string();
        updated.note = "Bring passport".to_string();
        updated.updated_at += 1;
        repository.update(updated.clone()).unwrap();

        assert!(repository.search_tasks("hotel").unwrap().is_empty());
        assert_eq!(
            repository.search_tasks("passport").unwrap(),
            vec![updated.clone()]
        );

        let mut deleted = updated.clone();
        deleted.deleted_at = Some(updated.updated_at + 1);
        deleted.updated_at += 1;
        repository.update(deleted.clone()).unwrap();

        assert!(repository.search_tasks("passport").unwrap().is_empty());

        let mut restored = deleted.clone();
        restored.deleted_at = None;
        restored.updated_at += 1;
        repository.update(restored.clone()).unwrap();

        assert_eq!(repository.search_tasks("passport").unwrap(), vec![restored]);
    }

    #[test]
    fn fts5_search_tracks_physical_task_and_list_deletes() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        let mut kept = sample_task();
        kept.list_id = list.id;
        kept.title = "Keep searchable".to_string();
        kept.note = "retained".to_string();
        kept.sort_order = "a0".to_string();
        let mut task_deleted_by_subtree = sample_task();
        task_deleted_by_subtree.list_id = list.id;
        task_deleted_by_subtree.title = "Delete searchable subtree".to_string();
        task_deleted_by_subtree.note = "temporary".to_string();
        task_deleted_by_subtree.sort_order = "a1".to_string();
        let mut task_deleted_by_list = sample_task();
        task_deleted_by_list.list_id = list.id;
        task_deleted_by_list.title = "Delete searchable list".to_string();
        task_deleted_by_list.note = "temporary".to_string();
        task_deleted_by_list.sort_order = "a2".to_string();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(kept.clone()).unwrap();
            task_repository
                .insert(task_deleted_by_subtree.clone())
                .unwrap();
            task_repository
                .insert(task_deleted_by_list.clone())
                .unwrap();
            assert_eq!(task_repository.search_tasks("searchable").unwrap().len(), 3);

            task_repository
                .delete_subtree(task_deleted_by_subtree.id)
                .unwrap();
            let titles = task_repository
                .search_tasks("searchable")
                .unwrap()
                .into_iter()
                .map(|task| task.title)
                .collect::<Vec<_>>();
            let mut titles = titles;
            titles.sort();
            assert_eq!(titles, vec!["Delete searchable list", "Keep searchable"]);
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut list_repository = SqliteListRepository::new(connection);
        list_repository.delete_with_tasks(list.id).unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let task_repository = SqliteTaskRepository::new(connection);
        assert!(task_repository
            .search_tasks("searchable")
            .unwrap()
            .is_empty());
    }

    #[test]
    fn fts5_search_supports_english_and_japanese_prefix_queries() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteTaskRepository::new(connection);
        let mut english = sample_task();
        english.title = "Buy milk".to_string();
        english.note = "Organic whole milk".to_string();
        english.updated_at = 1_799_000_000_000;
        let mut japanese = sample_task();
        japanese.title = "牛乳を買う".to_string();
        japanese.note = "明日の朝".to_string();
        japanese.updated_at = 1_799_000_001_000;
        repository.insert(english.clone()).unwrap();
        repository.insert(japanese.clone()).unwrap();

        assert_eq!(repository.search_tasks("milk").unwrap(), vec![english]);
        assert_eq!(
            repository.search_tasks("牛乳").unwrap(),
            vec![japanese.clone()]
        );
        assert_eq!(repository.search_tasks("明日").unwrap(), vec![japanese]);
        assert!(repository.search_tasks("乳").unwrap().is_empty());
    }

    #[test]
    fn v3_database_migrates_to_v4_and_backfills_tasks_fts() {
        let file = NamedTempFile::new().unwrap();
        create_v3_database(file.path(), &KEY);
        let mut task = sample_task();
        task.title = "Legacy searchable task".to_string();
        task.note = "Backfill target".to_string();
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteTaskRepository::new(connection);

        assert_eq!(
            read_user_version(repository.connection()).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(repository.search_tasks("backfill").unwrap(), vec![task]);
    }

    #[test]
    fn fts5_search_works_after_reopening_encrypted_database() {
        let file = NamedTempFile::new().unwrap();
        let mut task = sample_task();
        task.title = "Encrypted search".to_string();
        task.note = "SQLCipher FTS5".to_string();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut repository = SqliteTaskRepository::new(connection);
            repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteTaskRepository::new(connection);

        assert_eq!(repository.search_tasks("sqlcipher").unwrap(), vec![task]);
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
        assert_eq!(
            is_default_column(&connection),
            Some(("INTEGER".to_string(), 1, "0".to_string()))
        );
        assert_eq!(
            setting_column(&connection, "key"),
            Some(("TEXT".to_string(), 0))
        );
        assert_eq!(
            setting_column(&connection, "value"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            setting_column(&connection, "updated_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "task_id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "remind_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "snoozed_until"),
            Some(("INTEGER".to_string(), 0))
        );
    }

    #[test]
    fn v1_database_migrates_to_latest_and_preserves_existing_data() {
        let file = NamedTempFile::new().unwrap();
        create_baseline_v1_database(file.path(), &KEY, true);

        let mut list = sample_list("a0");
        list.is_default = true;
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
            is_default_column(&connection),
            Some(("INTEGER".to_string(), 1, "0".to_string()))
        );
        assert_eq!(
            setting_column(&connection, "value"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "created_at"),
            Some(("INTEGER".to_string(), 1))
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

        let mut list = sample_list("legacy");
        list.is_default = true;
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
            is_default_column(&connection),
            Some(("INTEGER".to_string(), 1, "0".to_string()))
        );
        assert_eq!(
            setting_column(&connection, "updated_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "task_id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            SqliteListRepository::new(connection).get(list.id).unwrap(),
            list
        );
    }

    #[test]
    fn sqlite_settings_repository_returns_none_for_missing_key() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let repository = SqliteSettingsRepository::new(connection);

        assert_eq!(repository.get_setting("ui_mode").unwrap(), None);
    }

    #[test]
    fn sqlite_settings_repository_roundtrips_setting() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSettingsRepository::new(connection);

        repository
            .set_setting("ui_mode", "simple", 1_799_000_000_000)
            .unwrap();

        assert_eq!(
            repository.get_setting("ui_mode").unwrap(),
            Some("simple".to_string())
        );
    }

    #[test]
    fn sqlite_settings_repository_overwrites_existing_setting() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteSettingsRepository::new(connection);

        repository
            .set_setting("ui_mode", "simple", 1_799_000_000_000)
            .unwrap();
        repository
            .set_setting("ui_mode", "advanced", 1_799_000_001_000)
            .unwrap();

        assert_eq!(
            repository.get_setting("ui_mode").unwrap(),
            Some("advanced".to_string())
        );
        let updated_at: i64 = repository
            .connection()
            .query_row(
                "SELECT updated_at FROM settings WHERE key = ?1",
                ["ui_mode"],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(updated_at, 1_799_000_001_000);
    }

    #[test]
    fn sqlite_reminder_repository_sets_lists_clears_and_snoozes_reminders() {
        let file = NamedTempFile::new().unwrap();
        let task = sample_task();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteReminderRepository::new(connection);

        let first = repository
            .set_task_reminder(task.id, 1_800_000_000_000, 1_799_000_000_000)
            .unwrap();
        assert_eq!(first.task_id, task.id);
        assert_eq!(
            repository.list_task_reminders(task.id).unwrap(),
            vec![first.clone()]
        );

        let second = repository
            .set_task_reminder(task.id, 1_800_000_600_000, 1_799_000_001_000)
            .unwrap();
        assert_ne!(first.id, second.id);
        assert_eq!(
            repository.list_task_reminders(task.id).unwrap(),
            vec![second.clone()]
        );

        let snoozed = repository
            .snooze_reminder(second.id, 1_800_004_200_000)
            .unwrap();
        assert_eq!(snoozed.snoozed_until, Some(1_800_004_200_000));
        assert_eq!(
            repository.clear_task_reminders(task.id).unwrap(),
            vec![snoozed]
        );
        assert!(repository.list_task_reminders(task.id).unwrap().is_empty());
    }

    #[test]
    fn sqlite_reminder_repository_lists_pending_open_tasks_only() {
        let file = NamedTempFile::new().unwrap();
        let mut pending_task = sample_task();
        pending_task.status = TaskStatus::Todo;
        pending_task.sort_order = "a0".to_string();
        let mut closed_task = sample_task();
        closed_task.status = TaskStatus::Done;
        closed_task.completed_at = Some(1_799_000_010_000);
        closed_task.sort_order = "a1".to_string();
        let mut expired_task = sample_task();
        expired_task.status = TaskStatus::Todo;
        expired_task.sort_order = "a2".to_string();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(pending_task.clone()).unwrap();
            task_repository.insert(closed_task.clone()).unwrap();
            task_repository.insert(expired_task.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteReminderRepository::new(connection);
        let pending = repository
            .set_task_reminder(pending_task.id, 1_800_000_000_000, 1_799_000_000_000)
            .unwrap();
        repository
            .set_task_reminder(closed_task.id, 1_800_000_000_000, 1_799_000_000_000)
            .unwrap();
        repository
            .set_task_reminder(expired_task.id, 1_799_999_999_999, 1_799_000_000_000)
            .unwrap();

        assert_eq!(
            repository
                .list_pending_reminders(1_799_999_999_999)
                .unwrap(),
            vec![pending]
        );
    }

    #[test]
    fn sqlite_reminder_repository_lists_subtree_and_list_reminders_for_cancellation() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        let mut parent = sample_task();
        parent.list_id = list.id;
        parent.parent_task_id = None;
        parent.sort_order = "a0".to_string();
        let mut child = sample_task();
        child.list_id = list.id;
        child.parent_task_id = Some(parent.id);
        child.sort_order = "a1".to_string();
        let mut other = sample_task();
        other.list_id = list.id;
        other.parent_task_id = None;
        other.sort_order = "a2".to_string();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(parent.clone()).unwrap();
            task_repository.insert(child.clone()).unwrap();
            task_repository.insert(other.clone()).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteReminderRepository::new(connection);
        let parent_reminder = repository
            .set_task_reminder(parent.id, 1_800_000_000_000, 1_799_000_000_000)
            .unwrap();
        let child_reminder = repository
            .set_task_reminder(child.id, 1_800_000_600_000, 1_799_000_000_000)
            .unwrap();
        let other_reminder = repository
            .set_task_reminder(other.id, 1_800_001_200_000, 1_799_000_000_000)
            .unwrap();

        assert_eq!(
            repository.list_task_subtree_reminders(parent.id).unwrap(),
            vec![parent_reminder.clone(), child_reminder.clone()]
        );
        assert_eq!(
            repository.list_list_reminders(list.id).unwrap(),
            vec![parent_reminder, child_reminder, other_reminder]
        );
    }

    #[test]
    fn task_and_list_physical_deletes_remove_reminders() {
        let file = NamedTempFile::new().unwrap();
        let list = sample_list("a0");
        let mut subtree_task = sample_task();
        subtree_task.list_id = list.id;
        subtree_task.parent_task_id = None;
        subtree_task.sort_order = "a0".to_string();
        let mut list_task = sample_task();
        list_task.list_id = list.id;
        list_task.parent_task_id = None;
        list_task.sort_order = "a1".to_string();
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(list.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.insert(subtree_task.clone()).unwrap();
            task_repository.insert(list_task.clone()).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut reminder_repository = SqliteReminderRepository::new(connection);
            reminder_repository
                .set_task_reminder(subtree_task.id, 1_800_000_000_000, 1_799_000_000_000)
                .unwrap();
            reminder_repository
                .set_task_reminder(list_task.id, 1_800_000_600_000, 1_799_000_000_000)
                .unwrap();
        }

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut task_repository = SqliteTaskRepository::new(connection);
            task_repository.delete_subtree(subtree_task.id).unwrap();
        }
        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let reminder_repository = SqliteReminderRepository::new(connection);
            assert!(reminder_repository
                .list_task_reminders(subtree_task.id)
                .unwrap()
                .is_empty());
            assert_eq!(
                reminder_repository
                    .list_task_reminders(list_task.id)
                    .unwrap()
                    .len(),
                1
            );
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut list_repository = SqliteListRepository::new(connection);
        list_repository.delete_with_tasks(list.id).unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let reminder_repository = SqliteReminderRepository::new(connection);
        assert!(reminder_repository
            .list_list_reminders(list.id)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn v4_database_migrates_to_v5_and_adds_settings_table() {
        let file = NamedTempFile::new().unwrap();
        create_v4_database(file.path(), &KEY);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            setting_column(&connection, "key"),
            Some(("TEXT".to_string(), 0))
        );
        assert_eq!(
            setting_column(&connection, "value"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            setting_column(&connection, "updated_at"),
            Some(("INTEGER".to_string(), 1))
        );
    }

    #[test]
    fn v5_database_migrates_to_v6_and_adds_reminders_table() {
        let file = NamedTempFile::new().unwrap();
        create_v5_database(file.path(), &KEY);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            reminder_column(&connection, "id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "task_id"),
            Some(("TEXT".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "remind_at"),
            Some(("INTEGER".to_string(), 1))
        );
        assert_eq!(
            reminder_column(&connection, "snoozed_until"),
            Some(("INTEGER".to_string(), 0))
        );
        assert_eq!(
            reminder_column(&connection, "created_at"),
            Some(("INTEGER".to_string(), 1))
        );
    }

    #[test]
    fn v2_database_promotes_first_active_list_to_default() {
        let file = NamedTempFile::new().unwrap();
        create_v2_database(file.path(), &KEY);

        let archived = List {
            archived_at: Some(1_799_000_001_000),
            ..sample_list("a0")
        };
        let active_second = sample_list("b0");
        let mut active_first = sample_list("a1");
        active_first.created_at = active_second.created_at - 1;
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            insert_v2_list(&connection, &archived);
            insert_v2_list(&connection, &active_second);
            insert_v2_list(&connection, &active_first);
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(
            read_user_version(&connection).unwrap(),
            LATEST_SCHEMA_VERSION
        );
        assert_eq!(
            default_list_ids(&connection),
            vec![active_first.id.to_string()]
        );
    }

    #[test]
    fn v2_database_with_no_active_lists_does_not_promote_default() {
        let file = NamedTempFile::new().unwrap();
        create_v2_database(file.path(), &KEY);

        let archived = List {
            archived_at: Some(1_799_000_001_000),
            ..sample_list("a0")
        };
        {
            let connection = open_raw_encrypted(file.path(), &KEY);
            insert_v2_list(&connection, &archived);
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert!(default_list_ids(&connection).is_empty());
    }

    #[test]
    fn ensure_default_list_creates_default_when_missing_and_keeps_existing_name() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);

        let inbox = repository
            .ensure_default_list("Inbox".to_string(), 1_799_000_000_000)
            .unwrap();
        let again = repository
            .ensure_default_list("インボックス".to_string(), 1_799_000_001_000)
            .unwrap();

        assert_eq!(inbox.id, again.id);
        assert_eq!(again.name, "Inbox");
        assert!(again.is_default);
        assert_eq!(repository.list_all().unwrap().len(), 1);
    }

    #[test]
    fn ensure_default_list_observes_ja_name_in_empty_database() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);

        let inbox = repository
            .ensure_default_list("インボックス".to_string(), 1_799_000_000_000)
            .unwrap();

        assert_eq!(inbox.name, "インボックス");
        assert!(inbox.is_default);
    }

    #[test]
    fn unique_index_prevents_multiple_default_lists() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);
        let first = repository
            .ensure_default_list("Inbox".to_string(), 1_799_000_000_000)
            .unwrap();
        let mut second = sample_list("a1");
        second.is_default = true;

        let result = repository.insert(second);

        assert!(matches!(result, Err(StorageError::Sqlite(_))));
        assert_eq!(repository.get_default().unwrap().unwrap().id, first.id);
    }

    #[test]
    fn default_list_cannot_be_archived_or_deleted_but_can_be_renamed() {
        let file = NamedTempFile::new().unwrap();
        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut repository = SqliteListRepository::new(connection);
        let mut list = repository
            .ensure_default_list("Inbox".to_string(), 1_799_000_000_000)
            .unwrap();

        list.name = "Renamed inbox".to_string();
        list.updated_at += 1;
        repository.update(list.clone()).unwrap();
        assert_eq!(repository.get(list.id).unwrap().name, "Renamed inbox");
        assert!(repository.get(list.id).unwrap().is_default);

        let mut archived = list.clone();
        archived.archived_at = Some(1_799_000_001_000);
        assert!(matches!(
            repository.update(archived),
            Err(StorageError::DefaultListProtected {
                operation: "archived",
                list_id,
            }) if list_id == list.id
        ));
        assert!(matches!(
            repository.delete_with_tasks(list.id),
            Err(StorageError::DefaultListProtected {
                operation: "deleted",
                list_id,
            }) if list_id == list.id
        ));
    }

    #[test]
    fn latest_schema_reopen_does_not_reapply_migrations() {
        let file = NamedTempFile::new().unwrap();

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let before_schema_version = schema_version(&connection);
        let before_user_version = read_user_version(&connection).unwrap();
        let before_archived_at_count = count_archived_at_columns(&connection);
        let before_is_default_column = is_default_column(&connection);
        drop(connection);

        let connection = open_encrypted(file.path(), &KEY).unwrap();

        assert_eq!(read_user_version(&connection).unwrap(), before_user_version);
        assert_eq!(schema_version(&connection), before_schema_version);
        assert_eq!(
            count_archived_at_columns(&connection),
            before_archived_at_count
        );
        assert_eq!(is_default_column(&connection), before_is_default_column);
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
    fn list_home_filters_due_active_and_closed_tasks_across_active_lists() {
        let file = NamedTempFile::new().unwrap();
        let today_start = 1_800_000_000_000;
        let tomorrow_start = today_start + 86_400_000;
        let overdue = today_start - 86_400_000;
        let tomorrow = tomorrow_start + 1_000;
        let upcoming = tomorrow_start + 86_400_000 + 1_000;

        let inbox = new_list("Inbox".to_string(), "a0".to_string(), today_start).unwrap();
        let work = new_list("Work".to_string(), "a1".to_string(), today_start).unwrap();
        let mut archived = new_list("Archive".to_string(), "a2".to_string(), today_start).unwrap();
        archived.archived_at = Some(today_start + 1);

        let mut due_today = new_task(
            inbox.id,
            None,
            "Due today".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        due_today.due_at = Some(today_start);
        let no_due_child = new_task(
            inbox.id,
            Some(due_today.id),
            "No due child".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        let no_due_parent = new_task(
            inbox.id,
            None,
            "No due parent".to_string(),
            "a4".to_string(),
            today_start,
        )
        .unwrap();
        let mut due_child = new_task(
            inbox.id,
            Some(no_due_parent.id),
            "Due child".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        due_child.due_at = Some(today_start);
        let mut overdue_task = new_task(
            work.id,
            None,
            "Overdue".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        overdue_task.due_at = Some(overdue);
        let mut tomorrow_task = new_task(
            inbox.id,
            None,
            "Tomorrow".to_string(),
            "a1".to_string(),
            today_start,
        )
        .unwrap();
        tomorrow_task.due_at = Some(tomorrow);
        let mut upcoming_task = new_task(
            inbox.id,
            None,
            "Upcoming".to_string(),
            "a2".to_string(),
            today_start,
        )
        .unwrap();
        upcoming_task.due_at = Some(upcoming);
        let no_due = new_task(
            inbox.id,
            None,
            "No due".to_string(),
            "a3".to_string(),
            today_start,
        )
        .unwrap();
        let mut archived_task = new_task(
            archived.id,
            None,
            "Archived".to_string(),
            "a0".to_string(),
            today_start,
        )
        .unwrap();
        archived_task.due_at = Some(today_start);
        let mut closed_today = new_task(
            work.id,
            None,
            "Closed today".to_string(),
            "a1".to_string(),
            today_start,
        )
        .unwrap();
        closed_today.due_at = Some(today_start);
        closed_today =
            transition_task(closed_today, TaskStatus::Done, None, today_start + 1_000).unwrap();
        let mut closed_yesterday = new_task(
            work.id,
            None,
            "Closed yesterday".to_string(),
            "a2".to_string(),
            today_start,
        )
        .unwrap();
        closed_yesterday.due_at = Some(today_start);
        closed_yesterday = transition_task(
            closed_yesterday,
            TaskStatus::Done,
            None,
            today_start - 1_000,
        )
        .unwrap();
        let mut wont_do_today = new_task(
            work.id,
            None,
            "Wont do today".to_string(),
            "a3".to_string(),
            today_start,
        )
        .unwrap();
        wont_do_today.due_at = Some(today_start);
        wont_do_today = transition_task(
            wont_do_today,
            TaskStatus::WontDo,
            Some("not needed".to_string()),
            today_start + 2_000,
        )
        .unwrap();

        {
            let connection = open_encrypted(file.path(), &KEY).unwrap();
            let mut list_repository = SqliteListRepository::new(connection);
            list_repository.insert(inbox.clone()).unwrap();
            list_repository.insert(work.clone()).unwrap();
            list_repository.insert(archived).unwrap();
        }

        let connection = open_encrypted(file.path(), &KEY).unwrap();
        let mut task_repository = SqliteTaskRepository::new(connection);
        for task in [
            due_today,
            overdue_task,
            tomorrow_task,
            upcoming_task,
            no_due,
            archived_task,
            closed_today,
            closed_yesterday,
            wont_do_today,
            no_due_child,
            no_due_parent,
            due_child,
        ] {
            task_repository.insert(task).unwrap();
        }

        let home_tasks = task_repository
            .list_home(today_start, tomorrow_start)
            .unwrap();
        let titles = home_tasks
            .iter()
            .map(|entry| entry.task.title.as_str())
            .collect::<Vec<_>>();

        assert_eq!(
            titles,
            vec![
                "Overdue",
                "Due today",
                "Due child",
                "Closed today",
                "Wont do today",
                "Tomorrow",
                "Upcoming",
                "No due child",
                "No due parent"
            ]
        );
        assert!(
            home_tasks
                .iter()
                .find(|entry| entry.task.title == "Due today")
                .unwrap()
                .is_home_target
        );
        assert!(
            !home_tasks
                .iter()
                .find(|entry| entry.task.title == "No due child")
                .unwrap()
                .is_home_target
        );
        assert!(
            !home_tasks
                .iter()
                .find(|entry| entry.task.title == "No due parent")
                .unwrap()
                .is_home_target
        );
        assert!(
            home_tasks
                .iter()
                .find(|entry| entry.task.title == "Due child")
                .unwrap()
                .is_home_target
        );
        assert_eq!(
            home_tasks
                .iter()
                .find(|entry| entry.task.title == "Overdue")
                .unwrap()
                .list_name,
            "Work"
        );
        assert!(!titles.contains(&"No due"));
        assert!(!titles.contains(&"Archived"));
        assert!(!titles.contains(&"Closed yesterday"));
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

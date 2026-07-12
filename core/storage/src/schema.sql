CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY NOT NULL,
    list_id TEXT NOT NULL,
    parent_task_id TEXT,
    title TEXT NOT NULL,
    note TEXT NOT NULL,
    status TEXT NOT NULL,
    priority INTEGER NOT NULL,
    due_kind TEXT,
    due_on TEXT,
    due_at_ms INTEGER,
    due_time_zone TEXT,
    scheduled_at INTEGER,
    estimated_minutes INTEGER,
    sort_order TEXT NOT NULL,
    completed_at INTEGER,
    closed_reason TEXT,
    deleted_at INTEGER,
    assignee TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    CHECK (
        (due_kind IS NULL AND due_on IS NULL AND due_at_ms IS NULL AND due_time_zone IS NULL)
        OR (due_kind = 'date' AND due_on IS NOT NULL AND due_at_ms IS NULL AND due_time_zone IS NULL)
        OR (due_kind = 'datetime' AND due_on IS NULL AND due_at_ms IS NOT NULL AND due_time_zone IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS lists (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    color TEXT NOT NULL,
    icon TEXT NOT NULL,
    org_id TEXT,
    sort_order TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS task_undo_entries (
    id TEXT PRIMARY KEY NOT NULL,
    operation_type TEXT NOT NULL,
    task_id TEXT NOT NULL,
    list_id TEXT NOT NULL,
    before_snapshot TEXT NOT NULL,
    after_updated_at INTEGER NOT NULL,
    after_deleted_at INTEGER,
    after_completed_at INTEGER,
    created_at INTEGER NOT NULL,
    consumed_at INTEGER
);

CREATE TABLE IF NOT EXISTS reminders (
    id TEXT PRIMARY KEY NOT NULL,
    task_id TEXT NOT NULL,
    remind_at INTEGER NOT NULL,
    snoozed_until INTEGER,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_id TEXT NOT NULL,
    collection TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0,
    blob BLOB NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_cursors (
    name TEXT PRIMARY KEY NOT NULL,
    seq INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_record_states (
    record_id TEXT NOT NULL,
    collection TEXT NOT NULL,
    plaintext_json TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (collection, record_id)
);

CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id);
CREATE INDEX IF NOT EXISTS idx_tasks_list_sort_order ON tasks(list_id, sort_order, id);
CREATE INDEX IF NOT EXISTS idx_tasks_parent_task_id ON tasks(parent_task_id);
CREATE INDEX IF NOT EXISTS idx_tasks_deleted_at ON tasks(deleted_at);
CREATE INDEX IF NOT EXISTS idx_tasks_home_targets
    ON tasks(due_kind, due_on, due_at_ms, status, completed_at, list_id)
    WHERE due_kind IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lists_sort_order ON lists(sort_order);
CREATE INDEX IF NOT EXISTS idx_task_undo_entries_latest
    ON task_undo_entries(consumed_at, created_at);
CREATE INDEX IF NOT EXISTS idx_task_undo_entries_task_id
    ON task_undo_entries(task_id);
CREATE INDEX IF NOT EXISTS idx_reminders_task_id ON reminders(task_id);
CREATE INDEX IF NOT EXISTS idx_reminders_pending
    ON reminders(snoozed_until, remind_at);
CREATE INDEX IF NOT EXISTS idx_sync_outbox_stable_order
    ON sync_outbox(created_at, id);

CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
    title,
    note,
    content=''
);

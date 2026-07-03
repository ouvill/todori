CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY NOT NULL,
    list_id TEXT NOT NULL,
    parent_task_id TEXT,
    title TEXT NOT NULL,
    note TEXT NOT NULL,
    status TEXT NOT NULL,
    priority INTEGER NOT NULL,
    due_at INTEGER,
    scheduled_at INTEGER,
    estimated_minutes INTEGER,
    sort_order TEXT NOT NULL,
    completed_at INTEGER,
    closed_reason TEXT,
    deleted_at INTEGER,
    assignee TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
    title,
    note,
    content=''
);

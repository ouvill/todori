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

CREATE INDEX IF NOT EXISTS idx_tasks_list_id ON tasks(list_id);
CREATE INDEX IF NOT EXISTS idx_tasks_parent_task_id ON tasks(parent_task_id);
CREATE INDEX IF NOT EXISTS idx_tasks_deleted_at ON tasks(deleted_at);
CREATE INDEX IF NOT EXISTS idx_lists_sort_order ON lists(sort_order);

CREATE VIRTUAL TABLE IF NOT EXISTS tasks_fts USING fts5(
    title,
    note,
    content=''
);

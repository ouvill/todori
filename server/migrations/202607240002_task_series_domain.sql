-- Protocol v8 is a pre-release breaking reset for task/template recurrence
-- plaintext. Local schema v22 preserves ordinary tasks and reseeds them through
-- a fresh outbox, while legacy encrypted templates/schedules cannot be
-- transformed by the zero-knowledge server.
CREATE TABLE IF NOT EXISTS taskveil_schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$
DECLARE
    claimed BOOLEAN;
BEGIN
    INSERT INTO taskveil_schema_migrations (version)
    VALUES ('202607240002_task_series_domain')
    ON CONFLICT (version) DO NOTHING
    RETURNING TRUE INTO claimed;

    IF COALESCE(claimed, FALSE) THEN
        DELETE FROM sync_records_history
        WHERE collection IN ('tasks', 'templates', 'schedules');

        DELETE FROM sync_records
        WHERE collection IN ('tasks', 'templates', 'schedules');

        DELETE FROM device_resync_sessions;
    END IF;
END
$$;

ALTER TABLE sync_records
    DROP CONSTRAINT IF EXISTS sync_records_collection_check;
ALTER TABLE sync_records
    ADD CONSTRAINT sync_records_collection_check
    CHECK (collection IN ('lists', 'tasks', 'templates', 'task_series', 'timer_sessions'));

ALTER TABLE sync_records_history
    DROP CONSTRAINT IF EXISTS sync_records_history_collection_check;
ALTER TABLE sync_records_history
    ADD CONSTRAINT sync_records_history_collection_check
    CHECK (collection IN ('lists', 'tasks', 'templates', 'task_series', 'timer_sessions'));

ALTER TABLE device_resync_sessions
    DROP CONSTRAINT IF EXISTS device_resync_sessions_base_cursor_collection_check;
ALTER TABLE device_resync_sessions
    ADD CONSTRAINT device_resync_sessions_base_cursor_collection_check
    CHECK (
        base_cursor_collection IS NULL
        OR base_cursor_collection IN ('lists', 'tasks', 'templates', 'task_series', 'timer_sessions')
    );

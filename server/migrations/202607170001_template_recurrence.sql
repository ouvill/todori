ALTER TABLE sync_records
    DROP CONSTRAINT IF EXISTS sync_records_collection_check;
ALTER TABLE sync_records
    ADD CONSTRAINT sync_records_collection_check
    CHECK (collection IN ('lists', 'tasks', 'templates', 'schedules', 'timer_sessions'));

ALTER TABLE sync_records_history
    DROP CONSTRAINT IF EXISTS sync_records_history_collection_check;
ALTER TABLE sync_records_history
    ADD CONSTRAINT sync_records_history_collection_check
    CHECK (collection IN ('lists', 'tasks', 'templates', 'schedules', 'timer_sessions'));

ALTER TABLE device_resync_sessions
    DROP CONSTRAINT IF EXISTS device_resync_sessions_base_cursor_collection_check;
ALTER TABLE device_resync_sessions
    ADD CONSTRAINT device_resync_sessions_base_cursor_collection_check
    CHECK (
        base_cursor_collection IS NULL
        OR base_cursor_collection IN ('lists', 'tasks', 'templates', 'schedules', 'timer_sessions')
    );

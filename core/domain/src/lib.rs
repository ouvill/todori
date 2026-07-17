//! `todori-domain`: エンティティ・ユースケース（純粋ロジック）を提供する crate。
//!
//! 詳細な論理スキーマは `docs/03_技術仕様書.md` §3 データモデル を参照。

pub mod entities;
pub mod recurrence;
pub mod sort_order;
pub mod usecases;

pub use entities::{
    ActiveTimerSession, CivilDate, CompletedTimerSession, DueValueError, IanaTimeZone, List, Task,
    TaskDue, TaskStatus, TimerFinishKind, TimerMode, TimerPhase, TimerRunState, UtcInstant,
};
pub use recurrence::{
    calculate_streak, next_occurrence_after, occurrences_after, scheduled_task_id,
    validate_and_normalize_rrule, virtual_next_occurrence_after_end, RecurrenceError,
    RecurrenceProvenance, RecurrenceSchedule, RevisionBoundary, ScheduleCursor, Streak,
    StreakOccurrence, TaskTemplate, TemplateNode, TemplateSnapshot, MAX_TEMPLATE_NODES,
    MAX_TEMPLATE_SNAPSHOT_BYTES, SETTLEMENT_BATCH_SIZE, TEMPLATE_SNAPSHOT_SCHEMA_REVISION,
};
pub use sort_order::{
    fractional_index_after, fractional_index_between, rebalance_ranks, validate_sort_order,
    MAX_RANK, MIN_RANK,
};
pub use usecases::{
    archive_list, new_default_list, new_list, new_task, pomodoro_target_reached_at, rename_list,
    restored_active_duration_ms, transition_task, unarchive_list, update_due,
    update_estimated_minutes, update_note, update_priority, update_scheduled_at, update_title,
    validate_active_timer_session, validate_active_timer_update, validate_completed_timer_session,
    validate_parent, validate_parent_for, DomainError, MAX_TIMER_SESSION_DURATION_MS,
};
pub use uuid::Uuid;

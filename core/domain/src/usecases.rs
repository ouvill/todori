//! リスト・タスク操作の純粋ユースケース。
//!
//! ストレージやシステムクロックには依存せず、現在時刻は呼び出し側から
//! UTC epoch millisecondsとして注入する。

use std::collections::HashSet;

use thiserror::Error;
use uuid::Uuid;

use crate::entities::{
    ActiveTimerSession, CompletedTimerSession, List, Task, TaskDue, TaskStatus, TimerMode,
    TimerPhase, TimerRunState,
};

pub const MAX_TIMER_SESSION_DURATION_MS: i64 = 7 * 24 * 60 * 60 * 1_000;

/// domain crateのユースケースで発生する検証エラー。
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum DomainError {
    #[error("task title must not be empty")]
    EmptyTitle,
    #[error("task priority must be between 0 and 3")]
    InvalidPriority,
    #[error("estimated minutes must be a positive multiple of 5")]
    InvalidEstimatedMinutes,
    #[error("list name must not be empty")]
    EmptyName,
    #[error("invalid task status transition")]
    InvalidTransition,
    #[error("task cannot be its own parent")]
    SelfReferenceParent,
    #[error("parent task was not found")]
    ParentNotFound,
    #[error("parent task belongs to a different list")]
    ParentInDifferentList,
    #[error("parent task would create a cycle")]
    CyclicParent,
    #[error("invalid sort order")]
    InvalidSortOrder,
    #[error("invalid sort order boundary")]
    InvalidSortOrderBoundary,
    #[error("sort order space is exhausted")]
    SortOrderSpaceExhausted,
    #[error("work timer phase requires a task and break phases must not reference a task")]
    InvalidTimerTaskLink,
    #[error("stopwatch mode supports only the work phase")]
    InvalidTimerModePhase,
    #[error("running timer requires last_resumed_at and paused timer must not retain it")]
    InvalidTimerRunState,
    #[error("timer timestamps are inconsistent")]
    InvalidTimerTimestamps,
    #[error("timer duration is outside the allowed range")]
    InvalidTimerDuration,
    #[error("timer duration arithmetic overflowed")]
    TimerDurationOverflow,
}

/// Active Timerの永続値がADR-018の復元契約を満たすか検証する。
pub fn validate_active_timer_session(session: &ActiveTimerSession) -> Result<(), DomainError> {
    if session.mode == TimerMode::Stopwatch && session.phase != TimerPhase::Work {
        return Err(DomainError::InvalidTimerModePhase);
    }
    let task_link_is_valid = match session.phase {
        TimerPhase::Work => session.task_id.is_some(),
        TimerPhase::ShortBreak | TimerPhase::LongBreak => session.task_id.is_none(),
    };
    if !task_link_is_valid {
        return Err(DomainError::InvalidTimerTaskLink);
    }
    match (session.state, session.last_resumed_at) {
        (TimerRunState::Running, Some(last_resumed_at)) => {
            if last_resumed_at < session.started_at {
                return Err(DomainError::InvalidTimerTimestamps);
            }
        }
        (TimerRunState::Paused, None) => {}
        (TimerRunState::Running, None) | (TimerRunState::Paused, Some(_)) => {
            return Err(DomainError::InvalidTimerRunState);
        }
    }
    if !(0..=MAX_TIMER_SESSION_DURATION_MS).contains(&session.accumulated_active_ms)
        || session
            .target_duration_ms
            .is_some_and(|duration| !(1..=MAX_TIMER_SESSION_DURATION_MS).contains(&duration))
    {
        return Err(DomainError::InvalidTimerDuration);
    }
    Ok(())
}

/// Wall clockからActive Timerのpauseを除く復元時間を計算する。
///
/// 時計が逆行した区間は0へclampする。paused stateは保存済み累積値だけを返す。
pub fn restored_active_duration_ms(
    session: &ActiveTimerSession,
    now_wall_ms: i64,
) -> Result<i64, DomainError> {
    validate_active_timer_session(session)?;
    let duration = match session.state {
        TimerRunState::Paused => session.accumulated_active_ms,
        TimerRunState::Running => {
            let last_resumed_at = session
                .last_resumed_at
                .ok_or(DomainError::InvalidTimerRunState)?;
            let active_span = now_wall_ms.saturating_sub(last_resumed_at).max(0);
            session
                .accumulated_active_ms
                .checked_add(active_span)
                .ok_or(DomainError::TimerDurationOverflow)?
        }
    };
    if duration > MAX_TIMER_SESSION_DURATION_MS {
        return Err(DomainError::InvalidTimerDuration);
    }
    Ok(duration)
}

/// 同期対象のimmutable work実績を厳密検証する。
pub fn validate_completed_timer_session(
    session: &CompletedTimerSession,
) -> Result<(), DomainError> {
    let elapsed = session
        .ended_at
        .checked_sub(session.started_at)
        .ok_or(DomainError::InvalidTimerTimestamps)?;
    if elapsed < 0 || session.created_at < session.ended_at {
        return Err(DomainError::InvalidTimerTimestamps);
    }
    if elapsed > MAX_TIMER_SESSION_DURATION_MS
        || session.active_duration_ms <= 0
        || session.active_duration_ms > elapsed
    {
        return Err(DomainError::InvalidTimerDuration);
    }
    Ok(())
}

/// タスクを作成する。
pub fn new_task(
    list_id: Uuid,
    parent_task_id: Option<Uuid>,
    title: String,
    sort_order: String,
    now_ms: i64,
) -> Result<Task, DomainError> {
    validate_title(&title)?;

    Ok(Task {
        id: Uuid::now_v7(),
        list_id,
        parent_task_id,
        title,
        note: String::new(),
        status: TaskStatus::Todo,
        priority: 0,
        due: None,
        scheduled_at: None,
        estimated_minutes: None,
        sort_order,
        completed_at: None,
        closed_reason: None,
        deleted_at: None,
        assignee: None,
        created_at: now_ms,
        updated_at: now_ms,
    })
}

/// リストを作成する。
pub fn new_list(name: String, sort_order: String, now_ms: i64) -> Result<List, DomainError> {
    new_list_with_default(name, sort_order, false, now_ms)
}

/// 既定リストを作成する。
pub fn new_default_list(
    name: String,
    sort_order: String,
    now_ms: i64,
) -> Result<List, DomainError> {
    new_list_with_default(name, sort_order, true, now_ms)
}

fn new_list_with_default(
    name: String,
    sort_order: String,
    is_default: bool,
    now_ms: i64,
) -> Result<List, DomainError> {
    validate_name(&name)?;

    Ok(List {
        id: Uuid::now_v7(),
        name,
        color: "#4F8EF7".to_string(),
        icon: "list".to_string(),
        org_id: None,
        sort_order,
        is_default,
        archived_at: None,
        created_at: now_ms,
        updated_at: now_ms,
    })
}

/// タスクタイトルを更新する。
pub fn update_title(mut task: Task, title: String, now_ms: i64) -> Result<Task, DomainError> {
    validate_title(&title)?;

    task.title = title;
    task.updated_at = now_ms;
    Ok(task)
}

/// タスクノートを更新する。
pub fn update_note(mut task: Task, note: String, now_ms: i64) -> Result<Task, DomainError> {
    task.note = note;
    task.updated_at = now_ms;
    Ok(task)
}

/// タスク優先度を更新する。
pub fn update_priority(mut task: Task, priority: i32, now_ms: i64) -> Result<Task, DomainError> {
    if !(0..=3).contains(&priority) {
        return Err(DomainError::InvalidPriority);
    }
    task.priority = priority;
    task.updated_at = now_ms;
    Ok(task)
}

/// タスク期限を日付のみまたは日時指定としてatomicに更新する。
pub fn update_due(mut task: Task, due: Option<TaskDue>, now_ms: i64) -> Result<Task, DomainError> {
    task.due = due;
    task.updated_at = now_ms;
    Ok(task)
}

/// タスク作業予定日時を更新する。
pub fn update_scheduled_at(
    mut task: Task,
    scheduled_at: Option<i64>,
    now_ms: i64,
) -> Result<Task, DomainError> {
    task.scheduled_at = scheduled_at;
    task.updated_at = now_ms;
    Ok(task)
}

/// タスク見積り所要時間を更新する。
pub fn update_estimated_minutes(
    mut task: Task,
    estimated_minutes: Option<i32>,
    now_ms: i64,
) -> Result<Task, DomainError> {
    if estimated_minutes.is_some_and(|minutes| minutes <= 0 || minutes % 5 != 0) {
        return Err(DomainError::InvalidEstimatedMinutes);
    }
    task.estimated_minutes = estimated_minutes;
    task.updated_at = now_ms;
    Ok(task)
}

/// タスクのステータスを遷移させる。
pub fn transition_task(
    mut task: Task,
    next: TaskStatus,
    closed_reason: Option<String>,
    now_ms: i64,
) -> Result<Task, DomainError> {
    if !task.status.can_transition_to(&next) {
        return Err(DomainError::InvalidTransition);
    }

    match next {
        TaskStatus::Done => {
            task.completed_at = Some(now_ms);
            task.closed_reason = None;
        }
        TaskStatus::WontDo => {
            task.completed_at = Some(now_ms);
            task.closed_reason = closed_reason;
        }
        TaskStatus::Todo => {
            task.completed_at = None;
            task.closed_reason = None;
        }
        TaskStatus::InProgress => {}
    }

    task.status = next;
    task.updated_at = now_ms;
    Ok(task)
}

/// リスト名を更新する。
pub fn rename_list(mut list: List, name: String, now_ms: i64) -> Result<List, DomainError> {
    validate_name(&name)?;

    list.name = name;
    list.updated_at = now_ms;
    Ok(list)
}

/// リストをアーカイブする。
///
/// 既にアーカイブ済みの場合は、呼び出し側のリトライを安全にするため冪等に成功させる。
pub fn archive_list(mut list: List, now_ms: i64) -> Result<List, DomainError> {
    if list.archived_at.is_none() {
        list.archived_at = Some(now_ms);
        list.updated_at = now_ms;
    }
    Ok(list)
}

/// アーカイブ済みリストを通常リストへ戻す。
///
/// アーカイブされていない場合は、呼び出し側のリトライを安全にするため冪等に成功させる。
pub fn unarchive_list(mut list: List, now_ms: i64) -> Result<List, DomainError> {
    if list.archived_at.is_some() {
        list.archived_at = None;
        list.updated_at = now_ms;
    }
    Ok(list)
}

/// 親候補が対象タスクの親として有効かを検証する。
pub fn validate_parent(
    task: &Task,
    candidate_parent_id: Uuid,
    tasks: &[Task],
) -> Result<(), DomainError> {
    validate_parent_for(task.id, task.list_id, candidate_parent_id, tasks)
}

/// 対象タスクIDとリストIDを分離して親候補を検証する。
pub fn validate_parent_for(
    task_id: Uuid,
    list_id: Uuid,
    candidate_parent_id: Uuid,
    tasks: &[Task],
) -> Result<(), DomainError> {
    if candidate_parent_id == task_id {
        return Err(DomainError::SelfReferenceParent);
    }

    let parent = find_task(tasks, candidate_parent_id)?;
    if parent.list_id != list_id {
        return Err(DomainError::ParentInDifferentList);
    }
    let mut visited = HashSet::new();
    let mut current = parent.parent_task_id;

    while let Some(current_id) = current {
        if current_id == task_id {
            return Err(DomainError::CyclicParent);
        }
        if !visited.insert(current_id) {
            return Err(DomainError::CyclicParent);
        }

        current = find_task(tasks, current_id)?.parent_task_id;
    }

    Ok(())
}

fn find_task(tasks: &[Task], task_id: Uuid) -> Result<&Task, DomainError> {
    tasks
        .iter()
        .find(|task| task.id == task_id)
        .ok_or(DomainError::ParentNotFound)
}

fn validate_title(title: &str) -> Result<(), DomainError> {
    // UI由来の空白だけの入力も実質的な未入力として扱う。
    if title.trim().is_empty() {
        return Err(DomainError::EmptyTitle);
    }
    Ok(())
}

fn validate_name(name: &str) -> Result<(), DomainError> {
    // UI由来の空白だけの入力も実質的な未入力として扱う。
    if name.trim().is_empty() {
        return Err(DomainError::EmptyName);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_700_000_000_000;
    const LATER: i64 = 1_700_000_001_000;

    fn task_fixture() -> Task {
        new_task(
            Uuid::now_v7(),
            None,
            "task".to_string(),
            "a0".to_string(),
            NOW,
        )
        .unwrap()
    }

    fn task_in_list(list_id: Uuid, title: &str) -> Task {
        new_task(list_id, None, title.to_string(), "a0".to_string(), NOW).unwrap()
    }

    fn active_timer(state: TimerRunState, phase: TimerPhase) -> ActiveTimerSession {
        ActiveTimerSession {
            session_id: Uuid::now_v7(),
            task_id: (phase == TimerPhase::Work).then(Uuid::now_v7),
            mode: crate::TimerMode::Pomodoro,
            phase,
            state,
            started_at: NOW,
            last_resumed_at: match state {
                TimerRunState::Running => Some(NOW + 1_000),
                TimerRunState::Paused => None,
            },
            accumulated_active_ms: 2_000,
            target_duration_ms: Some(25 * 60 * 1_000),
        }
    }

    fn completed_timer() -> CompletedTimerSession {
        CompletedTimerSession {
            id: Uuid::now_v7(),
            task_id: Uuid::now_v7(),
            mode: crate::TimerMode::Stopwatch,
            finish_kind: crate::TimerFinishKind::Completed,
            started_at: NOW,
            ended_at: NOW + 10_000,
            active_duration_ms: 8_000,
            created_at: NOW + 10_000,
        }
    }

    #[test]
    fn running_timer_restores_accumulated_and_current_wall_clock_span() {
        let timer = active_timer(TimerRunState::Running, TimerPhase::Work);

        assert_eq!(restored_active_duration_ms(&timer, NOW + 4_000), Ok(5_000));
    }

    #[test]
    fn running_timer_clamps_wall_clock_rollback_and_paused_ignores_now() {
        let running = active_timer(TimerRunState::Running, TimerPhase::Work);
        assert_eq!(restored_active_duration_ms(&running, NOW), Ok(2_000));

        let paused = active_timer(TimerRunState::Paused, TimerPhase::Work);
        assert_eq!(
            restored_active_duration_ms(&paused, NOW + MAX_TIMER_SESSION_DURATION_MS),
            Ok(2_000)
        );
    }

    #[test]
    fn active_timer_requires_task_only_for_work_and_bounded_durations() {
        let mut work = active_timer(TimerRunState::Running, TimerPhase::Work);
        work.task_id = None;
        assert_eq!(
            validate_active_timer_session(&work),
            Err(DomainError::InvalidTimerTaskLink)
        );

        let mut break_timer = active_timer(TimerRunState::Paused, TimerPhase::ShortBreak);
        break_timer.task_id = Some(Uuid::now_v7());
        assert_eq!(
            validate_active_timer_session(&break_timer),
            Err(DomainError::InvalidTimerTaskLink)
        );

        let mut invalid = active_timer(TimerRunState::Running, TimerPhase::LongBreak);
        invalid.accumulated_active_ms = MAX_TIMER_SESSION_DURATION_MS + 1;
        assert_eq!(
            validate_active_timer_session(&invalid),
            Err(DomainError::InvalidTimerDuration)
        );
    }

    #[test]
    fn stopwatch_rejects_break_phases_with_typed_error() {
        for phase in [TimerPhase::ShortBreak, TimerPhase::LongBreak] {
            let mut timer = active_timer(TimerRunState::Paused, phase);
            timer.mode = TimerMode::Stopwatch;
            assert_eq!(
                validate_active_timer_session(&timer),
                Err(DomainError::InvalidTimerModePhase)
            );
        }

        let mut work = active_timer(TimerRunState::Paused, TimerPhase::Work);
        work.mode = TimerMode::Stopwatch;
        assert_eq!(validate_active_timer_session(&work), Ok(()));
    }

    #[test]
    fn active_timer_requires_last_resumed_only_while_running() {
        let mut running = active_timer(TimerRunState::Running, TimerPhase::Work);
        running.last_resumed_at = None;
        assert_eq!(
            validate_active_timer_session(&running),
            Err(DomainError::InvalidTimerRunState)
        );

        let mut paused = active_timer(TimerRunState::Paused, TimerPhase::Work);
        paused.last_resumed_at = Some(NOW + 1_000);
        assert_eq!(
            validate_active_timer_session(&paused),
            Err(DomainError::InvalidTimerRunState)
        );
    }

    #[test]
    fn completed_timer_requires_positive_active_time_within_elapsed_and_seven_days() {
        let valid = completed_timer();
        assert_eq!(validate_completed_timer_session(&valid), Ok(()));

        for invalid_duration in [0, 10_001] {
            let mut invalid = valid.clone();
            invalid.active_duration_ms = invalid_duration;
            assert_eq!(
                validate_completed_timer_session(&invalid),
                Err(DomainError::InvalidTimerDuration)
            );
        }

        let mut reversed = valid.clone();
        reversed.ended_at = reversed.started_at - 1;
        assert_eq!(
            validate_completed_timer_session(&reversed),
            Err(DomainError::InvalidTimerTimestamps)
        );

        let mut created_before_end = valid.clone();
        created_before_end.created_at = created_before_end.ended_at - 1;
        assert_eq!(
            validate_completed_timer_session(&created_before_end),
            Err(DomainError::InvalidTimerTimestamps)
        );

        let mut too_long = valid;
        too_long.ended_at = too_long.started_at + MAX_TIMER_SESSION_DURATION_MS + 1;
        too_long.created_at = too_long.ended_at;
        assert_eq!(
            validate_completed_timer_session(&too_long),
            Err(DomainError::InvalidTimerDuration)
        );
    }

    #[test]
    fn new_task_sets_defaults() {
        let list_id = Uuid::now_v7();
        let task = new_task(list_id, None, "buy milk".to_string(), "a0".to_string(), NOW).unwrap();

        assert_eq!(task.list_id, list_id);
        assert_eq!(task.parent_task_id, None);
        assert_eq!(task.title, "buy milk");
        assert_eq!(task.note, "");
        assert_eq!(task.status, TaskStatus::Todo);
        assert_eq!(task.priority, 0);
        assert_eq!(task.due, None);
        assert_eq!(task.scheduled_at, None);
        assert_eq!(task.estimated_minutes, None);
        assert_eq!(task.sort_order, "a0");
        assert_eq!(task.completed_at, None);
        assert_eq!(task.closed_reason, None);
        assert_eq!(task.deleted_at, None);
        assert_eq!(task.assignee, None);
        assert_eq!(task.created_at, NOW);
        assert_eq!(task.updated_at, NOW);
    }

    #[test]
    fn new_task_rejects_empty_title() {
        assert_eq!(
            new_task(
                Uuid::now_v7(),
                None,
                "   ".to_string(),
                "a0".to_string(),
                NOW
            ),
            Err(DomainError::EmptyTitle)
        );
    }

    #[test]
    fn update_title_changes_title_and_updated_at() {
        let task = task_fixture();
        let updated = update_title(task, "updated".to_string(), LATER).unwrap();

        assert_eq!(updated.title, "updated");
        assert_eq!(updated.updated_at, LATER);
    }

    #[test]
    fn update_title_rejects_empty_title_without_changing_task() {
        let task = task_fixture();
        let result = update_title(task.clone(), "".to_string(), LATER);

        assert_eq!(result, Err(DomainError::EmptyTitle));
        assert_eq!(task.title, "task");
        assert_eq!(task.updated_at, NOW);
    }

    #[test]
    fn update_task_fields_change_values_and_updated_at() {
        let task = task_fixture();
        let task = update_note(task, "note".to_string(), LATER).unwrap();
        let task = update_priority(task, 3, LATER + 1).unwrap();
        let due = TaskDue::date_time(LATER + 2, "UTC").unwrap();
        let task = update_due(task, Some(due.clone()), LATER + 2).unwrap();
        let task = update_scheduled_at(task, Some(LATER + 3), LATER + 3).unwrap();
        let task = update_estimated_minutes(task, Some(45), LATER + 4).unwrap();

        assert_eq!(task.note, "note");
        assert_eq!(task.priority, 3);
        assert_eq!(task.due, Some(due));
        assert_eq!(task.scheduled_at, Some(LATER + 3));
        assert_eq!(task.estimated_minutes, Some(45));
        assert_eq!(task.updated_at, LATER + 4);
    }

    #[test]
    fn planning_attributes_reject_invalid_priority_and_estimate() {
        let task = task_fixture();
        assert_eq!(
            update_priority(task.clone(), -1, LATER).unwrap_err(),
            DomainError::InvalidPriority
        );
        assert_eq!(
            update_priority(task.clone(), 4, LATER).unwrap_err(),
            DomainError::InvalidPriority
        );
        for invalid in [0, -5, 1, 24, 26] {
            assert_eq!(
                update_estimated_minutes(task.clone(), Some(invalid), LATER).unwrap_err(),
                DomainError::InvalidEstimatedMinutes
            );
        }
        assert_eq!(
            update_estimated_minutes(task.clone(), None, LATER)
                .unwrap()
                .estimated_minutes,
            None
        );
        assert_eq!(
            update_estimated_minutes(task, Some(45), LATER)
                .unwrap()
                .estimated_minutes,
            Some(45)
        );
    }

    #[test]
    fn transition_rejects_invalid_transition() {
        let mut task = task_fixture();
        task.status = TaskStatus::Done;

        assert_eq!(
            transition_task(task, TaskStatus::WontDo, None, LATER),
            Err(DomainError::InvalidTransition)
        );
    }

    #[test]
    fn transition_to_done_sets_completed_at_and_clears_closed_reason() {
        let task = task_fixture();
        let updated =
            transition_task(task, TaskStatus::Done, Some("ignored".to_string()), LATER).unwrap();

        assert_eq!(updated.status, TaskStatus::Done);
        assert_eq!(updated.completed_at, Some(LATER));
        assert_eq!(updated.closed_reason, None);
        assert_eq!(updated.updated_at, LATER);
    }

    #[test]
    fn transition_to_wont_do_sets_completed_at_and_keeps_closed_reason() {
        let task = task_fixture();
        let updated = transition_task(
            task,
            TaskStatus::WontDo,
            Some("not planned".to_string()),
            LATER,
        )
        .unwrap();

        assert_eq!(updated.status, TaskStatus::WontDo);
        assert_eq!(updated.completed_at, Some(LATER));
        assert_eq!(updated.closed_reason, Some("not planned".to_string()));
        assert_eq!(updated.updated_at, LATER);
    }

    #[test]
    fn reopen_to_todo_clears_completed_at_and_closed_reason() {
        let task = transition_task(task_fixture(), TaskStatus::Done, None, LATER).unwrap();
        let reopened = transition_task(task, TaskStatus::Todo, None, LATER + 1).unwrap();

        assert_eq!(reopened.status, TaskStatus::Todo);
        assert_eq!(reopened.completed_at, None);
        assert_eq!(reopened.closed_reason, None);
        assert_eq!(reopened.updated_at, LATER + 1);
    }

    #[test]
    fn transition_to_in_progress_keeps_completion_metadata() {
        let task = task_fixture();
        let updated = transition_task(task, TaskStatus::InProgress, None, LATER).unwrap();

        assert_eq!(updated.status, TaskStatus::InProgress);
        assert_eq!(updated.completed_at, None);
        assert_eq!(updated.closed_reason, None);
        assert_eq!(updated.updated_at, LATER);
    }

    #[test]
    fn new_list_sets_defaults() {
        let list = new_list("Inbox".to_string(), "a0".to_string(), NOW).unwrap();

        assert_eq!(list.name, "Inbox");
        assert_eq!(list.color, "#4F8EF7");
        assert_eq!(list.icon, "list");
        assert_eq!(list.org_id, None);
        assert_eq!(list.sort_order, "a0");
        assert!(!list.is_default);
        assert_eq!(list.archived_at, None);
        assert_eq!(list.created_at, NOW);
        assert_eq!(list.updated_at, NOW);
    }

    #[test]
    fn new_default_list_sets_is_default() {
        let list = new_default_list("Inbox".to_string(), "a0".to_string(), NOW).unwrap();

        assert_eq!(list.name, "Inbox");
        assert!(list.is_default);
        assert_eq!(list.archived_at, None);
    }

    #[test]
    fn new_list_rejects_empty_name() {
        assert_eq!(
            new_list(" ".to_string(), "a0".to_string(), NOW),
            Err(DomainError::EmptyName)
        );
    }

    #[test]
    fn rename_list_changes_name_and_updated_at() {
        let list = new_list("Inbox".to_string(), "a0".to_string(), NOW).unwrap();
        let updated = rename_list(list, "Work".to_string(), LATER).unwrap();

        assert_eq!(updated.name, "Work");
        assert_eq!(updated.updated_at, LATER);
    }

    #[test]
    fn rename_list_rejects_empty_name() {
        let list = new_list("Inbox".to_string(), "a0".to_string(), NOW).unwrap();

        assert_eq!(
            rename_list(list, "\t".to_string(), LATER),
            Err(DomainError::EmptyName)
        );
    }

    #[test]
    fn archive_list_sets_archived_at_and_updated_at() {
        let list = new_list("Work".to_string(), "a1".to_string(), NOW).unwrap();
        let archived = archive_list(list, LATER).unwrap();

        assert_eq!(archived.archived_at, Some(LATER));
        assert_eq!(archived.updated_at, LATER);
    }

    #[test]
    fn archive_list_is_idempotent_when_already_archived() {
        let list = new_list("Work".to_string(), "a1".to_string(), NOW).unwrap();
        let archived = archive_list(list, LATER).unwrap();
        let archived_again = archive_list(archived, LATER + 1).unwrap();

        assert_eq!(archived_again.archived_at, Some(LATER));
        assert_eq!(archived_again.updated_at, LATER);
    }

    #[test]
    fn unarchive_list_clears_archived_at_and_updates_updated_at() {
        let list = new_list("Work".to_string(), "a1".to_string(), NOW).unwrap();
        let archived = archive_list(list, LATER).unwrap();
        let unarchived = unarchive_list(archived, LATER + 1).unwrap();

        assert_eq!(unarchived.archived_at, None);
        assert_eq!(unarchived.updated_at, LATER + 1);
    }

    #[test]
    fn unarchive_list_is_idempotent_when_not_archived() {
        let list = new_list("Work".to_string(), "a1".to_string(), NOW).unwrap();
        let unarchived = unarchive_list(list, LATER).unwrap();

        assert_eq!(unarchived.archived_at, None);
        assert_eq!(unarchived.updated_at, NOW);
    }

    #[test]
    fn validate_parent_accepts_valid_parent() {
        let list_id = Uuid::now_v7();
        let parent = task_in_list(list_id, "parent");
        let child = task_in_list(list_id, "child");

        assert_eq!(validate_parent(&child, parent.id, &[parent]), Ok(()));
    }

    #[test]
    fn validate_parent_rejects_self_reference() {
        let task = task_fixture();

        assert_eq!(
            validate_parent(&task, task.id, &[task.clone()]),
            Err(DomainError::SelfReferenceParent)
        );
    }

    #[test]
    fn validate_parent_rejects_missing_parent() {
        let task = task_fixture();

        assert_eq!(
            validate_parent(&task, Uuid::now_v7(), &[]),
            Err(DomainError::ParentNotFound)
        );
    }

    #[test]
    fn validate_parent_rejects_parent_in_different_list() {
        let parent = task_fixture();
        let child = task_fixture();

        assert_eq!(
            validate_parent(&child, parent.id, &[parent]),
            Err(DomainError::ParentInDifferentList)
        );
    }

    #[test]
    fn validate_parent_ignores_legacy_deleted_at_parent() {
        let list_id = Uuid::now_v7();
        let mut parent = task_in_list(list_id, "parent");
        parent.deleted_at = Some(LATER);
        let child = task_in_list(list_id, "child");

        assert_eq!(validate_parent(&child, parent.id, &[parent]), Ok(()));
    }

    #[test]
    fn validate_parent_rejects_indirect_cycle() {
        let list_id = Uuid::now_v7();
        let mut a = task_in_list(list_id, "a");
        let mut b = task_in_list(list_id, "b");
        let mut c = task_in_list(list_id, "c");

        a.parent_task_id = Some(b.id);
        b.parent_task_id = Some(c.id);
        c.parent_task_id = Some(a.id);

        assert_eq!(
            validate_parent(&a, c.id, &[a.clone(), b, c]),
            Err(DomainError::CyclicParent)
        );
    }

    #[test]
    fn validate_parent_for_accepts_new_task_without_existing_task_row() {
        let list_id = Uuid::now_v7();
        let task_id = Uuid::now_v7();
        let parent = task_in_list(list_id, "parent");

        assert_eq!(
            validate_parent_for(task_id, list_id, parent.id, &[parent]),
            Ok(())
        );
    }
}

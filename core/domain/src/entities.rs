//! タスク・リストのエンティティ定義。
//!
//! フィールド構成は `docs/03_技術仕様書.md` §3.5 (lists) / §3.6 (tasks) に準拠する。
//! 日付のみの期限はcivil date、瞬間は検証済みUTC instantとして保持する。

use std::{fmt, str::FromStr};

use chrono::{DateTime, NaiveDate, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum DueValueError {
    #[error("invalid civil date: {0}")]
    InvalidCivilDate(String),
    #[error("invalid UTC instant milliseconds: {0}")]
    InvalidUtcInstant(i64),
    #[error("invalid IANA time zone: {0}")]
    InvalidIanaTimeZone(String),
}

/// Timezoneを持たないGregorian calendar上の日付。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct CivilDate(String);

impl CivilDate {
    pub fn parse(value: impl Into<String>) -> Result<Self, DueValueError> {
        let value = value.into();
        let parsed = NaiveDate::parse_from_str(&value, "%Y-%m-%d")
            .map_err(|_| DueValueError::InvalidCivilDate(value.clone()))?;
        if parsed.format("%Y-%m-%d").to_string() != value {
            return Err(DueValueError::InvalidCivilDate(value));
        }
        Ok(Self(value))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for CivilDate {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl FromStr for CivilDate {
    type Err = DueValueError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::parse(value)
    }
}

impl<'de> Deserialize<'de> for CivilDate {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(value).map_err(serde::de::Error::custom)
    }
}

/// UTC上の一意な瞬間。epoch millisecondsはstorage表現に限定する。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct UtcInstant(i64);

impl UtcInstant {
    pub fn from_millis(value: i64) -> Result<Self, DueValueError> {
        DateTime::<Utc>::from_timestamp_millis(value)
            .ok_or(DueValueError::InvalidUtcInstant(value))?;
        Ok(Self(value))
    }

    pub fn as_millis(self) -> i64 {
        self.0
    }
}

impl<'de> Deserialize<'de> for UtcInstant {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = i64::deserialize(deserializer)?;
        Self::from_millis(value).map_err(serde::de::Error::custom)
    }
}

/// IANA timezone databaseのcanonical identifier。
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize)]
#[serde(transparent)]
pub struct IanaTimeZone(String);

impl IanaTimeZone {
    pub fn parse(value: impl Into<String>) -> Result<Self, DueValueError> {
        let value = value.into();
        value
            .parse::<Tz>()
            .map_err(|_| DueValueError::InvalidIanaTimeZone(value.clone()))?;
        Ok(Self(value))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for IanaTimeZone {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl FromStr for IanaTimeZone {
    type Err = DueValueError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::parse(value)
    }
}

impl<'de> Deserialize<'de> for IanaTimeZone {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::parse(value).map_err(serde::de::Error::custom)
    }
}

/// タスク期限。日付のみと日時指定は同時に成立しない。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum TaskDue {
    Date {
        due_on: CivilDate,
    },
    DateTime {
        due_at: UtcInstant,
        time_zone: IanaTimeZone,
    },
}

impl TaskDue {
    pub fn date(value: impl Into<String>) -> Result<Self, DueValueError> {
        Ok(Self::Date {
            due_on: CivilDate::parse(value)?,
        })
    }

    pub fn date_time(due_at_ms: i64, time_zone: impl Into<String>) -> Result<Self, DueValueError> {
        Ok(Self::DateTime {
            due_at: UtcInstant::from_millis(due_at_ms)?,
            time_zone: IanaTimeZone::parse(time_zone)?,
        })
    }
}

/// タスクのステータス。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Todo,
    InProgress,
    Done,
    WontDo,
}

/// Timerの計測方式。task statusとは独立した端末ローカル/実績属性である。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimerMode {
    Pomodoro,
    Stopwatch,
}

/// Active Timerが現在計測している区間。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimerPhase {
    Work,
    ShortBreak,
    LongBreak,
}

/// Active Timerの端末ローカルな実行状態。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimerRunState {
    Running,
    Paused,
}

/// 同期するwork実績が通常完了か、明示保存された中断かを表す。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimerFinishKind {
    Completed,
    Interrupted,
}

/// 端末ローカルだけに保存する、1 device 1 activeのTimer状態。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActiveTimerSession {
    pub session_id: Uuid,
    pub task_id: Option<Uuid>,
    pub mode: TimerMode,
    pub phase: TimerPhase,
    pub state: TimerRunState,
    pub started_at: i64,
    pub last_resumed_at: Option<i64>,
    pub accumulated_active_ms: i64,
    pub target_duration_ms: Option<i64>,
}

/// 完了または明示保存した中断workを表すimmutableな同期実績。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CompletedTimerSession {
    pub id: Uuid,
    pub task_id: Uuid,
    pub mode: TimerMode,
    pub finish_kind: TimerFinishKind,
    pub started_at: i64,
    pub ended_at: i64,
    pub active_duration_ms: i64,
    pub created_at: i64,
}

impl TaskStatus {
    /// 現在のステータスから `next` への遷移が許可されるかどうかを判定する。
    ///
    /// 許可される遷移:
    /// - `Todo` -> `InProgress` / `Done` / `WontDo`
    /// - `InProgress` -> `Todo` / `Done` / `WontDo`
    /// - `Done` / `WontDo` -> `Todo` (再オープン)
    pub fn can_transition_to(&self, next: &TaskStatus) -> bool {
        use TaskStatus::*;
        match (self, next) {
            (a, b) if a == b => false,
            (Todo, InProgress) | (Todo, Done) | (Todo, WontDo) => true,
            (InProgress, Todo) | (InProgress, Done) | (InProgress, WontDo) => true,
            (Done, Todo) | (WontDo, Todo) => true,
            _ => false,
        }
    }
}

/// リストエンティティ（`docs/03_技術仕様書.md` §3.5）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct List {
    pub id: Uuid,
    /// 暗号化対象フィールド（§4.8）。復号後の平文をここに保持する想定。
    pub name: String,
    pub color: String,
    pub icon: String,
    /// fractional index。
    pub sort_order: String,
    pub is_default: bool,
    pub archived_at: Option<i64>,
    pub created_at: i64,
    pub updated_at: i64,
}

/// タスクエンティティ（`docs/03_技術仕様書.md` §3.6）。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub id: Uuid,
    pub list_id: Uuid,
    pub parent_task_id: Option<Uuid>,
    /// TaskとBlueprintNodeで共有する、実行状態を含まない内容値。
    #[serde(flatten)]
    pub content: crate::recurrence::TaskContent,
    pub status: TaskStatus,
    pub due: Option<TaskDue>,
    pub scheduled_at: Option<i64>,
    /// 同一階層内でのfractional index。
    pub sort_order: String,
    pub completed_at: Option<i64>,
    pub closed_reason: Option<String>,
    /// tombstoneを兼ねる論理削除日時。
    pub deleted_at: Option<i64>,
    pub assignee: Option<Uuid>,
    /// Task Series-generated occurrence provenance. Manual tasks keep this `None`.
    pub series_occurrence: Option<crate::recurrence::SeriesOccurrenceRef>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn todo_can_transition_to_in_progress_done_wont_do() {
        assert!(TaskStatus::Todo.can_transition_to(&TaskStatus::InProgress));
        assert!(TaskStatus::Todo.can_transition_to(&TaskStatus::Done));
        assert!(TaskStatus::Todo.can_transition_to(&TaskStatus::WontDo));
    }

    #[test]
    fn in_progress_can_transition_to_todo_done_wont_do() {
        assert!(TaskStatus::InProgress.can_transition_to(&TaskStatus::Todo));
        assert!(TaskStatus::InProgress.can_transition_to(&TaskStatus::Done));
        assert!(TaskStatus::InProgress.can_transition_to(&TaskStatus::WontDo));
    }

    #[test]
    fn done_and_wont_do_can_reopen_to_todo() {
        assert!(TaskStatus::Done.can_transition_to(&TaskStatus::Todo));
        assert!(TaskStatus::WontDo.can_transition_to(&TaskStatus::Todo));
    }

    #[test]
    fn done_and_wont_do_cannot_transition_to_each_other_or_in_progress() {
        assert!(!TaskStatus::Done.can_transition_to(&TaskStatus::WontDo));
        assert!(!TaskStatus::WontDo.can_transition_to(&TaskStatus::Done));
        assert!(!TaskStatus::Done.can_transition_to(&TaskStatus::InProgress));
        assert!(!TaskStatus::WontDo.can_transition_to(&TaskStatus::InProgress));
    }

    #[test]
    fn same_status_transition_is_rejected() {
        assert!(!TaskStatus::Todo.can_transition_to(&TaskStatus::Todo));
    }

    #[test]
    fn task_roundtrips_through_json() {
        let task = Task {
            id: Uuid::now_v7(),
            list_id: Uuid::now_v7(),
            parent_task_id: None,
            content: crate::recurrence::TaskContent {
                title: "牛乳を買う".to_string(),
                note: String::new(),
                priority: 0,
                estimated_minutes: None,
            },
            status: TaskStatus::Todo,
            due: None,
            scheduled_at: None,
            sort_order: "a0".to_string(),
            completed_at: None,
            closed_reason: None,
            deleted_at: None,
            assignee: None,
            series_occurrence: None,
            created_at: 0,
            updated_at: 0,
        };
        let json = serde_json::to_string(&task).unwrap();
        let restored: Task = serde_json::from_str(&json).unwrap();
        assert_eq!(task, restored);
    }

    #[test]
    fn due_values_validate_and_roundtrip_as_tagged_union() {
        let date = TaskDue::date("2026-07-12").unwrap();
        let date_time = TaskDue::date_time(1_783_798_200_000, "Asia/Tokyo").unwrap();

        assert_eq!(
            serde_json::from_str::<TaskDue>(&serde_json::to_string(&date).unwrap()).unwrap(),
            date
        );
        assert_eq!(
            serde_json::from_str::<TaskDue>(&serde_json::to_string(&date_time).unwrap()).unwrap(),
            date_time
        );
        assert!(TaskDue::date("2026-02-30").is_err());
        assert!(TaskDue::date_time(1_783_798_200_000, "JST").is_err());
        assert!(
            serde_json::from_str::<TaskDue>(r#"{"kind":"date","due_on":"2026-02-30"}"#).is_err()
        );
        assert!(serde_json::from_str::<TaskDue>(
            r#"{"kind":"date_time","due_at":1783798200000,"time_zone":"Unknown/Zone"}"#
        )
        .is_err());
    }
}

//! タスク・リストのエンティティ定義。
//!
//! フィールド構成は `docs/03_技術仕様書.md` §3.5 (lists) / §3.6 (tasks) に準拠する。
//! 時刻はすべて UTC epoch milliseconds (`i64`) で保持する。

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// タスクのステータス。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TaskStatus {
    Todo,
    InProgress,
    Done,
    WontDo,
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
    pub org_id: Option<Uuid>,
    /// fractional index。
    pub sort_order: String,
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
    /// 暗号化対象フィールド（§4.8）。
    pub title: String,
    pub note: String,
    pub status: TaskStatus,
    pub priority: i32,
    pub due_at: Option<i64>,
    pub scheduled_at: Option<i64>,
    pub estimated_minutes: Option<i32>,
    /// 同一階層内でのfractional index。
    pub sort_order: String,
    pub completed_at: Option<i64>,
    pub closed_reason: Option<String>,
    /// tombstoneを兼ねる論理削除日時。
    pub deleted_at: Option<i64>,
    pub assignee: Option<Uuid>,
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
            title: "牛乳を買う".to_string(),
            note: String::new(),
            status: TaskStatus::Todo,
            priority: 0,
            due_at: None,
            scheduled_at: None,
            estimated_minutes: None,
            sort_order: "a0".to_string(),
            completed_at: None,
            closed_reason: None,
            deleted_at: None,
            assignee: None,
            created_at: 0,
            updated_at: 0,
        };
        let json = serde_json::to_string(&task).unwrap();
        let restored: Task = serde_json::from_str(&json).unwrap();
        assert_eq!(task, restored);
    }
}

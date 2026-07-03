//! `todori-domain`: エンティティ・ユースケース（純粋ロジック）を提供する crate。
//!
//! 詳細な論理スキーマは `docs/03_技術仕様書.md` §3 データモデル を参照。

pub mod entities;
pub mod usecases;

pub use entities::{List, Task, TaskStatus};
pub use usecases::{
    delete_task, new_list, new_task, rename_list, restore_task, transition_task, update_due_at,
    update_estimated_minutes, update_note, update_priority, update_scheduled_at, update_title,
    validate_parent, validate_parent_for, DomainError,
};
pub use uuid::Uuid;

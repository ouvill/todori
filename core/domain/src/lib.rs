//! `todori-domain`: エンティティ・ユースケース（純粋ロジック）を提供する crate。
//!
//! 詳細な論理スキーマは `docs/03_技術仕様書.md` §3 データモデル を参照。

pub mod entities;
pub mod sort_order;
pub mod usecases;

pub use entities::{
    CivilDate, DueValueError, IanaTimeZone, List, Task, TaskDue, TaskStatus, UtcInstant,
};
pub use sort_order::{
    fractional_index_after, fractional_index_between, rebalance_ranks, validate_sort_order,
    MAX_RANK, MIN_RANK,
};
pub use usecases::{
    archive_list, new_default_list, new_list, new_task, rename_list, transition_task,
    unarchive_list, update_due, update_estimated_minutes, update_note, update_priority,
    update_scheduled_at, update_title, validate_parent, validate_parent_for, DomainError,
};
pub use uuid::Uuid;
